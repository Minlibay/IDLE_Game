// Правила мира. Сервер — единственный источник правды: зоны, армии, бои, а также экономика
// замков (ресурсы, здания, обучение армии — см. kingdom.ts). Клиент только показывает состояние.
//
// Герой с главной армией стоит в зоне (heroZone). Поход — только в соседнюю зону, по таймеру.
// По прибытии:
//   • своя зона — просто переход;
//   • нейтральная зона — бой с нейтралами (победа = захват);
//   • чужая зона без гарнизона и без хозяина — захват без боя;
//   • чужая зона с гарнизоном и/или хозяином с армией — бой (PvP);
//   • чужой замок — набег: бой с армией замка; победа = часть ресурсов, щит защитнику.
// Идти в чужую или ничью зону можно только с армией: один герой зоны не захватывает.
// Проигравший на карте теряет всю армию, его герой возвращается в замок.
// Замок захватить нельзя; защитник замка при поражении теряет только часть армии.
// Союзники по гильдии (guilds.ts) друг на друга не нападают; победы на карте дают опыт гильдии.

import { randomUUID } from "node:crypto";
import type { Cost, GameData } from "../gameData.ts";
import type { Storage, StoredReport } from "../storage.ts";
import type { TreasureQuality } from "../treasures.ts";
import { addArmies, armyTotal, compact, hasUnits, isEmpty, subtractArmies, type Army } from "./army.ts";
import { applyLosses, resolveBattle, type BattleResult, type BattleSettings } from "./battle.ts";
import { generateZones, type GeneratorSettings, type Zone } from "./generator.ts";
import { hexDistance, isAdjacent } from "./grid.ts";
import { Guilds, type GuildSettings } from "./guilds.ts";
import {
  advanceKingdom, armyMultiplier, cancelOrder, consume, createKingdom, kingdomView, pay, recruit, refund,
  startBuilding, storageCapacity, type ExtraBonuses, type Kingdom, type KingdomSettings,
} from "./kingdom.ts";

export type March = { fromZone: number; toZone: number; startedAt: number; arrivesAt: number };

export type Player = {
  id: number;
  name: string;
  token: string;
  color: string;
  castleZone: number;
  heroZone: number;
  heroLevel: number;
  /** Главная армия — идёт вместе с героем. */
  army: Army;
  march: March | null;
  createdAt: number;
  /** Замок, его ресурсы и армия, стоящая в замке. */
  kingdom: Kingdom;
  /** Защита новичка: до этого момента замок нельзя атаковать. Снимается, если игрок сам нападает на игроков. */
  protectionUntil: number;
  /** Щит после набега: до этого момента замок нельзя атаковать. */
  shieldUntil: number;
  /** Сколько золота герой может внести в казну (копится со временем, зависит от уровня героя). */
  depositBank: number;
  depositUpdatedAt: number;
  /** Бонусы реликвий армии героя (ARMY_POWER, ARMY_ATTACK…), уже урезанные до armyGearCaps. */
  armyGear: Record<string, number>;
  /** Класс героя (сокровища выпадают только своего класса). null — ещё не сообщён. */
  classId: string | null;
  /** Сокровища игрока (именные, уникальные, сетовые). Позже — предметы Steam Inventory. */
  treasures: OwnedTreasure[];
  /** Засчитанное игровое время (мс) и момент последнего запроса игрока. */
  treasurePlaytimeMs: number;
  treasureLastSeen: number;
  /** При каком игровом времени следующая находка. */
  treasureNextMs: number;
  /** Номер недели и сколько сокровищ уже найдено за неё (недельный лимит). */
  treasureWeek: number;
  treasureWeekCount: number;
  treasureSavedPlaytimeMs: number;
  /** Гильдия игрока (null — без гильдии) и когда он из неё вышел (null — не выходил; для ожидания перед вступлением в новую). */
  guildId: number | null;
  guildLeftAt: number | null;
};

export type OwnedTreasure = { uid: string; itemId: string; at: number };

export type ReportSide = { name: string; tag?: string | null; army: Army; lost: Army; power: number; heroLevel: number };

export type ReportData = {
  kind: "battle" | "capture" | "zone_lost" | "info" | "raid" | "treasure";
  zoneId: number;
  tier: number;
  won: boolean;
  text: string;
  /** Тот же текст шаблоном «… {name} …» и его параметры: клиент переводит шаблон на язык игрока. */
  template?: string;
  args?: Record<string, string | number>;
  attacker?: ReportSide;
  defender?: ReportSide;
  /** Добыча набега (ресурсы). */
  loot?: Cost;
};

export type GameSettings = GeneratorSettings & BattleSettings & KingdomSettings & GuildSettings & {
  worldSeed: number;
  marchSeconds: number;
  castleMarchSeconds: number;
  castleMinDistance: number;
  maxNameLength: number;
  reportsKept: number;
  raidLootShare: number;
  raidProtectedResource: number;
  raidDefenderLoss: number;
  raidShieldHours: number;
  newbieProtectionHours: number;
  depositPerLevelPerMinute: number;
  depositBankMinutes: number;
  armyGearCaps: Readonly<Record<string, number>>;
  treasureDropMinutes: number;
  treasureWeeklyCap: number;
  treasureMaxGapSeconds: number;
  treasureWeights: Readonly<Record<TreasureQuality, number>>;
};

