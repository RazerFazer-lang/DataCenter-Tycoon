extends SceneTree
## Co-op-Teil von „Stabilität & Fehler“ mit zwei Programmen:
##   BUG-02  anderer Programmstand: Der Client bekommt eine klare Meldung statt Netzwerkfehlern.
##   BUG-07  Pausemenü beim Host: Die Welt läuft für den Client weiter.
## Aufruf (zuerst Host, dann Client):
##   godot --headless --path . --script res://tests/stability_coop.gd -- --role=host
##   godot --headless --path . --script res://tests/stability_coop.gd -- --role=client

const PORT := 7897

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
	nm.call("_start_host_internal", "Hosti", PORT, {}, "", "Koop", "", false, false)
	chk("Host läuft", nm.is_in_session)
	# Der Client versucht es zuerst mit falschem Stand, dann richtig.
	chk("richtiger Client kommt rein", await until(func(): return nm.players.size() > 1, 60.0))
	var hud: Node = main.get("hud")
	main.call("_open_pause")
	var lbl: Label = hud.get("_pause_runs_lbl")
	chk("Pausemenü sagt, dass die Welt weiterläuft", lbl != null and lbl.text == tr("Co-op: Die Welt läuft für alle weiter, auch während dieses Menü offen ist."), lbl.text if lbl else "")
	var t0: float = gs.time_of_day
	var d0: int = gs.day_number
	await create_timer(6.0).timeout
	chk("Host: Spielzeit läuft im Pausemenü weiter", bool(main.get("_is_paused")) and (gs.time_of_day > t0 or gs.day_number > d0), [t0, gs.time_of_day])
	await until(func(): return nm.players.size() == 1, 40.0)


func _client() -> void:
	var reasons: Array = []
	nm.connection_failed.connect(func(r: String): reasons.append(r))
	# Anderer Programmstand: so tun, als hätte dieser Client andere Netzwerkfunktionen.
	nm.set("_net_build", "abcdef1234")
	nm.join_game("127.0.0.1", "Klient", PORT, "")
	var failed: bool = await until(func(): return not reasons.is_empty(), 15.0)
	var r := str(reasons[0]) if failed else ""
	# Schluss der Meldung (nach den Prüfsummen), in der eingestellten Sprache.
	var tail := tr("Gleiche Spielversion, aber ein anderer Programmstand (Netzwerk-Prüfsumme Host %s, Client %s). Beide brauchen denselben Download, am einfachsten über den Launcher.").get_slice(")", 1)
	chk("anderer Programmstand: Beitritt scheitert mit klarer Meldung", failed and r.contains("abcdef1234") and r.ends_with(tail), r)
	chk("anderer Programmstand: nicht in der Sitzung", not nm.is_in_session and not gs.is_active)
	nm.set("_net_build", "")
	reasons.clear()
	await create_timer(1.0).timeout
	nm.join_game("127.0.0.1", "Klient", PORT, "")
	chk("gleicher Stand: Beitritt klappt", await until(func(): return gs.is_active and nm.is_in_session, 20.0), reasons)
	# Der Host öffnet sein Pausemenü, sobald wir drin sind. Kommen weiter Sim-Takte an?
	await create_timer(2.0).timeout
	var ticks := [0]
	gs.state_updated.connect(func(): ticks[0] += 1)
	await create_timer(6.0).timeout
	chk("Host im Pausemenü: Sim-Takte kommen weiter an", int(ticks[0]) >= 8, "%d in 6 s" % int(ticks[0]))
