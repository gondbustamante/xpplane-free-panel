#!/usr/bin/env python3
"""Validate mapping/**/*.json against the schema documented in docs/MAPPING.md and print a status table."""
import glob
import json
import os
import sys

KINDS = {"toggle2": 2, "toggle3": 3, "korry": None}
COLORS = {"amber", "green", "white", "blue"}


def check_binding(binding, where, positions, errors):
    if not isinstance(binding, dict) or "dataref" not in binding:
        errors.append(f"{where}: binding sin 'dataref'")
        return
    if "index" in binding and (not isinstance(binding["index"], int) or binding["index"] < 0):
        errors.append(f"{where}: 'index' debe ser entero >= 0")
    if "values" in binding and len(binding["values"]) != len(positions):
        errors.append(f"{where}: 'values' tiene {len(binding['values'])} entradas y 'positions' {len(positions)}")


def validate(path):
    errors = []
    with open(path, encoding="utf-8") as handle:
        panel = json.load(handle)
    for key in ("id", "title", "controls"):
        if key not in panel:
            errors.append(f"falta '{key}' en el subpanel")
    rows = []
    seen = set()
    for control in panel.get("controls", []):
        cid = control.get("id", "<sin id>")
        where = f"{cid}"
        if cid in seen:
            errors.append(f"{where}: id duplicado")
        seen.add(cid)
        for key in ("label", "kind", "positions", "col", "row"):
            if key not in control:
                errors.append(f"{where}: falta '{key}'")
        kind = control.get("kind")
        positions = control.get("positions", [])
        if kind not in KINDS:
            errors.append(f"{where}: kind '{kind}' no soportado")
        elif KINDS[kind] and len(positions) != KINDS[kind]:
            errors.append(f"{where}: {kind} necesita {KINDS[kind]} posiciones, tiene {len(positions)}")
        for name in ("state", "write"):
            if name in control:
                check_binding(control[name], f"{where}.{name}", positions, errors)
        if "state" not in control and "commands" not in control:
            errors.append(f"{where}: necesita 'state' o 'commands'")
        for half in ("top", "bottom"):
            lamp = (control.get("lamps") or {}).get(half)
            if lamp and lamp.get("color") not in COLORS:
                errors.append(f"{where}.lamps.{half}: color '{lamp.get('color')}' no válido")
        state = control.get("state") or {}
        target = f"{state.get('dataref', '-')}" + (f"[{state['index']}]" if "index" in state else "")
        rows.append((cid, kind, "/".join(positions), target, "sí" if control.get("verified") else "NO"))
    return panel, rows, errors


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mapping")
    files = sorted(glob.glob(os.path.join(root, "**", "*.json"), recursive=True))
    if not files:
        sys.exit("No hay archivos de mapeo.")
    failed = False
    total = verified = 0
    for path in files:
        panel, rows, errors = validate(path)
        print(f"\n== {panel.get('title', '?')}  ({os.path.relpath(path)})")
        for row in rows:
            print("  {:<22} {:<8} {:<18} {:<36} verificado: {}".format(*row))
            total += 1
            verified += row[4] == "sí"
        for error in errors:
            print(f"  ERROR: {error}")
            failed = True
    print(f"\n{total} controles, {verified} verificados, {total - verified} pendientes.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
