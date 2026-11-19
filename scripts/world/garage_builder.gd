class_name GarageBuilder
extends Node3D
## Constructs the PBR Modern Tech / Stylized Indie Garage, Hall B Expansion,
## Enterprise Hall C (with dedicated Power & Fiber Subpanel), Exterior Yard,
## Streetlamp, Trees, Dusk/Night Floodlight, and Dynamic Blackout/UPS Lighting.

var breaker_port_pos: Vector3 = Vector3(-4.2, 1.18, -4.16)
var router_port_pos: Vector3 = Vector3(-1.0, 1.48, -4.16)
var hall_c_breaker_port_pos: Vector3 = Vector3(14.6, 1.18, -4.16)
var hall_c_router_port_pos: Vector3 = Vector3(16.6, 1.48, -4.16)

var _partition_b: StaticBody3D
var _partition_c: StaticBody3D
var _ceiling_lights: Array[SpotLight3D] = []
var _light_bar_mats: Array[StandardMaterial3D] = []
var _reflection_probes: Array[ReflectionProbe] = []
var _desk_glow_light: OmniLight3D
var _ext_ac_fan: Node3D
var _emergency_light: OmniLight3D
var _exterior_lamp_light: OmniLight3D
var _street_lamp_light: OmniLight3D
var _street_lamp_mat: StandardMaterial3D

var _breaker_lever: MeshInstance3D
var _breaker_led_mat: StandardMaterial3D
var _breaker_load_bar: MeshInstance3D
var _breaker_load_mat: StandardMaterial3D
var _breaker_label: Label3D

var _hall_c_breaker_label: Label3D
var _hall_c_router_label: Label3D

var _router_root: Node3D
var _router_mesh_holder: Node3D
var _router_visual_tier: int = -1
var _router_led_mat: StandardMaterial3D
var _router_label: Label3D

var _breaker_audio: AudioStreamPlayer3D
var _pc_audio: AudioStreamPlayer3D

var _extinguisher_mesh_root: Node3D
var _blink_time: float = 0.0


func _ready() -> void:
	_build_architecture()
	_build_structural_details()
	_build_exterior_environment()
	_build_delivery_zone()
	_build_lighting()
	_build_reflection_probes()
	_build_breaker_box()
	_build_extinguisher_station()
	_build_wall_router()
	_build_hall_c_subpanel()
	_build_terminal_desk()
	_build_wall_decor()
	_build_workshop_props()
	apply_graphics_quality(SettingsManager.graphics_quality)


func _process(delta: float) -> void:
	_blink_time += delta
	if _ext_ac_fan != null:
		_ext_ac_fan.rotation.z += delta * 11.0
	_update_dynamic_visuals()


func apply_graphics_quality(quality: int) -> void:
	for i in range(_ceiling_lights.size()):
		# Enable soft SpotLight shadows on High/Ultra for dramatic depth!
		# Ultra wie Hoch: 4 Lampen mit Schatten. Alle 6 kosteten ~56 ms pro Frame, weil sich drehende Lüfter die Schatten ständig neu rendern lassen.
		_ceiling_lights[i].shadow_enabled = (quality >= 2 and i < 4)
		_ceiling_lights[i].distance_fade_enabled = true
		_ceiling_lights[i].distance_fade_begin = 16.0
		_ceiling_lights[i].distance_fade_shadow = 9.0
		_ceiling_lights[i].distance_fade_length = 4.0
	for rp in _reflection_probes:
		rp.visible = (quality >= 2)
	if _desk_glow_light != null:
		_desk_glow_light.visible = (quality >= 1)


func set_room_level(level: int) -> void:
	_set_wall_open(_partition_b, level >= 1)
	_set_wall_open(_partition_c, level >= 2)


func _set_wall_open(wall: StaticBody3D, opened: bool) -> void:
	if wall == null:
		return
	wall.visible = not opened
	for child in wall.get_children():
		if child is CollisionShape3D:
			child.disabled = opened


func set_extinguisher_mounted(mounted: bool) -> void:
	if _extinguisher_mesh_root != null:
		_extinguisher_mesh_root.visible = mounted


