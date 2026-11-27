extends Node
## Cyberangriffe und Firewall (GAME-06). Angriffe kommen als Ereignis. Firewall-Regeln am PC mildern sie
## vorher, während eines Angriffs sieht man den Verkehr und blockt die richtigen Quellen.
## Der Netzwerk-Admin (GAME-07) blockt von selbst. Der Host rechnet, die Clients schicken nur Anfragen.
## Folgen laufen über GameState.ddos_active (wie bisher) und income_mult().

signal cyber_changed
signal action_result(ok: bool, message: String)

## Regeln: Name, Wirkung, Kosten am Tag.
const RULES := {
	"ports": {"name": "Unnötige Ports schließen", "desc": "Brute-Force-Angriffe scheitern oft schon am Eingang (60 %).", "cost": 0},
	"ratelimit": {"name": "Ratenlimit", "desc": "Ein DDoS legt nicht mehr alles lahm, die Einnahmen sinken nur auf 60 %. Echte Kunden merken es leicht: −3 % Einnahmen.", "cost": 0},
	"geo": {"name": "Geo-Sperre", "desc": "35 % weniger Angriffe, aber manche Kunden aus dem Ausland kommen nicht mehr durch: −4 % Einnahmen.", "cost": 0},
	"ids": {"name": "Einbruchserkennung (IDS)", "desc": "Meldet Angriffe früher: 20 s mehr Zeit zum Abwehren.", "cost": 40},
	"backup": {"name": "Offline-Backups", "desc": "Erpressungstrojaner können nichts dauerhaft verschlüsseln, das Rack ist nach kurzer Zeit wieder da.", "cost": 30},
}
const RULE_ORDER: Array[String] = ["ports", "ratelimit", "geo", "ids", "backup"]
## Angriffsarten: Zeit bis zum Schaden, Zahl der Angreifer und der echten Quellen.
const KINDS := {
	"ddos": {"name": "DDoS-Angriff", "time": 60.0, "bad": [4, 7], "good": [4, 7]},
	"bruteforce": {"name": "Brute-Force auf Admin-Zugänge", "time": 45.0, "bad": [2, 4], "good": [4, 6]},
	"ransom": {"name": "Erpressungstrojaner", "time": 35.0, "bad": [1, 3], "good": [5, 7]},
}
const BAD_PATTERNS := ["SYN-Flut", "immer dieselbe Anfrage", "Login-Versuche im Sekundentakt", "verschlüsselte Nutzlast", "unbekanntes Programm", "Portscan"]
const GOOD_PATTERNS := ["Webseitenaufrufe", "API-Anfragen", "Backup-Abgleich", "Spielserver-Verkehr", "Monitoring", "Video-Streams"]
const COUNTRIES := ["Deutschland", "Niederlande", "Frankreich", "USA", "Brasilien", "Vietnam", "Rumänien", "Indien", "Russland", "China"]
const HISTORY_MAX := 10
const RANSOM_OFFLINE := 120.0
const BACKUP_OFFLINE := 20.0
const RANSOM_RECOVERY := 1200.0

var rules: Dictionary = {}
## Laufender Angriff: {kind, left, total, sources: [{id, ip, country, rps, pattern, bad, blocked}]}
var attack: Dictionary = {}
var history: Array = []
var stats := {"won": 0, "lost": 0}
## Rack -> Sekunden, bis es nach einem Erpressungstrojaner wieder läuft.
var encrypted: Dictionary = {}

var _cooldown := 90.0
var _admin_acc := 0.0
var _last_day := -1
var _dirty := false
var _was_active := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func _process(_delta: float) -> void:
	var active: bool = NetworkManager.is_in_session and GameState.is_active
	if not active:
		if _was_active:
			_was_active = false
			reset()
		return
	_was_active = true
	if not multiplayer.is_server():
		return
	if _dirty:
		_dirty = false
		_broadcast()


func reset() -> void:
	rules = {}
	attack = {}
	history = []
	stats = {"won": 0, "lost": 0}
	encrypted = {}
	_cooldown = 90.0
	_admin_acc = 0.0
	_last_day = -1
	cyber_changed.emit()


func export_data() -> Dictionary:
	return {"rules": rules.duplicate(), "attack": attack.duplicate(true), "history": history.duplicate(true), "stats": stats.duplicate(),
		"encrypted": encrypted.duplicate(), "cooldown": _cooldown}


