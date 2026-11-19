extends SceneTree
## Prüft den echten PC-Ablauf im Spiel: Host-Sitzung, hinsetzen, hochfahren, Desktop, herunterfahren.
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/boot_flow_probe.gd
## Ausgabe: Zeilen mit "BOOT" im Log. Exit-Code 0 = alles ok, 1 = mindestens eine Prüfung fehlgeschlagen.

const MIRROR_SCRIPT := "res://scripts/world/pc_screen_mirror.gd"
const PROBE_PORT := 7791

var _failed := false


func _initialize() -> void:
	create_timer(55.0).timeout.connect(func() -> void:
		print("BOOT FEHLER Timer-Abbruch nach 55 s")
		quit(2))
	await process_frame

	var main_scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	# Ladebildschirm (2.4 s) abwarten, damit er die Sitzung nicht überlagert.
	await create_timer(3.0).timeout

	var net: Node = root.get_node_or_null("NetworkManager")
	var state: Node = root.get_node_or_null("PcScreenState")
	if net == null or state == null:
		print("BOOT FEHLER Autoloads fehlen (NetworkManager/PcScreenState)")
		quit(1)
		return

	var err: int = net.call("host_game", "Probe", PROBE_PORT, "Probe-Welt")
	_check(err == OK, "host_game (err=%d)" % err)
	if err != OK:
		await _finish(main_scene, net)
		return

	var world: Node = main_scene.get("world")
	var t_player: float = await _wait_for(func() -> bool: return world.get("local_player") != null, 10.0)
	_check(t_player >= 0.0, "Spielfigur gespawnt (%.2f s)" % t_player)
	if t_player < 0.0:
		await _finish(main_scene, net)
		return
	await create_timer(1.0).timeout

	var mirror: Node = _find_by_script(main_scene, MIRROR_SCRIPT)
	_check(mirror != null, "PcScreenMirror gefunden")
	if mirror == null:
		await _finish(main_scene, net)
		return
	var off_node: CanvasItem = mirror.get("_off") as CanvasItem
	var terminal: Control = main_scene.get("terminal_ui") as Control

	# 1) Ausgangslage: PC aus, Monitor schwarz
	_check(str(state.get("phase")) == "idle", "Start: phase=idle (ist %s)" % state.get("phase"))
	_check(off_node != null and off_node.visible, "Start: Monitor zeigt Aus-Bild")
	_sample(mirror, "aus")

	# 2) Hinsetzen wie im Spiel (E am Schreibtisch): main._open_terminal()
	main_scene.call("_open_terminal")
	await create_timer(0.6).timeout
	_check(str(state.get("phase")) == "boot", "Hinsetzen: phase=boot (ist %s)" % state.get("phase"))
	_check(off_node != null and not off_node.visible, "Hinsetzen: Monitor ist an")
	_sample(mirror, "boot")

	# 3) Hochfahren bis Desktop (Kaltstart 5.6 s + Kamerafahrt)
	var t_desk: float = await _wait_for(func() -> bool: return str(state.get("phase")) == "desktop", 15.0)
	_check(t_desk >= 0.0, "Hochgefahren: phase=desktop nach %.2f s" % t_desk)
	_check(terminal != null and terminal.visible, "Vollbild-Terminal ist offen")
	_check(off_node != null and not off_node.visible, "Desktop: Monitor ist an")
	_sample(mirror, "desktop")

	# 4) Herunterfahren über das Startmenü
	terminal.call("_shut_down_pc")
	await create_timer(0.3).timeout
	_check(str(state.get("phase")) == "shutdown", "Herunterfahren: phase=shutdown (ist %s)" % state.get("phase"))
	var t_idle: float = await _wait_for(func() -> bool: return str(state.get("phase")) == "idle", 8.0)
	_check(t_idle >= 0.0, "Heruntergefahren: phase=idle nach %.2f s" % t_idle)
	# Die Schließ-Animation läuft nach dem Wechsel auf idle noch kurz weiter.
	var t_closed: float = await _wait_for(func() -> bool: return terminal != null and not terminal.visible, 3.0)
	_check(t_closed >= 0.0, "Terminal geschlossen nach %.2f s" % t_closed)
	# Der Spiegel muss das Aus-Bild sofort zeigen, nicht erst nach dem Idle-Intervall (1 s).
	var t_off: float = await _wait_for(func() -> bool: return off_node != null and off_node.visible, 0.3)
	_check(t_off >= 0.0, "Aus: Monitor zeigt Aus-Bild nach %.2f s" % t_off)
	_sample(mirror, "aus_danach")

	await _finish(main_scene, net)


func _check(ok: bool, label: String) -> void:
	print("BOOT %s %s" % ["OK    " if ok else "FEHLER", label])
	if not ok:
		_failed = true


## Mittelpixel des Monitor-Viewports, nur zur Information (bei offenem Vollbild kann das Bild pausieren).
func _sample(mirror: Node, label: String) -> void:
	var vp: SubViewport = _find_subviewport(mirror)
	if vp == null:
		print("BOOT INFO %s: kein SubViewport gefunden" % label)
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		print("BOOT INFO %s: Viewport-Bild leer" % label)
		return
	var c: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	print("BOOT INFO %s: Viewport-Mitte (%.3f, %.3f, %.3f)" % [label, c.r, c.g, c.b])


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


func _find_by_script(node: Node, path: String) -> Node:
	var scr: Script = node.get_script() as Script
	if scr != null and scr.resource_path == path:
		return node
	for child in node.get_children():
		var hit := _find_by_script(child, path)
		if hit != null:
			return hit
	return null


func _find_subviewport(node: Node) -> SubViewport:
	for child in node.get_children():
		if child is SubViewport:
			return child as SubViewport
		var hit := _find_subviewport(child)
		if hit != null:
			return hit
	return null


func _finish(main_scene: Node, net: Node) -> void:
	if net.has_method("leave_session"):
		net.call("leave_session")
	main_scene.queue_free()
	await _frames(5)
	print("BOOT ERGEBNIS " + ("FEHLGESCHLAGEN" if _failed else "ALLES OK"))
	quit(1 if _failed else 0)