extends RefCounted
class_name ArenaThemes

# Themed versions of the floating disc, one per deck. Each theme sets the
# sky, the floor pattern and the floating props around the disc; the two
# halves of the floor always glow in the two heroes' colors.

const R := 7.6
const HW := 10.4   # platform half-width / half-depth / squareness (HoloLab.PLAT_*)
const HD := 7.4
const N := 4.0

# theme id -> sky colors, floor pattern / base, light tint
const THEMES: Dictionary = {
	"disc": {"name": "FLOATING DISC", "deep": Color(0.02, 0.0, 0.05), "cloud": Color(0.35, 0.08, 0.55), "accent": Color(0.9, 0.3, 0.1), "acc": 0.4, "stars": 1.0, "pattern": 0, "base": Color(0.025, 0.012, 0.05), "under": Color(0.10, 0.07, 0.14), "light": Color(0.9, 0.8, 1.0), "ambient": Color(0.6, 0.45, 0.9)},
	"grunk": {"name": "BLAST QUARRY", "deep": Color(0.05, 0.015, 0.0), "cloud": Color(0.45, 0.16, 0.03), "accent": Color(1.0, 0.55, 0.1), "acc": 0.6, "stars": 0.3, "pattern": 1, "base": Color(0.05, 0.03, 0.02), "under": Color(0.22, 0.13, 0.07), "light": Color(1.0, 0.78, 0.55), "ambient": Color(1.0, 0.6, 0.35)},
	"agatha": {"name": "GRANDMA'S KITCHEN", "deep": Color(0.12, 0.05, 0.06), "cloud": Color(0.7, 0.42, 0.38), "accent": Color(1.0, 0.85, 0.55), "acc": 0.5, "stars": 0.25, "pattern": 2, "base": Color(0.07, 0.04, 0.04), "under": Color(0.45, 0.3, 0.2), "light": Color(1.0, 0.9, 0.75), "ambient": Color(1.0, 0.78, 0.65)},
	"presto": {"name": "ARCANE LIBRARY", "deep": Color(0.01, 0.01, 0.06), "cloud": Color(0.18, 0.1, 0.5), "accent": Color(0.4, 0.8, 1.0), "acc": 0.45, "stars": 1.4, "pattern": 3, "base": Color(0.02, 0.015, 0.06), "under": Color(0.12, 0.08, 0.2), "light": Color(0.8, 0.8, 1.0), "ambient": Color(0.55, 0.5, 1.0)},
	"barnacle": {"name": "HIGH SEAS", "deep": Color(0.0, 0.03, 0.05), "cloud": Color(0.05, 0.28, 0.35), "accent": Color(0.75, 0.95, 1.0), "acc": 0.35, "stars": 0.6, "pattern": 4, "base": Color(0.06, 0.035, 0.02), "under": Color(0.25, 0.16, 0.09), "light": Color(0.85, 0.95, 1.0), "ambient": Color(0.5, 0.8, 0.9)},
	"reginald": {"name": "CASTLE KEEP", "deep": Color(0.03, 0.04, 0.1), "cloud": Color(0.55, 0.42, 0.25), "accent": Color(1.0, 0.85, 0.5), "acc": 0.55, "stars": 0.4, "pattern": 5, "base": Color(0.045, 0.045, 0.06), "under": Color(0.3, 0.29, 0.32), "light": Color(1.0, 0.92, 0.75), "ambient": Color(0.75, 0.75, 0.95)},
	"larry": {"name": "CASINO ROYALE", "deep": Color(0.03, 0.0, 0.04), "cloud": Color(0.42, 0.04, 0.3), "accent": Color(1.0, 0.8, 0.2), "acc": 0.55, "stars": 1.6, "pattern": 6, "base": Color(0.01, 0.05, 0.025), "under": Color(0.15, 0.06, 0.12), "light": Color(1.0, 0.85, 0.9), "ambient": Color(0.9, 0.55, 0.85)},
}

static var _root: Node3D
static var _rng := RandomNumberGenerator.new()


