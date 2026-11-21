extends SceneTree
## Misst, was einzelne Render-Einstellungen pro Frame kosten (Frame-Zeit und reine GPU-Zeit).
## Jede Einstellung wird einzeln abgeschaltet, gemessen und danach wiederhergestellt.
## "aufloesung_50" ist nur ein Test, ob die Pixelmenge der Engpass ist.
## Alle Änderungen gelten nur für diesen Testlauf, settings.cfg bleibt unberührt.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/render_cost_probe.gd -- q=3
## Ausgabe: Zeilen mit "RENDER", Zeiten in ms.

const WARMUP_SEC := 6.0
const SETTLE_SEC := 1.0
const RESTORE_SEC := 0.5
const SAMPLE_FRAMES := 180
const EFFECTS: Array[String] = [
	"sdfgi_enabled",
	"volumetric_fog_enabled",
	"ssr_enabled",
	"ssil_enabled",
	"ssao_enabled",
]


func _initialize() -> void:
	create_timer(58.0).timeout.connect(func() -> void: quit(2))
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
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await create_timer(WARMUP_SEC).timeout

	print("RENDER fenster=%s msaa_3d=%d scaling_mode=%d scale=%.2f" % [
		str(DisplayServer.window_get_size()), int(root.msaa_3d), int(root.scaling_3d_mode), root.scaling_3d_scale,
	])
	await _measure("basis")

	var env := _find_environment()
	if env != null:
		for prop in EFFECTS:
			if not (prop in env) or not bool(env.get(prop)):
				print("RENDER %-24s nicht aktiv" % prop)
				continue
			await _toggle(prop + "_aus",
				func() -> void: env.set(prop, false),
				func() -> void: env.set(prop, true))

	var old_msaa := root.msaa_3d
	await _toggle("msaa_aus",
		func() -> void: root.msaa_3d = Viewport.MSAA_DISABLED,
		func() -> void: root.msaa_3d = old_msaa)

	var old_mode := root.scaling_3d_mode
	await _toggle("fsr2_zu_bilinear",
		func() -> void: root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR,
		func() -> void: root.scaling_3d_mode = old_mode)

	var old_scale := root.scaling_3d_scale
	await _toggle("aufloesung_50",
		func() -> void: root.scaling_3d_scale = 0.5,
		func() -> void: root.scaling_3d_scale = old_scale)
	quit(0)


func _toggle(label: String, apply: Callable, restore: Callable) -> void:
	apply.call()
	await _measure(label)
	restore.call()
	await create_timer(RESTORE_SEC).timeout


func _measure(label: String) -> void:
	await create_timer(SETTLE_SEC).timeout
	var vp_rid := root.get_viewport_rid()
	var times: Array[float] = []
	var gpu_sum := 0.0
	var draw_sum := 0
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		draw_sum += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	print("RENDER %-24s avg=%.2f ms median=%.2f p99=%.2f gpu=%.2f draws=%d" % [
		label,
		total / float(times.size()),
		times[times.size() / 2],
		times[mini(times.size() - 1, int(times.size() * 0.99))],
		gpu_sum / float(SAMPLE_FRAMES),
		draw_sum / SAMPLE_FRAMES,
	])


func _find_environment() -> Environment:
	for n in root.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	var world := root.get_world_3d()
	if world != null and world.environment != null:
		return world.environment
	return null