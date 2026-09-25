class_name BattleFigure
extends Node2D
## Фигурка солдата в повторе боя (BattleReplay): бежит, бьёт, стреляет, падает.
## Анимация процедурная (покачивание, выпад, падение). Внешний вид — картинка отряда
## (UnitData.battle_sprite), а пока её нет — солдатик, нарисованный кодом по типу отряда.
## Позиция узла — точка под ногами.

const RUN_BOB := 3.0
const RUN_BOB_SPEED := 14.0
const LUNGE := 7.0
const DEAD_COLOR := Color(0.62, 0.5, 0.48, 0.85)

var unit_id := ""
var alive := true
var ranged := false
var is_hero := false
## 1 — смотрит вправо, -1 — влево.
var facing := 1
## Тело (картинка или нарисованный солдатик): его качаем, двигаем при ударе и роняем.
var _body: Node2D
var _height := 30.0
## Цвет стороны: кольцо под ногами (картинку отряда целиком не перекрашиваем).
var _side_color := Color.WHITE
var _moving := false
var _cheering := false
var _phase := 0.0


## texture == null — солдатик рисуется кодом (вид по unit_style: id отряда).
func setup(texture: Texture2D, height: float, p_facing: int, tint: Color, phase: float, unit_style := "") -> void:
	facing = p_facing
	_height = height
	_side_color = tint
	# Живые поверх павших; павшие — поверх фона поля (он на уровне 0).
	z_index = 1
	_phase = phase
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		# Точка вращения — ноги: так фигурка падает, а не крутится вокруг центра.
		sprite.centered = false
		sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height())
		sprite.scale = Vector2.ONE * height / float(texture.get_height())
		sprite.flip_h = facing < 0
		_body = sprite
		tint = Color.WHITE.lerp(tint, 0.2)
	else:
		var drawn := SoldierDrawing.new()
		drawn.style = unit_style
		drawn.tint = tint
		drawn.pixel = height / SoldierDrawing.HEIGHT_PIXELS
		drawn.scale.x = facing
		_body = drawn
		tint = Color.WHITE
	_body.modulate = tint
	add_child(_body)


func _process(delta: float) -> void:
	if not alive or _body == null:
		return
	_phase += delta
	if _moving:
		_body.position.y = -absf(sin(_phase * RUN_BOB_SPEED)) * RUN_BOB
	elif _cheering:
		_body.position.y = -absf(sin(_phase * 8.0)) * RUN_BOB * 2.0
	else:
		_body.position.y = sin(_phase * 3.0) * 0.6


func _draw() -> void:
	# Тень под ногами.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, _height * 0.28, Color(0, 0, 0, 0.28 if alive else 0.15))
	if alive:
		draw_arc(Vector2.ZERO, _height * 0.3, 0.0, TAU, 16, Color(_side_color, 0.8), 2.0)


## Бег в точку за duration секунд.
func run_to(point: Vector2, duration: float, delay := 0.0) -> Tween:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void: _moving = true)
	tween.tween_property(self, "position", point, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: _moving = false)
	return tween


## Удар: короткий выпад в сторону врага.
func strike() -> void:
	if not alive:
		return
	var tween := create_tween()
	tween.tween_property(_body, "position:x", LUNGE * facing, 0.07)
	tween.tween_property(_body, "position:x", 0.0, 0.12)


## Отдача при выстреле (лучники).
func recoil() -> void:
	if not alive:
		return
	var tween := create_tween()
	tween.tween_property(_body, "position:x", -3.0 * facing, 0.05)
	tween.tween_property(_body, "position:x", 0.0, 0.15)


## Падение: заваливается назад и остаётся лежать (приглушённым цветом).
func die(instant := false) -> void:
	if not alive:
		return
	alive = false
	_moving = false
	_cheering = false
	z_index = 0
	var angle := deg_to_rad(-85.0 * facing)
	queue_redraw()
	if instant:
		_body.rotation = angle
		_body.position = Vector2.ZERO
		_body.modulate = DEAD_COLOR
		return
	var tween := create_tween().set_parallel()
	_body.modulate = Color(1.8, 0.5, 0.5)
	tween.tween_property(_body, "rotation", angle, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, "position", Vector2.ZERO, 0.35)
	tween.tween_property(_body, "modulate", DEAD_COLOR, 0.6)


