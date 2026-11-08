extends Node3D
class_name HeroPlaque3D

# Everdeck Sprint 1a.5 — the 3D hero badge is now an INVISIBLE anchor +
# pick area. All visuals moved to the 2D HeroBadge panel (main creates
# one per player; this node follows its panel's projected position, so
# 3D pick raycasts, the director's hero_position, and the 2D arrow snap
# target all agree on the same point). Every visual/animation method
# forwards to the badge. set_far_side is a no-op kept for compatibility
# (the 2D portrait needs no flipping).

var player: int = 0
var class_id: String = ""
var badge: HeroBadge = null  # wired by main after board.sync()

var _area: Area3D = null
# Step 2: the Boss now stands on the field as a 3D model. The anchor sits
# at the Boss (place_at), so attacks, Tricks and the targeting arrow aim at
# the model; the 2D panel still shows HP, mana and the deck.
var boss: HoloUnit = null
var _placed: bool = false
var _ring: MeshInstance3D = null


func setup(player_idx: int, hero_class: String, hp: int) -> void:
	player = player_idx
	class_id = hero_class
	# Invisible pick area (covers the 2D panel generously). The plaque
	# node itself follows the panel (see _process), so this moves with it.
	_area = Area3D.new()
	_area.name = "PickArea"
	_area.monitoring = false
	_area.monitorable = true
	_area.set_meta("hero_player", player_idx)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 1.2
	shape.shape = cyl
	shape.position = Vector3(0, 0.4, 0)
	_area.add_child(shape)
	add_child(_area)
	_snap_to_badge()
	# Hotfix 1c.2: the hp parameter was accepted but ignored — apply it
	# so a freshly created plaque never shows the badge default.
	if badge != null:
		badge.set_hp(hp, 30)


func _process(_delta: float) -> void:
	if not _placed:
		_snap_to_badge()


# Anchor the plaque on the Boss standing at `pos` (boss may be null when a
# class has no model: the anchor still sits there).
func place_at(pos: Vector3, boss_unit: HoloUnit) -> void:
	_placed = true
	boss = boss_unit
	position = pos
	if _area != null:
		var shape: CollisionShape3D = _area.get_child(0)
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.1
		cyl.height = 3.2
		shape.shape = cyl
		shape.position = Vector3(0, 1.6, 0)
	if _ring == null:
		var tm := TorusMesh.new()
		tm.inner_radius = 1.15
		tm.outer_radius = 1.32
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.2)
		_ring = MeshInstance3D.new()
		_ring.mesh = tm
		_ring.material_override = m
		_ring.scale = Vector3(1, 0.25, 1)
		_ring.position.y = 0.06
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.visible = false
		add_child(_ring)


# Where hits land on the Boss (chest height).
func hit_point() -> Vector3:
	return global_position + Vector3(0, 1.7 if boss != null else 0.4, 0)


func _snap_to_badge() -> void:
	# Glue the anchor to the 2D panel: unproject the panel's canvas
	# center onto the table plane (y=0).
	if badge == null or not is_instance_valid(badge):
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var center_canvas: Vector2 = badge.get_global_rect().get_center()
	var vp_pos: Vector2 = vp.get_canvas_transform() * center_canvas
	var origin: Vector3 = cam.project_ray_origin(vp_pos)
	var normal: Vector3 = cam.project_ray_normal(vp_pos)
	if absf(normal.y) > 0.0001:
		var t: float = -origin.y / normal.y
		if t > 0.0:
			position = origin + normal * t
			position.y = 0.0


# --- Compatibility + forwards (the board and director call these) ---

func set_far_side(_far: bool) -> void:
	pass  # the 2D portrait needs no flipping


func set_enemy_badge(hand_size: int, show: bool) -> void:
	if badge != null:
		badge.set_hand_count(hand_size, show)


func set_deck_count(n: int) -> void:
	if badge != null:
		badge.set_deck_count(n)


func set_mana(mana: int, max_mana: int) -> void:
	if badge != null:
		badge.set_mana(mana, max_mana)


func update_hp(hp: int) -> void:
	if badge != null:
		badge.set_hp(hp, 30)


func set_highlight(on: bool) -> void:
	if badge != null:
		badge.set_highlight(on)
	if _ring != null:
		_ring.visible = on


func is_highlighted() -> bool:
	return badge != null and badge.is_highlighted()


func punch_hp(duration: float) -> void:
	if badge != null:
		badge.punch_hp(duration)


func start_hero_damage(duration: float) -> void:
	if badge != null:
		badge.start_damage(duration)
	if boss != null and is_instance_valid(boss):
		boss.tween_param("flash", 0.8, 0.0, maxf(duration, 0.2))
		boss.knock(0.7)


func start_hero_heal(duration: float) -> void:
	if badge != null:
		badge.start_heal(duration)
	if boss != null and is_instance_valid(boss):
		FxLab.sparks(get_parent(), global_position + Vector3(0, 0.3, 0), Color(0.35, 1.0, 0.5), 34, 2.6, 0.97)


func start_hero_death(duration: float) -> void:
	if badge != null:
		badge.start_death(duration)
	if boss != null and is_instance_valid(boss):
		# The Boss glitches (the full loss moment comes with the end screens).
		boss.tween_param("glitch", 0.0, 0.8, duration)


func pulse_deck(duration: float) -> void:
	if badge != null:
		badge.pulse_deck(duration)


func pop_mana_gems(mana: int, pop_time: float, stagger: float) -> void:
	if badge != null:
		badge.pop_mana_gems(mana, pop_time, stagger)
