extends Control
class_name HeroBadge

# The Boss card: a tall gold-framed card down the left edge (enemy upper
# left, mine lower left), drawn in code to match END TURN and the
# Signature Move medallion.
#   - portrait window with the Boss's art, jewel on top in the Boss color
#   - name ribbon across the bottom of the portrait
#   - Health: a big red gem over the portrait's corner, plus a thin bar
#   - Mana: a blue crystal and "3/6" (plain numbers, no themed icons)
#   - Deck and (enemy) Hand counts
# The whole card is a drop/snap target for the targeting arrow and
# glows red when targeted. Everything ignores the mouse so taps fall
# through to the 3D pick layer. The director's Boss animation hooks
# (damage shake, heal, death, deck pulse, mana pop) live here.

const MY_W: float = 140.0
const MY_H: float = 300.0
const ENEMY_SCALE: float = 0.86
const MAX_HP: int = 30

# Fixed canvas positions (top-left of the card).
const ENEMY_POS := Vector2(12, 62)
const MY_POS := Vector2(12, 404)
# Kept for code that sizes things off the old panel.
const PANEL_W: float = MY_W
const PANEL_H: float = MY_H

var player: int = 0
var class_id: String = ""

var _hp: int = 30
var _max_hp: int = 30
var _mana: int = 0
var _max_mana: int = 0
var _deck: int = 30
var _hand: int = 0
var _show_hand: bool = false
var _highlighted: bool = false
var _is_mine: bool = true
var _k: float = 1.0               # 1 for mine, ENEMY_SCALE for the enemy's
var _t: float = 0.0
var _hp_flash: Color = Color(0, 0, 0, 0)
var _hp_punch: float = 0.0        # extra scale on the Health gem
var _mana_pop: float = 0.0
var _deck_pulse: float = 0.0
var _portrait: Texture2D = null
var _color: Color = Color(1.0, 0.75, 0.35)
var _font: Font
var _body: Font

# Labels the tests (and old code) read; kept in sync, drawn by _draw.
var _hp_label: Label = null
var _mana_label: Label = null
var _deck_label: Label = null
var _hand_label: Label = null
# The themed mana counter is gone (plain "3/6" now); kept as null so old
# checks for it read cleanly.
var counter: Variant = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	_body = UIKit.font(UIKit.FONT_BODY_PATH)
	_resize()


func _mk_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	add_child(l)
	return l


func setup(player_idx: int, hero_class: String) -> void:
	player = player_idx
	class_id = hero_class
	_color = UIKit.CLASS_COLOR.get(hero_class, Color(1.0, 0.75, 0.35))
	_portrait = CardArt.texture_for("", str(CardView.CLASS_ART.get(hero_class, "")))
	if _hp_label == null:
		_hp_label = _mk_label()
		_mana_label = _mk_label()
		_deck_label = _mk_label()
		_hand_label = _mk_label()
	_sync_labels()
	queue_redraw()


func _resize() -> void:
	_k = 1.0 if _is_mine else ENEMY_SCALE
	custom_minimum_size = Vector2(MY_W, MY_H) * _k
	size = custom_minimum_size
	pivot_offset = size * 0.5


func _sync_labels() -> void:
	if _hp_label == null:
		return
	_hp_label.text = "%d/%d" % [_hp, _max_hp]
	_mana_label.text = "%d/%d" % [_mana, _max_mana]
	_deck_label.text = "%d" % _deck
	_hand_label.text = "%d" % _hand


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# --- Drawing ---

# Chamfered rectangle (cut corners), inset by `i` pixels.
func _shape(r: Rect2, c: float, i: float = 0.0) -> PackedVector2Array:
	var a := r.grow(-i)
	var cc: float = maxf(c - i * 0.4, 2.0)
	return PackedVector2Array([
		a.position + Vector2(cc, 0), Vector2(a.end.x - cc, a.position.y),
		Vector2(a.end.x, a.position.y + cc), Vector2(a.end.x, a.end.y - cc),
		Vector2(a.end.x - cc, a.end.y), Vector2(a.position.x + cc, a.end.y),
		Vector2(a.position.x, a.end.y - cc), Vector2(a.position.x, a.position.y + cc)])


