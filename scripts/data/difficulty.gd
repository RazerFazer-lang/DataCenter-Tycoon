class_name Difficulty
extends RefCounted
## Schwierigkeitsgrade (GAME-10). Gewählt beim neuen Spiel, später im Admin-Menü änderbar.
## Die Werte sind Faktoren auf das normale Spiel (1.0 = wie bisher).

const LEVELS := {
	"easy": {
		"name": "Leicht", "desc": "Mehr Startgeld, höhere Einnahmen, niedrigere Kosten, seltener Ausfälle und Zwischenfälle.",
		"start_money": 4000.0, "revenue": 1.25, "costs": 0.75, "failures": 0.6, "events": 0.6,
	},
	"normal": {
		"name": "Normal", "desc": "Das Spiel, wie es gedacht ist.",
		"start_money": 1800.0, "revenue": 1.0, "costs": 1.0, "failures": 1.0, "events": 1.0,
	},
	"hard": {
		"name": "Schwer", "desc": "Weniger Startgeld, knappere Einnahmen, höhere Kosten, häufiger Ausfälle und Angriffe.",
		"start_money": 1200.0, "revenue": 0.85, "costs": 1.25, "failures": 1.4, "events": 1.4,
	},
	"sandbox": {
		"name": "Sandbox", "desc": "Unendlich Geld, alles freigeschaltet, keine Rechnungen. Erfolge zählen hier nicht.",
		"start_money": 9999999.0, "revenue": 1.0, "costs": 0.0, "failures": 1.0, "events": 1.0,
	},
}
const ORDER: Array[String] = ["easy", "normal", "hard", "sandbox"]
const DEFAULT := "normal"
## So viel Geld hält die Sandbox immer bereit.
const SANDBOX_MONEY := 9999999.0


static func valid(level: String) -> String:
	return level if LEVELS.has(level) else DEFAULT


## Faktor eines Schwierigkeitsgrads: "revenue", "costs", "failures" oder "events".
static func mult(level: String, key: String) -> float:
	return float((LEVELS[valid(level)] as Dictionary).get(key, 1.0))


static func display_name(level: String) -> String:
	return str((LEVELS[valid(level)] as Dictionary)["name"])


static func is_sandbox(level: String) -> bool:
	return level == "sandbox"
