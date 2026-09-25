class_name PanZoomView
extends Control
## Основа для больших «полотен» (мировая карта, сетка талантов): перетаскивание левой/правой
## кнопкой мыши, масштаб колесом вокруг курсора, клик и двойной клик.
## Наследники рисуют в _draw() с учётом zoom и pan (экран = точка_полотна * zoom + pan)
## и переопределяют _on_click() / _on_double_click().

const ZOOM_STEP := 1.15
const DRAG_THRESHOLD := 4.0

@export var min_zoom := 0.35
@export var max_zoom := 3.0

var zoom := 1.0
var pan := Vector2.ZERO

var _dragging := false
var _drag_moved := false
var _drag_distance := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Поставить точку полотна в центр видимой области.
func center_on_point(canvas_point: Vector2) -> void:
	pan = size * 0.5 - canvas_point * zoom
	queue_redraw()


func to_canvas(screen_point: Vector2) -> Vector2:
	return (screen_point - pan) / zoom


func to_screen(canvas_point: Vector2) -> Vector2:
	return canvas_point * zoom + pan


## Видимая часть полотна (в его координатах) с запасом margin.
func visible_canvas_rect(margin := 0.0) -> Rect2:
	return Rect2(-pan / zoom, size / zoom).grow(margin)


## Клик без перетаскивания (координаты экрана). Переопределяется.
func _on_click(_screen_point: Vector2) -> void:
	pass


func _on_double_click(_screen_point: Vector2) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(button.position, ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if button.pressed:
				if button.double_click and button.button_index == MOUSE_BUTTON_LEFT:
					_on_double_click(button.position)
				_dragging = true
				_drag_moved = false
				_drag_distance = 0.0
			else:
				if _dragging and not _drag_moved and button.button_index == MOUSE_BUTTON_LEFT:
					_on_click(button.position)
				_dragging = false
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_drag_distance += motion.relative.length()
		if _drag_distance > DRAG_THRESHOLD:
			_drag_moved = true
			pan += motion.relative
			queue_redraw()
		accept_event()


func _zoom_at(point: Vector2, factor: float) -> void:
	var canvas_point := to_canvas(point)
	zoom = clampf(zoom * factor, min_zoom, max_zoom)
	pan = point - canvas_point * zoom
	queue_redraw()
