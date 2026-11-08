extends Node
var out := "/tmp/shots"
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var m: Node = load("res://main.tscn").instantiate()
	add_child(m)
	await _f(3)
	m._show_deck_builder("barnacle", "random")
	await _f(20)
	await _shot("db_1")
	var db: Node = m.find_child("DeckBuilder", true, false)
	var ids: Array = db._tiles.keys()
	for i in 5:
		db._add(ids[i * 3], db._tiles[ids[i * 3]])
	db._add(ids[0], db._tiles[ids[0]])
	db._hover(db._tiles[ids[7]], true)
	await _f(6)
	await _shot("db_2")
	db._autofill()
	db._set_cost_filter("3")
	await _f(30)
	await _shot("db_3")
	get_tree().quit()
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
