extends Node
## Быстрая проверка логики предметов и сохранений.
## Запуск: Godot.exe --headless --path . -- --autotest --selftest --quit-after-seconds=3
## В консоли должно появиться «SELFTEST OK».

var _errors := PackedStringArray()


func _ready() -> void:
	await get_tree().process_frame
	_test_data_loaded()
	_test_loot()
	_test_monsters()
	_test_equip()
	_test_new_slots_and_relics()
	_test_treasures()
	_test_upgrade()
	_test_fusion()
	_test_save_load()
	_test_skill_data()
	_test_talents()
	_test_kingdom()
	_test_needs()
	_test_army()
	await _test_battle_replay()
	await _test_biome_ground()
	await _test_skill_mechanics()
	_test_translation()
	await _test_hero_chase()
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


## Биомы, роли, лимиты ролей в волне, элиты, шаман и щит босса.
func _test_monsters() -> void:
	_check(Database.biomes.size() >= 3, "biomes not loaded")
	_check(Database.get_biome_for_wave(1).id == "forest" and Database.get_biome_for_wave(10).id == "forest", "waves 1-10 must be forest")
	_check(Database.get_biome_for_wave(11).id == "graveyard", "wave 11 must be graveyard")
	_check(Database.get_biome_for_wave(21).id == "mountains", "wave 21 must be mountains")
	_check(Database.get_biome_for_wave(Database.biomes.size() * Database.WAVES_PER_BIOME + 1).id == "forest", "biomes must cycle")
	for biome in Database.biomes:
		var first_wave := biome.order * Database.WAVES_PER_BIOME + 1
		var pool := Database.get_monsters_for_wave(first_wave + 8, false)
		_check(not pool.is_empty() and pool.all(func(m: MonsterData) -> bool: return m.biome == biome.id), "wrong monsters in " + biome.id)
		var roles := {}
		for monster in pool:
			roles[monster.role] = true
		_check(roles.size() == 4, "biome %s must have all 4 roles, has %d" % [biome.id, roles.size()])
		_check(Database.get_monsters_for_wave(first_wave + 9, true).size() == 1, "biome %s must have one boss" % biome.id)

	# Лимиты ролей: шаман один, громил не больше двух (в волне до 8 монстров).
	var manager := WaveManager.new()
	for i in 200:
		var wave := manager.build_wave(9)
		var shamans := wave.filter(func(m: MonsterData) -> bool: return m.role == MonsterData.Role.SHAMAN).size()
		var brutes := wave.filter(func(m: MonsterData) -> bool: return m.role == MonsterData.Role.BRUTE).size()
		if shamans > 1 or brutes > 2:
			_check(false, "role limits broken: %d shamans, %d brutes" % [shamans, brutes])
			break
	var elites := manager.assign_elites(manager.build_wave(40), 40)
	_check(elites.filter(func(e: Dictionary) -> bool: return e.elite != "").size() <= 2, "too many elites")
	manager.free()

	var hero := get_tree().get_first_node_in_group(Hero.GROUP) as Hero
	if hero == null:
		return
	var scene: PackedScene = load("res://scenes/actors/monster.tscn")
	# Элита: сильнее, награды больше, имя с модификатором.
	var goblin_data := Database.get_monster("goblin")
	var elite: Monster = scene.instantiate()
	add_child(elite)
	elite.setup(goblin_data, 5, hero, "stoneskin")
	var normal: Monster = scene.instantiate()
	add_child(normal)
	normal.setup(goblin_data, 5, hero)
	_check(elite.is_elite() and elite.max_hp > normal.max_hp * 2.0 and elite.armor > normal.armor, "elite is not stronger")
	_check(elite.reward_multiplier > 1.0 and elite.get_display_name().begins_with("Каменнокожий"), "elite rewards/name wrong")

	# Шаман лечит раненого и усиливает союзников рядом.
	var shaman: Monster = scene.instantiate()
	add_child(shaman)
	shaman.setup(Database.get_monster("goblin_shaman"), 5, hero)
	shaman.position = Vector3(50, 0, 0)
	normal.position = Vector3(51, 0, 0)
	elite.position = Vector3(200, 0, 0)
	normal.hp = normal.max_hp * 0.3
	shaman._ability_cooldown = 0.0
	shaman._update_shaman(0.1)
	_check(normal.hp > normal.max_hp * 0.3, "shaman did not heal the wounded ally")
	_check(normal._buff_multiplier > 1.0, "shaman did not buff the ally")
	_check(elite._buff_multiplier == 1.0, "shaman buffed a far ally")

	# Щит босса: на половине здоровья урон поглощается.
	var lich: Monster = scene.instantiate()
	add_child(lich)
	lich.setup(Database.get_monster("lich"), 20, hero)
	lich.position = Vector3(300, 0, 0)
	lich.take_hit(lich.max_hp * 0.6 * (100.0 + lich.armor) / 100.0)
	_check(lich._shield > 0.0, "boss shield did not appear at half health")
	var hp_before := lich.hp
	lich.take_hit(lich._shield * 0.5)
	_check(is_equal_approx(lich.hp, hp_before), "shield did not absorb the hit")
	for monster in [elite, normal, shaman, lich]:
		monster.remove_from_group(Monster.GROUP)
		monster.queue_free()
	print("  monsters ok: elite, shaman heal/buff, boss shield")


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


