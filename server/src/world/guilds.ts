// Гильдии игроков: создание, приглашения, роли, уровень (опыт за взносы золотом и победы на карте),
// общий бонус к силе армии и чат. Союзники по гильдии не нападают друг на друга (проверяет game.ts).
//
// Роли: глава (всё), офицер (приглашает, исключает участников), участник.
// Места: guildBaseSlots на 1-м уровне + guildSlotsPerLevel за каждый следующий.
// Бонус: guildBonusPerMember % силы армии за участника, но не больше потолка, который растёт с уровнем.

import type { Storage } from "../storage.ts";
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
};

/** Что гильдиям нужно от игры: игроки, их сохранение и догон экономики замка перед оплатой. */
export type GuildHooks = {
  getPlayer(id: number): Player | undefined;
  findPlayerByName(name: string): Player | undefined;
  savePlayer(player: Player): void;
  syncKingdom(player: Player, now: number): void;
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

export class Guilds {
  private guilds = new Map<number, Guild>();
  private nextId: number;
  private lastChatAt = new Map<number, number>();
  private storage: Storage;
  private settings: GuildSettings;
  private hooks: GuildHooks;

  constructor(storage: Storage, settings: GuildSettings, hooks: GuildHooks) {
    this.storage = storage;
    this.settings = settings;
    this.hooks = hooks;
    let maxId = 0;
    for (const guild of storage.loadGuilds()) {
      this.guilds.set(guild.id, guild);
      maxId = Math.max(maxId, guild.id);
    }
    this.nextId = maxId + 1;
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
      lastMessageId: guild.nextMessageId - 1,
    };
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
  disband(actor: Player): void {
    const guild = this.requireGuild(actor);
    this.requireRole(guild, actor, ["leader"]);
    for (const member of guild.members) {
      const player = this.hooks.getPlayer(member.playerId);
      if (!player) continue;
      player.guildId = null;
      this.hooks.savePlayer(player);
    }
    this.guilds.delete(guild.id);
    this.storage.deleteGuild(guild.id);
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

  /** Опыт гильдии за победу участника (вызывает game.ts). */
  addWinXp(player: Player, amount: number, now: number): void {
    const guild = this.guildOf(player);
    if (!guild || amount <= 0) return;
    this.memberOf(guild, player.id)!.contribution += amount;
    this.addXpTo(guild, amount, now);
    this.save(guild);
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
