extends SceneTree
## Spielt die Werkbank mit simulierter Maus durch: Zusammenbau und jede Reparatur.
## Aufruf: godot --headless --path . --script res://tests/workbench_check.gd
## Mit Bildern (ohne --headless): -- --shots=<Ordner>   Nur einzelne Fälle: -- --only=<Text>

var bad := 0
var shots := ""
var only := ""
var main: Node
var gs: Node
var ui: Control
var shot_n := 0


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
		elif a.begins_with("--only="):
			only = a.substr(7)
	await process_frame
	gs = root.get_node("GameState")
	var nm := root.get_node("NetworkManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	# Intro und Ladebildschirm fangen sonst Klicks ab; headless ist das Fenster nur 64 Pixel groß.
	main.get("intro_splash").set_process_input(false)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	main.set("_startup_done", true)
	nm.call("_start_host_internal", "Test", 7795, {}, "", "Werkbanktest", "", false, false)
	for i in 20:
		await process_frame
	gs.time_of_day = 0.45
	ui = main.get("workbench_ui")
	_check_plans()

	var t0 := {"cpu": "", "gpu": "gpu_onboard", "ram": "", "storage": "", "cooling": "", "psu": ""}
	for cat in t0.keys():
		if cat != "gpu":
			t0[cat] = _part_of_tier(cat, 0)
	var t2 := {}
	for cat in t0.keys():
		t2[cat] = _part_of_tier(cat, 2)
	var t3 := {}
	for cat in t0.keys():
		t3[cat] = _part_of_tier(cat, 3)
	await _run_case("bau_t0", {"mode": "assembly", "label": "Einsteiger", "mainboard_id": "web_server", "components": t0})
	await _run_case("bau_t2", {"mode": "assembly", "label": "Profi", "mainboard_id": "web_server", "components": t2})
	await _run_case("bau_t3", {"mode": "assembly", "label": "KI-Server", "mainboard_id": "gpu_server", "components": t3})
	# Sichtbarer Schaden + Kit, verdeckter Schaden + Teil aus dem Lager, am Rack schon gefunden.
	for cat in ["cpu", "ram", "gpu", "storage", "cooling", "psu", "mainboard"]:
		await _run_case("rep_" + cat, {"mode": "repair", "state": "crashed", "faulty_part": cat, "label": "Defekt " + cat, "mainboard_id": "web_server", "components": t2})
		if cat != "mainboard":
			await _run_case("teil_" + cat, {"mode": "repair", "state": "crashed", "faulty_part": cat, "fault_hidden": true, "label": "Verdeckt " + cat, "mainboard_id": "web_server", "components": t2}, _part_of_tier(cat, 3 if cat in ["ram", "gpu"] else 1))
	await _run_case("rep_bekannt", {"mode": "repair", "state": "crashed", "faulty_part": "psu", "diagnosed": true, "label": "Bekannt", "mainboard_id": "web_server", "components": t2})
	await _run_case("service", {"mode": "service", "state": "ok", "build_quality": 48, "label": "Überholen", "mainboard_id": "web_server", "components": t2})
	await _run_case("rep_gpu_t3", {"mode": "repair", "state": "crashed", "faulty_part": "gpu", "label": "KI defekt", "mainboard_id": "gpu_server", "components": t3})
	await _run_case("teil_gpu_t3", {"mode": "repair", "state": "crashed", "faulty_part": "gpu", "fault_hidden": true, "label": "KI Umbau", "mainboard_id": "gpu_server", "components": t3}, _part_of_tier("gpu", 2))
	await _run_case("rep_switch", {"mode": "repair", "state": "crashed", "faulty_part": "", "label": "Switch", "mainboard_id": "net_switch", "components": {}})
	await _check_rules(t0)
	print("ERGEBNIS: %d Fehler" % bad)
	nm.call("leave_session")
	quit(1 if bad > 0 else 0)


func _part_of_tier(cat: String, tier: int) -> String:
	var hc: Script = load("res://scripts/data/hardware_catalog.gd")
	var f := ""
	for pd in hc.call("get_category_parts", cat):
		if int((pd as Dictionary).get("vtier", 0)) == tier:
			f = str(pd["id"])
			break
	return f


## Jeder Plan muss sich vollständig abarbeiten lassen und nur bekannte Teile benutzen.
func _check_plans() -> void:
	var ap: Script = load("res://scripts/data/assembly_plan.gd")
	var n := 0
	var fails := []
	for mb in ["web_server", "storage_server", "gpu_server", "net_switch"]:
		for tier in range(-1, 4):
			var comps := {}
			for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
				comps[cat] = "" if tier < 0 else _part_of_tier(cat, tier)
			for cat in ["", "cpu", "gpu", "ram", "storage", "cooling", "psu", "mainboard"]:
				for variant in ["assembly", "service", "kit", "hidden", "known", "part0", "part1", "part2", "part3"]:
					var mode: String = variant if variant in ["assembly", "service"] else "repair"
					if mode != "repair" and (cat != "" or mb == "net_switch"):
						continue
					if str(variant).begins_with("part") and not (cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]):
						continue
					var spare := {"kind": "kit", "id": "x"}
					if str(variant).begins_with("part"):
						spare = {"kind": "part", "id": _part_of_tier(cat, int(str(variant).substr(4)))}
					var plan: Dictionary = ap.call("build", {"mode": mode, "mainboard_id": mb, "components": comps, "faulty_part": cat,
						"fault_hidden": variant == "hidden", "diagnosed": variant == "known", "spare": spare})
					var done := {}
					var guard := 0
					while guard < 200:
						guard += 1
						var nt: Dictionary = ap.call("next_task", plan, done)
						if nt.is_empty():
							break
						if str(nt["kind"]) != "choose" and not (plan["items"] as Dictionary).has(nt["item"]):
							fails.append("%s/%s/%d/%s: Teil %s" % [variant, mb, tier, cat, nt["item"]])
						for k in (nt["set"] as Dictionary).keys():
							if not (plan["items"] as Dictionary).has(k):
								fails.append("%s/%s/%d/%s: Zustand %s" % [variant, mb, tier, cat, k])
						done[nt["id"]] = 1.0
					if not ap.call("is_complete", plan, done):
						fails.append("%s/%s/%d/%s unvollständig" % [variant, mb, tier, cat])
					n += 1
	chk("%d Montagepläne vollständig lösbar" % n, fails.is_empty(), fails.slice(0, 5))


