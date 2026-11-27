extends RefCounted
## Kabel und Netze: Buchsen und Ports, Kabel stecken und ziehen, LAN-Ketten, Rack-Cluster,
## Router-Stufen und die Neuberechnung von Strom- und Datennetz samt Kennzahlen.
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


static func count_cables_on(cable_type: String, endpoint_id: String) -> int:
	var n := 0
	for cid in GameState.cables.keys():
		var c := CableData.of(GameState.cables[cid])
		if c.cable_type == cable_type and c.touches(endpoint_id):
			n += 1
	return n


## Buchse jedes Kabels an einem Anschluss: {cable_id: slot}. Kabel ohne gespeicherte Buchse
## (alte Spielstände) bekommen der Reihe nach die freien Buchsen, sortiert nach Kabel-ID.
static func get_cable_slot_map(cable_type: String, endpoint_id: String) -> Dictionary:
	var result := {}
	var used := {}
	var legacy: Array[String] = []
	for cid in GameState.cables.keys():
		var c := CableData.of(GameState.cables[cid])
		if c.cable_type != cable_type or not c.touches(endpoint_id):
			continue
		var s := c.slot_at(endpoint_id)
		if s >= 0 and not used.has(s):
			result[str(cid)] = s
			used[s] = true
		else:
			legacy.append(str(cid))
	legacy.sort()
	var next := 0
	for cid in legacy:
		while used.has(next):
			next += 1
		result[cid] = next
		used[next] = true
	return result


## Wie get_cable_slot_map, aber für alle Anschlüsse einer Kabelart in einem Durchgang:
## Anschluss -> {Kabel-ID -> Buchse}. Gleiche Regeln, gleiche Reihenfolge.
static func get_cable_slot_maps(cable_type: String) -> Dictionary:
	var per := {}
	for cid in GameState.cables.keys():
		var c := CableData.of(GameState.cables[cid])
		if c.cable_type != cable_type:
			continue
		_slot_map_take(per, c.from_id, str(cid), c.from_slot)
		if c.to_id != c.from_id:
			_slot_map_take(per, c.to_id, str(cid), c.to_slot)
	var out := {}
	for e in per:
		var p: Array = per[e]
		var result: Dictionary = p[0]
		var used: Dictionary = p[1]
		var legacy: Array = p[2]
		legacy.sort()
		var next := 0
		for cid in legacy:
			while used.has(next):
				next += 1
			result[cid] = next
			used[next] = true
		out[e] = result
	return out


static func _slot_map_take(per: Dictionary, endpoint_id: String, cid: String, s: int) -> void:
	if not per.has(endpoint_id):
		per[endpoint_id] = [{}, {}, []]
	var p: Array = per[endpoint_id]
	if s >= 0 and not (p[1] as Dictionary).has(s):
		(p[0] as Dictionary)[cid] = s
		(p[1] as Dictionary)[s] = true
	else:
		(p[2] as Array).append(cid)


## Gewünschte Buchse, wenn sie existiert und frei ist, sonst die erste freie. -1 = keine frei.
static func pick_free_slot(cable_type: String, endpoint_id: String, wanted: int) -> int:
	var used: Array = get_cable_slot_map(cable_type, endpoint_id).values()
	var max_n := get_max_ports(cable_type, endpoint_id)
	if wanted >= 0 and wanted < max_n and not used.has(wanted):
		return wanted
	for i in range(max_n):
		if not used.has(i):
			return i
	return -1


static func is_lan_strip_decor(eid: String) -> bool:
	return GameState.decor_items.has(eid) and StripData.of(GameState.decor_items[eid]).is_lan()


## Liefert das Kabel an genau dieser Buchse (slot_idx), oder {} wenn der Port frei ist.
static func get_cable_on_slot(cable_type: String, endpoint_id: String, slot_idx: int) -> Dictionary:
	if slot_idx < 0:
		return {}
	var smap := get_cable_slot_map(cable_type, endpoint_id)
	for cid in smap.keys():
		if int(smap[cid]) == slot_idx and GameState.cables.has(cid):
			return GameState.cables[cid] as Dictionary
	return {}


