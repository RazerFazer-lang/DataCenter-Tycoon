extends SceneTree
## Prüft Roadmap-Paket C: Regale, Einrichtung, zweite Werkbank, Kameras, Diebe, Lieferung.
## Aufruf: godot --headless --path . --script res://tests/paketc_check.gd

var bad := 0
var gs: Node
var dm: Node
var sm: Node
var main: Node
var SS: GDScript
var DS: GDScript
var me := 1


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	gs = root.get_node("GameState")
	dm = root.get_node("DecorManager")
	sm = root.get_node("SaveManager")
	SS = load("res://scripts/data/shelf_spec.gd")
	DS = load("res://scripts/data/decor_spec.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Test", 7844, {}, "", "PaketC", "", false, false)
	await wait(20)
	me = root.multiplayer.get_unique_id()
	gs.money = 50000.0
	gs.room_level = 1
	gs.time_of_day = 0.5
	await _shelves()
	await _placing()
	await _decor()
	await _bench()
	await _aisle()
	await _cams()
	await _thief()
	if has_method("_delivery"):
		await call("_delivery")
	await _save()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


func _crate(t: String, hold: bool = true, pack: int = 1) -> String:
	var cid: String = gs._alloc_id("crate")
	gs.crates[cid] = {"id": cid, "item_type": t, "pos": Vector3(0, 0, 0), "held_by": me if hold else 0, "held_slot": gs.get_active_slot(me), "pack_count": pack}
	return cid


func _drop_all() -> void:
	for c in gs.crates.keys():
		if int(gs.crates[c].get("held_by", 0)) != 0:
			gs.crates.erase(c)


func _add(t: String, pos: Vector3, rot: float = 0.0) -> String:
	var did: String = gs._alloc_id("decor")
	gs.decor_items[did] = {"id": did, "item_type": t, "pos": pos, "rot_y": rot, "stored_items": []}
	gs._broadcast_decor_items()
	return did


func _shelves() -> void:
	print("--- Regale")
	chk("Start-Regal steht", gs.decor_items.has("decor_start") and str(gs.decor_items["decor_start"]["item_type"]) == "prop_storage_shelf")
	var kits := 0
	for e in gs.decor_items["decor_start"]["stored_items"]:
		if e is Dictionary:
			kits += 1
	chk("Start-Kits liegen darin", kits >= 4, kits)
	chk("Kits werden gezählt", gs.count_repair_kits("ram") >= 1, gs.count_repair_kits("ram"))
	var pal: Dictionary = {"item_type": "rack"}
	chk("Rack braucht eine Palette", SS.needs_pallet(pal) and SS.span("prop_storage_shelf", pal) == 0 and SS.span("prop_pallet_rack", pal) == 1)
	chk("Kit braucht einen Platz", SS.span("prop_storage_shelf", {"item_type": "kit_ram"}) == 1)
	chk("Server-Karton braucht zwei", SS.span("prop_storage_shelf", {"item_type": "web_server"}) == 2)
	chk("Server passt nicht ins Kleinteileregal", SS.span("prop_shelf_small", {"item_type": "web_server"}) == 0)
	chk("leerer Karton nicht einlagerbar", SS.span("prop_storage_shelf", {"item_type": "empty_carton"}) == 0)
	# Alles, was im Shop ist, muss irgendwo hineinpassen.
	var nofit: Array = []
	for t in gs.ITEM_CATALOG.keys():
		var cat := str(gs.ITEM_CATALOG[t].get("category", ""))
		if t == "cart" or t == "empty_carton" or t == "slot_build_box" or cat == "":
			continue
		if SS.span("prop_pallet_rack", {"item_type": t}) == 0:
			nofit.append(t)
	chk("jede Ware passt ins Palettenregal", nofit.is_empty(), nofit)
	var over: Array = []
	for t in gs.ITEM_CATALOG.keys():
		var d: Vector3 = SS.dims({"item_type": t})
		for s in SS.SPECS.keys():
			var n: int = SS.span(s, {"item_type": t})
			if n > 0 and not bool(SS.SPECS[s]["pallet"]) and d.x > float(n) * float(SS.SPECS[s]["unit_w"]) + 0.01:
				over.append([t, s])
	chk("keine Ware ragt über ihre Plätze hinaus", over.is_empty(), over)
	var did := _add("prop_storage_shelf", Vector3(2.0, 0, 0.5))
	await wait(3)
	_drop_all()
	_crate("web_server")
	gs.request_decor_shelf_interact(did, 4)
	await wait(2)
	var arr: Array = gs.decor_items[did]["stored_items"]
	chk("Server rutscht auf freie Plätze 3 und 4", arr[3] is Dictionary and SS.owner_of(gs.decor_items[did], 4) == 3, arr.slice(0, 5))
	_crate("ups")
	gs.request_decor_shelf_interact(did, 3)
	await wait(2)
	chk("belegter Platz wird abgelehnt", not gs.get_player_held_crate(me).is_empty())
	_drop_all()
	gs.request_decor_shelf_interact(did, 4)
	await wait(2)
	chk("Herausnehmen über zweiten Platz", str(gs.get_player_held_crate(me).get("item_type", "")) == "web_server" and SS.owner_of(gs.decor_items[did], 3) < 0)
	_drop_all()
	_crate("rack")
	gs.request_decor_shelf_interact(did, 0)
	await wait(2)
	chk("Rack kommt nicht ins Schwerlastregal", not gs.get_player_held_crate(me).is_empty())
	_drop_all()
	var pr := _add("prop_pallet_rack", Vector3(9.0, 0, 0.5))
	_crate("rack")
	gs.request_decor_shelf_interact(pr, 4)
	await wait(2)
	chk("Rack steht im Palettenregal", gs.get_player_held_crate(me).is_empty() and gs.decor_items[pr]["stored_items"][4] is Dictionary)
	_crate("kit_cpu", true, 6)
	var sh := _add("prop_shelf_small", Vector3(9.0, 0, 3.0))
	var before: int = gs.count_repair_kits("cpu")
	gs.request_decor_shelf_interact(sh, 0)
	await wait(2)
	chk("Mengenkiste bleibt zusammen", gs.count_repair_kits("cpu") == before and gs.get_player_held_crate(me).is_empty(), before)
	gs._consume_repair_kit_server(me, "cpu")
	chk("Verbrauch aus dem Regal", gs.count_repair_kits("cpu") == before - 1)
	# 3D: Ware steht auf dem Boden ihres Fachs
	await wait(5)
	var float_bad: Array = []
	var seen := 0
	for s in root.find_children("*", "Node3D", true, false):
		if s.get_script() != null and str((s.get_script() as Script).resource_path).ends_with("shelf_prop.gd"):
			seen += 1
	chk("Regale sind in der Welt", seen >= 4, seen)
	chk("nichts schwebt", float_bad.is_empty(), float_bad)
	var n_crates: int = gs.crates.size()
	gs.request_sell_decor(pr)
	await wait(3)
	chk("Verkauf: Ware bleibt stehen", gs.crates.size() == n_crates + 1 and not gs.decor_items.has(pr))
	gs.decor_items.erase(did)
	gs.decor_items.erase(sh)
	gs.crates.clear()
	gs._broadcast_decor_items()


