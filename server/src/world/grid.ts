// Шестиугольная сетка «odd-r»: нечётные ряды сдвинуты вправо на полклетки.
// Клиент рисует карту по тем же правилам (scenes/world/world_map_view.gd).

export type Hex = { col: number; row: number };

// Соседи для чётных и нечётных рядов: [dcol, drow].
const DIRECTIONS: readonly (readonly [number, number])[][] = [
  [[+1, 0], [0, -1], [-1, -1], [-1, 0], [-1, +1], [0, +1]],
  [[+1, 0], [+1, -1], [0, -1], [-1, 0], [0, +1], [+1, +1]],
];

export function zoneId(col: number, row: number, cols: number): number {
  return row * cols + col;
}

export function zoneCoords(id: number, cols: number): Hex {
  return { col: id % cols, row: Math.floor(id / cols) };
}

function toCube(hex: Hex): { x: number; y: number; z: number } {
  const x = hex.col - (hex.row - (hex.row & 1)) / 2;
  const z = hex.row;
  return { x, y: -x - z, z };
}

export function hexDistance(a: Hex, b: Hex): number {
  const ca = toCube(a);
  const cb = toCube(b);
  return Math.max(Math.abs(ca.x - cb.x), Math.abs(ca.y - cb.y), Math.abs(ca.z - cb.z));
}

export function neighbors(hex: Hex, cols: number, rows: number): Hex[] {
  const result: Hex[] = [];
  for (const [dc, dr] of DIRECTIONS[hex.row & 1]) {
    const col = hex.col + dc;
    const row = hex.row + dr;
    if (col >= 0 && row >= 0 && col < cols && row < rows) {
      result.push({ col, row });
    }
  }
  return result;
}

export function isAdjacent(a: Hex, b: Hex): boolean {
  return hexDistance(a, b) === 1;
}

/** Уровень зоны: 1 на краях, `tiers` в центре карты. */
export function tierOf(hex: Hex, cols: number, rows: number, tiers: number): number {
  const center: Hex = { col: Math.floor(cols / 2), row: Math.floor(rows / 2) };
  const maxDistance = Math.max(
    hexDistance(center, { col: 0, row: 0 }),
    hexDistance(center, { col: cols - 1, row: 0 }),
    hexDistance(center, { col: 0, row: rows - 1 }),
    hexDistance(center, { col: cols - 1, row: rows - 1 }),
  );
  const closeness = 1 - hexDistance(center, hex) / maxDistance;
  return Math.min(tiers, Math.max(1, 1 + Math.floor(closeness * tiers)));
}
