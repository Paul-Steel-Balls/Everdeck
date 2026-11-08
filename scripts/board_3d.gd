extends Node3D
class_name Board3D

# Everdeck Sprint 1a + 1b — the 3D match table. Node3D root, hosted in
# the MAIN viewport behind the 2D overlay (Sprint 1b: moved out of the
# 1280x720 SubViewport so the 3D renders at the phone's native resolution
# instead of being upscaled and soft).
# Layout (Sprint 1a.2 — readability pass; the ACTIVE player is always the
# near side, +z — the board flips when the phone is passed):
#   hero plaques z = +/-2.3, minion rows z = +/-0.9, mana rows flank the
#   plaques (5 gems each side, same depth), decks at (+/-6.3, +/-2.3),
#   7 slots per row, spacing 1.7, rows CENTERED (slot i sits at
#   (i - (count-1)/2) * spacing, so 1 is middle, 2 straddle, etc.).
# Camera: closer + less steep than 1b (fov 50, theta ~48.6 deg) so the
# table fills a 20:9 phone and tokens read ~1/10 of the screen width.
# Minion3D instances live in _minions, keyed by uid. Positions come from
# slot math, NOT containers. sync() updates existing nodes, adds new
# ones, removes dead ones — the board is NEVER freed + rebuilt mid-match.
# Picking: Area3D + CollisionShape3D on every minion / hero plaque,
# raycast from the camera; screen positions are MAIN-VIEWPORT coords
# (main converts canvas coords via the viewport's canvas transform).
# The targeting arrow is a 3D curved arrow (a chain of small segment
# meshes + a cone head) arcing from the source to the point under the
# finger on the table plane.
# Animation pools (Sprint 1b): floaters, particle emitters, projectiles,
# shockwave rings, crack flashes and the coin are pre-built in _ready and
# reused round-robin — never created/freed per hit.

# Step 2 (the real battlefield): the lab's layout. Crew stand as 3D
# models on a themed floating platform, Bosses at z = +/-4.9 with your
# deck's set piece beside you, seen from a fixed camera.
const TOKEN_SCALE: float = 1.55  # Crew nodes are scaled to this (was 1.22)
# Visual footprint radius in world units (the summoning pad). The 2D stat
# badges sit at +/-0.70r, so their outer edge lands on the footprint.
const TOKEN_VISUAL_R: float = 0.88
# Slot spacing: footprint plus a small visible gap. Seven per row fit.
const SLOT_SPACING: float = TOKEN_VISUAL_R * 2.0 + 0.06
const MY_ROW_Z: float = 2.0
const ENEMY_ROW_Z: float = -2.0
const CENTER_Z: float = 0.0
const ROW_CENTER_X: float = 0.0
const BOSS_SCALE: float = 1.75
# The arena (platform, props, set piece) is built at the lab's size and
# scaled up by this; the Bosses stand where the scaled stage puts them.
const STAGE_SCALE: float = 1.15
# Sprint 1c: HEADS/TAILS label height for the center-screen coin flip
# (low enough to stay on-screen at all aspect ratios).
const COIN_LABEL_HEIGHT: float = 1.1
# Fixed battle camera (no drift): the whole platform with the set piece.
const CAM_FOV: float = 47.0
const CAM_POS := Vector3(0, 13.4, 13.6)
const CAM_TARGET := Vector3(0, -0.6, 0.9)
# The camera sits ~2.5x farther than the phone-era table, so the pooled
# effects (floaters, projectiles, particles) are sized up to match.
const FX_SCALE: float = 2.2
# Sprint 1b Fix 1: 3D render scale, wired to the viewport's
# scaling_3d_scale (1.0 = native resolution; drop to ~0.8 if a phone
# struggles). ONE const — the whole game reads this one value.
const RENDER_SCALE_3D: float = 1.0
# Animation pool sizes (Sprint 1b). Pools cover the worst simultaneous
# use: a full-board AoE (14 floaters), buff-all (7 shimmer), a full
# destroy (7 bursts/flashes), a big split (6 projectiles). Reuse kills
# the node's in-flight tween (via the "anim_tween" meta) and resets it.
const POOL_FLOATERS: int = 16
const POOL_DUST: int = 2
const POOL_SPARKS: int = 2
const POOL_GREY_PUFF: int = 12
const POOL_SHIMMER: int = 8
const POOL_DESTROY_BURST: int = 8
const POOL_PROJECTILES: int = 8
const POOL_SHOCKWAVES: int = 2
const POOL_CRACK_FLASHES: int = 8

var _camera: Camera3D = null
var _camera_base_pos: Vector3 = Vector3.ZERO
var _shake_mag: float = 0.0
var _shake_time: float = 0.0
var _shake_dur: float = 0.0
var _minions: Dictionary = {}  # uid -> Minion3D
var _plaques: Array = [null, null]  # player -> HeroPlaque3D (hero badges)
# Sprint 1a.5: main owns the 2D HeroBadge panels and passes them here so
# sync() can wire each plaque to its panel when the plaque is created.
var hero_badges: Array = [null, null]  # player -> HeroBadge (2D)
var _slot_tweens: Dictionary = {}  # uid -> Tween
# Sprint 1b animation pools (round-robin indices).
var _floaters: Array = []  # [Label3D]
var _floater_idx: int = 0
var _particles: Dictionary = {}  # kind -> [CPUParticles3D]
var _particle_idx: Dictionary = {}  # kind -> int
var _projectiles: Array = []  # [{"sphere": MeshInstance3D, "trail": CPUParticles3D}]
var _projectile_idx: int = 0
var _shockwaves: Array = []  # [MeshInstance3D]
var _shockwave_idx: int = 0
var _crack_flashes: Array = []  # [MeshInstance3D]
var _crack_idx: int = 0
var _coin: MeshInstance3D = null
var _coin_heads_mat: StandardMaterial3D = null
var _coin_tails_mat: StandardMaterial3D = null
# Hotfix 1c.1: dark pill + moderate white HEADS/TAILS label under the
# center-screen coin (billboarded, so they face the camera).
var _coin_pill: MeshInstance3D = null
var _coin_label: Label3D = null
# Sprint 1a.5: faint ghost token shown at the landing slot while the
# player drags a minion with a targeted Entrance (arrow active).
var _ghost: Node3D = null


