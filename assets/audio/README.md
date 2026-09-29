# Звуки и музыка

Сейчас здесь **временные** звуки: их синтезирует `tools/generate_audio.py` в ретро-стиле 8/16 бит.
Любой файл можно заменить своим. Положите файл с тем же именем: подходят `.ogg` (лучше всего), `.mp3` и `.wav`.
Удалённый файл просто не звучит, игра не падает.

- **Варианты звука:** `hit.ogg`, `hit_2.ogg`, `hit_3.ogg`… Игра выбирает случайный, чтобы частые звуки не повторялись один в один (до 4 вариантов).
- **Свой звук умения:** `sfx/skill_<id умения>.ogg`, например `skill_fireball.ogg`. Он важнее звука группы.
- **Музыка** играет по кругу, поэтому начало и конец трека должны стыковаться без паузы.
- **Громкость** каждого звука, минимальный интервал повторов и разброс высоты тона задаются в `scripts/autoload/sound.gd` (`SOUNDS`).
- **Пересоздать временные звуки:** `python tools/generate_audio.py`. С флагом `--keep` уже существующие (например, ваши) файлы не трогаются. Нужны `pip install numpy scipy soundfile`.

Рекомендуемый формат: OGG Vorbis, моно для эффектов, 32–44 кГц. Эффекты — без тишины в начале, пик около −1 дБ.
Громкость между звуками выравнивает игра.

## Когда что звучит

Три вида звуков, у каждого свой ползунок в настройках:
- **Бой.** По умолчанию слышен, только пока курсор над полосой боя или открыто окно. В трее молчит.
- **Интерфейс.** Звучит, только когда игрок сам что-то делает.
- **Уведомления.** Звучат всегда; в трее — если включено «Уведомления, пока игра в трее».

### Интерфейс (`sfx/`)

| Файл | Когда | Промпт для генератора звуков (ElevenLabs Sound Effects и т.п.) |
|---|---|---|
| click | любая кнопка | soft short UI click, wooden fantasy game menu, very short |
| tab | переключатель, вкладка | light UI tick, slightly higher than a click, fantasy menu |
| panel_open / panel_close | открыть / закрыть окно | soft paper whoosh opening a fantasy book / closing it, short |
| equip | надеть или снять предмет | armor piece equipped, light metal clank with leather, short |
| sell | продажа предмета | handful of gold coins dropping into a pile, fantasy RPG |
| upgrade_ok | заточка удалась | blacksmith anvil ding with magical sparkle, success |
| upgrade_fail | заточка не удалась | dull metal clunk and a short descending fail tone |
| merge | слияние предметов, сброс талантов | magical swirl rising into a sparkle, item transmutation |
| talent | изучен талант | soft magical chime, skill point spent |
| keystone | изучен ключевой талант | deep powerful magical chord with low boom, epic unlock |
| build | начать стройку | three hammer knocks on wood, medieval construction |
| recruit | нанять отряд | two war drum hits and a short horn, recruit soldiers |
| claim | забрать награду (задания, достижения) | coins and a bright two-note reward chime |
| donate | взнос в казну гильдии или замка | coins dropped into a wooden chest |
| error | действие недоступно | soft low double buzz, UI denied, not harsh |
| prestige | перерождение | epic magical rising swell into a huge bright chord, rebirth, 4 seconds |

### Бой

