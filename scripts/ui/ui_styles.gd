class_name UiStyles
extends RefCounted
## Общие стили интерфейса, которые собираются в коде (ячейки предметов, талантов).

const SLOT_BG := Color(0.1, 0.1, 0.14, 0.95)
const SLOT_BG_SELECTED := Color(0.25, 0.22, 0.36, 0.95)


static func make_slot_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	return style


## Рамка ячейки: normal/hover/pressed. selected — толще и светлее.
static func apply_slot_style(button: Button, border: Color, selected: bool) -> void:
	var width := 3 if selected else 2
	var normal := make_slot_style(SLOT_BG_SELECTED if selected else SLOT_BG, border, width)
	var hover := make_slot_style(SLOT_BG_SELECTED, border.lightened(0.2), width)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("hover_pressed", hover)
	button.add_theme_stylebox_override("disabled", normal)
