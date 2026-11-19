extends SceneTree
## Misst am PC die Frame-Zeit und schaltet nacheinander Teile ab, um den teuren Teil zu finden.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/pc_cost_probe.gd


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.5).timeout
	root.get_node("/root/NetworkManager").host_game("Probe", 7793, "Cost Probe")
	await create_timer(4.0).timeout
	main_scene.call("_open_terminal")
	await create_timer(8.0).timeout

	var terminal: Control = main_scene.get("terminal_ui")
	await _measure("PC offen (Desktop)")

	var mirror := _find_mirror(root)
	if mirror != null:
		mirror.process_mode = Node.PROCESS_MODE_DISABLED
		await _measure("PC offen, 3D-Monitor angehalten")
		mirror.process_mode = Node.PROCESS_MODE_INHERIT

	root.get_viewport().disable_3d = true
	await _measure("PC offen, 3D-Welt nicht gerendert")
	root.get_viewport().disable_3d = false

	if terminal != null:
		terminal.process_mode = Node.PROCESS_MODE_DISABLED
		await _measure("PC offen, TerminalUI._process aus")
		terminal.process_mode = Node.PROCESS_MODE_INHERIT
		terminal.visible = false
		await _measure("TerminalUI unsichtbar")
	quit(0)


func _find_mirror(n: Node) -> Node:
	if n is PcScreenMirror:
		return n
	for c in n.get_children():
		var f := _find_mirror(c)
		if f != null:
			return f
	return null


func _measure(title: String) -> void:
	await create_timer(0.5).timeout
	var times := PackedFloat64Array()
	var proc := 0.0
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for _i in range(90):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	print("%s: Median %.2f ms, Max %.2f ms, Script-Process %.2f ms, Draw-Calls %.0f, Nodes %d" % [
		title, times[times.size() / 2], times[times.size() - 1], proc / 90.0, draws / 90.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])