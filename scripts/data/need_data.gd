class_name NeedData
extends Resource
## Потребность героя (сытость, жажда, бодрость): шкала 0–100, падает во время боя.
## Высокое значение даёт бонусы, низкое — небольшой штраф. Смерти от потребностей нет.
## Новая потребность = новый .tres в data/needs/.

@export var id := ""
@export var display_name := ""
@export var icon: Texture2D
@export var order := 0
@export var bar_color := Color(0.9, 0.6, 0.2)
## Сколько единиц шкалы теряется за минуту боя.
@export var decay_per_minute := 3.0

@export_group("Restore")
## Какой ресурс королевства герой расходует автоматически ("" — не расходует).
@export var consumes_resource := ""
## Сколько шкалы восстанавливает 1 единица ресурса.
@export var restore_per_unit := 20.0
## Восстанавливается отдыхом; на нуле герой сам уходит отдыхать.
@export var restored_by_rest := false

@export_group("Effects")
## От этого значения и выше действуют satisfied_modifiers.
@export var satisfied_threshold := 70.0
## Ниже этого значения действуют low_modifiers.
@export var low_threshold := 30.0
@export var satisfied_modifiers: Array[StatModifier] = []
@export var low_modifiers: Array[StatModifier] = []
