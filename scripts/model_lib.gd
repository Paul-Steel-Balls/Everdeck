extends RefCounted
class_name ModelLib

# The 3D minion models (res://models3d/<card_id>.glb). The folder is not
# imported by the editor (.gdignore); the GLB files ship as-is in their own
# packs (everdeck_models_NN.pck) and are parsed at runtime on first use, then
# cached so each card's model is only decoded once per session.

const DIR := "res://models3d/"

static var _cache: Dictionary = {}   # card_id -> Node3D template (or null)


static func has_model(card_id: String) -> bool:
	return FileAccess.file_exists(DIR + card_id + ".glb")


# A fresh copy of the card's model, or null when it has none. Meshes and
# textures are shared between copies; materials are set by the caller.
# Parse a model into the cache ahead of time (no-op if already there), so
# its first appearance mid-match doesn't stall a frame.
static func preload_model(card_id: String) -> void:
	if not _cache.has(card_id) and has_model(card_id):
		_cache[card_id] = _load(card_id)


static func is_cached(card_id: String) -> bool:
	return _cache.has(card_id)


static func instance(card_id: String) -> Node3D:
	if not _cache.has(card_id):
		_cache[card_id] = _load(card_id)
	var tpl: Node3D = _cache[card_id]
	return null if tpl == null else tpl.duplicate() as Node3D


static func _load(card_id: String) -> Node3D:
	var path: String = DIR + card_id + ".glb"
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		push_warning("ModelLib: could not read " + path)
		return null
	return doc.generate_scene(state) as Node3D


# Meshes of a model, with their combined bounding box in the model's space.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var bb: AABB = m.transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return box
