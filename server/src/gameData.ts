// Игровые данные сервера. Единый источник — .tres в Godot-проекте;
// server/data/game_data.json генерируется инструментом tools/export_server_data.gd.

import { readFileSync } from "node:fs";

export type Cost = Record<string, number>;

export type UnitStats = {
  attack: number;
  defense: number;
  housing: number;
  upkeep: number;
  cost: Cost;
  trainTime: number;
  requiredBuilding: string;
  requiredLevel: number;
};

export type BuildingStats = {
  maxLevel: number;
  townHall: boolean;
  baseCost: Cost;
  costGrowth: number;
  baseBuildTime: number;
  buildTimeGrowth: number;
  produces: string;
  productionPerLevel: number;
  storagePerLevel: number;
  armyCapacityPerLevel: number;
  modifiers: { stat: string; value: number }[];
};

export type KingdomConfig = {
  resources: string[];
  startResources: Record<string, number>;
  baseStorage: number;
  goldStorageMultiplier: number;
  maxQueue: number;
  starvingPowerMultiplier: number;
};

export type GameData = {
  units: Record<string, UnitStats>;
  buildings: Record<string, BuildingStats>;
  kingdom: KingdomConfig;
};

export function loadGameData(path: string): GameData {
  const raw = JSON.parse(readFileSync(path, "utf8")) as Partial<GameData>;
  if (!raw.units || Object.keys(raw.units).length === 0 || !raw.buildings || !raw.kingdom) {
    throw new Error(`Incomplete ${path}. Run tools/export_server_data.gd in Godot.`);
  }
  return { units: raw.units, buildings: raw.buildings, kingdom: raw.kingdom };
}
