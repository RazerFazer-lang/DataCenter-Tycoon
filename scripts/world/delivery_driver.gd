extends Node3D
## Fahrer des CLOUD-EXPRESS-Lieferwagens (rein visuell, keine Kollision).
## Folgt den Abladeschritten, die GameState synchronisiert (exit, load, walk_in, drop, walk_back, enter):
## steigt aus, holt die Kartons an der Schiebetür, trägt einen einzelnen Karton in den Armen
## oder schiebt mehrere auf der Sackkarre zur Lieferzone, zieht die leere Karre zurück,
## verstaut sie im Laderaum und steigt wieder ein.
## Alle Positionen sind lokal zum DeliveryVan (Fahrtrichtung +X, Garage auf -Z).

const HandTruckScript := preload("res://scripts/world/hand_truck.gd")
const REALISTIC_DRIVER_MODEL_ID := "delivery_driver_realistic"
const RigHelper := preload("res://scripts/world/humanoid_rig_helper.gd")

enum TruckMode { HIDDEN, PARKED, PUSHED, PULLED, STOWED }

const SEAT_POS := Vector3(1.53, 0.45, -0.46)
const DOOR_OUT_POS := Vector3(1.66, 0.0, -1.55)
const CARGO_POS := Vector3(-0.10, 0.0, -1.50)
const TRUCK_PARK_OFFSET := Vector3(0.72, 0.0, -0.12) # Karre steht neben dem Fahrer an der Schiebetür
const TRUCK_STOW_POS := Vector3(-0.30, 0.67, -0.70) # auf dem Laderaumboden hinter der Schiebetür
const TRUCK_PUSH_DIST := 1.2
const TRUCK_PULL_OFFSET := Vector3(0.06, 0.0, 1.0)
const TRUCK_PUSH_TILT := 0.61 # etwa 35°
const TRUCK_PULL_TILT := 0.79 # etwa 45°
const VAN_STOP_FALLBACK := Vector3(0.2, 0.0, 12.4)
const SEATED_SCALE := 0.88
const STANDING_SCALE := 0.96
const CAB_EXIT_TIME := 0.9
const CAB_ENTER_TIME := 0.9
const STOW_TIME := 0.6
const WALK_CYCLE_RATE := 7.0
const YAW_DRIVE := -PI / 2.0
const YAW_OUT := 0.0
const YAW_TO_VAN := PI

# Indizes im Posen-Array
const J_THIGH_L := 0
const J_THIGH_R := 1
const J_KNEE_L := 2
const J_KNEE_R := 3
const J_SHOULDER_L := 4
const J_SHOULDER_R := 5
const J_SHOULDER_L_Z := 6
const J_SHOULDER_R_Z := 7
const J_ELBOW_L := 8
const J_ELBOW_R := 9
const J_TORSO := 10
const J_HEAD := 11
const J_CROUCH := 12 # 0 = stehend, 1 = in der Hocke (Becken tiefer, Füße bleiben stehen)
const J_COUNT := 13

var _anim_t: float = 0.0
var _walk_cycle: float = 0.0
var _trip_t: float = 0.0
var _trip_step: int = -1
var _step: String = ""
var _truck_out: bool = false
var _crouch: float = 0.0

# Mehr-Personal-Konfiguration fuer Liefer-Stufen 1 (1 Fahrer), 2 (2 Mitarbeiter) & 3 (3 Logistiker)
var _role_idx: int = 0
var _vehicle_tier: int = 1
var _seat_pos: Vector3 = SEAT_POS
var _door_out_pos: Vector3 = DOOR_OUT_POS
var _cargo_pos: Vector3 = CARGO_POS
var _target_offset: Vector3 = Vector3.ZERO
var _time_lag: float = 0.0
var _stow_pos: Vector3 = TRUCK_STOW_POS

# Ergebnis der aktuellen Frame-Berechnung
var _o_pos: Vector3 = SEAT_POS
var _o_yaw: float = YAW_DRIVE
var _o_scale: float = SEATED_SCALE
var _o_pose: PackedFloat32Array = PackedFloat32Array()

var _truck: HandTruckScript = null

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _thigh_l: Node3D
var _thigh_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _held_box: MeshInstance3D
var _skel: Skeleton3D = null
var _skel_bones: Dictionary = {}
var _skel_cur: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_ensure_built()


## Der Wagen übergibt die Sackkarre (ein Geschwister-Node im Wagen).
func set_hand_truck(truck: HandTruckScript) -> void:
	_truck = truck
	if _truck != null:
		_truck.visible = false