export class GameError extends Error {
  status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

const PLAYER_COLORS = [
  "#4a9dff", "#ff5f5f", "#5fd35f", "#ffb03a", "#b865ff", "#3fd0d0",
  "#ff7ac8", "#c8d34a", "#8a7bff", "#ff8f4a", "#4affa3", "#e0e0e0",
];

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** Номер недели (с понедельника, UTC): 1 января 1970 — четверг, поэтому +3 дня. */
export function weekIndex(now: number): number {
  return Math.floor((now / DAY_MS + 3) / 7);
}

export class Game {
  readonly zones: Zone[];
  readonly guilds: Guilds;
  private players = new Map<number, Player>();
  private playersByToken = new Map<string, Player>();
  private version: number;
  private nextPlayerId: number;
  private storage: Storage;
  private data: GameData;
  private settings: GameSettings;
  private random: () => number;

  constructor(storage: Storage, data: GameData, settings: GameSettings, random: () => number = Math.random, now = Date.now()) {
    this.storage = storage;
    this.data = data;
    this.settings = settings;
    this.random = random;

    const saved = storage.loadZones();
    const expected = settings.gridCols * settings.gridRows;
    const regenerate = saved.length !== expected;
    if (regenerate) {
      if (saved.length > 0) console.warn(`World size changed (${saved.length} -> ${expected} zones): regenerating, players get new castles`);
      this.zones = generateZones(data.units, settings, settings.worldSeed);
      storage.clearZones();
      storage.saveZones(this.zones);
      storage.setMeta("version", "0");
    } else {
      this.zones = saved.sort((a, b) => a.id - b.id);
    }
    this.version = Number(storage.getMeta("version") ?? 0);

    let maxId = 0;
    for (const player of storage.loadPlayers()) {
      this.migratePlayer(player, now);
      this.players.set(player.id, player);
      this.playersByToken.set(player.token, player);
      maxId = Math.max(maxId, player.id);
    }
    this.nextPlayerId = maxId + 1;
    if (regenerate) this.relocatePlayers();
    this.guilds = new Guilds(storage, settings, {
      getPlayer: (id) => this.players.get(id),
      findPlayerByName: (name) => [...this.players.values()].find((other) => other.name.toLowerCase() === name.toLowerCase()),
      savePlayer: (player) => this.savePlayer(player),
      syncKingdom: (player, time) => this.sync(player, time),
    });
  }

  get worldVersion(): number {
    return this.version;
  }

  // --- Чтение ----------------------------------------------------------------------

  getPlayerByToken(token: string): Player | undefined {
    return this.playersByToken.get(token);
  }

  getPlayer(id: number): Player | undefined {
    return this.players.get(id);
  }

  /** Состояние мира для клиента. since > 0 — только зоны, изменившиеся после этой версии; 0 — вся карта. */
  worldView(since: number, now: number) {
    return {
      version: this.version,
      cols: this.settings.gridCols,
      rows: this.settings.gridRows,
      tiers: this.settings.tiers,
      serverTime: now,
      zones: this.zones.filter((zone) => since <= 0 || zone.version > since).map((zone) => this.zoneView(zone)),
      players: [...this.players.values()].map((player) => ({
        id: player.id,
        name: player.name,
        color: player.color,
        castleZone: player.castleZone,
        heroZone: player.heroZone,
        heroLevel: player.heroLevel,
        marching: player.march !== null,
        protectedUntil: this.protectedUntil(player, now),
        guildId: player.guildId,
        guildTag: this.guilds.tagOf(player),
        guildColor: this.guilds.colorOf(player),
      })),
    };
  }

  zoneView(zone: Zone) {
    return {
      id: zone.id,
      col: zone.col,
      row: zone.row,
      tier: zone.tier,
      owner: zone.ownerId,
      castle: zone.isCastle,
      // Состав чужого гарнизона не раскрываем — только количество.
      garrison: Object.values(zone.garrison).reduce((sum, count) => sum + count, 0),
      neutral: zone.neutral,
      bonus: zone.bonus,
    };
  }

  /** Всё о самом игроке, включая замок. Состояние замка перед этим догоняется до now. */
  playerView(player: Player, now: number) {
    this.sync(player, now);
    this.accrueTreasureTime(player, now);
    const owned = this.zones.filter((zone) => zone.ownerId === player.id);
    const bonuses = this.territoryBonuses(player);
    return {
      id: player.id,
      name: player.name,
      color: player.color,
      castleZone: player.castleZone,
      heroZone: player.heroZone,
      heroLevel: player.heroLevel,
      army: player.army,
      march: player.march,
      zonesOwned: owned.length,
      bonuses,
      garrisons: owned.filter((zone) => !isEmpty(zone.garrison)).map((zone) => ({ zoneId: zone.id, army: zone.garrison })),
      kingdom: kingdomView(player.kingdom, this.data, this.settings, this.fieldArmies(player), this.armyBonuses(player)),
      armyGear: player.armyGear,
      classId: player.classId,
      treasures: player.treasures.map((treasure) => ({ uid: treasure.uid, itemId: treasure.itemId })),
      treasureNextMs: Math.max(0, player.treasureNextMs - player.treasurePlaytimeMs),
      treasureWeekCount: player.treasureWeek === weekIndex(now) ? player.treasureWeekCount : 0,
      treasureWeekCap: this.settings.treasureWeeklyCap,
      protectionUntil: player.protectionUntil,
      shieldUntil: player.shieldUntil,
      depositAvailable: Math.floor(this.depositBank(player, now)),
      incoming: this.incomingAttacks(player),
      guild: this.guilds.summary(player, now),
      guildInvites: this.guilds.invitesFor(player, now),
      reports: this.storage.loadReports(player.id, this.settings.reportsKept) satisfies StoredReport[],
      serverTime: now,
    };
  }

