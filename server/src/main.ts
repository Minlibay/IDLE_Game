// Точка входа сервера мировой карты. Запуск: npm start (из папки server/).

import { CONFIG } from "./config.ts";
import { loadGameData } from "./gameData.ts";
import { createHttpServer } from "./http.ts";
import { Storage } from "./storage.ts";
import { Game } from "./world/game.ts";

const gameData = loadGameData(CONFIG.gameDataPath);
const storage = new Storage(CONFIG.dbPath);
const game = new Game(storage, gameData, CONFIG);
const server = createHttpServer(game, gameData, CONFIG);

const ticker = setInterval(() => {
  try {
    game.tick(Date.now());
  } catch (error) {
    console.error("tick failed", error);
  }
}, CONFIG.tickMs);

server.listen(CONFIG.port, CONFIG.host, () => {
  console.log(`World server: http://${CONFIG.host}:${CONFIG.port}  (zones: ${game.zones.length}, db: ${CONFIG.dbPath})`);
});

function shutdown(): void {
  clearInterval(ticker);
  server.close(() => {
    storage.close();
    process.exit(0);
  });
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
