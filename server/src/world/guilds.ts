// Гильдии игроков: создание, приглашения, роли, уровень (опыт за взносы золотом и победы на карте),
// общий бонус к силе армии и чат. Союзники по гильдии не нападают друг на друга (проверяет game.ts).
//
// Роли: глава (всё), офицер (приглашает, исключает участников), участник.
// Места: guildBaseSlots на 1-м уровне + guildSlotsPerLevel за каждый следующий.
// Бонус: guildBonusPerMember % силы армии за участника, но не больше потолка, который растёт с уровнем.
// Дерево бонусов (data/guild/guild.json): очки за уровни гильдии, распределяет глава.
// Босс гильдии: раз в неделю, общий запас здоровья, у каждого участника несколько атак в сутки.
// Сезон: зоны участников приносят очки (по уровню зоны); регионы контролирует гильдия с большинством зон.

import type { GuildCatalog } from "../gameData.ts";
import type { Storage } from "../storage.ts";
import type { Zone } from "./generator.ts";
import { canAfford, pay } from "./kingdom.ts";
import type { Player } from "./game.ts";

export type GuildRole = "leader" | "officer" | "member";
export type GuildMember = { playerId: number; role: GuildRole; joinedAt: number; contribution: number };
export type GuildInvite = { playerId: number; invitedBy: number; at: number };
/** Сообщение чата. Системные (вступил, повышен…) — шаблоном для перевода на клиенте. */
export type GuildMessage = {
  id: number;
  at: number;
  playerId: number;
  text: string;
  system?: boolean;
  template?: string;
  args?: Record<string, string | number>;
};

/** Босс недели. damage и attacks — по id игрока (строкой, как ключи JSON). */
export type GuildBoss = {
  week: number;
  level: number;
  maxHp: number;
  hp: number;
  damage: Record<string, number>;
  attacks: Record<string, { day: number; count: number }>;
  killedAt: number | null;
};

export type SeasonAward = { season: number; place: number };

/** Общий сезон войны гильдий (хранится в meta). regions — id гильдии, контролирующей регион, или null. */
export type SeasonState = { id: number; startedAt: number; endsAt: number; lastTickAt: number; regions: (number | null)[] };

export type Guild = {
  id: number;
  name: string;
  tag: string;
  color: string;
  createdAt: number;
  level: number;
  xp: number;
  members: GuildMember[];
  invites: GuildInvite[];
  chat: GuildMessage[];
  nextMessageId: number;
  /** Бонусы гильдии: id бонуса → ранг. */
  perks: Record<string, number>;
  perksResetAt: number | null;
  /** Уровень следующего босса (растёт после каждой победы). */
  bossLevel: number;
  boss: GuildBoss | null;
  seasonPoints: number;
  awards: SeasonAward[];
};

export type GuildSettings = {
  guildCreateCost: number;
  guildNameMinLength: number;
  guildNameMaxLength: number;
  guildTagMinLength: number;
  guildTagMaxLength: number;
  guildBaseSlots: number;
  guildSlotsPerLevel: number;
  /** Сколько всего опыта нужно для уровня: [0] — 1-й уровень, [1] — 2-й и т.д.; длина = максимальный уровень. */
  guildLevelXp: readonly number[];
  guildInviteHours: number;
  guildRejoinHours: number;
  guildLeaderInactiveDays: number;
  guildBonusPerMember: number;
  guildBonusBaseCap: number;
  guildBonusCapPerLevel: number;
  guildXpPerNeutralTier: number;
  guildXpPerPvpWin: number;
  guildChatKept: number;
  guildChatMaxLength: number;
  guildChatCooldownMs: number;
  guildColors: readonly string[];
  guildPerkResetHours: number;
  guildBossBaseHp: number;
  guildBossHpGrowth: number;
  guildBossMinMembers: number;
  guildBossAttacksPerDay: number;
  guildBossLuck: number;
  guildBossGoldPerLevel: number;
  guildBossXpPerLevel: number;
  seasonDays: number;
  seasonTickMinutes: number;
  regionGrid: number;
  regionMinZones: number;
  regionControlMultiplier: number;
  seasonRewards: readonly { gold: number; xp: number }[];
  seasonStandingsShown: number;
  gridCols: number;
  gridRows: number;
};

/** Что гильдиям нужно от игры: игроки, их сохранение и догон экономики замка перед оплатой. */
export type GuildHooks = {
  getPlayer(id: number): Player | undefined;
  allPlayers(): Iterable<Player>;
  findPlayerByName(name: string): Player | undefined;
  savePlayer(player: Player): void;
  syncKingdom(player: Player, now: number): void;
  /** Сила удара игрока по боссу (армия + герой, как в бою на карте). */
  attackPower(player: Player, now: number): number;
  /** Золото в казну замка игрока (награды босса и сезона). */
  rewardGold(player: Player, gold: number, now: number): void;
  /** Игрок вышел из гильдии (или она распущена): вернуть подкрепления и т.п. */
  membershipChanged(player: Player, now: number): void;
};

