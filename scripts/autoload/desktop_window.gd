extends Node
## Превращает окно игры в прозрачную полоску внизу рабочего стола
## и управляет «сквозными» кликами: пустые места пропускают клики на рабочий стол.

enum Mode { FULL, BATTLE }

const WINDOW_HEIGHT := 340
## Высота нижней зоны, которая принимает клики в бою. Выше — клики уходят на рабочий стол.
const BATTLE_INTERACTIVE_HEIGHT := 190

var _enabled := false
var _mode := Mode.FULL
var _modal_count := 0


func _ready() -> void:
	# При запуске внутри вкладки «Game» редактора окном управлять нельзя.
	if Engine.is_embedded_in_editor():
		return
	_enabled = true
	var window := get_window()
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = Vector2i(usable.size.x, WINDOW_HEIGHT)
	window.position = Vector2i(usable.position.x, usable.end.y - WINDOW_HEIGHT)
	window.size_changed.connect(_apply)
	_apply()


## Всё окно принимает клики (экран создания героя).
func set_full_mode() -> void:
	_mode = Mode.FULL
	_apply()


## Клики принимает только нижняя полоса с боем.
func set_battle_mode() -> void:
	_mode = Mode.BATTLE
	_apply()


## Открыто модальное окно (инвентарь) — всё окно принимает клики, пока не вызван pop_modal().
func push_modal() -> void:
	_modal_count += 1
	_apply()


func pop_modal() -> void:
	_modal_count = maxi(0, _modal_count - 1)
	_apply()


func _apply() -> void:
	if not _enabled:
		return
	if _mode == Mode.FULL or _modal_count > 0:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return
	var size := Vector2(get_window().size)
	var top := maxf(0.0, size.y - BATTLE_INTERACTIVE_HEIGHT)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		Vector2(0, top), Vector2(size.x, top), size, Vector2(0, size.y),
	]))
