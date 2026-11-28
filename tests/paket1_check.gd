extends SceneTree
## Prüft das Roadmap-Paket 1: Teleport, Buchsen, Umsetzen, Feuerlöscher, Einschub-Strom, Stromkasten,
## Kühlgeräte, Firmenstufen, Admin-Menü und Markennamen.
## Aufruf: godot --headless --path . --script res://tests/paket1_check.gd

var bad := 0
var gs: Node
var nm: Node
var am: Node
var sm: Node
var main: Node
var world: Node


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	nm = root.get_node("NetworkManager")
	am = root.get_node("AdminManager")
	sm = root.get_node("SaveManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	nm.call("_start_host_internal", "Test", 7811, {}, "", "Paket", "", false, false)
	await wait(20)
	world = main.get_node("World")
	gs.money = 500000.0
	await _teleport()
	await _sockets()
	await _decor()
	await _extinguisher()
	await _slot_power()
	await _breaker()
	await _coolers()
	_levels()
	await _admin()
	_brands()
	await _save()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


func _shape_state() -> Array:
	var on := 0
	var off := 0
	for n in world.get_node("Garage").find_child("HalleNordSite", true, false).find_children("*", "CollisionShape3D", true, false):
		if (n as CollisionShape3D).disabled:
			off += 1
		else:
			on += 1
	return [on, off]


## Boden von Halle Nord trägt (Strahl von oben trifft auf Höhe 0).
func _floor_on() -> bool:
	var o: Vector3 = gs.HALLE_NORD_ORIGIN
	var q := PhysicsRayQueryParameters3D.create(o + Vector3(-6.0, 3.0, 0.0), o + Vector3(-6.0, -2.0, 0.0))
	q.collision_mask = 1
	var hit: Dictionary = (world.local_player as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and absf((hit["position"] as Vector3).y) < 0.05


func _teleport() -> void:
	print("--- Teleport")
	var lp: Node3D = world.local_player
	chk("Halle Nord anfangs ohne Kollision", _shape_state()[0] == 0, _shape_state())
	gs.company_level = 3
	gs.money = maxf(gs.money, 20000.0)
	gs.request_buy_halle_nord()
	await wait(3)
	# Seit v3.8 baut erst ein Bautrupp die Halle
	gs._tick_constructions(999.0)
	await wait(3)
	# Gesperrte Abschnitte (Verteiler, Kaltgang) und nicht gebaute Ausbauten bleiben bewusst ohne Kollision.
	chk("Host kauft: Boden aktiv", gs.halle_nord_owned and _floor_on() and _shape_state()[0] > 0, _shape_state())
	lp.teleport_between_sites()
	for i in 90:
		await physics_frame
	chk("Host steht in Halle Nord", lp.position.z < -300.0 and lp.position.y > -0.5, lp.position)
	lp.position.y = -9.0
	await wait(3)
	for i in 30:
		await physics_frame
	chk("Sicherheitsnetz fängt auf", lp.position.y > -0.5 and lp.position.z < -300.0, lp.position)
	lp.teleport_between_sites()
	for i in 60:
		await physics_frame
	chk("zurück in der Garage", lp.position.z > -10.0 and lp.position.y > -0.5, lp.position)
	var data: Dictionary = gs.export_save_data()
	gs.clear_local_state()
	await wait(2)
	gs.load_from_save_data(data, "p1", "p1")
	gs.is_active = true
	await wait(3)
	chk("nach dem Laden Boden aktiv", gs.halle_nord_owned and _floor_on(), _shape_state())


func _rack(pos: Vector3) -> String:
	var rid: String = gs._alloc_rack_id()
	gs.racks[rid] = gs._make_rack_data(rid, "rack", pos, 0.0)
	gs.racks_changed.emit()
	return rid


func _decor_add(type: String, pos: Vector3) -> String:
	var did: String = gs._alloc_id("decor")
	gs.decor_items[did] = {"id": did, "item_type": type, "pos": pos, "rot_y": 0.0, "stored_items": [null, null, null, null] if type == "prop_storage_shelf" else []}
	gs._broadcast_decor_items()
	return did


func _cable_between(t: String, a: String, b: String) -> Dictionary:
	for cid in gs.cables:
		var c: Dictionary = gs.cables[cid]
		if c["cable_type"] == t and [c["from_id"], c["to_id"]].has(a) and [c["from_id"], c["to_id"]].has(b):
			return c
	return {}


func _sockets() -> void:
	print("--- Buchsen")
	var strip := _decor_add("prop_power_strip", Vector3(2.0, 0.0, 2.0))
	var lan := _decor_add("prop_lan_strip", Vector3(3.0, 0.0, 2.0))
	var r1 := _rack(Vector3(0.0, 0.0, 0.0))
	await wait(3)
	gs.request_connect_cable("power", strip, r1, 4, 0)
	gs.request_connect_cable("network", lan, r1, 6, 0)
	await wait(3)
	var pc := _cable_between("power", strip, r1)
	chk("Strom sitzt in Dose 5", int(pc.get("from_slot", -1)) == 4, pc)
	var res: Callable = world._make_cable_socket_resolver()
	var want: Vector3 = world._decor_nodes[strip].get_socket_world_positions()[4]
	chk("Stecker wird an Dose 5 gezeichnet", (res.call(str(pc["id"]), "power", strip) as Vector3).is_equal_approx(want))
	var nc := _cable_between("network", lan, r1)
	var want_n: Vector3 = world._decor_nodes[lan].get_socket_world_positions()[6]
	chk("LAN-Stecker an Port 7", (res.call(str(nc["id"]), "network", lan) as Vector3).is_equal_approx(want_n))
	var socks: Array = world.get_socket_positions("network", r1)
	chk("Rack-LAN sitzt in einer echten Buchse (nicht dazwischen)", absf(world._rack_nodes[r1].to_local(socks[0]).x - 0.208) < 0.002, world._rack_nodes[r1].to_local(socks[0]))
	chk("zwei Rack-Dosen getrennt", (world.get_socket_positions("power", r1) as Array).size() == 2)
	for ep in [["power", gs.HALL_NORD_BREAKER_ID, 16], ["network", gs.HALL_NORD_ROUTER_ID, 16], ["network", gs.HALL_C_ROUTER_ID, 4]]:
		var s: Array = world.get_socket_positions(ep[0], ep[1])
		var uniq := {}
		for v in s:
			uniq[str(v)] = 1
		chk("eigene Buchsen %s" % ep[1], s.size() >= ep[2] and uniq.size() == s.size(), s.size())
	# belegte Buchse wird vom Server auf eine freie verschoben, aber nie doppelt vergeben
	var r2 := _rack(Vector3(0.0, 0.0, -2.0))
	gs.request_connect_cable("power", strip, r2, 4, 0)
	await wait(2)
	var map: Dictionary = gs.get_cable_slot_map("power", strip)
	chk("keine Dose doppelt", map.size() == 2 and map.values()[0] != map.values()[1], map)


func _decor() -> void:
	print("--- Umsetzen")
	var strip := ""
	for d in gs.decor_items:
		if gs.is_power_strip_decor(d):
			strip = d
	var n_before: int = gs.count_cables_on("power", strip)
	gs.request_relocate_decor(strip, Vector3(2.3, 0.0, 1.1), PI * 0.5)
	await wait(3)
	var d: Dictionary = gs.decor_items[strip]
	chk("Leiste umgesetzt (Raster 25 cm)", (d["pos"] as Vector3).is_equal_approx(Vector3(2.25, 0.0, 1.0)), d["pos"])
	chk("Kabel bleiben dran", gs.count_cables_on("power", strip) == n_before and n_before > 0, n_before)
	chk("3D-Modell folgt", world._decor_nodes[strip].position.is_equal_approx(d["pos"]))
	gs.request_relocate_decor(strip, Vector3(0.0, 0.0, 0.0), 0.0)
	await wait(2)
	chk("nicht ins Rack", not (gs.decor_items[strip]["pos"] as Vector3).is_equal_approx(Vector3.ZERO))
	gs.request_relocate_decor(strip, Vector3(99.0, 0.0, 0.0), 0.0)
	await wait(2)
	chk("nicht außerhalb", (gs.decor_items[strip]["pos"] as Vector3).x < 10.0)
	var shelf := _decor_add("prop_storage_shelf", Vector3(-3.0, 0.0, 1.0))
	await wait(2)
	gs.decor_items[shelf]["stored_items"][0] = {"id": "crate_z", "item_type": "ups", "pos": Vector3.ZERO, "held_by": 0}
	gs.request_relocate_decor(shelf, Vector3(-3.0, 0.0, 2.0), 0.0)
	await wait(2)
	chk("Regal mit Inhalt umgesetzt", gs.decor_items[shelf]["stored_items"][0] != null and (gs.decor_items[shelf]["pos"] as Vector3).z == 2.0)
	var ri: Node = main.get("rack_inspector")
	main.call("_open_device_inspector", "decor", shelf)
	await wait(3)
	chk("Menü für Einrichtung offen", ri.visible)
	main.call("_on_relocate_rack_requested", shelf)
	await wait(2)
	chk("Umsetzen gestartet", world.local_player.relocating_rack_id == shelf)
	await wait(5)
	world.local_player.relocating_rack_id = ""
	var money_before: float = gs.money
	gs.request_sell_decor(shelf)
	await wait(2)
	chk("verkauft, Kiste bleibt", not gs.decor_items.has(shelf) and gs.money > money_before and gs.crates.values().any(func(c): return c["item_type"] == "ups"))


func _extinguisher() -> void:
	print("--- Feuerlöscher")
	gs.request_set_active_slot(1)
	chk("je Standort einer", gs.get_extinguisher_at_station("garage") == "garage" and gs.get_extinguisher_at_station("nord") == "nord")
	gs.request_pickup_extinguisher("garage")
	await wait(2)
	chk("genommen, Halter leer", gs.is_player_holding_extinguisher(1) and gs.get_extinguisher_at_station("garage") == "")
	var g: Node = world.get_node("Garage")
	chk("Halter sichtbar leer", not g._extinguisher_mounts["garage"].visible and g._extinguisher_mounts["nord"].visible)
	gs.request_drop_extinguisher(Vector3(1.0, 0.0, 2.0), 0.5)
	await wait(2)
	chk("steht auf dem Boden", world._extinguisher_nodes.has("garage") and world._extinguisher_nodes["garage"].position.is_equal_approx(Vector3(1.0, 0.0, 2.0)))
	chk("Halter bleibt leer", gs.get_extinguisher_at_station("garage") == "")
	gs.request_set_active_slot(2)
	gs.request_pickup_extinguisher("garage")
	await wait(2)
	chk("aufgehoben in Slot 2", gs.get_held_extinguisher(1) == "garage" and not world._extinguisher_nodes.has("garage"))
	gs.request_hang_extinguisher("nord")
	await wait(2)
	chk("belegter Halter nimmt keinen zweiten", gs.is_player_holding_extinguisher(1))
	var rid: String = gs.racks.keys()[0]
	var slot: Dictionary = gs.racks[rid]["slots"][0]
	slot.merge({"item_type": "web_server", "state": "burning", "fire_level": 1.0}, true)
	for i in 5:
		gs.request_spray_extinguisher(rid, 0)
	chk("Brand gelöscht", str(slot["state"]) == "crashed", slot["fire_level"])
	var f1: float = gs.get_extinguisher_fill("garage")
	chk("Füllung sinkt", f1 < 1.0 and f1 > 0.9, f1)
	for i in 130:
		gs.request_spray_extinguisher("", -1)
	chk("wird leer (~20 s)", gs.get_extinguisher_fill("garage") == 0.0)
	slot["state"] = "burning"
	slot["fire_level"] = 1.0
	gs.request_spray_extinguisher(rid, 0)
	chk("leer löscht nicht", float(slot["fire_level"]) == 1.0)
	slot["state"] = "ok"
	gs.request_hang_extinguisher("garage")
	await wait(2)
	gs._update_extinguishers(gs.EXT_REFILL_SECONDS * 0.5)
	chk("füllt sich im Halter", absf(gs.get_extinguisher_fill("garage") - 0.5) < 0.05, gs.get_extinguisher_fill("garage"))
	gs.request_pickup_extinguisher("garage")
	await wait(2)
	gs.handle_player_disconnect(1)
	await wait(1)
	chk("nach Verbindungsabbruch im Halter", gs.get_extinguisher_at_station("garage") == "garage")
	gs.request_set_active_slot(1)
	var s: Dictionary = gs._sanitize_extinguishers({"garage": {"station": "nord"}, "nord": {"station": "nord"}})
	chk("kaputte Daten: kein doppelter Halter", s["garage"]["station"] != s["nord"]["station"], [s["garage"]["station"], s["nord"]["station"]])
	chk("leere Daten: Standard", gs._sanitize_extinguishers(null).size() == 2)


func _slot_power() -> void:
	print("--- Einschub-Strom")
	var rid: String = gs.racks.keys()[0]
	var rack: Dictionary = gs.racks[rid]
	var slot: Dictionary = rack["slots"][0]
	slot.merge({"item_type": "web_server", "state": "ok", "components": gs._default_components("web_server")}, true)
	slot.erase("offline")
	var other: Dictionary = rack["slots"][1]
	other.merge({"item_type": "web_server", "state": "ok", "components": gs._default_components("web_server")}, true)
	gs._recalculate_networks_and_metrics()
	var strip := ""
	for d in gs.decor_items:
		if gs.is_power_strip_decor(d):
			strip = d
	gs.request_connect_cable("power", gs.WALL_BREAKER_ID, strip, 0, 5)
	await wait(3)
	chk("Rack läuft über die Leiste", bool(rack["powered"]))
	# Erster Strom: die Server fahren der Reihe nach hoch
	for i in 80:
		gs._update_slot_boot(0.5)
	var w_on: int = gs.get_rack_hardware_summary(rid)["watts"]
	gs.request_toggle_slot_extended(rid, 0)
	await wait(2)
	chk("ausgefahren = aus", bool(slot.get("offline", false)) and not gs.is_slot_on(slot))
	chk("anderer Einschub läuft weiter", gs.is_slot_on(other))
	chk("Verbrauch sinkt", int(gs.get_rack_hardware_summary(rid)["watts"]) < w_on, [w_on, gs.get_rack_hardware_summary(rid)["watts"]])
	gs.request_toggle_slot_extended(rid, 0)
	await wait(2)
	chk("eingeschoben: fährt hoch", slot.has("boot_left") and not gs.is_slot_on(slot), slot.get("boot_total", 0))
	gs._update_slot_boot(3.0)
	chk("nach 3 s noch nicht fertig", not gs.is_slot_on(slot))
	gs._update_slot_boot(20.0)
	chk("danach online", gs.is_slot_on(slot) and not slot.has("boot_left"))
	chk("Hochfahrzeiten 6–15 s", gs.get_boot_seconds("mb_h110m_srv") == 6.0 and gs.get_boot_seconds("mb_hgx_8gpu") in [15.0, 6.0], [gs.get_boot_seconds("web_server"), gs.get_boot_seconds("gpu_server")])
	var cats := {}
	for id in gs.ITEM_CATALOG:
		var c: Dictionary = gs.ITEM_CATALOG[id]
		if bool(c.get("mainboard", false)):
			cats[c["mb_cat"]] = gs.get_boot_seconds(id)
	chk("je Klasse eine Zeit", cats.get("entry") == 6.0 and cats.get("server") == 9.0 and cats.get("storage") == 11.0 and cats.get("gpu") == 15.0, cats)
	# gezogen und wieder eingesetzt
	gs.request_toggle_slot_extended(rid, 1)
	await wait(2)
	gs.request_pull_server_tray(rid, 1)
	await wait(2)
	chk("Server gezogen", str(rack["slots"][1]["item_type"]) == "")
	gs.request_insert_server_tray(rid, 1)
	await wait(2)
	chk("eingesetzt, noch aus", str(rack["slots"][1]["item_type"]) != "" and not gs.is_slot_on(rack["slots"][1]))
	gs.request_toggle_slot_extended(rid, 1)
	await wait(2)
	gs._update_slot_boot(20.0)
	chk("eingesetzt und hochgefahren", gs.is_slot_on(rack["slots"][1]))
	var node: Node = world._rack_nodes[rid]
	gs.request_toggle_slot_extended(rid, 0)
	await wait(10)
	gs.request_toggle_slot_extended(rid, 0)
	await wait(20)
	chk("Anzeige ohne Fehler", is_instance_valid(node))
	gs._update_slot_boot(20.0)


func _breaker() -> void:
	print("--- Stromkasten")
	chk("eine Steckdose", gs.get_max_ports("power", gs.WALL_BREAKER_ID) == 1)
	var rid: String = gs.racks.keys()[1]
	gs.request_connect_cable("power", gs.WALL_BREAKER_ID, rid, -1, -1)
	await wait(2)
	chk("zweites Kabel abgelehnt", gs.count_cables_on("power", gs.WALL_BREAKER_ID) == 1)
	chk("Router nutzt echte Ports", gs.get_max_ports("network", gs.WALL_ROUTER_ID) == gs.ROUTER_TIER_JACK_COUNTS[gs.router_tier])
	chk("altes Zubehör nicht mehr kaufbar", gs._accessory_price("power_strip") == 0 and gs._accessory_price("net_hub") == 0)
	var data: Dictionary = gs.export_save_data()
	data.erase("schema") # Spielstände von vor v3.4 haben noch kein Schema
	data["power_strips"] = 7
	data["net_hubs"] = 2
	data["cables"]["cable_alt1"] = {"id": "cable_alt1", "cable_type": "power", "from_id": gs.WALL_BREAKER_ID, "to_id": rid, "from_slot": 3, "to_slot": -1}
	var strips := 0
	var lans := 0
	gs.load_from_save_data(data, "p1", "p1")
	await wait(3)
	for c in gs.crates.values():
		if c["item_type"] == "prop_power_strip":
			strips += int(c.get("pack_count", 1))
		if c["item_type"] == "prop_lan_strip":
			lans += int(c.get("pack_count", 1))
	chk("alter Stand: 7 Strom- und 2 LAN-Leisten als Kisten", strips == 7 and lans == 2, [strips, lans])
	chk("altes Kabel bleibt stecken", gs.cables.has("cable_alt1") and bool(gs.racks[rid]["powered"]))
	gs.load_from_save_data(gs.export_save_data(), "p1", "p1")
	await wait(2)
	strips = 0
	for c in gs.crates.values():
		if c["item_type"] == "prop_power_strip":
			strips += int(c.get("pack_count", 1))
	chk("nur einmal umgewandelt", strips == 7, strips)
	gs._van_parcel_parts.append("acc:power_strip")
	gs._deliver_parts_parcel()
	chk("alte Bestellung kommt als Leiste", gs._van_parcel_parts.is_empty())


func _coolers() -> void:
	print("--- Kühlgeräte")
	var prices := {"cool_k90": [2400, 2], "cool_inrow": [5500, 3], "cool_tower": [9800, 4], "cool_cdu": [18000, 5]}
	for id in prices:
		var c: Dictionary = gs.ITEM_CATALOG[id]
		chk("%s $%d ab Stufe %d" % [c["name"], c["price"], gs.get_item_required_level(id)], int(c["price"]) == prices[id][0] and gs.get_item_required_level(id) == prices[id][1])
	gs.room_level = 1
	var ids := {}
	for spec in [["cool_k90", Vector3(8.5, 0, 6.0)], ["cool_tower", Vector3(5.0, 0, 6.0)], ["cool_inrow", Vector3(8.0, 0, 0.0)], ["cool_cdu", Vector3(9.5, 0, 1.5)]]:
		gs.crates["held"] = {"id": "held", "item_type": spec[0], "pos": Vector3.ZERO, "held_by": 1, "held_slot": 1, "pack_count": 1}
		gs.request_set_active_slot(1)
		gs.request_place_held_structure(spec[1], 0.0)
		await wait(2)
		for cid in gs.coolers:
			if gs.coolers[cid]["cooler_type"] == spec[0]:
				ids[spec[0]] = cid
		chk("%s aufgestellt" % spec[0], ids.has(spec[0]))
		gs.crates.erase("held")
	gs.crates["held"] = {"id": "held", "item_type": "cool_cdu", "pos": Vector3.ZERO, "held_by": 1, "held_slot": 1, "pack_count": 1}
	gs.request_place_held_structure(Vector3(6.0, 0, 6.0), 0.0)
	await wait(1)
	chk("Standgerät nicht auf den Rasen", gs.crates.has("held"))
	gs.crates.erase("held")
	for t in ids:
		chk("%s hat Stromanschluss und Modell" % t, gs.get_max_ports("power", ids[t]) == 1 and world.get_port_world_pos("power", ids[t]) is Vector3 and world._cooler_nodes[ids[t]].get_child_count() > 8)
	var strip := ""
	for d in gs.decor_items:
		if gs.is_power_strip_decor(d):
			strip = d
	gs.request_connect_cable("power", strip, ids["cool_inrow"], -1, 0)
	await wait(2)
	chk("Reihenkühler läuft", bool(gs.coolers[ids["cool_inrow"]]["powered"]))
	chk("Innengerät läuft nicht durch Standgerät", not gs.has_indoor_unit())
	chk("nahe Racks entlastet", gs._get_floor_cooler_relief(Vector3(9.0, 0, 0.0)) == 6.0 and gs._get_floor_cooler_relief(Vector3(0.0, 0, 0.0)) == 0.0)
	main.call("_open_device_inspector", "cooler", ids["cool_inrow"])
	await wait(3)
	chk("Menü offen", main.get("rack_inspector").visible)
	main.call("_close_rack_inspector")
	gs.room_temp = 60.0
	for i in 10:
		gs._run_simulation_step(1.0)
	chk("kühlt ohne Innengerät", gs.room_temp < 55.0, gs.room_temp)


func _levels() -> void:
	print("--- Stufen")
	chk("10 Stufen bis 5 Mio.", gs.COMPANY_LEVEL_THRESHOLDS.size() == 10 and gs.COMPANY_LEVEL_THRESHOLDS[9] == 5000000 and gs.COMPANY_LEVEL_BENEFITS.size() == 10)
	chk("Anfang unverändert", gs.COMPANY_LEVEL_THRESHOLDS.slice(0, 5) == [0, 24000, 72000, 180000, 400000])
	var prev := 0.0
	var ok := true
	for l in range(1, 11):
		var b: Dictionary = gs.COMPANY_LEVEL_BENEFITS[l]
		ok = ok and float(b["rev_mult"]) > prev
		prev = float(b["rev_mult"])
		gs.company_level = l
		gs.get_max_delivery_slots()
	chk("Boni steigen", ok)
	chk("8 Ruf-Ränge", gs.REPUTATION_LABELS.size() == 8 and gs.REPUTATION_THRESHOLDS.size() == 7)
	gs.reputation = 100.0
	chk("höchster Rang", gs.get_reputation_label() == "Marktführer")
	gs.reputation = 0.0
	chk("niedrigster Rang", gs.get_reputation_label() == "Unbekannt")
	gs.reputation = 20.0
	var max_req := 0
	for cat in load("res://scripts/data/hardware_catalog.gd").PARTS.values():
		for p in cat:
			max_req = maxi(max_req, gs.get_part_required_level(p))
	chk("alle Teile spätestens mit Stufe 4 frei", max_req == 4, max_req)


func _admin() -> void:
	print("--- Admin")
	var fake := 4242
	nm.players[fake] = {"name": "Gast", "color": Color.WHITE, "skin": {}}
	gs.money = 1000.0
	chk("Gast darf nichts", not am.execute(fake, "money_set", {"v": 99999.0}) and gs.money == 1000.0)
	chk("Gast kann sich nicht selbst freischalten", not am.execute(fake, "grant", {"peer": fake}) and not am.is_admin(fake))
	chk("Host setzt Geld", am.execute(1, "money_set", {"v": 5000.0}) and gs.money == 5000.0)
	for a in [{}, {"v": "x"}, {"v": NAN}, {"v": INF}, {"v": [1]}, {"v": 1.0, "a": 1, "b": 2, "c": 3, "d": 4}]:
		am.execute(1, "money_set", a)
	chk("kaputte Werte ändern nichts", gs.money == 5000.0, gs.money)
	am.execute(1, "money_set", {"v": 1.0e30})
	chk("Wert begrenzt", gs.money == float(root.get_node("SecurityGuard").MAX_MONEY), gs.money)
	chk("unbekannter Befehl abgelehnt", not am.execute(1, "rm_rf", {}))
	chk("Host gibt Rechte", am.execute(1, "grant", {"peer": fake}) and am.is_admin(fake))
	chk("Gast-Admin darf", am.execute(fake, "reputation", {"v": 50.0}) and gs.reputation == 50.0)
	chk("Gast-Admin darf keine Rechte vergeben", not am.execute(fake, "revoke", {"peer": fake}) and am.is_admin(fake))
	chk("Gast-Admin kann Host nicht kicken", not am.execute(fake, "kick", {"peer": 1}) and not am.execute(fake, "ban", {"peer": 1}))
	nm.players[4343] = {"name": "Zwei", "color": Color.WHITE, "skin": {}}
	am.execute(1, "grant", {"peer": 4343})
	chk("Gast-Admin kann anderen Admin nicht kicken", not am.execute(fake, "kick", {"peer": 4343}))
	am._on_player_left(4343)
	chk("Rechte enden mit der Verbindung", not am.is_admin(4343))
	chk("Stufe", am.execute(1, "level", {"v": 7}) and gs.company_level == 7)
	chk("Uhrzeit", am.execute(1, "time", {"v": 18}) and absf(gs.time_of_day - 0.75) < 0.01)
	chk("Wetter", am.execute(1, "weather", {"v": "rain"}) and gs.weather_state == "rain" and not am.execute(1, "weather", {"v": "lava"}))
	chk("Uhr anhalten", am.execute(1, "time_scale", {"v": 0.0}) and gs.clock_scale == 0.0)
	var t0: float = gs.time_of_day
	await wait(30)
	chk("Uhr steht", is_equal_approx(gs.time_of_day, t0))
	chk("ungültiges Tempo abgelehnt", not am.execute(1, "time_scale", {"v": 7.0}))
	am.execute(1, "time_scale", {"v": 1.0})
	var day: int = gs.day_number
	am.execute(1, "next_day", {})
	for i in 3:
		gs._run_simulation_step(1.0)
	chk("nächster Tag", gs.day_number == day + 1, [day, gs.day_number])
	for rid in gs.racks:
		for s in gs.racks[rid]["slots"]:
			s.erase("offline")
			s.erase("boot_left")
	gs._recalculate_networks_and_metrics()
	chk("Brand auslösen", am.execute(1, "fire", {}) and gs.has_any_fire())
	chk("alles reparieren", am.execute(1, "repair_all", {}) and not gs.has_any_fire())
	chk("nichts zu reparieren", not am.execute(1, "repair_all", {}))
	gs.building_upgrades = {}
	chk("Netzausfall an/aus", am.execute(1, "outage", {}) and gs.grid_outage_left > 0.0 and am.execute(1, "outage_end", {}) and gs.grid_outage_left == 0.0)
	var n: int = gs.crates.size()
	gs.crates.clear()
	chk("Item geben", am.execute(1, "give_item", {"id": "ups", "n": 6}) and gs.crates.size() == 1 and int(gs.crates.values()[0]["pack_count"]) == 1)
	chk("unbekanntes Item abgelehnt", not am.execute(1, "give_item", {"id": "server_tray", "n": 1}) and not am.execute(1, "give_item", {"id": "../x", "n": 1}))
	chk("Bauteil geben", am.execute(1, "give_part", {"id": "gpu_rtx4090", "n": 3}) and int(gs.parts_inventory.get("gpu_rtx4090", 0)) >= 3 and not am.execute(1, "give_part", {"id": "gpu_quatsch", "n": 1}))
	chk("Teleport nach Halle Nord", am.execute(1, "send_site", {"peer": 1, "site": "halle_nord"}))
	await wait(3)
	chk("angekommen", world.local_player.position.z < -300.0, world.local_player.position)
	am.execute(1, "send_site", {"peer": 1, "site": "garage"})
	await wait(3)
	chk("Ziel ohne Figur abgelehnt", not am.execute(1, "goto", {"peer": 9999}))
	chk("Protokoll gefüllt", am.log_entries.size() > 10, am.log_entries.size())
	main.call("_open_admin")
	var ui: Node = main.get("admin_ui")
	for tab in ["players", "money", "world", "events", "items", "log"]:
		ui._tab = tab
		ui.refresh()
		await wait(2)
		chk("Reiter %s" % tab, ui.visible and ui._body.get_child_count() > 0)
	ui._tab = "items"
	ui._search = "prismor"
	ui.refresh()
	await wait(2)
	chk("Suche findet Bauteile", ui._list_box.get_child_count() > 5, ui._list_box.get_child_count())
	main.call("_close_admin")
	nm.players.erase(fake)
	nm.players.erase(4343)
	am._reset()
	chk("Sitzungsende löscht Rechte", not am.is_admin(fake) and am.log_entries.is_empty())
	# Rate-Limit für Gäste
	nm.players[fake] = {"name": "Gast", "color": Color.WHITE, "skin": {}}
	am._granted[fake] = true
	var done := 0
	for i in 60:
		if am.execute(fake, "money_add", {"v": 1}):
			done += 1
	chk("Gast-Admin wird gedrosselt", done <= 20, done)
	nm.players.erase(fake)
	am._reset()


func _brands() -> void:
	print("--- Marken")
	var re := RegEx.create_from_string("(?i)celeron|pentium|\\bcore i\\d|core 2|xeon|athlon|ryzen|epyc|threadripper|genoa|bergamo|nvidia|geforce|\\brtx|\\bgtx|quadro|tesla|blackwell|nvlink|instinct|intel|\\bamd\\b|gigabyte|asrock|supermicro|asus|exos|sunon|noctua|80\\+|optane|windows|speedport|sprinter")
	var hits: Array = []
	var hc = load("res://scripts/data/hardware_catalog.gd")
	var names := {}
	for cat in hc.PARTS:
		for p in hc.PARTS[cat]:
			if re.search(str(p["name"])) != null:
				hits.append(p["name"])
			if names.has(p["name"]):
				hits.append("doppelt " + str(p["name"]))
			names[p["name"]] = 1
	for id in gs.ITEM_CATALOG:
		for k in ["name", "desc"]:
			if re.search(str(gs.ITEM_CATALOG[id].get(k, ""))) != null:
				hits.append([id, gs.ITEM_CATALOG[id][k]])
	chk("keine Marken und keine doppelten Namen im Katalog", hits.is_empty(), hits)
	var f := 0
	for p in hc.get_category_parts("gpu"):
		if hc.matches_filter("gpu", p, "Performance"):
			f += 1
	chk("GPU-Filter Performance", f >= 10, f)
	chk("alte Bauteil-IDs gelten weiter", not hc.get_part("cpu", "cpu_xeon_64c").is_empty() and not hc.get_part("gpu", "gpu_h200").is_empty())


func _save() -> void:
	print("--- Speichern")
	gs.request_set_active_slot(1)
	for c in gs.crates.values():
		c["held_by"] = 0
	gs.request_pickup_extinguisher("garage")
	await wait(2)
	gs.request_drop_extinguisher(Vector3(1.5, 0.0, 1.5), 0.2)
	await wait(2)
	var r: Dictionary = sm.save_world("paket1", "Paket1", gs.export_save_data())
	chk("gespeichert", r["ok"])
	var l: Dictionary = sm.load_world_file("paket1")
	chk("Signatur gültig", l["integrity"]["status"] == "valid", l["integrity"])
	gs.load_from_save_data(l["state"], "paket1", "Paket1")
	await wait(3)
	var e: Dictionary = gs.extinguishers["garage"]
	chk("Löscher liegt noch am Platz", str(e["station"]) == "" and e["pos"] is Vector3 and (e["pos"] as Vector3).is_equal_approx(Vector3(1.5, 0.0, 1.5)), e)
	chk("Firmenstufe bleibt", gs.company_level >= 7, gs.company_level)
	chk("Uhr läuft nach dem Laden normal", gs.clock_scale == 1.0)
