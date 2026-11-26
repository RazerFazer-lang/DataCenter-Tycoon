extends Node
## Root coordinator connecting the 3D World, Orbiting Showcase MenuCamera,
## MainMenu, HUD (+ Ingame Chat & Pause Save), TerminalUI, and Interactive RackInspectorUI.

@onready var world: WorldController = $World
@onready var menu_camera: Camera3D = $MenuCamera
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var hud: GameHUD = $UI/HUD
@onready var terminal_ui: TerminalUI = $UI/TerminalUI
@onready var rack_inspector: RackInspectorUI = $UI/RackInspectorUI

const DedicatedServerScript := preload("res://scripts/server/dedicated_server.gd")

var intro_splash: IntroSplash
var loading_screen: LoadingScreen
var workbench_ui: WorkbenchUI
var admin_ui: AdminUI
var avatar_ui: AvatarEditorUI
var _avatar_from_pause := false
var _is_paused: bool = false
var _menu_orbit_angle: float = 0.0
# Hinsetzen läuft, Vollbild ist noch nicht offen. Der Zähler macht alte Timer ungültig.
var _pc_entering: bool = false
var _pc_enter_token: int = 0
# Der Ladebildschirm läuft einmal beim Programmstart, danach kommt das Hauptmenü.
var _startup_done: bool = false
## Schreibt zu Engine-Fehlern den Spielkontext ins Log (siehe ErrorWatch).
var error_watch: ErrorWatch = null


func _ready() -> void:
	error_watch = ErrorWatch.new()
	error_watch.context_provider = _error_context
	OS.add_logger(error_watch)

	loading_screen = LoadingScreen.new()
	$UI.add_child(loading_screen)
	loading_screen.loading_finished.connect(_on_loading_finished)

	intro_splash = IntroSplash.new()
	$UI.add_child(intro_splash)
	intro_splash.intro_fading_out.connect(_on_intro_fading_out)

	workbench_ui = WorkbenchUI.new()
	$UI.add_child(workbench_ui)
	workbench_ui.visible = false
	workbench_ui.close_requested.connect(_close_workbench_ui)

	admin_ui = AdminUI.new()
	$UI.add_child(admin_ui)
	admin_ui.visible = false
	admin_ui.close_requested.connect(_close_admin)
	hud.admin_requested.connect(_open_admin)
	AdminManager.teleport_requested.connect(_on_admin_teleport)

	avatar_ui = AvatarEditorUI.new()
	$UI.add_child(avatar_ui)
	avatar_ui.closed.connect(_on_avatar_closed)
	hud.avatar_requested.connect(func() -> void: _open_avatar(true))
	world.locker_open_requested.connect(func() -> void: _open_avatar(false))

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
	world.workbench_open_requested.connect(_open_workbench_ui)

	terminal_ui.close_requested.connect(_close_terminal)
	terminal_ui.typing_state_changed.connect(_on_terminal_typing_changed)
	rack_inspector.close_requested.connect(_close_rack_inspector)
	rack_inspector.relocate_rack_requested.connect(_on_relocate_rack_requested)
	hud.resume_requested.connect(_resume_from_pause)
	hud.leave_requested.connect(_leave_to_menu)

	# Dedizierter Server: kein Intro, kein Ladebildschirm, kein Menü, die Welt startet sofort.
	if DedicatedServerScript.is_requested():
		_startup_done = true
		intro_splash.visible = false
		loading_screen.visible = false
		var server := DedicatedServerScript.new()
		server.name = "DedicatedServer"
		add_child(server)
		return

	# Ablauf: Verion-Digital Studio- & Titel-Intro -> nahtloser Ladebildschirm -> 3D-Hauptmenü.
	intro_splash.start_intro()
	_warm_up_views()


## Vor dem Abbau abmelden: Godot meldet beim Beenden noch Dinge, wenn GDScript schon heruntergefahren ist.
func _exit_tree() -> void:
	if error_watch != null:
		OS.remove_logger(error_watch)
		error_watch = null


