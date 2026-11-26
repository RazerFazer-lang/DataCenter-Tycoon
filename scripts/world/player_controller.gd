class_name PlayerController
extends CharacterBody3D
## Represents both the local First-Person Player and stylized articulated Remote Co-op Avatars.
## Integrates SettingsManager (mouse sensitivity, FOV), smooth walk animations, placement ghosts,
## 3D cable pulling, hardware repair, fire extinguishing, and smooth remote sync.

const MOVE_SPEED := 4.8
const SPRINT_SPEED := 7.4
const JUMP_VELOCITY := 4.6
const GRAVITY := 13.5
## Ducken: Kapselhöhe, Kamerahöhe und Tempo im Stehen bzw. geduckt.
const CROUCH_SPEED := 2.4
const STAND_HEIGHT := 1.72
const CROUCH_HEIGHT := 1.12
const STAND_HEAD_Y := 1.56
const CROUCH_HEAD_Y := 0.98
## Etwas schmaler als der Körper, damit eine Wand direkt daneben das Aufstehen nicht blockiert.
const STAND_PROBE_RADIUS := 0.32
## Zielhilfe für Kabelanschlüsse: maximaler Abstand des Ports quer zur Blickrichtung (Meter).
const PORT_ASSIST_RADIUS := 0.16
## Liegt ein Hindernis näher als das am Port, zählt er trotzdem als sichtbar (Ports sitzen bündig am Gehäuse).
const PORT_ASSIST_SIGHT_SLACK := 0.25
const INTERACT_RANGE := 3.6
const PLACE_RANGE := 5.5

var peer_id: int = 1
var is_local: bool = false
var player_name: String = "Spieler"
var avatar_color: Color = Color(0.22, 0.72, 0.98)

var cable_active_type: String = "" # "" | "power" | "network"
var cable_start_id: String = ""
## Slot-System: Tasten 1-4 wählen den aktiven Slot. Was darin liegt, legt erst die Aufnahme fest.
## cable_start_id / cable_active_type gehören immer zum aktiven Slot, die übrigen Slots liegen hier.
var active_slot: int = 1
var _slot_cables: Array = [{}, {}, {}, {}]
var relocating_rack_id: String = ""
var place_rot_y: float = 0.0
var _ghost_strip_link: String = ""
var _rot_manual: bool = false   # selbst gedreht: die Wand bestimmt die Richtung nicht mehr
var hold_yaw: float = 0.0       # Drehung der getragenen Ware
var _hold_cid: String = ""

var ui_locked: bool = false
var is_seated_at_pc: bool = false
var is_at_workbench: bool = false
var _workbench_pos: Vector3 = Vector3.ZERO
var is_typing_at_pc: bool = false
var _pre_seat_pos: Vector3 = Vector3(2.78, 0.0, -2.05)
var _pre_seat_yaw: float = 0.0
var _stand_blend_timer: float = 0.0
var _remote_pose_flag: int = 0 # 0 steht, 1 sitzt am PC, 2 tippt, 3 duckt sich, 4 Sofa/Bank, 5 Werkbank, 6 Leiter, 7 in der Luft

# Kamerafahrt an den Monitor: erst hinsetzen, dann heranfahren, bis der Bildschirm das Bild füllt.
const PC_SIT_SETTLE := 0.45
const PC_FOCUS_TIME := 1.15
const PC_UNFOCUS_TIME := 0.5
const PC_FOCUS_FOV := 50.0
const PC_FOCUS_FILL := 1.04
var _pc_sit_time: float = 0.0
var _pc_focus: float = 0.0
var _pc_cam_moved: bool = false
var _pc_screen: MeshInstance3D = null
var current_prompt: String = ""
var current_sub_prompt: String = ""

var _world: Node = null
var _camera: Camera3D
var _ray: RayCast3D
var _head_pivot: Node3D
var _avatar_root: Node3D
var _human: HumanModel
var _nametag: Label3D

# Held visual (shown in first-person corner OR in remote avatar's hands)
var _held_root: Node3D
var _held_item_holder: Node3D
## Ich-Ansicht: eigene Arme (FpArms).
var _fp: FpArms
var _vm_from := Vector3.ZERO
var _last_aim := Vector3.ZERO
var _emote_wheel: EmoteWheel
var _held_half_w := 0.24
var _held_half_xz := Vector2(0.23, 0.23)
var _held_item_type_cached: String = ""
var _held_extinguisher: Node3D
var _foam_root: Node3D
## Schlaghebel des Feuerlöschers in der Hand: wird beim Sprühen heruntergedrückt.
var _held_lever_pivot: Node3D
const EXT_LEVER_PRESS_DEG := 8.0
var _foam_balls: Array[MeshInstance3D] = []

# AAA Viewmodel-Physik (Maus-Trägheit, Lauf-Bob, Aufnehmen-Spring, Landedämpfer)
var _vm_sway: Vector2 = Vector2.ZERO
var _vm_equip: float = 0.0
var _vm_land_dip: float = 0.0
var _cam_weight_dip: float = 0.0
var _emote_badge: Label3D
var _emote_timer: float = 0.0
var _emote_id: String = ""
## Auf einer Leiter (Dach).
var on_ladder := false
var _was_on_floor: bool = true
var _vm_last_state_key: String = ""

# AAA 3D-Hologramm-Platzierung & Boden-Ablege-Vorschau (local only)
var _ghost_root: Node3D
var _ghost_model_holder: Node3D
var _ghost_footprint: Node3D
var _ghost_front_arrow: Node3D
var _ghost_drop_ring: MeshInstance3D
var _ghost_holo_mat: ShaderMaterial
var _ghost_frame_mat: StandardMaterial3D
var _ghost_model_key: String = ""
var _ghost_is_drop_preview: bool = false
var _ghost_valid: bool = false
var _ghost_rot_y: float = 0.0
var _ghost_pos: Vector3 = Vector3.ZERO
var _ghost_visual_pos: Vector3 = Vector3.ZERO
var _ghost_visual_rot: float = 0.0
var _ghost_has_visual_pose: bool = false
var _hovered_shelf: Object = null
var _hovered_rack: Object = null
var _ui_unlock_cooldown: float = 0.0

# Remote interpolation targets
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _remote_spraying: bool = false

# Timers & animation state
var _net_send_accum: float = 0.0
var _action_tick_accum: float = 0.0
var _is_spraying_local: bool = false
var _anim_time: float = 0.0
var _walk_cycle: float = 0.0
var _footstep_accum: float = 0.0

# Ducken (nur lokaler Spieler)
var is_crouching: bool = false
var _body_col: CollisionShape3D
var _body_shape: CapsuleShape3D
var _stand_probe: CapsuleShape3D

var skin_data: Dictionary = {}
## Haltung der Mitspieler: zuletzt gesehener Gegenstand in der Hand.
var _remote_held := ""
var seat_kind := ""
var _talk_left := 0.0
## Steht am Spind (Editor offen): Tür geht auf.
var at_locker := false


func setup(p_peer_id: int, p_is_local: bool, p_name: String, p_color: Color, world_ref: Node) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	player_name = p_name
	avatar_color = p_color
	_world = world_ref


## Aussehen setzen (auch während der Sitzung).
func apply_skin(skin: Variant) -> void:
	skin_data = SettingsManager.sanitize_skin(skin)
	if _avatar_root != null:
		_build_human()
	if _fp != null:
		_fp.set_look(skin_data)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_target_pos = position

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = STAND_HEIGHT
	col.shape = cap
	col.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)
	add_child(col)
	_body_col = col
	_body_shape = cap
	_stand_probe = CapsuleShape3D.new()
	_stand_probe.radius = STAND_PROBE_RADIUS
	_stand_probe.height = STAND_HEIGHT

	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0.0, 1.56, 0.0)
	add_to_group("player_body")
	add_child(_head_pivot)

	_build_avatar_visuals()
	_build_held_visuals()

	if is_local:
		add_to_group("local_player")
		_nametag.visible = false

		_camera = Camera3D.new()
		_camera.fov = SettingsManager.fov
		_camera.near = 0.06
		_camera.far = 320.0
		_head_pivot.add_child(_camera)
		_camera.current = true
		SettingsManager.settings_changed.connect(_on_settings_changed)
	GameState.player_emote_received.connect(_on_player_emote_received)
	NetworkManager.chat_message_received.connect(_on_chat)
	if is_local:

		_ray = RayCast3D.new()
		_ray.target_position = Vector3(0.0, 0.0, -INTERACT_RANGE)
		_ray.collision_mask = 1 | 4
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = true
		_camera.add_child(_ray)

		_held_root.position = Vector3(0.36, -0.30, -0.62)
		_held_root.scale = Vector3(0.62, 0.62, 0.62)
		_camera.add_child(_held_root)
		for vi in _held_extinguisher.find_children("*", "VisualInstance3D", true, false):
			(vi as VisualInstance3D).layers = FpArms.LAYER
		_fp = FpArms.new()
		_camera.add_child(_fp)
		_fp.set_look(skin_data if not skin_data.is_empty() else SettingsManager.get_skin())

		_build_placement_ghost()
	else:
		_held_root.position = Vector3(0.0, 1.05, -0.58)
		_held_root.scale = Vector3(0.75, 0.75, 0.75)
		add_child(_held_root)


func _exit_tree() -> void:
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()


func _on_settings_changed() -> void:
	if _camera != null:
		_camera.fov = SettingsManager.fov


func apply_remote_pose(pos: Vector3, yaw: float, pitch: float, p_tool: int, spraying: bool) -> void:
	if is_local:
		return
	_target_pos = pos
	_target_yaw = yaw
	_target_pitch = pitch
	_remote_pose_flag = p_tool
	_remote_spraying = spraying


func enter_pc_seat() -> void:
	if not is_local:
		return
	if not is_seated_at_pc:
		_pre_seat_pos = Vector3(clampf(position.x, 1.6, 4.2), 0.0, maxf(position.z, -2.15))
		_pre_seat_yaw = rotation.y
	is_seated_at_pc = true
	is_typing_at_pc = false
	_stand_blend_timer = 0.0
	_pc_sit_time = 0.0
	SfxManager.play("chair_sit", -8.0, 1.0)


func exit_pc_seat() -> void:
	if not is_local:
		return
	if is_seated_at_pc:
		is_seated_at_pc = false
		is_typing_at_pc = false
		_stand_blend_timer = 0.38
		SfxManager.play("chair_sit", -11.0, 1.18)


## An der Werkbank: eigene Figur ausblenden (die Werkbank-Kamera übernimmt) und zum Tisch drehen.
func enter_workbench(bench_pos: Vector3) -> void:
	if not is_local:
		return
	is_at_workbench = true
	_workbench_pos = bench_pos
	visible = false


func exit_workbench() -> void:
	if not is_local or not is_at_workbench:
		return
	is_at_workbench = false
	visible = true
	if _camera != null:
		_camera.make_current()


var _sofa_id := ""
var _sofa_time := 0.0
var _sofa_rested := false


## Auf das Sofa setzen. Jede Bewegungstaste steht wieder auf.
func sit_on_sofa(did: String) -> void:
	if not is_local or _sofa_id != "" or not GameState.decor_items.has(did):
		return
	_sofa_id = did
	_sofa_time = 0.0
	_sofa_rested = false
	_pre_seat_pos = position
	SfxManager.play("chair_sit", -8.0, 0.85)


func _process_sofa(delta: float) -> void:
	var d: Dictionary = GameState.decor_items.get(_sofa_id, {})
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.2 or Input.is_action_just_pressed("jump")
	if d.is_empty() or ui_locked or (moving and _sofa_time > 0.4):
		_sofa_id = ""
		_stand_blend_timer = 0.30
		SfxManager.play("chair_sit", -12.0, 1.2)
		return
	_sofa_time += delta
	var ry := float(d.get("rot_y", 0.0))
	var fwd := Vector3(sin(ry), 0.0, cos(ry))
	var side := Vector3(cos(ry), 0.0, -sin(ry))
	# Auf die Seite setzen, von der man kommt: so haben zwei Platz.
	var off := clampf((_pre_seat_pos - (d["pos"] as Vector3)).dot(side), -0.45, 0.45)
	var target: Vector3 = (d["pos"] as Vector3) + fwd * 0.10 + side * (0.45 if off >= 0.0 else -0.45)
	position = position.lerp(Vector3(target.x, 0.0, target.z), clampf(delta * 8.0, 0.0, 1.0))
	if _sofa_time < 0.7:
		rotation.y = lerp_angle(rotation.y, ry + PI, clampf(delta * 8.0, 0.0, 1.0))
	_head_pivot.position.y = lerpf(_head_pivot.position.y, 1.10, clampf(delta * 8.0, 0.0, 1.0))
	velocity = Vector3.ZERO
	if _sofa_time >= DecorManager.REST_SIT_TIME and not _sofa_rested:
		_sofa_rested = true
		DecorManager.request_rest(_sofa_id)
		SfxManager.play("save", -12.0, 1.1)


var _bench_pos := Vector3.ZERO
var _bench_yaw := 0.0
var _bench_time := 0.0
var _bench_rested := false
var _ladder_y := 0.0


## Auf eine Gartenbank setzen. Jede Bewegung steht wieder auf.
func sit_on_bench(target: Node3D) -> void:
	if not is_local or seat_kind != "" or target == null or GameState.is_player_holding_anything(peer_id):
		SfxManager.play("error")
		return
	seat_kind = "bench"
	_bench_time = 0.0
	_bench_rested = false
	_pre_seat_pos = position
	_bench_yaw = deg_to_rad(float(target.get_meta("yaw", 0.0)))
	var side := Vector3(cos(_bench_yaw), 0.0, -sin(_bench_yaw))
	var off := 0.42 if (position - target.global_position).dot(side) >= 0.0 else -0.42
	_bench_pos = Vector3(target.global_position.x, 0.0, target.global_position.z) + side * off
	SfxManager.play("chair_sit", -8.0, 0.9)


func _process_bench(delta: float) -> void:
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.2 or Input.is_action_just_pressed("jump")
	if ui_locked or (moving and _bench_time > 0.4):
		seat_kind = ""
		_stand_blend_timer = 0.30
		SfxManager.play("chair_sit", -12.0, 1.2)
		return
	_bench_time += delta
	position = position.lerp(_bench_pos, clampf(delta * 8.0, 0.0, 1.0))
	if _bench_time < 0.7:
		rotation.y = lerp_angle(rotation.y, _bench_yaw + PI, clampf(delta * 8.0, 0.0, 1.0))
	_head_pivot.position.y = lerpf(_head_pivot.position.y, 1.16, clampf(delta * 8.0, 0.0, 1.0))
	velocity = Vector3.ZERO
	if _bench_time >= OutdoorManager.BENCH_REST and not _bench_rested:
		_bench_rested = true
		OutdoorManager.request_use("bench")
		SfxManager.play("save", -12.0, 1.1)


## Leiter zum Dach: [E] steigt ein, vor und zurück klettert, Springen lässt los.
func start_ladder(from_top: bool) -> void:
	if not is_local or on_ladder:
		return
	if GameState.is_player_holding_anything(peer_id):
		SfxManager.play("error")
		return
	on_ladder = true
	velocity = Vector3.ZERO
	_ladder_y = OutdoorWorld.ROOF_Y - 0.1 if from_top else 0.05
	SfxManager.play("part_touch", -8.0, 0.8)


func _process_ladder(delta: float) -> void:
	var foot := OutdoorWorld.LADDER_POS + Vector3(0.0, 0.0, -0.58)
	var inp := 0.0 if ui_locked else Input.get_axis("move_back", "move_forward")
	# Beim Hinunterschauen geht vorwärts nach unten.
	if _head_pivot.rotation.x < -0.9 and position.y > 1.0:
		inp = -inp
	_ladder_y += inp * 1.9 * delta
	velocity = Vector3(0.0, inp * 1.9, 0.0)
	_footstep_accum += absf(inp) * delta
	if _footstep_accum > 0.42:
		_footstep_accum = 0.0
		SfxManager.play("step_raised", -10.0, randf_range(1.1, 1.25))
	position = position.lerp(Vector3(foot.x, _ladder_y, foot.z), clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, PI, clampf(delta * 6.0, 0.0, 1.0)) if absf(inp) > 0.1 else rotation.y
	_head_pivot.position.y = lerpf(_head_pivot.position.y, STAND_HEAD_Y, clampf(delta * 8.0, 0.0, 1.0))
	if _ladder_y > OutdoorWorld.ROOF_Y + 0.15:
		on_ladder = false
		velocity = Vector3.ZERO
		position = Vector3(foot.x, OutdoorWorld.ROOF_Y + 0.08, -4.15)
	elif _ladder_y < 0.0 or (not ui_locked and Input.is_action_just_pressed("jump")):
		on_ladder = false
		velocity = Vector3.ZERO
		position = Vector3(foot.x, maxf(0.05, position.y), foot.z - 0.45)


func set_typing_at_pc(active: bool) -> void:
	is_typing_at_pc = active and is_seated_at_pc


func start_relocate_rack(rack_id: String) -> void:
	if not is_local or not GameState.racks.has(rack_id):
		return
	cable_start_id = ""
	relocating_rack_id = rack_id
	place_rot_y = float(GameState.racks[rack_id].get("rot_y", 0.0))
	SfxManager.play("pickup", -8.0)


func start_relocate_decor(decor_id: String) -> void:
	if not is_local or not GameState.decor_items.has(decor_id):
		return
	cable_start_id = ""
	relocating_rack_id = decor_id
	place_rot_y = float((GameState.decor_items[decor_id] as Dictionary).get("rot_y", 0.0))
	SfxManager.play("pickup", -8.0)


