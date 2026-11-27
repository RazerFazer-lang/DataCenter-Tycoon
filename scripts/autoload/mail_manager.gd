extends Node
## Gemeinsames E-Mail-Postfach der Firma. Der Host legt Mails an und führt Aktionen aus,
## alle Spieler sehen dasselbe Postfach. Texte werden als Vorlage mit Werten gespeichert
## und erst beim Anzeigen übersetzt: {"text": "...", "args": [...]}.

signal mails_changed
signal mail_added(mail: Dictionary)
signal action_result(ok: bool, message: String)

const MAX_MAILS := 90
const TICKET_MAIL_GAP := 150.0
const PRAISE_SAT := 96.0
const REPORT_REWARD := 25
## Ab dieser Erfahrung prüft die Buchhaltung Absender.
const SUSPICION_SKILL := 3

const CATS := {
	"bill": {"name": "Rechnungen", "icon": "invoice"},
	"customer": {"name": "Kunden", "icon": "people"},
	"contract": {"name": "Verträge", "icon": "chart"},
	"order": {"name": "Bestellungen", "icon": "cart"},
	"bank": {"name": "Bank", "icon": "bank"},
	"city": {"name": "Stadtwerke", "icon": "power"},
	"rival": {"name": "Konkurrenz", "icon": "tower"},
	"job": {"name": "Bewerbungen", "icon": "headset"},
	"spam": {"name": "Werbung", "icon": "info"},
	"system": {"name": "Verion", "icon": "verion"},
}

const BILL_ADDR := {
	"power": "rechnung@stadtwerke-energie.vrn", "grid_fee": "netz@stadtwerke-netz.vrn", "rent": "buero@immobilien-kraemer.vrn",
	"internet": "business@netlink.vrn", "insurance": "service@hanse-gewerbe.vrn", "maintenance": "service@kaeltetec.vrn",
	"license": "lizenzen@nordlicht-software.vrn",
}

## Betrugsmails. Man erkennt sie am Absender, an Fehlern und am Druck.
const PHISHING := [
	{"from": "Stadtwerke Energie GmbH", "addr": "rechnung@stadtwerke-energie.zahlung-sofort.vrn", "subject": "LETZTE MAHNUNG!! Strom wird heute abgeschalten",
		"body": ["Sehr geerter Kunde,", "ihre Rechnung wurde leider nicht bezahlt. Wenn Sie nicht in 2 Stunden bezahlen, schalten wir den Strom ab.", "Bitte benutzen Sie nur den Knopf unten. Nicht anrufen!"], "act": "Sofort bezahlen ($%d)", "min": 120, "max": 320},
	{"from": "Hanse Direktbank", "addr": "sicherheit@hanse-direktbank.konto-pruefung.vrn", "subject": "Ihr Konto wurde eingeschrenkt",
		"body": ["Lieber Kunde,", "wir haben verdächtige Aktivitäten festgestelt. Bestätigen Sie ihr Konto mit einer kleinen Test-Überweisung.", "Sonst wird ihr gesamtes Guthaben gelöscht."], "act": "Konto bestätigen ($%d)", "min": 90, "max": 260},
	{"from": "NetLink Business", "addr": "business@netl1nk.vrn", "subject": "Rechnung RE-0001 Internet Premium Plus",
		"body": ["Guten Tag,", "anbei die Rechnung für das bestellte Paket Premium Plus. Der Betrag ist sofort fällig.", "Ihr NetLink Team"], "act": "Jetzt bezahlen ($%d)", "min": 60, "max": 180},
	{"from": "CloudParts.de Gewinnspiel", "addr": "gewinn@cloudparts-gewinner.vrn", "subject": "Glückwunsch!!! Sie haben 4 Server gewonen",
		"body": ["Hallo Gewinner!", "Sie sind unser 1.000.000ster Besucher. Für den Versand der 4 Server brauchen wir nur eine kleine Gebühr."], "act": "Versandgebühr zahlen ($%d)", "min": 49, "max": 99},
	{"from": "Helios Dynamics Einkauf", "addr": "einkauf@helios-dynamics.freemail.vrn", "subject": "Dringend: Großauftrag, Kaution nötig",
		"body": ["Sehr geehrte Damen und Herren,", "wir möchten ihr gesamtes Rechenzentrum mieten, für immer. Wegen unserer Regeln müssen Sie zuerst eine Kaution überweisen.", "Antworten Sie schnell, sonst geht der Auftrag an andere."], "act": "Kaution überweisen ($%d)", "min": 200, "max": 450},
	{"from": "Hanse Gewerbeversicherung AG", "addr": "service@hanse-gewerbe-ag.vrn", "subject": "Beitragsrückstand: Schutz erlischt in 60 Minuten",
		"body": ["Wertes Mitglied,", "ihr Beitrag ist nicht eingegangen. Bezahlen Sie den offenen Betrag bevor der Schutz erlischt.", "Diese Nachricht wurde automatisch erstelt."], "act": "Beitrag zahlen ($%d)", "min": 80, "max": 240},
]

