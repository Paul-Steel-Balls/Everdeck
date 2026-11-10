extends Control

# Everdeck Phase 3 + Sprint 1a — UI controller. Pure presentation; all
# rules live in GameState.
# States: TITLE -> CLASSSELECT (P1, then P2) -> DECKBUILD (P1, then P2)
# -> INTERSTITIAL -> MATCH -> GAMEOVER.
# Match: a real 3D tabletop (Board3D in the main viewport, behind the
# 2D overlay — Sprint 1b: moved out of the 1280x720 SubViewport so the 3D
# renders at native resolution) + the hand as 2D fanned cards on top.
# Drag-to-play + 3D curved targeting arrow (minion attacks) / 2D arrow
# (hand cards), tap-to-select (fallback), long-press (touch) / hover
# (desktop) to magnify a card. Hero power: button in the match controls
# (tap; tap a friendly minion for Reginald's targeted power).
# After each player action, main takes the GameState event stream and the
# AnimDirector plays it, then the view fully syncs. Tapping the screen
# while the director plays sets a 3x speed-up for the rest of that batch.
# Sprint 1a.2: readability & layout — centered rows, closer camera, big
# readable tokens, hero plaques with portraits, inspect panel (long-press),
# "what did they play" recap, manual deckbuilder scroll.

enum Screen { TITLE, CLASSSELECT, DECKBUILD, INTERSTITIAL, MATCH, GAMEOVER, ONLINE_MENU, ONLINE_LOBBY }

const LONG_PRESS_MS: int = 400
const DRAG_THRESHOLD: float = 12.0
const HAND_CARD_W: float = 130.0
const HAND_CARD_H: float = 188.0  # HAND_CARD_W x CardFrame.ASPECT
const HAND_ZONE_H: float = 110.0
const VIEW_W: float = 1280.0
const VIEW_H: float = 720.0
const MATCH_LOG_PATH: String = "user://match_log.jsonl"
# Deckbuilder pool: 5 columns of compact tiles (keeps the 360x440 card
# aspect ratio). Grid width = 5*244 + 4*14 = 1276, centered in 1280.
const POOL_COLS: int = 5
const POOL_TILE_W: int = 244
const POOL_TILE_H: int = 298
const SCROLL_DEADZONE: float = 12.0

var _screen: Screen = Screen.TITLE
var _gs: GameState = null
# Sprint MP-1: online play. _online reroutes the class-select /
# deckbuild flow to "my side only", then hands off to a NetMatch +
# OnlineMatch screen. All MP-1 state lives here; the local flow is
# untouched when _online is false.
var _online: bool = false
var _online_role: String = ""  # "host" / "guest"
var _online_code: String = ""
var _online_url: String = ""
var _net_match: NetMatch = null
var _online_match: OnlineMatch = null
var _online_url_edit: LineEdit = null
var _online_code_edit: LineEdit = null
# PC online play: the match runs on the real 3D board. The host's game
# also runs the relay (LocalRelay), so over Tailscale the guest connects
# straight to the host. The board renders NetMatch's mirror GameState;
# every action goes to the host as a request, and each sync (ours or the
# opponent's) is animated through the same director as local play.
var _online3d: bool = false
var _awaiting_sync: bool = false
var _local_relay: LocalRelay = null
var _online_addr_edit: LineEdit = null
var _online_status_label: Label = null
var _online_room_label: Label = null
var _decks: Array = [[], []]
var _classes: Array = ["", ""]
var _selecting_player: int = 0
# True while a class pick from this frame is still "in flight". A second
# pick before the next frame is a duplicate delivery of the same tap
# (touch + emulated mouse), never a real second tap — P2 cannot tap before
# the P2 screen has rendered (next frame). Cleared in _process each frame.
# (Engine.get_frames_drawn() can't be used: it never advances headless.)
var _class_pick_locked: bool = false
var _building_player: int = 0
var _build_deck: Array = []
var _pool_cards: Array = []
var _pending: Dictionary = {}  # {"kind": "card", "hand_idx": int} / {"kind": "attack", "board_idx": int} / {"kind": "hero_power"}
var _game_logged: bool = false

# Deckbuild refs (in-place refresh preserves scroll — no full rebuild).
var _pool_grid: GridContainer = null
var _pool_center: CenterContainer = null  # centers PoolGrid in the scroll area
var _deck_strip: HBoxContainer = null
var _deck_count: Label = null
var _deck_done: Button = null
var _deck_autofill: Button = null
# Sprint 1a.2 (item 1): the deckbuilder no longer relies on the
# ScrollContainer's built-in touch handling (broken on device). Tile and
# empty-space drags are tracked manually: past 12px the gesture becomes
# a scroll (delta applied directly to scroll_vertical/scroll_horizontal,
# fling on release), under 12px it's a tap.
var _pool_scroll: ScrollContainer = null
var _deck_strip_scroll: ScrollContainer = null
var _manual_scroll: Dictionary = {}  # {scroll, horizontal, start_pos, last_pos, last_t, dragging, vel}
var _deck_fling: Dictionary = {}  # {scroll, horizontal, vel}
# Deckbuilder tile press state (separate from the match `_press`
# machinery — pool/strip tiles must NOT start card drags; a drag here
# is a scroll, handled manually).
var _db_press: Dictionary = {}  # {kind, card_id, t, start_pos, dragging, magnified}

# Match interaction state.
var _press: Dictionary = {}   # {ctx, t, down, start_pos, dragging, magnified, node}
var _drag: Dictionary = {}    # {ctx, targets, snapped, home_pos, home_z, grab_offset, press_start, arrow_on}
var _target_nodes: Dictionary = {}  # key -> {"node": Control, "target": Dictionary}
var _hand_cards: Array = []
var _board_zone: Control = null
var _hand_zone: Control = null
var _arrow: Line2D = null
var _arrowhead: Polygon2D = null
var _tarrow: TargetArrow = null
var _magnify_overlay: Control = null
# Sprint 1a.2: inspect panel (long-press any minion/hero/hand card, or tap
# an enemy when not targeting) and the "what did they play" recap.
var _inspect_overlay: Control = null
var _emote_menu: Control = null
var _turn_played_cards: Array = []  # card_ids played this turn, in order
# Sprint 1c: action history (replaces the top-left log line). Match
# state — survives _refresh_match/_clear_overlay; cleared in _start_match.
# Newest first, capped at HistoryColumn.MAX_ENTRIES. Each entry:
# {kind, player, card_id, art_id, name, detail, attacker_uid,
#  target_kind, target_player, target_uid}.
var _history: Array = []
var _history_uid_cards: Dictionary = {}  # minion uid -> card_id (name lookup)
var _history_column: HistoryColumn = null
# Sprint 1c: Signature Move long-press -> inspect; tap still uses it.
var _sig_press: Dictionary = {}
# Sprint 1a.3: hand-card gesture layer (replaces tap-to-play). A tap NEVER
# plays a card: touch down lifts the card, hold >= 0.35s shows a preview,
# drag crosses the play line to play.
const GESTURE_PREVIEW_MS: int = 350
var _hand_preview: Control = null  # large preview card, shown while held
var _toast_label: Label = null
var _stat_badges: StatBadges = null  # Sprint 1a.4: 2D minion stat badges
var _hero_badges: Array = [null, null]  # Sprint 1a.5: 2D hero badge panels
# Sprint 1a.3: input-lock watchdog — if input stays locked longer than
# this, force a full sync, clear state, unlock, and warn naming the flag.
const WATCHDOG_MS: int = 5000
var _watchdog_since: int = 0

# Sprint 1a — 3D match view + animation.
var _board_3d: Board3D = null
var _anim_director: AnimDirector = null
var _animating: bool = false  # input locked while the director plays
# --- vs Computer ---
var _vs_ai: bool = false
var _human_idx: int = 0
var _ai: AIPlayer = null
var _ai_turn: bool = false  # input locked while the computer plays its turn
# Step 2: the 90-second turn clock (TurnTimer draws the last-15s fuse).
# Runs for whoever is at the controls; at zero the turn ends by itself.
var turn_timer_enabled: bool = true
var _turn_timer: TurnTimer = null
var _clock_key: String = ""
var _match_warmed: bool = false
var _sig_was_ready_key: String = ""  # turn key while the Signature Move was still unused  # models preloaded + effects warmed this match
# Set while the player builds a deck for a computer match: {hero, opponent}.
var _pending_ai: Dictionary = {}
var _pick_layer: Control = null  # full-screen, bottom-most: 3D picking


func _ready() -> void:
	_show_title()
	# F3 frame-time readout (one per game, above every screen).
	if get_tree().root.get_node_or_null("PerfLayer") == null:
		var layer := CanvasLayer.new()
		layer.name = "PerfLayer"
		layer.layer = 100
		layer.add_child(PerfHud.new())
		get_tree().root.add_child.call_deferred(layer)


# Sprint 1a.2: the hand fan centers on the ACTUAL canvas width (stretch
# mode canvas_items + aspect expand keeps height at 720 and widens the
# canvas: 1600 on a 20:9 phone, 1280 on 16:9).
func _canvas_width() -> float:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.y <= 0:
		return VIEW_W
	return VIEW_H * float(win.x) / float(win.y)


func _process(delta: float) -> void:
	# A class pick only locks out duplicates within its own frame; clear
	# the lock so the next frame's (real) pick counts.
	_class_pick_locked = false
	# Keep the deckbuilder pool grid centered (the scroll area's width is
	# only known after layout, and changes on viewport resize).
	if _screen == Screen.DECKBUILD:
		_center_deckbuild_grid()
		_deckbuild_fling_step(delta)
	_tick_turn_clock(delta)
	_tick_hover_card()
	_tick_hand_fx(delta)
	# Long-press -> inspect (Sprint 1a.2; touch primary path). Not while
	# animating.
	if _animating or _ai_turn:
		return
	# Sprint 1a.3: hand cards are excluded — their hold shows the gesture
	# preview (not the inspect modal). Long-press inspect still applies
	# to board minions and heroes.
	if not _press.is_empty() and _press.get("down", false) and not _press.get("dragging", false) and not _press.get("magnified", false) and str(_press.get("ctx", {}).get("kind", "")) != "hand_card":
		if Time.get_ticks_msec() - int(_press.get("t", 0)) >= LONG_PRESS_MS:
			var ctx: Dictionary = _press.get("ctx", {})
			var inspect_data: Dictionary = _inspect_data_for_press_ctx(ctx)
			if not inspect_data.is_empty():
				_press["magnified"] = true
				_show_inspect(inspect_data)
	# Deckbuilder tiles use their own press state (see below): long-press
	# a pool/strip tile to magnify it, so the small 5-column tiles stay
	# readable.
	if not _db_press.is_empty() and not _db_press.get("dragging", false) and not _db_press.get("magnified", false):
		if Time.get_ticks_msec() - int(_db_press.get("t", 0)) >= LONG_PRESS_MS:
			var db_card: Dictionary = CardDB.get_card(str(_db_press.get("card_id", "")))
			if not db_card.is_empty():
				_db_press["magnified"] = true
				_show_magnify(db_card)
	# Sprint 1a.3: hand-card gesture — hold still >= 0.35s (no drag) shows
	# a large preview above the hand while the finger stays down.
	if not _press.is_empty() and str(_press.get("ctx", {}).get("kind", "")) == "hand_card" and _press.get("down", false) and not _press.get("dragging", false) and not _press.get("preview", false):
		if Time.get_ticks_msec() - int(_press.get("t", 0)) >= GESTURE_PREVIEW_MS:
			_press["preview"] = true
			_show_hand_preview(_press["ctx"])
	# Sprint 1c: Signature Move long-press -> inspect (name/cost/text).
	# Same 0.35s timing as hand cards; moving off cancels (the gui_input
	# handler clears _sig_press); tap still uses the move.
	if not _sig_press.is_empty() and not bool(_sig_press.get("long_fired", false)):
		if Time.get_ticks_msec() - int(_sig_press.get("t", 0)) >= GESTURE_PREVIEW_MS:
			_sig_press["long_fired"] = true
			var pdata: Dictionary = _inspect_data_for_hero_power(_gs.active) if _gs != null else {}
			if not pdata.is_empty():
				_show_inspect(pdata)
	# Sprint 1a.3: input-lock watchdog. If input stays locked (_animating
	# or any modal flag) for more than WATCHDOG_MS, force a full sync,
	# clear all press/drag/pending/modal state, unlock, and warn naming
	# the stuck flag. This is the backstop for a modal whose close path
	# is broken (the 1a.2 inspect softlock).
	var locked_flag: String = ""
	if _animating:
		locked_flag = "_animating"
	elif _inspect_overlay != null:
		locked_flag = "_inspect_overlay"
	# (The emote picker is not a lock: any tap off its buttons closes it,
	# and a player may take their time choosing.)
	elif _magnify_overlay != null:
		locked_flag = "_magnify_overlay"
	if locked_flag != "":
		if _watchdog_since == 0:
			_watchdog_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _watchdog_since > WATCHDOG_MS:
			push_warning("Everdeck watchdog: input locked by %s for >%dms; forcing full sync + unlock" % [locked_flag, WATCHDOG_MS])
			_dismiss_all_modals()
			_press = {}
			_drag = {}
			_db_press = {}
			_pending = {}
			_animating = false
			_watchdog_since = 0
			if _screen == Screen.MATCH:
				_refresh_match()
			elif _screen == Screen.DECKBUILD:
				_refresh_deckbuild()
	else:
		_watchdog_since = 0


