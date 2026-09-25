// Экономика замка на сервере: ресурсы и казна, здания и стройка, армия замка и её обучение, содержание.
// Состояние «догоняется» лениво (advanceKingdom) при каждом обращении — в т.ч. пока игрок оффлайн.
// Клиент только показывает это состояние и присылает действия (build / recruit / cancel / consume).

import type { Cost, GameData } from "../gameData.ts";
import { addArmies, armyTotal, attackOf, defenseOf, type Army } from "./army.ts";

export type TrainingOrder = { id: string; count: number; total: number; nextAt: number; perUnitMs: number };

export type Construction = { id: string; level: number; startedAt: number; finishAt: number };

export type Kingdom = {
  resources: Record<string, number>;
  levels: Record<string, number>;
  construction: Construction | null;
  /** Армия, стоящая в замке (защищает его при набеге). */
  army: Army;
  queue: TrainingOrder[];
  starving: boolean;
  updatedAt: number;
};

export type KingdomSettings = {
  /** Множитель скорости стройки/обучения и стартовых ресурсов (1 — обычно; для тестов больше). */
  devSpeed: number;
};

export class KingdomError extends Error {}

const MS_PER_MINUTE = 60_000;

export function createKingdom(data: GameData, now: number, settings: KingdomSettings): Kingdom {
  const resources: Record<string, number> = {};
  for (const id of data.kingdom.resources) resources[id] = (data.kingdom.startResources[id] ?? 0) * settings.devSpeed;
  const levels: Record<string, number> = {};
  for (const [id, building] of Object.entries(data.buildings)) if (building.townHall) levels[id] = 1;
  return { resources, levels, construction: null, army: {}, queue: [], starving: false, updatedAt: now };
}

// --- Чтение ----------------------------------------------------------------------

export function levelOf(kingdom: Kingdom, buildingId: string): number {
  return kingdom.levels[buildingId] ?? 0;
}

export function townHallLevel(kingdom: Kingdom, data: GameData): number {
  for (const [id, building] of Object.entries(data.buildings)) if (building.townHall) return levelOf(kingdom, id);
  return 999;
}

export function storageCapacity(kingdom: Kingdom, data: GameData, resourceId: string): number {
  let capacity = data.kingdom.baseStorage;
  for (const [id, building] of Object.entries(data.buildings)) capacity += building.storagePerLevel * levelOf(kingdom, id);
  return resourceId === "gold" ? capacity * data.kingdom.goldStorageMultiplier : capacity;
}

export function productionPerMinute(kingdom: Kingdom, data: GameData, resourceId: string): number {
  let total = 0;
  for (const [id, building] of Object.entries(data.buildings)) {
    if (building.produces === resourceId) total += building.productionPerLevel * levelOf(kingdom, id);
  }
  return total;
}

/**
 * Бонусы, которые сервер знает помимо зданий (например, захваченные зоны): стат → проценты.
 * Таланты героя считает клиент, поэтому на армию сервера они не влияют.
 */
export type ExtraBonuses = Record<string, number>;

/** Бонус зданий (+ extra) к стату в процентах, например TRAINING_SPEED или ARMY_POWER. */
export function buildingBonus(kingdom: Kingdom, data: GameData, stat: string, extra: ExtraBonuses = {}): number {
  let total = extra[stat] ?? 0;
  for (const [id, building] of Object.entries(data.buildings)) {
    const level = levelOf(kingdom, id);
    if (level <= 0) continue;
    for (const modifier of building.modifiers) if (modifier.stat === stat) total += modifier.value * level;
  }
  return total;
}

export function armyCapacity(kingdom: Kingdom, data: GameData): number {
  let capacity = 0;
  for (const [id, building] of Object.entries(data.buildings)) capacity += building.armyCapacityPerLevel * levelOf(kingdom, id);
  return capacity;
}

/** Занятые места: вся армия игрока (замок + на карте + гарнизоны) + очередь обучения. */
export function housingUsed(kingdom: Kingdom, data: GameData, otherArmies: Army[]): number {
  let used = 0;
  const all = otherArmies.reduce((sum, army) => addArmies(sum, army), kingdom.army);
  for (const [id, count] of Object.entries(all)) used += (data.units[id]?.housing ?? 1) * count;
  for (const order of kingdom.queue) used += (data.units[order.id]?.housing ?? 1) * order.count;
  return used;
}

export function upkeepPerMinute(data: GameData, armies: Army[]): number {
  let total = 0;
  for (const army of armies) {
    for (const [id, count] of Object.entries(army)) total += (data.units[id]?.upkeep ?? 0) * count;
  }
  return total;
}

/** Множитель силы армии: бонусы зданий (Кузница, Конюшня), зон и голод. */
export function armyPowerMultiplier(kingdom: Kingdom, data: GameData, extra: ExtraBonuses = {}): number {
  const bonus = 1 + buildingBonus(kingdom, data, "ARMY_POWER", extra) / 100;
  return bonus * (kingdom.starving ? data.kingdom.starvingPowerMultiplier : 1);
}

