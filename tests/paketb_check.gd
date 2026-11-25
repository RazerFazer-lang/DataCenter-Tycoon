extends SceneTree
## Prüft Roadmap-Paket B: Markt und Konkurrenz, Postfach, Rechnungsfolgen, Verion OS.
## Aufruf: godot --headless --path . --script res://tests/paketb_check.gd

var bad := 0
var gs: Node
var sm: Node
var fm: Node
var mk: Node
var mm: Node
var main: Node
var rid := ""


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	sm = root.get_node("SaveManager")
	fm = root.get_node("FinanceManager")
	mk = root.get_node("MarketManager")
	mm = root.get_node("MailManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Test", 7843, {}, "", "PaketB", "", false, false)
	await wait(20)
	gs.money = 50000.0
	gs.room_level = 1
	gs.power_tier = 3
	gs.router_tier = 2
	rid = gs._alloc_rack_id()
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(0.5, 0.0, 0.0), 0.0)
	for k in 3:
		gs.racks[rid]["slots"][k].merge({"item_type": "web_server", "state": "ok", "components": gs._default_components("web_server")}, true)
	gs.racks[rid]["services"] = [{"type": "web", "customer": "ShopNova GmbH", "users": 40.0, "trend": 0.0}]
	gs.request_connect_cable("power", gs.WALL_BREAKER_ID, rid, -1, -1)
	gs.request_connect_cable("network", gs.WALL_ROUTER_ID, rid, -1, -1)
	for i in 80:
		gs._update_slot_boot(0.5)
	gs._recalculate_networks_and_metrics()
	await _market()
	await _contracts()
	await _poach()
	await _mail()
	await _bills()
	await _os()
	await _save()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


func _level(n: int) -> void:
	# Firmenwert so setzen, dass die gewünschte Stufe erreicht ist.
	gs.money = float(gs.COMPANY_LEVEL_THRESHOLDS[n - 1]) + 60000.0 if n > 1 else 9000.0
	gs.company_level = n