## Konfiguriert Rolle & Positionen fuer Liefer-Stufe 1 (Sprinter), 2 (7,5t Kastenwagen) oder 3 (18t LKW).
func configure_worker(role_idx: int, tier: int) -> void:
	_role_idx = maxi(0, role_idx)
	_vehicle_tier = clampi(tier, 1, 3)
	_time_lag = float(_role_idx) * 0.24
	if _vehicle_tier == 1:
		_seat_pos = SEAT_POS
		_door_out_pos = DOOR_OUT_POS
		_cargo_pos = CARGO_POS
		_target_offset = Vector3.ZERO
		_stow_pos = TRUCK_STOW_POS
	elif _vehicle_tier == 2:
		# 7,5t Kastenwagen mit Ausklapp-Rampe & 2 Mitarbeitern (Fahrer + Beifahrer)
		if _role_idx == 0:
			_seat_pos = Vector3(2.35, 0.78, -0.54)
			_door_out_pos = Vector3(2.45, 0.0, -1.78)
			_cargo_pos = Vector3(0.35, 0.0, -2.55)
			_target_offset = Vector3(0.72, 0.0, 0.0)
			_stow_pos = Vector3(0.20, 0.86, -0.82)
		else:
			_seat_pos = Vector3(2.35, 0.78, 0.54)
			_door_out_pos = Vector3(1.85, 0.0, -1.90)
			_cargo_pos = Vector3(-0.78, 0.0, -2.55)
			_target_offset = Vector3(-0.72, 0.0, 0.14)
			_stow_pos = Vector3(-0.75, 0.86, -0.82)
	else:
		# 18t Schwerlast-LKW mit Hydraulik-Ladebordwand & 3 Logistikern gleichzeitig!
		if _role_idx == 0:
			_seat_pos = Vector3(3.12, 1.05, -0.64)
			_door_out_pos = Vector3(3.18, 0.0, -1.88)
			_cargo_pos = Vector3(0.45, 0.0, -2.72)
			_target_offset = Vector3(1.08, 0.0, -0.08)
			_stow_pos = Vector3(0.35, 1.08, -0.92)
		elif _role_idx == 1:
			_seat_pos = Vector3(3.12, 1.05, 0.0)
			_door_out_pos = Vector3(2.45, 0.0, -1.98)
			_cargo_pos = Vector3(-0.45, 0.0, -2.72)
			_target_offset = Vector3(0.0, 0.0, 0.16)
			_stow_pos = Vector3(-0.45, 1.08, -0.92)
		else:
			_seat_pos = Vector3(3.12, 1.05, 0.64)
			_door_out_pos = Vector3(1.80, 0.0, -2.08)
			_cargo_pos = Vector3(-1.35, 0.0, -2.72)
			_target_offset = Vector3(-1.08, 0.0, -0.04)
			_stow_pos = Vector3(-1.25, 1.08, -0.92)
	reset_to_seat()


## Setzt den Fahrer sofort auf den Fahrersitz (z. B. wenn der Wagen unsichtbar ist).
func reset_to_seat() -> void:
	_ensure_built()
	_step = ""
	_truck_out = false
	_held_box.visible = false
	_o_pos = _seat_pos
	_o_yaw = YAW_DRIVE
	_o_scale = SEATED_SCALE
	_apply_transform(_seat_pos, YAW_DRIVE, SEATED_SCALE)
	_apply_pose(_pose_seated(), 0.0, true)
	_update_truck(TruckMode.HIDDEN, 0.0, 0.0, 0, 0.0)


