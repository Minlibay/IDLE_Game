extends Node
## Превращает окно игры в прозрачную полоску внизу рабочего стола
## и управляет «сквозными» кликами: пустые места пропускают клики на рабочий стол.

enum Mode { FULL, BATTLE }

const WINDOW_HEIGHT := 340
## Высота нижней зоны, которая принимает клики в бою. Выше — клики уходят на рабочий стол.
const BATTLE_INTERACTIVE_HEIGHT := 190
## Какую долю экрана занимает окно в режиме карты.
const MAP_SCREEN_SHARE := 0.9

var _enabled := false
var _mode := Mode.FULL
var _modal_count := 0
var _map_mode := false


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
	_apply_strip_geometry()
	window.size_changed.connect(_apply)
	_apply()


## Режим карты: окно раскрывается на большую часть экрана и целиком принимает клики.
func enter_map_mode() -> void:
	if not _enabled or _map_mode:
		return
	_map_mode = true
	var window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var map_size := Vector2i(Vector2(usable.size) * MAP_SCREEN_SHARE)
	window.size = map_size
	window.position = usable.position + (usable.size - map_size) / 2
	push_modal()


func exit_map_mode() -> void:
	if not _map_mode:
		return
	_map_mode = false
	_apply_strip_geometry()
	pop_modal()


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


## Полоска во всю ширину экрана над панелью задач.
func _apply_strip_geometry() -> void:
	var window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = Vector2i(usable.size.x, WINDOW_HEIGHT)
	window.position = Vector2i(usable.position.x, usable.end.y - WINDOW_HEIGHT)