static func build(root: Node3D, theme: String) -> void:
	_root = root
	_rng.seed = hash(theme)
	match theme:
		"grunk":
			_quarry()
		"agatha":
			_kitchen()
		"presto":
			_library()
		"barnacle":
			_seas()
		"reginald":
			_castle()
		"larry":
			_casino()


# --- helpers ---

static func _mat(c: Color, metal: float = 0.0, rough: float = 0.6, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


static func _glow(c: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _mi(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(rt: float, rb: float, h: float, seg: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _torus(ri: float, ro: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	return t


# A floating group around the disc (kept out of the camera's view line).
static func _edge(a: float) -> float:
	# Distance from the centre to the platform's edge in direction a.
	var c: float = abs(cos(a))
	var s: float = abs(sin(a))
	return 1.0 / pow(pow(c / HW, N) + pow(s / HD, N), 1.0 / N)


static func _float_spots(n: int, near: float, far: float, ylo: float, yhi: float) -> Array:
	var out: Array = []
	for i in n:
		var a: float = (float(i) / n) * TAU + _rng.randf_range(-0.2, 0.2)
		var d: float = _edge(a) + _rng.randf_range(near, far)
		var p := Vector3(cos(a) * d, _rng.randf_range(ylo, yhi), sin(a) * d)
		if p.z > HD + 0.5:
			continue  # keep the camera's view clear
		out.append(p)
	return out


static func _holder(p: Vector3, spin: float = 0.0) -> Node3D:
	var h := Node3D.new()
	h.position = p
	h.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
	h.set_meta("bob", _rng.randf() * TAU)
	if spin != 0.0:
		h.set_meta("spin", spin)
	_root.add_child(h)
	return h


static func _rock(parent: Node3D, size: float, col: Color) -> void:
	var r := _cyl(size, 0.05, size * 1.6, 7)
	var m := _mi(r, _mat(col, 0.1, 0.9), Vector3(0, -size * 0.8, 0), parent)
	m.rotation.y = _rng.randf() * TAU


static func _embers(n: int, col: Color, ylo: float, yhi: float) -> void:
	for i in n:
		var a: float = _rng.randf() * TAU
		var d: float = _edge(a) + _rng.randf_range(0.5, 8.0)
		var e := _mi(_sphere(_rng.randf_range(0.03, 0.07)), _glow(col), Vector3(cos(a) * d, _rng.randf_range(ylo, yhi), sin(a) * d - 1.0), _root)
		e.set_meta("bob", _rng.randf() * TAU)
		e.set_meta("twinkle", _rng.randf())


# --- Grunk: Blast Quarry. Rock islands piled with TNT crates and powder
# kegs, embers in a smoky orange dusk. ---
static func _quarry() -> void:
	for p in _float_spots(20, 1.3, 5.5, -2.0, 1.2):
		var h := _holder(p)
		var s: float = _rng.randf_range(0.7, 1.6)
		_rock(h, s, Color(0.3, 0.18, 0.1))
		for k in _rng.randi_range(1, 3):
			var o := Vector3(_rng.randf_range(-s, s) * 0.4, 0.0, _rng.randf_range(-s, s) * 0.4)
			if _rng.randf() < 0.55:
				var crate := _mi(_box(Vector3(0.55, 0.45, 0.45)), _mat(Color(0.75, 0.12, 0.08), 0.0, 0.7), o + Vector3(0, 0.22, 0), h)
				_mi(_box(Vector3(0.57, 0.1, 0.47)), _mat(Color(0.95, 0.85, 0.6)), Vector3(0, 0.0, 0), crate)
				crate.rotation.y = _rng.randf() * TAU
			else:
				var keg := _mi(_cyl(0.22, 0.22, 0.55, 12), _mat(Color(0.35, 0.2, 0.1), 0.0, 0.8), o + Vector3(0, 0.28, 0), h)
				for yy in [-0.17, 0.17]:
					_mi(_cyl(0.235, 0.235, 0.05, 12), _mat(Color(0.25, 0.25, 0.28), 0.8, 0.4), Vector3(0, yy, 0), keg)
				# A lit fuse spark on top.
				var spark := _mi(_sphere(0.06), _glow(Color(1.0, 0.8, 0.3)), Vector3(0, 0.34, 0), keg)
				spark.set_meta("twinkle", _rng.randf())
	_embers(70, Color(1.0, 0.55, 0.15), -1.0, 5.0)


# --- Agatha: Grandma's Kitchen. Teacups and saucers, rolling pins,
# cookies and a soup pot drift in a warm rosy sky. ---
static func _kitchen() -> void:
	var cups: Array = [Color(0.95, 0.75, 0.8), Color(0.75, 0.85, 1.0), Color(1.0, 0.95, 0.85), Color(0.8, 0.95, 0.8)]
	for p in _float_spots(22, 1.2, 5.5, -1.2, 2.5):
		var h := _holder(p, _rng.randf_range(-0.25, 0.25))
		var kind: float = _rng.randf()
		var sc: float = _rng.randf_range(0.8, 1.5)
		h.scale = Vector3(sc, sc, sc)
		if kind < 0.35:
			var c: Color = cups[_rng.randi() % cups.size()]
			_mi(_cyl(0.5, 0.35, 0.6), _mat(c, 0.0, 0.3), Vector3(0, 0.3, 0), h)
			_mi(_cyl(0.46, 0.46, 0.02), _mat(Color(0.45, 0.25, 0.12)), Vector3(0, 0.55, 0), h)  # tea
			var handle := _mi(_torus(0.12, 0.2), _mat(c, 0.0, 0.3), Vector3(0.52, 0.32, 0), h)
			handle.rotation.x = PI / 2
			_mi(_cyl(0.8, 0.7, 0.06), _mat(c, 0.0, 0.3), Vector3(0, 0.0, 0), h)  # saucer
		elif kind < 0.55:
			var pin := _mi(_cyl(0.18, 0.18, 1.4, 16), _mat(Color(0.85, 0.65, 0.4), 0.0, 0.6), Vector3.ZERO, h)
			pin.rotation.z = PI / 2
			for sx in [-1.0, 1.0]:
				_mi(_cyl(0.07, 0.07, 0.45, 10), _mat(Color(0.7, 0.45, 0.25)), Vector3(0, sx * 0.9, 0), pin)
		elif kind < 0.85:
			var ck := _mi(_cyl(0.45, 0.45, 0.1, 20), _mat(Color(0.85, 0.6, 0.3), 0.0, 0.9), Vector3.ZERO, h)
			for k in 5:
				_mi(_sphere(0.06), _mat(Color(0.25, 0.12, 0.05)), Vector3(_rng.randf_range(-0.3, 0.3), 0.05, _rng.randf_range(-0.3, 0.3)), ck)
		else:
			_mi(_cyl(0.7, 0.6, 0.8), _mat(Color(0.2, 0.25, 0.5), 0.5, 0.35), Vector3(0, 0.4, 0), h)
			_mi(_cyl(0.72, 0.72, 0.06), _mat(Color(0.8, 0.7, 0.4), 0.8, 0.3), Vector3(0, 0.82, 0), h)
			var steam := _mi(_sphere(0.35), _glow(Color(1.0, 1.0, 1.0), 0.12), Vector3(0, 1.2, 0), h)
			steam.scale = Vector3(1.0, 1.6, 1.0)
	_embers(30, Color(1.0, 0.95, 0.8), 0.0, 5.0)


# --- Presto: Arcane Library. Floating books (some open), candles and
# glowing rune rings among the stars. ---
static func _library() -> void:
	var covers: Array = [Color(0.45, 0.1, 0.15), Color(0.1, 0.2, 0.45), Color(0.15, 0.35, 0.2), Color(0.4, 0.25, 0.55)]
	for p in _float_spots(24, 1.2, 5.5, -1.2, 3.0):
		var h := _holder(p, _rng.randf_range(-0.2, 0.2))
		var kind: float = _rng.randf()
		if kind < 0.6:
			var n: int = _rng.randi_range(1, 4)
			for k in n:
				var c: Color = covers[_rng.randi() % covers.size()]
				var bk := _mi(_box(Vector3(0.9, 0.18, 0.65)), _mat(c, 0.0, 0.7), Vector3(0, k * 0.19, 0), h)
				bk.rotation.y = _rng.randf_range(-0.4, 0.4)
				_mi(_box(Vector3(0.84, 0.14, 0.6)), _mat(Color(0.95, 0.9, 0.75)), Vector3(0.03, 0, 0), bk)
		elif kind < 0.8:
			_mi(_cyl(0.09, 0.09, 0.6, 10), _mat(Color(0.95, 0.92, 0.8)), Vector3(0, 0.3, 0), h)
			var fl := _mi(_sphere(0.08), _glow(Color(1.0, 0.75, 0.3)), Vector3(0, 0.68, 0), h)
			fl.scale = Vector3(1, 1.8, 1)
			fl.set_meta("twinkle", _rng.randf())
			var halo := _mi(_sphere(0.3), _glow(Color(1.0, 0.7, 0.3), 0.15), Vector3(0, 0.68, 0), h)
			halo.scale = Vector3(1, 1.3, 1)
		else:
			var ring := _mi(_torus(0.9, 1.0), _glow(Color(0.5, 0.8, 1.0)), Vector3.ZERO, h)
			ring.rotation.x = _rng.randf_range(0.6, 1.4)
			h.set_meta("spin", _rng.randf_range(0.3, 0.8))
	_embers(40, Color(0.6, 0.85, 1.0), -1.0, 6.0)


# --- Barnacle: High Seas. The disc floats over a dark ocean; barrels,
# crates and a broken mast with a torn sail bob on the swell. ---
static func _seas() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(120, 120)
	sea.subdivide_width = 80
	sea.subdivide_depth = 80
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lab/sea.gdshader")
	_mi(sea, sm, Vector3(0, -2.4, 0), _root)
	for p in _float_spots(20, 1.0, 6.0, -2.0, -1.4):
		var h := _holder(p)
		h.rotation.x = _rng.randf_range(-0.2, 0.2)
		var kind: float = _rng.randf()
		if kind < 0.45:
			var b := _mi(_cyl(0.32, 0.32, 0.8, 14), _mat(Color(0.4, 0.25, 0.12), 0.0, 0.8), Vector3.ZERO, h)
			b.rotation.z = PI / 2 if _rng.randf() < 0.5 else 0.0
			for yy in [-0.26, 0.26]:
				_mi(_cyl(0.335, 0.335, 0.06, 14), _mat(Color(0.2, 0.2, 0.22), 0.8, 0.4), Vector3(0, yy, 0), b)
		elif kind < 0.8:
			_mi(_box(Vector3(0.8, 0.8, 0.8)), _mat(Color(0.5, 0.35, 0.18), 0.0, 0.85), Vector3.ZERO, h)
		else:
			var mast := _mi(_cyl(0.1, 0.12, 4.0, 10), _mat(Color(0.35, 0.22, 0.12)), Vector3(0, 1.6, 0), h)
			mast.rotation.z = _rng.randf_range(0.3, 0.7)
			var sail := QuadMesh.new()
			sail.size = Vector2(1.8, 1.6)
			var sail_m := _mat(Color(0.85, 0.8, 0.68), 0.0, 0.9)
			sail_m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mi(sail, sail_m, Vector3(0.95, 0.6, 0), mast)
	_embers(25, Color(0.8, 0.95, 1.0), -2.0, 4.0)


# --- Reginald: Castle Keep. Floating stone towers with banners on poles
# and shields, in a golden dawn. ---
static func _castle() -> void:
	var banners: Array = [Color(0.2, 0.35, 0.85), Color(0.75, 0.15, 0.2), Color(0.9, 0.75, 0.25)]
	for p in _float_spots(16, 1.5, 5.5, -1.8, 0.4):
		var h := _holder(p)
		h.rotation.x = 0.0
		h.rotation.z = 0.0
		var s: float = _rng.randf_range(0.8, 1.4)
		_rock(h, s, Color(0.28, 0.27, 0.3))
		var th: float = _rng.randf_range(1.2, 2.6) * s
		_mi(_cyl(0.45 * s, 0.5 * s, th, 12), _mat(Color(0.55, 0.53, 0.58), 0.0, 0.85), Vector3(0, th * 0.5, 0), h)
		for k in 6:
			var a: float = k * TAU / 6.0
			_mi(_box(Vector3(0.18, 0.25, 0.18) * s), _mat(Color(0.55, 0.53, 0.58), 0.0, 0.85), Vector3(cos(a) * 0.42 * s, th + 0.12 * s, sin(a) * 0.42 * s), h)
		_mi(_cyl(0.03, 0.03, 1.2 * s, 6), _mat(Color(0.3, 0.25, 0.2)), Vector3(0, th + 0.6 * s, 0), h)
		var flag := QuadMesh.new()
		flag.size = Vector2(0.7, 0.45) * s
		var fm := _mat(banners[_rng.randi() % banners.size()], 0.0, 0.8, 0.4)
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi(flag, fm, Vector3(0.36 * s, th + 0.95 * s, 0), h)
	for p2 in _float_spots(6, 1.5, 4.0, 0.5, 2.5):
		var sh := _holder(p2, 0.3)
		var shield := _mi(_cyl(0.4, 0.4, 0.06, 20), _mat(banners[_rng.randi() % banners.size()], 0.4, 0.4), Vector3.ZERO, sh)
		shield.rotation.x = PI / 2
		_mi(_torus(0.36, 0.42), _mat(Color(0.85, 0.75, 0.4), 0.9, 0.3), Vector3.ZERO, sh).rotation.x = PI / 2
	_embers(30, Color(1.0, 0.9, 0.6), 0.0, 6.0)


# --- Larry: Casino Royale. Giant dice, stacks of chips and playing cards
# tumble through a neon night. ---
static func _casino() -> void:
	var chips: Array = [Color(0.85, 0.1, 0.15), Color(0.1, 0.2, 0.8), Color(0.1, 0.6, 0.25), Color(0.1, 0.1, 0.1), Color(0.9, 0.75, 0.2)]
	for p in _float_spots(24, 1.2, 5.5, -1.2, 3.0):
		var h := _holder(p, _rng.randf_range(-0.5, 0.5))
		var kind: float = _rng.randf()
		if kind < 0.35:
			var d := _mi(_box(Vector3(0.9, 0.9, 0.9)), _mat(Color(0.95, 0.95, 0.92), 0.0, 0.3), Vector3.ZERO, h)
			# Pips on three faces.
			var pip := _sphere(0.08)
			var pm := _mat(Color(0.1, 0.1, 0.1))
			_mi(pip, pm, Vector3(0, 0.45, 0), d)
			for o in [Vector2(-0.22, -0.22), Vector2(0.22, 0.22)]:
				_mi(pip, pm, Vector3(o.x, o.y, 0.45), d)
			for o2 in [Vector2(-0.22, -0.22), Vector2(0, 0), Vector2(0.22, 0.22)]:
				_mi(pip, pm, Vector3(0.45, o2.x, o2.y), d)
			h.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		elif kind < 0.7:
			var n: int = _rng.randi_range(2, 6)
			var c: Color = chips[_rng.randi() % chips.size()]
			for k in n:
				var chip := _mi(_cyl(0.4, 0.4, 0.1, 24), _mat(c, 0.1, 0.4), Vector3(_rng.randf_range(-0.03, 0.03), k * 0.105, 0), h)
				_mi(_torus(0.28, 0.34), _mat(Color(0.95, 0.95, 0.9)), Vector3(0, 0.0, 0), chip).scale = Vector3(1, 0.3, 1)
		else:
			var card := _mi(_box(Vector3(0.7, 1.0, 0.02)), _mat(Color(0.97, 0.97, 0.95), 0.0, 0.5), Vector3.ZERO, h)
			var suit: Color = Color(0.85, 0.1, 0.15) if _rng.randf() < 0.5 else Color(0.1, 0.1, 0.1)
			_mi(_sphere(0.12), _mat(suit), Vector3(0, 0, 0.02), card).scale = Vector3(1, 1, 0.2)
			h.rotation = Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf() * TAU, _rng.randf_range(-0.6, 0.6))
	_embers(60, Color(1.0, 0.85, 0.3), -1.0, 6.0)
