extends Node
## Корневая сцена: показывает создание героя или бой.
##
## Аргументы для разработки (пишутся после « -- »):
##   --autotest              отдельное свежее сохранение, герой создаётся автоматически
##   --class=archer          класс героя для автотеста
##   --level=10              уровень героя для автотеста
##   --wave=11               начать с этой волны (проверка биомов и боссов)
##   --open-inventory        сразу открыть инвентарь (для скриншотов)
##   --open-talents          сразу открыть таланты (для скриншотов)
##   --open-kingdom          сразу открыть королевство (для скриншотов)
##   --open-army             сразу открыть вкладку «Армия» (для скриншотов)
##   --open-map              сразу открыть мировую карту
##   --world-test            проверка связи с сервером карты (tests/world_test.gd; сервер должен быть запущен)
##   --preview-anim=имя:кадр  показать кадр анимации героя (проверка артов; с --timescale=0.01 мир почти замирает)
##   --tired                 бодрость на нуле — герой сразу уходит отдыхать
##   --selftest              прогнать проверку логики предметов (tests/self_test.gd)
##   --timescale=4           ускорить время
##   --screenshot=путь.png   сохранить скриншот через 6 секунд и выйти
##   --quit-after-seconds=N  выйти через N секунд

const CREATION_SCENE := preload("res://scenes/creation/character_creation.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
const SELF_TEST_SCRIPT := preload("res://tests/self_test.gd")
const WORLD_TEST_SCRIPT := preload("res://tests/world_test.gd")
const SCREENSHOT_DELAY := 6.0

var _current: Node


func _ready() -> void:
	var args := _parse_user_args()
	if GameState.autotest and not GameState.has_character():
		var class_id: String = args.get("class", Database.classes[0].id)
		GameState.create_character(tr("Тест"), class_id)
		GameState.level = int(args.get("level", 1))
		if args.has("wave"):
			GameState.wave = maxi(1, int(args.wave))
			GameState.best_wave = GameState.wave
			GameState.progress.run_best_wave = GameState.wave
	if args.has("tired"):
		for need in Database.needs:
			if need.restored_by_rest:
				GameState.needs.values[need.id] = 0.0
	if args.has("timescale"):
		Engine.time_scale = float(args.timescale)

	if GameState.has_character():
		_show_battle()
	else:
		_show_creation()
	Settings.language_changed.connect(_on_language_changed)
	GameState.prestiged.connect(_on_prestiged)

	if args.has("open-inventory") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).inventory_panel.open.call_deferred()
	if args.has("open-talents") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).talent_grid.open.call_deferred()
	if args.has("open-kingdom") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).kingdom_panel.open.call_deferred()
	if args.has("open-army") and _current.has_node("HUD"):
		var hud := _current.get_node("HUD") as Hud
		hud.kingdom_panel.tabs.current_tab = 1
		hud.kingdom_panel.open.call_deferred()
	if args.has("open-guild") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).guild_panel.show_tab.call_deferred(int(args.get("guild-tab", 0)))
	if args.has("open-journal") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).journal_panel.show_tab.call_deferred(int(args.get("journal-tab", 0)))
	if args.has("open-settings") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).settings_panel.open.call_deferred()
	if args.has("open-map") and _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).world_map.open.call_deferred()
	if args.has("world-test"):
		var world_test := Node.new()
		world_test.set_script(WORLD_TEST_SCRIPT)
		add_child(world_test)
	if args.has("preview-anim") and _current.has_node("Hero"):
		_preview_animation.call_deferred(_current.get_node("Hero") as Hero, str(args["preview-anim"]))
	if args.has("selftest"):
		var self_test := Node.new()
		self_test.set_script(SELF_TEST_SCRIPT)
		add_child(self_test)
	if args.has("screenshot"):
		_take_screenshot_later(str(args.screenshot))
	if args.has("quit-after-seconds"):
		get_tree().create_timer(float(args["quit-after-seconds"]), true, false, true).timeout.connect(get_tree().quit)


## Тексты, собранные кодом, проще всего обновить, пересоздав текущий экран (прогресс хранится в GameState).
func _on_language_changed() -> void:
	if _current is CharacterCreation:
		_show_creation()
		return
	_show_battle()
	if _current.has_node("HUD"):
		(_current.get_node("HUD") as Hud).settings_panel.open.call_deferred()


## После перерождения бой начинается заново с новой волны; окно пути открывается на перерождении.
func _on_prestiged(gained: int) -> void:
	_show_battle()
	WorldService.report_hero_level()
	if _current.has_node("HUD"):
		var hud := _current.get_node("HUD") as Hud
		hud.journal_panel.show_tab.call_deferred(3)
		hud.show_message.call_deferred(tr("Новая жизнь! Получено душ: %d") % gained)


func _show_creation() -> void:
	var creation: CharacterCreation = _replace_current(CREATION_SCENE)
	creation.character_created.connect(_show_battle)


func _show_battle() -> void:
	_replace_current(BATTLE_SCENE)


func _replace_current(scene: PackedScene) -> Node:
	if _current:
		_current.queue_free()
	_current = scene.instantiate()
	add_child(_current)
	return _current


## Ставит героя в заданный кадр анимации и замораживает её (для проверки артов).
func _preview_animation(hero: Hero, spec: String) -> void:
	var parts := spec.split(":")
	var animation := StringName(parts[0])
	hero.finish_walk()
	if not hero.play_action(animation):
		push_warning("No animation '%s'" % animation)
		return
	hero.visual.set_frame_and_progress(int(parts[1]) if parts.size() > 1 else 0, 0.0)
	hero.visual.pause()


func _take_screenshot_later(path: String) -> void:
	await get_tree().create_timer(SCREENSHOT_DELAY, true, false, true).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Screenshot saved: ", path)
	get_tree().quit()


func _parse_user_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var clean := arg.trim_prefix("--")
		var parts := clean.split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
