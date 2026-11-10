extends RefCounted

# Mechanics pass, wave 1: one test group per new rule. Uses test-only
# cards (CardDB.add_test_card), so the real 340-card pool is untouched.
#
# Called from test_runner.gd: MechanicsTests.new().run(self)

var r  # the runner (has _check)


func _c(id: String, extra: Dictionary = {}) -> String:
	var c: Dictionary = {"id": id, "name": id, "class": "neutral", "cost": 1, "type": "minion",
		"attack": 2, "health": 2, "keywords": [], "text": "", "flavor": "", "art": "token"}
	c.merge(extra, true)
	CardDB.add_test_card(c)
	return id


func _gs() -> GameState:
	var gs := GameState.new()
	gs.set_seed(777)
	var deck: Array = []
	for _i in 30:
		deck.append("angry_squirrel")
	gs.setup(deck, deck.duplicate(), "neutral", "neutral")
	gs.active = 0
	for p in 2:
		gs.players[p]["hand"] = []
		gs.players[p]["board"] = []
		gs.players[p]["mana"] = 10
		gs.players[p]["max_mana"] = 10
	gs.take_events()
	return gs


# Put a Crew member straight onto a board, ready to attack.
func _put(gs: GameState, p: int, cid: String, ready: bool = true) -> Dictionary:
	gs._summon(p, CardDB.get_card(cid), not ready)
	var m: Dictionary = gs.players[p]["board"][gs.players[p]["board"].size() - 1]
	if ready:
		m["sick"] = false
		m["can_attack"] = true
		m["attacks_left"] = 2 if m.get("windfury", false) else 1
	gs._settle()
	return m


func _enemy(i: int) -> Dictionary:
	return {"kind": "minion", "player": 1, "board_idx": i}


func _face(p: int) -> Dictionary:
	return {"kind": "hero", "player": p, "board_idx": -1}


func _has_event(evs: Array, type: String) -> bool:
	for e in evs:
		if str(e.get("type", "")) == type:
			return true
	return false


func run(runner) -> void:
	r = runner
	_stunt_double()
	_backstage()
	_encore()
	_showstopper()
	_tip_jar()
	_heckle()
	_stage_fright()
	_on_credit()
	_triggers()
	_vibes()
	_online_snapshot()
	_ai()


func _stunt_double() -> void:
	var gs := _gs()
	_c("t_shield", {"attack": 1, "health": 3, "keywords": ["shield"]})
	_c("t_hitter", {"attack": 2, "health": 5})
	var a: Dictionary = _put(gs, 0, "t_hitter")
	var s: Dictionary = _put(gs, 1, "t_shield")
	gs.take_events()
	gs.attack(0, 0, _enemy(0))
	r._check("Stunt Double: first hit does nothing", int(s["health"]) == 3 and not s["shield"])
	r._check("Stunt Double: shield_popped event", _has_event(gs.take_events(), "shield_popped"))
	r._check("Stunt Double: the attacker still takes damage", int(a["health"]) == 4)
	gs.players[0]["board"][0]["can_attack"] = true
	gs.players[0]["board"][0]["attacks_left"] = 1
	gs.attack(0, 0, _enemy(0))
	r._check("Stunt Double: second hit lands", int(s["health"]) == 1)


func _backstage() -> void:
	var gs := _gs()
	_c("t_sneak", {"attack": 3, "health": 2, "keywords": ["stealth", "taunt"]})
	_c("t_bolt", {"type": "spell", "effect": "damage", "effect_value": 2, "target": "any_enemy", "attack": 0, "health": 0})
	_put(gs, 0, "t_hitter")
	_put(gs, 1, "t_sneak")
	var targets: Array = gs.valid_attack_targets(0)
	r._check("Backstage: can't be attacked, and its Bouncer guards nothing", targets.size() == 1 and targets[0]["kind"] == "hero")
	gs.players[0]["hand"] = ["t_bolt"]
	r._check("Backstage: can't be targeted by a Trick", not gs.play_card(0, 0, _enemy(0)))
	r._check("Backstage: card target options skip it", gs.card_target_options(0, CardDB.get_card("t_bolt")).size() == 1)
	gs.end_turn()
	var sneak: Dictionary = gs.players[1]["board"][0]
	gs.attack(1, 0, _face(0))
	r._check("Backstage: ends when it attacks", not sneak["stealth"] and int(gs.players[0]["hp"]) == 27)


