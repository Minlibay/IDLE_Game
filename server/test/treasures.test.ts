import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { weekIndex } from "../src/world/game.ts";
import { createGame, gameData, settings } from "./helpers.ts";

const MINUTE = 60_000;
const INTERVAL = settings.treasureDropMinutes * MINUTE;

/** Игрок «играет»: опрашивает сервер каждые step мс в течение duration мс. */
function play(game: ReturnType<typeof createGame>["game"], player: Parameters<ReturnType<typeof createGame>["game"]["playerView"]>[0], from: number, duration: number, step = 15_000): number {
  let now = from;
  while (now < from + duration) {
    now += step;
    game.playerView(player, now);
  }
  return now;
}

describe("treasure catalog", () => {
  it("is read from data/treasures with the same ids as the game", () => {
    const warrior = gameData.treasures.byClass.warrior;
    assert.ok(warrior, "warrior catalog loaded");
    assert.equal(warrior.legendary.length % 5, 0, "5 pieces per set");
    assert.ok(warrior.legendary.length >= 40);
    assert.ok(warrior.named.length > 0 && warrior.unique.length > 0);
    assert.ok(gameData.treasures.byId.w_emberforge_helmet, "set piece id = <set>_<slot>");
    assert.equal(gameData.treasures.byId.w_emberforge_helmet.name, "Шлем Закалённого горна");
    for (const classId of ["warrior", "mage", "archer"]) assert.ok(gameData.treasures.byClass[classId], classId);
  });
});

describe("treasure drops by playtime", () => {
  it("drop after the interval of playtime, only for the hero's class", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    game.setHeroClass(player, "mage");
    let now = play(game, player, 0, INTERVAL - MINUTE);
    assert.equal(player.treasures.length, 0, "not yet");
    now = play(game, player, now, 2 * MINUTE);
    assert.equal(player.treasures.length, 1);
    assert.equal(gameData.treasures.byId[player.treasures[0].itemId].classId, "mage");
    const view = game.playerView(player, now);
    assert.equal(view.treasures.length, 1);
    assert.equal(view.treasureWeekCount, 1);
    assert.ok(view.treasureNextMs > 0 && view.treasureNextMs <= INTERVAL);
    assert.equal(view.reports[0].data.kind, "treasure");
    assert.equal(view.reports[0].data.template, "Найдено сокровище: {item} ({quality})");
  });

  it("closed game does not accumulate playtime", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    game.setHeroClass(player, "warrior");
    game.playerView(player, 10_000);
    game.playerView(player, 10_000 + 10 * INTERVAL); // вернулся через 20 часов — пауза не засчитана
    assert.equal(player.treasures.length, 0);
    assert.ok(player.treasurePlaytimeMs <= 10_000);
  });

  it("weekly cap, reset next week", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    game.setHeroClass(player, "archer");
    const start = 0;
    let now = play(game, player, start, (settings.treasureWeeklyCap + 3) * INTERVAL, 60_000);
    assert.equal(player.treasures.length, settings.treasureWeeklyCap, "capped this week");
    // Следующая неделя: находки снова идут.
    const nextWeek = (weekIndex(now) + 1) * 7 * 86_400_000 - 3 * 86_400_000 + 1000;
    player.treasureLastSeen = nextWeek;
    now = play(game, player, nextWeek, 2 * INTERVAL, 60_000);
    assert.ok(player.treasures.length > settings.treasureWeeklyCap, "drops resume next week");
  });

  it("no class — no drops; unknown class rejected", () => {
    const { game } = createGame();
    const player = game.register("A", 0);
    play(game, player, 0, 2 * INTERVAL);
    assert.equal(player.treasures.length, 0);
    assert.throws(() => game.setHeroClass(player, "necromancer"), /класс/);
  });

  it("treasures survive a restart", async () => {
    const { Storage } = await import("../src/storage.ts");
    const storage = new Storage(":memory:");
    const first = createGame({}, storage).game;
    const player = first.register("A", 0);
    first.setHeroClass(player, "warrior");
    play(first, player, 0, INTERVAL + MINUTE);
    assert.equal(player.treasures.length, 1);
    const second = createGame({}, storage).game;
    const loaded = second.getPlayerByToken(player.token)!;
    assert.deepEqual(loaded.treasures.map((t) => t.itemId), player.treasures.map((t) => t.itemId));
  });
});
