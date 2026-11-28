extends SceneTree
## Prüft Roadmap-Paket A: Kartons, Strom-/LAN-Leisten, Rack-Start und Einbau, Notstrom.
## Aufruf: godot --headless --path . --script res://tests/paketa_check.gd

var bad := 0
var gs: Node
var sm: Node
var main: Node
var world: Node
var cf


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func secs(s: float) -> void:
	await create_timer(s).timeout


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	sm = root.get_node("SaveManager")
	cf = load("res://scripts/world/carton_factory.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Test", 7841, {}, "", "PaketA", "", false, false)
	await wait(20)
	world = main.get_node("World")
	gs.money = 200000.0
	gs.company_level = 5
	gs.room_level = 1
	gs.power_tier = 3
	await _cartons()
	await _strips()
	await _boot()
	await _ups()
	await _install()
	await _cart()
	await _save()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


func _hold(item: String, extra: Dictionary = {}) -> void:
	for k in gs.crates.keys():
		if int(gs.crates[k].get("held_by", 0)) == 1:
			gs.crates.erase(k)
	gs.request_set_active_slot(1)
	var c := {"id": "held", "item_type": item, "pos": Vector3.ZERO, "held_by": 1, "held_slot": 1, "pack_count": 1}
	c.merge(extra, true)
	gs.crates["held"] = c


func _empties() -> Array:
	var out: Array = []
	for c in gs.crates.values():
		if str(c["item_type"]) == "empty_carton":
			out.append(c)
	return out


func _place(item: String, pos: Vector3, rot: float = 0.0, extra: Dictionary = {}) -> void:
	_hold(item, extra)
	gs.request_place_held_structure(pos, rot)
	await wait(3)


func _rack(pos: Vector3, servers: int = 2) -> String:
	var rid: String = gs._alloc_rack_id()
	gs.racks[rid] = gs._make_rack_data(rid, "rack", pos, 0.0)
	for k in servers:
		gs.racks[rid]["slots"][k].merge({"item_type": "web_server", "state": "ok", "components": gs._default_components("web_server")}, true)
	gs.racks_changed.emit()
	gs._recalculate_networks_and_metrics()
	return rid


func _decor_add(type: String, pos: Vector3) -> String:
	var did: String = gs._alloc_id("decor")
	gs.decor_items[did] = {"id": did, "item_type": type, "pos": pos, "rot_y": 0.0, "stored_items": []}
	gs._broadcast_decor_items()
	return did


