class_name Monster
extends Actor
## Монстр: идёт к герою, встаёт в очередь за другими монстрами и атакует вблизи.

const GROUP := &"monsters"
## Рост статов с каждой волной.
const HP_GROWTH_PER_WAVE := 1.15
const DAMAGE_GROWTH_PER_WAVE := 1.10
## Минимальная дистанция между монстрами в очереди.
const QUEUE_SPACING := 0.9

var data: MonsterData
var wave_level := 1
var target: Actor


func setup(p_data: MonsterData, p_wave: int, p_target: Actor) -> void:
	data = p_data
	wave_level = p_wave
	target = p_target
	max_hp = data.base_hp * pow(HP_GROWTH_PER_WAVE, p_wave - 1)
	hp = max_hp
	damage = data.base_damage * pow(DAMAGE_GROWTH_PER_WAVE, p_wave - 1)
	attack_interval = data.attack_interval
	attack_range = data.attack_range
	attack_cooldown = attack_interval * 0.5
	if data.sprite_frames:
		set_sprite_frames(data.sprite_frames, data.sprite_height, true)
	else:
		set_sprite(data.sprite, data.sprite_height, true)
	add_to_group(GROUP)
	_update_health()


func _tick(delta: float) -> void:
	_is_moving = false
	if not is_alive() or target == null or not target.is_alive():
		return
	var dx := target.global_position.x - global_position.x
	if absf(dx) > attack_range:
		if not _is_blocked(signf(dx)):
			position.x += signf(dx) * data.move_speed * delta
			_is_moving = true
		set_base_animation(&"walk" if _is_moving else ANIM_IDLE)
		return
	set_base_animation(ANIM_IDLE)
	attack_cooldown -= delta
	if attack_cooldown <= 0.0:
		attack_cooldown = attack_interval
		if not play_action(&"attack"):
			lunge(signf(dx))
		var hit := roll_hit()
		target.take_hit(hit.amount, hit.is_crit)


## Есть ли впереди (ближе к герою) другой живой монстр вплотную.
func _is_blocked(direction: float) -> bool:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Monster
		if other == self or other == null or not other.is_alive():
			continue
		var ahead := (other.global_position.x - global_position.x) * direction
		if ahead > 0.0 and ahead < QUEUE_SPACING:
			return true
	return false


func _die() -> void:
	remove_from_group(GROUP)
	super._die()


func _on_death_animation_finished() -> void:
	queue_free()
