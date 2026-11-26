extends RefCounted
## Racks: Rack- und Einschubdaten, Werte der Server, Einbau und Ausbau von Modulen und Bauteilen,
## Abdeckungen, Server-Schlitten, Defekte, Diagnose, Reparatur, Wartung, Verkauf und Umbenennen.
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


## Vergibt für Racks immer die niedrigste freie Nummer ab 1 (rack_1, rack_2, ...),
## unabhängig davon, wie viele Kisten/Kabel vorher erzeugt wurden.
static func _alloc_rack_id() -> String:
	var n := 1
	while GameState.racks.has("rack_%d" % n):
		n += 1
	return "rack_%d" % n


static func _default_components(server_type: String = "web_server") -> Dictionary:
	# Mainboards kommen nackt: CPU, RAM, GPU, Speicher, Kühlung und Netzteil kauft der Spieler danach selbst.
	if is_mainboard(server_type):
		return HardwareCatalog.make_empty_components()
	return HardwareCatalog.make_default_components(server_type)


static func _make_empty_slot() -> Dictionary:
	return SlotData.make_empty(_default_components())


static func _make_rack_data(rack_id: String, rack_type: String, pos: Vector3, rot_y: float) -> Dictionary:
	var slot_count := int(GameState.ITEM_CATALOG.get(rack_type, {}).get("slots", 4))
	var slots: Array = []
	for _i in range(slot_count):
		slots.append(_make_empty_slot())
	return RackData.make(rack_id, rack_type, pos, rot_y, slots)


static func _ensure_loaded_compat() -> void:
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		RackData.fill_defaults(r)
		# Alte Spielstände hatten genau einen Dienst pro Rack: in die Dienstliste übernehmen.
		if not (r.get("services") is Array):
			var migrated: Array = []
			var old_type := str(r.get("rental_type", "none"))
			if old_type != "none" and HardwareCatalog.RENTAL_PROFILES.has(old_type):
				migrated.append({
					"type": old_type,
					"customer": str(r.get("rental_customer", "")),
					"users": float(r.get("active_users", 0)),
					"trend": 0.0,
				})
			r["services"] = migrated
		var slots: Array = r.get("slots", [])
		for s in slots:
			var sd: Dictionary = s
			var stype := str(sd.get("item_type", ""))
			if not sd.has("components") or not (sd["components"] is Dictionary):
				sd["components"] = _default_components(stype if stype != "" else "web_server")
			else:
				sd["components"] = HardwareCatalog.normalize_components(sd["components"] as Dictionary, stype if stype != "" else "web_server")
	for cid in GameState.coolers.keys():
		var c: Dictionary = GameState.coolers[cid]
		if not c.has("cooler_type"):
			c["cooler_type"] = "cooler"


static func is_slot_upgradeable(item_type: String) -> bool:
	# Die alten Chassis bleiben nur für bestehende Spielstände gültig.
	if item_type == "web_server" or item_type == "storage_server" or item_type == "gpu_server":
		return true
	return is_mainboard(item_type)


static func is_mainboard(item_type: String) -> bool:
	var entry: Dictionary = GameState.ITEM_CATALOG.get(item_type, {})
	return bool(entry.get("mainboard", false))


## Welches 3D-Gehäuse (1U/2U/4U) für einen Einschub gezeigt wird.
static func get_chassis_visual(item_type: String) -> String:
	if is_mainboard(item_type):
		return str(GameState.ITEM_CATALOG[item_type].get("chassis", "web_server"))
	return item_type


## Mainboard-IDs einer Kategorie ("" = alle), aufsteigend nach Preis sortiert.
static func get_mainboards(mb_cat: String = "") -> Array:
	var out: Array = []
	for key in GameState.ITEM_CATALOG:
		var id := str(key)
		if not is_mainboard(id):
			continue
		if mb_cat != "" and str(GameState.ITEM_CATALOG[id].get("mb_cat", "")) != mb_cat:
			continue
		out.append(id)
	out.sort_custom(func(a, b) -> bool: return int(GameState.ITEM_CATALOG[a]["price"]) < int(GameState.ITEM_CATALOG[b]["price"]))
	return out


## Bauqualität eines Einschubs oder Schlittens (0–100). Server aus alten Spielständen haben 100.
static func get_build_quality(data: Dictionary) -> int:
	return clampi(int(roundf(float(data.get("build_quality", 100)))), 0, 100)


static func get_slot_sloppiness(slot: Dictionary) -> float:
	return float(100 - get_build_quality(slot)) / 100.0


static func get_slot_stats(slot: Dictionary) -> Dictionary:
	if GameState._stats_research != GameState.research_levels:
		GameState._stats_research = GameState.research_levels.duplicate()
		GameState._stats_cache.clear()
	var key := [slot.get("item_type", ""), slot.get("build_quality", 100), slot.get("components", {})]
	var hit: Variant = GameState._stats_cache.get(key)
	if hit == null:
		if GameState._stats_cache.size() > 512:
			GameState._stats_cache.clear()
		hit = _compute_slot_stats(slot)
		# Schreibgeschützt statt bei jedem Abruf kopiert: Wer etwas ändern will, nimmt duplicate().
		(hit as Dictionary).make_read_only()
		GameState._stats_cache[key.duplicate(true)] = hit
	return hit


