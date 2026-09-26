import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Game, GameSettings, Player } from "../src/world/game.ts";
import { neighbors, zoneId } from "../src/world/grid.ts";
import { GuildError } from "../src/world/guilds.ts";
import { createGame, gameData, settings } from "./helpers.ts";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const RED = settings.guildColors[0];

/** Гильдия: глава A + участники names. */
function guildWith(game: Game, names: string[], now = 0) {
  const leader = game.register("A", now);
  leader.kingdom.resources.gold = 1000;
  game.guilds.create(leader, "Стальные волки", "ВОЛК", RED, now);
  const members = names.map((name) => {
    const player = game.register(name, now);
    game.guilds.invite(leader, name, now);
    game.guilds.accept(player, leader.guildId, now);
    return player;
  });
  return { leader, members, guild: game.guilds.guildOf(leader)! };
}

function setup(overrides: Partial<GameSettings> = {}, names: string[] = []) {
  const { game } = createGame(overrides);
  return { game, ...guildWith(game, names) };
}

describe("guild perks", () => {
  it("points come from guild levels; branch tiers unlock with invested points; only the leader learns", () => {
    const { game, leader, members: [b], guild } = setup({}, ["B"]);
    assert.equal(game.guilds.perkPointsTotal(guild), gameData.guild.pointsPerLevel);
    assert.throws(() => game.guilds.learnPerk(b, "treasury", 0), /прав/);
    assert.throws(() => game.guilds.learnPerk(leader, "fortune", 0), /ветку/, "third perk needs 4 points in the branch");
    game.guilds.learnPerk(leader, "treasury", 0);
    assert.throws(() => game.guilds.learnPerk(leader, "mentors", 0), /ветку/, "second perk needs 2 points in the branch");
    game.guilds.learnPerk(leader, "treasury", 0);
    assert.throws(() => game.guilds.learnPerk(leader, "mentors", 0), /очков/, "all points spent");
    assert.throws(() => game.guilds.learnPerk(leader, "nope", 0), GuildError);

    const bonuses = game.playerView(b, 0).bonuses as Record<string, number>;
    assert.equal(bonuses.GOLD_FIND, gameData.guild.perks.treasury.values[1], "perk bonus reaches every member's hero");
  });

  it("army perks strengthen the army on the server; reset once a day", () => {
    const { game, leader, guild } = setup();
    guild.level = 2;
    game.guilds.learnPerk(leader, "morale", 0);
    assert.equal(game.guilds.perkBonuses(leader).ARMY_POWER, gameData.guild.perks.morale.values[0]);
    const view = game.guilds.view(leader, 0, 0)!;
    assert.equal(view.perkPointsFree, game.guilds.perkPointsTotal(guild) - 1);

    game.guilds.resetPerks(leader, 10);
    assert.deepEqual(guild.perks, {});
    game.guilds.learnPerk(leader, "morale", 20);
    assert.throws(() => game.guilds.resetPerks(leader, 30), /раз в сутки/);
    game.guilds.resetPerks(leader, 10 + settings.guildPerkResetHours * HOUR);
  });

  it("«renown» raises guild experience from victories", () => {
    const { game, leader, guild } = setup();
    for (let i = 0; i < 2; i++) game.guilds.learnPerk(leader, "banner", 0);
    guild.level = 3;
    for (let i = 0; i < 2; i++) game.guilds.learnPerk(leader, "brotherhood", 0);
    game.guilds.learnPerk(leader, "renown", 0);
    const before = guild.xp;
    game.guilds.addWinXp(leader, 100, 0);
    assert.equal(guild.xp - before, Math.round(100 * (1 + gameData.guild.perks.renown.values[0] / 100)));
  });
});

