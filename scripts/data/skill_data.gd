class_name SkillData
extends Resource
## Умение класса. Что именно оно делает, задаёт effect:
## StrikeEffect (удар), AreaEffect (область), MultiShotEffect (залп), BuffEffect (усиление).
## Новое умение = новый .tres в data/skills/ + добавить его в список skills класса.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## Цвет названия умения, всплывающего над героем.
@export var color := Color(0.6, 0.9, 1.0)
## Перезарядка в секундах.
@export var cooldown := 8.0
## С какого уровня героя умение доступно.
@export var unlock_level := 1
@export var effect: SkillEffect
