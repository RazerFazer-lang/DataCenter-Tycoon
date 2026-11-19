extends SceneTree
## Misst beim Sitzen am PC GPU- und CPU-Zeit getrennt und schaltet einzelne Teile ab.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/seat_cost_probe.gd

var _vp_rid: RID


func _initialize() -> void:
	create_timer(70.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.5).timeout
	root.get_node("/root/NetworkManager").host_game("Probe", 7794, "Seat Probe")
	await create_timer(4.0).timeout
	await _measure("Stehend in der Welt")

	main_scene.call("_open_terminal")
	await create_timer(8.0).timeout
	var terminal: Control = main_scene.get("terminal_ui")
	await _measure("Am PC, Vollbild offen")
	if terminal != null:
		terminal.visible = false
	await _measure("Am PC, Vollbild versteckt")

	var mirror := _find_by_script(root, "pc_screen_mirror.gd")
	if mirror != null:
		mirror.process_mode = Node.PROCESS_MODE_DISABLED
		var vp := _first_subviewport(mirror)
		if vp != null:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		await _measure("Am PC, 3D-Monitor komplett aus")
		mirror.process_mode = Node.PROCESS_MODE_INHERIT
		if vp != null:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		print("3D-Monitor nicht gefunden")

	var lights := _collect_shadow_lights(root)
	for l in lights:
		l.shadow_enabled = false
	await _measure("Am PC, Schatten aus (%d Lichter)" % lights.size())
	for l in lights:
		l.shadow_enabled = true

	var env_node := _find_world_env(root)
	if env_node != null and env_node.environment != null:
		var env := env_node.environment
		var flags := {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "sdfgi": env.sdfgi_enabled, "ssr": env.ssr_enabled, "glow": env.glow_enabled, "fog_vol": env.volumetric_fog_enabled}
		print("Environment: ", flags)
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		await _measure("Am PC, SSAO/SSIL/SDFGI/SSR/Nebel aus")
	quit(0)


func _find_by_script(n: Node, file_name: String) -> Node:
	var s := n.get_script() as Script
	if s != null and s.resource_path.ends_with(file_name):
		return n
	for c in n.get_children():
		var f := _find_by_script(c, file_name)
		if f != null:
			return f
	return null


func _first_subviewport(n: Node) -> SubViewport:
	for c in n.get_children():
		if c is SubViewport:
			return c
	return null


func _collect_shadow_lights(n: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if n is Light3D and (n as Light3D).shadow_enabled:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_shadow_lights(c))
	return out


func _find_world_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var f := _find_world_env(c)
		if f != null:
			return f
	return null


func _measure(title: String) -> void:
	await create_timer(0.6).timeout
	var frames := PackedFloat64Array()
	var gpu := 0.0
	var cpu := 0.0
	var last := Time.get_ticks_usec()
	for _i in range(90):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
	frames.sort()
	print("%s: Frame-Median %.2f ms, Max %.2f ms, GPU %.2f ms, Render-CPU %.2f ms, Draw-Calls %d" % [
		title, frames[frames.size() / 2], frames[frames.size() - 1], gpu / 90.0, cpu / 90.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])