# Sprint 1a.3: Android back button closes the topmost modal (any tap
# anywhere also closes them, via each overlay's gui_input).
func _input(event: InputEvent) -> void:
	# A hand card dragged with the mouse hides while its targeting arrow
	# is out, and a hidden Control gets no more mouse events, so the
	# release (the moment the card is played) would never arrive. Route
	# the drag and the release from here while the card is hidden.
	if not _press.is_empty() and str(_press.get("family", "")) == "mouse" and _press.has("preview"):
		var pn: Control = _press.get("node")
		if pn != null and is_instance_valid(pn) and not pn.is_visible_in_tree():
			var le: InputEvent = make_input_local(event)
			if le is InputEventMouseMotion and (le.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				_on_gesture_move(le.position)
				get_viewport().set_input_as_handled()
				return
			if le is InputEventMouseButton and le.button_index == MOUSE_BUTTON_LEFT and not le.pressed:
				_on_gesture_release(le.position)
				get_viewport().set_input_as_handled()
				return
	# Esc during a computer match: ask to leave.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _screen == Screen.MATCH and _vs_ai:
			_toggle_leave_prompt()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		_dismiss_all_modals()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACK:
		_dismiss_all_modals()


# Sprint 1a.3: safety net — every modal closes on any tap anywhere (each
# overlay's own gui_input), the Android back button (above), and the
# start of any new action (callers: _after_action, _after_end_turn,
# _on_end_turn).
func _dismiss_all_modals() -> void:
	_dismiss_inspect()
	_dismiss_emote_menu()
	_dismiss_magnify()
	_hide_hand_preview()


func _press_card(ctx: Dictionary) -> Dictionary:
	match ctx.get("kind", ""):
		"hand_card":
			var active: int = _gs.active if _gs != null else 0
			var hand: Array = _gs.players[active]["hand"] if _gs != null else []
			var idx: int = int(ctx.get("hand_idx", -1))
			if idx >= 0 and idx < hand.size():
				return CardDB.get_card(hand[idx])
		"my_minion":
			if _gs != null:
				var board: Array = _gs.players[_gs.active]["board"]
				var idx2: int = int(ctx.get("board_idx", -1))
				if idx2 >= 0 and idx2 < board.size():
					return CardDB.get_card(board[idx2].get("card_id", ""))
		"target":
			var t: Dictionary = ctx.get("target", {})
			if t.get("kind", "") == "minion" and _gs != null:
				var b: Array = _gs.players[int(t.get("player", 0))]["board"]
				var bi: int = int(t.get("board_idx", -1))
				if bi >= 0 and bi < b.size():
					return CardDB.get_card(b[bi].get("card_id", ""))
	return {}


# --- Helpers ---

func _clear() -> void:
	# Screen change: free EVERYTHING, including the 3D board (allowed —
	# _clear() only runs on screen changes, never mid-match).
	for c in get_children():
		if c == _net_match or c == _local_relay:
			continue
		c.queue_free()
	_pending = {}
	_press = {}
	_db_press = {}
	_drag = {}
	_target_nodes = {}
	_sig_press = {}
	_hand_cards = []
	_board_zone = null
	_hand_zone = null
	_arrow = null
	_arrowhead = null
	_tarrow = null
	_magnify_overlay = null
	_pool_center = null
	_pool_grid = null
	_deck_strip = null
	_deck_count = null
	_deck_done = null
	_deck_autofill = null
	_history_column = null
	_board_3d = null
	_anim_director = null
	_stat_badges = null
	_pick_layer = null
	_hero_badges = [null, null]
	_turn_timer = null
	_clock_key = ""
	_match_warmed = false
	_animating = false


# Match refresh: free the 2D overlay only. The 3D board + director persist
# (Board3D.sync() updates them in place — never free + rebuild mid-match).
# Unlike _clear(), this PRESERVES _pending: the old _clear() wiped it on
# every _refresh_match(), which silently broke tap-to-target (set a
# pending action -> refresh -> pending gone -> tap on target did nothing).
func _clear_overlay() -> void:
	for c in get_children():
		if c == _board_3d:
			continue
		if c is AnimDirector:
			continue
		if c == _stat_badges:
			continue
		if c in _hero_badges:
			continue
		if c == _turn_timer:
			continue
		if c == _net_match or c == _local_relay:
			continue
		# Detach immediately (not just queue_free): _refresh_match can run
		# twice without a frame in between, and a queued-but-still-child
		# node with the same name would force Godot to auto-rename the
		# new node (breaking find_child lookups).
		remove_child(c)
		c.queue_free()
	_press = {}
	_drag = {}
	_target_nodes = {}
	_sig_press = {}
	_hand_cards = []
	_board_zone = null
	_hand_zone = null
	_arrow = null
	_arrowhead = null
	_tarrow = null
	_magnify_overlay = null
	_inspect_overlay = null
	_emote_menu = null
	_pool_center = null
	_pick_layer = null
	_history_column = null


func _full_rect(c: Control) -> Control:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c


# Does playing this card need the player to pick a target right now?
# (Random effects like swap_stats need none; a targeted Battlecry with no
# valid targets needs none either — the Battlecry fizzles.)
func _card_needs_target(card: Dictionary) -> bool:
	if _gs == null:
		return false
	return not _gs.card_target_options(_gs.active, card).is_empty()


# --- Title ---

func _show_title() -> void:
	_screen = Screen.TITLE
	_clear()
	_vs_ai = false
	_ai_turn = false
	_pending_ai = {}
	_music("menu")
	var title := TitleScreen.new()
	title.name = "TitleScreen"
	add_child(title)
	title.play_pressed.connect(func() -> void: _goto(_show_hero_select))
	title.online_pressed.connect(func() -> void: _goto(_show_online_menu))
	title.quit_pressed.connect(func() -> void: get_tree().quit())
	title.lab_pressed.connect(func() -> void: _goto(_show_lab))
	title.export_pressed.connect(func() -> void: title.set_status(_export_log()))


# Battlefield Preview (options for the 3D rebuild).
func _show_lab() -> void:
	_screen = Screen.CLASSSELECT
	_clear()
	_music("battle")
	var lab := HoloLab.new()
	lab.name = "HoloLab"
	add_child(lab)
	lab.back_pressed.connect(func() -> void: _goto(_show_title))


# Hero select for a match against the computer.
func _show_hero_select() -> void:
	_screen = Screen.CLASSSELECT
	_clear()
	_pending_ai = {}
	_music("select")
	var hs := HeroSelect.new()
	hs.name = "HeroSelect"
	add_child(hs)
	hs.back_pressed.connect(func() -> void: _goto(_show_title))
	hs.start_quick.connect(func(hero: String, opp: String) -> void:
		_goto(func() -> void: start_vs_ai(hero, AIPlayer.build_deck(hero), opp)))
	hs.start_build.connect(func(hero: String, opp: String) -> void:
		_goto(func() -> void: _show_deck_builder(hero, opp)))


func _show_deck_builder(hero: String, opp: String) -> void:
	_screen = Screen.DECKBUILD
	_clear()
	_music("select")
	var db := DeckBuilder.new()
	db.name = "DeckBuilder"
	db.setup(hero)
	add_child(db)
	db.back_pressed.connect(func() -> void: _goto(_show_hero_select))
	db.done.connect(func(deck: Array) -> void:
		_goto(func() -> void: start_vs_ai(hero, deck, opp)))


func _music(key: String) -> void:
	var m: Node = get_node_or_null("/root/Music")
	if m != null:
		m.play(key)


# Whose side is drawn at the bottom: the human vs the computer; the
# active player in the old pass-and-play mode.
func _view() -> int:
	if _vs_ai or _online3d:
		return _human_idx
	return _gs.active if _gs != null else 0


# Animated screen change (falls back to an instant change when the
# Transition autoload is absent, e.g. in some test harnesses).
func _goto(fn: Callable) -> void:
	var tr: Node = get_node_or_null("/root/Transition")
	if tr == null:
		fn.call()
	else:
		tr.go(fn)


func _on_play() -> void:
	_selecting_player = 0
	_classes = ["", ""]
	_show_class_select()


# --- Class select (P1 picks, then P2 picks; mirrors allowed) ---

func _show_class_select() -> void:
	_screen = Screen.CLASSSELECT
	_clear()
	add_child(CardView.bg_rect(CardView.TITLE_BG))
	var root := VBoxContainer.new()
	_full_rect(root)
	root.add_child(CardView.label("Player %d — Choose your class" % (_selecting_player + 1), 36))
	root.add_child(CardView.label("Same class for both players is fine (mirror match).", 22))
	var grid := GridContainer.new()
	grid.name = "ClassGrid"
	grid.columns = 3
	# Center the grid in the full-width VBox (a plain GridContainer sits at
	# the left edge, leaving a big empty margin on the right).
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for class_id in CardDB.CLASS_IDS:
		var hp: Dictionary = CardDB.hero_power_for(class_id)
		var b := CardView.button("", 20, 380, 280, CardView.class_color(class_id))
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		CardView.full_rect(col)
		col.add_theme_constant_override("separation", 2)
		var art := CardView.class_portrait(class_id, 110, 110)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art_wrap := HBoxContainer.new()
		art_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		art_wrap.add_child(art)
		col.add_child(art_wrap)
		col.add_child(CardView.label(CardDB.class_display_name(class_id), 26, Color.WHITE))
		col.add_child(CardView.label(str(hp.get("name", "")), 20, CardView.GOLD_TEXT))
		var hp_l := CardView.label(str(hp.get("text", "")), 17)
		hp_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(hp_l)
		b.add_child(col)
		b.pressed.connect(_on_class_picked.bind(class_id))
		grid.add_child(b)
	root.add_child(grid)
	add_child(root)


func _on_class_picked(class_id: String) -> void:
	# Duplicate-delivery guard: a second pick before the next frame is the
	# same tap delivered twice (touch + emulated mouse), not P2's tap —
	# P2 cannot tap before the P2 screen renders (a later frame).
	# Without this, one P1 tap consumed P2's choice with P1's class.
	if _class_pick_locked:
		return
	_class_pick_locked = true
	_classes[_selecting_player] = class_id
	if _online:
		# Online: only my own class + deck are picked locally.
		_building_player = 0
		_build_deck = []
		_show_deckbuild()
		return
	if _selecting_player == 0:
		_selecting_player = 1
		_show_class_select()
	else:
		_building_player = 0
		_build_deck = []
		_show_deckbuild()


# --- Deckbuilding (GRID picker, in-place refresh preserves scroll) ---
# Class-filtered: only the building player's class cards + neutrals.
# Copy limits by rarity: Legendary max 1, everything else max 2.

func _show_deckbuild() -> void:
	_screen = Screen.DECKBUILD
	_clear()
	add_child(CardView.bg_rect(CardView.TABLE_BG))
	var class_id: String = _classes[_building_player]
	_pool_cards = CardDB.cards_for_class(class_id)
	var root := VBoxContainer.new()
	_full_rect(root)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", CardView.panel_style(CardView.class_color(class_id), 10))
	var header_l := CardView.label("Player %d — %s — Build your deck" % [_building_player + 1, CardDB.class_display_name(class_id)], 34)
	header.add_child(header_l)
	root.add_child(header)
	root.add_child(CardView.label("Tap a card to add (Legendary max 1 copy, others max 2). Tap a deck card to remove it.", 22))

	# Pool GRID (scrollable, POOL_COLS columns of compact tiles).
	# Centered via a CenterContainer: a ScrollContainer pins its child to
	# the left edge, which left a big empty margin on the right.
	# Sprint 1a.2: scrolling is manual (the ScrollContainer's built-in
	# touch handling is broken on device). Tile and empty-space drags are
	# tracked in gui_input; past 12px the delta is applied directly to
	# scroll_vertical, with fling on release.
	var scroll := ScrollContainer.new()
	scroll.name = "PoolScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = SCROLL_DEADZONE
	scroll.gui_input.connect(_on_deckbuild_scroll_input.bind(scroll, false))
	var center := CenterContainer.new()
	center.name = "PoolCenter"
	var grid := GridContainer.new()
	grid.name = "PoolGrid"
	grid.columns = POOL_COLS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for card in _pool_cards:
		var tile := CardView.make_card_button(card, POOL_TILE_W, POOL_TILE_H)
		# gui_input (not pressed): lets us tell a tap (add card) from a
		# drag (scroll) and from a long-press (magnify).
		tile.gui_input.connect(_on_pool_tile_input.bind(card["id"], tile))
		grid.add_child(tile)
	center.add_child(grid)
	scroll.add_child(center)
	root.add_child(scroll)
	_pool_grid = grid
	_pool_center = center
	_pool_scroll = scroll

	# Deck strip (bottom): one compact tile per UNIQUE card with its copy
	# count; tap a tile to remove a single copy. Same manual horizontal
	# scroll as the pool.
	var deck_scroll := ScrollContainer.new()
	deck_scroll.name = "DeckStripScroll"
	deck_scroll.custom_minimum_size.y = 84
	deck_scroll.scroll_deadzone = SCROLL_DEADZONE
	deck_scroll.gui_input.connect(_on_deckbuild_scroll_input.bind(deck_scroll, true))
	var deck_row := HBoxContainer.new()
	deck_row.name = "DeckStrip"
	deck_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	deck_row.add_theme_constant_override("separation", 8)
	deck_scroll.add_child(deck_row)
	root.add_child(deck_scroll)
	_deck_strip = deck_row
	_deck_strip_scroll = deck_scroll

	# Bottom bar: count + AUTO-FILL + DONE.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	_deck_count = CardView.label("Deck: %d / 30" % _build_deck.size(), 26)
	bottom.add_child(_deck_count)
	_deck_autofill = CardView.button("AUTO-FILL", 24, 220, 64, CardView.BTN_BLUE)
	_deck_autofill.pressed.connect(_on_autofill)
	bottom.add_child(_deck_autofill)
	_deck_done = CardView.button("DONE", 32, 200, 64, CardView.BTN_END)
	_deck_done.pressed.connect(_on_deck_done)
	bottom.add_child(_deck_done)
	root.add_child(bottom)

	add_child(root)
	_refresh_deckbuild()


# Keep the pool grid horizontally centered: the CenterContainer must be as
# wide as the scroll area (so the grid centers inside it), but never
# narrower than the grid itself (so nothing clips on a narrow viewport).
func _center_deckbuild_grid() -> void:
	if not is_instance_valid(_pool_center) or not is_instance_valid(_pool_grid):
		return
	var scroll: ScrollContainer = _pool_center.get_parent() as ScrollContainer
	if scroll == null or scroll.size.x <= 0.0:
		return
	var want: float = max(scroll.size.x, _pool_grid.get_minimum_size().x)
	if abs(_pool_center.custom_minimum_size.x - want) > 0.5:
		_pool_center.custom_minimum_size.x = want


# In-place refresh: badges, strip, count, DONE — WITHOUT rebuilding the
# pool grid, so the scroll position never jumps back to the top.
func _refresh_deckbuild() -> void:
	if _pool_grid == null:
		return
	for i in _pool_cards.size():
		var tile: Button = _pool_grid.get_child(i)
		# Remove old badge.
		var old: Node = tile.find_child("CountBadge", false, false)
		if old != null:
			tile.remove_child(old)
			old.free()
		var card: Dictionary = _pool_cards[i]
		var in_deck: int = _build_deck.count(card["id"])
		if in_deck > 0:
			var badge := PanelContainer.new()
			badge.name = "CountBadge"
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_stylebox_override("panel", CardView.panel_style(CardView.MANA_GEM, 999))
			badge.add_child(CardView.label("x%d" % in_deck, 22, CardView.INK))
			badge.anchor_left = 1.0
			badge.anchor_top = 0.0
			badge.anchor_right = 1.0
			badge.anchor_bottom = 0.0
			badge.offset_left = -56
			badge.offset_top = 6
			badge.offset_right = -6
			badge.offset_bottom = 42
			tile.add_child(badge)
		tile.modulate = Color(0.45, 0.45, 0.45) if in_deck >= CardDB.max_copies(card) else Color.WHITE
	# Deck strip: one tile per unique card, with its copy count.
	for c in _deck_strip.get_children():
		_deck_strip.remove_child(c)
		c.free()
	var seen: Dictionary = {}
	var order: Array = []
	for cid in _build_deck:
		if not seen.has(cid):
			seen[cid] = 0
			order.append(cid)
		seen[cid] = int(seen[cid]) + 1
	for cid in order:
		var card: Dictionary = CardDB.get_card(cid)
		var tile := CardView.make_deck_tile(card, int(seen[cid]))
		tile.gui_input.connect(_on_strip_tile_input.bind(cid, tile))
		_deck_strip.add_child(tile)
	_deck_count.text = "Deck: %d / 30" % _build_deck.size()
	_deck_done.disabled = _build_deck.size() != GameState.DECK_SIZE


func _on_add_card(card_id: String) -> void:
	if _build_deck.size() >= GameState.DECK_SIZE:
		return
	if _build_deck.count(card_id) >= CardDB.max_copies(CardDB.get_card(card_id)):
		return
	_build_deck.append(card_id)
	_refresh_deckbuild()


func _on_remove_card_by_id(card_id: String) -> void:
	# Strip tiles are collapsed by unique card; removing takes one copy.
	var idx: int = _build_deck.find(card_id)
	if idx >= 0:
		_build_deck.remove_at(idx)
		_refresh_deckbuild()


func _on_deck_done() -> void:
	if not GameState.validate_deck(_build_deck, _classes[_building_player]):
		return
	_decks[_building_player] = _build_deck.duplicate()
	if not _pending_ai.is_empty():
		var pa: Dictionary = _pending_ai
		_pending_ai = {}
		var built: Array = _build_deck.duplicate()
		_goto(func() -> void: start_vs_ai(str(pa["hero"]), built, str(pa["opponent"])))
		return
	if _online:
		_start_online_connection()
		return
	if _building_player == 0:
		_building_player = 1
		_build_deck = []
		_show_deckbuild()
	else:
		_start_match()


# --- Deckbuilder tile input (tap vs scroll-drag vs long-press) ---
# Pool/strip tiles use gui_input (not the Button.pressed signal) so a
# touch drag can be told apart from a tap: tiles are MOUSE_FILTER_PASS,
# so the ScrollContainer also sees the drag and scrolls; we just make
# sure a drag doesn't ALSO add/remove a card. A long-press (no drag)
# magnifies the card via the shared _process check.

func _on_pool_tile_input(event: InputEvent, card_id: String, node: Control) -> void:
	_on_deckbuild_tile_input(event, "pool", card_id, node)


func _on_strip_tile_input(event: InputEvent, card_id: String, node: Control) -> void:
	_on_deckbuild_tile_input(event, "strip", card_id, node)


# Sprint 1a.3: canvas-space position of an event (gui_input positions
# are LOCAL to the receiving control; the tile moves as the content
# scrolls, so tile-local deltas fed back the scroll they just caused).
func _scroll_canvas_pos(event: InputEvent, node: Control) -> Vector2:
	return node.get_global_transform_with_canvas() * event.position


func _scroll_family(event: InputEvent) -> String:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return "touch"
	return "mouse"


func _on_deckbuild_tile_input(event: InputEvent, kind: String, card_id: String, node: Control = null) -> void:
	# Sprint 1a.3: manual scroll (the ScrollContainer's built-in touch
	# handling is broken on device). Past 12px a drag becomes a scroll:
	# the delta is applied directly to the scroll offset, the tap is
	# cancelled, and the drag event is consumed so the ScrollContainer
	# never double-scrolls. Under 12px it's a tap.
	# Drags are tracked in CANVAS space (the tile moves under the finger
	# as the content scrolls, so tile-local coords fed the scroll back
	# into itself) and only ONE input family is processed per gesture
	# (a press locks the family; the other family's events are ignored).
	var scroll: ScrollContainer = _deck_strip_scroll if kind == "strip" else _pool_scroll
	var horizontal: bool = kind == "strip"
	var ref: Control = node if node != null else scroll
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_manual_scroll(scroll, horizontal, _scroll_canvas_pos(event, ref), "touch", ref)
			_db_press = {"kind": kind, "card_id": card_id, "t": Time.get_ticks_msec(), "start_pos": event.position, "dragging": false, "magnified": false}
		else:
			_end_manual_scroll("touch")
			_on_deckbuild_tile_release()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_begin_manual_scroll(scroll, horizontal, _scroll_canvas_pos(event, ref), "mouse", ref)
			_db_press = {"kind": kind, "card_id": card_id, "t": Time.get_ticks_msec(), "start_pos": event.position, "dragging": false, "magnified": false}
		else:
			_end_manual_scroll("mouse")
			_on_deckbuild_tile_release()
	elif event is InputEventScreenDrag:
		_manual_scroll_drag(_scroll_canvas_pos(event, ref), "touch", node)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_manual_scroll_drag(_scroll_canvas_pos(event, ref), "mouse", node)


# A drag that starts on empty scroll space (no tile owns the press).
func _on_deckbuild_scroll_input(event: InputEvent, scroll: ScrollContainer, horizontal: bool) -> void:
	if not _db_press.is_empty() or not _manual_scroll.is_empty():
		return  # a tile owns this gesture
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_manual_scroll(scroll, horizontal, _scroll_canvas_pos(event, scroll), "touch", scroll)
		else:
			_end_manual_scroll("touch")
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_manual_scroll(scroll, horizontal, _scroll_canvas_pos(event, scroll), "mouse", scroll)
			else:
				_end_manual_scroll("mouse")
	elif event is InputEventScreenDrag:
		_manual_scroll_drag(_scroll_canvas_pos(event, scroll), "touch", scroll)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_manual_scroll_drag(_scroll_canvas_pos(event, scroll), "mouse", scroll)


func _begin_manual_scroll(scroll: ScrollContainer, horizontal: bool, pos: Vector2, family: String, ref: Control) -> void:
	_deck_fling = {}  # a new press kills any in-flight fling
	_manual_scroll = {"scroll": scroll, "horizontal": horizontal, "family": family, "ref": ref, "start_pos": pos, "last_pos": pos, "last_t": Time.get_ticks_msec(), "dragging": false, "vel": Vector2.ZERO}


func _manual_scroll_drag(canvas_pos: Vector2, family: String, node: Control) -> void:
	if _manual_scroll.is_empty():
		return
	var ms: Dictionary = _manual_scroll
	if str(ms.get("family", "")) != family:
		return  # Sprint 1a.3: one input family per gesture.
	var pos: Vector2 = canvas_pos
	if not bool(ms.get("dragging", false)):
		if pos.distance_to(ms["start_pos"]) > SCROLL_DEADZONE:
			ms["dragging"] = true
			if node != null:
				# Consume the drag so the ScrollContainer's native
				# handling never double-scrolls.
				node.accept_event()
			if not _db_press.is_empty():
				_db_press["dragging"] = true  # suppress the tap
	if bool(ms.get("dragging", false)):
		var delta: Vector2 = pos - ms["last_pos"]
		var now: int = Time.get_ticks_msec()
		var dt: float = maxf(1.0, float(now - int(ms["last_t"]))) / 1000.0
		var scroll: ScrollContainer = ms["scroll"]
		if scroll != null:
			if bool(ms["horizontal"]):
				scroll.scroll_horizontal = _clamp_scroll_h(scroll, scroll.scroll_horizontal - delta.x)
			else:
				scroll.scroll_vertical = _clamp_scroll_v(scroll, scroll.scroll_vertical - delta.y)
		ms["vel"] = delta / dt
		ms["last_pos"] = pos
		ms["last_t"] = now


func _end_manual_scroll(family: String) -> void:
	# Release: a scroll in motion keeps flinging (decays in _process);
	# a press that never scrolled is a tap (handled by the caller).
	if _manual_scroll.is_empty():
		return
	if str(_manual_scroll.get("family", "")) != family:
		return  # Sprint 1a.3: one input family per gesture.
	var ms: Dictionary = _manual_scroll
	_manual_scroll = {}
	if not bool(ms.get("dragging", false)):
		return
	var scroll: ScrollContainer = ms["scroll"]
	if scroll == null or _screen != Screen.DECKBUILD:
		return
	var vel: Vector2 = ms["vel"]
	var v: float = vel.x if bool(ms["horizontal"]) else vel.y
	if absf(v) > 60.0:
		_deck_fling = {"scroll": scroll, "horizontal": bool(ms["horizontal"]), "vel": clampf(v, -3000.0, 3000.0)}


func _deckbuild_fling_step(delta: float) -> void:
	if _deck_fling.is_empty():
		return
	var f: Dictionary = _deck_fling
	var scroll: ScrollContainer = f["scroll"]
	if scroll == null or not is_instance_valid(scroll):
		_deck_fling = {}
		return
	var v: float = float(f["vel"])
	if absf(v) < 20.0:
		_deck_fling = {}
		return
	if bool(f["horizontal"]):
		scroll.scroll_horizontal = _clamp_scroll_h(scroll, scroll.scroll_horizontal - v * delta)
	else:
		scroll.scroll_vertical = _clamp_scroll_v(scroll, scroll.scroll_vertical - v * delta)
	f["vel"] = v * exp(-3.5 * delta)


func _clamp_scroll_v(scroll: ScrollContainer, val: float) -> float:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	return clampf(val, 0.0, maxf(0.0, bar.max_value - bar.page))


func _clamp_scroll_h(scroll: ScrollContainer, val: float) -> float:
	var bar: HScrollBar = scroll.get_h_scroll_bar()
	return clampf(val, 0.0, maxf(0.0, bar.max_value - bar.page))


func _on_deckbuild_tile_release() -> void:
	if _db_press.is_empty():
		return
	var was_dragging: bool = _db_press.get("dragging", false)
	var was_mag: bool = _db_press.get("magnified", false)
	var kind: String = str(_db_press.get("kind", ""))
	var card_id: String = str(_db_press.get("card_id", ""))
	_db_press = {}
	if was_mag or was_dragging:
		return
	if kind == "pool":
		_on_add_card(card_id)
	elif kind == "strip":
		_on_remove_card_by_id(card_id)


# --- AUTO-FILL (playtesting convenience) ---
# Fills the remaining deck slots with random legal cards for the current
# class (own class + neutrals, copy limits respected). UI-layer only: it
# uses its own RNG and never touches the game engine's seeded RNG.
func _on_autofill() -> void:
	_autofill_deck()
	_refresh_deckbuild()


func _autofill_deck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var class_id: String = _classes[_building_player]
	var pool: Array = CardDB.cards_for_class(class_id)
	if pool.is_empty():
		return
	var counts: Dictionary = {}
	for cid in _build_deck:
		counts[cid] = int(counts.get(cid, 0)) + 1
	var attempts: int = 0
	while _build_deck.size() < GameState.DECK_SIZE and attempts < 20000:
		attempts += 1
		var card: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var cid: String = str(card["id"])
		if int(counts.get(cid, 0)) < CardDB.max_copies(card):
			_build_deck.append(cid)
			counts[cid] = int(counts.get(cid, 0)) + 1


# --- Match ---

func _start_match() -> void:
	_music("battle")
	_gs = GameState.new()
	_gs.setup(_decks[0], _decks[1], _classes[0], _classes[1])
	_game_logged = false
	# Sprint 1c: fresh match, fresh action history.
	_history = []
	_history_uid_cards = {}
	_history_column = null
	if _vs_ai:
		_turn_played_cards = []
		_ai_turn = false
		_clear()
		_refresh_match()
		_maybe_run_ai()
		return
	_show_interstitial(0, "Player 1 starts! Pass the phone to Player 1.")


# --- Sprint MP-1: online play flow ---
# Title -> PLAY ONLINE -> menu (host / join with code) -> class select
# (mine only) -> deckbuild (mine only) -> lobby -> OnlineMatch screen.
# NOTE: NetMatch is added as a child AFTER the lobby's _clear() (which
# frees all children), and is removed by hand before returning to the
# title screen, for the same reason.

func _show_online_menu() -> void:
	_screen = Screen.ONLINE_MENU
	_clear()
	add_child(CardView.bg_rect(CardView.TITLE_BG))
	var v := VBoxContainer.new()
	_full_rect(v)
	v.add_theme_constant_override("separation", 14)
	v.add_spacer(true)
	v.add_child(_center(CardView.label("PLAY ONLINE", 48, CardView.GOLD_TEXT)))
	v.add_child(_center(CardView.label("Both PCs on the same Tailscale network. One hosts, the other joins.", 22)))
	var host_btn := CardView.button("HOST A GAME", 32, 360, 72, CardView.BTN_END)
	host_btn.pressed.connect(_on_online_host)
	v.add_child(_center(host_btn))
	v.add_child(_center(CardView.label("or join your friend's game:", 22)))
	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 10)
	_online_addr_edit = LineEdit.new()
	_online_addr_edit.placeholder_text = "Host's Tailscale name or address"
	_online_addr_edit.text = _load_last_host()
	_online_addr_edit.custom_minimum_size = Vector2(460, 56)
	_online_addr_edit.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	join_row.add_child(_online_addr_edit)
	var join_btn := CardView.button("JOIN", 28, 200, 56, CardView.BTN_BLUE)
	join_btn.pressed.connect(_on_online_join)
	join_row.add_child(join_btn)
	v.add_child(join_row)
	_online_status_label = CardView.label("", 22)
	v.add_child(_center(_online_status_label))
	var back := CardView.button("BACK", 24, 200, 56, CardView.BTN_BLUE)
	back.pressed.connect(_show_title)
	v.add_child(_center(back))
	v.add_spacer(true)
	add_child(v)


