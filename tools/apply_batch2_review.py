#!/usr/bin/env python3
"""Batch 2 review fixes — one-time transform for Everdeck cards.json.

Applies the 6 review items:
  1. Scaled class premium (1-2:+0, 3-6:+1, 7-10:+2) — replaces flat +1 and 7-10 budget-1.
  2. Presto signature cap: damage_per_hand_card N<=1.
  3. Agatha signature reprice: destroy_damaged 4->2 pts; pairing via BC+DR combos.
  4. Legendaries: at most 2 per class use signature; other 3 = distinct BC+DR combos.
  5. Cut Grog (Barnacle 1-mana gain_mana) -> Press Gang. 1-mana gain_mana = Presto-only.
  6. Cut/redesign: Fireworks Finale (redesign), Kraken Queen (redesign),
     plus forced cuts: Big Red Button, Harpoon, Pyroblast (damage 5 cannot price
     at +1 and cost-1 duplicates an existing card), Casserole Cannon (damage 5
     cannot price at +1; cost-1 duplicates Pin -> became 2-cost AoE-1).

Explicit overrides for spells, Legendaries, Finale, Village, cuts/replacements.
All other class minions: bulk stat adjustment to hit the scaled target exactly.
Neutrals untouched. Re-runnable: prints changes; safe to run once (back up first).
"""
import json, copy, sys

PATH = "data/cards.json"
cards = json.load(open(PATH))
by_id = {c["id"]: c for c in cards}

VANILLA = {1:4, 2:5, 3:6, 4:8, 5:9, 6:10, 7:12, 8:13, 9:14, 10:16}
SPELL_TABLE = {  # (effect, value) -> cost at on-budget (mirrors check_cards.py, with destroy_damaged 2)
    ("damage", 1): 1, ("damage", 2): 1, ("damage", 3): 2, ("damage", 4): 3, ("damage", 5): 4,
    ("damage_all_enemy_minions", 1): 2, ("damage_all_enemy_minions", 2): 5,
    ("damage_all_minions", 2): 4,
    ("random_enemy_damage", 1): 1, ("random_enemy_damage", 2): 1, ("random_enemy_damage", 3): 1,
    ("random_enemy_damage", 4): 2, ("random_enemy_damage", 5): 3,
    ("heal_hero", 3): 1, ("heal_hero", 5): 2, ("heal_draw", 5): 1,
    ("draw", 1): 1, ("draw", 2): 2, ("draw", 3): 4,
    ("draw_self_damage", 2): 1, ("damage_per_card_played", 1): 3, ("damage_per_card_played", 2): 4,
    ("damage_per_card_played", 3): 5, ("damage_per_card_played", 4): 6, ("damage_per_card_played", 5): 7,
    ("damage_per_hand_card", 1): 5,
    ("destroy", 0): 5, ("steal_weak", 2): 4, ("swap_hands", 0): 3,
    ("coin_flip", 2): 1, ("gain_mana", 1): 1,
    ("buff_friendly", 1): 1, ("buff_friendly", 2): 2,
    ("damage_split", 1): 1, ("damage_split", 2): 1, ("damage_split", 3): 2, ("damage_split", 4): 3, ("damage_split", 5): 4,
    ("destroy_damaged", 0): 2, ("recruit", 1): 2, ("recruit", 2): 3, ("recruit", 3): 4,
    ("recruit", 4): 5, ("recruit", 5): 6, ("buff_all_friendly", 1): 3, ("swap_stats", 0): 2,
}
MINION_PTS = {  # (effect, value) -> minion points (mirrors check_cards.py, destroy_damaged 2)
    ("damage", 1): 1, ("damage", 2): 2, ("damage", 3): 3, ("damage", 4): 4, ("damage", 5): 5,
    ("damage_all_enemy_minions", 1): 3, ("damage_all_enemy_minions", 2): 5,
    ("damage_all_minions", 2): 3,
    ("heal_hero", 3): 1, ("heal_hero", 5): 2, ("heal_draw", 5): 1,
    ("draw", 1): 2, ("draw", 2): 4, ("draw_self_damage", 2): 2,
    ("damage_per_card_played", 1): 3, ("damage_per_card_played", 2): 4, ("damage_per_card_played", 3): 5,
    ("damage_per_card_played", 4): 6,
    ("damage_per_hand_card", 1): 5,
    ("summon_token", 0): 2, ("gain_mana", 1): 1,
    ("buff_friendly", 1): 2, ("buff_friendly", 2): 4,
    ("random_enemy_damage", 1): 1, ("random_enemy_damage", 2): 1, ("random_enemy_damage", 3): 2,
    ("random_enemy_damage", 4): 3, ("random_enemy_damage", 5): 4,
    ("damage_split", 1): 1, ("damage_split", 2): 2, ("damage_split", 3): 3, ("damage_split", 4): 4, ("damage_split", 5): 5,
    ("destroy_damaged", 0): 2, ("recruit", 1): 3, ("recruit", 2): 4, ("recruit", 3): 5,
    ("recruit", 4): 6, ("recruit", 5): 7, ("buff_all_friendly", 1): 4, ("swap_stats", 0): 2,
    ("", 0): 0,
}

