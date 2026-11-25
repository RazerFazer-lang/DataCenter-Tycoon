extends Node
## Alles rund um die Halle: Zauntor, Hintertür, Außenlampen, Pflege der Außengeräte, Dach (Solar, Schüssel,
## Wetterstation), Garten und Pausenplatz, Jahreszeiten. Der Host rechnet, der Zustand liegt im Spielstand.

signal changed

const DAYS_PER_SEASON := 4.0
const SEASON_NAMES: Array[String] = ["Frühling", "Sommer", "Herbst", "Winter"]
## Temperatur im Raum durch die Jahreszeit.
const SEASON_TEMP: Array[float] = [0.0, 1.5, -1.0, -3.5]

const SOLAR_PRICE := 2400.0
const SOLAR_SAVE := 0.12
const DISH_GROWTH := 0.04
const CLOG_MAX_LOSS := 0.35
const GATE_THIEF := 0.18
const LAMP_THIEF := 0.70
const GRILL_COST := 8.0
const GRILL_SECS := 25.0
const GRILL_PORTIONS := 4
const FOOD_SECS := 240.0
const FEED_COST := 2.0
const BENCH_REST := 6.0
const SEED_COST := 6.0
const PLANTS: Array[String] = ["tomato", "lettuce", "berry"]
const PLANT_NAMES := {"tomato": "Tomaten", "lettuce": "Salat", "berry": "Erdbeeren"}
const PLANT_PAY := {"tomato": 38.0, "lettuce": 24.0, "berry": 46.0}
## Wachstum in Spieltagen (mit Wasser, im Sommer).
const PLANT_DAYS := {"tomato": 1.8, "lettuce": 1.1, "berry": 2.2}
const DEFAULT := {
	"gate": false, "gate_auto": true, "door": false, "lamps": true, "solar": false, "solar_dirt": 0.0, "dish": 1.0, "forecast": "",
	"grill_t": 0.0, "grill_left": 0, "feed": 0.0, "snow": 0.0, "clog": {}, "next_plant": 0,
	"beds": [{"p": "", "g": 0.0, "w": 0.0}, {"p": "", "g": 0.0, "w": 0.0}, {"p": "", "g": 0.0, "w": 0.0}],
}

var state: Dictionary = DEFAULT.duplicate(true)
## Anzeige auf jedem Rechner: Schnee läuft weich nach.
var snow_shown := 0.0
var _accum := 0.0
var _sync := 0.0
var _dirty := false
var _last_day := -1
var _last_weather := ""
var _last_night := false
var _apply_t := 0.0


func _ready() -> void:
	GameState.world_snapshot_loaded.connect(func() -> void: changed.emit())


func reset() -> void:
	state = DEFAULT.duplicate(true)
	snow_shown = 0.0
	_last_day = -1
	_last_weather = ""
	changed.emit()


## Gerundet, damit die Prüfsumme des Spielstands nach dem Laden gleich bleibt.
func export_data() -> Dictionary:
	return _snap(state)


func _snap(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.001)
	if v is Dictionary:
		var d := {}
		for k in (v as Dictionary).keys():
			d[k] = _snap(v[k])
		return d
	if v is Array:
		var a := []
		for e in v:
			a.append(_snap(e))
		return a
	return v


## Zustand aus Spielstand oder Netzwerk übernehmen, alles geprüft.
func load_data(raw: Variant) -> void:
	var d: Dictionary = raw if raw is Dictionary else {}
	var s := DEFAULT.duplicate(true)
	for k in ["gate", "gate_auto", "door", "lamps", "solar"]:
		s[k] = bool(d.get(k, s[k]))
	for k in ["solar_dirt", "dish", "feed", "snow"]:
		s[k] = _f(d.get(k, s[k]))
	s["grill_t"] = clampf(_f(d.get("grill_t", 0.0), 999.0), 0.0, GRILL_SECS)
	s["grill_left"] = clampi(int(_f(d.get("grill_left", 0), 99.0)), 0, GRILL_PORTIONS)
	s["next_plant"] = clampi(int(_f(d.get("next_plant", 0), 99.0)), 0, 2)
	s["forecast"] = str(d.get("forecast", "")).left(12)
	if d.get("clog") is Dictionary:
		for c in (d["clog"] as Dictionary).keys():
			s["clog"][str(c)] = _f(d["clog"][c])
	var beds: Variant = d.get("beds", [])
	if beds is Array:
		for i in mini(3, (beds as Array).size()):
			if beds[i] is Dictionary:
				var p := str((beds[i] as Dictionary).get("p", ""))
				s["beds"][i] = {"p": p if PLANTS.has(p) else "", "g": _f((beds[i] as Dictionary).get("g", 0.0)), "w": _f((beds[i] as Dictionary).get("w", 0.0))}
	state = s
	snow_shown = float(s["snow"])
	changed.emit()


