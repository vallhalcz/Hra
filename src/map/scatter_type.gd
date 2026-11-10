@tool
class_name ScatterType
extends Resource
## Typ scatter spritu. Soubor: res://data/scatter/<typ>.tres
## V Blenderu pojmenuj plochu "SCATTER_<typ>" a sprity se na ní rozsypou při importu.

@export var texture: Texture2D                       ## sprite (velikost v metrech = px / 64)
@export_range(0.01, 50.0) var density := 4.0         ## kusů na m²
@export var scale_range := Vector2(0.8, 1.2)
@export_range(0.0, 1.0) var min_normal_y := 0.75     ## na svazích strmějších než tohle se nesází
@export var tint_a := Color(1, 1, 1)                 ## náhodný odstín mezi A a B
@export var tint_b := Color(0.85, 1.0, 0.8)
@export var wind_strength := 0.05
@export var y_offset := 0.0
@export var seed := 0
@export_enum("none", "G0", "G1", "G2", "G3") var auto_layer := "none"  ## automaticky pokrývá vrstvu terénu (např. trávu na G0)
