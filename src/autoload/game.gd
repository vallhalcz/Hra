extends Node
## Správa map: rychlé přechody (fade 0.18 s), předčítání sousedních map na pozadí.
## Mapy: res://assets/maps/<id>.(tscn|glb|fbx) — id = název souboru.

signal interaction_started(npc)
signal battle_requested(npc)

const START_MAP := "uvod"
const START_SPAWN := "start"
const FADE_TIME := 0.18
const EXTS := [".tscn", ".glb", ".gltf", ".fbx"]

var holder: Node3D
var player: Player
var camera: Hd2dCamera
var current_map: Node3D
var current_id := ""
var busy := false
var _grace_until := 0
var _requested := {}  # id -> path (threaded load běží)
var _fade_rect: ColorRect

func _ready() -> void:
	_setup_input()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

func setup(p_holder: Node3D, p_player: Player, p_camera: Hd2dCamera) -> void:
	holder = p_holder
	player = p_player
	camera = p_camera

func map_path(id: String) -> String:
	for base in ["res://maps/", "res://assets/maps/"]:
		for e in EXTS:
			var p := "%s%s%s" % [base, id, e]
			if ResourceLoader.exists(p):
				return p
	return ""

## Zavolej, když se hráč blíží k exitu — mapa se načte na pozadí a přechod je pak okamžitý.
func preload_map(id: String) -> void:
	if _requested.has(id):
		return
	var p := map_path(id)
	if p != "":
		_requested[id] = p
		ResourceLoader.load_threaded_request(p)

func change_map(id: String, spawn_id := "start", fade := true) -> void:
	if busy:
		return
	var p := map_path(id)
	if p == "":
		push_error("Mapa '%s' neexistuje v res://assets/maps/" % id)
		return
	busy = true
	player.set_physics_process(false)
	if fade:
		await _fade(1.0)
	preload_map(id)
	var scene := ResourceLoader.load_threaded_get(_requested[id]) as PackedScene
	if current_map:
		holder.remove_child(current_map)
		current_map.queue_free()
	current_map = scene.instantiate()
	current_id = id
	holder.add_child(current_map)
	for c in current_map.get_children():  # metadata z importované mapy uvnitř wrapper scény
		for k in c.get_meta_list():
			if not current_map.has_meta(k):
				current_map.set_meta(k, c.get_meta(k))
	_wire_exits()
	_spawn_characters()
	var sp := current_map.find_child("SPAWN_" + spawn_id, true, false) as Node3D
	player.global_position = (sp.global_position if sp else Vector3.ZERO) + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	camera.apply_map(current_map)
	await get_tree().process_frame
	_grace_until = Time.get_ticks_msec() + 600
	player.set_physics_process(true)
	if fade:
		await _fade(0.0)
	busy = false

func _spawn_characters() -> void:
	for m in current_map.find_children("*", "Marker3D", true, false):
		if not m.has_meta("character_id"):
			continue
		var npc := Npc.new()
		if npc.setup(m.get_meta("character_id")):
			current_map.add_child(npc)
			npc.global_position = m.global_position
		else:
			npc.free()

func _wire_exits() -> void:
	for a in current_map.find_children("*", "Area3D", true, false):
		if not a.has_meta("target_map"):
			continue
		a.body_entered.connect(func(b: Node3D) -> void:
			if b == player and Time.get_ticks_msec() > _grace_until:
				change_map(a.get_meta("target_map"), a.get_meta("target_spawn", "start")))
		preload_map(a.get_meta("target_map"))  # sousedy se předčítají hned

func _fade(to: float) -> void:
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", to, FADE_TIME)
	await t.finished

func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E, KEY_ENTER, KEY_SPACE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	InputMap.action_add_event("interact", jb)
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in axes:
		var j := InputEventJoypadMotion.new()
		j.axis = axes[action][0]
		j.axis_value = axes[action][1]
		InputMap.action_add_event(action, j)
