#!/usr/bin/env python3
"""Apply numbered SQL migrations in order; track state in schema_migrations."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import psycopg2

_MIGRATION_FILE = re.compile(r"^(\d+)_.+\.sql$")


def _default_database_url() -> str:
    return os.environ.get(
        "DATABASE_URL",
        "postgres://postgres:postgres@localhost:5432/cloud-native-deployment-platform",
    )


def _ordered_migration_files(migrations_dir: Path) -> list[tuple[int, Path]]:
    found: list[tuple[int, Path]] = []
    for path in sorted(migrations_dir.iterdir()):
        if not path.is_file():
            continue
        match = _MIGRATION_FILE.match(path.name)
        if not match:
            continue
        found.append((int(match.group(1)), path))
    found.sort(key=lambda item: item[0])
    return found


def _ensure_schema_migrations_table(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              filename TEXT NOT NULL UNIQUE,
              applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            """
        )


def _applied_versions(conn) -> set[int]:
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM schema_migrations")
        return {row[0] for row in cur.fetchall()}


def _run_migration(conn, version: int, filename: str, sql_body: str) -> None:
    """Execute migration SQL and record success in schema_migrations (one transaction)."""
    with conn:
        with conn.cursor() as cur:
            cur.execute(sql_body)
            cur.execute(
                "INSERT INTO schema_migrations (version, filename) VALUES (%s, %s)",
                (version, filename),
            )


def run_migrations(database_url: str, migrations_dir: Path) -> int:
    """Connect, ensure tracking table exists, apply pending numbered migrations."""
    if not migrations_dir.is_dir():
        print(f"migrations directory not found: {migrations_dir}", file=sys.stderr)
        return 1

    migrations = _ordered_migration_files(migrations_dir)
    if not migrations:
        print(f"no numbered migration *.sql files in {migrations_dir}", file=sys.stderr)
        return 1

    try:
        conn = psycopg2.connect(database_url)
    except psycopg2.Error as exc:
        print(f"could not connect: {exc}", file=sys.stderr)
        return 1

    try:
        conn.autocommit = False
        _ensure_schema_migrations_table(conn)
        conn.commit()

        pending = [(v, p) for v, p in migrations if v not in _applied_versions(conn)]
        for version, path in pending:
            sql_body = path.read_text(encoding="utf-8")
            try:
                _run_migration(conn, version, path.name, sql_body)
                conn.commit()
                print(f"applied {path.name}")
            except psycopg2.Error as exc:
                conn.rollback()
                print(f"failed {path.name}: {exc}", file=sys.stderr)
                return 1
    finally:
        conn.close()

    return 0


def main() -> int:
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Run SQL migrations against PostgreSQL.")
    parser.add_argument(
        "--migrations-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "migrations",
        help="Directory containing NN_name.sql migrations",
    )
    parser.add_argument(
        "--database-url",
        default=_default_database_url(),
        help="PostgreSQL URL (default: DATABASE_URL env or local docker-style URL)",
    )
    args = parser.parse_args()

    return run_migrations(args.database_url, args.migrations_dir)


if __name__ == "__main__":
    sys.exit(main())