func _f(v: Variant, hi: float = 1.0) -> float:
	return clampf(float(v), 0.0, hi) if (v is float or v is int) and is_finite(float(v)) else 0.0


# ---------------------------------------------------------------- Jahreszeit

## 0..4, siehe Nature. Ein Jahr dauert 16 Spieltage, es beginnt im Frühling.
func season() -> float:
	if not GameState.is_active:
		return 1.3
	# Die Uhr springt um Mitternacht zurück, der Tag zählt gleichzeitig hoch.
	return fposmod((float(GameState.day_number - 1) + GameState.time_of_day) / DAYS_PER_SEASON, 4.0)


func season_index() -> int:
	return int(season())


func season_label() -> String:
	return tr(SEASON_NAMES[season_index()])


func season_temp() -> float:
	return SEASON_TEMP[season_index()]


func is_winter() -> bool:
	return season_index() == 3


func is_snowing() -> bool:
	return is_winter() and GameState.weather_state in ["rain", "storm"]


func is_night() -> bool:
	return GameState.time_of_day < 0.24 or GameState.time_of_day > 0.76


func lamps_on() -> bool:
	return bool(state["lamps"]) and (GameState.time_of_day < 0.27 or GameState.time_of_day > 0.72 or GameState.weather_state == "storm") and DecorManager.has_power()


# ---------------------------------------------------------------- Wirkung

## Leistung eines Außengeräts (1 = sauber).
func unit_factor(cid: String) -> float:
	return 1.0 - CLOG_MAX_LOSS * float((state["clog"] as Dictionary).get(cid, 0.0))


func clog(cid: String) -> float:
	return float((state["clog"] as Dictionary).get(cid, 0.0))


## Womit ist das Gerät zu? leaves, snow, dust
func clog_kind() -> String:
	return ["dust", "dust", "leaves", "snow"][season_index()]


## Solarleistung 0..1 im Moment.
func solar_output() -> float:
	if not bool(state["solar"]):
		return 0.0
	var t := GameState.time_of_day
	var sun := maxf(0.0, sin((t - 0.25) * TAU)) if t > 0.25 and t < 0.75 else 0.0
	sun = pow(sun, 0.7)
	sun *= {"clear": 1.0, "heatwave": 1.0, "cloudy": 0.5, "rain": 0.25, "storm": 0.12}.get(GameState.weather_state, 1.0)
	sun *= [0.95, 1.0, 0.75, 0.5][season_index()]
	return sun * (1.0 - 0.75 * float(state["solar_dirt"])) * (1.0 - 0.9 * float(state["snow"]))


## Faktor auf den Stromverbrauch. Über den Tag gerechnet spart die saubere Anlage rund 12 Prozent.
func power_mult() -> float:
	return 1.0 - solar_output() * SOLAR_SAVE * 3.0


func dish_bonus() -> float:
	return DISH_GROWTH if float(state["dish"]) >= 0.7 else 0.0


func thief_factor() -> float:
	var f := 1.0
	if bool(state["gate"]):
		f *= GATE_THIEF
	if bool(state["lamps"]) and DecorManager.has_power():
		f *= LAMP_THIEF
	return f


func has_food(peer: int) -> bool:
	return DecorManager.has_buff(peer, "food")


# ---------------------------------------------------------------- Netzwerk

