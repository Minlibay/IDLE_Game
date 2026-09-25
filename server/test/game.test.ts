import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Storage } from "../src/storage.ts";
import { GameError, type Game, type Player } from "../src/world/game.ts";
import { hexDistance, neighbors, zoneId } from "../src/world/grid.ts";
import { createGame, giveArmy, settings } from "./helpers.ts";

const MARCH_MS = settings.marchSeconds * 1000;

/** Соседняя с героем зона, подходящая под условие. */
function neighbourZone(game: Game, player: Player, filter: (id: number) => boolean = () => true): number {
  const from = game.zones[player.heroZone];
  const ids = neighbors(from, settings.gridCols, settings.gridRows).map((hex) => zoneId(hex.col, hex.row, settings.gridCols));
  const id = ids.find((candidate) => !game.zones[candidate].isCastle && filter(candidate));
  assert.ok(id !== undefined, "no suitable neighbour zone");
  return id;
}

/** Совершить поход и дождаться прибытия. */
function march(game: Game, player: Player, target: number, now: number): number {
  game.move(player, target, now);
  const arrival = now + MARCH_MS;
  game.tick(arrival);
  return arrival;
}

describe("game rules", () => {
  it("new player gets a castle on the map edge", () => {
    const { game } = createGame();
    const player = game.register("Антон", 0);
    const castle = game.zones[player.castleZone];
    assert.equal(castle.tier, 1);
    assert.equal(castle.isCastle, true);
    assert.equal(castle.ownerId, player.id);
    assert.equal(player.heroZone, player.castleZone);
  });

  it("castles keep a minimum distance and names are unique", () => {
    const { game } = createGame();
    const a = game.register("A", 0);
    const b = game.register("B", 0);
    assert.ok(hexDistance(game.zones[a.castleZone], game.zones[b.castleZone]) >= settings.castleMinDistance);
    assert.throws(() => game.register("a", 0), GameError);
  });

  it("can only move to adjacent zones and not while marching", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    const far = (player.castleZone + game.zones.length / 2) % game.zones.length;
    assert.throws(() => game.move(player, far, 0), /соседнюю/);
    const target = neighbourZone(game, player);
    game.move(player, target, 0);
    assert.throws(() => game.move(player, target, 1), /походе/);
  });

  it("strong army captures a neutral zone; weak army dies and hero returns home", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    giveArmy(player, { knight: 50 });
    game.deploy(player, { knight: 50 }, 0);
    const target = neighbourZone(game, player);
    march(game, player, target, 0);
    assert.equal(game.zones[target].ownerId, player.id);
    assert.equal(player.heroZone, target);

    const weak = game.register("Weak", 0);
    giveArmy(weak, { militia: 1 });
    game.deploy(weak, { militia: 1 }, 0);
    const hard = neighbourZone(game, weak, (id) => Object.keys(game.zones[id].neutral).length > 0);
    game.zones[hard].neutral = { knight: 500 };
    march(game, weak, hard, 0);
    assert.equal(game.zones[hard].ownerId, null);
    assert.deepEqual(weak.army, {});
    assert.equal(weak.heroZone, weak.castleZone);
  });

  it("enemy zone without garrison and without its owner is captured freely", () => {
    const { game } = createGame();
    const owner = game.register("Owner", 0);
    const attacker = game.register("Attacker", 0);
    const zone = neighbourZone(game, owner);
    game.zones[zone].ownerId = owner.id;
    game.zones[zone].neutral = {};
    // Ставим атакующего по соседству с зоной.
    const approach = neighbors(game.zones[zone], settings.gridCols, settings.gridRows)
      .map((hex) => zoneId(hex.col, hex.row, settings.gridCols))
      .find((id) => !game.zones[id].isCastle)!;
    game.zones[approach].ownerId = attacker.id;
    attacker.heroZone = approach;

    march(game, attacker, zone, 0);
    assert.equal(game.zones[zone].ownerId, attacker.id, "undefended zone must be captured");
  });

  it("PvP: defender present with army — loser's army dies, loser's hero goes home", () => {
    const { game } = createGame();
    const owner = game.register("Owner", 0);
    const attacker = game.register("Attacker", 0);
    const zone = neighbourZone(game, owner);
    game.zones[zone].ownerId = owner.id;
    game.zones[zone].neutral = {};
    owner.heroZone = zone;
    owner.army = { spearman: 200 };
    const approach = neighbors(game.zones[zone], settings.gridCols, settings.gridRows)
      .map((hex) => zoneId(hex.col, hex.row, settings.gridCols))
      .find((id) => !game.zones[id].isCastle && id !== owner.castleZone)!;
    game.zones[approach].ownerId = attacker.id;
    attacker.heroZone = approach;
    attacker.army = { militia: 10 };

    march(game, attacker, zone, 0);
    assert.equal(game.zones[zone].ownerId, owner.id, "defender keeps the zone");
    assert.deepEqual(attacker.army, {}, "attacker army is wiped");
    assert.equal(attacker.heroZone, attacker.castleZone, "attacker hero returns home");
    assert.ok((owner.army.spearman ?? 0) > 0 && (owner.army.spearman ?? 0) <= 200, "defender takes some losses");

    // Теперь атакующий приходит с огромной армией и побеждает.
    attacker.heroZone = approach;
    attacker.army = { knight: 2000 };
    march(game, attacker, zone, MARCH_MS * 3);
    assert.equal(game.zones[zone].ownerId, attacker.id);
    assert.deepEqual(owner.army, {}, "defender army is wiped");
    assert.equal(owner.heroZone, owner.castleZone, "defender hero returns home");
  });

  it("garrison defends the zone while the hero is away", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    giveArmy(player, { knight: 60 });
    game.deploy(player, { knight: 60 }, 0);
    const zone = neighbourZone(game, player);
    march(game, player, zone, 0);
    const afterCapture = player.army.knight ?? 0; // часть рыцарей погибла в бою с нейтралами
    game.garrison(player, { knight: 20 }, 0);
    assert.deepEqual(game.zones[zone].garrison, { knight: 20 });
    assert.deepEqual(player.army, { knight: afterCapture - 20 });
    game.withdraw(player, { knight: 5 }, 0);
    assert.deepEqual(game.zones[zone].garrison, { knight: 15 });
    assert.throws(() => game.withdraw(player, { knight: 99 }, 0), GameError);
  });

  it("deploy and recall only at the castle, units come from the castle army", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    assert.throws(() => game.deploy(player, { militia: 1 }, 0), /нет столько/);
    giveArmy(player, { militia: 10 });
    game.deploy(player, { militia: 10 }, 0);
    assert.deepEqual(game.recall(player, { militia: 4 }, 0), { militia: 4 });
    assert.deepEqual(player.army, { militia: 6 });
    assert.deepEqual(player.kingdom.army, { militia: 4 });
    assert.throws(() => game.recall(player, { militia: 100 }, 0), GameError);
    player.heroZone = neighbourZone(game, player);
    assert.throws(() => game.deploy(player, { militia: 1 }, 0), /замке/);
  });

  it("owned zones give passive bonuses", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    giveArmy(player, { knight: 100 });
    game.deploy(player, { knight: 100 }, 0);
    const zone = neighbourZone(game, player);
    march(game, player, zone, 0);
    const view = game.playerView(player, 0);
    assert.equal(view.zonesOwned, 2);
    const bonus = game.zones[zone].bonus;
    assert.ok((view.bonuses[bonus.stat] ?? 0) >= bonus.value);
  });

  it("changing the world size regenerates the map and relocates players", () => {
    const storage = new Storage(":memory:");
    const small = createGame({ gridCols: 20, gridRows: 20 }, storage).game;
    const player = small.register("A", 0);
    giveArmy(player, { knight: 7 });
    small.deploy(player, { knight: 7 }, 0);
    const big = createGame({}, storage).game;
    assert.equal(big.zones.length, settings.gridCols * settings.gridRows);
    const moved = big.getPlayerByToken(player.token);
    assert.ok(moved, "account must survive the resize");
    assert.deepEqual(moved.army, { knight: 7 }, "army with the hero is kept");
    assert.equal(big.zones[moved.castleZone].ownerId, player.id);
    assert.equal(big.zones[moved.castleZone].isCastle, true);
    assert.equal(moved.heroZone, moved.castleZone);
  });

  it("world state survives a restart", () => {
    const storage = new Storage(":memory:");
    const first = createGame({}, storage).game;
    const player = first.register("A", 0);
    giveArmy(player, { knight: 5 });
    first.deploy(player, { knight: 5 }, 0);
    const second = createGame({}, storage).game;
    const loaded = second.getPlayerByToken(player.token);
    assert.ok(loaded);
    assert.deepEqual(loaded.army, { knight: 5 });
    assert.equal(second.zones[player.castleZone].ownerId, player.id);
  });

  it("world view returns only changed zones with since", () => {
    const { game } = createGame();
    const full = game.worldView(0, 0);
    game.register("A", 0);
    const before = game.worldVersion;
    game.register("B", 0);
    const delta = game.worldView(before, 0);
    assert.equal(delta.zones.length, 1);
    assert.equal(full.zones.length, game.zones.length);
  });
});
