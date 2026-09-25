class_name GuildPanel
extends PanelContainer
## Окно гильдии [G]. Без гильдии — создание гильдии и полученные приглашения;
## в гильдии — участники, чат и управление (приглашения, взносы, выход).
## Всё решает сервер (server/src/world/guilds.ts): окно показывает состояние и отправляет запросы.

const REFRESH_INTERVAL := 3.0
## Опасные действия (исключить, передать главенство, выйти, распустить) — вторым нажатием за это время.
const CONFIRM_TIME := 3.0
## Игрок считается «в сети», если заходил не раньше, чем столько секунд назад.
const ONLINE_SECONDS := 120.0
const COLOR_OK := Color(0.55, 0.9, 0.5)
const COLOR_BAD := Color(1.0, 0.5, 0.45)
const COLOR_HINT := Color(0.7, 0.7, 0.78)
const COLOR_SYSTEM := "#9aa0b8"
const COLOR_TIME := "#6f7590"
const COLOR_NAME := "#ffd978"
const ROLE_NAMES := {"leader": "Глава", "officer": "Офицер", "member": "Участник"}
const ROLE_MARKS := {"leader": "★", "officer": "◆", "member": "·"}
const BANNER_ICON := preload("res://assets/ui/icons/banner.png")
const GOLD_ICON := preload("res://assets/ui/icons/gold.png")
## Как на сервере (config.ts): длины названия, тега и сообщения.
const NAME_MAX_LENGTH := 24
const TAG_MAX_LENGTH := 4
const CHAT_MAX_LENGTH := 200
## Цвета гильдий — те же, что принимает сервер (config.ts guildColors).
const GUILD_COLORS := ["#e05a4f", "#f0a038", "#e8d44d", "#6cc75a", "#3fbfb0", "#4a90e2", "#8f6ae0", "#d65fb5", "#c8c8d0", "#8b6a4a"]

@onready var close_button: Button = %CloseButton
@onready var title_label: Label = %Title
@onready var level_label: Label = %LevelLabel
@onready var xp_bar: ProgressBar = %XpBar
@onready var info_label: Label = %InfoLabel
@onready var result_label: Label = %ResultLabel
@onready var body: Control = %Body

var _refresh_timer := 0.0
var _selected_member := -1
var _armed := ""
var _armed_timer := 0.0
var _color: String = GUILD_COLORS[0]
var _built := false

# Без гильдии.
var _no_guild: HBoxContainer
var _name_edit: LineEdit
var _tag_edit: LineEdit
var _color_buttons: Array[Button] = []
var _create_button: Button
var _cost_label: Label
var _invites_list: VBoxContainer
# В гильдии.
var _in_guild: HBoxContainer
var _members_list: VBoxContainer
var _role_button: Button
var _transfer_button: Button
var _kick_button: Button
var _chat_log: RichTextLabel
var _chat_edit: LineEdit
var _send_button: Button
var _invite_edit: LineEdit
var _invite_button: Button
var _pending_list: VBoxContainer
var _donate_spin: SpinBox
var _donate_button: Button
var _treasury_label: Label
var _leave_button: Button
var _offline_label: Label


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)
	_build_no_guild()
	_build_in_guild()
	_offline_label = Label.new()
	_offline_label.text = "Нет связи с сервером карты — гильдии работают только онлайн."
	_offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_offline_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_offline_label.add_theme_color_override("font_color", COLOR_HINT)
	body.add_child(_offline_label)
	_built = true
	WorldService.me_updated.connect(_refresh)
	WorldService.guild_updated.connect(_refresh)


func _exit_tree() -> void:
	if visible:
		DesktopWindow.pop_modal()


func _process(delta: float) -> void:
	if not visible:
		return
	if _armed != "":
		_armed_timer -= delta
		if _armed_timer <= 0.0:
			_armed = ""
			_refresh()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		if WorldService.is_logged_in():
			WorldService.refresh_guild()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


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
	result_label.text = ""
	_refresh_timer = 0.0
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()


# --- Обновление --------------------------------------------------------------------

