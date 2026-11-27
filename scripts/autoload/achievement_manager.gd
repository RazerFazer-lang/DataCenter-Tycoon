extends Node
## Erfolge (REL-07, zugleich GAME-11). Sie gehören dem Spieler, nicht der Welt, und gelten über alle
## Spielstände. Im Co-op schaltet jeder Spieler sie selbst frei, aus dem Weltzustand, den alle sehen.
## Gespeichert in user://achievements.cfg (eine kleine Datei im Spielerordner, Cloud-tauglich).
## Ist Steam eingerichtet, meldet SteamBridge jeden Erfolg auch dort (API-Name ACH_<ID>).

signal unlocked(id: String)

const SAVE_PATH := "user://achievements.cfg"
## Sekunden zwischen zwei Prüfungen des Weltzustands.
const CHECK_S := 2.0

## Reihenfolge = Anzeige. name und desc werden übersetzt (translations/strings.csv).
const LIST := {
	"first_rack": {"name": "Erstes Rack", "desc": "Stelle dein erstes Rack auf."},
	"first_server": {"name": "Es läuft!", "desc": "Ein Server läuft mit Strom und Netz."},
	"first_customer": {"name": "Erster Kunde", "desc": "Vermiete ein Rack an einen Kunden."},
	"contracts_5": {"name": "Vertragspartner", "desc": "Habe fünf Verträge gleichzeitig laufen."},
	"racks_10": {"name": "Serverraum", "desc": "Betreibe zehn Racks gleichzeitig."},
	"racks_25": {"name": "Rechenzentrum", "desc": "Betreibe 25 Racks gleichzeitig."},
	"compute_1000": {"name": "Tausend Recheneinheiten", "desc": "Erreiche 1.000 CU Rechenleistung."},
	"compute_10000": {"name": "Großrechner", "desc": "Erreiche 10.000 CU Rechenleistung."},
	"money_100k": {"name": "Sechsstellig", "desc": "Habe 100.000 $ auf dem Konto."},
	"money_1m": {"name": "Millionär", "desc": "Habe 1.000.000 $ auf dem Konto."},
	"level_3": {"name": "Mittelstand", "desc": "Erreiche Firmenstufe 3."},
	"level_5": {"name": "Etabliert", "desc": "Erreiche Firmenstufe 5."},
	"level_10": {"name": "Marktführer", "desc": "Erreiche Firmenstufe 10."},
	"research": {"name": "Forschergeist", "desc": "Erforsche deine erste Stufe."},
	"reputation_80": {"name": "Guter Ruf", "desc": "Bring den Ruf deiner Firma auf 80."},
	"halle_nord": {"name": "Ab in den Norden", "desc": "Kaufe Halle Nord."},
	"day_30": {"name": "Ein Monat Betrieb", "desc": "Halte dein Rechenzentrum 30 Tage am Laufen."},
	"fire_out": {"name": "Brandschutz", "desc": "Lösche einen Brand im Rechenzentrum."},
	"team": {"name": "Teamarbeit", "desc": "Spiele mit mindestens einem Mitspieler."},
}

## id -> Unix-Zeit der Freischaltung.
var done: Dictionary = {}
var _timer := 0.0
var _had_fire := false


func _ready() -> void:
	_load()
	SteamBridge.init()


func _process(delta: float) -> void:
	SteamBridge.poll()
	_timer += delta
	if _timer < CHECK_S:
		return
	_timer = 0.0
	# GAME-10: In der Sandbox zählen Erfolge nicht.
	if GameState.is_active and NetworkManager.is_in_session and not GameState.is_sandbox():
		check_now()


func is_unlocked(id: String) -> bool:
	return done.has(id)


func unlocked_count() -> int:
	return done.size()


## Prüft den Weltzustand und schaltet frei, was erfüllt ist. Gibt die neu freigeschalteten zurück.
func check_now() -> Array[String]:
	var got: Array[String] = []
	for id in LIST:
		if not done.has(id) and _condition(str(id)):
			unlock(str(id))
			got.append(str(id))
	return got


func unlock(id: String) -> void:
	if done.has(id) or not LIST.has(id):
		return
	done[id] = int(Time.get_unix_time_from_system())
	_save()
	SteamBridge.unlock_achievement(id)
	unlocked.emit(id)


func _condition(id: String) -> bool:
	var gs := GameState
	match id:
		"first_rack":
			return gs.racks.size() >= 1
		"first_server":
			for r in gs.racks.values():
				var rd := RackData.of(r)
				if rd.powered and rd.networked and not rd.used_slots().is_empty():
					return true
			return false
		"first_customer":
			for r in gs.racks.values():
				if not RackData.of(r).services.is_empty() or RackData.of(r).rental_type != "none":
					return true
			return false
		"contracts_5":
			return gs.get_active_contract_count() >= 5
		"racks_10":
			return gs.racks.size() >= 10
		"racks_25":
			return gs.racks.size() >= 25
		"compute_1000":
			return gs.total_compute >= 1000
		"compute_10000":
			return gs.total_compute >= 10000
		"money_100k":
			return gs.money >= 100000.0
		"money_1m":
			return gs.money >= 1000000.0
		"level_3":
			return gs.company_level >= 3
		"level_5":
			return gs.company_level >= 5
		"level_10":
			return gs.company_level >= 10
		"research":
			for v in gs.research_levels.values():
				if int(v) > 0:
					return true
			return false
		"reputation_80":
			return gs.reputation >= 80.0
		"halle_nord":
			return gs.halle_nord_owned
		"day_30":
			return gs.day_number >= 30
		"fire_out":
			# Ein Brand war da und ist jetzt aus.
			var fire := gs.has_any_fire()
			var out := _had_fire and not fire
			_had_fire = fire
			return out
		"team":
			return NetworkManager.players.size() >= 2
	return false


func _load() -> void:
	done.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in cfg.get_section_keys("unlocked") if cfg.has_section("unlocked") else PackedStringArray():
		if LIST.has(id):
			done[id] = int(cfg.get_value("unlocked", id, 0))


func _save() -> void:
	var cfg := ConfigFile.new()
	for id in done:
		cfg.set_value("unlocked", id, done[id])
	cfg.save(SAVE_PATH)


## Nur für Tests: alles vergessen (die Datei bleibt bis zum nächsten Freischalten).
func reset_for_test() -> void:
	done.clear()
	_had_fire = false
