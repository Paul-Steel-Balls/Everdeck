extends SceneTree

# Burst checker: the most damage each Boss can deal to the enemy Boss in
# ONE turn, from hand, through the real game rules. The bots play one move
# at a time and never set up a combo turn; players do. This finds the
# combo turns before players do.
#
#   godot --headless --path . -s res://tools/sim_burst.gd
#
# Model: your board and theirs start empty (nothing set up the turn
# before); you hold any cards your Boss may put in a deck (copy limits
# kept, at most a full hand); you have N mana and your Signature Move.
# A beam search tries play orders and keeps the best partial turns.
#
# Environment: BURST_MANA (comma list, default 6,7,8,9,10), BURST_BEAM
# (default 250), BURST_CLASSES, BURST_OUT (JSON path).

const ALL_CLASSES: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
const ENEMY_HP: int = 30


func _init() -> void:
	var manas: Array = []
	for m in _env("BURST_MANA", "6,7,8,9,10").split(","):
		manas.append(int(m))
	var beam: int = int(_env("BURST_BEAM", "250"))
	var classes: Array = ALL_CLASSES
	if _env("BURST_CLASSES", "") != "":
		classes = Array(_env("BURST_CLASSES", "").split(","))
	var out: Array = []
	for cls in classes:
		for mana in manas:
			var best: Dictionary = _search(cls, int(mana), beam)
			out.append({"class": cls, "mana": mana, "damage": best["damage"], "line": best["line"]})
			print("%-9s %2d mana: %2d damage  %s" % [cls, mana, best["damage"], ", ".join(best["names"])])
	if _env("BURST_OUT", "") != "":
		var f := FileAccess.open(_env("BURST_OUT", ""), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " "))
		f.close()
	quit()


func _env(k: String, d: String) -> String:
	var v: String = OS.get_environment(k)
	return v if v != "" else d


func _fresh(cls: String, mana: int) -> GameState:
	var gs := GameState.new()
	gs.set_seed(7)
	var opp: String = "agatha" if cls != "agatha" else "grunk"
	gs.setup(AIPlayer.build_deck(cls, 1), AIPlayer.build_deck(opp, 2), cls, opp)
	var p: Dictionary = gs.players[0]
	p["hand"] = []
	p["board"] = []
	p["mana"] = mana
	p["max_mana"] = mana
	p["hero_power_used"] = false
	p["cards_played_this_turn"] = 0
	gs.players[1]["board"] = []
	gs.players[1]["hp"] = ENEMY_HP
	return gs


# A partial turn: the game so far, what was played, and copies used.
func _search(cls: String, mana: int, beam: int) -> Dictionary:
	var pool: Array = []
	for c in CardDB.cards_for_class(cls):
		if int(c["cost"]) <= mana:
			pool.append(c)
	var start := {"gs": _fresh(cls, mana), "line": [], "used": {}, "power": false}
	var frontier: Array = [start]
	var best: Dictionary = {"damage": 0, "line": [], "names": []}
	for _depth in GameState.MAX_HAND:
		var next: Array = []
		var seen: Dictionary = {}
		for st in frontier:
			for c in pool:
				var cid: String = str(c["id"])
				if int(st["used"].get(cid, 0)) >= CardDB.max_copies(c):
					continue
				var ns: Variant = _play(st, cid)
				if ns != null:
					_add(next, seen, ns)
			if not st["power"]:
				var ps: Variant = _power(st)
				if ps != null:
					_add(next, seen, ps)
		if next.is_empty():
			break
		next.sort_custom(func(a, b) -> bool: return _score(a) > _score(b))
		frontier = next.slice(0, beam)
		for st2 in frontier:
			var dmg: int = ENEMY_HP - int(st2["gs"].players[1]["hp"])
			if dmg > best["damage"]:
				best = {"damage": dmg, "line": st2["line"], "names": _names(st2["line"])}
	return best


func _names(line: Array) -> Array:
	var n: Array = []
	for cid in line:
		n.append("Signature Move" if cid == "*power" else str(CardDB.get_card(cid).get("name", cid)))
	return n


func _key(st: Dictionary) -> String:
	var l: Array = st["line"].duplicate()
	l.sort()
	var g: GameState = st["gs"]
	return "%s|%d|%d" % [",".join(l), g.players[0]["mana"], g.players[1]["hp"]]


func _add(next: Array, seen: Dictionary, st: Dictionary) -> void:
	var k: String = _key(st)
	if seen.has(k):
		return
	seen[k] = true
	next.append(st)


# Damage done, plus what's left to spend and the combo counter, so a
# turn that sets up (free cards, mana) isn't cut before it pays off.
func _score(st: Dictionary) -> float:
	var g: GameState = st["gs"]
	var dmg: float = float(ENEMY_HP - int(g.players[1]["hp"]))
	return dmg + 1.2 * float(g.players[0]["mana"]) + 1.5 * float(g.players[0]["cards_played_this_turn"])


func _copy(st: Dictionary) -> Dictionary:
	var g: GameState = st["gs"].clone()
	g.set_seed(11)
	return {"gs": g, "line": st["line"].duplicate(), "used": st["used"].duplicate(), "power": st["power"]}


func _play(st: Dictionary, cid: String) -> Variant:
	var g0: GameState = st["gs"]
	if g0.winner != -1 or g0.players[0]["hand"].size() >= GameState.MAX_HAND:
		return null
	var card: Dictionary = CardDB.get_card(cid)
	if int(g0.players[0]["mana"]) < int(card["cost"]):
		return null
	var ns: Dictionary = _copy(st)
	var g: GameState = ns["gs"]
	g.players[0]["hand"].append(cid)
	var idx: int = g.players[0]["hand"].size() - 1
	var target: Dictionary = {}
	var opts: Array = g.card_target_options(0, card)
	for t in opts:
		if str(t.get("kind", "")) == "hero" and int(t.get("player", -1)) == 1:
			target = t
	if target.is_empty() and not opts.is_empty() and card["type"] != "minion":
		return null  # a Trick that can only hit Crew does nothing to the Boss
	if not g.play_card(0, idx, target):
		return null
	_swing(g)
	ns["line"].append(cid)
	ns["used"][cid] = int(ns["used"].get(cid, 0)) + 1
	return ns


func _power(st: Dictionary) -> Variant:
	var ns: Dictionary = _copy(st)
	var g: GameState = ns["gs"]
	var opts: Array = g.hero_power_target_options(0)
	var target: Dictionary = {}
	for t in opts:
		if str(t.get("kind", "")) == "hero" and int(t.get("player", -1)) == 1:
			target = t
	if not opts.is_empty() and target.is_empty():
		for t2 in opts:
			target = t2
			break
	if not g.use_hero_power(0, target):
		return null
	_swing(g)
	ns["line"].append("*power")
	ns["power"] = true
	return ns


# Every Crew member that can attack this turn (Hustle) hits the enemy Boss.
func _swing(g: GameState) -> void:
	for b in g.players[0]["board"].size():
		if g.winner != -1:
			return
		if g.can_attack(0, b):
			g.attack(0, b, {"kind": "hero", "player": 1, "board_idx": -1})