func _refresh() -> void:
	if not _built or not visible:
		return
	var online := WorldService.is_logged_in()
	var summary := WorldService.my_guild()
	var in_guild := online and not summary.is_empty()
	_offline_label.visible = not online
	_no_guild.visible = online and summary.is_empty()
	_in_guild.visible = in_guild
	level_label.visible = in_guild
	xp_bar.visible = in_guild
	if in_guild:
		_refresh_header(summary)
		_refresh_members()
		_refresh_chat()
		_refresh_manage()
		if not WorldService.guild.is_empty():
			WorldService.mark_guild_chat_read()
	else:
		title_label.text = tr("Гильдия")
		title_label.remove_theme_color_override("font_color")
		info_label.text = ""
		if online:
			_refresh_no_guild()


func _refresh_header(summary: Dictionary) -> void:
	title_label.text = WorldService.tagged_name(str(summary.name), summary.tag)
	title_label.add_theme_color_override("font_color", Color(str(summary.color)))
	var view := WorldService.guild
	level_label.text = tr("Ур. %d") % int(summary.level)
	if not view.is_empty():
		var next: Variant = view.get("nextLevelXp")
		level_label.text = (tr("Ур. %d · опыт %d / %d") % [int(summary.level), int(view.xp), int(next)]) if next != null 			else tr("Ур. %d · максимум") % int(summary.level)
		var from := float(view.levelXp)
		xp_bar.max_value = maxf(1.0, (float(next) if next != null else float(view.xp)) - from)
		xp_bar.value = float(view.xp) - from if next != null else xp_bar.max_value
		xp_bar.tooltip_text = (tr("Опыт гильдии: %d / %d\nОпыт дают взносы золотом (1 золото = 1 опыт) и победы участников на карте.")
			% [int(view.xp), int(next)]) if next != null else tr("Максимальный уровень гильдии")
	info_label.text = tr("Участники: %d / %d · бонус: +%d%% к силе армии") % [int(summary.members), int(summary.slots), int(summary.bonus)]
	info_label.tooltip_text = tr("+%d%% к силе армии за каждого участника, но не больше %d%% (потолок растёт с уровнем гильдии).") % [
		1, int(WorldService.guild.get("bonusCap", summary.bonus))]


func _refresh_no_guild() -> void:
	var gold := GameState.kingdom.get_resource("gold")
	_cost_label.text = tr("Цена: 1000 золота из казны замка (в казне: %d)") % roundi(gold)
	_create_button.disabled = gold < 1000.0
	for child in _invites_list.get_children():
		child.queue_free()
	var invites := WorldService.guild_invites()
	if invites.is_empty():
		var empty := Label.new()
		empty.text = tr("Приглашений пока нет. Глава или офицер гильдии может пригласить вас по имени: %s") % str(WorldService.me.get("name", ""))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", COLOR_HINT)
		empty.add_theme_font_size_override("font_size", 12)
		_invites_list.add_child(empty)
		return
	for invite: Dictionary in invites:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = Color(str(invite.color))
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = tr("%s · ур. %d · %d/%d · пригласил %s") % [
			WorldService.tagged_name(str(invite.name), invite.tag), int(invite.level), int(invite.members), int(invite.slots), str(invite.invitedBy)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.tooltip_text = tr("Приглашение действует ещё %s") % UiFormat.duration(WorldService.time_until(float(invite.expiresAt)))
		row.add_child(label)
		var accept := _make_button(tr("Вступить"), &"ButtonGreen")
		accept.pressed.connect(_run.bind(WorldService.guild_accept.bind(int(invite.guildId)), tr("Вы вступили в гильдию")))
		row.add_child(accept)
		var decline := _make_button(tr("Отказаться"), &"ButtonRed")
		decline.pressed.connect(_run.bind(WorldService.guild_decline.bind(int(invite.guildId)), tr("Приглашение отклонено")))
		row.add_child(decline)
		_invites_list.add_child(row)


func _refresh_members() -> void:
	for child in _members_list.get_children():
		child.queue_free()
	var view := WorldService.guild
	if view.is_empty():
		return
	var group := ButtonGroup.new()
	group.allow_unpress = true
	var now := WorldService.server_now_ms()
	var found := false
	for member: Dictionary in view.members:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 22)
		button.button_pressed = int(member.playerId) == _selected_member
		found = found or button.button_pressed
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var me := int(member.playerId) == WorldService.my_id()
		row.add_child(_cell("%s %s" % [ROLE_MARKS[member.role], member.name], 0, Color(COLOR_NAME) if me else Color.WHITE, true))
		row.add_child(_cell(tr("ур. %d") % int(member.heroLevel), 52))
		row.add_child(_cell(tr(ROLE_NAMES[member.role]), 70))
		row.add_child(_cell(str(int(member.contribution)), 60))
		row.add_child(_cell(_seen_text(now - float(member.lastSeen)), 86, COLOR_OK if now - float(member.lastSeen) < ONLINE_SECONDS * 1000.0 else COLOR_HINT))
		button.add_child(row)
		button.tooltip_text = tr("Вклад в опыт гильдии: %d\nВ гильдии с: %s") % [int(member.contribution), _date_text(float(member.joinedAt))]
		button.toggled.connect(_on_member_toggled.bind(int(member.playerId)))
		_members_list.add_child(button)
	if not found:
		_selected_member = -1
	_refresh_member_actions()


