class_name DeliveryVan
extends Node3D
## v1.0 Realistic European "CLOUD EXPRESS" Delivery Van.
## Features sculpted angled hood, raked transparent windshield with visible cabin interior
## (dashboard, steering wheel, 2 seats), wing mirrors, slatted radiator grille, EU license plates,
## wheel arch flares, 5-spoke alloy wheels, flush fleet livery, steel sliding-door track,
## birch-plywood lined cargo hold with interior LED light, split rear barn doors & animated hazard lights.

const LANE_Z := 12.4
const START_X := -26.0
const STOP_X := 0.2
const END_X := 32.0
const DeliveryDriverScript := preload("res://scripts/world/delivery_driver.gd")
const HandTruckScript := preload("res://scripts/world/hand_truck.gd")

var _vehicle_root: Node3D
var _active_tier: int = 0
var _wheel_radius: float = 0.40
var _wheels: Array[Node3D] = []
var _side_door: Node3D
var _side_door_base_pos: Vector3 = Vector3(-0.08, 1.32, -1.05)
var _side_ramp: Node3D
var _tail_lift: Node3D
var _tail_lift_base_y: float = 1.04
var _beacon_mat: StandardMaterial3D
var _hazard_mat: StandardMaterial3D
var _brake_mat: StandardMaterial3D
var _headlight_glow: OmniLight3D
var _cargo_light: OmniLight3D
var _cargo_boxes: Array[MeshInstance3D] = []
var _engine_audio: AudioStreamPlayer3D
var _sfx_audio: AudioStreamPlayer3D
var _prev_van_phase: String = "idle"
var _backup_beep_accum: float = 0.0
var _driver: DeliveryDriverScript
var _drivers: Array = []
var _hand_truck: HandTruckScript
var _hand_trucks: Array = []
var _cab_door: Node3D
var _cab_door_recess: MeshInstance3D
var _cab_door_t: float = 0.0
var _unload_t: float = 0.0

var _prev_x: float = START_X
var _door_open_t: float = 0.0
var _blink_t: float = 0.0


func _ready() -> void:
	position = Vector3(START_X, 0.0, LANE_Z)
	visible = false
	_vehicle_root = Node3D.new()
	add_child(_vehicle_root)
	_switch_vehicle_tier(1)
	_setup_audio()


func _clear_vehicle_root() -> void:
	_wheels.clear()
	_cargo_boxes.clear()
	_drivers.clear()
	_hand_trucks.clear()
	_driver = null
	_hand_truck = null
	_side_door = null
	_side_ramp = null
	_tail_lift = null
	_cab_door = null
	_cab_door_recess = null
	_headlight_glow = null
	_cargo_light = null
	_beacon_mat = null
	_hazard_mat = null
	_brake_mat = null
	if _vehicle_root != null:
		for c in _vehicle_root.get_children():
			c.queue_free()


func _switch_vehicle_tier(tier: int) -> void:
	var t := clampi(tier, 1, 3)
	if t == _active_tier and _vehicle_root != null and _vehicle_root.get_child_count() > 0:
		return
	_active_tier = t
	_clear_vehicle_root()
	_door_open_t = 0.0
	_cab_door_t = 0.0

	var model_id := "delivery_van"
	_wheel_radius = 0.40
	var staff_n := 1
	if t == 2:
		model_id = "delivery_truck_medium"
		_wheel_radius = 0.46
		staff_n = 2
	elif t == 3:
		model_id = "delivery_truck_heavy"
		_wheel_radius = 0.52
		staff_n = 3

	var custom_m := ModelLoader.instantiate_custom_model(model_id)
	if custom_m != null:
		_vehicle_root.add_child(custom_m)
		_bind_custom_fleet_model(custom_m, t, staff_n)
	else:
		_build_van_geometry()


func _setup_audio() -> void:
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.position = Vector3(2.2, 0.85, 0.0)
	_engine_audio.stream = SfxManager.get_loop_stream("van_engine")
	_engine_audio.max_distance = 28.0
	_engine_audio.unit_size = 4.6
	_engine_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_engine_audio.volume_db = -60.0
	add_child(_engine_audio)

	_sfx_audio = AudioStreamPlayer3D.new()
	_sfx_audio.position = Vector3(-1.8, 0.95, 0.0)
	_sfx_audio.max_distance = 32.0
	_sfx_audio.unit_size = 5.0
	add_child(_sfx_audio)


