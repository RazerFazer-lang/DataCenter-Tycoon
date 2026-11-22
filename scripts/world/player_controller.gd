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
const AVATAR_MODEL_ID := "player"

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

var ui_locked: bool = false
var is_seated_at_pc: bool = false
var is_typing_at_pc: bool = false
var _pre_seat_pos: Vector3 = Vector3(2.78, 0.0, -2.05)
var _pre_seat_yaw: float = 0.0
var _stand_blend_timer: float = 0.0
var _remote_pose_flag: int = 0 # 0=standing, 1=seated at PC, 2=seated & typing, 3=crouching

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
var _avatar_head: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _nametag: Label3D

# Held visual (shown in first-person corner OR in remote avatar's hands)
var _held_root: Node3D
var _held_item_holder: Node3D
## Ich-Perspektive: Unterarm + Hand (nur lokaler Spieler, sonst null).
var _fp_hand: Node3D
const FP_HAND_ITEM_POS := Vector3(0.0, -0.13, 0.02)
const FP_HAND_EXT_POS := Vector3(0.0, 0.26, 0.0)
var _held_item_type_cached: String = ""
var _held_extinguisher: Node3D
var _foam_root: Node3D
## Schlaghebel des Feuerlöschers in der Hand: wird beim Sprühen heruntergedrückt.
var _held_lever_pivot: Node3D
const EXT_LEVER_PRESS_DEG := 8.0
var _foam_balls: Array[MeshInstance3D] = []

# Floor placement hologram (local only)
var _ghost_root: Node3D
var _ghost_mesh: MeshInstance3D
var _ghost_front_strip: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_valid: bool = false
var _ghost_rot_y: float = 0.0
var _ghost_pos: Vector3 = Vector3.ZERO

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

# Skin (Hose, Haut). Die Jacke steckt in avatar_color.
var skin_pants_color: Color = Color(0.15, 0.17, 0.21)
var skin_tone_color: Color = Color(0.88, 0.72, 0.60)


func setup(p_peer_id: int, p_is_local: bool, p_name: String, p_color: Color, world_ref: Node) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	player_name = p_name
	avatar_color = p_color
	_world = world_ref


## Übernimmt den Skin aus dem Spieler-Eintrag. Nach setup() und vor add_child() aufrufen,
## weil die Visuals in _ready() entstehen.
func apply_skin(skin: Variant) -> void:
	var colors := SettingsManager.skin_colors(skin, avatar_color)
	avatar_color = colors["jacket"]
	skin_pants_color = colors["pants"]
	skin_tone_color = colors["tone"]


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
	add_child(_head_pivot)

	_build_avatar_visuals()
	_build_held_visuals()

	if is_local:
		_avatar_root.visible = false
		_nametag.visible = false

		_camera = Camera3D.new()
		_camera.fov = SettingsManager.fov
		_camera.near = 0.06
		_camera.far = 120.0
		_head_pivot.add_child(_camera)
		_camera.current = true
		SettingsManager.settings_changed.connect(_on_settings_changed)

		_ray = RayCast3D.new()
		_ray.target_position = Vector3(0.0, 0.0, -INTERACT_RANGE)
		_ray.collision_mask = 1 | 4
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = true
		_camera.add_child(_ray)

		_held_root.position = Vector3(0.36, -0.30, -0.62)
		_held_root.scale = Vector3(0.62, 0.62, 0.62)
		_camera.add_child(_held_root)
		_build_fp_hand()

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


func set_typing_at_pc(active: bool) -> void:
	is_typing_at_pc = active and is_seated_at_pc


func start_relocate_rack(rack_id: String) -> void:
	if not is_local or not GameState.racks.has(rack_id):
		return
	cable_start_id = ""
	relocating_rack_id = rack_id
	place_rot_y = float(GameState.racks[rack_id].get("rot_y", 0.0))
	SfxManager.play("pickup", -8.0)


