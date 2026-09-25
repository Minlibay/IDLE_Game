class_name KingdomPanel
extends PanelContainer
## Королевство: ресурсы и склад, сетка зданий, детали выбранного здания, стройка.

const BUILDING_SLOT_SCENE := preload("res://scenes/ui/building_slot.tscn")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.7, 0.7, 0.78)

var _selected: BuildingData
var _slots: Array[BuildingSlot] = []
var _resource_labels: Dictionary[String, Label] = {}
var _cost_labels: Dictionary[String, Label] = {}
var _cost_key := ""

@onready var resource_bar: HBoxContainer = %ResourceBar
@onready var close_button: Button = %CloseButton
@onready var buildings_grid: GridContainer = %BuildingsGrid
@onready var construction_label: Label = %ConstructionLabel
@onready var construction_bar: ProgressBar = %ConstructionBar
@onready var name_label: Label = %BuildingNameLabel
@onready var level_label: Label = %BuildingLevelLabel
@onready var description_label: Label = %BuildingDescriptionLabel
@onready var effect_label: Label = %BuildingEffectLabel
@onready var cost_box: HBoxContainer = %CostBox
@onready var time_label: Label = %BuildTimeLabel
@onready var upgrade_button: Button = %UpgradeButton
@onready var reason_label: Label = %ReasonLabel


func _ready() -> void:
	close_button.pressed.connect(close)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	for resource_id: String in KingdomState.RESOURCES:
		var label := _add_resource_item(resource_bar, resource_id)
		_resource_labels[resource_id] = label
	for building in Database.buildings:
		var slot: BuildingSlot = BUILDING_SLOT_SCENE.instantiate()
		buildings_grid.add_child(slot)
		slot.setup(building)
		slot.building_pressed.connect(_select)
		_slots.append(slot)
	if not Database.buildings.is_empty():
		_selected = Database.buildings[0]
	GameState.kingdom.resources_changed.connect(_refresh)
	GameState.kingdom.buildings_changed.connect(_refresh)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	show()
	DesktopWindow.push_modal()
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()


func _select(building: BuildingData) -> void:
	_selected = building
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	var kingdom := GameState.kingdom
	var capacity := kingdom.get_storage_capacity()
	for resource_id: String in _resource_labels:
		var rate := kingdom.get_production_per_minute(resource_id)
		_resource_labels[resource_id].text = "%d/%d" % [floori(kingdom.get_resource(resource_id)), roundi(capacity)] \
			+ (" +%s/м" % StatModifier.format_number(rate) if rate > 0.0 else "")

	var constructing := kingdom.get_construction_building()
	for slot in _slots:
		var ratio := kingdom.get_construction_ratio() if slot.building == constructing else -1.0
		slot.update_state(kingdom.get_level(slot.building), kingdom.can_upgrade(slot.building), ratio, slot.building == _selected)

	construction_bar.visible = constructing != null
	if constructing:
		construction_label.text = "Стройка: %s ур. %d — %s" % [
			constructing.display_name, kingdom.construction_level, UiFormat.duration(kingdom.construction_left)]
		construction_bar.value = kingdom.get_construction_ratio()
	else:
		construction_label.text = "Строители свободны"
	_update_details()


func _update_details() -> void:
	if _selected == null:
		return
	var kingdom := GameState.kingdom
	var level := kingdom.get_level(_selected)
	name_label.text = _selected.display_name
	level_label.text = "Уровень %d / %d" % [level, _selected.max_level] if level > 0 else "Не построено"
	description_label.text = _selected.description

	var lines := PackedStringArray()
	if level > 0:
		lines.append("Сейчас: " + _effect_text(_selected, level))
	if level < _selected.max_level:
		lines.append("Ур. %d: %s" % [level + 1, _effect_text(_selected, level + 1)])
	effect_label.text = "\n".join(lines)

	var maxed := level >= _selected.max_level
	cost_box.visible = not maxed
	time_label.visible = not maxed
	if not maxed:
		var cost := kingdom.get_upgrade_cost(_selected)
		# Узлы стоимости пересоздаются только при смене здания/уровня, а цвета обновляются каждый раз.
		var cost_key := "%s|%d" % [_selected.id, level]
		if cost_key != _cost_key:
			_cost_key = cost_key
			_rebuild_cost(cost)
		for resource_id: String in _cost_labels:
			var enough := kingdom.get_resource(resource_id) >= float(cost[resource_id])
			_cost_labels[resource_id].modulate = COLOR_OK if enough else COLOR_BAD
		time_label.text = "Время стройки: " + UiFormat.duration(_selected.get_build_time(level + 1))

	var reason := kingdom.get_upgrade_block_reason(_selected)
	upgrade_button.disabled = reason != ""
	upgrade_button.text = "Построить" if level == 0 else "Улучшить до ур. %d" % (level + 1)
	if maxed:
		upgrade_button.text = "Максимум"
	reason_label.text = reason if not maxed else ""


## Что даёт здание на данном уровне.
func _effect_text(building: BuildingData, level: int) -> String:
	var parts := PackedStringArray()
	if building.produces != "":
		parts.append("+%s %s/мин" % [StatModifier.format_number(building.production_per_level * level),
			KingdomState.resource_name(building.produces)])
	if building.storage_per_level > 0.0:
		parts.append("склад %d" % roundi(KingdomState.BASE_STORAGE + building.storage_per_level * level))
	if building.is_town_hall:
		parts.append("здания до ур. %d" % level)
	if not building.modifiers.is_empty():
		parts.append(StatModifier.describe_list(building.modifiers, level))
	return ", ".join(parts)


func _rebuild_cost(cost: Dictionary) -> void:
	for child in cost_box.get_children():
		cost_box.remove_child(child)
		child.queue_free()
	_cost_labels.clear()
	for resource_id: String in cost:
		var label := _add_resource_item(cost_box, resource_id)
		label.text = str(int(cost[resource_id]))
		_cost_labels[resource_id] = label


func _on_upgrade_pressed() -> void:
	if _selected:
		GameState.kingdom.start_upgrade(_selected)


func _add_resource_item(parent: Container, resource_id: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.tooltip_text = KingdomState.resource_name(resource_id)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := TextureRect.new()
	icon.texture = KingdomState.resource_icon(resource_id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	parent.add_child(box)
	return label
