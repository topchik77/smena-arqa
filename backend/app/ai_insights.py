"""Optional, constrained AI prioritisation of already computed day facts.

Set both OPENAI_API_KEY and OPENAI_MODEL on the server to opt in. The model
must support Responses API structured outputs; no model or key is selected
implicitly. Only aggregate summary values and their trusted explanations leave
the server. Trip IDs, dates, timestamps and individual trips are never sent.

This synchronous entry point belongs in a synchronous FastAPI route. A private
event loop enforces a seven-second total network deadline (not just a per-read
timeout). No retries. Cache and concurrency limits are per server process;
multi-worker/public deployments need authentication and a shared spend limit.
"""

import asyncio
import hashlib
import json
import logging
import os
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass

import httpx

from .models import DayView, InsightsView

logger = logging.getLogger(__name__)
API_URL = "https://api.openai.com/v1/responses"
REQUEST_TIMEOUT_SECONDS = 7.0
WAIT_TIMEOUT_SECONDS = 8.0
CACHE_TTL_SECONDS = 300.0
FAILURE_TTL_SECONDS = 20.0
MAX_CACHE_ENTRIES = 64
MAX_CONCURRENT_REQUESTS = 2
MAX_OUTPUT_TOKENS = 256

UNAVAILABLE = "ИИ сейчас недоступен. Показан проверяемый разбор по формулам."
BUSY = "ИИ занят другим разбором. Показан проверяемый разбор по формулам."
AI_SCOPE = "ИИ выбрал и упорядочил факты. Все суммы и формулировки рассчитаны сервером."


@dataclass(frozen=True)
class _CacheEntry:
    expires_at: float
    selected_ids: tuple[str, ...] | None


_cache: OrderedDict[str, _CacheEntry] = OrderedDict()
_inflight: dict[str, threading.Event] = {}
_lock = threading.Lock()


def _local_fallback(local: InsightsView, explanation: str) -> InsightsView:
    return local.model_copy(update={"limitations": [*local.limitations, explanation]})


def _render(local: InsightsView, candidates: dict[str, str], entry: _CacheEntry) -> InsightsView:
    if entry.selected_ids is None:
        return _local_fallback(local, UNAVAILABLE)
    return local.model_copy(
        update={
            "source": "ai",
            "title": "Главное за день",
            "facts": [candidates[item] for item in entry.selected_ids],
            "limitations": [*local.limitations, AI_SCOPE],
        }
    )


def _request_payload(model: str, summary: dict, candidates: dict[str, str]) -> dict:
    return {
        "model": model,
        "store": False,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "instructions": (
            "Choose and order 1 to 3 distinct candidate IDs most useful for a driver reviewing a day. "
            "Use only the supplied aggregate summary and the already verified candidate statements. "
            "Prioritise material commission and payment composition. "
            "Use trip duration only when helpful. "
            "Do not calculate, write explanations or infer causes. "
            "Do not predict earnings or recommend working hours. "
            "Return only selected_ids. No tools or external information are available."
        ),
        "input": json.dumps({"summary": summary, "candidates": candidates}, ensure_ascii=False),
        "text": {
            "format": {
                "type": "json_schema",
                "name": "day_fact_selection",
                "strict": True,
                "schema": {
                    "type": "object",
                    "properties": {
                        "selected_ids": {
                            "type": "array",
                            "items": {"type": "string", "enum": list(candidates)},
                            "minItems": 1,
                            "maxItems": 3,
                        }
                    },
                    "required": ["selected_ids"],
                    "additionalProperties": False,
                },
            }
        },
    }


