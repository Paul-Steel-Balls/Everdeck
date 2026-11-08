#!/usr/bin/env bash
# Sprint MP-1 net test harness.
# Starts the relay locally, runs two headless Godot instances (host +
# guest) through the handshake and scripted opening turns, then
# compares the public-state hashes in their result files.
#
# Usage: tests/run_net_test.sh
# Exit code 0 = PASS (handshake completed, hashes match, hidden hands
# stayed hidden on both sides).

set -u
GAME_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EVERDECK_DIR="$(cd "$GAME_DIR/.." && pwd)"
GODOT="${GODOT:-$HOME/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
PORT="${NETTEST_PORT:-8971}"
WORK="$(mktemp -d /tmp/everdeck-nettest-XXXXXX)"
echo "workdir: $WORK"

"$EVERDECK_DIR/server/.venv/bin/python" "$EVERDECK_DIR/server/relay.py" \
    --host 127.0.0.1 --port "$PORT" > "$WORK/relay.log" 2>&1 &
RELAY_PID=$!
trap 'kill $RELAY_PID 2>/dev/null' EXIT
sleep 1

timeout 180 "$GODOT" --headless --path "$GAME_DIR" res://tests/net_test_main.tscn -- \
    --role=host --relay="ws://127.0.0.1:$PORT" \
    --code-file="$WORK/code.txt" --result-file="$WORK/host.json" \
    > "$WORK/host.log" 2>&1 &
HOST_PID=$!

timeout 180 "$GODOT" --headless --path "$GAME_DIR" res://tests/net_test_main.tscn -- \
    --role=guest --relay="ws://127.0.0.1:$PORT" \
    --code-file="$WORK/code.txt" --result-file="$WORK/guest.json" \
    > "$WORK/guest.log" 2>&1 &
GUEST_PID=$!

wait $HOST_PID; HOST_RC=$?
wait $GUEST_PID; GUEST_RC=$?
echo "host rc=$HOST_RC guest rc=$GUEST_RC"

python3 - "$WORK/host.json" "$WORK/guest.json" <<'EOF'
import json, sys
try:
    host = json.load(open(sys.argv[1]))
    guest = json.load(open(sys.argv[2]))
except Exception as e:
    print("NETTEST: FAIL (result files unreadable:", e, ")")
    sys.exit(1)
print("host:", host)
print("guest:", guest)
ok = (
    host.get("status") == "done" and guest.get("status") == "done"
    and host.get("hash") and host.get("hash") == guest.get("hash")
    and host.get("hidden_ok") and guest.get("hidden_ok")
    and host.get("own_hand_ok") and guest.get("own_hand_ok")
)
print("NETTEST:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
EOF
