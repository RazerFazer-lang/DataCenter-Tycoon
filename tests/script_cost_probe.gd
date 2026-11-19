extends SceneTree
## Findet heraus, welche Skripte pro Frame am meisten Zeit kosten.
## Gemessen wird die Skriptzeit (Performance.TIME_PROCESS) als Median über eine feste Anzahl Frames,
## einmal mit allen Skripten, einmal ohne alle, dann je Skriptart abgeschaltet.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/script_cost_probe.gd -- q=3

const WARMUP_SEC := 5.0
const FRAMES_PER_SAMPLE := 8


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

	var groups := {}
	_collect(root, groups)

	var baseline := await _measure()
	print("COST q=%d baseline script=%.2fms frame=%.2fms groups=%d" % [quality, baseline.x, baseline.y, groups.size()])

	for path in groups.keys():
		_set_group(groups[path], false)
	var none := await _measure()
	for path in groups.keys():
		_set_group(groups[path], true)
	print("COST q=%d alle_aus script=%.2fms frame=%.2fms" % [quality, none.x, none.y])

	var results: Array = []
	for path in groups.keys():
		_set_group(groups[path], false)
		var t := await _measure()
		_set_group(groups[path], true)
		results.append({"path": path, "count": (groups[path] as Array).size(), "saved": baseline.x - t.x})

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["saved"] > b["saved"])
	for r in results:
		print("COST %7.2fms  x%-4d %s" % [r["saved"], r["count"], r["path"]])
	quit(0)


func _set_group(nodes: Array, enabled: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.set_process(enabled)
			n.set_physics_process(enabled)


func _collect(node: Node, groups: Dictionary) -> void:
	var script := node.get_script() as Script
	if script != null and node != current_scene and (node.is_processing() or node.is_physics_processing()):
		var key := script.resource_path if script.resource_path != "" else "<inline>"
		if not groups.has(key):
			groups[key] = []
		groups[key].append(node)
	for child in node.get_children():
		_collect(child, groups)


## x = Median der Skriptzeit in ms, y = Median der Frame-Zeit in ms
func _measure() -> Vector2:
	await process_frame
	var proc := PackedFloat32Array()
	var frame := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in range(FRAMES_PER_SAMPLE):
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append(float(now - last) / 1000.0)
		last = now
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	proc.sort()
	frame.sort()
	return Vector2(proc[proc.size() / 2], frame[frame.size() / 2])