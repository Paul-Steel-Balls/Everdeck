extends Node
class_name NetMatch

# Sprint MP-1: online match protocol on top of NetClient.
#
# Model: HOST IS AUTHORITATIVE. The host owns the one real GameState.
# The guest sends intended actions (act messages, targets named by
# minion uid, never board index); the host validates them through the
# engine's own methods and, on success, broadcasts a "sync": the
# engine's event stream PLUS an authoritative state snapshot.
#
# Hidden information is enforced in the sync itself, per recipient:
#  - a snapshot only ever contains the RECIPIENT's own hand card ids;
#    the opponent's hand is a count, their deck is a count.
#  - draw / card_burned events for the other player have card_id
#    stripped before they leave the host.
# Both clients (host included) render from a mirror GameState whose
# public fields are overwritten by each snapshot, so host and guest run
# the exact same view code path. The snapshot is the source of truth;
# the event stream rides along for animation/history.
#
# Handshake: both sides commit a deck hash first; the guest then
# reveals its deck+class, the host verifies the hash, validates the
# deck with GameState.validate_deck, flips for first player, runs
# setup(), and sends match_start + the initial sync. (The host's own
# deck is never revealed to the guest — it is hidden information; its
# commit hash is sent for the record only.)

signal status_changed(text: String)
signal room_ready(code: String)
signal match_started(my_idx: int)
signal sync_applied(events: Array)
signal action_rejected(reason: String)
signal opponent_disconnected
signal failed(reason: String)

var net: NetClient = null
var role: String = ""  # "host" or "guest"
var my_idx: int = -1
var mirror: GameState = null
var room_code: String = ""

var _my_deck: Array = []
var _my_class: String = ""
var _my_commit: String = ""
var _started: bool = false

# Host-only state.
var _gs: GameState = null
var _peer_commit: String = ""
var _peer_deck: Array = []
var _peer_class: String = ""

# Guest-only state.
var _host_commit: String = ""


static func deck_hash(deck: Array) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(deck).to_utf8_buffer())
	return h.finish().hex_encode()


func _ready() -> void:
	net = NetClient.new()
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.connect_failed.connect(func(reason: String) -> void: failed.emit("Could not reach the relay: %s" % reason))
	net.disconnected.connect(_on_net_disconnected)
	net.room_created.connect(_on_room_created)
	net.joined.connect(_on_joined)
	net.join_failed.connect(func(reason: String) -> void:
		if role == "guest" and not _started:
			failed.emit("Join failed: %s" % reason)
	)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_gone)
	net.game_message.connect(_on_game_message)


# --- Entry points (called by the UI / tests) ---

func host_game(url: String, deck: Array, class_id: String) -> void:
	role = "host"
	_my_deck = deck.duplicate()
	_my_class = class_id
	_my_commit = deck_hash(_my_deck)
	status_changed.emit("Connecting to relay…")
	net.connect_to_relay(url)


func join_game(url: String, code: String, deck: Array, class_id: String) -> void:
	role = "guest"
	room_code = code.to_upper()
	_my_deck = deck.duplicate()
	_my_class = class_id
	_my_commit = deck_hash(_my_deck)
	status_changed.emit("Connecting to relay…")
	net.connect_to_relay(url)


# One player action. Host: applied to the authoritative engine now.
# Guest: sent to the host; the result comes back as a sync (or reject).
func submit_action(act: Dictionary) -> void:
	if not _started:
		return
	if role == "host":
		_host_apply(my_idx, act)
	else:
		var m: Dictionary = act.duplicate()
		m["t"] = "act"
		net.send_game(m)


func leave() -> void:
	net.close()


# --- NetClient signal handlers ---

func _on_net_connected() -> void:
	if role == "host":
		status_changed.emit("Connected — creating room…")
		net.create_room()
	else:
		status_changed.emit("Connected — joining room %s…" % room_code)
		net.join_room(room_code)


