extends Node
## Связь с сервером (server/): вход, состояние мира, игрока и его замка, действия.
## Все правила карты (походы, бои, захваты, набеги) и экономика замка — на сервере;
## здесь только запросы и кэш для интерфейса. Состояние замка уходит в GameState.kingdom.apply_server(),
## бонусы захваченных зон — в GameState.set_territory_bonuses().

signal me_updated
## На зону или замок игрока идёт чужая армия (новая угроза).
signal incoming_attack(attack: Dictionary)
## Пришли новые отчёты (бои, набеги).
signal new_reports(reports: Array)
signal world_updated
signal login_changed(logged_in: bool)
signal request_failed(message: String)
## Внутренний: запрос карты завершён (запросы карты выполняются по очереди).
signal _world_request_done

## Боевой сервер мировой карты — клиент подключается к нему сам.
const DEFAULT_URL := "http://46.8.124.62:8787"
## Локальный сервер для разработки и автотестов (npm start в папке server/).
const LOCAL_URL := "http://127.0.0.1:8787"
## Пока открыта карта — обновляем часто.
const POLL_INTERVAL := 4.0
## Когда карта закрыта — реже (замок, бонусы территорий, предупреждение о набеге).
const BACKGROUND_INTERVAL := 15.0
## Съеденное героем отправляется на сервер пачкой раз в столько секунд.
const CONSUME_FLUSH_INTERVAL := 10.0
## Не чаще этого проверяем, закончилась ли стройка/обучение (секунд).
const EVENT_REFRESH_INTERVAL := 2.0
## Реликвии армии часто перекладывают — отправляем бонусы на сервер с небольшой задержкой.
const GEAR_REPORT_DELAY := 1.0
const REQUEST_TIMEOUT := 10.0

var server_url := DEFAULT_URL
var token := ""
## Данные игрока с сервера (см. Game.playerView на сервере).
var me: Dictionary = {}
## Зоны по id (Dictionary или null, пока не загружены).
var zones: Array = []
## Игроки на карте: id -> Dictionary.
var players: Dictionary = {}
var cols := 0
var rows := 0
var tiers := 10
var world_version := 0
var connected := false
## В автотесте сеть выключена, если не запрошен --world-test.
var enabled := true

var _polling := false
var _poll_timer: Timer
var _world_request_active := false
## Серверное время минус локальное (мс) — для таймеров походов.
var _server_offset_ms := 0.0
var _config_path := "user://world_server.cfg"
var _auto_connecting := false
var _consume_timer := 0.0
var _event_refresh_timer := 0.0
var _gear_report_timer := -1.0
## Уже показанные угрозы и отчёты (чтобы не сообщать дважды).
var _known_attacks: Dictionary = {}
var _last_report_id := -1
## Как на сервере (config.ts maxNameLength).
const MAX_NAME_LENGTH := 20


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if GameState.autotest:
		enabled = args.has("--world-test")
		_config_path = "user://world_server_autotest.cfg"
		server_url = LOCAL_URL
	_load_config()
	_poll_timer = Timer.new()
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	_update_poll_timer()
	GameState.leveled_up.connect(func(_level: int) -> void: report_hero_level())
	GameState.army_gear_changed.connect(func() -> void: _gear_report_timer = GEAR_REPORT_DELAY)
	set_process(enabled)
	if enabled and is_logged_in():
		refresh_me()
	elif enabled and not GameState.autotest:
		auto_connect()


func _process(delta: float) -> void:
	if not is_logged_in():
		return
	_consume_timer += delta
	if _consume_timer >= CONSUME_FLUSH_INTERVAL:
		_consume_timer = 0.0
		_flush_consumption()
	if _gear_report_timer >= 0.0:
		_gear_report_timer -= delta
		if _gear_report_timer < 0.0:
			report_hero_level()
	_event_refresh_timer -= delta
	if _event_refresh_timer <= 0.0 and GameState.kingdom.needs_refresh():
		_event_refresh_timer = EVENT_REFRESH_INTERVAL
		refresh_me()


# --- Состояние --------------------------------------------------------------------

func is_logged_in() -> bool:
	return token != ""


func set_polling(value: bool) -> void:
	_polling = value
	_update_poll_timer()


func get_zone(zone_id: int) -> Dictionary:
	if zone_id < 0 or zone_id >= zones.size() or zones[zone_id] == null:
		return {}
	return zones[zone_id]


func get_player(player_id: Variant) -> Dictionary:
	if player_id == null:
		return {}
	return players.get(int(player_id), {})


func my_id() -> int:
	return int(me.get("id", -1))


func hero_zone() -> int:
	return int(me.get("heroZone", -1))


func castle_zone() -> int:
	return int(me.get("castleZone", -1))


func is_marching() -> bool:
	return me.get("march") != null and not (me.get("march", {}) as Dictionary).is_empty()


func is_hero_at_castle() -> bool:
	return not me.is_empty() and not is_marching() and hero_zone() == castle_zone()


## Секунд до конца похода (0 — не в походе).
func march_time_left() -> float:
	if not is_marching():
		return 0.0
	var arrives: float = me.march.arrivesAt
	return maxf(0.0, (arrives - server_now_ms()) / 1000.0)


