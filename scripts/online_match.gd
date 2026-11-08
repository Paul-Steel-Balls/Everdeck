extends Control
class_name OnlineMatch

# Sprint MP-1: the online match screen. Used by BOTH players: the host
# and the guest render the same way, from NetMatch's mirror GameState,
# always from their own perspective (your hero + hand at the bottom,
# opponent at the top; the opponent's hand is a count, never cards).
# Input sends intended actions to NetMatch.submit_action; the screen
# re-renders on every sync_applied. No rules live here — legality is
# the host engine's call (the mirror's read-only helpers are used only
# to decide what to highlight).
#
# Deliberately a plain 2D screen (CardView rows), not the 3D table:
# MP-1's job is the network foundation. Wiring the 3D table +
# AnimDirector to the mirror is a later sprint.

signal leave_requested

var _nm: NetMatch = null
var _my_idx: int = 0
var _opp_idx: int = 1

var _title_label: Label = null
var _status_label: Label = null
var _log_label: Label = null
var _opp_hero_btn: Button = null
var _opp_info_label: Label = null
var _my_hero_btn: Button = null
var _my_info_label: Label = null
var _opp_board_box: HBoxContainer = null
var _my_board_box: HBoxContainer = null
var _hand_box: HBoxContainer = null
var _power_btn: Button = null
var _end_turn_btn: Button = null
var _banner: PanelContainer = null
var _banner_label: Label = null

# Current selection: {} or {"kind":"card","hand_idx":int} or
# {"kind":"attack","uid":int} or {"kind":"power"}.
var _sel: Dictionary = {}
var _log_lines: Array = []


func _ready() -> void:
	add_child(CardView.bg_rect(CardView.TABLE_BG))
	var root := VBoxContainer.new()
	CardView.full_rect(root)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	_title_label = CardView.label("ONLINE MATCH", 26, CardView.GOLD_TEXT)
	top.add_child(_title_label)
	var leave := CardView.button("LEAVE", 20, 120, 44, CardView.BTN_BLUE)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	top.add_child(leave)
	root.add_child(top)

	_status_label = CardView.label("", 24)
	root.add_child(_status_label)

	# Opponent block.
	var opp_row := HBoxContainer.new()
	opp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_opp_hero_btn = CardView.button("", 22, 340, 64, CardView.BTN_BLUE)
	_opp_hero_btn.pressed.connect(_on_hero_tapped.bind(false))
	opp_row.add_child(_opp_hero_btn)
	_opp_info_label = CardView.label("", 20)
	opp_row.add_child(_opp_info_label)
	root.add_child(opp_row)
	_opp_board_box = HBoxContainer.new()
	_opp_board_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_opp_board_box.custom_minimum_size = Vector2(0, 140)
	root.add_child(_opp_board_box)

	# My board.
	_my_board_box = HBoxContainer.new()
	_my_board_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_board_box.custom_minimum_size = Vector2(0, 140)
	root.add_child(_my_board_box)

	# My hero + controls.
	var my_row := HBoxContainer.new()
	my_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_hero_btn = CardView.button("", 22, 340, 64, CardView.BTN_END)
	_my_hero_btn.pressed.connect(_on_hero_tapped.bind(true))
	my_row.add_child(_my_hero_btn)
	_my_info_label = CardView.label("", 20)
	my_row.add_child(_my_info_label)
	_power_btn = CardView.button("SIGNATURE MOVE", 20, 220, 56, CardView.BTN_BLUE)
	_power_btn.pressed.connect(_on_power_tapped)
	my_row.add_child(_power_btn)
	_end_turn_btn = CardView.button("END TURN", 24, 200, 64, CardView.BTN_END, CardView.INK)
	_end_turn_btn.pressed.connect(_on_end_turn)
	my_row.add_child(_end_turn_btn)
	root.add_child(my_row)

	# My hand.
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.custom_minimum_size = Vector2(0, 176)
	root.add_child(_hand_box)

	_log_label = CardView.label("", 17)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_log_label)

	# Banner (game over / disconnect), hidden until needed.
	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	var bv := VBoxContainer.new()
	_banner_label = CardView.label("", 34, CardView.GOLD_TEXT)
	bv.add_child(_banner_label)
	var b_leave := CardView.button("BACK TO TITLE", 24, 260, 60, CardView.BTN_BLUE)
	b_leave.pressed.connect(func() -> void: leave_requested.emit())
	bv.add_child(b_leave)
	_banner.add_child(bv)
	add_child(_banner)


