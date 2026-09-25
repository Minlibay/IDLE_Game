extends SceneTree
## Генерирует временные пиксельные спрайты-заглушки.
## Запуск: Godot.exe --headless --path . --script res://tools/generate_placeholders.gd
## Чтобы поставить свои арты — просто замените PNG с тем же именем в assets/sprites/.
## Существующие файлы НЕ перезаписываются (чтобы не затереть готовые арты). Перегенерировать всё: -- --force
## Правило для артов: персонаж смотрит ВПРАВО, прозрачный фон, ноги у нижнего края картинки.

const OUT_DIR := "res://assets/sprites/"
const OUTLINE_COLOR := Color(0.08, 0.06, 0.1, 1.0)
const CLEAR := Color(0, 0, 0, 0)

const SKIN := Color(0.96, 0.78, 0.62)
const STEEL := Color(0.62, 0.67, 0.76)
const RED := Color(0.75, 0.16, 0.16)
const BROWN := Color(0.42, 0.26, 0.14)
const LEATHER := Color(0.55, 0.37, 0.2)
const GOLD := Color(0.95, 0.78, 0.25)
const SILVER := Color(0.86, 0.89, 0.93)
const CYAN := Color(0.35, 0.9, 1.0)
const EYE := Color(0.1, 0.1, 0.15)

var _rng := RandomNumberGenerator.new()
var _force := OS.get_cmdline_user_args().has("--force")


func _initialize() -> void:
	_rng.seed = 1337
	for sub in ["heroes", "monsters", "items", "fx", "skills", "talents", "resources", "buildings", "needs", "units"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + sub))

	_save(_warrior(), "heroes/warrior.png")
	_save(_archer(), "heroes/archer.png")
	_save(_mage(), "heroes/mage.png")

	_save(_slime(), "monsters/slime.png")
	_save(_goblin(), "monsters/goblin.png")
	_save(_skeleton(), "monsters/skeleton.png")
	_save(_ogre(), "monsters/ogre.png")

	_save(_icon_sword(), "items/sword.png")
	_save(_icon_bow(), "items/bow.png")
	_save(_icon_staff(), "items/staff.png")
	_save(_icon_armor(), "items/armor.png")
	_save(_icon_helmet(), "items/helmet.png")
	_save(_icon_ring(), "items/ring.png")
	_save(_icon_shoulders(), "items/shoulders.png")
	_save(_icon_legs(), "items/legs.png")
	_save(_icon_boots(), "items/boots.png")
	# Реликвии армии.
	_save(_icon_banner(), "items/banner.png")
	_save(_icon_horn(), "items/horn.png")
	_save(_icon_tower_shield(), "items/tower_shield.png")
	_save(_icon_drill_book(), "items/drill_book.png")
	_save(_icon_cauldron(), "items/cauldron.png")
	_save(_icon_standard(), "items/standard.png")

	_save(_arrow(), "fx/arrow.png")
	_save(_orb(), "fx/orb.png", false)
	_save(_shadow(), "fx/shadow.png", false)
	_save(_ground(), "fx/ground.png", false)
	_save(_ring(), "fx/ring.png", false)
	_save(_fireball(), "fx/fireball.png", false)

	_save(_skill_power_strike(), "skills/power_strike.png")
	_save(_skill_whirlwind(), "skills/whirlwind.png")
	_save(_skill_war_cry(), "skills/war_cry.png")
	_save(_skill_aimed_shot(), "skills/aimed_shot.png")
	_save(_skill_multishot(), "skills/multishot.png")
	_save(_skill_hunter_fury(), "skills/hunter_fury.png")
	_save(_skill_fireball(), "skills/fireball.png")
	_save(_skill_meteor(), "skills/meteor.png")
	_save(_skill_arcane_shield(), "skills/arcane_shield.png")

	# Иконки талантов по типу стата (имена = StatModifier.ICON_NAMES).
	_save(_talent_damage(), "talents/damage.png")
	_save(_talent_max_hp(), "talents/max_hp.png")
	_save(_talent_armor(), "talents/armor.png")
	_save(_talent_attack_speed(), "talents/attack_speed.png")
	_save(_talent_crit_chance(), "talents/crit_chance.png")
	_save(_talent_crit_damage(), "talents/crit_damage.png")
	_save(_talent_skill_damage(), "talents/skill_damage.png")
	_save(_talent_skill_cooldown(), "talents/skill_cooldown.png")
	_save(_talent_click_power(), "talents/click_power.png")
	_save(_talent_gold_find(), "talents/gold_find.png")
	_save(_talent_xp_gain(), "talents/xp_gain.png")
	_save(_talent_drop_chance(), "talents/drop_chance.png")
	_save(_talent_regen(), "talents/regen.png")
	_save(_talent_lifesteal(), "talents/lifesteal.png")
	_save(_need_energy(), "talents/rest_speed.png")
	_save(_talent_need_decay(), "talents/need_decay.png")

	# Ресурсы королевства (имена = id ресурса).
	_save(_res_food(), "resources/food.png")
	_save(_res_water(), "resources/water.png")
	_save(_res_wood(), "resources/wood.png")
	_save(_res_stone(), "resources/stone.png")
	_save(_res_gold(), "resources/gold.png")

	# Здания (имена = id здания).
	_save(_bld_town_hall(), "buildings/town_hall.png")
	_save(_bld_farm(), "buildings/farm.png")
	_save(_bld_well(), "buildings/well.png")
	_save(_bld_sawmill(), "buildings/sawmill.png")
	_save(_bld_quarry(), "buildings/quarry.png")
	_save(_bld_tavern(), "buildings/tavern.png")
	_save(_bld_forge(), "buildings/forge.png")
	_save(_bld_barracks(), "buildings/barracks.png")
	_save(_bld_market(), "buildings/market.png")
	_save(_bld_stable(), "buildings/stable.png")

	# Отряды армии (имена = id отряда) и иконки новых бонусов.
	_save(_unit_militia(), "units/militia.png")
	_save(_unit_spearman(), "units/spearman.png")
	_save(_unit_archer(), "units/archer.png")
	_save(_unit_knight(), "units/knight.png")
	_save(_talent_training_speed(), "talents/training_speed.png")
	_save(_talent_army_power(), "talents/army_power.png")

	# Потребности героя.
	_save(_need_hunger(), "needs/hunger.png")
	_save(_need_thirst(), "needs/thirst.png")
	_save(_need_energy(), "needs/energy.png")

	print("Placeholder sprites generated in ", OUT_DIR)
	quit()


