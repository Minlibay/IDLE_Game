class_name UnitData
extends Resource
## Тип отряда армии замка. Новый отряд = новый .tres в data/units/.
## Атака и защита — задел для захвата территорий на карте мира.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var order := 0

@export_group("Stats")
@export var attack := 3.0
@export var defense := 2.0
## Сколько мест в армии занимает один солдат.
@export var housing := 1
## Сколько еды в минуту съедает один солдат.
@export var upkeep_per_minute := 0.05

@export_group("Recruitment")
## Стоимость одного солдата: {"food": 10, "gold": 10}.
@export var cost: Dictionary = {}
## Время обучения одного солдата (секунды, без бонусов).
@export var train_time := 8.0
## Какое здание и какого уровня нужно, чтобы нанимать ("" — без требований).
@export var required_building := "barracks"
@export var required_level := 1
