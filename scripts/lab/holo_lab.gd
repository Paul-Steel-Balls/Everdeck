extends Control
class_name HoloLab

# Battlefield Preview: flip between three arenas and three minion looks,
# and fire the actions (summon, melee, ranged, spell, shield, death) to
# judge them in motion before the full build.

signal back_pressed

const ARENAS: Array = ["HOLO COLOSSEUM", "FLOATING DISC", "TAVERN DIORAMA", "BLAST QUARRY", "GRANDMA'S KITCHEN", "ARCANE LIBRARY", "HIGH SEAS", "CASTLE KEEP", "CASINO ROYALE"]
const ARENA_PILLS: Array = ["COLOSSEUM", "DISC", "TAVERN", "QUARRY", "KITCHEN", "LIBRARY", "HIGH SEAS", "CASTLE", "CASINO"]
# Floating-disc themes (index in ARENAS -> ArenaThemes id), one per deck.
const DISC_THEMES: Dictionary = {1: "disc", 3: "grunk", 4: "agatha", 5: "presto", 6: "barnacle", 7: "reginald", 8: "larry"}
# Demo heroes: each side glows in its hero's class color.
# Demo heroes. On a deck-themed arena, your hero is that deck's hero (the
# arena follows your deck); the opponent is a different hero.
var MY_HERO := "grunk"
var THEIR_HERO := "barnacle"
const STYLES: Array = ["HOLO CARDS", "HOLO FIGURES", "HOLO BUSTS", "3D MODELS"]

# Demo lineup: [card_id, body type for the FIGURE look]
# A full board: 7 minions a side (the game's maximum).
const MINE: Array = [["grunk_scout", "goblin"], ["grunk_dynamite", "goblin"], ["reg_shield_knight", "knight"], ["presto_familiar", "beast"], ["knight", "knight"], ["guard_dog", "beast"], ["grunk_imp", "goblin"]]
const THEIRS: Array = [["wolf", "beast"], ["agatha_golem", "golem"], ["barnacle_aye", "beast"], ["neutral_sandwich", "golem"], ["agatha_bouncer", "knight"], ["barnacle_sailor", "knight"], ["lar_dice_golem", "golem"]]
const CAM_POS := Vector3(0, 10.8, 9.4)
# Themed platforms: a rounded square, bigger than the original disc.
const CAM_LOOK := Vector3(0, 0.0, 0.35)

var arena: int = 1
var style: int = 3
var _world: Node3D
var _arena_root: Node3D
var _units_root: Node3D
var _cam: Camera3D
var _env: WorldEnvironment
var _mine: Array = []
var _theirs: Array = []
var _heroes: Array = []
var _hero_units: Array = []   # HoloUnit per hero (3D model heroes), mine first
var _prop_holder: Node3D = null
var _theme: String = ""
var _busy: bool = false
var _btns: Dictionary = {}
var _caption: Label
var buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "LabWorld"
	add_child(_world)
	_cam = Camera3D.new()
	_cam.fov = 47.0
	_cam.position = CAM_POS
	_world.add_child(_cam)
	_cam.look_at_from_position(_cam.position, CAM_LOOK)
	_cam.current = true
	_env = WorldEnvironment.new()
	_world.add_child(_env)
	_build_ui()
	_rebuild()