# --- Персонажи (32x48, смотрят вправо) ---------------------------------------

func _warrior() -> Image:
	var img := _new(32, 48)
	var steel_dark := STEEL.darkened(0.3)
	_rect(img, 11, 34, 4, 9, steel_dark)
	_rect(img, 17, 34, 4, 9, steel_dark)
	_rect(img, 10, 42, 6, 4, BROWN)
	_rect(img, 16, 42, 6, 4, BROWN)
	_rect(img, 9, 20, 14, 15, STEEL)
	_rect(img, 9, 20, 3, 15, steel_dark)
	_rect(img, 9, 31, 14, 2, BROWN)
	_rect(img, 15, 31, 2, 2, GOLD)
	_rect(img, 11, 11, 10, 9, SKIN)
	_rect(img, 18, 14, 2, 2, EYE)
	_rect(img, 10, 7, 12, 5, STEEL)
	_rect(img, 10, 11, 3, 5, STEEL)
	_rect(img, 14, 3, 4, 4, RED)
	_rect(img, 4, 21, 7, 12, RED)
	_rect(img, 5, 22, 5, 10, RED.lightened(0.15))
	_rect(img, 6, 25, 3, 4, GOLD)
	_rect(img, 24, 5, 3, 18, SILVER)
	_rect(img, 25, 5, 1, 18, Color.WHITE)
	_rect(img, 21, 22, 9, 2, GOLD)
	_rect(img, 24, 24, 3, 5, BROWN)
	_rect(img, 21, 24, 3, 4, SKIN)
	return img


func _archer() -> Image:
	var img := _new(32, 48)
	var green := Color(0.25, 0.55, 0.3)
	var green_dark := green.darkened(0.35)
	_rect(img, 6, 16, 4, 14, LEATHER)
	_rect(img, 6, 12, 1, 4, SILVER)
	_rect(img, 8, 11, 1, 5, SILVER)
	_rect(img, 11, 34, 4, 9, LEATHER.darkened(0.3))
	_rect(img, 17, 34, 4, 9, LEATHER.darkened(0.3))
	_rect(img, 10, 42, 6, 4, BROWN)
	_rect(img, 16, 42, 6, 4, BROWN)
	_rect(img, 10, 20, 12, 15, green)
	_rect(img, 10, 30, 12, 2, LEATHER)
	_rect(img, 11, 11, 10, 9, SKIN)
	_rect(img, 18, 14, 2, 2, EYE)
	_rect(img, 10, 8, 12, 4, green_dark)
	_rect(img, 10, 8, 3, 11, green_dark)
	_rect(img, 9, 12, 2, 9, green_dark)
	for y in range(9, 39):
		var t := float(y - 9) / 29.0
		var x := 24 + roundi(sin(t * PI) * 5.0)
		_rect(img, x, y, 2, 1, BROWN)
	for y in range(10, 38):
		_px(img, 24, y, Color(0.92, 0.92, 0.85))
	_rect(img, 22, 22, 4, 4, SKIN)
	return img


func _mage() -> Image:
	var img := _new(32, 48)
	var purple := Color(0.42, 0.25, 0.65)
	var purple_dark := purple.darkened(0.35)
	for y in range(20, 46):
		var half := 5 + int((y - 20) * 0.22)
		_rect(img, 16 - half, y, half * 2, 1, purple)
	_rect(img, 10, 44, 12, 2, GOLD)
	_rect(img, 11, 29, 10, 2, GOLD)
	_rect(img, 11, 13, 10, 8, SKIN)
	_rect(img, 18, 16, 2, 2, EYE)
	_rect(img, 12, 19, 8, 5, Color(0.92, 0.92, 0.95))
	_rect(img, 8, 12, 16, 2, purple_dark)
	for i in range(10):
		var w := 12 - i
		_rect(img, 10 + i / 2, 11 - i, w, 1, purple_dark)
	_px(img, 13, 8, GOLD)
	_rect(img, 25, 8, 2, 38, BROWN)
	_ellipse(img, 26.0, 7.0, 3.5, 3.5, CYAN)
	_px(img, 25, 6, Color.WHITE)
	_rect(img, 23, 24, 4, 4, SKIN)
	return img


func _slime() -> Image:
	var img := _new(32, 24)
	var green := Color(0.35, 0.8, 0.35)
	_ellipse(img, 16.0, 14.0, 13.0, 8.5, green)
	_ellipse(img, 13.0, 11.0, 6.0, 3.0, green.lightened(0.3))
	_rect(img, 19, 10, 3, 4, Color.WHITE)
	_rect(img, 24, 10, 3, 4, Color.WHITE)
	_rect(img, 20, 11, 2, 2, EYE)
	_rect(img, 25, 11, 2, 2, EYE)
	return img


