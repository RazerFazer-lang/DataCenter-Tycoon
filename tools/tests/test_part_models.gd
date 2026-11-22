extends Node
## Prüft, ob HardwareMeshFactory die Blender-Modelle aus assets/models lädt und markiert.
## Start: Godot --headless --path <projekt> res://tools/tests/test_part_models.tscn

const CATS := ["mainboard", "cpu", "ram", "gpu", "storage", "cooling", "psu"]


func _ready() -> void:
	var failed := false
	for item_type in ["web_server", "gpu_server"]:
		var fans: Array = []
		var comps := {"cpu": 3, "ram": 3, "gpu": 2, "storage": 3, "cooling": 3, "psu": 3}
		var srv := HardwareMeshFactory.build_open_server_chassis(item_type, comps, fans)
		add_child(srv)
		var found: Dictionary = {}
		_collect(srv, found)
		var models := _count_glb_roots(srv)
		print("TEST %s: part_cat=%s glb_roots=%d fans=%d" % [item_type, str(found.keys()), models, fans.size()])
		for cat in CATS:
			if not found.has(cat):
				print("TEST FAIL %s: part_cat '%s' fehlt" % [item_type, cat])
				failed = true
		if models < CATS.size():
			print("TEST FAIL %s: nur %d von %d Bauteilen kommen aus .glb" % [item_type, models, CATS.size()])
			failed = true
		srv.queue_free()
	print("TEST label mainboard = %s" % GameState.get_component_label("mainboard"))
	print("TEST RESULT: %s" % ("FAIL" if failed else "OK"))
	get_tree().quit(1 if failed else 0)


func _collect(n: Node, found: Dictionary) -> void:
	if n.has_meta("part_cat"):
		found[str(n.get_meta("part_cat"))] = true
	for c in n.get_children():
		_collect(c, found)


## Importierte .glb-Szenen haben eine scene_file_path; im Code gebaute Knoten nicht.
func _count_glb_roots(n: Node) -> int:
	var count := 0
	if n.scene_file_path.ends_with(".glb"):
		count += 1
	for c in n.get_children():
		count += _count_glb_roots(c)
	return count