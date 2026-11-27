extends RefCounted
## Verträge und Kunden: Vertragsangebote, Auszahlungen, Rack-Vermietung, Dienste und ihre Nutzer,
## Ruf der Firma, Support-Tickets und Anrufe, Team-Aufträge.
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


static func get_max_contracts_limit() -> int:
	var lvl_b: Dictionary = GameState.COMPANY_LEVEL_BENEFITS.get(GameState.get_company_level(), {})
	return int(lvl_b.get("max_contracts", 4)) + GameState.career_completed.size()


static func get_open_ticket_count() -> int:
	return GameState.support_tickets.size()


static func is_ticket_issue_fixed(ticket: Dictionary) -> bool:
	var rid := str(ticket.get("rack_id", ""))
	if not GameState.racks.has(rid):
		return true
	var r: Dictionary = GameState.racks[rid]
	if str(r.get("rental_type", "none")) == "none":
		return true
	var issue := str(ticket.get("issue_key", "ok"))
	var m: Dictionary = r.get("metrics", {})
	if not bool(r.get("powered", false)) or not bool(r.get("networked", false)):
		return false
	match issue:
		"ram":
			return float(m.get("ram_pct", 0.0)) < 88.0
		"cpu":
			return float(m.get("cpu_pct", 0.0)) < 88.0
		"gpu":
			return float(m.get("gpu_pct", 0.0)) < 88.0
		"storage":
			return float(m.get("storage_pct", 0.0)) < 88.0
		"network":
			return float(m.get("net_pct", 0.0)) < 90.0 and GameState.used_bandwidth_mbps <= GameState.max_bandwidth_mbps
		"overheat":
			return float(r.get("temp", 22.0)) < 68.0
		"psu":
			return not bool(GameState.get_rack_hardware_summary(rid)["psu_overloaded"])
		"offline":
			return bool(r.get("powered", false)) and bool(r.get("networked", false)) and int(GameState.get_rack_hardware_summary(rid)["active_servers"]) > 0
		_:
			return str(m.get("bottleneck", "ok")) == "ok"


static func get_active_contract_count() -> int:
	var n := 0
	for cid in GameState.contracts.keys():
		if bool(GameState.contracts[cid]["active"]):
			n += 1
	return n


## Reihenfolge für die Anzeige: feste Vorlagen zuerst, danach befristete Angebote.
static func get_contract_display_order() -> Array[String]:
	var order: Array[String] = []
	for tmpl in GameState.CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		var cid := str(tmpl_dict["id"])
		if GameState.contracts.has(cid):
			order.append(cid)
	var extra: Array[String] = []
	for key in GameState.contracts.keys():
		var cid := str(key)
		if not order.has(cid):
			extra.append(cid)
	extra.sort()
	order.append_array(extra)
	return order


## Erzeugt ein befristetes Angebot, abgeleitet von einer Vorlage, die zum aktuellen Ausbau passt.
## GAME-05: Kurztext einer Bewertung je Sterne (übersetzt in der Sprache des Hosts).
static func tr_review(stars: int) -> String:
	match clampi(stars, 1, 5):
		5:
			return TranslationServer.translate("Läuft absolut zuverlässig, gerne wieder.")
		4:
			return TranslationServer.translate("Fast immer erreichbar, kleine Aussetzer.")
		3:
			return TranslationServer.translate("Geht so, öfter mal langsam.")
		2:
			return TranslationServer.translate("Zu viele Ausfälle für unser Geld.")
	return TranslationServer.translate("Nie wieder, ständig offline.")


## GAME-05: Mieter bewerten ab und zu, je nach Zufriedenheit. Einmal am Tag, nur Host.
static func _daily_rental_reviews() -> void:
	for rid in GameState.racks.keys():
		var r := RackData.of(GameState.racks[rid])
		if r.services.is_empty() or randf() > 0.2:
			continue
		var sat := r.satisfaction
		var st := 5 if sat >= 92.0 else (4 if sat >= 80.0 else (3 if sat >= 60.0 else (2 if sat >= 40.0 else 1)))
		GameState.add_review(r.rental_customer if not r.rental_customer.is_empty() else "Mieter", st, tr_review(st))


static func _make_random_contract() -> Dictionary:
	var ram_cap := maxi(int(GameState.total_ram_gb), 4) * GameState.RANDOM_CONTRACT_RAM_REACH
	var bases: Array[Dictionary] = []
	for tmpl in GameState.CONTRACTS_TEMPLATE:
		var tmpl_dict: Dictionary = tmpl
		if int(tmpl_dict["req_ram_gb"]) <= ram_cap:
			bases.append(tmpl_dict)
	if bases.is_empty():
		var first: Dictionary = GameState.CONTRACTS_TEMPLATE[0]
		bases.append(first)
	var base: Dictionary = bases[randi() % bases.size()]
	var scale := randf_range(GameState.RANDOM_CONTRACT_SCALE_MIN, GameState.RANDOM_CONTRACT_SCALE_MAX)
	var premium := randf_range(GameState.RANDOM_CONTRACT_PREMIUM_MIN, GameState.RANDOM_CONTRACT_PREMIUM_MAX)
	var cid := ""
	while cid == "" or GameState.contracts.has(cid):
		cid = "r_%d_%d" % [GameState.day_number, randi() % 100000]
	return {
		"id": cid,
		"title": str(GameState.RANDOM_CONTRACT_TITLES[randi() % GameState.RANDOM_CONTRACT_TITLES.size()]),
		"client": str(GameState.RANDOM_CONTRACT_CLIENTS[randi() % GameState.RANDOM_CONTRACT_CLIENTS.size()]),
		"required_compute": maxi(1, int(roundf(float(base["required_compute"]) * scale))),
		"req_ram_gb": maxi(2, int(roundf(float(base["req_ram_gb"]) * scale))),
		"req_mbps": snappedf(maxf(5.0, float(base["req_mbps"]) * scale), 0.5),
		# GAME-05: Gute Bewertungen bringen besser bezahlte Anfragen (bei 3,5 Sternen wie bisher).
		"payout_per_cycle": maxi(1, int(roundf(float(base["payout_per_cycle"]) * scale * premium * (0.825 + 0.05 * GameState.rating_avg())))),
		"penalty_per_cycle": maxi(1, int(roundf(float(base["penalty_per_cycle"]) * scale * GameState.RANDOM_CONTRACT_PENALTY_MULT))),
		"random": true,
		"duration_days": randi_range(GameState.RANDOM_CONTRACT_DURATION_MIN, GameState.RANDOM_CONTRACT_DURATION_MAX),
		"days_left": 0,
		"offer_days_left": GameState.RANDOM_CONTRACT_OFFER_DAYS,
		"active": false,
		"status": "idle",
	}


