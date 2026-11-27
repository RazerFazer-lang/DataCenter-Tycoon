extends RefCounted
## Strom: Steckleisten und ihre Ketten, USV, Sicherungen, Hauptschalter, Netzausfall,
## Strom der Einschübe (Hochfahren) und Stromrechnung.
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


static func get_estimated_daily_bill() -> int:
	return int(roundf(GameState.daily_energy_cost + GameState.daily_peak_kw * PowerTariff.PEAK_CHARGE_PER_KW))


## GAME-02: Netzbezug dieses Takts abrechnen. Arbeitspreis nach Tarif der Stunde, die höchste Netzlast
## des Tages zählt für den Leistungspreis. Solar deckt tagsüber einen Teil, USV-Laden kommt dazu,
## Peak-Shaving geht ab.
static func account_energy(dt: float, charge_kw: float, shave_kw: float) -> void:
	var hour := PowerTariff.hour_of(GameState.time_of_day)
	var load_kw := float(GameState.total_watts) / 1000.0
	var solar_kw := 0.0
	if GameState.has_building_upgrade("upg_pv_solar"):
		solar_kw = load_kw * PowerTariff.solar_share(hour, GameState.weather_state)
	var grid_kw := maxf(0.0, (load_kw - solar_kw - shave_kw) * OutdoorManager.power_mult()) + charge_kw
	GameState.solar_kw_now = solar_kw
	GameState.shave_kw_now = shave_kw
	GameState.grid_kw_now = 0.0 if GameState.on_generator else grid_kw
	# GAME-01: Läuft das Aggregat, kommt nichts vom Netz. Den Diesel rechnet Operations ab.
	if GameState.on_generator:
		return
	# Verbrauch in Spielstunden: ein Spieltag zählt 24 Stunden Last.
	var kwh := grid_kw * dt / GameState.DAY_LENGTH_SECONDS * 24.0
	GameState.daily_kwh += kwh
	GameState.daily_energy_cost += kwh * GameState.electricity_rate * PowerTariff.mult_at(hour)
	GameState.daily_peak_kw = maxf(GameState.daily_peak_kw, grid_kw)


## Neuer Tagespreis: zufällige Änderung, die zum Grundpreis zurückzieht. Nur auf dem Host.
static func _roll_electricity_rate(current: float) -> float:
	var pull := (GameState.ELECTRICITY_RATE_PER_KWH - current) * GameState.ELECTRICITY_RATE_REVERSION
	var swing := randf_range(-GameState.ELECTRICITY_RATE_DAILY_SWING, GameState.ELECTRICITY_RATE_DAILY_SWING)
	return snappedf(clampf(current + pull + swing, GameState.ELECTRICITY_RATE_MIN, GameState.ELECTRICITY_RATE_MAX), 0.01)


static func is_power_strip_decor(eid: String) -> bool:
	return GameState.decor_items.has(eid) and StripData.of(GameState.decor_items[eid]).is_power()


static func is_ups_type(item_type: String) -> bool:
	return GameState.UPS_TYPES.has(item_type)


static func get_ups_type(u: Dictionary) -> String:
	var t := str(u.get("ups_type", "ups"))
	return t if GameState.UPS_TYPES.has(t) else "ups"


static func get_ups_spec(u: Dictionary) -> Dictionary:
	return GameState.UPS_TYPES[get_ups_type(u)]


static func get_ups_health(u: Dictionary) -> float:
	return clampf(float(u.get("health", 100.0)), GameState.UPS_MIN_HEALTH, 100.0)


## Nutzbare Kapazität in Wh, Alterung eingerechnet.
static func get_ups_capacity(u: Dictionary) -> float:
	return float(get_ups_spec(u)["cap"]) * get_ups_health(u) / 100.0


static func get_ups_stored_wh(u: Dictionary) -> float:
	return get_ups_capacity(u) * clampf(float(u.get("charge", 0.0)), 0.0, 100.0) / 100.0


static func is_ups_ready(u: Dictionary) -> bool:
	return bool(u.get("connected", false)) and float(u.get("charge", 0.0)) > 0.2 and not bool(u.get("tripped", false))


