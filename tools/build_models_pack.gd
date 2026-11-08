extends SceneTree
# Headless: godot --headless --path . -s res://tools/build_models_pack.gd -- <out_dir>
# Packs the 3D models (raw .glb, parsed at runtime by ModelLib) into
# everdeck_models_NN.pck files, each kept under PACK_LIMIT so every one can
# be sent to the PC on its own. ArtPacks mounts every everdeck_*.pck it
# finds next to the game, so the split is invisible to the game.
# models3d/ has a .gdignore, so the editor never imports them and the code
# export never includes them.

const PACK_LIMIT := 20 * 1024 * 1024


func _init() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	var files: Array = []
	for f in DirAccess.get_files_at("res://models3d"):
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	var pack_i := 0
	var pk: PCKPacker = null
	var used := 0
	var n := 0
	for f in files:
		var p: String = "res://models3d".path_join(f)
		var sz: int = FileAccess.get_file_as_bytes(p).size()
		if pk == null or used + sz > PACK_LIMIT:
			if pk != null:
				pk.flush()
			pack_i += 1
			pk = PCKPacker.new()
			pk.pck_start(out_dir.path_join("everdeck_models_%02d.pck" % pack_i))
			used = 0
		pk.add_file(p, ProjectSettings.globalize_path(p))
		used += sz
		n += 1
	if pk != null:
		pk.flush()
	print("MODELS PACKS packs=", pack_i, " files=", n)
	quit()