func _placing() -> void:
	print("--- Aufstellen")
	var s: Dictionary = DS.snap_pose("prop_storage_shelf", Vector3(-2.0, 0, -4.0), 1.2)
	chk("rastet mit dem Rücken an der Nordwand ein", absf(float(s["rot_y"])) < 0.01 and absf((s["pos"] as Vector3).z - (gs.WALL_FACE_NORTH_Z + 0.34 + 0.015)) < 0.01, s)
	var a := _add("prop_storage_shelf", Vector3(8.0, 0, -1.0))
	var b: Dictionary = DS.snap_pose("prop_storage_shelf", Vector3(10.2, 0, -0.8), 0.0)
	chk("rastet am Nachbarregal ein", absf((b["pos"] as Vector3).x - 9.972) < 0.01 and absf((b["pos"] as Vector3).z + 1.0) < 0.01, b)
	chk("Nachbarplatz ist frei", DS.can_place("prop_storage_shelf", b["pos"], float(b["rot_y"])))
	chk("nicht ineinander", not DS.can_place("prop_storage_shelf", Vector3(8.6, 0, -1.0), 0.0))
	chk("nicht in der Wand", not DS.can_place("prop_sofa", Vector3(0.0, 0, -4.5), 0.0))
	chk("nicht vor dem Tor", not DS.can_place("prop_sofa", Vector3(0.0, 0, 3.6), 0.0))
	chk("nicht vor Router, Stromkasten oder Feuerlöscher", not DS.can_place("prop_storage_shelf", Vector3(-1.0, 0, -4.12), 0.0) and not DS.can_place("prop_shelf_small", Vector3(-2.8, 0, -4.2), 0.0) and DS.can_place("prop_storage_shelf", Vector3(0.50, 0, -4.12), 0.0))
	chk("nicht auf dem Schreibtisch", not DS.can_place("prop_water", Vector3(2.8, 0, -3.5), 0.0))
	var sg: Dictionary = DS.sign_spot(Vector3(-1.0, 2.0, gs.WALL_FACE_NORTH_Z), Vector3(0, 0, 1))
	chk("Leuchtschild hängt an der Wand", not sg.is_empty() and absf((sg["pos"] as Vector3).y - 2.0) < 0.01, sg)
	chk("Leuchtschild nicht über dem Tor", not DS.can_place_sign(Vector3(0.0, 2.0, gs.WALL_FACE_SOUTH_Z - 0.062), PI))
	_crate("prop_sofa")
	gs.request_place_held_structure(Vector3(8.0, 0, 2.0), 0.0)
	await wait(3)
	var ok := false
	for d in gs.decor_items.values():
		ok = ok or str(d["item_type"]) == "prop_sofa"
	chk("Sofa aufstellen über den Spielweg", ok)
	gs.crates.clear()
	gs.request_relocate_decor(a, Vector3(10.0, 0, 1.5), PI / 2.0)
	await wait(3)
	chk("Regal umsetzen", (gs.decor_items[a]["pos"] as Vector3).distance_to(Vector3(10.0, 0, 1.5)) < 0.1, gs.decor_items[a]["pos"])
	gs.decor_items.erase(a)
	gs._broadcast_decor_items()


