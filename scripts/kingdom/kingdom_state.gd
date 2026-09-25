class_name KingdomState
extends RefCounted
## Королевство: ресурсы, уровни зданий, стройка (одна за раз), производство и оффлайн-прогресс.
## Живёт внутри GameState (GameState.kingdom) и сохраняется вместе с ним.

signal resources_changed
signal buildings_changed
## Изменились бонусы зданий к характеристикам.
signal bonuses_changed
signal construction_finished(building: BuildingData, level: int)

const RESOURCES := ["food", "water", "wood", "stone"]
const RESOURCE_NAMES := {"food": "Еда", "water": "Вода", "wood": "Дерево", "stone": "Камень", "gold": "Золото"}
const RESOURCE_ICON_DIR := "res://assets/sprites/resources/"
const START_RESOURCES := {"food": 30.0, "water": 30.0, "wood": 80.0, "stone": 40.0}
## Склад без построек; Ратуша добавляет storage_per_level за уровень.
const BASE_STORAGE := 100.0
## Оффлайн-прогресс считается максимум за 12 часов.
const MAX_OFFLINE_SECONDS := 12.0 * 3600.0

var resources: Dictionary[String, float] = {}
var levels: Dictionary[String, int] = {}
var construction_id := ""
var construction_level := 0
var construction_left := 0.0
var construction_total := 0.0
var _bonuses: Dictionary = {}


static func resource_name(resource_id: String) -> String:
	return RESOURCE_NAMES.get(resource_id, resource_id)


static func resource_icon(resource_id: String) -> Texture2D:
	return load(RESOURCE_ICON_DIR + resource_id + ".png")


## Новое королевство: стартовые ресурсы и Ратуша 1-го уровня.
func reset() -> void:
	resources.clear()
	for resource_id: String in RESOURCES:
		resources[resource_id] = START_RESOURCES.get(resource_id, 0.0)
	levels.clear()
	for building in Database.buildings:
		if building.is_town_hall:
			levels[building.id] = 1
	_clear_construction()
	_rebuild_bonuses()
	resources_changed.emit()
	buildings_changed.emit()


# --- Чтение состояния -----------------------------------------------------------

func get_level(building: BuildingData) -> int:
	return levels.get(building.id, 0)


func get_town_hall_level() -> int:
	for building in Database.buildings:
		if building.is_town_hall:
			return get_level(building)
	return 999


func get_resource(resource_id: String) -> float:
	if resource_id == "gold":
		return GameState.gold
	return resources.get(resource_id, 0.0)


func get_storage_capacity() -> float:
	var capacity := BASE_STORAGE
	for building in Database.buildings:
		capacity += building.storage_per_level * get_level(building)
	return capacity


func get_production_per_minute(resource_id: String) -> float:
	var total := 0.0
	for building in Database.buildings:
		if building.produces == resource_id:
			total += building.production_per_level * get_level(building)
	return total


## Бонус зданий к характеристике (StatModifier.Stat).
func get_bonus(stat: int, skill_id := "") -> float:
	return StatModifier.read_bonus(_bonuses, stat, skill_id)


func get_max_allowed_level(building: BuildingData) -> int:
	if building.is_town_hall:
		return building.max_level
	return mini(building.max_level, get_town_hall_level())


func get_upgrade_cost(building: BuildingData) -> Dictionary:
	return building.get_cost(get_level(building) + 1)


func can_afford(cost: Dictionary) -> bool:
	for resource_id: String in cost:
		if get_resource(resource_id) < float(cost[resource_id]):
			return false
	return true


## Почему нельзя улучшить здание ("" — можно).
func get_upgrade_block_reason(building: BuildingData) -> String:
	var level := get_level(building)
	if level >= building.max_level:
		return "Максимальный уровень"
	if is_constructing():
		return "Строители заняты: %s" % get_construction_building().display_name
	if level >= get_max_allowed_level(building):
		return "Нужна Ратуша %d-го уровня" % (level + 1)
	if not can_afford(get_upgrade_cost(building)):
		return "Не хватает ресурсов"
	return ""


func can_upgrade(building: BuildingData) -> bool:
	return get_upgrade_block_reason(building) == ""


func is_constructing() -> bool:
	return construction_id != ""


func get_construction_building() -> BuildingData:
	return Database.get_building(construction_id)


func get_construction_ratio() -> float:
	return 1.0 - construction_left / construction_total if construction_total > 0.0 else 0.0


# --- Действия -------------------------------------------------------------------

