class_name WorldMapView
extends PanZoomView
## Отрисовка мировой карты: шестиугольные зоны, владельцы, замки, герои, поход.
## Перетаскивание и масштаб — из PanZoomView; клик — выбрать зону.

signal zone_selected(zone_id: int)

const HEX_SIZE := 14.0
## С какого масштаба показывать номер уровня зоны.
const TIER_LABEL_ZOOM := 2.4
## Центрировать можно, только когда окно уже раскрыто (в режиме полоски карта слишком низкая).
const MIN_FOCUS_HEIGHT := 400.0

const TILE_DIR := "res://assets/ui/map/"
## Местность по уровню зоны: [максимальный уровень, [[местность, вес], ...]].
## Выбор детерминирован по id зоны — карта всегда выглядит одинаково.
const TERRAIN_BY_TIER := [
	[3, [["grass", 5], ["forest", 3], ["hills", 1]]],
	[6, [["forest", 3], ["hills", 4], ["grass", 1], ["mountains", 1]]],
	[8, [["mountains", 4], ["hills", 2], ["forest", 1]]],
	[99, [["dark", 1]]],
]
## Ширина базового тайла (равнина). Остальные масштабируются так же; выступы (горы, деревья)
## торчат вверх и заходят на ряд выше — ряды рисуются сверху вниз, получается объём.
const BASE_TILE_WIDTH := 28.0
const OWNER_TINT_ALPHA := 0.35
## Ничья зона без нейтралов (зачищена) — чуть темнее.
const CLEARED_MODULATE := Color(0.65, 0.65, 0.72)

const MARKER_CASTLE := preload("res://assets/ui/map/marker_castle.png")
const MARKER_BANNER := preload("res://assets/ui/map/marker_banner.png")
const MARKER_HERO := preload("res://assets/ui/map/marker_hero.png")
const OUTLINE_SELECTED := preload("res://assets/ui/map/outline_selected.png")
const OUTLINE_TARGET := preload("res://assets/ui/map/outline_target.png")


var selected_zone := -1
## Отложенное центрирование на герое: ждём данные зон и раскрытия окна.
var _focus_pending := false
## Кэш местности по id зоны.
var _terrain_cache: Dictionary = {}


func _ready() -> void:
	# Карта 100×100 — разрешаем отдалить так, чтобы она помещалась целиком.
	min_zoom = 0.12
	WorldService.world_updated.connect(queue_redraw)
	WorldService.me_updated.connect(queue_redraw)


## Центрировать на герое, как только будут готовы данные и размер окна.
func request_focus() -> void:
	_focus_pending = true
	set_process(true)


func _process(_delta: float) -> void:
	if not _focus_pending:
		set_process(false)
		return
	var hero := WorldService.hero_zone()
	if size.y < MIN_FOCUS_HEIGHT or WorldService.get_zone(hero).is_empty():
		return
	_focus_pending = false
	center_on(hero)
	if selected_zone < 0:
		select(hero)


func center_on(zone_id: int) -> void:
	var zone := WorldService.get_zone(zone_id)
	if zone.is_empty():
		return
	center_on_point(HexGrid.center(int(zone.col), int(zone.row), HEX_SIZE))


func select(zone_id: int) -> void:
	selected_zone = zone_id
	queue_redraw()
	zone_selected.emit(zone_id)


func _on_click(screen_point: Vector2) -> void:
	var zone_id := _zone_at(screen_point)
	if zone_id >= 0:
		select(zone_id)


## Зона под точкой экрана (-1 — нет).
func _zone_at(screen_point: Vector2) -> int:
	var cols := WorldService.cols
	var rows := WorldService.rows
	if cols <= 0:
		return -1
	var map_point := (screen_point - pan) / zoom
	var approx_row := roundi(map_point.y / (HEX_SIZE * 1.5))
	var best := -1
	var best_distance := INF
	for row in range(approx_row - 1, approx_row + 2):
		if row < 0 or row >= rows:
			continue
		var approx_col := roundi(map_point.x / (HEX_SIZE * sqrt(3.0)) - 0.5 * (row & 1))
		for col in range(approx_col - 1, approx_col + 2):
			if col < 0 or col >= cols:
				continue
			var distance := map_point.distance_to(HexGrid.center(col, row, HEX_SIZE))
			if distance < best_distance:
				best_distance = distance
				best = row * cols + col
	return best if best_distance <= HEX_SIZE else -1




