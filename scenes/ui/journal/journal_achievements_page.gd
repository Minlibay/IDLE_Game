class_name JournalAchievementsPage
extends VBoxContainer
## Вкладка «Достижения»: у каждого несколько уровней; за уровень — души. Позже — Steam Achievements
## (id уровня: "<id>_<номер>").

signal result(text: String, ok: bool)

var _grid: GridContainer


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := PanelUi.section(self, tr("Достижения"), 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	box.add_child(scroll)


func refresh() -> void:
	PanelUi.clear(_grid)
	var progress := GameState.progress
	for achievement: Dictionary in HeroProgress.ACHIEVEMENTS:
		_grid.add_child(_make_card(achievement, progress))


func _make_card(achievement: Dictionary, progress: HeroProgress) -> Control:
	var tiers: Array = achievement.tiers
	var tier := progress.achievement_tier(achievement)
	var claimed := int(progress.achievements_claimed.get(achievement.id, 0))
	var value := progress.achievement_value(achievement)
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	var stars := ""
	for i in tiers.size():
		stars += "★" if i < tier else "☆"
	head.add_child(PanelUi.cell(tr(str(achievement.name)), 0, PanelUi.COLOR_GOLD if tier >= tiers.size() else Color.WHITE, true, 13))
	head.add_child(PanelUi.cell(stars, 60, PanelUi.COLOR_GOLD, false, 12))
	card.add_child(head)
	var next := mini(tier, tiers.size() - 1)
	var desc := tr(str(achievement.desc))
	if desc.contains("%s"):
		desc = desc % _format_big(int(tiers[next]))
	var row := HBoxContainer.new()
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"BarBuild"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = float(tiers[next])
	bar.value = minf(float(value), float(tiers[next]))
	bar.tooltip_text = "%s / %s" % [_format_big(value), _format_big(int(tiers[next]))]
	var label := PanelUi.cell(desc, 0, PanelUi.COLOR_HINT, true, 11)
	card.add_child(label)
	row.add_child(bar)
	if claimed < tier:
		var claim := PanelUi.button("+" + UiFormat.souls(int(achievement.souls[claimed])), &"ButtonGreen")
		claim.custom_minimum_size = Vector2(80, 22)
		claim.pressed.connect(_on_claim_pressed.bind(str(achievement.id)))
		row.add_child(claim)
	else:
		row.add_child(PanelUi.cell(tr("✔ всё") if tier >= tiers.size() else tr("награда: %s") % UiFormat.souls(int(achievement.souls[tier])), 100, PanelUi.COLOR_HINT, false, 11))
	card.add_child(row)
	return card


## 1500 -> «1 500», 2000000 -> «2 000 000».
static func _format_big(value: int) -> String:
	var text := str(value)
	var result := ""
	while text.length() > 3:
		result = " " + text.substr(text.length() - 3) + result
		text = text.substr(0, text.length() - 3)
	return text + result


func _on_claim_pressed(achievement_id: String) -> void:
	var souls := GameState.progress.claim_achievement(achievement_id)
	GameState.save_game()
	result.emit(tr("Получено душ: %d") % souls if souls > 0 else tr("Нечего забирать"), souls > 0)