func _encore() -> void:
	var gs := _gs()
	_c("t_twice", {"attack": 2, "health": 4, "keywords": ["windfury"]})
	_c("t_twice_rush", {"attack": 1, "health": 1, "keywords": ["windfury", "charge"]})
	_put(gs, 0, "t_twice")
	r._check("Encore: first attack", gs.attack(0, 0, _face(1)))
	r._check("Encore: second attack", gs.attack(0, 0, _face(1)))
	r._check("Encore: no third attack", not gs.attack(0, 0, _face(1)))
	r._check("Encore: 4 damage dealt", int(gs.players[1]["hp"]) == 26)
	gs.players[0]["hand"] = ["t_twice_rush"]
	gs.play_card(0, 0)
	var m: Dictionary = gs.players[0]["board"][1]
	r._check("Encore + Hustle: two attacks the turn it's played", int(m["attacks_left"]) == 2)
	gs.end_turn()
	gs.end_turn()
	r._check("Encore: two attacks again next turn", int(gs.players[0]["board"][0]["attacks_left"]) == 2)


func _showstopper() -> void:
	var gs := _gs()
	_c("t_poison", {"attack": 1, "health": 1, "keywords": ["poison"]})
	_c("t_giant", {"attack": 1, "health": 8})
	var giant: Dictionary = _put(gs, 1, "t_giant")
	_put(gs, 0, "t_poison")
	gs.attack(0, 0, _enemy(0))
	r._check("Showstopper: destroys any Crew it damages", gs.players[1]["board"].is_empty())
	r._check("Showstopper: dies in the trade too", gs.players[0]["board"].is_empty())
	var gs2 := _gs()
	_put(gs2, 1, "t_shield")
	_put(gs2, 0, "t_poison")
	gs2.attack(0, 0, _enemy(0))
	r._check("Showstopper vs Stunt Double: the shield takes it, no kill", gs2.players[1]["board"].size() == 1)
	var gs3 := _gs()
	_put(gs3, 1, "t_giant")
	var defender: Dictionary = _put(gs3, 0, "t_giant")
	gs3.end_turn()
	gs3.end_turn()
	gs3.players[1]["board"].clear()
	_put(gs3, 1, "t_poison")
	gs3.active = 1
	gs3.attack(1, 0, {"kind": "minion", "player": 0, "board_idx": 0})
	r._check("Showstopper: works when it's attacked too", gs3.players[0]["board"].is_empty() and defender["health"] <= 0)


func _tip_jar() -> void:
	var gs := _gs()
	_c("t_leech", {"attack": 3, "health": 3, "keywords": ["lifesteal"]})
	_c("t_leech_cry", {"attack": 1, "health": 1, "keywords": ["lifesteal"], "effect": "damage", "effect_value": 2, "target": "enemy_hero"})
	gs.players[0]["hp"] = 20
	_put(gs, 0, "t_leech")
	gs.attack(0, 0, _face(1))
	r._check("Tip Jar: attack damage heals your Boss", int(gs.players[0]["hp"]) == 23 and int(gs.players[1]["hp"]) == 27)
	gs.players[0]["hand"] = ["t_leech_cry"]
	gs.play_card(0, 0, _face(1))
	r._check("Tip Jar: its own Entrance damage heals too", int(gs.players[0]["hp"]) == 25)
	gs.players[0]["hp"] = 30
	gs.players[0]["board"][0]["can_attack"] = true
	gs.players[0]["board"][0]["attacks_left"] = 1
	gs.attack(0, 0, _face(1))
	r._check("Tip Jar: never heals above 30", int(gs.players[0]["hp"]) == 30)