func _process(delta: float) -> void:
	# A slow drift of the camera keeps the scene alive.
	var t: float = Time.get_ticks_msec() / 1000.0
	var disc: bool = DISC_THEMES.has(arena)
	var cp: Vector3 = CAM_POS
	var cl: Vector3 = CAM_LOOK
	if arena == 1:
		cp = Vector3(0, 11.6, 11.8)
		cl = Vector3(0, -0.4, 0.6)
	elif disc:
		# The bigger themed platform: pull back to fit it, set piece included.
		cp = Vector3(0, 13.4, 13.6)
		cl = Vector3(0, -0.6, 0.9)
	# The camera holds still during battle.
	_cam.position = cp
	_cam.look_at(cl)
	if _arena_root != null and not (_arena_root is ArenaStage):
		for c in _arena_root.get_children():
			if c.has_meta("spin"):
				c.rotation.y += float(c.get_meta("spin")) * delta
			if c.has_meta("twinkle"):
				var mm: MeshInstance3D = c
				mm.visible = sin(t * 3.0 + float(c.get_meta("twinkle")) * 7.0) > -0.6
			if c.has_meta("bob"):
				c.position.y += sin(t * 0.8 + float(c.get_meta("bob"))) * delta * 0.3


# --- Scene building ---

func _rebuild() -> void:
	if _arena_root != null:
		_arena_root.queue_free()
	if _units_root != null:
		_units_root.queue_free()
	var th_id: String = DISC_THEMES.get(arena, "disc")
	MY_HERO = th_id if UIKit.CLASS_COLOR.has(th_id) else "grunk"
	THEIR_HERO = "barnacle" if MY_HERO != "barnacle" else "grunk"
	_arena_root = Node3D.new()
	_world.add_child(_arena_root)
	_prop_holder = null
	_theme = ""
	_units_root = Node3D.new()
	_world.add_child(_units_root)
	match arena:
		0:
			_arena_table()
		2:
			_arena_tavern()
		_:
			_arena_sky(DISC_THEMES.get(arena, "disc"))
	_mine.clear()
	_theirs.clear()
	_heroes.clear()
	_hero_units.clear()
	_spawn_heroes()
	if _prop_holder != null and not _hero_units.is_empty() and _hero_units[0] != null:
		# The hero plays with the set piece now and then (more often here
		# than in a match, so it shows up while previewing).
		var act := StageAct.new()
		act.theme = _theme
		act.hero = _hero_units[0]
		act.prop = _prop_holder
		act.prop_size = ArenaStage.SET_PIECE_SIZE
		act.color = UIKit.CLASS_COLOR[MY_HERO]
		act.interval = Vector2(7.0, 11.0)
		act.first_delay = 2.0
		_units_root.add_child(act)
	for i in MINE.size():
		_mine.append(_spawn(MINE[i], 1.0, i, MINE.size()))
	for j in THEIRS.size():
		_theirs.append(_spawn(THEIRS[j], -1.0, j, THEIRS.size()))
	_refresh_buttons()
	_caption.text = "%s  +  %s" % [ARENAS[arena], STYLES[style]]


func _slot(side: float, i: int, n: int) -> Vector3:
	return Vector3((i - (n - 1) * 0.5) * 1.5, 0.0, 1.85 * side)


func _spawn(spec: Array, side: float, i: int, n: int) -> HoloUnit:
	var cid: String = spec[0]
	var cls: String = str(CardDB.get_card(cid).get("class", "neutral"))
	var col: Color = UIKit.CLASS_COLOR.get(cls, Color(1.0, 0.75, 0.35))
	var u := HoloUnit.new()
	var pad: Color = UIKit.CLASS_COLOR[MY_HERO if side > 0 else THEIR_HERO]
	u.setup(cid, spec[1], style, side, col, pad)
	u.position = _slot(side, i, n)
	u.scale = Vector3(1.22, 1.22, 1.22)
	u.home = u.position
	_units_root.add_child(u)
	return u


