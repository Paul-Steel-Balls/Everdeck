extends Control
class_name TitleScreen

# Animated main menu. Layout follows Ian's Grok mockup (logo + tagline +
# stacked buttons on the left, a hero on the right) with motion everywhere:
# churning smoke, rising embers, a floating logo with a shine sweep,
# buttons that slide in and react to the mouse, and the six heroes taking
# turns in the showcase with their own line.

signal play_pressed
signal online_pressed
signal export_pressed
signal quit_pressed
signal lab_pressed

const HERO_ORDER: Array = ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
const HERO_HOLD_S: float = 6.5
const VIEW := Vector2(1280, 720)

# Mouth points live in UIKit.HERO_MOUTH (shared with hero select).
const MOUTH: Dictionary = UIKit.HERO_MOUTH
# Keep the bubble clear of the button column.
const BUBBLE_MIN_X: float = 515.0

var _hero_rects: Array = []  # two TextureRects we crossfade between
var _hero_idx: int = 0
var _front: int = 0
var _hero_name: Label
var _hero_title: Label
var _bubble: SpeechBubble
var _logo: Control
var _status: Label
var _timer: float = 0.0
var _t: float = 0.0
var buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_hero_showcase()
	_build_left_column()
	_build_footer()
	_show_hero(0, true)


func _process(delta: float) -> void:
	_t += delta
	_timer += delta
	if _timer >= HERO_HOLD_S:
		_timer = 0.0
		_show_hero((_hero_idx + 1) % HERO_ORDER.size(), false)
	if _logo != null:
		_logo.position.y = _logo.get_meta("base_y", _logo.position.y) + sin(_t * 1.6) * 5.0
		_logo.rotation = sin(_t * 0.9) * 0.008
	# Slow Ken Burns push on the front hero.
	var fr: TextureRect = _hero_rects[_front]
	var k: float = clamp(_timer / HERO_HOLD_S, 0.0, 1.0)
	fr.scale = Vector2.ONE * (1.0 + 0.045 * k)
	_track_mouth()


# Screen point (in this control's space) of the current hero's mouth.
func _mouth_point() -> Vector2:
	var tr: TextureRect = _hero_rects[_front]
	if tr.texture == null:
		return Vector2(900, 300)
	var ts: Vector2 = tr.texture.get_size()
	var sc: float = min(tr.size.x / ts.x, tr.size.y / ts.y)
	var drawn: Vector2 = ts * sc
	var off: Vector2 = (tr.size - drawn) * 0.5
	var uv: Vector2 = MOUTH.get(HERO_ORDER[_hero_idx], Vector2(0.5, 0.4))
	var local: Vector2 = off + uv * drawn
	return get_global_transform().affine_inverse() * (tr.get_global_transform() * local)


func _track_mouth() -> void:
	if _bubble == null:
		return
	var mouth: Vector2 = _mouth_point()
	# Bubble sits to the left of the face, a little above the mouth; the
	# tail reaches right to the corner of the mouth.
	var p := Vector2(mouth.x - _bubble.size.x - 95.0, mouth.y - _bubble.size.y * 0.5 - 45.0)
	p.x = max(p.x, BUBBLE_MIN_X)
	p.y = max(p.y, 300.0)  # stay below the tagline
	_bubble.position = p
	_bubble.set_target(mouth)


# --- Building ---

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/nebula.gdshader")
	bg.material = m
	add_child(bg)


func _build_hero_showcase() -> void:
	var holder := Control.new()
	holder.name = "HeroShowcase"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -720
	holder.offset_right = 0
	add_child(holder)
	for i in 2:
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Taller than the screen so the head and shoulders fill the right
		# side; the lower body runs off the bottom edge.
		tr.offset_top = -10
		tr.offset_bottom = 300
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/hero_fade.gdshader")
		tr.material = m
		tr.modulate.a = 0.0
		holder.add_child(tr)
		tr.resized.connect(func() -> void: tr.pivot_offset = Vector2(tr.size.x * 0.6, tr.size.y * 0.35))
		_hero_rects.append(tr)
	# Embers in front of the hero, behind the UI.
	var em := UIKit.embers(VIEW, 110)
	em.name = "Embers"
	add_child(em)
	# Name plate + speech bubble, bottom right.
	var plate := VBoxContainer.new()
	plate.name = "HeroPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.anchor_left = 1.0
	plate.anchor_right = 1.0
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.offset_left = -560
	plate.offset_right = -40
	plate.offset_top = -150
	plate.offset_bottom = -30
	plate.alignment = BoxContainer.ALIGNMENT_END
	plate.add_theme_constant_override("separation", 0)
	_hero_name = UIKit.label("", 54, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 12)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hero_title = UIKit.label("", 22, UIKit.GOLD, UIKit.FONT_BODY_PATH, 6)
	_hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	plate.add_child(_hero_name)
	plate.add_child(_hero_title)
	add_child(plate)
	_bubble = SpeechBubble.new()
	_bubble.name = "Bubble"
	add_child(_bubble)