func _center(c: Control) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(c)
	return row


func _on_online_host() -> void:
	_online_url = "ws://127.0.0.1:%d" % LocalRelay.PORT
	_online = true
	_online_role = "host"
	_online_code = ""
	_selecting_player = 0
	_classes = ["", ""]
	_show_class_select()


func _on_online_join() -> void:
	var addr: String = _online_addr_edit.text.strip_edges()
	if addr == "":
		_online_status_label.text = "Type the host's Tailscale name or address first."
		return
	_save_last_host(addr)
	if "://" in addr:
		_online_url = addr
	elif addr.count(":") == 1:
		_online_url = "ws://%s" % addr  # name:port
	else:
		_online_url = "ws://%s:%d" % [addr, LocalRelay.PORT]
	_online = true
	_online_role = "guest"
	_online_code = ""
	_selecting_player = 0
	_classes = ["", ""]
	_show_class_select()


# The last address joined, remembered for next time.
func _load_last_host() -> String:
	var f := FileAccess.open("user://last_host.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


func _save_last_host(addr: String) -> void:
	var f := FileAccess.open("user://last_host.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(addr)


# This PC's Tailscale addresses (100.64.0.0/10), to tell the friend.
static func tailscale_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var parts: PackedStringArray = str(a).split(".")
		if parts.size() == 4 and parts[0] == "100" and int(parts[1]) >= 64 and int(parts[1]) <= 127:
			out.append(str(a))
	return out


func _show_online_lobby() -> void:
	_screen = Screen.ONLINE_LOBBY
	_clear()
	add_child(CardView.bg_rect(CardView.TITLE_BG))
	var v := VBoxContainer.new()
	_full_rect(v)
	v.add_spacer(true)
	v.add_child(CardView.label("ONLINE LOBBY", 44, CardView.GOLD_TEXT))
	_online_room_label = CardView.label("", 40, CardView.GOLD_TEXT)
	v.add_child(_online_room_label)
	_online_status_label = CardView.label("Connecting…", 26)
	v.add_child(_online_status_label)
	var cancel := CardView.button("CANCEL", 26, 240, 60, CardView.BTN_BLUE)
	cancel.pressed.connect(_cancel_online)
	v.add_child(cancel)
	v.add_spacer(true)
	add_child(v)


func _start_online_connection() -> void:
	_show_online_lobby()
	_net_match = NetMatch.new()
	add_child(_net_match)
	_net_match.status_changed.connect(func(t: String) -> void:
		if is_instance_valid(_online_status_label):
			_online_status_label.text = t)
	_net_match.room_ready.connect(func(_code: String) -> void:
		if is_instance_valid(_online_status_label):
			_online_status_label.text = "Waiting for your friend to join…")
	_net_match.failed.connect(func(reason: String) -> void:
		if is_instance_valid(_online_status_label):
			_online_status_label.text = reason)
	_net_match.match_started.connect(_on_online_match_started)
	if _online_role == "host":
		if _local_relay == null:
			_local_relay = LocalRelay.new()
			_local_relay.name = "LocalRelay"
			add_child(_local_relay)
		if not _local_relay.is_listening() and _local_relay.start() != OK:
			_online_status_label.text = "Couldn't open port %d to host (is another Everdeck already hosting?)" % LocalRelay.PORT
			return
		var ts: Array = tailscale_addresses()
		if is_instance_valid(_online_room_label):
			_online_room_label.text = ("Tell your friend to join: %s" % ", ".join(ts)) if not ts.is_empty() else "Tell your friend to join with this PC's Tailscale name"
		_net_match.host_game(_online_url, _decks[0], _classes[0])
	else:
		_net_match.join_game(_online_url, _online_code, _decks[0], _classes[0])


func _on_online_match_started(my_idx: int) -> void:
	_human_idx = my_idx
	_online3d = true
	_vs_ai = false
	_awaiting_sync = false
	_net_match.sync_applied.connect(_on_online_sync_entry)
	_net_match.action_rejected.connect(_on_online_rejected)
	_net_match.emote_received.connect(func(id: String) -> void: _show_emote(1 - _view(), id))
	_net_match.opponent_disconnected.connect(_on_online_opponent_gone)
	if _net_match.mirror != null and _net_match.mirror.players.size() == 2:
		_begin_online_board()


func _on_online_sync_entry(events: Array) -> void:
	if _screen != Screen.MATCH or _gs == null:
		_begin_online_board()  # the guest's first sync carries the opening state
		return
	_on_online_sync(events)


func _begin_online_board() -> void:
	if _net_match == null or _net_match.mirror == null or _net_match.mirror.players.size() != 2:
		return
	_music("battle")
	_gs = _net_match.mirror
	_gs.take_events()
	_game_logged = true  # online matches aren't written to the local log
	_history = []
	_history_uid_cards = {}
	_history_column = null
	_turn_played_cards = []
	_ai_turn = _gs.active != _human_idx
	_clear()
	_refresh_match()


func _on_online_opponent_gone() -> void:
	if not _online3d:
		return
	_show_toast("Your opponent left the match.")
	await get_tree().create_timer(2.5).timeout
	_teardown_online()
	_show_title()


func _teardown_online() -> void:
	_online3d = false
	_awaiting_sync = false
	_ai_turn = false
	if _local_relay != null:
		_local_relay.stop()
		remove_child(_local_relay)
		_local_relay.queue_free()
		_local_relay = null
	if _online_match != null:
		remove_child(_online_match)
		_online_match.queue_free()
		_online_match = null
	if _net_match != null:
		_net_match.leave()
		remove_child(_net_match)
		_net_match.queue_free()
		_net_match = null
	_online = false
	_online_role = ""


func _cancel_online() -> void:
	_teardown_online()
	_show_title()


func _leave_online_match() -> void:
	_teardown_online()
	_show_title()


func _show_interstitial(_next_player: int, msg: String) -> void:
	_screen = Screen.INTERSTITIAL
	_clear()
	add_child(CardView.bg_rect(CardView.TITLE_BG))
	var v := VBoxContainer.new()
	_full_rect(v)
	v.add_spacer(true)
	v.add_child(CardView.label("PASS THE PHONE", 56, CardView.GOLD_TEXT))
	v.add_child(CardView.label(msg, 30))
	# Sprint 1a.2 (item 8): "what did they play?" recap — a row of mini
	# cards for every card the just-finished player played this turn, in
	# order. Tap a mini card to inspect it. View-only: collected from the
	# existing card_played events (no engine changes).
	if not _turn_played_cards.is_empty():
		var just_finished: int = 1 - _next_player
		v.add_child(CardView.label("Player %d played:" % (just_finished + 1), 24, CardView.GOLD_TEXT))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 170)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		for cid in _turn_played_cards:
			var rcard: Dictionary = CardDB.get_card(str(cid))
			if rcard.is_empty():
				continue
			var mini := CardView.make_card_button(rcard, 110, 140)
			mini.pressed.connect(_on_recap_mini_pressed.bind(str(cid)))
			row.add_child(mini)
		scroll.add_child(row)
		v.add_child(scroll)
	_turn_played_cards = []
	v.add_child(CardView.label("Hide your hand until you tap READY.", 24))
	var ready := CardView.button("READY", 40, 260, 90, CardView.BTN_READY, CardView.INK)
	ready.pressed.connect(_on_interstitial_ready.bind(_next_player))
	v.add_child(ready)
	v.add_spacer(true)
	add_child(v)


func _on_interstitial_ready(_player: int) -> void:
	_refresh_match()


func _on_recap_mini_pressed(card_id: String) -> void:
	_show_inspect(_inspect_data_for_card(CardDB.get_card(card_id)))


# Sprint 1a.2 (item 8): accumulate the card_ids from card_played events
# (main already drains take_events after each action).
func _accumulate_played(events: Array) -> void:
	for e in events:
		if str(e.get("type", "")) == "card_played":
			_turn_played_cards.append(str((e.get("data", {}) as Dictionary).get("card_id", "")))


# --- Sprint 1c: action history ---
# Records every card played (either player), every attack, and every
# Signature Move, newest first, capped at HistoryColumn.MAX_ENTRIES.
# Each entry carries a plain-English detail line built from the events
# that followed its cause. Called alongside _accumulate_played — main
# already drains take_events() after each action, so this only reads.
func _record_history(events: Array) -> void:
	if _gs == null:
		return
	# Pre-pass: map minion uids to card_ids for this batch (names for
	# the detail lines — the minions may be dead by the time we read).
	for e in events:
		var t0: String = str(e.get("type", ""))
		var d0: Dictionary = e.get("data", {})
		if t0 == "minion_summoned" or t0 == "minion_died":
			var cid0: String = str(d0.get("card_id", ""))
			if cid0 != "":
				_history_uid_cards[int(d0.get("uid", -1))] = cid0
	var pending: Dictionary = {}
	var evs: Array = []
	for e in events:
		var t: String = str(e.get("type", ""))
		var d: Dictionary = e.get("data", {})
		if t == "card_played" or t == "attack" or t == "signature_move":
			_finalize_history_entry(pending, evs)
			pending = _history_entry_for_cause(t, d)
			evs = []
		elif not pending.is_empty():
			evs.append(e)
	_finalize_history_entry(pending, evs)


func _history_entry_for_cause(t: String, d: Dictionary) -> Dictionary:
	var p: int = int(d.get("player", 0))
	if t == "card_played":
		var cid: String = str(d.get("card_id", ""))
		var card: Dictionary = CardDB.get_card(cid)
		return {"kind": "played", "player": p, "card_id": cid,
			"art_id": str(card.get("art", "token")),
			"name": str(card.get("name", cid))}
	if t == "attack":
		var auid: int = int(d.get("attacker_uid", -1))
		var acid: String = _history_uid_card(auid)
		var acard: Dictionary = CardDB.get_card(acid)
		return {"kind": "attack", "player": p, "card_id": acid,
			"attacker_uid": auid,
			"target_kind": str(d.get("target_kind", "")),
			"target_player": int(d.get("target_player", -1)),
			"target_uid": int(d.get("target_uid", -1)),
			"art_id": str(acard.get("art", "token")),
			"name": str(acard.get("name", "a Crew member"))}
	# signature_move
	var cls: String = str(d.get("class", ""))
	var hp: Dictionary = CardDB.hero_power_for(cls)
	return {"kind": "signature", "player": p, "card_id": "",
		"art_id": str(CardView.CLASS_ART.get(cls, "token")),
		"name": str(hp.get("name", "Signature Move"))}


func _finalize_history_entry(pending: Dictionary, evs: Array) -> void:
	if pending.is_empty():
		return
	pending["detail"] = _history_detail(pending, evs)
	_history.push_front(pending)
	while _history.size() > HistoryColumn.MAX_ENTRIES:
		_history.pop_back()


func _history_uid_card(uid: int) -> String:
	if _history_uid_cards.has(uid):
		return str(_history_uid_cards[uid])
	if _gs != null:
		for p in [0, 1]:
			var m: Dictionary = _gs.minion_by_uid(p, uid)
			if not m.is_empty():
				return str(m.get("card_id", ""))
	return ""


func _history_minion_name(uid: int) -> String:
	var cid: String = _history_uid_card(uid)
	if cid != "":
		var nm: String = str(CardDB.get_card(cid).get("name", ""))
		if nm != "":
			return nm
	return "a Crew member"


func _history_hero_name(p: int) -> String:
	if _gs == null or p < 0 or p > 1:
		return "the Boss"
	return "Player %d's %s" % [p + 1, CardDB.class_display_name(str(_gs.players[p].get("class", "")))]


func _history_target_name(d: Dictionary) -> String:
	if str(d.get("target_kind", "")) == "hero":
		return _history_hero_name(int(d.get("player", 0)))
	return _history_minion_name(int(d.get("uid", -1)))


# One plain-English clause for a single effect event. actor = the player
# who caused the action (for "took N damage" vs "dealt N to X").
func _history_clause(t: String, d: Dictionary, actor: int) -> String:
	match t:
		"damage":
			var amt: int = int(d.get("amount", 0))
			if int(d.get("player", -1)) == actor:
				return "took %d damage" % amt
			return "dealt %d to %s" % [amt, _history_target_name(d)]
		"heal":
			var amt2: int = int(d.get("amount", 0))
			if int(d.get("player", -1)) == actor:
				return "restored %d" % amt2
			return "restored %d to %s" % [amt2, _history_target_name(d)]
		"draw":
			return "drew a card"
		"card_burned":
			return "burned a card"
		"minion_destroyed":
			return "destroyed %s" % _history_minion_name(int(d.get("uid", -1)))
		"minion_died":
			return "%s died" % _history_minion_name(int(d.get("uid", -1)))
		"coin_flip":
			return "Heads" if bool(d.get("heads", false)) else "Tails"
		"minion_summoned":
			var snm: String = str(CardDB.get_card(str(d.get("card_id", ""))).get("name", ""))
			return "summoned %s" % snm if snm != "" else ""
		"buff":
			return "gave %s +%d/+%d" % [_history_minion_name(int(d.get("uid", -1))),
				int(d.get("attack_delta", 0)), int(d.get("health_delta", 0))]
		"minion_stolen":
			return "stole %s" % _history_minion_name(int(d.get("uid", -1)))
		"stats_swapped":
			return "swapped %s's stats" % _history_minion_name(int(d.get("uid", -1)))
		"hands_swapped":
			return "swapped hands"
		"entrance":
			return "Entrance"
		"final_bow":
			return "Final Bow"
	return ""


func _history_detail(pending: Dictionary, evs: Array) -> String:
	var kind: String = str(pending.get("kind", ""))
	var actor: int = int(pending.get("player", 0))
	if kind == "attack":
		return _attack_detail(pending, evs)
	var clauses: Array = []
	var destroyed: Array = []  # uids already reported via "destroyed X"
	for e in evs:
		var t: String = str(e.get("type", ""))
		var d: Dictionary = e.get("data", {})
		# Summoning the played minion itself is redundant with the card
		# name ("Angry Squirrel: summoned Angry Squirrel").
		if t == "minion_summoned" and str(d.get("card_id", "")) == str(pending.get("card_id", "")):
			continue
		# A destroy is always followed by the minion_died — reporting
		# both ("destroyed X, X died") is redundant.
		if t == "minion_destroyed":
			destroyed.append(int(d.get("uid", -1)))
		if t == "minion_died" and destroyed.has(int(d.get("uid", -1))):
			continue
		var cl: String = _history_clause(t, d, actor)
		if cl != "":
			clauses.append(cl)
	var head: String = str(pending.get("name", ""))
	if clauses.is_empty():
		return head
	return "%s: %s" % [head, ", ".join(clauses)]


func _attack_detail(pending: Dictionary, evs: Array) -> String:
	var auid: int = int(pending.get("attacker_uid", -1))
	var attacker_name: String = str(pending.get("name", "a Crew member"))
	var target_name: String = ""
	if str(pending.get("target_kind", "")) == "hero":
		target_name = _history_hero_name(int(pending.get("target_player", 0)))
	else:
		target_name = _history_minion_name(int(pending.get("target_uid", -1)))
	var dealt: int = 0
	var took: int = 0
	var extra: Array = []
	var deaths: Array = []
	for e in evs:
		var t: String = str(e.get("type", ""))
		var d: Dictionary = e.get("data", {})
		if t == "damage":
			var amt: int = int(d.get("amount", 0))
			var to_attacker: bool = str(d.get("target_kind", "")) == "minion" and int(d.get("uid", -2)) == auid
			var to_defender: bool = (not to_attacker) and (
				(str(d.get("target_kind", "")) == "hero" and int(d.get("player", -1)) == int(pending.get("target_player", -2))) or
				(str(d.get("target_kind", "")) == "minion" and int(d.get("uid", -2)) == int(pending.get("target_uid", -2))))
			if to_attacker:
				took += amt
			elif to_defender:
				dealt += amt
			else:
				extra.append("dealt %d to %s" % [amt, _history_target_name(d)])
		elif t == "minion_died":
			deaths.append("%s died" % _history_minion_name(int(d.get("uid", -1))))
		elif t == "entrance" or t == "final_bow":
			extra.append("Final Bow" if t == "final_bow" else "Entrance")
	var parts: Array = []
	if dealt > 0:
		parts.append("dealt %d" % dealt)
	if took > 0:
		parts.append("took %d" % took)
	parts.append_array(extra)
	var line: String = "%s attacked %s" % [attacker_name, target_name]
	if not parts.is_empty():
		line += ": " + ", ".join(parts)
	if not deaths.is_empty():
		line += ". " + ". ".join(deaths) + "."
	return line


func _on_history_entry_tapped(entry: Dictionary) -> void:
	if _animating or _ai_turn:
		return
	var data: Dictionary = {}
	match str(entry.get("kind", "")):
		"played", "attack":
			data = _inspect_data_for_card(CardDB.get_card(str(entry.get("card_id", ""))))
		"signature":
			data = _inspect_data_for_hero_power(int(entry.get("player", 0)))
	if data.is_empty():
		return
	data["detail_line"] = str(entry.get("detail", ""))
	_show_inspect(data)


# Resting on a history thumbnail: the card (or the Boss card for a
# Signature Move) pops up to its left with a line saying what happened.
var _history_pop: Control = null


func _on_history_hover(entry: Dictionary, rect: Rect2) -> void:
	if _history_pop != null and is_instance_valid(_history_pop):
		_history_pop.queue_free()
	_history_pop = null
	if entry.is_empty() or _gs == null:
		return
	var box := VBoxContainer.new()
	box.name = "HistoryPopup"
	box.z_index = 220
	box.add_theme_constant_override("separation", 6)
	var who: String = "You" if int(entry.get("player", 0)) == _view() else ("The computer" if _vs_ai else "Your opponent")
	var head := CardView.label(who, 18, Color(0.55, 0.78, 1.0) if who == "You" else Color(1.0, 0.55, 0.55))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var cw: float = 210.0
	if str(entry.get("kind", "")) == "signature":
		var data: Dictionary = _inspect_data_for_hero_power(int(entry.get("player", 0)))
		var pl := CardView.label("%s\n%s" % [str(data.get("name", "")), str(data.get("text", ""))], 17, CardView.GOLD_TEXT)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(cw, 0)
		box.add_child(pl)
	else:
		var card: Dictionary = CardDB.get_card(str(entry.get("card_id", "")))
		if not card.is_empty():
			box.add_child(CardView.make_card_button(card, int(cw), int(cw * CardFrame.ASPECT)))
	var det: String = str(entry.get("detail", ""))
	if det != "":
		var dl := CardView.label(det, 16, Color.WHITE)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(cw, 0)
		box.add_child(dl)
	var plate_sb: StyleBox = CardView.panel_style(Color(0.06, 0.04, 0.1, 0.9), 12)
	box.draw.connect(func() -> void: box.draw_style_box(plate_sb, Rect2(Vector2(-10, -8), box.size + Vector2(20, 16))))
	add_child(box)
	for n in box.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(cw, 0)
	box.reset_size()
	var h: float = box.get_combined_minimum_size().y
	box.position = Vector2(rect.position.x - cw - 26.0, clampf(rect.position.y - 20.0, 12.0, 720.0 - h - 12.0))
	_history_pop = box


func _build_history_column() -> void:
	var col := HistoryColumn.new()
	col.name = "HistoryColumn"
	col.setup(Callable(self, "_on_history_entry_tapped"), _view(), Callable(self, "_on_history_hover"))
	# The left edge belongs to the Boss cards now; history runs down the
	# right edge, above END TURN.
	col.position = Vector2(_canvas_width() - HistoryColumn.ENTRY_W - HistoryColumn.COL_X, HistoryColumn.COL_Y)
	add_child(col)
	col.set_entries(_history)
	_history_column = col


func _inspect_data_for_hero_power(player_idx: int) -> Dictionary:
	# Sprint 1c: inspect data for a Signature Move (history detail +
	# long-press on the Signature Move button). Cost comes from the
	# game rules, not the card data (HERO_POWERS has no cost key).
	if _gs == null:
		return {}
	var p: Dictionary = _gs.players[player_idx]
	var class_id: String = str(p.get("class", ""))
	var hp_info: Dictionary = CardDB.hero_power_for(class_id)
	if hp_info.is_empty():
		return {}
	return {
		"art_id": str(CardView.CLASS_ART.get(class_id, "token")),
		"name": str(hp_info.get("name", "")),
		"is_power": true,
		"cost": GameState.HERO_POWER_COST,
		"text": str(hp_info.get("text", "")),
	}


func _refresh_match() -> void:
	if _gs.winner != -1:
		_show_gameover()
		return
	_screen = Screen.MATCH
	_clear_overlay()
	_ensure_board_3d()
	var active: int = _view()
	var enemy: int = 1 - active
	var ap: Dictionary = _gs.players[active]
	var ep: Dictionary = _gs.players[enemy]
	# Sprint 1a.2: the hand fan centers on the ACTUAL canvas width, not
	# the 1280 constant (1600 on a 20:9 phone).
	var vw: float = _canvas_width()

	# 3D picking layer: full-screen, bottom-most overlay child. It is
	# transparent and sits under the controls, so any tap not consumed by
	# a 2D control (hand card, button) falls through to it and raycasts
	# the 3D table.
	_pick_layer = Control.new()
	_pick_layer.name = "BoardPickLayer"
	_pick_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_rect(_pick_layer)
	_pick_layer.gui_input.connect(_on_board_pick_gui_input)
	add_child(_pick_layer)

	# Sprint 1a.2: the two full-width purple info bars are GONE. Their
	# info lives on the 3D hero plaques (portrait, HP gem, player name,
	# enemy hand-size badge) and the mana rows beside the plaques. The
	# middle of the screen is fully transparent — the 3D table shows
	# through. From bottom to top: hand (bottom edge) -> my plaque ->
	# my row -> center line -> enemy row -> enemy plaque.

	# Sprint 1c: the top-left log line is gone (it ran over the light wood
	# rim and was unreadable). The action history column below replaces it.

	# Turn plaque, top-center: a gold-edged ribbon in the display font
	# (lit violet on your turn, dim steel on theirs).
	var turn_text: String = "YOUR TURN \u2014 PLAYER %d" % (active + 1)
	var my_turn: bool = true
	if _vs_ai:
		my_turn = _gs.active == _human_idx
		turn_text = "YOUR TURN" if my_turn else "COMPUTER'S TURN"
	elif _online3d:
		my_turn = _gs.active == _human_idx
		turn_text = "YOUR TURN" if my_turn else "OPPONENT'S TURN"
	var turn_pill := TurnBanner.new()
	turn_pill.name = "TurnPill"
	turn_pill.setup(turn_text, my_turn, 22)
	turn_pill.position = Vector2(vw / 2 - turn_pill.size.x / 2, 8)
	add_child(turn_pill)

	# Sprint 1c: action history column (replaces the unreadable top-left
	# log line). Left edge, between the two hero panels; newest on top,
	# max 8. Tap an entry -> detail panel (inspect dismiss rules).
	_build_history_column()

	# --- HAND ZONE (bottom): fan of cards, manual positions ---
	# Cards stay fully visible apart from a small bottom bleed.
	var hand_zone := Control.new()
	hand_zone.name = "HandZone"
	hand_zone.anchor_left = 0.0
	hand_zone.anchor_right = 1.0
	hand_zone.anchor_top = 1.0
	hand_zone.anchor_bottom = 1.0
	hand_zone.offset_left = 0
	hand_zone.offset_right = 0
	hand_zone.offset_top = -HAND_ZONE_H
	hand_zone.offset_bottom = 0
	hand_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fan: Array = CardView.fan_transforms(ap["hand"].size(), HAND_CARD_W, vw)
	for i in ap["hand"].size():
		var card: Dictionary = CardDB.get_card(ap["hand"][i])
		var cb := CardView.make_card_button(card, int(HAND_CARD_W), int(HAND_CARD_H))
		cb.name = "HandCard%d" % i
		cb.position = Vector2(fan[i]["x"], fan[i]["y"] - 10)
		cb.rotation = fan[i]["rot"]
		cb.z_index = i
		cb.set_meta("fan_home", cb.position)
		cb.set_meta("fan_rot", cb.rotation)
		cb.set_meta("fan_z", i)
		if not _gs.can_play(active, i):
			cb.modulate = Color(0.6, 0.6, 0.6)
		elif not _ai_turn and not _remote_turn():
			# Playable now: the card glows so it catches the eye.
			var face: CardFrame = cb.get_node_or_null("Face") as CardFrame
			if face != null:
				face.glow = true
		cb.gui_input.connect(_on_pressable_gui_input.bind({"kind": "hand_card", "hand_idx": i, "node": cb}))
		hand_zone.add_child(cb)
		_hand_cards.append(cb)
	add_child(hand_zone)
	_hand_zone = hand_zone

	# END TURN: a gold-framed plaque on the right edge at table mid-height
	# (EndTurnButton draws itself; it turns emerald when you're out of moves).
	var end_turn := EndTurnButton.new()
	end_turn.name = "EndTurnBtn"
	end_turn.position = Vector2(vw - 190, 300)
	var my_controls: bool = not _ai_turn and not _remote_turn()
	end_turn.set_look(EndTurnButton.Look.WAITING if not my_controls else (EndTurnButton.Look.DONE if not _has_moves(active) else EndTurnButton.Look.READY))
	end_turn.pressed.connect(_on_end_turn)
	add_child(end_turn)

	# Signature Move: a round gold medallion with the deck's emblem and a
	# cost jewel, below END TURN on the right edge (the Crew rows own the
	# center). SignatureButton draws itself.
	var hp_info: Dictionary = _gs.hero_power(active)
	var sig := SignatureButton.new()
	sig.name = "HeroPowerBtn"
	var sig_look: int = SignatureButton.Look.READY
	if ap["hero_power_used"]:
		sig_look = SignatureButton.Look.USED
	elif not _gs.can_use_hero_power(active) and str(hp_info.get("target", "none")) != "friendly_minion":
		sig_look = SignatureButton.Look.SHORT
	elif str(hp_info.get("target", "none")) == "friendly_minion" and _gs.hero_power_target_options(active).is_empty():
		sig_look = SignatureButton.Look.SHORT
	sig.setup(str(ap["class"]), CardView.class_color(str(ap["class"])), int(hp_info.get("cost", 2)), sig_look)
	sig.position = Vector2(vw - 190, 440)
	if sig_look == SignatureButton.Look.USED and _sig_was_ready_key == "%d|%d" % [active, _gs.turn_count]:
		sig.scale.x = 0.0
		sig.flip_to_used()  # it was just used: turn the medallion over
	_sig_was_ready_key = ("%d|%d" % [active, _gs.turn_count]) if sig_look != SignatureButton.Look.USED else ""
	# Sprint 1c: long-press opens inspect (name/cost/text); tap still
	# uses it. Same gesture rules as hand cards (moving off cancels).
	sig.gui_input.connect(_on_sig_gesture_input.bind(sig))
	add_child(sig)
	# The move's name on a small gold-edged ribbon under the medallion.
	var sig_pill := PanelContainer.new()
	sig_pill.name = "SigPill"
	var sig_pill_sb := StyleBoxFlat.new()
	sig_pill_sb.bg_color = Color(0.06, 0.03, 0.1, 0.92)
	sig_pill_sb.border_color = UIKit.GOLD_DEEP
	sig_pill_sb.set_border_width_all(2)
	sig_pill_sb.set_corner_radius_all(10)
	sig_pill_sb.shadow_color = Color(0, 0, 0, 0.45)
	sig_pill_sb.shadow_size = 4
	sig_pill_sb.shadow_offset = Vector2(0, 2)
	sig_pill_sb.content_margin_left = 12
	sig_pill_sb.content_margin_right = 12
	sig_pill_sb.content_margin_top = 3
	sig_pill_sb.content_margin_bottom = 4
	sig_pill.add_theme_stylebox_override("panel", sig_pill_sb)
	var sig_name := UIKit.label(str(hp_info.get("name", "")), 15, UIKit.GOLD, UIKit.FONT_BODY_PATH, 4)
	sig_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sig_pill.add_child(sig_name)
	add_child(sig_pill)
	sig_pill.position = Vector2(vw - 230, 542)
	sig_pill.resized.connect(func() -> void: sig_pill.position.x = vw - 140 - sig_pill.size.x * 0.5)

	# Pending-action hint.
	if not _pending.is_empty():
		var hint := CardView.label("Tap a target (or tap again to cancel).", 22)
		hint.position = Vector2(vw / 2 - 220, 64)
		add_child(hint)

	# Targeting arrow (2D, for hand-card drags) drawn above everything.
	_arrow = Line2D.new()
	_arrow.name = "TargetArrow"
	_arrow.width = 7
	_arrow.default_color = Color(1.0, 0.15, 0.15)
	_arrow.visible = false
	_arrow.z_index = 100
	add_child(_arrow)
	_arrowhead = Polygon2D.new()
	_arrowhead.name = "ArrowHead"
	_arrowhead.polygon = PackedVector2Array([Vector2(0, 0), Vector2(-16, -8), Vector2(-16, 8)])
	_arrowhead.color = Color(1.0, 0.15, 0.15)
	_arrowhead.visible = false
	_arrowhead.z_index = 101
	add_child(_arrowhead)
	# The Line2D / head above keep the arrow's logic (where it points,
	# snapped or not); TargetArrow draws it: the cyan hologram beam, the
	# lock-on ring and the outcome chips.
	_arrow.self_modulate.a = 0.0
	_arrowhead.self_modulate.a = 0.0
	_tarrow = TargetArrow.new()
	_tarrow.name = "TargetArrowFX"
	_tarrow.visible = false
	add_child(_tarrow)


	# Sync the 3D board to the state (adds/updates/removes minions by uid,
	# flips sides when the active player changed). Never rebuilds it.
	if _board_3d != null:
		_board_3d.sync(_gs)
		if not _match_warmed:
			_match_warmed = true
			_board_3d.preload_models(_match_model_ids())
			_board_3d.warmup_fx()


# Creates the 3D board (a Node3D child of this Control root — it renders
# in the main viewport behind the 2D overlay) and the animation
# director, once. Called by _refresh_match; the board persists across
# refreshes. Sprint 1b: no SubViewport — the board used to render into a
# 1280x720 SubViewport and get stretched to the screen, so the 3D was
# upscaled and soft on 1080p-1440p phones. Now it renders at native
# resolution; RENDER_SCALE_3D (Board3D) can drop it to ~0.8 if a phone
# struggles. The Board3D is added BEFORE the overlay children, so the
# 2D overlay draws on top of it.
func _ensure_board_3d() -> void:
	if _board_3d != null and is_instance_valid(_board_3d):
		return
	_board_3d = Board3D.new()
	_board_3d.name = "Board3D"
	_board_3d.view_player = _human_idx if (_vs_ai or _online3d) else -1
	add_child(_board_3d)
	# Sprint 1a.4: 2D minion stat badges (pinned to projected token
	# positions). Created once with the board; it reads the board's
	# minions every frame.
	if _stat_badges == null or not is_instance_valid(_stat_badges):
		_stat_badges = StatBadges.new()
		_stat_badges.name = "StatBadges"
		add_child(_stat_badges)
	_stat_badges.set_board(_board_3d)
	# Sprint 1a.5: the 2D hero badge panels (main owns them). Fixed
	# canvas positions, laid out with containers so nothing overlaps.
	# The 3D plaque follows its panel via unproject. Setup once per
	# board (once per match); set_side runs on every refresh.
	for p in [0, 1]:
		if _hero_badges[p] == null or not is_instance_valid(_hero_badges[p]):
			var hb := HeroBadge.new()
			hb.name = "HeroBadge%d" % p
			add_child(hb)
			_hero_badges[p] = hb
		var hb2: HeroBadge = _hero_badges[p]
		var cls: String = str(_gs.players[p]["class"])
		if hb2.class_id != cls:
			hb2.setup(p, cls)
		hb2.set_side(p == _view())
	_board_3d.hero_badges = _hero_badges
	if _turn_timer == null or not is_instance_valid(_turn_timer):
		_turn_timer = TurnTimer.new()
		_turn_timer.name = "TurnTimer"
		add_child(_turn_timer)
	if _anim_director == null or not is_instance_valid(_anim_director):
		_anim_director = AnimDirector.new()
		_anim_director.name = "AnimDirector"
		add_child(_anim_director)


# After a player action: take the event stream, play it (the director
# animates the batch), then fully sync the view. The state was already
# --- Actions: local play mutates the engine; online play asks the host ---

func _remote_turn() -> bool:
	return _gs != null and (_vs_ai or _online3d) and _gs.active != _human_idx


func _do_play(hand_idx: int, target: Dictionary) -> bool:
	if not _online3d:
		return _gs.play_card(_gs.active, hand_idx, target) if not target.is_empty() else _gs.play_card(_gs.active, hand_idx)
	if not _gs.can_play(_gs.active, hand_idx):
		return false
	return _submit_online({"act": "play_card", "hand_idx": hand_idx, "target": _wire_target(target)})


func _do_attack(board_idx: int, target: Dictionary) -> bool:
	if not _online3d:
		return _gs.attack(_gs.active, board_idx, target)
	if not _gs.can_attack(_gs.active, board_idx):
		return false
	var m: Dictionary = _gs.players[_gs.active]["board"][board_idx]
	return _submit_online({"act": "attack", "attacker_uid": int(m.get("uid", -1)), "target": _wire_target(target)})


func _do_hero_power(target: Dictionary) -> bool:
	if not _online3d:
		return _gs.use_hero_power(_gs.active, target) if not target.is_empty() else _gs.use_hero_power(_gs.active)
	if bool(_gs.players[_gs.active]["hero_power_used"]):
		return false
	return _submit_online({"act": "hero_power", "target": _wire_target(target)})


# Engine target (board index) -> wire target (minion uid / hero player).
func _wire_target(t: Dictionary) -> Dictionary:
	if t.is_empty():
		return {}
	if str(t.get("kind", "")) == "hero":
		return {"kind": "hero", "player": int(t.get("player", -1))}
	var p: int = int(t.get("player", -1))
	var bi: int = int(t.get("board_idx", -1))
	if p < 0 or bi < 0 or bi >= _gs.players[p]["board"].size():
		return {}
	return {"kind": "minion", "uid": int(_gs.players[p]["board"][bi].get("uid", -1))}


# Send a request to the host and lock input until its sync comes back.
func _submit_online(act: Dictionary) -> bool:
	if _net_match == null or _awaiting_sync:
		return false
	_dismiss_all_modals()
	_awaiting_sync = true
	_ai_turn = true
	_net_match.submit_action(act)
	return true


# A sync from the host (our action, the opponent's, or a forced end of
# turn): animate its events on the 3D board, then redraw.
func _on_online_sync(_events: Array) -> void:
	if not _online3d or _gs == null:
		return
	_awaiting_sync = false
	var events: Array = _gs.take_events()
	_accumulate_played(events)
	_record_history(events)
	_board_3d.preload_models(_ids_from_events(events))
	_animating = true
	_ai_turn = true
	if _anim_director != null and _board_3d != null:
		await _anim_director.play_events(events, _board_3d, _gs, Callable(self, "_whoosh_hands"), Callable(self, "_play_your_turn_banner"))
		_anim_director.ANIM_SPEED = 1.0
	_animating = false
	if _gs == null or not _online3d:
		return
	_ai_turn = _gs.active != _human_idx or _awaiting_sync
	if _gs.winner != -1:
		_show_gameover()
		return
	_refresh_match()


func _on_online_rejected(reason: String) -> void:
	_awaiting_sync = false
	if _gs != null:
		_ai_turn = _gs.active != _human_idx
	_show_toast(reason)
	_refresh_match()


func _ids_from_events(events: Array) -> Array:
	var ids: Array = []
	for e in events:
		var d: Dictionary = (e as Dictionary).get("data", {})
		var cid: String = str(d.get("card_id", ""))
		if cid != "":
			ids.append(cid)
	return ids


# mutated synchronously by the handler, so this is fire-and-forget: with
# no awaitable events the director returns synchronously and the
# refresh happens immediately. The director's speed-up (tap during
# animations) resets to 1x after each batch.
func _after_action() -> void:
	if _gs == null:
		return
	if _online3d:
		return  # the host's sync brings the events (_on_online_sync)
	_dismiss_all_modals()  # Sprint 1a.3: a new action closes every modal.
	if _board_3d == null or _anim_director == null:
		_refresh_match()
		return
	var events: Array = _gs.take_events()
	_accumulate_played(events)
	_record_history(events)
	_animating = true
	await _anim_director.play_events(events, _board_3d, _gs, Callable(self, "_whoosh_hands"), Callable(self, "_play_your_turn_banner"))
	_anim_director.ANIM_SPEED = 1.0
	_animating = false
	_refresh_match()


# End turn: same, but the interstitial shows after the animation.
func _after_end_turn() -> void:
	if _gs == null:
		return
	_dismiss_all_modals()  # Sprint 1a.3: a new action closes every modal.
	var events: Array = _gs.take_events()
	_accumulate_played(events)
	_record_history(events)
	_animating = true
	if _anim_director != null and _board_3d != null:
		await _anim_director.play_events(events, _board_3d, _gs, Callable(self, "_whoosh_hands"), Callable(self, "_play_your_turn_banner"))
		_anim_director.ANIM_SPEED = 1.0
	_animating = false
	if _gs.winner != -1:
		_show_gameover()
		return
	if _vs_ai:
		_turn_played_cards = []
		_refresh_match()
		_maybe_run_ai()
		return
	_show_interstitial(_gs.active, "Player %d's turn! Pass the phone to Player %d." % [_gs.active + 1, _gs.active + 1])


# The director's 2D bits (main owns the 2D overlay): the "YOUR TURN"
# banner sweeps in from the left and out to the right (~0.9s, the
# director's BANNER_TIME const). The interstitial follows after the
# batch, so this banner is the in-match turn signal.
func _play_your_turn_banner() -> void:
	var banner_text: String = "YOUR TURN"
	if _vs_ai and _gs != null and _gs.active != _human_idx:
		banner_text = "COMPUTER'S TURN"
	elif _online3d and _gs != null and _gs.active != _human_idx:
		banner_text = "OPPONENT'S TURN"
	var banner := TurnBanner.new()
	banner.name = "YourTurnBanner"
	banner.setup(banner_text, banner_text == "YOUR TURN", 54)
	var vw2: float = _canvas_width()
	var mid_x: float = vw2 * 0.5 - banner.size.x * 0.5
	banner.position = Vector2(-banner.size.x - 40.0, 300)
	banner.z_index = 150
	add_child(banner)
	var dur: float = AnimDirector.BANNER_TIME
	var tw := create_tween()
	tw.tween_property(banner, "position:x", mid_x, dur * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(banner, "position:x", mid_x + 12.0, dur * 0.3)
	tw.tween_property(banner, "position:x", vw2 + 40.0, dur * 0.35).set_ease(Tween.EASE_IN)
	await tw.finished
	banner.queue_free()


# The director's 2D bits: swapped hands whoosh across (the pre-swap
# hand cards slide off-screen; the refresh then shows the new hand).
func _whoosh_hands() -> void:
	var dur: float = AnimDirector.HANDS_WHOOSH_TIME
	var tweens: Array = []
	for cb in _hand_cards:
		var tw := create_tween()
		tw.tween_property(cb, "position:x", cb.position.x - 1400.0, dur).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(cb, "modulate:a", 0.0, dur)
		tweens.append(tw)
	for tw in tweens:
		await tw.finished


# Convert a 3D pick (uid-based) into the board_idx ctx the rest of the
# input code uses. The pick itself is uid-based; the engine API takes
# board_idx, resolved here via minion_index_by_uid — never by arithmetic.
func _ctx_for_pick(hit: Dictionary) -> Dictionary:
	if hit.is_empty() or _gs == null:
		return {}
	if hit.get("kind", "") == "minion":
		var p: int = int(hit.get("player", 0))
		var uid: int = int(hit.get("uid", -1))
		var bi: int = _gs.minion_index_by_uid(p, uid)
		if bi < 0:
			return {}
		if p == _view():
			return {"kind": "my_minion", "board_idx": bi, "uid": uid}
		return {"kind": "target", "target": {"kind": "minion", "player": p, "board_idx": bi}, "uid": uid}
	if hit.get("kind", "") == "hero":
		var hp_p: int = int(hit.get("player", 0))
		if hp_p == _view():
			# Sprint 1a.2: tapping your own hero opens the emote menu;
			# long-press inspects it.
			return {"kind": "my_hero", "player": hp_p}
		return {"kind": "target", "target": {"kind": "hero", "player": hp_p, "board_idx": -1}}
	return {}


# Input on the 3D table (via the pick layer): raycast the camera, then
# run the same press / drag / tap state machine as the 2D controls.
# While animations play, a tap here is the 3x speed-up (not a press).
func _on_board_pick_gui_input(event: InputEvent) -> void:
	# Mouse wheel: zoom in toward the cursor / back out; middle-click resets.
	if event is InputEventMouseButton and event.pressed and _board_3d != null:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_board_3d.zoom_step(1, _to_viewport_pos(mb.position))
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_board_3d.zoom_step(-1, _to_viewport_pos(mb.position))
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_board_3d.reset_zoom()
			return
	if _animating or _ai_turn:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			if _anim_director != null:
				_anim_director.boost_speed()
		return
	if _gs == null or _board_3d == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var hit: Dictionary = _board_3d.pick(_to_viewport_pos(event.position))
			var ctx: Dictionary = _ctx_for_pick(hit)
			if ctx.is_empty():
				return
			_press = {"ctx": ctx, "t": Time.get_ticks_msec(), "down": true, "start_pos": event.position, "dragging": false, "magnified": false, "node": null}
		else:
			_on_press_release(event.position)
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			var hit2: Dictionary = _board_3d.pick(_to_viewport_pos(event.position))
			var ctx2: Dictionary = _ctx_for_pick(hit2)
			if ctx2.is_empty():
				return
			_press = {"ctx": ctx2, "t": Time.get_ticks_msec(), "down": true, "start_pos": event.position, "dragging": false, "magnified": false, "node": null}
		else:
			_on_press_release(event.position)
	elif event is InputEventScreenDrag:
		_on_drag_move(event.position)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_on_drag_move(event.position)


# Map a canvas point (a Control's local coords, 1280x720 logical space)
# into MAIN-VIEWPORT coords for the 3D camera's raycasts. The canvas is
# stretched to the window (stretch mode canvas_items), so canvas coords
# are NOT window coords on phones — the viewport's canvas transform
# converts them. Headless / 1280x720 window: the identity.
func _to_viewport_pos(pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * pos


# --- Unified press / drag / tap input ---

func _global_pos(event: InputEvent, node: Control) -> Vector2:
	return node.global_position + event.position


func _on_pressable_gui_input(event: InputEvent, ctx: Dictionary) -> void:
	# While animations play, a tap here is the 3x speed-up (not a press).
	if _animating or _ai_turn:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			if _anim_director != null:
				_anim_director.boost_speed()
		return
	var node: Control = ctx.get("node")
	if str(ctx.get("kind", "")) == "hand_card":
		_on_hand_gesture_input(event, ctx, node)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press = {"ctx": ctx, "t": Time.get_ticks_msec(), "down": true, "start_pos": _global_pos(event, node), "dragging": false, "magnified": false, "node": node}
		else:
			_on_press_release(_global_pos(event, node))
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press = {"ctx": ctx, "t": Time.get_ticks_msec(), "down": true, "start_pos": _global_pos(event, node), "dragging": false, "magnified": false, "node": node}
		else:
			_on_press_release(_global_pos(event, node))
	elif event is InputEventScreenDrag:
		_on_drag_move(_global_pos(event, node))
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_on_drag_move(_global_pos(event, node))



# --- Sprint 1a.3: hand-card gesture layer (replaces tap-to-play) ---
# ONE gesture state machine (press / move / release + hold timing) so
# mouse input maps onto it later. A tap NEVER plays a card.
#   touch down: the card lifts and scales up slightly
#   hold still >= 0.35s: a large preview shows above the hand ONLY while
#     the finger stays down (release closes it, nothing is played)
#   drag: the preview hides and the card follows the finger
#   release above the play line (untargeted card): play, or snap back
#     with "Not enough mana" when mana is short
#   release below the line: cancel, the card glides back
#   card needing a target: crossing the line shrinks it to an icon beside
#     my hero with an arrow to the finger; release on a valid target
#     plays, anywhere else cancels and the card returns to the hand.
func _gesture_family(event: InputEvent) -> String:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return "touch"
	return "mouse"


func _play_line_y() -> float:
	# The play line sits just above the hand zone.
	if _hand_zone != null:
		return _hand_zone.global_position.y - 8.0
	return VIEW_H - HAND_ZONE_H - 8.0


func _on_hand_gesture_input(event: InputEvent, ctx: Dictionary, node: Control) -> void:
	# While animations play, a tap here is the 3x speed-up (not a press).
	if _animating or _ai_turn:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			if _anim_director != null:
				_anim_director.boost_speed()
		return
	var fam: String = _gesture_family(event)
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			if not _press.is_empty():
				return  # one gesture at a time (also one input family)
			_press = {"ctx": ctx, "t": Time.get_ticks_msec(), "down": true,
				"family": fam, "start_pos": _global_pos(event, node),
				"dragging": false, "preview": false, "node": node,
				"home_pos": node.position, "home_z": node.z_index,
				"grab_offset": Vector2.ZERO}
			# Touch down: the card lifts and scales up slightly.
			node.z_index = 50
			node.pivot_offset = node.size / 2.0
			node.scale = Vector2(1.06, 1.06)
		else:
			if _press.is_empty() or str(_press.get("family", "")) != fam:
				return
			_on_gesture_release(_global_pos(event, node))
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		if _press.is_empty() or str(_press.get("family", "")) != fam:
			return
		_on_gesture_move(_global_pos(event, node))


func _on_gesture_move(pos: Vector2) -> void:
	if _press.is_empty() or not _press.get("down", false):
		return
	if pos.distance_to(_press["start_pos"]) <= DRAG_THRESHOLD:
		return
	if _press.get("preview", false):
		_hide_hand_preview()
		_press["preview"] = false
	if not _press.get("dragging", false):
		_press["dragging"] = true
		var node: Control = _press["node"]
		_press["grab_offset"] = _press["start_pos"] - (_press["home_pos"] + node.size / 2.0)
	_begin_drag(_press["ctx"], pos)
	_update_drag(pos)


func _on_gesture_release(pos: Vector2) -> void:
	if _press.is_empty():
		return
	var node: Control = _press.get("node")
	var was_dragging: bool = _press.get("dragging", false)
	var home_pos: Vector2 = _press.get("home_pos", node.position if node != null else Vector2.ZERO)
	var home_z: int = int(_press.get("home_z", 0))
	_press = {}
	_hide_hand_preview()
	if not was_dragging:
		# Tap, or preview-only release: restore the card, NEVER play.
		_restore_hand_card(node, home_pos, home_z)
		return
	# Drag release: _end_drag evaluates the drop (home slot is in _drag).
	_end_drag(pos)


# Return a hand card to its fan slot (position, scale, z).
func _restore_hand_card(node: Control, home_pos: Vector2, home_z: int) -> void:
	if node == null:
		return
	node.position = home_pos
	node.scale = Vector2.ONE
	node.z_index = home_z
	node.visible = true


# Cancel: the card glides back to the hand.
func _glide_card_home(node: Control, home_pos: Vector2, home_z: int) -> void:
	if node == null:
		return
	# Sprint 1a.5: a card hidden while the arrow was out reappears the
	# moment the drag cancels.
	node.visible = true
	var tw := node.create_tween()
	tw.tween_property(node, "position", home_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.18)
	tw.tween_callback(_restore_hand_card.bind(node, home_pos, home_z))


# Large preview above the hand, shown ONLY while the finger stays down.
func _show_hand_preview(ctx: Dictionary, anchor_x: float = -1.0) -> void:
	_hide_hand_preview()
	var card: Dictionary = _press_card(ctx)
	if card.is_empty() or _hand_zone == null:
		return
	var vw: float = _canvas_width()
	var big := CardView.make_card_button(card, 300, 420, true)
	big.name = "HandPreview"
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hand_top: float = _hand_zone.global_position.y
	# Hotfix 1c.2: keyword definitions below the preview (Alex: keywords
	# were only defined on the battlefield inspect panel). The box is a
	# child of the card so it is freed with it; shift the card up to
	# make room.
	var kw_box: VBoxContainer = _keyword_help_box(card, 16, 300.0)
	var kw_h: float = 0.0
	if kw_box != null:
		kw_h = _inspect_keywords(card).size() * 24.0
		kw_box.position = Vector2(0, 424.0)
		big.add_child(kw_box)
	var px: float = (vw - 300.0) / 2.0 if anchor_x < 0.0 else clampf(anchor_x - 150.0, 170.0, vw - 300.0 - 210.0)
	big.position = Vector2(px, maxf(8.0, hand_top - 432.0 - kw_h - (40.0 if anchor_x >= 0.0 else 0.0)))
	for n in big.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.z_index = 200
	add_child(big)
	_hand_preview = big


func _hide_hand_preview() -> void:
	if _hand_preview != null and is_instance_valid(_hand_preview):
		_hand_preview.queue_free()
	_hand_preview = null


func _show_toast(text: String) -> void:
	if _toast_label == null:
		_toast_label = CardView.label("", 26, Color.WHITE)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_label.z_index = 400
		add_child(_toast_label)
	var vw: float = _canvas_width()
	_toast_label.text = text
	_toast_label.position = Vector2(vw / 2.0 - 250.0, 300.0)
	_toast_label.size = Vector2(500, 44)
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_hide_toast)


func _hide_toast() -> void:
	if _toast_label != null:
		_toast_label.visible = false


# Sprint 1a.4: unified 2D targeting arrow (hand cards AND minion
# attacks use the same arrow). While a card is held inside the hand zone
# there is no arrow (preview only). Once the finger crosses the top of
# the hand zone with a card that needs a target, the arrow appears from
# the card's exit point at the hand edge to the finger, curving up over
# the table. GREY while not over a valid target; RED + target highlight
# when over one. Snap: within ~60px (screen space) of a valid target the
# arrowhead snaps onto it and turns red. Release on red → play; anywhere
# else → cancel. The origin is pure 2D (never a 3D projection, never
# Vector2.ZERO) — this kills the 1a.3 arrow-origin bug.
const ARROW_SNAP_PX: float = 60.0
# Sprint 1c: the arrow only appears once the finger is this far above
# the hand-zone line (hand cards) or from the drag origin (attacks).
# Below that the card stays visible under the finger as normal, and the
# curve scales with arrow length so short arrows don't hook or loop.
const ARROW_APPEAR_PX: float = 40.0
const ARROW_CURVE_LIFT: float = 120.0
const ARROW_POINTS: int = 16


func _target_screen_pos(t: Dictionary) -> Vector2:
	# Canvas-space screen position of a target (for snap + arrowhead).
	if _board_3d == null or _gs == null:
		return Vector2(-9999, -9999)
	var world: Vector3 = Vector3.ZERO
	var found: bool = false
	if t.get("kind", "") == "minion":
		var p: int = int(t.get("player", 0))
		var bi: int = int(t.get("board_idx", -1))
		var board: Array = _gs.players[p]["board"]
		if bi >= 0 and bi < board.size():
			var uid: int = _gs.uid_for(board[bi])
			var res: Dictionary = _board_3d.minion_position(uid)
			if bool(res.get("found", false)):
				world = res["position"] + _board_3d.aim_lift_minion(uid)
				found = true
	elif t.get("kind", "") == "hero":
		var res2: Dictionary = _board_3d.hero_position(int(t.get("player", 0)), _view())
		if bool(res2.get("found", false)):
			world = res2["position"] + _board_3d.aim_lift_hero(int(t.get("player", 0)))
			found = true
	if not found:
		return Vector2(-9999, -9999)
	var vp: Vector2 = _board_3d.screen_pos(world)
	return get_viewport().get_canvas_transform().affine_inverse() * vp


func _snap_target(finger: Vector2) -> Dictionary:
	# The nearest valid drag target within ARROW_SNAP_PX of the finger
	# (screen space), or {}.
	var best: Dictionary = {}
	var best_d: float = ARROW_SNAP_PX
	# The finger over a 3D model (Crew or Boss) snaps to it.
	var over: Dictionary = {}
	if _board_3d != null:
		over = _board_3d.pick(get_viewport().get_canvas_transform() * finger)
	for t in _drag.get("targets", []):
		var sp: Vector2 = _target_screen_pos(t)
		var d: float = finger.distance_to(sp)
		if not over.is_empty() and str(over.get("kind", "")) == str(t.get("kind", "")) and int(over.get("player", -1)) == int(t.get("player", -2)):
			if str(t.get("kind", "")) == "hero":
				d = 0.0
			elif _gs != null:
				var tb: Array = _gs.players[int(t.get("player", 0))]["board"]
				var tbi: int = int(t.get("board_idx", -1))
				if tbi >= 0 and tbi < tb.size() and _gs.uid_for(tb[tbi]) == int(over.get("uid", -1)):
					d = 0.0
		# A Boss can also be targeted on its 2D panel.
		if str(t.get("kind", "")) == "hero":
			var hp_i: int = int(t.get("player", 0))
			if hp_i >= 0 and hp_i < _hero_badges.size() and _hero_badges[hp_i] != null and is_instance_valid(_hero_badges[hp_i]):
				if (_hero_badges[hp_i] as Control).get_global_rect().has_point(finger):
					d = 0.0
		if d < best_d:
			best_d = d
			best = t
	return best


func _update_target_arrow(origin: Vector2, finger: Vector2) -> void:
	# Snap to the nearest valid target within ARROW_SNAP_PX.
	var best: Dictionary = _snap_target(finger)
	_drag["snapped"] = best
	_clear_highlights()
	var end: Vector2 = finger
	var red: bool = false
	if not best.is_empty():
		end = _target_screen_pos(best)
		red = true
		_highlight_targets([best])
	_draw_curved_arrow(origin, end, red)
	_update_arrow_fx(origin, end, best, finger)


# What kind of action the arrow is for (sets the ring's center mark).
func _arrow_kind() -> String:
	var ctx: Dictionary = _drag.get("ctx", {})
	match str(ctx.get("kind", "")):
		"my_minion":
			return "attack"
		"hand_card":
			var c: Dictionary = _press_card(ctx)
			var eff: String = str(c.get("effect", ""))
			return "heal" if eff.begins_with("heal") else ("attack" if str(c.get("type", "")) == "minion" else "trick")
	return "trick"


# The damage this action deals to a target, or -1 when it isn't damage.
func _arrow_damage() -> int:
	var ctx: Dictionary = _drag.get("ctx", {})
	if _gs == null:
		return -1
	match str(ctx.get("kind", "")):
		"my_minion":
			var b: Array = _gs.players[_gs.active]["board"]
			var bi: int = int(ctx.get("board_idx", -1))
			return int(b[bi]["attack"]) if bi >= 0 and bi < b.size() else -1
		"hand_card":
			var c: Dictionary = _press_card(ctx)
			if str(c.get("effect", "")) == "damage":
				return int(c.get("effect_value", 0))
	return -1


# Draw the beam: locked on a valid target with outcome chips, aiming at
# nothing, or blocked (a Bouncer is in the way) with the reason.
func _update_arrow_fx(origin: Vector2, end: Vector2, best: Dictionary, finger: Vector2) -> void:
	if _tarrow == null:
		return
	_tarrow.visible = true
	_tarrow.previews = []
	_tarrow.reason = ""
	var kind: String = _arrow_kind()
	if not best.is_empty():
		var dmg: int = _arrow_damage()
		if dmg > 0:
			_tarrow.previews = _outcome_chips(best, dmg, end, origin)
		_tarrow.aim(origin, end, TargetArrow.State.LOCKED, kind)
		return
	# Over an enemy that can't be picked while a Bouncer stands guard?
	if kind == "attack" and _gs != null:
		var foe: int = 1 - _gs.active
		var guarded: bool = false
		for m in _gs.players[foe]["board"]:
			if bool(m.get("taunt", false)):
				guarded = true
		if guarded:
			var spots: Array = [{"kind": "hero", "player": foe, "board_idx": -1}]
			for i in _gs.players[foe]["board"].size():
				spots.append({"kind": "minion", "player": foe, "board_idx": i})
			for t in spots:
				var sp: Vector2 = _target_screen_pos(t)
				if sp.distance_to(finger) < 46.0:
					_tarrow.reason = "A Bouncer is in the way"
					_tarrow.aim(origin, sp, TargetArrow.State.BLOCKED, kind)
					return
	_tarrow.aim(origin, finger, TargetArrow.State.AIMING, kind)


# "-3" over what takes damage; a skull when it would die. An attack also
# shows what hits back.
func _outcome_chips(t: Dictionary, dmg: int, tpos: Vector2, apos: Vector2) -> Array:
	var out: Array = []
	var p: int = int(t.get("player", 0))
	var hp: int = 0
	var counter: int = 0
	if str(t.get("kind", "")) == "hero":
		hp = int(_gs.players[p]["hp"])
	else:
		var b: Array = _gs.players[p]["board"]
		var bi: int = int(t.get("board_idx", -1))
		if bi < 0 or bi >= b.size():
			return out
		hp = int(b[bi]["health"])
		counter = int(b[bi]["attack"])
	out.append({"pos": tpos + Vector2(0, -40), "text": "-%d" % dmg, "lethal": dmg >= hp})
	var ctx: Dictionary = _drag.get("ctx", {})
	if str(ctx.get("kind", "")) == "my_minion" and counter > 0:
		var mb: Array = _gs.players[_gs.active]["board"]
		var mi: int = int(ctx.get("board_idx", -1))
		if mi >= 0 and mi < mb.size():
			out.append({"pos": apos + Vector2(0, -42), "text": "-%d" % counter, "lethal": counter >= int(mb[mi]["health"])})
	return out


func _draw_curved_arrow(from: Vector2, to: Vector2, red: bool) -> void:
	if _arrow == null or _arrowhead == null:
		return
	var col: Color = Color(1.0, 0.15, 0.15) if red else Color(0.55, 0.55, 0.6)
	_arrow.default_color = col
	_arrowhead.color = col
	# Sprint 1c: the curve scales with arrow length — a fixed lift makes
	# short arrows hook/loop. Below ~40px the arrow isn't shown at all.
	var dist: float = from.distance_to(to)
	var lift: float = minf(ARROW_CURVE_LIFT, dist * 0.4)
	var mid: Vector2 = (from + to) * 0.5 + Vector2(0, -lift)
	var pts := PackedVector2Array()
	for i in ARROW_POINTS + 1:
		var t: float = float(i) / float(ARROW_POINTS)
		var a: float = (1.0 - t) * (1.0 - t)
		var b: float = 2.0 * (1.0 - t) * t
		var c: float = t * t
		pts.append(from * a + mid * b + to * c)
	_arrow.points = pts
	_arrow.visible = true
	_arrowhead.position = to
	# Aim the head along the curve's end tangent.
	var prev: Vector2 = pts[ARROW_POINTS - 1] if pts.size() > 1 else from
	if to.distance_to(prev) > 1.0:
		_arrowhead.rotation = atan2(to.y - prev.y, to.x - prev.x)
	_arrowhead.visible = true


func _on_press_release(pos: Vector2) -> void:
	if _press.is_empty():
		return
	var was_dragging: bool = _press.get("dragging", false)
	var was_mag: bool = _press.get("magnified", false)
	var ctx: Dictionary = _press.get("ctx", {})
	_press = {}
	if was_mag:
		return  # magnify overlay handles its own dismiss
	if was_dragging:
		_end_drag(pos)
	else:
		_do_tap(ctx)


func _on_drag_move(pos: Vector2) -> void:
	if _press.is_empty() or not _press.get("down", false) or _press.get("magnified", false):
		return
	if not _press.get("dragging", false):
		if pos.distance_to(_press["start_pos"]) > DRAG_THRESHOLD:
			_press["dragging"] = true
			_begin_drag(_press["ctx"], _press["start_pos"])
	if _press.get("dragging", false):
		_update_drag(pos)


func _begin_drag(ctx: Dictionary, start_pos: Vector2) -> void:
	var node: Control = ctx.get("node")
	# Home slot for restore/glide-back. The gesture press already stored
	# the pre-lift values in _press; the direct-call path (tests) reads
	# the node's current state.
	var home_pos: Vector2 = node.position if node != null else Vector2.ZERO
	var home_z: int = node.z_index if node != null else 0
	if not _press.is_empty() and _press.get("node") == node:
		home_pos = _press.get("home_pos", home_pos)
		home_z = int(_press.get("home_z", home_z))
	if node != null:
		node.z_index = 50
		node.pivot_offset = node.size / 2.0
		node.scale = Vector2(1.06, 1.06)
	var grab: Vector2 = _press.get("grab_offset", Vector2.ZERO) if not _press.is_empty() else Vector2.ZERO
	# Sprint 1a.4: the unified 2D arrow needs no 3D origin and no
	# Vector2.ZERO fallback — press_start is the on-screen fallback.
	_drag = {"ctx": ctx, "targets": [], "snapped": {}, "home_pos": home_pos, "home_z": home_z, "grab_offset": grab, "press_start": start_pos, "arrow_on": false}
	match ctx.get("kind", ""):
		"hand_card":
			# Targets are listed now; the arrow appears when the card
			# crosses the top of the hand zone.
			var card: Dictionary = _press_card(ctx)
			if _card_needs_target(card):
				_drag["targets"] = _gs.card_target_options(_gs.active, card)
		"my_minion":
			_drag["targets"] = _gs.valid_attack_targets(_gs.active)


func _update_drag(pos: Vector2) -> void:
	if _drag.is_empty():
		return
	if str(_drag.get("ctx", {}).get("kind", "")) == "hand_card":
		_update_hand_drag(pos)
		return
	# Minion attack: the unified 2D arrow, from the minion's screen
	# position to the finger. Origin fallback is the press-down point
	# (always on-screen) — never Vector2.ZERO.
	var ctx: Dictionary = _drag["ctx"]
	var origin: Vector2 = _drag.get("press_start", pos)
	if _board_3d != null:
		var auid: int = int(ctx.get("uid", -1))
		var res: Dictionary = _board_3d.minion_position(auid)
		if bool(res.get("found", false)):
			var vp: Vector2 = _board_3d.screen_pos(res["position"])
			origin = get_viewport().get_canvas_transform().affine_inverse() * vp
	# Sprint 1c: no arrow until the finger is 40px from the origin — a
	# shorter arrow hooks/loops at the hand edge.
	if origin.distance_to(pos) < ARROW_APPEAR_PX:
		_hide_arrow()
		_clear_highlights()
		_drag["snapped"] = {}
		return
	_update_target_arrow(origin, pos)


# Sprint 1a.4: the dragged hand card follows the finger. A targeted card
# crossing the top of the hand zone shows the unified arrow (from the
# card's exit point at the hand edge to the finger); dragging back below
# the line hides it. No icon mode anymore.
func _update_hand_drag(pos: Vector2) -> void:
	var node: Control = _drag["ctx"].get("node")
	if node == null:
		return
	var card: Dictionary = _press_card(_drag["ctx"])
	var targeted: bool = _card_needs_target(card)
	var line_y: float = _play_line_y()
	node.position = pos - _drag.get("grab_offset", Vector2.ZERO) - node.size / 2.0
	# Sprint 1c: the arrow needs 40px of clearance above the hand-zone
	# line — below that the card stays visible under the finger.
	if targeted and pos.y < line_y - ARROW_APPEAR_PX:
		if not _drag.get("arrow_on", false):
			# Sprint 1a.5: the card hides so it can't block the board
			# while the arrow is out; it reappears if the finger comes
			# back into the hand zone.
			node.visible = false
			# A minion with a targeted Entrance gets a faint ghost
			# token at the slot where it will land.
			if str(card.get("type", "")) == "minion" and _board_3d != null and _gs != null:
				var bc: int = int(_gs.players[_gs.active]["board"].size())
				if bc < 7:
					var gp: Vector3 = _board_3d.slot_position(_gs.active, bc, bc + 1, _view())
					_board_3d.show_ghost_at(gp)
		_drag["arrow_on"] = true
		var origin: Vector2 = Vector2(node.position.x + node.size.x * 0.5, line_y)
		_update_target_arrow(origin, pos)
	elif _drag.get("arrow_on", false):
		_drag["arrow_on"] = false
		node.visible = true
		if _board_3d != null:
			_board_3d.hide_ghost()
		_drag["snapped"] = {}
		_hide_arrow()
		_clear_highlights()


func _end_drag(pos: Vector2) -> void:
	if _drag.is_empty():
		return
	var ctx: Dictionary = _drag["ctx"]
	var node: Control = ctx.get("node")
	var drag_kind: String = str(ctx.get("kind", ""))
	# Sprint 1a.5: the ghost token (if any) is done the moment the drag
	# ends, on every path.
	if _board_3d != null:
		_board_3d.hide_ghost()
	# Re-snap at the release point (the finger may have moved since the
	# last move event). Release on a valid (red) target → play; anywhere
	# else → cancel. For a targeted card the arrow (and snap) only exist
	# above the play line.
	var snapped: Dictionary = {}
	if drag_kind == "hand_card":
		var ec: Dictionary = _press_card(ctx)
		# Sprint 1c: no arrow below the 40px threshold -> no snap
		# (release in the hand zone = cancel, as now).
		if _card_needs_target(ec) and _drag.get("arrow_on", false) and pos.y < _play_line_y() - ARROW_APPEAR_PX:
			snapped = _snap_target(pos)
	elif drag_kind == "my_minion":
		snapped = _snap_target(pos)
	_hide_arrow()
	_clear_highlights()
	if _board_zone != null:
		_board_zone.modulate = Color.WHITE
	var home_pos: Vector2 = _drag.get("home_pos", node.position if node != null else Vector2.ZERO)
	var home_z: int = int(_drag.get("home_z", 0))
	_drag = {}
	if drag_kind != "hand_card" and node != null:
		node.scale = Vector2.ONE
		node.z_index = 0
	match drag_kind:
		"hand_card":
			# The drop decides. Cancel = glide back to the hand (no
			# state changed, no refresh needed). Play = the refresh
			# inside _after_action rebuilds the hand.
			var hand_idx: int = int(ctx.get("hand_idx", -1))
			var card: Dictionary = _press_card(ctx)
			if _card_needs_target(card):
				# Release on a valid (red/snapped) target → play;
				# anywhere else → cancel.
				if not snapped.is_empty() and _do_play(hand_idx, snapped):
					_after_action()
					return
				_glide_card_home(node, home_pos, home_z)
			else:
				# Untargeted: release above the play line = play.
				# Minions always go to the right end: the engine has no
				# insertion-position support (_summon appends), so there is
				# no "drop between minions" position to honor.
				if pos.y < _play_line_y():
					if int(_gs.players[_gs.active]["mana"]) < int(card.get("cost", 0)):
						_show_toast("Not enough mana")
						_glide_card_home(node, home_pos, home_z)
						return
					if _do_play(hand_idx, {}):
						_after_action()
						return
				_glide_card_home(node, home_pos, home_z)
		"my_minion":
			var board_idx: int = int(ctx.get("board_idx", -1))
			if not snapped.is_empty():
				if _do_attack(board_idx, snapped):
					_after_action()
					return
			_refresh_match()



func _highlight_targets(targets: Array) -> void:
	for t in targets:
		var key: String = "hero_%d" % t["player"] if t["kind"] == "hero" else "minion_%d_%d" % [t["player"], t["board_idx"]]
		if _target_nodes.has(key):
			CardView.set_highlight(_target_nodes[key]["node"], true)
	if _board_3d != null and _gs != null:
		_board_3d.set_target_highlight(targets, _gs, true)


func _clear_highlights() -> void:
	for key in _target_nodes.keys():
		CardView.set_highlight(_target_nodes[key]["node"], false)
	if _board_3d != null:
		_board_3d.clear_highlights()


func _hide_arrow() -> void:
	if _tarrow != null:
		_tarrow.visible = false
	if _arrow != null:
		_arrow.visible = false
	if _arrowhead != null:
		_arrowhead.visible = false


# --- Modal mouse-filter audit (Sprint 1a.3) ---
# The 1a.2 inspect softlock: a full-screen dimming ColorRect and the
# PanelContainer kept MOUSE_FILTER_STOP, swallowing every tap so the
# overlay root's gui_input (the dismiss handler) never fired. Rule for
# every modal: the overlay ROOT is the only STOP control (it owns the
# dismiss); every non-interactive descendant is IGNORE. Interactive
# Buttons keep STOP (they dismiss/select via their own handlers).
func _modal_descendants_ignore(root: Control) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Button:
				continue  # interactive: keeps STOP, dismisses/selects itself
			if ch is Control:
				(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			stack.append(ch)


# --- Magnify ---

func _show_magnify(card: Dictionary) -> void:
	if _magnify_overlay != null:
		return
	_hide_arrow()
	_clear_highlights()
	if _board_zone != null:
		_board_zone.modulate = Color.WHITE
	var overlay := Control.new()
	overlay.name = "MagnifyOverlay"
	overlay.z_index = 200
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	_full_rect(bg)
	overlay.add_child(bg)
	var big := CardView.make_magnified_card(card)
	big.name = "MagnifiedCard"
	# Hotfix 1c.2: keyword definitions below the magnified card (the
	# small pool tiles intentionally omit them; the magnified full-card
	# view is where they go). Shift the card up to make room.
	var kw_box: VBoxContainer = _keyword_help_box(card, 18, 600.0)
	var kw_h: float = 0.0
	if kw_box != null:
		kw_h = _inspect_keywords(card).size() * 28.0
	var card_y: float = maxf(8.0, (720.0 - 640.0 - kw_h) / 2.0)
	big.position = Vector2((VIEW_W - 460) / 2.0, card_y)
	big.pivot_offset = big.size / 2.0
	big.scale = Vector2(0.85, 0.85)
	overlay.add_child(big)
	if kw_box != null:
		kw_box.position = Vector2((VIEW_W - 600.0) / 2.0, card_y + 646.0)
		overlay.add_child(kw_box)
	overlay.gui_input.connect(_on_magnify_gui_input)
	# Sprint 1a.3: the dim bg and the card must not swallow taps — the
	# overlay root owns the dismiss. (The big card is a Button by
	# construction but is NOT interactive here, so it goes IGNORE too;
	# taps fall through to the root.)
	_modal_descendants_ignore(overlay)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_magnify_overlay = overlay
	overlay.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(overlay, "modulate", Color(1, 1, 1, 1), 0.15)
	tw.parallel().tween_property(big, "scale", Vector2.ONE, 0.18)


func _on_magnify_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_dismiss_magnify()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss_magnify()


func _dismiss_magnify() -> void:
	if _magnify_overlay == null:
		return
	var ov: Control = _magnify_overlay
	_magnify_overlay = null
	_db_press = {}
	ov.queue_free()


# --- Inspect panel (Sprint 1a.2, item 7) ---
# Long-press ANY minion (either side), either hero plaque, or a hand
# card -> full art, name, CURRENT attack/health (red damaged / green
# buffed), full card text, and a one-line explanation per keyword.
# A tap on an enemy (not while targeting) also inspects.

const KEYWORD_HELP: Dictionary = {
	"Bouncer": "Enemies must attack this first.",
	"Hustle": "Can attack the turn it's played.",
	"Entrance": "Happens when you play it from your hand.",
	"Final Bow": "Happens when it dies.",
	# Mechanics pass, wave 1.
	"Stunt Double": "The first damage it takes does nothing.",
	"Backstage": "Can't be attacked or targeted until it attacks.",
	"Encore": "Can attack twice each turn.",
	"Showstopper": "Destroys any Crew member it damages.",
	"Tip Jar": "Damage it deals heals your Boss.",
	"Heckle": "Removes a Crew member's text and buffs.",
	"Stage Fright": "The target misses its next attack.",
	"On Credit": "Cheap now: some of your mana is locked next turn.",
	"Vibe": "Helps other Crew while it's on the board.",
}


func _inspect_keywords(card: Dictionary) -> Array:
	var out: Array = []
	var kws: Array = card.get("keywords", [])
	if "taunt" in kws:
		out.append("Bouncer")
	if "charge" in kws:
		out.append("Hustle")
	if str(card.get("effect", "")) != "" and str(card.get("type", "")) == "minion":
		out.append("Entrance")
	if str(card.get("deathrattle", "")) != "":
		out.append("Final Bow")
	for pair in [["shield", "Stunt Double"], ["stealth", "Backstage"], ["windfury", "Encore"], ["poison", "Showstopper"], ["lifesteal", "Tip Jar"]]:
		if pair[0] in kws:
			out.append(pair[1])
	var effs: Array = [str(card.get("effect", "")), str(card.get("effect2", "")), str(card.get("deathrattle", ""))]
	for t in card.get("triggers", []):
		effs.append(str(t.get("effect", "")))
	if "silence" in effs:
		out.append("Heckle")
	if "freeze" in effs:
		out.append("Stage Fright")
	if int(card.get("overload", 0)) > 0:
		out.append("On Credit")
	if not (card.get("vibe", {}) as Dictionary).is_empty():
		out.append("Vibe")
	return out


# Hotfix 1c.2: keyword explanation lines for the deckbuilder magnify
# view and the hand preview (Alex: keywords were only defined on the
# battlefield inspect panel). Same four lines as the inspect panel.
# Returns null when the card has no keywords.
func _keyword_help_box(card: Dictionary, font_size: int, width: float) -> VBoxContainer:
	var kws: Array = _inspect_keywords(card)
	if kws.is_empty():
		return null
	var box := VBoxContainer.new()
	box.name = "KeywordHelp"
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A dark plate behind the lines so they read over the board.
	var plate_sb: StyleBox = CardView.panel_style(Color(0.06, 0.04, 0.1, 0.88), 10)
	box.draw.connect(func() -> void: box.draw_style_box(plate_sb, Rect2(Vector2(-6, -4), box.size + Vector2(12, 8))))
	for kw in kws:
		var l := CardView.label("%s — %s" % [kw, KEYWORD_HELP.get(kw, "")], font_size, CardView.GOLD_TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	return box


func _inspect_data_for_card(card: Dictionary) -> Dictionary:
	if card.is_empty():
		return {}
	return {
		"art_id": str(card.get("art", "")),
		"card_id": str(card.get("id", "")),
		"name": str(card.get("name", "")),
		"is_hero": false,
		"attack": int(card.get("attack", 0)),
		"base_attack": int(card.get("attack", 0)),
		"health": int(card.get("health", 0)),
		"base_health": int(card.get("health", 0)),
		"max_health": int(card.get("health", 0)),
		"text": str(card.get("text", "")),
		"keywords": _inspect_keywords(card),
	}


func _inspect_data_for_minion(minion: Dictionary) -> Dictionary:
	var d: Dictionary = _inspect_data_for_card(CardDB.get_card(str(minion.get("card_id", ""))))
	if d.is_empty():
		return {}
	# CURRENT stats (live from the board), not the base card.
	d["attack"] = int(minion.get("attack", d["attack"]))
	d["health"] = int(minion.get("health", d["health"]))
	d["max_health"] = int(minion.get("max_health", d["max_health"]))
	d["taunt"] = bool(minion.get("taunt", false))
	if bool(minion.get("sick", false)) and not bool(minion.get("can_attack", false)):
		d["status"] = "Warming up. Can attack next turn."
	return d


func _inspect_data_for_hero(player_idx: int) -> Dictionary:
	if _gs == null:
		return {}
	var p: Dictionary = _gs.players[player_idx]
	var class_id: String = str(p.get("class", ""))
	var hp_info: Dictionary = CardDB.hero_power_for(class_id)
	return {
		"art_id": str(CardView.CLASS_ART.get(class_id, "token")),
		"name": "Player %d — %s" % [player_idx + 1, CardDB.class_display_name(class_id)],
		"is_hero": true,
		"health": int(p["hp"]),
		"hero_power_name": str(hp_info.get("name", "")),
		"hero_power_text": str(hp_info.get("text", "")),
	}


func _inspect_data_for_press_ctx(ctx: Dictionary) -> Dictionary:
	if _gs == null:
		return {}
	match ctx.get("kind", ""):
		"hand_card":
			var active: int = _gs.active
			var idx: int = int(ctx.get("hand_idx", -1))
			var hand: Array = _gs.players[active]["hand"]
			if idx >= 0 and idx < hand.size():
				return _inspect_data_for_card(CardDB.get_card(str(hand[idx])))
		"my_minion":
			var bi: int = int(ctx.get("board_idx", -1))
			var board: Array = _gs.players[_gs.active]["board"]
			if bi >= 0 and bi < board.size():
				return _inspect_data_for_minion(board[bi])
		"my_hero":
			return _inspect_data_for_hero(int(ctx.get("player", _gs.active)))
		"target":
			var tgt: Dictionary = ctx.get("target", {})
			return _inspect_data_for_target(tgt)
	return {}


func _inspect_data_for_target(tgt: Dictionary) -> Dictionary:
	if _gs == null or tgt.is_empty():
		return {}
	if str(tgt.get("kind", "")) == "hero":
		return _inspect_data_for_hero(int(tgt.get("player", 0)))
	var p: int = int(tgt.get("player", 0))
	var bi: int = int(tgt.get("board_idx", -1))
	var board: Array = _gs.players[p]["board"]
	if bi >= 0 and bi < board.size():
		return _inspect_data_for_minion(board[bi])
	return {}


func _show_inspect_for_target(tgt: Dictionary) -> void:
	var data: Dictionary = _inspect_data_for_target(tgt)
	if not data.is_empty():
		_show_inspect(data)


func _show_inspect(data: Dictionary) -> void:
	if data.is_empty() or _inspect_overlay != null:
		return
	if not bool(data.get("is_hero", false)) and not bool(data.get("is_power", false)) and str(data.get("detail_line", "")) == "":
		_show_card_inspect(data)
		return
	_hide_arrow()
	_clear_highlights()
	var overlay := Control.new()
	overlay.name = "InspectOverlay"
	overlay.z_index = 300
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	_full_rect(bg)
	overlay.add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CardView.panel_style(Color(0.10, 0.09, 0.14, 0.98), 16))
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -330
	panel.offset_right = 260
	panel.offset_bottom = 330
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	# Full art, LARGE.
	var art := CardArt.new()
	art.art_id = str(data.get("art_id", ""))
	art.card_id = str(data.get("card_id", ""))
	art.custom_minimum_size = Vector2(280, 280)
	art.size = Vector2(280, 280)
	var art_wrap := HBoxContainer.new()
	art_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	art_wrap.add_child(art)
	v.add_child(art_wrap)
	# Name.
	var name_l := CardView.label(str(data.get("name", "")), 30, CardView.GOLD_TEXT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	# Sprint 1c: plain-English detail line for action-history entries.
	var detail_line: String = str(data.get("detail_line", ""))
	if detail_line != "":
		var det_l := CardView.label(detail_line, 20, Color.WHITE)
		det_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		det_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(det_l)
	# Stats: CURRENT attack/health, red if damaged, green if buffed.
	if bool(data.get("is_hero", false)):
		var hp_l := CardView.label("HP %d" % int(data.get("health", 0)), 30, Color(0.4, 1.0, 0.4))
		hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hp_l)
		var hp_name := CardView.label(str(data.get("hero_power_name", "")), 22, CardView.GOLD_TEXT)
		hp_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hp_name)
		var hp_text := CardView.label(str(data.get("hero_power_text", "")), 20)
		hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hp_text)
	elif bool(data.get("is_power", false)):
		# Sprint 1c: Signature Move inspect (history detail + long-press).
		var cost_l := CardView.label("Cost %d" % int(data.get("cost", 2)), 28, Color(1.0, 0.85, 0.2))
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cost_l)
		var ptext_l := CardView.label(str(data.get("text", "")), 20)
		ptext_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ptext_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ptext_l)
	else:
		var atk: int = int(data.get("attack", 0))
		var hp: int = int(data.get("health", 0))
		var atk_c: Color = Color(0.4, 1.0, 0.4) if atk > int(data.get("base_attack", atk)) else Color.WHITE
		var hp_c: Color = Color.WHITE
		if hp < int(data.get("max_health", hp)):
			hp_c = Color(1.0, 0.35, 0.35)
		elif hp > int(data.get("base_health", hp)):
			hp_c = Color(0.4, 1.0, 0.4)
		var stats := HBoxContainer.new()
		stats.alignment = BoxContainer.ALIGNMENT_CENTER
		stats.add_theme_constant_override("separation", 30)
		stats.add_child(CardView.label("ATK %d" % atk, 28, atk_c))
		stats.add_child(CardView.label("HP %d" % hp, 28, hp_c))
		v.add_child(stats)
		var text_l := CardView.label(str(data.get("text", "")), 20)
		text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(text_l)
		for kw in data.get("keywords", []):
			var kw_l := CardView.label("%s — %s" % [kw, KEYWORD_HELP.get(kw, "")], 18, CardView.GOLD_TEXT)
			kw_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			kw_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(kw_l)
	overlay.add_child(panel)
	overlay.gui_input.connect(_on_inspect_gui_input)
	# Sprint 1a.3 (softlock fix): bg, panel and ALL descendants go
	# MOUSE_FILTER_IGNORE — the overlay root is the only STOP control,
	# so every tap reaches the dismiss handler. (Ian's diagnosis
	# confirmed: bg + panel kept STOP and swallowed every tap.)
	_modal_descendants_ignore(overlay)
	add_child(overlay)
	_inspect_overlay = overlay


