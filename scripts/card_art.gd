extends Control
class_name CardArt

# Procedural card art, drawn in code with Godot shapes — no image files.
# Each card in CardDB has an "art" id; CardArt draws a small colorful
# scene for it. Coordinates are virtual 0..100 in both axes.

const VALID_ART: Array = [
	"squirrel", "squire", "recruit", "dog", "archer", "wolf", "knight",
	"brute", "ogre", "toddler", "golem", "dragon", "shield", "wall",
	"fortress", "bolt", "cavalry", "doctor", "zap", "eye", "manager",
	"fireball", "heal", "cookie", "nova", "dagger", "roulette", "mind",
	"hands", "coin", "intern",
]

# Hand-drawn hero portraits (one per class) + token art.
const HERO_ART: Array = [
	"hero_grunk", "hero_agatha", "hero_presto", "hero_barnacle",
	"hero_reginald", "hero_larry", "deckhand", "token",
]

var art_id: String = ""
# Card id (e.g. "agatha_boris"). When set and a painted image exists for
# it, the painting is drawn instead of the procedural art. Hero art ids
# ("hero_grunk") also resolve to painted portraits.
var card_id: String = ""

# Where faces usually sit in the paintings (0 = top, 1 = bottom). Used
# when a frame crops the painting so heads stay in view.
const FOCUS_Y: float = 0.35

static var _tex_cache: Dictionary = {}


# Painted texture for a card id or hero art id, or null if none exists.
static func texture_for(cid: String, aid: String = "") -> Texture2D:
	var path: String = ""
	if not cid.is_empty():
		path = "res://art/cards/%s.webp" % cid
	if (path.is_empty() or not ResourceLoader.exists(path)) and aid.begins_with("hero_"):
		path = "res://art/heroes/%s.webp" % aid
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[path] = tex
	return tex


# Draw the texture to fill the whole control, cropping the overflow
# (like CSS object-fit: cover), biased toward FOCUS_Y vertically.
func _draw_cover(tex: Texture2D) -> void:
	var ts: Vector2 = tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var sc: float = max(size.x / ts.x, size.y / ts.y)
	var src_size: Vector2 = size / sc
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * FOCUS_Y)
	draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), Rect2(src_pos, src_size))


# Every non-empty art id renders something: hand-drawn art where it
# exists, otherwise a deterministic hash-based scene (same id = same art).
# Nothing ever renders blank.
static func renders(art: String) -> bool:
	return not str(art).strip_edges().is_empty()


func _draw() -> void:
	var tex: Texture2D = texture_for(card_id, art_id)
	if tex != null:
		_draw_cover(tex)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.92, 0.85))
	match art_id:
		"squirrel": _art_squirrel()
		"squire": _art_squire()
		"recruit": _art_recruit()
		"dog": _art_dog()
		"archer": _art_archer()
		"wolf": _art_wolf()
		"knight": _art_knight()
		"brute": _art_brute()
		"ogre": _art_ogre()
		"toddler": _art_toddler()
		"golem": _art_golem()
		"dragon": _art_dragon()
		"shield": _art_shield()
		"wall": _art_wall()
		"fortress": _art_fortress()
		"bolt": _art_bolt()
		"cavalry": _art_cavalry()
		"doctor": _art_doctor()
		"zap": _art_zap()
		"eye": _art_eye()
		"manager": _art_manager()
		"fireball": _art_fireball()
		"heal": _art_heal()
		"cookie": _art_cookie()
		"nova": _art_nova()
		"dagger": _art_dagger()
		"roulette": _art_roulette()
		"mind": _art_mind()
		"hands": _art_hands()
		"coin": _art_coin()
		"intern": _art_intern()
		"hero_grunk": _art_hero_grunk()
		"hero_agatha": _art_hero_agatha()
		"hero_presto": _art_hero_presto()
		"hero_barnacle": _art_hero_barnacle()
		"hero_reginald": _art_hero_reginald()
		"hero_larry": _art_hero_larry()
		"deckhand": _art_deckhand()
		"token": _art_token()
		_: _art_generic()


# --- Helpers (virtual 0..100 coords) ---

func _px(x: float, y: float) -> Vector2:
	return Vector2(x / 100.0 * size.x, y / 100.0 * size.y)


func _u(v: float) -> float:
	return v / 100.0 * min(size.x, size.y)


