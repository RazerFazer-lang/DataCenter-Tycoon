extends Node
## Dedizierter Server für Windows. Hostet einen Spielstand ohne Hauptmenü und ohne
## eigene Spielerfigur und nimmt Befehle aus der Konsole an.
## Start neben der EXE: DataCenterTycoon.console.exe --headless -- --server
## Optional: --server-config=C:\Pfad\server.cfg (Standard: user://server.cfg)

const DEFAULT_CONFIG_PATH := "user://server.cfg"
const CONFIG_ARG := "--server-config="
const SECTION := "server"
const DEFAULT_NAME := "DataCenter Server"
const DEFAULT_WORLD := "Server DataCenter"
const STDIN_BUFFER := 1024
const MIN_ADMIN_PW := 6
const STOP_COMMANDS: Array[String] = ["stop", "quit", "exit"]

var _port: int = 0
var _stdin_thread: Thread = null
var _stopping: bool = false


static func _cmdline() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	return args


static func is_requested() -> bool:
	return _cmdline().has("--server")


func _ready() -> void:
	var path := _config_path()
	var cfg := _load_config(path)
	if cfg == null:
		get_tree().quit(1)
		return

	var server_name := str(cfg.get_value(SECTION, "name", DEFAULT_NAME)).strip_edges().left(18)
	if server_name.is_empty():
		server_name = DEFAULT_NAME
	_port = int(cfg.get_value(SECTION, "port", NetworkManager.DEFAULT_PORT))
	if _port <= 1024 or _port >= 65535:
		_log("Port %d ist ungültig, nutze %d." % [_port, NetworkManager.DEFAULT_PORT])
		_port = NetworkManager.DEFAULT_PORT
	var password := str(cfg.get_value(SECTION, "password", "")).strip_edges()
	var world_name := str(cfg.get_value(SECTION, "world", DEFAULT_WORLD)).strip_edges().left(32)
	if world_name.is_empty():
		world_name = DEFAULT_WORLD
	var use_upnp := bool(cfg.get_value(SECTION, "upnp", true))
	AdminManager.server_password = str(cfg.get_value(SECTION, "admin_password", "")).strip_edges().left(64)
	if AdminManager.server_password != "" and AdminManager.server_password.length() < MIN_ADMIN_PW:
		_log("admin_password ist zu kurz (mindestens %d Zeichen) und wird ignoriert." % MIN_ADMIN_PW)
		AdminManager.server_password = ""

	# Gilt nur für diese Sitzung, die settings.cfg bleibt unverändert.
	SettingsManager.autosave_enabled = true

	NetworkManager.connection_failed.connect(_on_host_failed)
	NetworkManager.port_forward_finished.connect(_on_port_forward_finished)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	GameState.world_saved.connect(_on_world_saved)

	_log("Konfiguration: %s" % ProjectSettings.globalize_path(path))
	_log("Starte '%s' auf UDP-Port %d mit Welt '%s' ..." % [server_name, _port, world_name])
	var err := NetworkManager.host_dedicated(server_name, _port, world_name, password, use_upnp)
	if err != OK:
		_log("Start fehlgeschlagen (Fehler %d)." % err)
		get_tree().quit(1)
		return

	_log("Server läuft. Spielstand: %s" % ProjectSettings.globalize_path(SaveManager.get_save_path(GameState.current_save_id)))
	_log("Passwort: %s | Plätze: %d | Autosave aktiv" % ["an" if not password.is_empty() else "aus", NetworkManager.MAX_PLAYERS])
	_log("Admin-Anmeldung im Spiel [F10]: %s" % ("an" if AdminManager.server_password != "" else "aus (admin_password in der server.cfg eintragen)"))
	_log("Befehle: help, status, players, admin <ID|Name>, unadmin <ID|Name>, kick <ID|Name>, save, stop")
	_start_console()


