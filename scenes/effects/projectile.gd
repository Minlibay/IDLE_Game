class_name Projectile
extends Node3D
## Снаряд дальнобойного героя (стрела, магический шар). Летит в цель и наносит урон.

const SPEED := 16.0
## Размер снаряда в мире по ширине.
const WORLD_WIDTH := 0.5

var _target: Actor
var _hit: Actor.Hit
var _on_impact := Callable()

@onready var sprite: Sprite3D = $Sprite


## Вызывать после add_child(). on_impact(position: Vector3) вызывается при попадании.
func launch(from: Vector3, target: Actor, hit: Actor.Hit, texture: Texture2D,
		size_scale := 1.0, tint := Color.WHITE, on_impact := Callable()) -> void:
	global_position = from
	_target = target
	_hit = hit
	_on_impact = on_impact
	sprite.texture = texture
	sprite.pixel_size = WORLD_WIDTH * size_scale / float(texture.get_width())
	sprite.modulate = tint


func _process(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_alive():
		queue_free()
		return
	var aim := _target.global_position + Vector3(0.0, _target.visual_height * 0.5, 0.0)
	var to_target := aim - global_position
	var step := SPEED * delta
	if to_target.length() <= step:
		var impact_position := _target.global_position
		_target.take_hit(_hit.amount, _hit.is_crit)
		if _on_impact.is_valid():
			_on_impact.call(impact_position)
		queue_free()
		return
	global_position += to_target.normalized() * step
	sprite.rotation.z = atan2(to_target.y, to_target.x)
