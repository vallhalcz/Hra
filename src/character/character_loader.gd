class_name CharacterLoader
extends RefCounted
## Načte postavu vytvořenou v tools/character_creator.html (res://characters/<id>/character.json + PNG).

const DIR := "res://characters/"
const ROWS := {
	"1": [], "3": ["down", "side", "up"], "4": ["down", "left", "right", "up"],
	"8": ["down", "down_left", "left", "up_left", "up", "up_right", "right", "down_right"],
}

static func load_def(id: String) -> Dictionary:
	var p := DIR + id + "/character.json"
	if not FileAccess.file_exists(p):
		push_error("Postava '%s' nenalezena (%s)" % [id, p])
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

## Animace v SpriteFrames: bez směrů "walk", se směry "walk_down", "walk_side"...
static func build_frames(def: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for a in def.get("animations", []):
		var tex := load(DIR + String(def.id) + "/" + String(a.file)) as Texture2D
		if tex == null:
			push_warning("Chybí obrázek animace %s/%s" % [def.id, a.file])
			continue
		var fw := int(a.frame_w)
		var fh := int(a.frame_h)
		var n := int(a.frames)
		var cols := maxi(1, int(a.get("columns", n)))
		var rows: Array = ROWS.get(str(a.get("directions", "1")), [])
		for r in maxi(1, rows.size()):
			var an: String = String(a.name) if rows.is_empty() else "%s_%s" % [a.name, rows[r]]
			sf.add_animation(an)
			sf.set_animation_speed(an, float(a.fps))
			sf.set_animation_loop(an, bool(a.loop))
			for f in n:
				var at := AtlasTexture.new()
				at.atlas = tex
				var col := (f % cols) if rows.is_empty() else f
				var row := floori(float(f) / cols) if rows.is_empty() else r
				at.region = Rect2(col * fw, row * fh, fw, fh)
				sf.add_frame(an, at)
	return sf

## Režim směrů dané animace ("1", "3", "4", "8").
static func dir_mode(def: Dictionary, anim: String) -> String:
	for a in def.get("animations", []):
		if a.name == anim:
			return str(a.get("directions", "1"))
	return "1"
