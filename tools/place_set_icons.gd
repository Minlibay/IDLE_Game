extends SceneTree
## Раскладывает нарезанный лист иконок сетов (ряды по 5: шлем, плечи, грудь, ноги, ботинки)
## по именам частей: assets/sprites/treasures/<id сета>_<слот>.png. Иконку подхватит TreasureCatalog.
##
## 1. Нарезать лист:  Godot.exe --headless --path . --script res://tools/slice_ui_sheet.gd -- <лист> <папка> p 5
## 2. Разложить:      Godot.exe --headless --path . --script res://tools/place_set_icons.gd -- <папка> p <сет ряда 1> [сет ряда 2]
##
## Половинки пар склеиваются, искры отбрасываются (см. tools/sheet_layout.gd).

const SheetLayout := preload("res://tools/sheet_layout.gd")
const OUT_DIR := "res://assets/sprites/treasures/"
const SLOTS := ["helmet", "shoulders", "armor", "legs", "boots"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- <slice_dir> <prefix> <set_row1> [set_row2 ...]")
		quit(1)
		return
	var dir: String = args[0]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(args[1] + ".json")))
	var sets: Array = args.slice(2)
	var rows := SheetLayout.layout(manifest, sets.size(), SLOTS.size())
	if rows.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for row in rows.size():
		for i in SLOTS.size():
			var target := OUT_DIR + "%s_%s.png" % [sets[row], SLOTS[i]]
			SheetLayout.compose(dir, rows[row][i], float(manifest.get("pixel_size", 1.0))).save_png(ProjectSettings.globalize_path(target))
			print("  %s  <-  %d piece(s)" % [target, (rows[row][i] as Array).size()])
	quit()
