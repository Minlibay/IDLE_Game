class_name LootDrop
extends Node3D
## Визуальный эффект: иконка предмета подпрыгивает над монстром и летит к герою.
## Сам предмет уже лежит в инвентаре — это только анимация.

const WORLD_SIZE := 0.5
const ARC_HEIGHT := 1.6

var _arc_start := Vector3.ZERO
var _arc_control := Vector3.ZERO
var _arc_end := Vector3.ZERO

@onready var sprite: Sprite3D = $Sprite


## Вызывать после add_child().
func fly(from: Vector3, to: Vector3, icon: Texture2D, tier_color: Color) -> void:
	var start := from + Vector3(0.0, 0.6, 0.2)
	_arc_start = start + Vector3(0.0, 0.5, 0.0)
	_arc_end = to + Vector3(0.0, 0.8, 0.2)
	_arc_control = (_arc_start + _arc_end) * 0.5 + Vector3(0.0, ARC_HEIGHT, 0.0)
	global_position = start
	sprite.texture = icon
	sprite.pixel_size = WORLD_SIZE / float(icon.get_height())
	sprite.modulate = Color.WHITE.lerp(tier_color, 0.35)
	var tween := create_tween()
	tween.tween_property(self, "global_position", _arc_start, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.15)
	tween.tween_method(_move_along_arc, 0.0, 1.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


## Квадратичная кривая Безье от монстра к герою.
func _move_along_arc(t: float) -> void:
	global_position = _arc_start.lerp(_arc_control, t).lerp(_arc_control.lerp(_arc_end, t), t)
