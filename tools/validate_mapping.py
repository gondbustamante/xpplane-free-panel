#!/usr/bin/env python3
"""Validate the mapping files against the schemas documented in docs/MAPPING.md and print a status table.

mapping/layout.json        panel groups and flight phases
mapping/<group>/*.json     one subpanel per file (toggle2 | toggle3 | korry | rotary controls)
mapping/fcu/*.json         the Flight Control Unit (selectors + buttons), its own schema
mapping/procedures/*.json  flows and checklists; sensed items must name real controls and positions
mapping/guide/*.json       learn-mode explanations; must name real controls, positions and panels
mapping/exercises/*.json   timed exercises over the procedures
mapping/turnaround/*.json  ground-time templates: milestones before off-blocks
mapping/reference/*.txt    xp.py dump of ToLiss; every AirbusFBW/ and toliss_airbus/ name must appear there
"""
import glob
import json
import os
import sys

KINDS = {"toggle2": 2, "toggle3": 3, "korry": None, "rotary": None, "knob": None, "display": None,
         "lever": None, "dualKnob": None}
DECORATIONS = {"line", "arrow", "bracket", "box", "text", "divider"}
GUARD_STYLES = {"cage", "red"}
KORRY_STYLES = {"round", "fire", "key", "keyRed"}
COLORS = {"amber", "green", "white", "blue", "red"}
FCU_FORMATS = {"speed", "mach", "heading", "altitude", "verticalSpeed", "flightPathAngle"}
FCU_BUTTON_KINDS = {"push", "toggle"}
DUMP_PREFIXES = ("AirbusFBW/", "toliss_airbus/")
# Panels drawn by the app itself, without a mapping file.
BUILTIN_PANELS = {"mcdu", "camera"}
# MCDU page keys the learn mode can explain, as "mcdu.<ToLiss command suffix>".
MCDU_KEYS = {"DirTo", "Prog", "Perf", "Init", "Data", "Fpln", "RadNav", "FuelPred", "SecFpln", "ATC", "Menu",
             "Airport"}


# ---------------------------------------------------------------- overhead-style subpanels

def check_binding(binding, where, positions, errors):
    if not isinstance(binding, dict) or "dataref" not in binding:
        errors.append(f"{where}: binding sin 'dataref'")
        return
    if "index" in binding and (not isinstance(binding["index"], int) or binding["index"] < 0):
        errors.append(f"{where}: 'index' debe ser entero >= 0")
    if "values" in binding and len(binding["values"]) != len(positions):
        errors.append(f"{where}: 'values' tiene {len(binding['values'])} entradas y 'positions' {len(positions)}")
    for raw, pos in (binding.get("aliases") or {}).items():
        if not isinstance(pos, int) or pos >= len(positions):
            errors.append(f"{where}: alias '{raw}' apunta a una posición inexistente")


