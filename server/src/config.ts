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

  // Сокровища (именные, уникальные, сетовые): выпадают по игровому времени — пока игра запущена
  // (клиент опрашивает сервер; пауза между запросами больше treasureMaxGapSeconds не засчитывается).
  treasuresDir: env.TREASURES_DIR ?? "../data/treasures",
  // Дерево бонусов гильдий и названия регионов — общий с игрой файл.
  guildDataPath: env.GUILD_DATA ?? "../data/guild/guild.json",
  treasureDropMinutes: Number(env.TREASURE_DROP_MINUTES ?? 120),
  treasureWeeklyCap: 5,
  treasureMaxGapSeconds: 90,
  // Шансы качества находки (веса).
  treasureWeights: { named: 65, unique: 25, legendary: 10 },

  // Гильдии. Создание — золото из казны замка. Места: база + за каждый уровень.
  guildCreateCost: Number(env.GUILD_CREATE_COST ?? 1000),
  guildNameMinLength: 3,
  guildNameMaxLength: 24,
  guildTagMinLength: 2,
  guildTagMaxLength: 4,
  guildBaseSlots: 20,
  guildSlotsPerLevel: 5,
  // Опыт для уровня (всего): 1-й … 7-й (7-й — максимум, 50 мест). Опыт: 1 золото взноса = 1, победы на карте.
  guildLevelXp: [0, 5_000, 15_000, 35_000, 70_000, 120_000, 200_000],
  guildInviteHours: 48,
  // После выхода или исключения вступить в другую гильдию можно только через столько часов.
  guildRejoinHours: 24,
  // Глава не заходил столько дней — главенство переходит офицеру (или самому давнему участнику).
  guildLeaderInactiveDays: 14,
  // Бонус к силе армии: % за участника, потолок = base + perLevel × (уровень − 1).
  guildBonusPerMember: 1,
  guildBonusBaseCap: 5,
  guildBonusCapPerLevel: 1,
  // Опыт гильдии за победы участников: над нейтралами — × уровень зоны; над игроками (и отбитая атака).
  guildXpPerNeutralTier: 30,
  guildXpPerPvpWin: 200,
  guildChatKept: 100,
  guildChatMaxLength: 200,
  guildChatCooldownMs: 1000,
  // Сброс бонусов гильдии — не чаще раза в столько часов.
  guildPerkResetHours: 24,
  // Босс гильдии (раз в неделю): здоровье = base × growth^(уровень−1) × max(minMembers, участников).
  guildBossBaseHp: 3000,
  guildBossHpGrowth: 1.5,
  guildBossMinMembers: 3,
  guildBossAttacksPerDay: 3,
  guildBossLuck: 0.1,
  // Награда за победу: золото каждому, кто бил босса, и опыт гильдии — × уровень босса.
  guildBossGoldPerLevel: 400,
  guildBossXpPerLevel: 1000,
  // Сезон войны гильдий: очки в час = сумма уровней зон участников (в своём регионе × regionControlMultiplier).
  seasonDays: Number(env.SEASON_DAYS ?? 14),
  seasonTickMinutes: 1,
  // Карта делится на regionGrid × regionGrid регионов; контроль — у гильдии с большинством зон (не меньше regionMinZones).
  regionGrid: 5,
  regionMinZones: 10,
  regionControlMultiplier: 1.5,
  // Награды тройке лидеров сезона: золото каждому участнику и опыт гильдии.
  seasonRewards: [{ gold: 3000, xp: 5000 }, { gold: 2000, xp: 3000 }, { gold: 1000, xp: 1500 }],
  seasonStandingsShown: 10,
  // Подкрепления союзнику: всего не больше этой доли мест в армии его замка; в пути — как набег (castleMarchSeconds).
  reinforcementShare: 0.5,
  guildColors: ["#e05a4f", "#f0a038", "#e8d44d", "#6cc75a", "#3fbfb0", "#4a90e2", "#8f6ae0", "#d65fb5", "#c8c8d0", "#8b6a4a"],

  maxUnitsPerType: 1_000_000,
  maxNameLength: 20,
  reportsKept: 30,
  maxBodyBytes: 64 * 1024,
  // Ответы крупнее этого сжимаются gzip (полная карта ~1.5 МБ -> в разы меньше).
  gzipMinBytes: 2048,
} as const;