func _decor() -> void:
	print("--- Einrichtung")
	var v := _add("prop_vending_lounge", Vector3(8.0, 0, -3.0))
	var m0: float = gs.money
	dm.request_use(v)
	await wait(2)
	chk("Kaffee kostet $4", absf(m0 - gs.money - 4.0) < 0.01, m0 - gs.money)
	chk("Kaffee macht schneller", dm.has_buff(me, "coffee") and dm.walk_mult(me) > 1.1 and dm.work_mult(me, Vector3(50, 0, 50)) < 0.9)
	gs.breaker_on = false
	m0 = gs.money
	dm.request_use(v)
	await wait(2)
	chk("ohne Strom kein Kaffee", absf(gs.money - m0) < 0.01)
	gs.breaker_on = true
	var w := _add("prop_water", Vector3(6.4, 0, -3.0))
	dm.request_use(w)
	await wait(2)
	chk("Wasser", dm.has_buff(me, "water"))
	for d in gs.decor_items.values():
		if str(d["item_type"]) == "prop_sofa":
			dm.request_rest(str(d["id"]))
	await wait(2)
	chk("Pause auf dem Sofa", dm.has_buff(me, "rest") and dm.staff_speed() > 1.1, dm.staff_speed())
	var t := _add("prop_tool_cart", Vector3(6.0, 0, 1.0))
	_drop_all()
	_crate("kit_ram")
	var n: int = gs.count_repair_kits("ram")
	dm.request_use(t)
	await wait(2)
	chk("Kit im Werkzeugwagen", dm.kit_count(gs.decor_items[t]) == 1 and gs.count_repair_kits("ram") == n)
	dm.request_use(t)
	await wait(2)
	chk("Kit wieder in der Hand", str(gs.get_player_held_crate(me).get("item_type", "")) == "kit_ram" and dm.kit_count(gs.decor_items[t]) == 0)
	_drop_all()
	_crate("web_server")
	dm.request_use(t)
	await wait(2)
	chk("Server gehört nicht in den Wagen", dm.kit_count(gs.decor_items[t]) == 0)
	_drop_all()
	chk("Werkzeugwagen hilft in der Nähe", dm.work_mult(99, Vector3(6, 0, 2)) < 0.9 and dm.work_mult(99, Vector3(16, 0, 2)) == 1.0)
	var h := _add("prop_dehumidifier", Vector3(4.0, 0, 1.5))
	chk("Luftentfeuchter bremst Staub und Lecks", dm.dust_factor(Vector3(5, 0, 1)) < 1.0 and dm.leak_factor() > 1.0)
	gs.decor_items[h]["tank"] = 1.0
	chk("voller Tank schaltet ab", dm.dust_factor(Vector3(5, 0, 1)) == 1.0 and dm.leak_factor() == 1.0)
	dm.request_use(h)
	await wait(2)
	chk("Tank leeren", float(gs.decor_items[h]["tank"]) == 0.0)
	dm._tick_dehumidifiers(600.0)
	chk("Tank füllt sich", float(gs.decor_items[h]["tank"]) > 0.2, gs.decor_items[h]["tank"])
	var l := _add("prop_logo_sign", Vector3(-1.0, 2.0, gs.WALL_FACE_NORTH_Z + 0.062))
	chk("Schild bringt Kunden", dm.growth_bonus() > 0.0)
	for i in 5:
		dm.request_use(l)
		await wait(1)
	chk("Schild aus", bool(gs.decor_items[l].get("off", false)) and dm.growth_bonus() == 0.0)
	dm.request_use(l)
	await wait(2)
	chk("Schild wieder an", dm.growth_bonus() > 0.0)
	_add("prop_parts_cabinet", Vector3(10.0, 0, -3.5))
	gs.bench_screws = 10
	gs.reputation = 50.0
	dm.run_day()
	chk("Tagesbonus: Schrauben und Ruf", gs.bench_screws == 22 and gs.reputation > 51.0, [gs.bench_screws, gs.reputation])
	await wait(40)
	var b0: float = float(dm.get_buffs(me)["coffee"])
	await wait(20)
	chk("Buff läuft ab", float(dm.get_buffs(me)["coffee"]) < b0)
	var hud: Control = main.get("hud")
	hud.visible = true
	hud.call("_refresh_buff_row")
	var cells: Dictionary = hud.get("_buff_cells")
	chk("HUD zeigt Kaffee", (cells["coffee"][0] as Control).visible or bool((main.get("world") if main.get("world") != null else hud.get("_world")).get("local_player").ui_locked), (cells["coffee"][1] as Label).text)


