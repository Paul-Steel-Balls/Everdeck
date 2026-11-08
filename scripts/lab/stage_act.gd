extends Node
class_name StageAct

# The hero stands at their deck's set piece, turned three-quarters toward it
# (never turning back to the camera), and every so often slowly plays with it:
# Grunk leans on the detonator and it sparks, Agatha checks the soup and the
# lid rattles, Presto reads and the book glows, Barnacle spins the wheel,
# Reginald salutes and the sword gleams, Larry spins the roulette wheel.
# Everything is eased acting offsets on the hero plus effects on the prop,
# so it slides in and out of the idle loop without a visible seam.

var theme: String = ""
var hero: HoloUnit
var prop: Node3D          # the set piece's holder
var prop_size: float = 3.0
var color: Color = Color.WHITE
var interval: Vector2 = Vector2(20.0, 30.0)  # seconds between acts (random in range)
var first_delay: float = 3.0

var _wait: float = 0.0
var _busy: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_wait = first_delay
	# Stand at the set piece: face between the camera and the prop.
	if hero != null and prop != null:
		var d: Vector3 = prop.global_position - hero.global_position
		hero.act_turn = atan2(d.x, d.z) * 0.6
		hero.act_w = 1.0
		hero.idle_sway = 0.05


func _process(delta: float) -> void:
	if _busy or hero == null or prop == null or not is_instance_valid(hero):
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = _rng.randf_range(interval.x, interval.y)
		play()


func _tw() -> Tween:
	return create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _top(f: float = 0.75) -> Vector3:
	return prop.global_position + Vector3(0, prop_size * f, 0)


func play() -> void:
	if _busy:
		return
	_busy = true
	var d: Vector3 = prop.global_position - hero.global_position
	# A slow half-step in toward the set piece.
	var t1 := _tw()
	t1.tween_property(hero, "act_step", Vector3(d.x, 0, d.z).normalized() * 0.28, 0.9)
	await t1.finished
	match theme:
		"grunk":
			await _grunk()
		"agatha":
			await _agatha()
		"presto":
			await _presto()
		"barnacle":
			await _barnacle(d)
		"reginald":
			await _reginald()
		"larry":
			await _larry()
	# Settle back into the idle loop.
	var t2 := _tw()
	t2.tween_property(hero, "act_lean", 0.0, 0.9)
	t2.parallel().tween_property(hero, "act_hop", 0.0, 0.9)
	t2.parallel().tween_property(hero, "act_step", Vector3.ZERO, 1.1)
	await t2.finished
	_busy = false


func _shake(node: Node3D, amount: float, times: int, step: float) -> void:
	var r0: Vector3 = node.rotation
	var tw := create_tween()
	for i in times:
		var s: float = (1.0 if i % 2 == 0 else -1.0) * amount * (1.0 - float(i) / times)
		tw.tween_property(node, "rotation:z", r0.z + s, step)
	tw.tween_property(node, "rotation:z", r0.z, step)
	await tw.finished


func _squash(node: Node3D, y: float, dur: float) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3(1.0 + (1.0 - y) * 0.5, y, 1.0 + (1.0 - y) * 0.5), dur * 0.3)
	tw.tween_property(node, "scale", Vector3.ONE, dur * 0.7)
	await tw.finished


func _puff(pos: Vector3, col: Color, n: int, speed: float) -> void:
	FxLab.burst(get_parent(), pos, col, n, speed)


# Grunk leans on the plunger: the detonator squashes, sparks fly, a puff of
# smoke, and Grunk bounces with glee.
func _grunk() -> void:
	var t := _tw()
	t.tween_property(hero, "act_lean", deg_to_rad(16), 0.6)
	t.parallel().tween_property(hero, "act_hop", -0.05, 0.6)
	await t.finished
	_squash(prop, 0.94, 0.6)
	FxLab.sparks(get_parent(), _top(0.4), Color(1.0, 0.65, 0.2), 70, 5.5, 0.6)
	FxLab.glint(get_parent(), _top(0.42), Color(1.0, 0.8, 0.4), 0.7)
	FxLab.flash_light(get_parent(), _top(0.5), Color(1.0, 0.6, 0.2), 3.0)
	await get_tree().create_timer(0.18).timeout
	FxLab.sparks(get_parent(), _top(0.4), Color(1.0, 0.75, 0.3), 30, 3.5, 0.8)
	var t2 := _tw()
	t2.tween_property(hero, "act_lean", deg_to_rad(-4), 0.25)
	t2.tween_property(hero, "act_hop", 0.25, 0.18)
	t2.tween_property(hero, "act_hop", 0.0, 0.18)
	t2.tween_property(hero, "act_hop", 0.12, 0.14)
	t2.tween_property(hero, "act_hop", 0.0, 0.14)
	await t2.finished


