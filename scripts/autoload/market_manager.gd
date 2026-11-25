extends Node
## Markt und Konkurrenz: fünf vom Computer gesteuerte Firmen kämpfen um dieselben Kunden.
## Der Host rechnet, die Clients bekommen den Stand und schicken nur Anfragen.
##   - Je Dienst ein gemeinsamer Kundenmarkt. Anteile nach Preis, Ruf und Qualität.
##   - Eigene Preise je Dienst, Werbung und Abwerben in beide Richtungen.
##   - Die Firmen bieten auf dieselben Verträge.
## Fair: Betroffen sind nur neue und unzufriedene Kunden. Am Anfang kaum spürbar, ab Firmenstufe 3 ganz.

signal market_changed
signal action_result(ok: bool, message: String)

const RIVALS := {
	"pfennig": {
		"name": "PfennigHost", "kind": "Billig-Hoster", "icon": "coin", "color": Color(0.96, 0.66, 0.18),
		"motto": "Billiger geht nicht. Besser schon.", "price": 0.72, "quality": 52.0, "rep": 46.0, "strength": 1.0,
		"spec": {"web": 1.6, "mail": 1.5, "dns": 1.5, "vps": 1.3, "archive": 1.2},
	},
	"aurelwerk": {
		"name": "Aurelwerk Cloud", "kind": "Premium-Anbieter", "icon": "gem", "color": Color(0.82, 0.70, 0.40),
		"motto": "Wer fragt, was es kostet, ist hier falsch.", "price": 1.34, "quality": 91.0, "rep": 78.0, "strength": 0.95,
		"spec": {"database": 1.6, "saas": 1.5, "storage": 1.4, "voip": 1.2},
	},
	"respawnia": {
		"name": "Respawnia", "kind": "Gaming-Spezialist", "icon": "pad", "color": Color(0.42, 0.82, 0.36),
		"motto": "Ping niedrig. Laune hoch.", "price": 1.02, "quality": 74.0, "rep": 62.0, "strength": 0.9,
		"spec": {"game": 1.9, "cloudgaming": 1.9, "stream": 1.3, "voip": 1.1},
	},
	"quarknetz": {
		"name": "Quarknetz KI", "kind": "KI-Firma", "icon": "brain", "color": Color(0.64, 0.46, 0.96),
		"motto": "Wir denken. Also bezahlen Sie.", "price": 1.16, "quality": 79.0, "rep": 60.0, "strength": 0.85,
		"spec": {"ai": 2.1, "database": 1.1, "surveillance": 1.4, "elearning": 1.2},
	},
	"kolossal": {
		"name": "Kolossal Rechenzentren", "kind": "Großkonzern", "icon": "tower", "color": Color(0.36, 0.60, 0.92),
		"motto": "Größe ist unser Produkt.", "price": 0.96, "quality": 69.0, "rep": 66.0, "strength": 1.35,
		"spec": {"cdn": 1.4, "storage": 1.2, "stream": 1.2, "music": 1.2},
	},
}
const RIVAL_ORDER: Array[String] = ["pfennig", "aurelwerk", "respawnia", "quarknetz", "kolossal"]

## Wie stark die Konkurrenz je Firmenstufe wirkt (Stufe 1, 2, ab 3).
const LEVEL_WEIGHT: Array[float] = [0.15, 0.40, 1.0]
const PRICE_MIN := 0.60
const PRICE_MAX := 1.60
const PRICE_STEP := 0.05
const PRICE_ELASTICITY := 1.3
const TICK_SECONDS := 10.0
## Kunden eines Dienstes im Gesamtmarkt: base_users * Faktor, wächst mit den Spieltagen.
const DEMAND_FACTOR := 45.0
const DEMAND_GROWTH := 0.03
const NEWS_MAX := 14
const LEADS_MAX := 5
const LEAD_DAYS := 2
const BID_SECONDS := 200.0
const BID_PAYOUT_CUT := 0.08
const TAKEN_DAYS := 3
const BREACH_LIMIT := 120.0
const POACH_SECONDS := 120.0
const POACH_COOLDOWN := 240.0
const POACH_SAT := 50.0
const POACH_LOSS := 0.35
const CAMPAIGNS_MAX := 2

const CAMPAIGNS := {
	"flyer": {"name": "Flyer & Lokalradio", "cost": 250, "boost": 0.20, "days": 2, "level": 1, "rep": 0.0,
		"desc": "Macht dich in der Stadt bekannt."},
	"online": {"name": "Online-Anzeigen", "cost": 1200, "boost": 0.45, "days": 3, "level": 1, "rep": 0.0,
		"desc": "Anzeigen in Suchmaschinen und Foren."},
	"tv": {"name": "TV-Spot", "cost": 6000, "boost": 0.90, "days": 4, "level": 3, "rep": 2.0,
		"desc": "Zur besten Sendezeit in ganz Deutschland."},
	"messe": {"name": "Messe-Stand", "cost": 15000, "boost": 1.30, "days": 5, "level": 5, "rep": 6.0,
		"desc": "Großer Auftritt auf der Hosting-Messe, stärkt auch den Ruf."},
}