def validate_subpanel(panel, errors):
    rows = []
    seen = set()
    if "group" not in panel:
        errors.append("falta 'group' en el subpanel")
    frame = panel.get("frame")
    if frame is not None and not all(k in frame for k in ("x", "y", "w", "h")):
        errors.append("'frame' necesita x, y, w, h")
    for deco in panel.get("decorations", []) or []:
        if deco.get("type") not in DECORATIONS:
            errors.append(f"decoración de tipo '{deco.get('type')}' no soportada")
        if deco.get("type") in ("line", "divider", "bracket") and len(deco.get("points") or []) < 2:
            errors.append(f"decoración '{deco.get('type')}' necesita al menos 2 'points'")
        if deco.get("type") in ("arrow", "box", "text") and not deco.get("at"):
            errors.append(f"decoración '{deco.get('type')}' necesita 'at'")
    for control in panel.get("controls", []):
        cid = control.get("id", "<sin id>")
        where = f"{cid}"
        if cid in seen:
            errors.append(f"{where}: id duplicado")
        seen.add(cid)
        for key in ("label", "kind", "positions"):
            if key not in control:
                errors.append(f"{where}: falta '{key}'")
        if frame is not None:
            if "x" not in control or "y" not in control:
                errors.append(f"{where}: el subpanel tiene 'frame', el control necesita 'x' e 'y'")
            elif not (0 <= control["x"] <= frame["w"] and 0 <= control["y"] <= frame["h"]):
                errors.append(f"{where}: ({control['x']}, {control['y']}) cae fuera del frame {frame['w']}x{frame['h']}")
        elif "col" not in control or "row" not in control:
            errors.append(f"{where}: sin 'frame' el control necesita 'col' y 'row'")
        if control.get("guardStyle") and control["guardStyle"] not in GUARD_STYLES:
            errors.append(f"{where}: guardStyle '{control['guardStyle']}' no válido")
        if control.get("style") and control["style"] not in KORRY_STYLES:
            errors.append(f"{where}: style '{control['style']}' no válido")
        if control.get("kind") == "knob" and not control.get("range"):
            errors.append(f"{where}: un knob necesita 'range'")
        if control.get("kind") == "lever" and len(control.get("positions", [])) < 2:
            errors.append(f"{where}: una lever necesita al menos 2 posiciones")
        if control.get("kind") == "dualKnob":
            cmds = control.get("commands") or {}
            if not all(k in cmds for k in ("up", "down")):
                errors.append(f"{where}: un dualKnob necesita al menos up y down (upSmall/downSmall para el centro)")
        if control.get("format") == "baro" and not control.get("baro"):
            errors.append(f"{where}: el formato 'baro' necesita 'baro' con 'std' y 'unit'")
        if control.get("baro") and not all(k in control["baro"] for k in ("std", "unit")):
            errors.append(f"{where}: 'baro' necesita 'std' y 'unit'")
        kind = control.get("kind")
        positions = control.get("positions", [])
        if kind not in KINDS:
            errors.append(f"{where}: kind '{kind}' no soportado")
        elif KINDS[kind] and len(positions) != KINDS[kind]:
            errors.append(f"{where}: {kind} necesita {KINDS[kind]} posiciones, tiene {len(positions)}")
        if kind == "rotary" and len(positions) < 2:
            errors.append(f"{where}: rotary necesita al menos 2 posiciones")
        if control.get("guarded") and kind != "korry":
            errors.append(f"{where}: 'guarded' solo aplica a korry")
        for name in ("state", "write"):
            if name in control:
                check_binding(control[name], f"{where}.{name}", positions, errors)
        if "state" not in control and "commands" not in control and kind != "display":
            errors.append(f"{where}: necesita 'state' o 'commands'")
        for half in ("top", "bottom"):
            lamp = (control.get("lamps") or {}).get(half)
            if lamp and lamp.get("color") not in COLORS:
                errors.append(f"{where}.lamps.{half}: color '{lamp.get('color')}' no válido")
        state = control.get("state") or {}
        target = f"{state.get('dataref', '-')}" + (f"[{state['index']}]" if "index" in state else "")
        status = "sí" if control.get("verified") else "NO"
        if control.get("readOnly"):
            status += " (bloqueado)"
        rows.append((cid, kind, "/".join(positions), target, status))
    return rows


def names_in_subpanel(panel):
    datarefs, commands = set(), set()
    for control in panel.get("controls", []):
        for key in ("state", "write"):
            if key in control:
                datarefs.add(control[key]["dataref"])
        for half in ("top", "bottom"):
            lamp = (control.get("lamps") or {}).get(half)
            if lamp and lamp.get("dataref"):
                datarefs.add(lamp["dataref"])
        for key in ("std", "unit"):
            value = (control.get("baro") or {}).get(key)
            if value:
                datarefs.add(value)
        for key in ("up", "down", "press", "pull", "upSmall", "downSmall"):
            value = (control.get("commands") or {}).get(key)
            if value:
                commands.add(value)
    return datarefs, commands


# ---------------------------------------------------------------- FCU

def check_fcu_binding(binding, where, errors):
    if not isinstance(binding, dict) or "dataref" not in binding:
        errors.append(f"{where}: binding sin 'dataref'")
        return
    if "index" in binding and (not isinstance(binding["index"], int) or binding["index"] < 0):
        errors.append(f"{where}: 'index' debe ser entero >= 0")


