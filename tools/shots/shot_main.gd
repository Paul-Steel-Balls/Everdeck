extends Node
# Screenshot harness (dev only): drives main.tscn through title -> class
# select -> a match with some minions down, saving PNGs to user://shots.

var m: Node
var out_dir: String = ""

func _ready() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	m = load("res://main.tscn").instantiate()
	add_child(m)
	await _wait(20)
	await _shot("01_title")
	m._on_play()
	await _wait(10)
	await _shot("02_class_select")
	var cls: Array = ["agatha", "larry"]
	m._decks = [_deck(cls[0]), _deck(cls[1])]
	m._classes = cls
	m._start_match()
	m._on_interstitial_ready(0)
	await _wait(30)
	await _shot("03_match_start")
	# Give both players mana and drop a few minions to see the board.
	for p in 2:
		m._gs.players[p]["mana"] = 10
		m._gs.players[p]["max_mana"] = 10
	for p in [0, 1]:
		m._gs.active = p
		var played := 0
		var i := 0
		while played < 3 and i < m._gs.players[p]["hand"].size():
			var cid: String = str(m._gs.players[p]["hand"][i])
			var card: Dictionary = CardDB.get_card(cid)
			if card.get("type", "") == "minion" and m._gs.play_card(p, i):
				played += 1
			else:
				i += 1
	m._gs.active = 0
	m._after_action()
	await _wait(120)
	await _shot("04_board")
	var hand: Array = m._gs.players[0]["hand"]
	if hand.size() > 0:
		m._show_magnify(CardDB.get_card(str(hand[0])))
		await _wait(10)
		await _shot("05_magnify")
	get_tree().quit()

func _deck(cls: String) -> Array:
	var d: Array = []
	for c in CardDB.cards_for_class(cls):
		if c["type"] == "minion" and d.size() < 30:
			d.append(c["id"])
	for c in CardDB.cards_for_class("neutral"):
		if d.size() < 30:
			d.append(c["id"])
	return d

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT ", name)
