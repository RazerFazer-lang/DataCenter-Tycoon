extends Node
## Root coordinator connecting the 3D World, Orbiting Showcase MenuCamera,
## MainMenu, HUD (+ Ingame Chat & Pause Save), TerminalUI, and Interactive RackInspectorUI.

@onready var world: WorldController = $World
@onready var menu_camera: Camera3D = $MenuCamera
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var hud: GameHUD = $UI/HUD
@onready var terminal_ui: TerminalUI = $UI/TerminalUI
@onready var rack_inspector: RackInspectorUI = $UI/RackInspectorUI

var loading_screen: LoadingScreen
var _is_paused: bool = false
var _menu_orbit_angle: float = 0.0
# Hinsetzen läuft, Vollbild ist noch nicht offen. Der Zähler macht alte Timer ungültig.
var _pc_entering: bool = false
var _pc_enter_token: int = 0
# Der Ladebildschirm läuft einmal beim Programmstart, danach kommt das Hauptmenü.
var _startup_done: bool = false


func _ready() -> void:
	loading_screen = LoadingScreen.new()
	$UI.add_child(loading_screen)
	loading_screen.loading_finished.connect(_on_loading_finished)

	hud.bind_world(world)
	hud.visible = false
	terminal_ui.visible = false
	rack_inspector.visible = false
	# Das Hauptmenü erscheint erst nach dem Ladebildschirm.
	main_menu.visible = false
	world.show_menu_showcase()
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	PcScreenState.local_seat_lost.connect(_on_pc_seat_lost)
	NetworkManager.connection_succeeded.connect(_on_session_entered)
	NetworkManager.disconnected_from_session.connect(_on_session_left)

	world.terminal_open_requested.connect(_open_terminal)
	world.rack_inspect_requested.connect(_open_rack_inspector)
	world.device_inspect_requested.connect(_open_device_inspector)

	terminal_ui.close_requested.connect(_close_terminal)
	terminal_ui.typing_state_changed.connect(_on_terminal_typing_changed)
	rack_inspector.close_requested.connect(_close_rack_inspector)
	rack_inspector.relocate_rack_requested.connect(_on_relocate_rack_requested)
	hud.resume_requested.connect(_resume_from_pause)
	hud.leave_requested.connect(_leave_to_menu)

	# Ablauf: Ladebildschirm, dann Hauptmenü, dann per Klick die Welt.
	loading_screen.start_loading("STARTE RECHENZENTRUM…", 2.4)


func _apply_launcher_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var mode := ""
	var join_ip := "127.0.0.1"
	var port := NetworkManager.DEFAULT_PORT
	var player_name := SettingsManager.player_name
	var world_name := "Garage Cloud GmbH"
	var load_id := ""

	for raw in args:
		var a := str(raw).strip_edges()
		if a == "--host":
			mode = "host"
		elif a.begins_with("--join="):
			mode = "join"
			join_ip = a.substr(7)
		elif a.begins_with("--load="):
			mode = "load"
			load_id = a.substr(7)
		elif a.begins_with("--name="):
			player_name = a.substr(7).left(18)
		elif a.begins_with("--world="):
			world_name = a.substr(8).left(32)
		elif a.begins_with("--port="):
			var p := int(a.substr(7))
			if p > 1024 and p < 65535:
				port = p
		elif a.begins_with("--quality="):
			SettingsManager.graphics_quality = clampi(int(a.substr(10)), 0, 3)
			SettingsManager.save_settings()

	# Kein Direktstart mehr: die Launcher-Werte landen im Hauptmenü, die Welt startet per Klick.
	if mode == "load" and load_id.is_empty():
		mode = ""
	main_menu.apply_launcher_prefill(mode, player_name, world_name, join_ip, port)


func _process(delta: float) -> void:
	if main_menu.visible and menu_camera != null:
		# Smooth AAA cinematic glide framed so the Showcase Racks & Workstation shine in the open right viewport!
		_menu_orbit_angle += delta * 0.13
		var cam_pos := Vector3(
			1.25 + cos(_menu_orbit_angle) * 2.85,
			2.05 + sin(_menu_orbit_angle * 0.65) * 0.24,
			1.55 + sin(_menu_orbit_angle) * 1.85
		)
		menu_camera.position = cam_pos
		menu_camera.look_at(Vector3(-1.35, 1.25, -2.55), Vector3.UP)


