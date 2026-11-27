extends Node
## Betrieb der Anlage (Gameplay & Wirtschaft): Lastspitzen mit der USV kappen (GAME-02),
## Diesel-Notstrom mit Tank (GAME-01), Fernwärme (GAME-08) und Zertifizierungen (GAME-09).
## Der Host rechnet und speichert, die Clients bekommen den Stand und schicken nur Anfragen.

signal operations_changed
signal action_result(ok: bool, message: String)

# ---------------------------------------------------------------- GAME-01 Notstrom

## Aggregate: aufgestellte Notstromaggregate (Einrichtung) und das Container-Aggregat an Halle Nord.
const GEN_SPECS := {
	"prop_diesel_gen": {"name": "Notstromaggregat 40 kVA", "kw": 32.0, "tank": 200.0, "l_per_kwh": 0.30, "start_s": 15.0},
	"nord": {"name": "2-MVA-Aggregat Halle Nord", "kw": 1600.0, "tank": 2000.0, "l_per_kwh": 0.26, "start_s": 12.0},
}
## Diesel: $ je Liter, Bestellmengen und Sekunden bis der Tankwagen da ist.
const DIESEL_PRICE := 3.2
const ORDER_SIZES: Array[int] = [50, 200, 500, 1000]
const TANKER_DELAY := 75.0
## Tank des Halle-Nord-Aggregats nach dem Kauf (Liter).
const NORD_START_FUEL := 400.0

## GAME-02: USV gibt in der Abendspitze Strom ab und lädt nachts nach.
var peak_shaving := false
## Halle-Nord-Aggregat: Tank, läuft, Restsekunden bis es läuft (0 = steht).
var nord_fuel := 0.0
var nord_running := false
var nord_starting := 0.0
var nord_init := false
## Unterwegs: [{"l": Liter, "t": Sekunden bis Ankunft}]
var fuel_orders: Array = []

# ---------------------------------------------------------------- GAME-08 Fernwärme
## Anteil der IT-Leistung, der als nutzbare Wärme ins Netz geht.
const HEAT_RECOVERY := 0.65
## $ je kWh Wärme bei normaler Nachfrage.
const HEAT_PRICE := 0.42
## Nachfrage je Jahreszeit (Frühling, Sommer, Herbst, Winter).
const HEAT_DEMAND := [1.0, 0.35, 1.0, 1.6]
var heat_kwh_today := 0.0
var heat_money_today := 0.0
var heat_kwh_total := 0.0
var heat_money_total := 0.0
var _heat_day := -1

# ---------------------------------------------------------------- GAME-09 Zertifikate
const CERTS := {
	"tier3": {"name": "Tier III (Rechenzentrums-Verfügbarkeit)", "fee": 4000, "mult": 1.15,
		"desc": "Prüft, ob der Betrieb einen Ausfall übersteht: Notstrom, USV und doppelte Einspeisung."},
	"iso27001": {"name": "ISO 27001 (Informationssicherheit)", "fee": 3000, "mult": 1.10,
		"desc": "Prüft Firewall, Backups, Überwachung und Wachdienst."},
}
const CERT_ORDER: Array[String] = ["tier3", "iso27001"]
## Sekunden bis der Prüfer kommt und wie lange er durch die Garage geht.
const AUDIT_DELAY := 45.0
const AUDIT_WALK := 32.0
## Weg des Prüfers in der Garage (vom Tor zu den Racks, zum Kasten und zurück).
const AUDIT_ROUTE: Array[Vector3] = [Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, 3.0), Vector3(0.6, 0.0, 0.6), Vector3(-2.4, 0.0, -1.6), Vector3(2.0, 0.0, -2.4), Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, 6.0)]
## id -> {"valid_until": Tag, "last": [nicht erfüllte Punkte], "last_day": Tag, "passed": bool}
var certs: Dictionary = {}
## Laufende Prüfung: {"cert", "phase": "wait"|"walk", "t"}
var audit: Dictionary = {}

var _dirty := false
var _was_active := false
var _overload := 0.0
var _fuel_sync := 0.0
## Nach Überlast bleibt das Aggregat bis zum Ende des Ausfalls aus (kein Dauer-Anlassen).
var _tripped := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	var active: bool = NetworkManager.is_in_session and GameState.is_active
	if not active:
		if _was_active:
			_was_active = false
			reset()
		return
	_was_active = true
	if not multiplayer.is_server():
		return
	if not nord_init and GameState.has_building_upgrade("upg_diesel_gen"):
		init_nord_tank(false)
	if _dirty:
		_dirty = false
		_broadcast()