func _heckle() -> void:
	var gs := _gs()
	_c("t_hecklee", {"attack": 2, "health": 3, "keywords": ["taunt", "shield"], "deathrattle": "damage", "deathrattle_value": 5, "deathrattle_target": "enemy_hero",
		"triggers": [{"when": "end_of_turn", "effect": "damage", "value": 1, "target": "enemy_hero"}]})
	_c("t_heckle", {"type": "spell", "effect": "silence", "target": "enemy_minion", "attack": 0, "health": 0})
	var m: Dictionary = _put(gs, 1, "t_hecklee")
	gs._apply_buff(1, m, 2)
	gs.players[0]["hand"] = ["t_heckle"]
	gs.play_card(0, 0, _enemy(0))
	r._check("Heckle: removes Bouncer and Stunt Double", not m["taunt"] and not m["shield"] and m["silenced"])
	r._check("Heckle: removes buffs (back to printed 2/3)", int(m["attack"]) == 2 and int(m["max_health"]) == 3 and int(m["health"]) == 3)
	gs.end_turn()
	gs.end_turn()
	r._check("Heckle: its end-of-turn effect is gone", int(gs.players[0]["hp"]) == 30)
	gs.players[0]["hand"] = ["t_bolt", "t_bolt"]
	gs.play_card(0, 0, _enemy(0))
	gs.play_card(0, 0, _enemy(0))
	r._check("Heckle: its Final Bow is gone", gs.players[1]["board"].is_empty() and int(gs.players[1]["hp"]) == 30 and int(gs.players[0]["hp"]) == 30)


func _stage_fright() -> void:
	var gs := _gs()
	_c("t_freeze", {"type": "spell", "effect": "freeze", "target": "enemy_minion", "attack": 0, "health": 0})
	_put(gs, 1, "t_giant")
	gs.players[0]["hand"] = ["t_freeze"]
	gs.play_card(0, 0, _enemy(0))
	r._check("Stage Fright: frozen event", _has_event(gs.take_events(), "frozen"))
	gs.end_turn()
	r._check("Stage Fright: it can't attack on its next turn", not gs.can_attack(1, 0))
	gs.end_turn()
	gs.end_turn()
	r._check("Stage Fright: wears off after that turn", gs.can_attack(1, 0))
	# Frozen on its own turn: misses the rest of this turn AND the next.
	var gs2 := _gs()
	var mine: Dictionary = _put(gs2, 0, "t_giant")
	gs2._resolve_effect(1, "freeze", 0, {"kind": "minion", "player": 0, "board_idx": 0})
	r._check("Stage Fright on your own turn: can't attack now", not gs2.can_attack(0, 0))
	gs2.end_turn()
	gs2.end_turn()
	r._check("Stage Fright on your own turn: or next turn", not gs2.can_attack(0, 0) and int(mine["frozen"]) == 1)


func _on_credit() -> void:
	var gs := _gs()
	_c("t_credit", {"cost": 1, "attack": 4, "health": 4, "overload": 2})
	gs.players[0]["max_mana"] = 5
	gs.players[0]["mana"] = 5
	gs.players[0]["hand"] = ["t_credit"]
	gs.play_card(0, 0)
	r._check("On Credit: owed shows this turn", int(gs.players[0]["overload_next"]) == 2)
	gs.end_turn()
	gs.end_turn()
	r._check("On Credit: next turn has 2 less mana", int(gs.players[0]["max_mana"]) == 6 and int(gs.players[0]["mana"]) == 4 and int(gs.players[0]["overload_locked"]) == 2)
	gs.end_turn()
	gs.end_turn()
	r._check("On Credit: paid off after one turn", int(gs.players[0]["mana"]) == 7 and int(gs.players[0]["overload_locked"]) == 0)


