extends SceneTree
## Prüft den PC-Ablauf: Hinsetzen fährt hoch, Aufstehen lässt den PC an, nur "Herunterfahren" schaltet ihn aus.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/pc_power_probe.gd

var _fails: int = 0


func _initialize() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(3.5).timeout
	root.get_node("/root/NetworkManager").host_game("Probe", 7795, "Power Probe")
	await create_timer(3.0).timeout
	var pcs: Node = root.get_node("/root/PcScreenState")
	var terminal: Control = main_scene.get("terminal_ui")
	_check("PC ist beim Spielstart aus", pcs.get("phase") == "idle")

	main_scene.call("_open_terminal")
	await create_timer(0.5).timeout
	_check("Hinsetzen startet den Kaltstart", pcs.get("phase") == "boot" and bool(pcs.get("cold_boot")))
	await create_timer(9.0).timeout
	_check("Nach dem Hochfahren Desktop", pcs.get("phase") == "desktop")
	_check("Nach dem Hochfahren Homescreen ohne offene App", str(terminal.get("_active_app")) == "")
	_check("3D-Welt hinter dem Vollbild aus", root.disable_3d)

	main_scene.call("_close_terminal")
	await create_timer(1.5).timeout
	_check("Nach dem Aufstehen läuft der PC weiter", pcs.get("phase") == "desktop" and int(pcs.get("user_peer")) == 0)
	_check("3D-Welt nach dem Aufstehen wieder an", not root.disable_3d)

	main_scene.call("_open_terminal")
	await create_timer(0.3).timeout
	_check("Erneutes Hinsetzen fährt nicht neu hoch", pcs.get("phase") == "desktop")
	await create_timer(2.5).timeout
	var boot: Node = terminal.get("_boot_screen")
	_check("Kein Bootbildschirm im Vollbild", boot != null and not bool(boot.call("is_running")))

	terminal.call("_shut_down_pc")
	await create_timer(0.3).timeout
	_check("Herunterfahren wird gemeldet", pcs.get("phase") == "shutdown")
	await create_timer(3.5).timeout
	_check("Nach dem Herunterfahren ist der PC aus", pcs.get("phase") == "idle")
	_check("Vollbild nach dem Herunterfahren zu", not terminal.visible)
	_check("3D-Welt nach dem Herunterfahren an", not root.disable_3d)
	print("ERGEBNIS: %d Fehler" % _fails)
	quit(0 if _fails == 0 else 1)


func _check(title: String, ok: bool) -> void:
	if ok:
		print("OK: ", title)
	else:
		_fails += 1
		print("FEHLER: ", title)