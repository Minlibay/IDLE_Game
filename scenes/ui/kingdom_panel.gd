class_name KingdomPanel
extends PanelContainer
## Королевство (оформление — assets/ui/kingdom/, по макетам assets/ui/source/ui_kingdom_*_mockup.webp):
## шапка с вкладками и ресурсами, строка состояния (защита, нападения, взнос в казну),
## вкладки «Здания» (карточки, стройка, описание) и «Армия» (ArmyView).
## Всё состояние — с сервера (GameState.kingdom — зеркало); кнопки отправляют действия на сервер.

const BUILDING_SLOT_SCENE := preload("res://scenes/ui/building_slot.tscn")
const UI_DIR := "res://assets/ui/kingdom/"
const TAB_ICON_BUILDINGS := preload("res://assets/sprites/buildings/town_hall.png")
const TAB_ICON_ARMY := preload("res://assets/ui/kingdom/icon_swords.png")
const ICON_SHIELD := preload("res://assets/ui/kingdom/icon_shield.png")
const ICON_SWORDS := preload("res://assets/ui/kingdom/icon_swords.png")
const ICON_HOURGLASS := preload("res://assets/ui/kingdom/icon_hourglass.png")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const COLOR_RATE := Color(0.55, 0.9, 0.55)

var _selected: BuildingData
var _slots: Array[BuildingSlot] = []
## resource_id -> [строка «Еда 120/250», строка «+2/м»].
var _resource_labels: Dictionary[String, Array] = {}
var _cost_labels: Dictionary[String, Label] = {}
var _cost_key := ""

@onready var buildings_tab: Button = %BuildingsTab
@onready var army_tab: Button = %ArmyTab
@onready var resource_bar: HBoxContainer = %ResourceBar
@onready var close_button: BaseButton = %CloseButton
@onready var status_strip: PanelContainer = %StatusStrip
@onready var status_icon: TextureRect = %StatusIcon
@onready var status_label: Label = %StatusLabel
@onready var deposit_button: Button = %DepositButton
@onready var buildings_page: Control = %BuildingsPage
@onready var army_view: ArmyView = %ArmyView
@onready var buildings_grid: GridContainer = %BuildingsGrid
@onready var construction_row: PanelContainer = %ConstructionRow
@onready var construction_label: Label = %ConstructionLabel
@onready var construction_bar: ProgressBar = %ConstructionBar
@onready var big_icon_frame: PanelContainer = %BigIconFrame
@onready var big_icon: TextureRect = %BigIcon
@onready var name_label: Label = %BuildingNameLabel
@onready var level_label: Label = %BuildingLevelLabel
@onready var description_label: Label = %BuildingDescriptionLabel
@onready var effect_label: Label = %BuildingEffectLabel
@onready var cost_box: HBoxContainer = %CostBox
@onready var time_row: HBoxContainer = %TimeRow
@onready var time_label: Label = %BuildTimeLabel
@onready var upgrade_button: Button = %UpgradeButton
@onready var reason_label: Label = %ReasonLabel


func _ready() -> void:
	close_button.pressed.connect(close)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	deposit_button.pressed.connect(_on_deposit_pressed)
	_setup_tabs()
	_setup_styles()
	for resource_id: String in KingdomState.RESOURCES:
		_add_resource_plaque(resource_id)
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


# --- Построение ---------------------------------------------------------------------

func _setup_tabs() -> void:
	var group := ButtonGroup.new()
	for tab: Button in [buildings_tab, army_tab]:
		tab.button_group = group
		UiStyles.style_button(tab, UI_DIR + "tab.png", UI_DIR + "tab_selected.png", 8, Vector4(10, 4, 12, 4))
		tab.add_theme_constant_override("icon_max_width", 18)
	buildings_tab.icon = TAB_ICON_BUILDINGS
	army_tab.icon = TAB_ICON_ARMY
	buildings_tab.toggled.connect(func(_on: bool) -> void: _show_page())
	army_tab.toggled.connect(func(_on: bool) -> void: _show_page())


func _setup_styles() -> void:
	status_strip.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "status_strip.png", 7, Vector4(8, 3, 8, 3)))
	_style_deposit_button()
	construction_row.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "queue_row.png", 8, Vector4(8, 3, 8, 4)))
	big_icon_frame.add_theme_stylebox_override("panel", UiStyles.texture_style(UiStyles.SLOT_DIR + "tier_epic.png", 8, Vector4(6, 6, 6, 6)))
	var buildings_box := buildings_grid.get_parent()
	var title := UiStyles.make_section_title(tr("Здания"))
	buildings_box.add_child(title)
	buildings_box.move_child(title, 0)
	var details_box := name_label.get_parent().get_parent().get_parent()
	var details_title := UiStyles.make_section_title(tr("Описание здания"))
	details_box.add_child(details_title)
	details_box.move_child(details_title, 0)


