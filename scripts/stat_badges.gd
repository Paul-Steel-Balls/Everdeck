extends Control
class_name StatBadges

# Everdeck Sprint 1a.4 — minion stat numbers as 2D overlay badges, pinned
# each frame to the token's projected screen position
# (camera.unproject_position). Attack bottom-left, health bottom-right,
# using the SAME red/green oval badges as the hand cards. The number sits
# INSIDE its badge, bold, sized to the badge (never bigger); the badge is
# about 30% of the token's on-screen width. Damaged health shows a darker
# red with a white number; buffed stats show a gold outline. Badges hide
# when the token is off-screen or during a death animation. This replaces
# the 3D stat discs + Label3D numbers (too big, overlapped neighbors, hid
# behind discs at some angles).

# Chip style (same family as the arrow's outcome chips): a deep fill, a
# light rim in the same hue, a white display-font number with a thick ink
# outline, and a soft drop shadow.
const ATK_BG := Color(0.66, 0.36, 0.02)
const ATK_RIM := Color(1.0, 0.84, 0.45)
const HP_BG := Color(0.07, 0.44, 0.18)
const HP_RIM := Color(0.72, 1.0, 0.76)
const HP_HURT_BG := Color(0.6, 0.05, 0.09)   # damaged: red
const HP_HURT_RIM := Color(1.0, 0.82, 0.82)
const GOLD_OUTLINE := Color(1.0, 0.86, 0.2)  # buffed: thick gold rim
# (Sprint 1a.5: the visual token radius comes from
# Board3D.token_visual_radius(), not a local const.)

var _board: Board3D = null
var _badges: Dictionary = {}  # uid -> {"atk": PanelContainer, "hp": PanelContainer, "atk_l": Label, "hp_l": Label}
var _flash: Dictionary = {}  # uid -> Color (transient hp badge color)


func set_board(board: Board3D) -> void:
	_board = board


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _badge_pair() -> Dictionary:
	var atk := PanelContainer.new()
	atk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atk_l := _badge_label()
	atk.add_child(atk_l)
	var hp := PanelContainer.new()
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_l := _badge_label()
	hp.add_child(hp_l)
	add_child(atk)
	add_child(hp)
	return {"atk": atk, "hp": hp, "atk_l": atk_l, "hp_l": hp_l}


func _badge_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UIKit.font(UIKit.FONT_DISPLAY_PATH))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", UIKit.INK)
	l.add_theme_constant_override("outline_size", 7)
	return l


