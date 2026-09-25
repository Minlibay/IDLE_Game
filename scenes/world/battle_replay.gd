class_name BattleReplay
extends PanelContainer
## Повтор боя из отчёта сервера: две толпы бегут навстречу, сходятся, солдаты падают.
## Исход и потери уже посчитал сервер — здесь только показ по данным отчёта
## (армии, потери, сила, герои, добыча). Повтор одинаков при каждом просмотре: зерно — id отчёта.
## Большая армия показывается сокращённо: одна фигурка = несколько солдат.

signal closed

enum Phase { IDLE, CHARGE, FIGHT, DONE }

const MAX_FIGURES_PER_SIDE := 36
const FIGURE_HEIGHT := 28.0
const HERO_HEIGHT := 44.0
## Фаза сближения и фаза схватки, секунд (при скорости ×1).
const CHARGE_TIME := 1.3
const FIGHT_TIME := 4.5
## Как часто кто-то бьёт или стреляет.
const ACTION_INTERVAL := 0.12
const FORMATION_ROWS := 6
const FORMATION_SPACING := 15.0
const RANGED_UNITS := ["archer"]
const HERO_TEXTURE := preload("res://assets/sprites/heroes/warrior.png")
const ARROW_TEXTURE := preload("res://assets/sprites/fx/arrow.png")
const SPARK_TEXTURE := preload("res://assets/sprites/fx/ring.png")
const COLOR_MINE := Color(0.55, 0.8, 1.0)
const COLOR_ENEMY := Color(1.0, 0.6, 0.55)
const COLOR_NEUTRAL := Color(0.85, 0.85, 0.7)
const COLOR_WIN := Color(0.45, 0.9, 0.45)
const COLOR_LOSS := Color(1.0, 0.45, 0.4)
const SPEEDS := [1.0, 2.0, 4.0]

## Стороны: "attacker"/"defender" -> {figures: Array[BattleFigure], deaths: Array[BattleFigure],
## killed: int, weight: float (сила всех фигурок), facing}.
var _sides: Dictionary = {}
var _data: Dictionary = {}
var _phase := Phase.IDLE
var _time := 0.0
var _action_timer := 0.0
var _speed_index := 0
var _rng := RandomNumberGenerator.new()

@onready var title_label: Label = %ReplayTitle
@onready var speed_button: Button = %SpeedButton
@onready var skip_button: Button = %SkipButton
@onready var close_button: Button = %ReplayCloseButton
@onready var attacker_label: Label = %AttackerLabel
@onready var defender_label: Label = %DefenderLabel
@onready var attacker_bar: ProgressBar = %AttackerBar
@onready var defender_bar: ProgressBar = %DefenderBar
@onready var field: Control = %Field
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	speed_button.pressed.connect(_on_speed_pressed)
	skip_button.pressed.connect(skip)
	close_button.pressed.connect(close)
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Есть ли в отчёте, что показывать (бой, а не захват пустой зоны).
static func can_replay(report: Dictionary) -> bool:
	var data: Dictionary = report.get("data", {})
	return data.has("attacker") and data.has("defender")


## Запускает повтор боя из отчёта ({id, createdAt, data}).
func play(report: Dictionary) -> void:
	if not can_replay(report):
		return
	_clear()
	_data = report.data
	_rng.seed = int(report.get("id", 0)) * 7919 + 17
	show()
	# Размер поля известен только после раскладки.
	await get_tree().process_frame
	if not visible:
		return
	title_label.text = str(_data.get("text", "Бой"))
	var attacker: Dictionary = _data.attacker
	var defender: Dictionary = _data.defender
	_build_side("attacker", attacker, 1, _side_color(attacker))
	_build_side("defender", defender, -1, _side_color(defender))
	attacker_label.text = "%s · сила %d" % [attacker.name, int(attacker.power)]
	defender_label.text = "сила %d · %s" % [int(defender.power), defender.name]
	result_label.text = ""
	skip_button.disabled = false
	_phase = Phase.CHARGE
	_time = 0.0
	_charge()
	_update_bars()


func close() -> void:
	if not visible:
		return
	_clear()
	hide()
	closed.emit()


## Сразу к концу боя.
func skip() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	for key: String in _sides:
		var side: Dictionary = _sides[key]
		for figure: BattleFigure in side.figures:
			figure.position = figure.get_meta("target")
		while side.killed < (side.deaths as Array).size():
			(side.deaths[side.killed] as BattleFigure).die(true)
			side.killed += 1
	_finish()


## Сколько фигурок погибло / всего — для проверки в тестах.
func get_side_stats(key: String) -> Dictionary:
	var side: Dictionary = _sides.get(key, {})
	var figures: Array = side.get("figures", [])
	var dead := figures.filter(func(figure: BattleFigure) -> bool: return not figure.alive).size()
	return {"figures": figures.size(), "dead": dead, "planned_deaths": (side.get("deaths", []) as Array).size()}


