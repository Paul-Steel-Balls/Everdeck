extends VBoxContainer
class_name HistoryColumn

# Everdeck Sprint 1c — the action-history column. A vertical strip on the
# left edge of the match screen, between the two hero panels (main
# positions it; the panels are fixed at (10,75) and (10,407), so this
# owns y 189..397). Up to 8 entries, newest on top, older ones drop off
# the end. Each entry: a small card-art icon (hero portrait for a
# Signature Move), a border colored by the acting player (viewer blue,
# other red), and a tiny corner letter for the action type (P = played,
# A = attacked, S = Signature Move — the fallback font has no unicode
# glyphs, verified by probe). Tap an entry -> the on_tap callable with
# the entry dict; main shows the detail panel (inspect rules).

const MAX_ENTRIES: int = 8
const ENTRY_W: float = 30.0
const ENTRY_H: float = 26.0
const COL_X: float = 12.0
const COL_Y: float = 189.0

const KIND_LETTER: Dictionary = {"played": "P", "attack": "A", "signature": "S"}

var _on_tap: Callable = Callable()
var _viewer: int = 0


func setup(on_tap: Callable, viewer: int) -> void:
	_on_tap = on_tap
	_viewer = viewer
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_entries(entries: Array) -> void:
	for c in get_children():
		c.queue_free()
	var n: int = mini(entries.size(), MAX_ENTRIES)
	for i in n:
		add_child(_make_entry(entries[i]))


func _border_color(player: int) -> Color:
	# Mine blue, enemy red — relative to the viewer.
	return Color(0.25, 0.5, 1.0) if player == _viewer else Color(1.0, 0.25, 0.25)


func _make_entry(entry: Dictionary) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(ENTRY_W, ENTRY_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.88)
	sb.border_color = _border_color(int(entry.get("player", 0)))
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)
	var art := CardArt.new()
	art.art_id = str(entry.get("art_id", "token"))
	art.card_id = str(entry.get("card_id", ""))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(4, 3)
	art.size = Vector2(20, 20)
	root.add_child(art)
	var glyph := Label.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.text = str(KIND_LETTER.get(str(entry.get("kind", "")), "?"))
	glyph.add_theme_font_size_override("font_size", 10)
	glyph.add_theme_color_override("font_color", Color(1, 1, 1))
	glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	glyph.add_theme_constant_override("outline_size", 3)
	glyph.position = Vector2(19, 12)
	glyph.size = Vector2(10, 12)
	root.add_child(glyph)
	root.gui_input.connect(_on_entry_gui_input.bind(entry))
	return root


func _on_entry_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_on_tap.call(entry)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap.call(entry)
