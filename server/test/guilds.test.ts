import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Storage } from "../src/storage.ts";
import { GameError, type Game, type Player } from "../src/world/game.ts";
import { neighbors, zoneId } from "../src/world/grid.ts";
import { GuildError } from "../src/world/guilds.ts";
import { createGame, giveArmy, settings } from "./helpers.ts";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const RED = settings.guildColors[0];

function withGold(player: Player, gold = 1000): Player {
  player.kingdom.resources.gold = gold;
  return player;
}

/** Гильдия с главой A и участниками из names (все приняли приглашение). */
function guildWith(game: Game, names: string[], now = 0) {
  const leader = withGold(game.register("A", now));
  game.guilds.create(leader, "Стальные волки", "волк", RED, now);
  const members = names.map((name) => {
    const player = game.register(name, now);
    game.guilds.invite(leader, name, now);
    game.guilds.accept(player, leader.guildId, now);
    return player;
  });
  return { leader, members, guild: game.guilds.guildOf(leader)! };
}

describe("guilds", () => {
  it("creation costs castle gold, name and tag are unique, tag is upper-cased", () => {
    const { game } = createGame();
    const poor = game.register("Poor", 0);
    poor.kingdom.resources.gold = 10;
    assert.throws(() => game.guilds.create(poor, "Нищие", "НИЩ", RED, 0), GuildError);

    const leader = withGold(game.register("A", 0), 1500);
    game.guilds.create(leader, "  Стальные   волки ", "волк", RED, 0);
    const summary = game.playerView(leader, 0).guild!;
    assert.equal(summary.name, "Стальные волки");
    assert.equal(summary.tag, "ВОЛК");
    assert.equal(summary.role, "leader");
    assert.equal(summary.slots, settings.guildBaseSlots);
    assert.equal(leader.kingdom.resources.gold, 500);

    const other = withGold(game.register("B", 0));
    assert.throws(() => game.guilds.create(other, "стальные волки", "ДРУГ", RED, 0), /названием/);
    assert.throws(() => game.guilds.create(other, "Другие", "Волк", RED, 0), /тег/i);
    assert.throws(() => game.guilds.create(other, "Другие", "X", RED, 0), /Тег/);
    assert.throws(() => game.guilds.create(other, "Другие", "ДР", "#123456", 0), /цвет/);
  });

  it("invite → accept; invites expire; players in another guild can't be invited", () => {
    const { game } = createGame();
    const { leader, guild } = guildWith(game, []);
    const b = game.register("B", 0);
    game.guilds.invite(leader, "b", 0);
    assert.equal(game.playerView(b, 0).guildInvites.length, 1);
    assert.equal(game.playerView(b, 0).guildInvites[0].invitedBy, "A");
    assert.throws(() => game.guilds.invite(leader, "B", 0), /уже приглашён/);

    // Приглашение истекает через guildInviteHours.
    const late = settings.guildInviteHours * HOUR;
    assert.equal(game.playerView(b, late).guildInvites.length, 0);
    assert.throws(() => game.guilds.accept(b, guild.id, late), GuildError);

    game.guilds.invite(leader, "B", late);
    game.guilds.accept(b, guild.id, late);
    assert.equal(b.guildId, guild.id);
    assert.equal(guild.members.length, 2);

    const c = withGold(game.register("C", 0));
    game.guilds.create(c, "Чужие", "ЧУЖ", RED, 0);
    assert.throws(() => game.guilds.invite(leader, "C", late), /другой гильдии/);
    assert.throws(() => game.guilds.invite(leader, "Нет такого", late), /не найден/);
  });

  it("roles: officers invite and kick members, only the leader manages officers", () => {
    const { game } = createGame();
    const { leader, members: [b, c, d] } = guildWith(game, ["B", "C", "D"]);
    assert.throws(() => game.guilds.invite(b, "X", 0), /прав/);
    game.guilds.setRole(leader, b.id, "officer", 0);
    game.register("E", 0);
    game.guilds.invite(b, "E", 0);
    game.guilds.kick(b, c.id, 0);
    assert.equal(c.guildId, null);
    game.guilds.setRole(leader, d.id, "officer", 0);
    assert.throws(() => game.guilds.kick(b, d.id, 0), /прав/, "officer can't kick another officer");
    assert.throws(() => game.guilds.kick(b, leader.id, 0), /прав/);
    assert.throws(() => game.guilds.setRole(b, d.id, "member", 0), /прав/);
  });

  it("leaving: leader must hand over first; rejoin cooldown after leaving or being kicked", () => {
    const { game } = createGame();
    const { leader, members: [b], guild } = guildWith(game, ["B"]);
    assert.throws(() => game.guilds.leave(leader, 0), /передайте главенство/);
    game.guilds.transfer(leader, b.id, 0);
    assert.equal(game.playerView(b, 0).guild!.role, "leader");
    game.guilds.leave(leader, 10);
    assert.equal(leader.guildId, null);

    game.guilds.invite(b, "A", 20);
    assert.throws(() => game.guilds.accept(leader, guild.id, 20), /через сутки/);
    game.guilds.accept(leader, guild.id, 10 + settings.guildRejoinHours * HOUR);
    assert.equal(leader.guildId, guild.id);

    // Последний участник-глава уходит — гильдия распускается.
    const { game: game2 } = createGame();
    const solo = withGold(game2.register("S", 0));
    game2.guilds.create(solo, "Одиночки", "ОДН", RED, 0);
    game2.guilds.leave(solo, 0);
    assert.equal(solo.guildId, null);
    assert.equal(game2.playerView(solo, 0).guild, null);
  });

  it("slots grow with level: donations and wins give experience", () => {
    const { game } = createGame();
    const { leader, guild } = guildWith(game, []);
    // Все места заняты приглашениями — больше приглашать нельзя.
    for (let i = 0; i < settings.guildBaseSlots - 1; i++) {
      game.register(`P${i}`, 0);
      game.guilds.invite(leader, `P${i}`, 0);
    }
    game.register("Extra", 0);
    assert.throws(() => game.guilds.invite(leader, "Extra", 0), /свободных мест/);

    let donated = 0;
    while (guild.level < 2) {
      leader.kingdom.resources.gold = 1000;
      donated += game.guilds.donate(leader, 1000, 0);
    }
    assert.equal(donated, settings.guildLevelXp[1]);
    assert.equal(game.guilds.slots(guild), settings.guildBaseSlots + settings.guildSlotsPerLevel);
    game.guilds.invite(leader, "Extra", 0);
    const view = game.guilds.view(leader, 0, 0)!;
    assert.equal(view.members[0].contribution, donated);
    assert.ok(view.chat.some((message) => message.template?.startsWith("Гильдия достигла")));

    game.guilds.addWinXp(leader, 250, 0);
    assert.equal(guild.xp, donated + 250);
  });

  it("guild bonus adds army power, capped by level", () => {
    const { game } = createGame();
    const { leader } = guildWith(game, ["B", "C"]);
    assert.equal(game.guilds.bonusPercent(leader), 3 * settings.guildBonusPerMember);
    const { game: big } = createGame();
    const names = Array.from({ length: 10 }, (_, i) => `M${i}`);
    const { leader: bigLeader } = guildWith(big, names);
    assert.equal(big.guilds.bonusPercent(bigLeader), settings.guildBonusBaseCap);
    const view = big.playerView(bigLeader, 0);
    assert.equal(view.guild!.bonus, settings.guildBonusBaseCap);
  });

  it("allies can't attack each other; a march to a new ally is aborted", () => {
    const { game } = createGame();
    const { leader, members: [b] } = guildWith(game, ["B"]);
    // Зона B рядом с героем A.
    const around = neighbors(game.zones[leader.castleZone], settings.gridCols, settings.gridRows)
      .map((hex) => zoneId(hex.col, hex.row, settings.gridCols));
    const target = game.zones[around[0]];
    target.ownerId = b.id;
    target.neutral = {};
    giveArmy(leader, { militia: 10 });
    game.deploy(leader, { militia: 10 }, 0);
    assert.throws(() => game.move(leader, target.id, 0), (error: unknown) => error instanceof GameError && /союзника/.test(error.message));

    // Поход начат до вступления в гильдию — по прибытии срывается.
    const { game: game2 } = createGame();
    const a2 = withGold(game2.register("A", 0));
    const b2 = game2.register("B", 0);
    const zone2 = game2.zones[neighbors(game2.zones[a2.castleZone], settings.gridCols, settings.gridRows)
      .map((hex) => zoneId(hex.col, hex.row, settings.gridCols))[0]];
    zone2.ownerId = b2.id;
    zone2.neutral = {};
    giveArmy(a2, { militia: 10 });
    game2.deploy(a2, { militia: 10 }, 0);
    game2.move(a2, zone2.id, 0);
    game2.guilds.create(a2, "Союз", "СОЮЗ", RED, 0);
    game2.guilds.invite(a2, "B", 0);
    game2.guilds.accept(b2, a2.guildId, 0);
    game2.tick(settings.marchSeconds * 1000);
    assert.equal(zone2.ownerId, b2.id, "ally zone stays with its owner");
    assert.equal(game2.playerView(a2, settings.marchSeconds * 1000).reports[0].data.template, "Поход сорван: {name} — ваш союзник по гильдии");
  });

  it("tags appear on the world map", () => {
    const { game } = createGame();
    const { leader } = guildWith(game, []);
    const entry = game.worldView(0, 0).players.find((player) => player.id === leader.id)!;
    assert.equal(entry.guildTag, "ВОЛК");
    assert.equal(entry.guildColor, RED);
    assert.equal(entry.guildId, leader.guildId);
  });

  it("chat: length limit, rate limit, messages since id, system messages", () => {
    const { game } = createGame();
    const { leader, members: [b] } = guildWith(game, ["B"]);
    game.guilds.postMessage(leader, "  Привет,\nвсем!  ", 5000);
    assert.throws(() => game.guilds.postMessage(leader, "ещё", 5100), /быстро/);
    assert.throws(() => game.guilds.postMessage(b, "", 5000), /пустое/);
    assert.throws(() => game.guilds.postMessage(b, "x".repeat(settings.guildChatMaxLength + 1), 5000), /длинное/);
    const view = game.guilds.view(b, 0, 6000)!;
    const last = view.chat[view.chat.length - 1];
    assert.equal(last.text, "Привет, всем!");
    assert.equal(last.name, "A");
    assert.ok(view.chat.some((message) => message.system && message.template === "{name} вступил в гильдию"));
    assert.equal(game.guilds.view(b, last.id, 6000)!.chat.length, 0);
  });

  it("inactive leader: leadership passes to an active officer", () => {
    const { game } = createGame();
    const { leader, members: [b, c] } = guildWith(game, ["B", "C"]);
    game.guilds.setRole(leader, c.id, "officer", 0);
    const later = settings.guildLeaderInactiveDays * DAY + HOUR;
    b.treasureLastSeen = later;
    c.treasureLastSeen = later;
    const view = game.guilds.view(b, 0, later)!;
    assert.equal(view.members.find((member) => member.playerId === c.id)!.role, "leader");
    assert.equal(view.members.find((member) => member.playerId === leader.id)!.role, "member");
  });

  it("disband frees everyone immediately; guilds survive a restart", () => {
    const storage = new Storage(":memory:");
    const { game } = createGame({}, storage);
    const { leader, members: [b] } = guildWith(game, ["B"]);
    const reloaded = createGame({}, storage).game;
    const bReloaded = reloaded.getPlayer(b.id)!;
    assert.equal(reloaded.playerView(bReloaded, 0).guild!.tag, "ВОЛК");

    game.guilds.disband(leader);
    assert.equal(b.guildId, null);
    const c = withGold(game.register("C", 0));
    game.guilds.create(c, "Новые", "НОВ", RED, 0);
    game.guilds.invite(c, "B", 0);
    game.guilds.accept(b, c.guildId, 0);
    assert.equal(b.guildId, c.guildId, "no rejoin cooldown after disband");
  });
});
