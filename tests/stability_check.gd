extends SceneTree
## Punkte aus „Stabilität & Fehler“, die ohne zweiten Spieler prüfbar sind:
## Netzwerk-Prüfsumme (BUG-02), Port-Prüfung (BUG-03), Spielstand-Signatur (BUG-04), Techniker in
## Halle Nord (BUG-05), liegengebliebene Aufträge (BUG-06), Fehlerkontext im Log (BUG-01).
## Aufruf: godot --headless --path . --script res://tests/stability_check.gd
## Mit zweitem Spieler: tests/stability_coop.gd

var bad := 0
var gs: Node
var fm: Node
var tm: Node
var nm: Node
var sm: Node
var main: Node
var hc: Script


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func _initialize() -> void:
	await process_frame
	if OS.get_cmdline_user_args().has("--only-id"):
		print("NETBUILD ", root.get_node("NetworkManager").net_build_id())
		quit(0)
		return
	gs = root.get_node("GameState")
	fm = root.get_node("FinanceManager")
	tm = root.get_node("TechnicianManager")
	nm = root.get_node("NetworkManager")
	sm = root.get_node("SaveManager")
	hc = load("res://scripts/data/hardware_catalog.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	main.get("intro_splash").set_process(false)
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)

	_check_rpc_list()
	await _check_error_watch()
	_check_ports()

	nm.call("_start_host_internal", "Test", 7799, {}, "", "Stabilitaet", "", false, false)
	for i in 10:
		await process_frame
	await _check_label_freed()
	_check_login_reasons()
	_check_save_rounding()
	tm.set_process(false)
	fm.set_process(false)
	gs.set_process(false)
	_check_technician_nord()
	_check_blocked_jobs()

	print("ERGEBNIS: %d Fehler" % bad)
	nm.call("leave_session")
	quit(1 if bad > 0 else 0)


# ---------------------------------------------------------------- BUG-02

## Jedes Skript mit @rpc steht in RPC_SCRIPTS, sonst fehlt es in der Prüfsumme.
func _check_rpc_list() -> void:
	var found: Array[String] = []
	_scan("res://scripts", found)
	found.sort()
	var listed: Array = (nm.RPC_SCRIPTS as Array).duplicate()
	listed.sort()
	chk("alle Skripte mit @rpc stehen in RPC_SCRIPTS", found == listed, {"fehlt": found.filter(func(p): return not listed.has(p)), "zu viel": listed.filter(func(p): return not found.has(p))})
	var id1: String = nm.net_build_id()
	nm.set("_net_build", "")
	var id2: String = nm.net_build_id()
	chk("Netzwerk-Prüfsumme ist fest", id1.length() == 10 and id1 == id2, id1)
	# Über Programmstarts hinweg gleich: Ein zweiter Godot-Prozess muss dieselbe Prüfsumme bilden.
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/stability_check.gd", "--", "--only-id"], out, true)
	var other := ""
	for line in str(out[0] if not out.is_empty() else "").split("\n"):
		if line.begins_with("NETBUILD "):
			other = line.substr(9).strip_edges()
	chk("Netzwerk-Prüfsumme ist in einem zweiten Programm gleich", code == 0 and other == id1, [id1, other])


func _scan(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir + "/" + f).contains("@rpc("):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + d, out)


func _check_login_reasons() -> void:
	var ok_msg := {"v": UIStyle.game_version(), "b": nm.net_build_id()}
	chk("Anmeldung mit gleichem Stand angenommen", nm.login_reject_reason(ok_msg, "n", "10.0.0.2") == "")
	var other: String = nm.login_reject_reason({"v": UIStyle.game_version(), "b": "abcdef1234"}, "n", "10.0.0.2")
	chk("anderer Programmstand wird mit Grund abgelehnt", other.contains("Programmstand") and other.contains("abcdef1234") and other.contains(nm.net_build_id()), other)
	var old: String = nm.login_reject_reason({"v": UIStyle.game_version()}, "n", "10.0.0.2")
	chk("Client ohne Prüfsumme wird abgelehnt", old.contains("Programmstand"), old)
	var ver: String = nm.login_reject_reason({"v": "0.0.1", "b": "x"}, "n", "10.0.0.2")
	chk("andere Version meldet weiter die Version", ver.contains("0.0.1") and not ver.contains("Programmstand"), ver)


# ---------------------------------------------------------------- BUG-03