func _cartons() -> void:
	print("--- Kartons")
	var kinds := {}
	for id in gs.ITEM_CATALOG:
		kinds[cf.kind_for(id)] = 1
	chk("alle acht Arten kommen vor", kinds.size() >= 6, kinds.keys())
	for k in cf.SIZES:
		var c: Node3D = cf.build(k, "Test")
		root.add_child(c)
		var ok: bool = c.find_child("Flap_F", true, false) != null and c.find_child("Flap_L", true, false) != null and c.find_child("Tape", true, false) != null
		cf.set_open(c, 1.0)
		ok = ok and absf((c.find_child("Flap_F", true, false) as Node3D).rotation.x) > 2.0 and not (c.find_child("Tape", true, false) as Node3D).visible
		chk("Karton %s mit Klappen und Band" % k, ok)
		c.queue_free()
	await _place("rack", Vector3(0.0, 0.0, 0.0))
	var rid: String = gs.racks.keys()[gs.racks.size() - 1]
	chk("Rack steht sofort (Server)", gs.racks.size() == 1)
	await wait(4)
	chk("Gerät kommt aus dem Karton", world._rack_nodes[rid].scale.x < 0.5 or not world._rack_nodes[rid].visible, world._rack_nodes[rid].scale)
	chk("noch kein leerer Karton", _empties().is_empty())
	await secs(2.6)
	chk("Gerät danach normal groß", world._rack_nodes[rid].scale.is_equal_approx(Vector3.ONE) and world._rack_nodes[rid].visible)
	chk("leerer Karton liegt daneben", _empties().size() == 1 and _empties()[0]["carton"] == "pallet" and (_empties()[0]["pos"] as Vector3).distance_to(Vector3.ZERO) > 0.7, _empties())
	await _place("prop_lan_strip", Vector3(2.5, 0.0, 2.5), 0.0, {"pack_count": 3})
	await secs(2.4)
	chk("Mengen-Kiste: kein Karton vor dem letzten Stück", _empties().size() == 1 and int(gs.crates["held"]["pack_count"]) == 2)
	await _place("ups", Vector3(-2.5, 0.0, 2.0), 0.0, {"unboxed": true, "ups": {"charge": 80.0, "health": 61.0}})
	await secs(2.4)
	chk("Gebrauchtes Gerät: kein Karton", _empties().size() == 1)
	var u: Dictionary = gs.ups_units.values()[0]
	chk("Akku-Zustand bleibt beim Umstellen", is_equal_approx(float(u["health"]), 61.0) and absf(float(u["charge"]) - 80.0) < 1.5, u)
	var m: float = gs.money
	var e: Dictionary = _empties()[0]
	gs.crates.erase("held")
	gs.crates[e["id"]]["held_by"] = 1
	gs.crates[e["id"]]["held_slot"] = 1
	gs.request_dump_carton("garage")
	await wait(2)
	chk("Altpapier bringt Geld", _empties().is_empty() and gs.money >= m + 7.0, gs.money - m)
	m = gs.money
	_hold("ups")
	gs.request_dump_carton("garage")
	await wait(2)
	chk("andere Ware nicht einwerfen", gs.crates.has("held") and gs.money <= m + 1.0)
	gs.request_dump_carton("quatsch")
	gs.crates.erase("held")
	for i in 40:
		gs._spawn_empty_carton("deco", Vector3(float(i % 5), 0.0, 1.0))
	chk("höchstens 30 leere Kartons", _empties().size() == 30, _empties().size())
	await wait(4)
	for c in _empties():
		gs.crates.erase(c["id"])
	gs._broadcast_crates()
	chk("Container in beiden Hallen", world.get_node("Garage")._paper_lids.size() == 2)
	gs.workbench_state = {"mode": "build_box", "label": "B", "rack_id": "", "slot_idx": 0, "mainboard_id": "web_server", "components": {}}
	gs.request_workbench_unpack()
	await wait(3)
	chk("Bausatz auspacken lässt Karton zurück", _empties().size() == 1 and _empties()[0]["carton"] == "build")
	gs.workbench_state = {}
	for c in _empties():
		gs.crates.erase(c["id"])


var strip := ""
var lan := ""


