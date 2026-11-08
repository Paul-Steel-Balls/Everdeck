extends RefCounted
class_name CardView

# Everdeck — all card/UI presentation. Colors live here so tests can
# pin them (no grey-dominant UI) and every screen stays colorful.
# Polish pass: Hearthstone-style cards (integrated ATK/HP badges, fitted
# text, drop shadows), fan hand, drag targeting, zoned board.

const TABLE_BG := Color(0.03, 0.32, 0.33)      # deep teal felt
const TITLE_BG := Color(0.23, 0.08, 0.42)      # deep purple
const CARD_FACE := Color(0.98, 0.94, 0.85)     # cream card face
const FRAME_MINION := Color(0.95, 0.65, 0.15) # warm amber
const FRAME_SPELL := Color(0.15, 0.55, 1.0)   # bright blue
const FRAME_CHAOS := Color(1.0, 0.25, 0.65)   # hot pink
const BTN_END := Color(0.1, 0.75, 0.3)        # green END TURN / DONE
const BTN_READY := Color(0.95, 0.75, 0.1)     # gold READY
const BTN_BLUE := Color(0.15, 0.45, 0.95)     # blue secondary buttons
const HERO_P1 := Color(0.85, 0.1, 0.2)        # crimson (you)
const HERO_P2 := Color(0.1, 0.3, 0.9)        # royal blue (enemy)
const MANA_GEM := Color(0.95, 0.75, 0.1)      # gold mana
const HP_GEM := Color(0.9, 0.1, 0.2)         # red HP
const ATK_GEM := Color(0.9, 0.1, 0.2)        # red ATK badge
const HP_BADGE := Color(0.1, 0.65, 0.25)      # green HP badge
const GOLD_TEXT := Color(1.0, 0.85, 0.25)
const INK := Color(0.12, 0.1, 0.08)          # near-black text on cards
const FLAVOR_INK := Color(0.45, 0.25, 0.6)    # purple flavor text
const EMOTE_COLORS: Array = [
	Color(0.1, 0.7, 0.7),   # Well played — teal
	Color(1.0, 0.6, 0.1),   # Oops — orange
	Color(1.0, 0.3, 0.7),   # Wow! — pink
	Color(0.6, 0.2, 0.9),   # Threaten — purple
]

# Per-class color schemes (Phase 3): hero frames, class-select buttons,
# deckbuilder header, hero-power button accent.
const CLASS_COLORS: Dictionary = {
	"grunk": Color(0.2, 0.65, 0.15),     # goblin green
	"agatha": Color(0.85, 0.35, 0.45),   # soup-rose
	"presto": Color(0.15, 0.45, 0.95),   # wizard blue
	"barnacle": Color(0.05, 0.6, 0.65),  # sea teal
	"reginald": Color(0.85, 0.65, 0.1),  # knight gold
	"larry": Color(0.55, 0.2, 0.85),     # gambler purple
	"neutral": Color(0.5, 0.5, 0.5),
}

const CLASS_ART: Dictionary = {
	"grunk": "hero_grunk",
	"agatha": "hero_agatha",
	"presto": "hero_presto",
	"barnacle": "hero_barnacle",
	"reginald": "hero_reginald",
	"larry": "hero_larry",
}


static func class_color(class_id: String) -> Color:
	return CLASS_COLORS.get(class_id, CLASS_COLORS["neutral"])


static func class_portrait(class_id: String, w: float = 120, h: float = 120) -> CardArt:
	var art := CardArt.new()
	art.art_id = str(CLASS_ART.get(class_id, "token"))
	art.custom_minimum_size = Vector2(w, h)
	return art

static var _board_tex: Texture2D = null


static func frame_color(card: Dictionary) -> Color:
	if card["type"] == "spell":
		if card["id"] in ["roulette", "mind_trick", "hand_swap", "coin_flip"]:
			return FRAME_CHAOS
		return FRAME_SPELL
	return FRAME_MINION


static func is_chaos(card: Dictionary) -> bool:
	return card["type"] == "spell" and card["id"] in ["roulette", "mind_trick", "hand_swap", "coin_flip"]


# --- Generic helpers ---

static func full_rect(c: Control) -> Control:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c


# Make a Button tile scroll-friendly: the tile itself gets
# MOUSE_FILTER_PASS (it still receives taps via gui_input, but drags
# also reach the parent ScrollContainer), and EVERY descendant gets
# MOUSE_FILTER_IGNORE so no child swallows the drag. Without this, a
# ScrollContainer child with default filters eats touch drags and the
# list can't be scrolled.
static func pass_through(tile: Button) -> Button:
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	_ignore_mouse_recursive(tile)
	return tile


