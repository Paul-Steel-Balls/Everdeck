extends Node3D
class_name HoloUnit

# Prototype minion for the Battlefield Preview. Three looks:
#   CARD   - the card's painting as a standing hologram panel on an emitter
#   FIGURE - a hologram toy figure built from simple shapes (body types)
#   BUST   - a physical pedestal "chess piece" projecting a hologram bust
#   MODEL  - the card's own 3D model in its painted colors, with only a
#            light hologram touch (class-color rim, faint scanlines)
# Each look has its own way of moving, attacking, getting hit and dying.

enum Style { CARD, FIGURE, BUST, MODEL }

const HOLO_SHADER := preload("res://shaders/lab/holo.gdshader")
const LITE_SHADER := preload("res://shaders/lab/holo_lite.gdshader")
const OUTLINE_SHADER := preload("res://shaders/lab/holo_outline.gdshader")
const MODEL_HEIGHT := 1.55  # tallest a model stands (before the unit's scale)
const MODEL_WIDTH := 1.2   # widest it may be, so neighbours don't overlap

var card_id: String = ""
var kind: String = "goblin"  # goblin / knight / beast / golem (FIGURE look)
var style: int = Style.CARD
var side: float = 1.0  # +1 = my row (near camera), -1 = enemy
var color: Color = Color(0.7, 0.4, 1.0)
var pad_color: Color = Color(0.7, 0.4, 1.0)
var home: Vector3 = Vector3.ZERO
var busy: bool = false
# Acting offsets (MODEL look), layered on top of the idle motion so a scripted
# action eases in and out of the idle loop with no seam.
var act_turn: float = 0.0     # facing while acting (radians)
var act_w: float = 0.0        # 0 = idle sway, 1 = fully turned to act_turn
var act_lean: float = 0.0     # forward lean (radians, about the feet)
var act_hop: float = 0.0      # extra height
var act_step: Vector3 = Vector3.ZERO  # small step toward something
var idle_sway: float = 0.16   # how far the idle look-around turns (radians)
# Crew on the board face the other side of the table: units in the near
# half (z > 0) turn by NEAR_YAW, far ones keep facing the camera (which is
# the near side). Eased, so a stolen unit turns round as it changes rows.
var face_enemy: bool = false
var pop: bool = false            # set before _ready: outline + richer color
const POP_SATURATION := 1.2
const POP_CONTRAST := 1.08
var near_yaw: float = PI
var _base_yaw: float = 0.0
var _yaw_set: bool = false

var _vis: Node3D        # everything that moves/tilts with the unit
var _mats: Array = []   # holo materials (for flash / dissolve / fade)
var _arm: Node3D        # FIGURE: weapon arm pivot
var _t: float = 0.0
var _shield: MeshInstance3D
var _pad_mat: ShaderMaterial


func setup(cid: String, k: String, st: int, s: float, col: Color, pad: Color = Color(0, 0, 0, 0)) -> void:
	pad_color = col if pad.a == 0.0 else pad
	card_id = cid
	kind = k
	style = st
	side = s
	color = col


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	match style:
		Style.CARD:
			_build_card()
		Style.FIGURE:
			_build_figure()
		Style.BUST:
			_build_bust()
		Style.MODEL:
			if not _build_model():
				style = Style.FIGURE
				_build_figure()
	# Face the camera's side of the table.
	if side < 0.0 and style != Style.MODEL:
		_vis.rotation.y = PI if style == Style.FIGURE else 0.0


func _process(delta: float) -> void:
	_t += delta
	if busy:
		return
	match style:
		Style.CARD:
			_vis.position.y = sin(_t * 1.8 + home.x) * 0.04
		Style.FIGURE:
			_vis.position.y = abs(sin(_t * 2.2 + home.x)) * 0.03
			_vis.scale = Vector3(1.0 + sin(_t * 4.4) * 0.015, 1.0 - sin(_t * 4.4) * 0.015, 1.0)
		Style.MODEL:
			# Breathing and a slow look-around facing the camera, blended with
			# any acting offsets.
			var sway: float = sin(_t * 0.6 + home.x * 1.7) * idle_sway
			if face_enemy and is_inside_tree():
				var want: float = near_yaw if global_position.z > 0.0 else 0.0
				_base_yaw = want if not _yaw_set else lerp_angle(_base_yaw, want, minf(1.0, delta * 5.0))
				_yaw_set = true
			_vis.position = act_step + Vector3(0, sin(_t * 2.0 + home.x) * 0.02 + 0.02 + act_hop, 0)
			_vis.scale = Vector3(1.0, 1.0 + sin(_t * 2.6 + home.x) * 0.012, 1.0)
			_vis.rotation = Vector3(act_lean, lerp_angle(_base_yaw + sway, act_turn, act_w) + sway * act_w, 0)
		Style.BUST:
			var b: Node3D = _vis.get_node_or_null("Bust")
			if b != null:
				b.position.y = 1.0 + sin(_t * 1.6 + home.x) * 0.05
				b.rotation.y = sin(_t * 0.7 + home.x) * 0.12


