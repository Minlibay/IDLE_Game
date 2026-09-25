class_name HealthBar3D
extends Node3D
## Полоска здоровья над бойцом.

@export var width := 0.9

@onready var _fill: MeshInstance3D = $Fill


func set_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_fill.scale.x = maxf(ratio, 0.001)
	_fill.position.x = -width * (1.0 - ratio) * 0.5


func set_fill_color(color: Color) -> void:
	var material := _fill.material_override as StandardMaterial3D
	material.albedo_color = color