export class GuildError extends Error {
  status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;
const TAG_PATTERN = /^[\p{L}\p{N}]+$/u;
const SEASON_META = "guildSeason";

/** Номер недели (как weekIndex в game.ts): с понедельника, UTC. */
function weekOf(now: number): number {
  return Math.floor((now / DAY_MS + 3) / 7);
}

function weekStart(week: number): number {
  return (week * 7 - 3) * DAY_MS;
}

export class Guilds {
  private guilds = new Map<number, Guild>();
  private nextId: number;
  private lastChatAt = new Map<number, number>();
  private storage: Storage;
  private settings: GuildSettings;
  private catalog: GuildCatalog;
  private hooks: GuildHooks;
  private random: () => number;
  private season: SeasonState;

  constructor(storage: Storage, settings: GuildSettings, catalog: GuildCatalog, hooks: GuildHooks, random: () => number, now: number) {
    this.storage = storage;
    this.settings = settings;
    this.catalog = catalog;
    this.hooks = hooks;
    this.random = random;
    let maxId = 0;
    for (const guild of storage.loadGuilds()) {
      // Гильдии, созданные до бонусов, босса и сезонов.
      guild.perks ??= {};
      guild.perksResetAt ??= null;
      guild.bossLevel ??= 1;
      guild.boss ??= null;
      guild.seasonPoints ??= 0;
      guild.awards ??= [];
      this.guilds.set(guild.id, guild);
      maxId = Math.max(maxId, guild.id);
    }
    this.nextId = maxId + 1;
    const saved = storage.getMeta(SEASON_META);
    this.season = saved ? JSON.parse(saved) as SeasonState : this.newSeason(1, now);
    if (!saved) this.saveSeason();
  }

  // --- Чтение ------------------------------------------------------------------------

  guildOf(player: Player): Guild | undefined {
    return player.guildId === null ? undefined : this.guilds.get(player.guildId);
  }

  areAllies(a: Player, b: Player): boolean {
    return a.guildId !== null && a.guildId === b.guildId;
  }

  tagOf(player: Player): string | null {
    return this.guildOf(player)?.tag ?? null;
  }

  colorOf(player: Player): string | null {
    return this.guildOf(player)?.color ?? null;
  }

  slots(guild: Guild): number {
    return this.settings.guildBaseSlots + (guild.level - 1) * this.settings.guildSlotsPerLevel;
  }

  bonusCap(guild: Guild): number {
    return this.settings.guildBonusBaseCap + (guild.level - 1) * this.settings.guildBonusCapPerLevel;
  }

  /** Бонус гильдии к силе армии игрока, %. */
  bonusPercent(player: Player): number {
    const guild = this.guildOf(player);
    if (!guild) return 0;
    return Math.min(guild.members.length * this.settings.guildBonusPerMember, this.bonusCap(guild));
  }

  /** Коротко о гильдии игрока — для /api/me (кнопка, тег, счётчик новых сообщений). */
  summary(player: Player, now: number) {
    const guild = this.guildOf(player);
    if (!guild) return null;
    this.maintain(guild, now);
    return {
      id: guild.id,
      name: guild.name,
      tag: guild.tag,
      color: guild.color,
      level: guild.level,
      role: this.memberOf(guild, player.id)?.role ?? "member",
      members: guild.members.length,
      slots: this.slots(guild),
      bonus: this.bonusPercent(player),
      badge: this.badge(guild),
      lastMessageId: guild.nextMessageId - 1,
    };
  }

  /** Знак прошлого сезона: 1–3 — место гильдии в только что завершившемся сезоне, 0 — нет. */
  badge(guild: Guild): number {
    return guild.awards.find((award) => award.season === this.season.id - 1)?.place ?? 0;
  }

  badgeOf(player: Player): number {
    const guild = this.guildOf(player);
    return guild ? this.badge(guild) : 0;
  }

  /** Приглашения, полученные игроком. */
  invitesFor(player: Player, now: number) {
    const result = [];
    for (const guild of this.guilds.values()) {
      this.expireInvites(guild, now);
      const invite = guild.invites.find((entry) => entry.playerId === player.id);
      if (!invite) continue;
      result.push({
        guildId: guild.id,
        name: guild.name,
        tag: guild.tag,
        color: guild.color,
        level: guild.level,
        members: guild.members.length,
        slots: this.slots(guild),
        invitedBy: this.hooks.getPlayer(invite.invitedBy)?.name ?? "?",
        expiresAt: invite.at + this.settings.guildInviteHours * HOUR_MS,
      });
    }
    return result;
  }