func _update_dynamic_visuals() -> void:
	var power_alive := true if not GameState.is_active else (GameState.breaker_on or GameState.ups_backup_active)
	var on_ups := GameState.is_active and GameState.ups_backup_active
	var overloading := GameState.is_active and GameState.breaker_on and GameState.total_watts > GameState.max_watts

	var flicker := 1.0
	if overloading:
		flicker = 0.55 + 0.45 * sin(_blink_time * 28.0)

	# Ceiling lights: indices 0..1 Garage, 2..3 Hall B, 4..5 Enterprise Hall C
	for i in range(_ceiling_lights.size()):
		var light := _ceiling_lights[i]
		var allowed := true
		if i >= 4:
			allowed = GameState.room_level >= 2
		elif i >= 2:
			allowed = GameState.room_level >= 1
		var enabled := power_alive and allowed
		var ups_dim := 0.72 if on_ups else 1.0
		light.light_energy = (4.4 * flicker * ups_dim) if enabled else 0.0
		light.light_color = Color(1.0, 0.88, 0.72) if on_ups else Color(0.98, 0.97, 0.95)
		if i < _light_bar_mats.size():
			_light_bar_mats[i].emission_energy_multiplier = (1.35 * flicker * ups_dim) if enabled else 0.04

	if _desk_glow_light != null:
		_desk_glow_light.light_energy = (0.28 if not GameState.ddos_active else 0.55) if power_alive else 0.0
		_desk_glow_light.light_color = Color(0.95, 0.32, 0.24) if GameState.ddos_active else Color(0.96, 0.96, 0.94)

	var os_sh := MatLib.get_os_screen_material()
	if os_sh != null:
		os_sh.set_shader_parameter("power_on", 1.0 if power_alive else 0.0)
		os_sh.set_shader_parameter("alert_mode", 1.0 if (GameState.is_active and GameState.ddos_active) else 0.0)
	var tel_sh := MatLib.get_telemetry_screen_material()
	if tel_sh != null:
		tel_sh.set_shader_parameter("power_on", 1.0 if power_alive else 0.0)
		tel_sh.set_shader_parameter("heat_warn", 1.0 if (GameState.is_active and GameState.room_temp >= 68.0) else 0.0)

	# Exterior night lamps turn on automatically at dusk/night!
	var tod := GameState.time_of_day if GameState.is_active else 0.36
	var is_night := (tod < 0.24 or tod > 0.74)
	if _exterior_lamp_light != null:
		_exterior_lamp_light.light_energy = 2.6 if (is_night and power_alive) else 0.0
	if _street_lamp_light != null:
		_street_lamp_light.light_energy = 3.2 if is_night else 0.0
	if _street_lamp_mat != null:
		_street_lamp_mat.emission_energy_multiplier = 3.2 if is_night else 0.15

	if _emergency_light != null:
		if not power_alive:
			_emergency_light.light_color = Color(1.0, 0.20, 0.14)
			_emergency_light.light_energy = 1.4 + 0.5 * sin(_blink_time * 6.0)
		elif on_ups:
			_emergency_light.light_color = Color(1.0, 0.68, 0.18)
			_emergency_light.light_energy = 0.85 + 0.35 * sin(_blink_time * 8.0)
		elif GameState.is_active and GameState.has_any_fire():
			_emergency_light.light_color = Color(1.0, 0.28, 0.12)
			_emergency_light.light_energy = 1.2 + 0.65 * sin(_blink_time * 12.0)
		else:
			_emergency_light.light_energy = 0.0

	# Update 3D Spatial Workstation PC & 50Hz Breaker Transformer Hum!
	var amb_gain := SettingsManager.get_effective_fan_gain()
	if _pc_audio != null:
		if power_alive and amb_gain > 0.005:
			if not _pc_audio.playing:
				_pc_audio.play()
			_pc_audio.volume_db = linear_to_db(amb_gain) - 13.0
		elif _pc_audio.playing:
			_pc_audio.stop()
	if _breaker_audio != null:
		if GameState.breaker_on and amb_gain > 0.005:
			if not _breaker_audio.playing:
				_breaker_audio.play()
			var load_boost := clampf(float(GameState.total_watts) / float(maxi(GameState.max_watts, 1)), 0.0, 1.0) * 6.0
			_breaker_audio.volume_db = linear_to_db(amb_gain) - 16.0 + load_boost
		elif _breaker_audio.playing:
			_breaker_audio.stop()

	# Rebuild 3D Wall Router appearance whenever Router Tier changes!
	var cur_rt := clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)
	if _router_visual_tier != cur_rt:
		_rebuild_router_visuals(cur_rt)

	if not GameState.is_active:
		return

	if _breaker_lever != null:
		_breaker_lever.rotation_degrees.x = -28.0 if GameState.breaker_on else 34.0
	if _breaker_led_mat != null:
		if not GameState.breaker_on:
			_breaker_led_mat.emission = Color(0.95, 0.56, 0.12) if on_ups else Color(0.95, 0.16, 0.14)
			_breaker_led_mat.emission_energy_multiplier = 0.95 + 0.4 * sin(_blink_time * 8.0)
		elif overloading:
			_breaker_led_mat.emission = Color(0.95, 0.62, 0.08)
			_breaker_led_mat.emission_energy_multiplier = 1.1 + 0.5 * sin(_blink_time * 16.0)
		else:
			_breaker_led_mat.emission = Color(0.22, 0.76, 0.36)
			_breaker_led_mat.emission_energy_multiplier = 0.75
	if _breaker_load_bar != null and _breaker_load_mat != null:
		var ratio := clampf(float(GameState.total_watts) / float(maxi(GameState.max_watts, 1)), 0.04, 1.0)
		_breaker_load_bar.scale.x = ratio if power_alive else 0.04
		if not power_alive or ratio >= 1.0:
			_breaker_load_mat.emission = Color(0.92, 0.18, 0.14)
		elif ratio >= 0.8 or on_ups:
			_breaker_load_mat.emission = Color(0.92, 0.66, 0.14)
		else:
			_breaker_load_mat.emission = Color(0.24, 0.74, 0.38)
		_breaker_load_mat.emission_energy_multiplier = 0.72

	if _breaker_label != null:
		var used_p := GameState.count_cables_on("power", GameState.WALL_BREAKER_ID)
		var max_p := GameState.get_max_ports("power", GameState.WALL_BREAKER_ID)
		var state_txt := "EIN" if GameState.breaker_on else ("USV-NOTSTROM!" if on_ups else "AUS (BLACKOUT!)")
		_breaker_label.text = "SICHERUNGSKASTEN\nStatus: %s\n%dW / %dW\nPorts: %d / %d" % [
			state_txt, GameState.total_watts, GameState.max_watts, used_p, max_p
		]
		_breaker_label.modulate = Color(0.95, 0.28, 0.24) if not power_alive else (Color(0.92, 0.64, 0.16) if (overloading or on_ups) else Color(0.18, 0.20, 0.22))

	if _hall_c_breaker_label != null:
		var used_cp := GameState.count_cables_on("power", GameState.HALL_C_BREAKER_ID)
		var max_cp := GameState.get_max_ports("power", GameState.HALL_C_BREAKER_ID)
		_hall_c_breaker_label.text = "HALLE-C STROMBUS\nPorts: %d / %d" % [used_cp, max_cp]

	if _hall_c_router_label != null:
		var used_cn := GameState.count_cables_on("network", GameState.HALL_C_ROUTER_ID)
		var max_cn := GameState.get_max_ports("network", GameState.HALL_C_ROUTER_ID)
		_hall_c_router_label.text = "HALLE-C 10G FIBER\nPorts: %d / %d" % [used_cn, max_cn]

	if _router_led_mat != null:
		if not power_alive:
			_router_led_mat.emission = Color(0.2, 0.2, 0.2)
			_router_led_mat.emission_energy_multiplier = 0.05
		elif GameState.ddos_active:
			_router_led_mat.emission = Color(0.95, 0.18, 0.16)
			_router_led_mat.emission_energy_multiplier = 1.2 * (0.5 + 0.5 * sin(_blink_time * 18.0))
		else:
			_router_led_mat.emission = Color(0.20, 0.74, 0.36)
			_router_led_mat.emission_energy_multiplier = 0.72 + 0.2 * sin(_blink_time * 6.0)
	if _router_label != null:
		var rt_info: Dictionary = GameState.ROUTER_TIERS[clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)]
		var used_n := GameState.count_cables_on("network", GameState.WALL_ROUTER_ID)
		var max_n := GameState.get_max_ports("network", GameState.WALL_ROUTER_ID)
		var net_txt := "DDOS-ANGRIFF! [E]" if GameState.ddos_active else ("ONLINE" if power_alive else "OFFLINE")
		var cap_warn := " ⚠ LIMIT!" if GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps else ""
		_router_label.text = "%s\n%s • %s / %s%s\nPorts: %d/%d  ([E] Kabel | [F] Upgrade)" % [
			str(rt_info["label"]), net_txt,
			HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps),
			str(rt_info["speed"]), cap_warn, used_n, max_n
		]
		if GameState.ddos_active:
			_router_label.modulate = Color(0.95, 0.24, 0.20)
		elif GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps:
			_router_label.modulate = Color(0.84, 0.48, 0.08)
		else:
			_router_label.modulate = Color(0.18, 0.20, 0.22)


