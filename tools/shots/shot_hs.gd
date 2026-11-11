extends Node
var out := OS.get_environment("SHOT_OUT") if OS.get_environment("SHOT_OUT") != "" else "/tmp/shots"
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	var m: Node = load("res://main.tscn").instantiate()
	add_child(m)
	await _f(3)
	m._show_hero_select()
	var hs: Node = m.find_child("HeroSelect", true, false)
	hs._select("grunk", false)
	await _f(45)
	await _shot("hs_1")
	hs._select("larry", false)
	await _f(8)
	await _shot("hs_2_switch")
	await _f(40)
	await _shot("hs_3")
	hs._select("reginald", false)
	hs._cycle_opp(1)
	hs._set_level(2, true)
	await _f(45)
	await _shot("hs_4")
	hs._on_lock()
	await _f(20)
	await _shot("hs_5_lock")
	get_tree().quit()
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
