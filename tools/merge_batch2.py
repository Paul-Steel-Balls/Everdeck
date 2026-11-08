#!/usr/bin/env python3
"""Merge Batch 2 card spec (batch2_cards.txt) into game/data/cards.json."""
import json, sys

SPEC = "game/tools/batch2_cards.txt"
PATH = "game/data/cards.json"

def parse_keywords(s):
    return [k for k in s.split(",") if k] if s else []

new_cards = []
for line in open(SPEC):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    parts = line.split("|")
    assert len(parts) == 19, f"bad field count {len(parts)}: {line[:80]}"
    (cid, name, cls, cost, typ, atk, hp, kws, effect, eval_, target,
     rarity, text, flavor, art, dr, drval, drtarget, note) = parts
    card = {
        "id": cid, "name": name, "class": cls, "cost": int(cost),
        "type": typ, "attack": int(atk), "health": int(hp),
        "keywords": parse_keywords(kws),
        "effect": effect, "effect_value": int(eval_) if eval_ else 0,
        "target": target, "rarity": rarity,
        "text": text, "flavor": flavor, "art": art,
        "deathrattle": dr, "deathrattle_value": int(drval) if drval else 0,
        "deathrattle_target": drtarget or "none",
    }
    if note:
        card["design_note"] = note
    new_cards.append(card)

cards = json.load(open(PATH))
ids = {c["id"] for c in cards}
for c in new_cards:
    assert c["id"] not in ids, f"duplicate id {c['id']}"
    ids.add(c["id"])
cards.extend(new_cards)
with open(PATH, "w") as f:
    json.dump(cards, f, indent=2)
    f.write("\n")
print(f"merged {len(new_cards)} new cards, total {len(cards)}")