func _relocating_name() -> String:
	if GameState.decor_items.has(relocating_rack_id):
		return tr(GameState.get_decor_name(relocating_rack_id))
	return GameState.get_rack_display_name(relocating_rack_id)


func set_ui_locked(locked: bool) -> void:
	var was_locked := ui_locked
	ui_locked = locked
	if ui_locked:
		if _emote_wheel != null:
			_emote_wheel.visible = false
		_is_spraying_local = false
		current_prompt = ""
		current_sub_prompt = ""
		_clear_shelf_hover()
		_clear_rack_hover()
	elif was_locked:
		# Kurze Sperrfrist nach UI-Schließen (z. B. Rack verkaufen), damit Klick/E kein gehaltenes Item wegwirft oder abstellt!
		_ui_unlock_cooldown = 0.18


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or ui_locked:
		return

	if event is InputEventMouseMotion and _emote_wheel != null and _emote_wheel.visible:
		_emote_wheel.move((event as InputEventMouseMotion).relative)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := SettingsManager.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		_head_pivot.rotation.x = clampf(
			_head_pivot.rotation.x - event.relative.y * sens,
			deg_to_rad(-82.0),
			deg_to_rad(82.0)
		)
		# Sanfte AAA-Maus-Trägheit für gehaltene Objekte & Hände
		_vm_sway.x = clampf(_vm_sway.x - event.relative.x * 0.00055, -0.055, 0.055)
		_vm_sway.y = clampf(_vm_sway.y + event.relative.y * 0.00045, -0.042, 0.042)

	# Mausrad dreht das Platzier-Hologramm direkt (wie in AAA-Bau-Simulatoren!)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mb := event as InputEventMouseButton
		if _ghost_root != null and _ghost_root.visible and not _ghost_is_drop_preview:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_handle_rotate(1)
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_handle_rotate(-1)
				return

	# Kontext-Interaktion: Tasten 1-4 wählen den aktiven Slot, die Aufnahme legt fest, was darin liegt.
	if event.is_action_pressed("tool_hands"):
		_select_slot(1)
	elif event.is_action_pressed("tool_power_cable"):
		_select_slot(2)
	elif event.is_action_pressed("tool_net_cable"):
		_select_slot(3)
	elif event.is_action_pressed("tool_slot_4"):
		_select_slot(4)
	elif event.is_action_pressed("rotate_item"):
		_handle_rotate(1)
	elif event.is_action_pressed("drop_item"):
		_handle_drop()
	elif event.is_action_pressed("inspect_rack"):
		_handle_inspect()
	elif event.is_action_pressed("primary_action"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if _ghost_root != null and _ghost_root.visible and not _ghost_is_drop_preview:
				_try_confirm_placement()
	elif event.is_action_pressed("interact"): # Interaktion über [E]
		if _ui_unlock_cooldown <= 0.0:
			_handle_primary_interact()
	elif event.is_action_pressed("secondary_action"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_handle_secondary_action()
	elif event.is_action_pressed("world_ping"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_handle_world_ping()
	elif event.is_action_pressed("emote_wheel"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_open_emote_wheel()
	elif event.is_action_released("emote_wheel"):
		_close_emote_wheel()
	elif event.is_action_pressed("emote_wave"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			GameState.request_player_emote("wave")
	elif event.is_action_pressed("emote_thumbs"):
		if _ui_unlock_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			GameState.request_player_emote("thumbs")
	elif event.is_action_pressed("teleport_site"):
		if _ui_unlock_cooldown <= 0.0 and not ui_locked:
			teleport_between_sites()


## Kabeltyp in einem Slot ("" | "power" | "network"). Der aktive Slot liest das laufende Kabel.
func get_slot_cable_type(slot: int) -> String:
	if slot < 1 or slot > GameState.SLOT_COUNT:
		return ""
	if slot == active_slot:
		return cable_active_type
	var stored: Dictionary = _slot_cables[slot - 1]
	return str(stored.get("type", ""))


## Wechselt den aktiven Slot. Ein gezogenes Kabel bleibt im Slot, in dem es aufgenommen wurde.
func _select_slot(slot: int) -> void:
	if slot == active_slot or slot < 1 or slot > GameState.SLOT_COUNT:
		return
	_slot_cables[active_slot - 1] = {"start": cable_start_id, "type": cable_active_type, "slot": cable_start_slot}
	var stored: Dictionary = _slot_cables[slot - 1]
	cable_start_id = str(stored.get("start", ""))
	cable_active_type = str(stored.get("type", ""))
	cable_start_slot = int(stored.get("slot", -1))
	active_slot = slot
	GameState.request_set_active_slot(slot)
	SfxManager.play("click", -10.0, 1.0)


## [R]: dreht das Hologramm, die Ware in den Händen oder das angeschaute Ding am Platz.
func _handle_rotate(dir: int) -> void:
	var step := PI * 0.5 * float(dir)
	var held := GameState.get_player_held_crate(peer_id)
	var placing := relocating_rack_id != ""
	if not placing and not held.is_empty():
		placing = str(GameState.ITEM_CATALOG[str(held["item_type"])]["category"]) == "placeable"
	if placing:
		var t := _ghost_model_key.get_slice("|", 0)
		if _follows_wall(t):
			SfxManager.play("error", -14.0)
			return
		if _ghost_root != null and _ghost_root.visible and DecorSpec.WALL_SNAP.has(t):
			# Von der Richtung aus weiterdrehen, die man gerade sieht.
			_rot_manual = true
			place_rot_y = fposmod(_ghost_rot_y + step, TAU)
		else:
			place_rot_y = fposmod(place_rot_y + step, TAU)
		SfxManager.play("click", -10.0, 1.15 if dir > 0 else 0.94)
		return
	if not held.is_empty():
		hold_yaw = fposmod(hold_yaw + step, TAU)
		SfxManager.play("click", -10.0, 1.15 if dir > 0 else 0.94)
		return
	var kind := _rotatable_kind(_get_aimed_interactable())
	if kind != "":
		var target := _get_aimed_interactable()
		act("press", (target as Node3D).global_position)
		GameState.request_rotate(kind, str(target.get_meta("entity_id")), dir)


## Was an der Wand hängt, richtet sich nach der Wand.
func _follows_wall(item_type: String) -> bool:
	if _ghost_root == null or not _ghost_root.visible:
		return false
	return item_type == GameState.INDOOR_UNIT_TYPE or DecorSpec.is_wall_sign(item_type) or (GameState.is_strip_type(item_type) and _ghost_pos.y >= GameState.STRIP_WALL_MIN_Y)


## Kann man das angeschaute Ding mit leeren Händen am Platz drehen? "" = nein.
func _rotatable_kind(target: Object) -> String:
	if target == null or not (target is Node3D) or cable_start_id != "" or GameState.is_player_holding_anything(peer_id):
		return ""
	if not GameState.get_player_pushed_cart(peer_id).is_empty():
		return ""
	var itype := str(target.get_meta("interact_type", ""))
	var eid := str(target.get_meta("entity_id", ""))
	match itype:
		"crate":
			return "crate" if GameState.crates.has(eid) else ""
		"rack_slot", "rack_panel":
			return "rack" if GameState.racks.has(eid) else ""
		"cart":
			return "cart" if GameState.carts.has(eid) else ""
		"ups_unit":
			return "ups" if GameState.ups_units.has(eid) else ""
		"cooler_unit":
			return "cooler" if GameState.coolers.has(eid) and not GameState.is_indoor_unit(eid) else ""
	if GameState.decor_items.has(eid):
		var d: Dictionary = GameState.decor_items[eid]
		if DecorSpec.is_wall_sign(str(d.get("item_type", ""))) or bool(d.get("wall", false)):
			return ""
		return "decor"
	return ""


func _handle_inspect() -> void:
	if relocating_rack_id != "" or cable_start_id != "":
		return
	var target := _get_aimed_interactable()
	if target == null or _world == null:
		return
	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	if itype == "outdoor" and eid == "gate":
		OutdoorManager.request_use(eid, true)
	elif itype == "wall_router":
		_world.open_device_inspector("router", eid)
	elif itype == "workbench":
		GameState.select_bench(eid)
		if GameState.can_workbench_service():
			GameState.request_workbench_service()
		elif GameState.decor_items.has(eid):
			_world.open_device_inspector("decor", eid)
	elif itype == "rack_slot" and GameState.racks.has(eid):
		_world.open_rack_inspector(eid, int(target.get_meta("slot_index", 0)))
	elif itype == "cooler_unit" and GameState.coolers.has(eid):
		_world.open_device_inspector("cooler", eid)
	elif itype == "ups_unit" and GameState.ups_units.has(eid):
		_world.open_device_inspector("ups", eid)
	elif itype == "cart" and GameState.carts.has(eid):
		_world.open_device_inspector("cart", eid)
	elif GameState.decor_items.has(eid):
		_world.open_device_inspector("decor", eid)


## Dauer vom Hinsetzen bis der Monitor das ganze Bild füllt.
func get_pc_focus_duration() -> float:
	return PC_SIT_SETTLE + PC_FOCUS_TIME


func _get_pc_screen() -> MeshInstance3D:
	if _pc_screen == null or not is_instance_valid(_pc_screen):
		_pc_screen = get_tree().get_first_node_in_group("pc_screen") as MeshInstance3D
	return _pc_screen


func _process(delta: float) -> void:
	if not is_local or _camera == null:
		return
	if is_seated_at_pc:
		_pc_sit_time += delta
		_pc_focus = clampf((_pc_sit_time - PC_SIT_SETTLE) / PC_FOCUS_TIME, 0.0, 1.0)
	else:
		_pc_focus = move_toward(_pc_focus, 0.0, delta / PC_UNFOCUS_TIME)

	if _pc_focus <= 0.0001:
		if _pc_cam_moved:
			_pc_cam_moved = false
			_camera.transform = Transform3D.IDENTITY
			_camera.fov = SettingsManager.fov
		return

	var screen := _get_pc_screen()
	if screen == null:
		return
	var eased := _pc_focus * _pc_focus * (3.0 - 2.0 * _pc_focus)
	var screen_pos := screen.global_position
	var normal := screen.global_transform.basis.z.normalized()
	var height := 0.4
	var quad := screen.mesh as QuadMesh
	if quad != null:
		height = quad.size.y * screen.global_transform.basis.y.length()
	var dist := (height * 0.5 * PC_FOCUS_FILL) / tan(deg_to_rad(PC_FOCUS_FOV) * 0.5)
	var target := Transform3D(Basis(), screen_pos + normal * dist).looking_at(screen_pos, Vector3.UP)
	_camera.global_transform = _head_pivot.global_transform.interpolate_with(target, eased)
	_camera.fov = lerpf(SettingsManager.fov, PC_FOCUS_FOV, eased)
	_pc_cam_moved = true


func _physics_process(delta: float) -> void:
	_anim_time += delta
	if _ui_unlock_cooldown > 0.0:
		_ui_unlock_cooldown = maxf(0.0, _ui_unlock_cooldown - delta)
	if relocating_rack_id != "" and not GameState.racks.has(relocating_rack_id) and not GameState.decor_items.has(relocating_rack_id):
		relocating_rack_id = ""
	if _emote_timer > 0.0:
		_emote_timer = maxf(0.0, _emote_timer - delta)
		if _emote_badge != null:
			_emote_badge.position.y = 2.28 + sin(_anim_time * 5.0) * 0.03
		if _emote_timer <= 0.0 and _emote_badge != null:
			_emote_badge.visible = false
	_update_held_visuals()
	if is_local:
		_animate_avatar(delta, velocity if not is_seated_at_pc and _sofa_id == "" else Vector3.ZERO, _pose_flag())
		_update_fp(delta)
	if is_local and position.y < -6.0:
		_rescue_from_fall()

	if not is_local:
		var prev_pos := position
		position = position.lerp(_target_pos, clampf(delta * 14.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 14.0, 0.0, 1.0))
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, _target_pitch, clampf(delta * 14.0, 0.0, 1.0))
		_animate_avatar(delta, (position - prev_pos) / maxf(delta, 0.001), _remote_pose_flag)
		_place_remote_held()
		_update_foam_visuals(_remote_spraying)
		return

	# Smooth First-Person Sit-Down & Stand-Up Animation at the PC Office Chair!
	if is_seated_at_pc:
		if is_crouching:
			_apply_crouch(false)
		var seat_target := Vector3(2.78, 0.0, -2.84)
		position = position.lerp(seat_target, clampf(delta * 9.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, -0.06, clampf(delta * 9.0, 0.0, 1.0))
		_head_pivot.position.y = lerpf(_head_pivot.position.y, 1.22, clampf(delta * 9.0, 0.0, 1.0))
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, -0.04, clampf(delta * 9.0, 0.0, 1.0))
		velocity = Vector3.ZERO
	elif _sofa_id != "":
		_process_sofa(delta)
	elif seat_kind != "":
		_process_bench(delta)
	elif on_ladder:
		pass
	elif _stand_blend_timer > 0.0:
		_stand_blend_timer = maxf(0.0, _stand_blend_timer - delta)
		position = position.lerp(_pre_seat_pos, clampf(delta * 10.0, 0.0, 1.0))
		_head_pivot.position.y = lerpf(_head_pivot.position.y, 1.56, clampf(delta * 10.0, 0.0, 1.0))
		velocity = Vector3.ZERO
	else:
		# Gravity & Local WASD Movement
		_update_crouch()
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif not ui_locked and not is_crouching and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY

		if ui_locked:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		else:
			var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
			var pushing_cart := not GameState.get_player_pushed_cart(peer_id).is_empty()
			var base_spd := 4.3 if pushing_cart else MOVE_SPEED
			var sprint_spd := 6.3 if pushing_cart else SPRINT_SPEED
			var speed := base_spd
			if is_crouching:
				speed = CROUCH_SPEED
			elif Input.is_action_pressed("sprint"):
				speed = sprint_spd
			speed *= DecorManager.walk_mult(peer_id)
			if move_dir.length_squared() > 0.001:
				velocity.x = move_dir.x * speed
				velocity.z = move_dir.z * speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)

		move_and_slide()

	if on_ladder:
		_process_ladder(delta)
	if is_at_workbench:
		var to_bench := _workbench_pos - position
		rotation.y = lerp_angle(rotation.y, atan2(-to_bench.x, -to_bench.z), clampf(delta * 8.0, 0.0, 1.0))
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, -0.55, clampf(delta * 6.0, 0.0, 1.0))

	# Smoothly push active cart right in front of the player
	var pushed_cart := GameState.get_player_pushed_cart(peer_id)
	if not pushed_cart.is_empty() and _world != null:
		var cpos := _compute_pushed_cart_pos()
		_world.update_local_pushed_cart(str(pushed_cart["id"]), cpos, rotation.y)

	# Subtle first-person walk bob + realistic concrete/floor footsteps + heavy placement weight dip
	_cam_weight_dip = lerpf(_cam_weight_dip, 0.0, clampf(delta * 9.5, 0.0, 1.0))
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if not is_seated_at_pc and _sofa_id == "" and _stand_blend_timer <= 0.0:
		if is_on_floor() and flat_speed > 0.6 and not ui_locked:
			_walk_cycle += delta * (7.5 + flat_speed * 0.7)
			_head_pivot.position.y = lerpf(_head_pivot.position.y, _head_y() + sin(_walk_cycle) * 0.030 - _cam_weight_dip, clampf(delta * 12.0, 0.0, 1.0))
			var step_interval := 0.34 if flat_speed > 5.8 else 0.48
			_footstep_accum += delta
			if _footstep_accum >= step_interval:
				_footstep_accum = 0.0
				var surf := "concrete"
				var is_wet := (GameState.weather_state == "rain" or GameState.weather_state == "storm")
				if position.z < -80.0:
					var lz := position.z - GameState.HALLE_NORD_ORIGIN.z
					if absf(position.x) < 10.0 and absf(lz) < 6.0:
						surf = "raised_floor"
					elif is_wet:
						surf = "wet"
				elif position.z > 4.65 and is_wet:
					surf = "wet"
				if surf == "concrete" and OutdoorWorld.surface(position) == "grass":
					surf = "snow" if OutdoorManager.snow_shown > 0.4 else "grass"
				SfxManager.play_footstep(flat_speed > 5.8, surf)
		else:
			_footstep_accum = 0.25
			_head_pivot.position.y = lerpf(_head_pivot.position.y, _head_y() - _cam_weight_dip, clampf(delta * 10.0, 0.0, 1.0))

	if not ui_locked:
		_update_viewmodel_motion(delta, flat_speed)
		_update_placement_preview(delta)
		_update_cable_preview()
		_update_continuous_actions(delta)
		_update_context_prompt()
	else:
		_clear_shelf_hover()
		if _ghost_root != null:
			_ghost_root.visible = false
		if _world != null and _world.has_method("update_cable_preview"):
			_world.update_cable_preview(false, "power", Vector3.ZERO, Vector3.ZERO)

	_update_foam_visuals(_is_spraying_local)

	_net_send_accum += delta
	if _net_send_accum >= 0.05:
		_net_send_accum = 0.0
		if _world != null and _world.has_method("send_local_pose"):
			_world.send_local_pose(position, rotation.y, _head_pivot.rotation.x, _pose_flag(), _is_spraying_local)
			if not pushed_cart.is_empty():
				_world.send_cart_pose(str(pushed_cart["id"]), _compute_pushed_cart_pos(), rotation.y)


## Ducken, solange die Taste gehalten wird. Aufstehen nur, wenn über dem Kopf Platz ist.
func _update_crouch() -> void:
	var want := not ui_locked and Input.is_action_pressed("crouch")
	if want and not is_crouching:
		_apply_crouch(true)
	elif not want and is_crouching and _can_stand_up():
		_apply_crouch(false)


## Passt die Kapsel an. Die Füße bleiben am Boden, weil der Ursprung des Körpers unten liegt.
func _apply_crouch(crouch: bool) -> void:
	is_crouching = crouch
	var h := CROUCH_HEIGHT if crouch else STAND_HEIGHT
	_body_shape.height = h
	_body_col.position.y = h * 0.5


## Prüft mit einer stehenden Kapsel, ob Decke, Rack oder Regal das Aufstehen verhindern.
func _can_stand_up() -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _stand_probe
	params.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, STAND_HEIGHT * 0.5 + 0.03, 0.0))
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _head_y() -> float:
	return CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y