  // --- Действия игрока: аккаунт и армия на карте ----------------------------------

  register(rawName: string, now: number): Player {
    const name = rawName.trim();
    if (name.length === 0 || name.length > this.settings.maxNameLength) {
      throw new GameError(`Имя должно быть от 1 до ${this.settings.maxNameLength} символов`);
    }
    for (const other of this.players.values()) {
      if (other.name.toLowerCase() === name.toLowerCase()) throw new GameError("Это имя уже занято", 409);
    }
    const castle = this.pickCastleZone();
    const id = this.nextPlayerId++;
    const player: Player = {
      id,
      name,
      token: randomUUID(),
      color: PLAYER_COLORS[(id - 1) % PLAYER_COLORS.length],
      castleZone: castle.id,
      heroZone: castle.id,
      heroLevel: 1,
      army: {},
      march: null,
      createdAt: now,
      kingdom: createKingdom(this.data, now, this.settings),
      protectionUntil: now + this.settings.newbieProtectionHours * HOUR_MS,
      shieldUntil: 0,
      depositBank: 0,
      depositUpdatedAt: now,
      armyGear: {},
      classId: null,
      treasures: [],
      treasurePlaytimeMs: 0,
      treasureLastSeen: now,
      treasureNextMs: this.treasureIntervalMs(),
      treasureWeek: weekIndex(now),
      treasureWeekCount: 0,
      treasureSavedPlaytimeMs: 0,
      guildId: null,
      guildLeftAt: null,
    };
    castle.ownerId = id;
    castle.isCastle = true;
    castle.neutral = {};
    castle.garrison = {};
    this.players.set(id, player);
    this.playersByToken.set(player.token, player);
    this.touch(castle);
    this.savePlayer(player);
    return player;
  }

  /** Класс героя: сокровища выпадают только для него. Новый персонаж другого класса — новый класс. */
  setHeroClass(player: Player, classId: unknown): void {
    if (typeof classId !== "string" || !this.data.treasures.byClass[classId]) throw new GameError("Неизвестный класс героя");
    if (player.classId === classId) return;
    player.classId = classId;
    this.savePlayer(player);
  }

  setHeroLevel(player: Player, level: unknown, now: number): void {
    if (typeof level !== "number" || !Number.isInteger(level) || level < 1 || level > 10_000) {
      throw new GameError("Некорректный уровень героя");
    }
    this.depositBank(player, now); // накопленное по старому уровню
    player.heroLevel = level;
    this.savePlayer(player);
  }

  /**
   * Бонусы реликвий армии от клиента. Предметы пока живут в клиенте, поэтому сервер принимает
   * только известные бонусы и урезает каждый до armyGearCaps — подделка даёт не больше потолка.
   */
  setArmyGear(player: Player, input: unknown, now: number): void {
    if (typeof input !== "object" || input === null || Array.isArray(input)) throw new GameError("Некорректные бонусы армии");
    const gear: Record<string, number> = {};
    for (const [stat, value] of Object.entries(input as Record<string, unknown>)) {
      const cap = this.settings.armyGearCaps[stat];
      if (cap === undefined) throw new GameError("Неизвестный бонус армии: " + stat);
      if (typeof value !== "number" || !Number.isFinite(value) || value < 0) throw new GameError("Некорректное значение " + stat);
      if (value > 0) gear[stat] = Math.min(cap, Math.round(value * 10) / 10);
    }
    this.sync(player, now); // до смены бонусов — по старым (содержание, обучение)
    player.armyGear = gear;
    this.savePlayer(player);
  }

