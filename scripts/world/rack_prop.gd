class_name RackProp
extends Node3D
## v2.1 Enterprise 19-Inch Server Rack (4U Standard / 6U Pro Titan).
## Blender 5.2 PBR cabinet (matte powder-coat, see-through hex mesh + smoked glass front & side windows,
## numbered 19" rails, internal cable channels, metered vertical PDU, spinning roof fans),
## 3 rear industrial ports (Top: Power & LAN, Bottom Plinth: Cluster Interconnect),
## integrated front OLED status display, subtle interior work-light, live server front LEDs,
## onboard 2-digit POST-code & BMC heartbeat LEDs, dynamic rear internal patch/power cables,
## removable glass side panels, and dynamic fault sparks, fire/smoke & roof heat shimmer VFX!

var rack_id: String = ""
var rack_type: String = "rack"
var slot_count: int = 4
var is_showcase_only: bool = false
var _rack_data: Dictionary = {}

var _power_port_marker: Node3D
var _net_port_marker: Node3D
var _cluster_port_marker: Node3D
var _power_led_mat: StandardMaterial3D
var _net_led_mat: StandardMaterial3D
var _cluster_led_mat: StandardMaterial3D

var _lcd_title: Label3D
var _lcd_stats: Label3D
var _lcd_bar_fill: MeshInstance3D
var _lcd_bar_mat: StandardMaterial3D

var _fan_audio: AudioStreamPlayer3D
var _fire_light: OmniLight3D
var _interior_light: OmniLight3D
var _led_bar_mat: StandardMaterial3D
var _roof_fans: Array[Node3D] = []
var _heat_fx: Array[CPUParticles3D] = []

## Bewegliche Teile aus dem Blender-Modell: panel_id -> {node, kind, closed, open, is_open, tween, area, ...}
var _panels: Dictionary = {}

var _slot_visuals: Array = []
var _hover_slot_root: Node3D
var _hover_slot_mat: StandardMaterial3D
var _hover_slot_idx: int = -1
var _anim_time: float = 0.0
var _smooth_fan_level: float = 0.0
var _smooth_fan_pitch: float = 0.9
var _smooth_interior_energy: float = 0.0

static var _tex_soft_smoke: ImageTexture
static var _tex_soft_flame: ImageTexture
static var _tex_soft_spark: ImageTexture
static var _tex_soft_heat: ImageTexture
static var _internal_pwr_mat: StandardMaterial3D
static var _internal_lan_mat: StandardMaterial3D


func setup(id: String, p_rack_type: String = "rack", p_showcase: bool = false) -> void:
	rack_id = id
	rack_type = p_rack_type
	slot_count = 6 if rack_type == "rack_pro" else 4
	is_showcase_only = p_showcase
	_ensure_shared_fx_assets()
	_build_rack_geometry()
	if not is_showcase_only:
		# Tür- und Seitenwandzustand kommt vom Server (Co-op synchronisiert).
		_apply_synced_panel_states(false)
		if not GameState.panel_states_changed.is_connected(_on_panel_states_changed):
			GameState.panel_states_changed.connect(_on_panel_states_changed)
	_setup_fan_audio()
	SettingsManager.settings_changed.connect(_apply_graphics_setting)
	_apply_graphics_setting()


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else to_global(Vector3(-0.27, 2.04, -0.49))


func get_net_port_global_pos() -> Vector3:
	return _net_port_marker.global_position if _net_port_marker != null else to_global(Vector3(0.23, 2.04, -0.49))


func get_cluster_port_global_pos() -> Vector3:
	return _cluster_port_marker.global_position if _cluster_port_marker != null else to_global(Vector3(-0.015, 0.112, -0.484))


func apply_data(data: Dictionary) -> void:
	_rack_data = data
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	_refresh_visuals()


func _apply_graphics_setting() -> void:
	var q := SettingsManager.graphics_quality
	if _fire_light != null:
		_fire_light.visible = (q >= 1)
	if _interior_light != null:
		_interior_light.visible = (q >= 1)
	for hf in _heat_fx:
		if is_instance_valid(hf):
			hf.visible = (q >= 1)


func _setup_fan_audio() -> void:
	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.position = Vector3(0.0, 1.15, 0.0)
	_fan_audio.stream = SfxManager.get_loop_stream("server_fan")
	_fan_audio.max_distance = 12.0
	_fan_audio.unit_size = 2.6
	_fan_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_fan_audio.volume_db = -60.0
	add_child(_fan_audio)


func _any_panel_open() -> bool:
	for p_v in _panels.values():
		if bool((p_v as Dictionary).get("is_open", false)):
			return true
	return false


