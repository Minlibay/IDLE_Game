class_name GuildBossPage
extends HBoxContainer
## Вкладка «Босс»: босс недели с общим запасом здоровья. У каждого участника несколько атак в сутки;
## урон — сила армии замка и героя (солдаты не гибнут). Убили — награда всем, кто сражался.

signal result(text: String, ok: bool)

const PORTRAIT_SIZE := 118.0

var _portrait: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _info_label: Label
var _attack_button: Button
var _attacks_label: Label
var _damage_label: Label
var _table: VBoxContainer
var _portrait_tween: Tween


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var left := PanelUi.section(self, tr("Босс недели"), 560)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	left.add_child(body)
	var portrait_box := Control.new()
	portrait_box.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait = TextureRect.new()
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.pivot_offset = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE) * 0.5
	portrait_box.add_child(_portrait)
	_damage_label = Label.new()
	_damage_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.add_theme_font_size_override("font_size", 20)
	_damage_label.add_theme_color_override("font_color", PanelUi.COLOR_GOLD)
	_damage_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_damage_label.add_theme_constant_override("outline_size", 6)
	_damage_label.modulate.a = 0.0
	portrait_box.add_child(_damage_label)
	body.add_child(portrait_box)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(_name_label)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(0, 20)
	_hp_bar = ProgressBar.new()
	_hp_bar.theme_type_variation = &"BarHealth"
	_hp_bar.show_percentage = false
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_box.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 4)
	bar_box.add_child(_hp_label)
	info.add_child(bar_box)
	_info_label = PanelUi.hint("", 12)
	info.add_child(_info_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	var attack_row := HBoxContainer.new()
	attack_row.add_theme_constant_override("separation", 8)
	_attack_button = PanelUi.button(tr("Атаковать"), &"ButtonRed")
	_attack_button.custom_minimum_size = Vector2(150, 34)
	_attack_button.pressed.connect(_on_attack_pressed)
	attack_row.add_child(_attack_button)
	_attacks_label = PanelUi.hint("", 12)
	_attacks_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack_row.add_child(_attacks_label)
	info.add_child(attack_row)
	body.add_child(info)

	var right := PanelUi.section(self, tr("Урон участников"), 0)
	_table = PanelUi.scroll_list(right)


func refresh() -> void:
	var boss: Dictionary = WorldService.guild.get("boss", {})
	if boss.is_empty():
		return
	var level := int(boss.level)
	var monster := boss_monster(level)
	if monster:
		var frames := monster.sprite_frames
		_portrait.texture = frames.get_frame_texture(Actor.ANIM_IDLE, 0) if frames and frames.has_animation(Actor.ANIM_IDLE) else monster.sprite
		_portrait.modulate = monster.tint if boss.killedAt == null else Color(0.4, 0.4, 0.45)
	_name_label.text = tr("%s · %d уровень") % [monster.display_name if monster else tr("Босс"), level]
	_hp_bar.max_value = maxf(1.0, float(boss.maxHp))
	_hp_bar.value = float(boss.hp)
	_hp_label.text = "%d / %d" % [int(boss.hp), int(boss.maxHp)]
	var killed: bool = boss.killedAt != null
	var lines := PackedStringArray()
	if killed:
		lines.append(tr("Повержен! Следующий босс (сильнее) придёт через %s.") % UiFormat.duration(WorldService.time_until(float(boss.endsAt))))
	else:
		lines.append(tr("Уйдёт через %s. Здоровье общее — бейте всей гильдией.") % UiFormat.duration(WorldService.time_until(float(boss.endsAt))))
	lines.append(tr("Награда за победу: %d золота в казну каждому, кто сражался, и опыт гильдии.") % int(boss.goldReward))
	lines.append(tr("Урон — сила армии замка и героя; солдаты не гибнут."))
	_info_label.text = "\n".join(lines)
	var left := int(boss.attacksLeft)
	_attack_button.disabled = killed or left <= 0
	_attack_button.text = tr("Атаковать (%d/%d)") % [left, int(boss.attacksPerDay)]
	_attacks_label.text = tr("Новые атаки через %s") % UiFormat.duration(WorldService.time_until(float(boss.attacksResetAt))) if left < int(boss.attacksPerDay) else ""

	PanelUi.clear(_table)
	var damage: Array = boss.damage
	if damage.is_empty():
		_table.add_child(PanelUi.hint(tr("Никто ещё не сражался с боссом на этой неделе.")))
	var total := 0.0
	for entry: Dictionary in damage:
		total += float(entry.damage)
	for index in damage.size():
		var entry: Dictionary = damage[index]
		var row := HBoxContainer.new()
		var mine := int(entry.playerId) == WorldService.my_id()
		var color := PanelUi.COLOR_GOLD if mine else Color.WHITE
		row.add_child(PanelUi.cell("%d." % (index + 1), 26, PanelUi.COLOR_HINT))
		row.add_child(PanelUi.cell(str(entry.name), 0, color, true))
		row.add_child(PanelUi.cell(str(int(entry.damage)), 70, color))
		row.add_child(PanelUi.cell("%d%%" % roundi(100.0 * float(entry.damage) / maxf(1.0, total)), 44, PanelUi.COLOR_HINT))
		_table.add_child(row)


## Босс недели выглядит как один из боссов волн (по кругу по уровню).
static func boss_monster(level: int) -> MonsterData:
	var bosses: Array[MonsterData] = []
	for monster in Database.monsters:
		if monster.is_boss:
			bosses.append(monster)
	if bosses.is_empty():
		return null
	bosses.sort_custom(func(a: MonsterData, b: MonsterData) -> bool: return a.min_wave < b.min_wave)
	return bosses[(level - 1) % bosses.size()]


func _on_attack_pressed() -> void:
	_attack_button.disabled = true
	var response := await WorldService.guild_attack_boss()
	if not response.ok:
		result.emit(str(response.error), false)
		refresh()
		return
	var attack: Dictionary = response.data.attack
	_play_hit(int(attack.damage))
	if attack.killed:
		result.emit(tr("Босс повержен! Награда уже в казне."), true)
	else:
		result.emit(tr("Удар на %d урона") % int(attack.damage), true)


func _play_hit(damage: int) -> void:
	_damage_label.text = "-%d" % damage
	if _portrait_tween:
		_portrait_tween.kill()
	_portrait_tween = create_tween().set_parallel()
	_damage_label.position.y = 0.0
	_damage_label.modulate.a = 1.0
	_portrait_tween.tween_property(_damage_label, "position:y", -24.0, 0.9)
	_portrait_tween.tween_property(_damage_label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	_portrait.scale = Vector2.ONE * 0.9
	_portrait_tween.tween_property(_portrait, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_portrait.self_modulate = Color(2.2, 1.4, 1.4)
	_portrait_tween.tween_property(_portrait, "self_modulate", Color.WHITE, 0.3)
