import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture(autouse=True)
def disable_external_ai(monkeypatch):
    """Tests cannot accidentally use a developer's real credentials or spend money."""
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_MODEL", raising=False)


@pytest.fixture
def trip():
    return {
        "id": "t1",
        "start": "2026-10-01T08:10:00+05:00",
        "end": "2026-10-01T08:32:00+05:00",
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    }


@pytest.fixture
def official_trips():
    return json.loads((Path(__file__).resolve().parents[2] / "data" / "trips.json").read_text())


@pytest.fixture
def database_path(tmp_path):
    return tmp_path / "diary.sqlite3"


@pytest.fixture
def client(database_path):
    with TestClient(create_app(database_path)) as test_client:
        yield test_client