## Füllt die offenen befristeten Angebote auf. Gibt die Zahl neuer Angebote zurück.
static func _fill_random_contract_offers() -> int:
	var offers := 0
	for key in GameState.contracts.keys():
		var c: Dictionary = GameState.contracts[key]
		if bool(c.get("random", false)) and not bool(c.get("active", false)):
			offers += 1
	var added := 0
	# GAME-05: Mit sehr guten Bewertungen kommt eine Anfrage mehr, mit schlechten eine weniger.
	var avg := GameState.rating_avg()
	var max_offers := GameState.RANDOM_CONTRACT_MAX_OFFERS + (1 if avg >= 4.5 else 0) - (1 if avg < 2.5 else 0)
	while offers < max_offers:
		var entry := _make_random_contract()
		GameState.contracts[str(entry["id"])] = entry
		MailManager.on_new_contract(entry)
		offers += 1
		added += 1
	return added


## Tageswechsel: Laufzeiten und Annahmefristen herunterzählen, abgelaufene entfernen, neue Angebote erzeugen.
static func _advance_random_contracts() -> void:
	for key in GameState.contracts.keys():
		var c: Dictionary = GameState.contracts[key]
		if not bool(c.get("random", false)):
			continue
		if bool(c.get("active", false)):
			c["days_left"] = int(c.get("days_left", 0)) - 1
			if int(c["days_left"]) <= 0:
				GameState.contracts.erase(key)
				GameState.post_event_f("✅ Befristeter Vertrag '%s' (%s) ist erfüllt und ausgelaufen.", [str(c["title"]), str(c["client"])], "good")
				var st := Sla.stars_for(c)
				GameState.add_review(str(c["client"]), st, tr_review(st))
		else:
			c["offer_days_left"] = int(c.get("offer_days_left", 1)) - 1
			if int(c["offer_days_left"]) <= 0:
				GameState.contracts.erase(key)
	if _fill_random_contract_offers() > 0:
		GameState.post_event("📄 Neue befristete Vertragsangebote im Support-Hub.", "info")


static func _process_contract_payouts() -> void:
	var avail_ram := 0 if GameState.ddos_active else GameState.total_ram_gb
	var avail_mbps := 0.0 if GameState.ddos_active else GameState.max_bandwidth_mbps
	var net_delta := 0.0
	var contract_income := 0.0
	var penalties := 0.0
	var had_sla_breach := false

	for cid in GameState.contracts.keys():
		var c: Dictionary = GameState.contracts[cid]
		if not bool(c["active"]):
			c["status"] = "idle"
			continue
		var req_ram := int(c.get("req_ram_gb", 4))
		var req_mbps := float(c.get("req_mbps", 15.0))
		var tier := Sla.tier(c)
		if avail_ram >= req_ram and avail_mbps >= req_mbps:
			avail_ram -= req_ram
			avail_mbps -= req_mbps
			c["status"] = "ok"
			var pay := float(c["payout_per_cycle"]) * GameState.revenue_bonus_mult * float(tier["pay"]) * Cyber.income_mult() * Operations.cert_mult()
			net_delta += pay
			contract_income += pay
			Sla.record(c, true)
		else:
			c["status"] = "underpowered"
			var pen := float(c["penalty_per_cycle"]) * float(tier["penalty"])
			net_delta -= pen
			penalties += pen
			had_sla_breach = true
			Sla.record(c, false)
		# GAME-05: Fällt die Verfügbarkeit unter das Versprechen, meldet sich der Kunde (einmal, bis es besser ist).
		if Sla.is_breached(c) and not bool(c.get("sla_warned", false)):
			c["sla_warned"] = true
			GameState.post_event_f("📉 SLA %s verletzt bei %s: Verfügbarkeit %.1f %% statt %.1f %%.", [
				str(tier["name"]), str(c.get("client", "")), Sla.availability(c) * 100.0, float(tier["target"]) * 100.0], "warn")
		elif not Sla.is_breached(c) and bool(c.get("sla_warned", false)):
			c["sla_warned"] = false

	# Add Rented Rack customer payouts (scaled by live active users & satisfaction!)
	var rental_payout := 0.0
	if not GameState.ddos_active:
		for rid in GameState.racks.keys():
			var rk: Dictionary = GameState.racks[rid]
			if str(rk.get("rental_type", "none")) != "none" and bool(rk.get("powered", false)) and bool(rk.get("networked", false)):
				rental_payout += float(rk.get("rental_income", 0.0))
	net_delta += rental_payout
	# GAME-04: Investoren bekommen ihren Anteil an den Einnahmen. Alles landet im Kassenbuch.
	var cut := FinanceManager.investor_cut(contract_income + rental_payout)
	net_delta -= cut
	FinanceManager.book("contracts", contract_income)
	FinanceManager.book("rentals", rental_payout)
	FinanceManager.book("penalties", -penalties)
	FinanceManager.book("investors", -cut)

	GameState.money = maxf(0.0, GameState.money + net_delta)
	if had_sla_breach:
		GameState.post_event("SLA-Strafe! Zu wenig aktiver RAM (GB) oder Internet-Bandbreite (Mbit/s) für laufende Verträge.", "warn")


