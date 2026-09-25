extends Node
## Быстрая проверка логики предметов и сохранений.
## Запуск: Godot.exe --headless --path . -- --autotest --selftest --quit-after-seconds=3
## В консоли должно появиться «SELFTEST OK».

var _errors := PackedStringArray()


func _ready() -> void:
	await get_tree().process_frame
	_test_data_loaded()
	_test_loot()
	_test_equip()
	_test_upgrade()
	_test_fusion()
	_test_save_load()
	_test_skill_data()
	_test_talents()
	_test_kingdom()
	_test_needs()
	_test_army()
	await _test_skill_casting()
	if _errors.is_empty():
		print("SELFTEST OK")
	else:
		printerr("SELFTEST FAILED:\n  " + "\n  ".join(_errors))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _test_data_loaded() -> void:
	_check(Database.classes.size() >= 3, "classes not loaded")
	_check(Database.monsters.size() >= 3, "monsters not loaded")
	_check(Database.items.size() >= 6, "items not loaded")
	_check(GameState.has_character(), "autotest character not created")
	_check(GameState.equipment.has(ItemBase.Slot.WEAPON), "starter weapon not equipped")


func _test_loot() -> void:
	var counts := [0, 0, 0, 0, 0]
	for i in 2000:
		counts[LootGenerator.roll_tier(20)] += 1
	_check(counts[Item.Tier.COMMON] > counts[Item.Tier.RARE], "tier weights look wrong: %s" % str(counts))
	var boss: MonsterData = Database.get_monsters_for_wave(10, true)[0]
	for i in 20:
		var item := LootGenerator.roll_drop(boss, 10)
		_check(item != null and item.tier >= Item.Tier.UNCOMMON, "boss must always drop uncommon+")


func _test_equip() -> void:
	var armor_base := Database.get_items_for_slot(ItemBase.Slot.ARMOR)[0]
	var armor := LootGenerator.create_item(armor_base, Item.Tier.RARE, 5)
	GameState.add_item(armor)
	var hp_before: float = GameState.get_hero_stats().max_hp
	_check(GameState.equip(armor), "cannot equip armor")
	_check(GameState.get_hero_stats().max_hp > hp_before, "armor did not increase max_hp")
	_check(not GameState.inventory.has(armor), "equipped item still in bag")
	_check(GameState.unequip(ItemBase.Slot.ARMOR), "cannot unequip armor")
	_check(GameState.inventory.has(armor), "unequipped item not in bag")


func _test_upgrade() -> void:
	GameState.add_gold(10_000_000)
	var item := LootGenerator.create_item(Database.items[0], Item.Tier.COMMON, 1)
	GameState.add_item(item)
	var damage_before := item.get_stats().duplicate()
	for i in 100:
		ItemUpgrader.try_upgrade(item)
	_check(item.upgrade_level == Item.MAX_UPGRADE_LEVEL, "upgrade did not reach max: %d" % item.upgrade_level)
	_check(ItemUpgrader.try_upgrade(item) == ItemUpgrader.Result.MAX_LEVEL, "upgrade above max allowed")
	for key: String in damage_before:
		_check(float(item.get_stats()[key]) > float(damage_before[key]), "upgrade did not raise " + key)


func _test_fusion() -> void:
	var base := Database.get_items_for_slot(ItemBase.Slot.HELMET)[0]
	var parts: Array[Item] = []
	for i in 3:
		var part := LootGenerator.create_item(base, Item.Tier.RARE, 7)
		parts.append(part)
		GameState.add_item(part)
	_check(ItemUpgrader.can_fuse(parts[0]), "fusion not available with 3 rare helmets")
	var result := ItemUpgrader.fuse(parts[0])
	_check(result != null and result.tier == Item.Tier.EPIC, "fusion did not produce epic")
	for part in parts:
		_check(not GameState.inventory.has(part), "fusion ingredient not consumed")


func _test_skill_data() -> void:
	for class_data in Database.classes:
		_check(class_data.skills.size() == 3, "%s: expected 3 skills, got %d" % [class_data.id, class_data.skills.size()])
		for skill in class_data.skills:
			_check(skill != null and skill.effect != null and skill.icon != null,
				"%s: broken skill resource" % class_data.id)