func set_ui_locked(locked: bool) -> void:
	ui_locked = locked
	if ui_locked:
		_is_spraying_local = false
		current_prompt = ""
		current_sub_prompt = ""


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or ui_locked:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := SettingsManager.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		_head_pivot.rotation.x = clampf(
			_head_pivot.rotation.x - event.relative.y * sens,
			deg_to_rad(-82.0),
			deg_to_rad(82.0)
		)

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
		place_rot_y = fmod(place_rot_y + PI * 0.5, TAU)
		SfxManager.play("click", -10.0, 1.15)
	elif event.is_action_pressed("drop_item"):
		_handle_drop()
	elif event.is_action_pressed("inspect_rack"):
		_handle_inspect()
	elif event.is_action_pressed("interact"): # Interaktion nur über [E] (umlegbar), nicht per Linksklick
		_handle_primary_interact()
	elif event.is_action_pressed("secondary_action"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_handle_secondary_action()


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


func _handle_inspect() -> void:
	if relocating_rack_id != "" or cable_start_id != "":
		return
	var target := _get_aimed_interactable()
	if target == null or _world == null:
		return
	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	if itype == "rack_slot":
		var sidx := int(target.get_meta("slot_index"))
		_world.open_rack_inspector(eid, sidx)
	elif (itype == "power_port" or itype == "net_port" or itype == "cluster_port") and GameState.racks.has(eid):
		_world.open_rack_inspector(eid, 0)
	elif itype == "wall_router":
		_world.open_device_inspector("router", eid)
	elif itype == "cooler_unit" and GameState.coolers.has(eid):
		_world.open_device_inspector("cooler", eid)
	elif itype == "ups_unit" and GameState.ups_units.has(eid):
		_world.open_device_inspector("ups", eid)
	elif itype == "cart" and GameState.carts.has(eid):
		_world.open_device_inspector("cart", eid)


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
	_update_held_visuals()

	if not is_local:
		var prev_pos := position
		position = position.lerp(_target_pos, clampf(delta * 14.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 14.0, 0.0, 1.0))
		_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, _target_pitch, clampf(delta * 14.0, 0.0, 1.0))
		var horiz_speed := Vector2(position.x - prev_pos.x, position.z - prev_pos.z).length() / maxf(delta, 0.001)
		_animate_remote_avatar(delta, horiz_speed)
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
			if move_dir.length_squared() > 0.001:
				velocity.x = move_dir.x * speed
				velocity.z = move_dir.z * speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)

		move_and_slide()

	# Smoothly push active cart right in front of the player
	var pushed_cart := GameState.get_player_pushed_cart(peer_id)
	if not pushed_cart.is_empty() and _world != null:
		var cpos := _compute_pushed_cart_pos()
		_world.update_local_pushed_cart(str(pushed_cart["id"]), cpos, rotation.y)

	# Subtle first-person walk bob + realistic concrete/floor footsteps
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if not is_seated_at_pc and _stand_blend_timer <= 0.0:
		if is_on_floor() and flat_speed > 0.6 and not ui_locked:
			_walk_cycle += delta * (7.5 + flat_speed * 0.7)
			_head_pivot.position.y = lerpf(_head_pivot.position.y, _head_y() + sin(_walk_cycle) * 0.030, clampf(delta * 12.0, 0.0, 1.0))
			var step_interval := 0.34 if flat_speed > 5.8 else 0.48
			_footstep_accum += delta
			if _footstep_accum >= step_interval:
				_footstep_accum = 0.0
				SfxManager.play_footstep(flat_speed > 5.8)
		else:
			_footstep_accum = 0.25
			_head_pivot.position.y = lerpf(_head_pivot.position.y, _head_y(), clampf(delta * 10.0, 0.0, 1.0))

	if not ui_locked:
		_update_placement_preview()
		_update_cable_preview()
		_update_continuous_actions(delta)
		_update_context_prompt()
	else:
		if _ghost_root != null:
			_ghost_root.visible = false
		if _world != null and _world.has_method("update_cable_preview"):
			_world.update_cable_preview(false, "power", Vector3.ZERO, Vector3.ZERO)

	_update_foam_visuals(_is_spraying_local)

	_net_send_accum += delta
	if _net_send_accum >= 0.05:
		_net_send_accum = 0.0
		if _world != null and _world.has_method("send_local_pose"):
			var pose_flag := 2 if is_typing_at_pc else (1 if is_seated_at_pc else (3 if is_crouching else 0))
			_world.send_local_pose(position, rotation.y, _head_pivot.rotation.x, pose_flag, _is_spraying_local)
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


func _animate_remote_avatar(delta: float, horiz_speed: float) -> void:
	var seated := (_remote_pose_flag == 1 or _remote_pose_flag == 2)
	var typing := (_remote_pose_flag == 2)
	var crouching := (_remote_pose_flag == 3)

	if _avatar_root != null:
		var target_y := -0.34 if seated else (-0.42 if crouching else 0.0)
		_avatar_root.position.y = lerpf(_avatar_root.position.y, target_y, clampf(delta * 10.0, 0.0, 1.0))

	if _avatar_head != null:
		var head_x := clampf(_head_pivot.rotation.x * 0.65, -0.7, 0.7)
		if typing:
			head_x += sin(_anim_time * 8.0) * 0.05 - 0.14
		elif seated:
			head_x -= 0.08
		_avatar_head.rotation.x = lerpf(_avatar_head.rotation.x, head_x, clampf(delta * 12.0, 0.0, 1.0))

	if seated:
		if _left_leg != null and _right_leg != null:
			_left_leg.rotation.x = lerpf(_left_leg.rotation.x, 1.48, clampf(delta * 12.0, 0.0, 1.0))
			_right_leg.rotation.x = lerpf(_right_leg.rotation.x, 1.48, clampf(delta * 12.0, 0.0, 1.0))
		if _left_arm != null and _right_arm != null:
			var tl := 1.12 + (sin(_anim_time * 24.0) * 0.16 if typing else 0.0)
			var tr := 1.12 + (cos(_anim_time * 24.0 + 0.7) * 0.16 if typing else 0.0)
			_left_arm.rotation.x = lerpf(_left_arm.rotation.x, tl, clampf(delta * 16.0, 0.0, 1.0))
			_right_arm.rotation.x = lerpf(_right_arm.rotation.x, tr, clampf(delta * 16.0, 0.0, 1.0))
		return

	var moving := horiz_speed > 0.35
	if moving:
		_walk_cycle += delta * clampf(horiz_speed * 2.2, 6.0, 14.0)
	# Geduckt: Beine nach vorn angewinkelt, beim Schleichen nur kleiner Schritt.
	var swing_amp := 0.22 if crouching else 0.55
	var leg_base := 1.05 if crouching else 0.0
	var leg_swing := sin(_walk_cycle) * swing_amp if moving else 0.0
	if _left_leg != null and _right_leg != null:
		_left_leg.rotation.x = lerpf(_left_leg.rotation.x, leg_base + leg_swing, clampf(delta * 12.0, 0.0, 1.0))
		_right_leg.rotation.x = lerpf(_right_leg.rotation.x, leg_base - leg_swing, clampf(delta * 12.0, 0.0, 1.0))

	var holding := GameState.is_player_holding_anything(peer_id)
	if _left_arm != null and _right_arm != null:
		var target_l := 0.85 if holding else -leg_swing * 0.6
		var target_r := 0.85 if holding else leg_swing * 0.6
		_left_arm.rotation.x = lerpf(_left_arm.rotation.x, target_l, clampf(delta * 12.0, 0.0, 1.0))
		_right_arm.rotation.x = lerpf(_right_arm.rotation.x, target_r, clampf(delta * 12.0, 0.0, 1.0))


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
		GameState.request_return_extinguisher()
		return
	var pushed_cart := GameState.get_player_pushed_cart(peer_id)
	if not pushed_cart.is_empty():
		GameState.request_release_cart(_compute_pushed_cart_pos(), rotation.y)
		return
	var held := GameState.get_player_held_crate(peer_id)
	if not held.is_empty():
		var forward := -global_transform.basis.z
		var drop_pos := global_position + forward * 1.15
		drop_pos.y = 0.0
		GameState.request_drop_crate(drop_pos)


