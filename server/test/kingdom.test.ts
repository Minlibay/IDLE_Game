import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Storage } from "../src/storage.ts";
import { GameError, splitSurvivors, type Game, type Player } from "../src/world/game.ts";
import { neighbors, zoneId } from "../src/world/grid.ts";
import { buildTimeMs, KingdomError, storageCapacity, trainTimeMs } from "../src/world/kingdom.ts";
import { createGame, gameData, giveArmy, settings } from "./helpers.ts";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

function rich(player: Player): void {
  for (const resource of gameData.kingdom.resources) player.kingdom.resources[resource] = 5000;
}

/** Ставит героя атакующего по соседству с замком защитника (в своей зоне). */
function besideCastle(game: Game, attacker: Player, defender: Player): number {
  const approach = neighbors(game.zones[defender.castleZone], settings.gridCols, settings.gridRows)
    .map((hex) => zoneId(hex.col, hex.row, settings.gridCols))
    .find((id) => !game.zones[id].isCastle)!;
  game.zones[approach].ownerId = attacker.id;
  game.zones[approach].neutral = {};
  attacker.heroZone = approach;
  return approach;
}

describe("castle economy", () => {
  it("new castle: start resources, town hall 1, newbie protection", () => {
    const { game } = createGame();
    const player = game.register("A", 1000);
    const view = game.playerView(player, 1000);
    assert.equal(view.kingdom.resources.gold, gameData.kingdom.startResources.gold);
    assert.equal(view.kingdom.levels.town_hall, 1);
    assert.equal(view.protectionUntil, 1000 + settings.newbieProtectionHours * HOUR);
  });

  it("buildings produce resources lazily, capped by storage", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    player.kingdom.levels.farm = 2;
    player.kingdom.resources.food = 0;
    game.playerView(player, 10 * MINUTE);
    assert.equal(Math.round(player.kingdom.resources.food), 20);
    game.playerView(player, 100 * HOUR);
    assert.equal(player.kingdom.resources.food, storageCapacity(player.kingdom, gameData, "food"));
    assert.ok(storageCapacity(player.kingdom, gameData, "gold") > storageCapacity(player.kingdom, gameData, "food"));
  });

  it("construction: pays, one at a time, finishes by time, needs the town hall level", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    const woodBefore = player.kingdom.resources.wood;
    game.build(player, "farm", 0);
    assert.ok(player.kingdom.resources.wood < woodBefore);
    assert.throws(() => game.build(player, "well", 0), /заняты/);
    const finish = buildTimeMs(gameData, "farm", 1, settings);
    game.playerView(player, finish - 1);
    assert.equal(player.kingdom.levels.farm ?? 0, 0);
    game.playerView(player, finish);
    assert.equal(player.kingdom.levels.farm, 1);
    assert.equal(player.kingdom.construction, null);

    rich(player);
    player.kingdom.levels.farm = 1;
    assert.throws(() => game.build(player, "farm", finish), /Ратуша/);
    assert.throws(() => game.build(player, "castle_of_dreams", finish), KingdomError);
  });

  it("recruitment: needs barracks and space, trains one by one, queue continues", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    rich(player);
    assert.throws(() => game.recruit(player, "militia", 1, 0), /здание/);
    player.kingdom.levels.barracks = 1;
    const capacity = game.playerView(player, 0).kingdom.army.capacity;
    assert.throws(() => game.recruit(player, "militia", capacity + 1, 0), /места/);
    game.recruit(player, "militia", 3, 0);
    game.recruit(player, "militia", 2, 0);
    const per = trainTimeMs(player.kingdom, gameData, "militia", settings);
    game.playerView(player, per * 2 + 1);
    assert.equal(player.kingdom.army.militia, 2);
    game.playerView(player, per * 5 + 1);
    assert.equal(player.kingdom.army.militia, 5);
    assert.equal(player.kingdom.queue.length, 0);
  });

  it("cancel refunds untrained units, next order starts", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    rich(player);
    player.kingdom.levels.barracks = 1;
    game.recruit(player, "militia", 4, 0);
    game.recruit(player, "militia", 1, 0);
    const goldAfter = player.kingdom.resources.gold;
    game.cancelTraining(player, 0, 0);
    assert.equal(player.kingdom.resources.gold, goldAfter + gameData.units.militia.cost.gold * 4);
    assert.equal(player.kingdom.queue.length, 1);
    assert.ok(player.kingdom.queue[0].nextAt > 0, "the next order starts training");
    assert.throws(() => game.cancelTraining(player, 5, 0), KingdomError);
  });

  it("army eats food; without food it is starving and weaker", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    giveArmy(player, { knight: 100 });
    player.kingdom.resources.food = 10;
    const view = game.playerView(player, 60 * MINUTE);
    assert.equal(player.kingdom.resources.food, 0);
    assert.equal(view.kingdom.army.starving, true);
    assert.ok(view.kingdom.army.attack < gameData.units.knight.attack * 100);
  });

  it("hero consumes food and water, never more than stored", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    player.kingdom.resources.food = 5;
    const taken = game.consume(player, { food: 8, water: 2, gold: 100 }, 0);
    assert.deepEqual(taken, { food: 5, water: 2 });
    assert.equal(player.kingdom.resources.food, 0);
  });

  it("gold deposit is limited by an allowance that grows with time and hero level", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    assert.throws(() => game.deposit(player, 100, 0), /Лимит/);
    game.setHeroLevel(player, 10, 0);
    game.playerView(player, 10 * MINUTE); // казна сама растёт от Ратуши — считаем «до» на момент взноса
    const before = player.kingdom.resources.gold;
    const accepted = game.deposit(player, 1_000_000, 10 * MINUTE);
    assert.equal(accepted, settings.depositPerLevelPerMinute * 10 * 10);
    assert.equal(player.kingdom.resources.gold, before + accepted);
  });

  it("castle survives a restart and keeps advancing", () => {
    const storage = new Storage(":memory:");
    const first = createGame({}, storage).game;
    const player = first.register("A", 0);
    player.kingdom.levels.farm = 3;
    player.kingdom.resources.food = 0;
    first.build(player, "well", 0);
    const second = createGame({}, storage).game;
    const loaded = second.getPlayerByToken(player.token)!;
    second.playerView(loaded, 10 * MINUTE);
    assert.equal(Math.round(loaded.kingdom.resources.food), 30);
    assert.equal(loaded.kingdom.levels.well, 1);
  });
});

