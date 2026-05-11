#!/usr/bin/env python3
"""Tests for SQL migration ordering and transaction behavior."""

# pylint: disable=protected-access,wrong-import-position

from __future__ import annotations

import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_migrations


class FakeCursor:
    """Small DB-API cursor fake for migration runner tests."""

    def __init__(self, conn: "FakeConnection") -> None:
        self.conn = conn
        self.rows: list[tuple[int]] = []

    def __enter__(self) -> "FakeCursor":
        return self

    def __exit__(self, _exc_type, _exc, _traceback) -> None:
        return None

    def execute(self, sql: str, params=None) -> None:
        """Record SQL and emulate schema_migrations reads/writes."""
        if "SELECT version FROM schema_migrations" in sql:
            self.rows = [(version,) for version in sorted(self.conn.applied_versions)]
            return
        if self.conn.fail_on_sql and self.conn.fail_on_sql in sql:
            raise run_migrations.psycopg2.Error("migration failed")
        if "INSERT INTO schema_migrations" in sql and params:
            version, filename = params
            self.conn.applied_versions.add(version)
            self.conn.inserted_versions.append((version, filename))

    def fetchall(self) -> list[tuple[int]]:
        """Return rows prepared by the last SELECT."""
        return self.rows


class FakeConnection:
    """Small psycopg2 connection fake with transaction counters."""

    def __init__(self, *, applied_versions=None, fail_on_sql: str | None = None) -> None:
        self.applied_versions = set(applied_versions or [])
        self.fail_on_sql = fail_on_sql
        self.autocommit = True
        self.rollbacks = 0
        self.closed = False
        self.inserted_versions: list[tuple[int, str]] = []

    def __enter__(self) -> "FakeConnection":
        return self

    def __exit__(self, _exc_type, _exc, _traceback) -> None:
        return None

    def cursor(self) -> FakeCursor:
        """Return a fresh fake cursor."""
        return FakeCursor(self)

    def commit(self) -> None:
        """Track commits so tests can assert transaction boundaries."""
        return None

    def rollback(self) -> None:
        """Track rollbacks on failed migrations."""
        self.rollbacks += 1

    def close(self) -> None:
        """Track that connections are closed in all paths."""
        self.closed = True


class RunMigrationsTests(unittest.TestCase):
    """Migration runner behavior without requiring a live PostgreSQL service."""

    def test_ordered_migration_files_ignores_non_numbered_files(self) -> None:
        """Only NN_name.sql files are selected, sorted by numeric version."""
        with tempfile.TemporaryDirectory() as tmp:
            migrations_dir = Path(tmp)
            (migrations_dir / "010_later.sql").write_text("-- later", encoding="utf-8")
            (migrations_dir / "002_second.sql").write_text("-- second", encoding="utf-8")
            (migrations_dir / "README.md").write_text("ignore me", encoding="utf-8")
            (migrations_dir / "abc_bad.sql").write_text("-- ignore", encoding="utf-8")

            ordered = run_migrations._ordered_migration_files(migrations_dir)

        self.assertEqual(
            [(version, path.name) for version, path in ordered],
            [(2, "002_second.sql"), (10, "010_later.sql")],
        )

    def test_run_migrations_applies_pending_files_and_skips_applied_versions(self) -> None:
        """Pending migrations are applied in order and already-recorded versions are skipped."""
        conn = FakeConnection(applied_versions={2})
        with tempfile.TemporaryDirectory() as tmp:
            migrations_dir = Path(tmp)
            (migrations_dir / "001_create_first.sql").write_text(
                "CREATE TABLE firsts();",
                encoding="utf-8",
            )
            (migrations_dir / "002_create_second.sql").write_text(
                "CREATE TABLE seconds();",
                encoding="utf-8",
            )
            (migrations_dir / "003_create_third.sql").write_text(
                "CREATE TABLE thirds();",
                encoding="utf-8",
            )

            with patch.object(run_migrations.psycopg2, "connect", return_value=conn):
                with redirect_stdout(StringIO()):
                    result = run_migrations.run_migrations("postgres://example", migrations_dir)

        self.assertEqual(result, 0)
        self.assertFalse(conn.autocommit)
        self.assertTrue(conn.closed)
        self.assertEqual(
            conn.inserted_versions,
            [(1, "001_create_first.sql"), (3, "003_create_third.sql")],
        )

    def test_run_migrations_rolls_back_and_stops_on_sql_failure(self) -> None:
        """A failed migration rolls back, returns non-zero, and does not record success."""
        conn = FakeConnection(fail_on_sql="CREATE TABLE broken")
        with tempfile.TemporaryDirectory() as tmp:
            migrations_dir = Path(tmp)
            (migrations_dir / "001_broken.sql").write_text(
                "CREATE TABLE broken();",
                encoding="utf-8",
            )

            with patch.object(run_migrations.psycopg2, "connect", return_value=conn):
                with redirect_stderr(StringIO()):
                    result = run_migrations.run_migrations("postgres://example", migrations_dir)

        self.assertEqual(result, 1)
        self.assertEqual(conn.rollbacks, 1)
        self.assertEqual(conn.inserted_versions, [])
        self.assertTrue(conn.closed)


if __name__ == "__main__":
    unittest.main()
