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
# Hard mode: 0 = pick one move at a time (Easy/Normal). N = plan the turn:
# try sequences of moves, keep the N best lines at each step, and play the
# first move of the best line (the Lab's --plan N, move for move).
var plan_width: int = 0
const PLAN_DEPTH: int = 6

enum Level { EASY, NORMAL, HARD }


# The three difficulty levels.
static func for_level(level: int) -> AIPlayer:
	var ai := AIPlayer.new()
	match level:
		Level.EASY:
			ai.sloppiness = 0.45
		Level.HARD:
			ai.sloppiness = 0.0
			ai.plan_width = 4
		_:
			ai.sloppiness = 0.15
	return ai


# Hard mode plays a tuned list (the Lab's best deck for that Boss) instead
# of a random curve. Falls back to build_deck if there isn't one.
static func tuned_deck(class_id: String) -> Array:
	var f := FileAccess.open("res://data/bot_decks.json", FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary and d.has(class_id):
			var deck: Array = []
			for cid in d[class_id]:
				if not CardDB.get_card(str(cid)).is_empty():
					deck.append(str(cid))
			if deck.size() == GameState.DECK_SIZE:
				return deck
	return build_deck(class_id)


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
	if plan_width > 0:
		return _plan(gs, me, plan_width)
	var base: float = evaluate(gs, me)
	var scored: Array = []
	for a in legal_actions(gs, me):
		# Random effects land differently each time: average a few tries
		# so one lucky roll does not fool the AI.
		var samples: int = SAMPLES_RANDOM if _is_random(gs, me, a) else 1
		var total: float = 0.0
		var ok: bool = true
		for _s in samples:
			var g: GameState = _look(gs, me)
			if not apply(g, me, a):
				ok = false
				break
			total += evaluate(g, me)
		if not ok:
			continue
		var diff: float = total / float(samples) - base
		# Mana now (the Lucky Penny, a Mana Potion) is only worth what it
		# lets you play next: look one play further, or the AI scores the
		# Penny as "lose a card, gain nothing" and never uses it.
		# Popping a Stunt Double only pays off with the hit that follows:
		# look one action further for those attacks too.
		if _gives_mana(gs, me, a) or _pops_shield(gs, a):
			var g2: GameState = _look(gs, me)
			if apply(g2, me, a):
				diff += _best_followup(g2, me)
		# A Signature Move that changes nothing (healing at full health)
		# earns no tempo: don't burn 2 mana on it.
		var tempo: float = 0.0 if (str(a.get("type", "")) == "power" and absf(diff) < 0.001) else _tempo(gs, me, a)
		var gain: float = diff + tempo
		scored.append([gain, a])
	if scored.is_empty():
		return {"type": "end"}
	# The best move; a tie goes to the one listed first (a fixed rule, so
	# the Lab's copy of the bot makes the same choice).
	var bi: int = 0
	for i in range(1, scored.size()):
		if scored[i][0] > scored[bi][0]:
			bi = i
	var best: float = scored[bi][0]
	if best >= WIN_SCORE * 0.5:
		return scored[bi][1]  # lethal: never get cute
	if best < MIN_GAIN:
		return {"type": "end"}
	# Sloppiness: sometimes take the next-best move instead.
	var pick: Array = scored[bi]
	if sloppiness > 0.0 and scored.size() > 1 and rng.randf() < sloppiness:
		var ai2: int = -1
		for i in scored.size():
			if i != bi and (ai2 == -1 or scored[i][0] > scored[ai2][0]):
				ai2 = i
		var alt: Array = scored[ai2]
		if alt[0] >= MIN_GAIN and alt[0] >= best * 0.6:
			pick = alt
	return pick[1]


# Hard mode: beam search over this turn's move sequences. Each line is
# [score, game copy, first move, tempo so far, order]. Re-plans every move,
# so dice and draws are seen as they land.
func _plan(gs: GameState, me: int, width: int) -> Dictionary:
	var root: GameState = _look(gs, me)
	var base: float = evaluate(root, me)
	var best_score: float = base
	var best_act: Dictionary = {"type": "end"}
	var beam: Array = [[base, root, {"type": "end"}, 0.0, 0]]
	for _d in PLAN_DEPTH:
		var cand: Array = []
		for line in beam:
			var g: GameState = line[1]
			var first: Dictionary = line[2]
			for a in legal_actions(g, me):
				var g2: GameState = g.clone()
				if not apply(g2, me, a):
					continue
				var t: float = float(line[3]) + _tempo(g, me, a)
				var f: Dictionary = a if str(first.get("type", "")) == "end" else first
				var sc: float = evaluate(g2, me) + t
				if g2.winner == me:
					return f
				cand.append([sc, g2, f, t, cand.size()])
		if cand.is_empty():
			break
		# Best first; equal scores keep the order they were found (the Lab's
		# stable sort), so both pick the same line.
		cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[4] < y[4]))
		cand.resize(mini(width, cand.size()))
		if cand[0][0] > best_score:
			best_score = cand[0][0]
			best_act = cand[0][2]
		beam = cand
	if best_score - base < MIN_GAIN:
		return {"type": "end"}
	return best_act


