"""No paid network calls: every enabled-provider test uses an HTTPX MockTransport."""

import asyncio
import json
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date

import httpx
import pytest

from app import ai_insights as ai
from app.insights import explain_day
from app.models import DayView, Summary

REAL_ASYNC_CLIENT = httpx.AsyncClient


@pytest.fixture(autouse=True)
def clean_ai_state(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_MODEL", raising=False)
    with ai._lock:
        ai._cache.clear()
        ai._inflight.clear()
    yield
    with ai._lock:
        ai._cache.clear()
        ai._inflight.clear()


@pytest.fixture
def day():
    return DayView(
        date=date(2026, 10, 1),
        trips=[],
        summary=Summary(
            trip_count=2,
            revenue="3900.00",
            commission="585.00",
            net="3315.00",
            cash="1500.00",
            card="2400.00",
            trip_minutes=35,
        ),
    )


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "test-key-never-sent-to-network")
    monkeypatch.setenv("OPENAI_MODEL", "test-structured-model")

    def install(handler):
        transport = httpx.MockTransport(handler)
        monkeypatch.setattr(
            ai.httpx,
            "AsyncClient",
            lambda **kwargs: REAL_ASYNC_CLIENT(transport=transport, **kwargs),
        )

    return install


def provider_result(selection=None, *, status="completed"):
    return {
        "status": status,
        "output": [
            {
                "type": "message",
                "content": [
                    {
                        "type": "output_text",
                        "text": json.dumps(selection or {"selected_ids": ["fact_3", "fact_2"]}),
                    }
                ],
            }
        ],
    }


def test_unconfigured_provider_returns_same_local_object(day, monkeypatch):
    async def forbidden(*args, **kwargs):
        pytest.fail("Provider must not be called without both settings")

    monkeypatch.setattr(ai, "_select_facts", forbidden)
    local = explain_day(day)
    assert ai.explain_with_optional_ai(day, local) is local
    monkeypatch.setenv("OPENAI_API_KEY", "only-key")
    assert ai.explain_with_optional_ai(day, local) is local
    monkeypatch.delenv("OPENAI_API_KEY")
    monkeypatch.setenv("OPENAI_MODEL", "only-model")
    assert ai.explain_with_optional_ai(day, local) is local


def test_empty_day_never_calls_provider(day, configured):
    configured(lambda request: pytest.fail("Empty days do not need a paid request"))
    day.summary = day.summary.model_copy(update={"trip_count": 0})
    local = explain_day(day)
    assert ai.explain_with_optional_ai(day, local) is local


def test_valid_selection_uses_exact_server_facts_and_only_aggregate_input(day, configured):
    sent = []

    def handler(request):
        sent.append(request)
        return httpx.Response(200, json=provider_result())

    configured(handler)
    local = explain_day(day)
    result = ai.explain_with_optional_ai(day, local)
    assert result.source == "ai"
    assert result.facts == [local.facts[2], local.facts[1]]
    assert result.text == local.text
    assert ai.AI_SCOPE in result.limitations
    assert local.source == "local"  # The deterministic baseline is not mutated.
    assert len(local.facts) == 3
    assert len(sent) == 1
    request = sent[0]
    assert str(request.url) == ai.API_URL
    payload = json.loads(request.content)
    assert payload["store"] is False
    assert payload["max_output_tokens"] == 256
    assert payload["model"] == "test-structured-model"
    assert payload["text"]["format"]["strict"] is True
    data = json.loads(payload["input"])
    assert set(data) == {"summary", "candidates"}
    assert data["summary"] == day.summary.model_dump(mode="json")
    assert "trips" not in payload["input"]
    assert "2026-10-01" not in payload["input"]
    assert "start" not in payload["input"]
    assert "end" not in payload["input"]


@pytest.mark.parametrize(
    "selection",
    [
        {"selected_ids": []},
        {"selected_ids": ["fact_1", "fact_2", "fact_3", "fact_4"]},
        {"selected_ids": ["fact_1", "fact_1"]},
        {"selected_ids": ["work_tomorrow_at_08"]},
        {"selected_ids": ["fact_1"], "advice": "Earn 100000 tomorrow"},
        {"selected_ids": "fact_1"},
        {"selected_ids": [1]},
        {"selected_ids": [{"id": "fact_1"}]},
        ["fact_1"],
    ],
)
def test_invalid_selection_falls_back_without_model_text(day, configured, selection):
    configured(lambda request: httpx.Response(200, json=provider_result(selection)))
    local = explain_day(day)
    result = ai.explain_with_optional_ai(day, local)
    assert result.source == "local"
    assert result.text == local.text
    assert result.facts == local.facts
    assert ai.UNAVAILABLE in result.limitations
    assert "Earn 100000" not in result.model_dump_json()