func _build_architecture() -> void:
	var floor_mat := MatLib.get_mat("concrete_floor")
	var epoxy_mat := MatLib.get_mat("epoxy_floor")
	var ent_floor_mat := MatLib.get_mat("enterprise_floor")
	var wall_mat := MatLib.get_mat("garage_wall")
	var wainscot_mat := MatLib.get_mat("wainscot_wall")
	var ceiling_mat := _mat(Color(0.20, 0.22, 0.26), 0.88, 0.05)

	# Floors: Garage (-5.5..5.5), Hall B (5.5..12.5), Enterprise Hall C (12.5..21.5)
	_add_box_static(self, Vector3(0.0, -0.1, 0.0), Vector3(11.0, 0.2, 9.0), floor_mat)
	_add_box_visual(self, Vector3(-0.8, 0.002, -0.4), Vector3(7.6, 0.006, 6.2), epoxy_mat)
	_add_box_static(self, Vector3(9.0, -0.1, 0.0), Vector3(7.0, 0.2, 9.0), epoxy_mat)
	_add_box_static(self, Vector3(17.0, -0.1, 0.0), Vector3(9.0, 0.2, 9.0), ent_floor_mat)

	# Clean Brushed Aluminum Raised-Floor Edge Trim in Enterprise Hall C (no neon!)
	var ent_trim := MatLib.get_mat("galvanized_steel")
	_add_box_visual(self, Vector3(17.0, 0.006, -4.15), Vector3(8.4, 0.008, 0.08), ent_trim)
	_add_box_visual(self, Vector3(17.0, 0.006, 4.15), Vector3(8.4, 0.008, 0.08), ent_trim)

	# Subtle realistic floor seam grid across all 3 halls
	var grid_mat := _mat(Color(0.36, 0.37, 0.38), 0.86, 0.0)
	for x_i in range(-5, 22):
		_add_box_visual(self, Vector3(float(x_i), 0.005, 0.0), Vector3(0.015, 0.003, 8.8), grid_mat)
	for z_i in range(-4, 5):
		_add_box_visual(self, Vector3(8.0, 0.005, float(z_i)), Vector3(26.8, 0.003, 0.015), grid_mat)

	# Ceiling & Roof Fascia (bright realistic light-grey ceiling)
	var bright_ceil := _mat(Color(0.68, 0.69, 0.70), 0.90, 0.02)
	_add_box_static(self, Vector3(8.0, 3.9, 0.0), Vector3(27.5, 0.2, 9.4), bright_ceil)
	_add_box_visual(self, Vector3(8.0, 4.08, 4.72), Vector3(27.8, 0.32, 0.28), _mat(Color(0.24, 0.25, 0.27), 0.55, 0.30))

	# Perimeter Walls
	_add_box_static(self, Vector3(8.0, 1.9, -4.6), Vector3(27.5, 3.8, 0.25), wall_mat)
	_add_box_static(self, Vector3(-5.6, 1.9, 0.0), Vector3(0.25, 3.8, 9.4), wall_mat)
	_add_box_static(self, Vector3(21.6, 1.9, 0.0), Vector3(0.25, 3.8, 9.4), wall_mat)

	# South Wall with Open Garage Doorway (X -2.2..+2.2)
	_add_box_static(self, Vector3(-3.85, 1.9, 4.6), Vector3(3.3, 3.8, 0.25), wall_mat)
	_add_box_static(self, Vector3(11.85, 1.9, 4.6), Vector3(19.3, 3.8, 0.25), wall_mat)
	_add_box_static(self, Vector3(0.0, 3.4, 4.6), Vector3(4.4, 0.8, 0.25), wall_mat)

	# Two-Tone Industrial Lower Wall Paint + Matte Charcoal Rubber Bumper Rail (no neon stripe!)
	_add_box_visual(self, Vector3(8.0, 0.55, -4.46), Vector3(27.0, 1.10, 0.03), wainscot_mat)
	_add_box_visual(self, Vector3(-5.46, 0.55, 0.0), Vector3(0.03, 1.10, 9.0), wainscot_mat)
	_add_box_visual(self, Vector3(21.46, 0.55, 0.0), Vector3(0.03, 1.10, 9.0), wainscot_mat)
	_add_box_visual(self, Vector3(-3.85, 0.55, 4.46), Vector3(3.25, 1.10, 0.03), wainscot_mat)
	_add_box_visual(self, Vector3(11.85, 0.55, 4.46), Vector3(19.25, 1.10, 0.03), wainscot_mat)

	var rail_trim := _mat(Color(0.24, 0.25, 0.27), 0.65, 0.12)
	_add_box_visual(self, Vector3(8.0, 1.11, -4.44), Vector3(27.0, 0.055, 0.03), rail_trim)
	_add_box_visual(self, Vector3(-5.44, 1.11, 0.0), Vector3(0.03, 0.055, 9.0), rail_trim)
	_add_box_visual(self, Vector3(21.44, 1.11, 0.0), Vector3(0.03, 0.055, 9.0), rail_trim)

	# Partition Wall B (X = +5.5) -> Unlocks Hall B ($1800)
	_partition_b = _build_expansion_wall(
		"PartitionWallB",
		5.5,
		"HALLE B — GARAGEN-ANBAU GESPERRT\nIm Management-PC freischalten ($1.800)\n+63 m² Rechenzentrum-Fläche",
		Color(0.95, 0.85, 0.45)
	)

	# Partition Wall C (X = +12.5) -> Unlocks Enterprise Hall C ($4800)
	_partition_c = _build_expansion_wall(
		"PartitionWallC",
		12.5,
		"HALLE C — ENTERPRISE-FLÜGEL GESPERRT\nIm Management-PC freischalten ($4.800)\n+81 m² + Eigener 10G-Fiber & Strom-Verteiler!",
		Color(0.88, 0.90, 0.94)
	)

	var wing_b_sign := Label3D.new()
	wing_b_sign.text = "HALLE B — SERVERRAUM"
	wing_b_sign.font_size = 42
	wing_b_sign.pixel_size = 0.0056
	wing_b_sign.position = Vector3(9.0, 2.95, -4.42)
	wing_b_sign.modulate = Color(0.20, 0.22, 0.25)
	add_child(wing_b_sign)

	var wing_c_sign := Label3D.new()
	wing_c_sign.text = "HALLE C — ENTERPRISE RECHENZENTRUM"
	wing_c_sign.font_size = 44
	wing_c_sign.pixel_size = 0.0056
	wing_c_sign.position = Vector3(17.2, 2.98, -4.42)
	wing_c_sign.modulate = Color(0.20, 0.22, 0.25)
	add_child(wing_c_sign)


func _build_expansion_wall(wname: String, x_pos: float, sign_text: String, sign_col: Color) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = wname
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(x_pos, 1.9, 0.0)
	add_child(wall)

	_add_box_visual(wall, Vector3.ZERO, Vector3(0.22, 3.8, 8.95), MatLib.get_mat("corrugated_metal"))
	var hazard_mat := MatLib.get_mat("hazard_stripes")
	_add_box_visual(wall, Vector3(-0.12, -1.68, 0.0), Vector3(0.03, 0.24, 8.8), hazard_mat)
	_add_box_visual(wall, Vector3(-0.12, 1.20, 0.0), Vector3(0.03, 0.14, 8.8), hazard_mat)
	for slat in range(-3, 4):
		_add_box_visual(wall, Vector3(-0.12, float(slat) * 0.42, 0.0), Vector3(0.04, 0.03, 8.8), _mat(Color(0.14, 0.16, 0.20), 0.5, 0.5))

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.22, 3.8, 8.95)
	col.shape = shape
	wall.add_child(col)

	var lock_sign := Label3D.new()
	lock_sign.text = sign_text
	lock_sign.font_size = 40
	lock_sign.pixel_size = 0.0054
	lock_sign.position = Vector3(-0.16, 0.2, 0.0)
	lock_sign.rotation_degrees.y = -90.0
	lock_sign.modulate = sign_col
	wall.add_child(lock_sign)
	return wall


func _build_structural_details() -> void:
	var steel_mat := MatLib.make_brushed_metal(Color(0.17, 0.20, 0.24), 0.34, 0.72)
	var tray_mat := MatLib.make_brushed_metal(Color(0.30, 0.34, 0.40), 0.42, 0.62)
	var door_mat := MatLib.get_mat("corrugated_metal")
	var hazard_mat := MatLib.get_mat("hazard_stripes")

	# Floor hazard warning thresholds at Hall B & Hall C archways + steel portal frames
	for ax in [5.5, 12.5]:
		_add_box_visual(self, Vector3(float(ax), 0.008, 0.0), Vector3(0.28, 0.008, 8.6), hazard_mat)
		_add_box_visual(self, Vector3(float(ax), 3.68, 0.0), Vector3(0.30, 0.24, 8.9), steel_mat)

	for bx in [-4.0, 0.0, 4.0, 8.8, 13.0, 17.2, 21.0]:
		_add_box_visual(self, Vector3(float(bx), 3.72, 0.0), Vector3(0.16, 0.20, 8.9), steel_mat)

	# Continuous Overhead Cable Trays across Garage + Hall B + Hall C
	_add_box_visual(self, Vector3(7.6, 3.46, -3.55), Vector3(25.2, 0.06, 0.34), tray_mat)
	_add_box_visual(self, Vector3(7.6, 3.51, -3.72), Vector3(25.2, 0.08, 0.03), steel_mat)
	_add_box_visual(self, Vector3(7.6, 3.51, -3.38), Vector3(25.2, 0.08, 0.03), steel_mat)
	for hx in [-4.2, -1.0, 3.0, 7.5, 12.0, 16.5, 20.0]:
		_add_box_visual(self, Vector3(float(hx), 3.64, -3.55), Vector3(0.04, 0.34, 0.04), steel_mat)

	# Overhead Spiral Galvanized HVAC Air Ductwork with Diffusers across all 3 Halls!
	BuildingPropFactory.build_hvac_ceiling_ducts(self)

	# Sectional Rolled-up Garage Door + Tracks
	_add_box_visual(self, Vector3(-2.22, 1.50, 4.42), Vector3(0.10, 3.0, 0.14), steel_mat)
	_add_box_visual(self, Vector3(2.22, 1.50, 4.42), Vector3(0.10, 3.0, 0.14), steel_mat)
	_add_box_visual(self, Vector3(-2.22, 3.08, 2.85), Vector3(0.08, 0.08, 3.2), steel_mat)
	_add_box_visual(self, Vector3(2.22, 3.08, 2.85), Vector3(0.08, 0.08, 3.2), steel_mat)
	for p_idx in range(4):
		_add_box_visual(self, Vector3(0.0, 3.12, 3.95 - float(p_idx) * 0.68), Vector3(4.32, 0.07, 0.62), door_mat)


