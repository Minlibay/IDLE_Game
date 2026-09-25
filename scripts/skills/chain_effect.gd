class_name ChainEffect
extends SkillEffect
## Цепной удар (цепная молния): снаряд летит в цель и перескакивает на ближайших врагов,
## каждый прыжок слабее предыдущего. Каждый враг задевается один раз.

@export var damage_multiplier := 1.8
## Сколько всего врагов задевает цепь (вместе с первой целью).
@export var jumps := 5
## Урон каждого следующего прыжка × falloff.
@export var falloff := 0.85
## На какое расстояние может перескочить цепь.
@export var jump_radius := 5.0
@export var projectile_texture: Texture2D
@export var projectile_scale := 1.2
@export var tint := Color(0.6, 0.85, 1.0)


func execute(caster: Hero, target: Monster, power := 1.0) -> void:
	_jump(caster, caster.global_position + Vector3(0.3, caster.visual_height * 0.55, 0.05), target, damage_multiplier * power, 1, {}, power)


func _jump(caster: Hero, from: Vector3, target: Monster, multiplier: float, index: int, hit_ids: Dictionary, power: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(target) or not target.is_alive():
		return
	hit_ids[target.get_instance_id()] = true
	var projectile: Projectile = Hero.PROJECTILE_SCENE.instantiate()
	caster.effects_parent.add_child(projectile)
	var texture := projectile_texture if projectile_texture else caster.class_data.projectile_texture
	projectile.launch(from, target, caster.roll_hit(multiplier), texture, projectile_scale, tint,
		func(impact: Vector3) -> void:
			if is_instance_valid(target):
				_apply_riders(caster, target, power)
			if index >= jumps or not is_instance_valid(caster):
				return
			var next := _next_target(caster, impact, hit_ids)
			if next:
				_jump(caster, impact + Vector3(0, 0.6, 0), next, multiplier * falloff, index + 1, hit_ids, power))


func _next_target(caster: Hero, from: Vector3, hit_ids: Dictionary) -> Monster:
	var best: Monster = null
	var best_distance := jump_radius
	for node in caster.get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster == null or not monster.is_alive() or hit_ids.has(monster.get_instance_id()):
			continue
		var distance := absf(monster.global_position.x - from.x)
		if distance <= best_distance:
			best = monster
			best_distance = distance
	return best