## Победители радуются.
func cheer() -> void:
	if alive:
		_moving = false
		_cheering = true


## Солдатик, нарисованный кодом (пока нет картинки отряда). Смотрит вправо, ноги в (0, 0).
## Координаты — в «пикселях» фигурки: pixel = высота / HEIGHT_PIXELS.
class SoldierDrawing extends Node2D:
	const HEIGHT_PIXELS := 13.0
	const SKIN := Color(0.96, 0.8, 0.64)
	const LEGS := Color(0.28, 0.22, 0.2)
	const WOOD := Color(0.55, 0.36, 0.2)
	const STEEL := Color(0.78, 0.8, 0.86)
	const STEEL_DARK := Color(0.45, 0.47, 0.54)

	var style := ""
	var tint := Color.WHITE
	var pixel := 2.0

	func _draw() -> void:
		var body_color := tint
		match style:
			"knight":
				body_color = STEEL
			"archer":
				body_color = tint.lerp(Color(0.3, 0.55, 0.3), 0.35)
		_box(-2.0, -4.0, 1.6, 4.0, LEGS)
		_box(0.4, -4.0, 1.6, 4.0, LEGS)
		_box(-2.5, -9.0, 5.0, 5.2, body_color)
		if style == "knight":
			_box(-0.9, -9.0, 1.8, 5.2, tint) # гербовая накидка цвета стороны
		_box(-1.6, -12.2, 3.6, 3.2, SKIN)
		match style:
			"militia":
				_box(-1.8, -12.8, 3.9, 1.0, WOOD.lightened(0.2)) # соломенная шляпа
				_line(1.8, -3.0, 4.6, -13.5, WOOD, 0.7)
				_line(3.8, -13.2, 4.2, -15.0, STEEL, 0.4)
				_line(4.6, -13.5, 5.2, -15.2, STEEL, 0.4)
				_line(5.3, -13.7, 6.1, -15.2, STEEL, 0.4)
			"spearman":
				_box(-1.9, -13.0, 4.0, 1.8, STEEL_DARK)
				_line(-0.5, -4.5, 7.5, -13.0, WOOD, 0.6)
				_triangle(Vector2(7.5, -13.0), Vector2(6.5, -12.9), Vector2(8.8, -14.6), STEEL)
				draw_circle(_p(2.4, -6.8), pixel * 2.1, STEEL_DARK)
				draw_circle(_p(2.4, -6.8), pixel * 1.6, tint.darkened(0.2))
			"archer":
				_box(-1.9, -13.0, 3.9, 1.6, Color(0.25, 0.45, 0.25)) # капюшон
				_box(-2.1, -12.2, 0.9, 2.6, Color(0.25, 0.45, 0.25))
				draw_arc(_p(2.2, -7.8), pixel * 3.4, -1.2, 1.2, 10, WOOD, pixel * 0.6)
				_line(2.2 + 3.4 * cos(-1.2), -7.8 + 3.4 * sin(-1.2), 2.2 + 3.4 * cos(1.2), -7.8 + 3.4 * sin(1.2), Color(0.9, 0.9, 0.85), 0.25)
			"knight":
				_box(-1.9, -13.0, 4.0, 4.0, STEEL) # шлем
				_box(0.2, -11.4, 1.8, 0.5, Color(0.1, 0.1, 0.12)) # прорезь
				_box(-0.4, -14.2, 1.0, 1.3, tint) # плюмаж
				_line(2.4, -6.0, 6.8, -11.6, STEEL, 0.6)
				_line(1.6, -7.2, 3.4, -5.0, STEEL_DARK, 0.5)
			_:
				_line(2.0, -5.0, 5.5, -10.5, STEEL, 0.5)
		_box(1.4, -8.6, 1.4, 3.0, SKIN if style != "knight" else STEEL_DARK) # рука

	func _p(x: float, y: float) -> Vector2:
		return Vector2(x, y) * pixel

	func _box(x: float, y: float, w: float, h: float, color: Color) -> void:
		draw_rect(Rect2(_p(x, y), Vector2(w, h) * pixel), color)

	func _line(x1: float, y1: float, x2: float, y2: float, color: Color, width: float) -> void:
		draw_line(_p(x1, y1), _p(x2, y2), color, maxf(1.0, width * pixel))

	func _triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([a * pixel, b * pixel, c * pixel]), color)
