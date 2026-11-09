#!/usr/bin/env python3
"""Turn a meta stress-test run (tools/sim_meta.gd + sim_search.gd output,
summarised by meta_report.py) into the small JSON tables the meta
dashboard reads.

    python3 tools/meta_datasets.py <run dir> <out dir> [old run dir]
"""
import json, os, sys

NAMES = {"grunk": "Grunk", "agatha": "Agatha", "presto": "Presto", "barnacle": "Barnacle",
         "reginald": "Reginald", "larry": "Larry"}
CLASSES = list(NAMES)
CARDS = {c["id"]: c for c in json.load(open("data/cards.json"))}
RULES = [("none", "Now: second player gets 5 cards + Penny"), ("p2minus", "Second player gets 4 cards + Penny"),
         ("nocoin", "Second player gets 5 cards, no Penny"), ("p2hp3", "Now, plus second Boss starts on 33"),
         ("p2card", "Second player gets 6 cards + Penny"), ("p1nodraw", "Now, plus first player skips turn-1 draw")]


def j(p):
    return json.load(open(p))


def pct(x):
    return round(x * 100, 1)


def main():
    run, out = sys.argv[1], sys.argv[2]
    old = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(out, exist_ok=True)
    r1, r2 = j(f"{run}/r1.json"), j(f"{run}/r2.json")
    searches = {c: j(f"{run}/s1_{c}.json") for c in CLASSES}

    classes = []
    for c in CLASSES:
        m = r2["classes"][c]
        classes.append({
            "boss": NAMES[c],
            "random_deck_wr": pct(r1["classes"][c]["wr"]),
            "tuned_vs_random_field_wr": pct(searches[c]["final_wr"]),
            "meta_wr": pct(m["wr"]), "meta_lo": pct(m["ci"][0]), "meta_hi": pct(m["ci"][1]),
            "first_wr": pct(m["first_wr"]), "second_wr": pct(m["second_wr"]),
            "games": m["n"],
        })
    classes.sort(key=lambda r: -r["meta_wr"])

    matchups = []
    for a in CLASSES:
        for b in CLASSES:
            if a == b:
                continue
            m = r2["matchups"][f"{a}|{b}"]
            matchups.append({"deck": NAMES[a], "vs": NAMES[b], "wr": pct(m["wr"]), "games": m["n"]})

    seat = []
    if old:
        o = j(f"{old}/r2.json")["first_player"]
        seat.append({"rule": "Before the AI fix (Penny never played)", "first_wr": pct(o["wr"]),
                     "lo": pct(o["ci"][0]), "hi": pct(o["ci"][1]), "games": o["n"]})
    for key, label in RULES:
        f = f"{run}/v_{key}.json"
        if key == "none":
            d = r2["first_player"]
        elif os.path.exists(f):
            d = j(f)["first_player"]
        else:
            continue
        seat.append({"rule": label, "first_wr": pct(d["wr"]), "lo": pct(d["ci"][0]), "hi": pct(d["ci"][1]), "games": d["n"]})

    decks = []
    for c in CLASSES:
        counts = searches[c]["counts"]
        for cid, n in sorted(counts.items(), key=lambda kv: (CARDS[kv[0]]["cost"], CARDS[kv[0]]["name"])):
            k = CARDS[cid]
            stats = f"{k['attack']}/{k['health']}" if k["type"] == "minion" else "Trick"
            decks.append({"boss": NAMES[c], "card": k["name"], "id": cid, "cost": k["cost"], "copies": n,
                          "stats": stats, "class_card": k["class"] != "neutral", "text": k.get("text", "")})

    cards = []
    for c in r1["cards"]:
        if c["deck_n"] < 150 or c["delta"] is None or c["id"] == "coin":
            continue
        cards.append({"card": c["name"], "id": c["id"], "boss": NAMES.get(c["played_as"], c["played_as"]),
                      "neutral": c["card_class"] == "neutral", "cost": c["cost"],
                      "lift": pct(c["delta"]), "decks": c["deck_n"], "played": pct(c["play_rate"]),
                      "text": c.get("text", "")})
    cards.sort(key=lambda r: -r["lift"])

    runs = [{"stage": "Random decks, every pairing", "games": r1["games"]},
            {"stage": "Deck search (6 Bosses)", "games": sum(
                (6 + s["iters"] + s["iters"] // 15) * s["games"] + 6 * s["games"] for s in searches.values())},
            {"stage": "Tuned decks vs each other", "games": r2["games"]}]
    for key, _ in RULES[1:]:
        f = f"{run}/v_{key}.json"
        if os.path.exists(f):
            runs.append({"stage": f"What-if: {key}", "games": j(f)["games"]})

    for name, rows in [("classes", classes), ("matchups", matchups), ("seat", seat), ("decks", decks),
                       ("cards", cards), ("runs", runs)]:
        json.dump(rows, open(f"{out}/{name}.json", "w"), indent=1)
        print(name, len(rows))


if __name__ == "__main__":
    main()