static func _compute_slot_stats(slot: Dictionary) -> Dictionary:
	var item_type := str(slot.get("item_type", ""))
	if item_type == "" or not GameState.ITEM_CATALOG.has(item_type):
		return {
			"compute": 0, "watts": 0, "heat": 0.0, "fault_mult": 1.0,
			"revenue_bonus": 0.0, "total_value": 0,
			"cpu_score": 0, "ram_gb": 0, "gpu_score": 0, "vram_gb": 0,
			"storage_tb": 0.0, "psu_max_watts": 0, "psu_overloaded": false, "ram_tag": "",
			"missing_parts": [], "complete": false,
		}

	var base: Dictionary = GameState.ITEM_CATALOG[item_type]
	var compute := int(base["compute"])
	var watts := float(base["watts"])
	var heat := float(base["heat"])
	var fault_mult := 1.0
	var watt_mult := 1.0
	var total_val := int(base["price"])
	var rev_bonus := float(base.get("revenue_bonus", 0.0))
	var cpu_score := 0
	var ram_gb := 0
	var gpu_score := 0
	var vram_gb := 0
	var storage_tb := 0.0
	var psu_max_watts := 550
	var ram_tag := "DDR3"
	var missing: Array = []

	if is_slot_upgradeable(item_type):
		var raw_comps: Dictionary = slot.get("components", {})
		var comps := HardwareCatalog.normalize_components(raw_comps, item_type)
		# Mainboard-/Chassis-Basis plus alle eingebauten Bauteile
		watts = 65.0
		heat = 2.0
		compute = int(GameState.ITEM_CATALOG[item_type].get("base_compute", 4 if item_type == "web_server" else (6 if item_type == "storage_server" else 10)))
		for cat in HardwareCatalog.CATEGORY_ORDER:
			var part_id := str(comps.get(cat, ""))
			if part_id.is_empty():
				if GameState.REQUIRED_PART_CATS.has(cat):
					missing.append(cat)
				continue
			var pd := HardwareCatalog.get_part(cat, part_id)
			if pd.is_empty():
				continue
			total_val += int(pd.get("cost", 0))
			compute += int(pd.get("compute", 0))
			watts += float(pd.get("watts", 0))
			heat += float(pd.get("heat", 0.0))
			fault_mult *= float(pd.get("fault_mult", 1.0))
			rev_bonus += float(pd.get("revenue_bonus", 0.0))
			if cat == "cpu":
				cpu_score += int(pd.get("cpu_score", 12))
			elif cat == "ram":
				ram_gb += int(pd.get("ram_gb", 2))
				ram_tag = str(pd.get("tag", "DDR3"))
			elif cat == "gpu":
				gpu_score += int(pd.get("gpu_score", 4))
				vram_gb += int(pd.get("vram_gb", 0))
			elif cat == "storage":
				storage_tb += float(pd.get("storage_tb", 0.5))
			elif cat == "psu":
				psu_max_watts = int(pd.get("psu_max_watts", 350))
				watt_mult *= float(pd.get("watt_mult", 1.0))

	# Ohne Pflichtteile startet das Board nicht: keine Rechenleistung, nur Standby-Verbrauch.
	if not missing.is_empty():
		compute = 0
		watts = 10.0
		heat = 0.5
	var psu_overloaded := is_slot_upgradeable(item_type) and not missing.has("psu") and (watts > float(psu_max_watts))
	if psu_overloaded:
		fault_mult *= 2.4
		heat += 4.5

	# Forschung wirkt auf alle Server.
	heat *= GameState.get_research_mult("cooling")
	watt_mult *= GameState.get_research_mult("efficiency")
	fault_mult *= GameState.get_research_mult("reliability")

	# Schlampig gebaute Server laufen wärmer, fallen öfter aus und drosseln.
	var sloppy := get_slot_sloppiness(slot)
	heat *= 1.0 + 0.60 * sloppy
	fault_mult = clampf(fault_mult, 0.15, 3.0) * (1.0 + 2.0 * sloppy)
	var throttle := 1.0 - 0.30 * maxf(0.0, sloppy - 0.15)
	compute = int(roundf(float(compute) * throttle))
	cpu_score = int(roundf(float(cpu_score) * throttle))
	gpu_score = int(roundf(float(gpu_score) * throttle))

	var final_watts := maxi(40, int(roundf(watts * watt_mult)))
	var final_heat := maxf(1.5, heat)
	return {
		"compute": compute,
		"watts": final_watts,
		"heat": final_heat,
		"fault_mult": clampf(fault_mult, 0.15, 6.0),
		"build_quality": get_build_quality(slot),
		"revenue_bonus": rev_bonus,
		"total_value": total_val,
		"cpu_score": cpu_score,
		"ram_gb": ram_gb,
		"gpu_score": gpu_score,
		"vram_gb": vram_gb,
		"storage_tb": storage_tb,
		"psu_max_watts": psu_max_watts,
		"psu_overloaded": psu_overloaded,
		"ram_tag": ram_tag,
		"missing_parts": missing,
		"complete": missing.is_empty(),
	}


