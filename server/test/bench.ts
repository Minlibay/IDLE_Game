// Нагрузочный замер сервера (не входит в npm test): мир с сотнями игроков и гильдий.
//   node --disable-warning=ExperimentalWarning test/bench.ts [игроков]
// Печатает время основных операций; ориентир — единицы миллисекунд на запрос.

import { createGame } from "./helpers.ts";

const PLAYERS = Number(process.argv[2] ?? 500);
const GUILD_SIZE = 20;

const { game } = createGame({ guildCreateCost: 0 });
const players = [];
let start = performance.now();
for (let i = 0; i < PLAYERS; i++) players.push(game.register(`P${i}`, 0));
console.log(`register ${PLAYERS}: ${(performance.now() - start).toFixed(0)} ms`);

// Гильдии по GUILD_SIZE игроков и по 15 зон у каждого игрока.
start = performance.now();
for (let g = 0; g * GUILD_SIZE < PLAYERS; g++) {
  const leader = players[g * GUILD_SIZE];
  game.guilds.create(leader, `Гильдия ${g}`, `G${g}`, "#e05a4f", 0);
  for (let m = 1; m < GUILD_SIZE && g * GUILD_SIZE + m < PLAYERS; m++) {
    const member = players[g * GUILD_SIZE + m];
    game.guilds.invite(leader, member.name, 0);
    game.guilds.accept(member, leader.guildId, 0);
  }
}
let zone = 0;
for (const player of players) {
  for (let k = 0; k < 15; k++) {
    while (game.zones[zone].ownerId !== null) zone++;
    game.zones[zone].ownerId = player.id;
  }
}
console.log(`guilds + zones: ${(performance.now() - start).toFixed(0)} ms`);

function time(label: string, runs: number, work: () => unknown): void {
  const t0 = performance.now();
  for (let i = 0; i < runs; i++) work();
  console.log(`${label}: ${((performance.now() - t0) / runs).toFixed(2)} ms`);
}

time("playerView (poll /api/me)", 200, () => game.playerView(players[Math.floor(Math.random() * PLAYERS)], 1000));
time("guild view (/api/guild)", 200, () => game.guilds.view(players[Math.floor(Math.random() * PLAYERS)], 0, 1000));
time("worldView full map", 5, () => JSON.stringify(game.worldView(0, 1000)));
time("worldView incremental", 200, () => game.worldView(game.worldVersion, 1000));
time("tick (no marches)", 200, () => game.tick(2000));
let now = 60_000;
time("tick with season minute", 20, () => { now += 60_000; game.tick(now); });
