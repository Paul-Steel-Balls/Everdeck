extends Node3D
class_name ArenaStage

# The themed battlefield, shared by the real match board and the lab: a
# floating platform (the original round disc, or a rounded square for the
# deck themes) with the theme's floor, sky, floating props and lights, and
# the deck's set piece standing beside your Boss. Each half of the floor
# glows in its Boss's color. The theme follows your own deck.
#
# The floating props carry "spin" / "twinkle" / "bob" metadata; this node
# animates them, so whoever builds a stage gets a living backdrop.

const PLAT_HW := 10.4
const PLAT_HD := 7.4
const PLAT_N := 4.0
const DISC_R := 7.6
const HERO_Z := 4.9                 # Bosses stand at z = +/-HERO_Z
const SET_PIECE_GAP := 0.9          # Boss centre to the set piece's near side
const SET_PIECE_FOOT := 2.3         # widest a set piece may be
const SET_PIECE_TALL := 2.6         # tallest
const SET_PIECE_SIZE := 3.2         # reference size for its acting effects

var theme: String = "disc"
var env: Environment = null
var prop_holder: Node3D = null      # the set piece (null on the plain disc)

var _near_c: Color
var _far_c: Color


# Build the whole stage. near_c / far_c: the Boss colors of the near (your)
# half and the far half.
func build(theme_id: String, near_c: Color, far_c: Color) -> void:
	theme = theme_id if ArenaThemes.THEMES.has(theme_id) else "disc"
	_near_c = near_c
	_far_c = far_c
	var th: Dictionary = ArenaThemes.THEMES[theme]
	env = _environment(th)
	var disc: bool = theme == "disc"
	# The original disc stays round; the deck themes stand on a bigger
	# rounded-square platform with room for the set piece by your Boss.
	var HW: float = DISC_R if disc else PLAT_HW
	var HD: float = DISC_R if disc else PLAT_HD
	var N: float = 2.0 if disc else PLAT_N
	# Rocky underside.
	var under := _add(platform_mesh(HW + 0.15, HD + 0.15, N, 2.2, 0.55), _std(th["under"], 0.3, 0.8), Vector3.ZERO)
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor := PlaneMesh.new()
	floor.size = Vector2(HW * 2.0, HD * 2.0)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/lab/disc_floor.gdshader")
	fm.set_shader_parameter("near_col", near_c)
	fm.set_shader_parameter("far_col", far_c)
	fm.set_shader_parameter("radius", HD)
	fm.set_shader_parameter("half_w", HW)
	fm.set_shader_parameter("shape_n", N)
	fm.set_shader_parameter("pattern", th["pattern"])
	fm.set_shader_parameter("base_col", th["base"])
	var fl := _add(floor, fm, Vector3(0, 0.01, 0))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Glowing edge band, each half in its color.
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/lab/rim_band.gdshader")
	bm.set_shader_parameter("near_col", near_c.darkened(0.1))
	bm.set_shader_parameter("far_col", far_c.darkened(0.1))
	_add(band_mesh(HW, HD, N), bm, Vector3.ZERO).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if disc:
		_disc_islands()
		_lights(Color(0.9, 0.8, 1.0), 0.8)
		return
	ArenaThemes.build(self, theme)
	_set_piece(near_c)
	_lights(th["light"], 0.9)


func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	for c in get_children():
		if c.has_meta("spin"):
			(c as Node3D).rotation.y += float(c.get_meta("spin")) * delta
		if c.has_meta("twinkle"):
			(c as Node3D).visible = sin(t * 3.0 + float(c.get_meta("twinkle")) * 7.0) > -0.6
		if c.has_meta("bob"):
			(c as Node3D).position.y += sin(t * 0.8 + float(c.get_meta("bob"))) * delta * 0.3


# Where your Boss stands (theirs is mirrored).
static func hero_pos(near: bool) -> Vector3:
	return Vector3(0.0, 0.0, HERO_Z if near else -HERO_Z)