func _bg(c: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), c)


func _circle(x: float, y: float, r: float, c: Color) -> void:
	draw_circle(_px(x, y), _u(r), c)


func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(_px(x, y), Vector2(w / 100.0 * size.x, h / 100.0 * size.y)), c)


func _tri(x1: float, y1: float, x2: float, y2: float, x3: float, y3: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([_px(x1, y1), _px(x2, y2), _px(x3, y3)]), c)


func _poly(pts: Array, c: Color) -> void:
	var arr := PackedVector2Array()
	for p in pts:
		arr.append(_px(p[0], p[1]))
	draw_colored_polygon(arr, c)


func _line(x1: float, y1: float, x2: float, y2: float, c: Color, w: float = 3.0) -> void:
	draw_line(_px(x1, y1), _px(x2, y2), c, _u(w))


func _eyes(x1: float, y1: float, x2: float, y2: float, r: float = 4.0) -> void:
	_circle(x1, y1, r, Color.WHITE)
	_circle(x2, y2, r, Color.WHITE)
	_circle(x1, y1, r * 0.45, Color.BLACK)
	_circle(x2, y2, r * 0.45, Color.BLACK)


# --- Art pieces ---

func _art_squirrel() -> void:
	_bg(Color(0.85, 0.72, 0.5))
	_tri(68, 78, 95, 25, 82, 82, Color(0.45, 0.28, 0.1))  # bushy tail
	_circle(48, 62, 26, Color(0.6, 0.38, 0.15))  # body
	_circle(46, 36, 17, Color(0.6, 0.38, 0.15))  # head
	_tri(34, 30, 28, 12, 44, 22, Color(0.6, 0.38, 0.15))
	_tri(58, 30, 64, 12, 48, 22, Color(0.6, 0.38, 0.15))
	_circle(42, 34, 2.5, Color.BLACK)
	_line(62, 20, 74, 48, Color(0.8, 0.8, 0.85), 3.0)  # tiny sword


func _art_squire() -> void:
	_bg(Color(0.6, 0.78, 0.95))
	_poly([[30, 85], [30, 45], [50, 28], [70, 45], [70, 85]], Color(0.15, 0.35, 0.85))  # shield
	_line(50, 42, 50, 72, Color(1, 1, 1), 3.0)
	_line(38, 55, 62, 55, Color(1, 1, 1), 3.0)
	_circle(50, 22, 12, Color(0.7, 0.7, 0.75))  # helmet


func _art_recruit() -> void:
	_bg(Color(0.75, 0.9, 0.6))
	_circle(50, 32, 15, Color(0.98, 0.8, 0.6))  # head
	_rect(35, 48, 30, 40, Color(0.5, 0.55, 0.65))  # armor
	_line(72, 20, 84, 78, Color(0.8, 0.8, 0.85), 4.0)  # sword
	_circle(45, 30, 2.5, Color.BLACK)
	_circle(55, 30, 2.5, Color.BLACK)


func _art_dog() -> void:
	_bg(Color(1.0, 0.9, 0.6))
	_tri(22, 38, 14, 10, 38, 24, Color(0.55, 0.35, 0.15))  # ear
	_tri(78, 38, 86, 10, 62, 24, Color(0.55, 0.35, 0.15))  # ear
	_circle(50, 55, 32, Color(0.85, 0.62, 0.35))  # head
	_circle(50, 68, 14, Color(0.98, 0.9, 0.75))  # snout
	_circle(50, 62, 5, Color.BLACK)  # nose
	_rect(42, 74, 16, 8, Color(1.0, 0.5, 0.6))  # tongue
	_eyes(38, 46, 62, 46, 5.0)


func _art_archer() -> void:
	_bg(Color(0.6, 0.85, 0.85))
	_line(20, 15, 20, 85, Color(0.5, 0.3, 0.1), 4.0)  # bow
	_line(20, 15, 48, 50, Color(0.5, 0.3, 0.1), 2.5)
	_line(20, 85, 48, 50, Color(0.5, 0.3, 0.1), 2.5)
	_line(20, 50, 90, 50, Color(0.8, 0.2, 0.2), 3.0)  # arrow (missing)
	_circle(62, 30, 13, Color(0.98, 0.8, 0.6))  # head, looking away
	_circle(80, 82, 3, Color.BLACK)  # the missed arrow, far away