static func get_max_ports(cable_type: String, endpoint_id: String) -> int:
	if cable_type == "cluster":
		return GameState.CLUSTER_PORTS_PER_RACK if GameState.racks.has(endpoint_id) else 0
	if cable_type == "power":
		if endpoint_id == GameState.WALL_BREAKER_ID:
			return GameState.BREAKER_BASE_SOCKETS
		if endpoint_id == GameState.HALL_C_BREAKER_ID:
			return 6 + GameState.power_tier * 2
		if endpoint_id == GameState.HALL_NORD_BREAKER_ID:
			return 16
		if GameState.is_power_strip_decor(endpoint_id):
			return StripRules.POWER_TOP + 2
		if GameState.racks.has(endpoint_id):
			return 2
		if GameState.coolers.has(endpoint_id):
			# Das Innengerät hat keine Strombuchse, es läuft über das Außengerät.
			return 0 if GameState.is_indoor_unit(endpoint_id) else 1
		if GameState.ups_units.has(endpoint_id):
			return 2 # Connect to breaker AND optionally daisy-chain out
		return 0
	else:
		if endpoint_id == GameState.WALL_ROUTER_ID:
			return GameState.ROUTER_TIER_JACK_COUNTS[clampi(GameState.router_tier, 0, GameState.ROUTER_TIER_JACK_COUNTS.size() - 1)]
		if endpoint_id == GameState.HALL_C_ROUTER_ID:
			return 4
		if endpoint_id == GameState.HALL_NORD_ROUTER_ID:
			return 16
		if is_lan_strip_decor(endpoint_id):
			return StripRules.LAN_TOP + 2
		if GameState.racks.has(endpoint_id):
			return 1 + _count_rack_switches(endpoint_id) * 3
		return 0


static func _count_rack_switches(rack_id: String) -> int:
	if not GameState.racks.has(rack_id):
		return 0
	var count := 0
	for slot in GameState.racks[rack_id]["slots"]:
		if str(slot["item_type"]) == "net_switch" and str(slot["state"]) == "ok":
			count += 1
	return count


## Bandbreite, die über jede LAN-Kette läuft (alle Racks hinter der ersten Leiste am Router).
static func _compute_lan_chains() -> void:
	var out := {}
	var of := {}
	for rid in GameState.racks.keys():
		var rack: Dictionary = GameState.racks[rid]
		if not bool(rack.get("networked", false)):
			continue
		var r_rent := str(rack.get("rental_type", "none"))
		if r_rent == "none" or not HardwareCatalog.RENTAL_PROFILES.has(r_rent):
			continue
		var mbps := float(rack.get("active_users", 0)) * float((HardwareCatalog.RENTAL_PROFILES[r_rent] as Dictionary).get("mbps_per_user", 0.5))
		var cur := str(rid)
		var root := ""
		for i in 128:
			if not GameState._lan_parent.has(cur):
				break
			cur = str(GameState._lan_parent[cur])
			if is_lan_strip_decor(cur):
				root = cur
		if root != "":
			out[root] = float(out.get(root, 0.0)) + mbps
			of[str(rid)] = root
	GameState.lan_chain_mbps = out
	GameState.lan_chain_of = of


static func get_lan_chain_root(did: String) -> String:
	var cur := did
	var root := ""
	for i in 128:
		if is_lan_strip_decor(cur):
			root = cur
		if not GameState._lan_parent.has(cur):
			break
		cur = str(GameState._lan_parent[cur])
	return root


