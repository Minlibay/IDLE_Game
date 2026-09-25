class_name WaveManager
extends Node
## Формирует волны: сколько и каких монстров, босс каждые BOSS_EVERY волн.
## Сам монстров не создаёт — просит об этом сигналом monster_spawn_requested (это делает Battle).

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal monster_spawn_requested(data: MonsterData, wave: int)

const BOSS_EVERY := 10
const BASE_MONSTER_COUNT := 3
const MAX_MONSTER_COUNT := 10
## +1 монстр каждые N волн.
const WAVES_PER_EXTRA_MONSTER := 3

var current_wave := 0
var _queue: Array[MonsterData] = []
var _alive := 0
var _active := false

@onready var spawn_timer: Timer = $SpawnTimer


func _ready() -> void:
	spawn_timer.timeout.connect(_spawn_next)


func start_wave(wave: int) -> void:
	current_wave = wave
	_queue = build_wave(wave)
	_alive = 0
	_active = true
	wave_started.emit(wave)
	_spawn_next()
	spawn_timer.start()


func stop() -> void:
	_active = false
	_queue.clear()
	_alive = 0
	spawn_timer.stop()


func is_boss_wave(wave: int) -> bool:
	return wave % BOSS_EVERY == 0


func build_wave(wave: int) -> Array[MonsterData]:
	var result: Array[MonsterData] = []
	var pool := Database.get_monsters_for_wave(wave, false)
	if not pool.is_empty():
		var count := mini(BASE_MONSTER_COUNT + int(wave / float(WAVES_PER_EXTRA_MONSTER)), MAX_MONSTER_COUNT)
		for i in count:
			result.append(_pick_weighted(pool))
	if is_boss_wave(wave):
		var bosses := Database.get_monsters_for_wave(wave, true)
		if not bosses.is_empty():
			result.append(bosses.pick_random())
	return result


## Battle вызывает для каждого созданного монстра, чтобы волна знала, когда она зачищена.
func register_monster(monster: Monster) -> void:
	_alive += 1
	monster.died.connect(_on_monster_died)


func _spawn_next() -> void:
	if not _active:
		return
	if _queue.is_empty():
		spawn_timer.stop()
		return
	monster_spawn_requested.emit(_queue.pop_front(), current_wave)


func _on_monster_died(_actor: Actor) -> void:
	_alive -= 1
	if _active and _alive <= 0 and _queue.is_empty():
		_active = false
		wave_cleared.emit(current_wave)


func _pick_weighted(pool: Array[MonsterData]) -> MonsterData:
	var total := 0.0
	for monster in pool:
		total += monster.spawn_weight
	var roll := randf() * total
	for monster in pool:
		roll -= monster.spawn_weight
		if roll <= 0.0:
			return monster
	return pool.back()
