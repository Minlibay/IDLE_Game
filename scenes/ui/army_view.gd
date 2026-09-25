class_name ArmyView
extends HBoxContainer
## Вкладка «Армия» в окне королевства: сила и численность, содержание, очередь обучения, найм отрядов.

const UNIT_SLOT_SCENE := preload("res://scenes/ui/unit_slot.tscn")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)

var _selected: UnitData
var _slots: Array[UnitSlot] = []
var _queue_time_labels: Array[Label] = []
var _cost_labels: Dictionary[String, Label] = {}
var _cost_unit_id := ""

@onready var power_label: Label = %PowerLabel
@onready var stats_label: Label = %ArmyStatsLabel
@onready var starving_label: Label = %StarvingLabel
@onready var queue_list: VBoxContainer = %QueueList
@onready var units_grid: GridContainer = %UnitsGrid
@onready var name_label: Label = %UnitNameLabel
@onready var info_label: Label = %UnitInfoLabel
@onready var cost_box: HBoxContainer = %UnitCostBox
@onready var time_label: Label = %UnitTimeLabel
@onready var amount_spin: SpinBox = %AmountSpin
@onready var max_button: Button = %MaxButton
@onready var recruit_button: Button = %RecruitButton
@onready var reason_label: Label = %RecruitReasonLabel


func _ready() -> void:
	for unit in Database.units:
		var slot: UnitSlot = UNIT_SLOT_SCENE.instantiate()
		units_grid.add_child(slot)
		slot.setup(unit)
		slot.unit_pressed.connect(_select)
		_slots.append(slot)
	if not Database.units.is_empty():
		_selected = Database.units[0]
	amount_spin.value_changed.connect(func(_value: float) -> void: refresh())
	max_button.pressed.connect(_on_max_pressed)
	recruit_button.pressed.connect(_on_recruit_pressed)
	GameState.kingdom.army.changed.connect(_rebuild_queue)
	_rebuild_queue()


## Вызывается окном королевства каждый раз, когда меняются ресурсы (т.е. каждый кадр, пока окно открыто).
func refresh() -> void:
	if not is_visible_in_tree():
		return
	var army := GameState.kingdom.army
	power_label.text = "Сила армии: %d" % roundi(army.get_power())
	stats_label.text = "Атака %d · Защита %d\nСолдат: %d · Места: %d / %d\nСодержание: %s еды/мин" % [
		roundi(army.get_attack()), roundi(army.get_defense()), army.get_total_units(),
		army.get_housing_used(), army.get_capacity(), StatModifier.format_number(snappedf(army.get_upkeep_per_minute(), 0.01))]
	starving_label.visible = army.starving
	for i in _queue_time_labels.size():
		if i < army.queue.size():
			_queue_time_labels[i].text = "%s ×%d — %s" % [
				Database.get_unit(army.queue[i].id).display_name, int(army.queue[i].count),
				UiFormat.duration(army.get_order_time_left(i))]
	for slot in _slots:
		slot.update_state(army.get_count(slot.unit), army.is_unlocked(slot.unit),
			army.get_recruit_block_reason(slot.unit, 1) == "", slot.unit == _selected)
	_update_details()


func _select(unit: UnitData) -> void:
	_selected = unit
	amount_spin.value = 1
	refresh()


func _update_details() -> void:
	if _selected == null:
		return
	var army := GameState.kingdom.army
	var kingdom := GameState.kingdom
	name_label.text = "%s (в армии: %d)" % [_selected.display_name, army.get_count(_selected)]
	info_label.text = "%s\nАтака %s · Защита %s · Мест: %d · Еда: %s/мин" % [
		_selected.description, StatModifier.format_number(_selected.attack), StatModifier.format_number(_selected.defense),
		_selected.housing, StatModifier.format_number(_selected.upkeep_per_minute)]

	var count := int(amount_spin.value)
	var total_cost := KingdomState.multiply_cost(_selected.cost, count)
	if _cost_unit_id != _selected.id:
		_cost_unit_id = _selected.id
		for child in cost_box.get_children():
			cost_box.remove_child(child)
			child.queue_free()
		_cost_labels.clear()
		for resource_id: String in _selected.cost:
			_cost_labels[resource_id] = UiStyles.add_resource_item(cost_box, resource_id)
	for resource_id: String in _cost_labels:
		var amount := float(total_cost[resource_id])
		_cost_labels[resource_id].text = str(ceili(amount))
		_cost_labels[resource_id].modulate = COLOR_OK if kingdom.get_resource(resource_id) >= amount else COLOR_BAD
	time_label.text = "Обучение: %s" % UiFormat.duration(army.get_training_time(_selected) * count)

	var reason := army.get_recruit_block_reason(_selected, count)
	recruit_button.disabled = reason != ""
	recruit_button.text = "Нанять ×%d" % count
	reason_label.text = reason


func _rebuild_queue() -> void:
	for child in queue_list.get_children():
		queue_list.remove_child(child)
		child.queue_free()
	_queue_time_labels.clear()
	var army := GameState.kingdom.army
	if army.queue.is_empty():
		var empty := Label.new()
		empty.text = "Очередь обучения пуста"
		empty.add_theme_font_size_override("font_size", 11)
		empty.modulate = Color(0.7, 0.7, 0.78)
		queue_list.add_child(empty)
	for i in army.queue.size():
		var unit := Database.get_unit(army.queue[i].id)
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = unit.icon if unit else null
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_queue_time_labels.append(label)
		var cancel := Button.new()
		cancel.text = "✕"
		cancel.tooltip_text = "Отменить (ресурсы вернутся)"
		cancel.pressed.connect(army.cancel_order.bind(i))
		row.add_child(cancel)
		queue_list.add_child(row)
	refresh()


func _on_max_pressed() -> void:
	amount_spin.value = maxi(1, GameState.kingdom.army.get_max_recruitable(_selected))


func _on_recruit_pressed() -> void:
	if _selected and GameState.kingdom.army.recruit(_selected, int(amount_spin.value)):
		amount_spin.value = 1
