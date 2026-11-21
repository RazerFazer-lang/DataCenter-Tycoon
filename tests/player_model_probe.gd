extends SceneTree
## Prüft assets/models/player.glb: Laden, Gelenke Pivot_* und Material DCT_Jacket.
## Aufruf: godot --headless --path . -s tests/player_model_probe.gd

const MODEL_PATH := "res://assets/models/player.glb"
const PIVOTS := ["Pivot_LegL", "Pivot_LegR", "Pivot_ArmL", "Pivot_ArmR", "Pivot_Head"]


func _init() -> void:
	var ok := true
	if not ResourceLoader.exists(MODEL_PATH):
		print("PROBE FAIL: ", MODEL_PATH, " fehlt")
		quit(1)
		return
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		print("PROBE FAIL: kein PackedScene")
		quit(1)
		return
	var model := scene.instantiate() as Node3D
	if model == null:
		print("PROBE FAIL: Wurzel ist kein Node3D")
		quit(1)
		return

	for pivot_name in PIVOTS:
		var n := model.find_child(pivot_name, true, false) as Node3D
		if n == null:
			print("PROBE FAIL: Gelenk fehlt: ", pivot_name)
			ok = false
		else:
			print("PROBE pivot ", pivot_name, " y=", snappedf(n.global_transform.origin.y if n.is_inside_tree() else _local_y(n, model), 0.001), " children=", n.get_child_count())

	var jacket_surfaces := _count_jacket(model)
	print("PROBE DCT_Jacket-Flächen: ", jacket_surfaces)
	if jacket_surfaces == 0:
		print("PROBE FAIL: Material DCT_Jacket nicht gefunden")
		ok = false

	model.free()
	print("PROBE ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)


func _local_y(n: Node3D, root: Node3D) -> float:
	var y := 0.0
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			y += (cur as Node3D).position.y
		cur = cur.get_parent()
	return y


func _count_jacket(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m != null and m.resource_name == "DCT_Jacket":
					count += 1
	for child in node.get_children():
		count += _count_jacket(child)
	return count