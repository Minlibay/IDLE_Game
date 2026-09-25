extends Node3D
## Сцена боя: связывает героя, волны монстров, награды, эффекты и интерфейс.

## Где стоит герой и откуда выходят монстры (доля ширины экрана).
const HERO_SCREEN_X := 0.2
const SPAWN_SCREEN_X := 1.03
## Герой выходит из-за левого края экрана к своей позиции.
const HERO_ENTER_SCREEN_X := -0.03
const HERO_ENTER_TIME := 1.5
## Разброс монстров по глубине, чтобы толпа выглядела объёмнее.
const SPAWN_DEPTH_SPREAD := 0.35
const RESPAWN_DELAY := 2.5
## Сколько секунд земля нового биома проявляется поверх старой.
const GROUND_FADE_TIME := 1.2
## Земля — вертикальная полоса перед героем и монстрами (вид сбоку, как край платформы), без перекоса перспективы.
## Плотность её пикселей (на единицу мира) — как у спрайтов монстров.
const GROUND_TEXELS_PER_UNIT := 52.0
## Доля высоты полосы над линией ног: там травинки и кромка травы, ниже — земля.
const GROUND_SURFACE_SHARE := 0.3
## Полоса позади персонажей (они на глубине от -0.35 до 0.35): их ноги ложатся на траву, как в 2D-играх.
const GROUND_Z := -0.6
const NEXT_WAVE_DELAY := 1.0
## Рост наград с каждой волной.
const XP_GROWTH_PER_WAVE := 1.08
const GOLD_GROWTH_PER_WAVE := 1.07

const MONSTER_SCENE := preload("res://scenes/actors/monster.tscn")
const FLOATING_TEXT_SCENE := preload("res://scenes/effects/floating_text.tscn")
const LOOT_DROP_SCENE := preload("res://scenes/effects/loot_drop.tscn")

const COLOR_HERO_DAMAGE := Color(1.0, 0.35, 0.3)
const COLOR_DAMAGE := Color.WHITE
const COLOR_CRIT := Color(1.0, 0.85, 0.2)
const COLOR_GOLD := Color(1.0, 0.82, 0.3)
const COLOR_HEAL := Color(0.4, 1.0, 0.45)
const COLOR_REST := Color(0.8, 0.8, 1.0)
const REST_ZZZ_INTERVAL := 1.2
const OFFLINE_MESSAGE_DURATION := 7.0

## Герой отдыхает: волны на паузе, восстанавливается бодрость.
var _resting := false
var _zzz_timer := 0.0
var _ground_texture: Texture2D

@onready var camera: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var hero: Hero = $Hero
@onready var monsters_root: Node3D = $Monsters
@onready var effects_root: Node3D = $Effects
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: Hud = $HUD


func _ready() -> void:
	DesktopWindow.set_battle_mode()
	get_viewport().size_changed.connect(_layout)

	hero.setup(GameState.get_class_data(), GameState.get_hero_stats(), effects_root)
	hero.damaged.connect(_on_actor_damaged.bind(hero))
	hero.died.connect(_on_hero_died)
	hero.health_changed.connect(hud.set_hero_health)
	hero.healed.connect(_on_hero_healed)
	hero.skill_caster.skill_cast.connect(_on_skill_cast)
	hud.setup_skills(hero.skill_caster)
	hud.rest_requested.connect(start_rest)

	GameState.stats_changed.connect(_on_stats_changed)
	GameState.leveled_up.connect(_on_leveled_up)

	wave_manager.monster_spawn_requested.connect(_spawn_monster)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	_layout()
	_hero_enter()
	hud.set_hero_health(hero.hp, hero.max_hp)
	hero.set_aura(GameState.get_aura_color())
	_set_ground_for_wave(GameState.wave, false)
	wave_manager.start_wave(GameState.wave)
	_show_offline_report()
	GameState.offline_report_ready.connect(_show_offline_report)


