extends Node
## Звук игры: эффекты боя, интерфейса и уведомлений и музыка по биомам.
##
## Файлы: assets/audio/sfx/<id>.ogg (варианты — <id>_2, <id>_3…) и assets/audio/music/<трек>.ogg; подходят и .mp3/.wav.
## Нет файла — звук просто не играет, поэтому любой можно удалить или заменить своим (assets/audio/README.md).
## Временные звуки создаёт tools/generate_audio.py.
##
## Игра висит на экране часами, поэтому звук сдержанный:
## - звуки боя по умолчанию слышны, только пока игрок смотрит на игру (Settings.combat_sound);
## - уведомления (уровень, редкий дроп, нападение) звучат всегда, в трее — по настройке, бой и музыка там молчат;
## - одинаковые звуки не накладываются больше MAX_SAME раз и не повторяются чаще своего интервала.

enum Kind { COMBAT, UI, NOTIFY }

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTENSIONS := ["ogg", "mp3", "wav"]
const KIND_BUSES := {Kind.COMBAT: &"Combat", Kind.UI: &"UI", Kind.NOTIFY: &"Notify"}
const MUSIC_BUS := &"Music"
## Канал настроек (Settings.SOUND_CHANNELS) → шина.
const CHANNEL_BUSES := {"master": &"Master", "music": &"Music", "combat": &"Combat", "ui": &"UI", "notify": &"Notify"}
const VOICES := 16
const MAX_SAME := 3
const MAX_VARIANTS := 4
## Сколько секунд бой ещё слышен после того, как курсор ушёл с полосы боя.
const ATTENTION_GRACE := 3.0
## Звуки боя появляются и затихают плавно (доля громкости в секунду).
const COMBAT_FADE_SPEED := 2.0
const MUSIC_FADE_TIME := 2.0
const MUSIC_SILENT_DB := -40.0
## Насколько тише музыка, пока герой отдыхает.
const MUSIC_DUCK_DB := -10.0