func _process(delta: float) -> void:
	_anim_time += delta
	if _rack_data.is_empty():
		return

	var powered := bool(_rack_data.get("powered", false))
	var networked := bool(_rack_data.get("networked", false))
	var temp := float(_rack_data.get("temp", 22.0))
	var slots: Array = _rack_data.get("slots", [])
	var metrics: Dictionary = _rack_data.get("metrics", {})
	var cpu_load := clampf(float(metrics.get("cpu_pct", 20.0)) / 100.0, 0.05, 1.0)

	# 1. Dach-Abluftluefter + Hitzeflimmern oben ab 58 °C
	if powered:
		var rspeed := 8.0 + clampf((temp - 22.0) * 0.28, 0.0, 16.0)
		for rf in _roof_fans:
			if is_instance_valid(rf):
				rf.rotation.y += delta * rspeed

	var heat_active := powered and temp >= 58.0 and SettingsManager.graphics_quality >= 1
	var heat_ratio := clampf((temp - 58.0) / 30.0, 0.0, 1.0)
	for hf in _heat_fx:
		if is_instance_valid(hf):
			hf.emitting = heat_active
			if heat_active:
				hf.scale_amount_min = 0.55 + heat_ratio * 0.35
				hf.scale_amount_max = 1.05 + heat_ratio * 0.55

	# 2. Dezente Rack-Innenbeleuchtung (nur aktiv wenn Spieler nah < 7.5m ODER Tür/Seitenwand offen -> spart Licht-Passes!)
	var cam := get_viewport().get_camera_3d()
	var cam_dist := global_position.distance_to(cam.global_position) if cam != null else 0.0
	var panel_open := _any_panel_open()
	var target_inner := 0.0
	if powered and (panel_open or cam_dist < 7.5 or is_showcase_only):
		target_inner = 1.05 if panel_open else 0.52
	_smooth_interior_energy = lerpf(_smooth_interior_energy, target_inner, clampf(delta * 6.0, 0.0, 1.0))
	if _interior_light != null:
		_interior_light.visible = SettingsManager.graphics_quality >= 1 and _smooth_interior_energy > 0.02
		if _interior_light.visible:
			_interior_light.light_energy = _smooth_interior_energy
	if _led_bar_mat != null:
		_led_bar_mat.emission_energy_multiplier = 0.1 + _smooth_interior_energy * 1.4

	# 3. CPU-Drosselung: Entfernte Racks (> 14 m, ohne Brand) überspringen Lüfter-/LED-Animationen pro Frame
	if not is_showcase_only and cam_dist > 14.0:
		var any_slot_burning := false
		for s_chk in slots:
			if str((s_chk as Dictionary).get("state", "")) == "burning":
				any_slot_burning = true
				break
		if not any_slot_burning:
			_update_fan_audio(delta, 0, 0.0, temp)
			return

	# 3. Pro-Einschub Live-LEDs, Mainboard-POST-Codes, BMC-Heartbeat, Funken & Feuer/Rauch
	var active_servers := 0
	var gpu_weight := 0.0
	var has_fire := false
	var spark_flash := 0.0

	for i in range(mini(slots.size(), _slot_visuals.size())):
		var slot: Dictionary = slots[i]
		var vis: Dictionary = _slot_visuals[i]
		# Teleskopschienen: Schacht sanft nach vorne aus-/einfahren!
		var sroot: Node3D = vis.get("slot_root", null)
		if sroot != null and not is_showcase_only:
			var want_z := 0.48 if GameState.is_slot_extended(rack_id, i) else 0.0
			var cur_z := lerpf(float(vis.get("slide_z", 0.0)), want_z, clampf(delta * 8.5, 0.0, 1.0))
			if absf(cur_z - want_z) < 0.002:
				cur_z = want_z
			vis["slide_z"] = cur_z
			sroot.position.z = cur_z
			# Ausgefahrener Einschub bekommt Voll-Chassis-Hitbox, damit Zielen aufs Mainboard nie durch den Schlitten rutscht!
			var s_area: Area3D = vis.get("area", null)
			var s_shape: BoxShape3D = vis.get("area_shape", null)
			if s_area != null and s_shape != null:
				var slot_step_h: float = float(vis.get("slot_step", 0.40))
				if cur_z > 0.14:
					s_shape.size = Vector3(0.78, slot_step_h - 0.02, 0.80)
					s_area.position = Vector3(0.0, -0.01, 0.08)
				else:
					s_shape.size = Vector3(0.76, slot_step_h - 0.04, 0.24)
					s_area.position = Vector3(0.0, 0.0, 0.41)
			var rc: Node3D = vis.get("rear_cables", null)
			if rc != null and cur_z > 0.05:
				rc.visible = false
			if _hover_slot_root != null and _hover_slot_root.visible and _hover_slot_idx == i:
				_hover_slot_root.position = sroot.position
		var item_type := str(slot["item_type"])
		var st := str(slot["state"])
		var led_mat: StandardMaterial3D = vis["led_mat"]
		var hdd_mats: Array = vis["hdd_mats"]
		var nic_mat: StandardMaterial3D = vis["nic_mat"]
		var bmc_mat: StandardMaterial3D = vis["bmc_mat"]
		var post_lbl: Label3D = vis["post_lbl"]
		var smoke_fx: CPUParticles3D = vis["smoke_fx"]
		var flame_fx: CPUParticles3D = vis["flame_fx"]
		var spark_fx: CPUParticles3D = vis["spark_fx"]

		if item_type == "":
			smoke_fx.emitting = false
			flame_fx.emitting = false
			spark_fx.emitting = false
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
			smoke_fx.emitting = true
			flame_fx.emitting = true
			spark_fx.emitting = true
			led_mat.emission = Color(0.98, 0.16, 0.06)
			led_mat.emission_energy_multiplier = 1.4 + 0.6 * sin(_anim_time * 18.0)
			for hm in hdd_mats:
				(hm as StandardMaterial3D).emission_energy_multiplier = 0.02
			nic_mat.emission_energy_multiplier = 0.02
			bmc_mat.emission = Color(1.0, 0.15, 0.08)
			bmc_mat.emission_energy_multiplier = 1.4
			post_lbl.text = "FF"
			post_lbl.modulate = Color(1.0, 0.22, 0.10)
			post_lbl.visible = true
		elif st == "crashed":
			smoke_fx.emitting = false
			flame_fx.emitting = false
			# Periodischer elektrischer Funkenflug & Kurzschluss-Mikroblitz!
			var sp_t := float(vis["spark_timer"]) - delta
			if sp_t <= 0.0:
				vis["spark_timer"] = randf_range(1.25, 2.75)
				vis["spark_burst"] = 0.14
				spark_fx.restart()
				spark_fx.emitting = true
			else:
				vis["spark_timer"] = sp_t
			var burst := maxf(0.0, float(vis["spark_burst"]) - delta)
			vis["spark_burst"] = burst
			if burst > 0.0:
				spark_flash = maxf(spark_flash, burst / 0.14)
			var blink := sin(_anim_time * 10.5 + float(i)) > 0.0
			led_mat.emission = Color(0.95, 0.16, 0.12)
			led_mat.emission_energy_multiplier = 1.15 if blink else 0.06
			for hm in hdd_mats:
				(hm as StandardMaterial3D).emission_energy_multiplier = 0.02
			nic_mat.emission_energy_multiplier = 0.02
			bmc_mat.emission = Color(0.95, 0.18, 0.12)
			bmc_mat.emission_energy_multiplier = 1.2 if blink else 0.1
			post_lbl.text = "E4" if (i % 2 == 0) else "C5"
			post_lbl.modulate = Color(1.0, 0.26, 0.16) if blink else Color(0.35, 0.08, 0.05)
			post_lbl.visible = powered
		else:
			smoke_fx.emitting = false
			flame_fx.emitting = false
			spark_fx.emitting = false
			if not powered:
				led_mat.emission = Color(0.14, 0.14, 0.16)
				led_mat.emission_energy_multiplier = 0.02
				for hm in hdd_mats:
					(hm as StandardMaterial3D).emission_energy_multiplier = 0.02
				nic_mat.emission_energy_multiplier = 0.02
				bmc_mat.emission_energy_multiplier = 0.02
				post_lbl.visible = false
			elif temp >= 68.0:
				var warn_p := 0.75 + 0.45 * sin(_anim_time * 8.0 + float(i))
				led_mat.emission = Color(0.96, 0.62, 0.10)
				led_mat.emission_energy_multiplier = warn_p
				for h_i in range(hdd_mats.size()):
					var hm := hdd_mats[h_i] as StandardMaterial3D
					hm.emission = Color(0.95, 0.56, 0.12)
					hm.emission_energy_multiplier = 0.80 if sin(_anim_time * (14.0 + float(h_i) * 4.7) + float(i)) > 0.0 else 0.06
				nic_mat.emission = Color(0.24, 0.64, 0.96)
				nic_mat.emission_energy_multiplier = 0.75 if networked else 0.04
				bmc_mat.emission = Color(0.96, 0.64, 0.14)
				bmc_mat.emission_energy_multiplier = 0.9
				post_lbl.text = "7F"
				post_lbl.modulate = Color(1.0, 0.64, 0.16)
				post_lbl.visible = true
			else:
				# Realistische Enterprise-Server-Aktivitaet (feine punktfoermige LEDs, kein Neon!)
				if not networked and item_type != "net_switch":
					led_mat.emission = Color(0.90, 0.58, 0.16)
					led_mat.emission_energy_multiplier = 0.72
				else:
					led_mat.emission = Color(0.20, 0.82, 0.38)
					led_mat.emission_energy_multiplier = 0.82
				var rate := 8.0 + cpu_load * 16.0
				for h_i in range(hdd_mats.size()):
					var hm := hdd_mats[h_i] as StandardMaterial3D
					var ph := _anim_time * (rate + float(h_i) * 3.9 + float(i) * 2.1)
					var trig := sin(ph) * cos(ph * 0.63 + float(h_i) * 1.7)
					hm.emission = Color(0.22, 0.80, 0.38) if h_i == 0 else Color(0.94, 0.68, 0.16)
					hm.emission_energy_multiplier = 0.88 if trig > (0.48 - cpu_load * 0.38) else 0.05
				if networked or item_type == "net_switch":
					var pkt := sin(_anim_time * (19.0 + float(i) * 4.3)) > 0.15
					nic_mat.emission = Color(0.22, 0.66, 0.98)
					nic_mat.emission_energy_multiplier = 0.88 if pkt else 0.14
				else:
					nic_mat.emission_energy_multiplier = 0.03
				# Sanfter BMC-Heartbeat auf dem Mainboard (~1.2 Hz)
				var hb := 0.25 + 0.75 * absf(sin(_anim_time * 3.8 + float(i) * 0.9))
				bmc_mat.emission = Color(0.18, 0.88, 0.44)
				bmc_mat.emission_energy_multiplier = hb
				post_lbl.text = "A0" if (i % 2 == 0) else "AA"
				post_lbl.modulate = Color(0.96, 0.38, 0.14)
				post_lbl.visible = true

	# Feuer- ODER Kurzschluss-Funkenlicht (kein Dauer-Neon am Boden!)
	if _fire_light != null and _fire_light.visible:
		if has_fire:
			_fire_light.light_color = Color(1.0, 0.40, 0.10)
			_fire_light.light_energy = 1.65 + 0.50 * sin(_anim_time * 18.0)
		elif spark_flash > 0.01:
			_fire_light.light_color = Color(0.75, 0.88, 1.0)
			_fire_light.light_energy = 1.45 * spark_flash
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
	var clustered := bool(_rack_data.get("clustered", false))
	var temp := float(_rack_data.get("temp", 22.0))
	var slots: Array = _rack_data.get("slots", [])

	if _power_led_mat != null:
		_power_led_mat.emission = Color(0.24, 0.84, 0.40) if powered else Color(0.16, 0.16, 0.18)
		_power_led_mat.emission_energy_multiplier = 1.05 if powered else 0.04

	if _net_led_mat != null:
		_net_led_mat.emission = Color(0.22, 0.62, 0.96) if networked else Color(0.16, 0.16, 0.18)
		_net_led_mat.emission_energy_multiplier = 1.05 if networked else 0.04

	if _cluster_led_mat != null:
		_cluster_led_mat.emission = Color(0.68, 0.40, 0.96) if clustered else Color(0.16, 0.16, 0.18)
		_cluster_led_mat.emission_energy_multiplier = 1.10 if clustered else 0.04

	var used_slots := 0
	var rack_ram_gb := 0
	var total_watts := 0
	var any_fault := false
	var any_fire := false

	for i in range(mini(slots.size(), _slot_visuals.size())):
		var slot: Dictionary = slots[i]
		var vis: Dictionary = _slot_visuals[i]
		var item_type := str(slot["item_type"])
		var empty_mesh: Node3D = vis["empty_root"]
		var hw_holder: Node3D = vis["hw_holder"]
		var rear_cables: Node3D = vis["rear_cables"]
		var led_pod: Node3D = vis["led_pod"]
		var diag_pod: Node3D = vis["diag_pod"]
		var slot_lbl: Label3D = vis["slot_lbl"]

		if item_type == "":
			empty_mesh.visible = true
			hw_holder.visible = false
			rear_cables.visible = false
			led_pod.visible = false
			diag_pod.visible = false
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
			rear_cables.visible = true
			led_pod.visible = true
			diag_pod.visible = true

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
				_optimize_detail_subtree(srv_mesh, true, DETAIL_RANGE_END)
				hw_holder.add_child(srv_mesh)
				vis["hw_sig"] = sig

			var stats := GameState.get_slot_stats(slot)
			rack_ram_gb += int(stats.get("ram_gb", 0))
			total_watts += int(stats.get("watts", 0))
			var cat: Dictionary = GameState.ITEM_CATALOG[item_type]
			var st := str(slot["state"])
			if st == "burning":
				any_fire = true
				slot_lbl.text = tr("BRAND! (%.0f%%)") % (float(slot["fire_level"]) * 100.0)
				slot_lbl.modulate = Color(0.98, 0.34, 0.16)
			elif st == "crashed":
				any_fault = true
				slot_lbl.text = tr("DEFEKT · Schacht ziehen → Werkbank")
				slot_lbl.modulate = Color(0.96, 0.34, 0.30)
			else:
				var up_tag := _get_upgrade_badge(slot)
				slot_lbl.text = "%s%s" % [tr(str(cat["name"])), up_tag]
				slot_lbl.modulate = Color(0.92, 0.93, 0.94)

	# Integriertes Front-OLED/LCD-Statusdisplay aktualisieren
	var rname := GameState.get_rack_display_name(rack_id)
	var pro_tag := " PRO" if rack_type == "rack_pro" else ""
	var max_pdu := int((GameState.ITEM_CATALOG.get(rack_type, {}) as Dictionary).get("max_pdu_watts", 3200))
	var status_col := Color(0.24, 0.88, 0.48)
	var status_txt := "ONLINE"
	if any_fire:
		status_col = Color(1.0, 0.24, 0.12)
		status_txt = "ALARM: BRAND"
	elif not powered:
		status_col = Color(0.55, 0.58, 0.62)
		status_txt = "OFFLINE"
	elif any_fault:
		status_col = Color(1.0, 0.30, 0.22)
		status_txt = "STÖRUNG"
	elif temp >= 68.0 or total_watts > max_pdu:
		status_col = Color(0.98, 0.62, 0.14)
		status_txt = "ÜBERHITZT" if temp >= 68.0 else "ÜBERLAST"
	elif not networked:
		status_col = Color(0.94, 0.68, 0.20)
		status_txt = "KEIN LAN"

	if _lcd_title != null:
		var link_tag := "  LINK" if clustered else ""
		_lcd_title.text = "%s%s  •  %d/%d%s" % [rname.to_upper(), pro_tag, used_slots, slot_count, link_tag]
		_lcd_title.modulate = Color(0.95, 0.84, 0.48) if rack_type == "rack_pro" else Color(0.84, 0.92, 0.98)
	if _lcd_stats != null:
		_lcd_stats.text = "%dW  •  %.0f°C  •  %s" % [total_watts if powered else 0, temp, status_txt]
		_lcd_stats.modulate = status_col
	if _lcd_bar_fill != null and _lcd_bar_mat != null:
		var ratio := clampf(maxf(float(total_watts) / float(maxi(max_pdu, 1)), (temp - 20.0) / 65.0), 0.04, 1.0) if powered else 0.0
		_lcd_bar_fill.visible = powered
		_lcd_bar_fill.scale.x = ratio
		_lcd_bar_fill.position.x = -0.195 + (0.39 * ratio) * 0.5
		_lcd_bar_mat.albedo_color = status_col
		_lcd_bar_mat.emission = status_col

	# Kein schwebender gelber Text mehr über dem Rack: alle Infos stehen direkt am Rack-OLED & Fadenkreuz.


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
	var hdr_zc := total_h - 0.094
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

	# Neues Blender-5.2-Rack-Modell laden (assets/models/rack.glb bzw. rack_pro.glb)
	var custom_shell := ModelLoader.instantiate_custom_model(rack_type)
	var use_procedural_shell := custom_shell == null
	if custom_shell != null:
		add_child(custom_shell)
		_setup_custom_shell(custom_shell, total_h)

	var post_h := total_h - 0.24
	var mid_y := 0.16 + post_h * 0.5

	if use_procedural_shell:
		_build_procedural_shell_fallback(total_h, top_y, post_h, mid_y, is_pro, frame_mat, steel_mat, side_mat, dark_mat, perf_mat, glass)

	# 1. Dezente Rack-Innenbeleuchtung (beleuchtet Mainboards, Kupferkuehler & GPUs hinter dem Rauchglas!)
	_interior_light = OmniLight3D.new()
	_interior_light.position = Vector3(0.0, mid_y + 0.18, 0.14)
	_interior_light.light_color = Color(0.95, 0.97, 1.0)
	_interior_light.omni_range = 1.75
	_interior_light.omni_attenuation = 1.25
	_interior_light.light_energy = 0.0
	_interior_light.shadow_enabled = false
	add_child(_interior_light)

	# 2. Feuer- & Kurzschluss-Funkenlicht (nur aktiv bei Brand oder Defekt-Funken!)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, mid_y, 0.72)
	_fire_light.omni_range = 3.2
	_fire_light.light_energy = 0.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)

	# 3. Hitzeflimmern / warme Abluft ueber den beiden Dach-Abluftlueftern (aktiv ab 58 °C)
	for rx in [-0.20, 0.20]:
		var hf := _make_heat_shimmer_emitter()
		hf.position = Vector3(float(rx), total_h + 0.03, -0.05)
		add_child(hf)
		_heat_fx.append(hf)

	# 4. DIE 3 HINTEREN ANSCHLUESSE (2 OBEN: STROM & LAN, 1 GANZ UNTEN AM SOCKEL: RACK-VERBINDUNG!)
	# Oben links: Strom (PWR 230V/32A IEC)
	if use_procedural_shell:
		_add_box(self, Vector3(-0.25, top_y, -0.450), Vector3(0.24, 0.12, 0.055), dark_mat)
		_add_box(self, Vector3(-0.27, top_y, -0.474), Vector3(0.11, 0.060, 0.030), _mat(Color(0.86, 0.66, 0.16), 0.46, 0.10))
	_power_led_mat = _make_led_mat(Color(0.24, 0.84, 0.40))
	_limit_detail_range(_add_cyl(self, Vector3(-0.145, top_y - 0.002, -0.474), 0.009, 0.010, _power_led_mat, Vector3(90.0, 0.0, 0.0)))
	_power_port_marker = Node3D.new()
	_power_port_marker.position = Vector3(-0.27, top_y - 0.004, -0.492)
	add_child(_power_port_marker)
	if not is_showcase_only:
		var p_area := _make_area(Vector3(0.30, 0.24, 0.24), {"interact_type": "power_port", "entity_id": rack_id})
		p_area.position = Vector3(-0.25, top_y, -0.47)
		add_child(p_area)

	# Oben rechts: LAN (100G RJ45/SFP+ Uplink)
	if use_procedural_shell:
		_add_box(self, Vector3(0.25, top_y, -0.450), Vector3(0.24, 0.12, 0.055), dark_mat)
		_add_box(self, Vector3(0.23, top_y, -0.474), Vector3(0.11, 0.060, 0.030), _mat(Color(0.20, 0.50, 0.86), 0.45, 0.22))
	_net_led_mat = _make_led_mat(Color(0.22, 0.62, 0.96))
	_limit_detail_range(_add_cyl(self, Vector3(0.355, top_y - 0.002, -0.474), 0.009, 0.010, _net_led_mat, Vector3(90.0, 0.0, 0.0)))
	_net_port_marker = Node3D.new()
	_net_port_marker.position = Vector3(0.23, top_y - 0.004, -0.492)
	add_child(_net_port_marker)
	if not is_showcase_only:
		var n_area := _make_area(Vector3(0.30, 0.24, 0.24), {"interact_type": "net_port", "entity_id": rack_id})
		n_area.position = Vector3(0.25, top_y, -0.47)
		add_child(n_area)

	# Ganz unten mittig am Ruecksockel: Cluster- / Rack-Verbindungsport (LINK)
	if use_procedural_shell:
		_add_box(self, Vector3(0.0, 0.115, -0.452), Vector3(0.28, 0.10, 0.055), dark_mat)
		_add_box(self, Vector3(-0.015, 0.112, -0.474), Vector3(0.12, 0.055, 0.030), _mat(Color(0.60, 0.32, 0.86), 0.45, 0.22))
	_cluster_led_mat = _make_led_mat(Color(0.68, 0.40, 0.96))
	_limit_detail_range(_add_cyl(self, Vector3(0.105, 0.113, -0.468), 0.009, 0.010, _cluster_led_mat, Vector3(90.0, 0.0, 0.0)))
	_cluster_port_marker = Node3D.new()
	_cluster_port_marker.position = Vector3(-0.015, 0.112, -0.486)
	add_child(_cluster_port_marker)
	if not is_showcase_only:
		var c_area := _make_area(Vector3(0.36, 0.26, 0.28), {"interact_type": "cluster_port", "entity_id": rack_id})
		c_area.position = Vector3(0.0, 0.13, -0.47)
		add_child(c_area)

	# 5. INTEGRIERTES FRONT-OLED/LCD-STATUSDISPLAY IN DER KOPFBLENDE
	_lcd_title = Label3D.new()
	_lcd_title.text = GameState.get_rack_display_name(rack_id).to_upper()
	_lcd_title.font_size = 20
	_lcd_title.outline_size = 0
	_lcd_title.pixel_size = 0.00145
	_lcd_title.double_sided = false
	_lcd_title.no_depth_test = false
	_lcd_title.shaded = false
	_lcd_title.position = Vector3(0.0, hdr_zc + 0.022, 0.4665)
	_limit_detail_range(_lcd_title)
	add_child(_lcd_title)

	_lcd_stats = Label3D.new()
	_lcd_stats.text = "0W  •  22°C  •  OFFLINE"
	_lcd_stats.font_size = 18
	_lcd_stats.outline_size = 0
	_lcd_stats.pixel_size = 0.00135
	_lcd_stats.double_sided = false
	_lcd_stats.shaded = false
	_lcd_stats.position = Vector3(0.0, hdr_zc - 0.006, 0.4665)
	_limit_detail_range(_lcd_stats)
	add_child(_lcd_stats)

	var bar_bg_mat := _mat(Color(0.08, 0.10, 0.13), 0.8, 0.0)
	_limit_detail_range(_add_box(self, Vector3(0.0, hdr_zc - 0.029, 0.4658), Vector3(0.39, 0.007, 0.001), bar_bg_mat))
	_lcd_bar_mat = _make_led_mat(Color(0.24, 0.88, 0.48))
	_lcd_bar_mat.emission_energy_multiplier = 0.95
	_lcd_bar_fill = _add_box(self, Vector3(0.0, hdr_zc - 0.029, 0.4664), Vector3(0.39, 0.006, 0.001), _lcd_bar_mat)
	_lcd_bar_fill.visible = false
	_limit_detail_range(_lcd_bar_fill)

	# 6. SERVER-EINSCHUEBE (4 bzw. 6 Bays auf ausfahrbaren Teleskopschienen mit echten 3D-Servern & VFX!)
	for i in range(slot_count):
		var sy := first_slot_y + float(i) * slot_step
		# Feste aeusserste Teleskop-Fuehrungsschienen am Rack-Rahmen
		_add_box(self, Vector3(-0.382, sy - 0.088, 0.0), Vector3(0.018, 0.032, 0.74), steel_mat)
		_add_box(self, Vector3(0.382, sy - 0.088, 0.0), Vector3(0.018, 0.032, 0.74), steel_mat)

		var slot_root := Node3D.new()
		slot_root.position = Vector3(0.0, sy, 0.0)
		add_child(slot_root)

		# Mitfahrende innere Teleskopschienen links/rechts
		_limit_detail_range(_add_box(slot_root, Vector3(-0.366, -0.088, -0.02), Vector3(0.014, 0.024, 0.72), steel_mat), true)
		_limit_detail_range(_add_box(slot_root, Vector3(0.366, -0.088, -0.02), Vector3(0.014, 0.024, 0.72), steel_mat), true)

		var empty_root := Node3D.new()
		slot_root.add_child(empty_root)
		_limit_detail_range(_add_box(empty_root, Vector3(-0.355, -0.095, 0.0), Vector3(0.038, 0.022, 0.74), steel_mat), true)
		_limit_detail_range(_add_box(empty_root, Vector3(0.355, -0.095, 0.0), Vector3(0.038, 0.022, 0.74), steel_mat), true)
		# Front-Ziehgriff fuer den leeren Teleskop-Schlitten
		_limit_detail_range(_add_box(empty_root, Vector3(0.0, -0.095, 0.378), Vector3(0.70, 0.024, 0.018), steel_mat), true)
		var shelf_mat := StandardMaterial3D.new()
		shelf_mat.albedo_color = Color(0.24, 0.26, 0.29, 0.28)
		shelf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_limit_detail_range(_add_box(empty_root, Vector3(0.0, -0.105, 0.0), Vector3(0.68, 0.014, 0.72), shelf_mat), true)

		var hw_holder := Node3D.new()
		hw_holder.visible = false
		slot_root.add_child(hw_holder)

		# Dynamische kurze interne Strom- & Patchkabel hinten am eingebauten Server zur vertikalen PDU / Kabelkanal!
		var rear_cables := _build_slot_internal_cables()
		rear_cables.visible = false
		_optimize_detail_subtree(rear_cables, true, DETAIL_RANGE_END)
		slot_root.add_child(rear_cables)

		# 5 feine realistische Front-Status- & Aktivitaets-LEDs (PWR, 3x HDD I/O, NIC)
		var led_mat := _make_led_mat(Color(0.20, 0.82, 0.38))
		var hdd_mats: Array = [
			_make_led_mat(Color(0.22, 0.80, 0.38)),
			_make_led_mat(Color(0.94, 0.68, 0.16)),
			_make_led_mat(Color(0.94, 0.68, 0.16)),
		]
		var nic_mat := _make_led_mat(Color(0.22, 0.66, 0.98))

		var led_pod := Node3D.new()
		led_pod.visible = false
		slot_root.add_child(led_pod)
		_limit_detail_range(_add_box(led_pod, Vector3(0.348, 0.010, 0.415), Vector3(0.010, 0.010, 0.008), led_mat))
		for h_i in range(3):
			_limit_detail_range(_add_box(led_pod, Vector3(0.348, -0.008 - float(h_i) * 0.014, 0.415), Vector3(0.008, 0.006, 0.008), hdd_mats[h_i] as Material))
		_limit_detail_range(_add_box(led_pod, Vector3(0.348, -0.052, 0.415), Vector3(0.009, 0.008, 0.008), nic_mat))

		# Onboard Mainboard-Diagnose: 2-stelliger 7-Segment POST-Code + BMC-Heartbeat-LED (durchs Glas sichtbar!)
		var diag_pod := Node3D.new()
		diag_pod.visible = false
		slot_root.add_child(diag_pod)

		var post_lbl := Label3D.new()
		post_lbl.text = "A0"
		post_lbl.font_size = 24
		post_lbl.outline_size = 0
		post_lbl.pixel_size = 0.0015
		post_lbl.shaded = false
		post_lbl.modulate = Color(0.96, 0.38, 0.14)
		post_lbl.position = Vector3(0.20, -0.058, 0.14)
		post_lbl.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
		_limit_detail_range(post_lbl)
		diag_pod.add_child(post_lbl)

		var bmc_mat := _make_led_mat(Color(0.18, 0.88, 0.44))
		_limit_detail_range(_add_box(diag_pod, Vector3(0.16, -0.064, -0.04), Vector3(0.008, 0.005, 0.008), bmc_mat))

		# Dynamische Defekt-Funken & Brand-Rauch/Flammen-Partikel (gut sichtbar vor/aus dem Einschub!)
		var smoke_fx := _make_smoke_emitter()
		smoke_fx.position = Vector3(0.0, 0.02, 0.34)
		slot_root.add_child(smoke_fx)

		var flame_fx := _make_flame_emitter()
		flame_fx.position = Vector3(0.0, -0.02, 0.36)
		slot_root.add_child(flame_fx)

		var spark_fx := _make_spark_emitter()
		spark_fx.position = Vector3(0.04, -0.01, 0.38)
		slot_root.add_child(spark_fx)

		var slot_lbl := Label3D.new()
		slot_lbl.text = "SLOT %d" % (i + 1)
		slot_lbl.font_size = 15
		slot_lbl.pixel_size = 0.00195
		slot_lbl.double_sided = false
		slot_lbl.position = Vector3(0.0, 0.092, 0.440)
		slot_lbl.visibility_range_end = 6.5
		slot_lbl.visibility_range_end_margin = 1.0
		slot_root.add_child(slot_lbl)

		var s_area: Area3D = null
		var s_shape: BoxShape3D = null
		if not is_showcase_only:
			s_area = _make_area(Vector3(0.76, slot_step - 0.04, 0.24), {
				"interact_type": "rack_slot",
				"entity_id": rack_id,
				"slot_index": i,
				"rack_prop": self,
			})
			s_area.position = Vector3(0.0, 0.0, 0.41)
			slot_root.add_child(s_area)
			if s_area.get_child_count() > 0 and s_area.get_child(0) is CollisionShape3D:
				s_shape = (s_area.get_child(0) as CollisionShape3D).shape as BoxShape3D

		_slot_visuals.append({
			"slot_root": slot_root,
			"slot_step": slot_step,
			"area": s_area,
			"area_shape": s_shape,
			"slide_z": 0.0,
			"empty_root": empty_root,
			"hw_holder": hw_holder,
			"rear_cables": rear_cables,
			"hw_fans": [],
			"hw_sig": "",
			"led_pod": led_pod,
			"diag_pod": diag_pod,
			"led_mat": led_mat,
			"hdd_mats": hdd_mats,
			"nic_mat": nic_mat,
			"bmc_mat": bmc_mat,
			"post_lbl": post_lbl,
			"smoke_fx": smoke_fx,
			"flame_fx": flame_fx,
			"spark_fx": spark_fx,
			"spark_timer": randf_range(0.6, 2.0),
			"spark_burst": 0.0,
			"slot_lbl": slot_lbl,
		})

	if not is_showcase_only:
		_build_slot_hover_frame(slot_step)