static func _update_rack_rentals_and_support(dt: float) -> void:
	var tickets_dirty := false
	var call_dirty := false
	var total_rent := 0.0
	var time_wave := 0.85 + 0.30 * sin((GameState.time_of_day - 0.25) * TAU)

	# Manage incoming phone call ringing & timeout
	GameState._call_cooldown = maxf(0.0, GameState._call_cooldown - dt)
	if not GameState.active_call.is_empty():
		GameState.active_call["timer"] = float(GameState.active_call.get("timer", 0.0)) + dt
		if str(GameState.active_call.get("state", "ringing")) == "ringing":
			GameState._phone_ring_accum += dt
			if GameState._phone_ring_accum >= 4.2:
				GameState._phone_ring_accum = 0.0
				GameState._rpc_play_sfx.rpc("phone_ring")
			if float(GameState.active_call["timer"]) >= 42.0:
				var crid := str(GameState.active_call.get("rack_id", ""))
				if GameState.racks.has(crid):
					GameState.racks[crid]["satisfaction"] = maxf(5.0, float(GameState.racks[crid].get("satisfaction", 60.0)) - 12.0)
				GameState.post_event_f("📞 Verpasster Kundenanruf von %s! Zufriedenheit gesunken.", [str(GameState.active_call.get("customer", "Kunde"))], "warn")
				GameState.active_call.clear()
				GameState._call_cooldown = 30.0
				call_dirty = true
		call_dirty = true

	var worst_call_rack := ""
	var worst_call_issue := ""
	var worst_call_sat := 999.0
	var rep_delta := 0.0
	# Freie Hardware der Cluster-Racks, einmal pro Tick ermittelt und beim Verleihen verbraucht.
	var cluster_spare := GameState._compute_cluster_spare()

	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		var services := _get_rack_services(r)
		if services.is_empty():
			r["rental_type"] = "none"
			r["rental_customer"] = ""
			r["active_users"] = 0
			r["rental_income"] = 0.0
			r["metrics"] = {}
			continue

		var rtype := str((services[0] as Dictionary)["type"])
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rtype]
		var hw := GameState.get_rack_hardware_summary(rid)
		# GAME-06: Ein verschlüsseltes Rack (Erpressungstrojaner) läuft nicht, bis es wiederhergestellt ist.
		var powered := bool(r.get("powered", false)) and not Cyber.is_encrypted(str(rid))
		var networked := bool(r.get("networked", false))
		var active_servers := int(hw["active_servers"])
		var rtemp := float(r.get("temp", 22.0))
		var sat := float(r.get("satisfaction", 100.0))
		var grace := maxf(0.0, float(r.get("grace_timer", 0.0)) - dt)
		r["grace_timer"] = grace

		# Kunden kommen nach und nach: Jeder Dienst startet mit wenigen Nutzern und wächst je nach Ruf.
		var online := powered and networked and active_servers > 0
		# Auslastung aus dem letzten Tick bremst das Wachstum, bevor die Hardware an ihre Grenze kommt.
		var prev_m: Dictionary = r["metrics"] if r.get("metrics") is Dictionary else {}
		var prev_load := maxf(
			maxf(float(prev_m.get("ram_pct", 0.0)), float(prev_m.get("cpu_pct", 0.0))),
			maxf(maxf(float(prev_m.get("gpu_pct", 0.0)), float(prev_m.get("storage_pct", 0.0))), float(prev_m.get("net_pct", 0.0)))
		)
		var users_int := 0
		for svc in services:
			users_int += _update_service_users(svc as Dictionary, sat, online, dt, time_wave, prev_load)
		users_int = maxi(1, users_int)
		_sync_rack_rental_fields(r)
		r["active_users"] = users_int
		# Ressourcenbedarf und Preis pro Nutzer: Mittel aller Dienste, gewichtet nach Nutzerzahl.
		prof = _blend_service_profiles(services)

		# Cluster-Kabel: Reicht die eigene Hardware nicht, leiht sich das Rack freie Kapazität der verbundenen Racks.
		var cluster_borrowed: Dictionary = {}
		if active_servers > 0:
			hw = hw.duplicate()
			cluster_borrowed = GameState._borrow_cluster_capacity(str(rid), hw, users_int, prof, cluster_spare)

		# Calculate live per-resource utilization % so player can self-assess RAM/CPU/GPU/Storage/Router!
		var ram_total := maxf(0.5, float(hw["ram_gb"]))
		var ram_used := float(users_int) * float(prof["ram_gb_per_user"])
		var ram_pct := (ram_used / ram_total) * 100.0 if active_servers > 0 else 100.0

		var cpu_total := maxf(1.0, float(hw["cpu_score"]))
		var cpu_used := float(users_int) * float(prof["cpu_per_user"])
		var cpu_pct := (cpu_used / cpu_total) * 100.0 if active_servers > 0 else 100.0

		var gpu_pct := 0.0
		if float(prof["gpu_per_user"]) > 0.001:
			var gpu_total := maxf(1.0, float(hw["gpu_score"]))
			gpu_pct = ((float(users_int) * float(prof["gpu_per_user"])) / gpu_total) * 100.0 if active_servers > 0 else 100.0

		var sto_total := maxf(0.1, float(hw["storage_tb"]))
		var sto_used := float(users_int) * float(prof["storage_tb_per_user"])
		var sto_pct := (sto_used / sto_total) * 100.0 if active_servers > 0 else 100.0

		var net_need_mbps := float(users_int) * float(prof.get("mbps_per_user", 0.5))
		var net_pct := (net_need_mbps / maxf(1.0, GameState.max_bandwidth_mbps)) * 100.0
		if GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps:
			net_pct = maxf(net_pct, (GameState.used_bandwidth_mbps / maxf(1.0, GameState.max_bandwidth_mbps)) * 100.0)
		# GAME-03: Eine überlastete LAN-Kette bremst alle ihre Racks im gleichen Verhältnis.
		var chain_ratio := 1.0
		var chain_root := str(GameState.lan_chain_of.get(rid, ""))
		if chain_root != "":
			var chain_load := float(GameState.lan_chain_mbps.get(chain_root, 0.0))
			var chain_cap := GameState.lan_chain_cap()
			if chain_load > chain_cap:
				chain_ratio = chain_cap / chain_load
				net_pct = maxf(net_pct, chain_load / chain_cap * 100.0)

		var bottleneck := "ok"
		var peak_load := maxf(maxf(ram_pct, cpu_pct), maxf(maxf(gpu_pct, sto_pct), net_pct))
		if not powered or not networked or active_servers == 0:
			bottleneck = "offline"
		elif GameState._rack_has_fire(r):
			bottleneck = "overheat"
		elif bool(hw["psu_overloaded"]):
			bottleneck = "psu"
		elif rtemp >= 74.0:
			bottleneck = "overheat"
		elif peak_load >= 92.0:
			if ram_pct >= cpu_pct and ram_pct >= gpu_pct and ram_pct >= sto_pct and ram_pct >= net_pct:
				bottleneck = "ram"
			elif cpu_pct >= gpu_pct and cpu_pct >= sto_pct and cpu_pct >= net_pct:
				bottleneck = "cpu"
			elif gpu_pct >= sto_pct and gpu_pct >= net_pct:
				bottleneck = "gpu"
			elif sto_pct >= net_pct:
				bottleneck = "storage"
			else:
				bottleneck = "network"

		r["metrics"] = {
			"ram_used_gb": ram_used,
			"ram_total_gb": float(hw["ram_gb"]),
			"ram_pct": ram_pct,
			"cpu_pct": cpu_pct,
			"gpu_pct": gpu_pct,
			"storage_used_tb": sto_used,
			"storage_total_tb": float(hw["storage_tb"]),
			"storage_pct": sto_pct,
			"net_used_mbps": net_need_mbps,
			"net_pct": net_pct,
			"bottleneck": bottleneck,
			"cluster_borrowed": cluster_borrowed,
			"lan_throttle": chain_ratio,
		}

		# Satisfaction dynamics
		if bottleneck == "ok" and not GameState.ddos_active:
			sat = minf(100.0, sat + 1.4 * dt)
		elif grace <= 0.0:
			var penalty_rate := 2.4 if bottleneck == "offline" else (1.9 if peak_load >= 115.0 else 1.15)
			sat = maxf(0.0, sat - penalty_rate * dt)
		r["satisfaction"] = sat

		var income := 0.0
		if powered and networked and active_servers > 0 and not GameState.ddos_active:
			var sat_mult := clampf(sat / 100.0, 0.25, 1.15)
			income = float(users_int) * float(prof["pay_per_user"]) * sat_mult * GameState.revenue_bonus_mult * chain_ratio * Cyber.income_mult() * Operations.cert_mult()
		r["rental_income"] = income
		total_rent += income
		# Zufriedene Kunden empfehlen dich weiter, unzufriedene schaden dem Ruf.
		rep_delta += (sat - 60.0) / 100.0 * 0.05 * dt * sqrt(float(services.size()))

		# Auto-generate specific Customer Support Ticket on persistent bottleneck!
		if bottleneck != "ok" and not _has_open_ticket_for_rack(rid):
			if bottleneck == "offline" or sat < 86.0 or peak_load >= 96.0:
				_create_support_ticket(rid, r, bottleneck)
				tickets_dirty = true

		# Track most critical rack for an incoming VoIP Phone Call at the PC!
		if bottleneck != "ok" and grace <= 0.0 and (sat < 68.0 or bottleneck == "offline" or peak_load >= 112.0):
			if sat < worst_call_sat:
				worst_call_sat = sat
				worst_call_rack = rid
				worst_call_issue = bottleneck

		# If customer satisfaction collapses completely, customer cancels rental!
		if sat <= 5.0:
			var cname := str(r.get("rental_customer", "Kunde"))
			GameState.add_review(cname, 1, tr_review(1))
			r["rental_type"] = "none"
			r["rental_customer"] = ""
			r["active_users"] = 0
			r["satisfaction"] = 100.0
			r["rental_income"] = 0.0
			services.clear()
			GameState.reputation = maxf(0.0, GameState.reputation - 8.0)
			_clear_tickets_for_rack(rid)
			tickets_dirty = true
			GameState.post_event_f("❌ %s hat %s gekündigt (dauerhafte Überlastung)! Hardware aufrüsten & neu vermieten.", [cname, GameState.get_rack_display_name(rid)], "alert")
			MailManager.on_cancelled(cname, GameState.get_rack_display_name(rid))
			GameState._rpc_play_sfx.rpc("alarm")

	GameState.reputation = clampf(GameState.reputation + rep_delta, 0.0, 100.0)
	var rep_tier := get_reputation_tier()
	if rep_tier != GameState._last_rep_tier:
		if GameState._last_rep_tier >= 0:
			if rep_tier > GameState._last_rep_tier:
				GameState.post_event_f("⭐ Dein Ruf steigt: %s! Neue Kunden kommen schneller und zahlreicher.", [get_reputation_label()], "good")
			else:
				GameState.post_event_f("📉 Dein Ruf sinkt: %s. Es kommen weniger neue Kunden.", [get_reputation_label()], "warn")
		GameState._last_rep_tier = rep_tier

	GameState.total_rental_income_per_cycle = total_rent

	# Trigger Live Customer Phone Call at PC if a rack is critically impacted!
	if GameState.active_call.is_empty() and GameState._call_cooldown <= 0.0 and worst_call_rack != "":
		var cr: Dictionary = GameState.racks[worst_call_rack]
		var cname := str(cr.get("rental_customer", "Kunde"))
		var rtype := str(cr.get("rental_type", "web"))
		var call_msg := _describe_issue_call(worst_call_rack, cr, worst_call_issue)
		GameState.active_call = {
			"id": "call_%d" % GameState._next_ticket_num,
			"rack_id": worst_call_rack,
			"customer": cname,
			"rental_type": rtype,
			"issue_key": worst_call_issue,
			"message": str(call_msg["text"]),
			"message_args": call_msg["args"],
			"state": "ringing",
			"timer": 0.0,
		}
		GameState._next_ticket_num += 1
		GameState._phone_ring_accum = 0.0
		GameState._rpc_play_sfx.rpc("phone_ring")
		GameState.post_event_f("📞 EINGEHENDER ANRUF AM PC: %s beschwert sich über %s! Zum PC [E] gehen!", [cname, worst_call_rack.to_upper()], "alert")
		call_dirty = true

	# Tickets altern lassen. Unbeantwortete Tickets eskalieren nach Ablauf der SLA-Frist.
	for tid in GameState.support_tickets.keys():
		var t: Dictionary = GameState.support_tickets[tid]
		t["age"] = float(t.get("age", 0.0)) + dt
		if bool(t.get("reassured", false)) or bool(t.get("escalated", false)):
			continue
		if float(t["age"]) < get_ticket_sla(t):
			continue
		t["escalated"] = true
		var erid := str(t.get("rack_id", ""))
		if GameState.racks.has(erid):
			GameState.racks[erid]["satisfaction"] = maxf(0.0, float(GameState.racks[erid].get("satisfaction", 60.0)) - GameState.TICKET_ESCALATION_SAT_PENALTY)
		GameState.reputation = maxf(0.0, GameState.reputation - GameState.TICKET_ESCALATION_REP_PENALTY)
		tickets_dirty = true
		GameState._rpc_play_sfx.rpc("alarm")
		GameState.post_event_f("⏰ Ticket %s eskaliert: %s wartet zu lange auf eine Antwort (-%d%% Zufriedenheit).", [str(tid), str(t.get("customer", "Kunde")), int(GameState.TICKET_ESCALATION_SAT_PENALTY)], "alert")

	if tickets_dirty:
		GameState._broadcast_tickets()
	if call_dirty:
		GameState._broadcast_call()


