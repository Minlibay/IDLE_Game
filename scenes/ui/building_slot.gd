class_name BuildingSlot
extends Button
## Карточка здания: иконка, название, уровень в значке, полоска стройки.
## Рамки (assets/ui/kingdom/): серая — не построено, фиолетовая — построено,
## зелёная — можно улучшить, золотая — строится.

signal building_pressed(building: BuildingData)

const FRAME_DIR := "res://assets/ui/kingdom/"
## Левый верхний угол рамки со значком уровня не растягивается (значок — x 7..22, y 5..19 на картинке).
const FRAME_MARGINS := Vector4(24, 22, 12, 12)
const PADDING := Vector4(6, 8, 6, 4)

static var _styles: Dictionary = {}

var building: BuildingData

@onready var level_label: Label = $LevelLabel
@onready var build_bar: ProgressBar = $BuildBar


func _ready() -> void:
	pressed.connect(func() -> void: building_pressed.emit(building))


func setup(p_building: BuildingData) -> void:
	building = p_building
	icon = building.icon
	text = building.display_name
	tooltip_text = building.display_name


## construction_ratio < 0 — здание сейчас не строится.
func update_state(level: int, can_upgrade: bool, construction_ratio: float, selected: bool) -> void:
	level_label.text = str(level) if level > 0 else ""
	build_bar.visible = construction_ratio >= 0.0
	build_bar.value = maxf(construction_ratio, 0.0)
	var frame := "building_built" if level > 0 else "building_unbuilt"
	if construction_ratio >= 0.0:
		frame = "building_construction"
	elif can_upgrade:
		frame = "building_upgrade"
	var normal := _style(frame, Color.WHITE)
	var hover := _style(frame, UiStyles.HOVER_MODULATE)
	for state: String in ["normal", "disabled", "pressed"]:
		add_theme_stylebox_override(state, normal)
	for state: String in ["hover", "hover_pressed"]:
		add_theme_stylebox_override(state, hover)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UiStyles.set_selected(self, selected)
	# Не построенное здание — приглушённое.
	var dim := level == 0 and construction_ratio < 0.0
	add_theme_color_override("icon_normal_color", Color(0.55, 0.55, 0.6) if dim else Color.WHITE)
	add_theme_color_override("font_color", Color(0.6, 0.6, 0.68) if dim else Color(0.92, 0.9, 1.0))


static func _style(frame: String, modulate: Color) -> StyleBoxTexture:
	var key := frame + modulate.to_html()
	if not _styles.has(key):
		var style := StyleBoxTexture.new()
		style.texture = load(FRAME_DIR + frame + ".png")
		style.texture_margin_left = FRAME_MARGINS.x
		style.texture_margin_top = FRAME_MARGINS.y
		style.texture_margin_right = FRAME_MARGINS.z
		style.texture_margin_bottom = FRAME_MARGINS.w
		style.content_margin_left = PADDING.x
		style.content_margin_top = PADDING.y
		style.content_margin_right = PADDING.z
		style.content_margin_bottom = PADDING.w
		style.modulate_color = modulate
		_styles[key] = style
	return _styles[key]