# --- Materials ---

func _holo(textured: bool, uv_rect: Rect2 = Rect2(0, 0, 1, 1), oval: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLO_SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("use_tex", textured)
	if textured:
		var tex: Texture2D = CardArt.texture_for(card_id)
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))
	m.set_shader_parameter("oval_mask", oval)
	_mats.append(m)
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else _vis).add_child(mi)
	return mi


func _emitter(radius: float) -> void:
	# Summoning circle under every unit, in its SIDE's color (the hero's).
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.4, radius * 2.4)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/lab/rune_pad.gdshader")
	m.set_shader_parameter("col", pad_color)
	_pad_mat = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _cone(height: float, radius: float) -> void:
	# Soft light cone rising from the pad.
	var c := CylinderMesh.new()
	c.top_radius = radius * 1.15
	c.bottom_radius = radius * 0.8
	c.height = height
	c.cap_top = false
	c.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.10)
	_mesh(c, m, Vector3(0, height * 0.5, 0), self)


# --- Looks ---

func _build_model() -> bool:
	var root: Node3D = ModelLib.instance(card_id)
	if root == null:
		return false
	_emitter(0.5)
	var box: AABB = ModelLib.bounds(root)
	var k: float = min(MODEL_HEIGHT / max(box.size.y, 0.01), MODEL_WIDTH / max(max(box.size.x, box.size.z), 0.01))
	var holder := Node3D.new()
	holder.name = "Model"
	holder.scale = Vector3(k, k, k)
	# Feet on the pad, centred over it.
	holder.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	_vis.add_child(holder)
	holder.add_child(root)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m.mesh.get_surface_count():
			m.set_surface_override_material(si, _lite(m.get_active_material(si)))
	kind = "model"
	return true


func _lite(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LITE_SHADER
	m.set_shader_parameter("tint", color)
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		m.set_shader_parameter("albedo_tex", b.albedo_texture)
		if b.normal_enabled and b.normal_texture != null:
			m.set_shader_parameter("normal_tex", b.normal_texture)
			m.set_shader_parameter("use_normal", true)
		var orm: Texture2D = b.ao_texture if b.ao_texture != null else b.roughness_texture
		if orm != null:
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("use_orm", true)
	_mats.append(m)
	if pop:
		# Crew on the battlefield: richer colors, a brighter rim and a thin
		# ink outline so they stand out from the arena floor.
		m.set_shader_parameter("saturation", POP_SATURATION)
		m.set_shader_parameter("contrast", POP_CONTRAST)
		m.set_shader_parameter("rim_white", 0.45)
		m.set_shader_parameter("rim_strength", 0.7)
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter("line_color", color.darkened(0.88))
		m.next_pass = o
		_mats.append(o)
	return m

func _build_card() -> void:
	_emitter(0.6)
	_cone(0.5, 0.5)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.42)
	var panel := _mesh(q, _holo(true, Rect2(0, 0.02, 1, 0.96)), Vector3(0, 0.95, 0))
	panel.name = "Panel"
	panel.rotation.x = deg_to_rad(-12)


func _build_bust() -> void:
	# Physical pedestal: dark metal with a glowing class ring.
	var ped := CylinderMesh.new()
	ped.top_radius = 0.4
	ped.bottom_radius = 0.5
	ped.height = 0.3
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.1, 0.16)
	pm.metallic = 0.85
	pm.roughness = 0.3
	var p := MeshInstance3D.new()
	p.mesh = ped
	p.material_override = pm
	p.position.y = 0.15
	_vis.add_child(p)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.38
	ring.outer_radius = 0.44
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = color
	rm.emission_enabled = true
	rm.emission = color
	rm.emission_energy_multiplier = 3.0
	var r := MeshInstance3D.new()
	r.mesh = ring
	r.material_override = rm
	r.position.y = 0.3
	_vis.add_child(r)
	var c := CylinderMesh.new()
	c.top_radius = 0.55
	c.bottom_radius = 0.3
	c.height = 0.7
	c.cap_top = false
	c.cap_bottom = false
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.albedo_color = Color(color.r, color.g, color.b, 0.12)
	_mesh(c, cm, Vector3(0, 0.65, 0))
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var bust := _mesh(q, _holo(true, Rect2(0.08, 0.02, 0.84, 0.6), 1.0), Vector3(0, 1.05, 0))
	bust.name = "Bust"


