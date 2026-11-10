class_name Npc
extends CharacterBody3D
## Postava ve světě podle definice z tvůrce postav: sprite + animace + role (dialog, obchod, bloudění, nepřítel...).
## Konvence: sprity jsou nakreslené čelem DOPRAVA, doleva se zrcadlí.

var char_id := ""
var def := {}
var sprite: AnimatedSprite3D
var facing := "down"
var home := Vector3.ZERO
var gravity := 20.0
var _target := Vector3.ZERO
var _wait := 0.0
var _patrol_i := 0
var _contact_cd := 0.0

func setup(id: String) -> bool:
	char_id = id
	def = CharacterLoader.load_def(id)
	return not def.is_empty()

func fn(key: String) -> Dictionary:
	return def.get("functions", {}).get(key, {})

func has_fn(key: String) -> bool:
	return def.get("functions", {}).has(key)

func _ready() -> void:
	if def.is_empty():
		return
	name = "NPC_" + char_id
	collision_layer = 4
	collision_mask = 1
	add_to_group("npc")
	if def.get("category", "") in ["enemy", "boss"]:
		add_to_group("enemy")
	home = global_position
	_target = home
	var sp: Dictionary = def.get("sprite", {})
	var ppu := float(sp.get("ppu", 64))
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(sp.get("collision_radius", 0.28))
	cap.height = maxf(cap.radius * 2.0, float(sp.get("frame_h", 64)) / ppu * 0.8)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = CharacterLoader.build_frames(def)
	sprite.pixel_size = 1.0 / ppu * float(sp.get("scale", 1.0))
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.offset.y = float(sp.get("frame_h", 64)) * 0.5 + float(sp.get("pivot_y", 0))
	add_child(sprite)
	_play("idle")

func _physics_process(delta: float) -> void:
	if def.is_empty() or not is_inside_tree():
		return
	_contact_cd = maxf(0.0, _contact_cd - delta)
	var move := _ai(delta)
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if move.length() > 0.05:
		_face(move)
		_play("walk" if _has_anim("walk") else "idle")
	else:
		_play("idle")

func _ai(delta: float) -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var en := fn("enemy")
	if not en.is_empty() and player:
		var d := player.global_position - global_position
		d.y = 0
		var ai: String = en.get("ai", "wander_chase")
		var leash_ok := (global_position - home).length() < float(en.get("leash", 12))
		if ai in ["chase", "wander_chase"] and d.length() < float(en.get("aggro", 5)) and leash_ok:
			if d.length() < 0.8 and _contact_cd <= 0.0:
				_contact_cd = 3.0
				Game.battle_requested.emit(self)
			return d.normalized() * float(en.get("speed", 2.5))
		if ai in ["stationary"]:
			return Vector3.ZERO
	var pt := fn("patrol")
	if not pt.is_empty() and pt.get("points", []).size() > 0:
		var pts: Array = pt.points
		var p: Array = pts[_patrol_i % pts.size()]
		var tgt := home + Vector3(p[0], 0, p[1])
		var dd := tgt - global_position
		dd.y = 0
		if dd.length() < 0.15:
			_patrol_i = (_patrol_i + 1) % pts.size() if pt.get("loop", true) else mini(_patrol_i + 1, pts.size() - 1)
			return Vector3.ZERO
		return dd.normalized() * float(pt.get("speed", 1.5))
	var w := fn("wander")
	if w.is_empty() and en.get("ai", "") in ["wander", "wander_chase"]:
		w = {"radius": 3.0, "speed": float(en.get("speed", 2.5)) * 0.5, "pause": 2.0}
	if not w.is_empty():
		var dd := _target - global_position
		dd.y = 0
		if dd.length() < 0.15:
			_wait -= delta
			if _wait <= 0.0:
				_wait = float(w.get("pause", 2.0)) * randf_range(0.5, 1.5)
				var a := randf() * TAU
				_target = home + Vector3(cos(a), 0, sin(a)) * randf() * float(w.get("radius", 3.0))
			return Vector3.ZERO
		return dd.normalized() * float(w.get("speed", 1.2))
	return Vector3.ZERO

func _has_anim(base: String) -> bool:
	for a in def.get("animations", []):
		if a.name == base:
			return true
	return false

func _face(v: Vector3) -> void:
	var mode := CharacterLoader.dir_mode(def, "idle")
	if mode == "8":
		var names := CharacterLoader.ROWS["8"]
		var ang := atan2(v.x, v.z)  # 0 = dolů (k hráči), + = doprava
		var idx := int(round(ang / (PI / 4.0)))
		var map := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
		facing = map[posmod(idx, 8)]
	elif absf(v.x) > absf(v.z):
		facing = "right" if v.x > 0.0 else "left"
	else:
		facing = "down" if v.z > 0.0 else "up"

func _play(base: String) -> void:
	if not _has_anim(base):
		return
	var mode := CharacterLoader.dir_mode(def, base)
	var an := base
	var flip := facing == "left" or facing == "down_left" or facing == "up_left"
	if mode == "3":
		an = "%s_%s" % [base, "up" if facing.begins_with("up") else ("down" if facing == "down" else "side")]
	elif mode == "4":
		an = "%s_%s" % [base, facing if facing in ["down", "left", "right", "up"] else "down"]
		flip = false
	elif mode == "8":
		an = "%s_%s" % [base, facing]
		flip = false
	sprite.flip_h = flip
	if sprite.animation != an:
		sprite.play(an)

## Stisk E v blízkosti.
func interact() -> void:
	if get_parent() == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		var d := p.global_position - global_position
		_face(d)
		_play("idle")
	Game.interaction_started.emit(self)

func is_interactive() -> bool:
	return has_fn("dialog") or has_fn("merchant") or has_fn("quest") or has_fn("inn") or has_fn("healer") or has_fn("party")

## Další věta dialogu (zatím jen text; UI okno přijde později).
func next_line() -> Dictionary:
	var dl := fn("dialog")
	var lines: Array = dl.get("lines", [])
	if lines.is_empty():
		return {}
	var line: Dictionary = lines.pick_random() if dl.get("mode", "sequence") == "random" else lines[_patrol_i % lines.size()]
	if dl.get("mode", "sequence") != "random":
		_patrol_i += 1
	var who := String(line.get("speaker", ""))
	return {"speaker": who if who != "" else String(def.get("name", "")), "text": line.get("text", "")}
