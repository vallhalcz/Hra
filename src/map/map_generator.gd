class_name MapGenerator
extends RefCounted
## Postaví mapu z res://maps/<id>/map.json (export z tools/map_designer.html): terén z výškové mapy,
## splat mapa vrstev (měkké přechody), textury, detaily, objekty (spawn, exit, postavy, kolize, modely), světlo.
## Souřadnice z návrháře: x doprava, z dolů (k hráči), počátek v rohu; ve hře je mapa vystředěná kolem (0,0).

const TERRAIN_MAT := "res://data/materials/terrain.tres"

static func build(path: String) -> Node3D:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary):
		push_error("Neplatný map.json: " + path)
		return null
	var dir := path.get_base_dir()
	var size := Vector2(j.size[0], j.size[1])
	var origin := -size * 0.5
	var gw := int(j.grid[0])
	var gh := int(j.grid[1])
	var maxh := float(j.max_height)
	var hb := Marshalls.base64_to_raw(j.height_b64)
	var sb := Marshalls.base64_to_raw(j.splat_b64)

	var root := Node3D.new()
	root.name = String(j.id)
	root.set_meta("bounds", AABB(Vector3(origin.x, 0, origin.y), Vector3(size.x, maxh, size.y)))

	var heights := PackedFloat32Array()
	heights.resize(gw * gh)
	for i in gw * gh:
		heights[i] = float(hb[i * 2] | (hb[i * 2 + 1] << 8)) / 65535.0 * maxh
	var hfn := func(px: float, pz: float) -> float:
		var u := clampf((px - origin.x) / size.x, 0.0, 1.0) * (gw - 1)
		var v := clampf((pz - origin.y) / size.y, 0.0, 1.0) * (gh - 1)
		var x0 := mini(int(u), gw - 2)
		var y0 := mini(int(v), gh - 2)
		var fx := u - x0
		var fy := v - y0
		var h00 := heights[y0 * gw + x0]
		var h10 := heights[y0 * gw + x0 + 1]
		var h01 := heights[(y0 + 1) * gw + x0]
		var h11 := heights[(y0 + 1) * gw + x0 + 1]
		return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

	# ---- terén ----
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in gh:
		for x in gw:
			var i := y * gw + x
			st.set_color(Color8(sb[i * 4], sb[i * 4 + 1], sb[i * 4 + 2], sb[i * 4 + 3]))
			st.set_uv(Vector2(float(x) / (gw - 1), float(y) / (gh - 1)))
			st.add_vertex(Vector3(origin.x + size.x * x / (gw - 1), heights[i], origin.y + size.y * y / (gh - 1)))
	for y in gh - 1:
		for x in gw - 1:
			var a := y * gw + x
			var b := a + 1
			var c := a + gw
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	terrain.material_override = _material(j, dir, gw, gh, sb, origin, size)
	root.add_child(terrain)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	terrain.add_child(body)
	# automatické detaily podle vrstev (data/scatter/*.tres s auto_layer)
	MapBuilder._auto_scatter(root, terrain, [{"arrays": mesh.surface_get_arrays(0), "mat": null, "name": "", "prim": Mesh.PRIMITIVE_TRIANGLES}])

	# ---- ručně malované detaily ----
	var details: Dictionary = j.get("details", {})
	for type in details:
		var cfg := MapBuilder._load_cfg(String(type))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(type)) + cfg.seed
		var xf: Array[Transform3D] = []
		var cols: Array[Color] = []
		for p in details[type]:
			var wx: float = origin.x + float(p[0])
			var wz: float = origin.y + float(p[1])
			var s := rng.randf_range(cfg.scale_range.x, cfg.scale_range.y)
			xf.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(wx, hfn.call(wx, wz) + cfg.y_offset, wz)))
			cols.append(cfg.tint_a.lerp(cfg.tint_b, rng.randf()))
		var mmi := DetailLayer.make_instance(cfg, xf, cols)
		mmi.name = "Detail_" + String(type)
		root.add_child(mmi)

	# ---- objekty ----
	for o in j.get("objects", []):
		var wx: float = origin.x + float(o.x)
		var wz: float = origin.y + float(o.z)
		var pos := Vector3(wx, hfn.call(wx, wz), wz)
		match String(o.t):
			"spawn":
				var m := Marker3D.new()
				m.name = "SPAWN_" + String(o.id)
				root.add_child(m)
				m.position = pos
			"npc", "enemy":
				var m := Marker3D.new()
				m.name = ("NPC_" if o.t == "npc" else "ENEMY_") + String(o.id)
				m.set_meta("character_id", String(o.id))
				root.add_child(m)
				m.position = pos
			"exit":
				var a := Area3D.new()
				a.name = "EXIT_" + String(o.map)
				a.collision_layer = 0
				a.collision_mask = 2
				a.set_meta("target_map", String(o.map))
				a.set_meta("target_spawn", String(o.get("spawn", "start")))
				var acs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(float(o.w), 4.0, float(o.d))
				acs.shape = box
				acs.position.y = 2.0
				a.add_child(acs)
				root.add_child(a)
				a.position = pos
			"box":
				var sb2 := StaticBody3D.new()
				sb2.name = "COL"
				sb2.collision_layer = 1
				sb2.collision_mask = 0
				var bcs := CollisionShape3D.new()
				var bb := BoxShape3D.new()
				bb.size = Vector3(float(o.w), float(o.h), float(o.d))
				bcs.shape = bb
				sb2.add_child(bcs)
				root.add_child(sb2)
				sb2.position = pos + Vector3(0, float(o.h) * 0.5, 0)
			"model":
				var inst := _load_model(String(o.id))
				if inst:
					root.add_child(inst)
					inst.position = pos
					inst.rotation_degrees.y = float(o.get("rot", 0))
					inst.scale = Vector3.ONE * float(o.get("scale", 1))
					if o.get("solid", true):
						for mi in inst.find_children("*", "MeshInstance3D", true, false):
							(mi as MeshInstance3D).create_trimesh_collision()

	# ---- světlo ----
	var l: Dictionary = j.get("light", {})
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(float(l.get("sun_pitch", -50)), float(l.get("sun_yaw", -35)), 0)
	sun.light_color = Color(String(l.get("sun_color", "#fff1d6")))
	sun.light_energy = float(l.get("sun_energy", 1.0))
	sun.shadow_enabled = true
	root.add_child(sun)
	root.set_meta("ambient_color", Color(String(l.get("amb_color", "#a8b4cc"))))
	root.set_meta("ambient_energy", float(l.get("amb_energy", 0.6)))
	root.set_meta("sky_color", Color(String(l.get("sky", "#8cb8e6"))))
	return root

