extends Control
# Renders every card alone, exactly as the game draws it in hand, one PNG
# per card id. For the art catalog (what each card looks like put
# together). Env: CAT_OUT (folder), CAT_W (card width, default 300),
# CAT_IDS (optional comma list).
func _ready() -> void:
	var out: String = OS.get_environment("CAT_OUT") if OS.get_environment("CAT_OUT") != "" else "/tmp/catalog"
	DirAccess.make_dir_recursive_absolute(out)
	var w: int = int(OS.get_environment("CAT_W")) if OS.get_environment("CAT_W") != "" else 300
	var h: int = int(w * CardFrame.ASPECT)
	var pad := 6
	# Full-size window: the project stretches the UI to the window, so a
	# small window would shrink the card. Crop to the card afterwards.
	get_window().size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.1)
	bg.size = Vector2(get_window().size)
	add_child(bg)
	var ids: Array = []
	if OS.get_environment("CAT_IDS") != "":
		ids = Array(OS.get_environment("CAT_IDS").split(","))
	else:
		for c in CardDB.CARDS:
			ids.append(str(c["id"]))
	for cid in ids:
		var c: Dictionary = CardDB.get_card(cid)
		var b: Button = CardView.make_card_button(c, w, h)
		b.position = Vector2(pad, pad)
		b.size = Vector2(w, h)
		add_child(b)
		for k in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		# Saved whole; the catalog script crops each card to its outline.
		get_viewport().get_texture().get_image().save_png(out.path_join("%s.png" % cid))
		b.queue_free()
	get_tree().quit()