## Плечи, ноги, ботинки и 6 слотов реликвий армии.
func _test_new_slots_and_relics() -> void:
	for slot: int in [ItemBase.Slot.SHOULDERS, ItemBase.Slot.LEGS, ItemBase.Slot.BOOTS]:
		var bases := Database.get_items_for_slot(slot)
		_check(not bases.is_empty(), "no items for slot " + ItemBase.slot_name(slot))
		if bases.is_empty():
			continue
		var item := LootGenerator.create_item(bases[0], Item.Tier.RARE, 5)
		GameState.add_item(item)
		var hp_before: float = GameState.get_hero_stats().max_hp
		var armor_before: float = GameState.get_hero_stats().armor
		_check(GameState.equip(item), "cannot equip " + ItemBase.slot_name(slot))
		_check(GameState.equipment.get(slot) == item, "item not in slot " + ItemBase.slot_name(slot))
		_check(GameState.get_hero_stats().max_hp >= hp_before and GameState.get_hero_stats().armor > armor_before,
			"%s did not raise hero stats" % ItemBase.slot_name(slot))

	var relic_bases := Database.get_items_for_slot(ItemBase.Slot.ARMY)
	_check(relic_bases.size() >= 6, "army relics not loaded: %d" % relic_bases.size())
	if relic_bases.is_empty():
		return
	for i in GameState.army_relics.size():
		if GameState.army_relics[i]:
			GameState.unequip_item(GameState.army_relics[i])
	var banner := Database.get_item_base("war_banner")
	var hero_before: Dictionary = GameState.get_hero_stats()
	var relics: Array[Item] = []
	for i in GameState.ARMY_RELIC_SLOTS:
		var relic := LootGenerator.create_item(banner, Item.Tier.COMMON, 1)
		GameState.add_item(relic)
		_check(GameState.equip(relic), "cannot equip relic %d" % i)
		relics.append(relic)
	_check(not GameState.army_relics.has(null), "relic slots not filled")
	var power := float(GameState.get_army_gear_bonuses().get("ARMY_POWER", 0.0))
	var expected := 0.0
	for relic in relics:
		expected += float(relic.get_stats().army_power)
	_check(is_equal_approx(power, snappedf(expected, 0.1)), "army gear sum wrong: %f vs %f" % [power, expected])
	_check(GameState.get_hero_stats().damage == hero_before.damage, "relics must not change hero stats")

	# Седьмая реликвия заменяет такую же (самую дешёвую), старая уходит в сумку.
	var better := LootGenerator.create_item(banner, Item.Tier.EPIC, 10)
	GameState.add_item(better)
	_check(GameState.equip(better), "cannot replace a relic when all slots are full")
	_check(GameState.army_relics.has(better) and GameState.inventory.size() > 0, "relic replacement failed")
	_check(float(GameState.get_army_gear_bonuses().ARMY_POWER) > power, "better relic did not raise the bonus")

	# Сохранение и снятие.
	GameState.save_game()
	GameState.load_game()
	_check(GameState.army_relics.size() == GameState.ARMY_RELIC_SLOTS and not GameState.army_relics.has(null), "relics lost after load")
	var loaded: Item = GameState.army_relics[0]
	_check(GameState.unequip_item(loaded), "cannot unequip relic")
	_check(GameState.army_relics[0] == null and GameState.inventory.has(loaded), "unequipped relic not in the bag")


