extends Node
# Dev harness: the real match board with one Crew member per new keyword
# state (mechanics pass, wave 1), for a visual check. Env: SHOT_OUT.
# Top row (enemy): Stunt Double, Stage Fright, Backstage, Heckled, Vibe.
# Bottom row (you): Encore, Showstopper, Tip Jar, a "whenever" effect,
# and one with several at once.
var m: Node
var out := "/tmp/shots/keywords"

func _ready() -> void:
	if OS.get_environment("SHOT_OUT") != "":
		out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1920, 1080)
	CardDB.add_test_card({"id": "shot_trig", "name": "Shot Trigger", "class": "grunk", "cost": 2, "type": "minion", "attack": 2, "health": 3, "keywords": [], "text": "At the end of your turn, deal 1 damage to a random enemy.", "flavor": "", "art": "grunk_fuse",
		"triggers": [{"when": "end_of_turn", "effect": "damage", "value": 1, "target": "any_enemy"}]})
	CardDB.add_test_card({"id": "shot_vibe", "name": "Shot Vibe", "class": "barnacle", "cost": 3, "type": "minion", "attack": 3, "health": 3, "keywords": [], "text": "Vibe: Your other Crew have +1 Attack.", "flavor": "", "art": "barnacle_quartermaster",
		"vibe": {"attack": 1, "health": 0, "who": "other_friendly"}})
	m = load("res://main.tscn").instantiate()
	m.hover_cards_enabled = false
	add_child(m)
	await _frames(5)
	m.start_vs_ai("grunk", AIPlayer.build_deck("grunk"), "barnacle")
	var guard := 0
	while (m._gs.active != m._human_idx or m._ai_turn or m._animating) and guard < 6000:
		await _frames(1)
		guard += 1
	var me: int = m._human_idx
	var foe: int = 1 - me
	var gs: GameState = m._gs
	gs.players[me]["board"] = []
	gs.players[foe]["board"] = []
	var mine: Array = [["grunk_pyro", {"windfury": true}], ["grunk_tiny_bomber", {"poison": true}], ["grunk_boombox", {"lifesteal": true}], ["shot_trig", {}], ["grunk_wrecking", {"windfury": true, "lifesteal": true, "shield": true}]]
	var theirs: Array = [["barnacle_mate", {"shield": true}], ["barnacle_helm", {"frozen": 1}], ["barnacle_quartermaster", {"stealth": true}], ["barnacle_boarding", {"silenced": true}], ["shot_vibe", {}]]
	for e in mine:
		gs._summon(me, CardDB.get_card(_id(e[0], "grunk")), false)
		gs.players[me]["board"][-1].merge(e[1], true)
	for e in theirs:
		gs._summon(foe, CardDB.get_card(_id(e[0], "barnacle")), false)
		gs.players[foe]["board"][-1].merge(e[1], true)
	gs._refresh_vibes()
	for x in gs.players[me]["board"]:
		x["can_attack"] = true
		x["sick"] = false
	gs.players[me]["mana"] = 10
	gs.players[me]["max_mana"] = 10
	gs.players[me]["hand"] = []
	m._refresh_match()
	await _frames(90)
	await _shot("board")
	get_tree().quit()

# A real card id: the named one if it exists, else the class's n-th Crew.
func _id(want: String, cls: String) -> String:
	if not CardDB.get_card(want).is_empty():
		return want
	for c in CardDB.CARDS:
		if str(c["class"]) == cls and str(c["type"]) == "minion" and str(c.get("effect", "")) == "":
			return str(c["id"])
	return "angry_squirrel"

func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("%s.png" % name))
