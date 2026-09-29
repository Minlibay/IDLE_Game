extends Node
## Стресс-тест: долгий бой на ускорении + гоняние окон + пересоздание сцены (как при смене языка и перерождении).
## Каждые SAMPLE_SECONDS снимает счётчики (узлы, «осиротевшие» узлы, объекты, ресурсы, память, время кадра)
## и в конце проверяет, что они не растут без остановки — то есть нет утечек.
##
##   Godot.exe --headless --path . -- --autotest --soaktest --timescale=8 --quit-after-seconds=400
## В консоли — таблица и «SOAKTEST OK» (или «SOAKTEST FAILED» с причинами).

## Длительность боя (реальные секунды); переменная окружения SOAK_SECONDS — для быстрых прогонов.
var BATTLE_SECONDS := float(OS.get_environment("SOAK_SECONDS")) if OS.get_environment("SOAK_SECONDS") != "" else 150.0
const SAMPLE_SECONDS := 10.0
## Сколько раз открыть и закрыть каждое окно и сколько раз пересоздать сцену боя.
const PANEL_CYCLES := 30
const RELOAD_CYCLES := 8
## Допустимый рост после пересоздания сцены (узлы и объекты — от исходного уровня).
const MAX_NODE_GROWTH := 150
const MAX_OBJECT_GROWTH := 3000
const MAX_ORPHANS := 0

var _errors := PackedStringArray()
var _main: Node


func _ready() -> void:
	_main = get_parent()
	await _wait(3.0)
	print("SOAK: time | nodes | orphans | objects | resources | static MB | process ms | monsters | effects")
	var baseline := _sample("start")

	# 1. Долгий бой: волны, лут, умения, отдых — счётчики не должны расти бесконечно.
	var samples: Array[Dictionary] = []
	var elapsed := 0.0
	while elapsed < BATTLE_SECONDS:
		await _wait(SAMPLE_SECONDS)
		elapsed += SAMPLE_SECONDS
		samples.append(_sample("battle %ds" % int(elapsed)))
	_check_growth(samples)

	# 2. Окна: открыть и закрыть каждое много раз.
	var hud := _hud()
	if hud:
		for i in PANEL_CYCLES:
			for toggle: Callable in [hud.toggle_inventory, hud.toggle_talents, hud.toggle_kingdom, hud.toggle_guild, hud.toggle_journal, hud.settings_panel.toggle]:
				toggle.call()
				await get_tree().process_frame
				toggle.call()
				await get_tree().process_frame
		_check(DesktopWindow._modal_count == 0, "modal counter leaked after panel cycles: %d" % DesktopWindow._modal_count)
		# Вкладки окон с данными прогресса.
		for tab in 4:
			hud.journal_panel.show_tab(tab)
			await get_tree().process_frame
		hud.journal_panel.close()
	_sample("after panels")
	_measure_costs()

	# 3. Пересоздание сцены боя (так делают смена языка и перерождение) и сама смена языка.
	for i in RELOAD_CYCLES:
		_main.call(&"_show_battle")
		await _wait(0.5)
	Settings.set_language("en")
	await _wait(0.5)
	Settings.set_language("ru")
	await _wait(2.0)
	# После смены языка окно настроек открывается само (так задумано) — закрываем.
	var reloaded_hud := _hud()
	if reloaded_hud:
		reloaded_hud.settings_panel.close()
	# Окна, уничтоженные открытыми при пересоздании сцены, должны вернуть счётчик модальности.
	for toggle_name: String in ["toggle_inventory", "toggle_kingdom", "toggle_talents"]:
		reloaded_hud = _hud()
		if reloaded_hud:
			reloaded_hud.call(toggle_name)
		_main.call(&"_show_battle")
		await _wait(0.5)
	# Сигналы автозагрузок после пересоздания не должны падать на уничтоженных узлах.
	GameState.leveled_up.emit(GameState.level)
	GameState.progress.claimable_added.emit("soak")
	WorldService.me_updated.emit()
	WorldService.login_changed.emit(false)
	await _wait(1.0)
	var after := _sample("after reloads")
	_check(DesktopWindow._modal_count == 0, "modal counter leaked after reloads: %d" % DesktopWindow._modal_count)
	_check(int(after.orphans) <= MAX_ORPHANS, "orphan nodes after reloads: %d" % int(after.orphans))
	_check(int(after.nodes) - int(baseline.nodes) <= MAX_NODE_GROWTH,
		"nodes grew after reloads: %d -> %d" % [int(baseline.nodes), int(after.nodes)])
	_check(int(after.objects) - int(baseline.objects) <= MAX_OBJECT_GROWTH,
		"objects grew after reloads: %d -> %d" % [int(baseline.objects), int(after.objects)])

	if _errors.is_empty():
		print("SOAKTEST OK")
	else:
		printerr("SOAKTEST FAILED:\n  " + "\n  ".join(_errors))
	Sound.quit_game()


