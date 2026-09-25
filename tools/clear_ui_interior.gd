extends SceneTree
## Очищает внутренность рамки от нарисованной иконки: закрашивает прямоугольник внутри рамки
## цветом фона (берётся из точки sample). Так из «плашки с хлебом» получается пустая плашка.
##
##   Godot.exe --headless --path . --script res://tools/clear_ui_interior.gd -- <исходник> <результат> <отступ> <sample_x> <sample_y> [x_от] [x_до] [y_от] [y_до]
##
## <отступ> — толщина рамки, которую не трогаем; [x_от, x_до) и [y_от, y_до) — ограничить закраску
## (например, стереть только значок в углу).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("Usage: -- <src> <dst> <inset> <sample_x> <sample_y> [x_from] [x_to] [y_from] [y_to]")
		quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
	image.convert(Image.FORMAT_RGBA8)
	var inset := int(args[2])
	var fill := image.get_pixel(int(args[3]), int(args[4]))
	var x_from := int(args[5]) if args.size() > 5 else inset
	var x_to := int(args[6]) if args.size() > 6 else image.get_width() - inset
	var y_from := int(args[7]) if args.size() > 7 else inset
	var y_to := int(args[8]) if args.size() > 8 else image.get_height() - inset
	image.fill_rect(Rect2i(x_from, y_from, x_to - x_from, y_to - y_from), fill)
	image.save_png(ProjectSettings.globalize_path(args[1]))
	print("Cleared %s -> %s" % [args[0], args[1]])
	quit()
