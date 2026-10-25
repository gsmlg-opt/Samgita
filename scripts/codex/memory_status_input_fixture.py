#!/usr/bin/env python3
"""Prepare/read synthetic count input for the real native memory/status reader.

The native public status request must create and migrate this existing store
first. This helper never creates a database/schema or returns protocol frames.
It deliberately does not run or certify the production consolidation writer.
"""

import argparse
from contextlib import closing
import json
from pathlib import Path
import sqlite3


SEEDS = {"seed-two": (0, 2), "seed-nineteen": (2, 19), "seed-twenty": (19, 20)}


def open_existing(database: Path, mode: str) -> sqlite3.Connection:
    return sqlite3.connect(database.as_uri() + "?mode=" + mode, uri=True, timeout=1)


def read_count(database: Path) -> int:
    with closing(open_existing(database, "ro")) as connection:
        rows = connection.execute(
            "SELECT singleton, max_thread_count FROM consolidation_progress"
        ).fetchall()
    if len(rows) != 1 or rows[0][0] != 1:
        raise ValueError("Expected the real migrated singleton row")
    count = rows[0][1]
    if type(count) is not int or count < 0:
        raise ValueError("Expected a nonnegative integer count")
    return count


def seed_count(database: Path, expected: int, target: int) -> int:
    with closing(open_existing(database, "rw")) as connection:
        try:
            connection.execute("BEGIN IMMEDIATE")
            rows = connection.execute(
                "SELECT singleton, max_thread_count FROM consolidation_progress"
            ).fetchall()
            if rows != [(1, expected)]:
                raise ValueError("Synthetic seed requires the exact prescribed prior count")
            updated = connection.execute(
                "UPDATE consolidation_progress SET max_thread_count = ? "
                "WHERE singleton = 1 AND max_thread_count = ?",
                (target, expected),
            ).rowcount
            if updated != 1:
                raise ValueError("Synthetic seed must update exactly one existing row")
            connection.commit()
        except Exception:
            connection.rollback()
            raise
    # A separate read-only connection observes the committed input, rather
    # than returning the literal UPDATE value as an apparent observation.
    if read_count(database) != target:
        raise ValueError("Committed synthetic count did not match its prescribed target")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("read", *SEEDS))
    parser.add_argument("--codex-home", required=True)
    parser.add_argument("--stopped-native-pid", type=int, required=True)
    args = parser.parse_args()
    if args.stopped_native_pid <= 0 or Path("/proc", str(args.stopped_native_pid)).exists():
        raise ValueError("The owned native process must already be stopped")
    codex_home = Path(args.codex_home).resolve(strict=True)
    database = (codex_home / "memories_v2_1.sqlite").resolve(strict=True)
    if not database.is_file():
        raise ValueError("The native-created V2 database is missing")
    updated = seed_count(database, *SEEDS[args.operation]) if args.operation in SEEDS else 0
    print(
        json.dumps(
            {"singleton": 1, "max_thread_count": read_count(database), "updated_rows": updated},
            sort_keys=True,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
