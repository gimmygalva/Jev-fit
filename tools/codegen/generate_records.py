#!/usr/bin/env python3
"""Genera i record GRDB delle tabelle sincronizzate a partire dalle migrazioni SQL locali.

Lo schema SQL (Packages/JevKit/Sources/Persistence/Migrations/v*.sql) è la fonte di verità:
i record Swift ne sono una proiezione e non si scrivono a mano, così nomi delle colonne,
obbligatorietà e default non possono divergere (DATA_MODEL §6).

Uso:   python3 -I tools/codegen/generate_records.py           (scrive il file generato)
       python3 -I tools/codegen/generate_records.py --check   (CI: fallisce se non aggiornato)
"""
import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "Packages/JevKit/Sources/Persistence/Migrations"
OUTPUT = ROOT / "Packages/JevKit/Sources/Persistence/Records/SyncedRecords.generated.swift"

SYNC_COLUMNS = ["created_at", "updated_at", "deleted_at", "origin_device_id", "server_updated_at", "sync_state"]

# Tipo Swift per colonna. Chiave: "tabella.colonna" (precedenza) oppure "colonna".
ENUMS = {
    "user_profile.sex": "BiologicalSex",
    "experience": "ExperienceLevel",
    "activity_level": "ActivityLevel",
    "unit_system": "UnitSystem",
    "energy_unit": "EnergyUnitPreference",
    "goal.type": "GoalType",
    "macro_mode": "MacroMode",
    "nutrition_target.mode": "MacroMode",
    "split_preference": "SplitType",
    "split": "SplitType",
    "body_area": "BodyArea",
    "severity": "LimitationSeverity",
    "weight_entry.source": "MeasurementSource",
    "body_measurement.source": "MeasurementSource",
    "workout_session.source": "WorkoutSource",
    "body_measurement.type": "BodyMeasurementType",
    "load_type": "LoadType",
    "mechanics": "ExerciseMechanics",
    "laterality": "ExerciseLaterality",
    "muscle": "MuscleGroup",
    "role": "MuscleRole",
    "training_program.status": "ProgramStatus",
    "workout_session.status": "WorkoutSessionStatus",
    "nutrition_day.status": "NutritionDayStatus",
    "ai_recommendation.status": "RecommendationStatus",
    "set_type": "SetType",
    "entered_unit": "EnteredMassUnit",
    "pain_level": "PainLevel",
    "pain_report.level": "PainLevel",
    "exercise_preference.kind": "ExercisePreferenceKind",
    "meal_slot": "MealSlot",
    "food_source": "FoodSource",
    "day_type": "DayType",
    "nutrition_target.origin": "NutritionTargetOrigin",
    "confidence": "ConfidenceLabel",
}
JSON_ARRAYS = {
    "preferred_weekdays": "[Int]",
    "equipment": "[Equipment]",
    "muscle_priority": "[MuscleGroup]",
    "focus_muscles": "[MuscleGroup]",
    "contraindicated_areas": "[BodyArea]",
}
DAY_COLUMNS = {"day_key", "week_start", "effective_from"}
UUID_COLUMNS_TEXT_EXCEPTIONS = set()


def camel(name):
    head, *rest = name.split("_")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def type_name(table):
    return "".join(part[:1].upper() + part[1:] for part in table.split("_")) + "Record"


def lookup(mapping, table, column):
    return mapping.get(f"{table}.{column}", mapping.get(column))


def swift_type(table, column, sql_type, check_sql):
    enum = lookup(ENUMS, table, column)
    if enum:
        return enum
    if column in JSON_ARRAYS:
        return JSON_ARRAYS[column]
    if column in DAY_COLUMNS:
        return "DayKey"
    if sql_type == "BLOB":
        return "UUID"
    if column.endswith("_at"):
        return "Date"
    if sql_type == "REAL":
        return "Double"
    if sql_type == "INTEGER":
        if re.search(rf"\b{column}\s+IN\s*\(\s*0\s*,\s*1\s*\)", check_sql):
            return "Bool"
        return "Int"
    if sql_type == "TEXT":
        return "String"
    raise SystemExit(f"Tipo non gestito: {table}.{column} {sql_type}")


def swift_default(swift, default):
    """Default Swift equivalente al DEFAULT SQL (solo i casi usati nello schema)."""
    if default is None:
        return None
    raw = default.strip()
    if raw.startswith("'") and raw.endswith("'"):
        value = raw[1:-1]
        if swift.startswith("["):
            if value != "[]":
                raise SystemExit(f"Default JSON non gestito: {raw}")
            return "[]"
        if swift == "String":
            return '"' + value.replace('"', '\\"') + '"'
        # enum: case Swift dal valore raw
        return "." + camel(value)
    if swift == "Bool":
        return {"0": "false", "1": "true"}[raw]
    if swift in ("Int", "Double"):
        return raw
    raise SystemExit(f"Default non gestito: {raw} per {swift}")


