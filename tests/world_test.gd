extends Node
## Проверка связи клиента с сервером (сервер должен быть запущен в ускоренном режиме):
##   cd server && set MARCH_SECONDS=2 && set DEV_SPEED=100 && set DB_PATH=data/test_world.db && npm start
##   Godot.exe --headless --path . -- --autotest --world-test --quit-after-seconds=90
## В консоли должно появиться «WORLDTEST OK».
## Сценарий: замок с сервера → стройка казарм → найм ополченцев → армия на карту → захват зоны →
## гарнизон → возвращение в замок; еда героя и взнос золота в казну.

const TIMEOUT_MSEC := 30000

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
	var login := await WorldService.register(player_name, WorldService.LOCAL_URL)
	if not _check(login.ok, "register failed: %s" % login.get("error", "")):
		return
	_check(WorldService.zones.size() == WorldService.cols * WorldService.rows and WorldService.zones.size() >= 2000,
		"world has %d zones (%dx%d)" % [WorldService.zones.size(), WorldService.cols, WorldService.rows])
	_check(WorldService.is_hero_at_castle(), "hero must start at the castle")
	_check(WorldService.my_protection_until() > 0.0, "new player must have newbie protection")

	var kingdom := GameState.kingdom
	var army := kingdom.army
	if not _check(kingdom.synced, "kingdom not received from the server"):
		return
	_check(kingdom.get_level(Database.get_building("town_hall")) == 1, "town hall must be level 1")

	# Стройка казарм на сервере.
	var barracks := Database.get_building("barracks")
	if not _check(kingdom.start_upgrade(barracks), "cannot build barracks: " + kingdom.get_upgrade_block_reason(barracks)):
		return
	if not await _wait_until(func() -> bool: return kingdom.get_level(barracks) == 1, "barracks were not built"):
		return

	# Найм ополченцев на все свободные места.
	var militia := Database.get_unit("militia")
	var count := army.get_free_capacity()
	if not _check(count > 0 and army.recruit(militia, count), "cannot recruit: " + army.get_recruit_block_reason(militia, count)):
		return
	if not await _wait_until(func() -> bool: return army.get_count(militia) == count, "militia were not trained"):
		return

	# Еда героя уходит на сервер.
	var food_before := kingdom.get_resource("food")
	_check(kingdom.try_consume("food", 5.0), "hero cannot eat")
	await WorldService._flush_consumption()
	_check(kingdom.get_resource("food") <= food_before - 4.0, "server did not take the food: %f -> %f" % [food_before, kingdom.get_resource("food")])

	# Взнос золота: лимит сразу после регистрации пуст — золото героя возвращается.
	GameState.add_gold(100)
	var gold_before := GameState.gold
	var deposit := await WorldService.deposit_gold(100)
	_check(GameState.gold == gold_before - int(deposit.get("accepted", 0)), "hero gold mismatch after deposit")

	# Армия из замка → на карту.
	var deploy := await WorldService.deploy({"militia": count})
	_check(deploy.ok, "deploy failed: %s" % deploy.get("error", ""))
	_check(army.get_count(militia) == 0, "deployed militia still in the castle")
	_check(int(WorldService.get_my_army().get("militia", 0)) == count, "server army mismatch")

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
	if not _check(zone.owner != null and int(zone.owner) == WorldService.my_id(), "zone was not captured (militia: %d)" % count):
		return
	var bonus_stat: int = StatModifier.Stat.get(str(zone.bonus.stat), -1)
	_check(float(GameState.territory_bonuses.get(bonus_stat, 0.0)) > 0.0, "territory bonus not applied to GameState")

	# Гарнизон.
	var survivors := int(WorldService.get_my_army().get("militia", 0))
	var left := await WorldService.garrison({"militia": 1})
	_check(left.ok, "garrison failed: %s" % left.get("error", ""))
	_check(int(WorldService.get_my_garrison(target).get("militia", 0)) == 1, "garrison not stored")
	var back := await WorldService.withdraw({"militia": 1})
	_check(back.ok, "withdraw failed: %s" % back.get("error", ""))

	# Назад в замок и возвращение армии в замок.
	await WorldService.move(castle)
	if not await _wait_arrival():
		return
	var recall := await WorldService.recall({"militia": survivors})
	_check(recall.ok, "recall failed: %s" % recall.get("error", ""))
	_check(army.get_count(militia) == survivors, "recalled militia not in the castle")
	print("  world flow ok: barracks built, %d militia trained, zone #%d captured, %d came home" % [count, target, survivors])


func _wait_until(condition: Callable, message: String) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call():
		if Time.get_ticks_msec() - start > TIMEOUT_MSEC:
			return _check(false, message)
		await get_tree().create_timer(0.3, true, false, true).timeout
		await WorldService.refresh_me()
	return true


func _wait_arrival() -> bool:
	return await _wait_until(func() -> bool: return not WorldService.is_marching(), "march did not finish in time")
