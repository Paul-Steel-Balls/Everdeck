extends SceneTree
# Exports everything the Lab (lab/, the fast text-only simulator) needs
# from the game: every card as the game loads it, the tokens, the Lucky
# Penny, the Signature Moves and the payoff cap. Run after any card or
# Signature Move change:
#   godot --headless --path . -s res://tools/lab_export.gd
# Writes res://lab/data/rules.json.
func _init() -> void:
	var out := {
		"cards": CardDB.CARDS,
		"tokens": {"squireling": CardDB.TOKEN_SQUIRELING, "deckhand": CardDB.TOKEN_DECKHAND, "token": CardDB.TOKEN_GENERIC, "coin": CardDB.COIN},
		"hero_powers": CardDB.HERO_POWERS,
		"classes": CardDB.CLASS_IDS,
		"payoff_cap": GameState.payoff_cap,
		"version": ProjectSettings.get_setting("application/config/version", ""),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://lab/data"))
	var f := FileAccess.open("res://lab/data/rules.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false))
	f.close()
	print("lab export: %d cards" % CardDB.CARDS.size())
	quit()