static func _ignore_mouse_recursive(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse_recursive(c)


static func bg_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func label(text: String, size: int = 28, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func panel_style(color: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border_w > 0:
		s.border_width_left = border_w
		s.border_width_right = border_w
		s.border_width_top = border_w
		s.border_width_bottom = border_w
		s.border_color = border
	return s


# StyleBoxFlat with a soft drop shadow (cards feel physical).
static func card_style(frame: Color, border_w: int = 5) -> StyleBoxFlat:
	var s := panel_style(CARD_FACE, 10, frame, border_w)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(3, 4)
	return s


static func button(text: String, size: int = 28, min_w: int = 0, min_h: int = 0, bg: Color = BTN_BLUE, fg: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_stylebox_override("normal", panel_style(bg, 12))
	b.add_theme_stylebox_override("hover", panel_style(bg, 12))
	b.add_theme_stylebox_override("pressed", panel_style(bg, 12))
	b.add_theme_stylebox_override("focus", panel_style(bg, 12))
	# Disabled: dimmed version of the button color — without this, a
	# disabled button falls back to Godot's default dark-grey theme,
	# which reads as a stray dark panel (deckbuilder DONE button).
	b.add_theme_stylebox_override("disabled", panel_style(bg.darkened(0.55), 12))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if min_h > 0:
		b.custom_minimum_size.y = min_h
	return b


static func gem(text: String, bg: Color, size: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", panel_style(bg, 999))
	var l := label(text, size, Color.WHITE if bg.get_luminance() < 0.6 else INK)
	p.add_child(l)
	return p


# --- Text fitting ---
# Largest font size (<= max_size, >= min_size) at which `text` wraps into
# a box of `width` x `max_height`. Pure function — headless-testable.
static func fit_font_size(text: String, width: float, max_height: float, max_size: int, min_size: int) -> int:
	if str(text).is_empty():
		return max_size
	var font: Font = ThemeDB.get_fallback_font()
	var size: int = max_size
	while size > min_size:
		var s: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, size)
		if s.y <= max_height:
			return size
		size -= 1
	return min_size


# --- Fan layout ---
# Returns [{x, y, rot}] for n cards of card_w inside a fan of fan_w.
# Cards overlap (controlled) when crowded; gentle arc + rotation spread.
# Pure function — headless-testable. rot is in radians.
static func fan_transforms(n: int, card_w: float, fan_w: float) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var spacing: float = card_w
	if n > 1:
		spacing = (fan_w - card_w) / float(n - 1)
		spacing = clamp(spacing, card_w * 0.35, card_w)
	var total: float = card_w + spacing * float(n - 1)
	var x0: float = (fan_w - total) / 2.0
	var mid: float = float(n - 1) / 2.0
	for i in n:
		var t: float = 0.0
		if n > 1:
			t = (float(i) - mid) / max(1.0, mid)
		out.append({"x": x0 + float(i) * spacing, "y": t * t * 16.0, "rot": t * 0.21})
	return out


# --- Target highlight ---
# Gold border + warm tint while dragging over valid targets.
static func set_highlight(c: Control, on: bool) -> void:
	var hl: Node = c.find_child("Highlight", false, false)
	if on:
		if hl == null:
			var p := PanelContainer.new()
			p.name = "Highlight"
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_theme_stylebox_override("panel", panel_style(Color(0, 0, 0, 0), 10, Color(1.0, 0.85, 0.1), 5))
			full_rect(p)
			c.add_child(p)
		c.modulate = Color(1.25, 1.12, 0.5)
	else:
		if hl != null:
			# Immediate free (not queue_free): callers check state right away,
			# e.g. drag-end clears highlights then re-checks targets.
			hl.get_parent().remove_child(hl)
			hl.free()
		c.modulate = Color.WHITE


# --- Board texture ---
# Subtle speckled felt, generated once, tiled over the table.
static func board_texture() -> Texture2D:
	if _board_tex != null:
		return _board_tex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.30, 0.31))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for _i in 400:
		var x: int = rng.randi_range(0, 127)
		var y: int = rng.randi_range(0, 127)
		img.set_pixel(x, y, Color(0.02, 0.22, 0.24, 0.5))
	_board_tex = ImageTexture.create_from_image(img)
	return _board_tex


static func board_texture_rect() -> TextureRect:
	var t := TextureRect.new()
	t.texture = board_texture()
	t.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full_rect(t)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# --- Cards ---

# Full card: ornate frame + drop shadow + cost crystal + art + name banner
# + fitted rules text + flavor + INTEGRATED ATK/HP badges pinned to the
# bottom corners (children of the card, never floating below it).
# magnified=true: bigger text, full flavor (for the long-press view).
# Layout is budgeted so content NEVER overflows the card: top + art + name
# + rules (+ flavor) + badge zone == card height. Small hand cards omit
# flavor (read it via magnify); deckbuild + magnified cards show it.
static func make_card_button(card: Dictionary, w: int, h: int, _magnified: bool = false) -> Button:
	# The card is drawn by CardFrame (gilded frame, arched art window,
	# class ribbon, parchment rules with bold keywords, cut gems), fitted
	# into w x h at the frame's own proportions and centred.
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.size = Vector2(w, h)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var fw: float = minf(float(w), float(h) / CardFrame.ASPECT)
	var f := CardFrame.new()
	f.name = "Face"
	f.setup(card, CardFrame.Look.GILDED, fw)
	f.position = Vector2((w - fw) * 0.5, (h - fw * CardFrame.ASPECT) * 0.5)
	b.add_child(f)
	# Scroll-friendly: taps reach the tile via gui_input, drags reach a
	# parent ScrollContainer (deckbuilder pool). Children never swallow.
	pass_through(b)
	return b


static func _stat_badge(text: String, bg: Color, big: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", panel_style(bg, 999, Color(1, 1, 1, 0.6), 2))
	p.add_child(label(text, 18 if not big else 28, Color.WHITE))
	return p


# Big magnified card for the long-press/hover view (~2x hand size).
static func make_magnified_card(card: Dictionary) -> Button:
	return make_card_button(card, 460, 640, true)


# Compact deck-strip tile: cost + name + copy count ("x2"), dark ink text
# on the cream face (white-on-cream was unreadable). One tile per UNIQUE
# card; tap removes a single copy. Fixed compact size, no autowrap (label
# minimum-size blowup made old tiles unpredictably tall).
static func make_deck_tile(card: Dictionary, count: int = 1) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, 64)
	var frame := frame_color(card)
	var sb := card_style(frame, 3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_rect(h)
	h.add_theme_constant_override("separation", 8)
	var cost_l := label("%d" % card["cost"], 22, INK)
	cost_l.custom_minimum_size = Vector2(30, 0)
	cost_l.clip_text = true
	h.add_child(cost_l)
	var name_l := label(card["name"], 16, INK)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_l.clip_text = true
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_l)
	var count_l := label("x%d" % count, 16, INK)
	count_l.custom_minimum_size = Vector2(34, 0)
	count_l.clip_text = true
	h.add_child(count_l)
	b.add_child(h)
	pass_through(b)
	return b


# Board minion token: mini art + name + tags + INTEGRATED ATK/HP badges.
static func make_minion_button(m: Dictionary, mine: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(128, 132)
	var border := Color(0.9, 0.15, 0.15) if m["taunt"] else FRAME_MINION
	var sb := card_style(border, 4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_rect(v)
	v.add_theme_constant_override("separation", 1)
	var art := CardArt.new()
	var card: Dictionary = CardDB.get_card(m.get("card_id", ""))
	# The minion dict carries its own art (tokens: their token art from
	# the card's "token" field); fall back to the card lookup for
	# hand-built minion dicts (tests) that have no "art" key.
	art.art_id = str(m.get("art", card.get("art", "")))
	art.card_id = str(m.get("card_id", ""))
	art.custom_minimum_size = Vector2(112, 52)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var name_l := label(m["name"], 15, INK)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	var tag := ""
	if m["taunt"]:
		tag += "BOUNCER "
	if mine and not m["can_attack"]:
		tag += "zzz"
	if not tag.is_empty():
		v.add_child(label(tag, 13, Color(0.6, 0.1, 0.1)))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, 26)
	v.add_child(spacer)
	b.add_child(v)
	var atk := _stat_badge("%d" % m["attack"], ATK_GEM, false)
	atk.name = "ATKBadge"
	atk.anchor_left = 0.0
	atk.anchor_top = 1.0
	atk.anchor_right = 0.0
	atk.anchor_bottom = 1.0
	atk.offset_left = 6
	atk.offset_top = -38
	atk.offset_right = 50
	atk.offset_bottom = -4
	b.add_child(atk)
	var hp := _stat_badge("%d" % m["health"], HP_BADGE, false)
	hp.name = "HPBadge"
	hp.anchor_left = 1.0
	hp.anchor_top = 1.0
	hp.anchor_right = 1.0
	hp.anchor_bottom = 1.0
	hp.offset_left = -50
	hp.offset_top = -38
	hp.offset_right = -6
	hp.offset_bottom = -4
	b.add_child(hp)
	return b


# Hero panel: colored bar with class name + HP gem (+ mana gem for the
# active player). Uses the class color when a class is given.
static func make_hero_panel(player_idx: int, hp: int, mana: int, max_mana: int, show_mana: bool, class_id: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var bg := class_color(class_id) if class_id != "" else (HERO_P1 if player_idx == 0 else HERO_P2)
	p.add_theme_stylebox_override("panel", panel_style(bg, 10))
	var row := HBoxContainer.new()
	var title: String = "PLAYER %d" % (player_idx + 1)
	if class_id != "":
		title += " — %s" % CardDB.class_display_name(class_id)
	row.add_child(label(title, 24, Color.WHITE))
	row.add_child(gem("%d HP" % hp, Color(0.45, 0.02, 0.08), 22))
	if show_mana:
		row.add_child(gem("MANA %d / %d" % [mana, max_mana], MANA_GEM, 22))
	p.add_child(row)
	return p
