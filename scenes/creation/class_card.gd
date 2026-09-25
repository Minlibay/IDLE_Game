class_name ClassCard
extends Button
## Карточка класса на экране создания героя.

signal chosen(class_data: CharacterClass)

var class_data: CharacterClass

@onready var portrait: TextureRect = %Portrait
@onready var name_label: Label = %NameLabel
@onready var description_label: Label = %DescriptionLabel
@onready var stats_label: Label = %StatsLabel


func _ready() -> void:
	toggled.connect(_on_toggled)


func setup(p_class: CharacterClass) -> void:
	class_data = p_class
	portrait.texture = p_class.sprite
	name_label.text = p_class.display_name
	var skill_names := PackedStringArray()
	for skill in p_class.skills:
		if skill:
			skill_names.append(skill.display_name)
	description_label.text = p_class.description
	if not skill_names.is_empty():
		description_label.text += "\nУмения: " + ", ".join(skill_names)
	stats_label.text = "HP %d · Урон %d · %s" % [
		roundi(p_class.base_max_hp), roundi(p_class.base_damage),
		"Дальний бой" if p_class.is_ranged() else "Ближний бой"]


func _on_toggled(pressed: bool) -> void:
	if pressed:
		chosen.emit(class_data)
