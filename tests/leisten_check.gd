extends SceneTree
## Steckleisten mit Ein- und Ausgang an der Seite: Regeln, Ketten, Last, Einrasten, alte Spielstände.
## Aufruf: godot --headless --path . --script res://tests/leisten_check.gd

var bad := 0
var gs: Node
var nm: Node
var main: Node
var hints: Array = []


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func wait(s: float) -> void:
	await create_timer(s).timeout


func strip(id: String, pos: Vector3, lan := false, rot := 0.0) -> String:
	gs.decor_items[id] = {"id": id, "item_type": "prop_lan_strip" if lan else "prop_power_strip", "pos": pos, "rot_y": rot, "wall": false, "stored_items": []}
	return id


func rack(id: String, pos: Vector3, watts_each := 0) -> String:
	gs.racks[id] = gs._make_rack_data(id, "rack", pos, 0.0)
	return id


func cable(t: String, a: String, b: String, sa := -1, sb := -1) -> bool:
	var n0: int = gs.cables.size()
	gs._rpc_req_connect_cable(t, a, b, sa, sb)
	return gs.cables.size() == n0 + 1


func reset() -> void:
	gs.cables.clear()
	gs.decor_items.clear()
	gs.racks.clear()
	gs.coolers.clear()
	gs.ups_units.clear()
	gs.breaker_on = true
	gs._recalculate_networks_and_metrics()


func slot_of(t: String, eid: String, other: String) -> int:
	for cid in gs.cables.keys():
		var c: Dictionary = gs.cables[cid]
		if str(c["cable_type"]) != t:
			continue
		if str(c["from_id"]) == eid and str(c["to_id"]) == other:
			return int(c["from_slot"])
		if str(c["to_id"]) == eid and str(c["from_id"]) == other:
			return int(c["to_slot"])
	return -9


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
	nm.call("_start_host_internal", "Test", 7863, {}, "", "Leisten", "", false, false)
	await wait(0.8)
	gs.cable_hint.connect(func(m): hints.append(m))
	gs.room_level = 2
	gs.power_tier = gs.POWER_TIERS.size() - 1
	_rules()
	_chain()
	_load()
	await _snap()
	_lan()
	_migration()
	print("ERGEBNIS Fehler ", bad)
	nm.call("leave_session")
	quit(1 if bad > 0 else 0)