const SPAM := [
	{"from": "Kabelkönig", "addr": "news@kabelkoenig.vrn", "subject": "Kabel, Kabel, KABEL! Nur heute", "body": ["Hallo Freund des guten Kabels,", "9 Meter zum Preis von 10! Wer da nicht zugreift, ist selber schuld."]},
	{"from": "Büroglück", "addr": "angebot@bueroglueck.vrn", "subject": "Ihr Rücken wird es Ihnen danken", "body": ["Der Stuhl, der mitdenkt: jetzt mit 37 Verstellhebeln.", "Abmelden ist leider nicht möglich."]},
	{"from": "Horoskop für Admins", "addr": "sterne@admin-horoskop.vrn", "subject": "Merkur ist rückläufig, Ihr Router auch", "body": ["Diese Woche: Meiden Sie Updates am Freitag.", "Ihre Glückszahl: 127.0.0.1"]},
	{"from": "Kantine Nebenan", "addr": "hunger@kantine-nebenan.vrn", "subject": "Heute: Schnitzel mit allem", "body": ["Nur 400 Meter von Ihrem Tor entfernt.", "Wer drei isst, bekommt einen Kaffee."]},
]

var mails: Array = []
var _next_num := 1
var _ticket_gap: Dictionary = {}
var _last_day := -1
var _was_active := false
var _clock := 0.0


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
	if not multiplayer.is_server() or GameState.is_world_paused_for_empty_server():
		return
	_clock += delta
	var today: int = GameState.day_number
	if _last_day < 0:
		_last_day = today
		if mails.is_empty():
			_welcome()
	while _last_day < today:
		_last_day += 1
		run_day(_last_day)


func reset() -> void:
	mails.clear()
	_ticket_gap.clear()
	_next_num = 1
	_last_day = -1
	_clock = 0.0
	mails_changed.emit()


func export_data() -> Dictionary:
	return {"mails": mails.duplicate(true), "next_num": _next_num, "last_day": _last_day}


func import_data(d: Dictionary) -> void:
	mails.clear()
	var arr: Variant = d.get("mails", [])
	if arr is Array:
		for m in arr:
			if m is Dictionary and (m as Dictionary).has("id"):
				mails.append((m as Dictionary).duplicate(true))
	_next_num = maxi(1, int(d.get("next_num", 1)))
	_last_day = int(d.get("last_day", -1))
	if _last_day >= 0 and GameState.is_active:
		_last_day = mini(_last_day, GameState.day_number)
	_ticket_gap.clear()
	mails_changed.emit()


# ---------------------------------------------------------------- Netzwerk

func _online() -> bool:
	return NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and NetworkManager.is_in_session:
		_rpc_sync.rpc_id(peer_id, export_data())


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(d: Dictionary) -> void:
	import_data(d)


@rpc("authority", "call_remote", "reliable")
func _rpc_add(m: Dictionary) -> void:
	mails.push_front(m)
	mails_changed.emit()
	mail_added.emit(m)


@rpc("authority", "call_remote", "reliable")
func _rpc_patch(id: String, patch: Dictionary) -> void:
	var m := find(id)
	if not m.is_empty():
		m.merge(patch, true)
		mails_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_remove(ids: Array) -> void:
	_drop(ids)


@rpc("authority", "call_remote", "reliable")
func _rpc_feedback(ok: bool, message: String, args: Array) -> void:
	action_result.emit(ok, GameState.format_message(message, args))