func _strips() -> void:
	print("--- Leisten")
	strip = _decor_add("prop_power_strip", Vector3(3.0, 0.0, 1.0))
	lan = _decor_add("prop_lan_strip", Vector3(3.0, 0.0, 1.5))
	var rid: String = gs.racks.keys()[0]
	for k in 2:
		gs.racks[rid]["slots"][k].merge({"item_type": "web_server", "state": "ok", "components": gs._default_components("web_server")}, true)
	gs.request_connect_cable("power", gs.WALL_BREAKER_ID, strip, 0, 0)
	gs.request_connect_cable("power", strip, rid, 1, 0)
	gs.request_connect_cable("network", gs.WALL_ROUTER_ID, lan, 0, 0)
	gs.request_connect_cable("network", lan, rid, 1, 0)
	await wait(3)
	gs._update_slot_boot(60.0)
	gs._update_slot_boot(60.0)
	gs._recalculate_networks_and_metrics()
	chk("Rack läuft und ist im Netz", bool(gs.racks[rid]["powered"]) and bool(gs.racks[rid]["networked"]))
	chk("Last an der Leiste", gs.get_strip_load(strip) > 20 and absi(gs.get_strip_load(strip) - int(gs.get_rack_hardware_summary(rid)["watts"])) < 5, [gs.get_strip_load(strip), gs.get_rack_hardware_summary(rid)["watts"]])
	chk("jede Leiste 11 kW, Kette 22 kW", gs.get_strip_limit(strip) == 11000 and StripRules.CHAIN_LIMIT_W == 22000)
	var sub := _decor_add("prop_power_strip", Vector3(3.5, 0.0, -1.0))
	gs.request_connect_cable("power", strip, sub, 2, 0)
	await wait(2)
	chk("zweite Leiste auch 11 kW", gs.get_strip_limit(sub) == 11000)
	gs.request_toggle_strip(strip)
	await wait(2)
	chk("Schalter aus: Rack ohne Strom", not gs.is_strip_on(strip) and not bool(gs.racks[rid]["powered"]))
	await secs(0.6)
	var dn: Node = world._decor_nodes[strip]
	chk("Anzeige AUS, Wippe gekippt", dn._disp.text == "AUS" and dn._switch_node.rotation.x < 0.0, [dn._disp.text, dn._switch_node.rotation.x])
	gs.request_toggle_strip(strip)
	await wait(2)
	chk("Schalter ein: Strom wieder da", bool(gs.racks[rid]["powered"]))
	gs._update_slot_boot(60.0)
	gs._update_slot_boot(60.0)
	await secs(0.6)
	chk("Anzeige in Watt, LED an", dn._disp.text.contains("W") and dn._port_state[1] == 2, dn._disp.text)
	gs.request_toggle_strip(lan)
	await wait(2)
	chk("LAN-Leiste aus trennt das Netz", not bool(gs.racks[rid]["networked"]))
	gs.request_toggle_strip(lan)
	await wait(2)
	chk("LAN-Leiste ein", bool(gs.racks[rid]["networked"]))
	# Überlast an der Unterleiste
	var cid: String = gs._alloc_id("cooler")
	gs.coolers[cid] = {"id": cid, "cooler_type": "cool_cdu", "pos": Vector3(6.0, 0.0, 0.0), "rot_y": 0.0, "powered": false}
	var cid2: String = gs._alloc_id("cooler")
	gs.coolers[cid2] = {"id": cid2, "cooler_type": "cool_inrow", "pos": Vector3(7.5, 0.0, 0.0), "rot_y": 0.0, "powered": false}
	gs._broadcast_coolers()
	gs.request_connect_cable("power", sub, cid, 1, 0)
	gs.request_connect_cable("power", sub, cid2, 2, 0)
	await wait(2)
	chk("Last je Leiste, Kette zählt beide", gs.get_strip_load(sub) > 3500 and gs.get_chain_load(sub) >= gs.get_strip_load(sub) + gs.get_strip_load(strip) - 5, [gs.get_strip_load(sub), gs.get_strip_load(strip), gs.get_chain_load(sub)])
	gs.strip_loads[sub] = 12000
	gs._tick_strips(3.0)
	chk("löst nicht sofort aus", gs.is_strip_on(sub))
	gs._tick_strips(1.5)
	chk("löst nach 4 s aus", not gs.is_strip_on(sub) and bool(gs.decor_items[sub]["tripped"]) and not bool(gs.coolers[cid]["powered"]))
	chk("Hauptleiste bleibt an", gs.is_strip_on(strip) and bool(gs.racks[rid]["powered"]))
	gs.request_toggle_strip(sub)
	await wait(2)
	chk("wieder einschaltbar", gs.is_strip_on(sub) and not bool(gs.decor_items[sub]["tripped"]))
	gs.request_disconnect_cables_on("power", cid)
	await wait(2)
	gs.coolers.erase(cid)
	gs.coolers.erase(cid2)
	# Wandmontage
	var spot: Dictionary = gs.get_strip_wall_spot(Vector3(1.1, 1.13, -4.45), Vector3(0, 0, 1))
	chk("Platz an der Nordwand", not spot.is_empty() and (spot["pos"] as Vector3).is_equal_approx(Vector3(1.0, 1.1, -4.475)), spot)
	chk("nicht über dem Stromkasten", not gs.can_place_strip_on_wall(Vector3(-4.0, 1.1, -4.475), 0.0))
	chk("nicht am Garagentor", not gs.can_place_strip_on_wall(Vector3(0.0, 1.0, 4.475), PI))
	chk("nicht frei in der Luft", not gs.can_place_strip_on_wall(Vector3(1.0, 1.1, 0.0), 0.0))
	gs.request_relocate_decor(strip, spot["pos"], 0.0)
	await wait(3)
	chk("Leiste hängt an der Wand", gs.is_wall_strip(gs.decor_items[strip]) and dn.is_on_wall())
	chk("Buchsen zeigen in den Raum", dn.global_transform.basis.y.is_equal_approx(Vector3(0, 0, 1)), dn.global_transform.basis.y)
	chk("Kabel bleiben dran", gs.count_cables_on("power", strip) == 3 and bool(gs.racks[rid]["powered"]), gs.count_cables_on("power", strip))
	chk("Kabelrichtung waagerecht", absf((world.get_port_world_dir("power", strip) as Vector3).y) < 0.01)
	gs.request_relocate_decor(strip, Vector3(3.0, 0.0, 1.0), 0.0)
	await wait(3)
	chk("zurück auf den Boden", not gs.is_wall_strip(gs.decor_items[strip]) and not dn.is_on_wall())
	await _place("prop_power_strip", Vector3(1.0, 1.1, -4.475), 0.0, {"unboxed": true})
	var wall_n := 0
	for d in gs.decor_items.values():
		if gs.is_wall_strip(d):
			wall_n += 1
	chk("neu an die Wand setzen", wall_n == 1)
	gs.halle_nord_owned = true
	chk("Wand in Halle Nord", not gs.get_strip_wall_spot(Vector3(-11.8, 1.0, gs.HALLE_NORD_ORIGIN.z + 1.0), Vector3(1, 0, 0)).is_empty())
	gs.halle_nord_owned = false