# Agatha leans over the stove to check the soup: the pot rattles and steam
# puffs up; she nods, satisfied.
func _agatha() -> void:
	var t := _tw()
	t.tween_property(hero, "act_lean", deg_to_rad(14), 0.9)
	await t.finished
	_shake(prop, 0.02, 8, 0.07)
	for i in 3:
		FxLab.wisps(get_parent(), _top(0.8), 8)
		await get_tree().create_timer(0.35).timeout
	var t2 := _tw()
	for i in 2:
		t2.tween_property(hero, "act_lean", deg_to_rad(20), 0.2)
		t2.tween_property(hero, "act_lean", deg_to_rad(10), 0.2)
	await t2.finished


# Presto bends over the lectern: the pages glow and blue motes swirl up.
func _presto() -> void:
	var t := _tw()
	t.tween_property(hero, "act_lean", deg_to_rad(10), 0.6)
	await t.finished
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.5)
	l.omni_range = prop_size * 1.5
	l.light_energy = 0.0
	get_parent().add_child(l)
	l.global_position = _top(0.8)
	var tl := create_tween()
	tl.tween_property(l, "light_energy", 6.0, 0.6)
	tl.tween_property(l, "light_energy", 0.0, 1.2)
	tl.tween_callback(l.queue_free)
	for i in 4:
		FxLab.sparks(get_parent(), _top(0.7), Color(0.55, 0.85, 1.0), 14, 1.6, 0.95)
		FxLab.glint(get_parent(), _top(0.75) + Vector3(_rng.randf_range(-0.4, 0.4), 0.2, 0), Color(0.6, 0.85, 1.0), 0.35)
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.3).timeout


# Barnacle steps up and spins the wheel: a ring of light whirls on it and a
# few coins sparkle.
func _barnacle(d: Vector3) -> void:
	var t := _tw()
	t.tween_property(hero, "act_step", Vector3(d.x, 0, d.z).normalized() * 0.3, 0.6)
	t.parallel().tween_property(hero, "act_lean", deg_to_rad(6), 0.5)
	await t.finished
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = prop_size * 0.2
	tm.outer_radius = prop_size * 0.215
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 0.0)
	ring.material_override = m
	prop.add_child(ring)
	ring.position = Vector3(-prop_size * 0.15, prop_size * 0.55, 0)
	ring.rotation = Vector3(PI / 2, 0, 0)
	var tr := create_tween()
	tr.tween_property(m, "albedo_color:a", 0.8, 0.2)
	tr.parallel().tween_property(ring, "rotation:y", TAU * 3.0, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tr.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tr.tween_callback(ring.queue_free)
	_shake(prop, 0.012, 6, 0.08)
	await get_tree().create_timer(0.8).timeout
	for i in 3:
		FxLab.glint(get_parent(), _top(0.3) + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.3, 0.3)), Color(1.0, 0.85, 0.35), 0.4)
		await get_tree().create_timer(0.12).timeout
	await tr.finished


# Reginald stands tall and salutes the monument: the sword gleams.
func _reginald() -> void:
	var t := _tw()
	t.tween_property(hero, "act_lean", deg_to_rad(-5), 0.4)
	t.parallel().tween_property(hero, "act_hop", 0.08, 0.4)
	await t.finished
	FxLab.glint(get_parent(), _top(1.0), Color(1.0, 1.0, 0.9), 1.0)
	FxLab.flash_light(get_parent(), _top(0.95), Color(1.0, 1.0, 0.9), 2.5)
	await get_tree().create_timer(0.9).timeout
	var t2 := _tw()
	t2.tween_property(hero, "act_lean", deg_to_rad(12), 0.35)  # a bow
	t2.tween_property(hero, "act_lean", 0.0, 0.35)
	await t2.finished


# Larry gives the roulette a spin: a glowing ball races around the wheel,
# slows, and a little shower of chips pops when it lands.
func _larry() -> void:
	var t := _tw()
	t.tween_property(hero, "act_lean", deg_to_rad(8), 0.4)
	await t.finished
	var pivot := Node3D.new()
	prop.add_child(pivot)
	pivot.position = Vector3(0, prop_size * 0.42, 0)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 1.0, 0.9)
	ball.material_override = bm
	pivot.add_child(ball)
	ball.position = Vector3(prop_size * 0.22, 0, 0)
	var tr := create_tween()
	tr.tween_property(pivot, "rotation:y", TAU * 4.5 + _rng.randf() * TAU, 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	await tr.finished
	FxLab.glint(get_parent(), ball.global_position + Vector3(0, 0.1, 0), Color(1.0, 0.9, 0.5), 0.6)
	FxLab.sparks(get_parent(), ball.global_position + Vector3(0, 0.1, 0), Color(1.0, 0.85, 0.3), 24, 2.5, 0.9)
	var t2 := _tw()
	t2.tween_property(hero, "act_hop", 0.18, 0.15)
	t2.tween_property(hero, "act_hop", 0.0, 0.2)
	await t2.finished
	await get_tree().create_timer(0.4).timeout
	pivot.queue_free()
