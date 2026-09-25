class_name InventoryPanel
extends PanelContainer
## Инвентарь (оформление — assets/ui/inventory/, по макету assets/ui/source/ui_inventory_mockup.webp):
## экипировка героя вокруг его фигуры, реликвии армии, характеристики, сумка и карточка предмета
## с действиями (надеть/снять, продать, заточить, слить 3 в 1).

const ITEM_SLOT_SCENE := preload("res://scenes/ui/item_slot.tscn")
const UI_DIR := "res://assets/ui/inventory/"
const ICON_DIR := "res://assets/ui/icons/"
const COLOR_OK := Color(0.45, 0.9, 0.45)
const COLOR_BAD := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.62, 0.6, 0.72)
const SLOT_SIZE := Vector2(40, 40)
const RELIC_SLOT_SIZE := Vector2(34, 34)
## Слоты вокруг фигуры героя: слева и справа (сверху вниз).
const LEFT_SLOTS: Array[int] = [ItemBase.Slot.HELMET, ItemBase.Slot.SHOULDERS, ItemBase.Slot.ARMOR, ItemBase.Slot.LEGS]
const RIGHT_SLOTS: Array[int] = [ItemBase.Slot.WEAPON, ItemBase.Slot.TRINKET, ItemBase.Slot.BOOTS]
## Рамка пустого слота с призрачной иконкой.
const EMPTY_SLOT_FRAMES := {
	ItemBase.Slot.HELMET: "slot_helmet", ItemBase.Slot.SHOULDERS: "slot_shoulders", ItemBase.Slot.ARMOR: "slot_armor",
	ItemBase.Slot.LEGS: "slot_legs", ItemBase.Slot.WEAPON: "slot_weapon", ItemBase.Slot.TRINKET: "slot_trinket",
	ItemBase.Slot.BOOTS: "slot_boots",
}
## Иконка стата (assets/ui/icons/) для характеристик и карточки предмета.
const STAT_ICONS := {
	"damage": "attack", "max_hp": "health", "armor": "defense", "attack_speed": "time", "crit_chance": "battle",
	"army_power": "army", "army_attack": "attack", "army_defense": "defense", "training_speed": "time",
	"upkeep_reduction": "food",
}

var _selected: Item
var _equip_slots: Dictionary[int, ItemSlot] = {}
var _relic_slots: Array[ItemSlot] = []
var _bag_slots: Array[ItemSlot] = []
var _big_slot: ItemSlot

@onready var close_button: BaseButton = %CloseButton
@onready var count_label: Label = %CountLabel
@onready var gold_label: Label = %GoldLabel
@onready var left_slots: VBoxContainer = %LeftSlots
@onready var right_slots: VBoxContainer = %RightSlots
@onready var hero_sprite: TextureRect = %HeroSprite
@onready var relic_grid: GridContainer = %RelicGrid
@onready var hero_stats: GridContainer = %HeroStats
@onready var army_stats: GridContainer = %ArmyStats
@onready var bag_grid: GridContainer = %BagGrid
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_tier_label: Label = %ItemTierLabel
@onready var description_label: Label = %DescriptionLabel
@onready var item_stats: GridContainer = %ItemStats
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
	_build_titles()
	for slot: int in LEFT_SLOTS:
		_equip_slots[slot] = _make_equip_slot(slot, left_slots)
	for slot: int in RIGHT_SLOTS:
		_equip_slots[slot] = _make_equip_slot(slot, right_slots)
	for i in GameState.ARMY_RELIC_SLOTS:
		var relic_slot := _make_slot(relic_grid, RELIC_SLOT_SIZE)
		relic_slot.empty_frame = UI_DIR + "slot_relic.png"
		relic_slot.empty_tooltip = "Реликвия армии: пусто.\nРеликвии выпадают с монстров и усиливают армию замка."
		_relic_slots.append(relic_slot)
	for i in GameState.INVENTORY_SIZE:
		_bag_slots.append(_make_slot(bag_grid, SLOT_SIZE))
	_big_slot = ITEM_SLOT_SCENE.instantiate()
	(%BigSlot as Control).add_child(_big_slot)
	_big_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.inventory_changed.connect(_refresh)
	GameState.stats_changed.connect(_refresh)
	GameState.army_gear_changed.connect(_refresh)
	GameState.character_changed.connect(_update_hero_sprite)
	_update_hero_sprite()
	GameState.currency_changed.connect(_on_currency_changed)


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
	_update_hero_sprite()
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()