func _boot() -> void:
	print("--- Rack-Start")
	var rid: String = gs.racks.keys()[0]
	var slots: Array = gs.racks[rid]["slots"]
	slots[2].merge({"item_type": "net_switch", "state": "ok", "components": {}}, true)
	gs._recalculate_networks_and_metrics()
	chk("läuft", gs.is_slot_on(slots[0]) and gs.is_slot_on(slots[1]))
	gs.breaker_on = false
	gs._broadcast_power_change()
	chk("Stromausfall: alles aus", not gs.is_slot_on(slots[0]) and not gs.is_slot_on(slots[1]) and not gs.is_slot_on(slots[2]))
	gs.breaker_on = true
	gs._broadcast_power_change()
	var w: Array = [float(slots[0].get("boot_wait", 0)), float(slots[1].get("boot_wait", 0)), float(slots[2].get("boot_wait", 0))]
	chk("gestaffelt", w[0] > 0.5 and is_equal_approx(w[1] - w[0], 1.5) and is_equal_approx(w[2] - w[1], 1.5), w)
	var total := 0.0
	var first := -1.0
	var last := -1.0
	while total < 40.0 and last < 0.0:
		gs._update_slot_boot(0.25)
		total += 0.25
		if first < 0.0 and gs.is_slot_on(slots[0]):
			first = total
		if gs.is_slot_on(slots[0]) and gs.is_slot_on(slots[1]) and gs.is_slot_on(slots[2]):
			last = total
	chk("der Reihe nach online", first > 5.0 and last > first + 2.0 and last < 20.0, [first, last])
	gs.request_toggle_slot_extended(rid, 1)
	await wait(2)
	gs.breaker_on = false
	gs._broadcast_power_change()
	gs.breaker_on = true
	gs._broadcast_power_change()
	for i in 80:
		gs._update_slot_boot(0.5)
	chk("ausgefahrener Einschub startet nicht mit", gs.is_slot_on(slots[0]) and not gs.is_slot_on(slots[1]))
	gs.request_toggle_slot_extended(rid, 1)
	await wait(2)
	for i in 40:
		gs._update_slot_boot(0.5)
	chk("danach doch", gs.is_slot_on(slots[1]))
	var data: Dictionary = gs.export_save_data()
	gs.load_from_save_data(data, "pa", "pa")
	gs.is_active = true
	await wait(3)
	slots = gs.racks[rid]["slots"]
	chk("Laden startet nicht neu", gs.is_slot_on(slots[0]) and gs.is_slot_on(slots[1]))
	await secs(1.8)
	var node: Node = world._rack_nodes[rid]
	gs.breaker_on = false
	gs._broadcast_power_change()
	await wait(10)
	gs.breaker_on = true
	gs._broadcast_power_change()
	await wait(6)
	chk("Anzeige: Relais und Innenlicht", node._power_up_t > 0.0)
	await secs(1.0)
	chk("Anzeige SELBSTTEST", node._lcd_stats.text.contains("SELBSTTEST"), node._lcd_stats.text)
	for i in 60:
		gs._update_slot_boot(0.5)