func _goblin() -> Image:
	var img := _new(32, 40)
	var skin := Color(0.45, 0.7, 0.3)
	_rect(img, 12, 30, 3, 6, BROWN)
	_rect(img, 17, 30, 3, 6, BROWN)
	_rect(img, 11, 35, 5, 3, BROWN.darkened(0.3))
	_rect(img, 16, 35, 5, 3, BROWN.darkened(0.3))
	_rect(img, 10, 19, 12, 12, LEATHER)
	_rect(img, 10, 8, 12, 11, skin)
	_rect(img, 6, 10, 4, 3, skin)
	_rect(img, 22, 10, 4, 3, skin)
	_rect(img, 18, 12, 2, 2, RED)
	_rect(img, 15, 16, 6, 1, EYE)
	_px(img, 16, 17, Color.WHITE)
	_px(img, 19, 17, Color.WHITE)
	_rect(img, 25, 12, 2, 9, SILVER)
	_rect(img, 22, 20, 4, 3, skin)
	return img


func _skeleton() -> Image:
	var img := _new(32, 48)
	var bone := Color(0.9, 0.88, 0.8)
	var rust := Color(0.6, 0.35, 0.2)
	_rect(img, 11, 6, 11, 10, bone)
	_rect(img, 17, 9, 3, 3, EYE)
	_rect(img, 13, 9, 2, 3, EYE)
	_rect(img, 12, 16, 9, 3, bone)
	_rect(img, 13, 17, 1, 1, EYE)
	_rect(img, 16, 17, 1, 1, EYE)
	_rect(img, 15, 19, 2, 15, bone)
	for i in range(4):
		_rect(img, 11, 21 + i * 3, 10, 1, bone)
	_rect(img, 12, 33, 8, 3, bone)
	_rect(img, 12, 36, 2, 9, bone)
	_rect(img, 18, 36, 2, 9, bone)
	_rect(img, 11, 44, 4, 2, bone)
	_rect(img, 17, 44, 4, 2, bone)
	_rect(img, 9, 21, 2, 12, bone)
	_rect(img, 25, 8, 2, 16, rust)
	_rect(img, 23, 23, 6, 2, BROWN)
	_rect(img, 22, 21, 3, 9, bone)
	return img


func _ogre() -> Image:
	var img := _new(48, 56)
	var skin := Color(0.55, 0.6, 0.35)
	var club := BROWN.darkened(0.1)
	_rect(img, 14, 42, 7, 10, skin.darkened(0.2))
	_rect(img, 27, 42, 7, 10, skin.darkened(0.2))
	_rect(img, 12, 50, 10, 3, BROWN)
	_rect(img, 26, 50, 10, 3, BROWN)
	_ellipse(img, 24.0, 30.0, 13.0, 12.0, skin)
	_ellipse(img, 26.0, 33.0, 7.0, 6.0, skin.lightened(0.15))
	_rect(img, 13, 38, 22, 6, BROWN)
	_rect(img, 17, 8, 14, 12, skin)
	_rect(img, 26, 12, 3, 2, RED)
	_rect(img, 20, 12, 3, 2, RED)
	_rect(img, 22, 17, 8, 1, EYE)
	_rect(img, 23, 15, 1, 2, Color.WHITE)
	_rect(img, 28, 15, 1, 2, Color.WHITE)
	_rect(img, 7, 22, 6, 16, skin.darkened(0.1))
	_rect(img, 38, 10, 4, 22, club)
	_ellipse(img, 40.0, 10.0, 5.0, 7.0, club.darkened(0.2))
	_px(img, 35, 8, SILVER)
	_px(img, 45, 11, SILVER)
	_px(img, 40, 3, SILVER)
	_rect(img, 35, 24, 6, 12, skin.darkened(0.1))
	return img


# --- Иконки предметов (16x16) -------------------------------------------------

func _icon_sword() -> Image:
	var img := _new(16, 16)
	_rect(img, 7, 1, 2, 9, SILVER)
	_rect(img, 7, 1, 1, 9, Color.WHITE)
	_rect(img, 4, 10, 8, 2, GOLD)
	_rect(img, 7, 12, 2, 3, BROWN)
	return img


func _icon_bow() -> Image:
	var img := _new(16, 16)
	for y in range(1, 15):
		var t := float(y - 1) / 13.0
		_rect(img, 5 + roundi(sin(t * PI) * 6.0), y, 2, 1, BROWN)
	for y in range(2, 14):
		_px(img, 5, y, Color(0.92, 0.92, 0.85))
	return img


func _icon_staff() -> Image:
	var img := _new(16, 16)
	_rect(img, 7, 4, 2, 11, BROWN)
	_ellipse(img, 8.0, 4.0, 2.8, 2.8, CYAN)
	_px(img, 7, 3, Color.WHITE)
	return img


func _icon_armor() -> Image:
	var img := _new(16, 16)
	_rect(img, 4, 4, 8, 10, LEATHER)
	_rect(img, 2, 4, 3, 4, LEATHER.darkened(0.2))
	_rect(img, 11, 4, 3, 4, LEATHER.darkened(0.2))
	_rect(img, 6, 4, 4, 2, CLEAR)
	_rect(img, 4, 10, 8, 1, BROWN)
	return img


func _icon_helmet() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8.0, 10.0, 6.0, 7.0, STEEL)
	_rect(img, 1, 10, 14, 6, CLEAR)
	_rect(img, 2, 10, 12, 2, STEEL.darkened(0.3))
	_rect(img, 5, 7, 6, 1, EYE)
	_rect(img, 7, 1, 2, 3, RED)
	return img


func _icon_ring() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8.0, 10.0, 5.0, 4.5, GOLD)
	_ellipse(img, 8.0, 10.0, 2.8, 2.4, CLEAR)
	_ellipse(img, 8.0, 4.5, 2.2, 2.2, RED)
	_px(img, 7, 4, Color.WHITE)
	return img


func _icon_shoulders() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 4.0, 8.0, 3.6, 3.2, STEEL)
	_ellipse(img, 12.0, 8.0, 3.6, 3.2, STEEL)
	_rect(img, 0, 8, 16, 5, CLEAR)
	_rect(img, 1, 8, 6, 1, STEEL.darkened(0.3))
	_rect(img, 9, 8, 6, 1, STEEL.darkened(0.3))
	_rect(img, 6, 9, 4, 4, LEATHER)
	_px(img, 3, 6, Color.WHITE)
	_px(img, 11, 6, Color.WHITE)
	return img


