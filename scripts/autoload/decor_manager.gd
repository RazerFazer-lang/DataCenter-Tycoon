extends Node
## Zweck der Einrichtung: Kaffee, Wasser, Sofa-Pause, Werkzeugwagen, Luftentfeuchter, Leuchtschild,
## Kaltgang zwischen zwei Portalen, Kamera-Warnungen und nächtliche Diebe. Der Host rechnet.

signal buffs_changed
signal thief_changed

const COFFEE_SECS := 180.0
const COFFEE_COST := 4.0
const WATER_SECS := 90.0
const REST_SECS := 240.0
const REST_SIT_TIME := 6.0
const COFFEE_WALK := 0.15
const WATER_WALK := 0.08
const COFFEE_WORK := 0.80
const REST_WORK := 0.87
const TOOL_CART_WORK := 0.85
const TOOL_CART_RADIUS := 4.0
const TOOL_CART_SLOTS := 6
const DEHUM_RADIUS := 6.0
const DEHUM_DUST := 0.6
## Echte Sekunden, bis der Tank voll ist (1,5 Spieltage).
const DEHUM_FULL_SECS := 2160.0
const AISLE_RELIEF := 6.0
const AISLE_MIN := 2.0
const AISLE_MAX := 9.0
const AISLE_SIDE := 1.95
const SIGN_COLORS: Array[Color] = [Color(0.24, 0.62, 1.0), Color(0.20, 0.92, 0.62), Color(1.0, 0.62, 0.18), Color(0.96, 0.30, 0.62), Color(0.94, 0.96, 1.0)]
const SIGN_GROWTH := 0.06
const CAM_RANGE := 14.0
const CAM_HEAT_WARN := 66.0
const CAM_SMOKE_WARN := 78.0

const THIEF_LEVEL := 2
const THIEF_CHANCE := 0.40
const THIEF_CAM_FACTOR := 0.35
const THIEF_WALK := 1.7
const THIEF_RUN := 4.3
const THIEF_GRAB := 2.2
const THIEF_CATCH := 1.7
const THIEF_START := Vector3(-15.0, 0.0, 12.0)

## Spieler -> {"coffee": s, "water": s, "rest": s} Restzeit.
var buffs: Dictionary = {}
## Laufender Dieb: {"phase", "path", "dur", "t", "crate", "carry", "label"}. Leer = keiner.
var thief: Dictionary = {}
## Wird von der Welt gesetzt, damit der Host die Spielerpositionen kennt.
var world: Node = null

var _clock := 0.0
var _last_day := -1
var _was_active := false
var _warned: Dictionary = {}
var _night_done := -1
var _night_at := -1.0
var _dehum_accum := 0.0
var _cam_accum := 0.0
var _aisles: Array = []
var _aisles_dirty := true


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	GameState.decor_items_changed.connect(func(): _aisles_dirty = true)


func reset() -> void:
	buffs.clear()
	thief = {}
	_warned.clear()
	_last_day = -1
	_night_done = -1
	_night_at = -1.0
	_aisles_dirty = true
	buffs_changed.emit()
	thief_changed.emit()


func _process(delta: float) -> void:
	var active: bool = NetworkManager.is_in_session and GameState.is_active
	if not active:
		if _was_active:
			_was_active = false
			reset()
		return
	_was_active = true
	_clock += delta
	_tick_buffs(delta)
	if not thief.is_empty():
		thief["t"] = float(thief.get("t", 0.0)) + delta
	if not multiplayer.is_server() or GameState.is_world_paused_for_empty_server():
		return
	tick(delta)


# ---------------------------------------------------------------- Netzwerk

func _online() -> bool:
	return NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and NetworkManager.is_in_session:
		_rpc_sync.rpc_id(peer_id, buffs, thief)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(b: Dictionary, th: Dictionary) -> void:
	buffs = b.duplicate(true)
	thief = th.duplicate(true)
	buffs_changed.emit()
	thief_changed.emit()


func _broadcast() -> void:
	buffs_changed.emit()
	thief_changed.emit()
	if _online():
		_rpc_sync.rpc(buffs, thief)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


# ---------------------------------------------------------------- Stärkungen

