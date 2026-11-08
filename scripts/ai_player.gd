extends RefCounted
class_name AIPlayer

# The computer opponent. Pure logic, no UI: given a GameState and the
# AI's player index, next_action() returns ONE action to take now, or
# {"type": "end"}. It works by trying every legal action on a copy of
# the game (GameState.clone) and scoring the result; it takes the best
# action that improves its position, repeating until nothing helps.
#
# Action dicts:
#   {"type": "play", "hand_idx": int, "target": Dictionary}
#   {"type": "power", "target": Dictionary}
#   {"type": "attack", "board_idx": int, "target": Dictionary}
#   {"type": "end"}

const WIN_SCORE: float = 100000.0
# Small reward for spending mana, so the AI uses its turn instead of
# hoarding cards whose value the score cannot see (draw, buffs later).
const TEMPO_PER_MANA: float = 0.35
const MIN_GAIN: float = 0.05
const SAMPLES_RANDOM: int = 4
const RANDOM_EFFECTS: Array = ["random", "roulette", "coin", "swap", "steal", "recruit", "flip"]

var rng := RandomNumberGenerator.new()
# 0.0 = always the best move; higher = sometimes picks a near-best move
# (feels less robotic, and gives an easier difficulty).
var sloppiness: float = 0.15


func _init() -> void:
	rng.randomize()


# --- Deck building for the computer ---

# A playable deck with a mana curve: mostly minions, a few spells,
# weighted toward the class's own cards.
static func build_deck(class_id: String, seed_value: int = -1) -> Array:
	var r := RandomNumberGenerator.new()
	if seed_value >= 0:
		r.seed = seed_value
	else:
		r.randomize()
	var pool: Array = CardDB.cards_for_class(class_id)
	# Cost bucket quotas: cheap, early, mid, late.
	var quotas: Array = [[1, 2, 8], [3, 4, 10], [5, 6, 7], [7, 99, 5]]
	var deck: Array = []
	var counts: Dictionary = {}
	for q in quotas:
		var bucket: Array = []
		for c in pool:
			var cost: int = int(c["cost"])
			if cost >= int(q[0]) and cost <= int(q[1]):
				bucket.append(c)
		var need: int = int(q[2])
		var tries: int = 0
		while need > 0 and tries < 4000 and not bucket.is_empty():
			tries += 1
			var c: Dictionary = bucket[r.randi_range(0, bucket.size() - 1)]
			# Class cards twice as likely; minions three times as likely.
			var w: float = (2.0 if c["class"] == class_id else 1.0) * (3.0 if c["type"] == "minion" else 1.0)
			if r.randf() * 6.0 > w:
				continue
			var cid: String = str(c["id"])
			if int(counts.get(cid, 0)) >= CardDB.max_copies(c):
				continue
			deck.append(cid)
			counts[cid] = int(counts.get(cid, 0)) + 1
			need -= 1
	# Top up from the whole pool if a bucket ran dry.
	var guard: int = 0
	while deck.size() < GameState.DECK_SIZE and guard < 20000:
		guard += 1
		var c2: Dictionary = pool[r.randi_range(0, pool.size() - 1)]
		var cid2: String = str(c2["id"])
		if int(counts.get(cid2, 0)) < CardDB.max_copies(c2):
			deck.append(cid2)
			counts[cid2] = int(counts.get(cid2, 0)) + 1
	return deck


# --- Turn play ---

func next_action(gs: GameState, me: int) -> Dictionary:
	if gs.winner != -1 or gs.active != me:
		return {"type": "end"}
	var base: float = evaluate(gs, me)
	var scored: Array = []
	for a in legal_actions(gs, me):
		# Random effects land differently each time: average a few tries
		# so one lucky roll does not fool the AI.
		var samples: int = SAMPLES_RANDOM if _is_random(gs, me, a) else 1
		var total: float = 0.0
		var ok: bool = true
		for _s in samples:
			var g: GameState = gs.clone()
			if not apply(g, me, a):
				ok = false
				break
			total += evaluate(g, me)
		if not ok:
			continue
		var gain: float = total / float(samples) - base + _tempo(gs, me, a)
		scored.append([gain, a])
	if scored.is_empty():
		return {"type": "end"}
	scored.sort_custom(func(x, y) -> bool: return x[0] > y[0])
	var best: float = scored[0][0]
	if best >= WIN_SCORE * 0.5:
		return scored[0][1]  # lethal: never get cute
	if best < MIN_GAIN:
		return {"type": "end"}
	# Sloppiness: sometimes take a near-best move instead.
	var pick: Array = scored[0]
	if sloppiness > 0.0 and scored.size() > 1 and rng.randf() < sloppiness:
		var alt: Array = scored[1]
		if alt[0] >= MIN_GAIN and alt[0] >= best * 0.6:
			pick = alt
	return pick[1]


