extends SceneTree
## Gameplay & Wirtschaft (GAME-01..10) ohne zweiten Spieler.
## Aufruf: godot --headless --path . --script res://tests/gameplay_check.gd

const PORT := 7911

var bad := 0
var gs: Node
var ops: Node
var fm: Node
var main: Node
var events: Array[String] = []


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	gs = root.get_node("GameState")
	ops = root.get_node("Operations")
	fm = root.get_node("FinanceManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	gs.pending_difficulty = "hard"
	root.get_node("NetworkManager").call("_start_host_internal", "Test", PORT, {}, "", "Gameplay", "", false, false)
	await wait(20)
	gs.event_logged.connect(func(msg: String, _sev: String) -> void: events.append(msg))

	await _check_difficulty()
	_check_tariff()
	await _check_generators()
	for m in ["_check_lan", "_check_sla", "_check_investors", "_check_staff", "_check_cyber", "_check_heat", "_check_certs"]:
		if has_method(m):
			await call(m)

	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").leave_session()
	quit(1 if bad > 0 else 0)


# --- GAME-10 Schwierigkeit ---

func _check_difficulty() -> void:
	chk("Neue Welt übernimmt die gewählte Schwierigkeit", gs.difficulty == "hard" and gs.pending_difficulty == "normal", gs.difficulty)
	chk("Schwer: weniger Startgeld", is_equal_approx(gs.money, 1200.0), gs.money)
	chk("Schwer: höhere Kosten und mehr Ausfälle", gs.diff("costs") > 1.0 and gs.diff("failures") > 1.0 and gs.diff("revenue") < 1.0)
	var before_bills: int = fm.bills.size()
	gs.money = 5000.0
	chk("Sandbox einschalten", gs.set_difficulty("sandbox") and gs.is_sandbox())
	chk("Sandbox: unendlich Geld", gs.money >= 9999999.0)
	chk("Sandbox: alles freigeschaltet", gs.is_part_unlocked({"vtier": 4}) and gs.is_item_unlocked("prop_diesel_gen"))
	fm.call("_issue_bill", "rent", 450.0, gs.day_number, [])
	chk("Sandbox: keine Rechnungen", fm.bills.size() == before_bills, fm.bills.size())
	chk("Zurück auf Normal gibt das alte Geld zurück", gs.set_difficulty("normal") and is_equal_approx(gs.money, 5000.0), gs.money)
	fm.call("_issue_bill", "rent", 450.0, gs.day_number, [])
	chk("Normal: Rechnungen wieder da", fm.bills.size() == before_bills + 1)
	var data: Dictionary = gs.export_save_data()
	chk("Schwierigkeit wird gespeichert", str(data.get("difficulty", "")) == "normal")
	gs.set_difficulty("easy")
	gs.load_from_save_data(data, "gameplay", "Gameplay")
	await wait(3)
	chk("Schwierigkeit wird geladen", gs.difficulty == "normal")
	chk("Alter Spielstand ohne Schwierigkeit ist Normal", Difficulty.valid("") == "normal" and Difficulty.mult("quatsch", "costs") == 1.0)


# --- GAME-02 Strompreis ---

func _check_tariff() -> void:
	chk("Tarifzonen", PowerTariff.zone_at(3.0)["id"] == "night" and PowerTariff.zone_at(12.0)["id"] == "day" and PowerTariff.zone_at(19.0)["id"] == "peak" and PowerTariff.zone_at(23.5)["id"] == "night")
	chk("Nächster Wechsel", int(PowerTariff.next_change(12.0)[0]) == 17 and int(PowerTariff.next_change(20.0)[0]) == 22)
	chk("Sonne nur tagsüber", PowerTariff.sun_at(2.0) == 0.0 and PowerTariff.sun_at(13.0) > 0.9)
	chk("Weniger Sonne bei Regen", PowerTariff.solar_share(13.0, "rain") < PowerTariff.solar_share(13.0, "clear"))
	var P: GDScript = load("res://scripts/autoload/game_state/power.gd")
	gs.total_watts = 6000
	gs.on_generator = false
	gs.electricity_rate = 1.0
	gs.daily_energy_cost = 0.0
	gs.daily_kwh = 0.0
	gs.daily_peak_kw = 0.0
	gs.time_of_day = 3.0 / 24.0
	P.account_energy(60.0, 0.0, 0.0)
	var night: float = gs.daily_energy_cost
	gs.daily_energy_cost = 0.0
	gs.time_of_day = 19.0 / 24.0
	P.account_energy(60.0, 0.0, 0.0)
	var peak: float = gs.daily_energy_cost
	chk("Nachts billiger als abends", night > 0.0 and peak > night * 1.9, [night, peak])
	chk("Tagesspitze wird gemerkt", is_equal_approx(gs.daily_peak_kw, 6.0), gs.daily_peak_kw)
	chk("Rechnung = Arbeitspreis + Leistungspreis", gs.get_estimated_daily_bill() == int(roundf(gs.daily_energy_cost + 6.0 * PowerTariff.PEAK_CHARGE_PER_KW)), gs.get_estimated_daily_bill())
	gs.daily_peak_kw = 0.0
	P.account_energy(60.0, 0.0, 2.0)
	chk("Peak-Shaving senkt die Netzlast", is_equal_approx(gs.daily_peak_kw, 4.0), gs.daily_peak_kw)
	ops.request_set_peak_shaving(true)
	chk("Peak-Shaving einschalten", ops.peak_shaving)
	ops.request_set_peak_shaving(false)


# --- GAME-01 Notstrom ---

func _check_generators() -> void:
	chk("Ohne Aggregat: Redundanz N", ops.redundancy_level() == "N", ops.redundancy_level())
	var spot := Vector3(9.2, 0.0, 6.4)
	chk("Aggregat passt auf den Rasen", gs.can_place_item_at("prop_diesel_gen", spot), spot)
	chk("Aggregat nicht in der Halle", not gs.can_place_item_at("prop_diesel_gen", Vector3(0.0, 0.0, 0.0)))
	gs.decor_items["decor_gen1"] = {"id": "decor_gen1", "item_type": "prop_diesel_gen", "pos": spot, "rot_y": 0.0, "wall": false, "stored_items": [], "fuel": 100.0, "running": false, "starting": 0.0}
	chk("Zweites Aggregat nicht direkt daneben", not gs.can_place_item_at("prop_diesel_gen", spot + Vector3(0.6, 0.0, 0.0)))
	chk("Verschieben an den eigenen Platz geht", gs.can_place_item_at("prop_diesel_gen", spot, 0.0, "decor_gen1"))
	gs.total_watts = 8000
	chk("Mit Diesel: Redundanz N+1", ops.redundancy_level() == "N+1", ops.redundancy_level())
	gs.breaker_on = true
	gs.call("_start_grid_outage", 600.0)
	chk("Netzausfall schaltet ab", not gs.breaker_on and gs.grid_outage_left > 0.0)
	ops.tick_generators(1.0)
	var g0: Dictionary = gs.decor_items["decor_gen1"]
	chk("Aggregat startet", float(g0["starting"]) > 0.0 and not gs.on_generator, g0["starting"])
	for i in 16:
		ops.tick_generators(1.0)
	chk("Nach 15 s läuft es und der Strom ist da", gs.on_generator and gs.breaker_on and bool(gs.decor_items["decor_gen1"]["running"]))
	var fuel0 := float(gs.decor_items["decor_gen1"]["fuel"])
	# Das Anspringen rechnet die Netze neu, in der leeren Testwelt ist die Last danach 0.
	gs.total_watts = 8000
	ops.tick_generators(60.0)
	chk("Diesel wird nach Last verbraucht", float(gs.decor_items["decor_gen1"]["fuel"]) < fuel0, [fuel0, gs.decor_items["decor_gen1"]["fuel"]])
	gs.total_watts = 60000
	for i in 5:
		ops.tick_generators(1.0)
	chk("Überlast schaltet das Aggregat ab", not gs.on_generator and not gs.breaker_on)
	gs.total_watts = 8000
	gs.call("_end_grid_outage")
	ops.tick_generators(1.0)
	chk("Netz zurück: Aggregat aus, Netz an", not gs.on_generator and gs.breaker_on and not bool(gs.decor_items["decor_gen1"]["running"]))
	gs.money = 10000.0
	var m0: float = gs.money
	ops.request_order_diesel(50)
	chk("Diesel bestellen kostet Geld", ops.fuel_orders.size() == 1 and gs.money < m0)
	var f1 := float(gs.decor_items["decor_gen1"]["fuel"])
	ops.tick_generators(ops.TANKER_DELAY + 1.0)
	chk("Tankwagen füllt nach", ops.fuel_orders.is_empty() and float(gs.decor_items["decor_gen1"]["fuel"]) > f1 + 49.0)
	ops.request_order_diesel(1000)
	chk("Nicht mehr bestellen als in die Tanks passt", ops.fuel_orders.is_empty())
	# Altes Gebäude-Upgrade an Halle Nord bekommt über SaveSchema 6 einen vollen Tank.
	var data: Dictionary = gs.export_save_data()
	data.erase("schema")
	data["operations"] = {}
	(data["building_upgrades"] as Dictionary)["upg_diesel_gen"] = true
	gs.load_from_save_data(data, "gameplay", "Gameplay")
	await wait(3)
	chk("Altes Halle-Nord-Aggregat: voller Tank", is_equal_approx(ops.nord_fuel, 2000.0) and ops.generators().size() == 2, ops.nord_fuel)
	gs.decor_items.erase("decor_gen1")
	(gs.building_upgrades as Dictionary).erase("upg_diesel_gen")


# --- GAME-03 LAN-Ketten ---

func _check_lan() -> void:
	var C: GDScript = load("res://scripts/autoload/game_state/cables.gd")
	gs.max_bandwidth_mbps = 10000.0
	chk("LAN-Kette trägt höchstens 1 Gbit/s", is_equal_approx(gs.lan_chain_cap(), 1000.0))
	gs.max_bandwidth_mbps = 250.0
	chk("Kleiner Router begrenzt auch die Kette", is_equal_approx(gs.lan_chain_cap(), 250.0))
	gs.max_bandwidth_mbps = 10000.0
	gs.racks["rack_lan"] = gs._make_rack_data("rack_lan", "rack", Vector3(1, 0, 1), 0.0)
	gs.racks["rack_lan"]["networked"] = true
	gs.racks["rack_lan"]["rental_type"] = "web"
	gs.racks["rack_lan"]["active_users"] = 4000
	gs.decor_items["decor_lan1"] = {"id": "decor_lan1", "item_type": "prop_lan_strip", "pos": Vector3.ZERO, "rot_y": 0.0, "wall": false, "stored_items": []}
	gs._lan_parent = {"rack_lan": "decor_lan1"}
	C._compute_lan_chains()
	var mb := float(gs.lan_chain_mbps.get("decor_lan1", 0.0))
	chk("Kette kennt ihre Racks und deren Bandbreite", str(gs.lan_chain_of.get("rack_lan", "")) == "decor_lan1" and mb > 0.0, [mb, gs.lan_chain_of])
	gs.racks.erase("rack_lan")
	gs.decor_items.erase("decor_lan1")
	gs._lan_parent = {}


# --- GAME-05 SLA & Bewertungen ---

func _check_sla() -> void:
	var C: GDScript = load("res://scripts/autoload/game_state/contracts.gd")
	gs.reviews = []
	chk("Ohne Bewertungen 3,5 Sterne", is_equal_approx(gs.rating_avg(), 3.5))
	var cid := "c_blog"
	if bool(gs.contracts[cid]["active"]):
		gs.do_toggle_contract(cid, 1)
	gs.do_toggle_contract(cid, 1, "gold")
	chk("Gold braucht 4 Sterne", not bool(gs.contracts[cid]["active"]))
	gs.do_toggle_contract(cid, 1, "silver")
	chk("Silber geht ab 3 Sternen", bool(gs.contracts[cid]["active"]) and str(gs.contracts[cid]["sla"]) == "silver")
	gs.total_ram_gb = 4096
	gs.max_bandwidth_mbps = 100000.0
	gs.ddos_active = false
	var m0: float = gs.money
	C._process_contract_payouts()
	var gain: float = gs.money - m0
	var base: float = float(gs.contracts[cid]["payout_per_cycle"]) * float(gs.revenue_bonus_mult)
	chk("Silber zahlt ×1,25", is_equal_approx(gain, base * 1.25), [gain, base])
	gs.total_ram_gb = 0
	events.clear()
	for i in 6:
		C._process_contract_payouts()
	chk("Ausfälle senken die Verfügbarkeit", Sla.availability(gs.contracts[cid]) < 0.99, Sla.availability(gs.contracts[cid]))
	var warned := false
	for e in events:
		if e.contains("SLA"):
			warned = true
	chk("SLA-Verletzung wird gemeldet", warned, events)
	var rep0: float = gs.reputation
	for i in 5:
		gs.add_review("Testkunde", 5, "Top")
	chk("Bewertungen heben Schnitt und Ruf", gs.rating_avg() > 4.0 and gs.reputation > rep0, [gs.rating_avg(), gs.reputation])
	gs.do_toggle_contract(cid, 1)
	chk("Kündigen nach Ausfällen gibt eine schwache Bewertung", int(gs.reviews.back()["stars"]) <= 4)
	gs.do_toggle_contract(cid, 1, "gold")
	chk("Mit guten Bewertungen geht Gold", bool(gs.contracts[cid]["active"]) and str(gs.contracts[cid]["sla"]) == "gold")
	gs.do_toggle_contract(cid, 1)
	chk("Sterne aus der Verfügbarkeit", Sla.stars_for({"sla": "gold", "sla_ok": 100.0, "sla_n": 100.0}) == 5 and Sla.stars_for({"sla": "gold", "sla_ok": 50.0, "sla_n": 100.0}) == 1)
	var data: Dictionary = gs.export_save_data()
	chk("Bewertungen werden gespeichert", (data.get("reviews", []) as Array).size() == gs.reviews.size())


# --- GAME-04 Investoren & Monatsbilanz ---

func _check_investors() -> void:
	var C: GDScript = load("res://scripts/autoload/game_state/contracts.gd")
	gs.company_level = 1
	fm.investors.clear()
	fm.request_accept_investor("angel")
	chk("Investor erst ab Firmenstufe 2", fm.investors.is_empty())
	gs.company_level = 3
	var m0: float = gs.money
	fm.request_accept_investor("angel")
	chk("Investor zahlt ein", fm.investors.size() == 1 and is_equal_approx(gs.money - m0, 15000.0), gs.money - m0)
	fm.request_accept_investor("angel")
	chk("Derselbe Investor nur einmal", fm.investors.size() == 1)
	fm.request_accept_investor("vc")
	fm.request_accept_investor("fund")
	chk("Höchstens zwei Investoren, der Fonds braucht Stufe 5", fm.investors.size() == 2)
	chk("Anteile addieren sich", is_equal_approx(fm.investor_share_total(), 0.25), fm.investor_share_total())
	chk("Investoren nehmen ihren Anteil", is_equal_approx(fm.investor_cut(1000.0), 250.0))
	# Zahlungstakt: Vertrag läuft, Investoren bekommen ihren Teil, alles im Kassenbuch.
	var cid := "c_blog"
	if not bool(gs.contracts[cid]["active"]):
		gs.do_toggle_contract(cid, 1)
	gs.total_ram_gb = 4096
	gs.max_bandwidth_mbps = 100000.0
	fm.ledger.clear()
	var before: float = gs.money
	C._process_contract_payouts()
	var row: Dictionary = fm.ledger.get(str(gs.day_number), {})
	var pay := float(row.get("contracts", 0.0))
	chk("Kassenbuch: Vertragseinnahmen", pay > 0.0, row)
	chk("Kassenbuch: Gewinnanteil abgezogen", is_equal_approx(float(row.get("investors", 0.0)), -pay * 0.25), row)
	chk("Konto bekommt Einnahmen minus Anteil", is_equal_approx(gs.money - before, pay * 0.75 + float(row.get("rentals", 0.0)) * 0.75), gs.money - before)
	gs.do_toggle_contract(cid, 1)
	# Monatsbilanz
	fm.ledger = {"1": {"contracts": 500.0, "bills": -120.0}, "2": {"wages": -80.0, "other": 30.0}, "31": {"rentals": 900.0}}
	var s1: Dictionary = fm.month_summary(1)
	chk("Monat 1: Einnahmen, Ausgaben, Ergebnis", is_equal_approx(float(s1["income"]), 530.0) and is_equal_approx(float(s1["expense"]), 200.0) and is_equal_approx(float(s1["net"]), 330.0), s1)
	chk("Monat 2 ist getrennt", is_equal_approx(float(fm.month_summary(2)["net"]), 900.0) and fm.month_of(31) == 2 and fm.month_of(30) == 1)
	# Tagesabschluss bucht den Rest als Sonstiges
	fm.ledger = {}
	fm.set("_day_money", {str(gs.day_number): 1000.0})
	gs.money = 1600.0
	fm.book("contracts", 400.0)
	fm.call("_close_ledger_day", gs.day_number + 1)
	chk("Rest des Tages wird Einkäufe & Sonstiges", is_equal_approx(float(fm.ledger[str(gs.day_number)].get("other", 0.0)), 200.0), fm.ledger)
	# Rückkauf und Ablauf
	var inv_id := str(fm.investors.keys()[0])
	gs.money = 100000.0
	var cost: int = fm.get_buyout_cost(fm.investors[inv_id])
	fm.request_buyout_investor(inv_id)
	chk("Rückkauf kostet Geld und beendet die Beteiligung", not fm.investors.has(inv_id) and is_equal_approx(gs.money, 100000.0 - float(cost)), cost)
	var other_id := str(fm.investors.keys()[0])
	fm.investors[other_id]["days_left"] = 1
	fm.call("_tick_investors", gs.day_number)
	chk("Beteiligung läuft aus", fm.investors.is_empty())
	var data: Dictionary = fm.export_data()
	chk("Investoren und Kassenbuch werden gespeichert", data.has("investors") and data.has("ledger"))


# --- GAME-07 Personal ---

func _check_staff() -> void:
	var st: Node = root.get_node("Staff")
	gs.money = 50000.0
	var pool: Array = fm.CANDIDATE_POOL
	var idx_clean := -1
	var idx_guard := -1
	var idx_admin := -1
	for i in pool.size():
		match str(pool[i]["role"]):
			"cleaning":
				idx_clean = i if idx_clean < 0 else idx_clean
			"security":
				idx_guard = i if idx_guard < 0 else idx_guard
			"netadmin":
				idx_admin = i if idx_admin < 0 else idx_admin
	chk("Neue Rollen haben Bewerbungen", idx_clean >= 0 and idx_guard >= 0 and idx_admin >= 0)
	fm.request_hire(idx_clean)
	fm.request_hire(idx_guard)
	fm.request_hire(idx_admin)
	chk("Reinigung, Wachdienst und Admin eingestellt", not st.worker("cleaning").is_empty() and not st.worker("security").is_empty() and not st.worker("netadmin").is_empty())
	# Reinigung tagsüber
	gs.time_of_day = 10.0 / 24.0
	chk("Reinigung tagsüber im Dienst, Wachdienst nicht", st.on_duty("cleaning") and not st.on_duty("security"))
	gs.racks["rack_dust"] = gs._make_rack_data("rack_dust", "rack", Vector3(-1.0, 0.0, 0.0), 0.0)
	var slot: Dictionary = gs.racks["rack_dust"]["slots"][0]
	slot["item_type"] = "web_server"
	slot["dust_level"] = 60.0
	st.call("_plan", "cleaning")
	st.call("_plan", "cleaning")
	chk("Reinigung geht zum staubigen Rack", str(st.views["cleaning"].get("phase", "")) == "walk" and str(st.call("_st", "cleaning")["target"]) == "rack_dust", st.views["cleaning"].get("text", ""))
	st.call("_advance", "cleaning", 120.0)
	st.call("_plan", "cleaning")
	chk("Reinigung putzt", str(st.views["cleaning"].get("phase", "")) == "work")
	st.call("_advance", "cleaning", 60.0)
	chk("Staub ist weg", float(gs.racks["rack_dust"]["slots"][0]["dust_level"]) < 25.0, gs.racks["rack_dust"]["slots"][0]["dust_level"])
	gs.racks.erase("rack_dust")
	# Wachdienst nachts
	gs.time_of_day = 23.0 / 24.0
	chk("Wachdienst nachts im Dienst", st.on_duty("security") and not st.on_duty("cleaning"))
	chk("Wachdienst schreckt Diebe ab", st.thief_factor() < 0.7, st.thief_factor())
	st.views["security"] = {"id": "x", "phase": "idle", "pos": Vector3(1.0, 0.0, 8.0), "path": [], "dur": 0.0, "stamp": 0}
	chk("Wachdienst stellt nahe Diebe", st.guard_catches(Vector3(1.5, 0.0, 8.5)) and not st.guard_catches(Vector3(8.0, 0.0, 2.0)))
	gs.time_of_day = 10.0 / 24.0


# --- GAME-06 Cyberangriffe ---

func _check_cyber() -> void:
	var cy: Node = root.get_node("Cyber")
	cy.reset()
	cy.start_attack("ddos")
	chk("DDoS läuft und legt den Verkehr lahm", not cy.attack.is_empty() and gs.ddos_active and cy.bad_left() >= 4)
	var srcs: Array = cy.attack["sources"]
	var good: Dictionary = {}
	for s in srcs:
		if not bool(s["bad"]):
			good = s
	gs.racks["rack_cy"] = gs._make_rack_data("rack_cy", "rack", Vector3(1, 0, 1), 0.0)
	gs.racks["rack_cy"]["rental_type"] = "web"
	gs.racks["rack_cy"]["satisfaction"] = 90.0
	cy.request_block(str(good["id"]))
	chk("Echte Quelle sperren kostet Zufriedenheit", bool(good["blocked"]) and float(gs.racks["rack_cy"]["satisfaction"]) < 90.0)
	for s in srcs:
		if bool(s["bad"]):
			cy.request_block(str(s["id"]))
	chk("Alle Angreifer gesperrt: Angriff abgewehrt", cy.attack.is_empty() and not gs.ddos_active and int(cy.stats["won"]) == 1)
	cy.request_set_rule("ratelimit", true)
	cy.start_attack("ddos")
	chk("Mit Ratenlimit läuft der Verkehr weiter, nur gebremst", not gs.ddos_active and cy.income_mult() < 0.65, cy.income_mult())
	cy.tick(999.0)
	chk("Zeit abgelaufen: durchgekommen", cy.attack.is_empty() and int(cy.stats["lost"]) == 1)
	cy.request_set_rule("ratelimit", false)
	# Erpressungstrojaner ohne und mit Backup. Der Admin aus dem Personal-Test bleibt so lange draußen,
	# sonst wehrt er den Trojaner im großen Testschritt manchmal schon selbst ab.
	var admins := {}
	for k in fm.employees.keys():
		if str(fm.employees[k].get("role", "")) == "netadmin":
			admins[k] = fm.employees[k]
	for k in admins.keys():
		fm.employees.erase(k)
	gs.racks["rack_cy"]["slots"][0]["item_type"] = "web_server"
	gs.money = 10000.0
	cy.start_attack("ransom")
	cy.tick(999.0)
	chk("Ohne Backup: Rack verschlüsselt und teuer", cy.is_encrypted("rack_cy") and gs.money < 10000.0, [cy.encrypted, gs.money])
	cy.encrypted.clear()
	cy.request_set_rule("backup", true)
	cy.start_attack("ransom")
	cy.tick(999.0)
	chk("Mit Backup: nur kurz weg", cy.is_encrypted("rack_cy") and float(cy.encrypted["rack_cy"]) <= cy.BACKUP_OFFLINE)
	cy.tick(cy.BACKUP_OFFLINE + 1.0)
	chk("Danach läuft es wieder", not cy.is_encrypted("rack_cy"))
	fm.employees.merge(admins)
	# Einbruchserkennung gibt mehr Zeit, der Admin blockt selbst
	cy.request_set_rule("ids", true)
	cy.start_attack("ddos")
	chk("IDS: 20 s mehr Zeit", is_equal_approx(float(cy.attack["total"]), 80.0))
	var bad0: int = cy.bad_left()
	for i in 4:
		cy.tick(5.0)
	chk("Netzwerk-Admin blockt Angreifer", cy.bad_left() < bad0 or cy.attack.is_empty(), [bad0, cy.bad_left()])
	cy.attack = {}
	cy.call("_apply_ddos_flag")
	chk("Lizenzen kosten am Tag", cy.daily_cost() == 70)
	gs.racks.erase("rack_cy")
	var data: Dictionary = gs.export_save_data()
	chk("Firewall wird gespeichert", (data.get("cyber", {}) as Dictionary).has("rules") and ((data["cyber"]["rules"]) as Dictionary).has("backup"))
	cy.reset()


# --- GAME-08 Fernwärme ---

func _check_heat() -> void:
	ops.reset()
	(gs.building_upgrades as Dictionary).erase("upg_district_heat")
	chk("Fernwärme ist ein Gebäude-Ausbau", gs.BUILDING_UPGRADE_CATALOG.has("upg_district_heat") and "upg_district_heat" in gs.BUILDING_UPGRADE_ORDER)
	gs.total_watts = 20000
	ops.tick_heat(60.0)
	chk("Ohne Anschluss keine Wärme", ops.heat_kw_now() == 0.0 and ops.heat_kwh_today == 0.0)
	gs.building_upgrades["upg_district_heat"] = true
	chk("Wärmeleistung = 65 % der IT-Last", is_equal_approx(ops.heat_kw_now(), 13.0), ops.heat_kw_now())
	var day0: int = gs.day_number
	gs.day_number = 2 # Frühling
	ops.set("_heat_day", 2)
	ops.tick_heat(60.0)
	chk("Eine Spielminute = 1 h: 13 kWh", is_equal_approx(ops.heat_kwh_today, 13.0), ops.heat_kwh_today)
	var spring: float = ops.heat_money_today
	chk("Preis × Nachfrage × Schwierigkeit", is_equal_approx(spring, 13.0 * ops.HEAT_PRICE * 1.0 * gs.diff("revenue")), spring)
	gs.day_number = 14 # Winter
	chk("Im Winter mehr Nachfrage als im Sommer", ops.heat_demand() > 1.5)
	gs.day_number = 6 # Sommer
	chk("Im Sommer wenig Nachfrage", ops.heat_demand() < 0.5)
	gs.day_number = 3
	var m0: float = gs.money
	var rep0: float = gs.reputation
	ops.tick_heat(0.01)
	chk("Um Mitternacht wird ausgezahlt", gs.money > m0 + spring * 0.99 and ops.heat_kwh_today < 0.01 and ops.heat_money_total > 0.0, [gs.money - m0, spring])
	chk("Fernwärme bringt etwas Ruf", gs.reputation > rep0 or rep0 >= 100.0)
	chk("Fernwärme steht in der Bilanz", _ledger_has("heat"), fm.ledger.keys().size())
	var data: Dictionary = gs.export_save_data()
	chk("Fernwärme wird gespeichert", (data.get("operations", {}) as Dictionary).has("heat"))
	gs.day_number = day0
	(gs.building_upgrades as Dictionary).erase("upg_district_heat")
	gs.total_watts = 0


func _ledger_has(cat: String) -> bool:
	for d in fm.ledger.keys():
		if float((fm.ledger[d] as Dictionary).get(cat, 0.0)) != 0.0:
			return true
	return float((fm.get("_day_money") as Dictionary).get(cat, 0.0)) != 0.0


# --- GAME-09 Zertifikate ---

func _check_certs() -> void:
	var cy: Node = root.get_node("Cyber")
	var st: Node = root.get_node("Staff")
	ops.reset()
	cy.reset()
	chk("Ohne Zertifikat kein Bonus", is_equal_approx(ops.cert_mult(), 1.0))
	chk("Tier III hat 5 Prüfpunkte", ops.cert_checks("tier3").size() == 5)
	chk("ISO 27001 hat 5 Prüfpunkte", ops.cert_checks("iso27001").size() == 5)
	gs.money = 20000.0
	var m0: float = gs.money
	ops.request_audit("tier3")
	chk("Prüfung beantragt und bezahlt", str(ops.audit.get("cert", "")) == "tier3" and is_equal_approx(m0 - gs.money, 4000.0 * gs.diff("costs")), m0 - gs.money)
	var m1: float = gs.money
	ops.request_audit("iso27001")
	chk("Nur eine Prüfung gleichzeitig", str(ops.audit["cert"]) == "tier3" and gs.money == m1)
	ops.tick_audit(ops.AUDIT_DELAY + 0.1)
	chk("Der Prüfer kommt und läuft", str(ops.audit.get("phase", "")) == "walk" and not (st.views["auditor"] as Dictionary).is_empty())
	var npc: Node = main.find_child("Staff_auditor", true, false)
	await wait(2)
	chk("Prüfer-Figur ist zu sehen", npc != null and npc.visible and npc.get("_human") != null)
	ops.tick_audit(ops.AUDIT_WALK + 0.1)
	chk("Leere Anlage fällt durch", ops.audit.is_empty() and not ops.cert_valid("tier3") and not (ops.certs["tier3"]["last"] as Array).is_empty(), ops.certs.get("tier3", {}))
	chk("Prüfer geht wieder", (st.views["auditor"] as Dictionary).is_empty())
	# Tier III erfüllen: Aggregat mit Diesel, USV, Rack an A+B, kühl.
	gs.decor_items["decor_genc"] = {"id": "decor_genc", "item_type": "prop_diesel_gen", "pos": Vector3(9.2, 0.0, 6.4), "rot_y": 0.0, "wall": false, "stored_items": [], "fuel": 120.0, "running": false, "starting": 0.0}
	gs.ups_units["ups_c"] = {"id": "ups_c", "pos": Vector3(-3, 0, -3), "ups_type": "ups", "health": 100.0, "rot_y": 0.0, "connected": true, "charge": 80.0, "discharging": false}
	gs.racks["rack_c"] = gs._make_rack_data("rack_c", "rack", Vector3(1, 0, 1), 0.0)
	gs.racks["rack_c"]["slots"][0]["item_type"] = "web_server"
	gs.racks["rack_c"]["temp"] = 24.0
	for i in 2:
		gs.cables["cab_c%d" % i] = {"id": "cab_c%d" % i, "cable_type": "power", "from_id": "rack_c", "to_id": "ups_c", "from_slot": i, "to_slot": i}
	var fails: Array = []
	for c in ops.cert_checks("tier3"):
		if not bool(c[1]):
			fails.append(c[0])
	chk("Tier III: alle Punkte erfüllt", fails.is_empty(), fails)
	ops.request_audit("tier3")
	ops.tick_audit(ops.AUDIT_DELAY + 0.1)
	ops.tick_audit(ops.AUDIT_WALK + 0.1)
	chk("Tier III bestanden, ein Spieljahr gültig", ops.cert_valid("tier3") and int(ops.certs["tier3"]["valid_until"]) == gs.day_number + 16, ops.certs.get("tier3", {}))
	chk("Bonus ×1,15", is_equal_approx(ops.cert_mult(), 1.15), ops.cert_mult())
	# ISO 27001: Firewall, Backup, Kamera, Wachdienst
	cy.request_set_rule("ports", true)
	cy.request_set_rule("ids", true)
	cy.request_set_rule("backup", true)
	gs.breaker_on = true
	gs.decor_items["decor_camc"] = {"id": "decor_camc", "item_type": "prop_cctv_monitor", "pos": Vector3(-4.0, 1.0, 4.0), "rot_y": 0.0, "wall": false, "stored_items": []}
	fm.employees["emp_secc"] = {"id": "emp_secc", "name": "Test Wache", "role": "security", "skill": 2, "salary": 0}
	var iso_fail: Array = []
	for c in ops.cert_checks("iso27001"):
		if not bool(c[1]):
			iso_fail.append(c[0])
	chk("ISO 27001: alle Punkte erfüllt", iso_fail.is_empty(), iso_fail)
	cy.history.append({"day": gs.day_number, "kind": "ddos", "result": "durchgekommen"})
	chk("Frischer erfolgreicher Angriff verhindert ISO", not bool(ops.cert_checks("iso27001")[4][1]))
	cy.history.clear()
	ops.request_audit("iso27001")
	ops.tick_audit(ops.AUDIT_DELAY + 0.1)
	ops.tick_audit(ops.AUDIT_WALK + 0.1)
	chk("Beide Zertifikate: ×1,15 × ×1,10", is_equal_approx(ops.cert_mult(), 1.15 * 1.10), ops.cert_mult())
	var data: Dictionary = gs.export_save_data()
	chk("Zertifikate werden gespeichert", ((data.get("operations", {}) as Dictionary).get("certs", {}) as Dictionary).has("tier3"))
	var day0: int = gs.day_number
	gs.day_number += 17
	events.clear()
	ops.tick_audit(0.1)
	chk("Nach einem Jahr abgelaufen, mit Hinweis", not ops.cert_valid("tier3") and is_equal_approx(ops.cert_mult(), 1.0) and events.any(func(e): return "abgelaufen" in e), events)
	gs.day_number = day0
	gs.decor_items.erase("decor_genc")
	gs.decor_items.erase("decor_camc")
	gs.ups_units.erase("ups_c")
	gs.racks.erase("rack_c")
	gs.cables.erase("cab_c0")
	gs.cables.erase("cab_c1")
	fm.employees.erase("emp_secc")
	cy.reset()
	ops.reset()
