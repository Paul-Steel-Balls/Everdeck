extends Node
class_name AnimDirector

# Everdeck Sprint 1b — the motion pass. Plays the GameState event stream
# after each player action. State is ALREADY resolved when this runs;
# the director only SHOWS it, then main does a full sync so the view
# always matches the state even if an animation is skipped. Input is
# locked by main while this runs.
#
# Grouping: a "cause" event (attack, spell_cast, signature_move, entrance,
# final_bow) CONSUMES the consecutive damage events that follow it and
# plays them as one group — damage that shares an attack or an AoE plays
# SIMULTANEOUSLY, not one after another. A bare damage group (no cause
# directly before it — self-damage: fatigue, coin-flip tails,
# draw-self-damage) plays with no projectile, just the damage visuals.
# Cause-consumes-group also fixes origins: the projectile comes from the
# source minion (Entrance/Final Bow) or the caster's hero (spell /
# signature move), and an AoE gets a shockwave instead of projectiles.
# Consecutive-damage grouping slightly over-groups one case: Double
# Down's two deal-1 pings (effect + effect2) land together. One spell,
# one moment — accepted.
#
# Parallelism: within a group, all visuals start together and the
# director awaits the longest non-floater duration (gem punch / shake).
# Floaters (0.7s) keep floating after the handler returns — they are
# fire-and-forget on pooled nodes, and the pool (16) covers the worst
# simultaneous group (a full-board AoE: 14 floaters).

# --- ALL durations live in this one const block ---
const LUNGE_LIFT_HEIGHT: float = 0.3   # how high the attacker lifts
const LUNGE_LIFT_TIME: float = 0.10    # lift duration (ease-out)
const LUNGE_IN_TIME: float = 0.18      # lunge toward the target (ease-in)
const LUNGE_OUT_TIME: float = 0.22     # return to the slot (ease-out)
const LUNGE_STOP_DIST: float = 1.15    # stop this far short of the target
const HIT_STOP_TIME: float = 0.06      # freeze at impact
# Step 2: 3D Crew models strike (turn, wind up, dash, hit-pause, slash)
const STRIKE_TURN_TIME: float = 0.14   # turn to face the target
const STRIKE_WIND_TIME: float = 0.20   # lean back + half-step away
const STRIKE_DASH_TIME: float = 0.16   # dash in (expo ease-in)
const STRIKE_PAUSE_TIME: float = 0.09  # both freeze as the blow lands
const STRIKE_BACK_TIME: float = 0.40   # recover to the slot
const STRIKE_STOP_CREW: float = 1.0    # stop this far short of a Crew target
const STRIKE_STOP_BOSS: float = 1.5    # ...and of a Boss
const BUILD_TIME: float = 0.70         # summon: the model builds up out of cubes
const GLITCH_TIME: float = 0.30        # death: digital tearing
const DERES_TIME: float = 0.50         # death: cubes blink out
const CAMERA_SHAKE_PER_DAMAGE: float = 0.04  # shake units per damage point
const CAMERA_SHAKE_MAX: float = 0.25   # shake cap
const CAMERA_SHAKE_DECAY: float = 0.20 # shake decay duration
const TRIGGER_FLASH_TIME: float = 0.15 # Entrance / Final Bow rim flash
const SUMMON_DROP_HEIGHT: float = 0.8  # token drops from this high
const SUMMON_DROP_TIME: float = 0.22   # drop duration
const SUMMON_SQUASH_TIME: float = 0.30 # landing squash (0.85 -> 1.05 -> 1.0)
const SLOT_SLIDE_TIME: float = 0.18    # neighbors / survivors sliding (must match Board3D._tween_to_slot)
const DAMAGE_FLOAT_TIME: float = 0.70  # "-N" floater: rise + fade
const DAMAGE_FLOAT_RISE: float = 0.6   # how far the floater rises
const FLOATER_POP_TIME: float = 0.15   # floater scale 1.6 -> 1.0
const DAMAGE_FLASH_TIME: float = 0.08  # white/emissive flash
const DAMAGE_SHAKE_TIME: float = 0.12  # token wobble
const GEM_PUNCH_TIME: float = 0.25    # gem number punch (1.5 -> 1.0)
const HEAL_GLOW_TIME: float = 0.40     # green glow pulse
const DESTROY_FLASH_TIME: float = 0.15 # dark crack flash
const DEATH_TIME: float = 0.40        # tilt + sink + fade
const DEATH_TILT_DEG: float = 20.0    # death tilt, degrees
const DEATH_SINK: float = 0.35        # how far the dead token sinks
const PROJECTILE_TIME: float = 0.35   # spell / signature projectile flight
const SHOCKWAVE_TIME: float = 0.25    # AoE shockwave ring expansion
const STEAL_LIFT_HEIGHT: float = 0.5  # stolen minion lifts this high
const STEAL_GLIDE_TIME: float = 0.45  # stolen minion glides across
const SWAP_SPIN_TIME: float = 0.30    # stats-swap gem half-turn
const COIN_SPIN_TIME: float = 0.50    # coin flip spin
const COIN_HOLD_TIME: float = 0.20    # coin rests showing heads/tails
# Sprint 1c: the center-screen coin moment holds the result longer so
# the HEADS/TAILS label clearly reads before the effect plays.
const COIN_RESULT_HOLD_TIME: float = 0.6
const DRAW_SLIDE_TIME: float = 0.30   # deck box slides to the hand edge
const MANA_GEM_POP_TIME: float = 0.15 # turn-start mana gem pop
const MANA_GEM_STAGGER: float = 0.05  # mana gems light up, one at a time
const HERO_DAMAGE_TIME: float = 0.30  # plaque shake + red flash
const HERO_DEATH_SHAKE_TIME: float = 1.20  # hero death, half-speed slow-motion
const HERO_DEATH_HOLD: float = 1.0    # hold on the dead hero before game over
const BANNER_TIME: float = 0.90       # "YOUR TURN" banner sweep (played by main)
const HANDS_WHOOSH_TIME: float = 0.40 # swapped hands whoosh (played by main)
# Speed multiplier: all durations are divided by this. A VAR (not const)
# — deliberate: tap-to-speed-up sets it to 3x mid-batch, and the smoke
# test runs with it high. main resets it to 1.0 after each batch.
var ANIM_SPEED: float = 1.0