func _spawn_heroes() -> void:
	for spec in [[MY_HERO, 1.0], [THEIR_HERO, -1.0]]:
		var cls: String = spec[0]
		var side: float = spec[1]
		var h := Node3D.new()
		h.position = Vector3(0, 0, 4.9 * side)
		_units_root.add_child(h)
		var col: Color = UIKit.CLASS_COLOR[cls]
		if ModelLib.has_model("hero_" + cls):
			# The hero's own 3D model, a size up from the minions.
			var hu := HoloUnit.new()
			hu.setup("hero_" + cls, "model", HoloUnit.Style.MODEL, side, col, col)
			hu.scale = Vector3(1.75, 1.75, 1.75)
			hu.home = h.position
			h.add_child(hu)
			_hero_units.append(hu)
			var ring0 := TorusMesh.new()
			ring0.inner_radius = 0.85
			ring0.outer_radius = 0.95
			var rm0 := StandardMaterial3D.new()
			rm0.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm0.albedo_color = col
			_add(ring0, rm0, Vector3(0, 0.03, 0), h)
			h.set_meta("cls", cls)
			_heroes.append(h)
			continue
		var q := QuadMesh.new()
		q.size = Vector2(1.9, 1.9)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = HoloUnit.HOLO_SHADER
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("tex", UIKit.hero_texture(cls))
		var face: Vector3 = UIKit.HERO_FACE[cls]
		m.set_shader_parameter("uv_rect", Vector4(face.x - 0.42, face.y - 0.22, 0.84, 0.56))
		m.set_shader_parameter("oval_mask", 1.0)
		m.set_shader_parameter("tint", col)
		mi.material_override = m
		mi.position = Vector3(0, 1.5, 0)
		mi.rotation.x = deg_to_rad(-20 if side > 0 else -5)
		h.add_child(mi)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.75
		ring.outer_radius = 0.85
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = col
		var r := MeshInstance3D.new()
		r.mesh = ring
		r.material_override = rm
		r.position.y = 0.03
		h.add_child(r)
		h.set_meta("cls", cls)
		_heroes.append(h)


func _std(c: Color, metal: float = 0.0, rough: float = 0.6) -> StandardMaterial3D:
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
	(parent if parent != null else _arena_root).add_child(mi)
	return mi


func _environment(bg: Color, ambient: Color, ambient_e: float, glow: float, sky: bool = false) -> void:
	var e := Environment.new()
	if sky:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/lab/nebula_sky.gdshader")
		var s := Sky.new()
		s.sky_material = sm
		e.sky = s
		e.background_mode = Environment.BG_SKY
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_e
	e.glow_enabled = glow > 0.0
	e.glow_intensity = glow
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.fog_enabled = not sky
	e.fog_light_color = bg.lightened(0.15)
	e.fog_density = 0.012
	_env.environment = e


func _grid_mat(size: Vector2, base: Color = Color(0.03, 0.01, 0.07)) -> ShaderMaterial:
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/lab/grid_top.gdshader")
	gm.set_shader_parameter("size", size)
	gm.set_shader_parameter("halves", 1.0)
	gm.set_shader_parameter("base_col", base)
	return gm