func _check_ports() -> void:
	var p: int = nm.free_udp_port()
	chk("freier UDP-Port gefunden", p > 0, p)
	var reasons: Array = []
	var cb := func(r: String): reasons.append(r)
	nm.connection_failed.connect(cb)
	nm.test_no_udp_ports = true
	var err: int = nm.join_game("127.0.0.1", "Klient", 7799, "")
	nm.test_no_udp_ports = false
	chk("ohne freie Ports: Beitritt bricht sofort ab", err != OK and not nm.is_in_session)
	chk("ohne freie Ports: klare Meldung", reasons.size() == 1 and str(reasons[0]) == TranslationServer.translate(nm.NO_UDP_PORTS_TEXT), reasons)
	reasons.clear()
	nm.test_no_udp_ports = true
	nm.call("_start_host_internal", "Test", 7799, {}, "", "X", "", false, false)
	nm.test_no_udp_ports = false
	chk("ohne freie Ports: Hosten meldet es ebenso", reasons.size() == 1 and str(reasons[0]) == TranslationServer.translate(nm.NO_UDP_PORTS_TEXT), reasons)
	reasons.clear()
	var blocker := PacketPeerUDP.new()
	blocker.bind(7798)
	nm.call("_start_host_internal", "Test", 7798, {}, "", "X", "", false, false)
	blocker.close()
	chk("belegter Port: Meldung nennt den Port", reasons.size() == 1 and str(reasons[0]).contains("7798") and not nm.is_in_session, reasons)
	nm.connection_failed.disconnect(cb)
	nm.call("leave_session")


# ---------------------------------------------------------------- BUG-04

func _check_save_rounding() -> void:
	var state: Dictionary = gs.export_save_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var probe: Array = []
	for i in 3000:
		# Genau auf der Rundungsgrenze der 4. Nachkommastelle, darunter ein winziger Rest,
		# den die Datei mit ihren 14 Stellen nicht mehr speichert.
		var base := float(rng.randi_range(-500000, 500000)) / 10000.0
		probe.append(base + 0.00005 + rng.randf_range(-1e-13, 1e-13))
	state["bug04_probe"] = probe
	state["money"] = 1234.56785 + 3e-13
	var r: Dictionary = sm.save_world("bug04test", "bug04test", state)
	var l: Dictionary = sm.load_world_file("bug04test")
	var status := str((l.get("integrity", {}) as Dictionary).get("status", ""))
	chk("Spielstand mit Werten an der Rundungsgrenze bleibt gültig", bool(r.get("ok", false)) and status == "valid", status)
	var root_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(sm.get_save_path("bug04test")))
	var old_sig: String = root.get_node("SecurityGuard").compute_save_signature(sm._serialize_state(state))
	var file_sig: String = root.get_node("SecurityGuard").compute_save_signature((root_v as Dictionary)["state"])
	chk("Gegenprobe: so wie bisher signiert hätte es „manipuliert“ geheißen", old_sig != file_sig)
	sm.save_world("bug04test", "bug04test", gs.export_save_data())
	chk("normaler Spielstand bleibt gültig", str((sm.load_world_file("bug04test")["integrity"] as Dictionary)["status"]) == "valid")
	sm.delete_save("bug04test")


# ---------------------------------------------------------------- BUG-05 / BUG-06

func _part(cat: String, tier: int) -> String:
	for pd in hc.call("get_category_parts", cat):
		if int((pd as Dictionary).get("vtier", 0)) == tier:
			return str(pd["id"])
	return ""


func _comps(tier: int) -> Dictionary:
	var d := {}
	for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
		d[cat] = _part(cat, tier)
	return d


func _check_technician_nord() -> void:
	gs.money = 100000.0
	gs.time_of_day = 0.5
	var idx := -1
	for i in range(fm.CANDIDATE_POOL.size()):
		if str(fm.CANDIDATE_POOL[i]["role"]) == "technician" and int(fm.CANDIDATE_POOL[i]["skill"]) == 5:
			idx = i
	fm._do_hire(idx, 1)
	tm.tick(0.1)
	chk("Techniker im Dienst", not tm.view.is_empty())
	gs.halle_nord_owned = true
	var nid: String = gs._alloc_id("rack")
	gs.racks[nid] = gs._make_rack_data(nid, "rack", Vector3(-3.0, 0.0, -318.5), PI)
	gs.racks[nid]["slots"][0].merge({"item_type": "web_server", "state": "crashed", "faulty_part": "cooling", "components": _comps(1)}, true)
	var kid: String = gs._alloc_id("crate")
	gs.crates[kid] = {"id": kid, "item_type": "kit_cooling", "pos": Vector3(0.5, 0.0, 7.0), "held_by": 0}
	var front: Vector3 = tm._rack_front(nid)
	var seen := {"ride_there": false, "walk_nord": false, "ride_back": false, "take_at": Vector3.INF, "nord_len": 0.0}
	var t := 0.0
	var done := false
	while t < 700.0:
		tm.tick(0.1)
		t += 0.1
		var v: Dictionary = tm.view
		var ph := str(v.get("phase", ""))
		if ph == "wait" and str(v.get("text", "")).contains(tr("Halle Nord")):
			seen["ride_there"] = true
		if ph == "wait" and str(v.get("text", "")) == tr("mit dem Shuttle zurück"):
			seen["ride_back"] = true
		if ph == "walk":
			var path: Array = v.get("path", [])
			var all_nord := not path.is_empty()
			var len := 0.0
			for i in path.size():
				all_nord = all_nord and (path[i] as Vector3).z < -300.0 and absf((path[i] as Vector3).x) < 9.8
				if i > 0:
					len += (path[i] as Vector3).distance_to(path[i - 1])
			if all_nord and len > 1.0:
				seen["walk_nord"] = true
				seen["nord_len"] = maxf(float(seen["nord_len"]), len)
		if seen["take_at"] == Vector3.INF and str(tm._job.get("carry", "")) != "":
			seen["take_at"] = tm._pos
		if str(gs.racks[nid]["slots"][0]["item_type"]) != "" and str(gs.racks[nid]["slots"][0]["state"]) == "ok":
			done = true
			break
	chk("fährt mit dem Shuttle nach Halle Nord", seen["ride_there"])
	chk("läuft in Halle Nord sichtbar zum Rack", seen["walk_nord"], "%.1f m" % float(seen["nord_len"]))
	chk("nimmt den Server vor dem Rack heraus, nicht an der Haltestelle", (seen["take_at"] as Vector3).distance_to(front) < 0.8, [seen["take_at"], front])
	chk("fährt mit dem Server zurück", seen["ride_back"])
	chk("repariert und setzt in Halle Nord wieder ein", done, "%.0f s" % t)
	var home := -1.0
	t = 0.0
	while t < 120.0:
		tm.tick(0.1)
		t += 0.1
		if tm._phase == "idle" and not tm._is_remote(tm._pos) and tm._pos.distance_to(tm.HOME) < 0.6:
			home = t
			break
	chk("fährt danach zurück an seinen Platz", home > 0.0, tm._pos)
	# Weg in Halle Nord um Einbauten herum
	var oz: float = gs.HALLE_NORD_ORIGIN.z
	var way: Array = tm.find_path(tm._nord_stop(), Vector3(-8.0, 0.0, oz + 3.5))
	var inside := way.size() > 2
	for p in way:
		inside = inside and absf((p as Vector3).x) < 9.8 and absf((p as Vector3).z - oz) < 5.8
	chk("Weg in Halle Nord bleibt in der Halle", inside, way.size())
	chk("zwischen den Standorten gibt es keinen Fußweg", tm.find_path(tm.HOME, front).is_empty())
	gs.racks.erase(nid)


