extends PanelContainer
class_name HeroBadge

# Everdeck Sprint 1a.5 — the hero badge as a 2D overlay panel (enemy
# upper-left, mine lower-left), replacing the 3D badge's oversized piled
# Label3D text. Laid out with containers so nothing can overlap:
# circular portrait, HP bar with "28/30" inside it, mana crystals +
# "3/6", a deck icon + count, and (enemy only) a hand icon + count.
# The whole panel is the drop/snap target for the 2D targeting arrow
# (the 3D HeroPlaque3D anchor follows this panel's projected position,
# so pick raycasts, hero_position, and arrow snap all agree). It
# highlights red when targeted. All controls are MOUSE_FILTER_IGNORE so
# taps fall through to the 3D pick layer (the invisible Area3D follows
# the panel). The director's hero animation hooks live here now (2D).

const PANEL_W: float = 220.0
const PANEL_H: float = 110.0
const PORTRAIT_PX: int = 64
const HP_BAR_W: float = 132.0
const HP_BAR_H: float = 24.0
const MAX_HP: int = 30

# Fixed canvas positions (top-left of the panel).
const ENEMY_POS := Vector2(10, 75)
const MY_POS := Vector2(10, 407)

var player: int = 0
var class_id: String = ""

var _hp_fill: ColorRect = null
var _hp_label: Label = null
var _hp_bar: Control = null
var _mana_gems: Array = []  # [Panel]
var _mana_label: Label = null
var _deck_label: Label = null
var _deck_icon: Panel = null
var _hand_icon: Panel = null
var _hand_label: Label = null
var _hand_row: Control = null
var _style_normal: StyleBoxFlat = null
var _style_highlight: StyleBoxFlat = null
var _highlighted: bool = false
var _base_modulate: Color = Color.WHITE
# Step 2: the deck's themed mana counter (dynamite, cookies, candles...).
# It replaces the plain gem dots; the "3/6" label stays in the panel.
var counter: ManaCounter = null
var _is_mine: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	_style_normal = _pill_style(Color(0.05, 0.04, 0.08, 0.85), Color(1, 1, 1, 0.0), 0)
	_style_highlight = _pill_style(Color(0.05, 0.04, 0.08, 0.85), Color(1.0, 0.15, 0.15), 4)
	add_theme_stylebox_override("panel", _style_normal)


func _pill_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_right = border_w
	sb.border_width_top = border_w
	sb.border_width_bottom = border_w
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func setup(player_idx: int, hero_class: String) -> void:
	player = player_idx
	class_id = hero_class
	# Rebuild (setup may run again on a reused panel).
	for c in get_children():
		c.queue_free()
	_mana_gems = []
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)
	hbox.add_child(_make_portrait(hero_class))
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)
	vbox.add_child(_make_hp_bar())
	vbox.add_child(_make_mana_row())
	vbox.add_child(_make_deck_row())
	counter = ManaCounter.new()
	counter.name = "ManaCounter"
	add_child(counter)
	counter.setup(hero_class, 26.0 if _is_mine else 20.0)
	_mana_label.visible = false  # the counter shows the numbers


func _process(_delta: float) -> void:
	# The counter rides with the panel: under mine, beside the enemy's.
	if counter != null:
		counter.global_position = global_position + (Vector2(0, PANEL_H + 8) if _is_mine else Vector2(PANEL_W + 10, 8))


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _make_portrait(hero_class: String) -> TextureRect:
	# Circular portrait: the existing CardArt rendered once into a
	# SubViewport, shown through a circular canvas_item mask.
	var vp := SubViewport.new()
	vp.name = "PortraitVP"
	vp.size = Vector2i(128, 128)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.handle_input_locally = false
	var art := CardArt.new()
	art.art_id = str(CardView.CLASS_ART.get(hero_class, "token"))
	art.size = Vector2(128, 128)
	art.position = Vector2.ZERO
	vp.add_child(art)
	add_child(vp)  # not in the layout; just hosts the texture
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture = vp.get_texture()
	tr.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 d = UV - vec2(0.5);\n\tif (length(d) > 0.5) { discard; }\n\tCOLOR = texture(TEXTURE, UV);\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	tr.material = sm
	return tr


func _make_hp_bar() -> Control:
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(HP_BAR_W, HP_BAR_H)
	var track := ColorRect.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.color = Color(0.12, 0.08, 0.08)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	_hp_fill = ColorRect.new()
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.color = Color(0.85, 0.12, 0.18)
	_hp_fill.anchor_top = 0.0
	_hp_fill.anchor_bottom = 1.0
	_hp_fill.anchor_left = 0.0
	_hp_fill.anchor_right = 0.0
	_hp_fill.offset_left = 0.0
	_hp_fill.offset_right = HP_BAR_W
	_hp_fill.offset_top = 0.0
	_hp_fill.offset_bottom = 0.0
	bar.add_child(_hp_fill)
	_hp_label = _mk_label("30/30", 15)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_hp_label)
	_hp_bar = bar
	return bar