func _handle_primary_interact() -> void:
	if relocating_rack_id != "":
		if _ghost_root != null and _ghost_root.visible and _ghost_valid:
			GameState.request_relocate_rack(relocating_rack_id, _ghost_pos, place_rot_y)
			relocating_rack_id = ""
		else:
			SfxManager.play("error")
		return

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

	var held := GameState.get_player_held_crate(peer_id)
	if not held.is_empty():
		var item_type := str(held["item_type"])
		var cat_type := str(GameState.ITEM_CATALOG[item_type]["category"])
		if cat_type == "placeable" and _ghost_root != null and _ghost_root.visible:
			if _ghost_valid:
				GameState.request_place_held_structure(_ghost_pos, _ghost_rot_y)
			else:
				SfxManager.play("error")
			return

	var target := _get_aimed_interactable()
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
			# Die Einspeisung unten am Stromkasten ist auch bei geschlossener Tür erreichbar.
			if hands_empty:
				cable_active_type = "power"
				cable_start_id = eid
				cable_start_slot = _aimed_socket_idx("power", eid)
				SfxManager.play("cable", -8.0, 1.05)
		"net_port":
			if hands_empty:
				cable_active_type = "network"
				cable_start_id = eid
				cable_start_slot = _aimed_socket_idx("network", eid)
				SfxManager.play("cable", -8.0, 1.15)
		"cluster_port":
			if hands_empty:
				cable_active_type = "cluster"
				cable_start_id = eid
				cable_start_slot = -1
				SfxManager.play("cable", -8.0, 1.25)
		"extinguisher_station":
			if GameState.is_player_holding_extinguisher(peer_id):
				GameState.request_return_extinguisher()
			elif hands_empty:
				GameState.request_pickup_extinguisher()
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
			if hands_empty and _world != null and _world.has_method("open_device_inspector"):
				_world.open_device_inspector("cooler", eid)
		"ups_unit":
			if hands_empty and _world != null and _world.has_method("open_device_inspector"):
				_world.open_device_inspector("ups", eid)
		"rack_slot":
			var slot_idx := int(target.get_meta("slot_index"))
			if not held.is_empty():
				var held_type := str(held["item_type"])
				if str(GameState.ITEM_CATALOG[held_type]["category"]) == "module":
					GameState.request_install_module(eid, slot_idx)
			elif hands_empty:
				if GameState.racks.has(eid):
					var slot: Dictionary = GameState.racks[eid]["slots"][slot_idx]
					var st := str(slot["state"])
					if st != "crashed" and st != "burning":
						if _world != null and _world.has_method("open_rack_inspector"):
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

	if GameState.is_player_holding_anything(peer_id):
		_handle_drop()
		return

	var target := _get_aimed_interactable()
	if target != null:
		var itype := str(target.get_meta("interact_type"))
		var eid := str(target.get_meta("entity_id"))
		if itype == "rack_slot":
			var slot_idx := int(target.get_meta("slot_index"))
			GameState.request_remove_module(eid, slot_idx)
		elif itype == "cart":
			GameState.request_unload_cart_to_hands(eid)
		elif itype == "power_port":
			_unplug_into_hand("power", eid)
		elif itype == "net_port" or itype == "wall_router":
			_unplug_into_hand("network", eid)
		elif itype == "cluster_port":
			_unplug_into_hand("cluster", eid)


