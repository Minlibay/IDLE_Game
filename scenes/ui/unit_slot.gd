class_name UnitSlot
extends Button
## Карточка отряда: портрет, название, число солдат в значке.
## Рамки (assets/ui/kingdom/): фиолетовая — открыт, зелёная (tier_uncommon) — можно нанять,
## серая с замком — нужно здание (вместо названия — требование).

signal unit_pressed(unit: UnitData)

const FRAME_DIR := "res://assets/ui/kingdom/"
const FRAME_MARGIN := 12
const PADDING := Vector4(6, 8, 6, 4)

var unit: UnitData

@onready var count_badge: PanelContainer = $CountBadge
@onready var count_label: Label = $CountBadge/CountLabel
@onready var lock_icon: TextureRect = $Lock


func _ready() -> void:
	pressed.connect(func() -> void: unit_pressed.emit(unit))
	count_badge.add_theme_stylebox_override("panel", UiStyles.texture_style(FRAME_DIR + "count_badge.png", 6, Vector4(4, 1, 4, 1)))


func setup(p_unit: UnitData) -> void:
	unit = p_unit
	icon = unit.icon
	text = unit.display_name
	tooltip_text = unit.display_name


## locked_text — что нужно, чтобы открыть отряд (показывается вместо названия).
func update_state(count: int, unlocked: bool, can_recruit: bool, selected: bool, locked_text := "") -> void:
	count_label.text = "×%d" % count
	count_badge.visible = count > 0
	lock_icon.visible = not unlocked
	text = unit.display_name if unlocked else locked_text
	var frame := FRAME_DIR + ("unit_card.png" if unlocked else "unit_locked.png")
	if unlocked and can_recruit:
		frame = UiStyles.SLOT_DIR + "tier_uncommon.png"
	UiStyles.style_button(self, frame, frame, FRAME_MARGIN if unlocked and not can_recruit else 9, PADDING)
	UiStyles.set_selected(self, selected)
	add_theme_color_override("icon_normal_color", Color.WHITE if unlocked else Color(0.35, 0.35, 0.42))
	add_theme_color_override("font_color", Color(0.92, 0.9, 1.0) if unlocked else Color(0.6, 0.6, 0.68))
