class_name CharacterClass
extends Resource
## Описание класса героя. Новый класс = новый .tres в data/classes/ (подхватится автоматически).

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## Порядок карточки на экране создания героя.
@export var order := 0

@export_group("Visual")
## Спрайт героя. Персонаж смотрит вправо, ноги у нижнего края.
@export var sprite: Texture2D
## Высота спрайта в мире (в метрах). Размер картинки в пикселях не важен.
@export var sprite_height := 1.6
## Если задан — герой атакует снарядами (дальний бой).
@export var projectile_texture: Texture2D

@export_group("Stats")
@export var base_max_hp := 100.0
@export var hp_per_level := 12.0
@export var base_damage := 10.0
@export var damage_per_level := 2.0
@export var base_armor := 0.0
## Секунд между атаками.
@export var attack_interval := 1.0
## Дальность атаки в метрах.
@export var attack_range := 2.0
@export_range(0.0, 1.0) var crit_chance := 0.05

@export_group("Skills")
## Умения класса (data/skills/). Порядок на панели — по уровню открытия.
@export var skills: Array[SkillData] = []

@export_group("Talents")
@export var talent_tree: TalentTree


func is_ranged() -> bool:
	return projectile_texture != null