## Wird jeden Frame vom DeliveryVan aufgerufen.
func update_driver(delta: float, phase: String, _unload_t: float, _cargo_count: int) -> void:
	_ensure_built()
	_anim_t += delta
	_sync_trip_clock(delta)
	var step: String = GameState.van_trip_phase if phase == "unloading" else ""
	_step = step
	var dur: float = maxf(GameState.van_trip_duration, 0.1)
	var t := maxf(0.0, _trip_t - _time_lag)
	var staff_n := 1 if _vehicle_tier == 1 else (2 if _vehicle_tier == 2 else 3)
	var total_n: int = maxi(0, GameState.van_trip_count)
	var n: int = clampi(ceili(float(total_n) / float(staff_n)), 0, HandTruckScript.MAX_CRATES)
	if total_n > 0 and _role_idx >= total_n:
		n = 0
	var with_truck: bool = GameState.van_trip_kind == "truck"
	var turn: float = GameState.VAN_DRIVER_TURN_TIME
	var target := _to_van_local(GameState.van_trip_target) + _target_offset

	_o_pos = _seat_pos
	_o_yaw = YAW_DRIVE
	_o_scale = SEATED_SCALE
	_o_pose = _pose_seated()
	var show_box := false
	var truck_mode: int = TruckMode.PARKED if _truck_out else TruckMode.HIDDEN
	var truck_blend := 0.0
	var truck_tilt := 0.0
	var truck_crates := 0
	var stow_u := 0.0

	match step:
		"exit":
			_truck_out = false
			truck_mode = TruckMode.HIDDEN
			if t < CAB_EXIT_TIME:
				var u := clampf((t - 0.2) / (CAB_EXIT_TIME - 0.2), 0.0, 1.0)
				var su := smoothstep(0.0, 1.0, u)
				_o_pos = _cab_path(u)
				_o_yaw = lerp_angle(YAW_DRIVE, YAW_OUT, su)
				_o_scale = lerpf(SEATED_SCALE, STANDING_SCALE, u)
				_o_pose = _blend(_pose_seated(), _pose_standing(), su)
			else:
				var walk_d := maxf(dur - CAB_EXIT_TIME - 0.1, 0.3)
				var u := clampf((t - CAB_EXIT_TIME) / walk_d, 0.0, 1.0)
				var tu := clampf((t - CAB_EXIT_TIME) / 0.3, 0.0, 1.0)
				_set_walk(_door_out_pos, _cargo_pos, u, tu, YAW_OUT, YAW_TO_VAN, PackedFloat32Array(), delta)

		"load":
			_o_pos = _cargo_pos
			_o_yaw = YAW_TO_VAN
			_o_scale = STANDING_SCALE
			if n <= 0:
				_o_pose = _pose_standing()
				truck_mode = TruckMode.HIDDEN
			elif with_truck:
				var spd := 1.0 if _vehicle_tier == 1 else (1.30 if _vehicle_tier == 2 else 1.55)
				var fetch: float = GameState.VAN_TRUCK_FETCH_TIME / spd
				var per: float = GameState.VAN_LOAD_TIME_PER_CRATE / spd
				if t < fetch:
					# Sackkarre aus dem Laderaum nehmen
					_o_pose = _pose_reach(sin(PI * t / fetch) * 2.0 - 1.0)
					if t >= fetch * 0.55:
						_truck_out = true
				else:
					_truck_out = true
					var local_t := t - fetch
					var i := floori(local_t / per)
					truck_crates = clampi(floori(local_t / per + 0.28), 0, n)
					if i < n:
						# Karton greifen, zur Karre drehen, auf die Schaufel stellen
						var f := fmod(local_t, per) / per
						var turn_w := sin(PI * clampf((f - 0.3) / 0.5, 0.0, 1.0))
						_o_yaw = lerp_angle(YAW_TO_VAN, _yaw_for(TRUCK_PARK_OFFSET), turn_w * 0.8)
						_o_pose = _pose_reach(cos(TAU * (f - 0.2)))
						show_box = f > 0.35 and f < 0.72
					else:
						_o_pose = _pose_truck_upright()
				truck_mode = TruckMode.PARKED
			else:
				var u := clampf(t / dur, 0.0, 1.0)
				var reach_in := smoothstep(0.0, 1.0, clampf(u / 0.35, 0.0, 1.0))
				var pull_out := smoothstep(0.0, 1.0, clampf((u - 0.45) / 0.45, 0.0, 1.0))
				_o_pose = _blend(_pose_reach(reach_in * 2.0 - 1.0), _pose_carry(), pull_out)
				show_box = u > 0.42

		"walk_in":
			if n <= 0:
				_o_pos = _cargo_pos
				_o_yaw = YAW_OUT
				_o_scale = STANDING_SCALE
				_o_pose = _pose_standing()
				truck_mode = TruckMode.HIDDEN
			else:
				var walk_d := maxf(dur - turn, 0.1)
				var u := clampf((t - turn) / walk_d, 0.0, 1.0)
				var tu := clampf(t / turn, 0.0, 1.0)
				var upper := _pose_push() if with_truck else _pose_carry()
				_set_walk(_cargo_pos, target, u, tu, YAW_TO_VAN, YAW_OUT, upper, delta)
				if with_truck:
					_truck_out = true
					truck_mode = TruckMode.PUSHED
					truck_blend = smoothstep(0.0, 1.0, clampf(t / (turn + 0.25), 0.0, 1.0))
					truck_tilt = TRUCK_PUSH_TILT * truck_blend
					truck_crates = n
				else:
					show_box = true

		"drop":
			if n <= 0:
				_o_pos = _cargo_pos
				_o_yaw = YAW_OUT
				_o_scale = STANDING_SCALE
				_o_pose = _pose_standing()
				truck_mode = TruckMode.HIDDEN
			else:
				_o_pos = target
				_o_yaw = YAW_OUT
				_o_scale = STANDING_SCALE
				if with_truck:
					var spd := 1.0 if _vehicle_tier == 1 else (1.30 if _vehicle_tier == 2 else 1.55)
					var tilt_t: float = GameState.VAN_TRUCK_TILT_TIME / spd
					var per: float = GameState.VAN_DROP_TIME_PER_CRATE_TRUCK / spd
					var up := smoothstep(0.0, 1.0, clampf(t / tilt_t, 0.0, 1.0))
					var dropped := 0
					if t >= dur:
						dropped = n
					elif t >= tilt_t:
						dropped = clampi(floori((t - tilt_t) / per), 0, n)
					var tug := 0.0
					if t > tilt_t:
						tug = sin(PI * fmod(t - tilt_t, per) / per)
					_o_pose = _blend(_blend(_pose_push(), _pose_truck_upright(), up), _pose_truck_tug(), tug * 0.6)
					_truck_out = true
					truck_mode = TruckMode.PUSHED
					truck_blend = 1.0
					truck_tilt = TRUCK_PUSH_TILT * (1.0 - up)
					truck_crates = maxi(0, n - dropped)
				else:
					var bend := smoothstep(0.0, 1.0, clampf(t / (dur * 0.75), 0.0, 1.0))
					_o_pose = _blend(_pose_carry(), _pose_drop_hand(), bend)
					show_box = t < dur

		"walk_back":
			if n <= 0:
				_o_pos = _cargo_pos
				_o_yaw = YAW_TO_VAN
				_o_scale = STANDING_SCALE
				_o_pose = _pose_standing()
				truck_mode = TruckMode.HIDDEN
			else:
				var walk_d := maxf(dur - turn, 0.1)
				var u := clampf((t - turn) / walk_d, 0.0, 1.0)
				var tu := clampf(t / turn, 0.0, 1.0)
				if with_truck:
					_set_walk(target, _cargo_pos, u, tu, YAW_OUT, YAW_TO_VAN, _pose_pull(), delta)
					truck_mode = TruckMode.PULLED
					truck_blend = 1.0 - smoothstep(0.0, 1.0, clampf((u - 0.8) / 0.2, 0.0, 1.0))
					truck_tilt = TRUCK_PULL_TILT * smoothstep(0.0, 1.0, tu) * truck_blend
				else:
					_set_walk(target, _cargo_pos, u, tu, YAW_OUT, YAW_TO_VAN, PackedFloat32Array(), delta)
					if t < turn:
						_o_pose = _blend(_pose_drop_hand(), _pose_standing(), smoothstep(0.0, 1.0, tu))

		"enter":
			var walk_end := maxf(dur - CAB_ENTER_TIME, STOW_TIME + 0.3)
			if t < STOW_TIME:
				_o_pos = _cargo_pos
				_o_yaw = YAW_TO_VAN
				_o_scale = STANDING_SCALE
				_o_pose = _pose_reach(sin(PI * t / STOW_TIME) * 2.0 - 1.0)
				if _truck_out:
					stow_u = clampf(t / (STOW_TIME * 0.9), 0.0, 1.0)
					truck_mode = TruckMode.STOWED if stow_u < 1.0 else TruckMode.HIDDEN
			elif t < walk_end:
				_truck_out = false
				truck_mode = TruckMode.HIDDEN
				var u := clampf((t - STOW_TIME) / (walk_end - STOW_TIME), 0.0, 1.0)
				var tu := clampf((t - STOW_TIME) / 0.3, 0.0, 1.0)
				_set_walk(_cargo_pos, _door_out_pos, u, tu, YAW_TO_VAN, YAW_TO_VAN, PackedFloat32Array(), delta)
			else:
				_truck_out = false
				truck_mode = TruckMode.HIDDEN
				var u := clampf((t - walk_end) / (CAB_ENTER_TIME - 0.1), 0.0, 1.0)
				var su := smoothstep(0.0, 1.0, u)
				_o_pos = _cab_path(1.0 - u)
				_o_yaw = lerp_angle(YAW_TO_VAN, YAW_DRIVE, su)
				_o_scale = lerpf(STANDING_SCALE, SEATED_SCALE, u)
				_o_pose = _blend(_pose_standing(), _pose_seated(), su)

		_:
			_truck_out = false
			truck_mode = TruckMode.HIDDEN

	_apply_transform(_o_pos, _o_yaw, _o_scale)
	_apply_pose(_o_pose, delta, false)
	_held_box.visible = show_box
	_update_truck(truck_mode, truck_blend, truck_tilt, truck_crates, stow_u)


