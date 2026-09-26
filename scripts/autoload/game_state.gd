extends Node
## Прогресс игрока: персонаж, уровень, золото, волна, инвентарь, экипировка, таланты,
## королевство (kingdom) и потребности героя (needs).
## Сохраняется в JSON (user://save.json) — автоматически и при выходе.

signal character_changed
## Изменились характеристики героя (уровень, экипировка, заточка надетого).
signal stats_changed
signal currency_changed
## Изменились волна или опыт.
signal progress_changed
signal inventory_changed
signal leveled_up(new_level: int)
## Изменились вложенные таланты (изучение или сброс).
signal talents_changed
## Готов отчёт «пока вас не было» (приходит после первого ответа сервера о замке).
signal offline_report_ready
## Изменились реликвии армии (их бонусы уходят на сервер — см. WorldService).
signal army_gear_changed
## Изменилась сокровищница (найдено новое сокровище или список пришёл с сервера).
signal treasures_changed
## Найдено новое сокровище (дроп по игровому времени с сервера).
signal treasure_found(item: Item)
## Герой переродился: gained — сколько душ получено. Сцена боя пересоздаётся (main.gd).
signal prestiged(gained: int)

const SAVE_VERSION := 1
const INVENTORY_SIZE := 60
## Слотов под реликвии армии.
const ARMY_RELIC_SLOTS := 6
const AUTOSAVE_INTERVAL := 30.0
const CRIT_MULTIPLIER := 2.0
const MAX_CRIT_CHANCE := 0.75
const MAX_DOUBLE_STRIKE := 0.5
## Потолок суммарного бонуса сокровищ (предметы + бонусы сетов) к стату, в процентах.
## Сокровища продаются за деньги — поэтому их сила заметная, но ограниченная.
const TREASURE_BONUS_CAPS := {
	StatModifier.Stat.DAMAGE: 30.0, StatModifier.Stat.MAX_HP: 30.0, StatModifier.Stat.ARMOR: 40.0,
	StatModifier.Stat.ATTACK_SPEED: 20.0, StatModifier.Stat.CRIT_CHANCE: 10.0, StatModifier.Stat.CRIT_DAMAGE: 50.0,
	StatModifier.Stat.SKILL_DAMAGE: 50.0, StatModifier.Stat.SKILL_COOLDOWN: 20.0, StatModifier.Stat.LIFESTEAL: 5.0,
	StatModifier.Stat.REGEN: 60.0, StatModifier.Stat.DOUBLE_STRIKE: 25.0, StatModifier.Stat.KILL_HEAL: 5.0,
}
const TREASURE_DEFAULT_CAP := 30.0
## Очки талантов: 1 за каждый уровень после первого.
const TALENT_POINTS_PER_LEVEL := 1
const TALENT_RESET_COST_PER_LEVEL := 50
## Перезарядка умений не сокращается сильнее, чем до этой доли.
const MIN_SKILL_COOLDOWN_MULTIPLIER := 0.3
## Отчёт «Пока вас не было» показывается, если игра была закрыта дольше этого.
const OFFLINE_REPORT_MIN_SECONDS := 60.0

## Режим автотеста (запуск с аргументом -- --autotest): отдельное сохранение.
var autotest := OS.get_cmdline_user_args().has("--autotest")
var save_path := "user://autotest_save.json" if autotest else "user://save.json"

var hero_name := ""
var class_id := ""
var level := 1
var xp := 0
var gold := 0
var wave := 1
var best_wave := 1
## Применять умения автоматически (переключатель «Авто» на панели умений).
var auto_cast := true
var inventory: Array[Item] = []
var equipment: Dictionary[int, Item] = {}
## Реликвии армии: ARMY_RELIC_SLOTS ячеек, null — пусто. Усиливают армию замка (на сервере).
var army_relics: Array[Item] = []
## Сокровищница: сокровища игрока, которые сейчас не надеты. Владение — на сервере (WorldService).
var treasures: Array[Item] = []
## Кэш бонусов надетых сокровищ и их сетов (уже с потолками): "стат|skill_id" -> значение.
var _treasure_bonuses: Dictionary = {}
## Сокровища, про которые уже известно (чтобы сообщать только о новых находках).
var _known_treasure_uids: Dictionary = {}
## id таланта -> вложенный ранг.
var talent_ranks: Dictionary[String, int] = {}
## Кэш суммарных бонусов талантов: "стат|skill_id" -> значение.
var _talent_bonuses: Dictionary = {}
## Королевство: ресурсы, здания, стройка.
var kingdom := KingdomState.new()
## Потребности героя: сытость, жажда, бодрость.
var needs := NeedsState.new()
## Перерождение и души, бестиарий, достижения, ежедневные задания.
var progress := HeroProgress.new()
## Отчёт об оффлайн-прогрессе после загрузки (пусто — не было). Показывает и очищает бой.
var offline_report: Dictionary = {}
## Сколько секунд игра была закрыта (для отчёта; 0 — отчёт не нужен).
var _offline_seconds := 0.0
## Бонусы захваченных зон мировой карты: StatModifier.Stat -> значение (присылает WorldService).
var territory_bonuses: Dictionary = {}


