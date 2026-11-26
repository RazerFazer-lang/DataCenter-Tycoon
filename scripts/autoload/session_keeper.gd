extends Node
## Hält Co-op-Sitzungen am Leben.
##   Wiederverbinden (NET-02): Reißt die Verbindung ab, ohne dass der Host die Sitzung beendet hat,
##     verbindet sich der Client selbst neu. Der Host hält Platz, Position und getragene Ware frei.
##   Host-Wechsel (NET-07): Wer am längsten dabei ist, bekommt regelmäßig eine Kopie der Welt.
##     Geht der Host (oder stürzt ab), übernimmt er sie und die anderen verbinden sich mit ihm.
##     Klappt nur, wenn er erreichbar ist (LAN, VPN, freigegebener Port).

## Overlay in main.gd: aktiv = gerade am Wiederverbinden oder Übernehmen.
signal recovering_changed(active: bool, text: String)

## So lange hält der Host einem abgebrochenen Spieler seinen Platz frei.
const RESERVE_S := 90.0
## Versuche, sich wieder mit dem alten Host zu verbinden (danach Host-Wechsel, falls geplant).
const RECONNECT_TRIES := 7
const RECONNECT_TRIES_BEFORE_MIGRATE := 2
const RETRY_S := 3.0
## Versuche, sich mit dem neuen Host zu verbinden (er muss die Welt erst laden).
const MIGRATE_JOIN_TRIES := 12
## So oft bekommt der Nachfolger eine frische Kopie der Welt.
const MIGRATE_SYNC_S := 15.0
## ENet-Zeitlimit für die Verbindung zum Host: Abbrüche fallen so nach höchstens 10 s auf.
const PEER_TIMEOUT_MIN_MS := 4000
const PEER_TIMEOUT_MAX_MS := 10000
const BLOB_MAX := 4 * 1024 * 1024
## Ein Verbindungsversuch, der so lange hängt, gilt als gescheitert (ENet allein wartet länger).
const ATTEMPT_TIMEOUT_S := 6.0

# --- Host
var _poses: Dictionary = {}       # peer_id -> [pos, yaw]
var _reserved: Dictionary = {}    # Schlüssel -> {t, name, pos, yaw, crates: [[id, slot]], slot}
var _sync_accum: float = 0.0
var _plan_sent: Dictionary = {}
var _closing_sent: bool = false

# --- Client
var _host_closing: String = ""    # "" | "end" | "migrate"
var _plan: Dictionary = {}        # {peer, ip, port, host}
var _my_id: int = 0
var _mig_blob: PackedByteArray = PackedByteArray()
var _mode: String = ""            # "" | "reconnect" | "migrate_join" | "migrate_host"
var _tries: int = 0
var _password: String = ""
var _retry_timer: Timer
var _attempt_timer: Timer
## Eigene Lage vor dem Abbruch: {pos, yaw, cable_type, cable_id, cable_slot, slot}
var stash: Dictionary = {}
## Vom Host gemeldete Lage, wird angewendet, sobald die eigene Figur steht.
var _restore_pending: Dictionary = {}
var _restore_deadline: int = 0


func _ready() -> void:
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_try_next)
	add_child(_retry_timer)
	_attempt_timer = Timer.new()
	_attempt_timer.one_shot = true
	_attempt_timer.timeout.connect(_on_attempt_timeout)
	add_child(_attempt_timer)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)


## Zeilen fürs Log, damit sich Abbrüche und Host-Wechsel aus Spieler-Logs nachvollziehen lassen.
func _log(msg: String) -> void:
	print("[Sitzung %s] %s" % [Time.get_time_string_from_system(), msg])


func is_recovering() -> bool:
	return _mode != ""


## Wer übernimmt, wenn der Host geht (peer_id, 0 = niemand). Auf Clients aus dem Plan des Hosts.
func successor() -> int:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		return _pick_successor()
	return int(_plan.get("peer", 0))


