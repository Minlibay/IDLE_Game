class_name ItemSetData
extends RefCounted
## Сет сокровищ (как в WoW): 5 частей одного класса и бонусы за 2, 4 и 5 надетых частей.
## Собирается TreasureCatalog из data/treasures/<класс>.json.

## Бонус сета: действует, если надето не меньше pieces частей.
class Bonus:
	var pieces := 2
	var modifiers: Array[StatModifier] = []
	## За полный сет вокруг героя появляется аура цвета сета.
	var aura := false

var id := ""
var display_name := ""
var class_id := ""
var season := 1
var color := Color.WHITE
var lore := ""
## id частей (ItemBase) в порядке слотов.
var piece_ids: PackedStringArray = []
var bonuses: Array[Bonus] = []


func get_piece_count() -> int:
	return piece_ids.size()


## Описание бонуса одной строкой: «(2) +6% урона».
static func describe_bonus(bonus: Bonus) -> String:
	var text := "(%d) %s" % [bonus.pieces, StatModifier.describe_list(bonus.modifiers)]
	if bonus.aura:
		text += ", аура героя"
	return text
