class_name TalentData
extends Resource
## Талант: бонусы (modifiers) × вложенный ранг.
## В описании {value} заменяется значением первого бонуса с учётом ранга, {value2} — второго и т.д.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## Иконка. Пусто — берётся иконка по типу первого бонуса.
@export var icon: Texture2D
## Номер ветки (колонки) в дереве: 0, 1, 2.
@export var branch := 0
## Ряд в ветке: 0 — верхний. Ряд N требует N × points_per_row очков в ветке.
@export var row := 0
@export var max_rank := 1
@export var modifiers: Array[StatModifier] = []


func get_description(rank: int) -> String:
	var text := description
	for i in modifiers.size():
		var key := "{value}" if i == 0 else "{value%d}" % (i + 1)
		text = text.replace(key, StatModifier.format_number(modifiers[i].value * maxi(rank, 1)))
	return text


func get_icon() -> Texture2D:
	if icon:
		return icon
	if modifiers.is_empty():
		return null
	return load(StatModifier.get_icon_path(modifiers[0].stat))