## Nach dem Verlassen einer Sitzung (nicht während Wiederverbinden oder Übernehmen).
func on_session_left() -> void:
	if _mode != "":
		return
	_poses.clear()
	_reserved.clear()
	_plan.clear()
	_plan_sent.clear()
	_mig_blob = PackedByteArray()
	_host_closing = ""
	_closing_sent = false
	_sync_accum = 0.0


# ======================================================================= Host

## Letzte bekannte Lage eines Spielers (von world_controller, jede Bewegungsmeldung).
func note_pose(peer_id: int, pos: Vector3, yaw: float) -> void:
	_poses[peer_id] = [pos, yaw]


## Wo die Ware eines gegangenen Spielers hinfällt: an seine letzte Stelle.
func drop_pos(peer_id: int) -> Vector3:
	if _poses.has(peer_id):
		return GameState._clamp_drop_pos(_poses[peer_id][0] as Vector3)
	return Vector3(0.0, 0.0, 2.0)


## Host: Ein Spieler ist weg (vor handle_player_disconnect). Platz freihalten, falls er wiederkommt.
func on_peer_left(peer_id: int, kicked: bool) -> void:
	var key: String = NetworkManager.peer_key(peer_id)
	if not kicked and key != "":
		var held: Array = []
		for cid in GameState.crates.keys():
			var c: Dictionary = GameState.crates[cid]
			if int(c.get("held_by", 0)) == peer_id:
				held.append([str(cid), int(c.get("held_slot", 1))])
		var pose: Array = _poses.get(peer_id, [Vector3.INF, 0.0])
		_reserved[key] = {
			"t": Time.get_ticks_msec(), "name": NetworkManager.get_player_name(peer_id),
			"pos": pose[0], "yaw": pose[1], "crates": held, "slot": GameState.get_active_slot(peer_id),
			"seq": int((NetworkManager.players.get(peer_id, {}) as Dictionary).get("seq", 0)) if NetworkManager.players.get(peer_id, null) is Dictionary else 0,
		}
	_poses.erase(peer_id)
	if int(_plan_sent.get("peer", 0)) == peer_id:
		_plan_sent.clear()
		_sync_accum = MIGRATE_SYNC_S # gleich einen neuen Nachfolger bestimmen


## Host: Hängt von diesem Spieler noch eine alte Verbindung, die zuerst abräumen (vor der Namensvergabe).
func drop_stale_for(peer_id: int) -> void:
	var key: String = NetworkManager.peer_key(peer_id)
	if key == "":
		return
	for pid in NetworkManager.players.keys():
		if int(pid) != peer_id and int(pid) != 1 and NetworkManager.peer_key(int(pid)) == key:
			NetworkManager.drop_stale_peer(int(pid))


## Host: Ein Spieler hat sich angemeldet und die Welt bekommen. War er eben schon da: alles zurück.
func on_peer_registered(peer_id: int) -> void:
	_expire_reservations()
	drop_stale_for(peer_id)
	var key: String = NetworkManager.peer_key(peer_id)
	if key != "" and _reserved.has(key):
		var r: Dictionary = _reserved[key]
		_reserved.erase(key)
		var changed := false
		for e in (r.get("crates", []) as Array):
			var cid := str(e[0])
			if GameState.crates.has(cid) and int(GameState.crates[cid].get("held_by", 0)) == 0:
				GameState.crates[cid]["held_by"] = peer_id
				GameState.crates[cid]["held_slot"] = int(e[1])
				changed = true
		GameState.player_active_slot[peer_id] = int(r.get("slot", 1))
		# Wer kurz weg war, bleibt beim Host-Wechsel an seinem Platz in der Reihe.
		if int(r.get("seq", 0)) > 0 and NetworkManager.players.get(peer_id, null) is Dictionary:
			(NetworkManager.players[peer_id] as Dictionary)["seq"] = int(r["seq"])
		if changed:
			GameState._broadcast_crates()
		var pos: Vector3 = r.get("pos", Vector3.INF)
		if pos != Vector3.INF:
			_poses[peer_id] = [pos, float(r.get("yaw", 0.0))]
			_rpc_restore.rpc_id(peer_id, pos, float(r.get("yaw", 0.0)), int(r.get("slot", 1)))
		GameState.post_event_f("🔁 %s ist wieder da.", [NetworkManager.get_player_name(peer_id)], "info")
	# Der Neue soll wissen, wer übernimmt, falls der Host geht.
	if not _plan_sent.is_empty():
		_rpc_plan.rpc_id(peer_id, _plan_sent)
	_sync_accum = MIGRATE_SYNC_S