## Wo war man, als ein Engine-Fehler kam? Eine Zeile fürs Log, ohne persönliche Daten.
func _error_context() -> String:
	var parts := PackedStringArray()
	if not NetworkManager.is_in_session:
		parts.append("Hauptmenü")
	else:
		parts.append("%s, %d Spieler" % ["Host" if multiplayer.is_server() else "Client", NetworkManager.players.size()])
		var lp: Node3D = world.local_player if world != null else null
		if lp != null:
			var p := lp.position
			var site := "Halle Nord" if p.z < -80.0 else ("Garage" if OutdoorWorld.HALL.has_point(Vector2(p.x, p.z)) else "draußen")
			parts.append("%s (%.1f, %.1f, %.1f)" % [site, p.x, p.y, p.z])
		parts.append("Tag %d %s Uhr" % [GameState.day_number, GameState.get_time_string()])
	var open := PackedStringArray()
	for n: Node in [intro_splash, loading_screen, main_menu, terminal_ui, rack_inspector, workbench_ui, admin_ui, avatar_ui]:
		if n != null and n is CanvasItem and (n as CanvasItem).visible:
			open.append(n.get_class() if n.get_script() == null else str((n.get_script() as Script).get_global_name()))
	if _is_paused:
		open.append("Pause")
	parts.append("offen: " + (", ".join(open) if not open.is_empty() else "nichts"))
	parts.append("%.1f s nach Start, Bild %d, %d Knoten" % [Time.get_ticks_msec() / 1000.0, Engine.get_frames_drawn(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	return " | ".join(parts)


## Blickpunkte, die beim ersten Hinsehen sonst kurz ruckeln (Shader, Pipelines, Texturen).
const WARM_SPOTS := [
	[Vector3(0.5, 1.65, 2.0), Vector3(0.0, 1.0, -3.0)],
	[Vector3(1.0, 1.7, 0.5), Vector3(20.0, 1.2, 0.0)],
	[Vector3(0.0, 1.65, 2.0), Vector3(0.0, 1.3, 14.0)],
	[Vector3(-3.0, 1.7, 14.0), Vector3(3.0, 1.5, 0.0)],
	[Vector3(-9.0, 1.7, 9.0), Vector3(25.0, 1.5, -5.0)],
	[Vector3(-9.5, 1.7, -8.5), Vector3(20.0, 2.5, -6.0)],
	[Vector3(2.0, 6.0, -2.0), Vector3(20.0, 14.0, 12.0)],
	[Vector3(2.0, 6.0, -2.0), Vector3(20.0, 2.0, 20.0)],
	[Vector3(-6.0, 1.7, -322.0), Vector3(6.0, 1.0, -318.0)],
]


## Einmal je Programmstart auch beim ersten Betreten der Welt (siehe _warm_up_session).
var _session_warmed := false


## Hinter dem deckenden Intro bzw. Ladebildschirm einmal durch die wichtigen Blickpunkte fahren: Was
## dort zu sehen ist, wird schon jetzt einmal gezeichnet, nicht erst beim ersten Hinsehen im Spiel.
## Sobald nichts Deckendes mehr davor liegt (Intro übersprungen und ausgeblendet), hört es auf.
func _warm_up_views() -> void:
	await _sweep_views(menu_camera, func() -> bool:
		if _startup_done or NetworkManager.is_in_session:
			return false
		return (intro_splash.visible and intro_splash.modulate.a >= 0.999) or (loading_screen.visible and loading_screen.modulate.a >= 0.999))
	if not NetworkManager.is_in_session:
		menu_camera.current = true


## Im Spiel sehen Lampen, Tageszeit und Figuren anders aus als im Menü, dafür braucht die Grafikkarte
## eigene Varianten. Deshalb beim ersten Betreten noch einmal kurz hinter dem Ladebildschirm.
func _warm_up_session() -> void:
	if _session_warmed or DisplayServer.get_name() == "headless":
		return
	_session_warmed = true
	loading_screen.start_loading("BETRETE RECHENZENTRUM…", 1.6)
	# Auf die eigene Figur warten: Deren Kamera ist die Vorlage (Sichtfeld, Ebenen, Weite).
	var t0 := Time.get_ticks_msec()
	while (world.local_player == null or get_viewport().get_camera_3d() == null or get_viewport().get_camera_3d() == menu_camera) \
			and Time.get_ticks_msec() - t0 < 1000:
		await get_tree().process_frame
	var player_cam := get_viewport().get_camera_3d()
	if player_cam == null or player_cam == menu_camera:
		return
	await _sweep_views(player_cam, func() -> bool:
		return NetworkManager.is_in_session and loading_screen.visible and loading_screen.modulate.a >= 0.999)
	if is_instance_valid(player_cam) and NetworkManager.is_in_session:
		player_cam.current = true


## Eine eigene Kamera (Einstellungen wie template) durch WARM_SPOTS fahren, solange covered() gilt.
func _sweep_views(template: Camera3D, covered: Callable) -> void:
	var cam := Camera3D.new()
	cam.name = "WarmUpCamera"
	cam.cull_mask = template.cull_mask
	cam.near = template.near
	cam.far = maxf(template.far, 500.0)
	cam.fov = template.fov
	cam.attributes = template.attributes
	cam.environment = template.environment
	menu_camera.get_parent().add_child(cam)
	await get_tree().process_frame
	for sp in WARM_SPOTS:
		if not bool(covered.call()):
			break
		cam.current = true
		cam.global_position = sp[0]
		cam.look_at(sp[1], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
	cam.queue_free()


func _on_intro_fading_out() -> void:
	loading_screen.start_loading("STARTE RECHENZENTRUM…", 1.95)


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
	if (main_menu.visible or loading_screen.visible) and not NetworkManager.is_in_session and menu_camera != null:
		# Smooth AAA cinematic glide framed so the Showcase Racks & Workstation shine in the open right viewport!
		_menu_orbit_angle += delta * 0.13
		var cam_pos := Vector3(
			1.25 + cos(_menu_orbit_angle) * 2.85,
			2.05 + sin(_menu_orbit_angle * 0.65) * 0.24,
			1.55 + sin(_menu_orbit_angle) * 1.85
		)
		menu_camera.position = cam_pos
		menu_camera.look_at(Vector3(-1.35, 1.25, -2.55), Vector3.UP)


## Fokusverlust (Windows-Taste, Alt+Tab): Maus freigeben, damit man andere Fenster bedienen kann.
## Ist die Maus im Spiel gefangen, geht das Pausemenü auf; offene Menüs zeigen die Maus ohnehin schon.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		return
	_release_mouse_for_os()


## Gibt die gefangene Maus an Windows zurück (Fokusverlust oder Windows-Taste).
func _release_mouse_for_os() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if NetworkManager.is_in_session and not _is_paused and not _pc_entering and not terminal_ui.visible and not rack_inspector.visible and not workbench_ui.visible:
		_open_pause()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Windows-Taste: Startmenü und andere Fenster sollen sofort bedienbar sein.
	# Die Taste wird nicht als behandelt markiert, damit Windows sie weiter bekommt.
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_META:
		_release_mouse_for_os()
		return

	if not NetworkManager.is_in_session:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Beim Umbenennen gehören alle Tasten dem Eingabefeld. [ESC] bricht nur die Eingabe ab.
		if rack_inspector.visible and rack_inspector.is_typing():
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				rack_inspector.cancel_typing()
			return
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if avatar_ui.visible:
				avatar_ui.close()
			elif admin_ui.visible:
				_close_admin()
			elif workbench_ui != null and workbench_ui.visible:
				_close_workbench_ui()
			elif rack_inspector.visible and rack_inspector.is_preview_fullscreen():
				rack_inspector.set_preview_fullscreen(false)
			elif rack_inspector.visible:
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

		if event.is_action_pressed("admin_menu"):
			get_viewport().set_input_as_handled()
			if admin_ui.visible:
				_close_admin()
			else:
				_open_admin()
			return

		# [E] schließt das Rack-Menü wieder (beim Umbenennen oben bereits abgefangen).
		if rack_inspector.visible and event.is_action_pressed("interact"):
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
	_warm_up_session()


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
	hud.show_toast(tr("PC besetzt: %s sitzt gerade davor") % PcScreenState.user_name, true)


func _on_session_left(_reason: String) -> void:
	_return_to_menu_ui()


func _leave_to_menu() -> void:
	if NetworkManager.is_in_session and multiplayer.is_server() and SettingsManager.autosave_enabled:
		GameState.save_current_world("", true)
	NetworkManager.leave_session()
	_return_to_menu_ui()
	main_menu.show_status(tr("Sitzung beendet."))


func _return_to_menu_ui() -> void:
	admin_ui.visible = false
	avatar_ui.close()
	_is_paused = false
	_pc_entering = false
	_pc_enter_token += 1
	if workbench_ui != null and workbench_ui.visible:
		workbench_ui.close_workbench()
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


func _open_workbench_ui() -> void:
	if _is_paused or terminal_ui.visible or rack_inspector.visible or workbench_ui == null:
		return
	var worker := GameState.get_workbench_worker()
	if worker > 0 and worker != multiplayer.get_unique_id():
		hud.show_toast(tr("Werkbank besetzt: %s arbeitet gerade") % NetworkManager.get_player_name(worker), true)
		return
	workbench_ui.open_workbench()
	if workbench_ui.visible:
		hud.visible = false
		if world.local_player != null:
			world.local_player.set_ui_locked(true)
			world.local_player.enter_workbench(workbench_ui.prop.global_position)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_workbench_ui() -> void:
	if workbench_ui != null and workbench_ui.visible:
		# Löst close_requested aus und landet damit noch einmal hier.
		workbench_ui.close_workbench()
		return
	hud.visible = NetworkManager.is_in_session
	if world.local_player != null:
		world.local_player.exit_workbench()
		world.local_player.set_ui_locked(false)
	if NetworkManager.is_in_session:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_relocate_rack_requested(rack_id: String) -> void:
	_close_rack_inspector()
	if GameState.decor_items.has(rack_id):
		if world.local_player != null:
			world.local_player.start_relocate_decor(rack_id)
		return
	world.start_relocate_rack(rack_id)


func _open_admin() -> void:
	if not AdminManager.is_local_admin() and not AdminManager.login_available:
		return
	# Nicht über andere Vollbild-Ansichten legen.
	if terminal_ui.visible or rack_inspector.visible or workbench_ui.visible or _pc_entering:
		return
	if _is_paused:
		_resume_from_pause()
	admin_ui.open()
	if world.local_player != null:
		world.local_player.set_ui_locked(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_admin() -> void:
	if not admin_ui.visible:
		return
	admin_ui.visible = false
	if not NetworkManager.is_in_session:
		return
	if world.local_player != null:
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_admin_teleport(pos: Vector3, yaw: float) -> void:
	if terminal_ui.visible:
		_close_terminal()
	if workbench_ui.visible:
		_close_workbench_ui()
	if world.local_player != null:
		world.local_player.admin_teleport(pos, yaw)


## Figuren-Editor im Spiel: aus dem Pausemenü oder am Spind.
func _open_avatar(from_pause: bool) -> void:
	if terminal_ui.visible or rack_inspector.visible or workbench_ui.visible or admin_ui.visible or _pc_entering:
		return
	_avatar_from_pause = from_pause
	if from_pause:
		hud.set_pause_visible(false)
	hud.visible = false
	avatar_ui.open()
	if world.local_player != null:
		world.local_player.set_ui_locked(true)
		world.local_player.at_locker = not from_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_avatar_closed() -> void:
	if world.local_player != null:
		world.local_player.at_locker = false
	if not NetworkManager.is_in_session:
		return
	hud.visible = true
	if _avatar_from_pause:
		_open_pause()
		return
	if world.local_player != null:
		world.local_player.set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