func _process(delta: float) -> void:
	if not hero.is_alive():
		return
	if _resting:
		GameState.needs.rest_tick(delta)
		_zzz_timer -= delta
		# У героя с нарисованной анимацией отдыха «z» уже есть в самом рисунке.
		if _zzz_timer <= 0.0 and not hero.has_animation(&"rest"):
			_zzz_timer = REST_ZZZ_INTERVAL
			_float_text(hero.global_position + Vector3(0.3, hero.visual_height, 0.3), "Zzz", COLOR_REST, 1.0, 0.8, 1.4)
		if GameState.needs.is_rested():
			_end_rest()
		return
	GameState.needs.tick(delta)
	if GameState.needs.needs_rest():
		start_rest()


## Отдых: монстры отступают, волна ставится на паузу до полного восстановления бодрости.
func start_rest() -> void:
	if _resting or not hero.is_alive():
		return
	_resting = true
	_zzz_timer = 0.0
	wave_manager.stop()
	for monster in monsters_root.get_children():
		monster.queue_free()
	hero.set_resting(true)
	hud.set_resting(true)
	hud.show_message(tr("Герой устал и отдыхает…"))


func _end_rest() -> void:
	_resting = false
	hero.set_resting(false)
	hud.set_resting(false)
	hud.show_message(tr("Герой отдохнул и снова в бою!"))
	wave_manager.start_wave(GameState.wave)


func _show_offline_report() -> void:
	var report := GameState.offline_report
	if report.is_empty():
		return
	GameState.offline_report = {}
	var parts := PackedStringArray()
	var gained: Dictionary = report.get("resources", {})
	for resource_id: String in gained:
		parts.append("+%d %s" % [roundi(gained[resource_id]), KingdomState.resource_name(resource_id)])
	var trained: Dictionary = report.get("trained", {})
	for unit_id: String in trained:
		var unit := Database.get_unit(unit_id)
		if unit:
			parts.append(tr("обучено: %s ×%d") % [unit.display_name, int(trained[unit_id])])
	for built: String in report.get("built", []):
		parts.append(tr("построено: ") + built)
	if parts.is_empty():
		return
	hud.show_message(tr("Пока вас не было (%s): %s") % [
		UiFormat.duration(report.get("real_seconds", 0.0)), ", ".join(parts)], OFFLINE_MESSAGE_DURATION)


func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		hero.register_click()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_I:
		hud.toggle_inventory()
	elif key.keycode == KEY_T:
		hud.toggle_talents()
	elif key.keycode == KEY_K:
		hud.toggle_kingdom()
	elif key.keycode == KEY_M:
		hud.toggle_map()
	elif key.keycode == KEY_G:
		hud.toggle_guild()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
		hero.skill_caster.try_cast_index(key.keycode - KEY_1)


func _hero_enter() -> void:
	hero.home_x = _lane_point(HERO_SCREEN_X).x
	hero.walk_in(_lane_point(HERO_ENTER_SCREEN_X), _lane_point(HERO_SCREEN_X), HERO_ENTER_TIME)


func _layout() -> void:
	hero.home_x = _lane_point(HERO_SCREEN_X).x
	hero.position = _lane_point(HERO_SCREEN_X)


## Точка на линии боя (z = 0) под заданной долей ширины экрана.
func _lane_point(screen_x_ratio: float) -> Vector3:
	var size := get_viewport().get_visible_rect().size
	var screen_pos := Vector2(size.x * screen_x_ratio, size.y * 0.75)
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.BACK, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return Vector3.ZERO
	return Vector3((hit as Vector3).x, 0.0, 0.0)