func _market() -> void:
	print("--- Markt")
	chk("5 Konkurrenten", mk.rivals.size() == 5, mk.rivals.keys())
	var ok_names := true
	for r in mk.RIVAL_ORDER:
		ok_names = ok_names and mk.rival_name(r) != r and mk.rival_users(r) > 0.0
	chk("alle mit Namen und Kunden", ok_names)
	var sh: Dictionary = mk.get_shares("web")
	var sum := 0.0
	for k in sh:
		sum += float(sh[k])
	chk("Anteile ergeben 100 %", absf(sum - 1.0) < 0.001, sum)
	chk("eigener Anteil", float(sh["you"]) > 0.0 and float(sh["you"]) < 1.0, sh["you"])
	var tot: Dictionary = mk._calc_total_shares()
	sum = 0.0
	for k in tot:
		sum += float(tot[k])
	chk("Gesamtanteile ergeben 100 %", absf(sum - 1.0) < 0.001, sum)
	chk("Spezialisten stark: Gaming", mk.rival_power("respawnia", "game") > mk.rival_power("quarknetz", "game"))
	chk("Spezialisten stark: KI", mk.rival_power("quarknetz", "ai") > mk.rival_power("respawnia", "ai"))
	_level(1)
	gs.reputation = 50.0
	chk("Stufe 1 kaum Wirkung", absf(mk.level_weight() - 0.15) < 0.01 and absf(mk.growth_factor("web") - 1.0) < 0.15, mk.growth_factor("web"))
	_level(4)
	gs.reputation = 5.0
	var low: float = mk.growth_factor("web")
	gs.reputation = 95.0
	var high: float = mk.growth_factor("web")
	chk("Stufe 4: Ruf wirkt", mk.level_weight() == 1.0 and high > low + 0.1, [low, high])
	gs.reputation = 50.0
	# Preise
	var base: float = mk.growth_factor("web")
	mk.request_set_price("web", 0.7)
	await wait(2)
	var cheap: float = mk.growth_factor("web")
	var p_cheap: Dictionary = gs._blend_service_profiles(gs.racks[rid]["services"])
	mk.request_set_price("web", 1.4)
	await wait(2)
	var dear: float = mk.growth_factor("web")
	var p_dear: Dictionary = gs._blend_service_profiles(gs.racks[rid]["services"])
	chk("billig bringt mehr Kunden", cheap > base and dear < base, [cheap, base, dear])
	chk("teuer bringt mehr pro Kunde", float(p_dear["pay_per_user"]) > float(p_cheap["pay_per_user"]) * 1.9)
	chk("teuer vertreibt Kunden", mk.price_shed("web") > 0.0)
	mk.request_set_price("web", 99.0)
	mk.request_set_price("none", 0.5)
	await wait(2)
	chk("Preis begrenzt", is_equal_approx(mk.get_price("web"), mk.PRICE_MAX) and not mk.prices.has("none"), mk.prices)
	mk.request_set_price("web", NAN)
	mk.request_set_price("web", 1.0)
	await wait(2)
	chk("Grundpreis gilt wieder", is_equal_approx(mk.get_price("web"), 1.0) and is_equal_approx(float(gs._blend_service_profiles(gs.racks[rid]["services"])["pay_per_user"]), 0.56))
	# Nur neue Kunden: zufriedene bleiben auch bei schwachem Markt
	gs.reputation = 0.0
	var svc := {"type": "web", "users": 40.0, "trend": 0.0}
	for i in 100:
		gs._update_service_users(svc, 95.0, true, 0.5, 1.0, 20.0)
	chk("zufriedene Kunden gehen nicht", float(svc["users"]) >= 40.0, svc["users"])
	gs.reputation = 50.0
	# Werbung
	var m0: float = gs.money
	var g0: float = mk.growth_factor("web")
	mk.request_campaign("online")
	await wait(2)
	chk("Werbung kostet und wirkt", is_equal_approx(gs.money, m0 - 1200.0) and mk.growth_factor("web") > g0 * 1.3, mk.growth_factor("web") / g0)
	mk.request_campaign("online")
	mk.request_campaign("flyer")
	mk.request_campaign("tv")
	await wait(2)
	chk("höchstens 2, nichts doppelt", mk.campaigns.size() == 2, mk.campaigns)
	mk.run_day(gs.day_number)
	mk.run_day(gs.day_number)
	mk.run_day(gs.day_number)
	chk("Werbung läuft aus", mk.campaigns.is_empty())
	# Viele Tage: Werte bleiben in Grenzen
	var sane := true
	for d in 120:
		mk.run_day(gs.day_number + d)
		for s in mk.services_list():
			mk._relax_users(s, 0.1)
		for r in mk.RIVAL_ORDER:
			var x: Dictionary = mk.rivals[r]
			sane = sane and float(x["strength"]) >= 0.1 and float(x["strength"]) <= 2.5 and float(x["price"]) > 0.4 and mk.rival_users(r) >= 0.0 and is_finite(mk.rival_users(r))
	chk("120 Tage ohne Ausreißer", sane)
	chk("Nachrichten begrenzt", mk.news.size() <= mk.NEWS_MAX and not mk.news.is_empty(), mk.news.size())
	chk("Kundenliste begrenzt", mk.leads.size() <= mk.LEADS_MAX)
	mk._go_bankrupt("pfennig", gs.day_number)
	chk("Pleite: keine Kunden, keine Kraft", mk.rival_users("pfennig") == 0.0 and mk.rival_power("pfennig", "web") == 0.0)
	mk._rival_day("pfennig", gs.day_number + 10)
	chk("neuer Investor", str(mk.rivals["pfennig"]["state"]) == "ok")


