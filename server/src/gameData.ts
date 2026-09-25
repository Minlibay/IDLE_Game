// Характеристики отрядов. Единый источник — .tres в Godot-проекте;
// server/data/game_data.json генерируется инструментом tools/export_server_data.gd.

import { readFileSync } from "node:fs";

export type UnitStats = {
  attack: number;
  defense: number;
  housing: number;
};

export type GameData = {
  units: Record<string, UnitStats>;
};

export function loadGameData(path: string): GameData {
  const raw = JSON.parse(readFileSync(path, "utf8")) as Partial<GameData>;
  if (!raw.units || Object.keys(raw.units).length === 0) {
    throw new Error(`No units in ${path}. Run tools/export_server_data.gd in Godot.`);
  }
  return { units: raw.units };
}
