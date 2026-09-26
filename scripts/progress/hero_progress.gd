class_name HeroProgress
extends RefCounted
## Долгий прогресс героя: перерождение и души, бестиарий, счётчики, достижения, ежедневные задания.
## Хранится в сохранении вместе с героем (GameState.progress), переживает перерождение.
##
## Перерождение: с рекорда волны PRESTIGE_MIN_WAVE (в текущей жизни) герой начинает заново — волна 1,
## уровень 1, таланты возвращаются; снаряжение, сокровища, замок и гильдия остаются. Взамен — души
## (souls_for), на которые покупаются вечные улучшения (SOUL_UPGRADES).

signal changed
## Выполнено задание или открыт новый уровень достижения (для уведомления).
signal claimable_added(text: String)

const PRESTIGE_MIN_WAVE := 30

## Вечные улучшения за души: стат (как StatModifier.Stat) и % за ранг; цена = base × growth^ранг.
## Особое — head_start: после перерождения начинать сразу с волны 1 + 5 × ранг.
const SOUL_UPGRADES := [
	{"id": "ancestral_might", "name": "Сила предков", "stat": "DAMAGE", "per_rank": 10.0, "base_cost": 3, "growth": 1.35, "max_rank": 50},
	{"id": "ancestral_vigor", "name": "Стойкость предков", "stat": "MAX_HP", "per_rank": 10.0, "base_cost": 3, "growth": 1.35, "max_rank": 50},
	{"id": "gold_vein", "name": "Золотая жила", "stat": "GOLD_FIND", "per_rank": 15.0, "base_cost": 2, "growth": 1.35, "max_rank": 50},
	{"id": "wisdom", "name": "Мудрость веков", "stat": "XP_GAIN", "per_rank": 10.0, "base_cost": 2, "growth": 1.35, "max_rank": 50},
	{"id": "swiftness", "name": "Стремительность", "stat": "ATTACK_SPEED", "per_rank": 3.0, "base_cost": 4, "growth": 1.5, "max_rank": 20},
	{"id": "fortune", "name": "Благосклонность судьбы", "stat": "DROP_CHANCE", "per_rank": 5.0, "base_cost": 4, "growth": 1.5, "max_rank": 20},
	{"id": "head_start", "name": "Стартовый рывок", "stat": "", "per_rank": 5.0, "base_cost": 5, "growth": 2.0, "max_rank": 5},
]
const HEAD_START_WAVES := 5

## Бестиарий: за столько убийств вида — столько % урона против него. За каждую запись на последнем
## пороге — ещё BESTIARY_MASTERY_DAMAGE % урона против всех.
const BESTIARY_THRESHOLDS := [100, 1000, 10000]
const BESTIARY_DAMAGE := [5.0, 10.0, 15.0]
const BESTIARY_MASTERY_DAMAGE := 1.0

## Достижения: stat — счётчик (или особое значение, см. achievement_value), tiers — пороги, souls — награда за уровень.
## id уровня для Steam: "<id>_<номер уровня>".
const ACHIEVEMENTS := [
	{"id": "slayer", "name": "Истребитель", "desc": "Убейте %s монстров", "stat": "kill", "tiers": [1000, 10000, 100000], "souls": [2, 5, 15]},
	{"id": "elite_hunter", "name": "Охотник на элиту", "desc": "Убейте %s элитных монстров", "stat": "kill_elite", "tiers": [50, 500, 5000], "souls": [2, 5, 15]},
	{"id": "boss_hunter", "name": "Гроза боссов", "desc": "Победите %s боссов", "stat": "kill_boss", "tiers": [10, 100, 500], "souls": [2, 5, 15]},
	{"id": "conqueror", "name": "Покоритель волн", "desc": "Дойдите до %s волны", "stat": "best_wave", "tiers": [25, 50, 100, 200], "souls": [1, 3, 8, 20]},
	{"id": "tireless", "name": "Неутомимый", "desc": "Пройдите %s волн", "stat": "wave", "tiers": [100, 1000, 10000], "souls": [1, 5, 15]},
	{"id": "eternal", "name": "Вечный герой", "desc": "Переродитесь %s раз", "stat": "prestige", "tiers": [1, 5, 25], "souls": [3, 8, 20]},
	{"id": "rich", "name": "Богач", "desc": "Добудьте %s золота с монстров", "stat": "gold", "tiers": [10000, 1000000, 100000000], "souls": [1, 5, 15]},
	{"id": "skill_master", "name": "Мастер умений", "desc": "Примените умения %s раз", "stat": "skill", "tiers": [1000, 10000, 100000], "souls": [2, 5, 15]},
	{"id": "smith", "name": "Мастер заточки", "desc": "Заточите предмет до +%s", "stat": "max_upgrade", "tiers": [5, 10], "souls": [2, 5]},
	{"id": "collector", "name": "Коллекционер", "desc": "Соберите %s сокровищ", "stat": "treasures", "tiers": [1, 10, 30], "souls": [2, 5, 15]},
	{"id": "scholar", "name": "Знаток монстров", "desc": "Изучите %s видов монстров (1000 убийств)", "stat": "bestiary", "tiers": [3, 10, 20], "souls": [3, 8, 20]},
	{"id": "brotherhood", "name": "Братство", "desc": "Вступите в гильдию", "stat": "guild", "tiers": [1], "souls": [2]},
]

