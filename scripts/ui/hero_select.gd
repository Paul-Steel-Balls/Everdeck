extends Control
class_name HeroSelect

# Hero select (vs Computer). Big animated hero on the left with their
# line in a speech bubble, details on the right (title, play-style bars,
# Signature Move), the six heroes as hexagon buttons along the bottom,
# an opponent picker, and LOCK IN. After LOCK IN the player chooses a
# ready-made deck or builds their own.

signal back_pressed
signal start_quick(hero: String, opponent: String)
signal start_build(hero: String, opponent: String)

const HEROES: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
const OPPONENTS: Array = ["random", "grunk", "agatha", "presto", "barnacle", "reginald", "larry"]

var selected: String = ""
var _opp_idx: int = 0
var _t: float = 0.0

var _bg_mat: ShaderMaterial
var _smoke: Color = Color(0.24, 0.08, 0.36)
var _ember: Color = Color(0.75, 0.24, 0.04)
var _glow: Control
var _stage: Control
var _portrait: TextureRect
var _old_portrait: TextureRect
var _bubble: SpeechBubble
var _quote: Label
var _name: Label
var _title: Label
var _bars: Dictionary = {}
var _sig_panel: PanelContainer
var _sig_name: Label
var _sig_text: Label
var _opp_label: Label
var _hexes: Dictionary = {}
var _lock: Button
var _embers: GPUParticles2D
var _overlay: Control
var buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bg()
	_build_stage()
	_build_header()
	_build_info()
	_build_roster()
	_select(HEROES[randi() % HEROES.size()], true)


func _process(delta: float) -> void:
	_t += delta
	if _portrait != null:
		# Idle: a slow bob, a breath, and a tiny sway.
		_portrait.position.y = sin(_t * 1.3) * 6.0
		var b: float = 1.0 + sin(_t * 2.1) * 0.01
		_portrait.scale = Vector2(b, b)
		_portrait.rotation = sin(_t * 0.8) * 0.006
	if _glow != null:
		_glow.queue_redraw()


# --- Background ---

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://shaders/nebula.gdshader")
	bg.material = _bg_mat
	add_child(bg)


func _tint_bg(col: Color) -> void:
	var from_s: Color = _smoke
	var from_e: Color = _ember
	var to_s: Color = col.darkened(0.62)
	var to_e: Color = col.darkened(0.25)
	_smoke = to_s
	_ember = to_e
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(c: Color) -> void: _bg_mat.set_shader_parameter("smoke_color", c), from_s, to_s, 0.6)
	tw.tween_method(func(c: Color) -> void: _bg_mat.set_shader_parameter("ember_color", c), from_e, to_e, 0.6)


# --- Hero stage (left) ---

func _build_stage() -> void:
	_glow = Control.new()
	_glow.name = "Glow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.position = Vector2(0, 0)
	_glow.size = Vector2(640, 720)
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.position = Vector2(30, -10)
	_stage.size = Vector2(580, 864)
	add_child(_stage)
	_embers = UIKit.embers(Vector2(600, 720), 70)
	_embers.position = Vector2(320, 730)
	add_child(_embers)


