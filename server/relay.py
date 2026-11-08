#!/usr/bin/env python3
"""Everdeck relay server — a dumb WebSocket message passer.

Run it:
    python3 relay.py [--host 0.0.0.0] [--port 8765]
    (needs the `websockets` package: pip install websockets,
     or use the bundled venv: .venv/bin/python relay.py)

Protocol (JSON text frames):
  - A client connects and sends {"t": "create"}.
    Relay replies {"t": "room", "code": "XXXXX"} and waits.
  - A second client sends {"t": "join", "code": "XXXXX"}.
    If the room exists, relay replies {"t": "joined"} to the guest and
    {"t": "peer_joined"} to the host, and the two are paired.
    If not, relay replies {"t": "error", "msg": "no such room"}.
  - Once paired, EVERY further message from either side is forwarded
    to the peer verbatim. The relay has no game logic and never looks
    inside game messages.
  - If one side disconnects, the relay sends {"t": "peer_left"} to the
    other side and closes the room.
"""

import argparse
import asyncio
import json
import secrets

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

# Unambiguous alphabet: no 0/O, 1/I/L.
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LEN = 5

rooms = {}  # code -> host websocket (waiting) ; paired rooms -> code in `pairs`
pairs = {}  # websocket -> peer websocket


def new_code():
    while True:
        code = "".join(secrets.choice(ALPHABET) for _ in range(CODE_LEN))
        if code not in rooms:
            return code


async def send_json(ws, obj):
    await ws.send(json.dumps(obj))


async def handler(ws):
    code = None
    try:
        async for raw in ws:
            if ws in pairs:
                # Paired: forward verbatim to the peer.
                peer = pairs[ws]
                try:
                    await peer.send(raw)
                except ConnectionClosed:
                    break
                continue
            # Not paired yet: only room control messages are handled.
            try:
                msg = json.loads(raw)
            except (ValueError, TypeError):
                await send_json(ws, {"t": "error", "msg": "bad json"})
                continue
            t = msg.get("t")
            if t == "create":
                code = new_code()
                rooms[code] = ws
                await send_json(ws, {"t": "room", "code": code})
            elif t == "join":
                want = str(msg.get("code", "")).upper()
                host = rooms.pop(want, None)
                if host is None:
                    await send_json(ws, {"t": "error", "msg": "no such room"})
                    continue
                code = want
                pairs[ws] = host
                pairs[host] = ws
                await send_json(ws, {"t": "joined", "code": code})
                await send_json(host, {"t": "peer_joined", "code": code})
            else:
                await send_json(ws, {"t": "error", "msg": "not paired"})
    except ConnectionClosed:
        pass
    finally:
        # Clean up: drop a waiting room, or notify the paired peer.
        if code is not None and rooms.get(code) is ws:
            rooms.pop(code, None)
        peer = pairs.pop(ws, None)
        if peer is not None:
            pairs.pop(peer, None)
            try:
                await send_json(peer, {"t": "peer_left"})
            except ConnectionClosed:
                pass


async def main():
    ap = argparse.ArgumentParser(description="Everdeck relay server")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    async with serve(handler, args.host, args.port):
        print(f"Everdeck relay listening on ws://{args.host}:{args.port}")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