def validate_fcu(panel, errors):
    rows = []
    seen = set()
    selector_ids = set()
    if "selectors" not in panel:
        errors.append("falta 'selectors' en el FCU")
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
        mode = "rueda: cmd" if "increase" in commands else "rueda: write"
        rows.append((sid, "selector", selector.get("format", "?"), value.get("dataref", "-"), mode, "sí" if selector.get("verified") else "NO"))

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


def names_in_fcu(panel):
    datarefs, commands = set(), set()
    if "available" in panel:
        datarefs.add(panel["available"]["dataref"])
    for selector in panel.get("selectors", []):
        for key in ("value", "alternateValue", "mode", "managed", "dashed", "write"):
            if key in selector:
                datarefs.add(selector[key]["dataref"])
        for key in ("increase", "decrease", "push", "pull"):
            value = (selector.get("commands") or {}).get(key)
            if value:
                commands.add(value)
    for button in panel.get("buttons", []):
        if button.get("command"):
            commands.add(button["command"])
        for key in ("lit", "state"):
            if key in button:
                datarefs.add(button[key]["dataref"])
    return datarefs, commands


# ---------------------------------------------------------------- shared

def validate(path):
    errors = []
    with open(path, encoding="utf-8") as handle:
        panel = json.load(handle)
    for key in ("id", "title"):
        if key not in panel:
            errors.append(f"falta '{key}' en el panel")
    is_fcu = "selectors" in panel or os.path.basename(os.path.dirname(path)) == "fcu"
    if is_fcu:
        rows = validate_fcu(panel, errors)
        names = names_in_fcu(panel)
        group = "fcu"
    else:
        if "controls" not in panel:
            errors.append("falta 'controls' en el subpanel")
        rows = validate_subpanel(panel, errors)
        names = names_in_subpanel(panel)
        group = panel.get("group")
    return panel, rows, errors, names, group


def validate_layout(root, panel_ids, panel_ids_by_group):
    path = os.path.join(root, "layout.json")
    if not os.path.exists(path):
        return ["falta mapping/layout.json"], set()
    with open(path, encoding="utf-8") as handle:
        layout = json.load(handle)
    errors = []
    group_ids = {g["id"] for g in layout.get("groups", [])}
    for phase in layout.get("phases", []):
        for sub in phase.get("subpanels", []):
            if sub not in panel_ids and sub not in BUILTIN_PANELS:
                errors.append(f"layout.json: la fase '{phase.get('id')}' referencia el panel inexistente '{sub}'")
    for group in (layout.get("canvases") or {}):
        if group not in group_ids:
            errors.append(f"layout.json: 'canvases' usa el grupo no declarado '{group}'")
    for group, arrangement in (layout.get("arrangements") or {}).items():
        if group not in group_ids:
            errors.append(f"layout.json: 'arrangements' usa el grupo no declarado '{group}'")
        placed = []
        for column in arrangement.get("columns", []):
            for row in column:
                placed.extend(row)
        for sub in placed:
            if sub not in panel_ids:
                errors.append(f"layout.json: la disposición de '{group}' coloca el panel inexistente '{sub}'")
        for sub in {s for s in placed if placed.count(s) > 1}:
            errors.append(f"layout.json: la disposición de '{group}' coloca '{sub}' más de una vez")
        missing = sorted(p for p in panel_ids_by_group.get(group, set()) if p not in placed)
        if missing:
            print(f"AVISO: la disposición de '{group}' no coloca: {', '.join(missing)} (se dibujarán debajo)")
    return errors, group_ids


PROCEDURE_KINDS = {"flow", "checklist"}