def premium(cost):
    return 0 if cost <= 2 else 1 if cost <= 6 else 2

def minion_total(c):
    kw = 0
    if "taunt" in c["keywords"]: kw += 1
    if "charge" in c["keywords"]: kw += 1
    bc = MINION_PTS.get((c["effect"], c["effect_value"]), 0)
    dr = MINION_PTS.get((c.get("deathrattle") or "", c.get("deathrattle_value") or 0), 0)
    return c["attack"] + c["health"] + kw + bc + dr

def minion_target(c):
    return VANILLA[c["cost"]] + premium(c["cost"])

changed = []  # (id, what)

def set_fields(cid, **kw):
    c = by_id[cid]
    for k, v in kw.items():
        if c.get(k) != v:
            changed.append((cid, f"{k} {c.get(k)!r} -> {v!r}"))
            c[k] = v

# ---------------------------------------------------------------- spells: value scaling (keep cost)
set_fields("agatha_face", effect_value=3, text="Deal 3 damage to an enemy minion.")
set_fields("barnacle_cannon", effect_value=3, text="Deal 3 damage to an enemy.")
set_fields("barnacle_rum", effect_value=5, text="Deal 5 damage to an enemy.")
set_fields("grunk_firecracker_spell", effect_value=2, text="Deal 2 damage to an enemy.")
set_fields("grunk_molotov", effect_value=3, text="Deal 3 damage to an enemy.")
set_fields("grunk_wildfire", effect_value=4, text="Deal 4 damage to a random enemy.")
set_fields("presto_orb", effect_value=5, text="Deal 5 damage to an enemy.")
set_fields("presto_payoff", effect_value=2,
           text="Deal 2 damage to the enemy hero for each other card you played this turn.")
set_fields("presto_thesis", effect_value=3,
           text="Deal 3 damage to the enemy hero for each other card you played this turn.")
set_fields("presto_grad", effect_value=4,
           text="Deal 4 damage to the enemy hero for each other card you played this turn.")
set_fields("presto_magna", effect_value=5,
           text="Deal 5 damage to the enemy hero for each other card you played this turn.")

# ---------------------------------------------------------------- spells: cost rule (unscalable -> cost -1)
set_fields("nova", cost=4,
           design_note="Re-costed to 4 per scaled class premium (Batch 2 review).")
set_fields("assassinate", cost=4,
           design_note="Re-costed to 4 per scaled class premium (Batch 2 review; destroy is unscalable).")
set_fields("hand_swap", cost=2,
           design_note="Re-costed to 2 per scaled class premium (Batch 2 review; swap_hands is unscalable).")
set_fields("mind_trick", cost=3,
           design_note="Re-costed to 3 per scaled class premium (Batch 2 review; steal_weak is unscalable).")
set_fields("agatha_wrath_mild", cost=3,
           design_note="Re-costed to 3 per scaled class premium (Batch 2 review; both-sides AoE-2 has no higher value).")
set_fields("presto_disint", cost=4,
           design_note="Re-costed to 4 per scaled class premium (Batch 2 review; destroy is unscalable).")

# ---------------------------------------------------------------- spells: forced effect changes (table cap + dedup)
set_fields("agatha_cannon", cost=2, effect="damage_all_enemy_minions", effect_value=1,
           target="none", text="Deal 1 damage to ALL enemy minions.",
           design_note="Reworked (Batch 2 review): damage 5 cannot price at +1 at cost 4 (table capped) and cost-1 duplicates Pin; became Agatha's cheap AoE-1.")