# A look-ahead copy with the hidden cards hidden: the bot knows what's in
# its own deck but not the order, and doesn't know the opponent's hand or
# deck at all. Without this, a copy kept the real deck order, so testing
# a card that draws showed the bot exactly what it would draw (a peek).
func _look(gs: GameState, me: int) -> GameState:
	var g: GameState = gs.clone()
	_shuffle(g, g.players[me]["deck"])
	var foe: Dictionary = g.players[1 - me]
	var n: int = foe["hand"].size()
	var pool: Array = foe["hand"] + foe["deck"]
	_shuffle(g, pool)
	foe["hand"] = pool.slice(0, n)
	foe["deck"] = pool.slice(n)
	return g


func _shuffle(g: GameState, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = g.rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _pops_shield(gs: GameState, a: Dictionary) -> bool:
	if str(a.get("type", "")) != "attack":
		return false
	var t: Dictionary = a.get("target", {})
	if str(t.get("kind", "")) != "minion":
		return false
	var b: Array = gs.players[int(t["player"])]["board"]
	var i: int = int(t["board_idx"])
	return i >= 0 and i < b.size() and bool(b[i].get("shield", false))


func _gives_mana(gs: GameState, me: int, a: Dictionary) -> bool:
	if str(a.get("type", "")) != "play":
		return false
	var card: Dictionary = CardDB.get_card(str(gs.players[me]["hand"][int(a["hand_idx"])]))
	return str(card.get("effect", "")) == "gain_mana"


# The best gain of one more action from position `gs` (0 if nothing is
# worth doing). Mana cards are skipped here so this never chains.
func _best_followup(gs: GameState, me: int) -> float:
	var base: float = evaluate(gs, me)
	var best: float = 0.0
	for b in legal_actions(gs, me):
		if _gives_mana(gs, me, b):
			continue
		var g: GameState = _look(gs, me)
		if not apply(g, me, b):
			continue
		var gain: float = evaluate(g, me) - base + _tempo(gs, me, b)
		if gain > best:
			best = gain
	return best


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
		# Stage Fright: a frozen Crew member skips its next attack.
		# Encore: twice the swings.
		if int(m.get("frozen", 0)) > 0:
			continue
		threat += float(m["attack"]) * (2.0 if m.get("windfury", false) else 1.0)
	var my_hp: int = int(mine["hp"])
	v -= threat * (0.5 if my_hp > 15 else (0.9 if my_hp > 8 else 1.6))
	if threat >= float(my_hp):
		v -= 25.0  # I would die next turn: emergency
	return v


# Each point of health is worth more the lower health gets: 1.8 for the
# last 8, 1.0 for the next 7, 0.6 above 15. Summed point by point, so
# losing health ALWAYS lowers the value. (It used to be hp x one rate
# picked by the band, which jumped UP when health crossed 15 or 8: the
# AI then refused to hit a Boss at 16 and stalled forever, spending its
# 2 mana on the Signature Move every turn.)
static func health_value(hp: int) -> float:
	var h: float = float(maxi(hp, 0))
	return 1.8 * minf(h, 8.0) + 1.0 * clampf(h - 8.0, 0.0, 7.0) + 0.6 * maxf(h - 15.0, 0.0)


# What a Crew member's keywords and ongoing effects are worth beyond its
# stats. The AI looks one move ahead, so without this it can't see that a
# "whenever" or "at the end of your turn" Crew member keeps paying off.
static func _keyword_value(m: Dictionary, atk: float) -> float:
	var v: float = 0.0
	if m.get("shield", false):
		# A whole extra life against one hit: about half the Crew
		# member's value (the Hearthstone rule of thumb for Divine Shield).
		v += 2.0 + atk * 0.6 + float(max(0, int(m["health"]))) * 0.2
	if m.get("stealth", false):
		v += 0.8
	if m.get("windfury", false):
		v += atk * 0.9
	if m.get("poison", false):
		v += 2.5
	if m.get("lifesteal", false):
		v += atk * 0.5
	if int(m.get("frozen", 0)) > 0:
		v -= atk * 0.6
	if m.get("silenced", false):
		return v
	var card: Dictionary = CardDB.get_card(str(m.get("card_id", "")))
	for t in card.get("triggers", []):
		var amt: float = float(t.get("value", 1))
		var when: String = str(t.get("when", ""))
		if when == "end_of_turn" or when == "start_of_turn":
			v += 1.5 + amt * 1.2  # fires every turn it lives
		else:
			v += 1.0 + amt * 0.6  # fires when its condition comes up
	if not (card.get("vibe", {}) as Dictionary).is_empty():
		v += 0.6  # its bonus to others already shows in their stats
	return v


static func _side_value(p: Dictionary, is_me: bool) -> float:
	var hp: int = int(p["hp"])
	var v: float = 0.0
	# Health matters more the lower it gets (for both sides: the AI
	# defends when low and goes for the throat when the enemy is low).
	v += health_value(hp)
	for m in p["board"]:
		var atk: float = float(m["attack"])
		var health: float = float(max(0, int(m["health"])))
		v += atk * 1.3 + health * 1.0 + 0.8
		if m.get("taunt", false):
			v += 0.8 + health * 0.2
		v += _keyword_value(m, atk)
	v += min(float(p["hand"].size()), 8.0) * 0.9
	# On Credit: mana already spent from next turn.
	v -= float(p.get("overload_next", 0)) * 0.6
	if not is_me:
		pass
	return v
