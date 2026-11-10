"""Compare Godot sim records with Lab records game by game.
usage: python3 lab/parity.py godot.jsonl lab.jsonl"""
import json, sys
g = {r["seed"]: r for r in map(json.loads, open(sys.argv[1]))}
l = {r["seed"]: r for r in map(json.loads, open(sys.argv[2]))}
keys = ["a", "b", "w", "t", "hp", "d0", "d1", "p0", "p1", "pw"]
same = diff = 0
first = None
for s, gr in g.items():
    lr = l.get(s)
    if lr is None:
        continue
    bad = [k for k in keys if gr[k] != lr[k]]
    if bad:
        diff += 1
        if first is None:
            first = (s, bad, gr, lr)
    else:
        same += 1
print(f"{same} identical, {diff} different, {len(g) - same - diff} missing")
if first:
    s, bad, gr, lr = first
    print("first difference: seed", s, "fields", bad)
    for k in bad:
        print(" godot", k, str(gr[k])[:400])
        print(" lab  ", k, str(lr[k])[:400])
sys.exit(0 if diff == 0 and same > 0 else 1)
