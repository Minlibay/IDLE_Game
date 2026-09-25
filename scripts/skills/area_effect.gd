class_name AreaEffect
extends SkillEffect
## Урон по области: вокруг героя (вихрь), вокруг цели (метеор) или по линии перед героем (line — пробивающий выстрел).

@export var damage_multiplier := 1.5
@export var radius := 3.0
## true — центр в цели, false — вокруг героя.
@export var center_on_target := false
## Линия: все враги перед героем на расстоянии до radius (пробивает насквозь).
@export var line := false
@export var color := Color(1.0, 0.8, 0.3)


func should_auto_cast(caster: Hero) -> bool:
	var target := caster.find_target()
	if target == null:
		return false
	return center_on_target or line or absf(target.global_position.x - caster.global_position.x) <= radius


func execute(caster: Hero, target: Monster, power := 1.0) -> void:
	if line:
		_hit_line(caster, power)
		return
	var center := caster.global_position
	if center_on_target and target:
		center = target.global_position
	else:
		caster.lunge(1.0)
	_damage_area(caster, center, radius, damage_multiplier * power, null, power)
	_spawn_burst(caster, center, radius, color)


## Все враги перед героем (по направлению к ближайшему) до radius.
func _hit_line(caster: Hero, power: float) -> void:
	var from := caster.global_position.x
	var nearest := caster.find_target()
	var direction := signf(nearest.global_position.x - from) if nearest else 1.0
	for node in caster.get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster == null or not monster.is_alive():
			continue
		var ahead := (monster.global_position.x - from) * direction
		if ahead >= 0.0 and ahead <= radius:
			var hit := caster.roll_hit(damage_multiplier * power)
			monster.take_hit(hit.amount, hit.is_crit)
			_apply_riders(caster, monster, power)
			_spawn_burst(caster, monster.global_position, 0.8, color)