func _neon(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


# A: a sci-fi stadium. Each player owns a half of the floor (blue / red),
# with stepped stands and neon all around.
func _arena_table() -> void:
	_environment(Color(0.02, 0.01, 0.05), Color(0.5, 0.35, 0.8), 0.35, 1.0)
	var W := 18.0
	var D := 13.5
	var floor := BoxMesh.new()
	floor.size = Vector3(W + 0.6, 0.4, D + 0.6)
	_add(floor, _std(Color(0.08, 0.06, 0.12), 0.8, 0.35), Vector3(0, -0.21, 0))
	var top := PlaneMesh.new()
	top.size = Vector2(W, D)
	_add(top, _grid_mat(Vector2(W, D)), Vector3(0, 0.005, 0))
	# Side lines: blue along my edge, red along theirs.
	for z in [-1.0, 1.0]:
		var strip := BoxMesh.new()
		strip.size = Vector3(W + 0.6, 0.08, 0.08)
		_add(strip, _neon(Color(0.3, 0.6, 1.0) if z > 0 else Color(1.0, 0.3, 0.35)), Vector3(0, 0.02, (D * 0.5 + 0.3) * z))
	# Stepped stands around the floor.
	for tier in 3:
		var h: float = 0.6 + tier * 0.7
		var off: float = 1.2 + tier * 1.3
		for z2 in [-1.0, 1.0]:
			var b := BoxMesh.new()
			b.size = Vector3(W + off * 2.0, h, 1.2)
			_add(b, _std(Color(0.10, 0.07, 0.15), 0.5, 0.5), Vector3(0, h * 0.5 - 0.4, (D * 0.5 + off) * z2))
			var lip := BoxMesh.new()
			lip.size = Vector3(W + off * 2.0, 0.05, 0.05)
			_add(lip, _neon(Color(0.3, 0.6, 1.0) if z2 > 0 else Color(1.0, 0.3, 0.35)), Vector3(0, h - 0.4, (D * 0.5 + off - 0.6) * z2))
		for x2 in [-1.0, 1.0]:
			var b2 := BoxMesh.new()
			b2.size = Vector3(1.2, h, D + off * 2.0)
			_add(b2, _std(Color(0.10, 0.07, 0.15), 0.5, 0.5), Vector3((W * 0.5 + off) * x2, h * 0.5 - 0.4, 0))
	# Crowd: little flickering lights in the stands.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 220:
		var dot := SphereMesh.new()
		dot.radius = 0.06
		dot.height = 0.12
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var tier2: int = rng.randi() % 3
		var pos := Vector3(rng.randf_range(-W * 0.6, W * 0.6), 0.25 + tier2 * 0.7, (D * 0.5 + 1.2 + tier2 * 1.3) * side)
		var cc: Color = [Color(0.3, 0.6, 1.0), Color(1.0, 0.35, 0.4), Color(1.0, 0.8, 0.3), Color(0.7, 0.4, 1.0)][rng.randi() % 4]
		var d := _add(dot, _neon(cc), pos)
		d.set_meta("twinkle", rng.randf() * TAU)
	# Corner pylons.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var py := CylinderMesh.new()
			py.top_radius = 0.15
			py.bottom_radius = 0.3
			py.height = 4.0
			_add(py, _std(Color(0.15, 0.12, 0.2), 0.9, 0.3), Vector3((W * 0.5 + 0.4) * cx, 1.6, (D * 0.5 + 0.4) * cz))
			var orb := SphereMesh.new()
			orb.radius = 0.32
			orb.height = 0.64
			_add(orb, _neon(Color(0.3, 0.6, 1.0) if cz > 0 else Color(1.0, 0.3, 0.35)), Vector3((W * 0.5 + 0.4) * cx, 3.7, (D * 0.5 + 0.4) * cz))
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-60), deg_to_rad(25), 0)
	key.light_energy = 0.6
	key.light_color = Color(0.8, 0.7, 1.0)
	_arena_root.add_child(key)
	for z3 in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 3.0, 3.0 * z3)
		l.light_color = Color(0.4, 0.6, 1.0) if z3 > 0 else Color(1.0, 0.4, 0.45)
		l.light_energy = 1.4
		l.omni_range = 10.0
		_arena_root.add_child(l)


# B: the floating disc (Ian's pick, from Grok's concept): a round platform
# adrift in a nebula, each half glowing in its hero's color, ringed by
# floating rocks crowned with crystals.
func _arena_sky(theme: String = "disc") -> void:
	# The shared themed stage (the real match board builds the same one).
	_arena_root.queue_free()
	var st := ArenaStage.new()
	_arena_root = st
	_world.add_child(st)
	st.build(theme, UIKit.CLASS_COLOR[MY_HERO], UIKit.CLASS_COLOR[THEIR_HERO])
	_env.environment = st.env
	if st.prop_holder != null:
		_prop_holder = st.prop_holder
		_theme = theme



