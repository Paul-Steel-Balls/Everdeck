extends Control
# Dev harness: card frame options side by side (current / GILDED / HOLO).
# Env CARD_IDS=a,b,c  CARD_OUT=/path.png  CARD_W=200
func _ready() -> void:
	var ids: PackedStringArray = (OS.get_environment("CARD_IDS") if OS.get_environment("CARD_IDS") != "" else "grunk_dan,fireball,grunk_king,coin").split(",")
	var w: float = float(OS.get_environment("CARD_W")) if OS.get_environment("CARD_W") != "" else 200.0
	var h: float = w * CardFrame.ASPECT
	var gap := 26.0
	var label_w := 120.0
	get_window().size = Vector2i(int(label_w + ids.size() * (w + gap) + gap), int(4 * (h + gap + 10) + gap))
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.1)
	bg.size = Vector2(get_window().size)
	add_child(bg)
	var rows := ["NOW", "DECK\nBUILDER", "A  GILDED", "B  HOLO"]
	for r in 4:
		var y: float = gap + r * (h + gap + 10)
		var l := UIKit.label(rows[r], 20, UIKit.GOLD, UIKit.FONT_DISPLAY_PATH)
		l.position = Vector2(14, y + h * 0.45)
		add_child(l)
		for i in ids.size():
			var c: Dictionary = CardDB.get_card(ids[i]) if ids[i] != "coin" else CardDB.COIN
			var x: float = label_w + i * (w + gap)
			if r == 0:
				var b: Button = CardView.make_card_button(c, int(w), int(h))
				b.position = Vector2(x, y)
				b.size = Vector2(w, h)
				add_child(b)
			elif r == 1:
				var cf := CardFace.make(c, Vector2(w, w * 1.4))
				cf.position = Vector2(x, y)
				add_child(cf)
			else:
				var f := CardFrame.new()
				add_child(f)
				f.position = Vector2(x, y)
				f.setup(c, CardFrame.Look.GILDED if r == 2 else CardFrame.Look.HOLO, w)
	for k in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("CARD_OUT") if OS.get_environment("CARD_OUT") != "" else "/tmp/shots/cards.png")
	get_tree().quit()