## at — где появиться (помощники босса); по умолчанию — из-за правого края экрана.
func _spawn_monster(data: MonsterData, wave: int, elite_id := "", at: Variant = null) -> void:
	var monster: Monster = MONSTER_SCENE.instantiate()
	monsters_root.add_child(monster)
	var spawn: Vector3 = at if at is Vector3 else _lane_point(SPAWN_SCREEN_X)
	if not at is Vector3:
		spawn.z = randf_range(-SPAWN_DEPTH_SPREAD, SPAWN_DEPTH_SPREAD)
	monster.position = spawn
	monster.setup(data, wave, hero, elite_id)
	monster.summon_requested.connect(func(minion: MonsterData, point: Vector3) -> void:
		_spawn_monster(minion, wave, "", point))
	if monster.is_elite():
		hud.show_message(tr("Элита: %s!") % monster.get_display_name())
	monster.damaged.connect(_on_actor_damaged.bind(monster))
	monster.died.connect(_on_monster_died)
	monster.damaged.connect(_on_monster_damaged)
	wave_manager.register_monster(monster)


func _on_actor_damaged(amount: float, is_crit: bool, actor: Actor) -> void:
	var color := COLOR_HERO_DAMAGE if actor == hero else (COLOR_CRIT if is_crit else COLOR_DAMAGE)
	var text := str(maxi(1, roundi(amount))) + ("!" if is_crit else "")
	# Разброс по X и Y, чтобы цифры частых ударов не слипались в одно число.
	var pos := actor.global_position + Vector3(randf_range(-0.4, 0.4), actor.visual_height + randf_range(0.0, 0.35), 0.3)
	_float_text(pos, text, color, 1.4 if is_crit else 1.0)


func _on_monster_died(actor: Actor) -> void:
	var monster := actor as Monster
	var data := monster.data
	var level := monster.wave_level - 1
	var xp_bonus := (1.0 + GameState.get_bonus(StatModifier.Stat.XP_GAIN) / 100.0) * monster.reward_multiplier
	var gold_bonus := (1.0 + GameState.get_bonus(StatModifier.Stat.GOLD_FIND) / 100.0) * monster.reward_multiplier
	GameState.add_xp(roundi(data.xp_reward * pow(XP_GROWTH_PER_WAVE, level) * xp_bonus))
	if hero.kill_heal > 0.0:
		hero.heal(hero.max_hp * hero.kill_heal, false)
	var gold := roundi(data.gold_reward * pow(GOLD_GROWTH_PER_WAVE, level) * gold_bonus)
	GameState.add_gold(gold)
	_float_text(monster.global_position + Vector3(0.0, monster.visual_height * 0.5, 0.3), tr("+%d з") % gold, COLOR_GOLD, 0.8)

	var item := LootGenerator.roll_drop(data, monster.wave_level,
		GameState.get_bonus(StatModifier.Stat.DROP_CHANCE) / 100.0 + monster.drop_bonus)
	if item == null:
		return
	GameState.add_item(item)
	var drop: LootDrop = LOOT_DROP_SCENE.instantiate()
	effects_root.add_child(drop)
	drop.fly(monster.global_position, hero.global_position, item.get_base().icon, item.get_tier_color())
	_float_text(hero.global_position + Vector3(0.0, hero.visual_height + 0.5, 0.3),
		item.get_base().display_name, item.get_tier_color(), 1.1, 0.6, 1.6)


## Вампиризм: часть урона по монстрам возвращается герою.
func _on_monster_damaged(amount: float, _is_crit: bool) -> void:
	if hero.lifesteal > 0.0:
		hero.heal(amount * hero.lifesteal, false)


func _on_hero_died(_actor: Actor) -> void:
	wave_manager.stop()
	GameState.set_wave(GameState.wave - 1)
	hud.show_message(tr("Герой пал! Отступаем на волну %d") % GameState.wave)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	for monster in monsters_root.get_children():
		monster.queue_free()
	hero.revive()
	_hero_enter()
	wave_manager.start_wave(GameState.wave)


