extends SceneTree
## Кнопки окна «свернуть в трей» и «настройки» на основе маленькой кнопки закрытия:
## та же рамка и фон, вместо крестика — свой значок того же цвета.
##
##   Godot.exe --headless --path . --script res://tools/make_window_buttons.gd

const DIR := "res://assets/ui/buttons/"
## Рамка кнопки (пиксели от края), внутри неё — фон и значок.
const BORDER := 3
## Пиксель значка ярче фона кнопки на GLYPH_MIN_LIGHTNESS; крестик с краями и тенью отличается от фона на CROSS_EDGE_LIGHTNESS.
const GLYPH_MIN_LIGHTNESS := 0.45
const CROSS_EDGE_LIGHTNESS := 0.05

const GLYPHS := {
	"tray": [
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"########",
		"########",
	],
	"settings": [
		"..#.#..",
		".#####.",
		"##...##",
		".#...#.",
		"##...##",
		".#####.",
		"..#.#..",
	],
}


func _initialize() -> void:
	for state in ["", "_hover"]:
		var source := Image.load_from_file(ProjectSettings.globalize_path(DIR + "close_small%s.png" % state))
		source.convert(Image.FORMAT_RGBA8)
		for glyph_name: String in GLYPHS:
			var image := _without_cross(source)
			_draw_glyph(image, GLYPHS[glyph_name], _glyph_color(source))
			var path := DIR + "%s_small%s.png" % [glyph_name, state]
			image.save_png(ProjectSettings.globalize_path(path))
			print("saved ", path)
	quit()


## Стирает крестик: светлые пиксели внутри рамки закрашиваются самым частым цветом фона.
func _without_cross(source: Image) -> Image:
	var image := source.duplicate()
	var background := _background_color(source)
	for y in range(BORDER, image.get_height() - BORDER):
		for x in range(BORDER, image.get_width() - BORDER):
			if absf(image.get_pixel(x, y).get_luminance() - background.get_luminance()) >= CROSS_EDGE_LIGHTNESS:
				image.set_pixel(x, y, background)
	return image


func _background_color(source: Image) -> Color:
	var counts := {}
	for y in range(BORDER, source.get_height() - BORDER):
		for x in range(BORDER, source.get_width() - BORDER):
			var color := source.get_pixel(x, y)
			if color.get_luminance() < GLYPH_MIN_LIGHTNESS:
				counts[color] = int(counts.get(color, 0)) + 1
	var best := Color.BLACK
	var best_count := -1
	for color: Color in counts:
		if counts[color] > best_count:
			best = color
			best_count = counts[color]
	return best


## Цвет крестика — самый светлый пиксель внутри рамки.
func _glyph_color(source: Image) -> Color:
	var best := Color.WHITE
	var best_lightness := -1.0
	for y in range(BORDER, source.get_height() - BORDER):
		for x in range(BORDER, source.get_width() - BORDER):
			var color := source.get_pixel(x, y)
			if color.get_luminance() > best_lightness:
				best = color
				best_lightness = color.get_luminance()
	return best


func _draw_glyph(image: Image, rows: Array, color: Color) -> void:
	var glyph_size := Vector2i(rows[0].length(), rows.size())
	var inner := Vector2i(image.get_width(), image.get_height()) - Vector2i.ONE * BORDER * 2
	var origin := Vector2i.ONE * BORDER + (inner - glyph_size) / 2
	for y in glyph_size.y:
		for x in glyph_size.x:
			if rows[y][x] == "#":
				image.set_pixel(origin.x + x, origin.y + y, color)
