class_name TalentButton
extends Button
## Ячейка таланта: иконка, ранг «2/5», рамка по состоянию (закрыт / доступен / изучен / максимум).

signal talent_pressed(talent: TalentData)

const COLOR_LOCKED := Color(0.25, 0.25, 0.3)
const COLOR_AVAILABLE := Color(0.85, 0.85, 0.9)
const COLOR_LEARNED := Color(0.4, 0.85, 0.4)
const COLOR_MAXED := Color(1.0, 0.75, 0.25)

var talent: TalentData

@onready var rank_label: Label = $RankLabel


func _ready() -> void:
	pressed.connect(func() -> void: talent_pressed.emit(talent))


func setup(p_talent: TalentData) -> void:
	talent = p_talent
	icon = talent.get_icon()
	tooltip_text = talent.display_name


func update_state(rank: int, unlocked: bool, can_learn: bool, selected: bool) -> void:
	rank_label.text = "%d/%d" % [rank, talent.max_rank]
	var border := COLOR_LOCKED
	if rank >= talent.max_rank:
		border = COLOR_MAXED
	elif rank > 0:
		border = COLOR_LEARNED
	elif can_learn:
		border = COLOR_AVAILABLE
	UiStyles.apply_slot_style(self, border, selected)
	# Закрытые ряды — затемнены; изученные таланты — в полном цвете.
	self_modulate = Color.WHITE if unlocked or rank > 0 else Color(0.45, 0.45, 0.5)
	rank_label.modulate = border