set_fields("presto_echo", effect="random_enemy_damage", effect_value=4, target="none",
           text="Deal 4 damage to a random enemy.",
           design_note="Reworked (Batch 2 review): damage 4 cannot price at +0 at cost 2 and cost-rule has no fixed point; became random damage (no duplicate of Bolt).")

# ---------------------------------------------------------------- Finale redesign (item 6)
set_fields("grunk_finale", attack=3, health=3, effect="damage_all_enemy_minions", effect_value=1,
           target="none", deathrattle="", deathrattle_value=0, deathrattle_target="none",
           text="Taunt. Battlecry: Deal 1 damage to ALL enemy minions.",
           design_note="Redesigned (Batch 2 review): the 0-attack Deathrattle-only pattern failed twice (-11, then -4.4); now a Taunt Battlecry body.")

# ---------------------------------------------------------------- Village stabilizing effect (item 3)
set_fields("agatha_village", effect="heal_hero", effect_value=5, target="none",
           text="Taunt. Battlecry: Restore 5 Health to your hero.",
           design_note="Stabilizing effect added (Batch 2 review): Battlecry heal 5.")

# ---------------------------------------------------------------- Legendaries (items 2, 3, 4)
def legend(cid, a, h, eff, ev, tgt, dr, drv, drt, text, note=None):
    kw = dict(attack=a, health=h, effect=eff, effect_value=ev, target=tgt,
              deathrattle=dr, deathrattle_value=drv, deathrattle_target=drt, text=text)
    if note is not None:
        kw["design_note"] = note
    set_fields(cid, **kw)

# Grunk: Jr + King keep signature; Sparky, Dan, Grandma -> combos
legend("grunk_jr", 3, 1, "damage_split", 5, "none", "", 0, "none",
       "Battlecry: Deal 5 damage, split randomly among enemy characters.",
       "Signature keeper (Batch 2 review: at most 2 Legendaries per class use the signature); +1 stat for scaled premium.")
legend("grunk_king", 2, 1, "damage_split", 4, "none", "", 0, "none",
       "Battlecry: Deal 4 damage, split randomly among enemy characters.",
       "Signature keeper (Batch 2 review); -1 stat for scaled premium.")
legend("grunk_sparky", 1, 1, "damage", 1, "enemy_minion", "damage", 1, "enemy_minion",
       "Battlecry: Deal 1 damage to an enemy minion. Deathrattle: Deal 1 damage to an enemy minion.",
       "Reworked (Batch 2 review): at most 2 Legendaries per class use the signature; Sparky became a Battlecry+Deathrattle combo.")
