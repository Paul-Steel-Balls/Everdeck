extends RefCounted
class_name FxLab

# Effects for the Battlefield Preview: impact flashes, particle bursts,
# projectiles, summon beams and floating damage numbers.

static func _add_mat(c: Color, a: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, a)
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = UIKit.glow_texture(64)
	return m


static func burst(parent: Node, pos: Vector3, col: Color, amount: int = 40, speed: float = 3.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -4, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.16
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.25, col.lightened(0.3))
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _add_mat(Color.WHITE)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(p.queue_free)


static func flash_light(parent: Node, pos: Vector3, col: Color, energy: float = 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 3.5
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


static func impact(parent: Node, pos: Vector3, col: Color) -> void:
	burst(parent, pos, col, 50, 4.0)
	flash_light(parent, pos, col)
	# Expanding shock ring.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.26
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col.lightened(0.4)
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	mi.rotation.x = deg_to_rad(90)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(4, 4, 4), 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


static func projectile(parent: Node, from: Vector3, to: Vector3, col: Color, dur: float = 0.45) -> void:
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	var mi := MeshInstance3D.new()
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.5)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = from
	# Trail particles that follow the bolt.
	var trail := GPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.35
	var pm := ParticleProcessMaterial.new()
	pm.spread = 20.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.1
	pm.scale_max = 0.22
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.4))
	g.set_color(1, Color(col.r, col.g, col.b, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	trail.process_material = pm
	var q := QuadMesh.new()
	q.material = _add_mat(Color.WHITE)
	trail.draw_pass_1 = q
	trail.local_coords = false
	mi.add_child(trail)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.5
	l.omni_range = 2.0
	mi.add_child(l)
	var mid: Vector3 = (from + to) * 0.5 + Vector3(0, 1.2, 0)
	var tw := mi.create_tween()
	tw.tween_method(func(t: float) -> void:
		var a: Vector3 = from.lerp(mid, t)
		var b: Vector3 = mid.lerp(to, t)
		mi.global_position = a.lerp(b, t), 0.0, 1.0, dur)
	await tw.finished
	impact(parent, to, col)
	trail.emitting = false
	mi.mesh = null
	parent.get_tree().create_timer(0.5).timeout.connect(mi.queue_free)


static func beam(parent: Node, pos: Vector3, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 6.0
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 3.0, 0)
	mi.scale = Vector3(0.05, 1, 0.05)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), 0.15)
	tw.tween_property(mi, "scale", Vector3(0.02, 1, 0.02), 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	flash_light(parent, pos + Vector3(0, 0.5, 0), col, 4.0)


static func damage_number(parent: Node, pos: Vector3, amount: int) -> void:
	var l := Label3D.new()
	l.text = "-%d" % amount
	l.font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	l.font_size = 96
	l.pixel_size = 0.004
	l.outline_size = 24
	l.modulate = Color(1, 0.25, 0.2)
	l.outline_modulate = Color(0.05, 0.0, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)
	l.global_position = pos
	l.scale = Vector3(0.3, 0.3, 0.3)
	var tw := l.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.2)
	tw.parallel().tween_property(l, "position:y", pos.y + 0.6, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


static func _cube_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _cube_ramp(col: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.15, col.lightened(0.45))
	g.add_point(0.7, Color(col.r, col.g, col.b, 0.8))
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _points_texture(pts: PackedVector3Array, origin: Vector3) -> ImageTexture:
	var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		var p: Vector3 = pts[i] - origin
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	return ImageTexture.create_from_image(img)


# Death: cubes peel off the unit's surface, drift up and outward, spin,
# shrink and blink out.
static func cubes_scatter(parent: Node, pts: PackedVector3Array, col: Color) -> void:
	if pts.is_empty():
		return
	var origin: Vector3 = Vector3.ZERO
	for p in pts:
		origin += p
	origin /= float(pts.size())
	var ps := GPUParticles3D.new()
	ps.amount = pts.size()
	ps.lifetime = 1.4
	ps.one_shot = true
	ps.explosiveness = 0.55
	ps.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_texture(pts, origin)
	pm.emission_point_count = pts.size()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(0.6, 0.8))
	sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _cube_ramp(col)
	ps.process_material = pm
	var b := BoxMesh.new()
	b.size = Vector3(0.1, 0.1, 0.1)
	b.material = _cube_mat()
	ps.draw_pass_1 = b
	parent.add_child(ps)
	ps.global_position = origin
	ps.emitting = true
	flash_light(parent, origin, col, 3.0)
	parent.get_tree().create_timer(2.2).timeout.connect(ps.queue_free)


