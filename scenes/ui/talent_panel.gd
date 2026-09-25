class_name TalentPanel
extends PanelContainer
## Дерево талантов: ветки (колонки) × ряды, детали выбранного таланта, изучение и сброс.
## Дерево берётся из класса героя (CharacterClass.talent_tree).

const TALENT_BUTTON_SCENE := preload("res://scenes/ui/talent_button.tscn")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const COLOR_POINTS := Color(1.0, 0.85, 0.35)

var _tree: TalentTree
var _selected: TalentData
var _buttons: Array[TalentButton] = []
var _branch_labels: Array[Label] = []
## Сброс требует двойного нажатия, чтобы не потратить золото случайно.
var _reset_armed := false

@onready var points_label: Label = %PointsLabel
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton
@onready var branches_box: HBoxContainer = %BranchesBox
@onready var name_label: Label = %TalentNameLabel
@onready var rank_label: Label = %TalentRankLabel
@onready var info_label: Label = %TalentInfoLabel
@onready var requirement_label: Label = %RequirementLabel
@onready var learn_button: Button = %LearnButton
@onready var result_label: Label = %TalentResultLabel


func _ready() -> void:
	close_button.pressed.connect(close)
	learn_button.pressed.connect(_on_learn_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	GameState.talents_changed.connect(_refresh)
	GameState.leveled_up.connect(func(_level: int) -> void: _refresh())
	GameState.currency_changed.connect(_refresh)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	if _tree == null:
		_build()
	show()
	DesktopWindow.push_modal()
	_reset_armed = false
	result_label.text = ""
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()


func _build() -> void:
	_tree = GameState.get_talent_tree()
	if _tree == null:
		return
	for branch in _tree.branch_names.size():
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 118
		column.add_theme_constant_override("separation", 4)
		var header := Label.new()
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(header)
		_branch_labels.append(header)
		var row_box: HBoxContainer = null
		var current_row := -1
		for talent in _tree.get_talents_in_branch(branch):
			if talent.row != current_row:
				current_row = talent.row
				row_box = HBoxContainer.new()
				row_box.alignment = BoxContainer.ALIGNMENT_CENTER
				column.add_child(row_box)
			var button: TalentButton = TALENT_BUTTON_SCENE.instantiate()
			row_box.add_child(button)
			button.setup(talent)
			button.talent_pressed.connect(_select)
			_buttons.append(button)
		branches_box.add_child(column)
	if not _tree.talents.is_empty():
		_selected = _tree.talents[0]


func _select(talent: TalentData) -> void:
	_selected = talent
	result_label.text = ""
	_refresh()


func _refresh() -> void:
	if not visible or _tree == null:
		return
	var available := GameState.get_available_talent_points()
	points_label.text = "Свободных очков: %d" % available
	points_label.modulate = COLOR_POINTS if available > 0 else COLOR_HINT
	for branch in _branch_labels.size():
		_branch_labels[branch].text = "%s (%d)" % [_tree.branch_names[branch], GameState.get_branch_points(branch)]
	for button in _buttons:
		var talent := button.talent
		button.update_state(GameState.get_talent_rank(talent), GameState.is_talent_row_unlocked(talent),
			GameState.can_learn_talent(talent), talent == _selected)
	var spent := GameState.get_talent_points_spent()
	var cost := GameState.get_talent_reset_cost()
	reset_button.disabled = spent == 0
	reset_button.text = ("Точно? %d з" if _reset_armed else "Сброс (%d з)") % cost
	_update_details()


func _update_details() -> void:
	if _selected == null:
		name_label.text = "Выберите талант"
		rank_label.text = ""
		info_label.text = ""
		requirement_label.text = ""
		learn_button.disabled = true
		return
	var rank := GameState.get_talent_rank(_selected)
	name_label.text = _selected.display_name
	rank_label.text = "Ранг %d / %d · ветка «%s»" % [rank, _selected.max_rank, _tree.branch_names[_selected.branch]]
	var lines := PackedStringArray()
	if rank > 0:
		lines.append("Сейчас: " + _selected.get_description(rank))
	if rank < _selected.max_rank:
		lines.append(("Следующий ранг: " if rank > 0 else "") + _selected.get_description(rank + 1))
	info_label.text = "\n".join(lines)

	requirement_label.text = ""
	if not GameState.is_talent_row_unlocked(_selected):
		requirement_label.text = "Нужно %d очков в ветке «%s»" % [
			_tree.get_required_points(_selected), _tree.branch_names[_selected.branch]]
	elif rank < _selected.max_rank and GameState.get_available_talent_points() == 0:
		requirement_label.text = "Нет свободных очков — они даются за уровень"
	learn_button.disabled = not GameState.can_learn_talent(_selected)
	learn_button.text = "Максимум" if rank >= _selected.max_rank else "Изучить"


func _on_learn_pressed() -> void:
	if _selected and GameState.learn_talent(_selected):
		_show_result("Изучено: %s" % _selected.display_name, COLOR_OK)


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	if GameState.reset_talents():
		_show_result("Таланты сброшены, очки возвращены", COLOR_OK)
	else:
		_show_result("Не хватает золота на сброс", COLOR_BAD)
	_refresh()


func _show_result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.modulate = color
