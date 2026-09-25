class_name Hud
extends CanvasLayer
## Интерфейс боя: герой (HP, опыт, золото, волна), умения, потребности, окна
## (сумка, таланты, королевство) и всплывающие сообщения.

signal rest_requested

const SKILL_BUTTON_SCENE := preload("res://scenes/ui/skill_button.tscn")
const MESSAGE_DURATION := 2.4
const COLOR_HIGHLIGHT := Color(1.0, 0.85, 0.35)
const COLOR_DANGER := Color(1.0, 0.45, 0.4)
## Важные сообщения (нападение, набег) висят дольше.
const ALERT_DURATION := 6.0
## Как часто проверять, можно ли что-то построить (подсветка кнопки королевства).
const KINGDOM_HINT_INTERVAL := 0.5

var _message_tween: Tween
var _kingdom_hint_timer := 0.0

@onready var name_label: Label = %NameLabel
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_text: Label = %HpText
@onready var xp_bar: ProgressBar = %XpBar
@onready var gold_label: Label = %GoldLabel
@onready var wave_label: Label = %WaveLabel
@onready var inventory_button: Button = %InventoryButton
@onready var talents_button: Button = %TalentsButton
@onready var kingdom_button: Button = %KingdomButton
@onready var map_button: Button = %MapButton
@onready var quit_button: Button = %QuitButton
@onready var message_label: Label = %MessageLabel
@onready var skill_list: HBoxContainer = %SkillList
@onready var auto_cast_button: Button = %AutoCastButton
@onready var needs_panel: NeedsPanel = %NeedsPanel
@onready var inventory_panel: InventoryPanel = %InventoryPanel
@onready var talent_grid: TalentGrid = %TalentGrid
@onready var kingdom_panel: KingdomPanel = %KingdomPanel
@onready var world_map: WorldMap = %WorldMap


func _ready() -> void:
	auto_cast_button.button_pressed = GameState.auto_cast
	auto_cast_button.toggled.connect(func(pressed: bool) -> void: GameState.auto_cast = pressed)
	GameState.progress_changed.connect(_refresh)
	GameState.currency_changed.connect(_refresh)
	GameState.character_changed.connect(_refresh)
	GameState.talents_changed.connect(_refresh)
	GameState.kingdom.construction_finished.connect(_on_construction_finished)
	GameState.kingdom.army.order_completed.connect(_on_order_completed)
	WorldService.incoming_attack.connect(_on_incoming_attack)
	WorldService.new_reports.connect(_on_new_reports)
	WorldService.me_updated.connect(_update_map_button)
	GameState.treasure_found.connect(_on_treasure_found)
	inventory_button.pressed.connect(toggle_inventory)
	talents_button.pressed.connect(toggle_talents)
	kingdom_button.pressed.connect(toggle_kingdom)
	map_button.pressed.connect(toggle_map)
	quit_button.pressed.connect(_on_quit_pressed)
	needs_panel.rest_requested.connect(rest_requested.emit)
	message_label.modulate.a = 0.0
	_refresh()


func _process(delta: float) -> void:
	_kingdom_hint_timer -= delta
	if _kingdom_hint_timer <= 0.0:
		_kingdom_hint_timer = KINGDOM_HINT_INTERVAL
		_update_kingdom_button()


func set_hero_health(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	# Оба значения округляются одинаково, иначе при регенерации бывает «729 / 728».
	hp_text.text = "%d / %d" % [ceili(current), ceili(maximum)]


## Создаёт кнопки умений героя (клавиши 1, 2, 3...).
func setup_skills(caster: SkillCaster) -> void:
	for child in skill_list.get_children():
		child.queue_free()
	for i in caster.skills.size():
		var button: SkillButton = SKILL_BUTTON_SCENE.instantiate()
		skill_list.add_child(button)
		button.setup(caster.skills[i], caster, str(i + 1))


func set_resting(value: bool) -> void:
	needs_panel.set_resting(value)


func toggle_inventory() -> void:
	_toggle_panel(inventory_panel)


func toggle_talents() -> void:
	_toggle_panel(talent_grid)


func toggle_kingdom() -> void:
	_toggle_panel(kingdom_panel)


func toggle_map() -> void:
	_toggle_panel(world_map)


func show_message(text: String, duration := MESSAGE_DURATION) -> void:
	message_label.text = text
	if _message_tween:
		_message_tween.kill()
	message_label.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.6)


