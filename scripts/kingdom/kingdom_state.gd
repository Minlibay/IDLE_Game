class_name KingdomState
extends RefCounted
## Королевство (замок) — зеркало состояния сервера (server/src/world/kingdom.ts).
## Ресурсы, казна, стройка и армия считаются только на сервере, чтобы их нельзя было подделать.
## Клиент получает состояние через WorldService (apply_server), между опросами плавно
## «догоняет» производство для показа и отправляет действия: стройку, найм, еду героя.
## Живёт внутри GameState (GameState.kingdom); в сохранение пишется только кэш последнего состояния.

signal resources_changed
signal buildings_changed
## Изменились бонусы зданий к характеристикам.
signal bonuses_changed
signal construction_finished(building: BuildingData, level: int)
## Пришло первое состояние с сервера за сессию: отчёт о том, что изменилось с прошлого запуска.
signal first_sync(report: Dictionary)

## "gold" — казна замка (отдельно от золота героя; герой может вносить своё золото в казну).
const RESOURCES := ["food", "water", "wood", "stone", "gold"]
const RESOURCE_NAMES := {"food": "Еда", "water": "Вода", "wood": "Дерево", "stone": "Камень", "gold": "Казна"}
const RESOURCE_ICON_DIR := "res://assets/sprites/resources/"
## Стартовые значения нового замка (выгружаются на сервер: tools/export_server_data.gd).
const START_RESOURCES := {"food": 30.0, "water": 30.0, "wood": 80.0, "stone": 40.0, "gold": 200.0}
## Склад без построек; Ратуша добавляет storage_per_level за уровень.
const BASE_STORAGE := 100.0
## Казна вмещает во столько раз больше обычного склада.
const GOLD_STORAGE_MULTIPLIER := 5.0

var resources: Dictionary[String, float] = {}
var levels: Dictionary[String, int] = {}
## Стройка с сервера: {id, level, startedAt, finishAt} (мс серверного времени) или пусто.
var construction: Dictionary = {}
## Получено ли состояние с сервера в этой сессии (до этого показывается кэш из сохранения).
var synced := false
var _bonuses: Dictionary = {}
## Съедено героем, но ещё не отправлено на сервер.
var _pending_consumption: Dictionary[String, float] = {}
## Кэш из сохранения — с ним сравнивается первое состояние с сервера (отчёт «пока вас не было»).
var _cached: Dictionary = {}
## Армия этого замка.
var army := ArmyState.new()


func _init() -> void:
	army.setup(self)


static func resource_name(resource_id: String) -> String:
	return TranslationServer.translate(RESOURCE_NAMES.get(resource_id, resource_id))


static func resource_icon(resource_id: String) -> Texture2D:
	return load(RESOURCE_ICON_DIR + resource_id + ".png")


## Стоимость × количество.
static func multiply_cost(cost: Dictionary, count: int) -> Dictionary:
	var result := {}
	for resource_id: String in cost:
		result[resource_id] = float(cost[resource_id]) * count
	return result


## Новый персонаж: пустое зеркало (настоящий замок создаёт сервер при регистрации).
func reset() -> void:
	resources.clear()
	for resource_id: String in RESOURCES:
		resources[resource_id] = START_RESOURCES.get(resource_id, 0.0)
	levels.clear()
	for building in Database.buildings:
		if building.is_town_hall:
			levels[building.id] = 1
	construction = {}
	synced = false
	_cached = {}
	_pending_consumption.clear()
	army.reset()
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
	return resources.get(resource_id, 0.0)


## Вместимость склада для ресурса (казна больше).
func get_storage_capacity(resource_id := "food") -> float:
	var capacity := BASE_STORAGE
	for building in Database.buildings:
		capacity += building.storage_per_level * get_level(building)
	return capacity * GOLD_STORAGE_MULTIPLIER if resource_id == "gold" else capacity


func get_production_per_minute(resource_id: String) -> float:
	var total := 0.0
	for building in Database.buildings:
		if building.produces == resource_id:
			total += building.production_per_level * get_level(building)
	return total


## Бонус зданий к характеристике героя (StatModifier.Stat).
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


## Почему нельзя улучшить здание ("" — можно). Окончательно решает сервер.
func get_upgrade_block_reason(building: BuildingData) -> String:
	var level := get_level(building)
	if level >= building.max_level:
		return tr("Максимальный уровень")
	if not synced:
		return tr("Нет связи с сервером")
	if is_constructing():
		return tr("Строители заняты: %s") % get_construction_building().display_name
	if level >= get_max_allowed_level(building):
		return tr("Нужна Ратуша %d-го уровня") % (level + 1)
	if not can_afford(get_upgrade_cost(building)):
		return tr("Не хватает ресурсов")
	return ""


func can_upgrade(building: BuildingData) -> bool:
	return get_upgrade_block_reason(building) == ""


func is_constructing() -> bool:
	return not construction.is_empty()


func get_construction_building() -> BuildingData:
	return Database.get_building(str(construction.get("id", ""))) if is_constructing() else null


## Уровень, до которого идёт стройка.
func get_construction_level() -> int:
	return int(construction.get("level", 0))


## Секунд до конца стройки.
func get_construction_left() -> float:
	if not is_constructing():
		return 0.0
	return maxf(0.0, (float(construction.finishAt) - WorldService.server_now_ms()) / 1000.0)


func get_construction_ratio() -> float:
	if not is_constructing():
		return 0.0
	var started := float(construction.startedAt)
	var total := maxf(1.0, float(construction.finishAt) - started)
	return clampf((WorldService.server_now_ms() - started) / total, 0.0, 1.0)