func _build_exterior_environment() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var grass_mat := MatLib.get_mat("grass")
	var curb_mat := _mat(Color(0.55, 0.56, 0.58), 0.88, 0.0)
	var wood_fence := MatLib.get_mat("wood_desk")
	var trunk_mat := _mat(Color(0.32, 0.22, 0.14), 0.9, 0.0)
	var leaf_mat := _mat(Color(0.20, 0.48, 0.22), 0.85, 0.0)
	var pole_mat := MatLib.make_brushed_metal(Color(0.22, 0.25, 0.28), 0.45, 0.6)

	# Concrete Driveway + Surrounding Lawn + Street beyond Z=10.6
	_add_box_static(self, Vector3(0.0, -0.11, 7.6), Vector3(7.4, 0.2, 6.2), asp_mat)
	_add_box_static(self, Vector3(-11.5, -0.13, 7.6), Vector3(15.6, 0.2, 6.4), grass_mat)
	_add_box_static(self, Vector3(13.5, -0.13, 7.6), Vector3(19.6, 0.2, 6.4), grass_mat)
	# Street & dashed lane lines
	_add_box_visual(self, Vector3(2.0, -0.12, 14.5), Vector3(48.0, 0.2, 7.6), asp_mat)
	_add_box_visual(self, Vector3(2.0, -0.14, 23.0), Vector3(48.0, 0.2, 10.0), grass_mat)
	var stripe_mat := _mat(Color(0.92, 0.92, 0.90), 0.75, 0.0)
	for sx in range(-18, 22, 4):
		_add_box_visual(self, Vector3(float(sx), -0.01, 14.5), Vector3(1.8, 0.01, 0.16), stripe_mat)

	# Driveway curbs
	_add_box_visual(self, Vector3(-3.75, 0.03, 7.6), Vector3(0.16, 0.08, 6.0), curb_mat)
	_add_box_visual(self, Vector3(3.75, 0.03, 7.6), Vector3(0.16, 0.08, 6.0), curb_mat)

	# Invisible driveway containment walls
	_add_invisible_wall(Vector3(-6.2, 2.0, 7.5), Vector3(0.3, 4.0, 6.2))
	_add_invisible_wall(Vector3(13.2, 2.0, 7.5), Vector3(0.3, 4.0, 6.2))
	_add_invisible_wall(Vector3(3.5, 2.0, 10.4), Vector3(20.0, 4.0, 0.3))

	# Wooden Perimeter Yard Fence along left/right front
	_add_box_visual(self, Vector3(-7.4, 0.65, 10.4), Vector3(6.8, 1.3, 0.12), wood_fence)
	_add_box_visual(self, Vector3(8.5, 0.65, 10.4), Vector3(9.2, 1.3, 0.12), wood_fence)

	# Organic multi-branch realistic trees across yard & street
	var tree_spots: Array[Vector3] = [
		Vector3(-6.8, 0.0, 7.8),
		Vector3(6.8, 0.0, 7.5),
		Vector3(-9.5, 0.0, 19.5),
		Vector3(-1.5, 0.0, 19.8),
		Vector3(7.2, 0.0, 19.5),
		Vector3(14.5, 0.0, 19.2),
	]
	for tp in tree_spots:
		BuildingPropFactory.build_realistic_tree(self, tp)

	# Architectural Exterior Brick Cladding, Gutter, Spinning Exterior AC Condenser & Recycling Bin
	var brick_mat := MatLib.get_mat("exterior_brick")
	_add_box_visual(self, Vector3(-3.85, 1.9, 4.76), Vector3(3.35, 3.82, 0.08), brick_mat)
	_add_box_visual(self, Vector3(11.85, 1.9, 4.76), Vector3(19.35, 3.82, 0.08), brick_mat)
	_add_box_visual(self, Vector3(0.0, 3.4, 4.76), Vector3(4.42, 0.82, 0.08), brick_mat)
	# Aluminum Rain Gutter & Vertical Downspout
	_add_box_visual(self, Vector3(8.0, 3.92, 4.88), Vector3(27.8, 0.11, 0.12), pole_mat)
	_add_box_visual(self, Vector3(-5.35, 1.95, 4.86), Vector3(0.09, 3.9, 0.09), pole_mat)
	# Exterior Wall-Mounted AC Condenser Unit with Spinning Fan
	_add_box_visual(self, Vector3(3.75, 0.56, 5.12), Vector3(0.95, 0.72, 0.42), MatLib.make_brushed_metal(Color(0.76, 0.80, 0.84), 0.45, 0.25))
	_add_box_visual(self, Vector3(3.60, 0.56, 5.34), Vector3(0.50, 0.50, 0.03), _mat(Color(0.10, 0.12, 0.14), 0.7, 0.2))
	_ext_ac_fan = Node3D.new()
	_ext_ac_fan.position = Vector3(3.60, 0.56, 5.36)
	add_child(_ext_ac_fan)
	_add_box_visual(_ext_ac_fan, Vector3.ZERO, Vector3(0.42, 0.06, 0.02), pole_mat)
	_add_box_visual(_ext_ac_fan, Vector3.ZERO, Vector3(0.06, 0.42, 0.02), pole_mat)
	# Recycling Bin beside Garage Door
	_add_box_visual(self, Vector3(-3.35, 0.46, 5.20), Vector3(0.56, 0.88, 0.56), _mat(Color(0.18, 0.34, 0.56), 0.55, 0.10))
	_add_box_visual(self, Vector3(-3.35, 0.93, 5.20), Vector3(0.60, 0.08, 0.60), _mat(Color(0.14, 0.26, 0.44), 0.50, 0.10))

	# Glowing Exterior Streetlamp by Driveway Corner (turns on automatically at dusk!)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.07
	pc.bottom_radius = 0.10
	pc.height = 4.6
	pole.mesh = pc
	pole.material_override = pole_mat
	pole.position = Vector3(4.3, 2.3, 10.2)
	add_child(pole)
	_add_box_visual(self, Vector3(3.85, 4.55, 10.2), Vector3(0.95, 0.10, 0.16), pole_mat)

	_street_lamp_mat = StandardMaterial3D.new()
	_street_lamp_mat.albedo_color = Color(1.0, 0.92, 0.72)
	_street_lamp_mat.emission_enabled = true
	_street_lamp_mat.emission = Color(1.0, 0.88, 0.62)
	_street_lamp_mat.emission_energy_multiplier = 0.15
	_add_box_visual(self, Vector3(3.55, 4.46, 10.2), Vector3(0.38, 0.07, 0.22), _street_lamp_mat)

	_street_lamp_light = OmniLight3D.new()
	_street_lamp_light.position = Vector3(3.55, 4.1, 10.2)
	_street_lamp_light.light_color = Color(1.0, 0.88, 0.62)
	_street_lamp_light.light_energy = 0.0
	_street_lamp_light.omni_range = 14.0
	add_child(_street_lamp_light)

	# Warm Floodlight directly over the garage door for night deliveries
	_exterior_lamp_light = OmniLight3D.new()
	_exterior_lamp_light.position = Vector3(0.0, 3.6, 5.2)
	_exterior_lamp_light.light_color = Color(1.0, 0.92, 0.78)
	_exterior_lamp_light.light_energy = 0.0
	_exterior_lamp_light.omni_range = 10.5
	add_child(_exterior_lamp_light)