func import_data(d: Dictionary) -> void:
	rules = {}
	var rr: Variant = d.get("rules", {})
	if rr is Dictionary:
		for k in (rr as Dictionary).keys():
			if RULES.has(str(k)):
				rules[str(k)] = true
	attack = (d.get("attack", {}) as Dictionary).duplicate(true) if d.get("attack", {}) is Dictionary else {}
	if not attack.is_empty() and not KINDS.has(str(attack.get("kind", ""))):
		attack = {}
	history = (d.get("history", []) as Array).duplicate(true) if d.get("history", []) is Array else []
	var s: Variant = d.get("stats", {})
	stats = {"won": int((s as Dictionary).get("won", 0)), "lost": int((s as Dictionary).get("lost", 0))} if s is Dictionary else {"won": 0, "lost": 0}
	encrypted = (d.get("encrypted", {}) as Dictionary).duplicate() if d.get("encrypted", {}) is Dictionary else {}
	_cooldown = float(d.get("cooldown", 90.0))
	cyber_changed.emit()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and NetworkManager.is_in_session:
		_rpc_sync.rpc_id(peer_id, export_data())


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(d: Dictionary) -> void:
	import_data(d)


@rpc("authority", "call_remote", "reliable")
func _rpc_feedback(ok: bool, message: String, args: Array) -> void:
	action_result.emit(ok, GameState.format_message(message, args))


func _broadcast() -> void:
	cyber_changed.emit()
	if NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_sync.rpc(export_data())


func _feedback(peer: int, ok: bool, message: String, args: Array = []) -> void:
	if peer == multiplayer.get_unique_id() or peer == 0:
		action_result.emit(ok, GameState.format_message(message, args))
	elif peer > 0:
		_rpc_feedback.rpc_id(peer, ok, message, args)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


# ---------------------------------------------------------------- Abfragen

func has_rule(id: String) -> bool:
	return rules.has(id)


func daily_cost() -> int:
	var c := 0
	for id in rules.keys():
		c += int(RULES[id]["cost"])
	return c


## Faktor auf alle Einnahmen: Regeln kosten etwas, ein gemilderter DDoS mehr.
func income_mult() -> float:
	var m := 1.0
	if has_rule("ratelimit"):
		m *= 0.97
	if has_rule("geo"):
		m *= 0.96
	if not attack.is_empty() and str(attack.get("kind", "")) == "ddos" and has_rule("ratelimit"):
		m *= 0.6
	return m


func is_encrypted(rid: String) -> bool:
	return float(encrypted.get(rid, 0.0)) > 0.0


func bad_left() -> int:
	var n := 0
	for s in attack.get("sources", []):
		if bool(s["bad"]) and not bool(s["blocked"]):
			n += 1
	return n


func admin() -> Dictionary:
	return Staff.worker("netadmin")


# ---------------------------------------------------------------- Host: Ablauf

## Aus dem Sim-Schritt (Host). Ersetzt den alten DDoS-Zufall.
func tick(dt: float) -> void:
	if not multiplayer.is_server():
		return
	_tick_daily()
	for rid in encrypted.keys():
		encrypted[rid] = float(encrypted[rid]) - dt
		if float(encrypted[rid]) <= 0.0:
			encrypted.erase(rid)
			GameState.post_event_f("🔓 %s läuft wieder.", [GameState.get_rack_display_name(str(rid))], "good")
			_dirty = true
	if attack.is_empty():
		var has_power := GameState.breaker_on or GameState.ups_backup_active
		if not ((GameState.ai_platform_level > 0 or GameState.get_active_contract_count() >= 2) and GameState.total_compute >= 20 and has_power):
			return
		var speed := GameState.diff("events") * (0.65 if has_rule("geo") else 1.0)
		_cooldown -= dt * speed
		if _cooldown <= 0.0:
			var dmult := float(GameState.ROUTER_TIERS[clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)]["ddos_mult"])
			_cooldown = randf_range(80.0, 140.0) * dmult
			start_attack(_pick_kind())
		return
	attack["left"] = float(attack["left"]) - dt
	_tick_admin(dt)
	if bad_left() == 0:
		_end_attack(true)
	elif float(attack["left"]) <= 0.0:
		_end_attack(false)
	else:
		attack["tick"] = float(attack.get("tick", 0.0)) + dt
		if float(attack["tick"]) >= 1.0:
			attack["tick"] = 0.0
			_dirty = true


func _pick_kind() -> String:
	var r := randf()
	if GameState.get_company_level() >= 3 and r < 0.2:
		return "ransom"
	return "bruteforce" if r < 0.5 else "ddos"


