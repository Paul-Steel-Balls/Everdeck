extends RefCounted
class_name CardDB

# Everdeck Phase 3 — card pool loads from res://data/cards.json (340 cards).
# This file is the ONLY source of truth for card data at runtime: no
# hardcoded card table. Each JSON row is normalized on load (missing
# optional fields get defaults) so game code can always read every field.
# Fields: id, name, class, cost, type ("minion"/"spell"), attack, health,
# keywords (Array of "taunt"/"charge"), effect, effect_value, target,
# rarity, text, flavor, art, deathrattle, deathrattle_value,
# deathrattle_target, effect2, effect2_value, effect2_target (effect2
# only on the 4 exception spells).

static var CARDS: Array = []
static var _loaded: bool = false


static func _static_init() -> void:
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
	if f == null:
		push_error("CardDB: could not open res://data/cards.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var arr: Array = []
	if parsed is Array:
		arr = parsed
	elif parsed is Dictionary:
		arr = parsed.get("cards", [])
	for c in arr:
		if c is Dictionary:
			_normalize(c)
	CARDS = arr


static func _normalize(c: Dictionary) -> void:
	c["class"] = str(c.get("class", "neutral"))
	c["rarity"] = str(c.get("rarity", "Common"))
	c["keywords"] = c.get("keywords", [])
	c["effect"] = str(c.get("effect", ""))
	c["effect_value"] = int(c.get("effect_value", 0))
	c["target"] = str(c.get("target", "none"))
	c["deathrattle"] = str(c.get("deathrattle", ""))
	c["deathrattle_value"] = int(c.get("deathrattle_value", 0))
	c["deathrattle_target"] = str(c.get("deathrattle_target", "none"))
	c["effect2"] = str(c.get("effect2", ""))
	c["effect2_value"] = int(c.get("effect2_value", 0))
	c["effect2_target"] = str(c.get("effect2_target", "none"))


# Token minion (not in the pool — only summoned by Middle Manager).
const TOKEN_SQUIRELING: Dictionary = {"id": "squireling", "name": "Kevin, the Intern", "cost": 1, "type": "minion", "attack": 1, "health": 1, "text": "", "flavor": "Unpaid. Overworked. Somehow still smiling.", "art": "intern", "keywords": [], "effect": "", "effect_value": 0, "target": "none", "class": "neutral", "rarity": "Common", "deathrattle": "", "deathrattle_value": 0, "deathrattle_target": "none", "effect2": "", "effect2_value": 0, "effect2_target": "none"}

# Token minion (not in the pool — only summoned by Barnacle's hero power).
const TOKEN_DECKHAND: Dictionary = {"id": "deckhand", "name": "Deckhand", "cost": 1, "type": "minion", "attack": 1, "health": 1, "text": "", "flavor": "Swabs decks. Sings shanties. Gets paid in biscuits.", "art": "deckhand", "keywords": [], "effect": "", "effect_value": 0, "target": "none", "class": "barnacle", "rarity": "Common", "deathrattle": "", "deathrattle_value": 0, "deathrattle_target": "none", "effect2": "", "effect2_value": 0, "effect2_target": "none"}

# Generic 1/1 token for summon_token cards whose token name is parsed out
# of their rules text (all summon_token cards read "Summon a 1/1 <name>.").
# The board shows the parsed name; this dict is only the stat template.
const TOKEN_GENERIC: Dictionary = {"id": "token", "name": "Token", "cost": 1, "type": "minion", "attack": 1, "health": 1, "text": "", "flavor": "", "art": "token", "keywords": [], "effect": "", "effect_value": 0, "target": "none", "class": "neutral", "rarity": "Common", "deathrattle": "", "deathrattle_value": 0, "deathrattle_target": "none", "effect2": "", "effect2_value": 0, "effect2_target": "none"}

# The Coin — NOT in the pool, NOT in decks. Given to Player 2 at game start
# (Balance Patch v1). 0-cost spell: gain 1 mana this turn only.
const COIN: Dictionary = {"id": "coin", "name": "Lucky Penny", "cost": 0, "type": "spell", "attack": 0, "health": 0, "text": "Gain 1 Mana this turn only.", "flavor": "Found it under the couch. Still counts.", "art": "coin", "keywords": [], "effect": "gain_mana", "effect_value": 1, "target": "none", "class": "neutral", "rarity": "Common", "deathrattle": "", "deathrattle_value": 0, "deathrattle_target": "none", "effect2": "", "effect2_value": 0, "effect2_target": "none"}

# Hero powers (Phase 1 §3/§4): one per class, 2 mana, once per turn.
# Chosen by class selection, NOT by deckbuilding. effect/target follow the
# same effect system as cards (Grunk's fixed enemy_hero target is built
# by the caller; Reginald's friendly_minion target is player-chosen).
const HERO_POWERS: Dictionary = {
	"grunk": {"name": "Throw a Firecracker", "text": "Deal 2 damage to the enemy Boss.", "effect": "damage", "value": 2, "target": "enemy_hero"},
	"agatha": {"name": "A Nice Cup of Tea", "text": "Restore 3 Health to your Boss.", "effect": "heal_hero", "value": 3, "target": "none"},
	"presto": {"name": "Forbidden Homework", "text": "Draw a card. Take 2 damage.", "effect": "draw_self_damage", "value": 2, "target": "none"},
	"barnacle": {"name": "Hire a Deckhand", "text": "Summon a 1/1 Deckhand.", "effect": "summon_token", "value": 0, "target": "none"},
	"reginald": {"name": "Knight's Blessing", "text": "Give a friendly Crew member +1/+1.", "effect": "buff_friendly", "value": 1, "target": "friendly_minion"},
	"larry": {"name": "Feeling Lucky", "text": "Deal 1 damage to a random enemy.", "effect": "random_enemy_damage", "value": 1, "target": "none"},
}

const CLASS_IDS: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]