# --- Построение ---------------------------------------------------------------------

## Заголовки разделов: «✦ Название ———».
func _build_titles() -> void:
	var sections := {
		"VBox/Body/EquipSection/VBox": "Экипировка",
		"VBox/Body/StatsSection/VBox": "Герой",
		"VBox/Body/BagSection/VBox": "Предметы",
		"VBox/Body/DetailsSection/VBox": "Описание предмета",
	}
	for path: String in sections:
		var box := get_node(path) as VBoxContainer
		var title := _make_title(sections[path])
		box.add_child(title)
		box.move_child(title, 0)
	# Внутри раздела «Экипировка» — подзаголовок реликвий, в «Герое» — подзаголовок армии.
	var relic_title := _make_title("Реликвии армии")
	relic_grid.get_parent().add_child(relic_title)
	relic_grid.get_parent().move_child(relic_title, relic_grid.get_index())
	var army_title := _make_title("Армия")
	army_stats.get_parent().add_child(army_title)
	army_stats.get_parent().move_child(army_title, army_stats.get_index())


func _make_title(text: String) -> HBoxContainer:
	return UiStyles.make_section_title(text)


func _make_slot(parent: Container, slot_size: Vector2) -> ItemSlot:
	var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
	item_slot.custom_minimum_size = slot_size
	parent.add_child(item_slot)
	item_slot.item_pressed.connect(_select)
	return item_slot


func _make_equip_slot(slot: int, parent: Container) -> ItemSlot:
	var item_slot := _make_slot(parent, SLOT_SIZE)
	item_slot.empty_frame = UI_DIR + EMPTY_SLOT_FRAMES[slot] + ".png"
	item_slot.empty_tooltip = "%s: пусто" % ItemBase.slot_name(slot)
	return item_slot


## Фигура героя в нише: первый кадр анимации ожидания или спрайт класса.
func _update_hero_sprite() -> void:
	var class_data := GameState.get_class_data()
	var texture: Texture2D = null
	if class_data:
		texture = class_data.sprite
		var frames := class_data.sprite_frames
		if frames and frames.has_animation(&"idle") and frames.get_frame_count(&"idle") > 0:
			texture = frames.get_frame_texture(&"idle", 0)
	hero_sprite.texture = texture


# --- Обновление ---------------------------------------------------------------------

func _refresh() -> void:
	if not visible:
		return
	if _selected and not (GameState.inventory.has(_selected) or GameState.is_equipped(_selected)):
		_selected = null
	for i in _bag_slots.size():
		var item: Item = GameState.inventory[i] if i < GameState.inventory.size() else null
		_bag_slots[i].set_item(item)
		_bag_slots[i].set_selected(item != null and item == _selected)
	for slot: int in _equip_slots:
		var equipped: Item = GameState.equipment.get(slot)
		_equip_slots[slot].set_item(equipped)
		_equip_slots[slot].set_selected(equipped != null and equipped == _selected)
	for i in _relic_slots.size():
		var relic: Item = GameState.army_relics[i] if i < GameState.army_relics.size() else null
		_relic_slots[i].set_item(relic)
		_relic_slots[i].set_selected(relic != null and relic == _selected)
	count_label.text = "Сумка: %d / %d" % [GameState.inventory.size(), GameState.INVENTORY_SIZE]
	_update_stats()
	_update_details()


func _on_currency_changed() -> void:
	if visible:
		_update_details()


