extends SceneTree
## Misst, was Schatten der Deckenlampen kosten, wenn sich die Lüfter drehen bzw. stehen.
## Varianten: 4 bzw. 6 Lampen mit Schatten, jeweils mit drehenden und angehaltenen Lüftern.
## "Lüfter aus" schaltet _process der Skripte ab, die Lüfter drehen (rack_prop, cooler_prop, garage_builder).
## rl=1/2 schaltet Halle B/C frei und setzt eine eigene Kamera zwischen Halle B und C,
## damit die Schatten der Lampen 2-5 innerhalb der Schatten-Ausblendung (9 m) liegen.
## Alle Änderungen gelten nur für diesen Testlauf, settings.cfg und Spielstände bleiben unberührt.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/shadow_probe.gd -- q=3 rl=2
## Ausgabe: Zeilen mit "SHADOW", Zeiten in ms.

const WARMUP_SEC := 6.0
const SETTLE_SEC := 1.5
const ROOM_SETTLE_SEC := 0.5
const SAMPLE_FRAMES := 240
const DEFAULT_SHADOW_LAMPS := 4
const SPIN_SCRIPTS: Array[String] = ["rack_prop.gd", "cooler_prop.gd", "garage_builder.gd"]
const HALL_CAM_POS := Vector3(13.0, 2.2, 0.3)
const HALL_CAM_TARGET := Vector3(17.0, 1.0, 0.3)


func _initialize() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(2))
	var quality := 3
	var room_level := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("q="):
			quality = clampi(int(arg.substr(2)), 0, 3)
		elif arg.begins_with("rl="):
			room_level = clampi(int(arg.substr(3)), 0, 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var settings := root.get_node_or_null("SettingsManager")
	if settings != null:
		settings.set("graphics_quality", quality)

	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(WARMUP_SEC).timeout

	var garage := _find_by_script("garage_builder.gd")
	if garage == null:
		print("SHADOW garage_builder nicht gefunden")
		quit(1)
		return
	var lights: Array = garage.get("_ceiling_lights")
	if lights == null or lights.is_empty():
		print("SHADOW keine Deckenlampen gefunden")
		quit(1)
		return
	if room_level > 0:
		_unlock_halls(garage, room_level)
		await create_timer(ROOM_SETTLE_SEC).timeout
	_print_lamps(lights)

	var default_lamps := lights.size() if quality >= 3 else (DEFAULT_SHADOW_LAMPS if quality >= 2 else 0)
	await _measure("%d_schatten_luefter_an" % default_lamps)
	_set_shadow_lamps(lights, lights.size())
	await _measure("%d_schatten_luefter_an" % lights.size())
	_set_spin(false)
	await _measure("%d_schatten_luefter_aus" % lights.size())
	_set_shadow_lamps(lights, default_lamps)
	await _measure("%d_schatten_luefter_aus" % default_lamps)
	quit(0)


func _unlock_halls(garage: Node, level: int) -> void:
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		print("SHADOW GameState nicht gefunden")
		return
	game_state.set("room_level", level)
	if garage.has_method("set_room_level"):
		garage.call("set_room_level", level)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = HALL_CAM_POS
	cam.look_at(HALL_CAM_TARGET, Vector3.UP)
	cam.make_current()
	print("SHADOW room_level=%d, eigene Kamera gesetzt" % level)


func _measure(label: String) -> void:
	await create_timer(SETTLE_SEC).timeout
	var times: Array[float] = []
	var draw_sum := 0
	var last := Time.get_ticks_usec()
	for i in range(SAMPLE_FRAMES):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		draw_sum += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	print("SHADOW %-26s avg=%.2f ms median=%.2f p99=%.2f draws=%d" % [
		label,
		total / float(times.size()),
		times[times.size() / 2],
		times[mini(times.size() - 1, int(times.size() * 0.99))],
		draw_sum / SAMPLE_FRAMES,
	])


func _set_shadow_lamps(lights: Array, count: int) -> void:
	for i in range(lights.size()):
		(lights[i] as Light3D).shadow_enabled = i < count


func _set_spin(enabled: bool) -> void:
	var changed := 0
	for n in root.find_children("*", "", true, false):
		var s: Variant = (n as Node).get_script()
		if s is Script and SPIN_SCRIPTS.has((s as Script).resource_path.get_file()):
			(n as Node).set_process(enabled)
			changed += 1
	print("SHADOW lüfter %s: %d Nodes" % ["an" if enabled else "angehalten", changed])


func _print_lamps(lights: Array) -> void:
	for i in range(lights.size()):
		var l := lights[i] as SpotLight3D
		print("SHADOW lampe %d sichtbar=%s schatten=%s energie=%.2f pos=%s" % [
			i, str(l.is_visible_in_tree()), str(l.shadow_enabled), l.light_energy, str(l.global_position),
		])
	var cam := root.get_camera_3d()
	if cam != null:
		print("SHADOW kamera pos=%s" % str(cam.global_position))


func _find_by_script(file_name: String) -> Node:
	for n in root.find_children("*", "", true, false):
		var s: Variant = (n as Node).get_script()
		if s is Script and (s as Script).resource_path.get_file() == file_name:
			return n
	return null