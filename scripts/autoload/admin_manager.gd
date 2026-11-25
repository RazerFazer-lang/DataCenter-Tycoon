extends Node
## Admin-Befehle für den Host und von ihm freigeschaltete Mitspieler.
## Jeder Befehl läuft über den Host: Rechte, Werte und Ziele werden dort geprüft und protokolliert.
## Freischaltungen gelten nur für die laufende Sitzung und hängen an der Verbindung, nie am Namen.

signal rights_changed
signal log_changed
signal teleport_requested(pos: Vector3, yaw: float)

const LOG_MAX := 60
const RATE_HITS := 20
const RATE_WINDOW := 10.0
const WEATHERS: Array[String] = ["clear", "cloudy", "rain", "storm", "heatwave"]
const TIME_SCALES: Array[float] = [0.0, 1.0, 3.0, 10.0]
const SITES: Array[String] = ["garage", "halle_nord"]
## Befehle, die nur der Host selbst geben darf.
const HOST_ONLY: Array[String] = ["grant", "revoke"]
const COMMANDS: Array[String] = [
	"grant", "revoke", "kick", "ban", "goto", "bring", "send_site",
	"money_set", "money_add", "reputation", "level",
	"time", "next_day", "weather", "time_scale",
	"fire", "crash", "outage", "outage_end", "ddos", "repair_all", "clean_all",
	"give_item", "give_part", "deliver_now",
]

## Freigeschaltete Verbindungen (peer_id -> true). Der Host steht nie darin, er ist immer Admin.
var _granted: Dictionary = {}
## Neueste Einträge zuerst: {time, who, text, ok}
var log_entries: Array = []


func _ready() -> void:
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.disconnected_from_session.connect(func(_r: String): _reset())
	NetworkManager.connection_succeeded.connect(_reset)


func _reset() -> void:
	_granted.clear()
	log_entries.clear()
	rights_changed.emit()
	log_changed.emit()


func _on_player_left(peer_id: int) -> void:
	if not _is_host():
		return
	if _granted.has(peer_id):
		_granted.erase(peer_id)
		_sync_rights()


func _is_host() -> bool:
	return NetworkManager.is_in_session and multiplayer.multiplayer_peer != null and multiplayer.is_server()


func is_admin(peer_id: int) -> bool:
	if peer_id == 1:
		return true
	return _granted.has(peer_id)


## Darf dieser Spieler das Menü öffnen?
func is_local_admin() -> bool:
	if not NetworkManager.is_in_session or multiplayer.multiplayer_peer == null:
		return false
	return is_admin(multiplayer.get_unique_id())


func is_local_host() -> bool:
	return _is_host()


# ------------------------------------------------------------------ Befehl senden

func send(cmd: String, args: Dictionary = {}) -> void:
	if not is_local_admin():
		return
	_rpc_command.rpc_id(1, cmd, args)


@rpc("any_peer", "call_local", "reliable")
func _rpc_command(cmd: String, args: Dictionary) -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	execute(sender, cmd, args)


## Prüft und führt einen Befehl aus (nur Host). Gibt true zurück, wenn er ausgeführt wurde.
func execute(sender: int, cmd: String, args: Dictionary) -> bool:
	if not _is_host() or not GameState.is_active:
		return false
	if not is_admin(sender):
		# Nicht freigeschaltet: still ablehnen, aber für den Host festhalten (gedrosselt).
		if SecurityGuard.check_rate_limit(sender, "admin_denied", 2, 20.0):
			_log(sender, "Abgelehnt, keine Rechte: %s" % cmd.left(24), false)
		return false
	if not SecurityGuard.check_rate_limit(sender, "admin", RATE_HITS, RATE_WINDOW):
		return false
	if not COMMANDS.has(cmd) or args.size() > 4:
		return false
	if HOST_ONLY.has(cmd) and sender != 1:
		_log(sender, "Abgelehnt, nur Host: %s" % cmd, false)
		return false
	var text := _run(sender, cmd, args)
	if text == "":
		if _is_reachable(sender):
			GameState._rpc_play_sfx.rpc_id(sender, "error")
		return false
	_log(sender, text, true)
	return true


