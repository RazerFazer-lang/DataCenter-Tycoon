class_name UpsProp
extends Node3D
## Detailed 3D UPS Emergency Backup Battery Unit (UPS-1) with 5-segment LED charge meter,
## heavy industrial battery casing and front-top Power Port. Status is shown in the HUD prompt.

## Frontfläche der CEE-Steckdose am Blender-Modell (tools/blender/build_utilities.py, build_ups).
const MODEL_PORT_POS := Vector3(0.0, 1.30, 0.29)
const PROCEDURAL_PORT_POS := Vector3(0.0, 1.32, 0.28)

var ups_id: String = ""
var _ups_data: Dictionary = {}

var _power_port_marker: Node3D
var _bar_mats: Array[StandardMaterial3D] = []
var _status_led_mat: StandardMaterial3D
var _ups_audio: AudioStreamPlayer3D
var _blink_t: float = 0.0


func setup(id: String) -> void:
	ups_id = id
	_build_geometry()
	_ups_audio = AudioStreamPlayer3D.new()
	_ups_audio.position = Vector3(0.0, 0.70, 0.0)
	_ups_audio.stream = SfxManager.get_loop_stream("ups_hum")
	_ups_audio.max_distance = 6.5
	_ups_audio.unit_size = 1.5
	_ups_audio.volume_db = -60.0
	add_child(_ups_audio)


func apply_data(data: Dictionary) -> void:
	_ups_data = data
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	_refresh_visuals()


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else global_position + Vector3(0.0, 1.32, 0.30)


func _process(delta: float) -> void:
	_blink_t += delta
	if _ups_data.is_empty() or _status_led_mat == null:
		return
	var discharging := bool(_ups_data.get("discharging", false))
	var connected := bool(_ups_data.get("connected", false))
	if discharging:
		_status_led_mat.emission = Color(0.92, 0.52, 0.10)
		_status_led_mat.emission_energy_multiplier = 0.95 + 0.45 * sin(_blink_t * 10.0)
	elif connected:
		_status_led_mat.emission = Color(0.22, 0.76, 0.38)
		_status_led_mat.emission_energy_multiplier = 0.75
	else:
		_status_led_mat.emission = Color(0.25, 0.25, 0.28)
		_status_led_mat.emission_energy_multiplier = 0.05

	if _ups_audio != null:
		var gain := SettingsManager.get_effective_fan_gain()
		if (connected or discharging) and gain > 0.005:
			if not _ups_audio.playing:
				_ups_audio.play()
			_ups_audio.volume_db = linear_to_db(gain) - (9.0 if discharging else 17.0)
			_ups_audio.pitch_scale = 1.18 if discharging else 0.96
		elif _ups_audio.playing:
			_ups_audio.stop()


func _refresh_visuals() -> void:
	var charge := clampf(float(_ups_data.get("charge", 0.0)), 0.0, 100.0)
	var connected := bool(_ups_data.get("connected", false))
	var discharging := bool(_ups_data.get("discharging", false))

	for i in range(_bar_mats.size()):
		var threshold := float(i + 1) * 20.0 - 10.0
		var lit := charge >= threshold
		var m := _bar_mats[i]
		if not lit:
			m.emission_energy_multiplier = 0.03
		elif discharging:
			m.emission = Color(0.92, 0.56, 0.14) if charge > 25.0 else Color(0.92, 0.18, 0.14)
			m.emission_energy_multiplier = 0.90
		else:
			m.emission = Color(0.24, 0.78, 0.40)
			m.emission_energy_multiplier = 0.75


func _build_geometry() -> void:
	var custom_m := ModelLoader.instantiate_custom_model("ups")
	var port_pos := PROCEDURAL_PORT_POS
	if custom_m != null:
		add_child(custom_m)
		_bind_model_lights(custom_m)
		port_pos = MODEL_PORT_POS
	else:
		_build_procedural_body()

	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.70, 1.28, 0.62)
	col.shape = sh
	col.position = Vector3(0.0, 0.64, 0.0)
	sb.add_child(col)
	add_child(sb)

	_power_port_marker = Node3D.new()
	_power_port_marker.position = port_pos
	add_child(_power_port_marker)

	# Dedicated Top Power Socket interact area (Contextual 1-Hand Cable Grab!)
	var pp_area := Area3D.new()
	pp_area.collision_layer = 4
	pp_area.collision_mask = 0
	var pp_col := CollisionShape3D.new()
	var pp_sh := BoxShape3D.new()
	pp_sh.size = Vector3(0.36, 0.22, 0.28)
	pp_col.shape = pp_sh
	pp_area.position = Vector3(0.0, 1.30, 0.22)
	pp_area.add_child(pp_col)
	pp_area.set_meta("interact_type", "power_port")
	pp_area.set_meta("entity_id", ups_id)
	add_child(pp_area)

	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var acol := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.74, 1.18, 0.70)
	acol.shape = ash
	area.position = Vector3(0.0, 0.59, 0.02)
	area.add_child(acol)
	area.set_meta("interact_type", "ups_unit")
	area.set_meta("entity_id", ups_id)
	add_child(area)


