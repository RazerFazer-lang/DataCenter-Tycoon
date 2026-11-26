extends RefCounted
## Einkauf und Lieferung: Warenkorb, Kasse, Tagesangebote, Lieferfenster, Packen der Kisten,
## Fahrt, Abladen und Unterschrift des Lieferfahrzeugs, Lieferzone und Lieferort.
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


static func get_delivery_fee(tier: int, express: bool = false) -> int:
	var base := int(GameState.DELIVERY_FEES.get(clampi(tier, 1, 3), 15))
	return base + (GameState.DELIVERY_EXPRESS_SURCHARGE if express else 0)


static func get_next_delivery_slot() -> Dictionary:
	var cur_h := GameState.time_of_day * 24.0
	for h in GameState.DELIVERY_SLOTS_HOURS:
		if float(h) > cur_h + 0.12:
			return {"day": GameState.day_number, "hour": h, "tomorrow": false}
	return {"day": GameState.day_number + 1, "hour": GameState.DELIVERY_SLOTS_HOURS[0], "tomorrow": true}


static func get_next_delivery_slot_label() -> String:
	var s := get_next_delivery_slot()
	if bool(s["tomorrow"]):
		return "Morgen %02d:00 Uhr" % int(s["hour"])
	return "%02d:00 Uhr" % int(s["hour"])


static func get_scheduled_delivery_label() -> String:
	if GameState.pending_delivery_express:
		return "Sofort-Express"
	if GameState.scheduled_delivery_hour < 0:
		return get_next_delivery_slot_label()
	if GameState.scheduled_delivery_day > GameState.day_number:
		return "Morgen %02d:00 Uhr" % GameState.scheduled_delivery_hour
	return "%02d:00 Uhr" % GameState.scheduled_delivery_hour


static func _is_delivery_window_due() -> bool:
	if GameState.pending_delivery_express:
		return true
	if GameState.scheduled_delivery_hour < 0:
		return true
	if GameState.day_number > GameState.scheduled_delivery_day:
		return true
	return GameState.day_number == GameState.scheduled_delivery_day and (GameState.time_of_day * 24.0) >= float(GameState.scheduled_delivery_hour)


static func _update_delivery_van(delta: float) -> void:
	match GameState.van_phase:
		"idle":
			if not GameState.pending_delivery_items.is_empty() and _is_delivery_window_due():
				GameState.van_cargo = _pack_van_cargo(GameState.pending_delivery_items)
				GameState.pending_delivery_items.clear()
				GameState.pending_delivery_express = false
				GameState.scheduled_delivery_hour = -1
				GameState.scheduled_delivery_day = 0
				_start_delivery_van()
		"arriving":
			GameState.van_phase_time += delta
			if GameState.van_phase_time >= GameState.VAN_ARRIVE_DURATION:
				_begin_unloading()
		"unloading":
			GameState.van_phase_time += delta
			GameState.van_trip_time += delta
			_update_van_trip()
		"departing":
			GameState.van_phase_time += delta
			if GameState.van_phase_time >= GameState.VAN_DEPART_DURATION:
				GameState.van_phase = "idle"
				GameState.van_phase_time = 0.0
				_reset_van_trip()
				_broadcast_van_state()


## Das Fahrzeug fährt los (van_cargo ist schon gepackt).
static func _start_delivery_van() -> void:
	_reset_van_trip()
	GameState.van_site = "halle_nord" if GameState.halle_nord_owned and GameState.delivery_target_site == "halle_nord" else "garage"
	GameState.van_delivery_tier = compute_delivery_tier(GameState.van_cargo)
	GameState.van_phase = "arriving"
	GameState.van_phase_time = 0.0
	GameState._van_unload_accum = 0.0
	if GameState.van_site == "garage":
		GameState.set_garage_door_open_server(true)
	_clear_van_bay()
	_broadcast_van_state()


## Kisten, die genau da stehen, wo gleich das Fahrzeug parkt, rücken zur Seite.
static func _clear_van_bay() -> void:
	var o := DeliveryPlan.offset(GameState.van_site)
	var moved := false
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if int(c.get("held_by", 0)) != 0:
			continue
		var p: Vector3 = (c["pos"] as Vector3) - o
		if absf(p.x) > 1.75 or p.z < DeliveryPlan.clear_z(GameState.van_delivery_tier) or p.z > 16.0:
			continue
		c["held_by"] = -1
		var sp := DeliveryPlan.assign(DeliveryPlan.survey(GameState.van_site), c, DeliveryPlan.spot_limit(GameState.van_delivery_tier))
		c["held_by"] = 0
		_apply_spot(c, sp, GameState.van_site)
		moved = true
	for cid in GameState.carts.keys():
		var ct: Dictionary = GameState.carts[cid]
		var cp: Vector3 = (ct["pos"] as Vector3) - o
		if int(ct.get("pushed_by", 0)) == 0 and absf(cp.x) < 1.9 and cp.z > DeliveryPlan.clear_z(GameState.van_delivery_tier) and cp.z < 16.0:
			var ds := DeliveryPlan.assign(DeliveryPlan.survey(GameState.van_site), {"item_type": "cart"})
			ct["pos"] = (ds["pos"] as Vector3) + o
			GameState._broadcast_carts()
	if moved:
		GameState._broadcast_crates()


