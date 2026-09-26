class_name WorldMap
extends Control
## Окно мировой карты: зоны, поход героя, армия на карте, гарнизоны, набеги на замки, отчёты о боях
## и их повтор (BattleReplay: как толпы сходятся и дерутся).
## Все правила — на сервере (WorldService); здесь только интерфейс.

enum DialogMode { NONE, DEPLOY, RECALL, GARRISON, WITHDRAW }

const COLOR_WIN := Color(0.45, 0.9, 0.45)
const COLOR_LOSS := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const REPORTS_SHOWN := 8
const MARCH_REDRAW_INTERVAL := 0.2
## Как часто спрашивать сервер о прибытии, когда таймер похода истёк.
const ARRIVAL_CHECK_INTERVAL := 1.0
const DIALOG_TITLES := {
	DialogMode.DEPLOY: "Отправить армию из замка на карту",
	DialogMode.RECALL: "Вернуть армию в замок",
	DialogMode.GARRISON: "Оставить гарнизон в зоне",
	DialogMode.WITHDRAW: "Забрать солдат из гарнизона",
}

var _selected := -1
var _dialog_mode := DialogMode.NONE
var _dialog_spins: Dictionary[String, SpinBox] = {}
var _redraw_timer := 0.0
var _arrival_timer := 0.0
var _error_tween: Tween

@onready var map_view: WorldMapView = %MapView
@onready var status_label: Label = %StatusLabel
@onready var army_label: Label = %ArmyLabel
@onready var deploy_button: Button = %DeployButton
@onready var recall_button: Button = %RecallButton
@onready var center_button: Button = %CenterButton
@onready var close_button: Button = %CloseButton
@onready var zone_title: Label = %ZoneTitle
@onready var zone_info: Label = %ZoneInfo
@onready var move_button: Button = %MoveButton
@onready var garrison_button: Button = %GarrisonButton
@onready var withdraw_button: Button = %WithdrawButton
@onready var reports_list: VBoxContainer = %ReportsList
@onready var login_panel: PanelContainer = %LoginPanel
@onready var url_edit: LineEdit = %UrlEdit
@onready var name_edit: LineEdit = %NameEdit
@onready var login_button: Button = %LoginButton
@onready var army_dialog: PanelContainer = %ArmyDialog
@onready var dialog_title: Label = %DialogTitle
@onready var dialog_rows: VBoxContainer = %DialogRows
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var error_label: Label = %ErrorLabel
@onready var battle_replay: BattleReplay = %BattleReplay


func _ready() -> void:
	close_button.pressed.connect(close)
	deploy_button.pressed.connect(_open_dialog.bind(DialogMode.DEPLOY))
	recall_button.pressed.connect(_open_dialog.bind(DialogMode.RECALL))
	garrison_button.pressed.connect(_open_dialog.bind(DialogMode.GARRISON))
	withdraw_button.pressed.connect(_open_dialog.bind(DialogMode.WITHDRAW))
	center_button.pressed.connect(func() -> void: map_view.center_on(WorldService.hero_zone()))
	move_button.pressed.connect(_on_move_pressed)
	login_button.pressed.connect(_on_login_pressed)
	confirm_button.pressed.connect(_on_dialog_confirm)
	cancel_button.pressed.connect(_close_dialog)
	map_view.zone_selected.connect(_on_zone_selected)
	WorldService.me_updated.connect(_refresh)
	WorldService.world_updated.connect(_refresh)
	WorldService.login_changed.connect(func(_logged_in: bool) -> void: _refresh())
	WorldService.request_failed.connect(_show_error)
	WorldService.new_reports.connect(_on_new_reports)
	error_label.modulate.a = 0.0


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	show()
	DesktopWindow.enter_map_mode()
	WorldService.set_polling(true)
	map_view.request_focus()
	url_edit.text = WorldService.server_url
	name_edit.text = GameState.hero_name
	_refresh()
	if not WorldService.is_logged_in():
		await WorldService.auto_connect()
		_refresh()
	if WorldService.is_logged_in():
		await WorldService.refresh_me()
		await WorldService.refresh_world(WorldService.zones.is_empty())
		_focus_hero()


func close() -> void:
	if not visible:
		return
	_close_dialog()
	battle_replay.close()
	hide()
	WorldService.set_polling(false)
	DesktopWindow.exit_map_mode()