func _process(delta: float) -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	delta *= _speed()
	_time += delta
	if _phase == Phase.CHARGE:
		if _time >= CHARGE_TIME:
			_phase = Phase.FIGHT
			_time = 0.0
		return
	# Схватка: потери распределены по времени, в середине — плотнее.
	var progress := clampf(_time / FIGHT_TIME, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, progress)
	for key: String in _sides:
		var side: Dictionary = _sides[key]
		var deaths: Array = side.deaths
		var should_be_dead := floori(deaths.size() * eased)
		while side.killed < should_be_dead:
			var victim: BattleFigure = deaths[side.killed]
			victim.die()
			_spark(victim.position + Vector2(0, -FIGURE_HEIGHT * 0.5))
			side.killed += 1
	_action_timer -= delta
	while _action_timer <= 0.0:
		_action_timer += ACTION_INTERVAL
		_random_action("attacker", "defender")
		_random_action("defender", "attacker")
	_update_bars()
	if progress >= 1.0:
		_finish()


# --- Построение ---------------------------------------------------------------------

func _build_side(key: String, side: Dictionary, facing: int, tint: Color) -> void:
	var army: Dictionary = side.get("army", {})
	var lost: Dictionary = side.get("lost", {})
	var total := 0
	for unit_id: String in army:
		total += int(army[unit_id])
	var figure_total := mini(MAX_FIGURES_PER_SIDE, total)
	var figures: Array[BattleFigure] = []
	var deaths: Array[BattleFigure] = []
	var melee: Array[BattleFigure] = []
	var ranged: Array[BattleFigure] = []
	var weight := 0.0
	for unit in Database.units:
		var count := int(army.get(unit.id, 0))
		if count <= 0:
			continue
		var n := maxi(1, roundi(float(count) / total * figure_total))
		var lost_count := mini(count, int(lost.get(unit.id, 0)))
		var dying := n if lost_count >= count else roundi(float(lost_count) / count * n)
		for i in n:
			var height := FIGURE_HEIGHT * (1.2 if unit.housing >= 3 else 1.0)
			var figure := _spawn(unit.battle_sprite, height, facing, tint, unit.id)
			figure.unit_id = unit.id
			figure.ranged = unit.id in RANGED_UNITS
			figure.set_meta("weight", unit.attack + unit.defense)
			weight += unit.attack + unit.defense
			figures.append(figure)
			(ranged if figure.ranged else melee).append(figure)
			if i < dying:
				deaths.append(figure)
	# Строй: ближний бой впереди, стрелки сзади.
	var rank := 0
	for figure in melee + ranged:
		_place_in_formation(figure, rank, facing)
		rank += 1
	# Герой (если был в бою) стоит за строем и не погибает — сервер только отправляет его домой.
	if int(side.get("heroLevel", 0)) > 0:
		var hero := _spawn(HERO_TEXTURE, HERO_HEIGHT, facing, Color.WHITE)
		hero.is_hero = true
		var x := 22.0 if facing > 0 else field.size.x - 22.0
		hero.position = Vector2(x, field.size.y * 0.62)
		hero.set_meta("target", hero.position + Vector2(18.0 * facing, 0))
		figures.append(hero)
	_shuffle_with_rng(deaths)
	_sides[key] = {"figures": figures, "deaths": deaths, "killed": 0, "weight": maxf(1.0, weight), "facing": facing}


func _spawn(texture: Texture2D, height: float, facing: int, tint: Color, unit_style := "") -> BattleFigure:
	var figure := BattleFigure.new()
	figure.setup(texture, height, facing, tint, _rng.randf() * TAU, unit_style)
	field.add_child(figure)
	return figure


## Место в строю: колонки от края поля к центру, ряды по высоте.
func _place_in_formation(figure: BattleFigure, rank: int, facing: int) -> void:
	var column := rank / FORMATION_ROWS
	var row := rank % FORMATION_ROWS
	var top := field.size.y * 0.3
	var row_step := (field.size.y * 0.66) / FORMATION_ROWS
	# Первые колонки — ближе к центру (впереди).
	var front := field.size.x * 0.5 - 90.0 * facing
	var x := front - column * FORMATION_SPACING * facing + _rng.randf_range(-3.0, 3.0)
	var start_x := (x - field.size.x * 0.28 * facing)
	var y := top + (row + 0.5) * row_step + _rng.randf_range(-4.0, 4.0) + (column % 2) * row_step * 0.4
	figure.position = Vector2(start_x, y)
	# Пехота сходится в центре, стрелки подходят на дистанцию выстрела.
	var target_x := x
	if not figure.ranged:
		target_x = field.size.x * 0.5 - facing * _rng.randf_range(6.0, 40.0 + column * 6.0)
	figure.set_meta("target", Vector2(target_x, y + _rng.randf_range(-6.0, 6.0)))


func _charge() -> void:
	for key: String in _sides:
		for figure: BattleFigure in _sides[key].figures:
			var delay := _rng.randf_range(0.0, 0.25)
			figure.run_to(figure.get_meta("target"), (CHARGE_TIME - delay) / _speed(), delay / _speed())


# --- Схватка ------------------------------------------------------------------------

