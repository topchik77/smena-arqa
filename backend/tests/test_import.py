import json
from datetime import date
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.import_data import import_file
from app.repository import TripConflict, TripRepository


def test_official_import_is_idempotent(database_path):
    repository = TripRepository(database_path)
    source = Path(__file__).resolve().parents[2] / "data" / "trips.json"
    assert import_file(source, repository) == (2, 0)
    assert import_file(source, repository) == (0, 2)
    assert repository.day(date(2026, 10, 1)).summary.net == "3315.00"


def test_import_conflict_rolls_back_the_entire_batch(database_path, tmp_path, trip):
    repository = TripRepository(database_path)
    source = tmp_path / "trips.json"
    source.write_text(json.dumps([trip]))
    assert import_file(source, repository) == (1, 0)
    source.write_text(json.dumps([{**trip, "id": "new-id"}, {**trip, "amount": 2500}]))
    with pytest.raises(TripConflict):
        import_file(source, repository)
    assert repository.day(date(2026, 10, 1)).summary.trip_count == 1


def test_import_invalid_record_does_not_write_valid_predecessors(database_path, tmp_path, trip):
    repository = TripRepository(database_path)
    repository.initialize()
    source = tmp_path / "trips.json"
    source.write_text(json.dumps([trip, {**trip, "id": "invalid", "amount": 0}]))
    with pytest.raises(ValidationError):
        import_file(source, repository)
    assert repository.dates() == []


def test_demo_import_is_separate_and_has_usable_days(database_path):
    repository = TripRepository(database_path)
    root = Path(__file__).resolve().parents[2] / "data"
    import_file(root / "trips.json", repository)
    assert import_file(root / "demo-trips.json", repository) == (14, 0)
    assert repository.dates() == [date(2026, 10, day) for day in [1, 2, 5, 6]]
    assert repository.day(date(2026, 10, 6)).summary.trip_count == 6