## Ежедневные задания: 5 в день из этого списка (guild — только для тех, кто в гильдии).
## target: base + per_level × уровень героя (+ per_wave × рекорд волны), округление до round.
const DAILY_COUNT := 5
const DAILY_TEMPLATES := [
	{"type": "kill", "desc": "Убейте %d монстров", "base": 200, "per_level": 4, "round": 10},
	{"type": "kill_elite", "desc": "Убейте %d элитных монстров", "base": 5, "per_level": 0.1, "round": 1},
	{"type": "kill_boss", "desc": "Победите %d боссов", "base": 2, "per_level": 0.0, "round": 1},
	{"type": "wave", "desc": "Пройдите %d волн", "base": 10, "per_level": 0.1, "round": 1},
	{"type": "skill", "desc": "Примените умения %d раз", "base": 80, "per_level": 1, "round": 10},
	{"type": "gold", "desc": "Добудьте %d золота с монстров", "base": 500, "per_wave": 80, "round": 100},
	{"type": "upgrade", "desc": "Заточите снаряжение %d раза", "base": 2, "per_level": 0.0, "round": 1},
	{"type": "rest", "desc": "Дайте герою отдохнуть %d раз", "base": 1, "per_level": 0.0, "round": 1},
	{"type": "guild_donate", "desc": "Внесите золото в гильдию %d раз", "base": 1, "per_level": 0.0, "round": 1, "guild": true},
	{"type": "guild_boss", "desc": "Атакуйте босса гильдии %d раза", "base": 2, "per_level": 0.0, "round": 1, "guild": true},
]
## Награда за задание: золото (DAILY_GOLD_BASE + DAILY_GOLD_PER_WAVE × рекорд волны) и душа.
const DAILY_GOLD_BASE := 200
const DAILY_GOLD_PER_WAVE := 40
const DAILY_SOULS := 1

var souls := 0
var prestige_count := 0
## Рекорд волны в текущей жизни (для перерождения). Общий рекорд — GameState.best_wave.
var run_best_wave := 1
var soul_upgrades: Dictionary = {}
var bestiary: Dictionary = {}
## Счётчики за всё время: kill, kill_elite, kill_boss, wave, gold, skill, upgrade, rest, prestige…
var stats: Dictionary = {}
## Сколько уровней достижения уже забрано: id → число.
var achievements_claimed: Dictionary = {}
## Задания дня: {"date": "ГГГГ-ММ-ДД", "quests": [{type, desc, target, progress, claimed, gold, souls}]}.
var daily: Dictionary = {}


# --- Бонусы -------------------------------------------------------------------------

## Бонус к стату от улучшений за души и мастерства бестиария (в процентах).
func get_bonus(stat: int) -> float:
	var total := 0.0
	var stat_name: String = StatModifier.Stat.find_key(stat) if StatModifier.Stat.find_key(stat) != null else ""
	for upgrade: Dictionary in SOUL_UPGRADES:
		if upgrade.stat == stat_name:
			total += float(upgrade.per_rank) * get_upgrade_rank(str(upgrade.id))
	return total


