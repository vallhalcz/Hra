@tool
extends EditorPlugin
## Hra Tools: (1) auto-zpracování map z Blenderu, (2) dock "Hra": nová mapa, štětec detailů, přiřazení textur.

const SCATTER_DIR := "res://data/scatter/"
const TERRAIN_MAT := "res://data/materials/terrain.tres"
const AUTO_MAT_DIR := "res://data/materials/auto/"

class MapPostImport extends EditorScenePostImportPlugin:
	func _post_process(scene: Node) -> void:
		if get_source_file().begins_with("res://assets/maps/"):
			MapBuilder.build(scene)

var _pp: EditorScenePostImportPlugin
var _dock: VBoxContainer
var _map_opt: OptionButton
var _type_opt: OptionButton
var _brush_on: CheckButton
var _radius: HSlider
var _density: HSlider
var _erase: CheckButton
var _tex_picker: EditorResourcePicker
var _tex_target: OptionButton
var _tex_pixel: CheckBox
var _status: Label

var _layer: DetailLayer
var _cursor: MeshInstance3D
var _painting := false
var _grid := {}
var _pts := PackedVector3Array()
var _scl := PackedFloat32Array()
var _tnt := PackedFloat32Array()
var _old: Array = []
var _tm_cache := {}

func _enter_tree() -> void:
	_pp = MapPostImport.new()
	add_scene_post_import_plugin(_pp)
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)

func _exit_tree() -> void:
	remove_scene_post_import_plugin(_pp)
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_free_cursor()

# ---------------------------------------------------------------- dock

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b

func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Hra"
	_dock.custom_minimum_size = Vector2(260, 0)

	_dock.add_child(_label("1) NOVÁ MAPA"))
	_map_opt = OptionButton.new()
	_dock.add_child(_map_opt)
	_dock.add_child(_btn("Obnovit seznam", _refresh_lists))
	_dock.add_child(_btn("Vytvořit scénu mapy (res://maps)", _create_map_scene))

	_dock.add_child(HSeparator.new())
	_dock.add_child(_label("2) DETAILY (štětec)"))
	_type_opt = OptionButton.new()
	_dock.add_child(_type_opt)
	_dock.add_child(_btn("Nová vrstva detailů v mapě", _new_layer))
	_brush_on = CheckButton.new()
	_brush_on.text = "Štětec aktivní"
	_brush_on.button_pressed = true
	_dock.add_child(_brush_on)
	_erase = CheckButton.new()
	_erase.text = "Guma (nebo drž Shift)"
	_dock.add_child(_erase)
	_dock.add_child(_label("Velikost štětce"))
	_radius = HSlider.new()
	_radius.min_value = 0.5
	_radius.max_value = 8.0
	_radius.step = 0.1
	_radius.value = 2.0
	_dock.add_child(_radius)
	_dock.add_child(_label("Hustota (násobek)"))
	_density = HSlider.new()
	_density.min_value = 0.1
	_density.max_value = 3.0
	_density.step = 0.1
	_density.value = 1.0
	_dock.add_child(_density)
	_dock.add_child(_label("Vyber vrstvu v Scene panelu → LMB maluje v 3D pohledu."))

	_dock.add_child(HSeparator.new())
	_dock.add_child(_label("3) TEXTURA → OBJEKT"))
	_tex_picker = EditorResourcePicker.new()
	_tex_picker.base_type = "Texture2D"
	_tex_picker.editable = true
	_dock.add_child(_tex_picker)
	_tex_target = OptionButton.new()
	for t in ["Vybraný objekt", "Terén: G0 (tráva)", "Terén: G1", "Terén: G2", "Terén: G3", "Terén: útes (Cliff)"]:
		_tex_target.add_item(t)
	_dock.add_child(_tex_target)
	_tex_pixel = CheckBox.new()
	_tex_pixel.text = "Pixel-art (ostré texely)"
	_dock.add_child(_tex_pixel)
	_dock.add_child(_btn("Přiřadit texturu", _assign_texture))
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_status)
	_dock.add_child(HSeparator.new())
	_dock.add_child(_label("4) POSTAVY"))
	_dock.add_child(_btn("Importovat ZIP z res://incoming", _import_zips))
	_dock.add_child(_label("ZIP z tvůrce postav hoď do složky incoming – naimportuje se sám."))
	_refresh_lists()
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_import_zips)

func _refresh_lists() -> void:
	_map_opt.clear()
	for f in DirAccess.get_files_at("res://assets/maps/"):
		if f.get_extension() in ["glb", "gltf", "fbx"]:
			_map_opt.add_item(f)
	_type_opt.clear()
	for f in DirAccess.get_files_at(SCATTER_DIR):
		if f.ends_with(".tres"):
			_type_opt.add_item(f.get_basename())

func _say(t: String) -> void:
	_status.text = t

# ---------------------------------------------------------------- nová mapa / vrstva