func _environment(th: Dictionary) -> Environment:
	var e := Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lab/nebula_sky.gdshader")
	sm.set_shader_parameter("deep", th["deep"])
	sm.set_shader_parameter("cloud", th["cloud"])
	sm.set_shader_parameter("accent", th["accent"])
	sm.set_shader_parameter("accent_amt", th["acc"])
	sm.set_shader_parameter("stars", th["stars"])
	var s := Sky.new()
	s.sky_material = sm
	e.sky = s
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = th["ambient"]
	e.ambient_light_energy = 0.45
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	return e


# The deck's set piece: one big, detailed 3D prop beside your Boss (the
# detonator, the stove, the lectern...), in its own materials. Sized to a
# footprint and a height cap, set a little toward the camera so it never
# stands in front of the Crew row.
func _set_piece(col: Color) -> void:
	var root: Node3D = ModelLib.instance("prop_" + theme)
	if root == null:
		return
	var box: AABB = ModelLib.bounds(root)
	var k: float = min(SET_PIECE_FOOT / max(box.size.x, box.size.z), SET_PIECE_TALL / box.size.y)
	var holder := Node3D.new()
	holder.name = "SetPiece"
	var half: float = max(box.size.x, box.size.z) * k * 0.5
	var hp: Vector3 = hero_pos(true)
	holder.position = Vector3(hp.x + SET_PIECE_GAP + half * 0.8, 0.0, hp.z + 0.45)
	holder.rotation.y = deg_to_rad(-28)  # turned a little toward the middle
	add_child(holder)
	prop_holder = holder
	root.scale = Vector3(k, k, k)
	root.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	holder.add_child(root)
	var pad := TorusMesh.new()
	pad.inner_radius = SET_PIECE_FOOT * 0.55
	pad.outer_radius = SET_PIECE_FOOT * 0.58
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = col
	_add(pad, pm, Vector3(0, 0.02, 0), holder).scale = Vector3(1, 0.3, 1)
	if theme == "larry":
		# Polished gold blows out under the lamp: dull it a little.
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m3: MeshInstance3D = mi
			for si in m3.mesh.get_surface_count():
				var src: Material = m3.get_active_material(si)
				if src is BaseMaterial3D:
					var bm2: BaseMaterial3D = src.duplicate()
					bm2.albedo_color = Color(0.72, 0.7, 0.68)
					bm2.metallic_specular = 0.25
					bm2.roughness = 0.65
					m3.set_surface_override_material(si, bm2)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, SET_PIECE_SIZE * 1.4, SET_PIECE_SIZE * 0.6)
	lamp.light_energy = 0.45 if theme == "larry" else 1.1
	lamp.omni_range = SET_PIECE_SIZE * 3.0
	holder.add_child(lamp)


func _lights(key_c: Color, key_e: float) -> void:
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-25), 0)
	key.light_energy = key_e
	key.light_color = key_c
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	key.shadow_blur = 0.8
	add_child(key)
	for z3 in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 2.5, 3.5 * z3)
		l.light_color = _near_c if z3 > 0 else _far_c
		l.light_energy = 1.2
		l.omni_range = 9.0
		add_child(l)