func _art_wolf() -> void:
	_bg(Color(0.75, 0.7, 0.9))
	_tri(24, 36, 16, 8, 40, 22, Color(0.45, 0.45, 0.5))
	_tri(76, 36, 84, 8, 60, 22, Color(0.45, 0.45, 0.5))
	_circle(50, 55, 32, Color(0.6, 0.6, 0.65))
	_tri(30, 52, 18, 60, 32, 66, Color(0.95, 0.95, 0.95))  # snout
	_tri(70, 52, 82, 60, 68, 66, Color(0.95, 0.95, 0.95))
	_rect(38, 12, 26, 10, Color(1.0, 0.2, 0.2))  # tiny hat
	_rect(32, 20, 38, 4, Color(1.0, 0.2, 0.2))
	_eyes(40, 46, 60, 46, 4.5)


func _art_knight() -> void:
	_bg(Color(0.95, 0.75, 0.75))
	_poly([[35, 88], [35, 40], [50, 22], [65, 40], [65, 88]], Color(0.75, 0.75, 0.8))  # armor
	_line(50, 22, 62, 8, Color(1.0, 0.2, 0.2), 4.0)  # plume, flopping
	_circle(62, 8, 4, Color(1.0, 0.2, 0.2))
	_rect(30, 90, 40, 6, Color(0.5, 0.35, 0.2))  # ground
	_line(20, 70, 30, 88, Color(0.5, 0.35, 0.2), 3.0)  # fallen lance


func _art_brute() -> void:
	_bg(Color(1.0, 0.8, 0.6))
	_circle(28, 68, 20, Color(0.85, 0.55, 0.35))  # fist
	_circle(72, 68, 20, Color(0.85, 0.55, 0.35))  # fist
	_circle(50, 34, 18, Color(0.85, 0.55, 0.35))  # head
	_rect(38, 50, 24, 22, Color(0.6, 0.3, 0.2))  # body
	_eyes(44, 32, 56, 32, 3.5)


func _art_ogre() -> void:
	_bg(Color(0.7, 0.9, 0.6))
	_circle(50, 55, 30, Color(0.35, 0.7, 0.25))  # ogre blob
	_eyes(40, 48, 60, 48, 4.5)
	_rect(36, 62, 28, 4, Color(0.3, 0.3, 0.3))  # mouth
	_rect(70, 14, 20, 14, Color(1, 1, 1))  # diploma
	_circle(80, 30, 4, Color(1.0, 0.8, 0.1))  # seal


func _art_toddler() -> void:
	_bg(Color(1.0, 0.8, 0.85))
	_circle(50, 55, 34, Color(0.98, 0.82, 0.68))  # giant baby face
	_eyes(38, 48, 62, 48, 5.5)
	_circle(50, 70, 7, Color(0.9, 0.4, 0.7))  # pacifier
	_circle(50, 18, 5, Color(0.9, 0.7, 0.2))  # one hair curl


func _art_golem() -> void:
	_bg(Color(0.75, 0.75, 0.8))
	_poly([[30, 88], [35, 50], [50, 38], [65, 50], [70, 88]], Color(0.5, 0.5, 0.55))
	_poly([[38, 50], [50, 38], [62, 50], [50, 60]], Color(0.65, 0.65, 0.7))
	_circle(44, 46, 4, Color(1.0, 0.8, 0.1))
	_circle(56, 46, 4, Color(1.0, 0.8, 0.1))


func _art_dragon() -> void:
	_bg(Color(1.0, 0.7, 0.6))
	_tri(10, 60, 38, 25, 42, 68, Color(0.9, 0.2, 0.15))  # wing
	_tri(90, 60, 62, 25, 58, 68, Color(0.9, 0.2, 0.15))  # wing
	_circle(50, 62, 24, Color(0.2, 0.65, 0.3))  # body
	_circle(50, 36, 15, Color(0.2, 0.65, 0.3))  # head
	_circle(44, 34, 3, Color.BLACK)
	_circle(56, 34, 3, Color.BLACK)
	_tri(70, 50, 88, 44, 72, 58, Color(1.0, 0.6, 0.1))  # flame
	_rect(42, 78, 16, 10, Color(0.4, 0.4, 0.4))  # tiny briefcase


