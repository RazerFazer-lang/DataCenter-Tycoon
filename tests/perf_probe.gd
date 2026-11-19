extends SceneTree
## Misst Frame-Zeiten im Hauptmenü-Showcase (bewegte Kamera) bei einer Grafikstufe.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/perf_probe.gd -- q=3
## Ausgabe: Frame-Zeiten, Skriptzeit pro Frame, Draw Calls, Objekte und Anzahl der Meshes/Lichter.

const WARMUP_SEC := 6.0
const MEASURE_USEC := 8_000_000
const SPIKE_MS := 33.3


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
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
	await create_timer(WARMUP_SEC).timeout

	var times := PackedFloat32Array()
	var process_total := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < MEASURE_USEC:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		process_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		last = now
	if times.is_empty():
		print("PERF keine Frames gemessen")
		quit(1)
		return

	var total := 0.0
	var spikes := 0
	for t in times:
		total += t
		if t > SPIKE_MS:
			spikes += 1
	var sorted := times.duplicate()
	sorted.sort()
	var p99 := sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	print("PERF q=%d frames=%d avg=%.2fms fps=%.0f p99=%.2fms max=%.2fms spikes>33ms=%d script=%.2fms" % [
		quality, times.size(), total / times.size(), 1000.0 * times.size() / total,
		p99, sorted[sorted.size() - 1], spikes, process_total / times.size(),
	])
	print("PERF q=%d draw_calls=%d objects=%d primitives=%d" % [
		quality,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])

	var counts := {"mesh": 0, "multimesh": 0, "lights": 0, "shadow_lights": 0, "probes": 0, "particles": 0, "audio3d": 0}
	_count_nodes(root, counts)
	print("PERF q=%d meshes=%d multimesh=%d lights=%d shadow_lights=%d probes=%d particles=%d audio3d=%d" % [
		quality, counts["mesh"], counts["multimesh"], counts["lights"], counts["shadow_lights"],
		counts["probes"], counts["particles"], counts["audio3d"],
	])
	quit(0)


func _count_nodes(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		counts["mesh"] += 1
	elif node is MultiMeshInstance3D:
		counts["multimesh"] += 1
	elif node is Light3D:
		counts["lights"] += 1
		var light := node as Light3D
		if light.shadow_enabled and light.visible:
			counts["shadow_lights"] += 1
	elif node is ReflectionProbe:
		counts["probes"] += 1
	elif node is GPUParticles3D or node is CPUParticles3D:
		counts["particles"] += 1
	elif node is AudioStreamPlayer3D:
		counts["audio3d"] += 1
	for child in node.get_children():
		_count_nodes(child, counts)