func _new_portrait(cls: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture = UIKit.hero_texture(cls)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = _stage.size
	tr.pivot_offset = Vector2(_stage.size.x * 0.5, _stage.size.y * 0.4)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hero_fade.gdshader")
	m.set_shader_parameter("fade_left", 0.12)
	m.set_shader_parameter("fade_bottom", 0.3)
	m.set_shader_parameter("rim_color", UIKit.CLASS_COLOR[cls])
	tr.material = m
	_stage.add_child(tr)
	return tr


func _draw_glow() -> void:
	if selected == "":
		return
	var col: Color = UIKit.CLASS_COLOR[selected]
	var pulse: float = 0.85 + 0.15 * sin(_t * 2.0)
	var c := Vector2(320, 330)
	for i in range(14, 0, -1):
		var r: float = 30.0 * i * pulse
		_glow.draw_circle(c, r, Color(col.r, col.g, col.b, 0.028))


func _mouth_point() -> Vector2:
	if _portrait == null or _portrait.texture == null:
		return Vector2(400, 300)
	var ts: Vector2 = _portrait.texture.get_size()
	var sc: float = min(_portrait.size.x / ts.x, _portrait.size.y / ts.y)
	var drawn: Vector2 = ts * sc
	var off: Vector2 = (_portrait.size - drawn) * 0.5
	var uv: Vector2 = UIKit.HERO_MOUTH.get(selected, Vector2(0.5, 0.4))
	return get_global_transform().affine_inverse() * (_portrait.get_global_transform() * (off + uv * drawn))


func _track_mouth() -> void:
	if _bubble == null or selected == "":
		return
	var mouth: Vector2 = _mouth_point()
	# Bubble up and to the right of the mouth (the info panel is on the
	# right, the screen edge on the left), tail reaching down-left.
	var p := Vector2(mouth.x + 70.0, mouth.y - _bubble.size.y - 70.0)
	p.x = clamp(p.x, 20.0, 640.0 - _bubble.size.x)
	p.y = max(p.y, 70.0)
	_bubble.position = p
	_bubble.set_target(mouth)


# --- Header ---

func _build_header() -> void:
	var back := UIKit.button("BACK", UIKit.BTN_PURPLE, 20, Vector2(130, 48))
	back.name = "Back"
	back.position = Vector2(20, 16)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)
	buttons["back"] = back
	var h := UIKit.label("CHOOSE YOUR BOSS", 30, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 8)
	h.position = Vector2(680, 18)
	add_child(h)
	UIKit.enter(h, Vector2(0, -30), 0.05)


# --- Info panel (right) ---

func _build_info() -> void:
	_name = UIKit.label("", 60, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 12)
	_name.position = Vector2(676, 64)
	add_child(_name)
	_title = UIKit.label("", 26, Color.WHITE, UIKit.FONT_BODY_PATH, 6)
	_title.position = Vector2(684, 140)
	add_child(_title)
	_quote = UIKit.label("", 19, Color(1, 1, 1, 0.82), "res://fonts/Inter-SemiBold.otf", 4)
	_quote.position = Vector2(686, 176)
	add_child(_quote)
	var y: float = 214.0
	for stat in ["Aggression", "Defense", "Chaos"]:
		var l := UIKit.label(stat.to_upper(), 18, Color(1, 1, 1, 0.9), UIKit.FONT_DISPLAY_PATH, 5)
		l.position = Vector2(684, y + 2)
		add_child(l)
		var pips: Array = []
		for i in 5:
			var pip := Panel.new()
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pip.position = Vector2(870 + i * 52, y)
			pip.size = Vector2(44, 26)
			pip.pivot_offset = pip.size * 0.5
			add_child(pip)
			pips.append(pip)
		_bars[stat] = pips
		y += 40.0
	# Signature Move: a comic panel.
	_sig_panel = PanelContainer.new()
	_sig_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sig_panel.position = Vector2(680, 340)
	_sig_panel.custom_minimum_size = Vector2(540, 0)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	var hdr := UIKit.label("SIGNATURE MOVE  ·  2 MANA", 16, UIKit.INK, UIKit.FONT_DISPLAY_PATH)
	hdr.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	v.add_child(hdr)
	_sig_name = UIKit.label("", 28, UIKit.INK, "res://fonts/Inter-Black.otf")
	_sig_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	v.add_child(_sig_name)
	_sig_text = UIKit.label("", 21, Color(0.15, 0.1, 0.2), UIKit.FONT_BODY_PATH)
	_sig_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_sig_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sig_text)
	_sig_panel.add_child(v)
	add_child(_sig_panel)
	# Opponent picker.
	var opp_row := HBoxContainer.new()
	opp_row.position = Vector2(680, 488)
	opp_row.add_theme_constant_override("separation", 10)
	var ol := UIKit.label("OPPONENT", 20, Color(1, 1, 1, 0.85), UIKit.FONT_DISPLAY_PATH, 5)
	ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opp_row.add_child(ol)
	var prev := UIKit.button("<", UIKit.BTN_BLUE, 22, Vector2(52, 46))
	prev.pressed.connect(func() -> void: _cycle_opp(-1))
	opp_row.add_child(prev)
	_opp_label = UIKit.label("", 22, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 6)
	_opp_label.custom_minimum_size = Vector2(250, 0)
	_opp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opp_row.add_child(_opp_label)
	var nxt := UIKit.button(">", UIKit.BTN_BLUE, 22, Vector2(52, 46))
	nxt.pressed.connect(func() -> void: _cycle_opp(1))
	opp_row.add_child(nxt)
	add_child(opp_row)
	buttons["opp_prev"] = prev
	buttons["opp_next"] = nxt
	_update_opp()
	_lock = UIKit.button("LOCK IN!", Color(0.95, 0.62, 0.08), 40, Vector2(330, 84), true)
	_lock.name = "LockIn"
	_lock.position = Vector2(900, 600)
	_lock.pressed.connect(_on_lock)
	add_child(_lock)
	buttons["lock"] = _lock


