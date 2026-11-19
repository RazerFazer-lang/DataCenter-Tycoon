extends Node
## Optional external .glb / .gltf 3D model override pipeline.
## Drop Blender/Sketchfab .glb files into res://assets/models/<id>.glb OR
## <game_folder>/custom_models/<id>.glb to automatically replace procedural meshes!

var _cache: Dictionary = {} # model_id -> PackedScene or Node template path


func has_custom_model(model_id: String) -> bool:
	return not _find_model_path(model_id).is_empty()


func instantiate_custom_model(model_id: String) -> Node3D:
	var path := _find_model_path(model_id)
	if path.is_empty():
		return null

	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			if inst is Node3D:
				return inst as Node3D

	# Runtime GLTFDocument loader works even for external .glb files next to the exported .exe!
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return null
	var scene_root := doc.generate_scene(state)
	if scene_root is Node3D:
		return scene_root as Node3D
	return null


func _find_model_path(model_id: String) -> String:
	if _cache.has(model_id):
		return str(_cache[model_id])

	var res_glb := "res://assets/models/%s.glb" % model_id
	if FileAccess.file_exists(res_glb):
		_cache[model_id] = res_glb
		return res_glb

	var exe_dir := OS.get_executable_path().get_base_dir()
	var ext_glb := exe_dir.path_join("custom_models/%s.glb" % model_id)
	if FileAccess.file_exists(ext_glb):
		_cache[model_id] = ext_glb
		return ext_glb

	var user_glb := ProjectSettings.globalize_path("user://custom_models/%s.glb" % model_id)
	if FileAccess.file_exists(user_glb):
		_cache[model_id] = user_glb
		return user_glb

	_cache[model_id] = ""
	return ""