func _create_map_scene() -> void:
	if _map_opt.item_count == 0:
		_say("V res://assets/maps není žádný soubor.")
		return
	var file := _map_opt.get_item_text(_map_opt.selected)
	var id := file.get_basename()
	var src := load("res://assets/maps/" + file) as PackedScene
	if src == null:
		_say("Soubor se ještě neimportoval, počkej chvíli.")
		return
	var root := Node3D.new()
	root.name = id.capitalize().replace(" ", "")
	var inst := src.instantiate()
	inst.name = "Import"
	root.add_child(inst)
	inst.owner = root
	var det := Node3D.new()
	det.name = "Details"
	root.add_child(det)
	det.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute("res://maps")
	var out := "res://maps/%s.tscn" % id
	ResourceSaver.save(ps, out)
	root.free()
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(out)
	_say("Vytvořeno: " + out + ". Hra teď bere tuto scénu místo samotného GLB.")

func _new_layer() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _type_opt.item_count == 0:
		_say("Otevři scénu mapy (res://maps/...) a vyber typ.")
		return
	var tname := _type_opt.get_item_text(_type_opt.selected)
	var det := root.get_node_or_null("Details")
	if det == null:
		det = Node3D.new()
		det.name = "Details"
		root.add_child(det)
		det.owner = root
	var l := DetailLayer.new()
	l.scatter_type = load(SCATTER_DIR + tname + ".tres")
	l.name = tname.capitalize().replace(" ", "")
	det.add_child(l, true)
	l.owner = root
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(l)
	_say("Vrstva '%s' vytvořena a vybrána. Maluj levým tlačítkem na terénu." % tname)

# ---------------------------------------------------------------- štětec

func _handles(object: Object) -> bool:
	return object is DetailLayer

func _edit(object: Object) -> void:
	_layer = object as DetailLayer

func _make_visible(visible: bool) -> void:
	if not visible:
		_layer = null
		_free_cursor()

func _free_cursor() -> void:
	if is_instance_valid(_cursor):
		_cursor.queue_free()
	_cursor = null

func _ensure_cursor() -> void:
	if is_instance_valid(_cursor):
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	_cursor = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.05
	cyl.radial_segments = 32
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.9, 0.2, 0.35)
	cyl.material = m
	_cursor.mesh = cyl
	root.add_child(_cursor)  # bez owner => neuloží se do scény

func _terrains() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	return root.find_children("Terrain*", "MeshInstance3D", true, false) if root else []

func _ray(o: Vector3, d: Vector3) -> Dictionary:
	var best := {}
	var bt := INF
	for mi in _terrains():
		if mi.mesh == null:
			continue
		if not _tm_cache.has(mi.mesh):
			_tm_cache[mi.mesh] = mi.mesh.generate_triangle_mesh()
		var tm: TriangleMesh = _tm_cache[mi.mesh]
		var xf: Transform3D = mi.global_transform
		var inv := xf.affine_inverse()
		var r := tm.intersect_ray(inv * o, (inv.basis * d).normalized())
		if r.is_empty():
			continue
		var gp: Vector3 = xf * r["position"]
		var t := o.distance_to(gp)
		if t < bt:
			bt = t
			best = {"pos": gp, "normal": (xf.basis * r["normal"]).normalized()}
	return best

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _layer == null or not _brush_on.button_pressed or not (event is InputEventMouse):
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return AFTER_GUI_INPUT_PASS
	if event.alt_pressed:
		return AFTER_GUI_INPUT_PASS
	var hit := _ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	_ensure_cursor()
	if is_instance_valid(_cursor):
		_cursor.visible = not hit.is_empty()
		if not hit.is_empty():
			_cursor.global_position = hit["pos"]
			_cursor.scale = Vector3(_radius.value, 1, _radius.value)
	if event is InputEventMouseButton:
		if event.pressed and not hit.is_empty():
			_begin_stroke()
			_apply(hit["pos"], event.shift_pressed)
			return AFTER_GUI_INPUT_STOP
		elif not event.pressed and _painting:
			_end_stroke()
			return AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _painting:
		if not hit.is_empty():
			_apply(hit["pos"], event.shift_pressed)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _cell() -> float:
	var cfg := _layer.scatter_type if _layer.scatter_type else ScatterType.new()
	return 1.0 / sqrt(maxf(cfg.density * _density.value, 0.01))

func _rebuild_grid() -> void:
	_grid.clear()
	var c := _cell()
	for p in _pts:
		_grid[Vector2i(floori(p.x / c), floori(p.z / c))] = true

func _begin_stroke() -> void:
	_painting = true
	_pts = _layer.points.duplicate()
	_scl = _layer.scales.duplicate()
	_tnt = _layer.tints.duplicate()
	while _scl.size() < _pts.size():
		_scl.append(1.0)
	while _tnt.size() < _pts.size():
		_tnt.append(0.0)
	_old = [_layer.points.duplicate(), _layer.scales.duplicate(), _layer.tints.duplicate()]
	_rebuild_grid()