def validate_procedures(root, controls, panel_ids):
    """Flows and checklists: unique ids, known phases, real controls, positions and panels."""
    errors, seen = [], set()
    phases = set()
    layout_path = os.path.join(root, "layout.json")
    if os.path.exists(layout_path):
        with open(layout_path, encoding="utf-8") as handle:
            phases = {phase.get("id") for phase in json.load(handle).get("phases", [])}
    paths = sorted(glob.glob(os.path.join(root, "procedures", "*.json")))
    count = sensed = 0
    for path in paths:
        name = os.path.relpath(path)
        with open(path, encoding="utf-8") as handle:
            book = json.load(handle)
        for procedure in book.get("procedures", []):
            pid = procedure.get("id")
            where = f"{name} · {pid}"
            if not pid or pid in seen:
                errors.append(f"{where}: id vacío o repetido")
            seen.add(pid)
            if procedure.get("kind") not in PROCEDURE_KINDS:
                errors.append(f"{where}: 'kind' debe ser flow o checklist")
            if not procedure.get("title"):
                errors.append(f"{where}: falta 'title'")
            if procedure.get("phase") and procedure["phase"] not in phases:
                errors.append(f"{where}: la fase '{procedure['phase']}' no está en layout.json")
            items = procedure.get("items", [])
            if not items:
                errors.append(f"{where}: sin ítems")
            for index, item in enumerate(items, 1):
                at = f"{where} #{index}"
                count += 1
                if not item.get("challenge") or not item.get("response"):
                    errors.append(f"{at}: faltan 'challenge' o 'response'")
                if not item.get("why"):
                    print(f"AVISO: {at}: sin 'why'")
                for panel in item.get("panels", []):
                    if panel not in panel_ids:
                        errors.append(f"{at}: el panel '{panel}' no existe")
                checks = item.get("checks", [])
                sensed += bool(checks)
                for check in checks:
                    control = controls.get(check.get("control"))
                    if control is None:
                        errors.append(f"{at}: el mando '{check.get('control')}' no existe")
                        continue
                    expect = check.get("expect") or []
                    if not expect:
                        errors.append(f"{at}: '{check['control']}' sin 'expect'")
                    for position in expect:
                        if position not in control.get("positions", []):
                            errors.append(f"{at}: '{check['control']}' no tiene la posición '{position}'"
                                          f" (posiciones: {control.get('positions')})")
    if paths:
        print(f"\nProcedimientos: {len(seen)} en {len(paths)} archivo(s), {count} ítems, {sensed} con detección automática.")
    return errors


def validate_guide(root, controls, panel_ids):
    """Explanations: known controls (panel, FCU or MCDU page key), known positions, one entry per control."""
    errors, explained = [], set()
    fcu_ids = set()
    for path in glob.glob(os.path.join(root, "fcu", "*.json")):
        with open(path, encoding="utf-8") as handle:
            fcu = json.load(handle)
        fcu_ids |= {item.get("id") for item in fcu.get("selectors", []) + fcu.get("buttons", [])}
    mcdu_ids = {f"mcdu.{key}" for key in MCDU_KEYS}
    paths = sorted(glob.glob(os.path.join(root, "guide", "*.json")))
    systems = 0
    for path in paths:
        name = os.path.relpath(path)
        with open(path, encoding="utf-8") as handle:
            book = json.load(handle)
        for system in book.get("systems", []):
            systems += 1
            if not system.get("id") or not system.get("title") or not system.get("summary"):
                errors.append(f"{name} · sistema '{system.get('id')}': faltan 'id', 'title' o 'summary'")
            for panel in system.get("panels", []):
                if panel not in panel_ids:
                    errors.append(f"{name} · sistema '{system.get('id')}': el panel '{panel}' no existe")
        for entry in book.get("explanations", []):
            ids = entry.get("controls") or []
            where = f"{name} · {', '.join(ids) or '<sin controles>'}"
            if not ids or not entry.get("what"):
                errors.append(f"{where}: faltan 'controls' o 'what'")
            for cid in ids:
                if cid in explained:
                    errors.append(f"{where}: '{cid}' ya tiene explicación")
                explained.add(cid)
                control = controls.get(cid)
                if control is None and cid not in fcu_ids and cid not in mcdu_ids:
                    errors.append(f"{where}: el mando '{cid}' no existe")
                    continue
                if control is not None:
                    for position in (entry.get("positions") or {}):
                        if position not in control.get("positions", []):
                            errors.append(f"{where}: '{cid}' no tiene la posición '{position}'"
                                          f" (posiciones: {control.get('positions')})")
    if paths:
        explainable = set(controls) | fcu_ids
        missing = sorted(explainable - explained)
        print(f"\nGuía: {systems} sistemas, {len(explained & explainable)} de {len(explainable)} mandos explicados"
              f" y {len(explained & mcdu_ids)} teclas del MCDU.")
        if missing:
            print(f"AVISO: sin explicación: {', '.join(missing)}")
    return errors


