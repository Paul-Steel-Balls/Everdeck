#!/usr/bin/env python3
"""Job 1: Batch 1 v2 fixes for Everdeck cards.json."""
import json, re, sys

PATH = "game/data/cards.json"
with open(PATH) as f:
    cards = json.load(f)
by_id = {c["id"]: c for c in cards}

def set_card(cid, **kw):
    c = by_id[cid]
    for k, v in kw.items():
        c[k] = v
    return c

# --- 1a. Demo Crew 3/3 -> 3/2 Charge (text fixed by the 13-card loop) ---
set_card("grunk_demo_crew", health=2)

# --- 1c. Agatha 7-9: pot -> Taunt; biggest -> Battlecry heal 3 ---
set_card("agatha_pot", keywords=["taunt"], text="Taunt.")
set_card("agatha_biggest", effect="heal_hero", effect_value=3, target="none",
         text="Battlecry: Restore 3 Health to your hero.")

# --- 2. Finale -> Taunt ---
f = by_id["grunk_finale"]
f["keywords"] = ["taunt"]
f["text"] = "Taunt. Deathrattle: Deal 1 damage to ALL enemy minions."
f["design_note"] = (f.get("design_note", "") +
    " Taunt added (Batch 1 v2): without Taunt it never died, so the "
    "Deathrattle never fired.").strip()

# --- 3. Text fixes: 13 cards whose Taunt/Charge isn't in text ---
fixed = []
for c in cards:
    kws = c.get("keywords", [])
    txt = c.get("text") or ""
    if "taunt" in kws and "Taunt" not in txt:
        c["text"] = ("Taunt. " + txt).strip() if txt else "Taunt."
        fixed.append(c["id"])
    elif "charge" in kws and "Charge" not in txt:
        c["text"] = ("Charge. " + txt).strip() if txt else "Charge."
        fixed.append(c["id"])
print("text fixes:", len(fixed), fixed)

# --- 4. Signature reworks: 10 Legendaries ---
SIG = "Legendary: {} signature effect ({})."
# Grunk: damage_split
set_card("grunk_sparky", attack=2, health=1, effect="damage_split",
         effect_value=2, target="none",
         text="Battlecry: Deal 2 damage, split randomly among enemy characters.",
         design_note=SIG.format("Grunk", "damage_split"))
set_card("grunk_dan", attack=2, health=2, effect="damage_split",
         effect_value=3, target="none",
         text="Battlecry: Deal 3 damage, split randomly among enemy characters.",
         design_note=SIG.format("Grunk", "damage_split"))
set_card("grunk_king", attack=2, health=2, effect="damage_split",
         effect_value=4, target="none",
         text="Battlecry: Deal 4 damage, split randomly among enemy characters.",
         design_note=SIG.format("Grunk", "damage_split"))
set_card("grunk_jr", attack=2, health=1, effect="damage_split",
         effect_value=5, target="none",
         text="Battlecry: Deal 5 damage, split randomly among enemy characters.",
         design_note=SIG.format("Grunk", "damage_split"))
set_card("grunk_grandma", attack=4, health=4, effect="", effect_value=0,
         target="none", deathrattle="damage_split", deathrattle_value=2,
         deathrattle_target="none",
         text="Deathrattle: Deal 2 damage, split randomly among enemy characters.",
         design_note=SIG.format("Grunk", "damage_split"))
# Agatha: destroy_damaged
set_card("agatha_timmy", attack=2, health=1, effect="destroy_damaged",
         effect_value=0, target="none",
         text="Battlecry: Destroy all damaged enemy minions.",
         design_note=SIG.format("Agatha", "destroy_damaged"))
set_card("agatha_bobby", attack=3, health=2, effect="destroy_damaged",
         effect_value=0, target="none",
         text="Battlecry: Destroy all damaged enemy minions.",
         design_note=SIG.format("Agatha", "destroy_damaged"))
set_card("agatha_last", attack=4, health=3, effect="", effect_value=0,
         target="none", deathrattle="destroy_damaged", deathrattle_value=0,
         deathrattle_target="none",
         text="Deathrattle: Destroy all damaged enemy minions.",
         design_note=SIG.format("Agatha", "destroy_damaged"))
set_card("agatha_unleashed", attack=5, health=5, effect="destroy_damaged",
         effect_value=0, target="none",
         text="Battlecry: Destroy all damaged enemy minions.",
         design_note=SIG.format("Agatha", "destroy_damaged"))
set_card("agatha_soupocalypse", attack=7, health=6, effect="", effect_value=0,
         target="none", deathrattle="destroy_damaged", deathrattle_value=0,
         deathrattle_target="none",
         text="Deathrattle: Destroy all damaged enemy minions.",
         design_note=SIG.format("Agatha", "destroy_damaged"))

# --- 3b. Stale design_notes ---
STALE_SENT = "Target field describes the Deathrattle (no Battlecry on this card)."
for cid in ("neutral_slice", "grunk_boom_squad", "grunk_brigade", "grunk_aunt",
            "grunk_warmachine", "grunk_megabomb", "agatha_marge", "agatha_doom"):
    c = by_id[cid]
    note = c.get("design_note", "")
    note = note.replace(STALE_SENT, "").strip()
    note = re.sub(r"\s+", " ", note).strip()
    if note:
        c["design_note"] = note
    else:
        c.pop("design_note", None)
# wrath_full skew note: card is 6/3, note says 6/2
w = by_id["agatha_wrath_full"]
if "design_note" in w:
    w["design_note"] = w["design_note"].replace("6/2", "6/3")

# --- audit: any other note mentioning a stat split that mismatches? ---
for c in cards:
    note = c.get("design_note", "")
    for m in re.finditer(r"\((\d+)/(\d+)\)", note):
        a, h = int(m.group(1)), int(m.group(2))
        if (a, h) != (c["attack"], c["health"]):
            print(f"NOTE MISMATCH {c['id']}: note says {a}/{h}, card is "
                  f"{c['attack']}/{c['health']}: {note[:100]}")

with open(PATH, "w") as f:
    json.dump(cards, f, indent=2)
    f.write("\n")
print("wrote", len(cards), "cards")
