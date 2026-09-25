// Все числа баланса и настройки сервера — здесь.
// Часть можно переопределить переменными окружения (удобно для тестов и хостинга).

const env = process.env;

export const CONFIG = {
  host: env.HOST ?? "127.0.0.1",
  port: Number(env.PORT ?? 8787),
  dbPath: env.DB_PATH ?? "data/world.db",
  gameDataPath: env.GAME_DATA_PATH ?? "data/game_data.json",
  worldSeed: Number(env.WORLD_SEED ?? 20260925),

  // Карта: 100 × 100 = 10 000 шестиугольных зон. Уровень 1 — края, уровень 10 — центр.
  // При смене размера существующий мир пересоздаётся (аккаунты сохраняются, замки — новые).
  gridCols: 100,
  gridRows: 100,
  tiers: 10,

  // Поход в соседнюю зону, секунд.
  marchSeconds: Number(env.MARCH_SECONDS ?? 20),
  // Поход на чужой замок (набег) дольше — у защитника есть время подготовиться.
  castleMarchSeconds: Number(env.CASTLE_MARCH_SECONDS ?? 90),
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

  // Экономика замка. DEV_SPEED > 1 ускоряет стройку и обучение (и даёт больше стартовых ресурсов) — для тестов.
  devSpeed: Number(env.DEV_SPEED ?? 1),

  // Набеги на замки: добыча = raidLootShare × (ресурс − raidProtectedResource).
  raidLootShare: 0.2,
  raidProtectedResource: 100,
  // Защитник проигранного набега теряет эту долю армии (не всю, в отличие от боёв на карте).
  raidDefenderLoss: 0.5,
  // Щит после набега и защита новичка, часов.
  raidShieldHours: 4,
  newbieProtectionHours: 72,

  // Взнос золота героя в казну: лимит копится depositPerLevelPerMinute × уровень героя в минуту,
  // максимум — за depositBankMinutes минут.
  depositPerLevelPerMinute: 2,
  depositBankMinutes: 12 * 60,

  // Потолки бонусов реликвий армии (сумма всех 6 слотов, %). Предметы пока считает клиент —
  // сервер не даёт больше этих значений, сколько бы ни прислали.
  armyGearCaps: { ARMY_POWER: 60, ARMY_ATTACK: 60, ARMY_DEFENSE: 60, TRAINING_SPEED: 100, UPKEEP_REDUCTION: 50 },

  maxUnitsPerType: 1_000_000,
  maxNameLength: 20,
  reportsKept: 30,
  maxBodyBytes: 64 * 1024,
  // Ответы крупнее этого сжимаются gzip (полная карта ~1.5 МБ -> в разы меньше).
  gzipMinBytes: 2048,
} as const;
