class_name ArmyView
extends HBoxContainer
## Вкладка «Армия» в окне королевства: сила и численность, содержание, очередь обучения,
## карточки отрядов и найм. Состояние — с сервера (GameState.kingdom.army), найм и отмену выполняет сервер.

const UNIT_SLOT_SCENE := preload("res://scenes/ui/unit_slot.tscn")
const UI_DIR := "res://assets/ui/kingdom/"
const ICON_DIR := "res://assets/ui/icons/"
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const MAX_AMOUNT := 9999

var _selected: UnitData
var _amount := 1
var _slots: Array[UnitSlot] = []
var _queue_labels: Array[Label] = []
var _queue_bars: Array[ProgressBar] = []
var _cost_labels: Dictionary[String, Label] = {}
var _cost_unit_id := ""
## Подписи характеристик армии: ключ -> Label.
var _army_labels: Dictionary[String, Label] = {}
var _stat_labels: Dictionary[String, Label] = {}

@onready var power_label: Label = %PowerLabel
@onready var army_stats: GridContainer = %ArmyStats
@onready var capacity_bar: ProgressBar = %CapacityBar
@onready var starving_ribbon: PanelContainer = %StarvingRibbon
@onready var queue_list: VBoxContainer = %QueueList
@onready var units_grid: GridContainer = %UnitsGrid
@onready var portrait_frame: PanelContainer = %PortraitFrame
@onready var portrait: TextureRect = %Portrait
@onready var name_label: Label = %UnitNameLabel
@onready var description_label: Label = %UnitDescriptionLabel
@onready var stat_chips: HBoxContainer = %StatChips
@onready var cost_box: HBoxContainer = %UnitCostBox
@onready var time_label: Label = %UnitTimeLabel
@onready var value_box: PanelContainer = %ValueBox
@onready var amount_label: Label = %AmountLabel
@onready var minus_button: TextureButton = %MinusButton
@onready var plus_button: TextureButton = %PlusButton
@onready var max_button: TextureButton = %MaxButton
@onready var recruit_button: Button = %RecruitButton
@onready var reason_label: Label = %RecruitReasonLabel


func _ready() -> void:
	_add_titles()
	starving_ribbon.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "warning_ribbon.png", 8, Vector4(10, 2, 14, 2)))
	portrait_frame.add_theme_stylebox_override("panel", UiStyles.texture_style(UiStyles.SLOT_DIR + "tier_epic.png", 8, Vector4(6, 6, 6, 6)))
	value_box.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "value_box.png", 6, Vector4(4, 2, 4, 2)))
	for key: String in ["attack", "soldiers", "housing", "upkeep"]:
		var icon_name: String = {"attack": "attack", "soldiers": "army", "housing": "castle", "upkeep": "food"}[key]
		army_stats.add_child(UiStyles.make_icon(load(ICON_DIR + icon_name + ".png"), 14))
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		army_stats.add_child(label)
		_army_labels[key] = label
	for key: String in ["attack", "defense", "housing", "upkeep"]:
		var icon_name: String = {"attack": "attack", "defense": "defense", "housing": "castle", "upkeep": "food"}[key]
		_stat_labels[key] = UiStyles.add_chip(stat_chips, load(ICON_DIR + icon_name + ".png"))
		_stat_labels[key].get_parent().get_parent().tooltip_text = {"attack": "Атака солдата", "defense": "Защита солдата",
			"housing": "Мест в армии", "upkeep": "Еды в минуту"}[key]
	for unit in Database.units:
		var slot: UnitSlot = UNIT_SLOT_SCENE.instantiate()
		units_grid.add_child(slot)
		slot.setup(unit)
		slot.unit_pressed.connect(_select)
		_slots.append(slot)
	if not Database.units.is_empty():
		_selected = Database.units[0]
	minus_button.pressed.connect(func() -> void: _change_amount(-_step()))
	plus_button.pressed.connect(func() -> void: _change_amount(_step()))
	max_button.pressed.connect(_on_max_pressed)
	recruit_button.pressed.connect(_on_recruit_pressed)
	GameState.kingdom.army.changed.connect(_rebuild_queue)
	_rebuild_queue()


func _add_titles() -> void:
	var titles := {
		"SummarySection/VBox": ["Армия замка", 0],
		"UnitsSection/VBox": ["Отряды", 0],
		"RecruitSection/VBox": ["Найм", 0],
	}
	for path: String in titles:
		var box := get_node(path) as VBoxContainer
		var title := UiStyles.make_section_title(titles[path][0])
		box.add_child(title)
		box.move_child(title, int(titles[path][1]))
	var queue_title := UiStyles.make_section_title("Очередь обучения", 11)
	var summary := get_node("SummarySection/VBox") as VBoxContainer
	summary.add_child(queue_title)
	summary.move_child(queue_title, queue_list.get_parent().get_index())


