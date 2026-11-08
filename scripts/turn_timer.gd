extends Control
class_name TurnTimer

# The 90-second turn clock. Silent for the first 75 seconds; for the last
# 15 a themed fuse burns along the table toward the END TURN button and
# the seconds tick at its tip. When it reaches the button the turn ends
# (main calls end turn). Each deck burns its own way:
#   Grunk     a black-powder fuse spitting orange sparks
#   Agatha    kitchen twine, puffs of steam
#   Presto    a line of runes winking out in blue motes
#   Barnacle  tarred rope, embers
#   Reginald  a slow-match cord, gold sparks
#   Larry     a strip of marquee bulbs going dark, pink and gold glints

const TURN_TIME := 90.0
const WARN_TIME := 15.0

const LOOKS := {
	"grunk": {"cord": Color(0.25, 0.18, 0.12), "hot": Color(1.0, 0.6, 0.15), "spark": Color(1.0, 0.85, 0.35), "style": "fuse"},
	"agatha": {"cord": Color(0.85, 0.82, 0.78), "hot": Color(1.0, 0.75, 0.5), "spark": Color(1.0, 1.0, 1.0), "style": "twine"},
	"presto": {"cord": Color(0.25, 0.35, 0.8), "hot": Color(0.5, 0.85, 1.0), "spark": Color(0.75, 0.95, 1.0), "style": "runes"},
	"barnacle": {"cord": Color(0.45, 0.33, 0.2), "hot": Color(1.0, 0.5, 0.2), "spark": Color(1.0, 0.7, 0.3), "style": "rope"},
	"reginald": {"cord": Color(0.35, 0.3, 0.25), "hot": Color(1.0, 0.8, 0.35), "spark": Color(1.0, 0.92, 0.55), "style": "fuse"},
	"larry": {"cord": Color(0.35, 0.1, 0.3), "hot": Color(1.0, 0.4, 0.75), "spark": Color(1.0, 0.85, 0.3), "style": "bulbs"},
}

var deck: String = "grunk"
var left: float = TURN_TIME   # seconds left this turn
var from_x: float = 300.0     # where the fuse starts (canvas x)
var to_x: float = 1090.0      # where it ends: the END TURN button's left edge
var line_y: float = 350.0

var _t: float = 0.0
var _sparks: Array = []       # [{p, v, life, max}]
var _num: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	_num = Label.new()
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_num.add_theme_font_size_override("font_size", 38)
	_num.add_theme_color_override("font_color", Color.WHITE)
	_num.add_theme_color_override("font_outline_color", Color.BLACK)
	_num.add_theme_constant_override("outline_size", 6)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.size = Vector2(60, 40)
	add_child(_num)


func warning() -> bool:
	return left <= WARN_TIME and left > 0.0


func _look() -> Dictionary:
	return LOOKS.get(deck, LOOKS["grunk"])


func _process(delta: float) -> void:
	_t += delta
	visible = warning() or not _sparks.is_empty()
	if not visible:
		return
	var tip := _tip()
	var lk: Dictionary = _look()
	if warning():
		# Throw a few sparks (or puffs) off the burning tip each frame.
		var n: int = 4 if lk["style"] != "twine" else 1
		for k in n:
			var a: float = randf_range(-PI, 0.0)
			var sp: float = randf_range(90.0, 260.0) if lk["style"] != "twine" else randf_range(15.0, 40.0)
			var life: float = randf_range(0.25, 0.5) if lk["style"] != "twine" else randf_range(0.7, 1.1)
			_sparks.append({"p": tip, "v": Vector2(cos(a), sin(a)) * sp, "life": life, "max": life})
	var keep: Array = []
	for s in _sparks:
		s["life"] -= delta
		if s["life"] > 0.0:
			s["p"] += s["v"] * delta
			if lk["style"] == "twine":
				s["v"] = s["v"] * 0.97 + Vector2(0, -30.0 * delta)
			else:
				s["v"] += Vector2(0, 260.0 * delta)
			keep.append(s)
	_sparks = keep
	_num.text = "%d" % int(ceil(left)) if warning() else ""
	_num.position = tip + Vector2(-30, -70)
	_num.add_theme_color_override("font_color", Color.WHITE.lerp(lk["hot"], 0.5 + 0.5 * sin(_t * 8.0)) if left < 5.0 else Color.WHITE)
	queue_redraw()


func _tip() -> Vector2:
	var f: float = clampf(left / WARN_TIME, 0.0, 1.0)
	# The fuse burns from the far end toward the button.
	return Vector2(lerpf(to_x, from_x, f), line_y + sin(_t * 2.0) * 0.0)


func _draw() -> void:
	var lk: Dictionary = _look()
	var tip := _tip()
	if warning():
		var cord: Color = lk["cord"]
		match str(lk["style"]):
			"runes":
				var x: float = tip.x
				while x < to_x:
					var a: float = 0.55 + 0.45 * sin(_t * 4.0 + x * 0.05)
					_rune(Vector2(x + 8, line_y), Color(0.5, 0.75, 1.0, a))
					x += 22.0
			"bulbs":
				var x2: float = tip.x
				var k: int = 0
				while x2 < to_x:
					var on: bool = int(_t * 6.0 + k) % 3 != 0
					draw_circle(Vector2(x2 + 8, line_y), 5.0, Color(1.0, 0.85, 0.4) if on else Color(0.45, 0.3, 0.2))
					x2 += 18.0
					k += 1
			_:
				# A cord with a twist pattern.
				draw_line(Vector2(tip.x, line_y), Vector2(to_x, line_y), Color(0, 0, 0, 0.85), 14.0)
				draw_line(Vector2(tip.x, line_y), Vector2(to_x, line_y), cord, 9.0)
				var x3: float = tip.x
				while x3 < to_x:
					draw_line(Vector2(x3, line_y - 4.0), Vector2(x3 + 7.0, line_y + 4.0), cord.lightened(0.35), 2.5)
					x3 += 9.0
		# The burnt part: a faint ash trail behind the tip.
		draw_line(Vector2(from_x, line_y), Vector2(tip.x, line_y), Color(0.1, 0.1, 0.1, 0.35), 3.0)
		# The burning tip.
		var fl: float = 0.8 + 0.2 * sin(_t * 22.0)
		var hot: Color = lk["hot"]
		for k2 in 6:
			draw_circle(tip, (46.0 - k2 * 7.0) * fl, Color(hot.r, hot.g, hot.b, 0.06 + k2 * 0.07))
		draw_circle(tip, 9.0 * fl, Color(1.0, 1.0, 0.9))
	var sc: Color = lk["spark"]
	for s in _sparks:
		var a2: float = float(s["life"]) / float(s["max"])
		var p: Vector2 = s["p"]
		if str(lk["style"]) == "twine":
			draw_circle(p, 6.0 + (1.0 - a2) * 10.0, Color(1, 1, 1, 0.25 * a2))
		else:
			var v: Vector2 = s["v"]
			draw_line(p, p - v.normalized() * 15.0, Color(sc.r, sc.g, sc.b, a2), 3.0)


func _rune(c: Vector2, col: Color) -> void:
	draw_line(c + Vector2(-5, -6), c + Vector2(5, 6), col, 2.0)
	draw_line(c + Vector2(5, -6), c + Vector2(-5, 6), col, 2.0)
	draw_line(c + Vector2(0, -7), c + Vector2(0, 7), col, 2.0)
