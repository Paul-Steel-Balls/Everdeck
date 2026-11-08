extends Node
# Autoload. The PC build ships the game code in Everdeck.pck and the
# paintings in separate art packs (everdeck_art_*.pck) so a code update
# is one small file. At startup, mount every art pack found next to the
# game. In the editor the art is already in res://art, so nothing is
# found and nothing happens.

var loaded: Array = []


func _init() -> void:
	for dir in _search_dirs():
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if f.begins_with("everdeck_") and f.ends_with(".pck"):
				var path: String = dir.path_join(f)
				if ProjectSettings.load_resource_pack(path, true):
					loaded.append(path)
		if not loaded.is_empty():
			return


func _search_dirs() -> Array:
	var dirs: Array = []
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--main-pack" and i + 1 < args.size():
			dirs.append(args[i + 1].get_base_dir())
		elif a.begins_with("--main-pack="):
			dirs.append(a.trim_prefix("--main-pack=").get_base_dir())
	# The launcher .bat changes into the game folder first, so the working
	# directory is the most reliable place to look.
	var cwd := DirAccess.open(".")
	if cwd != null:
		dirs.append(cwd.get_current_dir())
	dirs.append(OS.get_executable_path().get_base_dir())
	return dirs