func _build_slot_hover_frame(slot_step: float) -> void:
	_hover_slot_root = Node3D.new()
	_hover_slot_root.visible = false
	add_child(_hover_slot_root)

	_hover_slot_mat = StandardMaterial3D.new()
	_hover_slot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_slot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_slot_mat.albedo_color = Color(0.28, 0.86, 1.0, 0.92)
	_hover_slot_mat.no_depth_test = false

	var hw := 0.385
	var hh := (slot_step - 0.05) * 0.5
	var zf := 0.448
	var bar_t := 0.011
	# Oberer & unterer dünner Leucht-Rahmen + seitliche Eckklammern
	_add_box(_hover_slot_root, Vector3(0.0, hh, zf), Vector3(hw * 2.0, bar_t, bar_t), _hover_slot_mat)
	_add_box(_hover_slot_root, Vector3(0.0, -hh, zf), Vector3(hw * 2.0, bar_t, bar_t), _hover_slot_mat)
	_add_box(_hover_slot_root, Vector3(-hw, 0.0, zf), Vector3(bar_t, hh * 2.0, bar_t), _hover_slot_mat)
	_add_box(_hover_slot_root, Vector3(hw, 0.0, zf), Vector3(bar_t, hh * 2.0, bar_t), _hover_slot_mat)
	# Seitliche Schienen-Markierung für ausgefahrene Schlitten
	_add_box(_hover_slot_root, Vector3(-hw, -hh, 0.06), Vector3(bar_t, bar_t, 0.76), _hover_slot_mat)
	_add_box(_hover_slot_root, Vector3(hw, -hh, 0.06), Vector3(bar_t, bar_t, 0.76), _hover_slot_mat)