func _process(delta: float) -> void:
	_blink_t += delta
	var phase := GameState.van_phase
	var pt := GameState.van_phase_time

	if not GameState.is_active or phase == "idle":
		visible = false
		_prev_x = START_X
		_door_open_t = 0.0
		_unload_t = 0.0
		_cab_door_t = 0.0
		for dr in _drivers:
			(dr as DeliveryDriverScript).reset_to_seat()
		if _engine_audio != null and _engine_audio.playing:
			_engine_audio.stop()
		_prev_van_phase = "idle"
		_backup_beep_accum = 0.0
		return

	# Fahrzeugmodell (Stufe 1 Lieferwagen / Stufe 2 Kastenwagen 7,5t / Stufe 3 Schwerlast-LKW 18t) dynamisch umschalten!
	var want_tier := clampi(GameState.van_delivery_tier, 1, 3)
	if want_tier != _active_tier:
		_switch_vehicle_tier(want_tier)

	# Bei Ankunft: Druckluft-Bremszischen bei 7,5t/18t LKW (Garagentor oeffnet der Server in GameState!)
	if phase != _prev_van_phase:
		if phase == "unloading" and _active_tier >= 2 and _sfx_audio != null:
			var ab := SfxManager.get_sound_stream("air_brake")
			var g_gain := SettingsManager.get_effective_sfx_gain()
			if ab != null and g_gain > 0.005:
				_sfx_audio.stream = ab
				_sfx_audio.volume_db = linear_to_db(g_gain * SfxManager.get_outdoor_transmission()) - 4.5
				_sfx_audio.pitch_scale = randf_range(0.92, 1.05)
				_sfx_audio.play()
		_prev_van_phase = phase

	visible = true
	var lane_z := LANE_Z + (0.28 if _active_tier == 2 else (0.58 if _active_tier == 3 else 0.0))
	var target_x := STOP_X
	var target_door := 0.0

	match phase:
		"arriving":
			# Realistische Rückwärtslogistik: erst kurz über die Einfahrt hinaus vorfahren,
			# dann kurz anhalten (Rückwärtsgang) und rückwärts in die Halteposition rangieren!
			var u := clampf(pt / GameState.VAN_ARRIVE_DURATION, 0.0, 1.0)
			var overshoot_x := STOP_X + 3.6
			if u < 0.62:
				var f := u / 0.62
				var eased := 1.0 - pow(1.0 - f, 2.4)
				target_x = lerpf(START_X, overshoot_x, eased)
			elif u < 0.70:
				target_x = overshoot_x
			else:
				var r := (u - 0.70) / 0.30
				var r_eased := r * r * (3.0 - 2.0 * r)
				target_x = lerpf(overshoot_x, STOP_X, r_eased)
			target_door = 0.0
		"unloading":
			target_x = STOP_X
			target_door = _driver.get_side_door_target() if _driver != null else 1.0
		"departing":
			var u := clampf(pt / GameState.VAN_DEPART_DURATION, 0.0, 1.0)
			var eased := pow(u, 2.2)
			target_x = lerpf(STOP_X, END_X, eased)
			target_door = 0.0

	var dx := target_x - _prev_x
	_prev_x = target_x
	position = Vector3(target_x, 0.0, lane_z)

	# Rückfahr-Piepen NUR wenn das Fahrzeug tatsächlich rückwärts fährt (dx < 0) — niemals beim Vorwärtsfahren!
	var is_reversing := (phase == "arriving" and dx < -0.0008)
	if is_reversing and _sfx_audio != null:
		_backup_beep_accum += delta
		if _backup_beep_accum >= 0.68:
			_backup_beep_accum = 0.0
			var bp := SfxManager.get_sound_stream("backup_beep")
			var g_gain := SettingsManager.get_effective_sfx_gain()
			if bp != null and g_gain > 0.005:
				_sfx_audio.stream = bp
				_sfx_audio.volume_db = linear_to_db(g_gain * SfxManager.get_outdoor_transmission()) - 6.5
				_sfx_audio.pitch_scale = 1.0 if _active_tier <= 2 else 0.94
				_sfx_audio.play()
	else:
		_backup_beep_accum = 0.55

	# Alle Raeder (4 bzw. 6 beim Schwerlast-LKW) passend zum Radradius drehen
	var wheel_spin := -dx / maxf(_wheel_radius, 0.25)
	for w in _wheels:
		w.rotation.z += wheel_spin

	# Fahrzeugspezifische Entlade-Mechanik:
	# - Stufe 1 (Lieferwagen): seitliche Schiebetuer
	# - Stufe 2 (7,5t Kastenwagen): Seiten-Rolltuer + ausklappbare Alu-Laderampe!
	# - Stufe 3 (18t Schwerlast-LKW): breite Rolltuer + absenkbare Hydraulik-Ladebordwand!
	_door_open_t = lerpf(_door_open_t, target_door, clampf(delta * 5.0, 0.0, 1.0))
	if _side_door != null:
		if _active_tier == 1:
			var pop_out := clampf(_door_open_t * 4.5, 0.0, 1.0)
			var slide_u := clampf((_door_open_t - 0.14) / 0.86, 0.0, 1.0)
			_side_door.position.z = lerpf(-1.05, -1.13, pop_out)
			_side_door.position.x = lerpf(-0.08, -1.62, slide_u)
		else:
			# Rolltuer gleitet glatt nach oben in den Dachkasten
			var open_u := clampf(_door_open_t * 1.25, 0.0, 1.0)
			_side_door.position.y = _side_door_base_pos.y + open_u * (1.05 if _active_tier == 2 else 1.15)
			_side_door.scale.y = maxf(0.05, 1.0 - open_u * 0.92)
			_side_door.visible = open_u < 0.98

	if _side_ramp != null:
		# Ausklappbare Alu-Rampe (Stufe 2): klappt sanft nach aussen (-Z) auf die Fahrbahn!
		var ramp_u := smoothstep(0.0, 1.0, clampf((_door_open_t - 0.12) / 0.88, 0.0, 1.0))
		_side_ramp.rotation_degrees.x = lerpf(0.0, -118.0, ramp_u)

	if _tail_lift != null:
		# Hydraulik-Ladebordwand (Stufe 3): klappt aus der Senkrechten flach und faehrt hydraulisch auf Bodenniveau ab!
		var fold_u := smoothstep(0.0, 1.0, clampf(_door_open_t / 0.45, 0.0, 1.0))
		var lower_u := smoothstep(0.0, 1.0, clampf((_door_open_t - 0.40) / 0.60, 0.0, 1.0))
		_tail_lift.rotation_degrees.x = lerpf(90.0, 0.0, fold_u)
		_tail_lift.position.y = lerpf(_tail_lift_base_y, 0.09, lower_u)

	# Kartons im Laderaum: Restladung plus die Kartons der laufenden Fahrt, die noch nicht entnommen wurden
	var rem := GameState.van_cargo_count
	if _driver != null and phase == "unloading":
		rem += _driver.get_trip_crates_in_van()
	for i in range(_cargo_boxes.size()):
		_cargo_boxes[i].visible = (i < rem)

	# Team aus 1 / 2 / 3 Mitarbeitern animieren
	if phase == "unloading":
		_unload_t += delta
	else:
		_unload_t = 0.0
	for dr in _drivers:
		(dr as DeliveryDriverScript).update_driver(delta, phase, _unload_t, rem)
	if _driver != null:
		_cab_door_t = lerpf(_cab_door_t, _driver.get_cab_door_target(), clampf(delta * 6.0, 0.0, 1.0))
	if _cab_door != null:
		_cab_door.rotation_degrees.y = -68.0 * _cab_door_t
	if _cab_door_recess != null:
		_cab_door_recess.visible = _cab_door_t > 0.04

	# Cargo bay interior light turns on automatically while door is open
	if _cargo_light != null:
		_cargo_light.light_energy = 1.2 * _door_open_t

	# Flashing amber roof lightbar + 4-way hazard indicators while unloading
	var blink_on := sin(_blink_t * 9.5) > 0.0
	if _beacon_mat != null:
		if phase == "unloading":
			_beacon_mat.emission_energy_multiplier = 2.8 if blink_on else 0.18
		else:
			_beacon_mat.emission_energy_multiplier = 0.12
	if _hazard_mat != null:
		if phase == "unloading":
			_hazard_mat.emission_energy_multiplier = 2.6 if blink_on else 0.05
		else:
			_hazard_mat.emission_energy_multiplier = 0.05
	if _brake_mat != null:
		var braking := (phase == "arriving" and pt > GameState.VAN_ARRIVE_DURATION * 0.55) or phase == "unloading"
		_brake_mat.emission_energy_multiplier = 2.8 if braking else 1.1

	if _headlight_glow != null:
		var is_night := (GameState.time_of_day < 0.25 or GameState.time_of_day > 0.74)
		_headlight_glow.light_energy = 3.2 if is_night else 0.45

	# Click-free spatial diesel van engine rumble
	if _engine_audio != null:
		var gain := SettingsManager.get_effective_sfx_gain()
		if gain <= 0.005:
			if _engine_audio.playing:
				_engine_audio.stop()
		else:
			if not _engine_audio.playing:
				_engine_audio.play()
			var speed := absf(dx) / maxf(delta, 0.001)
			var vol_lin := clampf((0.24 + clampf(speed / 12.0, 0.0, 0.48)) * gain, 0.02, 1.0)
			var tier_vol_boost := 0.0 if _active_tier == 1 else (2.2 if _active_tier == 2 else 4.0)
			var tier_pitch_scale := 1.0 if _active_tier == 1 else (0.82 if _active_tier == 2 else 0.66)
			_engine_audio.volume_db = linear_to_db(vol_lin) - 7.5 + tier_vol_boost
			_engine_audio.pitch_scale = clampf((0.84 + speed * 0.042) * tier_pitch_scale, 0.52, 1.44)