func legal_actions(gs: GameState, me: int) -> Array:
	var out: Array = []
	var p: Dictionary = gs.players[me]
	for i in p["hand"].size():
		if not gs.can_play(me, i):
			continue
		var card: Dictionary = CardDB.get_card(str(p["hand"][i]))
		var opts: Array = gs.card_target_options(me, card)
		if opts.is_empty():
			out.append({"type": "play", "hand_idx": i, "target": {}})
		else:
			for t in opts:
				out.append({"type": "play", "hand_idx": i, "target": t})
			if card["type"] == "minion":
				# A minion's Entrance may also be played with no target.
				out.append({"type": "play", "hand_idx": i, "target": {}})
	var hp_opts: Array = gs.hero_power_target_options(me)
	if hp_opts.is_empty():
		if gs.can_use_hero_power(me, {}):
			out.append({"type": "power", "target": {}})
	else:
		for t2 in hp_opts:
			if gs.can_use_hero_power(me, t2):
				out.append({"type": "power", "target": t2})
	for b in p["board"].size():
		if not gs.can_attack(me, b):
			continue
		for t3 in gs.valid_attack_targets(me):
			out.append({"type": "attack", "board_idx": b, "target": t3})
	return out


static func apply(gs: GameState, me: int, a: Dictionary) -> bool:
	match str(a.get("type", "")):
		"play":
			return gs.play_card(me, int(a["hand_idx"]), a.get("target", {}))
		"power":
			return gs.use_hero_power(me, a.get("target", {}))
		"attack":
			return gs.attack(me, int(a["board_idx"]), a["target"])
	return false


func _is_random(gs: GameState, me: int, a: Dictionary) -> bool:
	if str(a.get("type", "")) == "power":
		return str(gs.hero_power(me).get("effect", "")).contains("random")
	if str(a.get("type", "")) != "play":
		return false
	var card: Dictionary = CardDB.get_card(str(gs.players[me]["hand"][int(a["hand_idx"])]))
	var blob: String = (str(card.get("effect", "")) + " " + str(card.get("effect2", "")) + " " + str(card.get("deathrattle", ""))).to_lower()
	for k in RANDOM_EFFECTS:
		if blob.contains(k):
			return true
	return false


func _tempo(gs: GameState, me: int, a: Dictionary) -> float:
	match str(a.get("type", "")):
		"play":
			var cid: String = str(gs.players[me]["hand"][int(a["hand_idx"])])
			return TEMPO_PER_MANA * float(CardDB.get_card(cid).get("cost", 0))
		"power":
			return TEMPO_PER_MANA * float(GameState.HERO_POWER_COST)
	return 0.0


# --- Position scoring (from `me`'s point of view) ---

static func evaluate(gs: GameState, me: int) -> float:
	if gs.winner == me:
		return WIN_SCORE
	if gs.winner == 1 - me:
		return -WIN_SCORE
	var mine: Dictionary = gs.players[me]
	var theirs: Dictionary = gs.players[1 - me]
	var v: float = _side_value(mine, true) - _side_value(theirs, false)
	# Threat: the enemy board's attack is damage coming at me next turn.
	# Counting it makes the AI value clearing threats over pure face hits.
	var threat: float = 0.0
	for m in theirs["board"]:
		threat += float(m["attack"])
	var my_hp: int = int(mine["hp"])
	v -= threat * (0.5 if my_hp > 15 else (0.9 if my_hp > 8 else 1.6))
	if threat >= float(my_hp):
		v -= 25.0  # I would die next turn: emergency
	return v


static func _side_value(p: Dictionary, is_me: bool) -> float:
	var hp: int = int(p["hp"])
	var v: float = 0.0
	# Health matters more the lower it gets (for both sides: the AI
	# defends when low and goes for the throat when the enemy is low).
	v += float(hp) * (0.6 if hp > 15 else (1.0 if hp > 8 else 1.8))
	for m in p["board"]:
		var atk: float = float(m["attack"])
		var health: float = float(max(0, int(m["health"])))
		v += atk * 1.3 + health * 1.0 + 0.8
		if m.get("taunt", false):
			v += 0.8 + health * 0.2
	v += min(float(p["hand"].size()), 8.0) * 0.9
	if not is_me:
		pass
	return v
