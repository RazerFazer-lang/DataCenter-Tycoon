extends Node
## Manages ENet Co-op networking (Host/Join via IP, Radmin VPN, Tailscale, LAN),
## Save-backed Host startup, Ingame Co-op Chat RPCs, and InputMap setup.

signal connection_succeeded
signal connection_failed(reason: String)
signal disconnected_from_session(reason: String)
signal players_changed
signal player_joined(peer_id: int, info: Dictionary)
signal player_left(peer_id: int)
signal chat_message_received(sender_name: String, sender_color: Color, message: String, timestamp: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

const PLAYER_COLORS := [
	Color(0.22, 0.72, 0.98), # Cyan
	Color(0.98, 0.56, 0.18), # Orange
	Color(0.32, 0.88, 0.45), # Green
	Color(0.84, 0.38, 0.96), # Purple
]

var local_player_name: String = "Admin"
## peer_id (int) -> { "name": String, "color": Color }
var players: Dictionary = {}
var is_in_session: bool = false


func _ready() -> void:
	_setup_input_actions()
	local_player_name = SettingsManager.player_name
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


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


func host_game(player_name: String, port: int = DEFAULT_PORT, world_name: String = "Mein DataCenter") -> Error:
	return _start_host_internal(player_name, port, {}, "", world_name)


func host_from_save(save_id: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	var loaded := SaveManager.load_world_file(save_id)
	if not bool(loaded.get("ok", false)):
		connection_failed.emit(str(loaded.get("error", "Spielstand konnte nicht geladen werden.")))
		return ERR_FILE_CANT_READ
	return _start_host_internal(
		player_name,
		port,
		loaded["state"] as Dictionary,
		str(loaded["save_id"]),
		str(loaded["display_name"])
	)


func _start_host_internal(player_name: String, port: int, loaded_state: Dictionary, save_id: String, display_name: String) -> Error:
	leave_session()
	local_player_name = player_name.strip_edges().left(18)
	if local_player_name.is_empty():
		local_player_name = "Host"
	SettingsManager.player_name = local_player_name
	SettingsManager.save_settings()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("Port %d konnte nicht geöffnet werden (Fehler %d)." % [port, err])
		return err

	multiplayer.multiplayer_peer = peer
	is_in_session = true
	players.clear()

	var host_info := {
		"name": local_player_name,
		"color": PLAYER_COLORS[0],
	}
	players[1] = host_info
	DisplayServer.window_set_title("DataCenter Tycoon Co-op [HOST - %s]" % local_player_name)

	if loaded_state.is_empty():
		var clean_name := display_name.strip_edges()
		if clean_name.is_empty():
			clean_name = "Mein DataCenter"
		GameState.initialize_new_world(SaveManager.sanitize_save_id(clean_name), clean_name)
	else:
		GameState.load_from_save_data(loaded_state, save_id, display_name)

	players_changed.emit()
	player_joined.emit(1, host_info)
	connection_succeeded.emit()
	return OK


func join_game(ip: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave_session()
	local_player_name = player_name.strip_edges().left(18)
	if local_player_name.is_empty():
		local_player_name = "Techniker"
	SettingsManager.player_name = local_player_name

	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"
	SettingsManager.record_recent_ip(clean_ip)

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(clean_ip, port)
	if err != OK:
		connection_failed.emit("Verbindung zu %s:%d fehlgeschlagen (Fehler %d)." % [clean_ip, port, err])
		return err

	multiplayer.multiplayer_peer = peer
	DisplayServer.window_set_title("DataCenter Tycoon Co-op [CLIENT - %s]" % local_player_name)
	return OK


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_in_session = false
	GameState.clear_local_state()
	DisplayServer.window_set_title("DataCenter Tycoon Co-op")


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


func _on_peer_connected(_peer_id: int) -> void:
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	GameState.handle_player_disconnect(peer_id)
	_rpc_remove_player.rpc(peer_id)


func _on_connected_to_server() -> void:
	is_in_session = true
	_rpc_register_player.rpc_id(1, local_player_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	leave_session()
	connection_failed.emit("Keine Antwort vom Host. Prüfe IP-Adresse, Port (7777) oder VPN.")


func _on_server_disconnected() -> void:
	leave_session()
	disconnected_from_session.emit("Der Host hat die Sitzung beendet.")


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

	_rpc_sync_player_roster.rpc_id(peer_id, players)
	GameState.send_full_snapshot_to_peer(peer_id)
	_rpc_add_player.rpc(peer_id, info)
	GameState.post_event("%s ist dem Rechenzentrum beigetreten." % clean_name, "info")


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
			GameState.post_event("%s hat die Sitzung verlassen." % old_name, "info")
