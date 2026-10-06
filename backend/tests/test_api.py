from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


def test_official_example_summary(client, official_trips):
    for trip in official_trips:
        response = client.post("/api/v1/trips", json=trip)
        assert response.status_code == 201
        assert response.headers["location"] == "/api/v1/days/2026-10-01"
    body = client.get("/api/v1/days/2026-10-01").json()
    assert body["timezone"] == "Asia/Almaty"
    assert body["summary"] == {
        "trip_count": 2,
        "revenue": "3900.00",
        "commission": "585.00",
        "net": "3315.00",
        "cash": "1500.00",
        "card": "2400.00",
        "trip_minutes": 37,
    }
    assert [trip["id"] for trip in body["trips"]] == ["t2", "t1"]
    assert body["trips"][1]["start"] == "2026-10-01T08:10:00+05:00"


def test_empty_day_is_not_an_error(client):
    response = client.get("/api/v1/days/2026-10-04")
    assert response.status_code == 200
    body = response.json()
    assert body["trips"] == []
    assert body["summary"] == {
        "trip_count": 0,
        "revenue": "0.00",
        "commission": "0.00",
        "net": "0.00",
        "cash": "0.00",
        "card": "0.00",
        "trip_minutes": 0,
    }
    assert client.get("/api/v1/dates").json() == {"dates": []}


def test_tiyn_exactness_and_payment_split(client, trip):
    for identifier, amount, commission, payment in [
        ("a", "0.10", "0.01", "cash"),
        ("b", "0.20", "0.02", "card"),
        ("c", "100.99", "15.15", "card"),
    ]:
        assert (
            client.post(
                "/api/v1/trips",
                json={
                    **trip,
                    "id": identifier,
                    "amount": amount,
                    "commission": commission,
                    "payment": payment,
                },
            ).status_code
            == 201
        )
    summary = client.get("/api/v1/days/2026-10-01").json()["summary"]
    assert summary["revenue"] == "101.29"
    assert summary["commission"] == "15.18"
    assert summary["net"] == "86.11"
    assert Decimal(summary["cash"]) + Decimal(summary["card"]) == Decimal(summary["revenue"])


@pytest.mark.parametrize(
    "changed",
    [
        {"amount": 0},
        {"amount": -1},
        {"amount": "NaN"},
        {"amount": "Infinity"},
        {"amount": "1.001"},
        {"amount": "100000000.01"},
        {"amount": "1E+999999999"},
        {"amount": "1E-999999999"},
        {"amount": "0e99999999999999999"},
        {"amount": True},
        {"commission": True},
        {"commission": -1},
        {"commission": 2401},
        {"commission": "0.001"},
        {"end": "2026-10-01T08:10:00+05:00"},
        {"end": "2026-10-01T08:09:00+05:00"},
        {"start": "2026-10-01T08:10:00"},
        {"end": "2026-10-01T08:32:00"},
        {"start": 1234567890},
        {"start": "1780000000"},
        {"start": "1780000000.0"},
        {"start": "1900-10-01T08:10:00+05:00"},
        {"end": "9999-12-31T23:59:59-23:59"},
        {"payment": "crypto"},
        {"id": ""},
        {"id": "a" * 101},
        {"id": "../trip"},
        {"unrecognized": "value"},
    ],
)
def test_invalid_trip_never_persists(client, trip, changed):
    response = client.post("/api/v1/trips", json={**trip, **changed})
    assert response.status_code == 422
    assert isinstance(response.json()["detail"], str)
    assert client.get("/api/v1/dates").json() == {"dates": []}


def test_timezone_day_boundary_and_overnight_trip(client, trip):
    # UTC Sep 30 is local Oct 1. End crosses local midnight into Oct 2.
    crossing = {
        **trip,
        "start": "2026-09-30T19:01:00Z",
        "end": "2026-10-01T19:03:00Z",
    }
    assert client.post("/api/v1/trips", json=crossing).status_code == 201
    assert client.get("/api/v1/dates").json() == {"dates": ["2026-10-01"]}
    assert client.get("/api/v1/days/2026-09-30").json()["summary"]["trip_count"] == 0
    assert client.get("/api/v1/days/2026-10-02").json()["summary"]["trip_count"] == 0
    assert client.get("/api/v1/days/2026-10-01").json()["summary"]["trip_minutes"] == 1442


