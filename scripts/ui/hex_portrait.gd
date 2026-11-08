extends Control
class_name HexPortrait

# A hexagon-cropped hero face with a class-colored rim. Used as the
# roster buttons on hero select. Hover lifts and brightens it; the
# selected one gets a pulsing ring.

signal picked(class_id: String)

var class_id: String = ""
var selected: bool = false
var _hover: bool = false
var _t: float = 0.0
var _tex: Texture2D


func setup(cls: String) -> void:
	class_id = cls
	_tex = UIKit.hero_texture(cls)
	custom_minimum_size = Vector2(118, 128)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		_bump(1.1))
	mouse_exited.connect(func() -> void:
		_hover = false
		_bump(1.0))
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _bump(s: float) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(s, s), 0.14)


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		picked.emit(class_id)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if selected or _hover:
		queue_redraw()


func _hex(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * i - 90.0)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.46
	var col: Color = UIKit.CLASS_COLOR.get(class_id, Color.WHITE)
	if selected:
		var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
		draw_colored_polygon(_hex(c, r + 10.0 + pulse * 4.0), Color(col.r, col.g, col.b, 0.35 + 0.25 * pulse))
	# Ink outline, then the face texture, then the class rim.
	draw_colored_polygon(_hex(c + Vector2(4, 5), r + 5.0), Color(0, 0, 0, 0.5))
	draw_colored_polygon(_hex(c, r + 5.0), UIKit.INK)
	if _tex != null:
		var face: Vector3 = UIKit.HERO_FACE.get(class_id, Vector3(0.5, 0.35, 0.25))
		var ts: Vector2 = _tex.get_size()
		var fr_px: float = face.z * ts.x
		var fc_px: Vector2 = Vector2(face.x * ts.x, face.y * ts.y)
		var pts: PackedVector2Array = _hex(c, r)
		var uvs := PackedVector2Array()
		for p in pts:
			var rel: Vector2 = (p - c) / r
			uvs.append((fc_px + rel * fr_px) / ts)
		var shade: Color = Color(1, 1, 1) if (selected or _hover) else Color(0.62, 0.62, 0.7)
		var cols := PackedColorArray()
		for _i in pts.size():
			cols.append(shade)
		draw_polygon(pts, cols, uvs, _tex)
	var rim: PackedVector2Array = _hex(c, r)
	rim.append(rim[0])
	draw_polyline(rim, col if (selected or _hover) else col.darkened(0.35), 5.0 if selected else 4.0, true)