def load_schema():
    db = sqlite3.connect(":memory:")
    for f in sorted(MIGRATIONS.glob("v*.sql")):
        db.executescript(f.read_text())
    tables = []
    for table, sql in db.execute("select name, sql from sqlite_master where type = 'table' order by rowid"):
        info = list(db.execute(f"pragma table_info({table})"))
        if not any(row[1] == "sync_state" for row in info):
            continue
        columns = []
        for _, name, sql_type, notnull, default, pk in info:
            columns.append((name, sql_type.upper(), bool(notnull or pk), default))
        tables.append((table, sql, columns))
    return tables


def render(tables):
    out = [
        "// GENERATO da tools/codegen/generate_records.py a partire da Persistence/Migrations/*.sql.",
        "// NON MODIFICARE A MANO: cambia la migrazione (nuova versione) e rigenera.",
        "// swiftlint:disable all",
        "",
        "import Foundation",
        "import GRDB",
        "import JevCore",
        "import JevDomain",
        "",
    ]
    names = []
    for table, sql, columns in tables:
        name = type_name(table)
        names.append(name)
        domain = [c for c in columns if c[0] not in SYNC_COLUMNS and c[0] != "id"]
        fields = []  # (camel, swift type incl. optional, column, default)
        for column, sql_type, notnull, default in domain:
            base = swift_type(table, column, sql_type, sql)
            full = base if notnull else base + "?"
            dflt = swift_default(base, default)
            if dflt is None and not notnull:
                dflt = "nil"
            fields.append((camel(column), full, column, dflt))

        out.append(f"/// Riga della tabella `{table}` (fatto sincronizzato).")
        out.append(f"public struct {name}: SyncedRecord, Equatable {{")
        out.append(f'    public static let databaseTableName = "{table}"')
        out.append("")
        out.append("    public var id: UUID")
        for f in fields:
            out.append(f"    public var {f[0]}: {f[1]}")
        out.append("    public var createdAt: Date")
        out.append("    public var updatedAt: Date")
        out.append("    public var deletedAt: Date?")
        out.append("    public var originDeviceId: UUID?")
        out.append("    public var serverUpdatedAt: Date?")
        out.append("    public var syncState: RecordSyncState")
        out.append("")
        params = ["id: UUID"]
        for f in fields:
            params.append(f"{f[0]}: {f[1]}" + (f" = {f[3]}" if f[3] is not None else ""))
        params += [
            "createdAt: Date",
            "updatedAt: Date",
            "deletedAt: Date? = nil",
            "originDeviceId: UUID? = nil",
            "serverUpdatedAt: Date? = nil",
            "syncState: RecordSyncState = .pending",
        ]
        out.append("    public init(")
        out.append(",\n".join(f"        {p}" for p in params))
        out.append("    ) {")
        out.append("        self.id = id")
        for f in fields:
            out.append(f"        self.{f[0]} = {f[0]}")
        for p in ["createdAt", "updatedAt", "deletedAt", "originDeviceId", "serverUpdatedAt", "syncState"]:
            out.append(f"        self.{p} = {p}")
        out.append("    }")
        out.append("")
        out.append("    public enum CodingKeys: String, CodingKey, CaseIterable {")
        out.append("        case id")
        for f in fields:
            out.append(f'        case {f[0]} = "{f[2]}"' if f[0] != f[2] else f"        case {f[0]}")
        out.append('        case createdAt = "created_at"')
        out.append('        case updatedAt = "updated_at"')
        out.append('        case deletedAt = "deleted_at"')
        out.append('        case originDeviceId = "origin_device_id"')
        out.append('        case serverUpdatedAt = "server_updated_at"')
        out.append('        case syncState = "sync_state"')
        out.append("    }")
        out.append("")
        out.append("    public static var databaseColumnNames: [String] { CodingKeys.allCases.map(\\.rawValue) }")
        out.append("}")
        out.append("")

    out.append("/// Tutti i tipi di record sincronizzati, nell'ordine di creazione delle tabelle")
    out.append("/// (i genitori prima dei figli: è anche l'ordine di push e pull, DATA_MODEL §5).")
    out.append("public enum SyncedTables {")
    out.append("    public static let all: [any SyncedRecord.Type] = [")
    out.append(",\n".join(f"        {n}.self" for n in names))
    out.append("    ]")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    text = render(load_schema())
    if "--check" in sys.argv:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != text:
            sys.exit(f"{OUTPUT.relative_to(ROOT)} non è aggiornato: esegui tools/codegen/generate_records.py")
        print("ok: record generati aggiornati")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text)
    print(f"scritto {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
