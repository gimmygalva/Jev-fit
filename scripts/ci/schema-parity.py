#!/usr/bin/env python3
"""Verifica che lo schema locale (SQLite, GRDB) e lo schema cloud (Supabase) siano speculari per le
tabelle sincronizzate (DATA_MODEL §4).

- Locale: applica in memoria le migrazioni SQL di Packages/JevKit/Sources/Persistence/Migrations.
  Tabelle sincronizzate = tabelle con colonna `sync_state`.
- Cloud: legge information_schema dal database indicato dalle variabili PG* (dopo db-test.sh).
  Tabelle sincronizzate = tabelle di `public` con il trigger `<tabella>_sync_columns`.

Controlli: stesso insieme di tabelle; stesse colonne (al netto di `sync_state`, solo locale, e di
`user_id`, solo cloud); stessa obbligatorietà (NOT NULL) per ogni colonna.
Uso: python3 scripts/ci/schema-parity.py  (con PGHOST/PGUSER/... e DB_NAME come db-test.sh)
"""
import os
import pathlib
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "Packages/JevKit/Sources/Persistence/Migrations"
LOCAL_ONLY = {"sync_state"}
CLOUD_ONLY = {"user_id"}


def local_schema():
    db = sqlite3.connect(":memory:")
    files = sorted(MIGRATIONS.glob("v*.sql"))
    if not files:
        sys.exit(f"Nessuna migrazione locale in {MIGRATIONS}")
    for f in files:
        db.executescript(f.read_text())
    schema = {}
    for (table,) in db.execute("select name from sqlite_master where type = 'table'"):
        cols = {row[1]: bool(row[3] or row[5]) for row in db.execute(f"pragma table_info({table})")}
        if "sync_state" in cols:
            schema[table] = {c: nn for c, nn in cols.items() if c not in LOCAL_ONLY}
    return schema


def cloud_schema():
    query = """
      select c.table_name, c.column_name, c.is_nullable
      from information_schema.columns c
      where c.table_schema = 'public'
        and exists (select 1 from information_schema.triggers t
                    where t.trigger_schema = 'public' and t.event_object_table = c.table_name
                      and t.trigger_name = c.table_name || '_sync_columns')
      order by 1, 2
    """
    out = subprocess.run(
        ["psql", "-X", "-At", "-F", "|", "-v", "ON_ERROR_STOP=1",
         "-d", os.environ.get("DB_NAME", "jevfit_test"), "-c", query],
        check=True, capture_output=True, text=True,
    ).stdout
    schema = {}
    for line in out.splitlines():
        table, column, nullable = line.split("|")
        if column not in CLOUD_ONLY:
            schema.setdefault(table, {})[column] = nullable == "NO"
    return schema


def main():
    local, cloud = local_schema(), cloud_schema()
    errors = []
    for t in sorted(set(local) - set(cloud)):
        errors.append(f"{t}: sincronizzata in locale ma assente nel cloud")
    for t in sorted(set(cloud) - set(local)):
        errors.append(f"{t}: sincronizzata nel cloud ma assente in locale")
    for t in sorted(set(local) & set(cloud)):
        lc, cc = local[t], cloud[t]
        for c in sorted(set(lc) - set(cc)):
            errors.append(f"{t}.{c}: colonna solo locale")
        for c in sorted(set(cc) - set(lc)):
            errors.append(f"{t}.{c}: colonna solo cloud")
        for c in sorted(set(lc) & set(cc)):
            # server_updated_at: obbligatoria nel cloud, NULL in locale finché il record non è sincronizzato.
            if c == "server_updated_at":
                continue
            if lc[c] != cc[c]:
                errors.append(f"{t}.{c}: NOT NULL locale={lc[c]} cloud={cc[c]}")
    if errors:
        print("Schema locale e cloud non speculari:")
        print("\n".join(f"  - {e}" for e in errors))
        sys.exit(1)
    print(f"ok: {len(local)} tabelle sincronizzate speculari (colonne e NOT NULL)")


if __name__ == "__main__":
    main()