## 0 = Fahrertür zu, 1 = offen. Der Wagen animiert die Tür danach.
func get_cab_door_target() -> float:
	match _step:
		"exit":
			return 1.0 if _trip_t < CAB_EXIT_TIME + 0.35 else 0.0
		"enter":
			var walk_end := maxf(GameState.van_trip_duration - CAB_ENTER_TIME, STOW_TIME + 0.3)
			return 1.0 if _trip_t > walk_end - 0.45 else 0.0
	return 0.0


## 1 = Schiebetür offen. Beim Einsteigen zieht der Fahrer sie zu, sobald die Sackkarre verstaut ist.
func get_side_door_target() -> float:
	if _step == "enter" and _trip_t >= STOW_TIME * 0.8:
		return 0.0
	return 1.0


## Kartons der laufenden Fahrt, die der Fahrer noch nicht aus dem Laderaum genommen hat.
## Der Wagen blendet so viele Kartons zusätzlich zu GameState.van_cargo_count ein.
func get_trip_crates_in_van() -> int:
	if _step != "load":
		return 0
	var n: int = clampi(GameState.van_trip_count, 0, HandTruckScript.MAX_CRATES)
	if GameState.van_trip_kind == "truck":
		var fetch: float = GameState.VAN_TRUCK_FETCH_TIME
		if _trip_t < fetch:
			return n
		var per: float = GameState.VAN_LOAD_TIME_PER_CRATE
		return n - clampi(floori((_trip_t - fetch) / per + 0.65), 0, n)
	return n if _trip_t <= GameState.van_trip_duration * 0.42 else 0


func _sync_trip_clock(delta: float) -> void:
	if GameState.van_trip_step != _trip_step:
		_trip_step = GameState.van_trip_step
		_trip_t = GameState.van_trip_time
	else:
		_trip_t += delta


## Rechnet eine Position aus GameState (Weltkoordinaten der Garage) in Wagen-Koordinaten um, Höhe auf dem Boden.
func _to_van_local(world_pos: Vector3) -> Vector3:
	var local := world_pos - VAN_STOP_FALLBACK
	var van := get_parent() as Node3D
	if van != null and van.is_inside_tree():
		local = van.to_local(world_pos)
	local.y = 0.0
	return local


## Laufen von from nach to. turn_u dreht in Laufrichtung, am Ende (u > 0,85) zur Blickrichtung end_yaw.
## upper: Oberkörper-Pose (Tragen, Schieben); leer = normales Armschwingen.
func _set_walk(from: Vector3, to: Vector3, u: float, turn_u: float, start_yaw: float, end_yaw: float, upper: PackedFloat32Array, delta: float) -> void:
	var dir := to - from
	dir.y = 0.0
	var walk_yaw := _yaw_for(dir) if dir.length_squared() > 0.0001 else end_yaw
	var yaw := lerp_angle(start_yaw, walk_yaw, smoothstep(0.0, 1.0, turn_u))
	_o_yaw = lerp_angle(yaw, end_yaw, smoothstep(0.0, 1.0, clampf((u - 0.85) / 0.15, 0.0, 1.0)))
	_o_pos = from.lerp(to, u)
	_o_scale = STANDING_SCALE
	if u < 1.0:
		_walk_cycle = wrapf(_walk_cycle + delta * WALK_CYCLE_RATE, 0.0, TAU)
		var walk := _pose_walk(_walk_cycle)
		_o_pose = walk if upper.is_empty() else _with_legs(upper, walk)
		_o_pos.y += absf(sin(_walk_cycle)) * 0.022
	else:
		_o_pose = _pose_standing() if upper.is_empty() else upper


func _update_truck(mode: int, blend: float, tilt: float, crates: int, stow_u: float) -> void:
	if _truck == null:
		return
	if mode == TruckMode.HIDDEN:
		_truck.visible = false
		_truck.reset_motion()
		return
	_truck.visible = true
	var park_pos := _cargo_pos + TRUCK_PARK_OFFSET
	var pos := park_pos
	var yaw := YAW_OUT
	match mode:
		TruckMode.PUSHED, TruckMode.PULLED:
			var ground := Vector3(_o_pos.x, 0.0, _o_pos.z)
			var att_pos: Vector3
			var att_yaw: float
			if mode == TruckMode.PUSHED:
				att_pos = ground + Vector3(0.0, 0.0, -TRUCK_PUSH_DIST).rotated(Vector3.UP, _o_yaw)
				att_yaw = _o_yaw
			else:
				att_pos = ground + TRUCK_PULL_OFFSET.rotated(Vector3.UP, _o_yaw)
				att_yaw = _o_yaw + PI
			var b := clampf(blend, 0.0, 1.0)
			pos = park_pos.lerp(att_pos, b)
			yaw = lerp_angle(YAW_OUT, att_yaw, b)
		TruckMode.STOWED:
			pos = park_pos.lerp(_stow_pos, smoothstep(0.0, 1.0, stow_u))
			pos.y = _stow_pos.y * smoothstep(0.0, 0.55, stow_u)
	_truck.set_pose(pos, yaw, tilt, crates)