| Файл | Когда | Промпт |
|---|---|---|
| attack_warrior | удар воина | sword swing whoosh, short, no impact |
| attack_mage | атака мага | small magic bolt cast, short sparkly zap |
| attack_archer | выстрел лучника | bow string release twang with arrow whoosh |
| hit (+ _2, _3) | попадание по монстру | punchy cartoon impact thud on a creature, short |
| hit_crit | критический удар | heavy critical hit impact with sharp crack, short |
| hero_hurt | героя ранили | short pained grunt-like hit on hero, retro game |
| monster_die | монстр погиб | small creature poof, defeated monster vanishes |
| gold | золото за убийство (очень часто, тихо) | single retro coin pickup blip |
| loot | выпал обычный предмет | item drop tick with a tiny sparkle |
| elite | появился элитный монстр | ominous low dissonant stab |
| boss_slam | удар босса по земле | huge ground slam boom with debris |
| boss_shield | босс поставил щит | magical shield activation shimmer rising |
| wave_clear | волна пройдена | soft short three-note ascending chime |
| skill_fire | огненные умения | fire burst whoosh with crackling flames |
| skill_frost | ледяная нова | ice crystals forming, glassy shimmer |
| skill_lightning | цепная молния | electric zap crackle, lightning chain |
| skill_arcane | сила тайной магии | arcane energy rising, phaser-like hum |
| skill_slash | удары воина (рассечение, вихрь, казнь…) | double heavy sword slash whoosh with metallic ring |
| skill_heavy | землетрясение, удар щитом | heavy ground impact with rumble |
| skill_shout | боевой клич, последний рубеж | short war horn blast, battle cry |
| skill_arrows | залпы лучника | volley of several arrows whooshing |
| skill_poison | ядовитая стрела | bubbling poison, acid hiss |
| skill_snare | ловушка | whip crack and rope snare tightening |
| skill_buff | глаз орла, ярость охотника | rising sparkling buff arpeggio |
| skill_shield | магический щит | protective magic bubble forming, soft hum |
| skill_drain | похищение жизни | dark life-drain swell, reverse whoosh |

### Уведомления

| Файл | Когда | Промпт |
|---|---|---|
| level_up | новый уровень | classic retro level-up fanfare, bright, 1 second |
| loot_rare | редкий предмет | two bright magical bell notes, rare item |
| loot_epic | эпический предмет | four ascending magical bells, epic item |
| loot_legendary | легендарный предмет | short triumphant fanfare with shimmering bells, legendary drop |
| treasure | найдено сокровище | magical harp glissando with a bell, treasure found |
| boss_appear | волна с боссом | dramatic low horn with two big war drums, boss appears |
| boss_defeated | босс побеждён | short victory fanfare, retro RPG |
| hero_died | герой пал | sad descending four-note melody, game over but gentle |
| construction_done | стройка в замке завершена | two pleasant bell tones, task complete |
| units_ready | отряд обучен | short two-note horn call |
| attack_alarm | на замок/зону идёт враг | medieval alarm bell rung three times |
| report | пришёл отчёт (набег, потеря зоны) | soft notification pop |
| guild_invite | приглашение в гильдию | letter arrival, three gentle ascending notes |
| chat | новое сообщение в чате гильдии (не чаще раза в 15 с) | tiny soft double pop |
| quest_done | задание или достижение выполнено | short cheerful quest complete jingle |
| rest_start / rest_end | герой ушёл отдыхать / вернулся | soft sleepy descending two notes / gentle ascending two notes |

### Музыка (`music/`)

Каждый трек идёт по кругу, громкость по умолчанию — 35%. Смена трека плавная. Во время отдыха музыка тише.

| Файл | Когда | Промпт для генератора музыки (Suno и т.п.) |
|---|---|---|
| forest | биом «Лес», волны 1–9 | calm cheerful fantasy forest, flute and plucked strings, light percussion, 16-bit RPG, seamless loop, instrumental, 90 bpm |
| graveyard | «Кладбище», 11–19 | eerie but cozy graveyard, music box and soft organ, ticking clock, minor key, 16-bit RPG, seamless loop, instrumental, 75 bpm |
| mountains | «Горы», 21–29 | heroic mountain journey, french horn and strings, marching drums, dorian mode, 16-bit RPG, seamless loop, instrumental, 100 bpm |
| cursed | «Проклятые земли», 31+ | dark cursed lands, tense pulsing bass, dissonant bells, heartbeat drum, phrygian, 16-bit RPG, seamless loop, instrumental, 85 bpm |
| boss | каждая 10-я волна (босс) | intense boss battle, driving bass and drums, fast chiptune lead, harmonic minor, seamless loop, instrumental, 140 bpm |
| menu | экран создания героя | gentle calm fantasy menu theme, music box and warm pad, no drums, seamless loop, instrumental, 70 bpm |

Для фоновой игры лучше спокойные треки без резких акцентов, 1–3 минуты. Громкие места раздражают, если слушать часами.
