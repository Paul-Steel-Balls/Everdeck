extends Button
class_name EndTurnButton

# END TURN, drawn in code so it matches the rest of the game: a gold-framed
# plaque with pointed ends, a jewel on top, a face lit by state, a light
# sheen that sweeps across now and then, and a lift on hover and squash on
# press.
#   ready    your turn, moves still left: deep holo-violet face, gold rim
#   done     your turn, nothing left you can do: the face turns emerald
#            and breathes, so you know you're done
#   waiting  the other side's turn: dim steel, "ENEMY TURN"

enum Look { READY, DONE, WAITING }

const W := 170.0
const H := 100.0

var look: int = Look.READY
var _t: float = 0.0
var _hover: float = 0.0     # 0..1 eased
var _sheen: float = -1.0    # -1 idle, else 0..1 across the face
var _sheen_wait: float = 2.0
var _font: Font


func _init() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	pivot_offset = Vector2(W, H) * 0.5
	mouse_entered.connect(func() -> void: UIKit._tween_scale(self, 1.05, 0.12))
	mouse_exited.connect(func() -> void: UIKit._tween_scale(self, 1.0, 0.16))
	button_down.connect(func() -> void: UIKit._tween_scale(self, 0.94, 0.06))
	button_up.connect(func() -> void: UIKit._tween_scale(self, 1.05 if is_hovered() else 1.0, 0.14))


func set_look(l: int) -> void:
	look = l
	disabled = l == Look.WAITING
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_hover = move_toward(_hover, 1.0 if (is_hovered() and not disabled) else 0.0, delta * 6.0)
	if _sheen < 0.0:
		_sheen_wait -= delta
		if _sheen_wait <= 0.0 and look != Look.WAITING:
			_sheen = 0.0
	else:
		_sheen += delta * 1.4
		if _sheen > 1.0:
			_sheen = -1.0
			_sheen_wait = 3.5 if look == Look.READY else 1.6
	queue_redraw()


# The plaque outline: a long hexagon (pointed ends), inset by `k` pixels.
func _plaque(k: float) -> PackedVector2Array:
	var p: float = 22.0  # how far the points stick out
	var top: float = 14.0 + k
	var bot: float = H - 10.0 - k
	var mid: float = (top + bot) * 0.5
	return PackedVector2Array([
		Vector2(p + k * 0.6, top), Vector2(W - p - k * 0.6, top),
		Vector2(W - 4.0 - k, mid),
		Vector2(W - p - k * 0.6, bot), Vector2(p + k * 0.6, bot),
		Vector2(4.0 + k, mid)])


func _face_colors() -> Array:
	match look:
		Look.DONE:
			var b: float = 0.5 + 0.5 * sin(_t * 3.0)
			return [Color(0.06, 0.42, 0.22).lerp(Color(0.1, 0.62, 0.3), b), Color(0.02, 0.2, 0.1), Color(0.35, 1.0, 0.55)]
		Look.WAITING:
			return [Color(0.2, 0.21, 0.26), Color(0.1, 0.1, 0.13), Color(0.55, 0.58, 0.68)]
		_:
			return [Color(0.25, 0.12, 0.5), Color(0.07, 0.03, 0.16), Color(0.75, 0.55, 1.0)]


func _draw() -> void:
	var fc: Array = _face_colors()
	var top_c: Color = fc[0]
	var bot_c: Color = fc[1]
	var accent: Color = fc[2]
	var waiting: bool = look == Look.WAITING
	# Glow behind (stronger when done, or hovered).
	var glow_a: float = (0.28 + 0.18 * sin(_t * 3.0)) if look == Look.DONE else 0.12 + 0.18 * _hover
	if not waiting:
		for i in 4:
			var g := _plaque(-4.0 - i * 3.0)
			draw_colored_polygon(g, Color(accent.r, accent.g, accent.b, glow_a * (0.35 - i * 0.07)))
	# Drop shadow.
	var sh := _plaque(0.0)
	for i in sh.size():
		sh[i] += Vector2(0, 4)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	# Gold frame: dark rim, bright bevel on the top half, mid-gold body.
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.25) if not waiting else Color(0.3, 0.3, 0.34)
	var gold: Color = UIKit.GOLD if not waiting else Color(0.62, 0.64, 0.7)
	draw_colored_polygon(_plaque(0.0), gold_d)
	draw_colored_polygon(_plaque(2.0), gold)
	var bevel := _plaque(2.0)
	var mid_y: float = (bevel[0].y + bevel[3].y) * 0.5
	var upper := PackedVector2Array()
	for v in bevel:
		upper.append(Vector2(v.x, minf(v.y, mid_y)))
	draw_colored_polygon(upper, gold.lightened(0.35))
	draw_colored_polygon(_plaque(6.0), gold_d)
	# Face: two-tone (lighter top, darker bottom).
	var face := _plaque(8.0)
	draw_colored_polygon(face, bot_c)
	var fmid: float = (face[0].y + face[3].y) * 0.5
	var fup := PackedVector2Array()
	for v in face:
		fup.append(Vector2(v.x, minf(v.y, fmid + 4.0)))
	draw_colored_polygon(fup, top_c)
	# Fine inner line in the accent color.
	var inner := _plaque(11.0)
	inner.append(inner[0])
	draw_polyline(inner, Color(accent.r, accent.g, accent.b, 0.55), 1.5, true)
	# A sheen sweeping across the face.
	if _sheen >= 0.0 and not waiting:
		var x: float = lerpf(-30.0, W + 30.0, _sheen)
		var band := PackedVector2Array([Vector2(x - 14, 0), Vector2(x + 2, 0), Vector2(x - 18, H), Vector2(x - 34, H)])
		for part in Geometry2D.intersect_polygons(band, face):
			draw_colored_polygon(part, Color(1, 1, 1, 0.22))
	# Jewel on the top edge.
	var jc := Vector2(W * 0.5, 14.0)
	var jr: float = 10.0
	var jewel := PackedVector2Array([jc + Vector2(0, -jr), jc + Vector2(jr, 0), jc + Vector2(0, jr), jc + Vector2(-jr, 0)])
	draw_colored_polygon(jewel, gold_d)
	var jin := PackedVector2Array()
	for v in jewel:
		jin.append(jc + (v - jc) * 0.68)
	draw_colored_polygon(jin, accent if not waiting else Color(0.4, 0.42, 0.5))
	draw_circle(jc + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.8))
	# Label.
	var txt: String = "ENEMY TURN" if waiting else "END TURN"
	var fs: int = 21 if waiting else 25
	var tw: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2((W - tw) * 0.5, fmid + fs * 0.42)
	var col: Color = Color.WHITE.lerp(Color(1.0, 0.92, 0.6), _hover) if not waiting else Color(0.75, 0.77, 0.82)
	draw_string_outline(_font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, UIKit.INK)
	draw_string(_font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