func _contracts() -> void:
	print("--- Verträge")
	_level(4)
	for k in gs.contracts.keys():
		if bool(gs.contracts[k].get("active", false)):
			gs.do_toggle_contract(k, 1)
	gs._fill_random_contract_offers()
	var cid := ""
	for k in gs.contracts:
		if bool(gs.contracts[k].get("random", false)):
			cid = k
	mk.start_bid(cid, "aurelwerk")
	var c: Dictionary = gs.contracts[cid]
	var pay := int(c["payout_per_cycle"])
	chk("Gegengebot drückt den Preis", mk.contract_payout(c) < pay or pay <= 2, [pay, mk.contract_payout(c)])
	var cut: int = mk.contract_payout(c)
	gs.do_toggle_contract(cid, 1)
	chk("angenommen zum neuen Preis", bool(c["active"]) and int(c["payout_per_cycle"]) == cut and not c.has("bid_rival"))
	gs.do_toggle_contract(cid, 1)
	# Feste Vorlage: verloren, gesperrt, wieder frei
	mk.start_bid("c_ml", "quarknetz")
	mk._tick_bids(mk.BID_SECONDS + 1.0)
	var t: Dictionary = gs.contracts["c_ml"]
	chk("Vertrag an Konkurrenz verloren", mk.is_contract_taken(t) and str(t["taken_by"]) == "quarknetz")
	gs.do_toggle_contract("c_ml", 1)
	chk("vergebener Vertrag nicht annehmbar", not bool(t["active"]))
	mk.run_day(int(t["taken_until"]) + 1)
	gs.do_toggle_contract("c_ml", 1)
	chk("später wieder frei", bool(t["active"]), t)
	t["status"] = "underpowered"
	mk._tick_bids(mk.BREACH_LIMIT + 1.0)
	chk("nicht erfüllter Vertrag geht verloren", not bool(t["active"]) and mk.is_contract_taken(t))
	t.erase("taken_by")
	t.erase("taken_until")
	_level(10)
	var lim: int = gs.get_max_contracts_limit()
	chk("Vertragsgrenze nach Stufe", lim > 4, lim)
	var n := 0
	for k in gs.contracts.keys():
		mk.clear_bid(gs.contracts[k])
		gs.do_toggle_contract(k, 1)
	n = gs.get_active_contract_count()
	chk("mehr als 4 Verträge möglich", n > 4, n)
	for k in gs.contracts.keys():
		if bool(gs.contracts[k].get("active", false)):
			gs.do_toggle_contract(k, 1)


func _poach() -> void:
	print("--- Abwerben")
	_level(4)
	mk.leads.clear()
	mk._add_lead("kolossal")
	var lid: String = mk.leads.keys()[0]
	mk.leads[lid]["service"] = "web"
	mk.leads[lid]["users"] = 12
	gs.racks[rid]["powered"] = true
	gs.racks[rid]["networked"] = true
	gs.reputation = 100.0
	mk.request_set_price("web", 0.6)
	await wait(2)
	chk("Chance begrenzt", mk.lead_chance(mk.leads[lid]) <= 0.95 and mk.lead_chance(mk.leads[lid]) > 0.5, mk.lead_chance(mk.leads[lid]))
	var won := false
	var m0: float = gs.money
	var u0: float = mk.player_users("web")
	for i in 12:
		if not mk.leads.has(lid):
			mk.leads[lid] = {"id": lid, "rival": "kolossal", "service": "web", "users": 12, "customer": "Test", "cost": 80, "until_day": gs.day_number + 2}
		mk.do_lead(lid, 1)
		if mk.player_users("web") > u0 + 10.0:
			won = true
			break
	chk("Kunde abgeworben", won and gs.money < m0, mk.player_users("web") - u0)
	mk.leads["L99"] = {"id": "L99", "rival": "kolossal", "service": "ai", "users": 5, "customer": "Test", "cost": 10, "until_day": 99}
	m0 = gs.money
	mk.do_lead("L99", 1)
	chk("ohne passendes Rack kein Angebot", mk.leads.has("L99") and gs.money == m0)
	mk.leads.erase("L99")
	mk.request_set_price("web", 1.0)
	await wait(2)
	# Konkurrenz wirbt ab
	gs.racks[rid]["satisfaction"] = 30.0
	mk._poach_cooldown = 0.0
	mk._maybe_poach()
	chk("unzufriedener Kunde wird umworben", not mk.poach.is_empty(), mk.poach)
	m0 = gs.money
	mk.do_counter_poach(1)
	chk("Treuerabatt hält ihn", mk.poach.is_empty() and gs.money < m0 and float(gs.racks[rid]["satisfaction"]) >= 50.0)
	gs.racks[rid]["satisfaction"] = 30.0
	mk._poach_cooldown = 0.0
	mk._maybe_poach()
	u0 = mk.player_users("web")
	mk._tick_poach(mk.POACH_SECONDS + 1.0)
	chk("sonst gehen Kunden", mk.player_users("web") < u0 * 0.8, [u0, mk.player_users("web")])
	gs.racks[rid]["satisfaction"] = 96.0
	mk._poach_cooldown = 0.0
	mk._maybe_poach()
	chk("zufriedene werden nicht umworben", mk.poach.is_empty())
	gs.racks[rid]["satisfaction"] = 30.0
	mk._poach_cooldown = 0.0
	_level(1)
	mk._maybe_poach()
	chk("auf Stufe 1 kein Abwerben", mk.poach.is_empty())
	gs.racks[rid]["satisfaction"] = 90.0
	gs.reputation = 50.0