func _feedback(peer: int, ok: bool, message: String, args: Array = []) -> void:
	if peer == multiplayer.get_unique_id():
		action_result.emit(ok, GameState.format_message(message, args))
	elif peer > 0:
		_rpc_feedback.rpc_id(peer, ok, message, args)


func _drop(ids: Array) -> void:
	for i in range(mails.size() - 1, -1, -1):
		if ids.has(str(mails[i]["id"])):
			mails.remove_at(i)
	mails_changed.emit()


func _patch(id: String, patch: Dictionary) -> void:
	var m := find(id)
	if m.is_empty():
		return
	m.merge(patch, true)
	mails_changed.emit()
	if _online():
		_rpc_patch.rpc(id, patch)


func _remove(ids: Array) -> void:
	_drop(ids)
	if _online():
		_rpc_remove.rpc(ids)


# ---------------------------------------------------------------- Abfragen

func find(id: String) -> Dictionary:
	for m in mails:
		if str((m as Dictionary)["id"]) == id:
			return m
	return {}


func get_unread_count() -> int:
	var n := 0
	for m in mails:
		if not bool((m as Dictionary).get("read", false)):
			n += 1
	return n


func text_of(v: Variant) -> String:
	if v is Dictionary:
		return GameState.format_message(str((v as Dictionary).get("text", "")), (v as Dictionary).get("args", []))
	return tr(str(v))


## Warnhinweis der Buchhaltung bei verdächtigen Mails.
func is_flagged(m: Dictionary) -> bool:
	if not bool(m.get("phish", false)):
		return false
	var acc: Dictionary = FinanceManager.get_accountant()
	return not acc.is_empty() and int(acc.get("skill", 0)) >= SUSPICION_SKILL


## Stand einer Mail als Text, leer = noch offen.
func status_of(m: Dictionary) -> String:
	var done := str(m.get("done", ""))
	if done != "":
		return done
	var ref := str(m.get("ref", ""))
	match str(m.get("kind", "")):
		"bill":
			if not FinanceManager.bills.has(ref):
				return "Bezahlt"
		"contract", "contract_bid":
			if not GameState.contracts.has(ref):
				return "Nicht mehr verfügbar"
			var c: Dictionary = GameState.contracts[ref]
			if bool(c.get("active", false)):
				return "Angenommen"
			if MarketManager.is_contract_taken(c):
				return "Nicht mehr verfügbar"
		"ticket":
			if not GameState.support_tickets.has(ref):
				return "Erledigt"
		"lead":
			if not MarketManager.leads.has(ref):
				return "Nicht mehr verfügbar"
		"poach":
			if MarketManager.poach.is_empty() or str(MarketManager.poach.get("rack_id", "")) + "/" + str(MarketManager.poach.get("service", "")) != ref:
				return "Erledigt"
		"job":
			if FinanceManager.hired_pool.has(int(m.get("pool_idx", -1))):
				return "Eingestellt"
	return ""


## Aktionen einer Mail: [{"id", "label": {text, args}, "style"}]. Leer, wenn erledigt.
func actions_of(m: Dictionary) -> Array:
	if status_of(m) != "":
		return []
	var ref := str(m.get("ref", ""))
	match str(m.get("kind", "")):
		"bill":
			var b: Dictionary = FinanceManager.bills[ref]
			return [{"id": "pay", "label": _t("Jetzt bezahlen (%s)", [FinanceManager.format_money(float(b["amount"]))]), "style": "good"}]
		"contract", "contract_bid":
			return [
				{"id": "accept", "label": _t("Vertrag annehmen ($%d / Zyklus)", [MarketManager.contract_payout(GameState.contracts[ref])]), "style": "good"},
				{"id": "open:support", "label": _t("Verträge ansehen"), "style": "plain"},
			]
		"ticket":
			var t: Dictionary = GameState.support_tickets[ref]
			var out: Array = []
			if GameState.is_ticket_issue_fixed(t):
				out.append({"id": "resolve", "label": _t("Als gelöst melden"), "style": "good"})
			if not bool(t.get("reassured", false)):
				out.append({"id": "reassure", "label": _t("Freundlich antworten"), "style": "accent"})
			if not bool(t.get("compensated", false)):
				out.append({"id": "compensate", "label": _t("Gutschrift geben ($60)"), "style": "plain"})
			return out
		"lead":
			var l: Dictionary = MarketManager.leads[ref]
			return [{"id": "offer", "label": _t("Angebot machen ($%d, Chance %d %%)", [int(l["cost"]), int(MarketManager.lead_chance(l) * 100.0)]), "style": "good"}]
		"poach":
			return [{"id": "counter", "label": _t("Treuerabatt geben ($%d)", [int(MarketManager.poach.get("cost", 0))]), "style": "good"}]
		"job":
			return [
				{"id": "hire", "label": _t("Einstellen"), "style": "good"},
				{"id": "decline", "label": _t("Absagen"), "style": "plain"},
			]
		"praise":
			return [{"id": "thank", "label": _t("Bedanken"), "style": "accent"}]
		"phish":
			return [{"id": "fake", "label": _t(str(m.get("fake_label", "Jetzt bezahlen ($%d)")), [int(m.get("amount", 0))]), "style": "good"}]
		"loan":
			return [{"id": "open:bank", "label": _t("Zur Bank"), "style": "accent"}]
	return []


