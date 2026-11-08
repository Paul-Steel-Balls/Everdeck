extends Control
class_name DeckBuilder

# Deck builder (PC): a filterable, mouse-wheel-scrolling grid of cards on
# the left; the deck list with a mana curve on the right. Click a card to
# add it (it flies into the list); click a list row to take one out.

signal back_pressed
signal done(deck: Array)

const COLS: int = 5
const CARD_SIZE := Vector2(160, 224)
const COST_FILTERS: Array = ["ALL", "0-1", "2", "3", "4", "5", "6", "7+"]

var class_id: String = ""
var deck: Array = []
var _pool: Array = []
var _cost_filter: String = "ALL"
var _side_filter: String = "ALL"  # ALL / CLASS / NEUTRAL
var _bg_mat: ShaderMaterial
var _grid: GridContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _count_label: Label
var _bar_fill: ColorRect
var _curve: Control
var _done_btn: Button
var _filter_btns: Dictionary = {}
var _tiles: Dictionary = {}  # card_id -> CardFace
var buttons: Dictionary = {}


func setup(cls: String, start_deck: Array = []) -> void:
	class_id = cls
	deck = start_deck.duplicate()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pool = CardDB.cards_for_class(class_id)
	_pool.sort_custom(func(a, b) -> bool:
		if int(a["cost"]) != int(b["cost"]):
			return int(a["cost"]) < int(b["cost"])
		if (a["class"] == "neutral") != (b["class"] == "neutral"):
			return a["class"] != "neutral"
		return str(a["name"]) < str(b["name"]))
	_build_bg()
	_build_top()
	_build_grid()
	_build_side()
	_refresh_all()


# --- Layout ---

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://shaders/nebula.gdshader")
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	_bg_mat.set_shader_parameter("smoke_color", col.darkened(0.7))
	_bg_mat.set_shader_parameter("ember_color", col.darkened(0.45))
	_bg_mat.set_shader_parameter("ember_strength", 0.3)
	bg.material = _bg_mat
	add_child(bg)


func _build_top() -> void:
	var back := UIKit.button("BACK", UIKit.BTN_PURPLE, 18, Vector2(110, 44))
	back.position = Vector2(16, 14)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)
	buttons["back"] = back
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	var t := UIKit.label("BUILD YOUR DECK", 26, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 8)
	t.position = Vector2(146, 10)
	add_child(t)
	var c := UIKit.label(CardDB.class_display_name(class_id).to_upper(), 18, col.lightened(0.25), UIKit.FONT_DISPLAY_PATH, 6)
	c.position = Vector2(148, 42)
	add_child(c)
	var row := HBoxContainer.new()
	row.position = Vector2(430, 16)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for f in COST_FILTERS:
		var b := _pill(f, func() -> void: _set_cost_filter(f))
		row.add_child(b)
		_filter_btns["cost_" + f] = b
	var row2 := HBoxContainer.new()
	row2.position = Vector2(430, 58)
	row2.add_theme_constant_override("separation", 6)
	add_child(row2)
	for f2 in ["ALL", "CLASS", "NEUTRAL"]:
		var b2 := _pill(f2, func() -> void: _set_side_filter(f2))
		row2.add_child(b2)
		_filter_btns["side_" + f2] = b2


func _pill(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 32)
	b.add_theme_font_override("font", UIKit.font(UIKit.FONT_DISPLAY_PATH))
	b.add_theme_font_size_override("font_size", 14)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


func _style_pill(b: Button, on: bool) -> void:
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.1) if on else (Color(1, 1, 1, 0.16) if st.begins_with("hover") else Color(0, 0, 0, 0.4))
		sb.border_color = UIKit.INK if on else Color(1, 1, 1, 0.25)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE if on else Color(1, 1, 1, 0.75))


func _build_grid() -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "PoolScroll"
	_scroll.position = Vector2(16, 100)
	_scroll.size = Vector2(COLS * (CARD_SIZE.x + 12) + 24, 610)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 30)
	_scroll.add_child(margin)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 14)
	margin.add_child(_grid)
	for c in _pool:
		var cid: String = str(c["id"])
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var face := CardFace.make(c, CARD_SIZE)
		face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		face.pivot_offset = CARD_SIZE * 0.5
		holder.add_child(face)
		face.mouse_entered.connect(func() -> void: _hover(face, true))
		face.mouse_exited.connect(func() -> void: _hover(face, false))
		face.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_add(cid, face))
		_grid.add_child(holder)
		_tiles[cid] = face


func _hover(face: CardFace, on: bool) -> void:
	face.get_parent().z_index = 10 if on else 0
	var tw := face.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(face, "scale", Vector2(1.32, 1.32) if on else Vector2.ONE, 0.14)