func _build_figure() -> void:
	_emitter(0.5)
	var m := _holo(false)
	match kind:
		"goblin":
			_mesh(_capsule(0.22, 0.62), m, Vector3(0, 0.42, 0))
			var head := _mesh(_sphere(0.27), m, Vector3(0, 0.98, 0))
			for sx in [-1.0, 1.0]:
				var ear := _mesh(_cone_mesh(0.09, 0.42), m, Vector3(sx * 0.3, 1.05, 0))
				ear.rotation.z = -sx * deg_to_rad(70)
			_mesh(_sphere(0.05), m, Vector3(-0.1, 1.0, 0.24))
			_mesh(_sphere(0.05), m, Vector3(0.1, 1.0, 0.24))
			_arm = Node3D.new()
			_arm.position = Vector3(0.28, 0.62, 0)
			_vis.add_child(_arm)
			_mesh(_capsule(0.06, 0.4), m, Vector3(0, -0.15, 0), _arm)
			var dyn := _mesh(_cyl(0.06, 0.32), _holo_color(Color(1, 0.3, 0.2)), Vector3(0, -0.38, 0.06), _arm)
			dyn.rotation.x = deg_to_rad(80)
			head.name = "Head"
		"knight":
			_mesh(_capsule(0.26, 0.9), m, Vector3(0, 0.55, 0))
			var helm := _mesh(_cyl(0.2, 0.32), m, Vector3(0, 1.18, 0))
			helm.name = "Head"
			_mesh(_box(Vector3(0.3, 0.04, 0.05)), m, Vector3(0, 1.2, 0.2))
			var plume := _mesh(_cone_mesh(0.08, 0.35), _holo_color(Color(1, 0.3, 0.3)), Vector3(0, 1.45, -0.05))
			plume.rotation.x = deg_to_rad(-20)
			var sh := _mesh(_cyl(0.3, 0.06), m, Vector3(-0.32, 0.62, 0.08))
			sh.rotation.z = deg_to_rad(90)
			sh.rotation.y = deg_to_rad(90)
			_arm = Node3D.new()
			_arm.position = Vector3(0.32, 0.8, 0)
			_vis.add_child(_arm)
			_mesh(_capsule(0.07, 0.42), m, Vector3(0, -0.18, 0), _arm)
			var blade := _mesh(_box(Vector3(0.07, 0.8, 0.03)), _holo_color(Color(0.8, 0.95, 1.0)), Vector3(0, -0.2, 0.42), _arm)
			blade.rotation.x = deg_to_rad(90)
		"beast":
			var body := _mesh(_capsule(0.24, 0.95), m, Vector3(0, 0.5, 0))
			body.rotation.x = deg_to_rad(90)
			var head2 := _mesh(_sphere(0.24), m, Vector3(0, 0.72, 0.52))
			head2.name = "Head"
			for sx2 in [-1.0, 1.0]:
				_mesh(_cone_mesh(0.07, 0.24), m, Vector3(sx2 * 0.13, 0.98, 0.5))
				for sz in [-0.28, 0.28]:
					_mesh(_capsule(0.06, 0.38), m, Vector3(sx2 * 0.16, 0.19, sz))
			var tail := _mesh(_capsule(0.06, 0.5), m, Vector3(0, 0.7, -0.55))
			tail.rotation.x = deg_to_rad(-40)
		_:  # golem
			_mesh(_box(Vector3(0.8, 0.85, 0.5)), m, Vector3(0, 0.62, 0))
			var h3 := _mesh(_box(Vector3(0.36, 0.3, 0.34)), m, Vector3(0, 1.2, 0.04))
			h3.name = "Head"
			for sx3 in [-1.0, 1.0]:
				_mesh(_box(Vector3(0.26, 0.7, 0.3)), m, Vector3(sx3 * 0.56, 0.52, 0))
	# Small portrait medallion so you can tell which card it is.
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.42)
	var med := _mesh(q, _holo(true, Rect2(0.15, 0.05, 0.7, 0.5), 1.0), Vector3(0, 1.75 if kind != "beast" else 1.35, 0))
	med.rotation.x = deg_to_rad(-15)
	med.name = "Medallion"