func _update_continuous_actions(delta: float) -> void:
	_is_spraying_local = false
	var target := _get_aimed_interactable()
	var holding_ext := GameState.is_player_holding_extinguisher(peer_id)

	if holding_ext and (Input.is_action_pressed("primary_action") or Input.is_action_pressed("interact")):
		_is_spraying_local = true
		SfxManager.keep_extinguisher_spraying()
		_action_tick_accum += delta
		if _action_tick_accum >= 0.16:
			_action_tick_accum = 0.0
			if target != null and str(target.get_meta("interact_type")) == "rack_slot":
				var eid := str(target.get_meta("entity_id"))
				var sidx := int(target.get_meta("slot_index"))
				GameState.request_extinguish_slot(eid, sidx, 0.20)
		return

	if cable_start_id == "" and not GameState.is_player_holding_anything(peer_id) and Input.is_action_pressed("interact"):
		if target != null and str(target.get_meta("interact_type")) == "rack_slot":
			var eid := str(target.get_meta("entity_id"))
			var sidx := int(target.get_meta("slot_index"))
			if GameState.racks.has(eid):
				var slot: Dictionary = GameState.racks[eid]["slots"][sidx]
				if str(slot["item_type"]) != "" and str(slot["state"]) == "crashed" and not GameState.is_slot_awaiting_diagnosis(slot):
					_action_tick_accum += delta
					if _action_tick_accum >= 0.18:
						_action_tick_accum = 0.0
						SfxManager.play("click", -12.0, 1.35)
						GameState.request_repair_slot(eid, sidx, 0.16)
					return

	_action_tick_accum = 0.0


## Buchse, an der das gezogene Kabel beginnt (-1 = Anschluss hat nur einen Steckpunkt).
var cable_start_slot: int = -1


## Freie Buchse am Anschluss, die dem Fadenkreuz am nächsten liegt. -1 = nur ein Steckpunkt oder alles belegt.
func _aimed_socket_idx(cable_type: String, eid: String) -> int:
	if eid == "" or _world == null or _camera == null or not _world.has_method("get_socket_positions"):
		return -1
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
			if eid == GameState.WALL_BREAKER_ID or eid == GameState.HALL_C_BREAKER_ID or GameState.racks.has(eid) or (GameState.coolers.has(eid) and not GameState.is_indoor_unit(eid)) or GameState.ups_units.has(eid):
				return eid
	elif cable_type == "cluster":
		if (itype == "cluster_port" or itype == "rack_slot") and GameState.racks.has(eid):
			return eid
	else:
		if itype == "wall_router":
			return eid
		if itype == "net_port" or itype == "rack_slot":
			if eid == GameState.WALL_ROUTER_ID or eid == GameState.HALL_C_ROUTER_ID or GameState.racks.has(eid):
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


func _update_placement_preview() -> void:
	if _ghost_root == null or not _ghost_root.is_inside_tree():
		return
	var item_type := ""
	var ignore_rid := ""
	if relocating_rack_id != "" and GameState.racks.has(relocating_rack_id):
		item_type = str(GameState.racks[relocating_rack_id].get("rack_type", "rack"))
		ignore_rid = relocating_rack_id
	else:
		var held := GameState.get_player_held_crate(peer_id)
		if held.is_empty():
			_ghost_root.visible = false
			return
		item_type = str(held["item_type"])
		if str(GameState.ITEM_CATALOG[item_type]["category"]) != "placeable":
			_ghost_root.visible = false
			return

	var space := get_world_3d().direct_space_state
	var origin := _camera.global_position
	var end := origin + (-_camera.global_transform.basis.z) * PLACE_RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_ghost_root.visible = false
		return

	var hpos: Vector3 = hit["position"]
	var hnormal: Vector3 = hit["normal"]
	if item_type == GameState.INDOOR_UNIT_TYPE:
		# Innengeräte rasten an der Innenwand ein, auf die man schaut
		var spot: Dictionary = GameState.get_wall_mount_spot(hpos, hnormal)
		if spot.is_empty():
			if absf(hnormal.y) > 0.3:
				_ghost_root.visible = false
				return
			_ghost_pos = hpos + hnormal * GameState.WALL_UNIT_OFFSET
			_ghost_rot_y = atan2(hnormal.x, hnormal.z)
			_ghost_valid = false
		else:
			_ghost_pos = spot["pos"]
			_ghost_rot_y = float(spot["rot_y"])
			_ghost_valid = true
	else:
		if hnormal.y < 0.7:
			_ghost_root.visible = false
			return
		_ghost_pos = Vector3(roundf(hpos.x * 2.0) * 0.5, 0.0, roundf(hpos.z * 2.0) * 0.5)
		# Außengeräte zeigen immer mit dem Lüfter zur Straße
		_ghost_rot_y = 0.0 if GameState.is_heat_pump_type(item_type) else place_rot_y
		_ghost_valid = GameState.can_place_item_at(item_type, _ghost_pos, _ghost_rot_y, ignore_rid)
	_ghost_root.visible = true
	_ghost_root.position = _ghost_pos
	_ghost_root.rotation.y = _ghost_rot_y

	var bm := _ghost_mesh.mesh as BoxMesh
	if item_type == "rack_pro":
		bm.size = Vector3(0.92, 2.48, 0.92)
		_ghost_mesh.position = Vector3(0.0, 1.24, 0.0)
		_ghost_front_strip.position = Vector3(0.0, 1.24, 0.47)
	elif item_type == "rack":
		bm.size = Vector3(0.92, 2.12, 0.92)
		_ghost_mesh.position = Vector3(0.0, 1.06, 0.0)
		_ghost_front_strip.position = Vector3(0.0, 1.06, 0.47)
	elif item_type == "chiller":
		bm.size = Vector3(1.14, 1.50, 0.52)
		_ghost_mesh.position = Vector3(0.0, 0.75, 0.0)
		_ghost_front_strip.position = Vector3(0.0, 0.75, 0.27)
	elif item_type == "cooler":
		bm.size = Vector3(1.04, 0.98, 0.48)
		_ghost_mesh.position = Vector3(0.0, 0.49, 0.0)
		_ghost_front_strip.position = Vector3(0.0, 0.49, 0.25)
	elif item_type == GameState.INDOOR_UNIT_TYPE:
		bm.size = Vector3(0.96, 0.30, 0.22)
		_ghost_mesh.position = Vector3.ZERO
		_ghost_front_strip.position = Vector3(0.0, 0.0, 0.12)
	else:
		bm.size = Vector3(0.74, 1.32, 0.60)
		_ghost_mesh.position = Vector3(0.0, 0.66, 0.0)
		_ghost_front_strip.position = Vector3(0.0, 0.66, 0.31)

	if _ghost_valid:
		_ghost_mat.albedo_color = Color(0.18, 0.92, 0.44, 0.42)
		_ghost_mat.emission = Color(0.14, 0.85, 0.38)
	else:
		_ghost_mat.albedo_color = Color(0.96, 0.22, 0.20, 0.46)
		_ghost_mat.emission = Color(0.92, 0.16, 0.16)


