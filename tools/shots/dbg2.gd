extends Node
func _ready():
	get_window().size = Vector2i(1280, 720)
	var m: Node = load("res://main.tscn").instantiate()
	add_child(m)
	var ts = m.find_child("TitleScreen", true, false)
	var dot := ColorRect.new()
	dot.color = Color(0, 1, 0)
	dot.size = Vector2(10, 10)
	ts.add_child(dot)
	var names = ["grunk","agatha","presto","barnacle","reginald","larry"]
	for h in 6:
		for i in 75:
			await get_tree().process_frame
			dot.position = ts._mouth_point() - Vector2(5, 5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/shots/mouth_%d.png" % h)
		for i in 195 - 75:
			await get_tree().process_frame
	get_tree().quit()