# --- The hand follows the mouse: cards near the cursor rise, straighten
# and grow, their neighbours lean away; resting on one for a moment shows
# it big above the hand. ---
var _hand_hover_idx: int = -1
var _hand_hover_since: int = 0
var _hand_hover_preview: bool = false


func _tick_hand_fx(delta: float) -> void:
	if _screen != Screen.MATCH or _hand_zone == null or _hand_cards.is_empty():
		return
	var busy: bool = not _press.is_empty() or not _drag.is_empty() or _inspect_overlay != null
	if busy:
		_hand_hover_idx = -1
		return
	var mp: Vector2 = get_global_mouse_position()
	var top: float = _hand_zone.global_position.y
	var near: bool = hover_cards_enabled and mp.y > top - 70.0 and mp.y < get_viewport_rect().size.y + 4.0
	var k: float = minf(1.0, delta * 14.0)
	var hovered: int = -1
	var best: float = 1e9
	for i in _hand_cards.size():
		var cb: Control = _hand_cards[i]
		if not is_instance_valid(cb) or not cb.has_meta("fan_home"):
			continue
		var home: Vector2 = cb.get_meta("fan_home")
		var rot0: float = float(cb.get_meta("fan_rot"))
		var dx: float = mp.x - (_hand_zone.global_position.x + home.x + cb.size.x * 0.5)
		var f: float = exp(-pow(dx / 105.0, 2.0)) if near else 0.0
		var push: float = (-signf(dx) * 30.0 * exp(-pow(dx / 175.0, 2.0)) * (1.0 - f)) if near else 0.0
		var tpos: Vector2 = home + Vector2(push, -52.0 * f)
		var tsc: float = 1.0 + 0.16 * f
		cb.pivot_offset = Vector2(cb.size.x * 0.5, cb.size.y)
		cb.position = tpos if cb.position.distance_to(tpos) < 0.4 else cb.position.lerp(tpos, k)
		cb.rotation = lerp_angle(cb.rotation, lerpf(rot0, 0.0, f), k)
		var sc: float = lerpf(cb.scale.x, tsc, k)
		cb.scale = Vector2(sc, sc)
		cb.z_index = int(cb.get_meta("fan_z")) + (30 if f > 0.55 else 0)
		if near and absf(dx) < cb.size.x * 0.5 and absf(dx) < best:
			best = absf(dx)
			hovered = i
	if hovered != _hand_hover_idx:
		_hand_hover_idx = hovered
		_hand_hover_since = Time.get_ticks_msec()
		if _hand_hover_preview:
			_hide_hand_preview()
			_hand_hover_preview = false
		return
	if hovered >= 0 and not _hand_hover_preview and Time.get_ticks_msec() - _hand_hover_since >= HOVER_CARD_MS:
		var cbh: Control = _hand_cards[hovered]
		_show_hand_preview({"kind": "hand_card", "hand_idx": hovered, "node": cbh}, cbh.global_position.x + cbh.size.x * 0.5)
		_hand_hover_preview = true


