extends Node
class_name LocalRelay

# The relay, built into the game: the hosting player's game runs this, so
# no separate relay.py is needed. Same protocol as server/relay.py (create
# a room, join it, then every message is forwarded verbatim to the paired
# peer; peer_left when one side drops). Over Tailscale the guest connects
# straight to the host's Tailscale name or address on PORT.
#
# One difference: a direct game has exactly one room, so a guest that
# joins with an empty code (or "ANY") is put in the open room.

const PORT := 8765

var _server := TCPServer.new()
var _pending: Array = []      # [{tcp, ws}] still upgrading to WebSocket
var _clients: Array = []      # WebSocketPeer
var _rooms: Dictionary = {}   # code -> host WebSocketPeer (waiting)
var _pairs: Dictionary = {}   # WebSocketPeer -> peer WebSocketPeer
var _codes: Dictionary = {}   # WebSocketPeer -> room code it created
var _rng := RandomNumberGenerator.new()


func start(port: int = PORT, bind: String = "*") -> Error:
	_rng.randomize()
	return _server.listen(port, bind)


func stop() -> void:
	for ws in _clients:
		(ws as WebSocketPeer).close()
	_clients.clear()
	_pending.clear()
	_rooms.clear()
	_pairs.clear()
	_server.stop()


func is_listening() -> bool:
	return _server.is_listening()


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var tcp: StreamPeerTCP = _server.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 20
		ws.accept_stream(tcp)
		_clients.append(ws)
	var gone: Array = []
	for ws in _clients:
		var w: WebSocketPeer = ws
		w.poll()
		var st: int = w.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			gone.append(w)
			continue
		while st == WebSocketPeer.STATE_OPEN and w.get_available_packet_count() > 0:
			_on_text(w, w.get_packet().get_string_from_utf8())
	for w in gone:
		_drop(w)


func _send(w: WebSocketPeer, obj: Dictionary) -> void:
	if w.get_ready_state() == WebSocketPeer.STATE_OPEN:
		w.send_text(JSON.stringify(obj))


func _on_text(w: WebSocketPeer, raw: String) -> void:
	if _pairs.has(w):
		var peer: WebSocketPeer = _pairs[w]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(raw)
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		_send(w, {"t": "error", "msg": "bad json"})
		return
	var msg: Dictionary = parsed
	match str(msg.get("t", "")):
		"create":
			var code := _new_code()
			_rooms[code] = w
			_codes[w] = code
			_send(w, {"t": "room", "code": code})
		"join":
			var want: String = str(msg.get("code", "")).to_upper()
			if (want == "" or want == "ANY") and _rooms.size() == 1:
				want = str(_rooms.keys()[0])
			if not _rooms.has(want):
				_send(w, {"t": "error", "msg": "no game waiting (is the host still in the lobby?)" if _rooms.is_empty() else "no such room"})
				return
			var host: WebSocketPeer = _rooms[want]
			_rooms.erase(want)
			_pairs[w] = host
			_pairs[host] = w
			_send(w, {"t": "joined", "code": want})
			_send(host, {"t": "peer_joined", "code": want})
		_:
			_send(w, {"t": "error", "msg": "not paired"})


func _drop(w: WebSocketPeer) -> void:
	_clients.erase(w)
	if _codes.has(w):
		var code: String = _codes[w]
		if _rooms.get(code) == w:
			_rooms.erase(code)
		_codes.erase(w)
	if _pairs.has(w):
		var peer: WebSocketPeer = _pairs[w]
		_pairs.erase(w)
		_pairs.erase(peer)
		_send(peer, {"t": "peer_left"})


func _new_code() -> String:
	const ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	while true:
		var c := ""
		for i in 5:
			c += ALPHABET[_rng.randi() % ALPHABET.length()]
		if not _rooms.has(c):
			return c
	return ""