static func _material(j: Dictionary, dir: String, gw: int, gh: int, sb: PackedByteArray, origin: Vector2, size: Vector2) -> Material:
	var mat := (load(TERRAIN_MAT) as ShaderMaterial).duplicate() as ShaderMaterial
	var names := ["tex0", "tex1", "tex2", "tex3", "tex_cliff"]
	var tints := ["tint0", "tint1", "tint2", "tint3", "tint_cliff"]
	var tiles := [0.25, 0.25, 0.25, 0.25]
	var pixel := false
	var layers: Array = j.get("layers", [])
	for i in mini(5, layers.size()):
		var L: Dictionary = layers[i]
		var tp: String = dir + "/" + String(L.get("texture", ""))
		if String(L.get("texture", "")) != "" and ResourceLoader.exists(tp):
			mat.set_shader_parameter(names[i], load(tp))
		mat.set_shader_parameter(tints[i], Color(String(L.get("tint", "#ffffff"))))
		var tl := 1.0 / maxf(float(L.get("tile", 4.0)), 0.05)
		if i < 4:
			tiles[i] = tl
		else:
			mat.set_shader_parameter("tiles_per_meter", tl)
		pixel = pixel or bool(L.get("pixel", false))
	mat.set_shader_parameter("tiles", Vector4(tiles[0], tiles[1], tiles[2], tiles[3]))
	mat.set_shader_parameter("pixel_filter", pixel)
	mat.set_shader_parameter("splat_tex", ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_RGBA8, sb)))
	mat.set_shader_parameter("use_splat", true)
	mat.set_shader_parameter("map_origin", origin)
	mat.set_shader_parameter("map_size", size)
	return mat

static func _load_model(id: String) -> Node3D:
	for e in [".glb", ".tscn", ".gltf", ".fbx"]:
		var p := "res://assets/props/" + id + e
		if ResourceLoader.exists(p):
			var ps := load(p) as PackedScene
			return ps.instantiate() as Node3D if ps else null
	push_warning("Model '%s' nenalezen v res://assets/props/" % id)
	return null
