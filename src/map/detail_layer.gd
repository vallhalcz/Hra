@tool
class_name DetailLayer
extends MultiMeshInstance3D
## Ručně malované detaily (kytky, kameny, trs trávy...). Data jsou uložená ve scéně (points/scales),
## malují se štětcem v editoru (dock "Hra" ve spodním panelu). Běží i ve hře.

const SPRITE_SHADER := "res://src/shaders/sprite_billboard.gdshader"
const PPU := 64.0

@export var scatter_type: ScatterType:
	set(v):
		scatter_type = v
		_rebuild()
@export var points := PackedVector3Array():
	set(v):
		points = v
		_rebuild()
@export var scales := PackedFloat32Array()
@export var tints := PackedFloat32Array()  ## 0..1 mezi tint_a a tint_b

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	var cfg := scatter_type if scatter_type else ScatterType.new()
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in points.size():
		var s := scales[i] if i < scales.size() else 1.0
		xf.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), points[i]))
		cols.append(cfg.tint_a.lerp(cfg.tint_b, tints[i] if i < tints.size() else 0.0))
	multimesh = make_multimesh(cfg, xf, cols)

static func make_multimesh(cfg: ScatterType, xf: Array[Transform3D], cols: Array[Color]) -> MultiMesh:
	var tex: Texture2D = cfg.texture if cfg.texture else placeholder()
	var quad := QuadMesh.new()
	var size := Vector2(tex.get_width(), tex.get_height()) / PPU
	quad.size = size
	quad.center_offset = Vector3(0, size.y * 0.5, 0)  # pivot dole uprostřed
	var sm := ShaderMaterial.new()
	sm.shader = load(SPRITE_SHADER)
	sm.set_shader_parameter("albedo_tex", tex)
	sm.set_shader_parameter("wind_strength", cfg.wind_strength)
	quad.material = sm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	return mm

static func make_instance(cfg: ScatterType, xf: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = make_multimesh(cfg, xf, cols)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

static func placeholder() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 14):
		var h := 6 + (x * 7) % 9
		for y in range(16 - h, 16):
			img.set_pixel(x, y, Color(0.35 + 0.02 * (y % 5), 0.65, 0.25))
	return ImageTexture.create_from_image(img)