# Tap while animations play: 3x speed-up for the rest of this batch.
# Never lowers an already-higher speed (e.g. the smoke test's).
func boost_speed() -> void:
	ANIM_SPEED = max(ANIM_SPEED, 3.0)


func _dur(t: float) -> float:
	return t / max(ANIM_SPEED, 0.01)


func _wait(t: float) -> void:
	await get_tree().create_timer(_dur(t)).timeout


# Play events in order. hand_whoosh / banner are main's 2D callables
# (the director is 3D; main owns the 2D overlay). Empty Callables are
# skipped (the headless smoke test passes none).
func play_events(events: Array, board: Board3D, gs: GameState, hand_whoosh: Callable = Callable(), banner: Callable = Callable()) -> void:
	if board == null or gs == null:
		return
	var i: int = 0
	while i < events.size():
		# The caller (main) can free the board mid-batch (scene change
		# in a test) while this coroutine is suspended on an await.
		# Never touch a freed board — just stop.
		if not is_instance_valid(board):
			return
		var ev: Dictionary = events[i]
		var type: String = str(ev.get("type", ""))
		var data: Dictionary = ev.get("data", {})
		match type:
			"attack":
				var group: Array = _take_damage_group(events, i + 1)
				await _play_attack(data, group, board, gs)
				i += 1 + group.size()
			"spell_cast":
				var group2: Array = _take_damage_group(events, i + 1)
				await _play_spell_cast(data, group2, board, gs)
				i += 1 + group2.size()
			"signature_move":
				var group3: Array = _take_damage_group(events, i + 1)
				await _play_signature_move(data, group3, board, gs)
				i += 1 + group3.size()
			"entrance":
				var group4: Array = _take_damage_group(events, i + 1)
				await _play_entrance(data, group4, board, gs)
				i += 1 + group4.size()
			"final_bow":
				var group5: Array = _take_damage_group(events, i + 1)
				await _play_final_bow(data, group5, board, gs)
				i += 1 + group5.size()
			"damage":
				# Bare damage group (no consuming cause — self-damage).
				var group6: Array = _take_damage_group(events, i)
				await _play_damage_visuals(group6, board, gs)
				i += group6.size()
			"heal":
				await _play_heal(data, board, gs)
				i += 1
			"buff":
				await _play_buff(data, board, gs)
				i += 1
			"minion_summoned":
				await _play_summon(data, board, gs)
				i += 1
			"minion_died":
				# Consecutive deaths died together: animate together,
				# then the survivors slide once.
				var deaths: Array = []
				while i < events.size() and str(events[i].get("type", "")) == "minion_died":
					deaths.append(events[i].get("data", {}))
					i += 1
				await _play_deaths(deaths, board, gs)
			"minion_destroyed":
				var destroys: Array = []
				while i < events.size() and str(events[i].get("type", "")) == "minion_destroyed":
					destroys.append(events[i].get("data", {}))
					i += 1
				await _play_destroys(destroys, board, gs)
			"minion_stolen":
				await _play_steal(data, board, gs)
				i += 1
			"stats_swapped":
				await _play_stats_swap(data, board, gs)
				i += 1
			"hands_swapped":
				if hand_whoosh.is_valid():
					await hand_whoosh.call()
				i += 1
			"coin_flip":
				await _play_coin_flip(data, board, gs)
				i += 1
			"draw", "card_burned":
				await _play_draw(data, board, gs)
				i += 1
			"turn_start":
				await _play_turn_start(data, board, gs, banner)
				i += 1
			_:
				# Snap: card_played, mana_changed, empty_deck, game_over,
				# minion_summoned (handled above), etc. The full sync
				# after this fixes the view.
				i += 1


