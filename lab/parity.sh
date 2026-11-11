#!/bin/bash
# Lab parity check: the same seeded games in Godot and the Lab must match
# move for move. Run after ANY rules or bot change on either side.
#   bash lab/parity.sh [patch.json]
# Uses a stress patch by default (random new mechanics on ~90 cards), so
# every keyword and trigger path gets played.
set -e
cd "$(dirname "$0")/.."
G=${GODOT:-/opt/godot/Godot_v4.7.2-stable_linux.x86_64}
T=$(mktemp -d)
PATCH=${1:-lab/data/stress_patch.json}
$G --headless --path . -s res://tools/lab_export.gd >/dev/null 2>&1
(cd lab && cargo build --release -q)
for run in "plain::13:0" "patch:$PATCH:21:0" "hard:$PATCH:31:4"; do
  IFS=: read name pf seed plan <<< "$run"
  SIM_PLAN=$plan SIM_PATCH=$pf SIM_CLONE_SEED=4242 SIM_GAMES=8 SIM_SEED=$seed SIM_OUT=$T/g.jsonl $G --headless --path . -s res://tools/sim_meta.gd >/dev/null 2>&1
  ./lab/target/release/everdeck_lab meta ${pf:+--patch $pf} --games 8 --seed $seed --clone-seed 4242 --plan $plan --out $T/l.jsonl >/dev/null 2>&1
  echo -n "$name: "; python3 lab/parity.py $T/g.jsonl $T/l.jsonl | head -6
done
rm -rf $T
