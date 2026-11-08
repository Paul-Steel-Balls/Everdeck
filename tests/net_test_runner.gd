extends Node

# Sprint MP-1 net test: one instance of this scene runs as the HOST,
# another as the GUEST (see tests/run_net_test.sh). They connect
# through a locally running relay, complete the commit/reveal/
# match_start handshake, then play scripted opening turns through
# NetMatch (real engine on the host, mirror on the guest):
#   my turn 1: play the first playable no-target card (if any), end turn
#   my turn 2: end turn
# When turn_count >= 5 (both players have had two turns) each side
# writes a result file with the public-state hash of its mirror; the
# harness asserts the hashes match — i.e. both sides agree on the
# board state — and that hidden hands stayed hidden (placeholders).

var _role: String = ""
var _relay: String = ""
var _code_file: String = ""
var _result_file: String = ""
var _nm: NetMatch = null
var _my_idx: int = -1
var _started_msec: int = 0
var _joined: bool = false
var _sync_count: int = 0
var _last_acted_sync: int = -1
var _acted_this_turn: bool = false
var _play_attempted: bool = false
var _finished: bool = false
var _cooldown: float = 0.0

const FINISH_TURN_COUNT: int = 5
const TIMEOUT_MS: int = 120000


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1]
	_role = str(args.get("role", ""))
	_relay = str(args.get("relay", NetClient.RELAY_URL))
	_code_file = str(args.get("code-file", ""))
	_result_file = str(args.get("result-file", ""))
	if _role != "host" and _role != "guest":
		_finish("failed", "missing --role=host|guest")
		return
	_nm = NetMatch.new()
	add_child(_nm)
	_nm.room_ready.connect(_on_room_ready)
	_nm.match_started.connect(_on_match_started)
	_nm.sync_applied.connect(_on_sync)
	_nm.failed.connect(func(reason: String) -> void: _finish("failed", reason))
	_nm.action_rejected.connect(func(reason: String) -> void:
		# A rejected scripted action is not fatal: fall through to
		# ending the turn so the script cannot wedge.
		_play_attempted = true
	)
	if _role == "host":
		_nm.host_game(_relay, _make_deck("grunk"), "grunk")
	# Guest waits for the code file in _process.


static func _make_deck(class_id: String) -> Array:
	var deck: Array = []
	for c in CardDB.cards_for_class(class_id):
		for _k in CardDB.max_copies(c):
			if deck.size() < GameState.DECK_SIZE:
				deck.append(str(c["id"]))
	return deck


func _on_room_ready(code: String) -> void:
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	if f != null:
		f.store_string(code)
		f.close()


func _on_match_started(idx: int) -> void:
	_my_idx = idx


var _cards_played_seen: int = 0


func _on_sync(events: Array) -> void:
	_sync_count += 1
	for e in events:
		if str((e as Dictionary).get("type", "")) == "card_played":
			_cards_played_seen += 1


func _process(delta: float) -> void:
	if _finished:
		return
	if Time.get_ticks_msec() - _started_msec > TIMEOUT_MS:
		_finish("failed", "timeout")
		return
	if _role == "guest" and not _joined:
		if _code_file != "" and FileAccess.file_exists(_code_file):
			var f := FileAccess.open(_code_file, FileAccess.READ)
			var code: String = f.get_as_text().strip_edges()
			f.close()
			if code.length() >= 4:
				_joined = true
				_nm.join_game(_relay, code, _make_deck("agatha"), "agatha")
		return
	if _my_idx == -1 or _nm.mirror == null or _nm.mirror.players.size() < 2:
		return
	var m: GameState = _nm.mirror
	if m.winner != -1 or m.turn_count >= FINISH_TURN_COUNT:
		_finish("done", "")
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if m.active != _my_idx:
		_acted_this_turn = false
		_play_attempted = false
		_last_acted_sync = _sync_count
		return
	if _sync_count == _last_acted_sync:
		return  # waiting for the sync our last action produces
	# It's my turn and a fresh sync has landed since my last action.
	if not _play_attempted:
		_play_attempted = true
		_last_acted_sync = _sync_count
		_cooldown = 0.4
		if not _acted_this_turn:
			_acted_this_turn = true
			_try_play_card()
		return
	# Play step done: end the turn.
	_last_acted_sync = _sync_count
	_cooldown = 0.4
	_nm.submit_action({"act": "end_turn"})


func _try_play_card() -> void:
	var m: GameState = _nm.mirror
	var hand: Array = m.players[_my_idx]["hand"]
	for i in hand.size():
		if not m.can_play(_my_idx, i):
			continue
		var card: Dictionary = CardDB.get_card(str(hand[i]))
		if card.is_empty():
			continue
		if m.card_target_options(_my_idx, card).is_empty():
			_nm.submit_action({"act": "play_card", "hand_idx": i, "target": {}})
			return
	# Nothing playable without a target: end via the normal step flow.


func _finish(status: String, reason: String) -> void:
	if _finished:
		return
	_finished = true
	var out: Dictionary = {"role": _role, "status": status, "reason": reason}
	if status == "done" and _nm != null and _nm.mirror != null:
		var snap: Dictionary = NetMatch.snapshot_from_state(_nm.mirror, _my_idx)
		out["hash"] = NetMatch.public_state_hash(snap)
		out["turn_count"] = _nm.mirror.turn_count
		out["winner"] = _nm.mirror.winner
		out["cards_played_seen"] = _cards_played_seen
		# Hidden-information check: the opponent's hand in my mirror
		# must be all placeholders; my own hand must be real ids.
		var opp_hand: Array = _nm.mirror.players[1 - _my_idx]["hand"]
		var hidden_ok: bool = true
		for cid in opp_hand:
			if str(cid) != "":
				hidden_ok = false
		out["hidden_ok"] = hidden_ok
		var my_hand: Array = _nm.mirror.players[_my_idx]["hand"]
		var mine_ok: bool = true
		for cid in my_hand:
			if str(cid) == "":
				mine_ok = false
		out["own_hand_ok"] = mine_ok
	var f := FileAccess.open(_result_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))
		f.close()
	print("NETTEST ", _role, " ", status, " ", reason)
	get_tree().quit(0 if status == "done" else 1)
