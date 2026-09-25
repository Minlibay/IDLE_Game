class_name InventoryPanel
extends PanelContainer
## Инвентарь: экипировка, сумка, детали предмета и действия
## (надеть/снять, продать, заточить, слить 3 в 1).

const ITEM_SLOT_SCENE := preload("res://scenes/ui/item_slot.tscn")
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)

var _selected: Item
var _equip_slots: Dictionary[int, ItemSlot] = {}

@onready var close_button: Button = %CloseButton
@onready var count_label: Label = %CountLabel
@onready var equip_grid: GridContainer = %EquipGrid
@onready var stats_label: Label = %StatsLabel
@onready var bag_grid: GridContainer = %BagGrid
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_info_label: Label = %ItemInfoLabel
@onready var equip_button: Button = %EquipButton
@onready var sell_button: Button = %SellButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var fuse_button: Button = %FuseButton
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	close_button.pressed.connect(close)
	equip_button.pressed.connect(_on_equip_pressed)
	sell_button.pressed.connect(_on_sell_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	fuse_button.pressed.connect(_on_fuse_pressed)
	for slot: int in ItemBase.Slot.values():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var label := Label.new()
		label.text = ItemBase.slot_name(slot)
		label.add_theme_font_size_override("font_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
		var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		box.add_child(item_slot)
		item_slot.item_pressed.connect(_select)
		equip_grid.add_child(box)
		_equip_slots[slot] = item_slot
	GameState.inventory_changed.connect(_refresh)
	GameState.stats_changed.connect(_refresh)
	GameState.currency_changed.connect(_update_details)


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


func _refresh() -> void:
	if not visible:
		return
	if _selected and not (GameState.inventory.has(_selected) or GameState.is_equipped(_selected)):
		_selected = null

	for child in bag_grid.get_children():
		bag_grid.remove_child(child)
		child.queue_free()
	for item in GameState.inventory:
		var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		bag_grid.add_child(item_slot)
		item_slot.set_item(item)
		item_slot.set_selected(item == _selected)
		item_slot.item_pressed.connect(_select)

	for slot: int in _equip_slots:
		var equipped: Item = GameState.equipment.get(slot)
		_equip_slots[slot].set_item(equipped)
		_equip_slots[slot].set_selected(equipped != null and equipped == _selected)

	count_label.text = "Сумка: %d / %d" % [GameState.inventory.size(), GameState.INVENTORY_SIZE]
	var stats := GameState.get_hero_stats()
	stats_label.text = "HP %d · Урон %d\nБроня %d · Крит %d%%\nАтака раз в %.2f с" % [
		roundi(stats.max_hp), roundi(stats.damage), roundi(stats.armor),
		roundi(stats.crit_chance * 100.0), stats.attack_interval]
	_update_details()


func _select(item: Item) -> void:
	_selected = item
	result_label.text = ""
	_refresh()


func _update_details() -> void:
	var has_item := _selected != null
	for button: Button in [equip_button, sell_button, upgrade_button, fuse_button]:
		button.disabled = not has_item
	if not has_item:
		item_name_label.text = "Выберите предмет"
		item_name_label.modulate = Color.WHITE
		item_info_label.text = ""
		equip_button.text = "Надеть"
		sell_button.text = "Продать"
		upgrade_button.text = "Заточить"
		fuse_button.text = "Слить 3→1"
		return

	var base := _selected.get_base()
	item_name_label.text = _selected.get_display_name()
	item_name_label.modulate = _selected.get_tier_color()
	var lines := PackedStringArray()
	lines.append("%s · %s · ур. %d" % [_selected.get_tier_name(), ItemBase.slot_name(base.slot), _selected.item_level])
	var stats := _selected.get_stats()
	for key: String in stats:
		lines.append("%s: +%s" % [Item.STAT_NAMES.get(key, key), str(stats[key])])
	if not base.allowed_classes.is_empty():
		var names := PackedStringArray()
		for id in base.allowed_classes:
			var class_data := Database.get_class_data(id)
			names.append(class_data.display_name if class_data else id)
		lines.append("Только: " + ", ".join(names))
	item_info_label.text = "\n".join(lines)

	var equipped := GameState.is_equipped(_selected)
	equip_button.text = "Снять" if equipped else "Надеть"
	equip_button.disabled = not equipped and not GameState.can_equip(_selected)

	sell_button.text = "Продать (%d з)" % _selected.get_sell_price()
	sell_button.disabled = equipped

	if _selected.upgrade_level >= Item.MAX_UPGRADE_LEVEL:
		upgrade_button.text = "Заточка: макс."
		upgrade_button.disabled = true
	else:
		var cost := ItemUpgrader.get_upgrade_cost(_selected)
		upgrade_button.text = "Заточить: %d з (%d%%)" % [cost, roundi(ItemUpgrader.get_success_chance(_selected) * 100.0)]
		upgrade_button.disabled = GameState.gold < cost

	fuse_button.disabled = not ItemUpgrader.can_fuse(_selected)
	fuse_button.tooltip_text = "Нужно 3 предмета тира «%s» в слот «%s» в сумке" % [
		_selected.get_tier_name(), ItemBase.slot_name(base.slot)]


func _on_equip_pressed() -> void:
	if _selected == null:
		return
	if GameState.is_equipped(_selected):
		if not GameState.unequip(_selected.get_base().slot):
			_show_result("Сумка полна", COLOR_BAD)
	else:
		GameState.equip(_selected)


func _on_sell_pressed() -> void:
	if _selected == null:
		return
	var price := _selected.get_sell_price()
	GameState.sell_item(_selected)
	_selected = null
	_show_result("Продано за %d з" % price, COLOR_OK)
	_refresh()


func _on_upgrade_pressed() -> void:
	if _selected == null:
		return
	match ItemUpgrader.try_upgrade(_selected):
		ItemUpgrader.Result.SUCCESS:
			_show_result("Успех! Теперь +%d" % _selected.upgrade_level, COLOR_OK)
		ItemUpgrader.Result.FAILED:
			_show_result("Неудача… золото потрачено", COLOR_BAD)
		ItemUpgrader.Result.NOT_ENOUGH_GOLD:
			_show_result("Не хватает золота", COLOR_BAD)
		ItemUpgrader.Result.MAX_LEVEL:
			_show_result("Максимальная заточка", COLOR_BAD)
	_update_details()


func _on_fuse_pressed() -> void:
	if _selected == null:
		return
	var result := ItemUpgrader.fuse(_selected)
	if result == null:
		_show_result("Нечего сливать", COLOR_BAD)
		return
	_selected = result
	_show_result("Получено: %s (%s)" % [result.get_display_name(), result.get_tier_name()], result.get_tier_color())
	_refresh()


func _show_result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.modulate = color