func _run_case(label: String, wb: Dictionary, choice: String = "kit") -> void:
	if only != "" and not label.contains(only):
		return
	wb["done"] = {}
	wb["worker"] = 0
	wb["rack_id"] = ""
	wb["slot_idx"] = 0
	if choice != "kit":
		gs.parts_inventory[choice] = 1
	gs.bench_screws = 80
	gs.bench_paste = 10.0
	gs.workbench_state = wb.duplicate(true)
	var kcat := str(wb.get("faulty_part", ""))
	if kcat == "":
		kcat = "mainboard"
	if str(wb["mode"]) == "repair":
		var kid: String = gs.get_repair_kit_id_for_cat(kcat)
		gs.storage_shelf_slots["test:0"] = {"id": "k", "item_type": kid, "pos": Vector3.ZERO, "held_by": 0}
	var kits_before: int = gs.count_repair_kits(kcat)
	gs.workbench_changed.emit()
	for i in 5:
		await process_frame
	main.call("_open_workbench_ui")
	chk(label + ": Arbeitsplatz offen", ui.visible)
	if not ui.visible:
		return
	var piece: Node = ui.get("piece")
	var missing := []
	for id in piece.items.keys():
		var it: Object = piece.items[id]
		if it.aabb.size == Vector3.ZERO and not (str(it.spec["kind"]) in ["paste", "point"]):
			missing.append(id)
	chk(label + ": alle Modelle vorhanden", missing.is_empty(), missing)
	await _wait(0.8)
	await _shot(label + "_start")
	var total: int = ap_total(piece)
	var ap: Script = load("res://scripts/data/assembly_plan.gd")
	var t_start := Time.get_ticks_msec()
	var stuck := ""
	var count := 0
	while ui.visible and count < 190:
		var nt: Dictionary = ap.call("next_task", piece.plan, piece.done)
		if nt.is_empty():
			break
		count += 1
		if str(nt["kind"]) == "choose":
			await _shot(label + "_auswahl")
			gs.request_workbench_choose(choice)
			for i in 5:
				await process_frame
			total = ap_total(piece)
			if not piece.done.has("choose"):
				stuck = "Auswahl abgelehnt"
				break
			continue
		if str(nt["id"]) == "test_off" or str(nt["kind"]) == "measure":
			while not piece.is_post_finished():
				await process_frame
			await _wait(0.3)
			await _shot("%s_%s" % [label, nt["id"]])
		if not await _do_task(piece, nt):
			stuck = "%s (%s)" % [nt["id"], ui.get("_hint_lbl").text]
			break
		if count == int(total * 0.33) or count == int(total * 0.66) or count == total - 4:
			await _wait(0.5)
			await _shot("%s_%d" % [label, count])
	for i in 20:
		await process_frame
	chk("%s: %d/%d Handgriffe" % [label, count, total], stuck == "" and count == total, stuck)
	if str(gs.workbench_state.get("mode", "")) != "ready_tray":
		print("      Stand: ", gs.workbench_state)
	chk(label + ": Server fertig", str(gs.workbench_state.get("mode", "")) == "ready_tray" and not ui.visible, gs.workbench_state.get("mode", ""))
	print("      Dauer Automat: %.0f s" % (float(Time.get_ticks_msec() - t_start) / 1000.0))
	await _wait(0.3)
	if ui.visible:
		ui.call("close_workbench")
	chk(label + ": volle Bauqualität", int(gs.workbench_state.get("build_quality", -1)) >= (97 if str(wb["mode"]) != "repair" else 95), gs.workbench_state.get("build_quality"))
	if str(wb["mode"]) == "repair":
		if choice == "kit":
			chk(label + ": Kit verbraucht", gs.count_repair_kits(kcat) == kits_before - 1)
		else:
			chk(label + ": Teil verbraucht, Kit bleibt", int(gs.parts_inventory.get(choice, 0)) == 0 and gs.count_repair_kits(kcat) == kits_before)
			chk(label + ": neues Teil im Server", str((gs.workbench_state.get("components", {}) as Dictionary).get(kcat, "")) == choice)
	elif str(wb["mode"]) == "assembly":
		chk(label + ": Schrauben und Paste verbraucht", gs.bench_screws < 80 and gs.bench_paste < 10.0, [gs.bench_screws, gs.bench_paste])
	gs.workbench_state = {}
	gs.workbench_changed.emit()