## Aktive Dienste eines Racks. Ungültige Einträge (unbekannte Dienste, "none") werden entfernt.
static func _get_rack_services(r: Dictionary) -> Array:
	if not (r.get("services") is Array):
		r["services"] = []
	var arr: Array = r["services"]
	for i in range(arr.size() - 1, -1, -1):
		var e: Variant = arr[i]
		if not (e is Dictionary):
			arr.remove_at(i)
			continue
		var t := str((e as Dictionary).get("type", ""))
		if t == "none" or not HardwareCatalog.RENTAL_PROFILES.has(t):
			arr.remove_at(i)
	return arr


static func _find_service(services: Array, service_type: String) -> int:
	for i in range(services.size()):
		if str((services[i] as Dictionary).get("type", "")) == service_type:
			return i
	return -1


## Hält die alten Einzelfelder (rental_type, rental_customer) passend zur Dienstliste.
## Tickets, Anrufe, Terminal und Rack-Schild lesen weiter diese Felder.
static func _sync_rack_rental_fields(r: Dictionary) -> void:
	var services: Array = r.get("services", [])
	if services.is_empty():
		r["rental_type"] = "none"
		r["rental_customer"] = ""
		r["active_users"] = 0
		r["rental_income"] = 0.0
		r["satisfaction"] = 100.0
		r["grace_timer"] = 0.0
		return
	var first: Dictionary = services[0]
	r["rental_type"] = str(first.get("type", "none"))
	var cname := str(first.get("customer", ""))
	if services.size() > 1:
		cname += " +%d" % (services.size() - 1)
	r["rental_customer"] = cname
	var total := 0
	for s in services:
		total += int(roundf(float((s as Dictionary).get("users", 0.0))))
	r["active_users"] = total


