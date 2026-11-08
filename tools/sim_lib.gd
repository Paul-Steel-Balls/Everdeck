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