# Show the ghost token at a slot. It is purely visual: no Area3D (it
# must not eat picks) and no shadows.
func show_ghost_at(world_pos: Vector3) -> void:
	if _ghost == null:
		_ghost = _build_ghost()
	_ghost.position = world_pos + Vector3(0, 0.06, 0)
	_ghost.visible = true


func hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


func _build_ghost() -> Node3D:
	var root := Node3D.new()
	root.name = "GhostToken"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.9, 1.0, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TOKEN_VISUAL_R
	cyl.bottom_radius = TOKEN_VISUAL_R
	cyl.height = 0.1
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = TOKEN_VISUAL_R * 0.92
	tor.outer_radius = TOKEN_VISUAL_R * 1.02
	tor.rings = 6
	tor.ring_segments = 24
	ring.mesh = tor
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	root.visible = false
	add_child(root)
	return root


func _ready() -> void:
	# Sprint 1b Fix 1: the main viewport renders the 3D at native
	# resolution (render scale) with MSAA 2x. The project setting also
	# sets msaa_3d=1 (2x); this makes it explicit on the viewport itself.
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.scaling_3d_scale = RENDER_SCALE_3D
		vp.msaa_3d = Viewport.MSAA_2X
	_build_camera()
	_build_lighting()
	_build_table()
	_build_pools()


# --- Zoom: the mouse wheel moves the camera in toward what's under the
# cursor and lowers it, so the models are seen closer and more from the
# front; wheel back out (or middle-click) to return to the table view. ---
const ZOOM_MAX: float = 0.68
const ZOOM_STEP: float = 0.17
const ZOOM_LOW_ELEV: float = 26.0   # camera elevation (deg) at full zoom
var zoom_amount: float = 0.0
var _zoom_target: float = 0.0
var _zoom_focus: Vector3 = CAM_TARGET
var _zoom_focus_target: Vector3 = CAM_TARGET


func zoom_step(dir: int, viewport_pt: Vector2) -> void:
	if dir > 0:
		var hit: Variant = _ground_point(viewport_pt)
		if hit != null:
			var hp: Vector3 = hit
			hp.x = clampf(hp.x, -7.0, 7.0)
			hp.z = clampf(hp.z, -6.0, 6.5)
			_zoom_focus_target = Vector3(hp.x, 0.8, hp.z) if _zoom_target <= 0.001 else _zoom_focus_target.lerp(Vector3(hp.x, 0.8, hp.z), 0.5)
		_zoom_target = minf(ZOOM_MAX, _zoom_target + ZOOM_STEP)
	else:
		_zoom_target = maxf(0.0, _zoom_target - ZOOM_STEP)


func reset_zoom() -> void:
	_zoom_target = 0.0


func is_zoomed() -> bool:
	return _zoom_target > 0.001 or zoom_amount > 0.01


# Where a screen point meets the table (y = 0), or null.
func _ground_point(viewport_pt: Vector2) -> Variant:
	if _camera == null:
		return null
	var o: Vector3 = _camera.project_ray_origin(viewport_pt)
	var d: Vector3 = _camera.project_ray_normal(viewport_pt)
	if absf(d.y) < 0.0001:
		return null
	var t: float = -o.y / d.y
	return o + d * t if t > 0.0 else null


func _apply_zoom(delta: float) -> void:
	if _camera == null:
		return
	if zoom_amount < 0.0005 and _zoom_target <= 0.0:
		if zoom_amount != 0.0:
			zoom_amount = 0.0
			_camera.position = CAM_POS
			_camera.look_at(CAM_TARGET)
			_camera_base_pos = CAM_POS
		return
	var k: float = minf(1.0, delta * 7.0)
	zoom_amount = lerpf(zoom_amount, _zoom_target, k)
	if _zoom_target <= 0.0:
		_zoom_focus_target = _zoom_focus_target.lerp(CAM_TARGET, k)
	_zoom_focus = _zoom_focus.lerp(_zoom_focus_target, k)
	var zn: float = zoom_amount / ZOOM_MAX
	var target: Vector3 = CAM_TARGET.lerp(_zoom_focus, minf(1.0, zn * 1.4))
	var d: Vector3 = CAM_POS - CAM_TARGET
	var elev0: float = atan2(d.y, d.z)
	var elev: float = lerpf(elev0, deg_to_rad(ZOOM_LOW_ELEV), zn)
	var dist: float = d.length() * (1.0 - zoom_amount)
	var pos: Vector3 = target + Vector3(0.0, sin(elev), cos(elev)) * dist
	_camera_base_pos = pos
	if _shake_time <= 0.0:
		_camera.position = pos
	_camera.look_at(target)


func _process(delta: float) -> void:
	if not _preload_q.is_empty():
		_pump_preload()
	_apply_zoom(delta)
	# Camera shake (attack impacts): random offsets that decay to zero,
	# then the camera returns exactly to its base position.
	if _shake_time > 0.0 and _camera != null:
		_shake_time -= delta
		if _shake_time <= 0.0:
			_camera.position = _camera_base_pos
		else:
			var k: float = _shake_mag * (_shake_time / max(_shake_dur, 0.001))
			_camera.position = _camera_base_pos + Vector3(randf_range(-k, k), randf_range(-k, k), randf_range(-k, k))


# Attack-impact camera shake: magnitude is clamped by the caller
# (0.04 per damage, max 0.25); decay is the shake duration.
func shake_camera(magnitude: float, duration: float) -> void:
	_shake_mag = magnitude
	_shake_dur = duration
	_shake_time = duration


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "MatchCamera"
	_camera.fov = CAM_FOV
	_camera.position = CAM_POS
	add_child(_camera)
	# look_at AFTER add_child: look_at errors and does nothing on a node
	# that is not yet in the tree (latent 1a bug — the camera stared at
	# the horizon instead of the table).
	_camera.look_at(CAM_TARGET)
	_camera.current = true
	_camera_base_pos = _camera.position