func _build_side() -> void:
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(910, 14)
	panel.size = Vector2(356, 692)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.02, 0.09, 0.88)
	sb.border_color = col.darkened(0.2)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var title := UIKit.label("YOUR DECK", 24, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 7)
	title.position = Vector2(930, 26)
	add_child(title)
	_count_label = UIKit.label("0 / 30", 24, UIKit.GOLD, UIKit.FONT_DISPLAY_PATH, 7)
	_count_label.position = Vector2(1150, 26)
	add_child(_count_label)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.1)
	bar_bg.position = Vector2(930, 64)
	bar_bg.size = Vector2(316, 10)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = col
	_bar_fill.position = Vector2(930, 64)
	_bar_fill.size = Vector2(0, 10)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_fill)
	_curve = Control.new()
	_curve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curve.position = Vector2(930, 84)
	_curve.size = Vector2(316, 74)
	_curve.draw.connect(_draw_curve)
	add_child(_curve)
	var ls := ScrollContainer.new()
	ls.name = "DeckList"
	ls.position = Vector2(924, 168)
	ls.size = Vector2(330, 440)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(ls)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(312, 0)
	_list.add_theme_constant_override("separation", 4)
	ls.add_child(_list)
	var auto := UIKit.button("AUTO-FILL", UIKit.BTN_BLUE, 18, Vector2(150, 46))
	auto.position = Vector2(928, 618)
	auto.pressed.connect(_autofill)
	add_child(auto)
	buttons["auto"] = auto
	var clear := UIKit.button("CLEAR", UIKit.BTN_PURPLE, 16, Vector2(110, 46))
	clear.position = Vector2(1100, 618)
	clear.pressed.connect(func() -> void:
		deck.clear()
		_refresh_all())
	add_child(clear)
	buttons["clear"] = clear
	_done_btn = UIKit.button("DONE!", UIKit.BTN_GREEN, 26, Vector2(300, 60), true)
	_done_btn.position = Vector2(938, 660)
	_done_btn.size = Vector2(300, 50)
	_done_btn.custom_minimum_size = Vector2(300, 50)
	_done_btn.pressed.connect(func() -> void:
		if deck.size() == GameState.DECK_SIZE:
			done.emit(deck.duplicate()))
	add_child(_done_btn)
	buttons["done"] = _done_btn


func _draw_curve() -> void:
	var buckets: Array = [0, 0, 0, 0, 0, 0, 0, 0]
	for cid in deck:
		var c: int = int(CardDB.get_card(cid).get("cost", 0))
		buckets[clamp(c, 0, 7)] += 1
	var mx: int = 1
	for b in buckets:
		mx = max(mx, int(b))
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	var w: float = _curve.size.x / 8.0
	var f: Font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	for i in 8:
		var h: float = (_curve.size.y - 18.0) * float(buckets[i]) / float(max(mx, 4))
		var r := Rect2(Vector2(i * w + 6, _curve.size.y - 18.0 - h), Vector2(w - 12, h))
		_curve.draw_rect(r, col)
		_curve.draw_rect(r, UIKit.INK, false, 2.0)
		var lab: String = str(i) if i < 7 else "7+"
		_curve.draw_string(f, Vector2(i * w, _curve.size.y - 2), lab, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.75))


# --- Filters ---

func _set_cost_filter(f: String) -> void:
	_cost_filter = f
	_apply_filters()


func _set_side_filter(f: String) -> void:
	_side_filter = f
	_apply_filters()


func _apply_filters() -> void:
	for f in COST_FILTERS:
		_style_pill(_filter_btns["cost_" + f], f == _cost_filter)
	for f2 in ["ALL", "CLASS", "NEUTRAL"]:
		_style_pill(_filter_btns["side_" + f2], f2 == _side_filter)
	for c in _pool:
		var holder: Control = _tiles[str(c["id"])].get_parent()
		holder.visible = _passes(c)
	_scroll.scroll_vertical = 0


func _passes(c: Dictionary) -> bool:
	var cost: int = int(c["cost"])
	match _cost_filter:
		"0-1":
			if cost > 1:
				return false
		"7+":
			if cost < 7:
				return false
		"ALL":
			pass
		_:
			if cost != int(_cost_filter):
				return false
	if _side_filter == "CLASS" and c["class"] == "neutral":
		return false
	if _side_filter == "NEUTRAL" and c["class"] != "neutral":
		return false
	return true


# --- Deck edits ---

func _add(cid: String, face: CardFace) -> void:
	var c: Dictionary = CardDB.get_card(cid)
	if deck.size() >= GameState.DECK_SIZE or deck.count(cid) >= CardDB.max_copies(c):
		_shake(face)
		return
	deck.append(cid)
	_fly(face)
	_refresh_all(cid)


func _remove(cid: String) -> void:
	var i: int = deck.rfind(cid)
	if i >= 0:
		deck.remove_at(i)
	_refresh_all()


func _autofill() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var filled: Array = AIPlayer.build_deck(class_id)
	# Keep what the player chose; top up from a curve-built deck.
	for cid in filled:
		if deck.size() >= GameState.DECK_SIZE:
			break
		if deck.count(cid) < CardDB.max_copies(CardDB.get_card(cid)):
			deck.append(cid)
	var guard: int = 0
	while deck.size() < GameState.DECK_SIZE and guard < 5000:
		guard += 1
		var c: Dictionary = _pool[r.randi_range(0, _pool.size() - 1)]
		if deck.count(str(c["id"])) < CardDB.max_copies(c):
			deck.append(str(c["id"]))
	_refresh_all()


