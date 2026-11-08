#!/usr/bin/env python3
"""Batch 3 card checker for Everdeck (Phase 2, Batch 3 complete: 340 cards).

Checks res://data/cards.json against the amended Phase 1 design doc:
- valid JSON, unique ids, required fields, enums
- counts: 340 total; 50 per class, 40 neutral
- mana curves per Phase 1 targets (post Batch 2 v2 re-test + Batch 3)
- rarity budgets
- minion cost-vs-budget WITH SCALED CLASS PREMIUM (class 1-2: table+0;
  class 3-6: table+1; class 7-10: table+2; neutral 1-6: table;
  neutral 7-10: table-1; existing 23 neutrals grandfathered)
- minion effect prices (Batch 2 v2 + Full-set review): random_enemy_damage
  on minions = N (no discount); draw 2 on minions = 3; summon_token = 1;
  Battlecry targeted damage N>=2 = N+1 (Deathrattle damage stays N);
  damage_per_card_played = 2 + 2N
- spell cost-vs-table: class spells cost = table(value) - premium(band)
  (scalable effects); unscalable effects (destroy, swap_hands, steal_weak,
  AoE-2) use the cost-1 fallback: cost = table(value) - 1.
  Grandma's Wrath is an explicit exception at 4 mana.
  The 7 moved spells are checked as class cards (no longer exempt).
  Random-damage spells (random_enemy_damage, damage_split) =
  max(1, targeted - 2). No pure deal-1 spells (checker-enforced §2B ban).
  effect2 (second small effect) only on the 4 exception spells, cost <= 2.
- class bans (Grunk, Agatha, Presto, Larry, Barnacle, Reginald)
- new-neutral bans (existing 23 grandfathered)
- buff_friendly Reginald-only; draw_self_damage value == 2
- deathrattle_target present on Deathrattle cards; target == "none" on
  Deathrattle-only minions; Battlecry/Deathrattle targets validated separately
- NO within-pool duplicates (neutral; each class + neutrals)
- vanilla cap <= 3 per class (neutrals exempt)
- every NEW legendary has an effect unique at that value in its class
  (existing legendaries grandfathered); at most 2 Legendaries per class
  use the signature effect
- no draw-family effects on NEW non-Presto cards
- skew design_note for extreme Attack:Health ratios on new minions
- damage_per_hand_card N <= 1; destroy_damaged priced at 2
- 1-mana gain_mana spells are Presto-only

Usage: python3 tools/check_cards.py
Exit code 0 = all checks pass. Prints curve report + violations.
"""
import json
import sys
from collections import Counter

CARDS_PATH = "data/cards.json"

VANILLA = {1: 4, 2: 5, 3: 6, 4: 8, 5: 9, 6: 10, 7: 12, 8: 13, 9: 14, 10: 16}

EFFECTS = {"damage", "gain_mana", "heal_hero", "heal_draw", "draw",
           "summon_token", "damage_all_enemy_minions", "destroy",
           "random_minion_damage", "steal_weak", "swap_hands", "coin_flip",
           "draw_self_damage", "damage_per_card_played", "buff_friendly",
           "random_enemy_damage", "damage_all_minions",
           # Signature effects (Batch 1 v2): Legendary-only, owning class only.
           "damage_split", "destroy_damaged", "damage_per_hand_card",
           "recruit", "buff_all_friendly", "swap_stats"}
# Signature effect -> owning class. Only Legendaries of that class may use it.
SIGNATURES = {"damage_split": "grunk", "destroy_damaged": "agatha",
              "damage_per_hand_card": "presto", "recruit": "barnacle",
              "buff_all_friendly": "reginald", "swap_stats": "larry"}
# Spells allowed a second small effect (effect2) — Full-set review exception.
# Combined effects are otherwise banned. Cost <= 2 enforced in the check.
EFFECT2_EXCEPTIONS = {"wisdom", "presto_cantrip", "reg_blessing",
                      "lar_double_down"}
# Damage values cap at 5 (no SS2 row for 6+; Grunk Jr. re-test).
DAMAGE_CAPPED = {"damage", "random_enemy_damage", "damage_split"}
TARGETS = {"none", "any_enemy", "enemy_minion", "friendly_minion", "enemy_hero"}
KEYWORDS = {"taunt", "charge"}
RARITIES = {"Common", "Rare", "Epic", "Legendary"}
CLASSES = {"neutral", "grunk", "agatha", "presto", "barnacle", "reginald", "larry"}
DRAW_FAMILY = {"draw", "heal_draw", "coin_flip", "draw_self_damage"}

