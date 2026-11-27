class_name PowerTariff
extends RefCounted
## Strompreis über den Tag (GAME-02): Nacht billig, Tag normal, Abendspitze teuer.
## Dazu ein Aufschlag auf die höchste Last des Tages (Leistungspreis). Der Arbeitspreis schwankt
## weiter von Tag zu Tag (GameState.electricity_rate), die Zonen sind Faktoren darauf.

## Zonen in Spielstunden [von, bis): Name, Faktor auf den Tagespreis.
const ZONES := [
	{"from": 0.0, "to": 6.0, "id": "night", "name": "Nachttarif", "mult": 0.70},
	{"from": 6.0, "to": 17.0, "id": "day", "name": "Tagtarif", "mult": 1.00},
	{"from": 17.0, "to": 22.0, "id": "peak", "name": "Abendspitze", "mult": 1.40},
	{"from": 22.0, "to": 24.0, "id": "night", "name": "Nachttarif", "mult": 0.70},
]
## Leistungspreis: $ je kW der höchsten Netzlast eines Tages.
const PEAK_CHARGE_PER_KW := 8.0
## Die Solaranlage deckt mittags bei klarem Himmel bis zu diesem Anteil der Last.
const PV_SHARE := 0.6
## Peak-Shaving: Unter dieser Ladung (Prozent) hält die USV ihre Energie für Ausfälle zurück.
const SHAVE_RESERVE := 40.0
## Sonne je Wetter (Faktor auf die Solarleistung).
const SUN_BY_WEATHER := {"clear": 1.0, "heatwave": 1.0, "cloudy": 0.5, "rain": 0.25, "storm": 0.1}


## Stunde 0..24 aus der Tageszeit 0..1.
static func hour_of(time_of_day: float) -> float:
	return fposmod(time_of_day, 1.0) * 24.0


static func zone_at(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	for z in ZONES:
		if h >= float(z["from"]) and h < float(z["to"]):
			return z
	return ZONES[0]


static func mult_at(hour: float) -> float:
	return float(zone_at(hour)["mult"])


static func is_peak(hour: float) -> bool:
	return str(zone_at(hour)["id"]) == "peak"


## Nächster Zonenwechsel: [Stunde, Zone]. Gleiche Zonen hintereinander zählen als eine.
static func next_change(hour: float) -> Array:
	var cur := str(zone_at(hour)["id"])
	var h := fposmod(hour, 24.0)
	for step in 48:
		var t := fposmod(floorf(h) + 1.0 + float(step), 24.0)
		var z := zone_at(t)
		if str(z["id"]) != cur:
			return [t, z]
	return [h, zone_at(h)]


## Sonnenstand 0..1 (Glockenkurve von 6 bis 20 Uhr, Spitze um 13 Uhr).
static func sun_at(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h <= 6.0 or h >= 20.0:
		return 0.0
	return pow(sin((h - 6.0) / 14.0 * PI), 1.4)


## Anteil der Last, den die Solaranlage gerade deckt (0..PV_SHARE).
static func solar_share(hour: float, weather: String) -> float:
	return PV_SHARE * sun_at(hour) * float(SUN_BY_WEATHER.get(weather, 0.6))