describe("guild boss", () => {
  it("three attacks a day, damage from the army and hero, table of damage", () => {
    const { game, leader, members: [b] } = setup({}, ["B"]);
    leader.kingdom.army = { militia: 20 };
    const first = game.guilds.attackBoss(leader, 0);
    assert.ok(first.damage > 0 && !first.killed);
    game.guilds.attackBoss(leader, 0);
    game.guilds.attackBoss(leader, 0);
    assert.throws(() => game.guilds.attackBoss(leader, 0), /закончились/);
    game.guilds.attackBoss(b, 0);
    const boss = game.guilds.view(leader, 0, 0)!.boss;
    assert.equal(boss.attacksLeft, 0);
    assert.equal(boss.damage.length, 2);
    assert.equal(boss.damage[0].playerId, leader.id, "leader dealt the most damage");
    assert.equal(boss.maxHp, settings.guildBossBaseHp * settings.guildBossMinMembers);
    // На следующий день атаки снова есть.
    assert.equal(game.guilds.view(leader, 0, DAY)!.boss.attacksLeft, settings.guildBossAttacksPerDay);
  });

  it("killing the boss rewards everyone who fought; next week the boss is stronger", () => {
    // Здоровье 5 × 3 участника: удар главы (герой 1-го уровня) не добивает, рыцари B — добивают.
    const { game, leader, members: [b, c], guild } = setup({ guildBossBaseHp: 5 }, ["B", "C"]);
    const goldBefore = leader.kingdom.resources.gold;
    const cGold = c.kingdom.resources.gold;
    b.kingdom.army = { knight: 100 };
    game.guilds.attackBoss(leader, 0);
    const result = game.guilds.attackBoss(b, 0);
    assert.ok(result.killed);
    const reward = settings.guildBossGoldPerLevel;
    assert.equal(leader.kingdom.resources.gold, goldBefore + reward);
    assert.equal(c.kingdom.resources.gold, cGold, "members who did not fight get nothing");
    assert.throws(() => game.guilds.attackBoss(c, 0), /повержен/);
    assert.equal(guild.bossLevel, 2);
    assert.ok(guild.xp >= settings.guildBossXpPerLevel);

    const nextWeek = 7 * DAY;
    const boss = game.guilds.view(leader, 0, nextWeek)!.boss;
    assert.equal(boss.level, 2);
    assert.equal(boss.hp, boss.maxHp);
  });
});

describe("guild season", () => {
  /** Отдаёт игроку count зон первого региона (левый верхний угол карты). */
  function ownZones(game: Game, player: Player, count: number, offset = 0): void {
    let given = 0;
    for (const zone of game.zones) {
      if (given >= count + offset) break;
      if (game.guilds.regionOf(zone) !== 0 || zone.isCastle || zone.ownerId !== null) continue;
      if (given++ < offset) continue;
      zone.ownerId = player.id;
    }
  }

  it("zones give points by tier; the majority guild controls the region (×1.5)", () => {
    const { game, leader } = setup({ regionMinZones: 3 });
    const rival = game.register("R", 0);
    rival.kingdom.resources.gold = 1000;
    game.guilds.create(rival, "Соперники", "СОП", RED, 0);
    ownZones(game, leader, 4);
    ownZones(game, rival, 2, 4);
    game.tick(HOUR);
    const regions = game.worldView(0, HOUR).regions;
    assert.equal(regions.list[0].guildId, leader.guildId);
    assert.equal(regions.list[0].tag, "ВОЛК");
    assert.equal(regions.list[0].name, gameData.guild.regions[0]);
    const leaderGuild = game.guilds.guildOf(leader)!;
    const rivalGuild = game.guilds.guildOf(rival)!;
    // Замок — тоже владение и приносит очки.
    const tierSum = (player: Player) => game.zones.filter((zone) => zone.ownerId === player.id && game.guilds.regionOf(zone) === 0)
      .reduce((sum, zone) => sum + zone.tier, 0);
    // Первый тик засчитывает не больше 5 интервалов (простой сервера не в счёт).
    const minutes = 5 * settings.seasonTickMinutes;
    assert.ok(Math.abs(rivalGuild.seasonPoints - (tierSum(rival) * minutes) / 60) < 1e-6);
    assert.ok(leaderGuild.seasonPoints > (tierSum(leader) * minutes) / 60, "control multiplier applies");
  });

  it("season end: rewards and badge for the top guilds, points reset", () => {
    const { game, leader, members: [b] } = setup({ seasonDays: 1, regionMinZones: 3 }, ["B"]);
    ownZones(game, leader, 3);
    const gold = b.kingdom.resources.gold;
    for (let t = 1; t <= 25; t++) game.tick(t * HOUR);
    const guild = game.guilds.guildOf(leader)!;
    assert.deepEqual(guild.awards, [{ season: 1, place: 1 }]);
    // Казна за сутки ещё и производит золото — награда не меньше обещанной.
    assert.ok(b.kingdom.resources.gold >= gold + settings.seasonRewards[0].gold);
    assert.ok(guild.seasonPoints < 1, "points reset for the new season");
    assert.equal(game.playerView(b, 25 * HOUR).guild!.badge, 1);
    assert.equal(game.worldView(0, 25 * HOUR).players.find((player) => player.id === b.id)!.guildBadge, 1);
    assert.equal(game.guilds.view(leader, 0, 25 * HOUR)!.season.id, 2);
  });
});