func _mk_label(text: String, fs: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _gem(color: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 999
	sb.corner_radius_top_right = 999
	sb.corner_radius_bottom_left = 999
	sb.corner_radius_bottom_right = 999
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_mana_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	for _i in 10:
		var g := _gem(Color(1.0, 0.8, 0.15))
		row.add_child(g)
		_mana_gems.append(g)
	_mana_label = _mk_label("0/0", 14)
	row.add_child(_mana_label)
	return row


func _card_icon(bg: Color = Color(0.35, 0.15, 0.55)) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(16, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.border_color = Color(0.85, 0.65, 0.15)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	return p


# Sprint 1c: the two card icons get tiny "Deck" / "Hand" captions and
# distinct icon colors (deck purple, hand teal) — the identical purple
# icons were unreadable. Each icon block is a VBox: icon+count on top,
# caption below.
func _make_count_block(icon: Panel, caption_text: String, start_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	top.add_child(icon)
	var lab := _mk_label(start_text, 14)
	top.add_child(lab)
	box.add_child(top)
	var cap := _mk_label(caption_text, 11)
	cap.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(cap)
	box.set_meta("count_label", lab)
	return box


func _make_deck_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_deck_icon = _card_icon(Color(0.35, 0.15, 0.55))
	var deck_box := _make_count_block(_deck_icon, "Deck", "30")
	_deck_label = deck_box.get_meta("count_label") as Label
	row.add_child(deck_box)
	_hand_icon = _card_icon(Color(0.15, 0.45, 0.5))
	_hand_row = _make_count_block(_hand_icon, "Hand", "0")
	_hand_label = _hand_row.get_meta("count_label") as Label
	_hand_row.visible = false
	row.add_child(_hand_row)
	return row


# --- Position / state ---

func set_side(is_mine: bool) -> void:
	position = MY_POS if is_mine else ENEMY_POS
	if is_mine != _is_mine:
		_is_mine = is_mine
		if counter != null:
			counter.setup(class_id, 26.0 if is_mine else 20.0)
			counter.set_mana(counter.mana, counter.max_mana)


func set_hp(hp: int, max_hp: int = MAX_HP) -> void:
	var frac: float = clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	if _hp_fill != null:
		_hp_fill.offset_right = HP_BAR_W * frac
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [hp, max_hp]


func set_mana(mana: int, max_mana: int) -> void:
	if counter != null:
		counter.set_mana(mana, max_mana)
	for i in _mana_gems.size():
		var g: Panel = _mana_gems[i]
		g.visible = i < max_mana and counter == null
		if i < max_mana:
			var sb := g.get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null:
				sb.bg_color = Color(1.0, 0.8, 0.15) if i < mana else Color(0.25, 0.25, 0.3)
	if _mana_label != null:
		_mana_label.text = "%d/%d" % [mana, max_mana]


func set_deck_count(n: int) -> void:
	if _deck_label != null:
		_deck_label.text = "%d" % n


# Sprint 1c: 2D floating text ON the panel (hero damage/heal floaters).
# The old 3D Label3D at the left-edge anchor could rise off-screen; the
# panel is always on-screen, so the floater is too. Returns the label
# (tests assert its position is inside the viewport).
func float_text(text: String, color: Color) -> Label:
	var l := _mk_label(text, 30)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(140, 40)
	l.z_index = 60
	var parent: Control = get_parent() as Control
	if parent != null:
		l.position = position + Vector2(40, 6)
		parent.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "position:y", l.position.y - 52.0, 0.7).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
		tw.tween_callback(l.queue_free)
	return l


func set_hand_count(n: int, show: bool) -> void:
	if _hand_row != null:
		_hand_row.visible = show
	if _hand_label != null:
		_hand_label.text = "%d" % n


func set_highlight(on: bool) -> void:
	_highlighted = on
	add_theme_stylebox_override("panel", _style_highlight if on else _style_normal)


func is_highlighted() -> bool:
	return _highlighted


# --- Director animation hooks (2D) ---

func punch_hp(duration: float) -> void:
	if _hp_bar == null:
		return
	_hp_bar.pivot_offset = _hp_bar.size / 2.0
	_hp_bar.scale = Vector2(1.3, 1.3)
	var tw := _hp_bar.create_tween()
	tw.tween_property(_hp_bar, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _shake_panel(duration: float, amplitude: float) -> void:
	var base: Vector2 = position
	var step: float = duration / 4.0
	var tw := create_tween()
	tw.tween_property(self, "position", base + Vector2(amplitude, 0), step).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", base + Vector2(-amplitude, 0), step).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", base + Vector2(amplitude * 0.5, 0), step).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", base, step).set_ease(Tween.EASE_OUT)


func _flash_bar(color: Color, duration: float) -> void:
	if _hp_fill == null:
		return
	var tw := create_tween()
	tw.tween_property(_hp_fill, "color", color, duration * 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hp_fill, "color", Color(0.85, 0.12, 0.18), duration * 0.75).set_ease(Tween.EASE_IN)


func start_damage(duration: float) -> void:
	_shake_panel(duration, 9.0)
	_flash_bar(Color(1.0, 0.3, 0.3), duration)
	punch_hp(duration)


func start_heal(duration: float) -> void:
	_flash_bar(Color(0.3, 1.0, 0.4), duration)
	punch_hp(duration)


func start_death(duration: float) -> void:
	_shake_panel(duration, 18.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.35, 0.3, 0.3), duration).set_ease(Tween.EASE_IN)


func pulse_deck(duration: float) -> void:
	if _deck_icon == null:
		return
	_deck_icon.pivot_offset = _deck_icon.size / 2.0
	_deck_icon.scale = Vector2(1.5, 1.5)
	var tw := _deck_icon.create_tween()
	tw.tween_property(_deck_icon, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func pop_mana_gems(mana: int, pop_time: float, stagger: float) -> void:
	if counter != null:
		counter.pop(mana, pop_time, stagger)
	for i in mini(mana, _mana_gems.size()):
		var g: Panel = _mana_gems[i]
		g.visible = counter == null
		g.pivot_offset = g.size / 2.0
		g.scale = Vector2(1.6, 1.6)
		var tw := g.create_tween()
		tw.tween_property(g, "scale", Vector2.ONE, pop_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(i * stagger)
