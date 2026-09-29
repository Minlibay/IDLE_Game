class_name TalentData
extends Resource
## Узел сетки талантов: бонусы (modifiers) × ранг.
## Малые и значимые узлы генерирует TalentTree; ключевые описываются вручную (TalentTree.keystones).
## В описании {value} заменяется значением первого бонуса с учётом ранга, {value2} — второго и т.д.;
## пустое описание собирается из бонусов автоматически.

enum Kind { MINOR, NOTABLE, KEYSTONE, START }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## Иконка. Пусто — берётся иконка по типу первого бонуса.
@export var icon: Texture2D
@export var kind: Kind = Kind.MINOR
## Сектор (индекс в TalentTree.regions). Для ключевых — в каком секторе их поставить.
@export var region := 0
## Для ключевых: сдвиг по углу от середины сектора (-1..1), чтобы два ключевых не стояли в одной клетке.
@export_range(-1.0, 1.0) var region_offset := 0.0
@export var max_rank := 1
@export var modifiers: Array[StatModifier] = []

## Клетка в сетке (заполняет TalentTree при построении).
var grid_position := Vector2i.ZERO


func get_description(rank: int) -> String:
	if description == "":
		return StatModifier.describe_list(modifiers, maxi(rank, 1))
	var text := description
	for i in modifiers.size():
		var key := "{value}" if i == 0 else "{value%d}" % (i + 1)
		text = text.replace(key, StatModifier.format_number(modifiers[i].value * maxi(rank, 1)))
	return text


## Иконки ключевых талантов: <id без префикса класса>.png (общие у классов — «Несокрушимый» и т.п.).
const KEYSTONE_ICON_DIR := "res://assets/sprites/talents/keystones/"

var _keystone_icon: Texture2D


func get_icon() -> Texture2D:
	if icon:
		return icon
	if kind == Kind.KEYSTONE:
		if _keystone_icon == null:
			var path := KEYSTONE_ICON_DIR + id.substr(id.find("_") + 1) + ".png"
			if ResourceLoader.exists(path):
				_keystone_icon = load(path)
		if _keystone_icon:
			return _keystone_icon
	if modifiers.is_empty():
		return null
	return StatModifier.get_icon(modifiers[0].stat)
