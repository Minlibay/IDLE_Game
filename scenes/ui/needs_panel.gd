class_name NeedsPanel
extends PanelContainer
## Шкалы потребностей героя (строятся из data/needs/) и кнопка отдыха.

signal rest_requested

const LEVEL_NAMES := ["мало", "норма", "хорошо"]

var _bars: Dictionary[String, ProgressBar] = {}
var _rows: Dictionary[String, Control] = {}
var _resting := false

@onready var bars_box: VBoxContainer = %NeedBars
@onready var rest_button: Button = %RestButton


func _ready() -> void:
	for need in Database.needs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon := TextureRect.new()
		icon.texture = need.icon
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(96, 11)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = NeedsState.MAX_VALUE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if need.bar_theme_variation != &"":
			bar.theme_type_variation = need.bar_theme_variation
		else:
			bar.add_theme_stylebox_override("fill", _bar_style(need.bar_color))
		row.add_child(bar)
		bars_box.add_child(row)
		_bars[need.id] = bar
		_rows[need.id] = row
	rest_button.pressed.connect(rest_requested.emit)
	GameState.needs.changed.connect(_refresh)
	GameState.kingdom.resources_changed.connect(_refresh_tooltips)
	_refresh()


func set_resting(value: bool) -> void:
	_resting = value
	_refresh()


func _refresh() -> void:
	for need in Database.needs:
		_bars[need.id].value = GameState.needs.get_value(need)
	rest_button.disabled = _resting or not GameState.needs.can_rest_manually()
	rest_button.text = tr("Спит…") if _resting else tr("Отдых")
	_refresh_tooltips()


func _refresh_tooltips() -> void:
	for need in Database.needs:
		var level := GameState.needs.get_level(need)
		var lines := PackedStringArray()
		lines.append("%s: %d / 100 (%s)" % [need.display_name, roundi(GameState.needs.get_value(need)), tr(LEVEL_NAMES[level])])
		if need.consumes_resource != "":
			lines.append(tr("Запас: %d %s — герой берёт сам") % [
				floori(GameState.kingdom.get_resource(need.consumes_resource)),
				KingdomState.resource_name(need.consumes_resource)])
		if need.restored_by_rest:
			lines.append(tr("На нуле герой уходит отдыхать"))
		if not need.satisfied_modifiers.is_empty():
			lines.append(tr("От %d: %s") % [roundi(need.satisfied_threshold), StatModifier.describe_list(need.satisfied_modifiers)])
		if not need.low_modifiers.is_empty():
			lines.append(tr("Ниже %d: %s") % [roundi(need.low_threshold), StatModifier.describe_list(need.low_modifiers)])
		_rows[need.id].tooltip_text = "\n".join(lines)


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style