def _parse_selection(response: object, candidates: dict[str, str]) -> tuple[str, ...]:
    """Validate provider content independently, even with strict structured output."""
    if not isinstance(response, dict) or response.get("status") != "completed":
        raise ValueError("AI response was not completed")
    output = response.get("output")
    if not isinstance(output, list):
        raise ValueError("Missing response output")
    texts: list[str] = []
    for item in output:
        if not isinstance(item, dict):
            raise ValueError("Invalid output item")
        if item.get("type") != "message":
            continue
        content = item.get("content")
        if not isinstance(content, list):
            raise ValueError("Invalid message content")
        for part in content:
            if not isinstance(part, dict) or part.get("type") != "output_text":
                raise ValueError("Refused or unsupported response content")
            text = part.get("text")
            if not isinstance(text, str) or len(text) > 4096:
                raise ValueError("Invalid response text")
            texts.append(text)
    if len(texts) != 1:
        raise ValueError("Expected one structured result")
    selection = json.loads(texts[0])
    if not isinstance(selection, dict) or set(selection) != {"selected_ids"}:
        raise ValueError("Unexpected result shape")
    ids = selection["selected_ids"]
    if not isinstance(ids, list) or not 1 <= len(ids) <= 3:
        raise ValueError("Expected one to three IDs")
    if any(not isinstance(item, str) or item not in candidates for item in ids):
        raise ValueError("Unknown insight ID")
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate insight IDs")
    return tuple(ids)


async def _select_facts(api_key: str, payload: dict, candidates: dict[str, str]) -> tuple[str, ...]:
    async with asyncio.timeout(REQUEST_TIMEOUT_SECONDS):
        # HTTPX performs no request retries by default and does not follow redirects.
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT_SECONDS, follow_redirects=False) as client:
            response = await client.post(
                API_URL,
                headers={"Authorization": f"Bearer {api_key}"},
                json=payload,
            )
            response.raise_for_status()
            return _parse_selection(response.json(), candidates)


def explain_with_optional_ai(day: DayView, local: InsightsView) -> InsightsView:
    """Keep the local result unless an explicitly enabled provider returns valid IDs."""
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    model = os.getenv("OPENAI_MODEL", "").strip()
    if not api_key or not model or not day.summary.trip_count or not local.facts:
        return local

    summary = day.summary.model_dump(mode="json")
    candidates = {f"fact_{index + 1}": fact for index, fact in enumerate(local.facts)}
    payload = _request_payload(model, summary, candidates)
    # Facts participate in the key so wording changes cannot render a stale mapping.
    cache_key = hashlib.sha256(
        json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
    ).hexdigest()

    with _lock:
        now = time.monotonic()
        for expired_key in [key for key, value in _cache.items() if value.expires_at <= now]:
            del _cache[expired_key]
        cached = _cache.get(cache_key)
        if cached is not None:
            _cache.move_to_end(cache_key)
            return _render(local, candidates, cached)
        waiting = _inflight.get(cache_key)
        if waiting is None:
            if len(_inflight) >= MAX_CONCURRENT_REQUESTS:
                return _local_fallback(local, BUSY)
            waiting = threading.Event()
            _inflight[cache_key] = waiting
            owner = True
        else:
            owner = False

    if not owner:
        waiting.wait(timeout=WAIT_TIMEOUT_SECONDS)
        with _lock:
            cached = _cache.get(cache_key)
        return _render(local, candidates, cached) if cached else _local_fallback(local, BUSY)

    selected_ids = None
    try:
        selected_ids = asyncio.run(_select_facts(api_key, payload, candidates))
    except (httpx.HTTPError, TimeoutError, ValueError, TypeError) as exc:
        # Log only the class: provider response text may contain request data.
        logger.warning("Optional AI unavailable: %s", type(exc).__name__)
    finally:
        ttl = CACHE_TTL_SECONDS if selected_ids is not None else FAILURE_TTL_SECONDS
        entry = _CacheEntry(time.monotonic() + ttl, selected_ids)
        with _lock:
            _cache[cache_key] = entry
            _cache.move_to_end(cache_key)
            while len(_cache) > MAX_CACHE_ENTRIES:
                _cache.popitem(last=False)
            _inflight.pop(cache_key, None)
            waiting.set()
    return _render(local, candidates, entry)
