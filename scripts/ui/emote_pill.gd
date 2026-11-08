extends Button
class_name EmotePill

# One emote choice in the picker around your Boss: a small gold-rimmed
# plaque (same family as END TURN), lifting on hover.

const W := 172.0
const H := 44.0

var label_text: String = ""
var _hover: float = 0.0
var _font: Font


func _init() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	_font = UIKit.font(UIKit.FONT_DISPLAY_PATH)
	pivot_offset = Vector2(W, H) * 0.5
	mouse_entered.connect(func() -> void: UIKit._tween_scale(self, 1.08, 0.1))
	mouse_exited.connect(func() -> void: UIKit._tween_scale(self, 1.0, 0.14))
	button_down.connect(func() -> void: UIKit._tween_scale(self, 0.94, 0.05))


func _process(delta: float) -> void:
	_hover = move_toward(_hover, 1.0 if is_hovered() else 0.0, delta * 8.0)
	queue_redraw()


func _pill(k: float) -> PackedVector2Array:
	var p: float = 14.0
	var top: float = 4.0 + k
	var bot: float = H - 4.0 - k
	var mid: float = (top + bot) * 0.5
	return PackedVector2Array([Vector2(p + k * 0.5, top), Vector2(W - p - k * 0.5, top), Vector2(W - 3.0 - k, mid),
		Vector2(W - p - k * 0.5, bot), Vector2(p + k * 0.5, bot), Vector2(3.0 + k, mid)])


func _draw() -> void:
	var gold: Color = UIKit.GOLD
	var gold_d: Color = UIKit.GOLD_DEEP.darkened(0.25)
	if _hover > 0.0:
		for i in 3:
			draw_colored_polygon(_pill(-3.0 - i * 3.0), Color(1.0, 0.85, 0.4, 0.12 * _hover * (3 - i)))
	var sh := _pill(0.0)
	for i in sh.size():
		sh[i] += Vector2(0, 3)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	draw_colored_polygon(_pill(0.0), gold_d)
	draw_colored_polygon(_pill(1.5), gold)
	draw_colored_polygon(_pill(4.0), gold_d)
	var face := _pill(5.0)
	draw_colored_polygon(face, Color(0.08, 0.04, 0.18).lerp(Color(0.2, 0.1, 0.4), _hover))
	var up := PackedVector2Array()
	for v in face:
		up.append(Vector2(v.x, minf(v.y, H * 0.5)))
	draw_colored_polygon(up, Color(0.24, 0.12, 0.46).lerp(Color(0.36, 0.2, 0.62), _hover))
	var fs: int = 17
	while fs > 10 and _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > W - 34.0:
		fs -= 1
	var tw: float = _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2((W - tw) * 0.5, H * 0.5 + fs * 0.4)
	draw_string_outline(_font, base, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, UIKit.INK)
	draw_string(_font, base, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE.lerp(Color(1.0, 0.92, 0.6), _hover))