## Weg zwischen Sitz (u = 0) und Platz vor der Fahrertür (u = 1):
## erst seitlich durch die Türöffnung, dann hinunter auf den Boden.
func _cab_path(u: float) -> Vector3:
	var side_u := smoothstep(0.0, 1.0, clampf(u / 0.65, 0.0, 1.0))
	var drop_u := smoothstep(0.0, 1.0, clampf((u - 0.4) / 0.6, 0.0, 1.0))
	return Vector3(
		lerpf(_seat_pos.x, _door_out_pos.x, u),
		lerpf(_seat_pos.y, _door_out_pos.y, drop_u),
		lerpf(_seat_pos.z, _door_out_pos.z, side_u)
	)


func _yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _apply_transform(pos: Vector3, yaw: float, scl: float) -> void:
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	scale = Vector3(scl, scl, scl)


# ---------------------------------------------------------------------------
# Posen: [Oberschenkel L/R, Knie L/R, Schulter L/R, Schulter-Z L/R, Ellbogen L/R, Oberkörper, Kopf, Hocke]
# Oberschenkel/Schulter/Ellbogen positiv = nach vorn, Oberkörper negativ = vorbeugen.
# ---------------------------------------------------------------------------

func _pose_seated() -> PackedFloat32Array:
	var sway := sin(_anim_t * 1.3) * 0.04
	return PackedFloat32Array([1.50, 1.50, -1.45, -1.45, 0.85 + sway, 0.85 - sway, 0.15, -0.15, 0.75, 0.75, 0.12, -0.12, 0.0])


func _pose_standing() -> PackedFloat32Array:
	var breath := sin(_anim_t * 1.6) * 0.015
	return PackedFloat32Array([0.0, 0.0, -0.04, -0.04, 0.05, 0.05, -0.06, 0.06, 0.15, 0.15, breath, 0.0, 0.0])


func _pose_walk(c: float) -> PackedFloat32Array:
	var s := sin(c)
	var k := cos(c)
	return PackedFloat32Array([
		0.5 * s, -0.5 * s,
		-0.05 - 0.7 * maxf(0.0, k), -0.05 - 0.7 * maxf(0.0, -k),
		-0.35 * s, 0.35 * s,
		-0.06, 0.06,
		0.25, 0.25,
		-0.04, 0.02,
		0.0,
	])


func _pose_reach(swing: float) -> PackedFloat32Array:
	var reach := (swing + 1.0) * 0.5 # 0 = zurückgezogen, 1 = in den Laderaum gestreckt
	var sh := lerpf(0.9, 1.4, reach)
	var el := lerpf(0.6, 0.15, reach)
	return PackedFloat32Array([0.22, 0.22, -0.30, -0.30, sh, sh, 0.10, -0.10, el, el, lerpf(-0.10, -0.35, reach), 0.15, 0.0])


## Karton vor der Brust, Oberkörper leicht zurückgelehnt.
func _pose_carry() -> PackedFloat32Array:
	var sway := sin(_anim_t * 2.2) * 0.02
	return PackedFloat32Array([0.0, 0.0, -0.04, -0.04, 0.55 + sway, 0.55 - sway, 0.0, 0.0, 0.95, 0.95, 0.07, 0.10, 0.0])


## In die Hocke gehen und den Karton auf dem Boden absetzen.
func _pose_drop_hand() -> PackedFloat32Array:
	return PackedFloat32Array([1.0, 1.0, -1.5, -1.5, 0.95, 0.95, 0.0, 0.0, 0.7, 0.7, -0.75, 0.3, 1.0])


## Beide Hände an den Griffen der gekippten Sackkarre.
func _pose_push() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, -0.04, -0.04, 0.60, 0.60, 0.0, 0.0, 0.25, 0.25, -0.14, 0.10, 0.0])


## Karre aufgerichtet, Blick auf die Kartons.
func _pose_truck_upright() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, -0.04, -0.04, 0.50, 0.50, 0.0, 0.0, 0.45, 0.45, -0.04, -0.18, 0.0])


## Kurzes Zurückziehen der Karre, damit der Karton von der Schaufel rutscht.
func _pose_truck_tug() -> PackedFloat32Array:
	return PackedFloat32Array([0.12, -0.10, -0.10, -0.04, 0.40, 0.40, 0.0, 0.0, 0.25, 0.25, 0.10, -0.10, 0.0])


## Rechte Hand hinten am Griff der gezogenen Karre.
func _pose_pull() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, -0.04, -0.04, 0.10, -0.20, -0.06, 0.10, 0.20, 0.05, -0.05, 0.0, 0.0])


## Oberkörper aus upper, Beine aus dem Laufzyklus.
static func _with_legs(upper: PackedFloat32Array, legs: PackedFloat32Array) -> PackedFloat32Array:
	var out := upper.duplicate()
	out[J_THIGH_L] = legs[J_THIGH_L]
	out[J_THIGH_R] = legs[J_THIGH_R]
	out[J_KNEE_L] = legs[J_KNEE_L]
	out[J_KNEE_R] = legs[J_KNEE_R]
	return out


