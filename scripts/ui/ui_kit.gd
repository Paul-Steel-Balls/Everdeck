extends RefCounted
class_name UIKit

# Shared look-and-feel for the reworked screens: fonts, colors, chunky
# animated buttons, and small motion helpers. Everything is built in code
# (no .tscn), matching the rest of the project.

const FONT_LOGO_PATH := "res://fonts/BungeeShade-Regular.ttf"
const FONT_DISPLAY_PATH := "res://fonts/Bungee-Regular.ttf"
const FONT_INLINE_PATH := "res://fonts/BungeeInline-Regular.ttf"
const FONT_BODY_PATH := "res://fonts/Inter-ExtraBold.otf"
const FONT_BODY_LIGHT_PATH := "res://fonts/Inter-SemiBold.otf"

const GOLD := Color(1.0, 0.78, 0.22)
const GOLD_DEEP := Color(0.85, 0.45, 0.05)
const INK := Color(0.06, 0.03, 0.10)
const NIGHT := Color(0.05, 0.02, 0.09)
const HOLO := Color(0.66, 0.42, 1.0)

const BTN_GREEN := Color(0.16, 0.62, 0.20)
const BTN_BLUE := Color(0.16, 0.36, 0.86)
const BTN_PURPLE := Color(0.46, 0.22, 0.80)
const BTN_RED := Color(0.78, 0.16, 0.20)

const CLASS_COLOR: Dictionary = {
	"grunk": Color(1.0, 0.45, 0.10),
	"agatha": Color(1.0, 0.76, 0.25),
	"presto": Color(0.70, 0.40, 1.0),
	"barnacle": Color(0.10, 0.80, 0.78),
	"reginald": Color(0.30, 0.50, 1.0),
	"larry": Color(0.20, 0.85, 0.40),
}

# Personality for the menus. Titles and lines are display-only.
const HERO_INFO: Dictionary = {
	"grunk": {"title": "The Demolition Goblin", "line": "Stand back. Further. FURTHER."},
	"agatha": {"title": "The Soup Matriarch", "line": "You look thin. Let me fix that."},
	"presto": {"title": "The Overdue Apprentice", "line": "I studied for this! ...Mostly."},
	"barnacle": {"title": "Terror of the Tide", "line": "Hoist the sails! And the snacks!"},
	"reginald": {"title": "Knight of Paperwork", "line": "State your business. In triplicate."},
	"larry": {"title": "The House", "line": "Feelin' lucky? I always am."},
}

# Left corner of each hero's mouth in the portrait painting (0..1 UV).
# Speech bubble tails point here.
const HERO_MOUTH: Dictionary = {
	"grunk": Vector2(0.42, 0.455),
	"agatha": Vector2(0.545, 0.485),
	"presto": Vector2(0.59, 0.43),
	"barnacle": Vector2(0.45, 0.40),
	"reginald": Vector2(0.455, 0.40),
	"larry": Vector2(0.49, 0.345),
}

# Center of each hero's face (0..1 UV) and a radius (fraction of width)
# for round/hex portrait crops.
const HERO_FACE: Dictionary = {
	"grunk": Vector3(0.52, 0.36, 0.30),
	"agatha": Vector3(0.58, 0.38, 0.24),
	"presto": Vector3(0.60, 0.36, 0.25),
	"barnacle": Vector3(0.45, 0.33, 0.27),
	"reginald": Vector3(0.50, 0.30, 0.26),
	"larry": Vector3(0.55, 0.28, 0.26),
}

# Play-style ratings shown on hero select (display only, 1..5).
const HERO_STYLE: Dictionary = {
	"grunk": {"Aggression": 5, "Defense": 2, "Chaos": 3},
	"agatha": {"Aggression": 2, "Defense": 5, "Chaos": 1},
	"presto": {"Aggression": 3, "Defense": 2, "Chaos": 4},
	"barnacle": {"Aggression": 4, "Defense": 3, "Chaos": 2},
	"reginald": {"Aggression": 2, "Defense": 4, "Chaos": 1},
	"larry": {"Aggression": 3, "Defense": 2, "Chaos": 5},
}

