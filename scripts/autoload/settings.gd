extends Node
## Настройки игрока (пока — язык). Хранятся в user://settings.cfg, не в сохранении героя:
## язык общий для всех героев на этом компьютере.
##
## Тексты игры пишутся по-русски и переводятся через TranslationServer: ключ перевода — русская строка,
## переводы лежат в locale/<язык>.po (обновление ключей: python tools/i18n_extract.py).

signal language_changed

const PATH := "user://settings.cfg"
## Язык → его название (на самом этом языке, чтобы его нашёл тот, кто другого не знает).
const LANGUAGES := {"ru": "Русский", "en": "English"}
const DEFAULT_LANGUAGE := "en"
## Для этих языков системы по умолчанию выбирается русский.
const RUSSIAN_SPEAKING := ["ru", "uk", "be", "kk"]

var language := DEFAULT_LANGUAGE


func _ready() -> void:
	language = _initial_language()
	TranslationServer.set_locale(language)


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
	return "ru" if OS.get_locale_language() in RUSSIAN_SPEAKING else DEFAULT_LANGUAGE


func _save() -> void:
	if _is_test_run():
		return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("general", "language", language)
	config.save(PATH)


## Автотесты всегда идут на русском (если не задан --lang=…) и настройки игрока не трогают.
func _is_test_run() -> bool:
	return "--autotest" in OS.get_cmdline_user_args()
