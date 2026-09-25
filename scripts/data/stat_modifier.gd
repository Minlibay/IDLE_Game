class_name StatModifier
extends Resource
## Бонус к характеристике (используется талантами). Значение указывается за 1 ранг.

enum Stat {
	DAMAGE,         ## % урона
	MAX_HP,         ## % здоровья
	ARMOR,          ## + единицы брони
	ATTACK_SPEED,   ## % скорости атаки
	CRIT_CHANCE,    ## + % шанса крита
	CRIT_DAMAGE,    ## + % к множителю крита
	SKILL_DAMAGE,   ## % урона умений (всех или skill_id)
	SKILL_COOLDOWN, ## % сокращения перезарядки (всех или skill_id)
	CLICK_POWER,    ## % к ускорению атаки от клика
	GOLD_FIND,      ## % золота
	XP_GAIN,        ## % опыта
	DROP_CHANCE,    ## % шанса выпадения предметов
	REGEN,          ## % регенерации здоровья
	LIFESTEAL,      ## % нанесённого урона возвращается здоровьем
	REST_SPEED,     ## % скорости отдыха (восстановления бодрости)
	NEED_DECAY,     ## % замедления голода/жажды/усталости
}
## Новые значения добавляйте ТОЛЬКО в конец: в .tres статы хранятся числами.

## Имена иконок в assets/sprites/talents/ (в порядке Stat).
const ICON_NAMES := [
	"damage", "max_hp", "armor", "attack_speed", "crit_chance", "crit_damage", "skill_damage",
	"skill_cooldown", "click_power", "gold_find", "xp_gain", "drop_chance", "regen", "lifesteal",
	"rest_speed", "need_decay",
]
const ICON_DIR := "res://assets/sprites/talents/"
## Подписи для describe() (в порядке Stat).
const STAT_LABELS := [
	"урона", "здоровья", "брони", "скорости атаки", "шанса крита", "крит. урона", "урона умений",
	"сокращения перезарядки", "силы клика", "золота", "опыта", "шанса дропа", "регенерации",
	"вампиризма", "скорости отдыха", "замедления голода и жажды",
]

@export var stat: Stat = Stat.DAMAGE
## Значение за 1 ранг таланта. Проценты, кроме ARMOR.
@export var value := 1.0
## Если задано — бонус действует только на это умение (для SKILL_DAMAGE и SKILL_COOLDOWN).
@export var skill_id := ""


## Короткое описание: "+10% здоровья", "+4 брони", "-15% урона". multiplier — уровень/ранг.
func describe(multiplier := 1.0) -> String:
	var amount := value * multiplier
	var sign_text := "+" if amount >= 0.0 else "-"
	var unit := "" if stat == Stat.ARMOR else "%"
	return "%s%s%s %s" % [sign_text, format_number(absf(amount)), unit, STAT_LABELS[stat]]


## Описания списка бонусов через запятую.
static func describe_list(list: Array[StatModifier], multiplier := 1.0) -> String:
	var parts := PackedStringArray()
	for modifier in list:
		parts.append(modifier.describe(multiplier))
	return ", ".join(parts)


## Ключ в словаре бонусов: "стат|skill_id".
static func bonus_key(value_stat: int, value_skill_id: String) -> String:
	return "%d|%s" % [value_stat, value_skill_id]


## Прибавляет бонусы (× multiplier) в словарь «ключ -> значение».
## Общий механизм для талантов, зданий и потребностей.
static func accumulate(target: Dictionary, list: Array[StatModifier], multiplier: float) -> void:
	for modifier in list:
		var key := bonus_key(modifier.stat, modifier.skill_id)
		target[key] = float(target.get(key, 0.0)) + modifier.value * multiplier


## Значение бонуса из словаря: общий бонус + бонус конкретного умения (если skill_id задан).
static func read_bonus(source: Dictionary, value_stat: int, value_skill_id := "") -> float:
	var total := float(source.get(bonus_key(value_stat, ""), 0.0))
	if value_skill_id != "":
		total += float(source.get(bonus_key(value_stat, value_skill_id), 0.0))
	return total


static func get_icon_path(value_stat: int) -> String:
	return ICON_DIR + ICON_NAMES[value_stat] + ".png"


## 4.0 -> "4", 2.5 -> "2.5"
static func format_number(number: float) -> String:
	if is_equal_approx(number, roundf(number)):
		return str(roundi(number))
	return "%.1f" % number