func _check_blocked_jobs() -> void:
	var rid: String = gs._alloc_id("rack")
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(1.0, 0.0, -2.0), 0.0)
	tm._job = {"kind": "fetch", "rack": rid, "slot": 0}
	tm._no_way(tr("holt einen defekten Server"))
	var list: Array = tm.view.get("blocked", [])
	chk("liegengebliebener Auftrag steht in der Ansicht", list.size() == 1 and str(list[0][0]) == gs.get_rack_display_name(rid) and int(list[0][1]) >= 59, list)
	chk("mit dem Grund", list.size() == 1 and str(list[0][2]) == tr("holt einen defekten Server"), list)
	var host := VBoxContainer.new()
	root.add_child(host)
	load("res://scripts/ui/finance_apps.gd").call("render_staff", host, "", true)
	var texts := PackedStringArray()
	for n in host.find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	var btn := false
	for n in host.find_children("*", "Button", true, false):
		btn = btn or (n as Button).text == tr("Jetzt erneut versuchen")
	var want := tr("Kommt nicht hin: %s") % gs.get_rack_display_name(rid)
	var shown := false
	for s in texts:
		shown = shown or s.begins_with(want)
	chk("Personal-Fenster zeigt den Auftrag", shown, want)
	chk("Personal-Fenster hat „Jetzt erneut versuchen“", btn)
	host.queue_free()
	tm._rpc_req_retry_blocked()
	chk("erneut versuchen räumt die Liste", tm._unreachable.is_empty() and (tm.view.get("blocked", [1]) as Array).is_empty())
	gs.racks.erase(rid)


# ---------------------------------------------------------------- BUG-01

func _check_error_watch() -> void:
	var ew: ErrorWatch = main.get("error_watch")
	chk("Fehlerkontext ist angemeldet", ew != null)
	if ew == null:
		return
	print("(der folgende Fehler ist Absicht)")
	root.get_node("gibt_es_nicht_stabilitaet")
	await process_frame
	await process_frame
	chk("zu einem Engine-Fehler steht der Kontext im Log", ew.last_report.begins_with("[Fehlerkontext]") and ew.last_report.contains("Hauptmenü"), ew.last_report)


## Schrift, die im selben Bild wieder verschwindet, darf keinen Fehler im Log hinterlassen.
func _check_label_freed() -> void:
	var ew: ErrorWatch = main.get("error_watch")
	var reports := int(ew.get("_reports"))
	var world: Node = main.get("world")
	var gone := Label3D.new()
	gone.font_size = 20
	gone.pixel_size = 0.001
	world.add_child(gone)
	gone.free()
	var kept := Label3D.new()
	kept.font_size = 20
	kept.pixel_size = 0.002
	world.add_child(kept)
	await process_frame
	await process_frame
	chk("sofort gelöschte Schrift: kein Fehler", int(ew.get("_reports")) == reports, ew.last_report)
	chk("kleine Schrift blendet in der Ferne aus", kept.visibility_range_end > 0.0, kept.visibility_range_end)
	kept.queue_free()