func _build_delivery_zone() -> void:
	var yellow_mat := _mat(Color(0.95, 0.74, 0.12), 0.55, 0.05)
	var dark_mat := _mat(Color(0.14, 0.16, 0.18), 0.6, 0.2)
	var wood_pallet_mat := MatLib.get_mat("wood_desk")

	_add_box_visual(self, Vector3(0.0, 0.012, 5.1), Vector3(4.2, 0.015, 0.10), yellow_mat)
	_add_box_visual(self, Vector3(0.0, 0.012, 7.9), Vector3(4.2, 0.015, 0.10), yellow_mat)
	_add_box_visual(self, Vector3(-2.05, 0.012, 6.5), Vector3(0.10, 0.015, 2.9), yellow_mat)
	_add_box_visual(self, Vector3(2.05, 0.012, 6.5), Vector3(0.10, 0.015, 2.9), yellow_mat)

	for bx in [-2.45, 2.45]:
		var b_cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.085
		cm.bottom_radius = 0.095
		cm.height = 0.92
		b_cyl.mesh = cm
		b_cyl.material_override = yellow_mat
		b_cyl.position = Vector3(float(bx), 0.46, 4.95)
		add_child(b_cyl)
		var b_cap := MeshInstance3D.new()
		var ccm := CylinderMesh.new()
		ccm.top_radius = 0.088
		ccm.bottom_radius = 0.088
		ccm.height = 0.12
		b_cap.mesh = ccm
		b_cap.material_override = dark_mat
		b_cap.position = Vector3(float(bx), 0.76, 4.95)
		add_child(b_cap)

	_add_box_visual(self, Vector3(-1.3, 0.025, 7.35), Vector3(1.15, 0.04, 0.82), wood_pallet_mat)

	var sign_in := Label3D.new()
	sign_in.text = "▼ LIEFERZONE (BESTELLUNGEN) ▼"
	sign_in.font_size = 38
	sign_in.pixel_size = 0.0055
	sign_in.position = Vector3(0.0, 3.28, 4.44)
	sign_in.rotation_degrees.y = 180.0
	sign_in.modulate = Color(1.0, 0.85, 0.25)
	add_child(sign_in)


func _build_lighting() -> void:
	var housing_mat := _mat(Color(0.20, 0.22, 0.26), 0.5, 0.4)
	var light_positions: Array[Vector3] = [
		Vector3(-2.4, 3.58, -1.0),
		Vector3(2.4, 3.58, 1.0),
		Vector3(9.0, 3.58, -1.2),
		Vector3(9.0, 3.58, 1.8),
		Vector3(17.0, 3.58, -1.5),
		Vector3(17.0, 3.58, 1.8),
	]
	for pos in light_positions:
		_add_box_visual(self, pos + Vector3(0.0, 0.19, 0.0), Vector3(1.92, 0.06, 0.30), housing_mat)
		var bar_mat := StandardMaterial3D.new()
		bar_mat.albedo_color = Color(0.98, 0.97, 0.95)
		bar_mat.emission_enabled = true
		bar_mat.emission = Color(0.98, 0.96, 0.92)
		bar_mat.emission_energy_multiplier = 1.35
		_light_bar_mats.append(bar_mat)
		_add_box_visual(self, pos + Vector3(0.0, 0.14, 0.0), Vector3(1.80, 0.04, 0.20), bar_mat)

		var spot := SpotLight3D.new()
		spot.position = pos - Vector3(0.0, 0.06, 0.0)
		spot.rotation_degrees.x = -90.0
		spot.light_color = Color(0.98, 0.97, 0.95)
		spot.light_energy = 4.4
		spot.spot_range = 10.5
		spot.spot_angle = 72.0
		spot.spot_attenuation = 1.15
		spot.shadow_enabled = false
		add_child(spot)
		_ceiling_lights.append(spot)

	_emergency_light = OmniLight3D.new()
	_emergency_light.position = Vector3(-4.0, 3.1, -3.5)
	_emergency_light.light_color = Color(1.0, 0.18, 0.14)
	_emergency_light.light_energy = 0.0
	_emergency_light.omni_range = 13.0
	add_child(_emergency_light)


func _build_reflection_probes() -> void:
	# Real-time box-projected ReflectionProbes give glossy epoxy floors & steel racks crisp reflections!
	var specs: Array = [
		{"pos": Vector3(0.0, 1.9, 0.0), "size": Vector3(11.4, 4.0, 9.4)},
		{"pos": Vector3(9.0, 1.9, 0.0), "size": Vector3(7.4, 4.0, 9.4)},
		{"pos": Vector3(17.0, 1.9, 0.0), "size": Vector3(9.4, 4.0, 9.4)},
	]
	for sp in specs:
		var d: Dictionary = sp
		var rp := ReflectionProbe.new()
		rp.position = d["pos"]
		rp.size = d["size"]
		rp.box_projection = true
		rp.interior = true
		rp.intensity = 0.85
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		add_child(rp)
		_reflection_probes.append(rp)


func _build_breaker_box() -> void:
	var root := Node3D.new()
	root.position = Vector3(-4.2, 1.55, -4.38)
	add_child(root)

	var metal := MatLib.make_brushed_metal(Color(0.28, 0.32, 0.37), 0.42, 0.55)
	var dark := _mat(Color(0.12, 0.14, 0.17), 0.55, 0.35)

	_add_box_visual(root, Vector3.ZERO, Vector3(0.76, 1.02, 0.20), metal)
	_add_box_visual(root, Vector3(0.0, 0.02, 0.085), Vector3(0.64, 0.72, 0.05), dark)
	_add_box_visual(root, Vector3(0.0, 0.43, 0.105), Vector3(0.68, 0.08, 0.02), _mat(Color(0.95, 0.78, 0.10), 0.5, 0.1))

	for cx in [-0.22, 0.22]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.032
		cm.height = 1.65
		pipe.mesh = cm
		pipe.material_override = _mat(Color(0.45, 0.49, 0.54), 0.4, 0.65)
		pipe.position = Vector3(float(cx), 1.32, -0.02)
		root.add_child(pipe)

	for b_idx in range(6):
		var bx := -0.22 + float(b_idx) * 0.088
		_add_box_visual(root, Vector3(bx, -0.14, 0.115), Vector3(0.055, 0.12, 0.03), _mat(Color(0.22, 0.25, 0.30), 0.5, 0.2))
		_add_box_visual(root, Vector3(bx, -0.12, 0.138), Vector3(0.03, 0.04, 0.03), _mat(Color(0.12, 0.52, 0.85), 0.4, 0.1))

	_add_box_visual(root, Vector3(0.0, 0.26, 0.112), Vector3(0.56, 0.07, 0.02), _mat(Color(0.08, 0.10, 0.12), 0.7, 0.1))
	_breaker_load_mat = StandardMaterial3D.new()
	_breaker_load_mat.albedo_color = Color(0.18, 0.92, 0.45)
	_breaker_load_mat.emission_enabled = true
	_breaker_load_mat.emission = Color(0.18, 0.92, 0.45)
	_breaker_load_mat.emission_energy_multiplier = 1.6
	_breaker_load_bar = _add_box_visual(root, Vector3(0.0, 0.26, 0.122), Vector3(0.52, 0.045, 0.015), _breaker_load_mat)

	_breaker_lever = MeshInstance3D.new()
	var lever_bm := BoxMesh.new()
	lever_bm.size = Vector3(0.28, 0.075, 0.16)
	_breaker_lever.mesh = lever_bm
	_breaker_lever.material_override = _mat(Color(0.88, 0.16, 0.14), 0.35, 0.25)
	_breaker_lever.position = Vector3(-0.06, 0.06, 0.14)
	root.add_child(_breaker_lever)

	_breaker_led_mat = StandardMaterial3D.new()
	_breaker_led_mat.albedo_color = Color(0.2, 1.0, 0.4)
	_breaker_led_mat.emission_enabled = true
	_breaker_led_mat.emission = Color(0.2, 1.0, 0.4)
	_breaker_led_mat.emission_energy_multiplier = 2.0
	_add_box_visual(root, Vector3(0.22, 0.08, 0.115), Vector3(0.08, 0.08, 0.03), _breaker_led_mat)

	_add_box_visual(root, Vector3(0.0, -0.37, 0.11), Vector3(0.36, 0.16, 0.07), dark)
	var port_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	_add_box_visual(root, Vector3(0.0, -0.37, 0.135), Vector3(0.24, 0.09, 0.055), port_mat)
	breaker_port_pos = root.position + Vector3(0.0, -0.37, 0.18)

	_breaker_label = Label3D.new()
	_breaker_label.text = "SICHERUNGSKASTEN"
	_breaker_label.font_size = 26
	_breaker_label.pixel_size = 0.0040
	_breaker_label.position = Vector3(0.0, 0.78, 0.11)
	_breaker_label.modulate = Color(0.18, 0.20, 0.22)
	root.add_child(_breaker_label)

	# Separate Contextual Interaction Zones: Upper Switch Lever vs Lower Yellow Power Socket!
	var sw_area := _make_interact_area(Vector3(0.84, 0.66, 0.40), {
		"interact_type": "wall_breaker",
		"entity_id": GameState.WALL_BREAKER_ID,
	})
	sw_area.position = Vector3(0.0, 0.18, 0.08)
	root.add_child(sw_area)

	var port_area := _make_interact_area(Vector3(0.56, 0.34, 0.42), {
		"interact_type": "power_port",
		"entity_id": GameState.WALL_BREAKER_ID,
	})
	port_area.position = Vector3(0.0, -0.37, 0.12)
	root.add_child(port_area)

	# 3D Spatial 50Hz Mains Transformer Hum right inside the Breaker Box!
	_breaker_audio = AudioStreamPlayer3D.new()
	_breaker_audio.stream = SfxManager.get_loop_stream("breaker_hum")
	_breaker_audio.max_distance = 6.5
	_breaker_audio.unit_size = 1.4
	_breaker_audio.volume_db = -60.0
	root.add_child(_breaker_audio)


