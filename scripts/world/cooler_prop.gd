class_name CoolerProp
extends Node3D
## Detailed Modern Tech AC-1 Cooler & Industrial AC-Pro Twin-Turbine Chiller
## with spinning 6-blade rotors, coolant tank, Power Port, and 3D airflow audio.

var cooler_id: String = ""
var cooler_type: String = "cooler"
var is_showcase_only: bool = false
var _powered: bool = false

var _fan_rotors: Array[Node3D] = []
var _led_mat: StandardMaterial3D
var _status_label: Label3D
var _power_port_marker: Node3D
var _fan_audio: AudioStreamPlayer3D
var _spin_speed: float = 0.0
var _smooth_vol: float = 0.0


func setup(id: String, p_cooler_type: String = "cooler", p_showcase: bool = false) -> void:
	cooler_id = id
	cooler_type = p_cooler_type
	is_showcase_only = p_showcase
	_build_geometry()
	_setup_audio()


func apply_data(data: Dictionary) -> void:
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	_powered = bool(data.get("powered", false))

	var cooling_val := 40 if cooler_type == "chiller" else 18
	if _led_mat != null:
		_led_mat.emission = Color(0.22, 0.72, 0.38) if _powered else Color(0.18, 0.18, 0.20)
		_led_mat.emission_energy_multiplier = 0.85 if _powered else 0.05
	if _status_label != null:
		var title := "AC-PRO" if cooler_type == "chiller" else cooler_id.to_upper()
		_status_label.text = "%s\n%s (-%d°C)" % [title, tr("KÜHLT") if _powered else tr("KEIN STROM"), cooling_val]
		_status_label.modulate = Color(0.90, 0.92, 0.94) if _powered else Color(0.92, 0.76, 0.40)


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else global_position + Vector3(0.0, 1.42, 0.30)


func _setup_audio() -> void:
	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.position = Vector3(0.0, 0.90, 0.25)
	_fan_audio.stream = SfxManager.get_loop_stream("cooler_fan")
	_fan_audio.max_distance = 12.0
	_fan_audio.unit_size = 2.5
	_fan_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_fan_audio.volume_db = -60.0
	add_child(_fan_audio)


func _process(delta: float) -> void:
	var target_spin := (18.0 if cooler_type == "chiller" else 15.0) if _powered else 0.0
	_spin_speed = lerpf(_spin_speed, target_spin, clampf(delta * 3.0, 0.0, 1.0))
	if _spin_speed > 0.05:
		for r in _fan_rotors:
			r.rotation.z += delta * _spin_speed

	if _fan_audio == null or is_showcase_only:
		return
	var gain := SettingsManager.get_effective_fan_gain()
	var base_gain := 0.72 if cooler_type == "chiller" else 0.56
	var target_vol := (base_gain * gain) if (_powered and gain > 0.005) else 0.0
	_smooth_vol = lerpf(_smooth_vol, target_vol, clampf(delta * 3.2, 0.0, 1.0))
	if _smooth_vol <= 0.01:
		if _fan_audio.playing:
			_fan_audio.stop()
	else:
		if not _fan_audio.playing:
			_fan_audio.play(randf_range(0.0, 1.6))
		_fan_audio.volume_db = linear_to_db(_smooth_vol) - 7.0
		_fan_audio.pitch_scale = (0.78 if cooler_type == "chiller" else 0.88) + (_spin_speed / 18.0) * 0.26


