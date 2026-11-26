extends SceneTree
## Co-op & Netzwerk mit drei Programmen (Host, A, B), Port 7900:
##   NET-08  Baurechte: A darf erst nach Freigabe einkaufen.
##   NET-02  Wiederverbinden: A reißt ab und kommt mit Ware in der Hand, Position und Kabel zurück.
##   NET-07  Host-Wechsel: Der Host geht, A (am längsten dabei) übernimmt, B verbindet sich mit A.
##           Danach stürzt A ab, B übernimmt selbst.
## Aufruf: tests/run_coop_net.sh startet alle drei (Host zuerst).

const PORT := 7900

var bad := 0
var role := ""
var gs: Node
var nm: Node
var sk: Node
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
	sk = root.get_node("SessionKeeper")
	# Jedes Programm ist ein eigener Spieler (die Testläufe teilen sich eine settings.cfg).
	root.get_node("SettingsManager").client_id = "test_%s_%d" % [role, OS.get_process_id()]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.0).timeout
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	match role:
		"host":
			await _host()
		"a":
			await _a()
		"b":
			await _b()
	print(role.to_upper(), "  ERGEBNIS: %d Fehler" % bad)
	if nm.is_in_session:
		nm.leave_session()
	await create_timer(0.5).timeout
	quit(1 if bad > 0 else 0)


func _peer_named(n: String) -> int:
	for pid in nm.players.keys():
		if str(nm.players[pid].get("name", "")) == n:
			return int(pid)
	return 0


# ------------------------------------------------------------------ Host

func _host() -> void:
	nm.call("_start_host_internal", "Hosti", PORT, {}, "", "Koopnetz", "", false, false)
	gs.money = 50000.0
	chk("alle da", await until(func(): return nm.players.size() == 3, 60.0), nm.players.size())
	var a := _peer_named("Anna")
	# --- Baurechte: A versucht zu kaufen, darf aber noch nicht.
	var m0: float = gs.money
	await create_timer(3.0).timeout
	chk("ohne Baurecht: nichts gekauft", is_equal_approx(gs.money, m0), [m0, gs.money])
	chk("Freigabe für A", gs.set_build_right(a, true))
	chk("A kauft nach der Freigabe", await until(func(): return gs.money < m0 - 1.0, 10.0), [m0, gs.money])
	# --- Wiederverbinden: A bekommt eine Kiste in die Hand.
	var cid: String = gs._alloc_id("crate")
	gs.crates[cid] = {"id": cid, "item_type": "kit_ram", "pos": Vector3(1.0, 0.0, 1.0), "held_by": a, "held_slot": 1}
	gs._broadcast_crates()
	print("HOST Kiste ", cid, " an A ", a)
	chk("A bricht ab, Platz wird freigehalten", await until(func(): return _peer_named("Anna") == 0 and sk.reservation_count() == 1, 25.0))
	chk("Kiste liegt dort, wo A stand", (gs.crates[cid]["pos"] as Vector3).distance_to(Vector3(2.0, 0.0, -1.0)) < 1.0 and int(gs.crates[cid]["held_by"]) == 0, gs.crates[cid])
	chk("A ist wieder da", await until(func(): return _peer_named("Anna") != 0, 30.0))
	var a2 := _peer_named("Anna")
	chk("A hat die Kiste wieder in der Hand", await until(func(): return int(gs.crates[cid]["held_by"]) == a2, 5.0), gs.crates[cid])
	chk("A behält seinen Platz in der Reihe", int(nm.players[a2].get("seq", 0)) == 1 and sk.successor() == a2, nm.players[a2])
	chk("A behält das Baurecht", gs.can_build(a2))
	# --- Host-Wechsel: Geld markieren, gehen.
	gs.money = 4242.0
	await create_timer(1.0).timeout
	chk("Übergabe an A", await sk.hand_over())
	nm.leave_session()
	await create_timer(3.0).timeout


# ------------------------------------------------------------------ A

