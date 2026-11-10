bl_info = {"name": "Hra Map Tools", "author": "vallhalcz", "version": (0, 1), "blender": (3, 6, 0),
           "location": "3D View > N panel > Hra", "description": "Pomocník pro mapy do Godot HD-2D hry", "category": "Import-Export"}
import bpy, os

LAYERS = ["G0", "G1", "G2", "G3", "Cliff"]

def _empty(name, display, size=1.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    e.location = bpy.context.scene.cursor.location
    bpy.context.collection.objects.link(e)
    bpy.context.view_layer.objects.active = e
    return e

class HRA_OT_spawn(bpy.types.Operator):
    bl_idname = "hra.add_spawn"; bl_label = "Přidat SPAWN"; bl_options = {"REGISTER", "UNDO"}
    sid: bpy.props.StringProperty(name="ID", default="start")
    def execute(self, ctx):
        _empty("SPAWN_" + self.sid, "SINGLE_ARROW", 1.0); return {"FINISHED"}

class HRA_OT_exit(bpy.types.Operator):
    bl_idname = "hra.add_exit"; bl_label = "Přidat EXIT"; bl_options = {"REGISTER", "UNDO"}
    target: bpy.props.StringProperty(name="Cílová mapa", default="les")
    spawn: bpy.props.StringProperty(name="Cílový spawn", default="start")
    def execute(self, ctx):
        e = _empty("EXIT_%s__%s" % (self.target, self.spawn), "CUBE", 0.5); e.scale = (2, 1, 2); return {"FINISHED"}

class HRA_OT_scatter(bpy.types.Operator):
    bl_idname = "hra.scatter_from_selection"; bl_label = "Vybrané meshe → SCATTER"; bl_options = {"REGISTER", "UNDO"}
    stype: bpy.props.StringProperty(name="Typ", default="grass")
    def execute(self, ctx):
        for o in ctx.selected_objects:
            if o.type == "MESH":
                o.name = "SCATTER_" + self.stype
                o.display_type = "WIRE"
        return {"FINISHED"}

class HRA_OT_prefix(bpy.types.Operator):
    bl_idname = "hra.prefix"; bl_label = "Přejmenovat výběr"; bl_options = {"REGISTER", "UNDO"}
    prefix: bpy.props.StringProperty()
    def execute(self, ctx):
        for o in ctx.selected_objects:
            base = o.name.split("_", 1)[-1] if o.name.split("_")[0] in ("SOLID", "COL", "Terrain") else o.name
            o.name = self.prefix + base if self.prefix != "Terrain" else "Terrain"
        return {"FINISHED"}

class HRA_OT_layers(bpy.types.Operator):
    bl_idname = "hra.make_layer_materials"; bl_label = "Vytvořit materiály G0–G3 + Cliff"; bl_options = {"REGISTER", "UNDO"}
    def execute(self, ctx):
        cols = [(.42, .62, .24), (.52, .70, .30), (.62, .52, .34), (.34, .50, .22), (.45, .40, .36)]
        for n, c in zip(LAYERS, cols):
            m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
            m.diffuse_color = (*c, 1)
        return {"FINISHED"}

class HRA_OT_texture(bpy.types.Operator):
    bl_idname = "hra.assign_texture"; bl_label = "Přiřadit texturu výběru"; bl_options = {"REGISTER", "UNDO"}
    filepath: bpy.props.StringProperty(subtype="FILE_PATH")
    def invoke(self, ctx, ev):
        ctx.window_manager.fileselect_add(self); return {"RUNNING_MODAL"}
    def execute(self, ctx):
        img = bpy.data.images.load(self.filepath, check_existing=True)
        name = os.path.splitext(os.path.basename(self.filepath))[0]
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        tex = nt.nodes.get("HraTex") or nt.nodes.new("ShaderNodeTexImage")
        tex.name = "HraTex"; tex.image = img; tex.interpolation = "Closest" if ctx.scene.hra_pixel else "Linear"
        bsdf = nt.nodes.get("Principled BSDF")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        for o in ctx.selected_objects:
            if o.type == "MESH":
                o.data.materials.clear(); o.data.materials.append(m)
        return {"FINISHED"}

class HRA_OT_export(bpy.types.Operator):
    bl_idname = "hra.export"; bl_label = "Exportovat GLB do Godot projektu"
    def execute(self, ctx):
        s = ctx.scene.hra_project_dir; name = ctx.scene.hra_map_id
        if not s or not name:
            self.report({"ERROR"}, "Vyplň složku projektu a ID mapy"); return {"CANCELLED"}
        path = os.path.join(bpy.path.abspath(s), "assets", "maps", name + ".glb")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_cameras=True, export_lights=True,
                                  export_extras=True, export_apply=True, export_yup=True,
                                  export_attributes=True)
        self.report({"INFO"}, "Exportováno: " + path); return {"FINISHED"}

class HRA_PT_panel(bpy.types.Panel):
    bl_label = "Hra mapa"; bl_idname = "HRA_PT_panel"; bl_space_type = "VIEW_3D"; bl_region_type = "UI"; bl_category = "Hra"
    def draw(self, ctx):
        l = self.layout; sc = ctx.scene
        l.operator("hra.make_layer_materials")
        l.label(text="Výběr →")
        r = l.row(align=True)
        for p in ("Terrain", "SOLID_", "COL_"):
            r.operator("hra.prefix", text=p.strip("_")).prefix = p
        l.operator("hra.scatter_from_selection")
        l.prop(sc, "hra_pixel"); l.operator("hra.assign_texture")
        l.operator("hra.add_spawn"); l.operator("hra.add_exit")
        l.separator()
        l.prop(sc, "hra_project_dir"); l.prop(sc, "hra_map_id")
        l.operator("hra.export")

CLASSES = (HRA_OT_texture, HRA_OT_spawn, HRA_OT_exit, HRA_OT_scatter, HRA_OT_prefix, HRA_OT_layers, HRA_OT_export, HRA_PT_panel)

def register():
    for c in CLASSES: bpy.utils.register_class(c)
    bpy.types.Scene.hra_project_dir = bpy.props.StringProperty(name="Složka projektu", subtype="DIR_PATH")
    bpy.types.Scene.hra_pixel = bpy.props.BoolProperty(name="Pixel-art (ostré)", default=False)
    bpy.types.Scene.hra_map_id = bpy.props.StringProperty(name="ID mapy", default="uvod")

def unregister():
    for c in reversed(CLASSES): bpy.utils.unregister_class(c)
    del bpy.types.Scene.hra_pixel, bpy.types.Scene.hra_project_dir, bpy.types.Scene.hra_map_id

if __name__ == "__main__":
    register()
