extends SceneTree
## Lieferschein im Co-op mit zwei Programmen: Der Client nimmt den Schein, der Fahrer wartet,
## der Host sieht, wer unterschreibt, und die Unterschrift des Clients kommt beim Host an.
## Aufruf (zuerst Host, dann Client):
##   godot --headless --path . --script res://tests/delivery_note_coop.gd -- --role=host
##   godot --headless --path . --script res://tests/delivery_note_coop.gd -- --role=client

const PORT := 7915

var bad := 0
var role := ""
var gs: Node
var nm: Node
var main: Node


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print(role.to_upper(), "  ", "PASS  " if ok else "FAIL  ", label, "  ", extra)


func until(f: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if f.call():
			return true
		await create_timer(0.1).timeout
	return false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	await process_frame
	gs = root.get_node("GameState")
	nm = root.get_node("NetworkManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.0).timeout
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	if role == "host":
		await _host()
	else:
		await _client()
	print(role.to_upper(), "  ERGEBNIS: %d Fehler" % bad)
	nm.leave_session()
	await create_timer(0.5).timeout
	quit(1 if bad > 0 else 0)


func _host() -> void:
	nm.call("_start_host_internal", "Hosti", PORT, {}, "", "Lieferkoop", "", false, false)
	chk("Client kommt rein", await until(func(): return nm.players.size() > 1, 60.0))
	await create_timer(2.0).timeout
	gs.money = 50000.0
	gs.van_cargo = ["rack", "web_server"]
	gs._start_delivery_van()
	var reached: bool = await until(func(): return gs.van_trip_phase == "sign", 120.0)
	chk("Fahrer wartet auf die Unterschrift", reached)
	var client := 0
	for p in nm.players.keys():
		if int(p) != 1:
			client = int(p)
	chk("Client hält den Schein", await until(func(): return gs.van_sign_peer == client, 20.0), gs.van_sign_peer)
	# Der Host kommt nicht dazwischen, auch nicht mit gültiger Unterschrift.
	gs.request_sign_delivery(load("res://scripts/data/delivery_note.gd").test_signature())
	await create_timer(1.0).timeout
	chk("Host kann nicht dazwischen unterschreiben", gs.van_trip_phase == "sign")
	chk("Unterschrift des Clients kommt an", await until(func(): return gs.van_trip_phase == "enter", 50.0))
	chk("Name des Clients steht im Plan", str(gs.van_plan.get("signed_by", "")) == "Klient", gs.van_plan.get("signed_by", ""))
	await until(func(): return nm.players.size() == 1, 40.0)


func _client() -> void:
	nm.join_game("127.0.0.1", "Klient", PORT, "")
	chk("in der Sitzung", await until(func(): return nm.is_in_session and gs.is_active, 30.0))
	chk("Lieferschein kommt mit dem Ladeplan", await until(func(): return gs.van_trip_phase == "sign" and not (gs.van_plan.get("doc", {}) as Dictionary).is_empty(), 120.0))
	var ui: Control = main.get("delivery_note_ui")
	main.call("_open_delivery_note")
	chk("Fenster beim Client offen", ui.visible)
	chk("Host bestätigt: Client unterschreibt", await until(func(): return gs.van_sign_peer == root.multiplayer.get_unique_id(), 10.0), gs.van_sign_peer)
	# Wartet der Fahrer wirklich? Länger als die normale Wartezeit.
	await create_timer(gs.VAN_SIGN_TIME + 4.0).timeout
	chk("Fahrer wartet länger als sonst", gs.van_trip_phase == "sign")
	var pad: Control = ui.get("_pad")
	pad.call("set_strokes", load("res://scripts/data/delivery_note.gd").test_signature())
	# set_strokes zeigt nur an. Für das Senden die Striche wie gezeichnet übernehmen:
	gs.request_sign_delivery(pad.call("strokes_normalized"))
	ui.set("_sent", true)
	chk("Stempel nach der Bestätigung", await until(func(): return (ui.get("_stamp") as Control).visible, 15.0))
	chk("Fenster schließt sich", await until(func(): return not ui.visible, 6.0))
	await create_timer(1.0).timeout
