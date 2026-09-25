extends SceneTree
## Перекрашивает фиолетовые части картинки интерфейса в другой оттенок (золото и тёмные тона не трогает).
## Так из одной кнопки получаются зелёная, красная, синяя — в том же стиле.
##
##   Godot.exe --headless --path . --script res://tools/recolor_ui.gd -- <исходник> <результат> <оттенок 0..1> [насыщенность×] [яркость×]
##
## Оттенки: красный 0.0, зелёный 0.33, синий 0.6, фиолетовый (исходный) ~0.75.

## Какие пиксели считаются фиолетовыми (оттенок в этом диапазоне и заметная насыщенность).
const VIOLET_HUE_MIN := 0.62
const VIOLET_HUE_MAX := 0.9
const MIN_SATURATION := 0.12


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- <src> <dst> <hue> [saturation_mult] [value_mult]")
		quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
	image.convert(Image.FORMAT_RGBA8)
	var hue := float(args[2])
	var saturation_mult := float(args[3]) if args.size() > 3 else 1.0
	var value_mult := float(args[4]) if args.size() > 4 else 1.0
	var changed := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.0 or color.s < MIN_SATURATION or color.h < VIOLET_HUE_MIN or color.h > VIOLET_HUE_MAX:
				continue
			image.set_pixel(x, y, Color.from_hsv(hue, clampf(color.s * saturation_mult, 0.0, 1.0),
				clampf(color.v * value_mult, 0.0, 1.0), color.a))
			changed += 1
	image.save_png(ProjectSettings.globalize_path(args[1]))
	print("Recolored %d pixels -> %s" % [changed, args[1]])
	quit()