func _update_cable_preview() -> void:
	if _world == null or not _world.has_method("update_cable_preview"):
		return
	if cable_start_id == "" or cable_active_type == "":
		_world.update_cable_preview(false, "power", Vector3.ZERO, Vector3.ZERO)
		return
	var start_pos: Variant = _world.get_port_world_pos(cable_active_type, cable_start_id)
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
	if GameState.count_cables_on(cable_active_type, cable_start_id) >= GameState.get_max_ports(cable_active_type, cable_start_id):
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


## Zieht das zuletzt gesteckte Kabel an diesem Port ab (wie der Server) und nimmt das freie Ende in die Hand.
func _unplug_into_hand(cable_type: String, endpoint_id: String) -> void:
	var other := ""
	for cid in GameState.cables.keys():
		var c: Dictionary = GameState.cables[cid]
		if str(c.get("cable_type", "")) != cable_type:
			continue
		var a := str(c.get("from_id", ""))
		var b := str(c.get("to_id", ""))
		if a == endpoint_id:
			other = b
		elif b == endpoint_id:
			other = a
	GameState.request_disconnect_cables_on(cable_type, endpoint_id)
	if other != "":
		cable_start_id = other
		cable_active_type = cable_type


func _cable_label(cable_type: String) -> String:
	match cable_type:
		"power":
			return tr("Stromkabel (Gelb)")
		"cluster":
			return tr("Cluster-Kabel (Lila)")
		_:
			return tr("Netzwerkkabel (Blau)")