  /** Всё о гильдии игрока — для окна гильдии. since — id последнего уже полученного сообщения чата. */
  view(player: Player, since: number, now: number) {
    const guild = this.guildOf(player);
    if (!guild) return null;
    this.maintain(guild, now);
    const levelXp = this.settings.guildLevelXp;
    const maxLevel = levelXp.length;
    return {
      ...this.summary(player, now)!,
      xp: guild.xp,
      levelXp: levelXp[guild.level - 1],
      nextLevelXp: guild.level < maxLevel ? levelXp[guild.level] : null,
      maxLevel,
      bonusCap: this.bonusCap(guild),
      createdAt: guild.createdAt,
      members: guild.members
        .map((member) => {
          const other = this.hooks.getPlayer(member.playerId);
          return {
            playerId: member.playerId,
            name: other?.name ?? "?",
            heroLevel: other?.heroLevel ?? 1,
            role: member.role,
            contribution: member.contribution,
            joinedAt: member.joinedAt,
            lastSeen: other?.treasureLastSeen ?? 0,
          };
        })
        .sort((a, b) => roleOrder(a.role) - roleOrder(b.role) || b.contribution - a.contribution),
      memberCount: guild.members.length,
      invites: guild.invites.map((invite) => ({
        playerId: invite.playerId,
        name: this.hooks.getPlayer(invite.playerId)?.name ?? "?",
        invitedBy: this.hooks.getPlayer(invite.invitedBy)?.name ?? "?",
        expiresAt: invite.at + this.settings.guildInviteHours * HOUR_MS,
      })),
      chat: guild.chat.filter((message) => message.id > since).map((message) => ({
        ...message,
        name: message.system ? "" : this.hooks.getPlayer(message.playerId)?.name ?? "?",
      })),
      perks: guild.perks,
      perkPoints: this.perkPointsTotal(guild),
      perkPointsFree: this.perkPointsTotal(guild) - this.perkPointsSpent(guild),
      perksResetAt: guild.perksResetAt === null ? 0 : guild.perksResetAt + this.settings.guildPerkResetHours * HOUR_MS,
      boss: this.bossView(guild, player, now),
      season: this.seasonView(guild),
      awards: guild.awards,
      serverTime: now,
    };
  }

  // --- Действия ------------------------------------------------------------------------

  create(player: Player, rawName: unknown, rawTag: unknown, rawColor: unknown, now: number): Guild {
    if (this.guildOf(player)) throw new GuildError("Вы уже состоите в гильдии");
    const name = String(rawName ?? "").trim().replace(/\s+/g, " ");
    const tag = String(rawTag ?? "").trim().toUpperCase();
    const color = String(rawColor ?? "");
    const settings = this.settings;
    if (name.length < settings.guildNameMinLength || name.length > settings.guildNameMaxLength) {
      throw new GuildError("Название гильдии: от 3 до 24 символов");
    }
    if (tag.length < settings.guildTagMinLength || tag.length > settings.guildTagMaxLength || !TAG_PATTERN.test(tag)) {
      throw new GuildError("Тег: от 2 до 4 букв или цифр");
    }
    if (!settings.guildColors.includes(color)) throw new GuildError("Выберите цвет гильдии");
    for (const other of this.guilds.values()) {
      if (other.name.toLowerCase() === name.toLowerCase()) throw new GuildError("Гильдия с таким названием уже есть", 409);
      if (other.tag === tag) throw new GuildError("Такой тег уже занят", 409);
    }
    this.requireRejoinAllowed(player, now);
    this.hooks.syncKingdom(player, now);
    const cost = { gold: settings.guildCreateCost };
    if (!canAfford(player.kingdom, cost)) throw new GuildError("Не хватает золота в казне замка");
    pay(player.kingdom, cost);

    const guild: Guild = {
      id: this.nextId++,
      name,
      tag,
      color,
      createdAt: now,
      level: 1,
      xp: 0,
      members: [{ playerId: player.id, role: "leader", joinedAt: now, contribution: 0 }],
      invites: [],
      chat: [],
      nextMessageId: 1,
      perks: {},
      perksResetAt: null,
      bossLevel: 1,
      boss: null,
      seasonPoints: 0,
      awards: [],
    };
    this.guilds.set(guild.id, guild);
    this.removeInvitesOf(player.id);
    player.guildId = guild.id;
    this.hooks.savePlayer(player);
    this.system(guild, now, "{name} основал гильдию", { name: player.name });
    this.save(guild);
    return guild;
  }

