class_name Hero
extends Actor
## Герой игрока: автоматически бьёт ближайшего монстра в радиусе атаки.
## Клик мышкой срезает часть перезарядки — так игрок ускоряет атаки.
## Умения — в дочернем компоненте SkillCaster, временные усиления — баффы (add_buff).

const GROUP := &"hero"
## Какую долю интервала атаки срезает один клик.
const CLICK_COOLDOWN_REDUCTION := 0.3
## Регенерация: доля максимального HP в секунду.
const REGEN_PER_SECOND := 0.01
## Во время отдыха здоровье восстанавливается во столько раз быстрее.
const REST_REGEN_MULTIPLIER := 5.0
const REST_POSE := Vector3(1.1, 0.72, 1.0)
const HEALTH_BAR_COLOR := Color(0.3, 0.85, 0.35)
const PROJECTILE_SCENE := preload("res://scenes/effects/projectile.tscn")


## Временное усиление от умения.
class Buff:
	var id: String
	var stat: int
	var value: float
	var time_left: float


var class_data: CharacterClass
## Куда добавлять снаряды и визуальные эффекты.
var effects_parent: Node
## Бонусы от талантов (см. GameState.get_hero_stats).
var regen_multiplier := 1.0
var click_power := 1.0
var lifesteal := 0.0
## Отдыхает (не атакует, быстрее лечится). Управляет Battle.
var is_resting := false
var _base_stats: Dictionary = {}
var _buffs: Array[Buff] = []
var _click_tween: Tween
var _walk_tween: Tween
var _walk_duration := 0.0

@onready var skill_caster: SkillCaster = $SkillCaster


func setup(p_class: CharacterClass, stats: Dictionary, p_effects_parent: Node) -> void:
	class_data = p_class
	effects_parent = p_effects_parent
	add_to_group(GROUP)
	if p_class.sprite_frames:
		set_sprite_frames(p_class.sprite_frames, p_class.sprite_height, false)
	else:
		set_sprite(p_class.sprite, p_class.sprite_height, false)
	health_bar.set_fill_color(HEALTH_BAR_COLOR)
	apply_stats(stats, true)
	skill_caster.setup(self, p_class)


## Применяет статы из GameState.get_hero_stats(). Процент здоровья сохраняется.
func apply_stats(stats: Dictionary, full_heal := false) -> void:
	_base_stats = stats
	_recalculate_stats(full_heal)


func revive() -> void:
	hp = max_hp
	attack_cooldown = 0.0
	clear_buffs()
	_reset_visual()
	_update_health()


## Герой идёт из точки from в точку to (появление в начале боя и после возрождения).
func walk_in(from: Vector3, to: Vector3, duration: float) -> void:
	position = from
	_is_moving = true
	set_base_animation(&"walk")
	_walk_duration = duration
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "position", to, duration)
	await _walk_tween.finished
	_is_moving = false
	set_base_animation(ANIM_IDLE)


## Мгновенно довести героя до места (например, для просмотра анимаций).
func finish_walk() -> void:
	if _walk_tween and _walk_tween.is_running():
		_walk_tween.custom_step(_walk_duration)


func set_resting(value: bool) -> void:
	is_resting = value
	set_base_animation(&"rest" if value else ANIM_IDLE)
	# Нет анимации отдыха — «присаживаем» статичный спрайт.
	pose_scale = REST_POSE if value and not has_animation(&"rest") else Vector3.ONE
	# Затемнение «сна» — только для статичного спрайта; нарисованная анимация отдыха и так понятна.
	visual.modulate = Color(0.75, 0.75, 0.9) if value and not has_animation(&"rest") else Color.WHITE


func register_click() -> void:
	if not is_alive() or is_resting:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - attack_interval * CLICK_COOLDOWN_REDUCTION * click_power)
	if _click_tween:
		_click_tween.kill()
	_click_tween = create_tween()
	_click_tween.tween_property(visual, "modulate", Color(1.4, 1.4, 1.0), 0.04)
	_click_tween.tween_property(visual, "modulate", Color.WHITE, 0.12)


# --- Цели и снаряды (используются и атакой, и умениями) ------------------------

## Ближайший живой монстр в радиусе (по умолчанию — радиус атаки).
func find_target(max_range := -1.0) -> Monster:
	var targets := find_targets(1, max_range)
	return targets[0] if not targets.is_empty() else null


