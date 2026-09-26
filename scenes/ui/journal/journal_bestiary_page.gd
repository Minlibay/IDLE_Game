class_name JournalBestiaryPage
extends VBoxContainer
## Вкладка «Бестиарий»: убийства каждого вида; за 100 / 1000 / 10 000 — урон против него,
## за каждый полностью изученный вид — немного урона против всех.

signal result(text: String, ok: bool)

var _summary: Label
var _grid: GridContainer


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := PanelUi.section(self, tr("Бестиарий"), 0)
	_summary = PanelUi.hint("", 12)
	box.add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	box.add_child(scroll)


func refresh() -> void:
	var progress := GameState.progress
	var mastered := progress.mastered_count()
	_summary.text = tr("Урон против вида: %s за 100 / 1 000 / 10 000 убийств. Полностью изучено видов: %d — +%d%% урона против всех.") % [
		" / ".join(HeroProgress.BESTIARY_DAMAGE.map(func(value: float) -> String: return "+%d%%" % int(value))), mastered,
		roundi(mastered * HeroProgress.BESTIARY_MASTERY_DAMAGE)]
	PanelUi.clear(_grid)
	var monsters := Database.monsters.duplicate()
	monsters.sort_custom(func(a: MonsterData, b: MonsterData) -> bool: return a.min_wave < b.min_wave or (a.min_wave == b.min_wave and a.id < b.id))
	for monster: MonsterData in monsters:
		_grid.add_child(_make_card(monster, progress))


func _make_card(monster: MonsterData, progress: HeroProgress) -> Control:
	var kills := int(progress.bestiary.get(monster.id, 0))
	var tier := progress.bestiary_tier(monster.id)
	var known := kills > 0
	var card := HBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)
	var frames := monster.sprite_frames
	var texture: Texture2D = frames.get_frame_texture(Actor.ANIM_IDLE, 0) if frames and frames.has_animation(Actor.ANIM_IDLE) else monster.sprite
	var icon := UiStyles.make_icon(texture, 40)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Невстреченный монстр — чёрный силуэт.
	icon.modulate = monster.tint if known else Color(0, 0, 0, 0.85)
	card.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	var title := monster.display_name if known else "???"
	if monster.is_boss and known:
		title += " ★"
	texts.add_child(PanelUi.cell(title, 0, PanelUi.COLOR_GOLD if tier >= 3 else Color.WHITE, true, 12))
	var next_index := mini(tier, HeroProgress.BESTIARY_THRESHOLDS.size() - 1)
	var next: int = HeroProgress.BESTIARY_THRESHOLDS[next_index]
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"BarBuild"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = next
	bar.value = mini(kills, next)
	texts.add_child(bar)
	var bonus := tr("+%d%% урона") % int(HeroProgress.BESTIARY_DAMAGE[tier - 1]) if tier > 0 else tr("нет бонуса")
	texts.add_child(PanelUi.cell(tr("%d / %d · %s") % [kills, next, bonus] if tier < 3 else tr("%d · %s · изучен") % [kills, bonus], 0, PanelUi.COLOR_HINT, true, 10))
	card.add_child(texts)
	card.tooltip_text = tr("Убито: %d") % kills
	return card
