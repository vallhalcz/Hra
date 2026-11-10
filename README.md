# Hra – HD-2D (Octopath styl) v Godotu 4.7

Malé 3D scény z Blenderu + 2D billboard sprity, pevná kamera, rychlé přechody mezi mapami.

## Workflow
1. V Blenderu vymodeluj mapu (1 m = 1 jednotka, sprite postavy 64 px = 1 m) a exportuj **glTF (.glb)** do `assets/maps/<id>.glb` (FBX funguje taky).
2. Godot při importu sám zpracuje mapu (plugin `addons/hra_tools`, zapnutý v project.godot) – žádné ruční nastavování.
3. Spusť hru: `src/main.tscn`. Start = mapa `uvod`, spawn `SPAWN_start`.

## Konvence názvů v Blenderu (`.001` se ignoruje)
| Název | Co se stane |
|---|---|
| `Terrain*` | terénní shader + kolize. Materiály ploch `G0..G3` = vrstvy (tráva…), `Cliff` = útes. Přechody se vyhladí automaticky. Pokud máš vertex color (R,G,B,A = G0..G3), použije se místo toho. |
| `SOLID_*` | viditelný objekt s kolizí |
| `COL_*` | jen neviditelná kolize |
| `SCATTER_<typ>` | plocha, na které se rozsypou sprity (tráva, kameny) podle `data/scatter/<typ>.tres` |
| `SPAWN_<id>` | Empty – kde se objeví hráč |
| `EXIT_<mapa>__<spawn>` | Empty, velikost = scale – přechod do mapy |
| `Sprite_*`, `REF_*` | reference, při importu se smažou |
| Camera | úhel + FOV se převezmou do hry |

## Scatter typ
`data/scatter/<typ>.tres` → nový Resource `ScatterType`: textura (px/64 = metry), hustota na m², velikost, odstín, vítr. Bez souboru se použije zelený placeholder.

## Textury terénu
`data/materials/terrain.tres` → doplň `tex0..tex3`, `tex_cliff`, uprav `tint*`, `edge_softness`, `edge_noise`, makro variaci.

## Struktura
- `src/autoload/game.gd` – přechody map (fade 0.18 s + předčítání sousedů na pozadí)
- `src/camera/hd2d_camera.gd` – pevná kamera + tilt-shift DoF
- `src/map/map_builder.gd` – import mapy z Blenderu
- `src/shaders/` – terén a billboard sprity