## До count ближайших живых монстров в радиусе, от ближнего к дальнему.
func find_targets(count: int, max_range := -1.0) -> Array[Monster]:
	var reach := attack_range if max_range < 0.0 else max_range
	var my_x := global_position.x
	var result: Array[Monster] = []
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster and monster.is_alive() and absf(monster.global_position.x - my_x) <= reach:
			result.append(monster)
	result.sort_custom(func(a: Monster, b: Monster) -> bool:
		return absf(a.global_position.x - my_x) < absf(b.global_position.x - my_x))
	if result.size() > count:
		result.resize(count)
	return result


func launch_projectile(target: Monster, hit: Hit, size_scale := 1.0, tint := Color.WHITE,
		texture_override: Texture2D = null, on_impact := Callable(), offset := Vector3.ZERO) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	effects_parent.add_child(projectile)
	var from := global_position + Vector3(0.3, visual_height * 0.55, 0.05) + offset
	var texture := texture_override if texture_override else class_data.projectile_texture
	projectile.launch(from, target, hit, texture, size_scale, tint, on_impact)


# --- Баффы --------------------------------------------------------------------

## Добавляет бафф (BuffEffect.Stat). Повторное применение с тем же id обновляет длительность.
func add_buff(id: String, stat: int, value: float, duration: float) -> void:
	for buff in _buffs:
		if buff.id == id:
			buff.time_left = duration
			return
	var buff := Buff.new()
	buff.id = id
	buff.stat = stat
	buff.value = value
	buff.time_left = duration
	_buffs.append(buff)
	_recalculate_stats()


func has_buffs() -> bool:
	return not _buffs.is_empty()


func clear_buffs() -> void:
	_buffs.clear()
	_recalculate_stats()


func _update_buffs(delta: float) -> void:
	if _buffs.is_empty():
		return
	var expired := false
	for i in range(_buffs.size() - 1, -1, -1):
		_buffs[i].time_left -= delta
		if _buffs[i].time_left <= 0.0:
			_buffs.remove_at(i)
			expired = true
	if expired:
		_recalculate_stats()


## Итоговые статы = статы от уровня и экипировки + активные баффы.
func _recalculate_stats(full_heal := false) -> void:
	if _base_stats.is_empty():
		return
	var damage_bonus := 0.0
	var speed_bonus := 0.0
	var armor_bonus := 0.0
	for buff in _buffs:
		match buff.stat:
			BuffEffect.Stat.DAMAGE:
				damage_bonus += buff.value
			BuffEffect.Stat.ATTACK_SPEED:
				speed_bonus += buff.value
			BuffEffect.Stat.ARMOR:
				armor_bonus += buff.value
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = _base_stats.max_hp
	damage = _base_stats.damage * (1.0 + damage_bonus)
	armor = _base_stats.armor + armor_bonus
	attack_interval = _base_stats.attack_interval / (1.0 + speed_bonus)
	attack_range = _base_stats.attack_range
	crit_chance = _base_stats.crit_chance
	crit_multiplier = _base_stats.crit_multiplier
	regen_multiplier = _base_stats.get("regen_multiplier", 1.0)
	click_power = _base_stats.get("click_power", 1.0)
	lifesteal = _base_stats.get("lifesteal", 0.0)
	if is_alive() or full_heal:
		hp = max_hp if full_heal else max_hp * ratio
	_update_health()


# --- Цикл боя -----------------------------------------------------------------

func _tick(delta: float) -> void:
	if not is_alive():
		return
	_update_buffs(delta)
	if hp < max_hp:
		var rest_bonus := REST_REGEN_MULTIPLIER if is_resting else 1.0
		hp = minf(max_hp, hp + max_hp * REGEN_PER_SECOND * regen_multiplier * rest_bonus * delta)
		_update_health()
	if is_resting:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if attack_cooldown > 0.0:
		return
	var target := find_target()
	if target == null:
		return
	attack_cooldown = attack_interval
	_attack(target)


func _attack(target: Monster) -> void:
	var hit := roll_hit()
	if not play_action(&"attack"):
		lunge(signf(target.global_position.x - global_position.x))
	if class_data.is_ranged():
		launch_projectile(target, hit)
	else:
		target.take_hit(hit.amount, hit.is_crit)


func _die() -> void:
	_buffs.clear()
	super._die()
