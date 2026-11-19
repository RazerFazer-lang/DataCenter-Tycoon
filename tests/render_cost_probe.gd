extends SceneTree
## Findet heraus, welcher Grafikeffekt pro Frame am meisten Zeit kostet.
## Jeder Effekt wird einzeln abgeschaltet, die Frame-Zeit (Median) gemessen und der Effekt wieder eingeschaltet.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/render_cost_probe.gd -- q=3

const WARMUP_SEC := 5.0
const FRAMES_PER_SAMPLE := 10


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
	await create_timer(WARMUP_SEC).timeout

	print("RENDER gpu=%s vendor=%s typ=%d viewport=%s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		int(RenderingServer.get_video_adapter_type()), str(root.get_visible_rect().size),
	])

	var nodes := {"env": [], "lights": [], "probes": [], "viewports": []}
	_collect(root, nodes)
	var env: Environment = null
	if not (nodes["env"] as Array).is_empty():
		env = (nodes["env"][0] as WorldEnvironment).environment

	var toggles := {}
	if env != null:
		if env.sky != null:
			print("RENDER sky process_mode=%d radiance_size=%d material=%s" % [
				int(env.sky.process_mode), int(env.sky.radiance_size), env.sky.sky_material.get_class() if env.sky.sky_material != null else "null",
			])
			toggles["himmel_shader"] = [[env.sky, "sky_material", ProceduralSkyMaterial.new()]]
			toggles["himmel_radiance_32"] = [[env.sky, "radiance_size", Sky.RADIANCE_SIZE_32]]
		toggles["sdfgi"] = [[env, "sdfgi_enabled", false]]
		toggles["vol_fog"] = [[env, "volumetric_fog_enabled", false]]
		toggles["ssr"] = [[env, "ssr_enabled", false]]
		toggles["ssil"] = [[env, "ssil_enabled", false]]
		toggles["ssao"] = [[env, "ssao_enabled", false]]
		toggles["glow"] = [[env, "glow_enabled", false]]
	toggles["msaa"] = [[root, "msaa_3d", Viewport.MSAA_DISABLED]]
	var shadow_list: Array = []
	for l in nodes["lights"]:
		shadow_list.append([l, "shadow_enabled", false])
	toggles["schatten"] = shadow_list
	var probe_list: Array = []
	for p in nodes["probes"]:
		probe_list.append([p, "visible", false])
	toggles["reflection_probes"] = probe_list
	var vp_list: Array = []
	for v in nodes["viewports"]:
		vp_list.append([v, "render_target_update_mode", SubViewport.UPDATE_DISABLED])
	toggles["subviewports"] = vp_list
	var all_list: Array = []
	for key in toggles.keys():
		all_list.append_array(toggles[key])
	toggles["ALLES"] = all_list

	print("RENDER lichter_mit_schatten=%d probes=%d subviewports=%d" % [shadow_list.size(), probe_list.size(), vp_list.size()])

	var baseline := await _measure()
	print("RENDER q=%d baseline=%.2fms" % [quality, baseline])
	for key in toggles.keys():
		var entries: Array = toggles[key]
		if entries.is_empty():
			continue
		var originals: Array = []
		for e in entries:
			originals.append(e[0].get(e[1]))
			e[0].set(e[1], e[2])
		var t := await _measure()
		for i in range(entries.size()):
			entries[i][0].set(entries[i][1], originals[i])
		print("RENDER %-20s aus: %7.2fms  gespart: %7.2fms" % [key, t, baseline - t])
	quit(0)


func _collect(node: Node, nodes: Dictionary) -> void:
	if node is WorldEnvironment:
		nodes["env"].append(node)
	elif node is Light3D and (node as Light3D).shadow_enabled:
		nodes["lights"].append(node)
	elif node is ReflectionProbe and (node as ReflectionProbe).visible:
		nodes["probes"].append(node)
	elif node is SubViewport:
		nodes["viewports"].append(node)
	for child in node.get_children():
		_collect(child, nodes)


## Median der Frame-Zeit in ms
func _measure() -> float:
	await process_frame
	await process_frame
	var frame := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in range(FRAMES_PER_SAMPLE):
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append(float(now - last) / 1000.0)
		last = now
	frame.sort()
	return frame[frame.size() / 2]