func _build_van_geometry() -> void:
	var custom_m := ModelLoader.instantiate_custom_model("delivery_van")
	if custom_m != null:
		_vehicle_root.add_child(custom_m)
		_bind_custom_fleet_model(custom_m, 1, 1)
		return

	# Clean automotive & logistics fleet materials (clearcoat white paint + navy/amber livery)
	var body_white := _paint_mat(Color(0.93, 0.94, 0.95), 0.24, 0.14)
	var fleet_navy := _paint_mat(Color(0.10, 0.20, 0.34), 0.28, 0.18)
	var fleet_amber := _paint_mat(Color(0.88, 0.58, 0.12), 0.30, 0.14)
	var trim_plastic := _mat(Color(0.14, 0.15, 0.17), 0.78, 0.06)
	var chassis_dark := _mat(Color(0.09, 0.10, 0.12), 0.85, 0.15)
	var steel_rail := _mat(Color(0.54, 0.57, 0.62), 0.32, 0.82)
	var chrome_mat := _mat(Color(0.78, 0.82, 0.86), 0.18, 0.90)
	var tire_mat := _mat(Color(0.08, 0.085, 0.095), 0.92, 0.0)
	var alloy_mat := _mat(Color(0.72, 0.75, 0.79), 0.28, 0.82)
	var plywood_mat := _mat(Color(0.68, 0.56, 0.40), 0.86, 0.0)
	var floor_mat := _mat(Color(0.20, 0.21, 0.23), 0.86, 0.06)
	var seat_mat := _mat(Color(0.18, 0.20, 0.23), 0.88, 0.0)
	var plate_white := _mat(Color(0.95, 0.96, 0.97), 0.35, 0.08)
	var eu_blue := _mat(Color(0.08, 0.22, 0.64), 0.35, 0.08)

	# Real semi-transparent automotive tinted glass so cabin interior is visible!
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.12, 0.18, 0.24, 0.48)
	glass_mat.roughness = 0.08
	glass_mat.metallic = 0.22
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# ==========================================================================
	# 1. CHASSIS, UNDERBODY, SIDE CLADDING & SCULPTED BUMPERS
	# ==========================================================================
	_add_box(self, Vector3(0.10, 0.42, 0.0), Vector3(5.55, 0.22, 1.96), chassis_dark)
	# Matte charcoal lower body rubbing trim (cargo van styling)
	_add_box(self, Vector3(0.08, 0.62, -1.03), Vector3(5.48, 0.24, 0.05), trim_plastic)
	_add_box(self, Vector3(0.08, 0.62, 1.03), Vector3(5.48, 0.24, 0.05), trim_plastic)

	# Front sculpted bumper + lower air intake + license plate
	_add_box(self, Vector3(2.96, 0.54, 0.0), Vector3(0.28, 0.34, 2.08), trim_plastic)
	_add_box(self, Vector3(3.04, 0.48, 0.0), Vector3(0.16, 0.14, 1.12), chassis_dark) # Lower intake
	_add_box(self, Vector3(3.11, 0.56, 0.0), Vector3(0.02, 0.12, 0.52), plate_white)
	_add_box(self, Vector3(3.115, 0.56, -0.22), Vector3(0.02, 0.12, 0.07), eu_blue)
	var f_plate := Label3D.new()
	f_plate.text = "DC-EX 2406"
	f_plate.font_size = 24
	f_plate.pixel_size = 0.0022
	f_plate.position = Vector3(3.128, 0.56, 0.03)
	f_plate.rotation_degrees.y = 90.0
	f_plate.modulate = Color(0.08, 0.09, 0.11)
	add_child(f_plate)

	# Rear bumper with integrated anti-slip boarding step
	_add_box(self, Vector3(-2.74, 0.50, 0.0), Vector3(0.26, 0.24, 2.12), trim_plastic)
	_add_box(self, Vector3(-2.82, 0.62, 0.0), Vector3(0.14, 0.03, 1.46), steel_rail)

	# ==========================================================================
	# 2. SCULPTED SPRINTER CAB (+X) WITH VISIBLE INTERIOR
	# ==========================================================================
	# Lower cab doors & engine bay walls
	_add_box(self, Vector3(1.86, 0.96, 0.0), Vector3(1.52, 0.78, 2.04), body_white)
	# Angled aerodynamic hood nose
	var hood := _add_box(self, Vector3(2.60, 1.18, 0.0), Vector3(0.84, 0.12, 1.94), body_white)
	hood.rotation_degrees.z = -17.0
	_add_box(self, Vector3(2.74, 0.94, 0.0), Vector3(0.54, 0.44, 1.96), body_white)

	# Slatted dark radiator grille + chrome horizontal bar & center emblem
	_add_box(self, Vector3(3.01, 0.94, 0.0), Vector3(0.06, 0.34, 1.08), chassis_dark)
	for slat_y in [-0.10, 0.0, 0.10]:
		_add_box(self, Vector3(3.04, 0.94 + slat_y, 0.0), Vector3(0.03, 0.025, 1.02), trim_plastic)
	_add_box(self, Vector3(3.05, 0.95, 0.0), Vector3(0.03, 0.045, 0.96), chrome_mat)
	var badge := MeshInstance3D.new()
	var b_cyl := CylinderMesh.new()
	b_cyl.top_radius = 0.085
	b_cyl.bottom_radius = 0.085
	b_cyl.height = 0.035
	badge.mesh = b_cyl
	badge.material_override = chrome_mat
	badge.position = Vector3(3.055, 0.95, 0.0)
	badge.rotation_degrees.z = 90.0
	add_child(badge)

	# Cab roof + aerodynamic roof spoiler fairing smoothly joining cargo roof height!
	_add_box(self, Vector3(1.60, 2.12, 0.0), Vector3(1.22, 0.12, 1.98), body_white)
	var fairing := _add_box(self, Vector3(1.26, 2.34, 0.0), Vector3(0.76, 0.34, 1.98), body_white)
	fairing.rotation_degrees.z = 22.0

	# Cab A-Pillars & B-Pillars framing transparent windows
	for side_z in [-0.96, 0.96]:
		var a_pillar := _add_box(self, Vector3(2.26, 1.72, side_z), Vector3(0.11, 0.84, 0.10), body_white)
		a_pillar.rotation_degrees.z = 24.0
		_add_box(self, Vector3(1.12, 1.72, side_z), Vector3(0.16, 0.82, 0.10), body_white)
		# Door handles & key lock
		_add_box(self, Vector3(1.42, 1.18, side_z * 1.075), Vector3(0.16, 0.045, 0.045), trim_plastic)
		# Commercial dual wing mirrors on steel stalks
		var dir_z := signf(side_z)
		_add_box(self, Vector3(2.14, 1.44, side_z + dir_z * 0.14), Vector3(0.04, 0.04, 0.24), trim_plastic)
		_add_box(self, Vector3(2.14, 1.62, side_z + dir_z * 0.14), Vector3(0.04, 0.04, 0.24), trim_plastic)
		_add_box(self, Vector3(2.14, 1.54, side_z + dir_z * 0.26), Vector3(0.08, 0.34, 0.07), trim_plastic)
		_add_box(self, Vector3(2.10, 1.54, side_z + dir_z * 0.26), Vector3(0.02, 0.30, 0.05), chrome_mat)

	# Raked Panoramic Windshield + Windshield Wipers + Side Cab Windows
	var windshield := _add_box(self, Vector3(2.26, 1.70, 0.0), Vector3(0.05, 0.80, 1.82), glass_mat)
	windshield.rotation_degrees.z = 24.0
	_add_box(self, Vector3(2.40, 1.38, -0.35), Vector3(0.03, 0.025, 0.56), trim_plastic)
	_add_box(self, Vector3(2.40, 1.38, 0.36), Vector3(0.03, 0.025, 0.56), trim_plastic)
	_add_box(self, Vector3(1.66, 1.70, -0.99), Vector3(0.96, 0.64, 0.03), glass_mat)
	_add_box(self, Vector3(1.66, 1.70, 0.99), Vector3(0.96, 0.64, 0.03), glass_mat)

	# Visible Cab Interior (Dashboard, Steering Wheel, Driver & Passenger Seats)
	_add_box(self, Vector3(2.16, 1.24, 0.0), Vector3(0.46, 0.26, 1.80), trim_plastic)
	var wheel_rim := MeshInstance3D.new()
	var w_torus := TorusMesh.new()
	w_torus.inner_radius = 0.13
	w_torus.outer_radius = 0.165
	wheel_rim.mesh = w_torus
	wheel_rim.material_override = trim_plastic
	wheel_rim.position = Vector3(1.94, 1.44, -0.44)
	wheel_rim.rotation_degrees = Vector3(0.0, 0.0, 62.0)
	add_child(wheel_rim)
	for seat_z in [-0.46, 0.46]:
		_add_box(self, Vector3(1.52, 1.18, seat_z), Vector3(0.44, 0.14, 0.48), seat_mat)
		_add_box(self, Vector3(1.34, 1.54, seat_z), Vector3(0.14, 0.62, 0.46), seat_mat)
		_add_box(self, Vector3(1.34, 1.94, seat_z), Vector3(0.11, 0.18, 0.24), seat_mat)

	# Aufschwingende Fahrertür (Garagenseite) + Fahrer am Lenkrad
	_build_driver_door(body_white, fleet_navy, fleet_amber, trim_plastic, glass_mat)
	_hand_truck = HandTruckScript.new()
	_vehicle_root.add_child(_hand_truck)
	_hand_trucks.append(_hand_truck)
	_driver = DeliveryDriverScript.new()
	_vehicle_root.add_child(_driver)
	_driver.set_hand_truck(_hand_truck)
	_driver.configure_worker(0, 1)
	_drivers.append(_driver)

	# ==========================================================================
	# 3. HIGH-ROOF CARGO BOX (-X) WITH PLYWOOD INTERIOR & SPLIT REAR DOORS
	# ==========================================================================
	_add_box(self, Vector3(-0.78, 0.60, 0.0), Vector3(3.78, 0.14, 2.08), floor_mat)     # Cargo floor
	_add_box(self, Vector3(-0.78, 2.54, 0.0), Vector3(3.80, 0.12, 2.08), body_white)    # Cargo roof
	_add_box(self, Vector3(1.04, 1.57, 0.0), Vector3(0.10, 1.86, 2.06), body_white)     # Bulkhead
	_add_box(self, Vector3(0.98, 1.57, 0.0), Vector3(0.03, 1.78, 1.94), plywood_mat)    # Interior bulkhead liner
	_add_box(self, Vector3(-0.78, 1.57, 1.00), Vector3(3.76, 1.86, 0.10), body_white)   # Far (+Z) wall
	_add_box(self, Vector3(-0.78, 1.57, 0.94), Vector3(3.64, 1.74, 0.03), plywood_mat)  # Far interior liner

	# Garage-facing (-Z) wall panels framing the sliding doorway (X = -0.92..+0.72)
	_add_box(self, Vector3(-1.78, 1.57, -1.00), Vector3(1.78, 1.86, 0.10), body_white)
	_add_box(self, Vector3(-1.78, 1.57, -0.94), Vector3(1.68, 1.74, 0.03), plywood_mat)
	_add_box(self, Vector3(0.88, 1.57, -1.00), Vector3(0.36, 1.86, 0.10), body_white)
	# Overhead header trim above sliding doorway + steel sliding door guide rail!
	_add_box(self, Vector3(-0.08, 2.44, -1.00), Vector3(1.68, 0.16, 0.10), body_white)
	_add_box(self, Vector3(-1.66, 1.46, -1.055), Vector3(1.94, 0.05, 0.035), steel_rail) # Middle track rail
	_add_box(self, Vector3(-0.88, 2.45, -1.055), Vector3(3.30, 0.04, 0.03), steel_rail)  # Upper track rail

	# Rear Double Barn Doors (-X) with vertical center seam, hinges, grab handle & EU plate
	_add_box(self, Vector3(-2.64, 1.57, -0.51), Vector3(0.10, 1.84, 0.98), body_white)
	_add_box(self, Vector3(-2.64, 1.57, 0.51), Vector3(0.10, 1.84, 0.98), body_white)
	_add_box(self, Vector3(-2.68, 1.57, 0.0), Vector3(0.03, 1.84, 0.03), chassis_dark) # Center door seam
	for hy in [0.95, 2.18]:
		_add_box(self, Vector3(-2.70, hy, -1.00), Vector3(0.06, 0.11, 0.06), trim_plastic)
		_add_box(self, Vector3(-2.70, hy, 1.00), Vector3(0.06, 0.11, 0.06), trim_plastic)
	_add_box(self, Vector3(-2.70, 1.24, 0.14), Vector3(0.05, 0.16, 0.05), trim_plastic) # Rear handle
	_add_box(self, Vector3(-2.70, 1.14, -0.45), Vector3(0.02, 0.12, 0.50), plate_white)
	_add_box(self, Vector3(-2.705, 1.14, -0.66), Vector3(0.02, 0.12, 0.07), eu_blue)

	# ==========================================================================
	# 4. SLIDING SIDE CARGO DOOR (-Z) & FLUSH FLEET LIVERY (ZERO Z-FIGHTING!)
	# ==========================================================================
	_side_door = Node3D.new()
	_side_door.position = Vector3(-0.08, 1.54, -1.05)
	add_child(_side_door)
	_add_box(_side_door, Vector3.ZERO, Vector3(1.66, 1.76, 0.06), body_white)
	_add_box(_side_door, Vector3(0.0, -0.82, -0.02), Vector3(1.66, 0.14, 0.035), trim_plastic) # Lower trim match
	# Flush continuous navy + amber logistics stripe on sliding door
	_add_box(_side_door, Vector3(0.0, -0.40, -0.036), Vector3(1.65, 0.24, 0.012), fleet_navy)
	_add_box(_side_door, Vector3(0.0, -0.24, -0.036), Vector3(1.65, 0.055, 0.012), fleet_amber)
	_add_box(_side_door, Vector3(0.68, -0.06, -0.048), Vector3(0.18, 0.045, 0.04), trim_plastic) # Door handle

	# Continuous matching navy + amber stripes on rear panel (-Z), cab doors, and far side (+Z)
	_add_box(self, Vector3(-1.78, 1.14, -1.058), Vector3(1.77, 0.24, 0.012), fleet_navy)
	_add_box(self, Vector3(-1.78, 1.30, -1.058), Vector3(1.77, 0.055, 0.012), fleet_amber)
	_add_box(self, Vector3(1.42, 1.14, -1.028), Vector3(1.38, 0.20, 0.012), fleet_navy)
	_add_box(self, Vector3(1.42, 1.28, -1.028), Vector3(1.38, 0.05, 0.012), fleet_amber)

	_add_box(self, Vector3(-0.78, 1.14, 1.058), Vector3(3.75, 0.24, 0.012), fleet_navy)
	_add_box(self, Vector3(-0.78, 1.30, 1.058), Vector3(3.75, 0.055, 0.012), fleet_amber)
	_add_box(self, Vector3(1.42, 1.14, 1.028), Vector3(1.38, 0.20, 0.012), fleet_navy)
	_add_box(self, Vector3(1.42, 1.28, 1.028), Vector3(1.38, 0.05, 0.012), fleet_amber)

	# Clean crisp "CLOUD EXPRESS" Fleet Signage on BOTH sides (properly seated on panels!)
	for side in [-1.0, 1.0]:
		var brand := Label3D.new()
		brand.text = "CLOUD EXPRESS"
		brand.font_size = 44
		brand.pixel_size = 0.0052
		brand.position = Vector3(-1.78 if side < 0.0 else -0.82, 1.92, side * 1.066)
		brand.rotation_degrees.y = 180.0 if side < 0.0 else 0.0
		brand.modulate = Color(0.10, 0.20, 0.36)
		add_child(brand)

		var sub := Label3D.new()
		sub.text = "IT-HARDWARE & SERVER LOGISTIK"
		sub.font_size = 22
		sub.pixel_size = 0.0044
		sub.position = Vector3(-1.78 if side < 0.0 else -0.82, 1.68, side * 1.066)
		sub.rotation_degrees.y = 180.0 if side < 0.0 else 0.0
		sub.modulate = Color(0.76, 0.46, 0.08)
		add_child(sub)

	# ==========================================================================
	# 5. CARGO BAY PARCELS & INTERIOR OVERHEAD WORK LIGHT
	# ==========================================================================
	var c_mat := MatLib.get_mat("cardboard")
	for i in range(6):
		var col := i % 3
		var row := i / 3
		var box := _add_box(self, Vector3(-0.56 + float(col) * 0.56, 0.90 + float(row) * 0.46, -0.08), Vector3(0.46, 0.40, 0.46), c_mat)
		_cargo_boxes.append(box)

	_cargo_light = OmniLight3D.new()
	_cargo_light.position = Vector3(-0.10, 2.38, -0.10)
	_cargo_light.light_color = Color(1.0, 0.96, 0.88)
	_cargo_light.omni_range = 4.2
	_cargo_light.light_energy = 0.0
	add_child(_cargo_light)

	# ==========================================================================
	# 6. REALISTIC AUTOMOTIVE LIGHTING (LED Headlights, Turn Signals, Taillights, Lightbar)
	# ==========================================================================
	var hl_mat := StandardMaterial3D.new()
	hl_mat.albedo_color = Color(1.0, 0.98, 0.92)
	hl_mat.emission_enabled = true
	hl_mat.emission = Color(1.0, 0.96, 0.86)
	hl_mat.emission_energy_multiplier = 3.0

	_hazard_mat = StandardMaterial3D.new()
	_hazard_mat.albedo_color = Color(0.96, 0.54, 0.08)
	_hazard_mat.emission_enabled = true
	_hazard_mat.emission = Color(1.0, 0.56, 0.06)
	_hazard_mat.emission_energy_multiplier = 0.05

	_brake_mat = StandardMaterial3D.new()
	_brake_mat.albedo_color = Color(0.82, 0.10, 0.08)
	_brake_mat.emission_enabled = true
	_brake_mat.emission = Color(1.0, 0.12, 0.08)
	_brake_mat.emission_energy_multiplier = 1.2

	# Front headlight housings + outer amber turn indicators + lower fog lamps
	for lz in [-0.74, 0.74]:
		_add_box(self, Vector3(3.01, 0.96, lz), Vector3(0.06, 0.20, 0.34), hl_mat)
		_add_box(self, Vector3(3.01, 0.96, lz + signf(lz) * 0.21), Vector3(0.06, 0.18, 0.09), _hazard_mat)
		_add_box(self, Vector3(3.08, 0.54, lz * 0.95), Vector3(0.04, 0.09, 0.16), hl_mat)

	_headlight_glow = OmniLight3D.new()
	_headlight_glow.position = Vector3(3.9, 1.0, 0.0)
	_headlight_glow.light_color = Color(1.0, 0.95, 0.84)
	_headlight_glow.omni_range = 11.0
	_headlight_glow.light_energy = 0.45
	add_child(_headlight_glow)

	# Tall vertical van-style rear light clusters (Brake + Amber Turn + White Reverse)
	for tz in [-0.92, 0.92]:
		_add_box(self, Vector3(-2.70, 1.28, tz), Vector3(0.05, 0.56, 0.16), trim_plastic)
		_add_box(self, Vector3(-2.72, 1.44, tz), Vector3(0.03, 0.20, 0.12), _brake_mat)
		_add_box(self, Vector3(-2.72, 1.24, tz), Vector3(0.03, 0.13, 0.12), _hazard_mat)
		_add_box(self, Vector3(-2.72, 1.09, tz), Vector3(0.03, 0.11, 0.12), plate_white)
	# Third high-mount center brake light above rear doors
	_add_box(self, Vector3(-2.68, 2.52, 0.0), Vector3(0.05, 0.06, 0.38), _brake_mat)

	# Low-profile commercial amber LED roof warning lightbar
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.98, 0.62, 0.10)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.60, 0.06)
	_beacon_mat.emission_energy_multiplier = 0.15
	_add_box(self, Vector3(0.92, 2.63, 0.0), Vector3(0.24, 0.09, 0.72), _beacon_mat)
	_add_box(self, Vector3(0.92, 2.63, 0.0), Vector3(0.26, 0.10, 0.18), trim_plastic)

	# ==========================================================================
	# 7. FENDER FLARES & 4 DETAILED 5-SPOKE COMMERCIAL WHEELS
	# ==========================================================================
	var wheel_spots: Array[Vector3] = [
		Vector3(1.94, 0.40, -1.01),
		Vector3(1.94, 0.40, 1.01),
		Vector3(-1.54, 0.40, -1.01),
		Vector3(-1.54, 0.40, 1.01),
	]
	for wp in wheel_spots:
		# Sculpted wheel arch fender trim above each tire
		_add_box(self, Vector3(wp.x, 0.88, wp.z * 1.03), Vector3(0.92, 0.09, 0.12), trim_plastic)

		var wroot := Node3D.new()
		wroot.position = wp
		add_child(wroot)

		var tire := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.40
		tc.bottom_radius = 0.40
		tc.height = 0.25
		tire.mesh = tc
		tire.material_override = tire_mat
		tire.rotation_degrees.x = 90.0
		wroot.add_child(tire)

		var rim := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 0.235
		rc.bottom_radius = 0.235
		rc.height = 0.265
		rim.mesh = rc
		rim.material_override = alloy_mat
		rim.rotation_degrees.x = 90.0
		wroot.add_child(rim)

		# Inner hub + 5-spoke star pattern so tire rotation looks ultra-crisp!
		var hub := MeshInstance3D.new()
		var hc := CylinderMesh.new()
		hc.top_radius = 0.075
		hc.bottom_radius = 0.075
		hc.height = 0.285
		hub.mesh = hc
		hub.material_override = chassis_dark
		hub.rotation_degrees.x = 90.0
		wroot.add_child(hub)
		for s_i in range(5):
			var sp := _add_box(wroot, Vector3.ZERO, Vector3(0.41, 0.045, 0.272), chassis_dark)
			sp.rotation_degrees.z = float(s_i) * 36.0
		_wheels.append(wroot)