static func _blend(a: PackedFloat32Array, b: PackedFloat32Array, u: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(J_COUNT)
	for i in range(J_COUNT):
		out[i] = lerpf(a[i], b[i], u)
	return out


func _apply_pose(pose: PackedFloat32Array, delta: float, snap: bool) -> void:
	var k := 1.0 if snap else clampf(delta * 14.0, 0.0, 1.0)
	if _skel != null:
		if _skel_cur.size() != J_COUNT:
			_skel_cur.resize(J_COUNT)
		for i in range(J_COUNT):
			_skel_cur[i] = lerpf(_skel_cur[i], pose[i], k)
		RigHelper.set_leg_pitch(_skel, _skel_bones, "thigh_l", _skel_cur[J_THIGH_L])
		RigHelper.set_leg_pitch(_skel, _skel_bones, "thigh_r", _skel_cur[J_THIGH_R])
		RigHelper.set_leg_pitch(_skel, _skel_bones, "knee_l", _skel_cur[J_KNEE_L])
		RigHelper.set_leg_pitch(_skel, _skel_bones, "knee_r", _skel_cur[J_KNEE_R])
		RigHelper.set_arm_pose(_skel, _skel_bones, true, _skel_cur[J_SHOULDER_L], -_skel_cur[J_SHOULDER_L_Z])
		RigHelper.set_arm_pose(_skel, _skel_bones, false, _skel_cur[J_SHOULDER_R], _skel_cur[J_SHOULDER_R_Z])
		RigHelper.set_forearm_bend(_skel, _skel_bones, true, _skel_cur[J_ELBOW_L])
		RigHelper.set_forearm_bend(_skel, _skel_bones, false, _skel_cur[J_ELBOW_R])
		RigHelper.set_torso_pitch(_skel, _skel_bones, "spine", -_skel_cur[J_TORSO])
		RigHelper.set_torso_pitch(_skel, _skel_bones, "head", -_skel_cur[J_HEAD])
		_crouch = _skel_cur[J_CROUCH]
		_body.position = Vector3(0.0, -0.26 * _crouch, 0.15 * _crouch)
		return
	_thigh_l.rotation.x = lerpf(_thigh_l.rotation.x, pose[J_THIGH_L], k)
	_thigh_r.rotation.x = lerpf(_thigh_r.rotation.x, pose[J_THIGH_R], k)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, pose[J_KNEE_L], k)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, pose[J_KNEE_R], k)
	_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, pose[J_SHOULDER_L], k)
	_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, pose[J_SHOULDER_R], k)
	_shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, pose[J_SHOULDER_L_Z], k)
	_shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, pose[J_SHOULDER_R_Z], k)
	_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, pose[J_ELBOW_L], k)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, pose[J_ELBOW_R], k)
	_torso.rotation.x = lerpf(_torso.rotation.x, pose[J_TORSO], k)
	_head.rotation.x = lerpf(_head.rotation.x, pose[J_HEAD], k)
	_crouch = lerpf(_crouch, pose[J_CROUCH], k)
	# Beim Hocken sinkt das Becken und rückt nach hinten, damit die Füße am Boden stehen bleiben
	_body.position = Vector3(0.0, -0.26 * _crouch, 0.15 * _crouch)


# ---------------------------------------------------------------------------
# Körper: Ursprung an den Füßen, Blickrichtung -Z, Hüfte auf 0,92 m, Größe etwa 1,78 m mit Mütze
# ---------------------------------------------------------------------------

func _ensure_built() -> void:
	if _body != null:
		return
	_build_body()