func _holo_color(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLO_SHADER
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("use_tex", false)
	_mats.append(m)
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _cone_mesh(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	return c


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


# --- Shared effects on the unit ---

func set_param(p: String, v: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(p, v)


func get_param(p: String) -> Variant:
	return _mats[0].get_shader_parameter(p) if not _mats.is_empty() else null


func tween_param(p: String, from: float, to: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: set_param(p, v), from, to, dur)
	return tw


func attack_point() -> Vector3:
	return global_position + Vector3(0, 0.9, 0)


# --- Actions ---

# Summon: the hologram is built from the pad up, one layer of cubes at a
# time, with a few loose cubes snapping into place around it.
func summon() -> void:
	busy = true
	var base_y: float = global_position.y - 0.05
	var top_y: float = base_y + 2.0
	set_param("build_y", base_y)
	FxLab.pad_pulse(get_parent(), global_position, color)
	FxLab.cubes_converge(get_parent(), surface_points(70), color, 0.7)
	var tw := tween_param("build_y", base_y, top_y, 0.85)
	await tw.finished
	set_param("build_y", 1000.0)
	busy = false


func hit(amount: int) -> void:
	tween_param("flash", 0.6, 0.0, 0.2)
	if style == Style.MODEL:
		knock()
		FxLab.damage_number(get_parent(), attack_point() + Vector3(0, 0.5, 0), amount)
		return
	var p0: Vector3 = _vis.position
	var tw := create_tween()
	for d in [0.12, -0.1, 0.07, -0.04, 0.0]:
		tw.tween_property(_vis, "position:x", p0.x + d, 0.04)
	FxLab.damage_number(get_parent(), attack_point() + Vector3(0, 0.5, 0), amount)


# Knocked back a step with a wobble, then settles (MODEL look).
func knock(strength: float = 1.0) -> void:
	var kb := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	kb.tween_property(self, "act_lean", deg_to_rad(-12) * strength, 0.08)
	kb.parallel().tween_property(self, "act_step", Vector3(0, 0, -0.12 * side) * strength, 0.08)
	kb.tween_property(self, "act_lean", deg_to_rad(5) * strength, 0.12)
	kb.tween_property(self, "act_lean", 0.0, 0.18)
	kb.parallel().tween_property(self, "act_step", Vector3.ZERO, 0.25)


# The summoning pad's color (the owner's Boss color; changes on a steal).
func set_pad_color(c: Color) -> void:
	pad_color = c
	if _pad_mat != null:
		_pad_mat.set_shader_parameter("col", c)


# Death: the hologram glitches, then breaks into cubes that drift up and
# blink out ("derezzed").
func die() -> void:
	busy = true
	var tg := tween_param("glitch", 0.0, 1.0, 0.35)
	await tg.finished
	FxLab.cubes_scatter(get_parent(), surface_points(220), color)
	var td := tween_param("dissolve", 0.0, 1.0, 0.55)
	await td.finished
	visible = false
	await get_tree().create_timer(1.2).timeout
	queue_free()


# Random points on the surfaces of this unit's hologram meshes (world
# space), used to seed the cube effects so they take the unit's shape.
func surface_points(n: int) -> PackedVector3Array:
	var tris: Array = []
	for mi in _vis.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not (m.material_override is ShaderMaterial or m.get_surface_override_material(0) is ShaderMaterial):
			continue
		var faces: PackedVector3Array = m.mesh.get_faces()
		var xf: Transform3D = m.global_transform
		for i in range(0, faces.size(), 3):
			tris.append([xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]])
	var out := PackedVector3Array()
	if tris.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	for k in n:
		var t: Array = tris[rng.randi() % tris.size()]
		var u: float = rng.randf()
		var v: float = rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		out.append(t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v)
	return out


func shield(on: bool) -> void:
	if on and _shield == null:
		var s := SphereMesh.new()
		s.radius = 0.85
		s.height = 1.5
		_shield = MeshInstance3D.new()
		_shield.mesh = s
		var m := ShaderMaterial.new()
		m.shader = HOLO_SHADER
		m.set_shader_parameter("tint", Color(0.5, 0.85, 1.0))
		m.set_shader_parameter("strength", 0.55)
		_shield.material_override = m
		_shield.position.y = 0.75
		add_child(_shield)
		_shield.scale = Vector3(0.1, 0.1, 0.1)
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_shield, "scale", Vector3.ONE, 0.35)
	elif not on and _shield != null:
		_shield.queue_free()
		_shield = null


# Walk/slide/dash to the target, strike in this look's style, come back.
func melee(target: HoloUnit) -> void:
	busy = true
	var start: Vector3 = position
	var dest: Vector3 = target.position + Vector3(0, 0, 0.95 * side)
	match style:
		Style.CARD:
			var panel: Node3D = _vis.get_node("Panel")
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(panel, "rotation:x", deg_to_rad(18), 0.2)  # rear back
			tw.tween_property(self, "position", dest, 0.28).set_trans(Tween.TRANS_EXPO)
			tw.parallel().tween_property(panel, "rotation:x", deg_to_rad(-55), 0.28)  # slam forward
			await tw.finished
			FxLab.impact(get_parent(), target.attack_point(), color)
			target.hit(3)
			var back := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			back.tween_property(panel, "rotation:x", deg_to_rad(-12), 0.3)
			back.parallel().tween_property(self, "position", start, 0.45)
			await back.finished
		Style.FIGURE:
			# Hop over in three bounces, swing, hop back.
			await _hops(start, dest, 3, 0.75)
			await _swing(target)
			await _hops(dest, start, 2, 0.5)
		Style.MODEL:
			await _model_strike(target, start, dest)
		Style.BUST:
			# The pedestal glides like a chess piece; the bust lunges.
			var bust: Node3D = _vis.get_node("Bust")
			var tw2 := create_tween()
			tw2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw2.tween_property(self, "position", dest, 0.55)
			tw2.parallel().tween_property(self, "position:y", 0.25, 0.27)
			tw2.tween_property(self, "position:y", 0.0, 0.1)
			tw2.tween_property(bust, "position:z", -0.5 * side, 0.12).set_trans(Tween.TRANS_BACK)
			await tw2.finished
			FxLab.impact(get_parent(), target.attack_point(), color)
			target.hit(3)
			var back2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			back2.tween_property(bust, "position:z", 0.0, 0.2)
			back2.tween_property(self, "position", start, 0.5)
			await back2.finished
	position = start
	busy = false


# A readable strike: turn, wind up, dash in, a short hit-pause where both
# freeze, a sharp impact effect over the contact point, then recover.
func _model_strike(target: HoloUnit, start: Vector3, dest: Vector3) -> void:
	var d: Vector3 = target.position - position
	var face: float = atan2(d.x, d.z)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "act_turn", face, 0.01)
	tw.tween_property(self, "act_w", 1.0, 0.14)
	await tw.finished
	busy = false  # let the acting offsets drive the pose during the strike
	var back: Vector3 = -Vector3(d.x, 0, d.z).normalized() * 0.18
	var wind := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wind.tween_property(self, "act_lean", deg_to_rad(-14), 0.2)
	wind.parallel().tween_property(self, "act_step", back, 0.2)
	await wind.finished
	var dash := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	dash.tween_property(self, "position", dest, 0.16)
	dash.parallel().tween_property(self, "act_lean", deg_to_rad(16), 0.16)
	dash.parallel().tween_property(self, "act_step", Vector3.ZERO, 0.16)
	await dash.finished
	# Hit-pause: both freeze for a beat so the blow lands.
	busy = true
	target.busy = true
	var hp: Vector3 = target.attack_point()
	FxLab.slash(get_parent(), hp, color, face)
	FxLab.sparks(get_parent(), hp, Color(1.0, 0.85, 0.5), 36, 5.0, 0.3)
	FxLab.glint(get_parent(), hp, Color(1, 1, 1), 0.8)
	FxLab.shock_ring(get_parent(), Vector3(hp.x, target.global_position.y + 0.05, hp.z), color, 1.2)
	_cam_shake(0.12, 0.18)
	await get_tree().create_timer(0.09).timeout
	target.busy = false
	target.hit(3)
	busy = false
	var ret := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ret.tween_property(self, "position", start, 0.4)
	ret.parallel().tween_property(self, "act_lean", 0.0, 0.35)
	ret.tween_property(self, "act_w", 0.0, 0.25)
	await ret.finished
	busy = true


