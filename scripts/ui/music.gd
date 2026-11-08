extends Node
# Autoload "Music": one looping track per area of the game, crossfading
# when the area changes. Tracks ship in everdeck_music.pck (PC build) or
# res://music (editor). Missing tracks are skipped silently.

const TRACKS: Dictionary = {
	"menu": "res://music/menu_dreamy_flashback.ogg",
	"select": "res://music/select_at_launch.ogg",
	"battle": "res://music/battle_clash_defiant.ogg",
}
const FADE_S: float = 1.2
const VOLUME_DB: float = -6.0

var current: String = ""
var _players: Array = []
var _active: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func play(key: String) -> void:
	if key == current:
		return
	current = key
	var path: String = str(TRACKS.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var nxt: AudioStreamPlayer = _players[_active]
	nxt.stream = stream
	nxt.volume_db = -40.0
	nxt.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nxt, "volume_db", VOLUME_DB, FADE_S)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE_S)
		tw.chain().tween_callback(old.stop)


func stop() -> void:
	current = ""
	for p in _players:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -60.0, FADE_S)
		tw.tween_callback(p.stop)