## Hebt den aktuell anvisierten Rack-Einschub klar farbcodiert hervor (verhindert Vertippen!).
func set_hovered_slot(slot_idx: int, mode: String = "default") -> void:
	if _hover_slot_root == null:
		return
	if slot_idx < 0 or slot_idx >= _slot_visuals.size():
		_hover_slot_root.visible = false
		_hover_slot_idx = -1
		return
	_hover_slot_idx = slot_idx
	var sroot: Node3D = (_slot_visuals[slot_idx] as Dictionary).get("slot_root", null)
	if sroot != null:
		_hover_slot_root.position = sroot.position
	_hover_slot_root.visible = true
	match mode:
		"insert":
			_hover_slot_mat.albedo_color = Color(0.20, 0.98, 0.56, 0.94)
		"pull":
			_hover_slot_mat.albedo_color = Color(1.0, 0.80, 0.22, 0.96)
		"warn":
			_hover_slot_mat.albedo_color = Color(1.0, 0.28, 0.22, 0.95)
		_:
			_hover_slot_mat.albedo_color = Color(0.32, 0.82, 1.0, 0.85)


## Kurze realistische 3D-Kabelboegen hinten am Server (Strom zur vertikalen PDU + Cat6A Patchkabel zum Kanal).
func _build_slot_internal_cables() -> Node3D:
	var root := Node3D.new()
	# Schwarzes IEC-Stromkabel von Server-PSU (+0.28, -0.05, -0.32) zur vertikalen PDU (+0.405, -0.03, -0.39)
	_add_cable_arc(root, [
		Vector3(0.28, -0.052, -0.31),
		Vector3(0.30, -0.052, -0.375),
		Vector3(0.365, -0.042, -0.405),
		Vector3(0.405, -0.025, -0.392),
	], 0.0065, _internal_pwr_mat)
	# Blaues Cat6A-Patchkabel von Server-I/O (-0.18, -0.045, -0.31) in den linken Kabelmanagement-Kanal (-0.40, -0.05, -0.29)
	_add_cable_arc(root, [
		Vector3(-0.18, -0.046, -0.31),
		Vector3(-0.22, -0.046, -0.378),
		Vector3(-0.34, -0.048, -0.375),
		Vector3(-0.40, -0.052, -0.295),
	], 0.0045, _internal_lan_mat)
	return root