func _build_hall_c_subpanel() -> void:
	# Dedicated Secondary Power Bus & 10G Fiber Switch inside Enterprise Hall C!
	var p_root := Node3D.new()
	p_root.position = Vector3(14.6, 1.55, -4.38)
	add_child(p_root)
	_add_box_visual(p_root, Vector3.ZERO, Vector3(0.72, 0.94, 0.20), MatLib.make_brushed_metal(Color(0.30, 0.32, 0.35), 0.42, 0.50))
	var y_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	_add_box_visual(p_root, Vector3(0.0, -0.34, 0.13), Vector3(0.30, 0.11, 0.055), y_mat)
	hall_c_breaker_port_pos = p_root.position + Vector3(0.0, -0.34, 0.18)

	_hall_c_breaker_label = Label3D.new()
	_hall_c_breaker_label.text = "HALLE-C STROMBUS"
	_hall_c_breaker_label.font_size = 25
	_hall_c_breaker_label.pixel_size = 0.0040
	_hall_c_breaker_label.position = Vector3(0.0, 0.68, 0.11)
	_hall_c_breaker_label.modulate = Color(0.18, 0.20, 0.22)
	p_root.add_child(_hall_c_breaker_label)

	var p_area := _make_interact_area(Vector3(0.84, 1.04, 0.44), {
		"interact_type": "power_port",
		"entity_id": GameState.HALL_C_BREAKER_ID,
	})
	p_area.position = Vector3(0.0, 0.0, 0.08)
	p_root.add_child(p_area)

	var n_root := Node3D.new()
	n_root.position = Vector3(16.6, 1.62, -4.38)
	add_child(n_root)
	_add_box_visual(n_root, Vector3.ZERO, Vector3(0.74, 0.44, 0.22), MatLib.make_brushed_metal(Color(0.20, 0.22, 0.25), 0.40, 0.55))
	var c_mat := _mat(Color(0.22, 0.46, 0.72), 0.45, 0.25)
	_add_box_visual(n_root, Vector3(0.0, -0.10, 0.13), Vector3(0.42, 0.09, 0.055), c_mat)
	hall_c_router_port_pos = n_root.position + Vector3(0.0, -0.10, 0.18)

	_hall_c_router_label = Label3D.new()
	_hall_c_router_label.text = "HALLE-C 10G FIBER"
	_hall_c_router_label.font_size = 25
	_hall_c_router_label.pixel_size = 0.0040
	_hall_c_router_label.position = Vector3(0.0, 0.44, 0.11)
	_hall_c_router_label.modulate = Color(0.18, 0.20, 0.22)
	n_root.add_child(_hall_c_router_label)

	var n_area := _make_interact_area(Vector3(0.84, 0.60, 0.42), {
		"interact_type": "net_port",
		"entity_id": GameState.HALL_C_ROUTER_ID,
	})
	n_area.position = Vector3(0.0, 0.0, 0.08)
	n_root.add_child(n_area)


func _build_extinguisher_station() -> void:
	var root := Node3D.new()
	root.position = Vector3(-2.8, 1.22, -4.36)
	add_child(root)

	_add_box_visual(root, Vector3(0.0, 0.12, -0.06), Vector3(0.34, 0.78, 0.03), _mat(Color(0.75, 0.12, 0.12), 0.55, 0.1))
	_add_box_visual(root, Vector3(0.0, -0.05, -0.03), Vector3(0.24, 0.42, 0.06), _mat(Color(0.20, 0.22, 0.25), 0.45, 0.5))

	_extinguisher_mesh_root = Node3D.new()
	root.add_child(_extinguisher_mesh_root)

	var red_mat := _mat(Color(0.88, 0.12, 0.12), 0.28, 0.38)
	var black_mat := _mat(Color(0.12, 0.13, 0.15), 0.45, 0.5)

	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10
	cyl.bottom_radius = 0.10
	cyl.height = 0.50
	body.mesh = cyl
	body.material_override = red_mat
	body.position = Vector3(0.0, 0.0, 0.09)
	_extinguisher_mesh_root.add_child(body)

	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.10
	sph.height = 0.14
	dome.mesh = sph
	dome.material_override = red_mat
	dome.position = Vector3(0.0, 0.25, 0.09)
	_extinguisher_mesh_root.add_child(dome)

	var band := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.103
	bcyl.bottom_radius = 0.103
	bcyl.height = 0.16
	band.mesh = bcyl
	band.material_override = _mat(Color(0.92, 0.92, 0.90), 0.6, 0.0)
	band.position = Vector3(0.0, 0.04, 0.09)
	_extinguisher_mesh_root.add_child(band)

	_add_box_visual(_extinguisher_mesh_root, Vector3(0.0, 0.34, 0.09), Vector3(0.05, 0.10, 0.05), black_mat)
	_add_box_visual(_extinguisher_mesh_root, Vector3(-0.07, 0.37, 0.09), Vector3(0.14, 0.025, 0.03), black_mat)
	_add_box_visual(_extinguisher_mesh_root, Vector3(0.09, 0.24, 0.11), Vector3(0.03, 0.28, 0.03), black_mat)
	var horn := MeshInstance3D.new()
	var hcyl := CylinderMesh.new()
	hcyl.top_radius = 0.02
	hcyl.bottom_radius = 0.055
	hcyl.height = 0.14
	horn.mesh = hcyl
	horn.material_override = black_mat
	horn.position = Vector3(0.09, 0.08, 0.12)
	_extinguisher_mesh_root.add_child(horn)

	var lbl := Label3D.new()
	lbl.text = "FEUERLÖSCHER"
	lbl.font_size = 24
	lbl.pixel_size = 0.0042
	lbl.position = Vector3(0.0, 0.62, 0.06)
	lbl.modulate = Color(1.0, 0.42, 0.38)
	root.add_child(lbl)

	var area := _make_interact_area(Vector3(0.48, 0.82, 0.42), {
		"interact_type": "extinguisher_station",
		"entity_id": "extinguisher_station",
	})
	area.position = Vector3(0.0, 0.04, 0.08)
	root.add_child(area)