func _art_shield() -> void:
	_bg(Color(0.65, 0.8, 1.0))
	_poly([[28, 88], [28, 42], [50, 24], [72, 42], [72, 88], [50, 96]], Color(0.15, 0.35, 0.85))
	_poly([[36, 80], [36, 48], [50, 36], [64, 48], [64, 80], [50, 86]], Color(0.85, 0.9, 1.0))
	_line(50, 50, 50, 72, Color(0.15, 0.35, 0.85), 3.0)


func _art_wall() -> void:
	_bg(Color(0.85, 0.75, 0.6))
	for row in 4:
		for col in 3:
			_rect(14 + col * 26, 22 + row * 18, 24, 15, Color(0.75, 0.55, 0.4))
	_circle(50, 12, 5, Color.BLACK)  # a face peeking over the top


func _art_fortress() -> void:
	_bg(Color(0.6, 0.8, 1.0))
	_rect(18, 40, 22, 48, Color(0.65, 0.6, 0.55))
	_rect(60, 40, 22, 48, Color(0.65, 0.6, 0.55))
	_rect(38, 55, 24, 33, Color(0.75, 0.7, 0.65))
	for x in [18, 27, 60, 69]:
		_rect(x, 32, 7, 10, Color(0.65, 0.6, 0.55))
	_line(50, 55, 50, 22, Color(0.4, 0.3, 0.2), 2.5)
	_tri(50, 12, 62, 24, 50, 24, Color(1.0, 0.2, 0.2))  # flag


func _art_bolt() -> void:
	_bg(Color(0.2, 0.2, 0.3))
	_poly([[58, 8], [34, 55], [50, 55], [40, 92], [68, 42], [50, 42]], Color(1.0, 0.85, 0.1))


func _art_cavalry() -> void:
	_bg(Color(0.9, 0.85, 0.7))
	_poly([[30, 70], [30, 35], [48, 18], [62, 30], [58, 55], [48, 70]], Color(0.55, 0.35, 0.15))  # horse head
	_circle(40, 34, 3.5, Color.BLACK)
	_line(62, 30, 88, 30, Color(0.7, 0.2, 0.2), 3.0)
	_tri(88, 22, 88, 38, 78, 30, Color(0.9, 0.2, 0.2))  # flag


func _art_doctor() -> void:
	_bg(Color(0.8, 0.92, 1.0))
	_circle(50, 38, 20, Color(0.98, 0.85, 0.65))  # head
	_rect(44, 30, 12, 4, Color.WHITE)  # head mirror band
	_circle(50, 32, 4, Color(0.8, 0.8, 0.85))
	_rect(46, 60, 8, 20, Color(1.0, 0.2, 0.2))  # cross stem
	_rect(40, 66, 20, 8, Color(1.0, 0.2, 0.2))
	_eyes(44, 40, 56, 40, 3.5)


func _art_zap() -> void:
	_bg(Color(1.0, 0.9, 0.4))
	_poly([[58, 10], [36, 55], [50, 55], [42, 90], [66, 44], [50, 44]], Color(1.0, 0.6, 0.05))
	_circle(30, 78, 8, Color(0.2, 0.2, 0.25))  # goggles
	_circle(70, 78, 8, Color(0.2, 0.2, 0.25))
	_line(38, 78, 62, 78, Color(0.2, 0.2, 0.25), 3.0)


func _art_eye() -> void:
	_bg(Color(0.85, 0.8, 1.0))
	_circle(50, 45, 26, Color.WHITE)  # giant eye
	_circle(50, 45, 13, Color(0.2, 0.5, 0.9))
	_circle(50, 45, 6, Color.BLACK)
	_circle(50, 82, 10, Color(0.3, 0.3, 0.35))  # binoculars
	_circle(72, 82, 10, Color(0.3, 0.3, 0.35))


func _art_manager() -> void:
	_bg(Color(0.75, 0.8, 0.85))
	_circle(50, 30, 15, Color(0.98, 0.8, 0.6))  # head
	_rect(35, 48, 30, 40, Color(0.25, 0.35, 0.55))  # suit
	_poly([[46, 50], [54, 50], [50, 78]], Color(1.0, 0.2, 0.2))  # tie
	_rect(70, 60, 20, 26, Color(0.9, 0.85, 0.7))  # clipboard
	_circle(76, 54, 3, Color.BLACK)  # pen