var rivals: Dictionary = {}
var prices: Dictionary = {}
var campaigns: Array = []
var leads: Dictionary = {}
var poach: Dictionary = {}
var news: Array = []

var _tick_accum := 0.0
var _poach_cooldown := 90.0
var _last_day := -1
var _next_num := 1
var _dirty := false
var _was_active := false
var _share_cache: Dictionary = {}
var _share_time := 0
var _growth_cache: Dictionary = {}
var _growth_time := 0


func _ready() -> void:
	_reset_rivals()
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
	var today: int = GameState.day_number
	if _last_day < 0:
		_last_day = today
		_init_users()
		_dirty = true
	while _last_day < today:
		_last_day += 1
		run_day(_last_day)
	tick(delta)
	if _dirty:
		_dirty = false
		_broadcast()


func reset() -> void:
	_share_cache = {}
	_reset_rivals()
	prices.clear()
	campaigns.clear()
	leads.clear()
	poach.clear()
	news.clear()
	_tick_accum = 0.0
	_poach_cooldown = 90.0
	_last_day = -1
	_next_num = 1
	market_changed.emit()


func _reset_rivals() -> void:
	rivals.clear()
	for rid in RIVAL_ORDER:
		var d: Dictionary = RIVALS[rid]
		rivals[rid] = {
			"id": rid, "price": float(d["price"]), "quality": float(d["quality"]), "rep": float(d["rep"]),
			"strength": float(d["strength"]), "users": {}, "trend": 0.0, "state": "ok", "back_day": 0,
			"outage_until": 0, "war_until": 0, "ad_until": 0,
		}


# ---------------------------------------------------------------- Speichern und Abgleich

func export_data() -> Dictionary:
	return {
		"rivals": rivals.duplicate(true), "prices": prices.duplicate(true), "campaigns": campaigns.duplicate(true),
		"leads": leads.duplicate(true), "poach": poach.duplicate(true), "news": news.duplicate(true),
		"last_day": _last_day, "next_num": _next_num,
	}


func import_data(d: Dictionary) -> void:
	_share_cache = {}
	_reset_rivals()
	var saved: Variant = d.get("rivals", {})
	if saved is Dictionary:
		for rid in RIVAL_ORDER:
			var s: Variant = (saved as Dictionary).get(rid)
			if s is Dictionary:
				(rivals[rid] as Dictionary).merge((s as Dictionary).duplicate(true), true)
	prices.clear()
	var sp: Variant = d.get("prices", {})
	if sp is Dictionary:
		for k in (sp as Dictionary).keys():
			prices[str(k)] = clampf(float(sp[k]), PRICE_MIN, PRICE_MAX)
	campaigns = _arr(d.get("campaigns")).duplicate(true)
	news = _arr(d.get("news")).duplicate(true)
	leads = _dict(d.get("leads")).duplicate(true)
	poach = _dict(d.get("poach")).duplicate(true)
	_next_num = maxi(1, int(d.get("next_num", 1)))
	_last_day = int(d.get("last_day", -1))
	if _last_day >= 0 and GameState.is_active:
		_last_day = mini(_last_day, GameState.day_number)
	market_changed.emit()


func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _arr(v: Variant) -> Array:
	return v if v is Array else []


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
	market_changed.emit()
	if NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_sync.rpc(export_data())


func _feedback(peer: int, ok: bool, message: String, args: Array = []) -> void:
	if peer == multiplayer.get_unique_id():
		action_result.emit(ok, GameState.format_message(message, args))
	elif peer > 0:
		_rpc_feedback.rpc_id(peer, ok, message, args)


# ---------------------------------------------------------------- Abfragen

func rival_name(rid: String) -> String:
	return str((RIVALS.get(rid, {}) as Dictionary).get("name", rid))


func level_weight() -> float:
	return LEVEL_WEIGHT[clampi(GameState.get_company_level() - 1, 0, LEVEL_WEIGHT.size() - 1)]


func get_price(service: String) -> float:
	return float(prices.get(service, 1.0))


func ad_boost() -> float:
	var b := 0.0
	for c in campaigns:
		b += float((c as Dictionary).get("boost", 0.0))
	return b


