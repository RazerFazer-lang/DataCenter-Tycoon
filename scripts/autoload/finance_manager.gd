extends Node
## Finanzen der Firma: Mitarbeiter, Bankkredite und Rechnungen.
## Der Host rechnet alles aus und schickt den Stand an die Clients.
## Clients schicken nur Anfragen (einstellen, Kredit aufnehmen, Rechnung bezahlen ...).
##   - Mitarbeiter: Tageslohn. Support-Agenten beantworten Tickets, Buchhalter bezahlen Rechnungen.
##   - Bank: Kredite mit Zins, Laufzeit und täglicher Rate, Bonität und Kontoauszug.
##   - Rechnungen: Strom (täglich), Garagenmiete, Internet, Versicherung, Netzentgelt,
##     Wartungsvertrag Klima & USV und Server-Lizenzen (wöchentlich),
##     jeweils mit Fälligkeit, Mahnstufen und am Ende Inkasso.

signal finance_changed
signal action_result(ok: bool, message: String)

const MAX_EMPLOYEES := 9
const MAX_ACTIVE_LOANS := 3
const STATEMENT_MAX := 60
const PAID_HISTORY_MAX := 30
const WEEK_DAYS := 7
const DUNNING_FEE_FLAT := 25
const DUNNING_FEE_PCT := 0.05
const DUNNING_GRACE_DAYS := 2
const MAX_DUNNING_LEVEL := 3
const COLLECTION_FEE_PCT := 0.25
const LOAN_LATE_PENALTY_PCT := 0.05
const EARLY_REPAY_DISCOUNT := 0.03
const SEVERANCE_DAYS := 2
const SCORE_MIN := 300
const SCORE_MAX := 850
const SCORE_START := 600
const CREDIT_LIMIT_PER_POINT := 180
## Jede Firmenstufe über 1 erhöht den Kreditrahmen um diesen Anteil.
const CREDIT_LIMIT_LEVEL_BONUS := 0.25
const SUPPORT_BASE_INTERVAL := 70.0
const SUPPORT_SKILL_STEP := 10.0
const SUPPORT_MIN_INTERVAL := 15.0
const ACCOUNTING_CHECK_INTERVAL := 8.0

const RENT_WEEKLY := 450.0
const INTERNET_BASE := 29.0
const INTERNET_PER_MBPS := 0.12
const INSURANCE_BASE := 60.0
const INSURANCE_PER_RACK := 25.0
const GRID_FEE_BASE := 35.0
const GRID_FEE_PER_KW := 4.0
const MAINTENANCE_PER_COOLER := 22.0
const MAINTENANCE_PER_UPS := 18.0
const LICENSE_PER_RACK := 15.0

const ROLES := {
	"support": {
		"title": "Support-Agent",
		"desc": "Beantwortet offene Support-Tickets und verschafft dir Zeit zum Aufrüsten.",
		"icon": "headset",
	},
	"accounting": {
		"title": "Buchhalter",
		"desc": "Bezahlt Rechnungen automatisch vor der Fälligkeit, wenn genug Geld da ist.",
		"icon": "invoice",
	},
	"netadmin": {
		"title": "Netzwerk-Admin",
		"desc": "Wehrt Cyberangriffe an der Firewall ab, bevor Kunden es merken. Erfahrene Admins blocken schneller und treffen genauer.",
		"icon": "net",
	},
	"security": {
		"title": "Sicherheitsdienst",
		"desc": "Läuft nachts Streife vor der Garage, schreckt Diebe ab und stellt sie.",
		"icon": "warn",
	},
	"cleaning": {
		"title": "Reinigung",
		"desc": "Entstaubt tagsüber die Racks in der Garage. Weniger Staub heißt kühlere und zuverlässigere Server.",
		"icon": "drop",
	},
	"technician": {
		"title": "Techniker",
		"desc": "Baut Bausätze, repariert defekte Server an der Werkbank und setzt sie wieder ein. Braucht Kits oder Teile aus dem Lager.",
		"icon": "building",
	},
}

## Sperren nach der letzten Mahnung. Nach dem Bezahlen gilt sofort wieder alles.
const BLOCK_KINDS: Array[String] = ["power", "grid_fee", "internet", "insurance", "license"]
const BLOCK_POWER_FACTOR := 0.35
const BLOCK_POWER_MIN := 900
const BLOCK_NET_FACTOR := 0.15
const BLOCK_LICENSE_FACTOR := 0.75
const BLOCK_WARNING := {
	"power": "Danach begrenzen wir Ihren Stromanschluss stark.",
	"grid_fee": "Danach begrenzen wir Ihren Stromanschluss stark.",
	"internet": "Danach drosseln wir Ihren Anschluss.",
	"insurance": "Danach zahlen wir bei Schäden nicht mehr.",
	"license": "Danach laufen Ihre Lizenzen nur noch eingeschränkt, das senkt Ihre Einnahmen.",
}
const BLOCK_TEXT := {
	"power": "Ihr Stromanschluss ist jetzt stark begrenzt (35 % der Leistung).",
	"grid_fee": "Ihr Stromanschluss ist jetzt stark begrenzt (35 % der Leistung).",
	"internet": "Ihr Internet ist jetzt auf 15 % gedrosselt.",
	"insurance": "Ihr Versicherungsschutz ruht. Schäden zahlen wir nicht.",
	"license": "Ihre Lizenzen sind eingeschränkt, Ihre Einnahmen sinken um 25 %.",
}

const BILL_KINDS := {
	"power": {"vendor": "Stadtwerke Energie GmbH", "title": "Stromrechnung", "icon": "power", "due_days": 3},
	"rent": {"vendor": "Immobilien Krämer KG", "title": "Garagenmiete", "icon": "building", "due_days": 4},
	"internet": {"vendor": "NetLink Business", "title": "Internet-Anschluss", "icon": "net", "due_days": 5},
	"insurance": {"vendor": "Hanse Gewerbeversicherung AG", "title": "Betriebsversicherung", "icon": "invoice", "due_days": 5},
	"grid_fee": {"vendor": "Stadtwerke Netz GmbH", "title": "Netzentgelt", "icon": "power", "due_days": 5},
	"maintenance": {"vendor": "KälteTec Service GmbH", "title": "Wartungsvertrag Klima & USV", "icon": "temp", "due_days": 6},
	"license": {"vendor": "Nordlicht Software AG", "title": "Server-Lizenzen", "icon": "verion", "due_days": 5},
}

