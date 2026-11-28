extends SceneTree
## Lieferwagen an Halle Nord: Bilder der Anfahrt (Weg durch die Einfahrt, Schranke offen, Stand vor dem Rolltor).
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/halle2_van_shots.gd

const OUT_DIR := "res://tests/_shots_halle2"
const TIMES := [5.0, 9.0, 12.0, 13.7]


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.0).timeout
	root.get_node("/root/NetworkManager").host_game("Probe", 7796, "Van Probe")
	await create_timer(4.0).timeout
	var gs := root.get_node("/root/GameState")
	gs.halle_nord_owned = true
	gs.halle_nord_changed.emit()
	gs.building_upgrades["upg_security_gate"] = true
	gs.building_upgrades_changed.emit()
	await create_timer(2.0).timeout
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for p in get_nodes_in_group("player"):
		(p as Node3D).global_position = Vector3(0, -50, 0)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 500.0
	root.add_child(cam)
	var o: Vector3 = gs.HALLE_NORD_ORIGIN
	for t in TIMES:
		for i in range(50):
			gs.van_site = "halle_nord"
			gs.van_delivery_tier = 3
			gs.van_phase = "arriving"
			gs.van_phase_time = float(t)
			cam.global_position = o + Vector3(6.0, 22.0, 30.0)
			cam.look_at(o + Vector3(-6.0, 0.0, 12.0), Vector3.UP)
			cam.make_current()
			await process_frame
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/van_%04.1f.jpg" % [OUT_DIR, t])
		img.save_jpg(path, 0.85)
		print("SHOT ", path)
	quit(0)
