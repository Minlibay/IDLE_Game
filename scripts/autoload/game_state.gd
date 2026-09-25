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

const SAVE_VERSION := 1
const INVENTORY_SIZE := 60
const AUTOSAVE_INTERVAL := 30.0
const CRIT_MULTIPLIER := 2.0
const MAX_CRIT_CHANCE := 0.75
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
## id таланта -> вложенный ранг.
var talent_ranks: Dictionary[String, int] = {}
## Кэш суммарных бонусов талантов: "стат|skill_id" -> значение.
var _talent_bonuses: Dictionary = {}
## Королевство: ресурсы, здания, стройка.
var kingdom := KingdomState.new()
## Потребности героя: сытость, жажда, бодрость.
var needs := NeedsState.new()
## Отчёт об оффлайн-прогрессе после загрузки (пусто — не было). Показывает и очищает бой.
var offline_report: Dictionary = {}
## Сколько секунд игра была закрыта (для отчёта; 0 — отчёт не нужен).
var _offline_seconds := 0.0
## Бонусы захваченных зон мировой карты: StatModifier.Stat -> значение (присылает WorldService).
var territory_bonuses: Dictionary = {}


func _ready() -> void:
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
	talent_ranks.clear()
	_rebuild_talent_bonuses()
	kingdom.reset()
	needs.reset()
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


## Суммарный бонус к стату от всех источников: таланты + здания + потребности + территории.
## С skill_id — плюс бонусы, действующие только на это умение.
func get_bonus(stat: int, skill_id := "") -> float:
	return get_talent_bonus(stat, skill_id) + kingdom.get_bonus(stat, skill_id) + needs.get_bonus(stat, skill_id) \
		+ float(territory_bonuses.get(stat, 0.0))


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
	progress_changed.emit()


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
	return equipment.values().has(item)


func can_equip(item: Item) -> bool:
	return item.get_base().can_be_used_by(class_id)


func equip(item: Item) -> bool:
	if not can_equip(item) or not inventory.has(item):
		return false
	var slot := item.get_base().slot
	var previous: Item = equipment.get(slot)
	inventory.erase(item)
	if previous:
		inventory.append(previous)
	equipment[slot] = item
	inventory_changed.emit()
	stats_changed.emit()
	return true


func unequip(slot: int) -> bool:
	var item: Item = equipment.get(slot)
	if item == null or inventory.size() >= INVENTORY_SIZE:
		return false
	equipment.erase(slot)
	inventory.append(item)
	inventory_changed.emit()
	stats_changed.emit()
	return true


func sell_item(item: Item) -> void:
	if is_equipped(item) or not inventory.has(item):
		return
	remove_item(item)
	add_gold(item.get_sell_price())


## Вызывается, когда у предмета поменялись статы (например, после заточки).
func notify_item_changed(item: Item) -> void:
	inventory_changed.emit()
	if is_equipped(item):
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
		"saved_at": Time.get_unix_time_from_system(),
		"inventory": inventory.map(func(item: Item) -> Dictionary: return item.to_dict()),
		"equipment": equipment.values().map(func(item: Item) -> Dictionary: return item.to_dict()),
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
	_rebuild_talent_bonuses()
	var saved_kingdom: Variant = data.get("kingdom", {})
	kingdom.from_dict(saved_kingdom if saved_kingdom is Dictionary else {})
	var saved_needs: Variant = data.get("needs", {})
	needs.from_dict(saved_needs if saved_needs is Dictionary else {})
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