## Множитель урона героя по монстру этого вида: бестиарий вида + мастерство всех изученных видов.
func damage_multiplier_vs(monster_id: String) -> float:
	var tier := bestiary_tier(monster_id)
	var bonus: float = BESTIARY_DAMAGE[tier - 1] if tier > 0 else 0.0
	return 1.0 + (bonus + mastered_count() * BESTIARY_MASTERY_DAMAGE) / 100.0


func bestiary_tier(monster_id: String) -> int:
	var kills := int(bestiary.get(monster_id, 0))
	var tier := 0
	for threshold: int in BESTIARY_THRESHOLDS:
		if kills >= threshold:
			tier += 1
	return tier


func mastered_count() -> int:
	var count := 0
	for monster_id: String in bestiary:
		if bestiary_tier(monster_id) >= BESTIARY_THRESHOLDS.size():
			count += 1
	return count


func studied_count(min_tier := 2) -> int:
	var count := 0
	for monster_id: String in bestiary:
		if bestiary_tier(monster_id) >= min_tier:
			count += 1
	return count


# --- События ------------------------------------------------------------------------

## Засчитывает событие: счётчик за всё время + подходящие задания дня.
func record(event: String, amount := 1) -> void:
	stats[event] = int(stats.get(event, 0)) + amount
	ensure_daily()
	for quest: Dictionary in daily.quests:
		if quest.type != event or quest.claimed or int(quest.progress) >= int(quest.target):
			continue
		quest.progress = mini(int(quest.target), int(quest.progress) + amount)
		if int(quest.progress) >= int(quest.target):
			claimable_added.emit(TranslationServer.translate("Задание выполнено: %s") % quest_text(quest))
	changed.emit()


func record_kill(monster_id: String, elite: bool, boss: bool) -> void:
	var before := bestiary_tier(monster_id)
	bestiary[monster_id] = int(bestiary.get(monster_id, 0)) + 1
	if bestiary_tier(monster_id) > before:
		var monster := Database.get_monster(monster_id)
		claimable_added.emit(TranslationServer.translate("Бестиарий: %s изучен до %d уровня") % [monster.display_name if monster else monster_id, before + 1])
	record("kill")
	if elite:
		record("kill_elite")
	if boss:
		record("kill_boss")


# --- Перерождение и души ----------------------------------------------------------------

func can_prestige() -> bool:
	return run_best_wave >= PRESTIGE_MIN_WAVE


## Сколько душ даст перерождение с рекордом волны wave: растёт быстрее, чем сама волна.
static func souls_for(wave: int) -> int:
	if wave < PRESTIGE_MIN_WAVE:
		return 0
	return int(pow(wave / 10.0, 2.0))


func get_upgrade_rank(upgrade_id: String) -> int:
	return int(soul_upgrades.get(upgrade_id, 0))


static func upgrade_cost(upgrade: Dictionary, rank: int) -> int:
	return int(ceil(float(upgrade.base_cost) * pow(float(upgrade.growth), rank)))


func can_buy_upgrade(upgrade: Dictionary) -> bool:
	var rank := get_upgrade_rank(str(upgrade.id))
	return rank < int(upgrade.max_rank) and souls >= upgrade_cost(upgrade, rank)


func buy_upgrade(upgrade_id: String) -> bool:
	for upgrade: Dictionary in SOUL_UPGRADES:
		if upgrade.id != upgrade_id or not can_buy_upgrade(upgrade):
			continue
		var rank := get_upgrade_rank(upgrade_id)
		souls -= upgrade_cost(upgrade, rank)
		soul_upgrades[upgrade_id] = rank + 1
		changed.emit()
		return true
	return false


## С какой волны начинается новая жизнь.
func start_wave() -> int:
	return 1 + HEAD_START_WAVES * get_upgrade_rank("head_start")


# --- Достижения -----------------------------------------------------------------------

## Текущее значение для достижения (счётчик или особая величина).
func achievement_value(achievement: Dictionary) -> int:
	match str(achievement.stat):
		"best_wave":
			return GameState.best_wave
		"treasures":
			return GameState.treasures.size()
		"bestiary":
			return studied_count(2)
		"guild":
			return 1 if not WorldService.my_guild().is_empty() else 0
		"max_upgrade":
			var best := 0
			for item: Item in GameState.inventory + GameState.equipment.values():
				best = maxi(best, item.upgrade_level)
			return best
		_:
			return int(stats.get(achievement.stat, 0))


