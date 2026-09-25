class_name SkillButton
extends Button
## Кнопка умения: иконка, затемнение перезарядки, горячая клавиша, замок до нужного уровня.

var skill: SkillData
var caster: SkillCaster

@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var cooldown_label: Label = $CooldownLabel
@onready var key_label: Label = $KeyLabel


func setup(p_skill: SkillData, p_caster: SkillCaster, hotkey: String) -> void:
	skill = p_skill
	caster = p_caster
	icon = skill.icon
	key_label.text = hotkey
	tooltip_text = "%s [%s]\n%s\nПерезарядка: %d с · открывается на ур. %d" % [
		skill.display_name, hotkey, skill.description, roundi(skill.cooldown), skill.unlock_level]
	pressed.connect(func() -> void: caster.try_cast(skill))


func _process(_delta: float) -> void:
	if skill == null:
		return
	if not caster.is_unlocked(skill):
		disabled = true
		cooldown_overlay.anchor_top = 0.0
		cooldown_label.text = "ур.%d" % skill.unlock_level
		return
	disabled = false
	var left := caster.get_cooldown_left(skill)
	cooldown_overlay.anchor_top = 1.0 - caster.get_cooldown_ratio(skill)
	cooldown_label.text = str(ceili(left)) if left > 0.0 else ""
