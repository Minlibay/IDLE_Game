class_name AreaEffect
extends SkillEffect
## Урон по области: вокруг героя (вихрь) или вокруг цели (метеор).

@export var damage_multiplier := 1.5
@export var radius := 3.0
## true — центр в цели, false — вокруг героя.
@export var center_on_target := false
@export var color := Color(1.0, 0.8, 0.3)


func should_auto_cast(caster: Hero) -> bool:
	var target := caster.find_target()
	if target == null:
		return false
	return center_on_target or absf(target.global_position.x - caster.global_position.x) <= radius


func execute(caster: Hero, target: Monster, power := 1.0) -> void:
	var center := caster.global_position
	if center_on_target and target:
		center = target.global_position
	else:
		caster.lunge(1.0)
	_damage_area(caster, center, radius, damage_multiplier * power)
	_spawn_burst(caster, center, radius, color)
