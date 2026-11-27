extends Node
## Manages ENet Co-op networking (Host/Join via IP, Radmin VPN, Tailscale, LAN,
## automatic UPnP port forwarding on the host's router),
## Save-backed Host startup, Ingame Co-op Chat RPCs, and InputMap setup.
## Joining clients authenticate first (same game version + optional world password).

signal connection_succeeded
signal connection_failed(reason: String)
signal disconnected_from_session(reason: String)
signal players_changed
signal player_joined(peer_id: int, info: Dictionary)
signal player_skin_changed(peer_id: int)
signal player_left(peer_id: int)
signal chat_message_received(sender_name: String, sender_color: Color, message: String, timestamp: String)
## Ergebnis der automatischen Portfreigabe beim Hosten.
signal port_forward_finished(ok: bool, ip: String, message: String)
## Neue Ping-Werte vom Host (siehe player_pings).
signal pings_updated
## Liste der im LAN gefundenen Spiele hat sich geändert (siehe lan_games).
signal lan_games_updated
## Bannliste des Hosts hat sich geändert.
signal ban_list_changed
## Status eines abgefragten Servers ist da oder ist weg (siehe query_server).
signal server_status_updated(key: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
## Zeit für Versions- und Passwortprüfung, danach trennt der Host einen nicht angemeldeten Client.
const AUTH_TIMEOUT := 5.0
const AUTH_MAX_BYTES := 1024
const PASSWORD_MAX_LEN := 32
## Abstand, in dem der Host die Ping-Werte an alle schickt.
const PING_INTERVAL := 1.0
## Ab hier warnt das HUD: Paketverlust in %, Ping in ms, Sekunden ohne Nachricht vom Host.
const CONN_LOSS_WARN := 5.0
const CONN_PING_WARN := 250
const CONN_SILENT_WARN := 3.0
## Wartezeit zwischen Kick-Nachricht und Trennen, damit der Grund ankommt.
const KICK_GRACE := 0.3
## LAN-Suche: UDP-Port, Sendeabstand, Ablaufzeit eines Eintrags, Paketkennung, Maximalgröße.
const DISCOVERY_PORT := 7778
const DISCOVERY_INTERVAL := 1.0
const DISCOVERY_TIMEOUT_MS := 3500
const DISCOVERY_MAGIC := "DCT_LAN_1"
const DISCOVERY_MAX_BYTES := 512
## Lobby: Statusabfrage auf Spielport + 2 (Standard 7779).
const STATUS_PORT_OFFSET := 2
const STATUS_QUERY := "DCT_Q1"
const STATUS_MAGIC := "DCT_STATUS_1"
const STATUS_TIMEOUT_MS := 2500
const STATUS_MAX_PER_10S := 20
## Ausweich-Ports für den Client, falls Windows keinen zufälligen Port mehr vergibt
## (unterhalb des Windows-Bereichs 49152–65535, den z. B. MSI Center komplett belegen kann).
const CLIENT_PORT_FALLBACK := 38200
const CLIENT_PORT_FALLBACK_COUNT := 40
const NO_UDP_PORTS_TEXT := "Windows hat keinen freien UDP-Port mehr. Meist hält ein anderes Programm alle Ports fest (bekannt: MSI Center, Dienst „MSI.CentralServer“). Beende es oder starte den PC neu und versuche es dann noch einmal."
## Alle Skripte mit @rpc. Ihre Netzwerkfunktionen gehen in die Prüfsumme bei der Anmeldung ein
## (tests/stability_check.gd prüft, dass die Liste vollständig ist).
const RPC_SCRIPTS: Array[String] = [
	"res://scripts/autoload/admin_manager.gd",
	"res://scripts/autoload/cyber_manager.gd",
	"res://scripts/autoload/decor_manager.gd",
	"res://scripts/autoload/finance_manager.gd",
	"res://scripts/autoload/game_state.gd",
	"res://scripts/autoload/mail_manager.gd",
	"res://scripts/autoload/market_manager.gd",
	"res://scripts/autoload/network_manager.gd",
	"res://scripts/autoload/operations_manager.gd",
	"res://scripts/autoload/outdoor_manager.gd",
	"res://scripts/autoload/pc_screen_state.gd",
	"res://scripts/autoload/session_keeper.gd",
	"res://scripts/autoload/staff_manager.gd",
	"res://scripts/autoload/technician_manager.gd",
	"res://scripts/world/world_controller.gd",
]

const PLAYER_COLORS := [
	Color(0.22, 0.72, 0.98), # Cyan
	Color(0.98, 0.56, 0.18), # Orange
	Color(0.32, 0.88, 0.45), # Green
	Color(0.84, 0.38, 0.96), # Purple
]

var local_player_name: String = "Admin"
## true, solange ein dedizierter Server ohne eigene Spielerfigur läuft.
var is_dedicated: bool = false
## peer_id (int) -> { "name": String, "color": Color }
var players: Dictionary = {}
var is_in_session: bool = false

const UPNP_DESCRIPTION := "DataCenter Together"
## Öffentliche IP des Hosts (leer, solange UPnP nicht geklappt hat).
var public_ip: String = ""
var hosted_port: int = 0
var _upnp: UPNP = null
var _upnp_thread: Thread = null

## Passwort der gehosteten Welt (leer = keins). Liegt nur im Speicher, nicht in settings.cfg.
var host_password: String = ""
## peer_id -> Zufallswert, auf den der Client seinen Passwort-Nachweis berechnet
var _auth_nonces: Dictionary = {}
var _crypto := Crypto.new()
var _joining: bool = false
var _join_password: String = ""
var _join_error: String = ""
var _net_build: String = ""
## Host: peer_id -> Schlüssel des Spielers für diese Welt (Baurechte, Wiederverbinden).
var _peer_keys: Dictionary = {}
## Host: gerade gekickte Spieler (bekommen keinen freigehaltenen Platz).
var _kicking: Dictionary = {}
## Host: Beitrittsreihenfolge (Host-Wechsel: wer am längsten dabei ist, übernimmt).
var _join_seq: int = 0
## Nur für Tests: tut so, als vergäbe Windows keinen UDP-Port mehr.
var test_no_udp_ports: bool = false

## peer_id -> Ping in ms (Host = 0). Wird vom Host verteilt.
var player_pings: Dictionary = {}
## peer_id -> Paketverlust in Prozent (vom Host gemessen).
var player_loss: Dictionary = {}
var _last_ping_sync_ms: int = 0
var _ping_timer: Timer = null
## Grund, den der Host beim Kicken mitgeschickt hat.
var _kick_reason: String = ""
## Sitzungs-Bannliste des Hosts (IP-Adressen und kleingeschriebene Spielernamen).
var banned_ips: Array[String] = []
var banned_names: Array[String] = []
## Daten der letzten Verbindung für reconnect(): {ip, port, password}
var _last_join: Dictionary = {}

## Name der gehosteten Welt (für die LAN-Ankündigung).
var hosted_world_name: String = ""
## "ip:port" -> {ip, port, world, host, players, max, password, version, sig, seen}
var lan_games: Dictionary = {}
var _lan_listener: PacketPeerUDP = null
## Ein Sender ohne feste Adresse plus einer pro lokaler IPv4. Windows schickt einen
## Broadcast an 255.255.255.255 sonst nur über einen Adapter (oft VPN/Hyper-V).
var _lan_broadcasts: Array[PacketPeerUDP] = []
var _lan_broadcast_port: int = 0
var _lan_broadcast_timer: Timer = null

var _status_server: PacketPeerUDP = null
var _status_hits: Dictionary = {}
var _query_udp: PacketPeerUDP = null
var _query_nonce: int = 0
var _query_last_ms: int = 0
var _query_sent: Dictionary = {}
var _dns: Dictionary = {}
## "ip:port" -> {state: wait | ok | offline, world, host, players, max, password, version, build, ping}
var server_status: Dictionary = {}


func _ready() -> void:
	_setup_input_actions()
	# SettingsManager lädt vor NetworkManager; gespeicherte Tasten erst jetzt anwenden.
	SettingsManager.apply_key_bindings()
	local_player_name = SettingsManager.player_name
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_ping_timer = Timer.new()
	_ping_timer.wait_time = PING_INTERVAL
	_ping_timer.autostart = true
	_ping_timer.timeout.connect(_on_ping_tick)
	add_child(_ping_timer)
	_lan_broadcast_timer = Timer.new()
	_lan_broadcast_timer.wait_time = DISCOVERY_INTERVAL
	_lan_broadcast_timer.timeout.connect(_on_lan_broadcast_tick)
	add_child(_lan_broadcast_timer)
	set_process(false)
	var scene_mp := multiplayer as SceneMultiplayer
	if scene_mp != null:
		scene_mp.auth_callback = _on_auth_data
		scene_mp.auth_timeout = AUTH_TIMEOUT
		scene_mp.peer_authenticating.connect(_on_peer_authenticating)
		scene_mp.peer_authentication_failed.connect(_on_peer_authentication_failed)


func _setup_input_actions() -> void:
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("crouch", [KEY_C, KEY_CTRL])
	_add_key_action("interact", [KEY_E])
	_add_key_action("inspect_rack", [KEY_F])
	_add_key_action("drop_item", [KEY_Q])
	_add_key_action("rotate_item", [KEY_R])
	_add_key_action("tool_hands", [KEY_1])
	_add_key_action("tool_power_cable", [KEY_2])
	_add_key_action("tool_net_cable", [KEY_3])
	_add_key_action("tool_slot_4", [KEY_4])
	_add_key_action("toggle_help", [KEY_H])
	_add_key_action("open_chat", [KEY_T])
	_add_key_action("toggle_perf", [KEY_F3])
	_add_key_action("world_ping", [KEY_G])
	_add_mouse_action("world_ping", MOUSE_BUTTON_MIDDLE)
	_add_key_action("emote_wave", [KEY_B])
	_add_key_action("emote_thumbs", [KEY_N])
	_add_key_action("emote_wheel", [KEY_V])
	_add_key_action("teleport_site", [KEY_T])
	_add_key_action("admin_menu", [KEY_F10])
	_add_mouse_action("primary_action", MOUSE_BUTTON_LEFT)
	_add_mouse_action("secondary_action", MOUSE_BUTTON_RIGHT)


func _add_key_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		if not InputMap.action_has_event(action_name, ev):
			InputMap.action_add_event(action_name, ev)


func _add_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventMouseButton.new()
	ev.button_index = button_index
	if not InputMap.action_has_event(action_name, ev):
		InputMap.action_add_event(action_name, ev)


func host_game(player_name: String, port: int = DEFAULT_PORT, world_name: String = "Mein DataCenter", password: String = "") -> Error:
	return _start_host_internal(player_name, port, {}, "", world_name, password)


func host_from_save(save_id: String, player_name: String, port: int = DEFAULT_PORT, password: String = "") -> Error:
	var loaded := SaveManager.load_world_file(save_id)
	if not bool(loaded.get("ok", false)):
		connection_failed.emit(tr(str(loaded.get("error", "Spielstand konnte nicht geladen werden."))))
		return ERR_FILE_CANT_READ
	return _start_host_internal(
		player_name,
		port,
		loaded["state"] as Dictionary,
		str(loaded["save_id"]),
		str(loaded["display_name"]),
		password
	)


## Dedizierter Server: kein Host-Spieler, alle MAX_PLAYERS Plätze gehen an Clients.
## world_name ist Anzeigename oder Spielstand-ID. Gibt es dazu keinen Spielstand, entsteht eine neue Welt.
func host_dedicated(server_name: String, port: int, world_name: String, password: String = "", use_upnp: bool = true) -> Error:
	var save_id := SaveManager.sanitize_save_id(world_name)
	if save_id.is_empty() or not FileAccess.file_exists(SaveManager.get_save_path(save_id)):
		return _start_host_internal(server_name, port, {}, "", world_name, password, true, use_upnp)
	var loaded := SaveManager.load_world_file(save_id)
	if not bool(loaded.get("ok", false)):
		connection_failed.emit(tr(str(loaded.get("error", "Spielstand konnte nicht geladen werden."))))
		return ERR_FILE_CANT_READ
	return _start_host_internal(
		server_name,
		port,
		loaded["state"] as Dictionary,
		str(loaded["save_id"]),
		str(loaded["display_name"]),
		password,
		true,
		use_upnp
	)


func _start_host_internal(player_name: String, port: int, loaded_state: Dictionary, save_id: String, display_name: String, password: String = "", dedicated: bool = false, use_upnp: bool = true) -> Error:
	leave_session()
	host_password = password.strip_edges().left(PASSWORD_MAX_LEN)
	local_player_name = SecurityGuard.sanitize_player_name(player_name, [], true, "Host")
	# Der Servername ist kein Spielername und soll die settings.cfg nicht überschreiben.
	if not dedicated:
		SettingsManager.player_name = local_player_name
		SettingsManager.save_settings()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS if dedicated else MAX_PLAYERS - 1) if not test_no_udp_ports else ERR_CANT_CREATE
	if err != OK:
		if free_udp_port() <= 0:
			connection_failed.emit(tr(NO_UDP_PORTS_TEXT))
		else:
			connection_failed.emit(tr("Port %d (UDP) ist schon belegt, vermutlich von einem zweiten Spiel oder Server auf diesem PC. Beende es oder wähle einen anderen Port (Fehler %d).") % [port, err])
		return err

	multiplayer.multiplayer_peer = peer
	is_in_session = true
	is_dedicated = dedicated
	# Auch ohne UPnP: Lobby-Status und Host-Wechsel brauchen den Port.
	hosted_port = port
	players.clear()

	_join_seq = 0
	var host_info := {
		"name": local_player_name,
		"color": PLAYER_COLORS[0],
		"skin": SettingsManager.get_skin(),
		"seq": 0,
	}
	if not dedicated:
		players[1] = host_info
	DisplayServer.window_set_title("DataCenter Together [%s - %s]" % ["SERVER" if dedicated else "HOST", local_player_name])
	if use_upnp:
		_start_port_forward(port)

	if loaded_state.is_empty():
		var clean_name := SecurityGuard.sanitize_label(display_name, 32, "Mein DataCenter")
		GameState.initialize_new_world(SaveManager.sanitize_save_id(clean_name), clean_name)
		hosted_world_name = clean_name
	else:
		var safe_display := SecurityGuard.sanitize_label(display_name, 32, "Mein DataCenter")
		GameState.load_from_save_data(loaded_state, save_id, safe_display)
		hosted_world_name = safe_display
	_start_lan_broadcast(port)
	_start_status_server(port)
	GameState.sync_build_rights()

	players_changed.emit()
	if not dedicated:
		player_joined.emit(1, host_info)
	connection_succeeded.emit()
	return OK