## Оплачивает и начинает стройку следующего уровня.
func start_upgrade(building: BuildingData) -> bool:
	if not can_upgrade(building):
		return false
	var cost := get_upgrade_cost(building)
	for resource_id: String in cost:
		if resource_id == "gold":
			GameState.try_spend_gold(int(cost[resource_id]))
		else:
			resources[resource_id] -= float(cost[resource_id])
	construction_id = building.id
	construction_level = get_level(building) + 1
	construction_total = building.get_build_time(construction_level)
	construction_left = construction_total
	resources_changed.emit()
	buildings_changed.emit()
	return true


## Забирает ресурс со склада (например, еду для героя).
func try_consume(resource_id: String, amount: float) -> bool:
	if resources.get(resource_id, 0.0) < amount:
		return false
	resources[resource_id] -= amount
	resources_changed.emit()
	return true


## Вызывается каждый кадр из GameState.
func tick(delta: float) -> void:
	_advance(delta)
	resources_changed.emit()


## Оффлайн-прогресс. Возвращает отчёт {seconds, resources: {id: прирост}, built: [..]}.
func simulate(seconds: float) -> Dictionary:
	seconds = clampf(seconds, 0.0, MAX_OFFLINE_SECONDS)
	var before := resources.duplicate()
	var built := _advance(seconds)
	var gained := {}
	for resource_id: String in RESOURCES:
		var delta: float = resources.get(resource_id, 0.0) - float(before.get(resource_id, 0.0))
		if delta >= 1.0:
			gained[resource_id] = delta
	resources_changed.emit()
	return {"seconds": seconds, "resources": gained, "built": built}


# --- Внутреннее -----------------------------------------------------------------

## Продвигает время: производство + стройка. Возвращает названия достроенных зданий.
func _advance(seconds: float) -> PackedStringArray:
	var finished := PackedStringArray()
	var remaining := seconds
	while remaining > 0.0:
		var step := remaining
		if is_constructing():
			step = clampf(construction_left, 0.0, remaining)
		_produce(step)
		remaining -= step
		if is_constructing():
			construction_left -= step
			if construction_left <= 0.0:
				finished.append(_finish_construction())
	return finished


func _produce(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var capacity := get_storage_capacity()
	for resource_id: String in RESOURCES:
		var rate := get_production_per_minute(resource_id)
		if rate <= 0.0:
			continue
		var current: float = resources.get(resource_id, 0.0)
		resources[resource_id] = maxf(current, minf(capacity, current + rate * seconds / 60.0))


func _finish_construction() -> String:
	var building := get_construction_building()
	var level := construction_level
	_clear_construction()
	if building == null:
		return ""
	levels[building.id] = level
	_rebuild_bonuses()
	buildings_changed.emit()
	bonuses_changed.emit()
	construction_finished.emit(building, level)
	return "%s ур. %d" % [building.display_name, level]


func _clear_construction() -> void:
	construction_id = ""
	construction_level = 0
	construction_left = 0.0
	construction_total = 0.0


func _rebuild_bonuses() -> void:
	_bonuses.clear()
	for building in Database.buildings:
		var level := get_level(building)
		if level > 0:
			StatModifier.accumulate(_bonuses, building.modifiers, level)


# --- Сохранение -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"resources": resources,
		"levels": levels,
		"construction": {
			"id": construction_id,
			"level": construction_level,
			"left": construction_left,
			"total": construction_total,
		},
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var saved_resources: Variant = data.get("resources", {})
	if saved_resources is Dictionary:
		for resource_id: String in RESOURCES:
			resources[resource_id] = maxf(0.0, float(saved_resources.get(resource_id, resources[resource_id])))
	var saved_levels: Variant = data.get("levels", {})
	if saved_levels is Dictionary:
		for building in Database.buildings:
			if saved_levels.has(building.id):
				levels[building.id] = clampi(int(saved_levels[building.id]), 0, building.max_level)
	var saved_construction: Variant = data.get("construction", {})
	if saved_construction is Dictionary and Database.get_building(str(saved_construction.get("id", ""))):
		construction_id = str(saved_construction.id)
		construction_level = int(saved_construction.get("level", 1))
		construction_total = maxf(0.0, float(saved_construction.get("total", 0.0)))
		construction_left = clampf(float(saved_construction.get("left", 0.0)), 0.0, construction_total)
	_rebuild_bonuses()
	resources_changed.emit()
	buildings_changed.emit()
