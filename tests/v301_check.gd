extends SceneTree
## Prüft Drehen mit [R], Techniker-Wege und die Admin-Anmeldung auf dedizierten Servern.
## Aufruf: godot --headless --path . --script res://tests/v301_check.gd

var bad := 0
var gs: Node
var nm: Node
var tm: Node
var am: Node
var main: Node
var lp: Node


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func wait(s: float) -> void:
	await create_timer(s).timeout


func key(code: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = p
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func hold(item: String, extra: Dictionary = {}) -> String:
	gs.crates.clear()
	var cid: String = gs._alloc_id("crate")
	var c := {"id": cid, "item_type": item, "pos": Vector3.ZERO, "held_by": 1, "held_slot": gs.get_active_slot(1), "pack_count": 1}
	c.merge(extra, true)
	gs.crates[cid] = c
	gs._broadcast_crates()
	await wait(0.2)
	return cid


func aim(from: Vector3, at: Vector3) -> void:
	lp.global_position = from
	lp.velocity = Vector3.ZERO
	var d := at - (from + Vector3(0, 1.62, 0))
	lp.rotation.y = atan2(-d.x, -d.z)
	lp._head_pivot.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	await wait(0.35)


func turned(a: float, b: float) -> bool:
	return absf(absf(angle_difference(a, b)) - PI * 0.5) < 0.02


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	nm = root.get_node("NetworkManager")
	tm = root.get_node("TechnicianManager")
	am = root.get_node("AdminManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(0.3)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	nm.call("_start_host_internal", "Test", 7861, {}, "", "Dreh", "", false, false)
	await wait(1.2)
	gs.money = 99999.0
	lp = main.get("world").local_player
	await _placing()
	await _carrying()
	await _in_place()
	await _workbench()
	await _ways()
	await _admin()
	await _perf()
	print("ERGEBNIS Fehler ", bad)
	nm.call("leave_session")
	quit(1 if bad > 0 else 0)


func _placing() -> void:
	await aim(Vector3(0, 0.1, 1.6), Vector3(0, 0, -0.6))
	for t in ["rack", "ups", "cool_inrow", "prop_sofa", "prop_shelf_small"]:
		await hold(t)
		var a: float = lp._ghost_rot_y
		await key(KEY_R)
		await wait(0.1)
		chk("[R] dreht beim Aufstellen: " + t, lp._ghost_root.visible and turned(a, lp._ghost_rot_y), "%.0f -> %.0f" % [rad_to_deg(a), rad_to_deg(lp._ghost_rot_y)])
	# Rechts vom Garagentor auf dem Rasen
	gs.coolers.clear()
	var lawn := Vector3((gs.HEAT_PUMP_LAWN_MIN.x + gs.HEAT_PUMP_LAWN_MAX.x) * 0.5, 0, (gs.HEAT_PUMP_LAWN_MIN.y + gs.HEAT_PUMP_LAWN_MAX.y) * 0.5)
	await aim(lawn + Vector3(0, 0.1, 2.2), lawn)
	await hold("cooler")
	var ca: float = lp._ghost_rot_y
	await key(KEY_R)
	await wait(0.1)
	chk("[R] dreht Außengeräte", turned(ca, lp._ghost_rot_y))
	for i in 12:
		if lp._ghost_valid:
			break
		lawn += Vector3(0.5, 0, 0)
		await aim(lawn + Vector3(0, 0.1, 2.2), lawn)
	var want: float = lp._ghost_rot_y
	gs.request_place_held_structure(lp._ghost_pos, want)
	await wait(0.2)
	var cr := -9.0
	for c in gs.coolers.values():
		cr = float(c["rot_y"])
	chk("Außengerät steht gedreht", absf(angle_difference(cr, want)) < 0.02, cr)
	# An der Wand: erst Einrasten, dann von Hand drehen
	gs.decor_items.clear()
	gs._broadcast_decor_items()
	lp.place_rot_y = PI
	await aim(Vector3(-1.0, 0.1, -2.6), Vector3(-1.0, 0.0, -4.1))
	await hold("prop_shelf_small")
	var wa: float = lp._ghost_rot_y
	chk("Regal rastet an der Wand ein", absf(wa) < 0.02, wa)
	await key(KEY_R)
	await wait(0.15)
	chk("[R] dreht auch an der Wand", turned(wa, lp._ghost_rot_y), "%.0f -> %.0f" % [rad_to_deg(wa), rad_to_deg(lp._ghost_rot_y)])
	for i in 3:
		await key(KEY_R)
	await wait(0.15)
	chk("viermal [R] ist wieder die Wandrichtung", absf(angle_difference(wa, lp._ghost_rot_y)) < 0.02)
	await hold("prop_tool_cart")
	chk("neues Stück rastet wieder ein", not lp._rot_manual)
	gs.crates.clear()
	gs._broadcast_crates()
	await wait(0.1)


func _carrying() -> void:
	await aim(Vector3(0, 0.1, 1.6), Vector3(0, 0, -0.2))
	var cid: String = await hold("web_server")
	var g: float = lp._ghost_rot_y
	await key(KEY_R)
	await wait(0.4)
	chk("[R] dreht getragene Ware", turned(g, lp._ghost_rot_y) and absf(lp._held_item_holder.rotation.y) > 1.3, lp._held_item_holder.rotation.y)
	var yaw: float = lp.rotation.y + lp.hold_yaw
	lp._handle_drop()
	await wait(0.3)
	chk("Ware liegt gedreht", absf(angle_difference(float(gs.crates[cid].get("rot", -9.0)), yaw)) < 0.03, gs.crates[cid].get("rot"))
	var node = main.get("world")._crate_nodes[cid]
	chk("Karton steht sichtbar gedreht", absf(angle_difference(node.rotation.y, yaw)) < 0.03)
	var r0: float = node.rotation.y
	await aim(Vector3(node.position.x, 0.1, node.position.z + 1.3), node.position + Vector3(0, 0.15, 0))
	chk("Hinweis zum Drehen", lp.current_sub_prompt.contains("[R]"), lp.current_sub_prompt)
	await key(KEY_R)
	await wait(0.3)
	chk("[R] dreht den Karton am Boden", turned(r0, node.rotation.y))
	await hold("web_server")
	chk("neue Ware fängt gerade an", lp.hold_yaw == 0.0)
	gs.crates.clear()
	gs._broadcast_crates()


func _in_place() -> void:
	gs.decor_items.clear()
	gs.racks.clear()
	gs.ups_units.clear()
	gs.coolers.clear()
	gs.racks["r1"] = gs._make_rack_data("r1", "rack", Vector3(0.0, 0.0, -1.0), 0.0)
	gs.ups_units["u1"] = {"id": "u1", "ups_type": "ups_cabinet", "health": 100.0, "pos": Vector3(2.5, 0, 1.0), "rot_y": 0.0, "connected": false, "charge": 20.0, "discharging": false}
	gs.coolers["c1"] = {"id": "c1", "cooler_type": "cool_inrow", "pos": Vector3(-2.0, 0, 1.0), "rot_y": 0.0, "powered": false}
	gs.decor_items["d1"] = {"id": "d1", "item_type": "prop_sofa", "pos": Vector3(0.0, 0, 1.2), "rot_y": 0.0, "wall": false, "stored_items": []}
	gs.decor_items["d2"] = {"id": "d2", "item_type": "prop_pallet_rack", "pos": Vector3(-1.0, 0, -3.35), "rot_y": 0.0, "wall": false, "stored_items": []}
	gs._broadcast_racks(); gs._broadcast_ups(); gs._broadcast_coolers(); gs._broadcast_decor_items()
	await wait(0.3)
	for k in [["rack", "r1", gs.racks], ["ups", "u1", gs.ups_units], ["cooler", "c1", gs.coolers], ["decor", "d1", gs.decor_items]]:
		var ok: bool = gs.server_rotate(k[0], k[1], 1)
		chk("am Platz drehen: %s" % k[0], ok and absf(float(k[2][k[1]]["rot_y"]) - PI * 0.5) < 0.01)
	chk("Palettenregal dreht sich nicht in die Wand", not gs.server_rotate("decor", "d2", 1) and float(gs.decor_items["d2"]["rot_y"]) == 0.0)
	gs.decor_items["d3"] = {"id": "d3", "item_type": "prop_logo_sign", "pos": Vector3(1.0, 2.0, -4.3), "rot_y": 0.0, "wall": false, "stored_items": []}
	chk("Wandschild dreht nicht", not gs.server_rotate("decor", "d3", 1))
	chk("Unbekanntes wird abgelehnt", not gs.server_rotate("rack", "gibtsnicht", 1) and not gs.server_rotate("boese", "r1", 1))
	# Mit Blick und Taste
	var before: float = gs.racks["r1"]["rot_y"]
	for yy in [0.5, 0.8, 1.1, 1.4]:
		await aim(Vector3(1.35, 0.1, -1.0), Vector3(0.3, yy, -1.0))
		if lp._rotatable_kind(lp._get_aimed_interactable()) != "":
			break
	var tg = lp._get_aimed_interactable()
	var info := "%s %s hält %s" % [tg.get_meta("interact_type") if tg != null else "nichts", lp.global_position, gs.is_player_holding_anything(1)]
	await key(KEY_R)
	await wait(0.2)
	chk("[R] dreht das angeschaute Rack", turned(before, gs.racks["r1"]["rot_y"]), info)
	gs.decor_items.clear()
	gs.racks.clear(); gs.ups_units.clear(); gs.coolers.clear()
	gs._broadcast_racks(); gs._broadcast_ups(); gs._broadcast_coolers(); gs._broadcast_decor_items()


func _workbench() -> void:
	var hc: Script = load("res://scripts/data/hardware_catalog.gd")
	var comps := {}
	for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
		comps[cat] = str((hc.call("get_category_parts", cat)[0] as Dictionary)["id"])
	gs.workbench_state = {"mode": "assembly", "label": "Q", "mainboard_id": "web_server", "components": comps, "done": {}, "worker": 0, "rack_id": "", "slot_idx": 0}
	gs.bench_screws = 500
	gs.workbench_changed.emit()
	await wait(0.3)
	var wb = main.get("workbench_ui")
	main.call("_open_workbench_ui")
	await wait(0.6)
	chk("Werkbank offen", wb.visible)
	if not wb.visible:
		return
	var orb: float = wb._orbit.x
	wb._cand = {}
	await key(KEY_R)
	await wait(0.6)
	chk("[R] dreht den Blick", absf(wb._orbit.x - orb) > 0.4, wb._orbit.x)
	wb._orbit_goal = NAN
	wb._orbit.x = 0.0
	# CPU greifen und drehen
	var task := {}
	for t in wb.piece.plan["tasks"]:
		if str(t["id"]) == "cpu_place":
			task = t
	chk("CPU-Schritt da", not task.is_empty())
	if task.is_empty():
		return
	var t0: int = wb.piece.cpu_turns()
	chk("CPU liegt verdreht", t0 != 0, t0)
	wb._begin_action(task, str(task["item"]))
	await wait(0.2)
	var it = wb.piece.items[str(task["item"])]
	var b0: Basis = it.cur.basis.orthonormalized()
	await key(KEY_R)
	await wait(0.5)
	var ang := rad_to_deg(b0.get_rotation_quaternion().angle_to(it.cur.basis.orthonormalized().get_rotation_quaternion()))
	chk("[R] dreht die CPU sichtbar in der Hand", ang > 60.0, ang)
	chk("Drehung zählt", int(wb._action["turns"]) == (t0 + 1) % 4)
	wb._cancel_action()
	await wait(0.1)
	chk("losgelassen bleibt sie gedreht", wb.piece.cpu_turns() == (t0 + 1) % 4)
	wb._begin_action(task, str(task["item"]))
	chk("neu gegriffen: Drehung gemerkt", int(wb._action["turns"]) == (t0 + 1) % 4)
	wb._cancel_action()
	# Ohne Greifen: R auf der liegenden CPU
	var t1: int = wb.piece.cpu_turns()
	wb.set_process(false)
	wb._cand = {"task": task, "item": str(task["item"]), "ok": true}
	await key(KEY_R)
	wb.set_process(true)
	chk("[R] dreht die liegende CPU", wb.piece.cpu_turns() == (t1 + 1) % 4)
	# Anderes Teil
	var other := {}
	for t in wb.piece.plan["tasks"]:
		if str(t["kind"]) == "place" and not bool(wb.piece.items[str(t["item"])].spec.get("turns", false)) and str(wb.piece.items[str(t["item"])].spec["kind"]) != "screw":
			other = t
			break
	wb._begin_action(other, str(other["item"]))
	wb._mouse = Vector2(1100, 640)
	await wait(0.2)
	var oit = wb.piece.items[str(other["item"])]
	var ob: Basis = oit.cur.basis.orthonormalized()
	await key(KEY_R)
	await wait(0.5)
	var oang := rad_to_deg(ob.get_rotation_quaternion().angle_to(oit.cur.basis.orthonormalized().get_rotation_quaternion()))
	chk("[R] dreht auch andere Teile", oang > 45.0, "%s %.0f" % [other["item"], oang])
	wb._cancel_action()
	main.call("_close_workbench_ui")
	gs.workbench_state = {}
	gs.workbench_changed.emit()
	await wait(0.3)


func crosses_wall(path: Array) -> bool:
	# Außenwände und geschlossene Trennwände, Durchgänge ausgenommen.
	for i in range(1, path.size()):
		for k in 11:
			var p: Vector3 = (path[i - 1] as Vector3).lerp(path[i], float(k) / 10.0)
			if absf(p.x + 5.6) < 0.13 and absf(p.z) < 4.6 and not (p.z > 3.2 and p.z < 4.1): return true
			if absf(p.z - 4.6) < 0.13 and p.x > -5.6 and p.x < 21.6 and not (gs.garage_door_open and absf(p.x) < 2.0): return true
			if absf(p.z + 4.6) < 0.13 and p.x > -5.6 and p.x < 21.6: return true
			if gs.room_level < 1 and absf(p.x - 5.5) < 0.11 and absf(p.z) < 4.6: return true
			if gs.room_level < 2 and absf(p.x - 12.5) < 0.11 and absf(p.z) < 4.6: return true
	return false


func _ways() -> void:
	tm.set_process(false)
	tm.reset()
	gs.room_level = 0
	gs.garage_door_open = true
	var home: Vector3 = tm.HOME
	var goals := {"links draußen": Vector3(-8, 0, 0), "hinter der Halle": Vector3(3, 0, -7.5), "Einfahrt": Vector3(0.5, 0, 7.5), "rechts draußen": Vector3(24, 0, 2), "im Raum": Vector3(3.5, 0, 2.5)}
	for g in goals:
		var t0 := Time.get_ticks_usec()
		var p: Array = tm.find_path(home, goals[g])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		chk("Weg %s ohne Wand" % g, not p.is_empty() and not crosses_wall(p), "%d Punkte, %.1f ms" % [p.size(), ms])
		if not p.is_empty():
			var q: Array = tm.find_path(p[p.size() - 1], home)
			chk("  und zurück", not q.is_empty() and not crosses_wall(q), q.size())
	chk("gesperrte Halle B bleibt zu", tm.find_path(home, Vector3(9, 0, 0)).is_empty())
	gs.room_level = 2
	var pc: Array = tm.find_path(home, Vector3(18, 0, 1))
	chk("freigeschaltete Hallen erreichbar", not pc.is_empty() and not crosses_wall(pc), pc.size())
	gs.garage_door_open = false
	var pd: Array = tm.find_path(home, Vector3(0.5, 0, 7.5))
	chk("Tor zu: außen herum durch die Hintertür", not pd.is_empty() and not crosses_wall(pd), pd.size())
	var om = root.get_node("OutdoorManager")
	om.state["door"] = false
	tm._use_back_door(pd)
	chk("macht die Hintertür auf", bool(om.state["door"]))
	gs.garage_door_open = true
	# Große Möbel mit echten Maßen
	gs.decor_items["big"] = {"id": "big", "item_type": "prop_pallet_rack", "pos": Vector3(-1.0, 0, 0.5), "rot_y": 0.0, "wall": false, "stored_items": []}
	var pb: Array = tm.find_path(Vector3(-1.0, 0, 2.0), Vector3(-1.0, 0, -1.5))
	var hit := false
	for i in range(1, pb.size()):
		for k in 9:
			var b: Vector3 = (pb[i - 1] as Vector3).lerp(pb[i], float(k) / 8.0)
			if absf(b.x + 1.0) < 1.52 and absf(b.z - 0.5) < 0.53:
				hit = true
	chk("um das Palettenregal herum", pb.size() > 3 and not hit, pb.size())
	gs.decor_items.clear()
	# Ganz zugestellt: durch Möbel zwängen, aber nie durch Wände
	for i in 12:
		gs.racks["b%d" % i] = gs._make_rack_data("b%d" % i, "rack", Vector3(-2.4, 0, -4.4 + 0.8 * i), 0.0)
	var pz: Array = tm.find_path(home, Vector3(3.0, 0, 0.0))
	chk("zugestellt: kommt trotzdem an, ohne Wand", not pz.is_empty() and not crosses_wall(pz), pz.size())
	gs.racks.clear()
	gs.room_level = 0


func _perf() -> void:
	var hc: Script = load("res://scripts/data/hardware_catalog.gd")
	var comps := {}
	for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
		comps[cat] = str((hc.call("get_category_parts", cat)[2] as Dictionary)["id"])
	var slot := {"item_type": "web_server", "components": comps, "build_quality": 100, "state": "ok"}
	var a: Dictionary = gs.get_slot_stats(slot)
	chk("Serverwerte gemerkt = gerechnet", a == gs._compute_slot_stats(slot))
	# Das Ergebnis ist schreibgeschützt (keine Kopie je Abruf); wer ändern will, nimmt duplicate().
	chk("Serverwerte schreibgeschützt", a.is_read_only())
	var a2 := a.duplicate()
	a2["watts"] = -1
	chk("Änderungen an einer Kopie schlagen nicht auf den Speicher durch", int(gs.get_slot_stats(slot)["watts"]) > 0 and not a2.is_read_only())
	slot["build_quality"] = 40
	chk("Bauqualität zählt", float(gs.get_slot_stats(slot)["heat"]) > float(a["heat"]) and gs.get_slot_stats(slot) == gs._compute_slot_stats(slot))
	var w0: int = gs.get_slot_stats(slot)["watts"]
	comps["psu"] = ""
	chk("Teil ausgebaut zählt sofort", bool(gs.get_slot_stats(slot)["complete"]) == false and int(gs.get_slot_stats(slot)["watts"]) != w0)
	comps["psu"] = str((hc.call("get_category_parts", "psu")[5] as Dictionary)["id"])
	slot["build_quality"] = 100
	var h0: float = gs.get_slot_stats(slot)["heat"]
	gs.research_levels["cooling"] = 1
	chk("Forschung zählt sofort", float(gs.get_slot_stats(slot)["heat"]) < h0, "%.1f -> %.1f" % [h0, gs.get_slot_stats(slot)["heat"]])
	gs.research_levels.erase("cooling")
	var same := true
	for cat in hc.get("CATEGORY_ORDER"):
		for p in hc.call("get_category_parts", cat):
			if hc.call("get_part", cat, str(p["id"])) != p or hc.call("find_part_category", str(p["id"])) != cat:
				same = false
	chk("Bauteil-Tabelle findet jedes Teil", same and hc.call("get_part", "cpu", "") == {} and not (hc.call("get_part", "cpu", "quatsch") as Dictionary).is_empty())
	if DisplayServer.get_name() == "headless":
		return
	# Nur mit Bild: Server im Rack wird zusammengefasst
	gs.racks["pm"] = gs._make_rack_data("pm", "rack", Vector3(0.0, 0.0, -1.0), 0.0)
	gs.racks["pm"]["slots"][0].merge(slot, true)
	gs.racks["pm"]["powered"] = true
	gs._broadcast_racks()
	await aim(Vector3(0.0, 0.1, 0.6), Vector3(0.0, 1.0, -1.0))
	var mm = load("res://scripts/world/mesh_merger.gd").call("instance")
	for i in 80:
		await wait(0.1)
		if i > 10 and mm.is_idle():
			break
	var rp = main.get("world")._rack_nodes["pm"]
	var holder: Node3D = rp._slot_visuals[0]["hw_holder"]
	var merged := 0
	var single := 0
	var surf := 0
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		if n.mesh == null:
			continue
		if str(n.name).begins_with("Merged_"):
			merged += 1
			surf += n.mesh.get_surface_count()
		else:
			single += 1
	chk("Server zusammengefasst", merged == 2 and surf < 60 and single < 25, "%d Netze, %d Flächen, %d einzeln" % [merged, surf, single])
	var fans: Array = rp._slot_visuals[0]["hw_fans"]
	var alive := true
	for f in fans:
		alive = alive and is_instance_valid(f) and f.mesh != null
	chk("Lüfter bleiben einzeln", alive, fans.size())
	var fx = rp._slot_visuals[0]["hw_fx"]
	fx.dust = 80.0
	rp.set_process(false)
	await wait(0.3)
	chk("Staub erscheint auf dem zusammengefassten Netz", fx._ov_on and (fx._ov_meshes[fx._ov_meshes.size() - 1] as MeshInstance3D).material_overlay != null)
	fx.dust = 0.0
	fx.temp = 30.0
	await wait(0.3)
	chk("ohne Staub wird kein Überzug gezeichnet", not fx._ov_on)
	rp.set_process(true)
	# Teil wechseln baut neu auf und fasst wieder zusammen
	gs.racks["pm"]["slots"][0]["components"]["ram"] = str((hc.call("get_category_parts", "ram")[6] as Dictionary)["id"])
	gs._broadcast_racks()
	for i in 80:
		await wait(0.1)
		if i > 35 and mm.is_idle():
			break
	merged = 0
	for n in rp._slot_visuals[0]["hw_holder"].find_children("Merged_*", "MeshInstance3D", true, false):
		merged += 1
	chk("nach dem Umbau wieder zusammengefasst", merged == 2, merged)
	gs.racks.erase("pm")
	gs._broadcast_racks()
	await wait(0.2)


func _admin() -> void:
	var fake := 4242
	nm.players[fake] = {"name": "Fern", "color": Color.WHITE, "skin": {}}
	chk("Fremder ist kein Admin", not am.is_admin(fake) and not am.execute(fake, "money_add", {"v": 5}))
	chk("Konsole gibt Rechte", am.set_admin_from_console(fake, true) and am.is_admin(fake) and am.is_owner(fake))
	chk("Anmeldung darf alles", am.execute(fake, "money_add", {"v": 5}))
	nm.players[4343] = {"name": "Zwei", "color": Color.WHITE, "skin": {}}
	chk("darf andere freischalten", am.execute(fake, "grant", {"peer": 4343}) and am.is_admin(4343) and not am.is_owner(4343))
	chk("Freigeschaltete dürfen das nicht", not am.execute(4343, "revoke", {"peer": fake}) and not am.execute(4343, "kick", {"peer": fake}))
	chk("Konsole nimmt Rechte", am.set_admin_from_console(fake, false) and not am.is_admin(fake))
	chk("doppelt ändert nichts", not am.set_admin_from_console(fake, false))
	chk("Beweis hängt an Zufall und Passwort", am._login_proof("a", "x") != am._login_proof("b", "x") and am._login_proof("a", "x") != am._login_proof("a", "y"))
	nm.players.erase(fake)
	nm.players.erase(4343)
	am._reset()
	chk("nach der Sitzung ist alles weg", not am.is_admin(4343) and not am.login_available)
	var ui = main.get("admin_ui")
	am._granted.clear()
	ui._build_login()
	chk("Anmeldefenster lässt sich bauen", ui._login_msg != null)
