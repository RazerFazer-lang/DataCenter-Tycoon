class_name SaveSchema
extends RefCounted
## Versionsnummer im Spielstand und genau eine Migration je Version.
##
## Jeder Spielstand speichert unter "schema" die Version, mit der er geschrieben wurde. Beim Laden laufen
## nur die Migrationen, die danach dazugekommen sind. Spielstände von vor v3.4 haben kein "schema",
## gelten als Version 0 und durchlaufen alle Migrationen.
##
## Neue Migration:
##   1. CURRENT um 1 erhöhen.
##   2. In STEPS einen Eintrag mit derselben Nummer anlegen.
##   3. Die Funktion in scripts/autoload/game_state/save_migrations.gd ergänzen (match in run()).
##   4. Einen Test in tests/save_schema_check.gd ergänzen.

const KEY := "schema"
const CURRENT := 7

## Nummer -> [Spielversion, Zeitpunkt, was passiert].
## Zeitpunkt "data": vor dem Einlesen, die Migration ändert nur die gelesenen Daten.
## Zeitpunkt "world": nach dem Einlesen, die Migration arbeitet mit der geladenen Welt.
const STEPS := {
	1: ["v0.3", "data", "Raumstufe aus dem alten Wert room_expanded"],
	2: ["v0.3", "world", "Spielstände ohne Rollwagen bekommen den Startwagen"],
	3: ["v2.6", "world", "Am Kasten oder Router montierte Leisten werden echte Leisten in Kisten"],
	4: ["v2.9", "world", "Festes Regal und 4er-Regale auf das neue Regalsystem"],
	5: ["v3.1", "world", "Kabel an Leisten auf Eingang und Ausgang umstecken"],
	6: ["v3.6", "world", "Das Halle-Nord-Aggregat bekommt einen echten Tank, gekaufte Aggregate starten voll"],
	7: ["v3.8", "world", "Neue Halle Nord: gekaufte Halle bekommt alle 3 Abschnitte, Geräte rücken auf freie Plätze"],
}


## Version eines gelesenen Spielstands. Fehlt sie oder ist sie unbrauchbar, ist es Version 0.
static func version_of(data: Dictionary) -> int:
	var v: Variant = data.get(KEY, 0)
	if not (v is int or v is float):
		return 0
	return maxi(0, int(v))


## Der Spielstand kommt aus einer neueren Spielversion (nach einem Downgrade).
static func is_newer(data: Dictionary) -> bool:
	return version_of(data) > CURRENT


## Nummern der Migrationen, die für diesen Spielstand und Zeitpunkt noch laufen müssen, aufsteigend.
static func pending(from_version: int, stage: String) -> Array[int]:
	var out: Array[int] = []
	for v in range(maxi(0, from_version) + 1, CURRENT + 1):
		if STEPS.has(v) and str((STEPS[v] as Array)[1]) == stage:
			out.append(v)
	return out


## Kurze Beschreibung für Logs und Tests.
static func describe(v: int) -> String:
	if not STEPS.has(v):
		return "Migration %d (unbekannt)" % v
	var s: Array = STEPS[v]
	return "Migration %d (%s): %s" % [v, str(s[0]), str(s[2])]
