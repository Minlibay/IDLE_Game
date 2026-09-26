// Игровые данные сервера. Единый источник — .tres в Godot-проекте;
// server/data/game_data.json генерируется инструментом tools/export_server_data.gd.

import { readFileSync } from "node:fs";
import { emptyTreasureCatalog, loadTreasureCatalog, type TreasureCatalog } from "./treasures.ts";

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

/** Бонус гильдии из data/guild/guild.json: ранги 1…values.length, значение ранга — values[ранг-1] (%). */
export type GuildPerk = { id: string; name: string; stat: string; values: number[]; branch: string; index: number };

export type GuildCatalog = {
  pointsPerLevel: number;
  /** Сколько очков нужно вложить в ветку, чтобы открыть её бонус № index. */
  tierPoints: number[];
  perks: Record<string, GuildPerk>;
  branches: { id: string; perks: string[] }[];
  /** Названия регионов карты (сетка regionGrid × regionGrid, по строкам). */
  regions: string[];
};

export type GameData = {
  units: Record<string, UnitStats>;
  buildings: Record<string, BuildingStats>;
  kingdom: KingdomConfig;
  /** Сокровища из data/treasures/*.json (тот же каталог, что у игры). */
  treasures: TreasureCatalog;
  /** Дерево бонусов гильдий и регионы (тот же файл, что у игры). */
  guild: GuildCatalog;
};

export function loadGameData(path: string, treasuresDir?: string, guildPath?: string): GameData {
  const raw = JSON.parse(readFileSync(path, "utf8")) as Partial<GameData>;
  if (!raw.units || Object.keys(raw.units).length === 0 || !raw.buildings || !raw.kingdom) {
    throw new Error(`Incomplete ${path}. Run tools/export_server_data.gd in Godot.`);
  }
  const treasures = treasuresDir ? loadTreasureCatalog(treasuresDir) : emptyTreasureCatalog();
  const guild = guildPath ? loadGuildCatalog(guildPath) : emptyGuildCatalog();
  return { units: raw.units, buildings: raw.buildings, kingdom: raw.kingdom, treasures, guild };
}

export function emptyGuildCatalog(): GuildCatalog {
  return { pointsPerLevel: 0, tierPoints: [], perks: {}, branches: [], regions: [] };
}

type RawGuildFile = {
  perk_points_per_level: number;
  branch_tier_points: number[];
  branches: { id: string; perks: { id: string; name: string; stat: string; values: number[] }[] }[];
  regions: string[];
};

export function loadGuildCatalog(path: string): GuildCatalog {
  const raw = JSON.parse(readFileSync(path, "utf8")) as RawGuildFile;
  const catalog: GuildCatalog = { pointsPerLevel: raw.perk_points_per_level, tierPoints: raw.branch_tier_points, perks: {}, branches: [], regions: raw.regions };
  for (const branch of raw.branches) {
    catalog.branches.push({ id: branch.id, perks: branch.perks.map((perk) => perk.id) });
    branch.perks.forEach((perk, index) => {
      catalog.perks[perk.id] = { id: perk.id, name: perk.name, stat: perk.stat, values: perk.values, branch: branch.id, index };
    });
  }
  return catalog;
}