func _build_body() -> void:
	var tape_mat := _mat(Color(0.74, 0.62, 0.42), 0.50, 0.0)
	var label_mat := _mat(Color(0.93, 0.93, 0.90), 0.60, 0.0)
	var cardboard: Material = MatLib.get_mat("cardboard")

	var driver_id := REALISTIC_DRIVER_MODEL_ID if ModelLoader.has_custom_model(REALISTIC_DRIVER_MODEL_ID) else "delivery_driver"
	var custom := ModelLoader.instantiate_custom_model(driver_id)
	if custom != null:
		var skel: Skeleton3D = RigHelper.find_skeleton(custom)
		if skel != null:
			_body = Node3D.new()
			add_child(_body)
			_body.add_child(custom)
			RigHelper.normalize_character_root(custom, true)
			_skel = skel
			_skel_bones = RigHelper.map_bones(skel)
			_skel_cur.resize(J_COUNT)
			_held_box = _add_box(_body, Vector3(0.0, 1.18, -0.47), Vector3(0.42, 0.30, 0.34), cardboard)
			_add_box(_held_box, Vector3(0.0, 0.151, 0.0), Vector3(0.06, 0.005, 0.345), tape_mat)
			_add_box(_held_box, Vector3(0.10, 0.03, -0.172), Vector3(0.13, 0.09, 0.004), label_mat)
			_held_box.visible = false
			return
		var p_body := custom.find_child("Pivot_Body", true, false) as Node3D
		var p_torso := custom.find_child("Pivot_Torso", true, false) as Node3D
		var p_head := custom.find_child("Pivot_Head", true, false) as Node3D
		var p_tl := custom.find_child("Pivot_ThighL", true, false) as Node3D
		var p_tr := custom.find_child("Pivot_ThighR", true, false) as Node3D
		var p_kl := custom.find_child("Pivot_KneeL", true, false) as Node3D
		var p_kr := custom.find_child("Pivot_KneeR", true, false) as Node3D
		var p_sl := custom.find_child("Pivot_ShoulderL", true, false) as Node3D
		var p_sr := custom.find_child("Pivot_ShoulderR", true, false) as Node3D
		var p_el := custom.find_child("Pivot_ElbowL", true, false) as Node3D
		var p_er := custom.find_child("Pivot_ElbowR", true, false) as Node3D
		if p_body != null and p_torso != null and p_head != null and p_tl != null and p_tr != null and p_kl != null and p_kr != null and p_sl != null and p_sr != null and p_el != null and p_er != null:
			add_child(custom)
			_body = p_body
			_torso = p_torso
			_head = p_head
			_thigh_l = p_tl
			_thigh_r = p_tr
			_knee_l = p_kl
			_knee_r = p_kr
			_shoulder_l = p_sl
			_shoulder_r = p_sr
			_elbow_l = p_el
			_elbow_r = p_er
			_held_box = _add_box(_torso, Vector3(0.0, 0.30, -0.47), Vector3(0.42, 0.30, 0.34), cardboard)
			_add_box(_held_box, Vector3(0.0, 0.151, 0.0), Vector3(0.06, 0.005, 0.345), tape_mat)
			_add_box(_held_box, Vector3(0.10, 0.03, -0.172), Vector3(0.13, 0.09, 0.004), label_mat)
			_held_box.visible = false
			return
		custom.free()

	var uniform_mat := _mat(Color(0.11, 0.19, 0.31), 0.78, 0.0)
	var collar_mat := _mat(Color(0.08, 0.14, 0.24), 0.80, 0.0)
	var trouser_mat := _mat(Color(0.17, 0.18, 0.20), 0.85, 0.0)
	var shoe_mat := _mat(Color(0.09, 0.08, 0.08), 0.55, 0.05)
	var sole_mat := _mat(Color(0.05, 0.05, 0.05), 0.95, 0.0)
	var skin_mat := _mat(Color(0.86, 0.69, 0.56), 0.62, 0.0)
	var hair_mat := _mat(Color(0.22, 0.15, 0.10), 0.90, 0.0)
	var eye_mat := _mat(Color(0.10, 0.09, 0.08), 0.30, 0.0)
	var eye_white_mat := _mat(Color(0.92, 0.91, 0.88), 0.35, 0.0)
	var lip_mat := _mat(Color(0.62, 0.38, 0.33), 0.55, 0.0)
	var reflect_mat := _mat(Color(0.82, 0.84, 0.86), 0.30, 0.35)
	var amber_mat := _mat(Color(0.88, 0.58, 0.12), 0.50, 0.0)
	var belt_mat := _mat(Color(0.10, 0.10, 0.11), 0.55, 0.20)
	var buckle_mat := _mat(Color(0.70, 0.72, 0.75), 0.25, 0.85)

	_body = Node3D.new()
	add_child(_body)

	# Becken, Gürtel mit Schnalle
	var pelvis := _add_capsule(_body, Vector3(0.0, 0.95, 0.0), 0.11, 0.36, trouser_mat)
	pelvis.rotation_degrees.z = 90.0
	pelvis.scale = Vector3(1.0, 1.0, 0.9)
	var belt := _add_cyl(_body, Vector3(0.0, 1.0, 0.0), 0.172, 0.045, belt_mat)
	belt.scale = Vector3(0.92, 1.0, 0.62)
	_add_box(_body, Vector3(0.0, 1.0, -0.108), Vector3(0.05, 0.035, 0.01), buckle_mat)

	# Beine mit Kniegelenk
	var leg_l := _build_leg(-0.10, trouser_mat, shoe_mat, sole_mat, reflect_mat)
	_thigh_l = leg_l[0]
	_knee_l = leg_l[1]
	var leg_r := _build_leg(0.10, trouser_mat, shoe_mat, sole_mat, reflect_mat)
	_thigh_r = leg_r[0]
	_knee_r = leg_r[1]

	# Oberkörper (Drehpunkt an der Hüfte, damit er sich vorbeugen kann)
	_torso = Node3D.new()
	_torso.position = Vector3(0.0, 0.92, 0.0)
	_body.add_child(_torso)
	# Schmalerer Brustkorb, damit die herabhängenden Arme nicht im Körper stecken
	# Kürzer als vorher: die Brust endet unter dem Kragen, damit der Hals sichtbar bleibt
	var chest := _add_capsule(_torso, Vector3(0.0, 0.28, 0.0), 0.20, 0.54, uniform_mat)
	chest.scale = Vector3(0.82, 1.0, 0.6)
	# Schulterpartie verbindet Brust und Oberarme (Gesamtbreite mit Armen ca. 0,48 m)
	var yoke := _add_capsule(_torso, Vector3(0.0, 0.47, 0.0), 0.058, 0.30, uniform_mat)
	yoke.rotation_degrees.z = 90.0
	yoke.scale = Vector3(1.0, 1.0, 0.72)
	var stripe := _add_cyl(_torso, Vector3(0.0, 0.22, 0.0), 0.203, 0.035, reflect_mat)
	stripe.scale = Vector3(0.82, 1.0, 0.6)
	_add_box(_torso, Vector3(0.0, 0.33, -0.122), Vector3(0.012, 0.42, 0.005), collar_mat) # Reißverschluss
	_add_box(_torso, Vector3(-0.09, 0.42, -0.112), Vector3(0.09, 0.032, 0.008), amber_mat) # Namensschild
	var collar := _add_cyl(_torso, Vector3(0.0, 0.545, 0.0), 0.075, 0.05, collar_mat)
	collar.scale = Vector3(1.0, 1.0, 0.85)
	_add_cyl(_torso, Vector3(0.0, 0.60, 0.0), 0.045, 0.12, skin_mat) # Hals

	# Kopf mit Gesicht, Haaren und Schirmmütze
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.615, 0.0)
	_torso.add_child(_head)
	var skull := _add_sphere(_head, Vector3(0.0, 0.13, 0.0), 0.11, 0.25, skin_mat)
	skull.scale = Vector3(0.92, 1.0, 1.0)
	# Haare nach hinten versetzt: vorne bleiben sie hinter der Stirn, Augen und Brauen liegen frei
	var hair := _add_sphere(_head, Vector3(0.0, 0.175, 0.03), 0.113, 0.19, hair_mat)
	hair.scale = Vector3(0.95, 1.0, 1.0)
	var nose := _add_sphere(_head, Vector3(0.0, 0.115, -0.108), 0.016, 0.04, skin_mat)
	nose.scale = Vector3(0.75, 1.0, 1.0)
	_add_box(_head, Vector3(0.0, 0.085, -0.099), Vector3(0.035, 0.006, 0.008), lip_mat) # Mund
	for ex in [-0.04, 0.04]:
		var x := float(ex)
		_add_sphere(_head, Vector3(x, 0.145, -0.096), 0.016, 0.032, eye_white_mat)
		_add_sphere(_head, Vector3(x, 0.145, -0.108), 0.008, 0.016, eye_mat) # Pupille
		_add_box(_head, Vector3(x, 0.168, -0.104), Vector3(0.035, 0.008, 0.01), hair_mat) # Augenbraue
		var ear := _add_sphere(_head, Vector3(x * 2.7, 0.125, 0.005), 0.025, 0.05, skin_mat)
		ear.scale = Vector3(0.5, 1.0, 0.8)
	var cap := _add_sphere(_head, Vector3(0.0, 0.20, 0.005), 0.12, 0.12, collar_mat)
	(cap.mesh as SphereMesh).is_hemisphere = true
	cap.scale = Vector3(1.0, 0.85, 1.03)
	var brim := _add_box(_head, Vector3(0.0, 0.205, -0.15), Vector3(0.19, 0.012, 0.11), collar_mat)
	brim.rotation.x = -0.12
	_add_box(_head, Vector3(0.0, 0.25, -0.110), Vector3(0.06, 0.03, 0.005), amber_mat) # Mützenlogo

	# Arme mit Ellbogengelenk
	var arm_l := _build_arm(-0.17, uniform_mat, collar_mat, skin_mat)
	_shoulder_l = arm_l[0]
	_elbow_l = arm_l[1]
	var arm_r := _build_arm(0.17, uniform_mat, collar_mat, skin_mat)
	_shoulder_r = arm_r[0]
	_elbow_r = arm_r[1]

	# Karton zwischen beiden Händen (am Oberkörper, damit er beim Bücken mitgeht)
	_held_box = _add_box(_torso, Vector3(0.0, 0.30, -0.47), Vector3(0.42, 0.30, 0.34), cardboard)
	_add_box(_held_box, Vector3(0.0, 0.151, 0.0), Vector3(0.06, 0.005, 0.345), tape_mat)
	_add_box(_held_box, Vector3(0.10, 0.03, -0.172), Vector3(0.13, 0.09, 0.004), label_mat)
	_held_box.visible = false