func services_list() -> Array[String]:
	var out: Array[String] = []
	for k in HardwareCatalog.RENTAL_PROFILES.keys():
		if str(k) != "none":
			out.append(str(k))
	return out


func player_users(service: String) -> float:
	var n := 0.0
	for rid in GameState.racks.keys():
		var sv: Variant = (GameState.racks[rid] as Dictionary).get("services", [])
		if sv is Array:
			for s in sv:
				if s is Dictionary and str(s.get("type", "")) == service:
					n += float(s.get("users", 0.0))
	return n


func player_satisfaction(service: String) -> float:
	var sum := 0.0
	var w := 0.0
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		var sv: Variant = r.get("services", [])
		if sv is Array:
			for s in sv:
				if s is Dictionary and str(s.get("type", "")) == service:
					var u := maxf(1.0, float(s.get("users", 0.0)))
					sum += float(r.get("satisfaction", 80.0)) * u
					w += u
	return sum / w if w > 0.0 else 80.0


func demand(service: String) -> float:
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES.get(service, {})
	var day := float(maxi(1, GameState.day_number))
	var own := player_users(service)
	return maxf(float(p.get("base_users", 10)) * DEMAND_FACTOR * (1.0 + DEMAND_GROWTH * day) + own * 0.5, own * 1.25)


func rival_users(rid: String, service: String = "") -> float:
	var u: Dictionary = _dict((rivals[rid] as Dictionary).get("users"))
	if service != "":
		return float(u.get(service, 0.0))
	var n := 0.0
	for k in u.keys():
		n += float(u[k])
	return n


## Marktanteile eines Dienstes: {"you": 0.2, "pfennig": 0.3, …, "free": 0.1}. Summe = 1.
func get_shares(service: String) -> Dictionary:
	var total := maxf(1.0, demand(service))
	var out := {}
	var used := player_users(service)
	out["you"] = used / total
	for rid in RIVAL_ORDER:
		var u := rival_users(rid, service)
		out[rid] = u / total
		used += u
	if used > total:
		for k in out.keys():
			out[k] = float(out[k]) * total / used
		used = total
	out["free"] = maxf(0.0, 1.0 - used / total)
	return out


## Anteil über alle Dienste, gewichtet nach Umsatz (Nutzer * Grundpreis). Wird je Sekunde einmal berechnet.
func get_total_shares() -> Dictionary:
	var now := Time.get_ticks_msec()
	if not _share_cache.is_empty() and now - _share_time < 1000:
		return _share_cache
	_share_time = now
	_share_cache = _calc_total_shares()
	return _share_cache


func _calc_total_shares() -> Dictionary:
	var out := {"you": 0.0, "free": 0.0}
	for rid in RIVAL_ORDER:
		out[rid] = 0.0
	var total := 0.0
	for s in services_list():
		var v := demand(s) * float(HardwareCatalog.RENTAL_PROFILES[s].get("pay_per_user", 0.5))
		var sh := get_shares(s)
		for k in sh.keys():
			out[k] = float(out[k]) + float(sh[k]) * v
		total += v
	for k in out.keys():
		out[k] = float(out[k]) / maxf(1.0, total)
	return out


func _price_factor(p: float) -> float:
	return pow(maxf(0.3, p), -PRICE_ELASTICITY)


func rival_power(rid: String, service: String) -> float:
	var r: Dictionary = rivals[rid]
	if str(r["state"]) != "ok":
		return 0.0
	var spec: Dictionary = RIVALS[rid]["spec"]
	var q := float(r["quality"]) * (0.55 if int(r.get("outage_until", 0)) >= GameState.day_number else 1.0)
	var price := float(r["price"]) * (0.85 if int(r.get("war_until", 0)) >= GameState.day_number else 1.0)
	var ad := 1.25 if int(r.get("ad_until", 0)) >= GameState.day_number else 1.0
	return float(r["strength"]) * float(spec.get(service, 0.7)) * _price_factor(price) * (0.5 + q / 100.0) * (0.5 + float(r["rep"]) / 100.0) * ad


func player_power(service: String, with_price: bool = true) -> float:
	var base := 0.75 + 0.10 * float(GameState.get_company_level())
	var p := _price_factor(get_price(service)) if with_price else 1.0
	return base * p * (0.5 + player_satisfaction(service) / 100.0) * (0.5 + float(GameState.reputation) / 100.0) * (1.0 + ad_boost() * 0.5)


func market_price(service: String) -> float:
	var sum := 0.0
	var w := 0.0
	for rid in RIVAL_ORDER:
		var pw := rival_power(rid, service)
		sum += float(rivals[rid]["price"]) * pw
		w += pw
	return sum / w if w > 0.0 else 1.0