static func get_rack_hardware_summary(rack_id: String) -> Dictionary:
	var out := {
		"cpu_score": 0, "ram_gb": 0, "gpu_score": 0, "vram_gb": 0,
		"storage_tb": 0.0, "watts": 0, "compute": 0,
		"active_servers": 0, "total_servers": 0, "psu_overloaded": false,
	}
	if not GameState.racks.has(rack_id):
		return out
	var r: Dictionary = GameState.racks[rack_id]
	var powered := bool(r.get("powered", false))
	var networked := bool(r.get("networked", false))
	for sl in r["slots"]:
		var sd: Dictionary = sl
		var itype := str(sd.get("item_type", ""))
		if itype == "":
			continue
		if is_slot_upgradeable(itype):
			out["total_servers"] = int(out["total_servers"]) + 1
		var st := get_slot_stats(sd)
		if not bool(sd.get("offline", false)):
			out["watts"] = int(out["watts"]) + int(st["watts"])
		if bool(st["psu_overloaded"]):
			out["psu_overloaded"] = true
		if not bool(st.get("complete", true)) and is_slot_upgradeable(itype):
			out["incomplete_servers"] = int(out.get("incomplete_servers", 0)) + 1
		if powered and networked and GameState.is_slot_on(sd) and is_slot_upgradeable(itype) and bool(st.get("complete", true)):
			out["active_servers"] = int(out["active_servers"]) + 1
			out["cpu_score"] = int(out["cpu_score"]) + int(st["cpu_score"])
			out["ram_gb"] = int(out["ram_gb"]) + int(st["ram_gb"])
			out["gpu_score"] = int(out["gpu_score"]) + int(st["gpu_score"])
			out["vram_gb"] = int(out["vram_gb"]) + int(st["vram_gb"])
			out["storage_tb"] = float(out["storage_tb"]) + float(st["storage_tb"])
			out["compute"] = int(out["compute"]) + int(st["compute"])
	return out


static func get_rack_sell_value(rack_id: String) -> int:
	if not GameState.racks.has(rack_id):
		return 0
	var r: Dictionary = GameState.racks[rack_id]
	var rtype := str(r.get("rack_type", "rack"))
	var total := int(GameState.ITEM_CATALOG.get(rtype, {}).get("price", 400))
	for slot in r["slots"]:
		var st := get_slot_stats(slot as Dictionary)
		total += int(st["total_value"])
	return int(roundf(float(total) * GameState.SELL_REFUND_RATIO))


static func get_device_sell_value(kind: String, eid: String) -> int:
	if kind == "cooler" and GameState.coolers.has(eid):
		var ctype := str(GameState.coolers[eid].get("cooler_type", "cooler"))
		return int(roundf(float(GameState.ITEM_CATALOG[ctype]["price"]) * GameState.SELL_REFUND_RATIO))
	if kind == "decor" and GameState.decor_items.has(eid):
		var dtype := str((GameState.decor_items[eid] as Dictionary).get("item_type", ""))
		return int(roundf(float((GameState.ITEM_CATALOG.get(dtype, {}) as Dictionary).get("price", 0)) * GameState.SELL_REFUND_RATIO))
	if kind == "ups" and GameState.ups_units.has(eid):
		return int(roundf(float(GameState.ITEM_CATALOG[GameState.get_ups_type(GameState.ups_units[eid])]["price"]) * GameState.SELL_REFUND_RATIO * (0.5 + 0.5 * GameState.get_ups_health(GameState.ups_units[eid]) / 100.0)))
	if kind == "cart" and GameState.carts.has(eid):
		var total := int(GameState.ITEM_CATALOG["cart"]["price"])
		var c_items: Array = GameState.carts[eid].get("items", [])
		for it in c_items:
			total += int(GameState.ITEM_CATALOG.get(str(it), {}).get("price", 0))
		return int(roundf(float(total) * GameState.SELL_REFUND_RATIO))
	return 0


static func is_shared_panel_open(entity_id: String, panel_id: String) -> bool:
	return GameState.shared_open_panels.has(_panel_key(entity_id, panel_id))


## Für Abfragen jedes Bild: Schlüssel einmal bauen (panel_key) und dann nur noch nachsehen.
static func panel_key(entity_id: String, panel_id: String) -> String:
	return _panel_key(entity_id, panel_id)


static func is_panel_key_open(key: String) -> bool:
	return GameState.shared_open_panels.has(key)


static func _panel_key(entity_id: String, panel_id: String) -> String:
	return entity_id + "|" + panel_id


