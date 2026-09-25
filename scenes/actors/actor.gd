class_name Actor
extends Node3D
## Базовый боец: здоровье, получение урона и «сочная» анимация спрайта
## (покачивание, выпад при атаке, вспышка при попадании, смерть).
## Наследники переопределяют _tick() и _on_death_animation_finished().

signal damaged(amount: float, is_crit: bool)
signal health_changed(current: float, maximum: float)
signal healed(amount: float)
signal died(actor: Actor)

## Спрайты выше этого размера считаются «HD-артом» и фильтруются сглаживанием.
const PIXEL_ART_MAX_HEIGHT := 128

var max_hp := 100.0
var hp := 100.0
var damage := 10.0
var armor := 0.0
var attack_interval := 1.0
var attack_range := 1.5
var crit_chance := 0.0
var crit_multiplier := 2.0
var attack_cooldown := 0.0
## Высота спрайта в мире — нужна эффектам (цифры урона, снаряды).
var visual_height := 1.6

## Базовая поза спрайта (например, «присел отдохнуть»); покачивание накладывается поверх.
var pose_scale := Vector3.ONE
var _is_moving := false
var _time := randf() * TAU
var _alpha_cut_mode := SpriteBase3D.ALPHA_CUT_DISCARD
var _flash_tween: Tween
var _lunge_tween: Tween

@onready var visual: Sprite3D = $Visual
@onready var shadow: MeshInstance3D = $Shadow
@onready var health_bar: HealthBar3D = $HealthBar


## Результат броска урона.
class Hit:
	var amount: float
	var is_crit: bool

	func _init(p_amount: float, p_is_crit: bool) -> void:
		amount = p_amount
		is_crit = p_is_crit


func _process(delta: float) -> void:
	_time += delta
	if is_alive():
		var speed := 10.0 if _is_moving else 3.0
		var wave := sin(_time * speed)
		visual.scale = pose_scale * Vector3(1.0 - wave * 0.025, 1.0 + wave * 0.035, 1.0)
	_tick(delta)


## Логика бойца каждый кадр. Переопределяется в наследниках.
func _tick(_delta: float) -> void:
	pass


func is_alive() -> bool:
	return hp > 0.0


## Ставит спрайт так, чтобы его высота в мире была world_height, а ноги стояли на земле.
func set_sprite(texture: Texture2D, world_height: float, flip: bool) -> void:
	visual_height = world_height
	visual.texture = texture
	visual.centered = true
	visual.pixel_size = world_height / float(texture.get_height())
	visual.offset = Vector2(0.0, texture.get_height() * 0.5)
	visual.flip_h = flip
	visual.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var is_pixel_art := texture.get_height() <= PIXEL_ART_MAX_HEIGHT
	visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if is_pixel_art else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_alpha_cut_mode = SpriteBase3D.ALPHA_CUT_DISCARD if is_pixel_art else SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	visual.alpha_cut = _alpha_cut_mode
	var width := world_height * float(texture.get_width()) / float(texture.get_height())
	shadow.scale = Vector3.ONE * clampf(width * 0.9, 0.5, 3.0)
	health_bar.position.y = world_height + 0.25


## Бросок урона. multiplier — множитель умения, force_crit — гарантированный крит.
func roll_hit(multiplier := 1.0, force_crit := false) -> Hit:
	var is_crit := force_crit or randf() < crit_chance
	var amount := damage * multiplier * randf_range(0.9, 1.1) * (crit_multiplier if is_crit else 1.0)
	return Hit.new(amount, is_crit)


func take_hit(amount: float, is_crit := false) -> void:
	if not is_alive():
		return
	var final_amount := amount * 100.0 / (100.0 + armor)
	hp = maxf(0.0, hp - final_amount)
	damaged.emit(final_amount, is_crit)
	_update_health()
	_flash()
	if hp <= 0.0:
		_die()


## notify = false — без всплывающих цифр (вампиризм, чтобы не спамить).
func heal(amount: float, notify := true) -> void:
	if not is_alive():
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before and notify:
		healed.emit(hp - before)
	_update_health()


## Короткий выпад в сторону цели.
func lunge(direction: float) -> void:
	if _lunge_tween:
		_lunge_tween.kill()
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(visual, "position:x", direction * 0.35, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(visual, "position:x", 0.0, 0.15)


func _update_health() -> void:
	health_changed.emit(hp, max_hp)
	health_bar.set_ratio(hp / max_hp if max_hp > 0.0 else 0.0)


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	visual.modulate = Color(1.0, 0.45, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color.WHITE, 0.2)


func _die() -> void:
	if _flash_tween:
		_flash_tween.kill()
	health_bar.hide()
	visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	died.emit(self)
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_property(visual, "scale", Vector3(1.3, 0.2, 1.0), 0.5)
	tween.tween_property(shadow, "transparency", 1.0, 0.5)
	tween.chain().tween_callback(_on_death_animation_finished)


## Восстанавливает внешний вид после смерти (используется героем).
func _reset_visual() -> void:
	visual.modulate = Color.WHITE
	visual.scale = Vector3.ONE
	visual.position = Vector3.ZERO
	visual.alpha_cut = _alpha_cut_mode
	shadow.transparency = 0.0
	health_bar.show()


func _on_death_animation_finished() -> void:
	pass