## Wachstumsfaktor für neue Kunden eines Dienstes. Mit Grundpreis, guter Leistung und ohne Werbung ≈ 1.
func growth_factor(service: String) -> float:
	var lw := level_weight()
	var avg := 0.0
	var n := 0
	for rid in RIVAL_ORDER:
		var p := rival_power(rid, service)
		if p > 0.0:
			avg += p
			n += 1
	var comp := 1.0
	if n > 0:
		comp = clampf(player_power(service, false) / maxf(0.05, avg / float(n)), 0.45, 1.6)
	var ref := lerpf(1.0, market_price(service), lw * 0.6)
	var price_f := clampf(pow(get_price(service) / maxf(0.3, ref), -1.1), 0.30, 1.90)
	var own := player_users(service)
	var sat := clampf(1.2 - own / maxf(1.0, demand(service)), 0.4, 1.0)
	return lerpf(1.0, comp, lw * 0.7) * price_f * (1.0 + ad_boost() + DecorManager.growth_bonus()) * lerpf(1.0, sat, lw)


## Wie growth_factor, aber je Dienst nur einmal pro Sekunde berechnet (Aufruf im Spieltakt für jedes Rack).
func growth_factor_cached(service: String) -> float:
	var now := Time.get_ticks_msec()
	if now - _growth_time > 1000:
		_growth_time = now
		_growth_cache.clear()
	if not _growth_cache.has(service):
		_growth_cache[service] = growth_factor(service)
	return float(_growth_cache[service])


## Nutzer je Sekunde, die wegen eines hohen Preises gehen.
func price_shed(service: String) -> float:
	var p := get_price(service)
	if p <= 1.15:
		return 0.0
	return (p - 1.15) * float(HardwareCatalog.RENTAL_PROFILES[service].get("base_users", 10)) * 0.02


## Wie stark neue Kunden gerade kommen, als Text für die Oberfläche.
func outlook_label(service: String) -> String:
	var f := growth_factor(service)
	if f >= 1.5:
		return "sehr stark"
	if f >= 1.1:
		return "stark"
	if f >= 0.85:
		return "normal"
	if f >= 0.55:
		return "schwach"
	return "sehr schwach"


func lead_chance(lead: Dictionary) -> float:
	var s := str(lead.get("service", "web"))
	return clampf(0.35 + float(GameState.reputation) / 220.0 + (1.1 - get_price(s)) * 0.5, 0.08, 0.95)


func has_running_service(service: String) -> bool:
	return _best_rack_for(service) != ""


func _best_rack_for(service: String) -> String:
	var best := ""
	var best_sat := -1.0
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		if not bool(r.get("powered", false)) or not bool(r.get("networked", false)):
			continue
		for s in _arr(r.get("services")):
			if s is Dictionary and str(s.get("type", "")) == service and float(r.get("satisfaction", 0.0)) > best_sat:
				best_sat = float(r.get("satisfaction", 0.0))
				best = str(rid)
	return best


# ---------------------------------------------------------------- Simulation (nur Host)

func _init_users() -> void:
	for s in services_list():
		_relax_users(s, 1.0)


## Nutzer der Konkurrenz Richtung Zielanteil bewegen. k = 0..1 (1 = sofort).
func _relax_users(service: String, k: float) -> void:
	var sum_p := 0.0
	var pw := {}
	for rid in RIVAL_ORDER:
		pw[rid] = rival_power(rid, service)
		sum_p += float(pw[rid])
	var total := demand(service)
	var room := maxf(0.0, total * 0.90 - player_users(service))
	for rid in RIVAL_ORDER:
		var u: Dictionary = rivals[rid]["users"]
		var target := room * float(pw[rid]) / sum_p if sum_p > 0.0 else 0.0
		u[service] = lerpf(float(u.get(service, 0.0)), target, k)


func tick(delta: float) -> void:
	_tick_bids(delta)
	_tick_poach(delta)
	_tick_accum += delta
	if _tick_accum < TICK_SECONDS:
		return
	_tick_accum = 0.0
	for rid in RIVAL_ORDER:
		rivals[rid]["prev"] = rival_users(rid)
	for s in services_list():
		_relax_users(s, 0.03)
	for rid in RIVAL_ORDER:
		var r: Dictionary = rivals[rid]
		var prev := maxf(1.0, float(r.get("prev", 1.0)))
		r["trend"] = lerpf(float(r.get("trend", 0.0)), (rival_users(rid) - prev) / prev * 100.0, 0.3)
		r.erase("prev")
	_maybe_bid()
	_maybe_poach()
	_dirty = true


