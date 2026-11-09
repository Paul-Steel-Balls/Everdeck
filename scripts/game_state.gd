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
	if p["mana"] != mana_before or p["max_mana"] != max_before:
		_emit("mana_changed", {"player": active, "mana": p["mana"], "max_mana": p["max_mana"]})
	p["hero_power_used"] = false
	p["cards_played_this_turn"] = 0
	for m in p["board"]:
		m["sick"] = false
		m["can_attack"] = true
	_draw(active, false)


func end_turn() -> void:
	if winner != -1:
		return
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
	_process_deaths()
	_lethal_deferred -= 1
	if p["mana"] != mana_before or p["max_mana"] != max_mana_before:
		_emit("mana_changed", {"player": p_idx, "mana": p["mana"], "max_mana": p["max_mana"]})
	_check_lethal()
	return true


func _summon(p_idx: int, card: Dictionary, sick: bool) -> void:
	var p: Dictionary = players[p_idx]
	if p["board"].size() >= MAX_BOARD:
		return
	var m: Dictionary = {
		"card_id": card["id"],
		"name": card["name"],
		"attack": card["attack"],
		"health": card["health"],
		"max_health": card["health"],
		"taunt": card["keywords"].has("taunt"),
		"can_attack": card["keywords"].has("charge"),
		"sick": sick and not card["keywords"].has("charge"),
		# Presentation: the art this minion shows. Tokens carry their own
		# token art (from the card's "token" field); regular minions carry
		# their card art. The view prefers this over the card lookup.
		"art": card.get("art", ""),
	}
	m["uid"] = _next_uid
	_next_uid += 1
	p["board"].append(m)
	_emit("minion_summoned", {"player": p_idx, "uid": m["uid"], "card_id": card["id"], "board_idx": p["board"].size() - 1})


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
		token = CardDB.TOKEN_DECKHAND
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
	_process_deaths()
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
			var p: Dictionary = players[p_idx]
			var heal_before: int = p["hp"]
			p["hp"] = min(STARTING_HP, p["hp"] + value)
			if p["hp"] > heal_before:
				_emit("heal", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": p["hp"] - heal_before, "source_uid": _src_uid, "source_card_id": _src_card})
		"heal_draw":
			var p2: Dictionary = players[p_idx]
			var heal_before2: int = p2["hp"]
			p2["hp"] = min(STARTING_HP, p2["hp"] + value)
			if p2["hp"] > heal_before2:
				_emit("heal", {"target_kind": "hero", "player": p_idx, "uid": -1, "amount": p2["hp"] - heal_before2, "source_uid": _src_uid, "source_card_id": _src_card})
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
			for m in enemy["board"]:
				m["health"] -= value
				_emit("damage", {"target_kind": "minion", "player": 1 - p_idx, "uid": uid_for(m), "amount": value, "source_uid": _src_uid, "source_card_id": _src_card})
		"damage_all_minions":
			# Snapshot both boards: apply to every minion, then clean up.
			# ALL damage events fire before ANY minion_died (deaths are
			# processed by the caller, after this effect resolves).
			for pl_i in players.size():
				for m in players[pl_i]["board"]:
					m["health"] -= value
					_emit("damage", {"target_kind": "minion", "player": pl_i, "uid": uid_for(m), "amount": value, "source_uid": _src_uid, "source_card_id": _src_card})
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
		"random_enemy_damage":
			_random_enemy_damage(p_idx, value)
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
			players[1 - p_idx]["hp"] -= payoff_dmg
			if payoff_dmg > 0:
				_emit("damage", {"target_kind": "hero", "player": 1 - p_idx, "uid": -1, "amount": payoff_dmg, "source_uid": _src_uid, "source_card_id": _src_card})
		"damage_per_hand_card":
			var count: int = hand_before if hand_before >= 0 else players[p_idx]["hand"].size()
			var hand_dmg: int = value * count
			players[1 - p_idx]["hp"] -= hand_dmg
			if hand_dmg > 0:
				_emit("damage", {"target_kind": "hero", "player": 1 - p_idx, "uid": -1, "amount": hand_dmg, "source_uid": _src_uid, "source_card_id": _src_card})
		"damage_split":
			# N 1-damage packets, each to a random enemy character.
			# No mid-split cleanup — a minion at 0 HP can absorb packets.
			for _i in value:
				var t: Dictionary = _random_enemy_character(p_idx)
				if t.is_empty():
					break
				_deal_damage_to_target(p_idx, t, 1)
		"recruit":
			_recruit(p_idx, value)
		"swap_stats":
			_swap_stats(p_idx)


func _apply_buff(p_idx: int, m: Dictionary, n: int) -> void:
	# Permanent: current AND max Health +N, damage taken stays.
	m["attack"] += n
	m["max_health"] += n
	m["health"] += n
	_emit("buff", {"player": p_idx, "uid": uid_for(m), "attack_delta": n, "health_delta": n, "source_uid": _src_uid, "source_card_id": _src_card})


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
		players[target["player"]]["hp"] -= amount
		_emit("damage", {"target_kind": "hero", "player": target["player"], "uid": -1, "amount": amount, "source_uid": _src_uid, "source_card_id": _src_card})
	else:
		var board: Array = players[target["player"]]["board"]
		if target["board_idx"] < board.size():
			board[target["board_idx"]]["health"] -= amount
			_emit("damage", {"target_kind": "minion", "player": target["player"], "uid": uid_for(board[target["board_idx"]]), "amount": amount, "source_uid": _src_uid, "source_card_id": _src_card})


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
		players[enemy_idx]["hp"] -= dmg
		_emit("damage", {"target_kind": "hero", "player": enemy_idx, "uid": -1, "amount": dmg, "source_uid": _src_uid, "source_card_id": _src_card})
		log.append("Roulette: %d damage to the enemy Boss!" % dmg)
	else:
		var idx: int = rng.randi_range(0, enemy["board"].size() - 1)
		enemy["board"][idx]["health"] -= dmg
		_emit("damage", {"target_kind": "minion", "player": enemy_idx, "uid": uid_for(enemy["board"][idx]), "amount": dmg, "source_uid": _src_uid, "source_card_id": _src_card})
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
	mine["board"].append(m)
	_emit("minion_stolen", {"from_player": 1 - p_idx, "to_player": p_idx, "uid": uid_for(m)})
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
	var old_atk: int = m["attack"]
	m["attack"] = m["health"]
	m["health"] = old_atk
	m["max_health"] = old_atk
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
			out.append({"owner": p_idx, "uid": uid_for(board[i]), "card_id": board[i]["card_id"], "name": board[i]["name"]})
		for i in range(dead_idx.size() - 1, -1, -1):
			board.remove_at(dead_idx[i])
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
			_resolve_deathrattle(int(dead["owner"]), dead)
		pending.append_array(_collect_dead())


# Kept for callers that used the old name.
func _cleanup_deaths() -> void:
	_process_deaths()


func _resolve_deathrattle(owner_idx: int, dead: Dictionary) -> void:
	var card: Dictionary = CardDB.get_card(str(dead["card_id"]))
	if card.is_empty():
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
	var taunts: Array = []
	for i in enemy["board"].size():
		if enemy["board"][i]["taunt"]:
			taunts.append({"kind": "minion", "player": enemy_idx, "board_idx": i})
	if not taunts.is_empty():
		return taunts
	var out: Array = []
	for i in enemy["board"].size():
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
	return m["can_attack"] and m["attack"] > 0


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
	attacker["can_attack"] = false
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
	if target["kind"] == "hero":
		players[target["player"]]["hp"] -= attacker["attack"]
		_emit("damage", {"target_kind": "hero", "player": target["player"], "uid": -1, "amount": attacker["attack"], "source_uid": attacker_uid, "source_card_id": ""})
	else:
		var enemy_board: Array = players[target["player"]]["board"]
		var defender: Dictionary = enemy_board[target["board_idx"]]
		var defender_uid: int = uid_for(defender)
		# Simultaneous trade: BOTH damage events fire before ANY
		# minion_died (deaths are processed below, after this block).
		defender["health"] -= attacker["attack"]
		_emit("damage", {"target_kind": "minion", "player": target["player"], "uid": defender_uid, "amount": attacker["attack"], "source_uid": attacker_uid, "source_card_id": ""})
		attacker["health"] -= defender["attack"]
		_emit("damage", {"target_kind": "minion", "player": p_idx, "uid": attacker_uid, "amount": defender["attack"], "source_uid": defender_uid, "source_card_id": ""})
	_process_deaths()
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
				return target["player"] == 1 - p_idx and target["board_idx"] < players[target["player"]]["board"].size()
			return false
		"enemy_minion":
			return target["kind"] == "minion" and target["player"] == 1 - p_idx and target["board_idx"] < players[target["player"]]["board"].size()
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
				out.append({"kind": "minion", "player": enemy_idx, "board_idx": i})
			out.append({"kind": "hero", "player": enemy_idx, "board_idx": -1})
		"enemy_minion":
			var e_idx: int = 1 - p_idx
			for i in players[e_idx]["board"].size():
				out.append({"kind": "minion", "player": e_idx, "board_idx": i})
		"friendly_minion":
			for i in players[p_idx]["board"].size():
				out.append({"kind": "minion", "player": p_idx, "board_idx": i})
	return out


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