func _add_cable_arc(parent: Node3D, pts: Array[Vector3], radius: float, mat: Material) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var length := d.length()
		if length < 0.002:
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = length + radius * 0.6
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = mat
		mi.position = (a + b) * 0.5
		var up := d.normalized()
		var ref := Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP
		var right := up.cross(ref).normalized()
		var fwd := right.cross(up).normalized()
		mi.basis = Basis(right, up, fwd)
		_limit_detail_range(mi)
		parent.add_child(mi)


# ==============================================================================
# PARTIKEL-EFFEKTE (Rauch, Flammen, Funkenflug, Dach-Hitzeflimmern)
# ==============================================================================

static func _ensure_shared_fx_assets() -> void:
	if _tex_soft_smoke == null:
		_tex_soft_smoke = _make_radial_tex(64, Color(0.14, 0.14, 0.16, 0.86), 1.4)
	if _tex_soft_flame == null:
		_tex_soft_flame = _make_radial_tex(64, Color(1.0, 0.60, 0.14, 0.96), 1.8)
	if _tex_soft_spark == null:
		_tex_soft_spark = _make_radial_tex(32, Color(1.0, 0.92, 0.56, 1.0), 2.2)
	if _tex_soft_heat == null:
		_tex_soft_heat = _make_radial_tex(64, Color(0.98, 0.88, 0.74, 0.28), 1.3)
	if _internal_pwr_mat == null:
		_internal_pwr_mat = StandardMaterial3D.new()
		_internal_pwr_mat.albedo_color = Color(0.06, 0.065, 0.07)
		_internal_pwr_mat.roughness = 0.72
	if _internal_lan_mat == null:
		_internal_lan_mat = StandardMaterial3D.new()
		_internal_lan_mat.albedo_color = Color(0.14, 0.42, 0.76)
		_internal_lan_mat.roughness = 0.54


