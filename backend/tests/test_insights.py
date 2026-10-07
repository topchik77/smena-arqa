"""Derived day comparisons, baseline selection, and one-snapshot consistency."""

import json
from datetime import date

import httpx

from app import ai_insights as ai
from app.models import TripInput
from app.repository import TripRepository


def make_trip(identifier, day, amount="1000.00", commission="0.00"):
    return {
        "id": identifier,
        "start": f"2026-10-{day:02}T09:00:00+05:00",
        "end": f"2026-10-{day:02}T09:20:00+05:00",
        "amount": amount,
        "commission": commission,
        "payment": "card",
    }


def add_day(client, day, count, amount="1000.00", commission="0.00"):
    for index in range(count):
        response = client.post("/api/v1/trips", json=make_trip(f"{day}-{index}", day, amount, commission))
        assert response.status_code == 201


def get_insight(client, day):
    response = client.post(f"/api/v1/days/2026-10-{day:02}/insights")
    assert response.status_code == 200
    return response.json()


def test_growth_compares_net_count_and_average_against_latest_earlier_active_day(client):
    add_day(client, 1, 1, "100.00")  # An older day must not be the baseline.
    add_day(client, 2, 2, "1000.00")
    add_day(client, 6, 3, "1500.00")  # Calendar days 3–5 are empty.
    result = get_insight(client, 6)
    assert result["source"] == "local"
    assert result["text"] == "Сравнение с 02.10.2026 — предыдущим днём с поездками."
    assert result["facts"] == [
        "На руки на 2 500 ₸ больше (125%).",
        "Поездок: 3 вместо 2 (+1).",
        "В среднем на руки за поездку: 1 500 ₸ вместо 1 000 ₸ (+500 ₸).",
    ]
    assert all("2026" not in fact for fact in result["facts"])


def test_decline_has_correct_direction_percentage_and_average(client):
    add_day(client, 2, 3, "1500.00")
    add_day(client, 6, 2, "1000.00")
    result = get_insight(client, 6)
    assert result["facts"] == [
        "На руки на 2 500 ₸ меньше (55,6%).",
        "Поездок: 2 вместо 3 (−1).",
        "В среднем на руки за поездку: 1 000 ₸ вместо 1 500 ₸ (−500 ₸).",
    ]


def test_future_days_never_become_a_baseline(client):
    add_day(client, 6, 1)
    add_day(client, 7, 2, "9000.00")
    first = get_insight(client, 6)
    assert "Более ранних дней с поездками нет" in first["text"]
    assert "9 000" not in json.dumps(first, ensure_ascii=False)
    add_day(client, 1, 1, "500.00")
    compared = get_insight(client, 6)
    assert "01.10.2026" in compared["text"]
    assert compared["facts"][0] == "На руки на 500 ₸ больше (100%)."


def test_zero_previous_net_reports_absolute_change_without_percentage(client):
    add_day(client, 1, 1, "1000.00", "1000.00")
    add_day(client, 6, 1, "1000.00")
    result = get_insight(client, 6)
    assert result["facts"][0] == ("На руки: +1 000 ₸. Раньше было 0 ₸, процент изменения не рассчитывается.")
    assert "%" not in result["facts"][0]
    assert "1 000 ₸ вместо 0 ₸ (+1 000 ₸)" in result["facts"][2]


def test_unchanged_zero_net_does_not_divide_by_zero(client):
    add_day(client, 1, 1, "1000.00", "1000.00")
    add_day(client, 6, 1, "2000.00", "2000.00")
    result = get_insight(client, 6)
    assert result["facts"][0] == "На руки без изменений: 0 ₸."
    assert result["facts"][2].endswith("(без изменений).")


def test_recorded_zero_net_can_be_a_real_full_decline(client):
    add_day(client, 1, 1, "1000.00")
    add_day(client, 6, 1, "1000.00", "1000.00")
    result = get_insight(client, 6)
    assert result["facts"][0] == "На руки на 1 000 ₸ меньше (100%)."


