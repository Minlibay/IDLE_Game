import { CONFIG } from "../src/config.ts";
import { loadGameData } from "../src/gameData.ts";
import { Storage } from "../src/storage.ts";
import { Game, type GameSettings } from "../src/world/game.ts";
import { seededRandom } from "../src/world/generator.ts";

export const gameData = loadGameData(new URL("../data/game_data.json", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));

export const settings: GameSettings = { ...CONFIG, marchSeconds: 10, luck: 0 };

/** Игра в памяти с детерминированной удачей. */
export function createGame(overrides: Partial<GameSettings> = {}, storage = new Storage(":memory:")): { game: Game; storage: Storage } {
  const game = new Game(storage, gameData.units, { ...settings, ...overrides }, seededRandom(42));
  return { game, storage };
}