func _compute_pushed_cart_pos() -> Vector3:
	var forward := -global_transform.basis.z
	var raw := global_position + forward * 1.32
	var max_x := 4.8 if GameState.room_level == 0 else (11.7 if GameState.room_level == 1 else 20.7)
	var cx := clampf(raw.x, -4.8, max_x)
	var cz := clampf(raw.z, -3.8, 9.2)
	# Keep cart inside doorway X bounds if rolling across threshold onto driveway
	if cz > 3.85:
		cx = clampf(cx, -1.75, 1.75) if cz < 5.0 else clampf(cx, -3.2, 3.2)
	return Vector3(cx, 0.0, cz)


func human_model() -> HumanModel:
	return _human


func _pose_flag() -> int:
	if is_seated_at_pc:
		return 2 if is_typing_at_pc else 1
	if _sofa_id != "" or seat_kind != "":
		return 4
	if is_at_workbench:
		return 5
	if on_ladder:
		return 6
	if is_crouching:
		return 3
	return 0 if is_on_floor() else 7


## Haltung der ganzen Figur. Für Mitspieler aus der übertragenen Haltung, für sich selbst (Schatten, Spiegel) aus dem eigenen Zustand.
func _animate_avatar(_delta: float, vel: Vector3, flag: int) -> void:
	if _human == null or _human.rig == null:
		return
	var r := _human.rig
	var flat := Vector3(vel.x, 0.0, vel.z)
	if flat.length() > 12.0:
		flat = Vector3.ZERO
	var seated := flag == 1 or flag == 2 or flag == 4
	_human.move(Vector3.ZERO if seated or flag == 5 else flat)
	r.crouch = 1.0 if flag == 3 else 0.0
	r.airborne = flag == 7
	r.seat = 1.0 if seated else 0.0
	r.seat_height = 0.46 if flag == 4 else 0.52
	r.look_pitch = clampf(_head_pivot.rotation.x, -0.9, 0.9)
	r.tempo = clampf(absf(vel.y) / 1.2, 0.0, 1.6)
	_talk_left = maxf(0.0, _talk_left - _delta)
	r.talk = 1.0 if _talk_left > 0.0 else 0.0
	var held := GameState.get_player_held_crate(peer_id)
	var ext := GameState.is_player_holding_extinguisher(peer_id)
	var cart := GameState.get_player_pushed_cart(peer_id)
	var b := ""
	var key := ""
	if flag == 2:
		b = "type"
	elif flag == 1:
		b = "type"
	elif flag == 4:
		b = "sofa"
	elif flag == 5:
		b = "work"
	elif flag == 6:
		b = "ladder"
	elif ext:
		b = "extinguisher"
		key = "ext"
	elif not held.is_empty():
		key = str(held.get("id", held.get("item_type", "")))
		var two := _is_two_handed_item(str(held["item_type"]), maxi(1, int(held.get("pack_count", 1))))
		b = ("carry_wide" if maxi(1, int(held.get("pack_count", 1))) > 1 else "carry_box") if two else "one"
	elif not cart.is_empty():
		b = "push"
		key = "cart"
	r.base = b
	if key != _remote_held:
		# Aufheben und Ablegen sichtbar machen.
		var drop := key == ""
		_remote_held = key
		if not seated and flag != 5 and key != "cart":
			r.play("place" if drop else "pickup", Vector3(0.0, 0.35 if _remote_low(drop) else 0.95, 0.42))


func _remote_low(_drop: bool) -> bool:
	return _head_pivot.rotation.x < -0.35


## Gehaltenes liegt in den Händen der Figur.
func _place_remote_held() -> void:
	if _human == null or _human.rig == null or _held_root == null:
		return
	var l := to_local(_human.rig.hand_transform(true).origin)
	var rr := to_local(_human.rig.hand_transform(false).origin)
	var held := GameState.get_player_held_crate(peer_id)
	if GameState.is_player_holding_extinguisher(peer_id):
		_held_root.position = rr + Vector3(-0.01, -0.27, -0.06)
	elif not held.is_empty() and not _is_two_handed_item(str(held["item_type"]), maxi(1, int(held.get("pack_count", 1)))):
		_held_root.position = rr + Vector3(0.0, 0.05, -0.10)
	else:
		_held_root.position = (l + rr) * 0.5 + Vector3(0.0, 0.0, -0.10)


## Handlung zeigen: eigene Arme, eigene Figur und bei den Mitspielern.
func act(action: String, world_at: Variant = null) -> void:
	if not is_local:
		return
	if _fp != null:
		_fp.play(action, world_at)
	var at := Vector3(0.0, 0.95, 0.45)
	if world_at is Vector3:
		var l := to_local(world_at)
		at = Vector3(clampf(-l.x, -0.5, 0.5), clampf(l.y, 0.15, 1.75), clampf(-l.z, 0.25, 0.55))
	play_remote_action(action, at)
	if _world != null and _world.has_method("send_local_action"):
		_world.send_local_action(action, at)


func play_remote_action(action: String, at: Vector3) -> void:
	if _human != null and _human.rig != null and at.is_finite():
		_human.rig.play(action, at.clamp(Vector3(-1, 0, 0), Vector3(1, 2, 1)))


## Passende Bewegung zum anvisierten Ding.
func _act_on_target(primary: bool) -> void:
	var at := _aim_point()
	if cable_start_id != "":
		act("plug", at)
		return
	var target := _get_aimed_interactable()
	if target == null:
		return
	var holding := not GameState.get_player_held_crate(peer_id).is_empty()
	match str(target.get_meta("interact_type")):
		"crate", "extinguisher_item", "extinguisher_station":
			act("pickup", at)
		"decor_shelf_slot", "workbench", "cart":
			act("place" if holding else "pickup", at)
		"terminal", "cooler_unit", "ups_unit", "wall_breaker", "strip_switch", "garage_door", "shuttle_teleport", "delivery_sign":
			act("press", at)
		"power_port", "net_port", "cluster_port", "wall_router":
			act("plug", at)
		"rack_slot":
			act("place" if holding and primary else "reach", at)
		"fuse_slot":
			act("plug", at)
		"outdoor":
			var oid := str(target.get_meta("entity_id"))
			if oid.begins_with("bed:") or oid == "feeder":
				act("feed", at)
			elif oid == "solar":
				act("sweep", at)
			elif oid == "dish":
				act("screw", at)
			else:
				act("press" if oid in ["gate", "lamps"] else "reach", at)
		"bench", "ladder":
			pass
		"decor_use":
			if str((GameState.decor_items.get(str(target.get_meta("entity_id")), {}) as Dictionary).get("item_type", "")) == "prop_water":
				act("drink")
			elif str((GameState.decor_items.get(str(target.get_meta("entity_id")), {}) as Dictionary).get("item_type", "")) != "prop_sofa":
				act("reach", at)
		_:
			act("reach", at)


func _aim_point() -> Vector3:
	if _ray != null and _ray.is_colliding():
		return _ray.get_collision_point()
	return _camera.global_position - _camera.global_basis.z * 0.6


func _open_emote_wheel() -> void:
	if _emote_wheel == null:
		var layer := CanvasLayer.new()
		layer.layer = 40
		add_child(layer)
		_emote_wheel = EmoteWheel.new()
		layer.add_child(_emote_wheel)
	_emote_wheel.open()


func _close_emote_wheel() -> void:
	if _emote_wheel == null or not _emote_wheel.visible:
		return
	var id := _emote_wheel.close()
	if id != "" and not ui_locked:
		GameState.request_player_emote(id)


## Eigene Arme: was liegt in der Hand, wo sind die Griffe.
func _update_fp(delta: float) -> void:
	if _fp == null:
		return
	var held_ext := GameState.is_player_holding_extinguisher(peer_id)
	var held := GameState.get_player_held_crate(peer_id)
	var cart := GameState.get_player_pushed_cart(peer_id)
	var mode := ""
	if is_seated_at_pc or is_at_workbench or _sofa_id != "" or on_ladder:
		mode = ""
	elif held_ext:
		mode = "ext"
	elif not held.is_empty():
		var two := _is_two_handed_item(str(held["item_type"]), maxi(1, int(held.get("pack_count", 1))))
		mode = "box" if two else "item"
		if two:
			_fp.half_w = _held_half_w
	elif not cart.is_empty():
		mode = "push"
		var cp := _compute_pushed_cart_pos()
		var cb := Basis(Vector3.UP, rotation.y)
		_fp.push_l = cp + cb * Vector3(-0.26, 0.98, 0.62)
		_fp.push_r = cp + cb * Vector3(0.26, 0.98, 0.62)
	elif cable_active_type != "":
		mode = "cable"
	_fp.grip_mode = mode
	_fp.item_xf = _held_root.transform
	_fp.bob = Vector3(_vm_sway.x, _vm_sway.y - _vm_land_dip + absf(sin(_walk_cycle * 0.5)) * -0.010, 0.0)
	_fp.set_plug(mode == "cable", Color(0.10, 0.35, 0.80) if cable_active_type == "network" else (Color(0.55, 0.20, 0.70) if cable_active_type == "cluster" else Color(0.09, 0.09, 0.10)))
	_fp.update(delta)


func _get_aimed_interactable() -> Object:
	if _ray == null:
		return null
	var skipped: Array[CollisionObject3D] = []
	var result: Object = null
	var door_hit: Object = null
	for _i in range(4):
		_ray.force_raycast_update()
		if not _ray.is_colliding():
			break
		var hit := _ray.get_collider()
		if hit == null or not hit.has_meta("interact_type"):
			break
		var hit_type := str(hit.get_meta("interact_type"))
		# Sicherungen und Hauptschalter liegen hinter der Kastentür: bei geschlossener Tür hindurchschauen,
		# damit der Blick die Tür trifft und man nicht genau zielen muss.
		var behind_breaker_door := hit_type == "fuse_slot" or hit_type == "wall_breaker"
		if behind_breaker_door and not GameState.is_breaker_door_open():
			if not (hit is CollisionObject3D):
				break
			skipped.append(hit as CollisionObject3D)
			_ray.add_exception(hit as CollisionObject3D)
			continue
		# Die Steckdose unten am Kasten bleibt auch durch den Klickbereich der Tür hindurch erreichbar.
		if door_hit == null and hit_type == "rack_panel" and str(hit.get_meta("panel_id", "")) == "breaker:door" and hit is CollisionObject3D:
			door_hit = hit
			skipped.append(hit as CollisionObject3D)
			_ray.add_exception(hit as CollisionObject3D)
			continue
		if door_hit != null and hit_type != "power_port":
			break
		result = hit
		break
	for obj in skipped:
		_ray.remove_exception(obj)
	if result == null:
		result = door_hit
	return result


func _handle_drop() -> void:
	if relocating_rack_id != "":
		relocating_rack_id = ""
		SfxManager.play("click", -10.0, 0.8)
		return
	if cable_start_id != "":
		cable_start_id = ""
		cable_active_type = ""
		SfxManager.play("cable_cut", -10.0, 0.9)
		return
	if GameState.is_player_holding_extinguisher(peer_id):
		GameState.request_drop_extinguisher(_safe_drop_pos(), rotation.y)
		return
	var pushed_cart := GameState.get_player_pushed_cart(peer_id)
	if not pushed_cart.is_empty():
		GameState.request_release_cart(_compute_pushed_cart_pos(), rotation.y)
		return
	var held := GameState.get_player_held_crate(peer_id)
	if not held.is_empty() and position.y > 2.5 and position.z > -60.0:
		SfxManager.play("error")
		return
	if not held.is_empty():
		var drop_pos: Vector3
		if _ghost_root != null and _ghost_root.visible and _ghost_is_drop_preview:
			drop_pos = _ghost_pos
		else:
			drop_pos = _safe_drop_pos()
		_cam_weight_dip = maxf(_cam_weight_dip, 0.042)
		act("place", drop_pos + Vector3(0.0, 0.3, 0.0))
		GameState.request_drop_crate(drop_pos, rotation.y + hold_yaw)


## Sicherer Vorwärts-Check gegen feste Hindernisse (Racks/Wände), damit das Item NIE in einem Rack verschwindet!
func _safe_drop_pos() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var dist := 1.05
	var space := get_world_3d().direct_space_state
	if space != null:
		var probe_from := global_position + Vector3(0.0, 0.75, 0.0)
		var probe_to := probe_from + forward * 1.45
		var q := PhysicsRayQueryParameters3D.create(probe_from, probe_to, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var hd := probe_from.distance_to(hit["position"] as Vector3)
			dist = clampf(hd - 0.50, 0.36, 1.05)
	var out := global_position + forward * dist
	out.y = 0.0
	return out


func _try_confirm_placement() -> void:
	if relocating_rack_id != "":
		if _ghost_root != null and _ghost_root.visible and _ghost_valid:
			_cam_weight_dip = maxf(_cam_weight_dip, 0.068)
			if GameState.decor_items.has(relocating_rack_id):
				GameState.request_relocate_decor(relocating_rack_id, _ghost_pos, _ghost_rot_y)
			else:
				GameState.request_relocate_rack(relocating_rack_id, _ghost_pos, _ghost_rot_y)
			relocating_rack_id = ""
		else:
			SfxManager.play("error")
		return
	var held := GameState.get_player_held_crate(peer_id)
	if not held.is_empty():
		var item_type := str(held["item_type"])
		var cat_type := str(GameState.ITEM_CATALOG[item_type]["category"])
		if cat_type == "placeable" and _ghost_root != null and _ghost_root.visible and not _ghost_is_drop_preview:
			if _ghost_valid:
				_cam_weight_dip = maxf(_cam_weight_dip, 0.065)
				GameState.request_place_held_structure(_ghost_pos, _ghost_rot_y)
			else:
				SfxManager.play("error")


func _handle_world_ping() -> void:
	if _camera == null:
		return
	var origin := _camera.global_position
	var fwd := -_camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 18.0, 1 | 4)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	var col_obj: Object = hit.get("collider")
	var kind := "look"
	var label := tr("Schau her!")
	if col_obj is Node and (col_obj as Node).has_meta("interact_type"):
		var itype := str((col_obj as Node).get_meta("interact_type"))
		var eid := str((col_obj as Node).get_meta("entity_id", ""))
		if itype == "rack_slot" or itype == "rack_power" or itype == "rack_net":
			if GameState.racks.has(eid):
				var rk: Dictionary = GameState.racks[eid]
				if GameState._rack_has_fire(rk):
					kind = "alert"
					label = tr("Brand löschen!")
				elif not bool(rk.get("powered", false)):
					kind = "cable"
					label = tr("Hier fehlt Strom!")
				elif not bool(rk.get("networked", false)):
					kind = "cable"
					label = tr("Hier fehlt LAN!")
				else:
					label = GameState.get_rack_display_name(eid)
		elif itype == "crate":
			label = tr("Paket abholen")
		elif itype == "breaker":
			kind = "alert"
			label = tr("Sicherung prüfen!")
	GameState.request_world_ping(pos, kind, label)


## Wer im Chat schreibt, bewegt den Mund.
func _on_chat(sender_name: String, _col: Color, message: String, _ts: String) -> void:
	if sender_name == player_name:
		_talk_left = clampf(message.length() * 0.09, 0.8, 5.0)


func _on_player_emote_received(sender_peer: int, emote_id: String) -> void:
	if sender_peer != peer_id:
		return
	_emote_id = emote_id
	_emote_timer = 2.6
	if _emote_badge != null:
		_emote_badge.text = tr(str(EmoteWheel.SAYS.get(emote_id, "")))
		_emote_badge.visible = not is_local
	if _human != null and _human.rig != null:
		_human.rig.play(emote_id)
	if is_local and _fp != null:
		_fp.play(emote_id)