func _update_context_prompt() -> void:
	current_prompt = ""
	current_sub_prompt = ""

	# Active 1-Hand Pulled Cable Prompt!
	if cable_start_id != "" and cable_active_type != "":
		var label := _cable_label(cable_active_type)
		var endpoint := _resolve_aimed_cable_endpoint(cable_active_type)
		if endpoint != "":
			if cable_start_id == endpoint:
				current_prompt = tr("[E / Rechtsklick] %s abbrechen") % label
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
			current_prompt = tr("[Klick / E] %s hier neu aufstellen") % GameState.get_rack_display_name(relocating_rack_id)
		else:
			current_prompt = tr("Neuen freien Bodenplatz für %s wählen") % GameState.get_rack_display_name(relocating_rack_id)
		current_sub_prompt = tr("[R] Drehen  •  [Q / Rechtsklick] Abbrechen (Alle Server bleiben erhalten)")
		return

	var held := GameState.get_player_held_crate(peer_id)
	if not held.is_empty():
		var item_type := str(held["item_type"])
		var cat: Dictionary = GameState.ITEM_CATALOG[item_type]
		if str(cat["category"]) == "placeable" and _ghost_root != null and _ghost_root.visible:
			if _ghost_valid:
				current_prompt = tr("[Klick / E] %s hier platzieren") % tr(str(cat["name"]))
			elif item_type == GameState.INDOOR_UNIT_TYPE:
				current_prompt = tr("Hier geht es nicht – auf eine freie Innenwand zielen (nicht über dem Garagentor)")
			elif GameState.is_heat_pump_type(item_type):
				current_prompt = tr("Hier geht es nicht – nur auf dem Rasen rechts vom Garagentor aufstellen")
			else:
				current_prompt = tr("Platz blockiert – freien Bereich in der Garage wählen")
			if item_type == GameState.INDOOR_UNIT_TYPE or GameState.is_heat_pump_type(item_type):
				current_sub_prompt = tr("[Q] Karton ablegen")
			else:
				current_sub_prompt = tr("[R] Drehen  •  [Q] Karton ablegen")
			return

	var target := _get_aimed_interactable()
	if target == null:
		var pc := GameState.get_player_pushed_cart(peer_id)
		if not pc.is_empty():
			var cnt := (pc.get("items", []) as Array).size()
			current_sub_prompt = tr("Schiebt Rollwagen (%d/%d Kartons)  •  Auf Karton [E] zum Aufladen  •  [Q] Loslassen") % [cnt, GameState.CART_MAX_ITEMS]
		elif GameState.is_player_holding_extinguisher(peer_id):
			current_sub_prompt = tr("Feuerlöscher bereit – auf brennenden Server zielen + [Klick halten]  •  [Q] Zurückhängen")
		elif not held.is_empty():
			var h_name := str(GameState.ITEM_CATALOG[str(held["item_type"])]["name"])
			current_sub_prompt = tr("Trägt: %s  •  [Q] Ablegen") % tr(h_name)
		return

	var itype := str(target.get_meta("interact_type"))
	var eid := str(target.get_meta("entity_id"))
	match itype:
		"terminal":
			current_prompt = tr("[E] Windows Server-PC öffnen (Shop, Verträge, Router, Upgrades)")
			if PcScreenState.is_occupied_by_other():
				current_prompt = tr("PC besetzt: %s sitzt gerade davor") % PcScreenState.user_name
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
			current_prompt = tr("[E] Verlängerungskabel ziehen (%s • %d/%d Steckdosen)") % [eid.to_upper(), used_p, max_p]
			if used_p > 0:
				current_sub_prompt = tr("[Rechtsklick] Letztes Stromkabel hier abziehen")
		"net_port":
			var used_np := GameState.count_cables_on("network", eid)
			var max_np := GameState.get_max_ports("network", eid)
			current_prompt = tr("[E] Blaues Netzwerkkabel ziehen (%s • %d/%d Ports)") % [eid.to_upper(), used_np, max_np]
			if used_np > 0:
				current_sub_prompt = tr("[Rechtsklick] Letztes Netzwerkkabel hier abziehen")
		"cluster_port":
			var used_cp := GameState.count_cables_on("cluster", eid)
			var max_cp := GameState.get_max_ports("cluster", eid)
			current_prompt = tr("[E] Lila Cluster-Kabel ziehen (%s • %d/%d Ports)") % [eid.to_upper(), used_cp, max_cp]
			if used_cp > 0:
				current_sub_prompt = tr("[Rechtsklick] Letztes Cluster-Kabel hier abziehen")
			else:
				current_sub_prompt = tr("Verbundene Racks leihen sich bei Engpässen freie Hardware")
		"extinguisher_station":
			if GameState.is_player_holding_extinguisher(peer_id):
				current_prompt = tr("[E] Feuerlöscher zurückhängen")
			elif GameState.extinguisher_held_by == 0 and not GameState.is_player_holding_anything(peer_id):
				current_prompt = tr("[E] Feuerlöscher nehmen")
			else:
				current_prompt = tr("Feuerlöscher wird gerade benutzt")
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
				var ct := str(GameState.crates[eid]["item_type"])
				var cname := tr(str(GameState.ITEM_CATALOG[ct]["name"]))
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
				if ctype == GameState.INDOOR_UNIT_TYPE:
					current_sub_prompt = tr("Kein Kabel nötig: läuft, sobald ein Goldis-Außengerät Strom hat")
				else:
					current_sub_prompt = tr("Auf die gelbe Buchse an der rechten Seite zielen für Stromkabel")
		"ups_unit":
			if GameState.ups_units.has(eid):
				var ch := float(GameState.ups_units[eid]["charge"])
				current_prompt = tr("[E / F] USV-Batterie %s (%.0f%%) — Umsetzen / Verkaufen") % [eid.to_upper(), ch]
				current_sub_prompt = tr("Auf gelbe Buchse oben zielen für Stromkabel")
		"rack_slot":
			var sidx := int(target.get_meta("slot_index"))
			if GameState.racks.has(eid):
				var slot: Dictionary = GameState.racks[eid]["slots"][sidx]
				var st_item := str(slot["item_type"])
				var st_state := str(slot["state"])
				if st_state == "burning":
					if GameState.is_player_holding_extinguisher(peer_id):
						current_prompt = tr("[Klick / E HALTEN] Brand in %s Slot %d löschen!") % [eid.to_upper(), sidx + 1]
					else:
						current_prompt = tr("SERVER BRENNT! Feuerlöscher an der Nordwand holen!")
				elif st_state == "crashed" and GameState.is_slot_awaiting_diagnosis(slot):
					current_prompt = tr("%s Slot %d: Defekt unbekannt") % [eid.to_upper(), sidx + 1]
					current_sub_prompt = tr("[F] Rack-Menü öffnen und in der 3D-Vorschau das defekte Teil suchen")
				elif st_state == "crashed":
					current_prompt = tr("[E HALTEN] %s Slot %d reparieren (%.0f%%)") % [eid.to_upper(), sidx + 1, float(slot["repair_progress"]) * 100.0]
					current_sub_prompt = tr("[F] Interaktives Rack-Menü öffnen")
				elif st_item == "":
					if not held.is_empty() and str(GameState.ITEM_CATALOG[str(held["item_type"])]["category"]) == "module":
						current_prompt = tr("[E] %s in %s Slot %d einschieben") % [
							str(GameState.ITEM_CATALOG[str(held["item_type"])]["name"]), eid.to_upper(), sidx + 1
						]
					else:
						current_prompt = tr("[E / F] %s Übersicht & Hardware-Overlay (Slot %d frei)") % [eid.to_upper(), sidx + 1]
				else:
					var m_name := str(GameState.ITEM_CATALOG[st_item]["name"])
					current_prompt = tr("[E / F] %s Overlay: %s — Strom, Kapazität & Upgrades") % [eid.to_upper(), m_name]
					if not GameState.is_player_holding_anything(peer_id):
						current_sub_prompt = tr("[Rechtsklick] Server ausbauen  •  [E / F] 3D-Hardware & Rack-Daten")