func join_game(ip: String, player_name: String, port: int = DEFAULT_PORT, password: String = "") -> Error:
	leave_session()
	_join_password = password.strip_edges().left(PASSWORD_MAX_LEN)
	_join_error = ""
	local_player_name = SecurityGuard.sanitize_player_name(player_name, [], false, "Techniker")
	SettingsManager.player_name = local_player_name

	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"
	SettingsManager.record_recent_ip(clean_ip)
	_last_join = {"ip": clean_ip, "port": port, "password": _join_password}
	_kick_reason = ""

	# Eigenen Port vorher fest belegen: Sonst sucht Windows erst beim ersten Senden einen, und gibt
	# es keinen mehr, scheitert jedes Paket still und am Ende steht nur „Keine Antwort vom Host“.
	var local_port := free_udp_port()
	if local_port <= 0:
		connection_failed.emit(tr(NO_UDP_PORTS_TEXT))
		return ERR_CANT_CREATE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(clean_ip, port, 0, 0, 0, local_port)
	if err != OK:
		connection_failed.emit(tr("Verbindung zu %s:%d fehlgeschlagen (Fehler %d).") % [clean_ip, port, err])
		return err

	# Antwortet der Host nicht, nach höchstens 10 s aufgeben (ENet wartet sonst bis zu 30 s).
	var host_pkt := peer.get_peer(1)
	if host_pkt != null:
		host_pkt.set_timeout(32, SessionKeeper.PEER_TIMEOUT_MIN_MS, SessionKeeper.PEER_TIMEOUT_MAX_MS)
	_joining = true
	multiplayer.multiplayer_peer = peer
	DisplayServer.window_set_title("DataCenter Together [CLIENT - %s]" % local_player_name)
	return OK