func _bench() -> void:
	print("--- Zweite Werkbank")
	var e := _add("prop_esd_workbench", Vector3(8.5, 0, 0.0))
	await wait(3)
	_drop_all()
	chk("zwei Bänke", gs.bench_exists(gs.MAIN_BENCH) and gs.bench_exists(e))
	_crate("slot_build_box")
	var cid: String = str(gs.get_player_held_crate(me)["id"])
	gs.crates[cid]["build_data"] = {"mainboard_id": "mb_intel_office", "components": {}}
	gs.select_bench(e)
	gs.request_workbench_place()
	await wait(3)
	var st: Dictionary = gs.bench_states.get(e, {})
	var main_st: Dictionary = gs.bench_states.get(gs.MAIN_BENCH, {})
	print("   Bank 2: ", st.get("mode", "-"), "  Bank 1: ", main_st.get("mode", "-"))
	chk("Kiste liegt auf Bank 2, Bank 1 bleibt leer", not st.is_empty() and main_st.is_empty())
	gs.request_workbench_unpack()
	await wait(2)
	gs.request_workbench_enter()
	await wait(2)
	chk("Bank 2 belegt", int((gs.bench_states[e] as Dictionary).get("worker", 0)) == me or str((gs.bench_states[e] as Dictionary).get("mode", "")) == "", gs.bench_states[e].get("worker", 0))
	gs.request_relocate_decor(e, Vector3(8.5, 0, 1.0), 0.0)
	await wait(2)
	var moved: bool = (gs.decor_items[e]["pos"] as Vector3).distance_to(Vector3(8.5, 0, 0.0)) > 0.1
	chk("belegte Bank nicht umsetzbar", not moved or int((gs.bench_states[e] as Dictionary).get("worker", 0)) == 0)
	gs.request_workbench_leave()
	await wait(2)
	gs.select_bench(gs.MAIN_BENCH)
	_drop_all()
	_crate("slot_build_box")
	cid = str(gs.get_player_held_crate(me)["id"])
	gs.crates[cid]["build_data"] = {"mainboard_id": "mb_intel_office", "components": {}}
	gs.request_workbench_place()
	await wait(3)
	chk("gleichzeitig Bank 1", not (gs.bench_states[gs.MAIN_BENCH] as Dictionary).is_empty() and not (gs.bench_states[e] as Dictionary).is_empty())
	gs.select_bench(e)
	_drop_all()
	gs.request_workbench_pickup()
	await wait(3)
	chk("von Bank 2 wegnehmen", (gs.bench_states[e] as Dictionary).is_empty() and not (gs.bench_states[gs.MAIN_BENCH] as Dictionary).is_empty())
	_drop_all()
	gs.select_bench(gs.MAIN_BENCH)
	gs.request_workbench_pickup()
	await wait(2)
	_drop_all()


func _aisle() -> void:
	print("--- Kaltgang")
	_add("prop_cold_aisle_gate", Vector3(14.0, 0, -2.5))
	chk("ein Portal reicht nicht", dm.get_aisles().is_empty())
	_add("prop_cold_aisle_gate", Vector3(14.0, 0, 2.0), PI)
	chk("zwei gegenüber ergeben einen Kaltgang", dm.get_aisles().size() == 1)
	var lp: Node3D = get_nodes_in_group("player_body")[0]
	var keep := lp.position
	var doors := root.find_children("Door_L", "Node3D", true, false)
	await wait(30)
	var closed := (doors[0] as Node3D).position.x
	lp.position = Vector3(14.0, 0.1, -1.8)
	for i in 40:
		lp.position = Vector3(14.0, 0.1, -1.8)
		await wait(1)
	chk("Türen öffnen von selbst", absf((doors[0] as Node3D).position.x - closed) > 0.2, [closed, (doors[0] as Node3D).position.x])
	lp.position = keep
	chk("Rack dazwischen kühler, daneben nicht", dm.aisle_relief(Vector3(15.2, 0, 0)) == 6.0 and dm.aisle_relief(Vector3(17.0, 0, 0)) == 0.0)