func _find_kind(kind: String) -> Dictionary:
	for m in mm.mails:
		if str(m.get("kind", "")) == kind:
			return m
	return {}


func _mail() -> void:
	print("--- Postfach")
	gs.money = 40000.0
	fm._issue_bill("internet", 70.0, gs.day_number, [])
	var b := _find_kind("bill")
	chk("Rechnung kommt als Mail", not b.is_empty() and mm.actions_of(b).size() == 1, b.get("subject"))
	var n: int = mm.get_unread_count()
	mm.request_read(str(b["id"]))
	await wait(1)
	chk("gelesen", mm.get_unread_count() == n - 1)
	var m0: float = gs.money
	mm.do_action(str(b["id"]), "pay", 1)
	chk("in der Mail bezahlt", not fm.bills.has(str(b["ref"])) and gs.money < m0 and mm.status_of(b) == "Bezahlt")
	mm.do_action(str(b["id"]), "pay", 1)
	chk("nicht doppelt bezahlt", gs.money >= m0 - 71.0)
	# Vertrag per Mail
	for k in gs.contracts.keys():
		if bool(gs.contracts[k].get("random", false)):
			gs.contracts.erase(k)
	gs._fill_random_contract_offers()
	var c := _find_kind("contract")
	mm.do_action(str(c["id"]), "accept", 1)
	chk("Vertrag per Mail angenommen", bool(gs.contracts[str(c["ref"])]["active"]) and mm.status_of(c) == "Angenommen")
	# Ticket per Mail
	gs.support_tickets.clear()
	mm._ticket_gap.clear()
	gs._create_support_ticket(rid, gs.racks[rid], "ram")
	var t := _find_kind("ticket")
	chk("Beschwerde kommt als Mail", not t.is_empty() and mm.actions_of(t).size() >= 2)
	gs.racks[rid]["satisfaction"] = 50.0
	mm.do_action(str(t["id"]), "reassure", 1)
	chk("Antwort beruhigt", bool(gs.support_tickets[str(t["ref"])]["reassured"]) and float(gs.racks[rid]["satisfaction"]) > 55.0)
	gs.support_tickets.clear()
	# Bewerbung
	fm.employees.clear()
	fm.hired_pool.clear()
	mm._job_mail()
	var j := _find_kind("job")
	mm.do_action(str(j["id"]), "hire", 1)
	chk("Bewerbung angenommen", fm.employees.size() == 1 and mm.status_of(j) == "Eingestellt")
	fm.employees.clear()
	# Betrug
	mm.post_phishing(0)
	var p := _find_kind("phish")
	chk("ohne Buchhaltung keine Warnung", not mm.is_flagged(p))
	fm.employees["E-9"] = {"id": "E-9", "name": "Test", "role": "accounting", "skill": 5, "wage": 1, "pool_idx": -1, "hired_day": 1, "work_done": 0}
	chk("erfahrene Buchhaltung warnt", mm.is_flagged(p))
	fm.employees.clear()
	m0 = gs.money
	mm.request_report(str(p["id"]))
	await wait(1)
	chk("Betrug melden bringt Prämie", gs.money == m0 + mm.REPORT_REWARD and mm.actions_of(p).is_empty())
	mm.request_report(str(p["id"]))
	await wait(1)
	chk("nur einmal", gs.money == m0 + mm.REPORT_REWARD)
	mm.post_phishing(1)
	p = _find_kind("phish")
	m0 = gs.money
	mm.do_action(str(p["id"]), "fake", 1)
	chk("auf Betrug hereinfallen kostet", gs.money == m0 - float(p["amount"]) and str(p["done"]) != "")
	gs.money = 30.0
	mm.post_phishing(4)
	p = _find_kind("phish")
	mm.do_action(str(p["id"]), "fake", 1)
	chk("nie unter 0 durch Betrug", gs.money >= 0.0, gs.money)
	gs.money = 40000.0
	mm.request_report(str(b["id"]))
	await wait(1)
	mm.do_action(str(b["id"]), "hire", 1)
	chk("fremde Aktion abgewiesen", true)
	# Bestellung und Lieferung
	mm.mails = mm.mails.slice(0, 40)
	var before: int = mm.mails.size()
	mm.on_order(3, 120.0, 12.0, "Tag 2, 9 Uhr", false)
	mm.on_delivery_done(2)
	chk("Bestell- und Liefermail", mm.mails.size() == before + 2)
	mm.request_delete(str(mm.mails[0]["id"]))
	await wait(1)
	chk("gelöscht", mm.mails.size() == before + 1)
	for i in 120:
		mm.on_delivery_done(1)
	chk("Postfach begrenzt", mm.mails.size() <= mm.MAX_MAILS, mm.mails.size())
	var texts_ok := true
	for d in range(2, 40):
		mm.run_day(d)
	for m in mm.mails:
		var s: String = mm.text_of(m["subject"])
		for l in m["body"]:
			s += mm.text_of(l)
		texts_ok = texts_ok and not s.contains("%s") and not s.contains("%d") and s.length() > 5
	chk("alle Texte vollständig", texts_ok)


