class_name PanelUi
extends RefCounted
## Общие кусочки интерфейса окон (гильдия, путь героя): разделы, ячейки таблиц, кнопки, текст армии.

const COLOR_OK := Color(0.55, 0.9, 0.5)
const COLOR_BAD := Color(1.0, 0.5, 0.45)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const COLOR_GOLD := Color(1.0, 0.85, 0.35)


## Раздел окна: рамка + заголовок; возвращает контейнер для содержимого.
static func section(parent: Container, title: String, min_width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelSection"
	panel.custom_minimum_size = Vector2(min_width, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if min_width <= 0.0 else Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiStyles.make_section_title(title))
	panel.add_child(box)
	parent.add_child(panel)
	return box


static func button(text: String, variation: StringName = &"") -> Button:
	var result := Button.new()
	result.text = text
	result.theme_type_variation = variation
	result.custom_minimum_size = Vector2(0, 26)
	return result


## Ячейка таблицы: подпись уже переведена (или это имя игрока) — автоперевод выключен.
static func cell(text: String, width: float, color := Color.WHITE, expand := false, font_size := 12) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


static func hint(text: String, font_size := 11) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_HINT)
	return label


static func scroll_list(parent: Container) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	parent.add_child(scroll)
	return list


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## «5 Копейщик, 2 Рыцарь» (имена отрядов уже переведены Database).
static func army_text(army: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit_id: String in army:
		var unit := Database.get_unit(unit_id)
		parts.append("%d %s" % [int(army[unit_id]), unit.display_name if unit else unit_id])
	return ", ".join(parts) if not parts.is_empty() else TranslationServer.translate("нет")
