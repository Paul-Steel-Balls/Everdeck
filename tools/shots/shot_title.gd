extends Node
# Dev screenshot harness for the title screen at several moments.
func _ready() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	if out.is_empty():
		out = "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	var m: Node = load("res://main.tscn").instantiate()
	add_child(m)
	await get_tree().process_frame
	var ts: Control = m.find_child("TitleScreen", true, false)
	print("MAIN size ", m.size, " TITLE size ", ts.size, " anchors ", ts.anchor_right, " off ", ts.offset_right)
	# Run with --fixed-fps 30 so time advances per frame, not wall clock.
	var frame := 0
	for t in [0.35, 3.0, 9.5, 16.0]:
		while frame < int(t * 30.0):
			await get_tree().process_frame
			frame += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("title_%04.1f.png" % t))
		print("SHOT ", t)
	var tm: Node = m.find_child("TitleScreen", true, false)
	var b: Control = tm.buttons["play"]
	b.emit_signal("mouse_entered")
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("title_hover.png"))
	b.emit_signal("pressed")
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("title_wipe.png"))
	get_tree().quit()