func reservation_count() -> int:
	_expire_reservations()
	return _reserved.size()


func _expire_reservations() -> void:
	var now := Time.get_ticks_msec()
	for key in _reserved.keys():
		if now - int(_reserved[key]["t"]) > int(RESERVE_S * 1000.0):
			_reserved.erase(key)


func _host_can_migrate() -> bool:
	return NetworkManager.is_in_session and multiplayer.multiplayer_peer != null and multiplayer.is_server() \
		and not NetworkManager.is_dedicated and GameState.is_active


## Der Client, der am längsten dabei ist (kleinste Beitrittsnummer).
func _pick_successor() -> int:
	var best := 0
	var best_seq := 1 << 30
	for pid in NetworkManager.players.keys():
		var p := int(pid)
		if p == 1 or not multiplayer.get_peers().has(p):
			continue
		var seq := int((NetworkManager.players[pid] as Dictionary).get("seq", 1 << 29))
		if seq < best_seq:
			best_seq = seq
			best = p
	return best


func _process(delta: float) -> void:
	if not _restore_pending.is_empty():
		_apply_restore()
	if not _host_can_migrate():
		return
	_sync_accum += delta
	if _sync_accum < MIGRATE_SYNC_S:
		return
	_sync_accum = 0.0
	_expire_reservations()
	var succ := _pick_successor()
	if succ == 0:
		_plan_sent.clear()
		return
	var plan := _make_plan(succ)
	if plan != _plan_sent:
		_plan_sent = plan
		_rpc_plan.rpc(plan)
	_send_state(succ)


func _make_plan(succ: int) -> Dictionary:
	return {"peer": succ, "ip": NetworkManager._get_peer_ip(succ), "port": NetworkManager.hosted_port,
		"host": NetworkManager.local_player_name, "succ_name": NetworkManager.get_player_name(succ)}


## Kopie der Welt für den Nachfolger: Spielstand, dazu wer was in der Hand hatte und wo stand.
func _send_state(succ: int) -> void:
	var held := {}
	var poses := {}
	for pid in NetworkManager.players.keys():
		var p := int(pid)
		var key: String = NetworkManager.peer_key(p) if p != 1 else ""
		if key == "":
			continue
		var list: Array = []
		for cid in GameState.crates.keys():
			if int(GameState.crates[cid].get("held_by", 0)) == p:
				list.append([str(cid), int(GameState.crates[cid].get("held_slot", 1))])
		held[key] = list
		if _poses.has(p):
			poses[key] = _poses[p]
	var blob := var_to_bytes({
		"v": 1,
		"state": SaveManager._serialize_state(GameState.export_save_data()),
		"save_id": GameState.current_save_id,
		"name": GameState.current_save_name,
		"host": NetworkManager.local_player_name,
		"held": held,
		"poses": poses,
	}).compress(FileAccess.COMPRESSION_GZIP)
	if blob.size() <= BLOB_MAX:
		_rpc_state.rpc_id(succ, blob)


## Host geht mit Mitspielern: Nachfolger bekommt die Welt, alle bekommen Bescheid. Danach leave_session().
func hand_over() -> bool:
	if not _host_can_migrate():
		return false
	var succ := _pick_successor()
	if succ == 0:
		return false
	_plan_sent = _make_plan(succ)
	_rpc_plan.rpc(_plan_sent)
	_send_state(succ)
	_rpc_host_leaving.rpc("migrate")
	_closing_sent = true
	NetworkManager.flush_peer()
	# Kurz warten, bis die Pakete sicher draußen sind (ENet schickt Verlorenes in dieser Zeit neu).
	await get_tree().create_timer(0.5).timeout
	return true


