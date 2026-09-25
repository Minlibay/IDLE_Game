extends RefCounted
## Раскладка нарезанного листа (результат tools/slice_ui_sheet.gd) по сетке «ряды × колонки».
## Общая логика для tools/place_set_icons.gd и tools/place_sheet_sprites.gd:
##   - мелкие обрезки (искры, частицы) отбрасываются;
##   - ряды — по самым большим разрывам по вертикали;
##   - в ряду куски распределяются по колонкам (к ближайшему центру, центры уточняются по площади),
##     поэтому половинки одного предмета (пара наплечников, сапог) склеиваются в одну картинку.

## Кусок меньше этой доли самого крупного — искра/частица, отбрасывается.
const MIN_AREA_SHARE := 0.04


## Возвращает ряды → колонки → группы кусков (элементы манифеста). Ошибка — пустой массив и push_error.
static func layout(manifest: Dictionary, rows: int, columns: int) -> Array:
	var elements: Array = manifest.get("elements", [])
	var max_area := 0.0
	for element: Dictionary in elements:
		max_area = maxf(max_area, _area(element))
	elements = elements.filter(func(element: Dictionary) -> bool: return _area(element) >= max_area * MIN_AREA_SHARE)
	var result := []
	for row: Array in _split_rows(elements, rows):
		var groups := _cluster_columns(row, columns)
		if groups.size() != columns:
			push_error("Row %d: found %d items instead of %d" % [result.size() + 1, groups.size(), columns])
			return []
		result.append(groups)
	return result


## Собирает группу кусков в одну картинку (по их положению на листе).
static func compose(dir: String, group: Array, pixel_size: float) -> Image:
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


static func _split_rows(elements: Array, count: int) -> Array:
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


static func _cluster_columns(row: Array, count: int) -> Array:
	var min_x := INF
	var max_x := -INF
	for element: Dictionary in row:
		min_x = minf(min_x, _center_x(element))
		max_x = maxf(max_x, _center_x(element))
	var centers := []
	for i in count:
		centers.append(lerpf(min_x, max_x, float(i) / maxf(1.0, count - 1)))
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


static func _rect(element: Dictionary) -> Rect2:
	var r: Array = element.sheet_rect
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


static func _area(element: Dictionary) -> float:
	return float(element.sheet_rect[2]) * float(element.sheet_rect[3])


static func _center_x(element: Dictionary) -> float:
	return float(element.sheet_rect[0]) + float(element.sheet_rect[2]) * 0.5


static func _center_y(element: Dictionary) -> float:
	return float(element.sheet_rect[1]) + float(element.sheet_rect[3]) * 0.5