# --- Hover a Crew member on the board: after a moment its card pops up
# beside it (no click needed), and goes away when the mouse moves off. ---
const HOVER_CARD_MS: int = 800
var hover_cards_enabled: bool = true  # (screenshot harnesses turn it off)
var _hover_uid: int = -1
var _hover_since: int = 0
var _hover_card: Control = null


func _tick_hover_card() -> void:
	var busy: bool = not hover_cards_enabled or _screen != Screen.MATCH or _board_3d == null or _gs == null or not _press.is_empty() \
		or not _drag.is_empty() or _inspect_overlay != null or _emote_menu != null \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var uid: int = -1
	var owner_p: int = -1
	if not busy:
		var hit: Dictionary = _board_3d.pick(get_viewport().get_canvas_transform() * get_global_mouse_position())
		if str(hit.get("kind", "")) == "minion":
			uid = int(hit.get("uid", -1))
			owner_p = int(hit.get("player", -1))
	if uid != _hover_uid:
		_clear_hover_card()
		_hover_uid = uid
		_hover_since = Time.get_ticks_msec()
		return
	if uid >= 0 and _hover_card == null and Time.get_ticks_msec() - _hover_since >= HOVER_CARD_MS:
		_show_hover_card(uid, owner_p)


func _clear_hover_card() -> void:
	if _hover_card != null and is_instance_valid(_hover_card):
		_hover_card.queue_free()
	_hover_card = null


