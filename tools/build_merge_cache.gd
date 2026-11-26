extends SceneTree
## Schreibt die Geometrie aller Bauteil-Modelle (hwm_*, part_*) nach assets/merge_cache/<modell>.bin.
## MeshMerger liest sie im Spiel in einem Hintergrund-Thread, statt die Daten von der Grafikkarte
## zurückzuholen (das wartet jedes Mal auf das laufende Bild).
## Ohne Bildschirm starten, dann liegen die Netze im Arbeitsspeicher:
##   godot --headless --path . -s res://tools/build_merge_cache.gd
## Nach jeder Änderung an den Bauteil-Modellen neu ausführen.

const OUT := "res://assets/merge_cache"
const KEEP := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]


func _initialize() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		push_error("Bitte mit --headless starten.")
		quit(1)
		return
	var ml := root.get_node("ModelLoader")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for old in DirAccess.get_files_at(OUT):
		if old.ends_with(".bin"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT.path_join(old)))
	var models := 0
	var surfaces := 0
	var bytes := 0
	for f in DirAccess.get_files_at("res://assets/models"):
		if not f.ends_with(".glb") or not (f.begins_with("hwm_") or f.begins_with("part_")):
			continue
		var id := f.get_basename()
		var m: Node = ml.instantiate_custom_model(id)
		if m == null:
			continue
		var data := {}
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null or not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_blend_shape_count() > 0:
				continue
			for s in mesh.get_surface_count():
				if (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var a: Array = mesh.surface_get_arrays(s)
				if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null:
					continue
				var keep: Array = []
				keep.resize(Mesh.ARRAY_MAX)
				for k in KEEP:
					keep[k] = a[k]
				data["%s|%d" % [m.get_path_to(mi), s]] = keep
				surfaces += 1
		m.free()
		if data.is_empty():
			continue
		var raw := var_to_bytes(data)
		var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
		var out := FileAccess.open(OUT.path_join(id + ".bin"), FileAccess.WRITE)
		out.store_32(raw.size())
		out.store_buffer(packed)
		out.close()
		models += 1
		bytes += packed.size() + 4
	print("Teile-Cache: %d Modelle, %d Flächen, %.1f MB" % [models, surfaces, bytes / 1048576.0])
	quit()
