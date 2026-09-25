class_name Item
extends RefCounted
## Конкретный экземпляр предмета: шаблон + тир + уровень + заточка + выпавшие статы.
## get_market_key() — ключ для будущей привязки к Steam Inventory (itemdef).

enum Tier { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const TIER_NAMES := ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный"]
const TIER_COLORS := [
	Color(0.78, 0.78, 0.78),
	Color(0.37, 0.83, 0.37),
	Color(0.29, 0.62, 1.0),
	Color(0.72, 0.4, 1.0),
	Color(1.0, 0.65, 0.17),
]
const TIER_STAT_MULTIPLIER := [1.0, 1.35, 1.8, 2.5, 3.5]
const MAX_UPGRADE_LEVEL := 10
## +10% ко всем статам за каждый уровень заточки.
const UPGRADE_STAT_BONUS := 0.1

const STAT_NAMES := {
	"damage": "Урон",
	"max_hp": "Здоровье",
	"armor": "Броня",
	"attack_speed": "Скорость атаки, %",
	"crit_chance": "Шанс крита, %",
	"army_power": "Сила армии, %",
	"army_attack": "Атака армии, %",
	"army_defense": "Защита армии, %",
	"training_speed": "Скорость обучения, %",
	"upkeep_reduction": "Меньше еды армии, %",
}
## Статы реликвий армии -> имена бонусов на сервере (они же — имена StatModifier.Stat, где есть).
const ARMY_STAT_KEYS := {
	"army_power": "ARMY_POWER",
	"army_attack": "ARMY_ATTACK",
	"army_defense": "ARMY_DEFENSE",
	"training_speed": "TRAINING_SPEED",
	"upkeep_reduction": "UPKEEP_REDUCTION",
}

## Сокровища не имеют случайных статов и заточки: их основа (статы слота) растёт вместе с героем —
## уровень сокровища = рекорд волны героя. Множитель — сила основы относительно обычного предмета.
const TREASURE_STAT_MULTIPLIER := {
	ItemBase.Quality.NAMED: 4.5, ItemBase.Quality.UNIQUE: 5.0, ItemBase.Quality.LEGENDARY: 5.0,
}
## Процентные статы основы сокровища с уровнем не растут (иначе скорость атаки и крит уходят в бесконечность).
const TREASURE_FIXED_STATS := ["attack_speed", "crit_chance"]

var uid := ""
var base_id := ""
var tier: int = Tier.COMMON
var item_level := 1
var upgrade_level := 0
var rolled_stats: Dictionary = {}


func get_base() -> ItemBase:
	return Database.get_item_base(base_id)


func is_treasure() -> bool:
	var base := get_base()
	return base != null and base.is_treasure()


## Итоговые статы с учётом заточки (у сокровища — с учётом уровня героя).
func get_stats() -> Dictionary:
	var result := {}
	if is_treasure():
		var base := get_base()
		var level := get_treasure_level()
		var quality_scale: float = TREASURE_STAT_MULTIPLIER.get(base.quality, 4.5)
		var level_scale := 1.0 + (level - 1) * LootGenerator.STAT_GROWTH_PER_LEVEL
		for key: String in base.base_stats:
			var scale := quality_scale * (1.0 if key in TREASURE_FIXED_STATS else level_scale)
			result[key] = snappedf(float(base.base_stats[key]) * scale, 0.1)
		return result
	var multiplier := 1.0 + UPGRADE_STAT_BONUS * upgrade_level
	for key: String in rolled_stats:
		result[key] = snappedf(float(rolled_stats[key]) * multiplier, 0.1)
	return result


## Уровень сокровища — рекорд волны героя (сокровища растут вместе с ним).
func get_treasure_level() -> int:
	return maxi(1, GameState.best_wave)


func get_tier_name() -> String:
	if is_treasure():
		return ItemBase.QUALITY_NAMES.get(get_base().quality, "")
	return TIER_NAMES[tier]


func get_tier_color() -> Color:
	if is_treasure():
		return ItemBase.QUALITY_COLORS.get(get_base().quality, Color.WHITE)
	return TIER_COLORS[tier]


func get_display_name() -> String:
	var text := get_base().display_name
	if upgrade_level > 0:
		text = "+%d %s" % [upgrade_level, text]
	return text


## Сокровища за золото не продаются (только на торговой площадке Steam).
func get_sell_price() -> int:
	if is_treasure():
		return 0
	return int((5 + item_level * 2) * pow(2.0, tier) * (1.0 + 0.25 * upgrade_level))


## Ключ для Steam Inventory: у сокровища — его id (один itemdef на предмет).
func get_market_key() -> String:
	if is_treasure():
		return base_id
	return "%s_t%d" % [base_id, tier]


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"base_id": base_id,
		"tier": tier,
		"item_level": item_level,
		"upgrade_level": upgrade_level,
		"rolled_stats": rolled_stats,
	}


static func from_dict(data: Dictionary) -> Item:
	var base_id_value := str(data.get("base_id", ""))
	if Database.get_item_base(base_id_value) == null:
		push_warning("Unknown item base '%s' in save, skipped" % base_id_value)
		return null
	var item := Item.new()
	item.uid = str(data.get("uid", generate_uid()))
	item.base_id = base_id_value
	item.tier = clampi(int(data.get("tier", 0)), 0, Tier.LEGENDARY)
	item.item_level = maxi(1, int(data.get("item_level", 1)))
	item.upgrade_level = clampi(int(data.get("upgrade_level", 0)), 0, MAX_UPGRADE_LEVEL)
	var stats: Variant = data.get("rolled_stats", {})
	if stats is Dictionary:
		item.rolled_stats = stats
	return item


static func generate_uid() -> String:
	return "%d_%d" % [int(Time.get_unix_time_from_system() * 1000.0), randi()]