func _build_driver_door(paint: Material, navy: Material, amber: Material, trim: Material, glass: Material) -> void:
	# Dunkle Türöffnung, nur sichtbar solange die Tür offen steht
	_cab_door_recess = _add_box(self, Vector3(1.68, 0.97, -1.040), Vector3(0.94, 0.74, 0.01), _mat(Color(0.07, 0.075, 0.085), 0.9, 0.0))
	_cab_door_recess.visible = false

	# Scharnier an der Vorderkante (X 2.16), Tür reicht bis zur B-Säule (X 1.20)
	_cab_door = Node3D.new()
	_cab_door.position = Vector3(2.16, 0.0, -1.045)
	add_child(_cab_door)
	_add_box(_cab_door, Vector3(-0.48, 0.96, 0.0), Vector3(0.96, 0.78, 0.05), paint)
	_add_box(_cab_door, Vector3(-0.48, 1.14, -0.028), Vector3(0.95, 0.20, 0.008), navy)
	_add_box(_cab_door, Vector3(-0.48, 1.28, -0.028), Vector3(0.95, 0.05, 0.008), amber)
	_add_box(_cab_door, Vector3(-0.78, 1.20, -0.04), Vector3(0.16, 0.045, 0.03), trim)
	# Fensterrahmen + Scheibe
	_add_box(_cab_door, Vector3(-0.48, 1.70, 0.0), Vector3(0.90, 0.62, 0.02), glass)
	_add_box(_cab_door, Vector3(-0.48, 2.03, 0.0), Vector3(0.96, 0.04, 0.05), paint)
	_add_box(_cab_door, Vector3(-0.94, 1.69, 0.0), Vector3(0.04, 0.66, 0.05), paint)


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