## id → [вид, громкость (дБ), минимальный интервал между повторами (с), разброс высоты тона].
const SOUNDS := {
	# Интерфейс
	&"click": [Kind.UI, -12.0, 0.03, 0.06],
	&"tab": [Kind.UI, -12.0, 0.03, 0.04],
	&"panel_open": [Kind.UI, -14.0, 0.05, 0.03],
	&"panel_close": [Kind.UI, -15.0, 0.05, 0.03],
	&"equip": [Kind.UI, -8.0, 0.05, 0.05],
	&"sell": [Kind.UI, -8.0, 0.05, 0.03],
	&"upgrade_ok": [Kind.UI, -6.0, 0.1, 0.0],
	&"upgrade_fail": [Kind.UI, -6.0, 0.1, 0.0],
	&"merge": [Kind.UI, -6.0, 0.1, 0.0],
	&"talent": [Kind.UI, -8.0, 0.05, 0.03],
	&"keystone": [Kind.UI, -5.0, 0.2, 0.0],
	&"build": [Kind.UI, -7.0, 0.1, 0.03],
	&"recruit": [Kind.UI, -7.0, 0.1, 0.03],
	&"claim": [Kind.UI, -6.0, 0.1, 0.0],
	&"donate": [Kind.UI, -8.0, 0.1, 0.03],
	&"error": [Kind.UI, -14.0, 0.15, 0.0],
	&"prestige": [Kind.UI, -3.0, 1.0, 0.0],
	# Бой
	&"attack_warrior": [Kind.COMBAT, -14.0, 0.08, 0.08],
	&"attack_mage": [Kind.COMBAT, -18.0, 0.08, 0.08],
	&"attack_archer": [Kind.COMBAT, -14.0, 0.08, 0.08],
	&"hit": [Kind.COMBAT, -16.0, 0.05, 0.1],
	&"hit_crit": [Kind.COMBAT, -11.0, 0.08, 0.06],
	&"hero_hurt": [Kind.COMBAT, -16.0, 0.15, 0.08],
	&"monster_die": [Kind.COMBAT, -13.0, 0.06, 0.1],
	&"gold": [Kind.COMBAT, -20.0, 0.12, 0.05],
	&"loot": [Kind.COMBAT, -12.0, 0.1, 0.05],
	&"elite": [Kind.COMBAT, -9.0, 0.5, 0.0],
	&"boss_slam": [Kind.COMBAT, -7.0, 0.3, 0.05],
	&"boss_shield": [Kind.COMBAT, -9.0, 0.5, 0.0],
	&"wave_clear": [Kind.COMBAT, -16.0, 0.5, 0.0],
	&"skill_fire": [Kind.COMBAT, -11.0, 0.15, 0.04],
	&"skill_frost": [Kind.COMBAT, -11.0, 0.15, 0.04],
	&"skill_lightning": [Kind.COMBAT, -12.0, 0.15, 0.04],
	&"skill_arcane": [Kind.COMBAT, -11.0, 0.15, 0.04],
	&"skill_slash": [Kind.COMBAT, -10.0, 0.15, 0.05],
	&"skill_heavy": [Kind.COMBAT, -9.0, 0.15, 0.04],
	&"skill_shout": [Kind.COMBAT, -11.0, 0.15, 0.03],
	&"skill_arrows": [Kind.COMBAT, -11.0, 0.15, 0.05],
	&"skill_poison": [Kind.COMBAT, -11.0, 0.15, 0.04],
	&"skill_snare": [Kind.COMBAT, -10.0, 0.15, 0.04],
	&"skill_buff": [Kind.COMBAT, -11.0, 0.15, 0.03],
	&"skill_shield": [Kind.COMBAT, -11.0, 0.15, 0.03],
	&"skill_drain": [Kind.COMBAT, -11.0, 0.15, 0.04],
	# Уведомления
	&"level_up": [Kind.NOTIFY, -6.0, 0.5, 0.0],
	&"loot_rare": [Kind.NOTIFY, -9.0, 0.3, 0.0],
	&"loot_epic": [Kind.NOTIFY, -7.0, 0.3, 0.0],
	&"loot_legendary": [Kind.NOTIFY, -5.0, 0.5, 0.0],
	&"treasure": [Kind.NOTIFY, -5.0, 0.5, 0.0],
	&"boss_appear": [Kind.NOTIFY, -6.0, 1.0, 0.0],
	&"boss_defeated": [Kind.NOTIFY, -6.0, 1.0, 0.0],
	&"hero_died": [Kind.NOTIFY, -8.0, 1.0, 0.0],
	&"construction_done": [Kind.NOTIFY, -8.0, 0.5, 0.0],
	&"units_ready": [Kind.NOTIFY, -10.0, 0.5, 0.0],
	&"attack_alarm": [Kind.NOTIFY, -6.0, 2.0, 0.0],
	&"report": [Kind.NOTIFY, -10.0, 1.0, 0.0],
	&"guild_invite": [Kind.NOTIFY, -8.0, 1.0, 0.0],
	&"chat": [Kind.NOTIFY, -14.0, 15.0, 0.0],
	&"quest_done": [Kind.NOTIFY, -8.0, 0.5, 0.0],
	&"rest_start": [Kind.NOTIFY, -14.0, 1.0, 0.0],
	&"rest_end": [Kind.NOTIFY, -14.0, 1.0, 0.0],
}

## Умение → звук его группы. Свой звук для умения — файл skill_<id умения>.ogg: он важнее группы.
const SKILL_SOUNDS := {
	"power_strike": &"skill_slash", "cleave": &"skill_slash", "whirlwind": &"skill_slash",
	"rend": &"skill_slash", "execute": &"skill_slash", "shield_bash": &"skill_heavy",
	"earthquake": &"skill_heavy", "war_cry": &"skill_shout", "last_stand": &"skill_shout",
	"fireball": &"skill_fire", "ignite": &"skill_fire", "meteor": &"skill_fire",
	"armageddon": &"skill_fire", "frost_nova": &"skill_frost", "chain_lightning": &"skill_lightning",
	"arcane_power": &"skill_arcane", "arcane_shield": &"skill_shield", "drain_life": &"skill_drain",
	"aimed_shot": &"skill_arrows", "multishot": &"skill_arrows", "arrow_rain": &"skill_arrows",
	"deadly_volley": &"skill_arrows", "piercing_shot": &"skill_arrows", "poison_arrow": &"skill_poison",
	"snare": &"skill_snare", "eagle_eye": &"skill_buff", "hunter_fury": &"skill_buff",
}

