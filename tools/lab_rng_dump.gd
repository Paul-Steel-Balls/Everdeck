extends SceneTree
# Prints Godot RandomNumberGenerator output for a few seeds, so the Lab's
# copy of the generator can be checked bit for bit.
func _init() -> void:
	for s in [0, 1, 12345, 1000003 * 5 + 7919, -7, 9007199254740993]:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var out: Array = []
		for i in 6:
			out.append(r.randi_range(0, i + 1))
		out.append(r.randi_range(2, 5))
		out.append(r.randi())
		for i in 3:
			out.append(PackedFloat64Array([r.randf()]).to_byte_array().hex_encode())
		out.append(r.randi_range(-3, 3))
		out.append(r.randi_range(5, 5))
		print(s, " ", out)
	quit()
