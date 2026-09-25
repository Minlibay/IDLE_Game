class_name Monster
extends Actor
## Монстр. Поведение зависит от роли (MonsterData.Role):
##   боец и громила — идут к герою, встают в очередь и бьют вблизи;
##   стрелок — держит дистанцию и стреляет снарядами;
##   шаман — держится сзади, лечит самого раненого союзника и усиливает урон союзников рядом.
## Элита — случайный монстр волны с модификатором (ELITE_MODIFIERS): сильнее, крупнее, золотое имя, больше наград.
## Босс — приёмы из MonsterData.boss_abilities: сокрушающий удар, призыв, щит, ярость.

## Босс просит Battle создать помощников (Battle регистрирует их в волне).
signal summon_requested(data: MonsterData, at: Vector3)

const GROUP := &"monsters"
## Рост статов с каждой волной.
const HP_GROWTH_PER_WAVE := 1.15
const DAMAGE_GROWTH_PER_WAVE := 1.10
## Минимальная дистанция между монстрами в очереди.
const QUEUE_SPACING := 0.9
const PROJECTILE_SCENE := preload("res://scenes/effects/projectile.tscn")
const RING_TEXTURE := preload("res://assets/sprites/fx/ring.png")

## Элита: базовое усиление + модификатор.
const ELITE_HP := 2.5
const ELITE_DAMAGE := 1.4
const ELITE_SIZE := 1.25
const ELITE_REWARD := 3.0
const ELITE_MODIFIERS := {
	"frenzied": {"name": "Бешеный", "color": Color(1.0, 0.5, 0.4), "attack_speed": 1.6, "move_speed": 1.4},
	"stoneskin": {"name": "Каменнокожий", "color": Color(0.8, 0.82, 0.95), "hp": 1.6, "armor": 40.0},
	"vampiric": {"name": "Вампир", "color": Color(0.95, 0.35, 0.45), "lifesteal": 0.35},
	"mighty": {"name": "Могучий", "color": Color(1.0, 0.82, 0.35), "damage": 1.6, "size": 1.15},
}
const COLOR_ELITE_NAME := Color(1.0, 0.82, 0.3)
const COLOR_BOSS_NAME := Color(1.0, 0.4, 0.35)

## Приёмы босса.
const SLAM_INTERVAL := 7.0
const SLAM_WINDUP := 0.9
const SLAM_DAMAGE := 2.5
const SUMMON_INTERVAL := 12.0
const SUMMON_COUNT := 2
const SHIELD_AT := 0.5
const SHIELD_SHARE := 0.25
const ENRAGE_AT := 0.25
const ENRAGE_SPEED := 1.6
## Шаман усиливает союзников в этом радиусе и лечит в радиусе побольше.
const SHAMAN_BUFF_RADIUS := 5.0
const SHAMAN_HEAL_RADIUS := 8.0

var data: MonsterData
var wave_level := 1
var target: Actor
## id модификатора элиты ("" — обычный монстр).
var elite_id := ""
## Множитель опыта и золота (элита — больше) и добавка к шансу дропа.
var reward_multiplier := 1.0
var drop_bonus := 0.0
var _move_speed := 2.5
var _lifesteal := 0.0
var _buff_multiplier := 1.0
var _buff_left := 0.0
var _ability_cooldown := 0.0
var _slam_cooldown := SLAM_INTERVAL * 0.6
var _summon_cooldown := SUMMON_INTERVAL * 0.5
var _shield := 0.0
var _shield_used := false
var _enraged := false
var _shield_sprite: Sprite3D


func setup(p_data: MonsterData, p_wave: int, p_target: Actor, p_elite_id := "") -> void:
	data = p_data
	wave_level = p_wave
	target = p_target
	elite_id = p_elite_id if ELITE_MODIFIERS.has(p_elite_id) and not p_data.is_boss else ""
	max_hp = data.base_hp * pow(HP_GROWTH_PER_WAVE, p_wave - 1)
	damage = data.base_damage * pow(DAMAGE_GROWTH_PER_WAVE, p_wave - 1)
	armor = data.armor
	attack_interval = data.attack_interval
	attack_range = data.attack_range
	_move_speed = data.move_speed
	var height := data.sprite_height
	base_modulate = data.tint
	if elite_id != "":
		var modifier: Dictionary = ELITE_MODIFIERS[elite_id]
		max_hp *= ELITE_HP * float(modifier.get("hp", 1.0))
		damage *= ELITE_DAMAGE * float(modifier.get("damage", 1.0))
		armor += float(modifier.get("armor", 0.0))
		attack_interval /= float(modifier.get("attack_speed", 1.0))
		_move_speed *= float(modifier.get("move_speed", 1.0))
		_lifesteal = float(modifier.get("lifesteal", 0.0))
		height *= ELITE_SIZE * float(modifier.get("size", 1.0))
		base_modulate = data.tint * modifier.color.lerp(Color.WHITE, 0.4)
		reward_multiplier = ELITE_REWARD
		drop_bonus = ELITE_REWARD - 1.0
	hp = max_hp
	attack_cooldown = attack_interval * 0.5
	_ability_cooldown = data.ability_interval * 0.5
	if data.sprite_frames:
		set_sprite_frames(data.sprite_frames, height, true)
	else:
		set_sprite(data.sprite, height, true)
	visual.modulate = base_modulate
	if elite_id != "" or data.is_boss:
		_add_name_label(height)
	add_to_group(GROUP)
	_update_health()