## Звук добычи по редкости предмета (Item.Tier).
const LOOT_SOUNDS := [&"loot", &"loot", &"loot_rare", &"loot_epic", &"loot_legendary"]

var _voices: Array[AudioStreamPlayer] = []
## id → варианты звука (пустой массив — файла нет, повторно не ищем).
var _streams := {}
var _last_played := {}
var _music_players: Array[AudioStreamPlayer] = []
var _music_current := 0
var _music_track := &""
var _music_ducked := false
## Плеер музыки → его текущее затухание/нарастание.
var _music_tweens := {}
var _combat_gain := 0.0
var _attention_until := 0.0
var _in_tray := false
## Игра закрывается: новые звуки не запускаются (иначе их потоки не успеют освободиться до выхода).
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		add_child(player)
		_music_players.append(player)
	_combat_gain = 1.0 if Settings.combat_sound == Settings.CombatSound.ALWAYS else 0.0
	Settings.sound_changed.connect(_apply_volumes)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)


## Выход из игры (все кнопки выхода идут сюда): сначала звук останавливается, потом quit.
## Поток, который ещё играет при выходе, держит AudioServer, и движок сообщает об утечке.
func quit_game() -> void:
	_quitting = true
	_stop_all()
	await get_tree().create_timer(0.1, true, false, true).timeout
	get_tree().quit()


func _exit_tree() -> void:
	_stop_all()


func _stop_all() -> void:
	for player: AudioStreamPlayer in _music_players + _voices:
		player.stop()
		player.stream = null
	_streams.clear()
	_music_tweens.clear()
	_music_track = &""


func _process(delta: float) -> void:
	var in_tray := DesktopWindow.is_in_tray()
	if in_tray != _in_tray:
		_in_tray = in_tray
		# В трее музыка на паузе (не тратит процессор на декодирование), бой и интерфейс молчат.
		for player in _music_players:
			player.stream_paused = in_tray
		if in_tray:
			for voice in _voices:
				if voice.playing and voice.get_meta(&"kind", Kind.COMBAT) != Kind.NOTIFY:
					voice.stop()
	var now := Time.get_ticks_msec() / 1000.0
	var target := 0.0
	if not in_tray:
		match Settings.combat_sound:
			Settings.CombatSound.ALWAYS:
				target = 1.0
			Settings.CombatSound.ON_HOVER:
				if DesktopWindow.is_attentive():
					_attention_until = now + ATTENTION_GRACE
				target = 1.0 if now < _attention_until else 0.0
	if _combat_gain != target:
		_combat_gain = move_toward(_combat_gain, target, COMBAT_FADE_SPEED * delta)
		_apply_volumes()


## Сыграть звук по id (SOUNDS). config_id — чьи настройки взять (для своего звука умения — его группы).
func play(id: StringName, config_id: StringName = &"") -> void:
	var config: Array = SOUNDS.get(config_id if config_id != &"" else id, [])
	if config.is_empty():
		push_warning("Sound: unknown sound id %s" % id)
		return
	var kind: int = config[0]
	if not _audible(kind):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(id, -100.0)) < float(config[2]):
		return
	var streams := _get_streams(id)
	if streams.is_empty():
		return
	var voice := _pick_voice(id, kind)
	if voice == null:
		return
	_last_played[id] = now
	voice.stream = streams[randi() % streams.size()]
	voice.bus = KIND_BUSES[kind]
	voice.volume_db = config[1]
	voice.pitch_scale = 1.0 + randf_range(-config[3], config[3])
	voice.set_meta(&"id", id)
	voice.set_meta(&"kind", kind)
	voice.play()


func play_skill(skill_id: String) -> void:
	var group: StringName = SKILL_SOUNDS.get(skill_id, &"skill_arcane")
	var own := StringName("skill_" + skill_id)
	if not _get_streams(own).is_empty():
		play(own, group)
	else:
		play(group)


func play_loot(tier: int) -> void:
	play(LOOT_SOUNDS[clampi(tier, 0, LOOT_SOUNDS.size() - 1)])


