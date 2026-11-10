@tool
class_name MapBuilder
extends RefCounted
## Zpracuje scénu z Blenderu při importu (volá addons/hra_tools/plugin.gd pro res://assets/maps/*).
##
## Konvence názvů objektů v Blenderu (suffix .001 apod. se ignoruje):
##   Terrain*            terén: shader + kolize + vyhlazené váhy vrstev z materiálů G0..G3 (Cliff = útes)
##   SOLID_*             viditelný objekt s kolizí (trimesh)
##   COL_*               pouze neviditelná kolize
##   SCATTER_<typ>       plocha, na které se rozsype sprite typu <typ> (data/scatter/<typ>.tres)
##   SPAWN_<id>          Empty = místo, kde se objeví hráč
##   EXIT_<mapa>__<id>   Empty (velikost = scale) = přechod do mapy <mapa> na SPAWN_<id>
##   Sprite_* / REF_*    pomocné reference, při importu se smažou
## Kamera z Blenderu se uloží jako metadata (pohled + FOV) a smaže.

const TERRAIN_MAT := "res://data/materials/terrain.tres"
const SCATTER_DIR := "res://data/scatter/"
const SPRITE_SHADER := "res://src/shaders/sprite_billboard.gdshader"
const PPU := 64.0
const MAX_INSTANCES := 30000

static func build(root: Node) -> void:
	var nodes: Array[Node] = []
	_collect(root, nodes)
	var bounds := AABB()
	var has_bounds := false
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var nm := String(n.name)
		if nm.begins_with("Sprite_") or nm.begins_with("REF_"):
			n.get_parent().remove_child(n)
			n.free()
		elif n is Camera3D:
			_read_camera(root, n)
			n.get_parent().remove_child(n)
			n.free()
		elif n is DirectionalLight3D:
			n.shadow_enabled = true
		elif _is_mesh(n):
			if nm.begins_with("Terrain"):
				var bb := _build_terrain(root, n)
				bounds = bb if not has_bounds else bounds.merge(bb)
				has_bounds = true
			elif nm.begins_with("SOLID_"):
				_add_body(root, n, _surfaces(n))
			elif nm.begins_with("COL_"):
				var b := _add_body(root, n, _surfaces(n))
				_swap(root, n, b)
			elif nm.begins_with("SCATTER_"):
				_bake_scatter(root, n)
		elif n.get_class() == "Node3D":
			if nm.begins_with("SPAWN_"):
				_swap(root, n, Marker3D.new())
			elif nm.begins_with("EXIT_"):
				_build_exit(root, n)
	if has_bounds:
		root.set_meta("bounds", bounds)

# ---------- pomocné ----------

static func _collect(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)

static func _is_mesh(n: Node) -> bool:
	return n is MeshInstance3D or n is ImporterMeshInstance3D

static func _clean(nm: String) -> String:
	var r := RegEx.new()
	r.compile("[_.]\\d{3}$")
	return r.sub(nm, "")

