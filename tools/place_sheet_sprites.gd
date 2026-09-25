extends SceneTree
## Раскладывает нарезанный лист (ряды × колонки) по именам файлов, слева направо, ряд за рядом.
## Для монстров, снарядов и любых листов «по N в ряд». Пропустить ячейку — имя "-".
##
## 1. Нарезать:   Godot.exe --headless --path . --script res://tools/slice_ui_sheet.gd -- <лист> <папка> p 4
## 2. Разложить:  Godot.exe --headless --path . --script res://tools/place_sheet_sprites.gd -- <папка> p <папка_вывода> <колонок> <имя1> <имя2> ...
##    пример:     ... -- tmp/monsters p res://assets/sprites/monsters 4 slime goblin goblin_archer goblin_shaman forest_troll ogre skeleton zombie

const SheetLayout := preload("res://tools/sheet_layout.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("Usage: -- <slice_dir> <prefix> <out_dir> <columns> <name1> [name2 ...]")
		quit(1)
		return
	var dir: String = args[0]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(args[1] + ".json")))
	var out_dir: String = args[2]
	var columns := int(args[3])
	var names: Array = args.slice(4)
	var rows := SheetLayout.layout(manifest, ceili(names.size() / float(columns)), columns)
	if rows.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for i in names.size():
		if names[i] == "-":
			continue
		var group: Array = rows[i / columns][i % columns]
		var target := out_dir.path_join("%s.png" % names[i])
		SheetLayout.compose(dir, group, float(manifest.get("pixel_size", 1.0))).save_png(ProjectSettings.globalize_path(target))
		print("  %s  <-  %d piece(s)" % [target, group.size()])
	quit()
