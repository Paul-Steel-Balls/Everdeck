extends Control
class_name TurnBanner

# The turn plaque: a ribbon with notched ends, gold edges with an ink
# line, a face lit for your turn (deep violet, gold lettering) or dim steel
# for theirs, and the display font. Used small at the top of the screen
# and big for the sweep when a turn starts.

var text: String = "YOUR TURN"
var mine: bool = true
var font_size: int = 26
var _t: float = 0.0
var _font: Font


func setup(t: String, is_mine: bool, fs: int) -> void:
	text = t
	mine = is_mine
	font_size = fs
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	size = Vector2(tw + fs * 3.4, fs * 1.9)
	custom_minimum_size = size
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _ribbon(i: float) -> PackedVector2Array:
	var W: float = size.x
	var H: float = size.y
	var n: float = H * 0.42  # notch depth
	return PackedVector2Array([Vector2(i * 0.5, i), Vector2(W - i * 0.5, i), Vector2(W - n + i * 0.6, H * 0.5),
		Vector2(W - i * 0.5, H - i), Vector2(i * 0.5, H - i), Vector2(n - i * 0.6, H * 0.5)])


func _draw() -> void:
	var W: float = size.x
	var H: float = size.y
	var gold: Color = UIKit.GOLD if mine else Color(0.7, 0.72, 0.78)
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.3) if mine else Color(0.3, 0.31, 0.36)
	var face_top: Color = Color(0.3, 0.14, 0.56) if mine else Color(0.2, 0.21, 0.26)
	var face_bot: Color = Color(0.1, 0.04, 0.22) if mine else Color(0.09, 0.09, 0.12)
	# Shadow.
	var sh := _ribbon(0.0)
	for i in sh.size():
		sh[i] += Vector2(0, H * 0.08)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	# Ink, gold, bevel, inner ink, face.
	draw_colored_polygon(_ribbon(-1.5), UIKit.INK)
	draw_colored_polygon(_ribbon(0.0), gold_d)
	draw_colored_polygon(_ribbon(1.5), gold)
	var up := PackedVector2Array()
	for v in _ribbon(1.5):
		up.append(Vector2(v.x, minf(v.y, H * 0.5)))
	draw_colored_polygon(up, gold.lightened(0.3))
	draw_colored_polygon(_ribbon(H * 0.1), UIKit.INK)
	var face := _ribbon(H * 0.12)
	draw_colored_polygon(face, face_bot)
	var fup := PackedVector2Array()
	for v in face:
		fup.append(Vector2(v.x, minf(v.y, H * 0.52)))
	draw_colored_polygon(fup, face_top)
	# A light sheen sweeping across now and then (your turn only).
	if mine:
		var ph: float = fmod(_t * 0.45, 1.6)
		if ph < 1.0:
			var x: float = lerpf(-H, W + H, ph)
			var band := PackedVector2Array([Vector2(x - H * 0.25, 0), Vector2(x + H * 0.05, 0), Vector2(x - H * 0.35, H), Vector2(x - H * 0.65, H)])
			for part in Geometry2D.intersect_polygons(band, face):
				draw_colored_polygon(part, Color(1, 1, 1, 0.16))
	# Lettering.
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2((W - tw) * 0.5, H * 0.5 + font_size * 0.4)
	var col: Color = Color(1.0, 0.86, 0.42) if mine else Color(0.82, 0.84, 0.9)
	draw_string_outline(_font, base + Vector2(0, font_size * 0.07), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(4, font_size / 4), Color(0, 0, 0, 0.5))
	draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(4, font_size / 4), UIKit.INK)
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