func _t(text: String, args: Array = []) -> Dictionary:
	return {"text": text, "args": args}


# ---------------------------------------------------------------- Mails anlegen (nur Host)

func post(cat: String, from: String, addr: String, subject: Dictionary, body: Array, extra: Dictionary = {}) -> void:
	if not multiplayer.is_server() or not GameState.is_active:
		return
	var m := {
		"id": "M%d" % _next_num, "cat": cat, "from": from, "addr": addr, "subject": subject, "body": body,
		"day": GameState.day_number, "tod": GameState.time_of_day, "read": false,
	}
	_next_num += 1
	m.merge(extra, true)
	mails.push_front(m)
	mails_changed.emit()
	mail_added.emit(m)
	if _online():
		_rpc_add.rpc(m)
	_prune()


func _prune() -> void:
	if mails.size() <= MAX_MAILS:
		return
	var ids: Array = []
	# Zuerst alte, gelesene und erledigte Mails, dann die ältesten überhaupt.
	for pass_n in 2:
		for i in range(mails.size() - 1, -1, -1):
			if mails.size() - ids.size() <= MAX_MAILS:
				break
			var m: Dictionary = mails[i]
			if ids.has(str(m["id"])):
				continue
			if pass_n == 0 and (not bool(m.get("read", false)) or not actions_of(m).is_empty()):
				continue
			ids.append(str(m["id"]))
	_remove(ids)


func _welcome() -> void:
	post("system", "Verion OS", "hallo@verion.vrn", _t("Willkommen bei Verion Mail"), [
		_t("Hallo %s,", [GameState.current_save_name]),
		_t("hier kommen Rechnungen, Kundenpost, Verträge und Bestellungen an. Vieles erledigst du direkt in der Mail."),
		_t("Vorsicht: Betrüger schreiben auch. Prüfe immer die Absender-Adresse, bevor du bezahlst. Verdächtige Mails meldest du mit einem Klick."),
	])


func on_bill(b: Dictionary) -> void:
	var lines: Array = [_t("Sehr geehrte Damen und Herren,"), _t("für %s berechnen wir Ihnen %s.", [str(b["title"]), FinanceManager.format_money(float(b["amount"]))])]
	for d in b.get("details", []):
		if d is Dictionary:
			lines.append(d)
	lines.append(_t("Bitte zahlen Sie bis Tag %d.", [int(b["due_day"])]))
	post("bill", str(b["vendor"]), str(BILL_ADDR.get(str(b["kind"]), "rechnung@verion.vrn")), _t("Rechnung %s: %s", [str(b["id"]), str(b["title"])]), lines, {"kind": "bill", "ref": str(b["id"])})


func on_dunning(b: Dictionary) -> void:
	var lvl := int(b["dunning"])
	var lines: Array = [
		_t("Sehr geehrte Damen und Herren,"),
		_t("die Rechnung %s ist noch offen. Mit Mahngebühr sind es jetzt %s.", [str(b["id"]), FinanceManager.format_money(float(b["amount"]))]),
		_t("Neue Frist: Tag %d.", [int(b["due_day"])]),
	]
	if lvl >= FinanceManager.MAX_DUNNING_LEVEL:
		lines.append(_t(str(FinanceManager.BLOCK_WARNING.get(str(b["kind"]), "Danach übergeben wir den Fall an ein Inkassobüro."))))
	post("bill", str(b["vendor"]), str(BILL_ADDR.get(str(b["kind"]), "rechnung@verion.vrn")), _t("%d. Mahnung zu Rechnung %s", [lvl, str(b["id"])]), lines, {"kind": "bill", "ref": str(b["id"]), "urgent": true})


