extends Node
# Dev harness: a vs-computer match where the "human" side is also played
# by an AIPlayer (driven through main's normal input entry points), with
# screenshots along the way.
var m: Node
var out := "/tmp/shots"
var shots := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	m = load("res://main.tscn").instantiate()
	add_child(m)
	await _frames(5)
	var hs: Array = CardDB.CLASS_IDS
	var hc: String = hs[randi() % 6]
	var oc: String = hs[randi() % 6]
	if OS.get_environment("SHOT_HERO") != "":
		hc = OS.get_environment("SHOT_HERO")
	if OS.get_environment("SHOT_FOE") != "":
		oc = OS.get_environment("SHOT_FOE")
	var every: int = int(OS.get_environment("SHOT_EVERY")) if OS.get_environment("SHOT_EVERY") != "" else 240
	m.start_vs_ai(hc, AIPlayer.build_deck(hc), oc)
	var me_bot := AIPlayer.new()
	var frames := 0
	while m._gs != null and m._gs.winner == -1 and frames < 30 * 3000:
		await _frames(1)
		frames += 1
		if frames % every == 0 and shots < 12 and DisplayServer.get_name() != "headless":
			await _shot()
		if m._gs.active == m._human_idx and not m._ai_turn and not m._animating:
			var a: Dictionary = me_bot.next_action(m._gs, m._human_idx)
			if a["type"] == "end":
				m._on_end_turn()
			else:
				AIPlayer.apply(m._gs, m._human_idx, a)
				await m._after_action()
	print("RESULT winner=", m._gs.winner if m._gs else -9, " human=", m._human_idx, " turns=", m._gs.turn_count if m._gs else -1, " frames=", frames)
	await _frames(20)
	if DisplayServer.get_name() != "headless":
		await _shot()
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("ai_%02d.png" % shots))
	shots += 1