static func _apply_spot(c: Dictionary, sp: Dictionary, site: String) -> void:
	c["pos"] = (sp["pos"] as Vector3) + DeliveryPlan.offset(site)
	c.erase("stk")
	c.erase("pal")
	if str(sp.get("stk", "")) != "":
		c["stk"] = str(sp["stk"])
	if bool(sp.get("pal", false)):
		c["pal"] = true


static func _begin_unloading() -> void:
	_clear_van_bay()
	GameState.van_phase = "unloading"
	GameState.van_phase_time = 0.0
	GameState.van_trip_phase = "work"
	GameState.van_trip_time = 0.0
	GameState.van_trip_total = GameState.van_cargo.size()
	GameState.van_trip_done = 0
	GameState._van_drop_i = 0
	GameState.van_plan = DeliveryPlan.build(GameState.van_site, GameState.van_delivery_tier, GameState.van_cargo)
	for e in GameState.van_plan["items"]:
		var it := str((e as Dictionary)["it"])
		if it.begins_with("build:"):
			var bd: Dictionary = GameState.pending_build_orders.get(it.substr(6), {})
			e["label"] = "%s · Slot %d" % [str(bd.get("rack_label", "Rack")), int(bd.get("slot_idx", 0)) + 1]
	GameState._rpc_sync_van_plan.rpc(GameState.van_plan)
	GameState._rpc_play_sfx.rpc("van_horn")
	var tmeta: Dictionary = GameState.DELIVERY_TIER_META.get(GameState.van_delivery_tier, GameState.DELIVERY_TIER_META[1])
	GameState.post_event_f("%s %s ist angekommen (%d Pakete · %s)!", [
		str(tmeta["icon"]), str(tmeta["name"]), GameState.van_trip_total, str(tmeta["method"])
	], "good")
	_broadcast_van_state()


static func _rpc_sync_van_plan(plan: Dictionary) -> void:
	GameState.van_plan = plan.duplicate(true)


## Abladen läuft nach Plan. Danach wartet der Fahrer auf die Unterschrift und steigt wieder ein.
static func _update_van_trip() -> void:
	match GameState.van_trip_phase:
		"work":
			var drops: Array = GameState.van_plan.get("drops", [])
			var dropped := false
			while GameState._van_drop_i < drops.size() and GameState.van_phase_time >= float(drops[GameState._van_drop_i][0]):
				_drop_planned(int(drops[GameState._van_drop_i][1]))
				GameState._van_drop_i += 1
				dropped = true
			if dropped:
				_broadcast_van_state()
			if GameState._van_drop_i >= drops.size() and GameState.van_phase_time >= float(GameState.van_plan.get("end", 0.0)):
				_set_van_trip("sign")
		"sign":
			if GameState.van_trip_time >= GameState.VAN_SIGN_TIME:
				GameState.post_event("📝 Niemand da zum Unterschreiben: Der Fahrer hat die Lieferung abgestellt.", "info")
				_set_van_trip("enter")
		"enter":
			if GameState.van_trip_time >= GameState.VAN_ENTER_TIME:
				GameState.van_phase = "departing"
				GameState.van_phase_time = 0.0
				GameState.van_trip_phase = ""
				MailManager.on_delivery_done(GameState.van_trip_total)
				_broadcast_van_state()
		_:
			_begin_unloading()


static func _set_van_trip(step: String) -> void:
	GameState.van_trip_phase = step
	GameState.van_trip_time = 0.0
	_broadcast_van_state()


static func _drop_planned(idx: int) -> void:
	var items: Array = GameState.van_plan.get("items", [])
	if idx < 0 or idx >= items.size():
		return
	var e: Dictionary = items[idx]
	var item := str(e["it"])
	GameState.van_cargo.erase(item)
	GameState.van_trip_done += 1
	if item == GameState.VAN_PARCEL_ITEM:
		_deliver_parts_parcel()
		return
	GameState._van_spot = e if _spot_still_free(e) else {}
	_deliver_item_to_zone(item)
	GameState._van_spot = {}


## Hat inzwischen jemand etwas auf den geplanten Platz gestellt?
static func _spot_still_free(e: Dictionary) -> bool:
	if str(e.get("cls", "")) == "cart" or str(e.get("stk", "")) != "":
		return true
	var p: Vector3 = (e["pos"] as Vector3) + DeliveryPlan.offset(GameState.van_site)
	for c in GameState.crates.values():
		var cp: Vector3 = (c as Dictionary)["pos"]
		if int((c as Dictionary).get("held_by", 0)) == 0 and Vector2(cp.x - p.x, cp.z - p.z).length() < 0.42:
			return false
	return true


static func _rpc_sign_delivery() -> void:
	if not GameState.multiplayer.is_server() or GameState.van_phase != "unloading" or GameState.van_trip_phase != "sign":
		return
	var peer_id := GameState._get_sender_id()
	GameState.reputation = minf(100.0, GameState.reputation + GameState.VAN_SIGN_REPUTATION)
	FinanceManager.credit_public(GameState.VAN_SIGN_TIP, "Lieferbonus")
	GameState._rpc_play_sfx.rpc("sign_pen")
	GameState.post_event_f("📝 %s hat die Lieferung unterschrieben. Alles da! (+$%d, etwas mehr Ruf)", [NetworkManager.get_player_name(peer_id), int(GameState.VAN_SIGN_TIP)], "good")
	_set_van_trip("enter")
	GameState._broadcast_sim_tick()