func _text(f: Font, pos: Vector2, s: String, fs: int, col: Color, outline: int, center_w: float = -1.0) -> void:
	var p := pos
	if center_w > 0.0:
		p.x += (center_w - f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) * 0.5
	if outline > 0:
		draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, UIKit.INK)
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _fit(f: Font, s: String, fs: int, w: float) -> int:
	var n: int = fs
	while n > 9 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x > w:
		n -= 1
	return n


func _draw() -> void:
	var k: float = _k
	var W: float = MY_W * k
	var H: float = MY_H * k
	var full := Rect2(Vector2.ZERO, Vector2(W, H))
	var ch: float = 14.0 * k
	var gold: Color = UIKit.GOLD
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.3)
	# Targeted: a red glow around the card.
	if _highlighted:
		var ga: float = 0.55 + 0.25 * sin(_t * 8.0)
		for i in 4:
			draw_colored_polygon(_shape(full, ch, -3.0 - i * 3.0), Color(1.0, 0.15, 0.12, ga * (0.4 - i * 0.08)))
	# Shadow, gold frame (dark rim, bright upper bevel), dark inner.
	var sh := _shape(full, ch)
	for i in sh.size():
		sh[i] += Vector2(0, 5)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.5))
	draw_colored_polygon(_shape(full, ch), gold_d)
	draw_colored_polygon(_shape(full, ch, 2.0 * k), gold)
	var bevel := _shape(full, ch, 2.0 * k)
	var up := PackedVector2Array()
	for v in bevel:
		up.append(Vector2(v.x, minf(v.y, H * 0.35)))
	draw_colored_polygon(up, gold.lightened(0.3))
	draw_colored_polygon(_shape(full, ch, 5.0 * k), gold_d)
	draw_colored_polygon(_shape(full, ch, 6.5 * k), Color(0.07, 0.05, 0.11))
	# Portrait window (the art cover-cropped toward the face).
	var pw := Rect2(Vector2(10, 12) * k, Vector2(MY_W - 20, 158) * k)
	draw_rect(pw.grow(2.0 * k), gold_d)
	if _portrait != null:
		var ts: Vector2 = _portrait.get_size()
		var sc: float = maxf(pw.size.x / ts.x, pw.size.y / ts.y)
		var src_size: Vector2 = pw.size / sc
		var src := Rect2(Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * 0.18), src_size)
		draw_texture_rect_region(_portrait, pw, src)
	else:
		draw_rect(pw, _color.darkened(0.5))
	# Inner shadow on the window edges + a faint Boss-color wash at the
	# bottom so the name ribbon reads.
	draw_rect(pw, Color(0, 0, 0, 0.35), false, 3.0 * k)
	var wash := PackedVector2Array([pw.position + Vector2(0, pw.size.y * 0.62), Vector2(pw.end.x, pw.position.y + pw.size.y * 0.62), pw.end, Vector2(pw.position.x, pw.end.y)])
	draw_polygon(wash, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.03, 0.02, 0.06, 0.85), Color(0.03, 0.02, 0.06, 0.85)]))
	if _hp_flash.a > 0.0:
		draw_rect(pw, _hp_flash)
	# Name ribbon across the portrait's bottom edge.
	var name_s: String = str(CardDB.CLASS_NAMES.get(class_id, class_id)).to_upper()
	var rib := Rect2(Vector2(4, pw.end.y / k - 16) * k, Vector2(MY_W - 8, 26) * k)
	var notch: float = 8.0 * k
	var rib_pts := PackedVector2Array([rib.position, Vector2(rib.end.x, rib.position.y), Vector2(rib.end.x - notch, rib.position.y + rib.size.y * 0.5), Vector2(rib.end.x, rib.end.y), Vector2(rib.position.x, rib.end.y), Vector2(rib.position.x + notch, rib.position.y + rib.size.y * 0.5)])
	draw_colored_polygon(rib_pts, _color.darkened(0.55))
	var rib_in := PackedVector2Array()
	for v in rib_pts:
		rib_in.append(rib.get_center() + (v - rib.get_center()) * Vector2(0.97, 0.78))
	draw_colored_polygon(rib_in, _color.darkened(0.25))
	rib_pts.append(rib_pts[0])
	draw_polyline(rib_pts, gold, 1.5 * k, true)
	var nfs: int = _fit(_font, name_s, int(15 * k), rib.size.x - notch * 2.6)
	_text(_font, Vector2(rib.position.x, rib.position.y + rib.size.y * 0.5 + nfs * 0.38), name_s, nfs, Color.WHITE, int(5 * k), rib.size.x)
	# Jewel on top, in the Boss color.
	var jc := Vector2(W * 0.5, 4.0 * k)
	var jr: float = 9.0 * k
	var jewel := PackedVector2Array([jc + Vector2(0, -jr), jc + Vector2(jr, 0), jc + Vector2(0, jr), jc + Vector2(-jr, 0)])
	draw_colored_polygon(jewel, gold_d)
	var jin := PackedVector2Array()
	for v in jewel:
		jin.append(jc + (v - jc) * 0.66)
	draw_colored_polygon(jin, _color.lightened(0.2))
	draw_circle(jc + Vector2(-1.5, -1.5) * k, 1.6 * k, Color(1, 1, 1, 0.85))
	# Health bar under the ribbon.
	var y: float = rib.end.y + 9.0 * k
	var hb := Rect2(Vector2(14 * k, y), Vector2(W - 28 * k, 7 * k))
	draw_rect(hb.grow(1.5 * k), Color(0, 0, 0, 0.7))
	draw_rect(hb, Color(0.22, 0.06, 0.08))
	var frac: float = clampf(float(_hp) / float(maxi(_max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y)), Color(0.9, 0.16, 0.2).lerp(Color(1, 1, 1), _hp_flash.a * 0.6))
	draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y * 0.4)), Color(1, 1, 1, 0.18))
	# Health gem over the portrait's lower-right corner.
	var gc := Vector2(W - 30 * k, pw.end.y - 44 * k)
	var gr: float = 21.0 * k * (1.0 + _hp_punch)
	var drop := PackedVector2Array()
	for i in 24:
		var a: float = TAU * i / 24.0 - PI / 2
		var rr: float = gr * (1.0 + 0.22 * maxf(0.0, -sin(a)) * absf(cos(a * 0.5)))
		drop.append(gc + Vector2(cos(a), sin(a)) * rr * Vector2(0.92, 1.0))
	var drop_o := PackedVector2Array()
	for v in drop:
		drop_o.append(gc + (v - gc) * 1.14)
	draw_colored_polygon(drop_o, gold_d)
	draw_colored_polygon(drop, Color(0.78, 0.1, 0.14))
	var hi := PackedVector2Array()
	for v in drop:
		hi.append(gc + Vector2(-3, -4) * k + (v - gc) * 0.55)
	draw_colored_polygon(hi, Color(1.0, 0.35, 0.35, 0.45))
	var hs: String = str(_hp)
	var hfs: int = int(24 * k * (1.0 + _hp_punch))
	_text(_font, Vector2(gc.x - gr, gc.y + hfs * 0.4), hs, hfs, Color.WHITE if _hp > 10 else Color(1.0, 0.85, 0.3), int(6 * k), gr * 2.0)
	# Mana: a blue crystal and "3/6".
	y = hb.end.y + 12.0 * k
	var mc := Vector2(30 * k, y + 16 * k)
	var ms: float = 13.0 * k * (1.0 + _mana_pop)
	var crys := PackedVector2Array([mc + Vector2(0, -ms * 1.15), mc + Vector2(ms * 0.85, -ms * 0.3), mc + Vector2(ms * 0.6, ms * 0.95), mc + Vector2(-ms * 0.6, ms * 0.95), mc + Vector2(-ms * 0.85, -ms * 0.3)])
	var crys_o := PackedVector2Array()
	for v in crys:
		crys_o.append(mc + (v - mc) * 1.18)
	draw_colored_polygon(crys_o, Color(0.04, 0.08, 0.2))
	draw_colored_polygon(crys, Color(0.2, 0.5, 1.0) if _mana > 0 else Color(0.25, 0.3, 0.42))
	draw_colored_polygon(PackedVector2Array([crys[0], crys[1], mc, crys[4]]), Color(0.55, 0.8, 1.0, 0.75) if _mana > 0 else Color(0.4, 0.45, 0.55, 0.6))
	var mtxt: String = "%d/%d" % [_mana, _max_mana]
	var mfs: int = int(25 * k)
	_text(_font, Vector2(52 * k, mc.y + mfs * 0.38), mtxt, mfs, Color(0.75, 0.9, 1.0) if _mana > 0 else Color(0.65, 0.68, 0.75), int(6 * k))
	# Deck (and the enemy's hand) counts.
	y = H - 50.0 * k
	draw_line(Vector2(16 * k, y), Vector2(W - 16 * k, y), Color(gold.r, gold.g, gold.b, 0.35), 1.0)
	y += 8.0 * k
	_count(Vector2(18 * k, y), _deck, "DECK", Color(0.42, 0.2, 0.62), _deck_pulse)
	if _show_hand:
		_count(Vector2(W * 0.53, y), _hand, "HAND", Color(0.15, 0.48, 0.52), 0.0)