static func get_reputation_factor() -> float:
	return clampf(GameState.reputation / 100.0, 0.0, 1.0)


static func get_reputation_tier() -> int:
	var tier := 0
	for th in GameState.REPUTATION_THRESHOLDS:
		if GameState.reputation >= th:
			tier += 1
	return tier


static func get_reputation_label() -> String:
	return GameState.REPUTATION_LABELS[get_reputation_tier()]


## Startnutzer eines neuen Dienstes: bei schlechtem Ruf nur eine Handvoll.
static func _start_users_for(service_type: String) -> float:
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[service_type]
	return maxf(1.0, roundf(float(p.get("base_users", 1)) * (0.15 + 0.35 * get_reputation_factor())))


## Nutzerzahl eines Dienstes fortschreiben. Gibt die gerundete Nutzerzahl zurück.
static func _update_service_users(svc: Dictionary, sat: float, online: bool, dt: float, time_wave: float, load_pct: float = 0.0) -> int:
	var st := str(svc.get("type", ""))
	if not HardwareCatalog.RENTAL_PROFILES.has(st):
		return 0
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[st]
	var base := float(p.get("base_users", 1))
	var prev := float(svc.get("users", base))
	var cur := prev
	if not online:
		cur = maxf(base * 0.2, cur - 4.5 * dt)
	elif sat >= 72.0:
		if load_pct < GameState.USER_GROWTH_LOAD_LIMIT:
			var headroom := clampf((GameState.USER_GROWTH_LOAD_LIMIT - load_pct) / GameState.USER_GROWTH_SOFT_RANGE, 0.0, 1.0)
			var growth := float(p.get("growth_rate", 1.0)) * time_wave * (0.35 + 0.65 * get_reputation_factor()) * MarketManager.growth_factor_cached(st)
			cur += growth * headroom * dt * 0.36
		elif load_pct >= GameState.USER_SHED_LOAD_LIMIT:
			# Hardware voll ausgelastet: ein Teil der Kunden wandert langsam ab.
			cur = maxf(base, cur - 1.0 * dt)
	elif sat < 45.0:
		cur = maxf(base * 0.25, cur - 2.2 * dt)
	# Zu hohe Preise vertreiben mit der Zeit Kunden.
	var shed := MarketManager.price_shed(st) * dt
	if shed > 0.0:
		cur = maxf(minf(cur, base * 0.5), cur - shed)
	svc["users"] = cur
	if dt > 0.0:
		var per_min := (cur - prev) / dt * 60.0
		svc["trend"] = lerpf(float(svc.get("trend", 0.0)), per_min, clampf(dt * 0.5, 0.0, 1.0))
	return maxi(0, int(roundf(cur)))


## Ein gemeinsames Profil für alle Dienste eines Racks, gewichtet nach Nutzerzahl.
static func _blend_service_profiles(services: Array) -> Dictionary:
	var first_type := str((services[0] as Dictionary).get("type", ""))
	var out: Dictionary = (HardwareCatalog.RENTAL_PROFILES[first_type] as Dictionary).duplicate(true)
	if services.size() == 1:
		out["pay_per_user"] = float(out.get("pay_per_user", 0.0)) * MarketManager.get_price(first_type)
		return out
	var sums := {}
	for k in GameState._BLEND_KEYS:
		sums[k] = 0.0
	var total_w := 0.0
	var base_sum := 0.0
	var max_sum := 0.0
	var growth_sum := 0.0
	for s in services:
		var sd: Dictionary = s
		var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[str(sd["type"])]
		var w := maxf(1.0, float(sd.get("users", 1.0)))
		total_w += w
		for k in GameState._BLEND_KEYS:
			var fallback := 0.5 if k == "mbps_per_user" else 0.0
			var price_f := MarketManager.get_price(str(sd["type"])) if k == "pay_per_user" else 1.0
			sums[k] = float(sums[k]) + w * float(p.get(k, fallback)) * price_f
		base_sum += float(p.get("base_users", 0))
		max_sum += float(p.get("max_users", 0))
		growth_sum += float(p.get("growth_rate", 0.0))
	for k in GameState._BLEND_KEYS:
		out[k] = float(sums[k]) / total_w
	out["base_users"] = int(base_sum)
	out["max_users"] = int(max_sum)
	out["growth_rate"] = growth_sum
	return out


static func _has_open_ticket_for_rack(rack_id: String) -> bool:
	for tid in GameState.support_tickets.keys():
		if str(GameState.support_tickets[tid].get("rack_id", "")) == rack_id:
			return true
	return false


static func _clear_tickets_for_rack(rack_id: String) -> void:
	var del_ids: Array[String] = []
	for tid in GameState.support_tickets.keys():
		if str(GameState.support_tickets[tid].get("rack_id", "")) == rack_id:
			del_ids.append(str(tid))
	for tid in del_ids:
		GameState.support_tickets.erase(tid)


