class_name OutdoorPrompts
extends RefCounted
## Hinweise beim Anvisieren der Dinge im Außenbereich: [Haupttext, Zusatz].


static func prompt_for(id: String, kind: String) -> Array:
	var m := OutdoorManager
	var s: Dictionary = m.state
	if kind == "ladder":
		return [_t("[E] Leiter hinunterklettern") if id == "ladder_top" else _t("[E] Leiter hinaufklettern"), _t("W / S klettern, Leertaste lässt los")]
	if kind == "bench":
		return [_t("[E] Hinsetzen"), _t("Kurz ausruhen: Handgriffe gehen danach schneller von der Hand")]
	if id.begins_with("bed:"):
		return _bed(s["beds"][clampi(int(id.substr(4)), 0, 2)], s)
	match id:
		"gate":
			return [_t("[E] Zauntor öffnen") if bool(s["gate"]) else _t("[E] Zauntor schließen"), _t("[F] Nachts automatisch schließen: %s") % (_t("an") if bool(s["gate_auto"]) else _t("aus"))]
		"door":
			return [_t("[E] Hintertür schließen") if bool(s["door"]) else _t("[E] Hintertür öffnen"), ""]
		"lamps":
			return [_t("[E] Außenlicht ausschalten") if bool(s["lamps"]) else _t("[E] Außenlicht einschalten"), _t("Leuchtet nachts und schreckt Diebe ab")]
		"solar":
			if not bool(s["solar"]):
				return [_t("[E] Solaranlage aufbauen ($%d)") % int(m.SOLAR_PRICE), _t("Spart über den Tag rund 12 %% Strom") % []]
			var out := int(round(m.solar_output() * 100.0))
			if float(s["snow"]) > 0.1:
				return [_t("[E] Module freiräumen"), _t("Liefert gerade %d %%") % out]
			if float(s["solar_dirt"]) >= 0.05:
				return [_t("[E] Module putzen (Schmutz %d %%)") % int(round(float(s["solar_dirt"]) * 100.0)), _t("Liefert gerade %d %%") % out]
			return [_t("Solaranlage: sauber"), _t("Liefert gerade %d %%") % out]
		"dish":
			var q := int(round(float(s["dish"]) * 100.0))
			return [_t("[E] Schüssel nachstellen (Signal %d %%)") % q if q < 97 else _t("Schüssel: Signal %d %%") % q, _t("Gutes Signal bringt mehr Kunden (+4 %%)") % []]
		"station":
			var nxt := GameState.weather_next
			return [_t("Wetterstation: %s, %s") % [m.season_label(), GameState.get_weather_label()], _t("Warnt vor Gewitter und Hitze") if nxt == "" else _t("Als Nächstes: %s") % _weather(nxt)]
		"grill":
			if float(s["grill_t"]) > 0.0:
				return [_t("Brutzelt … noch %d s") % int(ceil(float(s["grill_t"]))), ""]
			if int(s["grill_left"]) > 0:
				return [_t("[E] Essen nehmen (%d übrig)") % int(s["grill_left"]), _t("Stärkung: schneller laufen und arbeiten")]
			return [_t("[E] Grillen ($%d)") % int(m.GRILL_COST), _t("Reicht für vier Portionen")]
		"feeder":
			var f := int(round(float(s["feed"]) * 100.0))
			return [_t("[E] Vogelfutter nachfüllen ($%d)") % int(m.FEED_COST) if f <= 80 else _t("Futterhaus ist voll"), _t("Lockt Vögel an und hebt den Ruf ein wenig (%d %%)") % f]
	return ["", ""]


static func _bed(b: Dictionary, s: Dictionary) -> Array:
	var m := OutdoorManager
	if str(b["p"]) == "":
		if m.is_winter():
			return [_t("Hochbeet (im Winter ruht es)"), ""]
		return [_t("[E] %s pflanzen ($%d)") % [_t(m.PLANT_NAMES[m.PLANTS[int(s["next_plant"])]]), int(m.SEED_COST)], _t("Gießen nicht vergessen")]
	var nm := _t(m.PLANT_NAMES[b["p"]])
	if float(b["g"]) >= 1.0:
		return [_t("[E] %s ernten (+$%d)") % [nm, int(m.PLANT_PAY[b["p"]])], ""]
	var st := _t("gewachsen %d %%, Wasser %d %%") % [int(float(b["g"]) * 100.0), int(float(b["w"]) * 100.0)]
	return [_t("[E] %s gießen") % nm if float(b["w"]) < 0.8 else nm, st]


static func _weather(w: String) -> String:
	match w:
		"cloudy":
			return _t("Bewölkt")
		"rain":
			return _t("Schnee") if OutdoorManager.is_winter() else _t("Regen")
		"storm":
			return _t("Schneesturm") if OutdoorManager.is_winter() else _t("Gewitter")
		"heatwave":
			return _t("Hitzewelle")
	return _t("Sonnig")


static func _t(k: String) -> String:
	return TranslationServer.translate(k)