func _refresh_member_actions() -> void:
	var role := WorldService.guild_role()
	var target := _member(_selected_member)
	var selected := not target.is_empty() and _selected_member != WorldService.my_id()
	var target_role := str(target.get("role", ""))
	_role_button.visible = role == "leader"
	_transfer_button.visible = role == "leader"
	_kick_button.visible = role in ["leader", "officer"]
	_role_button.disabled = not selected
	_role_button.text = tr("Снять офицера") if target_role == "officer" else tr("Сделать офицером")
	_transfer_button.disabled = not selected
	_transfer_button.text = tr("Точно?") if _armed == "transfer" else tr("Передать главенство")
	_kick_button.disabled = not selected or target_role == "leader" or (role == "officer" and target_role == "officer")
	_kick_button.text = tr("Точно?") if _armed == "kick" else tr("Исключить")


func _refresh_chat() -> void:
	var lines := PackedStringArray()
	for message: Dictionary in WorldService.guild_chat:
		var time := "[color=%s]%s[/color]" % [COLOR_TIME, _time_text(float(message.at))]
		var text := _escape(WorldService.guild_message_text(message))
		if message.get("system", false):
			lines.append("%s [color=%s][i]%s[/i][/color]" % [time, COLOR_SYSTEM, text])
		else:
			lines.append("%s [color=%s]%s:[/color] %s" % [time, COLOR_NAME, _escape(str(message.name)), text])
	var bbcode := "\n".join(lines)
	if _chat_log.text != bbcode:
		_chat_log.text = bbcode


func _refresh_manage() -> void:
	var can_manage := WorldService.can_manage_guild()
	_invite_edit.editable = can_manage
	_invite_button.disabled = not can_manage
	_invite_edit.placeholder_text = tr("Имя игрока") if can_manage else tr("Приглашают глава и офицеры")
	for child in _pending_list.get_children():
		child.queue_free()
	for invite: Dictionary in WorldService.guild.get("invites", []):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = tr("%s — ждём ответа (%s)") % [invite.name, UiFormat.duration(WorldService.time_until(float(invite.expiresAt)))]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", COLOR_HINT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		if can_manage:
			var cancel := Button.new()
			cancel.theme_type_variation = &"CloseButton"
			cancel.custom_minimum_size = Vector2(18, 17)
			cancel.tooltip_text = tr("Отменить приглашение")
			cancel.pressed.connect(_run.bind(WorldService.guild_cancel_invite.bind(int(invite.playerId)), tr("Приглашение отменено")))
			row.add_child(cancel)
		_pending_list.add_child(row)
	var gold := roundi(GameState.kingdom.get_resource("gold"))
	_treasury_label.text = tr("В казне замка: %d · 1 золото = 1 опыт") % gold
	_donate_spin.max_value = maxi(1, gold)
	_donate_button.disabled = gold < 1
	var summary := WorldService.my_guild()
	var leader := WorldService.guild_role() == "leader"
	var alone := int(summary.get("members", 1)) <= 1
	if leader and not alone:
		_leave_button.text = tr("Точно?") if _armed == "disband" else tr("Распустить гильдию")
		_leave_button.tooltip_text = tr("Все участники покинут гильдию. Чтобы уйти самому, сначала передайте главенство.")
	else:
		_leave_button.text = tr("Точно?") if _armed == "leave" else (tr("Распустить гильдию") if leader else tr("Покинуть гильдию"))
		_leave_button.tooltip_text = tr("Вступить в другую гильдию можно будет через сутки.") if not leader else ""


