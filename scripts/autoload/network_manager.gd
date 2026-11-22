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
signal player_left(peer_id: int)
signal chat_message_received(sender_name: String, sender_color: Color, message: String, timestamp: String)
## Ergebnis der automatischen Portfreigabe beim Hosten.
signal port_forward_finished(ok: bool, ip: String, message: String)
## Neue Ping-Werte vom Host (siehe player_pings).
signal pings_updated
## Liste der im LAN gefundenen Spiele hat sich geändert (siehe lan_games).
signal lan_games_updated

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
## Zeit für Versions- und Passwortprüfung, danach trennt der Host einen nicht angemeldeten Client.
const AUTH_TIMEOUT := 5.0
const AUTH_MAX_BYTES := 1024
const PASSWORD_MAX_LEN := 32
## Abstand, in dem der Host die Ping-Werte an alle schickt.
const PING_INTERVAL := 1.0
## Wartezeit zwischen Kick-Nachricht und Trennen, damit der Grund ankommt.
const KICK_GRACE := 0.3
## LAN-Suche: UDP-Port, Sendeabstand, Ablaufzeit eines Eintrags, Paketkennung, Maximalgröße.
const DISCOVERY_PORT := 7778
const DISCOVERY_INTERVAL := 1.0
const DISCOVERY_TIMEOUT_MS := 3500
const DISCOVERY_MAGIC := "DCT_LAN_1"
const DISCOVERY_MAX_BYTES := 512

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

const UPNP_DESCRIPTION := "DataCenter Tycoon Co-op"
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

## peer_id -> Ping in ms (Host = 0). Wird vom Host verteilt.
var player_pings: Dictionary = {}
var _ping_timer: Timer = null
## Grund, den der Host beim Kicken mitgeschickt hat.
var _kick_reason: String = ""
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
	_add_key_action("interact", [KEY_E])
	_add_key_action("inspect_rack", [KEY_F])
	_add_key_action("drop_item", [KEY_Q])
	_add_key_action("rotate_item", [KEY_R])
	_add_key_action("tool_hands", [KEY_1])
	_add_key_action("tool_power_cable", [KEY_2])
	_add_key_action("tool_net_cable", [KEY_3])
	_add_key_action("toggle_help", [KEY_H])
	_add_key_action("open_chat", [KEY_T])
	_add_key_action("toggle_perf", [KEY_F3])
	_add_key_action("punch", [KEY_V])
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
	local_player_name = player_name.strip_edges().left(18)
	if local_player_name.is_empty():
		local_player_name = "Host"
	# Der Servername ist kein Spielername und soll die settings.cfg nicht überschreiben.
	if not dedicated:
		SettingsManager.player_name = local_player_name
		SettingsManager.save_settings()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS if dedicated else MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit(tr("Port %d konnte nicht geöffnet werden (Fehler %d).") % [port, err])
		return err

	multiplayer.multiplayer_peer = peer
	is_in_session = true
	is_dedicated = dedicated
	players.clear()

	var host_info := {
		"name": local_player_name,
		"color": PLAYER_COLORS[0],
	}
	if not dedicated:
		players[1] = host_info
	DisplayServer.window_set_title("DataCenter Tycoon Co-op [%s - %s]" % ["SERVER" if dedicated else "HOST", local_player_name])
	if use_upnp:
		_start_port_forward(port)

	if loaded_state.is_empty():
		var clean_name := display_name.strip_edges()
		if clean_name.is_empty():
			clean_name = "Mein DataCenter"
		GameState.initialize_new_world(SaveManager.sanitize_save_id(clean_name), clean_name)
		hosted_world_name = clean_name
	else:
		GameState.load_from_save_data(loaded_state, save_id, display_name)
		hosted_world_name = display_name.strip_edges()
	_start_lan_broadcast(port)

	players_changed.emit()
	if not dedicated:
		player_joined.emit(1, host_info)
	connection_succeeded.emit()
	return OK