# The 30 existing (grandfathered) card ids -> (class, rarity) per Phase 1 SS5.
EXISTING = {
    "angry_squirrel": ("neutral", "Common"), "squire": ("neutral", "Common"),
    "recruit": ("neutral", "Common"), "guard_dog": ("neutral", "Common"),
    "archer": ("neutral", "Common"), "wolf": ("neutral", "Common"),
    "knight": ("neutral", "Common"), "brute": ("neutral", "Common"),
    "ogre": ("neutral", "Rare"), "giant": ("neutral", "Rare"),
    "golem": ("neutral", "Rare"), "dragon": ("neutral", "Legendary"),
    "shieldbearer": ("neutral", "Common"), "wall": ("neutral", "Common"),
    "fortress": ("neutral", "Rare"), "charger": ("neutral", "Common"),
    "cavalry": ("neutral", "Common"), "medic": ("neutral", "Common"),
    "zapper": ("neutral", "Rare"), "scout": ("neutral", "Rare"),
    "summoner": ("neutral", "Epic"), "fireball": ("grunk", "Common"),
    "healing_light": ("agatha", "Rare"), "wisdom": ("presto", "Common"),
    "nova": ("agatha", "Rare"), "assassinate": ("agatha", "Epic"),
    "roulette": ("neutral", "Epic"), "mind_trick": ("larry", "Rare"),
    "hand_swap": ("larry", "Epic"), "coin_flip": ("neutral", "Common"),
}

EXPECTED_COUNTS = {"neutral": 40, "grunk": 50, "agatha": 50, "presto": 50,
                    "larry": 50, "barnacle": 50, "reginald": 50}
EXPECTED_CURVES = {
    "neutral": {1: 6, 2: 9, 3: 8, 4: 6, 5: 6, 6: 4, 7: 1},
    "grunk": {1: 13, 2: 13, 3: 12, 4: 7, 5: 5},
    "agatha": {1: 1, 2: 8, 3: 10, 4: 11, 5: 6, 6: 6, 7: 4, 8: 2, 9: 1, 10: 1},
    "presto": {1: 11, 2: 11, 3: 11, 4: 7, 5: 5, 6: 3, 7: 1, 9: 1},
    "barnacle": {1: 6, 2: 12, 3: 12, 4: 10, 5: 6, 6: 4},
    "larry": {1: 7, 2: 9, 3: 10, 4: 10, 5: 8, 6: 4, 7: 2},
    "reginald": {1: 4, 2: 8, 3: 10, 4: 12, 5: 8, 6: 5, 7: 3},
}
EXPECTED_RARITY = {
    "neutral": {"Common": 20, "Rare": 12, "Epic": 6, "Legendary": 2},
    "grunk": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
    "agatha": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
    "presto": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
    "barnacle": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
    "reginald": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
    "larry": {"Common": 20, "Rare": 15, "Epic": 10, "Legendary": 5},
}

TARGETED_DAMAGE_MANA = {1: 1, 2: 1, 3: 2, 4: 3, 5: 4}


def class_premium(cost):
    """Scaled class premium (Batch 2 review): 1-2 -> +0, 3-6 -> +1, 7-10 -> +2."""
    if cost <= 2:
        return 0
    if cost <= 6:
        return 1
    return 2


# (effect, value) pairs whose effect cannot scale, so the premium is
# implemented as cost - 1 (Batch 2 review cost-1 fallback).
UNSCALABLE_SPELLS = {("swap_hands", 0), ("destroy", 0), ("steal_weak", 2),
                     ("damage_all_enemy_minions", 2), ("damage_all_minions", 2)}


def minion_effect_points(effect, value, slot="battlecry"):
    """SS2A points for one Battlecry/Deathrattle effect. None = unpriced.
    slot distinguishes Battlecry from Deathrattle: Battlecry targeted
    damage N>=2 costs N+1 (Full-set review); Deathrattle damage stays N."""
    if effect == "":
        return 0
    if effect == "damage":
        if slot == "battlecry" and value >= 2:
            return value + 1
        return value
    if effect == "damage_all_enemy_minions":
        return {1: 3, 2: 5}.get(value)
    if effect == "heal_hero":
        return {3: 1, 5: 2}.get(value)
    if effect == "draw":
        return {1: 2, 2: 3}.get(value)  # Batch 2 v2: draw 2 on minions 4 -> 3.
    if effect == "summon_token":
        return 1  # Batch 2 v2: summon a 1/1 token 2 -> 1 point.
    if effect == "gain_mana":
        return 1
    if effect == "buff_friendly":
        return {1: 2, 2: 4}.get(value)
    if effect == "draw_self_damage":
        return 1
    if effect == "damage_per_card_played":
        return 2 + 2 * value  # Full-set review: payoffs deal 2N per card played.
    if effect == "random_enemy_damage":
        return value  # Batch 2 v2: NO randomness discount on minions.
    if effect == "damage_split":
        return value  # N points, split randomly. N <= 5 (damage cap).
    if effect == "destroy_damaged":
        return 2
    if effect == "damage_per_hand_card":
        return 3 + 2 * value
    if effect == "recruit":
        return value + 2
    if effect == "buff_all_friendly":
        return 4 * value
    if effect == "swap_stats":
        return 2
    return None


