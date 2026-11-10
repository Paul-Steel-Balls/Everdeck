extends Node3D
class_name Minion3D

# Everdeck Sprint 1a — a minion as a thick oval token on the 3D table.
# Portrait comes from the EXISTING CardArt rendered through a SubViewport
# into a ViewportTexture (256px, renders once — the art never changes).
# Attack/health gems are small 3D gems with Label3D numbers. Bouncer
# minions get a heavier stone/iron rim instead of gold. Sleeping minions
# show a floating "Zzz". Minions that can attack get an emissive green
# rim that pulses. Picking: Area3D + CylinderShape3D; the board raycasts
# the camera ray and reads the uid off this node's metadata.

const PORTRAIT_SIZE: int = 256
const BODY_RADIUS: float = 0.78
const BODY_HEIGHT: float = 0.22
const DISC_RADIUS: float = 0.66
const OVAL_Z: float = 0.8  # squash the body to an oval

var uid: int = -1
var player: int = 0
var card_id: String = ""

# Sprint 1a.4: stat numbers are 2D overlay badges (StatBadges, owned by
# main) pinned to the token's projected screen position. The 3D stat
# discs + Label3D numbers are GONE (they were too big, overlapped
# neighbors, and hid behind discs). This node keeps the live stat state
# for the badge manager, plus the director's animation entry points
# (punch/spin/flash), which forward to the 2D badges.
var cur_atk: int = 0
var cur_hp: int = 0
var base_atk: int = 0
var base_hp: int = 0
var max_hp: int = 0
var dying: bool = false  # the badge manager hides badges while dying
var badge_link: Node = null  # StatBadges, set by main via the board
# Hotfix 1c.1: the token's rest scale, set by the board (TOKEN_SCALE).
# EVERY scale tween on this node must be relative to base_scale — the
# old absolute tweens (1.08 -> 1.0) left tokens ~1.85x too big.
var base_scale: Vector3 = Vector3.ZERO

var _zzz_label: Label3D = null
var _gold_rim: MeshInstance3D = null
var _iron_rim: MeshInstance3D = null
var _guard_wall: MeshInstance3D = null  # Bouncer's glowing guard wall
var is_bouncer: bool = false
var _pulse_ring: MeshInstance3D = null
var _pulse_mat: StandardMaterial3D = null
var _target_ring: MeshInstance3D = null
var _body_mat: StandardMaterial3D = null
var _disc_mat: StandardMaterial3D = null
var _area: Area3D = null
# The Crew member's own 3D model (lite hologram), standing on its pad.
# Null for the few summoned tokens that have no model yet: those keep the
# old disc token (TOKEN_FIT scales it into the same footprint).
var unit: HoloUnit = null
var pad_color: Color = Color(0, 0, 0, 0)  # the owner's Boss color
const TOKEN_FIT: float = 0.78
# Summoned tokens that are the same creature as a Crew card with a model
# borrow that model (until the tokens get models of their own).
const TOKEN_MODELS: Dictionary = {"Parrot": "barnacle_scout", "Crow": "barnacle_storm", "Cabin Boy": "barnacle_cabin", "Casserole Dish": "agatha_dish"}
var model_id: String = ""
# Summoning sickness ("warming up"): a just-summoned hologram is still
# booting: it runs a little dim and flickery and a loading ring spins on
# its pad until it can attack. (Crew that already attacked show nothing:
# the missing green ring already says so.)
var warming: bool = false
var _warm_ring: MeshInstance3D = null
var _warm_tw: Tween = null
const MODEL_RING_R: float = 0.5  # rings around a model's feet
# Mechanics pass, wave 1: see-through shells for keyword states, built on
# first need, plus the small icons the badge layer draws (pips).
var _shells: Dictionary = {}  # "shield" / "frozen" / "stealth" -> MeshInstance3D
var pips: Array = []  # "encore", "poison", "lifesteal", "trigger", "vibe", "silenced"
const SHELL_LOOKS: Dictionary = {
	"shield": {"col": Color(1.0, 0.84, 0.3), "base_alpha": 0.07, "rim_alpha": 0.8, "frost": 0.0, "sphere": true},
	"frozen": {"col": Color(0.62, 0.88, 1.0), "base_alpha": 0.22, "rim_alpha": 0.6, "frost": 1.0, "sphere": false},
	"stealth": {"col": Color(0.42, 0.05, 0.16), "base_alpha": 0.32, "rim_alpha": 0.55, "frost": 0.0, "sphere": false},
}