static func _sanitize_open_panels(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	var src := data as Dictionary
	for k in src.keys():
		if out.size() >= GameState.MAX_SHARED_PANELS:
			break
		var ks := str(k)
		var v: Variant = src[k]
		if ks.length() <= 160 and ks.contains("|") and typeof(v) == TYPE_BOOL and bool(v):
			out[ks] = true
	return out


static func _rpc_req_toggle_panel(entity_id: String, panel_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	if entity_id.length() > 64 or panel_id.length() > 95:
		return
	var key := _panel_key(entity_id, panel_id)
	var opened := not GameState.shared_open_panels.has(key)
	if opened:
		if GameState.shared_open_panels.size() >= GameState.MAX_SHARED_PANELS:
			return
		GameState.shared_open_panels[key] = true
	else:
		GameState.shared_open_panels.erase(key)
	GameState._rpc_sync_panel.rpc(key, opened)
	if panel_id.begins_with("slot_") and GameState.racks.has(entity_id):
		_on_slot_panel_toggled(entity_id, int(panel_id.trim_prefix("slot_")), opened)


static func _on_slot_panel_toggled(rack_id: String, slot_idx: int, opened: bool) -> void:
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot.get("item_type", "")) == "":
		return
	var was_on := GameState.is_slot_on(slot) and bool(GameState.racks[rack_id].get("powered", false))
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	if opened and was_on:
		GameState._rpc_play_sfx.rpc("server_off")


static func _close_slot_panel(rack_id: String, slot_idx: int) -> void:
	var key := _panel_key(rack_id, "slot_%d" % slot_idx)
	if GameState.shared_open_panels.has(key):
		GameState.shared_open_panels.erase(key)
		GameState._rpc_sync_panel.rpc(key, false)


static func _rpc_sync_panel(key: String, opened: bool) -> void:
	if not GameState.multiplayer.is_server():
		if opened:
			GameState.shared_open_panels[key] = true
		else:
			GameState.shared_open_panels.erase(key)
	GameState.panel_states_changed.emit()


## Ausgefallen durch ein defektes Bauteil, das noch niemand in der 3D-Vorschau gefunden hat.
static func is_slot_awaiting_diagnosis(slot: Dictionary) -> bool:
	return str(slot.get("state", "")) == "crashed" \
		and str(slot.get("faulty_part", "")) != "" \
		and not bool(slot.get("diagnosed", false))


## Teil, das man dem Server (Einschub oder Schlitten) als kaputt ansieht. "" = nichts zu sehen.
static func get_visible_fault(data: Dictionary) -> String:
	if str(data.get("state", "")) != "crashed" or bool(data.get("fault_hidden", false)):
		return ""
	return str(data.get("faulty_part", ""))


static func get_component_label(cat: String) -> String:
	# Das Mainboard ist kein austauschbares Bauteil, braucht aber einen Namen für den Hover.
	if cat == "mainboard":
		return GameState.tr("Mainboard")
	return str((GameState.COMPONENT_CATALOG.get(cat, {}) as Dictionary).get("label", cat))


## Wählt zufällig ein eingebautes Bauteil. Switches haben keine sichtbaren Bauteile in der Vorschau.
static func _pick_faulty_part(slot: Dictionary) -> String:
	if get_chassis_visual(str(slot.get("item_type", ""))) == "net_switch":
		return ""
	var comps: Dictionary = slot.get("components", {}) as Dictionary
	var cands: Array[String] = ["mainboard"]
	for cat_v in GameState.COMPONENT_ORDER:
		var cat := str(cat_v)
		# Dieselbe Regel wie beim Modellaufbau, damit der Defekt immer sichtbar ist.
		if HardwareMeshFactory.has_part(comps, cat):
			cands.append(cat)
	if cands.is_empty():
		return ""
	return cands[randi() % cands.size()]


static func _rpc_req_diagnose_slot(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if not is_slot_awaiting_diagnosis(slot):
		return
	slot["diagnosed"] = true
	GameState.post_event_f("%s hat den Defekt gefunden: %s in %s Slot %d. Jetzt das Teil in der 3D-Vorschau anklicken, um es zu reparieren.", [
		NetworkManager.get_player_name(peer_id), get_component_label(str(slot["faulty_part"])),
		get_rack_display_name(rack_id), slot_idx + 1
	], "good")
	GameState._broadcast_racks()


static func _rpc_req_relocate_rack(rack_id: String, pos: Vector3, rot_y: float) -> void:
	if not GameState.multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_vec3(pos) or not SecurityGuard.is_finite_float(rot_y):
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "build"):
		return
	if not GameState.racks.has(rack_id):
		return
	var snapped := Vector3(roundf(pos.x * 2.0) * 0.5, 0.0, roundf(pos.z * 2.0) * 0.5)
	if not GameState.can_place_at(snapped, rack_id):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	GameState._disconnect_all_cables_of(rack_id)
	GameState.racks[rack_id]["pos"] = snapped
	GameState.racks[rack_id]["rot_y"] = rot_y
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_cables()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("place")
	GameState.post_event_f("%s hat %s umgesetzt (Kabel neu anschließen!).", [NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id)], "info")