## Золотая кнопка: монеты нарисованы слева — эта часть не растягивается.
func _style_deposit_button() -> void:
	var style := UiStyles.texture_style(UI_DIR + "button_gold.png", 8, Vector4(32, 3, 10, 3)).duplicate() as StyleBoxTexture
	style.texture_margin_left = 30
	var hover := style.duplicate() as StyleBoxTexture
	hover.modulate_color = UiStyles.HOVER_MODULATE
	var disabled := style.duplicate() as StyleBoxTexture
	disabled.modulate_color = Color(0.6, 0.6, 0.6)
	deposit_button.add_theme_stylebox_override("normal", style)
	deposit_button.add_theme_stylebox_override("hover", hover)
	deposit_button.add_theme_stylebox_override("pressed", hover)
	deposit_button.add_theme_stylebox_override("disabled", disabled)
	deposit_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Плашка ресурса в шапке: крупная иконка, «120/250», «+2/м» (название — в подсказке).
func _add_resource_plaque(resource_id: String) -> void:
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", UiStyles.texture_style(UI_DIR + "resource_plaque.png", 6, Vector4(5, 1, 8, 1)))
	plaque.tooltip_text = KingdomState.resource_name(resource_id)
	plaque.custom_minimum_size = Vector2(0, 34)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UiStyles.make_icon(KingdomState.resource_icon(resource_id), 28))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", -4)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 14)
	var rate := Label.new()
	rate.add_theme_font_size_override("font_size", 11)
	rate.add_theme_color_override("font_color", COLOR_RATE)
	lines.add_child(value)
	lines.add_child(rate)
	row.add_child(lines)
	plaque.add_child(row)
	resource_bar.add_child(plaque)
	_resource_labels[resource_id] = [value, rate]


func _show_page() -> void:
	buildings_page.visible = buildings_tab.button_pressed
	army_view.visible = army_tab.button_pressed
	_refresh()


func _select(building: BuildingData) -> void:
	_selected = building
	_refresh()


# --- Обновление ---------------------------------------------------------------------

func _refresh() -> void:
	if not visible:
		return
	var kingdom := GameState.kingdom
	for resource_id: String in _resource_labels:
		var labels: Array = _resource_labels[resource_id]
		var rate := kingdom.get_production_per_minute(resource_id)
		(labels[0] as Label).text = "%d/%d" % [floori(kingdom.get_resource(resource_id)), roundi(kingdom.get_storage_capacity(resource_id))]
		(labels[1] as Label).text = tr("+%s/м") % StatModifier.format_number(rate) if rate > 0.0 else ""
	_update_status_row()
	if army_view.visible:
		army_view.refresh()
		return

	var constructing := kingdom.get_construction_building()
	for slot in _slots:
		var ratio := kingdom.get_construction_ratio() if slot.building == constructing else -1.0
		slot.update_state(kingdom.get_level(slot.building), kingdom.can_upgrade(slot.building), ratio, slot.building == _selected)
	construction_bar.visible = constructing != null
	if constructing:
		construction_label.text = tr("Стройка: %s ур. %d — %s") % [
			constructing.display_name, kingdom.get_construction_level(), UiFormat.duration(kingdom.get_construction_left())]
		construction_bar.value = kingdom.get_construction_ratio()
	else:
		construction_label.text = tr("Строители свободны — выберите здание")
	_update_details()


