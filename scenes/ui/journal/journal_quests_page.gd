class_name JournalQuestsPage
extends VBoxContainer
## Вкладка «Задания»: 5 заданий дня; за каждое — золото и душа. Новые задания — в полночь.

signal result(text: String, ok: bool)

const GOLD_ICON := preload("res://assets/ui/icons/gold.png")

var _list: VBoxContainer
var _footer: Label


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := PanelUi.section(self, tr("Задания дня"), 0)
	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)
	_footer = PanelUi.hint("", 11)
	box.add_child(_footer)


func refresh() -> void:
	var progress := GameState.progress
	progress.ensure_daily()
	PanelUi.clear(_list)
	var quests: Array = progress.daily.quests
	for index in quests.size():
		_list.add_child(_make_row(quests[index], index))
	var now := Time.get_datetime_dict_from_system()
	var left := (23 - int(now.hour)) * 3600 + (59 - int(now.minute)) * 60 + (60 - int(now.second))
	_footer.text = tr("Новые задания через %s. Награда за каждое: золото и 1 душа (души — валюта перерождения).") % UiFormat.duration(left)


func _make_row(quest: Dictionary, index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var done := int(quest.progress) >= int(quest.target)
	var text := PanelUi.cell(GameState.progress.quest_text(quest), 330, PanelUi.COLOR_HINT if quest.claimed else Color.WHITE, false, 13)
	row.add_child(text)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(260, 18)
	bar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"BarBuild"
	bar.show_percentage = false
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.max_value = float(quest.target)
	bar.value = float(quest.progress)
	bar_box.add_child(bar)
	var bar_label := PanelUi.cell("%d / %d" % [int(quest.progress), int(quest.target)], 0, Color.WHITE, true, 11)
	bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_box.add_child(bar_label)
	row.add_child(bar_box)
	row.add_child(UiStyles.make_icon(GOLD_ICON, 18))
	row.add_child(PanelUi.cell("%d + %s" % [int(quest.gold), UiFormat.souls(int(quest.souls))], 140, PanelUi.COLOR_GOLD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if quest.claimed:
		row.add_child(PanelUi.cell(tr("✔ Получено"), 110, PanelUi.COLOR_OK))
	else:
		var claim := PanelUi.button(tr("Забрать"), &"ButtonGreen")
		claim.custom_minimum_size = Vector2(110, 26)
		claim.disabled = not done
		claim.pressed.connect(_on_claim_pressed.bind(index))
		row.add_child(claim)
	return row


func _on_claim_pressed(index: int) -> void:
	var ok := GameState.progress.claim_quest(index)
	GameState.save_game()
	result.emit(tr("Награда получена") if ok else tr("Задание ещё не выполнено"), ok)
