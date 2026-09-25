class_name TalentTree
extends Resource
## Дерево талантов класса: названия веток и список талантов.
## Один файл на класс: data/talents/<класс>_talents.tres (таланты — вложенные ресурсы).

@export var branch_names: PackedStringArray = []
## Сколько очков нужно вложить в ветку, чтобы открыть следующий ряд.
@export var points_per_row := 3
@export var talents: Array[TalentData] = []


func get_required_points(talent: TalentData) -> int:
	return talent.row * points_per_row


func get_talents_in_branch(branch: int) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for talent in talents:
		if talent.branch == branch:
			result.append(talent)
	result.sort_custom(func(a: TalentData, b: TalentData) -> bool: return a.row < b.row)
	return result


func find(talent_id: String) -> TalentData:
	for talent in talents:
		if talent.id == talent_id:
			return talent
	return null
