class_name ItemBase
extends Resource
## Шаблон предмета (например «Ржавый меч»). Конкретные выпавшие предметы — это Item.
## Обычные предметы (выпадают с монстров) — .tres в data/items/.
## Сокровища (именные, уникальные, сетовые) — из каталога data/treasures/*.json (см. TreasureCatalog):
## выпадают по игровому времени с сервера, привязаны к классу, позже — предметы Steam.

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

## MOB — обычный предмет с монстров; остальные — сокровища.
enum Quality { MOB, NAMED, UNIQUE, LEGENDARY }
const QUALITY_NAMES := {
	Quality.NAMED: "Именной", Quality.UNIQUE: "Уникальный", Quality.LEGENDARY: "Легендарный",
}
const QUALITY_COLORS := {
	Quality.NAMED: Color(0.3, 0.88, 0.82), Quality.UNIQUE: Color(1.0, 0.38, 0.36), Quality.LEGENDARY: Color(1.0, 0.8, 0.28),
}

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

@export_group("Treasure")
@export var quality: Quality = Quality.MOB
## Сет, частью которого является предмет ("" — не сетовый).
@export var set_id := ""
## Процентные бонусы сокровища (через общую систему StatModifier).
@export var modifiers: Array[StatModifier] = []
## Оттенок иконки (пока у сокровища нет своей картинки — иконка слота в цвете сета).
@export var icon_tint := Color.WHITE


func can_be_used_by(class_id: String) -> bool:
	return allowed_classes.is_empty() or allowed_classes.has(class_id)


func is_army_relic() -> bool:
	return slot == Slot.ARMY


## Сокровище: именной, уникальный или сетовый предмет (не с монстров).
func is_treasure() -> bool:
	return quality != Quality.MOB


static func slot_name(value: int) -> String:
	return TranslationServer.translate(SLOT_NAMES.get(value, "?"))
