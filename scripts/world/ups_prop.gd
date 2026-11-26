class_name UpsProp
extends Node3D
## Notstrom in drei Größen (tools/blender/build_paket_a.py): Display mit Ladestand, Last und Restzeit,
## Ladebalken, Modul-LEDs nach Akku-Zustand, drehende Lüfter, Umschalt-Klack, Brummen und Alarm.

const MODELS := {"ups": "ups_small", "ups_cabinet": "ups_cabinet", "ups_container": "ups_container"}
const SIZES := {"ups": Vector3(0.50, 0.95, 0.64), "ups_cabinet": Vector3(0.82, 2.04, 0.84), "ups_container": Vector3(2.04, 2.28, 1.34)}
## Öffnung der CEE-Dose auf der Front.
const PORTS := {"ups": Vector3(0.0, 0.13, 0.325), "ups_cabinet": Vector3(0.0, 0.17, 0.422), "ups_container": Vector3(0.0, 0.22, 0.68)}
## Displaymitte und Breite.
const SCREENS := {"ups": [Vector3(0.0, 0.788, 0.3160), 0.27], "ups_cabinet": [Vector3(0.0, 1.868, 0.4150), 0.39], "ups_container": [Vector3(0.415, 1.528, 0.6650), 0.39]}

var ups_id: String = ""
var ups_type: String = "ups"
var _ups_data: Dictionary = {}

var _power_port_marker: Node3D
var _bar_mats: Array[StandardMaterial3D] = []
var _mod_mats: Array[StandardMaterial3D] = []
var _status_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _beacon_light: OmniLight3D
var _screen: Label3D
var _fans: Array = [] # [Knoten, Achse]
var _hum: AudioStreamPlayer3D
var _shot: AudioStreamPlayer3D
var _alarm: AudioStreamPlayer3D
var _heat: CPUParticles3D
var _sparks: CPUParticles3D
var _flash: OmniLight3D
var _t: float = 0.0
var _alarm_accum: float = 0.0
var _fan_speed: float = 0.0
var _was_discharging: bool = false
var _was_tripped: bool = false
var _seen_data: bool = false
var _screen_accum: float = 1.0


func setup(id: String, p_type: String = "ups") -> void:
	ups_id = id
	ups_type = p_type if MODELS.has(p_type) else "ups"
	_build_geometry()
	var big := 1.0 if ups_type == "ups" else (1.4 if ups_type == "ups_cabinet" else 2.0)
	_hum = _make_player("ups_hum", 5.0 + 3.0 * big, 1.2 * big)
	_hum.volume_db = -60.0
	_shot = _make_player("", 8.0 + 4.0 * big, 2.0 * big)
	_alarm = _make_player("ups_alarm", 14.0, 2.6)


