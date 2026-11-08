# Everdeck relay server

A dumb WebSocket message passer for Everdeck online play. It pairs two
clients by a short room code and forwards their messages verbatim — no
game logic lives here.

## Run

```
python3 relay.py --host 0.0.0.0 --port 8765
```

Requires the `websockets` Python package (`pip install websockets`).
A ready-made virtualenv is bundled: `.venv/bin/python relay.py`.

The game client points at the relay through the `RELAY_URL` constant in
`game/scripts/net.gd` (default `ws://127.0.0.1:8765`) or the relay
address field on the Play Online screen.