## Host beendet ohne Übergabe (oder dedizierter Server stoppt): Clients sollen sich nicht neu verbinden.
func announce_end() -> void:
	if _closing_sent or multiplayer.multiplayer_peer == null or not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		return
	_closing_sent = true
	_rpc_host_leaving.rpc("end")
	NetworkManager.flush_peer()


# ======================================================================= Client

@rpc("authority", "call_remote", "reliable")
func _rpc_plan(plan: Dictionary) -> void:
	_plan = plan.duplicate()
	_my_id = multiplayer.get_unique_id()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(blob: PackedByteArray) -> void:
	if blob.size() <= BLOB_MAX:
		_mig_blob = blob


@rpc("authority", "call_remote", "reliable")
func _rpc_host_leaving(kind: String) -> void:
	_host_closing = kind if kind in ["end", "migrate"] else "end"


@rpc("authority", "call_remote", "reliable")
func _rpc_restore(pos: Vector3, yaw: float, slot: int) -> void:
	if not SecurityGuard.is_finite_vec3(pos):
		return
	_restore_pending = {"pos": pos, "yaw": yaw, "slot": slot}
	_restore_deadline = Time.get_ticks_msec() + 8000


## NetworkManager: Verbindung zum Host weg (nicht beim Anmelden). true = wir kümmern uns darum.
func on_server_lost(kicked: bool) -> bool:
	if kicked or _host_closing == "end" or NetworkManager._last_join.is_empty():
		_host_closing = ""
		return false
	_stash_local()
	_password = str(NetworkManager._last_join.get("password", ""))
	_log("Verbindung weg (Host meldete: %s, Nachfolger %d, ich %d, Kopie %d Bytes)" % [_host_closing if _host_closing != "" else "nichts", int(_plan.get("peer", 0)), _my_id, _mig_blob.size()])
	if _host_closing == "migrate" and _plan_valid():
		_begin_migration()
	else:
		_mode = "reconnect"
		_tries = 0
		recovering_changed.emit(true, tr("Verbindung zum Host verloren. Verbinde neu …"))
		NetworkManager.leave_session()
		_retry_timer.start(1.0)
	return true


func _plan_valid() -> bool:
	return int(_plan.get("peer", 0)) > 1 and str(_plan.get("ip", "")) != "" and int(_plan.get("port", 0)) > 0


## Abbrechen (Knopf im Overlay): zurück ins Menü.
func cancel() -> void:
	if _mode == "":
		return
	_retry_timer.stop()
	_give_up(tr("Wiederverbinden abgebrochen."))


func _try_next() -> void:
	_log("Versuch %d (%s)" % [_tries + 1, _mode])
	match _mode:
		"reconnect":
			_tries += 1
			# Antwortet der alte Host zweimal nicht und gibt es einen Nachfolger: Host-Wechsel.
			if _tries > RECONNECT_TRIES_BEFORE_MIGRATE and _plan_valid() and _mig_or_join_possible():
				_begin_migration()
				return
			if _tries > RECONNECT_TRIES:
				_give_up(tr("Verbindung zum Host verloren. Wiederverbinden hat nicht geklappt."))
				return
			recovering_changed.emit(true, tr("Verbindung zum Host verloren. Verbinde neu (Versuch %d von %d) …") % [_tries, RECONNECT_TRIES])
			var lj: Dictionary = NetworkManager._last_join
			NetworkManager.join_game(str(lj["ip"]), NetworkManager.local_player_name, int(lj["port"]), _password)
			_attempt_timer.start(ATTEMPT_TIMEOUT_S)
		"migrate_join":
			_tries += 1
			if _tries > MIGRATE_JOIN_TRIES:
				_give_up(tr("Host-Wechsel: %s ist nicht erreichbar.") % str(_plan.get("succ_name", tr("Der neue Host"))))
				return
			recovering_changed.emit(true, tr("Host-Wechsel: verbinde mit %s (Versuch %d von %d) …") % [str(_plan.get("succ_name", "?")), _tries, MIGRATE_JOIN_TRIES])
			NetworkManager.join_game(str(_plan["ip"]), NetworkManager.local_player_name, int(_plan["port"]), _password)
			_attempt_timer.start(ATTEMPT_TIMEOUT_S)