## Вызывается окном королевства, когда меняются ресурсы (т.е. каждый кадр, пока вкладка открыта).
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var army := GameState.kingdom.army
	power_label.text = "Сила армии: %d" % roundi(army.get_power())
	power_label.tooltip_text = "Атака ×%.2f · Защита ×%.2f\nЗдания, захваченные зоны, реликвии армии%s" % [
		army.get_attack_multiplier(), army.get_defense_multiplier(), ", голод" if army.starving else ""]
	power_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_army_labels.attack.text = "Атака %d · Защита %d" % [roundi(army.get_attack()), roundi(army.get_defense())]
	_army_labels.soldiers.text = "Солдат в замке: %d" % army.get_total_units()
	_army_labels.housing.text = "Места: %d / %d" % [army.get_housing_used(), army.get_capacity()]
	_army_labels.upkeep.text = "Содержание: %s еды/мин" % StatModifier.format_number(snappedf(army.get_upkeep_per_minute(), 0.01))
	capacity_bar.value = float(army.get_housing_used()) / maxf(1.0, float(army.get_capacity()))
	starving_ribbon.visible = army.starving
	for i in _queue_labels.size():
		if i < army.queue.size():
			var order: Dictionary = army.queue[i]
			var left := army.get_order_time_left(i)
			_queue_labels[i].text = "%s ×%d — %s" % [Database.get_unit(order.id).display_name, int(order.count), UiFormat.duration(left)]
			var total := float(order.get("perUnitMs", 0.0)) / 1000.0 * int(order.get("total", order.count))
			_queue_bars[i].value = clampf(1.0 - left / maxf(0.01, total), 0.0, 1.0)
	for slot in _slots:
		var building := army.get_required_building(slot.unit)
		var locked_text := "%s %d" % [building.display_name, slot.unit.required_level] if building else ""
		slot.update_state(army.get_count(slot.unit), army.is_unlocked(slot.unit),
			army.get_recruit_block_reason(slot.unit, 1) == "", slot.unit == _selected, locked_text)
	_update_details()


func _select(unit: UnitData) -> void:
	_selected = unit
	_amount = 1
	refresh()


func _update_details() -> void:
	if _selected == null:
		return
	var army := GameState.kingdom.army
	var kingdom := GameState.kingdom
	portrait.texture = _selected.icon
	name_label.text = "%s (в замке: %d)" % [_selected.display_name, army.get_count(_selected)]
	description_label.text = _selected.description
	_stat_labels.attack.text = StatModifier.format_number(_selected.attack)
	_stat_labels.defense.text = StatModifier.format_number(_selected.defense)
	_stat_labels.housing.text = str(_selected.housing)
	_stat_labels.upkeep.text = StatModifier.format_number(_selected.upkeep_per_minute)

	var total_cost := KingdomState.multiply_cost(_selected.cost, _amount)
	if _cost_unit_id != _selected.id:
		_cost_unit_id = _selected.id
		for child in cost_box.get_children():
			cost_box.remove_child(child)
			child.queue_free()
		_cost_labels.clear()
		for resource_id: String in _selected.cost:
			_cost_labels[resource_id] = UiStyles.add_chip(cost_box, KingdomState.resource_icon(resource_id))
	for resource_id: String in _cost_labels:
		var need := float(total_cost[resource_id])
		_cost_labels[resource_id].text = str(ceili(need))
		_cost_labels[resource_id].modulate = COLOR_OK if kingdom.get_resource(resource_id) >= need else COLOR_BAD
	time_label.text = "Обучение: %s" % UiFormat.duration(army.get_training_time(_selected) * _amount)
	amount_label.text = str(_amount)

	var reason := army.get_recruit_block_reason(_selected, _amount)
	recruit_button.disabled = reason != ""
	recruit_button.text = "Нанять ×%d" % _amount
	reason_label.text = reason


func _rebuild_queue() -> void:
	for child in queue_list.get_children():
		queue_list.remove_child(child)
		child.queue_free()
	_queue_labels.clear()
	_queue_bars.clear()
	var army := GameState.kingdom.army
	if army.queue.is_empty():
		var empty := Label.new()
		empty.text = "Очередь пуста — выберите отряд и нажмите «Нанять»"
		empty.add_theme_font_size_override("font_size", 10)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.modulate = Color(0.7, 0.7, 0.78)
		queue_list.add_child(empty)
	for i in army.queue.size():
		var unit := Database.get_unit(army.queue[i].id)
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "queue_row.png", 8, Vector4(5, 2, 5, 2)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.add_child(UiStyles.make_icon(unit.icon if unit else null, 22))
		var lines := VBoxContainer.new()
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lines.add_theme_constant_override("separation", 1)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		lines.add_child(label)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"BarBuild"
		bar.custom_minimum_size = Vector2(0, 5)
		bar.max_value = 1.0
		bar.show_percentage = false
		lines.add_child(bar)
		row.add_child(lines)
		var cancel := TextureButton.new()
		cancel.texture_normal = load(UI_DIR + "cancel.png")
		cancel.ignore_texture_size = true
		cancel.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		cancel.custom_minimum_size = Vector2(20, 20)
		cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cancel.tooltip_text = "Отменить (ресурсы вернутся)"
		cancel.pressed.connect(army.cancel_order.bind(i))
		row.add_child(cancel)
		row_panel.add_child(row)
		queue_list.add_child(row_panel)
		_queue_labels.append(label)
		_queue_bars.append(bar)
	refresh()


## Shift — шаг 10.
func _step() -> int:
	return 10 if Input.is_key_pressed(KEY_SHIFT) else 1


func _change_amount(delta: int) -> void:
	_amount = clampi(_amount + delta, 1, MAX_AMOUNT)
	refresh()


func _on_max_pressed() -> void:
	_amount = clampi(GameState.kingdom.army.get_max_recruitable(_selected), 1, MAX_AMOUNT)
	refresh()


func _on_recruit_pressed() -> void:
	if _selected and GameState.kingdom.army.recruit(_selected, _amount):
		_amount = 1
		refresh()
