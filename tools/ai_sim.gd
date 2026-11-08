extends SceneTree
# Headless: godot --headless --path . -s res://tools/ai_sim.gd -- <games> <mode>
# mode "ai" = AI vs AI (all class pairs), "random" = AI (P1/P2 alternating) vs random mover.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var games: int = int(args[0]) if args.size() > 0 else 60
	var mode: String = args[1] if args.size() > 1 else "ai"
	var classes: Array = CardDB.CLASS_IDS
	var wins: Dictionary = {}
	var plays: Dictionary = {}
	var first_wins: int = 0
	var ai_wins: int = 0
	var turns_total: int = 0
	var stuck: int = 0
	var t0: int = Time.get_ticks_msec()
	for g in games:
		var c0: String = classes[g % classes.size()]
		var c1: String = classes[(g / classes.size() + g) % classes.size()]
		var gs := GameState.new()
		gs.setup(AIPlayer.build_deck(c0), AIPlayer.build_deck(c1), c0, c1)
		var bots: Array = [AIPlayer.new(), AIPlayer.new()]
		var ai_seat: int = g % 2
		var actions: int = 0
		while gs.winner == -1 and gs.turn_count < 120:
			var me: int = gs.active
			var a: Dictionary
			if mode == "random" and me != ai_seat:
				a = _random_action(gs, me, bots[me])
			else:
				a = bots[me].next_action(gs, me)
			if a["type"] == "end":
				gs.end_turn()
			else:
				if not AIPlayer.apply(gs, me, a):
					print("ILLEGAL ", a)
					gs.end_turn()
				actions += 1
				if actions > 4000:
					break
			gs.take_events()
		if gs.winner == -1:
			stuck += 1
			continue
		turns_total += gs.turn_count
		var wc: String = str(gs.players[gs.winner]["class"])
		wins[wc] = int(wins.get(wc, 0)) + 1
		plays[c0] = int(plays.get(c0, 0)) + 1
		plays[c1] = int(plays.get(c1, 0)) + 1
		if gs.winner == 0:
			first_wins += 1
		if gs.winner == ai_seat:
			ai_wins += 1
	var done: int = games - stuck
	print("GAMES ", games, " finished ", done, " stuck ", stuck, " avg turns ", float(turns_total) / max(done, 1), " ms/game ", (Time.get_ticks_msec() - t0) / max(games, 1))
	print("FIRST PLAYER WIN ", float(first_wins) / max(done, 1))
	if mode == "random":
		print("AI WIN RATE vs random ", float(ai_wins) / max(done, 1))
	for c in classes:
		print("  ", c, " ", int(wins.get(c, 0)), "/", int(plays.get(c, 0)))
	quit()


func _random_action(gs: GameState, me: int, bot: AIPlayer) -> Dictionary:
	var acts: Array = bot.legal_actions(gs, me)
	if acts.is_empty() or randf() < 0.2:
		return {"type": "end"}
	return acts[randi() % acts.size()]
