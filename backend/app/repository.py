"""SQLite repository: one connection per operation and atomic idempotent writes."""

import sqlite3
from contextlib import closing
from datetime import date, datetime, timedelta
from pathlib import Path

from .models import LOCAL_TZ, DayView, Summary, TripInput, TripView, money_text

SCHEMA = """
CREATE TABLE IF NOT EXISTS trips (
    id TEXT PRIMARY KEY NOT NULL,
    start TEXT NOT NULL,
    end TEXT NOT NULL CHECK (end > start),
    amount_tiyn INTEGER NOT NULL CHECK (amount_tiyn > 0 AND amount_tiyn <= 10000000000),
    payment TEXT NOT NULL CHECK (payment IN ('cash', 'card')),
    commission_tiyn INTEGER NOT NULL CHECK (commission_tiyn >= 0 AND commission_tiyn <= amount_tiyn),
    local_date TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS trips_by_day ON trips(local_date, start);
"""
COLUMNS = "id, start, end, amount_tiyn, payment, commission_tiyn, local_date"


class TripConflict(Exception):
    """The trip ID already identifies a different, immutable payload."""


class TripRepository:
    def __init__(self, path: Path):
        self.path = path

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=10000")
        return connection

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self.connect()) as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.executescript(SCHEMA)

    @staticmethod
    def _write(connection: sqlite3.Connection, trip: TripInput) -> bool:
        payload = trip.canonical()
        existing = connection.execute(f"SELECT {COLUMNS} FROM trips WHERE id = ?", (trip.id,)).fetchone()
        if existing is not None:
            if tuple(existing) != payload:
                raise TripConflict(trip.id)
            return False
        connection.execute(f"INSERT INTO trips ({COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?)", payload)
        return True

    def add(self, trip: TripInput) -> tuple[TripView, bool]:
        # BEGIN IMMEDIATE serializes writers before the lookup. The primary key is
        # the final database invariant, including writes from other processes.
        with closing(self.connect()) as connection, connection:
            connection.execute("BEGIN IMMEDIATE")
            created = self._write(connection, trip)
        return self.view(trip.canonical()), created

    def import_all(self, trips: list[TripInput]) -> tuple[int, int]:
        """All records are committed together, or none on a conflict."""
        created = 0
        with closing(self.connect()) as connection, connection:
            connection.execute("BEGIN IMMEDIATE")
            for trip in trips:
                created += self._write(connection, trip)
        return created, len(trips) - created

    @staticmethod
    def view(row: sqlite3.Row | tuple) -> TripView:
        return TripView(
            id=row[0],
            start=datetime.fromisoformat(row[1]).astimezone(LOCAL_TZ),
            end=datetime.fromisoformat(row[2]).astimezone(LOCAL_TZ),
            amount=money_text(row[3]),
            payment=row[4],
            commission=money_text(row[5]),
        )

    def day(self, selected: date) -> DayView:
        # A single SELECT snapshot backs both the list and summary. Concurrent
        # additions cannot make these two parts of the response disagree.
        with closing(self.connect()) as connection:
            rows = connection.execute(
                f"SELECT {COLUMNS} FROM trips WHERE local_date = ? ORDER BY start DESC, id",
                (selected.isoformat(),),
            ).fetchall()
        return self._day_from_rows(selected, rows)

    def day_with_previous(self, selected: date) -> tuple[DayView, DayView | None]:
        """Read selected day and latest earlier active day in one SQL snapshot.

        A single statement keeps date selection, current totals and baseline
        totals consistent even if another connection adds a trip during reading.
        Empty calendar days and dates after the selection never become a baseline.
        """
        selected_key = selected.isoformat()
        with closing(self.connect()) as connection:
            rows = connection.execute(
                f"""SELECT {COLUMNS} FROM trips
                WHERE local_date = ? OR local_date = (
                    SELECT MAX(local_date) FROM trips WHERE local_date < ?
                )
                ORDER BY local_date, start DESC, id""",
                (selected_key, selected_key),
            ).fetchall()
        current_rows = [row for row in rows if row[6] == selected_key]
        previous_rows = [row for row in rows if row[6] < selected_key]
        previous = (
            self._day_from_rows(date.fromisoformat(previous_rows[0][6]), previous_rows)
            if previous_rows
            else None
        )
        return self._day_from_rows(selected, current_rows), previous

    @classmethod
    def _day_from_rows(cls, selected: date, rows: list[sqlite3.Row]) -> DayView:
        revenue = sum(row[3] for row in rows)
        commission = sum(row[5] for row in rows)
        cash = sum(row[3] for row in rows if row[4] == "cash")
        durations = [datetime.fromisoformat(row[2]) - datetime.fromisoformat(row[1]) for row in rows]
        # Duration is descriptive (not working hours) and rounded down only once,
        # after aggregating exact timedeltas.
        minutes = sum(durations, timedelta()) // timedelta(minutes=1)
        return DayView(
            date=selected,
            trips=[cls.view(row) for row in rows],
            summary=Summary(
                trip_count=len(rows),
                revenue=money_text(revenue),
                commission=money_text(commission),
                net=money_text(revenue - commission),
                cash=money_text(cash),
                card=money_text(revenue - cash),
                trip_minutes=minutes,
            ),
        )

    def dates(self) -> list[date]:
        with closing(self.connect()) as connection:
            rows = connection.execute("SELECT DISTINCT local_date FROM trips ORDER BY local_date").fetchall()
        return [date.fromisoformat(row[0]) for row in rows]
