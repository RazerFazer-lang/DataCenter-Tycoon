extends SceneTree
## Probe: Hängt das Beenden am Abbau der Hauptszene, oder kommen zu wenige Frames?
## Aufruf: godot --path . --script res://tests/quit_probe.gd -- [free]
## Mit "free" wird die Hauptszene vor quit() freigegeben.
## Beendet nach QUIT_AFTER_MS Echtzeit, unabhängig von der Framerate.

const QUIT_AFTER_MS := 8000
const LOG_EVERY_MS := 1000

var _free_first: bool = false
var _scene: Node = null
var _quitting: bool = false
var _t0: int = 0
var _next_log: int = 0
var _frames: int = 0
var _do_showcase: bool = false
var _kill_pending: Array[String] = []


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	_next_log = _t0 + LOG_EVERY_MS
	_free_first = OS.get_cmdline_user_args().has("free")
	if OS.get_cmdline_user_args().has("noscene"):
		print("QUIT_PROBE start noscene (nur Autoloads)")
		return
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("scene="):
			path = arg.substr(6)
	print("QUIT_PROBE szene=", path)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ui="):
			var ui_path: String = arg.substr(3)
			var ui_script: Script = load(ui_path) as Script
			if ui_script == null:
				print("QUIT_PROBE FEHLER: UI-Skript nicht ladbar: ", ui_path)
				quit(1)
				return
			var layer := CanvasLayer.new()
			var ctrl := Control.new()
			ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
			ctrl.set_script(ui_script)
			layer.add_child(ctrl)
			root.add_child(layer)
			_scene = layer
			print("QUIT_PROBE start ui=", ui_path)
			for call_arg in OS.get_cmdline_user_args():
				if call_arg.begins_with("call="):
					var method_name: String = call_arg.substr(5)
					if ctrl.has_method(method_name):
						ctrl.call_deferred(method_name)
						print("QUIT_PROBE call ", method_name)
					else:
						print("QUIT_PROBE FEHLER: Methode fehlt: ", method_name)
			return
	if path == "":
		print("QUIT_PROBE FEHLER: keine main_scene")
		quit(1)
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		print("QUIT_PROBE FEHLER: main_scene nicht ladbar: ", path)
		quit(1)
		return
	_scene = packed.instantiate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("drop="):
			var drop_path: String = arg.substr(5)
			var drop_node: Node = _scene.get_node_or_null(NodePath(drop_path))
			if drop_node == null:
				print("QUIT_PROBE FEHLER: drop-Knoten fehlt: ", drop_path)
			else:
				drop_node.get_parent().remove_child(drop_node)
				drop_node.free()
				print("QUIT_PROBE drop ", drop_path)
	root.add_child(_scene)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("kill="):
			var kill_path: String = arg.substr(5)
			var kill_node: Node = _scene.get_node_or_null(NodePath(kill_path))
			if kill_node == null:
				_kill_pending.append(kill_path)
				print("QUIT_PROBE kill wartet auf ", kill_path)
			else:
				kill_node.get_parent().remove_child(kill_node)
				kill_node.free()
				print("QUIT_PROBE kill ", kill_path)
	if OS.get_cmdline_user_args().has("tree"):
		for child in _scene.get_children():
			print("QUIT_PROBE child ", child.name, " (", child.get_class(), ", ", child.get_child_count(), " Kinder)")
	if OS.get_cmdline_user_args().has("cam"):
		var cam := Camera3D.new()
		cam.fov = 70.0
		root.add_child(cam)
		cam.look_at_from_position(Vector3(3.6, 2.35, 3.2), Vector3(-1.35, 1.25, -2.55), Vector3.UP)
		cam.current = true
		print("QUIT_PROBE cam aktiv")
	_do_showcase = OS.get_cmdline_user_args().has("showcase")
	print("QUIT_PROBE start free_first=", _free_first, " max_fps=", Engine.max_fps,
		" vsync=", DisplayServer.window_get_vsync_mode(),
		" low_proc=", OS.low_processor_usage_mode)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _kill_pending.is_empty() and is_instance_valid(_scene):
		for kp in _kill_pending.duplicate():
			var kn: Node = _scene.get_node_or_null(NodePath(kp))
			if kn != null:
				kn.get_parent().remove_child(kn)
				kn.free()
				_kill_pending.erase(kp)
				print("QUIT_PROBE kill (Frame %d) %s" % [_frames, kp])
	if _frames == 1 and is_instance_valid(_scene):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("killclass="):
				var cls: String = arg.substr(10)
				var victims: Array[Node] = _scene.find_children("*", cls, true, false)
				var freed: int = 0
				for v in victims:
					if is_instance_valid(v):
						v.get_parent().remove_child(v)
						v.free()
						freed += 1
				print("QUIT_PROBE killclass %s: %d Knoten" % [cls, freed])
	if _frames == 30 and is_instance_valid(_scene) and OS.get_cmdline_user_args().has("classes"):
		var counts: Dictionary = {}
		for n in _scene.find_children("*", "", true, false):
			var c: String = n.get_class()
			counts[c] = int(counts.get(c, 0)) + 1
		for c in counts:
			print("QUIT_PROBE class ", c, " x", counts[c])
	if _frames == 30 and is_instance_valid(_scene) and OS.get_cmdline_user_args().has("tree"):
		for child in _scene.get_children():
			print("QUIT_PROBE child30 ", child.name, " (", child.get_class(), ", ", child.get_child_count(), " Kinder)")
	if _do_showcase and _frames == 10:
		_do_showcase = false
		if is_instance_valid(_scene) and _scene.has_method("show_menu_showcase"):
			_scene.call("show_menu_showcase")
			print("QUIT_PROBE showcase aufgerufen (Frame 10)")
		else:
			print("QUIT_PROBE FEHLER: Szene hat kein show_menu_showcase")
	var now: int = Time.get_ticks_msec()
	if now >= _next_log:
		_next_log = now + LOG_EVERY_MS
		print("QUIT_PROBE t=%d ms frames=%d fps=%.1f focus=%s mode=%d" % [
			now - _t0, _frames, Engine.get_frames_per_second(),
			str(DisplayServer.window_is_focused()), DisplayServer.window_get_mode()])
	if _quitting or now - _t0 < QUIT_AFTER_MS:
		return false
	_quitting = true
	_finish()
	return false


func _finish() -> void:
	if _free_first and is_instance_valid(_scene):
		_scene.queue_free()
		for i in 30:
			await process_frame
	print("QUIT_PROBE orphans:")
	Node.print_orphan_nodes()
	print("QUIT_PROBE quit() aufgerufen nach %d ms, frames=%d" % [Time.get_ticks_msec() - _t0, _frames])
	quit(0)


func _finalize() -> void:
	print("QUIT_PROBE _finalize nach %d ms" % [Time.get_ticks_msec() - _t0])