func _make_player(loop_name: String, dist: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.position = Vector3(0.0, SIZES[ups_type].y * 0.6, 0.0)
	if loop_name == "ups_hum":
		p.stream = SfxManager.get_loop_stream("ups_hum")
	elif loop_name != "":
		p.stream = SfxManager.get_sound_stream(loop_name)
	p.max_distance = dist
	p.unit_size = unit
	add_child(p)
	return p


func apply_data(data: Dictionary) -> void:
	_ups_data = data
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	var dis := bool(data.get("discharging", false))
	var trip := bool(data.get("tripped", false))
	if _seen_data:
		if dis != _was_discharging:
			_play_shot("ups_transfer", -2.0, 1.0 if dis else 0.86)
			_burst(0.55 if dis else 0.25)
		if trip and not _was_tripped:
			_play_shot("breaker_trip", -2.0, 0.9)
			_burst(1.4)
			if _sparks != null:
				_sparks.restart()
				_sparks.emitting = true
	_was_discharging = dis
	_was_tripped = trip
	_seen_data = true
	_refresh_leds()


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else global_position + Vector3(0.0, 0.15, 0.3)


func get_socket_world_positions() -> Array[Vector3]:
	var base := get_power_port_global_pos()
	var side := global_transform.basis.x * 0.026
	var out: Array[Vector3] = [base - side, base + side]
	return out


func _play_shot(sfx: String, db: float, pitch: float) -> void:
	var s := SfxManager.get_sound_stream(sfx)
	var gain := SettingsManager.get_effective_sfx_gain()
	if s == null or gain <= 0.005:
		return
	_shot.stream = s
	_shot.volume_db = db + linear_to_db(gain)
	_shot.pitch_scale = pitch
	_shot.play()


## Kurzer Lichtbogen beim Umschalten.
func _burst(energy: float) -> void:
	if _flash == null or SettingsManager.graphics_quality < 1:
		return
	_flash.visible = true
	_flash.light_energy = energy * 2.2
	var tw := create_tween()
	tw.tween_property(_flash, "light_energy", 0.0, 0.22)
	tw.tween_callback(func(): _flash.visible = false)


func _process(delta: float) -> void:
	_t += delta
	if _ups_data.is_empty():
		return
	var dis := bool(_ups_data.get("discharging", false))
	var conn := bool(_ups_data.get("connected", false))
	var trip := bool(_ups_data.get("tripped", false))
	var charge := float(_ups_data.get("charge", 0.0))
	var charging := conn and not dis and GameState.breaker_on and charge < 99.5

	# Lüfter: im Netzbetrieb ruhig, beim Laden und Entladen schneller
	var want := 0.0
	if not trip:
		want = 26.0 if dis else (15.0 if charging else (5.0 if conn else 0.0))
	_fan_speed = lerpf(_fan_speed, want, clampf(delta * 1.4, 0.0, 1.0))
	if _fan_speed > 0.05:
		for f in _fans:
			if is_instance_valid(f[0]):
				(f[0] as Node3D).rotate_object_local(f[1], delta * _fan_speed)

	if _status_mat != null:
		if trip:
			_set_mat(_status_mat, Color(0.95, 0.10, 0.06), 2.2 if fmod(_t, 0.5) < 0.25 else 0.05)
		elif dis:
			_set_mat(_status_mat, Color(0.98, 0.55, 0.08), 1.2 + 0.7 * sin(_t * 9.0))
		elif charging:
			_set_mat(_status_mat, Color(0.18, 0.60, 1.0), 0.8 + 0.5 * sin(_t * 2.4))
		elif conn:
			_set_mat(_status_mat, Color(0.18, 0.85, 0.36), 1.1)
		else:
			_set_mat(_status_mat, Color(0.2, 0.2, 0.2), 0.02)
	if charging and not _bar_mats.is_empty():
		# Laufendes Segment zeigt das Laden
		var full := int(charge / 100.0 * float(_bar_mats.size()))
		var idx := clampi(full, 0, _bar_mats.size() - 1)
		_bar_mats[idx].emission_energy_multiplier = 0.15 + 1.1 * (0.5 + 0.5 * sin(_t * 4.0))
	if _beacon_mat != null:
		var on := (dis or trip) and fmod(_t, 0.8) < 0.4
		_set_mat(_beacon_mat, Color(1.0, 0.30, 0.04) if trip else Color(1.0, 0.55, 0.08), 3.0 if on else 0.06)
		_beacon_light.visible = on
	if _heat != null:
		_heat.emitting = (dis or charging) and SettingsManager.graphics_quality >= 1

	_screen_accum += delta
	if _screen_accum >= 0.5:
		_screen_accum = 0.0
		_refresh_screen(dis, conn, trip, charging, charge)

	var gain := SettingsManager.get_effective_fan_gain()
	if (conn or dis) and not trip and gain > 0.005:
		if not _hum.playing:
			_hum.play()
		_hum.volume_db = linear_to_db(gain) - (5.0 if dis else (10.0 if charging else 16.0))
		_hum.pitch_scale = (1.16 if dis else 0.96) * (1.0 if ups_type == "ups" else (0.82 if ups_type == "ups_cabinet" else 0.66))
	elif _hum.playing:
		_hum.stop()
	# Alarm: alle 4 s im Batteriebetrieb, hektisch unter 20 %
	if dis or trip:
		_alarm_accum += delta
		var every := 0.9 if trip or charge < 10.0 else (1.6 if charge < 20.0 else 4.0)
		if _alarm_accum >= every:
			_alarm_accum = 0.0
			var sg := SettingsManager.get_effective_sfx_gain()
			if sg > 0.005:
				_alarm.volume_db = -6.0 + linear_to_db(sg)
				_alarm.pitch_scale = 1.0 if ups_type == "ups" else 0.88
				_alarm.play()
	else:
		_alarm_accum = 3.2


func _set_mat(m: StandardMaterial3D, col: Color, energy: float) -> void:
	m.emission = col
	m.emission_energy_multiplier = energy


func _refresh_screen(dis: bool, conn: bool, trip: bool, charging: bool, charge: float) -> void:
	if _screen == null:
		return
	if not conn and not dis:
		_screen.text = tr("KEIN NETZ") if charge > 0.2 else ""
		_screen.modulate = Color(0.45, 0.50, 0.55)
		return
	var head := tr("NETZBETRIEB")
	var col := Color(0.50, 0.95, 0.62)
	if trip:
		head = tr("ÜBERLAST - AUS")
		col = Color(1.0, 0.32, 0.26)
	elif dis:
		head = tr("BATTERIEBETRIEB")
		col = Color(1.0, 0.72, 0.28) if charge >= 20.0 else Color(1.0, 0.36, 0.28)
	elif charging:
		head = tr("LÄDT")
		col = Color(0.50, 0.80, 1.0)
	var line2 := "%.0f %%   %d Wh" % [charge, int(GameState.get_ups_stored_wh(_ups_data))]
	var line3 := ""
	if dis:
		line3 = tr("%d W   noch %d min") % [GameState.total_watts, GameState.get_ups_runtime_minutes()]
	elif charging:
		line3 = tr("%d W Ladung") % int(GameState.get_ups_spec(_ups_data)["charge_w"])
	else:
		line3 = tr("bis %d W   Akku %d %%") % [int(GameState.get_ups_spec(_ups_data)["out"]), roundi(GameState.get_ups_health(_ups_data))]
	_screen.text = "%s\n%s\n%s" % [head, line2, line3]
	_screen.modulate = col


func _refresh_leds() -> void:
	var charge := clampf(float(_ups_data.get("charge", 0.0)), 0.0, 100.0)
	var dis := bool(_ups_data.get("discharging", false))
	var trip := bool(_ups_data.get("tripped", false))
	for i in range(_bar_mats.size()):
		var lit := charge >= (float(i) + 0.5) * 100.0 / float(_bar_mats.size())
		var col := Color(0.20, 0.86, 0.38)
		if trip:
			col = Color(0.92, 0.14, 0.10)
		elif dis:
			col = Color(0.95, 0.58, 0.12) if charge > 20.0 else Color(0.95, 0.16, 0.10)
		_set_mat(_bar_mats[i], col, 0.95 if lit else 0.02)
	# Modul-LEDs zeigen den Akku-Zustand: grün, gelb, rot
	var health := GameState.get_ups_health(_ups_data)
	for i in range(_mod_mats.size()):
		var lim := 100.0 - float(i) * 60.0 / float(maxi(1, _mod_mats.size()))
		var c := Color(0.18, 0.86, 0.38) if health >= lim - 8.0 else (Color(0.96, 0.66, 0.12) if health >= lim - 24.0 else Color(0.95, 0.14, 0.10))
		_set_mat(_mod_mats[i], c, 0.9 if bool(_ups_data.get("connected", false)) else 0.05)


func _build_geometry() -> void:
	var size: Vector3 = SIZES[ups_type]
	var mdl := ModelLoader.instantiate_custom_model(str(MODELS[ups_type]))
	if mdl != null:
		add_child(mdl)
		_bind(mdl)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position.y = size.y * 0.5
		mi.material_override = MatLib.make_brushed_metal(Color(0.20, 0.22, 0.25), 0.45, 0.4)
		add_child(mi)

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	sb.add_child(col)
	add_child(sb)

	var port: Vector3 = PORTS[ups_type]
	_power_port_marker = Node3D.new()
	_power_port_marker.position = port
	add_child(_power_port_marker)
	_add_area(port, Vector3(0.30, 0.28, 0.22), "power_port")
	_add_area(Vector3(0.0, size.y * 0.56, 0.0), Vector3(size.x + 0.06, size.y * 0.86, size.z + 0.08), "ups_unit")

	var sc: Array = SCREENS[ups_type]
	_screen = Label3D.new()
	_screen.font_size = 34
	_screen.pixel_size = float(sc[1]) / 400.0
	_screen.outline_size = 0
	_screen.shaded = false
	_screen.double_sided = false
	_screen.line_spacing = -4.0
	_screen.position = sc[0]
	_screen.visibility_range_end = 9.0
	add_child(_screen)

	_flash = OmniLight3D.new()
	_flash.position = Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.2)
	_flash.light_color = Color(0.70, 0.84, 1.0)
	_flash.omni_range = 2.6
	_flash.light_energy = 0.0
	_flash.visible = false
	add_child(_flash)
	if ups_type == "ups_container":
		_beacon_light = OmniLight3D.new()
		_beacon_light.position = Vector3(0.0, size.y + 0.15, 0.30)
		_beacon_light.light_color = Color(1.0, 0.52, 0.10)
		_beacon_light.omni_range = 4.5
		_beacon_light.light_energy = 1.6
		_beacon_light.visible = false
		add_child(_beacon_light)
	_heat = _make_heat(size)
	add_child(_heat)
	_sparks = _make_sparks(size)
	add_child(_sparks)