## ups.glb: Ladeanzeige und Status-LED an eigene Materialkopien binden, damit jede USV einzeln leuchtet.
func _bind_model_lights(model: Node3D) -> void:
	for i in range(5):
		var bm := _bind_model_mat(model, "DCT_U_UpsBar%d" % (i + 1))
		if bm != null:
			_bar_mats.append(bm)
	_status_led_mat = _bind_model_mat(model, "DCT_U_UpsStatus")
	if _bar_mats.size() != 5 or _status_led_mat == null:
		push_warning("ups.glb: Material für Ladeanzeige oder Status-LED fehlt")


func _bind_model_mat(root: Node, mat_name: String) -> StandardMaterial3D:
	var bound: StandardMaterial3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src == null or src.resource_name != mat_name:
				continue
			if bound == null:
				bound = (src.duplicate() as StandardMaterial3D) if src is StandardMaterial3D else StandardMaterial3D.new()
				bound.emission_enabled = true
			mi.set_surface_override_material(s, bound)
	return bound


## Ersatzgehäuse aus Boxen, falls ups.glb fehlt.
func _build_procedural_body() -> void:
	var chassis_mat := MatLib.make_brushed_metal(Color(0.16, 0.18, 0.22), 0.42, 0.58)
	var amber_mat := _mat(Color(0.96, 0.68, 0.12), 0.40, 0.20)
	var dark_mat := _mat(Color(0.09, 0.10, 0.13), 0.68, 0.22)

	# Heavy battery rack base + main steel housing
	_add_box(self, Vector3(0.0, 0.05, 0.0), Vector3(0.72, 0.10, 0.64), dark_mat)
	_add_box(self, Vector3(0.0, 0.66, 0.0), Vector3(0.68, 1.16, 0.58), chassis_mat)
	# Amber high-voltage side accent stripes
	_add_box(self, Vector3(-0.345, 0.66, 0.0), Vector3(0.025, 0.96, 0.46), amber_mat)
	_add_box(self, Vector3(0.345, 0.66, 0.0), Vector3(0.025, 0.96, 0.46), amber_mat)
	# Front recessed battery pack modules
	for row in range(3):
		var ry := 0.26 + float(row) * 0.24
		_add_box(self, Vector3(0.0, ry, 0.295), Vector3(0.56, 0.18, 0.03), dark_mat)
		_add_box(self, Vector3(0.0, ry, 0.312), Vector3(0.46, 0.03, 0.015), amber_mat)

	# 5-Segment Glowing Battery Charge Bar
	_add_box(self, Vector3(0.0, 1.05, 0.295), Vector3(0.56, 0.16, 0.03), dark_mat)
	for s_i in range(5):
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.22, 0.92, 0.48)
		bm.emission_enabled = true
		bm.emission = Color(0.22, 0.92, 0.48)
		bm.emission_energy_multiplier = 0.1
		_bar_mats.append(bm)
		_add_box(self, Vector3(-0.20 + float(s_i) * 0.095, 1.05, 0.312), Vector3(0.072, 0.095, 0.018), bm)

	# Status LED
	_status_led_mat = StandardMaterial3D.new()
	_status_led_mat.albedo_color = Color(0.2, 1.0, 0.45)
	_status_led_mat.emission_enabled = true
	_status_led_mat.emission = Color(0.2, 1.0, 0.45)
	_status_led_mat.emission_energy_multiplier = 0.2
	_add_box(self, Vector3(0.24, 1.05, 0.314), Vector3(0.045, 0.095, 0.018), _status_led_mat)

	# Realistic Matte Yellow Industrial IEC Power Socket on Top
	_add_box(self, Vector3(0.0, 1.27, 0.20), Vector3(0.26, 0.075, 0.13), dark_mat)
	var pmat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	_add_box(self, Vector3(0.0, 1.29, 0.22), Vector3(0.18, 0.055, 0.09), pmat)


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
