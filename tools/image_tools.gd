extends RefCounted
## Общие функции обработки сгенерированных картинок (листы интерфейса, ленты анимаций).
## Используется инструментами: const ImageTools := preload("res://tools/image_tools.gd")

const DEFAULT_MIN_BRIGHTNESS := 0.82
const DEFAULT_MAX_SATURATION := 0.12


static func is_background(color: Color, min_brightness: float, max_saturation: float) -> bool:
	var brightness := (color.r + color.g + color.b) / 3.0
	var saturation := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	return color.a < 0.1 or (brightness >= min_brightness and saturation <= max_saturation)


## Заливка от краёв: весь связный светлый фон (в т.ч. нарисованная «шахматка») становится прозрачным.
static func remove_background(image: Image, min_brightness := DEFAULT_MIN_BRIGHTNESS, max_saturation := DEFAULT_MAX_SATURATION) -> void:
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
		if not is_background(image.get_pixel(x, y), min_brightness, max_saturation):
			continue
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0: stack.append(index - 1)
		if x < w - 1: stack.append(index + 1)
		if y > 0: stack.append(index - w)
		if y < h - 1: stack.append(index + w)


## Связные области непрозрачных пикселей → прямоугольники (сверху вниз, слева направо).
static func find_elements(image: Image, min_area := 200) -> Array[Rect2i]:
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
		if area >= min_area:
			boxes.append(Rect2i(min_p, max_p - min_p + Vector2i.ONE))
	boxes.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		if absi(a.position.y - b.position.y) > 40:
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
	return boxes


## Размер «пикселя» арта: нижний квартиль длин одноцветных отрезков по рядам.
static func estimate_pixel_size(image: Image, boxes: Array[Rect2i]) -> float:
	var runs: Array[int] = []
	for box in boxes:
		for y in range(box.position.y, box.end.y, 3):
			var run := 1
			var previous := image.get_pixel(box.position.x, y)
			for x in range(box.position.x + 1, box.end.x):
				var color := image.get_pixel(x, y)
				if similar(color, previous):
					run += 1
				else:
					if run >= 2 and run <= 24:
						runs.append(run)
					run = 1
				previous = color
	if runs.is_empty():
		return 1.0
	runs.sort()
	return float(runs[runs.size() / 4])


static func similar(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) < 0.12


## Уменьшение: каждый «пиксель» арта берётся из центра своего блока (без смешивания цветов).
static func downscale(source: Image, pixel_size: float) -> Image:
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