static func _create_support_ticket(rack_id: String, rack: Dictionary, issue_key: String) -> void:
	var tid := "T-%d" % GameState._next_ticket_num
	GameState._next_ticket_num += 1
	var cname := str(rack.get("rental_customer", "Kunde"))
	var rtype := str(rack.get("rental_type", "web"))
	var users := int(rack.get("active_users", 0))
	var m: Dictionary = rack.get("metrics", {})
	var rid_up := GameState.get_rack_display_name(rack_id)
	# Titel und Text bleiben Vorlagen mit Werten. Übersetzt wird erst beim
	# Empfänger, damit jeder Spieler sie in seiner eigenen Sprache sieht.
	var title := ""
	var title_args: Array = []
	var msg := ""
	var msg_args: Array = []
	var prio := "HOCH"
	match issue_key:
		"ram":
			title = "Arbeitsspeicher (RAM) voll!"
			msg = "Hallo Support, bei unseren %d aktiven Nutzern läuft der RAM auf %s über (%.1f / %.0f GB)! Dienste stürzen ab — bitte mehr/schnelleren RAM (DDR3/DDR4/DDR5) einbauen!"
			msg_args = [users, rid_up, float(m.get("ram_used_gb", 0.0)), float(m.get("ram_total_gb", 0.0))]
		"cpu":
			title = "CPU-Auslastung bei %.0f%%!"
			title_args = [float(m.get("cpu_pct", 100.0))]
			msg = "Unsere %d aktiven User klagen über extreme Lags auf %s! Der Prozessor ist komplett am Limit — wir brauchen dringend stärkere CPUs oder einen weiteren Server!"
			msg_args = [users, rid_up]
		"gpu":
			title = "GPU-Leistung reicht nicht aus!"
			msg = "Bei %d aktiven Nutzern hängen unsere GPU-Jobs auf %s (%.0f%% Last). Bitte bessere Grafikkarten verbauen!"
			msg_args = [users, rid_up, float(m.get("gpu_pct", 100.0))]
		"storage":
			title = "Festplatten-Speicher fast voll!"
			msg = "Warnung: Unsere %d Nutzer belegen bereits %.1f / %.1f TB auf %s! Uploads schlagen fehl — bitte größere HDD/SSD/NVMe einbauen!"
			msg_args = [users, float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0)), rid_up]
		"network":
			title = "Internet-Leitung zu langsam!"
			msg = "Hoher Ping & Paketverlust bei %d aktiven Usern! Dein Router drosselt %s — bitte Internet-Router upgraden!"
			msg_args = [users, rid_up]
		"overheat":
			prio = "KRITISCH"
			title = "Kritische Rack-Temperatur (%.0f°C)!"
			title_args = [float(rack.get("temp", 75.0))]
			msg = "Thermal Throttling auf %s! Bitte sofort Server-Kühlung verbessern oder Klimaanlage anschließen!"
			msg_args = [rid_up]
		"psu":
			prio = "KRITISCH"
			title = "Netzteil-Überlastung erkannt!"
			msg = "Spannungsabfälle auf %s — ein verbautes Netzteil ist zu schwach für die Komponenten! Bitte stärkeres Netzteil (PSU) einbauen."
			msg_args = [rid_up]
		_:
			prio = "KRITISCH"
			title = "Komplettausfall — Server offline!"
			msg = "NOTFALL: Unser gemietetes %s ist komplett unerreichbar! Bitte sofort Stromkabel, Netzwerkkabel & Server-Zustand prüfen!"
			msg_args = [rid_up]

	GameState.support_tickets[tid] = {
		"id": tid,
		"rack_id": rack_id,
		"customer": cname,
		"rental_type": rtype,
		"issue_key": issue_key,
		"title": title,
		"title_args": title_args,
		"message": msg,
		"message_args": msg_args,
		"priority": prio,
		"created_day": GameState.day_number,
		"age": 0.0,
		"reassured": false,
		"compensated": false,
		"escalated": false,
	}
	GameState._rpc_play_sfx.rpc("ticket_notify")
	GameState.post_event_f("🎧 Neues Support-Ticket %s von %s: %s", [tid, cname, {"text": title, "args": title_args}], "warn")
	MailManager.on_ticket(GameState.support_tickets[tid])


## Antwortfrist eines Tickets in Sekunden (nach Priorität).
static func get_ticket_sla(ticket: Dictionary) -> float:
	return float(GameState.TICKET_SLA_SECONDS.get(str(ticket.get("priority", "HOCH")), GameState.TICKET_DEFAULT_SLA))


## Restzeit bis zur Eskalation. 0 bei beantworteten oder bereits eskalierten Tickets.
static func get_ticket_sla_remaining(ticket: Dictionary) -> float:
	if bool(ticket.get("reassured", false)) or bool(ticket.get("escalated", false)):
		return 0.0
	return maxf(0.0, get_ticket_sla(ticket) - float(ticket.get("age", 0.0)))


## Liefert den Anruftext als Vorlage plus Werte ({text, args}).
static func _describe_issue_call(rack_id: String, rack: Dictionary, issue_key: String) -> Dictionary:
	var users := int(rack.get("active_users", 0))
	var m: Dictionary = rack.get("metrics", {})
	var who := str(rack.get("rental_customer", ""))
	var rid_up := GameState.get_rack_display_name(rack_id)
	match issue_key:
		"ram":
			return {"text": "„Hallo?! Hier ist %s! Bei %d aktiven Usern ist der RAM auf %s zu %.0f%% voll — unsere Kunden fliegen ständig raus! Wann baut ihr mehr RAM ein?“",
				"args": [who, users, rid_up, float(m.get("ram_pct", 100.0))]}
		"cpu":
			return {"text": "„Dringend! Hier %s — die CPU auf %s hängt bei %.0f%% Last mit %d Usern, alles laggt unerträglich! Macht bitte sofort ein CPU-Upgrade!“",
				"args": [who, rid_up, float(m.get("cpu_pct", 100.0)), users]}
		"gpu":
			return {"text": "„Hier %s! Unsere KI/Video-Aufträge auf %s stehen still, die GPU ist restlos überlastet (%.0f%%)! Wir brauchen dringend dickere Grafikkarten!“",
				"args": [who, rid_up, float(m.get("gpu_pct", 100.0))]}
		"storage":
			return {"text": "„Hallo Support, %s hier! Der Speicher auf %s ist komplett voll (%.1f / %.1f TB) — unsere Kunden können nichts mehr hochladen!“",
				"args": [who, rid_up, float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0))]}
		"network":
			return {"text": "„%s am Apparat! Euer alter Router bremst unser ganzes %s aus — Ping über 400 ms bei %d Usern! Wann gibt's schnelleres Internet?“",
				"args": [who, rid_up, users]}
		"overheat":
			return {"text": "„ALARM! Hier %s — euer Monitoring meldet %.0f°C auf %s! Wenn die Server gleich abbrennen, kündigen wir sofort!“",
				"args": [who, float(rack.get("temp", 80.0)), rid_up]}
		"psu":
			return {"text": "„%s hier! Auf %s brechen ständig die Netzteile ein — bitte baut stärkere PSUs ein, bevor uns Daten verloren gehen!“",
				"args": [who, rid_up]}
		_:
			return {"text": "„NOTFALL! Hier ist %s — unser gemietetes %s ist KOMPLETT OFFLINE! Prüft sofort Strom, LAN-Kabel und Server!“",
				"args": [who, rid_up]}