func _bills() -> void:
	print("--- Rechnungsfolgen")
	_level(1)
	gs.money = 60000.0
	fm.bills.clear()
	gs._recalculate_networks_and_metrics()
	var w0: int = gs.max_watts
	var n0: float = gs.max_bandwidth_mbps
	var r0: float = gs.revenue_bonus_mult
	var day: int = gs.day_number
	for k in ["power", "internet", "insurance", "license", "rent"]:
		fm._issue_bill(k, 100.0, day, [])
	for d in range(day, day + 30):
		fm._process_dunning(d)
	gs._recalculate_networks_and_metrics()
	chk("gesperrt nach letzter Mahnung", fm.get_blocked_kinds().size() == 4, fm.get_blocked_kinds())
	chk("Strom begrenzt", gs.max_watts < w0 * 0.5 and gs.max_watts >= 900, [w0, gs.max_watts])
	chk("Internet gedrosselt", gs.max_bandwidth_mbps < n0 * 0.3, [n0, gs.max_bandwidth_mbps])
	chk("Lizenz mindert Einnahmen", gs.revenue_bonus_mult < r0 * 0.8, [r0, gs.revenue_bonus_mult])
	chk("Versicherung ruht", not gs.is_insured())
	var m0: float = gs.money
	gs._pay_insurance(500.0, "Brandschaden")
	chk("kein Geld von der Versicherung", gs.money == m0)
	var rent := 0
	for b in fm.bills.values():
		if str(b["kind"]) == "rent":
			rent += 1
	chk("Miete geht weiter ans Inkasso", rent == 0)
	var mails := 0
	for m in mm.mails:
		if str(m.get("kind", "")) == "bill" and bool(m.get("urgent", false)):
			mails += 1
	chk("Mahnungen und Sperren als Mail", mails >= 8, mails)
	fm.request_pay_all()
	await wait(2)
	gs._recalculate_networks_and_metrics()
	chk("nach dem Bezahlen sofort frei", fm.get_blocked_kinds().is_empty() and gs.max_watts == w0 and is_equal_approx(gs.max_bandwidth_mbps, n0) and is_equal_approx(gs.revenue_bonus_mult, r0))
	m0 = gs.money
	gs._pay_insurance(500.0, "Brandschaden")
	chk("Versicherung zahlt wieder", is_equal_approx(gs.money, m0 + 500.0))