# Consecutive "damage" events starting at `start` (one group).
func _take_damage_group(events: Array, start: int) -> Array:
	var out: Array = []
	var j: int = start
	while j < events.size() and str(events[j].get("type", "")) == "damage":
		out.append(events[j].get("data", {}))
		j += 1
	return out


# --- Cause handlers (each consumes its damage group) ---

func _play_attack(data: Dictionary, group: Array, board: Board3D, gs: GameState) -> void:
	var attacker_uid: int = int(data.get("attacker_uid", -1))
	var node: Minion3D = board.minion_node(attacker_uid)
	if node == null:
		# Attacker gone — still play the hits so they land.
		await _play_damage_visuals(group, board, gs)
		return
	var target_res: Dictionary = _target_position(data, board, gs)
	if not bool(target_res.get("found", false)):
		await _play_damage_visuals(group, board, gs)
		return
	var target_pos: Vector3 = target_res["position"]
	board.cancel_slot_tween(attacker_uid)
	if node.unit != null:
		await _model_strike(node, data, target_pos, group, board, gs)
		return
	var start: Vector3 = node.position
	var dir: Vector3 = target_pos - start
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		await _play_damage_visuals(group, board, gs)
		return
	dir = dir.normalized()
	var dest: Vector3 = target_pos - dir * LUNGE_STOP_DIST
	dest.y = start.y + LUNGE_LIFT_HEIGHT
	# Lift (ease-out), lunge in (ease-in).
	var tw1 := create_tween()
	tw1.tween_property(node, "position:y", start.y + LUNGE_LIFT_HEIGHT, _dur(LUNGE_LIFT_TIME)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await tw1.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	var tw2 := create_tween()
	tw2.tween_property(node, "position", dest, _dur(LUNGE_IN_TIME)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw2.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	# Impact: hit-stop (freeze), spark burst, camera shake, damage.
	await _wait(HIT_STOP_TIME)
	var total_dmg: int = 0
	for d in group:
		total_dmg += int(d.get("amount", 0))
	board.spawn_particles("sparks", (start + target_pos) * 0.5 + Vector3(0, 0.4, 0))
	var shake_mag: float = min(CAMERA_SHAKE_MAX, CAMERA_SHAKE_PER_DAMAGE * float(total_dmg))
	if shake_mag > 0.0:
		board.shake_camera(shake_mag, _dur(CAMERA_SHAKE_DECAY))
	await _play_damage_visuals(group, board, gs)
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	# Return (ease-out). Floaters keep floating after this returns.
	var tw3 := create_tween()
	tw3.tween_property(node, "position", start, _dur(LUNGE_OUT_TIME)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await tw3.finished


# A 3D Crew member's strike: turn to the target, wind up, dash in, a short
# hit-pause where both freeze, a sharp slash + sparks + glint + ring over
# the contact point, camera shake, the damage lands, then recover.
func _model_strike(node: Minion3D, data: Dictionary, target_pos: Vector3, group: Array, board: Board3D, gs: GameState) -> void:
	var u: HoloUnit = node.unit
	var start: Vector3 = node.position
	var d: Vector3 = target_pos - start
	d.y = 0.0
	if d.length_squared() < 0.001:
		await _play_damage_visuals(group, board, gs)
		return
	var dir: Vector3 = d.normalized()
	var is_boss: bool = str(data.get("target_kind", "")) == "hero"
	var dest: Vector3 = target_pos - dir * (STRIKE_STOP_BOSS if is_boss else STRIKE_STOP_CREW)
	dest.y = start.y
	var face: float = atan2(d.x, d.z)
	var tgt_unit: HoloUnit = null
	if is_boss:
		tgt_unit = board.boss_unit(int(data.get("target_player", 0)))
	else:
		var tn: Minion3D = board.minion_node(int(data.get("target_uid", -1)))
		if tn != null:
			tgt_unit = tn.unit
	u.act_turn = face
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(u, "act_w", 1.0, _dur(STRIKE_TURN_TIME))
	await tw.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	var wind := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wind.tween_property(u, "act_lean", deg_to_rad(-14), _dur(STRIKE_WIND_TIME))
	wind.parallel().tween_property(u, "act_step", -Vector3(0, 0, 0.18), _dur(STRIKE_WIND_TIME))
	await wind.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	var dash := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	dash.tween_property(node, "position", dest, _dur(STRIKE_DASH_TIME))
	dash.parallel().tween_property(u, "act_lean", deg_to_rad(16), _dur(STRIKE_DASH_TIME))
	dash.parallel().tween_property(u, "act_step", Vector3.ZERO, _dur(STRIKE_DASH_TIME))
	await dash.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	# Hit-pause: both freeze for a beat so the blow lands.
	var hp: Vector3 = target_pos + Vector3(0, 1.7 if is_boss else 1.0, 0)
	var col: Color = u.color
	u.busy = true
	if tgt_unit != null:
		tgt_unit.busy = true
	FxLab.slash(board, hp, col, face)
	FxLab.sparks(board, hp, Color(1.0, 0.85, 0.5), 36, 5.0, 0.3)
	FxLab.glint(board, hp, Color(1, 1, 1), 0.8)
	FxLab.shock_ring(board, Vector3(hp.x, target_pos.y + 0.05, hp.z), col, 1.4 if is_boss else 1.2)
	var total_dmg: int = 0
	for gd in group:
		total_dmg += int(gd.get("amount", 0))
	var shake_mag: float = min(CAMERA_SHAKE_MAX, 0.06 + CAMERA_SHAKE_PER_DAMAGE * float(total_dmg))
	board.shake_camera(shake_mag, _dur(CAMERA_SHAKE_DECAY))
	await _wait(STRIKE_PAUSE_TIME)
	if is_instance_valid(u):
		u.busy = false
	if tgt_unit != null and is_instance_valid(tgt_unit):
		tgt_unit.busy = false
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	# The damage lands (flash + knockback + floaters) as the attacker
	# recovers back to its slot.
	var ret := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ret.tween_property(node, "position", start, _dur(STRIKE_BACK_TIME))
	ret.parallel().tween_property(u, "act_lean", 0.0, _dur(STRIKE_BACK_TIME) * 0.9)
	ret.tween_property(u, "act_w", 0.0, _dur(STRIKE_TURN_TIME) * 1.6)
	await _play_damage_visuals(group, board, gs)
	if ret.is_running():
		await ret.finished


# The attack target's position: hero plaque or target minion. Found-flag
# — a missing target is NOT at the origin.
func _target_position(data: Dictionary, board: Board3D, gs: GameState) -> Dictionary:
	if str(data.get("target_kind", "")) == "hero":
		return board.hero_position(int(data.get("target_player", 0)), board.view_of(gs))
	return board.minion_position(int(data.get("target_uid", -1)))


func _play_spell_cast(data: Dictionary, group: Array, board: Board3D, gs: GameState) -> void:
	if group.is_empty():
		return
	var card: Dictionary = CardDB.get_card(str(data.get("card_id", "")))
	var effect: String = str(card.get("effect", ""))
	await _play_effect_damage(effect, group, int(data.get("player", 0)), -1, board, gs)


func _play_signature_move(data: Dictionary, group: Array, board: Board3D, gs: GameState) -> void:
	if group.is_empty():
		return
	var hp: Dictionary = CardDB.hero_power_for(str(data.get("class", "")))
	var effect: String = str(hp.get("effect", ""))
	await _play_effect_damage(effect, group, int(data.get("player", 0)), -1, board, gs)


func _play_entrance(data: Dictionary, group: Array, board: Board3D, gs: GameState) -> void:
	# The minion's rim flashes + pulses so players see WHO caused it.
	var uid: int = int(data.get("uid", -1))
	var node: Minion3D = board.minion_node(uid)
	if node != null:
		node.start_trigger_flash(_dur(TRIGGER_FLASH_TIME))
		await _wait(TRIGGER_FLASH_TIME)
	if group.is_empty():
		return
	var card: Dictionary = CardDB.get_card(str(data.get("card_id", "")))
	await _play_effect_damage(str(card.get("effect", "")), group, int(data.get("player", 0)), uid, board, gs)


func _play_final_bow(data: Dictionary, group: Array, board: Board3D, gs: GameState) -> void:
	# No rim flash: the minion's node is already gone (minion_died
	# precedes final_bow in the stream, and its death animation played).
	# The effect still plays, from the owner's hero plaque (the dead
	# minion has no node to be a projectile origin).
	if group.is_empty():
		return
	var card: Dictionary = CardDB.get_card(str(data.get("card_id", "")))
	await _play_effect_damage(str(card.get("deathrattle", "")), group, int(data.get("player", 0)), -1, board, gs)


# Damage from one effect: AoE (damage_all_*) gets a shockwave ring, then
# all hits land together; anything else gets one projectile per hit
# (simultaneous), then the damage visuals. source_uid >= 0 = the effect
# came from that minion (Entrance); -1 = the caster's hero.
func _play_effect_damage(effect: String, group: Array, caster: int, source_uid: int, board: Board3D, gs: GameState) -> void:
	if effect == "damage_all_enemy_minions" or effect == "damage_all_minions":
		await _play_aoe_damage(group, board, gs)
	else:
		await _play_projectile_damage(group, caster, source_uid, board, gs)


func _play_projectile_damage(group: Array, caster: int, source_uid: int, board: Board3D, gs: GameState) -> void:
	# Origin: the source minion if it still has a node, else the caster's
	# hero plaque. No projectile for self-damage (target = caster's own
	# hero) — the hit just lands.
	var origin: Vector3 = Vector3.ZERO
	var have_origin: bool = false
	if source_uid >= 0:
		var src_node: Minion3D = board.minion_node(source_uid)
		if src_node != null:
			origin = src_node.position + _aim_lift(board, "minion", -1, src_node)
			have_origin = true
	if not have_origin:
		var hp_res: Dictionary = board.hero_position(caster, board.view_of(gs))
		if bool(hp_res.get("found", false)):
			origin = hp_res["position"] + _aim_lift(board, "hero", caster, null)
			have_origin = true
	if have_origin:
		for d in group:
			var target_kind: String = str(d.get("target_kind", ""))
			var tp: int = int(d.get("player", 0))
			if target_kind == "hero" and tp == caster:
				continue  # self-damage: no projectile
			var target_pos: Vector3 = Vector3.ZERO
			var have_target: bool = false
			if target_kind == "hero":
				var tr: Dictionary = board.hero_position(tp, board.view_of(gs))
				if bool(tr.get("found", false)):
					target_pos = tr["position"] + _aim_lift(board, "hero", tp, null)
					have_target = true
			else:
				var mr: Dictionary = board.minion_position(int(d.get("uid", -1)))
				if bool(mr.get("found", false)):
					target_pos = mr["position"] + _aim_lift(board, "minion", -1, board.minion_node(int(d.get("uid", -1))))
					have_target = true
			if have_target:
				# Fire-and-forget (the pool owns the tween); the director
				# awaits the flight duration, not each tween — a killed
				# tween (pool reuse) must never hang the batch.
				board.launch_projectile(origin, target_pos, _dur(PROJECTILE_TIME))
		await _wait(PROJECTILE_TIME)
	await _play_damage_visuals(group, board, gs)


# How far above the anchor (feet) a projectile leaves / lands: chest
# height on a 3D model (launch_projectile adds its own 0.4).
func _aim_lift(board: Board3D, kind: String, player: int, node: Minion3D) -> Vector3:
	if kind == "hero":
		return Vector3(0, 1.3, 0) if board.boss_unit(player) != null else Vector3.ZERO
	if node != null and node.unit != null:
		return Vector3(0, 0.6, 0)
	return Vector3.ZERO


# Where a floater starts: above a model's head, or just over a token.
func _float_pos(node: Minion3D) -> Vector3:
	return node.position + Vector3(0, 2.3 if node.unit != null else 0.6, 0)


# A Boss's numbers float over the Boss model when there is one, else on
# the 2D panel.
func _boss_floater(board: Board3D, p: int, text: String, color: Color) -> void:
	if board.boss_unit(p) != null and board.hero_plaque(p) != null:
		_spawn_floater(board, board.hero_plaque(p).position + Vector3(0, 3.6, 0), text, color)
	else:
		board.hero_floater(p, text, color)


func _play_aoe_damage(group: Array, board: Board3D, gs: GameState) -> void:
	# One shockwave ring per affected row, then all hits land together.
	var rows: Dictionary = {}
	for d in group:
		if str(d.get("target_kind", "")) == "minion":
			rows[int(d.get("player", 0))] = true
	for p in rows.keys():
		# Sprint 1a.4: the row center comes from the board's slot math
		# (idx 0 of 1 = centered about ROW_CENTER_X).
		var row_center: Vector3 = board.slot_position(int(p), 0, 1, board.view_of(gs))
		row_center.y = 0.12
		board.spawn_shockwave(row_center, _dur(SHOCKWAVE_TIME))
	if not rows.is_empty():
		await _wait(SHOCKWAVE_TIME)
	await _play_damage_visuals(group, board, gs)


# --- Damage / heal / buff visuals ---

# All damage in the group plays SIMULTANEOUSLY: floaters + flashes +
# shakes + gem punches start together; the director awaits the longest
# non-floater part (the gem punch). Floaters (0.7s) keep floating after
# this returns. Hero death is the exception: slow-mo shake + 1s hold.
func _play_damage_visuals(group: Array, board: Board3D, gs: GameState) -> void:
	if not is_instance_valid(board):
		return
	var dead_heroes: Array = []
	for d in group:
		var target_kind: String = str(d.get("target_kind", ""))
		var p: int = int(d.get("player", 0))
		var uid: int = int(d.get("uid", -1))
		var amount: int = int(d.get("amount", 0))
		if target_kind == "hero":
			var plaque: HeroPlaque3D = board.hero_plaque(p)
			if plaque == null:
				continue
			board.update_hero_hp(p, int(gs.players[p]["hp"]))
			# Sprint 1c: hero floaters live ON the 2D badge panel — the
			# old 3D Label3D at the left-edge anchor could rise
			# off-screen.
			_boss_floater(board, p, "-%d" % amount, Color(1.0, 0.2, 0.2))
			if int(gs.players[p]["hp"]) <= 0:
				if not dead_heroes.has(p):
					dead_heroes.append(p)
			else:
				plaque.start_hero_damage(_dur(HERO_DAMAGE_TIME))
		else:
			var node: Minion3D = board.minion_node(uid)
			if node == null:
				continue
			# The node still exists even when the minion is dying (it is
			# removed by its later minion_died event), so the hit still
			# shows: floater + flash + shake. Only the stat update /
			# gem punch needs the live minion from gs — a dying minion
			# is already gone from the end state, and its numbers are
			# moot because the death animation follows.
			var m: Dictionary = gs.minion_by_uid(p, uid)
			if not m.is_empty():
				board.update_unit_stats(m, p == board.view_of(gs))
				node.punch_labels("hp", _dur(GEM_PUNCH_TIME))
			_spawn_floater(board, _float_pos(node), "-%d" % amount, Color(1.0, 0.2, 0.2))
			node.start_damage_flash(_dur(DAMAGE_FLASH_TIME))
			node.start_shake(_dur(DAMAGE_SHAKE_TIME))
	if not dead_heroes.is_empty():
		for hp_p in dead_heroes:
			var plaque2: HeroPlaque3D = board.hero_plaque(int(hp_p))
			if plaque2 != null:
				plaque2.start_hero_death(_dur(HERO_DEATH_SHAKE_TIME))
		await _wait(HERO_DEATH_SHAKE_TIME + HERO_DEATH_HOLD)
	else:
		await _wait(GEM_PUNCH_TIME)


func _spawn_floater(board: Board3D, pos: Vector3, text: String, color: Color) -> void:
	var fl: Label3D = board.get_floater()
	fl.text = text
	fl.position = pos
	fl.modulate = Color(color.r, color.g, color.b, 1.0)
	fl.scale = Vector3(1.6, 1.6, 1.6)
	var tw := fl.create_tween()
	fl.set_meta("anim_tween", tw)
	tw.tween_property(fl, "scale", Vector3.ONE, _dur(FLOATER_POP_TIME)).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(fl, "position:y", pos.y + DAMAGE_FLOAT_RISE, _dur(DAMAGE_FLOAT_TIME)).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(a: float) -> void: fl.modulate.a = a, 1.0, 0.0, _dur(DAMAGE_FLOAT_TIME))
	# Sprint 1a.5: a visible=false at fade end makes a stuck visible
	# floater impossible (e.g. the "+2" heal popup on the table rim).
	tw.tween_callback(fl.set_visible.bind(false))


func _play_heal(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var target_kind: String = str(data.get("target_kind", ""))
	var p: int = int(data.get("player", 0))
	var uid: int = int(data.get("uid", -1))
	var amount: int = int(data.get("amount", 0))
	if target_kind == "hero":
		var plaque: HeroPlaque3D = board.hero_plaque(p)
		if plaque == null:
			return
		board.update_hero_hp(p, int(gs.players[p]["hp"]))
		# Sprint 1c: hero floaters live ON the 2D badge panel (see above).
		_boss_floater(board, p, "+%d" % amount, Color(0.3, 1.0, 0.4))
		plaque.start_hero_heal(_dur(HEAL_GLOW_TIME))
		await _wait(HEAL_GLOW_TIME)
	else:
		var node: Minion3D = board.minion_node(uid)
		if node == null:
			return
		var m: Dictionary = gs.minion_by_uid(p, uid)
		if m.is_empty():
			return
		board.update_unit_stats(m, p == board.view_of(gs))
		# Transient green for the punch, then restore the state color
		# (red if still below max) via a second update_stats.
		node.set_hp_label_color(Color(0.3, 1.0, 0.4))
		_spawn_floater(board, _float_pos(node), "+%d" % amount, Color(0.3, 1.0, 0.4))
		node.start_heal_glow(_dur(HEAL_GLOW_TIME))
		node.punch_labels("hp", _dur(GEM_PUNCH_TIME))
		await _wait(max(HEAL_GLOW_TIME, GEM_PUNCH_TIME))
		if is_instance_valid(board):
			board.update_unit_stats(m, p == board.view_of(gs))


func _play_buff(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var p: int = int(data.get("player", 0))
	var uid: int = int(data.get("uid", -1))
	var node: Minion3D = board.minion_node(uid)
	if node == null:
		return
	var m: Dictionary = gs.minion_by_uid(p, uid)
	if m.is_empty():
		return
	board.update_unit_stats(m, p == board.view_of(gs))
	if node.unit != null:
		FxLab.sparks(board, node.position + Vector3(0, 0.2, 0), Color(1.0, 0.85, 0.3), 30, 2.4, 0.97)
		node.unit.tween_param("flash", 0.45, 0.0, _dur(GEM_PUNCH_TIME) * 1.4)
	else:
		board.spawn_particles("shimmer", node.position + Vector3(0, 0.4, 0))
	node.punch_labels("both", _dur(GEM_PUNCH_TIME))
	await _wait(GEM_PUNCH_TIME)


# --- Summon / death / destroy ---

func _play_summon(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var p: int = int(data.get("player", 0))
	var uid: int = int(data.get("uid", -1))
	var m: Dictionary = gs.minion_by_uid(p, uid)
	if m.is_empty():
		return
	var bi: int = gs.minion_index_by_uid(p, uid)
	# Neighbors slide aside BEFORE the token lands (only the summoning
	# player's row — see Board3D.slide_to_slots).
	if board.slide_to_slots(gs, p):
		await _wait(SLOT_SLIDE_TIME)
	board.add_unit(p, m, bi, board.view_of(gs), gs.players[p]["board"].size())
	var node: Minion3D = board.minion_node(uid)
	if node == null:
		return
	var slot: Vector3 = board.slot_position(p, bi, gs.players[p]["board"].size(), board.view_of(gs))
	if node.unit != null:
		# The hologram is built from the pad up, one layer of cubes at a
		# time, with loose cubes snapping in around it.
		node.position = slot
		var u: HoloUnit = node.unit
		var base_y: float = slot.y - 0.05
		var top_y: float = base_y + 2.0 * node.scale.y
		u.set_param("build_y", base_y)
		FxLab.pad_pulse(board, slot, u.pad_color)
		FxLab.cubes_converge(board, u.surface_points(70), u.color, _dur(BUILD_TIME) * 0.8)
		var tb := u.tween_param("build_y", base_y, top_y, _dur(BUILD_TIME))
		await tb.finished
		if is_instance_valid(u):
			u.set_param("build_y", 1000.0)
		return
	# Drop from above with a slight spin settling to 0.
	node.position = slot + Vector3(0, SUMMON_DROP_HEIGHT, 0)
	node.rotation.y = 0.6
	var tw := create_tween()
	tw.tween_property(node, "position", slot, _dur(SUMMON_DROP_TIME)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(node, "rotation:y", 0.0, _dur(SUMMON_DROP_TIME)).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_instance_valid(node) or not is_instance_valid(board):
		return
	# Land with a squash (scale y base*0.85 -> base*1.05 -> base) + a dust
	# ring. Hotfix 1c.1: relative to the token's base_scale — the old
	# absolute 0.85/1.05/1.0 left every summoned token ~1.85x too thick.
	board.spawn_particles("dust", slot + Vector3(0, 0.05, 0))
	var tw2 := create_tween()
	var bsy: float = node.base_scale.y if node.base_scale != Vector3.ZERO else node.scale.y
	tw2.tween_property(node, "scale:y", bsy * 0.85, _dur(SUMMON_SQUASH_TIME) * 0.4).set_ease(Tween.EASE_OUT)
	tw2.tween_property(node, "scale:y", bsy * 1.05, _dur(SUMMON_SQUASH_TIME) * 0.3).set_ease(Tween.EASE_OUT)
	tw2.tween_property(node, "scale:y", bsy, _dur(SUMMON_SQUASH_TIME) * 0.3).set_ease(Tween.EASE_OUT)
	await tw2.finished


func _play_deaths(deaths: Array, board: Board3D, gs: GameState) -> void:
	var removed: Array = []
	for d in deaths:
		var uid: int = int(d.get("uid", -1))
		var node: Minion3D = board.minion_node(uid)
		if node == null:
			continue
		removed.append(uid)
		board.cancel_slot_tween(uid)
		node.dying = true
		if node.unit != null:
			_model_death(node, board)
			continue
		board.spawn_particles("grey_puff", node.position + Vector3(0, 0.3, 0))
		var tw := create_tween()
		tw.tween_property(node, "rotation:x", deg_to_rad(DEATH_TILT_DEG), _dur(DEATH_TIME)).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "position:y", node.position.y - DEATH_SINK, _dur(DEATH_TIME)).set_ease(Tween.EASE_IN)
		tw.parallel().tween_method(node.set_fade, 1.0, 0.0, _dur(DEATH_TIME))
	if removed.is_empty():
		return
	var any_model: bool = false
	for uid2 in removed:
		var n2: Minion3D = board.minion_node(uid2)
		if n2 != null and n2.unit != null:
			any_model = true
	await _wait(GLITCH_TIME + DERES_TIME if any_model else DEATH_TIME)
	if not is_instance_valid(board):
		return
	for uid in removed:
		board.remove_unit(uid)
	# THEN the survivors slide together.
	if board.slide_to_slots(gs):
		await _wait(SLOT_SLIDE_TIME)


# A 3D Crew member's death: the hologram glitches, then breaks into cubes
# that drift up and blink out. Fire-and-forget; the caller awaits the
# total (GLITCH_TIME + DERES_TIME).
func _model_death(node: Minion3D, board: Board3D) -> void:
	var u: HoloUnit = node.unit
	u.busy = true
	var tg := u.tween_param("glitch", 0.0, 1.0, _dur(GLITCH_TIME))
	await tg.finished
	if not is_instance_valid(u) or not is_instance_valid(board):
		return
	FxLab.cubes_scatter(board, u.surface_points(220), u.color)
	u.tween_param("dissolve", 0.0, 1.0, _dur(DERES_TIME))


func _play_destroys(destroys: Array, board: Board3D, gs: GameState) -> void:
	# Distinct, harsher effect BEFORE the death: a dark crack flash and
	# a short black-purple burst. The following minion_died plays the
	# normal death.
	var any: bool = false
	for d in destroys:
		var uid: int = int(d.get("uid", -1))
		var node: Minion3D = board.minion_node(uid)
		if node == null:
			continue
		any = true
		var flash: MeshInstance3D = board.get_crack_flash()
		flash.position = node.position + Vector3(0, 0.4, 0)
		flash.scale = Vector3(0.5, 0.5, 0.5)
		var mat: StandardMaterial3D = flash.get_meta("mat")
		var tw := flash.create_tween()
		flash.set_meta("anim_tween", tw)
		tw.tween_property(flash, "scale", Vector3(1.8, 1.8, 1.8), _dur(DESTROY_FLASH_TIME)).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.9, 0.0, _dur(DESTROY_FLASH_TIME))
		tw.finished.connect(func() -> void: flash.visible = false)
		board.spawn_particles("destroy_burst", node.position + Vector3(0, 0.4, 0))
	if any:
		await _wait(DESTROY_FLASH_TIME)


# --- Steal / swap / hands / coin / draw / turn ---

func _play_steal(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var to_p: int = int(data.get("to_player", 0))
	var uid: int = int(data.get("uid", -1))
	var node: Minion3D = board.minion_node(uid)
	if node == null:
		return
	var bi: int = gs.minion_index_by_uid(to_p, uid)
	if bi < 0:
		return
	var dest: Vector3 = board.slot_position(to_p, bi, gs.players[to_p]["board"].size(), board.view_of(gs))
	board.cancel_slot_tween(uid)
	node.player = to_p
	node.set_pad_color(board._pad_color(gs, to_p))
	# Lift, glide across to the new owner's row, settle.
	var start_y: float = node.position.y
	var tw := create_tween()
	tw.tween_property(node, "position:y", start_y + STEAL_LIFT_HEIGHT, _dur(STEAL_GLIDE_TIME) * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", Vector3(dest.x, start_y + STEAL_LIFT_HEIGHT, dest.z), _dur(STEAL_GLIDE_TIME) * 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "position", dest, _dur(STEAL_GLIDE_TIME) * 0.2).set_ease(Tween.EASE_IN)
	await tw.finished
	if not is_instance_valid(board):
		return
	# Both rows settle.
	if board.slide_to_slots(gs):
		await _wait(SLOT_SLIDE_TIME)


func _play_stats_swap(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var p: int = int(data.get("player", 0))
	var uid: int = int(data.get("uid", -1))
	var node: Minion3D = board.minion_node(uid)
	if node == null:
		return
	var m: Dictionary = gs.minion_by_uid(p, uid)
	if m.is_empty():
		return
	# Both gems spin a half-turn, then land on the new numbers.
	node.spin_gems(_dur(SWAP_SPIN_TIME))
	await _wait(SWAP_SPIN_TIME)
	if not is_instance_valid(board):
		return
	board.update_unit_stats(m, p == board.view_of(gs))


func _play_coin_flip(data: Dictionary, board: Board3D, gs: GameState) -> void:
	# Sprint 1c: the coin flip is a center-screen moment. The old version
	# played at the hero's 3D anchor on the left edge and could rise
	# off-screen; this spins a large coin at the table center, lands
	# showing HEADS/TAILS with a text label, holds ~0.6s, then the
	# effect's own events follow.
	var heads: bool = bool(data.get("heads", false))
	await board.flip_coin_center(heads, _dur(COIN_SPIN_TIME), _dur(COIN_RESULT_HOLD_TIME))


func _play_draw(data: Dictionary, board: Board3D, gs: GameState) -> void:
	var p: int = int(data.get("player", 0))
	await board.animate_draw(p, board.view_of(gs), _dur(DRAW_SLIDE_TIME))


func _play_turn_start(data: Dictionary, board: Board3D, gs: GameState, banner: Callable) -> void:
	var p: int = int(data.get("player", 0))
	# Mana gems light up one at a time, left to right.
	var mana: int = int(gs.players[p]["mana"])
	board.animate_mana_gems(p, mana, _dur(MANA_GEM_POP_TIME), _dur(MANA_GEM_STAGGER))
	await _wait(MANA_GEM_POP_TIME + MANA_GEM_STAGGER * float(max(mana, 1)))
	# "YOUR TURN" banner sweeps in and out before input unlocks.
	if banner.is_valid():
		await banner.call()
