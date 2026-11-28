extends SceneTree
## Prüft angestellte Techniker und das Profi-Werkzeug im Zeitraffer.
## Aufruf: godot --headless --path . --script res://tests/technician_check.gd

var bad := 0
var gs: Node
var fm: Node
var tm: Node
var hc: Script


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


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


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	fm = root.get_node("FinanceManager")
	tm = root.get_node("TechnicianManager")
	hc = load("res://scripts/data/hardware_catalog.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	main.get("intro_splash").set_process(false)
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Test", 7798, {}, "", "Technikertest", "", false, false)
	for i in 10:
		await process_frame
	tm.set_process(false)
	fm.set_process(false)
	gs.set_process(false)
	gs.money = 100000.0

	# --- Einstellen
	var idx := {}
	for i in range(fm.CANDIDATE_POOL.size()):
		if str(fm.CANDIDATE_POOL[i]["role"]) == "technician":
			idx[int(fm.CANDIDATE_POOL[i]["skill"])] = i
	chk("Techniker bewerben sich", idx.has(2) and idx.has(5), idx)
	gs.time_of_day = 0.5
	fm._do_hire(idx[5], 1)
	fm._do_hire(idx[2], 1)
	var techs: Array = tm.get_technicians()
	chk("zwei eingestellt, zweite Person nachts", techs.size() == 2 and str(techs[0]["shift"]) == "day" and str(techs[1]["shift"]) == "night")
	tm.tick(0.1)
	chk("tagsüber arbeitet die Tagschicht", str(tm.view.get("name", "")) == "Alex Brandt", tm.view.get("name"))

	# --- Bausatz bauen und einsetzen
	var rid: String = gs._alloc_id("rack")
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(1.0, 0.0, -2.0), 0.0)
	gs.bench_screws = 500
	gs.bench_paste = 50.0
	_kit_box(rid, 0)
	var t := _run(func(): return str(gs.racks[rid]["slots"][0]["item_type"]) != "", 400.0)
	chk("Bausatz gebaut und im Rack", t > 0.0, "%.0f s, Qualität %d" % [t, gs.get_build_quality(gs.racks[rid]["slots"][0])])
	chk("gute Qualität bei viel Erfahrung", gs.get_build_quality(gs.racks[rid]["slots"][0]) >= 85)
	chk("Werkbank wieder frei", gs.workbench_state.is_empty(), gs.workbench_state)
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)

	# --- Reparatur mit Kit
	var s: Dictionary = gs.racks[rid]["slots"][0]
	_clear_kits()
	s.merge({"state": "crashed", "faulty_part": "ram", "fault_hidden": true, "diagnosed": false}, true)
	t = _run(func(): return not gs.workbench_state.is_empty(), 40.0)
	chk("ohne Ersatzteil bleibt der Server im Rack", t < 0.0 and str(gs.racks[rid]["slots"][0]["state"]) == "crashed", tm._warned)
	_kit("kit_ram")
	t = _run(func(): return str(gs.racks[rid]["slots"][0]["item_type"]) != "" and str(gs.racks[rid]["slots"][0]["state"]) == "ok", 400.0)
	chk("mit Kit repariert und eingesetzt", t > 0.0 and gs.count_repair_kits("ram") == 0, "%.0f s" % t)
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)

	# --- Reparatur mit Teil aus dem Lager
	gs.racks[rid]["slots"][0].merge({"state": "crashed", "faulty_part": "psu", "fault_hidden": false, "diagnosed": false}, true)
	gs.parts_inventory[_part("psu", 3)] = 1
	t = _run(func(): return str(gs.racks[rid]["slots"][0]["item_type"]) != "" and str(gs.racks[rid]["slots"][0]["state"]) == "ok", 400.0)
	chk("mit Teil aus dem Lager repariert", t > 0.0 and str(gs.racks[rid]["slots"][0]["components"]["psu"]) == _part("psu", 3), "%.0f s" % t)
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)

	# --- Überholen
	gs.racks[rid]["slots"][0]["build_quality"] = 45
	t = _run(func(): return str(gs.racks[rid]["slots"][0]["item_type"]) != "" and gs.get_build_quality(gs.racks[rid]["slots"][0]) > 80, 400.0)
	chk("schlechten Server überholt", t > 0.0, gs.get_build_quality(gs.racks[rid]["slots"][0]))
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)
	gs.racks[rid]["slots"][0]["build_quality"] = 45
	gs.racks[rid]["services"] = [{"type": "web", "customer": "X", "users": 1.0, "trend": 0.0}]
	t = _run(func(): return not gs.workbench_state.is_empty(), 30.0)
	chk("vermietete Racks werden nicht zum Überholen geleert", t < 0.0)
	gs.racks[rid]["services"] = []
	gs.racks[rid]["slots"][0]["build_quality"] = 100

	# --- Aufgaben abschalten
	tm._rpc_req_set_duty(str(techs[0]["id"]), "build", false)
	_kit_box(rid, 1)
	t = _run(func(): return not gs.workbench_state.is_empty(), 30.0)
	chk("ohne Aufgabe 'Bauen' wird nicht gebaut", t < 0.0)
	tm._rpc_req_set_duty(str(techs[0]["id"]), "build", true)

	# --- Spieler übernimmt
	t = _run(func(): return gs.get_workbench_worker() == -1 and gs.get_workbench_done().size() > 6, 200.0)
	chk("Techniker baut", t > 0.0)
	gs._do_workbench_enter()
	var n: int = gs.get_workbench_done().size()
	chk("Spieler übernimmt den Platz", gs.get_workbench_worker() == 1 and n > 6)
	_run(func(): return false, 10.0)
	chk("Techniker wartet solange", gs.get_workbench_done().size() == n and gs.get_workbench_worker() == 1, tm.view.get("text"))
	gs._do_workbench_leave()
	t = _run(func(): return str(gs.racks[rid]["slots"][1]["item_type"]) != "", 400.0)
	chk("danach baut der Techniker weiter", t > 0.0)
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)

	# --- Schichtwechsel
	gs.time_of_day = 0.9
	_run(func(): return str(tm.view.get("name", "")) == "Kim Vogt", 5.0)
	chk("nachts übernimmt die Nachtschicht", str(tm.view.get("name", "")) == "Kim Vogt", tm.view.get("name"))
	tm._rpc_req_set_shift(str(techs[1]["id"]), "day")
	_run(func(): return tm.view.is_empty(), 5.0)
	chk("ohne Nachtschicht ist niemand da", tm.view.is_empty())
	tm._rpc_req_set_shift(str(techs[1]["id"]), "night")
	_run(func(): return not tm.view.is_empty(), 5.0)

	# --- Weniger Erfahrung = schlechter und langsamer
	var q5 := _avg_quality(5)
	var q2 := _avg_quality(2)
	chk("Erfahrung zählt", q5[0] > q2[0] and q5[1] < q2[1], "Stufe 5: %.0f %% in %.0f s, Stufe 2: %.0f %% in %.0f s" % [q5[0], q5[1], q2[0], q2[1]])
	gs.bench_tools = {"akku": true, "torque": true, "paste_gun": true}
	var q2t := _avg_quality(2)
	chk("Profi-Werkzeug hilft dem Techniker", q2t[0] > q2[0] and q2t[1] < q2[1], "%.0f %% in %.0f s" % [q2t[0], q2t[1]])
	gs.bench_tools = {}

	# --- Entlassen mitten in der Arbeit
	_kit("kit_ram")
	gs.racks[rid]["slots"][0].merge({"state": "crashed", "faulty_part": "ram", "fault_hidden": true, "diagnosed": false}, true)
	t = _run(func(): return str(tm._job.get("carry", "")) != "", 60.0)
	var cid := str(tm._job.get("carry", ""))
	chk("Techniker trägt den Server", t > 0.0 and int(gs.crates[cid]["held_by"]) == -1)
	# Speichern beim Tragen
	var sm := root.get_node("SaveManager")
	sm.save_world("techtest", "techtest", gs.export_save_data())
	fm._do_fire(str(techs[1]["id"]), 1)
	tm.tick(0.1)
	chk("entlassen: Server liegt auf dem Boden", gs.crates.has(cid) and int(gs.crates[cid]["held_by"]) == 0 and tm.view.is_empty())
	gs.load_from_save_data(sm.load_world_file("techtest")["state"], "techtest", "techtest")
	tm.reset()
	gs.time_of_day = 0.9
	t = _run(func(): return str(gs.racks[rid]["slots"][0]["item_type"]) != "" and str(gs.racks[rid]["slots"][0]["state"]) == "ok", 500.0)
	chk("nach dem Laden holt er den Server vom Boden und macht fertig", t > 0.0, "%.0f s" % t)
	sm.delete_save("techtest")
	_run(func(): return tm._phase == "idle" and tm._job.is_empty(), 60.0)

	# --- Halle Nord mit dem Shuttle
	gs.halle_nord_owned = true
	var nid: String = gs._alloc_id("rack")
	# Abschnitt 1 der neuen Halle Nord (v3.8)
	gs.racks[nid] = gs._make_rack_data(nid, "rack", Vector3(-6.0, 0.0, -320.0), 0.0)
	gs.racks[nid]["slots"][0].merge({"item_type": "web_server", "state": "crashed", "faulty_part": "cooling", "components": _comps(1)}, true)
	_kit("kit_cooling")
	t = _run(func(): return str(gs.racks[nid]["slots"][0]["item_type"]) != "" and str(gs.racks[nid]["slots"][0]["state"]) == "ok", 600.0)
	chk("repariert auch in Halle Nord", t > 0.0, "%.0f s" % t)

	# --- Weg um Racks herum
	gs.racks["rack_block"] = gs._make_rack_data("rack_block", "rack", Vector3(-1.5, 0.0, 1.0), 0.0)
	var path: Array = tm.find_path(Vector3(-3.5, 0.0, 1.0), Vector3(1.0, 0.0, 1.0))
	var clear := path.size() > 3
	for i in range(1, path.size()):
		for k in 6:
			var p: Vector3 = (path[i - 1] as Vector3).lerp(path[i], float(k) / 5.0)
			if Vector2(p.x + 1.5, p.z - 1.0).length() < 0.45:
				clear = false
	chk("Weg führt um das Rack herum", clear, path.size())
	gs.racks.erase("rack_block")

	_check_tools()
	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").call("leave_session")
	quit(1 if bad > 0 else 0)