## Земля биома: при смене биома новая проявляется поверх старой (animate), при запуске — сразу.
func _set_ground_for_wave(wave: int, animate: bool) -> void:
	var biome := Database.get_biome_for_wave(wave)
	var texture: Texture2D = biome.ground_texture if biome and biome.ground_texture else null
	if texture == null or texture == _ground_texture:
		return
	_ground_texture = texture
	if ground.material_override == null:
		ground.material_override = (ground.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	if not animate:
		_apply_ground_texture(ground.material_override, texture)
		return
	var overlay := MeshInstance3D.new()
	overlay.mesh = ground.mesh
	var material := (ground.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	_apply_ground_texture(material, texture)
	material.albedo_color = Color(1, 1, 1, 0)
	overlay.material_override = material
	overlay.position = ground.position + Vector3(0, 0, 0.002)
	add_child(overlay)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 1.0, GROUND_FADE_TIME)
	tween.tween_callback(func() -> void:
		_apply_ground_texture(ground.material_override, texture)
		overlay.queue_free())


## Текстура земли: повтор по ширине и высота полосы — так, чтобы пиксели были квадратными и того же
## размера, что у монстров; кромка травы — на линии ног.
func _apply_ground_texture(material: StandardMaterial3D, texture: Texture2D) -> void:
	material.albedo_texture = texture
	var quad := ground.mesh as QuadMesh
	var tile_width := texture.get_width() / GROUND_TEXELS_PER_UNIT
	material.uv1_scale = Vector3(quad.size.x / tile_width, 1.0, 1.0)
	quad.size.y = texture.get_height() / GROUND_TEXELS_PER_UNIT
	ground.position = Vector3(0.0, quad.size.y * (GROUND_SURFACE_SHARE - 0.5), GROUND_Z)


func _on_wave_started(wave: int) -> void:
	_set_ground_for_wave(wave, true)
	var biome := Database.get_biome_for_wave(wave)
	if wave_manager.is_boss_wave(wave):
		var bosses := Database.get_monsters_for_wave(wave, true)
		hud.show_message(tr("Волна %d — БОСС: %s!") % [wave, bosses[0].display_name if not bosses.is_empty() else "?"])
	elif biome and Database.get_wave_in_biome(wave) == 1:
		hud.show_message(tr("%s — волны %d–%d") % [biome.display_name, wave, wave + Database.WAVES_PER_BIOME - 1])


func _on_wave_cleared(wave: int) -> void:
	GameState.set_wave(wave + 1)
	if wave_manager.is_boss_wave(wave):
		GameState.save_game()
	await get_tree().create_timer(NEXT_WAVE_DELAY).timeout
	if not is_inside_tree() or not hero.is_alive() or _resting:
		return
	wave_manager.start_wave(GameState.wave)


func _on_stats_changed() -> void:
	hero.apply_stats(GameState.get_hero_stats())
	hero.set_aura(GameState.get_aura_color())


func _on_leveled_up(new_level: int) -> void:
	hero.apply_stats(GameState.get_hero_stats(), true)
	hero.play_action(&"victory")
	_float_text(hero.global_position + Vector3(0.0, hero.visual_height + 0.3, 0.3),
		tr("Уровень %d!") % new_level, COLOR_GOLD, 1.5, 1.0, 1.5)
	for skill in hero.skill_caster.skills:
		if skill.unlock_level == new_level:
			hud.show_message(tr("Новое умение: %s!") % skill.display_name)


func _on_skill_cast(skill: SkillData) -> void:
	_float_text(hero.global_position + Vector3(0.0, hero.visual_height + 0.5, 0.3),
		skill.display_name, skill.color, 1.2, 0.7, 1.2)


func _on_hero_healed(amount: float) -> void:
	_float_text(hero.global_position + Vector3(0.0, hero.visual_height * 0.7, 0.3),
		"+%d" % roundi(amount), COLOR_HEAL, 1.1)


func _float_text(pos: Vector3, text: String, color: Color, size_scale := 1.0, rise := 0.8, duration := 0.9) -> void:
	var label: FloatingText = FLOATING_TEXT_SCENE.instantiate()
	effects_root.add_child(label)
	label.global_position = pos
	label.show_text(text, color, size_scale, rise, duration)