func _shake(n: Control) -> void:
	var x: float = n.position.x
	var tw := n.create_tween()
	for d in [8.0, -8.0, 5.0, -5.0, 0.0]:
		tw.tween_property(n, "position:x", x + d, 0.04)


# A copy of the card shrinks and flies into the deck list.
func _fly(face: CardFace) -> void:
	var ghost := CardFace.make(face.card, CARD_SIZE)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	ghost.global_position = face.global_position
	ghost.pivot_offset = CARD_SIZE * 0.5
	ghost.z_index = 50
	var tw := ghost.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "global_position", Vector2(1010, 300), 0.32)
	tw.tween_property(ghost, "scale", Vector2(0.25, 0.25), 0.32)
	tw.tween_property(ghost, "modulate:a", 0.2, 0.32)
	tw.chain().tween_callback(ghost.queue_free)


func _refresh_all(just_added: String = "") -> void:
	_apply_filters_badges()
	_apply_filter_styles_once()
	var n: int = deck.size()
	_count_label.text = "%d / %d" % [n, GameState.DECK_SIZE]
	_count_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.45) if n == GameState.DECK_SIZE else UIKit.GOLD)
	var tw := _bar_fill.create_tween()
	tw.tween_property(_bar_fill, "size:x", 316.0 * float(n) / float(GameState.DECK_SIZE), 0.18)
	_done_btn.disabled = n != GameState.DECK_SIZE
	_done_btn.modulate.a = 1.0 if n == GameState.DECK_SIZE else 0.45
	_curve.queue_redraw()
	_rebuild_list(just_added)


var _styled_once: bool = false


func _apply_filter_styles_once() -> void:
	if _styled_once:
		return
	_styled_once = true
	_apply_filters()


func _apply_filters_badges() -> void:
	for cid in _tiles:
		var face: CardFace = _tiles[cid]
		var c: Dictionary = face.card
		var cnt: int = deck.count(cid)
		var full: bool = cnt >= CardDB.max_copies(c)
		face.set_dim(full)
		var badge: Label = face.get_node_or_null("Count")
		if cnt > 0:
			if badge == null:
				badge = UIKit.label("", 22, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 8)
				badge.name = "Count"
				badge.position = Vector2(CARD_SIZE.x - 46, 2)
				face.add_child(badge)
			badge.text = "x%d" % cnt
		elif badge != null:
			badge.queue_free()


func _rebuild_list(just_added: String) -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var counts: Dictionary = {}
	var order: Array = []
	for cid in deck:
		if not counts.has(cid):
			order.append(cid)
		counts[cid] = int(counts.get(cid, 0)) + 1
	order.sort_custom(func(a, b) -> bool:
		var ca: Dictionary = CardDB.get_card(a)
		var cb: Dictionary = CardDB.get_card(b)
		if int(ca["cost"]) != int(cb["cost"]):
			return int(ca["cost"]) < int(cb["cost"])
		return str(ca["name"]) < str(cb["name"]))
	for cid in order:
		var row := _list_row(CardDB.get_card(cid), int(counts[cid]))
		_list.add_child(row)
		if cid == just_added:
			row.pivot_offset = Vector2(150, 18)
			row.scale = Vector2(1.12, 1.12)
			row.modulate = Color(1.6, 1.6, 1.6)
			var tw := row.create_tween().set_parallel(true)
			tw.tween_property(row, "scale", Vector2.ONE, 0.25)
			tw.tween_property(row, "modulate", Color.WHITE, 0.35)


func _list_row(c: Dictionary, count: int) -> Control:
	var col: Color = UIKit.CLASS_COLOR.get(str(c["class"]), Color(0.75, 0.62, 0.42))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(306, 36)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.55) if st == "normal" else col.darkened(0.3)
		sb.border_color = UIKit.INK
		sb.set_border_width_all(2)
		sb.border_width_left = 6
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var cost := UIKit.label(str(int(c["cost"])), 18, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 6)
	cost.position = Vector2(12, 5)
	b.add_child(cost)
	var nm := UIKit.label(str(c["name"]), 15, Color.WHITE, UIKit.FONT_BODY_PATH, 4)
	nm.position = Vector2(42, 7)
	nm.clip_text = true
	nm.size = Vector2(212, 24)
	b.add_child(nm)
	if count > 1:
		var x := UIKit.label("x%d" % count, 16, UIKit.GOLD, UIKit.FONT_DISPLAY_PATH, 6)
		x.position = Vector2(264, 6)
		b.add_child(x)
	if str(c.get("rarity", "")) == "Legendary":
		var star := UIKit.label("★", 16, Color(1, 0.62, 0.08), UIKit.FONT_BODY_PATH, 4)
		star.position = Vector2(286, 6)
		b.add_child(star)
	var cid: String = str(c["id"])
	b.pressed.connect(func() -> void: _remove(cid))
	return b
