#!/usr/bin/env python3
"""Allinea App/Resources/Localizable.xcstrings con le stringhe dell'interfaccia (ADR-015).

Xcode estrae da solo le stringhe del target app, non quelle dei package (Features,
DesignSystem). Questo script cerca le chiavi italiane nei sorgenti Swift e aggiunge al catalogo
quelle mancanti, con `extractionState: manual`. Non rimuove nulla.

Riconosce i letterali senza interpolazione passati a: Text, Button, Label, Toggle, Picker,
TextField, Tab, navigationTitle, accessibilityLabel, StepTitle (anche `subtitle:`),
JevSelectionCard (anche `subtitle:`), JevChip, JevInlineNotice, NumberField (`label:`/`unit:`),
più i `case ...: "..."` delle estensioni di DisplayNames. Le chiavi con interpolazione
(es. "%lld giorni") vanno aggiunte a mano quando servirà tradurle.

Uso:  python3 -I tools/l10n/sync_strings.py           (aggiorna il catalogo)
      python3 -I tools/l10n/sync_strings.py --check   (CI: fallisce se mancano chiavi)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
SOURCES = [
    ROOT / "App",
    ROOT / "Packages/JevKit/Sources/Features",
    ROOT / "Packages/JevKit/Sources/DesignSystem",
]

LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALLS = [
    rf'\b(?:Text|Button|Label|Toggle|Picker|TextField|Tab|StepTitle|JevSelectionCard|JevChip|JevInlineNotice)\(\s*{LITERAL}',
    rf'\.(?:navigationTitle|accessibilityLabel)\(\s*(?:Text\()?{LITERAL}',
    rf'\b(?:subtitle|label|unit):\s*{LITERAL}',
    rf'\bcase\s+[^:\n]+:\s*{LITERAL}\s*$',
    rf'\bdefault:\s*{LITERAL}\s*$',
    rf':\s*LocalizedStringKey\s*=\s*{LITERAL}',
    rf'\?\s*{LITERAL}\s*:\s*{LITERAL}',
]


def keys_in(text):
    found = set()
    for pattern in CALLS:
        for match in re.finditer(pattern, text, flags=re.MULTILINE):
            for group in match.groups():
                if group is None:
                    continue
                if "\\(" in group or not group.strip():
                    continue  # interpolazione o stringa vuota
                found.add(group.encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
    return found


def collect():
    keys, symbols = set(), set()
    for base in SOURCES:
        for path in base.rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            # Le stringhe "verbatim" e gli identificatori di accessibilità non sono chiavi.
            text = re.sub(r'Text\(verbatim:\s*' + LITERAL + r'\)', "", text)
            text = re.sub(r'accessibilityIdentifier\(\s*' + LITERAL + r'\s*\)', "", text)
            keys |= keys_in(text)
            # I nomi dei simboli SF (anche dentro un ternario) non sono testo da tradurre.
            for line in text.splitlines():
                if "systemName:" in line:
                    symbols |= set(re.findall(LITERAL, line.split("systemName:", 1)[1]))
    return keys - symbols


def main():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    missing = sorted(k for k in collect() if k not in strings)
    if "--check" in sys.argv:
        if missing:
            print("Chiavi mancanti nello String Catalog (esegui tools/l10n/sync_strings.py):")
            print("\n".join(f"  - {k}" for k in missing))
            sys.exit(1)
        print(f"ok: {len(strings)} chiavi nel catalogo, nessuna mancante")
        return
    for key in missing:
        strings[key] = {"extractionState": "manual"}
    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"aggiunte {len(missing)} chiavi")


if __name__ == "__main__":
    main()