func _icon_legs() -> Image:
	var img := _new(16, 16)
	_rect(img, 4, 2, 8, 3, LEATHER.darkened(0.2))
	_rect(img, 4, 5, 3, 9, STEEL)
	_rect(img, 9, 5, 3, 9, STEEL)
	_rect(img, 4, 8, 3, 1, STEEL.darkened(0.3))
	_rect(img, 9, 8, 3, 1, STEEL.darkened(0.3))
	_rect(img, 7, 2, 2, 2, GOLD)
	return img


func _icon_boots() -> Image:
	var img := _new(16, 16)
	_rect(img, 3, 3, 4, 9, LEATHER)
	_rect(img, 3, 11, 6, 3, LEATHER.darkened(0.2))
	_rect(img, 9, 4, 4, 8, LEATHER)
	_rect(img, 9, 11, 6, 3, LEATHER.darkened(0.2))
	_rect(img, 3, 3, 4, 1, BROWN)
	_rect(img, 9, 4, 4, 1, BROWN)
	return img


func _icon_banner() -> Image:
	var img := _new(16, 16)
	_rect(img, 3, 1, 1, 14, BROWN)
	_rect(img, 4, 2, 9, 7, RED)
	for x in range(4, 13):
		_px(img, x, 9 + (x % 2), RED.darkened(0.2))
	_ellipse(img, 8.5, 5.5, 1.8, 1.8, GOLD)
	_px(img, 3, 0, GOLD)
	return img


func _icon_horn() -> Image:
	var img := _new(16, 16)
	for i in 11:
		var t := float(i) / 10.0
		var x := 2 + i
		var y := roundi(11.0 - sin(t * PI * 0.8) * 5.0)
		var r := int(1 + t * 2.5)
		_rect(img, x, y - r, 1, r * 2 + 1, Color(0.93, 0.87, 0.72).darkened(0.3 * (1.0 - t)))
	_rect(img, 5, 7, 1, 7, GOLD)
	_rect(img, 9, 5, 1, 7, GOLD)
	return img


func _icon_tower_shield() -> Image:
	var img := _new(16, 16)
	_rect(img, 3, 2, 10, 9, STEEL)
	_ellipse(img, 8.0, 10.0, 5.0, 5.0, STEEL)
	_rect(img, 3, 1, 10, 1, STEEL.darkened(0.3))
	_rect(img, 7, 3, 2, 10, Color(0.25, 0.45, 0.85))
	_rect(img, 4, 6, 8, 2, Color(0.25, 0.45, 0.85))
	return img


func _icon_drill_book() -> Image:
	var img := _new(16, 16)
	_rect(img, 3, 2, 10, 12, Color(0.45, 0.2, 0.2))
	_rect(img, 4, 3, 8, 10, Color(0.55, 0.25, 0.25))
	_rect(img, 3, 2, 2, 12, Color(0.3, 0.12, 0.12))
	_rect(img, 7, 5, 4, 1, GOLD)
	_rect(img, 7, 7, 4, 1, GOLD)
	_rect(img, 8, 9, 2, 2, GOLD)
	return img


func _icon_cauldron() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8.0, 10.0, 6.0, 4.5, Color(0.25, 0.25, 0.28))
	_rect(img, 2, 6, 12, 2, Color(0.35, 0.35, 0.4))
	_rect(img, 4, 6, 8, 1, Color(0.85, 0.6, 0.25))
	_rect(img, 4, 14, 2, 2, Color(0.2, 0.2, 0.22))
	_rect(img, 10, 14, 2, 2, Color(0.2, 0.2, 0.22))
	_px(img, 6, 3, Color(0.9, 0.9, 0.9, 0.7))
	_px(img, 9, 2, Color(0.9, 0.9, 0.9, 0.7))
	_px(img, 8, 4, Color(0.9, 0.9, 0.9, 0.7))
	return img


func _icon_standard() -> Image:
	var img := _new(16, 16)
	_rect(img, 7, 3, 2, 12, BROWN)
	_rect(img, 3, 3, 10, 1, GOLD)
	_rect(img, 3, 4, 10, 6, Color(0.5, 0.2, 0.7))
	_rect(img, 3, 10, 3, 2, Color(0.5, 0.2, 0.7))
	_rect(img, 10, 10, 3, 2, Color(0.5, 0.2, 0.7))
	_ellipse(img, 8.0, 7.0, 2.0, 2.0, GOLD)
	_ellipse(img, 8.0, 2.0, 1.5, 1.5, GOLD)
	return img


# --- Эффекты ------------------------------------------------------------------

func _arrow() -> Image:
	var img := _new(20, 7)
	_rect(img, 3, 3, 13, 1, BROWN)
	_rect(img, 16, 2, 2, 3, SILVER)
	_px(img, 18, 3, SILVER)
	_rect(img, 1, 1, 3, 2, RED)
	_rect(img, 1, 4, 3, 2, RED)
	return img


func _orb() -> Image:
	var img := _new(12, 12)
	_ellipse(img, 6.0, 6.0, 5.5, 5.5, Color(CYAN, 0.55))
	_ellipse(img, 6.0, 6.0, 3.5, 3.5, CYAN.lightened(0.3))
	_ellipse(img, 5.0, 5.0, 1.3, 1.3, Color.WHITE)
	return img


func _shadow() -> Image:
	var img := _new(32, 16)
	for y in img.get_height():
		for x in img.get_width():
			var dx := (x + 0.5 - 16.0) / 16.0
			var dy := (y + 0.5 - 8.0) / 8.0
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 0.7) * 0.45
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return img