static var _fonts: Dictionary = {}


static func font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


static func label(text: String, size: int, color: Color = Color.WHITE, font_path: String = FONT_BODY_PATH, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font(font_path))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func hero_texture(class_id: String) -> Texture2D:
	return CardArt.texture_for("", "hero_" + class_id)


static func _box(fill: Color, border: Color, skew: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.skew = Vector2(skew, 0)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb


# A chunky slanted arcade button that grows on hover, squashes on press,
# and (optionally) breathes with a slow glow when idle.
static func button(text: String, fill: Color, font_size: int = 34, min_size: Vector2 = Vector2(360, 76), pulse: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(FONT_DISPLAY_PATH))
	b.add_theme_font_size_override("font_size", font_size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_stylebox_override("normal", _box(fill, GOLD, 0.18))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.18), Color(1, 0.95, 0.6), 0.18))
	b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.15), GOLD_DEEP, 0.18))
	b.add_theme_stylebox_override("hover_pressed", _box(fill.darkened(0.15), GOLD_DEEP, 0.18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Gloss: a soft white band across the top half.
	var gloss := ColorRect.new()
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.anchor_right = 1.0
	gloss.anchor_bottom = 0.5
	gloss.offset_left = 14
	gloss.offset_right = -14
	gloss.offset_top = 6
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/gloss.gdshader")
	gloss.material = gm
	b.add_child(gloss)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _tween_scale(b, 1.07, 0.12))
	b.mouse_exited.connect(func() -> void: _tween_scale(b, 1.0, 0.16))
	b.button_down.connect(func() -> void: _tween_scale(b, 0.94, 0.06))
	b.button_up.connect(func() -> void: _tween_scale(b, 1.07 if b.is_hovered() else 1.0, 0.14))
	if pulse:
		b.ready.connect(func() -> void: _start_pulse(b), CONNECT_ONE_SHOT)
	return b


static func _tween_scale(c: Control, s: float, t: float) -> void:
	if not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(s, s), t)


static func _start_pulse(b: Control) -> void:
	var tw := b.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(b, "self_modulate", Color(1.18, 1.12, 1.0), 0.9)
	tw.tween_property(b, "self_modulate", Color(1, 1, 1), 0.9)


# Slide a control in from an offset with a fade, after a delay.
static func enter(c: CanvasItem, from_offset: Vector2, delay: float, dur: float = 0.45) -> void:
	var target: Vector2 = c.position
	c.position = target + from_offset
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", target, dur)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.6)


# Soft round glow texture for particles.
static func glow_texture(px: int = 32) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = px
	t.height = px
	return t


# Rising embers across a rect: additive, flickering, drifting sideways.
static func embers(area: Vector2, amount: int = 90, tint: Color = Color(1.0, 0.55, 0.15)) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.texture = glow_texture(32)
	var cim := CanvasItemMaterial.new()
	cim.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = cim
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(area.x * 0.5, 20, 1)
	m.direction = Vector3(0, -1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 40.0
	m.initial_velocity_max = 130.0
	# Gentle sideways sway instead of turbulence (turbulence damps the
	# rise and leaves the embers stuck near the bottom).
	m.gravity = Vector3(6, -8, 0)
	m.damping_min = 0.0
	m.damping_max = 4.0
	m.scale_min = 0.12
	m.scale_max = 0.55
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.85, 0.4, 0.95))
	ramp.add_point(0.6, Color(tint.r, tint.g, tint.b, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(tint.r * 0.6, tint.g * 0.2, 0.05, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	m.color_ramp = rt
	p.process_material = m
	p.position = Vector2(area.x * 0.5, area.y + 10)
	return p