## Музыка: трек (имя файла в assets/audio/music без расширения) сменяется плавно; &"" — тишина.
func play_music(track: StringName) -> void:
	if track == _music_track or _quitting:
		return
	_music_track = track
	var old := _music_players[_music_current]
	if old.playing:
		_fade(old, MUSIC_SILENT_DB, true)
	var stream := _music_stream(track)
	if stream == null:
		return
	_music_current = 1 - _music_current
	var player := _music_players[_music_current]
	player.stream = stream
	player.volume_db = MUSIC_SILENT_DB
	player.stream_paused = _in_tray
	player.play()
	_fade(player, _music_level_db(), false)


func current_music() -> StringName:
	return _music_track


## Трек сцены боя: босс — своя тема, иначе — музыка биома волны.
func music_for_wave(wave: int, boss: bool) -> StringName:
	if boss:
		return &"boss"
	var biome := Database.get_biome_for_wave(wave)
	return StringName(biome.id) if biome else &""


## Отдых героя: музыка тише.
func set_music_ducked(value: bool) -> void:
	if value == _music_ducked:
		return
	_music_ducked = value
	var player := _music_players[_music_current]
	if player.playing:
		_fade(player, _music_level_db(), false, 1.0)


func is_file_present(id: StringName) -> bool:
	return not _get_streams(id).is_empty()


func _music_level_db() -> float:
	return MUSIC_DUCK_DB if _music_ducked else 0.0


func _fade(player: AudioStreamPlayer, to_db: float, stop_after: bool, time := MUSIC_FADE_TIME) -> void:
	var previous: Tween = _music_tweens.get(player)
	if previous and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, time)
	if stop_after:
		tween.tween_callback(player.stop)
	_music_tweens[player] = tween


func _audible(kind: int) -> bool:
	if Settings.muted or _quitting:
		return false
	if _in_tray:
		return kind == Kind.NOTIFY and Settings.sound_in_tray
	if kind == Kind.COMBAT:
		# Бой не слышен — не занимаем голоса (затухающий бой ещё звучит, пока громкость не упала).
		return _combat_gain > 0.02 and Settings.combat_sound != Settings.CombatSound.OFF
	return true


## Свободный голос; если все заняты — самый «доигравший» из звуков не важнее этого (бой < интерфейс < уведомления).
func _pick_voice(id: StringName, kind: int) -> AudioStreamPlayer:
	var same := 0
	var free: AudioStreamPlayer = null
	var victim: AudioStreamPlayer = null
	var victim_score := INF
	for voice in _voices:
		if not voice.playing:
			if free == null:
				free = voice
			continue
		if voice.get_meta(&"id", &"") == id:
			same += 1
		var voice_kind: int = voice.get_meta(&"kind", Kind.COMBAT)
		if voice_kind <= kind:
			var score := voice_kind * 1000.0 - voice.get_playback_position()
			if score < victim_score:
				victim_score = score
				victim = voice
	if same >= MAX_SAME:
		return null
	if free:
		return free
	if victim:
		victim.stop()
	return victim


func _get_streams(id: StringName) -> Array:
	if _streams.has(id):
		return _streams[id]
	var found: Array = []
	for i in MAX_VARIANTS:
		var stream := _load_audio(SFX_DIR + (str(id) if i == 0 else "%s_%d" % [id, i + 1]))
		if stream:
			found.append(stream)
		elif i > 0:
			break
	_streams[id] = found
	return found


func _music_stream(track: StringName) -> AudioStream:
	if track == &"":
		return null
	var stream := _load_audio(MUSIC_DIR + str(track))
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream


func _load_audio(path_without_extension: String) -> AudioStream:
	for extension: String in EXTENSIONS:
		var path := "%s.%s" % [path_without_extension, extension]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


func _ensure_buses() -> void:
	for bus_name: StringName in [MUSIC_BUS, &"Combat", &"UI", &"Notify"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")


func _apply_volumes() -> void:
	for channel: String in CHANNEL_BUSES:
		var gain := Settings.get_volume(channel)
		if channel == "combat":
			gain *= _combat_gain
		elif channel == "master" and Settings.muted:
			gain = 0.0
		var index := AudioServer.get_bus_index(CHANNEL_BUSES[channel])
		AudioServer.set_bus_mute(index, gain <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(gain, 0.001)))


## Щелчок у каждой кнопки игры. Кнопка с meta "silent" молчит (у неё свой звук, например открытие окна).
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	var callback := _on_button_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_button_pressed(button: BaseButton) -> void:
	if button.has_meta(&"silent"):
		return
	play(&"tab" if button.toggle_mode else &"click")
