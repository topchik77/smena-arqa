"""Explicit, validated, atomic JSON import: python -m app.import_data FILE."""

import argparse
import json
import os
import sys
from decimal import Decimal
from pathlib import Path

from pydantic import TypeAdapter, ValidationError

from .models import TripInput
from .repository import TripConflict, TripRepository


def import_file(path: Path, repository: TripRepository) -> tuple[int, int]:
    raw = json.loads(path.read_text(encoding="utf-8-sig"), parse_float=Decimal)
    trips = TypeAdapter(list[TripInput]).validate_python(raw)
    repository.initialize()
    return repository.import_all(trips)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate and atomically import trip JSON.")
    parser.add_argument("file", type=Path)
    parser.add_argument(
        "--db",
        type=Path,
        default=Path(os.getenv("ARQA_DB_PATH", Path(__file__).resolve().parents[2] / "var" / "arqa.sqlite3")),
    )
    args = parser.parse_args()
    try:
        created, replayed = import_file(args.file, TripRepository(args.db))
    except (OSError, ValueError, ValidationError, TripConflict) as exc:
        print(f"Import failed; no partial import: {exc}", file=sys.stderr)
        return 1
    print(f"Created: {created}; already present: {replayed}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