func _triggers() -> void:
	# Whenever you play a Trick: +1 attack.
	var gs := _gs()
	_c("t_wyrm", {"attack": 1, "health": 3, "triggers": [{"when": "friendly_trick_played", "effect": "buff_attack", "value": 1, "target": "self"}]})
	_c("t_spark", {"type": "spell", "cost": 0, "effect": "damage", "effect_value": 1, "target": "enemy_hero", "attack": 0, "health": 0})
	var w: Dictionary = _put(gs, 0, "t_wyrm")
	gs.players[0]["hand"] = ["t_spark", "t_spark", "angry_squirrel"]
	gs.take_events()
	gs.play_card(0, 0, _face(1))
	r._check("Trigger: emits a trigger event", _has_event(gs.take_events(), "trigger"))
	gs.play_card(0, 0, _face(1))
	gs.play_card(0, 0)
	r._check("Trigger: whenever you play a Trick (2 Tricks, 1 Crew = +2)", int(w["attack"]) == 3)
	# At the end of your turn: 1 damage to the enemy Boss.
	var gs2 := _gs()
	_c("t_ticker", {"attack": 0, "health": 3, "triggers": [{"when": "end_of_turn", "effect": "damage", "value": 1, "target": "enemy_hero"}]})
	_put(gs2, 0, "t_ticker")
	gs2.end_turn()
	r._check("Trigger: end of your turn", int(gs2.players[1]["hp"]) == 29)
	gs2.end_turn()
	r._check("Trigger: not at the end of the enemy's turn", int(gs2.players[1]["hp"]) == 29)
	# At the start of your turn: heal 2.
	var gs3 := _gs()
	_c("t_morning", {"attack": 0, "health": 3, "triggers": [{"when": "start_of_turn", "effect": "heal_hero", "value": 2, "target": "none"}]})
	_put(gs3, 0, "t_morning")
	gs3.players[0]["hp"] = 20
	gs3.end_turn()
	gs3.end_turn()
	r._check("Trigger: start of your turn", int(gs3.players[0]["hp"]) == 22)
	# Whenever your Boss is healed: +1 attack (Agatha's engine).
	var gs4 := _gs()
	_c("t_granny", {"attack": 1, "health": 4, "triggers": [{"when": "boss_healed", "effect": "buff_attack", "value": 1, "target": "self"}]})
	_c("t_tea", {"type": "spell", "cost": 0, "effect": "heal_hero", "effect_value": 3, "target": "none", "attack": 0, "health": 0})
	var g: Dictionary = _put(gs4, 0, "t_granny")
	gs4.players[0]["hp"] = 20
	gs4.players[0]["hand"] = ["t_tea", "t_tea"]
	gs4.play_card(0, 0)
	gs4.play_card(0, 0)
	r._check("Trigger: whenever your Boss is healed", int(g["attack"]) == 3)
	gs4.players[0]["hp"] = 30
	gs4.players[0]["hand"] = ["t_tea"]
	gs4.play_card(0, 0)
	r._check("Trigger: no heal at full Health, no trigger", int(g["attack"]) == 3)
	# Whenever a friendly Crew dies: draw a card.
	var gs5 := _gs()
	_c("t_mourner", {"attack": 1, "health": 5, "triggers": [{"when": "friendly_crew_died", "effect": "draw", "value": 1, "target": "none"}]})
	_put(gs5, 0, "t_mourner")
	_put(gs5, 0, "t_poison")
	_put(gs5, 1, "t_giant")
	var hand_before: int = gs5.players[0]["hand"].size()
	gs5.attack(0, 1, _enemy(0))
	r._check("Trigger: whenever a friendly Crew dies", gs5.players[0]["hand"].size() == hand_before + 1)
	# Whenever this attacks: draw (Barnacle's plunder).
	var gs6 := _gs()
	_c("t_plunder", {"attack": 2, "health": 2, "triggers": [{"when": "attacks", "effect": "draw", "value": 1, "target": "none"}]})
	_put(gs6, 0, "t_plunder")
	gs6.attack(0, 0, _face(1))
	r._check("Trigger: whenever this attacks", gs6.players[0]["hand"].size() == 1)
	# Whenever you summon: buff it? Here: +1 attack to self per summon.
	var gs7 := _gs()
	_c("t_captain", {"attack": 1, "health": 3, "triggers": [{"when": "friendly_summon", "effect": "buff_attack", "value": 1, "target": "self"}]})
	var cap: Dictionary = _put(gs7, 0, "t_captain")
	gs7.players[0]["class"] = "barnacle"
	gs7.use_hero_power(0)
	r._check("Trigger: whenever you summon (not itself)", int(cap["attack"]) == 2)
	# Whenever one of your random effects fires (Larry's engine).
	var gs8 := _gs()
	_c("t_gambler", {"attack": 1, "health": 3, "triggers": [{"when": "random_fired", "effect": "buff_attack", "value": 1, "target": "self"}]})
	var gam: Dictionary = _put(gs8, 0, "t_gambler")
	gs8.players[0]["class"] = "larry"
	gs8.use_hero_power(0)
	r._check("Trigger: whenever a random effect fires", int(gam["attack"]) == 2)
	# Triggers don't set off triggers: a buff-on-buff pair can't loop.
	var gs9 := _gs()
	_c("t_loop", {"attack": 1, "health": 3, "triggers": [{"when": "friendly_buffed", "effect": "buff_friendly", "value": 1, "target": "friendly_minion"}]})
	var l1: Dictionary = _put(gs9, 0, "t_loop")
	var l2: Dictionary = _put(gs9, 0, "t_loop")
	gs9._apply_buff(0, l1, 1)
	gs9._settle()
	r._check("Trigger: no loops (one buff sets off each listener once)", int(l1["attack"]) + int(l2["attack"]) <= 6)
	# Whenever this takes damage and survives (Grunk's fuses).
	var gs10 := _gs()
	_c("t_angry", {"attack": 1, "health": 5, "triggers": [{"when": "damaged", "effect": "buff_attack", "value": 2, "target": "self"}]})
	var ang: Dictionary = _put(gs10, 1, "t_angry")
	_put(gs10, 0, "t_hitter")
	gs10.attack(0, 0, _enemy(0))
	r._check("Trigger: whenever this takes damage", int(ang["attack"]) == 3)
	# A trigger holder that died first doesn't fire.
	var gs11 := _gs()
	_put(gs11, 0, "t_ticker")
	gs11.players[0]["board"][0]["health"] = 0
	gs11._settle()
	gs11.end_turn()
	r._check("Trigger: dead holders don't fire", int(gs11.players[1]["hp"]) == 30)