func _build_geometry() -> void:
	var custom_m := ModelLoader.instantiate_custom_model(cooler_type)
	if custom_m != null:
		add_child(custom_m)
	var is_pro := (cooler_type == "chiller")
	var h := 1.76 if is_pro else 1.36
	var body_mat := MatLib.make_brushed_metal(Color(0.68, 0.70, 0.72) if is_pro else Color(0.84, 0.84, 0.82), 0.44, 0.22 if is_pro else 0.12)
	var trim_mat := _mat(Color(0.22, 0.24, 0.26), 0.52, 0.38)
	var dark_mat := _mat(Color(0.11, 0.12, 0.13), 0.68, 0.20)
	var copper_mat := MatLib.get_mat("copper_metal")

	if not is_showcase_only:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.78, h + 0.04, 0.64)
		col.shape = sh
		col.position = Vector3(0.0, (h + 0.04) * 0.5, 0.0)
		sb.add_child(col)
		add_child(sb)

	for fx in [-0.30, 0.30]:
		for fz in [-0.24, 0.24]:
			_add_box(self, Vector3(float(fx), 0.025, float(fz)), Vector3(0.09, 0.05, 0.09), dark_mat)

	_add_box(self, Vector3(0.0, h * 0.5 + 0.02, 0.0), Vector3(0.74, h - 0.04, 0.60), body_mat)
	_add_box(self, Vector3(-0.375, h * 0.5 + 0.02, 0.0), Vector3(0.03, h - 0.12, 0.52), trim_mat)
	_add_box(self, Vector3(0.375, h * 0.5 + 0.02, 0.0), Vector3(0.03, h - 0.12, 0.52), trim_mat)

	# Side copper refrigerant pipes (+ glowing blue coolant cylinder on Chiller Pro!)
	for pz in [-0.08, 0.08]:
		var pipe := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.022
		pc.bottom_radius = 0.022
		pc.height = h * 0.70
		pipe.mesh = pc
		pipe.material_override = copper_mat
		pipe.position = Vector3(0.40, h * 0.45, float(pz))
		add_child(pipe)

	if is_pro:
		# Realistic brushed stainless steel pressurized refrigerant receiver tank (zero neon glow!)
		var tank := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.09
		tc.bottom_radius = 0.09
		tc.height = 1.05
		tank.mesh = tc
		tank.material_override = MatLib.get_mat("galvanized_steel")
		tank.position = Vector3(-0.42, 0.84, 0.0)
		add_child(tank)
		# Brass pressure gauge dial on top of tank
		_add_box(self, Vector3(-0.42, 1.40, 0.04), Vector3(0.08, 0.08, 0.04), _mat(Color(0.90, 0.90, 0.88), 0.4, 0.1))

	# Fan assembly (1 turbine on AC-1, 2 stacked turbines on AC-Pro!)
	var fan_ys: Array[float] = [0.78]
	if is_pro:
		fan_ys = [0.56, 1.18]
	for fy in fan_ys:
		_add_box(self, Vector3(0.0, fy, 0.302), Vector3(0.56, 0.56, 0.04), dark_mat)
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.235
		torus.outer_radius = 0.265
		rim.mesh = torus
		rim.material_override = trim_mat
		rim.position = Vector3(0.0, fy, 0.335)
		rim.rotation_degrees.x = 90.0
		add_child(rim)

		var rotor := Node3D.new()
		rotor.position = Vector3(0.0, fy, 0.332)
		add_child(rotor)
		var blade_mat := _mat(Color(0.28, 0.30, 0.33), 0.42, 0.45)
		for b_i in range(3):
			var blade := _add_box(rotor, Vector3.ZERO, Vector3(0.44, 0.065, 0.022), blade_mat)
			blade.rotation_degrees.z = float(b_i) * 60.0
		var hub := MeshInstance3D.new()
		var hcyl := CylinderMesh.new()
		hcyl.top_radius = 0.052
		hcyl.bottom_radius = 0.052
		hcyl.height = 0.04
		hub.mesh = hcyl
		hub.material_override = trim_mat
		hub.rotation_degrees.x = 90.0
		rotor.add_child(hub)
		_fan_rotors.append(rotor)

	# Realistic Industrial Thermostat LCD Panel + Tiny Status LED
	var disp_y := h - 0.14
	_add_box(self, Vector3(0.0, disp_y, 0.305), Vector3(0.46, 0.11, 0.03), dark_mat)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.22, 0.65, 0.35)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.22, 0.65, 0.35)
	_led_mat.emission_energy_multiplier = 0.08
	_add_box(self, Vector3(-0.14, disp_y, 0.322), Vector3(0.14, 0.045, 0.012), _led_mat)

	# Realistic Matte Yellow Industrial IEC Power Socket (no neon emission)
	_add_box(self, Vector3(0.0, h + 0.02, 0.22), Vector3(0.26, 0.075, 0.13), dark_mat)
	var p_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	_add_box(self, Vector3(0.0, h + 0.035, 0.24), Vector3(0.18, 0.055, 0.09), p_mat)

	_power_port_marker = Node3D.new()
	_power_port_marker.position = Vector3(0.0, h + 0.06, 0.30)
	add_child(_power_port_marker)

	if not is_showcase_only:
		# Dedicated Top Power Socket interact area (Contextual 1-Hand Cable Grab!)
		var pp_area := Area3D.new()
		pp_area.collision_layer = 4
		pp_area.collision_mask = 0
		var pp_col := CollisionShape3D.new()
		var pp_sh := BoxShape3D.new()
		pp_sh.size = Vector3(0.36, 0.22, 0.28)
		pp_col.shape = pp_sh
		pp_area.position = Vector3(0.0, h + 0.04, 0.24)
		pp_area.add_child(pp_col)
		pp_area.set_meta("interact_type", "power_port")
		pp_area.set_meta("entity_id", cooler_id)
		add_child(pp_area)

		var p_area := Area3D.new()
		p_area.collision_layer = 4
		p_area.collision_mask = 0
		var p_col := CollisionShape3D.new()
		var p_sh := BoxShape3D.new()
		p_sh.size = Vector3(0.80, h - 0.08, 0.72)
		p_col.shape = p_sh
		p_area.position = Vector3(0.0, (h - 0.08) * 0.5, 0.02)
		p_area.add_child(p_col)
		p_area.set_meta("interact_type", "cooler_unit")
		p_area.set_meta("entity_id", cooler_id)
		add_child(p_area)

	_status_label = Label3D.new()
	_status_label.text = cooler_id.to_upper()
	_status_label.font_size = 24
	_status_label.pixel_size = 0.0042
	_status_label.position = Vector3(0.0, h + 0.28, 0.15)
	add_child(_status_label)


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
