extends Control
class_name CardFace

# The reworked card: dark frame in the card's class color, the painting
# up top, a cost gem, a class-colored name ribbon with a rarity gem, a
# rules box with bold keywords, and attack / health badges for minions.
# Built at any size; everything scales from BASE (200 x 280).

const BASE := Vector2(200, 280)
const COST_BLUE := Color(0.20, 0.48, 1.0)
const ATK_COL := Color(0.95, 0.62, 0.10)
const HP_COL := Color(0.88, 0.16, 0.22)
const PARCHMENT := Color(0.97, 0.94, 0.86)
const RARITY_COL: Dictionary = {
	"Common": Color(0.9, 0.9, 0.92),
	"Rare": Color(0.25, 0.55, 1.0),
	"Epic": Color(0.72, 0.30, 1.0),
	"Legendary": Color(1.0, 0.62, 0.08),
}
const KEYWORDS: Array = ["Entrance:", "Final Bow:", "Bouncer", "Hustle"]

var card: Dictionary = {}
var dim: bool = false  # greyed out (e.g. no copies left)
var _art: CardArt
var _rules: RichTextLabel
var _top: Control  # draws ribbon, gems and stats ABOVE the painting


func set_dim(v: bool) -> void:
	if dim == v:
		return
	dim = v
	queue_redraw()
	if _top != null:
		_top.queue_redraw()


static func make(c: Dictionary, sz: Vector2 = BASE) -> CardFace:
	var f := CardFace.new()
	f.card = c
	f.custom_minimum_size = sz
	f.size = sz
	return f


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_art = CardArt.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.card_id = str(card.get("id", ""))
	_art.art_id = str(card.get("art", ""))
	add_child(_art)
	_rules = RichTextLabel.new()
	_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules.bbcode_enabled = true
	_rules.scroll_active = false
	_rules.fit_content = false
	_rules.add_theme_font_override("normal_font", UIKit.font(UIKit.FONT_BODY_PATH))
	_rules.add_theme_font_override("bold_font", UIKit.font("res://fonts/Inter-Black.otf"))
	_rules.add_theme_color_override("default_color", Color(0.12, 0.08, 0.14))
	_rules.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_rules)
	_top = Control.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.draw.connect(_draw_top)
	add_child(_top)
	resized.connect(_layout)
	_layout()


func _k() -> float:
	return size.x / BASE.x


func _class_col() -> Color:
	return UIKit.CLASS_COLOR.get(str(card.get("class", "")), Color(0.75, 0.62, 0.42))


func _art_rect() -> Rect2:
	var k: float = _k()
	return Rect2(Vector2(10, 10) * k, Vector2(BASE.x - 20, 138) * k)


func _rules_rect() -> Rect2:
	var k: float = _k()
	var bottom_pad: float = 26.0 if str(card.get("type", "")) == "minion" else 14.0
	return Rect2(Vector2(16, 178) * k, Vector2(BASE.x - 32, BASE.y - 178 - bottom_pad) * k)


func _layout() -> void:
	if _art == null:
		return
	var k: float = _k()
	var ar: Rect2 = _art_rect()
	_art.position = ar.position
	_art.size = ar.size
	var rr: Rect2 = _rules_rect()
	_rules.position = rr.position
	_rules.size = rr.size
	var txt: String = str(card.get("text", ""))
	if txt.is_empty():
		txt = "[i]%s[/i]" % str(card.get("flavor", ""))
	for kw in KEYWORDS:
		txt = txt.replace(kw, "[b]%s[/b]" % kw)
	var fs: int = int(round((13.0 if txt.length() < 70 else 11.5) * k))
	_rules.add_theme_font_size_override("normal_font_size", fs)
	_rules.add_theme_font_size_override("bold_font_size", fs)
	_rules.add_theme_font_size_override("italics_font_size", fs)
	_rules.text = "[center]%s[/center]" % txt
	_top.size = size
	queue_redraw()
	_top.queue_redraw()


func _draw() -> void:
	var k: float = _k()
	var col: Color = _class_col()
	var full := Rect2(Vector2.ZERO, size)
	# Drop shadow + frame.
	_rr(Rect2(Vector2(4, 6) * k, size), Color(0, 0, 0, 0.45), 14 * k)
	_rr(full, UIKit.INK, 14 * k)
	_rr(full.grow(-3 * k), col.darkened(0.15), 12 * k)
	_rr(full.grow(-7 * k), col.darkened(0.72), 9 * k)
	# Art border (painted by the CardArt child on top of this).
	var ar: Rect2 = _art_rect()
	_rr(ar.grow(3 * k), UIKit.INK, 6 * k)
	# Rules box.
	var rr: Rect2 = _rules_rect().grow_individual(4 * k, 18 * k, 4 * k, 4 * k)
	_rr(rr.grow(2.5 * k), UIKit.INK, 9 * k)
	_rr(rr, PARCHMENT, 8 * k)