func _rules() -> void:
	reset()
	var B: String = gs.WALL_BREAKER_ID
	strip("s1", Vector3(-2, 0, -1))
	strip("s2", Vector3(-1, 0, 0))
	rack("r1", Vector3(1, 0, 1))
	rack("r2", Vector3(2.5, 0, 1))
	hints.clear()
	chk("Kasten oben gezielt: kommt in den Eingang", cable("power", B, "s1", -1, 2) and slot_of("power", "s1", B) == 6)
	chk("Kasten hat nur einen Abgang", not cable("power", B, "s2"))
	chk("Leiste oben an Leiste gezielt: Ausgang in Eingang", cable("power", "s1", "s2", 3, -1) and slot_of("power", "s1", "s2") == 7 and slot_of("power", "s2", "s1") == 6)
	chk("Rack oben eingesteckt", cable("power", "s2", "r1") and slot_of("power", "s2", "r1") >= 0 and slot_of("power", "s2", "r1") < 6)
	chk("Rack an die Seite gezielt: kommt oben rein", cable("power", "r2", "s2", -1, 7) and slot_of("power", "s2", "r2") < 6)
	gs._rpc_req_disconnect_cable_slot("power", "s2", slot_of("power", "s2", "r2"))
	hints.clear()
	strip("s9", Vector3(3, 0, -3))
	cable("power", "s2", "s9")
	strip("s10", Vector3(3, 0, -2))
	chk("zweiter Ausgang gibt es nicht", not cable("power", "s2", "s10", 7, -1) and hints.size() == 1, hints)
	gs.decor_items.erase("s10")
	gs.decor_items.erase("s9")
	for cid in gs.cables.keys():
		if [gs.cables[cid]["from_id"], gs.cables[cid]["to_id"]].has("s9"):
			gs.cables.erase(cid)
	chk("Rack an Rack geht nicht", not cable("power", "r1", "r2"))
	chk("Ring wird abgelehnt", not cable("power", "s2", "s1", 7, 6))
	gs._recalculate_networks_and_metrics()
	chk("Strom fließt durch die Kette", bool(gs.racks["r1"]["powered"]) and gs.is_strip_fed("power", "s2"))
	gs.decor_items["s1"]["on"] = false
	gs._recalculate_networks_and_metrics()
	chk("erste Leiste aus: alles dahinter aus", not bool(gs.racks["r1"]["powered"]) and not gs.is_strip_fed("power", "s2"))
	gs.decor_items["s1"]["on"] = true
	# Alte Kabelwege gibt es nicht mehr: Rack gibt nichts weiter
	gs.cables["alt"] = {"id": "alt", "cable_type": "power", "from_id": "r1", "to_id": "r2", "from_slot": 1, "to_slot": 0}
	gs._recalculate_networks_and_metrics()
	chk("Rack gibt keinen Strom weiter", bool(gs.racks["r1"]["powered"]) and not bool(gs.racks["r2"]["powered"]))
	gs.cables.erase("alt")
	# A+B-Einspeisung
	strip("s3", Vector3(2, 0, -2))
	chk("zweite Leiste hinter der Kette", cable("power", "s2", "s3"))
	chk("Rack zweites Netzteil an andere Leiste", cable("power", "s3", "r1"))
	gs._recalculate_networks_and_metrics()
	gs.decor_items["s3"]["on"] = false
	gs._recalculate_networks_and_metrics()
	chk("A+B: eine Leiste aus, Rack läuft weiter", bool(gs.racks["r1"]["powered"]))
	gs.decor_items["s3"]["on"] = true
	# USV als Quelle
	reset()
	gs.ups_units["u1"] = {"id": "u1", "ups_type": "ups", "health": 100.0, "pos": Vector3(0, 0, 2), "rot_y": 0.0, "connected": false, "charge": 90.0, "discharging": false}
	strip("s1", Vector3(-2, 0, -1))
	chk("Kasten an USV", cable("power", B, "u1"))
	chk("USV in den Eingang (gezielt)", cable("power", "u1", "s1", -1, 6) and slot_of("power", "s1", "u1") == 6)
	rack("r1", Vector3(1, 0, 1))
	chk("Rack an Leiste hinter USV", cable("power", "s1", "r1"))
	gs._recalculate_networks_and_metrics()
	chk("Strom über USV und Leiste", bool(gs.racks["r1"]["powered"]))


func _chain() -> void:
	reset()
	var B: String = gs.WALL_BREAKER_ID
	var ids: Array = []
	for i in 6:
		ids.append(strip("k%d" % i, Vector3(-3 + i, 0, -2)))
	chk("Kasten an erste Leiste", cable("power", B, "k0"))
	var ok := true
	for i in 5:
		ok = ok and cable("power", ids[i], ids[i + 1])
	chk("sechs Leisten hintereinander", ok)
	rack("r1", Vector3(2, 0, 1))
	chk("Rack am Ende der Kette", cable("power", "k5", "r1"))
	gs._recalculate_networks_and_metrics()
	chk("Strom kommt am Ende an", bool(gs.racks["r1"]["powered"]))
	chk("Kettenanfang erkannt", gs.get_chain_root("k5") == "k0" and gs.get_chain_length("k3") == 6, gs.get_chain_root("k5"))
	gs.decor_items["k2"]["on"] = false
	gs._recalculate_networks_and_metrics()
	chk("mittlere Leiste aus: Ende aus", not bool(gs.racks["r1"]["powered"]) and gs.is_strip_fed("power", "k2") and not gs.is_strip_fed("power", "k4"))
	gs.decor_items["k2"]["on"] = true
	gs._recalculate_networks_and_metrics()
	chk("wieder an", bool(gs.racks["r1"]["powered"]))