func _run(sender: int, cmd: String, args: Dictionary) -> String:
	match cmd:
		"grant", "revoke", "kick", "ban", "goto", "bring", "send_site":
			return _run_player(sender, cmd, args)
		"money_set":
			var v := _num(args, "v", 0.0, float(SecurityGuard.MAX_MONEY))
			if is_nan(v):
				return ""
			GameState.money = v
			GameState._broadcast_sim_tick()
			return "Geld auf $%d gesetzt" % int(v)
		"money_add":
			var d := _num(args, "v", -1.0e8, 1.0e8)
			if is_nan(d):
				return ""
			GameState.money = clampf(GameState.money + d, 0.0, float(SecurityGuard.MAX_MONEY))
			GameState._broadcast_sim_tick()
			return "Geld geändert: %+d $" % int(d)
		"reputation":
			var r := _num(args, "v", 0.0, 100.0)
			if is_nan(r):
				return ""
			GameState.reputation = r
			GameState._broadcast_sim_tick()
			return "Ruf auf %d gesetzt" % roundi(r)
		"level":
			var lv := _num(args, "v", 1.0, float(GameState.COMPANY_LEVEL_THRESHOLDS.size()))
			if is_nan(lv):
				return ""
			GameState.company_level = roundi(lv)
			GameState._broadcast_sim_tick()
			return "Firmenstufe auf %d gesetzt" % roundi(lv)
		"time", "next_day", "weather", "time_scale":
			return _run_world(cmd, args)
		"fire", "crash", "outage", "outage_end", "ddos", "repair_all", "clean_all":
			return _run_event(cmd)
		"give_item", "give_part", "deliver_now":
			return _run_items(cmd, args)
	return ""


# ------------------------------------------------------------------ Spieler

func _run_player(sender: int, cmd: String, args: Dictionary) -> String:
	var pid := int(_num(args, "peer", 1.0, 2147483647.0)) if not is_nan(_num(args, "peer", 1.0, 2147483647.0)) else 0
	if not NetworkManager.players.has(pid):
		return ""
	var pname := NetworkManager.get_player_name(pid)
	match cmd:
		"grant":
			if pid == 1 or _granted.has(pid):
				return ""
			_granted[pid] = true
			_sync_rights()
			GameState.post_event_f("🛡️ %s ist jetzt Admin für diese Sitzung.", [pname], "info")
			return "%s zum Admin gemacht" % pname
		"revoke":
			if not _granted.has(pid):
				return ""
			_granted.erase(pid)
			_sync_rights()
			GameState.post_event_f("🛡️ %s ist kein Admin mehr.", [pname], "info")
			return "%s die Admin-Rechte entzogen" % pname
		"kick", "ban":
			# Host und andere Admins sind geschützt. Nur der Host darf Admins entfernen.
			if pid == 1 or pid == sender or (is_admin(pid) and sender != 1):
				return ""
			if cmd == "kick":
				NetworkManager.kick_player(pid)
				return "%s gekickt" % pname
			NetworkManager.ban_player(pid)
			return "%s gebannt" % pname
		"goto":
			if pid == sender:
				return ""
			var tgt := _player_pos(pid)
			if tgt == Vector3.INF:
				return ""
			_teleport(sender, tgt + Vector3(0.9, 0.1, 0.0), 0.0)
			return "zu %s teleportiert" % pname
		"bring":
			if pid == sender:
				return ""
			var own := _player_pos(sender)
			if own == Vector3.INF:
				return ""
			_teleport(pid, own + Vector3(0.9, 0.1, 0.0), 0.0)
			return "%s hergeholt" % pname
		"send_site":
			var site := str(args.get("site", ""))
			if not SITES.has(site) or (site == "halle_nord" and not GameState.halle_nord_owned):
				return ""
			if site == "halle_nord":
				_teleport(pid, GameState.HALLE_NORD_ORIGIN + Vector3(3.2, 0.12, -4.2), 0.0)
				return "%s nach Halle Nord geschickt" % pname
			_teleport(pid, Vector3(-4.1, 0.12, -3.5), -PI * 0.5)
			return "%s in die Start-Garage geschickt" % pname
	return ""