func _test_talents() -> void:
	for class_data in Database.classes:
		var class_tree := class_data.talent_tree
		_check(class_tree != null, "%s: no talent tree" % class_data.id)
		if class_tree == null:
			continue
		var talents := class_tree.get_talents()
		_check(talents.size() == class_tree.grid_size.x * class_tree.grid_size.y,
			"%s: grid has %d nodes" % [class_data.id, talents.size()])
		_check(talents.size() >= 590, "%s: expected ~600 talents" % class_data.id)
		var ids := {}
		var kinds := {}
		for talent in talents:
			_check(not ids.has(talent.id), "duplicate talent id " + talent.id)
			ids[talent.id] = true
			kinds[talent.kind] = int(kinds.get(talent.kind, 0)) + 1
			_check(talent.get_icon() != null, "talent without icon: " + talent.id)
			_check(not talent.get_description(1).contains("{"), "unfilled description: " + talent.id)
		_check(int(kinds.get(TalentData.Kind.START, 0)) == 1, "%s: exactly one start node" % class_data.id)
		_check(int(kinds.get(TalentData.Kind.KEYSTONE, 0)) == class_tree.keystones.size(), "%s: keystones not placed" % class_data.id)
		_check(int(kinds.get(TalentData.Kind.NOTABLE, 0)) >= 20, "%s: too few notables" % class_data.id)

	var tree := GameState.get_talent_tree()
	GameState.talent_ranks.clear()
	GameState._on_talents_updated()
	GameState.level = 30
	GameState.add_gold(1_000_000)
	var start := tree.get_start()
	_check(GameState.get_talent_rank(start) == 1, "start node must be learned")
	var neighbor := tree.neighbors(start)[0]
	var far := tree.at(Vector2i.ZERO)
	_check(GameState.can_learn_talent(neighbor), "neighbour of start must be learnable")
	_check(not GameState.can_learn_talent(far), "far node learnable without a path")
	var stats_before := GameState.get_hero_stats()
	_check(GameState.learn_talent(neighbor), "cannot learn neighbour of start")
	_check(not GameState.learn_talent(neighbor), "learned the same node twice")
	_check(GameState.get_talent_bonus(neighbor.modifiers[0].stat) > 0.0, "talent bonus not applied")
	_check(GameState.get_hero_stats() != stats_before or neighbor.modifiers[0].stat >= StatModifier.Stat.CLICK_POWER,
		"talent did not change hero stats")
	# Цепочка: следующий узел за изученным становится доступен.
	var next: TalentData = null
	for candidate in tree.neighbors(neighbor):
		if GameState.get_talent_rank(candidate) == 0:
			next = candidate
			break
	_check(next != null and GameState.can_learn_talent(next), "path does not extend from learned node")

	# Бонус ключевого таланта к конкретному умению не действует на остальные.
	for keystone in tree.keystones:
		for modifier in keystone.modifiers:
			if modifier.skill_id != "" and modifier.stat == StatModifier.Stat.SKILL_DAMAGE:
				talent_rank_force(keystone, 1)
				_check(GameState.get_skill_power(modifier.skill_id) > 1.0, "keystone not applied to " + modifier.skill_id)
				_check(is_equal_approx(GameState.get_skill_power("__other__"), 1.0 + GameState.get_bonus(StatModifier.Stat.SKILL_DAMAGE) / 100.0),
					"skill-specific keystone leaked to other skills")

	GameState.save_game()
	var spent := GameState.get_talent_points_spent()
	GameState.load_game()
	_check(GameState.get_talent_points_spent() == spent, "talents lost after load")
	_check(GameState.reset_talents(), "talent reset failed")
	_check(GameState.get_talent_points_spent() == 0, "talents not cleared after reset")
	_check(is_equal_approx(GameState.get_talent_bonus(neighbor.modifiers[0].stat), 0.0), "bonus remains after reset")

## Состояние замка, как его присылает сервер (Game.playerView().kingdom).
func _server_view(levels: Dictionary, resources: Dictionary, army := {}) -> Dictionary:
	var view := {
		"resources": resources,
		"levels": levels,
		"construction": null,
		"army": {"units": {}, "queue": [], "starving": false, "capacity": 0, "housingUsed": 0,
			"upkeep": 0.0, "attack": 0.0, "defense": 0.0, "powerMultiplier": 1.0, "trainTimes": {}},
	}
	(view.army as Dictionary).merge(army, true)
	return view


