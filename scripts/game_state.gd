extends RefCounted
class_name GameState

# Pure game logic for Everdeck — no UI. The UI layer (main.gd) calls these
# methods and reads the public fields. Headless tests target this class.
# Implements Phase 1 §4 exactly: Deathrattle (batch timing, chains, random
# targeting), all 17 base effects + 6 signature effects, effect2 spells,
# hero powers (2 mana, once/turn), cards-played counter, 7-minion cap.

const STARTING_HP: int = 30
const MAX_MANA: int = 10
const MAX_BOARD: int = 7
const MAX_HAND: int = 10
const DECK_SIZE: int = 30
const MAX_COPIES: int = 2
const HERO_POWER_COST: int = 2

var players: Array = []
var active: int = 0
var winner: int = -1
# The most "other cards" a per-card-played payoff counts (Firecracker
# Mage, Final Exam, Thesis Defense, Graduation Day). Balance patch 2:
# uncapped, Presto could kill from 30 Health in one turn (40 damage at
# 10 mana, a kill from 6 mana). The balance tools may change it to test;
# -1 means no cap.
static var payoff_cap: int = 3
var log: Array = []
var rng := RandomNumberGenerator.new()
# Turn count: number of player-turns that have begun (setup starts turn 1).
var turn_count: int = 0
# While > 0, lethal is deferred until the whole action (card play / attack /
# hero power, including Deathrattles and effect2) has resolved.
var _lethal_deferred: int = 0
# --- Sprint 1a: event stream (view/animation only — zero rule changes) ---
# Every state change that the view can animate is appended here, in
# resolution order. The UI takes the queue after each player action
# (take_events) and plays it; the stream never affects the rules.
var events: Array = []
# Incrementing counter for stable minion uids. NOT rng — seeded results
# must stay identical.
var _next_uid: int = 0
# False while setup() runs, so the initial deal / first turn's refills do
# not pollute the stream with events the UI would replay on the first
# real action.
var _events_enabled: bool = true
# --- Sprint 1b: effect source context (for damage/heal/buff events) ---
# While an effect resolves, these name the card/minion that caused it:
# - Entrance / Final Bow: _src_uid = the minion's uid, _src_card = its card
# - Spell: _src_uid = -1, _src_card = the spell's card id
# - Signature move: _src_uid = -1, _src_card = "" (no card)
# - Attack damage: set explicitly (attacker/defender uid, card "")
# - Fatigue: explicit -1 / "" (the empty deck, not a card)
# The resolve sites (play_card minion/spell, use_hero_power,
# _resolve_deathrattle) save/restore these around _resolve_effect, so
# nested resolution (a Deathrattle firing during an action) stays correct.
var _src_uid: int = -1
var _src_card: String = ""
# --- Mechanics pass, wave 1 ---
# Whenever triggers wait in this queue and fire at safe points (_settle),
# never in the middle of an effect that is walking a board.
# Entries: {"owner": int, "uid": int, "card_id": String, "trig": Dictionary}
var _trigger_queue: Array = []
# True while a trigger's effect resolves. Triggers don't set off other
# triggers (no loops); deaths they cause still do, after they finish.
var _in_trigger: bool = false
# Keywords a Crew member can carry, beyond taunt (Bouncer) and charge
# (Hustle). Shown to players as Stunt Double, Backstage, Encore,
# Showstopper and Tip Jar.
const STATE_KEYWORDS: Array = ["shield", "stealth", "windfury", "poison", "lifesteal"]


func _emit(type: String, data: Dictionary) -> void:
	if not _events_enabled:
		return
	events.append({"type": type, "data": data})


# Returns the queued events and clears the queue.
func take_events() -> Array:
	var out: Array = events
	events = []
	return out


# Stable uid for a minion dict. Assigns one lazily if the dict has none
# (tests build minions by hand; the view assigns on first sight). The uid
# lives on the dict, so it follows the minion when minions to its left die
# and the board shifts.
func uid_for(m: Dictionary) -> int:
	if m.has("uid"):
		return int(m["uid"])
	var uid: int = _next_uid
	_next_uid += 1
	m["uid"] = uid
	return uid


# The minion dict for a uid on a player's board ({} if not there).
func minion_by_uid(p_idx: int, uid: int) -> Dictionary:
	if uid < 0:
		return {}
	for m in players[p_idx]["board"]:
		if m.has("uid") and int(m["uid"]) == uid:
			return m
	return {}


# Board index for a uid (-1 if not there). The view resolves picks (which
# are uid-based) through this, never through board-index arithmetic.
func minion_index_by_uid(p_idx: int, uid: int) -> int:
	if uid < 0:
		return -1
	var board: Array = players[p_idx]["board"]
	for i in board.size():
		if board[i].has("uid") and int(board[i]["uid"]) == uid:
			return i
	return -1


func _init() -> void:
	rng.randomize()


func set_seed(s: int) -> void:
	rng.seed = s


# Deep copy for look-ahead (the computer opponent tries actions on a
# copy). The copy emits no events and gets a FRESH random seed, so the AI
# cannot peek at how a random effect will land.
func clone() -> GameState:
	var g := GameState.new()
	g.players = players.duplicate(true)
	g.active = active
	g.winner = winner
	g.turn_count = turn_count
	g._next_uid = _next_uid
	g._events_enabled = false
	g.rng.randomize()
	return g


# --- Setup ---

func setup(deck0: Array, deck1: Array, class0: String = "neutral", class1: String = "neutral") -> void:
	players = [_new_player(deck0, class0), _new_player(deck1, class1)]
	active = 0
	winner = -1
	log = []
	turn_count = 0
	events = []
	_next_uid = 0
	_events_enabled = false  # setup's deal / first turn must not enter the stream
	_shuffle(players[0]["deck"])
	_shuffle(players[1]["deck"])
	for _i in 3:
		_draw(0, true)
	for _i in 5:
		_draw(1, true)
	# Balance Patch v1 (corrected): Player 2 gets The Coin (not in the
	# deck, not in the pool) and is dealt 5 cards. P2's first draw on
	# their turn 1 then leaves them at 6 cards + Coin vs P1's 4.
	# (Simulation: 4 + Coin gives P1 58.2%; 5 + Coin gives 51.2%.)
	players[1]["hand"].append("coin")
	_start_turn()
	_events_enabled = true


func _new_player(deck: Array, class_id: String) -> Dictionary:
	return {
		"hp": STARTING_HP,
		"mana": 0,
		"max_mana": 0,
		"deck": deck.duplicate(),
		"decklist": deck.duplicate(),
		"hand": [],
		"board": [],
		"fatigue": 0,
		"class": class_id,
		"hero_power_used": false,
		"cards_played_this_turn": 0,
		# On Credit: mana owed (locked at the start of the next turn).
		"overload_next": 0,
		"overload_locked": 0,
	}


func _shuffle(deck: Array) -> void:
	# Fisher-Yates with our own RNG (seedable for tests).
	for i in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