func _process(delta: float) -> void:
	if not visible or not WorldService.is_marching():
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = MARCH_REDRAW_INTERVAL
		map_view.queue_redraw()
		_update_status()
	if WorldService.march_time_left() <= 0.0:
		_arrival_timer -= delta
		if _arrival_timer <= 0.0:
			_arrival_timer = ARRIVAL_CHECK_INTERVAL
			WorldService.refresh_me()
			WorldService.refresh_world()


func _focus_hero() -> void:
	map_view.request_focus()


# --- Обновление интерфейса ----------------------------------------------------------

func _refresh() -> void:
	if not visible:
		return
	login_panel.visible = not WorldService.is_logged_in()
	_update_status()
	_update_zone_panel()
	_update_reports()


func _update_status() -> void:
	if not WorldService.is_logged_in():
		status_label.text = tr("Нет входа на сервер карты")
		army_label.text = ""
		deploy_button.disabled = true
		recall_button.disabled = true
		return
	if WorldService.is_marching():
		status_label.text = tr("Поход в зону #%d — %s") % [int(WorldService.me.march.toZone), UiFormat.duration(WorldService.march_time_left())]
	elif WorldService.is_hero_at_castle():
		status_label.text = tr("Герой в замке")
	else:
		status_label.text = tr("Герой в зоне #%d") % WorldService.hero_zone()
	var incoming := WorldService.get_incoming()
	if not incoming.is_empty():
		var first: Dictionary = incoming[0]
		status_label.text += tr(" · ⚔ %s идёт на %s — %s") % [first.attacker, tr("ваш замок") if first.castle else tr("зону #%d") % int(first.toZone),
			UiFormat.duration(WorldService.time_until(float(first.arrivesAt)))]
	elif WorldService.my_protection_until() > 0.0:
		status_label.text += tr(" · замок под защитой ещё %s") % UiFormat.duration(WorldService.time_until(WorldService.my_protection_until()))
	var army := WorldService.get_my_army()
	army_label.text = tr("Армия с героем: %d · атака %d · зон: %d") % [
		_army_count(army), roundi(_army_stat(army, "attack")), int(WorldService.me.get("zonesOwned", 0))]
	deploy_button.disabled = not WorldService.is_hero_at_castle() or GameState.kingdom.army.get_total_units() == 0
	recall_button.disabled = not WorldService.is_hero_at_castle() or army.is_empty()