func get_display_name() -> String:
	if elite_id != "":
		return "%s %s" % [ELITE_MODIFIERS[elite_id].name, data.display_name]
	return data.display_name


func is_elite() -> bool:
	return elite_id != ""


# --- Цикл боя -----------------------------------------------------------------------

func _tick(delta: float) -> void:
	_is_moving = false
	if not is_alive() or target == null or not target.is_alive():
		return
	_update_buff(delta)
	if data.is_boss:
		_update_boss(delta)
	if data.role == MonsterData.Role.SHAMAN:
		_update_shaman(delta)
	var dx := target.global_position.x - global_position.x
	var distance := absf(dx)
	if data.is_ranged():
		# Стрелки и шаманы проходят сквозь очередь бойцов и встают на своей дистанции;
		# стреляют, как только герой в досягаемости (можно и на ходу).
		if distance > data.preferred_range:
			position.x += signf(dx) * _move_speed * delta
			_is_moving = true
		set_base_animation(&"walk" if _is_moving else ANIM_IDLE)
		if distance > attack_range:
			return
	else:
		if distance > attack_range:
			if not _is_blocked(signf(dx)):
				position.x += signf(dx) * _move_speed * delta
				_is_moving = true
			set_base_animation(&"walk" if _is_moving else ANIM_IDLE)
			return
		set_base_animation(ANIM_IDLE)
	attack_cooldown -= delta
	if attack_cooldown > 0.0:
		return
	attack_cooldown = attack_interval
	if not play_action(&"attack"):
		lunge(signf(dx))
	var hit := roll_hit(_buff_multiplier)
	if data.is_ranged():
		_shoot(hit)
	else:
		target.take_hit(hit.amount, hit.is_crit)
		if _lifesteal > 0.0:
			heal(hit.amount * _lifesteal, false)


func _shoot(hit: Hit) -> void:
	var texture := data.projectile_texture if data.projectile_texture else RING_TEXTURE
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	_effects_parent().add_child(projectile)
	var from := global_position + Vector3(-0.3 * signf(global_position.x - target.global_position.x), visual_height * 0.55, 0.05)
	projectile.launch(from, target, hit, texture, 0.8, data.projectile_tint)


## Есть ли впереди (ближе к герою) другой живой монстр вплотную.
func _is_blocked(direction: float) -> bool:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Monster
		if other == self or other == null or not other.is_alive() or other.data.is_ranged():
			continue
		var ahead := (other.global_position.x - global_position.x) * direction
		if ahead > 0.0 and ahead < QUEUE_SPACING:
			return true
	return false


# --- Шаман --------------------------------------------------------------------------

func _update_shaman(delta: float) -> void:
	_ability_cooldown -= delta
	if _ability_cooldown > 0.0:
		return
	_ability_cooldown = data.ability_interval
	var wounded: Monster = null
	for other in _allies_within(SHAMAN_HEAL_RADIUS):
		if other.hp < other.max_hp and (wounded == null or other.hp / other.max_hp < wounded.hp / wounded.max_hp):
			wounded = other
	if wounded:
		wounded.heal(wounded.max_hp * data.heal_percent / 100.0, false)
		_pulse(wounded, Color(0.45, 1.0, 0.5))
	for other in _allies_within(SHAMAN_BUFF_RADIUS):
		if other != self:
			other.apply_buff(1.0 + data.buff_percent / 100.0, data.buff_duration)
	play_action(&"attack")


## Усиление урона от шамана (сильнейшее действующее, с обновлением времени).
func apply_buff(multiplier: float, duration: float) -> void:
	_buff_multiplier = maxf(_buff_multiplier, multiplier)
	_buff_left = maxf(_buff_left, duration)
	visual.modulate = base_modulate * Color(1.3, 0.95, 0.8)


func _update_buff(delta: float) -> void:
	if _buff_left <= 0.0:
		return
	_buff_left -= delta
	if _buff_left <= 0.0:
		_buff_multiplier = 1.0
		visual.modulate = base_modulate


func _allies_within(radius: float) -> Array[Monster]:
	var result: Array[Monster] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Monster
		if other and other.is_alive() and absf(other.global_position.x - global_position.x) <= radius:
			result.append(other)
	return result


