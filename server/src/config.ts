// Все числа баланса и настройки сервера — здесь.
// Часть можно переопределить переменными окружения (удобно для тестов и хостинга).

const env = process.env;

export const CONFIG = {
  host: env.HOST ?? "127.0.0.1",
  port: Number(env.PORT ?? 8787),
  dbPath: env.DB_PATH ?? "data/world.db",
  gameDataPath: env.GAME_DATA_PATH ?? "data/game_data.json",
  worldSeed: Number(env.WORLD_SEED ?? 20260925),

  // Карта: 50 × 40 = 2000 шестиугольных зон. Уровень 1 — края, уровень 10 — центр.
  gridCols: 50,
  gridRows: 40,
  tiers: 10,

  // Поход в соседнюю зону, секунд.
  marchSeconds: Number(env.MARCH_SECONDS ?? 20),
  tickMs: 1000,

  // Бой: атака атакующего против защиты обороняющегося.
  heroPowerPerLevel: 5,
  // Потери победителя = (сила проигравшего / сила победителя) ^ lossExponent.
  lossExponent: 1.5,
  // Удача: сила каждой стороны умножается на случайное 1 ± luck.
  luck: 0.1,

  // Нейтральная армия: бюджет силы = base × growth^(уровень-1).
  neutralBasePower: 20,
  neutralPowerGrowth: 1.6,
  neutralSpread: 0.15,

  // Замки игроков — только в зонах 1-го уровня и не ближе этого расстояния друг к другу.
  castleMinDistance: 3,

  // Пассивный бонус зоны владельцу: bonusPerTier × уровень зоны (в процентах).
  bonusPerTier: 0.3,
  // Имена совпадают с StatModifier.Stat в клиенте.
  bonusStats: ["GOLD_FIND", "XP_GAIN", "DAMAGE", "ARMY_POWER", "TRAINING_SPEED", "DROP_CHANCE", "MAX_HP"],

  maxUnitsPerType: 1_000_000,
  maxNameLength: 20,
  reportsKept: 30,
  maxBodyBytes: 64 * 1024,
} as const;