def test_first_day_explains_averages_without_repeating_totals(client, official_trips):
    for trip in official_trips:
        assert client.post("/api/v1/trips", json=trip).status_code == 201
    result = get_insight(client, 1)
    assert "Более ранних дней с поездками нет" in result["text"]
    assert result["facts"] == [
        "В среднем на поездку после комиссии: 1 657,50 ₸.",
        "Средняя длительность поездки: около 18,5 мин.",
        "Доля комиссии в выручке: 15%.",
    ]
    assert "3 315" not in json.dumps(result, ensure_ascii=False)
    assert "час" not in " ".join(result["facts"])


def test_empty_day_does_not_imply_a_full_loss(client):
    add_day(client, 1, 2)
    result = get_insight(client, 6)
    assert result["facts"] == []
    assert "не означает падение" in result["text"]
    assert "100%" not in json.dumps(result, ensure_ascii=False)


def test_average_money_is_rounded_to_tiyn(client):
    add_day(client, 1, 3, "0.02", "0.01")
    add_day(client, 6, 3, "0.02")
    extra = make_trip("fractional-average", 6, "0.01")
    assert client.post("/api/v1/trips", json=extra).status_code == 201
    result = get_insight(client, 6)
    assert "0,02 ₸ вместо 0,01 ₸ (+0,01 ₸)" in result["facts"][2]


def test_tiny_change_is_not_reported_as_zero_percent(client):
    add_day(client, 1, 1, "1000.00")
    add_day(client, 6, 1, "1000.01")
    assert get_insight(client, 6)["facts"][0] == "На руки на 0,01 ₸ больше (<0,1%)."


def test_both_days_keep_one_snapshot_while_another_connection_writes(database_path, monkeypatch):
    reader = TripRepository(database_path)
    writer = TripRepository(database_path)
    writer.initialize()
    writer.import_all(
        [
            TripInput.model_validate(make_trip("earlier", 1)),
            TripInput.model_validate(make_trip("current", 6)),
        ]
    )
    original_connect = reader.connect
    wrote = False

    class InterleavedConnection:
        def __init__(self):
            self.connection = original_connect()

        def execute(self, statement, parameters):
            nonlocal wrote
            cursor = self.connection.execute(statement, parameters)
            if not wrote:
                wrote = True
                writer.import_all(
                    [
                        TripInput.model_validate(make_trip("new-baseline", 5, "9000.00")),
                        TripInput.model_validate(make_trip("new-current", 6, "3000.00")),
                    ]
                )
            return cursor

        def close(self):
            self.connection.close()

    monkeypatch.setattr(reader, "connect", InterleavedConnection)
    current, previous = reader.day_with_previous(date(2026, 10, 6))
    assert wrote
    assert current.summary.net == "1000.00"
    assert previous is not None
    assert previous.date == date(2026, 10, 1)
    assert previous.summary.net == "1000.00"
    updated, new_previous = writer.day_with_previous(date(2026, 10, 6))
    assert updated.summary.net == "4000.00"
    assert new_previous.date == date(2026, 10, 5)


def test_comparison_date_stays_in_text_and_never_reaches_optional_ai(client, monkeypatch):
    add_day(client, 1, 1)
    add_day(client, 6, 2, "1500.00")
    monkeypatch.setenv("OPENAI_API_KEY", "mock-test-only")
    monkeypatch.setenv("OPENAI_MODEL", "mock-comparison-model")
    original_client = httpx.AsyncClient
    sent = []

    def handler(request):
        sent.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                "status": "completed",
                "output": [
                    {
                        "type": "message",
                        "content": [{"type": "output_text", "text": '{"selected_ids":["fact_3","fact_1"]}'}],
                    }
                ],
            },
        )

    monkeypatch.setattr(
        ai.httpx,
        "AsyncClient",
        lambda **kwargs: original_client(transport=httpx.MockTransport(handler), **kwargs),
    )
    with ai._lock:
        ai._cache.clear()
    try:
        result = get_insight(client, 6)
        assert result["source"] == "ai"
        assert "01.10.2026" in result["text"]
        assert len(result["facts"]) == 2
        assert len(sent) == 1
        assert "2026" not in sent[0]["input"]
        assert "01.10" not in sent[0]["input"]
        assert "06.10" not in sent[0]["input"]
    finally:
        with ai._lock:
            ai._cache.clear()