func start_attack(kind: String) -> void:
	if not KINDS.has(kind):
		return
	var k: Dictionary = KINDS[kind]
	# Brute-Force scheitert oft schon an geschlossenen Ports.
	if kind == "bruteforce" and has_rule("ports") and randf() < 0.6:
		_log(kind, "abgeprallt")
		GameState.post_event("🛡 Brute-Force-Versuch an geschlossenen Ports abgeprallt.", "good")
		_dirty = true
		return
	var sources: Array = []
	var n_bad := randi_range(int(k["bad"][0]), int(k["bad"][1]))
	var n_good := randi_range(int(k["good"][0]), int(k["good"][1]))
	for i in n_bad:
		sources.append(_source(true, i))
	for i in n_good:
		sources.append(_source(false, i))
	sources.shuffle()
	for i in sources.size():
		sources[i]["id"] = "q%d" % i
	var total := float(k["time"]) + (20.0 if has_rule("ids") else 0.0)
	attack = {"kind": kind, "left": total, "total": total, "sources": sources, "tick": 0.0}
	_apply_ddos_flag()
	GameState.post_event_f("🚨 %s! In der Firewall-App am PC die Angreifer blocken (%d s).", [str(k["name"]), int(total)], "alert")
	GameState._rpc_play_sfx.rpc("alarm")
	GameState._broadcast_sim_tick()
	_dirty = true


func _source(bad: bool, i: int) -> Dictionary:
	var country: String = COUNTRIES[randi() % COUNTRIES.size()] if bad else COUNTRIES[randi() % 4]
	var ip := "%d.%d.%d.%d" % [randi_range(23, 223), randi_range(0, 255), randi_range(0, 255), randi_range(1, 254)]
	var rps := randi_range(900, 6000) if bad else randi_range(15, 420)
	# Manche Angreifer tarnen sich mit wenig Verkehr, dann verrät sie nur das Muster.
	if bad and i % 3 == 2:
		rps = randi_range(60, 300)
	var pattern: String = BAD_PATTERNS[randi() % BAD_PATTERNS.size()] if bad else GOOD_PATTERNS[randi() % GOOD_PATTERNS.size()]
	return {"id": "", "ip": ip, "country": country, "rps": rps, "pattern": pattern, "bad": bad, "blocked": false}


func _apply_ddos_flag() -> void:
	var on := not attack.is_empty() and str(attack.get("kind", "")) == "ddos" and not has_rule("ratelimit")
	if GameState.ddos_active != on:
		GameState.ddos_active = on
		GameState._broadcast_sim_tick()


func _tick_admin(dt: float) -> void:
	var e := admin()
	if e.is_empty():
		return
	var skill := int(e.get("skill", 1))
	_admin_acc += dt
	var every := maxf(3.0, 12.0 - float(skill) * 1.6)
	if _admin_acc < every:
		return
	_admin_acc = 0.0
	var open: Array = []
	for s in attack["sources"]:
		if not bool(s["blocked"]):
			open.append(s)
	if open.is_empty():
		return
	var pick: Dictionary = {}
	# Wenig Erfahrung: ab und zu trifft es eine echte Quelle.
	if randf() < float(5 - skill) * 0.04:
		pick = open[randi() % open.size()]
	else:
		for s in open:
			if bool(s["bad"]):
				pick = s
				break
	if pick.is_empty():
		return
	_block(pick, str(e.get("name", tr("Netzwerk-Admin"))))
	if bool(pick["bad"]):
		e["work_done"] = int(e.get("work_done", 0)) + 1


func _block(s: Dictionary, who: String) -> void:
	s["blocked"] = true
	if not bool(s["bad"]):
		# Ein echter Kunde ist ausgesperrt.
		var rented: Array = []
		for rid in GameState.racks.keys():
			if str(GameState.racks[rid].get("rental_type", "none")) != "none":
				rented.append(rid)
		if not rented.is_empty():
			var rid: String = rented[randi() % rented.size()]
			GameState.racks[rid]["satisfaction"] = maxf(0.0, float(GameState.racks[rid].get("satisfaction", 80.0)) - 8.0)
		GameState.post_event_f("⚠ %s hat %s gesperrt, das war echter Kundenverkehr.", [who, str(s["ip"])], "warn")
	_dirty = true


func _end_attack(won: bool) -> void:
	var kind := str(attack["kind"])
	var kname := str(KINDS[kind]["name"])
	attack = {}
	_apply_ddos_flag()
	if won:
		stats["won"] = int(stats["won"]) + 1
		GameState.reputation = minf(100.0, GameState.reputation + 1.0)
		GameState.post_event_f("🛡 %s abgewehrt. Alle Angreifer sind gesperrt.", [kname], "good")
		GameState._rpc_play_sfx.rpc("repair")
		_log(kind, "abgewehrt")
	else:
		stats["lost"] = int(stats["lost"]) + 1
		_fail(kind)
		_log(kind, "durchgekommen")
	GameState._broadcast_sim_tick()
	GameState._broadcast_racks()
	_dirty = true