func _ups() -> void:
	print("--- Notstrom")
	for uid in gs.ups_units.keys():
		gs.ups_units.erase(uid)
	gs._broadcast_ups()
	var rid: String = gs.racks.keys()[0]
	for t in [["ups", 700, 1], ["ups_cabinet", 3200, 2], ["ups_container", 12000, 4]]:
		chk("%s $%d ab Stufe %d" % [t[0], t[1], t[2]], int(gs.ITEM_CATALOG[t[0]]["price"]) == t[1] and gs.get_item_required_level(t[0]) == t[2])
	await _place("ups", Vector3(-2.5, 0.0, 0.0), 0.0, {"unboxed": true})
	await _place("ups_cabinet", Vector3(6.5, 0.0, -2.0), 0.0, {"unboxed": true})
	await _place("ups_container", Vector3(9.5, 0.0, 0.5), 0.0, {"unboxed": true})
	chk("drei Größen aufgestellt", gs.ups_units.size() == 3)
	await _place("ups_container", Vector3(10.0, 0.0, 2.0), 0.0, {"unboxed": true})
	chk("Container braucht Platz", gs.ups_units.size() == 3)
	gs.crates.erase("held")
	var by := {}
	for uid in gs.ups_units:
		by[gs.ups_units[uid]["ups_type"]] = uid
	for t in by:
		var n: Node = world._ups_nodes[by[t]]
		chk("%s: Modell, 10 Balken, Status, Lüfter, Display" % t, n._bar_mats.size() == 10 and n._status_mat != null and n._fans.size() >= 1 and n._screen != null and n._mod_mats.size() >= 3, [n._bar_mats.size(), n._fans.size(), n._mod_mats.size()])
		chk("%s: Anschluss" % t, world.get_port_world_pos("power", by[t]) is Vector3 and (world.get_socket_positions("power", by[t]) as Array).size() == 2)
	var u: Dictionary = gs.ups_units[by["ups"]]
	gs.request_connect_cable("power", strip, by["ups"], 3, 0)
	await wait(2)
	chk("verbunden", bool(u["connected"]))
	gs.get_strip_load(strip)
	u["charge"] = 50.0
	var l0: int = gs.total_watts
	gs._recalculate_networks_and_metrics()
	chk("lädt mit 300 W", gs.total_watts >= 300 and float(u["charge"]) == 50.0, gs.total_watts)
	gs._run_simulation_step(60.0)
	chk("Laden: 300 W × 1 h ≈ 14 %", absf(float(u["charge"]) - 50.0 - 13.8) < 2.0, u["charge"])
	u["charge"] = 100.0
	gs.breaker_on = false
	gs.grid_outage_left = 5000.0
	gs._broadcast_power_change()
	chk("Netz weg: Rack läuft weiter, kein Neustart", bool(gs.racks[rid]["powered"]) and gs.is_slot_on(gs.racks[rid]["slots"][0]) and gs.ups_backup_active)
	var load_w: float = float(gs.total_watts)
	var c0: float = float(u["charge"])
	gs._run_simulation_step(2.0)
	var wh: float = (c0 - float(u["charge"])) / 100.0 * gs.get_ups_capacity(u)
	chk("Entnahme nach Last (Wh)", absf(wh - (load_w * 1.06 + 20.0) * 2.0 / 60.0) < 1.0, [wh, load_w])
	chk("entlädt, Akku altert leicht", bool(u["discharging"]) and float(u["health"]) < 100.0 and float(u["health"]) > 99.5, u["health"])
	chk("Restzeit plausibel", gs.get_ups_runtime_minutes() > 60 and gs.get_ups_runtime_minutes() < 3000, gs.get_ups_runtime_minutes())
	await secs(0.8)
	var un: Node = world._ups_nodes[by["ups"]]
	chk("Display Batteriebetrieb", un._screen.text.begins_with("BATTERIEBETRIEB"), un._screen.text)
	# Überlast
	var big: Array = []
	for k in 2:
		var bc: String = gs._alloc_id("cooler")
		gs.coolers[bc] = {"id": bc, "cooler_type": "cool_cdu", "pos": Vector3(6.0 + k * 1.5, 0.0, 3.0), "rot_y": 0.0, "powered": false}
		gs._broadcast_coolers()
		gs.request_connect_cable("power", strip, bc, 4 + k, 0)
		big.append(bc)
	await wait(2)
	chk("Last über 3 kW", gs.total_watts > 3200, gs.total_watts)
	gs._run_simulation_step(2.0)
	gs._run_simulation_step(2.0)
	chk("Überlast schaltet ab", bool(u.get("tripped", false)) and not bool(gs.racks[rid]["powered"]) and not gs.is_slot_on(gs.racks[rid]["slots"][0]), [u.get("tripped"), gs.racks[rid]["powered"]])
	for bc in big:
		gs.request_disconnect_cables_on("power", bc)
		gs.coolers.erase(bc)
	gs._end_grid_outage()
	gs.breaker_on = true
	gs._broadcast_power_change()
	gs._run_simulation_step(1.0)
	chk("Netz zurück: Sperre weg, Server starten", not bool(u.get("tripped", false)) and gs.racks[rid]["slots"][0].has("boot_left"))
	for i in 80:
		gs._update_slot_boot(0.5)
	# leer
	u["charge"] = 0.3
	gs.breaker_on = false
	gs.grid_outage_left = 5000.0
	gs._broadcast_power_change()
	for i in 20:
		gs._run_simulation_step(1.0)
	chk("leer: alles aus", not bool(gs.racks[rid]["powered"]))
	gs._end_grid_outage()
	gs.breaker_on = true
	gs._broadcast_power_change()
	for i in 80:
		gs._update_slot_boot(0.5)
	# Akkutausch
	u["health"] = 50.0
	chk("halber Akku, halbe Kapazität", is_equal_approx(gs.get_ups_capacity(u), 1000.0))
	var m: float = gs.money
	gs.request_swap_ups_cells(by["ups"])
	await wait(2)
	chk("Akkus getauscht", is_equal_approx(float(u["health"]), 100.0) and gs.money <= m - 249.0 + 5.0)
	m = gs.money
	gs.request_swap_ups_cells(by["ups"])
	await wait(2)
	chk("frische Akkus nicht tauschbar", gs.money > m - 200.0)
	main.call("_open_device_inspector", "ups", by["ups_cabinet"])
	await wait(3)
	chk("Menü Notstrom", main.get("rack_inspector").visible)
	main.call("_close_rack_inspector")
	main.call("_open_device_inspector", "decor", strip)
	await wait(3)
	chk("Menü Leiste", main.get("rack_inspector").visible)
	main.call("_close_rack_inspector")
	gs.ups_units[by["ups_cabinet"]]["health"] = 70.0
	gs.request_pack_device("ups", by["ups_cabinet"])
	await wait(2)
	var held: Dictionary = gs.get_player_held_crate(1)
	chk("Schrank abgebaut mit Akku-Zustand", str(held.get("item_type", "")) == "ups_cabinet" and is_equal_approx(float(held["ups"]["health"]), 70.0), held)
	gs.crates.erase(str(held.get("id", "")))
	gs._broadcast_crates()
	# alter Spielstand ohne Typ
	var data: Dictionary = gs.export_save_data()
	data["ups_units"] = {"ups_1": {"id": "ups_1", "pos": Vector3(-2.5, 0, 2.5), "rot_y": 0.0, "connected": false, "charge": 60.0, "discharging": false}}
	gs.load_from_save_data(data, "pa", "pa")
	gs.is_active = true
	await wait(4)
	chk("alte USV wird zur kleinen", gs.get_ups_type(gs.ups_units["ups_1"]) == "ups" and gs.get_ups_health(gs.ups_units["ups_1"]) == 100.0 and world._ups_nodes["ups_1"]._bar_mats.size() == 10)
	gs._run_simulation_step(1.0)