  invite(actor: Player, targetName: unknown, now: number): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader", "officer"]);
    this.maintain(guild, now);
    const target = this.hooks.findPlayerByName(String(targetName ?? "").trim());
    if (!target) throw new GuildError("Игрок с таким именем не найден", 404);
    if (target.id === actor.id) throw new GuildError("Нельзя пригласить самого себя");
    if (target.guildId === guild.id) throw new GuildError("Игрок уже в вашей гильдии");
    if (target.guildId !== null) throw new GuildError("Игрок уже состоит в другой гильдии");
    if (guild.invites.some((invite) => invite.playerId === target.id)) throw new GuildError("Этот игрок уже приглашён");
    if (guild.members.length + guild.invites.length >= this.slots(guild)) {
      throw new GuildError("Нет свободных мест — повысьте уровень гильдии");
    }
    guild.invites.push({ playerId: target.id, invitedBy: actor.id, at: now });
    this.save(guild);
  }

  cancelInvite(actor: Player, playerId: unknown): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader", "officer"]);
    const before = guild.invites.length;
    guild.invites = guild.invites.filter((invite) => invite.playerId !== playerId);
    if (guild.invites.length === before) throw new GuildError("Приглашение не найдено", 404);
    this.save(guild);
  }

  accept(player: Player, guildId: unknown, now: number): void {
    if (this.guildOf(player)) throw new GuildError("Вы уже состоите в гильдии");
    const guild = typeof guildId === "number" ? this.guilds.get(guildId) : undefined;
    if (!guild) throw new GuildError("Гильдия не найдена", 404);
    this.maintain(guild, now);
    if (!guild.invites.some((invite) => invite.playerId === player.id)) throw new GuildError("Приглашение не найдено или истекло", 404);
    this.requireRejoinAllowed(player, now);
    if (guild.members.length >= this.slots(guild)) throw new GuildError("В гильдии нет свободных мест");
    this.removeInvitesOf(player.id);
    guild.members.push({ playerId: player.id, role: "member", joinedAt: now, contribution: 0 });
    player.guildId = guild.id;
    this.hooks.savePlayer(player);
    this.system(guild, now, "{name} вступил в гильдию", { name: player.name });
    this.save(guild);
  }

  decline(player: Player, guildId: unknown): void {
    const guild = typeof guildId === "number" ? this.guilds.get(guildId) : undefined;
    if (!guild) throw new GuildError("Гильдия не найдена", 404);
    guild.invites = guild.invites.filter((invite) => invite.playerId !== player.id);
    this.save(guild);
  }

  leave(player: Player, now: number): void {
    const guild = this.requireGuild(player);
    const member = this.memberOf(guild, player.id)!;
    if (member.role === "leader") {
      if (guild.members.length > 1) throw new GuildError("Сначала передайте главенство другому участнику");
      this.disband(player);
      return;
    }
    this.removeMember(guild, player, now);
    this.system(guild, now, "{name} покинул гильдию", { name: player.name });
    this.save(guild);
    this.hooks.membershipChanged(player, now);
  }

  kick(actor: Player, playerId: unknown, now: number): void {
    const guild = this.requireGuild(actor);
    const actorRole = this.requireRole(guild, actor, ["leader", "officer"]);
    const target = typeof playerId === "number" ? this.memberOf(guild, playerId) : undefined;
    if (!target) throw new GuildError("Такого участника нет", 404);
    if (target.playerId === actor.id) throw new GuildError("Чтобы уйти, нажмите «Покинуть гильдию»");
    if (target.role === "leader" || (actorRole === "officer" && target.role === "officer")) {
      throw new GuildError("Недостаточно прав");
    }
    const player = this.hooks.getPlayer(target.playerId)!;
    this.removeMember(guild, player, now);
    this.system(guild, now, "{name} исключён из гильдии", { name: player.name });
    this.save(guild);
    this.hooks.membershipChanged(player, now);
  }

  setRole(actor: Player, playerId: unknown, role: unknown, now: number): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    if (role !== "officer" && role !== "member") throw new GuildError("Неизвестная роль");
    const target = typeof playerId === "number" ? this.memberOf(guild, playerId) : undefined;
    if (!target || target.role === "leader") throw new GuildError("Такого участника нет", 404);
    if (target.role === role) return;
    target.role = role;
    const name = this.hooks.getPlayer(target.playerId)?.name ?? "?";
    this.system(guild, now, role === "officer" ? "{name} назначен офицером" : "{name} больше не офицер", { name });
    this.save(guild);
  }

  transfer(actor: Player, playerId: unknown, now: number): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    const target = typeof playerId === "number" ? this.memberOf(guild, playerId) : undefined;
    if (!target || target.playerId === actor.id) throw new GuildError("Такого участника нет", 404);
    this.memberOf(guild, actor.id)!.role = "officer";
    target.role = "leader";
    this.system(guild, now, "{name} теперь глава гильдии", { name: this.hooks.getPlayer(target.playerId)?.name ?? "?" });
    this.save(guild);
  }

  /** Роспуск: все участники свободны сразу (без ожидания перед вступлением в другую гильдию). */
  disband(actor: Player, now = Date.now()): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    const released: Player[] = [];
    for (const member of guild.members) {
      const player = this.hooks.getPlayer(member.playerId);
      if (!player) continue;
      player.guildId = null;
      this.hooks.savePlayer(player);
      released.push(player);
    }
    this.guilds.delete(guild.id);
    this.storage.deleteGuild(guild.id);
    for (const player of released) this.hooks.membershipChanged(player, now);
  }

  /** Взнос золота из казны замка: 1 золото = 1 опыт гильдии. Возвращает внесённую сумму. */
  donate(player: Player, amount: unknown, now: number): number {
    const guild = this.requireGuild(player);
    if (typeof amount !== "number" || !Number.isFinite(amount) || amount < 1) throw new GuildError("Укажите сумму");
    this.hooks.syncKingdom(player, now);
    const gold = Math.floor(Math.min(amount, player.kingdom.resources.gold ?? 0));
    if (gold < 1) throw new GuildError("Не хватает золота в казне замка");
    pay(player.kingdom, { gold });
    this.hooks.savePlayer(player);
    this.memberOf(guild, player.id)!.contribution += gold;
    this.addXpTo(guild, gold, now);
    this.save(guild);
    return gold;
  }

  /** Опыт гильдии за победу участника (вызывает game.ts); бонус «Громкая слава» его увеличивает. */
  addWinXp(player: Player, amount: number, now: number): void {
    const guild = this.guildOf(player);
    if (!guild || amount <= 0) return;
    const xp = Math.round(amount * this.guildXpMultiplier(guild));
    this.memberOf(guild, player.id)!.contribution += xp;
    this.addXpTo(guild, xp, now);
    this.save(guild);
  }

  // --- Бонусы гильдии (дерево) ---------------------------------------------------------

  perkPointsTotal(guild: Guild): number {
    return guild.level * this.catalog.pointsPerLevel;
  }

  perkPointsSpent(guild: Guild): number {
    return Object.values(guild.perks).reduce((sum, rank) => sum + rank, 0);
  }

  private branchPoints(guild: Guild, branchId: string): number {
    let total = 0;
    for (const [perkId, rank] of Object.entries(guild.perks)) if (this.catalog.perks[perkId]?.branch === branchId) total += rank;
    return total;
  }

  /** Бонусы дерева гильдии игрока: стат → проценты. */
  perkBonuses(player: Player): Record<string, number> {
    const guild = this.guildOf(player);
    const bonuses: Record<string, number> = {};
    if (!guild) return bonuses;
    for (const [perkId, rank] of Object.entries(guild.perks)) {
      const perk = this.catalog.perks[perkId];
      if (!perk || rank <= 0) continue;
      bonuses[perk.stat] = (bonuses[perk.stat] ?? 0) + perk.values[Math.min(rank, perk.values.length) - 1];
    }
    return bonuses;
  }

  private guildXpMultiplier(guild: Guild): number {
    let percent = 0;
    for (const [perkId, rank] of Object.entries(guild.perks)) {
      const perk = this.catalog.perks[perkId];
      if (perk?.stat === "GUILD_XP" && rank > 0) percent += perk.values[Math.min(rank, perk.values.length) - 1];
    }
    return 1 + percent / 100;
  }

  learnPerk(actor: Player, perkId: unknown, now: number): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    const perk = typeof perkId === "string" ? this.catalog.perks[perkId] : undefined;
    if (!perk) throw new GuildError("Нет такого бонуса", 404);
    const rank = guild.perks[perk.id] ?? 0;
    if (rank >= perk.values.length) throw new GuildError("Бонус уже на максимальном ранге");
    if (this.perkPointsSpent(guild) >= this.perkPointsTotal(guild)) throw new GuildError("Нет свободных очков — повысьте уровень гильдии");
    if (this.branchPoints(guild, perk.branch) < (this.catalog.tierPoints[perk.index] ?? 0)) {
      throw new GuildError("Сначала вложите больше очков в эту ветку");
    }
    guild.perks[perk.id] = rank + 1;
    this.system(guild, now, "Бонус «{perk}» повышен до {rank} ранга", { perk: perk.name, rank: rank + 1 });
    this.save(guild);
  }

  resetPerks(actor: Player, now: number): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    if (guild.perksResetAt !== null && now - guild.perksResetAt < this.settings.guildPerkResetHours * HOUR_MS) {
      throw new GuildError("Сбрасывать бонусы можно раз в сутки");
    }
    if (this.perkPointsSpent(guild) === 0) throw new GuildError("Бонусы ещё не выбраны");
    guild.perks = {};
    guild.perksResetAt = now;
    this.system(guild, now, "Бонусы гильдии сброшены — очки можно распределить заново", {});
    this.save(guild);
  }

  // --- Босс гильдии ------------------------------------------------------------------

  /** Босс текущей недели (новая неделя — новый босс того уровня, до которого гильдия дошла). */
  private currentBoss(guild: Guild, now: number): GuildBoss {
    const week = weekOf(now);
    if (!guild.boss || guild.boss.week !== week) {
      const level = guild.bossLevel;
      const settings = this.settings;
      const maxHp = Math.round(settings.guildBossBaseHp * settings.guildBossHpGrowth ** (level - 1) *
        Math.max(settings.guildBossMinMembers, guild.members.length));
      guild.boss = { week, level, maxHp, hp: maxHp, damage: {}, attacks: {}, killedAt: null };
      this.save(guild);
    }
    return guild.boss;
  }

  private attacksLeft(boss: GuildBoss, player: Player, now: number): number {
    const entry = boss.attacks[player.id];
    const used = entry && entry.day === Math.floor(now / DAY_MS) ? entry.count : 0;
    return Math.max(0, this.settings.guildBossAttacksPerDay - used);
  }

  /** Удар по боссу. Урон — сила армии и героя (без потерь). Победа — награды всем, кто бил. */
  attackBoss(player: Player, now: number): { damage: number; killed: boolean } {
    const guild = this.requireGuild(player);
    const boss = this.currentBoss(guild, now);
    if (boss.killedAt !== null) throw new GuildError("Босс этой недели уже повержен");
    if (this.attacksLeft(boss, player, now) <= 0) throw new GuildError("Атаки на сегодня закончились — приходите завтра");
    const luck = this.settings.guildBossLuck;
    const damage = Math.max(1, Math.round(this.hooks.attackPower(player, now) * (1 - luck + this.random() * luck * 2)));
    const day = Math.floor(now / DAY_MS);
    const entry = boss.attacks[player.id];
    boss.attacks[player.id] = { day, count: entry && entry.day === day ? entry.count + 1 : 1 };
    boss.damage[player.id] = (boss.damage[player.id] ?? 0) + Math.min(damage, boss.hp);
    boss.hp = Math.max(0, boss.hp - damage);
    const killed = boss.hp === 0;
    if (killed) {
      boss.killedAt = now;
      const gold = this.settings.guildBossGoldPerLevel * boss.level;
      for (const id of Object.keys(boss.damage)) {
        const member = this.hooks.getPlayer(Number(id));
        if (member && member.guildId === guild.id) this.hooks.rewardGold(member, gold, now);
      }
      guild.bossLevel = boss.level + 1;
      this.system(guild, now, "Босс гильдии {level} уровня повержен! Каждый, кто сражался, получил {gold} золота", { level: boss.level, gold });
      this.addXpTo(guild, Math.round(this.settings.guildBossXpPerLevel * boss.level * this.guildXpMultiplier(guild)), now);
    }
    this.save(guild);
    return { damage, killed };
  }

  private bossView(guild: Guild, player: Player, now: number) {
    const boss = this.currentBoss(guild, now);
    return {
      level: boss.level,
      maxHp: boss.maxHp,
      hp: boss.hp,
      killedAt: boss.killedAt,
      endsAt: weekStart(boss.week + 1),
      attacksLeft: this.attacksLeft(boss, player, now),
      attacksPerDay: this.settings.guildBossAttacksPerDay,
      attacksResetAt: (Math.floor(now / DAY_MS) + 1) * DAY_MS,
      goldReward: this.settings.guildBossGoldPerLevel * boss.level,
      damage: Object.entries(boss.damage)
        .map(([id, value]) => ({ playerId: Number(id), name: this.hooks.getPlayer(Number(id))?.name ?? "?", damage: value }))
        .sort((a, b) => b.damage - a.damage),
    };
  }

  // --- Сезон войны гильдий и регионы -----------------------------------------------------

  private newSeason(id: number, now: number): SeasonState {
    const regions = this.settings.regionGrid * this.settings.regionGrid;
    return { id, startedAt: now, endsAt: now + this.settings.seasonDays * DAY_MS, lastTickAt: now, regions: new Array(regions).fill(null) };
  }

  private saveSeason(): void {
    this.storage.setMeta(SEASON_META, JSON.stringify(this.season));
  }

  regionOf(zone: Zone): number {
    const grid = this.settings.regionGrid;
    const col = Math.min(grid - 1, Math.floor((zone.col * grid) / this.settings.gridCols));
    const row = Math.min(grid - 1, Math.floor((zone.row * grid) / this.settings.gridRows));
    return row * grid + col;
  }

  /**
   * Раз в seasonTickMinutes: кто контролирует регионы и сколько очков набрали гильдии.
   * Время простоя сервера не засчитывается (не больше 5 интервалов за раз).
   */
  tick(now: number, zones: readonly Zone[]): void {
    const interval = this.settings.seasonTickMinutes * 60_000;
    if (now - this.season.lastTickAt < interval) return;
    const minutes = Math.min(now - this.season.lastTickAt, interval * 5) / 60_000;
    const guildByPlayer = new Map<number, number>();
    for (const player of this.hooks.allPlayers()) if (player.guildId !== null) guildByPlayer.set(player.id, player.guildId);

    const regionCount = this.season.regions.length;
    const counts: Map<number, number>[] = Array.from({ length: regionCount }, () => new Map());
    const tiers: Map<number, number>[] = Array.from({ length: regionCount }, () => new Map());
    for (const zone of zones) {
      if (zone.ownerId === null) continue;
      const guildId = guildByPlayer.get(zone.ownerId);
      if (guildId === undefined) continue;
      const region = this.regionOf(zone);
      counts[region].set(guildId, (counts[region].get(guildId) ?? 0) + 1);
      tiers[region].set(guildId, (tiers[region].get(guildId) ?? 0) + zone.tier);
    }
    const points = new Map<number, number>();
    for (let region = 0; region < regionCount; region++) {
      const ranked = [...counts[region].entries()].sort((a, b) => b[1] - a[1]);
      const leader = ranked[0];
      const controlled = leader && leader[1] >= this.settings.regionMinZones && (ranked.length < 2 || leader[1] > ranked[1][1]);
      this.season.regions[region] = controlled ? leader[0] : null;
      for (const [guildId, tierSum] of tiers[region]) {
        const multiplier = controlled && leader[0] === guildId ? this.settings.regionControlMultiplier : 1;
        points.set(guildId, (points.get(guildId) ?? 0) + (tierSum * multiplier * minutes) / 60);
      }
    }
    for (const [guildId, value] of points) {
      const guild = this.guilds.get(guildId);
      if (!guild) continue;
      guild.seasonPoints += value;
      this.save(guild);
    }
    this.season.lastTickAt = now;
    if (now >= this.season.endsAt) this.endSeason(now);
    this.saveSeason();
  }

  /** Конец сезона: награды тройке лидеров, знак сезона, очки всех гильдий — в ноль. */
  private endSeason(now: number): void {
    const ranking = [...this.guilds.values()].filter((guild) => guild.seasonPoints > 0).sort((a, b) => b.seasonPoints - a.seasonPoints);
    this.settings.seasonRewards.forEach((reward, index) => {
      const guild = ranking[index];
      if (!guild) return;
      const place = index + 1;
      guild.awards.push({ season: this.season.id, place });
      for (const member of guild.members) {
        const player = this.hooks.getPlayer(member.playerId);
        if (player) this.hooks.rewardGold(player, reward.gold, now);
      }
      this.system(guild, now, "Сезон {season} завершён: {place} место! Каждый участник получил {gold} золота",
        { season: this.season.id, place, gold: reward.gold });
      this.addXpTo(guild, reward.xp, now);
    });
    for (const guild of this.guilds.values()) {
      guild.seasonPoints = 0;
      this.save(guild);
    }
    const regions = this.season.regions;
    this.season = this.newSeason(this.season.id + 1, now);
    this.season.regions = regions;
  }

  private seasonView(guild: Guild) {
    const ranking = [...this.guilds.values()].sort((a, b) => b.seasonPoints - a.seasonPoints);
    const place = ranking.findIndex((other) => other.id === guild.id) + 1;
    return {
      id: this.season.id,
      startedAt: this.season.startedAt,
      endsAt: this.season.endsAt,
      points: Math.floor(guild.seasonPoints),
      place,
      rewards: this.settings.seasonRewards,
      standings: ranking.slice(0, this.settings.seasonStandingsShown).map((other, index) => ({
        place: index + 1,
        guildId: other.id,
        name: other.name,
        tag: other.tag,
        color: other.color,
        members: other.members.length,
        points: Math.floor(other.seasonPoints),
        regions: this.season.regions.filter((owner) => owner === other.id).length,
      })),
    };
  }

  /** Регионы для карты: название (ключ перевода), границы в клетках и кто контролирует. */
  regionsView() {
    const grid = this.settings.regionGrid;
    return {
      grid,
      season: this.season.id,
      seasonEndsAt: this.season.endsAt,
      list: this.season.regions.map((owner, index) => {
        const guild = owner === null ? undefined : this.guilds.get(owner);
        return { index, name: this.catalog.regions[index] ?? "", guildId: guild?.id ?? null, tag: guild?.tag ?? null, color: guild?.color ?? null };
      }),
    };
  }

  postMessage(player: Player, rawText: unknown, now: number): void {
    const guild = this.requireGuild(player);
    // Управляющие символы убираем, пробелы схлопываем.
    const text = String(rawText ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
    if (text.length === 0) throw new GuildError("Сообщение пустое");
    if (text.length > this.settings.guildChatMaxLength) throw new GuildError("Сообщение слишком длинное");
    const last = this.lastChatAt.get(player.id) ?? 0;
    if (now - last < this.settings.guildChatCooldownMs) throw new GuildError("Не так быстро", 429);
    this.lastChatAt.set(player.id, now);
    this.pushMessage(guild, { id: 0, at: now, playerId: player.id, text });
    this.save(guild);
  }

  // --- Внутреннее ---------------------------------------------------------------------

  private addXpTo(guild: Guild, amount: number, now: number): void {
    guild.xp += Math.floor(amount);
    const levelXp = this.settings.guildLevelXp;
    while (guild.level < levelXp.length && guild.xp >= levelXp[guild.level]) {
      guild.level += 1;
      this.system(guild, now, "Гильдия достигла {level} уровня: мест {slots}", { level: guild.level, slots: this.slots(guild) });
    }
  }

  /** Просроченные приглашения и передача главенства, если глава давно не заходил. */
  private maintain(guild: Guild, now: number): void {
    let changed = this.expireInvites(guild, now);
    const leader = guild.members.find((member) => member.role === "leader");
    const inactiveSince = now - this.settings.guildLeaderInactiveDays * DAY_MS;
    const leaderPlayer = leader ? this.hooks.getPlayer(leader.playerId) : undefined;
    if (!leader || !leaderPlayer || leaderPlayer.treasureLastSeen < inactiveSince) {
      const candidates = guild.members
        .filter((member) => member !== leader)
        .map((member) => ({ member, seen: this.hooks.getPlayer(member.playerId)?.treasureLastSeen ?? 0 }))
        .filter((entry) => entry.seen >= inactiveSince)
        .sort((a, b) => roleOrder(a.member.role) - roleOrder(b.member.role) || a.member.joinedAt - b.member.joinedAt);
      if (candidates.length > 0) {
        if (leader) leader.role = "member";
        candidates[0].member.role = "leader";
        const name = this.hooks.getPlayer(candidates[0].member.playerId)?.name ?? "?";
        this.system(guild, now, "Глава давно не заходил — главенство перешло к {name}", { name });
        changed = true;
      }
    }
    if (changed) this.save(guild);
  }

  private expireInvites(guild: Guild, now: number): boolean {
    const before = guild.invites.length;
    const ttl = this.settings.guildInviteHours * HOUR_MS;
    guild.invites = guild.invites.filter((invite) => now - invite.at < ttl);
    if (guild.invites.length === before) return false;
    this.save(guild);
    return true;
  }

  private removeMember(guild: Guild, player: Player, now: number): void {
    guild.members = guild.members.filter((member) => member.playerId !== player.id);
    player.guildId = null;
    player.guildLeftAt = now;
    this.hooks.savePlayer(player);
  }

  private removeInvitesOf(playerId: number): void {
    for (const guild of this.guilds.values()) {
      const before = guild.invites.length;
      guild.invites = guild.invites.filter((invite) => invite.playerId !== playerId);
      if (guild.invites.length !== before) this.save(guild);
    }
  }

  private requireRejoinAllowed(player: Player, now: number): void {
    if (player.guildLeftAt !== null && now - player.guildLeftAt < this.settings.guildRejoinHours * HOUR_MS) {
      throw new GuildError("После выхода из гильдии вступить в новую можно только через сутки");
    }
  }

  private requireGuild(player: Player): Guild {
    const guild = this.guildOf(player);
    if (!guild) throw new GuildError("Вы не состоите в гильдии");
    return guild;
  }

  private requireRole(guild: Guild, player: Player, roles: GuildRole[]): GuildRole {
    const role = this.memberOf(guild, player.id)?.role;
    if (!role || !roles.includes(role)) throw new GuildError("Недостаточно прав");
    return role;
  }

  private memberOf(guild: Guild, playerId: number): GuildMember | undefined {
    return guild.members.find((member) => member.playerId === playerId);
  }

  private system(guild: Guild, now: number, template: string, args: Record<string, string | number>): void {
    const text = template.replace(/\{(\w+)\}/g, (_, key: string) => String(args[key] ?? ""));
    this.pushMessage(guild, { id: 0, at: now, playerId: 0, text, system: true, template, args });
  }

  private pushMessage(guild: Guild, message: GuildMessage): void {
    message.id = guild.nextMessageId++;
    guild.chat.push(message);
    if (guild.chat.length > this.settings.guildChatKept) guild.chat.splice(0, guild.chat.length - this.settings.guildChatKept);
  }

  private save(guild: Guild): void {
    if (this.guilds.has(guild.id)) this.storage.saveGuild(guild);
  }
}

function roleOrder(role: GuildRole): number {
  return role === "leader" ? 0 : role === "officer" ? 1 : 2;
}
