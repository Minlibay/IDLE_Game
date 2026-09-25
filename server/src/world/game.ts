// Правила мировой карты. Сервер — единственный источник правды о зонах, армиях на карте и боях.
//
// Герой с главной армией стоит в зоне (heroZone). Поход — только в соседнюю зону, по таймеру.
// По прибытии:
//   • своя зона — просто переход;
//   • нейтральная зона — бой с нейтралами (победа = захват);
//   • чужая зона без гарнизона и без хозяина — захват без боя;
//   • чужая зона с гарнизоном и/или хозяином с армией — бой (PvP).
// Проигравший теряет всю армию, его герой возвращается в замок. Замки захватить нельзя.

import { randomUUID } from "node:crypto";
import type { UnitStats } from "../gameData.ts";
import type { Storage, StoredReport } from "../storage.ts";
import { addArmies, hasUnits, isEmpty, subtractArmies, type Army } from "./army.ts";
import { resolveBattle, type BattleResult, type BattleSettings } from "./battle.ts";
import { generateZones, type GeneratorSettings, type Zone } from "./generator.ts";
import { hexDistance, isAdjacent } from "./grid.ts";

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
};

export type ReportSide = { name: string; army: Army; lost: Army; power: number; heroLevel: number };

export type ReportData = {
  kind: "battle" | "capture" | "zone_lost" | "info";
  zoneId: number;
  tier: number;
  won: boolean;
  text: string;
  attacker?: ReportSide;
  defender?: ReportSide;
};

