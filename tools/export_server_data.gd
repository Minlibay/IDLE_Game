extends SceneTree
## Выгружает игровые данные для сервера в server/data/game_data.json:
## отряды (data/units), здания (data/buildings) и параметры экономики замка (KingdomState).
## Единый источник данных — .tres; запускайте после любых изменений отрядов или зданий:
##   Godot.exe --headless --path . --script res://tools/export_server_data.gd

const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"
const OUTPUT := "res://server/data/game_data.json"
const STAT_NAMES := [
	"DAMAGE", "MAX_HP", "ARMOR", "ATTACK_SPEED", "CRIT_CHANCE", "CRIT_DAMAGE", "SKILL_DAMAGE",
	"SKILL_COOLDOWN", "CLICK_POWER", "GOLD_FIND", "XP_GAIN", "DROP_CHANCE", "REGEN", "LIFESTEAL",
	"REST_SPEED", "NEED_DECAY", "TRAINING_SPEED", "ARMY_POWER",
]


func _initialize() -> void:
	var units := {}
	for unit: UnitData in _load_all(UNITS_DIR):
		units[unit.id] = {
			"attack": unit.attack,
			"defense": unit.defense,
			"housing": unit.housing,
			"upkeep": unit.upkeep_per_minute,
			"cost": unit.cost,
			"trainTime": unit.train_time,
			"requiredBuilding": unit.required_building,
			"requiredLevel": unit.required_level,
		}
	var buildings := {}
	for building: BuildingData in _load_all(BUILDINGS_DIR):
		var modifiers := []
		for modifier in building.modifiers:
			modifiers.append({"stat": STAT_NAMES[modifier.stat], "value": modifier.value})
		buildings[building.id] = {
			"maxLevel": building.max_level,
			"townHall": building.is_town_hall,
			"baseCost": building.base_cost,
			"costGrowth": building.cost_growth,
			"baseBuildTime": building.base_build_time,
			"buildTimeGrowth": building.build_time_growth,
			"produces": building.produces,
			"productionPerLevel": building.production_per_level,
			"storagePerLevel": building.storage_per_level,
			"armyCapacityPerLevel": building.army_capacity_per_level,
			"modifiers": modifiers,
		}
	var kingdom := {
		"resources": KingdomState.RESOURCES,
		"startResources": KingdomState.START_RESOURCES,
		"baseStorage": KingdomState.BASE_STORAGE,
		"goldStorageMultiplier": KingdomState.GOLD_STORAGE_MULTIPLIER,
		"maxQueue": ArmyState.MAX_QUEUE,
		"starvingPowerMultiplier": ArmyState.STARVING_POWER_MULTIPLIER,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"units": units, "buildings": buildings, "kingdom": kingdom}, "  ", true) + "\n")
	file.close()
	print("Exported %d units, %d buildings to %s" % [units.size(), buildings.size(), OUTPUT])
	quit()


func _load_all(dir: String) -> Array:
	var result := []
	for file in DirAccess.get_files_at(dir):
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var res := load(dir.path_join(file_name))
			if res:
				result.append(res)
	return result