legend("grunk_dan", 1, 1, "damage", 2, "enemy_minion", "damage", 1, "enemy_minion",
       "Battlecry: Deal 2 damage to an enemy minion. Deathrattle: Deal 1 damage to an enemy minion.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
legend("grunk_grandma", 3, 2, "damage", 2, "enemy_minion", "damage_all_enemy_minions", 1, "none",
       "Battlecry: Deal 2 damage to an enemy minion. Deathrattle: Deal 1 damage to ALL enemy minions.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
# Agatha: Timmy + Unleashed keep signature; Bobby, Last, Soupocalypse -> combos
legend("agatha_bobby", 3, 3, "heal_hero", 5, "none", "summon_token", 0, "none",
       "Battlecry: Restore 5 Health to your hero. Deathrattle: Summon a 1/1 Casserole Dish.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo. Token: Casserole Dish, 1/1 minion, no keywords.")
legend("agatha_last", 4, 3, "heal_hero", 5, "none", "damage", 2, "enemy_minion",
       "Battlecry: Restore 5 Health to your hero. Deathrattle: Deal 2 damage to an enemy minion.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
legend("agatha_unleashed", 5, 5, "destroy_damaged", 0, "none", "damage_all_enemy_minions", 1, "none",
       "Battlecry: Destroy all damaged enemy minions. Deathrattle: Deal 1 damage to ALL enemy minions.",
       "Signature keeper, paired (Batch 2 review): Battlecry destroy_damaged + Deathrattle AoE-1; destroy_damaged repriced 4->2.")
legend("agatha_soupocalypse", 7, 6, "damage_all_enemy_minions", 1, "none", "heal_hero", 5, "none",
       "Battlecry: Deal 1 damage to ALL enemy minions. Deathrattle: Restore 5 Health to your hero.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo (no longer destroy_damaged).")
# Presto: Headmaster + Himself keep signature at N=1; Mira, Fizzle, Parchment -> combos
legend("presto_mira", 2, 1, "draw", 1, "none", "draw", 1, "none",
       "Battlecry: Draw a card. Deathrattle: Draw a card.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
legend("presto_fizzle", 2, 2, "random_enemy_damage", 2, "none", "draw", 1, "none",
       "Battlecry: Deal 2 damage to a random enemy. Deathrattle: Draw a card.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
legend("presto_parchment", 2, 2, "draw", 2, "none", "damage", 1, "enemy_minion",
       "Battlecry: Draw 2 cards. Deathrattle: Deal 1 damage to an enemy minion.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo.")
legend("presto_headmaster", 3, 2, "damage_per_hand_card", 1, "none", "", 0, "none",
       "Battlecry: Deal 1 damage to the enemy hero for each card in your hand.",
       "Signature keeper at N=1 (Batch 2 review: damage_per_hand_card capped at N=1); freed points spent on body stats (2/1 -> 3/2).")
legend("presto_himself", 3, 3, "damage_per_hand_card", 1, "none", "", 0, "none",
       "Battlecry: Deal 1 damage to the enemy hero for each card in your hand.",
       "Signature keeper at N=1 (Batch 2 review); freed points spent on body stats (2/2 -> 3/3).")
# Barnacle: Quinn + Admiral keep recruit; Peggy, Betty, Kraken Queen -> combos
legend("barnacle_peggy", 2, 1, "summon_token", 0, "none", "summon_token", 0, "none",
       "Battlecry: Summon a 1/1 Deckhand. Deathrattle: Summon a 1/1 Deckhand.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo. Token: Deckhand 1/1.")
legend("barnacle_betty", 3, 2, "damage", 2, "enemy_minion", "summon_token", 0, "none",
       "Battlecry: Deal 2 damage to an enemy minion. Deathrattle: Summon a 1/1 Deckhand.",
       "Reworked (Batch 2 review): Battlecry+Deathrattle combo. Token: Deckhand 1/1.")
legend("barnacle_krakenqueen", 4, 4, "random_enemy_damage", 2, "none", "summon_token", 0, "none",
       "Battlecry: Deal 2 damage to a random enemy. Deathrattle: Summon a 1/1 Tentacle.",
       "Redesigned (Batch 2 review): Deathrattle recruit 5 was high-variance (-3.0); now a Battlecry+Deathrattle combo. Token: Tentacle, 1/1 minion, no keywords.")

# ---------------------------------------------------------------- cuts -> replacements (items 5, 6)
CUT_IDS = {"barnacle_grog", "barnacle_harpoon", "grunk_button", "presto_pyro"}
cards = [c for c in cards if c["id"] not in CUT_IDS]
by_id = {c["id"]: c for c in cards}
changed.append(("CUT", "barnacle_grog, barnacle_harpoon, grunk_button, presto_pyro"))

def new_card(cid, cls, cost, typ, a, h, rar, eff, ev, tgt, text, flavor, art, note, kw=None):
    c = {"id": cid, "class": cls, "cost": cost, "type": typ, "attack": a, "health": h,
         "rarity": rar, "keywords": kw or [], "effect": eff, "effect_value": ev, "target": tgt,
         "deathrattle": "", "deathrattle_value": 0, "deathrattle_target": "none",
         "text": text, "flavor": flavor, "art": art, "design_note": note}
    cards.append(c)
    by_id[cid] = c
    changed.append(("ADD", f"{cid} ({cls} {cost} {typ} {a}/{h} {rar} {eff}({ev}))"))

new_card("barnacle_press_gang", "barnacle", 1, "minion", 1, 1, "Rare", "summon_token", 0, "none",
         "Battlecry: Summon a 1/1 Deckhand.", "They recruit. Voluntarily. Mostly.", "press_gang",
         "Replaces Grog (cut Batch 2 review: dead card; 1-mana gain_mana is Presto-only). Token: Deckhand 1/1.")
new_card("barnacle_harpoon_gunner", "barnacle", 4, "minion", 4, 3, "Common", "summon_token", 0, "none",
         "Battlecry: Summon a 1/1 Deckhand.", "Harpoons in one hand, Deckhand in the other. Efficiency.", "harpoon_gunner",
         "Replaces Harpoon (cut Batch 2 review: damage 5 cannot price at +1 and cost-1 duplicates Rum). Token: Deckhand 1/1.")
new_card("grunk_demo_expert", "grunk", 4, "minion", 4, 3, "Epic", "damage", 2, "enemy_minion",
         "Battlecry: Deal 2 damage to an enemy minion.", "She has a degree in explosions. It is from a real university. Probably.", "demo_expert",
         "Replaces Big Red Button (cut Batch 2 review: damage 5 cannot price at +1 and cost-1 duplicates Spicy).")
new_card("presto_blast_scholar", "presto", 4, "minion", 4, 3, "Rare", "damage", 2, "enemy_minion",
         "Battlecry: Deal 2 damage to an enemy minion.", "His thesis is on fire. Literally. It is on fire.", "blast_scholar",
         "Replaces Pyroblast (cut Batch 2 review: damage 5 cannot price at +1 and cost-1 duplicates Orb).")

# ---------------------------------------------------------------- bulk minion stat adjustment (item 1)
EXPLICIT = {cid for cid, _ in changed if cid not in ("CUT", "ADD")}
EXPLICIT |= {"grunk_finale", "agatha_village", "agatha_timmy", "barnacle_quinn", "barnacle_admiral",
             "grunk_jr", "grunk_king", "grunk_sparky", "grunk_dan", "grunk_grandma",
             "agatha_bobby", "agatha_last", "agatha_unleashed", "agatha_soupocalypse",
             "presto_mira", "presto_fizzle", "presto_parchment", "presto_headmaster", "presto_himself",
             "barnacle_peggy", "barnacle_betty", "barnacle_krakenqueen"}
# Note: grunk_jr/king keepers + Timmy/Quinn/Admiral (no change) are excluded so bulk skips them.

def skewed(a, h):
    return (h > 0 and a / h >= 3) or (a > 0 and h / a >= 3)

bulk_n = 0
for c in cards:
    if c["class"] == "neutral" or c["type"] != "minion" or c["id"] in EXPLICIT:
        continue
    total = minion_total(c)
    target = minion_target(c)
    delta = target - total
    if delta == 0:
        continue
    a, h = c["attack"], c["health"]
    cls = c["class"]
    orig = (a, h)
    # preferred stat for +/-1
    def pref():
        if cls == "grunk":
            return "attack" if delta > 0 else "health"
        if cls == "agatha":
            return "health" if delta > 0 else "attack"
        # presto/barnacle: add to smaller, remove from larger
        if delta > 0:
            return "attack" if a <= h else "health"
        return "attack" if a >= h else "health"
    if delta in (1, -1):
        p = pref()
        if p == "attack":
            a += 1 if delta > 0 else -1
        else:
            h += 1 if delta > 0 else -1
        if skewed(a, h):
            # rebalance: move the point to the other stat
            if p == "attack":
                a -= 1 if delta > 0 else -1
                h += 1 if delta > 0 else -1
            else:
                h -= 1 if delta > 0 else -1
                a += 1 if delta > 0 else -1
    elif delta in (2, -2):
        step = 1 if delta > 0 else -1
        a += step
        h += step
        if skewed(a, h):
            # fall back: both points on the larger/smaller side
            a -= step
            h -= step
            for _ in range(2):
                if cls == "grunk":
                    a += step
                elif cls == "agatha":
                    h += step
                else:
                    if step > 0:
                        (a, h) = (a + 1, h) if a <= h else (a, h + 1)
                    else:
                        (a, h) = (a - 1, h) if a >= h else (a, h - 1)
    else:
        print(f"WARN: {c['id']} delta {delta} out of range", file=sys.stderr)
        continue
    # floors
    a = max(0, a)
    h = max(1, h)
    if (a, h) != orig:
        c["attack"], c["health"] = a, h
        bulk_n += 1
        changed.append((c["id"], f"bulk stats {orig[0]}/{orig[1]} -> {a}/{h} (delta {delta})"))

json.dump(cards, open(PATH, "w"), indent=2)
print(f"Total cards: {len(cards)}")
print(f"Bulk minion adjustments: {bulk_n}")
print(f"Explicit changes: {len(changed) - bulk_n}")
for cid, what in changed:
    print(f"  {cid}: {what}")