export type GameSettings = GeneratorSettings & BattleSettings & {
  worldSeed: number;
  marchSeconds: number;
  castleMinDistance: number;
  maxNameLength: number;
  reportsKept: number;
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

export class Game {
  readonly zones: Zone[];
  private players = new Map<number, Player>();
  private playersByToken = new Map<string, Player>();
  private version: number;
  private nextPlayerId: number;
  private storage: Storage;
  private units: Record<string, UnitStats>;
  private settings: GameSettings;
  private random: () => number;

  constructor(storage: Storage, units: Record<string, UnitStats>, settings: GameSettings, random: () => number = Math.random) {
    this.storage = storage;
    this.units = units;
    this.settings = settings;
    this.random = random;

    const saved = storage.loadZones();
    if (saved.length === 0) {
      this.zones = generateZones(units, settings, settings.worldSeed);
      storage.saveZones(this.zones);
      storage.setMeta("version", "0");
    } else {
      this.zones = saved.sort((a, b) => a.id - b.id);
    }
    this.version = Number(storage.getMeta("version") ?? 0);

    let maxId = 0;
    for (const player of storage.loadPlayers()) {
      this.players.set(player.id, player);
      this.playersByToken.set(player.token, player);
      maxId = Math.max(maxId, player.id);
    }
    this.nextPlayerId = maxId + 1;
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
  worldView(since: number) {
    return {
      version: this.version,
      cols: this.settings.gridCols,
      rows: this.settings.gridRows,
      tiers: this.settings.tiers,
      zones: this.zones.filter((zone) => since <= 0 || zone.version > since).map((zone) => this.zoneView(zone)),
      players: [...this.players.values()].map((player) => ({
        id: player.id,
        name: player.name,
        color: player.color,
        castleZone: player.castleZone,
        heroZone: player.heroZone,
        heroLevel: player.heroLevel,
        marching: player.march !== null,
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

  playerView(player: Player) {
    const owned = this.zones.filter((zone) => zone.ownerId === player.id);
    const bonuses: Record<string, number> = {};
    for (const zone of owned) {
      bonuses[zone.bonus.stat] = Math.round(((bonuses[zone.bonus.stat] ?? 0) + zone.bonus.value) * 10) / 10;
    }
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
      reports: this.storage.loadReports(player.id, this.settings.reportsKept) satisfies StoredReport[],
      serverTime: Date.now(),
    };
  }

  // --- Действия игрока --------------------------------------------------------------

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

  setHeroLevel(player: Player, level: unknown): void {
    if (typeof level !== "number" || !Number.isInteger(level) || level < 1 || level > 10_000) {
      throw new GameError("Некорректный уровень героя");
    }
    player.heroLevel = level;
    this.savePlayer(player);
  }

  /** Армия из замка (клиент) выходит на карту. Герой должен быть в замке. */
  deploy(player: Player, army: Army): void {
    this.requireAtCastle(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    player.army = addArmies(player.army, army);
    this.savePlayer(player);
  }

  /** Армия с карты возвращается в замок (клиент). Возвращает отозванные отряды. */
  recall(player: Player, army: Army): Army {
    this.requireAtCastle(player);
    if (!hasUnits(player.army, army)) throw new GameError("Столько солдат в армии нет");
    player.army = subtractArmies(player.army, army);
    this.savePlayer(player);
    return army;
  }

  move(player: Player, zoneId: unknown, now: number): void {
    if (player.march) throw new GameError("Герой уже в походе");
    const target = this.requireZone(zoneId);
    const from = this.zones[player.heroZone];
    if (target.id === from.id) throw new GameError("Герой уже здесь");
    if (!isAdjacent(from, target)) throw new GameError("Идти можно только в соседнюю зону");
    if (target.isCastle && target.ownerId !== player.id) throw new GameError("Чужой замок захватить нельзя");
    player.march = {
      fromZone: from.id,
      toZone: target.id,
      startedAt: now,
      arrivesAt: now + this.settings.marchSeconds * 1000,
    };
    this.savePlayer(player);
  }

  /** Оставить часть армии гарнизоном в текущей (своей) зоне. */
  garrison(player: Player, army: Army): void {
    const zone = this.requireOwnHeroZone(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    if (!hasUnits(player.army, army)) throw new GameError("Столько солдат в армии нет");
    player.army = subtractArmies(player.army, army);
    zone.garrison = addArmies(zone.garrison, army);
    this.touch(zone);
    this.savePlayer(player);
  }

  /** Забрать солдат из гарнизона текущей зоны в главную армию. */
  withdraw(player: Player, army: Army): void {
    const zone = this.requireOwnHeroZone(player);
    if (isEmpty(army)) throw new GameError("Выберите отряды");
    if (!hasUnits(zone.garrison, army)) throw new GameError("Столько солдат в гарнизоне нет");
    zone.garrison = subtractArmies(zone.garrison, army);
    player.army = addArmies(player.army, army);
    this.touch(zone);
    this.savePlayer(player);
  }

  /** Завершает походы, время которых пришло. Вызывается сервером раз в секунду. */
  tick(now: number): void {
    const arrived = [...this.players.values()]
      .filter((player) => player.march && player.march.arrivesAt <= now)
      .sort((a, b) => a.march!.arrivesAt - b.march!.arrivesAt);
    for (const player of arrived) this.arrive(player, now);
  }

  // --- Внутреннее -------------------------------------------------------------------

  private arrive(player: Player, now: number): void {
    const march = player.march!;
    player.march = null;
    const zone = this.zones[march.toZone];

    if (zone.ownerId === player.id) {
      player.heroZone = zone.id;
      this.savePlayer(player);
      return;
    }

    if (zone.ownerId === null) {
      this.arriveAtNeutral(player, zone, now);
      return;
    }

    const defender = this.players.get(zone.ownerId);
    if (zone.isCastle || !defender) {
      player.heroZone = march.fromZone;
      this.savePlayer(player);
      this.report(player.id, now, { kind: "info", zoneId: zone.id, tier: zone.tier, won: false, text: "Поход сорван: зону нельзя захватить" });
      return;
    }
    this.arriveAtEnemy(player, defender, zone, now);
  }

  private arriveAtNeutral(player: Player, zone: Zone, now: number): void {
    if (isEmpty(zone.neutral)) {
      this.capture(zone, player);
      this.report(player.id, now, { kind: "capture", zoneId: zone.id, tier: zone.tier, won: true, text: "Зона занята без боя" });
      return;
    }
    const result = this.battle(player.army, player.heroLevel, zone.neutral, 0);
    const sides = this.reportSides(player.name, player.army, player.heroLevel, "Нейтралы", zone.neutral, 0, result);
    if (result.attackerWins) {
      player.army = result.attackerArmy;
      zone.neutral = {};
      this.capture(zone, player);
      this.report(player.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, text: "Нейтралы разбиты, зона захвачена", ...sides });
    } else {
      zone.neutral = result.defenderArmy;
      player.army = {};
      this.sendHome(player);
      this.touch(zone);
      this.report(player.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: false, text: "Армия погибла в бою с нейтралами, герой вернулся в замок", ...sides });
    }
  }

  private arriveAtEnemy(attacker: Player, defender: Player, zone: Zone, now: number): void {
    const defenderPresent = defender.heroZone === zone.id && defender.march === null;
    const defenderArmy = addArmies(zone.garrison, defenderPresent ? defender.army : {});

    if (isEmpty(defenderArmy) && !defenderPresent) {
      this.capture(zone, attacker);
      this.report(attacker.id, now, { kind: "capture", zoneId: zone.id, tier: zone.tier, won: true, text: `Зона игрока ${defender.name} была без защиты — захвачена` });
      this.report(defender.id, now, { kind: "zone_lost", zoneId: zone.id, tier: zone.tier, won: false, text: `${attacker.name} занял вашу зону без боя (гарнизона не было)` });
      return;
    }

    const defenderHero = defenderPresent ? defender.heroLevel : 0;
    const result = this.battle(attacker.army, attacker.heroLevel, defenderArmy, defenderHero);
    const sides = this.reportSides(attacker.name, attacker.army, attacker.heroLevel, defender.name, defenderArmy, defenderHero, result);

    if (result.attackerWins) {
      attacker.army = result.attackerArmy;
      zone.garrison = {};
      if (defenderPresent) {
        defender.army = {};
        this.sendHome(defender);
      }
      this.capture(zone, attacker);
      this.report(attacker.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, text: `Победа над ${defender.name}, зона захвачена`, ...sides });
      this.report(defender.id, now, {
        kind: "zone_lost", zoneId: zone.id, tier: zone.tier, won: false,
        text: defenderPresent ? `${attacker.name} разбил вашу армию, герой вернулся в замок` : `${attacker.name} разбил гарнизон и захватил зону`,
        ...sides,
      });
    } else {
      attacker.army = {};
      this.sendHome(attacker);
      this.splitSurvivors(zone, defender, defenderPresent, result.defenderArmy);
      this.touch(zone);
      this.report(attacker.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: false, text: `Поражение от ${defender.name}: армия погибла, герой вернулся в замок`, ...sides });
      this.report(defender.id, now, { kind: "battle", zoneId: zone.id, tier: zone.tier, won: true, text: `Атака ${attacker.name} отбита`, ...sides });
    }
  }

  /** Выжившие защитники делятся между гарнизоном и армией хозяина пропорционально исходному вкладу. */
  private splitSurvivors(zone: Zone, defender: Player, defenderPresent: boolean, survivors: Army): void {
    const garrison: Army = {};
    const heroArmy: Army = {};
    for (const [id, alive] of Object.entries(survivors)) {
      const fromGarrison = zone.garrison[id] ?? 0;
      const fromHero = defenderPresent ? defender.army[id] ?? 0 : 0;
      const total = fromGarrison + fromHero;
      const garrisonAlive = total > 0 ? Math.round((alive * fromGarrison) / total) : 0;
      if (garrisonAlive > 0) garrison[id] = garrisonAlive;
      if (alive - garrisonAlive > 0) heroArmy[id] = alive - garrisonAlive;
    }
    zone.garrison = garrison;
    if (defenderPresent) {
      defender.army = heroArmy;
      this.savePlayer(defender);
    }
  }

  private battle(attackerArmy: Army, attackerHero: number, defenderArmy: Army, defenderHero: number): BattleResult {
    return resolveBattle(
      { army: attackerArmy, heroLevel: attackerHero },
      { army: defenderArmy, heroLevel: defenderHero },
      this.units,
      this.settings,
      this.random,
    );
  }

  private reportSides(
    attackerName: string, attackerArmy: Army, attackerHero: number,
    defenderName: string, defenderArmy: Army, defenderHero: number,
    result: BattleResult,
  ): { attacker: ReportSide; defender: ReportSide } {
    return {
      attacker: { name: attackerName, army: attackerArmy, lost: result.attackerLost, power: Math.round(result.attackerPower), heroLevel: attackerHero },
      defender: { name: defenderName, army: defenderArmy, lost: result.defenderLost, power: Math.round(result.defenderPower), heroLevel: defenderHero },
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
    if (zone.isCastle) throw new GameError("Замок защищён и без гарнизона");
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
