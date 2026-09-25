extends SceneTree
## Нарезка ленты анимации (кадры в ряд, сгенерированы, например, в ChatGPT) в ровную ленту для игры.
##
##   Godot.exe --headless --path . --script res://tools/slice_animation_strip.gd -- <лента> <выход.png> [опции]
##
## Опции:
##   --frames=N        число кадров (по умолчанию — сколько фигур найдено)
##   --scale=S         размер «пикселя» арта в исходнике (по умолчанию — автоопределение)
##   --height=H        подогнать масштаб так, чтобы фигура была H пикселей ростом (медиана по кадрам)
##   --match=<json>    подогнать размер под другую ленту (обычно idle) — все анимации одного размера.
##                     Сравнивается ПЛОЩАДЬ фигуры (медиана по кадрам): в отличие от высоты, её почти не
##                     меняют поднятый меч, присед или прыжок.
##   --bg=B            минимальная яркость фона (0.82; для нарисованной «шахматки» ~0.6)
##
## Как режется:
## - каждая фигура (связная область, вместе с мечом) относится к «своей» ячейке ленты по центру;
##   фигура берётся целиком, даже если меч заходит в соседнюю ячейку, а чужие фигуры в кадр не попадают;
## - из всех кадров вырезается одна общая область, так персонаж не дрожит и ноги на одной линии;
## - якорь (anchor_x) — где корпус персонажа в кадре; игра по нему совмещает разные анимации.
## Результат — лента одинаковых кадров <выход.png> + <выход>.json.

const ImageTools := preload("res://tools/image_tools.gd")
## Отступ вокруг персонажа в итоговом кадре (пиксели арта).
const PADDING := 1
## Фигуры меньше этой площади (в пикселях исходника) — мелкие детали, они приклеиваются к ближайшему кадру.
const MIN_FIGURE_AREA := 2000
## Фигура считается отдельным кадром, если она не меньше этой доли самой крупной фигуры.
const FIGURE_MIN_SHARE := 0.25


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var options := _parse_options(args)
	if args.size() < 2:
		push_error("Usage: -- <strip> <out.png> [--frames=N] [--scale=S] [--height=H] [--match=idle.json] [--bg=B]")
		quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
	if image == null:
		push_error("Cannot load " + args[0])
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	var min_brightness := float(options.get("bg", ImageTools.DEFAULT_MIN_BRIGHTNESS))
	ImageTools.remove_background(image, min_brightness)

	var labels := _label_components(image)
	var components: Array = labels.components
	# Кадр = крупная фигура: не меньше четверти самой большой (выпавший меч или осколки — не кадр,
	# они приклеиваются к кадру своей ячейки).
	var max_area := 0
	for c: Dictionary in components:
		max_area = maxi(max_area, int(c.area))
	var figure_min_area := maxf(MIN_FIGURE_AREA, max_area * FIGURE_MIN_SHARE)
	var big := components.filter(func(c: Dictionary) -> bool: return c.area >= figure_min_area)
	var frame_count := int(options.get("frames", big.size()))
	var boxes: Array[Rect2i] = []
	for c: Dictionary in big:
		boxes.append(c.rect)
	if frame_count <= 0:
		push_error("No frames found")
		quit(1)
		return

	# Каждая область -> кадр по центру своей рамки.
	var cell_width := image.get_width() / float(frame_count)
	var frame_of := PackedInt32Array()
	frame_of.resize(components.size())
	var frame_rects: Array[Rect2i] = []
	frame_rects.resize(frame_count)
	var frame_areas := PackedInt32Array()
	frame_areas.resize(frame_count)
	for i in components.size():
		var rect: Rect2i = components[i].rect
		var frame := clampi(int(rect.get_center().x / cell_width), 0, frame_count - 1)
		frame_of[i] = frame
		frame_areas[frame] += int(components[i].area)
		frame_rects[frame] = rect if not frame_rects[frame].has_area() else frame_rects[frame].merge(rect)

	# Масштаб: явный, по росту фигуры (свой или взятый из другой ленты) или автоопределение.
	var heights: Array[int] = []
	for rect in frame_rects:
		if rect.has_area():
			heights.append(rect.size.y)
	heights.sort()
	var median_height := heights[heights.size() / 2]
	var areas: Array[int] = []
	for area in frame_areas:
		if area > 0:
			areas.append(area)
	areas.sort()
	var median_area := areas[areas.size() / 2]
	var target_height := float(options.get("height", 0.0))
	var target_area := 0.0
	if options.has("match"):
		var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(options.match))
		if reference is Dictionary and reference.has("figure_area"):
			target_area = float(reference.figure_area)
		elif reference is Dictionary and reference.has("figure_height"):
			target_height = float(reference.figure_height)
	var pixel_size := float(options.get("scale", 0.0))
	if pixel_size <= 0.0:
		if target_area > 0.0:
			pixel_size = sqrt(median_area / target_area)
		elif target_height > 0.0:
			pixel_size = median_height / target_height
		else:
			pixel_size = ImageTools.estimate_pixel_size(image, boxes)

	# Общая область в координатах ячейки.
	var union := Rect2i()
	for frame in frame_count:
		if not frame_rects[frame].has_area():
			continue
		var local := Rect2i(frame_rects[frame].position - Vector2i(int(frame * cell_width), 0), frame_rects[frame].size)
		union = local if not union.has_area() else union.merge(local)
	union = union.grow(roundi(PADDING * pixel_size))

	var label_map: PackedInt32Array = labels.map
	var w := image.get_width()
	var frames: Array[Image] = []
	for frame in frame_count:
		var origin := Vector2i(int(frame * cell_width), 0) + union.position
		var region := Image.create_empty(union.size.x, union.size.y, false, Image.FORMAT_RGBA8)
		for y in union.size.y:
			for x in union.size.x:
				var p := origin + Vector2i(x, y)
				if p.x < 0 or p.y < 0 or p.x >= w or p.y >= image.get_height():
					continue
				var label := label_map[p.y * w + p.x]
				if label >= 0 and frame_of[label] == frame:
					region.set_pixel(x, y, image.get_pixelv(p))
		frames.append(ImageTools.downscale(region, pixel_size))

	var fw := frames[0].get_width()
	var fh := frames[0].get_height()
	var strip := Image.create_empty(fw * frame_count, fh, false, Image.FORMAT_RGBA8)
	for i in frame_count:
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(i * fw, 0))

	var out_path: String = args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	strip.save_png(out_path)
	var anchor_x := _body_anchor(frames[0])
	var meta := FileAccess.open(out_path.get_basename() + ".json", FileAccess.WRITE)
	meta.store_string(JSON.stringify({"frames": frame_count, "frame_width": fw, "frame_height": fh,
		"anchor_x": anchor_x, "figure_height": roundi(median_height / pixel_size),
		"figure_area": roundi(median_area / (pixel_size * pixel_size)), "pixel_size": pixel_size}, "  "))
	print("%s: %d frames %dx%d, anchor x=%d (pixel size %.2f, figures %d)" % [
		out_path.get_file(), frame_count, fw, fh, anchor_x, pixel_size, big.size()])
	quit()