# Sprint 1a.2: public helper so the 2D overlay can place HUD elements
# (Signature Move button) beside a 3D anchor in viewport pixels.
func screen_pos(world: Vector3) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(world)


# Whose perspective the table is drawn from: -1 = the active player
# (old pass-and-play behavior); otherwise a fixed seat (vs computer /
# online: always the local human at the bottom).
var view_player: int = -1


func view_of(gs: GameState) -> int:
	return view_player if view_player >= 0 else gs.active


func side(player_idx: int, active: int) -> float:
	return _side(player_idx, active)


func _build_lighting() -> void:
	# The stage brings its own sky, lights and environment (_ensure_stage);
	# this is the neutral fallback until the first sync knows the decks.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.0, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.45, 0.9)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnv"
	_world_env.environment = env
	add_child(_world_env)


func _build_table() -> void:
	pass  # the themed stage replaces the old felt table (_ensure_stage)


# --- The themed stage and the Bosses ---
# The arena follows the deck of whoever sits at the bottom: your own
# theme, your set piece beside your Boss. Rebuilt only when the seating
# or the decks change (pass-and-play flips it between turns).

var _world_env: WorldEnvironment = null
var _stage: ArenaStage = null
var _stage_key: String = ""
var _bosses: Array = [null, null]  # player -> HoloUnit (the Boss model)
var _stage_act: StageAct = null


func _ensure_stage(gs: GameState) -> void:
	var near: int = view_of(gs)
	var far: int = 1 - near
	var near_cls: String = str(gs.players[near]["class"])
	var far_cls: String = str(gs.players[far]["class"])
	var key: String = "%d|%s|%s" % [near, near_cls, far_cls]
	if key == _stage_key and _stage != null:
		return
	_stage_key = key
	if _stage != null:
		_stage.queue_free()
	for b in _bosses:
		if b != null and is_instance_valid(b):
			(b as Node).queue_free()
	_bosses = [null, null]
	if _stage_act != null and is_instance_valid(_stage_act):
		_stage_act.queue_free()
	_stage_act = null
	var near_c: Color = UIKit.CLASS_COLOR.get(near_cls, Color(1.0, 0.6, 0.2))
	var far_c: Color = UIKit.CLASS_COLOR.get(far_cls, Color(0.2, 0.8, 0.8))
	_stage = ArenaStage.new()
	_stage.name = "Stage"
	_stage.scale = Vector3.ONE * STAGE_SCALE
	add_child(_stage)
	_stage.build(near_cls, near_c, far_c)
	_world_env.environment = _stage.env
	for p in [near, far]:
		var cls: String = str(gs.players[p]["class"])
		var is_near: bool = p == near
		var col: Color = near_c if is_near else far_c
		var pos: Vector3 = boss_pos(is_near)
		if not ModelLib.has_model("hero_" + cls):
			continue
		var hu := HoloUnit.new()
		hu.name = "Boss%d" % p
		hu.setup("hero_" + cls, "model", HoloUnit.Style.MODEL, 1.0 if is_near else -1.0, col, col)
		hu.scale = Vector3(BOSS_SCALE, BOSS_SCALE, BOSS_SCALE)
		hu.position = pos
		hu.home = pos
		add_child(hu)
		_bosses[p] = hu
		if is_near and _stage.prop_holder != null:
			# Your Boss stands at the set piece and, now and then, slowly
			# plays with it.
			var act := StageAct.new()
			act.theme = _stage.theme
			act.hero = hu
			act.prop = _stage.prop_holder
			act.prop_size = ArenaStage.SET_PIECE_SIZE * STAGE_SCALE
			act.color = col
			act.interval = Vector2(20.0, 30.0)
			act.first_delay = 6.0
			add_child(act)
			_stage_act = act
	for p2 in [0, 1]:
		var plaque: HeroPlaque3D = _plaques[p2]
		if plaque != null:
			plaque.place_at(boss_pos(p2 == near), _bosses[p2])


# Where a Boss stands on the (scaled) stage.
static func boss_pos(near: bool) -> Vector3:
	return ArenaStage.hero_pos(near) * STAGE_SCALE


# Screen-space aim points sit at chest height on a 3D model.
func aim_lift_minion(uid: int) -> Vector3:
	var n: Minion3D = _minions.get(uid)
	return Vector3(0, 1.0 * n.scale.y, 0) if n != null and n.unit != null else Vector3.ZERO


func aim_lift_hero(player_idx: int) -> Vector3:
	return Vector3(0, 1.7, 0) if boss_unit(player_idx) != null else Vector3.ZERO


# --- Smoothness: no first-use hitches ---
# Every model the match can show is parsed ahead of time, a few
# milliseconds' worth per frame, so a card's first entrance never stalls.
# Each effect also runs once out of sight, so its shader is compiled
# before the first real hit.

const PRELOAD_BUDGET_USEC: int = 4000
var _preload_q: Array = []
var _warmed: bool = false


func preload_models(ids: Array) -> void:
	for id in ids:
		var s: String = str(id)
		if s != "" and not ModelLib.is_cached(s) and not _preload_q.has(s):
			_preload_q.append(s)


func preload_pending() -> int:
	return _preload_q.size()


func _pump_preload() -> void:
	var t0: int = Time.get_ticks_usec()
	while not _preload_q.is_empty() and Time.get_ticks_usec() - t0 < PRELOAD_BUDGET_USEC:
		ModelLib.preload_model(str(_preload_q.pop_front()))