func _update_status_row() -> void:
	var parts := PackedStringArray()
	var icon := ICON_SHIELD
	var danger := false
	if not WorldService.is_logged_in():
		parts.append(tr("Нет связи с сервером — замок только для просмотра"))
	elif not GameState.kingdom.synced:
		parts.append(tr("Загрузка замка с сервера…"))
	for attack: Dictionary in WorldService.get_incoming():
		if attack.castle:
			danger = true
			parts.append(tr("%s идёт на замок (%d солдат) — %s") % [attack.attacker, int(attack.units),
				UiFormat.duration(WorldService.time_until(float(attack.arrivesAt)))])
	var protection := WorldService.my_protection_until()
	if protection > 0.0:
		parts.append(tr("Замок под защитой ещё %s") % UiFormat.duration(WorldService.time_until(protection)))
	elif parts.is_empty():
		parts.append(tr("Замок без защиты — армия в замке отражает набеги"))
	status_icon.texture = ICON_SWORDS if danger else icon
	status_label.text = " · ".join(parts)
	status_label.modulate = COLOR_BAD if danger else Color.WHITE
	var amount := mini(GameState.gold, WorldService.deposit_available())
	deposit_button.text = tr("Внести в казну %d") % amount if amount > 0 else tr("Внести в казну")
	deposit_button.disabled = amount <= 0 or not GameState.kingdom.synced
	deposit_button.tooltip_text = tr("Золото героя → казна замка. Лимит копится со временем и растёт с уровнем героя (сейчас %d).") \
		% WorldService.deposit_available()


func _update_details() -> void:
	if _selected == null:
		return
	var kingdom := GameState.kingdom
	var level := kingdom.get_level(_selected)
	big_icon.texture = _selected.icon
	name_label.text = _selected.display_name
	level_label.text = tr("Уровень %d / %d") % [level, _selected.max_level] if level > 0 else tr("Не построено")
	description_label.text = _selected.description

	var lines := PackedStringArray()
	if level > 0:
		lines.append(tr("Сейчас: ") + _effect_text(_selected, level))
	if level < _selected.max_level:
		lines.append(tr("→ Ур. %d: %s") % [level + 1, _effect_text(_selected, level + 1)])
	effect_label.text = "\n".join(lines)

	var maxed := level >= _selected.max_level
	cost_box.visible = not maxed
	time_row.visible = not maxed
	if not maxed:
		var cost := kingdom.get_upgrade_cost(_selected)
		# Плашки стоимости пересоздаются только при смене здания/уровня, а цифры и цвета — каждый раз.
		var cost_key := "%s|%d" % [_selected.id, level]
		if cost_key != _cost_key:
			_cost_key = cost_key
			_rebuild_cost(cost)
		for resource_id: String in _cost_labels:
			var need := float(cost[resource_id])
			var have := kingdom.get_resource(resource_id)
			_cost_labels[resource_id].text = "%d / %d" % [mini(floori(have), roundi(need)), roundi(need)]
			_cost_labels[resource_id].modulate = COLOR_OK if have >= need else COLOR_BAD
		time_label.text = tr("Время стройки: ") + UiFormat.duration(_selected.get_build_time(level + 1))

	var reason := kingdom.get_upgrade_block_reason(_selected)
	upgrade_button.disabled = reason != ""
	upgrade_button.text = tr("Построить") if level == 0 else tr("Улучшить до ур. %d") % (level + 1)
	if maxed:
		upgrade_button.text = tr("Максимум")
	reason_label.text = reason if not maxed else ""


## Что даёт здание на данном уровне.
func _effect_text(building: BuildingData, level: int) -> String:
	var parts := PackedStringArray()
	if building.produces != "":
		parts.append(tr("+%s %s/мин") % [StatModifier.format_number(building.production_per_level * level),
			KingdomState.resource_name(building.produces)])
	if building.storage_per_level > 0.0:
		parts.append(tr("склад %d, казна %d") % [roundi(KingdomState.BASE_STORAGE + building.storage_per_level * level),
			roundi((KingdomState.BASE_STORAGE + building.storage_per_level * level) * KingdomState.GOLD_STORAGE_MULTIPLIER)])
	if building.army_capacity_per_level > 0:
		parts.append(tr("армия %d мест") % (building.army_capacity_per_level * level))
	if building.is_town_hall:
		parts.append(tr("здания до ур. %d") % level)
	if not building.modifiers.is_empty():
		parts.append(StatModifier.describe_list(building.modifiers, level))
	return ", ".join(parts)


func _rebuild_cost(cost: Dictionary) -> void:
	for child in cost_box.get_children():
		cost_box.remove_child(child)
		child.queue_free()
	_cost_labels.clear()
	for resource_id: String in cost:
		_cost_labels[resource_id] = UiStyles.add_chip(cost_box, KingdomState.resource_icon(resource_id))


func _on_upgrade_pressed() -> void:
	if _selected:
		GameState.kingdom.start_upgrade(_selected)


func _on_deposit_pressed() -> void:
	deposit_button.disabled = true
	await WorldService.deposit_gold(mini(GameState.gold, WorldService.deposit_available()))
	_refresh()