## Именованные опции вида --key=value (позиционные аргументы остаются в args).
func _parse_options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			options[parts[0]] = parts[1]
	return options


## Метки связных областей: map[i] = номер области или -1 (фон).
func _label_components(image: Image) -> Dictionary:
	var w := image.get_width()
	var h := image.get_height()
	var map := PackedInt32Array()
	map.resize(w * h)
	map.fill(-1)
	var components: Array = []
	for start in w * h:
		if map[start] >= 0 or image.get_pixel(start % w, start / w).a < 0.5:
			continue
		var label := components.size()
		var min_p := Vector2i(w, h)
		var max_p := Vector2i(-1, -1)
		var area := 0
		var stack := PackedInt32Array([start])
		map[start] = label
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
				if map[n_index] < 0 and image.get_pixel(n.x, n.y).a >= 0.5:
					map[n_index] = label
					stack.append(n_index)
		components.append({"rect": Rect2i(min_p, max_p - min_p + Vector2i.ONE), "area": area})
	return {"map": map, "components": components}


## Якорь корпуса: медиана по X непрозрачных пикселей нижней половины кадра
## (ноги и корпус; поднятый меч и плюмаж не сдвигают якорь).
func _body_anchor(frame: Image) -> int:
	var xs: Array[int] = []
	for y in range(frame.get_height() / 2, frame.get_height()):
		for x in frame.get_width():
			if frame.get_pixel(x, y).a >= 0.5:
				xs.append(x)
	if xs.is_empty():
		return frame.get_width() / 2
	xs.sort()
	return xs[xs.size() / 2]