func _draw() -> void:
	var font := get_theme_default_font()
	if WorldService.zones.is_empty():
		draw_string(font, size * 0.5 - Vector2(80, 0), "Загрузка карты…", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		return
	var visible_rect := Rect2(-pan / zoom, size / zoom).grow(HEX_SIZE * 3.0)
	var radius := HEX_SIZE * zoom
	var tile_scale := sqrt(3.0) * radius / BASE_TILE_WIDTH
	var my_id := WorldService.my_id()

	# Зоны идут по рядам сверху вниз — нижние тайлы перекрывают выступы верхних.
	for zone: Variant in WorldService.zones:
		if zone == null:
			continue
		var map_center := HexGrid.center(int(zone.col), int(zone.row), HEX_SIZE)
		if not visible_rect.has_point(map_center):
			continue
		var center := map_center * zoom + pan
		var terrain := _terrain_texture(int(zone.id), int(zone.tier))
		var tile_size := terrain.get_size() * tile_scale
		var tile_rect := Rect2(Vector2(center.x - tile_size.x * 0.5, center.y + radius - tile_size.y), tile_size)
		var cleared: bool = zone.owner == null and (zone.neutral as Dictionary).is_empty()
		draw_texture_rect(terrain, tile_rect, false, CLEARED_MODULATE if cleared else Color.WHITE)
		if zone.owner != null:
			_draw_owner(center, radius, zone, my_id)
		if zone.castle:
			_draw_marker(MARKER_CASTLE, center, radius * 1.3)
		elif int(zone.garrison) > 0:
			_draw_marker(MARKER_BANNER, center + Vector2(radius * 0.45, -radius * 0.3), radius * 0.8)
		if zoom >= TIER_LABEL_ZOOM and not zone.castle:
			draw_string(font, center + Vector2(-4, 5) * zoom, str(int(zone.tier)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * zoom), Color(1, 1, 1, 0.7))

	_draw_move_targets(radius)
	if selected_zone >= 0:
		_draw_outline(selected_zone, radius, OUTLINE_SELECTED)
	_draw_march()
	_draw_heroes(radius, my_id)


## Заливка и рамка цветом владельца поверх местности.
func _draw_owner(center: Vector2, radius: float, zone: Dictionary, my_id: int) -> void:
	var owner := WorldService.get_player(zone.owner)
	var color := Color(str(owner.get("color", "#888888")))
	var mine := int(zone.owner) == my_id
	var corners := HexGrid.corners(center, radius * 0.86)
	draw_colored_polygon(corners, Color(color, OWNER_TINT_ALPHA if mine else OWNER_TINT_ALPHA * 0.8))
	corners.append(corners[0])
	draw_polyline(corners, color if mine else color.darkened(0.25), 2.0 if mine else 1.2)


## Маркер (замок, знамя, герой) по центру точки; size — высота маркера.
func _draw_marker(texture: Texture2D, center: Vector2, height: float, modulate := Color.WHITE) -> void:
	var marker_size := texture.get_size() * (height / texture.get_height())
	draw_texture_rect(texture, Rect2(center - marker_size * 0.5, marker_size), false, modulate)


func _draw_outline(zone_id: int, radius: float, texture: Texture2D) -> void:
	var zone := WorldService.get_zone(zone_id)
	if zone.is_empty():
		return
	var width := sqrt(3.0) * radius * 1.04
	var outline_size := Vector2(width, width * texture.get_height() / texture.get_width())
	draw_texture_rect(texture, Rect2(_screen_center(zone) - outline_size * 0.5, outline_size), false)


## Соседние с героем зоны — куда можно пойти.
func _draw_move_targets(radius: float) -> void:
	if WorldService.is_marching() or WorldService.hero_zone() < 0:
		return
	for zone_id in HexGrid.neighbors(WorldService.hero_zone(), WorldService.cols, WorldService.rows):
		_draw_outline(zone_id, radius * 0.94, OUTLINE_TARGET)


func _draw_march() -> void:
	if not WorldService.is_marching():
		return
	var march: Dictionary = WorldService.me.march
	var from := WorldService.get_zone(int(march.fromZone))
	var to := WorldService.get_zone(int(march.toZone))
	if from.is_empty() or to.is_empty():
		return
	var a := _screen_center(from)
	var b := _screen_center(to)
	draw_dashed_line(a, b, Color(1, 0.9, 0.4), 2.0, 6.0)
	_draw_marker(MARKER_HERO, a.lerp(b, WorldService.march_progress()), HEX_SIZE * zoom * 0.9)


## Мой герой — золотое кольцо, чужие — кольцо цвета игрока.
func _draw_heroes(radius: float, my_id: int) -> void:
	for player: Dictionary in WorldService.players.values():
		var zone := WorldService.get_zone(int(player.heroZone))
		var mine := int(player.id) == my_id
		if zone.is_empty() or (mine and WorldService.is_marching()):
			continue
		var point := _screen_center(zone) + Vector2(-radius * 0.35, radius * 0.35)
		var tint := Color.WHITE if mine else Color.WHITE.lerp(Color(str(player.color)), 0.7)
		_draw_marker(MARKER_HERO, point, radius * (0.9 if mine else 0.7), tint)


## Текстура местности зоны (детерминированно по id и уровню).
func _terrain_texture(zone_id: int, tier: int) -> Texture2D:
	if _terrain_cache.has(zone_id):
		return _terrain_cache[zone_id]
	var options: Array = TERRAIN_BY_TIER.back()[1]
	for entry: Array in TERRAIN_BY_TIER:
		if tier <= int(entry[0]):
			options = entry[1]
			break
	var total := 0
	for option: Array in options:
		total += int(option[1])
	var roll := posmod(hash(zone_id * 7919 + 13), total)
	var terrain: String = options[0][0]
	for option: Array in options:
		roll -= int(option[1])
		if roll < 0:
			terrain = option[0]
			break
	var texture: Texture2D = load(TILE_DIR + "terrain_" + terrain + ".png")
	_terrain_cache[zone_id] = texture
	return texture

func _screen_center(zone: Dictionary) -> Vector2:
	return HexGrid.center(int(zone.col), int(zone.row), HEX_SIZE) * zoom + pan
