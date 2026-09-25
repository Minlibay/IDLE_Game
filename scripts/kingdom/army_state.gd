class_name ArmyState
extends RefCounted
## Армия замка — зеркало сервера: отряды в замке, очередь обучения, вместимость, содержание и сила.
## Принадлежит KingdomState (kingdom.army). Найм и отмену выполняет сервер (через WorldService).
## Армия, ушедшая с героем на карту, — WorldService.get_my_army().

signal changed
## Заказ в очереди полностью обучен.
signal order_completed(unit: UnitData, count: int)

## Значения по умолчанию — те же, что выгружаются на сервер (tools/export_server_data.gd).
const STARVING_POWER_MULTIPLIER := 0.5
const MAX_QUEUE := 5

var units: Dictionary[String, int] = {}
## Очередь обучения с сервера: [{"id", "count" — осталось, "total" — заказано, "nextAt" — мс серверного
## времени до следующего солдата (только у первого заказа), "perUnitMs"}].
var queue: Array[Dictionary] = []
var starving := false
var capacity := 0
## Занятые места: вся армия игрока (замок + карта + гарнизоны) + очередь.
var housing_used := 0
var upkeep_per_minute := 0.0
var attack := 0.0
var defense := 0.0
## Множители атаки и защиты (здания, зоны, реликвии армии, голод) — как считает сервер.
var attack_multiplier := 1.0
var defense_multiplier := 1.0
## Время обучения одного солдата на сервере, мс: unit_id -> ms.
var train_times: Dictionary = {}
## Слабая ссылка на свой замок: замок владеет армией, обычная ссылка создала бы цикл (утечку памяти).
var _kingdom_ref: WeakRef


func setup(kingdom: KingdomState) -> void:
	_kingdom_ref = weakref(kingdom)


func _kingdom() -> KingdomState:
	return _kingdom_ref.get_ref() as KingdomState


func reset() -> void:
	units.clear()
	queue.clear()
	starving = false
	capacity = 0
	housing_used = 0
	upkeep_per_minute = 0.0
	attack = 0.0
	defense = 0.0
	attack_multiplier = 1.0
	defense_multiplier = 1.0
	train_times.clear()
	changed.emit()


# --- Чтение состояния -----------------------------------------------------------

func get_count(unit: UnitData) -> int:
	return units.get(unit.id, 0)


func get_total_units() -> int:
	var total := 0
	for unit_id: String in units:
		total += units[unit_id]
	return total


func get_housing_used() -> int:
	return housing_used


func get_capacity() -> int:
	return capacity


func get_free_capacity() -> int:
	return maxi(0, capacity - housing_used)


func get_required_building(unit: UnitData) -> BuildingData:
	return Database.get_building(unit.required_building)


func is_unlocked(unit: UnitData) -> bool:
	var building := get_required_building(unit)
	return building == null or _kingdom().get_level(building) >= unit.required_level


## Секунд на одного солдата (как считает сервер: здания + захваченные зоны).
func get_training_time(unit: UnitData) -> float:
	return float(train_times.get(unit.id, unit.train_time * 1000.0)) / 1000.0


## Сколько солдат можно нанять прямо сейчас (по месту и ресурсам).
func get_max_recruitable(unit: UnitData) -> int:
	var by_space := get_free_capacity() / maxi(1, unit.housing)
	var by_cost := by_space
	for resource_id: String in unit.cost:
		var price := float(unit.cost[resource_id])
		if price > 0.0:
			by_cost = mini(by_cost, floori(_kingdom().get_resource(resource_id) / price))
	return maxi(0, by_cost)