# --- Turn flow ---

func _start_turn() -> void:
	turn_count += 1
	_emit("turn_start", {"player": active})
	var p: Dictionary = players[active]
	var mana_before: int = p["mana"]
	var max_before: int = p["max_mana"]
	p["max_mana"] = min(MAX_MANA, p["max_mana"] + 1)
	p["mana"] = p["max_mana"]
	# On Credit: mana borrowed last turn is locked this turn.
	var owed: int = int(p.get("overload_next", 0))
	p["overload_locked"] = owed
	p["overload_next"] = 0
	if owed > 0:
		p["mana"] = maxi(0, int(p["mana"]) - owed)
		_emit("overload_locked", {"player": active, "amount": owed})
	if p["mana"] != mana_before or p["max_mana"] != max_before:
		_emit("mana_changed", {"player": active, "mana": p["mana"], "max_mana": p["max_mana"]})
	p["hero_power_used"] = false
	p["cards_played_this_turn"] = 0
	for m in p["board"]:
		m["sick"] = false
		m["can_attack"] = true
		m["attacks_left"] = 2 if m.get("windfury", false) else 1
	# Start-of-turn effects fire before the draw.
	_lethal_deferred += 1
	_queue_triggers(active, "start_of_turn")
	_settle()
	_lethal_deferred -= 1
	_check_lethal()
	if winner != -1:
		return
	_draw(active, false)


func end_turn() -> void:
	if winner != -1:
		return
	# End-of-turn effects, then Stage Fright wears off for this player's
	# Crew (a Crew member frozen on the enemy's turn misses one turn).
	_lethal_deferred += 1
	_queue_triggers(active, "end_of_turn")
	_settle()
	_lethal_deferred -= 1
	_check_lethal()
	if winner != -1:
		return
	for m in players[active]["board"]:
		if int(m.get("frozen", 0)) > 0:
			m["frozen"] = int(m["frozen"]) - 1
			if int(m["frozen"]) == 0:
				_emit("thawed", {"player": active, "uid": uid_for(m)})
	active = 1 - active
	_start_turn()


# --- Drawing / fatigue ---