func run_day(day: int) -> void:
	for i in range(campaigns.size() - 1, -1, -1):
		var c: Dictionary = campaigns[i]
		c["days_left"] = int(c.get("days_left", 1)) - 1
		if int(c["days_left"]) <= 0:
			campaigns.remove_at(i)
			GameState.post_event_f("Werbung '%s' ist ausgelaufen.", [str(CAMPAIGNS[str(c["kind"])]["name"])], "info")
	for lid in leads.keys():
		if int(leads[lid].get("until_day", 0)) < day:
			leads.erase(lid)
	for cid in GameState.contracts.keys():
		var ct: Dictionary = GameState.contracts[cid]
		if int(ct.get("taken_until", 0)) > 0 and day > int(ct["taken_until"]):
			ct.erase("taken_until")
			ct.erase("taken_by")
	for rid in RIVAL_ORDER:
		_rival_day(rid, day)
	if leads.size() < LEADS_MAX and randf() < 0.75:
		_add_lead(_random_active_rival())
	_dirty = true


func _rival_day(rid: String, day: int) -> void:
	var r: Dictionary = rivals[rid]
	if str(r["state"]) == "pleite":
		if day >= int(r["back_day"]):
			r["state"] = "ok"
			r["strength"] = 0.8
			r["quality"] = float(RIVALS[rid]["quality"])
			r["rep"] = 45.0
			add_news("%s ist mit einem neuen Investor zurück am Markt.", [rival_name(rid)], rid)
		return
	var base := float(RIVALS[rid]["strength"]) * (1.0 + 0.06 * float(GameState.get_company_level() - 1))
	r["strength"] = clampf(lerpf(float(r["strength"]), base, 0.08) + randf_range(-0.07, 0.07), 0.15, 2.4)
	r["quality"] = clampf(lerpf(float(r["quality"]), float(RIVALS[rid]["quality"]), 0.25) + randf_range(-3.0, 3.0), 20.0, 98.0)
	r["rep"] = clampf(lerpf(float(r["rep"]), float(RIVALS[rid]["rep"]), 0.15) + randf_range(-2.0, 2.0), 10.0, 96.0)
	r["price"] = clampf(lerpf(float(r["price"]), float(RIVALS[rid]["price"]), 0.30) + randf_range(-0.03, 0.03), 0.55, 1.6)
	if float(r["strength"]) < 0.38 and randf() < 0.5:
		_go_bankrupt(rid, day)
		return
	var roll := randf()
	if roll < 0.07:
		r["outage_until"] = day + 1
		r["rep"] = maxf(10.0, float(r["rep"]) - 8.0)
		r["strength"] = float(r["strength"]) * 0.90
		add_news("Ausfall bei %s: Kunden beschweren sich öffentlich.", [rival_name(rid)], rid)
		_add_lead(rid)
		_add_lead(rid)
	elif roll < 0.13:
		r["war_until"] = day + 2
		add_news("Preiskampf: %s senkt für kurze Zeit alle Preise.", [rival_name(rid)], rid)
	elif roll < 0.18:
		r["strength"] = float(r["strength"]) + 0.16
		add_news("%s eröffnet ein neues Rechenzentrum.", [rival_name(rid)], rid)
	elif roll < 0.23:
		r["rep"] = maxf(10.0, float(r["rep"]) - 14.0)
		r["strength"] = float(r["strength"]) * 0.88
		add_news("Datenpanne bei %s, der Ruf ist angeschlagen.", [rival_name(rid)], rid)
		_add_lead(rid)
	elif roll < 0.30:
		r["ad_until"] = day + 2
		add_news("%s startet eine große Werbekampagne.", [rival_name(rid)], rid)


func _go_bankrupt(rid: String, day: int) -> void:
	var r: Dictionary = rivals[rid]
	r["state"] = "pleite"
	r["back_day"] = day + randi_range(4, 7)
	r["users"] = {}
	add_news("%s ist pleite! Seine Kunden suchen einen neuen Anbieter.", [rival_name(rid)], rid)
	GameState.post_event_f("📰 %s ist pleite! Seine Kunden suchen einen neuen Anbieter.", [rival_name(rid)], "good")
	for i in 3:
		_add_lead(rid)


func add_news(text: String, args: Array, rid: String = "") -> void:
	news.push_front({"day": GameState.day_number, "text": text, "args": args.duplicate(), "rival": rid})
	while news.size() > NEWS_MAX:
		news.pop_back()
	_dirty = true


func _random_active_rival() -> String:
	var act: Array[String] = []
	for rid in RIVAL_ORDER:
		if str(rivals[rid]["state"]) == "ok":
			act.append(rid)
	return act[randi() % act.size()] if not act.is_empty() else RIVAL_ORDER[0]


