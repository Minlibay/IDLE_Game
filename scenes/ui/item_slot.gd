class_name ItemSlot
extends Button
## Ячейка предмета: иконка, рамка цвета тира, уровень заточки.

signal item_pressed(item: Item)

const EMPTY_BORDER := Color(0.3, 0.3, 0.36)

var item: Item
var _selected := false

@onready var upgrade_label: Label = $UpgradeLabel


func _ready() -> void:
	pressed.connect(_on_pressed)
	_apply_style()


func set_item(p_item: Item) -> void:
	item = p_item
	icon = item.get_base().icon if item else null
	upgrade_label.text = "+%d" % item.upgrade_level if item and item.upgrade_level > 0 else ""
	tooltip_text = "%s\n%s" % [item.get_display_name(), item.get_tier_name()] if item else ""
	_apply_style()


func set_selected(value: bool) -> void:
	_selected = value
	_apply_style()


func _on_pressed() -> void:
	if item:
		item_pressed.emit(item)


func _apply_style() -> void:
	UiStyles.apply_slot_style(self, item.get_tier_color() if item else EMPTY_BORDER, _selected)
