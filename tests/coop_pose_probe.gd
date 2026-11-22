extends SceneTree
## Prüft im echten Ablauf, ob sich Host und Client gegenseitig sehen.
## Aufruf (zwei Prozesse, Host zuerst):
##   godot --path . --resolution 1280x720 --script res://tests/coop_pose_probe.gd -- role=host
##   godot --path . --resolution 1280x720 --script res://tests/coop_pose_probe.gd -- role=join
## Ausgabe: Zeilen mit "COOP <rolle>". Exit-Code 0 = alles ok, 1 = mindestens eine Prüfung fehlgeschlagen.

const PROBE_PORT := 7795
const MOVE_SECONDS := 8.0
const HOST_LINGER_SECONDS := 4.0

var _role := "host"
var _failed := false
var _other: Node3D = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw).strip_edges()
		if a.begins_with("role="):
			_role = a.substr(5)

	create_timer(45.0).timeout.connect(func() -> void:
		print("COOP %s FEHLER Timer-Abbruch nach 45 s" % _role)
		quit(2))
	await process_frame

	var main_scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	# Ladebildschirm (2.4 s) abwarten.
	await create_timer(3.0).timeout

	var net: Node = root.get_node_or_null("NetworkManager")
	var settings: Node = root.get_node_or_null("SettingsManager")
	if net == null:
		print("COOP %s FEHLER Autoload NetworkManager fehlt" % _role)
		quit(1)
		return
	# host_game speichert den Spielernamen in settings.cfg, deshalb am Ende zurücksetzen.
	var old_name := str(settings.get("player_name")) if settings != null else ""

	var err: int
	if _role == "host":
		err = net.call("host_game", "ProbeHost", PROBE_PORT, "Probe-Welt")
	else:
		err = net.call("join_game", "127.0.0.1", "ProbeClient", PROBE_PORT, "")
	_check(err == OK, "%s (err=%d)" % ["host_game" if _role == "host" else "join_game", err])
	if err != OK:
		await _finish(main_scene, net, settings, old_name)
		return

	var world: Node = main_scene.get("world")
	var t_me: float = await _wait_for(func() -> bool: return world.get("local_player") != null, 15.0)
	_check(t_me >= 0.0, "eigene Figur gespawnt (%.2f s)" % t_me)
	if t_me < 0.0:
		await _finish(main_scene, net, settings, old_name)
		return

	var me: Node3D = world.get("local_player") as Node3D
	var my_id: int = root.multiplayer.get_unique_id()
	print("COOP %s INFO meine peer_id=%d" % [_role, my_id])

	var t_other: float = await _wait_for(func() -> bool:
		_other = _find_other(world, my_id)
		return _other != null, 20.0)
	_check(t_other >= 0.0, "fremde Figur vorhanden (%.2f s)" % t_other)
	if _other == null:
		_dump_players(world)
		await _finish(main_scene, net, settings, old_name)
		return

	_report_other("Start")
	var other_start := _other.global_position

	# Im Kreis laufen, damit Positionen verschickt werden und die Gegenseite eine Bewegung sieht.
	var base := me.global_position
	var max_dist := 0.0
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < MOVE_SECONDS:
		var t := float(Time.get_ticks_msec() - t0) / 1000.0
		me.global_position = base + Vector3(sin(t * 1.5) * 1.5, 0.0, cos(t * 1.5) * 1.5)
		if is_instance_valid(_other):
			max_dist = maxf(max_dist, _other.global_position.distance_to(other_start))
		await process_frame

	if not is_instance_valid(_other):
		_check(false, "fremde Figur während des Laufs gelöscht")
	else:
		_report_other("Ende")
		_check(max_dist > 0.5, "fremde Figur bewegt sich (max. %.2f m vom Start)" % max_dist)

	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var cam_path := str(cam.get_path()) if cam != null else "<keine>"
	_check(cam != null and me.is_ancestor_of(cam), "aktive Kamera gehört zur eigenen Figur (%s)" % cam_path)

	if _role == "host":
		await create_timer(HOST_LINGER_SECONDS).timeout
	await _finish(main_scene, net, settings, old_name)


func _find_other(world: Node, my_id: int) -> Node3D:
	var nodes: Variant = world.get("_player_nodes")
	if not (nodes is Dictionary):
		return null
	for pid in (nodes as Dictionary).keys():
		var node: Variant = nodes[pid]
		if int(pid) != my_id and is_instance_valid(node):
			return node as Node3D
	return null


func _dump_players(world: Node) -> void:
	var nodes: Variant = world.get("_player_nodes")
	var keys: Array = (nodes as Dictionary).keys() if nodes is Dictionary else []
	var net: Node = root.get_node_or_null("NetworkManager")
	var roster: Array = (net.get("players") as Dictionary).keys() if net != null else []
	print("COOP %s INFO _player_nodes=%s, NetworkManager.players=%s" % [_role, keys, roster])


func _report_other(label: String) -> void:
	var avatar: Variant = _other.get("_avatar_root")
	var avatar_vis := "?"
	if avatar is Node3D:
		avatar_vis = str((avatar as Node3D).is_visible_in_tree())
	print("COOP %s INFO %s: fremd peer=%s pos=%s im_baum=%s sichtbar=%s avatar_sichtbar=%s is_local=%s parent=%s" % [
		_role, label, _other.get("peer_id"), _other.global_position, _other.is_inside_tree(),
		_other.is_visible_in_tree(), avatar_vis, _other.get("is_local"), _other.get_parent().get_path()])


func _check(ok: bool, label: String) -> void:
	print("COOP %s %s %s" % [_role, "OK    " if ok else "FEHLER", label])
	if not ok:
		_failed = true


func _wait_for(cond: Callable, timeout: float) -> float:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			return -1.0
		await process_frame
	return float(Time.get_ticks_msec() - t0) / 1000.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(main_scene: Node, net: Node, settings: Node, old_name: String) -> void:
	if net.has_method("leave_session"):
		net.call("leave_session")
	if settings != null and not old_name.is_empty():
		settings.set("player_name", old_name)
		if settings.has_method("save_settings"):
			settings.call("save_settings")
	main_scene.queue_free()
	await _frames(30)
	print("COOP %s ERGEBNIS %s" % [_role, "FEHLGESCHLAGEN" if _failed else "ALLES OK"])
	quit(1 if _failed else 0)