static func _reset_van_trip() -> void:
	GameState.van_trip_phase = ""
	GameState.van_trip_time = 0.0
	GameState.van_trip_done = 0
	GameState.van_trip_total = 0
	GameState._van_drop_i = 0
	GameState.van_plan = {}


## Welche Artikel bei Mehrfachbestellung automatisch in Mengen-Kisten (bis 6 Stück/Kiste) gebündelt werden.
static func is_bulk_packable(item_type: String) -> bool:
	if GameState.is_repair_kit(item_type):
		return true
	return item_type == "web_server" or item_type == "storage_server" or item_type == "gpu_server" or item_type == "net_switch" or item_type == GameState.INDOOR_UNIT_TYPE or GameState.is_strip_type(item_type)


static func is_heavy_delivery_item(item_type: String) -> bool:
	var base := item_type
	if base.begins_with("bulk:"):
		var parts := base.split(":")
		if parts.size() >= 2:
			base = parts[1]
	return base == "rack" or base == "rack_pro" or GameState.is_ups_type(base) or base == "cart" or GameState.is_heat_pump_type(base) or GameState.is_floor_cooler_type(base)


## Berechnet die Liefer-Kategorie (1 = Lieferwagen, 2 = Kastenwagen 7,5t, 3 = Schwerlast-LKW 18t).
static func compute_delivery_tier(packed_cargo: Array) -> int:
	var total := 0
	var heavy := 0
	for entry in packed_cargo:
		var s := str(entry)
		if s == GameState.VAN_PARCEL_ITEM:
			total += 1
			continue
		total += 1
		if is_heavy_delivery_item(s):
			heavy += 1
	if total >= 10 or heavy >= 4:
		return 3
	if total >= 5 or heavy >= 2:
		return 2
	return 1


## Fasst Bauteile/Zubehör ins Sammelpaket UND bündelt gleiche Mengen-Artikel (Kits, Module) in bis zu 6er-Kisten.
static func _pack_items_preview(items: Array, out_parcels: Array = []) -> Array:
	var physical: Array = []
	var bulk_counts: Dictionary = {}
	var bulk_order: Array[String] = []
	var has_parcel := false
	for entry in items:
		var s := str(entry)
		if s.begins_with("part:"):
			has_parcel = true
			out_parcels.append(s.substr(5))
		elif s.begins_with("acc:"):
			has_parcel = true
			out_parcels.append(s)
		elif s == GameState.VAN_PARCEL_ITEM:
			continue
		elif s.begins_with("bulk:"):
			physical.append(s)
		elif is_bulk_packable(s):
			if not bulk_counts.has(s):
				bulk_counts[s] = 0
				bulk_order.append(s)
			bulk_counts[s] = int(bulk_counts[s]) + 1
		else:
			physical.append(s)
	for btype in bulk_order:
		var rem := int(bulk_counts[btype])
		while rem > 0:
			var chunk := mini(rem, GameState.BULK_PACK_MAX)
			if chunk > 1:
				physical.append("bulk:%s:%d" % [btype, chunk])
			else:
				physical.append(btype)
			rem -= chunk
	if has_parcel:
		physical.push_front(GameState.VAN_PARCEL_ITEM)
	return physical


static func _pack_van_cargo(items: Array) -> Array:
	GameState._van_parcel_parts.clear()
	return _pack_items_preview(items, GameState._van_parcel_parts)


## Lieferzone des gewählten Standorts (Garage oder Halle Nord).
static func is_pos_in_delivery_zone(pos: Vector3) -> bool:
	var p := pos - DeliveryPlan.offset("halle_nord" if GameState.halle_nord_owned and GameState.delivery_target_site == "halle_nord" else "garage")
	return p.z >= 4.4 and p.z <= 9.2 and absf(p.x) <= 3.4


static func get_delivery_zone_ground_crates() -> int:
	var n := 0
	for c in GameState.crates.values():
		var cd: Dictionary = c as Dictionary
		if int(cd.get("held_by", 0)) == 0 and is_pos_in_delivery_zone(cd.get("pos", Vector3.ZERO) as Vector3):
			n += 1
	for ct in GameState.carts.values():
		var ctd: Dictionary = ct as Dictionary
		if int(ctd.get("pushed_by", 0)) == 0 and is_pos_in_delivery_zone(ctd.get("pos", Vector3.ZERO) as Vector3):
			n += 1
	return n


static func get_incoming_delivery_crates() -> int:
	if GameState.multiplayer.is_server():
		var n := 0
		for e in GameState.van_cargo:
			if str(e) != GameState.VAN_PARCEL_ITEM:
				n += 1
		var pend_packed := _pack_items_preview(GameState.pending_delivery_items)
		for e in pend_packed:
			if str(e) != GameState.VAN_PARCEL_ITEM:
				n += 1
		return maxi(0, n)
	return maxi(0, GameState.van_cargo_count + GameState.pending_delivery_count)


static func get_delivery_zone_used_slots() -> int:
	return get_delivery_zone_ground_crates() + get_incoming_delivery_crates()