## Сокровища: каталог, сеты и их бонусы, аура, синхронизация с сервером, потолки.
func _test_treasures() -> void:
	_check(Database.item_sets.size() >= 24, "treasure sets not loaded: %d" % Database.item_sets.size())
	_check(Database.treasures.size() >= 170, "treasures not loaded: %d" % Database.treasures.size())
	for class_data in Database.classes:
		_check(Database.get_treasures_for_class(class_data.id).size() >= 50, "too few treasures for " + class_data.id)
	_check(not Database.items.any(func(item: ItemBase) -> bool: return item.is_treasure()), "treasures must not drop from monsters")
	var class_id := GameState.class_id
	var item_set: ItemSetData = null
	for candidate: ItemSetData in Database.item_sets.values():
		if candidate.class_id == class_id:
			item_set = candidate
			break
	_check(item_set != null and item_set.get_piece_count() == 5, "no 5-piece set for " + class_id)
	if item_set == null:
		return
	_check(Database.get_item_base(item_set.piece_ids[0]).display_name.length() > 5, "set piece has no name")

	# Сервер прислал 5 частей сета и одно сокровище чужого класса.
	var other: ItemBase = null
	for treasure in Database.treasures:
		if not treasure.can_be_used_by(class_id):
			other = treasure
			break
	var list := []
	for i in item_set.piece_ids.size():
		list.append({"uid": "t%d" % i, "itemId": item_set.piece_ids[i]})
	list.append({"uid": "other", "itemId": other.id})
	var found := GameState.apply_server_treasures(list)
	_check(found.is_empty(), "first sync must not announce old treasures")
	_check(GameState.treasures.size() == 6, "treasures not received: %d" % GameState.treasures.size())

	var damage_before := GameState.get_bonus(StatModifier.Stat.DAMAGE)
	var foreign: Item = GameState.treasures.filter(func(item: Item) -> bool: return item.uid == "other")[0]
	_check(not GameState.equip(foreign), "treasure of another class equipped")
	for item: Item in GameState.treasures.duplicate():
		if item.get_base().set_id == item_set.id:
			_check(GameState.equip(item), "cannot equip set piece " + item.base_id)
	_check(GameState.get_set_piece_count(item_set.id) == 5, "set pieces not counted")
	_check(GameState.get_aura_color() == item_set.color, "full set must give the aura")
	var focus_stat: int = item_set.bonuses[0].modifiers[0].stat
	_check(GameState.get_bonus(focus_stat) > 0.0, "set bonus not applied")
	for key: String in GameState._treasure_bonuses:
		var stat := int(key.get_slice("|", 0))
		_check(float(GameState._treasure_bonuses[key]) <= GameState.TREASURE_BONUS_CAPS.get(stat, GameState.TREASURE_DEFAULT_CAP) + 0.001,
			"treasure bonus above the cap: " + key)
	_check(GameState.get_hero_stats().max_hp > 0.0 and GameState.get_bonus(StatModifier.Stat.DAMAGE) >= damage_before, "hero stats broken")

	# Статы основы растут с рекордом волны.
	var piece: Item = GameState.equipment.get(ItemBase.Slot.HELMET)
	var armor_low: float = piece.get_stats().get("armor", 0.0)
	var best := GameState.best_wave
	GameState.best_wave = best + 50
	_check(float(piece.get_stats().get("armor", 0.0)) > armor_low, "treasure stats do not grow with the best wave")
	GameState.best_wave = best

	# Сервер больше не подтверждает шлем — он снимается; новая находка объявляется.
	list.remove_at(0)
	list.append({"uid": "new1", "itemId": item_set.piece_ids[0]})
	var announced := []
	var capture := func(item: Item) -> void: announced.append(item.base_id)
	GameState.treasure_found.connect(capture)
	GameState.apply_server_treasures(list)
	GameState.treasure_found.disconnect(capture)
	_check(GameState.get_set_piece_count(item_set.id) == 4, "unconfirmed treasure still equipped")
	_check(GameState.get_aura_color().a == 0.0, "aura must disappear without the full set")
	_check(announced == [item_set.piece_ids[0]], "new treasure not announced: %s" % str(announced))

	# Сохранение: надетые сокровища остаются.
	GameState.save_game()
	GameState.load_game()
	_check(GameState.get_set_piece_count(item_set.id) == 4, "equipped treasures lost after load")
	for slot: int in GameState.equipment.keys():
		if GameState.equipment[slot].is_treasure():
			GameState.equipment.erase(slot)
	GameState.apply_server_treasures([])
	GameState.stats_changed.emit()


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


