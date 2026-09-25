class_name TalentTree
extends Resource
## Сетка талантов класса (~600 узлов). Узлы строятся детерминированно из настроек ниже,
## поэтому их id ("t_<x>_<y>") стабильны и сохранения не ломаются, пока настройки не меняются.
##
## Правило: изучать можно узел, соседний (по 4 сторонам) с уже изученным; старт в центре изучен всегда.
## Секторы (regions) делят сетку по углу вокруг центра. В каждом секторе:
##   малые узлы — один бонус из набора сектора, тем сильнее, чем дальше от центра;
##   значимые узлы (каждая notable_spacing-я клетка) — два бонуса, усиленные в notable_multiplier раз;
##   ключевые (keystones) — описаны вручную, ставятся у края своего сектора.

const START_ID := "start"

@export var grid_size := Vector2i(25, 24)
@export var regions: Array[TalentRegion] = []
@export var keystones: Array[TalentData] = []
## Поворот секторов (градусы): 0 — первый сектор начинается вправо от центра.
@export var region_angle_offset := 150.0
@export var notable_spacing := 4
@export var notable_multiplier := 3.0
## Прирост силы малого узла за клетку удаления от центра (0.04 = +4%).
@export var distance_growth := 0.04

var _talents: Array[TalentData] = []
var _by_id: Dictionary = {}
var _by_cell: Dictionary = {}


## Сбрасывает собранные узлы: при следующем обращении сетка соберётся заново (например, на другом языке).
func reset() -> void:
	_talents.clear()
	_by_id.clear()
	_by_cell.clear()


func get_talents() -> Array[TalentData]:
	_ensure_built()
	return _talents


func find(talent_id: String) -> TalentData:
	_ensure_built()
	return _by_id.get(talent_id)


func at(cell: Vector2i) -> TalentData:
	_ensure_built()
	return _by_cell.get(cell)


func get_start() -> TalentData:
	return find(START_ID)


func get_center() -> Vector2i:
	return grid_size / 2


func neighbors(talent: TalentData) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var other := at(talent.grid_position + offset)
		if other:
			result.append(other)
	return result


func region_of(cell: Vector2i) -> int:
	if regions.is_empty():
		return 0
	var rel := Vector2(cell - get_center())
	var angle := fposmod(rad_to_deg(atan2(rel.y, rel.x)) - region_angle_offset, 360.0)
	return mini(int(angle / (360.0 / regions.size())), regions.size() - 1)


func _ensure_built() -> void:
	if not _talents.is_empty() or regions.is_empty():
		return
	var center := get_center()
	var keystone_cells := _place_keystones()
	var notable_counters := PackedInt32Array()
	notable_counters.resize(regions.size())
	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var talent: TalentData
			if cell == center:
				talent = TalentData.new()
				talent.id = START_ID
				talent.display_name = tr("Начало пути")
				talent.description = tr("Отсюда растёт сетка талантов. Изучайте узлы рядом с уже изученными.")
				talent.kind = TalentData.Kind.START
				talent.icon = load("res://assets/ui/icons/talents.png")
			elif keystone_cells.has(cell):
				talent = keystone_cells[cell]
			else:
				var region := region_of(cell)
				var distance := Vector2(cell - center).length()
				if x % notable_spacing == 0 and y % notable_spacing == 0:
					talent = _make_notable(cell, region, distance, notable_counters[region])
					notable_counters[region] += 1
				else:
					talent = _make_minor(cell, region, distance)
			talent.grid_position = cell
			_talents.append(talent)
			_by_id[talent.id] = talent
			_by_cell[cell] = talent


## Ключевые таланты — у края сектора, по середине его угла (± region_offset).
func _place_keystones() -> Dictionary:
	var cells := {}
	var center := Vector2(get_center())
	var sector := 360.0 / maxf(1.0, regions.size())
	for keystone in keystones:
		var angle := deg_to_rad(region_angle_offset + sector * (keystone.region + 0.5 + keystone.region_offset * 0.35))
		var direction := Vector2(cos(angle), sin(angle))
		# Идём от центра по направлению, пока не упрёмся в край сетки.
		var cell := Vector2i(center)
		for step in range(1, grid_size.x + grid_size.y):
			var next := Vector2i((center + direction * step).round())
			if next.x < 0 or next.y < 0 or next.x >= grid_size.x or next.y >= grid_size.y:
				break
			cell = next
		while cells.has(cell):
			cell -= Vector2i(direction.round())
		keystone.kind = TalentData.Kind.KEYSTONE
		cells[cell] = keystone
	return cells


func _make_minor(cell: Vector2i, region: int, distance: float) -> TalentData:
	var pool := regions[region].minor_modifiers
	var source := pool[_hash(cell) % pool.size()]
	var talent := TalentData.new()
	talent.id = "t_%d_%d" % [cell.x, cell.y]
	talent.kind = TalentData.Kind.MINOR
	talent.region = region
	talent.modifiers = [_scaled(source, 1.0 + distance * distance_growth)]
	talent.display_name = tr(StatModifier.STAT_TITLES[source.stat])
	return talent


func _make_notable(cell: Vector2i, region: int, distance: float, index: int) -> TalentData:
	var pool := regions[region].minor_modifiers
	var first := _hash(cell) % pool.size()
	var second := (first + 1 + _hash(cell + Vector2i(7, 13)) % maxi(1, pool.size() - 1)) % pool.size()
	var scale := notable_multiplier * (1.0 + distance * distance_growth)
	var talent := TalentData.new()
	talent.id = "t_%d_%d" % [cell.x, cell.y]
	talent.kind = TalentData.Kind.NOTABLE
	talent.region = region
	talent.modifiers = [_scaled(pool[first], scale), _scaled(pool[second], scale)]
	var names := regions[region].notable_names
	talent.display_name = tr(names[index % names.size()]) if not names.is_empty() else regions[region].display_name
	return talent


func _scaled(source: StatModifier, multiplier: float) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = source.stat
	modifier.skill_id = source.skill_id
	modifier.value = snappedf(source.value * multiplier, 0.1)
	return modifier


## Детерминированный «случай» по клетке (одинаков при каждом запуске).
func _hash(cell: Vector2i) -> int:
	return absi(hash(cell.x * 73856093 ^ cell.y * 19349663))