## Сколько уровней достижения выполнено (не обязательно забрано).
func achievement_tier(achievement: Dictionary) -> int:
	var value := achievement_value(achievement)
	var tier := 0
	for threshold: int in achievement.tiers:
		if value >= threshold:
			tier += 1
	return tier


func claimable_achievements() -> int:
	var count := 0
	for achievement: Dictionary in ACHIEVEMENTS:
		count += achievement_tier(achievement) - int(achievements_claimed.get(achievement.id, 0))
	return count


## Забрать награду за следующий выполненный уровень. Возвращает души (0 — нечего забирать).
func claim_achievement(achievement_id: String) -> int:
	for achievement: Dictionary in ACHIEVEMENTS:
		if achievement.id != achievement_id:
			continue
		var claimed := int(achievements_claimed.get(achievement_id, 0))
		if claimed >= achievement_tier(achievement):
			return 0
		var reward := int(achievement.souls[claimed])
		achievements_claimed[achievement_id] = claimed + 1
		souls += reward
		changed.emit()
		return reward
	return 0


# --- Ежедневные задания ------------------------------------------------------------------

## Новый день — новые задания (детерминированно по дате и имени героя).
func ensure_daily() -> void:
	var today := Time.get_date_string_from_system()
	if daily.get("date", "") == today and daily.has("quests"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today + GameState.hero_name)
	var pool := []
	var in_guild := not WorldService.my_guild().is_empty()
	for template: Dictionary in DAILY_TEMPLATES:
		if not template.get("guild", false) or in_guild:
			pool.append(template)
	var quests := []
	while quests.size() < DAILY_COUNT and not pool.is_empty():
		var template: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var raw := float(template.base) + float(template.get("per_level", 0.0)) * GameState.level \
			+ float(template.get("per_wave", 0.0)) * run_best_wave
		var step := int(template.round)
		quests.append({
			"type": template.type,
			"desc": template.desc,
			"target": maxi(1, int(round(raw / step)) * step),
			"progress": 0,
			"claimed": false,
			"gold": DAILY_GOLD_BASE + DAILY_GOLD_PER_WAVE * run_best_wave,
			"souls": DAILY_SOULS,
		})
	daily = {"date": today, "quests": quests}


func quest_text(quest: Dictionary) -> String:
	return TranslationServer.translate(str(quest.desc)) % int(quest.target)


func claimable_quests() -> int:
	ensure_daily()
	var count := 0
	for quest: Dictionary in daily.quests:
		if not quest.claimed and int(quest.progress) >= int(quest.target):
			count += 1
	return count


## Забрать награду за задание index: золото герою и душа. true — забрано.
func claim_quest(index: int) -> bool:
	ensure_daily()
	if index < 0 or index >= daily.quests.size():
		return false
	var quest: Dictionary = daily.quests[index]
	if quest.claimed or int(quest.progress) < int(quest.target):
		return false
	quest.claimed = true
	souls += int(quest.souls)
	GameState.add_gold(int(quest.gold))
	changed.emit()
	return true


func claimable_total() -> int:
	return claimable_quests() + claimable_achievements()


# --- Сохранение -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"souls": souls,
		"prestige_count": prestige_count,
		"run_best_wave": run_best_wave,
		"soul_upgrades": soul_upgrades,
		"bestiary": bestiary,
		"stats": stats,
		"achievements_claimed": achievements_claimed,
		"daily": daily,
	}


## default_run_best — для старых сохранений (до перерождений): рекорд волны героя.
func from_dict(data: Dictionary, default_run_best: int) -> void:
	souls = maxi(0, int(data.get("souls", 0)))
	prestige_count = maxi(0, int(data.get("prestige_count", 0)))
	run_best_wave = maxi(1, int(data.get("run_best_wave", default_run_best)))
	soul_upgrades = _int_dict(data.get("soul_upgrades", {}))
	bestiary = _int_dict(data.get("bestiary", {}))
	stats = _int_dict(data.get("stats", {}))
	achievements_claimed = _int_dict(data.get("achievements_claimed", {}))
	var saved_daily: Variant = data.get("daily", {})
	daily = saved_daily if saved_daily is Dictionary else {}


static func _int_dict(value: Variant) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key: Variant in value:
			result[str(key)] = maxi(0, int(value[key]))
	return result