func _handle_primary_interact() -> void:
	if relocating_rack_id != "":
		_try_confirm_placement()
		return
	_vm_from = _aim_point()
	_act_on_target(true)

	# If player is currently holding a pulled cable in hand -> connect it to aimed compatible target!
	if cable_start_id != "" and cable_active_type != "":
		var endpoint := _resolve_aimed_cable_endpoint(cable_active_type)
		if endpoint == "":
			return
		if cable_start_id == endpoint:
			cable_start_id = ""
			cable_active_type = ""
			SfxManager.play("cable_cut", -10.0, 0.9)
		elif _cable_target_state(endpoint) == CableRenderer.TARGET_INVALID:
			# Ziel voll oder schon verbunden: Kabel bleibt in der Hand
			SfxManager.play("error")
		else:
			GameState.request_connect_cable(cable_active_type, cable_start_id, endpoint,
				cable_start_slot, _aimed_socket_idx(cable_active_type, endpoint))
			cable_start_id = ""
			cable_active_type = ""
		return

	# Wenn man direkt ein Lagerfach, eine Werkbank oder einen Rollwagen anvisiert, hat Einlagern Vorrang vor Boden-Platzierung!
	var target := _get_aimed_interactable()
	var target_type := str(target.get_meta("interact_type")) if target != null else ""
	var prioritize_target := (target_type == "decor_shelf_slot" or target_type == "workbench" or target_type == "cart" or target_type == "decor_use")

	var held := GameState.get_player_held_crate(peer_id)
	if not prioritize_target and not held.is_empty():
		var item_type := str(held["item_type"])
		var cat_type := str(GameState.ITEM_CATALOG[item_type]["category"])
		if cat_type == "placeable" and _ghost_root != null and _ghost_root.visible and not _ghost_is_drop_preview:
			_try_confirm_placement()
			return

	if target == null:
		_try_assisted_cable_start()
		return

	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	var hands_empty := not GameState.is_player_holding_anything(peer_id)

	match itype:
		"terminal":
			if PcScreenState.is_occupied_by_other():
				SfxManager.play("error")
			elif _world != null and _world.has_method("open_terminal"):
				_world.open_terminal()
		"garage_door":
			var garage := _world.get_node_or_null("Garage") if _world != null else null
			if garage != null and garage.has_method("toggle_garage_door"):
				garage.call("toggle_garage_door")
		"shuttle_teleport":
			teleport_between_sites()
		"outdoor":
			OutdoorManager.request_use(eid)
		"bench":
			sit_on_bench(target as Node3D)
		"ladder":
			start_ladder(eid == "ladder_top")
		"locker":
			if _world != null and _world.has_method("open_locker"):
				_world.open_locker()
		"decor_shelf_slot":
			GameState.request_decor_shelf_interact(str(target.get_meta("decor_id", "")), int(target.get_meta("slot_idx", 0)))
		"strip_switch":
			GameState.request_toggle_strip(eid)
		"paper_bin":
			GameState.request_dump_carton(eid)
		"parts_cabinet":
			GameState.request_refill_maint_kits()
		"wall_breaker":
			if GameState.is_breaker_door_open():
				GameState.request_toggle_breaker()
			else:
				SfxManager.play("error")
		"fuse_slot":
			if GameState.is_breaker_door_open():
				GameState.request_insert_fuse(int(target.get_meta("slot_idx", -1)))
			else:
				SfxManager.play("error")
		"wall_router":
			if GameState.ddos_active:
				GameState.request_mitigate_ddos()
			elif hands_empty:
				# Contextual 1-Hand: Looking at Router grabs a blue Network Cable!
				cable_active_type = "network"
				cable_start_id = eid
				cable_start_slot = _aimed_socket_idx("network", eid)
				SfxManager.play("cable", -8.0, 1.15)
		"power_port":
			# Die Einspeisung unten am Stromkasten oder an einer Stromleiste: exakten anvisierten Port nehmen!
			if hands_empty:
				var p_slot := _get_target_slot_idx(target, "power", eid)
				if p_slot >= 0 and not GameState.get_cable_on_slot("power", eid, p_slot).is_empty():
					# Port ist belegt -> direkt aus diesem Port abziehen!
					_unplug_into_hand("power", eid, p_slot)
				else:
					cable_active_type = "power"
					cable_start_id = eid
					cable_start_slot = p_slot if p_slot >= 0 else _aimed_socket_idx("power", eid)
					SfxManager.play("cable", -8.0, 1.05)
		"net_port":
			if hands_empty:
				var n_slot := _get_target_slot_idx(target, "network", eid)
				if n_slot >= 0 and not GameState.get_cable_on_slot("network", eid, n_slot).is_empty():
					# Port ist belegt -> direkt aus diesem Port abziehen!
					_unplug_into_hand("network", eid, n_slot)
				else:
					cable_active_type = "network"
					cable_start_id = eid
					cable_start_slot = n_slot if n_slot >= 0 else _aimed_socket_idx("network", eid)
					SfxManager.play("cable", -8.0, 1.15)
		"cluster_port":
			if hands_empty:
				cable_active_type = "cluster"
				cable_start_id = eid
				cable_start_slot = -1
				SfxManager.play("cable", -8.0, 1.25)
		"extinguisher_station":
			var st_id := str(target.get_meta("station", "garage"))
			if GameState.is_player_holding_extinguisher(peer_id):
				GameState.request_hang_extinguisher(st_id)
			elif hands_empty:
				var st_ext := GameState.get_extinguisher_at_station(st_id)
				if st_ext != "":
					GameState.request_pickup_extinguisher(st_ext)
				else:
					SfxManager.play("error")
		"extinguisher_item":
			if hands_empty:
				GameState.request_pickup_extinguisher(eid)
		"rack_panel":
			var rp_node: Variant = target.get_meta("rack_prop", null)
			if is_instance_valid(rp_node) and (rp_node as Object).has_method("toggle_panel"):
				(rp_node as Object).call("toggle_panel", str(target.get_meta("panel_id", "")))
		"crate":
			var pushed_c := GameState.get_player_pushed_cart(peer_id)
			if not pushed_c.is_empty():
				GameState.request_load_ground_crate_to_pushed_cart(eid)
			elif hands_empty:
				GameState.request_pickup_crate(eid)
		"cart":
			if not held.is_empty():
				GameState.request_load_held_crate_to_cart(eid)
			elif hands_empty:
				GameState.request_grab_cart(eid)
		"cooler_unit":
			if hands_empty and OutdoorManager.clog(eid) >= 0.25:
				OutdoorManager.request_use("unit:" + eid)
				act("sweep", _aim_point())
			elif hands_empty and _world != null and _world.has_method("open_device_inspector"):
				_world.open_device_inspector("cooler", eid)
		"ups_unit":
			if hands_empty and _world != null and _world.has_method("open_device_inspector"):
				_world.open_device_inspector("ups", eid)
		"decor_use":
			if str((GameState.decor_items.get(eid, {}) as Dictionary).get("item_type", "")) == "prop_sofa":
				if not hands_empty:
					SfxManager.play("error")
				else:
					sit_on_sofa(eid)
			else:
				DecorManager.request_use(eid)
		"delivery_sign":
			GameState.request_sign_delivery()
		"workbench":
			GameState.select_bench(eid)
			var wb := GameState.workbench_state
			var wb_mode := str(wb.get("mode", ""))
			if wb.is_empty():
				if not held.is_empty():
					GameState.request_workbench_place()
			elif wb_mode == "build_box":
				GameState.request_workbench_unpack()
			elif GameState.is_workbench_job():
				if _world != null and _world.has_method("open_workbench"):
					_world.open_workbench()
			elif wb_mode == "ready_tray":
				if hands_empty:
					GameState.request_workbench_pickup()
		"rack_slot":
			var slot_idx := int(target.get_meta("slot_index"))
			var is_ext := GameState.is_slot_extended(eid, slot_idx)
			if not held.is_empty():
				var held_type := str(held["item_type"])
				if held_type == "server_tray":
					if GameState.racks.has(eid):
						var slot_occ: Dictionary = GameState.racks[eid]["slots"][slot_idx]
						if str(slot_occ.get("item_type", "")) != "":
							SfxManager.play("error")
						elif not is_ext:
							GameState.request_toggle_slot_extended(eid, slot_idx)
						else:
							GameState.request_insert_server_tray(eid, slot_idx)
				elif str(GameState.ITEM_CATALOG[held_type]["category"]) == "module":
					GameState.request_install_module(eid, slot_idx)
				elif _world != null and _world.has_method("open_rack_inspector"):
					# Auch mit z. B. Reparatur-Kit in der Hand lässt sich das Rack-Menü sicher öffnen (Item bleibt erhalten!)
					_world.open_rack_inspector(eid, slot_idx)
			elif hands_empty:
				if GameState.racks.has(eid):
					var slot: Dictionary = GameState.racks[eid]["slots"][slot_idx]
					var st := str(slot["state"])
					var st_item := str(slot["item_type"])
					if st == "burning":
						pass
					elif is_ext and st_item != "":
						GameState.request_pull_server_tray(eid, slot_idx)
					elif _world != null and _world.has_method("open_rack_inspector"):
						_world.open_rack_inspector(eid, slot_idx)


func _handle_secondary_action() -> void:
	if relocating_rack_id != "":
		relocating_rack_id = ""
		SfxManager.play("click", -10.0, 0.8)
		return

	if cable_start_id != "":
		cable_start_id = ""
		cable_active_type = ""
		SfxManager.play("cable_cut", -10.0, 0.9)
		return

	_vm_from = _aim_point()
	_act_on_target(false)
	# ZUERST anvisiertes Ziel prüfen: Rechtsklick auf einen Rack-Schacht fährt ihn IMMER aus/ein —
	# auch wenn man einen Server-Schlitten oder ein Kit in der Hand hält (wirft das Item NIE ins Rack!).
	var target := _get_aimed_interactable()
	if target != null:
		var itype := str(target.get_meta("interact_type"))
		var eid := str(target.get_meta("entity_id"))
		if itype == "rack_slot":
			var slot_idx := int(target.get_meta("slot_index"))
			GameState.request_toggle_slot_extended(eid, slot_idx)
			return
		elif itype == "rack_panel":
			var rp_node: Variant = target.get_meta("rack_prop", null)
			if is_instance_valid(rp_node) and (rp_node as Object).has_method("toggle_panel"):
				(rp_node as Object).call("toggle_panel", str(target.get_meta("panel_id", "")))
			return
		elif itype == "decor_shelf_slot":
			return # Im Lagerregal nicht versehentlich per Rechtsklick auf den Boden werfen!
		elif itype == "workbench":
			GameState.select_bench(eid)
			if not GameState.is_player_holding_anything(peer_id) and not GameState.workbench_state.is_empty():
				GameState.request_workbench_pickup()
			return
		elif itype == "cart":
			if not GameState.is_player_holding_anything(peer_id):
				GameState.request_unload_cart_to_hands(eid)
			return
		elif itype == "power_port":
			if not GameState.is_player_holding_anything(peer_id):
				_unplug_into_hand("power", eid, _get_target_slot_idx(target, "power", eid))
			return
		elif itype == "net_port" or itype == "wall_router":
			if not GameState.is_player_holding_anything(peer_id):
				_unplug_into_hand("network", eid, _get_target_slot_idx(target, "network", eid))
			return
		elif itype == "cluster_port":
			if not GameState.is_player_holding_anything(peer_id):
				_unplug_into_hand("cluster", eid, -1)
			return

	# Im freien Raum legt Rechtsklick wie gewohnt ab (alternativ [Q]).
	if GameState.is_player_holding_anything(peer_id):
		_handle_drop()


var _ext_require_release: bool = false
var _was_holding_ext: bool = false


func _update_continuous_actions(delta: float) -> void:
	_is_spraying_local = false
	var target := _get_aimed_interactable()
	var ext_id := GameState.get_held_extinguisher(peer_id)
	var holding_ext := ext_id != ""
	# Gesprüht wird nur mit der linken Maustaste, [E] bleibt für den Wandhalter frei.
	var pressing_spray := Input.is_action_pressed("primary_action")

	# Beim Aufnehmen (oder Slot-Wechsel auf den Feuerlöscher) erst warten, bis die Maustaste losgelassen wurde,
	# damit der Feuerlöscher niemals sofort beim Aufheben lossprüht!
	if holding_ext and not _was_holding_ext:
		_ext_require_release = true
	_was_holding_ext = holding_ext

	if _ext_require_release:
		if not pressing_spray:
			_ext_require_release = false
		_action_tick_accum = 0.0
		return

	if holding_ext and pressing_spray and GameState.get_extinguisher_fill(ext_id) <= 0.0:
		if Input.is_action_just_pressed("primary_action"):
			SfxManager.play("error", -10.0, 0.7)
		_action_tick_accum = 0.0
		return
	if holding_ext and pressing_spray:
		_is_spraying_local = true
		SfxManager.keep_extinguisher_spraying()
		_action_tick_accum += delta
		if _action_tick_accum >= 0.16:
			_action_tick_accum = 0.0
			if target != null and str(target.get_meta("interact_type")) == "rack_slot":
				GameState.request_spray_extinguisher(str(target.get_meta("entity_id")), int(target.get_meta("slot_index")))
			else:
				GameState.request_spray_extinguisher("", -1)
		return

	# Ausgefallene Server werden nur noch in der 3D-Vorschau des Rack-Menüs repariert.
	_action_tick_accum = 0.0


## Buchse, an der das gezogene Kabel beginnt (-1 = Anschluss hat nur einen Steckpunkt).
var cable_start_slot: int = -1


## Liefert den explizit anvisierten Port-Index (slot_idx) einer Einzelport-Hitbox, sonst -1.
func _get_target_slot_idx(target: Area3D, cable_type: String, eid: String) -> int:
	if target != null and target.has_meta("slot_idx"):
		var s := int(target.get_meta("slot_idx", -1))
		if s >= 0 and s < GameState.get_max_ports(cable_type, eid):
			return s
	return -1


## Freie Buchse am Anschluss, die dem Fadenkreuz am nächsten liegt. -1 = nur ein Steckpunkt oder alles belegt.
func _aimed_socket_idx(cable_type: String, eid: String) -> int:
	if eid == "" or _world == null or _camera == null or not _world.has_method("get_socket_positions"):
		return -1
	var target := _get_aimed_interactable()
	if target != null and str(target.get_meta("entity_id", "")) == eid and target.has_meta("slot_idx"):
		var aimed_s := int(target.get_meta("slot_idx", -1))
		if aimed_s >= 0 and aimed_s < GameState.get_max_ports(cable_type, eid):
			if GameState.get_cable_on_slot(cable_type, eid, aimed_s).is_empty():
				return aimed_s
	var socks: Array = _world.get_socket_positions(cable_type, eid)
	if socks.is_empty():
		return -1
	var max_n := mini(socks.size(), GameState.get_max_ports(cable_type, eid))
	var used: Array = GameState.get_cable_slot_map(cable_type, eid).values()
	var origin := _camera.global_position
	var fwd := -_camera.global_transform.basis.z
	var best := -1
	var best_off := INF
	for i in range(max_n):
		if used.has(i):
			continue
		var to_p: Vector3 = (socks[i] as Vector3) - origin
		var off := (to_p - fwd * to_p.dot(fwd)).length()
		if off < best_off:
			best_off = off
			best = i
	return best


func _resolve_aimed_cable_endpoint(cable_type: String) -> String:
	var target := _get_aimed_interactable()
	if target == null:
		return _find_assisted_port(cable_type)
	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	if cable_type == "power":
		if itype == "wall_breaker" and eid == GameState.WALL_BREAKER_ID and not GameState.is_breaker_door_open():
			return ""
		if itype == "wall_breaker":
			return eid
		if itype == "power_port" or itype == "rack_slot" or itype == "cooler_unit" or itype == "ups_unit":
			if eid == GameState.WALL_BREAKER_ID or eid == GameState.HALL_C_BREAKER_ID or eid == GameState.HALL_NORD_BREAKER_ID or GameState.racks.has(eid) or (GameState.coolers.has(eid) and not GameState.is_indoor_unit(eid)) or GameState.ups_units.has(eid) or GameState.is_power_strip_decor(eid):
				return eid
	elif cable_type == "cluster":
		if (itype == "cluster_port" or itype == "rack_slot") and GameState.racks.has(eid):
			return eid
	else:
		if itype == "wall_router":
			return eid
		if itype == "net_port" or itype == "rack_slot":
			if eid == GameState.WALL_ROUTER_ID or eid == GameState.HALL_C_ROUTER_ID or eid == GameState.HALL_NORD_ROUTER_ID or GameState.racks.has(eid) or GameState.is_lan_strip_decor(eid):
				return eid
	return _find_assisted_port(cable_type)


## Zielhilfe: wählt den sichtbaren Port, der dem Fadenkreuz am nächsten liegt.
## Gilt nur für Racks, Klimageräte und USVs; Wandanschlüsse brauchen weiter einen direkten Treffer.
func _find_assisted_port(cable_type: String, racks_only: bool = false) -> String:
	if _world == null or _camera == null or not _world.has_method("get_port_world_pos"):
		return ""
	var ids: Array = GameState.racks.keys()
	if cable_type == "power" and not racks_only:
		for cid_v in GameState.coolers.keys():
			if not GameState.is_indoor_unit(str(cid_v)):
				ids.append(cid_v)
		ids = ids + GameState.ups_units.keys()
	if ids.is_empty():
		return ""
	var origin := _camera.global_position
	var fwd := -_camera.global_transform.basis.z
	var best_id := ""
	var best_off := PORT_ASSIST_RADIUS
	for id_v in ids:
		var eid := str(id_v)
		var p: Variant = _world.get_port_world_pos(cable_type, eid)
		if not (p is Vector3):
			continue
		var port_pos: Vector3 = p
		var to_port := port_pos - origin
		var along := to_port.dot(fwd)
		if along <= 0.0 or along > INTERACT_RANGE:
			continue
		var off := (to_port - fwd * along).length()
		if off < best_off and _port_in_sight(origin, port_pos):
			best_off = off
			best_id = eid
	return best_id


## Zielhilfe beim Kabelstart: Mit leerer Hand nimmt der Klick das Kabel am nächsten Rack-Port auf,
## auch wenn der Strahl die Hitbox knapp verfehlt.
func _try_assisted_cable_start() -> void:
	if GameState.is_player_holding_anything(peer_id):
		return
	# Nächster Port quer zur Blickrichtung gewinnt; bei Gleichstand hat Strom Vorrang (Reihenfolge).
	var pitch_by_type := {"power": 1.05, "network": 1.15, "cluster": 1.25}
	var best_type := ""
	var best_id := ""
	var best_off := INF
	for t_v in ["power", "network", "cluster"]:
		var t := str(t_v)
		var tid := _find_assisted_port(t, true)
		if tid == "":
			continue
		var off := _aim_offset_to_port(t, tid)
		if off < best_off:
			best_off = off
			best_type = t
			best_id = tid
	if best_id == "":
		return
	cable_active_type = best_type
	cable_start_id = best_id
	cable_start_slot = -1
	SfxManager.play("cable", -8.0, float(pitch_by_type[best_type]))


