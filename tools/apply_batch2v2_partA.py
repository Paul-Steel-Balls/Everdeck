#!/usr/bin/env python3
"""Part A: Batch 2 v2 re-test fixes. Re-cost class cards for the three new
§2A prices + small fixes. Neutrals untouched per task constraint (the 3 new
neutral summon_token cards sit within the +/-1 tolerance under the new
prices, so no edit is needed for the checker)."""
import json

PATH = "data/cards.json"

# id -> (attack, health): stat changes only, costs unchanged.
STAT_CHANGES = {
    # 1. random_enemy_damage on minions: N-1 -> N points. Remove 1 stat/slot.
    "grunk_dan": (0, 1),
    "agatha_soupocalypse": (6, 5),
    "presto_ink": (1, 1),
    "presto_trick": (2, 1),
    "presto_gamble": (2, 1),
    "presto_unstable": (3, 2),
    "presto_fizzle": (1, 1),  # BC random 2 + DR random 3: two slots -> -2 stats
    "presto_dragon": (5, 3),
    "barnacle_powder": (2, 1),
    "barnacle_tide": (2, 1),
    "barnacle_kraken": (2, 2),
    "barnacle_mutineer": (3, 3),
    "barnacle_betty": (3, 2),
    "barnacle_code": (4, 3),
    "barnacle_plunder": (3, 3),
    "barnacle_krakenqueen": (3, 2),
    # 2. Draw 2 on minions: 4 -> 3 points. Add 1 stat.
    "presto_tome": (2, 2),
    "presto_textbook": (1, 3),
    "presto_librarian": (3, 3),
    "presto_parchment": (3, 2),
    "presto_archmage": (4, 3),
    "presto_grandsage": (4, 4),
    # 3. summon_token on minions: 2 -> 1 point. Add 1 stat. (Class cards only;
    # neutrals untouched per constraint; grandfathered summoner untouched.)
    "agatha_dumpling": (3, 3),
    "agatha_carol": (4, 4),
    "agatha_bobby": (4, 3),
    "presto_scrollkeeper": (2, 2),
    "presto_mirror": (3, 3),
    "presto_circle": (4, 4),
    "presto_phoenix": (4, 5),
    "barnacle_parrot": (1, 2),
    "barnacle_sailor": (2, 2),
    "barnacle_bosun": (2, 2),
    "barnacle_perch": (1, 3),
    "barnacle_buddy": (2, 2),
    "barnacle_scout": (3, 3),
    "barnacle_storm": (2, 4),
    "barnacle_peggy": (3, 2),
    "barnacle_cook": (3, 3),
    "barnacle_salvage": (4, 4),
    "barnacle_priestess": (3, 5),
    "barnacle_commodore": (5, 4),
    "barnacle_fleet": (5, 5),
    "barnacle_harpoon_gunner": (4, 4),
    # 4. Grandma's Cookies: +Taunt, -1 health to stay at exact target.
    "agatha_cookies": (0, 3),
}

with open(PATH) as f:
    cards = json.load(f)
by_id = {c["id"]: c for c in cards}

for cid, (a, h) in STAT_CHANGES.items():
    c = by_id[cid]
    assert c["type"] == "minion", cid
    assert a >= 0 and h >= 1, cid
    c["attack"], c["health"] = a, h

# Cookies: add Taunt + fix text.
cookies = by_id["agatha_cookies"]
cookies["keywords"] = ["taunt"]
cookies["text"] = "Taunt. Battlecry: Restore 3 Health to your hero."

# Powder Monkey rename (Grunk one -> Powder Goblin; Barnacle keeps the name).
monkey = by_id["grunk_monkey"]
monkey["name"] = "Powder Goblin"
monkey["art"] = "powder_goblin"

# Grandma's Wrath back to 4 mana (explicit exception to the cost-1 fallback).
wrath = by_id["agatha_wrath_mild"]
wrath["cost"] = 4
wrath["design_note"] = ("Restored to 4 (Batch 2 v2 re-test: +4.6/copy at 3 mana "
    "after the cost-1 fallback; explicit exception to the fallback).")

# Design notes: presto_ink skew note is stale (card was 2/1, note said 1/3;
# now 1/1, no skew) -> remove. New 1/3 skews need notes.
by_id["presto_ink"].pop("design_note", None)
by_id["presto_textbook"]["design_note"] = (
    "Extreme skew (1/3): a textbook that soaks up punishment. "
    "(Batch 2 v2 re-cost.)")
by_id["barnacle_perch"]["design_note"] = (
    "Extreme skew (1/3): a perch; blocks, does not kill. (Batch 2 v2 re-cost.)")

with open(PATH, "w") as f:
    json.dump(cards, f, indent=1)
print(f"Part A applied: {len(STAT_CHANGES)} stat changes + cookies/rename/wrath/notes")
print(f"total cards: {len(cards)}")