func ap_total(piece: Node) -> int:
	var ap: Script = load("res://scripts/data/assembly_plan.gd")
	return int(ap.call("count_total", piece.plan))


func _do_task(piece: Node, task: Dictionary) -> bool:
	_key({"": KEY_1, "driver": KEY_2, "paste": KEY_3, "tweezers": KEY_4, "meter": KEY_5}[str(task["tool"])])
	await _wait(0.30)
	var item_id := str(task["item"])
	var it: Object = piece.items[item_id]
	var kind := str(task["kind"])
	var ok := false
	# Maus auf das Ziel, notfalls mehrere Punkte probieren (Teile können sich verdecken).
	for k in range(14):
		var pt: Vector3 = piece.anchor_of(item_id)
		if kind in ["place", "remove", "plug", "unplug", "lever", "press"] and k > 0:
			var f := Vector3(0.5 + 0.38 * sin(k * 2.1), 0.5 + 0.4 * cos(k * 1.3), 0.5 + 0.38 * cos(k * 2.7))
			pt = it.cur * (it.aabb.position + it.aabb.size * f)
		_aim(piece, pt)
		for i in 4:
			await process_frame
			_aim(piece, pt)
		var c: Dictionary = ui.call("_find_candidate")
		if not c.is_empty() and bool(c["ok"]) and str(c["task"]["id"]) == str(task["id"]):
			ok = true
			break
	if not ok:
		return false
	_button(true)
	if (ui.get("_action") as Dictionary).is_empty():
		return false
	var guard := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < guard:
		await process_frame
		if not ui.visible or piece.done.has(task["id"]):
			break
		var act: Dictionary = ui.get("_action")
		if act.is_empty():
			break
		match str(act["phase"]):
			"hold":
				_aim(piece, piece.anchor_of(item_id))
				if kind == "screw" and float(act["t"]) >= 1.03:
					_button(false)
			"paste":
				_aim(piece, piece.anchor_of(item_id))
				if float(act["t"]) >= 0.95:
					_button(false)
			"drag", "press":
				if int(act.get("turns", 0)) != 0:
					_key(KEY_R)
				var seat: Transform3D = piece.seat_xf(it)
				_aim_smooth(piece, seat.origin + Vector3(0.0, 0.016, 0.0))
			"carry":
				_aim_smooth(piece, Vector3(0.52, 0.0, 0.0))
				if act.get("waited", 0.0) > 0.5:
					_button(false)
				else:
					act["waited"] = float(act.get("waited", 0.0)) + 1.0 / 60.0
	_button(false)
	await _wait(0.12)
	return piece.done.has(task["id"]) or not ui.visible or str(gs.workbench_state.get("mode", "")) == "ready_tray"


