extends Node
## Превращает окно игры в прозрачную полоску внизу рабочего стола
## и управляет «сквозными» кликами: пустые места пропускают клики на рабочий стол.

enum Mode { FULL, BATTLE }

const WINDOW_HEIGHT := 340
## Высота нижней зоны, которая принимает клики в бою. Выше — клики уходят на рабочий стол.
const BATTLE_INTERACTIVE_HEIGHT := 190
## Какую долю экрана занимает окно в режиме карты.
const MAP_SCREEN_SHARE := 0.9
## Размер дырки под курсором (см. _apply) и отступ от её края, после которого она догоняет курсор.
const CLICK_HOLE_SIZE := 96.0
const CLICK_HOLE_MARGIN := 30.0
## Значок игры в трее (области уведомлений Windows).
const TRAY_ICON := "res://icon.svg"

var _enabled := false
var _mode := Mode.FULL
var _modal_count := 0
var _map_mode := false
## «Дырка» в окне под курсором, сквозь которую клики уходят на рабочий стол. Пустая — дырки нет.
var _hole := Rect2()
var _hole_applied := false
## Значок в трее, пока игра свёрнута (-1 — значка нет), и его меню по правой кнопке.
var _tray_id := -1
var _tray_menu := RID()


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
	_apply()


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if is_in_tray():
		# Окно могли развернуть кнопкой на панели задач — тогда значок в трее больше не нужен.
		if get_window().mode != Window.MODE_MINIMIZED:
			restore_from_tray()
		return
	_apply()


func _exit_tree() -> void:
	_remove_tray_icon()


## Сворачивает игру в трей: окно сворачивается (спрятать главное окно Godot не даёт), в трее появляется значок,
## а бой, стройка и таймеры идут дальше. Вернуть — щелчок по значку, «Развернуть» в его меню или кнопка на панели задач.
func minimize_to_tray() -> void:
	if not _enabled:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		get_window().mode = Window.MODE_MINIMIZED
		return
	_remove_tray_icon()
	_tray_id = DisplayServer.create_status_indicator(load(TRAY_ICON), ProjectSettings.get_setting("application/config/name"),
		func(button: int, _position: Vector2i) -> void:
			if button == MOUSE_BUTTON_LEFT:
				restore_from_tray.call_deferred())
	if NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU):
		_tray_menu = NativeMenu.create_menu()
		NativeMenu.add_item(_tray_menu, tr("Развернуть"), func(_tag: Variant) -> void: restore_from_tray.call_deferred())
		NativeMenu.add_separator(_tray_menu)
		NativeMenu.add_item(_tray_menu, tr("Сохранить и выйти"), func(_tag: Variant) -> void: _quit_from_tray.call_deferred())
		DisplayServer.status_indicator_set_menu(_tray_id, _tray_menu)
	get_window().mode = Window.MODE_MINIMIZED


func is_in_tray() -> bool:
	return _tray_id >= 0


func restore_from_tray() -> void:
	if not is_in_tray():
		return
	_remove_tray_icon()
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.always_on_top = true
	window.grab_focus()
	if not _map_mode:
		_apply_strip_geometry()
	_hole_applied = false
	_apply()


func _quit_from_tray() -> void:
	_remove_tray_icon()
	GameState.save_game()
	get_tree().quit()


func _remove_tray_icon() -> void:
	if _tray_id >= 0:
		DisplayServer.delete_status_indicator(_tray_id)
		_tray_id = -1
	if _tray_menu.is_valid():
		NativeMenu.free_menu(_tray_menu)
		_tray_menu = RID()


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


## Принимает ли окно клик в этой точке (координаты окна): в бою — только нижняя полоса.
func accepts_clicks_at(local: Vector2) -> bool:
	if _mode == Mode.FULL or _modal_count > 0:
		return true
	return local.y >= get_window().size.y - BATTLE_INTERACTIVE_HEIGHT


## Сквозные клики. Регион окна в Windows не только пропускает клики, но и обрезает отрисовку,
## поэтому «полоса без верха» срезала имена боссов, названия умений и цифры урона.
## Флаг mouse_passthrough в Windows клики другим программам не отдаёт.
## Поэтому окно рисуется целиком, а когда курсор выше боевой полосы, в регионе под ним
## вырезается небольшая дырка — клик проходит на рабочий стол, а заметить её под курсором нельзя.
func _apply() -> void:
	if not _enabled:
		return
	var window := get_window()
	var size := Vector2(window.size)
	var local := Vector2(DisplayServer.mouse_get_position() - window.position)
	# Перетаскивание, начатое в окне, не прерываем.
	var dragging := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var hole := _hole
	if not Rect2(Vector2.ZERO, size).has_point(local) or accepts_clicks_at(local) or (dragging and _hole == Rect2()):
		hole = Rect2()
	elif _hole == Rect2() or not _hole.grow(-CLICK_HOLE_MARGIN).has_point(local):
		hole = Rect2(local - Vector2.ONE * CLICK_HOLE_SIZE * 0.5, Vector2.ONE * CLICK_HOLE_SIZE)
		hole = hole.intersection(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0))
	if hole == _hole and _hole_applied:
		return
	_hole = hole
	_hole_applied = true
	DisplayServer.window_set_mouse_passthrough(_region_with_hole(size, hole))


## Всё окно, кроме дырки: внешний контур и дырка, соединённые «перемычкой» нулевой ширины.
static func _region_with_hole(size: Vector2, hole: Rect2) -> PackedVector2Array:
	if not hole.has_area():
		return PackedVector2Array()
	var bridge_x := hole.get_center().x
	return PackedVector2Array([
		Vector2(0, size.y), Vector2(0, 0), Vector2(bridge_x, 0),
		Vector2(bridge_x, hole.position.y), Vector2(hole.position.x, hole.position.y),
		Vector2(hole.position.x, hole.end.y), Vector2(hole.end.x, hole.end.y),
		Vector2(hole.end.x, hole.position.y), Vector2(bridge_x, hole.position.y),
		Vector2(bridge_x, 0), Vector2(size.x, 0), size,
	])


## Полоска во всю ширину экрана над панелью задач.
func _apply_strip_geometry() -> void:
	var window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.size = Vector2i(usable.size.x, WINDOW_HEIGHT)
	window.position = Vector2i(usable.position.x, usable.end.y - WINDOW_HEIGHT)