## Zeitraffer; liefert die Dauer oder -1, wenn es nicht rechtzeitig klappt.
func _run(done: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		tm.tick(0.1)
		t += 0.1
		if done.call():
			return t
	return -1.0


func _kit_box(rack_id: String, slot: int, tier: int = 1) -> void:
	var cid: String = gs._alloc_id("crate")
	gs.crates[cid] = {"id": cid, "item_type": "slot_build_box", "pos": Vector3(0.5, 0.0, 7.0), "held_by": 0, "label": "Bausatz",
		"build_data": {"rack_id": rack_id, "slot_idx": slot, "rack_label": "R", "mainboard_id": "web_server", "components": _comps(tier)}}


func _kit(item: String) -> void:
	gs.storage_shelf_slots["test:%s" % item] = {"id": "k", "item_type": item, "pos": Vector3.ZERO, "held_by": 0}


func _clear_kits() -> void:
	for d in gs.decor_items.values():
		for key in ["stored_items", "kits"]:
			var list: Array = d.get(key, [])
			for i in list.size():
				if list[i] is Dictionary and gs.is_repair_kit(str(list[i].get("item_type", ""))):
					list[i] = null
	for k in gs.storage_shelf_slots.keys():
		if gs.is_repair_kit(str(gs.storage_shelf_slots[k].get("item_type", ""))):
			gs.storage_shelf_slots.erase(k)
	for c in gs.crates.keys():
		if gs.is_repair_kit(str(gs.crates[c].get("item_type", ""))):
			gs.crates.erase(c)


## Mittlere Qualität und Dauer von sechs Bauten an der Werkbank.
func _avg_quality(skill: int) -> Array:
	var id: String = str(tm._emp_id)
	fm.employees[id]["skill"] = skill
	var q := 0.0
	var dur := 0.0
	tm._rng.seed = 4711
	for i in 16:
		gs.bench_screws = 500
		gs.bench_paste = 50.0
		gs.workbench_state = {"mode": "assembly", "label": "Q", "mainboard_id": "web_server", "components": _comps(2), "done": {}, "worker": 0, "rack_id": "", "slot_idx": 0}
		tm._yield_left = 0.0
		tm._job = {}
		dur += maxf(0.0, _run(func(): return str(gs.workbench_state.get("mode", "")) == "ready_tray", 600.0))
		q += float(gs.get_build_quality(gs.workbench_state))
		gs.workbench_state = {}
		_run(func(): return tm._phase == "idle", 30.0)
	return [q / 16.0, dur / 16.0]


func _check_tools() -> void:
	gs.workbench_state = {}
	gs.bench_tools = {}
	chk("Kupplung braucht den Akkuschrauber", gs._accessory_order_room("tool_torque") == 0 and gs._accessory_order_room("tool_akku") == 1 and gs._accessory_price("tool_akku") == 180)
	gs._van_parcel_parts.append("acc:tool_akku")
	gs._deliver_parts_parcel()
	chk("Werkzeug geliefert", gs.has_bench_tool("akku") and gs.get_tool_time_mult("screw") < 1.0 and gs._accessory_order_room("tool_akku") == 0 and gs._accessory_order_room("tool_torque") == 1)
	var m0: float = gs.money
	gs._van_parcel_parts.append("acc:tool_akku")
	gs._deliver_parts_parcel()
	chk("doppelt geliefert: Geld zurück", gs.money == m0 + 180.0)
	var sm := root.get_node("SaveManager")
	sm.save_world("tooltest", "tooltest", gs.export_save_data())
	gs.load_from_save_data(sm.load_world_file("tooltest")["state"], "tooltest", "tooltest")
	chk("Werkzeug überlebt das Speichern", gs.has_bench_tool("akku") and not gs.has_bench_tool("rcd"))
	sm.delete_save("tooltest")
	# Personenschutz-Schalter
	gs.bench_tools = {"rcd": true}
	gs.workbench_state = {"mode": "repair", "state": "crashed", "faulty_part": "cooling", "fault_hidden": true, "label": "R", "mainboard_id": "web_server", "components": _comps(2), "done": {}, "worker": 1, "rack_id": "", "slot_idx": 0}
	_kit("kit_cooling")
	for id in ["diag_plug", "power_on", "lid_out0", "lid_out1", "lid_off", "meas_cooling"]:
		gs.server_workbench_task(1, id, 1.0)
	gs.server_workbench_choose(1, "kit")
	gs.server_workbench_task(1, "pwm_unplug", 1.0)
	chk("Personenschutz-Schalter rettet das Mainboard", str(gs.workbench_state.get("extra_fault", "")) == "" and gs.get_workbench_done().has("power_off") and gs.get_workbench_done().has("pwm_unplug"))
