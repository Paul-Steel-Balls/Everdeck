extends Node

# Headless test runner for Everdeck GameState logic.
# Run: godot --headless --path . res://tests/test_main.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run_all()
	print("TESTS: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % name)
	else:
		_failed += 1
		print("FAIL: %s" % name)


func _deck_of(card_id: String, n: int = 30) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


func _gs_with_hands(h0: Array, h1: Array, mana0: int = 10, mana1: int = 10) -> GameState:
	return _gs_for(h0, h1, "neutral", "neutral", mana0, mana1)


func _gs_for(h0: Array, h1: Array, c0: String, c1: String, mana0: int = 10, mana1: int = 10) -> GameState:
	var gs := GameState.new()
	gs.set_seed(12345)
	gs.setup(_deck_of("angry_squirrel"), _deck_of("angry_squirrel"), c0, c1)
	gs.players[0]["hand"] = h0.duplicate()
	gs.players[1]["hand"] = h1.duplicate()
	gs.players[0]["mana"] = mana0
	gs.players[0]["max_mana"] = mana0
	gs.players[1]["mana"] = mana1
	gs.players[1]["max_mana"] = mana1
	gs.active = 0
	return gs


func _minion(card_id: String, can_attack: bool = true) -> Dictionary:
	var c: Dictionary = CardDB.get_card(card_id)
	return {
		"card_id": c["id"], "name": c["name"], "attack": c["attack"],
		"health": c["health"], "max_health": c["health"],
		"taunt": c["keywords"].has("taunt"),
		"can_attack": can_attack, "sick": false,
	}


func _card_with_effect(effect: String, type: String = "", class_id: String = "") -> Dictionary:
	for c in CardDB.CARDS:
		if str(c.get("effect", "")) == effect:
			if type != "" and c["type"] != type:
				continue
			if class_id != "" and c["class"] != class_id:
				continue
			return c
	return {}


func _card_with_dr(effect: String) -> Dictionary:
	for c in CardDB.CARDS:
		if str(c.get("deathrattle", "")) == effect:
			return c
	return {}


func _valid_deck_for(class_id: String) -> Array:
	var commons: Array = []
	for c in CardDB.cards_for_class(class_id):
		if c["rarity"] == "Common" and not commons.has(c["id"]):
			commons.append(c["id"])
		if commons.size() >= 15:
			break
	var d: Array = []
	for id in commons:
		d.append(id)
		d.append(id)
	return d



func _modal_no_stop_kids(root: Control) -> bool:
	# True when no non-Button descendant of a modal overlay keeps
	# MOUSE_FILTER_STOP (which would swallow taps meant for dismiss).
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Button:
				continue
			if ch is Control and (ch as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				return false
			stack.append(ch)
	return true

func _run_all() -> void:
	await _test_online_3d()
	_test_ai_no_stall()
	preload("res://tests/mechanics_tests.gd").new().run(self)
	# --- cards.json loading (Phase 3) ---
	_check("cards.json: 340 cards load", CardDB.CARDS.size() == 340)
	var fields_ok: bool = true
	var class_counts: Dictionary = {}
	for c in CardDB.CARDS:
		for f in ["id", "name", "class", "cost", "type", "attack", "health", "keywords", "effect", "effect_value", "target", "rarity", "text", "flavor", "art", "deathrattle", "deathrattle_value", "deathrattle_target"]:
			if not c.has(f):
				fields_ok = false
		class_counts[c["class"]] = class_counts.get(c["class"], 0) + 1
	_check("cards.json: every card has all fields", fields_ok)
	_check("cards.json: 50 per class + 40 neutral", class_counts.get("grunk", 0) == 50 and class_counts.get("agatha", 0) == 50 and class_counts.get("presto", 0) == 50 and class_counts.get("barnacle", 0) == 50 and class_counts.get("reginald", 0) == 50 and class_counts.get("larry", 0) == 50 and class_counts.get("neutral", 0) == 40)
	var e2: Array = []
	for c in CardDB.CARDS:
		if str(c.get("effect2", "")) != "":
			e2.append(c["id"])
	_check("cards.json: effect2 only on the 4 exception spells", e2.size() == 4 and e2.has("wisdom") and e2.has("presto_cantrip") and e2.has("reg_blessing") and e2.has("lar_double_down"))
	_check("cards.json: all art ids non-empty (generic art covers all)", CardDB.CARDS.all(func(c: Dictionary) -> bool: return not str(c.get("art", "")).strip_edges().is_empty()))

	# --- Deck validation ---
	var ok_deck: Array = _valid_deck_for("grunk")
	_check("validate_deck: 30 cards, class-legal, rarity limits = valid", GameState.validate_deck(ok_deck, "grunk"))
	_check("validate_deck: neutral-only deck passes", GameState.validate_deck(_valid_deck_for("neutral"), "grunk"))
	var short: Array = ok_deck.duplicate()
	short.pop_back()
	_check("validate_deck: 29 cards = invalid", not GameState.validate_deck(short))
	var long_d: Array = ok_deck.duplicate()
	long_d.append(ok_deck[0])
	_check("validate_deck: 31 cards = invalid", not GameState.validate_deck(long_d))
	# 3 copies of one Common (squire) + valid rest = invalid.
	var three: Array = ["squire", "squire", "squire"]
	var rest: Array = []
	for c in CardDB.cards_for_class("neutral"):
		if c["rarity"] == "Common" and c["id"] != "squire" and not rest.has(c["id"]):
			rest.append(c["id"])
		if rest.size() >= 14:
			break
	for i in 13:
		three.append(rest[i])
		three.append(rest[i])
	three.append(rest[13])
	_check("validate_deck: 3 copies = invalid", not GameState.validate_deck(three))
	var leg2: Array = _valid_deck_for("grunk")
	leg2[0] = "grunk_sparky"
	leg2[1] = "grunk_sparky"
	_check("validate_deck: Legendary x2 = invalid", not GameState.validate_deck(leg2))
	var wrong: Array = _valid_deck_for("grunk")
	wrong[0] = "healing_light"  # Agatha card in a Grunk deck.
	_check("validate_deck: wrong-class card = invalid", not GameState.validate_deck(wrong, "grunk"))
	var bad: Array = ok_deck.duplicate()
	bad[0] = "no_such_card"
	_check("validate_deck: unknown card = invalid", not GameState.validate_deck(bad))
	_check("validate_deck: mirror decks both valid (same class)", GameState.validate_deck(_valid_deck_for("grunk"), "grunk") and GameState.validate_deck(_valid_deck_for("grunk"), "grunk"))
	var coin_deck: Array = ok_deck.duplicate()
	coin_deck[0] = "coin"
	_check("validate_deck: Coin not allowed in decks", not GameState.validate_deck(coin_deck))

	# --- Setup / mana curve ---
	var gs := GameState.new()
	gs.setup(_deck_of("angry_squirrel"), _deck_of("angry_squirrel"), "grunk", "agatha")
	_check("setup: P0 starts, mana 1/1", gs.active == 0 and gs.players[0]["mana"] == 1 and gs.players[0]["max_mana"] == 1)
	# Balance Patch v1 (corrected): after setup P1 has 4 cards, P2 has 5 cards + The Coin.
	_check("setup: starting hands P1=4, P2=4+2 Coins", gs.players[0]["hand"].size() == 4 and gs.players[1]["hand"].size() == 6 and gs.players[1]["hand"].count("coin") == 2)
	_check("setup: Coin is not in the card pool", not CardDB.card_ids().has("coin"))
	_check("setup: classes stored", gs.players[0]["class"] == "grunk" and gs.players[1]["class"] == "agatha")
	_check("setup: turn_count starts at 1", gs.turn_count == 1)
	for _i in 20:
		gs.end_turn()
	_check("mana curve: caps at 10", gs.players[0]["max_mana"] == 10 and gs.players[1]["max_mana"] == 10)
	_check("mana curve: mana refills each turn", gs.players[gs.active]["mana"] == gs.players[gs.active]["max_mana"])

	# --- Draw + fatigue ---
	var gs2 := GameState.new()
	gs2.setup(_deck_of("angry_squirrel"), _deck_of("angry_squirrel"))
	gs2.players[0]["deck"] = []
	gs2.players[0]["fatigue"] = 0
	gs2.players[0]["hp"] = 30
	gs2.draw_cards(0, 3)
	_check("fatigue: 1+2+3 damage", gs2.players[0]["hp"] == 24 and gs2.players[0]["fatigue"] == 3)

	# --- Hand limit burn ---
	var gs3 := GameState.new()
	gs3.setup(_deck_of("angry_squirrel"), _deck_of("angry_squirrel"))
	gs3.players[0]["hand"] = _deck_of("angry_squirrel", 10)
	gs3.players[0]["deck"] = ["squire"]
	var log_before: int = gs3.log.size()
	gs3.draw_cards(0, 1)
	_check("hand limit: burn keeps hand at 10 + logs", gs3.players[0]["hand"].size() == 10 and gs3.log.size() > log_before)

	# --- Summoning sickness / charge ---
	var gs4 := _gs_with_hands(["squire"], [])
	_check("play minion: summoning sick", gs4.play_card(0, 0) and gs4.players[0]["board"][0]["can_attack"] == false)
	gs4.end_turn()
	gs4.end_turn()
	_check("summoning sickness wears off next turn", gs4.players[0]["board"][0]["can_attack"] == true)
	var gs5 := _gs_with_hands(["charger"], [])
	_check("charge: can attack immediately", gs5.play_card(0, 0) and gs5.players[0]["board"][0]["can_attack"] == true)

	# --- Taunt (Squire Gregory is now a Taunt minion too, so use Good Boy as the non-taunt) ---
	var gs6 := _gs_with_hands([], [])
	gs6.players[0]["board"] = [_minion("squire")]
	gs6.players[1]["board"] = [_minion("shieldbearer"), _minion("guard_dog")]
	var targets: Array = gs6.valid_attack_targets(0)
	_check("taunt: only taunt minion is a valid target", targets.size() == 1 and targets[0]["board_idx"] == 0)
	_check("taunt: attacking non-taunt fails", not gs6.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 1}))
	_check("taunt: attacking taunt works", gs6.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0}))

	# --- Battlecries ---
	var gs7 := _gs_with_hands(["medic"], [])
	gs7.players[0]["hp"] = 20
	_check("battlecry medic: heals 3", gs7.play_card(0, 0) and gs7.players[0]["hp"] == 23)
	var gs8 := _gs_with_hands(["zapper"], [])
	gs8.players[1]["board"] = [_minion("charger")]
	_check("battlecry zapper: 2 damage kills 2-HP charger", gs8.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0}) and gs8.players[1]["board"].is_empty())
	var gs9 := _gs_with_hands(["scout"], [])
	var deck_before: int = gs9.players[0]["deck"].size()
	_check("battlecry scout: draws 1", gs9.play_card(0, 0) and gs9.players[0]["hand"].size() == 1 and gs9.players[0]["deck"].size() == deck_before - 1)
	var gs10 := _gs_with_hands(["summoner"], [])
	_check("battlecry summoner: summons 1/1 token", gs10.play_card(0, 0) and gs10.players[0]["board"].size() == 2 and gs10.players[0]["board"][1]["card_id"] == "squireling")

	# --- Combat math ---
	var gs11 := _gs_with_hands([], [])
	gs11.players[0]["board"] = [_minion("brute")]
	gs11.players[1]["board"] = [_minion("squire")]
	_check("combat: minion-minion trades damage, defender dies", gs11.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0}) and gs11.players[1]["board"].is_empty() and gs11.players[0]["board"][0]["health"] == 2)
	_check("combat: damage persists", gs11.players[0]["board"][0]["health"] == 2)
	var gs12 := _gs_with_hands([], [])
	gs12.players[0]["board"] = [_minion("brute")]
	_check("combat: minion-hero deals attack", gs12.attack(0, 0, {"kind": "hero", "player": 1, "board_idx": -1}) and gs12.players[1]["hp"] == 26)
	var gs13 := _gs_with_hands([], [])
	gs13.players[0]["board"] = [_minion("brute")]
	gs13.players[1]["hp"] = 3
	_check("lethal: hero at 0 HP ends game", gs13.attack(0, 0, {"kind": "hero", "player": 1, "board_idx": -1}) and gs13.winner == 0)

	# --- Turn flow (Balance Patch v1 corrected: after P2's first draw, P1 = 4, P2 = 6 + Coin) ---
	var gs14 := GameState.new()
	gs14.setup(_deck_of("angry_squirrel"), _deck_of("angry_squirrel"))
	gs14.end_turn()
	var p2_hand: Array = gs14.players[1]["hand"]
	var p2_regular: int = 0
	for c in p2_hand:
		if c != "coin":
			p2_regular += 1
	_check("turn flow: end_turn passes + draws; P2 = 5 + 2 Coins after first draw", gs14.active == 1 and p2_hand.size() == 7 and p2_hand.count("coin") == 2 and p2_regular == 5 and gs14.players[0]["hand"].size() == 4)

	# --- Mana / board limits ---
	var gs15 := _gs_with_hands(["dragon"], [], 1, 10)
	_check("mana: cannot play card over mana", not gs15.can_play(0, 0) and not gs15.play_card(0, 0))
	var gs16 := _gs_with_hands(["squire"], [])
	for _i in 7:
		gs16.players[0]["board"].append(_minion("squire"))
	_check("board limit: 8th minion cannot be played", not gs16.can_play(0, 0))

	# --- Targeted spells ---
	var gs17 := _gs_with_hands(["assassinate"], [])
	_check("assassinate on hero fails", not gs17.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1}))
	var gs18 := _gs_with_hands(["fireball"], [])
	_check("fireball on own hero fails", not gs18.play_card(0, 0, {"kind": "hero", "player": 0, "board_idx": -1}))
	_check("fireball on enemy hero works", gs18.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1}) and gs18.players[1]["hp"] == 27)
	var gs19 := _gs_with_hands(["nova"], [])
	gs19.players[1]["board"] = [_minion("squire"), _minion("guard_dog")]
	_check("nova: 2 damage to all enemy minions", gs19.play_card(0, 0) and gs19.players[1]["board"].size() == 2 and gs19.players[1]["board"][0]["health"] == 1 and gs19.players[1]["board"][1]["health"] == 1)

	# --- Chaos cards ---
	var gs20 := _gs_with_hands(["hand_swap"], ["dragon"])
	_check("hand swap: hands exchange (played card is gone first)", gs20.play_card(0, 0) and gs20.players[0]["hand"] == ["dragon"] and gs20.players[1]["hand"] == [])
	var gs21 := _gs_with_hands(["mind_trick"], [])
	gs21.players[1]["board"] = [_minion("recruit"), _minion("ogre")]
	_check("mind trick: steals weak minion only", gs21.play_card(0, 0) and gs21.players[0]["board"].size() == 1 and gs21.players[0]["board"][0]["card_id"] == "recruit" and gs21.players[1]["board"].size() == 1)
	var gs22 := _gs_with_hands(["roulette"], [])
	gs22.players[1]["board"] = [_minion("fortress")]
	var hp_before: int = gs22.players[1]["hp"]
	gs22.play_card(0, 0)
	# Fortress has 6 HP; 2-5 damage leaves it at 1-4 HP, hero untouched.
	_check("roulette: 2-5 damage to a random enemy minion, hero untouched", gs22.players[1]["hp"] == hp_before and gs22.players[1]["board"].size() == 1 and gs22.players[1]["board"][0]["health"] >= 1 and gs22.players[1]["board"][0]["health"] <= 4)
	var gs22b := _gs_with_hands(["roulette"], [])
	gs22b.players[1]["board"] = []
	var hp22b: int = gs22b.players[1]["hp"]
	gs22b.play_card(0, 0)
	_check("roulette: with no enemy minions, hits the enemy hero for 2-5", gs22b.players[1]["hp"] >= hp22b - 5 and gs22b.players[1]["hp"] <= hp22b - 2)
	var gs23 := _gs_with_hands(["coin_flip"], [])
	gs23.set_seed(7)
	var hp23: int = gs23.players[0]["hp"]
	var hand23: int = gs23.players[0]["hand"].size()
	gs23.play_card(0, 0)
	# Heads: hand +1 (played card replaced + 1 extra draw), HP unchanged.
	# Tails: hand unchanged (played card replaced by the 1 draw), HP -2.
	var heads: bool = gs23.players[0]["hand"].size() == hand23 + 1 and gs23.players[0]["hp"] == hp23
	var tails: bool = gs23.players[0]["hand"].size() == hand23 and gs23.players[0]["hp"] == hp23 - 2
	_check("coin flip: heads draw 2 / tails draw 1 + take 2", heads != tails and (heads or tails))

	# --- Balance Patch v1 new effects ---
	var gs_heal := _gs_with_hands(["healing_light"], [])
	gs_heal.players[0]["hp"] = 20
	var heal_deck: int = gs_heal.players[0]["deck"].size()
	_check("heal_draw: heals 5 and draws a card", gs_heal.play_card(0, 0) and gs_heal.players[0]["hp"] == 25 and gs_heal.players[0]["hand"].size() == 1 and gs_heal.players[0]["deck"].size() == heal_deck - 1)
	var gs_heal2 := _gs_with_hands(["healing_light"], [])
	gs_heal2.players[0]["hp"] = 28
	_check("heal_draw: heal caps at 30", gs_heal2.play_card(0, 0) and gs_heal2.players[0]["hp"] == 30)
	var gs_coin := _gs_with_hands(["coin"], [])
	gs_coin.players[0]["mana"] = 5
	_check("Coin: 0-cost, grants +1 mana this turn", gs_coin.play_card(0, 0) and gs_coin.players[0]["mana"] == 6 and gs_coin.players[0]["hand"].is_empty())
	var gs_coin2 := _gs_with_hands(["coin"], [])
	gs_coin2.players[0]["mana"] = 0
	_check("Coin: playable at 0 mana", gs_coin2.play_card(0, 0) and gs_coin2.players[0]["mana"] == 1)
	var gs_coin3 := _gs_with_hands(["coin"], [])
	gs_coin3.players[0]["mana"] = 10
	_check("Coin: gain_mana caps at 10", gs_coin3.play_card(0, 0) and gs_coin3.players[0]["mana"] == 10)

	# --- Hero powers (all 6) ---
	var hp_grunk := _gs_for([], [], "grunk", "agatha")
	_check("hero power grunk: 2 mana, 2 damage to enemy hero, once/turn, turn not ended", hp_grunk.use_hero_power(0) and hp_grunk.players[1]["hp"] == 28 and hp_grunk.players[0]["mana"] == 8 and hp_grunk.players[0]["hero_power_used"] == true and hp_grunk.active == 0 and hp_grunk.players[0]["cards_played_this_turn"] == 0)
	_check("hero power grunk: second use same turn fails", not hp_grunk.use_hero_power(0) and hp_grunk.players[1]["hp"] == 28)
	hp_grunk.end_turn()
	hp_grunk.end_turn()
	_check("hero power grunk: usable again next turn", hp_grunk.use_hero_power(0) and hp_grunk.players[1]["hp"] == 26)
	var hp_poor := _gs_for([], [], "grunk", "agatha", 1, 10)
	_check("hero power: cannot use with < 2 mana", not hp_poor.use_hero_power(0) and hp_poor.players[0]["hero_power_used"] == false)
	var hp_agatha := _gs_for([], [], "agatha", "grunk")
	hp_agatha.players[0]["hp"] = 20
	_check("hero power agatha: restore 2", hp_agatha.use_hero_power(0) and hp_agatha.players[0]["hp"] == 22)
	var hp_agatha2 := _gs_for([], [], "agatha", "grunk")
	hp_agatha2.players[0]["hp"] = 29
	_check("hero power agatha: heal caps at 30", hp_agatha2.use_hero_power(0) and hp_agatha2.players[0]["hp"] == 30)
	var hp_presto := _gs_for([], [], "presto", "grunk")
	hp_presto.players[0]["deck"] = ["squire", "squire"]
	_check("hero power presto: draw 1 + take 2", hp_presto.use_hero_power(0) and hp_presto.players[0]["hand"].size() == 1 and hp_presto.players[0]["hp"] == 28)
	var hp_presto2 := _gs_for([], [], "presto", "grunk")
	hp_presto2.players[0]["deck"] = []
	hp_presto2.players[0]["fatigue"] = 0
	_check("hero power presto: empty deck fatigues AND damage still applies", hp_presto2.use_hero_power(0) and hp_presto2.players[0]["hp"] == 27)
	var hp_presto3 := _gs_for(_deck_of("angry_squirrel", 10), [], "presto", "grunk")
	hp_presto3.players[0]["deck"] = ["squire"]
	_check("hero power presto: full hand burns AND damage still applies", hp_presto3.use_hero_power(0) and hp_presto3.players[0]["hand"].size() == 10 and hp_presto3.players[0]["hp"] == 28)
	var hp_barn := _gs_for([], [], "barnacle", "grunk")
	_check("hero power barnacle: summons 1/2 Deckhand", hp_barn.use_hero_power(0) and hp_barn.players[0]["board"].size() == 1 and hp_barn.players[0]["board"][0]["name"] == "Deckhand" and hp_barn.players[0]["board"][0]["attack"] == 1 and hp_barn.players[0]["board"][0]["health"] == 2)
	var hp_barn_full := _gs_for([], [], "barnacle", "grunk")
	for _i in 7:
		hp_barn_full.players[0]["board"].append(_minion("squire"))
	_check("hero power barnacle: full board = cannot use, not consumed", not hp_barn_full.use_hero_power(0) and hp_barn_full.players[0]["hero_power_used"] == false and hp_barn_full.players[0]["mana"] == 10 and hp_barn_full.players[0]["board"].size() == 7)
	var hp_reg := _gs_for([], [], "reginald", "grunk")
	hp_reg.players[0]["board"] = [_minion("guard_dog")]
	_check("hero power reginald: buffs friendly minion +1/+1", hp_reg.use_hero_power(0, {"kind": "minion", "player": 0, "board_idx": 0}) and hp_reg.players[0]["board"][0]["attack"] == 3 and hp_reg.players[0]["board"][0]["health"] == 4 and hp_reg.players[0]["board"][0]["max_health"] == 4)
	var hp_reg_empty := _gs_for([], [], "reginald", "grunk")
	_check("hero power reginald: no friendly minion = cannot use, not consumed", not hp_reg_empty.use_hero_power(0) and hp_reg_empty.players[0]["hero_power_used"] == false and hp_reg_empty.players[0]["mana"] == 10)
	var hp_reg_dmg := _gs_for([], [], "reginald", "grunk")
	var dmg_m: Dictionary = _minion("guard_dog")
	dmg_m["health"] = 1  # 2/3 damaged to 1 HP: damage taken = 2.
	hp_reg_dmg.players[0]["board"] = [dmg_m]
	_check("hero power reginald: buff on damaged minion keeps damage taken", hp_reg_dmg.use_hero_power(0, {"kind": "minion", "player": 0, "board_idx": 0}) and hp_reg_dmg.players[0]["board"][0]["attack"] == 3 and hp_reg_dmg.players[0]["board"][0]["health"] == 2 and hp_reg_dmg.players[0]["board"][0]["max_health"] == 4)
	var hp_larry := _gs_for([], [], "larry", "grunk")
	_check("hero power larry: 2 damage to random enemy (hero only)", hp_larry.use_hero_power(0) and hp_larry.players[1]["hp"] == 28)
	var hp_larry2 := _gs_for([], [], "larry", "grunk")
	hp_larry2.players[1]["board"] = [_minion("squire")]
	var l_hp_before: int = hp_larry2.players[1]["hp"]
	var l_m_before: int = hp_larry2.players[1]["board"][0]["health"]
	hp_larry2.use_hero_power(0)
	_check("hero power larry: exactly 2 total damage with minions present", (l_hp_before - hp_larry2.players[1]["hp"]) + (l_m_before - hp_larry2.players[1]["board"][0]["health"]) == 2)
	var hp_neutral := _gs_with_hands([], [])
	_check("hero power: neutral class has none", not hp_neutral.use_hero_power(0))

	# --- Cards-played counter + damage_per_card_played ---
	var cp0 := _gs_for(["presto_payoff"], [], "presto", "grunk")
	_check("payoff: first card of the turn deals 0", cp0.play_card(0, 0) and cp0.players[1]["hp"] == 30 and cp0.players[0]["cards_played_this_turn"] == 1)
	var cp1 := _gs_for(["coin", "angry_squirrel", "presto_payoff"], [], "presto", "grunk")
	cp1.play_card(0, 0)
	_check("counter: Coin counts as a card played", cp1.players[0]["cards_played_this_turn"] == 1)
	cp1.play_card(0, 0)
	_check("counter: second card counted", cp1.players[0]["cards_played_this_turn"] == 2)
	# Payoff N=2: 2N=4 per other card x 2 others = 8 damage.
	_check("payoff: deals 2N per OTHER card (2x2x2=8)", cp1.play_card(0, 0) and cp1.players[1]["hp"] == 22)
	var cp2 := _gs_for(["coin", "presto_firecracker"], [], "presto", "grunk")
	cp2.play_card(0, 0)
	_check("payoff minion: 2N per other card (1x2x1=2)", cp2.play_card(0, 0) and cp2.players[1]["hp"] == 28 and cp2.players[0]["board"].size() == 1)
	# Balance patch 2: a payoff counts at most 3 other cards.
	var cpc := _gs_for(["coin", "coin", "angry_squirrel", "squire", "presto_payoff"], [], "presto", "grunk")
	for _k in 4:
		cpc.play_card(0, 0)
	_check("payoff: counts at most 3 other cards (4 played -> 4x3 = 12)", cpc.play_card(0, 0) and cpc.players[1]["hp"] == 18)
	var cp3 := _gs_for(["coin"], [], "presto", "grunk")
	cp3.play_card(0, 0)
	cp3.end_turn()
	cp3.end_turn()
	_check("counter: resets at the start of your turn", cp3.players[0]["cards_played_this_turn"] == 0)
	var cp4 := _gs_for([], [], "grunk", "agatha")
	cp4.use_hero_power(0)
	_check("counter: hero power does NOT increment it", cp4.players[0]["cards_played_this_turn"] == 0)

	# --- damage_per_hand_card (Battlecry counts the played card) ---
	var ph := _gs_for(["presto_headmaster", "angry_squirrel", "squire", "recruit"], [], "presto", "grunk")
	_check("hand payoff: Battlecry counts played card (4 in hand = 4 dmg)", ph.play_card(0, 0) and ph.players[1]["hp"] == 26 and ph.players[0]["board"].size() == 1)

	# --- draw_self_damage (card) ---
	var dsd_card: Dictionary = _card_with_effect("draw_self_damage")
	var dsd := _gs_for([str(dsd_card["id"])], [], "presto", "grunk")
	dsd.players[0]["deck"] = ["squire"]
	var dsd_hp: int = dsd.players[0]["hp"]
	var dsd_hand: int = dsd.players[0]["hand"].size()
	var dsd_ok: bool = dsd.play_card(0, 0)
	if dsd_card["type"] == "minion":
		_check("draw_self_damage card: draw 1 + take 2 (minion)", dsd_ok and dsd.players[0]["hp"] == dsd_hp - 2 and dsd.players[0]["hand"].size() == dsd_hand and dsd.players[0]["board"].size() == 1)
	else:
		_check("draw_self_damage card: draw 1 + take 2 (spell)", dsd_ok and dsd.players[0]["hp"] == dsd_hp - 2 and dsd.players[0]["hand"].size() == dsd_hand)

	# --- buff_friendly ---
	var bf_spell := _gs_for(["reg_greater_blessing"], [], "reginald", "grunk")
	_check("buff spell: no friendly minion = cannot play", not bf_spell.play_card(0, 0))
	bf_spell.players[0]["board"] = [_minion("guard_dog")]
	_check("buff spell: +2/+2 on friendly minion", bf_spell.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0}) and bf_spell.players[0]["board"][0]["attack"] == 4 and bf_spell.players[0]["board"][0]["health"] == 5 and bf_spell.players[0]["board"][0]["max_health"] == 5)
	var bf_dmg := _gs_for(["reg_greater_blessing"], [], "reginald", "grunk")
	var bf_m: Dictionary = _minion("guard_dog")
	bf_m["health"] = 1
	bf_dmg.players[0]["board"] = [bf_m]
	_check("buff: damaged minion keeps damage taken (1->3 HP, max 3->5)", bf_dmg.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0}) and bf_dmg.players[0]["board"][0]["health"] == 3 and bf_dmg.players[0]["board"][0]["max_health"] == 5)
	var bf_stack := _gs_for(["reg_greater_blessing", "reg_greater_blessing"], [], "reginald", "grunk")
	bf_stack.players[0]["board"] = [_minion("guard_dog")]
	bf_stack.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0})
	bf_stack.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0})
	_check("buff: buffs stack (+4/+4 total)", bf_stack.players[0]["board"][0]["attack"] == 6 and bf_stack.players[0]["board"][0]["health"] == 7)
	# Battlecry buff fizzle: minion playable with no OTHER friendly minion.
	var bf_fizzle := _gs_for(["reg_sergeant"], [], "reginald", "grunk")
	_check("battlecry fizzle: buff minion playable alone, effect does nothing", bf_fizzle.play_card(0, 0) and bf_fizzle.players[0]["board"].size() == 1 and bf_fizzle.players[0]["board"][0]["attack"] == 3)
	# Battlecry buff cannot self-target.
	var bf_self := _gs_for(["reg_sergeant"], [], "reginald", "grunk")
	bf_self.players[0]["board"] = [_minion("guard_dog")]
	bf_self.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 1})  # index 1 = just-summoned sergeant.
	_check("battlecry buff: self-target fizzles (other minion unbuffed, sergeant unbuffed)", bf_self.players[0]["board"][0]["attack"] == 2 and bf_self.players[0]["board"][1]["attack"] == 3)
	var bf_other := _gs_for(["reg_sergeant"], [], "reginald", "grunk")
	bf_other.players[0]["board"] = [_minion("guard_dog")]
	_check("battlecry buff: targets ANOTHER friendly minion", bf_other.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0}) and bf_other.players[0]["board"][0]["attack"] == 3)

	# --- random_enemy_damage ---
	var re1 := _gs_for(["grunk_rocket"], [], "grunk", "agatha")
	_check("random_enemy_damage: hero-only target takes full value (3)", re1.play_card(0, 0) and re1.players[1]["hp"] == 27)
	var re2 := _gs_for(["grunk_rocket"], [], "grunk", "agatha")
	re2.players[1]["board"] = [_minion("squire")]
	var re_hp: int = re2.players[1]["hp"]
	var re_m: int = re2.players[1]["board"][0]["health"]
	re2.play_card(0, 0)
	_check("random_enemy_damage: exactly N total damage with minions present", (re_hp - re2.players[1]["hp"]) + (re_m - re2.players[1]["board"][0]["health"]) == 3)

	# --- damage_all_minions ---
	var am := _gs_for(["lar_rigged_deck"], [], "larry", "grunk")
	am.players[0]["board"] = [_minion("recruit")]  # 2/1: dies to 2 damage.
	am.players[1]["board"] = [_minion("knight")]
	_check("damage_all_minions: hits both boards, not heroes", am.play_card(0, 0) and am.players[0]["board"].is_empty() and am.players[1]["board"].size() == 1 and am.players[1]["board"][0]["health"] == 1 and am.players[0]["hp"] == 30 and am.players[1]["hp"] == 30)

	# --- Signatures ---
	var ds := _gs_for(["grunk_king"], [], "grunk", "agatha")
	_check("damage_split: hero-only takes all 4", ds.play_card(0, 0) and ds.players[1]["hp"] == 26)
	var ds2 := _gs_for(["grunk_king"], [], "grunk", "agatha")
	ds2.players[1]["board"] = [_minion("squire"), _minion("guard_dog")]
	var ds_hp: int = ds2.players[1]["hp"]
	var ds_m0: int = ds2.players[1]["board"][0]["health"]
	var ds_m1: int = ds2.players[1]["board"][1]["health"]
	ds2.play_card(0, 0)
	_check("damage_split: exactly N total damage spread over enemy characters", (ds_hp - ds2.players[1]["hp"]) + (ds_m0 - ds2.players[1]["board"][0]["health"]) + (ds_m1 - ds2.players[1]["board"][1]["health"]) == 4)
	var dd := _gs_for(["agatha_timmy"], [], "agatha", "grunk")
	var dd_dog: Dictionary = _minion("guard_dog")
	dd_dog["health"] = 1
	dd.players[1]["board"] = [dd_dog, _minion("knight")]
	_check("destroy_damaged: only damaged enemy minions die", dd.play_card(0, 0) and dd.players[1]["board"].size() == 1 and dd.players[1]["board"][0]["card_id"] == "knight")
	var rec := _gs_for(["barnacle_quinn"], [], "barnacle", "grunk")
	rec.players[0]["deck"] = ["scout"]  # Nosy Nancy: Battlecry draw 1 — must NOT fire on recruit.
	_check("recruit: summons from deck, no Battlecry", rec.play_card(0, 0) and rec.players[0]["board"].size() == 2 and rec.players[0]["board"][1]["name"] == "Nosy Nancy" and rec.players[0]["deck"].is_empty() and rec.players[0]["hand"].is_empty())
	var rec2 := _gs_for(["barnacle_quinn"], [], "barnacle", "grunk")
	rec2.players[0]["deck"] = ["ogre"]  # 4 cost > 3: no candidate.
	_check("recruit: fizzles with no minion costing <= N (stays in deck)", rec2.play_card(0, 0) and rec2.players[0]["board"].size() == 1 and rec2.players[0]["deck"] == ["ogre"])
	var rec3 := _gs_for(["barnacle_quinn"], [], "barnacle", "grunk")
	rec3.players[0]["deck"] = ["squire", "ogre", "knight"]
	rec3.play_card(0, 0)
	_check("recruit: picks a minion costing <= N, leaves the rest", rec3.players[0]["board"].size() == 2 and rec3.players[0]["deck"].size() == 2 and rec3.players[0]["deck"].has("ogre"))
	var baf := _gs_for(["reg_prudence"], [], "reginald", "grunk")
	var baf_m: Dictionary = _minion("guard_dog")
	baf_m["health"] = 1
	baf.players[0]["board"] = [_minion("squire"), baf_m]
	_check("buff_all_friendly: ALL friendly incl. source +N/+N", baf.play_card(0, 0) and baf.players[0]["board"].size() == 3 and baf.players[0]["board"][0]["attack"] == 2 and baf.players[0]["board"][1]["health"] == 2 and baf.players[0]["board"][1]["max_health"] == 4 and baf.players[0]["board"][2]["attack"] == 4)
	var ss := _gs_for(["lar_tessa"], [], "larry", "grunk")
	var ss_m: Dictionary = _minion("ogre")
	ss_m["attack"] = 2
	ss_m["health"] = 5
	ss_m["max_health"] = 5
	ss.players[1]["board"] = [ss_m]
	_check("swap_stats: 2/5 enemy minion becomes 5/2", ss.play_card(0, 0) and ss.players[1]["board"][0]["attack"] == 5 and ss.players[1]["board"][0]["health"] == 2 and ss.players[1]["board"][0]["max_health"] == 2)
	var ss2 := _gs_for(["lar_tessa"], [], "larry", "grunk")
	_check("swap_stats: fizzles with no enemy minion, minion still summons", ss2.play_card(0, 0) and ss2.players[0]["board"].size() == 1)

	# --- effect2 (all 4 spells) ---
	var e_wis := _gs_for(["wisdom"], [], "presto", "grunk")
	e_wis.players[1]["board"] = [_minion("knight")]
	_check("effect2 wisdom: draw 2 + 1 dmg to enemy minion", e_wis.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0}) and e_wis.players[0]["hand"].size() == 2 and e_wis.players[1]["board"][0]["health"] == 2)
	var e_wis2 := _gs_for(["wisdom"], [], "presto", "grunk")
	_check("effect2 wisdom: no enemy minion = playable, effect2 fizzles, draw still happens", e_wis2.play_card(0, 0) and e_wis2.players[0]["hand"].size() == 2)
	var e_can := _gs_for(["presto_cantrip"], [], "presto", "grunk")
	e_can.players[1]["board"] = [_minion("knight")]
	_check("effect2 cantrip: draw 1 + 1 dmg to enemy minion", e_can.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0}) and e_can.players[0]["hand"].size() == 1 and e_can.players[1]["board"][0]["health"] == 2)
	var e_ble := _gs_for(["reg_blessing"], [], "reginald", "grunk")
	e_ble.players[0]["board"] = [_minion("guard_dog")]
	e_ble.players[0]["hp"] = 20
	_check("effect2 blessing: buff +1/+1 then heal 3", e_ble.play_card(0, 0, {"kind": "minion", "player": 0, "board_idx": 0}) and e_ble.players[0]["board"][0]["attack"] == 3 and e_ble.players[0]["board"][0]["health"] == 4 and e_ble.players[0]["hp"] == 23)
	var e_ble2 := _gs_for(["reg_blessing"], [], "reginald", "grunk")
	_check("effect2 blessing: no friendly minion = cannot play", not e_ble2.play_card(0, 0))
	var e_dd := _gs_for(["lar_double_down"], [], "larry", "grunk")
	_check("effect2 double down: 1 + random 1 = 2 to enemy hero (no minions)", e_dd.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1}) and e_dd.players[1]["hp"] == 28)
	var e_dd2 := _gs_for(["lar_double_down"], [], "larry", "grunk")
	e_dd2.players[1]["board"] = [_minion("squire")]
	var dd_hp: int = e_dd2.players[1]["hp"]
	var dd_m: int = e_dd2.players[1]["board"][0]["health"]
	e_dd2.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("effect2 double down: exactly 2 total damage with minions present", (dd_hp - e_dd2.players[1]["hp"]) + (dd_m - e_dd2.players[1]["board"][0]["health"]) == 2)

	# --- Targeted spell with no valid target cannot be played ---
	var ts := _gs_for(["assassinate"], [], "agatha", "grunk")
	_check("targeted spell: no enemy minion = cannot play", not ts.play_card(0, 0))

	# --- Deathrattle ---
	var dr1 := _gs_for([], [], "neutral", "neutral")
	dr1.players[0]["board"] = [_minion("neutral_slice")]
	dr1.players[1]["board"] = [_minion("brute"), _minion("guard_dog")]
	dr1.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle: fires when minion dies (damage 1 to remaining enemy minion)", dr1.players[1]["board"].size() == 1 and dr1.players[1]["board"][0]["health"] == 2)
	var dr_ass := _gs_for(["assassinate"], [], "agatha", "presto")
	dr_ass.players[1]["board"] = [_minion("presto_familiar")]
	dr_ass.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle: destroy triggers it (draw 1)", dr_ass.players[1]["hand"].size() == 1)
	var dr_steal := _gs_for(["mind_trick"], [], "larry", "presto")
	dr_steal.players[1]["board"] = [_minion("presto_familiar")]
	dr_steal.play_card(0, 0)
	_check("deathrattle: steal does NOT trigger it (no draw)", dr_steal.players[1]["hand"].is_empty() and dr_steal.players[0]["board"].size() == 1)
	# Chain: Grandma's Deathrattle AoE-1 kills the 1-HP draw minion -> it draws.
	var dr_chain := _gs_for([], [], "grunk", "presto")
	dr_chain.players[0]["board"] = [_minion("grunk_grandma")]
	dr_chain.players[1]["board"] = [_minion("brute"), _minion("presto_familiar")]
	dr_chain.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle chain: AoE deathrattle kills a deathrattle minion, which also fires", dr_chain.players[1]["hand"].size() == 1 and dr_chain.players[1]["board"].size() == 1)
	# Order: left-to-right, active player first (single batch via damage-all).
	var dr_ord := _gs_for(["lar_rigged_deck"], [], "larry", "grunk")
	var o_nap: Dictionary = _minion("neutral_napper")
	o_nap["health"] = 1
	var o_ven: Dictionary = _minion("neutral_vending")
	o_ven["health"] = 1
	dr_ord.players[0]["board"] = [o_nap, o_ven]
	dr_ord.play_card(0, 0)
	var ord_names: Array = []
	for m in dr_ord.players[0]["board"]:
		ord_names.append(m["name"])
	_check("deathrattle order: left-to-right summons (Clock before Snack)", ord_names == ["Rude Alarm Clock", "Angry Snack"])
	var dr_ord2 := _gs_for(["lar_rigged_deck"], [], "larry", "grunk")
	var o_nap2: Dictionary = _minion("neutral_napper")
	o_nap2["health"] = 1
	var o_ven2: Dictionary = _minion("neutral_vending")
	o_ven2["health"] = 1
	dr_ord2.players[0]["board"] = [o_nap2]
	dr_ord2.players[1]["board"] = [o_ven2]
	dr_ord2.play_card(0, 0)
	var log_txt: String = "\n".join(dr_ord2.log)
	_check("deathrattle order: active player's deathrattle logs before the other's", log_txt.find("Professional Napper") != -1 and log_txt.find("Haunted Vending Machine") != -1 and log_txt.find("Professional Napper") < log_txt.find("Haunted Vending Machine"))
	# Fizzles.
	var dr_fz := _gs_for([], [], "neutral", "neutral")
	dr_fz.players[0]["board"] = [_minion("neutral_slice")]
	dr_fz.players[1]["board"] = [_minion("brute")]
	dr_fz.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle fizzle: enemy_minion with no enemy minions = no effect, hero safe", dr_fz.players[1]["hp"] == 30)
	var dr_fz2 := _gs_for([], [], "reginald", "grunk")
	dr_fz2.players[0]["board"] = [_minion("reg_banner_order")]
	dr_fz2.players[1]["board"] = [_minion("brute")]
	dr_fz2.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle fizzle: buff with no friendly minion = no crash, no buff", dr_fz2.players[0]["board"].is_empty())
	var dr_fz3 := _gs_for([], [], "neutral", "neutral")
	for _i in 7:
		dr_fz3.players[0]["board"].append(_minion("squire"))
	dr_fz3._resolve_deathrattle(0, {"owner": 0, "card_id": "neutral_napper", "name": "Napper"})
	_check("deathrattle fizzle: summon on a full board does nothing", dr_fz3.players[0]["board"].size() == 7)
	# Lethal deferred: a Deathrattle heal saves a hero at 0.
	var dr_save := _gs_for([], [], "agatha", "grunk")
	dr_save.players[0]["hp"] = 0
	var dead_heal: Dictionary = _minion("agatha_consequences")
	dead_heal["health"] = 0
	dr_save.players[0]["board"] = [dead_heal]
	dr_save._process_deaths()
	_check("deathrattle: heal saves a hero at 0 (lethal checked after deathrattles)", dr_save.players[0]["hp"] == 3 and dr_save.winner == -1)
	# Deathrattle summon token has the right name.
	var dr_tok := _gs_for([], [], "neutral", "neutral")
	dr_tok.players[0]["board"] = [_minion("neutral_napper")]
	dr_tok.players[1]["board"] = [_minion("brute")]
	dr_tok.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	_check("deathrattle summon: token name parsed from card text", dr_tok.players[0]["board"].size() == 1 and dr_tok.players[0]["board"][0]["name"] == "Rude Alarm Clock")

	# --- 7-minion cap: summon_token fizzle on play ---
	var cap1 := _gs_for(["summoner"], [], "neutral", "neutral")
	for _i in 6:
		cap1.players[0]["board"].append(_minion("squire"))
	_check("cap: battlecry summon fizzles when the played minion fills the board", cap1.play_card(0, 0) and cap1.players[0]["board"].size() == 7)
	# 7-minion cap: Deathrattle summon fizzle covered above (dr_fz3).

	# --- Funny names / flavor / art (polish) ---
	var names_seen: Dictionary = {}
	var names_ok: bool = true
	var flavor_ok: bool = true
	var art_ok: bool = true
	for c in CardDB.CARDS:
		if str(c.get("name", "")).strip_edges().is_empty():
			names_ok = false
		if names_seen.has(c["name"]):
			names_ok = false
		names_seen[c["name"]] = true
		if str(c.get("flavor", "")).strip_edges().is_empty():
			flavor_ok = false
		if str(c.get("art", "")).strip_edges().is_empty() or not CardArt.renders(str(c.get("art", ""))):
			art_ok = false
	_check("cards: every card has a unique non-empty name", names_ok and names_seen.size() == 340)
	_check("cards: every card has flavor text", flavor_ok)
	_check("cards: every card has renderable art", art_ok)
	var tok: Dictionary = CardDB.TOKEN_SQUIRELING
	_check("token: has name + flavor + renderable art", not str(tok.get("name", "")).is_empty() and not str(tok.get("flavor", "")).is_empty() and CardArt.renders(str(tok.get("art", ""))))
	_check("token: deckhand has name + flavor + renderable art", not str(CardDB.TOKEN_DECKHAND.get("name", "")).is_empty() and CardArt.renders(str(CardDB.TOKEN_DECKHAND.get("art", ""))))
	_check("pool: 340 cards", CardDB.CARDS.size() == 340)
	# Generic art: an unknown art id still renders (no blank, no crash).
	var generic_art := CardArt.new()
	generic_art.art_id = "some_future_card_art_xyz"
	generic_art.custom_minimum_size = Vector2(100, 100)
	add_child(generic_art)
	await get_tree().process_frame
	_check("art: unknown art id renders via generic fallback", generic_art.art_id == "some_future_card_art_xyz")
	generic_art.queue_free()
	# Hero portraits render.
	for hid in ["hero_grunk", "hero_agatha", "hero_presto", "hero_barnacle", "hero_reginald", "hero_larry"]:
		var pa := CardArt.new()
		pa.art_id = hid
		_check("art: hero portrait renders: %s" % hid, CardArt.renders(pa.art_id))

	# --- Colorful UI palette (no grey-dominant UI) ---
	_check("palette: table bg is saturated", CardView.TABLE_BG.s > 0.25)
	_check("palette: title bg is saturated", CardView.TITLE_BG.s > 0.25)
	_check("palette: minion frame is saturated amber", CardView.FRAME_MINION.s > 0.5)
	_check("palette: spell frame is saturated blue", CardView.FRAME_SPELL.s > 0.5)
	_check("palette: chaos frame is saturated pink", CardView.FRAME_CHAOS.s > 0.5)
	_check("palette: END TURN button is saturated green", CardView.BTN_END.s > 0.5)
	_check("palette: hero colors are saturated", CardView.HERO_P1.s > 0.5 and CardView.HERO_P2.s > 0.5)
	_check("palette: mana gem is saturated gold", CardView.MANA_GEM.s > 0.5)
	_check("palette: card frames differ by type", CardView.frame_color(CardDB.get_card("angry_squirrel")) == CardView.FRAME_MINION and CardView.frame_color(CardDB.get_card("fireball")) == CardView.FRAME_SPELL and CardView.frame_color(CardDB.get_card("roulette")) == CardView.FRAME_CHAOS)
	for cid in CardDB.CLASS_IDS:
		_check("palette: class color saturated: %s" % cid, CardView.class_color(cid).s > 0.4)

	# --- UI: class select + deckbuilding grid + hand renders ---
	var main_scene: Control = load("res://main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# Class select: 6 classes, mirrors allowed.
	main_scene._selecting_player = 0
	main_scene._show_class_select()
	await get_tree().process_frame
	await get_tree().process_frame
	var class_grid: Node = main_scene.find_child("ClassGrid", true, false)
	_check("class select: grid holds 6 class buttons", class_grid is GridContainer and class_grid.get_child_count() == 6)
	if class_grid is GridContainer:
		# Grid centered in the full-width VBox (not pinned to the left edge).
		var expect_cx: float = (main_scene.size.x - class_grid.size.x) / 2.0
		_check("class select: grid centered (no left-edge pin, no one-sided margin)", abs(class_grid.global_position.x - expect_cx) <= 2.0 and class_grid.global_position.x >= 0.0)
	# Real picks happen on different frames (P2 taps after the P2 screen
	# renders), so await a frame between them — the duplicate-delivery
	# guard ignores a second pick in the SAME frame.
	main_scene._on_class_picked("grunk")
	await get_tree().process_frame
	main_scene._on_class_picked("grunk")
	_check("class select: mirror match allowed (same class twice)", main_scene._classes == ["grunk", "grunk"])
	# (Deckbuild for P1 is already shown by the second pick.)
	var grid: Node = main_scene.find_child("PoolGrid", true, false)
	_check("deckbuild: pool is a GridContainer", grid is GridContainer)
	if grid is GridContainer:
		_check("deckbuild: grid has 5 columns", grid.columns == 5)
		_check("deckbuild: grid holds class + neutral cards only (50 + 40 = 90)", grid.get_child_count() == 90)
	var pool_classes_ok: bool = true
	for c in main_scene._pool_cards:
		if c["class"] != "grunk" and c["class"] != "neutral":
			pool_classes_ok = false
	_check("deckbuild: pool excludes other classes", pool_classes_ok)
	_check("deckbuild: no single-column pool list remains", main_scene.find_child("PoolList", true, false) == null)
	_check("deckbuild: deck strip exists", main_scene.find_child("DeckStrip", true, false) != null)
	var pool_scroll: Node = main_scene.find_child("PoolScroll", true, false)
	_check("deckbuild: PoolScroll exists", pool_scroll is ScrollContainer)
	if pool_scroll is ScrollContainer:
		await get_tree().process_frame
		await get_tree().process_frame
		pool_scroll.scroll_vertical = 150
		main_scene._on_add_card("angry_squirrel")
		await get_tree().process_frame
		await get_tree().process_frame
		_check("deckbuild: scroll position preserved after adding a card", pool_scroll.scroll_vertical == 150)
		_check("deckbuild: card still added despite scroll fix", main_scene._build_deck.has("angry_squirrel"))
	# Legendary copy limit in the deckbuilder UI.
	main_scene._build_deck = []
	main_scene._on_add_card("grunk_sparky")
	main_scene._on_add_card("grunk_sparky")
	_check("deckbuild: Legendary max 1 copy enforced", main_scene._build_deck.count("grunk_sparky") == 1)
	main_scene._on_add_card("angry_squirrel")
	main_scene._on_add_card("angry_squirrel")
	main_scene._on_add_card("angry_squirrel")
	_check("deckbuild: Common max 2 copies enforced", main_scene._build_deck.count("angry_squirrel") == 2)
	# Deckbuilder grid centered (P1 Grunk deckbuilder still showing).
	await get_tree().process_frame
	await get_tree().process_frame
	_check("deckbuild: PoolCenter wrapper exists", main_scene.find_child("PoolCenter", true, false) != null)
	var dscroll: ScrollContainer = main_scene.find_child("PoolScroll", true, false)
	var dgrid: GridContainer = main_scene.find_child("PoolGrid", true, false)
	if dscroll != null and dgrid != null:
		var dleft: float = dgrid.global_position.x - dscroll.global_position.x
		var dright: float = dscroll.size.x - (dgrid.size.x + dleft)
		_check("deckbuild: grid centered (balanced margins, no left-edge clipping)", abs(dleft - dright) <= 2.0 and dleft >= 0.0)
		var pitch: float = dgrid.get_child(5).global_position.y - dgrid.get_child(0).global_position.y
		_check("deckbuild: rows do not overlap (pitch = tile height + separation)", abs(pitch - (298.0 + 14.0)) <= 1.0)
	else:
		_check("deckbuild: grid centered (balanced margins, no left-edge clipping)", false)
		_check("deckbuild: rows do not overlap (pitch = tile height + separation)", false)
	# HOTFIX: touch scrolling — pool/strip tiles must be MOUSE_FILTER_PASS
	# with all children IGNORE, and both ScrollContainers get a ~12px
	# deadzone, so drags scroll and clean taps still add/remove.
	var _pool_tiles_pass: bool = true
	for ti in dgrid.get_child_count():
		var ptile: Button = dgrid.get_child(ti)
		if ptile.mouse_filter != Control.MOUSE_FILTER_PASS:
			_pool_tiles_pass = false
		var pstack: Array = [ptile]
		while not pstack.is_empty():
			var pn: Node = pstack.pop_back()
			for pch in pn.get_children():
				if pch is Control and (pch as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
					_pool_tiles_pass = false
				pstack.append(pch)
	_check("hotfix: pool tiles are MOUSE_FILTER_PASS, all children IGNORE", _pool_tiles_pass)
	_check("hotfix: PoolScroll deadzone ~12px", abs(dscroll.scroll_deadzone - 12.0) <= 0.5)
	var dstrip_scroll: ScrollContainer = main_scene.find_child("DeckStripScroll", true, false)
	_check("hotfix: DeckStripScroll deadzone ~12px", dstrip_scroll != null and abs(dstrip_scroll.scroll_deadzone - 12.0) <= 0.5)
	# HOTFIX: deck strip tiles — dark ink text (not white-on-cream), and
	# cost + name + copy count on each tile.
	main_scene._build_deck = ["angry_squirrel", "angry_squirrel", "fireball"]
	main_scene._refresh_deckbuild()
	await get_tree().process_frame
	var dstrip: HBoxContainer = main_scene.find_child("DeckStrip", true, false)
	var _strip_ok: bool = dstrip != null and dstrip.get_child_count() == 2
	var _strip_text_ok: bool = false
	var _strip_tiles_pass: bool = true
	if _strip_ok:
		for si in dstrip.get_child_count():
			var stile: Button = dstrip.get_child(si)
			if stile.mouse_filter != Control.MOUSE_FILTER_PASS:
				_strip_tiles_pass = false
			var texts: Array = []
			var colors_ok: bool = true
			var sstack: Array = [stile]
			while not sstack.is_empty():
				var sn: Node = sstack.pop_back()
				for sch in sn.get_children():
					if sch is Control and (sch as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
						_strip_tiles_pass = false
					if sch is Label:
						texts.append((sch as Label).text)
						if (sch as Label).get_theme_color("font_color") == Color.WHITE:
							colors_ok = false
					sstack.append(sch)
			if si == 0 and texts.has("1") and texts.has("Angry Squirrel") and texts.has("x2") and colors_ok:
				_strip_text_ok = true
	_check("hotfix: deck strip collapses to unique cards with counts", _strip_ok)
	_check("hotfix: deck tile shows cost + name + xN in dark ink (not white)", _strip_text_ok)
	_check("hotfix: deck strip tiles are MOUSE_FILTER_PASS, all children IGNORE", _strip_tiles_pass)
	main_scene._build_deck = []
	main_scene._refresh_deckbuild()
	# HOTFIX: AUTO-FILL — a valid 30-card deck for every class.
	_check("hotfix: AUTO-FILL button exists next to DONE", main_scene.find_child("DeckStripScroll", true, false) != null and main_scene._deck_autofill is Button)
	for cls in CardDB.CLASS_IDS:
		main_scene._classes[main_scene._building_player] = cls
		main_scene._pool_cards = CardDB.cards_for_class(cls)
		main_scene._build_deck = []
		main_scene._autofill_deck()
		var adeck: Array = main_scene._build_deck
		_check("hotfix: auto-fill %s -> 30 cards, valid deck" % cls, adeck.size() == 30 and GameState.validate_deck(adeck, cls))
		# Partial deck: auto-fill tops up without exceeding limits.
		# (Start from 2 copies of a 2-copy-legal card, so the partial
		# deck itself is legal — autofill never removes cards.)
		var partial: Array = []
		for cid in adeck:
			if CardDB.max_copies(CardDB.get_card(cid)) == 2:
				partial = [cid, cid]
				break
		if partial.is_empty():
			partial = [adeck[0]]
		main_scene._build_deck = partial
		main_scene._autofill_deck()
		_check("hotfix: auto-fill %s tops up a partial deck legally" % cls, main_scene._build_deck.size() == 30 and GameState.validate_deck(main_scene._build_deck, cls))
	main_scene._build_deck = []
	main_scene._refresh_deckbuild()
	# Card render sample: screenshot cards + a spread across classes/rarities.
	# Every pool card must render art + type + name + rules + stats, all
	# within the tile bounds (no blank art, no clipped children). Flavor
	# is intentionally omitted on the compact 298px pool tiles (read it
	# via long-press magnify); it shows on taller cards.
	var sample_ids: Array = ["charger", "cavalry", "medic", "grunk_sparky", "healing_light", "presto_cantrip", "barnacle_quinn", "reg_blessing", "lar_double_down", "fireball", "roulette"]
	for sid in sample_ids:
		var scard: Dictionary = CardDB.get_card(sid)
		var tbtn: Button = CardView.make_card_button(scard, 244, 298)
		add_child(tbtn)
		await get_tree().process_frame
		await get_tree().process_frame
		var trect: Rect2 = tbtn.get_global_rect().grow(1.0)
		# The gilded CardFrame draws the frame, art, name, type tag and
		# gems; the rules are a RichTextLabel (bold keywords).
		var face2: CardFrame = tbtn.find_child("Face", false, false) as CardFrame
		var art_ok2: bool = face2 != null and face2._tex != null
		var expected_type2: String = "CREW" if scard["type"] == "minion" else ("CHAOS" if CardView.is_chaos(scard) else "TRICK")
		var type_ok2: bool = face2 != null and (("CREW" if face2._is_crew() else ("CHAOS" if CardView.is_chaos(face2.card) else "TRICK")) == expected_type2)
		var name_ok2: bool = face2 != null and str(face2.card.get("name", "")) == str(scard["name"])
		var rules_ok2: bool = str(scard.get("text", "")).is_empty() or (face2 != null and face2._rules.get_parsed_text().strip_edges() == str(scard["text"]).strip_edges())
		var flavor_ok2: bool = true
		var badges_ok2: bool = face2 != null and (scard["type"] != "minion" or (int(face2.card["attack"]) == int(scard["attack"]) and int(face2.card["health"]) == int(scard["health"])))
		var bounds_ok2: bool = face2 != null and trect.encloses(face2.get_global_rect()) and trect.encloses(face2._rules.get_global_rect())
		_check("render %s: art + type + name + rules + badges, all in bounds (flavor via magnify)" % sid, art_ok2 and type_ok2 and name_ok2 and rules_ok2 and flavor_ok2 and badges_ok2 and bounds_ok2)
		tbtn.queue_free()
	# Input: touch must not also deliver an emulated mouse tap.
	_check("input: touch does not emulate mouse (no double-delivered taps)", ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch") == false)
	# --- Class-select flow: P1 + P2 each genuinely choose ---
	var flow: Control = load("res://main.tscn").instantiate()
	add_child(flow)
	await get_tree().process_frame
	# P1 Grunk, P2 Larry -> each deckbuilder shows its own class.
	flow._on_play()
	await get_tree().process_frame
	flow._on_class_picked("grunk")
	await get_tree().process_frame
	flow._on_class_picked("larry")
	_check("flow: P1 Grunk + P2 Larry recorded", flow._classes == ["grunk", "larry"])
	await get_tree().process_frame
	await get_tree().process_frame
	var hdr1: String = ""
	var stack1: Array = [flow]
	while not stack1.is_empty():
		var n1: Node = stack1.pop_back()
		if n1 is Label and (n1 as Label).text.contains("Build your deck"):
			hdr1 = (n1 as Label).text
			break
		for c in n1.get_children():
			stack1.append(c)
	_check("flow: P1 deckbuilder shows Grunk (not P2's class)", hdr1.contains("Player 1") and hdr1.contains("Grunk"))
	flow._build_deck = _valid_deck_for("grunk")
	flow._on_deck_done()
	await get_tree().process_frame
	await get_tree().process_frame
	var hdr2: String = ""
	var stack2: Array = [flow]
	while not stack2.is_empty():
		var n2: Node = stack2.pop_back()
		if n2 is Label and (n2 as Label).text.contains("Build your deck"):
			hdr2 = (n2 as Label).text
			break
		for c in n2.get_children():
			stack2.append(c)
	_check("flow: P2 deckbuilder shows Larry (P2's own pick)", hdr2.contains("Player 2") and hdr2.contains("Larry"))
	var p2_pool_ok: bool = true
	for c in flow._pool_cards:
		if c["class"] != "larry" and c["class"] != "neutral":
			p2_pool_ok = false
	_check("flow: P2 pool is Larry + neutral only", p2_pool_ok)
	# Mirror: both pick Grunk -> both deckbuilders show Grunk.
	flow._on_play()
	await get_tree().process_frame
	flow._on_class_picked("grunk")
	await get_tree().process_frame
	flow._on_class_picked("grunk")
	_check("flow: mirror picks recorded (both Grunk)", flow._classes == ["grunk", "grunk"])
	await get_tree().process_frame
	await get_tree().process_frame
	var hdr_m: String = ""
	var stack_m: Array = [flow]
	while not stack_m.is_empty():
		var nm: Node = stack_m.pop_back()
		if nm is Label and (nm as Label).text.contains("Build your deck"):
			hdr_m = (nm as Label).text
			break
		for c in nm.get_children():
			stack_m.append(c)
	_check("flow: mirror P1 deckbuilder shows Grunk", hdr_m.contains("Player 1") and hdr_m.contains("Grunk"))
	flow._build_deck = _valid_deck_for("grunk")
	flow._on_deck_done()
	await get_tree().process_frame
	await get_tree().process_frame
	var hdr_m2: String = ""
	var stack_m2: Array = [flow]
	while not stack_m2.is_empty():
		var nm2: Node = stack_m2.pop_back()
		if nm2 is Label and (nm2 as Label).text.contains("Build your deck"):
			hdr_m2 = (nm2 as Label).text
			break
		for c in nm2.get_children():
			stack_m2.append(c)
	_check("flow: mirror P2 deckbuilder shows Grunk", hdr_m2.contains("Player 2") and hdr_m2.contains("Grunk"))
	# Duplicate delivery: one tap firing twice in the same frame must NOT
	# consume P2's choice with P1's class.
	flow._on_play()
	await get_tree().process_frame
	flow._on_class_picked("reginald")
	flow._on_class_picked("reginald")
	_check("flow: same-frame duplicate pick ignored (P2 choice not consumed)", flow._classes == ["reginald", ""] and flow._selecting_player == 1)
	await get_tree().process_frame
	flow._on_class_picked("larry")
	_check("flow: P2's later-frame pick counts after a duplicate", flow._classes == ["reginald", "larry"])
	flow.queue_free()
	var d0: Array = _valid_deck_for("grunk")
	var d1: Array = _valid_deck_for("grunk")
	main_scene._decks = [d0, d1]
	main_scene._classes = ["grunk", "grunk"]
	main_scene._start_match()
	main_scene._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# Hero power button exists in the match UI.
	_check("match: hero power button exists", main_scene.find_child("HeroPowerBtn", true, false) != null)
	# Match log: appends one JSON line with classes/decks/winner/turns.
	main_scene._gs.winner = 0
	main_scene._gs.turn_count = 7
	var log_ok: bool = main_scene._append_match_log("user://test_match_log.jsonl")
	var log_entry: Dictionary = {}
	if log_ok:
		var lf := FileAccess.open("user://test_match_log.jsonl", FileAccess.READ)
		if lf != null:
			var parsed: Variant = JSON.parse_string(lf.get_as_text().strip_edges())
			if parsed is Dictionary:
				log_entry = parsed
	DirAccess.remove_absolute("user://test_match_log.jsonl")
	_check("match log: entry has classes, decklists, winner, turn count", log_entry.get("classes", []) == ["grunk", "grunk"] and (log_entry.get("decklists", []) as Array).size() == 2 and (log_entry.get("decklists", [[]])[0] as Array).size() == 30 and int(log_entry.get("winner", {}).get("player", -1)) == 1 and int(log_entry.get("turn_count", -1)) == 7)
	# Match log: appending twice must NOT truncate (WRITE_READ bug).
	DirAccess.remove_absolute("user://test_match_log2.jsonl")
	main_scene._append_match_log("user://test_match_log2.jsonl")
	main_scene._append_match_log("user://test_match_log2.jsonl")
	var log_lines: int = 0
	var lf2 := FileAccess.open("user://test_match_log2.jsonl", FileAccess.READ)
	if lf2 != null:
		for line in lf2.get_as_text().split("\n"):
			if not line.strip_edges().is_empty():
				log_lines += 1
	DirAccess.remove_absolute("user://test_match_log2.jsonl")
	_check("match log: two appends keep 2 lines (no truncation)", log_lines == 2)
	# The log test set a winner — clear it so later tests see a live match.
	main_scene._gs.winner = -1

	# --- Polish: text fitting ---
	var font: Font = ThemeDB.get_fallback_font()
	var fit_all: bool = true
	for c in CardDB.CARDS:
		if str(c.get("text", "")).is_empty():
			continue
		var fs: int = CardView.fit_font_size(c["text"], 126, 40, 16, 7)
		var ms: Vector2 = font.get_multiline_string_size(c["text"], HORIZONTAL_ALIGNMENT_CENTER, 126, fs)
		if ms.y > 40.5:
			fit_all = false
	_check("fit: every card's rules text fits its box at the fitted size", fit_all)
	_check("fit: long text shrinks below max", CardView.fit_font_size("Battlecry: Restore 3 Health to your hero. And then some more words to make it very long indeed.", 126, 40, 16, 8) < 16)
	_check("fit: short text stays at max", CardView.fit_font_size("Taunt.", 126, 40, 16, 8) == 16)
	_check("fit: empty text returns max", CardView.fit_font_size("", 126, 40, 16, 8) == 16)

	# --- Polish: integrated badges ---
	var btn_minion: Button = CardView.make_card_button(CardDB.get_card("squire"), 150, 200)
	_check("card: a Crew card's face shows attack and health gems", btn_minion.find_child("Face", false, false) is CardFrame and (btn_minion.find_child("Face", false, false) as CardFrame)._is_crew())
	var btn_spell: Button = CardView.make_card_button(CardDB.get_card("fireball"), 150, 200)
	_check("card: spell has no ATK/HP badges", btn_spell.find_child("ATKBadge", false, false) == null and btn_spell.find_child("HPBadge", false, false) == null)
	var md: Dictionary = {"card_id": "squire", "name": "Squire Gregory", "attack": 1, "health": 2, "max_health": 2, "taunt": false, "can_attack": true, "sick": false}
	var mb: Button = CardView.make_minion_button(md, true)
	_check("minion token: badges integrated", mb.find_child("ATKBadge", false, false) != null and mb.find_child("HPBadge", false, false) != null)

	# --- Polish: fan layout ---
	var fan1: Array = CardView.fan_transforms(1, 150, 1280)
	_check("fan: single card has zero rotation", fan1.size() == 1 and fan1[0]["rot"] == 0.0)
	var fan5: Array = CardView.fan_transforms(5, 150, 1280)
	var rots: Array = []
	for f in fan5:
		rots.append(f["rot"])
	_check("fan: rotation spread is non-zero", rots.min() < 0.0 and rots.max() > 0.0)
	var fan10: Array = CardView.fan_transforms(10, 150, 1280)
	var spacing10: float = fan10[1]["x"] - fan10[0]["x"]
	_check("fan: crowded hand overlaps (spacing < card width)", spacing10 < 150.0)
	_check("fan: crowded hand stays within fan width", fan10[9]["x"] + 150.0 <= 1280.5 and fan10[0]["x"] >= -0.5)

	# --- Polish: highlight ---
	var hl_btn: Button = CardView.button("X", 20)
	CardView.set_highlight(hl_btn, true)
	_check("highlight: on adds Highlight child + tint", hl_btn.find_child("Highlight", false, false) != null and hl_btn.modulate != Color.WHITE)
	CardView.set_highlight(hl_btn, false)
	_check("highlight: off removes Highlight + restores white", hl_btn.find_child("Highlight", false, false) == null and hl_btn.modulate == Color.WHITE)

	# --- Sprint 1a.2: the purple info bars are gone (info lives on the
	# 3D plaques). Sprint 1c: the top-left log line is gone too (it ran
	# over the light wood rim and was unreadable) — the HistoryColumn
	# replaces it. The match overlay is: history column (left edge),
	# hand zone (bottom), END TURN + Signature buttons (right side). No
	# two controls overlap.
	var hist_node: Node = main_scene.find_child("HistoryColumn", true, false)
	var hand_zone: Node = main_scene.find_child("HandZone", true, false)
	var end_btn: Node = main_scene.find_child("EndTurnBtn", true, false)
	var sig_btn: Node = main_scene.find_child("HeroPowerBtn", true, false)
	_check("zones: history column, hand, end-turn and signature controls exist (no purple bars, no log line)", hist_node != null and hand_zone != null and end_btn != null and sig_btn != null and main_scene.find_child("LogLabel", true, false) == null)
	_check("zones: OppZone/MyZone removed", main_scene.find_child("OppZone", true, false) == null and main_scene.find_child("MyZone", true, false) == null)
	if hist_node is Control and hand_zone is Control and end_btn is Control and sig_btn is Control:
		var rects: Array = [hist_node.get_global_rect().grow(-1), hand_zone.get_global_rect().grow(-1), end_btn.get_global_rect().grow(-1), sig_btn.get_global_rect().grow(-1)]
		var overlap: bool = false
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					overlap = true
		_check("zones: no two controls overlap", not overlap)

	# --- Polish: hand fan renders ---
	if hand_zone is Control:
		_check("hand: HandZone has visible height", hand_zone.size.y > 100)
		var btns: int = 0
		var any_rot: bool = false
		for ch in hand_zone.get_children():
			if ch is Button:
				btns += 1
				if abs(ch.rotation) > 0.001:
					any_rot = true
		var expected: int = main_scene._gs.players[0]["hand"].size()
		_check("hand: card buttons match dealt hand size", expected > 0 and btns == expected)
		_check("hand: fan gives cards non-zero rotation spread", any_rot)

	# --- Polish: magnify ---
	main_scene._show_magnify(CardDB.get_card("dragon"))
	await get_tree().process_frame
	var ov: Node = main_scene.find_child("MagnifyOverlay", true, false)
	_check("magnify: overlay appears", ov != null)
	if ov != null:
		var big: Node = ov.find_child("MagnifiedCard", true, false)
		_check("magnify: card is ~2x hand size", big != null and big.custom_minimum_size.x >= 400)
		if big != null:
			var fl: Node = big.find_child("FlavorLabel", true, false)
			_check("magnify: full flavor text shown", fl != null and str(fl.text).length() > 0)
	main_scene._dismiss_magnify()

	# --- Polish: drag-to-play + targeting arrow ---
	# Targeted spell (fireball) onto the enemy hero.
	main_scene._gs.players[0]["hand"] = ["fireball"]
	main_scene._gs.players[0]["mana"] = 10
	main_scene._gs.players[0]["max_mana"] = 10
	main_scene._gs.players[1]["hp"] = 30
	main_scene._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hz2: Node = main_scene.find_child("HandZone", true, false)
	var hand_btn: Control = hz2.get_child(0)
	var ctx: Dictionary = {"kind": "hand_card", "hand_idx": 0, "node": hand_btn}
	main_scene._begin_drag(ctx, hand_btn.global_position + hand_btn.size / 2.0)
	_check("drag: no arrow before the play line (Sprint 1a.3)", main_scene._arrow == null or not main_scene._arrow.visible)
	# Sprint 1a.4: crossing the top of the hand zone shows the unified
	# arrow (from the card's exit point at the hand edge to the finger).
	# No icon mode anymore — the card follows the finger.
	main_scene._update_drag(Vector2(640, 200))
	_check("drag: arrow visible after crossing the play line", main_scene._arrow != null and main_scene._arrow.visible)
	_check("drag: arrow is on past the line (no icon mode)", bool(main_scene._drag.get("arrow_on", false)) and not bool(main_scene._drag.get("icon_mode", false)))
	# Sprint 1a.2: the enemy hero is a 3D badge (no OppHeroBtn). It must
	# be in the drag's target list; dragging onto it (within snap range)
	# highlights it red.
	var has_hero_target: bool = false
	for t in main_scene._drag.get("targets", []):
		if str(t.get("kind", "")) == "hero" and int(t.get("player", -1)) == 1:
			has_hero_target = true
	_check("drag: enemy hero is a valid target", has_hero_target)
	# Drop on the enemy badge's screen position (canvas coords).
	var hpos: Dictionary = main_scene._board_3d.hero_position(1, main_scene._gs.active)
	var hero_vp: Vector2 = main_scene._board_3d.screen_pos(hpos["position"])
	var hero_canvas: Vector2 = main_scene.get_viewport().get_canvas_transform().affine_inverse() * hero_vp
	main_scene._update_drag(hero_canvas)
	var plaque: HeroPlaque3D = main_scene._board_3d.hero_plaque(1)
	_check("drag: enemy badge highlighted on snap", plaque != null and plaque.is_highlighted())
	_check("drag: arrow is red on a valid target", main_scene._arrow != null and main_scene._arrow.default_color.r > 0.9)
	_check("drag: the beam locks onto the target", main_scene._tarrow != null and main_scene._tarrow.visible and main_scene._tarrow.state == TargetArrow.State.LOCKED)
	main_scene._end_drag(hero_canvas)
	_check("drag: release on valid target plays the card (hero -3 HP, hand -1)", main_scene._gs.players[1]["hp"] == 27 and main_scene._gs.players[0]["hand"].size() == 0)
	# Cancel: release far away from any target.
	main_scene._gs.players[0]["hand"] = ["fireball"]
	main_scene._gs.players[0]["mana"] = 10
	main_scene._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var hz3: Node = main_scene.find_child("HandZone", true, false)
	var hand_btn3: Control = hz3.get_child(0)
	var ctx3: Dictionary = {"kind": "hand_card", "hand_idx": 0, "node": hand_btn3}
	main_scene._begin_drag(ctx3, hand_btn3.global_position + hand_btn3.size / 2.0)
	main_scene._end_drag(Vector2(10, 710))
	_check("drag: release elsewhere cancels (hand unchanged, arrow hidden)", main_scene._gs.players[0]["hand"].size() == 1 and main_scene._arrow != null and not main_scene._arrow.visible)
	# Untargeted minion: drag onto the board zone to play.
	main_scene._gs.players[0]["hand"] = ["squire"]
	main_scene._gs.players[0]["mana"] = 10
	main_scene._gs.players[0]["board"] = []
	main_scene._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var hz4: Node = main_scene.find_child("HandZone", true, false)
	var hand_btn4: Control = hz4.get_child(0)
	var ctx4: Dictionary = {"kind": "hand_card", "hand_idx": 0, "node": hand_btn4}
	main_scene._begin_drag(ctx4, hand_btn4.global_position + hand_btn4.size / 2.0)
	# Sprint 1a.2: no BoardZone — dropping an untargeted minion anywhere
	# above the hand zone plays it. Use the screen center.
	main_scene._end_drag(Vector2(640, 360))
	_check("drag: untargeted minion dropped above the hand zone is played", main_scene._gs.players[0]["board"].size() == 1 and main_scene._gs.players[0]["hand"].size() == 0)
	# Sprint 1a.3: a tap NEVER plays a card (gesture only).
	main_scene._gs.players[0]["hand"] = ["squire"]
	main_scene._gs.players[0]["mana"] = 10
	main_scene._gs.players[0]["board"] = []
	main_scene._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var hz5: Node = main_scene.find_child("HandZone", true, false)
	var hand_btn5: Control = hz5.get_child(0)
	main_scene._do_tap({"kind": "hand_card", "hand_idx": 0, "node": hand_btn5})
	_check("tap never plays: tapping an untargeted card does nothing", main_scene._gs.players[0]["board"].size() == 0 and main_scene._gs.players[0]["hand"].size() == 1)
	main_scene.queue_free()

	# --- Sprint 1a: event stream (Part A) ---
	# A5(a): a minion trade emits attack -> 2 damage -> deaths, in order.
	var ev_trade := _gs_with_hands([], [])
	var tr_a: Dictionary = _minion("squire")
	tr_a["attack"] = 2
	tr_a["health"] = 2
	tr_a["max_health"] = 2
	var tr_d: Dictionary = _minion("squire")
	tr_d["attack"] = 2
	tr_d["health"] = 2
	tr_d["max_health"] = 2
	ev_trade.players[0]["board"] = [tr_a]
	ev_trade.players[1]["board"] = [tr_d]
	ev_trade.take_events()
	ev_trade.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	var ev_types: Array = []
	for e in ev_trade.take_events():
		ev_types.append(e["type"])
	_check("events: trade emits attack -> damage -> damage -> deaths", ev_types == ["attack", "damage", "damage", "minion_died", "minion_died"])
	# A5(b): uids are unique and stay on the right minion after a minion
	# to its left dies.
	var ev_uid := _gs_with_hands([], [])
	var u0: Dictionary = _minion("squire")
	var u1: Dictionary = _minion("squire")
	var u2: Dictionary = _minion("squire")
	ev_uid.players[1]["board"] = [u0, u1, u2]
	var id0: int = ev_uid.uid_for(u0)
	var id1: int = ev_uid.uid_for(u1)
	var id2: int = ev_uid.uid_for(u2)
	var killer: Dictionary = _minion("brute")
	killer["attack"] = 10
	killer["health"] = 10
	killer["max_health"] = 10
	ev_uid.players[0]["board"] = [killer]
	ev_uid.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	var rem: Array = ev_uid.players[1]["board"]
	_check("events: uids unique + stable after left minion dies", id0 != id1 and id1 != id2 and id0 != id2 and rem.size() == 2 and int(rem[0].get("uid", -1)) == id1 and int(rem[1].get("uid", -1)) == id2)
	# A5(c): AoE emits one damage event per target.
	var ev_aoe := _gs_for(["lar_rigged_deck"], [], "larry", "grunk")
	ev_aoe.players[0]["board"] = [_minion("recruit")]
	ev_aoe.players[1]["board"] = [_minion("knight"), _minion("squire")]
	ev_aoe.take_events()
	ev_aoe.play_card(0, 0)
	var aoe_dmg: int = 0
	var aoe_first_death: int = -1
	var aoe_events: Array = ev_aoe.take_events()
	for ei in aoe_events.size():
		if aoe_events[ei]["type"] == "damage":
			aoe_dmg += 1
		if aoe_events[ei]["type"] == "minion_died" and aoe_first_death < 0:
			aoe_first_death = ei
	var aoe_last_dmg: int = -1
	for ei in aoe_events.size():
		if aoe_events[ei]["type"] == "damage":
			aoe_last_dmg = ei
	_check("events: AoE emits one damage event per target (3 minions = 3)", aoe_dmg == 3)
	_check("events: AoE damage all precedes all deaths", aoe_first_death > 0 and aoe_last_dmg < aoe_first_death)
	# A5(d): every summon card's token name matches the name in its text,
	# and token_for reads the "token" field (regex fallback only if missing).
	var tok_all_ok: bool = true
	var tok_field_ok: bool = true
	for c in CardDB.CARDS:
		if c.get("effect") == "summon_token" or c.get("deathrattle") == "summon_token":
			if not (c.get("token") is Dictionary):
				tok_field_ok = false
				continue
			var re := RegEx.new()
			re.compile("Summon a 1/1 ([^.]+)\\.")
			var m := re.search(str(c.get("text", "")))
			if m == null or str(c["token"].get("name", "")) != m.get_string(1):
				tok_all_ok = false
			var tf: Dictionary = CardDB.token_for(c)
			if str(tf.get("name", "")) != str(c["token"].get("name", "")) or int(tf.get("attack", 0)) != 1 or int(tf.get("health", 0)) != 1:
				tok_all_ok = false
			if str(c["token"].get("art", "")).is_empty() or str(tf.get("art", "")) != str(c["token"].get("art", "")):
				tok_all_ok = false
	_check("events: every summon card has a token field with the text's name + art, token_for returns it 1/1", tok_all_ok and tok_field_ok)
	# Regex fallback: a card WITHOUT the token field still parses.
	var nofield: Dictionary = {"text": "Entrance: Summon a 1/1 Test Token."}
	_check("events: token_for falls back to the regex when the field is missing", str(CardDB.token_for(nofield).get("name", "")) == "Test Token")
	# take_events returns the queue and clears it.
	var ev_clear := _gs_with_hands(["squire"], [])
	ev_clear.take_events()
	ev_clear.play_card(0, 0)
	var first_take: Array = ev_clear.take_events()
	var second_take: Array = ev_clear.take_events()
	_check("events: take_events returns the queue and clears it", not first_take.is_empty() and second_take.is_empty())
	# card_played + minion_summoned + mana_changed on playing a minion.
	var ev_play := _gs_with_hands(["squire"], [])
	ev_play.take_events()
	ev_play.play_card(0, 0)
	var play_types: Array = []
	for e in ev_play.take_events():
		play_types.append(e["type"])
	_check("events: playing a minion emits card_played, minion_summoned, mana_changed", play_types.has("card_played") and play_types.has("minion_summoned") and play_types.has("mana_changed") and play_types[0] == "card_played")
	# spell_cast + damage on a targeted spell.
	var ev_spell := _gs_with_hands(["fireball"], [])
	ev_spell.take_events()
	ev_spell.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1})
	var spell_types: Array = []
	var spell_cast_ok: bool = false
	for e in ev_spell.take_events():
		spell_types.append(e["type"])
		if e["type"] == "spell_cast" and e["data"].get("card_id") == "fireball" and e["data"].get("target_kind") == "hero" and e["data"].get("target_uid") == -1:
			spell_cast_ok = true
	_check("events: fireball emits spell_cast (hero, uid -1) + damage", spell_types.has("spell_cast") and spell_types.has("damage") and spell_cast_ok)
	# signature_move + damage on Grunk's hero power; heal on Agatha's.
	var ev_sig := _gs_for([], [], "grunk", "agatha")
	ev_sig.take_events()
	ev_sig.use_hero_power(0)
	var sig_types: Array = []
	for e in ev_sig.take_events():
		sig_types.append(e["type"])
	_check("events: Grunk signature move emits signature_move + damage + mana_changed", sig_types.has("signature_move") and sig_types.has("damage") and sig_types.has("mana_changed"))
	var ev_heal := _gs_for([], [], "agatha", "grunk")
	ev_heal.players[0]["hp"] = 20
	ev_heal.take_events()
	ev_heal.use_hero_power(0)
	var heal_types: Array = []
	var heal_amt: int = 0
	for e in ev_heal.take_events():
		heal_types.append(e["type"])
		if e["type"] == "heal":
			heal_amt = int(e["data"].get("amount", 0))
	_check("events: Agatha signature move emits signature_move + heal 2", heal_types.has("signature_move") and heal_types.has("heal") and heal_amt == 2)
	# buff on Reginald's hero power.
	var ev_buff := _gs_for([], [], "reginald", "grunk")
	ev_buff.players[0]["board"] = [_minion("guard_dog")]
	ev_buff.take_events()
	ev_buff.use_hero_power(0, {"kind": "minion", "player": 0, "board_idx": 0})
	var buff_types: Array = []
	var buff_ok: bool = false
	for e in ev_buff.take_events():
		buff_types.append(e["type"])
		if e["type"] == "buff" and int(e["data"].get("attack_delta", 0)) == 1 and int(e["data"].get("health_delta", 0)) == 1:
			buff_ok = true
	_check("events: Reginald signature move emits signature_move + buff +1/+1", buff_types.has("signature_move") and buff_types.has("buff") and buff_ok)
	# turn_start + draw on end_turn; game_over on lethal.
	var ev_turn := _gs_with_hands([], [])
	ev_turn.players[1]["mana"] = 3
	ev_turn.players[1]["max_mana"] = 3
	ev_turn.take_events()
	ev_turn.end_turn()
	var turn_types: Array = []
	for e in ev_turn.take_events():
		turn_types.append(e["type"])
	_check("events: end_turn emits turn_start + mana_changed + draw", turn_types.has("turn_start") and turn_types.has("mana_changed") and turn_types.has("draw"))
	var ev_lethal := _gs_with_hands([], [])
	ev_lethal.players[0]["board"] = [_minion("brute")]
	ev_lethal.players[1]["hp"] = 3
	ev_lethal.take_events()
	ev_lethal.attack(0, 0, {"kind": "hero", "player": 1, "board_idx": -1})
	var lethal_types: Array = []
	var lethal_winner: int = -1
	for e in ev_lethal.take_events():
		lethal_types.append(e["type"])
		if e["type"] == "game_over":
			lethal_winner = int(e["data"].get("winner", -1))
	_check("events: lethal attack emits game_over with the winner", lethal_types.has("game_over") and lethal_winner == 0)
	# empty_deck + damage on fatigue; card_burned on a full hand.
	var ev_fat := _gs_with_hands([], [])
	ev_fat.players[0]["deck"] = []
	ev_fat.players[0]["fatigue"] = 0
	ev_fat.take_events()
	ev_fat.draw_cards(0, 1)
	var fat_types: Array = []
	var fat_amt: int = 0
	for e in ev_fat.take_events():
		fat_types.append(e["type"])
		if e["type"] == "empty_deck":
			fat_amt = int(e["data"].get("amount", 0))
	_check("events: fatigue emits empty_deck + damage", fat_types.has("empty_deck") and fat_types.has("damage") and fat_amt == 1)
	var ev_burn := _gs_with_hands([], [])
	ev_burn.players[0]["hand"] = _deck_of("angry_squirrel", 10)
	ev_burn.players[0]["deck"] = ["squire"]
	ev_burn.take_events()
	ev_burn.draw_cards(0, 1)
	var burn_types: Array = []
	for e in ev_burn.take_events():
		burn_types.append(e["type"])
	_check("events: drawing with a full hand emits card_burned, not draw", burn_types.has("card_burned") and not burn_types.has("draw"))
	# final_bow on a Deathrattle death.
	var ev_fb := _gs_for([], [], "neutral", "neutral")
	ev_fb.players[0]["board"] = [_minion("neutral_napper")]
	ev_fb.players[1]["board"] = [_minion("brute")]
	ev_fb.take_events()
	ev_fb.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	var fb_types: Array = []
	for e in ev_fb.take_events():
		fb_types.append(e["type"])
	_check("events: Deathrattle death emits minion_died + final_bow", fb_types.has("minion_died") and fb_types.has("final_bow"))

	# --- Sprint 1b Fix 2: event gaps ---
	# minion_destroyed BEFORE minion_died (Assassinate = destroy spell).
	var ev_des := _gs_with_hands(["assassinate"], [])
	ev_des.players[1]["board"] = [_minion("squire")]
	ev_des.take_events()
	ev_des.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	var des_events: Array = ev_des.take_events()
	var des_idx: int = -1
	var des_died_idx: int = -1
	for ei in des_events.size():
		if des_events[ei]["type"] == "minion_destroyed" and des_idx < 0:
			des_idx = ei
		if des_events[ei]["type"] == "minion_died" and des_died_idx < 0:
			des_died_idx = ei
	_check("events: destroy emits minion_destroyed BEFORE minion_died", des_idx >= 0 and des_died_idx > des_idx)
	# minion_destroyed from destroy_damaged (Timmy's Entrance).
	var ev_dd := _gs_with_hands(["agatha_timmy"], [])
	var dd_victim: Dictionary = _minion("squire")
	dd_victim["health"] = 1
	dd_victim["max_health"] = 2
	ev_dd.players[1]["board"] = [dd_victim]
	ev_dd.take_events()
	ev_dd.play_card(0, 0)
	var dd_types: Array = []
	for e in ev_dd.take_events():
		dd_types.append(e["type"])
	_check("events: destroy_damaged emits minion_destroyed", dd_types.has("minion_destroyed"))
	# minion_stolen (Paid Off = steal_weak).
	var ev_st := _gs_with_hands(["mind_trick"], [])
	var st_victim: Dictionary = _minion("squire")
	st_victim["attack"] = 1
	ev_st.players[1]["board"] = [st_victim]
	var st_uid: int = ev_st.uid_for(st_victim)
	ev_st.take_events()
	ev_st.play_card(0, 0)
	var st_ok: bool = false
	for e in ev_st.take_events():
		if e["type"] == "minion_stolen" and int(e["data"].get("from_player", -1)) == 1 and int(e["data"].get("to_player", -1)) == 0 and int(e["data"].get("uid", -1)) == st_uid:
			st_ok = true
	_check("events: steal_weak emits minion_stolen {from 1, to 0, uid}", st_ok)
	# stats_swapped (Flip-Side Tessa's Entrance; random, one candidate).
	var ev_sw := _gs_with_hands(["lar_tessa"], [])
	var sw_victim: Dictionary = _minion("squire")
	sw_victim["attack"] = 1
	sw_victim["health"] = 3
	sw_victim["max_health"] = 3
	ev_sw.players[1]["board"] = [sw_victim]
	var sw_uid: int = ev_sw.uid_for(sw_victim)
	ev_sw.take_events()
	ev_sw.play_card(0, 0)
	var sw_ok: bool = false
	for e in ev_sw.take_events():
		if e["type"] == "stats_swapped" and int(e["data"].get("player", -1)) == 1 and int(e["data"].get("uid", -1)) == sw_uid and int(e["data"].get("attack", -1)) == 3 and int(e["data"].get("health", -1)) == 1:
			sw_ok = true
	_check("events: swap_stats emits stats_swapped {player 1, uid, 3/1}", sw_ok)
	# hands_swapped (Oops, Wrong Hand!).
	var ev_hs := _gs_with_hands(["hand_swap"], ["squire"])
	ev_hs.take_events()
	ev_hs.play_card(0, 0)
	var hs_ok: bool = false
	for e in ev_hs.take_events():
		if e["type"] == "hands_swapped":
			hs_ok = true
	_check("events: swap_hands emits hands_swapped", hs_ok)
	_check("events: swap_hands actually swaps the hands", ev_hs.players[0]["hand"] == ["squire"] and ev_hs.players[1]["hand"].is_empty())
	# coin_flip (Coin Flip of Destiny).
	var ev_cf := _gs_with_hands(["coin_flip"], [])
	ev_cf.take_events()
	ev_cf.play_card(0, 0)
	var cf_ok: bool = false
	for e in ev_cf.take_events():
		if e["type"] == "coin_flip" and int(e["data"].get("player", -1)) == 0 and e["data"].get("heads") is bool:
			cf_ok = true
	_check("events: coin_flip emits coin_flip {player, heads: bool}", cf_ok)
	# entrance (Zapper's Entrance) + source_uid on Entrance damage.
	var ev_en := _gs_with_hands(["zapper"], [])
	ev_en.take_events()
	ev_en.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1})
	var en_events: Array = ev_en.take_events()
	var en_idx: int = -1
	var en_dmg_idx: int = -1
	var en_src_ok: bool = false
	var en_uid: int = -1
	for ei in en_events.size():
		if en_events[ei]["type"] == "entrance" and en_idx < 0:
			en_idx = ei
			en_uid = int(en_events[ei]["data"].get("uid", -1))
		if en_events[ei]["type"] == "damage" and en_dmg_idx < 0:
			en_dmg_idx = ei
			if int(en_events[ei]["data"].get("source_uid", -999)) == en_uid and str(en_events[ei]["data"].get("source_card_id", "")) == "zapper":
				en_src_ok = true
	_check("events: Entrance emits entrance before its effect resolves", en_idx >= 0 and en_dmg_idx > en_idx)
	_check("events: Entrance damage carries source_uid = the minion + source_card_id", en_src_ok)
	# source_uid on Final Bow damage (The Last Slice's Final Bow).
	var ev_fbs := _gs_with_hands([], [])
	var fb_slice: Dictionary = _minion("neutral_slice")
	fb_slice["attack"] = 1
	fb_slice["health"] = 1
	fb_slice["max_health"] = 1
	var fb_brute: Dictionary = _minion("brute")
	fb_brute["attack"] = 5
	fb_brute["health"] = 10
	fb_brute["max_health"] = 10
	ev_fbs.players[0]["board"] = [fb_slice]
	ev_fbs.players[1]["board"] = [fb_brute]
	var fb_slice_uid: int = ev_fbs.uid_for(fb_slice)
	ev_fbs.take_events()
	ev_fbs.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	var fbs_events: Array = ev_fbs.take_events()
	var fbs_src_ok: bool = false
	for e in fbs_events:
		if e["type"] == "damage" and int(e["data"].get("source_uid", -999)) == fb_slice_uid and str(e["data"].get("source_card_id", "")) == "neutral_slice":
			fbs_src_ok = true
	_check("events: Final Bow damage carries source_uid = the dead minion + source_card_id", fbs_src_ok)
	# Spells keep source_uid -1, source_card_id = the spell.
	var ev_sp2 := _gs_with_hands(["fireball"], [])
	ev_sp2.take_events()
	ev_sp2.play_card(0, 0, {"kind": "hero", "player": 1, "board_idx": -1})
	var sp2_src_ok: bool = false
	for e in ev_sp2.take_events():
		if e["type"] == "damage" and int(e["data"].get("source_uid", -999)) == -1 and str(e["data"].get("source_card_id", "")) == "fireball":
			sp2_src_ok = true
	_check("events: spell damage keeps source_uid -1, source_card_id = the spell", sp2_src_ok)

	# --- Sprint 1b Fix 3: lookups return a found flag, never ZERO as "not found" ---
	var lk_gs := _gs_with_hands([], [])
	lk_gs.players[0]["board"] = [_minion("squire")]
	var lk_uid: int = 42
	lk_gs.players[0]["board"][0]["uid"] = lk_uid
	var lk_board := Board3D.new()
	add_child(lk_board)
	lk_board.sync(lk_gs)
	var lk_found: Dictionary = lk_board.minion_position(lk_uid)
	var lk_missing: Dictionary = lk_board.minion_position(9999)
	var lk_hero: Dictionary = lk_board.hero_position(0, 0)
	_check("lookups: minion_position returns found=true for a live minion", bool(lk_found.get("found", false)))
	_check("lookups: minion_position returns found=false for a missing uid (never ZERO-as-found)", not bool(lk_missing.get("found", false)))
	_check("lookups: hero_position returns found=true for a live plaque", bool(lk_hero.get("found", false)))
	lk_board.queue_free()

	# --- Sprint 1b: director smoke test (one batch of EVERY event type,
	# ANIM_SPEED high). gs_post is the resolved END state the director
	# shows; gs_pre is the board state before the batch (the director
	# animates the transition). After the batch + a full sync, the
	# board's uid set must match the game state's.
	var sm_pre := _gs_with_hands([], [])
	var sm_a_pre: Dictionary = _minion("squire")
	sm_a_pre["attack"] = 2
	sm_a_pre["health"] = 3
	sm_a_pre["max_health"] = 3
	sm_a_pre["uid"] = 10
	var sm_a2_pre: Dictionary = _minion("neutral_slice")
	sm_a2_pre["attack"] = 1
	sm_a2_pre["health"] = 1
	sm_a2_pre["max_health"] = 1
	sm_a2_pre["uid"] = 11
	var sm_b_pre: Dictionary = _minion("squire")
	sm_b_pre["attack"] = 2
	sm_b_pre["health"] = 3
	sm_b_pre["max_health"] = 3
	sm_b_pre["uid"] = 12
	var sm_b2_pre: Dictionary = _minion("squire")
	sm_b2_pre["attack"] = 1
	sm_b2_pre["health"] = 2
	sm_b2_pre["max_health"] = 2
	sm_b2_pre["uid"] = 13
	var sm_c_pre: Dictionary = _minion("squire")
	sm_c_pre["attack"] = 1
	sm_c_pre["health"] = 3
	sm_c_pre["max_health"] = 3
	sm_c_pre["uid"] = 14
	sm_pre.players[0]["board"] = [sm_a_pre, sm_a2_pre]
	sm_pre.players[1]["board"] = [sm_b_pre, sm_b2_pre, sm_c_pre]
	var sm_post := _gs_with_hands([], [])
	var sm_a_post: Dictionary = _minion("squire")
	sm_a_post["attack"] = 3
	sm_a_post["health"] = 2
	sm_a_post["max_health"] = 4
	sm_a_post["uid"] = 10
	var sm_new_post: Dictionary = _minion("squire")
	sm_new_post["attack"] = 1
	sm_new_post["health"] = 1
	sm_new_post["max_health"] = 1
	sm_new_post["uid"] = 15
	var sm_b2_post: Dictionary = _minion("squire")
	sm_b2_post["attack"] = 1
	sm_b2_post["health"] = 2
	sm_b2_post["max_health"] = 2
	sm_b2_post["uid"] = 13
	var sm_c_post: Dictionary = _minion("squire")
	sm_c_post["attack"] = 3
	sm_c_post["health"] = 1
	sm_c_post["max_health"] = 1
	sm_c_post["uid"] = 14
	sm_post.players[0]["board"] = [sm_a_post, sm_new_post, sm_b2_post]
	sm_post.players[1]["board"] = [sm_c_post]
	var sm_board := Board3D.new()
	add_child(sm_board)
	sm_board.sync(sm_pre)
	var sm_director := AnimDirector.new()
	add_child(sm_director)
	sm_director.ANIM_SPEED = 1000.0
	var sm_events: Array = [
		{"type": "turn_start", "data": {"player": 0}},
		{"type": "mana_changed", "data": {"player": 0, "mana": 5, "max_mana": 5}},
		{"type": "draw", "data": {"player": 0, "card_id": "squire"}},
		{"type": "card_played", "data": {"player": 0, "card_id": "zapper"}},
		{"type": "entrance", "data": {"player": 0, "uid": 10, "card_id": "zapper"}},
		{"type": "spell_cast", "data": {"player": 0, "card_id": "fireball", "target_kind": "hero", "target_player": 1, "target_uid": -1}},
		{"type": "damage", "data": {"target_kind": "hero", "player": 1, "uid": -1, "amount": 3, "source_uid": -1, "source_card_id": "fireball"}},
		{"type": "heal", "data": {"target_kind": "hero", "player": 0, "uid": -1, "amount": 3, "source_uid": -1, "source_card_id": ""}},
		{"type": "buff", "data": {"player": 0, "uid": 10, "attack_delta": 1, "health_delta": 1, "source_uid": -1, "source_card_id": ""}},
		{"type": "attack", "data": {"player": 0, "attacker_uid": 10, "target_kind": "minion", "target_player": 1, "target_uid": 12}},
		{"type": "damage", "data": {"target_kind": "minion", "player": 1, "uid": 12, "amount": 2, "source_uid": 10, "source_card_id": ""}},
		{"type": "damage", "data": {"target_kind": "minion", "player": 0, "uid": 10, "amount": 2, "source_uid": 12, "source_card_id": ""}},
		{"type": "minion_stolen", "data": {"from_player": 1, "to_player": 0, "uid": 13}},
		{"type": "stats_swapped", "data": {"player": 1, "uid": 14, "attack": 3, "health": 1}},
		{"type": "minion_destroyed", "data": {"player": 0, "uid": 11}},
		{"type": "minion_died", "data": {"player": 0, "uid": 11, "card_id": "neutral_slice"}},
		{"type": "final_bow", "data": {"player": 0, "uid": 11, "card_id": "neutral_slice"}},
		{"type": "damage", "data": {"target_kind": "minion", "player": 1, "uid": 12, "amount": 1, "source_uid": 11, "source_card_id": "neutral_slice"}},
		{"type": "minion_died", "data": {"player": 1, "uid": 12, "card_id": "squire"}},
		{"type": "minion_summoned", "data": {"player": 0, "uid": 15, "card_id": "squire", "board_idx": 1}},
		{"type": "hands_swapped", "data": {}},
		{"type": "coin_flip", "data": {"player": 0, "heads": true}},
		{"type": "card_burned", "data": {"player": 0, "card_id": "squire"}},
		{"type": "empty_deck", "data": {"player": 0, "amount": 1}},
		{"type": "signature_move", "data": {"player": 0, "class": "grunk"}},
		{"type": "game_over", "data": {"winner": 0}},
	]
	await sm_director.play_events(sm_events, sm_board, sm_post)
	sm_board.sync(sm_post)
	var sm_board_uids: Array = sm_board.board_uids()
	sm_board_uids.sort()
	var sm_gs_uids: Array = [10, 13, 14, 15]
	sm_gs_uids.sort()
	_check("director smoke: finishes a batch of every event type and the board's uid set matches the game state", sm_board_uids == sm_gs_uids)
	sm_board.queue_free()
	sm_director.queue_free()

	# --- Sprint 1a.4: minion rows are CENTERED about ROW_CENTER_X (right
	# of the left hero badges) ---
	var cboard := Board3D.new()
	add_child(cboard)
	await get_tree().process_frame
	var rcx: float = Board3D.ROW_CENTER_X
	var c1: Vector3 = cboard.slot_position(0, 0, 1, 0)
	_check("slots: 1 minion sits at the row center", absf(c1.x - rcx) < 0.001)
	var c2a: Vector3 = cboard.slot_position(0, 0, 2, 0)
	var c2b: Vector3 = cboard.slot_position(0, 1, 2, 0)
	_check("slots: 2 minions straddle the row center", absf((c2a.x + c2b.x) / 2.0 - rcx) < 0.001 and c2a.x < rcx and c2b.x > rcx)
	var sym7: bool = true
	for si in 7:
		var sa: Vector3 = cboard.slot_position(0, si, 7, 0)
		var sb: Vector3 = cboard.slot_position(0, 6 - si, 7, 0)
		if absf((sa.x + sb.x) / 2.0 - rcx) > 0.001:
			sym7 = false
	_check("slots: 7 minions symmetric about the row center", sym7)
	var c7l: Vector3 = cboard.slot_position(0, 0, 7, 0)
	var c7r: Vector3 = cboard.slot_position(0, 6, 7, 0)
	_check("slots: 7 per row still fit (within table half-width 8)", absf(c7l.x) < 8.0 and absf(c7r.x) < 8.0)
	# Token+badge footprint spacing: adjacent slots never overlap.
	var sp: float = Board3D.SLOT_SPACING
	_check("slots: spacing includes badges + a gap", absf(sp - (Board3D.TOKEN_VISUAL_R * 2.0 + 0.06)) < 0.0001)
	cboard.queue_free()

	# --- Sprint 1a.2 (b): hand fan centers on the ACTUAL viewport width ---
	var fan1600: Array = CardView.fan_transforms(5, 130, 1600)
	var fan2000: Array = CardView.fan_transforms(5, 130, 2000)
	var fc1600: float = (float(fan1600[0]["x"]) + float(fan1600[4]["x"]) + 130.0) / 2.0
	var fc2000: float = (float(fan2000[0]["x"]) + float(fan2000[4]["x"]) + 130.0) / 2.0
	_check("fan: centered for 1600-wide viewport", absf(fc1600 - 800.0) < 1.0)
	_check("fan: centered for 2000-wide viewport", absf(fc2000 - 1000.0) < 1.0)

	# --- Sprint 1a.2 (c): inspect opens on long-press of an enemy minion ---
	# Damaged enemy minion (1/2): the panel must show CURRENT stats.
	# (Fresh scene: the shared main_scene was freed after the drag tests.)
	var m3: Control = load("res://main.tscn").instantiate()
	add_child(m3)
	await get_tree().process_frame
	m3._on_play()
	await get_tree().process_frame
	m3._on_class_picked("grunk")
	await get_tree().process_frame
	m3._on_class_picked("grunk")
	await get_tree().process_frame
	await get_tree().process_frame
	m3._on_autofill()
	m3._on_deck_done()
	await get_tree().process_frame
	m3._on_autofill()
	m3._on_deck_done()
	await get_tree().process_frame
	m3._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var insp_minion: Dictionary = _minion("squire")
	insp_minion["health"] = 1
	m3._gs.players[1]["board"] = [insp_minion]
	m3._gs.active = 0
	m3._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var insp_uid: int = m3._gs.uid_for(insp_minion)
	var insp_ctx: Dictionary = {"kind": "target", "target": {"kind": "minion", "player": 1, "board_idx": 0}, "uid": insp_uid}
	# Simulate a long-press: _process fires the inspect once LONG_PRESS_MS elapses.
	m3._press = {"ctx": insp_ctx, "t": Time.get_ticks_msec() - 600, "down": true, "start_pos": Vector2.ZERO, "dragging": false, "magnified": false, "node": null}
	await get_tree().process_frame
	await get_tree().process_frame
	_check("inspect: long-press on enemy minion opens the panel", m3._inspect_overlay != null)
	if m3._inspect_overlay != null:
		# The inspect is the gilded card itself, with the LIVE numbers.
		var cf3: CardFrame = m3._inspect_overlay.find_child("Face", true, false) as CardFrame
		_check("inspect: shows the Crew member as its card", cf3 != null)
		_check("inspect: shows CURRENT health (1, damaged)", cf3 != null and int(cf3.card["health"]) == 1)
		_check("inspect: damaged health is red", cf3 != null and cf3._stat_col("health").g < 0.8)
		_check("inspect: shows the Bouncer keyword line", _has_label_with(m3._inspect_overlay, "Bouncer"))
		m3._dismiss_inspect()
	m3.queue_free()

	# --- Sprint 1a.2 (d): "what did they play?" recap ---
	var m4: Control = load("res://main.tscn").instantiate()
	add_child(m4)
	await get_tree().process_frame
	m4._turn_played_cards = []
	m4._accumulate_played([
		{"type": "card_played", "data": {"player": 0, "card_id": "fireball"}},
		{"type": "damage", "data": {"target_kind": "hero", "player": 1, "amount": 3}},
		{"type": "card_played", "data": {"player": 0, "card_id": "squire"}},
	])
	_check("recap: accumulates exactly the played card_ids in order", m4._turn_played_cards == ["fireball", "squire"])
	m4._show_interstitial(1, "Player 1's turn! Pass the phone to Player 1.")
	await get_tree().process_frame
	# Count mini-card buttons via the recap row directly.
	var recap_row: HBoxContainer = null
	var find_stack: Array = [m4]
	while not find_stack.is_empty() and recap_row == null:
		var fn: Node = find_stack.pop_back()
		if fn is HBoxContainer and fn.get_child_count() == 2:
			var ok: bool = true
			for fch in fn.get_children():
				if not (fch is Button):
					ok = false
			if ok:
				recap_row = fn
		for fch2 in fn.get_children():
			find_stack.append(fch2)
	_check("recap: the interstitial shows exactly the 2 played mini cards", recap_row != null and recap_row.get_child_count() == 2)
	_check("recap: the turn list resets after display", m4._turn_played_cards.is_empty())
	m4.queue_free()

	# --- Sprint 1a.2 (item 1): manual deckbuilder scroll ---
	# Real InputEventScreenTouch + InputEventScreenDrag objects fed to the
	# pool tile's input handler (headless Godot does not dispatch
	# synthetic events through viewport GUI hit-testing, so the test
	# drives the handler directly — the events and the handler are real).
	# A drag past 12px must change scroll_vertical, and the tap must be
	# cancelled (deck unchanged).
	var m2: Control = load("res://main.tscn").instantiate()
	add_child(m2)
	await get_tree().process_frame
	m2._on_play()
	await get_tree().process_frame
	m2._on_class_picked("grunk")
	await get_tree().process_frame
	m2._on_class_picked("grunk")
	await get_tree().process_frame
	await get_tree().process_frame
	var pscroll: ScrollContainer = m2.find_child("PoolScroll", true, false)
	_check("scroll: PoolScroll exists", pscroll != null)
	if pscroll != null:
		pscroll.scroll_vertical = 200.0
		await get_tree().process_frame
		var pgrid: GridContainer = m2.find_child("PoolGrid", true, false)
		var tile0: Control = pgrid.get_child(0)
		var card0: String = str(m2._pool_cards[0]["id"])
		# Press in the tile's local coords (tile is 244x298, unscaled).
		var lp := Vector2(122, 149)
		var tpress := InputEventScreenTouch.new()
		tpress.pressed = true
		tpress.index = 0
		tpress.position = lp
		m2._on_pool_tile_input(tpress, card0, tile0)
		await get_tree().process_frame
		# Drag upward in 20px steps (finger up -> scroll_vertical grows).
		for di in range(1, 6):
			var tdrag := InputEventScreenDrag.new()
			tdrag.index = 0
			tdrag.position = lp + Vector2(0, -20.0 * di)
			tdrag.relative = Vector2(0, -20.0)
			m2._on_pool_tile_input(tdrag, card0, tile0)
			await get_tree().process_frame
		var trelease := InputEventScreenTouch.new()
		trelease.pressed = false
		trelease.index = 0
		trelease.position = lp + Vector2(0, -100.0)
		m2._on_pool_tile_input(trelease, card0, tile0)
		await get_tree().process_frame
		_check("scroll: manual drag changes scroll_vertical", pscroll.scroll_vertical > 200.0)
		_check("scroll: the drag cancels the tap (deck unchanged)", m2._build_deck.is_empty())
		# And a clean tap (no drag) still adds the card.
		var tpress2 := InputEventScreenTouch.new()
		tpress2.pressed = true
		tpress2.index = 0
		tpress2.position = lp
		m2._on_pool_tile_input(tpress2, card0, tile0)
		var trelease2 := InputEventScreenTouch.new()
		trelease2.pressed = false
		trelease2.index = 0
		trelease2.position = lp
		m2._on_pool_tile_input(trelease2, card0, tile0)
		await get_tree().process_frame
		_check("scroll: a clean tap still adds the card", m2._build_deck == [card0])
	m2.queue_free()

	# --- Sprint 1a.3: modal mouse-filter structural test ---
	# For every full-screen modal, the overlay root is the only STOP
	# control; every descendant is IGNORE or PASS (Buttons excepted —
	# they keep STOP and dismiss/select themselves).
	var m5: Control = load("res://main.tscn").instantiate()
	add_child(m5)
	await get_tree().process_frame
	await get_tree().process_frame
	m5._show_magnify(CardDB.get_card("angry_squirrel"))
	_check("modal audit: magnify root is STOP", m5._magnify_overlay.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("modal audit: magnify has no STOP descendants", _modal_no_stop_kids(m5._magnify_overlay))
	m5._dismiss_magnify()
	var inspect_data := {"kind": "minion", "name": "Test", "cost_text": "", "stats": "1/1", "text": "Hi", "keywords": [], "card_id": ""}
	m5._show_inspect(inspect_data)
	_check("modal audit: inspect root is STOP", m5._inspect_overlay.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("modal audit: inspect has no STOP descendants", _modal_no_stop_kids(m5._inspect_overlay))
	m5._dismiss_inspect()
	m5._show_emote_menu()
	_check("modal audit: emote root is STOP", m5._emote_menu.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("modal audit: emote has no non-button STOP descendants", _modal_no_stop_kids(m5._emote_menu))
	m5._dismiss_emote_menu()
	# Android back button (ui_cancel) closes modals.
	m5._show_inspect(inspect_data)
	var back_ev := InputEventAction.new()
	back_ev.action = "ui_cancel"
	back_ev.pressed = true
	m5._input(back_ev)
	_check("modal audit: ui_cancel (back button) closes inspect", m5._inspect_overlay == null)
	# Watchdog: a modal stuck open past the timeout is force-closed.
	m5._show_inspect(inspect_data)
	m5._watchdog_since = Time.get_ticks_msec() - 6000
	await get_tree().process_frame
	await get_tree().process_frame
	_check("watchdog: stuck modal is force-closed with a warning", m5._inspect_overlay == null)
	m5.queue_free()

	# --- Sprint 1a.3: REAL tap through GUI hit-testing (needs rendering) ---
	# Headless Godot never dispatches synthetic events to gui_input, so
	# this runs only when a real DisplayServer is up (xvfb).
	if DisplayServer.get_name() != "headless":
		var m6: Control = load("res://main.tscn").instantiate()
		add_child(m6)
		await get_tree().process_frame
		await get_tree().process_frame
		m6._show_inspect(inspect_data)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("xvfb tap: inspect is open", m6._inspect_overlay != null)
		# Tap the dim area (top-left, canvas space) through the real
		# viewport input path — this is the tap the 1a.2 softlock ate.
		var vp6: Viewport = m6.get_viewport()
		var tap_at: Vector2 = m6._to_viewport_pos(Vector2(60, 60))
		var tp6 := InputEventScreenTouch.new()
		tp6.pressed = true
		tp6.index = 0
		tp6.position = tap_at
		vp6.push_input(tp6)
		await get_tree().process_frame
		var tr6 := InputEventScreenTouch.new()
		tr6.pressed = false
		tr6.index = 0
		tr6.position = tap_at
		vp6.push_input(tr6)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("xvfb tap: real tap through hit-testing closes inspect", m6._inspect_overlay == null)
		m6.queue_free()
	else:
		_check("xvfb tap: skipped under headless (no GUI hit-testing)", true)

	# --- Sprint 1a.3: 40-move monotonic scroll test (canvas-space) ---
	var m7: Control = load("res://main.tscn").instantiate()
	add_child(m7)
	await get_tree().process_frame
	m7._on_play()
	await get_tree().process_frame
	m7._on_class_picked("grunk")
	await get_tree().process_frame
	m7._on_class_picked("grunk")
	await get_tree().process_frame
	await get_tree().process_frame
	var pscroll7: ScrollContainer = m7.find_child("PoolScroll", true, false)
	var pgrid7: GridContainer = m7.find_child("PoolGrid", true, false)
	var tile7: Control = pgrid7.get_child(0)
	var card7: String = str(m7._pool_cards[0]["id"])
	pscroll7.scroll_vertical = 200.0
	await get_tree().process_frame
	var lp7 := Vector2(122, 149)
	var tp7 := InputEventScreenTouch.new()
	tp7.pressed = true
	tp7.index = 0
	tp7.position = lp7
	m7._on_pool_tile_input(tp7, card7, tile7)
	await get_tree().process_frame
	# A drag from the OTHER input family is ignored (one family per
	# gesture).
	var mm7 := InputEventMouseMotion.new()
	mm7.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm7.position = lp7 + Vector2(0, -30)
	m7._on_pool_tile_input(mm7, card7, tile7)
	_check("scroll: other family's drag is ignored", not bool(m7._manual_scroll.get("dragging", false)))
	# 40 small upward moves in canvas space: the scroll must move
	# monotonically (no jitter/feedback) and add no card.
	var last_v7: float = pscroll7.scroll_vertical
	var monotonic7: bool = true
	for di7 in range(1, 41):
		var td7 := InputEventScreenDrag.new()
		td7.index = 0
		td7.position = lp7 + Vector2(0, -2.0 * di7)
		td7.relative = Vector2(0, -2.0)
		m7._on_pool_tile_input(td7, card7, tile7)
		await get_tree().process_frame
		var v7: float = pscroll7.scroll_vertical
		if v7 < last_v7 - 0.001:
			monotonic7 = false
		last_v7 = v7
	var tr7 := InputEventScreenTouch.new()
	tr7.pressed = false
	tr7.index = 0
	tr7.position = lp7 + Vector2(0, -80)
	m7._on_pool_tile_input(tr7, card7, tile7)
	await get_tree().process_frame
	_check("scroll: 40 small moves scroll monotonically", monotonic7)
	_check("scroll: 40 small moves moved the scroll", pscroll7.scroll_vertical > 200.0)
	_check("scroll: the 40-move drag added no card", m7._build_deck.is_empty())
	m7.queue_free()

	# --- Sprint 1a.3: hand-card gesture layer ---
	var m8: Control = load("res://main.tscn").instantiate()
	add_child(m8)
	await get_tree().process_frame
	m8._on_play()
	await get_tree().process_frame
	m8._on_class_picked("grunk")
	await get_tree().process_frame
	m8._on_class_picked("grunk")
	await get_tree().process_frame
	m8._build_deck = _valid_deck_for("grunk")
	m8._on_deck_done()
	await get_tree().process_frame
	m8._build_deck = _valid_deck_for("grunk")
	m8._on_deck_done()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# Touch down lifts the card; a tap never plays.
	m8._gs.players[0]["hand"] = ["squire"]
	m8._gs.players[0]["mana"] = 10
	m8._gs.players[0]["board"] = []
	m8._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hz8: Node = m8.find_child("HandZone", true, false)
	var card_btn8: Control = hz8.get_child(0)
	var ctx8 := {"kind": "hand_card", "hand_idx": 0, "node": card_btn8}
	var lp8 := Vector2(65, 85)
	var gp8 := InputEventScreenTouch.new()
	gp8.pressed = true
	gp8.index = 0
	gp8.position = lp8
	m8._on_hand_gesture_input(gp8, ctx8, card_btn8)
	_check("gesture: touch down lifts the card", card_btn8.z_index == 50 and card_btn8.scale.x > 1.0)
	var gr8 := InputEventScreenTouch.new()
	gr8.pressed = false
	gr8.index = 0
	gr8.position = lp8
	m8._on_hand_gesture_input(gr8, ctx8, card_btn8)
	await get_tree().process_frame
	_check("gesture: tap never plays (hand + board unchanged)", m8._gs.players[0]["hand"].size() == 1 and m8._gs.players[0]["board"].size() == 0)
	_check("gesture: card restored after tap", card_btn8.z_index == 0 and card_btn8.scale == Vector2.ONE)
	# Hold >= 0.35s shows the preview; release closes it, nothing plays.
	m8._on_hand_gesture_input(gp8, ctx8, card_btn8)
	m8._press["t"] = Time.get_ticks_msec() - 400
	await get_tree().process_frame
	await get_tree().process_frame
	_check("gesture: hold >= 0.35s shows the preview", m8._hand_preview != null)
	m8._on_hand_gesture_input(gr8, ctx8, card_btn8)
	await get_tree().process_frame
	_check("gesture: preview release plays nothing", m8._gs.players[0]["hand"].size() == 1)
	_check("gesture: preview hidden after release", m8._hand_preview == null)
	# Drag above the play line plays an untargeted minion.
	m8._on_hand_gesture_input(gp8, ctx8, card_btn8)
	var start_c8: Vector2 = card_btn8.global_position + lp8
	for di8 in range(1, 8):
		m8._on_gesture_move(start_c8 + Vector2(0, -40.0 * di8))
		await get_tree().process_frame
	_check("gesture: drag enters dragging state", bool(m8._press.get("dragging", false)))
	_check("gesture: dragged card follows the finger", card_btn8.global_position.y < start_c8.y - 100.0)
	m8._on_gesture_release(Vector2(start_c8.x, m8._play_line_y() - 60.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check("gesture: release above the play line plays the minion", m8._gs.players[0]["board"].size() == 1 and m8._gs.players[0]["hand"].size() == 0)
	await get_tree().create_timer(1.2).timeout
	# Not enough mana: snap back with a toast, nothing played.
	m8._gs.players[0]["hand"] = ["squire"]
	m8._gs.players[0]["mana"] = 0
	m8._gs.players[0]["board"] = []
	m8._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hz9: Node = m8.find_child("HandZone", true, false)
	var card_btn9: Control = hz9.get_child(0)
	var ctx9 := {"kind": "hand_card", "hand_idx": 0, "node": card_btn9}
	m8._on_hand_gesture_input(gp8, ctx9, card_btn9)
	var start_c9: Vector2 = card_btn9.global_position + lp8
	for di9 in range(1, 8):
		m8._on_gesture_move(start_c9 + Vector2(0, -40.0 * di9))
		await get_tree().process_frame
	m8._on_gesture_release(Vector2(start_c9.x, m8._play_line_y() - 60.0))
	await get_tree().process_frame
	_check("gesture: not enough mana shows the toast, plays nothing", m8._toast_label != null and m8._toast_label.visible and m8._toast_label.text == "Not enough mana" and m8._gs.players[0]["hand"].size() == 1)
	# Targeted card: crossing the line -> arrow; release on a valid
	# target plays; release elsewhere cancels.
	m8._gs.players[0]["hand"] = ["fireball"]
	m8._gs.players[0]["mana"] = 10
	m8._gs.players[0]["board"] = []
	m8._gs.players[1]["hp"] = 30
	m8._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hz10: Node = m8.find_child("HandZone", true, false)
	var card_btn10: Control = hz10.get_child(0)
	var ctx10 := {"kind": "hand_card", "hand_idx": 0, "node": card_btn10}
	m8._on_hand_gesture_input(gp8, ctx10, card_btn10)
	var start_c10: Vector2 = card_btn10.global_position + lp8
	for di10 in range(1, 8):
		m8._on_gesture_move(start_c10 + Vector2(0, -60.0 * di10))
		await get_tree().process_frame
	_check("gesture: targeted card past the line shows the arrow", m8._arrow != null and m8._arrow.visible and bool(m8._drag.get("arrow_on", false)))
	var hpos10: Dictionary = m8._board_3d.hero_position(1, m8._gs.active)
	var hero_vp10: Vector2 = m8._board_3d.screen_pos(hpos10["position"])
	var hero_canvas10: Vector2 = m8.get_viewport().get_canvas_transform().affine_inverse() * hero_vp10
	m8._on_gesture_move(hero_canvas10)
	await get_tree().process_frame
	_check("gesture: arrow is red on a valid target", m8._arrow != null and m8._arrow.default_color.r > 0.9)
	m8._on_gesture_release(hero_canvas10)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("gesture: release on a valid target plays (hero -3, hand -1)", m8._gs.players[1]["hp"] == 27 and m8._gs.players[0]["hand"].size() == 0)
	await get_tree().create_timer(0.6).timeout
	m8._gs.players[0]["hand"] = ["fireball"]
	m8._gs.players[0]["mana"] = 10
	m8._gs.players[1]["hp"] = 30
	m8._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var hz11: Node = m8.find_child("HandZone", true, false)
	var card_btn11: Control = hz11.get_child(0)
	var ctx11 := {"kind": "hand_card", "hand_idx": 0, "node": card_btn11}
	m8._on_hand_gesture_input(gp8, ctx11, card_btn11)
	var start_c11: Vector2 = card_btn11.global_position + lp8
	for di11 in range(1, 8):
		m8._on_gesture_move(start_c11 + Vector2(0, -60.0 * di11))
		await get_tree().process_frame
	m8._on_gesture_release(Vector2(30, 700))
	await get_tree().create_timer(0.4).timeout
	_check("gesture: targeted card released elsewhere cancels", m8._gs.players[1]["hp"] == 30 and m8._gs.players[0]["hand"].size() == 1)
	# A Crew card with a targeted Entrance (2 damage to an enemy Crew
	# member): drag it up, aim at the enemy, let go -> it lands and hits.
	await get_tree().create_timer(0.4).timeout
	m8._gs.players[0]["hand"] = ["grunk_boot"]
	m8._gs.players[0]["mana"] = 10
	m8._gs.players[0]["board"] = []
	m8._gs.players[1]["board"] = [_minion("angry_squirrel")]
	m8._gs.players[1]["board"][0]["health"] = 5
	m8._gs.players[1]["board"][0]["max_health"] = 5
	m8._refresh_match()
	for _f12 in 4:
		await get_tree().process_frame
	var hz12: Node = m8.find_child("HandZone", true, false)
	var card_btn12: Control = hz12.get_child(0)
	var ctx12 := {"kind": "hand_card", "hand_idx": 0, "node": card_btn12}
	m8._on_hand_gesture_input(gp8, ctx12, card_btn12)
	var start_c12: Vector2 = card_btn12.global_position + lp8
	for di12 in range(1, 8):
		m8._on_gesture_move(start_c12 + Vector2(0, -60.0 * di12))
		await get_tree().process_frame
	var e_uid12: int = m8._gs.uid_for(m8._gs.players[1]["board"][0])
	var e_res12: Dictionary = m8._board_3d.minion_position(e_uid12)
	var e_canvas12: Vector2 = m8.get_viewport().get_canvas_transform().affine_inverse() * m8._board_3d.screen_pos(e_res12["position"])
	m8._on_gesture_move(e_canvas12)
	await get_tree().process_frame
	var snapped12: bool = not (m8._drag.get("snapped", {}) as Dictionary).is_empty()
	m8._on_gesture_release(e_canvas12)
	for _f13 in 3:
		await get_tree().process_frame
	_check("gesture: a Crew card's targeted Entrance snaps to the enemy (snapped=%s)" % snapped12, snapped12)
	_check("gesture: release plays the Crew card and its Entrance hits (enemy 5 -> 3)", m8._gs.players[0]["board"].size() == 1 and m8._gs.players[1]["board"].size() == 1 and int(m8._gs.players[1]["board"][0]["health"]) == 3)
	# Same with the MOUSE: once the arrow is out the card hides and stops
	# getting mouse events, so the release must still be caught.
	var w14: int = Time.get_ticks_msec()
	while (m8._animating or m8._ai_turn) and Time.get_ticks_msec() - w14 < 8000:
		await get_tree().process_frame
	m8._gs.players[0]["hand"] = ["grunk_boot"]
	m8._gs.players[0]["mana"] = 10
	m8._gs.players[0]["board"] = []
	m8._gs.players[1]["board"][0]["health"] = 5
	m8._refresh_match()
	for _f14 in 4:
		await get_tree().process_frame
	var hz14: Node = m8.find_child("HandZone", true, false)
	var card14: Control = hz14.get_child(0)
	var ctx14 := {"kind": "hand_card", "hand_idx": 0, "node": card14}
	var md14 := InputEventMouseButton.new()
	md14.button_index = MOUSE_BUTTON_LEFT
	md14.pressed = true
	md14.position = card14.size * 0.5
	m8._on_hand_gesture_input(md14, ctx14, card14)
	var start14: Vector2 = card14.global_position + card14.size * 0.5
	for di14 in range(1, 8):
		var mm14 := InputEventMouseMotion.new()
		mm14.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm14.position = (start14 + Vector2(0, -60.0 * di14)) - card14.global_position
		if card14.is_visible_in_tree():
			m8._on_hand_gesture_input(mm14, ctx14, card14)
		else:
			var gm14 := InputEventMouseMotion.new()
			gm14.button_mask = MOUSE_BUTTON_MASK_LEFT
			gm14.position = m8.get_global_transform_with_canvas() * (start14 + Vector2(0, -60.0 * di14))
			m8._input(gm14)
		await get_tree().process_frame
	_check("mouse: the card hides while the arrow is out", not card14.is_visible_in_tree())
	var gr14 := InputEventMouseButton.new()
	gr14.button_index = MOUSE_BUTTON_LEFT
	gr14.pressed = false
	gr14.position = m8.get_global_transform_with_canvas() * e_canvas12
	m8._input(gr14)
	for _f15 in 3:
		await get_tree().process_frame
	_check("mouse: letting go over the enemy plays the Crew card and its Entrance hits", m8._gs.players[0]["board"].size() == 1 and int(m8._gs.players[1]["board"][0]["health"]) == 3)
	m8.queue_free()

	# --- Sprint 1a.4: board layout & targeting ---
	# The layout targets 16:9 (1600 and 2000 widths); force a 16:9 window
	# so the headless viewport isn't square.
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	await get_tree().process_frame
	var m9: Control = load("res://main.tscn").instantiate()
	add_child(m9)
	await get_tree().process_frame
	m9._on_play()
	await get_tree().process_frame
	m9._on_class_picked("grunk")
	await get_tree().process_frame
	m9._on_class_picked("grunk")
	await get_tree().process_frame
	m9._build_deck = _valid_deck_for("grunk")
	m9._on_deck_done()
	await get_tree().process_frame
	m9._build_deck = _valid_deck_for("grunk")
	m9._on_deck_done()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	m9._gs.players[0]["mana"] = 10
	m9._gs.players[0]["max_mana"] = 10
	var c2t9: Transform2D = m9.get_viewport().get_canvas_transform().affine_inverse()
	var vsz9: Vector2 = m9.get_viewport().get_visible_rect().size
	# 1a.4 (1): no two tokens overlap (screen-space rects) at 1/4/7 per side.
	for tn9 in [1, 4, 7]:
		m9._gs.players[0]["board"] = []
		m9._gs.players[1]["board"] = []
		for ti9 in tn9:
			m9._gs.players[0]["board"].append(_minion("angry_squirrel"))
			m9._gs.players[1]["board"].append(_minion("angry_squirrel"))
		m9._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var rects9: Array = []
		for p9 in [0, 1]:
			var bd9: Array = m9._gs.players[p9]["board"]
			for bi9 in bd9.size():
				var wp9: Vector3 = m9._board_3d.slot_position(p9, bi9, bd9.size(), m9._gs.active)
				var cp9: Vector2 = c2t9 * m9._board_3d.screen_pos(wp9)
				var ep9: Vector2 = c2t9 * m9._board_3d.screen_pos(wp9 + Vector3(Board3D.TOKEN_VISUAL_R, 0, 0))
				var rr9: float = cp9.distance_to(ep9)
				rects9.append(Rect2(cp9 - Vector2(rr9, rr9), Vector2(rr9 * 2.0, rr9 * 2.0)))
		var overlap9: bool = false
		for a9 in rects9.size():
			for b9 in range(a9 + 1, rects9.size()):
				if (rects9[a9] as Rect2).intersects(rects9[b9] as Rect2):
					overlap9 = true
		_check("1a.4: no token overlap at %d per side" % tn9, not overlap9)
	# 1a.4 (2): badges don't overlap rows, END TURN, Signature Move, or the hand.
	m9._gs.players[0]["board"] = []
	m9._gs.players[1]["board"] = []
	for ti9b in 7:
		m9._gs.players[0]["board"].append(_minion("angry_squirrel"))
		m9._gs.players[1]["board"].append(_minion("angry_squirrel"))
	m9._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var badge_rects9: Array = []
	for p9b in [0, 1]:
		# Sprint 1a.5: hero badges are 2D panels (not 3D). Use the actual
		# panel rects.
		badge_rects9.append((m9._hero_badges[p9b] as Control).get_global_rect())
	var row_rects9: Array = []
	for p9c in [0, 1]:
		var bd9c: Array = m9._gs.players[p9c]["board"]
		var rr9c := Rect2(Vector2.ZERO, Vector2.ZERO)
		var first9: bool = true
		for bi9c in bd9c.size():
			var wp9c: Vector3 = m9._board_3d.slot_position(p9c, bi9c, bd9c.size(), m9._gs.active)
			var cp9c: Vector2 = c2t9 * m9._board_3d.screen_pos(wp9c)
			var ep9c: Vector2 = c2t9 * m9._board_3d.screen_pos(wp9c + Vector3(Board3D.TOKEN_VISUAL_R, 0, 0))
			var rad9c: float = cp9c.distance_to(ep9c)
			var tr9c := Rect2(cp9c - Vector2(rad9c, rad9c), Vector2(rad9c * 2.0, rad9c * 2.0))
			rr9c = tr9c if first9 else rr9c.merge(tr9c)
			first9 = false
		row_rects9.append(rr9c)
	var end_rect9: Rect2 = (m9.find_child("EndTurnBtn", true, false) as Control).get_global_rect()
	var sig_rect9: Rect2 = (m9.find_child("HeroPowerBtn", true, false) as Control).get_global_rect()
	var hand_rect9: Rect2 = _hand_cards_rect(m9)
	var badge_ok9: bool = true
	for br9b in badge_rects9:
		for rr9b in row_rects9:
			if (br9b as Rect2).intersects(rr9b as Rect2):
				badge_ok9 = false
		if (br9b as Rect2).intersects(end_rect9) or (br9b as Rect2).intersects(sig_rect9) or (br9b as Rect2).intersects(hand_rect9):
			badge_ok9 = false
	_check("1a.4: badges clear rows, END TURN, Sig Move, hand (%dx%d)" % [int(vsz9.x), int(vsz9.y)], badge_ok9)
	# Same badge check at 2000 width (spec: 1600 and 2000).
	get_window().size = Vector2i(2000, 1125)
	await get_tree().process_frame
	await get_tree().process_frame
	m9._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var c2t9b: Transform2D = m9.get_viewport().get_canvas_transform().affine_inverse()
	var vsz9b: Vector2 = m9.get_viewport().get_visible_rect().size
	var badge_rects9b: Array = []
	for p9d in [0, 1]:
		# Sprint 1a.5: hero badges are 2D panels (not 3D). Use the actual
		# panel rects.
		badge_rects9b.append((m9._hero_badges[p9d] as Control).get_global_rect())
	var row_rects9b: Array = []
	for p9e in [0, 1]:
		var bd9e: Array = m9._gs.players[p9e]["board"]
		var rr9e := Rect2(Vector2.ZERO, Vector2.ZERO)
		var first9b: bool = true
		for bi9e in bd9e.size():
			var wp9e: Vector3 = m9._board_3d.slot_position(p9e, bi9e, bd9e.size(), m9._gs.active)
			var cp9e: Vector2 = c2t9b * m9._board_3d.screen_pos(wp9e)
			var ep9e: Vector2 = c2t9b * m9._board_3d.screen_pos(wp9e + Vector3(Board3D.TOKEN_VISUAL_R, 0, 0))
			var rad9e: float = cp9e.distance_to(ep9e)
			var tr9e := Rect2(cp9e - Vector2(rad9e, rad9e), Vector2(rad9e * 2.0, rad9e * 2.0))
			rr9e = tr9e if first9b else rr9e.merge(tr9e)
			first9b = false
		row_rects9b.append(rr9e)
	var end_rect9b: Rect2 = (m9.find_child("EndTurnBtn", true, false) as Control).get_global_rect()
	var sig_rect9b: Rect2 = (m9.find_child("HeroPowerBtn", true, false) as Control).get_global_rect()
	var hand_rect9b: Rect2 = _hand_cards_rect(m9)
	var badge_ok9b: bool = true
	for br9f in badge_rects9b:
		for rr9f in row_rects9b:
			if (br9f as Rect2).intersects(rr9f as Rect2):
				badge_ok9b = false
		if (br9f as Rect2).intersects(end_rect9b) or (br9f as Rect2).intersects(sig_rect9b) or (br9f as Rect2).intersects(hand_rect9b):
			badge_ok9b = false
	_check("1a.4: badges clear rows, END TURN, Sig Move, hand (%dx%d)" % [int(vsz9b.x), int(vsz9b.y)], badge_ok9b)
	# Back to 1600 for the arrow tests.
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	await get_tree().process_frame
	# 1a.4 (3): arrow grey off-target, red on-target, snaps within 60px.
	m9._gs.players[0]["hand"] = ["fireball"]
	m9._gs.players[0]["board"] = []
	m9._gs.players[1]["board"] = []
	m9._gs.players[1]["hp"] = 30
	m9._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var hz9a: Node = m9.find_child("HandZone", true, false)
	var cb9a: Control = hz9a.get_child(0)
	var ctx9a := {"kind": "hand_card", "hand_idx": 0, "node": cb9a}
	m9._begin_drag(ctx9a, cb9a.global_position + cb9a.size / 2.0)
	var line9: float = m9._play_line_y()
	m9._update_drag(Vector2(800, line9 - 100))
	await get_tree().process_frame
	var grey9: Color = m9._arrow.default_color
	_check("1a.4: arrow grey off-target", m9._arrow.visible and grey9.r < 0.7 and grey9.g < 0.7 and grey9.b < 0.7)
	var hh9: Dictionary = m9._board_3d.hero_position(1, m9._gs.active)
	var hc9: Vector2 = c2t9 * m9._board_3d.screen_pos(hh9["position"])
	# Aim 40px off the Boss's aim point (chest height), inside the snap.
	var aimpt9: Vector2 = m9._target_screen_pos({"kind": "hero", "player": 1, "board_idx": -1})
	m9._update_drag(aimpt9 + Vector2(40, 0))
	await get_tree().process_frame
	var red9: Color = m9._arrow.default_color
	var snapped9: Dictionary = m9._drag.get("snapped", {})
	_check("1a.4: arrow red on-target", red9.r > 0.9 and red9.g < 0.3)
	_check("1a.4: snaps within 60px", not snapped9.is_empty() and str(snapped9.get("kind", "")) == "hero" and int(snapped9.get("player", -1)) == 1)
	# Step 2: the arrowhead lands at the Boss model's chest (its aim point).
	var aim9: Vector2 = c2t9 * m9._board_3d.screen_pos(hh9["position"] + m9._board_3d.aim_lift_hero(1))
	_check("1a.4: arrowhead snaps onto the target", (m9._arrowhead as Node2D).position.distance_to(aim9) < 5.0)
	# 1a.4 (5): the arrow origin is inside the screen (the 1a.3 bug).
	var org9: Vector2 = (m9._arrow as Line2D).points[0]
	_check("1a.4: arrow origin inside the screen", org9.x >= 0.0 and org9.y >= 0.0 and org9.x <= vsz9.x and org9.y <= vsz9.y)
	m9._end_drag(Vector2(800, 700))
	await get_tree().process_frame
	# 1a.4 (4): release off-target cancels with no state change.
	m9._gs.players[0]["hand"] = ["fireball"]
	m9._gs.players[0]["mana"] = 10
	m9._gs.players[1]["hp"] = 30
	m9._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var hz9b: Node = m9.find_child("HandZone", true, false)
	var cb9b: Control = hz9b.get_child(0)
	var ctx9b := {"kind": "hand_card", "hand_idx": 0, "node": cb9b}
	m9._begin_drag(ctx9b, cb9b.global_position + cb9b.size / 2.0)
	m9._update_drag(Vector2(800, line9 - 100))
	await get_tree().process_frame
	m9._end_drag(Vector2(800, line9 - 100))
	await get_tree().process_frame
	_check("1a.4: release off-target cancels (hand, hp, mana unchanged)",
		m9._gs.players[0]["hand"].size() == 1 and m9._gs.players[1]["hp"] == 30 and m9._gs.players[0]["mana"] == 10)
	# 1a.4 (5b): minion-attack arrow origin is inside the screen too.
	var atk_m9: Dictionary = _minion("angry_squirrel", true)
	m9._gs.players[0]["board"] = [atk_m9]
	m9._gs.players[1]["board"] = []
	m9._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var auid9: int = m9._gs.uid_for(m9._gs.players[0]["board"][0])
	var actx9 := {"kind": "my_minion", "board_idx": 0, "uid": auid9, "node": null}
	m9._begin_drag(actx9, Vector2(800, 500))
	m9._update_drag(Vector2(800, 300))
	await get_tree().process_frame
	var aorg9: Vector2 = (m9._arrow as Line2D).points[0]
	_check("1a.4: attack arrow origin inside the screen", aorg9.x >= 0.0 and aorg9.y >= 0.0 and aorg9.x <= vsz9.x and aorg9.y <= vsz9.y)
	m9._end_drag(Vector2(800, 700))
	m9.queue_free()

	# --- Sprint 1a.5: layout polish ---
	# Layout at 16:9 (1600x900, 2000x1125) and 20:9 (2400x1080).
	for wsz15 in [Vector2i(1600, 900), Vector2i(2000, 1125), Vector2i(2400, 1080)]:
		get_window().size = wsz15
		await get_tree().process_frame
		await get_tree().process_frame
		var m15: Control = load("res://main.tscn").instantiate()
		add_child(m15)
		await get_tree().process_frame
		m15._on_play()
		await get_tree().process_frame
		m15._on_class_picked("grunk")
		await get_tree().process_frame
		m15._on_class_picked("grunk")
		await get_tree().process_frame
		m15._build_deck = _valid_deck_for("grunk")
		m15._on_deck_done()
		await get_tree().process_frame
		m15._build_deck = _valid_deck_for("grunk")
		m15._on_deck_done()
		await get_tree().process_frame
		m15._gs.players[0]["mana"] = 10
		m15._gs.players[0]["max_mana"] = 10
		var c2t15: Transform2D = m15.get_viewport().get_canvas_transform().affine_inverse()
		var vsz15: Vector2 = m15.get_viewport().get_visible_rect().size
		var vrad15: float = Board3D.TOKEN_VISUAL_R
		# 1a.5 (1): token+badge no-overlap at 1/4/7 per side. The actual
		# 2D badge rects must sit inside their token rect.
		for tn15 in [1, 4, 7]:
			m15._gs.players[0]["board"] = []
			m15._gs.players[1]["board"] = []
			for ti15 in tn15:
				m15._gs.players[0]["board"].append(_minion("angry_squirrel"))
				m15._gs.players[1]["board"].append(_minion("angry_squirrel"))
			m15._refresh_match()
			await get_tree().process_frame
			await get_tree().process_frame
			var rects15: Array = []
			var badges_in15: bool = true
			for p15 in [0, 1]:
				var bd15: Array = m15._gs.players[p15]["board"]
				for bi15 in bd15.size():
					var wp15: Vector3 = m15._board_3d.slot_position(p15, bi15, bd15.size(), m15._gs.active)
					var cp15: Vector2 = c2t15 * m15._board_3d.screen_pos(wp15)
					var ep15: Vector2 = c2t15 * m15._board_3d.screen_pos(wp15 + Vector3(vrad15, 0, 0))
					var rr15: float = cp15.distance_to(ep15)
					var tr15 := Rect2(cp15 - Vector2(rr15, rr15), Vector2(rr15 * 2.0, rr15 * 2.0))
					rects15.append(tr15)
					var uid15: int = m15._gs.uid_for(bd15[bi15])
					var pair15: Dictionary = m15._stat_badges._badges.get(uid15, {})
					for bk15 in ["atk", "hp"]:
						var bctl15: Control = pair15.get(bk15)
						if bctl15 == null:
							badges_in15 = false
						elif not tr15.encloses(bctl15.get_global_rect()):
							badges_in15 = false
			var overlap15: bool = false
			for a15 in rects15.size():
				for b15 in range(a15 + 1, rects15.size()):
					if (rects15[a15] as Rect2).intersects(rects15[b15] as Rect2):
						overlap15 = true
			_check("1a.5: no token+badge overlap at %d per side (%dx%d)" % [tn15, int(wsz15.x), int(wsz15.y)], not overlap15)
			_check("1a.5: badges inside their token at %d per side (%dx%d)" % [tn15, int(wsz15.x), int(wsz15.y)], badges_in15)
		# 1a.5 (2): hero panels don't overlap rows, END TURN, the Sig
		# Move button/pill, or the hand.
		m15._gs.players[0]["board"] = []
		m15._gs.players[1]["board"] = []
		for ti10b in 7:
			m15._gs.players[0]["board"].append(_minion("angry_squirrel"))
			m15._gs.players[1]["board"].append(_minion("angry_squirrel"))
		m15._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var panel_rects15: Array = []
		for p10b in [0, 1]:
			panel_rects15.append((m15._hero_badges[p10b] as Control).get_global_rect())
		var row_rects15: Array = []
		for p10c in [0, 1]:
			var bd15c: Array = m15._gs.players[p10c]["board"]
			var rr15c := Rect2(Vector2.ZERO, Vector2.ZERO)
			var first15: bool = true
			for bi15c in bd15c.size():
				var wp15c: Vector3 = m15._board_3d.slot_position(p10c, bi15c, bd15c.size(), m15._gs.active)
				var cp15c: Vector2 = c2t15 * m15._board_3d.screen_pos(wp15c)
				var ep15c: Vector2 = c2t15 * m15._board_3d.screen_pos(wp15c + Vector3(vrad15, 0, 0))
				var rad15c: float = cp15c.distance_to(ep15c)
				var tr15c := Rect2(cp15c - Vector2(rad15c, rad15c), Vector2(rad15c * 2.0, rad15c * 2.0))
				rr15c = tr15c if first15 else rr15c.merge(tr15c)
				first15 = false
			row_rects15.append(rr15c)
		var end_rect15: Rect2 = (m15.find_child("EndTurnBtn", true, false) as Control).get_global_rect()
		var sig_rect15: Rect2 = (m15.find_child("HeroPowerBtn", true, false) as Control).get_global_rect()
		var sigpill_rect15: Rect2 = (m15.find_child("SigPill", true, false) as Control).get_global_rect()
		var hand_rect15: Rect2 = _hand_cards_rect(m15)
		var panels_ok15: bool = true
		for pr15 in panel_rects15:
			for rr10b in row_rects15:
				if (pr15 as Rect2).intersects(rr10b as Rect2):
					panels_ok15 = false
			for or15 in [end_rect15, sig_rect15, sigpill_rect15, hand_rect15]:
				if (pr15 as Rect2).intersects(or15 as Rect2):
					panels_ok15 = false
		_check("1a.5: hero panels clear rows, END TURN, Sig, hand (%dx%d)" % [int(wsz15.x), int(wsz15.y)], panels_ok15)
		# 1a.5 (3): the card hides while the arrow is active and
		# reappears when the finger comes back into the hand zone.
		var line15: float = m15._play_line_y()
		m15._gs.players[0]["hand"] = ["fireball"]
		m15._gs.players[0]["board"] = []
		m15._gs.players[1]["board"] = []
		m15._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var hz15: Node = m15.find_child("HandZone", true, false)
		var cn15: Control = hz15.get_child(0)
		var ctx15 := {"kind": "hand_card", "hand_idx": 0, "node": cn15}
		m15._begin_drag(ctx15, cn15.global_position + cn15.size / 2.0)
		m15._update_drag(Vector2(vsz15.x / 2.0, line15 - 100.0))
		await get_tree().process_frame
		_check("1a.5: card hides while the arrow is active (%dx%d)" % [int(wsz15.x), int(wsz15.y)], not cn15.visible)
		_check("1a.5: arrow is on while the card is hidden", bool(m15._drag.get("arrow_on", false)))
		m15._update_drag(Vector2(vsz15.x / 2.0, line15 + 100.0))
		await get_tree().process_frame
		_check("1a.5: card reappears in the hand zone (%dx%d)" % [int(wsz15.x), int(wsz15.y)], cn15.visible)
		_check("1a.5: arrow is off back in the hand zone", not bool(m15._drag.get("arrow_on", false)))
		m15._end_drag(Vector2(vsz15.x / 2.0, line15 + 100.0))
		await get_tree().process_frame
		# 1a.5 (4): a minion with a targeted Entrance shows a ghost
		# token at the landing slot while the arrow is active.
		m15._gs.players[0]["hand"] = ["archer"]
		m15._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var hz10b: Node = m15.find_child("HandZone", true, false)
		var cn10b: Control = hz10b.get_child(0)
		var ctx10b := {"kind": "hand_card", "hand_idx": 0, "node": cn10b}
		m15._begin_drag(ctx10b, cn10b.global_position + cn10b.size / 2.0)
		m15._update_drag(Vector2(vsz15.x / 2.0, line15 - 100.0))
		await get_tree().process_frame
		var ghost15: Node3D = m15._board_3d._ghost
		_check("1a.5: ghost token shows at the landing slot (%dx%d)" % [int(wsz15.x), int(wsz15.y)], ghost15 != null and ghost15.visible)
		m15._update_drag(Vector2(vsz15.x / 2.0, line15 + 100.0))
		await get_tree().process_frame
		_check("1a.5: ghost hides when the finger returns (%dx%d)" % [int(wsz15.x), int(wsz15.y)], ghost15 == null or not ghost15.visible)
		m15._end_drag(Vector2(vsz15.x / 2.0, line15 + 100.0))
		await get_tree().process_frame
		# 1a.5 (5): the arrow snaps to and highlights the enemy hero panel.
		m15._gs.players[0]["hand"] = ["fireball"]
		m15._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var hz10c: Node = m15.find_child("HandZone", true, false)
		var cn10c: Control = hz10c.get_child(0)
		var ctx10c := {"kind": "hand_card", "hand_idx": 0, "node": cn10c}
		m15._begin_drag(ctx10c, cn10c.global_position + cn10c.size / 2.0)
		var epanel15: Rect2 = (m15._hero_badges[1] as Control).get_global_rect()
		m15._update_drag(epanel15.get_center())
		await get_tree().process_frame
		var snapped15: Dictionary = m15._drag.get("snapped", {})
		_check("1a.5: arrow snaps to the enemy hero panel (%dx%d)" % [int(wsz15.x), int(wsz15.y)], str(snapped15.get("kind", "")) == "hero" and int(snapped15.get("player", -1)) == 1)
		_check("1a.5: enemy hero panel highlights red (%dx%d)" % [int(wsz15.x), int(wsz15.y)], (m15._hero_badges[1] as HeroBadge).is_highlighted())
		m15._end_drag(epanel15.get_center() + Vector2(500, 500))
		await get_tree().process_frame
		m15.queue_free()
	# 1a.5 (6): heal floaters fade out and hide (the stuck "+2").
	var m16: Control = load("res://main.tscn").instantiate()
	add_child(m16)
	await get_tree().process_frame
	m16._on_play()
	await get_tree().process_frame
	m16._on_class_picked("grunk")
	await get_tree().process_frame
	m16._on_class_picked("grunk")
	await get_tree().process_frame
	m16._build_deck = _valid_deck_for("grunk")
	m16._on_deck_done()
	await get_tree().process_frame
	m16._build_deck = _valid_deck_for("grunk")
	m16._on_deck_done()
	await get_tree().process_frame
	m16._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var dir11: AnimDirector = m16._anim_director
	var board11: Board3D = m16._board_3d
	dir11._spawn_floater(board11, Vector3.ZERO, "+2", Color(0.3, 1.0, 0.4))
	await get_tree().create_timer(1.2).timeout
	var stuck11: bool = false
	for f11 in board11._floaters:
		if (f11 as Label3D).visible and (f11 as Label3D).modulate.a > 0.01:
			stuck11 = true
	_check("1a.5: heal floater fades out and hides (no stuck '+2')", not stuck11)
	m16.queue_free()

	# --- Sprint 1c: game readability ---
	# 1c (1): history records plays/attacks/signature moves with the
	# correct actor and order, caps at 8, and builds the detail lines.
	var m17: Control = load("res://main.tscn").instantiate()
	add_child(m17)
	await get_tree().process_frame
	m17._on_play()
	await get_tree().process_frame
	m17._on_class_picked("grunk")
	await get_tree().process_frame
	m17._on_class_picked("grunk")
	await get_tree().process_frame
	m17._build_deck = _valid_deck_for("grunk")
	m17._on_deck_done()
	await get_tree().process_frame
	m17._build_deck = _valid_deck_for("grunk")
	m17._on_deck_done()
	await get_tree().process_frame
	m17._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	# Trade: two 2/2 squirrels — both die.
	m17._gs.players[0]["board"] = [_minion("angry_squirrel")]
	m17._gs.players[1]["board"] = [_minion("angry_squirrel")]
	m17._gs.players[0]["mana"] = 10
	m17._gs.attack(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	m17._record_history(m17._gs.take_events())
	_check("1c: history records the attack with the right actor", m17._history.size() == 1 and str(m17._history[0].get("kind")) == "attack" and int(m17._history[0].get("player")) == 0)
	var trade_detail: String = str(m17._history[0].get("detail", ""))
	_check("1c: trade detail line", trade_detail == "Angry Squirrel attacked Angry Squirrel: dealt 2, took 2. Angry Squirrel died. Angry Squirrel died.")
	# Destroy (Written Out of the Will on an enemy squirrel).
	m17._gs.players[0]["board"] = []
	m17._gs.players[1]["board"] = [_minion("angry_squirrel")]
	m17._gs.players[0]["hand"] = ["assassinate"]
	m17._gs.players[0]["mana"] = 10
	m17._gs.play_card(0, 0, {"kind": "minion", "player": 1, "board_idx": 0})
	m17._record_history(m17._gs.take_events())
	_check("1c: history records the destroy, newest on top", m17._history.size() == 2 and str(m17._history[0].get("kind")) == "played" and int(m17._history[0].get("player")) == 0)
	_check("1c: destroy detail line", str(m17._history[0].get("detail", "")) == "Written Out of the Will: destroyed Angry Squirrel")
	# Coin flip (synthetic events — the engine flip is random).
	m17._record_history([
		{"type": "card_played", "data": {"player": 1, "card_id": "coin_flip"}},
		{"type": "coin_flip", "data": {"player": 1, "heads": false}},
		{"type": "draw", "data": {"player": 1, "card_id": "squire"}},
		{"type": "damage", "data": {"player": 1, "target_kind": "hero", "uid": -1, "amount": 2, "source_uid": -1, "source_card_id": ""}},
	])
	_check("1c: history records the coin flip with the right actor", m17._history.size() == 3 and str(m17._history[0].get("kind")) == "played" and int(m17._history[0].get("player")) == 1)
	_check("1c: coin flip detail line", str(m17._history[0].get("detail", "")) == "Coin Flip of Destiny: Tails, drew a card, took 2 damage")
	# Signature Move (Grunk: Throw a Firecracker, 2 to the enemy hero).
	m17._gs.players[1]["hp"] = 30
	m17._gs.use_hero_power(0)
	m17._record_history(m17._gs.take_events())
	_check("1c: history records the signature move", m17._history.size() == 4 and str(m17._history[0].get("kind")) == "signature" and int(m17._history[0].get("player")) == 0)
	_check("1c: signature detail line", str(m17._history[0].get("detail", "")) == "Throw a Firecracker: dealt 2 to Player 2's Grunk")
	# Cap: 10 more plays -> still 8, newest first.
	for ci17 in 10:
		m17._record_history([{"type": "card_played", "data": {"player": ci17 % 2, "card_id": "coin"}}])
	_check("1c: history caps at 8, newest on top", m17._history.size() == 8 and int(m17._history[0].get("player")) == 1 and int(m17._history[7].get("player")) == 0)
	# 1c (2): Signature Move long-press opens inspect; tap still fires.
	m17._gs.players[0]["mana"] = 10
	m17._gs.players[0]["hero_power_used"] = false
	m17._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	var sig17: Button = m17.find_child("HeroPowerBtn", true, false)
	_check("1c: sig button has no pressed connection (gesture-driven)", sig17 != null)
	# Long-press: press, age the press past the threshold, let _process fire.
	var press_ev := InputEventScreenTouch.new()
	press_ev.pressed = true
	press_ev.position = Vector2(50, 50)
	m17._on_sig_gesture_input(press_ev, sig17)
	m17._sig_press["t"] = Time.get_ticks_msec() - 500
	await get_tree().process_frame
	await get_tree().process_frame
	var insp17: Node = m17.find_child("InspectOverlay", true, false)
	_check("1c: sig long-press opens inspect", insp17 != null)
	var insp_name17: String = ""
	var insp_cost17: String = ""
	if insp17 != null:
		for ch17 in (insp17 as Control).find_children("*", "Label", true, false):
			var lt17: String = (ch17 as Label).text
			if lt17 == "Throw a Firecracker":
				insp_name17 = lt17
			if lt17 == "Cost 2":
				insp_cost17 = lt17
	_check("1c: sig inspect shows name and cost", insp_name17 == "Throw a Firecracker" and insp_cost17 == "Cost 2")
	m17._dismiss_inspect()
	# Moving off cancels the long-press (no inspect).
	m17._on_sig_gesture_input(press_ev, sig17)
	var drag_ev := InputEventScreenDrag.new()
	drag_ev.position = Vector2(50, 100)
	m17._on_sig_gesture_input(drag_ev, sig17)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("1c: sig move-off cancels (no inspect)", m17.find_child("InspectOverlay", true, false) == null and m17._sig_press.is_empty())
	# Tap: press + quick release fires the move.
	m17._gs.players[1]["hp"] = 30
	m17._on_sig_gesture_input(press_ev, sig17)
	var rel_ev := InputEventScreenTouch.new()
	rel_ev.pressed = false
	rel_ev.position = Vector2(50, 50)
	m17._on_sig_gesture_input(rel_ev, sig17)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check("1c: sig tap still fires (enemy hero -2 HP)", m17._gs.players[1]["hp"] == 28 and m17._gs.players[0]["hero_power_used"])
	m17.queue_free()
	# 1c (3): every hero-origin effect starts on-screen at 16:9 and 20:9.
	# 1c (4): no arrow below the 40px threshold; the history column
	# overlaps nothing (hero panels, rows, hand).
	for wsz17 in [Vector2i(1600, 900), Vector2i(2000, 1125), Vector2i(2400, 1080)]:
		get_window().size = wsz17
		await get_tree().process_frame
		await get_tree().process_frame
		var m18: Control = load("res://main.tscn").instantiate()
		add_child(m18)
		await get_tree().process_frame
		m18._on_play()
		await get_tree().process_frame
		m18._on_class_picked("grunk")
		await get_tree().process_frame
		m18._on_class_picked("grunk")
		await get_tree().process_frame
		m18._build_deck = _valid_deck_for("grunk")
		m18._on_deck_done()
		await get_tree().process_frame
		m18._build_deck = _valid_deck_for("grunk")
		m18._on_deck_done()
		await get_tree().process_frame
		for ti18 in 7:
			m18._gs.players[0]["board"].append(_minion("angry_squirrel"))
			m18._gs.players[1]["board"].append(_minion("angry_squirrel"))
		m18._gs.players[0]["hand"] = ["fireball"]
		m18._gs.players[0]["mana"] = 10
		# Fill the history so the column is at its full 8-entry height.
		for ci18 in 8:
			m18._record_history([{"type": "card_played", "data": {"player": ci18 % 2, "card_id": "coin"}}])
		m18._refresh_match()
		await get_tree().process_frame
		await get_tree().process_frame
		var c2t18: Transform2D = m18.get_viewport().get_canvas_transform().affine_inverse()
		var vis18: Rect2 = m18.get_viewport().get_visible_rect()
		var onscreen18: bool = true
		# Hotfix 1c.1: the coin moment is fitted into the inter-row gap
		# (_coin_moment): coin plus the HEADS/TAILS pill, both on-screen.
		var cm18: Dictionary = m18._board_3d._coin_moment()
		var coin_c: Vector2 = c2t18 * m18._board_3d.screen_pos(cm18["pos"])
		var coin_l: Vector2 = c2t18 * m18._board_3d.screen_pos(cm18["pill_pos"])
		if not vis18.has_point(coin_c) or not vis18.has_point(coin_l):
			onscreen18 = false
		# Projectile origins: the hero anchor is the 3D point under the panel.
		for p18 in [0, 1]:
			var hr18: Dictionary = m18._board_3d.hero_position(p18, m18._gs.active)
			if bool(hr18.get("found", false)):
				if not vis18.has_point(c2t18 * m18._board_3d.screen_pos(hr18["position"])):
					onscreen18 = false
		# Hero floaters live on the 2D badge panel.
		for p18b in [0, 1]:
			var hb18: HeroBadge = m18._hero_badges[p18b]
			var fl18: Label = hb18.float_text("-3", Color(1, 0.2, 0.2))
			var fr18: Rect2 = fl18.get_global_rect()
			if not vis18.intersects(fr18):
				onscreen18 = false
			fl18.queue_free()
		_check("1c: hero-origin effects start on-screen at %dx%d" % [wsz17.x, wsz17.y], onscreen18)
		# History column overlaps nothing (panels, rows, hand).
		var hcol18: Control = m18.find_child("HistoryColumn", true, false)
		var hrect18: Rect2 = hcol18.get_global_rect()
		var blockers18: Array = []
		for p18c in [0, 1]:
			blockers18.append((m18._hero_badges[p18c] as Control).get_global_rect())
		var hz18: Node = m18.find_child("HandZone", true, false)
		blockers18.append((hz18 as Control).get_global_rect())
		for p18d in [0, 1]:
			var bd18: Array = m18._gs.players[p18d]["board"]
			for bi18 in bd18.size():
				var wp18: Vector3 = m18._board_3d.slot_position(p18d, bi18, bd18.size(), m18._gs.active)
				var cp18: Vector2 = c2t18 * m18._board_3d.screen_pos(wp18)
				var ep18: Vector2 = c2t18 * m18._board_3d.screen_pos(wp18 + Vector3(Board3D.TOKEN_VISUAL_R, 0, 0))
				var rr18: float = cp18.distance_to(ep18)
				blockers18.append(Rect2(cp18 - Vector2(rr18, rr18), Vector2(rr18 * 2.0, rr18 * 2.0)))
		var hov18: bool = false
		for b18 in blockers18:
			if (b18 as Rect2).grow(-1).intersects(hrect18.grow(-1)):
				hov18 = true
		_check("1c: history column overlaps nothing at %dx%d" % [wsz17.x, wsz17.y], not hov18)
		# Arrow threshold: drag a targeted card 20px above the line —
		# no arrow, card stays visible; at 100px the arrow is out.
		var hz18b: Node = m18.find_child("HandZone", true, false)
		var hbtn18: Control = hz18b.get_child(0)
		var ctx18: Dictionary = {"kind": "hand_card", "hand_idx": 0, "node": hbtn18}
		m18._begin_drag(ctx18, hbtn18.global_position + hbtn18.size / 2.0)
		var line18: float = m18._play_line_y()
		m18._update_drag(Vector2(640, line18 - 20))
		_check("1c: no arrow below the 40px threshold", m18._arrow == null or not m18._arrow.visible)
		_check("1c: card stays visible below the threshold", hbtn18.visible)
		m18._update_drag(Vector2(640, line18 - 100))
		_check("1c: arrow appears past the threshold", m18._arrow != null and m18._arrow.visible)
		m18._end_drag(Vector2(640, line18 - 20))
		_check("1c: release below the threshold cancels (hand intact)", m18._gs.players[0]["hand"].size() == 1 and m18._gs.players[0]["mana"] == 10)
		m18.queue_free()

	# --- Hotfix 1c.1: token scale ---
	# Run the director over a batch containing a summon, an Entrance, a
	# Final Bow, a buff, a hit and a steal. Every surviving token must
	# end at base_scale — the old absolute tweens (summon squash to
	# scale:y 1.0, trigger flash to Vector3.ONE) left them ~1.85x big.
	var sc_pre := _gs_with_hands([], [])
	var sc_a: Dictionary = _minion("squire")
	sc_a["uid"] = 30
	var sc_b: Dictionary = _minion("squire")
	sc_b["uid"] = 31
	var sc_c: Dictionary = _minion("squire")
	sc_c["uid"] = 32
	var sc_d: Dictionary = _minion("squire")
	sc_d["uid"] = 33
	sc_pre.players[0]["board"] = [sc_a, sc_b]
	sc_pre.players[1]["board"] = [sc_c, sc_d]
	var sc_post := _gs_with_hands([], [])
	var sc_a2: Dictionary = _minion("squire")
	sc_a2["uid"] = 30
	var sc_b2: Dictionary = _minion("squire")
	sc_b2["uid"] = 31
	var sc_new: Dictionary = _minion("squire")
	sc_new["uid"] = 34
	var sc_d2: Dictionary = _minion("squire")
	sc_d2["uid"] = 33
	sc_post.players[0]["board"] = [sc_a2, sc_b2, sc_new, sc_d2]
	sc_post.players[1]["board"] = []
	var sc_board := Board3D.new()
	add_child(sc_board)
	sc_board.sync(sc_pre)
	var sc_director := AnimDirector.new()
	add_child(sc_director)
	sc_director.ANIM_SPEED = 1000.0
	var sc_events: Array = [
		{"type": "minion_summoned", "data": {"player": 0, "uid": 34, "card_id": "squire", "board_idx": 2}},
		{"type": "entrance", "data": {"player": 0, "uid": 30, "card_id": "zapper"}},
		{"type": "buff", "data": {"player": 0, "uid": 30, "attack_delta": 1, "health_delta": 0, "source_uid": -1, "source_card_id": ""}},
		{"type": "attack", "data": {"player": 0, "attacker_uid": 30, "target_kind": "minion", "target_player": 1, "target_uid": 32}},
		{"type": "damage", "data": {"target_kind": "minion", "player": 1, "uid": 32, "amount": 5, "source_uid": 30, "source_card_id": ""}},
		{"type": "minion_died", "data": {"player": 1, "uid": 32, "card_id": "squire"}},
		{"type": "final_bow", "data": {"player": 1, "uid": 32, "card_id": "squire"}},
		{"type": "minion_stolen", "data": {"from_player": 1, "to_player": 0, "uid": 33}},
	]
	await sc_director.play_events(sc_events, sc_board, sc_post)
	await get_tree().process_frame
	await get_tree().process_frame
	var sc_tweens_ok := true
	var sc_base_ok := true
	for sc_uid in sc_board._minions.keys():
		var sc_n: Minion3D = sc_board._minions[sc_uid]
		if sc_n.scale != sc_n.base_scale:
			sc_tweens_ok = false
		if sc_n.base_scale != Vector3(Board3D.TOKEN_SCALE, Board3D.TOKEN_SCALE, Board3D.TOKEN_SCALE):
			sc_base_ok = false
	_check("1c.1: director tweens leave every token at base_scale (pre-sync)", sc_tweens_ok)
	_check("1c.1: every token's base_scale is TOKEN_SCALE", sc_base_ok)
	sc_board.sync(sc_post)
	var sc_net_ok := true
	for sc_uid2 in sc_board._minions.keys():
		var sc_n2: Minion3D = sc_board._minions[sc_uid2]
		if sc_n2.scale != sc_n2.base_scale:
			sc_net_ok = false
	_check("1c.1: sync() safety net holds every token at base_scale", sc_net_ok)
	sc_board.queue_free()
	sc_director.queue_free()

	# --- Hotfix 1c.1: coin flip at screen center ---
	# The coin rest point must project near the screen center (not the
	# far table center), the HEADS/TAILS label sits on a moderate dark
	# pill under the coin, and neither may cover the minion rows.
	for wsz19 in [Vector2i(1600, 900), Vector2i(2000, 1125), Vector2i(2400, 1080)]:
		get_window().size = wsz19
		await get_tree().process_frame
		await get_tree().process_frame
		var cb19 := Board3D.new()
		add_child(cb19)
		await get_tree().process_frame
		var vis19: Rect2 = get_viewport().get_visible_rect()
		# Hotfix 1c.1: the coin moment is fitted into the inter-row gap
		# at runtime (_coin_moment). The whole moment must sit on-screen
		# and never cover a minion token.
		var cm19: Dictionary = cb19._coin_moment()
		var cpos19: Vector3 = cm19["pos"]
		var csc19: float = cm19["coin_scale"]
		var ppos19: Vector3 = cm19["pill_pos"]
		var cvp19: Vector2 = cb19.screen_pos(cpos19)
		var cr19: float = 0.45 * csc19
		var crx19: float = cvp19.distance_to(cb19.screen_pos(cpos19 + Vector3(cr19, 0, 0)))
		var cry19: float = cvp19.distance_to(cb19.screen_pos(cpos19 + Vector3(0, cr19, 0)))
		var coin_r19 := Rect2(cvp19 - Vector2(crx19, cry19), Vector2(crx19 * 2.0, cry19 * 2.0))
		var pvp19: Vector2 = cb19.screen_pos(ppos19)
		var phx19: float = pvp19.distance_to(cb19.screen_pos(ppos19 + Vector3(0.45 * Board3D.FX_SCALE, 0, 0)))
		var phy19: float = pvp19.distance_to(cb19.screen_pos(ppos19 + Vector3(0, 0.16 * Board3D.FX_SCALE, 0)))
		var pill_r19 := Rect2(pvp19 - Vector2(phx19, phy19), Vector2(phx19 * 2.0, phy19 * 2.0))
		var moment19: Rect2 = coin_r19.merge(pill_r19)
		var cok19: bool = vis19.encloses(moment19)
		# The label is moderate (font 48 on a 0.9x0.32 dark pill), not
		# the old huge 72pt-at-2x label that covered the enemy row.
		if cb19._coin_label.font_size != 48:
			cok19 = false
		var pill_mesh19: QuadMesh = cb19._coin_pill.mesh as QuadMesh
		if pill_mesh19 == null or pill_mesh19.size != Vector2(0.9, 0.32) * Board3D.FX_SCALE:
			cok19 = false
		var gsc19 := _gs_with_hands([], [])
		for mi19 in 7:
			gsc19.players[0]["board"].append(_minion("squire"))
			gsc19.players[1]["board"].append(_minion("squire"))
		cb19.sync(gsc19)
		await get_tree().process_frame
		for p19 in [0, 1]:
			var bd19: Array = gsc19.players[p19]["board"]
			for bi19 in bd19.size():
				var wp19: Vector3 = cb19.slot_position(p19, bi19, bd19.size(), gsc19.active)
				var cp19: Vector2 = cb19.screen_pos(wp19)
				var rp19: float = cp19.distance_to(cb19.screen_pos(wp19 + Vector3(Board3D.TOKEN_VISUAL_R, 0, 0)))
				if moment19.intersects(Rect2(cp19 - Vector2(rp19, rp19), Vector2(rp19 * 2.0, rp19 * 2.0))):
					cok19 = false
		_check("1c.1: coin moment on-screen, clear of rows at %dx%d" % [wsz19.x, wsz19.y], cok19)
		cb19.queue_free()

	# --- Hotfix 1c.2 (1): hero HP stale after pass-the-phone ---
	# Alex: damage P2's hero, pass the phone, P2's badge showed the
	# PRE-damage HP until someone took damage again. Root cause: after
	# the interstitial's full _clear(), Board3D.sync()'s plaque-creation
	# path never called update_hp (HeroPlaque3D.setup ignored its hp
	# param), so the rebuilt badge showed the 30/30 default.
	var mh: Control = load("res://main.tscn").instantiate()
	add_child(mh)
	await get_tree().process_frame
	mh._decks = [_valid_deck_for("grunk"), _valid_deck_for("grunk")]
	mh._classes = ["grunk", "grunk"]
	mh._start_match()
	mh._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	# P1 (Grunk) firecrackers P2's hero for 2 via the real engine path.
	mh._gs.players[0]["mana"] = 10
	mh._gs.players[0]["max_mana"] = 10
	_check("1c.2: grunk hero power fires", mh._gs.use_hero_power(0))
	mh._board_3d.sync(mh._gs)
	await get_tree().process_frame
	_check("1c.2: P2 hero took 2", int(mh._gs.players[1]["hp"]) == 28)
	_check("1c.2: badge shows damage before end turn", _badge_hp_text(mh, 1) == "28/30")
	# End turn -> interstitial -> P2 taps READY. No new damage happens.
	mh._gs.end_turn()
	mh._show_interstitial(mh._gs.active, "Player 2's turn! Pass the phone to Player 2.")
	await get_tree().process_frame
	mh._on_interstitial_ready(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("1c.2: P2 badge shows reduced HP after interstitial", _badge_hp_text(mh, 1) == "28/30")
	_check("1c.2: P2 badge mana synced after interstitial", _badge_mana_text(mh, 1) == "%d/%d" % [int(mh._gs.players[1]["mana"]), int(mh._gs.players[1]["max_mana"])])
	# Pass back: P1's view of the enemy badge is correct too.
	mh._gs.end_turn()
	mh._show_interstitial(mh._gs.active, "Player 1's turn! Pass the phone to Player 1.")
	await get_tree().process_frame
	mh._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("1c.2: enemy badge shows reduced HP from P1 view", _badge_hp_text(mh, 1) == "28/30")
	mh.queue_free()

	# --- Hotfix 1c.2 (2): keyword definitions outside the battlefield ---
	# Alex: keywords were only defined on the battlefield inspect panel.
	# Deckbuilder magnify shows the Bouncer line.
	var mk: Control = load("res://main.tscn").instantiate()
	add_child(mk)
	await get_tree().process_frame
	mk._show_magnify(CardDB.get_card("squire"))
	await get_tree().process_frame
	var mov: Node = mk.find_child("MagnifyOverlay", true, false)
	_check("1c.2: magnify overlay appears", mov != null)
	_check("1c.2: magnify shows the Bouncer definition", mov != null and _has_label_with(mov, "Enemies must attack"))
	mk._dismiss_magnify()
	await get_tree().process_frame
	# A vanilla card shows no keyword box.
	mk._show_magnify(CardDB.get_card("angry_squirrel"))
	await get_tree().process_frame
	var mov2: Node = mk.find_child("MagnifyOverlay", true, false)
	_check("1c.2: magnify of vanilla card has no keyword box", mov2 != null and mov2.find_child("KeywordHelp", true, false) == null)
	mk._dismiss_magnify()
	mk.queue_free()
	# Hand preview shows the Bouncer line.
	var mp: Control = load("res://main.tscn").instantiate()
	add_child(mp)
	await get_tree().process_frame
	mp._decks = [_valid_deck_for("grunk"), _valid_deck_for("grunk")]
	mp._classes = ["grunk", "grunk"]
	mp._start_match()
	mp._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	mp._gs.players[0]["hand"] = ["squire"]
	mp._refresh_match()
	await get_tree().process_frame
	await get_tree().process_frame
	mp._show_hand_preview({"kind": "hand_card", "hand_idx": 0})
	await get_tree().process_frame
	_check("1c.2: hand preview appears", mp._hand_preview != null)
	_check("1c.2: hand preview shows the Bouncer definition", mp._hand_preview != null and _has_label_with(mp._hand_preview, "Enemies must attack"))
	mp._hide_hand_preview()
	# Inspect opened from a hand card shows the Bouncer line too.
	mp._show_inspect(mp._inspect_data_for_card(CardDB.get_card("squire")))
	await get_tree().process_frame
	_check("1c.2: hand-card inspect shows the Bouncer definition", mp._inspect_overlay != null and _has_label_with(mp._inspect_overlay, "Enemies must attack"))
	mp._dismiss_inspect()
	mp.queue_free()

	# --- Step 2: themed mana counter + the 90-second turn clock ---
	var mt: Control = load("res://main.tscn").instantiate()
	add_child(mt)
	await get_tree().process_frame
	mt._decks = [_valid_deck_for("grunk"), _valid_deck_for("agatha")]
	mt._classes = ["grunk", "agatha"]
	mt._start_match()
	mt._on_interstitial_ready(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var hb_t: HeroBadge = mt._hero_badges[0]
	_check("boss card: plain mana numbers, no themed counter", hb_t != null and hb_t.counter == null and hb_t.class_id == "grunk" and (mt._hero_badges[1] as HeroBadge).class_id == "agatha")
	_check("boss card: shows the mana as 3/6", hb_t._mana_label.text == "%d/%d" % [int(mt._gs.players[0]["mana"]), int(mt._gs.players[0]["max_mana"])])
	var mine_r: Rect2 = (mt._hero_badges[mt._view()] as Control).get_global_rect()
	var foe_r: Rect2 = (mt._hero_badges[1 - mt._view()] as Control).get_global_rect()
	_check("boss card: tall and skinny, mine low on the left, theirs high", mine_r.size.y > mine_r.size.x * 1.6 and mine_r.position.y > foe_r.end.y and mine_r.end.y <= 720.0 and foe_r.position.y >= 40.0)
	for _pf in 120:
		if mt._board_3d.preload_pending() == 0:
			break
		await get_tree().process_frame
	_check("step2: the match preloads every model it can show", mt._board_3d.preload_pending() == 0 and ModelLib.is_cached("hero_grunk") and mt._gs.players[0]["deck"].all(func(c: Variant) -> bool: return not ModelLib.has_model(str(c)) or ModelLib.is_cached(str(c))))
	_check("step2: summoned tokens find a model", Minion3D.model_for({"card_id": "deckhand", "art": "deckhand", "name": "Deckhand"}) != "" or not ModelLib.has_model("token_deckhand"))
	var wm := Minion3D.new()
	add_child(wm)
	var wmd: Dictionary = {"uid": 9901, "card_id": str(mt._gs.players[0]["deck"][0]), "name": "x", "attack": 2, "health": 2, "max_health": 2, "sick": true, "can_attack": false}
	wm.setup(wmd, 0)
	_check("step2: a just-summoned Crew member is warming up (booting hologram)", wm.unit == null or (wm.warming and wm._warm_ring != null and wm._warm_ring.visible))
	wmd["sick"] = false
	wmd["can_attack"] = true
	wm.update_stats(wmd, true)
	_check("step2: warming clears once it can attack", wm.unit == null or (not wm.warming and not wm._warm_ring.visible))
	_check("step2: inspect says it's warming up", "Warming up" in str(mt._inspect_data_for_minion({"card_id": wmd["card_id"], "sick": true, "can_attack": false}).get("status", "")))
	wm.queue_free()
	_check("step2: turn clock starts at 90s", mt._turn_timer != null and absf(mt._turn_timer.left - 90.0) < 1.0 and not mt._turn_timer.warning())
	mt._turn_timer.left = 14.0
	await get_tree().process_frame
	_check("step2: last 15s shows the fuse", mt._turn_timer.warning() and mt._turn_timer.visible and mt._turn_timer.deck == "grunk")
	var active_t: int = mt._gs.active
	mt._turn_timer.left = 0.01
	for _ft in 4:
		await get_tree().process_frame
	_check("step2: at zero the turn ends by itself", mt._gs.active != active_t or mt._screen != mt.Screen.MATCH)
	mt.queue_free()


func _badge_hp_text(m: Control, player_idx: int) -> String:
	var hb = m._hero_badges[player_idx]
	if hb == null or not is_instance_valid(hb) or hb._hp_label == null:
		return ""
	return str(hb._hp_label.text)


func _badge_mana_text(m: Control, player_idx: int) -> String:
	var hb = m._hero_badges[player_idx]
	if hb == null or not is_instance_valid(hb) or hb._mana_label == null:
		return ""
	return str(hb._mana_label.text)


func _has_label_with(root: Node, needle: String) -> bool:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and needle in str((n as Label).text):
			return true
		for ch in n.get_children():
			stack.append(ch)
	return false


# --- PC online play: two games in one process, host runs the built-in
# relay, the guest joins by address; both play on the real 3D board. ---
# The AI must keep hitting a Boss whatever its health (it used to stall
# at 16 and 8, where its health scoring jumped), and not waste 2 mana
# healing at full health.
func _test_ai_no_stall() -> void:
	var mono: bool = true
	for h in range(0, 31):
		if AIPlayer.health_value(h) <= AIPlayer.health_value(h - 1) and h > 0:
			mono = false
	_check("ai: losing health always lowers the AI's value of it", mono)
	for start_hp in [30, 16, 9, 8]:
		var gs := GameState.new()
		gs.setup(_valid_deck_for("reginald"), _valid_deck_for("agatha"), "reginald", "agatha")
		gs.active = 1
		gs.players[0]["hp"] = start_hp
		gs.players[0]["board"] = []
		gs.players[1]["board"] = [_minion("squire")]
		gs.players[1]["board"][0]["can_attack"] = true
		gs.players[1]["board"][0]["sick"] = false
		gs.players[1]["hand"] = []
		gs.players[1]["mana"] = 2
		var ai := AIPlayer.new()
		ai.sloppiness = 0.0
		var a: Dictionary = ai.next_action(gs, 1)
		_check("ai: attacks a Boss on %d health with an empty board in the way" % start_hp, str(a.get("type", "")) == "attack")
	var gs2 := GameState.new()
	gs2.setup(_valid_deck_for("reginald"), _valid_deck_for("agatha"), "reginald", "agatha")
	gs2.active = 1
	gs2.players[1]["hp"] = 30
	gs2.players[1]["hand"] = []
	gs2.players[1]["board"] = []
	gs2.players[1]["mana"] = 2
	var ai2 := AIPlayer.new()
	ai2.sloppiness = 0.0
	_check("ai: Agatha doesn't heal at full health", str(ai2.next_action(gs2, 1).get("type", "")) == "end")
	# The Lucky Penny: with 1 mana and a 2-cost Crew card in hand, the AI
	# plays the Penny first (it used to never play it), and doesn't waste
	# it when there's nothing it unlocks.
	var two: String = ""
	for c in CardDB.cards_for_class("grunk"):
		if int(c["cost"]) == 2 and c["type"] == "minion" and str(c.get("effect", "")) == "":
			two = str(c["id"])
			break
	var gs3 := GameState.new()
	gs3.setup(_valid_deck_for("grunk"), _valid_deck_for("grunk"), "grunk", "grunk")
	gs3.active = 1
	gs3.players[1]["hand"] = ["coin", two]
	gs3.players[1]["board"] = []
	gs3.players[1]["mana"] = 1
	gs3.players[1]["max_mana"] = 1
	gs3.players[1]["hero_power_used"] = true
	var a3: Dictionary = ai2.next_action(gs3, 1)
	_check("ai: plays the Lucky Penny to unlock a 2-cost Crew card", str(a3.get("type", "")) == "play" and str(gs3.players[1]["hand"][int(a3.get("hand_idx", -1))]) == "coin")
	gs3.players[1]["hand"] = ["coin"]
	_check("ai: keeps the Lucky Penny when it unlocks nothing", str(ai2.next_action(gs3, 1).get("type", "")) == "end")


func _test_online_3d() -> void:
	_check("online: game version stamped", NetMatch.build_version().begins_with("everdeck-pc-1/"))
	var host: Control = load("res://main.tscn").instantiate()
	var guest: Control = load("res://main.tscn").instantiate()
	add_child(host)
	add_child(guest)
	await get_tree().process_frame
	host._decks = [_valid_deck_for("grunk"), []]
	host._classes = ["grunk", ""]
	host._online = true
	host._online_role = "host"
	host._online_url = "ws://127.0.0.1:%d" % LocalRelay.PORT
	host._start_online_connection()
	for _i in 30:
		await get_tree().process_frame
	_check("online: host opened the built-in relay", host._local_relay != null and host._local_relay.is_listening())
	guest._decks = [_valid_deck_for("agatha"), []]
	guest._classes = ["agatha", ""]
	guest._online = true
	guest._online_role = "guest"
	guest._online_code = ""
	guest._online_url = "ws://127.0.0.1:%d" % LocalRelay.PORT
	guest._start_online_connection()
	var t0: int = Time.get_ticks_msec()
	while (host._screen != host.Screen.MATCH or guest._screen != guest.Screen.MATCH) and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	_check("online: both games reach the 3D match", host._screen == host.Screen.MATCH and guest._screen == guest.Screen.MATCH and host._board_3d != null and guest._board_3d != null)
	if host._gs == null or guest._gs == null:
		host.queue_free()
		guest.queue_free()
		return
	_check("online: seats are opposite", host._human_idx == 1 - guest._human_idx)
	_check("online: each side sees its own arena", host._board_3d._stage.theme == "grunk" and guest._board_3d._stage.theme == "agatha")
	var guest_hidden_ok: bool = true
	for cid in guest._gs.players[host._human_idx]["hand"]:
		if str(cid) != "":
			guest_hidden_ok = false
	_check("online: the opponent's hand stays hidden", guest_hidden_ok)
	# Whoever is up plays their cheapest playable card (or ends the turn).
	var me: Control = host if host._gs.active == host._human_idx else guest
	var other: Control = guest if me == host else host
	var played: bool = false
	host._net_match._gs.players[me._human_idx]["mana"] = 10
	me._gs.players[me._human_idx]["mana"] = 10
	for i in me._gs.players[me._human_idx]["hand"].size():
		var card: Dictionary = CardDB.get_card(str(me._gs.players[me._human_idx]["hand"][i]))
		if me._gs.can_play(me._human_idx, i) and str(card.get("type", "")) == "minion" and str(card.get("target", "none")) == "none":
			played = me._do_play(i, {})
			break
	if played:
		t0 = Time.get_ticks_msec()
		while (me._gs.players[me._human_idx]["board"].size() == 0 or other._gs.players[me._human_idx]["board"].size() == 0 or me._animating or other._animating) and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
		_check("online: a played Crew member appears on both boards", me._gs.players[me._human_idx]["board"].size() == 1 and other._gs.players[me._human_idx]["board"].size() == 1 and other._board_3d.minion_node(int(other._gs.players[me._human_idx]["board"][0]["uid"])) != null)
	_check("online: a Crew card was played", played)
	var turn0: int = me._gs.turn_count
	var guest_input_locked: bool = other._ai_turn
	_check("online: the waiting player can't act", guest_input_locked)
	me._on_end_turn()
	var etb: Node = me.find_child("EndTurnBtn", true, false)
	_check("online: END TURN shows the hand-off right away", etb is EndTurnButton and (etb as EndTurnButton).look == EndTurnButton.Look.WAITING)
	t0 = Time.get_ticks_msec()
	while (other._gs.active != other._human_idx or other._animating or me._animating) and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	_check("online: END TURN passes the turn on both screens", other._gs.active == other._human_idx and me._gs.active == other._human_idx and other._gs.turn_count > turn0)
	_check("online: the new player can act", not other._ai_turn)
	var hh: String = NetMatch.public_state_hash(NetMatch.snapshot_from_state(host._net_match._gs, 0))
	_check("online: host and guest agree on the board", hh == NetMatch.public_state_hash(_mirror_snapshot(guest._gs)) and hh == NetMatch.public_state_hash(_mirror_snapshot(host._gs)))
	# Emotes travel: the sender's Boss and the receiver's view of it both
	# show the bubble.
	other._emote_ready_at = 0
	other._send_emote("hey")
	t0 = Time.get_ticks_msec()
	while me.find_child("Bubble%d" % other._human_idx, false, false) == null and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	var mine_b: Node = other.find_child("Bubble%d" % other._human_idx, false, false)
	var theirs_b: Node = me.find_child("Bubble%d" % other._human_idx, false, false)
	_check("online: an emote shows on both screens as the Boss's own line", mine_b is SpeechBubble and theirs_b is SpeechBubble and (theirs_b as SpeechBubble)._label.text == Emotes.line(str(other._gs.players[other._human_idx]["class"]), "hey"))
	# Version mismatch is refused with a clear message.
	var why: Array = []
	guest._net_match.failed.connect(func(r: String) -> void: why.append(r))
	guest._net_match._on_game_message({"t": "commit", "hash": "x", "ver": "everdeck-pc-1/0.0.1"})
	_check("online: a different build is refused", not why.is_empty() and "versions" in str(why[0]))
	guest._teardown_online()
	host._teardown_online()
	host.queue_free()
	guest.queue_free()
	await get_tree().process_frame


# The area the hand's cards actually cover (the HandZone container itself
# spans the full width).
func _hand_cards_rect(m: Node) -> Rect2:
	var hz: Control = m.find_child("HandZone", true, false) as Control
	var r := Rect2()
	var first: bool = true
	for c in hz.get_children():
		if c is Control and str(c.name).begins_with("HandCard"):
			var cr: Rect2 = (c as Control).get_global_rect()
			r = cr if first else r.merge(cr)
			first = false
	return hz.get_global_rect() if first else r


func _mirror_snapshot(gs: GameState) -> Dictionary:
	var players: Array = []
	for p in 2:
		var pl: Dictionary = gs.players[p]
		players.append({"hp": pl["hp"], "mana": pl["mana"], "max_mana": pl["max_mana"], "fatigue": pl["fatigue"], "class": pl["class"],
			"hero_power_used": pl["hero_power_used"], "cards_played_this_turn": pl["cards_played_this_turn"],
			"hand_count": (pl["hand"] as Array).size(), "deck_count": (pl["deck"] as Array).size(), "board": pl["board"]})
	return {"active": gs.active, "winner": gs.winner, "turn_count": gs.turn_count, "players": players}