static func _recalculate_networks_and_metrics() -> void:
	if GameState.multiplayer.is_server():
		GameState._refresh_slot_power()
	GameState.max_watts = int(GameState.POWER_TIERS[GameState.power_tier]["watts"])
	if GameState.halle_nord_owned:
		GameState.max_watts += GameState.HALLE_NORD_EXTRA_WATTS
	if FinanceManager.is_power_blocked():
		GameState.max_watts = maxi(FinanceManager.BLOCK_POWER_MIN, int(float(GameState.max_watts) * FinanceManager.BLOCK_POWER_FACTOR))

	# Verbundkabel einmal zählen statt je Rack alle Kabel durchzugehen.
	var clustered_ids := {}
	for cid in GameState.cables.keys():
		var cc: Dictionary = GameState.cables[cid]
		if str(cc["cable_type"]) == "cluster":
			clustered_ids[str(cc["from_id"])] = true
			clustered_ids[str(cc["to_id"])] = true
	for rid in GameState.racks.keys():
		GameState.racks[rid]["powered"] = false
		GameState.racks[rid]["networked"] = false
		GameState.racks[rid]["clustered"] = clustered_ids.has(str(rid))
	for cid in GameState.coolers.keys():
		GameState.coolers[cid]["powered"] = false
	for uid in GameState.ups_units.keys():
		GameState.ups_units[uid]["connected"] = false

	# First discover which UPS units are wired into the main breaker power graph
	var bus_sources: Array[String] = [GameState.WALL_BREAKER_ID]
	if GameState.room_level >= 2:
		bus_sources.append(GameState.HALL_C_BREAKER_ID)
	if GameState.halle_nord_owned:
		bus_sources.append(GameState.HALL_NORD_BREAKER_ID)

	var bus_visited: Dictionary = {}
	var bus_queue: Array = []
	for src in bus_sources:
		bus_visited[src] = true
		bus_queue.append(src)

	var p_adj := StripRules.adjacency(StripRules.edges("power"))
	# Rollen ändern sich während der Berechnung nicht: einmal je Anschluss ermitteln.
	var p_roles := {}
	while not bus_queue.is_empty():
		var curr := str(bus_queue.pop_front())
		for x in p_adj.get(curr, []):
			var other: String = x[0]
			var cs: int = x[1]
			var os: int = x[2]
			if other == "" or bus_visited.has(other) or not StripRules.flows("power", curr, cs, other, os, p_roles):
				continue
			bus_visited[other] = true
			if GameState.ups_units.has(other):
				GameState.ups_units[other]["connected"] = true
				bus_queue.append(other)
			elif GameState.is_power_strip_decor(other) and GameState.is_strip_on(other):
				bus_queue.append(other)

	# Determine if UPS backup is keeping the power bus alive during a breaker outage
	var has_charged_ups := false
	for uid in GameState.ups_units.keys():
		if GameState.is_ups_ready(GameState.ups_units[uid]):
			has_charged_ups = true
			break

	GameState.ups_backup_active = (not GameState.breaker_on) and has_charged_ups
	var power_alive := GameState.breaker_on or GameState.ups_backup_active

	GameState._strip_parent = {}
	GameState._strip_feeds = {}
	if power_alive:
		var p_visited: Dictionary = {}
		var p_queue: Array = []
		for src in bus_sources:
			p_visited[src] = true
			p_queue.append(src)
		while not p_queue.is_empty():
			var curr := str(p_queue.pop_front())
			for x in p_adj.get(curr, []):
				var other: String = x[0]
				var cs: int = x[1]
				var os: int = x[2]
				if other == "" or not StripRules.flows("power", curr, cs, other, os, p_roles):
					continue
				# A+B-Einspeisung: ein Rack an zwei Leisten teilt seine Last auf beide auf.
				if GameState.racks.has(other) and p_visited.has(other):
					(GameState._strip_feeds[other] as Array).append(curr)
					continue
				if p_visited.has(other):
					continue
				p_visited[other] = true
				GameState._strip_parent[other] = curr
				GameState._strip_feeds[other] = [curr]
				if GameState.racks.has(other):
					GameState.racks[other]["powered"] = true
				elif GameState.coolers.has(other):
					GameState.coolers[other]["powered"] = true
				elif GameState.ups_units.has(other) or (GameState.is_power_strip_decor(other) and GameState.is_strip_on(other)):
					p_queue.append(other)

		# Goldis Innengeräte laufen, sobald mindestens ein Außengerät Strom hat.
		var any_heat_pump_on := false
		for cid in GameState.coolers.keys():
			if GameState.is_heat_pump_type(str(GameState.coolers[cid].get("cooler_type", "cooler"))) and bool(GameState.coolers[cid]["powered"]):
				any_heat_pump_on = true
				break
		if any_heat_pump_on:
			for cid in GameState.coolers.keys():
				if GameState.is_indoor_unit(str(cid)):
					GameState.coolers[cid]["powered"] = true

		# BFS Network from Wall Router (+ Hall C Router if unlocked)
		GameState._lan_parent = {}
		var n_visited: Dictionary = {GameState.WALL_ROUTER_ID: true}
		var n_queue: Array = [GameState.WALL_ROUTER_ID]
		if GameState.room_level >= 2:
			n_visited[GameState.HALL_C_ROUTER_ID] = true
			n_queue.append(GameState.HALL_C_ROUTER_ID)
		if GameState.halle_nord_owned:
			n_visited[GameState.HALL_NORD_ROUTER_ID] = true
			n_queue.append(GameState.HALL_NORD_ROUTER_ID)

		var n_adj := StripRules.adjacency(StripRules.edges("network"))
		var n_roles := {}
		while not n_queue.is_empty():
			var curr := str(n_queue.pop_front())
			var can_forward := (
				curr == GameState.WALL_ROUTER_ID
				or curr == GameState.HALL_C_ROUTER_ID
				or curr == GameState.HALL_NORD_ROUTER_ID
				or (is_lan_strip_decor(curr) and GameState.is_strip_on(curr))
				or (GameState.racks.has(curr) and bool(GameState.racks[curr]["powered"]) and _count_rack_switches(curr) > 0)
			)
			if not can_forward:
				continue
			for x in n_adj.get(curr, []):
				var other: String = x[0]
				var cs: int = x[1]
				var os: int = x[2]
				if other == "" or n_visited.has(other) or not StripRules.flows("network", curr, cs, other, os, n_roles):
					continue
				n_visited[other] = true
				GameState._lan_parent[other] = curr
				if GameState.racks.has(other):
					GameState.racks[other]["networked"] = true
					n_queue.append(other)
				elif is_lan_strip_decor(other):
					n_queue.append(other)

	# Aggregate real hardware & network bandwidth metrics (GB RAM, TB Storage, CPU, GPU, Mbit/s, Watts)
	var watts := 0
	var compute := 0
	var bonus_sum := 0.0
	var sum_ram := 0
	var sum_cpu := 0
	var sum_gpu := 0
	var sum_sto := 0.0
	var sum_mbps := 0.0
	var device_watts := {}
	if GameState.multiplayer.is_server():
		GameState._apply_rack_power_changes()

	for rid in GameState.racks.keys():
		var rack: Dictionary = GameState.racks[rid]
		if not bool(rack["powered"]):
			continue
		var rack_w0 := watts
		var r_rent := str(rack.get("rental_type", "none"))
		if bool(rack["networked"]) and r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
			var rprof: Dictionary = HardwareCatalog.RENTAL_PROFILES[r_rent]
			sum_mbps += float(rack.get("active_users", 0)) * float(rprof.get("mbps_per_user", 0.5))
		for slot in rack["slots"]:
			var sd: Dictionary = slot
			var item_type := str(sd["item_type"])
			if item_type == "":
				continue
			var st := str(sd["state"])
			var stats := GameState.get_slot_stats(sd)
			if GameState.is_slot_on(sd):
				watts += int(stats["watts"])
				if bool(rack["networked"]):
					compute += int(stats["compute"])
					bonus_sum += float(stats["revenue_bonus"])
					sum_ram += int(stats["ram_gb"])
					sum_cpu += int(stats["cpu_score"])
					sum_gpu += int(stats["gpu_score"])
					sum_sto += float(stats["storage_tb"])
			elif st == "burning":
				watts += int(stats["watts"])
		device_watts[rid] = watts - rack_w0

	# Kaltgang-/Warmgang-Airflow & Kabelmanagement-Bonus live berechnen
	GameState._recompute_layout_bonuses()

	var heatwave_cooler_mult := 1.22 if GameState.weather_state == "heatwave" else 1.0
	var airflow_watt_save := 1.0 - GameState.airflow_bonus * 0.45
	for cid in GameState.coolers.keys():
		if bool(GameState.coolers[cid]["powered"]):
			var ctype := str(GameState.coolers[cid].get("cooler_type", "cooler"))
			var cw := int(roundf(float(GameState.ITEM_CATALOG[ctype]["watts"]) * heatwave_cooler_mult * airflow_watt_save))
			watts += cw
			device_watts[cid] = cw

	# Ladende Notstrom-Batterien ziehen ihre Ladeleistung
	if GameState.breaker_on:
		for uid in GameState.ups_units.keys():
			var u: Dictionary = GameState.ups_units[uid]
			if bool(u["connected"]) and float(u["charge"]) < 99.5:
				var chw := int(GameState.get_ups_spec(u)["charge_w"])
				watts += chw
				device_watts[uid] = chw
	GameState._compute_strip_loads(device_watts)
	_compute_lan_chains()

	var req_compute := 0
	for cid in GameState.contracts.keys():
		if bool(GameState.contracts[cid]["active"]):
			req_compute += int(GameState.contracts[cid]["required_compute"])
			sum_mbps += float(GameState.contracts[cid].get("req_mbps", 15.0))

	var rt_d: Dictionary = GameState.ROUTER_TIERS[clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)]
	GameState.max_bandwidth_cu = int(rt_d["max_cu"])
	GameState.max_bandwidth_mbps = float(rt_d.get("max_mbps", 50.0))
	if GameState.halle_nord_owned:
		GameState.max_bandwidth_mbps += GameState.HALLE_NORD_EXTRA_MBPS
		GameState.max_bandwidth_cu += 600
	if FinanceManager.is_blocked("internet"):
		GameState.max_bandwidth_mbps = maxf(10.0, GameState.max_bandwidth_mbps * FinanceManager.BLOCK_NET_FACTOR)
	GameState.total_watts = watts
	GameState.total_ram_gb = sum_ram
	GameState.total_cpu_score = sum_cpu
	GameState.total_gpu_score = sum_gpu
	GameState.total_storage_tb = sum_sto
	GameState.used_bandwidth_mbps = sum_mbps
	GameState.raw_compute = compute
	GameState.total_compute = mini(compute, GameState.max_bandwidth_cu)
	GameState.used_compute = req_compute
	GameState.revenue_bonus_mult = (1.0 + minf(bonus_sum + GameState.cable_mgmt_bonus, 0.92)) * GameState.get_level_revenue_mult()
	if FinanceManager.is_blocked("license"):
		GameState.revenue_bonus_mult *= FinanceManager.BLOCK_LICENSE_FACTOR