def spell_table_cost(effect, value):
    """SS2B exact mana for a spell's effect at the given value. None = unpriced."""
    if effect == "damage":
        return TARGETED_DAMAGE_MANA.get(value)
    if effect == "damage_all_enemy_minions":
        return {1: 2, 2: 5}.get(value)
    if effect == "damage_all_minions":
        return 4 if value == 2 else None
    if effect == "random_enemy_damage":
        t = TARGETED_DAMAGE_MANA.get(value)
        return None if t is None else max(1, t - 2)  # Full-set review: -2, min 1.
    if effect == "random_minion_damage":
        return 2
    if effect == "heal_hero":
        return 1 if value == 3 else None
    if effect == "heal_draw":
        return 1
    if effect == "draw":
        return {1: 1, 2: 2, 3: 4}.get(value)
    if effect == "draw_self_damage":
        return 1
    if effect == "damage_per_card_played":
        return 2 + 2 * value  # Full-set review: payoffs deal 2N per card played.
    if effect == "destroy":
        return 5
    if effect == "steal_weak":
        return 4
    if effect == "swap_hands":
        return 3
    if effect == "coin_flip":
        return 1
    if effect == "gain_mana":
        return 1
    if effect == "buff_friendly":
        return {1: 1, 2: 2}.get(value)
    if effect == "damage_split":
        t = TARGETED_DAMAGE_MANA.get(value)
        return None if t is None else max(1, t - 2)  # Full-set review: -2, min 1.
    if effect == "destroy_damaged":
        return 2
    if effect == "damage_per_hand_card":
        return 3 + 2 * value
    if effect == "recruit":
        return value + 1
    if effect == "buff_all_friendly":
        return 3 * value
    if effect == "swap_stats":
        return 2
    return None


def valid_target_for(effect, target):
    """Whether `target` is legal for `effect`."""
    if effect in ("damage",):
        return target in ("any_enemy", "enemy_minion", "enemy_hero")
    if effect == "destroy":
        return target == "enemy_minion"
    if effect == "buff_friendly":
        return target == "friendly_minion"
    if effect == "swap_stats":
        return target == "enemy_minion"  # random enemy minion, fizzle if none
    if effect in ("heal_hero", "heal_draw", "draw", "summon_token",
                  "gain_mana", "coin_flip", "swap_hands",
                  "random_minion_damage", "damage_all_enemy_minions",
                  "damage_all_minions", "random_enemy_damage",
                  "draw_self_damage", "damage_per_card_played",
                  "steal_weak", "damage_split", "destroy_damaged",
                  "damage_per_hand_card", "recruit", "buff_all_friendly"):
        return target == "none"
    if effect == "":
        return target == "none"
    return False


def mech_sig(c):
    """Mechanical signature for dedup (name/flavor/art excluded)."""
    return (c["cost"], c["type"], c["attack"], c["health"],
            tuple(sorted(c.get("keywords", []))),
            c.get("effect", ""), c.get("effect_value", 0), c.get("target", ""),
            c.get("deathrattle", ""), c.get("deathrattle_value", 0),
            c.get("deathrattle_target", "none"),
            c.get("effect2", ""), c.get("effect2_value", 0),
            c.get("effect2_target", "none"))


