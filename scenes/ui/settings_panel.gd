class_name SettingsPanel
extends PanelContainer
## Окно настроек: язык, частота кадров и звук. Всё применяется сразу. При смене языка сцена боя
## пересоздаётся (см. main.gd), после чего окно открывается снова, чтобы было видно результат.

## Каналы громкости (Settings.SOUND_CHANNELS) → подпись.
const VOLUME_LABELS := {
	"master": "Общая громкость", "music": "Музыка", "combat": "Бой", "ui": "Интерфейс", "notify": "Уведомления",
}
const COMBAT_MODES := [
	[Settings.CombatSound.ALWAYS, "Всегда", "Звуки боя слышны всегда."],
	[Settings.CombatSound.ON_HOVER, "При наведении", "Звуки боя слышны, пока курсор над полосой боя или открыто окно, — не мешают работать."],
	[Settings.CombatSound.OFF, "Выкл.", "Бой без звука; интерфейс и уведомления остаются."],
]

var _volume_values := {}

@onready var close_button: Button = %CloseButton
@onready var language_list: GridContainer = %LanguageList
@onready var fps_list: HBoxContainer = %FpsList
@onready var mute_check: CheckButton = %MuteCheck
@onready var volume_grid: GridContainer = %VolumeGrid
@onready var combat_list: HBoxContainer = %CombatList
@onready var tray_check: CheckButton = %TrayCheck


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)
	var group := ButtonGroup.new()
	for code: String in Settings.LANGUAGES:
		var button := Button.new()
		button.text = Settings.LANGUAGES[code]
		# Название языка всегда на нём самом — не переводим.
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = code == Settings.language
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"ButtonBlue" if code == Settings.language else &""
		button.pressed.connect(Settings.set_language.bind(code))
		language_list.add_child(button)
	var fps_group := ButtonGroup.new()
	for limit: int in Settings.FRAME_LIMITS:
		var fps_button := Button.new()
		fps_button.text = tr("%d кадров/с") % limit
		fps_button.toggle_mode = true
		fps_button.button_group = fps_group
		fps_button.button_pressed = limit == Settings.frame_limit
		fps_button.custom_minimum_size = Vector2(130, 30)
		fps_button.tooltip_text = tr("Меньше нагрузка на видеокарту и батарею ноутбука.") if limit == 30 else tr("Плавнее, но нагрузка выше.")
		fps_button.pressed.connect(Settings.set_frame_limit.bind(limit))
		fps_list.add_child(fps_button)
	_build_sound()


func _build_sound() -> void:
	mute_check.button_pressed = Settings.muted
	mute_check.toggled.connect(Settings.set_muted)
	tray_check.button_pressed = Settings.sound_in_tray
	tray_check.tooltip_text = tr("Бой и музыка в трее молчат всегда; уведомления (уровень, редкая добыча, нападение) — по этой настройке.")
	tray_check.toggled.connect(Settings.set_sound_in_tray)
	for channel: String in Settings.SOUND_CHANNELS:
		var label := Label.new()
		label.text = tr(VOLUME_LABELS[channel])
		label.add_theme_font_size_override("font_size", 12)
		volume_grid.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Settings.get_volume(channel)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(150, 18)
		slider.value_changed.connect(_on_volume_changed.bind(channel))
		volume_grid.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(38, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		volume_grid.add_child(value)
		_volume_values[channel] = value
	var group := ButtonGroup.new()
	for mode: Array in COMBAT_MODES:
		var button := Button.new()
		button.text = tr(mode[1])
		button.tooltip_text = tr(mode[2])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = mode[0] == Settings.combat_sound
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 28)
		button.pressed.connect(Settings.set_combat_sound.bind(mode[0]))
		combat_list.add_child(button)
	Settings.sound_changed.connect(_refresh_sound)
	_refresh_sound()


func _on_volume_changed(value: float, channel: String) -> void:
	Settings.set_volume(channel, value)
	# Громкость интерфейса слышно сразу — щелчок на новой громкости.
	if channel in ["master", "ui"]:
		Sound.play(&"click")


func _refresh_sound() -> void:
	mute_check.set_pressed_no_signal(Settings.muted)
	tray_check.set_pressed_no_signal(Settings.sound_in_tray)
	for channel: String in _volume_values:
		(_volume_values[channel] as Label).text = "%d%%" % roundi(Settings.get_volume(channel) * 100.0)
		(_volume_values[channel] as Label).modulate = Color(1, 1, 1, 0.45 if Settings.muted else 1.0)


func _exit_tree() -> void:
	# Панель уничтожается вместе с HUD при смене языка — модальность окна надо вернуть.
	if visible:
		DesktopWindow.pop_modal()


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


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()
