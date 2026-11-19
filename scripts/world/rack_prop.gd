class_name RackProp
extends Node3D
## v0.6 Realistic 19-inch Industrial Server Rack (4U / 6U Pro).
## Zero neon — matte powder-coated steel cabinet, silver mounting rails, clear side glass,
## spinning roof exhaust fans, rear PDU strip, and REAL live-upgradable 3D server internals
## (Motherboard PCB, CPU + Cooler, GPU Card, RAM DIMMs, M.2 NVMe SSDs, Fan Wall & PSU)
## built via HardwareMeshFactory!

var rack_id: String = ""
var rack_type: String = "rack"
var slot_count: int = 4
var is_showcase_only: bool = false
var _rack_data: Dictionary = {}

var _power_port_marker: Node3D
var _net_port_marker: Node3D
var _power_led_mat: StandardMaterial3D
var _net_led_mat: StandardMaterial3D
var _header_label: Label3D
var _fan_audio: AudioStreamPlayer3D
var _fire_light: OmniLight3D
var _roof_fans: Array[Node3D] = []

var _slot_visuals: Array = []
var _anim_time: float = 0.0
var _smooth_fan_level: float = 0.0
var _smooth_fan_pitch: float = 0.9


func setup(id: String, p_rack_type: String = "rack", p_showcase: bool = false) -> void:
	rack_id = id
	rack_type = p_rack_type
	slot_count = 6 if rack_type == "rack_pro" else 4
	is_showcase_only = p_showcase
	_build_rack_geometry()
	_setup_fan_audio()
	SettingsManager.settings_changed.connect(_apply_graphics_setting)
	_apply_graphics_setting()


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else global_position + Vector3(0.0, 2.02, 0.49)


func get_net_port_global_pos() -> Vector3:
	return _net_port_marker.global_position if _net_port_marker != null else global_position + Vector3(0.0, 2.02, 0.49)


func apply_data(data: Dictionary) -> void:
	_rack_data = data
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	_refresh_visuals()


func _apply_graphics_setting() -> void:
	if _fire_light != null:
		_fire_light.visible = (SettingsManager.graphics_quality >= 1)


func _setup_fan_audio() -> void:
	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.position = Vector3(0.0, 1.15, 0.0)
	_fan_audio.stream = SfxManager.get_loop_stream("server_fan")
	_fan_audio.max_distance = 12.0
	_fan_audio.unit_size = 2.6
	_fan_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_fan_audio.volume_db = -60.0
	add_child(_fan_audio)