func _player_pos(peer_id: int) -> Vector3:
	for n in get_tree().get_nodes_in_group("players"):
		if n is PlayerController and int((n as PlayerController).peer_id) == peer_id:
			return (n as PlayerController).position
	return Vector3.INF


func _teleport(peer_id: int, pos: Vector3, yaw: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		teleport_requested.emit(pos, yaw)
	else:
		_rpc_teleport.rpc_id(peer_id, pos, yaw)


@rpc("authority", "call_remote", "reliable")
func _rpc_teleport(pos: Vector3, yaw: float) -> void:
	teleport_requested.emit(pos, yaw)


# ------------------------------------------------------------------ Zeit und Wetter

func _run_world(cmd: String, args: Dictionary) -> String:
	match cmd:
		"time":
			var h := _num(args, "v", 0.0, 23.99)
			if is_nan(h):
				return ""
			GameState.time_of_day = clampf(h / 24.0, 0.0, 0.999)
			GameState._broadcast_sim_tick()
			return "Uhrzeit auf %02d:%02d gestellt" % [int(h), int(fmod(h, 1.0) * 60.0)]
		"next_day":
			GameState._day_rollover_pending = true
			GameState.time_of_day = 0.25
			GameState._broadcast_sim_tick()
			return "zum nächsten Tag gesprungen"
		"weather":
			var w := str(args.get("v", ""))
			if not WEATHERS.has(w):
				return ""
			GameState.weather_state = w
			GameState._weather_timer = 240.0
			GameState._broadcast_sim_tick()
			return "Wetter: %s" % w
		"time_scale":
			var s := _num(args, "v", 0.0, 10.0)
			if is_nan(s) or not TIME_SCALES.has(s):
				return ""
			GameState.clock_scale = s
			GameState._broadcast_sim_tick()
			return "Uhr läuft %dfach" % int(s) if s > 0.0 else "Uhr angehalten"
	return ""


# ------------------------------------------------------------------ Ereignisse

func _running_slots() -> Array:
	var out: Array = []
	for rid in GameState.racks.keys():
		if not bool(GameState.racks[rid].get("powered", false)):
			continue
		for s in GameState.racks[rid]["slots"]:
			if str((s as Dictionary).get("item_type", "")) != "" and GameState.is_slot_on(s):
				out.append([str(rid), s])
	return out


func _run_event(cmd: String) -> String:
	match cmd:
		"fire", "crash":
			var run := _running_slots()
			if run.is_empty():
				return ""
			var pick: Array = run[randi() % run.size()]
			var slot: Dictionary = pick[1]
			if cmd == "fire":
				slot["state"] = "burning"
				slot["fire_level"] = 1.0
			else:
				slot["state"] = "crashed"
				slot["repair_progress"] = 0.0
				slot["faulty_part"] = GameState._pick_faulty_part(slot)
				slot["diagnosed"] = false
				slot["fault_hidden"] = randf() < GameState.FAULT_HIDDEN_CHANCE
			GameState._rpc_play_sfx.rpc("alarm")
			_refresh_racks()
			return ("Brand in %s" if cmd == "fire" else "Defekt in %s") % GameState.get_rack_display_name(pick[0])
		"outage":
			if GameState.grid_outage_left > 0.0:
				return ""
			GameState._start_grid_outage(60.0)
			return "Netzausfall ausgelöst"
		"outage_end":
			if GameState.grid_outage_left <= 0.0:
				return ""
			GameState._end_grid_outage()
			return "Netzausfall beendet"
		"ddos":
			if GameState.ddos_active:
				return ""
			GameState.ddos_active = true
			GameState._rpc_play_sfx.rpc("alarm")
			GameState._broadcast_sim_tick()
			return "DDoS-Angriff ausgelöst"
		"repair_all":
			var n := 0
			for rid in GameState.racks.keys():
				for s in GameState.racks[rid]["slots"]:
					var sd: Dictionary = s
					if str(sd.get("item_type", "")) != "" and str(sd.get("state", "ok")) != "ok":
						sd["state"] = "ok"
						sd["fire_level"] = 0.0
						sd["faulty_part"] = ""
						sd["diagnosed"] = false
						sd["fault_hidden"] = false
						sd["offline"] = true
						n += 1
			if n == 0:
				return ""
			_refresh_racks()
			return "%d Server gelöscht und repariert" % n
		"clean_all":
			for rid in GameState.racks.keys():
				for s in GameState.racks[rid]["slots"]:
					var cd: Dictionary = s
					if str(cd.get("item_type", "")) != "":
						cd["dust_level"] = 0.0
						cd["thermal_health"] = 100.0
			_refresh_racks()
			return "alle Server gereinigt"
	return ""


func _refresh_racks() -> void:
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()


# ------------------------------------------------------------------ Items

## Artikel, die der Admin geben darf (alles, was es auch als Kiste im Shop gibt).
func get_giveable_items() -> Array[String]:
	var out: Array[String] = []
	for id in GameState.ITEM_CATALOG.keys():
		var cat := str((GameState.ITEM_CATALOG[id] as Dictionary).get("category", ""))
		if cat == "placeable" or cat == "module" or cat == "repair_kit":
			out.append(str(id))
	return out


func _run_items(cmd: String, args: Dictionary) -> String:
	match cmd:
		"give_item":
			var id := str(args.get("id", ""))
			var n := _num(args, "n", 1.0, float(GameState.BULK_PACK_MAX))
			if is_nan(n) or not get_giveable_items().has(id):
				return ""
			var count := roundi(n)
			if not GameState.is_bulk_packable(id):
				count = 1
			if GameState.get_delivery_zone_free_slots() <= 0:
				return ""
			GameState._spawn_crate_internal(id, count)
			GameState._broadcast_crates()
			GameState._broadcast_sim_tick()
			return "%d× %s in die Lieferzone gestellt" % [count, str(GameState.ITEM_CATALOG[id]["name"])]
		"give_part":
			var pid := str(args.get("id", ""))
			var pn := _num(args, "n", 1.0, 20.0)
			if is_nan(pn) or not is_known_part(pid):
				return ""
			GameState.parts_inventory[pid] = int(GameState.parts_inventory.get(pid, 0)) + roundi(pn)
			GameState._broadcast_inventory()
			return "%d× Bauteil ins Lager gelegt" % roundi(pn)
		"deliver_now":
			if GameState.pending_delivery_items.is_empty() or GameState.van_phase != "idle":
				return ""
			GameState.pending_delivery_express = true
			return "Lieferung sofort losgeschickt"
	return ""


func is_known_part(part_id: String) -> bool:
	for cat in HardwareCatalog.PARTS.keys():
		for p in HardwareCatalog.PARTS[cat]:
			if str((p as Dictionary)["id"]) == part_id:
				return true
	return false


# ------------------------------------------------------------------ Helfer

## Zahl aus den Argumenten, geprüft und begrenzt. NAN, wenn sie fehlt oder unbrauchbar ist.
func _num(args: Dictionary, key: String, lo: float, hi: float) -> float:
	var v: Variant = args.get(key, null)
	if not (v is float or v is int):
		return NAN
	var f := float(v)
	if not SecurityGuard.is_finite_float(f):
		return NAN
	return clampf(f, lo, hi)


func _is_reachable(peer_id: int) -> bool:
	return peer_id == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer_id)


func _sync_rights() -> void:
	_rpc_sync_rights.rpc(_granted.duplicate())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_rights(data: Dictionary) -> void:
	if not _is_host():
		_granted = data.duplicate()
	rights_changed.emit()


func _log(sender: int, text: String, ok: bool) -> void:
	var entry := {"time": GameState.get_time_string(), "who": NetworkManager.get_player_name(sender), "text": text, "ok": ok}
	print("[ADMIN] %s (%d): %s" % [entry["who"], sender, text])
	for pid in NetworkManager.players.keys():
		if is_admin(int(pid)) and _is_reachable(int(pid)):
			_rpc_log.rpc_id(int(pid), entry)


@rpc("authority", "call_local", "reliable")
func _rpc_log(entry: Dictionary) -> void:
	log_entries.push_front(entry)
	if log_entries.size() > LOG_MAX:
		log_entries.resize(LOG_MAX)
	log_changed.emit()