  /** Солдаты из армии замка выходят на карту вместе с героем. Герой должен быть в замке. */
  deploy(player: Player, army: Army, now: number): void {
    this.requireAtCastle(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    this.sync(player, now);
    if (!hasUnits(player.kingdom.army, army)) throw new GameError("В замке нет столько солдат");
    player.kingdom.army = subtractArmies(player.kingdom.army, army);
    player.army = addArmies(player.army, army);
    this.savePlayer(player);
  }

  /** Солдаты главной армии возвращаются в замок. Возвращает отозванные отряды. */
  recall(player: Player, army: Army, now: number): Army {
    this.requireAtCastle(player);
    if (!hasUnits(player.army, army)) throw new GameError("Столько солдат в армии нет");
    this.sync(player, now);
    player.army = subtractArmies(player.army, army);
    player.kingdom.army = addArmies(player.kingdom.army, army);
    this.savePlayer(player);
    return army;
  }

  move(player: Player, zoneId: unknown, now: number): void {
    if (player.march) throw new GameError("Герой уже в походе");
    const target = this.requireZone(zoneId);
    const from = this.zones[player.heroZone];
    if (target.id === from.id) throw new GameError("Герой уже здесь");
    if (!isAdjacent(from, target)) throw new GameError("Идти можно только в соседнюю зону");
    const enemy = target.ownerId !== null && target.ownerId !== player.id ? this.players.get(target.ownerId) : undefined;
    const raid = target.isCastle && enemy !== undefined;
    if (target.isCastle && target.ownerId !== player.id && !enemy) throw new GameError("Этот замок нельзя атаковать");
    if (enemy && this.guilds.areAllies(player, enemy)) throw new GameError("Нельзя нападать на союзника по гильдии");
    if (raid && this.protectedUntil(enemy, now) > now) throw new GameError("Замок под защитой — напасть пока нельзя");
    if (target.ownerId !== player.id && isEmpty(player.army)) {
      throw new GameError(raid ? "Для набега нужна армия" : "Без армии зону не занять — возьмите солдат из замка");
    }
    // Нападение на игрока снимает защиту новичка.
    if (enemy) player.protectionUntil = Math.min(player.protectionUntil, now);
    const seconds = raid ? this.settings.castleMarchSeconds : this.settings.marchSeconds;
    player.march = { fromZone: from.id, toZone: target.id, startedAt: now, arrivesAt: now + seconds * 1000 };
    this.savePlayer(player);
  }

  /** Оставить часть армии гарнизоном в текущей (своей) зоне. */
  garrison(player: Player, army: Army, now: number): void {
    const zone = this.requireOwnHeroZone(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    if (!hasUnits(player.army, army)) throw new GameError("Столько солдат в армии нет");
    this.sync(player, now);
    player.army = subtractArmies(player.army, army);
    zone.garrison = addArmies(zone.garrison, army);
    this.touch(zone);
    this.savePlayer(player);
  }

  /** Забрать солдат из гарнизона текущей зоны в главную армию. */
  withdraw(player: Player, army: Army, now: number): void {
    const zone = this.requireOwnHeroZone(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    if (!hasUnits(zone.garrison, army)) throw new GameError("Столько солдат в гарнизоне нет");
    this.sync(player, now);
    zone.garrison = subtractArmies(zone.garrison, army);
    player.army = addArmies(player.army, army);
    this.touch(zone);
    this.savePlayer(player);
  }

  // --- Действия игрока: замок -------------------------------------------------------

  build(player: Player, buildingId: unknown, now: number): void {
    this.sync(player, now);
    startBuilding(player.kingdom, this.data, String(buildingId ?? ""), now, this.settings);
    this.savePlayer(player);
  }

  recruit(player: Player, unitId: unknown, count: unknown, now: number): void {
    this.sync(player, now);
    recruit(player.kingdom, this.data, String(unitId ?? ""), Number(count), now, this.settings, this.fieldArmies(player), this.armyBonuses(player));
    this.savePlayer(player);
  }

  cancelTraining(player: Player, index: unknown, now: number): void {
    if (typeof index !== "number" || !Number.isInteger(index)) throw new GameError("Нет такого заказа");
    this.sync(player, now);
    cancelOrder(player.kingdom, this.data, index, now, this.settings, this.armyBonuses(player));
    this.savePlayer(player);
  }

  /** Герой ест и пьёт со склада. Возвращает, сколько реально взято. */
  consume(player: Player, amounts: unknown, now: number): Record<string, number> {
    if (typeof amounts !== "object" || amounts === null) throw new GameError("Некорректный запрос");
    const clean: Record<string, number> = {};
    for (const [resource, value] of Object.entries(amounts as Record<string, unknown>)) {
      if (typeof value === "number" && Number.isFinite(value) && value > 0) clean[resource] = Math.min(value, 10_000);
    }
    this.sync(player, now);
    const taken = consume(player.kingdom, clean);
    this.savePlayer(player);
    return taken;
  }

  /**
   * Герой вносит заработанное золото в казну. Золото героя считает клиент, поэтому объём
   * ограничен сервером: лимит копится со временем пропорционально уровню героя.
   */
  deposit(player: Player, amount: unknown, now: number): number {
    if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) throw new GameError("Укажите сумму");
    this.sync(player, now);
    const room = storageCapacity(player.kingdom, this.data, "gold") - (player.kingdom.resources.gold ?? 0);
    const accepted = Math.floor(Math.max(0, Math.min(amount, this.depositBank(player, now), room)));
    if (accepted <= 0) throw new GameError(room <= 0 ? "Казна полна" : "Лимит взносов исчерпан, подождите");
    player.depositBank -= accepted;
    refund(player.kingdom, { gold: accepted });
    this.savePlayer(player);
    return accepted;
  }

  /** Завершает походы, время которых пришло. Вызывается сервером раз в секунду. */
  tick(now: number): void {
    const arrived = [...this.players.values()]
      .filter((player) => player.march && player.march.arrivesAt <= now)
      .sort((a, b) => a.march!.arrivesAt - b.march!.arrivesAt);
    for (const player of arrived) this.arrive(player, player.march!.arrivesAt);
  }

  // --- Внутреннее: замок ------------------------------------------------------------

  /** Догоняет экономику замка до now (производство, стройка, обучение, содержание армии). */
  private sync(player: Player, now: number): void {
    advanceKingdom(player.kingdom, this.data, now, this.settings, this.fieldArmies(player), this.armyBonuses(player));
  }

  /** Всё, что усиливает армию на сервере помимо зданий: захваченные зоны, реликвии армии, бонус гильдии. */
  private armyBonuses(player: Player): ExtraBonuses {
    const bonuses = this.territoryBonuses(player);
    for (const [stat, value] of Object.entries(player.armyGear)) bonuses[stat] = (bonuses[stat] ?? 0) + value;
    const guildBonus = this.guilds.bonusPercent(player);
    if (guildBonus > 0) bonuses.ARMY_POWER = (bonuses.ARMY_POWER ?? 0) + guildBonus;
    return bonuses;
  }

  /** Бонусы захваченных зон: стат → проценты (действуют и на армию сервера, и на героя в клиенте). */
  private territoryBonuses(player: Player): ExtraBonuses {
    const bonuses: ExtraBonuses = {};
    for (const zone of this.zones) {
      if (zone.ownerId !== player.id) continue;
      bonuses[zone.bonus.stat] = Math.round(((bonuses[zone.bonus.stat] ?? 0) + zone.bonus.value) * 10) / 10;
    }
    return bonuses;
  }

  // --- Внутреннее: сокровища по игровому времени -----------------------------------

  private treasureIntervalMs(): number {
    return this.settings.treasureDropMinutes * 60_000;
  }

  /**
   * Засчитывает игровое время: пока игра запущена, клиент регулярно спрашивает сервер, и промежутки
   * между запросами (не длиннее treasureMaxGapSeconds) складываются. Закрытая игра время не копит.
   */
  private accrueTreasureTime(player: Player, now: number): void {
    const gap = now - player.treasureLastSeen;
    player.treasureLastSeen = Math.max(player.treasureLastSeen, now);
    if (gap > 0 && gap <= this.settings.treasureMaxGapSeconds * 1000) player.treasurePlaytimeMs += gap;
    const found = this.rollTreasures(player, now);
    if (found || player.treasurePlaytimeMs - player.treasureSavedPlaytimeMs >= 60_000) {
      player.treasureSavedPlaytimeMs = player.treasurePlaytimeMs;
      this.savePlayer(player);
    }
  }

  /** Выдаёт сокровища, время которых пришло (с недельным лимитом). true — что-то выпало. */
  private rollTreasures(player: Player, now: number): boolean {
    const week = weekIndex(now);
    if (player.treasureWeek !== week) {
      player.treasureWeek = week;
      player.treasureWeekCount = 0;
    }
    const pool = player.classId ? this.data.treasures.byClass[player.classId] : undefined;
    let found = false;
    while (player.treasurePlaytimeMs >= player.treasureNextMs) {
      if (!pool || player.treasureWeekCount >= this.settings.treasureWeeklyCap) {
        // Лимит недели исчерпан (или класс неизвестен): время копится дальше, находка — позже.
        player.treasureNextMs = player.treasurePlaytimeMs + this.treasureIntervalMs();
        break;
      }
      const info = this.pickTreasure(pool);
      player.treasureNextMs += this.treasureIntervalMs();
      if (!info) break;
      player.treasures.push({ uid: randomUUID(), itemId: info.id, at: now });
      player.treasureWeekCount += 1;
      found = true;
      const quality = { named: "Именной", unique: "Уникальный", legendary: "Легендарный" }[info.quality];
      this.report(player.id, now, { kind: "treasure", zoneId: player.castleZone, tier: 0, won: true, ...say("Найдено сокровище: {item} ({quality})", { item: info.name, quality }) });
    }
    return found;
  }

  private pickTreasure(pool: Record<TreasureQuality, { id: string; name: string; quality: TreasureQuality }[]>) {
    const weights = this.settings.treasureWeights;
    const qualities = (Object.keys(weights) as TreasureQuality[]).filter((quality) => pool[quality]?.length > 0);
    const total = qualities.reduce((sum, quality) => sum + weights[quality], 0);
    if (total <= 0) return undefined;
    let roll = this.random() * total;
    let quality = qualities[qualities.length - 1];
    for (const candidate of qualities) {
      roll -= weights[candidate];
      if (roll < 0) {
        quality = candidate;
        break;
      }
    }
    const list = pool[quality];
    return list[Math.floor(this.random() * list.length)];
  }

  /** Армии игрока вне замка: главная армия и гарнизоны (они тоже едят). */
  private fieldArmies(player: Player): Army[] {
    const armies = [player.army];
    for (const zone of this.zones) if (zone.ownerId === player.id && !isEmpty(zone.garrison)) armies.push(zone.garrison);
    return armies;
  }

  private protectedUntil(player: Player, now: number): number {
    const until = Math.max(player.protectionUntil, player.shieldUntil);
    return until > now ? until : 0;
  }

  private depositBank(player: Player, now: number): number {
    const rate = this.settings.depositPerLevelPerMinute * player.heroLevel;
    const elapsed = Math.max(0, now - player.depositUpdatedAt) / 60_000;
    player.depositBank = Math.min(rate * this.settings.depositBankMinutes, player.depositBank + rate * elapsed);
    player.depositUpdatedAt = Math.max(player.depositUpdatedAt, now);
    return player.depositBank;
  }

  /** Кто идёт на зоны игрока (предупреждение о нападении). */
  private incomingAttacks(player: Player) {
    const result = [];
    for (const other of this.players.values()) {
      if (other.id === player.id || !other.march) continue;
      const zone = this.zones[other.march.toZone];
      if (zone.ownerId !== player.id) continue;
      result.push({
        attacker: other.name,
        attackerId: other.id,
        attackerTag: this.guilds.tagOf(other),
        fromZone: other.march.fromZone,
        toZone: zone.id,
        castle: zone.isCastle,
        arrivesAt: other.march.arrivesAt,
        units: armyTotal(other.army),
      });
    }
    return result.sort((a, b) => a.arrivesAt - b.arrivesAt);
  }

  // --- Внутреннее: походы и бои -------------------------------------------------------

  private arrive(player: Player, now: number): void {
    const march = player.march!;
    player.march = null;
    const zone = this.zones[march.toZone];
    this.sync(player, now);

    if (zone.ownerId === player.id) {
      player.heroZone = zone.id;
      this.savePlayer(player);
      return;
    }

    // Страховка для походов, начатых до проверки армии в move().
    if (isEmpty(player.army)) {
      this.abortMarch(player, march, zone, now, "Поход сорван: без армии зону не занять");
      return;
    }

    if (zone.ownerId === null) {
      this.arriveAtNeutral(player, zone, now);
      return;
    }

    const defender = this.players.get(zone.ownerId);
    if (!defender) {
      this.abortMarch(player, march, zone, now, "Поход сорван: зону нельзя захватить");
      return;
    }
    // Пока шли, могли оказаться в одной гильдии.
    if (this.guilds.areAllies(player, defender)) {
      this.abortMarch(player, march, zone, now, "Поход сорван: {name} — ваш союзник по гильдии", { name: defender.name });
      return;
    }
    this.sync(defender, now);
    if (zone.isCastle) this.arriveAtCastle(player, defender, march, zone, now);
    else this.arriveAtEnemy(player, defender, zone, now);
  }

  private abortMarch(player: Player, march: March, zone: Zone, now: number, text: string, args: Record<string, string | number> = {}): void {
    player.heroZone = this.zones[march.fromZone].ownerId === player.id ? march.fromZone : player.castleZone;
    this.savePlayer(player);
    this.report(player.id, now, { kind: "info", zoneId: zone.id, tier: zone.tier, won: false, ...say(text, args) });
  }

  private arriveAtNeutral(player: Player, zone: Zone, now: number): void {
    if (isEmpty(zone.neutral)) {
      this.capture(zone, player);
      this.report(player.id, now, { kind: "capture", zoneId: zone.id, tier: zone.tier, won: true, ...say("Зона занята без боя") });
      return;
    }
    const result = this.battle(player.army, player.heroLevel, this.attackMultiplier(player), zone.neutral, 0, 1);
    const sides = this.reportSides(player, player.army, player.heroLevel, null, zone.neutral, 0, result);
    if (result.attackerWins) {
      player.army = result.attackerArmy;
      zone.neutral = {};
      this.capture(zone, player);
      this.guilds.addWinXp(player, this.settings.guildXpPerNeutralTier * zone.tier, now);
      this.report(player.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, ...say("Нейтралы разбиты, зона захвачена"), ...sides });
    } else {
      zone.neutral = result.defenderArmy;
      player.army = {};
      this.sendHome(player);
      this.touch(zone);
      this.report(player.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: false, ...say("Армия погибла в бою с нейтралами, герой вернулся в замок"), ...sides });
    }
  }