static func get_delivery_zone_free_slots() -> int:
	return maxi(0, get_max_delivery_slots() - get_delivery_zone_used_slots())


static func get_max_delivery_slots() -> int:
	var lvl_b: Dictionary = GameState.COMPANY_LEVEL_BENEFITS.get(GameState.get_company_level(), {})
	var extra := int(lvl_b.get("delivery_bonus", 0))
	return GameState.DELIVERY_ZONE_MAX_CRATES + extra + (GameState.career_completed.size() * 2)


## Berechnet für den Warenkorb: {"crates": physische Kisten, "tier": 1..3, "packed": Array}.
static func preview_cart_delivery(entries: Array) -> Dictionary:
	var raw_items: Array = []
	for raw in entries:
		var e: Dictionary = raw
		var kind := str(e.get("kind", "item"))
		var qty := clampi(int(e.get("qty", 1)), 1, 24)
		if kind == "item":
			var itype := str(e.get("id", ""))
			if itype == "kit_bundle_all":
				for _q in range(qty):
					for kid in GameState.REPAIR_KIT_ORDER:
						raw_items.append(kid)
			elif GameState.ITEM_CATALOG.has(itype):
				for _q in range(qty):
					raw_items.append(itype)
		elif kind == "slot_build":
			raw_items.append("slot_build_box")
		elif kind == "part":
			raw_items.append("part:" + str(e.get("id", "")))
		elif kind == "acc":
			raw_items.append("acc:" + str(e.get("id", "")))
	var packed := _pack_items_preview(raw_items)
	var physical_crates := 0
	for p in packed:
		if str(p) != GameState.VAN_PARCEL_ITEM:
			physical_crates += 1
	return {
		"crates": physical_crates,
		"total_packages": packed.size(),
		"tier": compute_delivery_tier(packed),
		"packed": packed,
	}


static func _deliver_parts_parcel() -> void:
	if GameState._van_parcel_parts.is_empty():
		return
	var n_parts := 0
	var n_fuses := 0
	var n_crates := 0
	var n_power := 0
	var n_bench := 0
	for pid_v in GameState._van_parcel_parts:
		var pid := str(pid_v)
		match pid:
			"acc:fuse":
				GameState.fuse_stock += 1
				n_fuses += 1
			"acc:power_strip", "acc:net_hub":
				# Vor v2.6 bestelltes Zubehör kommt als echte Leiste.
				GameState._spawn_crate_internal("prop_power_strip" if pid == "acc:power_strip" else "prop_lan_strip")
				n_crates += 1
			"acc:tool_akku", "acc:tool_torque", "acc:tool_paste_gun", "acc:tool_meter_pro", "acc:tool_rcd":
				var tid := pid.substr(9)
				if GameState.has_bench_tool(tid):
					GameState.money += float(GameState.BENCH_TOOLS[tid]["price"])
				else:
					GameState.bench_tools[tid] = true
					GameState._rpc_sync_bench_tools.rpc(GameState.bench_tools)
					GameState.post_event_f("📦 Neues Werkzeug an der Werkbank: %s.", [str(GameState.BENCH_TOOLS[tid]["name"])], "good")
			"acc:screw_box":
				GameState.bench_screws = mini(GameState.BENCH_SCREWS_MAX, GameState.bench_screws + GameState.SCREW_BOX_COUNT)
				n_bench += 1
			"acc:paste_tube":
				GameState.bench_paste = minf(GameState.BENCH_PASTE_MAX, GameState.bench_paste + GameState.PASTE_TUBE_USES)
				n_bench += 1
			"acc:power_fuse":
				if GameState.power_fuse_stock == 0:
					GameState.power_fuse_stock = 1
					n_power += 1
			_:
				if pid.begins_with("acc:"):
					continue
				GameState.parts_inventory[pid] = int(GameState.parts_inventory.get(pid, 0)) + 1
				n_parts += 1
	GameState._van_parcel_parts.clear()
	GameState._rpc_play_sfx.rpc("pickup")
	if n_parts > 0:
		GameState._broadcast_inventory()
		GameState.post_event_f("📦 %d Hardware-Bauteil(e) ins Teile-Lager geliefert! Jetzt am Rack einbauen [E].", [n_parts], "good")
	if n_bench > 0:
		GameState._rpc_sync_bench_supplies.rpc(GameState.bench_screws, GameState.bench_paste)
		GameState.post_event_f("📦 %d× Werkbank-Material geliefert (Schrauben: %d, Wärmeleitpaste: %.0f Anwendungen).", [n_bench, GameState.bench_screws, GameState.bench_paste], "good")
	if n_fuses > 0 or n_power > 0:
		GameState._broadcast_fuses()
	if n_fuses > 0:
		GameState.post_event_f("📦 %d Sicherung(en) geliefert. Am Sicherungskasten mit [E] einsetzen.", [n_fuses], "good")
	if n_power > 0:
		GameState.post_event("📦 Drehsicherung geliefert. Am Sicherungskasten mit [E] in Steckplatz F2 einsetzen.", "good")
	if n_crates > 0:
		GameState._broadcast_crates()
	GameState._broadcast_sim_tick()