static func _make_radial_tex(size: int, col: Color, falloff: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), falloff) * col.a
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


func _make_particle_quad(tex: Texture2D, additive: bool, quad_size: float = 0.22) -> QuadMesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(quad_size, quad_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.material = mat
	return qm


func _make_smoke_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 24
	p.lifetime = 1.8
	p.preprocess = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.24, 0.04, 0.12)
	p.direction = Vector3(0.0, 1.0, 0.24)
	p.spread = 24.0
	p.gravity = Vector3(0.0, 0.30, 0.0)
	p.initial_velocity_min = 0.32
	p.initial_velocity_max = 0.58
	p.scale_amount_min = 0.85
	p.scale_amount_max = 2.0
	p.mesh = _make_particle_quad(_tex_soft_smoke, false, 0.24)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.16, 0.18, 0.0))
	grad.add_point(0.18, Color(0.12, 0.12, 0.14, 0.85))
	grad.set_color(1, Color(0.24, 0.24, 0.26, 0.0))
	p.color_ramp = grad
	return p


func _make_flame_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 26
	p.lifetime = 0.58
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.20, 0.03, 0.08)
	p.direction = Vector3(0.0, 1.0, 0.18)
	p.spread = 20.0
	p.gravity = Vector3(0.0, 0.72, 0.0)
	p.initial_velocity_min = 0.28
	p.initial_velocity_max = 0.62
	p.scale_amount_min = 0.65
	p.scale_amount_max = 1.45
	p.mesh = _make_particle_quad(_tex_soft_flame, true, 0.20)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.90, 0.42, 1.0))
	grad.add_point(0.45, Color(1.0, 0.44, 0.08, 0.92))
	grad.set_color(1, Color(0.65, 0.12, 0.02, 0.0))
	p.color_ramp = grad
	return p


