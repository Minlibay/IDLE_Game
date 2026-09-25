class_name TalentGrid
extends Control
## Окно сетки талантов (как «Карта»: раскрывается на большую часть экрана).
## Слева — полотно TalentGridView, справа — выбранный узел, изучение, сброс, легенда секторов.

const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_POINTS := Color(1.0, 0.85, 0.35)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const KIND_NAMES := {
	TalentData.Kind.MINOR: "Малый узел",
	TalentData.Kind.NOTABLE: "Значимый узел",
	TalentData.Kind.KEYSTONE: "Ключевой талант",
	TalentData.Kind.START: "Начало пути",
}

var _tree: TalentTree
var _selected: TalentData
## Сброс требует двойного нажатия, чтобы не потратить золото случайно.
var _reset_armed := false

@onready var grid_view: TalentGridView = %GridView
@onready var points_label: Label = %PointsLabel
@onready var reset_button: Button = %ResetButton
@onready var center_button: Button = %CenterButton
@onready var close_button: Button = %CloseButton
@onready var name_label: Label = %TalentNameLabel
@onready var kind_label: Label = %TalentKindLabel
@onready var info_label: Label = %TalentInfoLabel
@onready var requirement_label: Label = %RequirementLabel
@onready var learn_button: Button = %LearnButton
@onready var result_label: Label = %ResultLabel
@onready var legend_label: Label = %LegendLabel


func _ready() -> void:
	close_button.pressed.connect(close)
	center_button.pressed.connect(func() -> void: grid_view.center_on_start())
	learn_button.pressed.connect(func() -> void: _learn(_selected))
	reset_button.pressed.connect(_on_reset_pressed)
	grid_view.talent_selected.connect(_on_talent_selected)
	grid_view.talent_learn_requested.connect(_learn)
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
	_tree = GameState.get_talent_tree()
	grid_view.set_tree(_tree)
	show()
	DesktopWindow.enter_map_mode()
	_reset_armed = false
	result_label.text = ""
	if _selected == null and _tree:
		_selected = _tree.get_start()
		grid_view.selected = _selected
	_refresh()
	# Окно раскрывается асинхронно — вписываем сетку, когда размер уже новый.
	grid_view.request_fit()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.exit_map_mode()


func _on_talent_selected(talent: TalentData) -> void:
	_selected = talent
	result_label.text = ""
	_refresh()


func _learn(talent: TalentData) -> void:
	if talent == null:
		return
	if GameState.learn_talent(talent):
		_show_result("Изучено: %s" % talent.display_name, COLOR_OK)
	elif GameState.get_talent_rank(talent) >= talent.max_rank:
		_show_result("Уже изучено", COLOR_HINT)
	elif not GameState.is_talent_reachable(talent):
		_show_result("Сначала изучите соседний узел", COLOR_BAD)
	else:
		_show_result("Нет свободных очков", COLOR_BAD)


func _refresh() -> void:
	if not visible or _tree == null:
		return
	var available := GameState.get_available_talent_points()
	points_label.text = "Свободных очков: %d · изучено %d из %d" % [
		available, GameState.get_talent_points_spent(), _tree.get_talents().size() - 1]
	points_label.modulate = COLOR_POINTS if available > 0 else COLOR_HINT
	reset_button.disabled = GameState.get_talent_points_spent() == 0
	reset_button.text = ("Точно? %d з" if _reset_armed else "Сброс (%d з)") % GameState.get_talent_reset_cost()
	_update_legend()
	_update_details()
	grid_view.queue_redraw()


func _update_details() -> void:
	if _selected == null:
		return
	var rank := GameState.get_talent_rank(_selected)
	name_label.text = _selected.display_name
	var region_name := _tree.regions[_selected.region].display_name if _selected.kind != TalentData.Kind.START else ""
	kind_label.text = KIND_NAMES[_selected.kind] + (" · сектор «%s»" % region_name if region_name != "" else "")
	info_label.text = _selected.get_description(1)
	requirement_label.text = ""
	if rank == 0 and not GameState.is_talent_reachable(_selected):
		requirement_label.text = "Недоступно: изучайте узлы по цепочке от центра"
	elif rank == 0 and GameState.get_available_talent_points() == 0:
		requirement_label.text = "Нет свободных очков — они даются за уровень"
	learn_button.disabled = not GameState.can_learn_talent(_selected)
	learn_button.text = "Изучено" if rank > 0 else "Изучить (или двойной клик)"


## Легенда: сколько узлов изучено в каждом секторе.
func _update_legend() -> void:
	var learned := PackedInt32Array()
	var total := PackedInt32Array()
	learned.resize(_tree.regions.size())
	total.resize(_tree.regions.size())
	for talent in _tree.get_talents():
		if talent.kind == TalentData.Kind.START:
			continue
		total[talent.region] += 1
		if GameState.get_talent_rank(talent) > 0:
			learned[talent.region] += 1
	var lines := PackedStringArray()
	for i in _tree.regions.size():
		lines.append("■ %s: %d / %d" % [_tree.regions[i].display_name, learned[i], total[i]])
	legend_label.text = "\n".join(lines)


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
