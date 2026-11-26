extends SceneTree
## Co-op & Netzwerk ohne zweiten Spieler: Erreichbarkeit (NET-04), Statusabfrage der Lobby (NET-01),
## Baurechte (NET-08), Serverbefehle (NET-10), Glättung fremder Bewegungen (NET-05), Paketverlust (NET-03).
## Aufruf: godot --headless --path . --script res://tests/coop_net_check.gd
## Mit mehreren Spielern: tests/coop_net_coop.gd

const PORT := 7903

var bad := 0
var gs: Node
var nm: Node
var main: Node


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func until(f: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if f.call():
			return true
		await process_frame
	return false


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	nm = root.get_node("NetworkManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	main.get("intro_splash").set_process(false)
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)

	_check_reach()
	nm.call("_start_host_internal", "Hosti", PORT, {}, "", "Lobbytest", "", false, false)
	for i in 10:
		await process_frame
	await _check_status()
	_check_build_rights()
	_check_console()
	await _check_interpolation()
	_check_loss_text()

	print("ERGEBNIS: %d Fehler" % bad)
	nm.leave_session()
	quit(1 if bad > 0 else 0)


func _check_reach() -> void:
	chk("Tailscale erkannt", nm.address_kind("100.101.7.3") == "tailscale")
	chk("Radmin erkannt", nm.address_kind("26.12.0.9") == "radmin")
	chk("LAN erkannt", nm.address_kind("192.168.178.20") == "lan" and nm.address_kind("10.0.0.5") == "lan" and nm.address_kind("172.20.1.1") == "lan")
	chk("Rest bleibt außen vor", nm.address_kind("127.0.0.1") == "" and nm.address_kind("169.254.3.4") == "" and nm.address_kind("8.8.8.8") == "" and nm.address_kind("fe80::1") == "")
	var addrs: Array = nm.reach_addresses()
	var lan_seen := false
	for a in addrs:
		lan_seen = lan_seen or str(a["kind"]) == "lan"
	chk("eigene Adressen gefunden", addrs.size() > 0 and lan_seen, addrs)


func _check_status() -> void:
	chk("Statusabfrage läuft beim Host", nm.is_status_server_running())
	var keys: Array = []
	var cb := func(k: String): keys.append(k)
	nm.server_status_updated.connect(cb)
	nm.query_server("127.0.0.1", PORT)
	await until(func(): return keys.has("127.0.0.1:%d" % PORT), 4.0)
	var st: Dictionary = nm.get_server_status("127.0.0.1", PORT)
	chk("Lobby: Server antwortet", str(st.get("state", "")) == "ok", st)
	chk("Lobby: Welt, Host, Spieler, Version", str(st.get("world", "")) == "Lobbytest" and str(st.get("host", "")) == "Hosti" and int(st.get("players", -1)) == 1 \
		and int(st.get("max", 0)) == nm.MAX_PLAYERS and str(st.get("version", "")) == UIStyle.game_version() and str(st.get("build", "")) == nm.net_build_id(), st)
	chk("Lobby: kein Passwort, Ping gemessen", st.get("password", true) == false and int(st.get("ping", -1)) >= 0 and int(st.get("ping", 999)) < 500, st)
	keys.clear()
	nm.query_server("127.0.0.1", PORT + 40)
	await until(func(): return keys.has("127.0.0.1:%d" % (PORT + 40)), 5.0)
	chk("Lobby: kein Server dort = nicht erreichbar", str(nm.get_server_status("127.0.0.1", PORT + 40).get("state", "")) == "offline", nm.get_server_status("127.0.0.1", PORT + 40))
	nm.server_status_updated.disconnect(cb)
	# Gespeicherte Server
	var sm := root.get_node("SettingsManager")
	var before: Array = (sm.saved_servers as Array).duplicate(true)
	sm.add_saved_server("Freunde", "10.1.2.3", 7777)
	sm.add_saved_server("Freunde neu", "10.1.2.3", 7777)
	chk("gespeicherter Server ohne Doppel", (sm.saved_servers as Array).filter(func(s): return str(s["ip"]) == "10.1.2.3").size() == 1 and str(sm.saved_servers[0]["name"]) == "Freunde neu")
	sm.remove_saved_server("10.1.2.3", 7777)
	chk("gespeicherter Server entfernt", (sm.saved_servers as Array).filter(func(s): return str(s["ip"]) == "10.1.2.3").is_empty())
	sm.saved_servers = before
	sm.save_settings()


func _check_build_rights() -> void:
	chk("ohne Passwort: Bauen nur nach Freigabe", gs.build_open == false)
	chk("Host darf immer", gs.can_build(1))
	# Gedachter Mitspieler 77 (ohne echte Verbindung).
	nm.players[77] = {"name": "Gast", "color": Color.WHITE, "skin": {}, "seq": 5}
	nm.get("_peer_keys")[77] = "schluessel_gast"
	chk("neuer Mitspieler darf nicht bauen", not gs.can_build(77))
	chk("Freigabe", gs.set_build_right(77, true) and gs.can_build(77))
	chk("Freigabe ist gespeichert", (gs.export_save_data()["build_allowed"] as Dictionary).has("schluessel_gast"))
	var uid: String = gs.world_uid
	var data: Dictionary = gs.export_save_data()
	gs.load_from_save_data(data, gs.current_save_id, gs.current_save_name)
	chk("nach dem Laden noch freigegeben, Welt-ID bleibt", gs.build_allowed.has("schluessel_gast") and gs.world_uid == uid and uid.length() == 16)
	chk("Entzug", gs.set_build_right(77, false) and not gs.can_build(77))
	nm.host_password = "geheim"
	gs.sync_build_rights()
	chk("mit Passwort dürfen alle", gs.build_open and gs.can_build(77))
	nm.host_password = ""
	gs.sync_build_rights()
	nm.players.erase(77)
	nm.get("_peer_keys").erase(77)
	var k1: String = nm.world_key("welt_a")
	var k2: String = nm.world_key("welt_b")
	chk("Schlüssel je Welt verschieden, gleich lang", k1 != k2 and k1.length() == 32 and k1 == nm.world_key("welt_a"))


func _check_console() -> void:
	var srv: Node = load("res://scripts/server/dedicated_server.gd").new()
	srv.call("_handle_command", "time 14:30")
	chk("Konsole: time 14:30", absf(gs.time_of_day - 14.5 / 24.0) < 0.002, gs.get_time_string())
	srv.call("_handle_command", "weather rain")
	chk("Konsole: weather rain", gs.weather_state == "rain")
	srv.call("_handle_command", "weather schnee")
	chk("Konsole: falsches Wetter ändert nichts", gs.weather_state == "rain")
	srv.call("_handle_command", "speed 3")
	chk("Konsole: speed 3", is_equal_approx(gs.clock_scale, 3.0))
	srv.call("_handle_command", "speed 1")
	srv.call("_handle_command", "save-as Konsolen Test")
	var sm := root.get_node("SaveManager")
	chk("Konsole: save-as", FileAccess.file_exists(sm.get_save_path("konsolen_test")) and gs.current_save_name == "Konsolen Test")
	sm.delete_save("konsolen_test")
	var said: Array = []
	var cb := func(sender: String, _c: Color, msg: String, _ts: String): said.append([sender, msg])
	nm.chat_message_received.connect(cb)
	srv.call("_handle_command", "say Hallo zusammen")
	chk("Konsole: say", said.size() == 1 and str(said[0][0]) == "Server" and str(said[0][1]) == "Hallo zusammen", said)
	nm.chat_message_received.disconnect(cb)
	srv.call("_handle_command", "players")
	srv.call("_handle_command", "help")
	srv.free()


## Fremde Figur: 20 Meldungen je Sekunde mit Schwankung, danach Funkstille.
func _check_interpolation() -> void:
	var p: Node3D = load("res://scripts/world/player_controller.gd").new()
	p.set("is_local", false)
	var xs: Array[float] = []
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sent := 0
	var next_send := 0
	while Time.get_ticks_msec() - t0 < 1500:
		var now := Time.get_ticks_msec() - t0
		if now >= next_send:
			# Absenderzeit = Sendezeit, Ankunft streut um bis zu 60 ms (Ping-Schwankung).
			var x := float(now) / 1000.0 * 2.0
			p.call("apply_remote_pose", Vector3(x, 0.0, 0.0), 0.0, 0.0, 0, false, Time.get_ticks_msec() - rng.randi_range(0, 60))
			sent += 1
			next_send += 50
		var s: Dictionary = p.call("_remote_sample")
		xs.append((s["pos"] as Vector3).x)
		await process_frame
	var back := 0
	for i in range(1, xs.size()):
		if xs[i] < xs[i - 1] - 0.03:
			back += 1
	chk("Glättung: keine Rucke rückwärts", back == 0, "%d Rückschritte bei %d Bildern" % [back, xs.size()])
	var last_x: float = xs[xs.size() - 1]
	chk("Glättung: höchstens etwa 0,3 s hinterher", last_x > 2.0 * 1.5 - 0.7 and last_x < 2.0 * 1.5 + 0.1, last_x)
	# Funkstille: kurz weiterrechnen, dann stehen bleiben.
	var t1 := Time.get_ticks_msec()
	var xa := 0.0
	while Time.get_ticks_msec() - t1 < 800:
		xa = ((p.call("_remote_sample") as Dictionary)["pos"] as Vector3).x
		await process_frame
	chk("Glättung: ohne Meldungen höchstens 0,25 s weiter", xa <= 2.0 * 1.5 + 0.55, xa)
	p.call("apply_remote_pose", Vector3(40.0, 0.0, 5.0), 0.0, 0.0, 0, false, Time.get_ticks_msec())
	chk("Glättung: Teleport springt sofort", p.position.distance_to(Vector3(40.0, 0.0, 5.0)) < 0.01)
	p.free()


func _check_loss_text() -> void:
	chk("Host selbst: keine Verbindungswarnung", nm.connection_warning() == "")
	nm.player_loss[2] = 12.0
	chk("Paketverlust je Spieler abrufbar", is_equal_approx(nm.get_player_loss(2), 12.0))
	nm.player_loss.erase(2)
