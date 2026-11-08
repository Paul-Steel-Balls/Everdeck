extends Control
class_name SpeechBubble

# Comic speech bubble tinted to a class color: hard ink drop shadow, thick
# ink outline, class-colored inner rim, and a tail that always points at
# `target` (a point in this bubble's PARENT's coordinates, e.g. a mouth).

const PAD := Vector2(24, 14)
const RADIUS := 22
const INK_W := 5.0
const SHADOW := Vector2(6, 7)
const MAX_TEXT_W := 290.0
const FONT_SIZE := 22

var accent: Color = Color(1, 0.6, 0.2)
var target: Vector2 = Vector2.ZERO
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UIKit.label("", FONT_SIZE, UIKit.INK, "res://fonts/Inter-Black.otf")
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_label.position = PAD
	add_child(_label)


func set_line(text: String, color: Color) -> void:
	accent = color
	_label.text = text
	# Wrap long lines so the bubble stays compact (it lives in the narrow
	# gap between the menu buttons and the hero's face).
	var f: Font = _label.get_theme_font("font")
	var one_line: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var text_size: Vector2
	if one_line.x > MAX_TEXT_W:
		# Two balanced lines read better than one long and one short.
		var w: float = clamp(one_line.x * 0.6 + 24.0, 200.0, MAX_TEXT_W)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_size = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, FONT_SIZE)
		text_size.x = w
	else:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		text_size = one_line
	text_size += Vector2(2, 4)
	_label.custom_minimum_size = Vector2(text_size.x, 0)
	_label.size = text_size
	size = text_size + PAD * 2.0
	pivot_offset = _tail_base()
	queue_redraw()


func set_target(p: Vector2) -> void:
	target = p
	queue_redraw()


func _fill_color() -> Color:
	return Color(1, 1, 1).lerp(accent, 0.24)


# Where the tail leaves the bubble: the right edge when the target is off
# to the right (the usual case), otherwise the bottom edge.
func _tail_side_right() -> bool:
	return _to_local(target).x > size.x


func _tail_side_left() -> bool:
	return _to_local(target).x < 0.0


func _tail_base() -> Vector2:
	var local_t: Vector2 = _to_local(target)
	if _tail_side_right():
		return Vector2(size.x, clamp(local_t.y, RADIUS + 14.0, size.y - RADIUS - 6.0))
	if _tail_side_left():
		return Vector2(0.0, clamp(local_t.y, RADIUS + 6.0, size.y - RADIUS - 6.0))
	return Vector2(clamp(local_t.x, RADIUS + 18.0, size.x - RADIUS - 18.0), size.y)


func _to_local(p: Vector2) -> Vector2:
	return (p - position).rotated(-rotation) / scale.x if scale.x != 0.0 else p - position


func _tail_points(grow: float) -> PackedVector2Array:
	var base: Vector2 = _tail_base()
	var tip: Vector2 = _to_local(target)
	# Stop a little short of the mouth, and cap the tail length.
	var dir: Vector2 = tip - base
	var len: float = clamp(dir.length() - 8.0, 18.0, 110.0)
	tip = base + dir.normalized() * len if dir.length() > 0.01 else base + Vector2(0, 30)
	var w: float = 13.0 + grow
	if _tail_side_right():
		return PackedVector2Array([base + Vector2(-6, -w), tip, base + Vector2(-6, w)])
	if _tail_side_left():
		return PackedVector2Array([base + Vector2(6, -w), tip, base + Vector2(6, w)])
	return PackedVector2Array([base + Vector2(-w, -6), tip, base + Vector2(w, -6)])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Hard comic drop shadow.
	_round_rect(Rect2(r.position + SHADOW, r.size), UIKit.INK.lerp(Color.BLACK, 0.3), 0.0)
	var sp := _tail_points(INK_W)
	for i in sp.size():
		sp[i] += SHADOW
	draw_colored_polygon(sp, UIKit.INK.lerp(Color.BLACK, 0.3))
	# Ink outline (rect + tail), then fill, then class-colored rim.
	_round_rect(r.grow(INK_W), UIKit.INK, 0.0)
	draw_colored_polygon(_tail_points(INK_W * 1.6), UIKit.INK)
	_round_rect(r, _fill_color(), 0.0)
	draw_colored_polygon(_tail_points(0.0), _fill_color())
	_round_rect(r.grow(-3), Color(0, 0, 0, 0), 5.0, accent.darkened(0.05))
	# Shine: a soft white streak along the top-left.
	draw_line(Vector2(RADIUS, 8), Vector2(min(size.x * 0.45, size.x - RADIUS), 8), Color(1, 1, 1, 0.8), 3.0, true)


func _round_rect(r: Rect2, fill: Color, border_w: float, border: Color = Color.TRANSPARENT) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(RADIUS)
	sb.anti_aliasing = true
	if border_w > 0.0:
		sb.draw_center = false
		sb.border_color = border
		sb.set_border_width_all(int(border_w))
	draw_style_box(sb, r)
