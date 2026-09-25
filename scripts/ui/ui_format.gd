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


## Стоимость в виде «60 Дерево, 30 Камень, 100 Золото».
static func cost(cost_dict: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id: String in cost_dict:
		parts.append("%d %s" % [int(cost_dict[resource_id]), KingdomState.resource_name(resource_id)])
	return ", ".join(parts)
