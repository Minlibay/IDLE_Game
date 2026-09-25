extends SceneTree
## Нарезка листа интерфейса (сгенерированного, например, в ChatGPT) на отдельные элементы.
##
##   Godot.exe --headless --path . --script res://tools/slice_ui_sheet.gd -- <лист> <папка> <префикс> [масштаб|auto] [мин_яркость_фона] [макс_насыщенность_фона]
##
## 1. Убирает светлый фон (заливкой от краёв — светлые детали внутри элементов не трогаются).
##    Нарисованную «шахматку» прозрачности тоже убирает: задайте [мин_яркость_фона] ниже серых клеток (например 0.55).
## 2. Находит отдельные элементы (связные области непрозрачных пикселей).
## 3. Определяет размер «пикселя» пиксель-арта (или берёт [масштаб]) и уменьшает элементы до него.
## 4. Сохраняет <префикс>_<N>.png и <префикс>.json (координаты элементов на листе) в <папку>.

## Пиксель считается фоном, если он светлый и почти серый.
const DEFAULT_BACKGROUND_MIN_BRIGHTNESS := 0.82
const DEFAULT_BACKGROUND_MAX_SATURATION := 0.12
## Области меньше этой площади (в пикселях листа) — мусор/артефакты.
const MIN_ELEMENT_AREA := 200

var _background_min_brightness := DEFAULT_BACKGROUND_MIN_BRIGHTNESS
var _background_max_saturation := DEFAULT_BACKGROUND_MAX_SATURATION


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- <sheet> <out_dir> <prefix> [scale]")
		quit(1)
		return
	var sheet_path := ProjectSettings.globalize_path(args[0])
	var out_dir := args[1]
	var prefix := args[2]
	var image := Image.load_from_file(sheet_path)
	if image == null:
		push_error("Cannot load " + sheet_path)
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	if args.size() > 4:
		_background_min_brightness = float(args[4])
	if args.size() > 5:
		_background_max_saturation = float(args[5])
	_remove_background(image)
	var boxes := _find_elements(image)
	var scale := float(args[3]) if args.size() > 3 and args[3] != "auto" else _estimate_pixel_size(image, boxes)
	print("Sheet %dx%d, elements: %d, pixel size: %.2f" % [image.get_width(), image.get_height(), boxes.size(), scale])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var manifest := []
	for i in boxes.size():
		var box: Rect2i = boxes[i]
		var crop := image.get_region(box)
		var small := _downscale(crop, scale)
		var file_name := "%s_%d.png" % [prefix, i]
		small.save_png(out_dir.path_join(file_name))
		manifest.append({"file": file_name, "sheet_rect": [box.position.x, box.position.y, box.size.x, box.size.y],
			"size": [small.get_width(), small.get_height()]})
		print("  %s  sheet %s -> %dx%d" % [file_name, str(box), small.get_width(), small.get_height()])
	var json := FileAccess.open(out_dir.path_join(prefix + ".json"), FileAccess.WRITE)
	json.store_string(JSON.stringify({"pixel_size": scale, "elements": manifest}, "  "))
	quit()


func _is_background(color: Color) -> bool:
	var brightness := (color.r + color.g + color.b) / 3.0
	var saturation := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	return color.a < 0.1 or (brightness >= _background_min_brightness and saturation <= _background_max_saturation)


## Заливка от краёв листа: весь связный светлый фон становится прозрачным.
func _remove_background(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var index := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if visited[index]:
			continue
		visited[index] = 1
		var x := index % w
		var y := index / w
		if not _is_background(image.get_pixel(x, y)):
			continue
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0: stack.append(index - 1)
		if x < w - 1: stack.append(index + 1)
		if y > 0: stack.append(index - w)
		if y < h - 1: stack.append(index + w)


## Связные области непрозрачных пикселей → прямоугольники (сверху вниз, слева направо).
func _find_elements(image: Image) -> Array[Rect2i]:
	var w := image.get_width()
	var h := image.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var boxes: Array[Rect2i] = []
	for start in w * h:
		if visited[start] or image.get_pixel(start % w, start / w).a < 0.5:
			continue
		var min_p := Vector2i(w, h)
		var max_p := Vector2i(-1, -1)
		var area := 0
		var stack := PackedInt32Array([start])
		visited[start] = 1
		while not stack.is_empty():
			var index := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var p := Vector2i(index % w, index / w)
			area += 1
			min_p = Vector2i(mini(min_p.x, p.x), mini(min_p.y, p.y))
			max_p = Vector2i(maxi(max_p.x, p.x), maxi(max_p.y, p.y))
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := p + offset
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var n_index := n.y * w + n.x
				if not visited[n_index] and image.get_pixel(n.x, n.y).a >= 0.5:
					visited[n_index] = 1
					stack.append(n_index)
		if area >= MIN_ELEMENT_AREA:
			boxes.append(Rect2i(min_p, max_p - min_p + Vector2i.ONE))
	boxes.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		if absi(a.position.y - b.position.y) > 40:
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
	return boxes


## Размер «пикселя»: медиана длин одноцветных отрезков по рядам внутри элементов.
func _estimate_pixel_size(image: Image, boxes: Array[Rect2i]) -> float:
	var runs: Array[int] = []
	for box in boxes:
		for y in range(box.position.y, box.end.y, 3):
			var run := 1
			var previous := image.get_pixel(box.position.x, y)
			for x in range(box.position.x + 1, box.end.x):
				var color := image.get_pixel(x, y)
				if _similar(color, previous):
					run += 1
				else:
					if run >= 2 and run <= 24:
						runs.append(run)
					run = 1
				previous = color
	if runs.is_empty():
		return 1.0
	runs.sort()
	# Короткие отрезки — это отдельные «пиксели» арта; берём нижний квартиль.
	return float(runs[runs.size() / 4])


func _similar(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) < 0.12


## Уменьшение: каждый «пиксель» арта берётся из центра своего блока (без смешивания цветов).
func _downscale(source: Image, pixel_size: float) -> Image:
	var w := maxi(1, roundi(source.get_width() / pixel_size))
	var h := maxi(1, roundi(source.get_height() / pixel_size))
	var result := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var step := Vector2(source.get_width() / float(w), source.get_height() / float(h))
	for y in h:
		for x in w:
			var sx := mini(source.get_width() - 1, int((x + 0.5) * step.x))
			var sy := mini(source.get_height() - 1, int((y + 0.5) * step.y))
			var color := source.get_pixel(sx, sy)
			result.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0 if color.a >= 0.5 else 0.0))
	return result