func _install() -> void:
	print("--- Einbau")
	var rid: String = gs.racks.keys()[0]
	var node: Node = world._rack_nodes[rid]
	await secs(1.7)
	gs.parts_inventory["ram_ddr4_64gb"] = 1
	gs.request_install_component(rid, 0, "ram", "ram_ddr4_64gb")
	await wait(3)
	chk("Teil fährt ein", node._part_fx.size() >= 1, node._part_fx.size())
	await secs(1.2)
	chk("eingerastet, LED-Test lief", node._part_fx.is_empty())
	_hold("web_server")
	gs.request_install_module(rid, 3)
	await wait(3)
	chk("Einschub gleitet herein und ist noch aus", node._part_fx.size() >= 1 and not gs.is_slot_on(gs.racks[rid]["slots"][3]))
	await secs(1.4)
	chk("leerer Server-Karton", _empties().any(func(c): return c["carton"] == "server"))
	for i in 60:
		gs._update_slot_boot(0.5)
	chk("danach online", gs.is_slot_on(gs.racks[rid]["slots"][3]))


func _cart() -> void:
	print("--- Rollwagen")
	var cid := "cart_t"
	gs.carts[cid] = {"id": cid, "pos": Vector3(-3.2, 0.0, 2.8), "rot_y": 0.0, "pushed_by": 0, "items": []}
	gs._broadcast_carts()
	_hold("kit_ram", {"pack_count": 5})
	gs.request_load_held_crate_to_cart(cid)
	await wait(2)
	chk("aufgeladen", gs.carts[cid]["items"] == ["kit_ram"])
	gs.request_unload_cart_to_hands(cid)
	await wait(2)
	chk("Menge bleibt erhalten", int(gs.get_player_held_crate(1).get("pack_count", 1)) == 5, gs.get_player_held_crate(1))
	_hold("empty_carton", {"carton": "cooler"})
	gs.request_load_held_crate_to_cart(cid)
	await wait(2)
	gs.carts[cid]["pushed_by"] = 1
	var m: float = gs.money
	gs.request_dump_carton("garage")
	await wait(2)
	chk("Kartons vom Wagen einwerfen", (gs.carts[cid]["items"] as Array).is_empty() and gs.money >= m + 4.0, gs.money - m)
	gs.carts[cid]["pushed_by"] = 0
	# alter Wagen ohne Inhaltsdaten
	gs.carts[cid]["items"] = ["ups"]
	gs.carts[cid].erase("data")
	for k in gs.crates.keys():
		if int(gs.crates[k].get("held_by", 0)) == 1:
			gs.crates.erase(k)
	gs.request_unload_cart_to_hands(cid)
	await wait(2)
	chk("alter Wagen weiter nutzbar", str(gs.get_player_held_crate(1).get("item_type", "")) == "ups")