## Unzufriedener Kunde der Konkurrenz. Bevorzugt Dienste, die du gerade betreibst.
func _add_lead(rid: String) -> void:
	if leads.size() >= LEADS_MAX:
		return
	var own: Array[String] = []
	for s in services_list():
		if player_users(s) > 0.0:
			own.append(s)
	var service := ""
	if not own.is_empty() and randf() < 0.75:
		service = own[randi() % own.size()]
	else:
		var spec: Array = (RIVALS[rid]["spec"] as Dictionary).keys()
		service = str(spec[randi() % spec.size()])
	var p: Dictionary = HardwareCatalog.RENTAL_PROFILES[service]
	var lvl := float(GameState.get_company_level())
	var users := int(roundf(float(p.get("base_users", 10)) * randf_range(0.6, 1.4) * (0.8 + 0.35 * lvl)))
	var lid := "L%d" % _next_num
	_next_num += 1
	leads[lid] = {
		"id": lid, "rival": rid, "service": service, "users": maxi(2, users),
		"customer": HardwareCatalog.pick_customer_name(service, randi() % 9973),
		"cost": int(40.0 + float(users) * float(p.get("pay_per_user", 0.5)) * 5.0),
		"until_day": GameState.day_number + LEAD_DAYS,
	}
	MailManager.on_lead(leads[lid])
	_dirty = true


# ---------------------------------------------------------------- Verträge

func is_contract_taken(c: Dictionary) -> bool:
	return int(c.get("taken_until", 0)) >= GameState.day_number and str(c.get("taken_by", "")) != ""


## Auszahlung eines Vertrags, wenn er jetzt angenommen wird. Ein Gegengebot drückt den Preis.
func contract_payout(c: Dictionary) -> int:
	var pay := float(c.get("payout_per_cycle", 0))
	if str(c.get("bid_rival", "")) != "":
		pay *= 1.0 - BID_PAYOUT_CUT
	return maxi(1, int(roundf(pay)))


func _maybe_bid() -> void:
	# Pro Angebot im Schnitt ein Gebot alle paar Spieltage, je nach Stufe.
	var per_tick := 0.30 * level_weight() * TICK_SECONDS / GameState.DAY_LENGTH_SECONDS
	for cid in GameState.contracts.keys():
		var c: Dictionary = GameState.contracts[cid]
		if bool(c.get("active", false)) or str(c.get("bid_rival", "")) != "" or is_contract_taken(c):
			continue
		if randf() < per_tick:
			start_bid(str(cid), _random_active_rival())


func start_bid(cid: String, rid: String) -> void:
	var c: Dictionary = GameState.contracts[cid]
	c["bid_rival"] = rid
	c["bid_left"] = BID_SECONDS
	GameState.post_event_f("📄 %s bietet auf den Vertrag '%s' mit.", [rival_name(rid), str(c["title"])], "warn")
	MailManager.on_contract_bid(c, rid)
	GameState._broadcast_sim_tick()
	_dirty = true


func _tick_bids(delta: float) -> void:
	for cid in GameState.contracts.keys():
		var c: Dictionary = GameState.contracts[cid]
		if bool(c.get("active", false)):
			if str(c.get("status", "")) == "underpowered":
				c["breach_secs"] = float(c.get("breach_secs", 0.0)) + delta
				if float(c["breach_secs"]) >= BREACH_LIMIT and level_weight() >= 0.4:
					_lose_contract(str(cid), _random_active_rival(), true)
			elif c.has("breach_secs"):
				c["breach_secs"] = maxf(0.0, float(c["breach_secs"]) - delta * 2.0)
			continue
		if str(c.get("bid_rival", "")) == "":
			continue
		c["bid_left"] = float(c.get("bid_left", 0.0)) - delta
		if float(c["bid_left"]) <= 0.0:
			_lose_contract(str(cid), str(c["bid_rival"]), false)


func _lose_contract(cid: String, rid: String, was_ours: bool) -> void:
	var c: Dictionary = GameState.contracts[cid]
	if was_ours:
		GameState.post_event_f("❌ %s übernimmt deinen Vertrag '%s', weil er zu lange nicht erfüllt war.", [rival_name(rid), str(c["title"])], "alert")
	else:
		GameState.post_event_f("📄 Der Vertrag '%s' geht an %s.", [str(c["title"]), rival_name(rid)], "info")
	add_news("%s gewinnt den Vertrag '%s'.", [rival_name(rid), str(c["title"])], rid)
	MailManager.on_contract_lost(c, rid, was_ours)
	rivals[rid]["strength"] = minf(2.4, float(rivals[rid]["strength"]) + 0.03)
	if bool(c.get("random", false)):
		GameState.contracts.erase(cid)
	else:
		c["active"] = false
		c["status"] = "idle"
		c["taken_by"] = rid
		c["taken_until"] = GameState.day_number + TAKEN_DAYS
		clear_bid(c)
	GameState._recalculate_networks_and_metrics()
	GameState._broadcast_sim_tick()
	_dirty = true