static func _rpc_req_sell_rack(rack_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 6, 5.0):
		return
	if not GameState.is_destructive_action_allowed(peer_id):
		GameState._deny_destructive_action(peer_id, "Racks verkaufen")
		return
	if not GameState.racks.has(rack_id):
		return
	var refund := get_rack_sell_value(rack_id)
	GameState._disconnect_all_cables_of(rack_id)
	GameState._clear_tickets_for_rack(rack_id)
	if not GameState.active_call.is_empty() and str(GameState.active_call.get("rack_id", "")) == rack_id:
		GameState.active_call.clear()
		GameState._broadcast_call()
	var sold_name := get_rack_display_name(rack_id)
	GameState.racks.erase(rack_id)
	# Offene Türen/Schächte dieses Racks aufräumen, damit ein neues Rack mit derselben ID sauber startet.
	var prefix := rack_id + "|"
	for pkey in GameState.shared_open_panels.keys():
		if str(pkey).begins_with(prefix):
			GameState.shared_open_panels.erase(pkey)
			GameState._rpc_sync_panel.rpc(str(pkey), false)
	GameState.money += float(refund)
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_cables()
	GameState._broadcast_racks()
	GameState._broadcast_tickets()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_crates()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("sell")
	GameState.post_event_f("%s verkaufte %s für +$%d.", [NetworkManager.get_player_name(peer_id), sold_name, refund], "good")


static func _rpc_req_install_module(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	var held := GameState.get_player_held_crate(peer_id)
	if held.is_empty():
		return
	var item_type := str(held["item_type"])
	if str(GameState.ITEM_CATALOG[item_type]["category"]) != "module":
		return
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx]["item_type"]) != "":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var held_mod_cid := str(held["id"])
	var mod_pcount := maxi(1, int(GameState.crates[held_mod_cid].get("pack_count", 1)))
	if mod_pcount > 1:
		GameState.crates[held_mod_cid]["pack_count"] = mod_pcount - 1
	else:
		GameState.crates.erase(held_mod_cid)
		if not bool(held.get("unboxed", false)):
			GameState._spawn_empty_carton("server", GameState._carton_drop_pos(GameState.racks[rack_id]["pos"], float(GameState.racks[rack_id].get("rot_y", 0.0))), 0.6)
			GameState._rpc_play_sfx.rpc("carton_open")
	slots[slot_idx] = {
		"item_type": item_type,
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"offline": true, # fährt nach dem Einbau erst hoch
		"components": _default_components(item_type),
	}
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_crates()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("snap")
	GameState.post_event_f("%s baute %s in %s (Slot %d) ein.", [
		NetworkManager.get_player_name(peer_id),
		GameState.ITEM_CATALOG[item_type]["name"],
		get_rack_display_name(rack_id),
		slot_idx + 1,
	], "good")