  private arriveAtEnemy(attacker: Player, defender: Player, zone: Zone, now: number): void {
    const defenderPresent = defender.heroZone === zone.id && defender.march === null;
    const defenderArmy = addArmies(zone.garrison, defenderPresent ? defender.army : {});

    if (isEmpty(defenderArmy) && !defenderPresent) {
      this.capture(zone, attacker);
      this.report(attacker.id, now, { kind: "capture", zoneId: zone.id, tier: zone.tier, won: true, ...say("Зона игрока {name} была без защиты — захвачена", { name: defender.name }) });
      this.report(defender.id, now, { kind: "zone_lost", zoneId: zone.id, tier: zone.tier, won: false, ...say("{name} занял вашу зону без боя (гарнизона не было)", { name: attacker.name }) });
      return;
    }

    const defenderHero = defenderPresent ? defender.heroLevel : 0;
    const result = this.battle(attacker.army, attacker.heroLevel, this.attackMultiplier(attacker), defenderArmy, defenderHero, this.defenseMultiplier(defender));
    const sides = this.reportSides(attacker, attacker.army, attacker.heroLevel, defender, defenderArmy, defenderHero, result);

    if (result.attackerWins) {
      this.guilds.addWinXp(attacker, this.settings.guildXpPerPvpWin, now);
      attacker.army = result.attackerArmy;
      zone.garrison = {};
      if (defenderPresent) {
        defender.army = {};
        this.sendHome(defender);
      }
      this.capture(zone, attacker);
      this.report(attacker.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, ...say("Победа над {name}, зона захвачена", { name: defender.name }), ...sides });
      this.report(defender.id, now, {
        kind: "zone_lost", zoneId: zone.id, tier: zone.tier, won: false,
        ...say(defenderPresent ? "{name} разбил вашу армию, герой вернулся в замок" : "{name} разбил гарнизон и захватил зону", { name: attacker.name }),
        ...sides,
      });
    } else {
      this.guilds.addWinXp(defender, this.settings.guildXpPerPvpWin, now);
      attacker.army = {};
      this.sendHome(attacker);
      if (defenderPresent) [zone.garrison, defender.army] = splitSurvivors(result.defenderArmy, [zone.garrison, defender.army]);
      else zone.garrison = result.defenderArmy;
      this.savePlayer(defender);
      this.touch(zone);
      this.report(attacker.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: false, ...say("Поражение от {name}: армия погибла, герой вернулся в замок", { name: defender.name }), ...sides });
      this.report(defender.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, ...say("Атака {name} отбита", { name: attacker.name }), ...sides });
    }
  }

  /**
   * Набег на замок. Защищают армия замка и герой с армией, если он дома.
   * Победа атакующего: он забирает долю ресурсов сверх неприкосновенного запаса, защитник теряет
   * часть армии (не всю) и получает щит. Поражение атакующего: его армия гибнет, как обычно.
   */
  private arriveAtCastle(attacker: Player, defender: Player, march: March, zone: Zone, now: number): void {
    if (this.protectedUntil(defender, now) > now) {
      this.abortMarch(attacker, march, zone, now, "Замок {name} под щитом — набег сорван", { name: defender.name });
      return;
    }
    const kingdom = defender.kingdom;
    const heroHome = defender.heroZone === zone.id && defender.march === null;
    const heroArmy = heroHome ? defender.army : {};
    const defenderArmy = addArmies(kingdom.army, heroArmy);
    const defenderHero = heroHome ? defender.heroLevel : 0;
    const result = this.battle(attacker.army, attacker.heroLevel, this.attackMultiplier(attacker), defenderArmy, defenderHero, this.defenseMultiplier(defender));

    if (result.attackerWins) {
      this.guilds.addWinXp(attacker, this.settings.guildXpPerPvpWin, now);
      const losses = applyLosses(defenderArmy, this.settings.raidDefenderLoss);
      this.splitCastleDefenders(defender, heroHome, losses.remaining);
      const loot = this.plunder(kingdom);
      pay(kingdom, loot);
      refund(attacker.kingdom, loot);
      defender.shieldUntil = now + this.settings.raidShieldHours * HOUR_MS;
      attacker.army = result.attackerArmy;
      attacker.heroZone = this.zones[march.fromZone].ownerId === attacker.id ? march.fromZone : attacker.castleZone;
      const sides = this.reportSides(attacker, result.attackerArmy, attacker.heroLevel, defender, defenderArmy, defenderHero, result);
      sides.attacker.army = addArmies(result.attackerArmy, result.attackerLost);
      sides.defender.lost = losses.lost;
      this.savePlayer(attacker);
      this.savePlayer(defender);
      this.report(attacker.id, now, { kind: "raid", zoneId: zone.id, tier: zone.tier, won: true, ...say("Набег на замок {name} удался", { name: defender.name }), loot, ...sides });
      this.report(defender.id, now, { kind: "raid", zoneId: zone.id, tier: zone.tier, won: false, ...say("{name} разграбил ваш замок. Замок под щитом {hours} ч", { name: attacker.name, hours: this.settings.raidShieldHours }), loot, ...sides });
    } else {
      this.guilds.addWinXp(defender, this.settings.guildXpPerPvpWin, now);
      const sides = this.reportSides(attacker, attacker.army, attacker.heroLevel, defender, defenderArmy, defenderHero, result);
      attacker.army = {};
      this.sendHome(attacker);
      this.splitCastleDefenders(defender, heroHome, result.defenderArmy);
      this.savePlayer(defender);
      this.report(attacker.id, now, { kind: "raid", zoneId: zone.id, tier: zone.tier, won: false, ...say("Набег на замок {name} отбит: армия погибла, герой вернулся в замок", { name: defender.name }), ...sides });
      this.report(defender.id, now, { kind: "raid", zoneId: zone.id, tier: zone.tier, won: true, ...say("Набег {name} на ваш замок отбит", { name: attacker.name }), ...sides });
    }
  }

  /** Выжившие защитники замка: армия замка + армия героя, если он был дома (иначе она в бою не участвовала). */
  private splitCastleDefenders(defender: Player, heroHome: boolean, survivors: Army): void {
    if (heroHome) [defender.kingdom.army, defender.army] = splitSurvivors(survivors, [defender.kingdom.army, defender.army]);
    else defender.kingdom.army = survivors;
  }

  /** Добыча: доля каждого ресурса сверх неприкосновенного запаса. */
  private plunder(kingdom: Kingdom): Cost {
    const loot: Cost = {};
    for (const resource of this.data.kingdom.resources) {
      const spare = (kingdom.resources[resource] ?? 0) - this.settings.raidProtectedResource;
      const amount = Math.floor(Math.max(0, spare) * this.settings.raidLootShare);
      if (amount > 0) loot[resource] = amount;
    }
    return loot;
  }

  private attackMultiplier(player: Player): number {
    return armyMultiplier(player.kingdom, this.data, "attack", this.armyBonuses(player));
  }

  private defenseMultiplier(player: Player): number {
    return armyMultiplier(player.kingdom, this.data, "defense", this.armyBonuses(player));
  }

  private battle(
    attackerArmy: Army, attackerHero: number, attackerMultiplier: number,
    defenderArmy: Army, defenderHero: number, defenderMultiplier: number,
  ): BattleResult {
    return resolveBattle(
      { army: attackerArmy, heroLevel: attackerHero, multiplier: attackerMultiplier },
      { army: defenderArmy, heroLevel: defenderHero, multiplier: defenderMultiplier },
      this.data.units,
      this.settings,
      this.random,
    );
  }

  /** Стороны боя для отчёта; defender = null — нейтралы. */
  private reportSides(
    attacker: Player, attackerArmy: Army, attackerHero: number,
    defender: Player | null, defenderArmy: Army, defenderHero: number,
    result: BattleResult,
  ): { attacker: ReportSide; defender: ReportSide } {
    return {
      attacker: {
        name: attacker.name, tag: this.guilds.tagOf(attacker),
        army: attackerArmy, lost: result.attackerLost, power: Math.round(result.attackerPower), heroLevel: attackerHero,
      },
      defender: {
        name: defender?.name ?? "Нейтралы", tag: defender ? this.guilds.tagOf(defender) : null,
        army: defenderArmy, lost: result.defenderLost, power: Math.round(result.defenderPower), heroLevel: defenderHero,
      },
    };
  }

  private capture(zone: Zone, player: Player): void {
    zone.ownerId = player.id;
    zone.garrison = {};
    player.heroZone = zone.id;
    this.touch(zone);
    this.savePlayer(player);
  }

  private sendHome(player: Player): void {
    player.heroZone = player.castleZone;
    player.march = null;
    this.savePlayer(player);
  }

  /** Старые сохранения (до экономики на сервере): добавляет замок и защиту. */
  private migratePlayer(player: Player, now: number): void {
    player.kingdom ??= createKingdom(this.data, now, this.settings);
    player.protectionUntil ??= player.createdAt + this.settings.newbieProtectionHours * HOUR_MS;
    player.shieldUntil ??= 0;
    player.depositBank ??= 0;
    player.depositUpdatedAt ??= now;
    player.armyGear ??= {};
    player.classId ??= null;
    player.treasures ??= [];
    player.treasurePlaytimeMs ??= 0;
    player.treasureLastSeen ??= now;
    player.treasureNextMs ??= this.treasureIntervalMs();
    player.treasureWeek ??= weekIndex(now);
    player.treasureWeekCount ??= 0;
    player.treasureSavedPlaytimeMs ??= player.treasurePlaytimeMs;
    player.guildId ??= null;
    player.guildLeftAt ??= null;
  }

  /** После пересоздания мира: каждому игроку — новый замок; армия и замок сохраняются. */
  private relocatePlayers(): void {
    for (const player of this.players.values()) {
      const castle = this.pickCastleZone();
      castle.ownerId = player.id;
      castle.isCastle = true;
      castle.neutral = {};
      castle.garrison = {};
      player.castleZone = castle.id;
      player.heroZone = castle.id;
      player.march = null;
      this.touch(castle);
      this.savePlayer(player);
    }
  }

  private pickCastleZone(): Zone {
    const castles = this.zones.filter((zone) => zone.isCastle);
    const candidates = this.zones.filter((zone) =>
      zone.tier === 1 && zone.ownerId === null &&
      castles.every((castle) => hexDistance(castle, zone) >= this.settings.castleMinDistance));
    if (candidates.length === 0) throw new GameError("На карте не осталось места для нового замка", 503);
    return candidates[Math.floor(this.random() * candidates.length)];
  }

  private requireZone(zoneId: unknown): Zone {
    if (typeof zoneId !== "number" || !Number.isInteger(zoneId) || zoneId < 0 || zoneId >= this.zones.length) {
      throw new GameError("Нет такой зоны", 404);
    }
    return this.zones[zoneId];
  }

  private requireAtCastle(player: Player): void {
    if (player.march || player.heroZone !== player.castleZone) {
      throw new GameError("Герой должен стоять в своём замке");
    }
  }

  private requireOwnHeroZone(player: Player): Zone {
    if (player.march) throw new GameError("Герой в походе");
    const zone = this.zones[player.heroZone];
    if (zone.ownerId !== player.id) throw new GameError("Это не ваша зона");
    if (zone.isCastle) throw new GameError("В замке армия стоит без гарнизона");
    return zone;
  }

  private touch(zone: Zone): void {
    this.version += 1;
    zone.version = this.version;
    this.storage.saveZone(zone);
    this.storage.setMeta("version", String(this.version));
  }

  private savePlayer(player: Player): void {
    this.storage.savePlayer(player);
  }

  private report(playerId: number, now: number, data: ReportData): void {
    this.storage.addReport(playerId, now, data, this.settings.reportsKept);
  }
}

/** Текст отчёта из шаблона «… {name} …» — вместе с самим шаблоном, чтобы клиент мог его перевести. */
function say(template: string, args: Record<string, string | number> = {}): Pick<ReportData, "text" | "template" | "args"> {
  const text = template.replace(/\{(\w+)\}/g, (_, key: string) => String(args[key] ?? ""));
  return { text, template, args };
}

/**
 * Выжившие делятся между группами пропорционально их исходному составу.
 * Например, защитники зоны = гарнизон + армия хозяина.
 */
export function splitSurvivors(survivors: Army, groups: Army[]): Army[] {
  const result: Army[] = groups.map(() => ({}));
  for (const [id, alive] of Object.entries(survivors)) {
    const total = groups.reduce((sum, group) => sum + (group[id] ?? 0), 0);
    let left = alive;
    groups.forEach((group, index) => {
      const share = index === groups.length - 1 ? left : total > 0 ? Math.round((alive * (group[id] ?? 0)) / total) : 0;
      const taken = Math.min(left, share);
      result[index][id] = taken;
      left -= taken;
    });
  }
  return result.map(compact);
}