# Summon: loose cubes fall inward onto the unit's shape and vanish as the
# layers build.
static func cubes_converge(parent: Node, pts: PackedVector3Array, col: Color, dur: float) -> void:
	var min_y: float = 1e9
	for p in pts:
		min_y = min(min_y, p.y)
	for i in pts.size():
		var target: Vector3 = pts[i]
		var c := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 0.07)
		c.mesh = b
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col.lightened(0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		c.material_override = m
		parent.add_child(c)
		var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.4, 1.8), randf_range(-1.2, 1.2))
		c.global_position = target + off
		c.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		var delay: float = clamp((target.y - min_y) / 2.0, 0.0, 1.0) * dur * 0.8 + randf() * 0.1
		var tw := c.create_tween()
		tw.tween_interval(delay * 0.5)
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "global_position", target, dur * 0.6)
		tw.tween_property(c, "rotation", Vector3.ZERO, dur * 0.6)
		tw.chain().tween_property(m, "albedo_color:a", 0.0, 0.12)
		tw.chain().tween_callback(c.queue_free)


# A quick ring of light expanding across the pad.
static func pad_pulse(parent: Node, pos: Vector3, col: Color) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.3
	ring.outer_radius = 0.36
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col.lightened(0.3)
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.03, 0)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.6, 1, 2.6), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(mi.queue_free)


# --- Crisp effects (sharp, readable; no soft glow blobs) ---

static func _streak_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Real sparks: thin bright streaks that fly out along their velocity, arc
# down under gravity and wink out. `up` biases them upward (a fountain).
static func sparks(parent: Node, pos: Vector3, col: Color, amount: int = 40, speed: float = 5.0, up: float = 0.5) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.9
	p.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0 * (1.0 - up) + 25.0
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.add_point(0.3, col.lightened(0.25))
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g * 0.6, col.b * 0.4, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.4)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/lab/spark.gdshader")
	q.material = sm
	p.draw_pass_1 = q
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# A small hard flash: a 4-point star that pops and shrinks (a glint).
static func glint(parent: Node, pos: Vector3, col: Color, size: float = 0.6) -> void:
	for k in 2:
		var q := QuadMesh.new()
		q.size = Vector2(size * 0.08, size) if k == 0 else Vector2(size, size * 0.08)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := _streak_mat(col.lightened(0.6))
		m.vertex_color_use_as_albedo = false
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mi.material_override = m
		parent.add_child(mi)
		mi.global_position = pos
		mi.scale = Vector3(0.2, 0.2, 0.2)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE, 0.07)
		tw.tween_property(mi, "scale", Vector3(0.05, 0.05, 0.05), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


# A crisp shockwave: a thin bright ring that races out flat and fades.
static func shock_ring(parent: Node, pos: Vector3, col: Color, radius: float = 1.4) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.0
	ring.rings = 48
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	var m := _streak_mat(col.lightened(0.4))
	m.vertex_color_use_as_albedo = false
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.15, 0.15, 0.15)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.3, radius), 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(mi.queue_free)


# A slash arc: a thin bright crescent swept across the hit point.
static func slash(parent: Node, pos: Vector3, col: Color, facing: float = 0.0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 18
	for i in seg:
		var a0: float = lerp(-1.1, 1.1, float(i) / seg)
		var a1: float = lerp(-1.1, 1.1, float(i + 1) / seg)
		var w0: float = sin(float(i) / seg * PI) * 0.1
		var w1: float = sin(float(i + 1) / seg * PI) * 0.1
		var r := 0.75
		var p0 := Vector3(sin(a0) * r, cos(a0) * r * 0.6, 0)
		var p1 := Vector3(sin(a1) * r, cos(a1) * r * 0.6, 0)
		var q0 := Vector3(sin(a0) * (r - w0), cos(a0) * (r - w0) * 0.6, 0)
		var q1 := Vector3(sin(a1) * (r - w1), cos(a1) * (r - w1) * 0.6, 0)
		for v in [p0, q0, p1, p1, q0, q1]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _streak_mat(col.lightened(0.7))
	m.vertex_color_use_as_albedo = false
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(0, facing, deg_to_rad(-35))
	mi.scale = Vector3(0.6, 0.6, 0.6)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.25, 1.25, 1.25), 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:z", deg_to_rad(25), 0.16)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.22).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)


# Steam wisps: a few thin, slow, rising strands.
static func wisps(parent: Node, pos: Vector3, amount: int = 10) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.25, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.7)
	var m := _add_mat(Color.WHITE)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	q.material = m
	p.draw_pass_1 = q
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(2.5).timeout.connect(p.queue_free)