def test_replay_returns_original_and_does_not_add_money(client, trip):
    first = client.post("/api/v1/trips", json=trip)
    replay = client.post("/api/v1/trips", json=trip)
    assert (first.status_code, replay.status_code) == (201, 200)
    assert replay.json() == first.json()
    assert client.get("/api/v1/days/2026-10-01").json()["summary"]["revenue"] == "2400.00"


def test_equivalent_offsets_and_decimals_are_same_trip(client, trip):
    first = client.post("/api/v1/trips", json=trip)
    second = client.post(
        "/api/v1/trips",
        json={
            **trip,
            "start": "2026-10-01T03:10:00.000000Z",
            "end": "2026-10-01T03:32:00+00:00",
            "amount": "2400.00",
            "commission": "360.000",
        },
    )
    assert second.status_code == 200
    assert second.json() == first.json()


@pytest.mark.parametrize(
    "changed",
    [
        {"amount": 2500},
        {"commission": 359},
        {"payment": "cash"},
        {"end": "2026-10-01T08:33:00+05:00"},
        {"start": "2026-10-01T08:11:00+05:00"},
    ],
)
def test_same_id_changed_payload_is_conflict(client, trip, changed):
    assert client.post("/api/v1/trips", json=trip).status_code == 201
    response = client.post("/api/v1/trips", json={**trip, **changed})
    assert response.status_code == 409
    assert client.get("/api/v1/days/2026-10-01").json()["trips"][0]["amount"] == "2400.00"


def test_simultaneous_replay_creates_exactly_one_trip(client, trip):
    with ThreadPoolExecutor(max_workers=8) as executor:
        responses = list(executor.map(lambda _: client.post("/api/v1/trips", json=trip), range(16)))
    statuses = [response.status_code for response in responses]
    assert statuses.count(201) == 1
    assert statuses.count(200) == 15
    summary = client.get("/api/v1/days/2026-10-01").json()["summary"]
    assert summary["trip_count"] == 1
    assert summary["net"] == "2040.00"


def test_restart_preserves_trip_and_replay_protection(database_path, trip):
    with TestClient(create_app(database_path)) as first:
        assert first.post("/api/v1/trips", json=trip).status_code == 201
    with TestClient(create_app(database_path)) as restarted:
        assert restarted.post("/api/v1/trips", json=trip).status_code == 200
        assert restarted.get("/api/v1/days/2026-10-01").json()["summary"]["trip_count"] == 1


def test_concurrent_conflicting_payloads_never_overwrite(client, trip):
    candidates = [{**trip, "amount": 2400}, {**trip, "amount": 2500}]
    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(executor.map(lambda item: client.post("/api/v1/trips", json=item), candidates))
    assert sorted(response.status_code for response in responses) == [201, 409]
    winner = next(response.json() for response in responses if response.status_code == 201)
    day = client.get("/api/v1/days/2026-10-01").json()
    assert day["summary"]["trip_count"] == 1
    assert day["summary"]["revenue"] == winner["amount"]


def test_dates_are_sorted_and_unique(client, trip):
    for index, day in enumerate(["06", "01", "05", "06"]):
        payload = {
            **trip,
            "id": str(index),
            "start": f"2026-10-{day}T08:10:00+05:00",
            "end": f"2026-10-{day}T08:32:00+05:00",
        }
        assert client.post("/api/v1/trips", json=payload).status_code == 201
    assert client.get("/api/v1/dates").json() == {"dates": ["2026-10-01", "2026-10-05", "2026-10-06"]}


def test_insights_are_grounded_and_honestly_labelled(client, official_trips):
    for trip in official_trips:
        client.post("/api/v1/trips", json=trip)
    response = client.post("/api/v1/days/2026-10-01/insights")
    body = response.json()
    assert response.status_code == 200
    assert body["source"] == "local"
    assert "3 315 ₸" in body["text"]
    assert any("15%" in fact for fact in body["facts"])
    assert len(body["limitations"]) == 3
    assert client.post("/api/v1/days/2026-10-04/insights").json()["facts"] == []


def test_health_and_unknown_api_remain_json(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/api/v1/does-not-exist").status_code == 404
    assert client.get("/api/v1/does-not-exist").headers["content-type"] == "application/json"
    assert client.get("/api/v1/days/not-a-date").status_code == 422


def test_flutter_static_files_do_not_swallow_api_routes(database_path, tmp_path):
    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>Shift diary</html>")
    with TestClient(create_app(database_path, web_path=web)) as client:
        assert "Shift diary" in client.get("/").text
        assert client.get("/api/missing").status_code == 404
        assert client.get("/api/missing").headers["content-type"] == "application/json"
