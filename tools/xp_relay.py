#!/usr/bin/env python3
"""
Relay the X-Plane 12 Web API to the LAN.

X-Plane's built-in web server (REST + WebSocket, port 8086) only accepts connections from the
same machine. This script listens on all interfaces (default port 8087) and forwards raw TCP to
127.0.0.1:8086, which is enough for both HTTP and WebSocket traffic. Standard library only.

Run it on the PC that runs X-Plane:

    python3 xp_relay.py

Then point the iPad app at <IP of this PC>:8087. Allow the port in the Windows/macOS firewall.
"""
import argparse
import asyncio
import os
import re
import socket
import sys

# Built as XPRelay.exe (PyInstaller) the window opens with a double click: keep it open on
# errors so the message can be read.
FROZEN = getattr(sys, "frozen", False)

HTTP_METHODS = (b"GET ", b"POST ", b"PATCH ", b"PUT ", b"DELETE ", b"OPTIONS ", b"HEAD ")
HOST_HEADER = re.compile(rb"\r\nHost: [^\r\n]*", re.IGNORECASE)


def rewrite_host(chunk: bytes, upstream: str) -> bytes:
    """Make the request look local to X-Plane in case it validates the Host header."""
    if chunk.startswith(HTTP_METHODS):
        return HOST_HEADER.sub(b"\r\nHost: " + upstream.encode(), chunk, count=1)
    return chunk


async def pipe(reader, writer, transform=None):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(transform(data) if transform else data)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError, asyncio.CancelledError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(client_reader, client_writer, args):
    peer = client_writer.get_extra_info("peername") or ("?", 0)
    try:
        xp_reader, xp_writer = await asyncio.open_connection(args.xplane_host, args.xplane_port)
    except OSError as error:
        print(f"[relay] {peer[0]}:{peer[1]} -> X-Plane no responde en "
              f"{args.xplane_host}:{args.xplane_port} ({error}). ¿Está X-Plane 12.1.4+ arrancado?")
        client_writer.close()
        return
    print(f"[relay] conexión desde {peer[0]}:{peer[1]}")
    upstream = f"{args.xplane_host}:{args.xplane_port}"
    transform = None if args.no_rewrite_host else (lambda chunk: rewrite_host(chunk, upstream))
    await asyncio.gather(
        pipe(client_reader, xp_writer, transform),
        pipe(xp_reader, client_writer),
    )
    print(f"[relay] cerrada {peer[0]}:{peer[1]}")


def local_ips():
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except socket.gaierror:
        pass
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("10.255.255.255", 1))
        ips.add(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    return sorted(ip for ip in ips if not ip.startswith("127."))


async def main():
    parser = argparse.ArgumentParser(description="Expose the X-Plane Web API on the LAN.")
    parser.add_argument("--listen", default="0.0.0.0", help="interface to listen on (default: all)")
    parser.add_argument("--port", type=int, default=8087, help="LAN port (default: 8087)")
    parser.add_argument("--xplane-host", default="127.0.0.1")
    parser.add_argument("--xplane-port", type=int, default=8086)
    parser.add_argument("--no-rewrite-host", action="store_true",
                        help="forward the Host header untouched")
    args = parser.parse_args()

    try:
        server = await asyncio.start_server(lambda r, w: handle(r, w, args), args.listen, args.port)
    except OSError as error:
        print(f"[relay] No puedo usar el puerto {args.port} ({error}).")
        print("[relay] ¿Hay otra ventana del enlace abierta? Ciérrala y vuelve a abrir esta.")
        raise SystemExit(1)
    ips = local_ips() or ["<IP de este PC>"]
    print("=" * 60)
    print("  Enlace X-Plane -> iPad (A320 Overhead)")
    print("=" * 60)
    print(f"[relay] escuchando en {args.listen}:{args.port} -> X-Plane {args.xplane_host}:{args.xplane_port}")
    for ip in ips:
        print(f"[relay] en el iPad pon:  {ip}   puerto {args.port}")
    print("[relay] Deja esta ventana abierta mientras vuelas. Para salir, ciérrala o pulsa Ctrl+C.")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    if os.name == "nt":
        os.system("title Enlace X-Plane - A320 Overhead")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    except SystemExit:
        if FROZEN:
            input("Pulsa Intro para cerrar...")
        raise
