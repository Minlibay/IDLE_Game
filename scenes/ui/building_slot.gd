class_name BuildingSlot
extends Button
## Ячейка здания: иконка, уровень, полоска стройки.
## Рамки: пустая — не построено, фиолетовая — построено, зелёная — можно улучшить, золотая — строится.

signal building_pressed(building: BuildingData)

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
	var frame := "slot_skill" if level > 0 else "slot_empty"
	if construction_ratio >= 0.0:
		frame = "tier_legendary"
	elif can_upgrade:
		frame = "tier_uncommon"
	UiStyles.apply_slot_frame(self, frame, selected)
	self_modulate = Color.WHITE if level > 0 or construction_ratio >= 0.0 else Color(0.55, 0.55, 0.6)