func on_blocked(b: Dictionary) -> void:
	post("bill", str(b["vendor"]), str(BILL_ADDR.get(str(b["kind"]), "rechnung@verion.vrn")), _t("Sperre: Rechnung %s ist nicht bezahlt", [str(b["id"])]), [
		_t("Sehr geehrte Damen und Herren,"),
		_t(str(FinanceManager.BLOCK_TEXT.get(str(b["kind"]), "Die Leistung ist gesperrt."))),
		_t("Sobald %s bezahlt sind, heben wir die Sperre sofort auf.", [FinanceManager.format_money(float(b["amount"]))]),
	], {"kind": "bill", "ref": str(b["id"]), "urgent": true})


func on_new_contract(c: Dictionary) -> void:
	post("contract", str(c["client"]), _client_addr(str(c["client"])), _t("Angebot: %s", [str(c["title"])]), [
		_t("Guten Tag,"),
		_t("wir suchen einen Anbieter für '%s'.", [str(c["title"])]),
		_t("Bedarf: %d GB RAM und %.1f Mbit/s.", [int(c.get("req_ram_gb", 4)), float(c.get("req_mbps", 15.0))]),
		_t("Vergütung: $%d je Zyklus, Strafe bei Ausfall: $%d. Laufzeit: %d Tage.", [int(c["payout_per_cycle"]), int(c["penalty_per_cycle"]), int(c.get("duration_days", 1))]),
	], {"kind": "contract", "ref": str(c["id"])})


func on_contract_bid(c: Dictionary, rid: String) -> void:
	post("contract", str(c["client"]), _client_addr(str(c["client"])), _t("Gegenangebot zu '%s'", [str(c["title"])]), [
		_t("Guten Tag,"),
		_t("%s hat uns ein günstigeres Angebot gemacht. Wir entscheiden in den nächsten Minuten.", [MarketManager.rival_name(rid)]),
		_t("Wenn Sie %d %% nachlassen, bleiben wir bei Ihnen: $%d je Zyklus.", [int(MarketManager.BID_PAYOUT_CUT * 100.0), MarketManager.contract_payout(c)]),
	], {"kind": "contract_bid", "ref": str(c["id"]), "urgent": true})


func on_contract_lost(c: Dictionary, rid: String, was_ours: bool) -> void:
	var text := "der Vertrag '%s' war zu lange nicht erfüllt. Wir wechseln zu %s." if was_ours else "den Auftrag '%s' haben wir an %s vergeben."
	post("contract", str(c["client"]), _client_addr(str(c["client"])), _t("Absage zu '%s'", [str(c["title"])]), [_t("Guten Tag,"), _t(text, [str(c["title"]), MarketManager.rival_name(rid)])])


func on_lead(l: Dictionary) -> void:
	post("customer", str(l["customer"]), _client_addr(str(l["customer"])), _t("Wir sind unzufrieden mit %s", [MarketManager.rival_name(str(l["rival"]))]), [
		_t("Guten Tag,"),
		_t("bei %s läuft es gerade nicht rund. Wir überlegen, mit %d Nutzern (%s) zu wechseln.", [MarketManager.rival_name(str(l["rival"])), int(l["users"]), str(HardwareCatalog.RENTAL_PROFILES[str(l["service"])]["short"])]),
		_t("Eine Wechselprämie von $%d würde uns die Entscheidung leichter machen.", [int(l["cost"])]),
	], {"kind": "lead", "ref": str(l["id"])})