## Замок — зеркало сервера: правила экономики проверяют тесты сервера (server/test/kingdom.test.ts).
func _test_kingdom() -> void:
	var kingdom := GameState.kingdom
	_check(Database.buildings.size() >= 9, "buildings not loaded")
	kingdom.reset()
	var town_hall := Database.get_building("town_hall")
	var farm := Database.get_building("farm")
	var forge := Database.get_building("forge")
	_check(kingdom.get_level(town_hall) == 1, "town hall must start at level 1")
	_check(not kingdom.can_upgrade(farm), "actions must be blocked until the server state arrives")
	_check(kingdom.get_upgrade_block_reason(farm).contains("сервер"), "no 'server' reason before sync")

	var rich := {"food": 200.0, "water": 200.0, "wood": 200.0, "stone": 200.0, "gold": 1000.0}
	kingdom.apply_server(_server_view({"town_hall": 1, "farm": 1}, rich))
	_check(kingdom.synced, "kingdom not synced after apply_server")
	_check(kingdom.get_level(farm) == 1, "levels not applied from the server")
	_check(is_equal_approx(kingdom.get_resource("gold"), 1000.0), "treasury not applied")
	_check(kingdom.get_storage_capacity("gold") > kingdom.get_storage_capacity("food"), "treasury must hold more")
	_check(kingdom.get_upgrade_block_reason(farm).contains("Ратуша"), "town hall limit not enforced")
	_check(kingdom.can_upgrade(Database.get_building("well")), "well must be buildable")

	# Между ответами сервера производство показывается плавно, но не выше склада.
	var food_before := kingdom.get_resource("food")
	kingdom.tick(60.0)
	_check(kingdom.get_resource("food") > food_before, "no predicted production")
	kingdom.tick(100000.0)
	_check(kingdom.get_resource("food") <= kingdom.get_storage_capacity("food") + 0.01, "prediction exceeded storage")

	# Стройка с сервера: занятые строители, прогресс по времени.
	var now := WorldService.server_now_ms()
	var view := _server_view({"town_hall": 1, "farm": 1}, rich)
	view.construction = {"id": "well", "level": 1, "startedAt": now - 5000.0, "finishAt": now + 5000.0}
	kingdom.apply_server(view)
	_check(kingdom.is_constructing() and not kingdom.can_upgrade(forge), "second construction allowed while building")
	_check(kingdom.get_construction_ratio() > 0.3 and kingdom.get_construction_ratio() < 0.7, "construction ratio wrong")
	_check(not kingdom.needs_refresh(), "refresh requested before the construction ends")
	view.construction.finishAt = now - 1.0
	kingdom.apply_server(view)
	_check(kingdom.needs_refresh(), "no refresh when the construction time is over")

	# Достроенное здание: сигнал и бонус к герою.
	var finished := []
	kingdom.construction_finished.connect(func(building: BuildingData, _level: int) -> void: finished.append(building.id))
	var damage_before: float = GameState.get_hero_stats().damage
	kingdom.apply_server(_server_view({"town_hall": 3, "farm": 1, "forge": 3}, rich))
	_check(finished.has("forge"), "construction_finished not emitted")
	_check(GameState.get_bonus(StatModifier.Stat.DAMAGE) >= 9.0, "forge bonus not applied")
	_check(GameState.get_hero_stats().damage > damage_before, "forge did not raise hero damage")

	# Отчёт «пока вас не было»: первое состояние с сервера сравнивается с кэшем из сохранения.
	GameState.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	data.saved_at = Time.get_unix_time_from_system() - 3600.0
	FileAccess.open(GameState.save_path, FileAccess.WRITE).store_string(JSON.stringify(data))
	GameState.load_game()
	_check(not kingdom.synced, "cache from the save must not count as server state")
	_check(kingdom.get_level(forge) == 3, "cached building levels lost after load")
	var richer := rich.duplicate()
	richer.food = 250.0
	# Сцена боя показывает отчёт и сразу очищает его, поэтому ловим сигналами.
	var reports := []
	var ready := []
	var capture := func(changes: Dictionary) -> void: reports.append(changes)
	var mark_ready := func() -> void: ready.append(true)
	kingdom.first_sync.connect(capture, CONNECT_ONE_SHOT)
	GameState.offline_report_ready.connect(mark_ready, CONNECT_ONE_SHOT)
	kingdom.apply_server(_server_view({"town_hall": 3, "farm": 1, "forge": 3, "sawmill": 1}, richer, {"units": {"militia": 4}}))
	var report: Dictionary = reports[0] if not reports.is_empty() else {}
	_check(not ready.is_empty(), "offline report not produced after 1h")
	_check((report.get("built", []) as Array).size() == 1, "offline report missing the new building")
	_check(int((report.get("trained", {}) as Dictionary).get("militia", 0)) == 4, "offline report missing trained units")
	GameState.offline_report = {}