## Одновременно открыто только одно окно.
func _toggle_panel(panel: Control) -> void:
	for other: Control in [inventory_panel, talent_grid, kingdom_panel, world_map]:
		if other != panel:
			other.close()
	panel.toggle()


func _refresh() -> void:
	var class_data := GameState.get_class_data()
	var class_name_text := class_data.display_name if class_data else "?"
	name_label.text = "%s · %s · ур. %d" % [GameState.hero_name, class_name_text, GameState.level]
	xp_bar.max_value = GameState.xp_to_next_level()
	xp_bar.value = GameState.xp
	xp_bar.tooltip_text = "Опыт: %d / %d" % [GameState.xp, GameState.xp_to_next_level()]
	gold_label.text = str(GameState.gold)
	gold_label.tooltip_text = "Золото"
	var points := GameState.get_available_talent_points()
	talents_button.text = "Таланты (%d)" % points if points > 0 else "Таланты"
	talents_button.modulate = COLOR_HIGHLIGHT if points > 0 else Color.WHITE
	var biome := Database.get_biome_for_wave(GameState.wave)
	wave_label.text = "Волна %d · %s (рекорд %d)" % [GameState.wave, biome.display_name if biome else "", GameState.best_wave]
	wave_label.modulate = biome.color.lerp(Color.WHITE, 0.5) if biome else Color.WHITE


## Подсветка «Королевства», когда строители свободны и что-то можно построить.
func _update_kingdom_button() -> void:
	var kingdom := GameState.kingdom
	var can_build := false
	if not kingdom.is_constructing():
		for building in Database.buildings:
			if kingdom.can_upgrade(building):
				can_build = true
				break
	kingdom_button.modulate = COLOR_HIGHLIGHT if can_build else Color.WHITE
	kingdom_button.text = "Замок (!)" if can_build else "Замок"


## «Карта (!)» красным, пока на игрока идёт чужая армия.
func _update_map_button() -> void:
	var danger := not WorldService.get_incoming().is_empty()
	map_button.modulate = COLOR_DANGER if danger else Color.WHITE
	map_button.text = "Карта (!)" if danger else "Карта"


func _on_incoming_attack(attack: Dictionary) -> void:
	var target := "ваш замок" if attack.castle else "вашу зону #%d" % int(attack.toZone)
	show_message("⚔ %s идёт на %s (%d солдат), прибудет через %s" % [attack.attacker, target, int(attack.units),
		UiFormat.duration(WorldService.time_until(float(attack.arrivesAt)))], ALERT_DURATION)


func _on_treasure_found(item: Item) -> void:
	show_message("✦ Сокровище: %s (%s) — загляните в Сокровищницу [I]" % [item.get_display_name(), item.get_tier_name()], ALERT_DURATION)


func _on_new_reports(reports: Array) -> void:
	# Показываем самое свежее важное событие: набег или потерю зоны.
	for report: Dictionary in reports:
		var data: Dictionary = report.data
		if data.kind in ["raid", "zone_lost"]:
			show_message(str(data.text), ALERT_DURATION)
			return


func _on_construction_finished(building: BuildingData, level: int) -> void:
	show_message("Построено: %s, ур. %d" % [building.display_name, level])


func _on_order_completed(unit: UnitData, count: int) -> void:
	show_message("Обучено: %s ×%d" % [unit.display_name, count])


func _on_quit_pressed() -> void:
	GameState.save_game()
	get_tree().quit()