func _process(delta: float) -> void:
	_anim_time += delta
	if _rack_data.is_empty():
		return

	var powered := bool(_rack_data.get("powered", false))
	var networked := bool(_rack_data.get("networked", false))
	var temp := float(_rack_data.get("temp", 22.0))
	var slots: Array = _rack_data.get("slots", [])

	if powered:
		var rspeed := 8.0 + clampf((temp - 22.0) * 0.28, 0.0, 16.0)
		for rf in _roof_fans:
			rf.rotation.y += delta * rspeed

	var active_servers := 0
	var gpu_weight := 0.0
	var has_fire := false

	for i in range(mini(slots.size(), _slot_visuals.size())):
		var slot: Dictionary = slots[i]
		var vis: Dictionary = _slot_visuals[i]
		var item_type := str(slot["item_type"])
		var st := str(slot["state"])
		var led_mat: StandardMaterial3D = vis["led_mat"]
		var act_mat: StandardMaterial3D = vis["act_mat"]
		var fire_root: Node3D = vis["fire_root"]

		if item_type == "":
			continue

		var running := powered and st == "ok"
		if running:
			active_servers += 1
			var comps: Dictionary = slot.get("components", {})
			var gpu_lvl := HardwareMeshFactory.get_visual_tier(comps, "gpu")
			gpu_weight += (1.5 if item_type == "gpu_server" else (0.45 if item_type == "net_switch" else 0.85)) + float(gpu_lvl) * 0.35

			var speed := 11.0 + clampf((temp - 25.0) * 0.35, 0.0, 22.0)
			var hw_fans: Array = vis["hw_fans"]
			for fan_node in hw_fans:
				if is_instance_valid(fan_node):
					var fnode := fan_node as Node3D
					if str(fnode.get_meta("spin_axis", "z")) == "x":
						fnode.rotation.x += delta * speed
					else:
						fnode.rotation.z += delta * speed

		if st == "burning":
			has_fire = true
			led_mat.emission = Color(0.95, 0.16, 0.08)
			led_mat.emission_energy_multiplier = 1.2 + 0.6 * sin(_anim_time * 18.0)
			act_mat.emission_energy_multiplier = 0.02
			fire_root.visible = true
			var flames: Array = vis["flames"]
			for f_idx in range(flames.size()):
				var fm: MeshInstance3D = flames[f_idx]
				var phase := _anim_time * 9.0 + float(f_idx) * 1.9
				fm.position.y = 0.04 + fmod(phase * 0.12, 0.34)
				var sc := 0.75 + 0.35 * sin(phase * 1.6)
				fm.scale = Vector3(sc, sc * 1.3, sc)
		else:
			fire_root.visible = false
			if st == "crashed":
				led_mat.emission = Color(0.92, 0.16, 0.14)
				led_mat.emission_energy_multiplier = 1.0 if sin(_anim_time * 10.0) > 0.0 else 0.06
				act_mat.emission_energy_multiplier = 0.02
			elif not powered:
				led_mat.emission = Color(0.15, 0.15, 0.16)
				led_mat.emission_energy_multiplier = 0.02
				act_mat.emission_energy_multiplier = 0.02
			elif temp >= 68.0:
				led_mat.emission = Color(0.95, 0.65, 0.12)
				led_mat.emission_energy_multiplier = 0.90 + 0.35 * sin(_anim_time * 8.0 + float(i))
				act_mat.emission = Color(0.92, 0.55, 0.12)
				act_mat.emission_energy_multiplier = 0.75 if sin(_anim_time * 16.0 + float(i) * 2.3) > 0.0 else 0.08
			elif not networked and item_type != "net_switch":
				led_mat.emission = Color(0.90, 0.58, 0.16)
				led_mat.emission_energy_multiplier = 0.72
				act_mat.emission_energy_multiplier = 0.04
			else:
				# Crisp, subtle realistic server status & disk/NIC pinpoint LEDs (zero neon bloom!)
				led_mat.emission = Color(0.22, 0.78, 0.38)
				led_mat.emission_energy_multiplier = 0.78
				var traffic := sin(_anim_time * (18.0 + float(i) * 5.3)) * cos(_anim_time * 11.7 + float(i))
				act_mat.emission = Color(0.92, 0.68, 0.18)
				act_mat.emission_energy_multiplier = 0.85 if traffic > 0.18 else 0.06

	# Light ONLY emits warm orange glow when a server is actively burning (no idle neon floor glow!)
	if _fire_light != null and _fire_light.visible:
		if has_fire:
			_fire_light.light_color = Color(1.0, 0.42, 0.12)
			_fire_light.light_energy = 1.5 + 0.45 * sin(_anim_time * 16.0)
		else:
			_fire_light.light_energy = 0.0

	_update_fan_audio(delta, active_servers, gpu_weight, temp)


func _update_fan_audio(delta: float, active_servers: int, gpu_weight: float, temp: float) -> void:
	if _fan_audio == null or is_showcase_only:
		return

	var fan_gain := SettingsManager.get_effective_fan_gain()
	var target_level := 0.0
	var target_pitch := 0.86

	if active_servers > 0 and fan_gain > 0.005:
		var load_factor := clampf(gpu_weight / 4.8, 0.22, 1.0)
		var heat_factor := clampf((temp - 22.0) / 55.0, 0.0, 1.0)
		target_level = clampf((0.26 + load_factor * 0.42 + heat_factor * 0.34) * fan_gain, 0.0, 1.0)
		target_pitch = clampf(0.84 + load_factor * 0.24 + heat_factor * 0.56, 0.80, 1.65)

	_smooth_fan_level = lerpf(_smooth_fan_level, target_level, clampf(delta * 3.5, 0.0, 1.0))
	_smooth_fan_pitch = lerpf(_smooth_fan_pitch, target_pitch, clampf(delta * 2.8, 0.0, 1.0))

	if _smooth_fan_level <= 0.01:
		if _fan_audio.playing:
			_fan_audio.stop()
	else:
		if not _fan_audio.playing:
			_fan_audio.play(randf_range(0.0, 1.8))
		_fan_audio.volume_db = linear_to_db(_smooth_fan_level) - 6.0
		_fan_audio.pitch_scale = _smooth_fan_pitch


