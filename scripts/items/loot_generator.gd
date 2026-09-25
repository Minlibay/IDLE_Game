class_name LootGenerator
extends RefCounted
## Правила выпадения и создания предметов. Все числа баланса лута — здесь.

## Вес каждого тира: Обычный, Необычный, Редкий, Эпический, Легендарный.
const BASE_TIER_WEIGHTS := [700.0, 220.0, 60.0, 17.0, 3.0]
## На сколько растут шансы Редкого и выше с каждой волной (0.04 = +4%).
const RARE_WEIGHT_GROWTH_PER_WAVE := 0.04
## Прирост статов предмета за каждый уровень предмета.
const STAT_GROWTH_PER_LEVEL := 0.08
## Разброс статов при выпадении (±15%).
const STAT_ROLL_SPREAD := 0.15


## Возвращает выпавший предмет или null. drop_bonus — доп. шанс от талантов (0.3 = +30%).
static func roll_drop(monster: MonsterData, wave: int, drop_bonus := 0.0) -> Item:
	if not monster.is_boss and randf() > monster.drop_chance * (1.0 + drop_bonus):
		return null
	if Database.items.is_empty():
		return null
	var base: ItemBase = Database.items.pick_random()
	var min_tier: int = Item.Tier.UNCOMMON if monster.is_boss else Item.Tier.COMMON
	return create_item(base, roll_tier(wave, min_tier), wave)


static func roll_tier(wave: int, min_tier: int = Item.Tier.COMMON) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for tier in BASE_TIER_WEIGHTS.size():
		var weight: float = BASE_TIER_WEIGHTS[tier]
		if tier < min_tier:
			weight = 0.0
		elif tier >= Item.Tier.RARE:
			weight *= 1.0 + wave * RARE_WEIGHT_GROWTH_PER_WAVE
		weights.append(weight)
		total += weight
	var roll := randf() * total
	for tier in weights.size():
		roll -= weights[tier]
		if roll <= 0.0:
			return tier
	return min_tier


static func create_item(base: ItemBase, tier: int, item_level: int) -> Item:
	var item := Item.new()
	item.uid = Item.generate_uid()
	item.base_id = base.id
	item.tier = tier
	item.item_level = maxi(1, item_level)
	var scale: float = Item.TIER_STAT_MULTIPLIER[tier] * (1.0 + (item.item_level - 1) * STAT_GROWTH_PER_LEVEL)
	for key: String in base.base_stats:
		var roll := randf_range(1.0 - STAT_ROLL_SPREAD, 1.0 + STAT_ROLL_SPREAD)
		item.rolled_stats[key] = snappedf(float(base.base_stats[key]) * scale * roll, 0.1)
	return item


## Стартовое оружие класса (первое оружие, предназначенное именно этому классу).
static func create_starter_weapon(class_id: String) -> Item:
	for base in Database.get_items_for_slot(ItemBase.Slot.WEAPON):
		if not base.allowed_classes.is_empty() and base.can_be_used_by(class_id):
			return create_item(base, Item.Tier.COMMON, 1)
	return null
