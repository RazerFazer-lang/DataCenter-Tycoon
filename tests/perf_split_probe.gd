extends SceneTree
## Trennt die Render-Zeit in CPU- und GPU-Anteil, damit klar ist, ob die Anzahl der Meshes
## (CPU, Draw Calls) oder die Effekte (GPU) bremsen.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/perf_split_probe.gd -- q=3

const WARMUP_SEC := 6.0
const FRAMES := 60


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
		if settings.has_signal("settings_changed"):
			settings.emit_signal("settings_changed")
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(WARMUP_SEC).timeout

	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await process_frame
	await process_frame

	var cpu := 0.0
	var gpu := 0.0
	var setup := 0.0
	var frame := 0.0
	var last := Time.get_ticks_usec()
	for i in range(FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		frame += float(now - last) / 1000.0
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		setup += RenderingServer.get_frame_setup_time_cpu()

	var shadow_lights := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D and (n as Light3D).shadow_enabled and (n as Light3D).visible:
			shadow_lights += 1
		stack.append_array(n.get_children())

	print("SPLIT q=%d frame=%.2fms render_cpu=%.2fms render_gpu=%.2fms setup_cpu=%.2fms draw_calls=%d shadow_lights=%d settings_q=%s" % [
		quality, frame / FRAMES, cpu / FRAMES, gpu / FRAMES, setup / FRAMES,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), shadow_lights,
		str(settings.get("graphics_quality")) if settings != null else "keine",
	])
	quit(0)