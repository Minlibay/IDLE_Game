extends SceneTree
## Измеряет отступы для 9-slice у нарезанных элементов интерфейса:
## сколько пикселей с каждой стороны занимают рамка и угловые украшения до однотонного центра.
##   Godot.exe --headless --path . --script res://tools/measure_ui_margins.gd -- <png> [<png> ...]


func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null:
			push_error("Cannot load " + path)
			continue
		image.convert(Image.FORMAT_RGBA8)
		var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		print("%s %dx%d center=%s margins L%d T%d R%d B%d" % [path.get_file(), image.get_width(), image.get_height(),
			center.to_html(false), _margin(image, center, 0), _margin(image, center, 1),
			_margin(image, center, 2), _margin(image, center, 3)])
	quit()


## side: 0 — слева, 1 — сверху, 2 — справа, 3 — снизу.
## Для каждой линии поперёк стороны ищем первый пиксель цвета центра; отступ = максимум по линиям.
func _margin(image: Image, center: Color, side: int) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var lines := h if side % 2 == 0 else w
	var depth := (w if side % 2 == 0 else h) / 2
	var result := 0
	for line in lines:
		# Внешняя тень бывает цвета центра — сначала дожидаемся самой рамки.
		var seen_border := false
		for d in depth:
			var p := Vector2i.ZERO
			match side:
				0: p = Vector2i(d, line)
				1: p = Vector2i(line, d)
				2: p = Vector2i(w - 1 - d, line)
				3: p = Vector2i(line, h - 1 - d)
			var is_center := _similar(image.get_pixelv(p), center)
			if not is_center:
				seen_border = true
			elif seen_border:
				result = maxi(result, d)
				break
	return result


func _similar(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.1 and a.a > 0.5
