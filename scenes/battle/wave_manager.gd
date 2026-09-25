class_name WaveManager
extends Node
## Формирует волны: монстры биома этой волны (Database.get_biome_for_wave), босс биома каждые BOSS_EVERY волн.
## Роли смешиваются с ограничениями (шаман — один, громил немного), иногда монстр выходит элитой.
## Сам монстров не создаёт — просит об этом сигналом monster_spawn_requested (это делает Battle).

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal monster_spawn_requested(data: MonsterData, wave: int, elite_id: String)

const BOSS_EVERY := 10
const BASE_MONSTER_COUNT := 3
const MAX_MONSTER_COUNT := 10
## +1 монстр каждые N волн.
const WAVES_PER_EXTRA_MONSTER := 3
## Сколько монстров роли может быть в волне (в большой волне — больше).
const ROLE_LIMITS := {MonsterData.Role.SHAMAN: 1, MonsterData.Role.BRUTE: 2}
const BIG_WAVE := 8
## Шанс элиты на монстра: растёт с волной, но не выше ELITE_MAX_CHANCE; элит в волне — не больше 1 (2 с 20-й волны).
const ELITE_BASE_CHANCE := 0.04
const ELITE_CHANCE_PER_WAVE := 0.004
const ELITE_MAX_CHANCE := 0.2

var current_wave := 0
## Очередь появления: [{data: MonsterData, elite: String}].
var _queue: Array[Dictionary] = []
var _alive := 0
var _active := false

@onready var spawn_timer: Timer = $SpawnTimer


func _ready() -> void:
	spawn_timer.timeout.connect(_spawn_next)


func start_wave(wave: int) -> void:
	current_wave = wave
	_queue = []
	for entry in assign_elites(build_wave(wave), wave):
		_queue.append(entry)
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


## Состав волны: монстры биома с учётом лимитов ролей, на волне босса — ещё и босс биома.
func build_wave(wave: int) -> Array[MonsterData]:
	var result: Array[MonsterData] = []
	var pool := Database.get_monsters_for_wave(wave, false)
	if not pool.is_empty():
		var count := mini(BASE_MONSTER_COUNT + int(wave / float(WAVES_PER_EXTRA_MONSTER)), MAX_MONSTER_COUNT)
		var role_counts := {}
		for i in count:
			var allowed := pool.filter(func(monster: MonsterData) -> bool:
				return int(role_counts.get(monster.role, 0)) < _role_limit(monster.role, count))
			var picked := _pick_weighted(allowed if not allowed.is_empty() else pool)
			role_counts[picked.role] = int(role_counts.get(picked.role, 0)) + 1
			result.append(picked)
		# Бойцы впереди, стрелки и шаманы — в конце очереди появления (выходят позже, встают сзади).
		result.sort_custom(func(a: MonsterData, b: MonsterData) -> bool: return int(a.is_ranged()) < int(b.is_ranged()))
	if is_boss_wave(wave):
		var bosses := Database.get_monsters_for_wave(wave, true)
		if not bosses.is_empty():
			result.append(bosses.pick_random())
	return result


## Какие монстры волны выйдут элитой: [{data, elite}] (elite — id модификатора или "").
func assign_elites(monsters: Array[MonsterData], wave: int) -> Array[Dictionary]:
	var chance := minf(ELITE_MAX_CHANCE, ELITE_BASE_CHANCE + wave * ELITE_CHANCE_PER_WAVE)
	var max_elites := 2 if wave >= 20 else 1
	var elites := 0
	var result: Array[Dictionary] = []
	for monster in monsters:
		var elite := ""
		if not monster.is_boss and elites < max_elites and randf() < chance:
			elite = Monster.ELITE_MODIFIERS.keys().pick_random()
			elites += 1
		result.append({"data": monster, "elite": elite})
	return result


## Battle вызывает для каждого созданного монстра, чтобы волна знала, когда она зачищена.
func register_monster(monster: Monster) -> void:
	_alive += 1
	monster.died.connect(_on_monster_died)


func _role_limit(role: int, count: int) -> int:
	if not ROLE_LIMITS.has(role):
		return 999
	return int(ROLE_LIMITS[role]) + (1 if count >= BIG_WAVE else 0)


func _spawn_next() -> void:
	if not _active:
		return
	if _queue.is_empty():
		spawn_timer.stop()
		return
	var entry: Dictionary = _queue.pop_front()
	monster_spawn_requested.emit(entry.data, current_wave, entry.elite)


func _on_monster_died(_actor: Actor) -> void:
	_alive -= 1
	if _active and _alive <= 0 and _queue.is_empty():
		_active = false
		wave_cleared.emit(current_wave)


func _pick_weighted(pool: Array) -> MonsterData:
	var total := 0.0
	for monster: MonsterData in pool:
		total += monster.spawn_weight
	var roll := randf() * total
	for monster: MonsterData in pool:
		roll -= monster.spawn_weight
		if roll <= 0.0:
			return monster
	return pool.back()
