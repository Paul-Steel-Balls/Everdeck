extends Label
class_name PerfHud

# F3 toggles this small readout in the corner: frames per second, the
# average frame time, the worst frame in the last two seconds, and a count
# of hitches (frames slower than HITCH_MS, which you feel as a jolt). At
# 60 Hz every frame should take ~16.7 ms. While it's on, a line is also
# written every few seconds to perf_log.txt in the game's user folder, so
# a whole match can be checked afterwards.

const HITCH_MS := 25.0
const WINDOW_S := 2.0
const LOG_EVERY_S := 5.0

var _times: Array = []      # [time, frame_ms]
var _hitches: int = 0
var _log_t: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	position = Vector2(8, 4)
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible
		_hitches = 0
		_times.clear()


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	var ms: float = delta * 1000.0
	_times.append([_clock, ms])
	if ms > HITCH_MS and _times.size() > 3:
		_hitches += 1
	while not _times.is_empty() and _clock - float(_times[0][0]) > WINDOW_S:
		_times.pop_front()
	var total := 0.0
	var worst := 0.0
	for t in _times:
		total += float(t[1])
		worst = maxf(worst, float(t[1]))
	var avg: float = total / maxf(1.0, float(_times.size()))
	text = "%d fps   avg %.1f ms   worst %.1f ms   hitches %d" % [Engine.get_frames_per_second(), avg, worst, _hitches]
	add_theme_color_override("font_color", Color(0.75, 1.0, 0.75) if worst < HITCH_MS else Color(1.0, 0.7, 0.4))
	_log_t += delta
	if _log_t >= LOG_EVERY_S:
		_log_t = 0.0
		var f := FileAccess.open("user://perf_log.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf_log.txt") else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), text])
			f.close()