func _a() -> void:
	var events: Array = []
	gs.event_logged.connect(func(msg: String, _sev: String): events.append(msg))
	nm.join_game("127.0.0.1", "Anna", PORT, "")
	chk("A in der Sitzung", await until(func(): return gs.is_active and nm.is_in_session and nm.players.size() >= 2, 20.0))
	await until(func(): return nm.players.size() == 3, 30.0)
	chk("A darf anfangs nicht bauen", not gs.local_can_build())
	gs._rpc_req_buy_item.rpc_id(1, "rack")
	chk("A bekommt einen Hinweis", await until(func(): return events.any(func(m): return str(m).contains(tr("Einkaufen geht erst"))), 5.0), events.slice(-3))
	chk("A darf nach Freigabe bauen", await until(func(): return gs.local_can_build(), 15.0))
	gs._rpc_req_buy_item.rpc_id(1, "rack")
	# --- Wiederverbinden
	var old_id: int = root.multiplayer.get_unique_id()
	chk("A hat die Kiste", await until(func(): return not gs.get_player_held_crate(old_id).is_empty(), 15.0))
	var cid := str(gs.get_player_held_crate(old_id).get("id", ""))
	var lp: Node3D = root.get_tree().get_first_node_in_group("local_player")
	lp.position = Vector3(2.0, 0.05, -1.0)
	lp.set("cable_active_type", "power")
	# Echte Buchse (Wand-Router), sonst bricht das Spiel das Kabel selbst ab.
	lp.set("cable_active_type", "network")
	lp.set("cable_start_id", gs.WALL_ROUTER_ID)
	lp.set("cable_start_slot", 0)
	await create_timer(1.0).timeout
	nm.simulate_connection_loss()
	chk("A verbindet sich neu", sk.is_recovering())
	chk("A ist zurück", await until(func(): return nm.is_in_session and gs.is_active and not sk.is_recovering() and root.multiplayer.get_unique_id() != old_id, 40.0))
	await until(func(): return root.get_tree().get_first_node_in_group("local_player") != null and sk.get("_restore_pending").is_empty(), 10.0)
	await create_timer(1.0).timeout
	var new_id: int = root.multiplayer.get_unique_id()
	lp = root.get_tree().get_first_node_in_group("local_player")
	chk("A: Kiste wieder in der Hand", str(gs.get_player_held_crate(new_id).get("id", "")) == cid, gs.crates.get(cid, {}))
	chk("A: wieder an der alten Stelle", lp != null and lp.position.distance_to(Vector3(2.0, 0.05, -1.0)) < 0.6, lp.position if lp else null)
	chk("A: Kabel noch in der Hand", lp != null and str(lp.get("cable_start_id")) == gs.WALL_ROUTER_ID and str(lp.get("cable_active_type")) == "network", [lp.get("cable_start_id"), lp.get("cable_active_type")] if lp else null)
	# --- Host-Wechsel: A übernimmt.
	chk("A ist Nachfolger", await until(func(): return sk.successor() == new_id, 25.0), sk.successor())
	chk("A übernimmt die Welt", await until(func(): return nm.is_in_session and root.multiplayer.is_server() and gs.is_active and not sk.is_recovering(), 40.0))
	chk("A: Welt mit dem Stand des alten Hosts", is_equal_approx(gs.money, 4242.0), gs.money)
	chk("A: Spielstand gespeichert", FileAccess.file_exists(root.get_node("SaveManager").get_save_path(gs.current_save_id)), gs.current_save_id)
	chk("B kommt zu A", await until(func(): return nm.players.size() == 2, 40.0), nm.players.size())
	# B hat jetzt die Kopie. Absturz von A: B soll übernehmen.
	await until(func(): return not sk.get("_plan_sent").is_empty(), 20.0)
	await create_timer(2.0).timeout
	print("A stürzt ab")
	OS.kill(OS.get_process_id())


# ------------------------------------------------------------------ B

func _b() -> void:
	await create_timer(3.0).timeout
	nm.join_game("127.0.0.1", "Bert", PORT, "")
	chk("B in der Sitzung", await until(func(): return gs.is_active and nm.is_in_session, 25.0))
	chk("B sieht: A darf bauen, B nicht", await until(func(): return gs.can_build(_peer_named("Anna")) and not gs.local_can_build(), 30.0))
	chk("B: Host-Wechsel zu A", await until(func(): return sk.is_recovering(), 120.0))
	chk("B: wieder in der Sitzung bei A", await until(func(): return nm.is_in_session and gs.is_active and not sk.is_recovering() and not root.multiplayer.is_server(), 60.0))
	chk("B: Welt mit dem Stand des alten Hosts", is_equal_approx(gs.money, 4242.0), gs.money)
	chk("B: A ist Host", str(nm.players.get(1, {}).get("name", "")) == "Anna", nm.players.get(1, {}))
	chk("B: nach dem Absturz von A übernimmt B", await until(func(): return nm.is_in_session and root.multiplayer.is_server() and gs.is_active, 90.0))
	chk("B: Welt nach dem Absturz erhalten", is_equal_approx(gs.money, 4242.0), gs.money)