# --- Действия ------------------------------------------------------------------------

## Выполняет запрос к серверу и показывает итог.
func _run(request: Callable, success_text: String) -> void:
	var result: Dictionary = await request.call()
	_armed = ""
	if result.ok:
		_show_result(success_text, COLOR_OK)
	else:
		_show_result(str(result.error), COLOR_BAD)
	_refresh()


## Опасное действие: первое нажатие — «Точно?», второе (за CONFIRM_TIME) — выполнить.
func _confirmed(key: String) -> bool:
	if _armed == key:
		return true
	_armed = key
	_armed_timer = CONFIRM_TIME
	_refresh()
	return false


func _on_create_pressed() -> void:
	_run(WorldService.guild_create.bind(_name_edit.text.strip_edges(), _tag_edit.text.strip_edges(), _color), tr("Гильдия основана!"))


func _on_invite_pressed(_text := "") -> void:
	var player_name := _invite_edit.text.strip_edges()
	if player_name == "":
		return
	_invite_edit.text = ""
	_run(WorldService.guild_invite.bind(player_name), tr("Приглашение отправлено: %s") % player_name)


func _on_send_pressed(_text := "") -> void:
	var text := _chat_edit.text.strip_edges()
	if text == "":
		return
	_chat_edit.text = ""
	var result: Dictionary = await WorldService.guild_send_message(text)
	if not result.ok:
		_chat_edit.text = text
		_show_result(str(result.error), COLOR_BAD)


func _on_donate_pressed() -> void:
	var amount := int(_donate_spin.value)
	_run(WorldService.guild_donate.bind(amount), tr("Внесено в гильдию: %d золота") % amount)


func _on_role_pressed() -> void:
	var target := _member(_selected_member)
	if target.is_empty():
		return
	var role := "member" if target.role == "officer" else "officer"
	_run(WorldService.guild_set_role.bind(_selected_member, role), tr("Готово"))


func _on_transfer_pressed() -> void:
	if not _member(_selected_member).is_empty() and _confirmed("transfer"):
		_run(WorldService.guild_transfer.bind(_selected_member), tr("Главенство передано"))


func _on_kick_pressed() -> void:
	if not _member(_selected_member).is_empty() and _confirmed("kick"):
		_run(WorldService.guild_kick.bind(_selected_member), tr("Участник исключён"))


func _on_leave_pressed() -> void:
	var leader := WorldService.guild_role() == "leader"
	var alone := int(WorldService.my_guild().get("members", 1)) <= 1
	if leader and not alone:
		if _confirmed("disband"):
			_run(WorldService.guild_disband, tr("Гильдия распущена"))
	elif _confirmed("leave"):
		_run(WorldService.guild_leave, tr("Вы покинули гильдию"))


func _on_member_toggled(pressed: bool, player_id: int) -> void:
	if pressed:
		_selected_member = player_id
	elif _selected_member == player_id:
		_selected_member = -1
	_armed = ""
	_refresh_member_actions()


func _on_color_pressed(color: String) -> void:
	_color = color
	for button in _color_buttons:
		button.button_pressed = button.get_meta(&"color") == color


# --- Построение ------------------------------------------------------------------------