func _cycle_opp(d: int) -> void:
	_opp_idx = (_opp_idx + d + OPPONENTS.size()) % OPPONENTS.size()
	_update_opp()
	var tw := _opp_label.create_tween()
	_opp_label.pivot_offset = _opp_label.size * 0.5
	_opp_label.scale = Vector2(1.25, 1.25)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_opp_label, "scale", Vector2.ONE, 0.25)


func _update_opp() -> void:
	var o: String = OPPONENTS[_opp_idx]
	if o == "random":
		_opp_label.text = "RANDOM"
		_opp_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		_opp_label.text = CardDB.class_display_name(o).to_upper()
		_opp_label.add_theme_color_override("font_color", UIKit.CLASS_COLOR[o].lightened(0.2))


func opponent() -> String:
	var o: String = OPPONENTS[_opp_idx]
	if o == "random":
		return HEROES[randi() % HEROES.size()]
	return o


# --- Roster (bottom-left) ---

func _build_roster() -> void:
	var row := HBoxContainer.new()
	row.name = "Roster"
	row.position = Vector2(14, 588)
	row.add_theme_constant_override("separation", -8)
	add_child(row)
	var d: float = 0.15
	for cls in HEROES:
		var hx := HexPortrait.new()
		hx.setup(cls)
		hx.name = "Hex_" + cls
		hx.picked.connect(func(c: String) -> void: _select(c, false))
		row.add_child(hx)
		_hexes[cls] = hx
		hx.modulate.a = 0.0
		var tw := hx.create_tween()
		tw.tween_interval(d)
		tw.tween_property(hx, "modulate:a", 1.0, 0.25)
		d += 0.06


# --- Selection ---

