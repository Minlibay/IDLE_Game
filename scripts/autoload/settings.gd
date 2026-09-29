extends Node
## Настройки игрока: язык, частота кадров и звук. Хранятся в user://settings.cfg, не в сохранении героя:
## они общие для всех героев на этом компьютере.
##
## Тексты игры пишутся по-русски и переводятся через TranslationServer: ключ перевода — русская строка,
## переводы лежат в locale/<язык>.po (обновление ключей: python tools/i18n_extract.py).

signal language_changed
signal sound_changed

const PATH := "user://settings.cfg"
## Язык → его название (на самом этом языке, чтобы его нашёл тот, кто другого не знает).
## Порядок — как в окне настроек. Переводы: locale/<код>.po.
const LANGUAGES := {
	"ru": "Русский", "en": "English", "de": "Deutsch", "fr": "Français", "es": "Español",
	"pt_BR": "Português (BR)", "it": "Italiano", "pl": "Polski", "tr": "Türkçe", "uk": "Українська",
	"zh_CN": "简体中文", "ja": "日本語", "ko": "한국어",
}
const DEFAULT_LANGUAGE := "en"
## Язык системы → язык игры, если он не совпадает по коду (остальные — как есть, если поддерживаются).
const SYSTEM_LANGUAGE_MAP := {"be": "ru", "kk": "ru", "zh": "zh_CN", "pt": "pt_BR"}
## Частота кадров: для полоски на рабочем столе 30 хватает (спрайты анимированы не быстрее 16 кадров/с),
## а нагрузка на видеокарту вдвое меньше. Автотесты идут на 60.
const FRAME_LIMITS := [30, 60]
const DEFAULT_FRAME_LIMIT := 30
## Громкость каналов звука (0..1). Музыка и бой по умолчанию тише: игра висит на экране часами.
const SOUND_CHANNELS := ["master", "music", "combat", "ui", "notify"]
const DEFAULT_VOLUMES := {"master": 0.8, "music": 0.35, "combat": 0.5, "ui": 0.6, "notify": 0.8}
## Когда слышны звуки боя: всегда, только пока игрок смотрит на игру (курсор над полосой боя, открыто окно) или никогда.
enum CombatSound { ALWAYS, ON_HOVER, OFF }

var language := DEFAULT_LANGUAGE
var frame_limit := DEFAULT_FRAME_LIMIT
var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var muted := false
var combat_sound := CombatSound.ON_HOVER
## Звучат ли уведомления, пока игра свёрнута в трей (бой и музыка там молчат всегда).
var sound_in_tray := true
var _save_pending := false


func _ready() -> void:
	language = _initial_language()
	TranslationServer.set_locale(language)
	frame_limit = 60 if _is_test_run() else int(_load_value("frame_limit", DEFAULT_FRAME_LIMIT))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="):
			frame_limit = int(arg.trim_prefix("--fps="))
	if not frame_limit in FRAME_LIMITS:
		frame_limit = DEFAULT_FRAME_LIMIT
	apply_frame_limit()
	_load_sound()


## Громкость канала (0..1): master, music, combat, ui, notify.
func get_volume(channel: String) -> float:
	return float(volumes.get(channel, DEFAULT_VOLUMES.get(channel, 1.0)))


func set_volume(channel: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if not channel in SOUND_CHANNELS or is_equal_approx(value, get_volume(channel)):
		return
	volumes[channel] = value
	_sound_changed()


func set_muted(value: bool) -> void:
	if value == muted:
		return
	muted = value
	_sound_changed()


func toggle_muted() -> void:
	set_muted(not muted)


func set_combat_sound(mode: CombatSound) -> void:
	if mode == combat_sound:
		return
	combat_sound = mode
	_sound_changed()


func set_sound_in_tray(value: bool) -> void:
	if value == sound_in_tray:
		return
	sound_in_tray = value
	_sound_changed()


## Ползунок громкости меняет значение много раз в секунду — файл сохраняем один раз, чуть позже.
func _sound_changed() -> void:
	sound_changed.emit()
	if _save_pending:
		return
	_save_pending = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		_save_pending = false
		_save())


## В автотестах звук выключен (чтобы не шуметь при прогонах), если не задан --sound.
func _load_sound() -> void:
	var config := ConfigFile.new()
	if not _is_test_run() and config.load(PATH) == OK:
		for channel: String in SOUND_CHANNELS:
			volumes[channel] = clampf(float(config.get_value("sound", channel, DEFAULT_VOLUMES[channel])), 0.0, 1.0)
		muted = bool(config.get_value("sound", "muted", false))
		combat_sound = clampi(int(config.get_value("sound", "combat", CombatSound.ON_HOVER)), 0, CombatSound.OFF) as CombatSound
		sound_in_tray = bool(config.get_value("sound", "in_tray", true))
	if _is_test_run():
		muted = not "--sound" in OS.get_cmdline_user_args()


func set_frame_limit(value: int) -> void:
	if value == frame_limit or not value in FRAME_LIMITS:
		return
	frame_limit = value
	_save()
	apply_frame_limit()


## Свёрнутая в трей игра задаёт свою частоту (DesktopWindow) — тогда здесь ничего не меняем.
func apply_frame_limit() -> void:
	if DesktopWindow.is_in_tray():
		return
	Engine.max_fps = frame_limit


func _load_value(key: String, default_value: Variant) -> Variant:
	var config := ConfigFile.new()
	return config.get_value("general", key, default_value) if config.load(PATH) == OK else default_value


func set_language(code: String) -> void:
	if code == language or not LANGUAGES.has(code):
		return
	language = code
	TranslationServer.set_locale(code)
	_save()
	Database.retranslate()
	language_changed.emit()


func _initial_language() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			return arg.trim_prefix("--lang=")
	if _is_test_run():
		return "ru"
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var saved := str(config.get_value("general", "language", ""))
		if LANGUAGES.has(saved):
			return saved
	var system := OS.get_locale_language()
	var mapped: String = SYSTEM_LANGUAGE_MAP.get(system, system)
	return mapped if LANGUAGES.has(mapped) else DEFAULT_LANGUAGE


func _save() -> void:
	if _is_test_run():
		return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("general", "language", language)
	config.set_value("general", "frame_limit", frame_limit)
	for channel: String in SOUND_CHANNELS:
		config.set_value("sound", channel, snappedf(get_volume(channel), 0.01))
	config.set_value("sound", "muted", muted)
	config.set_value("sound", "combat", combat_sound)
	config.set_value("sound", "in_tray", sound_in_tray)
	config.save(PATH)


## Автотесты всегда идут на русском (если не задан --lang=…) и настройки игрока не трогают.
func _is_test_run() -> bool:
	return "--autotest" in OS.get_cmdline_user_args()