func _update_held_visuals() -> void:
	if _held_root == null:
		return
	var held_ext := GameState.is_player_holding_extinguisher(peer_id)
	var held_crate := GameState.get_player_held_crate(peer_id)

	_held_extinguisher.visible = held_ext
	if _fp_hand != null:
		_fp_hand.visible = held_ext or not held_crate.is_empty() or not str(cable_active_type).is_empty()
		_fp_hand.position = FP_HAND_EXT_POS if held_ext else FP_HAND_ITEM_POS
	if not held_crate.is_empty():
		var item_type := str(held_crate["item_type"])
		_held_item_holder.visible = true
		if _held_item_type_cached != item_type:
			for c in _held_item_holder.get_children():
				c.queue_free()
			var model := HardwareMeshFactory.build_item_visual(item_type)
			model.position = Vector3(0.0, -0.06, 0.0)
			_held_item_holder.add_child(model)
			_held_item_type_cached = item_type
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

	var jacket_mat := _mat(avatar_color, 0.45, 0.12)
	var pants_mat := _mat(skin_pants_color, 0.72, 0.05)
	var pack_mat := _mat(Color(0.24, 0.27, 0.32), 0.55, 0.25)
	var skin_mat := _mat(skin_tone_color, 0.65, 0.0)
	var belt_mat := _mat(Color(0.12, 0.13, 0.15), 0.5, 0.3)

	# Spielermodell aus assets/models/player.glb (tools/blender/build_player.py), sonst Box-Avatar.
	if _build_model_avatar({"DCT_Jacket": jacket_mat, "DCT_Pants": pants_mat, "DCT_Skin": skin_mat}):
		_add_nametag()
		return

	# Articulated Left & Right Legs (pivoted at hip Y = 0.68)
	_left_leg = Node3D.new()
	_left_leg.position = Vector3(-0.14, 0.68, 0.0)
	_avatar_root.add_child(_left_leg)
	_add_box(_left_leg, Vector3(0.0, -0.32, 0.0), Vector3(0.17, 0.62, 0.19), pants_mat)
	_add_box(_left_leg, Vector3(0.0, -0.63, -0.04), Vector3(0.18, 0.10, 0.26), belt_mat)

	_right_leg = Node3D.new()
	_right_leg.position = Vector3(0.14, 0.68, 0.0)
	_avatar_root.add_child(_right_leg)
	_add_box(_right_leg, Vector3(0.0, -0.32, 0.0), Vector3(0.17, 0.62, 0.19), pants_mat)
	_add_box(_right_leg, Vector3(0.0, -0.63, -0.04), Vector3(0.18, 0.10, 0.26), belt_mat)

	# Torso Tech Jacket + Toolbelt + Tech Backpack
	_add_box(_avatar_root, Vector3(0.0, 1.02, 0.0), Vector3(0.46, 0.62, 0.26), jacket_mat)
	_add_box(_avatar_root, Vector3(0.0, 0.74, 0.0), Vector3(0.48, 0.09, 0.28), belt_mat)
	_add_box(_avatar_root, Vector3(0.0, 1.04, 0.18), Vector3(0.32, 0.42, 0.15), pack_mat)

	# Articulated Left & Right Arms (pivoted at shoulder Y = 1.24)
	_left_arm = Node3D.new()
	_left_arm.position = Vector3(-0.31, 1.24, 0.0)
	_avatar_root.add_child(_left_arm)
	_add_box(_left_arm, Vector3(0.0, -0.24, 0.0), Vector3(0.14, 0.50, 0.15), jacket_mat)
	_add_box(_left_arm, Vector3(0.0, -0.52, 0.0), Vector3(0.11, 0.11, 0.12), skin_mat)

	_right_arm = Node3D.new()
	_right_arm.position = Vector3(0.31, 1.24, 0.0)
	_avatar_root.add_child(_right_arm)
	_add_box(_right_arm, Vector3(0.0, -0.24, 0.0), Vector3(0.14, 0.50, 0.15), jacket_mat)
	_add_box(_right_arm, Vector3(0.0, -0.52, 0.0), Vector3(0.11, 0.11, 0.12), skin_mat)

	# Head + Work Cap + Realistic Safety Glasses (no neon AR visor!)
	_avatar_head = Node3D.new()
	_avatar_head.position = Vector3(0.0, 1.50, 0.0)
	_avatar_root.add_child(_avatar_head)
	_add_box(_avatar_head, Vector3.ZERO, Vector3(0.34, 0.34, 0.34), skin_mat)
	# Work cap & visor brim
	_add_box(_avatar_head, Vector3(0.0, 0.15, 0.01), Vector3(0.37, 0.12, 0.37), jacket_mat)
	_add_box(_avatar_head, Vector3(0.0, 0.10, -0.22), Vector3(0.34, 0.03, 0.14), jacket_mat)
	# Matte dark-tinted safety glasses
	var glass_mat := _mat(Color(0.14, 0.16, 0.18), 0.18, 0.35)
	_add_box(_avatar_head, Vector3(0.0, 0.02, -0.175), Vector3(0.28, 0.08, 0.04), glass_mat)

	_add_nametag()


