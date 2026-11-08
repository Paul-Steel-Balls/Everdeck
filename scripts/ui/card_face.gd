extends Control
class_name CardFace

# The deck builder's card tile: a gilded CardFrame (the one card look used
# everywhere) fitted into the tile, plus a dim state (no copies left).
# Kept as its own class so the deck builder's tiles can take input and
# carry their count badge.

const BASE := Vector2(200, 280)

var card: Dictionary = {}
var dim: bool = false  # greyed out (e.g. no copies left)
var _frame: CardFrame = null


static func make(c: Dictionary, sz: Vector2 = BASE) -> CardFace:
	var f := CardFace.new()
	f.card = c
	f.custom_minimum_size = sz
	f.size = sz
	return f


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var fw: float = minf(size.x, size.y / CardFrame.ASPECT)
	_frame = CardFrame.new()
	_frame.name = "Face"
	add_child(_frame)
	_frame.setup(card, CardFrame.Look.GILDED, fw)
	_frame.position = Vector2((size.x - fw) * 0.5, (size.y - fw * CardFrame.ASPECT) * 0.5)
	_apply_dim()


func set_dim(v: bool) -> void:
	if dim == v:
		return
	dim = v
	_apply_dim()


func _apply_dim() -> void:
	if _frame != null:
		_frame.modulate = Color(0.45, 0.45, 0.5) if dim else Color.WHITE
