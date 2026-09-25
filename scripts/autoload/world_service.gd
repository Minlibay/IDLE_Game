extends Node
## Связь с сервером мировой карты (server/): вход, состояние мира и игрока, действия.
## Все правила карты (походы, бои, захваты) — на сервере; здесь только запросы и кэш для интерфейса.
## Бонусы захваченных зон передаются в GameState.set_territory_bonuses().

signal me_updated
signal world_updated
signal login_changed(logged_in: bool)
signal request_failed(message: String)
## Внутренний: запрос карты завершён (запросы карты выполняются по очереди).
signal _world_request_done

const DEFAULT_URL := "http://127.0.0.1:8787"
## Пока открыта карта — обновляем часто.
const POLL_INTERVAL := 4.0
## Когда карта закрыта — изредка, чтобы бонусы территорий были актуальны.
const BACKGROUND_INTERVAL := 60.0
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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if GameState.autotest:
		enabled = args.has("--world-test")
		_config_path = "user://world_server_autotest.cfg"
	_load_config()
	_poll_timer = Timer.new()
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	_update_poll_timer()
	GameState.leveled_up.connect(func(_level: int) -> void: report_hero_level())
	if enabled and is_logged_in():
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
	return maxf(0.0, (arrives - _server_now_ms()) / 1000.0)


func march_progress() -> float:
	if not is_marching():
		return 0.0
	var started: float = me.march.startedAt
	var arrives: float = me.march.arrivesAt
	return clampf((_server_now_ms() - started) / maxf(1.0, arrives - started), 0.0, 1.0)


func get_my_army() -> Dictionary:
	return me.get("army", {})


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


func logout() -> void:
	token = ""
	me = {}
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


## Отправить армию из замка (клиент) на карту. Солдаты списываются из армии замка.
func deploy(units: Dictionary) -> Dictionary:
	var result := await _action("/api/army/deploy", {"units": units})
	if result.ok:
		GameState.kingdom.army.remove_units(units)
	return result


## Вернуть армию с карты в замок (клиент).
func recall(units: Dictionary) -> Dictionary:
	var result := await _request(HTTPClient.METHOD_POST, "/api/army/recall", {"units": units})
	if result.ok:
		GameState.kingdom.army.add_units(result.data.returned)
		_apply_me(result.data.me)
	return result


func garrison(units: Dictionary) -> Dictionary:
	return await _action("/api/garrison", {"units": units})


func withdraw(units: Dictionary) -> Dictionary:
	return await _action("/api/garrison/withdraw", {"units": units})


func report_hero_level() -> void:
	if enabled and is_logged_in():
		_action("/api/hero", {"level": GameState.level}, false)


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
	me_updated.emit()


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


func _server_now_ms() -> float:
	return _local_now_ms() + _server_offset_ms


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(_config_path) == OK:
		server_url = str(config.get_value("server", "url", DEFAULT_URL))
		token = str(config.get_value("server", "token", ""))


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value("server", "url", server_url)
	config.set_value("server", "token", token)
	config.save(_config_path)