## Povrchy meshe jako pole slovníků {arrays, mat, name, prim} (funguje pro MeshInstance3D i ImporterMeshInstance3D).
static func _surfaces(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		for i in m.get_surface_count():
			out.append({"arrays": m.surface_get_arrays(i), "mat": m.surface_get_material(i),
				"name": (m as ArrayMesh).surface_get_name(i) if m is ArrayMesh else "", "prim": Mesh.PRIMITIVE_TRIANGLES})
	else:
		var im: ImporterMesh = n.mesh
		for i in im.get_surface_count():
			out.append({"arrays": im.get_surface_arrays(i), "mat": im.get_surface_material(i),
				"name": im.get_surface_name(i), "prim": im.get_surface_primitive_type(i)})
	return out

static func _set_surfaces(n: Node, surfs: Array) -> void:
	if n is MeshInstance3D:
		var am := ArrayMesh.new()
		for s in surfs:
			am.add_surface_from_arrays(s.prim, s.arrays)
			var i := am.get_surface_count() - 1
			am.surface_set_material(i, s.mat)
			am.surface_set_name(i, s.name)
		n.mesh = am
	else:
		var im := ImporterMesh.new()
		for s in surfs:
			im.add_surface(s.prim, s.arrays, [], {}, s.mat, s.name)
		n.mesh = im

static func _trimesh(surfs: Array) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	for s in surfs:
		var v: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		var idx = s.arrays[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			for i in idx:
				faces.append(v[i])
		else:
			faces.append_array(v)
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	return sh

static func _add_body(root: Node, n: Node3D, surfs: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	n.add_child(body)
	body.owner = root
	var cs := CollisionShape3D.new()
	cs.shape = _trimesh(surfs)
	body.add_child(cs)
	cs.owner = root
	return body

## Nahradí uzel old uzlem new (stejný název a transformace), potomci old se přesunou.
static func _swap(root: Node, old: Node3D, new: Node3D) -> void:
	var p := old.get_parent()
	var nm := old.name
	var idx := old.get_index()
	var xf := old.transform
	p.remove_child(old)
	if new.get_parent():
		new.get_parent().remove_child(new)
	p.add_child(new)
	p.move_child(new, idx)
	new.name = nm
	new.transform = xf
	new.owner = root
	for c in old.get_children():
		old.remove_child(c)
		new.add_child(c)
		_reown(c, root)
	old.free()

static func _reown(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_reown(c, root)

# ---------- kamera ----------

static func _read_camera(root: Node, cam: Camera3D) -> void:
	var xf := cam.transform
	var fwd := -xf.basis.z
	if absf(fwd.y) > 0.001:
		var t := -xf.origin.y / fwd.y
		var hit := xf.origin + fwd * t
		root.set_meta("cam_offset", xf.origin - hit)
	root.set_meta("cam_basis", xf.basis.orthonormalized())
	root.set_meta("cam_fov", cam.fov)

# ---------- terén ----------

static func _layer_color(s: Dictionary) -> Color:
	var mname := ""
	if s.mat != null:
		mname = String(s.mat.resource_name)
	var key := (String(s.name) + "|" + mname).to_upper()
	if "G0" in key: return Color(1, 0, 0, 0)
	if "G1" in key: return Color(0, 1, 0, 0)
	if "G2" in key: return Color(0, 0, 1, 0)
	if "G3" in key: return Color(0, 0, 0, 1)
	return Color(0, 0, 0, 0)  # Cliff / neznámé => útes

static func _build_terrain(root: Node, n: Node3D) -> AABB:
	var surfs := _surfaces(n)
	var mat: Material = load(TERRAIN_MAT) if ResourceLoader.exists(TERRAIN_MAT) else null
	var painted := false
	for s in surfs:
		var c = s.arrays[Mesh.ARRAY_COLOR]
		if c != null and c.size() > 0:
			painted = true
	var acc := {}
	var raw: Array = []
	for s in surfs:
		var v: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		var col := PackedColorArray()
		if painted:
			col = s.arrays[Mesh.ARRAY_COLOR]
		else:
			col.resize(v.size())
			col.fill(_layer_color(s))
			# svařit podle pozice: vrchol na hranici materiálů dostane průměr => měkký přechod
			for j in v.size():
				var k := Vector3i((v[j] * 100.0).round())
				if not acc.has(k):
					acc[k] = [Color(0, 0, 0, 0), 0]
				var e: Array = acc[k]
				e[0] += col[j]
				e[1] += 1
		raw.append(col)
	var aabb := AABB()
	var first := true
	for i in surfs.size():
		var s: Dictionary = surfs[i]
		var v: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		if not painted:
			var out := PackedColorArray()
			out.resize(v.size())
			for j in v.size():
				var e: Array = acc[Vector3i((v[j] * 100.0).round())]
				out[j] = e[0] / float(e[1])
			s.arrays[Mesh.ARRAY_COLOR] = out
		if mat:
			s.mat = mat
		for p in v:
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	_set_surfaces(n, surfs)
	_add_body(root, n, surfs)
	return n.transform * aabb

# ---------- exit ----------

static func _build_exit(root: Node, n: Node3D) -> void:
	var parts := _clean(String(n.name)).trim_prefix("EXIT_").split("__")
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	if parts.size() >= 2:
		a.set_meta("target_map", parts[0])
		a.set_meta("target_spawn", parts[1])
	else:
		a.set_meta("target_map", parts[0])
		a.set_meta("target_spawn", "start")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE  # velikost určuje scale empty objektu z Blenderu
	cs.shape = box
	_swap(root, n, a)
	a.add_child(cs)
	cs.owner = root

# ---------- scatter ----------

static func _bake_scatter(root: Node, n: Node3D) -> void:
	var type := _clean(String(n.name)).trim_prefix("SCATTER_")
	var path := SCATTER_DIR + type + ".tres"
	var cfg: ScatterType = load(path) if ResourceLoader.exists(path) else ScatterType.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(n.name)) + cfg.seed

	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	for s in _surfaces(n):
		var v: PackedVector3Array = s.arrays[Mesh.ARRAY_VERTEX]
		var idx = s.arrays[Mesh.ARRAY_INDEX]
		var tri_count: int = (idx.size() if (idx != null and idx.size() > 0) else v.size()) / 3
		for t in tri_count:
			var ia := t * 3
			var a: Vector3; var b: Vector3; var c: Vector3
			if idx != null and idx.size() > 0:
				a = v[idx[ia]]; b = v[idx[ia + 1]]; c = v[idx[ia + 2]]
			else:
				a = v[ia]; b = v[ia + 1]; c = v[ia + 2]
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area < 0.0001 or absf(cr.normalized().y) < cfg.min_normal_y:
				continue
			var expected := area * cfg.density
			var count := int(expected) + (1 if rng.randf() < fmod(expected, 1.0) else 0)
			for k in count:
				if xforms.size() >= MAX_INSTANCES:
					break
				var r1 := sqrt(rng.randf())
				var r2 := rng.randf()
				var p := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
				p.y += cfg.y_offset
				var sc := rng.randf_range(cfg.scale_range.x, cfg.scale_range.y)
				xforms.append(Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), p))
				cols.append(cfg.tint_a.lerp(cfg.tint_b, rng.randf()))

	var tex: Texture2D = cfg.texture if cfg.texture else _placeholder()
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
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swap(root, n, mmi)

static func _placeholder() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 14):
		var h := 6 + (x * 7) % 9
		for y in range(16 - h, 16):
			img.set_pixel(x, y, Color(0.35 + 0.02 * (y % 5), 0.65, 0.25))
	return ImageTexture.create_from_image(img)
