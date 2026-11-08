extends Control
class_name CardFrame

# A card, drawn in code (frame, gems, ribbon, art window) with the rules
# text in a RichTextLabel (keywords in bold). Two looks, for review:
#   GILDED  gold-framed, painted-card feel: arched art window, class
#           ribbon for the name, parchment text plate, cut-gem cost /
#           attack / health. Same family as the Boss cards and END TURN.
#   HOLO    the hologram language of the battlefield: dark glass, a neon
#           edge in the class color, hex gems, scanlines over the art.
# Size is free; everything scales off the width (designed at 250 px).

enum Look { GILDED, HOLO }

const BASE_W := 250.0
const ASPECT := 1.45   # height / width

var card: Dictionary = {}
var look: int = Look.GILDED
var _tex: Texture2D = null
var _rules: RichTextLabel = null
var _flavor: Label = null
var _font: Font
var _body: Font
var _t: float = 0.0


func setup(c: Dictionary, l: int, width: float) -> void:
	card = c
	look = l
	size = Vector2(width, width * ASPECT)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	_body = UIKit.font(UIKit.FONT_BODY_PATH)
	_tex = CardArt.texture_for(str(c.get("id", "")))
	if _tex == null:
		_tex = _fallback_art()
	if _rules == null:
		_rules = RichTextLabel.new()
		_rules.name = "RulesLabel"
		_rules.bbcode_enabled = true
		_rules.fit_content = false
		_rules.scroll_active = false
		_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rules.add_theme_font_override("normal_font", UIKit.font(UIKit.FONT_BODY_LIGHT_PATH))
		_rules.add_theme_font_override("bold_font", UIKit.font("res://fonts/Inter-Black.otf"))
		add_child(_rules)
	if _flavor == null and _big() and str(card.get("flavor", "")) != "":
		_flavor = Label.new()
		_flavor.name = "FlavorLabel"
		_flavor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_flavor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_flavor.add_theme_font_override("font", UIKit.font(UIKit.FONT_BODY_LIGHT_PATH))
		_flavor.add_theme_color_override("font_color", Color(0.42, 0.3, 0.18))
		add_child(_flavor)
	if _flavor != null:
		_flavor.text = str(card.get("flavor", ""))
	_layout_rules()
	queue_redraw()


func _ready() -> void:
	# RichTextLabel measures properly once it's in the tree.
	if not card.is_empty():
		_layout_rules.call_deferred()


# Big cards (inspect / magnify) also show the flavor line.
func _big() -> bool:
	return size.x >= 280.0


# A card with no painting yet (e.g. a token) shows its drawn placeholder,
# rendered once into a texture so it clips to the art window.
func _fallback_art() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 382)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var art := CardArt.new()
	art.art_id = str(card.get("art", ""))
	art.card_id = str(card.get("id", ""))
	art.size = Vector2(256, 382)
	vp.add_child(art)
	add_child(vp)
	return vp.get_texture()


func _k() -> float:
	return size.x / BASE_W


func _process(delta: float) -> void:
	_t += delta
	if look == Look.HOLO:
		queue_redraw()


func _is_crew() -> bool:
	return str(card.get("type", "")) == "minion"


func _class_color() -> Color:
	var cls: String = str(card.get("class", "neutral"))
	return UIKit.CLASS_COLOR.get(cls, Color(0.75, 0.72, 0.68))


func _rarity_color() -> Color:
	match str(card.get("rarity", "Common")):
		"Rare": return Color(0.3, 0.6, 1.0)
		"Epic": return Color(0.75, 0.35, 1.0)
		"Legendary": return Color(1.0, 0.6, 0.1)
	return Color(0.85, 0.85, 0.85)


func _rules_bbcode() -> String:
	var t: String = str(card.get("text", ""))
	for kw in ["Entrance:", "Final Bow:", "Taunt", "Bouncer", "Rush", "Charge", "Ward", "Shield"]:
		t = t.replace(kw, "[b]%s[/b]" % kw)
	return "[center]%s[/center]" % t


# Where the text plate sits, per look.
func _text_rect() -> Rect2:
	var k: float = _k()
	if look == Look.GILDED:
		return Rect2(Vector2(26, 222) * k, Vector2(198, 108) * k)
	return Rect2(Vector2(22, 222) * k, Vector2(206, 110) * k)


