class_name UiFormat
extends RefCounted
## Форматирование чисел и времени для интерфейса.


## 3725 -> "1 ч 2 мин", 190 -> "3 мин 10 с", 45 -> "45 с".
static func duration(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return TranslationServer.translate("%d ч %d мин") % [hours, minutes]
	if minutes > 0:
		return TranslationServer.translate("%d мин %d с") % [minutes, secs] if secs > 0 else TranslationServer.translate("%d мин") % minutes
	return TranslationServer.translate("%d с") % secs


## «1 душа», «3 души», «5 душ» — форма по числу и правилам языка (ключи перевода — русские формы:
## «душа» — для 1, «души» — «несколько» (2–4 в русском, украинском, польском), «душ» — остальное).
static func souls(count: int) -> String:
	return "%d %s" % [count, TranslationServer.translate(plural(count, "душа", "души", "душ"))]


## Форма слова по числу для текущего языка: one / few / many (few есть в русском, украинском и польском).
static func plural(count: int, one: String, few: String, many: String) -> String:
	var locale := TranslationServer.get_locale()
	if locale.begins_with("ru") or locale.begins_with("uk"):
		return plural_ru(count, one, few, many)
	if locale.begins_with("pl"):
		var n := absi(count)
		if n == 1:
			return one
		return few if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14] else many
	return one if absi(count) == 1 else many


## Русская форма слова по числу: 1 — one, 2–4 — few, 5–20 и остальные — many.
static func plural_ru(count: int, one: String, few: String, many: String) -> String:
	var n := absi(count) % 100
	if n >= 11 and n <= 19:
		return many
	match n % 10:
		1:
			return one
		2, 3, 4:
			return few
	return many


## Стоимость в виде «60 Дерево, 30 Камень, 100 Золото».
static func cost(cost_dict: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id: String in cost_dict:
		parts.append("%d %s" % [int(cost_dict[resource_id]), KingdomState.resource_name(resource_id)])
	return ", ".join(parts)