func _fail(kind: String) -> void:
	var racks: Array = []
	for rid in GameState.racks.keys():
		if not RackData.of(GameState.racks[rid]).used_slots().is_empty():
			racks.append(rid)
	match kind:
		"ddos":
			GameState.reputation = maxf(0.0, GameState.reputation - 4.0)
			GameState.post_event("Der DDoS ist abgeflaut, aber die Kunden haben es gemerkt (Ruf −4).", "warn")
		"bruteforce":
			GameState.reputation = maxf(0.0, GameState.reputation - 3.0)
			var fine := 300.0 * float(GameState.get_company_level())
			GameState.money = maxf(0.0, GameState.money - fine)
			FinanceManager.book("other", -fine)
			if not racks.is_empty():
				var rid: String = racks[randi() % racks.size()]
				GameState.racks[rid]["satisfaction"] = maxf(0.0, float(GameState.racks[rid].get("satisfaction", 80.0)) - 40.0)
			GameState.post_event_f("🔓 Einbruch in die Admin-Zugänge! Kundendaten waren offen, Meldung an die Aufsicht: $%d.", [int(fine)], "alert")
		"ransom":
			if racks.is_empty():
				return
			var rid: String = racks[randi() % racks.size()]
			if has_rule("backup"):
				encrypted[rid] = BACKUP_OFFLINE
				GameState.post_event_f("🔐 Erpressungstrojaner auf %s. Das Backup läuft, gleich ist es wieder da.", [GameState.get_rack_display_name(rid)], "warn")
			else:
				encrypted[rid] = RANSOM_OFFLINE
				GameState.money = maxf(0.0, GameState.money - RANSOM_RECOVERY)
				FinanceManager.book("other", -RANSOM_RECOVERY)
				GameState.reputation = maxf(0.0, GameState.reputation - 3.0)
				GameState.post_event_f("🔐 Erpressungstrojaner hat %s verschlüsselt! Wiederherstellung kostet $%d und dauert 2 Minuten. Offline-Backups hätten geholfen.", [GameState.get_rack_display_name(rid), int(RANSOM_RECOVERY)], "alert")


func _log(kind: String, result: String) -> void:
	history.append({"day": GameState.day_number, "kind": kind, "result": result})
	while history.size() > HISTORY_MAX:
		history.pop_front()


func _tick_daily() -> void:
	var today: int = GameState.day_number
	if _last_day < 0:
		_last_day = today
		return
	if today == _last_day:
		return
	_last_day = today
	var cost := daily_cost()
	if cost > 0:
		FinanceManager.debit_public(float(cost) * GameState.diff("costs"), "Firewall-Lizenzen")


# ---------------------------------------------------------------- Anfragen

func request_set_rule(id: String, on: bool) -> void:
	_rpc_req_rule.rpc_id(1, id, on)


func request_block(source_id: String) -> void:
	_rpc_req_block.rpc_id(1, source_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_rule(id: String, on: bool) -> void:
	if not multiplayer.is_server() or not RULES.has(id):
		return
	var peer := _sender()
	if GameState._deny_build(peer, "business"):
		return
	if on:
		rules[id] = true
	else:
		rules.erase(id)
	_apply_ddos_flag()
	_feedback(peer, true, "Regel „%s“ %s.", [str(RULES[id]["name"]), "an" if on else "aus"])
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_block(source_id: String) -> void:
	if not multiplayer.is_server() or attack.is_empty():
		return
	var peer := _sender()
	for s in attack["sources"]:
		if str(s["id"]) == source_id and not bool(s["blocked"]):
			_block(s, NetworkManager.get_player_name(peer))
			GameState._rpc_play_sfx.rpc_id(peer, "click")
			break
	if bad_left() == 0:
		_end_attack(true)
	_broadcast()


## Alter Weg (Router [E], Knopf im Support-Hub): blockt einen Angreifer von Hand.
func manual_block(peer: int) -> void:
	if attack.is_empty():
		return
	for s in attack["sources"]:
		if bool(s["bad"]) and not bool(s["blocked"]):
			_block(s, NetworkManager.get_player_name(peer))
			break
	if bad_left() == 0:
		_end_attack(true)
	_broadcast()