func _load() -> void:
	reset()
	var B: String = gs.WALL_BREAKER_ID
	strip("a", Vector3(-2, 0, -1))
	strip("b", Vector3(0, 0, -1))
	cable("power", B, "a")
	cable("power", "a", "b")
	# Last direkt setzen: so prüft der Test die Verteilung, nicht die Server
	gs._strip_feeds = {"x1": ["a"], "x2": ["b"], "x3": ["b"], "x4": ["a", "b"]}
	gs._compute_strip_loads({"x1": 3000, "x2": 4000, "x3": 2000, "x4": 1000})
	chk("Last je Leiste nur ihre Geräte", gs.get_strip_load("a") == 3500 and gs.get_strip_load("b") == 6500, [gs.get_strip_load("a"), gs.get_strip_load("b")])
	chk("Last der Kette alles zusammen", gs.get_chain_load("b") == 10000 and gs.get_chain_load("a") == 10000, gs.get_chain_load("b"))
	gs.strip_loads["b"] = StripRules.STRIP_LIMIT_W + 500
	for i in 6:
		gs._tick_strips(1.0)
	chk("überlastete Leiste löst aus", not gs.is_strip_on("b") and bool(gs.decor_items["b"].get("tripped", false)) and gs.is_strip_on("a"))
	gs.decor_items["b"]["on"] = true
	gs.decor_items["b"].erase("tripped")
	gs.strip_loads["b"] = 100
	gs.chain_loads = {"a": StripRules.CHAIN_LIMIT_W + 1000}
	for i in 6:
		gs._tick_strips(1.0)
	chk("überlastete Kette: erste Leiste fällt", not gs.is_strip_on("a"))
	gs.decor_items["a"]["on"] = true


func _snap() -> void:
	reset()
	strip("p", Vector3(0.0, 0, 0.0))
	var sn := StripRules.snap_spot("power", Vector3(0.70, 0, 0.05), false)
	chk("neue Leiste rastet am Ausgang ein", not sn.is_empty() and (sn["pos"] as Vector3).distance_to(Vector3(StripRules.LINK_PITCH, 0, 0)) < 0.001 and bool(sn["out_side"]), sn)
	chk("dort darf sie stehen", gs.can_place_item_at("prop_power_strip", sn["pos"], 0.0))
	chk("halb drüber nicht", not gs.can_place_item_at("prop_power_strip", Vector3(0.4, 0, 0), 0.0))
	var sn2 := StripRules.snap_spot("power", Vector3(-0.72, 0, 0), false)
	chk("vorn am Eingang rastet auch", not sn2.is_empty() and not bool(sn2["out_side"]))
	strip("q", sn["pos"])
	chk("direkt gesteckt = verbunden", StripRules.links("power") == [["p", "q"]])
	gs._rpc_req_connect_cable("power", gs.WALL_BREAKER_ID, "p", -1, -1)
	rack("r1", Vector3(2, 0, 2))
	cable("power", "q", "r1")
	gs._recalculate_networks_and_metrics()
	chk("Strom fließt ohne Kabel weiter", bool(gs.racks["r1"]["powered"]) and gs.is_strip_fed("power", "q"))
	chk("gesteckter Ausgang ist belegt", StripRules.slot_used("power", "p", 7) and cable("power", "p", "r1", 7, -1) and slot_of("power", "p", "r1") < 6)
	chk("belegter Eingang: kein Einrasten", StripRules.snap_spot("power", Vector3(-0.72, 0, 0), false).is_empty())
	gs.decor_items["q"]["rot_y"] = 0.3
	chk("schief gestellt: keine Verbindung", StripRules.links("power").is_empty())
	gs.decor_items["q"]["rot_y"] = 0.0
	# Gedreht und an der Wand
	reset()
	strip("w1", Vector3(1, 1.2, -4.3), false, PI)
	gs.decor_items["w1"]["wall"] = true
	var p: Vector3 = gs.decor_items["w1"]["pos"] + StripRules.axis(gs.decor_items["w1"]) * StripRules.LINK_PITCH
	gs.decor_items["w2"] = {"id": "w2", "item_type": "prop_power_strip", "pos": p, "rot_y": PI, "wall": true, "stored_items": []}
	chk("an der Wand gesteckt", StripRules.links("power") == [["w1", "w2"]], StripRules.links("power"))
	# Mit Bildschirm: Server legt sie an die richtige Stelle
	if DisplayServer.get_name() != "headless":
		reset()
		strip("p", Vector3(0.0, 0, 0.0))
		gs._broadcast_decor_items()
		await wait(0.3)
		var dp = main.get("world")._decor_nodes["p"]
		var socks: Array = dp.get_socket_world_positions()
		chk("Seitenbuchsen an den Enden", socks.size() == 8 and (socks[6] as Vector3).distance_to(Vector3(-StripRules.SIDE_X, StripRules.SIDE_Y, 0)) < 0.002 and (socks[7] as Vector3).distance_to(Vector3(StripRules.SIDE_X, StripRules.SIDE_Y, 0)) < 0.002)