func reset() -> void:
	heat_kwh_today = 0.0
	heat_money_today = 0.0
	heat_kwh_total = 0.0
	heat_money_total = 0.0
	_heat_day = -1
	certs = {}
	audit = {}
	peak_shaving = false
	nord_fuel = 0.0
	nord_running = false
	nord_starting = 0.0
	nord_init = false
	fuel_orders = []
	_overload = 0.0
	operations_changed.emit()


func export_data() -> Dictionary:
	return {
		"peak_shaving": peak_shaving, "nord_fuel": nord_fuel, "nord_running": nord_running, "nord_starting": nord_starting,
		"nord_init": nord_init, "fuel_orders": fuel_orders.duplicate(true),
		"heat": [heat_kwh_today, heat_money_today, heat_kwh_total, heat_money_total, _heat_day],
		"certs": certs.duplicate(true), "audit": audit.duplicate(true),
	}


func import_data(d: Dictionary) -> void:
	peak_shaving = bool(d.get("peak_shaving", false))
	nord_fuel = clampf(float(d.get("nord_fuel", 0.0)), 0.0, float(GEN_SPECS["nord"]["tank"]))
	nord_running = bool(d.get("nord_running", false))
	nord_starting = maxf(0.0, float(d.get("nord_starting", 0.0)))
	nord_init = bool(d.get("nord_init", false))
	fuel_orders = []
	for o in (d.get("fuel_orders", []) if d.get("fuel_orders", []) is Array else []):
		if o is Dictionary:
			fuel_orders.append({"l": clampf(float(o.get("l", 0.0)), 0.0, 5000.0), "t": maxf(0.0, float(o.get("t", 0.0)))})
	var h: Variant = d.get("heat", [])
	if h is Array and (h as Array).size() >= 5:
		heat_kwh_today = float(h[0])
		heat_money_today = float(h[1])
		heat_kwh_total = float(h[2])
		heat_money_total = float(h[3])
		_heat_day = int(h[4])
	certs = {}
	var cv: Variant = d.get("certs", {})
	if cv is Dictionary:
		for k in (cv as Dictionary).keys():
			if CERTS.has(str(k)) and cv[k] is Dictionary:
				certs[str(k)] = (cv[k] as Dictionary).duplicate(true)
	audit = (d.get("audit", {}) as Dictionary).duplicate(true) if d.get("audit", {}) is Dictionary else {}
	if not audit.is_empty() and not CERTS.has(str(audit.get("cert", ""))):
		audit = {}
	operations_changed.emit()


func mark_dirty() -> void:
	_dirty = true


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
	operations_changed.emit()
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


# ---------------------------------------------------------------- GAME-02 Lastspitzen kappen

