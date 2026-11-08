extends Node
# Dev harness: the real match board, staged — full rows, the turn fuse,
# then an attack, a summon and a death captured frame by frame (slowed
# down with time_scale) for review. Env: SHOT_HERO, SHOT_FOE, SHOT_OUT.
var m: Node
var out := "/tmp/shots/battle"
var n := 0

func _ready() -> void:
	if OS.get_environment("SHOT_OUT") != "":
		out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	m = load("res://main.tscn").instantiate()
	add_child(m)
	await _frames(5)
	var hc: String = OS.get_environment("SHOT_HERO") if OS.get_environment("SHOT_HERO") != "" else "grunk"
	var oc: String = OS.get_environment("SHOT_FOE") if OS.get_environment("SHOT_FOE") != "" else "barnacle"
	m.start_vs_ai(hc, AIPlayer.build_deck(hc), oc)
	var guard := 0
	while (m._gs.active != m._human_idx or m._ai_turn or m._animating) and guard < 6000:
		await _frames(1)
		guard += 1
	var me: int = m._human_idx
	var foe: int = 1 - me
	var gs: GameState = m._gs
	gs.players[me]["board"] = []
	gs.players[foe]["board"] = []
	var nb: int = int(OS.get_environment("SHOT_N")) if OS.get_environment("SHOT_N") != "" else 5
	for i in nb:
		gs.players[me]["board"].append(_minion(gs, _crew(hc, 7)[i % _crew(hc, 7).size()], true))
	for i in nb:
		gs.players[foe]["board"].append(_minion(gs, _crew(oc, 7)[i % _crew(oc, 7).size()], false))
	gs.players[me]["board"][1]["attack"] = 9
	gs.players[me]["hand"] = [_crew(hc, 7)[6]]
	if OS.get_environment("SHOT_FULLHAND") != "":
		var hand: Array = []
		for c in CardDB.CARDS:
			if str(c["class"]) == hc and hand.size() < 6:
				hand.append(c["id"])
		hand.append("coin")
		gs.players[me]["hand"] = hand
	gs.players[me]["mana"] = 10
	gs.players[me]["max_mana"] = 10
	gs.players[foe]["mana"] = 4
	gs.players[foe]["max_mana"] = 6
	m._refresh_match()
	if OS.get_environment("SHOT_HOVER") != "":
		await _frames(40)
		gs.players[foe]["board"][1]["health"] = 1
		m._refresh_match()
		await _frames(4)
		m._show_hover_card(int(gs.players[foe]["board"][1]["uid"]), foe)
		await _frames(10)
		await _shot("hover_enemy")
		m._clear_hover_card()
		m._show_hover_card(int(gs.players[me]["board"][5]["uid"]), me)
		await _frames(10)
		await _shot("hover_mine")
		get_tree().quit()
		return
	if OS.get_environment("SHOT_ARROW") != "":
		await _frames(40)
		var a := TargetArrow.new()
		m.add_child(a)
		var src: Vector2 = m._target_screen_pos({"kind": "minion", "player": me, "board_idx": 1})
		var tgt: Vector2 = m._target_screen_pos({"kind": "minion", "player": foe, "board_idx": 4})
		var boss: Vector2 = m._target_screen_pos({"kind": "hero", "player": foe, "board_idx": -1})
		var pv := [{"pos": tgt + Vector2(0, -34), "text": "-9", "lethal": true}, {"pos": src + Vector2(0, -38), "text": "-2", "lethal": true}]
		a.queue_free()
		# The real drag path: my 9-attack Crew member aimed at enemy #4.
		var tl: Array = [{"kind": "hero", "player": foe, "board_idx": -1}]
		for i in gs.players[foe]["board"].size():
			tl.append({"kind": "minion", "player": foe, "board_idx": i})
		m._drag = {"ctx": {"kind": "my_minion", "board_idx": 1, "uid": int(gs.players[me]["board"][1]["uid"])}, "targets": tl, "snapped": {}}
		m._update_target_arrow(src, tgt + Vector2(6, 4))
		await _frames(10)
		await _shot("arrow_real")
		m._hide_arrow()
		m._drag = {}
		get_tree().quit()
		return
		for st in [TargetArrow.Style.CHEVRON, TargetArrow.Style.BEAM]:
			a.style = st
			a.previews = pv
			a.aim(src, tgt, TargetArrow.State.LOCKED, "attack")
			await _frames(12)
			await _shot("arrow_%d_locked" % st)
			a.previews = []
			a.aim(src, src + Vector2(160, -120), TargetArrow.State.AIMING, "attack")
			await _frames(4)
			await _shot("arrow_%d_aiming" % st)
			a.reason = "A Taunt is in the way"
			a.aim(src, boss, TargetArrow.State.BLOCKED, "attack")
			await _frames(4)
			await _shot("arrow_%d_blocked" % st)
		get_tree().quit()
		return
	if OS.get_environment("SHOT_EMOTE") != "":
		await _frames(40)
		m._show_emote_menu()
		await _frames(6)
		await _shot("emote_menu")
		m._dismiss_emote_menu()
		m._send_emote("bring")
		m._show_emote(foe, "whoops")
		await _frames(14)
		await _shot("emote_mine")
		await _frames(6)
		await _shot("emote_both")
		get_tree().quit()
		return
	if OS.get_environment("SHOT_MOVIE") != "":
		await _movie(gs, me, foe)
		get_tree().quit()
		return
	await _frames(40)
	await _shot("board")
	m._turn_timer.left = 9.0
	await _frames(25)
	await _shot("fuse")
	m._turn_timer.left = 90.0
	if OS.get_environment("SHOT_QUICK") != "":
		get_tree().quit()
		return
	Engine.time_scale = 0.15
	gs.attack(me, 1, {"kind": "minion", "player": foe, "board_idx": 2})
	m._after_action()
	for i in 26:
		await _frames(2)
		await _shot("atk_%02d" % i)
	while m._animating:
		await _frames(1)
	await _frames(10)
	gs.play_card(me, 0, {})
	m._after_action()
	for j in 14:
		await _frames(2)
		await _shot("sum_%02d" % j)
	Engine.time_scale = 1.0
	get_tree().quit()

