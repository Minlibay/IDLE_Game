class_name HexGrid
extends RefCounted
## Шестиугольная сетка «odd-r» (нечётные ряды сдвинуты вправо) — те же правила, что на сервере
## (server/src/world/grid.ts). Шестиугольники «остриём вверх».

const DIRECTIONS := [
	[[1, 0], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1]],
	[[1, 0], [1, -1], [0, -1], [-1, 0], [0, 1], [1, 1]],
]


static func neighbors(zone_id: int, cols: int, rows: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if cols <= 0:
		return result
	var col := zone_id % cols
	var row := zone_id / cols
	for direction: Array in DIRECTIONS[row & 1]:
		var c: int = col + direction[0]
		var r: int = row + direction[1]
		if c >= 0 and r >= 0 and c < cols and r < rows:
			result.append(r * cols + c)
	return result


static func is_adjacent(a: int, b: int, cols: int, rows: int) -> bool:
	return neighbors(a, cols, rows).has(b)


## Центр шестиугольника в координатах карты (size — радиус).
static func center(col: int, row: int, size: float) -> Vector2:
	return Vector2(size * sqrt(3.0) * (col + 0.5 * (row & 1)), size * 1.5 * row)


static func corners(center_point: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center_point + Vector2(cos(angle), sin(angle)) * size)
	return points
