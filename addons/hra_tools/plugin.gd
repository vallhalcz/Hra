@tool
extends EditorPlugin

var _pp: EditorScenePostImportPlugin

class MapPostImport extends EditorScenePostImportPlugin:
	func _post_process(scene: Node) -> void:
		if get_source_file().begins_with("res://assets/maps/"):
			MapBuilder.build(scene)

func _enter_tree() -> void:
	_pp = MapPostImport.new()
	add_scene_post_import_plugin(_pp)

func _exit_tree() -> void:
	remove_scene_post_import_plugin(_pp)