static func _disconnect_all_cables_of(entity_id: String) -> void:
	var to_del: Array = []
	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c["from_id"]) == entity_id or str(c["to_id"]) == entity_id:
			to_del.append(cid)
	for cid in to_del:
		GameState.cables.erase(cid)


static func _rpc_req_connect_cable(cable_type: String, from_id: String, to_id: String, from_slot: int, to_slot: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "cable"):
		return
	if cable_type != "power" and cable_type != "network" and cable_type != "cluster":
		return
	if from_id == to_id:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	if not _is_valid_cable_endpoint(cable_type, from_id) or not _is_valid_cable_endpoint(cable_type, to_id):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c["cable_type"]) == cable_type:
			var a := str(c["from_id"])
			var b := str(c["to_id"])
			if (a == from_id and b == to_id) or (a == to_id and b == from_id):
				GameState._rpc_play_sfx.rpc_id(peer_id, "error")
				return

	if cable_type == "power" and (from_id == GameState.WALL_BREAKER_ID or to_id == GameState.WALL_BREAKER_ID) \
			and count_cables_on("power", GameState.WALL_BREAKER_ID) >= get_max_ports("power", GameState.WALL_BREAKER_ID):
		GameState.post_event("Der Stromkasten hat nur eine Steckdose. Schließe dort eine Stromleiste an und verteile von ihr weiter.", "warn")
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var rule := StripRules.plan(cable_type, from_id, from_slot, to_id, to_slot)
	if not bool(rule["ok"]):
		GameState._rpc_cable_hint.rpc_id(peer_id, str(rule["msg"]))
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	if count_cables_on(cable_type, from_id) >= get_max_ports(cable_type, from_id):
		GameState.post_event_f("Kein freier %s-Port an %s (Rack-Switch oder Upgrade nötig).", [
			_cable_type_label(cable_type), from_id.to_upper()
		], "warn")
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	if count_cables_on(cable_type, to_id) >= get_max_ports(cable_type, to_id):
		GameState.post_event_f("Kein freier %s-Port an %s.", [
			_cable_type_label(cable_type), to_id.to_upper()
		], "warn")
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return

	var use_from_slot := int(rule["a_slot"]) if StripRules.role(cable_type, from_id) == "strip" else pick_free_slot(cable_type, from_id, from_slot)
	var use_to_slot := int(rule["b_slot"]) if StripRules.role(cable_type, to_id) == "strip" else pick_free_slot(cable_type, to_id, to_slot)
	var cab_id := GameState._alloc_id("cable")
	GameState.cables[cab_id] = CableData.make(cab_id, cable_type, from_id, use_from_slot, to_id, use_to_slot)
	_recalculate_networks_and_metrics()
	GameState._broadcast_cables()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cable")
	var label := "%skabel" % _cable_type_label(cable_type)
	GameState.post_event_f("%s verband %s: %s ↔ %s", [NetworkManager.get_player_name(peer_id), label, from_id.to_upper(), to_id.to_upper()], "info")