export function buildingCost(data: GameData, buildingId: string, targetLevel: number): Cost {
  const building = data.buildings[buildingId];
  const multiplier = building.costGrowth ** (targetLevel - 1);
  const cost: Cost = {};
  for (const [resource, amount] of Object.entries(building.baseCost)) cost[resource] = Math.round(amount * multiplier);
  return cost;
}

export function buildTimeMs(data: GameData, buildingId: string, targetLevel: number, settings: KingdomSettings): number {
  const building = data.buildings[buildingId];
  return (building.baseBuildTime * building.buildTimeGrowth ** (targetLevel - 1) * 1000) / settings.devSpeed;
}

export function trainTimeMs(kingdom: Kingdom, data: GameData, unitId: string, settings: KingdomSettings, extra: ExtraBonuses = {}): number {
  const speed = 1 + buildingBonus(kingdom, data, "TRAINING_SPEED", extra) / 100;
  return (data.units[unitId].trainTime * 1000) / speed / settings.devSpeed;
}

export function canAfford(kingdom: Kingdom, cost: Cost): boolean {
  return Object.entries(cost).every(([resource, amount]) => (kingdom.resources[resource] ?? 0) >= amount);
}

export function multiplyCost(cost: Cost, count: number): Cost {
  const result: Cost = {};
  for (const [resource, amount] of Object.entries(cost)) result[resource] = amount * count;
  return result;
}

// --- Время -----------------------------------------------------------------------

/**
 * Догоняет состояние до момента now: производство (с потолком склада), содержание армии,
 * завершение стройки и обучение солдат. События обрабатываются по порядку, поэтому
 * достроенная ферма начинает производить ровно с момента завершения.
 * otherArmies — армии игрока вне замка (едят тоже).
 */
export function advanceKingdom(
  kingdom: Kingdom, data: GameData, now: number, settings: KingdomSettings, otherArmies: Army[] = [], extra: ExtraBonuses = {},
): void {
  let guard = 0;
  while (kingdom.updatedAt < now && guard++ < 10_000) {
    let next = now;
    if (kingdom.construction) next = Math.min(next, kingdom.construction.finishAt);
    if (kingdom.queue.length > 0) next = Math.min(next, kingdom.queue[0].nextAt);
    next = Math.max(next, kingdom.updatedAt);
    produce(kingdom, data, next - kingdom.updatedAt, otherArmies);
    kingdom.updatedAt = next;

    if (kingdom.construction && kingdom.construction.finishAt <= next) {
      kingdom.levels[kingdom.construction.id] = kingdom.construction.level;
      kingdom.construction = null;
    }
    const order = kingdom.queue[0];
    if (order && order.nextAt <= next) {
      kingdom.army[order.id] = (kingdom.army[order.id] ?? 0) + 1;
      order.count -= 1;
      if (order.count > 0) {
        order.perUnitMs = trainTimeMs(kingdom, data, order.id, settings, extra);
        order.nextAt = next + order.perUnitMs;
      } else {
        kingdom.queue.shift();
        const following = kingdom.queue[0];
        if (following) {
          following.perUnitMs = trainTimeMs(kingdom, data, following.id, settings, extra);
          following.nextAt = next + following.perUnitMs;
        }
      }
    }
  }
}

function produce(kingdom: Kingdom, data: GameData, ms: number, otherArmies: Army[]): void {
  if (ms <= 0) return;
  const minutes = ms / MS_PER_MINUTE;
  for (const resource of data.kingdom.resources) {
    const rate = productionPerMinute(kingdom, data, resource);
    if (rate <= 0) continue;
    const current = kingdom.resources[resource] ?? 0;
    const capacity = storageCapacity(kingdom, data, resource);
    kingdom.resources[resource] = Math.max(current, Math.min(capacity, current + rate * minutes));
  }
  // Содержание армии: солдаты едят со склада. Нет еды — армия слабеет (не умирает).
  const upkeep = upkeepPerMinute(data, [kingdom.army, ...otherArmies]) * minutes;
  if (upkeep > 0) {
    const food = kingdom.resources.food ?? 0;
    kingdom.starving = food < upkeep;
    kingdom.resources.food = Math.max(0, food - upkeep);
  } else {
    kingdom.starving = false;
  }
}

// --- Действия --------------------------------------------------------------------

export function startBuilding(kingdom: Kingdom, data: GameData, buildingId: string, now: number, settings: KingdomSettings): void {
  const building = data.buildings[buildingId];
  if (!building) throw new KingdomError("Нет такого здания");
  if (kingdom.construction) throw new KingdomError("Строители заняты");
  const level = levelOf(kingdom, buildingId);
  if (level >= building.maxLevel) throw new KingdomError("Максимальный уровень");
  const allowed = building.townHall ? building.maxLevel : Math.min(building.maxLevel, townHallLevel(kingdom, data));
  if (level >= allowed) throw new KingdomError(`Нужна Ратуша ${level + 1}-го уровня`);
  const cost = buildingCost(data, buildingId, level + 1);
  if (!canAfford(kingdom, cost)) throw new KingdomError("Не хватает ресурсов");
  pay(kingdom, cost);
  kingdom.construction = { id: buildingId, level: level + 1, startedAt: now, finishAt: now + buildTimeMs(data, buildingId, level + 1, settings) };
}