func _apply(gpos: Vector3, erase: bool) -> void:
	var c := _layer.to_local(gpos)
	var r: float = _radius.value
	if erase or _erase.button_pressed:
		var np := PackedVector3Array()
		var ns := PackedFloat32Array()
		var nt := PackedFloat32Array()
		for i in _pts.size():
			if Vector2(_pts[i].x - c.x, _pts[i].z - c.z).length() > r:
				np.append(_pts[i])
				ns.append(_scl[i])
				nt.append(_tnt[i])
		_pts = np
		_scl = ns
		_tnt = nt
		_rebuild_grid()
	else:
		var cfg := _layer.scatter_type if _layer.scatter_type else ScatterType.new()
		var cell := _cell()
		var tries := int(PI * r * r * cfg.density * _density.value * 0.8) + 2
		for i in tries:
			var a := randf() * TAU
			var d := sqrt(randf()) * r
			var p := Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d)
			var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
			if _grid.has(key):
				continue
			var h := _ray(_layer.to_global(p) + Vector3.UP * 60.0, Vector3.DOWN)
			if h.is_empty() or h["normal"].y < cfg.min_normal_y:
				continue
			p = _layer.to_local(h["pos"]) + Vector3(0, cfg.y_offset, 0)
			_grid[key] = true
			_pts.append(p)
			_scl.append(randf_range(cfg.scale_range.x, cfg.scale_range.y))
			_tnt.append(randf())
	_layer.scales = _scl
	_layer.tints = _tnt
	_layer.points = _pts  # setter přestaví multimesh

func _end_stroke() -> void:
	_painting = false
	var ur := get_undo_redo()
	ur.create_action("Malovat detaily", UndoRedo.MERGE_DISABLE, _layer)
	ur.add_do_property(_layer, "scales", _scl)
	ur.add_do_property(_layer, "tints", _tnt)
	ur.add_do_property(_layer, "points", _pts)
	ur.add_undo_property(_layer, "scales", _old[1])
	ur.add_undo_property(_layer, "tints", _old[2])
	ur.add_undo_property(_layer, "points", _old[0])
	ur.commit_action()

# ---------------------------------------------------------------- textury

func _assign_texture() -> void:
	var tex := _tex_picker.edited_resource as Texture2D
	if tex == null:
		_say("Nejdřív vyber nebo přetáhni texturu.")
		return
	var t := _tex_target.selected
	if t == 0:
		var n := 0
		DirAccess.make_dir_recursive_absolute(AUTO_MAT_DIR)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 1.0
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if _tex_pixel.button_pressed else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var path := AUTO_MAT_DIR + tex.resource_path.get_file().get_basename() + ".tres"
		ResourceSaver.save(mat, path)
		mat = load(path)
		for node in EditorInterface.get_selection().get_selected_nodes():
			for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
				if mi is MeshInstance3D:
					mi.material_override = mat
					n += 1
		_say("Materiál uložen (%s), nastaven na %d objektů." % [path, n] if n > 0 else "Vyber v Scene panelu objekt (MeshInstance3D).")
	else:
		var sm := load(TERRAIN_MAT) as ShaderMaterial
		var param := ["tex0", "tex1", "tex2", "tex3", "tex_cliff"][t - 1]
		sm.set_shader_parameter(param, tex)
		sm.set_shader_parameter("pixel_filter", _tex_pixel.button_pressed)
		ResourceSaver.save(sm, TERRAIN_MAT)
		_say("Terén: textura '%s' nastavena (%s)." % [tex.resource_path.get_file(), param])

# ---------------------------------------------------------------- postavy (ZIP z tvůrce postav)

var _importing := false

func _import_zips() -> void:
	if _importing:
		return
	var zips: Array[String] = []
	for f in DirAccess.get_files_at("res://incoming/"):
		if f.get_extension().to_lower() == "zip":
			zips.append(f)
	if zips.is_empty():
		return
	_importing = true
	var chars := []
	for f in zips:
		var z := ZIPReader.new()
		if z.open("res://incoming/" + f) != OK:
			_say("Nelze otevřít " + f)
			continue
		for path in z.get_files():
			if not path.begins_with("characters/") or path.ends_with("/") or ".." in path or path.ends_with("_editor.json"):
				continue
			var dst := "res://" + path
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var fa := FileAccess.open(dst, FileAccess.WRITE)
			if fa:
				fa.store_buffer(z.read_file(path))
				fa.close()
			if path.ends_with("character.json"):
				chars.append(path.get_base_dir().get_file())
		z.close()
		DirAccess.rename_absolute("res://incoming/" + f, "res://incoming/" + f + ".done")
	_say("Naimportované postavy: " + ", ".join(chars))
	EditorInterface.get_resource_filesystem().scan()
	_importing = false
