extends SceneTree
## Собирает нарезанные ленты анимаций персонажа в ресурс SpriteFrames для игры.
##
##   Godot.exe --headless --path . --script res://tools/build_sprite_frames.gd -- <папка> <имя>
##
## Берёт <папка>/<имя>_<анимация>.png + .json (их делает slice_animation_strip.gd) и сохраняет
## <папка>/<имя>_frames.tres. Якоря анимаций кладутся в метаданные "anchors" (их читает Actor),
## первый кадр idle — в <папка>/<имя>_portrait.png (статичная картинка для карточек и иконок).
## Ленты должны быть уже импортированы (Godot.exe --headless --path . --import).

## Скорость (кадров/с) и зацикливание по имени анимации. Незнакомые — 10 кадров/с без повтора.
const SETTINGS := {
	"idle": [6.0, true],
	"walk": [10.0, true],
	"rest": [4.0, true],
	"attack": [14.0, false],
	"power_strike": [12.0, false],
	"whirlwind": [16.0, false],
	"war_cry": [8.0, false],
	"hurt": [12.0, false],
	"death": [8.0, false],
	"victory": [8.0, false],
}
const DEFAULT_SETTINGS := [10.0, false]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- <dir> <name>")
		quit(1)
		return
	var dir: String = args[0].trim_suffix("/")
	var prefix: String = args[1] + "_"
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var anchors := {}
	for file in DirAccess.get_files_at(dir):
		if not file.begins_with(prefix) or not file.ends_with(".png") or file.ends_with("_portrait.png"):
			continue
		var animation := StringName(file.trim_prefix(prefix).trim_suffix(".png"))
		var meta_path := dir.path_join(file.get_basename() + ".json")
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		var texture := load(dir.path_join(file)) as Texture2D
		if not meta is Dictionary or texture == null:
			push_warning("Skipped %s (no .json or not imported)" % file)
			continue
		var settings: Array = SETTINGS.get(String(animation), DEFAULT_SETTINGS)
		frames.add_animation(animation)
		frames.set_animation_speed(animation, settings[0])
		frames.set_animation_loop(animation, settings[1])
		var fw := int(meta.frame_width)
		var fh := int(meta.frame_height)
		for i in int(meta.frames):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * fw, 0, fw, fh)
			frames.add_frame(animation, atlas)
		anchors[animation] = int(meta.get("anchor_x", fw / 2))
		print("  %s: %d frames %dx%d, %.0f fps%s" % [animation, int(meta.frames), fw, fh, settings[0], " loop" if settings[1] else ""])
	if not frames.has_animation(&"idle"):
		push_error("Character must have an idle animation (%sidle.png)" % prefix)
		quit(1)
		return
	frames.set_meta("anchors", anchors)
	var out := dir.path_join(args[1] + "_frames.tres")
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		push_error("Cannot save %s: %s" % [out, error_string(err)])
		quit(1)
		return
	# Портрет: первый кадр idle.
	var idle_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(prefix + "idle.json")))
	var idle := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(prefix + "idle.png")))
	idle.get_region(Rect2i(0, 0, int(idle_meta.frame_width), int(idle_meta.frame_height))) \
		.save_png(dir.path_join(prefix + "portrait.png"))
	print("Saved %s (%d animations)" % [out, frames.get_animation_names().size()])
	quit()