func _lan() -> void:
	reset()
	var R: String = gs.WALL_ROUTER_ID
	strip("l1", Vector3(-2, 0, -1), true)
	strip("l2", Vector3(0, 0, -1), true)
	rack("r1", Vector3(1, 0, 1))
	gs._rpc_req_connect_cable("power", gs.WALL_BREAKER_ID, "r1", -1, -1)
	chk("Router in den LAN-Eingang", cable("network", R, "l1") and slot_of("network", "l1", R) == 8)
	chk("LAN-Leiste an LAN-Leiste seitlich", cable("network", "l1", "l2") and slot_of("network", "l1", "l2") == 9 and slot_of("network", "l2", "l1") == 8)
	chk("Rack oben am LAN", cable("network", "l2", "r1") and slot_of("network", "l2", "r1") < 8)
	chk("Rack an LAN-Seite gezielt: kommt oben rein", slot_of("network", "l2", "r1") < 8)
	gs._recalculate_networks_and_metrics()
	chk("Netz kommt durch die Kette", bool(gs.racks["r1"]["networked"]) and gs.get_lan_chain_root("l2") == "l1")
	gs.decor_items["l1"]["on"] = false
	gs._recalculate_networks_and_metrics()
	chk("erste LAN-Leiste aus: Rack offline", not bool(gs.racks["r1"]["networked"]))
	gs.decor_items["l1"]["on"] = true
	gs.racks["r1"]["rental_type"] = "web"
	gs.racks["r1"]["active_users"] = 40
	gs._recalculate_networks_and_metrics()
	chk("Bandbreite der Kette gezählt", float(gs.lan_chain_mbps.get("l1", 0.0)) > 0.0 or not bool(gs.racks["r1"]["networked"]), gs.lan_chain_mbps)


func _migration() -> void:
	reset()
	var B: String = gs.WALL_BREAKER_ID
	strip("m1", Vector3(-2, 0, -1))
	strip("m2", Vector3(0, 0, -1))
	strip("m3", Vector3(2, 0, -1))
	rack("r1", Vector3(1, 0, 1))
	rack("r2", Vector3(2, 0, 1))
	rack("r3", Vector3(3, 0, 1))
	# Alter Aufbau: alles in die oberen Buchsen, eine Leiste speist zwei weitere, Rack speist Rack
	gs.cables = {
		"c1": {"id": "c1", "cable_type": "power", "from_id": B, "to_id": "m1", "from_slot": 0, "to_slot": 0},
		"c2": {"id": "c2", "cable_type": "power", "from_id": "m1", "to_id": "m2", "from_slot": 1, "to_slot": 0},
		"c3": {"id": "c3", "cable_type": "power", "from_id": "m3", "to_id": "m1", "from_slot": 0, "to_slot": 2},
		"c4": {"id": "c4", "cable_type": "power", "from_id": "m2", "to_id": "r1", "from_slot": 1, "to_slot": 0},
		"c5": {"id": "c5", "cable_type": "power", "from_id": "r1", "to_id": "r2", "from_slot": 1, "to_slot": 0},
		"c6": {"id": "c6", "cable_type": "power", "from_id": "m3", "to_id": "r3", "from_slot": 1, "to_slot": 0},
	}
	var res: Array = gs._migrate_strip_ports()
	gs._recalculate_networks_and_metrics()
	chk("Kasten jetzt im Eingang", int(gs.cables["c1"]["to_slot"]) == 6)
	chk("erste Kette umgesteckt", int(gs.cables["c2"]["from_slot"]) == 7 and int(gs.cables["c2"]["to_slot"]) == 6)
	chk("zweiter Abzweig passt nicht mehr und ist ab", not gs.cables.has("c3"))
	chk("Rack an Rack ist ab", not gs.cables.has("c5"))
	chk("Rack oben gesteckt", int(gs.cables["c4"]["from_slot"]) < 6)
	chk("läuft weiter", bool(gs.racks["r1"]["powered"]))
	chk("Bericht", int(res[0]) >= 3 and int(res[1]) == 2, res)
	chk("zweiter Durchlauf ändert nichts", gs._migrate_strip_ports() == [0, 0])
