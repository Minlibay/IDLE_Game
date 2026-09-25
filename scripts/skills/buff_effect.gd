class_name BuffEffect
extends SkillEffect
## Временное усиление героя (+урон, +скорость атаки, +броня, +шанс крита) и/или лечение.

## Новые значения — только в конец (в .tres хранятся числами).
enum Stat { DAMAGE, ATTACK_SPEED, ARMOR, CRIT_CHANCE }

@export var stat: Stat = Stat.DAMAGE
## DAMAGE, ATTACK_SPEED, CRIT_CHANCE: доля (0.5 = +50%). ARMOR: единицы брони. 0 = без баффа.
@export var value := 0.5
@export var duration := 6.0
## Лечение в долях от максимального HP (0.3 = 30%).
@export_range(0.0, 1.0) var heal_percent := 0.0
## Автоприменение только если HP героя ниже этой доли (1 = в любой момент боя).
@export_range(0.0, 1.0) var auto_cast_below_hp := 1.0
@export var color := Color(1.0, 0.8, 0.3)


func requires_target() -> bool:
	return false


func should_auto_cast(caster: Hero) -> bool:
	return caster.find_target() != null and caster.hp <= caster.max_hp * auto_cast_below_hp


func execute(caster: Hero, _target: Monster, _power := 1.0) -> void:
	if value != 0.0 and duration > 0.0:
		caster.add_buff(str(get_instance_id()), stat, value, duration)
	if heal_percent > 0.0:
		caster.heal(caster.max_hp * heal_percent)
	_spawn_burst(caster, caster.global_position, 1.6, color)
