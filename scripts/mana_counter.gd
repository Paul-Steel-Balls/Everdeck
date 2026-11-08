extends Control
class_name ManaCounter

# Themed mana: ten small icons drawn in code (crisp at any size), one look
# per deck. A lit icon is mana you can spend; a dark one is spent this
# turn; slots past your max stay hidden.
#   Grunk     dynamite sticks, fuses sparking
#   Agatha    cookies (a spent one has a bite taken out)
#   Presto    candles, flames flickering (spent ones smoke)
#   Barnacle  gold doubloons
#   Reginald  heater shields with a gold cross
#   Larry     casino chips
# The HeroBadge owns one (top_level, so its container ignores it) and
# forwards set_mana / pop to it.

const SLOTS := 10

var deck: String = "grunk"
var icon_h: float = 26.0
var mana: int = 0
var max_mana: int = 0

var _pop: Array = []      # per-slot extra scale (turn-start pop)
var _t: float = 0.0
var _label: Label = null
var _bg: StyleBoxFlat = null


func setup(theme_id: String, height: float) -> void:
	deck = theme_id
	icon_h = height
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	_pop.resize(SLOTS)
	_pop.fill(0.0)
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0.05, 0.04, 0.08, 0.82)
	for c in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		_bg.set(c, int(height * 0.5))
	if _label == null:
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_size_override("font_size", int(height * 0.62))
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)
	size = Vector2(_step() * SLOTS + height * 2.6, height * 1.45)
	_label.position = Vector2(_step() * SLOTS + height * 0.55, height * 0.12)
	_label.size = Vector2(height * 2.0, height * 1.2)
	queue_redraw()


func _step() -> float:
	return icon_h * 0.95


func set_mana(m: int, mx: int) -> void:
	mana = m
	max_mana = mx
	if _label != null:
		_label.text = "%d/%d" % [m, mx]
	queue_redraw()


# Turn start: the lit icons pop one after another.
func pop(m: int, pop_time: float, stagger: float) -> void:
	for i in mini(m, SLOTS):
		var tw := create_tween()
		tw.tween_interval(i * stagger)
		tw.tween_method(func(v: float) -> void:
			_pop[i] = v
			queue_redraw(), 0.6, 0.0, maxf(pop_time, 0.05) * 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _process(delta: float) -> void:
	_t += delta
	if mana > 0:
		queue_redraw()  # flames, fuses and sheen move


func _draw() -> void:
	if _bg != null:
		draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	for i in mini(max_mana, SLOTS):
		var c := Vector2(icon_h * 0.62 + i * _step(), size.y * 0.5)
		var s: float = icon_h * (1.0 + float(_pop[i]))
		_icon(c, s, i < mana, i)


func _icon(c: Vector2, s: float, lit: bool, i: int) -> void:
	DeckIcons.draw(self, deck, c, s, lit, i, _t, _bg.bg_color if _bg != null else Color(0, 0, 0))