func _tick_buffs(delta: float) -> void:
	var changed := false
	for p in buffs.keys():
		var b: Dictionary = buffs[p]
		for k in b.keys():
			b[k] = float(b[k]) - delta
			if float(b[k]) <= 0.0:
				b.erase(k)
				changed = true
		if b.is_empty():
			buffs.erase(p)
	if changed:
		buffs_changed.emit()


func has_buff(peer: int, kind: String) -> bool:
	return float((buffs.get(peer, {}) as Dictionary).get(kind, 0.0)) > 0.0


func get_buffs(peer: int) -> Dictionary:
	return buffs.get(peer, {})


func add_buff(peer: int, kind: String, secs: float) -> void:
	var b: Dictionary = buffs.get(peer, {})
	b[kind] = secs
	buffs[peer] = b
	_broadcast()


func walk_mult(peer: int) -> float:
	var m := 1.0
	if has_buff(peer, "coffee"):
		m += COFFEE_WALK
	if has_buff(peer, "water"):
		m += WATER_WALK
	return m


## Faktor für die Dauer von Handgriffen (kleiner = schneller).
func work_mult(peer: int, at: Vector3) -> float:
	var m := 1.0
	if has_buff(peer, "coffee"):
		m *= COFFEE_WORK
	if has_buff(peer, "rest"):
		m *= REST_WORK
	if near_type("prop_tool_cart", at, TOOL_CART_RADIUS):
		m *= TOOL_CART_WORK
	return m


# ---------------------------------------------------------------- Abfragen

func each_of(item_type: String) -> Array:
	var out: Array = []
	for d in GameState.decor_items.values():
		if str((d as Dictionary).get("item_type", "")) == item_type:
			out.append(d)
	return out


func near_type(item_type: String, at: Vector3, radius: float) -> bool:
	for d in each_of(item_type):
		if ((d as Dictionary)["pos"] as Vector3).distance_to(at) <= radius:
			return true
	return false


func has_power() -> bool:
	return GameState.breaker_on or GameState.ups_backup_active


## Schnellere Mitarbeiter durch Sofa und Wasserspender.
func staff_speed() -> float:
	return 1.0 + (0.08 if not each_of("prop_sofa").is_empty() else 0.0) + (0.03 if not each_of("prop_water").is_empty() else 0.0)


func growth_bonus() -> float:
	if not has_power():
		return 0.0
	for d in each_of("prop_logo_sign"):
		if not bool((d as Dictionary).get("off", false)):
			return SIGN_GROWTH
	return 0.0


func is_dehum_running(d: Dictionary) -> bool:
	return has_power() and float(d.get("tank", 0.0)) < 1.0


func dust_factor(at: Vector3) -> float:
	for d in each_of("prop_dehumidifier"):
		if is_dehum_running(d) and ((d as Dictionary)["pos"] as Vector3).distance_to(at) <= DEHUM_RADIUS:
			return DEHUM_DUST
	return 1.0


func leak_factor() -> float:
	for d in each_of("prop_dehumidifier"):
		if is_dehum_running(d):
			return 2.0
	return 1.0


func has_camera(at: Vector3) -> bool:
	return has_power() and near_type("prop_cctv_monitor", at, CAM_RANGE)


## Kaltgänge: zwei Portale, die sich gegenüberstehen. [a, b, Richtung]
func get_aisles() -> Array:
	if not _aisles_dirty:
		return _aisles
	_aisles_dirty = false
	_aisles = []
	var gates := each_of("prop_cold_aisle_gate")
	for i in gates.size():
		for j in range(i + 1, gates.size()):
			var a: Vector3 = gates[i]["pos"]
			var b: Vector3 = gates[j]["pos"]
			var ra := float(gates[i].get("rot_y", 0.0))
			var diff := absf(angle_difference(ra, float(gates[j].get("rot_y", 0.0))))
			if diff > 0.15 and absf(diff - PI) > 0.15:
				continue
			var n := Vector3(sin(ra), 0.0, cos(ra))
			var v := b - a
			var along := absf(v.dot(n))
			if along < AISLE_MIN or along > AISLE_MAX or (v - n * v.dot(n)).length() > 0.6:
				continue
			_aisles.append([a, b, v.normalized()])
	return _aisles


func aisle_relief(at: Vector3) -> float:
	for g in get_aisles():
		var a: Vector3 = g[0]
		var dir: Vector3 = g[2]
		var len: float = (g[1] as Vector3).distance_to(a)
		var rel := at - a
		rel.y = 0.0
		var t := rel.dot(dir)
		if t < -0.2 or t > len + 0.2:
			continue
		if (rel - dir * t).length() <= AISLE_SIDE:
			return AISLE_RELIEF
	return 0.0