func _show_hover_card(uid: int, p: int) -> void:
	if p < 0 or p > 1:
		return
	var minion: Dictionary = {}
	for m in _gs.players[p]["board"]:
		if _gs.uid_for(m) == uid:
			minion = m
	if minion.is_empty():
		return
	var data: Dictionary = _inspect_data_for_minion(minion)
	if data.is_empty():
		return
	var res: Dictionary = _board_3d.minion_position(uid)
	if not bool(res.get("found", false)):
		return
	var sp: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * _board_3d.screen_pos(res["position"])
	var cw: float = 230.0
	var ch: float = cw * CardFrame.ASPECT
	var box := VBoxContainer.new()
	box.name = "HoverCard"
	box.z_index = 200
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.add_child(CardView.make_card_button(_live_card(data), int(cw), int(ch)))
	_inspect_extras(box, data, 16)
	add_child(box)
	# Purely a picture: nothing in it takes the mouse.
	for n in box.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vw: float = _canvas_width()
	var x: float = sp.x + 80.0 if sp.x < vw * 0.5 else sp.x - 80.0 - cw
	box.position = Vector2(x, clampf(sp.y - ch * 0.5, 10.0, 720.0 - ch - 60.0))
	box.size.x = cw
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, 0.12)
	_hover_card = box