func _draw_top() -> void:
	var k: float = _k()
	var col: Color = _class_col()
	var full := Rect2(Vector2.ZERO, size)
	# Name ribbon across the bottom of the art.
	var rib := Rect2(Vector2(6, 136) * k, Vector2(BASE.x - 12, 34) * k)
	var skew: float = 6.0 * k
	var pts := PackedVector2Array([rib.position + Vector2(skew, 0), rib.position + Vector2(rib.size.x, 0), rib.end - Vector2(skew, 0), rib.position + Vector2(0, rib.size.y)])
	var pts_out := PackedVector2Array()
	var c0: Vector2 = rib.get_center()
	for p in pts:
		pts_out.append(c0 + (p - c0) * Vector2(1.0 + 4.0 * k / rib.size.x, 1.0 + 5.0 * k / rib.size.y))
	_top.draw_colored_polygon(pts_out, UIKit.INK)
	_top.draw_colored_polygon(pts, col)
	_top.draw_line(rib.position + Vector2(skew + 4 * k, 4 * k), Vector2(rib.end.x - 6 * k, rib.position.y + 4 * k), Color(1, 1, 1, 0.35), 2.0 * k)
	var name_s: String = str(card.get("name", ""))
	var nfont: Font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	var nsz: int = int(17 * k)
	while nsz > 7 and nfont.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x > rib.size.x - 24 * k:
		nsz -= 1
	var npos := Vector2(rib.position.x + 12 * k, rib.get_center().y + nsz * 0.36)
	_top.draw_string_outline(nfont, npos, name_s, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x - 24 * k, nsz, max(2, int(3.5 * k)), UIKit.INK)
	_top.draw_string(nfont, npos, name_s, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x - 24 * k, nsz, Color.WHITE)
	# Rarity gem under the ribbon.
	var rcol: Color = RARITY_COL.get(str(card.get("rarity", "Common")), Color.WHITE)
	var gc := Vector2(BASE.x * 0.5, 174) * k
	var diamond := PackedVector2Array([gc + Vector2(0, -7) * k, gc + Vector2(8, 0) * k, gc + Vector2(0, 7) * k, gc + Vector2(-8, 0) * k])
	var dout := PackedVector2Array()
	for p in diamond:
		dout.append(gc + (p - gc) * 1.45)
	_top.draw_colored_polygon(dout, UIKit.INK)
	_top.draw_colored_polygon(diamond, rcol)
	# Cost gem.
	_gem(Vector2(22, 22) * k, 19 * k, COST_BLUE, str(int(card.get("cost", 0))), 22 * k, _top)
	# Stats.
	if str(card.get("type", "")) == "minion":
		_gem(Vector2(22, BASE.y - 22) * k, 19 * k, ATK_COL, str(int(card.get("attack", 0))), 21 * k, _top)
		_gem(Vector2(BASE.x - 22, BASE.y - 22) * k, 19 * k, HP_COL, str(int(card.get("health", 0))), 21 * k, _top)
	else:
		var tag := "TRICK"
		var tf: Font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
		var ts: int = int(13 * k)
		var tp := Vector2(0, BASE.y - 7) * k
		_top.draw_string_outline(tf, tp, tag, HORIZONTAL_ALIGNMENT_CENTER, size.x, ts, int(4 * k), UIKit.INK)
		_top.draw_string(tf, tp, tag, HORIZONTAL_ALIGNMENT_CENTER, size.x, ts, col.lightened(0.4))
	if dim:
		_rr(full, Color(0, 0, 0, 0.55), 14 * k, _top)



func _gem(c: Vector2, r: float, fill: Color, text: String, fsize: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	ci.draw_circle(c + Vector2(2, 3) * _k(), r + 3.0 * _k(), Color(0, 0, 0, 0.45))
	ci.draw_circle(c, r + 3.5 * _k(), UIKit.INK)
	ci.draw_circle(c, r, fill)
	ci.draw_circle(c - Vector2(0, r * 0.35), r * 0.55, Color(1, 1, 1, 0.22))
	var f: Font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	var fs: int = int(fsize)
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(c.x - w * 0.5, c.y + fs * 0.36)
	ci.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5 * _k()), UIKit.INK)
	ci.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _rr(r: Rect2, c: Color, rad: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)
