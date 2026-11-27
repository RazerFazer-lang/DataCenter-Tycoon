class_name OperationsApp
extends RefCounted
## PC-App „Betrieb“: Strompreis über den Tag (GAME-02), Notstrom und Redundanz (GAME-01),
## Fernwärme (GAME-08) und Zertifizierungen (GAME-09). Daten aus GameState und Operations.
## state: {"tab": "power", "msg": "", "ok": true}

const T := preload("res://scripts/ui/finance_apps.gd")
const TABS := [["power", "Strom & Tarif"], ["backup", "Notstrom"], ["heat", "Fernwärme"], ["certs", "Zertifikate"]]
const ZONE_COL := {"night": Color(0.20, 0.55, 0.35), "day": Color(0.20, 0.45, 0.80), "peak": Color(0.82, 0.25, 0.18)}


static func render(host: Control, state: Dictionary, refresh: Callable) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	host.add_child(bar)
	var tab := str(state.get("tab", "power"))
	for t in TABS:
		var tid := str(t[0])
		var sel := tab == tid
		var b := Button.new()
		b.text = T._t(str(t[1]))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		MailApp._flat(b, T.COL_ACCENT if sel else Color(0.90, 0.92, 0.95), T.COL_ACCENT if sel else Color(0.84, 0.87, 0.91), Color.WHITE if sel else T.COL_TEXT)
		b.pressed.connect(func():
			state["tab"] = tid
			state["msg"] = ""
			SfxManager.play("click", -12.0, 1.1)
			refresh.call()
		)
		bar.add_child(b)
	var body := T._scroll_body(host)
	T._feedback_bar(body, str(state.get("msg", "")), bool(state.get("ok", true)))
	match tab:
		"power":
			_power(body)
		"backup":
			_backup(body)
		"heat":
			_heat(body)
		"certs":
			_certs(body)


static func _f(v: float, digits: int = 1) -> String:
	return String.num(v, digits).replace(".", ",") if TranslationServer.get_locale().begins_with("de") else String.num(v, digits)


# ---------------------------------------------------------------- Strom & Tarif