# A card or Crew member: the same gilded card as in your hand (current
# attack / health, damaged health in red, buffs in green), with its
# status and keyword help underneath.
func _show_card_inspect(data: Dictionary) -> void:
	_hide_arrow()
	_clear_highlights()
	var overlay := Control.new()
	overlay.name = "InspectOverlay"
	overlay.z_index = 300
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	_full_rect(bg)
	overlay.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_full_rect(v)
	var cw := HBoxContainer.new()
	cw.alignment = BoxContainer.ALIGNMENT_CENTER
	cw.add_child(CardView.make_card_button(_live_card(data), 320, 464))
	v.add_child(cw)
	_inspect_extras(v, data, 20)
	overlay.add_child(v)
	overlay.gui_input.connect(_on_inspect_gui_input)
	_modal_descendants_ignore(overlay)
	add_child(overlay)
	_inspect_overlay = overlay


# The card dictionary with the live numbers from inspect data.
func _live_card(data: Dictionary) -> Dictionary:
	var c: Dictionary = CardDB.get_card(str(data.get("card_id", ""))).duplicate()
	if c.is_empty():
		c = {"id": str(data.get("card_id", "")), "name": str(data.get("name", "")), "type": "minion", "cost": 0, "text": str(data.get("text", "")), "class": "neutral", "art": str(data.get("art_id", ""))}
	c["attack"] = int(data.get("attack", c.get("attack", 0)))
	c["health"] = int(data.get("health", c.get("health", 0)))
	c["max_health"] = int(data.get("max_health", c["health"]))
	c["base_attack"] = int(data.get("base_attack", c["attack"]))
	c["base_health"] = int(data.get("base_health", c["health"]))
	return c