## Полоса земли: сверху (дальний край) трава плавно проявляется, снизу — край земли.
func _ground() -> Image:
	var img := _new(64, 96)
	var grass := Color(0.36, 0.62, 0.3)
	var dirt := Color(0.45, 0.32, 0.2)
	for y in img.get_height():
		for x in img.get_width():
			var c := grass
			var alpha := 1.0
			if y < 20:
				alpha = float(y) / 20.0
				if _rng.randf() > alpha:
					continue
			elif y >= 74:
				c = dirt
				if y >= 84:
					alpha = 1.0 - float(y - 84) / 12.0
					if _rng.randf() > alpha:
						continue
			var v := _rng.randf_range(-0.06, 0.06)
			c = Color(c.r + v, c.g + v, c.b + v * 0.5)
			if y < 74 and _rng.randf() < 0.006:
				c = [Color(1, 0.9, 0.3), Color(1, 0.55, 0.7), Color.WHITE].pick_random()
			img.set_pixel(x, y, c)
	for x in img.get_width():
		img.set_pixel(x, 73, grass.darkened(0.3))
	return img


## Мягкое кольцо для эффектов умений по области (цвет задаётся материалом).
func _ring() -> Image:
	var img := _new(64, 64)
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
			var ring := exp(-pow((d - 0.85) / 0.09, 2.0))
			var fill := 0.18 if d < 0.85 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(ring, fill), 0.0, 1.0)))
	return img


func _fireball() -> Image:
	var img := _new(12, 12)
	_ellipse(img, 6.0, 6.0, 5.5, 5.5, Color(1.0, 0.35, 0.1, 0.6))
	_ellipse(img, 6.0, 6.0, 3.8, 3.8, Color(1.0, 0.55, 0.15))
	_ellipse(img, 6.0, 6.0, 2.2, 2.2, Color(1.0, 0.9, 0.4))
	return img


# --- Иконки умений (16x16) ----------------------------------------------------

func _skill_bg(color: Color) -> Image:
	var img := _new(16, 16)
	_rect(img, 1, 1, 14, 14, color.darkened(0.45))
	_rect(img, 2, 2, 12, 12, color.darkened(0.2))
	return img


func _skill_power_strike() -> Image:
	var img := _skill_bg(RED)
	_rect(img, 7, 2, 2, 8, SILVER)
	_rect(img, 5, 9, 6, 1, GOLD)
	_rect(img, 7, 10, 2, 3, BROWN)
	for p: Vector2i in [Vector2i(4, 3), Vector2i(11, 4), Vector2i(3, 7), Vector2i(12, 8)]:
		_px(img, p.x, p.y, GOLD)
	return img


func _skill_whirlwind() -> Image:
	var img := _skill_bg(STEEL)
	for i in 48:
		var t := i / 48.0
		var r := 1.0 + t * 5.0
		var a := t * TAU * 1.6
		_px(img, 8 + roundi(cos(a) * r), 8 + roundi(sin(a) * r), Color.WHITE)
	return img


func _skill_war_cry() -> Image:
	var img := _skill_bg(Color(1.0, 0.55, 0.15))
	_rect(img, 7, 3, 2, 7, Color.WHITE)
	_rect(img, 7, 11, 2, 2, Color.WHITE)
	return img


func _skill_aimed_shot() -> Image:
	var img := _skill_bg(Color(0.3, 0.6, 0.3))
	_ellipse(img, 8.0, 8.0, 5.0, 5.0, RED)
	_ellipse(img, 8.0, 8.0, 3.5, 3.5, Color.WHITE)
	_ellipse(img, 8.0, 8.0, 2.0, 2.0, RED)
	return img


func _skill_multishot() -> Image:
	var img := _skill_bg(Color(0.3, 0.6, 0.3))
	for i in 3:
		var y := 4 + i * 4
		_rect(img, 3, y, 8, 1, BROWN)
		_rect(img, 11, y - 1, 2, 3, SILVER)
		_px(img, 3, y - 1, RED)
	return img


func _skill_hunter_fury() -> Image:
	var img := _skill_bg(Color(0.85, 0.75, 0.2))
	for i in 8:
		_px(img, 4 + i, 11 - i, BROWN)
	_rect(img, 11, 3, 2, 2, SILVER)
	_rect(img, 2, 6, 3, 1, Color.WHITE)
	_rect(img, 3, 9, 3, 1, Color.WHITE)
	_rect(img, 5, 12, 3, 1, Color.WHITE)
	return img


func _skill_fireball() -> Image:
	var img := _skill_bg(Color(0.55, 0.2, 0.1))
	_ellipse(img, 6.0, 10.0, 3.0, 2.0, Color(1.0, 0.5, 0.1))
	_ellipse(img, 9.0, 7.0, 4.0, 4.0, Color(1.0, 0.5, 0.1))
	_ellipse(img, 9.0, 7.0, 2.5, 2.5, Color(1.0, 0.85, 0.3))
	_px(img, 8, 6, Color.WHITE)
	return img


func _skill_meteor() -> Image:
	var img := _skill_bg(Color(0.45, 0.25, 0.6))
	for i in 5:
		_rect(img, 3 + i, 3 + i, 2, 2, Color(1.0, 0.6, 0.2))
	_ellipse(img, 10.0, 10.0, 3.5, 3.5, BROWN)
	_px(img, 9, 9, BROWN.lightened(0.35))
	return img


func _skill_arcane_shield() -> Image:
	var img := _skill_bg(Color(0.2, 0.35, 0.8))
	_rect(img, 4, 3, 8, 6, CYAN)
	for i in 4:
		_rect(img, 4 + i, 9 + i, 8 - 2 * i, 1, CYAN)
	_rect(img, 6, 5, 4, 4, CYAN.lightened(0.5))
	return img


# --- Иконки талантов (16x16) --------------------------------------------------

