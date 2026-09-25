// Армия — словарь «id отряда → количество». Утилиты без побочных эффектов.

import type { UnitStats } from "../gameData.ts";

export type Army = Record<string, number>;

export function armyTotal(army: Army): number {
  let total = 0;
  for (const count of Object.values(army)) total += count;
  return total;
}

export function isEmpty(army: Army): boolean {
  return armyTotal(army) <= 0;
}

export function addArmies(a: Army, b: Army): Army {
  const result: Army = { ...a };
  for (const [id, count] of Object.entries(b)) {
    result[id] = (result[id] ?? 0) + count;
  }
  return compact(result);
}

/** a − b. Бросает ошибку, если в `a` не хватает солдат. */
export function subtractArmies(a: Army, b: Army): Army {
  const result: Army = { ...a };
  for (const [id, count] of Object.entries(b)) {
    const have = result[id] ?? 0;
    if (have < count) throw new Error(`not enough ${id}: have ${have}, need ${count}`);
    result[id] = have - count;
  }
  return compact(result);
}

export function hasUnits(army: Army, required: Army): boolean {
  return Object.entries(required).every(([id, count]) => (army[id] ?? 0) >= count);
}

/** Убирает нулевые записи. */
export function compact(army: Army): Army {
  const result: Army = {};
  for (const [id, count] of Object.entries(army)) {
    if (count > 0) result[id] = count;
  }
  return result;
}

export function attackOf(army: Army, units: Record<string, UnitStats>): number {
  let total = 0;
  for (const [id, count] of Object.entries(army)) total += (units[id]?.attack ?? 0) * count;
  return total;
}

export function defenseOf(army: Army, units: Record<string, UnitStats>): number {
  let total = 0;
  for (const [id, count] of Object.entries(army)) total += (units[id]?.defense ?? 0) * count;
  return total;
}

/** Проверяет армию из запроса клиента: только известные отряды, целые неотрицательные числа. */
export function sanitizeArmy(input: unknown, units: Record<string, UnitStats>, maxPerType: number): Army {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new Error("units must be an object");
  }
  const result: Army = {};
  for (const [id, value] of Object.entries(input as Record<string, unknown>)) {
    if (!(id in units)) throw new Error(`unknown unit: ${id}`);
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > maxPerType) {
      throw new Error(`invalid count for ${id}`);
    }
    if (value > 0) result[id] = value;
  }
  return result;
}