func _art_fireball() -> void:
	_bg(Color(0.35, 0.1, 0.05))
	_circle(50, 55, 28, Color(1.0, 0.45, 0.05))
	_circle(50, 55, 17, Color(1.0, 0.75, 0.15))
	_tri(50, 8, 38, 30, 62, 30, Color(1.0, 0.85, 0.3))  # flame
	_tri(30, 20, 22, 38, 40, 36, Color(1.0, 0.6, 0.1))
	_tri(70, 20, 78, 38, 60, 36, Color(1.0, 0.6, 0.1))


func _art_heal() -> void:
	_bg(Color(0.75, 1.0, 0.85))
	_circle(50, 50, 30, Color(1.0, 0.95, 0.6))
	_rect(44, 30, 12, 40, Color(1.0, 0.9, 0.1))
	_rect(30, 44, 40, 12, Color(1.0, 0.9, 0.1))
	for a in [0, 45, 90, 135, 180, 225, 270, 315]:
		var rad := deg_to_rad(float(a))
		_line(50, 50, 50 + cos(rad) * 42, 50 + sin(rad) * 42, Color(1.0, 0.95, 0.5), 2.0)


func _art_cookie() -> void:
	_bg(Color(0.9, 0.8, 0.6))
	_circle(45, 52, 28, Color(0.75, 0.5, 0.25))  # cookie
	_circle(36, 44, 3, Color(0.25, 0.15, 0.05))
	_circle(54, 60, 3, Color(0.25, 0.15, 0.05))
	_circle(46, 66, 3, Color(0.25, 0.15, 0.05))
	_rect(60, 30, 26, 16, Color(1, 1, 1))  # fortune paper
	_line(64, 38, 82, 38, Color(0.2, 0.2, 0.2), 1.5)


func _art_nova() -> void:
	_bg(Color(0.25, 0.05, 0.4))
	for a in [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330]:
		var rad := deg_to_rad(float(a))
		_line(50, 50, 50 + cos(rad) * 40, 50 + sin(rad) * 40, Color(1.0, 0.4, 0.9), 3.0)
	_circle(50, 50, 14, Color(1.0, 0.85, 0.2))
	_circle(50, 50, 6, Color.WHITE)


func _art_dagger() -> void:
	_bg(Color(0.3, 0.3, 0.35))
	_poly([[50, 10], [56, 55], [50, 68], [44, 55]], Color(0.85, 0.85, 0.9))  # blade
	_rect(40, 68, 20, 8, Color(0.5, 0.35, 0.1))  # guard
	_rect(46, 76, 8, 16, Color(0.35, 0.2, 0.05))  # handle
	_rect(20, 18, 60, 12, Color(0.1, 0.1, 0.12))  # mask
	_circle(35, 24, 3, Color(1.0, 0.9, 0.2))
	_circle(65, 24, 3, Color(1.0, 0.9, 0.2))


func _art_roulette() -> void:
	_bg(Color(0.1, 0.45, 0.25))
	_circle(50, 52, 34, Color(0.85, 0.75, 0.55))  # wheel rim
	for i in 8:
		var a1 := deg_to_rad(float(i * 45))
		var a2 := deg_to_rad(float(i * 45 + 45))
		var c := Color(1.0, 0.2, 0.2) if i % 2 == 0 else Color(0.1, 0.1, 0.1)
		_poly([[50, 52], [50 + cos(a1) * 28, 52 + sin(a1) * 28], [50 + cos(a2) * 28, 52 + sin(a2) * 28]], c)
	_circle(50, 52, 6, Color(1, 1, 1))
	_circle(50, 14, 4, Color(1, 1, 1))  # ball


func _art_mind() -> void:
	_bg(Color(0.55, 0.3, 0.85))
	_circle(50, 50, 26, Color(0.85, 0.6, 1.0))  # swirl base
	_circle(42, 44, 14, Color(0.55, 0.3, 0.85))
	_circle(42, 44, 6, Color(1, 1, 1))
	_circle(68, 68, 10, Color(0.98, 0.8, 0.6))  # hand
	_rect(64, 74, 8, 16, Color(0.98, 0.8, 0.6))