static func _power(body: VBoxContainer) -> void:
	var hour := PowerTariff.hour_of(GameState.time_of_day)
	var zone := PowerTariff.zone_at(hour)
	var rate := GameState.electricity_rate * float(zone["mult"])
	T._header(body, "power", T._t("Strom & Tarif"), T._t("Nachts billig, tagsüber normal, in der Abendspitze teuer. Dazu zahlt jeder Tag seine höchste Netzlast."))
	T._stat_tiles(body, [
		[T._t("Jetzt: %s") % T._t(str(zone["name"])), "$%s/kWh" % _f(rate, 2), ZONE_COL.get(str(zone["id"]), T.COL_TEXT)],
		[T._t("Netzbezug jetzt"), "%s kW" % _f(GameState.grid_kw_now), T.COL_TEXT],
		[T._t("Spitze heute"), "%s kW" % _f(GameState.daily_peak_kw), T.COL_WARN if GameState.daily_peak_kw > 0.0 else T.COL_TEXT],
		[T._t("Rechnung bis jetzt"), T._money(float(GameState.get_estimated_daily_bill())), T.COL_TEXT],
	])
	# Tagesband
	var card := T._card(body)
	card.add_child(T._label(T._t("Tarif über den Tag"), 14, T.COL_TEXT))
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 2)
	card.add_child(band)
	for h in 24:
		var z := PowerTariff.zone_at(float(h) + 0.5)
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(0, 22 if h == int(hour) else 14)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_SHRINK_END
		cell.color = ZONE_COL.get(str(z["id"]), T.COL_MUTED)
		if h != int(hour):
			cell.color = cell.color.lerp(Color.WHITE, 0.35)
		cell.tooltip_text = "%02d:00  %s ×%s" % [h, T._t(str(z["name"])), _f(float(z["mult"]), 2)]
		band.add_child(cell)
	var marks := HBoxContainer.new()
	card.add_child(marks)
	for txt in ["0", "6", "12", "17", "22", "24"]:
		var l := T._label(txt + ":00", 11, T.COL_MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		marks.add_child(l)
	var nxt := PowerTariff.next_change(hour)
	card.add_child(T._label(T._t("Ab %02d:00 gilt %s (×%s).") % [int(nxt[0]), T._t(str((nxt[1] as Dictionary)["name"])), _f(float((nxt[1] as Dictionary)["mult"]), 2)], 12, T.COL_MUTED, true))
	card.add_child(T._label(T._t("Grundpreis heute $%s/kWh. Leistungspreis $%d je kW Tagesspitze, heute bisher %s.") % [
		_f(GameState.electricity_rate, 2), int(PowerTariff.PEAK_CHARGE_PER_KW), T._money(GameState.daily_peak_kw * PowerTariff.PEAK_CHARGE_PER_KW)], 12, T.COL_MUTED, true))
	# Solar
	var sol := T._card(body, T.COL_GOOD if GameState.has_building_upgrade("upg_pv_solar") else Color(0, 0, 0, 0))
	if GameState.has_building_upgrade("upg_pv_solar"):
		sol.add_child(T._label(T._t("Solaranlage deckt gerade %s kW.") % _f(GameState.solar_kw_now), 14, T.COL_TEXT))
		sol.add_child(T._label(T._t("Mittags bei klarem Himmel bis %d %% der Last, bei Wolken und Regen weniger, nachts nichts.") % int(PowerTariff.PV_SHARE * 100.0), 12, T.COL_MUTED, true))
	else:
		sol.add_child(T._label(T._t("Keine Solaranlage. Die PV-Anlage gibt es in der App Gebäude, sie senkt vor allem den teuren Tagstrom."), 12, T.COL_MUTED, true))
	# Peak-Shaving
	var ups_n := 0
	for uid in GameState.ups_units.keys():
		if bool((GameState.ups_units[uid] as Dictionary).get("connected", false)):
			ups_n += 1
	var ps := T._card(body, T.COL_ACCENT if Operations.peak_shaving else Color(0, 0, 0, 0))
	ps.add_child(T._label(T._t("Abendspitze mit der USV kappen"), 15, T.COL_TEXT))
	ps.add_child(T._label(T._t("Von 17 bis 22 Uhr gibt die USV Strom ab, solange sie über %d %% geladen ist, und lädt danach zum günstigeren Preis nach. Senkt Arbeitspreis und Tagesspitze, nutzt aber die Akkus ab.") % int(PowerTariff.SHAVE_RESERVE), 12, T.COL_MUTED, true))
	if Operations.peak_shaving and GameState.shave_kw_now > 0.0:
		ps.add_child(T._label(T._t("Gerade gekappt: %s kW") % _f(GameState.shave_kw_now), 13, T.COL_GOOD))
	var on := Operations.peak_shaving
	var btn := T._button(T._t("Ausschalten") if on else T._t("Einschalten"), T.COL_MUTED if on else T.COL_ACCENT,
		func(): Operations.request_set_peak_shaving(not on), ups_n > 0 or on)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	ps.add_child(btn)
	if ups_n == 0:
		ps.add_child(T._label(T._t("Dafür braucht es eine angeschlossene USV."), 12, T.COL_WARN, true))


# ---------------------------------------------------------------- Notstrom

static func _backup(body: VBoxContainer) -> void:
	var lvl := Operations.redundancy_level()
	T._header(body, "power", T._t("Notstrom & Redundanz"), T._t("Bei Netzausfall überbrückt die USV, bis das Aggregat nach einigen Sekunden anspringt."))
	var lvl_col := T.COL_GOOD if lvl == "2N" else (T.COL_ACCENT if lvl == "N+1" else T.COL_BAD)
	T._stat_tiles(body, [
		[T._t("Redundanz"), lvl, lvl_col],
		[T._t("Diesel"), "%d / %d l" % [int(Operations.fuel_total()), int(Operations.tank_capacity())], T.COL_TEXT],
		[T._t("USV-Ladung"), "%d %%" % int(GameState.avg_ups_charge), T.COL_TEXT],
		[T._t("Last"), "%s kW" % _f(float(GameState.total_watts) / 1000.0), T.COL_TEXT],
	])
	var ex := T._card(body)
	ex.add_child(T._label(T._t("N: nur Netz, ein Ausfall legt alles lahm.  N+1: USV oder Aggregat fängt Ausfälle ab.  2N: USV und Aggregat mit Diesel, und jedes Rack hängt an zwei Stromkabeln (A+B). 2N zählt für die Tier-III-Prüfung."), 12, T.COL_MUTED, true))
	if GameState.grid_outage_left > 0.0:
		var oc := T._card(body, T.COL_BAD)
		oc.add_child(T._label(T._t("Netzausfall, noch etwa %d Min.") % GameState.get_grid_outage_minutes(), 15, T.COL_BAD))
		oc.add_child(T._label(T._t("Strom kommt gerade vom Aggregat.") if GameState.on_generator else (T._t("Strom kommt gerade aus der USV.") if GameState.ups_backup_active else T._t("Kein Notstrom: Alles steht.")), 13, T.COL_TEXT, true))
	T._section(body, T._t("Aggregate"))
	var gens := Operations.generators()
	if gens.is_empty():
		var nc := T._card(body)
		nc.add_child(T._label(T._t("Noch kein Aggregat. Das Notstromaggregat 40 kVA gibt es im Shop unter Einrichtung, es steht auf dem Rasen rechts vom Tor. An Halle Nord gibt es das große Aggregat als Gebäude-Ausbau."), 12, T.COL_MUTED, true))
	for gen in gens:
		var running := bool(gen["running"])
		var starting := float(gen["starting"]) > 0.0
		var fuel := float(gen["fuel"])
		var gc := T._card(body, T.COL_GOOD if running else (T.COL_WARN if starting else (T.COL_BAD if fuel <= 0.0 else T.COL_ACCENT)))
		var top := HBoxContainer.new()
		gc.add_child(top)
		var nm := T._label(T._t(str(gen["name"])), 15, T.COL_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var st := T._t("läuft") if running else (T._t("startet (%d s)") % ceili(float(gen["starting"])) if starting else (T._t("Tank leer") if fuel <= 0.0 else T._t("bereit")))
		top.add_child(T._label(st, 13, T.COL_TEXT))
		gc.add_child(T._bar(fuel / maxf(1.0, float(gen["tank"])), T.COL_GOOD if fuel > float(gen["tank"]) * 0.25 else T.COL_WARN))
		var spec: Dictionary = Operations.GEN_SPECS[str(gen["kind"])]
		gc.add_child(T._label(T._t("%d von %d l  •  bis %d kW  •  springt nach %d s an  •  %s l je kWh") % [
			int(fuel), int(float(gen["tank"])), int(float(gen["kw"])), int(spec["start_s"]), _f(float(spec["l_per_kwh"]), 2)], 12, T.COL_MUTED, true))
		var load_kw := float(GameState.total_watts) / 1000.0
		if load_kw > float(gen["kw"]):
			gc.add_child(T._label(T._t("Die Last (%s kW) ist größer als das Aggregat. Bei Ausfall schaltet es ab.") % _f(load_kw), 12, T.COL_BAD, true))
	if not gens.is_empty():
		T._section(body, T._t("Diesel bestellen"))
		var oc2 := T._card(body)
		var room := Operations.tank_capacity() - Operations.fuel_total() - Operations.fuel_ordered()
		oc2.add_child(T._label(T._t("$%s je Liter. Der Tankwagen kommt nach gut einer Minute und füllt die Tanks. Platz noch für %d l.") % [_f(Operations.DIESEL_PRICE, 2), int(maxf(room, 0.0))], 12, T.COL_MUTED, true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		oc2.add_child(row)
		for l in Operations.ORDER_SIZES:
			var liters: int = l
			var cost := float(liters) * Operations.DIESEL_PRICE
			row.add_child(T._button("%d l  %s" % [liters, T._money(cost)], T.COL_ACCENT, func(): Operations.request_order_diesel(liters),
				float(liters) <= room + 0.5 and GameState.money >= cost))
		for o in Operations.fuel_orders:
			oc2.add_child(T._label(T._t("Unterwegs: %d l, noch %d s") % [int(float(o["l"])), ceili(float(o["t"]))], 12, T.COL_TEXT))


# ---------------------------------------------------------------- Fernwärme (GAME-08)

const SEASONS := ["Frühling", "Sommer", "Herbst", "Winter"]


static func _heat(body: VBoxContainer) -> void:
	T._header(body, "temp", T._t("Fernwärme"), T._t("Die Racks machen Wärme. Mit einer Übergabestation geht sie ins Fernwärmenetz der Stadt und bringt Geld. Im Winter brauchen die Leute mehr davon."))
	var season := clampi(OutdoorManager.season_index(), 0, 3)
	var demand := Operations.heat_demand()
	if not Operations.has_heat():
		T._stat_tiles(body, [
			[T._t("Jahreszeit"), T._t(str(SEASONS[season])), T.COL_TEXT],
			[T._t("Nachfrage"), "×%s" % _f(demand, 2), T.COL_TEXT],
			[T._t("Möglich jetzt"), "%s kW" % _f(float(GameState.total_watts) / 1000.0 * Operations.HEAT_RECOVERY), T.COL_MUTED],
		])
		var nc := T._card(body, T.COL_ACCENT)
		nc.add_child(T._label(T._t("Noch nicht angeschlossen. Die Fernwärme-Übergabestation gibt es als Ausbau in der App Gebäude."), 13, T.COL_TEXT, true))
		nc.add_child(T._label(T._t("Bezahlt werden %s je kWh Wärme, mal die Nachfrage der Jahreszeit. Etwa zwei Drittel der Serverleistung kommen als Wärme an.") % ("$" + _f(Operations.HEAT_PRICE, 2)), 12, T.COL_MUTED, true))
		return
	var kw := Operations.heat_kw_now()
	var per_day := kw * 24.0 * Operations.HEAT_PRICE * demand * GameState.diff("revenue")
	T._stat_tiles(body, [
		[T._t("Wärme jetzt"), "%s kW" % _f(kw), T.COL_GOOD if kw > 0.0 else T.COL_MUTED],
		[T._t("Jahreszeit"), "%s  ×%s" % [T._t(str(SEASONS[season])), _f(demand, 2)], T.COL_GOOD if demand > 1.0 else (T.COL_WARN if demand < 1.0 else T.COL_TEXT)],
		[T._t("Heute"), "%d kWh  •  %s" % [int(Operations.heat_kwh_today), T._money(Operations.heat_money_today)], T.COL_TEXT],
		[T._t("Bisher gesamt"), T._money(Operations.heat_money_total), T.COL_GOOD],
	])
	var c := T._card(body)
	c.add_child(T._label(T._t("Bei dieser Last bringt die Fernwärme etwa %s am Tag. Abgerechnet wird um Mitternacht, dazu gibt es etwas Ruf.") % T._money(per_day), 13, T.COL_TEXT, true))
	c.add_child(T._label(T._t("Mehr Server heißt mehr Wärme. Im Sommer kauft die Stadt nur gut ein Drittel, im Winter das 1,6-Fache."), 12, T.COL_MUTED, true))
	T._section(body, T._t("Nachfrage im Jahr"))
	var yc := T._card(body)
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		yc.add_child(row)
		var nm := T._label(T._t(str(SEASONS[i])), 13, T.COL_ACCENT if i == season else T.COL_TEXT)
		nm.custom_minimum_size = Vector2(90, 0)
		row.add_child(nm)
		var b := T._bar(float(Operations.HEAT_DEMAND[i]) / 1.6, T.COL_ACCENT if i == season else T.COL_MUTED)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		row.add_child(T._label("×%s" % _f(float(Operations.HEAT_DEMAND[i]), 2), 12, T.COL_MUTED))


# ---------------------------------------------------------------- Zertifikate (GAME-09)

static func _certs(body: VBoxContainer) -> void:
	T._header(body, "flag", T._t("Zertifikate"), T._t("Ein Prüfer kommt vorbei und geht durch die Anlage. Wer besteht, bekommt ein Spieljahr lang höhere Mieten und Vertragseinnahmen."))
	var a: Dictionary = Operations.audit
	T._stat_tiles(body, [
		[T._t("Einnahmen-Bonus"), "×%s" % _f(Operations.cert_mult(), 2), T.COL_GOOD if Operations.cert_mult() > 1.0 else T.COL_MUTED],
		[T._t("Gültig"), "%d / %d" % [Operations.CERT_ORDER.filter(func(x): return Operations.cert_valid(x)).size(), Operations.CERT_ORDER.size()], T.COL_TEXT],
		[T._t("Prüfung"), (T._t("Prüfer unterwegs") if str(a["phase"]) == "wait" else T._t("Prüfer vor Ort")) if not a.is_empty() else T._t("keine"), T.COL_WARN if not a.is_empty() else T.COL_TEXT],
	])
	if not a.is_empty():
		var ac := T._card(body, T.COL_WARN)
		var nm0 := T._t(str(Operations.CERTS[str(a["cert"])]["name"]))
		ac.add_child(T._label((T._t("Der Prüfer für „%s“ kommt in %d s.") if str(a["phase"]) == "wait" else T._t("Der Prüfer für „%s“ geht durch die Anlage, noch %d s. Gezählt wird, was am Ende stimmt.")) % [nm0, ceili(float(a["t"]))], 13, T.COL_TEXT, true))
	for id in Operations.CERT_ORDER:
		var spec: Dictionary = Operations.CERTS[id]
		var valid := Operations.cert_valid(id)
		var info: Dictionary = Operations.certs.get(id, {})
		var checks := Operations.cert_checks(id)
		var ready := true
		for chk in checks:
			ready = ready and bool(chk[1])
		var card := T._card(body, T.COL_GOOD if valid else (T.COL_ACCENT if ready else Color(0, 0, 0, 0)))
		var top := HBoxContainer.new()
		card.add_child(top)
		var nm := T._label(T._t(str(spec["name"])), 15, T.COL_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		if valid:
			top.add_child(T._label(T._t("gültig bis Tag %d") % int(info.get("valid_until", 0)), 13, T.COL_GOOD))
		elif bool(info.get("passed", false)):
			top.add_child(T._label(T._t("abgelaufen"), 13, T.COL_WARN))
		card.add_child(T._label(T._t(str(spec["desc"])) + "  " + T._t("Bonus ×%s auf Mieten und Verträge.") % _f(float(spec["mult"]), 2), 12, T.COL_MUTED, true))
		for chk in checks:
			var ok := bool(chk[1])
			card.add_child(T._label(("✓  " if ok else "✗  ") + T._t(str(chk[0])), 13, T.COL_GOOD if ok else T.COL_BAD, true))
		var failed: Array = info.get("last", [])
		if not valid and not failed.is_empty():
			card.add_child(T._label(T._t("Letzte Prüfung (Tag %d) nicht bestanden.") % int(info.get("last_day", 0)), 12, T.COL_WARN, true))
		var fee := float(spec["fee"]) * maxf(GameState.diff("costs"), 0.0)
		var cid: String = id
		var label := T._t("Prüfung beantragen (%s)") % T._money(fee) if not valid else T._t("Früher neu prüfen (%s)") % T._money(fee)
		var btn := T._button(label, T.COL_ACCENT if ready else T.COL_MUTED, func(): Operations.request_audit(cid), a.is_empty() and GameState.money >= fee)
		card.add_child(btn)
		if not ready:
			card.add_child(T._label(T._t("Es fehlen noch Punkte. Du kannst trotzdem prüfen lassen und bis zum Ende der Begehung nachbessern."), 11, T.COL_MUTED, true))