func _draw(p_idx: int, initial: bool) -> void:
	var p: Dictionary = players[p_idx]
	if p["deck"].is_empty():
		p["fatigue"] += 1
		_emit("empty_deck", {"player": p_idx, "amount": p["fatigue"]})
		p["hp"] -= p["fatigue"]
		_emit("damage", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": p["fatigue"], "source_uid": -1, "source_card_id": ""})
		log.append("Empty deck! %d damage." % p["fatigue"])
		_check_lethal()
		return
	var card_id: String = p["deck"].pop_front()
	if p["hand"].size() >= MAX_HAND:
		_emit("card_burned", {"player": p_idx, "card_id": card_id})
		log.append("Burned: %s!" % CardDB.get_card(card_id)["name"])
	else:
		p["hand"].append(card_id)
		if not initial:
			_emit("draw", {"player": p_idx, "card_id": card_id})


func draw_cards(p_idx: int, n: int) -> void:
	for _i in n:
		if winner != -1:
			return
		_draw(p_idx, false)


# --- Playing cards ---

func can_play(p_idx: int, hand_idx: int) -> bool:
	if p_idx != active or winner != -1:
		return false
	var p: Dictionary = players[p_idx]
	if hand_idx < 0 or hand_idx >= p["hand"].size():
		return false
	var card: Dictionary = CardDB.get_card(p["hand"][hand_idx])
	if card.is_empty() or p["mana"] < card["cost"]:
		return false
	if card["type"] == "minion" and p["board"].size() >= MAX_BOARD:
		return false
	return true


# target: Dictionary {"kind": "hero"/"minion", "player": int, "board_idx": int} or {}
# Spells: a targeted primary effect with no valid target cannot be played.
# Minions: ALWAYS playable — a Battlecry with no valid target fizzles.
func play_card(p_idx: int, hand_idx: int, target: Dictionary = {}) -> bool:
	if not can_play(p_idx, hand_idx):
		return false
	var p: Dictionary = players[p_idx]
	var card_id: String = p["hand"][hand_idx]
	var card: Dictionary = CardDB.get_card(card_id)
	if card["type"] == "spell" and _requires_player_target(card, false):
		if target.is_empty() or not _is_valid_target(p_idx, card["target"], target, false):
			return false
	var hand_before: int = p["hand"].size()
	var mana_before: int = p["mana"]
	var max_mana_before: int = p["max_mana"]
	p["hand"].remove_at(hand_idx)
	p["mana"] -= card["cost"]
	_emit("card_played", {"player": p_idx, "card_id": card_id})
	_lethal_deferred += 1
	if card["type"] == "minion":
		_summon(p_idx, card, true)
		var src_idx: int = p["board"].size() - 1
		if card["effect"] != "":
			if not _requires_player_target(card, true) or _is_valid_target(p_idx, card["target"], target, true, src_idx):
				# Sprint 1b: the Entrance event + source context, so the
				# director can flash the source minion and the damage /
				# heal / buff events carry its uid + card id. Emitted only
				# when the Entrance actually resolves (not on fizzle).
				var src_uid: int = uid_for(p["board"][src_idx])
				var prev_uid: int = _src_uid
				var prev_card: String = _src_card
				_src_uid = src_uid
				_src_card = card_id
				_emit("entrance", {"player": p_idx, "uid": src_uid, "card_id": card_id})
				_resolve_effect(p_idx, card["effect"], card["effect_value"], target, hand_before, CardDB.token_for(card))
				_src_uid = prev_uid
				_src_card = prev_card
			else:
				log.append("Entrance fizzled — no valid target.")
	else:
		# Spell: the cast itself is an event (target resolved to a uid).
		var sc_kind: String = "none"
		var sc_player: int = -1
		var sc_uid: int = -1
		if not target.is_empty():
			sc_kind = str(target.get("kind", "none"))
			sc_player = int(target.get("player", -1))
			if sc_kind == "minion":
				var tb: Array = players[sc_player]["board"]
				var ti: int = int(target.get("board_idx", -1))
				if ti >= 0 and ti < tb.size():
					sc_uid = uid_for(tb[ti])
		_emit("spell_cast", {"player": p_idx, "card_id": card_id, "target_kind": sc_kind, "target_player": sc_player, "target_uid": sc_uid})
		# Spells resolve with source = the spell card (uid -1).
		var prev_uid2: int = _src_uid
		var prev_card2: String = _src_card
		_src_uid = -1
		_src_card = card_id
		_resolve_effect(p_idx, card["effect"], card["effect_value"], target, -1)
		if str(card.get("effect2", "")) != "":
			if not _requires_player_target(card, false, true) or _is_valid_target(p_idx, card["effect2_target"], target, false):
				_resolve_effect(p_idx, card["effect2"], card["effect2_value"], target, -1)
			else:
				log.append("Second effect fizzled — no valid target.")
		_src_uid = prev_uid2
		_src_card = prev_card2
	p["cards_played_this_turn"] += 1
	if int(card.get("overload", 0)) > 0:
		p["overload_next"] = int(p.get("overload_next", 0)) + int(card["overload"])
		_emit("overload", {"player": p_idx, "amount": int(card["overload"]), "owed": p["overload_next"]})
	var played_uid: int = -1
	if card["type"] == "minion" and not p["board"].is_empty():
		played_uid = uid_for(p["board"][p["board"].size() - 1])
	_queue_triggers(p_idx, "friendly_card_played", played_uid)
	if card["type"] == "spell":
		_queue_triggers(p_idx, "friendly_trick_played")
	_settle()
	_lethal_deferred -= 1
	if p["mana"] != mana_before or p["max_mana"] != max_mana_before:
		_emit("mana_changed", {"player": p_idx, "mana": p["mana"], "max_mana": p["max_mana"]})
	_check_lethal()
	return true


func _summon(p_idx: int, card: Dictionary, sick: bool) -> void:
	var p: Dictionary = players[p_idx]
	if p["board"].size() >= MAX_BOARD:
		return
	var kws: Array = card.get("keywords", [])
	var charge: bool = kws.has("charge")
	var m: Dictionary = {
		"card_id": card["id"],
		"name": card["name"],
		"attack": card["attack"],
		"health": card["health"],
		"max_health": card["health"],
		"taunt": kws.has("taunt"),
		"can_attack": charge,
		"attacks_left": (2 if kws.has("windfury") else 1) if charge else 0,
		"sick": sick and not charge,
		# Presentation: the art this minion shows. Tokens carry their own
		# token art (from the card's "token" field); regular minions carry
		# their card art. The view prefers this over the card lookup.
		"art": card.get("art", ""),
	}
	# Mechanics pass: only the state a Crew member actually has is stored
	# (the AI copies boards thousands of times a turn; absent = false/0).
	# Vibe bonuses, Stage Fright and Heckle add their keys when they happen;
	# Heckle reads the printed stats from the card.
	for k in STATE_KEYWORDS:
		if kws.has(k):
			m[k] = true
	m["uid"] = _next_uid
	_next_uid += 1
	p["board"].append(m)
	_emit("minion_summoned", {"player": p_idx, "uid": m["uid"], "card_id": card["id"], "board_idx": p["board"].size() - 1})
	_queue_triggers(p_idx, "friendly_summon", int(m["uid"]))
	_refresh_vibes()


# --- Hero powers ---

func hero_power(p_idx: int) -> Dictionary:
	return CardDB.hero_power_for(str(players[p_idx].get("class", "")))


func can_use_hero_power(p_idx: int, target: Dictionary = {}) -> bool:
	if p_idx != active or winner != -1:
		return false
	var p: Dictionary = players[p_idx]
	if p["hero_power_used"] or p["mana"] < HERO_POWER_COST:
		return false
	var hp: Dictionary = hero_power(p_idx)
	if hp.is_empty():
		return false
	if str(hp["effect"]) == "summon_token" and p["board"].size() >= MAX_BOARD:
		return false
	if str(hp["target"]) == "friendly_minion":
		if target.is_empty() or not _is_valid_target(p_idx, "friendly_minion", target, false):
			return false
	return true


func hero_power_target_options(p_idx: int) -> Array:
	var hp: Dictionary = hero_power(p_idx)
	if str(hp.get("target", "none")) != "friendly_minion":
		return []
	var out: Array = []
	for i in players[p_idx]["board"].size():
		out.append({"kind": "minion", "player": p_idx, "board_idx": i})
	return out


func use_hero_power(p_idx: int, target: Dictionary = {}) -> bool:
	if not can_use_hero_power(p_idx, target):
		return false
	var p: Dictionary = players[p_idx]
	var hp: Dictionary = hero_power(p_idx)
	var mana_before: int = p["mana"]
	var max_mana_before: int = p["max_mana"]
	p["mana"] -= HERO_POWER_COST
	p["hero_power_used"] = true
	_lethal_deferred += 1
	var use_target: Dictionary = target
	if str(hp["target"]) == "enemy_hero":
		use_target = {"kind": "hero", "player": 1 - p_idx, "board_idx": -1}
	var token: Dictionary = {}
	if str(hp["effect"]) == "summon_token":
		token = CardDB.deckhand_token()
	_emit("signature_move", {"player": p_idx, "class": str(p["class"])})
	# Signature moves resolve with source = the hero (uid -1, no card).
	var prev_uid3: int = _src_uid
	var prev_card3: String = _src_card
	_src_uid = -1
	_src_card = ""
	_resolve_effect(p_idx, str(hp["effect"]), int(hp["value"]), use_target, -1, token)
	_src_uid = prev_uid3
	_src_card = prev_card3
	log.append("Signature Move: %s!" % str(hp["name"]))
	_settle()
	_lethal_deferred -= 1
	if p["mana"] != mana_before or p["max_mana"] != max_mana_before:
		_emit("mana_changed", {"player": p_idx, "mana": p["mana"], "max_mana": p["max_mana"]})
	_check_lethal()
	return true


# --- Effects ---
# hand_before: hand size BEFORE the played card was removed (-1 = use
# current hand size). Battlecry damage_per_hand_card counts the played
# card (still in hand at resolution); Deathrattle does not (source gone).
# token: the token dict for summon_token (parsed from the source card's
# text, or the Deckhand for Barnacle's hero power).

func _resolve_effect(p_idx: int, effect: String, value: int, target: Dictionary, hand_before: int = -1, token: Dictionary = {}) -> void:
	match effect:
		"damage":
			_deal_damage_to_target(p_idx, target, value)
		"gain_mana":
			# The Coin: +1 mana this turn only, capped at 10.
			players[p_idx]["mana"] = min(MAX_MANA, players[p_idx]["mana"] + value)
		"heal_hero":
			_heal_hero(p_idx, value)
		"heal_draw":
			_heal_hero(p_idx, value)
			draw_cards(p_idx, 1)
		"draw":
			draw_cards(p_idx, value)
		"draw_self_damage":
			draw_cards(p_idx, 1)
			players[p_idx]["hp"] -= value
			_emit("damage", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": value, "source_uid": _src_uid, "source_card_id": _src_card})
		"summon_token":
			if token.is_empty():
				token = CardDB.TOKEN_SQUIRELING
			_summon(p_idx, token, true)
		"damage_all_enemy_minions":
			var enemy: Dictionary = players[1 - p_idx]
			var src_m: Dictionary = _source_minion()
			for m in enemy["board"].duplicate():
				_hit_minion(1 - p_idx, m, value, _src_uid, _src_card, src_m)
		"damage_all_minions":
			# Snapshot both boards: apply to every minion, then clean up.
			# ALL damage events fire before ANY minion_died (deaths are
			# processed by the caller, after this effect resolves).
			var src_m2: Dictionary = _source_minion()
			for pl_i in players.size():
				for m in players[pl_i]["board"].duplicate():
					_hit_minion(pl_i, m, value, _src_uid, _src_card, src_m2)
		"destroy":
			_destroy_target(target)
		"destroy_damaged":
			var foe: Dictionary = players[1 - p_idx]
			for m in foe["board"]:
				if m["health"] < m["max_health"] and m["health"] > 0:
					_emit("minion_destroyed", {"player": 1 - p_idx, "uid": uid_for(m)})
					m["health"] = 0
		"random_minion_damage":
			_random_minion_damage(p_idx)
			_queue_triggers(p_idx, "random_fired")
		"random_enemy_damage":
			_random_enemy_damage(p_idx, value)
			_queue_triggers(p_idx, "random_fired")
		"steal_weak":
			_steal_weak(p_idx, value)
		"swap_hands":
			var a: Array = players[0]["hand"]
			var b: Array = players[1]["hand"]
			players[0]["hand"] = b
			players[1]["hand"] = a
			_emit("hands_swapped", {})
			log.append("Hands swapped!")
		"coin_flip":
			_queue_triggers(p_idx, "random_fired")
			var heads: bool = rng.randf() < 0.5
			_emit("coin_flip", {"player": p_idx, "heads": heads})
			if heads:
				log.append("Coin Flip: heads! Draw 2 cards.")
				draw_cards(p_idx, 2)
			else:
				log.append("Coin Flip: tails! Draw a card and take 2 damage.")
				draw_cards(p_idx, 1)
				players[p_idx]["hp"] -= 2
				_emit("damage", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": 2, "source_uid": _src_uid, "source_card_id": _src_card})
		"buff_friendly":
			_buff_target(p_idx, target, value)
		"buff_all_friendly":
			for m in players[p_idx]["board"]:
				_apply_buff(p_idx, m, value)
		"damage_per_card_played":
			# Reads the counter BEFORE the played card increments it
			# ("other cards"). Engine doubles: 2N per other card.
			var n: int = players[p_idx]["cards_played_this_turn"]
			if payoff_cap >= 0:
				n = mini(n, payoff_cap)
			var payoff_dmg: int = value * 2 * n
			if payoff_dmg > 0:
				_hit_hero(1 - p_idx, payoff_dmg, _src_uid, _src_card, _source_minion())
		"damage_per_hand_card":
			var count: int = hand_before if hand_before >= 0 else players[p_idx]["hand"].size()
			var hand_dmg: int = value * count
			if hand_dmg > 0:
				_hit_hero(1 - p_idx, hand_dmg, _src_uid, _src_card, _source_minion())
		"damage_split":
			# N 1-damage packets, each to a random enemy character.
			# No mid-split cleanup — a minion at 0 HP can absorb packets.
			for _i in value:
				var t: Dictionary = _random_enemy_character(p_idx)
				if t.is_empty():
					break
				_deal_damage_to_target(p_idx, t, 1)
			_queue_triggers(p_idx, "random_fired")
		"recruit":
			_recruit(p_idx, value)
		"swap_stats":
			_swap_stats(p_idx)
		# --- Mechanics pass, wave 1 ---
		"buff_attack":
			var mt: Dictionary = _target_minion(target)
			if not mt.is_empty():
				mt["attack"] = int(mt["attack"]) + value
				_emit("buff", {"player": int(target["player"]), "uid": uid_for(mt), "attack_delta": value, "health_delta": 0, "source_uid": _src_uid, "source_card_id": _src_card})
				_queue_triggers(int(target["player"]), "friendly_buffed", uid_for(mt))
		"buff_health":
			var mh: Dictionary = _target_minion(target)
			if not mh.is_empty():
				mh["max_health"] = int(mh["max_health"]) + value
				mh["health"] = int(mh["health"]) + value
				_emit("buff", {"player": int(target["player"]), "uid": uid_for(mh), "attack_delta": 0, "health_delta": value, "source_uid": _src_uid, "source_card_id": _src_card})
				_queue_triggers(int(target["player"]), "friendly_buffed", uid_for(mh))
		"freeze":
			# Stage Fright: the target misses its next attack.
			var mf: Dictionary = _target_minion(target)
			if not mf.is_empty():
				var owner_f: int = int(target["player"])
				mf["frozen"] = 2 if owner_f == active else 1
				_emit("frozen", {"player": owner_f, "uid": uid_for(mf), "source_uid": _src_uid, "source_card_id": _src_card})
		"silence":
			# Heckle: strip the target's text and buffs.
			var ms: Dictionary = _target_minion(target)
			if not ms.is_empty():
				_silence(int(target["player"]), ms)
		"summon_tokens":
			for _k in maxi(1, value):
				_summon(p_idx, token if not token.is_empty() else CardDB.TOKEN_SQUIRELING, true)


func _apply_buff(p_idx: int, m: Dictionary, n: int) -> void:
	# Permanent: current AND max Health +N, damage taken stays.
	m["attack"] += n
	m["max_health"] += n
	m["health"] += n
	_emit("buff", {"player": p_idx, "uid": uid_for(m), "attack_delta": n, "health_delta": n, "source_uid": _src_uid, "source_card_id": _src_card})
	_queue_triggers(p_idx, "friendly_buffed", uid_for(m))


func _buff_target(p_idx: int, target: Dictionary, value: int) -> void:
	if target.is_empty() or target.get("kind", "") != "minion":
		return
	var board: Array = players[target["player"]]["board"]
	if target["board_idx"] < board.size():
		_apply_buff(int(target["player"]), board[target["board_idx"]], value)


func _deal_damage_to_target(p_idx: int, target: Dictionary, amount: int) -> void:
	if target.is_empty():
		return
	if target["kind"] == "hero":
		_hit_hero(int(target["player"]), amount, _src_uid, _src_card, _source_minion())
	else:
		var board: Array = players[target["player"]]["board"]
		if target["board_idx"] < board.size():
			_hit_minion(int(target["player"]), board[target["board_idx"]], amount, _src_uid, _src_card, _source_minion())


func _destroy_target(target: Dictionary) -> void:
	# Destroy = death: mark at 0 HP so the Deathrattle pipeline picks it
	# up (Deathrattle fires). Do NOT remove immediately.
	# Sprint 1b: minion_destroyed fires here, BEFORE the minion_died
	# the Deathrattle pipeline emits later. Only when the destroy
	# actually kills a live minion (health > 0) — a minion already at 0
	# is dead already and must not get a second destroyed event.
	if target.is_empty() or target["kind"] != "minion":
		return
	var board: Array = players[target["player"]]["board"]
	if target["board_idx"] < board.size():
		var m: Dictionary = board[target["board_idx"]]
		if m["health"] > 0:
			_emit("minion_destroyed", {"player": int(target["player"]), "uid": uid_for(m)})
		m["health"] = 0


func _random_enemy_character(p_idx: int) -> Dictionary:
	# Uniform choice over all enemy characters (minions + hero).
	var enemy_idx: int = 1 - p_idx
	var enemy: Dictionary = players[enemy_idx]
	var n: int = enemy["board"].size() + 1
	var pick: int = rng.randi_range(0, n - 1)
	if pick < enemy["board"].size():
		return {"kind": "minion", "player": enemy_idx, "board_idx": pick}
	return {"kind": "hero", "player": enemy_idx, "board_idx": -1}


func _random_enemy_damage(p_idx: int, value: int) -> void:
	var t: Dictionary = _random_enemy_character(p_idx)
	if not t.is_empty():
		_deal_damage_to_target(p_idx, t, value)


func _random_minion_damage(p_idx: int) -> void:
	# Balance Patch v1: 2-5 damage to a random enemy MINION; the enemy
	# hero only takes the hit if they have no minions.
	var enemy_idx: int = 1 - p_idx
	var enemy: Dictionary = players[enemy_idx]
	var dmg: int = rng.randi_range(2, 5)
	if enemy["board"].is_empty():
		_hit_hero(enemy_idx, dmg, _src_uid, _src_card, _source_minion())
		log.append("Roulette: %d damage to the enemy Boss!" % dmg)
	else:
		var idx: int = rng.randi_range(0, enemy["board"].size() - 1)
		_hit_minion(enemy_idx, enemy["board"][idx], dmg, _src_uid, _src_card, _source_minion())
		log.append("Roulette: %d damage to a random enemy Crew member!" % dmg)


func _steal_weak(p_idx: int, max_attack: int) -> void:
	var enemy: Dictionary = players[1 - p_idx]
	var mine: Dictionary = players[p_idx]
	var candidates: Array = []
	for i in enemy["board"].size():
		if enemy["board"][i]["attack"] <= max_attack:
			candidates.append(i)
	if candidates.is_empty():
		log.append("Paid Off fizzled — no weak enemy Crew member.")
		return
	if mine["board"].size() >= MAX_BOARD:
		log.append("Paid Off fizzled — your board is full.")
		return
	var idx: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var m: Dictionary = enemy["board"][idx]
	enemy["board"].remove_at(idx)
	m["can_attack"] = false
	m["sick"] = true
	m["attacks_left"] = 0
	mine["board"].append(m)
	_emit("minion_stolen", {"from_player": 1 - p_idx, "to_player": p_idx, "uid": uid_for(m)})
	_refresh_vibes()
	log.append("Paid Off stole %s!" % m["name"])


func _recruit(p_idx: int, max_cost: int) -> void:
	var p: Dictionary = players[p_idx]
	if p["board"].size() >= MAX_BOARD:
		log.append("Recruit fizzled — your board is full.")
		return
	var candidates: Array = []
	for i in p["deck"].size():
		var c: Dictionary = CardDB.get_card(p["deck"][i])
		if not c.is_empty() and c["type"] == "minion" and c["cost"] <= max_cost:
			candidates.append(i)
	if candidates.is_empty():
		log.append("Recruit fizzled — no Crew member costing %d or less in your deck." % max_cost)
		return
	var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var card_id: String = p["deck"][pick]
	p["deck"].remove_at(pick)
	# No Battlecry on summon (it wasn't played from hand).
	_summon(p_idx, CardDB.get_card(card_id), true)
	log.append("Recruited %s!" % CardDB.get_card(card_id)["name"])


func _swap_stats(p_idx: int) -> void:
	# Random enemy minion; fizzle if none. Swap Attack and (current)
	# Health; max Health follows the new Health.
	var enemy: Dictionary = players[1 - p_idx]
	if enemy["board"].is_empty():
		log.append("Swap Stats fizzled — no enemy Crew member.")
		return
	var idx: int = rng.randi_range(0, enemy["board"].size() - 1)
	var m: Dictionary = enemy["board"][idx]
	# Take Vibe bonuses off first, so the swap is of its own stats.
	_set_vibe(m, 0, 0)
	var old_atk: int = m["attack"]
	m["attack"] = m["health"]
	m["health"] = old_atk
	m["max_health"] = old_atk
	_refresh_vibes()
	_emit("stats_swapped", {"player": 1 - p_idx, "uid": uid_for(m), "attack": m["attack"], "health": m["health"]})
	log.append("Swapped %s to %d/%d!" % [m["name"], m["attack"], m["health"]])


# --- Deathrattle ---

# Collect + remove all dead minions (health <= 0), in Deathrattle order:
# active player's board left-to-right, then the other player's.
func _collect_dead() -> Array:
	var out: Array = []
	var order: Array = [active, 1 - active]
	for p_idx in order:
		var board: Array = players[p_idx]["board"]
		var dead_idx: Array = []
		for i in board.size():
			if board[i]["health"] <= 0:
				dead_idx.append(i)
		for i in dead_idx:
			out.append({"owner": p_idx, "uid": uid_for(board[i]), "card_id": board[i]["card_id"], "name": board[i]["name"], "silenced": bool(board[i].get("silenced", false))})
		for i in range(dead_idx.size() - 1, -1, -1):
			board.remove_at(dead_idx[i])
	if not out.is_empty():
		_refresh_vibes()
	return out


# Deathrattle pipeline: resolve the current batch of dead minions'
# Deathrattles (in order), then collect any new deaths they caused
# (chains) and repeat until no new deaths. Each minion fires at most
# once (it is gone from the board after firing).
func _process_deaths() -> void:
	var pending: Array = _collect_dead()
	while not pending.is_empty():
		var batch: Array = pending
		pending = []
		for dead in batch:
			_emit("minion_died", {"player": int(dead["owner"]), "uid": int(dead.get("uid", -1)), "card_id": str(dead["card_id"])})
			_queue_triggers(int(dead["owner"]), "friendly_crew_died")
			_resolve_deathrattle(int(dead["owner"]), dead)
		pending.append_array(_collect_dead())


# Kept for callers that used the old name.
func _cleanup_deaths() -> void:
	_process_deaths()


func _resolve_deathrattle(owner_idx: int, dead: Dictionary) -> void:
	var card: Dictionary = CardDB.get_card(str(dead["card_id"]))
	if card.is_empty() or bool(dead.get("silenced", false)):
		return
	var eff: String = str(card.get("deathrattle", ""))
	if eff == "":
		return
	var val: int = int(card.get("deathrattle_value", 0))
	var tgt_type: String = str(card.get("deathrattle_target", "none"))
	var target: Variant = _deathrattle_target(owner_idx, eff, tgt_type)
	if target == null:
		log.append("Final Bow fizzled — no valid target.")
		return
	log.append("Final Bow: %s!" % str(dead["name"]))
	_emit("final_bow", {"player": owner_idx, "uid": int(dead.get("uid", -1)), "card_id": str(dead["card_id"])})
	# The Final Bow resolves with source = the dead minion (its uid and
	# card), so its damage / heal / buff events carry the right origin.
	var prev_uid4: int = _src_uid
	var prev_card4: String = _src_card
	_src_uid = int(dead.get("uid", -1))
	_src_card = str(dead["card_id"])
	_resolve_effect(owner_idx, eff, val, target, -1, CardDB.token_for(card))
	_src_uid = prev_uid4
	_src_card = prev_card4


# Deathrattle targeting — ALL random, NO player choice. Returns a target
# dict, {} for untargeted effects, or null = fizzle (no valid target).
func _deathrattle_target(owner_idx: int, eff: String, tgt_type: String) -> Variant:
	match eff:
		"destroy":
			# Random valid target; fizzle with none.
			var foe: Dictionary = players[1 - owner_idx]
			if foe["board"].is_empty():
				return null
			var idx: int = rng.randi_range(0, foe["board"].size() - 1)
			return {"kind": "minion", "player": 1 - owner_idx, "board_idx": idx}
		"swap_stats":
			var foe2: Dictionary = players[1 - owner_idx]
			if foe2["board"].is_empty():
				return null
			return {}
		_:
			pass
	match tgt_type:
		"any_enemy":
			return _random_enemy_character(owner_idx)
		"enemy_minion":
			var foe3: Dictionary = players[1 - owner_idx]
			if foe3["board"].is_empty():
				return null
			var idx3: int = rng.randi_range(0, foe3["board"].size() - 1)
			return {"kind": "minion", "player": 1 - owner_idx, "board_idx": idx3}
		"friendly_minion":
			var mine: Dictionary = players[owner_idx]
			if mine["board"].is_empty():
				return null
			var idx4: int = rng.randi_range(0, mine["board"].size() - 1)
			return {"kind": "minion", "player": owner_idx, "board_idx": idx4}
		"enemy_hero":
			return {"kind": "hero", "player": 1 - owner_idx, "board_idx": -1}
		_:
			return {}


# --- Combat ---

func valid_attack_targets(p_idx: int) -> Array:
	# Returns target dicts the active player may attack.
	var enemy_idx: int = 1 - p_idx
	var enemy: Dictionary = players[enemy_idx]
	# Backstage Crew can't be attacked, and a hidden Bouncer guards nothing.
	var taunts: Array = []
	for i in enemy["board"].size():
		if enemy["board"][i]["taunt"] and not enemy["board"][i].get("stealth", false):
			taunts.append({"kind": "minion", "player": enemy_idx, "board_idx": i})
	if not taunts.is_empty():
		return taunts
	var out: Array = []
	for i in enemy["board"].size():
		if enemy["board"][i].get("stealth", false):
			continue
		out.append({"kind": "minion", "player": enemy_idx, "board_idx": i})
	out.append({"kind": "hero", "player": enemy_idx, "board_idx": -1})
	return out


func can_attack(p_idx: int, board_idx: int) -> bool:
	if p_idx != active or winner != -1:
		return false
	var board: Array = players[p_idx]["board"]
	if board_idx < 0 or board_idx >= board.size():
		return false
	var m: Dictionary = board[board_idx]
	return m["can_attack"] and m["attack"] > 0 and int(m.get("frozen", 0)) == 0


func attack(p_idx: int, board_idx: int, target: Dictionary) -> bool:
	if not can_attack(p_idx, board_idx):
		return false
	var valid: Array = valid_attack_targets(p_idx)
	var legal: bool = false
	for v in valid:
		if v["kind"] == target["kind"] and v["player"] == target["player"] and v["board_idx"] == target["board_idx"]:
			legal = true
			break
	if not legal:
		return false
	var attacker: Dictionary = players[p_idx]["board"][board_idx]
	# Encore attacks twice a turn; everyone else once.
	attacker["attacks_left"] = int(attacker.get("attacks_left", 1)) - 1
	attacker["can_attack"] = int(attacker["attacks_left"]) > 0
	_lethal_deferred += 1
	# Defensive bounds check first (unreachable via valid targets): a
	# failed attack emits nothing.
	if target["kind"] == "minion" and int(target["board_idx"]) >= players[target["player"]]["board"].size():
		_lethal_deferred -= 1
		return false
	var attacker_uid: int = uid_for(attacker)
	var target_uid: int = -1
	if target["kind"] == "minion":
		target_uid = uid_for(players[target["player"]]["board"][int(target["board_idx"])])
	_emit("attack", {"player": p_idx, "attacker_uid": attacker_uid, "target_kind": str(target["kind"]), "target_player": int(target["player"]), "target_uid": target_uid})
	# Backstage ends when it attacks.
	if attacker.get("stealth", false):
		attacker["stealth"] = false
		_emit("stealth_lost", {"player": p_idx, "uid": attacker_uid})
	_queue_self(p_idx, attacker, "attacks")
	if target["kind"] == "hero":
		_hit_hero(int(target["player"]), int(attacker["attack"]), attacker_uid, "", attacker)
	else:
		var enemy_board: Array = players[target["player"]]["board"]
		var defender: Dictionary = enemy_board[target["board_idx"]]
		var defender_uid: int = uid_for(defender)
		# Simultaneous trade: BOTH damage events fire before ANY
		# minion_died (deaths are processed below, after this block).
		var atk_a: int = int(attacker["attack"])
		var atk_d: int = int(defender["attack"])
		_hit_minion(int(target["player"]), defender, atk_a, attacker_uid, "", attacker)
		_hit_minion(p_idx, attacker, atk_d, defender_uid, "", defender)
	_settle()
	_lethal_deferred -= 1
	_check_lethal()
	return true


# --- Target validation for cards ---

# Does this card's effect need a player-chosen target?
# swap_stats is random (no player choice) despite its enemy_minion field.
func _requires_player_target(card: Dictionary, is_battlecry: bool, for_effect2: bool = false) -> bool:
	if for_effect2:
		return str(card.get("effect2_target", "none")) != "none"
	if str(card.get("effect", "")) == "swap_stats":
		return false
	return str(card.get("target", "none")) != "none"


# Validate `target` against a target type. For Battlecry buff_friendly,
# the source minion (just summoned at src_idx) cannot target itself.
func _is_valid_target(p_idx: int, target_type: String, target: Dictionary, is_battlecry: bool, src_idx: int = -1) -> bool:
	if target.is_empty():
		return false
	match target_type:
		"any_enemy":
			if target["kind"] == "hero":
				return target["player"] == 1 - p_idx
			if target["kind"] == "minion":
				return target["player"] == 1 - p_idx and target["board_idx"] < players[target["player"]]["board"].size() and not _hidden(target)
			return false
		"enemy_minion":
			return target["kind"] == "minion" and target["player"] == 1 - p_idx and target["board_idx"] < players[target["player"]]["board"].size() and not _hidden(target)
		"enemy_hero":
			return target["kind"] == "hero" and target["player"] == 1 - p_idx
		"friendly_minion":
			if target["kind"] != "minion" or target["player"] != p_idx:
				return false
			if target["board_idx"] >= players[p_idx]["board"].size():
				return false
			if is_battlecry and src_idx >= 0 and target["board_idx"] == src_idx:
				return false  # Battlecry buff cannot target itself.
			return true
		_:
			return false


func _is_valid_card_target(p_idx: int, card: Dictionary, target: Dictionary) -> bool:
	return _is_valid_target(p_idx, str(card.get("target", "none")), target, card["type"] == "minion")


# Valid player-chosen targets for a card (for UI highlighting).
# For spells whose primary effect is untargeted but effect2 is targeted
# (Wisdom, Cantrip), the player chooses the effect2 target.
func card_target_options(p_idx: int, card: Dictionary) -> Array:
	var out: Array = []
	# swap_stats is random (no player choice) despite its target field.
	if str(card.get("effect", "")) == "swap_stats":
		return out
	var ttype: String = str(card.get("target", "none"))
	if ttype == "none" and card["type"] == "spell":
		ttype = str(card.get("effect2_target", "none"))
	if ttype == "none":
		return out
	match ttype:
		"any_enemy":
			var enemy_idx: int = 1 - p_idx
			for i in players[enemy_idx]["board"].size():
				if not players[enemy_idx]["board"][i].get("stealth", false):
					out.append({"kind": "minion", "player": enemy_idx, "board_idx": i})
			out.append({"kind": "hero", "player": enemy_idx, "board_idx": -1})
		"enemy_minion":
			var e_idx: int = 1 - p_idx
			for i in players[e_idx]["board"].size():
				if not players[e_idx]["board"][i].get("stealth", false):
					out.append({"kind": "minion", "player": e_idx, "board_idx": i})
		"friendly_minion":
			for i in players[p_idx]["board"].size():
				out.append({"kind": "minion", "player": p_idx, "board_idx": i})
	return out


# --- Mechanics pass, wave 1: shared helpers ---

# A Backstage (stealthed) enemy Crew member can't be chosen.
func _hidden(target: Dictionary) -> bool:
	if str(target.get("kind", "")) != "minion":
		return false
	var b: Array = players[int(target["player"])]["board"]
	var i: int = int(target["board_idx"])
	return i >= 0 and i < b.size() and bool(b[i].get("stealth", false))


func _target_minion(target: Dictionary) -> Dictionary:
	if target.is_empty() or str(target.get("kind", "")) != "minion":
		return {}
	var b: Array = players[int(target["player"])]["board"]
	var i: int = int(target["board_idx"])
	if i < 0 or i >= b.size():
		return {}
	return b[i]


# The Crew member whose effect is resolving now ({} for Tricks and
# Signature Moves). Showstopper and Tip Jar follow its damage.
func _source_minion() -> Dictionary:
	if _src_uid < 0:
		return {}
	for pl in players.size():
		var m: Dictionary = minion_by_uid(pl, _src_uid)
		if not m.is_empty():
			return m
	return {}


func _owner_of(m: Dictionary) -> int:
	if m.is_empty():
		return -1
	for pl in players.size():
		if players[pl]["board"].has(m):
			return pl
	return -1


# All damage to a Crew member goes through here. Returns damage dealt.
# Stunt Double takes the first hit for free; Showstopper destroys what it
# damages; Tip Jar heals its owner by what it deals.
func _hit_minion(owner: int, m: Dictionary, amount: int, src_uid: int, src_card: String, src_m: Dictionary = {}) -> int:
	if amount <= 0:
		return 0
	if m.get("shield", false):
		m["shield"] = false
		_emit("shield_popped", {"player": owner, "uid": uid_for(m), "source_uid": src_uid, "source_card_id": src_card})
		return 0
	m["health"] = int(m["health"]) - amount
	_emit("damage", {"target_kind": "minion", "player": owner, "uid": uid_for(m), "amount": amount, "source_uid": src_uid, "source_card_id": src_card})
	if int(m["health"]) > 0:
		_queue_self(owner, m, "damaged")
	if not src_m.is_empty():
		if src_m.get("poison", false) and int(m["health"]) > 0:
			_emit("minion_destroyed", {"player": owner, "uid": uid_for(m)})
			m["health"] = 0
		if src_m.get("lifesteal", false):
			_lifesteal(src_m, amount)
	return amount


func _hit_hero(p_idx: int, amount: int, src_uid: int, src_card: String, src_m: Dictionary = {}) -> void:
	if amount <= 0:
		return
	players[p_idx]["hp"] = int(players[p_idx]["hp"]) - amount
	_emit("damage", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": amount, "source_uid": src_uid, "source_card_id": src_card})
	if not src_m.is_empty() and src_m.get("lifesteal", false):
		_lifesteal(src_m, amount)


func _lifesteal(src_m: Dictionary, amount: int) -> void:
	var owner: int = _owner_of(src_m)
	if owner < 0:
		return
	var prev_uid: int = _src_uid
	var prev_card: String = _src_card
	_src_uid = uid_for(src_m)
	_src_card = str(src_m.get("card_id", ""))
	_heal_hero(owner, amount)
	_src_uid = prev_uid
	_src_card = prev_card


func _heal_hero(p_idx: int, amount: int) -> void:
	var p: Dictionary = players[p_idx]
	var before: int = int(p["hp"])
	p["hp"] = mini(STARTING_HP, before + amount)
	if int(p["hp"]) > before:
		_emit("heal", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": int(p["hp"]) - before, "source_uid": _src_uid, "source_card_id": _src_card})
		_queue_triggers(p_idx, "boss_healed")


# Queue every "whenever" on p_idx's board that listens for `when`.
# exclude_uid: the Crew member that caused it (a Crew member doesn't
# trigger off its own summon or play).
func _queue_triggers(p_idx: int, when: String, exclude_uid: int = -1) -> void:
	if _in_trigger or p_idx < 0 or p_idx >= players.size():
		return
	for m in players[p_idx]["board"]:
		if int(m.get("uid", -2)) == exclude_uid:
			continue
		_queue_self(p_idx, m, when)


# Queue this one Crew member's triggers for `when`.
func _queue_self(p_idx: int, m: Dictionary, when: String) -> void:
	if _in_trigger or int(m.get("health", 0)) <= 0 or m.get("silenced", false):
		return
	var card: Dictionary = CardDB.get_card(str(m.get("card_id", "")))
	for t in card.get("triggers", []):
		if str(t.get("when", "")) == when:
			_trigger_queue.append({"owner": p_idx, "uid": uid_for(m), "card_id": str(m["card_id"]), "trig": t})


# Fire queued triggers in order. A holder that died or was Heckled in the
# meantime doesn't fire. Capped so a bad card can't loop forever.
func _flush_triggers() -> void:
	var fired: int = 0
	while not _trigger_queue.is_empty() and fired < 60 and winner == -1:
		var q: Dictionary = _trigger_queue.pop_front()
		var owner: int = int(q["owner"])
		var holder: Dictionary = minion_by_uid(owner, int(q["uid"]))
		if holder.is_empty() or int(holder["health"]) <= 0 or holder.get("silenced", false):
			continue
		fired += 1
		var t: Dictionary = q["trig"]
		var eff: String = str(t.get("effect", ""))
		var tgt_type: String = str(t.get("target", "none"))
		var target: Variant
		if tgt_type == "self":
			target = {"kind": "minion", "player": owner, "board_idx": minion_index_by_uid(owner, int(q["uid"]))}
		elif tgt_type == "friendly_hero":
			target = {"kind": "hero", "player": owner, "board_idx": -1}
		else:
			target = _deathrattle_target(owner, eff, tgt_type)
		if target == null:
			continue
		_emit("trigger", {"player": owner, "uid": int(q["uid"]), "card_id": str(q["card_id"]), "when": str(t.get("when", ""))})
		var prev_uid: int = _src_uid
		var prev_card: String = _src_card
		_src_uid = int(q["uid"])
		_src_card = str(q["card_id"])
		_in_trigger = true
		var tok: Dictionary = CardDB.token_for(CardDB.get_card(str(q["card_id"])))
		_resolve_effect(owner, eff, int(t.get("value", 0)), target, -1, tok)
		_in_trigger = false
		_src_uid = prev_uid
		_src_card = prev_card
	_trigger_queue.clear()


# Run everything an action set off until the board is still: Vibes,
# then triggers, then deaths (whose Final Bows and "whenever a friendly
# Crew dies" can set off more), until nothing is left.
func _settle() -> void:
	for _i in 40:
		_refresh_vibes()
		_flush_triggers()
		var any_dead: bool = false
		for pl in players:
			for m in pl["board"]:
				if int(m["health"]) <= 0:
					any_dead = true
		if not any_dead and _trigger_queue.is_empty():
			break
		if any_dead:
			_process_deaths()
	_refresh_vibes()


# --- Vibes (auras) ---
# A card's "vibe": {"attack": a, "health": h, "who": "other_friendly" |
# "all_friendly" | "friendly_deckhands" | "friendly_tokens" | "enemy"}. Bonuses are recomputed
# from scratch and applied as differences, so damage taken stays taken
# and losing a Vibe never kills.

func _vibe_applies(src: Dictionary, src_owner: int, m: Dictionary, m_owner: int, who: String) -> bool:
	match who:
		"other_friendly":
			return m_owner == src_owner and m != src
		"all_friendly":
			return m_owner == src_owner
		"friendly_deckhands":
			return m_owner == src_owner and m != src and str(m.get("card_id", "")) == "deckhand"
		"friendly_tokens":
			return m_owner == src_owner and m != src and CardDB.is_token_id(str(m.get("card_id", "")))
		"enemy":
			return m_owner != src_owner
	return false


func _refresh_vibes() -> void:
	var want: Dictionary = {}  # uid -> [atk, hp]
	var sources: Array = []
	var any_bonus: bool = false
	for pl in players.size():
		for m in players[pl]["board"]:
			if int(m.get("vibe_atk", 0)) != 0 or int(m.get("vibe_hp", 0)) != 0:
				any_bonus = true
			if int(m["health"]) <= 0 or m.get("silenced", false):
				continue
			var vibe: Dictionary = CardDB.get_card(str(m.get("card_id", ""))).get("vibe", {})
			if not vibe.is_empty():
				sources.append([pl, m, vibe])
	# The common case: no Vibes anywhere and none to take off.
	if sources.is_empty() and not any_bonus:
		return
	for pl in players.size():
		for m in players[pl]["board"]:
			var a: int = 0
			var h: int = 0
			for srcv in sources:
				if _vibe_applies(srcv[1], int(srcv[0]), m, pl, str(srcv[2].get("who", "other_friendly"))):
					a += int(srcv[2].get("attack", 0))
					h += int(srcv[2].get("health", 0))
			want[uid_for(m)] = [a, h]
	for pl in players.size():
		for m in players[pl]["board"]:
			var w: Array = want.get(uid_for(m), [0, 0])
			_set_vibe(m, int(w[0]), int(w[1]))


func _set_vibe(m: Dictionary, a: int, h: int) -> void:
	var da: int = a - int(m.get("vibe_atk", 0))
	var dh: int = h - int(m.get("vibe_hp", 0))
	if da == 0 and dh == 0:
		return
	if int(m["health"]) <= 0 and dh > 0:
		return  # already dead: a new Vibe doesn't bring it back
	m["attack"] = maxi(0, int(m["attack"]) + da)
	m["max_health"] = int(m["max_health"]) + dh
	if dh > 0:
		m["health"] = int(m["health"]) + dh
	else:
		m["health"] = mini(int(m["health"]), int(m["max_health"]))
	if a == 0 and h == 0:
		m.erase("vibe_atk")
		m.erase("vibe_hp")
	else:
		m["vibe_atk"] = a
		m["vibe_hp"] = h


# --- Heckle (silence) ---
func _silence(owner: int, m: Dictionary) -> void:
	_set_vibe(m, 0, 0)
	m["silenced"] = true
	m["taunt"] = false
	for k in STATE_KEYWORDS:
		m.erase(k)
	m.erase("frozen")
	if int(m.get("attacks_left", 0)) > 1:
		m["attacks_left"] = 1
	var card: Dictionary = CardDB.get_card(str(m.get("card_id", "")))
	var base_a: int = int(card.get("attack", m["attack"]))
	var base_h: int = int(card.get("health", m["max_health"]))
	m["attack"] = base_a
	var damage_taken: int = int(m["max_health"]) - int(m["health"])
	m["max_health"] = base_h
	m["health"] = mini(int(m["health"]), base_h) if damage_taken >= 0 else base_h
	_emit("silenced", {"player": owner, "uid": uid_for(m), "source_uid": _src_uid, "source_card_id": _src_card})
	_refresh_vibes()


# --- Cleanup / lethal ---

func _check_lethal() -> void:
	# Deferred: a Deathrattle heal can save a hero at 0 — lethal is only
	# checked after the whole action (incl. Deathrattles) resolves.
	if _lethal_deferred > 0:
		return
	var hp0: int = players[0]["hp"]
	var hp1: int = players[1]["hp"]
	var new_winner: int = winner
	if hp0 <= 0 and hp1 <= 0:
		new_winner = 1 - active
	elif hp0 <= 0:
		new_winner = 1
	elif hp1 <= 0:
		new_winner = 0
	if new_winner != -1 and winner == -1:
		winner = new_winner
		_emit("game_over", {"winner": winner})


# --- Deck validation (deckbuilding) ---

static func validate_deck(deck: Array, p_class: String = "") -> bool:
	if deck.size() != DECK_SIZE:
		return false
	var counts: Dictionary = {}
	for card_id in deck:
		if card_id == "coin":
			return false
		var card: Dictionary = CardDB.get_card(card_id)
		if card.is_empty():
			return false
		if p_class != "" and card["class"] != "neutral" and card["class"] != p_class:
			return false
		counts[card_id] = counts.get(card_id, 0) + 1
		if counts[card_id] > CardDB.max_copies(card):
			return false
	return true