func request_set_peak_shaving(on: bool) -> void:
	_rpc_req_peak_shaving.rpc_id(1, on)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_peak_shaving(on: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if GameState._deny_build(peer, "business"):
		return
	peak_shaving = on
	_feedback(peer, true, "USV kappt jetzt die Abendspitze und lädt nachts nach." if on else "USV hält ihre Ladung wieder nur für Ausfälle bereit.")
	_broadcast()


# ---------------------------------------------------------------- GAME-01 Aggregate

## Alle Aggregate: [{id, kind, name, fuel, tank, kw, running, starting}]. kind = Schlüssel in GEN_SPECS.
func generators() -> Array:
	var out: Array = []
	for did in GameState.decor_items.keys():
		var d: Dictionary = GameState.decor_items[did]
		if str(d.get("item_type", "")) != GameState.DIESEL_GEN_TYPE:
			continue
		var spec: Dictionary = GEN_SPECS["prop_diesel_gen"]
		out.append({"id": str(did), "kind": "prop_diesel_gen", "name": str(spec["name"]), "fuel": float(d.get("fuel", 0.0)),
			"tank": float(spec["tank"]), "kw": float(spec["kw"]), "running": bool(d.get("running", false)), "starting": float(d.get("starting", 0.0))})
	if GameState.has_building_upgrade("upg_diesel_gen"):
		var ns: Dictionary = GEN_SPECS["nord"]
		out.append({"id": "nord", "kind": "nord", "name": str(ns["name"]), "fuel": nord_fuel, "tank": float(ns["tank"]), "kw": float(ns["kw"]),
			"running": nord_running, "starting": nord_starting})
	return out


func _set_gen(id: String, key: String, value: Variant) -> void:
	if id == "nord":
		match key:
			"fuel":
				nord_fuel = float(value)
			"running":
				nord_running = bool(value)
			"starting":
				nord_starting = float(value)
		return
	if GameState.decor_items.has(id):
		GameState.decor_items[id][key] = value


## Tank des Halle-Nord-Aggregats beim Kauf (oder voll für alte Spielstände, SaveSchema 6).
func init_nord_tank(full: bool) -> void:
	nord_init = true
	nord_fuel = float(GEN_SPECS["nord"]["tank"]) if full else NORD_START_FUEL
	_dirty = true


func tank_capacity() -> float:
	var cap := 0.0
	for gen in generators():
		cap += float(gen["tank"])
	return cap


func fuel_total() -> float:
	var f := 0.0
	for gen in generators():
		f += float(gen["fuel"])
	return f


func fuel_ordered() -> float:
	var l := 0.0
	for o in fuel_orders:
		l += float(o["l"])
	return l


func is_gen_running(id: String) -> bool:
	for gen in generators():
		if str(gen["id"]) == id:
			return bool(gen["running"])
	return false


## Nur Host, aus dem Sim-Schritt. Netzausfall: Aggregate mit Diesel springen nach start_s an, bis dahin
## überbrückt die USV. Netz zurück: Aggregate gehen aus. Diesel wird nach Last verbraucht.
func tick_generators(dt: float) -> void:
	if not multiplayer.is_server():
		return
	_tick_fuel_orders(dt)
	var gens := generators()
	var outage := GameState.grid_outage_left > 0.0 and GameState._grid_breaker_restore
	if not outage:
		_tripped = false
		var any := false
		for gen in gens:
			if bool(gen["running"]) or float(gen["starting"]) > 0.0:
				_set_gen(str(gen["id"]), "running", false)
				_set_gen(str(gen["id"]), "starting", 0.0)
				any = true
		if GameState.on_generator or any:
			GameState.on_generator = false
			_overload = 0.0
			_changed(true)
		return
	if gens.is_empty():
		return
	if GameState.on_generator:
		_run_on_generator(dt, gens)
		return
	if _tripped:
		return
	# Anlassen
	var started := false
	for gen in gens:
		var id := str(gen["id"])
		if float(gen["fuel"]) <= 0.0:
			continue
		var left := float(gen["starting"])
		if left <= 0.0 and not bool(gen["running"]):
			left = float(GEN_SPECS[str(gen["kind"])]["start_s"])
			_set_gen(id, "starting", left)
			GameState.post_event_f("🛢 %s startet …", [str(gen["name"])], "info")
			_changed(true)
			continue
		left -= dt
		if left <= 0.0:
			_set_gen(id, "starting", 0.0)
			_set_gen(id, "running", true)
			started = true
		else:
			_set_gen(id, "starting", left)
	if started:
		GameState.on_generator = true
		GameState.breaker_on = true
		GameState.overload_timer = 0.0
		GameState._broadcast_power_change()
		GameState._rpc_play_sfx.rpc("breaker_on")
		GameState.post_event("⚡ Notstrom-Aggregat läuft: Die Anlage hängt am Diesel, bis das Netz zurück ist.", "good")
		_changed(true)


func _run_on_generator(dt: float, gens: Array) -> void:
	var load_kw := float(GameState.total_watts) / 1000.0
	var cap := 0.0
	var running: Array = []
	for gen in gens:
		if bool(gen["running"]) and float(gen["fuel"]) > 0.0:
			cap += float(gen["kw"])
			running.append(gen)
	if load_kw > cap * 1.05:
		_overload += dt
		if _overload >= 3.0:
			_stop_all(gens, "NOTSTROM ÜBERLASTET: %d kW bei höchstens %d kW. Das Aggregat hat abgeschaltet.", [int(load_kw), int(cap)])
			_tripped = true
			return
	else:
		_overload = maxf(0.0, _overload - dt)
	var kwh := load_kw * dt / GameState.DAY_LENGTH_SECONDS * 24.0
	var empty := 0
	for gen in running:
		var share := float(gen["kw"]) / maxf(cap, 0.001)
		var liters := kwh * share * float(GEN_SPECS[str(gen["kind"])]["l_per_kwh"])
		var fuel := maxf(0.0, float(gen["fuel"]) - liters)
		_set_gen(str(gen["id"]), "fuel", fuel)
		if fuel <= 0.0:
			_set_gen(str(gen["id"]), "running", false)
			empty += 1
	if empty >= running.size():
		_stop_all(gens, "DIESEL LEER: Das Notstrom-Aggregat steht. Diesel in der App Betrieb bestellen.", [])
		return
	_fuel_sync += dt
	if _fuel_sync >= 4.0:
		_fuel_sync = 0.0
		_changed(true)


func _stop_all(gens: Array, msg: String, args: Array) -> void:
	for gen in gens:
		_set_gen(str(gen["id"]), "running", false)
		_set_gen(str(gen["id"]), "starting", 0.0)
	_overload = 0.0
	GameState.on_generator = false
	GameState.breaker_on = false
	GameState._broadcast_power_change()
	GameState._rpc_play_sfx.rpc("power_down")
	GameState.post_event_f(msg, args, "alert")
	_changed(true)


func _changed(decor_too: bool) -> void:
	_dirty = true
	if decor_too:
		GameState._broadcast_decor_items()


func _tick_fuel_orders(dt: float) -> void:
	if fuel_orders.is_empty():
		return
	var arrived := 0.0
	var keep: Array = []
	for o in fuel_orders:
		o["t"] = float(o["t"]) - dt
		if float(o["t"]) <= 0.0:
			arrived += float(o["l"])
		else:
			keep.append(o)
	if arrived <= 0.0:
		return
	fuel_orders = keep
	var left := arrived
	for gen in generators():
		var room := float(gen["tank"]) - float(gen["fuel"])
		var add := minf(room, left)
		if add > 0.0:
			_set_gen(str(gen["id"]), "fuel", float(gen["fuel"]) + add)
			left -= add
	GameState.post_event_f("🚚 Tankwagen: %d l Diesel getankt.", [int(arrived - left)], "good")
	if left > 0.5:
		GameState.post_event_f("%d l passten nicht mehr in die Tanks und fuhren wieder mit.", [int(left)], "warn")
	_changed(true)


func request_order_diesel(liters: int) -> void:
	_rpc_req_order_diesel.rpc_id(1, liters)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_order_diesel(liters: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if GameState._deny_build(peer, "buy"):
		return
	if not (liters in ORDER_SIZES):
		return
	if generators().is_empty():
		_feedback(peer, false, "Erst ein Notstromaggregat aufstellen.")
		return
	var room := tank_capacity() - fuel_total() - fuel_ordered()
	if float(liters) > room + 0.5:
		_feedback(peer, false, "In die Tanks passen nur noch %d l.", [int(maxf(room, 0.0))])
		return
	var cost := float(liters) * DIESEL_PRICE
	if GameState.money < cost:
		_feedback(peer, false, "Nicht genug Geld: %d l Diesel kosten $%d.", [liters, int(cost)])
		return
	GameState.money -= cost
	FinanceManager.book("fuel", -cost)
	fuel_orders.append({"l": float(liters), "t": TANKER_DELAY})
	GameState.post_event_f("%s hat %d l Diesel bestellt ($%d). Der Tankwagen kommt in gut einer Minute.", [NetworkManager.get_player_name(peer), liters, int(cost)], "info")
	_feedback(peer, true, "%d l Diesel bestellt.", [liters])
	GameState._broadcast_sim_tick()
	_dirty = true


# ---------------------------------------------------------------- Redundanz

## "N" (nur Netz), "N+1" (USV oder Aggregat) oder "2N" (USV und Aggregat, alle Racks mit A+B-Einspeisung).
func redundancy_level() -> String:
	var ups_ok := false
	for uid in GameState.ups_units.keys():
		var u: Dictionary = GameState.ups_units[uid]
		if bool(u.get("connected", false)) and float(u.get("charge", 0.0)) >= 50.0:
			ups_ok = true
	var cap := 0.0
	for gen in generators():
		if float(gen["fuel"]) >= float(gen["tank"]) * 0.1:
			cap += float(gen["kw"])
	var gen_ok := cap > 0.0 and cap >= float(GameState.total_watts) / 1000.0
	if ups_ok and gen_ok and all_racks_ab():
		return "2N"
	if ups_ok or gen_ok:
		return "N+1"
	return "N"


## Jedes Rack mit Servern hängt an zwei Stromkabeln (A- und B-Einspeisung).
func all_racks_ab() -> bool:
	var any := false
	for rid in GameState.racks.keys():
		if RackData.of(GameState.racks[rid]).used_slots().is_empty():
			continue
		any = true
		if GameState.count_cables_on("power", str(rid)) < 2:
			return false
	return any


# ---------------------------------------------------------------- GAME-08 Fernwärme

func has_heat() -> bool:
	return GameState.has_building_upgrade("upg_district_heat")


func heat_demand() -> float:
	return float(HEAT_DEMAND[clampi(OutdoorManager.season_index(), 0, 3)])


## Wärmeleistung gerade jetzt in kW (0 ohne Anschluss).
func heat_kw_now() -> float:
	if not has_heat():
		return 0.0
	return float(GameState.total_watts) / 1000.0 * HEAT_RECOVERY


## Nur Host, aus dem Sim-Schritt: Wärme zählen, einmal am Tag abrechnen.
func tick_heat(dt: float) -> void:
	if not multiplayer.is_server():
		return
	var today: int = GameState.day_number
	if _heat_day < 0:
		_heat_day = today
	if today != _heat_day:
		_pay_heat()
		_heat_day = today
	if not has_heat():
		return
	var kwh := heat_kw_now() * dt / GameState.DAY_LENGTH_SECONDS * 24.0
	heat_kwh_today += kwh
	heat_money_today += kwh * HEAT_PRICE * heat_demand() * GameState.diff("revenue")


func _pay_heat() -> void:
	if heat_money_today >= 1.0:
		var pay := heat_money_today
		GameState.money += pay
		FinanceManager.book("heat", pay)
		heat_kwh_total += heat_kwh_today
		heat_money_total += pay
		GameState.reputation = minf(100.0, GameState.reputation + (0.3 if heat_kwh_today >= 20.0 else 0.1))
		GameState.post_event_f("♨ Fernwärme: %d kWh Abwärme verkauft, +$%d.", [int(heat_kwh_today), int(pay)], "good")
	heat_kwh_today = 0.0
	heat_money_today = 0.0
	_dirty = true


# ---------------------------------------------------------------- GAME-09 Zertifikate

func days_per_year() -> int:
	return int(OutdoorManager.DAYS_PER_SEASON * 4.0)


func cert_valid(id: String) -> bool:
	return certs.has(id) and int((certs[id] as Dictionary).get("valid_until", 0)) >= GameState.day_number


## Faktor auf Mieten und Vertragseinnahmen durch gültige Zertifikate.
func cert_mult() -> float:
	var m := 1.0
	for id in CERTS.keys():
		if cert_valid(id):
			m *= float(CERTS[id]["mult"])
	return m


## Prüfpunkte eines Zertifikats: [[Text, erfüllt]].
func cert_checks(id: String) -> Array:
	var out: Array = []
	match id:
		"tier3":
			var gen_ok := false
			for gen in generators():
				if float(gen["fuel"]) >= float(gen["tank"]) * 0.25:
					gen_ok = true
			var ups_ok := false
			for uid in GameState.ups_units.keys():
				var u: Dictionary = GameState.ups_units[uid]
				if bool(u.get("connected", false)) and float(u.get("charge", 0.0)) >= 50.0:
					ups_ok = true
			var hot := false
			for rid in GameState.racks.keys():
				if float(GameState.racks[rid].get("temp", 22.0)) >= 35.0:
					hot = true
			out.append(["Notstrom-Aggregat mit mindestens 25 % Diesel", gen_ok])
			out.append(["USV angeschlossen und über 50 % geladen", ups_ok])
			out.append(["Jedes Rack mit Servern an zwei Stromkabeln (A+B)", all_racks_ab()])
			out.append(["Kein Brand, kein abgestürzter Server", not GameState.has_any_fire() and not GameState.has_any_crash()])
			out.append(["Alle Racks unter 35 °C", not hot])
		"iso27001":
			var recent_loss := false
			for h in Cyber.history:
				if str(h.get("result", "")) == "durchgekommen" and int(h.get("day", 0)) >= GameState.day_number - 5:
					recent_loss = true
			out.append(["Firewall: Ports geschlossen und Einbruchserkennung an", Cyber.has_rule("ports") and Cyber.has_rule("ids")])
			out.append(["Offline-Backups an", Cyber.has_rule("backup")])
			out.append(["Überwachungskamera an der Lieferzone", DecorManager.has_camera(Vector3(0.0, 0.0, 6.0))])
			out.append(["Sicherheitsdienst eingestellt", not Staff.worker("security").is_empty()])
			out.append(["Kein erfolgreicher Angriff in den letzten 5 Tagen", not recent_loss])
	return out


func request_audit(id: String) -> void:
	_rpc_req_audit.rpc_id(1, id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_audit(id: String) -> void:
	if not multiplayer.is_server() or not CERTS.has(id):
		return
	var peer := _sender()
	if GameState._deny_build(peer, "business"):
		return
	if not audit.is_empty():
		_feedback(peer, false, "Es läuft schon eine Prüfung.")
		return
	var fee := float(CERTS[id]["fee"]) * maxf(GameState.diff("costs"), 0.0)
	if GameState.money < fee:
		_feedback(peer, false, "Die Prüfung kostet $%d.", [int(fee)])
		return
	GameState.money -= fee
	FinanceManager.book("other", -fee)
	audit = {"cert": id, "phase": "wait", "t": AUDIT_DELAY}
	GameState.post_event_f("📋 Prüfung „%s“ beantragt ($%d). Der Prüfer kommt in gut einer halben Minute.", [str(CERTS[id]["name"]), int(fee)], "info")
	_feedback(peer, true, "Prüfung beantragt.")
	GameState._broadcast_sim_tick()
	_broadcast()


## Nur Host, aus dem Sim-Schritt: Prüfer kommen lassen, laufen lassen, Ergebnis.
func tick_audit(dt: float) -> void:
	if not multiplayer.is_server():
		return
	for id in certs.keys():
		var c: Dictionary = certs[id]
		if bool(c.get("passed", false)) and int(c.get("valid_until", 0)) < GameState.day_number and not bool(c.get("expired_told", false)):
			c["expired_told"] = true
			GameState.post_event_f("📋 Zertifikat „%s“ ist abgelaufen. Für die höheren Mieten neue Prüfung beantragen.", [str(CERTS[id]["name"])], "warn")
			_dirty = true
	if audit.is_empty():
		return
	audit["t"] = float(audit["t"]) - dt
	if float(audit["t"]) > 0.0:
		return
	if str(audit["phase"]) == "wait":
		audit["phase"] = "walk"
		audit["t"] = AUDIT_WALK
		Staff.show_visitor("auditor", "Prüfer", "walk", "prüft „%s“", AUDIT_ROUTE, AUDIT_WALK, [str(CERTS[str(audit["cert"])]["name"])])
		GameState.post_event("📋 Der Prüfer ist da und geht durch die Anlage.", "info")
		_dirty = true
		return
	_finish_audit()


func _finish_audit() -> void:
	var id := str(audit["cert"])
	audit = {}
	Staff.hide_visitor("auditor")
	var failed: Array = []
	for chk in cert_checks(id):
		if not bool(chk[1]):
			failed.append(str(chk[0]))
	var c: Dictionary = certs.get(id, {})
	c["last_day"] = GameState.day_number
	c["last"] = failed
	if failed.is_empty():
		c["passed"] = true
		c["expired_told"] = false
		c["valid_until"] = GameState.day_number + days_per_year()
		GameState.reputation = minf(100.0, GameState.reputation + 5.0)
		GameState.post_event_f("🏅 Bestanden: „%s“ gilt bis Tag %d. Mieten und Verträge zahlen ×%.2f.", [str(CERTS[id]["name"]), int(c["valid_until"]), float(CERTS[id]["mult"])], "good")
		GameState._rpc_play_sfx.rpc("upgrade")
	else:
		GameState.post_event_f("📋 Nicht bestanden: „%s“. Offen sind noch %d Punkte, die Liste steht in der App Betrieb.", [str(CERTS[id]["name"]), failed.size()], "warn")
	certs[id] = c
	_dirty = true