func _cams() -> void:
	print("--- Kameras")
	var c := _add("prop_cctv_monitor", Vector3(2.5, 0, 3.6), 0.0)
	await wait(4)
	chk("Kamera sieht die Lieferzone", dm.has_camera(Vector3(0, 0, 6)))
	gs.breaker_on = false
	chk("ohne Strom blind", not dm.has_camera(Vector3(0, 0, 6)))
	gs.breaker_on = true
	var rid: String = gs._alloc_rack_id()
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(0.5, 0.0, 0.0), 0.0)
	gs.racks[rid]["temp"] = 68.0
	dm._tick_cameras()
	chk("Hitzewarnung", int(dm._warned.get(rid, 0)) == 1)
	gs.racks[rid]["temp"] = 80.0
	dm._tick_cameras()
	chk("Rauchwarnung", int(dm._warned.get(rid, 0)) == 2)
	gs.racks.erase(rid)
	var term: Control = main.get("terminal_ui")
	term.call("open_terminal")
	if term.get("_boot_screen") != null:
		term.call("_on_boot_finished")
	await wait(20)
	term.call("_open_app", "cams")
	await wait(20)
	var apps := root.find_children("*", "SubViewport", true, false).filter(func(n): return n.get_parent() is Control and n.get_child_count() == 1 and n.get_child(0) is Camera3D)
	chk("Kamera-App zeigt ein Bild", apps.size() >= 1, apps.size())
	if not apps.is_empty():
		print("   app: ", (apps[0].get_parent() as Control).is_visible_in_tree(), " kraft ", dm.has_power(), " grp ", get_nodes_in_group("cctv_cam").size())
		var cam: Camera3D = apps[0].get_child(0)
		chk("Kamera hängt an der Stele", cam.global_position.distance_to(Vector3(2.5, 2.4, 3.6)) < 0.6, cam.global_position)
	var d2 := _add("prop_cctv_monitor", Vector3(-2.5, 0, 3.9), 0.0)
	await wait(6)
	var labels := term.find_children("*", "Label", true, false).filter(func(x): return (x as Label).text == "2 Kameras" or (x as Label).text == "2 cameras")
	chk("zweite Kamera erscheint sofort", labels.size() == 1)
	gs.decor_items.erase(d2)
	gs._broadcast_decor_items()
	await wait(3)
	term.call("close_terminal")
	await wait(3)


func _thief() -> void:
	print("--- Diebe")
	gs.crates.clear()
	var c1 := _crate("web_server", false)
	gs.crates[c1]["pos"] = Vector3(1.0, 0, 7.0)
	gs.garage_door_open = false
	var c2 := _crate("ups", false)
	gs.crates[c2]["pos"] = Vector3(0.0, 0, 3.0)
	chk("geschlossenes Tor schützt innen", dm.thief_targets() == [c1], dm.thief_targets())
	gs.garage_door_open = true
	chk("offenes Tor nicht", dm.thief_targets().size() == 2)
	gs.money = 50000.0
	var ins0: float = gs.money
	dm.start_thief(c1)
	chk("Dieb kommt", str(dm.thief.get("phase", "")) == "in")
	dm.thief["t"] = 999.0
	dm._run_thief()
	chk("Dieb greift zu", str(dm.thief.get("phase", "")) == "grab")
	dm.thief["t"] = 999.0
	dm._run_thief()
	chk("Kiste weg", not gs.crates.has(c1) and str(dm.thief.get("phase", "")) == "out")
	dm.catch_thief(me)
	var back := 0
	for c in gs.crates.values():
		if str(c["item_type"]) == "web_server":
			back += 1
	chk("gefangen: Kiste liegt wieder da", back == 1 and str(dm.thief.get("phase", "")) == "flee")
	dm.thief["t"] = 999.0
	dm._run_thief()
	chk("Dieb ist weg", dm.thief.is_empty())
	for c in gs.crates.keys():
		if str(gs.crates[c]["item_type"]) == "web_server":
			c1 = c
	dm.start_thief(c1)
	for i in 3:
		dm.thief["t"] = 999.0
		dm._run_thief()
	chk("entkommen: Ware gestohlen", not gs.crates.has(c1) and dm.thief.is_empty())
	gs.time_of_day = 0.5
	dm._night_at = -1.0
	dm._tick_thief(1.0)
	chk("tagsüber keine Diebe", dm.thief.is_empty())
	gs.crates.clear()
	chk("Geld", gs.money >= ins0, gs.money - ins0)


