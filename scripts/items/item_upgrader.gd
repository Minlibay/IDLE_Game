class_name ItemUpgrader
extends RefCounted
## Прокачка предметов:
##  - заточка +1..+10 за золото с шансом неудачи;
##  - слияние: 3 предмета одного тира и слота -> 1 предмет следующего тира.

enum Result { SUCCESS, FAILED, NOT_ENOUGH_GOLD, MAX_LEVEL }

const FUSION_COUNT := 3
const MIN_SUCCESS_CHANCE := 0.3
const CHANCE_DROP_PER_LEVEL := 0.07


static func get_upgrade_cost(item: Item) -> int:
	return int(15.0 * pow(item.upgrade_level + 1, 2) * (item.tier + 1) * (1.0 + item.item_level * 0.1))


static func get_success_chance(item: Item) -> float:
	return maxf(MIN_SUCCESS_CHANCE, 1.0 - CHANCE_DROP_PER_LEVEL * item.upgrade_level)


static func try_upgrade(item: Item) -> Result:
	if item.is_treasure() or item.upgrade_level >= Item.MAX_UPGRADE_LEVEL:
		return Result.MAX_LEVEL
	if not GameState.try_spend_gold(get_upgrade_cost(item)):
		return Result.NOT_ENOUGH_GOLD
	if randf() > get_success_chance(item):
		return Result.FAILED
	item.upgrade_level += 1
	GameState.notify_item_changed(item)
	return Result.SUCCESS


## Другие предметы в сумке того же тира и слота (кандидаты на слияние).
static func find_fusion_partners(item: Item) -> Array[Item]:
	var partners: Array[Item] = []
	if item.tier >= Item.Tier.LEGENDARY:
		return partners
	var slot := item.get_base().slot
	for other in GameState.inventory:
		if other != item and other.tier == item.tier and other.get_base().slot == slot:
			partners.append(other)
			if partners.size() == FUSION_COUNT - 1:
				break
	return partners


static func can_fuse(item: Item) -> bool:
	return not item.is_treasure() and GameState.inventory.has(item) and find_fusion_partners(item).size() == FUSION_COUNT - 1


## Сливает предмет с двумя подходящими. Возвращает новый предмет или null.
static func fuse(item: Item) -> Item:
	if not can_fuse(item):
		return null
	var parts := find_fusion_partners(item)
	parts.append(item)
	var level := 1
	for part in parts:
		level = maxi(level, part.item_level)
		GameState.remove_item(part)
	var candidates := Database.get_items_for_slot(item.get_base().slot)
	var result := LootGenerator.create_item(candidates.pick_random(), item.tier + 1, level)
	GameState.add_item(result)
	return result