func _aim(piece: Node, p_local: Vector3) -> void:
	var cam: Camera3D = ui.get("_cam")
	if is_instance_valid(cam):
		_move_mouse(cam.unproject_position(piece.global_transform * p_local))


## Echte Eingabe-Ereignisse, damit auch Fenster, Mausfilter und Tasten mitgeprüft werden.
func _move_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func _button(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = ui.get("_mouse")
	ev.global_position = ev.position
	root.push_input(ev, true)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	root.push_input(ev, true)


func _aim_smooth(piece: Node, p_local: Vector3) -> void:
	var cam: Camera3D = ui.get("_cam")
	if is_instance_valid(cam):
		var m: Vector2 = ui.get("_mouse")
		_move_mouse(m.lerp(cam.unproject_position(piece.global_transform * p_local), 0.14))


## Regeln auf dem Host: Reihenfolge, Belegung, kein Abkürzen per Aufnehmen, Speichern.
func _check_rules(comps: Dictionary) -> void:
	gs.workbench_state = {"mode": "assembly", "label": "Regeln", "mainboard_id": "web_server", "components": comps, "done": {}, "worker": 0, "rack_id": "", "slot_idx": 0}
	gs._rpc_req_workbench_task("mb_place", 1.0)
	chk("ohne Arbeitsplatz kein Handgriff", gs.get_workbench_done().is_empty())
	gs._rpc_req_workbench_enter()
	chk("Arbeitsplatz belegt", gs.get_workbench_worker() == 1)
	gs._rpc_req_workbench_task("lid_on", 1.0)
	chk("falsche Reihenfolge abgelehnt", gs.get_workbench_done().is_empty())
	gs._rpc_req_workbench_task("mb_place", 1.0)
	chk("richtiger Handgriff zählt", gs.get_workbench_done().has("mb_place"))
	gs._rpc_req_workbench_leave()
	var n0: int = gs.crates.size()
	gs._rpc_req_workbench_pickup()
	chk("angefangener Bau lässt sich nicht mitnehmen", gs.crates.size() == n0 and not gs.workbench_state.is_empty())
	var sm := root.get_node("SaveManager")
	sm.save_world("wbtest", "wbtest", gs.export_save_data())
	var l: Dictionary = sm.load_world_file("wbtest")
	gs.load_from_save_data(l["state"], "wbtest", "wbtest")
	chk("Stand nach Laden erhalten", gs.get_workbench_done().has("mb_place") and gs.get_workbench_worker() == 0)
	gs.workbench_state["done"] = {}
	gs._rpc_req_workbench_pickup()
	var got := ""
	for c in gs.crates.values():
		if int(c.get("held_by", 0)) == 1:
			got = str(c["item_type"])
	chk("unberührter Bausatz wird wieder Karton", got == "slot_build_box", got)

	# Reparatur: Auswahl, Reihenfolge, Verbrauchsmaterial
	gs.workbench_state = {"mode": "repair", "state": "crashed", "faulty_part": "ram", "fault_hidden": true, "label": "Regeln", "mainboard_id": "web_server", "components": _all_tier(2), "done": {}, "worker": 1, "rack_id": "", "slot_idx": 0}
	gs._rpc_req_workbench_choose("kit")
	chk("ohne Diagnose keine Auswahl", not gs.get_workbench_done().has("choose"))
	gs._rpc_req_workbench_task("meas_ram", 1.0)
	chk("ohne Strom keine Messung", not gs.get_workbench_done().has("meas_ram"))
	for t in ["diag_plug", "power_on", "lid_out0", "lid_out1", "lid_off", "meas_cpu", "meas_ram"]:
		gs._rpc_req_workbench_task(t, 1.0)
	gs._rpc_req_workbench_task("ram_open", 1.0)
	chk("unter Strom wird nichts ausgebaut", gs.get_workbench_done().has("meas_ram") and not gs.get_workbench_done().has("ram_open"))
	gs._rpc_req_workbench_choose("gibt_es_nicht")
	gs._rpc_req_workbench_choose(_part_of_tier("cpu", 2))
	chk("falsches Ersatzteil abgelehnt", not gs.get_workbench_done().has("choose"))
	gs.storage_shelf_slots["test:0"] = {"id": "k", "item_type": "kit_ram", "pos": Vector3.ZERO, "held_by": 0}
	gs._rpc_req_workbench_choose("kit")
	var p3 := _part_of_tier("ram", 3)
	gs.parts_inventory[p3] = 1
	gs._rpc_req_workbench_choose(p3)
	chk("Auswahl lässt sich ändern", str(gs.workbench_state["spare"]["id"]) == p3 and gs.get_workbench_done().has("meas_ram"))
	gs._rpc_req_workbench_task("power_off", 1.0)
	gs._rpc_req_workbench_task("ram_open", 1.0)
	gs._rpc_req_workbench_choose("kit")
	chk("nach dem ersten Handgriff ist die Wahl fest", str(gs.workbench_state["spare"]["id"]) == p3)
	var s0: int = gs.bench_screws
	gs.workbench_state = {"mode": "assembly", "label": "R", "mainboard_id": "web_server", "components": comps, "done": {}, "worker": 1, "rack_id": "", "slot_idx": 0}
	gs._rpc_req_workbench_task("mb_place", 1.0)
	gs._rpc_req_workbench_task("mb_in0", 1.0)
	chk("Schraube verbraucht", gs.bench_screws == s0 - 1)
	gs.bench_screws = 0
	gs._rpc_req_workbench_task("mb_in1", 1.0)
	chk("ohne Schrauben geht es nicht weiter", not gs.get_workbench_done().has("mb_in1"))
	gs._van_parcel_parts.append("acc:screw_box")
	gs._van_parcel_parts.append("acc:paste_tube")
	var p0: float = gs.bench_paste
	gs._deliver_parts_parcel()
	var supplies_ok: bool = gs.bench_screws == 100 and gs.bench_paste == p0 + 10.0
	await _check_mistakes()
	chk("Lieferung füllt die Werkbank auf", supplies_ok)
	gs.workbench_state = {}
	sm.delete_save("wbtest")


## Alle zwingenden Handgriffe erledigen; skip = Präfixe, die vergessen werden; val = Werte für Schrauben/Paste.
func _auto(skip: Array, until: String = "", screw: float = 1.0, paste: float = 1.0) -> void:
	var ap: Script = load("res://scripts/data/assembly_plan.gd")
	for guard in 200:
		if not gs.is_workbench_job():
			return
		var plan: Dictionary = ap.call("build", gs.workbench_state)
		var done: Dictionary = gs.get_workbench_done()
		var pick := {}
		for t in plan["tasks"]:
			if bool(t["optional"]) or not ap.call("is_available", plan, done, t["id"]):
				continue
			var skipped := false
			for s in skip:
				if str(t["id"]).begins_with(s):
					skipped = true
			if not skipped:
				pick = t
				break
		if pick.is_empty() or str(pick["id"]) == until:
			return
		if str(pick["kind"]) == "choose":
			gs.storage_shelf_slots["test:0"] = {"id": "k", "item_type": gs.get_workbench_kit_id(), "pos": Vector3.ZERO, "held_by": 0}
			gs._rpc_req_workbench_choose("kit")
			continue
		var n: int = gs.get_workbench_done().size()
		gs._rpc_req_workbench_task(str(pick["id"]), paste if str(pick["kind"]) == "paste" else screw)
		if gs.get_workbench_done().size() == n and gs.is_workbench_job():
			return


func _job(mode: String, extra: Dictionary = {}) -> void:
	gs.bench_screws = 300
	gs.bench_paste = 30.0
	gs.workbench_state = {"mode": mode, "label": "Fehler", "mainboard_id": "web_server", "components": _all_tier(2), "done": {}, "worker": 1, "rack_id": "", "slot_idx": 0}
	gs.workbench_state.merge(extra, true)


func _check_mistakes() -> void:
	_job("assembly")
	_auto([])
	chk("sauber gebaut: 100 %", gs.workbench_state.get("build_quality") == 100, gs.workbench_state.get("build_quality"))
	_job("assembly")
	_auto(["mb_in", "gpu_screw", "psu_in"])
	var q_miss := int(gs.workbench_state.get("build_quality", 0))
	chk("vergessene Schrauben kosten Qualität", q_miss < 75 and q_miss > 40, q_miss)
	_job("assembly")
	_auto([], "", 0.75, 1.0)
	chk("lockere Schrauben kosten Qualität", int(gs.workbench_state.get("build_quality", 0)) < 80, gs.workbench_state.get("build_quality"))
	_job("assembly")
	_auto([], "", 1.6, 1.4)
	var q_over := int(gs.workbench_state.get("build_quality", 0))
	chk("überdreht und zu viel Paste", q_over < 55, q_over)

	_job("assembly")
	_auto(["pwm_plug"], "test_off")
	chk("Testlauf meldet fehlendes Lüfterkabel", str(gs.workbench_state["test"]["code"]) == "F1", gs.workbench_state.get("test"))
	gs._rpc_req_workbench_task("test_off", 1.0)
	chk("nach dem Fehltest geht es weiter", not gs.get_workbench_done().has("test_on") and str(gs.workbench_state["mode"]) == "assembly")
	_auto([])
	chk("nach dem Nachstecken bestanden", str(gs.workbench_state["mode"]) == "ready_tray" and gs.workbench_state["build_quality"] == 100)
	_job("assembly")
	_auto(["atx_plug"], "test_off")
	chk("ohne 24-Pin kein Strom", str(gs.workbench_state["test"]["code"]) == "--")

	_job("assembly")
	_auto(["paste"], "test_off")
	chk("ohne Paste brennt die CPU durch", str(gs.workbench_state["test"]["kind"]) == "cpu")
	gs._rpc_req_workbench_task("test_off", 1.0)
	chk("wird zur CPU-Reparatur", str(gs.workbench_state["mode"]) == "repair" and str(gs.workbench_state["faulty_part"]) == "cpu" and gs.get_workbench_done().has("lid_off"))
	_auto([])
	chk("CPU ersetzt, Server fertig", str(gs.workbench_state["mode"]) == "ready_tray", gs.workbench_state.get("build_quality"))

	_job("repair", {"state": "crashed", "faulty_part": "ram", "fault_hidden": true})
	_auto(["power_off"], "ram_open")
	gs._rpc_req_workbench_task("ram_open", 1.0)
	gs._rpc_req_workbench_task("ram_out2", 1.0)
	chk("unter Strom: Kurzschluss", str(gs.workbench_state.get("extra_fault", "")) == "mainboard" and gs.get_workbench_done().has("power_off"))
	_auto([], "test_off")
	chk("Testlauf zeigt Mainboard-Schaden", str((gs.workbench_state.get("test", {}) as Dictionary).get("code", "")) == "b2", gs.workbench_state.get("test"))
	gs._rpc_req_workbench_task("test_off", 1.0)
	chk("wird zur Mainboard-Reparatur", str(gs.workbench_state["faulty_part"]) == "mainboard" and str(gs.workbench_state["mode"]) == "repair")
	_auto([])
	chk("Mainboard ersetzt, Kurzschluss kostet Qualität", str(gs.workbench_state["mode"]) == "ready_tray" and int(gs.workbench_state["build_quality"]) < 100, gs.workbench_state.get("build_quality"))

	_job("assembly")
	_auto(["cpu_place", "paste"], "diag_plug")
	gs._rpc_req_workbench_break("cpu_place")
	gs._rpc_req_workbench_task("cpu_place", 1.0)
	chk("verbogene CPU ist zerstört", gs.needs_workbench_replacement() and not gs.get_workbench_done().has("cpu_place"))
	var cpu3 := _part_of_tier("cpu", 3)
	gs.parts_inventory[cpu3] = 1
	gs._rpc_req_workbench_choose(cpu3)
	chk("neue CPU aus dem Lager", not gs.needs_workbench_replacement() and str(gs.workbench_state["components"]["cpu"]) == cpu3 and not gs.parts_inventory.has(cpu3))
	_auto([])
	chk("mit neuer CPU fertig", str(gs.workbench_state["mode"]) == "ready_tray")

	_job("repair", {"state": "crashed", "faulty_part": "cpu", "fault_hidden": true})
	_auto([], "cpu_place")
	gs._rpc_req_workbench_break("cpu_place")
	chk("Ersatz-CPU zerstört: neu wählen", gs.needs_workbench_replacement())
	gs.storage_shelf_slots["test:0"] = {"id": "k", "item_type": "kit_cpu", "pos": Vector3.ZERO, "held_by": 0}
	gs._rpc_req_workbench_choose("kit")
	_auto([])
	chk("Reparatur danach fertig", str(gs.workbench_state["mode"]) == "ready_tray", gs.workbench_state.get("mode"))

	# Wirkung im Betrieb
	var good: Dictionary = gs.get_slot_stats({"item_type": "web_server", "state": "ok", "components": _all_tier(2), "build_quality": 100})
	var bad: Dictionary = gs.get_slot_stats({"item_type": "web_server", "state": "ok", "components": _all_tier(2), "build_quality": 50})
	var old: Dictionary = gs.get_slot_stats({"item_type": "web_server", "state": "ok", "components": _all_tier(2)})
	chk("schlechte Qualität: wärmer, riskanter, langsamer", float(bad["heat"]) > float(good["heat"]) and float(bad["fault_mult"]) > float(good["fault_mult"]) and int(bad["compute"]) < int(good["compute"]), [good["heat"], bad["heat"], good["fault_mult"], bad["fault_mult"]])
	chk("alte Server unverändert", old["heat"] == good["heat"] and old["fault_mult"] == good["fault_mult"])

	# Notreparatur am Rack, Überholen an der Werkbank
	var rid: String = gs._alloc_id("rack")
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(0, 0, 0), 0.0)
	var s: Dictionary = gs.racks[rid]["slots"][0]
	s.merge({"item_type": "web_server", "state": "crashed", "faulty_part": "psu", "diagnosed": true, "components": _all_tier(2)}, true)
	gs.maint_kits = 0
	for i in 5:
		gs._rpc_req_repair_slot(rid, 0, 1.0)
	chk("Notreparatur am Rack: höchstens 50 %", str(s["state"]) == "ok" and gs.get_build_quality(s) == 50, s.get("build_quality"))
	for c in gs.crates.keys():
		if int(gs.crates[c].get("held_by", 0)) == 1:
			gs.crates.erase(c)
	gs.workbench_state = {}
	gs._rpc_req_pull_server_tray(rid, 0)
	gs._rpc_req_workbench_place()
	chk("Schlitten auf der Werkbank mit 50 %", gs.can_workbench_service() and gs.get_build_quality(gs.workbench_state) == 50, gs.workbench_state)
	gs._rpc_req_workbench_service()
	gs.workbench_state["worker"] = 1
	_auto([])
	chk("Überholt auf 100 %", gs.workbench_state.get("build_quality") == 100, gs.workbench_state.get("build_quality"))
	gs._rpc_req_workbench_pickup()
	gs._rpc_req_insert_server_tray(rid, 0)
	chk("Qualität kommt im Rack an", gs.get_build_quality(gs.racks[rid]["slots"][0]) == 100 and str(gs.racks[rid]["slots"][0]["item_type"]) == "web_server")
	var sm := root.get_node("SaveManager")
	gs.racks[rid]["slots"][0]["build_quality"] = 63
	sm.save_world("wbq", "wbq", gs.export_save_data())
	gs.load_from_save_data(sm.load_world_file("wbq")["state"], "wbq", "wbq")
	chk("Qualität überlebt das Speichern", gs.get_build_quality(gs.racks[rid]["slots"][0]) == 63)
	sm.delete_save("wbq")


func _all_tier(tier: int) -> Dictionary:
	var d := {}
	for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
		d[cat] = _part_of_tier(cat, tier)
	return d


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(label: String) -> void:
	if shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	shot_n += 1
	var img := root.get_texture().get_image()
	img.save_jpg("%s/%02d_%s.jpg" % [shots, shot_n, label], 0.88)