func _make_spark_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.90
	p.amount = 18
	p.lifetime = 0.42
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.16, 0.03, 0.06)
	p.direction = Vector3(0.0, 0.35, 1.0)
	p.spread = 52.0
	p.gravity = Vector3(0.0, -4.8, 0.0)
	p.initial_velocity_min = 0.75
	p.initial_velocity_max = 1.85
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.15
	p.mesh = _make_particle_quad(_tex_soft_spark, true, 0.055)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.98, 1.0, 1.0))
	grad.add_point(0.35, Color(1.0, 0.80, 0.28, 1.0))
	grad.set_color(1, Color(1.0, 0.36, 0.06, 0.0))
	p.color_ramp = grad
	return p


func _make_heat_shimmer_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.45
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.13, 0.01, 0.13)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 16.0
	p.gravity = Vector3(0.0, 0.16, 0.0)
	p.initial_velocity_min = 0.22
	p.initial_velocity_max = 0.38
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.50
	p.mesh = _make_particle_quad(_tex_soft_heat, true, 0.26)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.90, 0.76, 0.0))
	grad.add_point(0.3, Color(1.0, 0.84, 0.68, 0.65))
	grad.set_color(1, Color(1.0, 0.90, 0.78, 0.0))
	p.color_ramp = grad
	return p


# ==============================================================================
# HILFSFUNKTIONEN & BEWEGLICHE TUEREN / ABNEHMBARE SEITENWAENDE
# ==============================================================================

func _make_led_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.24
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.04
	return m


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