func _on_room_created(code: String) -> void:
	room_code = code
	status_changed.emit("Room created. Waiting for your opponent…")
	room_ready.emit(code)


func _on_peer_joined() -> void:
	# Host: exchange deck commitments.
	status_changed.emit("Opponent connected — exchanging decks…")
	net.send_game({"t": "commit", "hash": _my_commit})


func _on_peer_gone() -> void:
	if _started:
		opponent_disconnected.emit()
	else:
		failed.emit("Opponent left before the match started.")


func _on_net_disconnected() -> void:
	if _started:
		opponent_disconnected.emit()
	elif role != "":
		failed.emit("Disconnected from the relay.")


# --- Game messages ---

func _on_game_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	match t:
		"commit":
			if role == "host":
				_peer_commit = str(msg.get("hash", ""))
			else:
				_host_commit = str(msg.get("hash", ""))
		"reveal":
			if role == "host":
				_host_on_reveal(msg)
		"match_start":
			if role == "guest":
				_guest_on_match_start(msg)
		"sync":
			if role == "guest":
				_apply_sync(msg)
		"act":
			if role == "host" and _started:
				_host_apply(1 - my_idx, msg)
		"reject":
			action_rejected.emit(str(msg.get("reason", "Action rejected by host.")))
		"reject_setup":
			failed.emit("Host rejected the setup: %s" % str(msg.get("reason", "")))


# Guest side of the handshake: on "joined", commit then reveal.
func _on_joined(_code: String) -> void:
	status_changed.emit("Joined — sending deck commitment…")
	net.send_game({"t": "commit", "hash": _my_commit})
	net.send_game({"t": "reveal", "deck": _my_deck, "class": _my_class})
	status_changed.emit("Deck sent — waiting for the host to start…")


func _guest_on_match_start(msg: Dictionary) -> void:
	my_idx = int(msg.get("your_idx", -1))
	mirror = GameState.new()
	_started = true
	status_changed.emit("Match started!")
	match_started.emit(my_idx)


# --- Host: setup + authoritative actions ---

func _host_on_reveal(msg: Dictionary) -> void:
	if _started:
		return
	var deck: Array = msg.get("deck", [])
	var class_id: String = str(msg.get("class", ""))
	if _peer_commit != "" and deck_hash(deck) != _peer_commit:
		net.send_game({"t": "reject_setup", "reason": "deck does not match its commitment hash"})
		failed.emit("Guest deck did not match its commitment hash.")
		return
	if not GameState.validate_deck(deck, class_id):
		net.send_game({"t": "reject_setup", "reason": "deck failed validation"})
		failed.emit("Guest deck failed validation.")
		return
	_peer_deck = deck.duplicate()
	_peer_class = class_id
	# First player decided host-side: a fair flip for who is Player 1.
	var flip := RandomNumberGenerator.new()
	flip.randomize()
	var host_first: bool = flip.randf() < 0.5
	var decks: Array = [_my_deck, _peer_deck] if host_first else [_peer_deck, _my_deck]
	var classes: Array = [_my_class, _peer_class] if host_first else [_peer_class, _my_class]
	my_idx = 0 if host_first else 1
	_gs = GameState.new()
	_gs.setup(decks[0], decks[1], classes[0], classes[1])
	mirror = GameState.new()
	_started = true
	net.send_game({"t": "match_start", "your_idx": 1 - my_idx, "classes": classes})
	_broadcast_sync([])
	status_changed.emit("Match started!")
	match_started.emit(my_idx)


