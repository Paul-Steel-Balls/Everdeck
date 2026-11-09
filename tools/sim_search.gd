extends SceneTree

# Deck search: hill-climb one class's 30-card list against the field to
# find the strongest deck the computer can pilot, before players do.
#
#   SEARCH_CLASS=grunk godot --headless --path . -s res://tools/sim_search.gd
#
# Environment:
#   SEARCH_CLASS  class to tune (required)
#   SEARCH_ITERS  mutations to try (default 100)
#   SEARCH_GAMES  games per evaluation (default 150)
#   SEARCH_FIELD  optional JSON {class: [30 ids]} or {class: [[30 ids], ...]}:
#                 opponents play these lists (later rounds: the tuned field,
#                 or every earlier round's lists so the search converges)
#   SEARCH_SEED   base seed (default 7)
#   SEARCH_OUT    output JSON path
#
# Each challenger plays the SAME games (same seeds, opponents, seats) as
# the current champion, so the comparison isn't drowned in luck. The seed
# set is refreshed every REFRESH steps so the list can't overfit to it.

const SimLib = preload("res://tools/sim_lib.gd")
const ALL_CLASSES: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
const REFRESH: int = 15
const STARTS: int = 6

var cls: String
var games: int
var field: Dictionary = {}
var ai := AIPlayer.new()
var rng := RandomNumberGenerator.new()
var pool: Array = []
var opponents: Array = []


func _init() -> void:
	SimLib.ensure_patch()
	cls = OS.get_environment("SEARCH_CLASS")
	var iters: int = int(_env("SEARCH_ITERS", "100"))
	games = int(_env("SEARCH_GAMES", "150"))
	var base: int = int(_env("SEARCH_SEED", "7"))
	var out_path: String = _env("SEARCH_OUT", "user://search_%s.json" % cls)
	if _env("SEARCH_FIELD", "") != "":
		field = JSON.parse_string(FileAccess.get_file_as_string(_env("SEARCH_FIELD", "")))
	ai.sloppiness = 0.0
	rng.seed = base * 31 + hash(cls)
	pool = CardDB.cards_for_class(cls)
	for c in ALL_CLASSES:
		if c != cls:
			opponents.append(c)
	var t0: int = Time.get_ticks_msec()
	var seeds: Array = _seed_set(base * 100000)
	var champ: Array = []
	var champ_score: float = -1.0
	# SEARCH_START: a JSON {class: [30 ids]} whose list for this class is
	# the first champion (round 2 starts from round 1's tuned list).
	var starts: Array = []
	if _env("SEARCH_START", "") != "":
		var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_env("SEARCH_START", "")))
		if sd.has(cls):
			starts.append(Array(sd[cls]))
	for s in STARTS - starts.size() * (STARTS - 1):
		starts.append(AIPlayer.build_deck(cls, base * 977 + s))
	for d in starts:
		var s: int = starts.find(d)
		var sc: float = _score(d, seeds)
		printerr("[search %s] start %d: %.3f" % [cls, s, sc])
		if sc > champ_score:
			champ = d
			champ_score = sc
	var start_score: float = champ_score
	var history: Array = [[0, champ_score]]
	var accepted: int = 0
	for it in range(1, iters + 1):
		if it % REFRESH == 0:
			seeds = _seed_set(base * 100000 + it * 1000)
			champ_score = _score(champ, seeds)
		var cand: Array = _mutate(champ)
		var sc2: float = _score(cand, seeds)
		if sc2 > champ_score:
			champ = cand
			champ_score = sc2
			accepted += 1
		history.append([it, champ_score])
		if it % 5 == 0:
			printerr("[search %s] iter %d  champ %.3f  accepted %d  %.0fs" % [cls, it, champ_score, accepted, (Time.get_ticks_msec() - t0) / 1000.0])
	# Final, unbiased check on games the search never saw: champion vs a
	# random deck of the same class over the same fresh games.
	var final_seeds: Array = []
	for i in games * 3:
		final_seeds.append(base * 7777777 + 1 + i * 104729)
	var final_wr: float = _score(champ, final_seeds)
	var baseline_wr: float = _score(AIPlayer.build_deck(cls, base * 31337), final_seeds)
	var counts: Dictionary = {}
	for cid in champ:
		counts[cid] = int(counts.get(cid, 0)) + 1
	var out := {"class": cls, "deck": champ, "counts": counts, "final_wr": final_wr, "random_deck_wr": baseline_wr,
		"start_wr": start_score, "iters": iters, "games": games, "accepted": accepted, "history": history,
		"vs_field": "tuned" if not field.is_empty() else "random"}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	printerr("[search %s] done: tuned %.3f vs random deck %.3f on fresh games, %.0fs" % [cls, final_wr, baseline_wr, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


func _env(k: String, d: String) -> String:
	var v: String = OS.get_environment(k)
	return v if v != "" else d


func _seed_set(base: int) -> Array:
	var s: Array = []
	for i in games:
		s.append(base + 1 + i * 7919)
	return s


# Win rate of `deck` over the games in `seeds`: opponents cycle through
# the other five classes, seats alternate.
func _score(deck: Array, seeds: Array) -> float:
	var w: float = 0.0
	for i in seeds.size():
		var sd: int = int(seeds[i])
		var opp: String = opponents[i % opponents.size()]
		var od: Array = _field_deck(opp, i, sd)
		var first: bool = (i / opponents.size()) % 2 == 0
		var rec: Dictionary
		if first:
			rec = SimLib.play(ai, cls, opp, deck, od, sd)
			w += 0.5 if rec["w"] == -1 else (1.0 if rec["w"] == 0 else 0.0)
		else:
			rec = SimLib.play(ai, opp, cls, od, deck, sd)
			w += 0.5 if rec["w"] == -1 else (1.0 if rec["w"] == 1 else 0.0)
	return w / float(seeds.size())


# The opponent's list for game i: a fixed list, one of several (a field
# given as {class: [[30 ids], [30 ids], ...]} rotates through them), or a
# fresh random deck when the field has none for that class.
func _field_deck(opp: String, i: int, sd: int) -> Array:
	if not field.has(opp):
		return AIPlayer.build_deck(opp, sd + 11)
	var f: Array = Array(field[opp])
	if not f.is_empty() and f[0] is Array:
		return Array(f[(i / opponents.size()) % f.size()])
	return f


# Swap 1-3 cards for others from the class pool, keeping the deck legal.
func _mutate(deck: Array) -> Array:
	var d: Array = deck.duplicate()
	var n: int = [1, 1, 2, 2, 3][rng.randi_range(0, 4)]
	for _k in n:
		d.remove_at(rng.randi_range(0, d.size() - 1))
		var guard: int = 0
		while d.size() < GameState.DECK_SIZE and guard < 500:
			guard += 1
			var c: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			if d.count(str(c["id"])) < CardDB.max_copies(c):
				d.append(str(c["id"]))
	return d