func _save() -> void:
	print("--- Speichern")
	gs.crates.clear()
	var sh := _add("prop_shelf_small", Vector3(16.0, 0, -3.0))
	gs.decor_items[sh]["stored_items"] = [null, {"item_type": "kit_psu", "pack_count": 1}]
	SS.units(gs.decor_items[sh])
	var n: int = gs.decor_items.size()
	var data: Dictionary = gs.export_save_data()

	gs.load_from_save_data(data.duplicate(true), "paketc", "PaketC")
	await wait(6)
	chk("Einrichtung bleibt", gs.decor_items.size() == n, [n, gs.decor_items.size()])
	chk("Regalinhalt bleibt", SS.owner_of(gs.decor_items[sh], 1) == 1)
	var starts := 0
	for d in gs.decor_items.values():
		if str(d["id"]) == "decor_start":
			starts += 1
	chk("kein zweites Start-Regal", starts == 1)
	# Alter Spielstand: festes Regal und 4er-Regal
	var old: Dictionary = data.duplicate(true)
	old.erase("start_shelf_done")
	old.erase("schema") # Spielstände von vor v3.4 haben noch kein Schema
	var di: Dictionary = {}
	di["decor_9"] = {"id": "decor_9", "item_type": "prop_storage_shelf", "pos": Vector3(8, 0, 0), "rot_y": 0.0, "stored_items": [{"item_type": "web_server"}, null, {"item_type": "kit_ram"}, null]}
	old["decor_items"] = di
	old["storage_shelf_slots"] = {"shelf_0:0": {"item_type": "kit_cpu", "id": "c1", "pack_count": 1}, "shelf_0:5": {"item_type": "rack", "id": "c2", "pack_count": 1}, "shelf_0:7": {"item_type": "web_server", "id": "c3", "pack_count": 1}}
	gs.load_from_save_data(old, "paketc", "PaketC")
	await wait(6)
	chk("altes 4er-Regal umgestellt", SS.owner_of(gs.decor_items["decor_9"], 1) == 1 and SS.owner_of(gs.decor_items["decor_9"], 11) == 11, gs.decor_items["decor_9"]["stored_items"].size())
	chk("festes Regal wird beweglich", gs.decor_items.has("decor_start"))
	var got: Array = []
	for e in gs.decor_items["decor_start"]["stored_items"]:
		if e is Dictionary:
			got.append(str(e["item_type"]))
	chk("Inhalt übernommen", got.has("kit_cpu") and got.has("web_server"), got)
	var racks_floor := 0
	for c in gs.crates.values():
		if str(c["item_type"]) == "rack":
			racks_floor += 1
	chk("Rack steht davor", racks_floor == 1, racks_floor)
	var shelves := 0
	for s in root.find_children("*", "Node3D", true, false):
		if s.get_script() != null and str((s.get_script() as Script).resource_path).ends_with("shelf_prop.gd") and not s.is_queued_for_deletion():
			shelves += 1
	chk("beide Regale in der Welt", shelves == 2, shelves)


func _run_van(max_s: float) -> void:
	var t := 0.0
	while t < max_s and gs.van_phase != "idle":
		gs._update_delivery_van(0.25)
		t += 0.25