func clear_bid(c: Dictionary) -> void:
	for k in ["bid_rival", "bid_left", "breach_secs"]:
		c.erase(k)


# ---------------------------------------------------------------- Abwerben deiner Kunden

func _maybe_poach() -> void:
	if not poach.is_empty() or _poach_cooldown > 0.0 or level_weight() < 0.4:
		return
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		if float(r.get("satisfaction", 100.0)) >= POACH_SAT:
			continue
		var sv := _arr(r.get("services"))
		if sv.is_empty():
			continue
		start_poach(str(rid), sv[randi() % sv.size()] as Dictionary, _random_active_rival())
		return


func start_poach(rack_id: String, svc: Dictionary, rid: String) -> void:
	var users := int(float(svc.get("users", 1.0)))
	poach = {
		"rack_id": rack_id, "service": str(svc.get("type", "")), "customer": str(svc.get("customer", "")),
		"rival": rid, "left": POACH_SECONDS, "users": users,
		"cost": mini(2500, 80 + int(float(users) * 0.4)),
	}
	GameState.post_event_f("⚠ %s wirbt %s ab! Biete einen Rabatt an oder mach den Kunden wieder zufrieden.", [rival_name(rid), str(svc.get("customer", ""))], "alert")
	MailManager.on_poach(poach)
	_dirty = true


func _tick_poach(delta: float) -> void:
	_poach_cooldown = maxf(0.0, _poach_cooldown - delta)
	if poach.is_empty():
		return
	poach["left"] = float(poach["left"]) - delta
	var rack_id := str(poach["rack_id"])
	if not GameState.racks.has(rack_id):
		_end_poach()
		return
	var r: Dictionary = GameState.racks[rack_id]
	if float(r.get("satisfaction", 0.0)) >= 72.0:
		GameState.post_event_f("🤝 %s ist wieder zufrieden und bleibt bei dir.", [str(poach["customer"])], "good")
		_end_poach()
	elif float(poach["left"]) <= 0.0:
		for s in _arr(r.get("services")):
			if s is Dictionary and str(s.get("type", "")) == str(poach["service"]):
				var floor_u := float(HardwareCatalog.RENTAL_PROFILES[str(poach["service"])].get("base_users", 4)) * 0.25
				var cur := float(s.get("users", 0.0))
				var lost := maxf(0.0, cur - maxf(minf(cur, floor_u), cur * (1.0 - POACH_LOSS)))
				s["users"] = cur - lost
				var u: Dictionary = rivals[str(poach["rival"])]["users"]
				u[str(poach["service"])] = float(u.get(str(poach["service"]), 0.0)) + lost
				GameState.post_event_f("❌ %s hat %d Kunden von %s abgeworben.", [rival_name(str(poach["rival"])), int(roundf(lost)), str(poach["customer"])], "alert")
		GameState.reputation = maxf(0.0, GameState.reputation - 1.5)
		add_news("%s wirbt %s bei dir ab.", [rival_name(str(poach["rival"])), str(poach["customer"])], str(poach["rival"]))
		_end_poach()
		GameState._broadcast_racks()


func _end_poach() -> void:
	poach = {}
	_poach_cooldown = POACH_COOLDOWN
	_dirty = true


# ---------------------------------------------------------------- Anfragen der Spieler

func request_set_price(service: String, value: float) -> void:
	_rpc_req_set_price.rpc_id(1, service, value)


func request_campaign(kind: String) -> void:
	_rpc_req_campaign.rpc_id(1, kind)


func request_lead_offer(lid: String) -> void:
	_rpc_req_lead.rpc_id(1, lid)