## Почему нельзя нанять count солдат ("" — можно). Окончательно решает сервер.
func get_recruit_block_reason(unit: UnitData, count: int) -> String:
	if not _kingdom().synced:
		return tr("Нет связи с сервером")
	if not is_unlocked(unit):
		var building := get_required_building(unit)
		return tr("Нужно: %s %d-го уровня") % [building.display_name, unit.required_level]
	if count <= 0:
		return tr("Укажите количество")
	if queue.size() >= MAX_QUEUE:
		return tr("Очередь обучения заполнена")
	if count * unit.housing > get_free_capacity():
		return tr("Не хватает места в армии (свободно %d)") % get_free_capacity()
	if not _kingdom().can_afford(KingdomState.multiply_cost(unit.cost, count)):
		return tr("Не хватает ресурсов")
	return ""


func get_upkeep_per_minute() -> float:
	return upkeep_per_minute


func get_attack_multiplier() -> float:
	return attack_multiplier


func get_defense_multiplier() -> float:
	return defense_multiplier


func get_attack() -> float:
	return attack


func get_defense() -> float:
	return defense


## Общая сила армии замка.
func get_power() -> float:
	return attack + defense


## Сколько секунд осталось до конца заказа в очереди.
func get_order_time_left(index: int) -> float:
	var order := queue[index]
	var unit := Database.get_unit(order.id)
	if unit == null:
		return 0.0
	var remaining := int(order.count)
	var per_unit := float(order.get("perUnitMs", 0.0)) / 1000.0
	if index == 0:
		var next_left := maxf(0.0, (float(order.nextAt) - WorldService.server_now_ms()) / 1000.0)
		return next_left + (remaining - 1) * per_unit
	return remaining * get_training_time(unit)


## Пора запросить сервер: первый заказ должен был выдать солдата.
func needs_refresh(server_now_ms: float) -> bool:
	return not queue.is_empty() and float(queue[0].get("nextAt", 0.0)) > 0.0 and server_now_ms >= float(queue[0].nextAt)


# --- Действия (выполняет сервер) ------------------------------------------------

func recruit(unit: UnitData, count: int) -> bool:
	if get_recruit_block_reason(unit, count) != "":
		return false
	WorldService.kingdom_recruit(unit.id, count)
	return true


## Отменяет заказ; ресурсы за необученных солдат возвращаются полностью.
func cancel_order(index: int) -> void:
	if index >= 0 and index < queue.size():
		WorldService.kingdom_cancel(index)


## Применяет армию замка с сервера (kingdomView().army).
func apply_server(view: Dictionary) -> void:
	var old_queue := queue.duplicate(true)
	var old_units := units.duplicate()
	units.clear()
	var server_units: Dictionary = view.get("units", {})
	for unit_id: String in server_units:
		if Database.get_unit(unit_id):
			units[unit_id] = int(server_units[unit_id])
	queue.clear()
	for entry: Variant in view.get("queue", []):
		if entry is Dictionary and Database.get_unit(str(entry.get("id", ""))):
			queue.append(entry)
	starving = bool(view.get("starving", false))
	capacity = int(view.get("capacity", 0))
	housing_used = int(view.get("housingUsed", 0))
	upkeep_per_minute = float(view.get("upkeep", 0.0))
	attack = float(view.get("attack", 0.0))
	defense = float(view.get("defense", 0.0))
	attack_multiplier = float(view.get("attackMultiplier", 1.0))
	defense_multiplier = float(view.get("defenseMultiplier", 1.0))
	train_times = view.get("trainTimes", {})
	# Заказ исчез из начала очереди, а солдат этого типа прибавилось — он обучен.
	if not old_queue.is_empty() and (queue.is_empty() or queue.size() < old_queue.size()):
		var finished: Dictionary = old_queue[0]
		if int(units.get(finished.id, 0)) > int(old_units.get(finished.id, 0)):
			var unit := Database.get_unit(finished.id)
			if unit:
				order_completed.emit(unit, int(finished.total))
	changed.emit()


## Кэш из сохранения (только отряды — для отчёта «пока вас не было»).
func load_cache(data: Dictionary) -> void:
	reset()
	var saved_units: Variant = data.get("units", {})
	if saved_units is Dictionary:
		for unit in Database.units:
			if saved_units.has(unit.id):
				units[unit.id] = maxi(0, int(saved_units[unit.id]))
	changed.emit()
