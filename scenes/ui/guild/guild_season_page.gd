class_name GuildSeasonPage
extends HBoxContainer
## Вкладка «Сезон»: война гильдий за регионы. Зоны участников приносят очки (по уровню зоны),
## регион контролирует гильдия с большинством зон — там очки идут с множителем. В конце сезона — награды тройке.

signal result(text: String, ok: bool)

var _summary: Label
var _regions_label: Label
var _rewards_label: Label
var _table: VBoxContainer


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var left := PanelUi.section(self, tr("Война гильдий"), 400)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 13)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_summary)
	_regions_label = PanelUi.hint("", 12)
	left.add_child(_regions_label)
	_rewards_label = PanelUi.hint("", 11)
	left.add_child(_rewards_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(PanelUi.hint(tr("Очки: каждый час — сумма уровней зон участников (центр карты ценнее). В регионе, который контролирует гильдия (больше всех зон, не меньше 10), очки ×1,5.")))

	var right := PanelUi.section(self, tr("Таблица сезона"), 0)
	var header := HBoxContainer.new()
	header.add_child(PanelUi.cell(tr("Место"), 50, PanelUi.COLOR_HINT))
	header.add_child(PanelUi.cell(tr("Гильдия"), 0, PanelUi.COLOR_HINT, true))
	header.add_child(PanelUi.cell(tr("Участники"), 80, PanelUi.COLOR_HINT))
	header.add_child(PanelUi.cell(tr("Регионы"), 70, PanelUi.COLOR_HINT))
	header.add_child(PanelUi.cell(tr("Очки"), 80, PanelUi.COLOR_HINT))
	right.add_child(header)
	_table = PanelUi.scroll_list(right)


func refresh() -> void:
	var season: Dictionary = WorldService.guild.get("season", {})
	if season.is_empty():
		return
	_summary.text = tr("Сезон %d · закончится через %s\nВаша гильдия: %d место, %d очков") % [
		int(season.id), UiFormat.duration(WorldService.time_until(float(season.endsAt))), int(season.place), int(season.points)]
	var my_guild := int(WorldService.my_guild().get("id", -1))
	var names := PackedStringArray()
	for region: Dictionary in WorldService.regions.get("list", []):
		if region.guildId != null and int(region.guildId) == my_guild:
			names.append(GuildCatalog.region_name(int(region.index)))
	_regions_label.text = tr("Под контролем: %s") % (", ".join(names) if not names.is_empty() else tr("пока ни одного региона"))
	var rewards := PackedStringArray()
	var list: Array = season.get("rewards", [])
	for index in list.size():
		rewards.append(tr("%d место: %d золота каждому и %d опыта гильдии") % [index + 1, int(list[index].gold), int(list[index].xp)])
	var awards: Array = WorldService.guild.get("awards", [])
	var history := PackedStringArray()
	for award: Dictionary in awards:
		history.append(tr("сезон %d — %d место") % [int(award.season), int(award.place)])
	_rewards_label.text = tr("Награды:\n") + "\n".join(rewards) + ("\n" + tr("Ваши награды: ") + ", ".join(history) if not history.is_empty() else "")

	PanelUi.clear(_table)
	var standings: Array = season.get("standings", [])
	if standings.is_empty():
		_table.add_child(PanelUi.hint(tr("Гильдии ещё не набрали очков в этом сезоне.")))
	for entry: Dictionary in standings:
		var mine := int(entry.guildId) == my_guild
		var row := HBoxContainer.new()
		var color := PanelUi.COLOR_GOLD if mine else Color.WHITE
		row.add_child(PanelUi.cell("%d." % int(entry.place), 50, PanelUi.COLOR_HINT))
		var name_cell := PanelUi.cell(WorldService.tagged_name(str(entry.name), entry.tag), 0, Color(str(entry.color)), true)
		row.add_child(name_cell)
		row.add_child(PanelUi.cell(str(int(entry.members)), 80, color))
		row.add_child(PanelUi.cell(str(int(entry.regions)), 70, color))
		row.add_child(PanelUi.cell(str(int(entry.points)), 80, color))
		_table.add_child(row)