describe("army relics", () => {
  it("relic bonuses raise attack/defense, speed up training, cut upkeep — and are capped", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    giveArmy(player, { knight: 10 });
    player.kingdom.levels.barracks = 1;
    const before = game.playerView(player, 0).kingdom.army;
    game.setArmyGear(player, { ARMY_ATTACK: 20, ARMY_DEFENSE: 10, TRAINING_SPEED: 50, UPKEEP_REDUCTION: 40 }, 0);
    const after = game.playerView(player, 0).kingdom.army;
    assert.ok(Math.abs(after.attack - before.attack * 1.2) < 1e-6, "attack +20%");
    assert.ok(Math.abs(after.defense - before.defense * 1.1) < 1e-6, "defense +10%");
    assert.ok(after.trainTimes.militia < before.trainTimes.militia, "training is faster");
    assert.ok(Math.abs(after.upkeep - before.upkeep * 0.6) < 1e-9, "upkeep -40%");

    game.setArmyGear(player, { ARMY_POWER: 100_000 }, 0);
    assert.equal(player.armyGear.ARMY_POWER, settings.armyGearCaps.ARMY_POWER, "forged values are capped");
    assert.throws(() => game.setArmyGear(player, { GOD_MODE: 5 }, 0), /Неизвестный/);
    assert.throws(() => game.setArmyGear(player, { ARMY_POWER: -5 }, 0), GameError);
  });

  it("relic attack bonus decides a close battle", () => {
    const weak = createGame().game;
    const strong = createGame().game;
    for (const [game, gear] of [[weak, {}], [strong, { ARMY_ATTACK: 60, ARMY_POWER: 60 }]] as const) {
      const player = game.register("A", 0);
      player.army = { militia: 10 };
      const target = neighbors(game.zones[player.castleZone], settings.gridCols, settings.gridRows)
        .map((hex) => zoneId(hex.col, hex.row, settings.gridCols))
        .find((id) => !game.zones[id].isCastle)!;
      game.zones[target].neutral = { militia: 18 }; // защита 36 против атаки 30 + герой 5
      game.setArmyGear(player, gear, 0);
      game.move(player, target, 0);
      game.tick(settings.marchSeconds * 1000);
    }
    const weakPlayer = weak.getPlayer(1)!;
    const strongPlayer = strong.getPlayer(1)!;
    assert.equal(weakPlayer.heroZone, weakPlayer.castleZone, "without relics the battle is lost");
    assert.notEqual(strongPlayer.heroZone, strongPlayer.castleZone, "relics won the battle");
  });
});