# C: a big physical game board on a tavern table under warm lamps; each
# player's half has its own felt color.
func _arena_tavern() -> void:
	_environment(Color(0.06, 0.03, 0.02), Color(1.0, 0.7, 0.45), 0.35, 0.8)
	var table := BoxMesh.new()
	table.size = Vector3(30, 0.6, 22)
	_add(table, _std(Color(0.30, 0.17, 0.08), 0.0, 0.75), Vector3(0, -0.62, 0))
	for z in [-1.0, 1.0]:
		var felt := BoxMesh.new()
		felt.size = Vector3(18, 0.3, 6.7)
		_add(felt, _std(Color(0.12, 0.2, 0.38) if z > 0 else Color(0.38, 0.12, 0.14), 0.0, 0.85), Vector3(0, -0.15, 3.4 * z))
		var rail := BoxMesh.new()
		rail.size = Vector3(18.6, 0.28, 0.28)
		_add(rail, _std(Color(0.85, 0.62, 0.25), 0.9, 0.3), Vector3(0, -0.05, 6.85 * z))
	var mid := BoxMesh.new()
	mid.size = Vector3(18.6, 0.3, 0.2)
	_add(mid, _std(Color(0.85, 0.62, 0.25), 0.9, 0.3), Vector3(0, -0.05, 0))
	for x in [-1.0, 1.0]:
		var rail2 := BoxMesh.new()
		rail2.size = Vector3(0.28, 0.28, 13.9)
		_add(rail2, _std(Color(0.85, 0.62, 0.25), 0.9, 0.3), Vector3(9.3 * x, -0.05, 0))
	for side in [-1.0, 1.0]:
		for i in 7:
			var slot := BoxMesh.new()
			slot.size = Vector3(1.15, 0.02, 1.0)
			_add(slot, _neon(Color(1.0, 0.8, 0.4)), _slot(side, i, 7) + Vector3(0, 0.005, 0))
	for p in [Vector3(-6, 6, -3), Vector3(6, 6, 3)]:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color(1.0, 0.7, 0.4)
		lamp.light_energy = 2.6
		lamp.omni_range = 16.0
		lamp.shadow_enabled = true
		_arena_root.add_child(lamp)
	var mug := CylinderMesh.new()
	mug.top_radius = 0.7
	mug.bottom_radius = 0.62
	mug.height = 1.5
	_add(mug, _std(Color(0.55, 0.35, 0.2), 0.0, 0.6), Vector3(11.5, 0.45, 3.5))
	var coin := CylinderMesh.new()
	coin.top_radius = 0.5
	coin.bottom_radius = 0.5
	coin.height = 0.08
	for i in 5:
		_add(coin, _std(Color(1.0, 0.78, 0.25), 1.0, 0.25), Vector3(-11.4, -0.28 + i * 0.085, 3.0))


# --- UI ---

func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	var back := UIKit.button("BACK", UIKit.BTN_PURPLE, 16, Vector2(100, 40))
	back.pressed.connect(func() -> void: back_pressed.emit())
	top.add_child(back)
	buttons["back"] = back
	for i in ARENAS.size():
		var b := _pill(ARENA_PILLS[i], func() -> void: _set_arena(i))
		top.add_child(b)
		_btns["a%d" % i] = b
	var top2 := HBoxContainer.new()
	top2.position = Vector2(124, 58)
	top2.add_theme_constant_override("separation", 8)
	add_child(top2)
	for j in STYLES.size():
		var b2 := _pill(STYLES[j], func() -> void: _set_style(j))
		top2.add_child(b2)
		_btns["s%d" % j] = b2
	_caption = UIKit.label("", 22, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 8)
	_caption.anchor_left = 1.0
	_caption.anchor_right = 1.0
	_caption.offset_left = -520
	_caption.offset_right = -20
	_caption.offset_top = 64
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_caption)
	var bottom := HBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -66
	bottom.offset_left = 16
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)
	var acts: Array = [["SUMMON", _act_summon], ["MELEE", _act_melee], ["RANGED", _act_ranged], ["TRICK", _act_spell], ["SHIELD", _act_shield], ["DEATH", _act_death], ["FULL DEMO", _act_demo]]
	for a in acts:
		var col: Color = UIKit.BTN_GREEN if a[0] == "FULL DEMO" else UIKit.BTN_BLUE
		var ab := UIKit.button(a[0], col, 18, Vector2(150 if a[0] == "FULL DEMO" else 120, 50))
		var cb: Callable = a[1]
		ab.pressed.connect(func() -> void: _run(cb))
		bottom.add_child(ab)
		buttons[str(a[0]).to_lower()] = ab