func _build_no_guild() -> void:
	_no_guild = HBoxContainer.new()
	_no_guild.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_guild.add_theme_constant_override("separation", 8)
	body.add_child(_no_guild)

	var create := _section(_no_guild, tr("Основать гильдию"), 460)
	_name_edit = _labeled_edit(create, tr("Название"), tr("от 3 до 24 символов"), NAME_MAX_LENGTH)
	_tag_edit = _labeled_edit(create, tr("Тег"), tr("2–4 буквы или цифры"), TAG_MAX_LENGTH)
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 4)
	var colors_label := Label.new()
	colors_label.text = tr("Цвет")
	colors_label.custom_minimum_size = Vector2(80, 0)
	colors.add_child(colors_label)
	for color: String in GUILD_COLORS:
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.custom_minimum_size = Vector2(24, 22)
		swatch.set_meta(&"color", color)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(color)
			var selected := state in ["pressed", "hover_pressed"]
			style.set_border_width_all(2 if selected else 1)
			style.border_color = Color.WHITE if selected else Color(0, 0, 0, 0.6)
			swatch.add_theme_stylebox_override(state, style)
		swatch.button_pressed = color == _color
		swatch.pressed.connect(_on_color_pressed.bind(color))
		colors.add_child(swatch)
		_color_buttons.append(swatch)
	create.add_child(colors)
	var hint := Label.new()
	hint.text = tr("Тег и цвет видны на карте: [ТЕГ] Имя. Союзники не нападают друг на друга.")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COLOR_HINT)
	create.add_child(hint)
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_cost_label = Label.new()
	_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost_label.add_theme_font_size_override("font_size", 12)
	bottom.add_child(UiStyles.make_icon(GOLD_ICON, 18))
	bottom.add_child(_cost_label)
	_create_button = _make_button(tr("Основать"), &"ButtonGreen")
	_create_button.custom_minimum_size = Vector2(120, 30)
	_create_button.pressed.connect(_on_create_pressed)
	bottom.add_child(_create_button)
	create.add_child(bottom)

	var invites := _section(_no_guild, tr("Приглашения"), 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_invites_list = VBoxContainer.new()
	_invites_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_invites_list)
	invites.add_child(scroll)