func _build_leg(side_x: float, trouser_mat: Material, shoe_mat: Material, sole_mat: Material, reflect_mat: Material) -> Array[Node3D]:
	var thigh := Node3D.new()
	thigh.position = Vector3(side_x, 0.92, 0.0)
	_body.add_child(thigh)
	_add_capsule(thigh, Vector3(0.0, -0.22, 0.0), 0.078, 0.50, trouser_mat)
	var knee := Node3D.new()
	knee.position = Vector3(0.0, -0.45, 0.0)
	thigh.add_child(knee)
	_add_capsule(knee, Vector3(0.0, -0.21, 0.0), 0.064, 0.46, trouser_mat)
	_add_cyl(knee, Vector3(0.0, -0.30, 0.0), 0.066, 0.03, reflect_mat) # Reflexstreifen
	# Arbeitsschuh: Schaft, Zehenkappe, Profilsohle
	_add_box(knee, Vector3(0.0, -0.415, -0.05), Vector3(0.11, 0.075, 0.25), shoe_mat)
	var toe := _add_sphere(knee, Vector3(0.0, -0.425, -0.14), 0.055, 0.11, shoe_mat)
	toe.scale = Vector3(1.0, 0.65, 1.0)
	_add_box(knee, Vector3(0.0, -0.456, -0.055), Vector3(0.12, 0.028, 0.28), sole_mat)
	var parts: Array[Node3D] = [thigh, knee]
	return parts


func _build_arm(side_x: float, sleeve_mat: Material, cuff_mat: Material, skin_mat: Material) -> Array[Node3D]:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side_x, 0.475, 0.0)
	_torso.add_child(shoulder)
	_add_sphere(shoulder, Vector3.ZERO, 0.044, 0.088, sleeve_mat)
	_add_capsule(shoulder, Vector3(0.0, -0.14, 0.0), 0.044, 0.32, sleeve_mat)
	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -0.29, 0.0)
	shoulder.add_child(elbow)
	_add_capsule(elbow, Vector3(0.0, -0.12, 0.0), 0.045, 0.28, sleeve_mat)
	_add_cyl(elbow, Vector3(0.0, -0.245, 0.0), 0.048, 0.03, cuff_mat) # Bündchen
	# Hand (ca. 19 cm lang): flache Handfläche, vier einzelne Finger, Daumen nach vorn.
	# Die Handfläche zeigt zum Körper (inward = +1 links, -1 rechts), die Finger krümmen sich dorthin.
	var inward := -signf(side_x)
	_add_box(elbow, Vector3(0.0, -0.33, 0.0), Vector3(0.034, 0.11, 0.080), skin_mat)
	var finger_z: Array[float] = [-0.027, -0.009, 0.009, 0.027]
	var finger_len: Array[float] = [0.080, 0.088, 0.082, 0.066]
	for fi in range(finger_z.size()):
		var flen := finger_len[fi]
		var finger := _add_capsule(elbow, Vector3(inward * 0.005, -0.365 - flen * 0.5, finger_z[fi]), 0.0105, flen, skin_mat)
		finger.rotation_degrees.z = 14.0 * inward
	var thumb := _add_capsule(elbow, Vector3(inward * 0.012, -0.31, -0.042), 0.0125, 0.068, skin_mat)
	thumb.rotation_degrees = Vector3(22.0, 0.0, 10.0 * inward)
	var parts: Array[Node3D] = [shoulder, elbow]
	return parts


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_capsule(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0)
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_sphere(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
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