func march_progress() -> float:
	if not is_marching():
		return 0.0
	var started: float = me.march.startedAt
	var arrives: float = me.march.arrivesAt
	return clampf((server_now_ms() - started) / maxf(1.0, arrives - started), 0.0, 1.0)


func get_my_army() -> Dictionary:
	return me.get("army", {})


## Чужие армии, идущие на зоны игрока: [{attacker, attackerId, fromZone, toZone, castle, arrivesAt, units}].
func get_incoming() -> Array:
	return me.get("incoming", [])


## Секунд до момента server_ms (мс серверного времени).
func time_until(server_ms: float) -> float:
	return maxf(0.0, (server_ms - server_now_ms()) / 1000.0)


## До какого момента (мс серверного времени) замок игрока нельзя атаковать; 0 — можно.
func my_protection_until() -> float:
	var until := maxf(float(me.get("protectionUntil", 0.0)), float(me.get("shieldUntil", 0.0)))
	return until if until > server_now_ms() else 0.0


## Защищён ли замок игрока player_id (данные карты).
func is_castle_protected(player_id: Variant) -> bool:
	return float(get_player(player_id).get("protectedUntil", 0.0)) > server_now_ms()


## Сколько золота героя сервер сейчас примет в казну.
func deposit_available() -> int:
	return int(me.get("depositAvailable", 0))


func get_my_garrison(zone_id: int) -> Dictionary:
	for entry: Dictionary in me.get("garrisons", []):
		if int(entry.zoneId) == zone_id:
			return entry.army
	return {}


func are_adjacent(a: int, b: int) -> bool:
	return HexGrid.is_adjacent(a, b, cols, rows)


# --- Запросы ----------------------------------------------------------------------

func register(player_name: String, url: String) -> Dictionary:
	server_url = url.strip_edges().trim_suffix("/")
	token = ""
	var result := await _request(HTTPClient.METHOD_POST, "/api/auth/register", {"name": player_name})
	if result.ok:
		token = result.data.token
		_save_config()
		_apply_me(result.data.me)
		login_changed.emit(true)
		report_hero_level()
		await refresh_world(true)
	return result


## Автоподключение: регистрация под именем героя. Имя занято — одна попытка с цифрами.
## Не вышло — false (окно карты покажет форму входа).
func auto_connect() -> bool:
	if is_logged_in() or not GameState.has_character() or _auto_connecting:
		return is_logged_in()
	_auto_connecting = true
	var base_name := GameState.hero_name.strip_edges().left(MAX_NAME_LENGTH)
	if base_name == "":
		base_name = "Герой"
	var result := await register(base_name, server_url)
	if not result.ok and int(result.get("status", 0)) == 409:
		var suffix := str(randi_range(100, 999))
		result = await register(base_name.left(MAX_NAME_LENGTH - suffix.length()) + suffix, server_url)
	_auto_connecting = false
	return result.ok


func logout() -> void:
	token = ""
	me = {}
	_known_attacks.clear()
	_last_report_id = -1
	GameState.kingdom.mark_unsynced()
	_save_config()
	GameState.set_territory_bonuses({})
	login_changed.emit(false)


func refresh_me() -> Dictionary:
	var result := await _request(HTTPClient.METHOD_GET, "/api/me")
	if result.ok:
		_apply_me(result.data)
	return result


func refresh_world(full := false) -> void:
	while _world_request_active:
		await _world_request_done
	_world_request_active = true
	var since := 0 if full or zones.is_empty() else world_version
	var result := await _request(HTTPClient.METHOD_GET, "/api/world?since=%d" % since)
	_world_request_active = false
	_world_request_done.emit()
	if not result.ok:
		return
	var data: Dictionary = result.data
	cols = int(data.cols)
	rows = int(data.rows)
	tiers = int(data.tiers)
	if zones.size() != cols * rows:
		zones.resize(cols * rows)
	for zone: Dictionary in data.zones:
		zones[int(zone.id)] = zone
	players.clear()
	for player: Dictionary in data.players:
		players[int(player.id)] = player
	world_version = int(data.version)
	world_updated.emit()


func move(zone_id: int) -> Dictionary:
	return await _action("/api/move", {"zoneId": zone_id})


## Отправить солдат из армии замка на карту вместе с героем.
func deploy(units: Dictionary) -> Dictionary:
	return await _action("/api/army/deploy", {"units": units})


## Вернуть солдат с карты в армию замка.
func recall(units: Dictionary) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, "/api/army/recall", {"units": units})
	if result.ok:
		_apply_me(result.data.me)
	return result


func garrison(units: Dictionary) -> Dictionary:
	return await _action("/api/garrison", {"units": units})


func withdraw(units: Dictionary) -> Dictionary:
	return await _action("/api/garrison/withdraw", {"units": units})


# --- Замок (всё выполняет сервер) -------------------------------------------------

func kingdom_build(building_id: String) -> Dictionary:
	return await _action("/api/kingdom/build", {"building": building_id}, false)