@pytest.mark.parametrize(
    "body",
    [
        provider_result(status="incomplete"),
        {"status": "completed", "output": [{"type": "message", "content": [{"type": "refusal"}]}]},
        {"status": "completed", "output": []},
        {"status": "completed", "output": None},
        {"status": "completed", "output": [None]},
        [],
    ],
)
def test_refusal_incomplete_or_malformed_response_falls_back(day, configured, body):
    configured(lambda request: httpx.Response(200, json=body))
    result = ai.explain_with_optional_ai(day, explain_day(day))
    assert result.source == "local"
    assert ai.UNAVAILABLE in result.limitations


def test_provider_failure_is_not_retried_and_is_briefly_cached(day, configured):
    attempts = []

    def fail(request):
        attempts.append(request)
        return httpx.Response(429, json={"error": "rate limit"})

    configured(fail)
    local = explain_day(day)
    assert ai.explain_with_optional_ai(day, local).source == "local"
    assert ai.explain_with_optional_ai(day, local).source == "local"
    assert len(attempts) == 1


def test_real_total_deadline_and_inflight_cleanup(day, configured, monkeypatch):
    attempts = []

    async def delayed(request):
        attempts.append(request)
        await asyncio.sleep(0.2)
        return httpx.Response(200, json=provider_result())

    configured(delayed)
    monkeypatch.setattr(ai, "REQUEST_TIMEOUT_SECONDS", 0.01)
    assert ai.explain_with_optional_ai(day, explain_day(day)).source == "local"
    assert len(attempts) == 1
    assert not ai._inflight


def test_cache_reuses_result_but_summary_and_model_changes_invalidate(day, configured, monkeypatch):
    attempts = []

    def handler(request):
        attempts.append(request)
        return httpx.Response(200, json=provider_result())

    configured(handler)
    local = explain_day(day)
    first = ai.explain_with_optional_ai(day, local)
    second = ai.explain_with_optional_ai(day, local)
    assert first == second
    assert len(attempts) == 1
    day.summary = day.summary.model_copy(update={"trip_count": 3})
    ai.explain_with_optional_ai(day, explain_day(day))
    assert len(attempts) == 2
    monkeypatch.setenv("OPENAI_MODEL", "other-structured-model")
    ai.explain_with_optional_ai(day, explain_day(day))
    assert len(attempts) == 3


def test_cache_expires_and_remains_bounded(day, configured, monkeypatch):
    attempts = []
    now = [100.0]

    def handler(request):
        attempts.append(request)
        return httpx.Response(200, json=provider_result())

    configured(handler)
    monkeypatch.setattr(ai, "MAX_CACHE_ENTRIES", 2)

    # Avoid replacing the time module shared with asyncio; replace ai's reference.
    class Clock:
        @staticmethod
        def monotonic():
            return now[0]

    monkeypatch.setattr(ai, "time", Clock)
    for count in range(2, 5):
        day.summary = day.summary.model_copy(update={"trip_count": count})
        ai.explain_with_optional_ai(day, explain_day(day))
    assert len(ai._cache) == 2
    assert len(attempts) == 3
    now[0] += ai.CACHE_TTL_SECONDS + 1
    ai.explain_with_optional_ai(day, explain_day(day))
    assert len(attempts) == 4
    assert len(ai._cache) == 1


def test_identical_concurrent_requests_share_one_provider_call(day, configured):
    attempts = []
    started = threading.Event()
    release = threading.Event()

    async def handler(request):
        attempts.append(request)
        started.set()
        await asyncio.to_thread(release.wait, 2)
        return httpx.Response(200, json=provider_result())

    configured(handler)
    local = explain_day(day)
    with ThreadPoolExecutor(max_workers=4) as pool:
        first = pool.submit(ai.explain_with_optional_ai, day, local)
        assert started.wait(2)
        others = [pool.submit(ai.explain_with_optional_ai, day, local) for _ in range(3)]
        release.set()
        results = [future.result(timeout=3) for future in [first, *others]]
    assert len(attempts) == 1
    assert all(result.source == "ai" for result in results)
    assert not ai._inflight


def test_concurrency_limit_returns_local_without_extra_spend(day, configured, monkeypatch):
    started = threading.Event()
    release = threading.Event()
    attempts = []

    async def handler(request):
        attempts.append(request)
        started.set()
        await asyncio.to_thread(release.wait, 2)
        return httpx.Response(200, json=provider_result())

    configured(handler)
    monkeypatch.setattr(ai, "MAX_CONCURRENT_REQUESTS", 1)
    other = day.model_copy(deep=True)
    other.summary.trip_count = 3
    with ThreadPoolExecutor(max_workers=1) as pool:
        pending = pool.submit(ai.explain_with_optional_ai, day, explain_day(day))
        assert started.wait(2)
        result = ai.explain_with_optional_ai(other, explain_day(other))
        release.set()
        assert pending.result(timeout=3).source == "ai"
    assert result.source == "local"
    assert ai.BUSY in result.limitations
    assert len(attempts) == 1