func _art_hands() -> void:
	_bg(Color(1.0, 0.75, 0.8))
	_rect(14, 40, 26, 22, Color(0.98, 0.8, 0.6))  # hand 1
	_rect(60, 40, 26, 22, Color(0.75, 0.85, 1.0))  # hand 2
	_line(40, 30, 60, 30, Color(0.9, 0.2, 0.2), 3.0)  # swap arrow
	_tri(60, 30, 50, 22, 50, 38, Color(0.9, 0.2, 0.2))
	_line(60, 72, 40, 72, Color(0.2, 0.4, 0.9), 3.0)
	_tri(40, 72, 50, 64, 50, 80, Color(0.2, 0.4, 0.9))


func _art_coin() -> void:
	_bg(Color(0.35, 0.25, 0.05))
	_circle(50, 52, 32, Color(1.0, 0.8, 0.1))
	_circle(50, 52, 24, Color(0.95, 0.7, 0.05))
	_circle(50, 40, 6, Color(1.0, 0.95, 0.6))  # heads
	_circle(50, 64, 6, Color(0.4, 0.2, 0.0))  # tails
	_line(50, 10, 50, 22, Color(1.0, 0.8, 0.1), 2.0)  # sparkle


func _art_intern() -> void:
	_bg(Color(0.9, 0.88, 0.8))
	_rect(18, 60, 64, 8, Color(0.6, 0.45, 0.25))  # desk
	_rect(24, 68, 6, 22, Color(0.6, 0.45, 0.25))
	_rect(70, 68, 6, 22, Color(0.6, 0.45, 0.25))
	_circle(50, 36, 12, Color(0.98, 0.8, 0.6))  # tiny head
	_rect(40, 48, 20, 14, Color(0.7, 0.75, 0.8))  # tiny body
	_rect(68, 48, 8, 12, Color(1.0, 0.4, 0.2))  # coffee cup
	_line(72, 48, 72, 42, Color(0.8, 0.8, 0.8), 1.5)


func _art_fallback() -> void:
	_bg(Color(0.6, 0.6, 0.6))
	_circle(50, 50, 25, Color(1.0, 0.85, 0.2))
	_circle(50, 50, 12, Color(1.0, 0.6, 0.1))


# --- Generic hash-based art (covers all 340 cards.json art ids) ---
# Deterministic per id: background hue + three shapes + a big initial
# letter, so every card has distinct, non-blank art with no asset files.

func _art_generic() -> void:
	var h: int = abs(int(art_id.hash()))
	var hue: float = float(h % 360) / 360.0
	var bg: Color = Color.from_hsv(hue, 0.45, 0.85)
	_bg(bg)
	var c1: Color = Color.from_hsv(fmod(hue + 0.35, 1.0), 0.8, 0.9)
	var c2: Color = Color.from_hsv(fmod(hue + 0.7, 1.0), 0.8, 0.55)
	var shape: int = (h >> 8) % 3
	if shape == 0:
		_circle(38, 42, 26, c1)
		_circle(62, 58, 22, c2)
	elif shape == 1:
		_tri(50, 14, 18, 78, 82, 78, c1)
		_circle(50, 58, 16, c2)
	else:
		_rect(18, 22, 64, 56, c1)
		_circle(50, 50, 16, c2)
	_eyes(40, 40, 60, 40, 4.0)
	var letter: String = art_id.substr(0, 1).to_upper()
	if not letter.is_empty():
		var font: Font = ThemeDB.get_fallback_font()
		var fs: int = int(min(size.x, size.y) * 0.42)
		var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, _px(50, 88) - Vector2(sz.x / 2.0, 0), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.9))


# --- Hero portraits (procedural, one per class) ---

func _art_hero_grunk() -> void:
	_bg(Color(0.25, 0.35, 0.1))  # green goblin demolitionist
	_circle(50, 52, 30, Color(0.3, 0.65, 0.15))  # goblin head
	_tri(24, 36, 14, 10, 38, 22, Color(0.3, 0.65, 0.15))
	_tri(76, 36, 86, 10, 62, 22, Color(0.3, 0.65, 0.15))
	_eyes(40, 48, 60, 48, 5.0)
	_rect(40, 64, 20, 5, Color.BLACK)  # grin
	_circle(78, 78, 10, Color(1.0, 0.3, 0.1))  # firecracker
	_line(78, 68, 78, 60, Color(0.9, 0.8, 0.2), 2.0)