func _talent_damage() -> Image:
	var img := _skill_bg(Color(0.7, 0.2, 0.2))
	_rect(img, 7, 3, 2, 7, SILVER)
	_rect(img, 5, 10, 6, 1, GOLD)
	_rect(img, 7, 11, 2, 3, BROWN)
	return img


func _talent_max_hp() -> Image:
	var img := _skill_bg(Color(0.75, 0.3, 0.4))
	_ellipse(img, 6.0, 6.5, 2.6, 2.6, RED.lightened(0.2))
	_ellipse(img, 10.0, 6.5, 2.6, 2.6, RED.lightened(0.2))
	for i in 6:
		_rect(img, 3 + i, 7 + i, 10 - 2 * i, 1, RED.lightened(0.2))
	return img


func _talent_armor() -> Image:
	var img := _skill_bg(STEEL)
	_rect(img, 4, 3, 8, 6, SILVER)
	for i in 4:
		_rect(img, 4 + i, 9 + i, 8 - 2 * i, 1, SILVER)
	_rect(img, 7, 4, 2, 7, STEEL.darkened(0.3))
	return img


func _talent_attack_speed() -> Image:
	var img := _skill_bg(Color(0.85, 0.7, 0.15))
	for i in 4:
		_px(img, 3 + i, 4 + i, Color.WHITE)
		_px(img, 3 + i, 11 - i, Color.WHITE)
		_px(img, 8 + i, 4 + i, Color.WHITE)
		_px(img, 8 + i, 11 - i, Color.WHITE)
	return img


func _talent_crit_chance() -> Image:
	var img := _skill_bg(Color(0.9, 0.5, 0.15))
	_ellipse(img, 8.0, 8.0, 5.0, 5.0, Color.WHITE)
	_ellipse(img, 8.0, 8.0, 3.5, 3.5, RED)
	_ellipse(img, 8.0, 8.0, 1.5, 1.5, Color.WHITE)
	return img


func _talent_crit_damage() -> Image:
	var img := _skill_bg(Color(0.55, 0.1, 0.1))
	_rect(img, 7, 2, 2, 12, GOLD)
	_rect(img, 2, 7, 12, 2, GOLD)
	for i in 4:
		_px(img, 4 + i, 4 + i, Color(1, 0.95, 0.6))
		_px(img, 11 - i, 4 + i, Color(1, 0.95, 0.6))
		_px(img, 4 + i, 11 - i, Color(1, 0.95, 0.6))
		_px(img, 11 - i, 11 - i, Color(1, 0.95, 0.6))
	return img


func _talent_skill_damage() -> Image:
	var img := _skill_bg(Color(0.5, 0.25, 0.75))
	_rect(img, 7, 3, 2, 10, CYAN.lightened(0.4))
	_rect(img, 3, 7, 10, 2, CYAN.lightened(0.4))
	_rect(img, 6, 6, 4, 4, Color.WHITE)
	return img


func _talent_skill_cooldown() -> Image:
	var img := _skill_bg(Color(0.25, 0.4, 0.8))
	_rect(img, 4, 3, 8, 1, GOLD)
	_rect(img, 4, 12, 8, 1, GOLD)
	for i in 4:
		_rect(img, 5 + i, 4 + i, 6 - 2 * i, 1, SILVER)
		_rect(img, 8 - i, 8 + i, 2 * i, 1, SILVER)
	return img


func _talent_click_power() -> Image:
	var img := _skill_bg(Color(0.2, 0.6, 0.6))
	for i in 8:
		_rect(img, 5, 3 + i, i / 2 + 1, 1, Color.WHITE)
	_rect(img, 7, 10, 2, 3, Color.WHITE)
	return img


func _talent_gold_find() -> Image:
	var img := _skill_bg(Color(0.6, 0.45, 0.1))
	_ellipse(img, 8.0, 8.0, 5.0, 5.0, GOLD)
	_ellipse(img, 8.0, 8.0, 3.5, 3.5, GOLD.darkened(0.2))
	_rect(img, 7, 5, 2, 6, GOLD.lightened(0.3))
	return img


func _talent_xp_gain() -> Image:
	var img := _skill_bg(Color(0.2, 0.55, 0.45))
	for i in 5:
		_rect(img, 8 - i, 3 + i, 2 * i + 1, 1, Color(0.6, 1.0, 0.6))
	_rect(img, 6, 8, 5, 5, Color(0.6, 1.0, 0.6))
	return img


func _talent_drop_chance() -> Image:
	var img := _skill_bg(Color(0.5, 0.33, 0.18))
	_rect(img, 3, 6, 10, 7, LEATHER)
	_rect(img, 3, 4, 10, 3, LEATHER.lightened(0.2))
	_rect(img, 7, 7, 2, 3, GOLD)
	return img


func _talent_regen() -> Image:
	var img := _skill_bg(Color(0.25, 0.6, 0.3))
	_rect(img, 7, 3, 2, 10, Color.WHITE)
	_rect(img, 3, 7, 10, 2, Color.WHITE)
	return img


func _talent_lifesteal() -> Image:
	var img := _skill_bg(Color(0.4, 0.08, 0.12))
	_ellipse(img, 8.0, 10.0, 3.5, 3.5, RED.lightened(0.1))
	for i in 5:
		_rect(img, 8 - i / 2, 3 + i, 1 + i, 1, RED.lightened(0.1))
	_px(img, 7, 9, Color(1, 0.7, 0.7))
	return img


func _talent_need_decay() -> Image:
	var img := _skill_bg(Color(0.6, 0.4, 0.2))
	_draw_drumstick(img)
	_rect(img, 10, 10, 4, 4, Color(0.4, 1.0, 0.5))
	_rect(img, 11, 9, 2, 6, Color(0.4, 1.0, 0.5))
	_rect(img, 9, 11, 6, 2, Color(0.4, 1.0, 0.5))
	return img


