class_name StrikeEffect
extends SkillEffect
## Мощная атака по цели. У дальнобойных классов — усиленный снаряд.
## Если splash_radius > 0, при попадании задевает и врагов вокруг цели.

@export var damage_multiplier := 2.5
## Всегда критический удар.
@export var force_crit := false

@export_group("Projectile")
@export var projectile_scale := 1.8
## Своя картинка снаряда. Пусто = снаряд класса.
@export var projectile_texture: Texture2D
@export var tint := Color.WHITE

@export_group("Splash")
@export var splash_radius := 0.0
@export var splash_multiplier := 1.0
@export var splash_color := Color(1.0, 0.55, 0.2)


func execute(caster: Hero, target: Monster, power := 1.0) -> void:
	var hit := caster.roll_hit(damage_multiplier * power, force_crit)
	if caster.class_data.is_ranged():
		caster.launch_projectile(target, hit, projectile_scale, tint, projectile_texture,
			_on_impact.bind(caster, target, power))
	else:
		caster.lunge(signf(target.global_position.x - caster.global_position.x))
		target.take_hit(hit.amount, hit.is_crit)
		_on_impact(target.global_position, caster, target, power)


## caster и target без типов: к моменту попадания объект теоретически может быть удалён.
func _on_impact(position: Vector3, caster: Variant, target: Variant, power: float) -> void:
	if splash_radius <= 0.0 or not is_instance_valid(caster):
		return
	var exclude: Monster = target if is_instance_valid(target) else null
	_damage_area(caster, position, splash_radius, splash_multiplier * power, exclude)
	_spawn_burst(caster, position, splash_radius, splash_color)
