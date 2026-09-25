// Генерация мира: gridCols × gridRows зон, уровни от краёв к центру, нейтральные армии и бонусы.

import type { UnitStats } from "../gameData.ts";
import type { Army } from "./army.ts";
import { tierOf, zoneCoords } from "./grid.ts";

export type ZoneBonus = { stat: string; value: number };

export type Zone = {
  id: number;
  col: number;
  row: number;
  tier: number;
  ownerId: number | null;
  /** Замок игрока — захватить нельзя. */
  isCastle: boolean;
  garrison: Army;
  neutral: Army;
  bonus: ZoneBonus;
  /** Версия мира, когда зона менялась в последний раз (для /api/world?since=). */
  version: number;
};

export type GeneratorSettings = {
  gridCols: number;
  gridRows: number;
  tiers: number;
  neutralBasePower: number;
  neutralPowerGrowth: number;
  neutralSpread: number;
  bonusPerTier: number;
  bonusStats: readonly string[];
};

/** Детерминированный генератор случайных чисел (mulberry32): мир одинаков при одном seed. */
export function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Состав нейтралов по уровню: [отряд, доля бюджета силы].
const NEUTRAL_MIX: readonly { maxTier: number; mix: readonly [string, number][] }[] = [
  { maxTier: 2, mix: [["militia", 1]] },
  { maxTier: 4, mix: [["militia", 0.5], ["spearman", 0.5]] },
  { maxTier: 6, mix: [["spearman", 0.5], ["archer", 0.5]] },
  { maxTier: 8, mix: [["spearman", 0.3], ["archer", 0.4], ["knight", 0.3]] },
  { maxTier: Infinity, mix: [["archer", 0.4], ["knight", 0.6]] },
];

export function neutralArmy(
  tier: number,
  units: Record<string, UnitStats>,
  settings: GeneratorSettings,
  random: () => number,
): Army {
  const spread = 1 + (random() * 2 - 1) * settings.neutralSpread;
  const budget = settings.neutralBasePower * settings.neutralPowerGrowth ** (tier - 1) * spread;
  const mix = NEUTRAL_MIX.find((entry) => tier <= entry.maxTier)!.mix;
  const army: Army = {};
  for (const [unitId, share] of mix) {
    const stats = units[unitId];
    if (!stats) continue;
    army[unitId] = Math.max(1, Math.round((budget * share) / (stats.attack + stats.defense)));
  }
  return army;
}

export function generateZones(units: Record<string, UnitStats>, settings: GeneratorSettings, seed: number): Zone[] {
  const random = seededRandom(seed);
  const zones: Zone[] = [];
  const count = settings.gridCols * settings.gridRows;
  for (let id = 0; id < count; id++) {
    const { col, row } = zoneCoords(id, settings.gridCols);
    const tier = tierOf({ col, row }, settings.gridCols, settings.gridRows, settings.tiers);
    const stat = settings.bonusStats[Math.floor(random() * settings.bonusStats.length)];
    zones.push({
      id,
      col,
      row,
      tier,
      ownerId: null,
      isCastle: false,
      garrison: {},
      neutral: neutralArmy(tier, units, settings, random),
      bonus: { stat, value: Math.round(settings.bonusPerTier * tier * 10) / 10 },
      version: 0,
    });
  }
  return zones;
}