# --- Ресурсы (16x16, без фона) -----------------------------------------------

func _draw_drumstick(img: Image) -> void:
	_ellipse(img, 6.5, 6.5, 4.0, 3.5, Color(0.72, 0.4, 0.18))
	_ellipse(img, 5.5, 5.5, 1.5, 1.2, Color(0.9, 0.6, 0.3))
	for i in 4:
		_rect(img, 9 + i, 9 + i, 2, 2, Color(0.95, 0.93, 0.85))
	_rect(img, 12, 13, 2, 2, Color(0.95, 0.93, 0.85))


func _draw_drop(img: Image, color: Color) -> void:
	_ellipse(img, 8.0, 10.0, 4.5, 4.0, color)
	for i in 6:
		_rect(img, 8 - i / 2, 2 + i, 1 + i, 1, color)
	_px(img, 6, 9, Color.WHITE)


func _res_food() -> Image:
	var img := _new(16, 16)
	_draw_drumstick(img)
	return img


func _res_water() -> Image:
	var img := _new(16, 16)
	_draw_drop(img, Color(0.3, 0.6, 1.0))
	return img


func _res_wood() -> Image:
	var img := _new(16, 16)
	_rect(img, 2, 5, 12, 7, Color(0.55, 0.35, 0.18))
	_rect(img, 2, 5, 12, 1, Color(0.65, 0.45, 0.25))
	_ellipse(img, 13.0, 8.5, 2.2, 3.5, Color(0.85, 0.7, 0.45))
	_px(img, 13, 8, Color(0.55, 0.35, 0.18))
	return img


func _res_stone() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8.0, 9.0, 6.0, 4.5, Color(0.55, 0.55, 0.6))
	_ellipse(img, 6.5, 7.5, 2.5, 1.5, Color(0.7, 0.7, 0.75))
	return img


func _res_gold() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8.0, 8.0, 5.5, 5.5, GOLD)
	_ellipse(img, 8.0, 8.0, 3.8, 3.8, GOLD.darkened(0.2))
	_rect(img, 7, 5, 2, 6, GOLD.lightened(0.35))
	return img


# --- Здания (16x16) ------------------------------------------------------------

func _house(bg: Color, roof: Color, wall: Color) -> Image:
	var img := _skill_bg(bg)
	for i in 4:
		_rect(img, 7 - i * 1, 3 + i, 2 + i * 2, 1, roof)
	_rect(img, 3, 7, 10, 1, roof)
	_rect(img, 4, 8, 8, 5, wall)
	_rect(img, 7, 10, 2, 3, BROWN.darkened(0.3))
	return img


func _bld_town_hall() -> Image:
	var img := _house(Color(0.35, 0.3, 0.55), RED, Color(0.85, 0.8, 0.7))
	_rect(img, 12, 2, 1, 5, BROWN)
	_rect(img, 13, 2, 2, 2, GOLD)
	_rect(img, 5, 9, 1, 1, CYAN)
	_rect(img, 10, 9, 1, 1, CYAN)
	return img


func _bld_farm() -> Image:
	var img := _skill_bg(Color(0.35, 0.55, 0.25))
	for x in [4, 7, 10]:
		_rect(img, x, 6, 1, 7, Color(0.55, 0.75, 0.25))
		_rect(img, x - 1, 3, 3, 4, Color(0.95, 0.8, 0.3))
	_rect(img, 2, 12, 12, 2, BROWN)
	return img


func _bld_well() -> Image:
	var img := _skill_bg(Color(0.25, 0.4, 0.6))
	_rect(img, 3, 3, 10, 2, RED.darkened(0.2))
	_rect(img, 4, 5, 1, 4, BROWN)
	_rect(img, 11, 5, 1, 4, BROWN)
	_rect(img, 3, 9, 10, 4, Color(0.6, 0.6, 0.65))
	_rect(img, 5, 9, 6, 1, Color(0.3, 0.6, 1.0))
	return img


func _bld_sawmill() -> Image:
	var img := _skill_bg(Color(0.45, 0.35, 0.2))
	_rect(img, 2, 9, 12, 4, Color(0.55, 0.35, 0.18))
	_ellipse(img, 13.0, 11.0, 1.5, 2.0, Color(0.85, 0.7, 0.45))
	_ellipse(img, 8.0, 6.0, 3.5, 3.5, SILVER)
	_ellipse(img, 8.0, 6.0, 1.2, 1.2, STEEL.darkened(0.3))
	return img


func _bld_quarry() -> Image:
	var img := _skill_bg(Color(0.4, 0.4, 0.45))
	_ellipse(img, 6.0, 11.0, 4.0, 2.5, Color(0.6, 0.6, 0.65))
	_ellipse(img, 11.0, 12.0, 2.5, 1.8, Color(0.7, 0.7, 0.75))
	for i in 7:
		_px(img, 5 + i, 8 - i, BROWN)
	_rect(img, 9, 2, 5, 2, SILVER)
	return img


func _bld_tavern() -> Image:
	var img := _house(Color(0.5, 0.3, 0.2), Color(0.55, 0.3, 0.15), Color(0.8, 0.65, 0.45))
	_rect(img, 10, 9, 3, 3, GOLD)
	_rect(img, 10, 9, 3, 1, Color.WHITE)
	_px(img, 13, 10, GOLD)
	return img


func _bld_forge() -> Image:
	var img := _skill_bg(Color(0.3, 0.25, 0.25))
	_rect(img, 3, 7, 10, 2, STEEL.darkened(0.3))
	_rect(img, 5, 9, 6, 2, STEEL.darkened(0.4))
	_rect(img, 4, 11, 8, 2, STEEL.darkened(0.3))
	_px(img, 7, 4, Color(1.0, 0.6, 0.2))
	_px(img, 9, 3, Color(1.0, 0.8, 0.3))
	_px(img, 11, 5, Color(1.0, 0.6, 0.2))
	return img