func _layout_rules() -> void:
	if _rules == null:
		return
	var r: Rect2 = _text_rect()
	if _flavor != null:
		var fr := Rect2(Vector2(r.position.x, r.position.y + r.size.y * 0.66), Vector2(r.size.x, r.size.y * 0.34))
		r.size.y *= 0.64
		_flavor.position = fr.position
		_flavor.size = fr.size
		_flavor.add_theme_font_size_override("font_size", maxi(int(11 * _k()), 9))
	_rules.position = r.position
	_rules.size = r.size
	_rules.text = _rules_bbcode()
	var dark: bool = look == Look.HOLO
	_rules.add_theme_color_override("default_color", Color(0.92, 0.95, 1.0) if dark else Color(0.16, 0.1, 0.06))
	var fs: int = int(17 * _k())
	while fs > 8:
		_rules.add_theme_font_size_override("normal_font_size", fs)
		_rules.add_theme_font_size_override("bold_font_size", fs)
		if _rules.get_content_height() <= r.size.y - 4.0 * _k():
			break
		fs -= 1
	# Centre vertically.
	var ch: float = _rules.get_content_height()
	_rules.position.y = r.position.y + maxf(0.0, (r.size.y - ch) * 0.5)
	_rules.size.y = minf(r.size.y, ch + 4.0)


func _draw() -> void:
	if card.is_empty():
		return
	if look == Look.GILDED:
		_draw_gilded()
	else:
		_draw_holo()


# --- shared bits ---

func _poly_round_top(r: Rect2, rad: float, segs: int = 10) -> PackedVector2Array:
	# Rect with an arched (rounded) top edge and square bottom corners.
	rad = minf(rad, r.size.x * 0.5 - 1.0)  # arcs must not meet (triangulation)
	var pts := PackedVector2Array()
	pts.append(Vector2(r.position.x, r.end.y))
	pts.append(Vector2(r.position.x, r.position.y + rad))
	for i in segs + 1:
		var a: float = PI + PI * 0.5 * i / segs
		pts.append(Vector2(r.position.x + rad, r.position.y + rad) + Vector2(cos(a), sin(a)) * rad)
	for i in segs + 1:
		var a2: float = PI * 1.5 + PI * 0.5 * i / segs
		pts.append(Vector2(r.end.x - rad, r.position.y + rad) + Vector2(cos(a2), sin(a2)) * rad)
	pts.append(Vector2(r.end.x, r.end.y))
	return pts


func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])


func _art(dst: Rect2, mask: PackedVector2Array) -> void:
	if _tex == null:
		draw_colored_polygon(mask, _class_color().darkened(0.6))
		return
	# Cover-crop the art into dst, then draw it through the mask polygon
	# with UVs (so arched / cut windows clip cleanly).
	var ts: Vector2 = _tex.get_size()
	var sc: float = maxf(dst.size.x / ts.x, dst.size.y / ts.y)
	var src_size: Vector2 = dst.size / sc
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * 0.3)
	var uvs := PackedVector2Array()
	for v in mask:
		var f: Vector2 = (v - dst.position) / dst.size
		uvs.append((src_pos + f * src_size) / ts)
	draw_colored_polygon(mask, Color.WHITE, uvs, _tex)


func _ink(poly: PackedVector2Array, w: float) -> void:
	var p := poly.duplicate()
	p.append(poly[0])
	draw_polyline(p, UIKit.INK, maxf(w, 1.0), true)