func setup(minion: Dictionary, player_idx: int, pad: Color = Color(0, 0, 0, 0)) -> void:
	uid = int(minion.get("uid", -1))
	player = player_idx
	card_id = str(minion.get("card_id", ""))
	pad_color = pad
	model_id = model_for(minion)
	if model_id != "" and ModelLib.has_model(model_id):
		_build_model(minion)
	else:
		_build_body(minion)
	_build_zzz()
	_build_pick_area()
	update_stats(minion, player_idx == 0)


func _std(color: Color, metallic: float = 0.0, roughness: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _torus(inner_r: float, outer_r: float, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_r
	mesh.outer_radius = outer_r
	mesh.rings = 40
	mesh.ring_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


# Which 3D model a Crew member shows: its own card's, else (a summoned
# token) "token_<art>", else a Crew card of the same creature.
static func model_for(minion: Dictionary) -> String:
	var cid: String = str(minion.get("card_id", ""))
	if ModelLib.has_model(cid):
		return cid
	var tok: String = "token_" + str(minion.get("art", ""))
	if ModelLib.has_model(tok):
		return tok
	var alias: String = str(TOKEN_MODELS.get(str(minion.get("name", "")), ""))
	return alias if ModelLib.has_model(alias) else ""


func _build_model(minion: Dictionary) -> void:
	var card: Dictionary = CardDB.get_card(card_id)
	if card.is_empty():
		card = CardDB.get_card(model_id)
	var cls: String = str(card.get("class", "neutral"))
	var col: Color = UIKit.CLASS_COLOR.get(cls, Color(1.0, 0.75, 0.35))
	unit = HoloUnit.new()
	unit.name = "Model"
	unit.setup(model_id, "model", HoloUnit.Style.MODEL, 1.0, col, pad_color if pad_color.a > 0.0 else col)
	unit.face_enemy = true
	unit.pop = OS.get_environment("EVERDECK_NO_POP") == ""
	var ny: String = OS.get_environment("EVERDECK_NEAR_YAW")
	if ny != "":
		unit.near_yaw = deg_to_rad(float(ny))
	add_child(unit)
	unit.home = Vector3(float(uid % 7) * 1.3, 0, 0)  # de-syncs the idle loops
	var flat := Vector3(1.0, 0.25, 1.0)
	# Bouncer: a heavy iron ring with a steel glint around the feet.
	_iron_rim = _torus(MODEL_RING_R * 0.86, MODEL_RING_R * 1.12, _std(Color(0.24, 0.25, 0.3), 0.85, 0.35))
	(_iron_rim.material_override as StandardMaterial3D).emission_enabled = true
	(_iron_rim.material_override as StandardMaterial3D).emission = Color(0.55, 0.6, 0.75)
	(_iron_rim.material_override as StandardMaterial3D).emission_energy_multiplier = 0.35
	_iron_rim.scale = Vector3(1.0, 0.6, 1.0)
	_iron_rim.position.y = 0.04
	_iron_rim.visible = false
	add_child(_iron_rim)
	# Bouncer: an ice-blue hex-light guard wall around the feet, so "attack
	# this first" reads from across the table.
	var wall := CylinderMesh.new()
	wall.top_radius = MODEL_RING_R * 1.32
	wall.bottom_radius = MODEL_RING_R * 1.32
	wall.height = 0.95
	wall.cap_top = false
	wall.cap_bottom = false
	wall.radial_segments = 40
	wall.rings = 1
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://shaders/lab/bouncer_wall.gdshader")
	_guard_wall = MeshInstance3D.new()
	_guard_wall.mesh = wall
	_guard_wall.material_override = wm
	_guard_wall.position.y = 0.48
	_guard_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guard_wall.visible = false
	add_child(_guard_wall)
	# Green "can attack" ring.
	_pulse_mat = StandardMaterial3D.new()
	_pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pulse_mat.albedo_color = Color(0.3, 1.0, 0.45)
	_pulse_mat.emission_enabled = true
	_pulse_mat.emission = Color(0.1, 1.0, 0.3)
	_pulse_ring = _torus(MODEL_RING_R * 1.14, MODEL_RING_R * 1.24, _pulse_mat)
	_pulse_ring.scale = flat
	_pulse_ring.position.y = 0.05
	_pulse_ring.visible = false
	add_child(_pulse_ring)
	# Gold target highlight.
	var hl_mat := StandardMaterial3D.new()
	hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl_mat.albedo_color = Color(1.0, 0.82, 0.2)
	_target_ring = _torus(MODEL_RING_R * 1.26, MODEL_RING_R * 1.38, hl_mat)
	_target_ring.scale = flat
	_target_ring.position.y = 0.06
	_target_ring.visible = false
	add_child(_target_ring)


func _build_body(minion: Dictionary) -> void:
	# Oval shell: body + portrait disc + rims live under one node that
	# carries the oval squash, so the gems/labels stay undistorted.
	var shell := Node3D.new()
	shell.name = "Shell"
	shell.scale = Vector3(TOKEN_FIT, TOKEN_FIT, OVAL_Z * TOKEN_FIT)
	add_child(shell)

	# Thick token body (warm ivory, like a poker chip).
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = BODY_RADIUS
	body_mesh.bottom_radius = BODY_RADIUS
	body_mesh.height = BODY_HEIGHT
	body_mesh.radial_segments = 28
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	_body_mat = _std(Color(0.93, 0.89, 0.78), 0.05, 0.55)
	body.material_override = _body_mat
	body.position.y = BODY_HEIGHT / 2.0
	shell.add_child(body)

	# Portrait disc on top (existing CardArt through a SubViewport).
	var vp := SubViewport.new()
	vp.name = "PortraitVP"
	vp.size = Vector2i(PORTRAIT_SIZE, PORTRAIT_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.handle_input_locally = false
	var art := CardArt.new()
	art.art_id = str(minion.get("art", CardDB.get_card(card_id).get("art", "")))
	art.card_id = card_id
	art.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	art.position = Vector2.ZERO
	vp.add_child(art)
	add_child(vp)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = DISC_RADIUS
	disc_mesh.bottom_radius = DISC_RADIUS
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 28
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_texture = vp.get_texture()
	disc_mat.roughness = 0.7
	_disc_mat = disc_mat
	disc.material_override = disc_mat
	disc.position.y = BODY_HEIGHT + 0.005
	shell.add_child(disc)

	# Gold bevel ring (default) + heavier stone/iron rim (Bouncer).
	_gold_rim = _torus(0.72, 0.80, _std(Color(0.85, 0.65, 0.15), 0.9, 0.3))
	_gold_rim.position.y = BODY_HEIGHT - 0.02
	shell.add_child(_gold_rim)
	# Sprint 1a.2: Bouncer rim must read CLEARLY different — a THICK dark
	# iron band (wide torus), not a subtle tint.
	_iron_rim = _torus(0.58, 0.92, _std(Color(0.20, 0.20, 0.26), 0.75, 0.45))
	_iron_rim.position.y = BODY_HEIGHT - 0.02
	_iron_rim.visible = false
	shell.add_child(_iron_rim)

	# Green "can attack" pulse ring (emissive, animated in _process).
	_pulse_mat = StandardMaterial3D.new()
	_pulse_mat.albedo_color = Color(0.15, 0.9, 0.3)
	_pulse_mat.emission_enabled = true
	_pulse_mat.emission = Color(0.1, 1.0, 0.3)
	_pulse_mat.emission_energy_multiplier = 1.0
	_pulse_mat.roughness = 0.4
	_pulse_ring = _torus(0.80, 0.87, _pulse_mat)
	_pulse_ring.position.y = 0.02
	_pulse_ring.visible = false
	shell.add_child(_pulse_ring)

	# Gold target-highlight ring (drag targets).
	var hl_mat := StandardMaterial3D.new()
	hl_mat.albedo_color = Color(1.0, 0.8, 0.1)
	hl_mat.emission_enabled = true
	hl_mat.emission = Color(1.0, 0.75, 0.1)
	hl_mat.emission_energy_multiplier = 1.2
	hl_mat.roughness = 0.4
	_target_ring = _torus(0.87, 0.95, hl_mat)
	_target_ring.position.y = 0.02
	_target_ring.visible = false
	shell.add_child(_target_ring)


func _build_zzz() -> void:
	_zzz_label = Label3D.new()
	_zzz_label.billboard = 1  # Label3D.BILLBOARD_ENABLED
	_zzz_label.font_size = 34
	_zzz_label.pixel_size = 0.012
	_zzz_label.modulate = Color(0.75, 0.85, 1.0)
	_zzz_label.outline_size = 6
	_zzz_label.outline_modulate = Color(0, 0, 0, 0.85)
	_zzz_label.text = "Zzz"
	_zzz_label.position = Vector3(0, 1.95 if unit != null else 0.85, 0)
	if unit != null:
		_zzz_label.pixel_size = 0.0075
	_zzz_label.visible = false
	add_child(_zzz_label)


func _build_pick_area() -> void:
	_area = Area3D.new()
	_area.name = "PickArea"
	_area.monitoring = false
	_area.monitorable = true
	_area.set_meta("minion_3d", self)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.7 if unit != null else 0.88 * TOKEN_FIT
	cyl.height = 1.9 if unit != null else 0.7
	shape.shape = cyl
	shape.position.y = 0.9 if unit != null else 0.2
	_area.add_child(shape)
	add_child(_area)


# Refresh state / rings from the live minion dict. is_mine = belongs to
# the player whose turn it is (the viewer) — only their minions show Zzz
# and the green "can attack" pulse. The 2D stat badges read cur_atk /
# cur_hp / base_atk / base_hp / max_hp from here every frame.
func update_stats(minion: Dictionary, is_mine: bool) -> void:
	cur_atk = int(minion.get("attack", 0))
	cur_hp = int(minion.get("health", 0))
	max_hp = int(minion.get("max_health", cur_hp))
	var card: Dictionary = CardDB.get_card(str(minion.get("card_id", "")))
	base_atk = int(card.get("attack", cur_atk))
	base_hp = int(card.get("health", cur_hp))
	# A state refresh clears any transient badge flash (e.g. the heal
	# green) — the badge manager re-derives colors from state.
	if badge_link != null and badge_link.has_method("clear_flash"):
		badge_link.clear_flash(uid)
	var taunt: bool = bool(minion.get("taunt", false))
	is_bouncer = taunt
	if _gold_rim != null:
		_gold_rim.visible = not taunt
	if _iron_rim != null:
		_iron_rim.visible = taunt
	if _guard_wall != null:
		_guard_wall.visible = taunt
	if unit != null:
		unit.side = 1.0 if is_mine else -1.0
	_set_shell("shield", bool(minion.get("shield", false)))
	_set_shell("frozen", int(minion.get("frozen", 0)) > 0)
	_set_shell("stealth", bool(minion.get("stealth", false)))
	var pp: Array = []
	if bool(minion.get("windfury", false)):
		pp.append("encore")
	if bool(minion.get("poison", false)):
		pp.append("poison")
	if bool(minion.get("lifesteal", false)):
		pp.append("lifesteal")
	if bool(minion.get("silenced", false)):
		pp.append("silenced")
	else:
		if not (card.get("triggers", []) as Array).is_empty():
			pp.append("trigger")
		if not (card.get("vibe", {}) as Dictionary).is_empty():
			pp.append("vibe")
	pips = pp
	var can_attack: bool = bool(minion.get("can_attack", false)) and cur_atk > 0 and int(minion.get("frozen", 0)) == 0
	if _pulse_ring != null:
		_pulse_ring.visible = is_mine and can_attack
	var sick: bool = bool(minion.get("sick", false)) and not can_attack
	if unit != null:
		_set_warming(sick)
	elif _zzz_label != null:
		_zzz_label.visible = sick


func _set_shell(kind: String, on: bool) -> void:
	if not on:
		if _shells.has(kind):
			(_shells[kind] as MeshInstance3D).visible = false
		return
	if not _shells.has(kind):
		var look: Dictionary = SHELL_LOOKS[kind]
		var mesh: Mesh
		if bool(look["sphere"]):
			var sp := SphereMesh.new()
			sp.radius = MODEL_RING_R * 1.45
			sp.height = MODEL_RING_R * 2.9
			sp.radial_segments = 32
			sp.rings = 16
			mesh = sp
		else:
			var cy := CylinderMesh.new()
			cy.top_radius = MODEL_RING_R * 1.2
			cy.bottom_radius = MODEL_RING_R * 1.3
			cy.height = 1.25
			cy.radial_segments = 32
			mesh = cy
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/lab/keyword_aura.gdshader")
		mat.set_shader_parameter("col", look["col"])
		mat.set_shader_parameter("base_alpha", look["base_alpha"])
		mat.set_shader_parameter("rim_alpha", look["rim_alpha"])
		mat.set_shader_parameter("frost", look["frost"])
		var mi := MeshInstance3D.new()
		mi.name = "Shell_" + kind
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = MODEL_RING_R * 1.25 if bool(look["sphere"]) else 0.62
		add_child(mi)
		_shells[kind] = mi
	(_shells[kind] as MeshInstance3D).visible = true


func _set_warming(on: bool) -> void:
	if on == warming:
		return
	warming = on
	if on and _warm_ring == null:
		_warm_ring = MeshInstance3D.new()
		_warm_ring.mesh = _arc_mesh(MODEL_RING_R * 0.94, MODEL_RING_R * 1.06, 0.75 * TAU)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.45, 0.95, 1.0)
		_warm_ring.material_override = m
		_warm_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_warm_ring.position.y = 0.08
		add_child(_warm_ring)
	if _warm_ring != null:
		_warm_ring.visible = on
	if _warm_tw != null and _warm_tw.is_valid():
		_warm_tw.kill()
	# Dim and flickery while booting; back to full when ready.
	_warm_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	var fx: Array = [["brightness", 0.72 if on else 1.12], ["flicker", 0.14 if on else 0.03], ["scan_strength", 0.2 if on else 0.05]]
	for pr in fx:
		var key: String = pr[0]
		var to: float = pr[1]
		var cur: Variant = unit.get_param(key)
		var from: float = float(cur) if cur != null else to
		_warm_tw.tween_method(func(v: float) -> void:
			if is_instance_valid(unit):
				unit.set_param(key, v), from, to, 0.5)


# A flat ring segment (the loading arc), its tail fading out.
static func _arc_mesh(r0: float, r1: float, span: float, seg: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		if (i / 4) % 2 == 1:
			continue  # dashes, like a loading spinner
		var a0: float = span * float(i) / seg
		var a1: float = span * float(i + 1) / seg
		var c0 := Color(1, 1, 1, float(i) / seg)
		var c1 := Color(1, 1, 1, float(i + 1) / seg)
		var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
		for v in [[p00, c0], [p01, c0], [p11, c1], [p00, c0], [p11, c1], [p10, c1]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


# --- Sprint 1b animation hooks (fire-and-forget; the director awaits
# the const durations). All tweens are created on this node, so they
# die with it if the node is freed mid-animation. ---

# Death fade: every per-node material goes transparent and its alpha
# follows `alpha`; the Zzz label fades too. Called every step of the
# death tween (via tween_method). Materials are all per-node (never
# shared), so this never leaks into another minion. The 2D badges are
# hidden by the badge manager (dying flag).
func set_fade(alpha: float) -> void:
	if unit != null:
		unit.set_param("dissolve", 1.0 - alpha)
	if alpha < 0.6:
		for sh in _shells.values():
			(sh as MeshInstance3D).visible = false
	_set_fade_recursive(self, alpha)
	if _zzz_label != null:
		_zzz_label.modulate.a = alpha


func _set_fade_recursive(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child == unit:
			continue
		if child is MeshInstance3D:
			var mat: Material = (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				if sm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.albedo_color.a = alpha
		_set_fade_recursive(child, alpha)


# Entrance / Final Bow trigger: the visible rim flashes bright (emission
# spike) and the token pulses once in scale, so players see WHO caused
# the effect. Fire-and-forget; the director awaits TRIGGER_FLASH_TIME.
func start_trigger_flash(duration: float) -> void:
	if unit != null:
		unit.tween_param("flash", 0.7, 0.0, duration)
		FxLab.glint(get_parent(), global_position + Vector3(0, 1.2 * scale.y, 0), Color(1.0, 0.95, 0.6), 0.7)
	var rim: MeshInstance3D = _gold_rim
	if _iron_rim != null and _iron_rim.visible:
		rim = _iron_rim
	if rim != null:
		var mat: Material = rim.material_override
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.95, 0.6)
			var tw := create_tween()
			tw.tween_property(sm, "emission_energy_multiplier", 3.0, duration * 0.3).set_ease(Tween.EASE_OUT)
			tw.tween_property(sm, "emission_energy_multiplier", 0.0, duration * 0.7).set_ease(Tween.EASE_IN)
			tw.finished.connect(func() -> void: sm.emission_enabled = false)
	var tw2 := create_tween()
	# Hotfix 1c.1: pulse relative to base_scale, never absolute 1.0.
	var b: Vector3 = base_scale if base_scale != Vector3.ZERO else scale
	tw2.tween_property(self, "scale", b * 1.08, duration * 0.4).set_ease(Tween.EASE_OUT)
	tw2.tween_property(self, "scale", b, duration * 0.6).set_ease(Tween.EASE_IN)


# Stats swap: the 2D badges tumble a half-turn via the badge manager.
func spin_gems(duration: float) -> void:
	if badge_link != null and badge_link.has_method("spin_badges"):
		badge_link.spin_badges(uid, duration)


# Gem punch: the 2D number badges scale 1.5 -> 1.0 via the badge manager.
# which: "hp" (damage/heal) or "both" (buff).
func punch_labels(which: String, duration: float) -> void:
	if badge_link != null and badge_link.has_method("punch_badges"):
		badge_link.punch_badges(uid, which, duration)


# Set the health badge's transient color (the director uses this for the
# green heal flash, then restores via update_stats -> badge refresh).
func set_hp_label_color(color: Color) -> void:
	if badge_link != null and badge_link.has_method("flash_hp_badge"):
		badge_link.flash_hp_badge(uid, color)


# Damage: the token's material flashes white/emissive, then restores.
func start_damage_flash(duration: float) -> void:
	if unit != null:
		unit.tween_param("flash", 0.8, 0.0, maxf(duration, 0.18))
	for mat in [_body_mat, _disc_mat]:
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission = Color.WHITE
		var tw := create_tween()
		tw.tween_property(mat, "emission_energy_multiplier", 1.8, duration * 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, duration * 0.7).set_ease(Tween.EASE_IN)
		tw.finished.connect(func() -> void: mat.emission_enabled = false)


# Damage: the token wobbles (rotation.z). Rotation, not position, so
# the shake never fights a slot tween (which owns position).
func start_shake(duration: float) -> void:
	if unit != null:
		unit.knock()
		return
	rotation.z = 0.0
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", 0.06, duration * 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:z", -0.06, duration * 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation:z", 0.0, duration * 0.25).set_ease(Tween.EASE_OUT)


# Heal: soft green glow pulse on the token's body.
func start_heal_glow(duration: float) -> void:
	if unit != null:
		FxLab.sparks(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.35, 1.0, 0.5), 26, 2.2, 0.97)
		FxLab.glint(get_parent(), global_position + Vector3(0, 1.0 * scale.y, 0), Color(0.5, 1.0, 0.6), 0.6)
	if _body_mat == null:
		return
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.2, 1.0, 0.4)
	var tw := create_tween()
	tw.tween_property(_body_mat, "emission_energy_multiplier", 1.0, duration * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body_mat, "emission_energy_multiplier", 0.0, duration * 0.7).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void: _body_mat.emission_enabled = false)


# Owner changed (steal): the pad takes the new owner's Boss color.
func set_pad_color(c: Color) -> void:
	pad_color = c
	if unit != null:
		unit.set_pad_color(c)


# Where hits land / projectiles aim (chest height).
func hit_point() -> Vector3:
	return global_position + Vector3(0, (1.0 if unit != null else 0.3) * scale.y, 0)


func set_highlight(on: bool) -> void:
	if _target_ring != null:
		_target_ring.visible = on


func _process(_delta: float) -> void:
	if _warm_ring != null and _warm_ring.visible:
		_warm_ring.rotation.y -= _delta * 3.2
	if _pulse_ring != null and _pulse_ring.visible and _pulse_mat != null:
		var t: float = Time.get_ticks_msec() / 1000.0
		_pulse_mat.emission_energy_multiplier = 0.8 + 0.5 * sin(t * 4.0)
