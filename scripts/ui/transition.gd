extends CanvasLayer
# Autoload "Transition": animated screen changes. Transition.go(fn) wipes
# the screen closed, runs fn (which builds the next screen), then wipes it
# open again. Input is blocked while the wipe runs.

var _rect: ColorRect
var _mat: ShaderMaterial
var _busy: bool = false


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/wipe.gdshader")
	_mat.set_shader_parameter("progress", 0.0)
	_rect.material = _mat
	add_child(_rect)


func is_busy() -> bool:
	return _busy


func go(fn: Callable, close_s: float = 0.28, open_s: float = 0.36) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_p, 0.0, 1.0, close_s)
	await tw.finished
	fn.call()
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_method(_set_p, 1.0, 0.0, open_s)
	await tw2.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _set_p(v: float) -> void:
	# Opening runs the wipe the other way across the screen.
	_mat.set_shader_parameter("progress", v)