func _add_nametag() -> void:
	_nametag = Label3D.new()
	_nametag.text = player_name
	_nametag.font_size = 30
	_nametag.pixel_size = 0.0048
	_nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nametag.position = Vector3(0.0, 2.04, 0.0)
	_nametag.modulate = Color(0.95, 0.95, 0.95)
	add_child(_nametag)


## Lädt player.glb und übernimmt dessen Gelenke für _animate_remote_avatar().
## Gibt false zurück, wenn das Modell fehlt oder ein Gelenk nicht gefunden wird.
func _build_model_avatar(tint_mats: Dictionary) -> bool:
	if not ModelLoader.has_custom_model(AVATAR_MODEL_ID):
		return false
	var model := ModelLoader.instantiate_custom_model(AVATAR_MODEL_ID)
	if model == null:
		return false
	var left_leg := model.find_child("Pivot_LegL", true, false) as Node3D
	var right_leg := model.find_child("Pivot_LegR", true, false) as Node3D
	var left_arm := model.find_child("Pivot_ArmL", true, false) as Node3D
	var right_arm := model.find_child("Pivot_ArmR", true, false) as Node3D
	var head := model.find_child("Pivot_Head", true, false) as Node3D
	if left_leg == null or right_leg == null or left_arm == null or right_arm == null or head == null:
		push_warning("player.glb: Gelenke Pivot_* fehlen, nutze Box-Avatar.")
		model.free()
		return false
	_avatar_root.add_child(model)
	_left_leg = left_leg
	_right_leg = right_leg
	_left_arm = left_arm
	_right_arm = right_arm
	_avatar_head = head
	_tint_avatar(model, tint_mats)
	return true


## Ersetzt die Blender-Materialien (DCT_Jacket, DCT_Pants, DCT_Skin) durch die Skin-Materialien.
func _tint_avatar(node: Node, tint_mats: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m != null and tint_mats.has(m.resource_name):
					mi.set_surface_override_material(i, tint_mats[m.resource_name] as Material)
	for child in node.get_children():
		_tint_avatar(child, tint_mats)


## Ich-Perspektive: Hand und Unterarm im Jackenstoff, Maße wie beim Box-Avatar.
## Hängt an _held_root und ist nur sichtbar, solange der aktive Slot etwas enthält.
func _build_fp_hand() -> void:
	_fp_hand = Node3D.new()
	_fp_hand.visible = false
	_fp_hand.position = FP_HAND_ITEM_POS
	_held_root.add_child(_fp_hand)

	var sleeve_mat := _mat(avatar_color, 0.45, 0.12)
	var skin_mat := _mat(skin_tone_color, 0.65, 0.0)
	_add_box(_fp_hand, Vector3.ZERO, Vector3(0.11, 0.09, 0.13), skin_mat)

	# Unterarm läuft von der Hand nach hinten, leicht nach unten und nach rechts aus dem Bild.
	var forearm := Node3D.new()
	forearm.position = Vector3(0.02, -0.02, 0.06)
	forearm.rotation_degrees = Vector3(18.0, 8.0, 0.0)
	_fp_hand.add_child(forearm)
	_add_box(forearm, Vector3(0.0, 0.0, 0.20), Vector3(0.13, 0.13, 0.40), sleeve_mat)


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


func _build_placement_ghost() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.visible = false
	if _world != null:
		_world.add_child.call_deferred(_ghost_root)
	else:
		get_parent().add_child.call_deferred(_ghost_root)

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.18, 0.92, 0.44, 0.42)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.emission_enabled = true
	_ghost_mat.emission = Color(0.14, 0.85, 0.38)
	_ghost_mat.emission_energy_multiplier = 0.9

	_ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.92, 2.12, 0.92)
	_ghost_mesh.mesh = bm
	_ghost_mesh.material_override = _ghost_mat
	_ghost_root.add_child(_ghost_mesh)

	_ghost_front_strip = MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(0.65, 0.18, 0.04)
	_ghost_front_strip.mesh = fbm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 1.0, 1.0)
	fmat.emission_energy_multiplier = 2.0
	_ghost_front_strip.material_override = fmat
	_ghost_root.add_child(_ghost_front_strip)


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
