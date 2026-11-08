extends Node
class_name NetClient

# Sprint MP-1: WebSocket transport to the Everdeck relay server.
# Deliberately NOT an autoload: main.gd (and the net test scene) own an
# instance, so the local game and the existing test suite never touch
# the network unless online play is explicitly started.
#
# Relay protocol (see server/relay.py): connect, then {"t":"create"}
# or {"t":"join","code":...}; once paired, game messages pass through
# verbatim. Relay control messages are consumed here and surfaced as
# signals; everything else is emitted as game_message.

signal connected
signal connect_failed(reason: String)
signal disconnected
signal room_created(code: String)
signal join_failed(reason: String)
signal joined(code: String)
signal peer_joined
signal peer_left
signal game_message(msg: Dictionary)

# Default relay address. Point this at any host running relay.py; the
# Play Online screen also has an editable field seeded from this.
const RELAY_URL: String = "ws://127.0.0.1:8765"

const _RELAY_TYPES: Array = ["room", "joined", "error", "peer_joined", "peer_left"]

var _ws := WebSocketPeer.new()
var _state: int = WebSocketPeer.STATE_CLOSED
var _open: bool = false


func connect_to_relay(url: String) -> void:
	_ws = WebSocketPeer.new()
	_open = false
	var err: Error = _ws.connect_to_url(url)
	if err != OK:
		connect_failed.emit("connect_to_url failed: %s" % err)


func create_room() -> void:
	_send({"t": "create"})


func join_room(code: String) -> void:
	_send({"t": "join", "code": code.to_upper()})


# Send one game message (any Dictionary) to the paired peer, verbatim.
func send_game(msg: Dictionary) -> void:
	_send(msg)


func close() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN or _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_ws.close()
	_open = false


func is_open() -> bool:
	return _open


func _send(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _process(_delta: float) -> void:
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st != _state:
		_state = st
		match st:
			WebSocketPeer.STATE_OPEN:
				_open = true
				connected.emit()
			WebSocketPeer.STATE_CLOSED:
				var was_open: bool = _open
				_open = false
				if was_open:
					disconnected.emit()
				else:
					connect_failed.emit("connection closed (code %d)" % _ws.get_close_code())
	while _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and _ws.get_available_packet_count() > 0:
		var text: String = _ws.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var msg: Dictionary = parsed
		var t: String = str(msg.get("t", ""))
		if t in _RELAY_TYPES:
			match t:
				"room":
					room_created.emit(str(msg.get("code", "")))
				"joined":
					joined.emit(str(msg.get("code", "")))
				"error":
					join_failed.emit(str(msg.get("msg", "relay error")))
				"peer_joined":
					peer_joined.emit()
				"peer_left":
					peer_left.emit()
		else:
			game_message.emit(msg)
