"""Генератор умений 30–80 уровней (data/skills/*.tres) и их подключения к классам.

Умения удобнее описывать здесь таблицей, чем править девять .tres на класс руками:
  python tools/skills_catalog.py
Скрипт перезаписывает только перечисленные здесь умения, остальные .tres не трогает,
и обновляет список skills у классов (data/classes/<класс>.tres) и уровни открытия первых трёх.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EFFECTS = {
    "strike": "res://scripts/skills/strike_effect.gd",
    "area": "res://scripts/skills/area_effect.gd",
    "buff": "res://scripts/skills/buff_effect.gd",
    "multi": "res://scripts/skills/multi_shot_effect.gd",
    "chain": "res://scripts/skills/chain_effect.gd",
}
BUFF_STATS = {"damage": 0, "attack_speed": 1, "armor": 2, "crit_chance": 3}

# Первые три умения каждого класса: теперь 1-й, 10-й и 20-й уровень.
BASE_LEVELS = {
    "warrior": {"power_strike": 1, "whirlwind": 10, "war_cry": 20},
    "archer": {"aimed_shot": 1, "multishot": 10, "hunter_fury": 20},
    "mage": {"fireball": 1, "meteor": 10, "arcane_shield": 20},
}

SKILLS = {
    "warrior": [
        dict(id="cleave", name="Рассекающий удар", level=30, cd=9, color=(1.0, 0.55, 0.3), anim="power_strike",
             desc="180% урона цели и 100% врагам вокруг неё.",
             effect="strike", fields=dict(damage_multiplier=1.8, splash_radius=2.5, splash_multiplier=1.0,
                                          splash_color=(1.0, 0.55, 0.3))),
        dict(id="shield_bash", name="Удар щитом", level=40, cd=12, color=(0.7, 0.75, 0.9), anim="power_strike",
             desc="150% урона и оглушение цели на 2,5 с (боссы — вдвое короче).",
             effect="strike", fields=dict(damage_multiplier=1.5, stun_duration=2.5, stun_color=(0.75, 0.75, 0.8))),
        dict(id="rend", name="Кровопускание", level=50, cd=10, color=(0.9, 0.2, 0.25), anim="attack",
             desc="120% урона и кровотечение: ещё 400% урона за 6 с.",
             effect="strike", fields=dict(damage_multiplier=1.2, dot_multiplier=4.0, dot_duration=6.0, dot_color=(1.0, 0.3, 0.3))),
        dict(id="earthquake", name="Землетрясение", level=60, cd=16, color=(0.8, 0.6, 0.35), anim="whirlwind",
             desc="220% урона всем врагам вокруг, оглушение на 1,5 с и отбрасывание.",
             effect="area", fields=dict(damage_multiplier=2.2, radius=4.5, color=(0.8, 0.6, 0.35),
                                        stun_duration=1.5, stun_color=(0.8, 0.75, 0.65), knockback=1.5)),
        dict(id="last_stand", name="Непоколебимость", level=70, cd=30, color=(1.0, 0.85, 0.4), anim="war_cry",
             desc="Лечит 25% здоровья и даёт +80 брони на 8 с. Сама срабатывает, когда здоровья меньше половины.",
             effect="buff", fields=dict(stat="armor", value=80.0, duration=8.0, heal_percent=0.25,
                                        auto_cast_below_hp=0.5, color=(1.0, 0.85, 0.4))),
        dict(id="execute", name="Казнь", level=80, cd=14, color=(0.85, 0.15, 0.15), anim="power_strike",
             desc="300% урона; по врагу с запасом здоровья меньше 30% — втрое больше.",
             effect="strike", fields=dict(damage_multiplier=3.0, execute_below=0.3, execute_multiplier=3.0)),
    ],
    "archer": [
        dict(id="poison_arrow", name="Ядовитая стрела", level=30, cd=8, color=(0.5, 0.95, 0.4),
             desc="150% урона и яд: ещё 300% урона за 6 с.",
             effect="strike", fields=dict(damage_multiplier=1.5, projectile_scale=1.4, tint=(0.6, 1.0, 0.4),
                                          dot_multiplier=3.0, dot_duration=6.0, dot_color=(0.6, 1.0, 0.4))),
        dict(id="snare", name="Ловчая сеть", level=40, cd=14, color=(0.8, 0.7, 0.45),
             desc="Сеть вокруг цели: 60% урона и обездвиживание врагов на 2 с.",
             effect="area", fields=dict(damage_multiplier=0.6, radius=2.5, center_on_target=True, color=(0.8, 0.7, 0.45),
                                        stun_duration=2.0, stun_color=(0.85, 0.8, 0.6))),
        dict(id="piercing_shot", name="Пробивающий выстрел", level=50, cd=10, color=(0.85, 0.9, 1.0),
             desc="Стрела пробивает насквозь: 220% урона всем врагам в линию.",
             effect="area", fields=dict(damage_multiplier=2.2, radius=14.0, line=True, color=(0.85, 0.9, 1.0))),
        dict(id="arrow_rain", name="Град стрел", level=60, cd=15, color=(0.95, 0.8, 0.5),
             desc="250% урона всем врагам в большой области вокруг цели.",
             effect="area", fields=dict(damage_multiplier=2.5, radius=4.0, center_on_target=True, color=(0.95, 0.8, 0.5))),
        dict(id="eagle_eye", name="Орлиный глаз", level=70, cd=25, color=(1.0, 0.85, 0.3),
             desc="+30% шанса крита на 8 с.",
             effect="buff", fields=dict(stat="crit_chance", value=0.3, duration=8.0, color=(1.0, 0.85, 0.3))),
        dict(id="deadly_volley", name="Смертельный залп", level=80, cd=18, color=(1.0, 0.4, 0.35),
             desc="10 стрел по ближайшим врагам, каждая — гарантированный крит на 120% урона.",
             effect="multi", fields=dict(projectile_count=10, damage_multiplier=1.2, force_crit=True, tint=(1.0, 0.6, 0.5))),
    ],
    "mage": [
        dict(id="chain_lightning", name="Цепная молния", level=30, cd=9, color=(0.55, 0.8, 1.0),
             desc="Молния бьёт цель на 180% и перескакивает ещё на 4 врагов, каждый раз на 15% слабее.",
             effect="chain", fields=dict(damage_multiplier=1.8, jumps=5, falloff=0.85, tint=(0.6, 0.85, 1.0))),
        dict(id="frost_nova", name="Кольцо льда", level=40, cd=15, color=(0.6, 0.9, 1.0),
             desc="100% урона всем врагам вокруг и заморозка на 3 с.",
             effect="area", fields=dict(damage_multiplier=1.0, radius=3.5, color=(0.6, 0.9, 1.0),
                                        stun_duration=3.0, stun_color=(0.55, 0.8, 1.2))),
        dict(id="ignite", name="Поджог", level=50, cd=12, color=(1.0, 0.5, 0.2),
             desc="Поджигает врагов вокруг цели: 350% урона за 6 с.",
             effect="area", fields=dict(damage_multiplier=0.5, radius=3.0, center_on_target=True, color=(1.0, 0.5, 0.2),
                                        dot_multiplier=3.5, dot_duration=6.0, dot_color=(1.0, 0.55, 0.2))),
        dict(id="arcane_power", name="Чародейская мощь", level=60, cd=25, color=(0.75, 0.5, 1.0),
             desc="+80% урона на 8 с.",
             effect="buff", fields=dict(stat="damage", value=0.8, duration=8.0, color=(0.75, 0.5, 1.0))),
        dict(id="drain_life", name="Вытягивание жизни", level=70, cd=12, color=(0.8, 0.25, 0.5),
             desc="250% урона цели, герой лечится на половину нанесённого урона.",
             effect="strike", fields=dict(damage_multiplier=2.5, heal_ratio=0.5, projectile_scale=1.3, tint=(0.9, 0.3, 0.55))),
        dict(id="armageddon", name="Армагеддон", level=80, cd=30, color=(1.0, 0.35, 0.1),
             desc="600% урона всем врагам в огромной области вокруг цели и поджог: ещё 300% за 6 с.",
             effect="area", fields=dict(damage_multiplier=6.0, radius=6.0, center_on_target=True, color=(1.0, 0.35, 0.1),
                                        dot_multiplier=3.0, dot_duration=6.0, dot_color=(1.0, 0.45, 0.15))),
    ],
}


def value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, tuple):
        return "Color(%s, %s, %s, 1)" % v
    if isinstance(v, float):
        return repr(v)
    return str(v)


def write_skill(class_id, skill):
    fields = dict(skill["fields"])
    if skill["effect"] == "buff":
        fields["stat"] = BUFF_STATS[fields["stat"]]
    effect_lines = "\n".join("%s = %s" % (k, value(v)) for k, v in fields.items())
    anim = '\nanimation = &"%s"' % skill["anim"] if skill.get("anim") else ""
    text = f'''[gd_resource type="Resource" script_class="SkillData" format=3]

[ext_resource type="Script" path="res://scripts/data/skill_data.gd" id="1"]
[ext_resource type="Script" path="{EFFECTS[skill["effect"]]}" id="2"]
[ext_resource type="Texture2D" path="res://assets/sprites/skills/{skill["id"]}.png" id="3"]

[sub_resource type="Resource" id="Resource_effect"]
script = ExtResource("2")
{effect_lines}

[resource]
script = ExtResource("1")
id = "{skill["id"]}"
display_name = "{skill["name"]}"
description = "{skill["desc"]}"
icon = ExtResource("3")
color = {value(skill["color"])}
cooldown = {float(skill["cd"])}
unlock_level = {skill["level"]}
effect = SubResource("Resource_effect"){anim}
'''
    path = os.path.join(ROOT, "data", "skills", "%s_%s.tres" % (class_id, skill["id"]))
    open(path, "w", encoding="utf8").write(text)


def update_class(class_id):
    path = os.path.join(ROOT, "data", "classes", class_id + ".tres")
    s = open(path, encoding="utf8").read()
    # Существующие ссылки на умения и их id ресурсов.
    refs = re.findall(r'\[ext_resource type="Resource" path="res://data/skills/([a-z_]+)\.tres" id="(\d+)"\]', s)
    known = {name for name, _ in refs}
    next_id = max(int(i) for i in re.findall(r' id="(\d+)"\]', s)) + 1
    ids = [rid for _, rid in refs]
    for skill in SKILLS[class_id]:
        name = "%s_%s" % (class_id, skill["id"])
        if name in known:
            continue
        line = '[ext_resource type="Resource" path="res://data/skills/%s.tres" id="%d"]' % (name, next_id)
        last = list(re.finditer(r'\[ext_resource type="Resource" path="res://data/skills/[a-z_]+\.tres" id="\d+"\]\n', s))[-1]
        s = s[:last.end()] + line + "\n" + s[last.end():]
        ids.append(str(next_id))
        next_id += 1
    array_type = re.search(r'skills = Array\[ExtResource\("(\d+)"\)\]', s).group(1)
    s = re.sub(r'skills = Array\[ExtResource\("\d+"\)\]\(\[[^\]]*\]\)',
               'skills = Array[ExtResource("%s")]([%s])' % (array_type, ", ".join('ExtResource("%s")' % i for i in ids)), s)
    open(path, "w", encoding="utf8").write(s)


def update_base_levels(class_id):
    for skill_id, level in BASE_LEVELS[class_id].items():
        path = os.path.join(ROOT, "data", "skills", "%s_%s.tres" % (class_id, skill_id))
        s = open(path, encoding="utf8").read()
        s = re.sub(r"unlock_level = \d+", "unlock_level = %d" % level, s)
        open(path, "w", encoding="utf8").write(s)


for class_id, skills in SKILLS.items():
    for skill in skills:
        write_skill(class_id, skill)
    update_class(class_id)
    update_base_levels(class_id)
print("skills:", sum(len(v) for v in SKILLS.values()))