func _host_apply(sender_idx: int, act: Dictionary) -> void:
	if _gs == null or _gs.winner != -1:
		_host_reject(sender_idx, "The match is over.")
		return
	if _gs.active != sender_idx:
		_host_reject(sender_idx, "Not your turn.")
		return
	var kind: String = str(act.get("act", ""))
	var ok: bool = false
	match kind:
		"play_card":
			ok = _gs.play_card(sender_idx, int(act.get("hand_idx", -1)), _resolve_target(act.get("target", {})))
		"attack":
			var bidx: int = _gs.minion_index_by_uid(sender_idx, int(act.get("attacker_uid", -1)))
			if bidx >= 0:
				ok = _gs.attack(sender_idx, bidx, _resolve_target(act.get("target", {})))
		"hero_power":
			ok = _gs.use_hero_power(sender_idx, _resolve_target(act.get("target", {})))
		"end_turn":
			_gs.end_turn()
			ok = true
		_:
			_host_reject(sender_idx, "Unknown action.")
			return
	if not ok:
		_host_reject(sender_idx, "Illegal action.")
		return
	_broadcast_sync(_gs.take_events())


func _host_reject(sender_idx: int, reason: String) -> void:
	if sender_idx == my_idx:
		action_rejected.emit(reason)
	else:
		net.send_game({"t": "reject", "reason": reason})


# Translate a wire target ({kind:"minion", uid} / {kind:"hero", player}
# / {}) into the engine's board-index target dict.
func _resolve_target(t: Variant) -> Dictionary:
	if not (t is Dictionary) or (t as Dictionary).is_empty():
		return {}
	var td: Dictionary = t
	if str(td.get("kind", "")) == "hero":
		return {"kind": "hero", "player": int(td.get("player", -1)), "board_idx": -1}
	if str(td.get("kind", "")) == "minion":
		var uid: int = int(td.get("uid", -1))
		for p in 2:
			var idx: int = _gs.minion_index_by_uid(p, uid)
			if idx >= 0:
				return {"kind": "minion", "player": p, "board_idx": idx}
		return {"kind": "minion", "player": -1, "board_idx": -1}
	return {}


func _broadcast_sync(events: Array) -> void:
	# To the guest (redacted for the guest) ...
	net.send_game({
		"t": "sync",
		"events": redact_events(events, 1 - my_idx),
		"state": snapshot_from_state(_gs, 1 - my_idx),
	})
	# ... and to our own view (redacted for us), same code path.
	_apply_sync({
		"events": redact_events(events, my_idx),
		"state": snapshot_from_state(_gs, my_idx),
	})


# --- Sync application (both roles render through this) ---

func _apply_sync(msg: Dictionary) -> void:
	if mirror == null:
		return
	_apply_snapshot_to_mirror(msg.get("state", {}))
	var evs: Array = msg.get("events", [])
	mirror.events = evs.duplicate()
	sync_applied.emit(evs)


func _apply_snapshot_to_mirror(state: Dictionary) -> void:
	if state.is_empty():
		return
	var players_out: Array = []
	for pdata_v in state.get("players", []):
		var pdata: Dictionary = pdata_v
		var hand: Array = []
		for cid in pdata.get("hand", []):
			hand.append(str(cid))
		# A hidden hand arrives empty with a count: pad placeholders so
		# counts read correctly; the ids themselves never leave the host.
		while hand.size() < int(pdata.get("hand_count", 0)):
			hand.append("")
		var deck: Array = []
		for _i in int(pdata.get("deck_count", 0)):
			deck.append("")
		var board: Array = []
		for m in pdata.get("board", []):
			board.append((m as Dictionary).duplicate())
		players_out.append({
			"hp": int(pdata.get("hp", 30)),
			"mana": int(pdata.get("mana", 0)),
			"max_mana": int(pdata.get("max_mana", 0)),
			"deck": deck,
			"decklist": [],
			"hand": hand,
			"board": board,
			"fatigue": int(pdata.get("fatigue", 0)),
			"class": str(pdata.get("class", "")),
			"hero_power_used": bool(pdata.get("hero_power_used", false)),
			"cards_played_this_turn": int(pdata.get("cards_played_this_turn", 0)),
		})
	mirror.players = players_out
	mirror.active = int(state.get("active", 0))
	mirror.winner = int(state.get("winner", -1))
	mirror.turn_count = int(state.get("turn_count", 0))


