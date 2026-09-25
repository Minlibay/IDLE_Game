// Каталог сокровищ (именные, уникальные, сетовые предметы) — тот же data/treasures/*.json, что читает игра
// (scripts/items/treasure_catalog.gd). id строятся одинаково: часть сета = "<id сета>_<слот>".
// Сервер выдаёт сокровища по игровому времени (см. Game) и хранит, кому что принадлежит.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type TreasureQuality = "named" | "unique" | "legendary";

export type TreasureInfo = { id: string; name: string; quality: TreasureQuality; classId: string };

export type TreasureCatalog = {
  /** classId → quality → предметы. */
  byClass: Record<string, Record<TreasureQuality, TreasureInfo[]>>;
  byId: Record<string, TreasureInfo>;
};

const SET_SLOTS = ["helmet", "shoulders", "armor", "legs", "boots"];

type RawCatalog = {
  class: string;
  slot_names?: Record<string, string>;
  sets?: { id: string; of: string }[];
  items?: { id: string; name: string; quality?: string }[];
};

export function emptyTreasureCatalog(): TreasureCatalog {
  return { byClass: {}, byId: {} };
}

export function loadTreasureCatalog(dir: string): TreasureCatalog {
  const catalog = emptyTreasureCatalog();
  if (!existsSync(dir)) return catalog;
  for (const file of readdirSync(dir).filter((name) => name.endsWith(".json")).sort()) {
    const raw = JSON.parse(readFileSync(join(dir, file), "utf8")) as RawCatalog;
    const classId = raw.class;
    const groups: Record<TreasureQuality, TreasureInfo[]> = { named: [], unique: [], legendary: [] };
    for (const set of raw.sets ?? []) {
      for (const slot of SET_SLOTS) {
        groups.legendary.push({ id: `${set.id}_${slot}`, name: `${raw.slot_names?.[slot] ?? slot} ${set.of}`, quality: "legendary", classId });
      }
    }
    for (const item of raw.items ?? []) {
      const quality: TreasureQuality = item.quality === "unique" ? "unique" : "named";
      groups[quality].push({ id: item.id, name: item.name, quality, classId });
    }
    catalog.byClass[classId] = groups;
    for (const list of Object.values(groups)) for (const info of list) catalog.byId[info.id] = info;
  }
  return catalog;
}