func _select(cls: String, instant: bool) -> void:
	if cls == selected and not instant:
		return
	selected = cls
	var col: Color = UIKit.CLASS_COLOR[cls]
	for k in _hexes:
		_hexes[k].set_selected(k == cls)
	_tint_bg(col)
	# Portrait: old one slides out left and fades, new one pops in.
	if _portrait != null:
		_old_portrait = _portrait
		var to := _old_portrait.create_tween().set_parallel(true)
		to.tween_property(_old_portrait, "modulate:a", 0.0, 0.25)
		to.tween_property(_old_portrait, "position:x", -80.0, 0.3)
		to.chain().tween_callback(_old_portrait.queue_free)
	_portrait = _new_portrait(cls)
	_portrait.modulate = Color(2.2, 2.2, 2.2, 0.0)
	_portrait.position.x = 90.0
	var tn := _portrait.create_tween().set_parallel(true)
	tn.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tn.tween_property(_portrait, "modulate", Color(1, 1, 1, 1), 0.45)
	tn.tween_property(_portrait, "position:x", 0.0, 0.4)
	# Text.
	var info: Dictionary = UIKit.HERO_INFO[cls]
	_name.text = CardDB.class_display_name(cls).to_upper()
	_name.add_theme_font_size_override("font_size", 60 if _name.text.length() <= 10 else 46)
	_title.text = str(info["title"])
	_title.add_theme_color_override("font_color", col.lightened(0.25))
	_quote.text = "\u201c%s\u201d" % str(info["line"])
	for l: Control in [_name, _title, _quote]:
		l.modulate.a = 0.0
		var tl: Tween = l.create_tween()
		tl.tween_property(l, "modulate:a", 1.0, 0.3)
	# Play-style pips fill one by one.
	var style: Dictionary = UIKit.HERO_STYLE[cls]
	var delay: float = 0.1
	for stat in _bars:
		var n: int = int(style[stat])
		for i in 5:
			var pip: Panel = _bars[stat][i]
			pip.add_theme_stylebox_override("panel", _pip_style(col if i < n else Color(1, 1, 1, 0.12), i < n))
			if i < n:
				pip.scale = Vector2(0.2, 0.2)
				var tp := pip.create_tween()
				tp.tween_interval(delay + i * 0.05)
				tp.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tp.tween_property(pip, "scale", Vector2.ONE, 0.25)
		delay += 0.08
	# Signature Move panel.
	var hp: Dictionary = CardDB.hero_power_for(cls)
	_sig_name.text = str(hp.get("name", ""))
	_sig_text.text = str(hp.get("text", ""))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1).lerp(col, 0.14)
	sb.border_color = UIKit.INK
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(7, 8)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_sig_panel.add_theme_stylebox_override("panel", sb)
	_sig_panel.pivot_offset = Vector2(40, 40)
	_sig_panel.rotation = -0.03
	var ts := _sig_panel.create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	ts.tween_property(_sig_panel, "rotation", -0.012, 0.6)
	# Embers take the class color.
	var pm: ParticleProcessMaterial = _embers.process_material
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.15, col.lightened(0.5))
	ramp.set_color(ramp.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt


func _pip_style(c: Color, filled: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.skew = Vector2(0.2, 0)
	sb.border_color = UIKit.INK if filled else Color(1, 1, 1, 0.2)
	sb.set_border_width_all(3)
	return sb


# --- Lock in -> deck choice ---

func _on_lock() -> void:
	if _overlay != null:
		return
	_overlay = Control.new()
	_overlay.name = "DeckChoice"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var col: Color = UIKit.CLASS_COLOR[selected]
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.07, 0.03, 0.12, 0.96)
	psb.border_color = col
	psb.set_border_width_all(5)
	psb.set_corner_radius_all(26)
	psb.shadow_color = Color(col.r, col.g, col.b, 0.35)
	psb.shadow_size = 30
	psb.content_margin_left = 50
	psb.content_margin_right = 50
	psb.content_margin_top = 34
	psb.content_margin_bottom = 34
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 0)
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	var q := UIKit.label("PICK YOUR DECK", 44, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 10)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	var sub := UIKit.label("%s is ready. How do you want to fight?" % CardDB.class_display_name(selected), 22, col.lightened(0.3), UIKit.FONT_BODY_PATH, 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var quick := UIKit.button("READY-MADE DECK", UIKit.BTN_GREEN, 34, Vector2(560, 86), true)
	quick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quick.pressed.connect(func() -> void: start_quick.emit(selected, opponent()))
	box.add_child(quick)
	var build := UIKit.button("BUILD MY OWN", UIKit.BTN_BLUE, 30, Vector2(480, 74))
	build.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	build.pressed.connect(func() -> void: start_build.emit(selected, opponent()))
	box.add_child(build)
	var cancel := UIKit.button("CANCEL", UIKit.BTN_PURPLE, 20, Vector2(200, 50))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void:
		_overlay.queue_free()
		_overlay = null)
	box.add_child(cancel)
	buttons["quick"] = quick
	buttons["build"] = build
	buttons["cancel"] = cancel
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.7, 0.7)
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	var tw := panel.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.3)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
