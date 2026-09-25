extends SceneTree
## Делает из полосы земли (нарезанной tools/slice_ui_sheet.gd) бесшовный тайл для боя:
## обрезает закруглённые концы полосы и сглаживает стык — правый край плавно переходит в левый.
##
##   Godot.exe --headless --path . --script res://tools/make_ground_tile.gd -- <полоса.png> <тайл.png> [обрезка_концов=0.06] [сглаживание_px=24]
##
## Результат: ширина = ширина полосы без концов минус сглаживание; повторяется без шва.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- <strip.png> <tile.png> [trim=0.06] [blend_px=24]")
		quit(1)
		return
	var strip := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
	strip.convert(Image.FORMAT_RGBA8)
	var trim := int(strip.get_width() * (float(args[2]) if args.size() > 2 else 0.06))
	var blend := int(args[3]) if args.size() > 3 else 24
	var source := strip.get_region(Rect2i(trim, 0, strip.get_width() - trim * 2, strip.get_height()))
	var width := source.get_width() - blend
	var height := source.get_height()
	var tile := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var color := source.get_pixel(x, y)
			if x < blend:
				# Левый край тайла — смесь начала полосы и её «лишнего» хвоста справа: так стык незаметен.
				var tail := source.get_pixel(width + x, y)
				var t := float(x) / float(blend)
				color = _mix(tail, color, t)
			tile.set_pixel(x, y, color)
	tile.save_png(ProjectSettings.globalize_path(args[1]))
	print("Ground tile %dx%d -> %s" % [width, height, args[1]])
	quit()


## Смесь с учётом прозрачности (травинки на фоне не превращаются в серое пятно).
func _mix(a: Color, b: Color, t: float) -> Color:
	var alpha := lerpf(a.a, b.a, t)
	if alpha <= 0.001:
		return Color(0, 0, 0, 0)
	var rgb := (Color(a.r, a.g, a.b) * a.a * (1.0 - t) + Color(b.r, b.g, b.b) * b.a * t) / alpha
	# Пиксель-арт: почти прозрачное — прозрачно, почти непрозрачное — непрозрачно.
	return Color(rgb.r, rgb.g, rgb.b, 0.0 if alpha < 0.35 else (1.0 if alpha > 0.65 else alpha))
