class_name SkillBurst
extends Node3D
## Расходящееся по земле кольцо — визуал умений по области и баффов.

const DURATION := 0.45

@onready var ring: MeshInstance3D = $Ring


## Вызывать после add_child().
func play(center: Vector3, radius: float, color: Color) -> void:
	global_position = center + Vector3(0.0, 0.03, 0.0)
	var material := ring.material_override as StandardMaterial3D
	material.albedo_color = color
	scale = Vector3.ONE * 0.2
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector3.ONE * radius * 2.0, DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, DURATION).set_delay(DURATION * 0.3)
	tween.chain().tween_callback(queue_free)
