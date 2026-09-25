class_name ArmyState
extends RefCounted
## Армия замка: отряды, очередь обучения, вместимость, содержание (еда) и сила.
## Принадлежит KingdomState (kingdom.army) — у каждого замка своя армия.
## get_attack() / get_defense() / add_units() / remove_units() — задел для боёв за территории на карте мира.

signal changed
## Заказ в очереди полностью обучен.
signal order_completed(unit: UnitData, count: int)

## Если армии нечего есть, её сила падает (солдаты не умирают и не разбегаются).
const STARVING_POWER_MULTIPLIER := 0.5
const MAX_QUEUE := 5

var units: Dictionary[String, int] = {}
## Очередь обучения: [{"id", "count" — осталось обучить, "total" — заказано, "left" — секунд до следующего солдата}].
var queue: Array[Dictionary] = []
var starving := false
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
	changed.emit()


# --- Чтение состояния -----------------------------------------------------------

func get_count(unit: UnitData) -> int:
	return units.get(unit.id, 0)


func get_total_units() -> int:
	var total := 0
	for unit_id: String in units:
		total += units[unit_id]
	return total


## Занятые места: обученные солдаты + те, что в очереди.
func get_housing_used() -> int:
	var used := 0
	for unit in Database.units:
		used += get_count(unit) * unit.housing
	for order in queue:
		var unit := Database.get_unit(order.id)
		if unit:
			used += int(order.count) * unit.housing
	return used


func get_capacity() -> int:
	var capacity := 0
	for building in Database.buildings:
		capacity += building.army_capacity_per_level * _kingdom().get_level(building)
	return capacity


func get_free_capacity() -> int:
	return maxi(0, get_capacity() - get_housing_used())


func get_required_building(unit: UnitData) -> BuildingData:
	return Database.get_building(unit.required_building)


func is_unlocked(unit: UnitData) -> bool:
	var building := get_required_building(unit)
	return building == null or _kingdom().get_level(building) >= unit.required_level


func get_training_time(unit: UnitData) -> float:
	return unit.train_time / (1.0 + GameState.get_bonus(StatModifier.Stat.TRAINING_SPEED) / 100.0)


## Сколько солдат можно нанять прямо сейчас (по месту и ресурсам).
func get_max_recruitable(unit: UnitData) -> int:
	var by_space := get_free_capacity() / maxi(1, unit.housing)
	var by_cost := by_space
	for resource_id: String in unit.cost:
		var price := float(unit.cost[resource_id])
		if price > 0.0:
			by_cost = mini(by_cost, floori(_kingdom().get_resource(resource_id) / price))
	return maxi(0, by_cost)


## Почему нельзя нанять count солдат ("" — можно).
func get_recruit_block_reason(unit: UnitData, count: int) -> String:
	if not is_unlocked(unit):
		var building := get_required_building(unit)
		return "Нужно: %s %d-го уровня" % [building.display_name, unit.required_level]
	if count <= 0:
		return "Укажите количество"
	if queue.size() >= MAX_QUEUE:
		return "Очередь обучения заполнена"
	if count * unit.housing > get_free_capacity():
		return "Не хватает места в армии (свободно %d)" % get_free_capacity()
	if not _kingdom().can_afford(KingdomState.multiply_cost(unit.cost, count)):
		return "Не хватает ресурсов"
	return ""


func get_upkeep_per_minute() -> float:
	var total := 0.0
	for unit in Database.units:
		total += get_count(unit) * unit.upkeep_per_minute
	return total


func get_power_multiplier() -> float:
	var multiplier := 1.0 + GameState.get_bonus(StatModifier.Stat.ARMY_POWER) / 100.0
	return multiplier * (STARVING_POWER_MULTIPLIER if starving else 1.0)


func get_attack() -> float:
	var total := 0.0
	for unit in Database.units:
		total += get_count(unit) * unit.attack
	return total * get_power_multiplier()


func get_defense() -> float:
	var total := 0.0
	for unit in Database.units:
		total += get_count(unit) * unit.defense
	return total * get_power_multiplier()


## Общая сила армии (для сравнения и будущих боёв на карте мира).
func get_power() -> float:
	return get_attack() + get_defense()


## Сколько секунд осталось до конца заказа в очереди.
func get_order_time_left(index: int) -> float:
	var order := queue[index]
	var unit := Database.get_unit(order.id)
	if unit == null:
		return 0.0
	var remaining := int(order.count)
	if index == 0:
		return float(order.left) + (remaining - 1) * get_training_time(unit)
	return remaining * get_training_time(unit)


# --- Действия -------------------------------------------------------------------

func recruit(unit: UnitData, count: int) -> bool:
	if get_recruit_block_reason(unit, count) != "":
		return false
	if not _kingdom().pay(KingdomState.multiply_cost(unit.cost, count)):
		return false
	queue.append({"id": unit.id, "count": count, "total": count, "left": get_training_time(unit)})
	changed.emit()
	return true


## Отменяет заказ; ресурсы за необученных солдат возвращаются полностью.
func cancel_order(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var order := queue[index]
	var unit := Database.get_unit(order.id)
	if unit:
		_kingdom().refund(KingdomState.multiply_cost(unit.cost, int(order.count)))
	queue.remove_at(index)
	changed.emit()


## Задел для карты мира: пополнение (например, награда за территорию).
func add_units(counts: Dictionary) -> void:
	for unit_id: String in counts:
		if Database.get_unit(unit_id):
			units[unit_id] = int(units.get(unit_id, 0)) + maxi(0, int(counts[unit_id]))
	changed.emit()


## Задел для карты мира: потери в бою или отправка отряда.
func remove_units(counts: Dictionary) -> void:
	for unit_id: String in counts:
		units[unit_id] = maxi(0, int(units.get(unit_id, 0)) - maxi(0, int(counts[unit_id])))
	changed.emit()


## Продвигает обучение. Вызывается королевством (в игре и при оффлайн-прогрессе).
func advance(seconds: float) -> void:
	var any_trained := false
	while seconds > 0.0 and not queue.is_empty():
		var order := queue[0]
		var unit := Database.get_unit(order.id)
		if unit == null:
			queue.pop_front()
			continue
		var step := minf(seconds, float(order.left))
		order.left = float(order.left) - step
		seconds -= step
		if float(order.left) <= 0.0:
			units[unit.id] = get_count(unit) + 1
			order.count = int(order.count) - 1
			any_trained = true
			if int(order.count) <= 0:
				queue.pop_front()
				order_completed.emit(unit, int(order.total))
			else:
				order.left = get_training_time(unit)
	if any_trained:
		changed.emit()


func set_starving(value: bool) -> void:
	if starving != value:
		starving = value
		changed.emit()


# --- Сохранение -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"units": units, "queue": queue, "starving": starving}


func from_dict(data: Dictionary) -> void:
	reset()
	var saved_units: Variant = data.get("units", {})
	if saved_units is Dictionary:
		for unit in Database.units:
			if saved_units.has(unit.id):
				units[unit.id] = maxi(0, int(saved_units[unit.id]))
	var saved_queue: Variant = data.get("queue", [])
	if saved_queue is Array:
		for entry: Variant in saved_queue:
			if entry is Dictionary and Database.get_unit(str(entry.get("id", ""))) and int(entry.get("count", 0)) > 0:
				queue.append({
					"id": str(entry.id),
					"count": int(entry.count),
					"total": int(entry.get("total", entry.count)),
					"left": maxf(0.0, float(entry.get("left", 0.0))),
				})
	starving = bool(data.get("starving", false))
	changed.emit()