func _notification(what: int) -> void:
	# Fenster oder Konsole wird geschlossen: vorher noch speichern.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _stopping:
		_stopping = true
		GameState.save_current_world()


func _exit_tree() -> void:
	# Ein noch blockierender Lesethread wird nicht abgewartet, sonst hängt das Beenden.
	if _stdin_thread != null and not _stdin_thread.is_alive():
		_stdin_thread.wait_to_finish()
	_stdin_thread = null


# --- Konfiguration ----------------------------------------------------------

func _config_path() -> String:
	for raw in _cmdline():
		var a := str(raw).strip_edges()
		if a.begins_with(CONFIG_ARG):
			var p := a.substr(CONFIG_ARG.length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
			if not p.is_empty():
				return p
	return DEFAULT_CONFIG_PATH


func _load_config(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path):
		cfg.set_value(SECTION, "name", DEFAULT_NAME)
		cfg.set_value(SECTION, "port", NetworkManager.DEFAULT_PORT)
		cfg.set_value(SECTION, "password", "")
		cfg.set_value(SECTION, "admin_password", Crypto.new().generate_random_bytes(6).hex_encode())
		cfg.set_value(SECTION, "world", DEFAULT_WORLD)
		cfg.set_value(SECTION, "upnp", true)
		var save_err := cfg.save(path)
		if save_err != OK:
			_log("server.cfg konnte nicht angelegt werden (Fehler %d), nutze Standardwerte." % save_err)
		else:
			_log("Neue server.cfg mit Standardwerten und zufälligem Admin-Passwort angelegt.")
		return cfg
	var err := cfg.load(path)
	if err != OK:
		_log("server.cfg ist fehlerhaft (Fehler %d): %s" % [err, ProjectSettings.globalize_path(path)])
		return null
	return cfg


# --- Konsole ----------------------------------------------------------------

func _start_console() -> void:
	_stdin_thread = Thread.new()
	_stdin_thread.start(_read_stdin)


## Läuft im Hintergrund-Thread, weil das Lesen blockiert, bis Eingabe kommt.
## Ein Aufruf kann mehrere Zeilen oder nur einen Teil einer Zeile liefern.
func _read_stdin() -> void:
	var pending := ""
	while true:
		var raw := OS.read_string_from_stdin(STDIN_BUFFER)
		if raw.is_empty():
			# Keine Konsole oder Eingabe beendet: eine angefangene letzte Zeile noch ausführen.
			var last := pending.strip_edges()
			if not last.is_empty():
				_handle_command.call_deferred(last)
			return
		var chunk := raw.replace("\r", "")
		pending += chunk
		# Konsole und Pipe liefern unter Windows je Aufruf eine Zeile ohne Umbruch,
		# eine umgeleitete Datei liefert den ganzen Puffer mit Umbrüchen.
		if not chunk.contains("\n"):
			pending += "\n"
		var lines := pending.split("\n")
		pending = lines[lines.size() - 1]
		for i in range(lines.size() - 1):
			var line := lines[i].strip_edges()
			if line.is_empty():
				continue
			_handle_command.call_deferred(line)
			if STOP_COMMANDS.has(line.to_lower()):
				return


func _handle_command(line: String) -> void:
	if line.is_empty():
		return
	var parts := line.split(" ", false, 1)
	var cmd := parts[0].to_lower()
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match cmd:
		"help":
			_log("help | status | players | admin <ID|Name> | unadmin <ID|Name> | kick <ID|Name> | save | stop")
		"status":
			_print_status()
		"players", "list":
			_print_players()
		"kick":
			_kick(arg)
		"admin":
			_set_admin(arg, true)
		"unadmin":
			_set_admin(arg, false)
		"save":
			var result := GameState.save_current_world()
			if not bool(result.get("ok", false)):
				_log("Speichern fehlgeschlagen: %s" % str(result.get("error", "unbekannt")))
		"stop", "quit", "exit":
			stop_server()
		_:
			_log("Unbekannter Befehl '%s'. 'help' zeigt alle Befehle." % cmd)


func _print_status() -> void:
	_log("Welt '%s' | Tag %d | $%.0f | %d/%d Spieler | Port %d" % [
		GameState.current_save_name,
		GameState.day_number,
		GameState.money,
		NetworkManager.players.size(),
		NetworkManager.MAX_PLAYERS,
		_port,
	])


func _print_players() -> void:
	if NetworkManager.players.is_empty():
		_log("Keine Spieler verbunden.")
		return
	for pid in NetworkManager.players.keys():
		var info: Dictionary = NetworkManager.players[pid]
		var ping := NetworkManager.get_player_ping(int(pid))
		_log("  ID %d | %s%s | %s" % [int(pid), str(info.get("name", "Spieler")), " (Admin)" if AdminManager.is_admin(int(pid)) else "", ("%d ms" % ping) if ping >= 0 else "– ms"])


func _kick(target: String) -> void:
	if target.is_empty():
		_log("Aufruf: kick <ID|Name>")
		return
	var peer_id := _find_peer(target)
	if peer_id <= 1:
		_log("Kein Spieler '%s' gefunden. 'players' zeigt alle IDs." % target)
		return
	var player_name := str((NetworkManager.players[peer_id] as Dictionary).get("name", "Spieler"))
	NetworkManager.kick_player(peer_id)
	_log("%s (ID %d) wird gekickt." % [player_name, peer_id])


func _set_admin(target: String, on: bool) -> void:
	if target.is_empty():
		_log("Aufruf: %s <ID|Name>" % ("admin" if on else "unadmin"))
		return
	var peer_id := _find_peer(target)
	if peer_id <= 1:
		_log("Kein Spieler '%s' gefunden. 'players' zeigt alle IDs." % target)
		return
	if AdminManager.set_admin_from_console(peer_id, on):
		_log("%s (ID %d) ist jetzt %s." % [NetworkManager.get_player_name(peer_id), peer_id, "Admin" if on else "kein Admin mehr"])
	else:
		_log("Keine Änderung.")


func _find_peer(target: String) -> int:
	if target.is_valid_int() and NetworkManager.players.has(target.to_int()):
		return target.to_int()
	var wanted := target.to_lower()
	for pid in NetworkManager.players.keys():
		var info: Dictionary = NetworkManager.players[pid]
		if str(info.get("name", "")).to_lower() == wanted:
			return int(pid)
	return 0


func stop_server() -> void:
	if _stopping:
		return
	_stopping = true
	_log("Speichere die Welt und beende den Server ...")
	var result := GameState.save_current_world()
	if not bool(result.get("ok", false)):
		_log("Speichern fehlgeschlagen: %s" % str(result.get("error", "unbekannt")))
	NetworkManager.leave_session()
	get_tree().quit(0)


# --- Ereignisse -------------------------------------------------------------

func _on_host_failed(reason: String) -> void:
	_log("Fehler: %s" % reason)


func _on_port_forward_finished(_success: bool, _ip: String, message: String) -> void:
	_log("UPnP: %s" % message)


func _on_player_joined(peer_id: int, info: Dictionary) -> void:
	_log("Beigetreten: %s (ID %d), %d/%d Spieler" % [
		str(info.get("name", "Spieler")), peer_id, NetworkManager.players.size(), NetworkManager.MAX_PLAYERS
	])


func _on_player_left(peer_id: int) -> void:
	_log("Verlassen: ID %d, %d/%d Spieler" % [peer_id, NetworkManager.players.size(), NetworkManager.MAX_PLAYERS])


func _on_world_saved(display_name: String, is_autosave: bool) -> void:
	_log("%s gespeichert: %s" % ["Autosave" if is_autosave else "Welt", display_name])


func _log(msg: String) -> void:
	print("[SERVER %s] %s" % [Time.get_time_string_from_system(), msg])