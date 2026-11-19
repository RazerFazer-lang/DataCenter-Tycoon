extends Node
## Gemeinsamer Zustand des Büro-PCs für alle Spieler.
## Wer am PC sitzt, meldet hier Hochfahren, geöffnete App und Tippen.
## Der 3D-Monitor in der Garage (PcScreenMirror) zeigt diesen Zustand bei allen Mitspielern an.

signal screen_changed
## Lokal: ein anderer Spieler hat den Platz bekommen (gleichzeitiges Hinsetzen, der Host entscheidet).
signal local_seat_lost

const PHASE_IDLE := "idle"
const PHASE_BOOT := "boot"
const PHASE_DESKTOP := "desktop"
const PHASE_SHUTDOWN := "shutdown"
const MAX_TEXT_LEN := 40

## Nur lokal: true, solange dieser Spieler das PC-Vollbild offen hat.
var local_fullscreen: bool = false

var phase: String = PHASE_IDLE
var app: String = ""
var detail: String = ""
var user_peer: int = 0
var user_name: String = ""
var cold_boot: bool = false
var typing: bool = false
## Zählt jeden neuen Startvorgang hoch, damit der 3D-Monitor einen neuen Boot erkennt.
var boot_serial: int = 0

var _boot_started_msec: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(_delta: float) -> void:
	if phase != PHASE_IDLE and not NetworkManager.is_in_session:
		_apply(PHASE_IDLE, "", "", 0, "", false, false)


func get_boot_elapsed() -> float:
	return float(Time.get_ticks_msec() - _boot_started_msec) / 1000.0


func is_local_user() -> bool:
	return user_peer != 0 and user_peer == _me()


## true, wenn gerade ein anderer Spieler am PC sitzt. Dann darf sich niemand sonst hinsetzen.
func is_occupied_by_other() -> bool:
	return user_peer != 0 and user_peer != _me()


func get_local_name() -> String:
	if NetworkManager.is_in_session:
		var n: String = NetworkManager.get_player_name(_me())
		if not n.strip_edges().is_empty():
			return n
	return "Admin"


# ---------------------------------------------------------------- Meldungen des Spielers am PC

func report_local(new_phase: String, new_app: String, is_cold: bool, new_detail: String = "") -> void:
	if is_occupied_by_other():
		return
	var me := _me()
	if user_peer == me and phase == new_phase and app == new_app and detail == new_detail and cold_boot == is_cold:
		return
	var keep_typing := typing and user_peer == me
	_send(new_phase, new_app, new_detail, me, get_local_name(), is_cold, keep_typing)


func report_local_typing(is_typing: bool) -> void:
	if not is_local_user() or typing == is_typing:
		return
	_send(phase, app, detail, user_peer, user_name, cold_boot, is_typing)


func report_local_closed() -> void:
	if not is_local_user():
		return
	_send(PHASE_IDLE, "", "", 0, "", false, false)


## Aufstehen: der PC läuft weiter, nur der Platz am Schreibtisch wird frei.
func report_local_released() -> void:
	if not is_local_user():
		return
	if phase == PHASE_SHUTDOWN:
		_send(PHASE_IDLE, "", "", 0, "", false, false)
		return
	_send(phase, app, detail, 0, "", cold_boot, false)


# ---------------------------------------------------------------- Netzwerk

func _send(p_phase: String, p_app: String, p_detail: String, peer: int, pname: String, cold: bool, is_typing: bool) -> void:
	_apply(p_phase, p_app, p_detail, peer, pname, cold, is_typing)
	if _online():
		_rpc_set_state.rpc(p_phase, p_app, p_detail, peer, pname, cold, is_typing)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_state(p_phase: String, p_app: String, p_detail: String, peer: int, pname: String, cold: bool, is_typing: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	# Jeder darf nur seinen eigenen Zustand melden oder den PC wieder freigeben.
	# Der Host darf alles (Stand für neue Mitspieler).
	var allowed := sender == 1 or peer == sender or (peer == 0 and sender == user_peer)
	if not allowed:
		return
	if not [PHASE_IDLE, PHASE_BOOT, PHASE_DESKTOP, PHASE_SHUTDOWN].has(p_phase):
		return
	# Nur einer darf sitzen: ein Platzanspruch, während schon jemand anderes sitzt, wird verworfen.
	# Der Host schickt dann allen seinen Stand, damit sich der zweite Spieler wieder hinstellt.
	if sender != 1 and peer != 0 and user_peer != 0 and user_peer != peer:
		if multiplayer.is_server():
			_rpc_set_state.rpc(phase, app, detail, user_peer, user_name, cold_boot, typing)
		return
	_apply(p_phase, p_app.left(MAX_TEXT_LEN), p_detail.left(MAX_TEXT_LEN), peer, pname.left(MAX_TEXT_LEN), cold, is_typing)


func _apply(p_phase: String, p_app: String, p_detail: String, peer: int, pname: String, cold: bool, is_typing: bool) -> void:
	var was_local := is_local_user()
	if p_phase == PHASE_BOOT and phase != PHASE_BOOT:
		boot_serial += 1
		_boot_started_msec = Time.get_ticks_msec()
	phase = p_phase
	app = p_app
	detail = p_detail
	user_peer = peer
	user_name = pname
	cold_boot = cold
	typing = is_typing
	screen_changed.emit()
	if was_local and peer != 0 and peer != _me():
		local_seat_lost.emit()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server() and NetworkManager.is_in_session and phase != PHASE_IDLE:
		_rpc_set_state.rpc_id(peer_id, phase, app, detail, user_peer, user_name, cold_boot, typing)


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id != user_peer:
		return
	# Verliert der Spieler am PC die Verbindung, bleibt der PC an. Nur ein Herunterfahren wird abgeschlossen.
	if phase == PHASE_SHUTDOWN:
		_apply(PHASE_IDLE, "", "", 0, "", false, false)
	else:
		_apply(phase, app, detail, 0, "", cold_boot, false)


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	if not NetworkManager.is_in_session or mp == null or mp is OfflineMultiplayerPeer:
		return false
	return mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _me() -> int:
	return multiplayer.get_unique_id()