## По умению на каждую цифру 1–9: открываются на 1, 10, 20 … 80 уровне.
func _test_skill_data() -> void:
	var expected_levels := [1, 10, 20, 30, 40, 50, 60, 70, 80]
	for class_data in Database.classes:
		_check(class_data.skills.size() == 9, "%s: expected 9 skills, got %d" % [class_data.id, class_data.skills.size()])
		var levels := []
		for skill in class_data.skills:
			_check(skill != null and skill.effect != null and skill.icon != null,
				"%s: broken skill resource" % class_data.id)
			if skill:
				levels.append(skill.unlock_level)
		levels.sort()
		_check(levels == expected_levels, "%s: unlock levels %s" % [class_data.id, str(levels)])


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
			"upkeep": 0.0, "attack": 0.0, "defense": 0.0, "attackMultiplier": 1.0, "defenseMultiplier": 1.0, "trainTimes": {}},
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


## Повтор боя: погибает столько фигурок, сколько потерь в отчёте; у проигравшего на карте — все.
func _test_battle_replay() -> void:
	var replay: BattleReplay = load("res://scenes/world/battle_replay.tscn").instantiate()
	get_tree().root.add_child(replay)
	var report := {"id": 42, "createdAt": 0, "data": {
		"kind": "battle", "zoneId": 1, "tier": 1, "won": true, "text": "Нейтралы разбиты",
		"attacker": {"name": "Я", "army": {"militia": 100, "archer": 20}, "lost": {"militia": 50}, "power": 500, "heroLevel": 3},
		"defender": {"name": "Нейтралы", "army": {"spearman": 30}, "lost": {"spearman": 30}, "power": 240, "heroLevel": 0},
	}}
	_check(BattleReplay.can_replay(report), "battle report must be replayable")
	_check(not BattleReplay.can_replay({"id": 1, "data": {"kind": "capture", "text": "x"}}), "capture without battle is not replayable")
	replay.play(report)
	await get_tree().process_frame
	await get_tree().process_frame
	var attacker := replay.get_side_stats("attacker")
	var defender := replay.get_side_stats("defender")
	_check(attacker.figures <= BattleReplay.MAX_FIGURES_PER_SIDE + 1, "too many figures: %d" % attacker.figures)
	replay.skip()
	attacker = replay.get_side_stats("attacker")
	defender = replay.get_side_stats("defender")
	_check(defender.dead == defender.figures, "loser must lose every figure: %s" % str(defender))
	_check(attacker.dead == attacker.planned_deaths and attacker.dead > 0, "attacker deaths wrong: %s" % str(attacker))
	_check(attacker.dead < attacker.figures, "winner must keep survivors (and the hero)")
	# Повтор одинаков при каждом просмотре.
	replay.play(report)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(replay.get_side_stats("attacker").planned_deaths == attacker.planned_deaths, "replay is not deterministic")
	replay.close()
	replay.queue_free()


