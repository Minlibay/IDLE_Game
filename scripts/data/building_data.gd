class_name BuildingData
extends Resource
## Здание королевства. Новое здание = новый .tres в data/buildings/.
## Стоимость и время стройки растут с каждым уровнем; бонусы и производство — линейно от уровня.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## Порядок в сетке зданий.
@export var order := 0
@export var max_level := 10
## Ратуша: её уровень ограничивает уровень остальных зданий.
@export var is_town_hall := false

@export_group("Cost")
## Стоимость 1-го уровня: {"wood": 30, "stone": 10, "gold": 20}. Ключи — ресурсы KingdomState + "gold".
@export var base_cost: Dictionary = {}
## Во сколько раз дорожает каждый следующий уровень.
@export var cost_growth := 1.6
## Время стройки 1-го уровня (секунды).
@export var base_build_time := 10.0
@export var build_time_growth := 1.5

@export_group("Effects")
## Какой ресурс производит ("" — ничего).
@export var produces := ""
## Производство в минуту за каждый уровень.
@export var production_per_level := 0.0
## Прибавка к вместимости склада за каждый уровень.
@export var storage_per_level := 0.0
## Прибавка к вместимости армии замка за каждый уровень.
@export var army_capacity_per_level := 0
## Бонусы за каждый уровень (как у талантов).
@export var modifiers: Array[StatModifier] = []


func get_cost(target_level: int) -> Dictionary:
	var result := {}
	var multiplier := pow(cost_growth, target_level - 1)
	for resource_id: String in base_cost:
		result[resource_id] = roundi(float(base_cost[resource_id]) * multiplier)
	return result


func get_build_time(target_level: int) -> float:
	return base_build_time * pow(build_time_growth, target_level - 1)
