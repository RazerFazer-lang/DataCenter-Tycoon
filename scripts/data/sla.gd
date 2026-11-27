class_name Sla
extends RefCounted
## SLA-Stufen für Verträge und Kundenbewertungen (GAME-05).
## Je höher die Stufe, desto mehr zahlt der Kunde, desto härter die Strafe und desto mehr Verfügbarkeit
## verspricht man. Gold bekommt nur, wer schon gute Bewertungen hat.

const TIERS := {
	"bronze": {"name": "Bronze", "target": 0.95, "pay": 1.0, "penalty": 1.0, "min_stars": 0.0},
	"silver": {"name": "Silber", "target": 0.99, "pay": 1.25, "penalty": 2.0, "min_stars": 3.0},
	"gold": {"name": "Gold", "target": 0.999, "pay": 1.6, "penalty": 3.5, "min_stars": 4.0},
}
const ORDER: Array[String] = ["bronze", "silver", "gold"]
## Gleitendes Fenster: Jeder Zahlungstakt zählt, ältere verblassen (Faktor je Takt).
const DECAY := 0.985
## So viele Bewertungen bleiben gespeichert, der Schnitt nimmt die letzten davon.
const REVIEWS_MAX := 30
const REVIEWS_AVG := 20
## Ohne Bewertungen gilt dieser Schnitt.
const START_STARS := 3.5


static func tier(c: Dictionary) -> Dictionary:
	return TIERS.get(str(c.get("sla", "bronze")), TIERS["bronze"])


static func tier_id(c: Dictionary) -> String:
	var t := str(c.get("sla", "bronze"))
	return t if TIERS.has(t) else "bronze"


## Gemessene Verfügbarkeit 0..1 (1.0, solange noch nichts gemessen ist).
static func availability(c: Dictionary) -> float:
	var n := float(c.get("sla_n", 0.0))
	if n < 0.5:
		return 1.0
	return clampf(float(c.get("sla_ok", 0.0)) / n, 0.0, 1.0)


## Ein Zahlungstakt: versorgt oder nicht.
static func record(c: Dictionary, ok: bool) -> void:
	c["sla_ok"] = float(c.get("sla_ok", 0.0)) * DECAY + (1.0 if ok else 0.0)
	c["sla_n"] = float(c.get("sla_n", 0.0)) * DECAY + 1.0


static func is_breached(c: Dictionary) -> bool:
	return float(c.get("sla_n", 0.0)) >= 3.0 and availability(c) < float(tier(c)["target"])


## Sterne für den Kunden am Ende: Hält man das Versprechen, gibt es 5, knapp daneben 4, sonst weniger.
static func stars_for(c: Dictionary) -> int:
	var gap := float(tier(c)["target"]) - availability(c)
	if gap <= 0.0:
		return 5
	if gap <= 0.02:
		return 4
	if gap <= 0.06:
		return 3
	if gap <= 0.15:
		return 2
	return 1


static func average(reviews: Array) -> float:
	if reviews.is_empty():
		return START_STARS
	var n := 0
	var sum := 0.0
	for i in range(reviews.size() - 1, -1, -1):
		var r: Variant = reviews[i]
		if r is Dictionary:
			sum += float((r as Dictionary).get("stars", 3))
			n += 1
		if n >= REVIEWS_AVG:
			break
	return sum / float(n) if n > 0 else START_STARS


static func stars_text(stars: float) -> String:
	var full := clampi(int(roundf(stars)), 0, 5)
	return "★".repeat(full) + "☆".repeat(5 - full)