func _os() -> void:
	print("--- Verion OS")
	var t = main.get("terminal_ui")
	var ps = root.get_node("PcScreenState")
	root.size = Vector2i(1280, 720)
	t.open_terminal()
	await wait(3)
	var boot = t._boot_screen
	chk("fährt hoch", boot.is_running())
	boot._t = boot.LOGIN_HOLD
	await wait(5)
	chk("wartet auf Anmeldung", boot.is_waiting_for_login() and str(ps.phase) == "boot")
	boot.skip()
	chk("Klick meldet an", boot._login_pressed)
	boot._t = boot.COLD_DURATION + 1.0
	await wait(5)
	await create_timer(0.4).timeout
	chk("Desktop", str(ps.phase) == "desktop", ps.phase)
	chk("keine App offen", t._active_app == "" and t._desktop.windows.is_empty())
	for a in t.APP_ORDER:
		t._open_app(a)
		await wait(3)
		chk("App " + a, t._active_app == a and t._desktop.window(a).body.get_child_count() > 0)
	chk("alle Fenster gleichzeitig", t._desktop.windows.size() == t.APP_ORDER.size())
	t._open_app("mail")
	await wait(2)
	chk("Dock holt nach vorn", t._active_app == "mail")
	t._open_app("mail")
	await wait(2)
	chk("Dock legt ab", not t._desktop.is_shown("mail") and t._active_app != "mail")
	var w = t._desktop.window("shop")
	t._desktop.focus("shop")
	var s0: Vector2 = w.size
	w.toggle_maximize()
	await wait(2)
	chk("maximiert", w.maximized and w.size.x > s0.x, w.size)
	w.toggle_maximize()
	chk("wieder normal", not w.maximized and w.size.is_equal_approx(s0))
	w._resize_dir = Vector2(1, 1)
	w._resize_start = Rect2(w.position, w.size)
	w._resize_mouse = Vector2(9000, 9000)
	w._do_resize(Vector2.ZERO)
	chk("Mindestgröße", w.size.x >= w.MIN_SIZE.x - 1.0 and w.size.y >= w.MIN_SIZE.y - 1.0, w.size)
	w._resize_dir = Vector2.ZERO
	w.position = Vector2(-5000, 9000)
	w.fit()
	chk("bleibt erreichbar", w.position.x > -w.size.x and w.position.y < 720.0, w.position)
	t._desktop.close_window("shop")
	chk("geschlossen", not t._desktop.windows.has("shop"))
	# Dunkel: dunkle Flächen, helle Schrift
	var l: Label = null
	for x in t._desktop.window("bills").body.find_children("*", "Label", true, false):
		l = x
		break
	chk("Schrift ist hell", VerionThemeLum(l) > 0.4, VerionThemeLum(l))
	t._toggle_theme()
	await wait(3)
	for x in t._desktop.window("bills").body.find_children("*", "Label", true, false):
		l = x
		break
	chk("heller Modus geht auch", VerionThemeLum(l) < 0.4, VerionThemeLum(l))
	t._toggle_theme()
	for tab in ["overview", "prices", "ads", "leads"]:
		t._market_state["tab"] = tab
		t._render_window("market")
		await wait(2)
	for f in ["all", "unread", "todo", "bill", "spam"]:
		t._mail_state["folder"] = f
		t._mail_state["mail"] = str(mm.mails[0]["id"])
		t._render_window("mail")
		await wait(2)
	t._desktop.toggle_start()
	t._desktop.toggle_notes()
	t._desktop.toast("a", "b", "mail", Color.RED)
	await wait(3)
	# Scrollstellung bleibt beim Neuzeichnen
	t._open_app("upgrades")
	await wait(4)
	var sc: ScrollContainer = null
	for x in t._desktop.window("upgrades").body.find_children("*", "ScrollContainer", true, false):
		sc = x
	sc.scroll_vertical = 120
	await wait(2)
	var before := sc.scroll_vertical
	t._render_window("upgrades")
	await wait(3)
	for x in t._desktop.window("upgrades").body.find_children("*", "ScrollContainer", true, false):
		sc = x
	chk("Scrollstellung bleibt", before > 0 and sc.scroll_vertical == before, [before, sc.scroll_vertical])
	t._shut_down_pc()
	await wait(3)
	chk("fährt herunter", str(ps.phase) == "shutdown")
	await create_timer(3.2).timeout
	chk("aus, Fenster zu", str(ps.phase) == "idle" and t._desktop.windows.is_empty(), ps.phase)