# The plain disc: floating rock islands with crystal clusters, and loose
# shards drifting in the air.
func _disc_islands() -> void:
	var R := DISC_R
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 16:
		var a: float = (float(i) / 16.0) * TAU + rng.randf_range(-0.15, 0.15)
		var d: float = rng.randf_range(R + 2.5, R + 7.0)
		var pos := Vector3(cos(a) * d, rng.randf_range(-2.5, 1.0), sin(a) * d - 1.5)
		if pos.z > R + 1.0:
			continue  # keep the camera's view clear
		var island := Node3D.new()
		island.position = pos
		island.set_meta("bob", rng.randf() * TAU)
		add_child(island)
		var rock := CylinderMesh.new()
		var rs: float = rng.randf_range(0.6, 1.6)
		rock.top_radius = rs
		rock.bottom_radius = 0.05
		rock.height = rs * 1.6
		rock.radial_segments = 7
		var rk := _add(rock, _std(Color(0.12, 0.08, 0.16), 0.2, 0.85), Vector3(0, -rs * 0.8, 0), island)
		rk.rotation.y = rng.randf() * TAU
		var tint: Color = [Color(0.75, 0.45, 1.0), Color(0.45, 0.65, 1.0), Color(1.0, 0.5, 0.9)][rng.randi() % 3]
		for c in rng.randi_range(2, 5):
			var cr := CylinderMesh.new()
			var h: float = rng.randf_range(0.6, 2.4) * (rs / 1.2)
			cr.top_radius = 0.0
			cr.bottom_radius = rng.randf_range(0.12, 0.3)
			cr.height = h
			cr.radial_segments = 6
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(tint.r, tint.g, tint.b, 0.75)
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.emission_enabled = true
			cm.emission = tint
			cm.emission_energy_multiplier = 1.6
			cm.metallic = 0.3
			cm.roughness = 0.1
			var cx := _add(cr, cm, Vector3(rng.randf_range(-rs, rs) * 0.5, h * 0.5, rng.randf_range(-rs, rs) * 0.5), island)
			cx.rotation = Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
	for j in 24:
		var sh := CylinderMesh.new()
		sh.top_radius = 0.0
		sh.bottom_radius = 0.08
		sh.height = rng.randf_range(0.3, 0.8)
		sh.radial_segments = 4
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(0.7, 0.55, 1.0, 0.8)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var aa: float = rng.randf() * TAU
		var dd: float = rng.randf_range(R + 1.0, R + 9.0)
		var shard := _add(sh, sm, Vector3(cos(aa) * dd, rng.randf_range(-1.0, 4.0), sin(aa) * dd - 2.0))
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		shard.set_meta("spin", rng.randf_range(-0.6, 0.6))
		shard.set_meta("bob", rng.randf() * TAU)


# --- Mesh helpers ---

static func _std(c: Color, metal: float = 0.0, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


# Points around a superellipse (n = 2 ellipse, larger n = squarer).
static func shape_pts(hw: float, hd: float, n: float, seg: int = 160) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a: float = float(i) / seg * TAU
		var c: float = cos(a)
		var s: float = sin(a)
		pts.append(Vector2(sign(c) * pow(abs(c), 2.0 / n) * hw, sign(s) * pow(abs(s), 2.0 / n) * hd))
	return pts


# The platform's rocky underside: the outline at the top, tapering down to
# a smaller copy of itself, closed at the bottom.
static func platform_mesh(hw: float, hd: float, n: float, depth: float, taper: float) -> ArrayMesh:
	var pts := shape_pts(hw, hd, n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k: int = pts.size()
	for i in k:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % k]
		var a0 := Vector3(a.x, 0.0, a.y)
		var b0 := Vector3(b.x, 0.0, b.y)
		var a1 := Vector3(a.x * taper, -depth, a.y * taper)
		var b1 := Vector3(b.x * taper, -depth, b.y * taper)
		for v in [a0, a1, b1, a0, b1, b0]:
			st.add_vertex(v)
		for v2 in [Vector3(0, -depth, 0), b1, a1]:
			st.add_vertex(v2)
	st.generate_normals()
	return st.commit()


# Thin glowing band along the platform's edge.
static func band_mesh(hw: float, hd: float, n: float) -> ArrayMesh:
	var pts := shape_pts(hw + 0.04, hd + 0.04, n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k: int = pts.size()
	for i in k:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % k]
		var lo := -0.08
		var hi := 0.06
		var a0 := Vector3(a.x, lo, a.y)
		var b0 := Vector3(b.x, lo, b.y)
		var a1 := Vector3(a.x, hi, a.y)
		var b1 := Vector3(b.x, hi, b.y)
		for v in [a0, a1, b1, a0, b1, b0]:
			st.add_vertex(v)
	return st.commit()