func _on_attempt_timeout() -> void:
	if _mode != "" and NetworkManager.is_joining():
		NetworkManager.abort_join(tr("Keine Antwort vom Host."))


## Nachfolger braucht die Weltkopie, alle anderen nur den Plan.
func _mig_or_join_possible() -> bool:
	return int(_plan.get("peer", 0)) != _my_id or not _mig_blob.is_empty()


## NetworkManager._fail_join während wir neu verbinden: false = normal melden.
func on_join_failed(reason: String, permanent: bool) -> bool:
	if _mode == "" or _mode == "migrate_host":
		return false
	if permanent:
		_give_up(reason)
		return true
	_retry_timer.start(RETRY_S)
	return true


func _begin_migration() -> void:
	var succ := int(_plan.get("peer", 0))
	if str(_plan.get("succ_name", "")) == "":
		_plan["succ_name"] = tr("der neue Host")
	# Erst den Modus setzen: leave_session() räumt sonst Plan und Weltkopie weg.
	_mode = "migrate_host" if succ == _my_id and not _mig_blob.is_empty() else "migrate_join"
	_tries = 0
	_log("Host-Wechsel: %s (Nachfolger %d auf %s:%d)" % ["ich übernehme" if _mode == "migrate_host" else "verbinde mit Nachfolger", succ, str(_plan.get("ip", "")), int(_plan.get("port", 0))])
	if NetworkManager.is_in_session:
		NetworkManager.leave_session()
	if _mode == "migrate_host":
		recovering_changed.emit(true, tr("Host-Wechsel: Du übernimmst die Welt …"))
		_take_over.call_deferred()
	else:
		recovering_changed.emit(true, tr("Host-Wechsel: %s übernimmt die Welt …") % str(_plan["succ_name"]))
		_retry_timer.start(2.0)


## Nachfolger: aus der Kopie hosten, auf demselben Port. Freigehaltene Plätze für die anderen anlegen.
func _take_over() -> void:
	# decompress_dynamic kann nur gzip, deflate und brotli.
	var raw := _mig_blob.decompress_dynamic(BLOB_MAX * 8, FileAccess.COMPRESSION_GZIP)
	var data: Variant = bytes_to_var(raw) if not raw.is_empty() else null
	if not (data is Dictionary) or not ((data as Dictionary).get("state", null) is Dictionary):
		_give_up(tr("Host-Wechsel: Die Kopie der Welt ist unvollständig."))
		return
	var d: Dictionary = data
	var state: Dictionary = SaveManager._deserialize_state(d["state"] as Dictionary)
	var old_host := str(d.get("host", "Host"))
	# Eigener Spielstand: der des alten Hosts bleibt bei ihm, hier entsteht eine Kopie.
	var save_id := SaveManager.sanitize_save_id("%s_von_%s" % [str(d.get("save_id", "welt")), old_host])
	var port := int(_plan.get("port", NetworkManager.DEFAULT_PORT))
	var err: int = NetworkManager._start_host_internal(NetworkManager.local_player_name, port, state, save_id, str(d.get("name", "Welt")), _password)
	if err != OK:
		_give_up(tr("Host-Wechsel: Port %d ist hier belegt, die Welt konnte nicht übernommen werden.") % port)
		return
	_log("Welt übernommen, hoste auf Port %d" % port)
	var now := Time.get_ticks_msec()
	var held: Dictionary = d.get("held", {}) if d.get("held", {}) is Dictionary else {}
	var poses: Dictionary = d.get("poses", {}) if d.get("poses", {}) is Dictionary else {}
	for key in held.keys():
		var pose: Array = poses.get(key, [Vector3.INF, 0.0]) if poses.get(key, null) is Array else [Vector3.INF, 0.0]
		_reserved[str(key)] = {"t": now, "name": "", "pos": pose[0], "yaw": pose[1], "crates": held[key], "slot": 1}
	_mode = ""
	_mig_blob = PackedByteArray()
	_plan.clear()
	recovering_changed.emit(false, "")
	GameState.save_current_world()
	GameState.post_event_f("🔁 Host-Wechsel: Du hast die Welt von %s übernommen.", [old_host], "good")
	_restore_from_stash()


