extends SceneTree
## Zeichnet pro Sekunde FPS, GPU-Zeit und Kameraposition auf.
## Zeigt, ob die Kosten nach dem Start abklingen (Aufwärmen) oder von der Kamerafahrt abhängen.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/perf_timeline_probe.gd -- q=3

const SECONDS := 40


func _initialize() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(2))
	var quality := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("q="):
			quality = clampi(int(arg.substr(2)), 0, 3)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var settings := root.get_node_or_null("SettingsManager")
	if settings != null:
		settings.set("graphics_quality", quality)
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)

	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	var start := Time.get_ticks_msec()
	for sec in range(SECONDS):
		var frames := 0
		var gpu := 0.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		while Time.get_ticks_msec() - start < (sec + 1) * 1000:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, float(now - last) / 1000.0)
			last = now
			frames += 1
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var cam := root.get_camera_3d()
		var cam_pos := cam.global_position if cam != null else Vector3.ZERO
		print("TL t=%02d fps=%d gpu=%.1fms worst=%.1fms cam=(%.1f, %.1f, %.1f)" % [
			sec, frames, gpu / maxf(1.0, float(frames)), worst, cam_pos.x, cam_pos.y, cam_pos.z,
		])
	quit(0)