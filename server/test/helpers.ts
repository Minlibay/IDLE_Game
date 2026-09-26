import { CONFIG } from "../src/config.ts";
import { loadGameData } from "../src/gameData.ts";
import { Storage } from "../src/storage.ts";
import { Game, type GameSettings, type Player } from "../src/world/game.ts";
import { seededRandom } from "../src/world/generator.ts";

const localPath = (relative: string) => new URL(relative, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
export const gameData = loadGameData(localPath("../data/game_data.json"), localPath("../../data/treasures"), localPath("../../data/guild/guild.json"));

export const settings: GameSettings = { ...CONFIG, marchSeconds: 10, castleMarchSeconds: 30, luck: 0, devSpeed: 1 };

/** Игра в памяти с детерминированной удачей. */
export function createGame(overrides: Partial<GameSettings> = {}, storage = new Storage(":memory:")): { game: Game; storage: Storage } {
  const game = new Game(storage, gameData, { ...settings, ...overrides }, seededRandom(42), 0);
  return { game, storage };
}

/** Выдать игроку солдат прямо в замок (в тестах вместо долгого обучения). */
export function giveArmy(player: Player, army: Record<string, number>): void {
  for (const [id, count] of Object.entries(army)) player.kingdom.army[id] = (player.kingdom.army[id] ?? 0) + count;
}