# ---------------------------------------------------------------- Benutzen

func request_use(did: String) -> void:
	_rpc_use.rpc_id(1, did)


func request_rest(did: String) -> void:
	_rpc_rest.rpc_id(1, did)


## Text für den Hinweis am Fadenkreuz: [Hauptzeile, Nebenzeile]
func prompt_for(did: String) -> Array:
	var d: Dictionary = GameState.decor_items.get(did, {})
	var sub := tr("[F] Umsetzen oder verkaufen")
	match str(d.get("item_type", "")):
		"prop_vending_lounge":
			if not has_power():
				return [tr("Automat: kein Strom"), sub]
			return [tr("[E] Kaffee kaufen ($%d): 3 Minuten schneller laufen und arbeiten") % int(COFFEE_COST), sub]
		"prop_water":
			return [tr("[E] Wasser trinken: 90 Sekunden schneller zu Fuß"), sub]
		"prop_sofa":
			return [tr("[E] Hinsetzen und Pause machen"), sub]
		"prop_tool_cart":
			var held: Dictionary = GameState.get_player_held_crate(multiplayer.get_unique_id())
			var n := kit_count(d)
			if GameState.is_repair_kit(str(held.get("item_type", ""))):
				return [tr("[E] %s in den Werkzeugwagen legen (%d/%d)") % [GameState.get_crate_display_label(held), n, TOOL_CART_SLOTS], sub]
			var first := _first_kit(d)
			if first >= 0:
				return [tr("[E] %s aus dem Werkzeugwagen nehmen (%d/%d)") % [GameState.get_crate_display_label((d["kits"] as Array)[first]), n, TOOL_CART_SLOTS], sub]
			return [tr("Werkzeugwagen (leer): Platz für %d Reparatur-Kits") % TOOL_CART_SLOTS, sub]
		"prop_dehumidifier":
			var tank := int(float(d.get("tank", 0.0)) * 100.0)
			if tank >= 100:
				return [tr("[E] Tank leeren (voll, Gerät steht)"), sub]
			return [tr("[E] Tank leeren (%d %% voll)") % tank, sub]
		"prop_logo_sign":
			return [tr("[E] Farbe wechseln / ausschalten"), sub]
		"prop_cctv_monitor":
			return [tr("Kamera läuft: Live-Bild in der Kamera-App am PC") if has_power() else tr("Kamera: kein Strom"), sub]
		"prop_cold_aisle_gate":
			for g in get_aisles():
				if (g[0] as Vector3).distance_to(d["pos"]) < 0.1 or (g[1] as Vector3).distance_to(d["pos"]) < 0.1:
					return [tr("Kaltgang geschlossen: Racks dazwischen bleiben 6 °C kühler"), sub]
			return [tr("Kaltgang-Portal: stell ein zweites gegenüber auf (2 bis 9 m)"), sub]
	return [tr(GameState.get_decor_name(did)), sub]


func kit_count(d: Dictionary) -> int:
	var n := 0
	for k in d.get("kits", []):
		if k is Dictionary:
			n += 1
	return n


func _first_kit(d: Dictionary) -> int:
	var arr: Array = d.get("kits", [])
	for i in arr.size():
		if arr[i] is Dictionary:
			return i
	return -1


@rpc("any_peer", "call_local", "reliable")
func _rpc_use(did: String) -> void:
	if multiplayer.is_server():
		do_use(did, _sender())


