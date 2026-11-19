extends SceneTree
## Startet das Spiel mit Fenster, setzt den Spieler an den PC, speichert Bildschirmfotos
## und misst die Frame-Zeiten mit echtem Rendering.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/visual_probe.gd

const SHOT_TIMES_MS: Array[int] = [300, 1000, 1700, 2300, 6500]
const SHOT_DIR := "res://tests/shots"


func _initialize() -> void:
	create_timer(50.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(1.0).timeout
	_shot("0_ladebildschirm")
	await create_timer(2.8).timeout
	_shot("1_hauptmenue")

	var net := root.get_node("/root/NetworkManager")
	net.host_game("Probe", 7792, "Visual Probe")
	await create_timer(2.0).timeout
	_shot("2_welt")
	await _measure("Frames in der Welt", 4.0)

	main_scene.call("_open_terminal")
	var start := Time.get_ticks_msec()
	for t in SHOT_TIMES_MS:
		var wait := float(t - (Time.get_ticks_msec() - start)) / 1000.0
		if wait > 0.0:
			await create_timer(wait).timeout
		_shot("3_sitzen_%04dms" % t)
	await _measure("Frames am PC", 4.0)
	quit(0)


func _shot(shot_name: String) -> void:
	var tex := root.get_texture()
	var img := tex.get_image() if tex != null else null
	if img == null:
		print("SHOT FEHLT ", shot_name)
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [SHOT_DIR, shot_name])
	img.save_png(path)
	print("SHOT ", path)


func _measure(title: String, seconds: float) -> void:
	var times := PackedFloat64Array()
	var stamps := PackedInt64Array()
	var begin := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - begin < int(seconds * 1000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		stamps.append(Time.get_ticks_msec() - begin)
		last = now
	if times.is_empty():
		print("%s: keine Frames" % title)
		return
	var sorted := times.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var worst := sorted[sorted.size() - 1]
	var spikes: Array[String] = []
	for i in range(times.size()):
		if times[i] > median * 1.8 and times[i] > 4.0:
			spikes.append("%d ms@%.1f" % [stamps[i], times[i]])
	print("%s: %d Frames, Median %.2f ms, Maximum %.2f ms, Spitzen %d" % [title, times.size(), median, worst, spikes.size()])
	if not spikes.is_empty():
		print("  Spitzen (Zeitpunkt@Dauer): ", ", ".join(spikes.slice(0, 30)))