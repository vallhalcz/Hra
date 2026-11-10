class_name Hd2dCamera
extends Camera3D
## Pevná kamera jako v Octopath: žádné otáčení, jen sleduje hráče.
## Pohled (úhel, vzdálenost, FOV) se bere z kamery v Blenderu (metadata mapy).
## Tilt-shift efekt = DoF (rozostření blízko a daleko od ohniskové vzdálenosti).

@export var target: Node3D
@export var follow_speed := 8.0
@export var edge_margin := Vector2(6.0, 4.0)  ## kolik metrů od okraje mapy se focus zastaví (X, Z)
@export var dof_range := 9.0
@export var dof_transition := 10.0

var offset := Vector3(0, 23.1, 27.6)
var bounds := AABB()
var has_bounds := false
var _focus := Vector3.ZERO

func _ready() -> void:
	attributes = CameraAttributesPractical.new()
	attributes.dof_blur_amount = 0.08
	look_at_from_position(offset, Vector3.ZERO)

func apply_map(map: Node) -> void:
	offset = map.get_meta("cam_offset", offset)
	fov = map.get_meta("cam_fov", fov)
	has_bounds = map.has_meta("bounds")
	if has_bounds:
		bounds = map.get_meta("bounds")
	var focus_dist := offset.length()
	var a: CameraAttributesPractical = attributes
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = focus_dist + dof_range
	a.dof_blur_far_transition = dof_transition
	a.dof_blur_near_enabled = true
	a.dof_blur_near_distance = maxf(focus_dist - dof_range, 0.1)
	a.dof_blur_near_transition = dof_transition * 0.6
	snap()

func snap() -> void:
	if target:
		_focus = _clamped(target.global_position)
		_place()

func _process(delta: float) -> void:
	if not target:
		return
	_focus = _focus.lerp(_clamped(target.global_position), 1.0 - exp(-follow_speed * delta))
	_place()

func _clamped(p: Vector3) -> Vector3:
	if has_bounds:
		var lo := bounds.position
		var hi := bounds.end
		p.x = clampf(p.x, lo.x + minf(edge_margin.x, bounds.size.x * 0.5), hi.x - minf(edge_margin.x, bounds.size.x * 0.5))
		p.z = clampf(p.z, lo.z + minf(edge_margin.y, bounds.size.z * 0.5), hi.z - minf(edge_margin.y, bounds.size.z * 0.5))
	return p

func _place() -> void:
	global_position = _focus + offset