## Ein freier lokaler UDP-Port: zuerst einer, den Windows vergibt, sonst einer aus dem Ausweichbereich.
## 0 = keiner frei.
func free_udp_port() -> int:
	if test_no_udp_ports:
		return 0
	var probe := PacketPeerUDP.new()
	if probe.bind(0) == OK:
		var p := probe.get_local_port()
		probe.close()
		if p > 0:
			return p
	for p in range(CLIENT_PORT_FALLBACK, CLIENT_PORT_FALLBACK + CLIENT_PORT_FALLBACK_COUNT):
		var t := PacketPeerUDP.new()
		if t.bind(p) == OK:
			t.close()
			return p
	return 0


## Zeitlimit für die Verbindung zum Host (ENet-Standard bis 30 s). Nur auf Clients.
func set_host_timeout(min_ms: int, max_ms: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or multiplayer.is_server():
		return
	var pkt := enet.get_peer(1)
	if pkt != null:
		pkt.set_timeout(32, min_ms, max_ms)


## Nur für Tests: Verbindung abreißen lassen, ohne den Host zu benachrichtigen (wie ein Kabelzug).
func simulate_connection_loss() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.host != null:
		var pkt := enet.get_peer(1)
		if pkt != null:
			pkt.peer_disconnect_now()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_on_server_disconnected()


## Wartende Pakete sofort senden (vor dem Schließen, damit „Host geht“ noch ankommt).
func flush_peer() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.host != null:
		enet.host.flush()


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server():
			SessionKeeper.announce_end()
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_stop_port_forward()
	_auth_nonces.clear()
	_peer_keys.clear()
	_joining = false
	players.clear()
	player_pings.clear()
	player_loss.clear()
	_last_ping_sync_ms = 0
	banned_ips.clear()
	banned_names.clear()
	SecurityGuard.clear_all_rate_limits()
	_stop_lan_broadcast()
	_stop_status_server()
	stop_lan_discovery()
	hosted_world_name = ""
	is_in_session = false
	is_dedicated = false
	_kicking.clear()
	GameState.clear_local_state()
	SessionKeeper.on_session_left()
	DisplayServer.window_set_title("DataCenter Together")


func _exit_tree() -> void:
	_stop_port_forward()
	_stop_lan_broadcast()
	stop_lan_discovery()


func _start_port_forward(port: int) -> void:
	hosted_port = port
	public_ip = ""
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))


## Läuft im Hintergrund-Thread, weil discover() einige Sekunden blockieren kann.
func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		_finish_port_forward.call_deferred(null, port, "", "Kein Router mit UPnP gefunden (Code %d).", err)
		return
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		_finish_port_forward.call_deferred(null, port, "", "Router gefunden, aber UPnP ist dort ausgeschaltet.")
		return
	var map_err := upnp.add_port_mapping(port, port, UPNP_DESCRIPTION, "UDP", 0)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		_finish_port_forward.call_deferred(null, port, "", "Der Router hat die Portfreigabe abgelehnt (Code %d).", map_err)
		return
	# Statusabfrage für die Lobby (Spielport + 2). Klappt sie nicht, geht das Spiel trotzdem.
	upnp.add_port_mapping(port + STATUS_PORT_OFFSET, port + STATUS_PORT_OFFSET, UPNP_DESCRIPTION + " Status", "UDP", 0)
	_finish_port_forward.call_deferred(upnp, port, upnp.query_external_address(), "")


## error_msg kommt unübersetzt aus dem UPnP-Thread und wird erst hier im Haupt-Thread übersetzt.
func _finish_port_forward(upnp: UPNP, port: int, ip: String, error_msg: String, error_code: int = 0) -> void:
	if _upnp_thread != null and not _upnp_thread.is_alive():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	# Session inzwischen beendet oder neu gestartet: Freigabe wieder entfernen.
	if not is_in_session or port != hosted_port:
		if upnp != null:
			upnp.delete_port_mapping(port, "UDP")
			upnp.delete_port_mapping(port + STATUS_PORT_OFFSET, "UDP")
		return
	if upnp == null:
		var reason: String = tr(error_msg) % error_code if error_msg.contains("%d") else tr(error_msg)
		port_forward_finished.emit(false, "", tr("%s Freunde außerhalb deines Netzwerks erreichen dich so nicht. Gib Port %d (UDP) im Router frei. Wie es ohne Portfreigabe geht (Tailscale, Radmin), steht im Pausemenü unter „So erreichen dich Freunde“.") % [reason, port])
		return
	_upnp = upnp
	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty() or _is_private_or_cgnat(clean_ip):
		port_forward_finished.emit(false, clean_ip, tr("Port %d ist im Router freigegeben, aber dein Anschluss hat keine eigene öffentliche IPv4 (DS-Lite/CGNAT). Nutze Tailscale.") % port)
		return
	public_ip = clean_ip
	DisplayServer.clipboard_set(clean_ip)
	port_forward_finished.emit(true, clean_ip, tr("Port %d freigegeben. IP für Freunde: %s (in die Zwischenablage kopiert)") % [port, clean_ip])