describe("castle raids", () => {
  function setup() {
    const { game } = createGame();
    const attacker = game.register("Raider", 0);
    const defender = game.register("Victim", 0);
    // Защита новичков закончилась.
    attacker.protectionUntil = 0;
    defender.protectionUntil = 0;
    besideCastle(game, attacker, defender);
    return { game, attacker, defender };
  }

  it("protected castle cannot be attacked; attacking a player removes own protection", () => {
    const { game, attacker, defender } = setup();
    attacker.army = { knight: 10 };
    defender.protectionUntil = HOUR;
    assert.throws(() => game.move(attacker, defender.castleZone, 0), /защитой/);
    defender.protectionUntil = 0;
    attacker.protectionUntil = 100 * HOUR;
    game.move(attacker, defender.castleZone, 0);
    assert.ok(attacker.protectionUntil <= 0);
    assert.equal(attacker.march!.arrivesAt, settings.castleMarchSeconds * 1000);
  });

  it("raid needs an army and the defender sees it coming", () => {
    const { game, attacker, defender } = setup();
    assert.throws(() => game.move(attacker, defender.castleZone, 0), /армия/);
    attacker.army = { militia: 7 };
    game.move(attacker, defender.castleZone, 0);
    const incoming = game.playerView(defender, 1).incoming;
    assert.equal(incoming.length, 1);
    assert.equal(incoming[0].attacker, "Raider");
    assert.equal(incoming[0].castle, true);
    assert.equal(incoming[0].units, 7);
  });

  it("successful raid: loot above the protected amount, defender loses part of the army, shield", () => {
    const { game, attacker, defender } = setup();
    const approach = attacker.heroZone;
    attacker.army = { knight: 200 };
    defender.kingdom.army = { militia: 10 };
    defender.kingdom.resources.gold = 1100;
    defender.kingdom.resources.wood = 50;
    game.move(attacker, defender.castleZone, 0);
    const arrival = settings.castleMarchSeconds * 1000;
    game.tick(arrival);

    const expectedGold = Math.floor((1100 - settings.raidProtectedResource) * settings.raidLootShare);
    const report = game.playerView(attacker, arrival).reports[0].data;
    assert.equal(report.kind, "raid");
    assert.equal(report.loot?.gold, expectedGold);
    // Шаблон для перевода на клиенте: текст = шаблон с подставленными параметрами.
    assert.equal(report.template, "Набег на замок {name} удался");
    assert.deepEqual(report.args, { name: defender.name });
    assert.equal(report.text, `Набег на замок ${defender.name} удался`);
    assert.ok(attacker.kingdom.resources.gold >= gameData.kingdom.startResources.gold + expectedGold);
    assert.equal(defender.kingdom.resources.wood, 50, "resources below the protected amount are safe");
    assert.equal(defender.kingdom.army.militia, 10 * (1 - settings.raidDefenderLoss));
    assert.equal(defender.shieldUntil, arrival + settings.raidShieldHours * HOUR);
    assert.equal(attacker.heroZone, approach, "attacker returns to the zone it came from");
    assert.ok((attacker.army.knight ?? 0) > 0);
    assert.equal(game.zones[defender.castleZone].ownerId, defender.id, "castle is never captured");

    // Под щитом второй набег невозможен.
    assert.throws(() => game.move(attacker, defender.castleZone, arrival), /защитой/);
  });

  it("failed raid: attacker army dies, defenders take losses, no shield", () => {
    const { game, attacker, defender } = setup();
    attacker.army = { militia: 5 };
    defender.kingdom.army = { spearman: 100 };
    game.move(attacker, defender.castleZone, 0);
    game.tick(settings.castleMarchSeconds * 1000);
    assert.deepEqual(attacker.army, {});
    assert.equal(attacker.heroZone, attacker.castleZone);
    assert.ok((defender.kingdom.army.spearman ?? 0) > 0 && (defender.kingdom.army.spearman ?? 0) <= 100);
    assert.equal(defender.shieldUntil, 0);
  });

  it("defender's hero at home defends with its army too", () => {
    const { game, attacker, defender } = setup();
    attacker.army = { knight: 30 };
    defender.kingdom.army = {};
    defender.army = { spearman: 200 };
    game.move(attacker, defender.castleZone, 0);
    game.tick(settings.castleMarchSeconds * 1000);
    assert.deepEqual(attacker.army, {}, "hero army at home repelled the raid");
    assert.ok((defender.army.spearman ?? 0) > 0);
  });

  it("raid is aborted if the castle got a shield while marching", () => {
    const { game, attacker, defender } = setup();
    attacker.army = { knight: 10 };
    game.move(attacker, defender.castleZone, 0);
    defender.shieldUntil = HOUR;
    game.tick(settings.castleMarchSeconds * 1000);
    assert.deepEqual(attacker.army, { knight: 10 });
    assert.notEqual(attacker.heroZone, defender.castleZone);
  });

  it("splitSurvivors keeps totals", () => {
    const [a, b] = splitSurvivors({ militia: 7 }, [{ militia: 10 }, { militia: 4 }]);
    assert.equal((a.militia ?? 0) + (b.militia ?? 0), 7);
    assert.throws(() => { throw new GameError("x"); }, GameError);
  });
});
