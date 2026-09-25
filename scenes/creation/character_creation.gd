class_name CharacterCreation
extends Control
## Экран создания героя: имя + выбор класса. Карточки строятся из data/classes/.

signal character_created

const CLASS_CARD_SCENE := preload("res://scenes/creation/class_card.tscn")

var _selected_class: CharacterClass

@onready var name_edit: LineEdit = %NameEdit
@onready var class_list: HBoxContainer = %ClassList
@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	DesktopWindow.set_full_mode()
	var group := ButtonGroup.new()
	for class_data in Database.classes:
		var card: ClassCard = CLASS_CARD_SCENE.instantiate()
		class_list.add_child(card)
		card.setup(class_data)
		card.button_group = group
		card.chosen.connect(_on_class_chosen)
	name_edit.text_changed.connect(func(_text: String) -> void: _update_start_button())
	name_edit.text_submitted.connect(func(_text: String) -> void: _on_start_pressed())
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(get_tree().quit)
	_update_start_button()
	name_edit.grab_focus()


func _on_class_chosen(class_data: CharacterClass) -> void:
	_selected_class = class_data
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = _selected_class == null or name_edit.text.strip_edges().is_empty()


func _on_start_pressed() -> void:
	if start_button.disabled:
		return
	GameState.create_character(name_edit.text.strip_edges(), _selected_class.id)
	character_created.emit()
