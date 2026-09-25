extends Node
## Проверка связи клиента с сервером карты (сервер должен быть запущен):
##   cd server && set MARCH_SECONDS=2 && npm start
##   Godot.exe --headless --path . -- --autotest --world-test --quit-after-seconds=60
## В консоли должно появиться «WORLDTEST OK».

const ARRIVAL_TIMEOUT_MSEC := 30000

var _errors := PackedStringArray()


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	if _errors.is_empty():
		print("WORLDTEST OK")
	else:
		printerr("WORLDTEST FAILED:\n  " + "\n  ".join(_errors))


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition


func _run() -> void:
	var player_name := "Тест%d" % (randi() % 1_000_000)
	var login := await WorldService.register(player_name, WorldService.DEFAULT_URL)
	if not _check(login.ok, "register failed: %s" % login.get("error", "")):
		return
	_check(WorldService.zones.size() == WorldService.cols * WorldService.rows and WorldService.zones.size() >= 2000,
		"world has %d zones (%dx%d)" % [WorldService.zones.size(), WorldService.cols, WorldService.rows])
	_check(WorldService.is_hero_at_castle(), "hero must start at the castle")

	# Армия из замка → на карту.
	var army := GameState.kingdom.army
	army.add_units({"knight": 30})
	var deploy := await WorldService.deploy({"knight": 30})
	_check(deploy.ok, "deploy failed: %s" % deploy.get("error", ""))
	_check(army.get_count(Database.get_unit("knight")) == 0, "deployed knights still in the castle")
	_check(int(WorldService.get_my_army().get("knight", 0)) == 30, "server army mismatch")

	# Поход в соседнюю зону и захват.
	var castle := WorldService.castle_zone()
	var target := -1
	for zone_id in HexGrid.neighbors(castle, WorldService.cols, WorldService.rows):
		if not WorldService.get_zone(zone_id).castle:
			target = zone_id
			break
	if not _check(target >= 0, "no neighbour zone"):
		return
	var move := await WorldService.move(target)
	_check(move.ok, "move failed: %s" % move.get("error", ""))
	_check(WorldService.is_marching(), "hero must be marching")
	if not await _wait_arrival():
		return
	await WorldService.refresh_world()
	var zone := WorldService.get_zone(target)
	_check(zone.owner != null and int(zone.owner) == WorldService.my_id(), "zone was not captured")
	var bonus_stat: int = StatModifier.Stat.get(str(zone.bonus.stat), -1)
	_check(float(GameState.territory_bonuses.get(bonus_stat, 0.0)) > 0.0, "territory bonus not applied to GameState")

	# Гарнизон.
	var left := await WorldService.garrison({"knight": 5})
	_check(left.ok, "garrison failed: %s" % left.get("error", ""))
	_check(int(WorldService.get_my_garrison(target).get("knight", 0)) == 5, "garrison not stored")
	var back := await WorldService.withdraw({"knight": 5})
	_check(back.ok, "withdraw failed: %s" % back.get("error", ""))

	# Назад в замок и отзыв армии.
	await WorldService.move(castle)
	if not await _wait_arrival():
		return
	var knights := int(WorldService.get_my_army().get("knight", 0))
	var recall := await WorldService.recall({"knight": knights})
	_check(recall.ok, "recall failed: %s" % recall.get("error", ""))
	_check(army.get_count(Database.get_unit("knight")) == knights, "recalled knights not in the castle")
	print("  world flow ok: captured zone #%d, %d knights came home" % [target, knights])


func _wait_arrival() -> bool:
	var start := Time.get_ticks_msec()
	while WorldService.is_marching():
		if Time.get_ticks_msec() - start > ARRIVAL_TIMEOUT_MSEC:
			return _check(false, "march did not finish in time")
		await get_tree().create_timer(0.5, true, false, true).timeout
		await WorldService.refresh_me()
	return true