func _vibes() -> void:
	var gs := _gs()
	_c("t_banner", {"attack": 1, "health": 2, "vibe": {"attack": 1, "health": 1, "who": "other_friendly"}})
	var a: Dictionary = _put(gs, 0, "t_hitter")
	var b: Dictionary = _put(gs, 0, "t_banner")
	r._check("Vibe: other friendly Crew get +1/+1", int(a["attack"]) == 3 and int(a["health"]) == 6 and int(a["max_health"]) == 6)
	r._check("Vibe: not the source itself", int(b["attack"]) == 1)
	var late: Dictionary = _put(gs, 0, "t_hitter")
	r._check("Vibe: Crew played later get it too", int(late["attack"]) == 3)
	var enemy_m: Dictionary = _put(gs, 1, "t_hitter")
	r._check("Vibe: enemy Crew don't", int(enemy_m["attack"]) == 2)
	# Damage taken stays taken while the Vibe is up.
	a["health"] = 2
	gs._settle()
	r._check("Vibe: damage taken stays", int(a["health"]) == 2)
	# The Vibe source dies: bonuses go, damaged Crew don't die from it.
	b["health"] = 0
	gs._settle()
	r._check("Vibe: gone when the source dies", int(a["attack"]) == 2 and int(a["max_health"]) == 5)
	r._check("Vibe: losing it never kills", int(a["health"]) == 2 and gs.players[0]["board"].size() == 2)
	# Heckle on the source turns it off.
	var gs2 := _gs()
	var x: Dictionary = _put(gs2, 1, "t_hitter")
	_put(gs2, 1, "t_banner")
	gs2.players[0]["hand"] = ["t_heckle"]
	gs2.play_card(0, 0, _enemy(1))
	r._check("Vibe: Heckle on the source turns it off", int(x["attack"]) == 2 and int(x["max_health"]) == 5)
	# Deckhands only (Barnacle's engine).
	var gs3 := _gs()
	_c("t_qm", {"attack": 3, "health": 3, "class": "barnacle", "vibe": {"attack": 1, "health": 0, "who": "friendly_deckhands"}})
	gs3.players[0]["class"] = "barnacle"
	_put(gs3, 0, "t_qm")
	var other: Dictionary = _put(gs3, 0, "t_hitter")
	gs3.use_hero_power(0)
	var dh: Dictionary = gs3.players[0]["board"][2]
	r._check("Vibe: Deckhands only", int(dh["attack"]) == 2 and int(other["attack"]) == 2)
	# Heckle on a Crew member with a Vibe bonus: back to printed, Vibe re-applies.
	var gs4 := _gs()
	var y: Dictionary = _put(gs4, 1, "t_hitter")
	_put(gs4, 1, "t_banner")
	gs4.players[0]["hand"] = ["t_heckle"]
	gs4.play_card(0, 0, _enemy(0))
	r._check("Vibe: a Heckled Crew member still gets others' Vibes", int(y["attack"]) == 3)


