class_name KingdomPanel
extends PanelContainer
## Королевство: ресурсы и склад; вкладки «Здания» (сетка, детали, стройка) и «Армия» (ArmyView).
## Всё состояние — с сервера (GameState.kingdom — зеркало); кнопки отправляют действия на сервер.

const BUILDING_SLOT_SCENE := preload("res://scenes/ui/building_slot.tscn")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.7, 0.7, 0.78)

var _selected: BuildingData
var _slots: Array[BuildingSlot] = []
var _resource_labels: Dictionary[String, Label] = {}
var _cost_labels: Dictionary[String, Label] = {}
var _cost_key := ""
## Строка под заголовком: связь, защита замка, нападения; и кнопка взноса золота героя в казну.
var _status_label: Label
var _deposit_button: Button

@onready var resource_bar: HBoxContainer = %ResourceBar
@onready var tabs: TabContainer = %Tabs
@onready var army_view: ArmyView = %ArmyView
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
	tabs.set_tab_title(0, "Здания")
	tabs.set_tab_title(1, "Армия")
	tabs.tab_changed.connect(func(_tab: int) -> void: _refresh())
	for resource_id: String in KingdomState.RESOURCES:
		var label := UiStyles.add_resource_item(resource_bar, resource_id)
		_resource_labels[resource_id] = label
	for building in Database.buildings:
		var slot: BuildingSlot = BUILDING_SLOT_SCENE.instantiate()
		buildings_grid.add_child(slot)
		slot.setup(building)
		slot.building_pressed.connect(_select)
		_slots.append(slot)
	if not Database.buildings.is_empty():
		_selected = Database.buildings[0]
	_build_status_row()
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


func _build_status_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_label)
	_deposit_button = Button.new()
	_deposit_button.add_theme_font_size_override("font_size", 11)
	_deposit_button.pressed.connect(_on_deposit_pressed)
	row.add_child(_deposit_button)
	var vbox := tabs.get_parent()
	vbox.add_child(row)
	vbox.move_child(row, tabs.get_index())


func _refresh() -> void:
	if not visible:
		return
	var kingdom := GameState.kingdom
	for resource_id: String in _resource_labels:
		var rate := kingdom.get_production_per_minute(resource_id)
		_resource_labels[resource_id].text = "%d/%d" % [floori(kingdom.get_resource(resource_id)), roundi(kingdom.get_storage_capacity(resource_id))] \
			+ (" +%s/м" % StatModifier.format_number(rate) if rate > 0.0 else "")
	_update_status_row()

	var constructing := kingdom.get_construction_building()
	for slot in _slots:
		var ratio := kingdom.get_construction_ratio() if slot.building == constructing else -1.0
		slot.update_state(kingdom.get_level(slot.building), kingdom.can_upgrade(slot.building), ratio, slot.building == _selected)

	construction_bar.visible = constructing != null
	if constructing:
		construction_label.text = "Стройка: %s ур. %d — %s" % [
			constructing.display_name, kingdom.get_construction_level(), UiFormat.duration(kingdom.get_construction_left())]
		construction_bar.value = kingdom.get_construction_ratio()
	else:
		construction_label.text = "Строители свободны"
	_update_details()
	army_view.refresh()


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
		parts.append("склад %d, казна %d" % [roundi(KingdomState.BASE_STORAGE + building.storage_per_level * level),
			roundi((KingdomState.BASE_STORAGE + building.storage_per_level * level) * KingdomState.GOLD_STORAGE_MULTIPLIER)])
	if building.army_capacity_per_level > 0:
		parts.append("армия %d мест" % (building.army_capacity_per_level * level))
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
		var label := UiStyles.add_resource_item(cost_box, resource_id)
		label.text = str(int(cost[resource_id]))
		_cost_labels[resource_id] = label


func _update_status_row() -> void:
	var parts := PackedStringArray()
	if not WorldService.is_logged_in():
		parts.append("Нет связи с сервером — замок только для просмотра")
	elif not GameState.kingdom.synced:
		parts.append("Загрузка замка с сервера…")
	for attack: Dictionary in WorldService.get_incoming():
		if attack.castle:
			parts.append("⚔ %s идёт на замок (%d солдат) — %s" % [attack.attacker, int(attack.units),
				UiFormat.duration(WorldService.time_until(float(attack.arrivesAt)))])
	var protection := WorldService.my_protection_until()
	if protection > 0.0:
		parts.append("Замок под защитой ещё %s" % UiFormat.duration(WorldService.time_until(protection)))
	_status_label.text = " · ".join(parts)
	_status_label.modulate = COLOR_BAD if not WorldService.get_incoming().is_empty() else COLOR_HINT
	var amount := mini(GameState.gold, WorldService.deposit_available())
	_deposit_button.text = "Внести в казну %d" % amount if amount > 0 else "Внести в казну"
	_deposit_button.disabled = amount <= 0 or not GameState.kingdom.synced
	_deposit_button.tooltip_text = "Золото героя → казна замка. Лимит копится со временем и растёт с уровнем героя (сейчас %d)." \
		% WorldService.deposit_available()


func _on_upgrade_pressed() -> void:
	if _selected:
		GameState.kingdom.start_upgrade(_selected)


func _on_deposit_pressed() -> void:
	_deposit_button.disabled = true
	await WorldService.deposit_gold(mini(GameState.gold, WorldService.deposit_available()))
	_refresh()