func _input(event: InputEvent) -> void:
	if not NetworkManager.is_in_session:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if rack_inspector.visible:
				_close_rack_inspector()
			elif _pc_entering:
				_cancel_pc_enter()
			elif terminal_ui.visible:
				_close_terminal()
			elif _is_paused:
				_resume_from_pause()
			else:
				_open_pause()
			return

		# Pressing F again closes the Rack Inspector smoothly
		if rack_inspector.visible and event.is_action_pressed("inspect_rack"):
			get_viewport().set_input_as_handled()
			_close_rack_inspector()
			return


func _on_session_entered() -> void:
	_is_paused = false
	main_menu.visible = false
	terminal_ui.visible = false
	rack_inspector.visible = false
	hud.visible = true
	hud.set_pause_visible(false)
	world.activate_session()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_loading_finished() -> void:
	if _startup_done:
		return
	_startup_done = true
	main_menu.visible = true
	main_menu.refresh_on_show()
	_apply_launcher_cli_args()


## Ein anderer Spieler hat den PC-Platz bekommen: aufstehen und kurz Bescheid geben.
func _on_pc_seat_lost() -> void:
	if _pc_entering:
		_cancel_pc_enter()
	elif terminal_ui.visible:
		_close_terminal()
	hud.show_toast("PC besetzt: %s sitzt gerade davor" % PcScreenState.user_name, true)


func _on_session_left(_reason: String) -> void:
	_return_to_menu_ui()


func _leave_to_menu() -> void:
	if NetworkManager.is_in_session and multiplayer.is_server() and SettingsManager.autosave_enabled:
		GameState.save_current_world("", true)
	NetworkManager.leave_session()
	_return_to_menu_ui()
	main_menu.show_status("Sitzung beendet.")


func _return_to_menu_ui() -> void:
	_is_paused = false
	_pc_entering = false
	_pc_enter_token += 1
	world.reset_world()
	world.show_menu_showcase()
	hud.visible = false
	hud.set_pause_visible(false)
	terminal_ui.visible = false
	rack_inspector.visible = false
	main_menu.visible = true
	main_menu.refresh_on_show()
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_terminal() -> void:
	if _is_paused or rack_inspector.visible or terminal_ui.visible or _pc_entering:
		return
	if world.local_player == null:
		terminal_ui.open_terminal()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# Hinsetzen, PC einschalten, an den Monitor heranfahren, dann Vollbild.
	_pc_entering = true
	_pc_enter_token += 1
	var token := _pc_enter_token
	world.local_player.set_ui_locked(true)
	world.local_player.enter_pc_seat()
	terminal_ui.power_on_pc()
	await get_tree().create_timer(world.local_player.get_pc_focus_duration()).timeout
	if token != _pc_enter_token or not _pc_entering:
		return
	_pc_entering = false
	terminal_ui.open_terminal()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cancel_pc_enter() -> void:
	_pc_entering = false
	_pc_enter_token += 1
	terminal_ui.cancel_power_on()
	if world.local_player != null:
		world.local_player.exit_pc_seat()
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_terminal() -> void:
	terminal_ui.close_terminal()
	if world.local_player != null:
		world.local_player.exit_pc_seat()
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_terminal_typing_changed(is_typing: bool) -> void:
	if world.local_player != null:
		world.local_player.set_typing_at_pc(is_typing)
	PcScreenState.report_local_typing(is_typing)


func _open_rack_inspector(rack_id: String, slot_index: int) -> void:
	if _is_paused or terminal_ui.visible:
		return
	rack_inspector.open_rack(rack_id, slot_index)
	if world.local_player != null:
		world.local_player.set_ui_locked(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_device_inspector(kind: String, entity_id: String) -> void:
	if _is_paused or terminal_ui.visible:
		return
	rack_inspector.open_device(kind, entity_id)
	if world.local_player != null:
		world.local_player.set_ui_locked(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_rack_inspector() -> void:
	rack_inspector.close_inspector()
	if world.local_player != null:
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_relocate_rack_requested(rack_id: String) -> void:
	_close_rack_inspector()
	world.start_relocate_rack(rack_id)


func _open_pause() -> void:
	_is_paused = true
	hud.set_pause_visible(true)
	if world.local_player != null:
		world.local_player.set_ui_locked(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_from_pause() -> void:
	_is_paused = false
	hud.set_pause_visible(false)
	if world.local_player != null:
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
