extends SceneTree
## Screenshots vom Öffnen des PCs: Host-Sitzung, hinsetzen, dann Bilder in festen Abständen.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/pc_open_shots.gd
## Ausgabe: tests/_shots/open_<ms>.png und Zeilen mit "SHOTS" im Log.

const PROBE_PORT := 7792
const SHOT_TIMES_MS: Array[int] = [50, 200, 400, 700, 1000, 1500, 2200, 3000, 4500, 6500]

var _shot_dir: String = ""


func _initialize() -> void:
	create_timer(50.0).timeout.connect(func() -> void:
		print("SHOTS FEHLER Timer-Abbruch nach 50 s")
		quit(2))
	await process_frame

	_shot_dir = ProjectSettings.globalize_path("res://tests/_shots")
	DirAccess.make_dir_recursive_absolute(_shot_dir)

	var main_scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.0).timeout

	var net: Node = root.get_node_or_null("NetworkManager")
	if net == null:
		print("SHOTS FEHLER NetworkManager fehlt")
		quit(1)
		return
	var err: int = net.call("host_game", "Probe", PROBE_PORT, "Probe-Welt")
	if err != OK:
		print("SHOTS FEHLER host_game err=%d" % err)
		quit(1)
		return

	var world: Node = main_scene.get("world")
	var t0 := Time.get_ticks_msec()
	while world.get("local_player") == null:
		if Time.get_ticks_msec() - t0 > 10000:
			print("SHOTS FEHLER keine Spielfigur")
			quit(1)
			return
		await process_frame
	await create_timer(1.5).timeout

	var state: Node = root.get_node_or_null("PcScreenState")
	var terminal: Control = main_scene.get("terminal_ui") as Control
	main_scene.call("_open_terminal")
	var start := Time.get_ticks_msec()
	for target in SHOT_TIMES_MS:
		while Time.get_ticks_msec() - start < target:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var file := "%s/open_%05d.png" % [_shot_dir, target]
		img.save_png(file)
		print("SHOTS %5d ms phase=%s terminal_visible=%s terminal_alpha=%.2f -> %s" % [
			target, str(state.get("phase")) if state != null else "?",
			str(terminal.visible) if terminal != null else "?",
			terminal.modulate.a if terminal != null else -1.0, file])

	if net.has_method("leave_session"):
		net.call("leave_session")
	main_scene.queue_free()
	for i in 30:
		await process_frame
	print("SHOTS fertig")
	quit(0)