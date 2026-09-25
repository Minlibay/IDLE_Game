class_name ItemBase
extends Resource
## Шаблон предмета (например «Ржавый меч»). Конкретные выпавшие предметы — это Item.
## Новый предмет = новый .tres в data/items/.

## Новые слоты добавляйте ТОЛЬКО в конец: в .tres и сохранениях слот хранится числом.
## ARMY — реликвия армии (знамя, рог…): усиливает армию замка, а не героя; таких слотов 6.
enum Slot { WEAPON, ARMOR, HELMET, TRINKET, SHOULDERS, LEGS, BOOTS, ARMY }

const SLOT_NAMES := {
	Slot.WEAPON: "Оружие",
	Slot.ARMOR: "Броня",
	Slot.HELMET: "Шлем",
	Slot.TRINKET: "Аксессуар",
	Slot.SHOULDERS: "Плечи",
	Slot.LEGS: "Ноги",
	Slot.BOOTS: "Ботинки",
	Slot.ARMY: "Реликвия армии",
}
## Слоты экипировки героя (в порядке показа). Реликвии армии — отдельно, см. GameState.army_relics.
const HERO_SLOTS: Array[int] = [Slot.HELMET, Slot.SHOULDERS, Slot.ARMOR, Slot.LEGS, Slot.WEAPON, Slot.BOOTS, Slot.TRINKET]

@export var id := ""
@export var display_name := ""
## Короткое описание для карточки предмета.
@export_multiline var description := ""
@export var slot: Slot = Slot.WEAPON
@export var icon: Texture2D
## Базовые статы для обычного тира 1-го уровня. Ключи героя: damage, max_hp, armor, attack_speed,
## crit_chance; реликвий армии: army_power, army_attack, army_defense, training_speed, upkeep_reduction.
@export var base_stats: Dictionary = {}
## Относительный шанс выпадения среди всех предметов (1 — обычный, 0.5 — вдвое реже).
@export var drop_weight := 1.0
## Какие классы могут надеть. Пусто = все.
@export var allowed_classes: PackedStringArray = []


func can_be_used_by(class_id: String) -> bool:
	return allowed_classes.is_empty() or allowed_classes.has(class_id)


func is_army_relic() -> bool:
	return slot == Slot.ARMY


static func slot_name(value: int) -> String:
	return SLOT_NAMES.get(value, "?")