func _build_wall_router() -> void:
	_router_root = Node3D.new()
	_router_root.position = Vector3(-1.0, 1.62, -4.38)
	add_child(_router_root)

	var silver_mat := MatLib.get_mat("galvanized_steel")
	var fpipe := MeshInstance3D.new()
	var fcm := CylinderMesh.new()
	fcm.top_radius = 0.024
	fcm.bottom_radius = 0.024
	fcm.height = 1.65
	fpipe.mesh = fcm
	fpipe.material_override = silver_mat
	fpipe.position = Vector3(0.0, 1.02, -0.02)
	_router_root.add_child(fpipe)

	_router_mesh_holder = Node3D.new()
	_router_root.add_child(_router_mesh_holder)

	_router_led_mat = StandardMaterial3D.new()
	_router_led_mat.albedo_color = Color(0.20, 0.72, 0.36)
	_router_led_mat.emission_enabled = true
	_router_led_mat.emission = Color(0.20, 0.72, 0.36)
	_router_led_mat.emission_energy_multiplier = 0.70

	router_port_pos = _router_root.position + Vector3(0.0, -0.09, 0.18)

	_router_label = Label3D.new()
	_router_label.text = "ALTER DSL-ROUTER (50 Mbit/s)"
	_router_label.font_size = 24
	_router_label.pixel_size = 0.0038
	_router_label.position = Vector3(0.0, 0.56, 0.10)
	_router_label.modulate = Color(0.18, 0.20, 0.22)
	_router_root.add_child(_router_label)

	var area := _make_interact_area(Vector3(0.84, 0.70, 0.44), {
		"interact_type": "wall_router",
		"entity_id": GameState.WALL_ROUTER_ID,
	})
	area.position = Vector3(0.0, 0.0, 0.08)
	_router_root.add_child(area)

	_rebuild_router_visuals(0)


func _rebuild_router_visuals(tier: int) -> void:
	if _router_mesh_holder == null:
		return
	_router_visual_tier = tier
	for c in _router_mesh_holder.get_children():
		c.queue_free()

	var dark_metal := MatLib.make_brushed_metal(Color(0.16, 0.18, 0.21), 0.40, 0.55)
	var galv := MatLib.get_mat("galvanized_steel")
	var perf := MatLib.get_mat("perforated_mesh")
	var port_blue := _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22)

	if tier == 0:
		# Tier 0: Old weathered 2005 plastic beige/cream home DSL router with 1 crooked antenna & 2 LAN ports!
		var old_plastic := _mat(Color(0.84, 0.81, 0.73), 0.72, 0.02)
		var grey_trim := _mat(Color(0.45, 0.44, 0.42), 0.65, 0.05)
		_add_box_visual(_router_mesh_holder, Vector3(0.0, -0.02, -0.02), Vector3(0.44, 0.24, 0.16), old_plastic)
		_add_box_visual(_router_mesh_holder, Vector3(0.0, -0.02, 0.062), Vector3(0.38, 0.18, 0.012), grey_trim)
		# Single crooked black DSL antenna
		var ant := MeshInstance3D.new()
		var ac := CylinderMesh.new()
		ac.top_radius = 0.007
		ac.bottom_radius = 0.011
		ac.height = 0.26
		ant.mesh = ac
		ant.material_override = dark_metal
		ant.position = Vector3(0.15, 0.21, -0.03)
		ant.rotation_degrees.z = -18.0
		_router_mesh_holder.add_child(ant)
		# 2 small LAN jacks + 1 tiny LED
		_add_box_visual(_router_mesh_holder, Vector3(-0.12, 0.03, 0.070), Vector3(0.028, 0.018, 0.012), _router_led_mat)
		for p_i in range(2):
			_add_box_visual(_router_mesh_holder, Vector3(-0.06 + float(p_i) * 0.12, -0.07, 0.072), Vector3(0.07, 0.055, 0.03), port_blue)
	elif tier == 1:
		# Tier 1: Matte-Black VDSL Business Router with 2 MIMO Antennas & 3 Ports
		_add_box_visual(_router_mesh_holder, Vector3.ZERO, Vector3(0.58, 0.30, 0.20), dark_metal)
		_add_box_visual(_router_mesh_holder, Vector3(0.0, 0.0, 0.102), Vector3(0.52, 0.22, 0.012), _mat(Color(0.10, 0.11, 0.13), 0.6, 0.2))
		for ax in [-0.22, 0.22]:
			var ant := MeshInstance3D.new()
			var ac := CylinderMesh.new()
			ac.top_radius = 0.008
			ac.bottom_radius = 0.013
			ac.height = 0.30
			ant.mesh = ac
			ant.material_override = dark_metal
			ant.position = Vector3(float(ax), 0.28, -0.02)
			ant.rotation_degrees.z = -10.0 if ax > 0 else 10.0
			_router_mesh_holder.add_child(ant)
		_add_box_visual(_router_mesh_holder, Vector3(-0.18, 0.06, 0.112), Vector3(0.045, 0.020, 0.012), _router_led_mat)
		for p_i in range(3):
			_add_box_visual(_router_mesh_holder, Vector3(-0.14 + float(p_i) * 0.14, -0.06, 0.112), Vector3(0.075, 0.060, 0.035), port_blue)
	elif tier == 2:
		# Tier 2: 1U Wall-Mount Brushed Steel 1G Glasfaser-Gateway with SFP cage & 5 ports!
		_add_box_visual(_router_mesh_holder, Vector3.ZERO, Vector3(0.74, 0.36, 0.24), dark_metal)
		_add_box_visual(_router_mesh_holder, Vector3(0.0, 0.0, 0.122), Vector3(0.68, 0.28, 0.015), perf)
		_add_box_visual(_router_mesh_holder, Vector3(-0.24, 0.07, 0.134), Vector3(0.08, 0.045, 0.022), galv) # SFP Fiber Cage
		_add_box_visual(_router_mesh_holder, Vector3(0.24, 0.07, 0.134), Vector3(0.045, 0.022, 0.012), _router_led_mat)
		for p_i in range(5):
			_add_box_visual(_router_mesh_holder, Vector3(-0.22 + float(p_i) * 0.11, -0.07, 0.134), Vector3(0.065, 0.055, 0.03), port_blue)
	else:
		# Tier 3 & 4: Full Wall-Mounted Enterprise 10G/100G Fiber Patch Cabinet with Dual Switch Blades & 24-Port Metallic Patch Panel!
		var cab_h := 0.56 if tier == 3 else 0.72
		_add_box_visual(_router_mesh_holder, Vector3(0.0, 0.06, 0.0), Vector3(0.84, cab_h, 0.30), dark_metal)
		_add_box_visual(_router_mesh_holder, Vector3(-0.39, 0.06, 0.14), Vector3(0.035, cab_h - 0.04, 0.03), galv)
		_add_box_visual(_router_mesh_holder, Vector3(0.39, 0.06, 0.14), Vector3(0.035, cab_h - 0.04, 0.03), galv)
		# Upper metallic 24-port patch panel + yellow fiber patch jumper
		_add_box_visual(_router_mesh_holder, Vector3(0.0, 0.20, 0.152), Vector3(0.72, 0.12, 0.022), galv)
		_add_box_visual(_router_mesh_holder, Vector3(0.0, 0.05, 0.152), Vector3(0.72, 0.12, 0.022), perf)
		_add_box_visual(_router_mesh_holder, Vector3(-0.24, 0.20, 0.168), Vector3(0.14, 0.025, 0.020), _mat(Color(0.86, 0.68, 0.14), 0.45, 0.05))
		_add_box_visual(_router_mesh_holder, Vector3(0.28, 0.20, 0.168), Vector3(0.055, 0.026, 0.016), _router_led_mat)
		for p_i in range(6):
			_add_box_visual(_router_mesh_holder, Vector3(-0.26 + float(p_i) * 0.104, -0.09, 0.156), Vector3(0.064, 0.055, 0.032), port_blue)


