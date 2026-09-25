class_name MultiShotEffect
extends SkillEffect
## Залп снарядов по нескольким ближайшим врагам. Если врагов меньше — лишние снаряды летят в них же.

@export var projectile_count := 5
@export var damage_multiplier := 0.8
@export var projectile_scale := 1.0
@export var tint := Color.WHITE
## Вертикальный разнос снарядов, чтобы залп было видно.
@export var spread := 0.12


func execute(caster: Hero, target: Monster, power := 1.0) -> void:
	var targets := caster.find_targets(projectile_count)
	if targets.is_empty():
		targets.append(target)
	for i in projectile_count:
		var offset := Vector3(0.0, (i - (projectile_count - 1) * 0.5) * spread, 0.0)
		caster.launch_projectile(targets[i % targets.size()], caster.roll_hit(damage_multiplier * power),
			projectile_scale, tint, null, Callable(), offset)