func _stop_port_forward() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null and hosted_port > 0:
		_upnp.delete_port_mapping(hosted_port, "UDP")
		_upnp.delete_port_mapping(hosted_port + STATUS_PORT_OFFSET, "UDP")
	_upnp = null
	hosted_port = 0
	public_ip = ""


## Über welche Adressen Freunde diesen PC erreichen: [{kind, ip}], kind = lan | tailscale | radmin | hamachi | public.
## Ohne Internetdienst bleibt das der Weg ohne Portfreigabe: gleiches LAN oder ein VPN wie Tailscale/Radmin.
func reach_addresses() -> Array:
	var out: Array = []
	var seen := {}
	for ip in IP.get_local_addresses():
		var kind := address_kind(ip)
		if kind != "" and not seen.has(ip):
			seen[ip] = true
			out.append({"kind": kind, "ip": ip})
	if not public_ip.is_empty() and not seen.has(public_ip):
		out.append({"kind": "public", "ip": public_ip})
	var order := {"lan": 0, "tailscale": 1, "radmin": 2, "hamachi": 3, "public": 4}
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(order[a["kind"]]) < int(order[b["kind"]]))
	return out


## Art einer lokalen IPv4-Adresse (leer = uninteressant, z. B. 127.0.0.1, 169.254.x, IPv6).
static func address_kind(ip: String) -> String:
	var p := ip.split(".")
	if p.size() != 4:
		return ""
	var a := p[0].to_int()
	var b := p[1].to_int()
	if a == 100 and b >= 64 and b <= 127:
		return "tailscale"
	if a == 26:
		return "radmin"
	if a == 25:
		return "hamachi"
	if a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168):
		return "lan"
	return ""