## Hinweis nur für den Spieler, der falsch gesteckt hat.
static func _rpc_cable_hint(msg: String) -> void:
	GameState.cable_hint.emit(GameState.tr(msg))


## Racks, die über ein Cluster-Kabel direkt mit rack_id verbunden sind.
static func _cluster_neighbors(rack_id: String) -> Array[String]:
	var out: Array[String] = []
	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c.get("cable_type", "")) != "cluster":
			continue
		var a := str(c.get("from_id", ""))
		var b := str(c.get("to_id", ""))
		if a == rack_id and GameState.racks.has(b):
			out.append(b)
		elif b == rack_id and GameState.racks.has(a):
			out.append(a)
	return out


## Freie Hardware je Cluster-Rack aus der Auslastung des letzten Ticks.
## Racks ohne Strom, ohne laufende Server, mit Brand oder überlasteter PSU verleihen nichts,
## ebenso Racks, die selbst gerade leihen.
static func _compute_cluster_spare() -> Dictionary:
	var spare: Dictionary = {}
	for rid in GameState.racks.keys():
		var rack_id := str(rid)
		if count_cables_on("cluster", rack_id) == 0:
			continue
		var r: Dictionary = GameState.racks[rid]
		if not bool(r.get("powered", false)) or GameState._rack_has_fire(r):
			continue
		var hw := GameState.get_rack_hardware_summary(rack_id)
		if int(hw["active_servers"]) <= 0 or bool(hw["psu_overloaded"]):
			continue
		var m: Dictionary = r["metrics"] if r.get("metrics") is Dictionary else {}
		var lent_last: Variant = m.get("cluster_borrowed", {})
		if lent_last is Dictionary and not (lent_last as Dictionary).is_empty():
			continue
		var has_tenants := not GameState._get_rack_services(r).is_empty()
		var used_frac := {
			"ram_gb": float(m.get("ram_pct", 0.0)) / 100.0,
			"cpu_score": float(m.get("cpu_pct", 0.0)) / 100.0,
			"gpu_score": float(m.get("gpu_pct", 0.0)) / 100.0,
			"storage_tb": float(m.get("storage_pct", 0.0)) / 100.0,
		}
		var free: Dictionary = {}
		for key in GameState.CLUSTER_RESOURCES:
			var total := float(hw[key])
			var used := total * float(used_frac[key]) if has_tenants else 0.0
			free[key] = maxf(0.0, total * GameState.CLUSTER_LENDER_RESERVE - used)
		spare[rack_id] = free
	return spare


