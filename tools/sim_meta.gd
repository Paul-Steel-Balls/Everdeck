extends SceneTree

# Meta stress test: the computer plays itself, headless, and writes one
# JSON line per game so tools/meta_report.py can find what's too strong.
#
#   godot --headless --path . -s res://tools/sim_meta.gd
#
# Settings come from the environment:
#   SIM_GAMES   games per ordered class pairing (default 20)
#   SIM_SEED    base seed (default 1)
#   SIM_SHARD   "i/n": run only every n-th game starting at i (parallel runs)
#   SIM_OUT     output path (default user://sim_meta.jsonl)
#   SIM_CLASSES comma list (default all six)
#   SIM_DECKS   optional JSON file {class: [30 ids], ...}: play these lists
#               instead of fresh random ones (used by the deck search)
#   SIM_HERO    with SIM_DECKS: only that class uses its list; everyone
#               else gets random decks (to test one list against the field)
#   SIM_SLOPPY  AI sloppiness, 0..1 (default 0.0: best play every time)
#
# Every game is seeded, so any line can be replayed exactly.

const SimLib = preload("res://tools/sim_lib.gd")
const ALL_CLASSES: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]


func _init() -> void:
	var games: int = int(OS.get_environment("SIM_GAMES")) if OS.get_environment("SIM_GAMES") != "" else 20
	var base_seed: int = int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 1
	var shard_i: int = 0
	var shard_n: int = 1
	if OS.get_environment("SIM_SHARD") != "":
		var parts: PackedStringArray = OS.get_environment("SIM_SHARD").split("/")
		shard_i = int(parts[0])
		shard_n = int(parts[1])
	var out_path: String = OS.get_environment("SIM_OUT") if OS.get_environment("SIM_OUT") != "" else "user://sim_meta.jsonl"
	var classes: Array = ALL_CLASSES
	if OS.get_environment("SIM_CLASSES") != "":
		classes = Array(OS.get_environment("SIM_CLASSES").split(","))
	var fixed: Dictionary = {}
	if OS.get_environment("SIM_DECKS") != "":
		fixed = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SIM_DECKS")))
	var hero_only: String = OS.get_environment("SIM_HERO")
	var sloppy: float = float(OS.get_environment("SIM_SLOPPY")) if OS.get_environment("SIM_SLOPPY") != "" else 0.0

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	var ai := AIPlayer.new()
	ai.sloppiness = sloppy
	var k: int = -1
	var t0: int = Time.get_ticks_msec()
	var done: int = 0
	for a in classes:
		for b in classes:
			if hero_only != "" and a != hero_only and b != hero_only:
				continue
			for g in games:
				k += 1
				if k % shard_n != shard_i:
					continue
				var seed: int = base_seed * 1000003 + k * 7919
				var rec: Dictionary = _play(ai, a, b, seed, fixed, hero_only)
				f.store_line(JSON.stringify(rec))
				done += 1
				if done % 25 == 0:
					f.flush()
					printerr("[sim] %d games, %.1fs" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	f.close()
	printerr("[sim] done: %d games in %.1fs" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


func _deck_for(cls: String, seed: int, fixed: Dictionary, hero_only: String) -> Array:
	if fixed.has(cls) and (hero_only == "" or hero_only == cls):
		return Array(fixed[cls])
	return AIPlayer.build_deck(cls, seed)


func _play(ai: AIPlayer, a: String, b: String, seed: int, fixed: Dictionary, hero_only: String) -> Dictionary:
	var d0: Array = _deck_for(a, seed + 1, fixed, hero_only)
	var d1: Array = _deck_for(b, seed + 2, fixed, hero_only)
	return SimLib.play(ai, a, b, d0, d1, seed)