## Abstand eines Ports quer zur Blickrichtung (Meter). Unbekannte Ports liefern INF.
func _aim_offset_to_port(cable_type: String, eid: String) -> float:
	var p: Variant = _world.get_port_world_pos(cable_type, eid)
	if not (p is Vector3):
		return INF
	var to_port: Vector3 = (p as Vector3) - _camera.global_position
	var fwd := -_camera.global_transform.basis.z
	return (to_port - fwd * to_port.dot(fwd)).length()


## Sichtprüfung gegen feste Körper (Layer 1), damit kein Port durch Wände oder von hinten gewählt wird.
func _port_in_sight(origin: Vector3, port_pos: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, port_pos, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(port_pos) < PORT_ASSIST_SIGHT_SLACK


func _clear_shelf_hover() -> void:
	if is_instance_valid(_hovered_shelf) and _hovered_shelf.has_method("set_hovered_slot"):
		_hovered_shelf.call("set_hovered_slot", -1, {})
	_hovered_shelf = null


func _clear_rack_hover() -> void:
	if is_instance_valid(_hovered_rack) and _hovered_rack.has_method("set_hovered_slot"):
		_hovered_rack.call("set_hovered_slot", -1, "default")
	_hovered_rack = null


func _is_two_handed_item(item_type: String, pack_count: int = 1) -> bool:
	if pack_count > 1:
		return true
	if item_type == "" or GameState.is_repair_kit(item_type) or item_type == "fuse":
		return false
	return true


func _update_viewmodel_motion(delta: float, flat_speed: float) -> void:
	if not is_local or _held_root == null:
		return
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_vm_land_dip = 0.055
	_was_on_floor = on_floor

	var held_ext := GameState.is_player_holding_extinguisher(peer_id)
	var held_crate := GameState.get_player_held_crate(peer_id)
	var item_type := str(held_crate.get("item_type", ""))
	var state_key := "ext" if held_ext else (item_type if not held_crate.is_empty() else ("cable:" + cable_active_type if not cable_active_type.is_empty() else ""))
	if state_key != _vm_last_state_key:
		_vm_last_state_key = state_key
		if state_key != "":
			_vm_equip = 1.0
			# Das Ding kommt von dort, wo es lag, in die Hände.
			var from := _camera.to_local(_vm_from) if _vm_from != Vector3.ZERO else Vector3(0, -0.5, -0.7)
			from.z = minf(from.z, -0.35)
			_held_root.position = from.limit_length(1.3)

	_vm_sway = _vm_sway.lerp(Vector2.ZERO, clampf(delta * 10.5, 0.0, 1.0))
	_vm_equip = move_toward(_vm_equip, 0.0, delta * 3.8)
	_vm_land_dip = lerpf(_vm_land_dip, 0.0, clampf(delta * 11.0, 0.0, 1.0))

	var two_handed := (not held_ext) and (not held_crate.is_empty()) and _is_two_handed_item(item_type, maxi(1, int(held_crate.get("pack_count", 1))))
	var base_pos := Vector3(0.0, -0.33, -0.54) if two_handed else (Vector3(0.12, -0.27, -0.42) if held_ext else Vector3(0.20, -0.21, -0.40))
	var base_scale := 0.50 if two_handed else (0.48 if held_ext else 0.46)

	# Figure-8 Lauf- & Atembewegung
	var move_amp := clampf(flat_speed / MOVE_SPEED, 0.0, 1.45) if (on_floor and not is_seated_at_pc) else 0.0
	var bob_x := cos(_walk_cycle * 0.5) * 0.016 * move_amp
	var bob_y := absf(sin(_walk_cycle * 0.5)) * -0.018 * move_amp + sin(_anim_time * 1.9) * 0.004
	var equip_ease := _vm_equip * _vm_equip * _vm_equip

	var target_pos := base_pos + Vector3(
		_vm_sway.x + bob_x,
		_vm_sway.y + bob_y - _vm_land_dip,
		0.0
	)
	_held_root.position = _held_root.position.lerp(target_pos, clampf(delta * lerpf(18.0, 7.5, _vm_equip), 0.0, 1.0))
	var cur_s := lerpf(_held_root.scale.x, base_scale, clampf(delta * 14.0, 0.0, 1.0))
	_held_root.scale = Vector3(cur_s, cur_s, cur_s)

	# Subtiles Rollen beim Strafen & Neigen beim Aufnehmen
	var local_vel := global_transform.basis.inverse() * velocity
	var strafe_roll := clampf(-local_vel.x * 0.014, -0.07, 0.07)
	var target_rot := Vector3(
		_vm_sway.y * 1.4 - equip_ease * 0.42,
		_vm_sway.x * 1.8,
		strafe_roll - _vm_sway.x * 0.9
	)
	_held_root.rotation = _held_root.rotation.lerp(target_rot, clampf(delta * 14.0, 0.0, 1.0))


func _update_placement_preview(delta: float) -> void:
	if _ghost_root == null or not _ghost_root.is_inside_tree():
		return

	# Zuerst Lagerregal-Hover aktualisieren: wenn man ein Fach anvisiert, übernimmt das Regal die Vorschau!
	var held := GameState.get_player_held_crate(peer_id)
	var aimed := _get_aimed_interactable()
	if aimed != null and relocating_rack_id == "" and str(aimed.get_meta("interact_type", "")) == "decor_shelf_slot":
		var shelf_obj: Variant = aimed.get_meta("shelf_prop", null)
		var s_idx := int(aimed.get_meta("slot_idx", -1))
		if is_instance_valid(shelf_obj) and (shelf_obj as Object).has_method("set_hovered_slot"):
			if _hovered_shelf != null and _hovered_shelf != shelf_obj:
				_clear_shelf_hover()
			_hovered_shelf = shelf_obj as Object
			_hovered_shelf.call("set_hovered_slot", s_idx, held)
			_ghost_root.visible = false
			_ghost_has_visual_pose = false
			return
	_clear_shelf_hover()

	var item_type := ""
	var ignore_rid := ""
	var is_placeable := false
	if relocating_rack_id != "" and GameState.racks.has(relocating_rack_id):
		item_type = str(GameState.racks[relocating_rack_id].get("rack_type", "rack"))
		ignore_rid = relocating_rack_id
		is_placeable = true
	elif relocating_rack_id != "" and GameState.decor_items.has(relocating_rack_id):
		item_type = str((GameState.decor_items[relocating_rack_id] as Dictionary).get("item_type", ""))
		ignore_rid = relocating_rack_id
		is_placeable = true
	else:
		if held.is_empty():
			_rot_manual = false
			_ghost_root.visible = false
			_ghost_has_visual_pose = false
			return
		item_type = str(held["item_type"])
		is_placeable = (str(GameState.ITEM_CATALOG[item_type]["category"]) == "placeable")

	# Wenn man ein nicht-platzierbares Item (Box/Kit/Server) trägt und auf Werkbank/Rack zielt, keinen Boden-Drop-Ring zeigen
	if not is_placeable and aimed != null:
		_ghost_root.visible = false
		_ghost_has_visual_pose = false
		return

	var space := get_world_3d().direct_space_state
	var origin := _camera.global_position
	var max_dist := PLACE_RANGE if is_placeable else 3.2
	var end := origin + (-_camera.global_transform.basis.z) * max_dist
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_ghost_root.visible = false
		_ghost_has_visual_pose = false
		return

	var hpos: Vector3 = hit["position"]
	var hnormal: Vector3 = hit["normal"]
	_ghost_is_drop_preview = not is_placeable
	var wall_strip := false

	if not is_placeable:
		if hnormal.y < 0.7:
			_ghost_root.visible = false
			_ghost_has_visual_pose = false
			return
		_ghost_pos = Vector3(hpos.x, hpos.y, hpos.z)
		_ghost_rot_y = rotation.y + hold_yaw
		_ghost_valid = true
	elif item_type == GameState.INDOOR_UNIT_TYPE:
		var spot: Dictionary = GameState.get_wall_mount_spot(hpos, hnormal)
		if spot.is_empty():
			if absf(hnormal.y) > 0.3:
				_ghost_root.visible = false
				_ghost_has_visual_pose = false
				return
			_ghost_pos = hpos + hnormal * GameState.WALL_UNIT_OFFSET
			_ghost_rot_y = atan2(hnormal.x, hnormal.z)
			_ghost_valid = false
		else:
			_ghost_pos = spot["pos"]
			_ghost_rot_y = float(spot["rot_y"])
			_ghost_valid = true
	elif DecorSpec.is_wall_sign(item_type):
		var lspot := DecorSpec.sign_spot(hpos, hnormal)
		if lspot.is_empty():
			_ghost_pos = hpos + hnormal * 0.06
			_ghost_rot_y = atan2(hnormal.x, hnormal.z) if absf(hnormal.y) < 0.3 else place_rot_y
			_ghost_valid = false
		else:
			_ghost_pos = lspot["pos"]
			_ghost_rot_y = float(lspot["rot_y"])
			_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)
	elif DecorSpec.SIZES.has(item_type):
		# Zielt man auf eine Wand, zählt der Fußpunkt davor: so rastet das Stück sauber an.
		var floor_hit := hpos
		if hnormal.y < 0.7:
			if absf(hnormal.y) > 0.3 or not DecorSpec.WALL_SNAP.has(item_type):
				_ghost_root.visible = false
				_ghost_has_visual_pose = false
				return
			floor_hit = hpos + hnormal * DecorSpec.footprint(item_type).y * 0.5
		var pose := DecorSpec.snap_pose(item_type, Vector3(floor_hit.x, 0.0, floor_hit.z), place_rot_y, ignore_rid, _rot_manual)
		_ghost_pos = pose["pos"]
		_ghost_rot_y = float(pose["rot_y"])
		_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)
	elif GameState.is_strip_type(item_type) and absf(hnormal.y) < 0.3:
		wall_strip = true
		var sspot: Dictionary = GameState.get_strip_wall_spot(hpos, hnormal)
		if sspot.is_empty():
			_ghost_pos = hpos
			_ghost_rot_y = atan2(hnormal.x, hnormal.z)
			_ghost_valid = false
		else:
			_ghost_pos = sspot["pos"]
			_ghost_rot_y = float(sspot["rot_y"])
			_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)
	else:
		if hnormal.y < 0.7:
			_ghost_root.visible = false
			_ghost_has_visual_pose = false
			return
		_ghost_pos = GameState.snap_place_pos(item_type, hpos)
		_ghost_rot_y = place_rot_y
		_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)

	# Leisten rasten an das Ende einer anderen Leiste und sind dann ohne Kabel verbunden.
	_ghost_strip_link = ""
	if is_placeable and GameState.is_strip_type(item_type):
		var sn := StripRules.snap_spot("power" if item_type == "prop_power_strip" else "network", _ghost_pos, wall_strip, ignore_rid)
		if not sn.is_empty():
			_ghost_pos = sn["pos"]
			_ghost_rot_y = float(sn["rot_y"])
			_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)
			_ghost_strip_link = str(sn["other"])

	# Echtes 3D-Hologramm-Modell bei Typwechsel aufbauen
	var gkey := ("%s|%s" % [item_type, "drop" if _ghost_is_drop_preview else "place"])
	if _ghost_model_key != gkey:
		if _ghost_model_key.get_slice("|", 0) != item_type:
			_rot_manual = false
		_rebuild_ghost_model(item_type, held, _ghost_is_drop_preview)
		_ghost_model_key = gkey

	# Sanftes AAA-Spring-Gleiten auf Raster & Drehung
	if not _ghost_has_visual_pose:
		_ghost_visual_pos = _ghost_pos
		_ghost_visual_rot = _ghost_rot_y
		_ghost_has_visual_pose = true
	else:
		var pk := clampf(delta * 18.0, 0.0, 1.0)
		var rk := clampf(delta * 16.0, 0.0, 1.0)
		_ghost_visual_pos = _ghost_visual_pos.lerp(_ghost_pos, pk)
		_ghost_visual_rot = lerp_angle(_ghost_visual_rot, _ghost_rot_y, rk)

	_ghost_root.visible = true
	_ghost_root.position = _ghost_visual_pos
	_ghost_root.basis = Basis(Vector3.UP, _ghost_visual_rot) * (Basis(Vector3.RIGHT, PI * 0.5) if wall_strip else Basis.IDENTITY)

	if _ghost_is_drop_preview:
		_ghost_holo_mat.set_shader_parameter("holo_color", Color(0.28, 0.78, 1.0, 0.36))
		_ghost_frame_mat.albedo_color = Color(0.32, 0.84, 1.0, 0.80)
		_ghost_frame_mat.emission = Color(0.28, 0.78, 1.0)
	elif _ghost_valid:
		_ghost_holo_mat.set_shader_parameter("holo_color", Color(0.14, 0.96, 0.56, 0.44))
		_ghost_frame_mat.albedo_color = Color(0.22, 1.0, 0.62, 0.94)
		_ghost_frame_mat.emission = Color(0.18, 0.96, 0.54)
	else:
		_ghost_holo_mat.set_shader_parameter("holo_color", Color(0.98, 0.22, 0.20, 0.50))
		_ghost_frame_mat.albedo_color = Color(1.0, 0.26, 0.22, 0.95)
		_ghost_frame_mat.emission = Color(0.98, 0.18, 0.16)


func _update_cable_preview() -> void:
	if _world == null or not _world.has_method("update_cable_preview"):
		return
	if cable_start_id == "" or cable_active_type == "":
		_world.update_cable_preview(false, "power", Vector3.ZERO, Vector3.ZERO)
		return
	var start_pos: Variant = _world.get_socket_world_pos(cable_active_type, cable_start_id, cable_start_slot)
	if start_pos == null:
		cable_start_id = ""
		cable_active_type = ""
		_world.update_cable_preview(false, "power", Vector3.ZERO, Vector3.ZERO)
		return
	var hand_pos := _camera.global_position + (-_camera.global_transform.basis.z) * 1.05 + Vector3(0.0, -0.22, 0.0)
	var endpoint := _resolve_aimed_cable_endpoint(cable_active_type)
	var target_state := _cable_target_state(endpoint)
	var snap: Variant = null
	if target_state != CableRenderer.TARGET_NONE:
		# Vorschau rastet an der Buchse ein, die beim Klick genommen wird
		var p: Variant = _world.get_socket_world_pos(cable_active_type, endpoint, _aimed_socket_idx(cable_active_type, endpoint))
		if p is Vector3 and (p as Vector3).distance_to(hand_pos) < 2.5:
			snap = p
	_world.update_cable_preview(true, cable_active_type, start_pos as Vector3, hand_pos, target_state, snap)


## Prüft das anvisierte Ziel wie der Server: freie Ports an beiden Enden, keine doppelte Verbindung.
func _cable_target_state(endpoint: String) -> int:
	if endpoint == "" or cable_active_type == "" or endpoint == cable_start_id:
		return CableRenderer.TARGET_NONE
	if GameState.count_cables_on(cable_active_type, endpoint) >= GameState.get_max_ports(cable_active_type, endpoint):
		return CableRenderer.TARGET_INVALID
	# Genau anvisierte Buchse schon belegt: nicht heimlich auf eine andere ausweichen.
	var aimed := _get_aimed_interactable() as Area3D
	if aimed != null and str(aimed.get_meta("entity_id", "")) == endpoint:
		var aimed_slot := _get_target_slot_idx(aimed, cable_active_type, endpoint)
		if aimed_slot >= 0 and not GameState.get_cable_on_slot(cable_active_type, endpoint, aimed_slot).is_empty():
			return CableRenderer.TARGET_INVALID
	if GameState.count_cables_on(cable_active_type, cable_start_id) >= GameState.get_max_ports(cable_active_type, cable_start_id):
		return CableRenderer.TARGET_INVALID
	if not bool(_strip_plan(endpoint)["ok"]):
		return CableRenderer.TARGET_INVALID
	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c.get("cable_type", "")) != cable_active_type:
			continue
		var a := str(c.get("from_id", ""))
		var b := str(c.get("to_id", ""))
		if (a == cable_start_id and b == endpoint) or (a == endpoint and b == cable_start_id):
			return CableRenderer.TARGET_INVALID
	return CableRenderer.TARGET_VALID


## Prüft wie der Server, ob das Kabel so an eine Leiste darf (Seite, Eingang, Ausgang).
func _strip_plan(endpoint: String) -> Dictionary:
	return StripRules.plan(cable_active_type, cable_start_id, cable_start_slot, endpoint, _aimed_socket_idx(cable_active_type, endpoint))


## Name einer Buchse an einer Leiste für die Hinweise.
func _strip_socket_name(ctype: String, eid: String, slot: int) -> String:
	match StripRules.slot_kind(ctype, eid, slot):
		"in":
			return tr("Eingang (weiß)")
		"out":
			return tr("Ausgang (rot)")
		"top":
			return (tr("Steckdose %d/%d") if ctype == "power" else tr("Port %d/%d")) % [slot + 1, StripRules.top_count(ctype)]
	return ""