func _style_badge(p: PanelContainer, bg: Color, outline: Color, buffed: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.border_color = outline
	sb.set_border_width_all(3 if buffed else 2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)


func _process(_delta: float) -> void:
	if _board == null or not is_instance_valid(_board):
		return
	var seen: Dictionary = {}
	for uid in _board.board_uids():
		seen[uid] = true
		var node: Minion3D = _board.minion_node(uid)
		if node == null:
			continue
		if not _badges.has(uid):
			_badges[uid] = _badge_pair()
			node.badge_link = self
		_update_badge(uid, node)
	# Drop badges for vanished uids.
	var dead: Array = []
	for uid in _badges.keys():
		if not seen.has(uid):
			dead.append(uid)
	for uid in dead:
		var pair: Dictionary = _badges[uid]
		(pair["atk"] as Control).queue_free()
		(pair["hp"] as Control).queue_free()
		_badges.erase(uid)
		_flash.erase(uid)


func _update_badge(uid: int, node: Minion3D) -> void:
	var pair: Dictionary = _badges[uid]
	var atk: PanelContainer = pair["atk"]
	var hp: PanelContainer = pair["hp"]
	# Hidden while the token dies.
	if node.dying:
		atk.visible = false
		hp.visible = false
		return
	var cam: Camera3D = _board.get_node("MatchCamera") as Camera3D
	if cam == null or cam.is_position_behind(node.position):
		atk.visible = false
		hp.visible = false
		return
	var vp_pos: Vector2 = _board.screen_pos(node.position)
	var canvas_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * vp_pos
	# Token on-screen radius: project a point one visual radius to the
	# side. Sprint 1a.5: the radius comes from the board (it shrank).
	var r_world: float = _board.token_visual_radius()
	var edge_vp: Vector2 = _board.screen_pos(node.position + Vector3(r_world, 0, 0))
	var edge_canvas: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * edge_vp
	var radius: float = maxf(canvas_pos.distance_to(edge_canvas), 4.0)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# Off-screen (with a small margin): hide.
	if vp_pos.x < -radius or vp_pos.x > vp_size.x + radius or vp_pos.y < -radius or vp_pos.y > vp_size.y + radius:
		atk.visible = false
		hp.visible = false
		return
	# Step 2: a standing 3D model leaves room for bigger, readable badges
	# (~40% of the footprint's width), set at its feet.
	var badge_d: float = radius * 2.0 * 0.40
	var atk_l: Label = pair["atk_l"]
	var hp_l: Label = pair["hp_l"]
	atk_l.text = "%d" % node.cur_atk
	hp_l.text = "%d" % node.cur_hp
	var fs: int = maxi(int(badge_d * 0.5), 10)
	atk_l.add_theme_font_size_override("font_size", fs)
	hp_l.add_theme_font_size_override("font_size", fs)
	# Colors: damaged health = darker red + white number; buffed stat =
	# gold outline. A transient flash color (heal) overrides.
	var atk_buff: bool = node.cur_atk > node.base_atk
	var atk_outline: Color = GOLD_OUTLINE if atk_buff else ATK_RIM
	var hp_bg: Color = HP_BG
	var hp_rim: Color = HP_RIM
	if node.cur_hp < node.max_hp:
		hp_bg = HP_HURT_BG
		hp_rim = HP_HURT_RIM
	if _flash.has(uid):
		hp_bg = _flash[uid]
	var hp_buff: bool = node.cur_hp > node.base_hp
	var hp_outline: Color = GOLD_OUTLINE if hp_buff else hp_rim
	_style_badge(atk, ATK_BG, atk_outline, atk_buff)
	_style_badge(hp, hp_bg, hp_outline, hp_buff)
	for b in [atk, hp]:
		(b as PanelContainer).custom_minimum_size = Vector2(badge_d, badge_d * 0.78)
		(b as Control).size = Vector2(badge_d, badge_d * 0.78)
	# Bottom-left / bottom-right of the token. Sprint 1a.5: x-offset is
	# +/-0.70r (badge outer edge lands exactly at the token's visual
	# radius), so adjacent tokens' badges can't overlap.
	atk.position = canvas_pos + Vector2(-radius * 0.58 - badge_d / 2.0, radius * 0.30 - badge_d * 0.39)
	hp.position = canvas_pos + Vector2(radius * 0.58 - badge_d / 2.0, radius * 0.30 - badge_d * 0.39)
	atk.visible = true
	hp.visible = true
	atk.z_index = 60
	hp.z_index = 60


# --- Director entry points (called via Minion3D forwarders) ---

func punch_badges(uid: int, which: String, duration: float) -> void:
	if not _badges.has(uid):
		return
	var pair: Dictionary = _badges[uid]
	var targets: Array = []
	if which == "hp" or which == "both":
		targets.append(pair["hp"])
	if which == "both":
		targets.append(pair["atk"])
	for b in targets:
		var c: Control = b
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(1.5, 1.5)
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func spin_badges(uid: int, duration: float) -> void:
	if not _badges.has(uid):
		return
	var pair: Dictionary = _badges[uid]
	for b in [pair["atk"], pair["hp"]]:
		var c: Control = b
		c.pivot_offset = c.size / 2.0
		c.rotation = 0.0
		var tw := c.create_tween()
		tw.tween_property(c, "rotation", PI, duration).set_ease(Tween.EASE_IN_OUT)
		tw.finished.connect(func() -> void: c.rotation = 0.0)


func flash_hp_badge(uid: int, color: Color) -> void:
	_flash[uid] = color


func clear_flash(uid: int) -> void:
	_flash.erase(uid)
