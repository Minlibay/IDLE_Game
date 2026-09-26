class_name GuildCatalog
extends RefCounted
## Дерево бонусов гильдий и названия регионов карты из data/guild/guild.json.
## Тот же файл читает сервер (server/src/gameData.ts): очки, ранги и эффекты считает он,
## клиент берёт отсюда названия, подписи и значения для показа.

const PATH := "res://data/guild/guild.json"
## Иконки бонусов по стату (иконки талантов); чего нет — значок гильдии.
const ICONS := {
	"GOLD_FIND": "res://assets/sprites/talents/gold_find.png",
	"XP_GAIN": "res://assets/sprites/talents/xp_gain.png",
	"DROP_CHANCE": "res://assets/sprites/talents/drop_chance.png",
	"ARMY_POWER": "res://assets/sprites/talents/army_power.png",
	"TRAINING_SPEED": "res://assets/sprites/talents/training_speed.png",
	"UPKEEP_REDUCTION": "res://assets/sprites/talents/need_decay.png",
	"DAMAGE": "res://assets/sprites/talents/damage.png",
	"MAX_HP": "res://assets/sprites/talents/max_hp.png",
}
const DEFAULT_ICON := "res://assets/ui/icons/banner.png"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"branches": [], "regions": [], "branch_tier_points": [], "perk_points_per_level": 0}
	return _data


static func branches() -> Array:
	return data().get("branches", [])


static func tier_points(index: int) -> int:
	var points: Array = data().get("branch_tier_points", [])
	return int(points[index]) if index < points.size() else 0


static func region_name(index: int) -> String:
	var regions: Array = data().get("regions", [])
	return TranslationServer.translate(str(regions[index])) if index >= 0 and index < regions.size() else ""


static func perk_icon(stat: String) -> Texture2D:
	return load(ICONS.get(stat, DEFAULT_ICON))


## «+10% золота с монстров» — значение ранга (1…) с переведённой подписью.
static func perk_effect(perk: Dictionary, rank: int) -> String:
	var values: Array = perk.values
	if rank <= 0 or rank > values.size():
		return ""
	return "+%s%% %s" % [StatModifier.format_number(float(values[rank - 1])), TranslationServer.translate(str(perk.label))]


## Сейчас и после повышения одной строкой: «+5% → +10% золота с монстров», «изучите: +5% …», «+15% … (макс.)».
static func perk_progress(perk: Dictionary, rank: int) -> String:
	var values: Array = perk.values
	var label := TranslationServer.translate(str(perk.label))
	if rank <= 0:
		return TranslationServer.translate("изучите: %s") % perk_effect(perk, 1)
	if rank >= values.size():
		return TranslationServer.translate("%s (макс.)") % perk_effect(perk, rank)
	return "+%s%% → +%s%% %s" % [StatModifier.format_number(float(values[rank - 1])), StatModifier.format_number(float(values[rank])), label]
