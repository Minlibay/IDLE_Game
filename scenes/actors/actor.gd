class_name Actor
extends Node3D
## Базовый боец: здоровье, получение урона и анимация спрайта.
##
## Анимация: у бойца есть SpriteFrames (из tools/build_sprite_frames.gd) с анимациями
## idle/walk/rest (фоновые, зациклены) и действиями attack/hurt/death/victory/<умение> (разовые).
## Если анимаций нет (только статичная картинка), покачивание, выпад и смерть делаются программно.
## Наследники переопределяют _tick() и _on_death_animation_finished().

signal damaged(amount: float, is_crit: bool)
signal health_changed(current: float, maximum: float)
signal healed(amount: float)
signal died(actor: Actor)

## Спрайты выше этого размера считаются «HD-артом» и фильтруются сглаживанием.
const PIXEL_ART_MAX_HEIGHT := 128
const ANIM_IDLE := &"idle"
const ANIM_HURT := &"hurt"
const ANIM_DEATH := &"death"
const DEATH_FADE_TIME := 0.5
## Анимация «ранен» не чаще, чем раз в столько секунд (иначе боец дёргается от каждого удара).
const HURT_MIN_INTERVAL := 1.0

var max_hp := 100.0
var hp := 100.0
var damage := 10.0
var armor := 0.0
## Обычный цвет спрайта (оттенок монстра, элиты); к нему возвращается вспышка удара.
var base_modulate := Color.WHITE
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
## true — у бойца настоящие покадровые анимации (не одна картинка).
var _animated := false
## Фоновая анимация, к которой возвращаемся после действия (idle / walk / rest).
var _base_animation := ANIM_IDLE
var _action_playing := false
var _dying := false
## Якорь корпуса по X для каждой анимации (метаданные SpriteFrames "anchors").
var _anchors: Dictionary = {}
var _last_hurt_time := -INF

@onready var visual: AnimatedSprite3D = $Visual
@onready var shadow: MeshInstance3D = $Shadow
@onready var health_bar: HealthBar3D = $HealthBar


## Результат броска урона.
class Hit:
	var amount: float
	var is_crit: bool

	func _init(p_amount: float, p_is_crit: bool) -> void:
		amount = p_amount
		is_crit = p_is_crit


func _ready() -> void:
	visual.animation_finished.connect(_on_visual_animation_finished)


func _process(delta: float) -> void:
	_time += delta
	if is_alive():
		if _animated:
			visual.scale = pose_scale
		else:
			var speed := 10.0 if _is_moving else 3.0
			var wave := sin(_time * speed)
			visual.scale = pose_scale * Vector3(1.0 - wave * 0.025, 1.0 + wave * 0.035, 1.0)
	_tick(delta)


## Логика бойца каждый кадр. Переопределяется в наследниках.
func _tick(_delta: float) -> void:
	pass


func is_alive() -> bool:
	return hp > 0.0


# --- Внешний вид ------------------------------------------------------------------

## Статичная картинка: высота в мире world_height, ноги на земле.
func set_sprite(texture: Texture2D, world_height: float, flip: bool) -> void:
	var frames := SpriteFrames.new()
	frames.rename_animation(&"default", ANIM_IDLE)
	frames.add_frame(ANIM_IDLE, texture)
	_setup_visual(frames, texture.get_height(), world_height, flip, false)


## Покадровые анимации. Масштаб считается по кадру idle — все анимации одного размера.
func set_sprite_frames(frames: SpriteFrames, world_height: float, flip: bool) -> void:
	var idle := frames.get_frame_texture(ANIM_IDLE, 0)
	_setup_visual(frames, idle.get_height(), world_height, flip, true)


func has_animation(animation: StringName) -> bool:
	return visual.sprite_frames != null and visual.sprite_frames.has_animation(animation)


## Разовое действие (attack, умение, victory...). false — такой анимации нет.
func play_action(animation: StringName) -> bool:
	if _dying or not has_animation(animation):
		return false
	_action_playing = true
	_play(animation)
	return true


## Фоновая анимация (idle / walk / rest). Если её нет — idle.
func set_base_animation(animation: StringName) -> void:
	var target := animation if has_animation(animation) else ANIM_IDLE
	if target == _base_animation:
		return
	_base_animation = target
	if not _action_playing and not _dying:
		_play(_base_animation)


