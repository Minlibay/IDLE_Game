class_name JournalPanel
extends PanelContainer
## Окно «Путь героя» [J]: ежедневные задания, достижения, бестиарий и перерождение.
## Всё хранится в GameState.progress (HeroProgress) и живёт в сохранении героя.

const TAB_TITLES := ["Задания", "Достижения", "Бестиарий", "Перерождение"]
const COLOR_OK := Color(0.55, 0.9, 0.5)
const COLOR_BAD := Color(1.0, 0.5, 0.45)
const REFRESH_INTERVAL := 1.0

@onready var close_button: Button = %CloseButton
@onready var souls_label: Label = %SoulsLabel
@onready var result_label: Label = %ResultLabel
@onready var tabs_row: HBoxContainer = %Tabs
@onready var body: Control = %Body

var _tab := 0
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _refresh_timer := 0.0


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)
	var group := ButtonGroup.new()
	for index in TAB_TITLES.size():
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = index == _tab
		tab.custom_minimum_size = Vector2(130, 24)
		tab.pressed.connect(_on_tab_pressed.bind(index))
		tabs_row.add_child(tab)
		tabs_row.move_child(tab, index)
		_tab_buttons.append(tab)
	for page: Control in [JournalQuestsPage.new(), JournalAchievementsPage.new(), JournalBestiaryPage.new(), JournalPrestigePage.new()]:
		page.visible = false
		body.add_child(page)
		page.result.connect(func(text: String, ok: bool) -> void:
			result_label.text = text
			result_label.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_BAD)
			_refresh())
		_pages.append(page)
	GameState.progress_changed.connect(_refresh)


func _exit_tree() -> void:
	if visible:
		DesktopWindow.pop_modal()


func _process(delta: float) -> void:
	if not visible:
		return
	# Счётчики (убийства, прогресс заданий) растут прямо в бою — обновляем раз в секунду.
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh()


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
	result_label.text = ""
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	DesktopWindow.pop_modal()


## Открыть на вкладке (0 — задания … 3 — перерождение).
func show_tab(index: int) -> void:
	open()
	_tab = clampi(index, 0, TAB_TITLES.size() - 1)
	_tab_buttons[_tab].button_pressed = true
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	var progress := GameState.progress
	souls_label.text = tr("Души: %d") % progress.souls
	var titles := TAB_TITLES.map(func(title: String) -> String: return tr(title))
	var quests := progress.claimable_quests()
	var achievements := progress.claimable_achievements()
	if quests > 0:
		titles[0] = "%s (%d)" % [titles[0], quests]
	if achievements > 0:
		titles[1] = "%s (%d)" % [titles[1], achievements]
	if progress.can_prestige():
		titles[3] = "%s (!)" % titles[3]
	for index in _tab_buttons.size():
		_tab_buttons[index].text = titles[index]
		_pages[index].visible = index == _tab
	_pages[_tab].call(&"refresh")


func _on_tab_pressed(index: int) -> void:
	_tab = index
	_refresh()