const LOAN_OFFERS := [
	{"id": "mikro", "title": "Mikrokredit", "amount": 2500, "days": 5, "rate": 0.06, "min_score": 0, "min_level": 1},
	{"id": "gruender", "title": "Gründerkredit", "amount": 10000, "days": 10, "rate": 0.10, "min_score": 560, "min_level": 2},
	{"id": "invest", "title": "Investitionskredit", "amount": 40000, "days": 20, "rate": 0.15, "min_score": 680, "min_level": 3},
	{"id": "wachstum", "title": "Wachstumskredit", "amount": 80000, "days": 25, "rate": 0.14, "min_score": 720, "min_level": 4},
	{"id": "konzern", "title": "Konzernkredit", "amount": 120000, "days": 30, "rate": 0.12, "min_score": 780, "min_level": 5},
]

const CANDIDATE_POOL := [
	{"name": "Lena Hoffmann", "role": "support", "skill": 2, "wage": 110},
	{"name": "Jonas Becker", "role": "support", "skill": 4, "wage": 185},
	{"name": "Aylin Demir", "role": "support", "skill": 3, "wage": 145},
	{"name": "Tim Schulz", "role": "support", "skill": 5, "wage": 240},
	{"name": "Marco Rossi", "role": "accounting", "skill": 2, "wage": 120},
	{"name": "Sabine Wolf", "role": "accounting", "skill": 3, "wage": 160},
	{"name": "Julia Neumann", "role": "accounting", "skill": 5, "wage": 230},
	# Neue Bewerbungen immer hinten anfügen: gespeicherte Spielstände merken sich den Platz in der Liste.
	{"name": "Kim Vogt", "role": "technician", "skill": 2, "wage": 150},
	{"name": "Robin Krause", "role": "technician", "skill": 3, "wage": 205},
	{"name": "Alex Brandt", "role": "technician", "skill": 5, "wage": 340},
	# GAME-07
	{"name": "Deniz Arslan", "role": "netadmin", "skill": 3, "wage": 220},
	{"name": "Sven Lorenz", "role": "netadmin", "skill": 5, "wage": 330},
	{"name": "Paul Wagner", "role": "security", "skill": 2, "wage": 130},
	{"name": "Olga Sommer", "role": "security", "skill": 4, "wage": 190},
	{"name": "Ines Krüger", "role": "cleaning", "skill": 2, "wage": 95},
	{"name": "Murat Yilmaz", "role": "cleaning", "skill": 4, "wage": 140},
]

# ---------------------------------------------------------------- GAME-04 Investoren & Monatsbilanz

## Ein Monat in der Bilanz (Spieltage).
const MONTH_DAYS := 30
## So viele Tage bleibt das Kassenbuch.
const LEDGER_DAYS := 95
## Kategorien der Bilanz: Schlüssel -> Name. Einnahmen stehen in INCOME_CATS.
const LEDGER_CATS := {
	"contracts": "Verträge", "rentals": "Mieten", "heat": "Fernwärme", "loans_in": "Kredite (Auszahlung)", "invest_in": "Investoren (Einlage)",
	"wages": "Löhne & Personal", "bills": "Rechnungen", "loans": "Kreditraten", "penalties": "Vertragsstrafen",
	"investors": "Gewinnanteil Investoren", "fuel": "Diesel", "other": "Einkäufe & Sonstiges",
}
const INCOME_CATS: Array[String] = ["contracts", "rentals", "heat", "loans_in", "invest_in"]
## Investoren: Einlage gegen einen Anteil an allen Einnahmen aus Verträgen und Mieten, befristet.
const INVESTOR_OFFERS := [
	{"id": "angel", "title": "Business Angel", "amount": 15000, "share": 0.10, "days": 20, "min_level": 2},
	{"id": "vc", "title": "Wagniskapital-Fonds", "amount": 60000, "share": 0.15, "days": 30, "min_level": 3},
	{"id": "fund", "title": "Infrastruktur-Fonds", "amount": 200000, "share": 0.20, "days": 40, "min_level": 5},
]
const MAX_INVESTORS := 2
## Rückkauf: Anteil der Einlage, gewichtet mit der Restlaufzeit.
const BUYOUT_FACTOR := 0.4

## Laufende Beteiligungen: id -> {id, offer, title, amount, share, days_left, days_total, paid, day}
var investors: Dictionary = {}
## Kassenbuch: "Tag" -> {Kategorie: Betrag}. Einnahmen positiv, Ausgaben negativ.
var ledger: Dictionary = {}
## Kontostand zu Tagesbeginn (nur Host), damit der Rest des Tages als „Sonstiges“ stimmt.
var _day_money: Dictionary = {}

var employees: Dictionary = {}
var loans: Dictionary = {}
var bills: Dictionary = {}
var paid_bills: Array = []
var statement: Array = []
var credit_score: int = SCORE_START
var hired_pool: Array[int] = []

var _next_bill_num: int = 1001
var _next_loan_num: int = 1
var _next_emp_num: int = 1
var _next_weekly_day: int = -1
var _last_day: int = -1
var _work_accum: Dictionary = {}
var _accounting_accum: float = 0.0
var _was_active: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	GameState.world_snapshot_loaded.connect(_on_world_snapshot_loaded)


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
	# Leerer dedizierter Server: keine Gehälter, keine Rechnungen.
	if GameState.is_world_paused_for_empty_server():
		return
	var today: int = GameState.day_number
	if _last_day < 0:
		_last_day = today
		if _next_weekly_day < 0:
			_next_weekly_day = today + 1
		return
	while _last_day < today:
		_last_day += 1
		_run_day(_last_day)
	_tick_employees(delta)


func reset() -> void:
	investors.clear()
	ledger.clear()
	_day_money.clear()
	employees.clear()
	loans.clear()
	bills.clear()
	paid_bills.clear()
	statement.clear()
	hired_pool.clear()
	_work_accum.clear()
	credit_score = SCORE_START
	_next_bill_num = 1001
	_next_loan_num = 1
	_next_emp_num = 1
	_next_weekly_day = -1
	_last_day = -1
	_accounting_accum = 0.0
	finance_changed.emit()


# ---------------------------------------------------------------- Speichern / Laden / Sync

func export_data() -> Dictionary:
	var pool: Array = []
	for i in hired_pool:
		pool.append(i)
	return {
		"employees": employees.duplicate(true),
		"loans": loans.duplicate(true),
		"bills": bills.duplicate(true),
		"paid_bills": paid_bills.duplicate(true),
		"statement": statement.duplicate(true),
		"credit_score": credit_score,
		"hired_pool": pool,
		"next_bill_num": _next_bill_num,
		"next_loan_num": _next_loan_num,
		"next_emp_num": _next_emp_num,
		"next_weekly_day": _next_weekly_day,
		"investors": investors.duplicate(true),
		"ledger": ledger.duplicate(true),
		"day_money": _day_money.duplicate(),
	}