func _cam_shake(amount: float, dur: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var tw := create_tween()
	var n := 5
	for i in n:
		var k: float = amount * (1.0 - float(i) / n)
		tw.tween_property(cam, "h_offset", randf_range(-k, k), dur / n)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-k, k), dur / n)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)


func _hops(from: Vector3, to: Vector3, n: int, dur: float) -> void:
	var tw := create_tween()
	for i in n:
		var a: Vector3 = from.lerp(to, float(i) / n)
		var b: Vector3 = from.lerp(to, float(i + 1) / n)
		var mid: Vector3 = (a + b) * 0.5 + Vector3(0, 0.35, 0)
		tw.tween_property(self, "position", mid, dur / n * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "position", b, dur / n * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(_vis, "scale", Vector3(1.15, 0.8, 1.15), 0.05)
		tw.tween_property(_vis, "scale", Vector3.ONE, 0.06)
	await tw.finished


func _swing(target: HoloUnit) -> void:
	var tw := create_tween()
	match kind:
		"knight":
			tw.tween_property(_arm, "rotation:x", deg_to_rad(-110), 0.18).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_arm, "rotation:x", deg_to_rad(60), 0.12).set_trans(Tween.TRANS_EXPO)
		"goblin":
			tw.tween_property(_arm, "rotation:x", deg_to_rad(-140), 0.16)
			tw.tween_property(_arm, "rotation:x", deg_to_rad(40), 0.1)
		_:
			# Pounce / body slam.
			tw.tween_property(_vis, "position", Vector3(0, 0.5, -0.4 * side), 0.15).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_vis, "position", Vector3(0, 0, -0.1 * side), 0.1)
	await tw.finished
	FxLab.impact(get_parent(), target.attack_point(), color)
	target.hit(3)
	var tw2 := create_tween()
	if _arm != null:
		tw2.tween_property(_arm, "rotation:x", 0.0, 0.2)
	tw2.parallel().tween_property(_vis, "position", Vector3.ZERO, 0.2)
	await tw2.finished


