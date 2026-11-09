extends SceneTree

# Best-list picker: for each Boss, which of many known lists does best
# against everyone else's known lists? One hill-climb per Boss is noisy
# (a lucky or unlucky search moves a Boss 10+ points); picking from a
# shared pool of every list found so far is much steadier.
#
#   PICK_POOL=pool.json godot --headless --path . -s res://tools/sim_pick.gd
#
# Environment:
#   PICK_POOL     JSON {class: [[30 ids], ...]}: the candidate lists
#   PICK_FIELD    optional JSON, same shape: the opponents (default: the pool)
#   PICK_CLASSES  comma list of classes to score (default all six)
#   PICK_GAMES    games per candidate (default 300)
#   PICK_SEED     base seed (default 5)
#   PICK_OUT      output JSON {class: [win rate per candidate, ...]}
#   SIM_PATCH     what-if patch (see sim_lib.gd)
#
# Every candidate of a class plays the SAME games (seeds, opponents,
# seats), so their scores compare fairly.

const SimLib = preload("res://tools/sim_lib.gd")
const ALL_CLASSES: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]


func _env(k: String, d: String) -> String:
	var v: String = OS.get_environment(k)
	return v if v != "" else d


func _init() -> void:
	SimLib.ensure_patch()
	var pool: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_env("PICK_POOL", "")))
	var field: Dictionary = pool
	if _env("PICK_FIELD", "") != "":
		field = JSON.parse_string(FileAccess.get_file_as_string(_env("PICK_FIELD", "")))
	var classes: Array = ALL_CLASSES
	if _env("PICK_CLASSES", "") != "":
		classes = Array(_env("PICK_CLASSES", "").split(","))
	var games: int = int(_env("PICK_GAMES", "300"))
	var base: int = int(_env("PICK_SEED", "5"))
	var ai := AIPlayer.new()
	ai.sloppiness = 0.0
	var out: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	for cls in classes:
		var opps: Array = []
		for c in ALL_CLASSES:
			if c != cls and field.has(c):
				opps.append(c)
		var scores: Array = []
		for deck in pool[cls]:
			var w: float = 0.0
			for i in games:
				var sd: int = base * 1000003 + i * 7919 + hash(cls) % 1000
				var opp: String = opps[i % opps.size()]
				var lists: Array = field[opp]
				var od: Array = Array(lists[(i / opps.size()) % lists.size()])
				if (i / opps.size()) % 2 == 0:
					var r: Dictionary = SimLib.play(ai, cls, opp, Array(deck), od, sd)
					w += 0.5 if r["w"] == -1 else (1.0 if r["w"] == 0 else 0.0)
				else:
					var r2: Dictionary = SimLib.play(ai, opp, cls, od, Array(deck), sd)
					w += 0.5 if r2["w"] == -1 else (1.0 if r2["w"] == 1 else 0.0)
			scores.append(w / float(games))
		out[cls] = scores
		printerr("[pick %s] %s  %.0fs" % [cls, str(scores), (Time.get_ticks_msec() - t0) / 1000.0])
	var f := FileAccess.open(_env("PICK_OUT", "user://pick.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()