const DETAIL_RANGE_END := 14.0
const DETAIL_RANGE_MARGIN := 1.0


func _limit_detail_range(node: GeometryInstance3D, disable_shadow: bool = false) -> void:
	if node == null:
		return
	node.visibility_range_end = DETAIL_RANGE_END
	node.visibility_range_end_margin = DETAIL_RANGE_MARGIN
	if disable_shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _optimize_detail_subtree(root: Node, disable_shadow: bool = true, max_dist: float = DETAIL_RANGE_END) -> void:
	if root == null:
		return
	for n in _collect_nodes(root):
		if n is GeometryInstance3D:
			var gi := n as GeometryInstance3D
			if disable_shadow:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if max_dist > 0.0:
				gi.visibility_range_end = max_dist
				gi.visibility_range_end_margin = DETAIL_RANGE_MARGIN


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, rad: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## Tueren, abnehmbare Glas-Seitenwaende, Dachluefter & Decken-LED-Leiste aus dem Blender-Modell verdrahten.
func _setup_custom_shell(shell: Node3D, total_h: float) -> void:
	for n in _collect_nodes(shell):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var sm := mi.mesh.surface_get_material(s)
					if sm is StandardMaterial3D and sm.resource_name == "Rack_InteriorLed":
						var dup := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(s, dup)
						_led_bar_mat = dup
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
			if nm.contains("FrontDoor") and open_deg < 0.0:
				open_deg = absf(open_deg)
			_panels[nm] = {
				"node": n3,
				"kind": "hinge",
				"closed": n3.rotation.y,
				"open": n3.rotation.y + deg_to_rad(open_deg),
				"is_open": false,
				"tween": null,
			}
			if not is_showcase_only:
				var reach := 0.40 if nm.contains("RearDoor") else 0.84
				var front := signf(n3.position.z)
				var d_area := _make_area(Vector3(reach + 0.06, total_h * 0.82, 0.18), {
					"interact_type": "rack_panel",
					"entity_id": rack_id,
					"panel_id": nm,
					"rack_prop": self,
				})
				d_area.position = Vector3(-side * reach * 0.5, total_h * 0.52, front * (0.14 if front > 0.0 else 0.08))
				n3.add_child(d_area)
		elif nm.contains("Panel_Side_"):
			# Seitenwände mit Glasfenster bleiben fest montiert (nur Front- und Hecktüren interaktiv).
			continue


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
	var kind := str(p["kind"])
	var node := node_v as Node3D
	var target := float(p["open"] if opening else p["closed"])

	if kind == "side_panel":
		# Seitenwand gleitet 14 cm heraus & wird abgenommen (kollidiert nie mit Nachbar-Racks!).
		# Klickzone schrumpft beim Abnehmen auf die vordere Seitenleiste, damit das offene Fenster frei bleibt.
		var area_v: Variant = p.get("area", null)
		if is_instance_valid(area_v):
			var sa := area_v as Area3D
			var sh := (sa.get_child(0) as CollisionShape3D).shape as BoxShape3D
			var th := float(p.get("total_h", 2.12))
			sh.size = Vector3(0.10, th * 0.74, 0.14 if opening else 0.74)
			sa.position.z = 0.36 if opening else 0.0
		if not animate or not node.is_inside_tree():
			node.position.x = target
			node.visible = not opening
			p["tween"] = null
			return
		node.visible = true
		var tw := create_tween()
		tw.tween_property(node, "position:x", target, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if opening:
			tw.tween_callback(func() -> void:
				if is_instance_valid(node):
					node.visible = false
			)
		p["tween"] = tw
		SfxManager.play("click", -9.0, 0.90 if opening else 0.72)
		return

	var prop := "rotation:y" if kind == "hinge" else "position:x"
	if not animate or not node.is_inside_tree():
		node.set_indexed(NodePath(prop), target)
		p["tween"] = null
		return
	var tw2 := create_tween()
	tw2.tween_property(node, prop, target, 0.55 if kind == "hinge" else 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	p["tween"] = tw2
	SfxManager.play("click", -10.0, 0.85 if opening else 0.70)


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


func get_panel_prompt(panel_id: String) -> String:
	var lbl := get_panel_label(panel_id)
	var opened := is_panel_open(panel_id)
	if panel_id.contains("Side_"):
		return (tr("[E] %s anbringen") if opened else tr("[E] %s abnehmen")) % lbl
	return (tr("[E] %s schließen") if opened else tr("[E] %s öffnen")) % lbl


func _collect_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		for c in out[i].get_children():
			out.append(c)
		i += 1
	return out


func _extra_float(n: Node, key: String, fallback: float) -> float:
	if n.has_meta("extras"):
		var ex: Variant = n.get_meta("extras")
		if ex is Dictionary and (ex as Dictionary).has(key):
			return float((ex as Dictionary)[key])
	if n.has_meta(key):
		return float(n.get_meta(key))
	return fallback


## Minimaler Fallback, falls rack.glb / rack_pro.glb fehlen sollte.
func _build_procedural_shell_fallback(total_h: float, top_y: float, post_h: float, mid_y: float, is_pro: bool,
		frame_mat: Material, steel_mat: Material, side_mat: Material, _dark_mat: Material, perf_mat: Material, glass: Material) -> void:
	_add_box(self, Vector3(0.0, 0.10, 0.0), Vector3(0.92, 0.14, 0.92), frame_mat)
	_add_box(self, Vector3(0.0, top_y, 0.0), Vector3(0.92, 0.16, 0.92), frame_mat)
	for px in [-0.42, 0.42]:
		for pz in [-0.42, 0.42]:
			_add_box(self, Vector3(float(px), mid_y, float(pz)), Vector3(0.068, post_h, 0.068), frame_mat)
		_add_box(self, Vector3(float(px) * 0.91, mid_y, 0.37), Vector3(0.030, post_h - 0.06, 0.024), steel_mat)
	if is_pro:
		_add_box(self, Vector3(-0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)
		_add_box(self, Vector3(0.448, mid_y, 0.425), Vector3(0.020, post_h - 0.08, 0.022), steel_mat)
	_add_box(self, Vector3(-0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
	_add_box(self, Vector3(0.43, mid_y, 0.0), Vector3(0.016, post_h - 0.22, 0.68), glass)
	_add_box(self, Vector3(0.0, mid_y, -0.43), Vector3(0.78, post_h - 0.08, 0.026), perf_mat)
	_add_box(self, Vector3(0.32, mid_y, -0.452), Vector3(0.082, post_h - 0.22, 0.042), side_mat)
	var _unused_h := total_h
