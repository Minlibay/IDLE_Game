class_name UiStyles
extends RefCounted
## Общие элементы интерфейса, которые собираются в коде: рамки ячеек (из assets/ui/slots/),
## рамка выделения, иконка ресурса с подписью, заголовок раздела, стиль из картинки (9-slice).

const SLOT_DIR := "res://assets/ui/slots/"
## Рамки предметов по редкости (индекс = Item.Tier).
const TIER_FRAMES := ["tier_common", "tier_uncommon", "tier_rare", "tier_epic", "tier_legendary"]
## Рамки сокровищ по качеству (ItemBase.Quality).
const TREASURE_FRAMES := {
	ItemBase.Quality.NAMED: "treasure_named", ItemBase.Quality.UNIQUE: "treasure_unique", ItemBase.Quality.LEGENDARY: "treasure_legendary",
}
## Отступы 9-slice для растягиваемых рамок (углы и украшения не растягиваются).
const FRAME_MARGINS := {
	"tier_common": 10, "tier_uncommon": 10, "tier_rare": 10, "tier_epic": 10, "tier_legendary": 13,
	"treasure_named": 10, "treasure_unique": 10, "treasure_legendary": 10,
	"slot_empty": 9, "slot_locked": 9, "slot_skill": 14,
}
const SELECTION_FRAME := "slot_selected"
const SELECTION_MARGIN := 10
## Рамка выделения чуть выходит за ячейку.
const SELECTION_OUTSET := 3
const HOVER_MODULATE := Color(1.25, 1.22, 1.35)
const ICON_PADDING := 6
const DIVIDER := preload("res://assets/ui/inventory/divider.png")
const COLOR_SECTION_TITLE := Color(0.88, 0.86, 0.96)

static var _style_cache: Dictionary = {}


static func tier_frame(tier: int) -> String:
	return TIER_FRAMES[clampi(tier, 0, TIER_FRAMES.size() - 1)]


## Рамка предмета: у сокровища — по качеству, у обычного — по тиру.
static func item_frame(item: Item) -> String:
	if item.is_treasure():
		return TREASURE_FRAMES.get(item.get_base().quality, "tier_epic")
	return tier_frame(item.tier)


## frame — имя рамки из assets/ui/slots/ или полный путь res://… к картинке.
static func frame_texture(frame: String) -> Texture2D:
	return load(frame if frame.begins_with("res://") else SLOT_DIR + frame + ".png")


## Растягиваемая рамка ячейки (9-slice). selected — поверх рисуется рамка выделения.
static func apply_slot_frame(button: Button, frame: String, selected: bool) -> void:
	_apply_styles(button, frame, FRAME_MARGINS.get(frame, 10), ICON_PADDING)
	set_selected(button, selected)


## Нерастягиваемая рамка (ромбы талантов): кнопка получает размер текстуры.
static func apply_fixed_frame(button: Button, frame: String, selected: bool, icon_padding: int) -> void:
	_apply_styles(button, frame, 0, icon_padding)
	button.custom_minimum_size = frame_texture(frame).get_size()
	set_selected(button, selected)


static func set_selected(button: Button, selected: bool) -> void:
	var overlay := button.get_node_or_null("SelectionFrame") as NinePatchRect
	if overlay == null:
		if not selected:
			return
		overlay = NinePatchRect.new()
		overlay.name = "SelectionFrame"
		overlay.texture = frame_texture(SELECTION_FRAME)
		# Только свечение по краям — предмет внутри остаётся виден.
		overlay.draw_center = false
		overlay.patch_margin_left = SELECTION_MARGIN
		overlay.patch_margin_top = SELECTION_MARGIN
		overlay.patch_margin_right = SELECTION_MARGIN
		overlay.patch_margin_bottom = SELECTION_MARGIN
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = -SELECTION_OUTSET
		overlay.offset_top = -SELECTION_OUTSET
		overlay.offset_right = SELECTION_OUTSET
		overlay.offset_bottom = SELECTION_OUTSET
		button.add_child(overlay)
	overlay.visible = selected


## Растягиваемый стиль из картинки: margin — неизменяемые края (углы), padding — отступ содержимого
## (Vector4: слева, сверху, справа, снизу). Кэшируется по пути и параметрам.
static func texture_style(path: String, margin: int, padding := Vector4(6, 4, 6, 4), modulate := Color.WHITE) -> StyleBoxTexture:
	var key := "tex|%s|%d|%s|%s" % [path, margin, str(padding), modulate.to_html()]
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	style.set_texture_margin_all(margin)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	style.modulate_color = modulate
	_style_cache[key] = style
	return style


## Оформляет кнопку картинками состояний (hover — подсвеченная normal, если своей нет).
static func style_button(button: Button, normal: String, pressed: String, margin: int, padding := Vector4(8, 3, 8, 3)) -> void:
	var base := texture_style(normal, margin, padding)
	var hover := texture_style(normal, margin, padding, HOVER_MODULATE)
	var down := texture_style(pressed, margin, padding)
	for state: String in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state, base)
	button.add_theme_stylebox_override("hover", hover)
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, down)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Заголовок раздела: «✦ Название ———» с декоративной линией.
static func make_section_title(text: String, font_size := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "✦ " + text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_SECTION_TITLE)
	row.add_child(label)
	var line := NinePatchRect.new()
	line.texture = DIVIDER
	line.patch_margin_left = 12
	line.patch_margin_right = 12
	line.custom_minimum_size = Vector2(24, DIVIDER.get_height())
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row


## Плашка «иконка + значение» (стоимость, характеристика) из assets/ui/kingdom/chip.png. Возвращает Label.
static func add_chip(parent: Container, texture: Texture2D, font_size := 13) -> Label:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", texture_style("res://assets/ui/kingdom/chip.png", 6, Vector4(6, 3, 10, 3)))
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(make_icon(texture, 22))
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	row.add_child(label)
	chip.add_child(row)
	parent.add_child(chip)
	return label


## Маленькая иконка (TextureRect) заданного размера.
static func make_icon(texture: Texture2D, icon_size := 16) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## Иконка ресурса + подпись (для стоимости и полосы ресурсов). Возвращает Label для текста.
static func add_resource_item(parent: Container, resource_id: String, font_size := 12) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.tooltip_text = KingdomState.resource_name(resource_id)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := TextureRect.new()
	icon.texture = KingdomState.resource_icon(resource_id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	box.add_child(label)
	parent.add_child(box)
	return label


static func _apply_styles(button: Button, frame: String, margin: int, icon_padding: int) -> void:
	var normal := _frame_style(frame, margin, icon_padding, Color.WHITE)
	var hover := _frame_style(frame, margin, icon_padding, HOVER_MODULATE)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("hover_pressed", hover)


## Стили кэшируются: ячеек много, а вариантов рамок — единицы.
static func _frame_style(frame: String, margin: int, icon_padding: int, modulate: Color) -> StyleBoxTexture:
	var key := "%s|%d|%d|%s" % [frame, margin, icon_padding, modulate.to_html()]
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = frame_texture(frame)
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(icon_padding)
	style.modulate_color = modulate
	_style_cache[key] = style
	return style