func _give_up(reason: String) -> void:
	_attempt_timer.stop()
	_log("Aufgegeben: %s" % reason)
	_mode = ""
	_tries = 0
	_plan.clear()
	_mig_blob = PackedByteArray()
	_host_closing = ""
	stash.clear()
	recovering_changed.emit(false, "")
	if NetworkManager.is_in_session:
		NetworkManager.leave_session()
	NetworkManager.disconnected_from_session.emit(reason)


func _on_connection_succeeded() -> void:
	_attempt_timer.stop()
	_host_closing = ""
	_closing_sent = false
	# Auch nach einem normalen Beitritt: Zeitlimit für Abbrüche kürzer als ENets Standard (30 s).
	NetworkManager.set_host_timeout(PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	if _mode == "reconnect" or _mode == "migrate_join":
		var was := _mode
		_mode = ""
		_tries = 0
		recovering_changed.emit(false, "")
		if was == "migrate_join":
			_plan.clear()
		# Meldet der Host keine Lage (z. B. nach dem Host-Wechsel ohne Eintrag): eigene nehmen.
		_restore_deadline = Time.get_ticks_msec() + 8000
		if _restore_pending.is_empty() and not stash.is_empty():
			_restore_pending = {"pos": stash.get("pos", Vector3.INF), "yaw": float(stash.get("yaw", 0.0)), "slot": int(stash.get("slot", 1)), "from_stash": true}


# ----------------------------------------------------------------------- Eigene Lage merken und zurücksetzen

func _local_player() -> Node:
	return get_tree().get_first_node_in_group("local_player")


func _stash_local() -> void:
	stash.clear()
	var lp := _local_player()
	if lp == null:
		return
	stash = {
		"pos": (lp as Node3D).position,
		"yaw": (lp as Node3D).rotation.y,
		"cable_type": str(lp.get("cable_active_type")),
		"cable_id": str(lp.get("cable_start_id")),
		"cable_slot": int(lp.get("cable_start_slot")),
		"slot": int(lp.get("active_slot")),
	}


func _restore_from_stash() -> void:
	if not stash.is_empty():
		_restore_pending = {"pos": stash.get("pos", Vector3.INF), "yaw": float(stash.get("yaw", 0.0)), "slot": int(stash.get("slot", 1)), "from_stash": true}
		_restore_deadline = Time.get_ticks_msec() + 8000


## Wartet, bis Welt und eigene Figur stehen, dann Lage, Werkzeugplatz und Kabel in der Hand zurück.
func _apply_restore() -> void:
	if Time.get_ticks_msec() > _restore_deadline:
		_restore_pending.clear()
		stash.clear()
		return
	var lp := _local_player()
	if lp == null or not GameState.is_active:
		return
	var pos: Vector3 = _restore_pending.get("pos", Vector3.INF)
	if pos != Vector3.INF and SecurityGuard.is_finite_vec3(pos):
		(lp as Node3D).position = pos + Vector3(0.0, 0.05, 0.0)
		(lp as Node3D).rotation.y = float(_restore_pending.get("yaw", 0.0))
		if "velocity" in lp:
			lp.set("velocity", Vector3.ZERO)
	var slot := int(_restore_pending.get("slot", 1))
	if lp.has_method("_select_slot") and int(lp.get("active_slot")) != slot:
		lp.call("_select_slot", slot)
	if not stash.is_empty() and str(stash.get("cable_id", "")) != "":
		lp.set("cable_active_type", str(stash["cable_type"]))
		lp.set("cable_start_id", str(stash["cable_id"]))
		lp.set("cable_start_slot", int(stash["cable_slot"]))
	_restore_pending.clear()
	stash.clear()