func _test_needs() -> void:
	var needs := GameState.needs
	var kingdom := GameState.kingdom
	var hunger: NeedData = null
	var energy: NeedData = null
	for need in Database.needs:
		if need.consumes_resource == "food":
			hunger = need
		if need.restored_by_rest:
			energy = need
	_check(hunger != null and energy != null, "hunger/energy needs not loaded")
	if hunger == null or energy == null:
		return
	needs.reset()
	_check(needs.get_level(hunger) == NeedsState.Level.SATISFIED, "needs must start satisfied")

	# Автоматическая еда со склада (склад известен после ответа сервера).
	kingdom.apply_server(_server_view({"town_hall": 1}, {"food": 10.0, "water": 10.0}))
	needs.values[hunger.id] = 50.0
	needs.tick(0.01)
	_check(needs.get_value(hunger) > 60.0, "hero did not eat automatically")
	_check(kingdom.get_resource("food") < 10.0, "food not consumed")

	# Голод без еды — штраф.
	kingdom.resources["food"] = 0.0
	needs.values[hunger.id] = 0.0
	needs.tick(0.01)
	_check(needs.get_level(hunger) == NeedsState.Level.LOW, "hunger must be LOW at 0")
	_check(GameState.get_bonus(StatModifier.Stat.DAMAGE) < GameState.get_talent_bonus(StatModifier.Stat.DAMAGE) \
		+ kingdom.get_bonus(StatModifier.Stat.DAMAGE), "hunger penalty not applied")

	# Усталость → отдых → бодрость восстановлена.
	needs.values[energy.id] = 0.0
	_check(needs.needs_rest(), "hero must want rest at 0 energy")
	for i in 200:
		needs.rest_tick(1.0)
	_check(needs.is_rested(), "rest did not restore energy")
	needs.reset()
	kingdom.take_pending_consumption()
	kingdom.reset()