## Рост за время боя: вторая половина не должна быть заметно больше первой (идёт в «плато»).
func _check_growth(samples: Array[Dictionary]) -> void:
	if samples.size() < 4:
		return
	var half := samples.size() / 2
	for key: String in ["nodes", "objects", "resources"]:
		var early := 0.0
		var late := 0.0
		for i in samples.size():
			if i < half:
				early = maxf(early, float(samples[i][key]))
			else:
				late = maxf(late, float(samples[i][key]))
		# Допуск: бой колеблется (число монстров, эффекты), но не должен уходить вверх.
		_check(late <= early * 1.25 + 60.0, "%s keep growing in battle: %d -> %d" % [key, int(early), int(late)])
	var orphans := int(samples.back().orphans)
	_check(orphans <= MAX_ORPHANS, "orphan nodes in battle: %d" % orphans)


## Сколько стоят частые операции (мс): обновление вкладок окон и расчёты, которые идут в бою.
func _measure_costs() -> void:
	var hud := _hud()
	if hud == null:
		return
	var costs := []
	hud.journal_panel.open()
	for tab in 4:
		hud.journal_panel.show_tab(tab)
		costs.append(["journal tab %d" % tab, _time(func() -> void: hud.journal_panel.call(&"_refresh"))])
	hud.journal_panel.close()
	hud.guild_panel.open()
	costs.append(["guild panel", _time(func() -> void: hud.guild_panel.call(&"_refresh"))])
	hud.guild_panel.close()
	costs.append(["hud refresh", _time(func() -> void: hud.call(&"_refresh"))])
	costs.append(["hero stats x100", _time(func() -> void:
		for i in 100:
			GameState.get_hero_stats())])
	costs.append(["claimable x100", _time(func() -> void:
		for i in 100:
			GameState.progress.claimable_total())])
	costs.append(["bestiary mult x1000", _time(func() -> void:
		for i in 1000:
			GameState.progress.damage_multiplier_vs("goblin"))])
	for entry: Array in costs:
		print("COST: %-22s %7.2f ms" % [entry[0], entry[1]])


func _time(work: Callable) -> float:
	var start := Time.get_ticks_usec()
	work.call()
	return (Time.get_ticks_usec() - start) / 1000.0


func _sample(label: String) -> Dictionary:
	var battle := _main.get_child(_main.get_child_count() - 1) if _main.get_child_count() > 0 else null
	var monsters := get_tree().get_nodes_in_group(Monster.GROUP).size()
	var effects := 0
	for node in get_tree().root.find_children("Effects", "", true, false):
		effects += node.get_child_count()
	var sample := {
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"memory": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}
	print("SOAK: %-14s | %5d | %3d | %6d | %5d | %6.1f | %5.2f | %3d | %3d" % [label, int(sample.nodes), int(sample.orphans),
		int(sample.objects), int(sample.resources), sample.memory, sample.process, monsters, effects])
	if battle == null:
		_errors.append("no battle scene")
	return sample


func _hud() -> Hud:
	for node in get_tree().root.find_children("HUD", "Hud", true, false):
		return node as Hud
	return null


## Ждёт реальные секунды (при ускоренном времени игры).
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