static func _rpc_req_remove_module(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState.is_player_holding_anything(peer_id) or not GameState.racks.has(rack_id):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		if GameState.is_player_holding_anything(peer_id):
			GameState.post_event("Hände voll! Erst Item mit [Q] ablegen oder freien Slot (1–4) wählen.", "warn")
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var item_type := str(slots[slot_idx]["item_type"])
	if item_type == "" or str(slots[slot_idx]["state"]) == "burning":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	slots[slot_idx] = _make_empty_slot()
	var cid := GameState._alloc_id("crate")
	GameState.crates[cid] = {"id": cid, "item_type": item_type, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": GameState.get_active_slot(peer_id), "unboxed": true}
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_crates()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc_id(peer_id, "pickup")


static func _rpc_req_sell_slot_module(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "sell", 8, 5.0):
		return
	if not GameState.is_destructive_action_allowed(peer_id):
		GameState._deny_destructive_action(peer_id, "Server-Module verkaufen")
		return
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if item_type == "" or str(slot["state"]) == "burning":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var stats := get_slot_stats(slot)
	var refund := int(roundf(float(stats["total_value"]) * GameState.SELL_REFUND_RATIO))
	slots[slot_idx] = _make_empty_slot()
	GameState.money += float(refund)
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("sell")
	GameState.post_event_f("%s verkaufte Modul aus %s Slot %d für +$%d.", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1, refund
	], "good")


static func _rpc_req_upgrade_slot_component(rack_id: String, slot_idx: int, category: String) -> void:
	# Legacy helper: advances to next part in HardwareCatalog
	if not GameState.multiplayer.is_server() or not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var comps: Dictionary = HardwareCatalog.normalize_components(slot.get("components", {}), str(slot.get("item_type", "web_server")))
	var cur_id := str(comps.get(category, HardwareCatalog.DEFAULT_PARTS.get(category, "")))
	var arr := HardwareCatalog.get_category_parts(category)
	var idx := HardwareCatalog.get_part_index(category, cur_id)
	if idx + 1 < arr.size():
		_rpc_req_install_component(rack_id, slot_idx, category, str((arr[idx + 1] as Dictionary)["id"]))


static func _rpc_req_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not GameState.racks.has(rack_id) or not HardwareCatalog.PARTS.has(category):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if not is_slot_upgradeable(item_type) or str(slot["state"]) == "burning":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var new_part := HardwareCatalog.get_part(category, part_id)
	if new_part.is_empty():
		return
	var comps := HardwareCatalog.normalize_components(slot.get("components", {}), item_type)
	var old_id := str(comps.get(category, ""))
	if old_id == part_id:
		return

	# v1.0 Unified Warehouse Flow: install purchased parts from parts_inventory (stock defaults always free)!
	var is_default := HardwareCatalog.is_stock_default_part(part_id)
	if not is_default:
		var stock := int(GameState.parts_inventory.get(part_id, 0))
		if stock <= 0:
			GameState._rpc_play_sfx.rpc_id(peer_id, "error")
			GameState.post_event_f("%s nicht im Teile-Lager! Erst im PC-Shop bestellen.", [str(new_part["name"])], "warn")
			return
		GameState.parts_inventory[part_id] = stock - 1
		if int(GameState.parts_inventory[part_id]) <= 0:
			GameState.parts_inventory.erase(part_id)

	# Return old swapped-out non-default component neatly back into the Parts Warehouse!
	if old_id != "" and not HardwareCatalog.is_stock_default_part(old_id):
		GameState.parts_inventory[old_id] = int(GameState.parts_inventory.get(old_id, 0)) + 1

	comps[category] = part_id
	slot["components"] = comps
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_inventory()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("upgrade")
	GameState.post_event_f("%s baute %s aus dem Lager in %s Slot %d ein!", [
		NetworkManager.get_player_name(peer_id), str(new_part["name"]), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


static func _rpc_req_buy_install_component(rack_id: String, slot_idx: int, category: String, part_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "buy"):
		return
	if not GameState.racks.has(rack_id) or not HardwareCatalog.PARTS.has(category):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var item_type := str(slot["item_type"])
	if not is_slot_upgradeable(item_type) or str(slot["state"]) == "burning":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var new_part := HardwareCatalog.get_part(category, part_id)
	if new_part.is_empty():
		return
	var cost := float(new_part.get("cost", 0))
	if cost <= 0.0 or GameState.money < cost or not GameState.is_part_unlocked(new_part):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var comps := HardwareCatalog.normalize_components(slot.get("components", {}), item_type)
	if str(comps.get(category, "")) == part_id:
		return

	# Teil direkt ins Lager buchen und sofort über den normalen Einbau-Weg verbauen.
	GameState.money -= cost
	GameState.parts_inventory[part_id] = int(GameState.parts_inventory.get(part_id, 0)) + 1
	_rpc_req_install_component(rack_id, slot_idx, category, part_id)
	GameState._rpc_play_sfx.rpc("cash")


static func _rpc_req_buy_install_module(rack_id: String, slot_idx: int, item_type: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "buy"):
		return
	if not GameState.racks.has(rack_id) or not GameState.ITEM_CATALOG.has(item_type):
		return
	if str(GameState.ITEM_CATALOG[item_type]["category"]) != "module":
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx]["item_type"]) != "":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var cost := float(GameState.ITEM_CATALOG[item_type]["price"])
	if GameState.money < cost or not GameState.is_item_unlocked(item_type):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	GameState.money -= cost
	slots[slot_idx] = {
		"item_type": item_type,
		"state": "ok",
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"components": _default_components(item_type),
	}
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")
	GameState._rpc_play_sfx.rpc("snap")
	GameState.post_event_f("%s kaufte %s und baute es in %s (Slot %d) ein.", [
		NetworkManager.get_player_name(peer_id),
		GameState.ITEM_CATALOG[item_type]["name"],
		get_rack_display_name(rack_id),
		slot_idx + 1,
	], "good")


## Anzeigename eines Racks: eigener Name oder „Rack N“ (ohne interne Debug-IDs).
static func get_rack_display_name(rack_id: String) -> String:
	var shown := ""
	if GameState.racks.has(rack_id):
		shown = RackData.of(GameState.racks[rack_id]).custom_name
	if shown.is_empty():
		var num := rack_id.get_slice("_", rack_id.get_slice_count("_") - 1)
		shown = ("Rack %s" % num) if num.is_valid_int() else rack_id
	return shown


## Entfernt Steuerzeichen und kürzt auf RACK_NAME_MAX_LEN.
static func _sanitize_rack_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.strip_edges().left(GameState.RACK_NAME_MAX_LEN)


static func _rpc_req_rename_rack(rack_id: String, new_name: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	if not GameState.racks.has(rack_id):
		return
	var peer_id := GameState._get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "rename", 6, 10.0):
		return
	var r: Dictionary = GameState.racks[rack_id]
	var filtered := SecurityGuard.sanitize_label(new_name, GameState.RACK_NAME_MAX_LEN, "")
	if not new_name.strip_edges().is_empty() and filtered.is_empty():
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var clean := _sanitize_rack_name(filtered.left(GameState.RACK_NAME_MAX_LEN * 4))
	if clean == str(r.get("custom_name", "")):
		return
	var old_name := get_rack_display_name(rack_id)
	r["custom_name"] = clean
	GameState._broadcast_racks()
	GameState.post_event_f("%s hat %s in %s umbenannt.", [NetworkManager.get_player_name(peer_id), old_name, get_rack_display_name(rack_id)], "info")


static func _rpc_req_repair_slot(rack_id: String, slot_idx: int, amount: float) -> void:
	if not GameState.multiplayer.is_server():
		return
	if not SecurityGuard.is_finite_float(amount):
		return
	var peer_id := GameState._get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "repair", 25, 2.0):
		return
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot["state"]) != "crashed":
		return
	# Erst das defekte Teil finden, dann reparieren.
	if is_slot_awaiting_diagnosis(slot):
		return
	var speed_mult := get_repair_speed_multiplier()
	var used_kit := false
	if GameState.maint_kits > 0 and float(slot["repair_progress"]) <= 0.001:
		GameState.maint_kits -= 1
		used_kit = true
	if used_kit or bool(slot.get("_using_kit", false)):
		slot["_using_kit"] = true
		speed_mult *= 2.2
	slot["repair_progress"] = minf(1.0, float(slot["repair_progress"]) + clampf(amount * speed_mult, 0.0, 1.0))
	if float(slot["repair_progress"]) >= 1.0:
		var full_ok := bool(slot.get("_using_kit", false))
		slot["state"] = "ok"
		slot["offline"] = true # nach der Reparatur neu hochfahren
		slot["repair_progress"] = 0.0
		slot["faulty_part"] = ""
		slot["diagnosed"] = false
		slot.erase("_using_kit")
		slot["dust_level"] = 0.0 if full_ok else 35.0
		slot["thermal_health"] = 100.0 if full_ok else 72.0
		# Schnell geflickt ist nicht ordentlich repariert: volle Qualität gibt es nur an der Werkbank.
		slot["build_quality"] = mini(get_build_quality(slot), GameState.RACK_REPAIR_QUALITY_KIT if full_ok else GameState.RACK_REPAIR_QUALITY)
		GameState._recalculate_networks_and_metrics()
		GameState._broadcast_sim_tick()
		var diag_str := GameState.tr("notdürftig mit Ersatzteil-Kit (Bauqualität höchstens 70 %)") if full_ok else GameState.tr("notdürftig (Bauqualität höchstens 50 %)")
		GameState.post_event_f("%s hat %s Slot %d %s repariert!", [
			NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1, diag_str
		], "good")
		GameState._rpc_play_sfx.rpc("repair")
	GameState._broadcast_racks()