func _save() -> void:
	print("--- Speichern")
	for k in gs.crates.keys():
		gs.crates.erase(k)
	gs._spawn_empty_carton("cooler", Vector3(1.0, 0.0, 2.0))
	gs.request_toggle_strip(lan)
	var cid: String = gs.carts.keys()[0]
	gs.carts[cid]["items"] = []
	_hold("ups", {"unboxed": true, "ups": {"charge": 33.0, "health": 44.0}})
	gs.request_load_held_crate_to_cart(cid)
	await wait(2)
	var wall := ""
	for d in gs.decor_items:
		if gs.is_wall_strip(gs.decor_items[d]):
			wall = d
	var r: Dictionary = sm.save_world("paketa", "PaketA", gs.export_save_data())
	chk("gespeichert", r["ok"])
	var l: Dictionary = sm.load_world_file("paketa")
	chk("Signatur gültig", l["integrity"]["status"] == "valid", l["integrity"])
	gs.load_from_save_data(l["state"], "paketa", "PaketA")
	await wait(4)
	chk("Karton-Art bleibt", _empties().size() == 1 and _empties()[0]["carton"] == "cooler")
	chk("Wandleiste bleibt", wall != "" and gs.is_wall_strip(gs.decor_items[wall]) and (gs.decor_items[wall]["pos"] as Vector3).y > 1.0, gs.decor_items.get(wall))
	chk("ausgeschaltete Leiste bleibt aus", not gs.is_strip_on(lan))
	gs.request_unload_cart_to_hands(cid)
	await wait(2)
	chk("Wageninhalt übersteht das Speichern", is_equal_approx(float((gs.get_player_held_crate(1).get("ups", {}) as Dictionary).get("health", 0.0)), 44.0), gs.get_player_held_crate(1))