const CLASS_NAMES: Dictionary = {
	"grunk": "Grunk",
	"agatha": "Grandma Agatha",
	"presto": "Presto",
	"barnacle": "Captain Barnacle",
	"reginald": "Sir Reginald",
	"larry": "\"Lucky\" Larry",
}


# Balance testing only (tools/sim_*): Signature Moves to try in place of
# the real ones. Empty in the real game.
static var hero_power_overrides: Dictionary = {}
# Balance testing only: a different Deckhand (Barnacle's Signature Move
# token) to try. Empty in the real game.
static var deckhand_override: Dictionary = {}


static func deckhand_token() -> Dictionary:
	return deckhand_override if not deckhand_override.is_empty() else TOKEN_DECKHAND


static func hero_power_for(class_id: String) -> Dictionary:
	if hero_power_overrides.has(class_id):
		return hero_power_overrides[class_id]
	return HERO_POWERS.get(class_id, {})


# Balance testing only: apply a what-if patch in memory, never saved.
# {"cards": {id: {field: value, ...}}, "powers": {class: {...}},
#  "payoff_cap": n}. Returns a list of problems (unknown ids/fields).
static func apply_test_patch(patch: Dictionary) -> Array:
	_ensure_loaded()
	var problems: Array = []
	var cards: Dictionary = patch.get("cards", {})
	for cid in cards:
		var c: Dictionary = get_card(str(cid))
		if c.is_empty():
			problems.append("no card " + str(cid))
			continue
		for k in cards[cid]:
			if not c.has(k):
				problems.append("%s has no field %s" % [cid, k])
				continue
			var v: Variant = cards[cid][k]
			c[k] = int(v) if (v is float and c[k] is int) else v
	var powers: Dictionary = patch.get("powers", {})
	for cls in powers:
		var hp: Dictionary = HERO_POWERS.get(cls, {}).duplicate()
		hp.merge(powers[cls], true)
		if hp.has("value"):
			hp["value"] = int(hp["value"])
		hero_power_overrides[cls] = hp
	if patch.has("deckhand"):
		var dh: Dictionary = TOKEN_DECKHAND.duplicate(true)
		for k in patch["deckhand"]:
			var v2: Variant = patch["deckhand"][k]
			dh[k] = int(v2) if v2 is float else v2
		deckhand_override = dh
	return problems


static func class_display_name(class_id: String) -> String:
	return str(CLASS_NAMES.get(class_id, class_id))


static func get_card(card_id: String) -> Dictionary:
	_ensure_loaded()
	if card_id == "squireling":
		return TOKEN_SQUIRELING
	if card_id == "deckhand":
		return deckhand_token()
	if card_id == "token":
		return TOKEN_GENERIC
	if card_id == "coin":
		return COIN
	for c in CARDS:
		if c["id"] == card_id:
			return c
	return {}


static func card_ids() -> Array:
	_ensure_loaded()
	var out: Array = []
	for c in CARDS:
		out.append(c["id"])
	return out


# Cards a player of `class_id` may put in their deck: own class + neutrals.
static func cards_for_class(class_id: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for c in CARDS:
		if c["class"] == class_id or c["class"] == "neutral":
			out.append(c)
	return out


static func max_copies(card: Dictionary) -> int:
	return 1 if str(card.get("rarity", "")) == "Legendary" else 2


# The token a summon_token card summons. Sprint 1a: read the card's
# "token" field ({name, art}) first; fall back to parsing the rules text
# with a regex ONLY if the field is missing. All tokens are 1/1 with no
# keywords. Kevin keeps his existing squireling id/flavor (the summoner
# test pins it); every other token is a TOKEN_GENERIC copy with the
# field's name + art.
static func token_for(card: Dictionary) -> Dictionary:
	var tok: Dictionary = {}
	if card.get("token") is Dictionary:
		tok = card["token"]
	if not tok.is_empty():
		var tname: String = str(tok.get("name", ""))
		if tname == "Kevin, the Intern":
			return TOKEN_SQUIRELING
		var t: Dictionary = TOKEN_GENERIC.duplicate()
		t["name"] = tname
		t["art"] = str(tok.get("art", "token"))
		return t
	var re := RegEx.new()
	if re.compile("Summon a 1/1 ([^.]+)\\.") != OK:
		return TOKEN_SQUIRELING
	var m := re.search(str(card.get("text", "")))
	if m == null:
		return TOKEN_SQUIRELING
	var tname2: String = m.get_string(1)
	if tname2 == "Kevin, the Intern":
		return TOKEN_SQUIRELING
	var t2: Dictionary = TOKEN_GENERIC.duplicate()
	t2["name"] = tname2
	return t2
