extends Control
class_name TargetArrow

# The targeting arrow, drawn in code over the board. It arcs from the
# attacker (or the card / Signature Move) to the cursor and, once snapped
# to a valid target, locks on with a reticle and previews the outcome.
#   CHEVRON  a chain of chevrons flowing along a curve toward the target
#            (the readable, game-y option)
#   BEAM     a tapered hologram beam with light pulses running along it,
#            in the Boss's color (matches the battlefield's hologram look)
# States: aiming (no target under the cursor: dim), locked (valid target:
# bright, reticle closes in), blocked (a target you can't pick, e.g. a
# Taunt is in the way: red, an X and a short reason).
# Action kinds pick the reticle's center mark: attack / trick / heal.

enum Style { CHEVRON, BEAM }
enum State { AIMING, LOCKED, BLOCKED }

var style: int = Style.BEAM
var state: int = State.AIMING
var kind: String = "attack"
var color: Color = Color(1.0, 0.55, 0.15)
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var reason: String = ""
# Outcome preview chips: [{pos, text, lethal}]
var previews: Array = []
var _t: float = 0.0
var _lock_t: float = 0.0
var _font: Font
var _body: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	_body = UIKit.font("res://fonts/Inter-Black.otf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100


func aim(a: Vector2, b: Vector2, s: int, k: String = "attack") -> void:
	if s == State.LOCKED and state != State.LOCKED:
		_lock_t = 0.0
	from = a
	to = b
	state = s
	kind = k
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_lock_t += delta
	queue_redraw()


func _curve_point(t: float, mid: Vector2) -> Vector2:
	var a: float = (1.0 - t) * (1.0 - t)
	var b: float = 2.0 * (1.0 - t) * t
	return from * a + mid * b + to * (t * t)


func _mid() -> Vector2:
	var d: float = from.distance_to(to)
	return (from + to) * 0.5 + Vector2(0, -minf(150.0, d * 0.42))


func _col() -> Color:
	match state:
		State.LOCKED: return color
		State.BLOCKED: return Color(1.0, 0.2, 0.2)
	return Color(0.75, 0.78, 0.88)


func _draw() -> void:
	if from.distance_to(to) < 30.0:
		return
	var mid: Vector2 = _mid()
	var n: int = 48
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(_curve_point(float(i) / n, mid))
	if style == Style.CHEVRON:
		_draw_chevrons(pts)
	else:
		_draw_beam(pts)
	_draw_reticle()
	for p in previews:
		_chip(p.get("pos", Vector2.ZERO), str(p.get("text", "")), bool(p.get("lethal", false)))
	if state == State.BLOCKED and reason != "":
		_tag(to + Vector2(0, 48), reason)


func _length(pts: PackedVector2Array) -> float:
	var l: float = 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


# Point and tangent at arc length s along the polyline.
func _at(pts: PackedVector2Array, s: float) -> Array:
	var acc: float = 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if acc + seg >= s:
			var f: float = (s - acc) / maxf(seg, 0.001)
			return [pts[i - 1].lerp(pts[i], f), (pts[i] - pts[i - 1]).normalized()]
		acc += seg
	return [pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()]


func _draw_chevrons(pts: PackedVector2Array) -> void:
	var c: Color = _col()
	var L: float = _length(pts) - 34.0
	var gap: float = 24.0
	var flow: float = fmod(_t * 60.0, gap)
	var s: float = flow + 8.0
	while s < L:
		var f: float = s / L
		var r: Array = _at(pts, s)
		var p: Vector2 = r[0]
		var d: Vector2 = r[1]
		var nrm := Vector2(-d.y, d.x)
		var w: float = lerpf(7.0, 13.0, f)
		var a: float = lerpf(0.35, 1.0, f) * (0.75 if state == State.AIMING else 1.0)
		var tip: Vector2 = p + d * w * 0.7
		var shape := PackedVector2Array([tip, p - d * w * 0.3 + nrm * w, p - d * w * 0.3 + nrm * w * 0.45 + d * w * 0.35, p - d * w * 0.3 - nrm * w * 0.45 + d * w * 0.35, p - d * w * 0.3 - nrm * w])
		var sh := PackedVector2Array()
		for v in shape:
			sh.append(v + Vector2(0, 3))
		draw_colored_polygon(PackedVector2Array([sh[0], sh[1], sh[2], sh[3], sh[4]]), Color(0, 0, 0, 0.35 * a))
		draw_colored_polygon(PackedVector2Array([shape[0], shape[1], shape[2]]), Color(c.r, c.g, c.b, a))
		draw_colored_polygon(PackedVector2Array([shape[0], shape[3], shape[4]]), Color(c.r, c.g, c.b, a))
		draw_colored_polygon(PackedVector2Array([shape[0], shape[2], shape[3]]), Color(c.r, c.g, c.b, a))
		draw_polyline(PackedVector2Array([shape[1], shape[0], shape[4]]), Color(1, 1, 1, 0.55 * a), 1.5, true)
		s += gap
	# Big head.
	var r2: Array = _at(pts, L + 18.0)
	var hp: Vector2 = r2[0]
	var hd: Vector2 = r2[1]
	var hn := Vector2(-hd.y, hd.x)
	var head := PackedVector2Array([hp + hd * 20.0, hp - hd * 8.0 + hn * 17.0, hp - hd * 2.0, hp - hd * 8.0 - hn * 17.0])
	draw_colored_polygon(head, UIKit.INK)
	draw_colored_polygon(_shrink(head, 0.78), c)
	draw_polyline(PackedVector2Array([head[1], head[0], head[3]]), Color(1, 1, 1, 0.6), 2.0, true)


func _shrink(p: PackedVector2Array, f: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for v in p:
		c += v
	c /= p.size()
	var o := PackedVector2Array()
	for v in p:
		o.append(c + (v - c) * f)
	return o


func _draw_beam(pts: PackedVector2Array) -> void:
	var c: Color = _col()
	var bright: float = 1.0 if state != State.AIMING else 0.55
	# Glow layers, tapering from thin at the source to thick at the tip.
	var layers := [[16.0, 0.08], [10.0, 0.16], [5.0, 0.5], [2.0, 1.0]]
	for lay in layers:
		var wmax: float = lay[0]
		var al: float = lay[1] * bright
		for i in range(1, pts.size()):
			var f: float = float(i) / pts.size()
			var w: float = wmax * lerpf(0.35, 1.0, f)
			var cc: Color = c.lerp(Color.WHITE, 0.6 if wmax <= 2.0 else 0.0)
			draw_line(pts[i - 1], pts[i], Color(cc.r, cc.g, cc.b, al), w, true)
	# Pulses running toward the target.
	var L: float = _length(pts)
	for j in 4:
		var s: float = fmod(_t * 260.0 + j * L / 4.0, L)
		var r: Array = _at(pts, s)
		var p: Vector2 = r[0]
		var f2: float = s / L
		draw_circle(p, lerpf(3.0, 7.0, f2) * 1.8, Color(c.r, c.g, c.b, 0.25 * bright))
		draw_circle(p, lerpf(2.0, 4.5, f2), Color(1, 1, 1, 0.9 * bright))
	# Source ring.
	draw_arc(from, 14.0, 0, TAU, 32, Color(c.r, c.g, c.b, 0.6 * bright), 2.0, true)


func _draw_reticle() -> void:
	var c: Color = _col()
	var p: Vector2 = to
	if state == State.AIMING:
		draw_arc(p, 16.0, 0, TAU, 32, Color(c.r, c.g, c.b, 0.6), 2.0, true)
		draw_circle(p, 3.0, Color(c.r, c.g, c.b, 0.8))
		return
	# Locked / blocked: a ring that snaps in from wide, rotating ticks.
	var close: float = clampf(_lock_t / 0.16, 0.0, 1.0)
	var r: float = lerpf(64.0, 38.0, ease(close, 0.4))
	var spin: float = _t * 1.6
	draw_arc(p, r + 3.0, 0, TAU, 48, Color(0, 0, 0, 0.4), 6.0, true)
	for i in 4:
		var a0: float = spin + i * TAU / 4.0 + 0.18
		draw_arc(p, r, a0, a0 + TAU / 4.0 - 0.36, 12, c, 4.0, true)
		var a1: float = spin + i * TAU / 4.0
		var dir := Vector2(cos(a1), sin(a1))
		draw_line(p + dir * (r - 9.0), p + dir * (r + 9.0), Color(1, 1, 1, 0.9), 3.0, true)
	draw_arc(p, r - 7.0, 0, TAU, 48, Color(c.r, c.g, c.b, 0.35), 1.5, true)
	# Center mark.
	if state == State.BLOCKED:
		draw_line(p + Vector2(-11, -11), p + Vector2(11, 11), c, 5.0, true)
		draw_line(p + Vector2(-11, 11), p + Vector2(11, -11), c, 5.0, true)
		return
	match kind:
		"heal":
			draw_rect(Rect2(p - Vector2(4, 12), Vector2(8, 24)), Color(0.4, 1.0, 0.5))
			draw_rect(Rect2(p - Vector2(12, 4), Vector2(24, 8)), Color(0.4, 1.0, 0.5))
		"trick":
			var star := PackedVector2Array()
			for i in 10:
				var a2: float = -PI / 2 + TAU * i / 10.0
				star.append(p + Vector2(cos(a2), sin(a2)) * (12.0 if i % 2 == 0 else 5.0))
			draw_colored_polygon(star, Color(1, 1, 1, 0.95))
		_:
			# Crossed swords, simple.
			for sgn in [-1.0, 1.0]:
				var d := Vector2(sgn, -1).normalized()
				draw_line(p - d * 12.0, p + d * 12.0, Color(1, 1, 1, 0.95), 3.5, true)
				var g := Vector2(-d.y, d.x)
				draw_line(p - d * 6.0 + g * 5.0, p - d * 6.0 - g * 5.0, Color(1, 1, 1, 0.95), 3.0, true)


# Outcome preview: "-3" on a chip, a skull when it would die.
func _chip(p: Vector2, t: String, lethal: bool) -> void:
	var fs: int = 22
	var w: float = _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0 + (26.0 if lethal else 0.0)
	var r := Rect2(p - Vector2(w * 0.5, 34), Vector2(w, 30))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.05, 0.08, 0.92) if not lethal else Color(0.12, 0.02, 0.04, 0.95)
	sb.set_corner_radius_all(15)
	sb.border_color = Color(1, 0.85, 0.85) if not lethal else Color(1.0, 0.3, 0.3)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	var x: float = r.position.x + 9.0
	if lethal:
		var sc := Vector2(x + 10.0, r.get_center().y - 1.0)
		draw_circle(sc, 9.0, Color(0.95, 0.93, 0.88))
		draw_rect(Rect2(sc + Vector2(-5, 5), Vector2(10, 6)), Color(0.95, 0.93, 0.88))
		draw_circle(sc + Vector2(-3.5, 0), 2.6, Color(0.1, 0.0, 0.0))
		draw_circle(sc + Vector2(3.5, 0), 2.6, Color(0.1, 0.0, 0.0))
		x += 26.0
	draw_string_outline(_font, Vector2(x, r.get_center().y + fs * 0.38), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UIKit.INK)
	draw_string(_font, Vector2(x, r.get_center().y + fs * 0.38), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _tag(p: Vector2, t: String) -> void:
	var fs: int = 15
	var w: float = _body.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var r := Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 26))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.04, 0.06, 0.92)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(1.0, 0.3, 0.3)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	draw_string(_body, Vector2(r.position.x + 10.0, r.get_center().y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