func join_game(ip: String, player_name: String, port: int = DEFAULT_PORT, password: String = "") -> Error:
	leave_session()
	_join_password = password.strip_edges().left(PASSWORD_MAX_LEN)
	_join_error = ""
	local_player_name = player_name.strip_edges().left(18)
	if local_player_name.is_empty():
		local_player_name = "Techniker"
	SettingsManager.player_name = local_player_name

	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"
	SettingsManager.record_recent_ip(clean_ip)
	_last_join = {"ip": clean_ip, "port": port, "password": _join_password}
	_kick_reason = ""

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(clean_ip, port)
	if err != OK:
		connection_failed.emit(tr("Verbindung zu %s:%d fehlgeschlagen (Fehler %d).") % [clean_ip, port, err])
		return err

	_joining = true
	multiplayer.multiplayer_peer = peer
	DisplayServer.window_set_title("DataCenter Tycoon Co-op [CLIENT - %s]" % local_player_name)
	return OK


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_stop_port_forward()
	_auth_nonces.clear()
	_joining = false
	players.clear()
	player_pings.clear()
	_stop_lan_broadcast()
	stop_lan_discovery()
	hosted_world_name = ""
	is_in_session = false
	is_dedicated = false
	GameState.clear_local_state()
	DisplayServer.window_set_title("DataCenter Tycoon Co-op")


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
		return
	if upnp == null:
		var reason: String = tr(error_msg) % error_code if error_msg.contains("%d") else tr(error_msg)
		port_forward_finished.emit(false, "", tr("%s Freunde außerhalb deines Netzwerks erreichen dich so nicht. Gib Port %d (UDP) im Router frei oder nutze Tailscale.") % [reason, port])
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
	_upnp = null
	hosted_port = 0
	public_ip = ""


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
	var reason := ""
	var client_version := str(msg.get("v", "?")).left(32)
	if client_version != UIStyle.game_version():
		reason = _version_mismatch_text(UIStyle.game_version(), client_version, false)
	elif not host_password.is_empty() and str(msg.get("proof", "")) != _password_proof(nonce, host_password):
		reason = "Falsches Passwort."
	if not reason.is_empty():
		# Nicht bestätigen: Der Client trennt sich selbst, sonst greift AUTH_TIMEOUT.
		_send_auth_msg(peer_id, {"t": "result", "ok": false, "reason": reason})
		return
	_send_auth_msg(peer_id, {"t": "result", "ok": true})
	(multiplayer as SceneMultiplayer).complete_auth(peer_id)


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
			if bool(msg.get("pw", false)) and _join_password.is_empty():
				_join_error = tr("Diese Welt ist mit einem Passwort geschützt. Trage es unter „Passwort“ ein.")
				_fail_join.call_deferred(_join_error)
				return
			_send_auth_msg(1, {
				"t": "login",
				"v": UIStyle.game_version(),
				"proof": _password_proof(str(msg.get("nonce", "")), _join_password),
			})
		"result":
			if bool(msg.get("ok", false)):
				(multiplayer as SceneMultiplayer).complete_auth(1)
			else:
				_join_error = tr(str(msg.get("reason", "Der Host hat die Verbindung abgelehnt.")).left(200))
				_fail_join.call_deferred(_join_error)


func _fail_join(reason: String) -> void:
	if not _joining:
		return
	_joining = false
	leave_session()
	connection_failed.emit(reason)


## localize = false, wenn der Text an einen anderen Spieler geschickt wird.
func _version_mismatch_text(host_version: String, client_version: String, localize: bool = true) -> String:
	var fmt := "Andere Spielversion: Host hat %s, Client hat %s. Beide brauchen dieselbe Version."
	return (tr(fmt) if localize else fmt) % [host_version, client_version]


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
	var clean := raw_text.strip_edges().left(180)
	if clean.is_empty():
		return
	var t_dict := Time.get_time_dict_from_system()
	var ts := "%02d:%02d" % [int(t_dict.get("hour", 0)), int(t_dict.get("minute", 0))]
	_rpc_broadcast_chat.rpc(get_player_name(sender_id), get_player_color(sender_id), clean, ts)


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
	for pid in multiplayer.get_peers():
		var pkt := enet.get_peer(pid)
		if pkt != null:
			pings[pid] = int(pkt.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	_rpc_sync_pings.rpc(pings)


@rpc("authority", "call_local", "unreliable")
func _rpc_sync_pings(pings: Dictionary) -> void:
	player_pings.clear()
	for pid in pings.keys():
		player_pings[int(pid)] = int(pings[pid])
	pings_updated.emit()


## Nur der Host kann kicken. Der Host selbst (peer 1) ist ausgenommen.
func kick_player(peer_id: int, reason: String = "Du wurdest vom Host aus der Sitzung entfernt.") -> void:
	if not is_in_session or multiplayer.multiplayer_peer == null or not multiplayer.is_server() or peer_id == 1:
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	_rpc_kicked.rpc_id(peer_id, reason.left(200))
	get_tree().create_timer(KICK_GRACE).timeout.connect(_disconnect_kicked.bind(peer_id))


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
	var info := {
		"magic": DISCOVERY_MAGIC,
		"version": UIStyle.game_version(),
		"world": hosted_world_name.left(40),
		"host": local_player_name.left(18),
		"port": _lan_broadcast_port,
		"players": players.size(),
		"max": MAX_PLAYERS,
		"password": not host_password.is_empty(),
	}
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
	set_process(false)
	if not lan_games.is_empty():
		lan_games.clear()
		lan_games_updated.emit()


func _process(_delta: float) -> void:
	if _lan_listener == null:
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
	}
	game["sig"] = JSON.stringify(game)
	return game


func can_reconnect() -> bool:
	return not _last_join.is_empty() and not is_in_session and not _joining


func reconnect() -> Error:
	if _last_join.is_empty():
		return ERR_UNCONFIGURED
	return join_game(str(_last_join["ip"]), local_player_name, int(_last_join["port"]), str(_last_join["password"]))


func _on_peer_connected(_peer_id: int) -> void:
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	GameState.handle_player_disconnect(peer_id)
	_rpc_remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	_joining = false
	is_in_session = true
	_rpc_register_player.rpc_id(1, local_player_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	_fail_join(tr("Keine Antwort vom Host. Prüfe IP-Adresse, Port (7777) oder VPN."))


func _on_server_disconnected() -> void:
	if _joining:
		_fail_join(_join_error if not _join_error.is_empty() else tr("Der Host hat die Verbindung bei der Anmeldung getrennt."))
		return
	leave_session()
	var reason := tr(_kick_reason) if not _kick_reason.is_empty() else tr("Der Host hat die Sitzung beendet.")
	_kick_reason = ""
	disconnected_from_session.emit(reason)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var color_idx := players.size() % PLAYER_COLORS.size()
	var clean_name := player_name.strip_edges().left(18)
	if clean_name.is_empty():
		clean_name = "Techniker %d" % peer_id
	var info := {
		"name": clean_name,
		"color": PLAYER_COLORS[color_idx],
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