func on_poach(p: Dictionary) -> void:
	post("customer", str(p["customer"]), _client_addr(str(p["customer"])), _t("%s hat uns ein Angebot gemacht", [MarketManager.rival_name(str(p["rival"]))]), [
		_t("Guten Tag,"),
		_t("wir sind mit der Leistung auf %s nicht mehr zufrieden. %s bietet uns bessere Bedingungen.", [GameState.get_rack_display_name(str(p["rack_id"])), MarketManager.rival_name(str(p["rival"]))]),
		_t("Wenn sich nichts ändert, wechseln wir in wenigen Minuten mit einem Teil unserer Nutzer."),
	], {"kind": "poach", "ref": str(p["rack_id"]) + "/" + str(p["service"]), "urgent": true})


func on_ticket(t: Dictionary) -> void:
	var rid := str(t.get("rack_id", ""))
	if _clock - float(_ticket_gap.get(rid, -999.0)) < TICKET_MAIL_GAP:
		return
	_ticket_gap[rid] = _clock
	post("customer", str(t.get("customer", "")), _client_addr(str(t.get("customer", ""))), _t(str(t.get("title", "")), t.get("title_args", [])), [
		_t("Hallo,"), _t(str(t.get("message", "")), t.get("message_args", [])), _t("Ticket: %s", [str(t.get("id", ""))]),
	], {"kind": "ticket", "ref": str(t.get("id", ""))})


func on_cancelled(customer: String, rack_name: String) -> void:
	post("customer", customer, _client_addr(customer), _t("Kündigung"), [
		_t("Guten Tag,"), _t("hiermit kündigen wir unseren Vertrag für %s. Die dauernden Ausfälle waren zu viel.", [rack_name]),
	])


func on_order(count: int, goods: float, shipping: float, slot_label: String, express: bool) -> void:
	var lines: Array = [_t("Danke für deine Bestellung!"), _t("%d Artikel, Warenwert $%.0f, Versand $%.0f.", [count, goods, shipping])]
	lines.append(_t("Expresslieferung: Der Wagen ist schon unterwegs.") if express else _t("Geplantes Lieferfenster: %s", [slot_label]))
	post("order", "CloudParts.de", "bestellung@cloudparts.vrn", _t("Bestellbestätigung"), lines)


func on_delivery_done(crates: int, doc: Dictionary = {}, signed_by: String = "") -> void:
	var lines: Array = [
		_t("Guten Tag,"), _t("wir haben deine Lieferung vor dem Tor abgestellt (%d Kisten).", [crates]) if crates > 0 else _t("wir haben dein Paket abgegeben. Die Teile liegen im Lager."),
	]
	if not doc.is_empty():
		if signed_by != "":
			lines.append(_t("Lieferschein %s, unterschrieben von %s.", [str(doc.get("no", "")), signed_by]))
		else:
			lines.append(_t("Lieferschein %s: Niemand hat unterschrieben, die Ware wurde trotzdem abgestellt.", [str(doc.get("no", ""))]))
	post("order", "Cloud Express", "zustellung@cloudexpress.vrn", _t("Deine Lieferung ist da"), lines)


func _client_addr(client: String) -> String:
	var s := client.to_lower()
	for pair in [["ä", "ae"], ["ö", "oe"], ["ü", "ue"], ["ß", "ss"], [" ", "-"], [".", ""], ["&", ""], ["+", ""]]:
		s = s.replace(str(pair[0]), str(pair[1]))
	while s.contains("--"):
		s = s.replace("--", "-")
	return "kontakt@%s.vrn" % s.trim_suffix("-")


func run_day(day: int) -> void:
	_announce_outage()
	if day >= 2 and randf() < 0.35:
		post_phishing(randi() % PHISHING.size())
	if randf() < 0.28:
		var s: Dictionary = SPAM[randi() % SPAM.size()]
		var lines: Array = []
		for l in s["body"]:
			lines.append(_t(str(l)))
		post("spam", str(s["from"]), str(s["addr"]), _t(str(s["subject"])), lines)
	if day % 3 == 0:
		_job_mail()
	if day % 7 == 0:
		post("bank", "Hanse Direktbank", "service@hanse-direktbank.vrn", _t("Dein Wochenbericht"), [
			_t("Guten Tag,"), _t("Kontostand: %s. Bonität: %d.", [FinanceManager.format_money(GameState.money), FinanceManager.credit_score]),
			_t("Offene Kredite: %s.", [FinanceManager.format_money(FinanceManager.get_total_debt())]),
		])
	elif FinanceManager.loans.is_empty() and FinanceManager.credit_score >= 620 and randf() < 0.18:
		post("bank", "Hanse Direktbank", "service@hanse-direktbank.vrn", _t("Ein Angebot für dein Wachstum"), [
			_t("Guten Tag,"), _t("deine Bonität ist gut. Du kannst bis zu %s als Kredit aufnehmen.", [FinanceManager.format_money(FinanceManager.get_free_credit())]),
		], {"kind": "loan"})
	_maybe_praise()
	if GameState.get_company_level() >= 2 and randf() < 0.16:
		_rival_mail()


