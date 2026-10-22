#!/usr/bin/env python3
"""
Command-line helper for the X-Plane 12 Web API, used to discover and verify ToLiss mappings.
Standard library only. Run it on the PC with X-Plane (default 127.0.0.1:8086) or point it at the
relay from any machine with --host/--port.

  xp.py dump  [--grep REGEX] [--out DIR]     dump datarefs/commands matching REGEX to text files
  xp.py get   NAME [--index I]               print a dataref value
  xp.py watch NAME [NAME...] [--interval S]  poll datarefs and print what changes (flip a switch
                                             in the sim and see which array index moves)
  xp.py set   NAME VALUE [--index I]         write a dataref (element) value
  xp.py cmd   NAME [--duration S]            fire a command

Examples:
  xp.py dump --grep "OHPLightSwitches|lightcommands"
  xp.py watch AirbusFBW/OHPLightSwitches
  xp.py set AirbusFBW/OHPLightSwitches 2 --index 7
  xp.py cmd toliss_airbus/lightcommands/NSSignUp
"""
import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class XPlane:
    def __init__(self, host, port):
        self.base = f"http://{host}:{port}/api/v2"
        self._dataref_ids = {}
        self._command_ids = {}

    def _request(self, method, path, query=None, body=None):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            sys.exit(f"HTTP {error.code} en {method} {path}: {detail}")
        except urllib.error.URLError as error:
            sys.exit(f"No se pudo conectar con {self.base}: {error.reason}")
        return json.loads(raw) if raw else None

    def datarefs(self):
        return self._request("GET", "/datarefs")["data"]

    def commands(self):
        return self._request("GET", "/commands")["data"]

    def dataref_id(self, name):
        if name not in self._dataref_ids:
            rows = self._request("GET", "/datarefs", {"filter[name]": name})["data"]
            match = next((row for row in rows if row["name"] == name), None)
            if match is None:
                sys.exit(f"X-Plane no conoce el dataref '{name}'. ¿Está cargado el avión?")
            self._dataref_ids[name] = match["id"]
        return self._dataref_ids[name]

    def command_id(self, name):
        if name not in self._command_ids:
            rows = self._request("GET", "/commands", {"filter[name]": name})["data"]
            match = next((row for row in rows if row["name"] == name), None)
            if match is None:
                sys.exit(f"X-Plane no conoce el comando '{name}'.")
            self._command_ids[name] = match["id"]
        return self._command_ids[name]

    def get(self, name, index=None):
        query = {"index": index} if index is not None else None
        return self._request("GET", f"/datarefs/{self.dataref_id(name)}/value", query)["data"]

    def set(self, name, value, index=None):
        query = {"index": index} if index is not None else None
        self._request("PATCH", f"/datarefs/{self.dataref_id(name)}/value", query, {"data": value})

    def activate(self, name, duration=0.0):
        self._request("POST", f"/command/{self.command_id(name)}/activate", None, {"duration": duration})


def parse_value(text):
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return text


def cmd_dump(xp, args):
    import os
    pattern = re.compile(args.grep, re.IGNORECASE) if args.grep else None
    os.makedirs(args.out, exist_ok=True)
    datarefs = [d for d in xp.datarefs() if not pattern or pattern.search(d["name"])]
    commands = [c for c in xp.commands() if not pattern or pattern.search(c["name"])]
    with open(os.path.join(args.out, "datarefs.txt"), "w", encoding="utf-8") as handle:
        for row in sorted(datarefs, key=lambda r: r["name"]):
            flag = "rw" if row.get("is_writable") else "ro"
            handle.write(f"{row['name']}\t{row.get('value_type')}\t{flag}\n")
    with open(os.path.join(args.out, "commands.txt"), "w", encoding="utf-8") as handle:
        for row in sorted(commands, key=lambda r: r["name"]):
            handle.write(f"{row['name']}\t{row.get('description') or ''}\n")
    print(f"{len(datarefs)} datarefs y {len(commands)} comandos escritos en {args.out}/")


def cmd_get(xp, args):
    print(json.dumps(xp.get(args.name, args.index)))


def cmd_watch(xp, args):
    previous = {name: xp.get(name) for name in args.names}
    for name, value in previous.items():
        print(f"{time.strftime('%H:%M:%S')}  {name} = {json.dumps(value)}")
    print("Mueve los controles en el simulador. Ctrl+C para salir.")
    try:
        while True:
            time.sleep(args.interval)
            for name in args.names:
                current = xp.get(name)
                before = previous[name]
                if current == before:
                    continue
                stamp = time.strftime("%H:%M:%S")
                if isinstance(current, list) and isinstance(before, list) and len(current) == len(before):
                    for index, (old, new) in enumerate(zip(before, current)):
                        if old != new:
                            print(f"{stamp}  {name}[{index}]  {old} -> {new}")
                else:
                    print(f"{stamp}  {name}  {json.dumps(before)} -> {json.dumps(current)}")
                previous[name] = current
    except KeyboardInterrupt:
        pass


def cmd_set(xp, args):
    xp.set(args.name, parse_value(args.value), args.index)
    print(f"OK  {args.name}{'[%d]' % args.index if args.index is not None else ''} = {args.value}")


def cmd_cmd(xp, args):
    xp.activate(args.name, args.duration)
    print(f"OK  {args.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8086)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("dump"); p.add_argument("--grep"); p.add_argument("--out", default="dump"); p.set_defaults(fn=cmd_dump)
    p = sub.add_parser("get"); p.add_argument("name"); p.add_argument("--index", type=int); p.set_defaults(fn=cmd_get)
    p = sub.add_parser("watch"); p.add_argument("names", nargs="+"); p.add_argument("--interval", type=float, default=0.2); p.set_defaults(fn=cmd_watch)
    p = sub.add_parser("set"); p.add_argument("name"); p.add_argument("value"); p.add_argument("--index", type=int); p.set_defaults(fn=cmd_set)
    p = sub.add_parser("cmd"); p.add_argument("name"); p.add_argument("--duration", type=float, default=0.0); p.set_defaults(fn=cmd_cmd)

    args = parser.parse_args()
    args.fn(XPlane(args.host, args.port), args)


if __name__ == "__main__":
    main()
