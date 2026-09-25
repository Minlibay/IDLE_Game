extends Node
## Реестр игровых данных. Загружает все .tres из папок data/ при старте.
## Чтобы добавить класс/монстра/предмет — положите новый .tres в нужную папку.

const CLASSES_DIR := "res://data/classes"
const MONSTERS_DIR := "res://data/monsters"
const ITEMS_DIR := "res://data/items"
const BUILDINGS_DIR := "res://data/buildings"
const NEEDS_DIR := "res://data/needs"

var classes: Array[CharacterClass] = []
var monsters: Array[MonsterData] = []
var items: Array[ItemBase] = []
var buildings: Array[BuildingData] = []
var needs: Array[NeedData] = []

var _classes_by_id: Dictionary[String, CharacterClass] = {}
var _items_by_id: Dictionary[String, ItemBase] = {}
var _buildings_by_id: Dictionary[String, BuildingData] = {}


func _ready() -> void:
	for res in _load_dir(CLASSES_DIR):
		var class_data := res as CharacterClass
		if class_data:
			classes.append(class_data)
			_classes_by_id[class_data.id] = class_data
	classes.sort_custom(func(a: CharacterClass, b: CharacterClass) -> bool: return a.order < b.order)

	for res in _load_dir(MONSTERS_DIR):
		var monster := res as MonsterData
		if monster:
			monsters.append(monster)

	for res in _load_dir(ITEMS_DIR):
		var item := res as ItemBase
		if item:
			items.append(item)
			_items_by_id[item.id] = item

	for res in _load_dir(BUILDINGS_DIR):
		var building := res as BuildingData
		if building:
			buildings.append(building)
			_buildings_by_id[building.id] = building
	buildings.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return a.order < b.order)

	for res in _load_dir(NEEDS_DIR):
		var need := res as NeedData
		if need:
			needs.append(need)
	needs.sort_custom(func(a: NeedData, b: NeedData) -> bool: return a.order < b.order)


func get_class_data(id: String) -> CharacterClass:
	return _classes_by_id.get(id)


func get_item_base(id: String) -> ItemBase:
	return _items_by_id.get(id)


func get_building(id: String) -> BuildingData:
	return _buildings_by_id.get(id)


func get_items_for_slot(slot: int) -> Array[ItemBase]:
	var result: Array[ItemBase] = []
	result.assign(items.filter(func(item: ItemBase) -> bool: return item.slot == slot))
	return result


func get_monsters_for_wave(wave: int, bosses: bool) -> Array[MonsterData]:
	var result: Array[MonsterData] = []
	result.assign(monsters.filter(func(m: MonsterData) -> bool: return m.is_boss == bosses and m.min_wave <= wave))
	return result


func _load_dir(path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	for file in DirAccess.get_files_at(path):
		# В экспортированной игре ресурсы лежат как *.tres.remap
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var res := load(path.path_join(file_name))
			if res:
				result.append(res)
	return result