func _update_zone_panel() -> void:
	var zone := WorldService.get_zone(_selected)
	var has_zone := not zone.is_empty() and WorldService.is_logged_in()
	move_button.visible = has_zone
	garrison_button.visible = false
	withdraw_button.visible = false
	if not has_zone:
		zone_title.text = tr("Выберите зону на карте")
		zone_info.text = tr("Колесо — масштаб, перетаскивание — сдвиг карты.\nЖёлтая рамка — куда может пойти герой.")
		return

	var my_id := WorldService.my_id()
	var mine: bool = zone.owner != null and int(zone.owner) == my_id
	var hero_here := not WorldService.is_marching() and WorldService.hero_zone() == _selected
	zone_title.text = tr("Зона #%d · уровень %d") % [_selected, int(zone.tier)]

	var lines := PackedStringArray()
	var region := WorldService.region_of(_selected)
	if not region.is_empty():
		var control := tr("контроль: [%s]") % region.tag if region.guildId != null else tr("никто не контролирует")
		lines.append(tr("Регион: %s (%s)") % [GuildCatalog.region_name(int(region.index)), control])
	if zone.owner == null:
		lines.append(tr("Ничья"))
	elif mine:
		lines.append(tr("Ваш замок") if zone.castle else tr("Ваша зона"))
	else:
		lines.append(tr("%s игрока %s") % [tr("Замок") if zone.castle else tr("Владение"), WorldService.player_display_name(zone.owner)])
		if WorldService.is_ally(zone.owner):
			lines.append(tr("Союзник по гильдии — нападать нельзя"))
	var neutral: Dictionary = zone.neutral
	if not neutral.is_empty():
		lines.append(tr("Нейтралы: %s\nЗащита ≈ %d") % [_army_text(neutral), roundi(_army_stat(neutral, "defense"))])
	if mine and zone.castle:
		lines.append(tr("Армия замка: ") + _army_text(GameState.kingdom.army.units))
	elif mine:
		var garrison := WorldService.get_my_garrison(_selected)
		lines.append(tr("Гарнизон: ") + (_army_text(garrison) if not garrison.is_empty() else tr("нет — зону займут без боя!")))
	elif zone.owner != null and not zone.castle:
		lines.append(tr("Гарнизон: %d солдат") % int(zone.garrison))
	elif zone.owner != null:
		if WorldService.is_castle_protected(zone.owner):
			var until := float(WorldService.get_player(zone.owner).get("protectedUntil", 0.0))
			lines.append(tr("Замок под защитой ещё %s") % UiFormat.duration(WorldService.time_until(until)))
		else:
			lines.append(tr("Набег: победа даёт часть ресурсов замка, поход дольше обычного"))
	for player: Dictionary in WorldService.players.values():
		if int(player.heroZone) == _selected and not player.marching:
			lines.append(tr("Здесь герой: %s (ур. %d)") % [WorldService.tagged_name(str(player.name), player.get("guildTag")), int(player.heroLevel)])
	lines.append(tr("Бонус владельцу: ") + _bonus_text(zone.bonus))
	zone_info.text = "\n".join(lines)

	var adjacent := WorldService.are_adjacent(WorldService.hero_zone(), _selected)
	var enemy_castle: bool = zone.castle and not mine
	var no_army := not mine and WorldService.get_my_army().is_empty()
	var raid_blocked := enemy_castle and WorldService.is_castle_protected(zone.owner)
	var ally := not mine and WorldService.is_ally(zone.owner)
	move_button.disabled = WorldService.is_marching() or not adjacent or raid_blocked or no_army or ally
	if mine:
		move_button.text = tr("Перейти сюда")
	elif enemy_castle:
		move_button.text = tr("Набег на замок")
	elif zone.owner != null:
		move_button.text = tr("Напасть на игрока")
	elif not neutral.is_empty():
		move_button.text = tr("Атаковать нейтралов")
	else:
		move_button.text = tr("Занять зону")
	if ally:
		move_button.tooltip_text = tr("Союзник по гильдии — нападать нельзя")
	elif not adjacent and not hero_here:
		move_button.tooltip_text = tr("Идти можно только в соседнюю с героем зону")
	elif no_army:
		move_button.tooltip_text = tr("Без армии зону не занять: в замке нажмите «Армию из замка →»")
	elif zone.owner != null and not mine and WorldService.my_protection_until() > 0.0:
		move_button.tooltip_text = tr("Нападение на игрока снимет защиту вашего замка")
	else:
		move_button.tooltip_text = ""
	move_button.visible = not hero_here

	garrison_button.visible = hero_here and mine and not zone.castle
	garrison_button.disabled = WorldService.get_my_army().is_empty()
	withdraw_button.visible = hero_here and mine and not WorldService.get_my_garrison(_selected).is_empty()


func _update_reports() -> void:
	for child in reports_list.get_children():
		reports_list.remove_child(child)
		child.queue_free()
	var reports: Array = WorldService.me.get("reports", [])
	if reports.is_empty():
		var empty := Label.new()
		empty.text = tr("Пока нет событий")
		empty.modulate = COLOR_HINT
		empty.add_theme_font_size_override("font_size", 11)
		reports_list.add_child(empty)
	for i in mini(REPORTS_SHOWN, reports.size()):
		var report: Dictionary = reports[i]
		var data: Dictionary = report.data
		var row := HBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		label.text = tr("%s %s · зона #%d · %s") % ["✔" if data.won else "✖", WorldService.report_text(data), int(data.zoneId), _ago(float(report.createdAt))]
		label.modulate = COLOR_WIN if data.won else COLOR_LOSS
		label.tooltip_text = _report_details(data)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		if BattleReplay.can_replay(report):
			var watch := Button.new()
			watch.text = "▶"
			watch.tooltip_text = tr("Посмотреть бой")
			watch.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			watch.pressed.connect(battle_replay.play.bind(report))
			row.add_child(watch)
		reports_list.add_child(row)


# --- Действия -----------------------------------------------------------------------

## Новый бой, пока карта открыта, — сразу показываем повтор (самый свежий).
func _on_new_reports(reports: Array) -> void:
	if not visible or battle_replay.visible:
		return
	for report: Dictionary in reports:
		if BattleReplay.can_replay(report):
			battle_replay.play(report)
			return


func _on_zone_selected(zone_id: int) -> void:
	_selected = zone_id
	_refresh()


func _on_move_pressed() -> void:
	move_button.disabled = true
	await WorldService.move(_selected)
	_refresh()


func _on_login_pressed() -> void:
	login_button.disabled = true
	var result := await WorldService.register(name_edit.text.strip_edges(), url_edit.text)
	login_button.disabled = false
	if result.ok:
		_refresh()
		_focus_hero()