static func _rpc_req_set_rack_rental(rack_id: String, rental_type: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	var peer_id := GameState._get_sender_id()
	if GameState._deny_build(peer_id, "business"):
		return
	if not GameState.racks.has(rack_id) or not HardwareCatalog.RENTAL_PROFILES.has(rental_type):
		return
	var r: Dictionary = GameState.racks[rack_id]
	var services := _get_rack_services(r)
	var pname := str(NetworkManager.get_player_name(peer_id))

	# "none" beendet alle Dienste. Jeder andere Dienst wird an- oder ausgeschaltet,
	# so kann ein Rack mehrere Dienste gleichzeitig vermieten.
	if rental_type == "none":
		if services.is_empty():
			return
		services.clear()
		GameState.post_event_f("%s beendete alle Vermietungen von %s.", [pname, GameState.get_rack_display_name(rack_id)], "info")
	else:
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rental_type]
		var idx := _find_service(services, rental_type)
		if idx >= 0:
			var gone: Dictionary = services[idx]
			services.remove_at(idx)
			GameState.post_event_f("%s beendete %s (%s) auf %s.", [pname, str(prof["short"]), str(gone.get("customer", "")), GameState.get_rack_display_name(rack_id)], "info")
		else:
			if services.size() >= GameState.MAX_SERVICES_PER_RACK:
				GameState._rpc_play_sfx.rpc_id(peer_id, "error")
				GameState.post_event_f("%s hat schon %d Dienste. Beende erst einen, bevor du einen neuen startest.", [GameState.get_rack_display_name(rack_id), GameState.MAX_SERVICES_PER_RACK], "warn")
				return
			var cname := HardwareCatalog.pick_customer_name(rental_type, GameState._next_entity_num + GameState.racks.size() + GameState.day_number + services.size())
			var start_users := _start_users_for(rental_type)
			services.append({"type": rental_type, "customer": cname, "users": start_users, "trend": 0.0})
			if services.size() == 1:
				r["satisfaction"] = 95.0
				r["grace_timer"] = 18.0
			else:
				r["grace_timer"] = maxf(float(r.get("grace_timer", 0.0)), 10.0)
			GameState.post_event_f("🤝 %s vermietet %s als %s an %s (%d Start-User, Ruf: %s)!", [
				pname, GameState.get_rack_display_name(rack_id), str(prof["short"]), cname, int(start_users), get_reputation_label()
			], "good")

	_sync_rack_rental_fields(r)
	_clear_tickets_for_rack(rack_id)
	if not GameState.active_call.is_empty() and str(GameState.active_call.get("rack_id", "")) == rack_id:
		GameState.active_call.clear()
		GameState._broadcast_call()
	GameState._rpc_play_sfx.rpc("cash")
	GameState._broadcast_racks()
	GameState._broadcast_tickets()
	GameState._broadcast_sim_tick()


static func _rpc_req_reply_ticket(ticket_id: String, action: String) -> void:
	if not GameState.multiplayer.is_server():
		return
	do_reply_ticket(ticket_id, action, GameState._get_sender_id())


static func do_reply_ticket(ticket_id: String, action: String, peer_id: int) -> void:
	if not GameState.support_tickets.has(ticket_id):
		return
	var t: Dictionary = GameState.support_tickets[ticket_id]
	var rid := str(t.get("rack_id", ""))

	match action:
		"reassure":
			if bool(t.get("reassured", false)):
				return
			t["reassured"] = true
			if GameState.racks.has(rid):
				GameState.racks[rid]["satisfaction"] = minf(100.0, float(GameState.racks[rid].get("satisfaction", 70.0)) + 12.0)
				GameState.racks[rid]["grace_timer"] = maxf(float(GameState.racks[rid].get("grace_timer", 0.0)), 45.0)
			GameState._rpc_play_sfx.rpc("ticket_notify")
			GameState.post_event_f("⌨ %s antwortete auf Ticket %s — Kunde beruhigt (+45s Zeit zum Aufrüsten).", [NetworkManager.get_player_name(peer_id), ticket_id], "info")
		"compensate":
			if bool(t.get("compensated", false)) or GameState.money < 60.0:
				GameState._rpc_play_sfx.rpc_id(peer_id, "error")
				return
			GameState.money -= 60.0
			t["compensated"] = true
			if GameState.racks.has(rid):
				GameState.racks[rid]["satisfaction"] = minf(100.0, float(GameState.racks[rid].get("satisfaction", 60.0)) + 24.0)
				GameState.racks[rid]["grace_timer"] = maxf(float(GameState.racks[rid].get("grace_timer", 0.0)), 75.0)
			GameState._rpc_play_sfx.rpc("cash")
			GameState.post_event_f("💰 %s gewährte $60 Rabatt für Ticket %s (+24%% Zufriedenheit).", [NetworkManager.get_player_name(peer_id), ticket_id], "good")
		"resolve":
			if not is_ticket_issue_fixed(t):
				GameState._rpc_play_sfx.rpc_id(peer_id, "error")
				GameState.post_event_f("Problem bei %s besteht noch! Erst Hardware/Kabel/Router beheben.", [GameState.get_rack_display_name(rid)], "warn")
				return
			var cname := str(t.get("customer", "Kunde"))
			GameState.support_tickets.erase(ticket_id)
			if GameState.racks.has(rid):
				GameState.racks[rid]["satisfaction"] = minf(100.0, float(GameState.racks[rid].get("satisfaction", 80.0)) + 16.0)
			GameState.money += 35.0
			GameState._rpc_play_sfx.rpc("cash")
			GameState.post_event_f("✅ Ticket %s von %s gelöst! (+$35 Support-Bonus & +16%% Zufriedenheit)", [ticket_id, cname], "good")

	GameState._broadcast_tickets()
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()


static func _rpc_req_answer_call() -> void:
	if not GameState.multiplayer.is_server() or GameState.active_call.is_empty():
		return
	if str(GameState.active_call.get("state", "")) != "ringing":
		return
	GameState.active_call["state"] = "answered"
	GameState.active_call["timer"] = 0.0
	GameState._rpc_play_sfx.rpc("phone_pickup")
	GameState._broadcast_call()


static func _rpc_req_resolve_call(choice: String) -> void:
	if not GameState.multiplayer.is_server() or GameState.active_call.is_empty():
		return
	var peer_id := GameState._get_sender_id()
	var rid := str(GameState.active_call.get("rack_id", ""))
	var cname := str(GameState.active_call.get("customer", "Kunde"))
	match choice:
		"upgrade_promise":
			if GameState.racks.has(rid):
				GameState.racks[rid]["satisfaction"] = minf(100.0, float(GameState.racks[rid].get("satisfaction", 60.0)) + 14.0)
				GameState.racks[rid]["grace_timer"] = maxf(float(GameState.racks[rid].get("grace_timer", 0.0)), 60.0)
			GameState.post_event_f("📞 %s versprach %s sofortiges Upgrade (+60s Schonfrist).", [NetworkManager.get_player_name(peer_id), cname], "good")
		"restart_compensate":
			if GameState.money >= 60.0:
				GameState.money -= 60.0
				if GameState.racks.has(rid):
					GameState.racks[rid]["satisfaction"] = minf(100.0, float(GameState.racks[rid].get("satisfaction", 60.0)) + 26.0)
					GameState.racks[rid]["grace_timer"] = maxf(float(GameState.racks[rid].get("grace_timer", 0.0)), 80.0)
				GameState.post_event_f("📞 %s gab %s $60 Gutschrift am Telefon (+26%% Zufriedenheit).", [NetworkManager.get_player_name(peer_id), cname], "good")
			else:
				GameState._rpc_play_sfx.rpc_id(peer_id, "error")
				return
		_:
			if GameState.racks.has(rid):
				GameState.racks[rid]["grace_timer"] = maxf(float(GameState.racks[rid].get("grace_timer", 0.0)), 20.0)
			GameState.post_event_f("📞 Anruf von %s beendet.", [cname], "info")

	GameState.active_call.clear()
	GameState._call_cooldown = 38.0
	GameState._rpc_play_sfx.rpc("phone_hangup")
	GameState._broadcast_call()
	GameState._broadcast_sim_tick()


