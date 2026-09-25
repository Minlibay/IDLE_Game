class_name TreasureCatalog
extends RefCounted
## Каталог сокровищ: читает data/treasures/<класс>.json и собирает шаблоны предметов (ItemBase)
## и сеты (ItemSetData). Тот же JSON читает сервер (server/src/treasures.ts) — id строятся одинаково:
## часть сета = "<id сета>_<слот>", именные и уникальные — свой id.
##
## Формат (сокращённый, чтобы сотни предметов описывались коротко):
##   sets:  id, name, of (родительный падеж для названий частей), color, focus [2 стата], skill, proc {стат: значение}
##          → 5 частей: «<slot_names[слот]> <of>», у каждой focus[0] и focus[1];
##            бонусы: 2 части — focus[0] ×2, 4 части — урон умения skill, 5 частей — proc + аура.
##   items: id, quality (named|unique), slot, name, mods {стат: значение}, lore.
## Статы — имена StatModifier.Stat; значения — проценты (ARMOR — единицы брони).

const DIR := "res://data/treasures/"
const SET_SLOTS := ["helmet", "shoulders", "armor", "legs", "boots"]
const SLOTS := {
	"helmet": ItemBase.Slot.HELMET, "shoulders": ItemBase.Slot.SHOULDERS, "armor": ItemBase.Slot.ARMOR,
	"legs": ItemBase.Slot.LEGS, "boots": ItemBase.Slot.BOOTS, "weapon": ItemBase.Slot.WEAPON, "trinket": ItemBase.Slot.TRINKET,
}
const QUALITIES := {"named": ItemBase.Quality.NAMED, "unique": ItemBase.Quality.UNIQUE}
## «Единица» стата для частей сета: часть даёт focus[0] × 1 и focus[1] × 0.7 единицы.
const STAT_UNITS := {
	"DAMAGE": 3.0, "MAX_HP": 3.0, "ARMOR": 4.0, "ATTACK_SPEED": 2.0, "CRIT_CHANCE": 1.0, "CRIT_DAMAGE": 6.0,
	"SKILL_DAMAGE": 4.0, "SKILL_COOLDOWN": 2.0, "CLICK_POWER": 5.0, "GOLD_FIND": 5.0, "XP_GAIN": 4.0,
	"DROP_CHANCE": 4.0, "REGEN": 8.0, "LIFESTEAL": 0.6, "DOUBLE_STRIKE": 2.0, "KILL_HEAL": 0.5,
}
const SECOND_FOCUS_SHARE := 0.7
const SET_SKILL_DAMAGE := 20.0

var items: Array[ItemBase] = []
var sets: Dictionary[String, ItemSetData] = {}


## Загружает все файлы каталога. mob_items — обычные предметы: их статы берутся как основа для слотов.
func load_all(mob_items: Array[ItemBase]) -> void:
	for file_name in DirAccess.get_files_at(DIR):
		if file_name.ends_with(".json"):
			_load_file(DIR + file_name, mob_items)


func _load_file(path: String, mob_items: Array[ItemBase]) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Treasure catalog %s is not valid JSON" % path)
		return
	var class_id := str(data.get("class", ""))
	var slot_names: Dictionary = data.get("slot_names", {})
	for entry: Dictionary in data.get("sets", []):
		var item_set := ItemSetData.new()
		item_set.id = str(entry.id)
		item_set.display_name = str(entry.name)
		item_set.class_id = class_id
		item_set.season = int(entry.get("season", 1))
		item_set.color = Color(str(entry.get("color", "#ffffff")))
		item_set.lore = str(entry.get("lore", ""))
		var focus: Array = entry.get("focus", [])
		for slot_key: String in SET_SLOTS:
			var mods := {}
			if focus.size() > 0:
				mods[focus[0]] = _unit(focus[0])
			if focus.size() > 1:
				mods[focus[1]] = snappedf(_unit(focus[1]) * SECOND_FOCUS_SHARE, 0.1)
			var base := _make_item("%s_%s" % [item_set.id, slot_key], "%s %s" % [slot_names.get(slot_key, slot_key), entry.of],
				ItemBase.Quality.LEGENDARY, slot_key, class_id, mods, item_set.lore, mob_items)
			base.set_id = item_set.id
			base.icon_tint = item_set.color.lerp(Color.WHITE, 0.35)
			item_set.piece_ids.append(base.id)
			items.append(base)
		if focus.size() > 0:
			item_set.bonuses.append(_bonus(2, {focus[0]: _unit(focus[0]) * 2.0}))
		var skill_bonus := _bonus(4, {"SKILL_DAMAGE": SET_SKILL_DAMAGE})
		skill_bonus.modifiers[0].skill_id = str(entry.get("skill", ""))
		item_set.bonuses.append(skill_bonus)
		var full := _bonus(5, entry.get("proc", {}))
		full.aura = true
		item_set.bonuses.append(full)
		sets[item_set.id] = item_set
	for entry: Dictionary in data.get("items", []):
		var quality: int = QUALITIES.get(str(entry.get("quality", "named")), ItemBase.Quality.NAMED)
		items.append(_make_item(str(entry.id), str(entry.name), quality, str(entry.slot), class_id,
			entry.get("mods", {}), str(entry.get("lore", "")), mob_items))


func _make_item(id: String, display_name: String, quality: int, slot_key: String, class_id: String,
		mods: Dictionary, lore: String, mob_items: Array[ItemBase]) -> ItemBase:
	var base := ItemBase.new()
	base.id = id
	base.display_name = display_name
	base.quality = quality
	base.slot = SLOTS.get(slot_key, ItemBase.Slot.TRINKET)
	base.allowed_classes = PackedStringArray([class_id])
	base.description = lore
	base.drop_weight = 0.0
	base.modifiers = _modifiers(mods)
	# Основа — обычный предмет того же слота (оружие — своего класса): его статы и иконка.
	var template := _template(base.slot, class_id, mob_items)
	if template:
		base.base_stats = template.base_stats.duplicate()
		base.icon = template.icon
	base.icon_tint = ItemBase.QUALITY_COLORS.get(quality, Color.WHITE).lerp(Color.WHITE, 0.45)
	return base


func _template(slot: int, class_id: String, mob_items: Array[ItemBase]) -> ItemBase:
	var fallback: ItemBase = null
	for item in mob_items:
		if item.slot != slot:
			continue
		if item.can_be_used_by(class_id) and not item.allowed_classes.is_empty():
			return item
		if fallback == null and item.allowed_classes.is_empty():
			fallback = item
	return fallback


func _bonus(pieces: int, mods: Dictionary) -> ItemSetData.Bonus:
	var bonus := ItemSetData.Bonus.new()
	bonus.pieces = pieces
	bonus.modifiers = _modifiers(mods)
	return bonus


func _modifiers(mods: Dictionary) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for stat_name: String in mods:
		var stat: int = StatModifier.Stat.get(stat_name, -1)
		if stat < 0:
			push_error("Unknown stat '%s' in treasure catalog" % stat_name)
			continue
		var modifier := StatModifier.new()
		modifier.stat = stat
		modifier.value = float(mods[stat_name])
		result.append(modifier)
	return result


func _unit(stat_name: String) -> float:
	return STAT_UNITS.get(stat_name, 2.0)