func _add_area(pos: Vector3, size: Vector3, interact_type: String) -> void:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	area.position = pos
	area.add_child(col)
	area.set_meta("interact_type", interact_type)
	area.set_meta("entity_id", ups_id)
	add_child(area)


## Warme Abluft über dem Gerät.
func _make_heat(size: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, size.y + 0.05, -0.05)
	p.amount = 10
	p.lifetime = 2.0
	p.preprocess = 2.0
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size.x * 0.30, 0.01, size.z * 0.25)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.0, 0.12, 0.0)
	p.initial_velocity_min = 0.10
	p.initial_velocity_max = 0.24
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.28, 0.28)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = RealisticVfx.get_smoke_puff_texture()
	qm.material = m
	p.mesh = qm
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.9, 0.95, 0.0), Color(0.9, 0.9, 0.95, 0.06), Color(0.9, 0.9, 0.95, 0.0)])
	p.color_ramp = g
	p.visibility_range_end = 12.0
	return p


func _make_sparks(size: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, size.y * 0.62, size.z * 0.5)
	p.amount = 26
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.direction = Vector3(0.0, 0.4, 1.0)
	p.spread = 55.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0
	var sm := BoxMesh.new()
	sm.size = Vector3(0.006, 0.006, 0.022)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.82, 0.42)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.30)
	m.emission_energy_multiplier = 3.0
	sm.material = m
	p.mesh = sm
	return p