func _art_hero_agatha() -> void:
	_bg(Color(0.95, 0.85, 0.7))  # grandma, soup
	_circle(50, 46, 28, Color(0.95, 0.85, 0.7))  # face
	_circle(50, 30, 30, Color(0.9, 0.9, 0.92))  # hair bun
	_circle(50, 18, 10, Color(0.9, 0.9, 0.92))
	_eyes(40, 46, 60, 46, 4.0)
	_rect(44, 58, 12, 3, Color(0.6, 0.2, 0.2))  # smile
	_circle(50, 82, 16, Color(0.85, 0.5, 0.2))  # soup pot
	_rect(36, 74, 28, 5, Color(0.6, 0.3, 0.1))


func _art_hero_presto() -> void:
	_bg(Color(0.15, 0.2, 0.6))  # blue wizard apprentice
	_tri(50, 6, 26, 56, 74, 56, Color(0.25, 0.15, 0.6))  # wizard hat
	_circle(50, 24, 6, Color(1.0, 0.85, 0.2))  # star
	_circle(50, 62, 26, Color(0.98, 0.8, 0.6))  # face
	_eyes(42, 58, 58, 58, 4.5)
	_rect(44, 72, 12, 3, Color(0.5, 0.2, 0.1))
	_line(76, 40, 86, 78, Color(0.6, 0.4, 0.2), 3.0)  # wand


func _art_hero_barnacle() -> void:
	_bg(Color(0.05, 0.35, 0.5))  # pirate queen
	_tri(50, 8, 22, 42, 78, 42, Color(0.1, 0.1, 0.15))  # pirate hat
	_circle(50, 58, 26, Color(0.98, 0.8, 0.6))  # face
	_circle(60, 54, 7, Color(0.1, 0.1, 0.1))  # eyepatch
	_circle(40, 54, 3.5, Color.BLACK)
	_rect(42, 68, 14, 3, Color(0.5, 0.1, 0.1))
	_circle(22, 30, 8, Color(0.2, 0.7, 0.2))  # parrot
	_circle(24, 28, 2, Color.BLACK)


func _art_hero_reginald() -> void:
	_bg(Color(0.85, 0.7, 0.15))  # gold knight
	_poly([[30, 88], [30, 40], [50, 20], [70, 40], [70, 88]], Color(0.9, 0.85, 0.6))  # armor
	_line(50, 20, 62, 6, Color(1.0, 0.2, 0.2), 4.0)  # plume
	_circle(62, 6, 4, Color(1.0, 0.2, 0.2))
	_rect(42, 48, 16, 22, Color(0.95, 0.8, 0.2))  # shield emblem
	_line(50, 50, 50, 68, Color(0.6, 0.4, 0.05), 2.5)
	_line(44, 59, 56, 59, Color(0.6, 0.4, 0.05), 2.5)


func _art_hero_larry() -> void:
	_bg(Color(0.2, 0.05, 0.35))  # gambler
	_circle(50, 56, 28, Color(0.98, 0.8, 0.6))  # face
	_eyes(40, 52, 60, 52, 4.0)
	_rect(40, 66, 20, 4, Color(0.2, 0.2, 0.2))  # smirk
	_rect(14, 10, 22, 30, Color.WHITE)  # card
	_circle(25, 25, 5, Color(1.0, 0.2, 0.2))
	_circle(78, 82, 12, Color.WHITE)  # die
	_circle(74, 78, 2, Color.BLACK)
	_circle(82, 86, 2, Color.BLACK)
	_circle(78, 82, 2, Color.BLACK)


func _art_deckhand() -> void:
	_bg(Color(0.2, 0.55, 0.7))
	_circle(50, 38, 16, Color(0.98, 0.8, 0.6))
	_rect(34, 56, 32, 32, Color(0.9, 0.9, 0.95))  # sailor shirt
	_rect(28, 22, 44, 8, Color(0.1, 0.2, 0.5))  # sailor hat
	_rect(24, 30, 52, 3, Color(0.1, 0.2, 0.5))
	_eyes(44, 38, 56, 38, 3.5)


func _art_token() -> void:
	_bg(Color(0.85, 0.85, 0.8))
	_circle(50, 50, 28, Color(0.7, 0.7, 0.75))
	_circle(50, 50, 16, Color(0.95, 0.85, 0.4))
