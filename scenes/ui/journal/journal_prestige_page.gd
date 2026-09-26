class_name JournalPrestigePage
extends HBoxContainer
## Вкладка «Перерождение»: новая жизнь героя за души и вечные улучшения за них.

signal result(text: String, ok: bool)

const CONFIRM_TIME := 3.0

var _souls_label: Label
var _info_label: Label
var _prestige_button: Button
var _upgrades: VBoxContainer
var _armed_until := 0.0


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var left := PanelUi.section(self, tr("Перерождение"), 440)
	_souls_label = Label.new()
	_souls_label.add_theme_font_size_override("font_size", 18)
	_souls_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	left.add_child(_souls_label)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 12)
	left.add_child(_info_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(PanelUi.hint(tr("Сбрасываются волна, уровень и таланты (очки возвращаются). Остаются снаряжение, сокровища, золото, замок, армия и гильдия.")))
	_prestige_button = PanelUi.button(tr("Переродиться"), &"ButtonRed")
	_prestige_button.custom_minimum_size = Vector2(0, 34)
	_prestige_button.pressed.connect(_on_prestige_pressed)
	left.add_child(_prestige_button)

	var right := PanelUi.section(self, tr("Вечные улучшения за души"), 0)
	_upgrades = VBoxContainer.new()
	_upgrades.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrades.add_theme_constant_override("separation", 2)
	right.add_child(_upgrades)


func refresh() -> void:
	var progress := GameState.progress
	_souls_label.text = tr("Души: %d") % progress.souls
	var gain := HeroProgress.souls_for(progress.run_best_wave)
	var lines := PackedStringArray()
	lines.append(tr("Перерождений: %d · рекорд волны в этой жизни: %d") % [progress.prestige_count, progress.run_best_wave])
	if progress.can_prestige():
		lines.append(tr("Перерождение сейчас даст %s. Чем дальше зайти, тем больше: на 50-й волне — %d, на 100-й — %d.") % [
			UiFormat.souls(gain), HeroProgress.souls_for(50), HeroProgress.souls_for(100)])
	else:
		lines.append(tr("Доступно с %d-й волны. Души растут с рекордом волны: на 30-й — %d, на 50-й — %d.") % [
			HeroProgress.PRESTIGE_MIN_WAVE, HeroProgress.souls_for(30), HeroProgress.souls_for(50)])
	if progress.start_wave() > 1:
		lines.append(tr("Новая жизнь начнётся с %d-й волны («Стартовый рывок»).") % progress.start_wave())
	_info_label.text = "\n".join(lines)
	var armed := Time.get_ticks_msec() / 1000.0 < _armed_until
	_prestige_button.disabled = not progress.can_prestige()
	_prestige_button.text = tr("Точно? Получить %s") % UiFormat.souls(gain) if armed else (tr("Переродиться (+%s)") % UiFormat.souls(gain) if progress.can_prestige() else tr("Переродиться"))

	PanelUi.clear(_upgrades)
	for upgrade: Dictionary in HeroProgress.SOUL_UPGRADES:
		_upgrades.add_child(_make_upgrade_row(upgrade, progress))


func _make_upgrade_row(upgrade: Dictionary, progress: HeroProgress) -> Control:
	var rank := progress.get_upgrade_rank(str(upgrade.id))
	var max_rank := int(upgrade.max_rank)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon_path: String = GuildCatalog.ICONS.get(str(upgrade.stat), "res://assets/ui/icons/battle.png")
	if upgrade.stat == "ATTACK_SPEED":
		icon_path = "res://assets/sprites/talents/attack_speed.png"
	row.add_child(UiStyles.make_icon(load(icon_path), 24))
	row.add_child(PanelUi.cell("%s · %d/%d" % [tr(str(upgrade.name)), rank, max_rank], 230, Color.WHITE, false, 12))
	var effect: String
	if upgrade.id == "head_start":
		effect = tr("начало с %d-й волны") % progress.start_wave()
	else:
		effect = tr("+%s%% (сейчас +%s%%)") % [StatModifier.format_number(float(upgrade.per_rank)), StatModifier.format_number(float(upgrade.per_rank) * rank)]
		effect += " " + tr(_stat_label(str(upgrade.stat)))
	row.add_child(PanelUi.cell(effect, 0, PanelUi.COLOR_OK if rank > 0 else PanelUi.COLOR_HINT, true, 11))
	var buy := PanelUi.button("", &"ButtonGreen")
	buy.custom_minimum_size = Vector2(110, 24)
	if rank >= max_rank:
		buy.text = tr("Максимум")
		buy.disabled = true
	else:
		buy.text = UiFormat.souls(HeroProgress.upgrade_cost(upgrade, rank))
		buy.disabled = not progress.can_buy_upgrade(upgrade)
	buy.pressed.connect(_on_buy_pressed.bind(str(upgrade.id)))
	row.add_child(buy)
	return row


static func _stat_label(stat: String) -> String:
	match stat:
		"DAMAGE": return "урона"
		"MAX_HP": return "здоровья"
		"GOLD_FIND": return "золота"
		"XP_GAIN": return "опыта"
		"ATTACK_SPEED": return "скорости атаки"
		"DROP_CHANCE": return "шанса дропа"
	return ""


func _on_buy_pressed(upgrade_id: String) -> void:
	var ok := GameState.buy_soul_upgrade(upgrade_id)
	result.emit(tr("Улучшение куплено") if ok else tr("Не хватает душ"), ok)


func _on_prestige_pressed() -> void:
	if Time.get_ticks_msec() / 1000.0 >= _armed_until:
		_armed_until = Time.get_ticks_msec() / 1000.0 + CONFIRM_TIME
		refresh()
		get_tree().create_timer(CONFIRM_TIME).timeout.connect(func() -> void: if is_inside_tree(): refresh())
		return
	_armed_until = 0.0
	var gained := GameState.prestige()
	if gained <= 0:
		result.emit(tr("Перерождение пока недоступно"), false)