## Zieht das Kabel am anvisierten Port (slot_idx) oder zuletzt gesteckte Kabel ab und nimmt das freie Ende in die Hand.
func _unplug_into_hand(cable_type: String, endpoint_id: String, slot_idx: int = -1) -> void:
	var other := ""
	var other_slot := -1
	if slot_idx >= 0:
		var slot_cab := GameState.get_cable_on_slot(cable_type, endpoint_id, slot_idx)
		if not slot_cab.is_empty():
			if str(slot_cab.get("from_id", "")) == endpoint_id:
				other = str(slot_cab.get("to_id", ""))
				other_slot = int(slot_cab.get("to_slot", -1))
			else:
				other = str(slot_cab.get("from_id", ""))
				other_slot = int(slot_cab.get("from_slot", -1))
			GameState.request_disconnect_cable_slot(cable_type, endpoint_id, slot_idx)
			if other != "":
				cable_start_id = other
				cable_start_slot = other_slot
				cable_active_type = cable_type
			return
	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c.get("cable_type", "")) != cable_type:
			continue
		var a := str(c.get("from_id", ""))
		var b := str(c.get("to_id", ""))
		if a == endpoint_id:
			other = b
			other_slot = int(c.get("to_slot", -1))
		elif b == endpoint_id:
			other = a
			other_slot = int(c.get("from_slot", -1))
	GameState.request_disconnect_cables_on(cable_type, endpoint_id)
	if other != "":
		cable_start_id = other
		cable_start_slot = other_slot
		cable_active_type = cable_type


func _strip_sub(ctype: String, eid: String, slot: int) -> String:
	match StripRules.slot_kind(ctype, eid, slot):
		"in":
			return tr("Hier kommt der Strom vom Kasten oder vom Ausgang der Leiste davor an") if ctype == "power" else tr("Hier kommt der Uplink vom Router oder von der LAN-Leiste davor an")
		"out":
			return tr("Führt zum Eingang der nächsten Leiste (oder Leiste direkt anstecken)")
	return tr("Oben nur Geräte: Racks, USV, Kühlung") if ctype == "power" else tr("Oben nur Racks")


func _cable_label(cable_type: String) -> String:
	match cable_type:
		"power":
			return tr("Stromkabel (Gelb)")
		"cluster":
			return tr("Cluster-Kabel (Lila)")
		_:
			return tr("Netzwerkkabel (Blau)")


func _update_context_prompt() -> void:
	_fill_context_prompt()
	if relocating_rack_id == "" and current_prompt != "" and _rotatable_kind(_get_aimed_interactable()) != "":
		current_sub_prompt += ("  •  " if current_sub_prompt != "" else "") + tr("[R] Drehen")


func _fill_context_prompt() -> void:
	current_prompt = ""
	current_sub_prompt = ""

	# Active 1-Hand Pulled Cable Prompt!
	if cable_start_id != "" and cable_active_type != "":
		var label := _cable_label(cable_active_type)
		var endpoint := _resolve_aimed_cable_endpoint(cable_active_type)
		if endpoint != "":
			if cable_start_id == endpoint:
				current_prompt = tr("[E / Rechtsklick] %s abbrechen") % label
			elif not bool(_strip_plan(endpoint)["ok"]):
				current_prompt = tr(str(_strip_plan(endpoint)["msg"]))
				current_sub_prompt = tr("[Rechtsklick / Q] Kabel loslassen")
			elif _cable_target_state(endpoint) == CableRenderer.TARGET_INVALID:
				current_prompt = tr("%s: %s ist voll oder schon verbunden") % [label, endpoint.to_upper()]
				current_sub_prompt = tr("[Rechtsklick / Q] Kabel loslassen")
			else:
				current_prompt = tr("[E] %s einstecken: %s ↔ %s") % [label, cable_start_id.to_upper(), endpoint.to_upper()]
				current_sub_prompt = tr("[Rechtsklick / Q] Kabel loslassen")
		else:
			current_prompt = tr("%s von %s in der Hand — Ziel-Buchse / Rack anvisieren") % [label, cable_start_id.to_upper()]
			current_sub_prompt = tr("[Rechtsklick / Q] Abbrechen")
		return

	if relocating_rack_id != "":
		if _ghost_root != null and _ghost_root.visible and _ghost_valid:
			current_prompt = tr("[Klick / E] %s hier neu aufstellen") % _relocating_name()
		else:
			current_prompt = tr("Neuen freien Bodenplatz für %s wählen") % _relocating_name()
		if GameState.decor_items.has(relocating_rack_id):
			current_sub_prompt = tr("[R] Drehen  •  [Q / Rechtsklick] Abbrechen (Kabel bleiben dran)")
		else:
			current_sub_prompt = tr("[R] Drehen  •  [Q / Rechtsklick] Abbrechen (Alle Server bleiben erhalten)")
		return

	var held := GameState.get_player_held_crate(peer_id)
	var target := _get_aimed_interactable()
	var target_type := str(target.get_meta("interact_type")) if target != null else ""
	var prioritize_target := (target_type == "decor_shelf_slot" or target_type == "workbench" or target_type == "cart" or target_type == "decor_use")

	if not prioritize_target and not held.is_empty():
		var item_type := str(held["item_type"])
		var cat: Dictionary = GameState.ITEM_CATALOG[item_type]
		if str(cat["category"]) == "placeable" and _ghost_root != null and _ghost_root.visible and not _ghost_is_drop_preview:
			_clear_rack_hover()
			if _ghost_valid:
				current_prompt = tr("[Linksklick / E] %s hier platzieren") % tr(str(cat["name"]))
				if _ghost_strip_link != "":
					current_prompt = tr("[Linksklick / E] %s direkt anstecken (ohne Kabel verbunden)") % tr(str(cat["name"]))
			elif item_type == GameState.INDOOR_UNIT_TYPE:
				current_prompt = tr("Hier geht es nicht – auf eine freie Innenwand zielen (nicht über dem Garagentor)")
			elif GameState.is_heat_pump_type(item_type):
				current_prompt = tr("Hier geht es nicht – nur auf dem Rasen rechts vom Garagentor aufstellen")
			else:
				current_prompt = tr("Platz blockiert – freien Bereich in der Garage wählen")
			if _follows_wall(item_type):
				current_sub_prompt = tr("Richtet sich nach der Wand  •  [Q] Karton ablegen")
			else:
				current_sub_prompt = tr("[R / Mausrad] Drehen (90°)  •  [Q] Karton ablegen")
			return

	# Rack-Slot 3D-Hover-Rahmen nur zeigen, wenn direkt auf einen Einschub gezielt wird
	if target == null or str(target.get_meta("interact_type", "")) != "rack_slot":
		_clear_rack_hover()

	if target == null:
		if not held.is_empty() and _ghost_root != null and _ghost_root.visible and _ghost_is_drop_preview:
			current_sub_prompt = tr("[R] Drehen  •  [Q] %s am markierten Punkt abstellen") % GameState.get_crate_display_label(held)
			return
		var pc := GameState.get_player_pushed_cart(peer_id)
		if not pc.is_empty():
			var cnt := (pc.get("items", []) as Array).size()
			current_sub_prompt = tr("Schiebt Rollwagen (%d/%d Kartons)  •  Auf Karton [E] zum Aufladen  •  [Q] Loslassen") % [cnt, GameState.CART_MAX_ITEMS]
		elif GameState.is_player_holding_extinguisher(peer_id):
			current_sub_prompt = tr("Feuerlöscher %d %%  •  [Linksklick halten] Sprühen  •  [Q] Auf den Boden stellen") % roundi(GameState.get_extinguisher_fill(GameState.get_held_extinguisher(peer_id)) * 100.0)
		elif not held.is_empty():
			var h_name := str(GameState.ITEM_CATALOG[str(held["item_type"])]["name"])
			current_sub_prompt = tr("Trägt: %s  •  [Q] Ablegen") % tr(h_name)
		return

	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	match itype:
		"terminal":
			current_prompt = tr("[E] Verion OS öffnen (Shop, Verträge, Router, Upgrades)")
			if PcScreenState.is_occupied_by_other():
				current_prompt = tr("PC besetzt: %s sitzt gerade davor") % PcScreenState.user_name
		"garage_door":
			var garage := _world.get_node_or_null("Garage") if _world != null else null
			var door_open := true
			if garage != null and garage.has_method("is_garage_door_open"):
				door_open = bool(garage.call("is_garage_door_open"))
			current_prompt = tr("[E] Garagentor schließen (dämpft Straßenlärm)") if door_open else tr("[E] Garagentor öffnen")
		"shuttle_teleport":
			if not GameState.halle_nord_owned:
				current_prompt = tr("Shuttle-Terminal: Großstandort Halle Nord ab Level 3 im PC kaufbar ($8.500)")
			elif position.z < -80.0:
				current_prompt = tr("[E] Zurück zur Start-Garage teleportieren (oder Taste [T])")
			else:
				current_prompt = tr("[E] Nach HALLE NORD (240 m²) teleportieren (oder Taste [T])")
		"decor_shelf_slot":
			var s_idx := int(target.get_meta("slot_idx", 0))
			var sd: Dictionary = GameState.decor_items.get(eid, {})
			var stype := str(sd.get("item_type", ""))
			var at := ShelfSpec.owner_of(sd, s_idx)
			if not held.is_empty():
				if ShelfSpec.fit(sd, s_idx, held) >= 0:
					current_prompt = tr("[E] %s hier einlagern") % GameState.get_crate_display_label(held)
				elif ShelfSpec.span(stype, held) <= 0:
					current_prompt = tr("Passt nicht in dieses Regal")
					if ShelfSpec.needs_pallet(held):
						current_sub_prompt = tr("Große Geräte passen nur ins Palettenregal")
				else:
					current_prompt = tr("Hier ist kein Platz mehr (braucht %d Plätze nebeneinander)") % ShelfSpec.span(stype, held)
			elif at >= 0:
				current_prompt = tr("[E] %s nehmen") % GameState.get_crate_display_label((sd["stored_items"] as Array)[at])
			else:
				current_prompt = tr(GameState.get_decor_name(eid))
			if current_sub_prompt == "":
				current_sub_prompt = tr("[F] Umsetzen oder verkaufen")
		"decor_use":
			var dp: Array = DecorManager.prompt_for(eid)
			current_prompt = str(dp[0])
			current_sub_prompt = str(dp[1])
		"delivery_sign":
			current_prompt = tr("[E] Lieferung unterschreiben")
		"parts_cabinet":
			current_prompt = tr("[E] +3 Wartungs- & Ersatzteil-Kits auffüllen ($20 • Vorrat: %d/12)") % GameState.maint_kits
			current_sub_prompt = tr("[F] Umsetzen oder verkaufen")
		"decor_info":
			var ip: Array = DecorManager.prompt_for(eid)
			current_prompt = str(ip[0])
			current_sub_prompt = tr("[F] Umsetzen oder verkaufen")
		"wall_breaker":
			if GameState.grid_outage_left > 0.0:
				current_prompt = tr("Netzausfall der Stadtwerke: Strom kommt in ca. %d Min. zurück") % GameState.get_grid_outage_minutes()
			elif GameState.breaker_on:
				current_prompt = tr("[E] Hauptschalter AUSSCHALTEN")
			elif not GameState.has_working_fuse():
				current_prompt = tr("Hauptschalter gesperrt: keine intakte Sicherung eingesetzt")
			else:
				current_prompt = tr("[E] Hauptschalter EINSCHALTEN (Blackout beheben!)")
		"fuse_slot":
			var fz_slot := int(target.get_meta("slot_idx", -1))
			var fz_state := "empty"
			if fz_slot >= 0 and fz_slot < GameState.breaker_fuses.size():
				fz_state = str(GameState.breaker_fuses[fz_slot])
			if fz_slot == GameState.POWER_FUSE_SLOT and GameState.power_fuse_stock > 0:
				current_prompt = tr("[E] Drehsicherung in F2 einsetzen (Stromstufe +1, alte Sicherung kommt in die Hand – Hände frei!)")
			elif fz_state == "ok":
				current_prompt = tr("Sicherung F%d: intakt") % (fz_slot + 1)
			elif GameState.fuse_stock <= 0:
				current_prompt = tr("Sicherung F%d: %s – keine Sicherung im Lager, am PC kaufen") % [fz_slot + 1, tr("durchgebrannt") if fz_state == "blown" else tr("leer")]
			elif fz_state == "blown":
				current_prompt = tr("[E] Durchgebrannte Sicherung F%d ersetzen (%d im Lager)") % [fz_slot + 1, GameState.fuse_stock]
			else:
				current_prompt = tr("[E] Sicherung in F%d einsetzen (%d im Lager)") % [fz_slot + 1, GameState.fuse_stock]
			current_sub_prompt = tr("Auf gelbe Buchse unten zielen für Stromkabel")
		"wall_router":
			if GameState.ddos_active:
				current_prompt = tr("[E] DDOS-ANGRIFF ABWEHREN!")
			else:
				var rt_info: Dictionary = GameState.ROUTER_TIERS[clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)]
				var used_n := GameState.count_cables_on("network", eid)
				var max_n := GameState.get_max_ports("network", eid)
				current_prompt = tr("[E] Netzwerkkabel ziehen (%s • %d/%d Ports)") % [str(rt_info["speed"]), used_n, max_n]
				current_sub_prompt = tr("[F] Router-Geschwindigkeit upgraden  •  [Rechtsklick] Kabel trennen")
		"power_port":
			var used_p := GameState.count_cables_on("power", eid)
			var max_p := GameState.get_max_ports("power", eid)
			var p_slot := _get_target_slot_idx(target, "power", eid)
			var p_lbl := tr("Stromleiste") if GameState.is_power_strip_decor(eid) else eid.to_upper()
			if p_slot >= 0 and StripRules.role("power", eid) == "strip":
				var nm_p := _strip_socket_name("power", eid, p_slot)
				var occ_s := GameState.get_cable_on_slot("power", eid, p_slot)
				if StripRules.is_linked("power", eid, p_slot):
					current_prompt = tr("%s: direkt mit der Nachbarleiste verbunden") % nm_p
				elif not occ_s.is_empty():
					var peer_s := str(occ_s.get("to_id", "")) if str(occ_s.get("from_id", "")) == eid else str(occ_s.get("from_id", ""))
					current_prompt = tr("[E / Rechtsklick] Kabel aus %s ziehen (↔ %s)") % [nm_p, peer_s.to_upper()]
				else:
					current_prompt = tr("[E] Stromkabel an %s anstecken") % nm_p
				current_sub_prompt = _strip_sub("power", eid, p_slot)
			elif p_slot >= 0:
				var occ_p := GameState.get_cable_on_slot("power", eid, p_slot)
				if not occ_p.is_empty():
					var peer_p := str(occ_p.get("to_id", "")) if str(occ_p.get("from_id", "")) == eid else str(occ_p.get("from_id", ""))
					current_prompt = tr("[E / Rechtsklick] Stromkabel aus Steckdose %d/%d ziehen (%s ↔ %s)") % [p_slot + 1, max_p, p_lbl, peer_p.to_upper()]
					current_sub_prompt = tr("Belegt: %d/%d Steckdosen") % [used_p, max_p]
				else:
					current_prompt = tr("[E] Stromkabel an Steckdose %d/%d anstecken (%s • frei)") % [p_slot + 1, max_p, p_lbl]
					current_sub_prompt = tr("Belegt: %d/%d Steckdosen") % [used_p, max_p]
			else:
				current_prompt = tr("[E] Verlängerungskabel ziehen (%s • %d/%d Steckdosen)") % [p_lbl, used_p, max_p]
				if used_p > 0:
					current_sub_prompt = tr("[Rechtsklick] Letztes Stromkabel hier abziehen")
			if GameState.decor_items.has(eid):
				current_sub_prompt += "  •  " + tr("[F] Leiste umsetzen")
		"net_port":
			var used_np := GameState.count_cables_on("network", eid)
			var max_np := GameState.get_max_ports("network", eid)
			var n_slot := _get_target_slot_idx(target, "network", eid)
			var n_lbl := tr("LAN-Leiste") if GameState.is_lan_strip_decor(eid) else (tr("Router") if eid == GameState.WALL_ROUTER_ID else eid.to_upper())
			if n_slot >= 0 and StripRules.role("network", eid) == "strip":
				var nm_n := _strip_socket_name("network", eid, n_slot)
				var occ_l := GameState.get_cable_on_slot("network", eid, n_slot)
				if StripRules.is_linked("network", eid, n_slot):
					current_prompt = tr("%s: direkt mit der Nachbarleiste verbunden") % nm_n
				elif not occ_l.is_empty():
					var peer_l := str(occ_l.get("to_id", "")) if str(occ_l.get("from_id", "")) == eid else str(occ_l.get("from_id", ""))
					current_prompt = tr("[E / Rechtsklick] Kabel aus %s ziehen (↔ %s)") % [nm_n, peer_l.to_upper()]
				else:
					current_prompt = tr("[E] Netzwerkkabel an %s anstecken") % nm_n
				current_sub_prompt = _strip_sub("network", eid, n_slot)
			elif n_slot >= 0:
				var occ_n := GameState.get_cable_on_slot("network", eid, n_slot)
				if not occ_n.is_empty():
					var peer_n := str(occ_n.get("to_id", "")) if str(occ_n.get("from_id", "")) == eid else str(occ_n.get("from_id", ""))
					current_prompt = tr("[E / Rechtsklick] LAN-Kabel aus Port %d/%d ziehen (%s ↔ %s)") % [n_slot + 1, max_np, n_lbl, peer_n.to_upper()]
					current_sub_prompt = tr("Belegt: %d/%d Ports") % [used_np, max_np]
				else:
					current_prompt = tr("[E] Netzwerkkabel an Port %d/%d anstecken (%s • frei)") % [n_slot + 1, max_np, n_lbl]
					current_sub_prompt = tr("Belegt: %d/%d Ports") % [used_np, max_np]
			else:
				current_prompt = tr("[E] Blaues Netzwerkkabel ziehen (%s • %d/%d Ports)") % [n_lbl, used_np, max_np]
				if used_np > 0:
					current_sub_prompt = tr("[Rechtsklick] Letztes Netzwerkkabel hier abziehen")
			if GameState.decor_items.has(eid):
				current_sub_prompt += "  •  " + tr("[F] Leiste umsetzen")
		"cluster_port":
			var used_cp := GameState.count_cables_on("cluster", eid)
			var max_cp := GameState.get_max_ports("cluster", eid)
			current_prompt = tr("[E] Lila Cluster-Kabel ziehen (%s • %d/%d Ports)") % [eid.to_upper(), used_cp, max_cp]
			if used_cp > 0:
				current_sub_prompt = tr("[Rechtsklick] Letztes Cluster-Kabel hier abziehen")
			else:
				current_sub_prompt = tr("Verbundene Racks leihen sich bei Engpässen freie Hardware")
		"extinguisher_station":
			var p_station := str(target.get_meta("station", "garage"))
			var p_ext := GameState.get_extinguisher_at_station(p_station)
			if GameState.is_player_holding_extinguisher(peer_id):
				current_prompt = tr("[E] Feuerlöscher zurückhängen") if p_ext == "" else tr("Hier hängt schon ein Feuerlöscher")
			elif p_ext == "":
				current_prompt = tr("Halter ist leer. Der Feuerlöscher muss erst zurückgebracht werden.")
			else:
				current_prompt = tr("[E] Feuerlöscher nehmen")
				current_sub_prompt = tr("Füllung: %d %%") % roundi(GameState.get_extinguisher_fill(p_ext) * 100.0)
		"strip_switch":
			var sd: Dictionary = GameState.decor_items.get(eid, {})
			if bool(sd.get("tripped", false)):
				current_prompt = tr("[E] Ausgelöste Leiste wieder einschalten")
			else:
				current_prompt = tr("[E] Leiste ausschalten") if GameState.is_strip_on(eid) else tr("[E] Leiste einschalten")
			if GameState.is_power_strip_decor(eid):
				current_sub_prompt = tr("Last: %d / %d W") % [GameState.get_strip_load(eid), GameState.get_strip_limit(eid)]
		"paper_bin":
			if str(held.get("item_type", "")) == "empty_carton":
				current_prompt = tr("[E] Karton einwerfen (+$%d)") % CartonFactory.refund(str(held.get("carton", "deco")))
			elif not GameState.get_player_pushed_cart(peer_id).is_empty():
				current_prompt = tr("[E] Leere Kartons vom Rollwagen einwerfen")
			else:
				current_prompt = tr("Altpapier: leere Kartons hier einwerfen")
		"extinguisher_item":
			current_prompt = tr("[E] Feuerlöscher aufheben")
			current_sub_prompt = tr("Füllung: %d %%") % roundi(GameState.get_extinguisher_fill(eid) * 100.0)
		"rack_panel":
			var rpp: Variant = target.get_meta("rack_prop", null)
			if is_instance_valid(rpp) and (rpp as Object).has_method("is_panel_open"):
				var panel_owner := rpp as Object
				var pid := str(target.get_meta("panel_id", ""))
				var plabel := str(panel_owner.call("get_panel_label", pid))
				if panel_owner.has_method("get_panel_prompt"):
					current_prompt = str(panel_owner.call("get_panel_prompt", pid))
				elif bool(panel_owner.call("is_panel_open", pid)):
					current_prompt = tr("[E] %s schließen") % plabel
				else:
					current_prompt = tr("[E] %s öffnen") % plabel
				current_sub_prompt = eid.to_upper()
		"crate":
			if GameState.crates.has(eid):
				var cname := GameState.get_crate_display_label(GameState.crates[eid] as Dictionary)
				var pc := GameState.get_player_pushed_cart(peer_id)
				if not pc.is_empty():
					var cnt := (pc.get("items", []) as Array).size()
					if cnt < GameState.CART_MAX_ITEMS:
						current_prompt = tr("[E] %s direkt auf Rollwagen laden (%d/%d)") % [cname, cnt, GameState.CART_MAX_ITEMS]
					else:
						current_prompt = tr("Rollwagen ist voll (4/4) – erst mit [Q] abstellen!")
				elif GameState.is_player_holding_anything(peer_id):
					current_prompt = tr("%s (Hände voll – erst [Q] ablegen)") % cname
				else:
					current_prompt = tr("[E] %s aufheben") % cname
		"cart":
			if GameState.carts.has(eid):
				var cdict: Dictionary = GameState.carts[eid]
				var cnt := (cdict.get("items", []) as Array).size()
				var pby := int(cdict.get("pushed_by", 0))
				if pby != 0:
					current_prompt = tr("Rollwagen wird von %s geschoben (%d/%d)") % [NetworkManager.get_player_name(pby), cnt, GameState.CART_MAX_ITEMS]
				elif not held.is_empty():
					var h_name := str(GameState.ITEM_CATALOG[str(held["item_type"])]["name"])
					current_prompt = tr("[E] %s auf Rollwagen laden (%d/%d)") % [tr(h_name), cnt, GameState.CART_MAX_ITEMS]
				else:
					current_prompt = tr("[E] Rollwagen schieben (%d/%d Kartons)") % [cnt, GameState.CART_MAX_ITEMS]
					if cnt > 0:
						current_sub_prompt = tr("[Rechtsklick] Karton runternehmen  •  [F] Verwalten / Verkaufen")
					else:
						current_sub_prompt = tr("[F] Verwalten / Verkaufen")
		"cooler_unit":
			if GameState.coolers.has(eid):
				var ctype := str(GameState.coolers[eid].get("cooler_type", "cooler"))
				current_prompt = tr("[E / F] %s verwalten (Umsetzen / Verkaufen)") % str(GameState.ITEM_CATALOG[ctype]["name"])
				var cl := OutdoorManager.clog(eid)
				if cl >= 0.25:
					current_prompt = tr("[E] Außengerät reinigen (Leistung nur %d %%)") % int(round(OutdoorManager.unit_factor(eid) * 100.0))
				if ctype == GameState.INDOOR_UNIT_TYPE:
					current_sub_prompt = tr("Kein Kabel nötig: läuft, sobald ein Goldis-Außengerät Strom hat")
				else:
					current_sub_prompt = tr("Auf die gelbe Buchse oben zielen für Stromkabel") if GameState.is_floor_cooler_type(ctype) else tr("Auf die gelbe Buchse an der rechten Seite zielen für Stromkabel")
		"ups_unit":
			if GameState.ups_units.has(eid):
				var ch := float(GameState.ups_units[eid]["charge"])
				var ups_state := tr("NOTSTROM!") if bool(GameState.ups_units[eid].get("discharging", false)) else (tr("LÄDT/BEREIT") if bool(GameState.ups_units[eid].get("connected", false)) else tr("KEIN KABEL"))
				current_prompt = tr("[E / F] USV-Batterie %s (%.0f%%, %s) — Umsetzen / Verkaufen") % [eid.to_upper(), ch, ups_state]
				current_sub_prompt = tr("Auf die gelbe Buchse unten zielen für Stromkabel")
		"locker":
			current_prompt = tr("[E] Spind: Figur umziehen")
		"outdoor", "bench", "ladder":
			var op: Array = OutdoorPrompts.prompt_for(eid, itype)
			current_prompt = str(op[0])
			current_sub_prompt = str(op[1])
		"workbench":
			GameState.select_bench(eid)
			var wb := GameState.workbench_state
			var wb_mode := str(wb.get("mode", ""))
			if wb.is_empty() and GameState.decor_items.has(eid):
				current_sub_prompt = tr("[F] Umsetzen oder verkaufen")
			if wb.is_empty():
				if not held.is_empty() and (str(held["item_type"]) == "slot_build_box" or str(held["item_type"]) == "server_tray"):
					current_prompt = tr("[E] %s auf Werkbank ablegen") % GameState.get_crate_display_label(held)
				else:
					current_prompt = tr("IT-Werkbank (frei)")
					if current_sub_prompt == "":
						current_sub_prompt = tr("Bausatz-Karton oder defekten Server-Schlitten herbringen")
			elif wb_mode == "build_box":
				current_prompt = tr("[E] Bausatz auspacken (%s)") % str(wb.get("label", "Server"))
				current_sub_prompt = tr("[Rechtsklick] Karton wieder aufnehmen")
			elif GameState.is_workbench_job() and GameState.get_workbench_worker() < 0:
				current_prompt = tr("[E] Von %s übernehmen") % TechnicianManager.get_worker_name()
			elif GameState.is_workbench_job() and GameState.get_workbench_worker() > 0:
				current_prompt = tr("%s arbeitet gerade") % NetworkManager.get_player_name(GameState.get_workbench_worker())
			elif wb_mode == "assembly":
				var fmt_a := tr("[E] Weiterbauen (%s)") if GameState.is_workbench_started() else tr("[E] Zusammenbau starten (%s)")
				current_prompt = fmt_a % str(wb.get("label", "Server"))
				if not GameState.is_workbench_started():
					current_sub_prompt = tr("[Rechtsklick] Karton wieder aufnehmen")
			elif wb_mode == "repair":
				var fmt_r := tr("[E] Weiter reparieren (%s)") if GameState.is_workbench_started() else tr("[E] Reparatur starten (%s)")
				current_prompt = fmt_r % str(wb.get("label", "Server"))
				if not GameState.is_workbench_started():
					current_sub_prompt = tr("[Rechtsklick] Server-Schlitten wieder aufnehmen")
			elif wb_mode == "service":
				current_prompt = tr("[E] Überholen (%s)") % str(wb.get("label", "Server"))
				if not GameState.is_workbench_started():
					current_sub_prompt = tr("[Rechtsklick] Server-Schlitten wieder aufnehmen")
			elif wb_mode == "ready_tray":
				current_prompt = tr("[E] Fertigen Server aufnehmen (%s)") % str(wb.get("label", "Server"))
				current_sub_prompt = tr("Ins ausgefahrene Rack einsetzen")
				if GameState.can_workbench_service():
					current_sub_prompt = tr("[F] Überholen (Bauqualität %d %%)") % GameState.get_build_quality(wb)
		"rack_slot":
			var sidx := int(target.get_meta("slot_index"))
			var rp_obj: Variant = target.get_meta("rack_prop", null)
			if is_instance_valid(rp_obj) and (rp_obj as Object).has_method("set_hovered_slot"):
				if _hovered_rack != null and _hovered_rack != rp_obj:
					_clear_rack_hover()
				_hovered_rack = rp_obj as Object
			if GameState.racks.has(eid):
				var rname := GameState.get_rack_display_name(eid)
				var slot: Dictionary = GameState.racks[eid]["slots"][sidx]
				var st_item := str(slot["item_type"])
				var st_state := str(slot["state"])
				var is_ext := GameState.is_slot_extended(eid, sidx)
				var hover_mode := "default"
				if st_state == "burning":
					hover_mode = "warn"
					if GameState.is_player_holding_extinguisher(peer_id):
						current_prompt = tr("[Linksklick HALTEN] Brand in %s · Slot %d löschen!") % [rname, sidx + 1]
						current_sub_prompt = tr("Füllung: %d %%") % roundi(GameState.get_extinguisher_fill(GameState.get_held_extinguisher(peer_id)) * 100.0)
					else:
						current_prompt = tr("SERVER BRENNT! Feuerlöscher vom Wandhalter holen!")
				elif not held.is_empty() and str(held["item_type"]) == "server_tray":
					if st_item != "":
						hover_mode = "warn"
						current_prompt = tr("%s · Slot %d ist belegt — leeren Slot wählen!") % [rname, sidx + 1]
						current_sub_prompt = tr("[Rechtsklick] Schacht %d %s") % [sidx + 1, tr("einfahren") if is_ext else tr("ausfahren")]
					elif is_ext:
						hover_mode = "insert"
						current_prompt = tr("[E] Server in %s · Slot %d einsetzen") % [rname, sidx + 1]
						current_sub_prompt = tr("[Rechtsklick] Schacht einfahren  •  [Q] Server ablegen")
					else:
						hover_mode = "insert"
						current_prompt = tr("[E / Rechtsklick] Schacht %d ausfahren (%s)") % [sidx + 1, rname]
						current_sub_prompt = tr("Danach [E] zum Einsetzen drücken")
				elif is_ext and st_item != "" and not GameState.is_player_holding_anything(peer_id):
					hover_mode = "pull"
					current_prompt = tr("[E] Server-Schlitten herausziehen (%s · Slot %d)") % [rname, sidx + 1]
					current_sub_prompt = tr("[Rechtsklick] Schacht einfahren  •  [F] Rack-Menü")
				elif st_state == "crashed":
					hover_mode = "warn"
					current_prompt = tr("[E] %s · Slot %d (AUSGEFALLEN)") % [rname, sidx + 1]
					current_sub_prompt = tr("[Rechtsklick] Schacht ausfahren (→ Werkbank)  •  [F] Rack-Menü")
				elif st_item == "":
					if not held.is_empty() and str(GameState.ITEM_CATALOG[str(held["item_type"])]["category"]) == "module":
						hover_mode = "insert"
						current_prompt = tr("[E] %s in %s · Slot %d einschieben") % [
							str(GameState.ITEM_CATALOG[str(held["item_type"])]["name"]), rname, sidx + 1
						]
						current_sub_prompt = tr("[Rechtsklick] Schacht %d %s") % [sidx + 1, tr("einfahren") if is_ext else tr("ausfahren")]
					else:
						current_prompt = tr("[E / F] %s · Slot %d (frei)") % [rname, sidx + 1]
						current_sub_prompt = tr("[Rechtsklick] Schacht %d %s") % [sidx + 1, tr("einfahren") if is_ext else tr("ausfahren")]
				else:
					current_prompt = tr("[E / F] %s · Slot %d verwalten") % [rname, sidx + 1]
					current_sub_prompt = tr("[Rechtsklick] Schacht %d %s") % [sidx + 1, tr("einfahren") if is_ext else tr("ausfahren")]
				if is_instance_valid(_hovered_rack):
					_hovered_rack.call("set_hovered_slot", sidx, hover_mode)