func _online_snapshot() -> void:
	# The guest only sees what the host's snapshot carries.
	var gs := _gs()
	var m: Dictionary = _put(gs, 0, "t_shield")
	m["frozen"] = 1
	_put(gs, 0, "t_banner")
	gs.players[0]["overload_next"] = 2
	var snap: Dictionary = NetMatch.snapshot_from_state(gs, 1)
	var nm := NetMatch.new()
	nm.mirror = GameState.new()
	nm._apply_snapshot_to_mirror(snap)
	var mm: Dictionary = nm.mirror.players[0]["board"][0]
	r._check("Online: Stunt Double, Stage Fright and Vibe bonus reach the guest", mm["shield"] and int(mm["frozen"]) == 1 and int(mm["vibe_atk"]) == 1 and int(mm["attack"]) == 2)
	r._check("Online: On Credit reaches the guest", int(nm.mirror.players[0]["overload_next"]) == 2)
	nm.free()


# Let the computer play out its turn.
func _ai_turn(gs: GameState, me: int) -> void:
	var ai := AIPlayer.new()
	ai.sloppiness = 0.0
	for _i in 30:
		var a: Dictionary = ai.next_action(gs, me)
		if str(a.get("type", "")) == "end":
			return
		AIPlayer.apply(gs, me, a)


func _ai() -> void:
	# Pops Stunt Double with the small one, then trades the big one in.
	var gs := _gs()
	_c("t_one", {"attack": 1, "health": 1})
	_c("t_five", {"attack": 5, "health": 5})
	_c("t_wall", {"attack": 3, "health": 3, "keywords": ["shield", "taunt"]})
	_put(gs, 0, "t_one")
	_put(gs, 0, "t_five")
	_put(gs, 1, "t_wall")
	_ai_turn(gs, 0)
	r._check("Bot: pops Stunt Double with a small Crew member, then kills it", gs.players[1]["board"].is_empty() and gs.players[0]["board"].size() == 1 and str(gs.players[0]["board"][0]["card_id"]) == "t_five")
	# Prefers a Crew member that keeps paying off over plain stats.
	var gs2 := _gs()
	_c("t_plain", {"cost": 3, "attack": 3, "health": 3})
	_c("t_engine", {"cost": 3, "attack": 2, "health": 2, "triggers": [{"when": "end_of_turn", "effect": "damage", "value": 2, "target": "enemy_hero"}]})
	gs2.players[0]["mana"] = 3
	gs2.players[0]["hand"] = ["t_plain", "t_engine"]
	_ai_turn(gs2, 0)
	r._check("Bot: values an end-of-turn engine over plain stats", gs2.players[0]["board"].size() == 1 and str(gs2.players[0]["board"][0]["card_id"]) == "t_engine")
	# Kills the engine before it fires again.
	var gs3 := _gs()
	_c("t_three", {"attack": 3, "health": 3})
	_put(gs3, 1, "t_engine")
	_put(gs3, 0, "t_three")
	gs3.players[1]["hp"] = 30
	_ai_turn(gs3, 0)
	r._check("Bot: kills an enemy engine instead of going face", gs3.players[1]["board"].is_empty())