func _refresh_visuals() -> void:
	var powered := bool(_rack_data.get("powered", false))
	var networked := bool(_rack_data.get("networked", false))
	var temp := float(_rack_data.get("temp", 22.0))
	var slots: Array = _rack_data.get("slots", [])

	if _power_led_mat != null:
		_power_led_mat.emission = Color(0.24, 0.78, 0.38) if powered else Color(0.18, 0.18, 0.18)
		_power_led_mat.emission_energy_multiplier = 0.80 if powered else 0.04

	if _net_led_mat != null:
		_net_led_mat.emission = Color(0.24, 0.78, 0.38) if networked else Color(0.18, 0.18, 0.18)
		_net_led_mat.emission_energy_multiplier = 0.80 if networked else 0.04

	var used_slots := 0
	var rack_ram_gb := 0
	for i in range(mini(slots.size(), _slot_visuals.size())):
		var slot: Dictionary = slots[i]
		var vis: Dictionary = _slot_visuals[i]
		var item_type := str(slot["item_type"])
		var empty_mesh: Node3D = vis["empty_root"]
		var hw_holder: Node3D = vis["hw_holder"]
		var led_pod: Node3D = vis["led_pod"]
		var slot_lbl: Label3D = vis["slot_lbl"]

		if item_type == "":
			empty_mesh.visible = true
			hw_holder.visible = false
			led_pod.visible = false
			vis["fire_root"].visible = false
			if str(vis["hw_sig"]) != "":
				_clear_children(hw_holder)
				(vis["hw_fans"] as Array).clear()
				vis["hw_sig"] = ""
			slot_lbl.text = "SLOT %d [LEER]" % (i + 1)
			slot_lbl.modulate = Color(0.68, 0.70, 0.72)
		else:
			used_slots += 1
			empty_mesh.visible = false
			hw_holder.visible = true
			led_pod.visible = true

			var comps: Dictionary = slot.get("components", {})
			var sig := "%s:%s:%s:%s:%s:%s:%s" % [
				item_type,
				str(comps.get("cpu", "")),
				str(comps.get("gpu", "")),
				str(comps.get("ram", "")),
				str(comps.get("storage", "")),
				str(comps.get("cooling", "")),
				str(comps.get("psu", "")),
			]
			if str(vis["hw_sig"]) != sig:
				_clear_children(hw_holder)
				var fans: Array = vis["hw_fans"]
				fans.clear()
				var srv_mesh := HardwareMeshFactory.build_open_server_chassis(item_type, comps, fans)
				srv_mesh.position = Vector3(0.0, -0.095, 0.04)
				hw_holder.add_child(srv_mesh)
				vis["hw_sig"] = sig

			var stats := GameState.get_slot_stats(slot)
			rack_ram_gb += int(stats.get("ram_gb", 0))
			var cat: Dictionary = GameState.ITEM_CATALOG[item_type]
			var st := str(slot["state"])
			if st == "burning":
				slot_lbl.text = "BRAND! (%.0f%%)" % (float(slot["fire_level"]) * 100.0)
				slot_lbl.modulate = Color(0.98, 0.34, 0.16)
			elif st == "crashed":
				var rp := float(slot["repair_progress"]) * 100.0
				slot_lbl.text = "DEFEKT [E] %.0f%%" % rp
				slot_lbl.modulate = Color(0.96, 0.34, 0.30)
			else:
				var up_tag := _get_upgrade_badge(slot)
				slot_lbl.text = "%s%s" % [str(cat["name"]), up_tag]
				slot_lbl.modulate = Color(0.92, 0.93, 0.94)

	if _header_label != null:
		var pwr_txt := "PWR:ON" if powered else "PWR:OFF"
		var net_txt := "NET:OK" if networked else "NET:NO"
		var pro_tag := " PRO" if rack_type == "rack_pro" else ""
		var rtype_rent := str(_rack_data.get("rental_type", "none"))
		var rent_line := "%s  %s  %.0f°C  [E] Overlay" % [pwr_txt, net_txt, temp]
		if rtype_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(rtype_rent):
			var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rtype_rent]
			var users := int(_rack_data.get("active_users", 0))
			var m: Dictionary = _rack_data.get("metrics", {})
			var bneck := str(m.get("bottleneck", "ok"))
			var warn_tag := (" ⚠" + bneck.to_upper()) if bneck != "ok" else ""
			rent_line = "%s %s • %d User%s • %.0f°C" % [str(prof["icon"]), str(prof["short"]), users, warn_tag, temp]
		_header_label.text = "%s%s | %d/%d (%d GB RAM)\n%s" % [
			rack_id.to_upper(), pro_tag, used_slots, slot_count, rack_ram_gb, rent_line
		]
		var bm := str((_rack_data.get("metrics", {}) as Dictionary).get("bottleneck", "ok"))
		if temp >= 75.0 or (rtype_rent != "none" and bm != "ok"):
			_header_label.modulate = Color(0.96, 0.32, 0.22)
		elif powered and networked:
			_header_label.modulate = Color(0.20, 0.22, 0.24)
		else:
			_header_label.modulate = Color(0.74, 0.50, 0.12)