func _update_held_visuals() -> void:
	if _held_root == null:
		return
	var held_ext := GameState.is_player_holding_extinguisher(peer_id)
	var held_crate := GameState.get_player_held_crate(peer_id)

	_held_extinguisher.visible = held_ext
	if not held_crate.is_empty():
		var item_type := str(held_crate["item_type"])
		var pcount := maxi(1, int(held_crate.get("pack_count", 1)))
		var cache_key := "%s|%s|%d" % [item_type, str(held_crate.get("label", "")), pcount]
		_held_item_holder.visible = true
		if _held_item_type_cached != cache_key:
			for c in _held_item_holder.get_children():
				c.queue_free()
			var model: Node3D
			if pcount > 1 or GameState.is_repair_kit(item_type) or item_type == "slot_build_box" or item_type == "server_tray":
				model = StorageShelfProp.build_stored_visual(held_crate)
			else:
				model = HardwareMeshFactory.build_item_visual(item_type, held_crate)
				model.scale = Vector3(0.82, 0.82, 0.82)
			if pcount > 1:
				model.scale = Vector3(0.96, 0.96, 0.96)
				model.position = Vector3(0.0, -0.06, -0.02)
			elif item_type == "server_tray":
				model.scale = Vector3(0.88, 0.88, 0.88)
				model.position = Vector3(0.0, -0.04, -0.02)
			elif item_type == "slot_build_box":
				model.scale = Vector3(1.0, 1.0, 1.0)
				model.position = Vector3(0.0, -0.06, -0.02)
			elif GameState.is_repair_kit(item_type):
				model.scale = Vector3(0.92, 0.92, 0.92)
				model.position = Vector3(0.0, -0.02, -0.02)
			else:
				model.position = Vector3(0.0, -0.05, 0.0)
			_held_item_holder.add_child(model)
			_held_item_type_cached = cache_key
			if is_local:
				for vi in model.find_children("*", "VisualInstance3D", true, false):
					(vi as VisualInstance3D).layers = FpArms.LAYER
			_held_half_xz = Vector2(_visual_half_width(model), _visual_half_width(model, true))
		if _hold_cid != str(held_crate["id"]):
			_hold_cid = str(held_crate["id"])
			hold_yaw = 0.0
			_held_item_holder.rotation.y = 0.0
		_held_item_holder.rotation.y = lerp_angle(_held_item_holder.rotation.y, hold_yaw, clampf(get_process_delta_time() * 14.0, 0.0, 1.0))
		var across := absf(sin(_held_item_holder.rotation.y))
		_held_half_w = clampf(lerpf(_held_half_xz.x, _held_half_xz.y, across) + 0.01, 0.10, 0.40)
	else:
		_held_item_holder.visible = false
		if _held_item_type_cached != "":
			for c in _held_item_holder.get_children():
				c.queue_free()
			_held_item_type_cached = ""


func _update_foam_visuals(spraying: bool) -> void:
	if _held_lever_pivot != null:
		var lever_target := deg_to_rad(EXT_LEVER_PRESS_DEG) if spraying else 0.0
		_held_lever_pivot.rotation.x = lerpf(_held_lever_pivot.rotation.x, lever_target, 0.35)
	if _foam_root == null:
		return
	_foam_root.visible = spraying
	if not spraying:
		return
	for i in range(_foam_balls.size()):
		var ball := _foam_balls[i]
		var t := fmod(_anim_time * 4.5 + float(i) * 0.25, 1.0)
		ball.position = Vector3(sin(_anim_time * 16.0 + float(i)) * 0.08 * t, -0.04 * t, -0.35 - t * 2.1)
		var s := 0.5 + t * 1.4
		ball.scale = Vector3(s, s, s)


