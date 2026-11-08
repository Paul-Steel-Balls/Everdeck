#!/usr/bin/env python3
"""Summarise tools/sim_meta.gd output: class win rates, matchups,
first-player edge, and per-card signals. Writes JSON for the dashboard
and prints a plain summary.

    python3 tools/meta_report.py out.json run1.jsonl [run2.jsonl ...]
"""
import json, math, sys
from collections import defaultdict

CARDS = {c["id"]: c for c in json.load(open("data/cards.json"))}
CARDS.setdefault("coin", {"id": "coin", "name": "Lucky Penny", "class": "neutral", "cost": 0, "type": "spell"})


def ci(w, n):
    """95% Wilson interval, as (lo, hi) fractions."""
    if n == 0:
        return (0.0, 1.0)
    p = w / n
    z = 1.96
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)


def load(paths):
    out = []
    for p in paths:
        for line in open(p):
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def summarise(games):
    classes = sorted({g["a"] for g in games} | {g["b"] for g in games})
    cls_w = defaultdict(float); cls_n = defaultdict(int)
    mu_w = defaultdict(float); mu_n = defaultdict(int)
    first_w = 0.0; first_n = 0
    seat_cls = defaultdict(lambda: [0.0, 0, 0.0, 0])  # first w,n / second w,n
    lengths = []; draws = 0
    # Per card, per class: in-deck games/wins, played games/wins, turn played sum
    card = defaultdict(lambda: {"deck_n": 0, "deck_w": 0.0, "play_n": 0, "play_w": 0.0,
                                "turn_sum": 0, "copies_played": 0})
    cls_base = defaultdict(lambda: [0.0, 0])  # non-mirror baseline per class
    for g in games:
        a, b, w = g["a"], g["b"], g["w"]
        lengths.append(g["t"])
        if w == -1:
            draws += 1
        score = [0.5, 0.5] if w == -1 else ([1.0, 0.0] if w == 0 else [0.0, 1.0])
        first_w += score[0]; first_n += 1
        seat_cls[a][0] += score[0]; seat_cls[a][1] += 1
        seat_cls[b][2] += score[1]; seat_cls[b][3] += 1
        if a != b:
            cls_w[a] += score[0]; cls_n[a] += 1
            cls_w[b] += score[1]; cls_n[b] += 1
            mu_w[(a, b)] += score[0]; mu_n[(a, b)] += 1
            mu_w[(b, a)] += score[1]; mu_n[(b, a)] += 1
        for side, cls in ((0, a), (1, b)):
            if a == b:
                continue  # mirrors say nothing about a card's strength vs the field
            s = score[side]
            cls_base[cls][0] += s; cls_base[cls][1] += 1
            for cid in set(g["d%d" % side]):
                k = (cls, cid)
                card[k]["deck_n"] += 1; card[k]["deck_w"] += s
            seen = set()
            for cid, turn in g["p%d" % side]:
                k = (cls, cid)
                card[k]["copies_played"] += 1
                card[k]["turn_sum"] += turn
                if cid not in seen:
                    seen.add(cid)
                    card[k]["play_n"] += 1; card[k]["play_w"] += s
    res = {"games": len(games), "draws": draws,
           "avg_turns": sum(lengths) / max(1, len(lengths)),
           "first_player": {"wr": first_w / max(1, first_n), "n": first_n, "ci": ci(first_w, first_n)},
           "classes": {}, "matchups": {}, "cards": []}
    for c in classes:
        n = cls_n[c]
        sc = seat_cls[c]
        res["classes"][c] = {"wr": cls_w[c] / max(1, n), "n": n, "ci": ci(cls_w[c], n),
                             "first_wr": sc[0] / max(1, sc[1]), "second_wr": sc[2] / max(1, sc[3])}
    for (x, y), n in mu_n.items():
        res["matchups"]["%s|%s" % (x, y)] = {"wr": mu_w[(x, y)] / n, "n": n, "ci": ci(mu_w[(x, y)], n)}
    for (cls, cid), d in card.items():
        base_w, base_n = cls_base[cls]
        base = base_w / max(1, base_n)
        rest_n = base_n - d["deck_n"]
        rest_w = base_w - d["deck_w"]
        deck_wr = d["deck_w"] / max(1, d["deck_n"])
        without_wr = rest_w / rest_n if rest_n > 0 else None
        info = CARDS.get(cid, {"name": cid, "class": "?", "cost": -1, "type": "?"})
        res["cards"].append({
            "id": cid, "name": info.get("name", cid), "card_class": info.get("class"),
            "cost": info.get("cost"), "type": info.get("type"), "rarity": info.get("rarity", ""),
            "atk": info.get("attack"), "hp": info.get("health"), "text": info.get("text", ""),
            "played_as": cls,
            "deck_n": d["deck_n"], "deck_wr": deck_wr,
            "without_wr": without_wr,
            # How much better a deck does with this card than without it.
            "delta": (deck_wr - without_wr) if without_wr is not None else None,
            "play_n": d["play_n"], "play_wr": d["play_w"] / max(1, d["play_n"]),
            "play_rate": d["play_n"] / max(1, d["deck_n"]),
            "avg_turn": d["turn_sum"] / max(1, d["copies_played"]),
            "class_wr": base,
        })
    return res


def main():
    out = sys.argv[1]
    games = load(sys.argv[2:])
    res = summarise(games)
    json.dump(res, open(out, "w"), indent=1)
    print("games %d  draws %d  avg turns %.1f" % (res["games"], res["draws"], res["avg_turns"]))
    fp = res["first_player"]
    print("first player wins %.1f%% (%.1f-%.1f)" % (fp["wr"] * 100, fp["ci"][0] * 100, fp["ci"][1] * 100))
    print("\nclass win rate vs the field (mirrors excluded)")
    for c, d in sorted(res["classes"].items(), key=lambda kv: -kv[1]["wr"]):
        print("  %-9s %5.1f%%  (%4.1f-%4.1f)  n=%d   first %4.1f%% / second %4.1f%%" % (
            c, d["wr"] * 100, d["ci"][0] * 100, d["ci"][1] * 100, d["n"], d["first_wr"] * 100, d["second_wr"] * 100))
    cls = sorted(res["classes"])
    print("\nmatchups (row's win rate vs column)")
    print("          " + " ".join("%8s" % c[:8] for c in cls))
    for x in cls:
        row = []
        for y in cls:
            m = res["matchups"].get("%s|%s" % (x, y))
            row.append("%7.0f%%" % (m["wr"] * 100) if m else "      --")
        print("  %-8s" % x[:8] + " ".join(row))
    cards = [c for c in res["cards"] if c["deck_n"] >= 150 and c["delta"] is not None]
    cards.sort(key=lambda c: -c["delta"])
    print("\nstrongest cards (deck win rate with vs without, same class)")
    for c in cards[:20]:
        print("  %+5.1f  %-24s %-9s %d-cost  in %d decks, played %.0f%%" % (
            c["delta"] * 100, c["name"], c["played_as"], c["cost"], c["deck_n"], c["play_rate"] * 100))
    print("\nweakest cards")
    for c in cards[-15:]:
        print("  %+5.1f  %-24s %-9s %d-cost  in %d decks, played %.0f%%" % (
            c["delta"] * 100, c["name"], c["played_as"], c["cost"], c["deck_n"], c["play_rate"] * 100))


if __name__ == "__main__":
    main()