def validate_exercises(root):
    """Exercises: unique ids, existing procedures, a positive target time."""
    errors, seen = [], set()
    procedures = {}
    for path in glob.glob(os.path.join(root, "procedures", "*.json")):
        with open(path, encoding="utf-8") as handle:
            for procedure in json.load(handle).get("procedures", []):
                procedures[procedure.get("id")] = procedure
    paths = sorted(glob.glob(os.path.join(root, "exercises", "*.json")))
    for path in paths:
        name = os.path.relpath(path)
        with open(path, encoding="utf-8") as handle:
            book = json.load(handle)
        for exercise in book.get("exercises", []):
            eid = exercise.get("id")
            where = f"{name} · {eid}"
            if not eid or eid in seen:
                errors.append(f"{where}: id vacío o repetido")
            seen.add(eid)
            if not exercise.get("title"):
                errors.append(f"{where}: falta 'title'")
            if not isinstance(exercise.get("targetSeconds"), int) or exercise["targetSeconds"] <= 0:
                errors.append(f"{where}: 'targetSeconds' debe ser un entero positivo")
            ids = exercise.get("procedures") or []
            if not ids:
                errors.append(f"{where}: sin 'procedures'")
            for pid in ids + (exercise.get("setup") or []):
                if pid not in procedures:
                    errors.append(f"{where}: el procedimiento '{pid}' no existe")
            if "coldAndDark" in exercise and not isinstance(exercise["coldAndDark"], bool):
                errors.append(f"{where}: 'coldAndDark' debe ser true o false")
    if paths:
        print(f"\nEjercicios: {len(seen)}.")
    return errors


TURNAROUND_SERVICES = {"deboarding", "refuel", "boarding"}
TURNAROUND_EVENTS = {"out"}


def validate_turnarounds(root, controls):
    """Turnarounds: unique ids, existing procedures, known services and events."""
    errors, seen = [], set()
    procedures = set()
    for path in glob.glob(os.path.join(root, "procedures", "*.json")):
        with open(path, encoding="utf-8") as handle:
            procedures |= {p.get("id") for p in json.load(handle).get("procedures", [])}
    count = 0
    for path in sorted(glob.glob(os.path.join(root, "turnaround", "*.json"))):
        name = os.path.relpath(path)
        with open(path, encoding="utf-8") as handle:
            book = json.load(handle)
        for template in book.get("turnarounds", []):
            tid = template.get("id")
            if not tid or tid in seen:
                errors.append(f"{name} · {tid}: id vacío o repetido")
            seen.add(tid)
            ids = set()
            for milestone in template.get("milestones", []):
                count += 1
                where = f"{name} · {tid} · {milestone.get('id')}"
                if not milestone.get("id") or milestone["id"] in ids:
                    errors.append(f"{where}: id vacío o repetido")
                ids.add(milestone.get("id"))
                if not isinstance(milestone.get("minutes"), int):
                    errors.append(f"{where}: 'minutes' debe ser un entero (negativo antes de la salida)")
                for pid in milestone.get("procedures", []):
                    if pid not in procedures:
                        errors.append(f"{where}: el procedimiento '{pid}' no existe")
                if milestone.get("service") and milestone["service"] not in TURNAROUND_SERVICES:
                    errors.append(f"{where}: servicio '{milestone['service']}' desconocido")
                if milestone.get("event") and milestone["event"] not in TURNAROUND_EVENTS:
                    errors.append(f"{where}: evento '{milestone['event']}' desconocido")
                for check in milestone.get("checks", []):
                    control = controls.get(check.get("control"))
                    if control is None:
                        errors.append(f"{where}: el mando '{check.get('control')}' no existe")
                        continue
                    for position in check.get("expect") or []:
                        if position not in control.get("positions", []):
                            errors.append(f"{where}: '{check['control']}' no tiene la posición '{position}'")
                if not (milestone.get("procedures") or milestone.get("service") or milestone.get("event")
                        or milestone.get("checks") or milestone.get("manual")):
                    errors.append(f"{where}: necesita 'procedures', 'checks', 'service', 'event' o 'manual'")
    if seen:
        print(f"\nTurnarounds: {len(seen)} con {count} hitos.")
    return errors