func _paint_mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := _mat(col, rough, metal)
	m.clearcoat_enabled = true
	m.clearcoat = 0.65
	m.clearcoat_roughness = 0.14
	return m


func _bind_custom_fleet_model(root: Node3D, tier: int, staff_n: int) -> void:
	for wn in ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]:
		var w := root.find_child(wn, true, false) as Node3D
		if w != null:
			_wheels.append(w)
	_side_door = root.find_child("Side_Door", true, false) as Node3D
	if _side_door != null:
		_side_door_base_pos = _side_door.position
	_side_ramp = root.find_child("Side_Ramp", true, false) as Node3D
	_tail_lift = root.find_child("Tail_Lift", true, false) as Node3D
	if _tail_lift != null:
		_tail_lift_base_y = _tail_lift.position.y
		_tail_lift.rotation_degrees.x = 90.0
	_cab_door = root.find_child("Cab_Door_L", true, false) as Node3D

	# Live-Materialien (Rundumleuchte, Warnblinker, Bremslicht) vom Blender-Modell uebernehmen
	_beacon_mat = _extract_live_mat(root, "Van_BeaconMat", Color(0.98, 0.62, 0.10))
	_hazard_mat = _extract_live_mat(root, "Van_HazardMat", Color(0.96, 0.54, 0.08))
	_brake_mat = _extract_live_mat(root, "Van_BrakeMat", Color(0.82, 0.10, 0.08))

	var hl_x := 3.6 if tier == 1 else (4.2 if tier == 2 else 5.2)
	_headlight_glow = OmniLight3D.new()
	_headlight_glow.position = Vector3(hl_x, 1.0, 0.0)
	_headlight_glow.light_color = Color(1.0, 0.96, 0.88)
	_headlight_glow.omni_range = 12.0 + float(tier) * 2.0
	_headlight_glow.light_energy = 0.45
	_vehicle_root.add_child(_headlight_glow)

	_cargo_light = OmniLight3D.new()
	_cargo_light.position = Vector3(-0.20, 2.28 + float(tier - 1) * 0.45, -0.10)
	_cargo_light.light_color = Color(1.0, 0.96, 0.88)
	_cargo_light.omni_range = 5.2
	_cargo_light.light_energy = 0.0
	_vehicle_root.add_child(_cargo_light)

	# Sichtbare Frachtpakete im Laderaum (6 im Lieferwagen, 10 im 7,5t Kastenwagen, 14 im 18t LKW)
	var c_mat := MatLib.get_mat("cardboard")
	var box_count := 6 if tier == 1 else (10 if tier == 2 else 14)
	var floor_y := 0.86 if tier == 1 else (1.06 if tier == 2 else 1.32)
	var cols := 3 if tier == 1 else (5 if tier == 2 else 7)
	var start_x := -0.56 if tier == 1 else (-1.35 if tier == 2 else -2.10)
	for i in range(box_count):
		var col := i % cols
		var row := i / cols
		var box := _add_box(_vehicle_root, Vector3(start_x + float(col) * 0.58, floor_y + float(row) * 0.46, -0.04), Vector3(0.46, 0.40, 0.46), c_mat)
		_cargo_boxes.append(box)

	# Personal-Team erstellen (Stufe 1: 1 Fahrer, Stufe 2: 2 Mitarbeiter, Stufe 3: 3 Logistiker!)
	for r in range(staff_n):
		var ht: HandTruckScript = HandTruckScript.new()
		_vehicle_root.add_child(ht)
		_hand_trucks.append(ht)
		var dr: DeliveryDriverScript = DeliveryDriverScript.new()
		_vehicle_root.add_child(dr)
		dr.set_hand_truck(ht)
		dr.configure_worker(r, tier)
		_drivers.append(dr)
		if r == 0:
			_driver = dr
			_hand_truck = ht


func _extract_live_mat(root: Node, mat_name: String, fallback_col: Color) -> StandardMaterial3D:
	var found: StandardMaterial3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var sm := mi.mesh.surface_get_material(s)
					if sm is StandardMaterial3D and sm.resource_name == mat_name:
						if found == null:
							found = (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
							found.emission_enabled = true
						mi.set_surface_override_material(s, found)
		for c in n.get_children():
			stack.append(c)
	if found == null:
		found = _mat(fallback_col, 0.2, 0.0)
		found.emission_enabled = true
		found.emission = fallback_col
	return found
