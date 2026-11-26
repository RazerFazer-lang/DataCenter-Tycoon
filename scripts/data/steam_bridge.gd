class_name SteamBridge
extends RefCounted
## Schnittstelle zu Steam (REL-07), vorbereitet ohne Steam-Konto.
##
## Solange das GodotSteam-Plugin fehlt oder keine App-ID eingetragen ist, tut keine Funktion etwas.
## Später: GodotSteam (GDExtension) ins Projekt legen, APP_ID eintragen, fertig. Das Spiel ruft schon
## heute an den richtigen Stellen auf (Erfolge, Status für Freunde). Mehr in docs/steam/README.md.

## App-ID aus Steamworks. 0 = noch keine, dann bleibt Steam aus.
const APP_ID := 0

static var _is_ready := false
static var _init_tried := false


## Das Steam-Objekt von GodotSteam, oder null.
static func steam() -> Object:
	return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null


## Steam läuft und ist eingerichtet.
static func available() -> bool:
	if not _init_tried:
		init()
	return _is_ready


## Einmal beim Start. Gibt zurück, ob Steam bereit ist.
static func init() -> bool:
	if _init_tried:
		return _is_ready
	_init_tried = true
	var s := steam()
	if s == null or APP_ID <= 0:
		return false
	var res: Variant = s.call("steamInitEx", false, APP_ID)
	_is_ready = res is Dictionary and int((res as Dictionary).get("status", 1)) == 0
	if not _is_ready:
		push_warning("Steam nicht bereit: %s" % str(res))
	return _is_ready


## API-Name eines Erfolgs in Steamworks (so muss er dort angelegt werden).
static func achievement_api_name(id: String) -> String:
	return "ACH_" + id.to_upper()


## Meldet einen freigeschalteten Erfolg an Steam. Ohne Steam passiert nichts.
static func unlock_achievement(id: String) -> bool:
	if not available():
		return false
	var s := steam()
	s.call("setAchievement", achievement_api_name(id))
	s.call("storeStats")
	return true


## Status für die Freundesliste, z. B. "Im Rechenzentrum: Tag 12". Ohne Steam passiert nichts.
static func set_status(text: String) -> void:
	if not available():
		return
	steam().call("setRichPresence", "steam_display", "#Status")
	steam().call("setRichPresence", "status", text.left(64))


## Muss regelmäßig laufen, solange Steam aktiv ist (Rückrufe von Steam).
static func poll() -> void:
	if _is_ready:
		steam().call("run_callbacks")
