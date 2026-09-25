class_name SkillEffect
extends Resource
## Базовый эффект умения. Новый тип умения: унаследуйтесь и переопределите execute(),
## при необходимости requires_target() и should_auto_cast().

const BURST_SCENE := preload("res://scenes/effects/skill_burst.tscn")

@export_group("On hit")
## Оглушение/заморозка каждого задетого врага, секунд (0 — нет).
@export var stun_duration := 0.0
@export var stun_color := Color(0.6, 0.65, 1.0)
## Урон со временем: весь урон за dot_duration в долях урона героя (3.0 = 300%). 0 — нет.
@export var dot_multiplier := 0.0
@export var dot_duration := 6.0
@export var dot_color := Color(0.6, 1.0, 0.4)
## Отбросить врага от героя на это расстояние.
@export var knockback := 0.0


## Нужен ли монстр в радиусе атаки, чтобы применить умение.
func requires_target() -> bool:
	return true


## Стоит ли применить умение автоматически прямо сейчас.
func should_auto_cast(caster: Hero) -> bool:
	return caster.find_target() != null


## power — множитель урона от талантов (1.0 = без бонуса).
func execute(_caster: Hero, _target: Monster, _power := 1.0) -> void:
	pass


## Урон всем живым монстрам в радиусе от точки (+ добавки при попадании). Возвращает число задетых.
func _damage_area(caster: Hero, center: Vector3, radius: float, multiplier: float, exclude: Monster = null, power := 1.0) -> int:
	var count := 0
	for node in caster.get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster == null or monster == exclude or not monster.is_alive():
			continue
		var offset := monster.global_position - center
		if Vector2(offset.x, offset.z).length() <= radius:
			var hit := caster.roll_hit(multiplier)
			monster.take_hit(hit.amount, hit.is_crit)
			_apply_riders(caster, monster, power)
			count += 1
	return count


## Добавки при попадании: оглушение, урон со временем, отбрасывание.
func _apply_riders(caster: Hero, monster: Monster, power := 1.0) -> void:
	if not is_instance_valid(monster) or not monster.is_alive():
		return
	if dot_multiplier > 0.0:
		monster.apply_dot(caster.damage * dot_multiplier * power, dot_duration, dot_color)
	if stun_duration > 0.0:
		monster.stun(stun_duration, stun_color)
	if knockback > 0.0:
		monster.knockback(caster.global_position.x, knockback)


## Расходящееся кольцо на земле.
func _spawn_burst(caster: Hero, center: Vector3, radius: float, color: Color) -> void:
	var burst: SkillBurst = BURST_SCENE.instantiate()
	caster.effects_parent.add_child(burst)
	burst.play(Vector3(center.x, 0.0, center.z), radius, color)