func _build_in_guild() -> void:
	_in_guild = HBoxContainer.new()
	_in_guild.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_in_guild.add_theme_constant_override("separation", 8)
	body.add_child(_in_guild)

	# Участники.
	var members := _section(_in_guild, tr("Участники"), 420)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	var header_row := MarginContainer.new()
	header_row.add_theme_constant_override("margin_left", 6)
	header_row.add_theme_constant_override("margin_right", 6)
	header.add_child(_cell(tr("Имя"), 0, COLOR_HINT, true))
	header.add_child(_cell(tr("Герой"), 52, COLOR_HINT))
	header.add_child(_cell(tr("Роль"), 70, COLOR_HINT))
	header.add_child(_cell(tr("Вклад"), 60, COLOR_HINT))
	header.add_child(_cell(tr("Заходил"), 86, COLOR_HINT))
	header_row.add_child(header)
	members.add_child(header_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_members_list = VBoxContainer.new()
	_members_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_members_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_members_list)
	members.add_child(scroll)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	_role_button = _make_button(tr("Сделать офицером"), &"")
	_role_button.pressed.connect(_on_role_pressed)
	_transfer_button = _make_button(tr("Передать главенство"), &"ButtonBlue")
	_transfer_button.pressed.connect(_on_transfer_pressed)
	_kick_button = _make_button(tr("Исключить"), &"ButtonRed")
	_kick_button.pressed.connect(_on_kick_pressed)
	for button in [_role_button, _transfer_button, _kick_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	members.add_child(actions)

	# Чат.
	var chat := _section(_in_guild, tr("Чат гильдии"), 0)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.selection_enabled = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	_chat_log.add_theme_font_size_override("italics_font_size", 12)
	# Сообщения игроков не переводим.
	_chat_log.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chat.add_child(_chat_log)
	var input := HBoxContainer.new()
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = tr("Сообщение…")
	_chat_edit.max_length = CHAT_MAX_LENGTH
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.text_submitted.connect(_on_send_pressed)
	input.add_child(_chat_edit)
	_send_button = _make_button(tr("Отправить"), &"ButtonBlue")
	_send_button.pressed.connect(_on_send_pressed)
	input.add_child(_send_button)
	chat.add_child(input)

	# Управление.
	var manage := _section(_in_guild, tr("Управление"), 270)
	var invite_row := HBoxContainer.new()
	_invite_edit = LineEdit.new()
	_invite_edit.max_length = 20
	_invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_edit.text_submitted.connect(_on_invite_pressed)
	invite_row.add_child(_invite_edit)
	_invite_button = _make_button(tr("Пригласить"), &"ButtonGreen")
	_invite_button.pressed.connect(_on_invite_pressed)
	invite_row.add_child(_invite_button)
	manage.add_child(invite_row)
	_pending_list = VBoxContainer.new()
	_pending_list.add_theme_constant_override("separation", 0)
	manage.add_child(_pending_list)
	var donate_row := HBoxContainer.new()
	donate_row.add_child(UiStyles.make_icon(GOLD_ICON, 18))
	_donate_spin = SpinBox.new()
	_donate_spin.min_value = 1
	_donate_spin.step = 1
	_donate_spin.value = 100
	_donate_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donate_row.add_child(_donate_spin)
	_donate_button = _make_button(tr("Внести"), &"")
	_donate_button.tooltip_text = tr("Золото из казны замка становится опытом гильдии; ваш вклад виден в списке участников.")
	_donate_button.pressed.connect(_on_donate_pressed)
	donate_row.add_child(_donate_button)
	manage.add_child(donate_row)
	_treasury_label = Label.new()
	_treasury_label.add_theme_font_size_override("font_size", 11)
	_treasury_label.add_theme_color_override("font_color", COLOR_HINT)
	manage.add_child(_treasury_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	manage.add_child(spacer)
	_leave_button = _make_button(tr("Покинуть гильдию"), &"ButtonRed")
	_leave_button.pressed.connect(_on_leave_pressed)
	manage.add_child(_leave_button)


## Раздел окна: рамка + заголовок; возвращает контейнер для содержимого.
func _section(parent: Container, title: String, min_width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelSection"
	panel.custom_minimum_size = Vector2(min_width, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if min_width <= 0.0 else Control.SIZE_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiStyles.make_section_title(title))
	panel.add_child(box)
	parent.add_child(panel)
	return box


func _labeled_edit(parent: Container, title: String, placeholder: String, max_length: int) -> LineEdit:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	parent.add_child(row)
	return edit


func _make_button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 26)
	return button


func _cell(text: String, width: float, color := Color.WHITE, expand := false) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Имена игроков переводить не нужно, а подписи уже переведены при создании.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


func _member(player_id: int) -> Dictionary:
	for member: Dictionary in WorldService.guild.get("members", []):
		if int(member.playerId) == player_id:
			return member
	return {}


func _show_result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.add_theme_color_override("font_color", color)


func _seen_text(ago_ms: float) -> String:
	if ago_ms < ONLINE_SECONDS * 1000.0:
		return tr("в сети")
	return UiFormat.duration(ago_ms / 1000.0) + tr(" назад")


func _time_text(server_ms: float) -> String:
	var local := _local_unix(server_ms)
	var time := Time.get_time_dict_from_unix_time(local)
	return "%02d:%02d" % [time.hour, time.minute]


func _date_text(server_ms: float) -> String:
	var date := Time.get_date_dict_from_unix_time(_local_unix(server_ms))
	return "%02d.%02d.%d" % [date.day, date.month, date.year]


## Время сервера (мс UTC) → секунды в часовом поясе игрока.
func _local_unix(server_ms: float) -> int:
	return int(server_ms / 1000.0) + int(Time.get_time_zone_from_system().bias) * 60


## Текст игроков в BBCode: квадратные скобки не должны превращаться в теги.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
