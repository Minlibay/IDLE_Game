class_name TalentRegion
extends Resource
## Сектор сетки талантов (например «Оружие», «Защита», «Лидерство»).
## Малые узлы сектора получают по одному бонусу из minor_modifiers, значимые — по два (усиленных).

@export var display_name := ""
@export var color := Color(0.8, 0.4, 0.4)
## Набор бонусов сектора; value — за один малый узел рядом с центром (дальше от центра — больше).
@export var minor_modifiers: Array[StatModifier] = []
## Названия значимых узлов сектора (выбираются по очереди).
@export var notable_names: PackedStringArray = []