def main():
    errors = []
    with open(CARDS_PATH) as f:
        cards = json.load(f)

    # --- shape / enums / uniqueness ---
    ids = [c.get("id") for c in cards]
    if len(ids) != len(set(ids)):
        dupes = [i for i, n in Counter(ids).items() if n > 1]
        errors.append(f"duplicate ids: {dupes}")
    required = {"id", "name", "class", "cost", "type", "attack", "health",
                "keywords", "effect", "effect_value", "target", "rarity",
                "text", "flavor", "art"}
    for c in cards:
        missing = required - set(c.keys())
        if missing:
            errors.append(f"{c.get('id')}: missing fields {sorted(missing)}")
        if c.get("class") not in CLASSES:
            errors.append(f"{c.get('id')}: bad class {c.get('class')}")
        if c.get("type") not in ("minion", "spell"):
            errors.append(f"{c.get('id')}: bad type {c.get('type')}")
        if c.get("rarity") not in RARITIES:
            errors.append(f"{c.get('id')}: bad rarity {c.get('rarity')}")
        if not set(c.get("keywords", [])) <= KEYWORDS:
            errors.append(f"{c.get('id')}: bad keywords {c.get('keywords')}")
        if c.get("effect", "") not in EFFECTS | {""}:
            errors.append(f"{c.get('id')}: effect not in closed list: {c.get('effect')}")
        dr = c.get("deathrattle", "")
        if dr not in EFFECTS | {""}:
            errors.append(f"{c.get('id')}: deathrattle not in closed list: {dr}")
        if c.get("target") not in TARGETS:
            errors.append(f"{c.get('id')}: bad target {c.get('target')}")
        if c.get("deathrattle_target", "none") not in TARGETS:
            errors.append(f"{c.get('id')}: bad deathrattle_target {c.get('deathrattle_target')}")
        if not (1 <= c.get("cost", 0) <= 10):
            errors.append(f"{c.get('id')}: cost {c.get('cost')} outside 1-10")
        if c.get("type") == "spell" and (c.get("attack") != 0 or c.get("health") != 0):
            errors.append(f"{c.get('id')}: spell with nonzero attack/health")
        if c.get("type") == "spell" and c.get("keywords"):
            errors.append(f"{c.get('id')}: spell with keywords")
        if c.get("type") == "spell" and c.get("effect", "") == "":
            errors.append(f"{c.get('id')}: spell with no effect")
        if c.get("type") == "minion" and (c.get("attack", -1) < 0 or c.get("health", -1) < 0):
            errors.append(f"{c.get('id')}: minion with negative stats")
        # Battlecry target (target) and Deathrattle target validated separately.
        if not valid_target_for(c.get("effect", ""), c.get("target")):
            errors.append(f"{c.get('id')}: target {c.get('target')} invalid "
                          f"for Battlecry effect {c.get('effect')}")
        if dr != "" and not valid_target_for(dr, c.get("deathrattle_target", "none")):
            errors.append(f"{c.get('id')}: deathrattle_target "
                          f"{c.get('deathrattle_target')} invalid for Deathrattle {dr}")
        if dr == "" and c.get("deathrattle_target", "none") != "none":
            errors.append(f"{c.get('id')}: deathrattle_target set with no Deathrattle")
        # Deathrattle-only minions must have target == "none" (target is Battlecry target).
        if c.get("effect", "") == "" and dr != "" and c.get("target") != "none":
            errors.append(f"{c.get('id')}: Deathrattle-only minion must have target 'none'")
        # draw_self_damage value fixed at 2.
        if c.get("effect") == "draw_self_damage" and c.get("effect_value") != 2:
            errors.append(f"{c.get('id')}: draw_self_damage value must be 2")
        if dr == "draw_self_damage" and c.get("deathrattle_value") != 2:
            errors.append(f"{c.get('id')}: draw_self_damage value must be 2")
        # buff_friendly Reginald-only.
        if (c.get("effect") == "buff_friendly" or dr == "buff_friendly") \
                and c.get("class") != "reginald":
            errors.append(f"{c.get('id')}: buff_friendly is Reginald-only")
        # Signature effects: only on Legendaries of the owning class.
        for slot, eff in (("effect", c.get("effect", "")),
                          ("deathrattle", dr)):
            if eff in SIGNATURES:
                owner = SIGNATURES[eff]
                if c.get("rarity") != "Legendary" or c.get("class") != owner:
                    errors.append(f"{c.get('id')}: signature effect {eff} "
                                  f"is {owner} Legendary-only")
        # No gain_mana on any Legendary (Batch 1 v2).
        if c.get("rarity") == "Legendary" and ("gain_mana" in
                (c.get("effect", ""), dr)):
            errors.append(f"{c.get('id')}: gain_mana on a Legendary")
        # damage_per_hand_card capped at N=1 (Batch 2 review).
        for eff, v in ((c.get("effect", ""), c.get("effect_value", 0)),
                       (dr, c.get("deathrattle_value", 0))):
            if eff == "damage_per_hand_card" and v > 1:
                errors.append(f"{c.get('id')}: damage_per_hand_card N={v} "
                              "exceeds cap 1")
        # 1-mana gain_mana spells are Presto-only (Batch 2 review; Grog cut).
        if c.get("type") == "spell" and c.get("cost") == 1 \
                and c.get("effect") == "gain_mana" and c.get("class") != "presto":
            errors.append(f"{c.get('id')}: 1-mana gain_mana spell must be Presto")
        # effect2 (Full-set review): second SMALL effect, spells ONLY, and
        # ONLY on the four explicit exception cards (cost <= 2). The second
        # effect is a corrective bonus (<= 1 mana of value) — it is NOT
        # priced into the spell's cost (cost still follows the first effect).
        e2 = c.get("effect2", "")
        e2v = c.get("effect2_value", 0)
        e2t = c.get("effect2_target", "none")
        if e2 != "":
            if c.get("type") != "spell":
                errors.append(f"{c.get('id')}: effect2 is spells-only")
            if c.get("id") not in EFFECT2_EXCEPTIONS:
                errors.append(f"{c.get('id')}: effect2 only allowed on "
                              f"exception cards {sorted(EFFECT2_EXCEPTIONS)}")
            if c.get("cost", 0) > 2:
                errors.append(f"{c.get('id')}: effect2 only allowed on "
                              "spells costing <= 2")
            if e2 not in EFFECTS:
                errors.append(f"{c.get('id')}: effect2 not in closed list: {e2}")
            if e2t not in TARGETS:
                errors.append(f"{c.get('id')}: bad effect2_target {e2t}")
            if e2 in EFFECTS and not valid_target_for(e2, e2t):
                errors.append(f"{c.get('id')}: effect2_target {e2t} invalid "
                              f"for effect2 {e2}")
            e2_price = spell_table_cost(e2, e2v) if e2 in EFFECTS else None
            if e2_price is None or e2_price > 1:
                errors.append(f"{c.get('id')}: effect2 must be SMALL "
                              f"(<= 1 mana of value), got {e2}({e2v}) = {e2_price}")
        elif "effect2_value" in c or "effect2_target" in c:
            if c.get("effect2_value", 0) != 0 or c.get("effect2_target", "none") != "none":
                errors.append(f"{c.get('id')}: effect2 fields set with no effect2")
        for v in (c.get("effect_value", 0) if c.get("effect") in DAMAGE_CAPPED
                  else 0,
                  c.get("deathrattle_value", 0) if dr in DAMAGE_CAPPED else 0):
            if v > 5:
                errors.append(f"{c.get('id')}: damage value {v} exceeds cap 5")
        # damage_per_card_played is Presto-only.
        if ("damage_per_card_played" in (c.get("effect", ""), dr)
                and c.get("class") != "presto"):
            errors.append(f"{c.get('id')}: damage_per_card_played is Presto-only")
        # Draw belongs to Presto: no draw-family effects on NEW non-Presto cards.
        if c.get("id") not in EXISTING and c.get("class") != "presto":
            if c.get("effect") in DRAW_FAMILY or dr in DRAW_FAMILY:
                errors.append(f"{c.get('id')}: draw-family effect on new non-Presto card")

    # --- existing-30 class/rarity ---
    for cid, (cls, rar) in EXISTING.items():
        match = [c for c in cards if c["id"] == cid]
        if not match:
            errors.append(f"existing card missing: {cid}")
        elif match[0]["class"] != cls or match[0]["rarity"] != rar:
            errors.append(f"{cid}: expected class {cls} / rarity {rar}, got "
                          f"{match[0]['class']} / {match[0]['rarity']}")

    # --- counts / curves / rarities ---
    by_class = {}
    for c in cards:
        by_class.setdefault(c["class"], []).append(c)
    if len(cards) != 340:
        errors.append(f"total cards {len(cards)}, expected 340")
    for cls, want in EXPECTED_COUNTS.items():
        got = len(by_class.get(cls, []))
        if got != want:
            errors.append(f"class {cls}: {got} cards, expected {want}")
    print("=== Curve report ===")
    for cls in ("neutral", "grunk", "agatha", "presto", "barnacle", "larry",
                "reginald"):
        curve = dict(sorted(Counter(c["cost"] for c in by_class.get(cls, [])).items()))
        print(f"  {cls}: {curve}")
        if curve != EXPECTED_CURVES.get(cls, {}):
            errors.append(f"curve {cls}: {curve}, expected {EXPECTED_CURVES.get(cls)}")
    print("=== Rarity report ===")
    for cls, want in EXPECTED_RARITY.items():
        got = dict(Counter(c["rarity"] for c in by_class.get(cls, [])))
        print(f"  {cls}: {got}")
        for r, n in want.items():
            if got.get(r, 0) != n:
                errors.append(f"rarity {cls}/{r}: {got.get(r, 0)}, expected {n}")

    # --- within-pool duplicates (SS5 rule (a)) ---
    pools = {"neutral": by_class.get("neutral", [])}
    for cls in CLASSES - {"neutral"}:
        pools[cls] = by_class.get(cls, []) + by_class.get("neutral", [])
    for pool_name, members in pools.items():
        seen = {}
        for c in members:
            s = mech_sig(c)
            if s in seen:
                errors.append(f"duplicate in {pool_name} pool: {c['id']} == {seen[s]}")
            seen[s] = c["id"]

    # --- vanilla cap (SS5 rule (b)): <= 3 vanilla minions per class ---
    for cls in CLASSES - {"neutral"}:
        van = [c["id"] for c in by_class.get(cls, [])
               if c["type"] == "minion" and not c.get("keywords")
               and not c.get("effect") and not c.get("deathrattle")]
        if len(van) > 3:
            errors.append(f"vanilla cap {cls}: {len(van)} > 3: {van}")
        print(f"  vanilla {cls}: {len(van)}")

    # --- legendary distinctiveness (SS5 rule (c)) ---
    # Signature effects are EXEMPT from uniqueness (at most 2 Legendaries
    # per class use the signature, by design). Non-signature Legendary
    # effects must be unique at value within the class (both slots count).
    for cls in CLASSES:
        seen = {}
        sig_count = 0
        for c in by_class.get(cls, []):
            if c["rarity"] != "Legendary" or c["id"] in EXISTING:
                continue
            pairs = set()
            if c.get("effect") and c["effect"] not in SIGNATURES:
                pairs.add((c["effect"], c.get("effect_value", 0)))
            if c.get("deathrattle") and c["deathrattle"] not in SIGNATURES:
                pairs.add((c["deathrattle"], c.get("deathrattle_value", 0)))
            if c.get("effect") in SIGNATURES or c.get("deathrattle") in SIGNATURES:
                sig_count += 1
            if not pairs and not c.get("effect") and not c.get("deathrattle"):
                errors.append(f"{c['id']}: Legendary with no effect")
            for p in pairs:
                if p in seen:
                    errors.append(f"{c['id']}: Legendary effect {p} duplicated "
                                  f"by {seen[p]} in {cls}")
                seen[p] = c["id"]
        if sig_count > 2:
            errors.append(f"{cls}: {sig_count} Legendaries use the signature "
                          "effect, max 2 (Batch 2 review)")

    # --- budget / pricing (with class premium) ---
    for c in cards:
        is_existing = c["id"] in EXISTING
        if c["type"] == "minion" and not is_existing:
            pts = 0
            for kw in c["keywords"]:
                pts += 1
            bc = minion_effect_points(c["effect"], c["effect_value"], "battlecry")
            dr_pts = minion_effect_points(c.get("deathrattle", ""),
                                          c.get("deathrattle_value", 0),
                                          "deathrattle")
            if bc is None:
                errors.append(f"{c['id']}: Battlecry effect {c['effect']} "
                              "has no minion price")
                continue
            if dr_pts is None:
                errors.append(f"{c['id']}: Deathrattle effect "
                              f"{c.get('deathrattle')} has no minion price")
                continue
            pts += bc + dr_pts
            total = c["attack"] + c["health"] + pts
            if c["class"] == "neutral":
                target = VANILLA[c["cost"]] - (1 if c["cost"] >= 7 else 0)
            else:
                target = VANILLA[c["cost"]] + class_premium(c["cost"])
            if abs(total - target) > 1:
                errors.append(f"{c['id']}: minion total {total} (A{c['attack']}"
                              f"+H{c['health']}+{pts}pts) vs premium target {target} "
                              f"(cost {c['cost']}, class {c['class']}), off by {total - target}")
            a, h = c["attack"], c["health"]
            if (h > 0 and a / h >= 3) or (a > 0 and h / a >= 3):
                if "design_note" not in c:
                    errors.append(f"{c['id']}: extreme skew {a}/{h} needs "
                                  "a design_note")
        if c["type"] == "spell":
            # No PURE deal-1 spells (Full-set review: Double Down violated
            # the §2B ban). A spell with effect damage 1 must have effect2.
            if c.get("effect") == "damage" and c.get("effect_value") == 1 \
                    and not c.get("effect2"):
                errors.append(f"{c['id']}: pure deal-1 spell banned (§2B); "
                              "add a second effect or re-cost")
            # Heal rule: no PURE heal spells above 1 mana.
            if c["effect"] == "heal_hero" and c["cost"] > 1:
                errors.append(f"{c['id']}: pure heal_hero spell above 1 mana "
                              "(heal rule)")
            want = spell_table_cost(c["effect"], c["effect_value"])
            if want is None:
                errors.append(f"{c['id']}: spell effect {c['effect']} "
                              "has no table price")
            elif c["id"] in EXISTING and EXISTING[c["id"]][0] == "neutral":
                # Grandfathered neutral (23): exact on-budget.
                if c["cost"] != want:
                    errors.append(f"{c['id']}: spell cost {c['cost']}, table "
                                  f"price for {c['effect']}({c['effect_value']}) "
                                  f"is {want}")
            elif c["class"] == "neutral":
                if c["cost"] != want:
                    errors.append(f"{c['id']}: spell cost {c['cost']}, table "
                                  f"price for {c['effect']}({c['effect_value']}) "
                                  f"is {want}")
            elif c["id"] == "agatha_wrath_mild":
                # EXPLICIT EXCEPTION (Batch 2 v2 re-test: +4.6/copy at 3
                # mana): Wrath stays at 4 despite the cost-1 fallback.
                if c["cost"] != 4:
                    errors.append(f"{c['id']}: Wrath exception requires cost 4, "
                                  f"got {c['cost']}")
            elif c["effect"] == "damage_per_card_played":
                # Payoff spells use the FLAT premium alt (table - 1), not the
                # band premium: Final Exam 6-1=5, Thesis 8-1=7, Grad 10-1=9.
                # (Before this pass all payoff spells sat in the 3-6 band,
                # where table-1 == table-premium(band), so the generic
                # branch passed them by coincidence.)
                if c["cost"] != want - 1:
                    errors.append(f"{c['id']}: spell cost {c['cost']}, "
                                  f"payoff table {want} -> flat premium alt "
                                  f"{want - 1}")
            elif (c["effect"], c["effect_value"]) in UNSCALABLE_SPELLS:
                # Cost-1 fallback: cost = table(value) - 1 (floor cost 1).
                if c["cost"] != want - 1:
                    errors.append(f"{c['id']}: spell cost {c['cost']}, "
                                  f"unscalable {c['effect']}({c['effect_value']}) "
                                  f"table {want} -> cost-1 fallback {want - 1}")
            else:
                # Scalable class spell: cost = table(value) - premium(band).
                if c["cost"] != want - class_premium(c["cost"]):
                    errors.append(f"{c['id']}: spell cost {c['cost']}, table "
                                  f"price for {c['effect']}({c['effect_value']}) "
                                  f"is {want}, premium(band) "
                                  f"{class_premium(c['cost'])} -> "
                                  f"expected {want - class_premium(c['cost'])}")

    # --- class bans ---
    GRUNK_BANNED = {"draw", "heal_draw", "coin_flip", "draw_self_damage",
                    "heal_hero", "buff_friendly", "damage_per_card_played",
                    "damage_all_minions"}
    for c in cards:
        effs = {c.get("effect", ""), c.get("deathrattle", "")} - {""}
        cls = c["class"]
        # effect2 (Full-set review): the second effect must obey the same
        # class bans as the first effect (set-based bans + burn targeting).
        e2 = c.get("effect2", "")
        if e2:
            e2t = c.get("effect2_target", "none")
            if cls == "grunk" and e2 in GRUNK_BANNED:
                errors.append(f"{c['id']}: Grunk banned effect2 {e2}")
            if cls == "agatha":
                if e2 in ("damage", "random_enemy_damage", "random_minion_damage") \
                        and e2t in ("any_enemy", "enemy_hero"):
                    errors.append(f"{c['id']}: Agatha face burn via effect2 {e2}")
                if e2 in {"buff_friendly", "damage_per_card_played", "draw_self_damage"}:
                    errors.append(f"{c['id']}: Agatha banned effect2 {e2}")
            if cls == "presto":
                if e2 in {"heal_hero", "heal_draw"}:
                    errors.append(f"{c['id']}: Presto banned heal via effect2")
                if e2 in {"damage_all_enemy_minions", "damage_all_minions"}:
                    errors.append(f"{c['id']}: Presto banned AoE via effect2")
            if cls == "larry":
                if e2 in {"draw", "heal_draw", "coin_flip", "draw_self_damage"}:
                    errors.append(f"{c['id']}: Larry banned draw via effect2")
                if e2 in {"heal_hero", "heal_draw"}:
                    errors.append(f"{c['id']}: Larry banned heal via effect2")
            if cls == "barnacle":
                if e2 == "destroy":
                    errors.append(f"{c['id']}: Barnacle banned destroy via effect2")
                if e2 in {"heal_hero", "heal_draw"}:
                    errors.append(f"{c['id']}: Barnacle banned heal via effect2")
                if e2 in {"damage_all_enemy_minions", "damage_all_minions"}:
                    errors.append(f"{c['id']}: Barnacle banned AoE via effect2")
            if cls == "reginald":
                if e2 in {"draw", "heal_draw", "coin_flip", "draw_self_damage"}:
                    errors.append(f"{c['id']}: Reginald banned draw via effect2")
                if e2 in {"damage_all_enemy_minions", "damage_all_minions"}:
                    errors.append(f"{c['id']}: Reginald banned AoE via effect2")
                if e2 in ("damage", "random_enemy_damage", "random_minion_damage") \
                        and e2t in ("any_enemy", "enemy_hero"):
                    errors.append(f"{c['id']}: Reginald burn via effect2 {e2}")
            if e2 == "buff_friendly" and cls != "reginald":
                errors.append(f"{c['id']}: buff_friendly effect2 is Reginald-only")
            if e2 == "damage_per_card_played" and cls != "presto":
                errors.append(f"{c['id']}: damage_per_card_played effect2 is Presto-only")
        if cls == "grunk":
            bad = effs & GRUNK_BANNED
            if bad:
                errors.append(f"{c['id']}: Grunk banned effects {sorted(bad)}")
            if c["type"] == "minion" and c["cost"] >= 6:
                errors.append(f"{c['id']}: Grunk minion costs 6+")
            # Grunk AoE capped at 1 damage (board clears belong to Agatha).
            for e in effs:
                if e in ("damage_all_enemy_minions", "damage_all_minions"):
                    v = c.get("effect_value", 0) if c.get("effect") == e \
                        else c.get("deathrattle_value", 0)
                    if v > 1:
                        errors.append(f"{c['id']}: Grunk AoE above 1 damage")
        if cls == "agatha":
            if "charge" in c["keywords"]:
                errors.append(f"{c['id']}: Agatha banned keyword charge")
            for e in effs:
                if e in ("damage", "random_enemy_damage", "random_minion_damage") \
                        and c["target"] in ("any_enemy", "enemy_hero"):
                    errors.append(f"{c['id']}: Agatha face burn via {e} "
                                  f"target {c['target']}")
            if c["cost"] == 1 and c["id"] != "healing_light":
                errors.append(f"{c['id']}: Agatha 1-cost card (only Healing "
                              "Light grandfathered)")
            if effs & {"buff_friendly", "damage_per_card_played",
                       "draw_self_damage"}:
                errors.append(f"{c['id']}: Agatha banned effect "
                              f"{sorted(effs & {'buff_friendly', 'damage_per_card_played', 'draw_self_damage'})}")
        if cls == "presto":
            if "taunt" in c["keywords"]:
                errors.append(f"{c['id']}: Presto banned keyword taunt")
            if effs & {"heal_hero", "heal_draw"}:
                errors.append(f"{c['id']}: Presto banned heal")
            if effs & {"damage_all_enemy_minions", "damage_all_minions"}:
                errors.append(f"{c['id']}: Presto banned AoE")
        if cls == "larry":
            if effs & {"draw", "heal_draw", "coin_flip", "draw_self_damage"}:
                errors.append(f"{c['id']}: Larry banned draw")
            if effs & {"heal_hero", "heal_draw"}:
                errors.append(f"{c['id']}: Larry banned heal")
            if "taunt" in c["keywords"]:
                errors.append(f"{c['id']}: Larry banned keyword taunt")
        if cls == "barnacle":
            if "destroy" in effs:
                errors.append(f"{c['id']}: Barnacle banned destroy")
            if effs & {"heal_hero", "heal_draw"}:
                errors.append(f"{c['id']}: Barnacle banned heal")
            if effs & {"damage_all_enemy_minions", "damage_all_minions"}:
                errors.append(f"{c['id']}: Barnacle banned AoE")
        if cls == "reginald":
            if effs & {"draw", "heal_draw", "coin_flip", "draw_self_damage"}:
                errors.append(f"{c['id']}: Reginald banned draw")
            if effs & {"damage_all_enemy_minions", "damage_all_minions"}:
                errors.append(f"{c['id']}: Reginald banned AoE")
            for e in effs:
                if e in ("damage", "random_enemy_damage", "random_minion_damage") \
                        and c["target"] in ("any_enemy", "enemy_hero"):
                    errors.append(f"{c['id']}: Reginald burn via {e}")
        # New-neutral bans (existing 23 grandfathered).
        if cls == "neutral" and c["id"] not in EXISTING:
            if effs & {"draw", "heal_hero", "heal_draw", "coin_flip",
                       "draw_self_damage"}:
                errors.append(f"{c['id']}: new neutral banned draw/heal")
            for e in effs:
                if e in ("damage",) and c["target"] in ("any_enemy", "enemy_hero"):
                    errors.append(f"{c['id']}: new neutral face burn via {e}")
                if e in ("random_enemy_damage", "random_minion_damage",
                         "damage_all_enemy_minions", "damage_all_minions"):
                    errors.append(f"{c['id']}: new neutral banned {e}")

    if errors:
        print(f"\n=== {len(errors)} VIOLATION(S) ===")
        for e in errors:
            print(f"  FAIL: {e}")
        sys.exit(1)
    print("\n=== ALL CHECKS PASS ===")
    sys.exit(0)


if __name__ == "__main__":
    main()
