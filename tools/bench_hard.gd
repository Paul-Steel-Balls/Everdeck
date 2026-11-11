extends SceneTree
# How long the Hard bot thinks per move inside the game (GDScript).
#   godot --headless --path . -s res://tools/bench_hard.gd
# BENCH_GAMES (default 4), BENCH_PLAN (default 4).
func _init() -> void:
	var games: int = int(OS.get_environment("BENCH_GAMES")) if OS.get_environment("BENCH_GAMES") != "" else 4
	var width: int = int(OS.get_environment("BENCH_PLAN")) if OS.get_environment("BENCH_PLAN") != "" else 4
	var classes: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
	var times: Array = []
	for gi in games:
		var a: String = classes[gi % 6]
		var b: String = classes[(gi + 3) % 6]
		var gs := GameState.new()
		var da: Array = AIPlayer.tuned_deck(a)
		var db: Array = AIPlayer.tuned_deck(b)
		if gi == 0:
			print("deck sizes %d %d, cards loaded %d" % [da.size(), db.size(), CardDB.cards_for_class(a).size()])
		gs.setup(da, db, a, b)
		var ai := AIPlayer.for_level(AIPlayer.Level.HARD)
		ai.plan_width = width
		while gs.winner == -1 and gs.turn_count <= 90:
			var p: int = gs.active
			for _n in 60:
				var t0: int = Time.get_ticks_usec()
				var act: Dictionary = ai.next_action(gs, p)
				times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
				if str(act.get("type", "end")) == "end" or not AIPlayer.apply(gs, p, act):
					break
				if gs.winner != -1:
					break
			if gs.winner != -1:
				break
			gs.end_turn()
	times.sort()
	var tot: float = 0.0
	for t in times:
		tot += t
	print("moves %d  avg %.0f ms  median %.0f ms  90th %.0f ms  worst %.0f ms" % [times.size(), tot / times.size(), times[times.size() / 2], times[int(times.size() * 0.9)], times[-1]])
	quit()
