extends SceneTree
## Выгружает характеристики отрядов из data/units/*.tres в server/data/game_data.json.
## Единый источник данных — .tres; запускайте после изменения отрядов:
##   Godot.exe --headless --path . --script res://tools/export_server_data.gd

const UNITS_DIR := "res://data/units"
const OUTPUT := "res://server/data/game_data.json"


func _initialize() -> void:
	var units := {}
	for file in DirAccess.get_files_at(UNITS_DIR):
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var unit := load(UNITS_DIR.path_join(file_name)) as UnitData
		if unit == null:
			continue
		units[unit.id] = {"attack": unit.attack, "defense": unit.defense, "housing": unit.housing}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"units": units}, "  ", true) + "\n")
	file.close()
	print("Exported %d units to %s" % [units.size(), OUTPUT])
	quit()