static func _deliver_item_to_zone(item_type: String) -> void:
	if item_type == "cart":
		var cid := GameState._alloc_id("cart")
		var csite := GameState.van_site if GameState.van_phase == "unloading" else GameState.delivery_target_site
		var csp: Dictionary = GameState._van_spot if not GameState._van_spot.is_empty() else DeliveryPlan.assign(DeliveryPlan.survey(csite), {"item_type": "cart"})
		var cart_pos: Vector3 = (csp["pos"] as Vector3) + DeliveryPlan.offset(csite)
		GameState.carts[cid] = {
			"id": cid,
			"pos": cart_pos,
			"rot_y": 0.0,
			"pushed_by": 0,
			"items": [],
		}
		GameState._broadcast_carts()
		GameState._rpc_play_sfx.rpc("place")
	elif item_type.begins_with("build:"):
		var oid := item_type.substr(6)
		var bdata: Dictionary = GameState.pending_build_orders.get(oid, {}).duplicate(true)
		GameState.pending_build_orders.erase(oid)
		var cid := GameState._spawn_crate_internal("slot_build_box")
		var rlabel := str(bdata.get("rack_label", "Rack"))
		var sidx := int(bdata.get("slot_idx", 0))
		GameState.crates[cid]["label"] = "%s · Slot %d" % [rlabel, sidx + 1]
		GameState.crates[cid]["build_data"] = bdata
		GameState._broadcast_crates()
		GameState._rpc_play_sfx.rpc("drop")
		GameState.post_event_f("📦 Bausatz-Karton geliefert: %s — an der Werkbank [E] zusammenbauen!", [GameState.crates[cid]["label"]], "good")
	elif item_type.begins_with("bulk:"):
		var parts := item_type.split(":")
		var base_type := parts[1] if parts.size() >= 2 else item_type
		var pcount := clampi(int(parts[2]) if parts.size() >= 3 else 1, 1, GameState.BULK_PACK_MAX)
		GameState._spawn_crate_internal(base_type, pcount)
		GameState._broadcast_crates()
		GameState._rpc_play_sfx.rpc("drop")
	else:
		GameState._spawn_crate_internal(item_type, 1)
		GameState._broadcast_crates()
		GameState._rpc_play_sfx.rpc("drop")


static func _broadcast_van_state() -> void:
	GameState.van_cargo_count = GameState.van_cargo.size()
	var pend_packed := _pack_items_preview(GameState.pending_delivery_items)
	GameState.pending_delivery_count = pend_packed.size()
	var trip := {
		"phase": GameState.van_trip_phase,
		"t": GameState.van_trip_time,
		"site": GameState.van_site,
		"done": GameState.van_trip_done,
		"total": GameState.van_trip_total,
		"tier": GameState.van_delivery_tier,
		"sched_day": GameState.scheduled_delivery_day,
		"sched_hour": GameState.scheduled_delivery_hour,
		"express": GameState.pending_delivery_express,
	}
	GameState._rpc_sync_van_state.rpc(GameState.van_phase, GameState.van_phase_time, GameState.van_cargo_count, GameState.pending_delivery_count, trip)


static func _rpc_sync_van_state(phase: String, phase_t: float, cargo_n: int, pending_n: int, trip: Dictionary) -> void:
	if not GameState.multiplayer.is_server():
		GameState.van_phase = phase
		GameState.van_phase_time = phase_t
		GameState.van_cargo_count = cargo_n
		GameState.pending_delivery_count = pending_n
		GameState.van_trip_phase = str(trip.get("phase", ""))
		GameState.van_trip_time = float(trip.get("t", 0.0))
		GameState.van_site = "halle_nord" if str(trip.get("site", "garage")) == "halle_nord" else "garage"
		GameState.van_trip_done = maxi(int(trip.get("done", 0)), 0)
		GameState.van_trip_total = maxi(int(trip.get("total", 0)), 0)
		GameState.van_delivery_tier = clampi(int(trip.get("tier", 1)), 1, 3)
		GameState.scheduled_delivery_day = int(trip.get("sched_day", 0))
		GameState.scheduled_delivery_hour = int(trip.get("sched_hour", -1))
		GameState.pending_delivery_express = bool(trip.get("express", false))
	GameState.van_updated.emit()


static func _rpc_req_buy_item(item_type: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "buy"):
		return
	if not SecurityGuard.check_rate_limit(peer_id, "buy", 10, 5.0):
		return
	if not GameState.ITEM_CATALOG.has(item_type):
		return
	if get_delivery_zone_free_slots() < 1:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event_f("🚫 Lieferzone voll (%d/%d Plätze)! Erst Pakete aus der Einfahrt räumen.", [
			get_delivery_zone_used_slots(), GameState.DELIVERY_ZONE_MAX_CRATES
		], "warn")
		return
	var price := float(GameState.ITEM_CATALOG[item_type]["price"])
	if GameState.money < price:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= price

	# Add to Delivery Vehicle! If vehicle is currently approaching, toss right into its cargo hold.
	if GameState.van_phase == "arriving":
		GameState.van_cargo.append(item_type)
	else:
		GameState.pending_delivery_items.append(item_type)
		if GameState.van_phase == "idle":
			GameState.van_cargo = _pack_van_cargo(GameState.pending_delivery_items)
			GameState.pending_delivery_items.clear()
			GameState.scheduled_delivery_day = 0
			GameState.scheduled_delivery_hour = -1
			GameState.pending_delivery_express = false
			_start_delivery_van()

	_broadcast_van_state()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")
	var tmeta: Dictionary = GameState.DELIVERY_TIER_META.get(GameState.van_delivery_tier, GameState.DELIVERY_TIER_META[1])
	GameState.post_event_f("%s bestellte %s — %s %s liefert gleich!", [
		NetworkManager.get_player_name(peer_id), GameState.ITEM_CATALOG[item_type]["name"], str(tmeta["icon"]), str(tmeta["name"])
	], "good")