func _count(at: Vector2, n: int, cap: String, col: Color, pulse: float) -> void:
	var k: float = _k
	var s: float = 1.0 + pulse
	var r := Rect2(at + Vector2(0, 2) * k, Vector2(16, 22) * k * s)
	draw_rect(r.grow(1.5 * k), UIKit.GOLD_DEEP)
	draw_rect(r, col)
	draw_rect(Rect2(r.position + Vector2(3, 3) * k, r.size - Vector2(6, 6) * k), col.lightened(0.2), false, 1.0)
	var fs: int = int(18 * k)
	_text(_font, at + Vector2(22 * k, 19 * k), str(n), fs, Color.WHITE, int(5 * k))
	_text(_body, at + Vector2(22 * k, 33 * k), cap, int(10 * k), Color(0.72, 0.72, 0.8), 0)


# --- Position / state ---

func set_side(is_mine: bool) -> void:
	position = MY_POS if is_mine else ENEMY_POS
	if is_mine != _is_mine or size.x <= 0.0:
		_is_mine = is_mine
		_resize()
		queue_redraw()


func set_hp(hp: int, max_hp: int = MAX_HP) -> void:
	_hp = hp
	_max_hp = max_hp
	_sync_labels()


func set_mana(mana: int, max_mana: int) -> void:
	_mana = mana
	_max_mana = max_mana
	_sync_labels()