func request_counter_poach() -> void:
	_rpc_req_counter_poach.rpc_id(1)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_price(service: String, value: float) -> void:
	if not multiplayer.is_server() or not HardwareCatalog.RENTAL_PROFILES.has(service) or service == "none":
		return
	if not SecurityGuard.is_finite_float(value) or not SecurityGuard.check_rate_limit(_sender(), "price", 20, 4.0):
		return
	var v := clampf(snappedf(value, PRICE_STEP), PRICE_MIN, PRICE_MAX)
	if is_equal_approx(v, 1.0):
		prices.erase(service)
	else:
		prices[service] = v
	_dirty = true


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_campaign(kind: String) -> void:
	if not multiplayer.is_server() or not CAMPAIGNS.has(kind):
		return
	var peer := _sender()
	var c: Dictionary = CAMPAIGNS[kind]
	for run in campaigns:
		if str((run as Dictionary).get("kind", "")) == kind:
			_feedback(peer, false, "Diese Werbung läuft schon.")
			return
	if campaigns.size() >= CAMPAIGNS_MAX:
		_feedback(peer, false, "Es laufen schon %d Kampagnen.", [CAMPAIGNS_MAX])
		return
	if GameState.get_company_level() < int(c["level"]):
		_feedback(peer, false, "Erst ab Firmenstufe %d.", [int(c["level"])])
		return
	if GameState.money < float(c["cost"]):
		_feedback(peer, false, "Dafür reicht das Geld nicht.")
		return
	FinanceManager.debit_public(float(c["cost"]), "Werbung: %s", [str(c["name"])])
	campaigns.append({"kind": kind, "boost": float(c["boost"]), "days_left": int(c["days"])})
	if float(c["rep"]) > 0.0:
		GameState.reputation = minf(100.0, GameState.reputation + float(c["rep"]))
	GameState.post_event_f("📣 %s startet die Werbung '%s' (+%d%% neue Kunden, %d Tage).", [
		NetworkManager.get_player_name(peer), str(c["name"]), int(float(c["boost"]) * 100.0), int(c["days"])], "good")
	_feedback(peer, true, "Werbung gestartet.")
	GameState._rpc_play_sfx.rpc("cash")
	GameState._broadcast_sim_tick()
	_dirty = true


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_lead(lid: String) -> void:
	if multiplayer.is_server():
		do_lead(lid, _sender())


func do_lead(lid: String, peer: int) -> void:
	if not leads.has(lid):
		_feedback(peer, false, "Dieser Kunde hat sich schon entschieden.")
		return
	var l: Dictionary = leads[lid]
	var service := str(l["service"])
	var rack_id := _best_rack_for(service)
	if rack_id == "":
		_feedback(peer, false, "Dafür brauchst du ein laufendes Rack mit diesem Dienst.")
		return
	if GameState.money < float(l["cost"]):
		_feedback(peer, false, "Dafür reicht das Geld nicht.")
		return
	FinanceManager.debit_public(float(l["cost"]), "Wechselprämie %s", [str(l["customer"])])
	leads.erase(lid)
	if randf() < lead_chance(l):
		for s in _arr(GameState.racks[rack_id].get("services")):
			if s is Dictionary and str(s.get("type", "")) == service:
				s["users"] = float(s.get("users", 0.0)) + float(l["users"])
				break
		var u: Dictionary = rivals[str(l["rival"])]["users"]
		u[service] = maxf(0.0, float(u.get(service, 0.0)) - float(l["users"]))
		GameState.racks[rack_id]["grace_timer"] = maxf(float(GameState.racks[rack_id].get("grace_timer", 0.0)), 25.0)
		GameState.post_event_f("🤝 %s wechselt von %s zu dir (+%d Kunden)!", [str(l["customer"]), rival_name(str(l["rival"])), int(l["users"])], "good")
		add_news("%s verliert %s an dich.", [rival_name(str(l["rival"])), str(l["customer"])], str(l["rival"]))
		_feedback(peer, true, "Gewonnen! Der Kunde wechselt zu dir.")
		GameState._rpc_play_sfx.rpc("cash")
	else:
		GameState.post_event_f("%s bleibt lieber bei %s.", [str(l["customer"]), rival_name(str(l["rival"]))], "info")
		_feedback(peer, false, "Der Kunde hat abgelehnt.")
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
	_dirty = true


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_counter_poach() -> void:
	if multiplayer.is_server():
		do_counter_poach(_sender())


func do_counter_poach(peer: int) -> void:
	if poach.is_empty():
		_feedback(peer, false, "Dieser Kunde hat sich schon entschieden.")
		return
	if GameState.money < float(poach["cost"]):
		_feedback(peer, false, "Dafür reicht das Geld nicht.")
		return
	FinanceManager.debit_public(float(poach["cost"]), "Treuerabatt %s", [str(poach["customer"])])
	var r: Dictionary = GameState.racks[str(poach["rack_id"])]
	r["satisfaction"] = minf(100.0, float(r.get("satisfaction", 50.0)) + 20.0)
	r["grace_timer"] = maxf(float(r.get("grace_timer", 0.0)), 40.0)
	GameState.post_event_f("🤝 Treuerabatt: %s bleibt bei dir.", [str(poach["customer"])], "good")
	_feedback(peer, true, "Der Kunde bleibt bei dir.")
	_end_poach()
	GameState._rpc_play_sfx.rpc("cash")
	GameState._broadcast_racks()
	GameState._broadcast_sim_tick()