static func _rpc_req_checkout_cart(entries: Array, express: bool = false) -> void:
	if not GameState.multiplayer.is_server() or entries.is_empty() or entries.size() > 40:
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "buy"):
		return
	if not SecurityGuard.check_rate_limit(peer_id, "checkout", 6, 5.0):
		return
	var total_cost := 0.0
	var queue_items: Array = []

	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var kind := str(e.get("kind", "item")) # "item" | "part"
		var qty := clampi(int(e.get("qty", 1)), 1, 24)
		if kind == "item":
			var itype := str(e.get("id", ""))
			if not GameState.ITEM_CATALOG.has(itype) or not GameState.is_item_unlocked(itype):
				continue
			total_cost += float(GameState.ITEM_CATALOG[itype]["price"]) * float(qty)
			if itype == "kit_bundle_all":
				for _q in range(qty):
					for kid in GameState.REPAIR_KIT_ORDER:
						queue_items.append(kid)
			else:
				for _q in range(qty):
					queue_items.append(itype)
		elif kind == "slot_build":
			var mb_id := str(e.get("mainboard_id", ""))
			var comps_d: Dictionary = e.get("components", {}) as Dictionary
			var bprice := GameState.calculate_slot_build_price(mb_id, comps_d)
			if bprice <= 0 or not GameState.ITEM_CATALOG.has(mb_id):
				continue
			total_cost += float(bprice)
			var oid := GameState._alloc_id("build")
			var rid := str(e.get("rack_id", ""))
			var sidx := maxi(0, int(e.get("slot_idx", 0)))
			var rlbl := str(e.get("rack_label", GameState.get_rack_display_name(rid) if not rid.is_empty() else "Rack"))
			GameState.pending_build_orders[oid] = {
				"rack_id": rid,
				"slot_idx": sidx,
				"rack_label": rlbl,
				"mainboard_id": mb_id,
				"components": comps_d.duplicate(true),
			}
			queue_items.append("build:" + oid)
		elif kind == "part":
			var cat := str(e.get("cat", ""))
			var pid := str(e.get("id", ""))
			var pd := HardwareCatalog.get_part(cat, pid)
			if pd.is_empty() or int(pd.get("cost", 0)) <= 0 or not GameState.is_part_unlocked(pd):
				continue
			total_cost += float(pd["cost"]) * float(qty)
			for _q in range(qty):
				queue_items.append("part:" + pid)
		elif kind == "acc":
			# Zubehör (Sicherung, Werkbank-Material, Werkzeug) kommt per Lieferwagen.
			var aid := str(e.get("id", ""))
			var aprice := _accessory_price(aid)
			if aprice <= 0:
				continue
			var room := _accessory_order_room(aid)
			for qi_prev in queue_items:
				if str(qi_prev) == "acc:" + aid:
					room -= 1
			qty = mini(qty, room)
			if qty <= 0:
				continue
			total_cost += float(aprice) * float(qty)
			for _q in range(qty):
				queue_items.append("acc:" + aid)

	var added_parcels: Array = []
	var packed_now := _pack_items_preview(queue_items, added_parcels)
	var order_tier := compute_delivery_tier(packed_now)
	var shipping_fee := float(get_delivery_fee(order_tier, express))
	var grand_total := total_cost + shipping_fee

	if queue_items.is_empty() or GameState.money < grand_total:
		for qi in queue_items:
			var qstr := str(qi)
			if qstr.begins_with("build:"):
				GameState.pending_build_orders.erase(qstr.substr(6))
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	# Lieferflächen-Limit (max. DELIVERY_ZONE_MAX_CRATES physische Kisten inkl. laufender Lieferungen)
	var needed_slots := 0
	for pe in packed_now:
		if str(pe) != GameState.VAN_PARCEL_ITEM:
			needed_slots += 1
	var free_slots := get_delivery_zone_free_slots()
	if needed_slots > free_slots:
		# Angelegte build_orders wieder aufräumen, da Bestellung abgebrochen wurde
		for qi in queue_items:
			var qstr := str(qi)
			if qstr.begins_with("build:"):
				GameState.pending_build_orders.erase(qstr.substr(6))
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event_f("🚫 Lieferzone zu voll (%d frei, %d Kisten benötigt)! Erst Pakete aus der Einfahrt holen.", [
			free_slots, needed_slots
		], "warn")
		return

	GameState.money -= grand_total
	if not GameState.checklist_ordered_anything:
		GameState.checklist_ordered_anything = true
		GameState._broadcast_checklist()
	if GameState.van_phase == "arriving":
		for ap in added_parcels:
			GameState._van_parcel_parts.append(str(ap))
		if not added_parcels.is_empty() and not GameState.van_cargo.has(GameState.VAN_PARCEL_ITEM):
			GameState.van_cargo.push_front(GameState.VAN_PARCEL_ITEM)
		for pn in packed_now:
			if str(pn) != GameState.VAN_PARCEL_ITEM:
				GameState.van_cargo.append(str(pn))
		order_tier = GameState.van_delivery_tier
	else:
		for qi in queue_items:
			GameState.pending_delivery_items.append(str(qi))
		if express:
			GameState.pending_delivery_express = true
			GameState.scheduled_delivery_hour = -1
			GameState.scheduled_delivery_day = 0
		elif GameState.scheduled_delivery_hour < 0:
			var next_slot := get_next_delivery_slot()
			GameState.scheduled_delivery_day = int(next_slot["day"])
			GameState.scheduled_delivery_hour = int(next_slot["hour"])

	_broadcast_van_state()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")
	var tmeta: Dictionary = GameState.DELIVERY_TIER_META.get(order_tier, GameState.DELIVERY_TIER_META[1])
	MailManager.on_order(queue_items.size(), total_cost, shipping_fee, get_scheduled_delivery_label(), express or GameState.van_phase == "arriving")
	if express or GameState.van_phase == "arriving":
		GameState.post_event_f("🛒 %s bestellte %d Artikel ($%.0f + $%.0f Express-Lieferung) — %s %s ist sofort unterwegs!", [
			NetworkManager.get_player_name(peer_id), queue_items.size(), total_cost, shipping_fee,
			str(tmeta["icon"]), str(tmeta["name"])
		], "good")
	else:
		GameState.post_event_f("🛒 %s bestellte %d Artikel ($%.0f + $%.0f Versand) — %s %s kommt im Lieferfenster %s!", [
			NetworkManager.get_player_name(peer_id), queue_items.size(), total_cost, shipping_fee,
			str(tmeta["icon"]), str(tmeta["name"]), get_scheduled_delivery_label()
		], "good")


