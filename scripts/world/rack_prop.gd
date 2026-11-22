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
var _cluster_port_marker: Node3D
var _cluster_led_mat: StandardMaterial3D
var _header_label: Label3D
var _fan_audio: AudioStreamPlayer3D
var _fire_light: OmniLight3D
var _roof_fans: Array[Node3D] = []
## Bewegliche Teile aus dem Blender-Modell: panel_id -> {node, kind, closed, open, is_open, tween}
var _panels: Dictionary = {}

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
	if not is_showcase_only:
		# Türzustand kommt vom Server, damit alle Spieler dieselben offenen Türen sehen
		_apply_synced_panel_states(false)
		if not GameState.panel_states_changed.is_connected(_on_panel_states_changed):
			GameState.panel_states_changed.connect(_on_panel_states_changed)
	_setup_fan_audio()
	SettingsManager.settings_changed.connect(_apply_graphics_setting)
	_apply_graphics_setting()


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else to_global(Vector3(0.0, 2.02, -0.49))


func get_net_port_global_pos() -> Vector3:
	return _net_port_marker.global_position if _net_port_marker != null else to_global(Vector3(0.0, 2.02, -0.49))


func get_cluster_port_global_pos() -> Vector3:
	return _cluster_port_marker.global_position if _cluster_port_marker != null else to_global(Vector3(0.0, 2.02, -0.49))


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
			var chassis := GameState.get_chassis_visual(item_type)
			gpu_weight += (1.5 if chassis == "gpu_server" else (0.45 if item_type == "net_switch" else 0.85)) + float(gpu_lvl) * 0.35

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

	if _cluster_led_mat != null:
		var clustered := bool(_rack_data.get("clustered", false))
		_cluster_led_mat.emission = Color(0.62, 0.38, 0.92) if clustered else Color(0.18, 0.18, 0.18)
		_cluster_led_mat.emission_energy_multiplier = 0.80 if clustered else 0.04

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
			slot_lbl.text = tr("SLOT %d [LEER]") % (i + 1)
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
				slot_lbl.text = tr("BRAND! (%.0f%%)") % (float(slot["fire_level"]) * 100.0)
				slot_lbl.modulate = Color(0.98, 0.34, 0.16)
			elif st == "crashed":
				var rp := float(slot["repair_progress"]) * 100.0
				slot_lbl.text = tr("DEFEKT [E] %.0f%%") % rp
				slot_lbl.modulate = Color(0.96, 0.34, 0.30)
			else:
				var up_tag := _get_upgrade_badge(slot)
				slot_lbl.text = "%s%s" % [tr(str(cat["name"])), up_tag]
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
			rent_line = tr("%s %s • %d User%s • %.0f°C") % [str(prof["icon"]), tr(str(prof["short"])), users, warn_tag, temp]
		_header_label.text = "%s%s | %d/%d (%d GB RAM)\n%s" % [
			GameState.get_rack_display_name(rack_id), pro_tag, used_slots, slot_count, rack_ram_gb, rent_line
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

	var plastic_mat := MatLib.get_mat("plastic_black")
	# Blender-Modell (assets/models/rack.glb bzw. rack_pro.glb) ersetzt das prozedurale Rack.
	var custom_shell := ModelLoader.instantiate_custom_model(rack_type)
	var use_procedural_shell := custom_shell == null
	if custom_shell != null:
		add_child(custom_shell)
		_setup_custom_shell(custom_shell, total_h)
	var post_h := total_h - 0.24
	var mid_y := 0.16 + post_h * 0.5

	if use_procedural_shell:
		# 4 Lenkrollen mit Gabel und daneben je ein Stellfuß mit Gummiteller
		for fx in [-0.38, 0.38]:
			for fz in [-0.38, 0.38]:
				var cx := float(fx)
				var cz := float(fz)
				_limit_detail_range(_add_box(self, Vector3(cx, 0.048, cz), Vector3(0.070, 0.008, 0.070), steel_mat))
				_limit_detail_range(_add_box(self, Vector3(cx - 0.018, 0.030, cz), Vector3(0.006, 0.030, 0.036), steel_mat))
				_limit_detail_range(_add_box(self, Vector3(cx + 0.018, 0.030, cz), Vector3(0.006, 0.030, 0.036), steel_mat))
				var wheel := _add_cyl(self, Vector3(cx, 0.022, cz), 0.022, 0.026, plastic_mat)
				_limit_detail_range(wheel)
				wheel.rotation_degrees.z = 90.0
				_limit_detail_range(_add_cyl(self, Vector3(cx * 0.80, 0.020, cz * 0.80), 0.006, 0.030, steel_mat))
				_limit_detail_range(_add_cyl(self, Vector3(cx * 0.80, 0.004, cz * 0.80), 0.018, 0.008, dark_mat))

		# Base Plinth, Roof Cap & Twin Spinning Roof Exhaust Fans under Perforated Grilles
		_add_box(self, Vector3(0.0, 0.10, 0.0), Vector3(0.92, 0.14, 0.92), frame_mat)
		_add_box(self, Vector3(0.0, top_y, 0.0), Vector3(0.92, 0.16, 0.92), frame_mat)
		# Lüftungsschlitze vorne im Sockel
		var vent_parts: Array = []
		for v in range(12):
			vent_parts.append([Vector3(-0.33 + float(v) * 0.06, 0.0, 0.0), Vector3(0.036, 0.060, 0.006)])
		var plinth_vents := HardwareMeshFactory.merged_boxes(self, "rack_plinth_vents", vent_parts, dark_mat)
		plinth_vents.position = Vector3(0.0, 0.10, 0.461)
		# Kabeleinführung mit Bürstenleiste vorne im Dach
		_add_box(self, Vector3(0.0, top_y + 0.084, 0.31), Vector3(0.46, 0.014, 0.07), dark_mat)
		_add_box(self, Vector3(0.0, top_y + 0.092, 0.31), Vector3(0.44, 0.004, 0.012), plastic_mat)
		# Zwei Abluftlüfter im Dach: Lochblech, dunkle Lüfterkammer, drehendes Lüfterrad, Schutzgitter
		var fan_blade_mat := MatLib.make_brushed_metal(Color(0.17, 0.18, 0.20), 0.60, 0.15)
		var fan_shade := MatLib.make_brushed_metal(Color(0.05, 0.05, 0.06), 0.85, 0.0)
		var roof_guard_parts: Array = [
			[Vector3(0.0, 0.0, -0.13), Vector3(0.27, 0.006, 0.008)],
			[Vector3(0.0, 0.0, 0.13), Vector3(0.27, 0.006, 0.008)],
			[Vector3(-0.13, 0.0, 0.0), Vector3(0.008, 0.006, 0.27)],
			[Vector3(0.13, 0.0, 0.0), Vector3(0.008, 0.006, 0.27)],
			[Vector3(0.0, 0.0, -0.065), Vector3(0.26, 0.004, 0.004)],
			[Vector3(0.0, 0.0, 0.0), Vector3(0.26, 0.004, 0.004)],
			[Vector3(0.0, 0.0, 0.065), Vector3(0.26, 0.004, 0.004)],
			[Vector3(-0.065, 0.0, 0.0), Vector3(0.004, 0.004, 0.26)],
			[Vector3(0.0, 0.0, 0.0), Vector3(0.004, 0.004, 0.26)],
			[Vector3(0.065, 0.0, 0.0), Vector3(0.004, 0.004, 0.26)],
		]
		for rx in [-0.20, 0.20]:
			var fx := float(rx)
			_add_box(self, Vector3(fx, top_y + 0.085, -0.05), Vector3(0.32, 0.02, 0.48), perf_mat)
			_add_cyl(self, Vector3(fx, top_y + 0.097, -0.05), 0.125, 0.004, fan_shade)
			_add_cyl(self, Vector3(fx, top_y + 0.101, -0.05), 0.040, 0.012, plastic_mat)
			var rf := Node3D.new()
			rf.position = Vector3(fx, top_y + 0.112, -0.05)
			add_child(rf)
			# Die Blätter liegen waagerecht, gedreht wird in _process um die Y-Achse.
			var blade_holder := Node3D.new()
			blade_holder.rotation_degrees.x = -90.0
			rf.add_child(blade_holder)
			HardwareMeshFactory.fan_blades(blade_holder, 0.115, 7, fan_blade_mat, steel_mat)
			_roof_fans.append(rf)
			var roof_guard := HardwareMeshFactory.merged_boxes(self, "rack_roof_guard", roof_guard_parts, steel_mat)
			roof_guard.position = Vector3(fx, top_y + 0.128, -0.05)

		# 4 Vertical Heavy-Gauge Corner Posts + Real 19-Inch Silver Slotted Mounting Rails
		for px in [-0.42, 0.42]:
			for pz in [-0.42, 0.42]:
				_add_box(self, Vector3(float(px), mid_y, float(pz)), Vector3(0.068, post_h, 0.068), frame_mat)
			# Silver 19-inch front & rear mounting rails (zero neon!)
			_add_box(self, Vector3(float(px) * 0.91, mid_y, 0.37), Vector3(0.030, post_h - 0.06, 0.024), steel_mat)
			_add_box(self, Vector3(float(px) * 0.91, mid_y, -0.37), Vector3(0.028, post_h - 0.06, 0.022), steel_mat)
			# Vierkantlöcher im 1-HE-Raster (44,45 mm) auf der vorderen Schiene
			var rail_len := post_h - 0.10
			var hole_count := int(rail_len / 0.04445)
			var hole_parts: Array = []
			for h in range(hole_count):
				hole_parts.append([Vector3(0.0, -rail_len * 0.5 + (float(h) + 0.5) * 0.04445, 0.0), Vector3(0.010, 0.010, 0.004)])
			var holes := HardwareMeshFactory.merged_boxes(self, "rack_rail_holes_%d" % hole_count, hole_parts, dark_mat)
			holes.position = Vector3(float(px) * 0.91, mid_y, 0.3825)

		# Pro Cabinet Brushed Aluminum Edge Trim (no neon!)
		if is_pro:
			_add_box(self, Vector3(-0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)
			_add_box(self, Vector3(0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)

		# Clear Glass Side Inspection Windows framed in charcoal steel so you see the REAL 3D Server Hardware inside!
		_add_box(self, Vector3(-0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
		_add_box(self, Vector3(0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
		# Stahlrahmen um die Seitenfenster und Schloss mit Griffmulde
		var glass_h := post_h - 0.22
		var window_frame_parts: Array = [
			[Vector3(0.0, glass_h * 0.5, 0.0), Vector3(0.006, 0.030, 0.70)],
			[Vector3(0.0, -glass_h * 0.5, 0.0), Vector3(0.006, 0.030, 0.70)],
			[Vector3(0.0, 0.0, 0.34), Vector3(0.006, glass_h, 0.030)],
			[Vector3(0.0, 0.0, -0.34), Vector3(0.006, glass_h, 0.030)],
		]
		for side in [-1.0, 1.0]:
			var sx := float(side)
			var wf := HardwareMeshFactory.merged_boxes(self, "rack_window_frame_%.3f" % glass_h, window_frame_parts, side_mat)
			wf.position = Vector3(sx * 0.440, mid_y, 0.0)
			_limit_detail_range(_add_box(self, Vector3(sx * 0.444, mid_y, 0.30), Vector3(0.006, 0.090, 0.022), dark_mat))
			var lock := _add_cyl(self, Vector3(sx * 0.448, mid_y + 0.065, 0.30), 0.007, 0.006, steel_mat)
			_limit_detail_range(lock)
			lock.rotation_degrees.z = 90.0
		# Rear perforated airflow door + Rear Vertical PDU Power Strip
		_add_box(self, Vector3(0.0, mid_y, -0.43), Vector3(0.78, post_h - 0.08, 0.026), perf_mat)
		# Schwenkgriff und Scharniere an der hinteren Tür
		_limit_detail_range(_add_box(self, Vector3(-0.33, mid_y, -0.448), Vector3(0.026, 0.16, 0.010), dark_mat))
		_limit_detail_range(_add_box(self, Vector3(-0.33, mid_y + 0.03, -0.456), Vector3(0.012, 0.07, 0.008), steel_mat))
		for hy in [0.30, 0.70]:
			_limit_detail_range(_add_cyl(self, Vector3(0.392, 0.16 + post_h * float(hy), -0.446), 0.008, 0.06, steel_mat))
		_add_box(self, Vector3(0.32, mid_y, -0.452), Vector3(0.082, post_h - 0.22, 0.042), side_mat)
		_limit_detail_range(_add_box(self, Vector3(0.32, mid_y + 0.55, -0.476), Vector3(0.038, 0.052, 0.016), _mat(Color(0.78, 0.18, 0.14), 0.42, 0.15)))

	# Fire-only dynamic light
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, mid_y, 0.78)
	_fire_light.omni_range = 3.2
	_fire_light.light_energy = 0.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)

	# Anschlüsse sitzen oben an der Rückseite (-Z), damit die Kabel hinter dem Rack verlaufen.
	# Realistic Matte Yellow Power IEC Receptacle Pod (Left) + Pinpoint Status LED
	_add_box(self, Vector3(-0.27, top_y, -0.445), Vector3(0.24, 0.12, 0.055), dark_mat)
	_add_box(self, Vector3(-0.29, top_y, -0.470), Vector3(0.12, 0.065, 0.032), _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08))
	_power_led_mat = StandardMaterial3D.new()
	_power_led_mat.albedo_color = Color(0.24, 0.78, 0.38)
	_power_led_mat.emission_enabled = true
	_power_led_mat.emission = Color(0.24, 0.78, 0.38)
	_power_led_mat.emission_energy_multiplier = 0.04
	_limit_detail_range(_add_box(self, Vector3(-0.18, top_y, -0.474), Vector3(0.024, 0.024, 0.016), _power_led_mat))

	_power_port_marker = Node3D.new()
	_power_port_marker.position = Vector3(-0.27, top_y, -0.50)
	add_child(_power_port_marker)

	if not is_showcase_only:
		var p_area := _make_area(Vector3(0.32, 0.24, 0.22), {
			"interact_type": "power_port",
			"entity_id": rack_id,
		})
		p_area.position = Vector3(-0.27, top_y, -0.46)
		add_child(p_area)

	# Realistic Matte Blue Network RJ45 Patch Pod (Right) + Pinpoint Link LED
	_add_box(self, Vector3(0.27, top_y, -0.445), Vector3(0.24, 0.12, 0.055), dark_mat)
	_add_box(self, Vector3(0.25, top_y, -0.470), Vector3(0.12, 0.065, 0.032), _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22))
	_net_led_mat = StandardMaterial3D.new()
	_net_led_mat.albedo_color = Color(0.24, 0.78, 0.38)
	_net_led_mat.emission_enabled = true
	_net_led_mat.emission = Color(0.24, 0.78, 0.38)
	_net_led_mat.emission_energy_multiplier = 0.04
	_limit_detail_range(_add_box(self, Vector3(0.36, top_y, -0.474), Vector3(0.024, 0.024, 0.016), _net_led_mat))

	_net_port_marker = Node3D.new()
	_net_port_marker.position = Vector3(0.27, top_y, -0.50)
	add_child(_net_port_marker)

	if not is_showcase_only:
		var n_area := _make_area(Vector3(0.32, 0.24, 0.22), {
			"interact_type": "net_port",
			"entity_id": rack_id,
		})
		n_area.position = Vector3(0.27, top_y, -0.46)
		add_child(n_area)

	# Lila Cluster-Port (Mitte): verbundene Racks leihen sich bei Engpässen freie Hardware.
	_add_box(self, Vector3(0.0, top_y, -0.445), Vector3(0.14, 0.12, 0.055), dark_mat)
	_add_box(self, Vector3(-0.015, top_y, -0.470), Vector3(0.08, 0.065, 0.032), _mat(Color(0.52, 0.28, 0.74), 0.45, 0.22))
	_cluster_led_mat = StandardMaterial3D.new()
	_cluster_led_mat.albedo_color = Color(0.62, 0.38, 0.92)
	_cluster_led_mat.emission_enabled = true
	_cluster_led_mat.emission = Color(0.18, 0.18, 0.18)
	_cluster_led_mat.emission_energy_multiplier = 0.04
	_limit_detail_range(_add_box(self, Vector3(0.045, top_y, -0.474), Vector3(0.024, 0.024, 0.016), _cluster_led_mat))

	_cluster_port_marker = Node3D.new()
	_cluster_port_marker.position = Vector3(-0.015, top_y, -0.50)
	add_child(_cluster_port_marker)

	if not is_showcase_only:
		var c_area := _make_area(Vector3(0.16, 0.24, 0.22), {
			"interact_type": "cluster_port",
			"entity_id": rack_id,
		})
		c_area.position = Vector3(0.0, top_y, -0.46)
		add_child(c_area)

	_header_label = Label3D.new()
	_header_label.text = GameState.get_rack_display_name(rack_id)
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
		_limit_detail_range(_add_box(led_pod, Vector3(0.345, -0.005, 0.415), Vector3(0.018, 0.018, 0.012), led_mat))
		_limit_detail_range(_add_box(led_pod, Vector3(0.345, -0.036, 0.415), Vector3(0.018, 0.014, 0.012), act_mat))

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
		_limit_detail_range(slot_lbl)
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


## Kleine Details (LEDs von 1,2 bis 2,4 cm, Slot-Beschriftung) sind ab ~14 m in 1440p kaum ein Pixel groß.
## Ab dort werden sie nicht mehr gezeichnet. Die 1 m Spielraum verhindert Flackern an der Grenze.
const DETAIL_RANGE_END := 14.0
const DETAIL_RANGE_MARGIN := 1.0


func _limit_detail_range(node: GeometryInstance3D) -> void:
	if node == null:
		return
	node.visibility_range_end = DETAIL_RANGE_END
	node.visibility_range_end_margin = DETAIL_RANGE_MARGIN


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, rad: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
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


## Türen und Seitenwände aus dem Blender-Modell beweglich machen und Dachlüfter registrieren.
func _setup_custom_shell(shell: Node3D, total_h: float) -> void:
	for n in _collect_nodes(shell):
		if not (n is Node3D):
			continue
		var n3 := n as Node3D
		var nm := String(n3.name)
		if nm.contains("Fan_Roof"):
			_roof_fans.append(n3)
		elif nm.contains("Hinge_"):
			var side := signf(n3.position.x)
			var fallback_deg := -105.0 if nm.ends_with("RearDoor_R") else 105.0
			var open_deg := _extra_float(n3, "dct_open_deg", fallback_deg)
			_panels[nm] = {
				"node": n3,
				"kind": "hinge",
				"closed": n3.rotation.y,
				"open": n3.rotation.y + deg_to_rad(open_deg),
				"is_open": false,
				"tween": null,
			}
			if not is_showcase_only:
				# Klickbereich über die ganze Türfläche (vom Scharnier bis zum Griff), schwenkt mit der Tür mit
				var reach := 0.40 if nm.contains("RearDoor") else 0.84
				var front := signf(n3.position.z)
				var d_area := _make_area(Vector3(reach + 0.06, total_h * 0.92, 0.18), {
					"interact_type": "rack_panel",
					"entity_id": rack_id,
					"panel_id": nm,
					"rack_prop": self,
				})
				d_area.position = Vector3(-side * reach * 0.5, total_h * 0.5, front * (0.14 if front > 0.0 else 0.08))
				n3.add_child(d_area)
		# Panel_Side_*: Seitenwände bleiben geschlossen und sind nicht interaktiv (nur Vorder- und Hecktür öffnen).
		elif nm.contains("Panel_Side_"):
			continue


## Fragt beim Server an. Die Tür bewegt sich erst, wenn der Server den neuen Zustand an alle schickt.
func toggle_panel(panel_id: String) -> void:
	if not _panels.has(panel_id):
		return
	GameState.request_toggle_panel(rack_id, panel_id)


func _on_panel_states_changed() -> void:
	_apply_synced_panel_states(true)


func _apply_synced_panel_states(animate: bool) -> void:
	for pid in _panels.keys():
		_set_panel_open(str(pid), GameState.is_shared_panel_open(rack_id, str(pid)), animate)


func _set_panel_open(panel_id: String, opening: bool, animate: bool) -> void:
	if not _panels.has(panel_id):
		return
	var p: Dictionary = _panels[panel_id]
	var node_v: Variant = p["node"]
	if not is_instance_valid(node_v):
		return
	if bool(p["is_open"]) == opening:
		return
	p["is_open"] = opening
	var old_tw: Variant = p.get("tween")
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	var is_hinge := str(p["kind"]) == "hinge"
	var prop := "rotation:y" if is_hinge else "position:x"
	var target := float(p["open"] if opening else p["closed"])
	var node := node_v as Node3D
	if not animate or not node.is_inside_tree():
		node.set_indexed(NodePath(prop), target)
		p["tween"] = null
		return
	var tw := create_tween()
	tw.tween_property(node, prop, target, 0.55 if is_hinge else 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	p["tween"] = tw
	SfxManager.play("click", -10.0, 0.85 if opening else 0.7)


func is_panel_open(panel_id: String) -> bool:
	if not _panels.has(panel_id):
		return false
	return bool((_panels[panel_id] as Dictionary).get("is_open", false))


func get_panel_label(panel_id: String) -> String:
	if panel_id.contains("FrontDoor"):
		return tr("Fronttür")
	if panel_id.contains("RearDoor_L"):
		return tr("Hintertür links")
	if panel_id.contains("RearDoor_R"):
		return tr("Hintertür rechts")
	if panel_id.contains("Side_L"):
		return tr("Seitenwand links")
	if panel_id.contains("Side_R"):
		return tr("Seitenwand rechts")
	return tr("Abdeckung")


func _collect_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		for c in out[i].get_children():
			out.append(c)
		i += 1
	return out


## glTF-Extras kommen je nach Importweg als Meta "extras" (Dictionary) oder als einzelne Meta-Keys an.
func _extra_float(n: Node, key: String, fallback: float) -> float:
	if n.has_meta("extras"):
		var ex: Variant = n.get_meta("extras")
		if ex is Dictionary and (ex as Dictionary).has(key):
			return float((ex as Dictionary)[key])
	if n.has_meta(key):
		return float(n.get_meta(key))
	return fallback
