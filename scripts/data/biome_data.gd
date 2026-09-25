class_name BiomeData
extends Resource
## Биом — набор монстров на 10 волн со своим боссом: лес (1–10), кладбище (11–20), горы (21–30)…
## После последнего биома всё идёт по кругу — монстры с каждым кругом сильнее (рост за волну).
## Новый биом = новый .tres в data/biomes/ + монстры с biome = его id.

@export var id := ""
@export var display_name := ""
## Порядок биомов по волнам.
@export var order := 0
## Цвет названия биома в интерфейсе.
@export var color := Color.WHITE
## Земля под ногами (полоса, повторяется по ширине). Пусто — обычная трава.
@export var ground_texture: Texture2D