## Preis eines Zubehörteils aus dem Warenkorb (0 = unbekannte ID).
static func _accessory_price(aid: String) -> int:
	match aid:
		"fuse":
			return GameState.FUSE_PRICE
		"screw_box":
			return GameState.SCREW_BOX_PRICE
		"paste_tube":
			return GameState.PASTE_TUBE_PRICE
	if aid.begins_with("tool_") and GameState.BENCH_TOOLS.has(aid.substr(5)):
		return int(GameState.BENCH_TOOLS[aid.substr(5)]["price"])
	return 0


## Wie viele Stück noch bestellt werden dürfen. Lieferungen, die unterwegs sind, zählen mit.
static func _accessory_order_room(aid: String) -> int:
	var key := "acc:" + aid
	var on_way := GameState.pending_delivery_items.count(key) + GameState.van_cargo.count(key) + GameState._van_parcel_parts.count(key)
	match aid:
		"screw_box":
			return maxi(0, (GameState.BENCH_SCREWS_MAX - GameState.bench_screws) / GameState.SCREW_BOX_COUNT - on_way)
		"paste_tube":
			return maxi(0, int((GameState.BENCH_PASTE_MAX - GameState.bench_paste) / GameState.PASTE_TUBE_USES) - on_way)
	if aid.begins_with("tool_"):
		var tid := aid.substr(5)
		var need := str((GameState.BENCH_TOOLS.get(tid, {}) as Dictionary).get("needs", ""))
		var need_ok := need == "" or GameState.has_bench_tool(need) or GameState.pending_delivery_items.has("acc:tool_" + need) or GameState.van_cargo.has("acc:tool_" + need) or GameState._van_parcel_parts.has("acc:tool_" + need)
		return 0 if (GameState.has_bench_tool(tid) or on_way > 0 or not need_ok) else 1
	return 20


static func cart_add_entry(kind: String, id: String, cat: String, display_name: String, price: int, amount: int = 1) -> void:
	var add_n := maxi(1, amount)
	var key := "%s:%s" % [kind, id]
	for item in GameState.shopping_cart:
		if str(item.get("key", "")) == key:
			item["qty"] = mini(int(item.get("qty", 1)) + add_n, 24)
			GameState.cart_changed.emit()
			return
	GameState.shopping_cart.append({
		"key": key,
		"kind": kind,
		"id": id,
		"cat": cat,
		"name": display_name,
		"price": price,
		"qty": mini(add_n, 24),
	})
	GameState.cart_changed.emit()


static func cart_add_slot_build(rack_id: String, slot_idx: int, mainboard_id: String, comps: Dictionary) -> bool:
	if not GameState.ITEM_CATALOG.has(mainboard_id):
		return false
	var rlabel := GameState.get_rack_display_name(rack_id)
	var key := "slot_build:%s:%d" % [rack_id, slot_idx]
	var price := GameState.calculate_slot_build_price(mainboard_id, comps)
	var mb_name := str(GameState.ITEM_CATALOG[mainboard_id]["name"])
	var entry := {
		"key": key,
		"kind": "slot_build",
		"id": mainboard_id,
		"cat": "slot_build",
		"rack_id": rack_id,
		"slot_idx": slot_idx,
		"rack_label": rlabel,
		"mainboard_id": mainboard_id,
		"components": comps.duplicate(true),
		"name": "%s · Slot %d (%s)" % [rlabel, slot_idx + 1, mb_name],
		"price": price,
		"qty": 1,
	}
	for i in range(GameState.shopping_cart.size()):
		if str(GameState.shopping_cart[i].get("key", "")) == key:
			GameState.shopping_cart[i] = entry
			GameState.cart_changed.emit()
			return true
	GameState.shopping_cart.append(entry)
	GameState.cart_changed.emit()
	return true