# --- Действия (выполняет сервер) ------------------------------------------------

## Отправляет на сервер заказ стройки следующего уровня. false — заведомо нельзя.
func start_upgrade(building: BuildingData) -> bool:
	if not can_upgrade(building):
		return false
	WorldService.kingdom_build(building.id)
	return true


## Герой берёт еду или воду со склада. Списывается сразу (для показа), на сервер уходит пачкой.
func try_consume(resource_id: String, amount: float) -> bool:
	if not synced or get_resource(resource_id) < amount:
		return false
	resources[resource_id] -= amount
	_pending_consumption[resource_id] = _pending_consumption.get(resource_id, 0.0) + amount
	resources_changed.emit()
	return true


## Забирает накопленное потребление для отправки на сервер.
func take_pending_consumption() -> Dictionary:
	var result := {}
	for resource_id: String in _pending_consumption:
		if _pending_consumption[resource_id] > 0.0:
			result[resource_id] = _pending_consumption[resource_id]
	_pending_consumption.clear()
	return result


## Каждый кадр: плавно показывает производство и содержание армии до следующего ответа сервера.
func tick(delta: float) -> void:
	if not synced:
		return
	for resource_id: String in RESOURCES:
		var rate := get_production_per_minute(resource_id)
		if rate <= 0.0:
			continue
		var current := get_resource(resource_id)
		resources[resource_id] = maxf(current, minf(get_storage_capacity(resource_id), current + rate * delta / 60.0))
	var upkeep := army.upkeep_per_minute * delta / 60.0
	if upkeep > 0.0:
		resources["food"] = maxf(0.0, get_resource("food") - upkeep)
	resources_changed.emit()


## Пора спросить сервер: по времени должна была закончиться стройка или обучиться солдат.
func needs_refresh() -> bool:
	if not synced:
		return false
	var now := WorldService.server_now_ms()
	if is_constructing() and now >= float(construction.finishAt):
		return true
	return army.needs_refresh(now)


## Применяет состояние замка с сервера (Game.playerView().kingdom).
func apply_server(view: Dictionary) -> void:
	var old_levels := levels.duplicate()
	var was_synced := synced
	resources.clear()
	var server_resources: Dictionary = view.get("resources", {})
	for resource_id: String in RESOURCES:
		# Съеденное героем, но ещё не дошедшее до сервера, вычитаем, чтобы цифры не прыгали.
		resources[resource_id] = maxf(0.0, float(server_resources.get(resource_id, 0.0)) - _pending_consumption.get(resource_id, 0.0))
	levels.clear()
	var server_levels: Dictionary = view.get("levels", {})
	for building in Database.buildings:
		if server_levels.has(building.id):
			levels[building.id] = int(server_levels[building.id])
	var server_construction: Variant = view.get("construction")
	construction = server_construction if server_construction is Dictionary else {}
	army.apply_server(view.get("army", {}))
	synced = true

	if old_levels != levels:
		_rebuild_bonuses()
		bonuses_changed.emit()
		if was_synced:
			for building in Database.buildings:
				if get_level(building) > int(old_levels.get(building.id, 0)):
					construction_finished.emit(building, get_level(building))
	if not was_synced:
		first_sync.emit(_changes_since_cache())
		_cached = {}
	resources_changed.emit()
	buildings_changed.emit()


## Связь с сервером потеряна или игрок вышел: действия недоступны, пока не придёт состояние.
func mark_unsynced() -> void:
	synced = false
	resources_changed.emit()
	buildings_changed.emit()


# --- Внутреннее -----------------------------------------------------------------

## Что изменилось с прошлого запуска: {resources: {id: прирост}, built: [..], trained: {unit_id: count}}.
func _changes_since_cache() -> Dictionary:
	if _cached.is_empty():
		return {}
	var gained := {}
	var cached_resources: Dictionary = _cached.get("resources", {})
	for resource_id: String in RESOURCES:
		var delta := get_resource(resource_id) - float(cached_resources.get(resource_id, get_resource(resource_id)))
		if delta >= 1.0:
			gained[resource_id] = delta
	var built := PackedStringArray()
	var cached_levels: Dictionary = _cached.get("levels", {})
	for building in Database.buildings:
		var level := get_level(building)
		if level > int(cached_levels.get(building.id, 0)):
			built.append(tr("%s ур. %d") % [building.display_name, level])
	var trained := {}
	var cached_units: Dictionary = (_cached.get("army", {}) as Dictionary).get("units", {})
	for unit_id: String in army.units:
		var count: int = army.units[unit_id] - int(cached_units.get(unit_id, 0))
		if count > 0:
			trained[unit_id] = count
	return {"resources": gained, "built": built, "trained": trained}


func _rebuild_bonuses() -> void:
	_bonuses.clear()
	for building in Database.buildings:
		var level := get_level(building)
		if level > 0:
			StatModifier.accumulate(_bonuses, building.modifiers, level)


# --- Сохранение (кэш) -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"resources": resources, "levels": levels, "army": {"units": army.units}}


## Загружает кэш: его видно до ответа сервера, и с ним сравнивается первое состояние с сервера.
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
	var saved_army: Variant = data.get("army", {})
	army.load_cache(saved_army if saved_army is Dictionary else {})
	_cached = to_dict().duplicate(true)
	_rebuild_bonuses()
	resources_changed.emit()
	buildings_changed.emit()