## Земля меняется по биомам: плавно проявляется поверх старой.
func _test_biome_ground() -> void:
	var battle := get_tree().get_first_node_in_group(Hero.GROUP).get_parent() if get_tree().get_first_node_in_group(Hero.GROUP) else null
	if battle == null or not battle.has_method("_set_ground_for_wave"):
		return
	var wave := 3 * Database.WAVES_PER_BIOME + 5
	battle._set_ground_for_wave(wave, true)
	await get_tree().create_timer(battle.GROUND_FADE_TIME + 0.3).timeout
	var material := battle.ground.material_override as StandardMaterial3D
	_check(material != null and material.albedo_texture == Database.get_biome_for_wave(wave).ground_texture, "ground did not change to the biome")
	battle._set_ground_for_wave(GameState.wave, false)


## Герой ближнего боя сам идёт к дальнему стрелку, а после его смерти возвращается на свою точку.
func _test_hero_chase() -> void:
	var hero := get_tree().get_first_node_in_group(Hero.GROUP) as Hero
	if hero == null or hero.attack_range >= 6.0:
		return  # стрелки (лучник, маг) и так достают дальних врагов
	var battle := hero.get_parent()
	battle.wave_manager.stop()
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		node.remove_from_group(Monster.GROUP)
		node.queue_free()
	await get_tree().process_frame
	hero.revive()
	hero.finish_walk()
	hero.global_position.x = hero.home_x
	var archer: Monster = load("res://scenes/actors/monster.tscn").instantiate()
	battle.monsters_root.add_child(archer)
	archer.setup(Database.get_monster("goblin_archer"), 1, hero)
	archer.max_hp = 1.0e9
	archer.hp = archer.max_hp
	archer.damage = 0.0
	archer.global_position = Vector3(hero.home_x + 7.0, 0.0, 0.0)
	var reached := await _wait_for(func() -> bool: return absf(archer.global_position.x - hero.global_position.x) <= hero.attack_range, 5.0)
	_check(reached, "hero did not walk to the ranged monster")
	archer.remove_from_group(Monster.GROUP)
	archer.queue_free()
	var home := await _wait_for(func() -> bool: return absf(hero.global_position.x - hero.home_x) < 0.05, 5.0)
	_check(home, "hero did not return home after the fight")
	for i in 3:
		await get_tree().process_frame
	_check(not hero.visual.flip_h and not hero._is_moving, "hero must stop and face right at home")
	battle.wave_manager.start_wave(GameState.wave)