describe("reinforcements", () => {
  function allies(overrides: Partial<GameSettings> = {}) {
    const { game, leader, members: [ally] } = setup(overrides, ["B"]);
    ally.kingdom.levels.barracks = 10;
    ally.kingdom.levels.town_hall = 10;
    return { game, leader, ally };
  }

  it("only allies, only soldiers from the castle, limited by the ally's army capacity", () => {
    const { game, leader, ally } = allies();
    const stranger = game.register("S", 0);
    leader.kingdom.army = { spearman: 1000 };
    assert.throws(() => game.reinforce(leader, stranger.id, { spearman: 1 }, 0), /союзникам/);
    assert.throws(() => game.reinforce(leader, ally.id, { knight: 1 }, 0), /нет столько/);
    const capacity = game.playerView(ally, 0).reinforcementCapacity;
    assert.ok(capacity > 0);
    assert.throws(() => game.reinforce(leader, ally.id, { spearman: capacity + 1 }, 0), /нет места/);
    game.reinforce(leader, ally.id, { spearman: 5 }, 0);
    assert.equal(leader.kingdom.army.spearman, 995);
    const view = game.playerView(ally, 0);
    assert.equal(view.reinforcementsIn.length, 1);
    assert.equal(view.reinforcementsIn[0].fromName, "A");
    const sent = game.playerView(leader, 0).reinforcementsSent;
    assert.deepEqual(sent[0].army, { spearman: 5 });

    game.recallReinforcement(leader, 0, 10);
    assert.equal(leader.kingdom.army.spearman, 1000);
    assert.equal(game.playerView(ally, 10).reinforcementsIn.length, 0);
  });

  it("reinforcements defend the ally's castle against a raid and share the losses", () => {
    const { game, leader, ally } = allies();
    const raider = game.register("Raider", 0);
    raider.protectionUntil = 0;
    ally.protectionUntil = 0;
    const approach = neighbors(game.zones[ally.castleZone], settings.gridCols, settings.gridRows)
      .map((hex) => zoneId(hex.col, hex.row, settings.gridCols)).find((id) => !game.zones[id].isCastle)!;
    game.zones[approach].ownerId = raider.id;
    game.zones[approach].neutral = {};
    raider.heroZone = approach;

    leader.kingdom.army = { spearman: 40 };
    game.reinforce(leader, ally.id, { spearman: 40 }, 0);
    const arrived = settings.castleMarchSeconds * 1000;
    ally.kingdom.army = {};
    raider.army = { militia: 30 };
    game.move(raider, ally.castleZone, arrived);
    game.tick(arrived * 2);
    const raiderReport = game.playerView(raider, arrived * 2).reports[0].data;
    assert.equal(raiderReport.won, false, "reinforcements repelled the raid");
    const left = game.playerView(leader, arrived * 2).reinforcementsSent[0].army.spearman ?? 0;
    assert.ok(left > 0 && left < 40, "helper lost part of the army");
    assert.equal(game.playerView(leader, arrived * 2).reports[0].data.template, "Ваши подкрепления помогли отбить набег на замок {name}");
  });

  it("troops still on the way don't defend; leaving the guild sends reinforcements home", () => {
    const { game, leader, ally } = allies();
    leader.kingdom.army = { spearman: 10 };
    game.reinforce(leader, ally.id, { spearman: 10 }, 0);
    const upkeepWith = game.playerView(leader, 0).kingdom;
    assert.ok(upkeepWith, "helper still pays upkeep");
    game.guilds.leave(ally, 5);
    assert.equal(leader.kingdom.army.spearman, 10);
    assert.equal(leader.reinforcementsSent.length, 0);
  });
});