## Gesamte Abgabeleistung aller bereiten Notstrom-Geräte.
static func get_ups_total_out() -> float:
	var sum := 0.0
	for uid in GameState.ups_units.keys():
		if is_ups_ready(GameState.ups_units[uid]):
			sum += float(get_ups_spec(GameState.ups_units[uid])["out"])
	return sum


## Restzeit in Spielminuten bei aktueller Last (alle bereiten Geräte zusammen).
static func get_ups_runtime_minutes() -> int:
	var wh := 0.0
	for uid in GameState.ups_units.keys():
		if is_ups_ready(GameState.ups_units[uid]):
			wh += get_ups_stored_wh(GameState.ups_units[uid])
	return int(wh / maxf(50.0, float(GameState.total_watts) * 1.06) * 60.0)


static func get_ups_swap_cost(u: Dictionary) -> int:
	return int(get_ups_spec(u)["swap"])


static func _rpc_req_swap_ups_cells(uid: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not GameState.ups_units.has(uid) or not SecurityGuard.check_rate_limit(peer_id, "ups_swap", 4, 5.0):
		return
	var u: Dictionary = GameState.ups_units[uid]
	var cost := get_ups_swap_cost(u)
	if GameState.money < float(cost) or get_ups_health(u) > 95.0 or bool(u.get("discharging", false)):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= float(cost)
	u["health"] = 100.0
	u["charge"] = minf(float(u.get("charge", 0.0)), 40.0)
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("upgrade")
	GameState.post_event_f("%s hat die Akkus von %s getauscht (-$%d).", [NetworkManager.get_player_name(peer_id), uid.to_upper(), cost], "good")


## Strom- und LAN-Leisten sind flach: feineres Raster und weniger Abstand zu Geräten.
static func is_strip_type(item_type: String) -> bool:
	return StripData.is_strip_type(item_type)


static func is_strip_on(did: String) -> bool:
	return StripData.of(GameState.decor_items.get(did, {})).on


static func is_wall_strip(d: Dictionary) -> bool:
	return StripData.of(d).wall


static func get_strip_limit(did: String) -> int:
	return StripRules.STRIP_LIMIT_W if is_power_strip_decor(did) else 0


## Erste Leiste der Kette, in der diese Leiste hängt ("" = hängt nicht am Strom).
static func get_chain_root(did: String) -> String:
	var cur := did
	var root := ""
	for i in 128:
		if is_power_strip_decor(cur):
			root = cur
		if not GameState._strip_parent.has(cur):
			break
		cur = str(GameState._strip_parent[cur])
	return root if StripRules.role("power", cur) == "source" else ""


## Kommt an dieser Leiste Strom bzw. Netz an?
static func is_strip_fed(ctype: String, did: String) -> bool:
	if ctype == "power":
		return GameState._strip_parent.has(did) and get_chain_root(did) != ""
	return GameState._lan_parent.has(did)


## Versorgt diese Leiste über ihren Ausgang eine weitere?
static func feeds_next_strip(ctype: String, did: String) -> bool:
	var parents := GameState._strip_parent if ctype == "power" else GameState._lan_parent
	for k in parents.keys():
		if str(parents[k]) == did and StripRules.is_strip(ctype, str(k)):
			return true
	return false


static func get_chain_load(did: String) -> int:
	return int(GameState.chain_loads.get(get_chain_root(did), 0))


static func get_chain_length(did: String) -> int:
	var root := get_chain_root(did)
	var n := 0
	for k in GameState._strip_parent.keys():
		if is_power_strip_decor(str(k)) and get_chain_root(str(k)) == root and root != "":
			n += 1
	return n


static func get_strip_load(did: String) -> int:
	return int(GameState.strip_loads.get(did, 0))


static func _rpc_req_toggle_strip(did: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not (is_power_strip_decor(did) or GameState.is_lan_strip_decor(did)) or not SecurityGuard.check_rate_limit(peer_id, "strip", 8, 4.0):
		return
	var s := StripData.of(GameState.decor_items[did])
	s.on = not s.on
	if s.on:
		s.tripped = false
		GameState._strip_over.erase(did)
	_after_strip_change()
	GameState._rpc_play_sfx.rpc("strip_switch")


static func _after_strip_change() -> void:
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_decor_items()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()


## Überlastete Leisten lösen nach ein paar Sekunden aus (nur Host). Ist die ganze Kette zu viel
## für den Abgang, fällt die erste Leiste am Kasten und alles dahinter ist aus.
static func _tick_strips(dt: float) -> void:
	for root_v in GameState.chain_loads.keys():
		var root := str(root_v)
		if not is_power_strip_decor(root) or not is_strip_on(root) or int(GameState.chain_loads[root]) <= StripRules.CHAIN_LIMIT_W:
			GameState._chain_over.erase(root)
			continue
		GameState._chain_over[root] = float(GameState._chain_over.get(root, 0.0)) + dt
		if float(GameState._chain_over[root]) >= GameState.STRIP_TRIP_SECONDS:
			GameState._chain_over.erase(root)
			var s := StripData.of(GameState.decor_items[root])
			s.on = false
			s.tripped = true
			GameState.post_event_f("LEISTENKETTE AUSGELÖST: %d W am Abgang, höchstens %d W. Die ganze Kette ist aus. Last auf einen zweiten Abgang verteilen und an der ersten Leiste wieder einschalten.", [int(GameState.chain_loads[root]), StripRules.CHAIN_LIMIT_W], "alert")
			_after_strip_change()
			GameState._rpc_play_sfx.rpc("breaker_trip")
			return
	for did_v in GameState.strip_loads.keys():
		var did := str(did_v)
		if not is_power_strip_decor(did) or not is_strip_on(did):
			GameState._strip_over.erase(did)
			continue
		if get_strip_load(did) <= get_strip_limit(did):
			GameState._strip_over.erase(did)
			continue
		# Eine Leiste weiter oben in der Kette ist schon aus? Dann hat diese keine Last mehr.
		GameState._strip_over[did] = float(GameState._strip_over.get(did, 0.0)) + dt
		if float(GameState._strip_over[did]) >= GameState.STRIP_TRIP_SECONDS:
			GameState._strip_over.erase(did)
			GameState.decor_items[did]["on"] = false
			GameState.decor_items[did]["tripped"] = true
			GameState.post_event_f("STROMLEISTE AUSGELÖST: %d W bei höchstens %d W. Last verteilen und am Schalter wieder einschalten.", [get_strip_load(did), get_strip_limit(did)], "alert")
			_after_strip_change()
			GameState._rpc_play_sfx.rpc("breaker_trip")
			return


## Last je Leiste (nur die Geräte oben in ihren Buchsen) und je Kette (alles am Abgang).
static func _compute_strip_loads(device_watts: Dictionary) -> void:
	var loads := {}
	var chains := {}
	for did in GameState.decor_items.keys():
		if is_power_strip_decor(str(did)):
			loads[did] = 0
	for dev in device_watts.keys():
		var feeds: Array = GameState._strip_feeds.get(str(dev), [])
		if feeds.is_empty():
			continue
		var share := float(device_watts[dev]) / float(feeds.size())
		for f in feeds:
			if loads.has(f):
				loads[f] = int(loads[f]) + roundi(share)
			var root := get_chain_root(str(f)) if is_power_strip_decor(str(f)) else ""
			if root != "":
				chains[root] = int(chains.get(root, 0)) + roundi(share)
	GameState.strip_loads = loads
	GameState.chain_loads = chains
	GameState.strip_loads_changed.emit()


## Montageplatz einer Leiste an einer Wand. Leer = hier geht es nicht.
static func get_strip_wall_spot(hit: Vector3, normal: Vector3) -> Dictionary:
	if absf(normal.y) > 0.3:
		return {}
	var n := Vector3(signf(normal.x), 0.0, 0.0) if absf(normal.x) > absf(normal.z) else Vector3(0.0, 0.0, signf(normal.z))
	var y := clampf(roundf(hit.y * 10.0) / 10.0, GameState.STRIP_WALL_MIN_Y + 0.02, GameState.STRIP_WALL_MAX_Y)
	for w in _strip_walls():
		var wn: Vector3 = w["n"]
		if not wn.is_equal_approx(n):
			continue
		var on_x := absf(wn.z) > 0.5
		var plane: float = w["at"]
		if absf((hit.z if on_x else hit.x) - plane) > GameState.WALL_HIT_TOLERANCE:
			continue
		var along := clampf(roundf((hit.x if on_x else hit.z) * 4.0) / 4.0, float(w["lo"]), float(w["hi"]))
		if absf(along - (hit.x if on_x else hit.z)) > 0.6:
			continue
		var pos := Vector3(along, y, plane) if on_x else Vector3(plane, y, along)
		return {"pos": pos, "rot_y": atan2(wn.x, wn.z)}
	return {}


static func _strip_walls() -> Array:
	var out: Array = []
	var max_x := GameState._interior_max_x() - 0.5
	out.append({"n": Vector3(0, 0, 1), "at": GameState.WALL_FACE_NORTH_Z, "lo": -5.0, "hi": max_x})
	out.append({"n": Vector3(0, 0, -1), "at": GameState.WALL_FACE_SOUTH_Z, "lo": -5.0, "hi": max_x})
	out.append({"n": Vector3(1, 0, 0), "at": GameState.WALL_FACE_WEST_X, "lo": -4.0, "hi": 4.0})
	if GameState.room_level >= 2:
		out.append({"n": Vector3(-1, 0, 0), "at": GameState.WALL_FACE_EAST_X, "lo": -4.0, "hi": 4.0})
	if GameState.halle_nord_owned:
		var o := GameState.HALLE_NORD_ORIGIN
		out.append({"n": Vector3(0, 0, 1), "at": o.z - 5.86, "lo": -9.3, "hi": 9.3})
		out.append({"n": Vector3(0, 0, -1), "at": o.z + 5.86, "lo": -9.3, "hi": 9.3})
		out.append({"n": Vector3(1, 0, 0), "at": -9.86, "lo": o.z - 5.3, "hi": o.z + 5.3})
		out.append({"n": Vector3(-1, 0, 0), "at": 9.86, "lo": o.z - 5.3, "hi": o.z + 5.3})
	return out


static func can_place_strip_on_wall(pos: Vector3, rot_y: float, ignore_id: String = "") -> bool:
	if pos.y < GameState.STRIP_WALL_MIN_Y or pos.y > GameState.STRIP_WALL_MAX_Y + 0.01:
		return false
	var n := Vector3(sin(rot_y), 0.0, cos(rot_y)).round()
	var spot := get_strip_wall_spot(pos, n)
	if spot.is_empty():
		return false
	# Entlang der Wand darf die Leiste frei sitzen (zusammengesteckte Leisten liegen nicht im Raster).
	var off := (spot["pos"] as Vector3) - pos
	var along_dir := Vector3(absf(n.z), 0.0, absf(n.x))
	off -= along_dir * off.dot(along_dir)
	if off.length() > 0.05:
		return false
	if absf(n.z) > 0.5:
		var local_z := pos.z - GameState.HALLE_NORD_ORIGIN.z if pos.z < -100.0 else pos.z
		# Tore frei lassen
		if n.z < 0.0 and local_z > 4.0 and absf(pos.x) < 2.75:
			return false
		if pos.z > -100.0:
			for k in GameState.STRIP_WALL_KEEPOUT:
				if absf(pos.z - float(k[0])) < 0.2 and absf(pos.x - float(k[1])) < float(k[3]) + 0.34 and absf(pos.y - float(k[2])) < float(k[4]) + 0.07:
					return false
	for did in GameState.decor_items.keys():
		if str(did) == ignore_id:
			continue
		var d: Dictionary = GameState.decor_items[did]
		if is_wall_strip(d) and (d["pos"] as Vector3).distance_to(pos) < 0.72 and absf((d["pos"] as Vector3).y - pos.y) < 0.14:
			return false
	for cid in GameState.coolers.keys():
		var c: Dictionary = GameState.coolers[cid]
		if str(c.get("cooler_type", "")) == GameState.INDOOR_UNIT_TYPE and (c["pos"] as Vector3).distance_to(pos) < 0.75:
			return false
	return true


static func can_place_strip_at(pos: Vector3, ignore_id: String = "") -> bool:
	if GameState.halle_nord_owned and pos.z < -100.0:
		var lz := pos.z - GameState.HALLE_NORD_ORIGIN.z
		if pos.x < -9.3 or pos.x > 9.3 or lz < -5.0 or lz > 5.2:
			return false
		if lz < -2.3 and pos.x > 4.3:
			return false
		if lz > 4.0 and absf(pos.x) < 2.3:
			return false
	else:
		var max_x := 4.8 if GameState.room_level == 0 else (11.7 if GameState.room_level == 1 else 20.6)
		if pos.x < -4.8 or pos.x > max_x or pos.z < -4.0 or pos.z > 3.9:
			return false
		if pos.z > 2.6 and absf(pos.x) < 2.2:
			return false
	for group in [GameState.racks, GameState.coolers, GameState.ups_units]:
		for gid in (group as Dictionary).keys():
			var entry: Dictionary = (group as Dictionary)[gid]
			if str(entry.get("cooler_type", "")) == GameState.INDOOR_UNIT_TYPE:
				continue
			var gpos: Vector3 = entry["pos"]
			if Vector2(gpos.x - pos.x, gpos.z - pos.z).length() < 0.62:
				return false
	for did in GameState.decor_items.keys():
		if str(did) == ignore_id or is_wall_strip(GameState.decor_items[did]):
			continue
		var d: Dictionary = GameState.decor_items[did]
		var dpos: Vector3 = d.get("pos", Vector3.ZERO)
		var gap := 0.24 if is_strip_type(str(d.get("item_type", ""))) else 0.62
		if Vector2(dpos.x - pos.x, dpos.z - pos.z).length() < gap:
			return false
		# Leisten direkt hintereinander: Enden berühren sich, aber nicht seitlich daneben.
		if is_strip_type(str(d.get("item_type", ""))):
			var rel := Vector2(pos.x - dpos.x, pos.z - dpos.z)
			var ax := StripRules.axis(d)
			var along := rel.dot(Vector2(ax.x, ax.z))
			var across := absf(rel.cross(Vector2(ax.x, ax.z)))
			if across < 0.13 and absf(along) < StripRules.LINK_PITCH - 0.02:
				return false
	return true


## Hochfahrzeit je nach Servergröße (Sekunden).
static func get_boot_seconds(item_type: String) -> float:
	if not GameState.is_slot_upgradeable(item_type):
		return 6.0
	match str((GameState.ITEM_CATALOG.get(item_type, {}) as Dictionary).get("mb_cat", "entry")):
		"server":
			return 9.0
		"storage":
			return 11.0
		"gpu":
			return 15.0
	return 6.0


## true, wenn der Server Strom bekommt und fertig hochgefahren ist (Rack-Strom wird extra geprüft).
static func is_slot_on(slot: Dictionary) -> bool:
	return str(slot.get("state", "ok")) == "ok" and not bool(slot.get("offline", false))


## Strom weg = alle Server aus. Strom da = Server fahren der Reihe nach hoch (nur Host).
static func _apply_rack_power_changes() -> void:
	for rid_v in GameState.racks.keys():
		var rid := str(rid_v)
		var now := bool(GameState.racks[rid]["powered"])
		if GameState._rack_power_prev.has(rid) and bool(GameState._rack_power_prev[rid]) != now:
			var k := 0
			for i in range((GameState.racks[rid]["slots"] as Array).size()):
				var slot: Dictionary = GameState.racks[rid]["slots"][i]
				if str(slot.get("item_type", "")) == "" or str(slot.get("state", "ok")) != "ok":
					continue
				slot["offline"] = true
				slot.erase("boot_wait")
				if now and not GameState.is_slot_extended(rid, i):
					var t := get_boot_seconds(str(slot["item_type"]))
					slot["boot_left"] = t
					slot["boot_total"] = t
					slot["boot_wait"] = GameState.RACK_BOOT_FIRST + float(k) * GameState.RACK_BOOT_STAGGER
					k += 1
				else:
					slot.erase("boot_left")
					slot.erase("boot_total")
		GameState._rack_power_prev[rid] = now
	for old in GameState._rack_power_prev.keys():
		if not GameState.racks.has(old):
			GameState._rack_power_prev.erase(old)


## Hält den Stromzustand aller Einschübe passend zur Schiene (nur Host).
static func _refresh_slot_power() -> void:
	# Meist ist kein Schacht ausgefahren: dann gar nicht erst Schlüssel bauen.
	var any_open := not GameState.shared_open_panels.is_empty()
	for rid in GameState.racks.keys():
		var slots: Array = GameState.racks[rid]["slots"]
		for i in range(slots.size()):
			var slot: Dictionary = slots[i]
			if str(slot.get("item_type", "")) == "":
				continue
			if any_open and GameState.is_slot_extended(str(rid), i):
				slot["offline"] = true
				slot.erase("boot_left")
				slot.erase("boot_total")
				slot.erase("boot_wait")
			elif bool(slot.get("offline", false)):
				if str(slot.get("state", "ok")) != "ok":
					slot.erase("boot_left")
					slot.erase("boot_total")
				elif not slot.has("boot_left"):
					var t := get_boot_seconds(str(slot["item_type"]))
					slot["boot_left"] = t
					slot["boot_total"] = t


static func _update_slot_boot(dt: float) -> void:
	var done := false
	var woke := false
	for rid in GameState.racks.keys():
		if not bool(GameState.racks[rid].get("powered", false)):
			continue
		for slot_v in GameState.racks[rid]["slots"]:
			var slot: Dictionary = slot_v
			if not slot.has("boot_left"):
				continue
			if float(slot.get("boot_wait", 0.0)) > 0.0:
				slot["boot_wait"] = float(slot["boot_wait"]) - dt
				if float(slot["boot_wait"]) <= 0.0:
					slot.erase("boot_wait")
					woke = true
				continue
			slot["boot_left"] = float(slot["boot_left"]) - dt
			if float(slot["boot_left"]) <= 0.0:
				slot.erase("boot_left")
				slot.erase("boot_total")
				slot.erase("offline")
				done = true
	if done:
		GameState._recalculate_networks_and_metrics()
		GameState._broadcast_racks()
		GameState._broadcast_sim_tick()
	elif woke:
		GameState._broadcast_racks()


## Zufällige Netzausfälle der Stadtwerke (nur Host). Der Hauptschalter fällt ab, die USV überbrückt,
## und nach Ablauf kommt das Netz von selbst zurück.
static func _tick_grid_outage(dt: float) -> void:
	if GameState.grid_outage_left > 0.0:
		GameState.grid_outage_left = maxf(0.0, GameState.grid_outage_left - dt)
		if GameState.grid_outage_left <= 0.0:
			_end_grid_outage()
		return
	if GameState.day_number < GameState.GRID_OUTAGE_FIRST_DAY:
		return
	if GameState._grid_outage_cooldown < 0.0:
		GameState._grid_outage_cooldown = _roll_grid_outage_cooldown()
	GameState._grid_outage_cooldown -= dt
	if GameState._grid_outage_cooldown <= 0.0:
		GameState._grid_outage_cooldown = _roll_grid_outage_cooldown()
		_start_grid_outage(randf_range(GameState.GRID_OUTAGE_MIN_SEC, GameState.GRID_OUTAGE_MAX_SEC))


## Sekunden bis zum nächsten geplanten Netzausfall (0 = unbekannt). Nur auf dem Host gültig.
static func get_next_outage_in() -> float:
	if GameState.day_number < GameState.GRID_OUTAGE_FIRST_DAY or GameState.grid_outage_left > 0.0:
		return 0.0
	return maxf(0.0, GameState._grid_outage_cooldown)


static func _roll_grid_outage_cooldown() -> float:
	return randf_range(0.8, 2.2) * float(GameState.DAY_LENGTH_SECONDS) / maxf(GameState.diff("events"), 0.1)


## Restdauer des Netzausfalls in Spielminuten (für HUD und Hinweise).
static func get_grid_outage_minutes() -> int:
	if GameState.grid_outage_left <= 0.0:
		return 0
	return maxi(1, roundi(GameState.grid_outage_left / float(GameState.DAY_LENGTH_SECONDS) * 1440.0))


static func _broadcast_power_change() -> void:
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()


static func _start_grid_outage(duration: float) -> void:
	# Seit GAME-01 übernehmen Aggregate nicht mehr sofort: Sie springen nach einigen Sekunden an
	# (Operations.tick_generators), die USV muss bis dahin überbrücken.
	GameState._grid_breaker_restore = GameState.breaker_on
	GameState.grid_outage_left = duration
	GameState.breaker_on = false
	GameState.overload_timer = 0.0
	_broadcast_power_change()
	GameState._rpc_play_sfx.rpc("power_down")
	var minutes := get_grid_outage_minutes()
	if GameState.ups_backup_active:
		GameState._rpc_play_sfx.rpc("ups_beep")
		GameState.post_event_f("NETZAUSFALL! Die Stadtwerke melden eine Störung (ca. %d Min.). USV-Notstrom hat übernommen.", [minutes], "warn")
	else:
		GameState.post_event_f("NETZAUSFALL! Die Stadtwerke melden eine Störung (ca. %d Min.). Ohne USV steht alles still.", [minutes], "alert")


static func _end_grid_outage() -> void:
	GameState.grid_outage_left = 0.0
	var restore := GameState._grid_breaker_restore and has_working_fuse()
	GameState._grid_breaker_restore = false
	if restore:
		GameState.breaker_on = true
		GameState.overload_timer = 0.0
	_broadcast_power_change()
	if restore:
		GameState._rpc_play_sfx.rpc("breaker_on")
		GameState.post_event("Netz wieder da: Die Stadtwerke haben die Störung behoben, der Strom läuft wieder.", "good")
	else:
		GameState.post_event("Netz wieder da. Der Hauptschalter ist aus und muss von Hand eingeschaltet werden.", "info")


static func _rpc_req_toggle_breaker() -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if not GameState.breaker_on and GameState.grid_outage_left > 0.0:
		# Wunsch merken: Nach dem Netzausfall schaltet der Hauptschalter wieder ein.
		GameState._grid_breaker_restore = true
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Hauptschalter bleibt aus: Netzausfall der Stadtwerke. Der Strom kommt automatisch zurück.", "warn")
		return
	if not GameState.breaker_on and not has_working_fuse():
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Hauptschalter lässt sich nicht einschalten: Im Sicherungskasten steckt keine intakte Sicherung.", "warn")
		return
	GameState.breaker_on = not GameState.breaker_on
	GameState.overload_timer = 0.0
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_coolers()
	GameState._broadcast_ups()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("breaker_on" if GameState.breaker_on else "breaker_trip")
	GameState.post_event_f("%s hat die Hauptsicherung EINGESCHALTET." if GameState.breaker_on else "%s hat die Hauptsicherung ABGESCHALTET.", [
		NetworkManager.get_player_name(peer_id),
	], "good" if GameState.breaker_on else "warn")


static func _rpc_req_upgrade_power() -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "expand"):
		return
	if GameState.power_fuse_stock > 0:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Die Drehsicherung liegt schon im Lager. Setze sie am Sicherungskasten in F2 ein.", "warn")
		return
	if _power_fuse_on_way():
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Die Drehsicherung ist schon bestellt und kommt mit dem Lieferwagen.", "warn")
		return
	if GameState.power_tier + 1 >= GameState.POWER_TIERS.size():
		return
	var next_tier: Dictionary = GameState.POWER_TIERS[GameState.power_tier + 1]
	var cost := float(next_tier["cost"])
	if GameState.money < cost:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= cost
	# Wie beim Warenkorb: Zubehör kommt ins Sammelpaket des Lieferwagens.
	if GameState.van_phase != "arriving":
		GameState.pending_delivery_items.append(GameState.POWER_FUSE_ACC)
	else:
		GameState._van_parcel_parts.append(GameState.POWER_FUSE_ACC)
		if not GameState.van_cargo.has(GameState.VAN_PARCEL_ITEM):
			GameState.van_cargo.push_front(GameState.VAN_PARCEL_ITEM)
	GameState._broadcast_van_state()
	GameState._broadcast_fuses()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")
	GameState.post_event_f("%s hat eine Drehsicherung für %s bestellt. Sie kommt mit dem Lieferwagen im Sammelpaket.", [
		NetworkManager.get_player_name(peer_id), str(next_tier["label"])
	], "good")


# ==============================================================================
# SICHERUNGSKASTEN: Sicherungen kaufen, einsetzen, bei Überlast durchbrennen lassen
# ==============================================================================
static func _make_fuse_slots(state: String) -> Array:
	var arr: Array = []
	for _i in range(GameState.FUSE_SLOT_COUNT):
		arr.append(state)
	return arr


static func _sanitize_fuses(data: Variant) -> Array:
	if not (data is Array):
		return _make_fuse_slots("ok")
	var src: Array = data
	var arr: Array = []
	for i in range(GameState.FUSE_SLOT_COUNT):
		var s := str(src[i]) if i < src.size() else "empty"
		arr.append(s if s == "ok" or s == "blown" else "empty")
	return arr


static func count_working_fuses() -> int:
	var n := 0
	for f in GameState.breaker_fuses:
		if str(f) == "ok":
			n += 1
	return n


## Der Hauptschalter lässt sich nur einschalten, solange mindestens eine intakte Sicherung steckt.
static func has_working_fuse() -> bool:
	return count_working_fuses() > 0


## Die Kastentür muss offen sein, bevor Sicherungen und der Hauptschalter bedient werden können.
static func is_breaker_door_open() -> bool:
	return GameState.shared_open_panels.has(GameState._panel_key(GameState.WALL_BREAKER_ID, "breaker:door"))


static func _blow_random_fuse() -> void:
	var ok_idx: Array[int] = []
	for i in range(GameState.breaker_fuses.size()):
		if str(GameState.breaker_fuses[i]) == "ok":
			ok_idx.append(i)
	if ok_idx.is_empty():
		return
	GameState.breaker_fuses[ok_idx[randi() % ok_idx.size()]] = "blown"
	GameState._broadcast_fuses()


## Server: sucht die Drehsicherung in allen Lieferwarteschlangen.
static func _power_fuse_on_way() -> bool:
	return GameState.pending_delivery_items.has(GameState.POWER_FUSE_ACC) \
		or GameState.van_cargo.has(GameState.POWER_FUSE_ACC) \
		or GameState._van_parcel_parts.has(GameState.POWER_FUSE_ACC)


## Für die UI: Ist die Drehsicherung bestellt, aber noch nicht geliefert?
static func is_power_fuse_on_way() -> bool:
	if GameState.multiplayer.is_server():
		return _power_fuse_on_way()
	return GameState.power_fuse_on_way_synced


static func _rpc_req_buy_fuse() -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState.money < float(GameState.FUSE_PRICE):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	GameState.money -= float(GameState.FUSE_PRICE)
	GameState.fuse_stock += 1
	GameState._broadcast_fuses()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("cash")


static func _rpc_req_insert_fuse(slot_idx: int) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if slot_idx < 0 or slot_idx >= GameState.breaker_fuses.size():
		return
	if slot_idx == GameState.POWER_FUSE_SLOT and GameState.power_fuse_stock > 0:
		_install_power_fuse(peer_id)
		return
	if str(GameState.breaker_fuses[slot_idx]) == "ok":
		return
	if GameState.fuse_stock <= 0:
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Keine Sicherung im Lager. Kaufe Sicherungen am PC im Shop unter \"Klima & USV\".", "warn")
		return
	GameState.fuse_stock -= 1
	GameState.breaker_fuses[slot_idx] = "ok"
	GameState._broadcast_fuses()
	GameState._rpc_play_sfx.rpc("pickup")
	GameState.post_event_f("%s hat eine Sicherung in Steckplatz %d eingesetzt.", [
		NetworkManager.get_player_name(peer_id), slot_idx + 1,
	], "good")


## Setzt die gekaufte Drehsicherung in F2 ein: Stromstufe +1, die alte Sicherung landet in der Hand.
static func _install_power_fuse(peer_id: int) -> void:
	if GameState.power_tier + 1 >= GameState.POWER_TIERS.size():
		GameState.power_fuse_stock = 0
		GameState._broadcast_fuses()
		return
	if GameState.is_player_holding_anything(peer_id):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		GameState.post_event("Hände frei machen: Die alte Sicherung wird dir beim Einsetzen in die Hand gegeben.", "warn")
		return
	GameState.power_fuse_stock = 0
	GameState.power_tier += 1
	var cid := GameState._alloc_id("crate")
	GameState.crates[cid] = {"id": cid, "item_type": GameState.OLD_FUSE_ITEM, "pos": Vector3.ZERO, "held_by": peer_id, "held_slot": GameState.get_active_slot(peer_id)}
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_fuses()
	GameState._broadcast_crates()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("upgrade")
	GameState.post_event_f("%s hat die Drehsicherung in F2 eingesetzt: Stromversorgung jetzt %s!", [
		NetworkManager.get_player_name(peer_id), str(GameState.POWER_TIERS[GameState.power_tier]["label"])
	], "good")