func _build_avatar_visuals() -> void:
	_avatar_root = Node3D.new()
	add_child(_avatar_root)
	_build_human()
	_add_nametag()


## Eigene Figur: nur Schatten (im Spiegel zeigt LockerProp eine eigene). Mitspieler: ganz.
func _build_human() -> void:
	if _human != null:
		_human.queue_free()
	_human = HumanModel.create(skin_data if not skin_data.is_empty() else SettingsManager.get_skin())
	_avatar_root.add_child(_human)
	if is_local:
		for mi in _human.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			# Eigene Ebene: Hallenlampen können die eigene Figur aus ihren Schatten nehmen (WorldController).
			(mi as MeshInstance3D).layers = MeshMerger.LOCAL_BODY_LAYER
		for l in _human.find_children("*", "Label3D", true, false):
			(l as Label3D).visible = false


static func _visual_half_width(n: Node3D, depth: bool = false) -> float:
	var hw := 0.0
	for mi_n in n.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var ab := (Transform3D(Basis.from_scale(n.scale), Vector3.ZERO) * xf) * mi.mesh.get_aabb()
		hw = maxf(hw, maxf(absf(ab.position.z), absf(ab.end.z)) if depth else maxf(absf(ab.position.x), absf(ab.end.x)))
	return hw


func _add_nametag() -> void:
	_nametag = Label3D.new()
	_nametag.text = player_name
	_nametag.font_size = 30
	_nametag.pixel_size = 0.0048
	_nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nametag.position = Vector3(0.0, 2.04, 0.0)
	_nametag.modulate = Color(0.95, 0.95, 0.95)
	add_child(_nametag)

	_emote_badge = Label3D.new()
	_emote_badge.text = ""
	_emote_badge.font_size = 34
	_emote_badge.pixel_size = 0.0052
	_emote_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_badge.position = Vector3(0.0, 2.28, 0.0)
	_emote_badge.modulate = Color(1.0, 0.88, 0.36)
	_emote_badge.visible = false
	add_child(_emote_badge)


func _build_held_visuals() -> void:
	_held_root = Node3D.new()

	# Dynamically holds the REAL 3D Server Hardware / Packaged Freight Unit!
	_held_item_holder = Node3D.new()
	_held_item_holder.visible = false
	_held_root.add_child(_held_item_holder)

	_held_extinguisher = Node3D.new()
	_held_extinguisher.visible = false
	_held_root.add_child(_held_extinguisher)

	# Gleiches 6-kg-Pulverlöscher-Modell wie an der Wand, nur mit der Düse nach vorn (-Z),
	# damit der Schaum aus _update_foam_visuals direkt aus der Löschpistole kommt.
	var e := _held_extinguisher
	var red_paint := _mat(Color(0.80, 0.06, 0.05), 0.22, 0.25)
	var white := _mat(Color(0.95, 0.95, 0.93), 0.55, 0.0)
	var black_rubber := _mat(Color(0.07, 0.07, 0.08), 0.75, 0.0)
	var black_plastic := _mat(Color(0.10, 0.10, 0.11), 0.42, 0.0)
	var chrome := MatLib.make_brushed_metal(Color(0.82, 0.83, 0.85), 0.16, 0.95)
	var seal_yellow := _mat(Color(0.95, 0.80, 0.10), 0.5, 0.0)
	var sticker_green := _mat(Color(0.20, 0.58, 0.30), 0.6, 0.0)

	_add_cyl_part(e, Vector3(0.0, -0.03, 0.0), 0.085, 0.085, 0.40, red_paint)
	var dome := MeshInstance3D.new()
	var dsm := SphereMesh.new()
	dsm.radius = 0.085
	dsm.height = 0.11
	dsm.radial_segments = 24
	dsm.rings = 12
	dome.mesh = dsm
	dome.material_override = red_paint
	dome.position = Vector3(0.0, 0.17, 0.0)
	e.add_child(dome)
	_add_cyl_part(e, Vector3(0.0, -0.225, 0.0), 0.087, 0.087, 0.03, black_plastic)
	_add_cyl_part(e, Vector3(0.0, -0.05, 0.0), 0.0865, 0.0865, 0.15, white)
	_add_cyl_part(e, Vector3(0.0, -0.165, -0.0855), 0.016, 0.016, 0.002, sticker_green, Vector3(90, 0, 0))

	# Armatur: Hals, Ventilkopf, Manometer, Schlaghebel, Tragegriff, Sicherungsstift
	_add_cyl_part(e, Vector3(0.0, 0.235, 0.0), 0.024, 0.024, 0.05, chrome)
	_add_cyl_part(e, Vector3(0.0, 0.275, 0.0), 0.030, 0.030, 0.045, chrome)
	_add_cyl_part(e, Vector3(0.036, 0.282, 0.0), 0.020, 0.020, 0.016, chrome, Vector3(0, 0, 90))
	_add_cyl_part(e, Vector3(0.0445, 0.282, 0.0), 0.016, 0.016, 0.002, white, Vector3(0, 0, 90))
	# Drehpunkt am vorderen Hebelende (am Ventilkopf), Ruhelage wie vorher
	_held_lever_pivot = Node3D.new()
	_held_lever_pivot.position = Vector3(0.0, 0.316, -0.03)
	e.add_child(_held_lever_pivot)
	var lever := _add_box(_held_lever_pivot, Vector3(0.0, 0.0, 0.075), Vector3(0.034, 0.016, 0.17), black_plastic)
	lever.rotation_degrees.x = 10.0
	var carry := _add_box(e, Vector3(0.0, 0.293, 0.04), Vector3(0.034, 0.016, 0.15), black_plastic)
	carry.rotation_degrees.x = -3.0
	_add_box(e, Vector3(0.027, 0.287, -0.032), Vector3(0.004, 0.012, 0.008), seal_yellow)

	# Schlauch vom Ventil nach vorn zur Löschpistole, Trichter zeigt nach -Z
	_add_hose_part(e, PackedVector3Array([
		Vector3(0.0, 0.265, -0.03),
		Vector3(0.0, 0.25, -0.09),
		Vector3(0.0, 0.14, -0.15),
		Vector3(0.0, 0.02, -0.19),
		Vector3(0.0, 0.0, -0.20),
	]), 0.011, black_rubber)
	_add_cyl_part(e, Vector3(0.0, 0.0, -0.205), 0.0135, 0.0135, 0.02, chrome, Vector3(-90, 0, 0))
	_add_cyl_part(e, Vector3(0.0, 0.0, -0.27), 0.030, 0.014, 0.11, black_plastic, Vector3(-90, 0, 0))

	_foam_root = Node3D.new()
	_foam_root.visible = false
	_held_extinguisher.add_child(_foam_root)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.92, 0.96, 1.0, 0.82)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for _i in range(6):
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		b.mesh = sm
		b.material_override = fmat
		_foam_root.add_child(b)
		_foam_balls.append(b)


## Zylinder oder Kegelstumpf für das gehaltene Modell. Vector3(-90, 0, 0) lässt die Oberseite nach -Z zeigen.
func _add_cyl_part(parent: Node3D, pos: Vector3, top_r: float, bottom_r: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = 20
	cm.rings = 0
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Schlauch als Kette von Zylindern durch `points`.
func _add_hose_part(parent: Node3D, points: PackedVector3Array, radius: float, mat: Material) -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.0001:
			continue
		var dir := seg / length
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = length + radius
		cm.radial_segments = 10
		cm.rings = 0
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		var q: Quaternion = Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
		mi.transform = Transform3D(Basis(q), (a + b) * 0.5)
		parent.add_child(mi)


## Vom Host geprüfter Admin-Teleport (nur der eigene Spieler).
func admin_teleport(pos: Vector3, yaw: float) -> void:
	if not is_local or not pos.is_finite():
		return
	is_seated_at_pc = false
	is_typing_at_pc = false
	_stand_blend_timer = 0.0
	relocating_rack_id = ""
	cable_start_id = ""
	cable_start_slot = -1
	if is_crouching:
		_apply_crouch(false)
	position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	SfxManager.play("save", -7.0, 1.08)
	if _world != null and _world.has_method("send_local_pose"):
		_world.send_local_pose(position, rotation.y, _head_pivot.rotation.x, 0, false)


## Wer durch die Welt fällt, landet wieder sicher am eigenen Standort.
func _rescue_from_fall() -> void:
	velocity = Vector3.ZERO
	if position.z < -80.0 and GameState.halle_nord_owned:
		position = GameState.HALLE_NORD_ORIGIN + Vector3(3.2, 0.12, -4.2)
	else:
		position = Vector3(-4.1, 0.12, -3.5)


func teleport_between_sites() -> void:
	if not GameState.is_active:
		return
	if not GameState.halle_nord_owned:
		SfxManager.play("error", -10.0)
		GameState.post_event("Großstandort Halle Nord ist noch nicht gekauft (ab Firmenstufe 3 unter Upgrades & Standorte).", "warn")
		return
	# Falls der Teleport vom PC-Sitz aus gestartet wurde: Sitzmodus & Aufsteh-Blend sofort beenden,
	# damit die Kamera weder am Monitor klebt noch zur Start-Garage zurückblendet!
	is_seated_at_pc = false
	is_typing_at_pc = false
	_stand_blend_timer = 0.0
	set_ui_locked(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ein gerade halb gezogenes Kabel sauber abbrechen; getragene Items (Kisten/Server/Kits/Feuerlöscher) bleiben in der Hand!
	if not cable_start_id.is_empty():
		cable_start_id = ""
		cable_start_slot = -1
	if is_crouching:
		_apply_crouch(false)
	var in_nord := (position.z < -80.0)
	if in_nord:
		position = Vector3(-4.1, 0.12, -3.5)
		rotation.y = -PI * 0.5
		GameState.post_event("📍 Standortwechsel: Start-Garage.", "info")
	else:
		position = GameState.HALLE_NORD_ORIGIN + Vector3(3.2, 0.12, -4.2)
		rotation.y = 0.0
		GameState.post_event("📍 Standortwechsel: Großstandort HALLE NORD (240 m²).", "good")
	velocity = Vector3.ZERO
	_head_pivot.rotation.x = 0.0
	SfxManager.play("save", -7.0, 1.08)
	if _world != null and _world.has_method("send_local_pose"):
		_world.send_local_pose(position, rotation.y, _head_pivot.rotation.x, 0, false)


func _build_placement_ghost() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.visible = false
	if _world != null:
		_world.add_child.call_deferred(_ghost_root)
	else:
		get_parent().add_child.call_deferred(_ghost_root)

	# AAA Blueprint-Fresnel + Scanline Hologramm-Shader
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;
uniform vec4 holo_color : source_color = vec4(0.14, 0.96, 0.56, 0.44);
void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.2);
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 0.30 - TIME * 4.8);
	float pulse = 0.88 + 0.12 * sin(TIME * 3.0);
	ALBEDO = holo_color.rgb * (1.05 + fresnel * 1.25);
	ALPHA = clamp((holo_color.a * 0.42 + fresnel * 0.68 + scan * 0.08) * pulse, 0.10, 0.92);
}
"""
	_ghost_holo_mat = ShaderMaterial.new()
	_ghost_holo_mat.shader = sh
	_ghost_holo_mat.set_shader_parameter("holo_color", Color(0.14, 0.96, 0.56, 0.44))

	_ghost_frame_mat = StandardMaterial3D.new()
	_ghost_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_frame_mat.albedo_color = Color(0.22, 1.0, 0.62, 0.94)
	_ghost_frame_mat.emission_enabled = true
	_ghost_frame_mat.emission = Color(0.18, 0.96, 0.54)
	_ghost_frame_mat.emission_energy_multiplier = 1.6

	_ghost_model_holder = Node3D.new()
	_ghost_root.add_child(_ghost_model_holder)

	_ghost_footprint = Node3D.new()
	_ghost_root.add_child(_ghost_footprint)

	# Leuchtender Front-Richtungs-Pfeil am Boden (zeigt exakt wohin die Rack-Glastür öffnet!)
	_ghost_front_arrow = Node3D.new()
	_ghost_root.add_child(_ghost_front_arrow)
	var shaft := _add_box(_ghost_front_arrow, Vector3(0.0, 0.015, 0.10), Vector3(0.06, 0.012, 0.18), _ghost_frame_mat)
	var wing_l := _add_box(_ghost_front_arrow, Vector3(-0.075, 0.015, 0.17), Vector3(0.045, 0.012, 0.18), _ghost_frame_mat)
	wing_l.rotation_degrees.y = -42.0
	var wing_r := _add_box(_ghost_front_arrow, Vector3(0.075, 0.015, 0.17), Vector3(0.045, 0.012, 0.18), _ghost_frame_mat)
	wing_r.rotation_degrees.y = 42.0
	var front_lbl := Label3D.new()
	front_lbl.text = "FRONT"
	front_lbl.font_size = 24
	front_lbl.pixel_size = 0.0022
	front_lbl.shaded = false
	front_lbl.modulate = Color(0.90, 1.0, 0.95)
	front_lbl.position = Vector3(0.0, 0.022, 0.34)
	front_lbl.rotation_degrees.x = -90.0
	_ghost_front_arrow.add_child(front_lbl)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Präziser Boden-Zielring für nicht-platzierbare Items (beim Ablegen mit [Q])
	_ghost_drop_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.20
	tm.outer_radius = 0.23
	_ghost_drop_ring.mesh = tm
	_ghost_drop_ring.material_override = _ghost_frame_mat
	_ghost_drop_ring.position = Vector3(0.0, 0.014, 0.0)
	_ghost_drop_ring.visible = false
	_ghost_root.add_child(_ghost_drop_ring)


const DECOR_GHOSTS := {
	"prop_power_strip": ["power_strip", Vector2(0.70, 0.16)],
	"prop_lan_strip": ["lan_strip", Vector2(0.66, 0.18)],
}


func _rebuild_ghost_model(item_type: String, held: Dictionary, is_drop_preview: bool) -> void:
	for c in _ghost_model_holder.get_children():
		c.queue_free()
	for c in _ghost_footprint.get_children():
		c.queue_free()

	var fp_size := Vector2(0.92, 0.92)
	var show_footprint := not is_drop_preview and item_type != GameState.INDOOR_UNIT_TYPE
	_ghost_drop_ring.visible = is_drop_preview
	_ghost_footprint.visible = show_footprint
	_ghost_front_arrow.visible = show_footprint

	var model: Node3D = null
	if is_drop_preview:
		if GameState.is_repair_kit(item_type) or item_type == "slot_build_box" or item_type == "server_tray":
			model = StorageShelfProp.build_stored_visual(held)
		else:
			model = HardwareMeshFactory.build_item_visual(item_type, held)
	elif item_type == "rack_pro":
		model = ModelLoader.instantiate_custom_model("rack_pro")
		fp_size = Vector2(0.94, 0.94)
	elif item_type == "rack":
		model = ModelLoader.instantiate_custom_model("rack_std")
		fp_size = Vector2(0.94, 0.94)
	elif GameState.is_ups_type(item_type):
		model = ModelLoader.instantiate_custom_model(str(UpsProp.MODELS[item_type]))
		var us: Vector3 = UpsProp.SIZES[item_type]
		fp_size = Vector2(us.x, us.z)
	elif DecorSpec.MODELS.has(item_type):
		model = ModelLoader.instantiate_custom_model(str(DecorSpec.MODELS[item_type]))
		fp_size = DecorSpec.footprint(item_type)
	elif DECOR_GHOSTS.has(item_type):
		model = ModelLoader.instantiate_custom_model(str(DECOR_GHOSTS[item_type][0]))
		fp_size = DECOR_GHOSTS[item_type][1]
	elif GameState.is_heat_pump_type(item_type) or GameState.is_floor_cooler_type(item_type) or item_type == GameState.INDOOR_UNIT_TYPE:
		var box_sz: Vector3 = CoolerProp.GHOST_SIZES.get(item_type, Vector3(1.04, 0.98, 0.48))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box_sz
		mi.mesh = bm
		mi.position = Vector3(0.0, 0.0 if item_type == GameState.INDOOR_UNIT_TYPE else box_sz.y * 0.5, 0.0)
		model = mi
		fp_size = Vector2(box_sz.x + 0.04, box_sz.z + 0.04)

	if model == null:
		var fb := MeshInstance3D.new()
		var fbm := BoxMesh.new()
		fbm.size = Vector3(0.90, 2.10, 0.90)
		fb.mesh = fbm
		fb.position = Vector3(0.0, 1.05, 0.0)
		model = fb

	_apply_holo_shader_recursive(model, _ghost_holo_mat)
	_ghost_model_holder.add_child(model)

	if show_footprint:
		var hx := fp_size.x * 0.5
		var hz := fp_size.y * 0.5
		var corner_len := minf(0.22, minf(hx, hz) * 0.65)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_add_box(_ghost_footprint, Vector3(sx * (hx - corner_len * 0.5), 0.012, sz * hz), Vector3(corner_len, 0.012, 0.022), _ghost_frame_mat)
				_add_box(_ghost_footprint, Vector3(sx * hx, 0.012, sz * (hz - corner_len * 0.5)), Vector3(0.022, 0.012, corner_len), _ghost_frame_mat)
				_add_box(_ghost_footprint, Vector3(sx * hx, 0.09, sz * hz), Vector3(0.016, 0.16, 0.016), _ghost_frame_mat)
		_ghost_front_arrow.position = Vector3(0.0, 0.0, hz + 0.06)


func _apply_holo_shader_recursive(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n is Label3D or n is Light3D or n is CPUParticles3D:
		if n is Node3D:
			(n as Node3D).visible = false
	for c in n.get_children():
		_apply_holo_shader_recursive(c, mat)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
