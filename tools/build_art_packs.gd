extends SceneTree
# Headless: godot --headless --path . -s res://tools/build_art_packs.gd -- <out_dir>
# Packs the imported paintings into everdeck_art_<group>.pck files.

const GROUPS: Dictionary = {
	"1": ["hero_", "neutral", "grunk_"],
	"2": ["agatha_", "presto_"],
	"3": ["barnacle_", "reg_", "lar_"],
}


func _init() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	var files: Array = []
	for sub in ["res://art/heroes", "res://art/cards"]:
		for f in DirAccess.get_files_at(sub):
			if f.ends_with(".webp.import"):
				files.append(sub.path_join(f))
	var by_group: Dictionary = {}
	for imp in files:
		var base: String = imp.get_file().trim_suffix(".webp.import")
		var g: String = "1"
		for key in GROUPS:
			for pre in GROUPS[key]:
				if base.begins_with(pre):
					g = key
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(imp)
	for g in by_group:
		var pk := PCKPacker.new()
		var path: String = out_dir.path_join("everdeck_art_%s.pck" % g)
		pk.pck_start(path)
		for imp in by_group[g]:
			var cf := ConfigFile.new()
			cf.load(imp)
			var dest: String = str(cf.get_value("remap", "path", ""))
			pk.add_file(imp, ProjectSettings.globalize_path(imp))
			pk.add_file(dest, ProjectSettings.globalize_path(dest))
		pk.flush()
		print("PACK ", path, " files=", by_group[g].size())
	quit()