func setup(nm: NetMatch, my_idx: int) -> void:
	_nm = nm
	_my_idx = my_idx
	_opp_idx = 1 - my_idx
	_nm.sync_applied.connect(_on_sync)
	_nm.action_rejected.connect(_on_rejected)
	_nm.opponent_disconnected.connect(_on_opponent_gone)
	_title_label.text = "ONLINE MATCH — Room %s · You are Player %d" % [_nm.room_code, _my_idx + 1]
	_refresh()


func _mirror() -> GameState:
	return _nm.mirror if _nm != null else null


func _my_turn() -> bool:
	var m := _mirror()
	return m != null and m.players.size() == 2 and m.active == _my_idx and m.winner == -1


# --- Sync / refresh ---

func _on_sync(events: Array) -> void:
	for e in events:
		_note_event(e)
	_refresh()
	var m := _mirror()
	if m != null and m.winner != -1:
		_show_banner("YOU WIN!" if m.winner == _my_idx else "YOU LOSE")
		_status_label.text = "Match over."


func _on_rejected(reason: String) -> void:
	_status_label.text = "Host rejected that: %s" % reason


func _on_opponent_gone() -> void:
	_show_banner("OPPONENT DISCONNECTED")
	_status_label.text = "Your opponent left the match."


func _show_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true


func _note_event(e: Dictionary) -> void:
	var m := _mirror()
	var t: String = str(e.get("type", ""))
	var d: Dictionary = e.get("data", {})
	var line: String = ""
	match t:
		"turn_start":
			line = "— Player %d's turn —" % (int(d.get("player", 0)) + 1)
		"card_played":
			var c: Dictionary = CardDB.get_card(str(d.get("card_id", "")))
			line = "Player %d played %s." % [int(d.get("player", 0)) + 1, str(c.get("name", "?"))]
		"signature_move":
			line = "Player %d used their Signature Move." % (int(d.get("player", 0)) + 1)
		"attack":
			line = "Player %d attacked." % (int(d.get("player", 0)) + 1)
		"game_over":
			line = "Game over — Player %d wins." % (int(d.get("winner", 0)) + 1)
	if line != "":
		_log_lines.append(line)
		while _log_lines.size() > 5:
			_log_lines.pop_front()
		_log_label.text = "\n".join(_log_lines)


func _refresh() -> void:
	var m := _mirror()
	if m == null or m.players.size() < 2:
		_status_label.text = "Starting match…"
		return
	var me: Dictionary = m.players[_my_idx]
	var opp: Dictionary = m.players[_opp_idx]
	_opp_hero_btn.text = "%s — HP %d" % [CardDB.class_display_name(str(opp["class"])), int(opp["hp"])]
	_opp_info_label.text = "  Hand: %d · Deck: %d · Mana: %d/%d" % [
		(opp["hand"] as Array).size(), (opp["deck"] as Array).size(), int(opp["mana"]), int(opp["max_mana"])]
	_my_hero_btn.text = "%s — HP %d" % [CardDB.class_display_name(str(me["class"])), int(me["hp"])]
	_my_info_label.text = "  Mana: %d/%d · Deck: %d" % [int(me["mana"]), int(me["max_mana"]), (me["deck"] as Array).size()]
	if m.winner != -1:
		_status_label.text = "Match over."
	elif _my_turn():
		_status_label.text = "Your turn. Tap a card, a Crew member, or END TURN."
	else:
		_status_label.text = "Opponent's turn — watching…"
	_end_turn_btn.disabled = not _my_turn()
	_power_btn.disabled = not _my_turn() or bool(me["hero_power_used"]) or int(me["mana"]) < GameState.HERO_POWER_COST
	_rebuild_board(_opp_board_box, _opp_idx, false)
	_rebuild_board(_my_board_box, _my_idx, true)
	_rebuild_hand()