func _get_upgrade_badge(slot: Dictionary) -> String:
	var stats := GameState.get_slot_stats(slot)
	var ram_gb := int(stats.get("ram_gb", 0))
	var ram_tag := str(stats.get("ram_tag", ""))
	if ram_gb <= 0:
		return ""
	return " [%dGB %s]" % [ram_gb, ram_tag]


func _build_rack_geometry() -> void:
	var is_pro := (rack_type == "rack_pro")
	var total_h := 2.48 if is_pro else 2.12
	var top_y := total_h - 0.08
	var slot_step := 0.35 if is_pro else 0.40
	var first_slot_y := 0.38 if is_pro else 0.44

	var frame_mat := MatLib.make_brushed_metal(Color(0.15, 0.16, 0.17), 0.42, 0.58)
	var steel_mat := MatLib.get_mat("galvanized_steel")
	var side_mat := MatLib.make_brushed_metal(Color(0.20, 0.21, 0.23), 0.48, 0.46)
	var dark_mat := _mat(Color(0.10, 0.11, 0.12), 0.68, 0.20)
	var perf_mat := MatLib.get_mat("perforated_mesh")
	var glass := MatLib.get_mat("smoked_glass")

	if not is_showcase_only:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.86, total_h - 0.04, 0.84)
		col.shape = shape
		col.position = Vector3(0.0, (total_h - 0.04) * 0.5, -0.02)
		body.add_child(col)
		add_child(body)

	# 4 Industrial Rubber Leveling Feet + Caster Brackets
	for fx in [-0.38, 0.38]:
		for fz in [-0.38, 0.38]:
			_add_box(self, Vector3(float(fx), 0.025, float(fz)), Vector3(0.085, 0.05, 0.085), dark_mat)

	# Optional custom external .glb visual shell override (assets/models/rack.glb or rack_pro.glb)
	var custom_shell := ModelLoader.instantiate_custom_model(rack_type)
	if custom_shell != null:
		add_child(custom_shell)

	# Base Plinth, Roof Cap & Twin Spinning Roof Exhaust Fans under Perforated Grilles
	_add_box(self, Vector3(0.0, 0.10, 0.0), Vector3(0.92, 0.14, 0.92), frame_mat)
	_add_box(self, Vector3(0.0, top_y, 0.0), Vector3(0.92, 0.16, 0.92), frame_mat)
	for rx in [-0.20, 0.20]:
		_add_box(self, Vector3(float(rx), top_y + 0.085, -0.05), Vector3(0.32, 0.02, 0.48), perf_mat)
		var rf := Node3D.new()
		rf.position = Vector3(float(rx), top_y + 0.098, -0.05)
		add_child(rf)
		_add_box(rf, Vector3.ZERO, Vector3(0.24, 0.015, 0.042), steel_mat)
		_add_box(rf, Vector3.ZERO, Vector3(0.042, 0.015, 0.24), steel_mat)
		_roof_fans.append(rf)

	# 4 Vertical Heavy-Gauge Corner Posts + Real 19-Inch Silver Slotted Mounting Rails
	var post_h := total_h - 0.24
	var mid_y := 0.16 + post_h * 0.5
	for px in [-0.42, 0.42]:
		for pz in [-0.42, 0.42]:
			_add_box(self, Vector3(float(px), mid_y, float(pz)), Vector3(0.068, post_h, 0.068), frame_mat)
		# Silver 19-inch front & rear mounting rails (zero neon!)
		_add_box(self, Vector3(float(px) * 0.91, mid_y, 0.37), Vector3(0.030, post_h - 0.06, 0.024), steel_mat)
		_add_box(self, Vector3(float(px) * 0.91, mid_y, -0.37), Vector3(0.028, post_h - 0.06, 0.022), steel_mat)

	# Pro Cabinet Brushed Aluminum Edge Trim (no neon!)
	if is_pro:
		_add_box(self, Vector3(-0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)
		_add_box(self, Vector3(0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)

	# Clear Glass Side Inspection Windows framed in charcoal steel so you see the REAL 3D Server Hardware inside!
	_add_box(self, Vector3(-0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
	_add_box(self, Vector3(0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
	# Rear perforated airflow door + Rear Vertical PDU Power Strip
	_add_box(self, Vector3(0.0, mid_y, -0.43), Vector3(0.78, post_h - 0.08, 0.026), perf_mat)
	_add_box(self, Vector3(0.32, mid_y, -0.452), Vector3(0.082, post_h - 0.22, 0.042), side_mat)
	_add_box(self, Vector3(0.32, mid_y + 0.55, -0.476), Vector3(0.038, 0.052, 0.016), _mat(Color(0.78, 0.18, 0.14), 0.42, 0.15))

	# Fire-only dynamic light
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, mid_y, 0.78)
	_fire_light.omni_range = 3.2
	_fire_light.light_energy = 0.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)

	# Realistic Matte Yellow Power IEC Receptacle Pod (Left) + Pinpoint Status LED
	_add_box(self, Vector3(-0.27, top_y, 0.445), Vector3(0.24, 0.12, 0.055), dark_mat)
	_add_box(self, Vector3(-0.29, top_y, 0.470), Vector3(0.12, 0.065, 0.032), _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08))
	_power_led_mat = StandardMaterial3D.new()
	_power_led_mat.albedo_color = Color(0.24, 0.78, 0.38)
	_power_led_mat.emission_enabled = true
	_power_led_mat.emission = Color(0.24, 0.78, 0.38)
	_power_led_mat.emission_energy_multiplier = 0.04
	_add_box(self, Vector3(-0.18, top_y, 0.474), Vector3(0.024, 0.024, 0.016), _power_led_mat)

	_power_port_marker = Node3D.new()
	_power_port_marker.position = Vector3(-0.27, top_y, 0.50)
	add_child(_power_port_marker)

	if not is_showcase_only:
		var p_area := _make_area(Vector3(0.32, 0.24, 0.22), {
			"interact_type": "power_port",
			"entity_id": rack_id,
		})
		p_area.position = Vector3(-0.27, top_y, 0.46)
		add_child(p_area)

	# Realistic Matte Blue Network RJ45 Patch Pod (Right) + Pinpoint Link LED
	_add_box(self, Vector3(0.27, top_y, 0.445), Vector3(0.24, 0.12, 0.055), dark_mat)
	_add_box(self, Vector3(0.25, top_y, 0.470), Vector3(0.12, 0.065, 0.032), _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22))
	_net_led_mat = StandardMaterial3D.new()
	_net_led_mat.albedo_color = Color(0.24, 0.78, 0.38)
	_net_led_mat.emission_enabled = true
	_net_led_mat.emission = Color(0.24, 0.78, 0.38)
	_net_led_mat.emission_energy_multiplier = 0.04
	_add_box(self, Vector3(0.36, top_y, 0.474), Vector3(0.024, 0.024, 0.016), _net_led_mat)

	_net_port_marker = Node3D.new()
	_net_port_marker.position = Vector3(0.27, top_y, 0.50)
	add_child(_net_port_marker)

	if not is_showcase_only:
		var n_area := _make_area(Vector3(0.32, 0.24, 0.22), {
			"interact_type": "net_port",
			"entity_id": rack_id,
		})
		n_area.position = Vector3(0.27, top_y, 0.46)
		add_child(n_area)

	_header_label = Label3D.new()
	_header_label.text = rack_id.to_upper()
	_header_label.font_size = 24
	_header_label.pixel_size = 0.0040
	_header_label.position = Vector3(0.0, top_y + 0.28, 0.32)
	add_child(_header_label)

	# Build 4 or 6 Open-View Server Bays (each dynamically hosts REAL 3D Server Hardware!)
	for i in range(slot_count):
		var sy := first_slot_y + float(i) * slot_step
		var slot_root := Node3D.new()
		slot_root.position = Vector3(0.0, sy, 0.0)
		add_child(slot_root)

		var empty_root := Node3D.new()
		slot_root.add_child(empty_root)
		_add_box(empty_root, Vector3(-0.36, -0.095, 0.0), Vector3(0.045, 0.026, 0.74), steel_mat)
		_add_box(empty_root, Vector3(0.36, -0.095, 0.0), Vector3(0.045, 0.026, 0.74), steel_mat)
		var shelf_mat := StandardMaterial3D.new()
		shelf_mat.albedo_color = Color(0.28, 0.30, 0.32, 0.32)
		shelf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_add_box(empty_root, Vector3(0.0, -0.105, 0.0), Vector3(0.68, 0.016, 0.72), shelf_mat)

		var hw_holder := Node3D.new()
		hw_holder.visible = false
		slot_root.add_child(hw_holder)

		# Subtle pinpoint server LEDs mounted on front-right rack ear
		var led_mat := StandardMaterial3D.new()
		led_mat.albedo_color = Color(0.24, 0.78, 0.38)
		led_mat.emission_enabled = true
		led_mat.emission = Color(0.24, 0.78, 0.38)
		led_mat.emission_energy_multiplier = 0.75

		var act_mat := StandardMaterial3D.new()
		act_mat.albedo_color = Color(0.92, 0.68, 0.18)
		act_mat.emission_enabled = true
		act_mat.emission = Color(0.92, 0.68, 0.18)
		act_mat.emission_energy_multiplier = 0.55

		var led_pod := Node3D.new()
		led_pod.visible = false
		slot_root.add_child(led_pod)
		_add_box(led_pod, Vector3(0.345, -0.005, 0.415), Vector3(0.018, 0.018, 0.012), led_mat)
		_add_box(led_pod, Vector3(0.345, -0.036, 0.415), Vector3(0.018, 0.014, 0.012), act_mat)

		var fire_root := Node3D.new()
		fire_root.position = Vector3(0.0, 0.04, 0.45)
		fire_root.visible = false
		slot_root.add_child(fire_root)

		var flames: Array = []
		for f in range(5):
			var fm := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.09 if f < 3 else 0.11
			sm.height = sm.radius * 2.0
			fm.mesh = sm
			var fmat := StandardMaterial3D.new()
			if f < 3:
				fmat.albedo_color = Color(1.0, 0.42, 0.08)
				fmat.emission_enabled = true
				fmat.emission = Color(1.0, 0.38, 0.05)
				fmat.emission_energy_multiplier = 2.6
			else:
				fmat.albedo_color = Color(0.18, 0.18, 0.20, 0.75)
				fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.material_override = fmat
			fm.position = Vector3((float(f) - 2.0) * 0.11, 0.05, 0.04)
			fire_root.add_child(fm)
			flames.append(fm)

		var slot_lbl := Label3D.new()
		slot_lbl.text = "SLOT %d" % (i + 1)
		slot_lbl.font_size = 15
		slot_lbl.pixel_size = 0.0028
		slot_lbl.position = Vector3(-0.08, 0.095, 0.445)
		slot_root.add_child(slot_lbl)

		if not is_showcase_only:
			var s_area := _make_area(Vector3(0.78, slot_step - 0.04, 0.22), {
				"interact_type": "rack_slot",
				"entity_id": rack_id,
				"slot_index": i,
			})
			s_area.position = Vector3(0.0, 0.0, 0.44)
			slot_root.add_child(s_area)

		_slot_visuals.append({
			"empty_root": empty_root,
			"hw_holder": hw_holder,
			"hw_fans": [],
			"hw_sig": "",
			"led_pod": led_pod,
			"led_mat": led_mat,
			"act_mat": act_mat,
			"fire_root": fire_root,
			"flames": flames,
			"slot_lbl": slot_lbl,
		})


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


func _make_area(size: Vector3, meta: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	for k in meta.keys():
		area.set_meta(k, meta[k])
	return area


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