func _build_left_column() -> void:
	_logo = _make_logo("EVERDECK", 112)
	_logo.position = Vector2(70, 46)
	_logo.set_meta("base_y", 46.0)
	add_child(_logo)
	var tag1 := UIKit.label("One set. No rotation. No nerfs.", 26, Color.WHITE, UIKit.FONT_BODY_PATH, 6)
	tag1.position = Vector2(84, 212)
	add_child(tag1)
	var tag2 := UIKit.label("You hate how it is. You'd hate change more.", 26, Color(1, 0.88, 0.62), UIKit.FONT_BODY_PATH, 6)
	tag2.position = Vector2(84, 248)
	add_child(tag2)
	var col := VBoxContainer.new()
	col.name = "Buttons"
	col.position = Vector2(84, 318)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var specs: Array = [
		["play", "PLAY", UIKit.BTN_GREEN, 44, Vector2(400, 92), true],
		["online", "PLAY ONLINE", UIKit.BTN_BLUE, 32, Vector2(400, 74), false],
		["lab", "BATTLEFIELD PREVIEW", Color(0.85, 0.35, 0.65), 20, Vector2(340, 56), false],
		["quit", "QUIT", UIKit.BTN_PURPLE, 26, Vector2(260, 60), false],
	]
	for s in specs:
		var b := UIKit.button(s[1], s[2], s[3], s[4], s[5])
		b.name = "Btn_" + s[0]
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(b)
		buttons[s[0]] = b
	buttons["play"].pressed.connect(func() -> void: play_pressed.emit())
	buttons["online"].pressed.connect(func() -> void: online_pressed.emit())
	buttons["quit"].pressed.connect(func() -> void: quit_pressed.emit())
	buttons["lab"].pressed.connect(func() -> void: lab_pressed.emit())
	# The Battlefield Preview is a dev tool: release builds hide it.
	buttons["lab"].visible = OS.is_debug_build()
	# Entrance: logo drops in, tagline and buttons slide in one by one.
	UIKit.enter(_logo, Vector2(0, -60), 0.05, 0.6)
	UIKit.enter(tag1, Vector2(-40, 0), 0.25)
	UIKit.enter(tag2, Vector2(-40, 0), 0.32)
	var d := 0.42
	for k in ["play", "online", "lab", "quit"]:
		_enter_button(buttons[k], d)
		d += 0.09


func _enter_button(b: Control, delay: float) -> void:
	# Buttons live in a VBox (which owns their position), so animate the
	# visual offset via scale + fade instead of position.
	b.modulate.a = 0.0
	b.scale = Vector2(0.6, 0.6)
	var tw := b.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE, 0.4)
	tw.tween_property(b, "modulate:a", 1.0, 0.25)


func _build_footer() -> void:
	var exp := Button.new()
	exp.name = "ExportLog"
	exp.flat = true
	exp.focus_mode = Control.FOCUS_NONE
	exp.text = "Export match log"
	exp.add_theme_font_override("font", UIKit.font(UIKit.FONT_BODY_LIGHT_PATH))
	exp.add_theme_font_size_override("font_size", 15)
	exp.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	exp.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.9))
	exp.anchor_top = 1.0
	exp.anchor_bottom = 1.0
	exp.offset_left = 16
	exp.offset_top = -40
	exp.offset_right = 220
	exp.offset_bottom = -10
	exp.pressed.connect(func() -> void: export_pressed.emit())
	add_child(exp)
	buttons["export"] = exp
	var cred := Button.new()
	cred.name = "Credits"
	cred.flat = true
	cred.focus_mode = Control.FOCUS_NONE
	cred.text = "Credits"
	cred.add_theme_font_override("font", UIKit.font(UIKit.FONT_BODY_LIGHT_PATH))
	cred.add_theme_font_size_override("font_size", 15)
	cred.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	cred.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.9))
	cred.anchor_left = 1.0
	cred.anchor_right = 1.0
	cred.anchor_top = 1.0
	cred.anchor_bottom = 1.0
	cred.offset_left = -110
	cred.offset_right = -16
	cred.offset_top = -40
	cred.offset_bottom = -10
	cred.pressed.connect(_show_credits)
	add_child(cred)
	buttons["credits"] = cred
	_status = UIKit.label("", 15, Color(1, 1, 1, 0.7), UIKit.FONT_BODY_LIGHT_PATH)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 230
	_status.offset_top = -36
	add_child(_status)


func set_status(text: String) -> void:
	_status.text = text