def load_reference(root):
    """Names from mapping/reference/*.txt (xp.py dump), or None when no dump exists yet."""
    def read(name):
        path = os.path.join(root, "reference", name)
        if not os.path.exists(path):
            return None
        with open(path, encoding="utf-8") as handle:
            return {line.split("\t")[0].strip() for line in handle if line.strip()}
    return read("datarefs.txt"), read("commands.txt")


def print_rows(rows):
    for row in rows:
        cells = list(row)
        status = cells.pop()
        widths = [22, 9, 18, 36, 14]
        text = "  ".join(f"{str(cell):<{widths[i] if i < len(widths) else 12}}" for i, cell in enumerate(cells))
        print(f"  {text}  verificado: {status}")


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mapping")
    files = sorted(f for f in glob.glob(os.path.join(root, "**", "*.json"), recursive=True)
                   if os.path.basename(f) != "layout.json" and os.sep + "reference" + os.sep not in f
                   and os.sep + "procedures" + os.sep not in f and os.sep + "guide" + os.sep not in f
                   and os.sep + "exercises" + os.sep not in f and os.sep + "turnaround" + os.sep not in f)
    if not files:
        sys.exit("No hay archivos de mapeo.")
    ref_datarefs, ref_commands = load_reference(root)
    failed = False
    total = verified = 0
    panel_ids, groups_used, all_ids = set(), set(), {}
    panel_ids_by_group = {}
    used_datarefs, used_commands = set(), set()
    controls = {}
    for path in files:
        panel, rows, errors, (datarefs, commands), group = validate(path)
        for control in panel.get("controls", []):
            controls[control.get("id")] = control
        panel_ids.add(panel.get("id"))
        groups_used.add(group)
        panel_ids_by_group.setdefault(group, set()).add(panel.get("id"))
        used_datarefs |= datarefs
        used_commands |= commands
        print(f"\n== {panel.get('title', '?')}  ({os.path.relpath(path)})")
        print_rows(rows)
        for row in rows:
            total += 1
            verified += str(row[-1]).startswith("sí")
            if row[0] in all_ids:
                errors.append(f"{row[0]}: id repetido en {os.path.relpath(all_ids[row[0]])}")
            all_ids[row[0]] = path
        for error in errors:
            print(f"  ERROR: {error}")
            failed = True

    layout_errors, group_ids = validate_layout(root, panel_ids, panel_ids_by_group)
    for group in groups_used - group_ids - {None}:
        layout_errors.append(f"layout.json: el grupo '{group}' no está declarado en 'groups'")
    for error in layout_errors:
        print(f"ERROR: {error}")
        failed = True

    for error in validate_procedures(root, controls, panel_ids | BUILTIN_PANELS | {"fcu"}):
        print(f"ERROR: {error}")
        failed = True

    for error in validate_turnarounds(root, controls):
        print(f"ERROR: {error}")
        failed = True

    for error in validate_exercises(root):
        print(f"ERROR: {error}")
        failed = True

    for error in validate_guide(root, controls, panel_ids | BUILTIN_PANELS | {"fcu"}):
        print(f"ERROR: {error}")
        failed = True

    if ref_datarefs is None or ref_commands is None:
        print("\nSin volcado en mapping/reference/: ejecuta tools/xp.py dump para comprobar nombres contra ToLiss.")
    else:
        checkable_d = {n for n in used_datarefs if n.startswith(DUMP_PREFIXES)}
        checkable_c = {n for n in used_commands if n.startswith(DUMP_PREFIXES)}
        for name in sorted(checkable_d - ref_datarefs):
            print(f"ERROR: el dataref '{name}' no aparece en mapping/reference/datarefs.txt")
            failed = True
        for name in sorted(checkable_c - ref_commands):
            print(f"ERROR: el comando '{name}' no aparece en mapping/reference/commands.txt")
            failed = True
        skipped = len(used_datarefs - checkable_d) + len(used_commands - checkable_c)
        print(f"\nNombres comprobados contra el volcado: {len(checkable_d)} datarefs y {len(checkable_c)} comandos"
              + (f" ({skipped} nombres sim/* fuera del filtro del volcado, no comprobados)." if skipped else "."))
    print(f"{total} controles, {verified} verificados, {total - verified} pendientes.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