func _random_action(key: String, enemy_key: String) -> void:
	var fighters: Array = (_sides[key].figures as Array).filter(func(figure: BattleFigure) -> bool: return figure.alive)
	if fighters.is_empty():
		return
	var figure: BattleFigure = fighters[_rng.randi() % fighters.size()]
	if figure.ranged:
		figure.recoil()
		var targets: Array = (_sides[enemy_key].figures as Array).filter(func(other: BattleFigure) -> bool: return other.alive)
		if not targets.is_empty():
			_shoot(figure, targets[_rng.randi() % targets.size()])
	else:
		figure.strike()


func _shoot(from: BattleFigure, to: BattleFigure) -> void:
	var arrow := Sprite2D.new()
	arrow.texture = ARROW_TEXTURE
	arrow.flip_h = from.facing < 0
	var start := from.position + Vector2(8.0 * from.facing, -FIGURE_HEIGHT * 0.6)
	var finish := to.position + Vector2(0, -FIGURE_HEIGHT * 0.5)
	arrow.position = start
	arrow.z_index = 5
	field.add_child(arrow)
	var duration := 0.35 / _speed()
	var tween := arrow.create_tween()
	tween.tween_method(func(t: float) -> void:
		# Дуга: стрела летит выше прямой.
		arrow.position = start.lerp(finish, t) + Vector2(0, -sin(t * PI) * 18.0), 0.0, 1.0, duration)
	tween.tween_callback(arrow.queue_free)


func _spark(point: Vector2) -> void:
	var spark := Sprite2D.new()
	spark.texture = SPARK_TEXTURE
	spark.position = point
	spark.scale = Vector2.ONE * 0.1
	spark.modulate = Color(1.0, 0.85, 0.5, 0.9)
	spark.z_index = 6
	field.add_child(spark)
	var tween := spark.create_tween().set_parallel()
	tween.tween_property(spark, "scale", Vector2.ONE * 0.35, 0.25)
	tween.tween_property(spark, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(spark.queue_free)


func _finish() -> void:
	_phase = Phase.DONE
	skip_button.disabled = true
	_update_bars()
	var attacker_wins := _attacker_won()
	var winner: Dictionary = _sides.get("attacker" if attacker_wins else "defender", {})
	for figure: BattleFigure in winner.get("figures", []):
		figure.cheer()
	var won := bool(_data.get("won", false))
	var lines := PackedStringArray()
	lines.append("Победа!" if won else "Поражение")
	lines.append("Потери: %s — %s · %s — %s" % [
		_data.attacker.name, _army_text(_data.attacker.get("lost", {})),
		_data.defender.name, _army_text(_data.defender.get("lost", {}))])
	var loot: Dictionary = _data.get("loot", {})
	if not loot.is_empty():
		var parts := PackedStringArray()
		for resource_id: String in loot:
			parts.append("%d %s" % [int(loot[resource_id]), KingdomState.resource_name(resource_id)])
		lines.append("Добыча: " + ", ".join(parts))
	result_label.text = "\n".join(lines)
	result_label.modulate = COLOR_WIN if won else COLOR_LOSS


# --- Вспомогательное ----------------------------------------------------------------

## Победил ли атакующий. Отчёт написан с точки зрения игрока: won — победил ли он сам.
func _attacker_won() -> bool:
	var mine_is_attacker := str(_data.attacker.name) == str(WorldService.me.get("name", ""))
	var won := bool(_data.get("won", false))
	return won if mine_is_attacker else not won


func _side_color(side: Dictionary) -> Color:
	var side_name := str(side.get("name", ""))
	if side_name == str(WorldService.me.get("name", "")):
		return COLOR_MINE
	return COLOR_NEUTRAL if side_name == "Нейтралы" else COLOR_ENEMY


func _update_bars() -> void:
	attacker_bar.value = _alive_share("attacker")
	defender_bar.value = _alive_share("defender")


## Доля оставшейся силы стороны (по живым фигуркам).
func _alive_share(key: String) -> float:
	var side: Dictionary = _sides.get(key, {})
	if side.is_empty():
		return 0.0
	var alive := 0.0
	for figure: BattleFigure in side.figures:
		if figure.alive and not figure.is_hero:
			alive += float(figure.get_meta("weight", 0.0))
	return alive / float(side.weight) * 100.0


func _shuffle_with_rng(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var temp: Variant = list[i]
		list[i] = list[j]
		list[j] = temp


func _army_text(army: Dictionary) -> String:
	var parts := PackedStringArray()
	for unit_id: String in army:
		var unit := Database.get_unit(unit_id)
		parts.append("%d %s" % [int(army[unit_id]), unit.display_name if unit else unit_id])
	return ", ".join(parts) if not parts.is_empty() else "нет"


func _speed() -> float:
	return SPEEDS[_speed_index]


func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	speed_button.text = "×%d" % int(_speed())


func _clear() -> void:
	_phase = Phase.IDLE
	_sides.clear()
	for child in field.get_children():
		if child is BattleFigure or child is Sprite2D:
			field.remove_child(child)
			child.queue_free()