func import_data(d: Dictionary) -> void:
	employees = _as_dict(d.get("employees", {})).duplicate(true)
	loans = _as_dict(d.get("loans", {})).duplicate(true)
	bills = _as_dict(d.get("bills", {})).duplicate(true)
	paid_bills = _as_array(d.get("paid_bills", [])).duplicate(true)
	statement = _as_array(d.get("statement", [])).duplicate(true)
	credit_score = clampi(int(d.get("credit_score", SCORE_START)), SCORE_MIN, SCORE_MAX)
	hired_pool.clear()
	for v in _as_array(d.get("hired_pool", [])):
		hired_pool.append(int(v))
	_next_bill_num = int(d.get("next_bill_num", 1001))
	_next_loan_num = int(d.get("next_loan_num", 1))
	_next_emp_num = int(d.get("next_emp_num", 1))
	_next_weekly_day = int(d.get("next_weekly_day", -1))
	investors = _as_dict(d.get("investors", {})).duplicate(true)
	ledger = _as_dict(d.get("ledger", {})).duplicate(true)
	_day_money = _as_dict(d.get("day_money", {})).duplicate()
	_last_day = GameState.day_number if GameState.is_active else -1
	_work_accum.clear()
	finance_changed.emit()


func _on_world_snapshot_loaded() -> void:
	finance_changed.emit()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and NetworkManager.is_in_session:
		_rpc_sync.rpc_id(peer_id, export_data())


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(data: Dictionary) -> void:
	import_data(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_feedback(ok: bool, message: String, args: Array) -> void:
	action_result.emit(ok, format_text(message, args))


func _broadcast() -> void:
	finance_changed.emit()
	if NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_sync.rpc(export_data())


func _feedback(peer: int, ok: bool, message: String, args: Array = []) -> void:
	if peer == _me():
		action_result.emit(ok, format_text(message, args))
	elif peer > 0:
		_rpc_feedback.rpc_id(peer, ok, message, args)


## Übersetzt eine Vorlage in der Sprache dieses Spielers und setzt die Werte ein.
## Alte Einträge ohne Werte werden nur übersetzt (bzw. unverändert angezeigt).
func format_text(text: String, args: Variant = []) -> String:
	var t := tr(text)
	var a := _as_array(args)
	if a.is_empty():
		return t
	return t % _tr_args(a)


## Übersetzt eingesetzte Werte, die selbst Schlüssel sind (Kredittitel, Rollen,
## Rechnungsarten). Namen und Beträge sind keine Schlüssel und bleiben gleich.
func _tr_args(args: Array) -> Array:
	var out: Array = []
	for v in args:
		out.append(tr(v) if v is String else v)
	return out


func _detail(text: String, args: Array = []) -> Dictionary:
	return {"text": text, "args": args}


func _as_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _as_array(v: Variant) -> Array:
	return v if v is Array else []


func _is_host() -> bool:
	return multiplayer.is_server()


func _me() -> int:
	return multiplayer.get_unique_id()


# ---------------------------------------------------------------- Formatierung

static func format_money(v: float) -> String:
	var neg := v < 0.0
	var digits := str(int(roundf(absf(v))))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-$" if neg else "$") + out


# ---------------------------------------------------------------- Abfragen für die Apps

func get_role_title(role: String) -> String:
	if ROLES.has(role):
		var r: Dictionary = ROLES[role]
		return str(r["title"])
	return role


func get_employees_sorted() -> Array:
	var arr: Array = employees.values()
	arr.sort_custom(func(a, b): return int(a["hired_day"]) < int(b["hired_day"]))
	return arr


func get_candidates() -> Array:
	var out: Array = []
	for i in range(CANDIDATE_POOL.size()):
		if hired_pool.has(i):
			continue
		var c: Dictionary = (CANDIDATE_POOL[i] as Dictionary).duplicate()
		c["pool_idx"] = i
		out.append(c)
	return out


func get_daily_wage_total() -> int:
	var sum := 0
	for e_v in employees.values():
		var e: Dictionary = e_v
		sum += int(e["wage"])
	return sum


## Geänderte Mitarbeiterdaten (Schicht, Aufgaben, Zähler) an alle schicken.
func sync_employees() -> void:
	_broadcast()


func get_accountant() -> Dictionary:
	var best: Dictionary = {}
	for e_v in employees.values():
		var e: Dictionary = e_v
		if str(e["role"]) == "accounting" and (best.is_empty() or int(e["skill"]) > int(best["skill"])):
			best = e
	return best


func get_total_debt() -> float:
	var sum := 0.0
	for l_v in loans.values():
		var ln: Dictionary = l_v
		sum += float(ln["remaining"])
	return sum


func get_daily_loan_payments() -> float:
	var sum := 0.0
	for l_v in loans.values():
		var ln: Dictionary = l_v
		sum += minf(float(ln["daily_payment"]), float(ln["remaining"]))
	return sum


func get_credit_limit() -> int:
	var base := maxi(0, (credit_score - 400) * CREDIT_LIMIT_PER_POINT)
	return int(float(base) * get_credit_level_factor())


## Faktor auf den Kreditrahmen durch die Firmenstufe (Stufe 1 = 1.0).
func get_credit_level_factor() -> float:
	var steps := float(maxi(GameState.get_company_level() - 1, 0))
	return 1.0 + CREDIT_LIMIT_LEVEL_BONUS * (minf(steps, 4.0) + maxf(0.0, steps - 4.0) * 0.5)


func get_free_credit() -> float:
	return maxf(0.0, float(get_credit_limit()) - get_total_debt())


func get_score_label() -> String:
	if credit_score >= 750:
		return "Sehr gut"
	if credit_score >= 680:
		return "Gut"
	if credit_score >= 600:
		return "Befriedigend"
	if credit_score >= 500:
		return "Ausreichend"
	return "Kritisch"


func get_offer_total(offer: Dictionary) -> int:
	return int(ceilf(float(offer["amount"]) * (1.0 + float(offer["rate"]))))


func get_offer_daily(offer: Dictionary) -> int:
	return int(ceilf(float(get_offer_total(offer)) / float(maxi(1, int(offer["days"])))))


func get_offer_block_reason(offer: Dictionary) -> String:
	var parts := _offer_block_parts(offer)
	if parts.is_empty():
		return ""
	return format_text(str(parts[0]), parts[1])


func _offer_block_parts(offer: Dictionary) -> Array:
	if loans.size() >= MAX_ACTIVE_LOANS:
		return ["Höchstens %d Kredite gleichzeitig.", [MAX_ACTIVE_LOANS]]
	var min_level := int(offer.get("min_level", 1))
	var level: int = GameState.get_company_level()
	if level < min_level:
		return ["Ab Firmenstufe %d verfügbar (aktuell %d).", [min_level, level]]
	if credit_score < int(offer["min_score"]):
		return ["Bonität ab %d nötig (aktuell %d).", [int(offer["min_score"]), credit_score]]
	if float(get_offer_total(offer)) > get_free_credit():
		return ["Übersteigt deinen freien Kreditrahmen (%s).", [format_money(get_free_credit())]]
	return []


func get_loans_sorted() -> Array:
	var arr: Array = loans.values()
	arr.sort_custom(func(a, b): return int(a["taken_day"]) < int(b["taken_day"]))
	return arr


func get_loan_repay_cost(ln: Dictionary) -> int:
	return int(ceilf(float(ln["remaining"]) * (1.0 - EARLY_REPAY_DISCOUNT)))


func get_open_bills() -> Array:
	var arr: Array = bills.values()
	arr.sort_custom(func(a, b): return int(a["due_day"]) < int(b["due_day"]))
	return arr


func get_open_bills_total() -> float:
	var sum := 0.0
	for b_v in bills.values():
		var b: Dictionary = b_v
		sum += float(b["amount"])
	return sum


func get_dunning_count() -> int:
	var n := 0
	for b_v in bills.values():
		var b: Dictionary = b_v
		if int(b["dunning"]) > 0:
			n += 1
	return n


## true, solange eine Rechnung dieser Art nach der letzten Mahnung gesperrt ist.
func is_blocked(kind: String) -> bool:
	for b in bills.values():
		if str((b as Dictionary).get("kind", "")) == kind and bool((b as Dictionary).get("blocked", false)):
			return true
	return false


func is_power_blocked() -> bool:
	return is_blocked("power") or is_blocked("grid_fee")


func get_blocked_kinds() -> Array[String]:
	var out: Array[String] = []
	for k in BLOCK_KINDS:
		if is_blocked(k):
			out.append(k)
	return out


## Buchungen anderer Systeme (Werbung, Prämien, Versicherung), nur auf dem Host.
func debit_public(amount: float, text: String, args: Array = []) -> void:
	_debit(amount, text, GameState.day_number, args)
	_broadcast()


func credit_public(amount: float, text: String, args: Array = []) -> void:
	GameState.money += amount
	_add_statement(GameState.day_number, text, amount, args)
	book("other", amount)
	_broadcast()


func get_next_weekly_day() -> int:
	return _next_weekly_day


# ---------------------------------------------------------------- Anfragen (Client oder Host)

func request_hire(pool_idx: int) -> void:
	if _is_host():
		_do_hire(pool_idx, _me())
	else:
		_rpc_req_hire.rpc_id(1, pool_idx)


func request_fire(emp_id: String) -> void:
	if _is_host():
		_do_fire(emp_id, _me())
	else:
		_rpc_req_fire.rpc_id(1, emp_id)


func request_take_loan(offer_id: String) -> void:
	if _is_host():
		_do_take_loan(offer_id, _me())
	else:
		_rpc_req_take_loan.rpc_id(1, offer_id)


func request_repay_loan(loan_id: String) -> void:
	if _is_host():
		_do_repay_loan(loan_id, _me())
	else:
		_rpc_req_repay_loan.rpc_id(1, loan_id)


func request_pay_bill(bill_id: String) -> void:
	if _is_host():
		_do_pay_bill(bill_id, _me())
	else:
		_rpc_req_pay_bill.rpc_id(1, bill_id)


func request_pay_all() -> void:
	if _is_host():
		_do_pay_all(_me())
	else:
		_rpc_req_pay_all.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_hire(pool_idx: int) -> void:
	if multiplayer.is_server():
		_do_hire(pool_idx, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_fire(emp_id: String) -> void:
	if multiplayer.is_server():
		_do_fire(emp_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_take_loan(offer_id: String) -> void:
	if multiplayer.is_server():
		_do_take_loan(offer_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_repay_loan(loan_id: String) -> void:
	if multiplayer.is_server():
		_do_repay_loan(loan_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_pay_bill(bill_id: String) -> void:
	if multiplayer.is_server():
		_do_pay_bill(bill_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_pay_all() -> void:
	if multiplayer.is_server():
		_do_pay_all(multiplayer.get_remote_sender_id())


# ---------------------------------------------------------------- Host-Logik: Aktionen

func _do_hire(pool_idx: int, peer: int) -> void:
	if GameState._deny_build(peer, "business"):
		return
	if pool_idx < 0 or pool_idx >= CANDIDATE_POOL.size() or hired_pool.has(pool_idx):
		_feedback(peer, false, "Diese Bewerbung gibt es nicht mehr.")
		return
	if employees.size() >= MAX_EMPLOYEES:
		_feedback(peer, false, "Das Team ist voll (%d Personen).", [MAX_EMPLOYEES])
		return
	var c: Dictionary = CANDIDATE_POOL[pool_idx]
	var wage := int(c["wage"])
	if GameState.money < float(wage):
		_feedback(peer, false, "Für die Startprämie fehlen %s.", [format_money(float(wage) - GameState.money)])
		return
	var day: int = GameState.day_number
	var eid := "E-%d" % _next_emp_num
	_next_emp_num += 1
	employees[eid] = {
		"id": eid,
		"name": str(c["name"]),
		"role": str(c["role"]),
		"skill": int(c["skill"]),
		"wage": wage,
		"pool_idx": pool_idx,
		"hired_day": day,
		"work_done": 0,
	}
	if str(c["role"]) == "technician":
		employees[eid]["shift"] = "day"
		# Die zweite Person übernimmt gleich die Nachtschicht.
		for other in employees.values():
			if str(other["id"]) != eid and str(other["role"]) == "technician" and str(other.get("shift", "day")) == "day":
				employees[eid]["shift"] = "night"
		employees[eid]["duties"] = {"build": true, "repair": true, "service": true}
	hired_pool.append(pool_idx)
	_debit(float(wage), "Startprämie %s", day, [str(c["name"])])
	GameState.post_event_f("%s hat %s als %s eingestellt (%s pro Tag).", [
		NetworkManager.get_player_name(peer), str(c["name"]), get_role_title(str(c["role"])), format_money(float(wage))
	], "good")
	_feedback(peer, true, "%s eingestellt.", [str(c["name"])])
	_broadcast()


func _do_fire(emp_id: String, peer: int) -> void:
	if not GameState.is_destructive_action_allowed(peer):
		_feedback(peer, false, "Nur der Host darf Mitarbeiter entlassen (Host-Schutz aktiv).")
		return
	if not employees.has(emp_id):
		_feedback(peer, false, "Mitarbeiter nicht gefunden.")
		return
	var e: Dictionary = employees[emp_id]
	var severance := float(int(e["wage"]) * SEVERANCE_DAYS)
	_debit(severance, "Abfindung %s", GameState.day_number, [str(e["name"])])
	hired_pool.erase(int(e.get("pool_idx", -1)))
	employees.erase(emp_id)
	_work_accum.erase(emp_id)
	GameState.post_event_f("%s hat %s entlassen (Abfindung %s).", [
		NetworkManager.get_player_name(peer), str(e["name"]), format_money(severance)
	], "warn")
	_feedback(peer, true, "%s entlassen.", [str(e["name"])])
	_broadcast()


func _do_take_loan(offer_id: String, peer: int) -> void:
	if not SecurityGuard.check_rate_limit(peer, "loan", 4, 10.0):
		return
	if not GameState.is_destructive_action_allowed(peer):
		_feedback(peer, false, "Nur der Host darf Kredite aufnehmen (Host-Schutz aktiv).")
		return
	var offer := _find_offer(offer_id)
	if offer.is_empty():
		_feedback(peer, false, "Kreditangebot nicht gefunden.")
		return
	var block := _offer_block_parts(offer)
	if not block.is_empty():
		_feedback(peer, false, str(block[0]), _as_array(block[1]))
		return
	var amount := float(offer["amount"])
	var total := float(get_offer_total(offer))
	var days := int(offer["days"])
	var day: int = GameState.day_number
	var lid := "K-%03d" % _next_loan_num
	_next_loan_num += 1
	loans[lid] = {
		"id": lid,
		"title": str(offer["title"]),
		"principal": amount,
		"rate": float(offer["rate"]),
		"days_total": days,
		"days_left": days,
		"daily_payment": float(get_offer_daily(offer)),
		"total_due": total,
		"remaining": total,
		"taken_day": day,
		"missed": 0,
	}
	GameState.money += amount
	_add_statement(day, "Auszahlung %s %s", amount, [str(offer["title"]), lid])
	book("loans_in", amount)
	GameState.post_event_f("%s hat einen %s über %s aufgenommen (Rate %s pro Tag).", [
		NetworkManager.get_player_name(peer), str(offer["title"]), format_money(amount), format_money(float(get_offer_daily(offer)))
	], "info")
	_feedback(peer, true, "%s ausgezahlt: +%s", [str(offer["title"]), format_money(amount)])
	_broadcast()


func _do_repay_loan(loan_id: String, peer: int) -> void:
	if not loans.has(loan_id):
		_feedback(peer, false, "Kredit nicht gefunden.")
		return
	var ln: Dictionary = loans[loan_id]
	var cost := float(get_loan_repay_cost(ln))
	if GameState.money < cost:
		_feedback(peer, false, "Für die Sondertilgung fehlen %s.", [format_money(cost - GameState.money)])
		return
	_debit(cost, "Sondertilgung %s", GameState.day_number, [loan_id])
	loans.erase(loan_id)
	_change_score(20)
	GameState.post_event_f("%s hat Kredit %s vorzeitig abbezahlt (%s).", [
		NetworkManager.get_player_name(peer), loan_id, format_money(cost)
	], "good")
	_feedback(peer, true, "Kredit %s abbezahlt.", [loan_id])
	_broadcast()


func _do_pay_bill(bill_id: String, peer: int) -> void:
	if not bills.has(bill_id):
		_feedback(peer, false, "Rechnung nicht gefunden oder schon bezahlt.")
		return
	var b: Dictionary = bills[bill_id]
	var amount := float(b["amount"])
	if GameState.money < amount:
		_feedback(peer, false, "Für Rechnung %s fehlen %s.", [bill_id, format_money(amount - GameState.money)])
		return
	_settle_bill(b, NetworkManager.get_player_name(peer))
	_feedback(peer, true, "Rechnung %s bezahlt (%s).", [bill_id, format_money(amount)])
	_broadcast()


func _do_pay_all(peer: int) -> void:
	var paid := 0
	var skipped := 0
	var who := NetworkManager.get_player_name(peer)
	for b_v in get_open_bills():
		var b: Dictionary = b_v
		if GameState.money >= float(b["amount"]):
			_settle_bill(b, who)
			paid += 1
		else:
			skipped += 1
	if paid == 0:
		_feedback(peer, false, "Keine Rechnung bezahlt: zu wenig Geld oder nichts offen.")
		return
	if skipped > 0:
		_feedback(peer, true, "%d Rechnung(en) bezahlt. %d offen geblieben (zu wenig Geld).", [paid, skipped])
	else:
		_feedback(peer, true, "%d Rechnung(en) bezahlt.", [paid])
	_broadcast()


# ---------------------------------------------------------------- Host-Logik: Tagesabschluss

func _run_day(day: int) -> void:
	_close_ledger_day(day)
	_tick_investors(day)
	_pay_wages(day)
	_collect_loan_rates(day)
	_issue_power_bill(day)
	if _next_weekly_day >= 0 and day >= _next_weekly_day:
		_issue_weekly_bills(day)
		_next_weekly_day = day + WEEK_DAYS
	_process_dunning(day)
	if bills.is_empty() and loans.values().all(func(l): return int(l["missed"]) == 0):
		_change_score(2)
	_broadcast()


func _pay_wages(day: int) -> void:
	var total := get_daily_wage_total()
	if total <= 0:
		return
	_debit(float(total), "Löhne Tag %d (%d Mitarbeiter)", day, [day - 1, employees.size()])
	if GameState.money < 0.0:
		GameState.post_event_f("Löhne bezahlt (%s). Das Konto ist im Minus!", [format_money(float(total))], "warn")
	else:
		GameState.post_event_f("Löhne für Tag %d bezahlt: %s.", [day - 1, format_money(float(total))], "info")


func _collect_loan_rates(day: int) -> void:
	for lid in loans.keys():
		var ln: Dictionary = loans[lid]
		var pay := minf(float(ln["daily_payment"]), float(ln["remaining"]))
		if GameState.money >= pay:
			_debit(pay, "Kreditrate %s", day, [str(lid)])
			ln["remaining"] = maxf(0.0, float(ln["remaining"]) - pay)
			ln["days_left"] = maxi(0, int(ln["days_left"]) - 1)
			if float(ln["remaining"]) <= 0.01:
				loans.erase(lid)
				_change_score(15)
				GameState.post_event_f("Kredit %s ist vollständig getilgt.", [str(lid)], "good")
		else:
			var penalty := ceilf(float(ln["remaining"]) * LOAN_LATE_PENALTY_PCT)
			ln["remaining"] = float(ln["remaining"]) + penalty
			ln["missed"] = int(ln["missed"]) + 1
			_change_score(-25)
			GameState.post_event_f("Kreditrate %s geplatzt! Verzugszins %s, Bonität sinkt.", [str(lid), format_money(penalty)], "warn")


func _issue_power_bill(day: int) -> void:
	var amount := float(GameState.last_daily_bill)
	if amount <= 0.0:
		return
	var rate := float(GameState.last_bill_rate)
	var peak_cost := float(GameState.last_peak_kw) * PowerTariff.PEAK_CHARGE_PER_KW
	var energy := float(GameState.last_energy_cost)
	_issue_bill("power", amount, day, [
		_detail("Abrechnungszeitraum: Tag %d", [day - 1]),
		_detail("Arbeitspreis nach Tageszeit: $%d (Grundpreis $%.2f pro kWh, Nacht ×0,7, Abendspitze ×1,4)", [int(roundf(energy)), rate]),
		_detail("Leistungspreis: $%d für %.1f kW Spitzenlast", [int(roundf(peak_cost)), float(GameState.last_peak_kw)]),
	])


func _issue_weekly_bills(day: int) -> void:
	var last_day := day + WEEK_DAYS - 1
	_issue_bill("rent", RENT_WEEKLY, day, [
		_detail("Mietzeitraum: Tag %d bis %d", [day, last_day]),
		_detail("Gewerbegarage inkl. Nebenkosten"),
	])
	var mbps := float(GameState.max_bandwidth_mbps)
	var net_cost := roundf(INTERNET_BASE + mbps * INTERNET_PER_MBPS)
	_issue_bill("internet", net_cost, day, [
		_detail("Leistungszeitraum: Tag %d bis %d", [day, last_day]),
		_detail("Tarif: Business %s", [HardwareCatalog.format_speed_mbps(mbps)]),
		_detail("Grundgebühr $%.0f + $%.2f pro Mbit/s", [INTERNET_BASE, INTERNET_PER_MBPS]),
	])
	var rack_count: int = GameState.racks.size()
	var ins_cost := INSURANCE_BASE + INSURANCE_PER_RACK * float(rack_count)
	_issue_bill("insurance", ins_cost, day, [
		_detail("Versicherungszeitraum: Tag %d bis %d", [day, last_day]),
		_detail("Inventar- und Elektronikversicherung"),
		_detail("%d versicherte Racks à $%.0f", [rack_count, INSURANCE_PER_RACK]),
	])
	var kw := float(GameState.max_watts) / 1000.0
	var grid_cost := roundf(GRID_FEE_BASE + kw * GRID_FEE_PER_KW)
	_issue_bill("grid_fee", grid_cost, day, [
		_detail("Abrechnungszeitraum: Tag %d bis %d", [day, last_day]),
		_detail("Anschlussleistung: %.1f kW", [kw]),
		_detail("Grundpreis $%.0f + $%.0f pro kW", [GRID_FEE_BASE, GRID_FEE_PER_KW]),
	])
	var cooler_count: int = GameState.coolers.size()
	var ups_count: int = GameState.ups_units.size()
	if cooler_count + ups_count > 0:
		var maint_cost := MAINTENANCE_PER_COOLER * float(cooler_count) + MAINTENANCE_PER_UPS * float(ups_count)
		_issue_bill("maintenance", maint_cost, day, [
			_detail("Leistungszeitraum: Tag %d bis %d", [day, last_day]),
			_detail("%d Klimageräte à $%.0f", [cooler_count, MAINTENANCE_PER_COOLER]),
			_detail("%d USV-Anlagen à $%.0f", [ups_count, MAINTENANCE_PER_UPS]),
		])
	if rack_count > 0:
		_issue_bill("license", LICENSE_PER_RACK * float(rack_count), day, [
			_detail("Lizenzzeitraum: Tag %d bis %d", [day, last_day]),
			_detail("Betriebssystem- und Management-Lizenzen"),
			_detail("%d Racks à $%.0f", [rack_count, LICENSE_PER_RACK]),
		])


func _issue_bill(kind: String, amount: float, day: int, details: Array) -> void:
	# GAME-10: Kosten je nach Schwierigkeit, in der Sandbox gar keine Rechnungen.
	amount *= GameState.diff("costs")
	if amount <= 0.0:
		return
	var k: Dictionary = BILL_KINDS[kind]
	var bid := "RE-%d" % _next_bill_num
	_next_bill_num += 1
	bills[bid] = {
		"id": bid,
		"kind": kind,
		"vendor": str(k["vendor"]),
		"title": str(k["title"]),
		"icon": str(k["icon"]),
		"amount": amount,
		"base_amount": amount,
		"issued_day": day,
		"due_day": day + int(k["due_days"]),
		"dunning": 0,
		"details": details.duplicate(true),
	}
	GameState.post_event_f("Neue Rechnung %s von %s: %s, fällig an Tag %d.", [
		bid, str(k["vendor"]), format_money(amount), day + int(k["due_days"])
	], "info")
	MailManager.on_bill(bills[bid])


func _process_dunning(day: int) -> void:
	for bid in bills.keys():
		var b: Dictionary = bills[bid]
		if day <= int(b["due_day"]):
			continue
		var lvl := int(b["dunning"])
		if lvl >= MAX_DUNNING_LEVEL and BLOCK_KINDS.has(str(b["kind"])):
			if not bool(b.get("blocked", false)):
				b["blocked"] = true
				_change_score(-25)
				GameState.post_event_f("Sperre! Rechnung %s von %s ist nicht bezahlt. %s", [
					str(bid), str(b["vendor"]), {"text": str(BLOCK_TEXT[str(b["kind"])]), "args": []}
				], "alert")
				MailManager.on_blocked(b)
			continue
		if lvl >= MAX_DUNNING_LEVEL:
			var cost := ceilf(float(b["amount"]) * (1.0 + COLLECTION_FEE_PCT))
			_debit(cost, "Inkasso %s %s", day, [str(bid), str(b["vendor"])])
			bills.erase(bid)
			_change_score(-40)
			GameState.post_event_f("Inkasso! Rechnung %s wurde mit %s Aufschlag eingezogen: %s.", [
				str(bid), "%d%%" % int(COLLECTION_FEE_PCT * 100.0), format_money(cost)
			], "warn")
			continue
		var fee := ceilf(float(DUNNING_FEE_FLAT) + float(b["base_amount"]) * DUNNING_FEE_PCT)
		lvl += 1
		b["dunning"] = lvl
		b["amount"] = float(b["amount"]) + fee
		b["due_day"] = day + DUNNING_GRACE_DAYS
		var details: Array = b["details"]
		details.append(_detail("Mahngebühr Stufe %d: %s", [lvl, format_money(fee)]))
		_change_score(-15)
		GameState.post_event_f("%d. Mahnung für %s (%s): jetzt %s, neue Frist Tag %d.", [
			lvl, str(bid), str(b["vendor"]), format_money(float(b["amount"])), int(b["due_day"])
		], "warn")
		MailManager.on_dunning(b)


func _settle_bill(b: Dictionary, paid_by: String, paid_by_args: Array = []) -> void:
	var bid := str(b["id"])
	var day: int = GameState.day_number
	_debit(float(b["amount"]), "Rechnung %s %s", day, [bid, str(b["vendor"])])
	var rec: Dictionary = b.duplicate(true)
	rec["paid_day"] = day
	rec["paid_by"] = paid_by
	rec["paid_by_args"] = paid_by_args.duplicate()
	paid_bills.push_front(rec)
	while paid_bills.size() > PAID_HISTORY_MAX:
		paid_bills.pop_back()
	bills.erase(bid)
	if bool(b.get("blocked", false)) and not is_blocked(str(b["kind"])):
		GameState.post_event_f("Sperre aufgehoben: %s ist bezahlt.", [str(b["title"])], "good")
	if int(b["dunning"]) == 0:
		_change_score(2)


# ---------------------------------------------------------------- Host-Logik: Mitarbeiter

func _tick_employees(delta: float) -> void:
	for eid in employees.keys():
		var e: Dictionary = employees[eid]
		if str(e["role"]) != "support":
			continue
		var interval := maxf(SUPPORT_MIN_INTERVAL, SUPPORT_BASE_INTERVAL - SUPPORT_SKILL_STEP * float(int(e["skill"])))
		var acc := float(_work_accum.get(eid, 0.0)) + delta
		if acc >= interval:
			var job := _find_support_job()
			if job.is_empty():
				acc = interval
			else:
				acc = 0.0
				GameState.request_reply_ticket(str(job["id"]), str(job["action"]))
				e["work_done"] = int(e["work_done"]) + 1
		_work_accum[eid] = acc

	_accounting_accum += delta
	if _accounting_accum >= ACCOUNTING_CHECK_INTERVAL:
		_accounting_accum = 0.0
		_accountant_pay()


## Nächste Aufgabe für einen Support-Agenten als {id, action}, leer wenn nichts zu tun ist.
## Zuerst werden Tickets mit bereits behobenem Problem geschlossen, danach das
## unbeantwortete Ticket mit der kürzesten Restfrist beantwortet.
func _find_support_job() -> Dictionary:
	var best_id := ""
	var best_remaining := INF
	for tid in GameState.support_tickets.keys():
		var t: Dictionary = GameState.support_tickets[tid]
		if GameState.is_ticket_issue_fixed(t):
			return {"id": str(tid), "action": "resolve"}
		if bool(t.get("reassured", false)):
			continue
		var remaining := GameState.get_ticket_sla_remaining(t)
		if remaining < best_remaining:
			best_remaining = remaining
			best_id = str(tid)
	if best_id.is_empty():
		return {}
	return {"id": best_id, "action": "reassure"}


func _accountant_pay() -> void:
	var acc := get_accountant()
	if acc.is_empty() or bills.is_empty():
		return
	var day: int = GameState.day_number
	var lookahead := 1 if int(acc["skill"]) >= 3 else 0
	var acc_name := str(acc["name"])
	var paid := 0
	for b_v in get_open_bills():
		var b: Dictionary = b_v
		if int(b["due_day"]) <= day + lookahead and GameState.money >= float(b["amount"]):
			_settle_bill(b, "Buchhaltung (%s)", [acc_name])
			paid += 1
	if paid > 0:
		acc["work_done"] = int(acc["work_done"]) + paid
		GameState.post_event_f("Buchhaltung (%s) hat %d Rechnung(en) bezahlt.", [acc_name, paid], "info")
		_broadcast()


# ---------------------------------------------------------------- Hilfsfunktionen

func _find_offer(offer_id: String) -> Dictionary:
	for o in LOAN_OFFERS:
		var offer: Dictionary = o
		if str(offer["id"]) == offer_id:
			return offer
	return {}


func _debit(amount: float, text: String, day: int, args: Array = []) -> void:
	if amount <= 0.0:
		return
	GameState.money -= amount
	_add_statement(day, text, -amount, args)
	book(_cat_for(text), -amount)


## Kategorie einer Buchung aus ihrem Text (alles andere ist „Einkäufe & Sonstiges“).
func _cat_for(text: String) -> String:
	if text.begins_with("Löhne") or text.begins_with("Startprämie") or text.begins_with("Abfindung"):
		return "wages"
	if text.begins_with("Kreditrate") or text.begins_with("Sondertilgung"):
		return "loans"
	if text.begins_with("Rechnung") or text.begins_with("Inkasso"):
		return "bills"
	return "other"


## Nur Host: Betrag ins Kassenbuch des laufenden Tags (Einnahmen positiv, Ausgaben negativ).
func book(cat: String, amount: float) -> void:
	if absf(amount) < 0.005:
		return
	var key := str(GameState.day_number)
	if not ledger.has(key):
		ledger[key] = {}
	var row: Dictionary = ledger[key]
	row[cat] = float(row.get(cat, 0.0)) + amount


## Tagesabschluss: Was sich am Kontostand des Vortags sonst noch getan hat, wird „Einkäufe & Sonstiges“.
func _close_ledger_day(day: int) -> void:
	var prev := str(day - 1)
	if _day_money.has(prev):
		var booked := 0.0
		for v in (ledger.get(prev, {}) as Dictionary).values():
			booked += float(v)
		var rest := GameState.money - float(_day_money[prev]) - booked
		if absf(rest) >= 0.5:
			if not ledger.has(prev):
				ledger[prev] = {}
			ledger[prev]["other"] = float((ledger[prev] as Dictionary).get("other", 0.0)) + rest
	_day_money[str(day)] = GameState.money
	for k in ledger.keys():
		if int(k) < day - LEDGER_DAYS:
			ledger.erase(k)
	for k in _day_money.keys():
		if int(k) < day - 2:
			_day_money.erase(k)


func month_of(day: int) -> int:
	return (maxi(day, 1) - 1) / MONTH_DAYS + 1


## Bilanz eines Monats: {"from", "to", "cats": {Kategorie: Summe}, "income", "expense", "net"}.
func month_summary(month: int) -> Dictionary:
	var from := (month - 1) * MONTH_DAYS + 1
	var to := month * MONTH_DAYS
	var cats := {}
	var income := 0.0
	var expense := 0.0
	for k in ledger.keys():
		var d := int(k)
		if d < from or d > to:
			continue
		for cat in (ledger[k] as Dictionary).keys():
			var v := float(ledger[k][cat])
			cats[cat] = float(cats.get(cat, 0.0)) + v
			if v >= 0.0:
				income += v
			else:
				expense -= v
	return {"from": from, "to": to, "cats": cats, "income": income, "expense": expense, "net": income - expense}


## Ergebnis je Tag der letzten n Tage (ältester zuerst).
func daily_net(n: int) -> Array:
	var out: Array = []
	for i in range(n - 1, -1, -1):
		var d := GameState.day_number - i
		var s := 0.0
		for v in (ledger.get(str(d), {}) as Dictionary).values():
			s += float(v)
		out.append([d, s])
	return out


# ---------------------------------------------------------------- Investoren

func investor_share_total() -> float:
	var s := 0.0
	for inv in investors.values():
		s += float(inv["share"])
	return minf(s, 0.5)


## Nur Host, aus dem Zahlungstakt: Anteil der Investoren an diesen Einnahmen. Gibt den Betrag zurück.
func investor_cut(revenue: float) -> float:
	if revenue <= 0.0 or investors.is_empty():
		return 0.0
	var cut := 0.0
	for id in investors.keys():
		var inv: Dictionary = investors[id]
		var part := revenue * float(inv["share"])
		inv["paid"] = float(inv.get("paid", 0.0)) + part
		cut += part
	return minf(cut, revenue * 0.5)


func get_investor_block_reason(offer: Dictionary) -> String:
	for inv in investors.values():
		if str(inv["offer"]) == str(offer["id"]):
			return "Läuft schon."
	if investors.size() >= MAX_INVESTORS:
		return "Höchstens %d Investoren gleichzeitig." % MAX_INVESTORS
	if GameState.get_company_level() < int(offer["min_level"]):
		return "Ab Firmenstufe %d." % int(offer["min_level"])
	return ""


func get_buyout_cost(inv: Dictionary) -> int:
	return int(roundf(float(inv["amount"]) * BUYOUT_FACTOR * float(inv["days_left"]) / maxf(1.0, float(inv["days_total"]))))


func request_accept_investor(offer_id: String) -> void:
	if _is_host():
		_do_accept_investor(offer_id, _me())
	else:
		_rpc_req_accept_investor.rpc_id(1, offer_id)


func request_buyout_investor(inv_id: String) -> void:
	if _is_host():
		_do_buyout_investor(inv_id, _me())
	else:
		_rpc_req_buyout_investor.rpc_id(1, inv_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_accept_investor(offer_id: String) -> void:
	if multiplayer.is_server():
		_do_accept_investor(offer_id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_buyout_investor(inv_id: String) -> void:
	if multiplayer.is_server():
		_do_buyout_investor(inv_id, multiplayer.get_remote_sender_id())


func _do_accept_investor(offer_id: String, peer: int) -> void:
	if GameState._deny_build(peer, "business"):
		return
	var offer: Dictionary = {}
	for o in INVESTOR_OFFERS:
		if str(o["id"]) == offer_id:
			offer = o
	if offer.is_empty():
		return
	var why := get_investor_block_reason(offer)
	if why != "":
		_feedback(peer, false, why)
		return
	var id := "I-%s-%d" % [offer_id, GameState.day_number]
	investors[id] = {
		"id": id, "offer": offer_id, "title": str(offer["title"]), "amount": float(offer["amount"]), "share": float(offer["share"]),
		"days_left": int(offer["days"]), "days_total": int(offer["days"]), "paid": 0.0, "day": GameState.day_number,
	}
	GameState.money += float(offer["amount"])
	_add_statement(GameState.day_number, "Einlage %s", float(offer["amount"]), [str(offer["title"])])
	book("invest_in", float(offer["amount"]))
	GameState.post_event_f("💼 %s holt %s an Bord: %s gegen %d %% der Einnahmen für %d Tage.", [
		NetworkManager.get_player_name(peer), str(offer["title"]), format_money(float(offer["amount"])), int(float(offer["share"]) * 100.0), int(offer["days"])], "info")
	_feedback(peer, true, "%s eingezahlt: +%s", [str(offer["title"]), format_money(float(offer["amount"]))])
	GameState._broadcast_sim_tick()
	_broadcast()


func _do_buyout_investor(inv_id: String, peer: int) -> void:
	if GameState._deny_build(peer, "business") or not investors.has(inv_id):
		return
	var inv: Dictionary = investors[inv_id]
	var cost := float(get_buyout_cost(inv))
	if GameState.money < cost:
		_feedback(peer, false, "Für den Rückkauf fehlen %s.", [format_money(cost - GameState.money)])
		return
	GameState.money -= cost
	_add_statement(GameState.day_number, "Rückkauf %s", -cost, [str(inv["title"])])
	book("investors", -cost)
	investors.erase(inv_id)
	GameState.post_event_f("💼 %s hat die Anteile von %s zurückgekauft (%s).", [NetworkManager.get_player_name(peer), str(inv["title"]), format_money(cost)], "info")
	_feedback(peer, true, "Anteile zurückgekauft.")
	GameState._broadcast_sim_tick()
	_broadcast()


func _tick_investors(_day: int) -> void:
	for id in investors.keys():
		var inv: Dictionary = investors[id]
		inv["days_left"] = int(inv["days_left"]) - 1
		if int(inv["days_left"]) <= 0:
			investors.erase(id)
			GameState.post_event_f("💼 Die Beteiligung von %s ist ausgelaufen. Ausgezahlt wurden %s.", [str(inv["title"]), format_money(float(inv.get("paid", 0.0)))], "good")


func _add_statement(day: int, text: String, amount: float, args: Array = []) -> void:
	statement.push_front({"day": day, "text": text, "args": args.duplicate(), "amount": amount, "balance": GameState.money})
	while statement.size() > STATEMENT_MAX:
		statement.pop_back()


func _change_score(delta_pts: int) -> void:
	credit_score = clampi(credit_score + delta_pts, SCORE_MIN, SCORE_MAX)