func _ready() -> void:
	_clear_relics()
	needs.setup(kingdom)
	kingdom.bonuses_changed.connect(stats_changed.emit)
	kingdom.first_sync.connect(_on_kingdom_first_sync)
	needs.state_changed.connect(stats_changed.emit)
	if autotest:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	load_game()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _process(delta: float) -> void:
	if has_character():
		kingdom.tick(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


# --- Персонаж -----------------------------------------------------------------

func has_character() -> bool:
	return class_id != "" and Database.get_class_data(class_id) != null


func create_character(p_name: String, p_class_id: String) -> void:
	hero_name = p_name
	class_id = p_class_id
	level = 1
	xp = 0
	gold = 0
	wave = 1
	best_wave = 1
	inventory.clear()
	equipment.clear()
	_clear_relics()
	treasures.clear()
	_known_treasure_uids.clear()
	_rebuild_treasure_bonuses()
	talent_ranks.clear()
	_rebuild_talent_bonuses()
	kingdom.reset()
	needs.reset()
	progress = HeroProgress.new()
	var starter := LootGenerator.create_starter_weapon(class_id)
	if starter:
		equipment[starter.get_base().slot] = starter
	save_game()
	character_changed.emit()
	stats_changed.emit()
	progress_changed.emit()
	currency_changed.emit()
	inventory_changed.emit()


func get_class_data() -> CharacterClass:
	return Database.get_class_data(class_id)


func get_hero_stats() -> Dictionary:
	var c := get_class_data()
	var bonus := {"damage": 0.0, "max_hp": 0.0, "armor": 0.0, "attack_speed": 0.0, "crit_chance": 0.0}
	for item: Item in equipment.values():
		var item_stats := item.get_stats()
		for key: String in item_stats:
			bonus[key] = float(bonus.get(key, 0.0)) + float(item_stats[key])
	var levels := level - 1
	var stat := StatModifier.Stat
	# get_bonus = таланты + здания + потребности.
	return {
		"max_hp": (c.base_max_hp + c.hp_per_level * levels + bonus.max_hp) * (1.0 + get_bonus(stat.MAX_HP) / 100.0),
		"damage": (c.base_damage + c.damage_per_level * levels + bonus.damage) * (1.0 + get_bonus(stat.DAMAGE) / 100.0),
		"armor": c.base_armor + bonus.armor + get_bonus(stat.ARMOR),
		"attack_interval": c.attack_interval / (1.0 + (bonus.attack_speed + get_bonus(stat.ATTACK_SPEED)) / 100.0),
		"crit_chance": clampf(c.crit_chance + (bonus.crit_chance + get_bonus(stat.CRIT_CHANCE)) / 100.0, 0.0, MAX_CRIT_CHANCE),
		"crit_multiplier": CRIT_MULTIPLIER + get_bonus(stat.CRIT_DAMAGE) / 100.0,
		"attack_range": c.attack_range,
		"regen_multiplier": 1.0 + get_bonus(stat.REGEN) / 100.0,
		"click_power": 1.0 + get_bonus(stat.CLICK_POWER) / 100.0,
		"lifesteal": get_bonus(stat.LIFESTEAL) / 100.0,
		"double_strike": clampf(get_bonus(stat.DOUBLE_STRIKE) / 100.0, 0.0, MAX_DOUBLE_STRIKE),
		"kill_heal": get_bonus(stat.KILL_HEAL) / 100.0,
	}


# --- Таланты ------------------------------------------------------------------

func get_talent_tree() -> TalentTree:
	var c := get_class_data()
	return c.talent_tree if c else null


## Стартовый узел сетки изучен всегда.
func get_talent_rank(talent: TalentData) -> int:
	if talent.kind == TalentData.Kind.START:
		return 1
	return talent_ranks.get(talent.id, 0)


func get_talent_points_total() -> int:
	return (level - 1) * TALENT_POINTS_PER_LEVEL


## Учитываются только узлы текущей сетки (устаревшие id из сохранения игнорируются — очки возвращаются).
func get_talent_points_spent() -> int:
	var tree := get_talent_tree()
	if tree == null:
		return 0
	var spent := 0
	for talent in tree.get_talents():
		if talent.kind != TalentData.Kind.START:
			spent += get_talent_rank(talent)
	return spent


func get_available_talent_points() -> int:
	return maxi(0, get_talent_points_total() - get_talent_points_spent())


## Узел доступен, если рядом (по 4 сторонам) есть изученный узел или старт.
func is_talent_reachable(talent: TalentData) -> bool:
	var tree := get_talent_tree()
	if tree == null:
		return false
	for neighbor in tree.neighbors(talent):
		if get_talent_rank(neighbor) > 0:
			return true
	return false


func can_learn_talent(talent: TalentData) -> bool:
	return get_available_talent_points() > 0 \
		and get_talent_rank(talent) < talent.max_rank \
		and is_talent_reachable(talent)


## Вкладывает 1 очко в талант.
func learn_talent(talent: TalentData) -> bool:
	if not can_learn_talent(talent):
		return false
	talent_ranks[talent.id] = get_talent_rank(talent) + 1
	_on_talents_updated()
	return true


func get_talent_reset_cost() -> int:
	return level * TALENT_RESET_COST_PER_LEVEL


## Сбрасывает все таланты за золото. Возвращает false, если нечего сбрасывать или не хватает золота.
func reset_talents() -> bool:
	if get_talent_points_spent() == 0 or not try_spend_gold(get_talent_reset_cost()):
		return false
	talent_ranks.clear()
	_on_talents_updated()
	return true


## Суммарный бонус к стату от всех источников: таланты + здания + потребности + территории и гильдия
## + сокровища + улучшения за души. С skill_id — плюс бонусы, действующие только на это умение.
func get_bonus(stat: int, skill_id := "") -> float:
	return get_talent_bonus(stat, skill_id) + kingdom.get_bonus(stat, skill_id) + needs.get_bonus(stat, skill_id) \
		+ float(territory_bonuses.get(stat, 0.0)) + StatModifier.read_bonus(_treasure_bonuses, stat, skill_id) \
		+ progress.get_bonus(stat)


## Бонусы территорий с сервера: {"GOLD_FIND": 1.5, ...} (имена = StatModifier.Stat).
func set_territory_bonuses(by_name: Dictionary) -> void:
	var converted := {}
	for stat_name: String in by_name:
		var stat: int = StatModifier.Stat.get(stat_name, -1)
		if stat >= 0:
			converted[stat] = float(by_name[stat_name])
	if converted != territory_bonuses:
		territory_bonuses = converted
		stats_changed.emit()


## Бонус только от талантов.
func get_talent_bonus(stat: int, skill_id := "") -> float:
	return StatModifier.read_bonus(_talent_bonuses, stat, skill_id)


## Множитель урона умения от бонусов (таланты и др.).
func get_skill_power(skill_id: String) -> float:
	return 1.0 + get_bonus(StatModifier.Stat.SKILL_DAMAGE, skill_id) / 100.0


## Множитель перезарядки умения от бонусов (меньше 1 = быстрее).
func get_skill_cooldown_multiplier(skill_id: String) -> float:
	var reduction := get_bonus(StatModifier.Stat.SKILL_COOLDOWN, skill_id) / 100.0
	return maxf(MIN_SKILL_COOLDOWN_MULTIPLIER, 1.0 - reduction)


func _on_talents_updated() -> void:
	_rebuild_talent_bonuses()
	talents_changed.emit()
	stats_changed.emit()


func _rebuild_talent_bonuses() -> void:
	_talent_bonuses.clear()
	var tree := get_talent_tree()
	if tree == null:
		return
	for talent in tree.get_talents():
		var rank := get_talent_rank(talent)
		if rank <= 0:
			continue
		StatModifier.accumulate(_talent_bonuses, talent.modifiers, rank)


# --- Прогресс -----------------------------------------------------------------

func xp_to_next_level() -> int:
	return int(25.0 * pow(level, 1.6))


func add_xp(amount: int) -> void:
	xp += amount
	var leveled := false
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		leveled = true
		leveled_up.emit(level)
	if leveled:
		stats_changed.emit()
	progress_changed.emit()


func set_wave(value: int) -> void:
	wave = maxi(1, value)
	best_wave = maxi(best_wave, wave)
	progress.run_best_wave = maxi(progress.run_best_wave, wave)
	progress_changed.emit()


# --- Перерождение -----------------------------------------------------------------

## Новая жизнь героя: волна (с учётом «Стартового рывка»), уровень 1, таланты возвращаются.
## Снаряжение, сокровища, золото, замок и гильдия остаются. Возвращает полученные души (0 — рано).
func prestige() -> int:
	if not progress.can_prestige():
		return 0
	var gained := HeroProgress.souls_for(progress.run_best_wave)
	progress.souls += gained
	progress.prestige_count += 1
	progress.record("prestige")
	level = 1
	xp = 0
	talent_ranks.clear()
	_rebuild_talent_bonuses()
	wave = progress.start_wave()
	best_wave = maxi(best_wave, wave)
	progress.run_best_wave = wave
	save_game()
	talents_changed.emit()
	stats_changed.emit()
	progress_changed.emit()
	character_changed.emit()
	prestiged.emit(gained)
	return gained


## Купить улучшение за души (сразу меняет характеристики героя).
func buy_soul_upgrade(upgrade_id: String) -> bool:
	if not progress.buy_upgrade(upgrade_id):
		return false
	stats_changed.emit()
	save_game()
	return true


func add_gold(amount: int) -> void:
	gold += amount
	currency_changed.emit()


func try_spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	currency_changed.emit()
	return true


# --- Инвентарь ----------------------------------------------------------------

## Кладёт предмет в сумку. Если сумка полна — предмет автоматически продаётся.
func add_item(item: Item) -> bool:
	if inventory.size() >= INVENTORY_SIZE:
		add_gold(item.get_sell_price())
		return false
	inventory.append(item)
	inventory_changed.emit()
	return true


func remove_item(item: Item) -> void:
	inventory.erase(item)
	inventory_changed.emit()


func is_equipped(item: Item) -> bool:
	return equipment.values().has(item) or army_relics.has(item)


func can_equip(item: Item) -> bool:
	return item.get_base().can_be_used_by(class_id)


func equip(item: Item) -> bool:
	if not can_equip(item) or not (inventory.has(item) or treasures.has(item)):
		return false
	if item.get_base().is_army_relic():
		return _equip_relic(item)
	var slot := item.get_base().slot
	var previous: Item = equipment.get(slot)
	inventory.erase(item)
	treasures.erase(item)
	if previous:
		_stash(previous)
	equipment[slot] = item
	_after_equipment_change()
	return true


## Снятый предмет: сокровище — в сокровищницу, обычный — в сумку.
func _stash(item: Item) -> void:
	if item.is_treasure():
		treasures.append(item)
	else:
		inventory.append(item)


func _after_equipment_change() -> void:
	_rebuild_treasure_bonuses()
	inventory_changed.emit()
	treasures_changed.emit()
	stats_changed.emit()


# --- Сокровища ---------------------------------------------------------------------

## Сколько частей сета надето.
func get_set_piece_count(set_id: String) -> int:
	var count := 0
	for item: Item in equipment.values():
		if item.get_base().set_id == set_id:
			count += 1
	return count


## Цвет ауры героя: полный сет (все части) — цвет сета; нет — прозрачный.
func get_aura_color() -> Color:
	for set_id: String in _equipped_set_ids():
		var item_set := Database.get_item_set(set_id)
		if item_set and get_set_piece_count(set_id) >= item_set.get_piece_count():
			return item_set.color
	return Color(0, 0, 0, 0)


## Список сокровищ с сервера: [{uid, itemId}]. Сервер — владелец: надетое, чего у игрока нет, снимается.
## Возвращает новые находки.
func apply_server_treasures(list: Array) -> Array[Item]:
	var owned := {}
	for entry: Variant in list:
		if entry is Dictionary and Database.get_item_base(str(entry.get("itemId", ""))):
			owned[str(entry.uid)] = str(entry.itemId)
	var changed := false
	for slot: int in equipment.keys():
		var item: Item = equipment[slot]
		if item.is_treasure() and not owned.has(item.uid):
			equipment.erase(slot)
			changed = true
	var equipped_uids := {}
	for item: Item in equipment.values():
		equipped_uids[item.uid] = true
	var first_sync := _known_treasure_uids.is_empty()
	var found: Array[Item] = []
	var result: Array[Item] = []
	for uid: String in owned:
		if equipped_uids.has(uid):
			continue
		var existing: Item = null
		for item in treasures:
			if item.uid == uid:
				existing = item
				break
		if existing == null:
			existing = _make_treasure(uid, owned[uid])
			if not first_sync and not _known_treasure_uids.has(uid):
				found.append(existing)
		result.append(existing)
	if result.size() != treasures.size() or changed:
		changed = true
	treasures = result
	for uid: String in owned:
		_known_treasure_uids[uid] = true
	if changed or not found.is_empty():
		_rebuild_treasure_bonuses()
		treasures_changed.emit()
		stats_changed.emit()
	for item in found:
		treasure_found.emit(item)
	return found


func _make_treasure(uid: String, item_id: String) -> Item:
	var item := Item.new()
	item.uid = uid
	item.base_id = item_id
	item.tier = Item.Tier.LEGENDARY
	return item


func _equipped_set_ids() -> Array[String]:
	var result: Array[String] = []
	for item: Item in equipment.values():
		var set_id := item.get_base().set_id
		if set_id != "" and not result.has(set_id):
			result.append(set_id)
	return result


## Бонусы надетых сокровищ и сетов, урезанные до TREASURE_BONUS_CAPS.
func _rebuild_treasure_bonuses() -> void:
	var raw := {}
	for item: Item in equipment.values():
		if item.is_treasure():
			StatModifier.accumulate(raw, item.get_base().modifiers, 1.0)
	for set_id in _equipped_set_ids():
		var item_set := Database.get_item_set(set_id)
		if item_set == null:
			continue
		var count := get_set_piece_count(set_id)
		for bonus in item_set.bonuses:
			if count >= bonus.pieces:
				StatModifier.accumulate(raw, bonus.modifiers, 1.0)
	_treasure_bonuses.clear()
	for key: String in raw:
		var stat := int(key.get_slice("|", 0))
		_treasure_bonuses[key] = minf(float(raw[key]), TREASURE_BONUS_CAPS.get(stat, TREASURE_DEFAULT_CAP))


## Снимает надетый предмет (экипировку героя или реликвию) в сумку.
func unequip_item(item: Item) -> bool:
	var index := army_relics.find(item)
	if index < 0:
		return unequip(item.get_base().slot) if equipment.get(item.get_base().slot) == item else false
	if inventory.size() >= INVENTORY_SIZE:
		return false
	army_relics[index] = null
	inventory.append(item)
	inventory_changed.emit()
	army_gear_changed.emit()
	return true


## Сумма бонусов реликвий: имя бонуса на сервере (Item.ARMY_STAT_KEYS) -> проценты.
func get_army_gear_bonuses() -> Dictionary:
	var result := {}
	for item in army_relics:
		if item == null:
			continue
		var stats := item.get_stats()
		for key: String in stats:
			if Item.ARMY_STAT_KEYS.has(key):
				var stat_name: String = Item.ARMY_STAT_KEYS[key]
				result[stat_name] = snappedf(float(result.get(stat_name, 0.0)) + float(stats[key]), 0.1)
	return result


## Реликвия — в свободную ячейку; если все заняты — вместо такой же реликвии или самой дешёвой.
func _equip_relic(item: Item) -> bool:
	var index := army_relics.find(null)
	if index < 0:
		for i in army_relics.size():
			if army_relics[i].base_id == item.base_id and (index < 0 or army_relics[i].get_sell_price() < army_relics[index].get_sell_price()):
				index = i
	if index < 0:
		index = 0
		for i in army_relics.size():
			if army_relics[i].get_sell_price() < army_relics[index].get_sell_price():
				index = i
	var previous := army_relics[index]
	inventory.erase(item)
	if previous:
		inventory.append(previous)
	army_relics[index] = item
	inventory_changed.emit()
	army_gear_changed.emit()
	return true


func _clear_relics() -> void:
	army_relics.clear()
	army_relics.resize(ARMY_RELIC_SLOTS)


func unequip(slot: int) -> bool:
	var item: Item = equipment.get(slot)
	if item == null or (not item.is_treasure() and inventory.size() >= INVENTORY_SIZE):
		return false
	equipment.erase(slot)
	_stash(item)
	_after_equipment_change()
	return true


func sell_item(item: Item) -> void:
	if is_equipped(item) or not inventory.has(item):
		return
	remove_item(item)
	add_gold(item.get_sell_price())


## Вызывается, когда у предмета поменялись статы (например, после заточки).
func notify_item_changed(item: Item) -> void:
	inventory_changed.emit()
	if army_relics.has(item):
		army_gear_changed.emit()
	elif is_equipped(item):
		stats_changed.emit()


# --- Сохранение ---------------------------------------------------------------

func save_game() -> void:
	if not has_character():
		return
	var data := {
		"version": SAVE_VERSION,
		"hero_name": hero_name,
		"class_id": class_id,
		"level": level,
		"xp": xp,
		"gold": gold,
		"wave": wave,
		"best_wave": best_wave,
		"auto_cast": auto_cast,
		"talents": talent_ranks,
		"kingdom": kingdom.to_dict(),
		"needs": needs.to_dict(),
		"progress": progress.to_dict(),
		"saved_at": Time.get_unix_time_from_system(),
		"inventory": inventory.map(func(item: Item) -> Dictionary: return item.to_dict()),
		"equipment": equipment.values().map(func(item: Item) -> Dictionary: return item.to_dict()),
		"army_relics": army_relics.map(func(item: Item) -> Variant: return item.to_dict() if item else null),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_warning("Save file is corrupted, starting fresh")
		return
	hero_name = str(data.get("hero_name", ""))
	class_id = str(data.get("class_id", ""))
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	wave = maxi(1, int(data.get("wave", 1)))
	best_wave = maxi(wave, int(data.get("best_wave", 1)))
	auto_cast = bool(data.get("auto_cast", true))
	talent_ranks.clear()
	var saved_talents: Variant = data.get("talents", {})
	if saved_talents is Dictionary:
		for talent_id: Variant in saved_talents:
			talent_ranks[str(talent_id)] = maxi(0, int(saved_talents[talent_id]))
	inventory.clear()
	for entry: Variant in data.get("inventory", []):
		if entry is Dictionary:
			var item := Item.from_dict(entry)
			if item:
				inventory.append(item)
	equipment.clear()
	for entry: Variant in data.get("equipment", []):
		if entry is Dictionary:
			var item := Item.from_dict(entry)
			if item:
				equipment[item.get_base().slot] = item
	_clear_relics()
	var saved_relics: Variant = data.get("army_relics", [])
	if saved_relics is Array:
		for i in mini((saved_relics as Array).size(), ARMY_RELIC_SLOTS):
			if saved_relics[i] is Dictionary:
				var relic := Item.from_dict(saved_relics[i])
				if relic and relic.get_base().is_army_relic():
					army_relics[i] = relic
	army_gear_changed.emit()
	_rebuild_talent_bonuses()
	# Сокровищница приходит с сервера; надетые сокровища — из сохранения (сервер их проверит).
	treasures.clear()
	_known_treasure_uids.clear()
	_rebuild_treasure_bonuses()
	var saved_kingdom: Variant = data.get("kingdom", {})
	kingdom.from_dict(saved_kingdom if saved_kingdom is Dictionary else {})
	var saved_needs: Variant = data.get("needs", {})
	needs.from_dict(saved_needs if saved_needs is Dictionary else {})
	var saved_progress: Variant = data.get("progress", {})
	progress.from_dict(saved_progress if saved_progress is Dictionary else {}, best_wave)
	_apply_offline_progress(float(data.get("saved_at", 0.0)))


## Замок живёт на сервере и пока игра закрыта; что изменилось — станет ясно после первого ответа сервера.
func _apply_offline_progress(saved_at: float) -> void:
	offline_report = {}
	_offline_seconds = 0.0
	if saved_at <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - saved_at
	if elapsed >= OFFLINE_REPORT_MIN_SECONDS:
		_offline_seconds = elapsed


func _on_kingdom_first_sync(report: Dictionary) -> void:
	if _offline_seconds <= 0.0 or report.is_empty():
		return
	offline_report = report
	offline_report.real_seconds = _offline_seconds
	_offline_seconds = 0.0
	offline_report_ready.emit()
