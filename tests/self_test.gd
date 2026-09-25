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

func _test_kingdom() -> void:
	var kingdom := GameState.kingdom
	_check(Database.buildings.size() >= 9, "buildings not loaded")
	kingdom.reset()
	var town_hall := Database.get_building("town_hall")
	var farm := Database.get_building("farm")
	var forge := Database.get_building("forge")
	_check(kingdom.get_level(town_hall) == 1, "town hall must start at level 1")
	_check(kingdom.get_level(farm) == 0, "farm must start unbuilt")

	GameState.add_gold(1_000_000)
	for resource_id: String in KingdomState.RESOURCES:
		kingdom.resources[resource_id] = 200.0
	_check(kingdom.start_upgrade(farm), "cannot start farm: " + kingdom.get_upgrade_block_reason(farm))
	_check(not kingdom.can_upgrade(forge), "second construction allowed while building")
	kingdom.simulate(farm.get_build_time(1) + 1.0)
	_check(kingdom.get_level(farm) == 1, "farm not finished by simulate()")
	_check(kingdom.get_production_per_minute("food") > 0.0, "farm does not produce food")

	var food_before := kingdom.get_resource("food")
	var report := kingdom.simulate(600.0)
	_check(kingdom.get_resource("food") > food_before, "no offline food production")
	_check((report.resources as Dictionary).has("food"), "offline report missing food")
	kingdom.simulate(KingdomState.MAX_OFFLINE_SECONDS)
	_check(kingdom.get_resource("food") <= kingdom.get_storage_capacity() + 0.01, "storage capacity exceeded")

	# Уровень зданий ограничен Ратушей.
	kingdom.levels[farm.id] = kingdom.get_town_hall_level()
	_check(kingdom.get_upgrade_block_reason(farm).contains("Ратуша"), "town hall limit not enforced")

	# Бонус здания попадает в характеристики героя.
	var damage_before: float = GameState.get_hero_stats().damage
	kingdom.levels[forge.id] = 3
	kingdom._rebuild_bonuses()
	_check(GameState.get_bonus(StatModifier.Stat.DAMAGE) >= 9.0, "forge bonus not applied")
	_check(GameState.get_hero_stats().damage > damage_before, "forge did not raise hero damage")

	# Оффлайн-прогресс при загрузке.
	kingdom.start_upgrade(Database.get_building("sawmill"))
	GameState.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	data.saved_at = Time.get_unix_time_from_system() - 3600.0
	FileAccess.open(GameState.save_path, FileAccess.WRITE).store_string(JSON.stringify(data))
	GameState.load_game()
	_check(not GameState.offline_report.is_empty(), "offline report not produced after 1h")
	_check(kingdom.get_level(Database.get_building("sawmill")) == 1, "construction not finished offline")
	_check(kingdom.get_level(forge) == 3, "building levels lost after load")
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

	# Автоматическая еда со склада.
	kingdom.resources["food"] = 10.0
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
	kingdom.resources["food"] = 50.0


func _test_army() -> void:
	var kingdom := GameState.kingdom
	var army := kingdom.army
	_check(Database.units.size() >= 4, "units not loaded")
	kingdom.reset()
	var militia := Database.get_unit("militia")
	var knight := Database.get_unit("knight")
	_check(not army.is_unlocked(militia), "militia must need barracks")
	_check(army.get_recruit_block_reason(militia, 1) != "", "recruit allowed without barracks")

	kingdom.levels["barracks"] = 2
	kingdom._rebuild_bonuses()
	for resource_id: String in KingdomState.RESOURCES:
		kingdom.resources[resource_id] = 500.0
	GameState.add_gold(1_000_000)
	_check(army.is_unlocked(militia), "militia locked with barracks 2")
	_check(not army.is_unlocked(knight), "knight must need stable")
	_check(army.get_capacity() >= 20, "barracks did not add army capacity")

	var food_before := kingdom.get_resource("food")
	_check(army.recruit(militia, 5), "cannot recruit 5 militia: " + army.get_recruit_block_reason(militia, 5))
	_check(kingdom.get_resource("food") < food_before, "recruit cost not paid")
	_check(army.get_recruit_block_reason(militia, army.get_capacity()) != "", "capacity limit not enforced")

	# Отмена возвращает ресурсы.
	army.recruit(militia, 2)
	var food_mid := kingdom.get_resource("food")
	army.cancel_order(1)
	_check(kingdom.get_resource("food") > food_mid, "cancel did not refund")

	# Обучение (в том числе через оффлайн-прогресс королевства).
	var report := kingdom.simulate(militia.train_time * 5 + 1.0)
	_check(army.get_count(militia) == 5, "militia not trained: %d" % army.get_count(militia))
	_check(int((report.trained as Dictionary).get("militia", 0)) == 5, "offline report missing trained units")
	var power := army.get_power()
	_check(power > 0.0, "army power is zero")

	# Кузница усиливает армию.
	kingdom.levels["forge"] = 5
	kingdom._rebuild_bonuses()
	_check(army.get_power() > power, "forge did not raise army power")

	# Без еды армия слабеет, но не умирает.
	var fed_power := army.get_power()
	kingdom.resources["food"] = 0.0
	kingdom.simulate(60.0)
	_check(army.starving, "army must starve without food")
	_check(army.get_count(militia) == 5, "starving army lost units")
	_check(army.get_power() < fed_power, "starving did not reduce power")
	kingdom.resources["food"] = 500.0
	kingdom.simulate(1.0)
	_check(not army.starving, "army still starving with food")

	# Задел для карты мира.
	army.remove_units({"militia": 2})
	_check(army.get_count(militia) == 3, "remove_units failed")
	army.add_units({"militia": 2})

	# Сохранение.
	army.recruit(militia, 3)
	GameState.save_game()
	GameState.load_game()
	_check(kingdom.army.get_count(militia) == 5, "army lost after load")
	_check(kingdom.army.queue.size() == 1, "training queue lost after load")
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