func _test_army() -> void:
	var kingdom := GameState.kingdom
	var army := kingdom.army
	_check(Database.units.size() >= 4, "units not loaded")
	kingdom.reset()
	var militia := Database.get_unit("militia")
	var knight := Database.get_unit("knight")
	var resources := {"food": 500.0, "water": 500.0, "wood": 500.0, "stone": 500.0, "gold": 1000.0}
	kingdom.apply_server(_server_view({"town_hall": 1}, resources))
	_check(not army.is_unlocked(militia), "militia must need barracks")
	_check(army.get_recruit_block_reason(militia, 1) != "", "recruit allowed without barracks")

	var now := WorldService.server_now_ms()
	kingdom.apply_server(_server_view({"town_hall": 2, "barracks": 2}, resources, {
		"units": {"militia": 5},
		"queue": [{"id": "militia", "count": 2, "total": 3, "nextAt": now + 4000.0, "perUnitMs": 8000.0}],
		"capacity": 25, "housingUsed": 7, "upkeep": 0.25, "attack": 15.0, "defense": 10.0, "trainTimes": {"militia": 7600.0},
	}))
	_check(army.is_unlocked(militia), "militia locked with barracks 2")
	_check(not army.is_unlocked(knight), "knight must need stable")
	_check(army.get_count(militia) == 5 and army.get_total_units() == 5, "units not applied from the server")
	_check(army.get_free_capacity() == 18, "free capacity wrong")
	_check(is_equal_approx(army.get_power(), 25.0), "army power not applied")
	_check(is_equal_approx(army.get_training_time(militia), 7.6), "training time not taken from the server")
	var left := army.get_order_time_left(0)
	_check(left > 11.0 and left <= 12.0, "order time left wrong: %f" % left)
	_check(army.get_recruit_block_reason(militia, 19) != "", "capacity limit not enforced")
	_check(army.get_recruit_block_reason(militia, 3) == "", "recruit blocked: " + army.get_recruit_block_reason(militia, 3))
	_check(army.get_max_recruitable(militia) == 18, "max recruitable wrong: %d" % army.get_max_recruitable(militia))

	# Заказ обучен: сигнал.
	var completed := []
	army.order_completed.connect(func(unit: UnitData, count: int) -> void: completed.append([unit.id, count]))
	kingdom.apply_server(_server_view({"town_hall": 2, "barracks": 2}, resources, {"units": {"militia": 7}, "capacity": 25, "housingUsed": 7}))
	_check(completed.size() == 1 and completed[0] == ["militia", 3], "order_completed not emitted: %s" % str(completed))

	# Голод приходит с сервера.
	kingdom.apply_server(_server_view({"town_hall": 2, "barracks": 2}, resources, {"units": {"militia": 7}, "starving": true}))
	_check(army.starving, "starving flag not applied")

	# Еда героя: списывается сразу, на сервер уходит пачкой.
	kingdom.apply_server(_server_view({"town_hall": 1}, resources))
	_check(kingdom.try_consume("food", 3.0), "hero cannot eat with food in storage")
	_check(is_equal_approx(kingdom.get_resource("food"), 497.0), "food not subtracted locally")
	kingdom.apply_server(_server_view({"town_hall": 1}, resources))
	_check(is_equal_approx(kingdom.get_resource("food"), 497.0), "pending consumption must stay subtracted until sent")
	var pending := kingdom.take_pending_consumption()
	_check(is_equal_approx(float(pending.get("food", 0.0)), 3.0), "pending consumption wrong")
	_check(kingdom.take_pending_consumption().is_empty(), "pending consumption not cleared")
	kingdom.reset()


## Ставит ранг напрямую (в обход требований) — только для тестов.
func talent_rank_force(talent: TalentData, rank: int) -> void:
	GameState.talent_ranks[talent.id] = rank
	GameState._on_talents_updated()


## Ждёт монстра в радиусе атаки и по очереди применяет все умения героя.
func _test_skill_casting() -> void:
	var hero := get_tree().get_first_node_in_group(Hero.GROUP) as Hero
	if hero == null:
		_check(false, "hero not found in battle")
		return
	GameState.level = 10  # открыть все умения
	GameState.auto_cast = false
	var caster := hero.skill_caster
	for skill in caster.skills:
		if not await _wait_for_target(hero):
			_check(false, "no monster in range to test '%s'" % skill.id)
			break
		if not hero.is_alive():
			hero.revive()
		caster.reset_cooldowns()
		var damage_before := hero.damage
		_check(caster.try_cast(skill), "cannot cast '%s'" % skill.id)
		_check(caster.get_cooldown_left(skill) > 0.0, "'%s' did not go on cooldown" % skill.id)
		var buff := skill.effect as BuffEffect
		if buff and buff.stat == BuffEffect.Stat.DAMAGE:
			_check(hero.damage > damage_before, "'%s' did not raise damage" % skill.id)
		print("  skill ok: ", skill.id)
	GameState.auto_cast = true


func _wait_for_target(hero: Hero, timeout_msec := 30000) -> bool:
	var start := Time.get_ticks_msec()
	while hero.find_target() == null:
		if Time.get_ticks_msec() - start > timeout_msec:
			return false
		await get_tree().process_frame
	return true


func _test_save_load() -> void:
	var count := GameState.inventory.size()
	var gold := GameState.gold
	var level := GameState.level
	GameState.save_game()
	GameState.load_game()
	_check(GameState.inventory.size() == count, "inventory size changed after load")
	_check(GameState.gold == gold, "gold changed after load")
	_check(GameState.level == level, "level changed after load")
	_check(GameState.equipment.has(ItemBase.Slot.WEAPON), "equipment lost after load")
