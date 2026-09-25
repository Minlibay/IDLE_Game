class_name ItemBase
extends Resource
## Шаблон предмета (например «Ржавый меч»). Конкретные выпавшие предметы — это Item.
## Новый предмет = новый .tres в data/items/.

enum Slot { WEAPON, ARMOR, HELMET, TRINKET }

const SLOT_NAMES := {
	Slot.WEAPON: "Оружие",
	Slot.ARMOR: "Броня",
	Slot.HELMET: "Шлем",
	Slot.TRINKET: "Аксессуар",
}

@export var id := ""
@export var display_name := ""
@export var slot: Slot = Slot.WEAPON
@export var icon: Texture2D
## Базовые статы для обычного тира 1-го уровня. Ключи: damage, max_hp, armor, attack_speed, crit_chance.
@export var base_stats: Dictionary = {}
## Какие классы могут надеть. Пусто = все.
@export var allowed_classes: PackedStringArray = []


func can_be_used_by(class_id: String) -> bool:
	return allowed_classes.is_empty() or allowed_classes.has(class_id)


static func slot_name(value: int) -> String:
	return SLOT_NAMES.get(value, "?")
