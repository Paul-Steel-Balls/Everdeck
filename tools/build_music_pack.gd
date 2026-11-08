extends SceneTree
# Headless: godot --headless --path . -s res://tools/build_music_pack.gd -- <out_dir>
# Packs the imported music into everdeck_music.pck.
func _init() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	var pk := PCKPacker.new()
	pk.pck_start(out_dir.path_join("everdeck_music.pck"))
	var n := 0
	for f in DirAccess.get_files_at("res://music"):
		if not f.ends_with(".ogg.import"):
			continue
		var imp: String = "res://music".path_join(f)
		var cf := ConfigFile.new()
		cf.load(imp)
		var dest: String = str(cf.get_value("remap", "path", ""))
		pk.add_file(imp, ProjectSettings.globalize_path(imp))
		pk.add_file(dest, ProjectSettings.globalize_path(dest))
		n += 1
	pk.flush()
	print("MUSIC PACK files=", n)
	quit()