func _announce_outage() -> void:
	var left: float = GameState.get_next_outage_in()
	if left <= 0.0 or left > float(GameState.DAY_LENGTH_SECONDS) or randf() > 0.55:
		return
	var mins := int(fposmod(GameState.time_of_day + left / float(GameState.DAY_LENGTH_SECONDS), 1.0) * 1440.0)
	post("city", "Stadtwerke Netz GmbH", "netz@stadtwerke-netz.vrn", _t("Arbeiten am Stromnetz"), [
		_t("Sehr geehrte Damen und Herren,"),
		_t("heute gegen %s Uhr arbeiten wir an der Leitung in Ihrer Straße. Der Strom kann kurz ausfallen.", ["%02d:%02d" % [mins / 60, (mins % 60) / 10 * 10]]),
		_t("Bei Gewitter kann es auch früher sein."),
	], {"urgent": true})


func _job_mail() -> void:
	var cands: Array = FinanceManager.get_candidates()
	if cands.is_empty() or FinanceManager.employees.size() >= FinanceManager.MAX_EMPLOYEES:
		return
	var c: Dictionary = cands[randi() % cands.size()]
	for m in mails:
		if str(m.get("kind", "")) == "job" and int(m.get("pool_idx", -1)) == int(c["pool_idx"]) and str(m.get("done", "")) == "":
			return
	post("job", str(c["name"]), _client_addr(str(c["name"])).replace("kontakt@", "post@"), _t("Bewerbung als %s", [FinanceManager.get_role_title(str(c["role"]))]), [
		_t("Guten Tag,"),
		_t("ich würde gern bei Ihnen arbeiten. Meine Erfahrung: %d von 5.", [int(c["skill"])]),
		_t("Gehaltswunsch: %s pro Tag.", [FinanceManager.format_money(float(c["wage"]))]),
	], {"kind": "job", "pool_idx": int(c["pool_idx"])})


func _maybe_praise() -> void:
	if randf() > 0.45:
		return
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		if str(r.get("rental_type", "none")) != "none" and float(r.get("satisfaction", 0.0)) >= PRAISE_SAT and int(r.get("active_users", 0)) >= 8:
			var sv: Array = r.get("services", [])
			var cname := str((sv[0] as Dictionary).get("customer", "")) if not sv.is_empty() else str(r.get("rental_customer", ""))
			post("customer", cname, _client_addr(cname), _t("Danke!"), [
				_t("Hallo,"), _t("%s läuft bei uns ohne jede Störung. Wir empfehlen euch gern weiter.", [GameState.get_rack_display_name(str(rid))]),
			], {"kind": "praise"})
			return


func _rival_mail() -> void:
	var rid: String = MarketManager._random_active_rival()
	var texts := [
		["Nur zur Info", "wir haben gesehen, dass ihr auch Server vermietet. Süß."],
		["Friedensangebot", "ihr lasst uns die großen Kunden, wir lassen euch die Garage. Deal?"],
		["Glückwunsch", "euer Wachstum ist beachtlich. Wir behalten euch im Auge."],
	]
	var t: Array = texts[randi() % texts.size()]
	post("rival", MarketManager.rival_name(rid), _client_addr(MarketManager.rival_name(rid)).replace("kontakt@", "chefetage@"), _t(str(t[0])), [_t("Hallo Nachbarn,"), _t(str(t[1])), _t(str(MarketManager.RIVALS[rid]["motto"]))])


func post_phishing(idx: int) -> void:
	var p: Dictionary = PHISHING[clampi(idx, 0, PHISHING.size() - 1)]
	var amount := int(float(randi_range(int(p["min"]), int(p["max"]))) * (1.0 + 0.35 * float(GameState.get_company_level() - 1)))
	var lines: Array = []
	for l in p["body"]:
		lines.append(_t(str(l)))
	post("bill" if idx == 0 or idx == 2 or idx == 5 else ("bank" if idx == 1 else "customer"), str(p["from"]), str(p["addr"]), _t(str(p["subject"])), lines, {"kind": "phish", "phish": true, "amount": amount, "fake_label": str(p["act"])})


