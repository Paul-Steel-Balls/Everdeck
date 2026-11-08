extends Node
var out := "/tmp/shots/lab"
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 540) if OS.get_environment("LAB_MODE") == "clip" else Vector2i(1280, 720)
	var m: Node = load("res://main.tscn").instantiate()
	add_child(m)
	await _f(3)
	m._show_lab()
	var lab: Node = m.find_child("HoloLab", true, false)
	var mode: String = OS.get_environment("LAB_MODE")
	if mode == "melee":
		lab.arena = int(OS.get_environment("LAB_ARENA"))
		lab._rebuild()
		await _f(8)
		for a in lab._units_root.find_children("*", "StageAct", false, false):
			a._wait = 9999.0
		Engine.time_scale = 0.12
		lab._mine[3].melee(lab._theirs[3])
		for k in int(OS.get_environment("LAB_FRAMES")):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("ml_%03d.png" % k))
		Engine.time_scale = 1.0
		get_tree().quit()
		return
	if mode == "actclip":
		# Slow motion so a software renderer can catch every beat of the act.
		var a2: int = int(OS.get_environment("LAB_ARENA"))
		lab.arena = a2
		lab._rebuild()
		await _f(8)
		var act: Node = lab._units_root.find_children("*", "StageAct", false, false)[0]
		act.first_delay = 9999.0
		act._wait = 9999.0
		Engine.time_scale = 0.12
		act.play()
		for k in int(OS.get_environment("LAB_FRAMES")):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("ac_%03d.png" % k))
		Engine.time_scale = 1.0
		get_tree().quit()
		return
	if mode == "act":
		# Frames of the hero playing with the set piece, per themed arena.
		for a in OS.get_environment("LAB_ARENAS").split(","):
			lab.arena = int(a)
			lab._rebuild()
			for k in 12:
				await _f(16)
				await _shot("act_%s_%02d" % [a, k])
		get_tree().quit()
		return
	if mode == "clip":
		lab.arena = int(OS.get_environment("LAB_ARENA"))
		lab.style = int(OS.get_environment("LAB_STYLE"))
		lab._rebuild()
		await _f(5)
		lab._run(lab._act_demo)
		var n := 0
		while lab._busy or n < 10:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("clip_%04d.png" % n))
			n += 1
			if n > 600:
				break
		get_tree().quit()
		return
	for a in lab.ARENAS.size():
		lab.arena = a
		lab.style = int(OS.get_environment("LAB_STYLE")) if OS.get_environment("LAB_STYLE") != "" else 3
		lab._rebuild()
		await _f(20)
		await _shot("arena%d" % a)
	if OS.get_environment("LAB_ONLY_ARENAS") != "":
		get_tree().quit()
		return
	lab.arena = 0
	lab._rebuild()
	await _f(5)
	lab._run(lab._act_summon)
	for k in [6, 10, 14, 30]:
		await _f(k - (0 if k == 6 else 0))
		await _shot("summon_%02d" % k)
	while lab._busy:
		await _f(1)
	await _f(10)
	lab._run(lab._act_death)
	for k2 in [8, 14, 20, 28]:
		await _f(6)
		await _shot("death_%02d" % k2)
	get_tree().quit()
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
