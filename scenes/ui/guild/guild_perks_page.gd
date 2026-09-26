class_name GuildPerksPage
extends VBoxContainer
## Вкладка «Бонусы»: дерево бонусов гильдии (три ветки по три бонуса). Очки дают уровни гильдии,
## распределяет глава; следующий бонус ветки открывается, когда в ветку вложено достаточно очков.

signal result(text: String, ok: bool)

var _points_label: Label
var _reset_button: Button
var _branch_labels: Dictionary = {}
var _perk_rows: Dictionary = {}


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	var branches := HBoxContainer.new()
	branches.size_flags_vertical = Control.SIZE_EXPAND_FILL
	branches.add_theme_constant_override("separation", 8)
	add_child(branches)
	for branch: Dictionary in GuildCatalog.branches():
		var box := PanelUi.section(branches, tr(str(branch.name)), 0)
		var points := PanelUi.hint("")
		box.add_child(points)
		_branch_labels[branch.id] = points
		for index in (branch.perks as Array).size():
			_perk_rows[branch.perks[index].id] = _make_perk_row(box, branch.perks[index], index)
	var footer := HBoxContainer.new()
	_points_label = Label.new()
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points_label.add_theme_font_size_override("font_size", 12)
	footer.add_child(_points_label)
	_reset_button = PanelUi.button(tr("Сбросить бонусы"), &"ButtonRed")
	_reset_button.tooltip_text = tr("Все очки вернутся, распределить их можно заново. Не чаще раза в сутки.")
	_reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(_reset_button)
	add_child(footer)


func refresh() -> void:
	var view := WorldService.guild
	if view.is_empty():
		return
	var perks: Dictionary = view.get("perks", {})
	var leader := WorldService.guild_role() == "leader"
	var free := int(view.get("perkPointsFree", 0))
	for branch: Dictionary in GuildCatalog.branches():
		var spent := 0
		for perk: Dictionary in branch.perks:
			spent += int(perks.get(perk.id, 0))
		(_branch_labels[branch.id] as Label).text = tr("Вложено очков: %d") % spent
		for index in (branch.perks as Array).size():
			var perk: Dictionary = branch.perks[index]
			_refresh_perk_row(_perk_rows[perk.id], perk, index, int(perks.get(perk.id, 0)), spent, free, leader)
	_points_label.text = tr("Свободных очков: %d из %d · каждый уровень гильдии даёт %d") % [
		free, int(view.get("perkPoints", 0)), int(GuildCatalog.data().get("perk_points_per_level", 0))]
	if not leader:
		_points_label.text += tr(" · распределяет глава")
	_reset_button.visible = leader
	var reset_at := float(view.get("perksResetAt", 0.0))
	var wait := WorldService.time_until(reset_at) if reset_at > 0.0 else 0.0
	_reset_button.disabled = wait > 0.0 or int(view.get("perkPoints", 0)) == free
	_reset_button.text = tr("Сброс через %s") % UiFormat.duration(wait) if wait > 0.0 else tr("Сбросить бонусы")


func _make_perk_row(parent: Container, perk: Dictionary, index: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var icon := UiStyles.make_icon(GuildCatalog.perk_icon(str(perk.stat)), 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	var name_label := PanelUi.cell("", 0, Color.WHITE, true, 13)
	var effect_label := PanelUi.cell("", 0, PanelUi.COLOR_OK, true, 11)
	var need_label := PanelUi.cell("", 0, PanelUi.COLOR_HINT, true, 10)
	texts.add_child(name_label)
	texts.add_child(effect_label)
	texts.add_child(need_label)
	row.add_child(texts)
	var learn := PanelUi.button("+", &"ButtonGreen")
	learn.custom_minimum_size = Vector2(34, 30)
	learn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	learn.pressed.connect(_on_learn_pressed.bind(str(perk.id)))
	row.add_child(learn)
	parent.add_child(row)
	return {"row": row, "icon": icon, "name": name_label, "effect": effect_label, "need": need_label, "learn": learn}


func _refresh_perk_row(parts: Dictionary, perk: Dictionary, index: int, rank: int, branch_spent: int, free: int, leader: bool) -> void:
	var max_rank := (perk.values as Array).size()
	(parts.name as Label).text = "%s · %d/%d" % [tr(str(perk.name)), rank, max_rank]
	(parts.effect as Label).text = GuildCatalog.perk_progress(perk, rank)
	(parts.effect as Label).tooltip_text = (parts.effect as Label).text
	(parts.effect as Label).add_theme_color_override("font_color", PanelUi.COLOR_OK if rank > 0 else PanelUi.COLOR_HINT)
	var needed := GuildCatalog.tier_points(index)
	var locked := branch_spent < needed
	(parts.need as Label).text = tr("Откроется, когда в ветку вложено %d очков") % needed if locked else ""
	(parts.icon as TextureRect).modulate = Color(1, 1, 1, 0.4) if locked else Color.WHITE
	var learn := parts.learn as Button
	learn.visible = leader and rank < max_rank
	learn.disabled = locked or free <= 0
	learn.tooltip_text = tr("Повысить ранг (1 очко)")


func _on_learn_pressed(perk_id: String) -> void:
	var response := await WorldService.guild_learn_perk(perk_id)
	result.emit(tr("Бонус повышен") if response.ok else str(response.error), response.ok)


func _on_reset_pressed() -> void:
	var response := await WorldService.guild_reset_perks()
	result.emit(tr("Бонусы сброшены — распределите очки заново") if response.ok else str(response.error), response.ok)
