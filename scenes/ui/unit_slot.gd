class_name UnitSlot
extends Button
## Ячейка отряда: иконка, число солдат. Закрытый отряд — рамка с замком (без иконки).

signal unit_pressed(unit: UnitData)

var unit: UnitData

@onready var count_label: Label = $CountLabel


func _ready() -> void:
	pressed.connect(func() -> void: unit_pressed.emit(unit))


func setup(p_unit: UnitData) -> void:
	unit = p_unit
	icon = unit.icon
	tooltip_text = unit.display_name


func update_state(count: int, unlocked: bool, can_recruit: bool, selected: bool) -> void:
	count_label.text = str(count) if count > 0 else ""
	var frame := "slot_locked"
	if can_recruit:
		frame = "tier_uncommon"
	elif unlocked:
		frame = "slot_skill"
	icon = unit.icon if unlocked else null
	UiStyles.apply_slot_frame(self, frame, selected)