func warmup_fx() -> void:
	if _warmed:
		return
	_warmed = true
	# Under the platform, out of the camera's view.
	var p := Vector3(0, -9.0, 0)
	var c := Color(1, 1, 1)
	FxLab.sparks(self, p, c, 4, 1.0, 0.5)
	FxLab.glint(self, p, c, 0.2)
	FxLab.shock_ring(self, p, c, 0.3)
	FxLab.slash(self, p, c, 0.0)
	FxLab.wisps(self, p, 2)
	FxLab.pad_pulse(self, p, c)
	var pts := PackedVector3Array([p, p + Vector3(0.1, 0, 0), p + Vector3(0, 0.1, 0)])
	FxLab.cubes_scatter(self, pts, c)
	FxLab.cubes_converge(self, pts, c, 0.2)
	for kind in ["shimmer", "grey_puff"]:
		spawn_particles(kind, p)


func boss_unit(player_idx: int) -> HoloUnit:
	var b: Variant = _bosses[player_idx]
	return b if b != null and is_instance_valid(b) else null


# --- Sprint 1b animation pools ---
# Pre-built, reused round-robin. Reuse kills the node's in-flight tween
# (stored in the "anim_tween" meta) and resets the node, so a pooled node
# never carries a stale animation. No pooled node is ever freed mid-match.

func _pool_kill_tween(node: Node) -> void:
	if not node.has_meta("anim_tween"):
		return
	var old: Tween = node.get_meta("anim_tween")
	if old != null and old.is_valid():
		old.kill()
	node.set_meta("anim_tween", null)


func _new_particle(kind: String, amount: int, lifetime: float, color: Color, vel_min: float, vel_max: float, spread: float, gravity: float, scale_min: float, scale_max: float, dir_up: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.spread = spread
	p.initial_velocity_min = vel_min * FX_SCALE
	p.initial_velocity_max = vel_max * FX_SCALE
	p.gravity = Vector3(0, gravity * FX_SCALE, 0)
	p.scale_amount_min = scale_min * FX_SCALE
	p.scale_amount_max = scale_max * FX_SCALE
	p.color = color
	if dir_up:
		p.direction = Vector3.UP
	add_child(p)
	return p


func _build_pools() -> void:
	# Damage/heal floaters (Label3D billboards, pooled).
	for _i in POOL_FLOATERS:
		var l := Label3D.new()
		l.billboard = 1  # Label3D.BILLBOARD_ENABLED
		l.font_size = 36
		l.pixel_size = 0.012 * FX_SCALE
		l.modulate = Color(1, 1, 1, 0)
		l.outline_size = 6
		l.outline_modulate = Color(0, 0, 0, 0.9)
		l.visible = false
		add_child(l)
		_floaters.append(l)
	# Particle emitters (each ≤ 24 particles, well under the 64 cap).
	_particles["dust"] = []
	_particles["sparks"] = []
	_particles["grey_puff"] = []
	_particles["shimmer"] = []
	_particles["destroy_burst"] = []
	_particle_idx = {"dust": 0, "sparks": 0, "grey_puff": 0, "shimmer": 0, "destroy_burst": 0}
	for _i in POOL_DUST:
		_particles["dust"].append(_new_particle("dust", 24, 0.5, Color(0.8, 0.75, 0.65), 1.2, 2.4, 90.0, 1.5, 0.05, 0.12, true))
	for _i in POOL_SPARKS:
		_particles["sparks"].append(_new_particle("sparks", 16, 0.35, Color(1.0, 0.85, 0.3), 2.0, 4.0, 180.0, 3.0, 0.03, 0.07))
	for _i in POOL_GREY_PUFF:
		_particles["grey_puff"].append(_new_particle("grey_puff", 20, 0.5, Color(0.5, 0.5, 0.5), 0.8, 1.6, 180.0, -0.5, 0.08, 0.16))
	for _i in POOL_SHIMMER:
		_particles["shimmer"].append(_new_particle("shimmer", 12, 0.6, Color(1.0, 0.85, 0.2), 0.8, 1.6, 30.0, -1.0, 0.03, 0.07, true))
	for _i in POOL_DESTROY_BURST:
		_particles["destroy_burst"].append(_new_particle("destroy_burst", 24, 0.45, Color(0.35, 0.1, 0.5), 2.0, 3.5, 180.0, 2.0, 0.04, 0.09))
	# Projectiles: emissive sphere + a world-space trail emitter each.
	var proj_mat := StandardMaterial3D.new()
	proj_mat.albedo_color = Color(1.0, 0.9, 0.4)
	proj_mat.emission_enabled = true
	proj_mat.emission = Color(1.0, 0.85, 0.25)
	proj_mat.emission_energy_multiplier = 2.0
	proj_mat.roughness = 0.3
	var proj_mesh := SphereMesh.new()
	proj_mesh.radius = 0.16 * FX_SCALE
	proj_mesh.height = 0.32 * FX_SCALE
	proj_mesh.radial_segments = 10
	proj_mesh.rings = 8
	for _i in POOL_PROJECTILES:
		var s := MeshInstance3D.new()
		s.mesh = proj_mesh
		s.material_override = proj_mat
		s.visible = false
		add_child(s)
		var trail := CPUParticles3D.new()
		trail.amount = 32
		trail.lifetime = 0.4
		trail.one_shot = false
		trail.emitting = false
		trail.local_coords = false  # particles stay in world space as the emitter moves
		trail.spread = 15.0
		trail.initial_velocity_min = 0.1
		trail.initial_velocity_max = 0.4
		trail.scale_amount_min = 0.03 * FX_SCALE
		trail.scale_amount_max = 0.06 * FX_SCALE
		trail.color = Color(1.0, 0.8, 0.2)
		add_child(trail)
		_projectiles.append({"sphere": s, "trail": trail})
	# Shockwave rings (flat tori that expand + fade).
	for _i in POOL_SHOCKWAVES:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.9
		ring_mesh.outer_radius = 1.0
		ring_mesh.rings = 8
		ring_mesh.ring_segments = 32
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.0)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.85, 0.3)
		ring_mat.emission_energy_multiplier = 1.5
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.roughness = 0.4
		ring.material_override = ring_mat
		ring.rotation.x = -PI / 2.0
		ring.visible = false
		ring.set_meta("mat", ring_mat)
		add_child(ring)
		_shockwaves.append(ring)
	# Crack flashes (destroy): dark-purple spheres that pop + fade.
	for _i in POOL_CRACK_FLASHES:
		var flash_mesh := SphereMesh.new()
		flash_mesh.radius = 0.5
		flash_mesh.height = 1.0
		flash_mesh.radial_segments = 10
		flash_mesh.rings = 8
		var flash := MeshInstance3D.new()
		flash.mesh = flash_mesh
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = Color(0.2, 0.05, 0.35, 0.0)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(0.5, 0.1, 0.8)
		flash_mat.emission_energy_multiplier = 2.0
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash.material_override = flash_mat
		flash.visible = false
		flash.set_meta("mat", flash_mat)
		add_child(flash)
		_crack_flashes.append(flash)
	# The coin (coin flip): one mesh, two materials (heads gold / tails bronze).
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.45
	coin_mesh.bottom_radius = 0.45
	coin_mesh.height = 0.08
	coin_mesh.radial_segments = 20
	_coin = MeshInstance3D.new()
	_coin.mesh = coin_mesh
	_coin_heads_mat = StandardMaterial3D.new()
	_coin_heads_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_coin_heads_mat.metallic = 0.9
	_coin_heads_mat.roughness = 0.25
	_coin_heads_mat.emission_enabled = true
	_coin_heads_mat.emission = Color(1.0, 0.8, 0.15)
	_coin_heads_mat.emission_energy_multiplier = 0.6
	_coin_tails_mat = StandardMaterial3D.new()
	_coin_tails_mat.albedo_color = Color(0.55, 0.35, 0.15)
	_coin_tails_mat.metallic = 0.7
	_coin_tails_mat.roughness = 0.4
	_coin.visible = false
	add_child(_coin)
	# Hotfix 1c.1: dark pill + moderate white HEADS/TAILS label shown
	# under the center-screen coin. Both billboard to face the camera;
	# the label skips the depth test so it always draws over the pill.
	var pill_mesh := QuadMesh.new()
	pill_mesh.size = Vector2(0.9, 0.32) * FX_SCALE
	_coin_pill = MeshInstance3D.new()
	_coin_pill.mesh = pill_mesh
	var pill_mat := StandardMaterial3D.new()
	pill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pill_mat.albedo_color = Color(0.03, 0.03, 0.06, 0.88)
	pill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_coin_pill.material_override = pill_mat
	_coin_pill.visible = false
	add_child(_coin_pill)
	_coin_label = Label3D.new()
	_coin_label.font_size = 48
	_coin_label.pixel_size = 0.005 * FX_SCALE
	_coin_label.modulate = Color.WHITE
	_coin_label.outline_size = 8
	_coin_label.outline_modulate = Color(0, 0, 0, 0.9)
	_coin_label.billboard = 1  # Label3D.BILLBOARD_ENABLED
	_coin_label.no_depth_test = true
	_coin_label.render_priority = 10
	_coin_label.visible = false
	add_child(_coin_label)


