extends SceneTree
## Bilder von Halle Nord (Halle 2) und den Garagen-Anbauten.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/halle2_shots.gd -- tag=vorher [upg=1]

const OUT_DIR := "res://tests/_shots_halle2"


func _initialize() -> void:
	create_timer(110.0).timeout.connect(func() -> void:
		print("SHOT Timer-Abbruch")
		quit(2))
	var tag := "vorher"
	var with_upg := false
	var only_one := false
	var night := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("tag="):
			tag = arg.substr(4)
		if arg == "upg=1":
			with_upg = true
		if arg == "sec=1":
			only_one = true
		if arg == "nacht=1":
			night = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.0).timeout
	var net := root.get_node("/root/NetworkManager")
	net.host_game("Probe", 7795, "Halle Probe")
	await create_timer(4.0).timeout
	var gs := root.get_node("/root/GameState")
	gs.money = 900000.0
	gs.room_level = 2
	gs.room_level_changed.emit()
	gs.halle_nord_owned = true
	gs.halle_nord_changed.emit()
	if with_upg:
		for uid in gs.BUILDING_UPGRADE_ORDER:
			if only_one and str(uid).begins_with("upg_nord_section"):
				continue
			gs.building_upgrades[uid] = true
		gs.building_upgrades_changed.emit()
	if night:
		gs.time_of_day = 0.9
	gs._recalculate_networks_and_metrics()
	await create_timer(3.0).timeout
	_hide_ui(root)
	# Spieler weit weg parken, damit er nicht im Bild steht
	for p in get_nodes_in_group("player"):
		if p is Node3D:
			(p as Node3D).global_position = Vector3(0, -50, 0)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 600.0
	root.add_child(cam)
	var o: Vector3 = gs.HALLE_NORD_ORIGIN
	var shots := [
		["nord_innen_tor", o + Vector3(-7.0, 1.7, 6.2), o + Vector3(-2.0, 1.2, -5.0)],
		["nord_innen_west", o + Vector3(6.0, 1.7, 3.0), o + Vector3(-9.0, 1.0, -3.0)],
		["nord_innen_ost", o + Vector3(-7.5, 1.7, 2.0), o + Vector3(9.0, 1.0, -4.0)],
		["nord_innen_oben", o + Vector3(10.5, 4.2, 6.0), o + Vector3(-4.0, 0.0, -2.0)],
		["nord_technik", o + Vector3(-7.4, 1.7, -1.6), o + Vector3(-10.4, 1.0, -6.4)],
		["nord_buero", o + Vector3(-8.4, 1.7, 2.6), o + Vector3(-11.4, 1.2, 5.6)],
		["nord_buero_innen", o + Vector3(-9.6, 1.6, 4.2), o + Vector3(-11.8, 1.5, 5.4)],
		["nord_aussen_front", o + Vector3(0.0, 3.0, 22.0), o + Vector3(0.0, 2.0, 0.0)],
		["nord_aussen_schraeg", o + Vector3(-20.0, 8.0, 20.0), o + Vector3(0.0, 1.0, 0.0)],
		["nord_aussen_ost", o + Vector3(22.0, 5.0, 12.0), o + Vector3(0.0, 1.0, 0.0)],
		["nord_luft", o + Vector3(0.0, 45.0, 30.0), o + Vector3(0.0, 0.0, 0.0)],
		["garage_hallen_bc", Vector3(2.0, 1.7, 3.5), Vector3(16.0, 1.0, -2.0)],
		["garage_halle_c", Vector3(10.5, 1.7, 3.0), Vector3(20.0, 1.0, -3.0)],
		["garage_aussen", Vector3(8.0, 6.0, 22.0), Vector3(8.0, 1.5, 0.0)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in range(40):
			cam.make_current()
			await process_frame
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/%s_%s.jpg" % [OUT_DIR, tag, s[0]])
		img.save_jpg(path, 0.85)
		print("SHOT ", path)
	quit(0)


func _hide_ui(n: Node) -> int:
	var c := 0
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
		c += 1
	elif n is Control and n.get_parent() is Window:
		(n as Control).visible = false
		c += 1
	for ch in n.get_children():
		c += _hide_ui(ch)
	return c
