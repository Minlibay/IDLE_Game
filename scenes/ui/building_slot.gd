class_name BuildingSlot
extends Button
## Ячейка здания: иконка, уровень, полоска стройки. Зелёная рамка — можно улучшить.

signal building_pressed(building: BuildingData)

const COLOR_NOT_BUILT := Color(0.3, 0.3, 0.36)
const COLOR_BUILT := Color(0.55, 0.6, 0.75)
const COLOR_CAN_UPGRADE := Color(0.45, 0.9, 0.45)
const COLOR_CONSTRUCTING := Color(1.0, 0.75, 0.25)

var building: BuildingData

@onready var level_label: Label = $LevelLabel
@onready var build_bar: ProgressBar = $BuildBar


func _ready() -> void:
	pressed.connect(func() -> void: building_pressed.emit(building))


func setup(p_building: BuildingData) -> void:
	building = p_building
	icon = building.icon
	tooltip_text = building.display_name


## construction_ratio < 0 — здание сейчас не строится.
func update_state(level: int, can_upgrade: bool, construction_ratio: float, selected: bool) -> void:
	level_label.text = str(level) if level > 0 else ""
	build_bar.visible = construction_ratio >= 0.0
	build_bar.value = maxf(construction_ratio, 0.0)
	var border := COLOR_BUILT if level > 0 else COLOR_NOT_BUILT
	if construction_ratio >= 0.0:
		border = COLOR_CONSTRUCTING
	elif can_upgrade:
		border = COLOR_CAN_UPGRADE
	UiStyles.apply_slot_style(self, border, selected)
	self_modulate = Color.WHITE if level > 0 or construction_ratio >= 0.0 else Color(0.55, 0.55, 0.6)