# --- Pool accessors (Sprint 1b) ---
# The director calls these; each returns a reset pooled node. Tweens the
# director creates on a pooled node are stored in the node's "anim_tween"
# meta and killed on the next reuse, so a stale tween never fights a new one.

func get_floater() -> Label3D:
	var l: Label3D = _floaters[_floater_idx]
	_floater_idx = (_floater_idx + 1) % _floaters.size()
	_pool_kill_tween(l)
	l.visible = true
	l.modulate = Color(1, 1, 1, 1)
	l.scale = Vector3.ONE
	return l


func spawn_particles(kind: String, pos: Vector3) -> void:
	var pool: Array = _particles.get(kind, [])
	if pool.is_empty():
		return
	var idx: int = int(_particle_idx.get(kind, 0))
	var p: CPUParticles3D = pool[idx]
	_particle_idx[kind] = (idx + 1) % pool.size()
	p.position = pos
	p.restart()


func launch_projectile(from: Vector3, to: Vector3, duration: float) -> Tween:
	# Arced flight (Bezier, raised mid-point) with a trail. Returns the
	# flight tween; the director awaits it. Cleanup (hide sphere, stop
	# trail) runs on tween finish.
	var entry: Dictionary = _projectiles[_projectile_idx]
	_projectile_idx = (_projectile_idx + 1) % _projectiles.size()
	var sphere: MeshInstance3D = entry["sphere"]
	var trail: CPUParticles3D = entry["trail"]
	_pool_kill_tween(sphere)
	var p0: Vector3 = from + Vector3(0, 0.4, 0)
	var p1: Vector3 = to + Vector3(0, 0.4, 0)
	var ctrl: Vector3 = (p0 + p1) * 0.5 + Vector3(0, 2.4, 0)
	sphere.position = p0
	sphere.visible = true
	trail.position = p0
	trail.emitting = true
	var tw := create_tween()
	sphere.set_meta("anim_tween", tw)
	tw.tween_method(func(t: float) -> void:
		var pos: Vector3 = _bezier(p0, ctrl, p1, t)
		sphere.position = pos
		trail.position = pos
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.finished.connect(func() -> void:
		sphere.visible = false
		trail.emitting = false
	)
	return tw


func _bezier(p0: Vector3, ctrl: Vector3, p1: Vector3, t: float) -> Vector3:
	var a: float = (1.0 - t) * (1.0 - t)
	var b: float = 2.0 * (1.0 - t) * t
	var c: float = t * t
	return p0 * a + ctrl * b + p1 * c


func spawn_shockwave(pos: Vector3, duration: float) -> Tween:
	# Expanding ring (scale 0.3 -> 6) that fades out. Returns the tween.
	var ring: MeshInstance3D = _shockwaves[_shockwave_idx]
	_shockwave_idx = (_shockwave_idx + 1) % _shockwaves.size()
	_pool_kill_tween(ring)
	var mat: StandardMaterial3D = ring.get_meta("mat")
	ring.position = Vector3(pos.x, 0.12, pos.z)
	ring.scale = Vector3(0.3, 0.3, 1.0)
	ring.visible = true
	mat.albedo_color.a = 0.85
	var tw := create_tween()
	ring.set_meta("anim_tween", tw)
	tw.tween_property(ring, "scale", Vector3(6.0, 6.0, 1.0), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.85, 0.0, duration)
	tw.finished.connect(func() -> void: ring.visible = false)
	return tw


func get_crack_flash() -> MeshInstance3D:
	var flash: MeshInstance3D = _crack_flashes[_crack_idx]
	_crack_idx = (_crack_idx + 1) % _crack_flashes.size()
	_pool_kill_tween(flash)
	flash.visible = true
	var mat: StandardMaterial3D = flash.get_meta("mat")
	mat.albedo_color.a = 0.9
	return flash


# Hotfix 1c.1: screen point -> world point on the plane y=height.
func _world_for_screen(sp: Vector2, height: float) -> Vector3:
	if _camera == null:
		return Vector3(ROW_CENTER_X, height, CENTER_Z)
	var origin: Vector3 = _camera.project_ray_origin(sp)
	var normal: Vector3 = _camera.project_ray_normal(sp)
	if absf(normal.y) < 0.0001:
		return Vector3(ROW_CENTER_X, height, CENTER_Z)
	var t: float = (height - origin.y) / normal.y
	if t < 0.0:
		return Vector3(ROW_CENTER_X, height, CENTER_Z)
	return origin + normal * t


# Hotfix 1c.1: fit the coin moment into the inter-row gap, measured in
# SCREEN space at runtime, so it never covers a token at any viewport
# size. Returns {"pos": coin rest, "coin_scale": float, "pill_pos"}.
# The label/pill keep a fixed moderate world size (font 48); only the
# coin scales, capped so it stays a satisfying flip.
func _coin_moment() -> Dictionary:
	var near_w: Vector3 = slot_position(0, 0, 1, 0)
	var far_w: Vector3 = slot_position(1, 0, 1, 0)
	var near_c: Vector2 = screen_pos(near_w)
	var far_c: Vector2 = screen_pos(far_w)
	var near_r: float = near_c.distance_to(screen_pos(near_w + Vector3(TOKEN_VISUAL_R, 0, 0)))
	var far_r: float = far_c.distance_to(screen_pos(far_w + Vector3(TOKEN_VISUAL_R, 0, 0)))
	var gap_top: float = far_c.y + far_r
	var gap_bot: float = near_c.y - near_r
	var gap_h: float = maxf(60.0, gap_bot - gap_top)
	var gap_cx: float = (near_c.x + far_c.x) * 0.5
	var gap_cy: float = (gap_top + gap_bot) * 0.5
	var pos: Vector3 = _world_for_screen(Vector2(gap_cx, gap_cy), 0.1)
	var pxw: float = maxf(1.0, screen_pos(pos).distance_to(screen_pos(pos + Vector3(1, 0, 0))))
	var pill_h_px: float = 0.32 * FX_SCALE * pxw
	var coin_d_px: float = clampf(gap_h - pill_h_px - 12.0, 40.0, 200.0)
	var sc: float = clampf(coin_d_px / (0.9 * pxw), 0.3, 1.8)
	var pill_pos: Vector3 = pos + Vector3(0, -(coin_d_px / pxw * 0.5 - 0.08), 0)
	return {"pos": pos, "coin_scale": sc, "pill_pos": pill_pos}


# Hotfix 1c.1: the coin flip is fitted into the inter-row gap (see
# _coin_moment): the coin spins down to the gap center, then lands
# showing HEADS/TAILS — moderate white text on a small dark pill
# tucked under the coin like a caption. Holds ~0.6s, then the effect's
# own events follow. Coroutine — the director awaits it.
func flip_coin_center(heads: bool, spin_time: float, hold_time: float) -> void:
	_pool_kill_tween(_coin)
	_coin.material_override = _coin_heads_mat if heads else _coin_tails_mat
	var moment: Dictionary = _coin_moment()
	var pos: Vector3 = moment["pos"]
	var sc: float = moment["coin_scale"]
	var pill_pos: Vector3 = moment["pill_pos"]
	_coin.scale = Vector3(sc, sc, sc)
	_coin.position = pos + Vector3(0, 0.8, 0)
	_coin.rotation = Vector3.ZERO
	_coin.visible = true
	_coin_pill.visible = false
	_coin_label.visible = false
	var tw := create_tween()
	_coin.set_meta("anim_tween", tw)
	tw.tween_property(_coin, "position:y", pos.y, spin_time).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(_coin, "rotation:y", PI * 6.0, spin_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	# Landed: the result on a dark pill tucked under the coin.
	_coin_label.text = "HEADS" if heads else "TAILS"
	_coin_pill.position = pill_pos
	_coin_label.position = pill_pos
	_coin_pill.visible = true
	_coin_label.visible = true
	_coin_label.modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(hold_time).timeout
	_coin.visible = false
	_coin.scale = Vector3.ONE
	_coin_pill.visible = false
	var tw2 := create_tween()
	_coin_label.set_meta("anim_tween", tw2)
	tw2.tween_method(func(a: float) -> void: _coin_label.modulate.a = a, 1.0, 0.0, 0.25)
	tw2.tween_callback(_coin_label.set_visible.bind(false))


# Sprint 1c: hero floaters belong ON the 2D hero panel (a 3D Label3D at
# the left-edge anchor rises off-screen). Forwards to the badge.
func hero_floater(player_idx: int, text: String, color: Color) -> void:
	if player_idx < 0 or player_idx >= hero_badges.size():
		return
	var hb: HeroBadge = hero_badges[player_idx]
	if hb != null and is_instance_valid(hb):
		hb.float_text(text, color)


func animate_draw(player_idx: int, active: int, duration: float) -> void:
	# Sprint 1a.4: the big deck stacks are gone; the draw animation is a
	# pop on the badge's deck-count icon. Coroutine — the director awaits
	# it. The final sync fixes the deck count afterward.
	var plaque: HeroPlaque3D = _plaques[player_idx]
	if plaque != null:
		plaque.pulse_deck(duration)
		await get_tree().create_timer(duration).timeout


# --- Layout (Sprint 1a.5) ---
# Signed z throughout. The active player's row is at z=+1.0 (just above
# the 2D hand, in the middle of their half); the enemy's is at z=-3.15.
# Rows are CENTERED about ROW_CENTER_X.

func _side(player_idx: int, active: int) -> float:
	return 1.0 if player_idx == active else -1.0


func _row_z(player_idx: int, active: int) -> float:
	return MY_ROW_Z if player_idx == active else ENEMY_ROW_Z


# The 2D HeroBadge panels live at fixed canvas positions (main owns
# them); the 3D HeroPlaque3D anchor follows its panel via unproject, so
# there are no badge world consts anymore. This just reports where the
# anchor currently is.
func _hero_position(player_idx: int, _active: int) -> Vector3:
	var plaque: HeroPlaque3D = _plaques[player_idx]
	if plaque != null:
		return plaque.position
	return Vector3.ZERO


# Token visual radius (world units) for the 2D stat badges.
func token_visual_radius() -> float:
	return TOKEN_VISUAL_R


func _slot_position(player_idx: int, idx: int, count: int, active: int) -> Vector3:
	# Rows are CENTERED about ROW_CENTER_X — 1 minion sits in the middle,
	# 2 straddle the middle, and so on. SLOT_SPACING includes the stat
	# badges (the token+badge footprint is the token itself) + a gap.
	var x: float = ROW_CENTER_X + (float(idx) - float(count - 1) / 2.0) * SLOT_SPACING
	return Vector3(x, 0.0, _row_z(player_idx, active))


# Public slot math (the director needs it for summon / steal targets).
# count = the row's minion count (the caller reads it from the GameState).
func slot_position(player_idx: int, idx: int, count: int, active: int) -> Vector3:
	return _slot_position(player_idx, idx, count, active)


# Tween every EXISTING minion node to its current-board slot (neighbors
# sliding aside for a summon, survivors closing ranks after a death, both
# rows settling after a steal). Does NOT add or remove nodes — the caller
# (the director) owns the new/dead node. only_player: slide just that
# player's row (a summon settles only its own row — a full-board slide
# could prematurely move a minion that a later steal event in the same
# batch is supposed to glide). Returns true if any node moved.
func slide_to_slots(gs: GameState, only_player: int = -1) -> bool:
	var moved: bool = false
	var active: int = view_of(gs)
	var players: Array = [only_player] if only_player >= 0 else [0, 1]
	for p in players:
		var board: Array = gs.players[p]["board"]
		for i in board.size():
			var m: Dictionary = board[i]
			var uid: int = gs.uid_for(m)
			var node: Minion3D = _minions.get(uid)
			if node != null:
				var target: Vector3 = _slot_position(p, i, board.size(), active)
				if node.position.distance_to(target) >= 0.01:
					_tween_to_slot(node, uid, target)
					moved = true
	return moved


# --- Full sync: update existing, add new, remove dead. Never rebuilds. ---

func sync(gs: GameState) -> void:
	var active: int = view_of(gs)
	_ensure_stage(gs)
	for p in [0, 1]:
		# Hero badge (Sprint 1a.5): the 2D HeroBadge panel (main owns it)
		# is the visual; the 3D plaque is an invisible anchor that
		# follows the panel via unproject. set_far_side is a no-op.
		var plaque: HeroPlaque3D = _plaques[p]
		if plaque == null:
			plaque = HeroPlaque3D.new()
			add_child(plaque)
			_plaques[p] = plaque
			plaque.badge = hero_badges[p]
			plaque.setup(p, str(gs.players[p]["class"]), int(gs.players[p]["hp"]))
			plaque.place_at(boss_pos(p == active), boss_unit(p))
		# Hotfix 1c.2: update_hp runs on EVERY sync, not just the
		# existing-plaque path. After the pass-the-phone interstitial's
		# full _clear(), plaques are recreated and setup() alone never
		# pushed HP onto the fresh badge, so it showed the construction
		# default (30/30) until the next action's sync corrected it.
		plaque.update_hp(int(gs.players[p]["hp"]))
		# The far badge's portrait faces the table center; the enemy
		# badge shows a hand-size badge; both badges show mana + deck.
		plaque.set_far_side(p != active)
		plaque.set_enemy_badge(int(gs.players[p]["hand"].size()), p != active)
		plaque.set_mana(int(gs.players[p]["mana"]), int(gs.players[p]["max_mana"]))
		plaque.set_deck_count(int(gs.players[p]["deck"].size()))
		# Minions.
		var board: Array = gs.players[p]["board"]
		var seen: Dictionary = {}
		for i in board.size():
			var m: Dictionary = board[i]
			var uid: int = gs.uid_for(m)
			seen[uid] = true
			var node: Minion3D = _minions.get(uid)
			var target_pos: Vector3 = _slot_position(p, i, board.size(), active)
			if node == null:
				node = Minion3D.new()
				node.setup(m, p, _pad_color(gs, p))
				node.scale = Vector3(TOKEN_SCALE, TOKEN_SCALE, TOKEN_SCALE)
				node.base_scale = Vector3(TOKEN_SCALE, TOKEN_SCALE, TOKEN_SCALE)
				add_child(node)
				_minions[uid] = node
				node.position = target_pos
			else:
				if node.player != p:
					node.set_pad_color(_pad_color(gs, p))
				node.player = p  # owner can change (steal)
				node.update_stats(m, p == active)
				# Hotfix 1c.1 safety net: an idle token must rest at
				# base_scale. Any scale tween that ended at an absolute
				# value is corrected here, so the error can't persist
				# past the turn.
				if node.base_scale == Vector3.ZERO:
					node.base_scale = Vector3(TOKEN_SCALE, TOKEN_SCALE, TOKEN_SCALE)
				node.scale = node.base_scale
				_tween_to_slot(node, uid, target_pos)
		var dead_uids: Array = []
		for uid in _minions.keys():
			var node2: Minion3D = _minions[uid]
			if node2.player == p and not seen.has(uid):
				dead_uids.append(uid)
		for uid in dead_uids:
			(_minions[uid] as Node).queue_free()
			_minions.erase(uid)


func _tween_to_slot(node: Minion3D, uid: int, target: Vector3) -> void:
	if node.position.distance_to(target) < 0.01:
		return
	var old: Tween = _slot_tweens.get(uid)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	_slot_tweens[uid] = tw
	tw.tween_property(node, "position", target, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# The director calls this before lunging a minion, so a slot tween from
# a previous sync never fights the lunge tween (both write position).
func cancel_slot_tween(uid: int) -> void:
	var old: Tween = _slot_tweens.get(uid)
	if old != null and old.is_valid():
		old.kill()
	_slot_tweens.erase(uid)


func _pad_color(gs: GameState, p: int) -> Color:
	return UIKit.CLASS_COLOR.get(str(gs.players[p]["class"]), Color(1.0, 0.75, 0.35))


# Pad color without a GameState (the director's add_unit): the Boss model's
# color, else gold.
func _pad_color_for(p: int) -> Color:
	var b: HoloUnit = boss_unit(p)
	return b.color if b != null else Color(1.0, 0.75, 0.35)


# --- Director hooks (snap changes between animations) ---

func add_unit(player_idx: int, minion: Dictionary, board_idx: int, active: int, count: int) -> void:
	var uid: int = int(minion.get("uid", -1))
	if uid < 0 or _minions.has(uid):
		return
	var node := Minion3D.new()
	node.setup(minion, player_idx, _pad_color_for(player_idx))
	node.scale = Vector3(TOKEN_SCALE, TOKEN_SCALE, TOKEN_SCALE)
	node.base_scale = Vector3(TOKEN_SCALE, TOKEN_SCALE, TOKEN_SCALE)
	add_child(node)
	_minions[uid] = node
	node.position = _slot_position(player_idx, board_idx, count, active)


func remove_unit(uid: int) -> void:
	if not _minions.has(uid):
		return
	var old: Tween = _slot_tweens.get(uid)
	if old != null and old.is_valid():
		old.kill()
	_slot_tweens.erase(uid)
	(_minions[uid] as Node).queue_free()
	_minions.erase(uid)


func update_unit_stats(minion: Dictionary, is_mine: bool) -> void:
	var uid: int = int(minion.get("uid", -1))
	if uid < 0 or not _minions.has(uid):
		return
	(_minions[uid] as Minion3D).update_stats(minion, is_mine)


func update_hero_hp(player_idx: int, hp: int) -> void:
	var plaque: HeroPlaque3D = _plaques[player_idx]
	if plaque != null:
		plaque.update_hp(hp)


func minion_node(uid: int) -> Minion3D:
	return _minions.get(uid)


func hero_plaque(player_idx: int) -> HeroPlaque3D:
	return _plaques[player_idx]


# Turn start: mana gems light up one at a time, left to right (scale
# pop, staggered). Fire-and-forget; the director awaits the total.
# Sets visible for gems up to `mana` — the new turn's gems may not have
# been synced yet (the final sync fixes materials/visibility).
func animate_mana_gems(player_idx: int, mana: int, pop_time: float, stagger: float) -> void:
	# Sprint 1a.4: the badge owns its mana gems now.
	var plaque: HeroPlaque3D = _plaques[player_idx]
	if plaque != null:
		plaque.pop_mana_gems(mana, pop_time, stagger)


# All uids currently on the board (the smoke test compares this to the
# game state's uid set after the director runs).
func board_uids() -> Array:
	return _minions.keys()


# Sprint 1b Fix 3: lookups return a found flag — NEVER Vector3.ZERO as
# "not found" (a minion legitimately at the origin would be
# indistinguishable from a missing one). Callers MUST check "found".
func minion_position(uid: int) -> Dictionary:
	var node: Minion3D = _minions.get(uid)
	if node == null:
		return {"found": false, "position": Vector3.ZERO}
	return {"found": true, "position": node.position}


func hero_position(player_idx: int, active: int) -> Dictionary:
	var plaque: HeroPlaque3D = _plaques[player_idx]
	if plaque == null:
		return {"found": false, "position": Vector3.ZERO}
	return {"found": true, "position": plaque.position}


func set_target_highlight(targets: Array, gs: GameState, on: bool) -> void:
	for t in targets:
		if t.get("kind", "") == "hero":
			var hp_plaque: HeroPlaque3D = _plaques[int(t.get("player", 0))]
			if hp_plaque != null:
				hp_plaque.set_highlight(on)
		elif t.get("kind", "") == "minion":
			var p: int = int(t.get("player", 0))
			var bi: int = int(t.get("board_idx", -1))
			var board: Array = gs.players[p]["board"]
			if bi >= 0 and bi < board.size():
				var uid: int = gs.uid_for(board[bi])
				var node: Minion3D = _minions.get(uid)
				if node != null:
					node.set_highlight(on)


func clear_highlights() -> void:
	for uid in _minions.keys():
		(_minions[uid] as Minion3D).set_highlight(false)
	for plaque in _plaques:
		if plaque != null:
			(plaque as HeroPlaque3D).set_highlight(false)


# --- Picking (raycast from the camera) ---

# screen_pos is in MAIN-VIEWPORT coords (main converts canvas coords via
# the viewport's canvas transform before calling this).
func pick(screen_pos: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var normal: Vector3 = _camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + normal * 100.0
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	if collider == null:
		return {}
	if collider.has_meta("minion_3d"):
		var m3d: Minion3D = collider.get_meta("minion_3d")
		return {"kind": "minion", "player": m3d.player, "uid": m3d.uid}
	if collider.has_meta("hero_player"):
		return {"kind": "hero", "player": int(collider.get_meta("hero_player"))}
	return {}