func _build_terminal_desk() -> void:
	var root := Node3D.new()
	root.position = Vector3(3.0, 0.0, -3.72)
	add_child(root)

	var wood_mat := MatLib.get_mat("wood_desk")
	var metal_mat := MatLib.make_brushed_metal(Color(0.14, 0.16, 0.20), 0.40, 0.58)
	var pad_mat := _mat(Color(0.10, 0.12, 0.16), 0.85, 0.0)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.14, 0.20, 0.26, 0.55)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.12

	_add_box_static(root, Vector3(0.0, 0.78, 0.0), Vector3(1.92, 0.055, 0.90), wood_mat)
	# Sleek metal desk frame legs (not thick blocky columns!)
	_add_box_visual(root, Vector3(-0.88, 0.39, -0.38), Vector3(0.045, 0.76, 0.045), metal_mat)
	_add_box_visual(root, Vector3(0.88, 0.39, -0.38), Vector3(0.045, 0.76, 0.045), metal_mat)
	_add_box_visual(root, Vector3(-0.88, 0.39, 0.38), Vector3(0.045, 0.76, 0.045), metal_mat)
	_add_box_visual(root, Vector3(0.88, 0.39, 0.38), Vector3(0.045, 0.76, 0.045), metal_mat)
	_add_box_visual(root, Vector3(-0.88, 0.14, 0.0), Vector3(0.040, 0.040, 0.76), metal_mat)
	_add_box_visual(root, Vector3(0.0, 0.22, -0.38), Vector3(1.74, 0.040, 0.040), metal_mat)
	_add_box_visual(root, Vector3(-0.10, 0.812, 0.14), Vector3(0.95, 0.008, 0.38), pad_mat)

	# Dual Thin-Bezel Monitors held on the Articulated Steel Clamp Arm!
	_add_box_visual(root, Vector3(-0.10, 1.24, -0.18), Vector3(0.86, 0.48, 0.030), metal_mat)
	var os_quad := MeshInstance3D.new()
	var oqm := QuadMesh.new()
	oqm.size = Vector2(0.82, 0.44)
	os_quad.mesh = oqm
	# Der Monitor zeigt live, was der Spieler am PC macht (für alle Mitspieler sichtbar).
	var pc_screen := PcScreenMirror.new()
	pc_screen.name = "PcScreenMirror"
	pc_screen.power_source = MatLib.get_os_screen_material()
	root.add_child(pc_screen)
	os_quad.material_override = pc_screen.make_screen_material()
	os_quad.position = Vector3(-0.10, 1.24, -0.162)
	# Die Spielerkamera fährt beim Hinsetzen an diese Fläche heran.
	os_quad.name = "PcScreenQuad"
	os_quad.add_to_group("pc_screen")
	root.add_child(os_quad)

	var side_mon := Node3D.new()
	side_mon.position = Vector3(-0.74, 1.20, -0.08)
	side_mon.rotation_degrees.y = 24.0
	root.add_child(side_mon)
	_add_box_visual(side_mon, Vector3.ZERO, Vector3(0.50, 0.40, 0.028), metal_mat)
	var tel_quad := MeshInstance3D.new()
	var tqm := QuadMesh.new()
	tqm.size = Vector2(0.46, 0.36)
	tel_quad.mesh = tqm
	tel_quad.material_override = MatLib.get_telemetry_screen_material()
	tel_quad.position = Vector3(0.0, 0.0, 0.017)
	side_mon.add_child(tel_quad)

	_desk_glow_light = OmniLight3D.new()
	_desk_glow_light.position = Vector3(-0.18, 1.28, 0.26)
	_desk_glow_light.light_color = Color(0.96, 0.96, 0.94)
	_desk_glow_light.light_energy = 0.28
	_desk_glow_light.omni_range = 2.6
	_desk_glow_light.shadow_enabled = false
	root.add_child(_desk_glow_light)

	# Detailed Workstation Props (Monitor Clamp Arm, 3-Drawer Pedestal, Sculpted Keyboard, Mouse, Mug with Handle, Desk Lamp, Detailed ATX Tower)
	BuildingPropFactory.build_terminal_desk_details(root)

	# 3D Spatial ATX Workstation Fan Whisper right at the Desk PC!
	_pc_audio = AudioStreamPlayer3D.new()
	_pc_audio.position = Vector3(0.68, 1.05, -0.10)
	_pc_audio.stream = SfxManager.get_loop_stream("pc_hum")
	_pc_audio.max_distance = 5.5
	_pc_audio.unit_size = 1.2
	_pc_audio.volume_db = -60.0
	root.add_child(_pc_audio)

	# Realistic Ergonomic 5-Caster Swivel Office Chair!
	var chair := BuildingPropFactory.build_office_chair()
	chair.position = Vector3(-0.22, 0.0, 0.86)
	chair.rotation_degrees.y = -18.0
	root.add_child(chair)

	var lbl := Label3D.new()
	lbl.text = "WINDOWS SERVER-PC [E]\nShop • Support • Upgrades"
	lbl.font_size = 26
	lbl.pixel_size = 0.0040
	lbl.position = root.position + Vector3(-0.08, 1.76, -0.14)
	lbl.modulate = Color(0.18, 0.20, 0.22)
	add_child(lbl)

	var area := _make_interact_area(Vector3(1.85, 1.25, 1.05), {
		"interact_type": "terminal",
		"entity_id": "terminal",
	})
	area.position = Vector3(0.0, 1.15, 0.0)
	root.add_child(area)


func _build_wall_decor() -> void:
	# Realistic Brushed Aluminum Company Sign Plaque with corner bolts (no neon!)
	var plaque_mat := MatLib.make_brushed_metal(Color(0.24, 0.26, 0.29), 0.38, 0.65)
	var bolt_mat := MatLib.get_mat("galvanized_steel")
	_add_box_visual(self, Vector3(3.0, 2.96, -4.45), Vector3(2.35, 0.46, 0.03), plaque_mat)
	for bx in [-1.08, 1.08]:
		for by in [-0.16, 0.16]:
			_add_box_visual(self, Vector3(3.0 + float(bx), 2.96 + float(by), -4.43), Vector3(0.03, 0.03, 0.02), bolt_mat)
	var brand := Label3D.new()
	brand.text = "GARAGE DATACENTER OPS"
	brand.font_size = 40
	brand.pixel_size = 0.0048
	brand.position = Vector3(3.0, 2.96, -4.42)
	brand.modulate = Color(0.92, 0.93, 0.94)
	add_child(brand)

	var wb := Node3D.new()
	wb.position = Vector3(-5.44, 1.98, 0.45)
	wb.rotation_degrees.y = 90.0
	add_child(wb)
	_add_box_visual(wb, Vector3.ZERO, Vector3(1.75, 1.05, 0.04), _mat(Color(0.55, 0.57, 0.60), 0.42, 0.55))
	_add_box_visual(wb, Vector3(0.0, 0.0, 0.022), Vector3(1.65, 0.95, 0.02), _mat(Color(0.94, 0.94, 0.92), 0.35, 0.0))
	BuildingPropFactory.build_whiteboard_tray(wb)
	var wb_txt := Label3D.new()
	wb_txt.text = "BETRIEBS-CHECKLISTE\n[✓] Alles mit der Hand [E]!\n[✓] Gelb=Strom, Blau=Netzwerk\n[✓] [E]/[F] am Rack: Hardware\n[ ] Alten DSL-Router upgraden!"
	wb_txt.font_size = 22
	wb_txt.pixel_size = 0.0042
	wb_txt.position = Vector3(0.0, 0.02, 0.04)
	wb_txt.modulate = Color(0.14, 0.16, 0.18)
	wb.add_child(wb_txt)


func _build_workshop_props() -> void:
	# 1. Realistic Heavy-Duty Slotted-Angle Industrial Workshop Rack (Cantilever Toolbox, Hollow Bins, Flanged Cable Reels, Duster Can, Spare Server!)
	var shelf := BuildingPropFactory.build_heavy_workshop_shelf()
	shelf.position = Vector3(-5.12, 0.0, -2.2)
	add_child(shelf)
	# Static collider so players don't walk through the workshop shelf
	_add_invisible_wall(Vector3(-5.12, 1.08, -2.2), Vector3(0.58, 2.16, 1.56))

	# 2. Realistic Tech Hardware Workbench (Pegboard + Hanging Wrenches/Screwdrivers + Lab Power Supply + Open Motherboard, CPU, GPU & RAM!)
	var bench := BuildingPropFactory.build_hardware_workbench()
	bench.position = Vector3(-4.95, 0.0, 2.25)
	bench.rotation_degrees.y = 90.0
	add_child(bench)
	_add_invisible_wall(Vector3(-4.95, 0.44, 2.25), Vector3(0.84, 0.88, 1.58))


func _make_interact_area(size: Vector3, meta: Dictionary) -> Area3D:
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


func _add_box_static(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body


func _add_invisible_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


func _add_box_visual(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
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
