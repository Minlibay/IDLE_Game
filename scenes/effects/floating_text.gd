class_name FloatingText
extends Label3D
## Всплывающий текст: цифры урона, золото, названия лута, «Уровень!».

func show_text(value: String, color: Color, size_scale := 1.0, rise := 0.8, duration := 0.9) -> void:
	text = value
	modulate = color
	scale = Vector3.ONE * size_scale
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + rise, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.tween_property(self, "outline_modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.chain().tween_callback(queue_free)