export function recruit(
  kingdom: Kingdom, data: GameData, unitId: string, count: number, now: number, settings: KingdomSettings,
  otherArmies: Army[], extra: ExtraBonuses = {},
): void {
  const unit = data.units[unitId];
  if (!unit) throw new KingdomError("Нет такого отряда");
  if (!Number.isInteger(count) || count <= 0 || count > 10_000) throw new KingdomError("Укажите количество");
  if (unit.requiredBuilding && levelOf(kingdom, unit.requiredBuilding) < unit.requiredLevel) {
    throw new KingdomError("Нужно здание более высокого уровня");
  }
  if (kingdom.queue.length >= data.kingdom.maxQueue) throw new KingdomError("Очередь обучения заполнена");
  const free = armyCapacity(kingdom, data) - housingUsed(kingdom, data, otherArmies);
  if (count * unit.housing > free) throw new KingdomError(`Не хватает места в армии (свободно ${Math.max(0, free)})`);
  const cost = multiplyCost(unit.cost, count);
  if (!canAfford(kingdom, cost)) throw new KingdomError("Не хватает ресурсов");
  pay(kingdom, cost);
  const perUnitMs = trainTimeMs(kingdom, data, unitId, settings, extra);
  // Обучается только первый заказ; следующие получают nextAt, когда до них дойдёт очередь.
  const nextAt = kingdom.queue.length === 0 ? now + perUnitMs : 0;
  kingdom.queue.push({ id: unitId, count, total: count, nextAt, perUnitMs });
}

/** Отмена заказа: ресурсы за необученных солдат возвращаются полностью. */
export function cancelOrder(kingdom: Kingdom, data: GameData, index: number, now: number, settings: KingdomSettings, extra: ExtraBonuses = {}): void {
  const order = kingdom.queue[index];
  if (!order) throw new KingdomError("Нет такого заказа");
  refund(kingdom, multiplyCost(data.units[order.id].cost, order.count));
  kingdom.queue.splice(index, 1);
  if (index === 0 && kingdom.queue[0]) {
    kingdom.queue[0].perUnitMs = trainTimeMs(kingdom, data, kingdom.queue[0].id, settings, extra);
    kingdom.queue[0].nextAt = now + kingdom.queue[0].perUnitMs;
  }
}

/** Герой ест и пьёт со склада (потребности). Берётся не больше, чем есть. */
export function consume(kingdom: Kingdom, amounts: Record<string, number>): Record<string, number> {
  const taken: Record<string, number> = {};
  for (const [resource, amount] of Object.entries(amounts)) {
    if (resource !== "food" && resource !== "water") continue;
    const take = Math.min(Math.max(0, amount), kingdom.resources[resource] ?? 0);
    kingdom.resources[resource] = (kingdom.resources[resource] ?? 0) - take;
    taken[resource] = take;
  }
  return taken;
}

export function pay(kingdom: Kingdom, cost: Cost): void {
  for (const [resource, amount] of Object.entries(cost)) kingdom.resources[resource] = (kingdom.resources[resource] ?? 0) - amount;
}

export function refund(kingdom: Kingdom, cost: Cost): void {
  for (const [resource, amount] of Object.entries(cost)) kingdom.resources[resource] = (kingdom.resources[resource] ?? 0) + amount;
}

/** Состояние замка для клиента. */
export function kingdomView(kingdom: Kingdom, data: GameData, settings: KingdomSettings, otherArmies: Army[], extra: ExtraBonuses = {}) {
  const production: Record<string, number> = {};
  const storage: Record<string, number> = {};
  for (const resource of data.kingdom.resources) {
    production[resource] = productionPerMinute(kingdom, data, resource);
    storage[resource] = storageCapacity(kingdom, data, resource);
  }
  const multiplier = armyPowerMultiplier(kingdom, data, extra);
  const trainTimes: Record<string, number> = {};
  for (const unitId of Object.keys(data.units)) trainTimes[unitId] = trainTimeMs(kingdom, data, unitId, settings, extra);
  return {
    resources: kingdom.resources,
    levels: kingdom.levels,
    construction: kingdom.construction,
    production,
    storage,
    army: {
      units: kingdom.army,
      queue: kingdom.queue,
      starving: kingdom.starving,
      capacity: armyCapacity(kingdom, data),
      housingUsed: housingUsed(kingdom, data, otherArmies),
      upkeep: upkeepPerMinute(data, [kingdom.army, ...otherArmies]),
      attack: attackOf(kingdom.army, data.units) * multiplier,
      defense: defenseOf(kingdom.army, data.units) * multiplier,
      total: armyTotal(kingdom.army),
      powerMultiplier: multiplier,
      trainTimes,
    },
  };
}
