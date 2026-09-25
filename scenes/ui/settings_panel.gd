class_name SettingsPanel
extends PanelContainer
## Окно настроек: пока — выбор языка. Язык меняется сразу; сцена боя пересоздаётся (см. main.gd),
## после чего окно открывается снова, чтобы было видно результат.

@onready var close_button: Button = %CloseButton
@onready var language_list: HBoxContainer = %LanguageList


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
		button.custom_minimum_size = Vector2(130, 30)
		button.theme_type_variation = &"ButtonBlue" if code == Settings.language else &""
		button.pressed.connect(Settings.set_language.bind(code))
		language_list.add_child(button)


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
