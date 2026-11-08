extends Control
# Dev harness: END TURN and Signature Move buttons in every state.
func _ready() -> void:
	get_window().size = Vector2i(1000, 420)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.07, 0.2)
	bg.size = Vector2(1000, 420)
	add_child(bg)
	var x := 30.0
	for l in [EndTurnButton.Look.READY, EndTurnButton.Look.DONE, EndTurnButton.Look.WAITING]:
		var b := EndTurnButton.new()
		b.position = Vector2(x, 30)
		add_child(b)
		b.set_look(l)
		x += 200
	x = 30.0
	var decks := ["grunk", "agatha", "presto", "barnacle", "reginald", "larry"]
	for i in 6:
		var s := SignatureButton.new()
		s.position = Vector2(x, 180)
		add_child(s)
		s.setup(decks[i], UIKit.CLASS_COLOR[decks[i]], 2, SignatureButton.Look.READY if i < 4 else (SignatureButton.Look.SHORT if i == 4 else SignatureButton.Look.USED))
		x += 130
	for k in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shots/buttons.png")
	get_tree().quit()
