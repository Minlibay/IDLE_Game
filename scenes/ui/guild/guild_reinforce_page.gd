class_name GuildReinforcePage
extends HBoxContainer
## Вкладка «Подкрепления»: отправить солдат из своего замка защищать замок союзника.
## Солдаты остаются вашими — едят из вашей казны, защищают союзника при набегах, отзываются в любой момент.

signal result(text: String, ok: bool)

var _ally_select: OptionButton
var _unit_rows: VBoxContainer
var _spins: Dictionary = {}
var _send_button: Button
var _sent_list: VBoxContainer
var _incoming_list: VBoxContainer
var _capacity_label: Label
var _ally_ids: Array[int] = []
var _no_units_label: Label


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var send := PanelUi.section(self, tr("Отправить союзнику"), 360)
	_ally_select = OptionButton.new()
	_ally_select.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	send.add_child(_ally_select)
	_unit_rows = VBoxContainer.new()
	_unit_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unit_rows.add_theme_constant_override("separation", 2)
	send.add_child(_unit_rows)
	_no_units_label = PanelUi.hint(tr("В замке нет солдат — обучите их в «Замке» [K]."))
	_unit_rows.add_child(_no_units_label)
	_send_button = PanelUi.button(tr("Отправить"), &"ButtonGreen")
	_send_button.tooltip_text = tr("Войска идут до замка союзника, как в набег, и защищают его, пока вы их не отзовёте.")
	_send_button.pressed.connect(_on_send_pressed)
	send.add_child(_send_button)

	var sent := PanelUi.section(self, tr("Мои подкрепления"), 0)
	_sent_list = PanelUi.scroll_list(sent)
	var incoming := PanelUi.section(self, tr("В моём замке"), 0)
	_capacity_label = PanelUi.hint("", 11)
	incoming.add_child(_capacity_label)
	_incoming_list = PanelUi.scroll_list(incoming)


func refresh() -> void:
	_refresh_allies()
	_refresh_units()
	_refresh_sent()
	_refresh_incoming()


func _refresh_allies() -> void:
	var members: Array = WorldService.guild.get("members", [])
	var ids: Array[int] = []
	for member: Dictionary in members:
		if int(member.playerId) != WorldService.my_id():
			ids.append(int(member.playerId))
	if ids == _ally_ids:
		return
	var selected := _ally_ids[_ally_select.selected] if _ally_select.selected >= 0 and _ally_select.selected < _ally_ids.size() else -1
	_ally_ids = ids
	_ally_select.clear()
	for member: Dictionary in members:
		if int(member.playerId) != WorldService.my_id():
			_ally_select.add_item(tr("%s (ур. %d)") % [member.name, int(member.heroLevel)])
	_ally_select.selected = maxi(0, _ally_ids.find(selected)) if not _ally_ids.is_empty() else -1


func _refresh_units() -> void:
	var castle: Dictionary = GameState.kingdom.army.units
	var shown := {}
	for unit in Database.units:
		var count := int(castle.get(unit.id, 0))
		if count <= 0:
			continue
		shown[unit.id] = true
		if not _spins.has(unit.id):
			var row := HBoxContainer.new()
			row.add_child(UiStyles.make_icon(unit.icon, 22))
			var label := PanelUi.cell(unit.display_name, 0, Color.WHITE, true)
			row.add_child(label)
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.step = 1
			spin.custom_minimum_size = Vector2(110, 0)
			row.add_child(spin)
			row.set_meta(&"unit", unit.id)
			_unit_rows.add_child(row)
			_spins[unit.id] = spin
		var spin: SpinBox = _spins[unit.id]
		spin.max_value = count
		spin.suffix = "/ %d" % count
	for unit_id: String in _spins.keys():
		if not shown.has(unit_id):
			(_spins[unit_id] as SpinBox).get_parent().queue_free()
			_spins.erase(unit_id)
	var no_units := _spins.is_empty()
	_no_units_label.visible = no_units
	_send_button.disabled = no_units or _ally_ids.is_empty()


func _refresh_sent() -> void:
	PanelUi.clear(_sent_list)
	var sent: Array = WorldService.me.get("reinforcementsSent", [])
	if sent.is_empty():
		_sent_list.add_child(PanelUi.hint(tr("Вы никому не отправляли подкрепления.")))
	for entry: Dictionary in sent:
		var row := HBoxContainer.new()
		var text := "→ %s: %s · %s" % [entry.toName, PanelUi.army_text(entry.army), _status(float(entry.arrivesAt))]
		var label := PanelUi.cell(text, 0, Color.WHITE, true)
		label.tooltip_text = text
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var recall := PanelUi.button(tr("Отозвать"))
		recall.pressed.connect(_on_recall_pressed.bind(int(entry.index)))
		row.add_child(recall)
		_sent_list.add_child(row)


func _refresh_incoming() -> void:
	PanelUi.clear(_incoming_list)
	var incoming: Array = WorldService.me.get("reinforcementsIn", [])
	var used := 0
	for entry: Dictionary in incoming:
		for unit_id: String in entry.army:
			var unit := Database.get_unit(unit_id)
			used += (unit.housing if unit else 1) * int(entry.army[unit_id])
	_capacity_label.text = tr("Мест для подкреплений: %d / %d (половина мест армии замка)") % [used, int(WorldService.me.get("reinforcementCapacity", 0))]
	if incoming.is_empty():
		_incoming_list.add_child(PanelUi.hint(tr("Союзники пока не присылали войска.")))
	for entry: Dictionary in incoming:
		var text := "← %s: %s · %s" % [entry.fromName, PanelUi.army_text(entry.army), _status(float(entry.arrivesAt))]
		var label := PanelUi.cell(text, 0, Color.WHITE, true)
		label.tooltip_text = text
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_incoming_list.add_child(label)


func _status(arrives_at: float) -> String:
	var left := WorldService.time_until(arrives_at)
	return tr("в пути %s") % UiFormat.duration(left) if left > 0.0 else tr("на месте")


func _on_send_pressed() -> void:
	if _ally_select.selected < 0 or _ally_select.selected >= _ally_ids.size():
		return
	var units := {}
	for unit_id: String in _spins:
		var count := int((_spins[unit_id] as SpinBox).value)
		if count > 0:
			units[unit_id] = count
	if units.is_empty():
		result.emit(tr("Выберите, сколько солдат отправить"), false)
		return
	var response := await WorldService.guild_reinforce(_ally_ids[_ally_select.selected], units)
	if response.ok:
		for spin: SpinBox in _spins.values():
			spin.value = 0
		# Солдаты ушли из замка — обновим армию замка.
		WorldService.refresh_me()
	result.emit(tr("Подкрепления в пути") if response.ok else str(response.error), response.ok)


func _on_recall_pressed(index: int) -> void:
	var response := await WorldService.guild_recall_reinforcement(index)
	result.emit(tr("Подкрепления вернулись в замок") if response.ok else str(response.error), response.ok)