# Ranged attack: a bolt from the unit to a point.
func ranged(to: Vector3) -> void:
	busy = true
	match style:
		Style.FIGURE:
			if _arm != null:
				var tw := create_tween()
				tw.tween_property(_arm, "rotation:x", deg_to_rad(-150), 0.18)
				tw.tween_property(_arm, "rotation:x", deg_to_rad(20), 0.1)
				await tw.finished
		_:
			var tw2 := create_tween()
			tw2.tween_property(_vis, "position:z", 0.25 * side, 0.12)
			tw2.tween_property(_vis, "position:z", -0.2 * side, 0.08)
			await tw2.finished
	await FxLab.projectile(get_parent(), attack_point(), to, color)
	var tw3 := create_tween()
	tw3.tween_property(_vis, "position", Vector3.ZERO, 0.2)
	if _arm != null:
		tw3.parallel().tween_property(_arm, "rotation:x", 0.0, 0.2)
	await tw3.finished
	busy = false


# Emotes: the Boss acts out what it says (hop, nod, bow, startle,
# wobble, lunge), using the same acting offsets as attacks.
func emote_act(id: String) -> void:
	if busy:
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	match id:
		"hey":
			for i in 2:
				tw.tween_property(self, "act_hop", 0.22, 0.13).set_ease(Tween.EASE_OUT)
				tw.tween_property(self, "act_hop", 0.0, 0.13).set_ease(Tween.EASE_IN)
		"nice":
			for i in 2:
				tw.tween_property(self, "act_lean", deg_to_rad(14), 0.14)
				tw.tween_property(self, "act_lean", 0.0, 0.16)
		"thanks":
			tw.tween_property(self, "act_lean", deg_to_rad(28), 0.32)
			tw.tween_interval(0.35)
			tw.tween_property(self, "act_lean", 0.0, 0.35)
		"whoa":
			tw.tween_property(self, "act_lean", deg_to_rad(-16), 0.1).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "act_hop", 0.3, 0.1).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "act_hop", 0.0, 0.18).set_ease(Tween.EASE_IN)
			tw.tween_interval(0.25)
			tw.tween_property(self, "act_lean", 0.0, 0.3)
		"whoops":
			act_turn = _base_yaw
			tw.tween_property(self, "act_w", 1.0, 0.05)
			for a in [0.35, -0.35, 0.22, -0.12, 0.0]:
				tw.tween_property(self, "act_turn", _base_yaw + float(a), 0.11)
			tw.tween_property(self, "act_w", 0.0, 0.1)
		"bring":
			var fwd := Vector3(0, 0, 0.22).rotated(Vector3.UP, _base_yaw)
			tw.tween_property(self, "act_lean", deg_to_rad(18), 0.16).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "act_step", fwd, 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.5)
			tw.tween_property(self, "act_lean", 0.0, 0.3)
			tw.parallel().tween_property(self, "act_step", Vector3.ZERO, 0.3)