# --- Босс ---------------------------------------------------------------------------

func _update_boss(delta: float) -> void:
	var abilities := data.boss_abilities
	if abilities.has("slam") and absf(target.global_position.x - global_position.x) <= attack_range + 0.5:
		_slam_cooldown -= delta
		if _slam_cooldown <= 0.0:
			_slam_cooldown = SLAM_INTERVAL / (ENRAGE_SPEED if _enraged else 1.0)
			_slam()
	if abilities.has("summon") and data.summon_id != "":
		_summon_cooldown -= delta
		if _summon_cooldown <= 0.0:
			_summon_cooldown = SUMMON_INTERVAL
			var minion := Database.get_monster(data.summon_id)
			if minion:
				for i in SUMMON_COUNT:
					summon_requested.emit(minion, global_position + Vector3(0.6 + i * 0.7, 0.0, randf_range(-0.3, 0.3)))
				_pulse(self, Color(0.6, 0.5, 1.0))
	if abilities.has("enrage") and not _enraged and hp <= max_hp * ENRAGE_AT:
		_enraged = true
		attack_interval /= ENRAGE_SPEED
		_move_speed *= 1.3
		base_modulate = base_modulate * Color(1.3, 0.7, 0.7)
		visual.modulate = base_modulate


## Сокрушающий удар: красный круг под героем растёт, затем — сильный удар.
func _slam() -> void:
	var ring := _spawn_ring(target.global_position + Vector3(0, 0.03, 0), Color(1.0, 0.25, 0.2, 0.8), 0.4, true)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 3.0, SLAM_WINDUP)
	tween.tween_callback(func() -> void:
		ring.queue_free()
		if is_alive() and target and target.is_alive():
			if not play_action(&"attack"):
				lunge(signf(target.global_position.x - global_position.x))
			var hit := roll_hit(SLAM_DAMAGE * _buff_multiplier)
			target.take_hit(hit.amount, hit.is_crit))


## Урон сначала поглощает щит (у босса с приёмом shield — один раз, на половине здоровья).
func take_hit(amount: float, is_crit := false) -> void:
	if not is_alive():
		return
	if _shield > 0.0:
		var absorbed := minf(_shield, amount)
		_shield -= absorbed
		amount -= absorbed
		if _shield <= 0.0 and _shield_sprite:
			_shield_sprite.queue_free()
			_shield_sprite = null
		if amount <= 0.0:
			_flash()
			return
	super.take_hit(amount, is_crit)
	if data and data.is_boss and data.boss_abilities.has("shield") and not _shield_used and is_alive() and hp <= max_hp * SHIELD_AT:
		_shield_used = true
		_shield = max_hp * SHIELD_SHARE
		_shield_sprite = _spawn_ring(global_position + Vector3(0, visual_height * 0.5, 0.1), Color(0.45, 0.75, 1.0, 0.7), visual_height * 1.3, false)
		_shield_sprite.reparent(self)


# --- Эффекты ------------------------------------------------------------------------

func _add_name_label(height: float) -> void:
	var label := Label3D.new()
	label.text = get_display_name()
	label.modulate = COLOR_BOSS_NAME if data.is_boss else COLOR_ELITE_NAME
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 8
	label.font_size = 36
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Имена соседних элит не должны слипаться — немного разносим их по высоте.
	label.position = Vector3(0, height + 0.5 + (get_instance_id() % 3) * 0.22, 0)
	add_child(label)


## Кольцо-эффект: на земле (flat) или вертикально вокруг (щит).
func _spawn_ring(at: Vector3, color: Color, size: float, flat: bool) -> Sprite3D:
	var ring := Sprite3D.new()
	ring.texture = RING_TEXTURE
	ring.modulate = color
	ring.shaded = false
	ring.no_depth_test = not flat
	ring.pixel_size = size / float(RING_TEXTURE.get_width())
	if flat:
		ring.rotation_degrees = Vector3(-90, 0, 0)
	else:
		ring.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_effects_parent().add_child(ring)
	ring.global_position = at
	return ring


## Вспышка-кольцо над монстром (лечение, призыв).
func _pulse(on: Actor, color: Color) -> void:
	var ring := _spawn_ring(on.global_position + Vector3(0, on.visual_height * 0.5, 0.15), color, on.visual_height, false)
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3.ONE * 1.6, 0.5)
	tween.tween_property(ring, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(ring.queue_free)


func _effects_parent() -> Node:
	var hero := target as Hero
	if hero and hero.effects_parent:
		return hero.effects_parent
	return get_parent()


func _die() -> void:
	remove_from_group(GROUP)
	if _shield_sprite:
		_shield_sprite.queue_free()
	super._die()


func _on_death_animation_finished() -> void:
	queue_free()
