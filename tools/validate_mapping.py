#!/usr/bin/env python3
"""Validate mapping/**/*.json against the schemas documented in docs/MAPPING.md and print a status table.

mapping/overhead/*.json  one subpanel per file (toggle2 | toggle3 | korry controls)
mapping/fcu/*.json       the Flight Control Unit (selectors + buttons)
"""
import glob
import json
import os
import sys

KINDS = {"toggle2": 2, "toggle3": 3, "korry": None}
COLORS = {"amber", "green", "white", "blue"}
FCU_FORMATS = {"speed", "mach", "heading", "altitude", "verticalSpeed", "flightPathAngle"}
FCU_BUTTON_KINDS = {"push", "toggle"}


def check_binding(binding, where, positions, errors):
    if not isinstance(binding, dict) or "dataref" not in binding:
        errors.append(f"{where}: binding sin 'dataref'")
        return
    if "index" in binding and (not isinstance(binding["index"], int) or binding["index"] < 0):
        errors.append(f"{where}: 'index' debe ser entero >= 0")
    if "values" in binding and len(binding["values"]) != len(positions):
        errors.append(f"{where}: 'values' tiene {len(binding['values'])} entradas y 'positions' {len(positions)}")


def check_fcu_binding(binding, where, errors):
    if not isinstance(binding, dict) or "dataref" not in binding:
        errors.append(f"{where}: binding sin 'dataref'")
        return
    if "index" in binding and (not isinstance(binding["index"], int) or binding["index"] < 0):
        errors.append(f"{where}: 'index' debe ser entero >= 0")


def validate_overhead(panel, errors):
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
        if control.get("guarded") and kind != "korry":
            errors.append(f"{where}: 'guarded' solo aplica a korry")
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
    return rows


def validate_fcu(panel, errors):
    rows = []
    seen = set()
    selector_ids = set()
    if "available" in panel:
        check_fcu_binding(panel["available"], "available", errors)

    for selector in panel.get("selectors", []):
        sid = selector.get("id", "<sin id>")
        where = f"{sid}"
        if sid in seen:
            errors.append(f"{where}: id duplicado")
        seen.add(sid)
        selector_ids.add(sid)
        for key in ("label", "format", "value"):
            if key not in selector:
                errors.append(f"{where}: falta '{key}'")
        for key in ("format", "alternateFormat"):
            if key in selector and selector[key] not in FCU_FORMATS:
                errors.append(f"{where}: {key} '{selector[key]}' no soportado")
        for key in ("value", "alternateValue", "mode", "managed", "dashed", "write"):
            if key in selector:
                check_fcu_binding(selector[key], f"{where}.{key}", errors)
        for key in ("range", "alternateRange"):
            rng = selector.get(key)
            if rng is not None:
                if not isinstance(rng, dict) or "min" not in rng or "max" not in rng:
                    errors.append(f"{where}.{key}: necesita 'min' y 'max'")
                elif rng["min"] > rng["max"]:
                    errors.append(f"{where}.{key}: min > max")
        if "alternateLabel" in selector and "mode" not in selector:
            errors.append(f"{where}: 'alternateLabel' sin 'mode' nunca se mostrará")
        commands = selector.get("commands") or {}
        for key in commands:
            if key not in ("increase", "decrease", "push", "pull"):
                errors.append(f"{where}.commands: clave '{key}' desconocida")
        if ("increase" in commands) != ("decrease" in commands):
            errors.append(f"{where}.commands: 'increase' y 'decrease' van juntos")
        value = selector.get("value") or {}
        target = value.get("dataref", "-")
        mode = "rueda: cmd" if "increase" in commands else "rueda: write"
        rows.append((sid, "selector", selector.get("format", "?"), target, mode, "sí" if selector.get("verified") else "NO"))

    for button in panel.get("buttons", []):
        bid = button.get("id", "<sin id>")
        where = f"{bid}"
        if bid in seen:
            errors.append(f"{where}: id duplicado")
        seen.add(bid)
        for key in ("label", "column"):
            if key not in button:
                errors.append(f"{where}: falta '{key}'")
        column = button.get("column")
        if column is not None and column != "center" and column not in selector_ids:
            errors.append(f"{where}: column '{column}' no es un selector ni 'center'")
        kind = button.get("kind", "push")
        if kind not in FCU_BUTTON_KINDS:
            errors.append(f"{where}: kind '{kind}' no soportado")
        if kind == "push" and "command" not in button:
            errors.append(f"{where}: un botón 'push' necesita 'command'")
        if kind == "toggle":
            if "state" not in button:
                errors.append(f"{where}: un botón 'toggle' necesita 'state'")
            positions = button.get("positions") or []
            if len(positions) < 2:
                errors.append(f"{where}: un botón 'toggle' necesita al menos 2 'positions'")
            if "values" in button and len(button["values"]) != len(positions):
                errors.append(f"{where}: 'values' tiene {len(button['values'])} entradas y 'positions' {len(positions)}")
        for key in ("lit", "state"):
            if key in button:
                check_fcu_binding(button[key], f"{where}.{key}", errors)
        target = button.get("command") or (button.get("state") or {}).get("dataref", "-")
        lit = (button.get("lit") or {}).get("dataref", "")
        rows.append((bid, kind, button.get("label", "?"), target, f"luz: {lit}" if lit else "", "sí" if button.get("verified") else "NO"))
    return rows


def validate(path):
    errors = []
    with open(path, encoding="utf-8") as handle:
        panel = json.load(handle)
    for key in ("id", "title"):
        if key not in panel:
            errors.append(f"falta '{key}' en el panel")
    is_fcu = "selectors" in panel or os.path.basename(os.path.dirname(path)) == "fcu"
    if is_fcu:
        if "selectors" not in panel:
            errors.append("falta 'selectors' en el FCU")
        rows = validate_fcu(panel, errors)
    else:
        if "controls" not in panel:
            errors.append("falta 'controls' en el subpanel")
        rows = validate_overhead(panel, errors)
    return panel, rows, errors


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mapping")
    files = sorted(glob.glob(os.path.join(root, "**", "*.json"), recursive=True))
    if not files:
        sys.exit("No hay archivos de mapeo.")
    failed = False
    total = verified = 0
    all_ids = {}
    for path in files:
        panel, rows, errors = validate(path)
        print(f"\n== {panel.get('title', '?')}  ({os.path.relpath(path)})")
        for row in rows:
            cells = list(row)
            status = cells.pop()
            print("  " + "  ".join(f"{cell:<22}" if i == 0 else f"{cell:<30}" if i == 3 else f"{cell:<12}" for i, cell in enumerate(cells))
                  + f"  verificado: {status}")
            total += 1
            verified += status == "sí"
            if row[0] in all_ids:
                errors.append(f"{row[0]}: id repetido en {os.path.relpath(all_ids[row[0]])}")
            all_ids[row[0]] = path
        for error in errors:
            print(f"  ERROR: {error}")
            failed = True
    print(f"\n{total} controles, {verified} verificados, {total - verified} pendientes.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
