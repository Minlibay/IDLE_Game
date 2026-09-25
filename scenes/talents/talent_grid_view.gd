class_name TalentGridView
extends PanZoomView
## Полотно сетки талантов: узлы, связи между изученными, подсветка доступных.
## Клик — выбрать узел, двойной клик — изучить, наведение — подсказка.

signal talent_selected(talent: TalentData)
signal talent_learn_requested(talent: TalentData)

## Шаг сетки на полотне (при масштабе 1).
const CELL := 40.0
## Размер рамки узла относительно клетки.
const SIZE_BY_KIND := {
	TalentData.Kind.MINOR: 0.62,
	TalentData.Kind.NOTABLE: 0.92,
	TalentData.Kind.KEYSTONE: 1.12,
	TalentData.Kind.START: 1.0,
}
const ICON_SHARE := 0.5
## При открытии сетка занимает почти всё окно.
const FIT_MARGIN := 0.96
## Вписывать можно, только когда окно уже раскрыто (в режиме полоски полотно слишком низкое).
const MIN_FIT_HEIGHT := 400.0
const REGION_TINT_ALPHA := 0.07
const COLOR_LINK_LEARNED := Color(1.0, 0.8, 0.35, 0.95)
const COLOR_LINK_AVAILABLE := Color(0.85, 0.85, 1.0, 0.35)
const COLOR_LINK_LOCKED := Color(0.4, 0.38, 0.5, 0.25)
const LOCKED_MODULATE := Color(0.5, 0.5, 0.58)
## Ключевые узлы всегда в золотой рамке (видны издалека как цели), до доступа — приглушены.
const KEYSTONE_LOCKED_MODULATE := Color(0.8, 0.72, 0.55)

const FRAME_LOCKED := preload("res://assets/ui/slots/talent_locked.png")
const FRAME_AVAILABLE := preload("res://assets/ui/slots/talent_available.png")
const FRAME_LEARNED := preload("res://assets/ui/slots/talent_learned.png")
const FRAME_MAXED := preload("res://assets/ui/slots/talent_maxed.png")
const FRAME_SELECTED := preload("res://assets/ui/slots/slot_selected.png")

var tree: TalentTree
var selected: TalentData
var _fit_pending := false


func _ready() -> void:
	min_zoom = 0.3
	max_zoom = 2.5
	GameState.talents_changed.connect(queue_redraw)
	GameState.leveled_up.connect(func(_level: int) -> void: queue_redraw())


func set_tree(p_tree: TalentTree) -> void:
	tree = p_tree
	queue_redraw()


## Вписать сетку, как только окно раскроется до полного размера.
func request_fit() -> void:
	_fit_pending = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _fit_pending:
		set_process(false)
		return
	if tree == null or size.y < MIN_FIT_HEIGHT:
		return
	_fit_pending = false
	center_on_start()


## Масштаб «вся сетка в окне» и центр на старте.
func center_on_start() -> void:
	if tree == null:
		return
	var grid_pixels := Vector2(tree.grid_size) * CELL
	zoom = clampf(minf(size.x / grid_pixels.x, size.y / grid_pixels.y) * FIT_MARGIN, min_zoom, max_zoom)
	center_on_point(_cell_center(tree.get_center()))


func select(talent: TalentData) -> void:
	selected = talent
	queue_redraw()
	talent_selected.emit(talent)


func talent_at(screen_point: Vector2) -> TalentData:
	if tree == null:
		return null
	var canvas := to_canvas(screen_point)
	var cell := Vector2i(floori(canvas.x / CELL), floori(canvas.y / CELL))
	return tree.at(cell)


func _on_click(screen_point: Vector2) -> void:
	var talent := talent_at(screen_point)
	if talent:
		select(talent)


func _on_double_click(screen_point: Vector2) -> void:
	var talent := talent_at(screen_point)
	if talent:
		select(talent)
		talent_learn_requested.emit(talent)


## Подсказка при наведении (Godot вызывает для tooltip).
func _get_tooltip(at_position: Vector2) -> String:
	var talent := talent_at(at_position)
	if talent == null:
		return ""
	return "%s\n%s" % [talent.display_name, talent.get_description(1)]


func _draw() -> void:
	if tree == null:
		return
	var view_rect := visible_canvas_rect(CELL * 2.0)
	_draw_region_tint(view_rect)
	_draw_links(view_rect)
	for talent in tree.get_talents():
		var center := _cell_center(talent.grid_position)
		if view_rect.has_point(center):
			_draw_node(talent, to_screen(center))


## Лёгкая подложка цветом сектора — видно, где «Оружие», где «Защита».
func _draw_region_tint(view_rect: Rect2) -> void:
	var cell_size := Vector2.ONE * CELL * zoom
	for talent in tree.get_talents():
		var center := _cell_center(talent.grid_position)
		if not view_rect.has_point(center) or talent.kind == TalentData.Kind.START:
			continue
		var color := Color(tree.regions[talent.region].color, REGION_TINT_ALPHA)
		draw_rect(Rect2(to_screen(center) - cell_size * 0.5, cell_size), color)


## Связи между соседними узлами: золотые — оба изучены, светлые — ведут к доступному.
func _draw_links(view_rect: Rect2) -> void:
	var width := maxf(1.0, 2.5 * zoom)
	for talent in tree.get_talents():
		var center := _cell_center(talent.grid_position)
		if not view_rect.has_point(center):
			continue
		var learned := GameState.get_talent_rank(talent) > 0
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other := tree.at(talent.grid_position + offset)
			if other == null:
				continue
			var other_learned := GameState.get_talent_rank(other) > 0
			var color := COLOR_LINK_LOCKED
			if learned and other_learned:
				color = COLOR_LINK_LEARNED
			elif learned or other_learned:
				color = COLOR_LINK_AVAILABLE
			draw_line(to_screen(center), to_screen(_cell_center(other.grid_position)), color,
				width if color == COLOR_LINK_LEARNED else maxf(1.0, width * 0.5))


func _draw_node(talent: TalentData, screen_center: Vector2) -> void:
	var rank := GameState.get_talent_rank(talent)
	var reachable := rank == 0 and GameState.is_talent_reachable(talent)
	var frame := FRAME_LOCKED
	if talent.kind == TalentData.Kind.START or (talent.kind == TalentData.Kind.KEYSTONE and rank > 0):
		frame = FRAME_MAXED
	elif rank > 0:
		frame = FRAME_LEARNED
	elif reachable:
		frame = FRAME_AVAILABLE
	var node_size := CELL * zoom * float(SIZE_BY_KIND[talent.kind])
	var modulate := Color.WHITE if rank > 0 or reachable else LOCKED_MODULATE
	# Ключевые узлы видно издалека: золотая рамка даже до изучения.
	if talent.kind == TalentData.Kind.KEYSTONE and rank == 0:
		frame = FRAME_MAXED
		modulate = Color.WHITE if reachable else KEYSTONE_LOCKED_MODULATE
	var rect := Rect2(screen_center - Vector2.ONE * node_size * 0.5, Vector2.ONE * node_size)
	draw_texture_rect(frame, rect, false, modulate)
	var icon := talent.get_icon()
	if icon:
		var icon_size := node_size * ICON_SHARE
		draw_texture_rect(icon, Rect2(screen_center - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, modulate)
	if talent == selected:
		draw_texture_rect(FRAME_SELECTED, rect.grow(node_size * 0.12), false)


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