func _is_private_or_cgnat(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return a == 10 \
		or (a == 172 and b >= 16 and b <= 31) \
		or (a == 192 and (b == 168 or b == 0)) \
		or (a == 100 and b >= 64 and b <= 127)


# --- Anmeldung: Versionsprüfung und Welt-Passwort --------------------------
# Läuft über die SceneMultiplayer-Authentifizierung, also vor peer_connected:
#   1. Host -> Client: hello  {Version, Passwort nötig?, Zufallswert}
#   2. Client -> Host: login  {Version, sha256(Zufallswert:Passwort)}
#   3. Host -> Client: result {ok, Grund}
# Das Passwort selbst geht nie über das Netz. Erst nach complete_auth() auf
# beiden Seiten gilt der Client als verbunden und bekommt Spieldaten.

func _on_peer_authenticating(peer_id: int) -> void:
	if not multiplayer.is_server():
		return # Der Client wartet auf das hello des Hosts.
	var nonce := _crypto.generate_random_bytes(16).hex_encode()
	_auth_nonces[peer_id] = nonce
	_send_auth_msg(peer_id, {
		"t": "hello",
		"v": UIStyle.game_version(),
		"b": net_build_id(),
		"w": GameState.world_uid,
		"pw": not host_password.is_empty(),
		"nonce": nonce,
	})


func _on_peer_authentication_failed(peer_id: int) -> void:
	_auth_nonces.erase(peer_id)
	if _joining and peer_id == 1:
		_fail_join(_join_error if not _join_error.is_empty() else tr("Der Host hat die Anmeldung nicht beantwortet. Vermutlich läuft bei ihm eine ältere Spielversion."))


func _on_auth_data(peer_id: int, data: PackedByteArray) -> void:
	var msg := _decode_auth_msg(data)
	if multiplayer.is_server():
		_handle_client_login(peer_id, msg)
	elif peer_id == 1:
		_handle_host_reply(msg)


func _handle_client_login(peer_id: int, msg: Dictionary) -> void:
	if not _auth_nonces.has(peer_id) or str(msg.get("t", "")) != "login":
		return # Unerwartete Nachricht: auth_timeout trennt den Client.
	var nonce := str(_auth_nonces[peer_id])
	_auth_nonces.erase(peer_id) # Ein Versuch pro Verbindung.
	var reason := login_reject_reason(msg, nonce, _get_peer_ip(peer_id))
	if not reason.is_empty():
		# Nicht bestätigen: Der Client trennt sich selbst, sonst greift AUTH_TIMEOUT.
		_send_auth_msg(peer_id, {"t": "result", "ok": false, "reason": reason})
		return
	_peer_keys[peer_id] = str(msg.get("k", "")).left(64)
	_send_auth_msg(peer_id, {"t": "result", "ok": true})
	(multiplayer as SceneMultiplayer).complete_auth(peer_id)


## Warum der Host eine Anmeldung ablehnt (unübersetzt, der Client übersetzt). Leer = angenommen.
func login_reject_reason(msg: Dictionary, nonce: String, client_ip: String) -> String:
	var client_version := str(msg.get("v", "?")).left(32)
	var client_build := str(msg.get("b", "")).left(32)
	if is_ip_banned(client_ip):
		return "Du wurdest vom Host aus dieser Sitzung gebannt."
	if client_version != UIStyle.game_version():
		return _version_mismatch_text(UIStyle.game_version(), client_version, false)
	if client_build != net_build_id():
		return _build_mismatch_text(net_build_id(), client_build, false)
	if not host_password.is_empty() and str(msg.get("proof", "")) != _password_proof(nonce, host_password):
		return "Falsches Passwort."
	return ""


func _handle_host_reply(msg: Dictionary) -> void:
	if not _joining:
		return
	match str(msg.get("t", "")):
		"hello":
			var host_version := str(msg.get("v", "?")).left(32)
			if host_version != UIStyle.game_version():
				_join_error = _version_mismatch_text(host_version, UIStyle.game_version())
				_fail_join.call_deferred(_join_error)
				return
			var host_build := str(msg.get("b", "")).left(32)
			if host_build != net_build_id():
				_join_error = _build_mismatch_text(host_build, net_build_id())
				_fail_join.call_deferred(_join_error)
				return
			if bool(msg.get("pw", false)) and _join_password.is_empty():
				_join_error = tr("Diese Welt ist mit einem Passwort geschützt. Trage es unter „Passwort“ ein.")
				_fail_join.call_deferred(_join_error)
				return
			_send_auth_msg(1, {
				"t": "login",
				"v": UIStyle.game_version(),
				"b": net_build_id(),
				"k": world_key(str(msg.get("w", ""))),
				"proof": _password_proof(str(msg.get("nonce", "")), _join_password),
			})
		"result":
			if bool(msg.get("ok", false)):
				(multiplayer as SceneMultiplayer).complete_auth(1)
			else:
				_join_error = tr(str(msg.get("reason", "Der Host hat die Verbindung abgelehnt.")).left(200))
				_fail_join.call_deferred(_join_error)


func is_joining() -> bool:
	return _joining


## Hängenden Beitritt abbrechen (SessionKeeper: Versuch dauert zu lange).
func abort_join(reason: String) -> void:
	_fail_join(reason)


func _fail_join(reason: String) -> void:
	if not _joining:
		return
	_joining = false
	# Falsche Version, Prüfsumme, Passwort oder Bann: Weiterversuchen bringt nichts.
	var permanent := not _join_error.is_empty()
	leave_session()
	if SessionKeeper.on_join_failed(reason, permanent):
		return
	connection_failed.emit(reason)


## localize = false, wenn der Text an einen anderen Spieler geschickt wird.
func _version_mismatch_text(host_version: String, client_version: String, localize: bool = true) -> String:
	var fmt := "Andere Spielversion: Host hat %s, Client hat %s. Beide brauchen dieselbe Version."
	return (tr(fmt) if localize else fmt) % [host_version, client_version]


## Gleiche Version, anderer Programmstand: Die Netzwerkfunktionen passen nicht zusammen.
func _build_mismatch_text(host_build: String, client_build: String, localize: bool = true) -> String:
	var fmt := "Gleiche Spielversion, aber ein anderer Programmstand (Netzwerk-Prüfsumme Host %s, Client %s). Beide brauchen denselben Download, am einfachsten über den Launcher."
	return (tr(fmt) if localize else fmt) % [host_build if not host_build.is_empty() else "?", client_build if not client_build.is_empty() else "?"]


## Prüfsumme aller Netzwerkfunktionen (Name, @rpc-Einstellungen, Parameter) der Skripte in RPC_SCRIPTS.
## Weicht sie ab, laufen sonst tausende „rpc node checksum failed“-Fehler auf, ohne dass jemand erfährt, warum.
func net_build_id() -> String:
	if not _net_build.is_empty():
		return _net_build
	var parts := PackedStringArray()
	for path in RPC_SCRIPTS:
		var scr := load(path) as Script
		if scr == null:
			parts.append(path + ":fehlt")
			continue
		var args := {}
		for m in scr.get_script_method_list():
			var sig := PackedStringArray()
			for a in (m["args"] as Array):
				sig.append("%s:%d" % [str(a["name"]), int(a["type"])])
			args[str(m["name"])] = ",".join(sig)
		var rows := PackedStringArray()
		var cfg: Variant = scr.get_rpc_config()
		if cfg is Dictionary:
			# Als String sortieren: StringNames sortiert Godot nach Speicheradresse, also je Start anders.
			var names := PackedStringArray()
			for n in (cfg as Dictionary).keys():
				names.append(str(n))
			names.sort()
			for n in names:
				var c: Variant = (cfg as Dictionary).get(StringName(n), (cfg as Dictionary).get(n))
				var ck := PackedStringArray()
				if c is Dictionary:
					for k in (c as Dictionary).keys():
						ck.append("%s=%s" % [str(k), str(c[k])])
				ck.sort()
				rows.append("%s(%s)%s" % [n, str(args.get(n, "")), ";".join(ck)])
		parts.append(path.get_file() + ":" + "|".join(rows))
	_net_build = "\n".join(parts).sha256_text().left(10)
	return _net_build


## Schlüssel dieses Spielers für eine Welt. Je Welt verschieden: Ein Host kann ihn nirgends sonst benutzen.
## Mit Name: Zwei Fenster auf einem PC (Launcher-Test) zählen so als zwei Spieler.
func world_key(world_uid: String) -> String:
	return ("%s:%s:%s" % [SettingsManager.get_client_id(), world_uid, local_player_name.to_lower()]).sha256_text().left(32)


func peer_key(peer_id: int) -> String:
	return str(_peer_keys.get(peer_id, ""))


func _password_proof(nonce: String, password: String) -> String:
	return ("%s:%s" % [nonce, password]).sha256_text()


func _send_auth_msg(peer_id: int, msg: Dictionary) -> void:
	var scene_mp := multiplayer as SceneMultiplayer
	if scene_mp == null:
		return
	var err := scene_mp.send_auth(peer_id, JSON.stringify(msg).to_utf8_buffer())
	if err != OK:
		push_warning("Anmeldedaten an Peer %d konnten nicht gesendet werden (Fehler %d)." % [peer_id, err])


func _decode_auth_msg(data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > AUTH_MAX_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary:
		return parsed
	return {}


func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return str(players[peer_id].get("name", "Spieler"))
	return "Spieler #%d" % peer_id


func get_player_color(peer_id: int) -> Color:
	if players.has(peer_id):
		return players[peer_id].get("color", Color.WHITE)
	return Color.WHITE


func send_chat_message(raw_text: String) -> void:
	if not is_in_session:
		return
	var text := raw_text.strip_edges().left(180)
	if text.is_empty():
		return
	_rpc_send_chat.rpc_id(1, text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_send_chat(raw_text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not SecurityGuard.check_rate_limit(sender_id, "chat", 4, 5.0, false):
		if sender_id == multiplayer.get_unique_id():
			_rpc_chat_notice("Bitte warte kurz vor der nächsten Nachricht (Spam-Schutz).")
		else:
			_rpc_chat_notice.rpc_id(sender_id, "Bitte warte kurz vor der nächsten Nachricht (Spam-Schutz).")
		return
	var clean := SecurityGuard.filter_chat_message(raw_text)
	if clean.is_empty():
		return
	var t_dict := Time.get_time_dict_from_system()
	var ts := "%02d:%02d" % [int(t_dict.get("hour", 0)), int(t_dict.get("minute", 0))]
	_rpc_broadcast_chat.rpc(get_player_name(sender_id), get_player_color(sender_id), clean, ts)


@rpc("authority", "call_local", "reliable")
func _rpc_chat_notice(notice_text: String) -> void:
	var t_dict := Time.get_time_dict_from_system()
	var ts := "%02d:%02d" % [int(t_dict.get("hour", 0)), int(t_dict.get("minute", 0))]
	chat_message_received.emit("System", Color(0.95, 0.72, 0.25), tr(notice_text), ts)


## Serverkonsole: Nachricht als „Server“ an alle. Gibt den gefilterten Text zurück (leer = nichts gesendet).
func server_say(raw_text: String) -> String:
	if not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return ""
	var clean := SecurityGuard.filter_chat_message(raw_text.strip_edges().left(180))
	if clean.is_empty():
		return ""
	var t := Time.get_time_dict_from_system()
	_rpc_broadcast_chat.rpc("Server", Color(0.95, 0.72, 0.25), clean, "%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))])
	return clean


@rpc("authority", "call_local", "reliable")
func _rpc_broadcast_chat(sender_name: String, sender_color: Color, message: String, timestamp: String) -> void:
	SfxManager.play("chat", -12.0)
	chat_message_received.emit(sender_name, sender_color, message, timestamp)


# --- Spielerliste: Ping, Kicken, Wiederverbinden ---------------------------

func get_player_ping(peer_id: int) -> int:
	return int(player_pings.get(peer_id, -1))


func _on_ping_tick() -> void:
	if not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pings := {1: 0}
	var losses := {1: 0.0}
	for pid in multiplayer.get_peers():
		var pkt := enet.get_peer(pid)
		if pkt != null:
			pings[pid] = int(pkt.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			losses[pid] = snappedf(_loss_pct(pkt), 0.1)
	_rpc_sync_pings.rpc(pings, losses)


## Paketverlust einer Verbindung in Prozent (ENet rechnet in 1/65536).
static func _loss_pct(pkt: ENetPacketPeer) -> float:
	return clampf(float(pkt.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) / float(ENetPacketPeer.PACKET_LOSS_SCALE) * 100.0, 0.0, 100.0)


@rpc("authority", "call_local", "unreliable")
func _rpc_sync_pings(pings: Dictionary, losses: Dictionary = {}) -> void:
	player_pings.clear()
	player_loss.clear()
	for pid in pings.keys():
		player_pings[int(pid)] = int(pings[pid])
		player_loss[int(pid)] = float(losses.get(pid, 0.0))
	_last_ping_sync_ms = Time.get_ticks_msec()
	pings_updated.emit()


func get_player_loss(peer_id: int) -> float:
	return float(player_loss.get(peer_id, 0.0))


## Zustand der eigenen Verbindung zum Host: {rtt, loss, silent}. silent = Sekunden ohne Lebenszeichen vom Host.
## Auf dem Host selbst immer alles gut.
func own_connection() -> Dictionary:
	var out := {"rtt": 0, "loss": 0.0, "silent": 0.0}
	if not is_in_session or multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return out
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var pkt: ENetPacketPeer = enet.get_peer(1) if enet != null else null
	if pkt != null:
		out["rtt"] = int(pkt.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		out["loss"] = _loss_pct(pkt)
	if _last_ping_sync_ms > 0:
		out["silent"] = float(Time.get_ticks_msec() - _last_ping_sync_ms) / 1000.0
	return out


## Text für die Warnung im HUD, leer = Verbindung in Ordnung.
func connection_warning() -> String:
	var c := own_connection()
	if float(c["silent"]) >= CONN_SILENT_WARN:
		return tr("Host antwortet nicht (seit %d s)") % int(c["silent"])
	if float(c["loss"]) >= CONN_LOSS_WARN:
		return tr("Verbindung instabil: %d %% Paketverlust") % int(roundf(float(c["loss"])))
	if int(c["rtt"]) >= CONN_PING_WARN:
		return tr("Hoher Ping zum Host: %d ms") % int(c["rtt"])
	return ""


## Nur der Host kann kicken. Der Host selbst (peer 1) ist ausgenommen.
func kick_player(peer_id: int, reason: String = "Du wurdest vom Host aus der Sitzung entfernt.") -> void:
	if not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server() or peer_id == 1:
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	_kicking[peer_id] = true
	_rpc_kicked.rpc_id(peer_id, reason.left(200))
	get_tree().create_timer(KICK_GRACE).timeout.connect(_disconnect_kicked.bind(peer_id))


## Nur der Host kann bannen (IP + Name für die aktuelle Sitzung).
func ban_player(peer_id: int, reason: String = "Du wurdest vom Host aus dieser Sitzung gebannt.") -> void:
	if not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server() or peer_id == 1:
		return
	var ip := _get_peer_ip(peer_id)
	if not ip.is_empty() and not banned_ips.has(ip):
		banned_ips.append(ip)
	var pname := get_player_name(peer_id)
	var pname_key := pname.strip_edges().to_lower()
	if not pname_key.is_empty() and not banned_names.has(pname_key):
		banned_names.append(pname_key)
	ban_list_changed.emit()
	GameState.post_event_f("%s wurde vom Host gebannt.", [pname], "warn")
	kick_player(peer_id, reason)


func clear_bans() -> void:
	if not multiplayer.is_server():
		return
	banned_ips.clear()
	banned_names.clear()
	ban_list_changed.emit()


func get_ban_count() -> int:
	return maxi(banned_ips.size(), banned_names.size())


func is_ip_banned(ip: String) -> bool:
	return not ip.is_empty() and banned_ips.has(ip)


func is_name_banned(player_name: String) -> bool:
	var key := SecurityGuard.strip_invisible_and_controls(player_name).to_lower()
	return not key.is_empty() and banned_names.has(key)


func _get_peer_ip(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var pkt := enet.get_peer(peer_id)
	if pkt == null:
		return ""
	return pkt.get_remote_address()


func _disconnect_kicked(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	_kick_reason = reason.left(200)
	# Nach einem Kick kein automatisches Wiederverbinden anbieten
	_last_join = {}


# --- LAN-Suche --------------------------------------------------------------

func _start_lan_broadcast(port: int) -> void:
	_stop_lan_broadcast()
	var fallback := _make_lan_sender("")
	if fallback != null:
		_lan_broadcasts.append(fallback)
	for addr in _local_lan_ipv4s():
		var udp := _make_lan_sender(addr)
		if udp != null:
			_lan_broadcasts.append(udp)
	if _lan_broadcasts.is_empty():
		push_warning("LAN-Ankündigung nicht möglich: kein Netzwerkadapter nutzbar.")
		return
	_lan_broadcast_port = port
	_lan_broadcast_timer.start()
	_on_lan_broadcast_tick()


## bind_address leer = Windows wählt den Adapter selbst.
func _make_lan_sender(bind_address: String) -> PacketPeerUDP:
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if not bind_address.is_empty():
		if udp.bind(0, bind_address) != OK:
			return null
	if udp.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK:
		udp.close()
		return null
	return udp


## Lokale IPv4-Adressen ohne Loopback (127.x) und ohne APIPA (169.254.x).
func _local_lan_ipv4s() -> Array[String]:
	var result: Array[String] = []
	for iface in IP.get_local_interfaces():
		var d: Dictionary = iface
		for a in d.get("addresses", []):
			var s := str(a)
			if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
				continue
			if not result.has(s):
				result.append(s)
	return result


func _stop_lan_broadcast() -> void:
	if _lan_broadcast_timer != null:
		_lan_broadcast_timer.stop()
	for udp in _lan_broadcasts:
		udp.close()
	_lan_broadcasts.clear()
	_lan_broadcast_port = 0


func _on_lan_broadcast_tick() -> void:
	if _lan_broadcasts.is_empty() or not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var info := _status_info(DISCOVERY_MAGIC)
	info["port"] = _lan_broadcast_port
	var packet := JSON.stringify(info).to_utf8_buffer()
	for udp in _lan_broadcasts:
		# Fehler einzelner Adapter (z. B. getrennt) ignorieren, die anderen senden weiter.
		udp.put_packet(packet)


func is_lan_discovery_active() -> bool:
	return _lan_listener != null


func start_lan_discovery() -> Error:
	if _lan_listener != null:
		return OK
	var udp := PacketPeerUDP.new()
	var err := udp.bind(DISCOVERY_PORT)
	if err != OK:
		return err
	_lan_listener = udp
	lan_games.clear()
	set_process(true)
	lan_games_updated.emit()
	return OK


func stop_lan_discovery() -> void:
	if _lan_listener != null:
		_lan_listener.close()
		_lan_listener = null
	if not lan_games.is_empty():
		lan_games.clear()
		lan_games_updated.emit()


func _process(_delta: float) -> void:
	if _status_server != null:
		_serve_status()
	if _query_udp != null:
		_read_status_replies()
	if _lan_listener == null:
		if _status_server == null and _query_udp == null:
			set_process(false)
		return
	var changed := false
	var now := Time.get_ticks_msec()
	var budget := 32
	while budget > 0 and _lan_listener.get_available_packet_count() > 0:
		budget -= 1
		var pkt := _lan_listener.get_packet()
		var game := _parse_lan_packet(pkt, _lan_listener.get_packet_ip())
		if game.is_empty():
			continue
		var key := "%s:%d" % [game["ip"], game["port"]]
		var prev: Dictionary = lan_games.get(key, {})
		if prev.is_empty() or str(prev.get("sig", "")) != str(game["sig"]):
			changed = true
		game["seen"] = now
		lan_games[key] = game
	for key in lan_games.keys():
		if now - int(lan_games[key]["seen"]) > DISCOVERY_TIMEOUT_MS:
			lan_games.erase(key)
			changed = true
	if changed:
		lan_games_updated.emit()


func _lan_num(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func _parse_lan_packet(pkt: PackedByteArray, ip: String) -> Dictionary:
	if pkt.is_empty() or pkt.size() > DISCOVERY_MAX_BYTES or ip.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if str(d.get("magic", "")) != DISCOVERY_MAGIC:
		return {}
	var port := _lan_num(d.get("port"), 0)
	if port < 1 or port > 65535:
		return {}
	var game := {
		"ip": ip,
		"port": port,
		"world": str(d.get("world", "")).strip_edges().left(40),
		"host": str(d.get("host", "")).strip_edges().left(18),
		"players": clampi(_lan_num(d.get("players"), 0), 0, MAX_PLAYERS),
		"max": clampi(_lan_num(d.get("max"), MAX_PLAYERS), 1, 16),
		"password": d.get("password", false) == true,
		"version": str(d.get("version", "")).left(16),
		"build": str(d.get("build", "")).left(16),
	}
	game["sig"] = JSON.stringify(game)
	return game


# --- Lobby ohne Internetdienst: Status-Abfrage per UDP ------------------------
# Der Host antwortet auf Spielport + STATUS_PORT_OFFSET auf "DCT_Q1:<Nonce>" mit Welt, Spielern,
# Passwort, Version und Prüfsumme. Spiel und Launcher fragen so gespeicherte Server und das LAN ab
# (Launcher per Broadcast an Port 7779). Die Antwort ist klein und je IP gedrosselt.

func _status_info(magic: String) -> Dictionary:
	return {
		"magic": magic,
		"version": UIStyle.game_version(),
		"build": net_build_id(),
		"world": hosted_world_name.left(40),
		"host": local_player_name.left(18),
		"port": hosted_port if hosted_port > 0 else _lan_broadcast_port,
		"players": players.size(),
		"max": MAX_PLAYERS,
		"password": not host_password.is_empty(),
		"dedicated": is_dedicated,
	}


func _start_status_server(port: int) -> void:
	_stop_status_server()
	var udp := PacketPeerUDP.new()
	var err := udp.bind(port + STATUS_PORT_OFFSET)
	if err != OK:
		push_warning("Statusabfrage: Port %d belegt (Fehler %d), die Lobby zeigt diesen Server dann ohne Details." % [port + STATUS_PORT_OFFSET, err])
		return
	_status_server = udp
	set_process(true)


func _stop_status_server() -> void:
	if _status_server != null:
		_status_server.close()
	_status_server = null
	_status_hits.clear()


func is_status_server_running() -> bool:
	return _status_server != null


func _serve_status() -> void:
	var budget := 32
	var now := Time.get_ticks_msec()
	while budget > 0 and _status_server.get_available_packet_count() > 0:
		budget -= 1
		var pkt := _status_server.get_packet()
		var ip := _status_server.get_packet_ip()
		var from_port := _status_server.get_packet_port()
		if pkt.size() > 64 or ip.is_empty():
			continue
		var s := pkt.get_string_from_utf8()
		if not s.begins_with(STATUS_QUERY):
			continue
		var hit: Array = _status_hits.get(ip, [now, 0])
		if now - int(hit[0]) > 10000:
			hit = [now, 0]
		hit[1] = int(hit[1]) + 1
		_status_hits[ip] = hit
		if int(hit[1]) > STATUS_MAX_PER_10S:
			continue
		var reply := _status_info(STATUS_MAGIC)
		reply["nonce"] = s.get_slice(":", 1).left(16)
		_status_server.set_dest_address(ip, from_port)
		_status_server.put_packet(JSON.stringify(reply).to_utf8_buffer())
	if _status_hits.size() > 512:
		_status_hits.clear()


## Fragt einen Server nach seinem Status. Das Ergebnis kommt über server_status_updated("ip:port").
func query_server(ip: String, port: int) -> void:
	var host := ip.strip_edges()
	if host.is_empty() or port < 1 or port > 65535 - STATUS_PORT_OFFSET:
		return
	if _query_udp == null:
		_query_udp = PacketPeerUDP.new()
		if _query_udp.bind(0) != OK:
			_query_udp = null
			return
		_query_udp.set_broadcast_enabled(true)
	var key := "%s:%d" % [host, port]
	if not server_status.has(key):
		server_status[key] = {"state": "wait"}
	var addr := host
	if not host.is_valid_ip_address():
		# Namen (z. B. von DynDNS) im Hintergrund auflösen, beim nächsten Abfragen ist er da.
		if not _dns.has(host):
			_dns[host] = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
			return
		var qid: int = _dns[host]
		var rs := IP.get_resolve_item_status(qid)
		if rs == IP.RESOLVER_STATUS_ERROR or rs == IP.RESOLVER_STATUS_NONE:
			IP.erase_resolve_item(qid)
			_dns.erase(host)
			_set_status(key, {"state": "offline"})
			return
		if rs != IP.RESOLVER_STATUS_DONE:
			return
		addr = IP.get_resolve_item_address(qid)
	_query_nonce += 1
	var nonce := str(_query_nonce)
	_query_sent[nonce] = {"key": key, "t": Time.get_ticks_msec()}
	_query_last_ms = Time.get_ticks_msec()
	_query_udp.set_dest_address(addr, port + STATUS_PORT_OFFSET)
	_query_udp.put_packet(("%s:%s" % [STATUS_QUERY, nonce]).to_utf8_buffer())
	set_process(true)


func get_server_status(ip: String, port: int) -> Dictionary:
	return server_status.get("%s:%d" % [ip.strip_edges(), port], {})


func _set_status(key: String, st: Dictionary) -> void:
	server_status[key] = st
	server_status_updated.emit(key)


func _read_status_replies() -> void:
	var now := Time.get_ticks_msec()
	var budget := 32
	while budget > 0 and _query_udp.get_available_packet_count() > 0:
		budget -= 1
		var pkt := _query_udp.get_packet()
		var from_ip := _query_udp.get_packet_ip()
		if pkt.size() > DISCOVERY_MAX_BYTES:
			continue
		var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not (parsed is Dictionary) or str((parsed as Dictionary).get("magic", "")) != STATUS_MAGIC:
			continue
		var d: Dictionary = (parsed as Dictionary).duplicate()
		var nonce := str(d.get("nonce", ""))
		if not _query_sent.has(nonce):
			continue
		var sent: Dictionary = _query_sent[nonce]
		_query_sent.erase(nonce)
		d["magic"] = DISCOVERY_MAGIC
		var game := _parse_lan_packet(JSON.stringify(d).to_utf8_buffer(), from_ip)
		if game.is_empty():
			continue
		game["state"] = "ok"
		game["ping"] = now - int(sent["t"])
		game["seen"] = now
		_set_status(str(sent["key"]), game)
	for nonce in _query_sent.keys():
		var q: Dictionary = _query_sent[nonce]
		if now - int(q["t"]) < STATUS_TIMEOUT_MS:
			continue
		_query_sent.erase(nonce)
		var st: Dictionary = server_status.get(str(q["key"]), {})
		# Kam inzwischen eine Antwort auf eine neuere Anfrage, bleibt der Server erreichbar.
		if int(st.get("seen", 0)) < int(q["t"]):
			_set_status(str(q["key"]), {"state": "offline"})
	# Nach 30 s ohne Anfrage den Abfrage-Socket wieder schließen.
	if _query_sent.is_empty() and now - _query_last_ms > 30000:
		_query_udp.close()
		_query_udp = null
		for host in _dns.keys():
			IP.erase_resolve_item(int(_dns[host]))
		_dns.clear()


func can_reconnect() -> bool:
	return not _last_join.is_empty() and not is_in_session and not _joining


func reconnect() -> Error:
	if _last_join.is_empty():
		return ERR_UNCONFIGURED
	return join_game(str(_last_join["ip"]), local_player_name, int(_last_join["port"]), str(_last_join["password"]))


func _on_peer_connected(peer_id: int) -> void:
	# Host: Abbrüche nach höchstens 15 s erkennen (ENet-Standard 30 s), dann hält SessionKeeper den Platz frei.
	if multiplayer.is_server():
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var pkt: ENetPacketPeer = enet.get_peer(peer_id) if enet != null else null
		if pkt != null:
			pkt.set_timeout(32, 5000, 15000)


## Host: Ein Spieler meldet sich neu an, während seine alte Verbindung noch hängt. Die alte sofort
## abräumen (wie ein Abbruch), damit er nicht doppelt da ist und seinen Platz zurückbekommt.
func drop_stale_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not players.has(peer_id):
		return
	_on_peer_disconnected(peer_id)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and multiplayer.get_peers().has(peer_id):
		enet.disconnect_peer(peer_id, true)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	SecurityGuard.clear_peer(peer_id)
	# Erst die letzte Stelle holen, on_peer_left vergisst sie.
	var drop := SessionKeeper.drop_pos(peer_id)
	SessionKeeper.on_peer_left(peer_id, _kicking.has(peer_id))
	GameState.handle_player_disconnect(peer_id, drop)
	_peer_keys.erase(peer_id)
	_kicking.erase(peer_id)
	if players.has(peer_id):
		_rpc_remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	_joining = false
	is_in_session = true
	_last_ping_sync_ms = Time.get_ticks_msec()
	_rpc_register_player.rpc_id(1, local_player_name, SettingsManager.get_skin())
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	_fail_join(tr("Keine Antwort vom Host. Prüfe IP-Adresse, Port (%d) oder VPN.") % int(_last_join.get("port", DEFAULT_PORT)))


func _on_server_disconnected() -> void:
	if _joining:
		_fail_join(_join_error if not _join_error.is_empty() else tr("Der Host hat die Verbindung bei der Anmeldung getrennt."))
		return
	# Unerwarteter Abbruch: SessionKeeper verbindet neu oder wechselt den Host.
	if SessionKeeper.on_server_lost(not _kick_reason.is_empty()):
		return
	leave_session()
	var reason := tr(_kick_reason) if not _kick_reason.is_empty() else tr("Der Host hat die Sitzung beendet.")
	_kick_reason = ""
	disconnected_from_session.emit(reason)


## Aussehen während der Sitzung ändern: Host prüft und verteilt.
func update_my_skin(look: Dictionary) -> void:
	if not is_in_session:
		return
	if multiplayer.is_server():
		_apply_skin(1, look)
	else:
		_rpc_req_skin.rpc_id(1, look)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_skin(look: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not players.has(peer_id) or not SecurityGuard.check_rate_limit(peer_id, "skin", 6, 10.0, false):
		return
	_apply_skin(peer_id, look)


func _apply_skin(peer_id: int, look: Dictionary) -> void:
	if not players.has(peer_id):
		return
	_rpc_player_skin.rpc(peer_id, SettingsManager.sanitize_skin(look))


@rpc("authority", "call_local", "reliable")
func _rpc_player_skin(peer_id: int, look: Dictionary) -> void:
	if not players.has(peer_id):
		return
	(players[peer_id] as Dictionary)["skin"] = SettingsManager.sanitize_skin(look)
	player_skin_changed.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_player(player_name: String, skin: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1 or players.has(peer_id):
		return
	if is_ip_banned(_get_peer_ip(peer_id)) or is_name_banned(player_name):
		kick_player(peer_id, "Du wurdest vom Host aus dieser Sitzung gebannt.")
		return
	SessionKeeper.drop_stale_for(peer_id)
	var existing_names: Array = []
	for p_info in players.values():
		if p_info is Dictionary:
			existing_names.append(str(p_info.get("name", "")))
	var color_idx := players.size() % PLAYER_COLORS.size()
	var clean_name := SecurityGuard.sanitize_player_name(player_name, existing_names, false, "Techniker %d" % peer_id)
	_join_seq += 1
	var info := {
		"name": clean_name,
		"color": PLAYER_COLORS[color_idx],
		"skin": SettingsManager.sanitize_skin(skin),
		"seq": _join_seq,
	}
	players[peer_id] = info
	# Der Spieler steht jetzt schon in players. _rpc_add_player hält ihn deshalb
	# auf dem Server für bekannt und meldet ihn nicht mehr, also hier melden.
	players_changed.emit()
	player_joined.emit(peer_id, info)

	_rpc_sync_player_roster.rpc_id(peer_id, players)
	GameState.send_full_snapshot_to_peer(peer_id)
	_rpc_add_player.rpc(peer_id, info)
	GameState.post_event_f("%s ist dem Rechenzentrum beigetreten.", [clean_name], "info")
	GameState.sync_build_rights()
	SessionKeeper.on_peer_registered(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_player_roster(roster: Dictionary) -> void:
	players = roster.duplicate(true)
	players_changed.emit()
	for pid in players.keys():
		player_joined.emit(int(pid), players[pid])


@rpc("authority", "call_local", "reliable")
func _rpc_add_player(peer_id: int, info: Dictionary) -> void:
	var already_known := players.has(peer_id)
	players[peer_id] = info
	players_changed.emit()
	if not already_known:
		player_joined.emit(peer_id, info)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_player(peer_id: int) -> void:
	if players.has(peer_id):
		var old_name := str(players[peer_id].get("name", "Spieler"))
		players.erase(peer_id)
		players_changed.emit()
		player_left.emit(peer_id)
		if multiplayer.is_server():
			GameState.post_event_f("%s hat die Sitzung verlassen.", [old_name], "info")
