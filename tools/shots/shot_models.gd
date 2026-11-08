extends Node3D
# Dev harness: a review sheet of 3D models as they look in game (lite
# hologram, on their pads). Env MODEL_IDS=a,b,c  MODEL_OUT=/path.png  MODEL_COLS=5
func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	var ids: PackedStringArray = OS.get_environment("MODEL_IDS").split(",")
	var cols: int = int(OS.get_environment("MODEL_COLS")) if OS.get_environment("MODEL_COLS") != "" else 5
	var rows: int = int(ceil(float(ids.size()) / cols))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.02, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.7, 0.85)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-25), 0)
	key.light_energy = 1.1
	add_child(key)
	var sx := 3.4
	var sz := 4.2
	for i in ids.size():
		var id: String = ids[i]
		var u := HoloUnit.new()
		var cls: String = str(CardDB.get_card(id).get("class", "neutral"))
		var col: Color = UIKit.CLASS_COLOR.get(cls, Color(1.0, 0.75, 0.35))
		u.setup(id, "model", HoloUnit.Style.MODEL, 1.0, col, col)
		var pos := Vector3((i % cols - (cols - 1) * 0.5) * sx, 0, (i / cols - (rows - 1) * 0.5) * sz)
		u.position = pos
		u.home = pos
		u.scale = Vector3.ONE * 1.22
		add_child(u)
		var l := Label3D.new()
		l.text = "%d. %s" % [i + 1, id.trim_prefix("token_").replace("_", " ")]
		l.font_size = 44
		l.pixel_size = 0.006
		l.outline_size = 12
		l.position = pos + Vector3(0, 0.05, 1.25)
		l.rotation.x = deg_to_rad(-55)
		add_child(l)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var dist: float = max(cols * sx, rows * sz) * 1.15
	cam.position = Vector3(0, dist * 0.7, dist * 0.62)
	cam.look_at(Vector3(0, 0.6, 0.3))
	cam.current = true
	for k in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("MODEL_OUT"))
	get_tree().quit()
