// Расчёт боя. Атака атакующего (армия + герой) против защиты обороняющегося.
// Проигравший теряет ВСЮ армию (герой выживает — это решает Game).
// Победитель теряет долю (сила проигравшего / сила победителя) ^ lossExponent.

import type { UnitStats } from "../gameData.ts";
import { attackOf, compact, defenseOf, type Army } from "./army.ts";

export type BattleSide = {
  army: Army;
  /** 0 — героя нет (нейтралы, пустой гарнизон). */
  heroLevel: number;
  /** Множитель силы отрядов (бонусы зданий, голод). По умолчанию 1. */
  multiplier?: number;
};

export type BattleSettings = {
  heroPowerPerLevel: number;
  lossExponent: number;
  luck: number;
};

export type BattleResult = {
  attackerWins: boolean;
  attackerPower: number;
  defenderPower: number;
  /** Что осталось у сторон после боя. */
  attackerArmy: Army;
  defenderArmy: Army;
  attackerLost: Army;
  defenderLost: Army;
};

export function resolveBattle(
  attacker: BattleSide,
  defender: BattleSide,
  units: Record<string, UnitStats>,
  settings: BattleSettings,
  random: () => number = Math.random,
): BattleResult {
  const roll = () => 1 + (random() * 2 - 1) * settings.luck;
  const attackerPower = (attackOf(attacker.army, units) * (attacker.multiplier ?? 1) + attacker.heroLevel * settings.heroPowerPerLevel) * roll();
  const defenderPower = (defenseOf(defender.army, units) * (defender.multiplier ?? 1) + defender.heroLevel * settings.heroPowerPerLevel) * roll();
  const attackerWins = attackerPower > defenderPower;

  const winnerPower = Math.max(attackerPower, defenderPower);
  const loserPower = Math.min(attackerPower, defenderPower);
  const winnerLossRatio = winnerPower > 0 ? Math.min(1, (loserPower / winnerPower) ** settings.lossExponent) : 0;

  const attackerOutcome = attackerWins ? applyLosses(attacker.army, winnerLossRatio) : wipe(attacker.army);
  const defenderOutcome = attackerWins ? wipe(defender.army) : applyLosses(defender.army, winnerLossRatio);

  return {
    attackerWins,
    attackerPower,
    defenderPower,
    attackerArmy: attackerOutcome.remaining,
    defenderArmy: defenderOutcome.remaining,
    attackerLost: attackerOutcome.lost,
    defenderLost: defenderOutcome.lost,
  };
}

/** Каждый отряд теряет долю ratio (округление вверх). */
export function applyLosses(army: Army, ratio: number): { remaining: Army; lost: Army } {
  const remaining: Army = {};
  const lost: Army = {};
  for (const [id, count] of Object.entries(army)) {
    const dead = Math.min(count, Math.ceil(count * ratio - 1e-9));
    lost[id] = dead;
    remaining[id] = count - dead;
  }
  return { remaining: compact(remaining), lost: compact(lost) };
}

function wipe(army: Army): { remaining: Army; lost: Army } {
  return { remaining: {}, lost: compact({ ...army }) };
}
