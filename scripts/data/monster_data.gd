class_name MonsterData
extends Resource
## Описание монстра. Новый монстр = новый .tres в data/monsters/.
## Статы указаны для 1-й волны, дальше их масштабирует WaveManager.

@export var id := ""
@export var display_name := ""

@export_group("Visual")
## Спрайт монстра. Рисуется смотрящим ВПРАВО — в игре отражается автоматически.
@export var sprite: Texture2D
@export var sprite_height := 1.2
## Покадровые анимации (idle, walk, attack, hurt, death). Пусто — статичный sprite.
@export var sprite_frames: SpriteFrames

@export_group("Stats")
@export var base_hp := 30.0
@export var base_damage := 5.0
@export var attack_interval := 1.2
@export var attack_range := 1.3
@export var move_speed := 2.5

@export_group("Rewards")
@export var xp_reward := 5
@export var gold_reward := 2
@export_range(0.0, 1.0) var drop_chance := 0.1

@export_group("Spawning")
## С какой волны монстр начинает появляться.
@export var min_wave := 1
## Относительная частота появления среди обычных монстров.
@export var spawn_weight := 1.0
## Босс появляется только на волнах-боссах (каждая 10-я).
@export var is_boss := false