func _rebuild_board(box: HBoxContainer, p_idx: int, mine: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	var m := _mirror()
	for bi in (m.players[p_idx]["board"] as Array).size():
		var minion: Dictionary = m.players[p_idx]["board"][bi]
		var b := CardView.make_minion_button(minion, mine)
		var uid: int = int(minion.get("uid", -1))
		b.pressed.connect(_on_minion_tapped.bind(p_idx, uid))
		box.add_child(b)


func _rebuild_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()
	var m := _mirror()
	var hand: Array = m.players[_my_idx]["hand"]
	for i in hand.size():
		var card: Dictionary = CardDB.get_card(str(hand[i]))
		if card.is_empty():
			continue
		var b := CardView.make_card_button(card, 130, 170)
		if not _sel.is_empty() and str(_sel.get("kind", "")) == "card" and int(_sel.get("hand_idx", -1)) == i:
			CardView.set_highlight(b, true)
		b.pressed.connect(_on_hand_tapped.bind(i))
		_hand_box.add_child(b)


# --- Input ---

func _on_hand_tapped(hand_idx: int) -> void:
	if not _my_turn():
		return
	var m := _mirror()
	var card: Dictionary = CardDB.get_card(str(m.players[_my_idx]["hand"][hand_idx]))
	if card.is_empty() or not m.can_play(_my_idx, hand_idx):
		return
	if m.card_target_options(_my_idx, card).is_empty():
		_nm.submit_action({"act": "play_card", "hand_idx": hand_idx, "target": {}})
		_sel = {}
	else:
		_sel = {"kind": "card", "hand_idx": hand_idx}
		_status_label.text = "Choose a target for %s." % str(card.get("name", "that card"))
	_refresh()


func _on_minion_tapped(p_idx: int, uid: int) -> void:
	if not _my_turn():
		return
	var m := _mirror()
	if not _sel.is_empty():
		# A selection is pending: this tap is a target choice.
		var target: Dictionary = {"kind": "minion", "uid": uid}
		match str(_sel.get("kind", "")):
			"card":
				_nm.submit_action({"act": "play_card", "hand_idx": int(_sel["hand_idx"]), "target": target})
			"attack":
				_nm.submit_action({"act": "attack", "attacker_uid": int(_sel["uid"]), "target": target})
			"power":
				_nm.submit_action({"act": "hero_power", "target": target})
		_sel = {}
		_refresh()
		return
	# No selection: tapping my ready minion selects it as an attacker.
	if p_idx == _my_idx:
		var bidx: int = m.minion_index_by_uid(_my_idx, uid)
		if bidx >= 0 and m.can_attack(_my_idx, bidx):
			_sel = {"kind": "attack", "uid": uid}
			_status_label.text = "Choose what to attack."
			_refresh()


func _on_hero_tapped(mine: bool) -> void:
	if not _my_turn() or _sel.is_empty():
		return
	var p_idx: int = _my_idx if mine else _opp_idx
	var target: Dictionary = {"kind": "hero", "player": p_idx}
	match str(_sel.get("kind", "")):
		"card":
			_nm.submit_action({"act": "play_card", "hand_idx": int(_sel["hand_idx"]), "target": target})
		"attack":
			_nm.submit_action({"act": "attack", "attacker_uid": int(_sel["uid"]), "target": target})
		"power":
			_nm.submit_action({"act": "hero_power", "target": target})
	_sel = {}
	_refresh()


func _on_power_tapped() -> void:
	if not _my_turn():
		return
	var m := _mirror()
	var hp: Dictionary = m.hero_power(_my_idx)
	if str(hp.get("target", "none")) == "friendly_minion":
		if m.hero_power_target_options(_my_idx).is_empty():
			return
		_sel = {"kind": "power"}
		_status_label.text = "Choose one of your Crew."
		_refresh()
	else:
		_nm.submit_action({"act": "hero_power", "target": {}})


func _on_end_turn() -> void:
	if not _my_turn():
		return
	_sel = {}
	_nm.submit_action({"act": "end_turn"})
