class_name GarageBuilder
extends Node3D

## Wird gesendet, nachdem das Router-Modell (und damit router_port_pos) neu aufgebaut wurde.
signal router_visuals_rebuilt
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
var _emergency_light: OmniLight3D
var _exterior_lamp_light: OmniLight3D
var _street_lamp_light: OmniLight3D
var _street_lamp_mat: StandardMaterial3D

var _breaker_lever: MeshInstance3D
var _breaker_led_mat: StandardMaterial3D
var _breaker_load_bar: MeshInstance3D
## Drehpunkt des Hauptschalters aus dem Blender-Modell (ersetzt _breaker_lever für die Animation).
var _breaker_lever_pivot: Node3D
var _breaker_lever_on_deg: float = -28.0
var _breaker_lever_off_deg: float = 34.0
var _breaker_load_base_sx: float = 1.0
## Steckdosendeckel der Einspeisung (Blender-Modell): klappen auf, sobald dort ein Stromkabel steckt.
var _socket_lids: Array[Node3D] = []
var _socket_lid_closed: Array[float] = []
var _socket_lid_open: Array[float] = []
## Öffenbare Türen und Seitenwände aus den Blender-Modellen: panel_id -> {node, prop, closed, open, is_open, tween, label}
var _panels: Dictionary = {}
## 3D-Schraubsicherungen F1–F4 im Sicherungskasten (Kappe sichtbar = Sicherung steckt).
var _fuse_caps: Array[Node3D] = []
var _fuse_cap_mats: Array[StandardMaterial3D] = []
var _fuse_ind_mats: Array[StandardMaterial3D] = []
var _fuse_visual_key: String = ""
## Ablage neben dem Sicherungskasten: Ersatzsicherungen (Lagerbestand) und ausgebaute, durchgebrannte Sicherungen.
const FUSE_TRAY_POS := Vector3(0.52, -0.30, -0.055)
const FUSE_TRAY_TOP := 0.006
const FUSE_TRAY_STOCK_MAX := 6
const FUSE_TRAY_SCRAP_MAX := 3
var _fuse_tray_stock: Node3D
var _fuse_tray_scrap: Node3D
var _fuse_ok_tpl: Node3D
var _fuse_blown_tpl: Node3D
var _fuse_prev_states: Array = []
var _breaker_load_mat: StandardMaterial3D
var _breaker_label: Label3D

var _hall_c_breaker_label: Label3D
var _hall_c_router_label: Label3D
## Steckdosenleiste am Kasten in Halle C: 2 Reihen × 7 Buchsen (max. 6 + 4 × 2 = 14 Anschlüsse).
const HALL_C_SOCKET_COLS := 7
const HALL_C_SOCKET_ROWS := 2
var _hall_c_socket_pos: Array[Vector3] = []
var _hall_c_socket_covers: Array[MeshInstance3D] = []

var _router_root: Node3D
## Weltpositionen der LAN-Buchsen der aktuellen Router-Stufe (Reihenfolge = Buchsennummer).
var _router_jack_pos: Array[Vector3] = []
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
	GameState.panel_states_changed.connect(_on_panel_states_changed)


func _process(delta: float) -> void:
	_blink_time += delta
	_update_dynamic_visuals()


func apply_graphics_quality(quality: int) -> void:
	for i in range(_ceiling_lights.size()):
		# Soft SpotLight shadows nur für die 2-3 zentralen Lampen (spart massiv Shadow-Map-Draw-Calls bei vielen Racks!)
		_ceiling_lights[i].shadow_enabled = (quality >= 3 and i < 3) or (quality >= 2 and i < 2)
		_ceiling_lights[i].distance_fade_enabled = true
		_ceiling_lights[i].distance_fade_begin = 15.0
		_ceiling_lights[i].distance_fade_shadow = 8.0
		_ceiling_lights[i].distance_fade_length = 4.0
	# Die Proben rendern nur einmal (UPDATE_ONCE) und kosten danach kaum etwas.
	for rp in _reflection_probes:
		rp.visible = (quality >= 1)
	if _desk_glow_light != null:
		_desk_glow_light.visible = (quality >= 1)


func set_room_level(level: int) -> void:
	_set_wall_open(_partition_b, level >= 1)
	_set_wall_open(_partition_c, level >= 2)


## Shader vorwärmen: Für ein paar Bilder alle Hallen öffnen und alle Lampen mit Schatten und ohne
## Distanz-Ausblendung rendern. So kompiliert Godot die Schatten- und Materialvarianten hinter dem
## Ladebildschirm statt beim Freischalten einer Halle. Zurückgesetzt wird durch den Aufrufer über
## set_room_level() und apply_graphics_quality().
var _shader_prewarm_active := false


func begin_shader_prewarm() -> void:
	_shader_prewarm_active = true
	_set_wall_open(_partition_b, true)
	_set_wall_open(_partition_c, true)
	for light in _ceiling_lights:
		light.shadow_enabled = true
		light.distance_fade_enabled = false