func do_use(did: String, peer: int) -> void:
	if not GameState.decor_items.has(did) or not SecurityGuard.check_rate_limit(peer, "decor_use", 12, 4.0):
		return
	var d: Dictionary = GameState.decor_items[did]
	match str(d.get("item_type", "")):
		"prop_vending_lounge":
			if not has_power() or GameState.money < COFFEE_COST or float(get_buffs(peer).get("coffee", 0.0)) > COFFEE_SECS - 10.0:
				GameState._rpc_play_sfx.rpc_id(peer, "error")
				return
			FinanceManager.debit_public(COFFEE_COST, "Kaffee")
			add_buff(peer, "coffee", COFFEE_SECS)
			GameState._rpc_play_sfx.rpc("coffee")
			GameState._broadcast_sim_tick()
		"prop_water":
			add_buff(peer, "water", WATER_SECS)
			GameState._rpc_play_sfx.rpc("water_pour")
		"prop_tool_cart":
			_use_tool_cart(d, peer)
		"prop_dehumidifier":
			if float(d.get("tank", 0.0)) < 0.05:
				GameState._rpc_play_sfx.rpc_id(peer, "error")
				return
			d["tank"] = 0.0
			GameState._broadcast_decor_items()
			GameState._rpc_play_sfx.rpc("water_pour")
			GameState.post_event_f("%s hat den Luftentfeuchter geleert.", [NetworkManager.get_player_name(peer)], "good")
		"prop_logo_sign":
			if bool(d.get("off", false)):
				d["off"] = false
				d["color_i"] = 0
			else:
				var ci := int(d.get("color_i", 0)) + 1
				if ci >= SIGN_COLORS.size():
					d["off"] = true
				else:
					d["color_i"] = ci
			GameState._broadcast_decor_items()
			GameState._rpc_play_sfx.rpc("click")


func _use_tool_cart(d: Dictionary, peer: int) -> void:
	var kits: Array = d.get("kits", [])
	while kits.size() < TOOL_CART_SLOTS:
		kits.append(null)
	var held: Dictionary = GameState.get_player_held_crate(peer)
	if not held.is_empty():
		var slot := kits.find(null)
		if slot < 0 or not GameState.is_repair_kit(str(held.get("item_type", ""))) or int(held.get("pack_count", 1)) > 1:
			GameState._rpc_play_sfx.rpc_id(peer, "error")
			return
		var c: Dictionary = held.duplicate(true)
		c["held_by"] = 0
		c["pos"] = Vector3.ZERO
		kits[slot] = c
		GameState.crates.erase(str(held["id"]))
		GameState._rpc_play_sfx.rpc("drawer")
	else:
		d["kits"] = kits
		var i := _first_kit(d)
		if i < 0 or GameState.is_player_holding_anything(peer):
			GameState._rpc_play_sfx.rpc_id(peer, "error")
			return
		var taken: Dictionary = (kits[i] as Dictionary).duplicate(true)
		kits.remove_at(i)
		kits.append(null)
		var cid: String = GameState._alloc_id("crate")
		taken["id"] = cid
		taken["held_by"] = peer
		taken["held_slot"] = GameState.get_active_slot(peer)
		GameState.crates[cid] = taken
		GameState._rpc_play_sfx.rpc("drawer")
	d["kits"] = kits
	GameState._broadcast_crates()
	GameState._broadcast_decor_items()
	GameState.shelf_changed.emit()