# Movie mode (run with --write-movie --fixed-fps 60): real-speed play, every
# frame recorded at exactly 1/60 s, for judging smoothness.
func _movie(gs: GameState, me: int, foe: int) -> void:
	await _frames(70)
	gs.attack(me, 1, {"kind": "minion", "player": foe, "board_idx": 2})
	m._after_action()
	await _settle()
	await _frames(20)
	gs.play_card(me, 0, {})
	m._after_action()
	await _settle()
	await _frames(20)
	gs.attack(me, 3, {"kind": "hero", "player": foe, "board_idx": -1})
	m._after_action()
	await _settle()
	await _frames(40)


func _settle() -> void:
	await _frames(2)
	var g := 0
	while m._animating and g < 900:
		await _frames(1)
		g += 1


func _crew(cls: String, k: int) -> Array:
	var ids: Array = []
	for c in CardDB.CARDS:
		if str(c["class"]) == cls and str(c["type"]) == "minion" and c["keywords"].is_empty() and str(c.get("effect", "")) == "" and ModelLib.has_model(str(c["id"])):
			ids.append(c["id"])
	return ids.slice(0, k)

func _minion(gs: GameState, card_id: String, ready: bool) -> Dictionary:
	var c: Dictionary = CardDB.get_card(card_id)
	var mm := {"card_id": c["id"], "name": c["name"], "attack": c["attack"], "health": c["health"], "max_health": c["health"], "taunt": false, "can_attack": ready, "sick": not ready}
	gs.uid_for(mm)
	return mm

func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("%s.png" % name))
	n += 1
