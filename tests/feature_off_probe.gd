extends SceneTree
## Misst in EINEM frischen Prozess die GPU-Zeit mit allen Effekten und danach mit genau einem abgeschalteten Effekt.
## Ein eigener Prozess pro Effekt verhindert, dass vorheriges Umschalten die Messung verfälscht.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/feature_off_probe.gd -- q=3 off=sdfgi

const WARMUP_SEC := 7.0
const SETTLE_SEC := 1.5
const MEASURE_SEC := 3.0


func _initialize() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	var quality := 3
	var off := "none"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("q="):
			quality = clampi(int(arg.substr(2)), 0, 3)
		elif arg.begins_with("off="):
			off = arg.substr(4)
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
	await create_timer(WARMUP_SEC).timeout

	var before := await _measure_gpu(rid)
	var applied := _apply_off(off)
	await create_timer(SETTLE_SEC).timeout
	var after := await _measure_gpu(rid)
	print("OFF q=%d %-14s geaendert=%d vorher=%.1fms nachher=%.1fms gespart=%.1fms" % [
		quality, off, applied, before, after, before - after,
	])
	quit(0)


func _measure_gpu(rid: RID) -> float:
	await process_frame
	var total := 0.0
	var frames := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(MEASURE_SEC * 1000.0):
		await process_frame
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		frames += 1
	return total / maxf(1.0, float(frames))


func _apply_off(off: String) -> int:
	var nodes: Array[Node] = []
	_collect(root, nodes)
	var env: Environment = null
	for n in nodes:
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			env = (n as WorldEnvironment).environment
			break

	var names: PackedStringArray = [off]
	if off == "all":
		names = ["sdfgi", "vol_fog", "ssr", "ssil", "ssao", "glow", "taa", "omni_shadows", "sun_shadow", "probes", "subviewports", "sky_radiance"]

	var changed := 0
	for name in names:
		match name:
			"sdfgi", "vol_fog", "ssr", "ssil", "ssao", "glow":
				if env != null:
					var prop := {"sdfgi": "sdfgi_enabled", "vol_fog": "volumetric_fog_enabled", "ssr": "ssr_enabled",
						"ssil": "ssil_enabled", "ssao": "ssao_enabled", "glow": "glow_enabled"}[name] as String
					if env.get(prop):
						env.set(prop, false)
						changed += 1
			"sky_radiance":
				if env != null and env.sky != null:
					env.sky.radiance_size = Sky.RADIANCE_SIZE_32
					changed += 1
			"taa":
				if root.use_taa:
					root.use_taa = false
					changed += 1
			"half_res":
				root.scaling_3d_scale = 0.5
				changed += 1
			"omni_shadows":
				for n in nodes:
					if (n is OmniLight3D or n is SpotLight3D) and (n as Light3D).shadow_enabled:
						(n as Light3D).shadow_enabled = false
						changed += 1
			"sun_shadow":
				for n in nodes:
					if n is DirectionalLight3D and (n as Light3D).shadow_enabled:
						(n as Light3D).shadow_enabled = false
						changed += 1
			"probes":
				for n in nodes:
					if n is ReflectionProbe and (n as ReflectionProbe).visible:
						(n as ReflectionProbe).visible = false
						changed += 1
			"subviewports":
				for n in nodes:
					if n is SubViewport:
						(n as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
						changed += 1
	return changed


func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for child in node.get_children():
		_collect(child, out)