static func _rpc_req_toggle_contract(contract_id: String, sla: String = "bronze") -> void:
	if not GameState.multiplayer.is_server():
		return
	if GameState._deny_build(GameState._get_sender_id(), "business"):
		return
	do_toggle_contract(contract_id, GameState._get_sender_id(), sla)


static func do_toggle_contract(contract_id: String, peer_id: int, sla: String = "bronze") -> void:
	if not GameState.contracts.has(contract_id):
		return
	var c: Dictionary = GameState.contracts[contract_id]
	var now_active := not bool(c["active"])
	if now_active and (get_active_contract_count() >= get_max_contracts_limit() or MarketManager.is_contract_taken(c)):
		GameState._rpc_play_sfx.rpc_id(peer_id, "error")
		return
	# GAME-05: SLA-Stufe beim Annehmen. Silber und Gold gibt es erst mit guten Bewertungen.
	if now_active:
		var tier := sla if Sla.TIERS.has(sla) else "bronze"
		var need := float(Sla.TIERS[tier]["min_stars"])
		if GameState.rating_avg() < need:
			GameState.tell_peer(peer_id, "SLA %s gibt es erst ab %s Sternen im Schnitt.", [str(Sla.TIERS[tier]["name"]), String.num(need, 1)], "warn")
			GameState._rpc_play_sfx.rpc_id(peer_id, "error")
			return
		c["sla"] = tier
		c["sla_ok"] = 0.0
		c["sla_n"] = 0.0
		c["sla_warned"] = false
	elif float(c.get("sla_n", 0.0)) >= 3.0:
		# Vorzeitig gekündigt: Der Kunde ist höchstens mäßig zufrieden.
		GameState.add_review(str(c.get("client", "Kunde")), mini(Sla.stars_for(c), 3) if bool(c.get("random", false)) else mini(Sla.stars_for(c), 4),
			tr_review(2 if bool(c.get("random", false)) else 3))
	if now_active and str(c.get("bid_rival", "")) != "":
		# Gegengebot: Der Kunde bleibt, zahlt aber etwas weniger.
		c["payout_orig"] = int(c["payout_per_cycle"])
		c["payout_per_cycle"] = MarketManager.contract_payout(c)
	elif not now_active and c.has("payout_orig"):
		c["payout_per_cycle"] = int(c["payout_orig"])
		c.erase("payout_orig")
	MarketManager.clear_bid(c)
	c["active"] = now_active
	c["status"] = "ok" if now_active else "idle"
	if bool(c.get("random", false)):
		if now_active:
			c["days_left"] = int(c.get("duration_days", GameState.RANDOM_CONTRACT_DURATION_MIN))
		else:
			# Ein gekündigter befristeter Vertrag ist weg und kann nicht neu angenommen werden.
			GameState.contracts.erase(contract_id)
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_sim_tick()
	GameState._rpc_play_sfx.rpc("click")
	GameState.post_event_f("%s hat Vertrag '%s' angenommen." if now_active else "%s hat Vertrag '%s' gekündigt.", [
		NetworkManager.get_player_name(peer_id), str(c["title"]),
	], "good" if now_active else "info")


static func _roll_team_order() -> void:
	if not GameState.multiplayer.is_server():
		return
	var active_slots := 0
	for rk in GameState.racks.values():
		for sl in (rk as Dictionary).get("slots", []):
			if not str((sl as Dictionary).get("item_type", "")).is_empty():
				active_slots += 1
	var pick := GameState.day_number % 3
	if pick == 0:
		GameState.active_team_order = {
			"kind": "uptime_streak",
			"title": "Team-Auftrag: 90 Sek. störungsfreier Betrieb",
			"progress": 0.0,
			"target": 90.0,
			"reward": 850 + GameState.day_number * 220,
			"done": false,
		}
	elif pick == 1:
		var goal_slots := maxi(2, active_slots + 2)
		GameState.active_team_order = {
			"kind": "expand_slots",
			"title": "Team-Auftrag: %d aktive Server-Einschübe betreiben" % goal_slots,
			"progress": float(active_slots),
			"target": float(goal_slots),
			"reward": 1100 + GameState.day_number * 260,
			"done": false,
		}
	else:
		GameState.active_team_order = {
			"kind": "cool_ops",
			"title": "Team-Auftrag: 75 Sek. unter 50 °C Raumtemperatur",
			"progress": 0.0,
			"target": 75.0,
			"reward": 950 + GameState.day_number * 240,
			"done": false,
		}


static func _tick_team_order(dt: float) -> void:
	if not GameState.multiplayer.is_server() or GameState.active_team_order.is_empty() or bool(GameState.active_team_order.get("done", false)):
		return
	var kind := str(GameState.active_team_order.get("kind", ""))
	var target := float(GameState.active_team_order.get("target", 90.0))
	var prog := float(GameState.active_team_order.get("progress", 0.0))
	if kind == "uptime_streak":
		if (GameState.breaker_on or GameState.ups_backup_active) and not GameState.has_any_fire() and not GameState.ddos_active and GameState.racks.size() >= 1:
			prog += dt
	elif kind == "cool_ops":
		if (GameState.breaker_on or GameState.ups_backup_active) and GameState.room_temp < 50.0 and GameState.racks.size() >= 1:
			prog += dt
	elif kind == "expand_slots":
		var running := 0
		for rk in GameState.racks.values():
			if bool((rk as Dictionary).get("powered", false)):
				for sl in (rk as Dictionary).get("slots", []):
					if not str((sl as Dictionary).get("item_type", "")).is_empty() and str((sl as Dictionary).get("state", "")) == "ok":
						running += 1
		prog = float(running)
	GameState.active_team_order["progress"] = minf(prog, target)
	if prog >= target:
		GameState.active_team_order["done"] = true
		var rew := int(GameState.active_team_order.get("reward", 1000))
		GameState.money += float(rew)
		GameState.reputation = clampf(GameState.reputation + 2.5, 0.0, 100.0)
		GameState._rpc_play_sfx.rpc("cash")
		GameState.post_event_f("🤝 %s abgeschlossen! Team-Bonus: +$%d!", [str(GameState.active_team_order["title"]), rew], "good")