func _online() -> bool:
	return NetworkManager.is_in_session and multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func broadcast() -> void:
	_dirty = false
	_sync = 0.0
	changed.emit()
	if _online():
		_rpc_state.rpc(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(s: Dictionary) -> void:
	var keep := snow_shown
	load_data(s)
	snow_shown = keep


func request_use(id: String, alt: bool = false) -> void:
	_rpc_use.rpc_id(1, id, alt)


@rpc("any_peer", "call_local", "reliable")
func _rpc_use(id: String, alt: bool) -> void:
	if not multiplayer.is_server():
		return
	var s := multiplayer.get_remote_sender_id()
	do_use(id.left(24), s if s != 0 else multiplayer.get_unique_id(), alt)


func _sfx(peer: int, snd: String) -> void:
	GameState._rpc_play_sfx.rpc_id(peer, snd)


func do_use(id: String, peer: int, alt: bool = false) -> void:
	if not SecurityGuard.check_rate_limit(peer, "outdoor_use", 14, 4.0):
		return
	var who := NetworkManager.get_player_name(peer)
	if id.begins_with("bed:"):
		_use_bed(int(id.substr(4)), peer)
		return
	if id.begins_with("unit:"):
		_clean_unit(id.substr(5), peer)
		return
	match id:
		"gate":
			if alt:
				state["gate_auto"] = not bool(state["gate_auto"])
				_sfx(peer, "click")
			else:
				if not bool(state["gate"]) and _delivery_here():
					_sfx(peer, "error")
					return
				state["gate"] = not bool(state["gate"])
				GameState._rpc_play_sfx.rpc("glass_door")
			broadcast()
		"door":
			state["door"] = not bool(state["door"])
			GameState._rpc_play_sfx.rpc("van_door" if bool(state["door"]) else "drawer")
			broadcast()
		"lamps":
			state["lamps"] = not bool(state["lamps"])
			GameState._rpc_play_sfx.rpc("strip_switch")
			broadcast()
		"solar":
			if not bool(state["solar"]):
				if GameState.money < SOLAR_PRICE:
					_sfx(peer, "error")
					return
				FinanceManager.debit_public(SOLAR_PRICE, "Solaranlage")
				state["solar"] = true
				state["solar_dirt"] = 0.0
				GameState._rpc_play_sfx.rpc("upgrade")
				GameState.post_event_f("☀ %s hat die Solaranlage auf dem Dach aufgebaut.", [who], "good")
				GameState._broadcast_sim_tick()
			elif float(state["solar_dirt"]) < 0.05 and float(state["snow"]) < 0.1:
				_sfx(peer, "error")
				return
			else:
				state["solar_dirt"] = 0.0
				_sfx(peer, "water_pour")
				GameState.post_event_f("%s hat die Solarmodule geputzt.", [who], "good")
			broadcast()
		"dish":
			if float(state["dish"]) > 0.97:
				_sfx(peer, "error")
				return
			state["dish"] = minf(1.0, float(state["dish"]) + 0.25)
			GameState._rpc_play_sfx.rpc("screw_tick")
			if float(state["dish"]) >= 0.97:
				GameState.post_event_f("📡 %s hat die Schüssel ausgerichtet.", [who], "good")
			broadcast()
		"grill":
			_use_grill(peer)
		"feeder":
			if float(state["feed"]) > 0.8 or GameState.money < FEED_COST:
				_sfx(peer, "error")
				return
			FinanceManager.debit_public(FEED_COST, "Vogelfutter")
			state["feed"] = 1.0
			_sfx(peer, "part_slide")
			GameState._broadcast_sim_tick()
			broadcast()
		"bench":
			DecorManager.add_buff(peer, "rest", DecorManager.REST_SECS)


func _delivery_here() -> bool:
	return GameState.van_phase != "idle" and GameState.van_site == "garage"


func _use_grill(peer: int) -> void:
	if int(state["grill_left"]) > 0 and float(state["grill_t"]) <= 0.0:
		state["grill_left"] = int(state["grill_left"]) - 1
		DecorManager.add_buff(peer, "food", FOOD_SECS)
		_sfx(peer, "pickup")
	elif float(state["grill_t"]) > 0.0 or GameState.money < GRILL_COST:
		_sfx(peer, "error")
		return
	else:
		FinanceManager.debit_public(GRILL_COST, "Grillgut")
		state["grill_t"] = GRILL_SECS
		state["grill_left"] = GRILL_PORTIONS
		GameState._rpc_play_sfx.rpc("part_set")
		GameState.post_event_f("🍖 %s hat den Grill angeworfen.", [NetworkManager.get_player_name(peer)], "info")
		GameState._broadcast_sim_tick()
	broadcast()


func _use_bed(i: int, peer: int) -> void:
	if i < 0 or i >= 3:
		return
	var b: Dictionary = state["beds"][i]
	if str(b["p"]) == "":
		if GameState.money < SEED_COST or is_winter():
			_sfx(peer, "error")
			return
		FinanceManager.debit_public(SEED_COST, "Saatgut")
		var k := int(state["next_plant"])
		state["next_plant"] = (k + 1) % PLANTS.size()
		state["beds"][i] = {"p": PLANTS[k], "g": 0.0, "w": 1.0}
		_sfx(peer, "part_slide")
		GameState._broadcast_sim_tick()
	elif float(b["g"]) >= 1.0:
		var pay := float(PLANT_PAY[b["p"]])
		FinanceManager.credit_public(pay, "Gartenernte")
		GameState.reputation = minf(100.0, GameState.reputation + 0.3)
		GameState.post_event_f("🌱 %s hat geerntet: %s (+$%d).", [NetworkManager.get_player_name(peer), PLANT_NAMES[b["p"]], int(pay)], "good")
		state["beds"][i] = {"p": "", "g": 0.0, "w": 0.0}
		_sfx(peer, "cash")
		GameState._broadcast_sim_tick()
	elif float(b["w"]) < 0.8:
		b["w"] = 1.0
		_sfx(peer, "water_pour")
	else:
		_sfx(peer, "error")
		return
	broadcast()


func _clean_unit(cid: String, peer: int) -> void:
	if not GameState.coolers.has(cid) or clog(cid) < 0.08:
		_sfx(peer, "error")
		return
	(state["clog"] as Dictionary).erase(cid)
	GameState._rpc_play_sfx.rpc("part_slide")
	GameState.post_event_f("%s hat ein Außengerät sauber gemacht.", [NetworkManager.get_player_name(peer)], "good")
	broadcast()


# ---------------------------------------------------------------- Simulation

func _process(delta: float) -> void:
	if not GameState.is_active:
		_show(delta)
		return
	_show(delta)
	if float(state["grill_t"]) > 0.0 and not _online():
		state["grill_t"] = maxf(0.0, float(state["grill_t"]) - delta)
	if not _online() or GameState.is_world_paused_for_empty_server():
		return
	_accum += delta
	_sync += delta
	if _accum >= 1.0:
		tick(_accum * GameState.clock_scale)
		_accum = 0.0
	if _dirty and _sync >= 4.0:
		broadcast()


## Wetter und Jahreszeit an Bäume und Wiese geben (auf jedem Rechner).
func _show(delta: float) -> void:
	snow_shown = move_toward(snow_shown, float(state["snow"]), delta * 0.05)
	_apply_t -= delta
	if _apply_t > 0.0:
		return
	_apply_t = 0.5
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var ws: Vector2 = {"storm": Vector2(0.22, 3.3), "rain": Vector2(0.125, 2.2), "cloudy": Vector2(0.09, 1.8)}.get(w, Vector2(0.06, 1.45))
	Nature.update(season(), snow_shown, ws.x, ws.y)


## Ein Schritt in Sekunden (Spielzeit läuft mit clock_scale).
func tick(dt: float) -> void:
	var days := dt / GameState.DAY_LENGTH_SECONDS
	if _last_day < 0:
		_last_day = GameState.day_number
	while _last_day < GameState.day_number:
		_last_day += 1
		_run_day()
	# Schnee
	var target := float(state["snow"])
	if is_snowing():
		target = minf(1.0, target + dt / 70.0)
	elif is_winter():
		target = move_toward(target, 0.55, dt / 260.0)
	else:
		target = maxf(0.0, target - dt / 110.0)
	_put("snow", target, 0.04)
	# Außengeräte: Laub im Herbst, Schnee im Winter, sonst langsam Staub
	var rate: float = [0.10, 0.07, 0.42, 0.22][season_index()]
	if is_snowing():
		rate = 1.6
	elif GameState.weather_state == "storm":
		rate *= 2.0
	var cl: Dictionary = state["clog"]
	for cid in cl.keys():
		if not GameState.coolers.has(cid):
			cl.erase(cid)
	for cid in GameState.coolers.keys():
		var ct := str((GameState.coolers[cid] as Dictionary).get("cooler_type", "cooler"))
		if not GameState.is_heat_pump_type(ct):
			continue
		var before := clog(cid)
		cl[cid] = minf(1.0, before + days * rate)
		if int(before * 20.0) != int(float(cl[cid]) * 20.0):
			_dirty = true
			if before < 0.6 and float(cl[cid]) >= 0.6:
				GameState.post_event(["Ein Außengerät ist verstaubt und kühlt schwächer. Draußen mit [E] reinigen.", "Ein Außengerät ist verstaubt und kühlt schwächer. Draußen mit [E] reinigen.", "🍂 Laub verstopft ein Außengerät. Draußen mit [E] freiräumen.", "❄ Schnee verstopft ein Außengerät. Draußen mit [E] freiräumen."][season_index()], "warn")
	# Dach
	if bool(state["solar"]):
		var wash := 0.6 if GameState.weather_state in ["rain", "storm"] and not is_winter() else 0.0
		_put("solar_dirt", clampf(float(state["solar_dirt"]) + days * (0.16 if season_index() != 0 else 0.26) - days * wash, 0.0, 1.0), 0.05)
	if GameState.weather_state != _last_weather:
		if GameState.weather_state == "storm" and _last_weather != "":
			state["dish"] = maxf(0.0, float(state["dish"]) - randf_range(0.25, 0.55))
			_dirty = true
			if float(state["dish"]) < 0.7:
				GameState.post_event("📡 Der Sturm hat die Schüssel auf dem Dach verstellt.", "warn")
		_last_weather = GameState.weather_state
	# Garten
	var gf: float = [0.9, 1.15, 0.6, 0.0][season_index()]
	for b in state["beds"]:
		if str(b["p"]) == "":
			continue
		if GameState.weather_state in ["rain", "storm"] and not is_winter():
			b["w"] = 1.0
		var w0 := float(b["w"])
		b["w"] = maxf(0.0, w0 - days / (0.5 if GameState.weather_state == "heatwave" else 0.9))
		var g0 := float(b["g"])
		if w0 > 0.05 and g0 < 1.0:
			b["g"] = minf(1.0, g0 + days * gf / float(PLANT_DAYS[b["p"]]))
		if int(g0 * 12.0) != int(float(b["g"]) * 12.0) or int(w0 * 5.0) != int(float(b["w"]) * 5.0):
			_dirty = true
		if is_winter() and float(b["g"]) < 1.0 and float(b["w"]) <= 0.0:
			b["p"] = ""
			_dirty = true
	_put("feed", maxf(0.0, float(state["feed"]) - days / 1.1), 0.08)
	if float(state["grill_t"]) > 0.0:
		state["grill_t"] = maxf(0.0, float(state["grill_t"]) - dt / maxf(0.1, GameState.clock_scale))
		if float(state["grill_t"]) <= 0.0:
			GameState.post_event("🍖 Das Essen auf dem Grill ist fertig!", "good")
			_dirty = true
	# Tor: nachts von allein zu, für Lieferungen auf
	var night := is_night()
	if bool(state["gate_auto"]) and night != _last_night and not _delivery_here():
		if bool(state["gate"]) != night:
			state["gate"] = night
			GameState._rpc_play_sfx.rpc("glass_door")
			broadcast()
	_last_night = night
	if bool(state["gate"]) and _delivery_here():
		state["gate"] = false
		GameState._rpc_play_sfx.rpc("glass_door")
		broadcast()


func _put(key: String, v: float, step: float) -> void:
	if int(float(state[key]) / step) != int(v / step):
		_dirty = true
	state[key] = v


func _run_day() -> void:
	var rep := 0.0
	if float(state["feed"]) > 0.05:
		rep += 0.4
	if int(state["grill_left"]) > 0:
		state["grill_left"] = 0
		_dirty = true
	for b in state["beds"]:
		if str(b["p"]) != "" and float(b["g"]) > 0.3:
			rep += 0.1
	if rep > 0.0 and GameState.reputation < 85.0:
		GameState.reputation = minf(85.0, GameState.reputation + rep)


## Das Tor wurde nachts aufgehebelt.
func force_gate_open() -> void:
	state["gate"] = false
	broadcast()