func set_deck_count(n: int) -> void:
	_deck = n
	_sync_labels()


func set_hand_count(n: int, show: bool) -> void:
	_hand = n
	_show_hand = show
	_sync_labels()


# Floating text ON the card (Boss damage/heal numbers): always on-screen.
func float_text(text: String, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_override("font", UIKit.font(UIKit.FONT_DISPLAY_PATH))
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(size.x, 44)
	l.z_index = 60
	var parent: Control = get_parent() as Control
	if parent != null:
		l.position = position + Vector2(0, size.y * 0.3)
		parent.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "position:y", l.position.y - 60.0, 0.8).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.25)
		tw.tween_callback(l.queue_free)
	return l


func set_highlight(on: bool) -> void:
	_highlighted = on
	queue_redraw()


func is_highlighted() -> bool:
	return _highlighted


# --- Director animation hooks ---

func punch_hp(duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _hp_punch = v, 0.35, 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _shake_panel(duration: float, amplitude: float) -> void:
	var base: Vector2 = MY_POS if _is_mine else ENEMY_POS
	var step: float = duration / 4.0
	var tw := create_tween()
	tw.tween_property(self, "position", base + Vector2(amplitude, 0), step).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", base + Vector2(-amplitude, 0), step).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", base + Vector2(amplitude * 0.5, 0), step).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", base, step).set_ease(Tween.EASE_OUT)


func _flash(color: Color, duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: _hp_flash = Color(color.r, color.g, color.b, a), 0.45, 0.0, duration).set_ease(Tween.EASE_IN)


func start_damage(duration: float) -> void:
	_shake_panel(duration, 9.0)
	_flash(Color(1.0, 0.15, 0.1), duration)
	punch_hp(duration)


func start_heal(duration: float) -> void:
	_flash(Color(0.3, 1.0, 0.45), duration)
	punch_hp(duration)


func start_death(duration: float) -> void:
	_shake_panel(duration, 18.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.35, 0.3, 0.3), duration).set_ease(Tween.EASE_IN)


func pulse_deck(duration: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _deck_pulse = v, 0.5, 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func pop_mana_gems(_mana_n: int, pop_time: float, _stagger: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mana_pop = v, 0.45, 0.0, maxf(pop_time, 0.05) * 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
