extends RefCounted
class_name DeckIcons

# The deck emblems drawn in code (crisp at any size): Grunk's dynamite,
# Agatha's cookie, Presto's candle, Barnacle's doubloon, Reginald's shield,
# Larry's casino chip. Used by the mana counter and the Signature Move
# button. `t` animates flames, fuses and glints; `bg` is the backdrop
# color (for the bite out of a spent cookie).

static func draw(ci: CanvasItem, deck: String, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	match deck:
		"grunk":
			_dynamite(ci, c, s, lit, i, t, bg)
		"agatha":
			_cookie(ci, c, s, lit, i, t, bg)
		"presto":
			_candle(ci, c, s, lit, i, t, bg)
		"barnacle":
			_doubloon(ci, c, s, lit, i, t, bg)
		"reginald":
			_shield(ci, c, s, lit, i, t, bg)
		_:
			_chip(ci, c, s, lit, i, t, bg)


static func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for k in 4:
		var f: float = 1.0 - k * 0.22
		ci.draw_circle(c, r * f, Color(col.r, col.g, col.b, 0.07 + k * 0.05))


static func _dynamite(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var w: float = s * 0.36
	var h: float = s * 0.66
	var body := Rect2(c.x - w * 0.5, c.y - h * 0.38, w, h)
	var red := Color(0.86, 0.16, 0.12) if lit else Color(0.3, 0.16, 0.15)
	ci.draw_rect(body, red)
	ci.draw_rect(Rect2(body.position.x, body.position.y, w * 0.28, h), red.lightened(0.25))
	for yy in [0.22, 0.78]:
		ci.draw_line(Vector2(body.position.x, body.position.y + h * yy), Vector2(body.end.x, body.position.y + h * yy), red.darkened(0.45), maxf(1.0, s * 0.06))
	var top := Vector2(c.x, body.position.y)
	var tip := top + Vector2(s * 0.16, -s * 0.2)
	if lit:
		ci.draw_line(top, tip, Color(0.55, 0.42, 0.3), maxf(1.0, s * 0.06))
		var fl: float = 0.75 + 0.25 * sin(t * 18.0 + i * 1.7)
		_glow(ci, tip, s * 0.32 * fl, Color(1.0, 0.6, 0.15))
		ci.draw_circle(tip, s * 0.08 * fl, Color(1.0, 0.95, 0.7))
		for k in 3:
			var a: float = t * 9.0 + i + k * 2.1
			ci.draw_line(tip, tip + Vector2(cos(a), sin(a)) * s * 0.17 * fl, Color(1.0, 0.85, 0.35), maxf(1.0, s * 0.04))
	else:
		ci.draw_line(top, top + Vector2(s * 0.05, -s * 0.07), Color(0.1, 0.08, 0.08), maxf(1.0, s * 0.06))


static func _cookie(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var r: float = s * 0.38
	var dough := Color(0.85, 0.62, 0.34) if lit else Color(0.36, 0.3, 0.26)
	if lit:
		_glow(ci, c, r * 1.35, Color(1.0, 0.8, 0.45))
	ci.draw_circle(c, r, dough.darkened(0.25))
	ci.draw_circle(c, r * 0.86, dough)
	var chip := Color(0.3, 0.16, 0.08) if lit else Color(0.18, 0.15, 0.13)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + i
	for k in 5:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.15, 0.6) * r
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * d, s * 0.06, chip)
	if not lit:
		# A bite taken out of a spent cookie.
		var bite := c + Vector2(r * 0.72, -r * 0.62)
		for k2 in 3:
			ci.draw_circle(bite + Vector2(k2 * r * 0.22 - r * 0.22, k2 * r * 0.18), r * 0.3, bg)


static func _candle(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var w: float = s * 0.26
	var h: float = s * 0.5
	var wax := Color(0.95, 0.9, 0.78) if lit else Color(0.4, 0.38, 0.36)
	var base_y: float = c.y + s * 0.38
	ci.draw_rect(Rect2(c.x - w * 0.5, base_y - h, w, h), wax)
	ci.draw_rect(Rect2(c.x - w * 0.5, base_y - h, w * 0.3, h), wax.darkened(0.08))
	ci.draw_circle(Vector2(c.x + w * 0.2, base_y - h + s * 0.04), s * 0.05, wax)  # a drip
	var wick := Vector2(c.x, base_y - h)
	ci.draw_line(wick, wick + Vector2(0, -s * 0.08), Color(0.15, 0.12, 0.1), maxf(1.0, s * 0.04))
	if lit:
		var fl: float = 0.85 + 0.15 * sin(t * 13.0 + i * 2.3)
		var tip := wick + Vector2(sin(t * 7.0 + i) * s * 0.02, -s * 0.12)
		_glow(ci, tip, s * 0.34 * fl, Color(1.0, 0.75, 0.35))
		var flame := PackedVector2Array([tip + Vector2(0, -s * 0.2 * fl), tip + Vector2(s * 0.08, 0), tip + Vector2(0, s * 0.07), tip + Vector2(-s * 0.08, 0)])
		ci.draw_colored_polygon(flame, Color(1.0, 0.7, 0.2))
		ci.draw_circle(tip + Vector2(0, s * 0.01), s * 0.04, Color(1.0, 1.0, 0.85))
	else:
		var sm := wick + Vector2(0, -s * 0.12)
		var a: float = fmod(t * 0.7 + i * 0.3, 1.0)
		ci.draw_circle(sm + Vector2(sin(a * 6.0) * s * 0.04, -a * s * 0.2), s * 0.035, Color(0.7, 0.7, 0.75, 0.5 * (1.0 - a)))


static func _doubloon(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var r: float = s * 0.37
	var gold := Color(1.0, 0.78, 0.25) if lit else Color(0.35, 0.28, 0.17)
	if lit:
		_glow(ci, c, r * 1.4, Color(1.0, 0.8, 0.3))
	ci.draw_circle(c, r, gold.darkened(0.3))
	ci.draw_circle(c, r * 0.84, gold)
	ci.draw_arc(c, r * 0.64, 0, TAU, 24, gold.darkened(0.3), maxf(1.0, s * 0.04))
	var k: float = r * 0.32
	ci.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), gold.darkened(0.45), maxf(1.0, s * 0.06))
	ci.draw_line(c + Vector2(k, -k), c + Vector2(-k, k), gold.darkened(0.45), maxf(1.0, s * 0.06))
	if lit:
		var a: float = fmod(t * 0.5 + i * 0.13, 1.0)
		if a < 0.12:
			_star(ci, c + Vector2(-r * 0.4, -r * 0.45), s * 0.14 * (1.0 - abs(a - 0.06) / 0.06), Color(1, 1, 0.9))


static func _shield(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var w: float = s * 0.34
	var top: float = c.y - s * 0.36
	var steel := Color(0.78, 0.82, 0.9) if lit else Color(0.25, 0.27, 0.32)
	var pts := PackedVector2Array([Vector2(c.x - w, top), Vector2(c.x + w, top), Vector2(c.x + w, top + s * 0.32), Vector2(c.x, c.y + s * 0.38), Vector2(c.x - w, top + s * 0.32)])
	if lit:
		_glow(ci, c, s * 0.5, Color(0.75, 0.85, 1.0))
	ci.draw_colored_polygon(pts, steel.darkened(0.3))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.8)
	ci.draw_colored_polygon(inner, steel)
	var gold := Color(1.0, 0.8, 0.3) if lit else Color(0.35, 0.3, 0.2)
	ci.draw_line(Vector2(c.x, top + s * 0.08), Vector2(c.x, c.y + s * 0.24), gold, maxf(1.5, s * 0.08))
	ci.draw_line(Vector2(c.x - w * 0.6, top + s * 0.24), Vector2(c.x + w * 0.6, top + s * 0.24), gold, maxf(1.5, s * 0.08))


static func _chip(ci: CanvasItem, c: Vector2, s: float, lit: bool, i: int, t: float, bg: Color) -> void:
	var r: float = s * 0.38
	var col := Color(0.86, 0.12, 0.2) if lit else Color(0.3, 0.22, 0.25)
	if lit:
		_glow(ci, c, r * 1.4, Color(1.0, 0.35, 0.5))
	ci.draw_circle(c, r, col)
	var edge := Color(0.97, 0.95, 0.9) if lit else Color(0.5, 0.48, 0.47)
	for k in 6:
		var a: float = k * TAU / 6.0 + (t * 0.6 if lit else 0.0) * 0.0
		ci.draw_arc(c, r * 0.84, a - 0.22, a + 0.22, 6, edge, maxf(1.5, s * 0.1))
	ci.draw_circle(c, r * 0.5, col.darkened(0.2))
	ci.draw_arc(c, r * 0.5, 0, TAU, 20, edge, maxf(1.0, s * 0.04))
	if lit:
		var a2: float = fmod(t * 0.45 + i * 0.11, 1.0)
		if a2 < 0.1:
			_star(ci, c + Vector2(r * 0.35, -r * 0.4), s * 0.13 * (1.0 - abs(a2 - 0.05) / 0.05), Color(1, 1, 1))


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.2:
		return
	ci.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, 1.5)
	ci.draw_line(c + Vector2(0, -r), c + Vector2(0, r), col, 1.5)