func _inspect_extras(v: VBoxContainer, data: Dictionary, fs: int) -> void:
	var st: String = str(data.get("status", ""))
	var kws: Array = data.get("keywords", [])
	if st == "" and kws.is_empty():
		return
	# On a dark plate so it reads over the board.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", CardView.panel_style(Color(0.06, 0.04, 0.1, 0.88), 10))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	plate.add_child(inner)
	if st != "":
		var sl := CardView.label(st, fs, Color(0.75, 0.85, 1.0))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(sl)
	for kw in kws:
		var kw_l := CardView.label("%s — %s" % [kw, KEYWORD_HELP.get(kw, "")], fs - 2, CardView.GOLD_TEXT)
		kw_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kw_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(kw_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.custom_minimum_size.x = 300.0 if fs >= 18 else 230.0
	row.add_child(plate)
	v.add_child(row)


func _on_inspect_gui_input(event: InputEvent) -> void:
	# Tap anywhere to close.
	if event is InputEventScreenTouch and not event.pressed:
		_dismiss_inspect()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss_inspect()


func _dismiss_inspect() -> void:
	if _inspect_overlay == null:
		return
	var ov: Control = _inspect_overlay
	_inspect_overlay = null
	ov.queue_free()


# --- Emote menu (Sprint 1a.2): emotes are hidden; tapping your own hero
# portrait opens a small menu of the four. ---

func _show_emote_menu() -> void:
	if _emote_menu != null:
		return
	var overlay := Control.new()
	overlay.name = "EmoteMenu"
	overlay.z_index = 250
	_full_rect(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	# Six plaques in two columns either side of your Boss.
	var me: int = _view()
	var c: Vector2 = _boss_head_canvas(me) + Vector2(0, 40)
	for ei in Emotes.IDS.size():
		var id: String = Emotes.IDS[ei]
		var eb := EmotePill.new()
		eb.name = "Emote_" + id
		eb.label_text = Emotes.label(str(_gs.players[me]["class"]) if _gs != null else "grunk", id)
		var col: int = ei % 2
		var row: int = ei / 2
		var x: float = c.x + (-EmotePill.W - 70.0 - row * 14.0 if col == 0 else 70.0 + row * 14.0)
		var y: float = c.y - 70.0 + row * (EmotePill.H + 8.0)
		eb.position = Vector2(x, y)
		eb.pressed.connect(_on_emote_menu_picked.bind(id))
		overlay.add_child(eb)
		eb.scale = Vector2(0.6, 0.6)
		eb.modulate.a = 0.0
		var tw := eb.create_tween()
		tw.tween_interval(ei * 0.025)
		tw.tween_property(eb, "modulate:a", 1.0, 0.08)
		tw.parallel().tween_property(eb, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	overlay.gui_input.connect(_on_emote_menu_gui_input)
	# Sprint 1a.3 (softlock audit): only the buttons STOP; a tap anywhere
	# else falls through to the overlay root and dismisses.
	_modal_descendants_ignore(overlay)
	_emote_menu = overlay


func _on_emote_menu_picked(id: String) -> void:
	_dismiss_emote_menu()
	_send_emote(id)


func _on_emote_menu_gui_input(event: InputEvent) -> void:
	# Tap anywhere (outside the buttons) dismisses.
	if event is InputEventScreenTouch and not event.pressed:
		_dismiss_emote_menu()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss_emote_menu()


func _dismiss_emote_menu() -> void:
	if _emote_menu == null:
		return
	var ov: Control = _emote_menu
	_emote_menu = null
	ov.queue_free()


# --- Tap fallback (existing behavior) ---

func _do_tap(ctx: Dictionary) -> void:
	if _animating or _ai_turn:
		return
	match ctx.get("kind", ""):
		"hand_card":
			pass  # Sprint 1a.3: a tap NEVER plays a card (gesture only).
		"my_minion":
			_on_my_minion_pressed(int(ctx.get("board_idx", -1)))
		"my_hero":
			# Sprint 1a.2: tapping your own hero portrait opens the
			# (hidden) emote menu. Long-press inspects instead.
			_show_emote_menu()
		"target":
			# Sprint 1a.2: a tap on an enemy minion/hero while NOT
			# choosing a target opens the inspect panel. During
			# targeting the tap still selects the target.
			if _pending.is_empty():
				_show_inspect_for_target(ctx.get("target", {}))
			else:
				_on_target_pressed(ctx.get("target", {}))


func _on_my_minion_pressed(board_idx: int) -> void:
	var active: int = _gs.active
	if not _pending.is_empty() and _pending.get("kind") == "hero_power":
		var tgt: Dictionary = {"kind": "minion", "player": active, "board_idx": board_idx}
		if _do_hero_power(tgt):
			_pending = {}
			_after_action()
		return
	if not _pending.is_empty() and _pending.get("kind") == "attack" and _pending.get("board_idx") == board_idx:
		_pending = {}
		_refresh_match()
		return
	if _gs.can_attack(active, board_idx):
		_pending = {"kind": "attack", "board_idx": board_idx}
		_refresh_match()


func _on_target_pressed(target: Dictionary) -> void:
	var active: int = _gs.active
	if _pending.is_empty():
		return
	if _pending["kind"] == "attack":
		if _do_attack(int(_pending["board_idx"]), target):
			_pending = {}
			_after_action()



func _on_hero_power_pressed() -> void:
	if _animating or _ai_turn:
		return
	if not _pending.is_empty() and _pending.get("kind") == "hero_power":
		_pending = {}
		_refresh_match()
		return
	var active: int = _gs.active
	var hp_info: Dictionary = _gs.hero_power(active)
	if str(hp_info.get("target", "none")) == "friendly_minion":
		if _gs.hero_power_target_options(active).is_empty():
			return
		_pending = {"kind": "hero_power"}
		_refresh_match()
	else:
		if _do_hero_power({}):
			_after_action()


# --- Sprint 1c: Signature Move long-press -> inspect ---
# Long-press (>= GESTURE_PREVIEW_MS, same as hand cards) opens the
# inspect panel with the move's name/cost/text. A quick tap still uses
# it. Moving off the button cancels (same rule as hand cards).
func _on_sig_gesture_input(event: InputEvent, sig: Button) -> void:
	if _animating or _ai_turn:
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			if _sig_press.is_empty():
				_sig_press = {"t": Time.get_ticks_msec(), "start_pos": _global_pos(event, sig),
					"long_fired": false, "btn": sig}
		else:
			_on_sig_release()
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		if not _sig_press.is_empty():
			if _global_pos(event, sig).distance_to(_sig_press.get("start_pos", Vector2.ZERO)) > DRAG_THRESHOLD:
				_sig_press = {}  # moving off cancels


func _on_sig_release() -> void:
	if _sig_press.is_empty():
		return
	var long_fired: bool = bool(_sig_press.get("long_fired", false))
	var btn: Button = _sig_press.get("btn")
	_sig_press = {}
	if long_fired:
		return  # the inspect panel is open; its own dismiss rules apply
	if btn != null and is_instance_valid(btn) and not btn.disabled:
		_on_hero_power_pressed()


# Anything left the player at the controls can do this turn: a playable
# card, a Crew member that can attack, or a usable Signature Move. When
# nothing is left, END TURN turns emerald.
func _has_moves(p: int) -> bool:
	for i in _gs.players[p]["hand"].size():
		if _gs.can_play(p, i):
			return true
	for b in _gs.players[p]["board"].size():
		if _gs.can_attack(p, b) and not _gs.valid_attack_targets(p).is_empty():
			return true
	if not bool(_gs.players[p]["hero_power_used"]):
		var hp: Dictionary = _gs.hero_power(p)
		if str(hp.get("target", "none")) == "friendly_minion":
			if not _gs.hero_power_target_options(p).is_empty():
				return true
		elif _gs.can_use_hero_power(p):
			return true
	return false


# Every model this match can put on the board: both decks, hands and
# boards, the tokens their cards summon, and the Bosses.
func _match_model_ids() -> Array:
	var ids: Array = []
	for p in [0, 1]:
		var pl: Dictionary = _gs.players[p]
		ids.append("hero_" + str(pl["class"]))
		var cards: Array = []
		for k in ["deck", "hand"]:
			for c in pl.get(k, []):
				cards.append(str(c if c is String else c.get("card_id", c.get("id", ""))))
		for m in pl.get("board", []):
			ids.append(Minion3D.model_for(m))
		if _online3d and cards.has(""):
			for c in CardDB.cards_for_class(str(pl["class"])):
				cards.append(str((c as Dictionary).get("id", "")) if c is Dictionary else str(c))
		for cid in cards:
			if cid == "":
				continue
			ids.append(cid)
			var card: Dictionary = CardDB.get_card(cid)
			var tok: Variant = card.get("token", null)
			if tok is Dictionary:
				ids.append(Minion3D.model_for({"card_id": "", "art": str(tok.get("art", "")), "name": str(tok.get("name", ""))}))
		if str(pl["class"]) == "barnacle":
			ids.append(Minion3D.model_for({"card_id": "deckhand", "art": "deckhand", "name": "Deckhand"}))
	return ids


# The turn clock: 90 seconds per turn for whoever is at the controls (not
# while the computer plays). The last 15 burn down as a themed fuse to
# the END TURN button; at zero the turn ends by itself (after any
# animation in flight finishes).
func _tick_turn_clock(delta: float) -> void:
	if _turn_timer == null or not is_instance_valid(_turn_timer):
		return
	if _screen != Screen.MATCH or _gs == null or _gs.winner != -1 or not turn_timer_enabled:
		_turn_timer.left = TurnTimer.TURN_TIME
		return
	var key: String = "%d|%d" % [_gs.active, _gs.turn_count]
	if key != _clock_key:
		_clock_key = key
		_turn_timer.left = TurnTimer.TURN_TIME
		_turn_timer.deck = str(_gs.players[_gs.active]["class"])
	if _remote_turn():
		# The opponent's turn: the host keeps their clock and ends the
		# turn for them if they run past it (a short grace for lag).
		if _online3d and _online_role == "host" and _net_match != null:
			_turn_timer.left -= delta
			if _turn_timer.left < -5.0:
				_turn_timer.left = TurnTimer.TURN_TIME
				_net_match.host_force_end_turn()
			_turn_timer.visible = false
			return
		_turn_timer.left = TurnTimer.TURN_TIME
		return
	var vw: float = get_viewport_rect().size.x
	_turn_timer.to_x = vw - 196.0
	_turn_timer.from_x = vw * 0.42
	# Along the seam between the two rows (clear of the Crew), into the
	# top of the END TURN button.
	_turn_timer.line_y = 350.0
	if _board_3d != null:
		var seam: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * _board_3d.screen_pos(Vector3(0, 0, _board_3d.CENTER_Z))
		_turn_timer.line_y = clampf(seam.y, 310.0, 390.0)
	_turn_timer.left = maxf(0.0, _turn_timer.left - delta)
	if _turn_timer.left <= 0.0 and not _animating and not _ai_turn:
		_turn_timer.left = TurnTimer.TURN_TIME  # one end per timeout
		_press = {}
		_drag = {}
		_pending = {}
		_hide_arrow()
		_on_end_turn()


func _on_end_turn() -> void:
	if _animating or _ai_turn:
		return
	_dismiss_all_modals()  # Sprint 1a.3: end turn is a new action.
	_pending = {}
	if _online3d:
		if _submit_online({"act": "end_turn"}):
			# Show the hand-off at once; the host's reply can take a moment.
			var btn: Node = find_child("EndTurnBtn", true, false)
			if btn is EndTurnButton:
				(btn as EndTurnButton).set_look(EndTurnButton.Look.WAITING)
		return
	_gs.end_turn()
	_after_end_turn()


# Your emote: your Boss says it (and acts it), and online it goes to the
# other player. A short cooldown stops spamming.
var _emote_ready_at: int = 0

func _send_emote(id: String) -> void:
	if Time.get_ticks_msec() < _emote_ready_at or _gs == null:
		return
	_emote_ready_at = Time.get_ticks_msec() + 1800
	_show_emote(_view(), id)
	if _online3d and _net_match != null:
		_net_match.send_emote(id)
	elif _vs_ai and id == "hey":
		# The computer greets you back.
		get_tree().create_timer(1.3).timeout.connect(func() -> void:
			if _gs != null and _screen == Screen.MATCH:
				_show_emote(1 - _view(), "hey"))


# A Boss emote: a speech bubble beside the Boss's head, and the Boss acts.
func _show_emote(p: int, id: String) -> void:
	if _gs == null or p < 0 or p > 1:
		return
	var cls: String = str(_gs.players[p]["class"])
	var old: Node = find_child("Bubble%d" % p, false, false)
	if old != null:
		old.queue_free()
	# The same comic bubble as the title screen, in the Boss's color,
	# beside the Boss's head (clear of the Crew rows), tail pointing at it.
	var b := SpeechBubble.new()
	b.name = "Bubble%d" % p
	b.z_index = 120
	add_child(b)
	b.set_line(Emotes.line(cls, id), UIKit.CLASS_COLOR.get(cls, Color(1.0, 0.75, 0.35)))
	var head: Vector2 = _boss_head_canvas(p)
	var vs: Vector2 = get_viewport_rect().size
	var pos := head + Vector2(58, -b.size.y * 0.5 + 26)
	pos.x = clampf(pos.x, 170.0, vs.x - b.size.x - 210.0)
	pos.y = clampf(pos.y, 10.0, vs.y - b.size.y - 10.0)
	b.position = pos
	b.set_target(head)
	b.scale = Vector2(0.3, 0.3)
	b.modulate.a = 0.0
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(b, "modulate:a", 0.0, 0.35)
	tw.tween_callback(b.queue_free)
	if _board_3d != null:
		var u: HoloUnit = _board_3d.boss_unit(p)
		if u != null:
			u.emote_act(Emotes.act(cls, id))


# Canvas position of a Boss's head (the speech bubble's tail points here).
func _boss_head_canvas(p: int) -> Vector2:
	if _board_3d != null:
		var u: HoloUnit = _board_3d.boss_unit(p)
		if u != null and u.is_inside_tree():
			var h: float = HoloUnit.MODEL_HEIGHT * u.global_transform.basis.get_scale().y * 0.92
			var c2t: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
			return c2t * _board_3d.screen_pos(u.global_position + Vector3(0, h, 0))
	var hb: Variant = _hero_badges[p] if p >= 0 and p < _hero_badges.size() else null
	if hb != null and is_instance_valid(hb):
		return (hb as Control).get_global_rect().get_center()
	return Vector2(640, 360)


# --- Match log (user://match_log.jsonl, one JSON object per line) ---

func _append_match_log(log_path: String = MATCH_LOG_PATH) -> bool:
	if _gs == null or _gs.winner == -1:
		return false
	var entry: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(true),
		"classes": [str(_gs.players[0]["class"]), str(_gs.players[1]["class"])],
		"decklists": [_decks[0], _decks[1]],
		"first_player": {"player": 1, "class": str(_gs.players[0]["class"])},
		"winner": {"player": _gs.winner + 1, "class": str(_gs.players[_gs.winner]["class"])},
		# turn_count = number of player-turns that began (setup starts turn 1).
		"turn_count": _gs.turn_count,
	}
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	f.close()
	return true


# Export: open the log file with the OS (share sheet / file viewer) and
# show the path. If the OS cannot open it, copy the whole log to the
# clipboard instead and say so. Returns a status message for the caller.
func _export_log() -> String:
	var path: String = ProjectSettings.globalize_path(MATCH_LOG_PATH)
	if not FileAccess.file_exists(MATCH_LOG_PATH):
		return "No matches logged yet."
	var err: Error = OS.shell_open(path)
	if err != OK:
		var f := FileAccess.open(MATCH_LOG_PATH, FileAccess.READ)
		if f != null:
			DisplayServer.clipboard_set(f.get_as_text())
		return "Could not open the file — whole log copied to clipboard. Path: %s" % path
	return "Log opened. Path: %s" % path


# --- Game over ---

func _show_gameover() -> void:
	_screen = Screen.GAMEOVER
	if not _game_logged:
		_append_match_log()
		_game_logged = true
	_clear()
	add_child(CardView.bg_rect(CardView.TITLE_BG))
	var v := VBoxContainer.new()
	_full_rect(v)
	v.add_spacer(true)
	var wclass: String = CardDB.class_display_name(str(_gs.players[_gs.winner]["class"]))
	var head: String = "PLAYER %d WINS!" % (_gs.winner + 1)
	if _vs_ai or _online3d:
		head = "YOU WIN!" if _gs.winner == _human_idx else "YOU LOSE!"
	v.add_child(CardView.label(head, 56, CardView.GOLD_TEXT))
	v.add_child(CardView.label("%s — %d turns" % [wclass, _gs.turn_count], 28))
	if _online3d:
		var leave := CardView.button("BACK TO TITLE", 30, 420, 70, CardView.BTN_BLUE)
		leave.pressed.connect(func() -> void:
			_teardown_online()
			_show_title())
		v.add_child(leave)
		v.add_spacer(true)
		add_child(v)
		return
	var rematch := CardView.button("REMATCH (same decks)", 30, 420, 70, CardView.BTN_END)
	rematch.pressed.connect(_start_match)
	v.add_child(rematch)
	var new_decks := CardView.button("NEW DECKS", 30, 420, 70, CardView.BTN_BLUE)
	new_decks.pressed.connect(func() -> void: _goto(_show_hero_select) if _vs_ai else _on_play())
	v.add_child(new_decks)
	var export_btn := CardView.button("EXPORT MATCH LOG", 24, 320, 56, CardView.BTN_BLUE)
	var status := CardView.label("", 20)
	export_btn.pressed.connect(func() -> void: status.text = _export_log())
	v.add_child(export_btn)
	v.add_child(status)
	v.add_spacer(true)
	add_child(v)


# --- vs Computer ---

# Set up a match against the computer. The human's seat (first or
# second) is a coin flip; the computer builds its own deck.
func start_vs_ai(human_class: String, human_deck: Array, ai_class: String) -> void:
	_vs_ai = true
	_ai = AIPlayer.new()
	_human_idx = randi() % 2
	var ai_deck: Array = AIPlayer.build_deck(ai_class)
	_classes = ["", ""]
	_decks = [[], []]
	_classes[_human_idx] = human_class
	_decks[_human_idx] = human_deck
	_classes[1 - _human_idx] = ai_class
	_decks[1 - _human_idx] = ai_deck
	_start_match()


func _maybe_run_ai() -> void:
	if _vs_ai and _gs != null and _gs.winner == -1 and _gs.active != _human_idx and not _ai_turn:
		_run_ai_turn()


# The computer plays its turn one action at a time, each animated like a
# human action, with short pauses so the player can follow along.
func _run_ai_turn() -> void:
	_ai_turn = true
	var me: int = 1 - _human_idx
	await get_tree().create_timer(0.7).timeout
	var guard: int = 0
	while _gs != null and _gs.winner == -1 and _gs.active == me and guard < 60:
		guard += 1
		var a: Dictionary = _ai.next_action(_gs, me)
		if str(a.get("type", "end")) == "end":
			break
		if not AIPlayer.apply(_gs, me, a):
			break
		await _after_action()
		await get_tree().create_timer(0.45).timeout
		if _screen != Screen.MATCH:
			break
	_ai_turn = false
	if _gs == null or _screen != Screen.MATCH:
		return
	if _gs.winner != -1:
		_show_gameover()
		return
	_gs.end_turn()
	_after_end_turn()


var _leave_prompt: Control = null


func _toggle_leave_prompt() -> void:
	if _leave_prompt != null and is_instance_valid(_leave_prompt):
		_leave_prompt.queue_free()
		_leave_prompt = null
		return
	var o := Control.new()
	o.name = "LeavePrompt"
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.z_index = 200
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	c.add_child(v)
	var q := UIKit.label("LEAVE THIS MATCH?", 40, Color.WHITE, UIKit.FONT_DISPLAY_PATH, 10)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var yes := UIKit.button("YES, QUIT", UIKit.BTN_RED, 28, Vector2(360, 70))
	yes.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	yes.pressed.connect(func() -> void:
		_leave_prompt = null
		_goto(_show_title))
	v.add_child(yes)
	var no := UIKit.button("KEEP PLAYING", UIKit.BTN_GREEN, 28, Vector2(360, 70))
	no.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	no.pressed.connect(_toggle_leave_prompt)
	v.add_child(no)
	add_child(o)
	_leave_prompt = o