static func cart_remove_entry(key: String) -> void:
	for i in range(GameState.shopping_cart.size() - 1, -1, -1):
		if str(GameState.shopping_cart[i].get("key", "")) == key:
			GameState.shopping_cart.remove_at(i)
			GameState.cart_changed.emit()
			return


static func cart_change_qty(key: String, delta: int) -> void:
	for i in range(GameState.shopping_cart.size() - 1, -1, -1):
		if str(GameState.shopping_cart[i].get("key", "")) == key:
			if str(GameState.shopping_cart[i].get("kind", "")) == "slot_build":
				if delta < 0:
					GameState.shopping_cart.remove_at(i)
					GameState.cart_changed.emit()
				return
			var nq := int(GameState.shopping_cart[i].get("qty", 1)) + delta
			if nq <= 0:
				GameState.shopping_cart.remove_at(i)
			else:
				GameState.shopping_cart[i]["qty"] = mini(nq, 24)
			GameState.cart_changed.emit()
			return


static func cart_clear() -> void:
	GameState.shopping_cart.clear()
	GameState.cart_changed.emit()


static func get_cart_count() -> int:
	var n := 0
	for item in GameState.shopping_cart:
		n += int(item.get("qty", 1))
	return n


static func get_cart_total() -> int:
	var t := 0
	for item in GameState.shopping_cart:
		t += int(item.get("price", 0)) * int(item.get("qty", 1))
	return t


static func _generate_daily_deals() -> void:
	if not GameState.multiplayer.is_server():
		return
	GameState.daily_deals.clear()
	var pool_items: Array[String] = ["rack", "web_server", "game_server", "storage_server", "ups", "cooler"]
	if GameState.get_company_level() >= 2:
		pool_items.append("cloud_server")
	if GameState.get_company_level() >= 3:
		pool_items.append("rack_pro")
		pool_items.append("ai_server")
	pool_items.shuffle()
	var count := mini(3, pool_items.size())
	for i in range(count):
		var itype := pool_items[i]
		if not GameState.ITEM_CATALOG.has(itype):
			continue
		var meta: Dictionary = GameState.ITEM_CATALOG[itype]
		var orig := int(meta["price"])
		var disc_pct := randi_range(35, 45)
		var deal_price := maxi(50, int(roundf(float(orig) * (1.0 - float(disc_pct) / 100.0))))
		GameState.daily_deals.append({
			"deal_id": "deal_d%d_%d" % [GameState.day_number, i],
			"item_type": itype,
			"name": str(meta["name"]) + " (B-Ware)",
			"seller": GameState.USED_SELLERS[(GameState.day_number + i) % GameState.USED_SELLERS.size()],
			"orig_price": orig,
			"price": deal_price,
			"discount_pct": disc_pct,
			"sold": false,
		})
	GameState._rpc_sync_daily_deals.rpc(GameState.daily_deals.duplicate(true))


static func _rpc_req_buy_daily_deal(deal_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "buy"):
		return
	if not SecurityGuard.check_rate_limit(peer_id, "buy", 8, 5.0):
		return
	if get_delivery_zone_free_slots() < 1:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Lieferzone voll! Erst Pakete aus der Einfahrt räumen.", "warn")
		return
	var found_idx := -1
	for i in range(GameState.daily_deals.size()):
		if str(GameState.daily_deals[i].get("deal_id", "")) == deal_id:
			found_idx = i
			break
	if found_idx < 0 or bool(GameState.daily_deals[found_idx].get("sold", false)):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var deal: Dictionary = GameState.daily_deals[found_idx]
	var price := float(deal["price"])
	if GameState.money < price:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	var item_type := str(deal["item_type"])
	if not GameState.ITEM_CATALOG.has(item_type):
		return
	GameState.money -= price
	deal["sold"] = true
	if GameState.van_phase == "arriving":
		GameState.van_cargo.append(item_type)
	else:
		GameState.pending_delivery_items.append(item_type)
		if GameState.van_phase == "idle":
			GameState.van_cargo = _pack_van_cargo(GameState.pending_delivery_items)
			GameState.pending_delivery_items.clear()
			GameState.scheduled_delivery_day = 0
			GameState.scheduled_delivery_hour = -1
			GameState.pending_delivery_express = false
			_start_delivery_van()
	GameState._rpc_sync_daily_deals.rpc(GameState.daily_deals.duplicate(true))
	_broadcast_van_state()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")
	GameState.post_event_f("%s schnappte sich %s für $%d (-%d%%) aus dem Gebrauchtmarkt!", [
		NetworkManager.get_player_name(peer_id), str(deal["name"]), int(price), int(deal["discount_pct"])
	], "good")


static func _rpc_req_set_delivery_site(site: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var target := "halle_nord" if (site == "halle_nord" and GameState.halle_nord_owned) else "garage"
	GameState.delivery_target_site = target
	GameState._rpc_sync_halle_nord.rpc(GameState.halle_nord_owned, GameState.delivery_target_site)
	GameState._broadcast_sim_tick()
