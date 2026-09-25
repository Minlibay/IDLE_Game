class_name SkillCaster
extends Node
## Компонент героя: умения класса, перезарядки, автоприменение и ручное применение.
## Автоприменение включается переключателем «Авто» (GameState.auto_cast).

signal skill_cast(skill: SkillData)

var hero: Hero
## Умения класса, отсортированные по уровню открытия (порядок = клавиши 1, 2, 3...).
var skills: Array[SkillData] = []
var _cooldowns: Dictionary[String, float] = {}
## Полная длительность последней перезарядки (с учётом талантов) — для индикатора.
var _cooldown_totals: Dictionary[String, float] = {}


func setup(p_hero: Hero, class_data: CharacterClass) -> void:
	hero = p_hero
	skills.clear()
	for skill in class_data.skills:
		if skill == null or skill.effect == null:
			push_warning("Class '%s' has a skill without effect, skipped" % class_data.id)
			continue
		skills.append(skill)
	skills.sort_custom(func(a: SkillData, b: SkillData) -> bool: return a.unlock_level < b.unlock_level)
	_cooldowns.clear()
	for skill in skills:
		_cooldowns[skill.id] = 0.0


func _process(delta: float) -> void:
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	if hero == null or not GameState.auto_cast or not hero.is_alive() or hero.is_resting:
		return
	for skill in skills:
		if is_ready(skill) and skill.effect.should_auto_cast(hero):
			try_cast(skill)
			return


func is_unlocked(skill: SkillData) -> bool:
	return GameState.level >= skill.unlock_level


func is_ready(skill: SkillData) -> bool:
	return hero != null and hero.is_alive() and not hero.is_resting and is_unlocked(skill) and get_cooldown_left(skill) <= 0.0


func get_cooldown_left(skill: SkillData) -> float:
	return _cooldowns.get(skill.id, 0.0)


func get_cooldown_ratio(skill: SkillData) -> float:
	var total: float = _cooldown_totals.get(skill.id, skill.cooldown)
	return get_cooldown_left(skill) / total if total > 0.0 else 0.0


func try_cast(skill: SkillData) -> bool:
	if not is_ready(skill):
		return false
	var target := hero.find_target()
	if skill.effect.requires_target() and target == null:
		return false
	if skill.animation != &"":
		hero.play_action(skill.animation)
	skill.effect.execute(hero, target, GameState.get_skill_power(skill.id))
	var cooldown := skill.cooldown * GameState.get_skill_cooldown_multiplier(skill.id)
	_cooldowns[skill.id] = cooldown
	_cooldown_totals[skill.id] = cooldown
	skill_cast.emit(skill)
	return true


func try_cast_index(index: int) -> bool:
	if index < 0 or index >= skills.size():
		return false
	return try_cast(skills[index])


func reset_cooldowns() -> void:
	for id in _cooldowns:
		_cooldowns[id] = 0.0