# --- Snapshot / redaction / hashing (static, testable) ---

static func _canonical_minion(m: Dictionary) -> Dictionary:
	return {
		"uid": int(m.get("uid", -1)),
		"card_id": str(m.get("card_id", "")),
		"name": str(m.get("name", "")),
		"attack": int(m.get("attack", 0)),
		"health": int(m.get("health", 0)),
		"max_health": int(m.get("max_health", 0)),
		"taunt": bool(m.get("taunt", false)),
		"can_attack": bool(m.get("can_attack", false)),
		"sick": bool(m.get("sick", false)),
		"art": str(m.get("art", "")),
	}


# The authoritative state as `recipient` is allowed to see it: their
# own hand in full, the opponent's hand/deck as counts only.
static func snapshot_from_state(gs: GameState, recipient: int) -> Dictionary:
	var players_out: Array = []
	for p in 2:
		var pl: Dictionary = gs.players[p]
		var hand_out: Array = []
		if p == recipient:
			hand_out = (pl["hand"] as Array).duplicate()
		var board_out: Array = []
		for m in pl["board"]:
			board_out.append(_canonical_minion(m))
		players_out.append({
			"hp": int(pl["hp"]),
			"mana": int(pl["mana"]),
			"max_mana": int(pl["max_mana"]),
			"fatigue": int(pl["fatigue"]),
			"class": str(pl["class"]),
			"hero_power_used": bool(pl["hero_power_used"]),
			"cards_played_this_turn": int(pl["cards_played_this_turn"]),
			"hand": hand_out,
			"hand_count": (pl["hand"] as Array).size(),
			"deck_count": (pl["deck"] as Array).size(),
			"board": board_out,
		})
	return {
		"active": gs.active,
		"winner": gs.winner,
		"turn_count": gs.turn_count,
		"players": players_out,
	}


# Strip hidden card ids from events meant for `recipient`: a draw or a
# burn of the OTHER player's card is public as an occurrence, private
# as to which card it was.
static func redact_events(events: Array, recipient: int) -> Array:
	var out: Array = []
	for e in events:
		var ev: Dictionary = e
		var data: Dictionary = (ev.get("data", {}) as Dictionary).duplicate()
		var t: String = str(ev.get("type", ""))
		if (t == "draw" or t == "card_burned") and int(data.get("player", -1)) != recipient:
			data["card_id"] = ""
		out.append({"type": t, "data": data})
	return out


# Hash of everything both players can see (boards, heroes, counts,
# turn state). Two clients in agreement on this hash agree on the
# public state of the match.
static func public_state_hash(state: Dictionary) -> String:
	var pub: Dictionary = {
		"active": int(state.get("active", 0)),
		"winner": int(state.get("winner", -1)),
		"turn_count": int(state.get("turn_count", 0)),
		"players": [],
	}
	for pdata_v in state.get("players", []):
		var pdata: Dictionary = pdata_v
		var board_out: Array = []
		for m in pdata.get("board", []):
			board_out.append(_canonical_minion(m))
		(pub["players"] as Array).append({
			"hp": int(pdata.get("hp", 0)),
			"mana": int(pdata.get("mana", 0)),
			"max_mana": int(pdata.get("max_mana", 0)),
			"fatigue": int(pdata.get("fatigue", 0)),
			"class": str(pdata.get("class", "")),
			"hero_power_used": bool(pdata.get("hero_power_used", false)),
			"cards_played_this_turn": int(pdata.get("cards_played_this_turn", 0)),
			"hand_count": int(pdata.get("hand_count", 0)),
			"deck_count": int(pdata.get("deck_count", 0)),
			"board": board_out,
		})
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(pub).to_utf8_buffer())
	return h.finish().hex_encode()
