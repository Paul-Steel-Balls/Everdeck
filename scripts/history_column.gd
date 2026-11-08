extends VBoxContainer
class_name HistoryColumn

# What just happened: a short column of card thumbnails down the right
# edge (newest on top). Each is the card's painting in a small frame,
# rimmed blue for you and red for them, with a tiny mark for what kind of
# action it was (a card played, an attack, a Signature Move). Rest the
# mouse on one and the full card pops up beside it with a line saying
# what it did; tap it for the big view.

const MAX_ENTRIES: int = 8      # how many the game remembers
const MAX_SHOWN: int = 5        # how many thumbnails fit above END TURN
const ENTRY_W: float = 36.0
const ENTRY_H: float = 44.0
const GAP: float = 5.0
const COL_X: float = 12.0
const COL_Y: float = 66.0       # top of the right-edge strip

var _on_tap: Callable = Callable()
var _on_hover: Callable = Callable()   # (entry, rect) or ({}, Rect2()) to hide
var _viewer: int = 0


func setup(on_tap: Callable, viewer: int, on_hover: Callable = Callable()) -> void:
	_on_tap = on_tap
	_on_hover = on_hover
	_viewer = viewer
	add_theme_constant_override("separation", int(GAP))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_entries(entries: Array) -> void:
	for c in get_children():
		c.queue_free()
	var n: int = mini(entries.size(), MAX_SHOWN)
	for i in n:
		add_child(_make_entry(entries[i], i == 0))


func _border_color(player: int) -> Color:
	# Mine blue, theirs red, relative to the viewer.
	return Color(0.3, 0.6, 1.0) if player == _viewer else Color(1.0, 0.3, 0.3)


func _make_entry(entry: Dictionary, newest: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(ENTRY_W, ENTRY_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col: Color = _border_color(int(entry.get("player", 0)))
	var kind: String = str(entry.get("kind", ""))
	var tex: Texture2D = CardArt.texture_for(str(entry.get("card_id", "")), str(entry.get("art_id", "")))
	root.draw.connect(func() -> void: _draw_thumb(root, tex, col, kind, newest))
	root.gui_input.connect(_on_entry_gui_input.bind(entry))
	root.mouse_entered.connect(func() -> void:
		if _on_hover.is_valid():
			_on_hover.call(entry, root.get_global_rect()))
	root.mouse_exited.connect(func() -> void:
		if _on_hover.is_valid():
			_on_hover.call({}, Rect2()))
	return root


func _draw_thumb(c: Control, tex: Texture2D, col: Color, kind: String, newest: bool) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	# Shadow, colored rim, ink line, the painting.
	c.draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.45))
	c.draw_rect(r.grow(1.0), UIKit.INK)
	c.draw_rect(r, col)
	var inner := r.grow(-2.5)
	if tex != null:
		var ts: Vector2 = tex.get_size()
		var sc: float = maxf(inner.size.x / ts.x, inner.size.y / ts.y)
		var src_size: Vector2 = inner.size / sc
		c.draw_texture_rect_region(tex, inner, Rect2(Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * 0.25), src_size))
	else:
		c.draw_rect(inner, col.darkened(0.6))
	if newest:
		c.draw_rect(r.grow(2.5), Color(1, 1, 1, 0.55), false, 1.5)
	# The action mark in the corner: a little badge.
	var bc := Vector2(r.end.x - 7, r.end.y - 7)
	c.draw_circle(bc, 8.0, UIKit.INK)
	c.draw_circle(bc, 6.6, col.darkened(0.25))
	match kind:
		"attack":
			for s in [-1.0, 1.0]:
				var d := Vector2(s, -1).normalized()
				c.draw_line(bc - d * 4.2, bc + d * 4.2, Color.WHITE, 1.6, true)
		"signature":
			var star := PackedVector2Array()
			for i in 10:
				var a: float = -PI / 2 + TAU * i / 10.0
				star.append(bc + Vector2(cos(a), sin(a)) * (4.6 if i % 2 == 0 else 2.0))
			c.draw_colored_polygon(star, Color.WHITE)
		_:
			c.draw_rect(Rect2(bc - Vector2(2.6, 3.4), Vector2(5.2, 6.8)), Color.WHITE)


func _on_entry_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_on_tap.call(entry)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap.call(entry)
