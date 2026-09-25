extends Node
## Реестр игровых данных. Загружает все .tres из папок data/ при старте.
## Чтобы добавить класс/монстра/предмет — положите новый .tres в нужную папку.

const CLASSES_DIR := "res://data/classes"
const MONSTERS_DIR := "res://data/monsters"
const ITEMS_DIR := "res://data/items"
const BUILDINGS_DIR := "res://data/buildings"
const NEEDS_DIR := "res://data/needs"
const UNITS_DIR := "res://data/units"
const BIOMES_DIR := "res://data/biomes"
## Сколько волн длится биом (последняя — волна босса).
const WAVES_PER_BIOME := 10

var classes: Array[CharacterClass] = []
var monsters: Array[MonsterData] = []
var items: Array[ItemBase] = []
var buildings: Array[BuildingData] = []
var needs: Array[NeedData] = []
var units: Array[UnitData] = []
## Биомы по порядку: лес → кладбище → горы → … и снова по кругу.
var biomes: Array[BiomeData] = []
## Сокровища (именные, уникальные, сетовые) из data/treasures/*.json — в пул дропа с монстров не входят.
var treasures: Array[ItemBase] = []
var item_sets: Dictionary[String, ItemSetData] = {}

var _classes_by_id: Dictionary[String, CharacterClass] = {}
var _items_by_id: Dictionary[String, ItemBase] = {}
var _buildings_by_id: Dictionary[String, BuildingData] = {}
var _units_by_id: Dictionary[String, UnitData] = {}
var _monsters_by_id: Dictionary[String, MonsterData] = {}


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
			_monsters_by_id[monster.id] = monster

	for res in _load_dir(BIOMES_DIR):
		var biome := res as BiomeData
		if biome:
			biomes.append(biome)
	biomes.sort_custom(func(a: BiomeData, b: BiomeData) -> bool: return a.order < b.order)

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

	for res in _load_dir(UNITS_DIR):
		var unit := res as UnitData
		if unit:
			units.append(unit)
			_units_by_id[unit.id] = unit
	units.sort_custom(func(a: UnitData, b: UnitData) -> bool: return a.order < b.order)

	var catalog := TreasureCatalog.new()
	catalog.load_all(items)
	treasures = catalog.items
	item_sets = catalog.sets
	for treasure in treasures:
		_items_by_id[treasure.id] = treasure
	retranslate()


## Переводит тексты данных (имена, описания) на текущий язык Settings.
## Русский оригинал каждого поля запоминается в мета-поле ресурса, так что язык можно менять сколько угодно раз.
func retranslate() -> void:
	var seen := {}
	for list: Array in [classes, monsters, items, buildings, needs, units, biomes, treasures, item_sets.values()]:
		for data: Object in list:
			_translate_object(data, seen)
	# Узлы талантов собираются из названий при первом обращении — пересобираем с новыми названиями.
	for class_data in classes:
		if class_data.talent_tree:
			class_data.talent_tree.reset()


## Данные — ресурсы и объекты со своим скриптом (ItemSetData — RefCounted); текстуры и сцены пропускаются.
func _translate_object(data: Object, seen: Dictionary) -> void:
	if data == null or seen.has(data) or data.get_script() == null:
		return
	seen[data] = true
	var originals: Dictionary = data.get_meta(&"i18n", {})
	for property in data.get_property_list():
		if not property.usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = property.name
		var value: Variant = data.get(key)
		match typeof(value):
			TYPE_STRING:
				if originals.has(key) or _is_russian(value):
					originals[key] = originals.get(key, value)
					data.set(key, tr(originals[key]))
			TYPE_PACKED_STRING_ARRAY:
				if originals.has(key) or Array(value).any(_is_russian):
					originals[key] = originals.get(key, value)
					var translated := PackedStringArray()
					for text: String in originals[key]:
						translated.append(tr(text))
					data.set(key, translated)
			TYPE_OBJECT:
				_translate_object(value, seen)
			TYPE_ARRAY:
				for element: Variant in value:
					if element is Object:
						_translate_object(element, seen)
	if not originals.is_empty():
		data.set_meta(&"i18n", originals)


static func _is_russian(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code >= 0x0410 and code <= 0x044F) or code == 0x0401 or code == 0x0451:
			return true
	return false


func get_class_data(id: String) -> CharacterClass:
	return _classes_by_id.get(id)


func get_item_base(id: String) -> ItemBase:
	return _items_by_id.get(id)


func get_item_set(id: String) -> ItemSetData:
	return item_sets.get(id)


## Сокровища класса (для каталога и тестов).
func get_treasures_for_class(class_id: String) -> Array[ItemBase]:
	var result: Array[ItemBase] = []
	result.assign(treasures.filter(func(item: ItemBase) -> bool: return item.can_be_used_by(class_id)))
	return result


func get_building(id: String) -> BuildingData:
	return _buildings_by_id.get(id)


func get_unit(id: String) -> UnitData:
	return _units_by_id.get(id)


func get_items_for_slot(slot: int) -> Array[ItemBase]:
	var result: Array[ItemBase] = []
	result.assign(items.filter(func(item: ItemBase) -> bool: return item.slot == slot))
	return result


func get_monster(id: String) -> MonsterData:
	return _monsters_by_id.get(id)


## Биом волны: по 10 волн на биом, после последнего — снова первый.
func get_biome_for_wave(wave: int) -> BiomeData:
	if biomes.is_empty():
		return null
	return biomes[int((maxi(1, wave) - 1) / WAVES_PER_BIOME) % biomes.size()]


## Номер волны внутри биома: 1..10.
func get_wave_in_biome(wave: int) -> int:
	return (maxi(1, wave) - 1) % WAVES_PER_BIOME + 1


## Монстры волны: из биома этой волны, открывшиеся к её номеру внутри биома (min_wave).
func get_monsters_for_wave(wave: int, bosses: bool) -> Array[MonsterData]:
	var biome := get_biome_for_wave(wave)
	var local_wave := get_wave_in_biome(wave)
	var result: Array[MonsterData] = []
	result.assign(monsters.filter(func(m: MonsterData) -> bool:
		return m.is_boss == bosses and (biome == null or m.biome == biome.id) and (bosses or m.min_wave <= local_wave)))
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
