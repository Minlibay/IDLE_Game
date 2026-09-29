extends SceneTree
## Делит лист с несколькими анимациями (ряды кадров, например из ChatGPT) на отдельные ленты — по ряду на анимацию.
## Ряды ищутся по пустым (светлым) полосам между ними; искры и «z» над фигурами остаются со своим рядом.
##
##   Godot.exe --headless --path . --script res://tools/split_sheet_rows.gd -- <лист> <папка> <имя ряда 1> <имя ряда 2> ...
##   пример: ... -- mage_sheet2.webp res://assets/sprites/heroes/mage/source mage_idle mage_walk
##
## Дальше каждую ленту режет tools/slice_animation_strip.gd (см. README, «Анимации персонажей»).

## Пиксель — фон, если он светлый и почти серый (как в slice_ui_sheet.gd).
const BACKGROUND_MIN_BRIGHTNESS := 0.82
const BACKGROUND_MAX_SATURATION := 0.12
## Полосы с содержимым, разделённые пустотой меньше этой высоты, — один ряд (искры над головой и т.п.).
const MIN_ROW_GAP := 40
## Поля вокруг ряда в сохранённой ленте.
const PADDING := 12


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- <sheet> <out_dir> <row_name1> [row_name2 ...]")
		quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
	if image == null:
		push_error("Cannot load " + args[0])
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	var names := args.slice(2)
	var rows := _find_rows(image)
	if rows.size() != names.size():
		push_error("Found %d rows, expected %d: %s" % [rows.size(), names.size(), str(rows)])
		quit(1)
		return
	var out_dir: String = args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for i in rows.size():
		var top := maxi(0, rows[i].x - PADDING)
		var bottom := mini(image.get_height(), rows[i].y + PADDING)
		var strip := image.get_region(Rect2i(0, top, image.get_width(), bottom - top))
		var path := out_dir.path_join(names[i] + ".png")
		strip.save_png(ProjectSettings.globalize_path(path))
		print("  %s: rows %d..%d" % [path, top, bottom])
	quit()


## Полосы [начало, конец) по вертикали, где есть не-фон; близкие полосы склеиваются.
func _find_rows(image: Image) -> Array[Vector2i]:
	var bands: Array[Vector2i] = []
	var start := -1
	for y in image.get_height():
		var filled := _row_has_content(image, y)
		if filled and start < 0:
			start = y
		elif not filled and start >= 0:
			bands.append(Vector2i(start, y))
			start = -1
	if start >= 0:
		bands.append(Vector2i(start, image.get_height()))
	var merged: Array[Vector2i] = []
	for band in bands:
		if not merged.is_empty() and band.x - merged[-1].y < MIN_ROW_GAP:
			merged[-1].y = band.y
		else:
			merged.append(band)
	return merged


func _row_has_content(image: Image, y: int) -> bool:
	for x in image.get_width():
		var color := image.get_pixel(x, y)
		if color.a > 0.1 and (color.v < BACKGROUND_MIN_BRIGHTNESS or color.s > BACKGROUND_MAX_SATURATION):
			return true
	return false