func _delivery() -> void:
	print("--- Lieferung")
	var DP: GDScript = load("res://scripts/data/delivery_plan.gd")
	gs.crates.clear()
	gs.carts.clear()
	gs.halle_nord_owned = true
	gs.delivery_target_site = "garage"
	for site in ["garage", "halle_nord"]:
		for tier in [1, 2, 3]:
			var last: Vector3 = DP.vehicle_pose(site, tier, "arriving", 0.0)["pos"]
			var last_yaw := float(DP.vehicle_pose(site, tier, "arriving", 0.0)["yaw"])
			var jump := 0.0
			var turn := 0.0
			var t := 0.0
			while t < DP.ARRIVE_TIME:
				t += 1.0 / 30.0
				var p: Dictionary = DP.vehicle_pose(site, tier, "arriving", t)
				jump = maxf(jump, (p["pos"] as Vector3).distance_to(last))
				turn = maxf(turn, absf(angle_difference(last_yaw, float(p["yaw"]))))
				last = p["pos"]
				last_yaw = float(p["yaw"])
			var parked: Dictionary = DP.vehicle_pose(site, tier, "unloading", 0.0)
			var out0: Dictionary = DP.vehicle_pose(site, tier, "departing", 0.0)
			chk("%s Stufe %d fährt ohne Sprünge rückwärts ans Tor" % [site, tier], jump < 0.75 and turn < 0.05 and last.distance_to(parked["pos"]) < 0.02 and (out0["pos"] as Vector3).distance_to(parked["pos"]) < 0.02 and absf(float(parked["yaw"])) < 0.01, [snappedf(jump, 0.01), snappedf(turn, 0.001)])
	# Plätze: nichts überlappt, nichts liegt unter dem Fahrzeug
	var cargo: Array = []
	for i in 5:
		cargo.append("rack")
	for t2 in ["cool_k90", "ups_cabinet", "web_server", "web_server", "gpu_server", "net_switch", "ups", "bulk:kit_ram:6", "bulk:kit_cpu:6", "kit_psu", "kit_gpu", "kit_storage", "prop_power_strip", "cooler", "prop_sofa", "cart", "parts_parcel"]:
		cargo.append(t2)
	for tier in [1, 2, 3]:
		var plan: Dictionary = DP.build("garage", tier, cargo)
		var bad_o: Array = []
		var items: Array = plan["items"]
		for a in items.size():
			var pa: Vector3 = items[a]["pos"]
			if str(items[a]["cls"]) == "parcel":
				continue
			if pa.z > DP.rear_z(tier) and absf(pa.x) < 1.5 or absf(pa.x) > 3.6 or pa.z < 4.9 or pa.z > 9.3:
				bad_o.append(["außerhalb", items[a]["it"], pa])
			for b in range(a + 1, items.size()):
				var pb: Vector3 = items[b]["pos"]
				if str(items[b]["cls"]) == "parcel" or (str(items[a]["stk"]) != "" and str(items[a]["stk"]) == str(items[b]["stk"])):
					continue
				var da: Vector3 = items[a]["d"]
				var db: Vector3 = items[b]["d"]
				if absf(pa.x - pb.x) < (da.x + db.x) * 0.5 - 0.06 and absf(pa.z - pb.z) < (da.z + db.z) * 0.5 - 0.06:
					bad_o.append([items[a]["it"], pa, items[b]["it"], pb])
		chk("Stufe %d: jede Ware hat ihren eigenen Platz" % tier, bad_o.is_empty(), bad_o)
		chk("Stufe %d: jedes Paket wird genau einmal abgestellt" % tier, (plan["drops"] as Array).size() == cargo.size())
		var overlap := 0
		for j in plan["jobs"]:
			for k in plan["jobs"]:
				if j == k or int(j["w"]) != int(k["w"]):
					continue
				var e0 := float(j["t"]) + float(j["load"]) + float(j["go"]) + float(j["drop"]) + float(j["back"])
				if float(k["t"]) >= float(j["t"]) and float(k["t"]) < e0 - 0.01:
					overlap += 1
		chk("Stufe %d: niemand macht zwei Dinge gleichzeitig" % tier, overlap == 0, snappedf(plan["end"], 0.1))
	# Kompletter Ablauf auf dem Host
	gs.money = 50000.0
	gs.van_phase = "idle"
	gs.van_cargo = ["parts_parcel", "rack", "web_server", "bulk:kit_ram:4", "kit_cpu", "kit_psu"]
	gs._van_parcel_parts = ["acc:fuse"]
	var blocker := _crate("ups", false)
	gs.crates[blocker]["pos"] = Vector3(0.0, 0.0, 8.7)
	var occ := _crate("web_server", false)
	gs.crates[occ]["pos"] = Vector3(1.52, 0.0, 5.5)
	gs._start_delivery_van()
	chk("Kiste im Weg rückt zur Seite", (gs.crates[blocker]["pos"] as Vector3).z < 7.8 or absf((gs.crates[blocker]["pos"] as Vector3).x) > 1.7, gs.crates[blocker]["pos"])
	_run_van(gs.VAN_ARRIVE_DURATION + 0.5)
	chk("lädt ab", gs.van_phase == "unloading" and gs.van_trip_phase == "work" and not gs.van_plan.is_empty())
	var fuses: int = gs.fuse_stock
	while gs.van_trip_done < 3:
		gs._update_delivery_van(0.25)
	var save: Dictionary = gs.export_save_data()
	chk("Speichern mittendrin: Rest bleibt unterwegs", (save["pending_delivery_items"] as Array).size() == 3, save["pending_delivery_items"])
	var snap: Dictionary = gs.build_snapshot()
	chk("Mitspieler bekommt den Plan", not (snap.get("van_plan", {}) as Dictionary).is_empty() and str(snap.get("van_trip_phase", "")) == "work")
	while gs.van_trip_phase == "work":
		gs._update_delivery_van(0.25)
	chk("alles abgestellt", gs.van_cargo.is_empty() and gs.crates.size() == 7, gs.crates.size())
	chk("Sammelpaket eingelagert", gs.fuse_stock > 0, [fuses, gs.fuse_stock])
	var near_occ := 0
	for c in gs.crates.keys():
		if c != occ and (gs.crates[c]["pos"] as Vector3).distance_to(gs.crates[occ]["pos"]) < 0.45:
			near_occ += 1
	chk("belegter Platz wird ausgelassen", near_occ == 0)
	var pal := 0
	for c in gs.crates.values():
		if bool(c.get("pal", false)) and absf((c["pos"] as Vector3).y - 0.144) < 0.001:
			pal += 1
	chk("Rack steht auf einer Palette", pal == 1)
	chk("Fahrer wartet auf die Unterschrift", gs.van_trip_phase == "sign")
	var rep0: float = gs.reputation
	var m0: float = gs.money
	gs.request_sign_delivery()
	await wait(2)
	chk("Unterschrift bringt Ruf und Trinkgeld", gs.reputation > rep0 and gs.money > m0 and gs.van_trip_phase == "enter")
	gs.request_sign_delivery()
	await wait(1)
	chk("nur einmal", absf(gs.money - m0 - gs.VAN_SIGN_TIP) < 0.01)
	_run_van(40.0)
	chk("fährt wieder weg", gs.van_phase == "idle" and gs.van_plan.is_empty())
	# Stapel rutschen nach
	gs.crates.clear()
	var ids: Array = []
	for i in 10:
		ids.append(gs._spawn_crate_internal("kit_ram"))
	gs._broadcast_crates()
	var stacked := ""
	var below := ""
	for id in ids:
		for id2 in ids:
			if id != id2 and str(gs.crates[id]["stk"]) == str(gs.crates[id2]["stk"]) and (gs.crates[id2]["pos"] as Vector3).y > (gs.crates[id]["pos"] as Vector3).y + 0.05:
				below = id
				stacked = id2
	chk("Kits werden gestapelt", stacked != "")
	if stacked != "":
		var y0 := (gs.crates[stacked]["pos"] as Vector3).y
		gs.crates.erase(below)
		gs._broadcast_crates()
		chk("oberer Koffer rutscht nach", (gs.crates[stacked]["pos"] as Vector3).y < y0 - 0.1, [y0, (gs.crates[stacked]["pos"] as Vector3).y])
	# Niemand unterschreibt
	gs.crates.clear()
	gs.van_cargo = ["kit_cpu"]
	gs._start_delivery_van()
	_run_van(gs.VAN_ARRIVE_DURATION + 0.5)
	while gs.van_trip_phase == "work":
		gs._update_delivery_van(0.25)
	m0 = gs.money
	_run_van(gs.VAN_SIGN_TIME + 1.0)
	chk("ohne Unterschrift kein Trinkgeld", gs.van_trip_phase == "enter" and absf(gs.money - m0) < 0.01, gs.van_trip_phase)
	_run_van(40.0)
	# Halle Nord
	gs.crates.clear()
	gs.delivery_target_site = "halle_nord"
	gs.van_cargo = ["web_server", "kit_cpu", "cart"]
	gs._start_delivery_van()
	gs.delivery_target_site = "garage"
	_run_van(160.0)
	var nord := 0
	for c in gs.crates.values():
		if (c["pos"] as Vector3).z < -300.0:
			nord += 1
	var ncart := 0
	for c in gs.carts.values():
		if (c["pos"] as Vector3).z < -300.0:
			ncart += 1
	chk("Halle Nord wird wirklich angefahren", nord == 2 and ncart == 1 and gs.van_phase == "idle", [nord, ncart, gs.van_phase])
	# Bestellung während des Abladens kommt mit der nächsten Tour
	gs.crates.clear()
	gs.carts.clear()
	gs.halle_nord_owned = false
	gs.van_cargo = ["kit_cpu", "kit_ram"]
	gs._start_delivery_van()
	_run_van(gs.VAN_ARRIVE_DURATION + 0.5)
	gs.request_order_cart([{"kind": "item", "id": "ups", "qty": 1}], false) if gs.has_method("request_order_cart") else gs.request_buy_item("ups")
	await wait(3)
	chk("Bestellung beim Abladen wartet auf die nächste Tour", gs.pending_delivery_items.has("ups") and gs.van_cargo.size() == 2, [gs.pending_delivery_items, gs.van_cargo])
	_run_van(160.0)
	gs.pending_delivery_items.clear()
	gs.van_phase = "idle"
	gs._reset_van_trip()
	gs.van_cargo.clear()
	gs.crates.clear()
	gs._broadcast_crates()