func _bld_barracks() -> Image:
	var img := _skill_bg(Color(0.5, 0.2, 0.2))
	for i in 10:
		_px(img, 3 + i, 12 - i, SILVER)
		_px(img, 3 + i, 3 + i, SILVER)
	_rect(img, 6, 5, 4, 6, RED)
	_rect(img, 7, 6, 2, 4, GOLD)
	return img


func _bld_market() -> Image:
	var img := _skill_bg(Color(0.4, 0.45, 0.25))
	for i in 5:
		_rect(img, 2 + i * 2 + i / 2, 3, 2, 3, RED if i % 2 == 0 else Color.WHITE)
	_rect(img, 3, 6, 1, 7, BROWN)
	_rect(img, 12, 6, 1, 7, BROWN)
	_rect(img, 3, 10, 10, 2, LEATHER)
	_ellipse(img, 8.0, 9.0, 1.5, 1.2, GOLD)
	return img


func _bld_stable() -> Image:
	var img := _house(Color(0.45, 0.35, 0.25), BROWN, Color(0.75, 0.6, 0.4))
	_rect(img, 4, 9, 8, 1, BROWN.darkened(0.2))
	_rect(img, 10, 9, 2, 2, Color(0.95, 0.85, 0.5))
	return img


# --- Отряды армии (16x16) ------------------------------------------------------

## Маленький солдатик: голова, тело нужного цвета, ноги.
func _soldier(bg: Color, body: Color) -> Image:
	var img := _skill_bg(bg)
	_rect(img, 6, 3, 4, 4, SKIN)
	_rect(img, 5, 7, 6, 5, body)
	_rect(img, 6, 12, 1, 2, BROWN)
	_rect(img, 9, 12, 1, 2, BROWN)
	return img


func _unit_militia() -> Image:
	var img := _soldier(Color(0.45, 0.4, 0.3), LEATHER)
	_rect(img, 12, 2, 1, 11, BROWN)
	_rect(img, 11, 2, 3, 1, SILVER)
	_px(img, 11, 1, SILVER)
	_px(img, 13, 1, SILVER)
	return img


func _unit_spearman() -> Image:
	var img := _soldier(Color(0.3, 0.4, 0.55), STEEL)
	_rect(img, 12, 1, 1, 13, BROWN)
	_rect(img, 12, 1, 1, 2, SILVER)
	_rect(img, 2, 7, 3, 5, RED)
	_rect(img, 6, 2, 4, 2, STEEL.darkened(0.2))
	return img


func _unit_archer() -> Image:
	var img := _soldier(Color(0.3, 0.5, 0.3), Color(0.25, 0.55, 0.3))
	for y in range(3, 13):
		_px(img, 12 + roundi(sin(float(y - 3) / 9.0 * PI) * 2.0), y, BROWN)
	_rect(img, 12, 3, 1, 10, Color(0.9, 0.9, 0.85))
	return img


func _unit_knight() -> Image:
	var img := _skill_bg(Color(0.5, 0.4, 0.2))
	_rect(img, 3, 9, 9, 3, Color(0.55, 0.4, 0.3))
	_rect(img, 11, 7, 3, 3, Color(0.55, 0.4, 0.3))
	_rect(img, 4, 12, 1, 2, BROWN)
	_rect(img, 10, 12, 1, 2, BROWN)
	_rect(img, 6, 3, 4, 3, SILVER)
	_rect(img, 5, 6, 5, 3, STEEL)
	_rect(img, 7, 1, 2, 2, RED)
	return img


func _talent_training_speed() -> Image:
	var img := _talent_skill_cooldown()
	_rect(img, 11, 10, 3, 3, LEATHER)
	return img


func _talent_army_power() -> Image:
	var img := _skill_bg(Color(0.55, 0.3, 0.15))
	for i in 10:
		_px(img, 3 + i, 12 - i, SILVER)
		_px(img, 3 + i, 3 + i, SILVER)
	_rect(img, 3, 11, 2, 2, GOLD)
	_rect(img, 11, 11, 2, 2, GOLD)
	return img


# --- Потребности (16x16) -------------------------------------------------------

func _need_hunger() -> Image:
	var img := _skill_bg(Color(0.7, 0.45, 0.2))
	_draw_drumstick(img)
	return img


func _need_thirst() -> Image:
	var img := _skill_bg(Color(0.2, 0.4, 0.7))
	_draw_drop(img, Color(0.5, 0.8, 1.0))
	return img


func _need_energy() -> Image:
	var img := _skill_bg(Color(0.35, 0.3, 0.6))
	_ellipse(img, 7.0, 8.0, 4.5, 4.5, Color(1.0, 0.92, 0.55))
	_ellipse(img, 9.0, 6.5, 4.0, 4.0, Color(0.35, 0.3, 0.6).darkened(0.2))
	_rect(img, 10, 10, 3, 1, Color.WHITE)
	_px(img, 12, 11, Color.WHITE)
	_rect(img, 10, 12, 3, 1, Color.WHITE)
	return img


# --- Утилиты рисования --------------------------------------------------------

func _new(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.has_area():
		img.fill_rect(r, c)


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	var offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o: Vector2i in offsets:
				var n := Vector2i(x, y) + o
				if n.x < 0 or n.y < 0 or n.x >= img.get_width() or n.y >= img.get_height():
					continue
				if src.get_pixel(n.x, n.y).a > 0.5:
					img.set_pixel(x, y, OUTLINE_COLOR)
					break


func _save(img: Image, relative_path: String, outline := true) -> void:
	if not _force and FileAccess.file_exists(OUT_DIR + relative_path):
		return
	if outline:
		_outline(img)
	var err := img.save_png(OUT_DIR + relative_path)
	if err != OK:
		push_error("Failed to save %s: %s" % [relative_path, error_string(err)])
