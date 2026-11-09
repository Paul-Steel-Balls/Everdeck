extends RefCounted

# One headless AI-vs-AI game, shared by the meta tools (sim_meta.gd,
# sim_search.gd). Returns a plain record; nothing is drawn.

const TURN_CAP: int = 90          # both players' turns together; then a draw
const ACTION_CAP: int = 60        # per turn, in case something loops


static func play(ai: AIPlayer, a: String, b: String, d0: Array, d1: Array, seed: int) -> Dictionary:
	var gs := GameState.new()
	gs.set_seed(seed)
	ai.rng.seed = seed + 3
	gs.setup(d0, d1, a, b)
	_variant(gs, OS.get_environment("SIM_VARIANT"))
	var played: Array = [[], []]
	var powers: Array = [0, 0]
	while gs.winner == -1 and gs.turn_count <= TURN_CAP:
		var p: int = gs.active
		var n: int = 0
		while gs.winner == -1 and n < ACTION_CAP:
			n += 1
			var act: Dictionary = ai.next_action(gs, p)
			if str(act.get("type", "")) == "end":
				break
			var cid: String = ""
			if act["type"] == "play":
				cid = str(gs.players[p]["hand"][int(act["hand_idx"])])
			if not AIPlayer.apply(gs, p, act):
				break
			if cid != "":
				played[p].append([cid, gs.turn_count])
			elif act["type"] == "power":
				powers[p] += 1
		if gs.winner != -1:
			break
		gs.end_turn()
	return {
		"a": a, "b": b, "seed": seed,
		"w": gs.winner,            # 0 = a (went first), 1 = b, -1 = draw
		"t": gs.turn_count,
		"hp": [int(gs.players[0]["hp"]), int(gs.players[1]["hp"])],
		"d0": d0, "d1": d1,
		"p0": played[0], "p1": played[1],
		"pw": powers,
	}


# What-if rules for the going-first problem, applied right after the deal.
# Simulation only: the real game never calls this.
static func _variant(gs: GameState, v: String) -> void:
	match v:
		"p2card":     # the second player is dealt one more card
			if not gs.players[1]["deck"].is_empty():
				gs.players[1]["hand"].append(gs.players[1]["deck"].pop_back())
		"p1nodraw":   # the first player skips their turn-1 draw
			var h: Array = gs.players[0]["hand"]
			if h.size() > 3:
				gs.players[0]["deck"].push_front(h.pop_back())
		"coin2":      # the second player gets two Lucky Pennies
			gs.players[1]["hand"].append("coin")
		"p2minus":    # the second player is dealt one card fewer (4 + Penny)
			var h2: Array = gs.players[1]["hand"]
			for i in range(h2.size() - 1, -1, -1):
				if str(h2[i]) != "coin":
					gs.players[1]["deck"].push_front(h2[i])
					h2.remove_at(i)
					break
		"nocoin":     # the second player keeps 5 cards but gets no Lucky Penny
			gs.players[1]["hand"].erase("coin")
		"p2hp3":      # the second player's Boss starts with 3 more health
			gs.players[1]["hp"] = int(gs.players[1]["hp"]) + 3