func _setup_visual(frames: SpriteFrames, reference_height: int, world_height: float, flip: bool, animated: bool) -> void:
	visual_height = world_height
	_animated = animated
	_anchors = frames.get_meta("anchors", {})
	visual.sprite_frames = frames
	visual.centered = true
	visual.pixel_size = world_height / float(reference_height)
	visual.flip_h = flip
	visual.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var is_pixel_art := reference_height <= PIXEL_ART_MAX_HEIGHT
	visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if is_pixel_art else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_alpha_cut_mode = SpriteBase3D.ALPHA_CUT_DISCARD if is_pixel_art else SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	visual.alpha_cut = _alpha_cut_mode
	var idle := frames.get_frame_texture(ANIM_IDLE, 0)
	var width := world_height * float(idle.get_width()) / float(reference_height)
	shadow.scale = Vector3.ONE * clampf(width * 0.9, 0.5, 3.0)
	health_bar.position.y = world_height + 0.25
	_base_animation = ANIM_IDLE
	_play(ANIM_IDLE)


## Границы всего, что рисуется у фигуры (спрайт, полоска здоровья, подписи), в мировых координатах.
func get_visual_bounds() -> AABB:
	var box := AABB(global_position, Vector3.ZERO)
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var visual_node := node as VisualInstance3D
		if visual_node and visual_node.is_visible_in_tree():
			box = box.merge(visual_node.global_transform * visual_node.get_aabb())
	return box


func _play(animation: StringName) -> void:
	visual.play(animation)
	# Ноги на земле, корпус — в точке бойца (кадры разных анимаций разной ширины).
	var texture := visual.sprite_frames.get_frame_texture(animation, 0)
	var shift := texture.get_width() * 0.5 - float(_anchors.get(animation, texture.get_width() * 0.5))
	visual.offset = Vector2(-shift if visual.flip_h else shift, texture.get_height() * 0.5)


func _on_visual_animation_finished() -> void:
	if _dying:
		_start_death_fade()
		return
	_action_playing = false
	_play(_base_animation)


# --- Бой --------------------------------------------------------------------------

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
	elif not _action_playing and _time - _last_hurt_time >= HURT_MIN_INTERVAL:
		if play_action(ANIM_HURT):
			_last_hurt_time = _time


## notify = false — без всплывающих цифр (вампиризм, чтобы не спамить).
func heal(amount: float, notify := true) -> void:
	if not is_alive():
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before and notify:
		healed.emit(hp - before)
	_update_health()


## Короткий выпад в сторону цели (для бойцов без анимации атаки).
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
	_flash_tween.tween_property(visual, "modulate", base_modulate, 0.2)


func _die() -> void:
	if _flash_tween:
		_flash_tween.kill()
	health_bar.hide()
	died.emit(self)
	if has_animation(ANIM_DEATH):
		# Сначала анимация смерти, затем исчезновение (_on_visual_animation_finished).
		_dying = true
		_action_playing = true
		_play(ANIM_DEATH)
		return
	_dying = true
	visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "modulate", Color(1, 1, 1, 0), DEATH_FADE_TIME)
	tween.tween_property(visual, "scale", Vector3(1.3, 0.2, 1.0), DEATH_FADE_TIME)
	tween.tween_property(shadow, "transparency", 1.0, DEATH_FADE_TIME)
	tween.chain().tween_callback(_on_death_animation_finished)


func _start_death_fade() -> void:
	visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "modulate", Color(1, 1, 1, 0), DEATH_FADE_TIME)
	tween.tween_property(shadow, "transparency", 1.0, DEATH_FADE_TIME)
	tween.chain().tween_callback(_on_death_animation_finished)


## Восстанавливает внешний вид после смерти (используется героем).
func _reset_visual() -> void:
	_dying = false
	_action_playing = false
	visual.modulate = base_modulate
	visual.scale = Vector3.ONE
	visual.position = Vector3.ZERO
	visual.alpha_cut = _alpha_cut_mode
	shadow.transparency = 0.0
	health_bar.show()
	_play(_base_animation)


func _on_death_animation_finished() -> void:
	pass