func _open_dialog(mode: DialogMode) -> void:
	var source := _dialog_source(mode)
	if source.is_empty():
		return
	_dialog_mode = mode
	dialog_title.text = tr(DIALOG_TITLES[mode])
	for child in dialog_rows.get_children():
		dialog_rows.remove_child(child)
		child.queue_free()
	_dialog_spins.clear()
	for unit in Database.units:
		var available := int(source.get(unit.id, 0))
		if available <= 0:
			continue
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = unit.icon
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = tr("%s (есть %d)") % [unit.display_name, available]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = available
		spin.value = available
		row.add_child(spin)
		dialog_rows.add_child(row)
		_dialog_spins[unit.id] = spin
	army_dialog.show()


func _dialog_source(mode: DialogMode) -> Dictionary:
	match mode:
		DialogMode.DEPLOY:
			return GameState.kingdom.army.units.duplicate()
		DialogMode.RECALL, DialogMode.GARRISON:
			return WorldService.get_my_army()
		DialogMode.WITHDRAW:
			return WorldService.get_my_garrison(WorldService.hero_zone())
	return {}


func _on_dialog_confirm() -> void:
	var units := {}
	for unit_id: String in _dialog_spins:
		var count := int(_dialog_spins[unit_id].value)
		if count > 0:
			units[unit_id] = count
	if units.is_empty():
		_close_dialog()
		return
	confirm_button.disabled = true
	var result: Dictionary
	match _dialog_mode:
		DialogMode.DEPLOY:
			result = await WorldService.deploy(units)
		DialogMode.RECALL:
			result = await WorldService.recall(units)
		DialogMode.GARRISON:
			result = await WorldService.garrison(units)
		DialogMode.WITHDRAW:
			result = await WorldService.withdraw(units)
	confirm_button.disabled = false
	if result.get("ok", false):
		_close_dialog()
	_refresh()


func _close_dialog() -> void:
	_dialog_mode = DialogMode.NONE
	army_dialog.hide()


func _show_error(message: String) -> void:
	if not visible:
		return
	error_label.text = message
	if _error_tween:
		_error_tween.kill()
	error_label.modulate.a = 1.0
	_error_tween = create_tween()
	_error_tween.tween_interval(3.0)
	_error_tween.tween_property(error_label, "modulate:a", 0.0, 0.6)


# --- Форматирование -----------------------------------------------------------------

func _army_text(army: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit_id: String in army:
		var unit := Database.get_unit(unit_id)
		parts.append("%d %s" % [int(army[unit_id]), unit.display_name if unit else unit_id])
	return ", ".join(parts) if not parts.is_empty() else tr("нет")


func _army_count(army: Dictionary) -> int:
	var total := 0
	for unit_id: String in army:
		total += int(army[unit_id])
	return total


func _army_stat(army: Dictionary, stat: String) -> float:
	var total := 0.0
	for unit_id: String in army:
		var unit := Database.get_unit(unit_id)
		if unit:
			total += float(unit.get(stat)) * int(army[unit_id])
	return total


func _bonus_text(bonus: Dictionary) -> String:
	var stat: int = StatModifier.Stat.get(str(bonus.get("stat", "")), -1)
	if stat < 0:
		return "?"
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.value = float(bonus.value)
	return modifier.describe()


func _report_details(data: Dictionary) -> String:
	if not data.has("attacker"):
		return WorldService.report_text(data)
	var lines := PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var side: Dictionary = data[key]
		lines.append(tr("%s: %s (сила %d, герой ур. %d)") % [
			tr("Атака") if key == "attacker" else tr("Защита"), WorldService.side_name(side), int(side.power), int(side.heroLevel)])
		lines.append(tr("  армия: %s") % _army_text(side.army))
		lines.append(tr("  потери: %s") % _army_text(side.lost))
	var loot: Dictionary = data.get("loot", {})
	if not loot.is_empty():
		var parts := PackedStringArray()
		for resource_id: String in loot:
			parts.append("%d %s" % [int(loot[resource_id]), KingdomState.resource_name(resource_id)])
		lines.append(tr("Добыча: ") + ", ".join(parts))
	return "\n".join(lines)


func _ago(created_ms: float) -> String:
	var seconds := Time.get_unix_time_from_system() - created_ms / 1000.0
	return UiFormat.duration(seconds) + tr(" назад") if seconds >= 5.0 else tr("только что")