func _text(f: Font, pos: Vector2, s: String, fs: int, col: Color, outline: int, center_w: float = -1.0) -> void:
	var p := pos
	if center_w > 0.0:
		p.x += (center_w - f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) * 0.5
	if outline > 0:
		draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, UIKit.INK)
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# The card name in a box: one line if it fits at a readable size, else
# two balanced lines.
func _name_text(box: Rect2, fs: int) -> void:
	var k: float = _k()
	var nm: String = str(card.get("name", ""))
	var nf: Font = UIKit.font("res://fonts/Inter-Black.otf")
	var one: int = _fit(nf, nm, fs, box.size.x)
	var words: PackedStringArray = nm.split(" ")
	if one >= int(fs * 0.8) or words.size() < 2:
		_text(nf, Vector2(box.position.x, box.get_center().y + one * 0.36), nm, one, Color.WHITE, int(6 * k), box.size.x)
		return
	var best: int = 1
	var best_d: float = 1e9
	for i in range(1, words.size()):
		var a: String = " ".join(words.slice(0, i))
		var b: String = " ".join(words.slice(i))
		var d: float = absf(nf.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - nf.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if d < best_d:
			best_d = d
			best = i
	var l1: String = " ".join(words.slice(0, best))
	var l2: String = " ".join(words.slice(best))
	var two: int = mini(_fit(nf, l1, int(15 * k), box.size.x), _fit(nf, l2, int(15 * k), box.size.x))
	var cy: float = box.get_center().y
	_text(nf, Vector2(box.position.x, cy - 1 * k), l1, two, Color.WHITE, int(5 * k), box.size.x)
	_text(nf, Vector2(box.position.x, cy + two * 0.95), l2, two, Color.WHITE, int(5 * k), box.size.x)


func _fit(f: Font, s: String, fs: int, w: float) -> int:
	var n: int = fs
	while n > 8 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x > w:
		n -= 1
	return n


func _gem_poly(c: Vector2, r: float, sides: int, rot: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in sides:
		var a: float = rot + TAU * i / sides
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


func _scaled(p: PackedVector2Array, c: Vector2, f: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for v in p:
		o.append(c + (v - c) * f)
	return o


# A cut gem with a number: rim, body, top facet highlight.
func _num_gem(c: Vector2, r: float, sides: int, rot: float, body: Color, rim: Color, n: String, fs: int) -> void:
	var g := _gem_poly(c, r, sides, rot)
	draw_colored_polygon(_scaled(g, c + Vector2(0, 3) * _k(), 1.08), Color(0, 0, 0, 0.45))
	draw_colored_polygon(_scaled(g, c, 1.22), UIKit.INK)
	draw_colored_polygon(_scaled(g, c, 1.16), rim.darkened(0.35))
	draw_colored_polygon(_scaled(g, c, 1.08), rim)
	draw_colored_polygon(g, body)
	var hi := PackedVector2Array([c])
	for i in sides:
		var v: Vector2 = g[i]
		if v.y < c.y + 0.1 * r:
			hi.append(v)
	if hi.size() >= 3:
		draw_colored_polygon(_scaled(g, c + Vector2(0, -r * 0.18), 0.6), body.lightened(0.28))
	_text(_font, Vector2(c.x - r, c.y + fs * 0.38), n, fs, Color.WHITE, int(7 * _k()), r * 2.0)


# --- GILDED ---

func _draw_gilded() -> void:
	var k: float = _k()
	var W: float = size.x
	var H: float = size.y
	var col: Color = _class_color()
	var gold: Color = UIKit.GOLD
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.3)
	var full := Rect2(Vector2.ZERO, size)
	var crew: bool = _is_crew()
	# Body + frame.
	var sh := _chamfer(full.grow(-1), 16 * k)
	for i in sh.size():
		sh[i] += Vector2(0, 6) * k
	draw_colored_polygon(sh, Color(0, 0, 0, 0.5))
	draw_colored_polygon(_chamfer(full, 16 * k), gold_d)
	draw_colored_polygon(_chamfer(full.grow(-2.5 * k), 15 * k), gold)
	var up := PackedVector2Array()
	for v in _chamfer(full.grow(-2.5 * k), 15 * k):
		up.append(Vector2(v.x, minf(v.y, H * 0.4)))
	draw_colored_polygon(up, gold.lightened(0.3))
	draw_colored_polygon(_chamfer(full.grow(-6 * k), 13 * k), gold_d)
	# Inner body: the class color, dark, with a lighter centre.
	var inner := _chamfer(full.grow(-8 * k), 12 * k)
	draw_colored_polygon(inner, col.darkened(0.72))
	# Thin ink lines on the gilding (outer edge and inner edge) so the
	# gold pops off anything behind it.
	_ink(_chamfer(full.grow(-0.5 * k), 16 * k), 1.6 * k)
	_ink(inner, 1.4 * k)
	draw_colored_polygon(_chamfer(full.grow(-20 * k), 8 * k), col.darkened(0.6))
	# Art window: arched for Crew, cut corners for Tricks.
	var aw := Rect2(Vector2(18, 18) * k, Vector2(W - 36 * k, 190 * k))
	var mask: PackedVector2Array = _poly_round_top(aw, aw.size.x * 0.5, 18) if crew else _chamfer(aw, 18 * k)
	var outer: PackedVector2Array = _poly_round_top(aw.grow(4 * k), aw.size.x * 0.5 + 4 * k, 18) if crew else _chamfer(aw.grow(4 * k), 20 * k)
	draw_colored_polygon(outer, gold_d)
	draw_colored_polygon(_poly_round_top(aw.grow(2.5 * k), aw.size.x * 0.5 + 2.5 * k, 18) if crew else _chamfer(aw.grow(2.5 * k), 19 * k), gold)
	_art(aw, mask)
	_ink(outer, 1.4 * k)
	_ink(mask, 1.2 * k)
	# Text plate: parchment.
	var tr := Rect2(Vector2(20, 214) * k, Vector2(W - 40 * k, 126 * k))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.87, 0.74)
	sb.set_corner_radius_all(int(10 * k))
	sb.border_color = gold_d
	sb.set_border_width_all(int(maxf(2.0, 2.5 * k)))
	draw_style_box(sb, tr)
	var ink_sb := StyleBoxFlat.new()
	ink_sb.draw_center = false
	ink_sb.set_corner_radius_all(int(11 * k))
	ink_sb.border_color = UIKit.INK
	ink_sb.set_border_width_all(maxi(1, int(1.3 * k)))
	draw_style_box(ink_sb, tr.grow(1.0 * k))
	draw_rect(Rect2(tr.position + Vector2(4, 4) * k, Vector2(tr.size.x - 8 * k, tr.size.y * 0.35)), Color(1, 1, 1, 0.18))
	# Name ribbon across the bottom of the art.
	var ry: float = 188 * k
	var rib := Rect2(Vector2(6 * k, ry), Vector2(W - 12 * k, 34 * k))
	var nt: float = 11 * k
	var rib_pts := PackedVector2Array([rib.position + Vector2(0, 0), Vector2(rib.end.x, rib.position.y), Vector2(rib.end.x - nt, rib.position.y + rib.size.y * 0.5),
		Vector2(rib.end.x, rib.end.y), Vector2(rib.position.x, rib.end.y), Vector2(rib.position.x + nt, rib.position.y + rib.size.y * 0.5)])
	var rs := PackedVector2Array()
	for v in rib_pts:
		rs.append(v + Vector2(0, 3) * k)
	draw_colored_polygon(rs, Color(0, 0, 0, 0.45))
	draw_colored_polygon(rib_pts, col.darkened(0.45))
	var rin := _scaled(rib_pts, rib.get_center(), 1.0)
	var top_half := PackedVector2Array()
	for v in rin:
		top_half.append(Vector2(v.x, minf(v.y, rib.get_center().y)))
	draw_colored_polygon(top_half, col.darkened(0.15))
	var rl := rib_pts.duplicate()
	rl.append(rib_pts[0])
	draw_polyline(rl, UIKit.INK, 4.2 * k, true)
	draw_polyline(rl, gold, 2.0 * k, true)
	_name_text(Rect2(rib.position + Vector2(nt * 1.5, 0), Vector2(rib.size.x - nt * 3.0, rib.size.y)), int(18 * k))
	# Rarity jewel on top of the ribbon.
	var jc := Vector2(W * 0.5, ry - 1 * k)
	var jr: float = 7 * k
	var jw := PackedVector2Array([jc + Vector2(0, -jr), jc + Vector2(jr, 0), jc + Vector2(0, jr), jc + Vector2(-jr, 0)])
	draw_colored_polygon(_scaled(jw, jc, 1.35), gold_d)
	draw_colored_polygon(jw, _rarity_color())
	draw_circle(jc + Vector2(-1.5, -1.5) * k, 1.5 * k, Color(1, 1, 1, 0.8))
	# Type tag at the bottom edge.
	var tag: String = "CREW" if crew else ("CHAOS" if CardView.is_chaos(card) else "TRICK")
	var tfs: int = int(12 * k)
	var tw: float = _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 22 * k
	var tg := Rect2(Vector2((W - tw) * 0.5, H - 20 * k), Vector2(tw, 20 * k))
	draw_colored_polygon(_chamfer(tg.grow(3 * k), 8 * k), UIKit.INK)
	draw_colored_polygon(_chamfer(tg.grow(2 * k), 7 * k), gold_d)
	draw_colored_polygon(_chamfer(tg, 6 * k), Color(0.1, 0.07, 0.14))
	_text(_font, Vector2(tg.position.x, tg.position.y + tg.size.y * 0.5 + tfs * 0.4), tag, tfs, gold, 0, tg.size.x)
	# Gems: cost (blue, top-left), attack (amber, bottom-left), health
	# (red, bottom-right).
	_num_gem(Vector2(22, 24) * k, 24 * k, 6, -PI / 2, Color(0.15, 0.42, 0.95), Color(0.75, 0.88, 1.0), str(int(card.get("cost", 0))), int(30 * k))
	if crew:
		_num_gem(Vector2(24 * k, H - 26 * k), 23 * k, 4, -PI / 2, Color(0.95, 0.6, 0.1), gold, str(int(card.get("attack", 0))), int(28 * k))
		_num_gem(Vector2(W - 24 * k, H - 26 * k), 23 * k, 8, -PI / 8, Color(0.82, 0.12, 0.16), gold, str(int(card.get("health", 0))), int(28 * k))


# --- HOLO ---

func _draw_holo() -> void:
	var k: float = _k()
	var W: float = size.x
	var H: float = size.y
	var col: Color = _class_color()
	var neon: Color = col.lightened(0.25)
	var full := Rect2(Vector2.ZERO, size)
	var crew: bool = _is_crew()
	var c1: float = 22 * k
	# Outer glow.
	for i in 4:
		draw_colored_polygon(_chamfer(full.grow((2 + i * 3) * k), c1 + i * 2 * k), Color(neon.r, neon.g, neon.b, 0.07 * (4 - i)))
	draw_colored_polygon(_chamfer(full, c1), Color(0.03, 0.03, 0.07))
	# Art, full-bleed in the top part, with scanlines and a fade to glass.
	var aw := Rect2(Vector2(6, 6) * k, Vector2(W - 12 * k, 214 * k))
	_art(aw, _chamfer(aw, c1 - 5 * k))
	for y in range(0, int(aw.size.y), int(maxf(3.0, 3 * k))):
		draw_line(Vector2(aw.position.x, aw.position.y + y), Vector2(aw.end.x, aw.position.y + y), Color(0, 0, 0, 0.12), 1.0)
	var sweep: float = fmod(_t * 0.35, 1.0)
	draw_rect(Rect2(Vector2(aw.position.x, aw.position.y + aw.size.y * sweep), Vector2(aw.size.x, 3 * k)), Color(neon.r, neon.g, neon.b, 0.25))
	var fade := PackedVector2Array([Vector2(aw.position.x, aw.position.y + aw.size.y * 0.55), Vector2(aw.end.x, aw.position.y + aw.size.y * 0.55), aw.end, Vector2(aw.position.x, aw.end.y)])
	draw_polygon(fade, PackedColorArray([Color(0.03, 0.03, 0.07, 0), Color(0.03, 0.03, 0.07, 0), Color(0.03, 0.03, 0.07, 1), Color(0.03, 0.03, 0.07, 1)]))
	# Name over the faded bottom of the art.
	_name_text(Rect2(Vector2(20 * k, 180 * k), Vector2(W - 40 * k, 32 * k)), int(19 * k))
	draw_line(Vector2(30 * k, 214 * k), Vector2(W - 30 * k, 214 * k), Color(neon.r, neon.g, neon.b, 0.8), 2.0 * k)
	draw_circle(Vector2(W * 0.5, 214 * k), 4 * k, _rarity_color())
	# Glass text panel.
	var tr := Rect2(Vector2(16, 220) * k, Vector2(W - 32 * k, 120 * k))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(neon.r, neon.g, neon.b, 0.08)
	sb.set_corner_radius_all(int(8 * k))
	sb.border_color = Color(neon.r, neon.g, neon.b, 0.35)
	sb.set_border_width_all(1)
	draw_style_box(sb, tr)
	# Neon edge.
	var edge := _chamfer(full.grow(-1.5 * k), c1)
	edge.append(edge[0])
	draw_polyline(edge, neon, 3.0 * k, true)
	var edge2 := _chamfer(full.grow(-6 * k), c1 - 3 * k)
	edge2.append(edge2[0])
	draw_polyline(edge2, Color(neon.r, neon.g, neon.b, 0.35), 1.0, true)
	# Type label.
	var tag: String = "CREW" if crew else "TRICK"
	_text(_font, Vector2(0, H - 9 * k), tag, int(11 * k), Color(neon.r, neon.g, neon.b, 0.9), 0, W)
	# Hex gems.
	_num_gem(Vector2(26, 26) * k, 22 * k, 6, 0.0, Color(0.06, 0.2, 0.5), Color(0.4, 0.75, 1.0), str(int(card.get("cost", 0))), int(28 * k))
	if crew:
		_num_gem(Vector2(26 * k, H - 28 * k), 21 * k, 6, 0.0, Color(0.45, 0.28, 0.02), Color(1.0, 0.75, 0.25), str(int(card.get("attack", 0))), int(26 * k))
		_num_gem(Vector2(W - 26 * k, H - 28 * k), 21 * k, 6, 0.0, Color(0.45, 0.04, 0.08), Color(1.0, 0.35, 0.4), str(int(card.get("health", 0))), int(26 * k))