# ---------------------------------------------------------------- Anfragen der Spieler

func request_read(id: String) -> void:
	_rpc_req_read.rpc_id(1, id)


func request_read_all() -> void:
	_rpc_req_read.rpc_id(1, "*")


func request_delete(id: String) -> void:
	_rpc_req_delete.rpc_id(1, id)


func request_report(id: String) -> void:
	_rpc_req_report.rpc_id(1, id)


func request_action(id: String, action: String) -> void:
	_rpc_req_action.rpc_id(1, id, action)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_read(id: String) -> void:
	if not multiplayer.is_server() or not SecurityGuard.check_rate_limit(_sender(), "mail_read", 30, 4.0):
		return
	for m in mails:
		if (id == "*" or str(m["id"]) == id) and not bool(m.get("read", false)):
			_patch(str(m["id"]), {"read": true})


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_delete(id: String) -> void:
	if not multiplayer.is_server() or not SecurityGuard.check_rate_limit(_sender(), "mail_del", 20, 4.0):
		return
	if not find(id).is_empty():
		_remove([id])


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_report(id: String) -> void:
	if not multiplayer.is_server() or not SecurityGuard.check_rate_limit(_sender(), "mail_rep", 10, 4.0):
		return
	var peer := _sender()
	var m := find(id)
	if m.is_empty() or str(m.get("done", "")) != "":
		return
	if bool(m.get("phish", false)):
		GameState.money += float(REPORT_REWARD)
		_patch(id, {"done": "Als Betrug gemeldet", "read": true})
		_feedback(peer, true, "Gut erkannt! Das war Betrug. Verion zahlt dir $%d Prämie.", [REPORT_REWARD])
		GameState._rpc_play_sfx.rpc("cash")
		GameState._broadcast_sim_tick()
	else:
		_feedback(peer, false, "Diese E-Mail ist echt.")


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_action(id: String, action: String) -> void:
	if not multiplayer.is_server() or not SecurityGuard.check_rate_limit(_sender(), "mail_act", 12, 4.0):
		return
	do_action(id, action, _sender())


func do_action(id: String, action: String, peer: int) -> void:
	var m := find(id)
	if m.is_empty():
		return
	var allowed := false
	for a in actions_of(m):
		if str((a as Dictionary)["id"]) == action:
			allowed = true
	if not allowed:
		_feedback(peer, false, "Das geht nicht mehr.")
		return
	var ref := str(m.get("ref", ""))
	match action:
		"pay":
			FinanceManager._do_pay_bill(ref, peer)
		"accept":
			GameState.do_toggle_contract(ref, peer)
		"resolve", "reassure", "compensate":
			GameState.do_reply_ticket(ref, action, peer)
		"offer":
			MarketManager.do_lead(ref, peer)
		"counter":
			MarketManager.do_counter_poach(peer)
		"hire":
			FinanceManager._do_hire(int(m.get("pool_idx", -1)), peer)
		"decline":
			_patch(id, {"done": "Abgesagt"})
		"thank":
			GameState.reputation = minf(100.0, GameState.reputation + 0.6)
			_patch(id, {"done": "Beantwortet"})
			_feedback(peer, true, "Danke geschickt, das freut den Kunden.")
		"fake":
			var loss := minf(maxf(0.0, GameState.money), float(m.get("amount", 0)))
			FinanceManager.debit_public(loss, "Betrug: %s", [str(m["addr"])])
			_patch(id, {"done": "Auf Betrug hereingefallen"})
			GameState.post_event_f("🎣 %s ist auf eine Betrugsmail hereingefallen: -$%d.", [NetworkManager.get_player_name(peer), int(loss)], "alert")
			_feedback(peer, false, "Das war Betrug! Das Geld ist weg.")
			GameState._rpc_play_sfx.rpc("error")
			GameState._broadcast_sim_tick()
	if not bool(m.get("read", false)):
		_patch(id, {"read": true})
	mails_changed.emit()
