class_name MonsterData
extends Resource
## Описание монстра. Новый монстр = новый .tres в data/monsters/.
## Статы указаны для 1-й волны, дальше их масштабирует Monster (рост за волну).

## Поведение в бою.
## FIGHTER — идёт к герою и бьёт вблизи; BRUTE — то же, но медленный, с бронёй и большим запасом здоровья;
## SHOOTER — держит дистанцию и стреляет снарядами; SHAMAN — держится сзади, лечит и усиливает других.
enum Role { FIGHTER, SHOOTER, BRUTE, SHAMAN }
const ROLE_NAMES := {Role.FIGHTER: "Боец", Role.SHOOTER: "Стрелок", Role.BRUTE: "Громила", Role.SHAMAN: "Шаман"}

@export var id := ""
@export var display_name := ""
@export var role: Role = Role.FIGHTER
## Биом (data/biomes/): в каких волнах монстр появляется.
@export var biome := "forest"

@export_group("Visual")
## Спрайт монстра. Рисуется смотрящим ВПРАВО — в игре отражается автоматически.
@export var sprite: Texture2D
@export var sprite_height := 1.2
## Покадровые анимации (idle, walk, attack, hurt, death). Пусто — статичный sprite.
@export var sprite_frames: SpriteFrames
## Оттенок спрайта (пока у монстра нет своей картинки — чужой спрайт в другом цвете).
@export var tint := Color.WHITE

@export_group("Stats")
@export var base_hp := 30.0
@export var base_damage := 5.0
@export var attack_interval := 1.2
@export var attack_range := 1.3
@export var move_speed := 2.5
## Броня: урон × 100 / (100 + броня). Громилы толстокожие — против них хороши криты и умения.
@export var armor := 0.0

@export_group("Ranged")
## Стрелок и шаман останавливаются на этом расстоянии от героя.
@export var preferred_range := 5.0
## Снаряд стрелка (стрела, топор, сгусток магии).
@export var projectile_texture: Texture2D
@export var projectile_tint := Color.WHITE

@export_group("Shaman")
## Раз в ability_interval шаман лечит самого раненого союзника на heal_percent его здоровья
## и усиливает урон союзников рядом на buff_percent на buff_duration секунд.
@export var ability_interval := 4.0
@export var heal_percent := 15.0
@export var buff_percent := 20.0
@export var buff_duration := 5.0

@export_group("Boss")
## Приёмы босса: "slam" — сокрушающий удар с замахом, "summon" — зовёт помощников,
## "shield" — щит на половине здоровья, "enrage" — ярость на четверти здоровья.
@export var boss_abilities: PackedStringArray = []
## Кого зовёт приём summon (id монстра).
@export var summon_id := ""

@export_group("Rewards")
@export var xp_reward := 5
@export var gold_reward := 2
@export_range(0.0, 1.0) var drop_chance := 0.1

@export_group("Spawning")
## С какой волны внутри биома появляется (1–10).
@export var min_wave := 1
## Относительная частота появления среди обычных монстров.
@export var spawn_weight := 1.0
## Босс появляется только на волнах-боссах (каждая 10-я).
@export var is_boss := false


func is_ranged() -> bool:
	return role == Role.SHOOTER or role == Role.SHAMAN
