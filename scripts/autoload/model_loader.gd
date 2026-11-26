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
				_configure_imported_visuals(inst as Node3D)
				return inst as Node3D

	# Runtime GLTFDocument loader works even for external .glb files next to the exported .exe!
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return null
	var scene_root := doc.generate_scene(state)
	if scene_root is Node3D:
		_configure_imported_visuals(scene_root as Node3D)
		return scene_root as Node3D
	return null


## Kleine Einzelteile (unter 20 cm) blenden ab etwa der 200-fachen Größe weich aus: Dann wären sie nur
## noch wenige Pixel groß. Das spart Zeichenaufrufe, auch in den Schatten. Leuchtende Teile (von weitem
## als Lichtpunkt sichtbar) und Figuren mit Skelett oder Gesichtsformen bleiben unverändert.
const SMALL_PART_SIZE := 0.20


static func _limit_small_part(mi: MeshInstance3D, xf: Transform3D) -> void:
	if mi.mesh == null or mi.skin != null or mi.visibility_range_end > 0.0:
		return
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return
	var longest := (xf * mi.mesh.get_aabb()).get_longest_axis_size()
	if longest <= 0.0 or longest >= SMALL_PART_SIZE:
		return
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
			return
		if m is ShaderMaterial:
			return
	mi.visibility_range_end = clampf(longest * 200.0, 10.0, 40.0)
	mi.visibility_range_end_margin = 2.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _configure_imported_visuals(node: Node, xf: Transform3D = Transform3D.IDENTITY) -> void:
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_limit_small_part(mi, xf)
		if mi.name.contains("Glass"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh != null:
				for s_idx in range(mi.mesh.get_surface_count()):
					var mat := mi.get_active_material(s_idx)
					if mat is BaseMaterial3D:
						var bm := mat as BaseMaterial3D
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in node.get_children():
		_configure_imported_visuals(child, xf)


func _find_model_path(model_id: String) -> String:
	if _cache.has(model_id):
		return str(_cache[model_id])

	# Im Export liegt nur die importierte Fassung (.glb.import + .scn) in der .pck, nicht die Rohdatei.
	# FileAccess.file_exists() findet sie dort nicht, ResourceLoader.exists() schon.
	var res_glb := "res://assets/models/%s.glb" % model_id
	if ResourceLoader.exists(res_glb) or FileAccess.file_exists(res_glb):
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
