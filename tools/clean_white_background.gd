extends SceneTree
## Убирает остатки белого фона в нарезанных картинках (после tools/slice_ui_sheet.gd):
##   1) «карманы» — сплошные белые пятна, запертые внутри силуэта (между луком и тетивой, рукой и телом):
##      заливка фона от краёв листа до них не доходит. Пятно считается фоном, если оно почти чисто белое
##      и окружено в основном тёмным контуром или прозрачностью (белые детали рисунка — блики, кости,
##      серебро, снег — окружены своими полутонами, их инструмент не трогает);
##   2) кайму — светлые серые пиксели, прилегающие к прозрачному краю.
##
##   Godot.exe --headless --path . --script res://tools/clean_white_background.gd -- [--dry-run] <файл.png или папка> ...
##
## Папки обходятся рекурсивно (кроме source/). Печатает, сколько пикселей убрано в каждом файле.
## Запускайте ОДИН раз сразу после нарезки: повторный проход снимает следующий светлый слой у краёв
## и может подъедать белые детали рисунка. Интерфейс (assets/ui) не чистить — там белое нарисовано.

## Почти чисто белое (кандидат в фон).
const WHITE_MIN := 0.9
const WHITE_MAX_SATURATION := 0.08
## Кайма: светлое и почти серое у прозрачного края.
const FRINGE_MIN_VALUE := 0.8
const FRINGE_MAX_SATURATION := 0.14
## Пятно внутри силуэта — фон, если его соседи в основном тёмные/прозрачные и оно не крошечное.
const POCKET_MIN_SIZE := 6
const POCKET_DARK_VALUE := 0.42
const POCKET_DARK_SHARE := 0.55

var _dry_run := false


func _initialize() -> void:
	var paths := []
	for arg in OS.get_cmdline_user_args():
		if arg == "--dry-run":
			_dry_run = true
		else:
			paths.append(arg)
	var files := []
	for path: String in paths:
		if path.ends_with(".png"):
			files.append(path)
		else:
			_collect(path, files)
	var total := 0
	for file: String in files:
		var removed := _clean(file)
		if removed > 0:
			total += 1
			print("  %4d px  %s" % [removed, file])
	print("%s %d of %d files" % ["Would clean" if _dry_run else "Cleaned", total, files.size()])
	quit()


func _clean(path: String) -> int:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		return 0
	image.convert(Image.FORMAT_RGBA8)
	var removed := _remove_pockets(image) + _remove_fringe(image)
	if removed > 0 and not _dry_run:
		image.save_png(ProjectSettings.globalize_path(path))
	return removed


## Белые пятна (4-связные), запертые тёмным контуром или касающиеся прозрачности.
func _remove_pockets(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var removed := 0
	for start_y in h:
		for start_x in w:
			var index := start_y * w + start_x
			if seen[index] or not _is_white(image.get_pixel(start_x, start_y)):
				continue
			var component: Array[Vector2i] = []
			var neighbours := {}
			var stack: Array[Vector2i] = [Vector2i(start_x, start_y)]
			seen[index] = 1
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				component.append(p)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := p + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
						neighbours[q] = true  # край картинки — как прозрачность
						continue
					var qi := q.y * w + q.x
					if seen[qi]:
						continue
					if _is_white(image.get_pixelv(q)):
						seen[qi] = 1
						stack.append(q)
					else:
						neighbours[q] = true
			if component.size() < POCKET_MIN_SIZE:
				continue
			var dark := 0
			for q: Vector2i in neighbours:
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					dark += 1
					continue
				var c := image.get_pixelv(q)
				if c.a < 0.05 or c.v < POCKET_DARK_VALUE:
					dark += 1
			if float(dark) / maxf(1.0, neighbours.size()) < POCKET_DARK_SHARE:
				continue
			for p in component:
				image.set_pixelv(p, Color(0, 0, 0, 0))
			removed += component.size()
	return removed


## Светлые серые пиксели у прозрачного края (2 прохода — кайма бывает в 2 пикселя).
func _remove_fringe(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var removed := 0
	for pass_index in 2:
		var to_clear: Array[Vector2i] = []
		for y in h:
			for x in w:
				var c := image.get_pixel(x, y)
				if c.a < 0.05 or c.v < FRINGE_MIN_VALUE or c.s > FRINGE_MAX_SATURATION:
					continue
				if _touches_transparency(image, x, y):
					to_clear.append(Vector2i(x, y))
		for p in to_clear:
			image.set_pixelv(p, Color(0, 0, 0, 0))
		removed += to_clear.size()
		if to_clear.is_empty():
			break
	return removed


func _touches_transparency(image: Image, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q := Vector2i(x, y) + d
		if q.x < 0 or q.y < 0 or q.x >= image.get_width() or q.y >= image.get_height():
			return true
		if image.get_pixelv(q).a < 0.05:
			return true
	return false


func _is_white(c: Color) -> bool:
	return c.a > 0.5 and minf(c.r, minf(c.g, c.b)) >= WHITE_MIN and c.s <= WHITE_MAX_SATURATION


func _collect(dir: String, out: Array) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".png"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if sub != "source":
			_collect(dir.path_join(sub), out)