func _wait_for(condition: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if condition.call():
			return true
		await get_tree().process_frame
		left -= get_process_delta_time()
	return condition.call()


## Английский перевод: данные (.tres и каталог сокровищ), строки кода, шаблоны отчётов сервера; возврат на русский.
func _test_translation() -> void:
	var goblin := Database.get_monster("goblin")
	var power_strike: SkillData = Database.get_class_data("warrior").skills[0]
	var set_piece := Database.get_item_base("w_emberforge_helmet")
	TranslationServer.set_locale("en")
	Database.retranslate()
	_check(goblin.display_name == "Goblin", "monster name not translated: %s" % goblin.display_name)
	_check(power_strike.display_name == "Power Strike", "skill name not translated: %s" % power_strike.display_name)
	_check(set_piece != null and set_piece.display_name == "Emberforge Helm", "set piece not translated")
	_check(UiFormat.duration(125) == "2 min 5 s", "duration not translated: %s" % UiFormat.duration(125))
	var report := {"text": "Набег на замок Бор удался", "template": "Набег на замок {name} удался", "args": {"name": "Бор"}}
	_check(WorldService.report_text(report) == "The raid on Бор's castle succeeded", "report template not translated: %s" % WorldService.report_text(report))
	_check(WorldService.report_text({"text": "Зона занята без боя"}) == "Zone taken without a fight", "old report text not translated")
	TranslationServer.set_locale("ru")
	Database.retranslate()
	_check(goblin.display_name == "Гоблин", "monster name not restored: %s" % goblin.display_name)
	_check(set_piece.display_name == "Шлем Закалённого горна", "set piece not restored: %s" % set_piece.display_name)


## Оглушение останавливает монстра, урон со временем тикает, добивание усиливает удар по раненой цели.
func _test_skill_mechanics() -> void:
	var hero := get_tree().get_first_node_in_group(Hero.GROUP) as Hero
	if hero == null:
		return
	var scene: PackedScene = load("res://scenes/actors/monster.tscn")
	var monster: Monster = scene.instantiate()
	add_child(monster)
	monster.setup(Database.get_monster("goblin"), 3, hero)
	monster.global_position = Vector3(hero.global_position.x + 30.0, 0, 0)
	monster.max_hp = 1.0e6
	monster.hp = monster.max_hp
	var x_before := monster.global_position.x
	monster.stun(0.5)
	_check(monster.is_stunned(), "stun not applied")
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(monster.global_position.x, x_before), "stunned monster moved")
	await get_tree().create_timer(0.4).timeout
	_check(not monster.is_stunned(), "stun did not end")
	var hp_before := monster.hp
	monster.apply_dot(1000.0, 1.0)
	await get_tree().create_timer(1.3).timeout
	_check(monster.hp < hp_before - 900.0, "damage over time did not tick fully: %f" % (hp_before - monster.hp))
	var boss: Monster = scene.instantiate()
	add_child(boss)
	boss.setup(Database.get_monster("ogre_boss"), 10, hero)
	boss.global_position = Vector3(hero.global_position.x + 40.0, 0, 0)
	boss.stun(2.0)
	_check(boss._stun_left <= 1.01, "boss stun must be halved")
	# Окно рисуется целиком, а клики принимает только боевая полоса.
	var window_height := float(get_window().size.y)
	_check(DesktopWindow.accepts_clicks_at(Vector2(100, window_height - 20.0)), "battle strip must accept clicks")
	_check(not DesktopWindow.accepts_clicks_at(Vector2(100, 10.0)), "area above the strip must pass clicks through")
	x_before = monster.global_position.x
	monster.knockback(hero.global_position.x, 2.0)
	await get_tree().create_timer(0.3).timeout
	_check(monster.global_position.x > x_before + 1.5, "knockback did not push the monster away")
	# Добивание: «Казнь» бьёт раненую цель сильнее.
	var execute := StrikeEffect.new()
	execute.damage_multiplier = 1.0
	execute.execute_below = 0.3
	execute.execute_multiplier = 3.0
	execute.force_crit = true
	monster.hp = monster.max_hp
	hp_before = monster.hp
	var damage_before := hero.damage
	hero.damage = 100.0
	execute.execute(hero, monster)
	await _wait_for(func() -> bool: return monster.hp < hp_before, 3.0)
	var normal_hit := hp_before - monster.hp
	monster.hp = monster.max_hp * 0.2
	hp_before = monster.hp
	execute.execute(hero, monster)
	await _wait_for(func() -> bool: return monster.hp < hp_before, 3.0)
	var execute_hit := hp_before - monster.hp
	hero.damage = damage_before
	_check(execute_hit > normal_hit * 2.0, "execute bonus not applied: %f vs %f" % [execute_hit, normal_hit])
	for node in [monster, boss]:
		node.remove_from_group(Monster.GROUP)
		node.queue_free()


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
	GameState.level = 80  # открыть все умения (последнее — на 80-м уровне)
	GameState.auto_cast = false
	var caster := hero.skill_caster
	for skill in caster.skills:
		if not await _wait_for_target(hero):
			_check(false, "no monster in range to test '%s'" % skill.id)
			break
		if not hero.is_alive():
			hero.revive()
		caster.reset_cooldowns()
		hero.clear_buffs()  # автокаст мог уже наложить этот бафф — тогда урон не вырастет
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