func end_shader_prewarm() -> void:
	_shader_prewarm_active = false


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
		var enabled := (power_alive and allowed) or _shader_prewarm_active
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

	var lever_node: Node3D = _breaker_lever_pivot if _breaker_lever_pivot != null else _breaker_lever
	if lever_node != null:
		lever_node.rotation_degrees.x = _breaker_lever_on_deg if GameState.breaker_on else _breaker_lever_off_deg
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
		_breaker_load_bar.scale.x = _breaker_load_base_sx * (ratio if power_alive else 0.04)
		if not power_alive or ratio >= 1.0:
			_breaker_load_mat.emission = Color(0.92, 0.18, 0.14)
		elif ratio >= 0.8 or on_ups:
			_breaker_load_mat.emission = Color(0.92, 0.66, 0.14)
		else:
			_breaker_load_mat.emission = Color(0.24, 0.74, 0.38)
		_breaker_load_mat.emission_energy_multiplier = 0.72

	_update_fuse_visuals()

	if _breaker_label != null:
		var used_p := GameState.count_cables_on("power", GameState.WALL_BREAKER_ID)
		var max_p := GameState.get_max_ports("power", GameState.WALL_BREAKER_ID)
		var state_txt := tr("EIN") if GameState.breaker_on else (tr("USV-NOTSTROM!") if on_ups else tr("AUS (BLACKOUT!)"))
		if GameState.is_active and GameState.grid_outage_left > 0.0:
			state_txt = tr("NETZAUSFALL") + ((" / " + tr("USV")) if on_ups else "")
		_breaker_label.text = tr("SICHERUNGSKASTEN\nStatus: %s\n%dW / %dW\nSteckdosen: %d / %d") % [
			state_txt, GameState.total_watts, GameState.max_watts, used_p, max_p
		]
		_breaker_label.modulate = Color(0.95, 0.28, 0.24) if not power_alive else (Color(0.92, 0.64, 0.16) if (overloading or on_ups) else Color(0.18, 0.20, 0.22))

	if not _socket_lids.is_empty():
		var plugged := GameState.count_cables_on("power", GameState.WALL_BREAKER_ID)
		for i in range(_socket_lids.size()):
			var lid := _socket_lids[i]
			var lid_target: float = _socket_lid_open[i] if i < plugged else _socket_lid_closed[i]
			lid.rotation.x = lerpf(lid.rotation.x, lid_target, 0.2)

	if _hall_c_breaker_label != null:
		var used_cp := GameState.count_cables_on("power", GameState.HALL_C_BREAKER_ID)
		var max_cp := GameState.get_max_ports("power", GameState.HALL_C_BREAKER_ID)
		_hall_c_breaker_label.text = tr("HALLE-C STROMBUS\nSteckdosen: %d / %d") % [used_cp, max_cp]
		# Gesperrte Buchsen (über der aktuellen Stromstufe) sind abgedeckt
		for i in range(_hall_c_socket_covers.size()):
			_hall_c_socket_covers[i].visible = i >= max_cp
		# Neues Kabel startet an der nächsten freien Buchse
		if not _hall_c_socket_pos.is_empty():
			hall_c_breaker_port_pos = get_hall_c_socket_pos(mini(used_cp, maxi(max_cp - 1, 0)))

	if _hall_c_router_label != null:
		var used_cn := GameState.count_cables_on("network", GameState.HALL_C_ROUTER_ID)
		var max_cn := GameState.get_max_ports("network", GameState.HALL_C_ROUTER_ID)
		_hall_c_router_label.text = tr("HALLE-C 10G FIBER\nPorts: %d / %d") % [used_cn, max_cn]

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
		var net_txt := tr("DDOS-ANGRIFF! [E]") if GameState.ddos_active else ("ONLINE" if power_alive else "OFFLINE")
		var cap_warn := " ⚠ LIMIT!" if GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps else ""
		_router_label.text = tr("%s\n%s • %s / %s%s\nPorts: %d/%d  ([E] Kabel | [F] Upgrade)") % [
			tr(str(rt_info["label"])), net_txt,
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
	_add_box_static_occluded(self, Vector3(8.0, 1.9, -4.6), Vector3(27.5, 3.8, 0.25), wall_mat)
	_add_box_static_occluded(self, Vector3(-5.6, 1.9, 0.0), Vector3(0.25, 3.8, 9.4), wall_mat)
	_add_box_static_occluded(self, Vector3(21.6, 1.9, 0.0), Vector3(0.25, 3.8, 9.4), wall_mat)

	# South Wall with Open Garage Doorway (X -2.2..+2.2)
	_add_box_static_occluded(self, Vector3(-3.85, 1.9, 4.6), Vector3(3.3, 3.8, 0.25), wall_mat)
	_add_box_static_occluded(self, Vector3(11.85, 1.9, 4.6), Vector3(19.3, 3.8, 0.25), wall_mat)
	_add_box_static_occluded(self, Vector3(0.0, 3.4, 4.6), Vector3(4.4, 0.8, 0.25), wall_mat)

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

	# Die Hallenschilder an der Wand (HALLE B / HALLE C) wurden entfernt.


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

	# Verdeckt alles hinter der geschlossenen Wand. Beim Freischalten wird die Wand unsichtbar,
	# damit ist auch der Occluder abgeschaltet.
	var occ := OccluderInstance3D.new()
	var box_occ := BoxOccluder3D.new()
	box_occ.size = Vector3(0.22, 3.8, 8.95)
	occ.occluder = box_occ
	wall.add_child(occ)

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


## Rasenmaterial mit großflächiger Farbvariation (saftig, trocken, dunkle Flecken) in Weltkoordinaten.
func _make_meadow_material(grass_mat: Material) -> Material:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D grass_norm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D var_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float tex_scale = 0.45;
uniform float normal_strength = 0.6;
uniform vec3 tint_lush : source_color = vec3(0.86, 1.0, 0.80);
uniform vec3 tint_dry : source_color = vec3(1.10, 1.02, 0.68);
uniform vec3 tint_dark : source_color = vec3(0.62, 0.76, 0.58);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tex_scale;
	vec3 base = texture(grass_tex, uv).rgb;
	float big = texture(var_noise, wpos.xz * 0.012).r;
	float mid = texture(var_noise, wpos.xz * 0.05 + vec2(0.37, 0.71)).r;
	float fine = texture(var_noise, wpos.xz * 0.22 + vec2(0.13, 0.52)).r;
	vec3 tint = mix(tint_lush, tint_dry, smoothstep(0.45, 0.75, big));
	tint = mix(tint, tint_dark, smoothstep(0.5, 0.8, mid) * 0.6);
	tint *= 0.9 + fine * 0.2;
	ALBEDO = base * tint;
	NORMAL_MAP = texture(grass_norm, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
}
"""
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.01
	noise.fractal_octaves = 4
	noise.seed = 2024
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.noise = noise
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("var_noise", noise_tex)
	var std := grass_mat as StandardMaterial3D
	if std != null:
		if std.albedo_texture != null:
			sm.set_shader_parameter("grass_tex", std.albedo_texture)
		if std.normal_enabled and std.normal_texture != null:
			sm.set_shader_parameter("grass_norm", std.normal_texture)
	return sm


func _build_exterior_environment() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var grass_mat := MatLib.get_mat("grass")
	var meadow_mat := _make_meadow_material(grass_mat)
	var curb_mat := _mat(Color(0.55, 0.56, 0.58), 0.88, 0.0)
	var trunk_mat := _mat(Color(0.32, 0.22, 0.14), 0.9, 0.0)
	var leaf_mat := _mat(Color(0.20, 0.48, 0.22), 0.85, 0.0)
	var pole_mat := MatLib.make_brushed_metal(Color(0.22, 0.25, 0.28), 0.45, 0.6)

	# Concrete Driveway + Surrounding Lawn + Street beyond Z=10.6
	_add_box_static(self, Vector3(0.0, -0.11, 7.6), Vector3(7.4, 0.2, 6.2), asp_mat)
	_add_box_static(self, Vector3(-11.5, -0.13, 7.6), Vector3(15.6, 0.2, 6.4), meadow_mat)
	_add_box_static(self, Vector3(13.5, -0.13, 7.6), Vector3(19.6, 0.2, 6.4), meadow_mat)
	# Großer Rasen bis zum Horizont (keine graue Kante mehr hinter der Straße)
	_add_box_visual(self, Vector3(2.0, -0.16, 65.8), Vector3(240.0, 0.2, 110.0), meadow_mat)
	# Straße mit Mittel- und Randlinien
	_add_box_visual(self, Vector3(2.0, -0.12, 14.5), Vector3(160.0, 0.2, 7.6), asp_mat)
	var stripe_mat := _mat(Color(0.92, 0.92, 0.90), 0.75, 0.0)
	for sx in range(-78, 82, 4):
		_add_box_visual(self, Vector3(float(sx), -0.015, 14.5), Vector3(1.8, 0.01, 0.14), stripe_mat)
	for lz in [11.05, 17.95]:
		_add_box_visual(self, Vector3(2.0, -0.015, float(lz)), Vector3(160.0, 0.01, 0.12), stripe_mat)
	# Bordsteine: vorne mit Absenkung an der Einfahrt, hinten durchgehend
	_add_box_visual(self, Vector3(-40.85, 0.0, 10.79), Vector3(74.3, 0.12, 0.18), curb_mat)
	_add_box_visual(self, Vector3(42.85, 0.0, 10.79), Vector3(78.3, 0.12, 0.18), curb_mat)
	_add_box_visual(self, Vector3(0.0, -0.03, 10.79), Vector3(7.4, 0.06, 0.18), curb_mat)
	_add_box_visual(self, Vector3(2.0, 0.0, 18.39), Vector3(160.0, 0.12, 0.18), curb_mat)
	# Gehweg mit Plattenfugen auf der anderen Straßenseite
	var walk_mat := _mat(Color(0.60, 0.60, 0.58), 0.9, 0.0)
	var joint_mat := _mat(Color(0.36, 0.36, 0.35), 0.95, 0.0)
	_add_box_visual(self, Vector3(2.0, -0.05, 19.38), Vector3(160.0, 0.2, 1.8), walk_mat)
	for jx in range(-30, 36, 2):
		_add_box_visual(self, Vector3(float(jx), 0.051, 19.38), Vector3(0.025, 0.004, 1.8), joint_mat)
	# Durchgehende Hecke hinter dem Gehweg: Körper, gerundete Oberkante, unregelmäßige Blattbuckel
	var hedge_mat: Material = leaf_mat
	var grass_std := grass_mat as StandardMaterial3D
	if grass_std != null:
		var hm := grass_std.duplicate() as StandardMaterial3D
		hm.albedo_color = Color(0.78, 0.92, 0.55)
		# Leichte Eigenhelligkeit, damit die Straßenseite im Schatten nicht schwarz wird
		hm.emission_enabled = true
		hm.emission = Color(0.12, 0.22, 0.06)
		hm.emission_energy_multiplier = 0.9
		# Weltkoordinaten statt Box-UVs: sonst wird die Textur über die ganze Heckenlänge gestreckt
		hm.uv1_triplanar = true
		hm.uv1_world_triplanar = true
		hm.uv1_scale = Vector3(0.9, 0.9, 0.9)
		hedge_mat = hm
	var hedge_x0 := -40.0
	var hedge_x1 := 44.0
	var hedge_len := hedge_x1 - hedge_x0
	var hedge_mid := (hedge_x0 + hedge_x1) * 0.5
	var hedge_z := 20.75
	_add_box_visual(self, Vector3(hedge_mid, 0.36, hedge_z), Vector3(hedge_len, 0.82, 0.74), hedge_mat)
	var hedge_crown := MeshInstance3D.new()
	var hedge_cm := CylinderMesh.new()
	hedge_cm.top_radius = 0.37
	hedge_cm.bottom_radius = 0.37
	hedge_cm.height = hedge_len
	hedge_cm.radial_segments = 20
	hedge_crown.mesh = hedge_cm
	hedge_crown.material_override = hedge_mat
	hedge_crown.rotation_degrees.z = 90.0
	hedge_crown.scale = Vector3(0.45, 1.0, 1.0) # flach gewölbt: ca. 17 cm über der Kastenkante
	hedge_crown.position = Vector3(hedge_mid, 0.77, hedge_z)
	add_child(hedge_crown)
	# Blattbuckel oben und an der Straßenseite brechen die gerade Silhouette auf (eine MultiMesh = ein Draw Call)
	var bump_mesh := SphereMesh.new()
	bump_mesh.radius = 0.3
	bump_mesh.height = 0.6
	bump_mesh.radial_segments = 12
	bump_mesh.rings = 6
	var bump_step := 0.5
	var bump_count := int(hedge_len / bump_step)
	var bumps := MultiMesh.new()
	bumps.transform_format = MultiMesh.TRANSFORM_3D
	bumps.use_colors = true # muss vor instance_count gesetzt werden
	bumps.mesh = bump_mesh
	bumps.instance_count = bump_count * 4
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 4711
	# Vier Grundtöne (dunkles Grün, frisches Hellgrün, gelbliche Spitzen, bläuliches Grün), pro Buckel gewürfelt
	var hedge_tints: Array[Color] = [
		Color(0.60, 0.78, 0.40),
		Color(0.80, 0.96, 0.52),
		Color(1.0, 0.98, 0.64),
		Color(0.56, 0.78, 0.60),
	]
	var tint_light := Color(1.0, 1.0, 0.80)
	for bi in range(bump_count):
		var bx := hedge_x0 + (float(bi) + hrng.randf()) * bump_step
		# Oberseite: runde Buckel, unten tief im Kasten versenkt, damit nichts schwebt
		var s_top := Vector3(hrng.randf_range(1.0, 1.7), hrng.randf_range(0.55, 0.9), hrng.randf_range(0.9, 1.3))
		var p_top := Vector3(bx, 0.64 + hrng.randf_range(-0.03, 0.05), hedge_z + hrng.randf_range(-0.1, 0.1))
		bumps.set_instance_transform(bi * 4, Transform3D(Basis.from_scale(s_top), p_top))
		bumps.set_instance_color(bi * 4, hedge_tints[hrng.randi() % hedge_tints.size()].lerp(tint_light, hrng.randf_range(0.0, 0.3)))
		# Vordere Oberkante: überdeckt den Übergang zwischen Kastenkante und Krone
		var s_edge := Vector3(hrng.randf_range(0.8, 1.2), hrng.randf_range(0.6, 0.9), hrng.randf_range(0.8, 1.1))
		var p_edge := Vector3(bx + hrng.randf_range(-0.2, 0.2), 0.60 + hrng.randf_range(-0.04, 0.04), hedge_z - 0.14)
		bumps.set_instance_transform(bi * 4 + 1, Transform3D(Basis.from_scale(s_edge), p_edge))
		bumps.set_instance_color(bi * 4 + 1, hedge_tints[hrng.randi() % hedge_tints.size()].lerp(tint_light, hrng.randf_range(0.0, 0.3)))
		# Straßenseite: flache Buckel dicht an der Kastenfront
		var s_side := Vector3(hrng.randf_range(0.9, 1.4), hrng.randf_range(0.7, 1.0), hrng.randf_range(0.45, 0.65))
		var p_side := Vector3(bx, hrng.randf_range(0.40, 0.66), hedge_z - 0.25)
		bumps.set_instance_transform(bi * 4 + 2, Transform3D(Basis.from_scale(s_side), p_side))
		bumps.set_instance_color(bi * 4 + 2, hedge_tints[hrng.randi() % hedge_tints.size()].lerp(tint_light, hrng.randf_range(0.0, 0.3)))
		# Untere Reihe an der Front: versetzt, damit die Kastenwand nicht als dunkle Fläche stehen bleibt
		var s_low := Vector3(hrng.randf_range(0.9, 1.4), hrng.randf_range(0.7, 1.0), hrng.randf_range(0.45, 0.65))
		var p_low := Vector3(bx + bump_step * 0.5, hrng.randf_range(0.10, 0.38), hedge_z - 0.25)
		bumps.set_instance_transform(bi * 4 + 3, Transform3D(Basis.from_scale(s_low), p_low))
		bumps.set_instance_color(bi * 4 + 3, hedge_tints[hrng.randi() % hedge_tints.size()].lerp(tint_light, hrng.randf_range(0.0, 0.3)))
	var bump_mat: Material = hedge_mat
	var hedge_std := hedge_mat as StandardMaterial3D
	if hedge_std != null:
		var bm := hedge_std.duplicate() as StandardMaterial3D
		bm.vertex_color_use_as_albedo = true
		bump_mat = bm
	var bumps_mi := MultiMeshInstance3D.new()
	bumps_mi.multimesh = bumps
	bumps_mi.material_override = bump_mat
	add_child(bumps_mi)

	# Driveway curbs
	_add_box_visual(self, Vector3(-3.75, 0.03, 7.6), Vector3(0.16, 0.08, 6.0), curb_mat)
	_add_box_visual(self, Vector3(3.75, 0.03, 7.6), Vector3(0.16, 0.08, 6.0), curb_mat)

	# Invisible driveway containment walls
	_add_invisible_wall(Vector3(-6.2, 2.0, 7.5), Vector3(0.3, 4.0, 6.2))
	_add_invisible_wall(Vector3(13.2, 2.0, 7.5), Vector3(0.3, 4.0, 6.2))
	_add_invisible_wall(Vector3(3.5, 2.0, 10.4), Vector3(20.0, 4.0, 0.3))

	# Weißer Lattenzaun links und rechts der Einfahrt (statt massiver Holzwand)
	var fence_mat := _mat(Color(0.93, 0.92, 0.88), 0.7, 0.0)
	for seg in [Vector2(-10.8, -4.0), Vector2(3.9, 13.1)]:
		var seg_v: Vector2 = seg
		var seg_len := seg_v.y - seg_v.x
		var mid := (seg_v.x + seg_v.y) * 0.5
		_add_box_visual(self, Vector3(mid, 0.25, 10.4), Vector3(seg_len, 0.07, 0.04), fence_mat)
		_add_box_visual(self, Vector3(mid, 0.80, 10.4), Vector3(seg_len, 0.07, 0.04), fence_mat)
		var n := int(seg_len / 0.16)
		for i in range(n + 1):
			var px := seg_v.x + seg_len * float(i) / float(n)
			_add_box_visual(self, Vector3(px, 0.5, 10.43), Vector3(0.07, 1.0, 0.025), fence_mat)
		var posts := int(ceil(seg_len / 2.0))
		for p in range(posts + 1):
			var post_x := seg_v.x + seg_len * float(p) / float(posts)
			_add_box_visual(self, Vector3(post_x, 0.56, 10.37), Vector3(0.10, 1.12, 0.10), fence_mat)

	# Organic multi-branch realistic trees across yard & street
	var tree_spots: Array[Vector3] = [
		Vector3(-6.8, 0.0, 7.8),
		Vector3(6.8, 0.0, 7.5),
		Vector3(-19.0, 0.0, 22.2),
		Vector3(-9.5, 0.0, 22.0),
		Vector3(-1.5, 0.0, 22.4),
		Vector3(7.2, 0.0, 22.1),
		Vector3(15.5, 0.0, 22.3),
		Vector3(24.0, 0.0, 22.0),
	]
	for tp in tree_spots:
		BuildingPropFactory.build_realistic_tree(self, tp)
	# Baumreihe im Hintergrund, damit der Horizont nicht leer wirkt
	var trng := RandomNumberGenerator.new()
	trng.seed = 1337
	var tx := -38.0
	while tx < 46.0:
		BuildingPropFactory.build_realistic_tree(self, Vector3(tx, 0.0, trng.randf_range(30.0, 38.0)), trng.randf_range(1.2, 1.6))
		tx += trng.randf_range(5.0, 8.0)

	# Architectural Exterior Brick Cladding, Gutter & Recycling Bin
	var brick_mat := MatLib.get_mat("exterior_brick")
	_add_box_visual(self, Vector3(-3.85, 1.9, 4.76), Vector3(3.35, 3.82, 0.08), brick_mat)
	_add_box_visual(self, Vector3(11.85, 1.9, 4.76), Vector3(19.35, 3.82, 0.08), brick_mat)
	_add_box_visual(self, Vector3(0.0, 3.4, 4.76), Vector3(4.42, 0.82, 0.08), brick_mat)
	# Aluminum Rain Gutter & Vertical Downspout
	_add_box_visual(self, Vector3(8.0, 3.92, 4.88), Vector3(27.8, 0.11, 0.12), pole_mat)
	_add_box_visual(self, Vector3(-5.35, 1.95, 4.86), Vector3(0.09, 3.9, 0.09), pole_mat)
	# Das feste Außen-Klimagerät ist entfernt. Die Goldis-Wärmepumpe stellt der Spieler selbst auf den Rasen.
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

	var cap_lbl := Label3D.new()
	cap_lbl.text = "Belegt: 0 / %d Plätze" % GameState.DELIVERY_ZONE_MAX_CRATES
	cap_lbl.font_size = 26
	cap_lbl.pixel_size = 0.0046
	cap_lbl.position = Vector3(0.0, 3.00, 4.44)
	cap_lbl.rotation_degrees.y = 180.0
	cap_lbl.modulate = Color(0.74, 0.96, 0.78)
	add_child(cap_lbl)
	var update_cap := func() -> void:
		if not is_instance_valid(cap_lbl):
			return
		var used := GameState.get_delivery_zone_used_slots()
		var mx := GameState.DELIVERY_ZONE_MAX_CRATES
		cap_lbl.text = tr("Lieferfläche: %d / %d Plätze") % [used, mx]
		if used >= mx:
			cap_lbl.modulate = Color(1.0, 0.34, 0.26)
		elif used >= mx - 3:
			cap_lbl.modulate = Color(1.0, 0.76, 0.22)
		else:
			cap_lbl.modulate = Color(0.68, 0.96, 0.76)
	GameState.crates_changed.connect(update_cap)
	GameState.van_updated.connect(update_cap)
	GameState.world_snapshot_loaded.connect(update_cap)
	update_cap.call()


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

	# Blender-Modell (assets/models/breaker_box.glb) ersetzt das prozedurale Modell, falls vorhanden.
	var bb_model := ModelLoader.instantiate_custom_model("breaker_box")
	if bb_model != null:
		root.add_child(bb_model)
		_setup_breaker_model(bb_model, root)
	else:
		# Unterverteilung wie im Technikraum: lichtgraues Stahlblechgehäuse, Abdeckung mit zwei Reihen
		# Reiheneinbaugeräten auf Hutschienen, Lastanzeige oben und gelben Einspeisedosen unten.
		# Außenmaße, Hebel, LED, Lastbalken und Port-Position entsprechen dem alten Modell.
		var housing := _mat(Color(0.74, 0.75, 0.74), 0.52, 0.18)
		var housing_edge := _mat(Color(0.63, 0.64, 0.63), 0.46, 0.25)
		var mount_plate := MatLib.make_brushed_metal(Color(0.46, 0.49, 0.52), 0.40, 0.70)
		var galv := MatLib.get_mat("galvanized_steel")
		var module_white := _mat(Color(0.93, 0.93, 0.91), 0.36, 0.0)
		var module_grey := _mat(Color(0.32, 0.34, 0.36), 0.45, 0.0)
		var toggle_blue := _mat(Color(0.14, 0.38, 0.72), 0.32, 0.0)
		var toggle_dark := _mat(Color(0.16, 0.17, 0.19), 0.40, 0.0)
		var window_grey := _mat(Color(0.22, 0.24, 0.26), 0.25, 0.0)
		var window_green := _mat(Color(0.18, 0.62, 0.30), 0.40, 0.0)
		var label_paper := _mat(Color(0.96, 0.95, 0.88), 0.85, 0.0)
		var dark := _mat(Color(0.10, 0.11, 0.13), 0.55, 0.20)
		var screen := _mat(Color(0.04, 0.06, 0.05), 0.15, 0.0)
		var screw_mat := MatLib.make_brushed_metal(Color(0.72, 0.74, 0.76), 0.30, 0.90)
		var lever_red := _mat(Color(0.86, 0.14, 0.12), 0.30, 0.10)
		var warn_yellow := _mat(Color(0.95, 0.78, 0.10), 0.5, 0.1)
		var test_yellow := _mat(Color(0.95, 0.80, 0.16), 0.4, 0.0)
		var port_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
		var conduit := _mat(Color(0.45, 0.49, 0.54), 0.4, 0.65)
		var gland := _mat(Color(0.20, 0.21, 0.23), 0.6, 0.0)

		# Gehäuse, umlaufende Kante und Montageplatte (in den Ausschnitten sichtbar)
		_add_box_visual(root, Vector3(0.0, 0.0, -0.01), Vector3(0.76, 1.02, 0.18), housing)
		_add_box_visual(root, Vector3(0.0, 0.4925, 0.09), Vector3(0.76, 0.035, 0.02), housing_edge)
		_add_box_visual(root, Vector3(0.0, -0.4925, 0.09), Vector3(0.76, 0.035, 0.02), housing_edge)
		_add_box_visual(root, Vector3(-0.3625, 0.0, 0.09), Vector3(0.035, 0.95, 0.02), housing_edge)
		_add_box_visual(root, Vector3(0.3625, 0.0, 0.09), Vector3(0.035, 0.95, 0.02), housing_edge)
		_add_box_visual(root, Vector3(0.0, 0.0, 0.082), Vector3(0.69, 0.95, 0.006), mount_plate)

		# Abdeckung mit zwei Ausschnitten: Reihe 1 bei y 0.04..0.16, Reihe 2 bei y -0.20..-0.08
		_add_box_visual(root, Vector3(0.0, 0.3175, 0.09), Vector3(0.69, 0.315, 0.012), housing)
		_add_box_visual(root, Vector3(0.0, -0.02, 0.09), Vector3(0.69, 0.12, 0.012), housing)
		_add_box_visual(root, Vector3(0.0, -0.3375, 0.09), Vector3(0.69, 0.275, 0.012), housing)
		_add_box_visual(root, Vector3(0.0, 0.10, 0.087), Vector3(0.66, 0.035, 0.006), galv)
		_add_box_visual(root, Vector3(0.0, -0.14, 0.087), Vector3(0.66, 0.035, 0.006), galv)
		for i in range(4):
			var sx := -0.32 if i % 2 == 0 else 0.32
			var sy := 0.455 if i < 2 else -0.455
			_add_cyl_visual(root, Vector3(sx, sy, 0.098), 0.008, 0.008, 0.004, screw_mat, Vector3(90, 0, 0), 12)
			_add_box_visual(root, Vector3(sx, sy, 0.1002), Vector3(0.011, 0.002, 0.001), dark)

		# Warnschild und Lastanzeige
		_add_box_visual(root, Vector3(0.0, 0.40, 0.0975), Vector3(0.66, 0.05, 0.003), warn_yellow)
		_add_small_label(root, Vector3(0.0, 0.40, 0.0995), "ACHTUNG  400 V", 26, 0.0015, Color(0.08, 0.08, 0.09))
		_add_small_label(root, Vector3(0.0, 0.335, 0.0965), "NETZLAST", 22, 0.0014, Color(0.20, 0.22, 0.24))
		_add_box_visual(root, Vector3(0.0, 0.26, 0.100), Vector3(0.60, 0.10, 0.010), dark)
		_add_box_visual(root, Vector3(0.0, 0.26, 0.1065), Vector3(0.56, 0.07, 0.003), screen)
		for i in range(5):
			_add_box_visual(root, Vector3(-0.26 + 0.13 * float(i), 0.287, 0.1085), Vector3(0.002, 0.008, 0.001), label_paper)
		_breaker_load_mat = StandardMaterial3D.new()
		_breaker_load_mat.albedo_color = Color(0.18, 0.92, 0.45)
		_breaker_load_mat.emission_enabled = true
		_breaker_load_mat.emission = Color(0.18, 0.92, 0.45)
		_breaker_load_mat.emission_energy_multiplier = 1.6
		_breaker_load_bar = _add_box_visual(root, Vector3(0.0, 0.255, 0.109), Vector3(0.52, 0.035, 0.003), _breaker_load_mat)

		# Reihe 1: Hauptschalter mit rotem Kipphebel (EIN = oben), Meldemodul mit Status-LED,
		# 6 Leitungsschutzschalter, FI-Schutzschalter mit Prüftaste, Überspannungsschutz
		_add_box_visual(root, Vector3(-0.27, 0.10, 0.105), Vector3(0.106, 0.11, 0.05), module_white)
		_add_box_visual(root, Vector3(-0.27, 0.060, 0.1305), Vector3(0.05, 0.012, 0.002), window_grey)
		_breaker_lever = MeshInstance3D.new()
		var lever_bm := BoxMesh.new()
		lever_bm.size = Vector3(0.07, 0.026, 0.06)
		_breaker_lever.mesh = lever_bm
		_breaker_lever.material_override = lever_red
		_breaker_lever.position = Vector3(-0.27, 0.10, 0.132)
		_breaker_lever.rotation_degrees.x = -28.0
		root.add_child(_breaker_lever)
		_add_box_visual(_breaker_lever, Vector3(0.0, 0.0, 0.034), Vector3(0.082, 0.032, 0.014), lever_red)

		_breaker_led_mat = StandardMaterial3D.new()
		_breaker_led_mat.albedo_color = Color(0.2, 1.0, 0.4)
		_breaker_led_mat.emission_enabled = true
		_breaker_led_mat.emission = Color(0.2, 1.0, 0.4)
		_breaker_led_mat.emission_energy_multiplier = 2.0
		_add_box_visual(root, Vector3(-0.18, 0.10, 0.105), Vector3(0.036, 0.11, 0.05), module_white)
		_add_cyl_visual(root, Vector3(-0.18, 0.125, 0.1325), 0.010, 0.010, 0.005, _breaker_led_mat, Vector3(90, 0, 0), 16)
		_add_box_visual(root, Vector3(-0.18, 0.075, 0.1305), Vector3(0.022, 0.024, 0.002), window_grey)

		for i in range(6):
			_add_breaker_module(root, Vector3(-0.13 + 0.038 * float(i), 0.10, 0.0), 0.038, module_white, toggle_blue, window_grey)
		_add_breaker_module(root, Vector3(0.135, 0.10, 0.0), 0.072, module_white, toggle_dark, window_grey)
		_add_cyl_visual(root, Vector3(0.158, 0.138, 0.1325), 0.007, 0.007, 0.006, test_yellow, Vector3(90, 0, 0), 12)
		_add_breaker_module(root, Vector3(0.215, 0.10, 0.0), 0.072, module_grey, toggle_dark, window_green)
		_add_box_visual(root, Vector3(0.30, 0.10, 0.09), Vector3(0.09, 0.12, 0.012), module_white)

		# Reihe 2: Vier Schraubsicherungen F1–F4 (per [E] einsetzen), zweiter FI, Rest mit Blindabdeckung
		var brass := MatLib.make_brushed_metal(Color(0.78, 0.62, 0.30), 0.35, 0.85)
		_fuse_caps.clear()
		_fuse_cap_mats.clear()
		_fuse_ind_mats.clear()
		_fuse_visual_key = ""
		for i in range(GameState.FUSE_SLOT_COUNT):
			var fx := -0.27 + 0.11 * float(i)
			var fy := -0.14
			# Sockel mit Messing-Gewindering und dunkler Öffnung (sichtbar, wenn der Steckplatz leer ist)
			_add_box_visual(root, Vector3(fx, fy, 0.105), Vector3(0.10, 0.11, 0.05), module_white)
			_add_cyl_visual(root, Vector3(fx, fy, 0.1315), 0.031, 0.031, 0.003, brass, Vector3(90, 0, 0), 20)
			_add_cyl_visual(root, Vector3(fx, fy, 0.1335), 0.022, 0.022, 0.002, dark, Vector3(90, 0, 0), 20)

			# Schraubkappe mit Kennmelder: grün = intakt, rot und verrußt = durchgebrannt
			var cap := Node3D.new()
			cap.position = Vector3(fx, fy, 0.133)
			root.add_child(cap)
			var cap_mat := StandardMaterial3D.new()
			cap_mat.albedo_color = Color(0.86, 0.86, 0.84)
			cap_mat.roughness = 0.55
			var ind_mat := StandardMaterial3D.new()
			ind_mat.emission_enabled = true
			_add_cyl_visual(cap, Vector3(0.0, 0.0, 0.006), 0.029, 0.029, 0.012, cap_mat, Vector3(90, 0, 0), 20)
			_add_cyl_visual(cap, Vector3(0.0, 0.0, 0.021), 0.024, 0.026, 0.018, cap_mat, Vector3(90, 0, 0), 20)
			_add_cyl_visual(cap, Vector3(0.0, 0.0, 0.0315), 0.010, 0.010, 0.003, ind_mat, Vector3(90, 0, 0), 16)
			_fuse_caps.append(cap)
			_fuse_cap_mats.append(cap_mat)
			_fuse_ind_mats.append(ind_mat)

			_add_small_label(root, Vector3(fx, -0.212, 0.0990), "F%d" % (i + 1), 22, 0.0012, Color(0.12, 0.12, 0.14))

			var slot_area := _make_interact_area(Vector3(0.105, 0.12, 0.30), {
				"interact_type": "fuse_slot",
				"entity_id": "wall_breaker_fuse_%d" % i,
				"slot_idx": i,
			})
			slot_area.set_meta("slot_idx", i)
			slot_area.position = Vector3(fx, fy, 0.12)
			root.add_child(slot_area)
		_add_breaker_module(root, Vector3(0.17, -0.14, 0.0), 0.072, module_white, toggle_dark, window_grey)
		_add_box_visual(root, Vector3(0.2775, -0.14, 0.09), Vector3(0.135, 0.12, 0.012), module_white)

		# Beschriftungsstreifen unter den Reihen
		_add_box_visual(root, Vector3(0.0, 0.028, 0.097), Vector3(0.66, 0.016, 0.002), label_paper)
		_add_box_visual(root, Vector3(0.0, -0.212, 0.097), Vector3(0.66, 0.016, 0.002), label_paper)

		# Einspeisung unten: Klemmengehäuse mit einer mittigen gelben Steckdose mit Klappdeckel
		_add_box_visual(root, Vector3(0.0, -0.37, 0.112), Vector3(0.40, 0.17, 0.04), dark)
		_add_small_label(root, Vector3(0.0, -0.305, 0.1325), "EINSPEISUNG 230 V", 18, 0.0012, Color(0.85, 0.86, 0.86))
		_add_cyl_visual(root, Vector3(0.0, -0.378, 0.145), 0.030, 0.030, 0.03, port_mat, Vector3(90, 0, 0), 20)
		_add_cyl_visual(root, Vector3(0.0, -0.378, 0.161), 0.021, 0.021, 0.003, dark, Vector3(90, 0, 0), 20)
		_add_box_visual(root, Vector3(0.0, -0.338, 0.150), Vector3(0.05, 0.012, 0.014), port_mat)

		# Kabelschutzrohre nach oben mit Verschraubung und Rohrschellen
		for i in range(2):
			var cx := -0.22 + 0.44 * float(i)
			_add_cyl_visual(root, Vector3(cx, 1.32, -0.02), 0.032, 0.032, 1.65, conduit, Vector3.ZERO, 20)
			_add_cyl_visual(root, Vector3(cx, 0.525, -0.02), 0.044, 0.044, 0.035, gland, Vector3.ZERO, 20)
			for k in range(2):
				_add_box_visual(root, Vector3(cx, 0.95 + 0.6 * float(k), -0.045), Vector3(0.09, 0.022, 0.03), galv)

	breaker_port_pos = root.position + Vector3(0.0, -0.37, 0.18)

	# Separate Contextual Interaction Zones: Upper Switch Lever vs Lower Yellow Power Socket!
	# Hauptschalter-Zone endet oberhalb der Sicherungsreihe, damit sich die Zonen nicht überlappen.
	var sw_area := _make_interact_area(Vector3(0.84, 0.50, 0.40), {
		"interact_type": "wall_breaker",
		"entity_id": GameState.WALL_BREAKER_ID,
	})
	sw_area.position = Vector3(0.0, 0.27, 0.08)
	root.add_child(sw_area)

	var port_area := _make_interact_area(Vector3(0.30, 0.30, 0.42), {
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


func _update_fuse_visuals() -> void:
	var fuses: Array = GameState.breaker_fuses
	var key := "%s#%d" % [str(fuses), GameState.fuse_stock]
	if key == _fuse_visual_key:
		return
	_fuse_visual_key = key
	_update_fuse_tray(fuses)
	for i in range(_fuse_caps.size()):
		var fz_state := str(fuses[i]) if i < fuses.size() else "empty"
		_fuse_caps[i].visible = fz_state != "empty"
		var cap_mat := _fuse_cap_mats[i]
		var ind_mat := _fuse_ind_mats[i]
		if fz_state == "blown":
			cap_mat.albedo_color = Color(0.24, 0.21, 0.19)
			ind_mat.albedo_color = Color(0.90, 0.15, 0.12)
			ind_mat.emission = Color(0.90, 0.15, 0.12)
			ind_mat.emission_energy_multiplier = 1.6
		else:
			cap_mat.albedo_color = Color(0.86, 0.86, 0.84)
			ind_mat.albedo_color = Color(0.22, 0.85, 0.38)
			ind_mat.emission = Color(0.22, 0.85, 0.38)
			ind_mat.emission_energy_multiplier = 1.1


func _build_hall_c_subpanel() -> void:
	# Dedicated Secondary Power Bus & 10G Fiber Switch inside Enterprise Hall C!
	var p_root := Node3D.new()
	p_root.position = Vector3(14.6, 1.55, -4.38)
	add_child(p_root)
	_add_box_visual(p_root, Vector3.ZERO, Vector3(0.72, 0.94, 0.20), MatLib.make_brushed_metal(Color(0.30, 0.32, 0.35), 0.42, 0.50))
	var y_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	var sock_mat := _mat(Color(0.08, 0.08, 0.09), 0.70, 0.0)
	var cover_mat := _mat(Color(0.52, 0.54, 0.57), 0.55, 0.30)
	# Gelbe Trägerplatte mit 2 × 7 Buchsen statt eines einzelnen Anschlussblocks
	_add_box_visual(p_root, Vector3(0.0, -0.265, 0.11), Vector3(0.64, 0.25, 0.02), y_mat)
	_hall_c_socket_pos.clear()
	_hall_c_socket_covers.clear()
	for r in range(HALL_C_SOCKET_ROWS):
		for c in range(HALL_C_SOCKET_COLS):
			var sx := -0.255 + 0.085 * float(c)
			var sy := -0.20 - 0.13 * float(r)
			_add_box_visual(p_root, Vector3(sx, sy, 0.126), Vector3(0.058, 0.058, 0.012), sock_mat)
			var cover := _add_box_visual(p_root, Vector3(sx, sy, 0.134), Vector3(0.062, 0.062, 0.006), cover_mat)
			cover.visible = false
			_hall_c_socket_covers.append(cover)
			_hall_c_socket_pos.append(p_root.position + Vector3(sx, sy, 0.14))
	hall_c_breaker_port_pos = get_hall_c_socket_pos(0)

	_hall_c_breaker_label = _add_small_label(p_root, Vector3(0.0, 0.30, 0.102), tr("HALLE-C STROMBUS"), 28, 0.0016, Color(0.90, 0.91, 0.93))

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
	# Vorderkante der Buchsenleiste (Box bei z = 0.13, Tiefe 0.055)
	hall_c_router_port_pos = n_root.position + Vector3(0.0, -0.10, 0.158)

	var n_area := _make_interact_area(Vector3(0.84, 0.60, 0.42), {
		"interact_type": "net_port",
		"entity_id": GameState.HALL_C_ROUTER_ID,
	})
	n_area.position = Vector3(0.0, 0.0, 0.08)
	n_root.add_child(n_area)


## Sicherungskasten aus assets/models/breaker_box.glb an die Spiellogik anbinden:
## Status-LED, Lastbalken, Hauptschalter, Sicherungen F1–F4, Kastentür und Steckdosendeckel.
func _setup_breaker_model(model: Node3D, root: Node3D) -> void:
	_breaker_led_mat = _glb_bind_mat(model, "DCT_U_StatusLED")
	if _breaker_led_mat != null:
		_breaker_led_mat.emission_enabled = true

	var load_node := _glb_find(model, "_LoadBar")
	if load_node is MeshInstance3D:
		_breaker_load_bar = load_node as MeshInstance3D
		_breaker_load_base_sx = _breaker_load_bar.scale.x
		_breaker_load_mat = _glb_bind_mat(_breaker_load_bar, "DCT_U_LoadBar")
		if _breaker_load_mat != null:
			_breaker_load_mat.emission_enabled = true

	var lever := _glb_find(model, "_Pivot_MainLever")
	if lever != null:
		_breaker_lever_pivot = lever
		_breaker_lever_on_deg = _glb_extra(lever, "dct_on_deg_x", -28.0)
		_breaker_lever_off_deg = _glb_extra(lever, "dct_off_deg_x", 28.0)

	# Schraubsicherungen F1–F4 (so im Modell angelegt): jede Kappe bekommt eigene Materialkopien,
	# damit "durchgebrannt" pro Slot sichtbar ist
	_fuse_caps.clear()
	_fuse_cap_mats.clear()
	_fuse_ind_mats.clear()
	_fuse_visual_key = ""
	for i in range(4):
		var fx := -0.27 + 0.11 * float(i)
		var cap := _glb_find(model, "_FuseCap_F%d" % (i + 1))
		if cap != null:
			var cap_mat := _glb_bind_mat(cap, "DCT_U_FuseCap")
			if cap_mat == null:
				cap_mat = StandardMaterial3D.new()
			var ind_mat := _glb_bind_mat(cap, "DCT_U_FuseIndicator")
			if ind_mat == null:
				ind_mat = StandardMaterial3D.new()
			ind_mat.emission_enabled = true
			_fuse_caps.append(cap)
			_fuse_cap_mats.append(cap_mat)
			_fuse_ind_mats.append(ind_mat)
		var slot_area := _make_interact_area(Vector3(0.105, 0.12, 0.30), {
			"interact_type": "fuse_slot",
			"entity_id": "wall_breaker_fuse_%d" % i,
			"slot_idx": i,
		})
		slot_area.position = Vector3(fx, -0.14, 0.12)
		root.add_child(slot_area)

	# Glastür: Klickbereich über fast die ganze Türfläche, damit man nicht genau auf den Griff zielen muss.
	# Er hängt an der Tür und schwenkt beim Öffnen mit weg, Sicherungen und Hauptschalter bleiben dann frei.
	var door_h := _glb_find(model, "_Hinge_Door")
	if door_h != null:
		_register_panel(door_h, "breaker:door", tr("Kastentür"), "rotation:y",
			deg_to_rad(_glb_extra(door_h, "dct_open_deg", -110.0)), GameState.WALL_BREAKER_ID,
			Vector3(0.38, -0.08, 0.16), Vector3(0.80, 0.76, 0.46))

	# Nur die einzelne mittige Einspeisedose ist verbaut (keine äußeren Blindabdeckungen/Dosen mehr).
	_socket_lids.clear()
	_socket_lid_closed.clear()
	_socket_lid_open.clear()
	var mid_lid := _glb_find(model, "_Hinge_SocketLid_2")
	if mid_lid == null:
		mid_lid = _glb_find(model, "_Hinge_SocketLid_1")
	if mid_lid != null:
		_socket_lids.append(mid_lid)
		_socket_lid_closed.append(mid_lid.rotation.x)
		_socket_lid_open.append(mid_lid.rotation.x + deg_to_rad(_glb_extra(mid_lid, "dct_open_deg_x", -100.0)))

	_build_fuse_tray(root)


## Feuerlöscher aus assets/models/extinguisher_station.glb: beim Abnehmen verschwindet nur der Löscher,
## Halterung und Brandschutzzeichen bleiben an der Wand.
func _setup_extinguisher_model(model: Node3D) -> void:
	_extinguisher_mesh_root = _glb_find(model, "extinguisher_Body")
	if _extinguisher_mesh_root == null:
		push_warning("extinguisher_station.glb: Knoten extinguisher_Body fehlt")


## Router-Modell einer Stufe: LEDs an das gemeinsame Status-Material hängen, Schranktür und Seitenwände öffenbar machen.
func _setup_router_model(model: Node3D) -> void:
	_glb_bind_mat(model, "DCT_U_RouterLED", _router_led_mat)
	var door_h := _glb_find(model, "_Hinge_Door")
	if door_h != null:
		_register_panel(door_h, "router:door", tr("Schranktür"), "rotation:y",
			deg_to_rad(_glb_extra(door_h, "dct_open_deg", -110.0)), GameState.WALL_ROUTER_ID,
			Vector3(0.78, 0.0, 0.10), Vector3(0.10, 0.40, 0.26))
	for side in ["L", "R"]:
		var sp := _glb_find(model, "_Panel_Side_" + str(side))
		if sp == null:
			continue
		var closed_x := _glb_extra(sp, "dct_closed_x", sp.position.x)
		var slide := _glb_extra(sp, "dct_slide_x", signf(closed_x) * 0.25)
		var label := tr("Seitenwand links") if str(side) == "L" else tr("Seitenwand rechts")
		_register_panel(sp, "router:side_" + str(side), label, "position:x", slide, GameState.WALL_ROUTER_ID,
			Vector3(signf(closed_x) * 0.03, 0.0, 0.0), Vector3(0.12, 0.30, 0.30))
	# DSL-Router: Stummelantenne lässt sich mit [E] schwenken
	var ant := _glb_find(model, "_Pivot_Antenna")
	if ant != null:
		_register_panel(ant, "router:antenna", tr("Antenne"), "rotation:y",
			deg_to_rad(_glb_extra(ant, "dct_tilt_deg_y", 18.0)), GameState.WALL_ROUTER_ID,
			Vector3(0.0, 0.14, 0.0), Vector3(0.07, 0.26, 0.07))


func _register_panel(node: Node3D, panel_id: String, label: String, prop: String, open_offset: float,
		entity_id: String, handle_pos: Vector3, handle_size: Vector3) -> void:
	var closed := node.rotation.y if prop == "rotation:y" else node.position.x
	_panels[panel_id] = {
		"node": node,
		"prop": prop,
		"closed": closed,
		"open": closed + open_offset,
		"is_open": false,
		"tween": null,
		"label": label,
		"entity_id": entity_id,
	}
	var area := _make_interact_area(handle_size, {
		"interact_type": "rack_panel",
		"entity_id": entity_id,
		"panel_id": panel_id,
		"rack_prop": self,
	})
	area.position = handle_pos
	node.add_child(area)
	# Zustand vom Server übernehmen (nach Router-Upgrade oder für später beitretende Spieler)
	_set_panel_open(panel_id, GameState.is_shared_panel_open(entity_id, panel_id), false)


## Fragt beim Server an. Bewegt wird erst, wenn der Server den neuen Zustand an alle schickt.
func toggle_panel(panel_id: String) -> void:
	if not _panels.has(panel_id):
		return
	GameState.request_toggle_panel(str((_panels[panel_id] as Dictionary).get("entity_id", "")), panel_id)


func _on_panel_states_changed() -> void:
	for pid in _panels.keys():
		if not _panels.has(pid):
			continue
		var eid := str((_panels[pid] as Dictionary).get("entity_id", ""))
		_set_panel_open(str(pid), GameState.is_shared_panel_open(eid, str(pid)), true)


func _set_panel_open(panel_id: String, opening: bool, animate: bool) -> void:
	if not _panels.has(panel_id):
		return
	var p: Dictionary = _panels[panel_id]
	var node_v: Variant = p["node"]
	if not is_instance_valid(node_v):
		_panels.erase(panel_id)
		return
	if bool(p["is_open"]) == opening:
		return
	p["is_open"] = opening
	var old_tw: Variant = p.get("tween")
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	var prop := str(p["prop"])
	var target := float(p["open"] if opening else p["closed"])
	var node := node_v as Node3D
	if not animate or not node.is_inside_tree():
		node.set_indexed(NodePath(prop), target)
		p["tween"] = null
		return
	var tw := create_tween()
	tw.tween_property(node, prop, target, 0.55 if prop == "rotation:y" else 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	p["tween"] = tw
	SfxManager.play("click", -10.0, 0.85 if opening else 0.7)


## Eigener Prompt-Text für Garagen-Abdeckungen (die Antenne wird geschwenkt statt geöffnet).
func get_panel_prompt(panel_id: String) -> String:
	var label := get_panel_label(panel_id)
	if panel_id == "router:antenna":
		return tr("[E] %s schwenken") % label
	if is_panel_open(panel_id):
		return tr("[E] %s schließen") % label
	return tr("[E] %s öffnen") % label


func is_panel_open(panel_id: String) -> bool:
	if not _panels.has(panel_id):
		return false
	return bool((_panels[panel_id] as Dictionary).get("is_open", false))


func get_panel_label(panel_id: String) -> String:
	if not _panels.has(panel_id):
		return tr("Abdeckung")
	return str((_panels[panel_id] as Dictionary).get("label", tr("Abdeckung")))


func _glb_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		for c in out[i].get_children():
			out.append(c)
		i += 1
	return out


func _glb_find(root: Node, suffix: String) -> Node3D:
	for n in _glb_nodes(root):
		if n is Node3D and String(n.name).ends_with(suffix):
			return n as Node3D
	return null


## glTF-Extras kommen je nach Importweg als Meta "extras" (Dictionary) oder als einzelne Meta-Keys an.
func _glb_extra(n: Node, key: String, fallback: float) -> float:
	if n.has_meta("extras"):
		var ex: Variant = n.get_meta("extras")
		if ex is Dictionary and (ex as Dictionary).has(key):
			return float((ex as Dictionary)[key])
	if n.has_meta(key):
		return float(n.get_meta(key))
	return fallback


## Ersetzt alle Oberflächen mit dem glTF-Material `mat_name` unter `root` durch `shared` oder,
## ohne `shared`, durch eine eigene Kopie des Originals, damit die Spiellogik Farbe und Leuchten steuern kann.
func _glb_bind_mat(root: Node, mat_name: String, shared: StandardMaterial3D = null) -> StandardMaterial3D:
	var bound: StandardMaterial3D = shared
	for n in _glb_nodes(root):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src == null or src.resource_name != mat_name:
				continue
			if bound == null:
				bound = (src.duplicate() as StandardMaterial3D) if src is StandardMaterial3D else StandardMaterial3D.new()
			mi.set_surface_override_material(s, bound)
	return bound


## Ablage rechts neben dem Sicherungskasten: zeigt bis zu 6 Ersatzsicherungen aus dem Lager (fuse_d02_ok.glb)
## und die zuletzt ausgebauten, durchgebrannten Sicherungen (fuse_d02_blown.glb).
func _build_fuse_tray(root: Node3D) -> void:
	_fuse_tray_stock = null
	_fuse_tray_scrap = null
	_fuse_ok_tpl = null
	_fuse_blown_tpl = null
	_fuse_prev_states.clear()
	var ok_tpl := ModelLoader.instantiate_custom_model("fuse_d02_ok")
	if ok_tpl == null:
		return
	var tray := Node3D.new()
	tray.name = "FuseTray"
	tray.position = FUSE_TRAY_POS
	root.add_child(tray)

	var steel := MatLib.get_mat("galvanized_steel")
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(0.22, FUSE_TRAY_TOP * 2.0, 0.09)
	shelf.mesh = shelf_mesh
	shelf.material_override = steel
	tray.add_child(shelf)
	var lip := MeshInstance3D.new()
	var lip_mesh := BoxMesh.new()
	lip_mesh.size = Vector3(0.22, 0.02, 0.004)
	lip.mesh = lip_mesh
	lip.material_override = steel
	lip.position = Vector3(0.0, 0.01, 0.043)
	tray.add_child(lip)

	# Vorlagen bleiben unsichtbar im Baum und werden pro Sicherung dupliziert
	var templates := Node3D.new()
	templates.name = "Templates"
	templates.visible = false
	tray.add_child(templates)
	templates.add_child(ok_tpl)
	_fuse_ok_tpl = ok_tpl
	var blown_tpl := ModelLoader.instantiate_custom_model("fuse_d02_blown")
	if blown_tpl != null:
		templates.add_child(blown_tpl)
		_fuse_blown_tpl = blown_tpl

	_fuse_tray_stock = Node3D.new()
	_fuse_tray_stock.name = "Stock"
	tray.add_child(_fuse_tray_stock)
	_fuse_tray_scrap = Node3D.new()
	_fuse_tray_scrap.name = "Scrap"
	tray.add_child(_fuse_tray_scrap)


func _update_fuse_tray(fuses: Array) -> void:
	if _fuse_tray_stock == null or _fuse_ok_tpl == null:
		return
	# Wechselt ein Steckplatz von "blown" auf "ok", liegt die ausgebaute Sicherung danach auf der Ablage
	if _fuse_prev_states.size() == fuses.size():
		for i in range(fuses.size()):
			if str(_fuse_prev_states[i]) == "blown" and str(fuses[i]) == "ok":
				_add_scrap_fuse()
	_fuse_prev_states = fuses.duplicate()

	for c in _fuse_tray_stock.get_children():
		_fuse_tray_stock.remove_child(c)
		c.queue_free()
	var want := mini(maxi(GameState.fuse_stock, 0), FUSE_TRAY_STOCK_MAX)
	for i in range(want):
		var f := _fuse_ok_tpl.duplicate() as Node3D
		f.position = Vector3(-0.085 + 0.032 * float(i % 3), FUSE_TRAY_TOP + 0.024,
			-0.018 + 0.036 * floorf(float(i) / 3.0))
		_fuse_tray_stock.add_child(f)


func _add_scrap_fuse() -> void:
	if _fuse_tray_scrap == null or _fuse_blown_tpl == null:
		return
	var kids := _fuse_tray_scrap.get_children()
	if kids.size() >= FUSE_TRAY_SCRAP_MAX:
		var oldest := kids[0]
		_fuse_tray_scrap.remove_child(oldest)
		oldest.queue_free()
	_fuse_tray_scrap.add_child(_fuse_blown_tpl.duplicate() as Node3D)
	var i := 0
	for c in _fuse_tray_scrap.get_children():
		var n3 := c as Node3D
		# liegend, damit man sie von den Ersatzsicherungen unterscheidet
		n3.position = Vector3(0.07, FUSE_TRAY_TOP + 0.012, -0.025 + 0.025 * float(i))
		n3.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		i += 1


func _build_extinguisher_station() -> void:
	var root := Node3D.new()
	root.position = Vector3(-2.8, 1.22, -4.36)
	add_child(root)

	# Blender-Modell (assets/models/extinguisher_station.glb) ersetzt das prozedurale Modell, falls vorhanden.
	var ext_model := ModelLoader.instantiate_custom_model("extinguisher_station")
	if ext_model != null:
		root.add_child(ext_model)
		_setup_extinguisher_model(ext_model)
	else:
		var red_paint := _mat(Color(0.80, 0.06, 0.05), 0.22, 0.25)
		var sign_red := _mat(Color(0.78, 0.08, 0.07), 0.55, 0.0)
		var white := _mat(Color(0.95, 0.95, 0.93), 0.55, 0.0)
		var black_rubber := _mat(Color(0.07, 0.07, 0.08), 0.75, 0.0)
		var black_plastic := _mat(Color(0.10, 0.10, 0.11), 0.42, 0.0)
		var chrome := MatLib.make_brushed_metal(Color(0.82, 0.83, 0.85), 0.16, 0.95)
		var steel := MatLib.get_mat("galvanized_steel")
		var seal_yellow := _mat(Color(0.95, 0.80, 0.10), 0.5, 0.0)
		var gauge_green := _mat(Color(0.16, 0.66, 0.30), 0.5, 0.0)
		var sticker_green := _mat(Color(0.20, 0.58, 0.30), 0.6, 0.0)

		# Brandschutzzeichen über der Halterung: weißer Rand, rotes Feld, vereinfachtes Piktogramm
		_add_box_visual(root, Vector3(0.0, 0.47, -0.068), Vector3(0.20, 0.20, 0.006), white)
		_add_box_visual(root, Vector3(0.0, 0.47, -0.064), Vector3(0.184, 0.184, 0.006), sign_red)
		_add_box_visual(root, Vector3(-0.025, 0.45, -0.0605), Vector3(0.036, 0.08, 0.002), white)
		_add_box_visual(root, Vector3(-0.025, 0.50, -0.0605), Vector3(0.016, 0.02, 0.002), white)
		var pic_hose := _add_box_visual(root, Vector3(0.003, 0.48, -0.0605), Vector3(0.006, 0.05, 0.002), white)
		pic_hose.rotation_degrees.z = -35.0
		for i in range(3):
			var flame := _add_box_visual(root, Vector3(0.03 + 0.02 * float(i), 0.42 + 0.014 * float(i % 2), -0.0605), Vector3(0.017, 0.017, 0.002), white)
			flame.rotation_degrees.z = 45.0

		# Wandhalterung mit Spannband. Sie bleibt hängen, wenn ein Spieler den Löscher nimmt.
		_add_box_visual(root, Vector3(0.0, 0.02, -0.066), Vector3(0.07, 0.22, 0.008), steel)
		_add_box_visual(root, Vector3(0.0, 0.05, -0.03), Vector3(0.03, 0.025, 0.064), steel)
		_add_torus_visual(root, Vector3(0.0, 0.05, 0.09), 0.086, 0.095, steel)

		_extinguisher_mesh_root = Node3D.new()
		root.add_child(_extinguisher_mesh_root)
		var e := _extinguisher_mesh_root
		var cz := 0.09

		# 6-kg-Pulverlöscher: Behälter mit gewölbter Schulter und Kunststofffuß
		_add_cyl_visual(e, Vector3(0.0, -0.03, cz), 0.085, 0.085, 0.40, red_paint, Vector3.ZERO, 32)
		_add_sphere_visual(e, Vector3(0.0, 0.17, cz), 0.085, 0.11, red_paint)
		_add_cyl_visual(e, Vector3(0.0, -0.225, cz), 0.087, 0.087, 0.03, black_plastic, Vector3.ZERO, 32)
		_add_cyl_visual(e, Vector3(0.0, -0.245, cz), 0.080, 0.084, 0.012, black_plastic, Vector3.ZERO, 32)

		# Etikett und Prüfplakette
		_add_cyl_visual(e, Vector3(0.0, -0.05, cz), 0.0865, 0.0865, 0.15, white, Vector3.ZERO, 32)
		_add_small_label(e, Vector3(0.0, -0.035, cz + 0.0875), "ABC-PULVER\n6 kg", 28, 0.0009, Color(0.10, 0.10, 0.12))
		_add_cyl_visual(e, Vector3(0.0, -0.165, cz + 0.0855), 0.016, 0.016, 0.002, sticker_green, Vector3(90, 0, 0), 16)

		# Armatur: Hals, Ventilkopf, Manometer, Schlaghebel, Tragegriff, Sicherungsstift mit Plombe
		_add_cyl_visual(e, Vector3(0.0, 0.235, cz), 0.024, 0.024, 0.05, chrome, Vector3.ZERO, 20)
		_add_cyl_visual(e, Vector3(0.0, 0.275, cz), 0.030, 0.030, 0.045, chrome, Vector3.ZERO, 20)
		_add_cyl_visual(e, Vector3(0.0, 0.282, cz + 0.036), 0.022, 0.022, 0.016, chrome, Vector3(90, 0, 0), 20)
		_add_cyl_visual(e, Vector3(0.0, 0.282, cz + 0.0445), 0.018, 0.018, 0.002, white, Vector3(90, 0, 0), 20)
		_add_box_visual(e, Vector3(0.0, 0.292, cz + 0.0458), Vector3(0.016, 0.004, 0.001), gauge_green)
		var needle := _add_box_visual(e, Vector3(0.003, 0.284, cz + 0.0462), Vector3(0.002, 0.014, 0.001), black_plastic)
		needle.rotation_degrees.z = -35.0
		var lever := _add_box_visual(e, Vector3(-0.045, 0.316, cz), Vector3(0.17, 0.016, 0.034), black_plastic)
		lever.rotation_degrees.z = -10.0
		var carry := _add_box_visual(e, Vector3(-0.04, 0.293, cz), Vector3(0.15, 0.016, 0.034), black_plastic)
		carry.rotation_degrees.z = 3.0
		_add_torus_visual(e, Vector3(0.032, 0.30, cz + 0.025), 0.007, 0.012, chrome, Vector3(90, 0, 0))
		_add_box_visual(e, Vector3(0.032, 0.287, cz + 0.027), Vector3(0.008, 0.012, 0.004), seal_yellow)

		# Schlauch vom Ventil seitlich nach unten, Löschpistole in der Klammer
		_add_cyl_visual(e, Vector3(0.03, 0.265, cz), 0.014, 0.014, 0.02, chrome, Vector3(0, 0, 90), 12)
		_add_hose_visual(e, PackedVector3Array([
			Vector3(0.035, 0.265, cz),
			Vector3(0.075, 0.255, cz + 0.02),
			Vector3(0.11, 0.215, cz + 0.03),
			Vector3(0.115, -0.08, cz + 0.03),
		]), 0.011, black_rubber)
		_add_cyl_visual(e, Vector3(0.115, -0.075, cz + 0.03), 0.0135, 0.0135, 0.02, chrome, Vector3.ZERO, 12)
		_add_cyl_visual(e, Vector3(0.115, -0.135, cz + 0.03), 0.013, 0.026, 0.11, black_plastic, Vector3.ZERO, 16)
		_add_box_visual(e, Vector3(0.098, 0.04, cz + 0.022), Vector3(0.03, 0.018, 0.03), steel)

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

	var conduit_model := ModelLoader.instantiate_custom_model("router_conduit")
	if conduit_model != null:
		_router_root.add_child(conduit_model)
	else:
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
	router_visuals_rebuilt.emit()
	for c in _router_mesh_holder.get_children():
		c.queue_free()

	for pid in _panels.keys():
		if str(pid).begins_with("router:"):
			_panels.erase(pid)

	# Kabelende auf eine echte RJ45-Buchse der aktuellen Stufe legen (Werte aus den Router-GLBs:
	# Mitte des blauen Buchsenrahmens, z = Vorderkante der Buchsenöffnung).
	const ROUTER_JACK_OFFSETS: Array[Vector3] = [
		Vector3(-0.04, -0.08, 0.075),
		Vector3(0.0, -0.062, 0.121),
		Vector3(-0.27, -0.06, 0.141),
		Vector3(-0.26, -0.095, 0.167),
		Vector3(-0.26, -0.095, 0.167),
	]
	router_port_pos = _router_root.position + ROUTER_JACK_OFFSETS[clampi(tier, 0, ROUTER_JACK_OFFSETS.size() - 1)]

	# Einzelne LAN-Buchsen je Stufe (Anzahl, erste Buchse und Abstand wie in den Router-Modellen)
	const ROUTER_JACK_COUNTS: Array[int] = [2, 3, 5, 6, 6]
	const ROUTER_JACK_FIRST_X: Array[float] = [-0.12, -0.14, -0.27, -0.26, -0.26]
	const ROUTER_JACK_PITCH: Array[float] = [0.08, 0.14, 0.09, 0.104, 0.104]
	var jt := clampi(tier, 0, ROUTER_JACK_COUNTS.size() - 1)
	_router_jack_pos.clear()
	for j in range(ROUTER_JACK_COUNTS[jt]):
		_router_jack_pos.append(_router_root.position + Vector3(
			ROUTER_JACK_FIRST_X[jt] + ROUTER_JACK_PITCH[jt] * float(j),
			ROUTER_JACK_OFFSETS[jt].y,
			ROUTER_JACK_OFFSETS[jt].z))

	var h := _router_mesh_holder
	var model_ids: Array[String] = ["router_t0_dsl", "router_t1_vdsl", "router_t2_gateway", "router_t3_core10g", "router_t4_core100g"]
	var r_model := ModelLoader.instantiate_custom_model(model_ids[clampi(tier, 0, model_ids.size() - 1)])
	if r_model != null:
		h.add_child(r_model)
		_setup_router_model(r_model)
	elif tier == 0:
		_build_router_tier_dsl(h)
	elif tier == 1:
		_build_router_tier_vdsl(h)
	elif tier == 2:
		_build_router_tier_gateway(h)
	else:
		_build_router_tier_cabinet(h, tier >= 4)


## Stufe 0: vergilbter Heim-DSL-Router aus Kunststoff mit Stummelantenne, LED-Reihe und 2 LAN-Buchsen.
func _build_router_tier_dsl(h: Node3D) -> void:
	var plastic := _mat(Color(0.84, 0.81, 0.73), 0.62, 0.0)
	var plastic_dark := _mat(Color(0.74, 0.71, 0.63), 0.66, 0.0)
	var bezel := _mat(Color(0.42, 0.41, 0.39), 0.40, 0.0)
	var slot := _mat(Color(0.12, 0.12, 0.12), 0.80, 0.0)
	var rubber := _mat(Color(0.09, 0.09, 0.10), 0.70, 0.0)
	var sticker := _mat(Color(0.93, 0.92, 0.84), 0.85, 0.0)
	var galv := MatLib.get_mat("galvanized_steel")
	var port_blue := _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22)
	var jack := _mat(Color(0.04, 0.04, 0.05), 0.75, 0.0)
	var contact := _mat(Color(0.86, 0.68, 0.26), 0.30, 0.90)

	_add_box_visual(h, Vector3(0.0, -0.02, -0.105), Vector3(0.30, 0.12, 0.01), galv)
	_add_box_visual(h, Vector3(0.0, -0.04, -0.02), Vector3(0.44, 0.20, 0.16), plastic)
	_add_box_visual(h, Vector3(0.0, 0.075, -0.025), Vector3(0.42, 0.03, 0.15), plastic_dark)
	_add_box_visual(h, Vector3(0.0, 0.094, -0.025), Vector3(0.40, 0.008, 0.14), plastic)
	_add_box_visual(h, Vector3(0.0, -0.04, 0.066), Vector3(0.40, 0.16, 0.012), bezel)

	for i in range(4):
		_add_cyl_visual(h, Vector3(-0.16 + 0.04 * float(i), 0.01, 0.073), 0.006, 0.006, 0.004, _router_led_mat, Vector3(90, 0, 0), 12)
	_add_small_label(h, Vector3(0.10, 0.03, 0.0725), "SpeedPort 50", 22, 0.0012, Color(0.80, 0.80, 0.76))
	for i in range(4):
		_add_box_visual(h, Vector3(0.11, -0.01 - 0.022 * float(i), 0.0725), Vector3(0.10, 0.006, 0.002), slot)
	_add_box_visual(h, Vector3(0.13, -0.11, 0.0725), Vector3(0.07, 0.03, 0.002), sticker)
	for p_i in range(2):
		_add_rj45_port(h, Vector3(-0.12 + 0.08 * float(p_i), -0.08, 0.074), port_blue, jack, contact)

	var ant := Node3D.new()
	ant.position = Vector3(0.15, 0.10, -0.04)
	ant.rotation_degrees.z = -18.0
	h.add_child(ant)
	_add_sphere_visual(ant, Vector3.ZERO, 0.017, 0.034, rubber)
	_add_cyl_visual(ant, Vector3(0.0, 0.13, 0.0), 0.007, 0.011, 0.24, rubber, Vector3.ZERO, 12)
	_add_cyl_visual(ant, Vector3(0.0, 0.045, 0.0), 0.0125, 0.0125, 0.012, bezel, Vector3.ZERO, 12)
	_add_cyl_visual(ant, Vector3(0.0, 0.10, 0.0), 0.0105, 0.0105, 0.010, bezel, Vector3.ZERO, 12)
	_add_sphere_visual(ant, Vector3(0.0, 0.25, 0.0), 0.008, 0.016, rubber)


## Stufe 1: mattschwarzer VDSL-Business-Router mit Hochglanzfront, Lüftungsgitter, 2 MIMO-Antennen und 3 Ports.
func _build_router_tier_vdsl(h: Node3D) -> void:
	var body := MatLib.make_brushed_metal(Color(0.12, 0.13, 0.15), 0.45, 0.35)
	var gloss := _mat(Color(0.05, 0.05, 0.06), 0.12, 0.10)
	var silver := MatLib.make_brushed_metal(Color(0.72, 0.74, 0.77), 0.25, 0.90)
	var perf := MatLib.get_mat("perforated_mesh")
	var galv := MatLib.get_mat("galvanized_steel")
	var rubber := _mat(Color(0.08, 0.08, 0.09), 0.60, 0.0)
	var port_blue := _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22)
	var jack := _mat(Color(0.04, 0.04, 0.05), 0.75, 0.0)
	var contact := _mat(Color(0.86, 0.68, 0.26), 0.30, 0.90)

	_add_box_visual(h, Vector3(0.0, 0.0, -0.115), Vector3(0.40, 0.16, 0.01), galv)
	_add_box_visual(h, Vector3.ZERO, Vector3(0.58, 0.30, 0.20), body)
	_add_box_visual(h, Vector3(0.0, 0.158, -0.005), Vector3(0.56, 0.016, 0.19), body)
	_add_box_visual(h, Vector3(0.0, 0.1675, -0.01), Vector3(0.40, 0.003, 0.12), perf)
	_add_box_visual(h, Vector3(0.0, -0.01, 0.106), Vector3(0.54, 0.24, 0.012), gloss)
	_add_box_visual(h, Vector3(0.0, 0.09, 0.1135), Vector3(0.54, 0.006, 0.003), silver)
	for i in range(5):
		_add_box_visual(h, Vector3(-0.23 + 0.035 * float(i), 0.06, 0.1135), Vector3(0.018, 0.006, 0.003), _router_led_mat)
	_add_small_label(h, Vector3(0.13, 0.06, 0.1125), "VDSL 250  BUSINESS", 22, 0.0012, Color(0.75, 0.77, 0.80))
	for p_i in range(3):
		_add_rj45_port(h, Vector3(-0.14 + 0.14 * float(p_i), -0.06, 0.12), port_blue, jack, contact)
	_add_cyl_visual(h, Vector3(0.235, -0.06, 0.117), 0.012, 0.012, 0.010, rubber, Vector3(90, 0, 0), 16)

	for side in range(2):
		var sx := -0.22 if side == 0 else 0.22
		_add_cyl_visual(h, Vector3(sx, 0.168, -0.06), 0.018, 0.018, 0.034, rubber, Vector3(0, 0, 90), 16)
		var ant := Node3D.new()
		ant.position = Vector3(sx, 0.168, -0.06)
		ant.rotation_degrees.z = 10.0 if side == 0 else -10.0
		h.add_child(ant)
		_add_box_visual(ant, Vector3(0.0, 0.13, 0.0), Vector3(0.034, 0.21, 0.014), rubber)
		_add_cyl_visual(ant, Vector3(0.0, 0.235, 0.0), 0.017, 0.017, 0.014, rubber, Vector3(90, 0, 0), 16)
		_add_cyl_visual(ant, Vector3(0.0, 0.025, 0.0), 0.017, 0.017, 0.014, rubber, Vector3(90, 0, 0), 16)


## Stufe 2: 1G-Glasfaser-Gateway mit Rack-Winkeln, SFP-Käfigen samt LC-Stecker,
## Status-Display, Konsolenport und 5 LAN-Ports. Die Faser läuft nach oben ins Leerrohr.
func _build_router_tier_gateway(h: Node3D) -> void:
	var body := MatLib.make_brushed_metal(Color(0.16, 0.18, 0.21), 0.40, 0.55)
	var face := _mat(Color(0.09, 0.10, 0.12), 0.50, 0.30)
	var galv := MatLib.get_mat("galvanized_steel")
	var perf := MatLib.get_mat("perforated_mesh")
	var jack := _mat(Color(0.04, 0.04, 0.05), 0.75, 0.0)
	var contact := _mat(Color(0.86, 0.68, 0.26), 0.30, 0.90)
	var port_blue := _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22)
	var console_blue := _mat(Color(0.48, 0.72, 0.90), 0.45, 0.10)
	var screen := _mat(Color(0.03, 0.05, 0.07), 0.15, 0.0)
	var fiber := _mat(Color(0.95, 0.78, 0.10), 0.45, 0.0)
	var lc_blue := _mat(Color(0.20, 0.45, 0.85), 0.40, 0.0)
	var screw := MatLib.make_brushed_metal(Color(0.72, 0.74, 0.76), 0.30, 0.90)

	_add_box_visual(h, Vector3.ZERO, Vector3(0.74, 0.36, 0.24), body)
	_add_box_visual(h, Vector3(0.0, 0.0, 0.1225), Vector3(0.66, 0.30, 0.005), face)
	for side in range(2):
		var sx := -0.385 if side == 0 else 0.385
		_add_box_visual(h, Vector3(sx, 0.0, 0.11), Vector3(0.03, 0.36, 0.03), galv)
		for k in range(2):
			_add_cyl_visual(h, Vector3(sx, -0.12 + 0.24 * float(k), 0.1265), 0.008, 0.008, 0.004, screw, Vector3(90, 0, 0), 12)

	# Obere Reihe: Statusdisplay, 2 SFP-Käfige (einer mit LC-Stecker), Status-LEDs
	_add_box_visual(h, Vector3(-0.23, 0.08, 0.127), Vector3(0.14, 0.07, 0.004), screen)
	_add_small_label(h, Vector3(-0.23, 0.08, 0.1295), "1G FIBER\nUPLINK OK", 20, 0.0010, Color(0.35, 0.85, 0.95))
	for i in range(2):
		var cx := -0.07 + 0.10 * float(i)
		_add_box_visual(h, Vector3(cx, 0.08, 0.134), Vector3(0.075, 0.045, 0.022), galv)
		_add_box_visual(h, Vector3(cx, 0.08, 0.1455), Vector3(0.06, 0.03, 0.002), jack)
	_add_box_visual(h, Vector3(-0.07, 0.08, 0.152), Vector3(0.03, 0.022, 0.016), lc_blue)
	_add_hose_visual(h, PackedVector3Array([
		Vector3(-0.07, 0.08, 0.16),
		Vector3(-0.06, 0.15, 0.18),
		Vector3(-0.03, 0.205, 0.13),
		Vector3(0.0, 0.215, -0.02),
	]), 0.005, fiber)
	for i in range(4):
		_add_cyl_visual(h, Vector3(0.15 + 0.04 * float(i), 0.10, 0.127), 0.006, 0.006, 0.004, _router_led_mat, Vector3(90, 0, 0), 12)
	_add_small_label(h, Vector3(0.21, 0.055, 0.1255), "GLASFASER-GATEWAY 1G", 20, 0.0010, Color(0.75, 0.77, 0.80))

	# Untere Reihe: 5 LAN-Ports, Konsolenport, Lüftungsschlitz
	for p_i in range(5):
		_add_rj45_port(h, Vector3(-0.27 + 0.09 * float(p_i), -0.06, 0.14), port_blue, jack, contact)
	_add_rj45_port(h, Vector3(0.23, -0.06, 0.14), console_blue, jack, contact)
	_add_box_visual(h, Vector3(0.0, -0.135, 0.126), Vector3(0.66, 0.025, 0.003), perf)


## Stufe 3 und 4: Wand-Netzwerkschrank mit 19"-Profilschienen, Patchpanel samt Glasfaser-Jumpern,
## Kabelführung und Switch. Stufe 4 bekommt zusätzlich eine 100G-Einschubkarte mit belegten SFP-Ports.
func _build_router_tier_cabinet(h: Node3D, is_100g: bool) -> void:
	var dark_metal := MatLib.make_brushed_metal(Color(0.16, 0.18, 0.21), 0.40, 0.55)
	var inner := _mat(Color(0.06, 0.07, 0.08), 0.70, 0.20)
	var face := _mat(Color(0.10, 0.11, 0.13), 0.45, 0.35)
	var galv := MatLib.get_mat("galvanized_steel")
	var perf := MatLib.get_mat("perforated_mesh")
	var hole := _mat(Color(0.03, 0.03, 0.03), 0.90, 0.0)
	var label_paper := _mat(Color(0.96, 0.95, 0.88), 0.85, 0.0)
	var port_blue := _mat(Color(0.20, 0.44, 0.72), 0.45, 0.22)
	var jack := _mat(Color(0.04, 0.04, 0.05), 0.75, 0.0)
	var contact := _mat(Color(0.86, 0.68, 0.26), 0.30, 0.90)
	var fiber := _mat(Color(0.95, 0.78, 0.10), 0.45, 0.0)
	var lc_blue := _mat(Color(0.20, 0.45, 0.85), 0.40, 0.0)
	var screw := MatLib.make_brushed_metal(Color(0.72, 0.74, 0.76), 0.30, 0.90)
	var cab_h := 0.72 if is_100g else 0.56
	var cy := 0.06
	var top := cy + cab_h * 0.5
	var bottom := cy - cab_h * 0.5

	# Korpus mit dunklem Innenraum und Lüftungsgitter im Deckel
	_add_box_visual(h, Vector3(0.0, cy, -0.14), Vector3(0.84, cab_h, 0.02), dark_metal)
	_add_box_visual(h, Vector3(-0.41, cy, 0.0), Vector3(0.02, cab_h, 0.30), dark_metal)
	_add_box_visual(h, Vector3(0.41, cy, 0.0), Vector3(0.02, cab_h, 0.30), dark_metal)
	_add_box_visual(h, Vector3(0.0, top - 0.01, 0.0), Vector3(0.84, 0.02, 0.30), dark_metal)
	_add_box_visual(h, Vector3(0.0, bottom + 0.01, 0.0), Vector3(0.84, 0.02, 0.30), dark_metal)
	_add_box_visual(h, Vector3(0.0, cy, -0.128), Vector3(0.80, cab_h - 0.04, 0.004), inner)
	_add_box_visual(h, Vector3(0.0, top + 0.002, -0.02), Vector3(0.50, 0.004, 0.18), perf)

	# 19"-Profilschienen mit Rasterlöchern
	var hole_count := int((cab_h - 0.08) / 0.0445)
	for side in range(2):
		var rx := -0.375 if side == 0 else 0.375
		_add_box_visual(h, Vector3(rx, cy, 0.14), Vector3(0.035, cab_h - 0.04, 0.02), galv)
		for k in range(hole_count):
			_add_box_visual(h, Vector3(rx, bottom + 0.06 + 0.0445 * float(k), 0.1505), Vector3(0.009, 0.009, 0.002), hole)

	# Typenschild oben, bei Stufe 4 mit zusätzlicher Lüftungsblende
	_add_box_visual(h, Vector3(0.0, 0.285, 0.148), Vector3(0.72, 0.06, 0.006), face)
	_add_small_label(h, Vector3(0.0, 0.285, 0.1515), "CORE 100G" if is_100g else "CORE 10G", 26, 0.0016, Color(0.80, 0.82, 0.85))
	if is_100g:
		_add_box_visual(h, Vector3(0.0, 0.36, 0.150), Vector3(0.72, 0.06, 0.004), perf)

	# Patchpanel mit 12 Keystone-Buchsen, Beschriftungsstreifen und 2 gelben Glasfaser-Jumpern
	_add_box_visual(h, Vector3(0.0, 0.20, 0.155), Vector3(0.72, 0.08, 0.01), galv)
	for i in range(12):
		_add_box_visual(h, Vector3(-0.275 + 0.05 * float(i), 0.195, 0.1605), Vector3(0.03, 0.026, 0.002), hole)
	_add_box_visual(h, Vector3(0.0, 0.228, 0.1605), Vector3(0.60, 0.010, 0.002), label_paper)
	for side in range(2):
		_add_cyl_visual(h, Vector3(-0.345 if side == 0 else 0.345, 0.20, 0.1615), 0.007, 0.007, 0.004, screw, Vector3(90, 0, 0), 12)
	for i in range(2):
		var px := -0.275 + 0.05 * float(i)
		_add_box_visual(h, Vector3(px, 0.195, 0.168), Vector3(0.02, 0.022, 0.014), lc_blue)
		_add_hose_visual(h, PackedVector3Array([
			Vector3(px, 0.195, 0.175),
			Vector3(px - 0.01, 0.15, 0.19),
			Vector3(-0.33 - 0.008 * float(i), 0.09, 0.185),
			Vector3(-0.335 - 0.008 * float(i), 0.03, 0.17),
		]), 0.0045, fiber)

	# Kabelführung mit Bürstenleiste und Führungsbügeln
	_add_box_visual(h, Vector3(0.0, 0.05, 0.150), Vector3(0.72, 0.07, 0.006), face)
	_add_box_visual(h, Vector3(0.0, 0.05, 0.1535), Vector3(0.66, 0.015, 0.001), hole)
	for i in range(6):
		_add_box_visual(h, Vector3(-0.25 + 0.10 * float(i), 0.05, 0.162), Vector3(0.012, 0.06, 0.018), galv)

	# Switch mit 6 Ports und Port-LEDs (Port-Höhe wie beim alten Modell)
	_add_box_visual(h, Vector3(0.0, -0.09, 0.152), Vector3(0.72, 0.08, 0.012), face)
	for p_i in range(6):
		var sx := -0.26 + 0.104 * float(p_i)
		_add_rj45_port(h, Vector3(sx, -0.095, 0.166), port_blue, jack, contact)
		_add_box_visual(h, Vector3(sx, -0.058, 0.1585), Vector3(0.012, 0.005, 0.002), _router_led_mat)

	if is_100g:
		# 100G-Einschub mit 8 SFP-Käfigen, 3 davon mit Glasfaser belegt
		_add_box_visual(h, Vector3(0.0, -0.21, 0.152), Vector3(0.72, 0.08, 0.012), face)
		for i in range(8):
			var qx := -0.28 + 0.08 * float(i)
			_add_box_visual(h, Vector3(qx, -0.215, 0.163), Vector3(0.06, 0.036, 0.012), galv)
			_add_box_visual(h, Vector3(qx, -0.215, 0.1695), Vector3(0.046, 0.024, 0.002), hole)
			_add_box_visual(h, Vector3(qx, -0.183, 0.1585), Vector3(0.010, 0.005, 0.002), _router_led_mat)
			if i < 3:
				_add_box_visual(h, Vector3(qx, -0.215, 0.177), Vector3(0.024, 0.02, 0.016), lc_blue)
				_add_hose_visual(h, PackedVector3Array([
					Vector3(qx, -0.215, 0.185),
					Vector3(qx + 0.01, -0.25, 0.20),
					Vector3(qx + 0.03, -0.32, 0.19),
				]), 0.0045, fiber)
		_add_box_visual(h, Vector3(0.0, -0.272, 0.150), Vector3(0.72, 0.03, 0.004), perf)
	else:
		_add_box_visual(h, Vector3(0.0, -0.175, 0.150), Vector3(0.72, 0.07, 0.004), perf)


func _build_terminal_desk() -> void:
	var root := Node3D.new()
	root.position = Vector3(3.0, 0.0, -3.72)
	add_child(root)

	# Blender-Modell (assets/models/terminal_desk.glb) ersetzt die prozeduralen Tischteile, falls vorhanden.
	var desk_model := ModelLoader.instantiate_custom_model("terminal_desk")
	if desk_model != null:
		root.add_child(desk_model)
		# Die Bildschirmfläche aus dem Modell fliegt raus, weil unten der Live-Spiegel eine eigene Fläche setzt.
		var model_screen := desk_model.find_child("PcScreenQuad", true, false)
		if model_screen != null:
			model_screen.queue_free()
		_add_desk_collider(root)
	else:
		_build_desk_procedural(root)

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

	_desk_glow_light = OmniLight3D.new()
	_desk_glow_light.position = Vector3(-0.18, 1.28, 0.26)
	_desk_glow_light.light_color = Color(0.96, 0.96, 0.94)
	_desk_glow_light.light_energy = 0.28
	_desk_glow_light.omni_range = 2.6
	_desk_glow_light.shadow_enabled = false
	root.add_child(_desk_glow_light)

	if desk_model == null:
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

	if desk_model == null:
		# Realistic Ergonomic 5-Caster Swivel Office Chair!
		var chair := BuildingPropFactory.build_office_chair()
		chair.position = Vector3(-0.22, 0.0, 0.86)
		chair.rotation_degrees.y = -18.0
		root.add_child(chair)

	# Das Schild über dem PC wurde entfernt; der Hinweis kommt beim Anschauen über den Interaktions-Prompt.
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
	# Das Whiteboard mit der statischen Betriebs-Checkliste wurde entfernt.
	# Die Aufgaben zeigt jetzt die Live-Checkliste im HUD.


func _build_workshop_props() -> void:
	# 1. Funktionales 3D-Schwerlast-Lagerregal (2K PBR aus Blender, 12 freie Stellplaetze mit 3D-Etiketten!)
	var shelf := StorageShelfProp.new()
	shelf.position = Vector3(-5.12, 0.0, -2.2)
	shelf.rotation_degrees.y = 90.0
	add_child(shelf)
	shelf.setup("shelf_0")
	# Kollisionswand nur im hinteren Regalrahmen, damit die 12 vorderen Fach-Hitboxen (Layer 4) niemals blockiert werden!
	_add_invisible_wall(Vector3(-5.30, 1.08, -2.2), Vector3(0.24, 2.16, 1.56))

	# 2. Funktionale industrielle 3D-IT-Werkbank (2K PBR aus Blender, fuer Zusammenbau & Reparatur!)
	var bench := WorkbenchProp.new()
	bench.position = Vector3(-4.95, 0.0, 2.25)
	bench.rotation_degrees.y = 90.0
	add_child(bench)
	bench.setup("wb_main")
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


## Statische Wand mit Occluder, damit Hallen hinter der Außenwand nicht verarbeitet werden.
func _add_box_static_occluded(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := _add_box_static(parent, pos, size, mat)
	var occ := OccluderInstance3D.new()
	var box_occ := BoxOccluder3D.new()
	box_occ.size = size
	occ.occluder = box_occ
	body.add_child(occ)
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


## Zylinder oder Kegelstumpf als reines Sichtteil. `rot_deg` dreht ihn, z. B. Vector3(90, 0, 0) für eine Scheibe zur Front.
func _add_cyl_visual(parent: Node3D, pos: Vector3, top_r: float, bottom_r: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO, segments: int = 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 0
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Kugel oder Ellipsoid (height < 2 × radius staucht sie) als reines Sichtteil.
func _add_sphere_visual(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.radial_segments = 24
	sm.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Ring (Spannband, Sicherungsstift). Ohne Drehung liegt er waagerecht um die Y-Achse.
func _add_torus_visual(parent: Node3D, pos: Vector3, inner_r: float, outer_r: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = 32
	tm.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Kleine aufgedruckte Beschriftung ohne Outline und ohne Schatten, nur von vorn sichtbar.
## Weltposition der Buchse idx am Kasten in Halle C (geklemmt auf die vorhandenen Buchsen).
func get_hall_c_socket_pos(idx: int) -> Vector3:
	if _hall_c_socket_pos.is_empty():
		return hall_c_breaker_port_pos
	return _hall_c_socket_pos[clampi(idx, 0, _hall_c_socket_pos.size() - 1)]


## Alle Buchsen am Kasten in Halle C (Weltpositionen, Reihenfolge = Buchsennummer).
func get_hall_c_socket_positions() -> Array[Vector3]:
	return _hall_c_socket_pos.duplicate()


## Alle LAN-Buchsen am Wand-Router der aktuellen Stufe.
func get_router_jack_positions() -> Array[Vector3]:
	return _router_jack_pos.duplicate()


func _add_small_label(parent: Node3D, pos: Vector3, text: String, font_size: int, px_size: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = px_size
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = pos
	parent.add_child(l)
	return l


## Reiheneinbaugerät auf der Hutschiene: Gehäuse, Kipphebel und Schaltstellungsfenster.
## pos.x/pos.y ist die Mitte, pos.z ein Versatz zur Standardtiefe des Sicherungskastens.
func _add_breaker_module(parent: Node3D, pos: Vector3, width: float, body_mat: Material, toggle_mat: Material, window_mat: Material) -> void:
	_add_box_visual(parent, Vector3(pos.x, pos.y, pos.z + 0.105), Vector3(width - 0.002, 0.11, 0.05), body_mat)
	_add_box_visual(parent, Vector3(pos.x, pos.y + 0.004, pos.z + 0.1335), Vector3(width * 0.42, 0.03, 0.007), toggle_mat)
	_add_box_visual(parent, Vector3(pos.x, pos.y - 0.034, pos.z + 0.1305), Vector3(width * 0.5, 0.010, 0.002), window_mat)


## Schlauch oder Kabel als Kette von Zylindern durch `points`, mit Kugeln an den Knickstellen.
func _add_hose_visual(parent: Node3D, points: PackedVector3Array, radius: float, mat: Material) -> void:
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
		cm.height = length
		cm.radial_segments = 10
		cm.rings = 0
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = mat
		var q: Quaternion = Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
		mi.transform = Transform3D(Basis(q), (a + b) * 0.5)
		parent.add_child(mi)
	for i in range(1, points.size() - 1):
		_add_sphere_visual(parent, points[i], radius, radius * 2.0, mat)


## RJ45-Buchse: farbiger Rahmen, dunkle Öffnung mit Rastnase und goldene Kontakte.
func _add_rj45_port(parent: Node3D, pos: Vector3, frame_mat: Material, jack_mat: Material, contact_mat: Material) -> void:
	_add_box_visual(parent, pos, Vector3(0.07, 0.055, 0.03), frame_mat)
	_add_box_visual(parent, pos + Vector3(0.0, -0.002, 0.0155), Vector3(0.044, 0.034, 0.002), jack_mat)
	_add_box_visual(parent, pos + Vector3(0.0, -0.022, 0.0158), Vector3(0.016, 0.008, 0.002), jack_mat)
	_add_box_visual(parent, pos + Vector3(0.0, 0.010, 0.0168), Vector3(0.030, 0.004, 0.001), contact_mat)


## Unsichtbarer Kollisionskörper für die Tischplatte, wenn das GLB-Modell die Optik übernimmt.
func _add_desk_collider(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.78, 0.0)
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.92, 0.055, 0.90)
	col.shape = shape
	body.add_child(col)


## Prozeduraler Tisch mit Platte, Gestell, USV und Monitorständer, falls kein GLB-Modell vorhanden ist.
func _build_desk_procedural(root: Node3D) -> void:
	var wood_mat := MatLib.get_mat("wood_desk")
	var metal_mat := MatLib.make_brushed_metal(Color(0.14, 0.16, 0.20), 0.40, 0.58)
	var edge_mat := _mat(Color(0.12, 0.09, 0.06), 0.55, 0.0)
	var frame_mat := MatLib.make_brushed_metal(Color(0.20, 0.21, 0.23), 0.42, 0.70)
	var glide_mat := _mat(Color(0.06, 0.06, 0.07), 0.80, 0.10)

	# Tischplatte aus Holz mit dunkler Kantenleiste rundum
	_add_box_static(root, Vector3(0.0, 0.78, 0.0), Vector3(1.92, 0.055, 0.90), wood_mat)
	_add_box_visual(root, Vector3(0.0, 0.78, 0.452), Vector3(1.92, 0.055, 0.016), edge_mat)
	_add_box_visual(root, Vector3(0.0, 0.78, -0.452), Vector3(1.92, 0.055, 0.016), edge_mat)
	_add_box_visual(root, Vector3(0.952, 0.78, 0.0), Vector3(0.016, 0.055, 0.90), edge_mat)
	_add_box_visual(root, Vector3(-0.952, 0.78, 0.0), Vector3(0.016, 0.055, 0.90), edge_mat)

	# Stahlgestell: vier Beine mit Fußgleitern, Zargen unter der Platte
	for lx in [-0.875, 0.875]:
		for lz in [-0.40, 0.40]:
			_add_box_visual(root, Vector3(float(lx), 0.36, float(lz)), Vector3(0.045, 0.72, 0.045), frame_mat)
			_add_box_visual(root, Vector3(float(lx), 0.012, float(lz)), Vector3(0.06, 0.024, 0.06), glide_mat)
	_add_box_visual(root, Vector3(0.0, 0.72, -0.40), Vector3(1.75, 0.06, 0.03), frame_mat)
	_add_box_visual(root, Vector3(0.0, 0.72, 0.40), Vector3(1.75, 0.06, 0.03), frame_mat)
	_add_box_visual(root, Vector3(-0.875, 0.72, 0.0), Vector3(0.03, 0.06, 0.80), frame_mat)
	_add_box_visual(root, Vector3(0.875, 0.72, 0.0), Vector3(0.03, 0.06, 0.80), frame_mat)
	# Untere Querstrebe hinten verbindet die Beine
	_add_box_visual(root, Vector3(0.0, 0.14, -0.40), Vector3(1.75, 0.030, 0.030), frame_mat)
	# Kabelkanal unter der Platte, hinten
	_add_box_visual(root, Vector3(0.0, 0.735, -0.33), Vector3(1.50, 0.030, 0.10), frame_mat)

	# USV unter der Platte, links, mit grüner Status-LED an der Front
	_add_box_visual(root, Vector3(-0.66, 0.11, -0.10), Vector3(0.30, 0.22, 0.40), _mat(Color(0.16, 0.17, 0.19), 0.55, 0.30))
	_add_box_visual(root, Vector3(-0.66, 0.19, 0.103), Vector3(0.10, 0.012, 0.004), BuildingPropFactory._emissive(Color(0.20, 0.90, 0.30), 1.2))

	# Monitorständer: runde Fußplatte, Säule und Gelenkarm zur Monitorrückseite
	BuildingPropFactory._cyl(root, Vector3(-0.10, 0.8175, -0.30), 0.11, 0.02, metal_mat)
	BuildingPropFactory._cyl(root, Vector3(-0.10, 0.9775, -0.30), 0.018, 0.30, metal_mat)
	_add_box_visual(root, Vector3(-0.10, 1.12, -0.2475), Vector3(0.03, 0.03, 0.12), metal_mat)
	_add_box_visual(root, Vector3(-0.10, 1.12, -0.19), Vector3(0.05, 0.05, 0.02), metal_mat)

	# Dual Thin-Bezel Monitors held on the Articulated Steel Clamp Arm!
	_add_box_visual(root, Vector3(-0.10, 1.24, -0.18), Vector3(0.86, 0.48, 0.030), metal_mat)


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
