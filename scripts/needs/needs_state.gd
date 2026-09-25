class_name NeedsState
extends RefCounted
## Потребности героя (data/needs/): шкалы 0–100, падают во время боя.
## Еду и воду герой берёт со склада королевства сам; бодрость восстанавливается отдыхом.
## Высокие значения дают бонусы, низкие — небольшие штрафы (через StatModifier).
## Живёт внутри GameState (GameState.needs) и сохраняется вместе с ним.

signal changed
## Какая-то потребность перешла порог — изменились бонусы.
signal state_changed

enum Level { LOW, NORMAL, SATISFIED }

const MAX_VALUE := 100.0
## Восстановление бодрости во время отдыха (в минуту, без бонусов).
const REST_PER_MINUTE := 120.0
## Здания и таланты не могут замедлить потребности больше, чем на 80%.
const MAX_DECAY_REDUCTION := 0.8
## Ручной отдых доступен, если бодрость ниже этого значения.
const MANUAL_REST_BELOW := 95.0

var values: Dictionary[String, float] = {}
var _levels: Dictionary[String, int] = {}
var _bonuses: Dictionary = {}
var _kingdom: KingdomState


func setup(kingdom: KingdomState) -> void:
	_kingdom = kingdom


func reset() -> void:
	values.clear()
	for need in Database.needs:
		values[need.id] = MAX_VALUE
	_update_levels(true)
	changed.emit()


func get_value(need: NeedData) -> float:
	return values.get(need.id, MAX_VALUE)


func get_level(need: NeedData) -> Level:
	var value := get_value(need)
	if value >= need.satisfied_threshold:
		return Level.SATISFIED
	if value < need.low_threshold:
		return Level.LOW
	return Level.NORMAL


## Бонус потребностей к характеристике (StatModifier.Stat).
func get_bonus(stat: int, skill_id := "") -> float:
	return StatModifier.read_bonus(_bonuses, stat, skill_id)


## Время боя: потребности падают, еда и вода расходуются со склада автоматически.
func tick(delta: float) -> void:
	var reduction := clampf(GameState.get_bonus(StatModifier.Stat.NEED_DECAY) / 100.0, 0.0, MAX_DECAY_REDUCTION)
	for need in Database.needs:
		var value := get_value(need) - need.decay_per_minute / 60.0 * delta * (1.0 - reduction)
		if need.consumes_resource != "" and value <= MAX_VALUE - need.restore_per_unit \
				and _kingdom.try_consume(need.consumes_resource, 1.0):
			value += need.restore_per_unit
		values[need.id] = clampf(value, 0.0, MAX_VALUE)
	_update_levels()
	changed.emit()


## Время отдыха: восстанавливается бодрость.
func rest_tick(delta: float) -> void:
	var speed := 1.0 + GameState.get_bonus(StatModifier.Stat.REST_SPEED) / 100.0
	for need in Database.needs:
		if need.restored_by_rest:
			values[need.id] = minf(MAX_VALUE, get_value(need) + REST_PER_MINUTE / 60.0 * delta * speed)
	_update_levels()
	changed.emit()


## Какая-то «отдыхаемая» потребность на нуле — герою пора отдохнуть.
func needs_rest() -> bool:
	for need in Database.needs:
		if need.restored_by_rest and get_value(need) <= 0.0:
			return true
	return false


func is_rested() -> bool:
	for need in Database.needs:
		if need.restored_by_rest and get_value(need) < MAX_VALUE:
			return false
	return true


func can_rest_manually() -> bool:
	for need in Database.needs:
		if need.restored_by_rest and get_value(need) < MANUAL_REST_BELOW:
			return true
	return false


func _update_levels(force := false) -> void:
	var any_changed := force
	for need in Database.needs:
		var level := get_level(need)
		if _levels.get(need.id, -1) != level:
			_levels[need.id] = level
			any_changed = true
	if any_changed:
		_rebuild_bonuses()
		state_changed.emit()


func _rebuild_bonuses() -> void:
	_bonuses.clear()
	for need in Database.needs:
		match get_level(need):
			Level.SATISFIED:
				StatModifier.accumulate(_bonuses, need.satisfied_modifiers, 1.0)
			Level.LOW:
				StatModifier.accumulate(_bonuses, need.low_modifiers, 1.0)


func to_dict() -> Dictionary:
	return values


func from_dict(data: Dictionary) -> void:
	reset()
	for need in Database.needs:
		if data.has(need.id):
			values[need.id] = clampf(float(data[need.id]), 0.0, MAX_VALUE)
	_update_levels(true)
	changed.emit()