func kingdom_recruit(unit_id: String, count: int) -> Dictionary:
	return await _action("/api/kingdom/recruit", {"unit": unit_id, "count": count}, false)


func kingdom_cancel(index: int) -> Dictionary:
	return await _action("/api/kingdom/cancel", {"index": index}, false)


## Внести золото героя в казну. Золото списывается сразу; то, что сервер не принял, возвращается.
func deposit_gold(amount: int) -> Dictionary:
	amount = mini(amount, GameState.gold)
	if amount <= 0 or not GameState.try_spend_gold(amount):
		return {"ok": false, "error": "Нет золота"}
	var result := await _request(HTTPClient.METHOD_POST, "/api/kingdom/deposit", {"gold": amount})
	var accepted := 0
	if result.ok:
		accepted = int(result.data.accepted)
		_apply_me(result.data.me)
	if amount > accepted:
		GameState.add_gold(amount - accepted)
	result.accepted = accepted
	return result


## Уровень героя и бонусы реликвий армии (сервер урежет их до своих потолков).
func report_hero_level() -> void:
	if enabled and is_logged_in():
		_action("/api/hero", {"level": GameState.level, "armyGear": GameState.get_army_gear_bonuses()}, false)


# --- Внутреннее -------------------------------------------------------------------

func _action(path: String, body: Dictionary, refresh_map := true) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, path, body)
	if result.ok:
		_apply_me(result.data)
		if refresh_map:
			refresh_world()
	return result


func _apply_me(data: Dictionary) -> void:
	me = data
	_server_offset_ms = float(data.get("serverTime", _local_now_ms())) - _local_now_ms()
	GameState.set_territory_bonuses(data.get("bonuses", {}))
	var kingdom: Variant = data.get("kingdom")
	if kingdom is Dictionary:
		GameState.kingdom.apply_server(kingdom)
	_detect_news()
	me_updated.emit()


## Новые угрозы и отчёты — для уведомлений в интерфейсе.
func _detect_news() -> void:
	var current := {}
	for attack: Dictionary in get_incoming():
		var key := "%d:%d" % [int(attack.attackerId), int(attack.arrivesAt)]
		current[key] = true
		if not _known_attacks.has(key):
			incoming_attack.emit(attack)
	_known_attacks = current
	var reports: Array = me.get("reports", [])
	if reports.is_empty():
		return
	var fresh := []
	for report: Dictionary in reports:
		if int(report.id) > _last_report_id:
			fresh.append(report)
	var first_load := _last_report_id < 0
	_last_report_id = maxi(_last_report_id, int(reports[0].id))
	if not first_load and not fresh.is_empty():
		new_reports.emit(fresh)


func _flush_consumption() -> void:
	var pending := GameState.kingdom.take_pending_consumption()
	if pending.is_empty():
		return
	var result := await _request(HTTPClient.METHOD_POST, "/api/kingdom/consume", {"resources": pending})
	if result.ok:
		_apply_me(result.data.me)


func _request(method: int, path: String, body: Variant = null) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "Сеть отключена", "status": 0}
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	# Ответ на запрос, отправленный до повторного входа, относится к другому игроку — его отбрасываем.
	var request_token := token
	if http.request(server_url + path, headers, method, payload) != OK:
		http.queue_free()
		return _fail("Не удалось отправить запрос", 0)
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var code: int = response[1]
	var bytes: PackedByteArray = response[3]
	if token != request_token and not path.begins_with("/api/auth/"):
		return {"ok": false, "error": "Устаревший ответ", "status": 0, "stale": true}
	if result != HTTPRequest.RESULT_SUCCESS:
		connected = false
		return _fail("Нет связи с сервером (%s)" % server_url, 0)
	connected = true
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if code == 401 and token != "":
		logout()
	if code != 200:
		var message := "Ошибка сервера (%d)" % code
		if data is Dictionary and data.has("error"):
			message = str(data.error)
		return _fail(message, code)
	return {"ok": true, "data": data}


func _fail(message: String, code: int) -> Dictionary:
	request_failed.emit(message)
	return {"ok": false, "error": message, "status": code}


func _on_poll() -> void:
	if not enabled or not is_logged_in():
		return
	await refresh_me()
	if _polling:
		refresh_world()


func _update_poll_timer() -> void:
	if _poll_timer == null:
		return
	_poll_timer.wait_time = POLL_INTERVAL if _polling else BACKGROUND_INTERVAL
	_poll_timer.start()


func _local_now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0


func server_now_ms() -> float:
	return _local_now_ms() + _server_offset_ms


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(_config_path) == OK:
		server_url = str(config.get_value("server", "url", server_url))
		token = str(config.get_value("server", "token", ""))
	# Переезд с локального сервера разработки на боевой: старый токен там недействителен.
	if not GameState.autotest and _is_local(server_url):
		server_url = DEFAULT_URL
		token = ""
		_save_config()


func _is_local(url: String) -> bool:
	return url.contains("127.0.0.1") or url.contains("localhost")


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value("server", "url", server_url)
	config.set_value("server", "token", token)
	config.save(_config_path)