@rpc("any_peer", "call_local", "reliable")
func _rpc_rest(did: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if str((GameState.decor_items.get(did, {}) as Dictionary).get("item_type", "")) != "prop_sofa" or not SecurityGuard.check_rate_limit(peer, "rest", 2, 8.0):
		return
	add_buff(peer, "rest", REST_SECS)


# ---------------------------------------------------------------- Simulation (nur Host)

func tick(delta: float) -> void:
	var today: int = GameState.day_number
	if _last_day < 0:
		_last_day = today
	while _last_day < today:
		_last_day += 1
		run_day()
	_dehum_accum += delta
	if _dehum_accum >= 5.0:
		_tick_dehumidifiers(_dehum_accum)
		_dehum_accum = 0.0
	_cam_accum += delta
	if _cam_accum >= 2.0:
		_cam_accum = 0.0
		_tick_cameras()
	_tick_thief(delta)


func run_day() -> void:
	var rep := 0.0
	if not each_of("prop_vending_lounge").is_empty():
		rep += 0.8
	if not each_of("prop_sofa").is_empty():
		rep += 0.5
	if not each_of("prop_water").is_empty():
		rep += 0.3
	if growth_bonus() > 0.0:
		rep += 0.6
	if rep > 0.0 and GameState.reputation < 85.0:
		GameState.reputation = minf(85.0, GameState.reputation + rep)
	if not each_of("prop_parts_cabinet").is_empty():
		GameState.bench_screws = mini(GameState.BENCH_SCREWS_MAX, GameState.bench_screws + 12)
		GameState.bench_paste = minf(GameState.BENCH_PASTE_MAX, GameState.bench_paste + 1.0)
		GameState._rpc_sync_bench_supplies.rpc(GameState.bench_screws, GameState.bench_paste)


func _tick_dehumidifiers(dt: float) -> void:
	var dirty := false
	for d in each_of("prop_dehumidifier"):
		if not is_dehum_running(d):
			continue
		var before := int(float(d.get("tank", 0.0)) * 20.0)
		d["tank"] = minf(1.0, float(d.get("tank", 0.0)) + dt / DEHUM_FULL_SECS)
		if int(float(d["tank"]) * 20.0) != before:
			dirty = true
		if float(d["tank"]) >= 1.0:
			GameState.post_event("Der Luftentfeuchter ist voll und hat abgeschaltet. Tank mit [E] leeren.", "warn")
	if dirty:
		GameState._broadcast_decor_items()


## Kameras sehen Hitze und Rauch früher als die normale Meldung.
func _tick_cameras() -> void:
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		var t := float(r.get("temp", 22.0))
		var key := str(rid)
		if t < CAM_HEAT_WARN - 6.0:
			_warned.erase(key)
			continue
		var lvl := 2 if t >= CAM_SMOKE_WARN else (1 if t >= CAM_HEAT_WARN else 0)
		if lvl <= int(_warned.get(key, 0)) or not has_camera(r["pos"]):
			continue
		_warned[key] = lvl
		if lvl == 1:
			GameState.post_event_f("📹 Kamera: %s wird heiß (%.0f °C).", [GameState.get_rack_display_name(key), t], "warn")
		else:
			GameState.post_event_f("📹 Kamera: Rauch an %s (%.0f °C)! Gleich brennt es.", [GameState.get_rack_display_name(key), t], "alert")
		GameState._rpc_play_sfx.rpc("ticket_notify")


# ---------------------------------------------------------------- Diebe

func is_night() -> bool:
	return GameState.time_of_day > 0.92 or GameState.time_of_day < 0.18


## Kisten, an die ein Dieb herankommt: draußen immer, drinnen nur bei offenem Tor nahe am Eingang.
func thief_targets() -> Array:
	var out: Array = []
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if int(c.get("held_by", 0)) != 0 or str(c.get("item_type", "")) == "empty_carton":
			continue
		var p: Vector3 = c["pos"]
		if p.z < -50.0 or absf(p.x) > 3.6:
			continue
		if p.z > 4.6 and p.z < 10.5:
			out.append(cid)
		elif GameState.garage_door_open and p.z > 2.2 and absf(p.x) < 2.4:
			out.append(cid)
	return out


func _tick_thief(_delta: float) -> void:
	if not thief.is_empty():
		_run_thief()
		return
	if not is_night():
		_night_at = -1.0
		return
	var night: int = GameState.day_number + (1 if GameState.time_of_day > 0.5 else 0)
	if _night_done == night:
		return
	if _night_at < 0.0:
		_night_at = _clock + randf_range(20.0, 160.0)
		return
	if _clock < _night_at:
		return
	_night_done = night
	if GameState.get_company_level() < THIEF_LEVEL:
		return
	var targets := thief_targets()
	if targets.is_empty():
		return
	var chance := THIEF_CHANCE
	if has_camera(Vector3(0.0, 0.0, 6.0)):
		chance *= THIEF_CAM_FACTOR
	if not GameState.garage_door_open:
		chance *= 0.75
	if randf() < chance:
		start_thief(str(targets[randi() % targets.size()]))


func start_thief(cid: String) -> void:
	var p: Vector3 = GameState.crates[cid]["pos"]
	var gate := Vector3(clampf(p.x, -2.2, 2.2), 0.0, 10.8)
	var at := Vector3(p.x, 0.0, p.z + 0.55)
	thief = {"phase": "in", "path": [THIEF_START, gate, at], "t": 0.0, "crate": cid, "carry": {}, "label": GameState.get_crate_display_label(GameState.crates[cid])}
	thief["dur"] = _path_len(thief["path"]) / THIEF_WALK
	if has_camera(Vector3(0.0, 0.0, 6.0)):
		GameState.post_event("📹 Kamera: Jemand schleicht an der Lieferzone herum! Lauf hin, um ihn zu verjagen.", "alert")
		GameState._rpc_play_sfx.rpc("alarm")
	_broadcast()


func _path_len(path: Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += (path[i] as Vector3).distance_to(path[i - 1])
	return maxf(0.1, l)


func thief_pos() -> Vector3:
	var path: Array = thief.get("path", [])
	if path.is_empty():
		return THIEF_START
	var want := _path_len(path) * clampf(float(thief["t"]) / maxf(0.1, float(thief["dur"])), 0.0, 1.0)
	for i in range(1, path.size()):
		var seg := (path[i] as Vector3).distance_to(path[i - 1])
		if want <= seg and seg > 0.001:
			return (path[i - 1] as Vector3).lerp(path[i], want / seg)
		want -= seg
	return path[path.size() - 1]


func _player_near(p: Vector3, dist: float) -> int:
	if world == null or not is_instance_valid(world):
		return 0
	var nodes: Dictionary = world.get("_player_nodes")
	for pid in nodes.keys():
		var n: Variant = nodes[pid]
		if is_instance_valid(n) and Vector2((n as Node3D).position.x - p.x, (n as Node3D).position.z - p.z).length() < dist:
			return int(pid)
	return 0


func _run_thief() -> void:
	var pos := thief_pos()
	var who := _player_near(pos, THIEF_CATCH)
	if who != 0 and str(thief["phase"]) != "flee":
		catch_thief(who)
		return
	if float(thief["t"]) < float(thief["dur"]):
		return
	var cid := str(thief["crate"])
	match str(thief["phase"]):
		"in":
			if not GameState.crates.has(cid) or int(GameState.crates[cid].get("held_by", 0)) != 0:
				_flee(pos)
				return
			thief.merge({"phase": "grab", "path": [pos, pos], "t": 0.0, "dur": THIEF_GRAB}, true)
			_broadcast()
		"grab":
			if not GameState.crates.has(cid) or int(GameState.crates[cid].get("held_by", 0)) != 0:
				_flee(pos)
				return
			thief["carry"] = (GameState.crates[cid] as Dictionary).duplicate(true)
			GameState.crates.erase(cid)
			GameState._broadcast_crates()
			_go_out(pos, "out")
		"out":
			_stolen()
		_:
			thief = {}
			_broadcast()


func _go_out(pos: Vector3, phase: String) -> void:
	var path := [pos, Vector3(clampf(pos.x, -2.2, 2.2), 0.0, 10.8), THIEF_START]
	thief.merge({"phase": phase, "path": path, "t": 0.0, "dur": _path_len(path) / THIEF_RUN}, true)
	_broadcast()


func _flee(pos: Vector3) -> void:
	_go_out(pos, "flee")


func catch_thief(peer: int) -> void:
	var pos := thief_pos()
	var carry: Dictionary = thief.get("carry", {})
	if not carry.is_empty():
		var cid: String = GameState._alloc_id("crate")
		carry["id"] = cid
		carry["held_by"] = 0
		carry["pos"] = GameState._clamp_drop_pos(Vector3(clampf(pos.x, -3.4, 3.4), 0.0, minf(pos.z, 10.0)))
		GameState.crates[cid] = carry
		thief["carry"] = {}
		GameState._broadcast_crates()
	GameState.reputation = minf(100.0, GameState.reputation + 0.5)
	GameState.post_event_f("🏃 %s hat den Dieb verjagt!", [NetworkManager.get_player_name(peer)], "good")
	GameState._rpc_play_sfx.rpc("whistle")
	_flee(pos)


func _stolen() -> void:
	var carry: Dictionary = thief.get("carry", {})
	thief = {}
	_broadcast()
	if carry.is_empty():
		return
	var it := str(carry.get("item_type", ""))
	var price := float((GameState.ITEM_CATALOG.get(it, {}) as Dictionary).get("price", 0)) * float(maxi(1, int(carry.get("pack_count", 1))))
	if it == "slot_build_box":
		price = float(GameState.calculate_slot_build_price(str((carry.get("build_data", {}) as Dictionary).get("mainboard_id", "")), (carry.get("build_data", {}) as Dictionary).get("components", {})))
	GameState.post_event_f("🦹 Diebstahl! '%s' wurde aus der Lieferzone gestohlen.", [GameState.get_crate_display_label(carry)], "alert")
	GameState._rpc_play_sfx.rpc("alarm")
	GameState._pay_insurance(roundf(price * 0.6), "Diebstahl")
	GameState._broadcast_sim_tick()