## Ergänzt hw um geliehene Kapazität der Nachbar-Racks und verbraucht sie in spare.
## Gibt die geliehenen Mengen je Ressource zurück (leer, wenn nichts geliehen wurde).
static func _borrow_cluster_capacity(rack_id: String, hw: Dictionary, users: int, prof: Dictionary, spare: Dictionary) -> Dictionary:
	var borrowed: Dictionary = {}
	var neighbors := _cluster_neighbors(rack_id)
	if neighbors.is_empty():
		return borrowed
	var needs := {
		"ram_gb": float(users) * float(prof["ram_gb_per_user"]),
		"cpu_score": float(users) * float(prof["cpu_per_user"]),
		"gpu_score": float(users) * float(prof["gpu_per_user"]),
		"storage_tb": float(users) * float(prof["storage_tb_per_user"]),
	}
	for key in GameState.CLUSTER_RESOURCES:
		var want := float(needs[key]) / GameState.CLUSTER_BORROW_TARGET - float(hw[key])
		if want <= 0.0:
			continue
		var got := 0.0
		for nid in neighbors:
			if not spare.has(nid):
				continue
			var ns: Dictionary = spare[nid]
			var take := minf(want - got, float(ns.get(key, 0.0)))
			if take <= 0.0:
				continue
			ns[key] = float(ns[key]) - take
			got += take
			if got >= want:
				break
		if got > 0.0:
			hw[key] = float(hw[key]) + got
			borrowed[key] = got
	return borrowed


static func _cable_type_label(cable_type: String) -> String:
	match cable_type:
		"power":
			return "Strom"
		"cluster":
			return "Cluster"
		_:
			return "Netzwerk"


