extends Button
class_name SignatureButton

# The Signature Move button: a round gold medallion with studs around the
# rim, a disc in the Boss's color with the deck's emblem in the middle
# (the same dynamite / cookie / candle / doubloon / shield / chip as the
# mana counter), and a mana-cost jewel on top.
#   ready     usable now: emblem lit, rim glints, soft glow on hover
#   short     not enough mana (or no target): emblem dark, cost jewel red
#   used      already used this turn: the medallion turns over to its dull
#             back side (a quick flip when it happens)

enum Look { READY, SHORT, USED }

const D := 100.0

var deck: String = "grunk"
var color: Color = Color(0.7, 0.5, 1.0)
var cost: int = 2
var look: int = Look.READY
var _t: float = 0.0
var _hover: float = 0.0
var _font: Font


func setup(deck_id: String, boss_color: Color, mana_cost: int, l: int) -> void:
	deck = deck_id
	color = boss_color
	cost = mana_cost
	look = l
	disabled = l != Look.READY
	queue_redraw()


func _init() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(D, D)
	size = Vector2(D, D)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	pivot_offset = Vector2(D, D) * 0.5
	mouse_entered.connect(func() -> void: UIKit._tween_scale(self, 1.07, 0.12))
	mouse_exited.connect(func() -> void: UIKit._tween_scale(self, 1.0, 0.16))
	button_down.connect(func() -> void: UIKit._tween_scale(self, 0.93, 0.06))
	button_up.connect(func() -> void: UIKit._tween_scale(self, 1.07 if is_hovered() else 1.0, 0.14))


# Turn the medallion over (call when it gets used).
func flip_to_used() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale:x", 0.0, 0.14)
	tw.tween_callback(func() -> void: setup(deck, color, cost, Look.USED))
	tw.tween_property(self, "scale:x", 1.0, 0.16)


func _process(delta: float) -> void:
	_t += delta
	_hover = move_toward(_hover, 1.0 if (is_hovered() and look == Look.READY) else 0.0, delta * 6.0)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(D, D) * 0.5 + Vector2(0, 4)
	var r: float = D * 0.42
	var used: bool = look == Look.USED
	var gold: Color = UIKit.GOLD if not used else Color(0.5, 0.48, 0.45)
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.25) if not used else Color(0.25, 0.24, 0.23)
	# Glow (ready: breathes a little, more on hover).
	if look == Look.READY:
		var ga: float = 0.1 + 0.06 * sin(_t * 2.4) + 0.2 * _hover
		for i in 4:
			draw_circle(c, r + 6.0 + i * 3.0, Color(color.r, color.g, color.b, ga * (0.4 - i * 0.08)))
	# Shadow, rim, studs.
	draw_circle(c + Vector2(0, 4), r + 3.0, Color(0, 0, 0, 0.45))
	draw_circle(c, r + 3.0, gold_d)
	draw_circle(c, r + 1.0, gold)
	draw_arc(c, r - 1.0, PI * 1.1, PI * 1.9, 24, gold.lightened(0.4), 3.0, true)
	for i in 12:
		var a: float = TAU * i / 12.0 + PI / 12.0
		var sp: Vector2 = c + Vector2(cos(a), sin(a)) * (r - 2.5)
		draw_circle(sp, 2.6, gold_d)
		draw_circle(sp + Vector2(-0.6, -0.6), 1.5, gold.lightened(0.45))
	draw_circle(c, r - 7.0, gold_d)
	# Disc: the Boss's color, darker at the edge.
	var disc: Color = color if not used else Color(0.22, 0.22, 0.26)
	var dr: float = r - 9.0
	for i in 6:
		var f: float = 1.0 - i / 6.0
		draw_circle(c, dr * f, disc.darkened(0.55 * f).lerp(disc.lightened(0.15), 1.0 - f))
	if used:
		# The back side: a plain engraved star.
		var pts := PackedVector2Array()
		for i in 10:
			var a2: float = -PI / 2 + TAU * i / 10.0
			pts.append(c + Vector2(cos(a2), sin(a2)) * (dr * (0.55 if i % 2 == 0 else 0.24)))
		draw_colored_polygon(pts, Color(0.32, 0.32, 0.36))
	else:
		DeckIcons.draw(self, deck, c, dr * 1.9, look == Look.READY, 0, _t, disc.darkened(0.5))
	# Rim glint sweeping round (ready only).
	if look == Look.READY:
		var ga2: float = fmod(_t * 0.35, 1.0) * TAU
		draw_arc(c, r - 0.5, ga2, ga2 + 0.5, 8, Color(1, 1, 1, 0.55), 2.0, true)
	# Cost jewel on top.
	var jc := Vector2(D * 0.5, 10.0)
	var jr: float = 15.0
	var gem: Color = Color(0.2, 0.5, 1.0)
	if look == Look.SHORT:
		gem = Color(0.75, 0.2, 0.25)
	elif used:
		gem = Color(0.3, 0.32, 0.4)
	var jewel := PackedVector2Array([jc + Vector2(0, -jr), jc + Vector2(jr, 0), jc + Vector2(0, jr), jc + Vector2(-jr, 0)])
	draw_colored_polygon(jewel, gold_d)
	var jin := PackedVector2Array()
	for v in jewel:
		jin.append(jc + (v - jc) * 0.78)
	draw_colored_polygon(jin, gem)
	draw_colored_polygon(PackedVector2Array([jin[0], jin[1], jc, jin[3]]), gem.lightened(0.25))
	var s: String = str(cost)
	var fs: int = 20
	var tw: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := jc + Vector2(-tw * 0.5, fs * 0.38)
	draw_string_outline(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UIKit.INK)
	draw_string(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