## LED-Materialien je Gerät kopieren und Lüfter merken.
func _bind(model: Node) -> void:
	var by_name := {}
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var nm := String(n.name)
		if nm.begins_with("FanX_") or nm.begins_with("Fan_"):
			MeshMerger.no_shadow(n)
		if nm.begins_with("FanX_"):
			_fans.append([n, Vector3.RIGHT])
		elif nm.begins_with("Fan_"):
			_fans.append([n, Vector3.BACK if ups_type == "ups" else Vector3.UP])
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if not (src is StandardMaterial3D):
				continue
			var rn := src.resource_name
			if not (rn.begins_with("UPS_Bar") or rn.begins_with("UPS_Mod") or rn == "UPS_Status" or rn == "UPS_Beacon"):
				continue
			if not by_name.has(rn):
				var d := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.emission_enabled = true
				d.albedo_color = d.albedo_color.darkened(0.75)
				by_name[rn] = d
			mi.set_surface_override_material(s, by_name[rn])
	for i in range(10):
		if by_name.has("UPS_Bar%d" % i):
			_bar_mats.append(by_name["UPS_Bar%d" % i])
		if by_name.has("UPS_Mod%d" % i):
			_mod_mats.append(by_name["UPS_Mod%d" % i])
	_status_mat = by_name.get("UPS_Status")
	_beacon_mat = by_name.get("UPS_Beacon")