func _make_logo(text: String, size: int) -> Control:
	var root := Control.new()
	root.name = "Logo"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Extrusion: stacked dark copies stepping down-right.
	for i in range(9, 0, -1):
		var ex := UIKit.label(text, size, Color(0.30, 0.09, 0.02).lerp(Color(0.12, 0.03, 0.02), i / 9.0), UIKit.FONT_DISPLAY_PATH)
		ex.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		ex.position = Vector2(i * 0.9, i * 1.1)
		root.add_child(ex)
	# Base: bright cream letters with a thick ink outline.
	var base := UIKit.label(text, size, Color(1, 0.97, 0.82), UIKit.FONT_DISPLAY_PATH, 16)
	base.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	root.add_child(base)
	# Face: inline cut on top in animated gold.
	var face := UIKit.label(text, size, Color.WHITE, UIKit.FONT_INLINE_PATH)
	face.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/logo.gdshader")
	face.material = m
	root.add_child(face)
	face.resized.connect(func() -> void: m.set_shader_parameter("label_size", face.size))
	return root


# --- Hero rotation ---

func _show_hero(idx: int, instant: bool) -> void:
	_hero_idx = idx
	var cls: String = HERO_ORDER[idx]
	var back: int = 1 - _front
	var tr_new: TextureRect = _hero_rects[back]
	var tr_old: TextureRect = _hero_rects[_front]
	tr_new.texture = UIKit.hero_texture(cls)
	(tr_new.material as ShaderMaterial).set_shader_parameter("rim_color", UIKit.CLASS_COLOR[cls])
	tr_new.scale = Vector2.ONE
	tr_new.position.x = 60.0
	_front = back
	tr_new.move_to_front()
	var dur: float = 0.0 if instant else 0.9
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(tr_new, "modulate:a", 1.0, max(dur, 0.6))
	tw.tween_property(tr_new, "position:x", 0.0, max(dur, 0.6) * 1.2)
	tw.tween_property(tr_old, "modulate:a", 0.0, max(dur, 0.01))
	# Name plate pops.
	var info: Dictionary = UIKit.HERO_INFO[cls]
	_hero_name.text = CardDB.class_display_name(cls).to_upper()
	_hero_name.add_theme_color_override("font_color", Color.WHITE)
	_hero_title.text = str(info["title"])
	_hero_title.add_theme_color_override("font_color", UIKit.CLASS_COLOR[cls].lightened(0.25))
	for l: Label in [_hero_name, _hero_title]:
		l.modulate.a = 0.0
		var t2: Tween = (l as Control).create_tween()
		t2.tween_interval(0.25 if not instant else 0.6)
		t2.tween_property(l, "modulate:a", 1.0, 0.35)
	# Speech bubble: pops in a beat after the hero arrives, wobbles once.
	var col: Color = UIKit.CLASS_COLOR[cls]
	_bubble.set_line(str(info["line"]), col)
	_bubble.scale = Vector2(0.2, 0.2)
	_bubble.modulate.a = 0.0
	_bubble.rotation = -0.1 if idx % 2 == 0 else 0.1
	var tb := _bubble.create_tween()
	tb.tween_interval(0.9 if not instant else 1.4)
	tb.set_parallel(true)
	tb.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tb.tween_property(_bubble, "scale", Vector2.ONE, 0.6)
	tb.tween_property(_bubble, "modulate:a", 1.0, 0.12)
	tb.tween_property(_bubble, "rotation", -0.025 if idx % 2 == 0 else 0.025, 0.6)
	tb.set_parallel(false)
	tb.tween_interval(HERO_HOLD_S - 2.6)
	tb.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tb.tween_property(_bubble, "scale", Vector2(0.3, 0.3), 0.22)
	tb.parallel().tween_property(_bubble, "modulate:a", 0.0, 0.22)


const CREDITS_TEXT: String = """[center][font_size=40][b]EVERDECK[/b][/font_size]

[b]Music[/b]
"Dreamy Flashback", "At Launch" and "Clash Defiant"
by Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/

[b]Fonts[/b]
Bungee by David Jonathan Ross - SIL Open Font License 1.1
Inter by Rasmus Andersson - SIL Open Font License 1.1

[b]Engine[/b]
Made with Godot Engine (godotengine.org) - MIT License

[i]Click anywhere to close.[/i][/center]"""


func _show_credits() -> void:
	var o := Control.new()
	o.name = "CreditsOverlay"
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(dim)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_override("normal_font", UIKit.font(UIKit.FONT_BODY_LIGHT_PATH))
	t.add_theme_font_override("bold_font", UIKit.font(UIKit.FONT_DISPLAY_PATH))
	t.add_theme_font_size_override("normal_font_size", 20)
	t.add_theme_font_size_override("bold_font_size", 24)
	t.add_theme_color_override("default_color", Color(1, 1, 1, 0.9))
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.offset_top = 60
	t.offset_left = 80
	t.offset_right = -80
	t.text = CREDITS_TEXT
	o.add_child(t)
	o.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			o.queue_free())
	add_child(o)
