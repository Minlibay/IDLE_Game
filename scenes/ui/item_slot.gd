class_name ItemSlot
extends Button
## Ячейка предмета: иконка, рамка редкости (assets/ui/slots/), уровень заточки.
## Пустая ячейка показывает empty_frame (например, рамку с призрачной иконкой слота).

signal item_pressed(item: Item)

var item: Item
## Рамка пустой ячейки: имя из assets/ui/slots/ или путь res://…
var empty_frame := "slot_empty"
## Подсказка для пустой ячейки.
var empty_tooltip := ""
var _selected := false

@onready var upgrade_label: Label = $UpgradeLabel


func _ready() -> void:
	pressed.connect(_on_pressed)
	_apply_style()


func set_item(p_item: Item) -> void:
	item = p_item
	icon = item.get_base().icon if item else null
	# Сокровище без своей картинки — иконка слота в цвете сета/качества.
	var tint := item.get_base().icon_tint if item else Color.WHITE
	for color_name: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]:
		add_theme_color_override(color_name, tint)
	upgrade_label.text = "+%d" % item.upgrade_level if item and item.upgrade_level > 0 else ""
	tooltip_text = "%s\n%s" % [item.get_display_name(), item.get_tier_name()] if item else empty_tooltip
	_apply_style()


func set_selected(value: bool) -> void:
	_selected = value
	_apply_style()


func _on_pressed() -> void:
	if item:
		item_pressed.emit(item)


func _apply_style() -> void:
	UiStyles.apply_slot_frame(self, UiStyles.item_frame(item) if item else empty_frame, _selected)