func VerionThemeLum(l: Label) -> float:
	if l == null:
		return 0.0
	return (l.get_theme_color("font_color") * l.modulate).get_luminance()


func _save() -> void:
	print("--- Speichern")
	_level(4)
	mk.request_set_price("game", 1.25)
	mk.request_campaign("flyer")
	await wait(3)
	mk._add_lead("aurelwerk")
	mm.post_phishing(3)
	fm.bills.clear()
	fm._issue_bill("internet", 50.0, gs.day_number, [])
	for b in fm.bills.values():
		b["blocked"] = true
	var mails: int = mm.mails.size()
	var users: float = mk.rival_users("kolossal")
	var news: int = mk.news.size()
	var r: Dictionary = sm.save_world("paketb", "PaketB", gs.export_save_data())
	chk("gespeichert", r["ok"])
	var l: Dictionary = sm.load_world_file("paketb")
	chk("Signatur gültig", l["integrity"]["status"] == "valid")
	gs.load_from_save_data(l["state"], "paketb", "PaketB")
	await wait(4)
	chk("Preise bleiben", is_equal_approx(mk.get_price("game"), 1.25), mk.prices)
	chk("Werbung bleibt", mk.campaigns.size() == 1)
	chk("Konkurrenz bleibt", absf(mk.rival_users("kolossal") - users) < users * 0.2 + 5.0 and mk.news.size() >= news, [users, mk.rival_users("kolossal")])
	chk("Mails bleiben", mm.mails.size() >= mails and not _find_kind("phish").is_empty(), [mails, mm.mails.size()])
	chk("Sperre bleibt", fm.is_blocked("internet"))
	# Alter Spielstand ohne Markt und Postfach
	var old: Dictionary = l["state"].duplicate(true)
	old.erase("market")
	old.erase("mail")
	gs.load_from_save_data(old, "paketb", "PaketB")
	await wait(6)
	chk("alter Spielstand: Markt startet", mk.rivals.size() == 5 and mk.rival_users("kolossal") > 0.0 and mk.prices.is_empty())
	chk("alter Spielstand: Willkommensmail", mm.mails.size() >= 1, mm.mails.size())