static func _is_valid_cable_endpoint(cable_type: String, endpoint_id: String) -> bool:
	# Cluster-Kabel verbinden nur Racks untereinander.
	if cable_type == "cluster":
		return GameState.racks.has(endpoint_id)
	if cable_type == "power":
		if endpoint_id == GameState.WALL_BREAKER_ID:
			return true
		if endpoint_id == GameState.HALL_C_BREAKER_ID and GameState.room_level >= 2:
			return true
		if endpoint_id == GameState.HALL_NORD_BREAKER_ID and GameState.halle_nord_owned:
			return true
		# Das Goldis Innengerät hat keine Strombuchse.
		return GameState.racks.has(endpoint_id) or (GameState.coolers.has(endpoint_id) and not GameState.is_indoor_unit(endpoint_id)) or GameState.ups_units.has(endpoint_id) or GameState.is_power_strip_decor(endpoint_id)
	else:
		if endpoint_id == GameState.WALL_ROUTER_ID:
			return true
		if endpoint_id == GameState.HALL_C_ROUTER_ID and GameState.room_level >= 2:
			return true
		if endpoint_id == GameState.HALL_NORD_ROUTER_ID and GameState.halle_nord_owned:
			return true
		return GameState.racks.has(endpoint_id) or is_lan_strip_decor(endpoint_id)


static func _rpc_req_disconnect_cable_slot(cable_type: String, endpoint_id: String, slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	if GameState._deny_build(GameState._get_sender_id(), "cable"):
		return
	var target_cid := ""
	if slot_idx >= 0:
		var smap := get_cable_slot_map(cable_type, endpoint_id)
		for cid in smap.keys():
			if int(smap[cid]) == slot_idx and GameState.cables.has(cid):
				target_cid = str(cid)
				break
	if target_cid == "":
		_rpc_req_disconnect_cables_on(cable_type, endpoint_id)
		return
	GameState.cables.erase(target_cid)
	_recalculate_networks_and_metrics()
	GameState._broadcast_cables()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cable_cut")


static func _rpc_req_disconnect_cables_on(cable_type: String, endpoint_id: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	if GameState._deny_build(GameState._get_sender_id(), "cable"):
		return
	var to_remove: Array = []
	for cid in GameState.cables.keys():
		var c := CableData.of(GameState.cables[cid])
		if c.cable_type == cable_type and c.touches(endpoint_id):
			to_remove.append(cid)
	if to_remove.is_empty():
		return
	GameState.cables.erase(to_remove[to_remove.size() - 1])
	_recalculate_networks_and_metrics()
	GameState._broadcast_cables()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cable_cut")


static func _rpc_req_upgrade_router() -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "expand"):
		return
	if GameState.router_tier + 1 >= GameState.ROUTER_TIERS.size():
		return
	var next_r: Dictionary = GameState.ROUTER_TIERS[GameState.router_tier + 1]
	var cost := float(next_r["cost"])
	if GameState.money < cost:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= cost
	GameState.router_tier += 1
	_recalculate_networks_and_metrics()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("upgrade")
	GameState.post_event_f("%s installierte neuen Router: %s!", [
		NetworkManager.get_player_name(peer_id), str(next_r["label"])
	], "good")


static func _approx_endpoint_pos(eid: String) -> Vector3:
	if GameState.racks.has(eid):
		return GameState.racks[eid].get("pos", Vector3.ZERO) as Vector3
	if GameState.coolers.has(eid):
		return GameState.coolers[eid].get("pos", Vector3.ZERO) as Vector3
	if GameState.ups_units.has(eid):
		return GameState.ups_units[eid].get("pos", Vector3.ZERO) as Vector3
	if eid == GameState.WALL_BREAKER_ID:
		return Vector3(-4.5, 1.5, -4.3)
	if eid == GameState.WALL_ROUTER_ID:
		return Vector3(0.4, 1.8, -4.3)
	if eid == GameState.HALL_C_BREAKER_ID:
		return Vector3(21.0, 1.5, -4.3)
	if eid == GameState.HALL_C_ROUTER_ID:
		return Vector3(21.0, 1.8, -2.5)
	if eid == GameState.HALL_NORD_BREAKER_ID:
		return GameState.HALLE_NORD_ORIGIN + Vector3(-8.2, 1.5, -5.7)
	if eid == GameState.HALL_NORD_ROUTER_ID:
		return GameState.HALLE_NORD_ORIGIN + Vector3(-4.6, 1.8, -5.7)
	return Vector3.ZERO