func _update_stats() -> void:
	gold_label.text = _format_int(GameState.gold)
	var stats := GameState.get_hero_stats()
	_fill_rows(hero_stats, [
		["health", "Здоровье", str(roundi(stats.max_hp))],
		["attack", "Урон", str(roundi(stats.damage))],
		["defense", "Броня", str(roundi(stats.armor))],
		["battle", "Крит", "%d%%" % roundi(stats.crit_chance * 100.0)],
		["time", "Атака раз в", "%.2f с" % stats.attack_interval],
	])
	var rows := []
	var bonuses := GameState.get_army_gear_bonuses()
	for key: String in Item.ARMY_STAT_KEYS:
		var stat_name: String = Item.ARMY_STAT_KEYS[key]
		if bonuses.has(stat_name):
			rows.append([STAT_ICONS[key], _short_stat_name(key), "+%s%%" % str(bonuses[stat_name])])
	if rows.is_empty():
		rows.append(["banner", "Нет реликвий", ""])
	_fill_rows(army_stats, rows)


func _update_details() -> void:
	var has_item := _selected != null
	for button: Button in [equip_button, sell_button, upgrade_button, fuse_button]:
		button.disabled = not has_item
	_big_slot.set_item(_selected)
	if not has_item:
		item_name_label.text = "Выберите предмет"
		item_name_label.modulate = Color.WHITE
		item_tier_label.text = "Нажмите на предмет в сумке или экипировке"
		item_tier_label.modulate = COLOR_HINT
		description_label.text = ""
		_fill_rows(item_stats, [])
		equip_button.text = "Надеть"
		sell_button.text = "Продать"
		upgrade_button.text = "Заточить"
		return

	var base := _selected.get_base()
	item_name_label.text = _selected.get_display_name()
	item_name_label.modulate = _selected.get_tier_color()
	item_tier_label.text = "%s · %s · ур. %d" % [_selected.get_tier_name(), ItemBase.slot_name(base.slot), _selected.item_level]
	item_tier_label.modulate = _selected.get_tier_color().lerp(COLOR_HINT, 0.4)
	var description := base.description
	if not base.allowed_classes.is_empty():
		var names := PackedStringArray()
		for id in base.allowed_classes:
			var class_data := Database.get_class_data(id)
			names.append(class_data.display_name if class_data else id)
		description += ("\n" if description != "" else "") + "Только: " + ", ".join(names)
	description_label.text = description
	var rows := []
	var stats := _selected.get_stats()
	for key: String in stats:
		var is_percent: bool = key in ["attack_speed", "crit_chance"] or Item.ARMY_STAT_KEYS.has(key)
		rows.append([STAT_ICONS.get(key, "level_up"), _short_stat_name(key), "+%s%s" % [str(stats[key]), "%" if is_percent else ""]])
	_fill_rows(item_stats, rows)

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


## Строки «иконка · название · значение» в сетке из 3 колонок (пересоздаются целиком — их мало).
func _fill_rows(grid: GridContainer, rows: Array) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for row: Array in rows:
		var icon := TextureRect.new()
		icon.texture = load(ICON_DIR + str(row[0]) + ".png")
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		grid.add_child(icon)
		var name_label := Label.new()
		name_label.text = str(row[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 11)
		grid.add_child(name_label)
		var value_label := Label.new()
		value_label.text = str(row[2])
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		grid.add_child(value_label)


func _short_stat_name(key: String) -> String:
	return str(Item.STAT_NAMES.get(key, key)).trim_suffix(", %")


## 12480 -> «12 480».
func _format_int(value: int) -> String:
	var text := str(absi(value))
	var result := ""
	while text.length() > 3:
		result = " " + text.right(3) + result
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + result


func _select(item: Item) -> void:
	_selected = item
	result_label.text = ""
	_refresh()


# --- Действия -----------------------------------------------------------------------

func _on_equip_pressed() -> void:
	if _selected == null:
		return
	if GameState.is_equipped(_selected):
		if not GameState.unequip_item(_selected):
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
	_refresh()


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