func _pill(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_override("font", UIKit.font(UIKit.FONT_DISPLAY_PATH))
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	return b


func _refresh_buttons() -> void:
	for k in _btns:
		var on: bool = (k == "a%d" % arena) or (k == "s%d" % style)
		var b: Button = _btns[k]
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.95, 0.62, 0.08) if on else (Color(1, 1, 1, 0.18) if st.begins_with("hover") else Color(0, 0, 0, 0.55))
			sb.border_color = UIKit.INK if on else Color(1, 1, 1, 0.3)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(16)
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _set_arena(i: int) -> void:
	if _busy:
		return
	arena = i
	_rebuild()


func _set_style(j: int) -> void:
	if _busy:
		return
	style = j
	_rebuild()


# --- Actions ---

func _run(cb: Callable) -> void:
	if _busy:
		return
	_busy = true
	await cb.call()
	_busy = false


func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not u.is_queued_for_deletion():
			out.append(u)
	return out


func _act_summon() -> void:
	# Re-summon the whole lineup with beams, one by one.
	_rebuild()
	for u in _mine + _theirs:
		u.visible = false
	for u2 in _mine + _theirs:
		u2.visible = true
		u2.summon()
		await get_tree().create_timer(0.16).timeout
	await get_tree().create_timer(0.6).timeout


func _act_melee() -> void:
	var a: Array = _alive(_mine)
	var b: Array = _alive(_theirs)
	if a.size() < 2 or b.is_empty():
		_rebuild()
		return
	await a[1].melee(b[0])


func _act_ranged() -> void:
	var a: Array = _alive(_theirs)
	var b: Array = _alive(_mine)
	if a.size() < 2 or b.is_empty():
		_rebuild()
		return
	await a[1].ranged(b[0].attack_point())
	b[0].hit(2)


func _act_spell() -> void:
	# A fireball from my hero at an enemy minion.
	var b: Array = _alive(_theirs)
	if b.is_empty():
		_rebuild()
		return
	var hero: Node3D = _heroes[0]
	var tgt: HoloUnit = b[b.size() - 1]
	await FxLab.projectile(_units_root, hero.global_position + Vector3(0, 1.4, 0), tgt.attack_point(), Color(1.0, 0.45, 0.1), 0.6)
	tgt.hit(4)


func _act_shield() -> void:
	var a: Array = _alive(_mine)
	if a.size() < 2:
		return
	var u: HoloUnit = a[1]
	u.shield(u._shield == null)
	await get_tree().create_timer(0.4).timeout


func _act_death() -> void:
	var b: Array = _alive(_theirs)
	if b.is_empty():
		_rebuild()
		return
	await b[0].die()


func _act_demo() -> void:
	await _act_summon()
	await get_tree().create_timer(0.3).timeout
	await _mine[1].melee(_theirs[0])
	await get_tree().create_timer(0.3).timeout
	await _theirs[1].ranged(_mine[0].attack_point())
	_mine[0].hit(2)
	await get_tree().create_timer(0.4).timeout
	await _mine[0].melee(_theirs[2])
	await get_tree().create_timer(0.3).timeout
	await _act_spell()
	await get_tree().create_timer(0.2).timeout
	await _theirs[0].die()
	_mine[1].shield(true)
	await get_tree().create_timer(0.8).timeout
