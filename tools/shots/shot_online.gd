extends Node
# Dev harness: one side of a real online match. Run two copies, one with
# SHOT_ROLE=host and one with SHOT_ROLE=guest; they meet over the game's
# built-in relay on 127.0.0.1 exactly as two PCs would over Tailscale.
# Each side plays a Crew card on its turn, ends the turn, and saves
# screenshots of what it sees. Env: SHOT_ROLE, SHOT_HERO, SHOT_OUT.
var m: Node
var out := "/tmp/shots/online"
var role := "host"

func _ready() -> void:
	role = OS.get_environment("SHOT_ROLE") if OS.get_environment("SHOT_ROLE") != "" else "host"
	out = (OS.get_environment("SHOT_OUT") if OS.get_environment("SHOT_OUT") != "" else out).path_join(role)
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	m = load("res://main.tscn").instantiate()
	add_child(m)
	await _frames(5)
	var hc: String = OS.get_environment("SHOT_HERO") if OS.get_environment("SHOT_HERO") != "" else ("grunk" if role == "host" else "agatha")
	m._decks = [AIPlayer.build_deck(hc), []]
	m._classes = [hc, ""]
	m._online = true
	m._online_role = role
	m._online_code = ""
	m._online_url = "ws://127.0.0.1:%d" % LocalRelay.PORT
	if role == "guest":
		await _secs(3.0)
	m._start_online_connection()
	await _secs(1.5)
	await _shot("0_lobby")
	var t0 := Time.get_ticks_msec()
	while m._screen != m.Screen.MATCH and Time.get_ticks_msec() - t0 < 30000:
		await _frames(1)
	if m._screen != m.Screen.MATCH:
		print("SHOT: never reached the match")
		get_tree().quit()
		return
	await _settle()
	await _secs(2.0)
	await _shot("1_start")
	# Three turns each: on my turn play the first Crew card I can, then end.
	var mine := 0
	t0 = Time.get_ticks_msec()
	while mine < 3 and Time.get_ticks_msec() - t0 < 120000:
		await _frames(1)
		if m._gs == null or m._gs.winner != -1:
			break
		if m._gs.active != m._human_idx or m._animating or m._awaiting_sync:
			continue
		await _secs(0.8)
		var me: int = m._human_idx
		for i in m._gs.players[me]["hand"].size():
			var card: Dictionary = CardDB.get_card(str(m._gs.players[me]["hand"][i]))
			if m._gs.can_play(me, i) and str(card.get("type", "")) == "minion" and str(card.get("target", "none")) == "none":
				m._do_play(i, {})
				break
		await _secs(0.5)
		await _settle()
		await _secs(1.0)
		await _shot("2_my_turn_%d" % mine)
		m._on_end_turn()
		await _secs(1.5)
		await _shot("3_their_turn_%d" % mine)
		mine += 1
	await _secs(3.0)
	await _settle()
	await _shot("4_end")
	print("SHOT: done, turn %d" % m._gs.turn_count)
	m._teardown_online()
	await _frames(5)
	get_tree().quit()


func _settle() -> void:
	await _frames(2)
	var g := 0
	while m._animating and g < 900:
		await _frames(1)
		g += 1


func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("%s.png" % name))