static func calculate_slot_build_price(mainboard_id: String, comps: Dictionary) -> int:
	if not GameState.ITEM_CATALOG.has(mainboard_id):
		return 0
	var total := int(GameState.ITEM_CATALOG[mainboard_id].get("price", 0))
	for cat_v in GameState.COMPONENT_ORDER:
		var cat := str(cat_v)
		var pid := str(comps.get(cat, ""))
		if pid.is_empty():
			continue
		var pd := HardwareCatalog.get_part(cat, pid)
		if not pd.is_empty():
			total += maxi(0, int(pd.get("cost", 0)))
	return total


static func is_slot_extended(rack_id: String, slot_idx: int) -> bool:
	return is_shared_panel_open(rack_id, "slot_%d" % slot_idx)


static func _rpc_req_pull_server_tray(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState.is_player_holding_anything(peer_id) or not GameState.racks.has(rack_id):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		if GameState.is_player_holding_anything(peer_id):
			GameState.post_event("Hände voll! Erst Item mit [Q] ablegen oder freien Slot (1–4) wählen.", "warn")
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	var itype := str(slot.get("item_type", ""))
	if itype == "" or str(slot.get("state", "")) == "burning":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var rlabel := get_rack_display_name(rack_id)
	_tray_from_slot(rack_id, slot_idx, slot, peer_id)
	slots[slot_idx] = _make_empty_slot()
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_crates()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc_id(peer_id, "pickup")
	GameState.post_event_f("🔧 %s hat den Server-Schlitten aus %s · Slot %d herausgezogen.", [
		NetworkManager.get_player_name(peer_id), rlabel, slot_idx + 1
	], "info")


## Server aus dem Einschub als Schlitten in die Hand nehmen; liefert die Kisten-ID.
static func _tray_from_slot(rack_id: String, slot_idx: int, slot: Dictionary, peer_id: int) -> String:
	var rlabel := get_rack_display_name(rack_id)
	var itype := str(slot.get("item_type", ""))
	var st := str(slot.get("state", "ok"))
	var cid := GameState._alloc_id("crate")
	GameState.crates[cid] = {
		"id": cid,
		"item_type": "server_tray",
		"pos": Vector3.ZERO,
		"held_by": peer_id,
		"held_slot": GameState.get_active_slot(peer_id),
		"label": "%s · Slot %d (%s)" % [rlabel, slot_idx + 1, "DEFEKT" if st == "crashed" else "OK"],
		"tray_data": {
			"mainboard_id": itype,
			"components": (slot.get("components", {}) as Dictionary).duplicate(true),
			"state": st,
			"faulty_part": str(slot.get("faulty_part", "")),
			"diagnosed": bool(slot.get("diagnosed", false)),
			"fault_hidden": bool(slot.get("fault_hidden", false)),
			"build_quality": get_build_quality(slot),
			"source_rack_id": rack_id,
			"source_slot_idx": slot_idx,
		},
	}
	return cid


static func _rpc_req_insert_server_tray(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	var held := GameState.get_player_held_crate(peer_id)
	if held.is_empty() or str(held.get("item_type", "")) != "server_tray":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if str(slots[slot_idx].get("item_type", "")) != "":
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	slots[slot_idx] = _slot_from_tray(held.get("tray_data", {}) as Dictionary)
	GameState.crates.erase(str(held["id"]))
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_crates()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("snap")
	GameState.post_event_f("✅ %s hat den Server in %s · Slot %d eingesetzt!", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


static func _slot_from_tray(td: Dictionary) -> Dictionary:
	var mb_id := str(td.get("mainboard_id", "web_server"))
	if not GameState.ITEM_CATALOG.has(mb_id):
		mb_id = "web_server"
	var st := str(td.get("state", "ok"))
	return {
		"item_type": mb_id,
		"state": st,
		"faulty_part": str(td.get("faulty_part", "")) if st == "crashed" else "",
		"diagnosed": bool(td.get("diagnosed", false)) if st == "crashed" else false,
		"fault_hidden": bool(td.get("fault_hidden", false)) if st == "crashed" else false,
		"build_quality": get_build_quality(td),
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"offline": true, # fährt nach dem Einschieben erst hoch
		"components": (td.get("components", _default_components(mb_id)) as Dictionary).duplicate(true),
	}


static func get_repair_speed_multiplier() -> float:
	var mult := 1.0
	for did in GameState.decor_items.keys():
		if str((GameState.decor_items[did] as Dictionary).get("item_type", "")) == "prop_esd_workbench":
			mult = 1.35
			break
	return mult


static func get_fault_diagnosis_info(slot: Dictionary) -> Dictionary:
	var part := str(slot.get("faulty_part", ""))
	if GameState.FAULT_DIAGNOSIS_META.has(part):
		return GameState.FAULT_DIAGNOSIS_META[part] as Dictionary
	return {"code": "ERR-GEN-01", "cause": "Allgemeine Hardware-Störung", "tool": "Wartungs-Kit"}


static func get_maintenance_warnings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in GameState.racks.keys():
		var rack: Dictionary = GameState.racks[rid]
		var slots: Array = rack.get("slots", [])
		for i in range(slots.size()):
			var sl: Dictionary = slots[i]
			if str(sl.get("item_type", "")) == "":
				continue
			var dust := float(sl.get("dust_level", 0.0))
			var th_hp := float(sl.get("thermal_health", 100.0))
			if str(sl.get("state", "ok")) != "ok" or dust >= 65.0 or th_hp <= 35.0:
				out.append({
					"rack_id": rid,
					"rack_name": get_rack_display_name(rid),
					"slot_idx": i,
					"state": str(sl.get("state", "ok")),
					"dust": int(roundf(dust)),
					"health": int(roundf(th_hp)),
				})
	return out


## Wartung lohnt sich erst ab sichtbarem Staub bzw. gealterter Wärmeleitpaste.
static func is_slot_maintainable(slot: Dictionary) -> bool:
	return roundf(float(slot.get("dust_level", 0.0))) >= GameState.MAINTAIN_MIN_DUST \
		or roundf(float(slot.get("thermal_health", 100.0))) <= GameState.MAINTAIN_MAX_THERMAL


static func _rpc_req_maintain_slot(rack_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not SecurityGuard.check_rate_limit(peer_id, "maintain", 10, 5.0):
		return
	if not GameState.racks.has(rack_id):
		return
	var slots: Array = GameState.racks[rack_id]["slots"]
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var slot: Dictionary = slots[slot_idx]
	if str(slot.get("item_type", "")) == "" or str(slot.get("state", "ok")) != "ok":
		return
	if not is_slot_maintainable(slot):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if GameState.maint_kits <= 0:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Keine Wartungs-Kits mehr! Am PC im Shop oder am Ersatzteil-Schrank auffüllen.", "warn")
		return
	GameState.maint_kits -= 1
	slot["dust_level"] = 0.0
	slot["thermal_health"] = 100.0
	GameState.racks[rack_id]["temp"] = maxf(22.0, float(GameState.racks[rack_id].get("temp", 35.0)) - 3.0)
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("repair")
	GameState.post_event_f("🧹 %s hat %s Slot %d gewartet (Staub 0 %%, Wärmeleitpaste 100 %% — Ausfallrisiko minimal!).", [
		NetworkManager.get_player_name(peer_id), get_rack_display_name(rack_id), slot_idx + 1
	], "good")


static func _rpc_req_refill_maint_kits() -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState.maint_kits >= 12:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var has_cabinet := false
	for did in GameState.decor_items.keys():
		if str((GameState.decor_items[did] as Dictionary).get("item_type", "")) == "prop_parts_cabinet":
			has_cabinet = true
			break
	var cost := 20.0 if has_cabinet else 45.0
	if GameState.money < cost:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= cost
	GameState.maint_kits = mini(12, GameState.maint_kits + 3)
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("snap")
	GameState.post_event_f("🧰 +3 Wartungs- & Ersatzteil-Kits aufgefüllt (Vorrat: %d, Kosten: $%d).", [GameState.maint_kits, int(cost)], "good")
