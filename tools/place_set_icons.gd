extends SceneTree
## Раскладывает нарезанный лист иконок сетов (ряды по 5: шлем, плечи, грудь, ноги, ботинки)
## по именам частей: assets/sprites/treasures/<id сета>_<слот>.png. Иконку подхватит TreasureCatalog.
##
## 1. Нарезать лист:  Godot.exe --headless --path . --script res://tools/slice_ui_sheet.gd -- <лист> <папка> p 5
## 2. Разложить:      Godot.exe --headless --path . --script res://tools/place_set_icons.gd -- <папка> p <сет ряда 1> [сет ряда 2]
##
## Пары (наплечники, сапоги) бывают нарисованы двумя отдельными половинками — они склеиваются
## в одну иконку (по колонкам листа). Мелкие обрезки (искры свечения) отбрасываются.

const OUT_DIR := "res://assets/sprites/treasures/"
const SLOTS := ["helmet", "shoulders", "armor", "legs", "boots"]
## Кусок меньше этой доли самого крупного — искра/частица, отбрасывается.
const MIN_AREA_SHARE := 0.04


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- <slice_dir> <prefix> <set_row1> [set_row2 ...]")
		quit(1)
		return
	var dir: String = args[0]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(args[1] + ".json")))
	var pixel_size := float(manifest.get("pixel_size", 1.0))
	var sets: Array = args.slice(2)
	var elements: Array = manifest.get("elements", [])
	var max_area := 0.0
	for element: Dictionary in elements:
		max_area = maxf(max_area, _area(element))
	elements = elements.filter(func(element: Dictionary) -> bool: return _area(element) >= max_area * MIN_AREA_SHARE)
	var rows := _split_rows(elements, sets.size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ok := true
	for row in rows.size():
		var groups := _merge_row(rows[row])
		if groups.size() != SLOTS.size():
			push_error("Row %d (%s): found %d items instead of %d" % [row + 1, sets[row], groups.size(), SLOTS.size()])
			ok = false
			continue
		for i in groups.size():
			var target := OUT_DIR + "%s_%s.png" % [sets[row], SLOTS[i]]
			_compose(dir, groups[i], pixel_size).save_png(ProjectSettings.globalize_path(target))
			print("  %s  <-  %d piece(s)" % [target, (groups[i] as Array).size()])
	quit(0 if ok else 1)


## Делит элементы на count рядов по самым большим разрывам между центрами по вертикали.
func _split_rows(elements: Array, count: int) -> Array:
	elements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _center_y(a) < _center_y(b))
	var gaps := []
	for i in range(1, elements.size()):
		gaps.append([_center_y(elements[i]) - _center_y(elements[i - 1]), i])
	gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var cuts := []
	for i in mini(count - 1, gaps.size()):
		cuts.append(gaps[i][1])
	cuts.sort()
	var rows := []
	var start := 0
	for cut: int in cuts:
		rows.append(elements.slice(start, cut))
		start = cut
	rows.append(elements.slice(start))
	return rows


## Внутри ряда куски распределяются по 5 колонкам: каждый — к ближайшему центру колонки
## (центры уточняются по самим кускам, с весом по площади). Так обе половинки пары попадают
## в свою колонку, даже если одна из них ближе к соседнему предмету, чем к своей паре.
func _merge_row(row: Array) -> Array:
	var count := SLOTS.size()
	var min_x := INF
	var max_x := -INF
	for element: Dictionary in row:
		min_x = minf(min_x, _center_x(element))
		max_x = maxf(max_x, _center_x(element))
	var centers := []
	for i in count:
		centers.append(lerpf(min_x, max_x, float(i) / (count - 1)))
	var groups := []
	for iteration in 20:
		groups = []
		for i in count:
			groups.append([])
		for element: Dictionary in row:
			var best := 0
			for i in count:
				if absf(_center_x(element) - centers[i]) < absf(_center_x(element) - centers[best]):
					best = i
			(groups[best] as Array).append(element)
		for i in count:
			var weight := 0.0
			var sum := 0.0
			for element: Dictionary in groups[i]:
				weight += _area(element)
				sum += _center_x(element) * _area(element)
			if weight > 0.0:
				centers[i] = sum / weight
	return groups.filter(func(group: Array) -> bool: return not group.is_empty())


func _center_x(element: Dictionary) -> float:
	return float(element.sheet_rect[0]) + float(element.sheet_rect[2]) * 0.5


## Собирает группу кусков в одну картинку (по их положению на листе).
func _compose(dir: String, group: Array, pixel_size: float) -> Image:
	var bounds := Rect2()
	for i in group.size():
		var rect := _rect(group[i])
		bounds = rect if i == 0 else bounds.merge(rect)
	var origin := bounds.position / pixel_size
	var images := []
	var size := Vector2i.ZERO
	for element: Dictionary in group:
		var image := Image.load_from_file(dir.path_join(str(element.file)))
		var offset := Vector2i((_rect(element).position / pixel_size - origin).round())
		images.append([image, offset])
		size = size.max(offset + image.get_size())
	var result := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for entry: Array in images:
		var image: Image = entry[0]
		result.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), entry[1])
	return result


func _rect(element: Dictionary) -> Rect2:
	var r: Array = element.sheet_rect
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


func _area(element: Dictionary) -> float:
	return float(element.sheet_rect[2]) * float(element.sheet_rect[3])


func _center_y(element: Dictionary) -> float:
	return float(element.sheet_rect[1]) + float(element.sheet_rect[3]) * 0.5
