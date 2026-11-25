class_name DecorProp
extends Node3D
## Frei platzierbare Einrichtung (Modelle aus tools/blender/build_paket_c.py, Maße in DecorSpec):
## drei Lagerregale, ESD-Werkbank, Ersatzteil-Schrank, Kaltgang-Portal, Automat, Kamera-Stele, Sofa,
## Wasserspender, Werkzeugwagen, Luftentfeuchter, Leuchtschild sowie Strom- und LAN-Leisten.
## Was man damit tun kann, steht in DecorManager.

const GATE_OPEN_DIST := 1.9
const GATE_SLIDE := 0.50

var decor_id: String = ""
var item_type: String = ""
var _socket_local_positions: Array[Vector3] = []
var _temp_lbl: Label3D
var _cctv_cam: Node3D
var _anim_t: float = 0.0
var _wall: bool = false
var _on: bool = true
var _tripped: bool = false
var _switch_node: Node3D
var _switch_mat: StandardMaterial3D
var _led_mats: Array[StandardMaterial3D] = []
var _act_mats: Array[StandardMaterial3D] = []
var _disp: Label3D
var _strip_accum: float = 1.0
## Je Buchse: 0 leer, 1 gesteckt, 2 gesteckt und in Betrieb.
var _port_state: PackedInt32Array = PackedInt32Array()

var _shelf: ShelfProp
var _bench: WorkbenchProp
var _doors: Array[Node3D] = []
var _door_base: Array[float] = []
var _door_t := 0.0
var _door_want := false
var _fans: Array[Node3D] = []
var _tank: Node3D
var _glow: OmniLight3D
var _live_mats: Dictionary = {}
var _sign_lbl: Label3D
var _drawers: Array[Node3D] = []
var _info_lbl: Label3D
var _slow := 0.0


func setup(did: String, itype: String, data: Dictionary) -> void:
	decor_id = did
	item_type = itype
	_apply_pose(data)
	match itype:
		"prop_power_strip":
			_build_power_strip()
		"prop_lan_strip":
			_build_lan_strip()
		"prop_esd_workbench":
			_build_esd_workbench()
		"prop_cold_aisle_gate":
			_build_gate()
		_:
			if ShelfSpec.is_shelf(itype):
				_build_shelf()
			else:
				_build_generic()
	apply_data(data)


## Am Boden liegend oder an der Wand (Leisten: Oberseite zeigt dann in den Raum).
func _apply_pose(data: Dictionary) -> void:
	position = data.get("pos", position) as Vector3
	_wall = bool(data.get("wall", false))
	var yaw := Basis(Vector3.UP, float(data.get("rot_y", 0.0)))
	basis = yaw * Basis(Vector3.RIGHT, PI * 0.5) if _wall else yaw


func is_on_wall() -> bool:
	return _wall


func get_socket_world_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for lp in _socket_local_positions:
		out.append(to_global(lp))
	return out


func get_port_world_pos() -> Vector3:
	if not _socket_local_positions.is_empty():
		return to_global(_socket_local_positions[0])
	return global_position + Vector3(0.0, 0.06, 0.0)


func apply_data(data: Dictionary) -> void:
	_apply_pose(data)
	_on = bool(data.get("on", true))
	_tripped = bool(data.get("tripped", false))
	if _shelf != null:
		_shelf.sync()
	match item_type:
		"prop_logo_sign":
			_apply_sign(data)
		"prop_dehumidifier":
			if _tank != null:
				_tank.scale.y = maxf(0.02, float(data.get("tank", 0.0)))
				_tank.visible = float(data.get("tank", 0.0)) > 0.01
		"prop_tool_cart":
			if _info_lbl != null:
				_info_lbl.text = "%d/%d" % [DecorManager.kit_count(data), DecorManager.TOOL_CART_SLOTS]


func _process(delta: float) -> void:
	_anim_t += delta
	if _cctv_cam != null:
		_cctv_cam.rotation_degrees.y = sin(_anim_t * 0.75) * 38.0
	if _switch_node != null and GameState.is_active:
		_process_strip(delta)
	if not _doors.is_empty():
		_process_gate(delta)
	for f in _fans:
		if GameState.is_active and DecorManager.is_dehum_running(GameState.decor_items.get(decor_id, {})):
			f.rotate_object_local(Vector3.BACK, delta * 9.0)
	_slow += delta
	if _slow < 0.5:
		return
	_slow = 0.0
	if not GameState.is_active:
		return
	var power := DecorManager.has_power()
	if _temp_lbl != null:
		_temp_lbl.text = "%.1f °C" % GameState.room_temp if power else ""
	if _glow != null and item_type != "prop_logo_sign":
		_glow.visible = power
	for k in _live_mats.keys():
		(_live_mats[k] as StandardMaterial3D).emission_energy_multiplier = float((_live_mats[k] as StandardMaterial3D).get_meta("e", 1.0)) if power else 0.0
	if item_type == "prop_logo_sign":
		_apply_sign(GameState.decor_items.get(decor_id, {}))


# ---------------------------------------------------------------- Bausteine

func _model() -> Node3D:
	var mdl := ModelLoader.instantiate_custom_model(str(DecorSpec.MODELS[item_type]))
	if mdl != null:
		add_child(mdl)
		_bind_live(mdl)
	else:
		var s: Vector3 = DecorSpec.SIZES[item_type]
		_box(self, Vector3(0.0, s.y * 0.5, 0.0), s, _mat(Color(0.22, 0.25, 0.30), 0.4, 0.5))
	return mdl


## Leuchtende Materialien (Name beginnt mit LIVE_) je Stück eigenständig machen, damit sie mit dem Strom aus- und angehen.
func _bind_live(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null or not src.resource_name.begins_with("LIVE_"):
				continue
			if not _live_mats.has(src.resource_name):
				var d := src.duplicate() as StandardMaterial3D
				d.resource_name = src.resource_name
				d.set_meta("e", d.emission_energy_multiplier)
				_live_mats[src.resource_name] = d
			mi.set_surface_override_material(s, _live_mats[src.resource_name])


func _area(itype: String, pos: Vector3, sz: Vector3) -> void:
	var area := _make_interact_area(sz, {"interact_type": itype, "decor_id": decor_id, "entity_id": decor_id, "item_type": item_type})
	area.position = pos
	add_child(area)


func _light(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	return l


func _small_label(pos: Vector3, px: int, size_m: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.font_size = px
	l.pixel_size = size_m
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.modulate = col
	l.position = pos
	l.visibility_range_end = 10.0
	add_child(l)
	return l


# ---------------------------------------------------------------- Regale

func _build_shelf() -> void:
	_shelf = ShelfProp.new()
	add_child(_shelf)
	_shelf.setup(decor_id, item_type)
	var s: Vector3 = DecorSpec.SIZES[item_type]
	# Nur hinten ein durchgehender Körper: die Fächer davor bleiben frei anvisierbar.
	_add_collider(Vector3(0.0, s.y * 0.5, -s.z * 0.18), Vector3(s.x, s.y, s.z * 0.62))
	for sx in [-0.5, 0.5]:
		_add_collider(Vector3((s.x - 0.06) * float(sx), s.y * 0.5, 0.0), Vector3(0.06, s.y, s.z))


# ---------------------------------------------------------------- ESD-Werkbank (echte zweite Werkbank)

func _build_esd_workbench() -> void:
	_bench = WorkbenchProp.new()
	add_child(_bench)
	_bench.setup(decor_id, str(DecorSpec.MODELS[item_type]))
	_add_collider(Vector3(0.0, 0.44, 0.0), Vector3(1.58, 0.88, 0.82))
	_bind_live(_bench)


# ---------------------------------------------------------------- Kaltgang-Portal mit Automatiktür

func _build_gate() -> void:
	var mdl := _model()
	if mdl != null:
		for n in ["Door_L", "Door_R"]:
			var dn := mdl.find_child(str(n), true, false) as Node3D
			if dn != null:
				_doors.append(dn)
				_door_base.append(dn.position.x)
	_temp_lbl = _small_label(Vector3(0.0, 2.485, 0.1335), 30, 0.0024, Color(0.58, 0.90, 1.0))
	for gx in [-1.05, 1.05]:
		_add_collider(Vector3(float(gx), 1.28, 0.0), Vector3(0.18, 2.56, 0.22))
		_area("decor_info", Vector3(float(gx), 1.28, 0.0), Vector3(0.28, 2.5, 0.34))


func _process_gate(delta: float) -> void:
	var want := false
	var nodes := get_tree().get_nodes_in_group("player_body")
	for p in nodes:
		var lp := to_local((p as Node3D).global_position)
		if absf(lp.x) < 1.15 and absf(lp.z) < GATE_OPEN_DIST:
			want = true
			break
	if not DecorManager.has_power():
		want = true
	if want != _door_want:
		_door_want = want
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_to(global_position) < 12.0 and DecorManager.has_power():
			SfxManager.play("glass_door", -12.0, 1.1 if want else 0.95)
	_door_t = move_toward(_door_t, 1.0 if want else 0.0, delta * 1.9)
	var e := smoothstep(0.0, 1.0, _door_t)
	for i in _doors.size():
		_doors[i].position.x = _door_base[i] + (-GATE_SLIDE if i == 0 else GATE_SLIDE) * e


# ---------------------------------------------------------------- Alles andere

func _build_generic() -> void:
	var mdl := _model()
	var s: Vector3 = DecorSpec.SIZES.get(item_type, Vector3(0.6, 1.0, 0.6))
	var use := "decor_use"
	match item_type:
		"prop_parts_cabinet":
			use = "parts_cabinet"
			_glow = _light(Vector3(0.0, 1.55, 0.10), Color(1.0, 0.97, 0.90), 0.35, 1.2)
		"prop_vending_lounge":
			_glow = _light(Vector3(-0.10, 1.25, 0.62), Color(0.92, 0.96, 1.0), 0.45, 2.2)
		"prop_cctv_monitor":
			use = "decor_info"
			_temp_lbl = _small_label(Vector3(0.0, 1.655, 0.1215), 30, 0.0022, Color(0.75, 0.95, 1.0))
			_cctv_cam = Node3D.new()
			_cctv_cam.position = Vector3(0.0, 2.40, 0.06)
			add_child(_cctv_cam)
			_cctv_cam.add_to_group("cctv_cam")
			_cctv_cam.set_meta("decor_id", decor_id)
			var head := ModelLoader.instantiate_custom_model("decor_cctv_cam_head")
			if head != null:
				_cctv_cam.add_child(head)
		"prop_logo_sign":
			_sign_lbl = _small_label(Vector3(0.0, 0.0, 0.066), 64, 0.0030, Color.WHITE)
			_sign_lbl.visibility_range_end = 40.0
			_glow = _light(Vector3(0.0, 0.0, 0.45), Color(0.3, 0.6, 1.0), 0.7, 2.6)
		"prop_dehumidifier":
			if mdl != null:
				_tank = mdl.find_child("Tank_Level", true, false) as Node3D
				for f in mdl.find_children("Fan_*", "Node3D", true, false):
					if not (f.get_parent() is MeshInstance3D):
						_fans.append(f as Node3D)
		"prop_tool_cart":
			_info_lbl = _small_label(Vector3(0.255, 0.925, 0.2565), 22, 0.0016, Color(0.95, 0.95, 0.92))
	if item_type == "prop_logo_sign":
		_area(use, Vector3(0.0, 0.0, 0.06), Vector3(s.x, s.y, 0.2))
		return
	_add_collider(Vector3(0.0, s.y * 0.5, 0.0), s)
	if item_type == "prop_sofa":
		_area(use, Vector3(0.0, 0.45, 0.08), Vector3(s.x, 0.9, s.z))
	else:
		_area(use, Vector3(0.0, s.y * 0.5, 0.06), Vector3(s.x + 0.04, s.y, s.z + 0.10))


func _apply_sign(d: Dictionary) -> void:
	if _sign_lbl == null:
		return
	var on := DecorManager.has_power() and not bool(d.get("off", false))
	var col: Color = DecorManager.SIGN_COLORS[clampi(int(d.get("color_i", 0)), 0, DecorManager.SIGN_COLORS.size() - 1)]
	var txt: String = GameState.current_save_name.to_upper().left(22)
	if _sign_lbl.text != txt:
		_sign_lbl.text = txt
		var w := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		_sign_lbl.pixel_size = minf(0.0036, 1.56 / maxf(1.0, w))
	_sign_lbl.modulate = col.lerp(Color.WHITE, 0.55) if on else Color(0.35, 0.37, 0.40)
	_glow.visible = on
	_glow.light_color = col
	var m: StandardMaterial3D = _live_mats.get("LIVE_Sign")
	if m != null:
		m.emission = col
		m.set_meta("e", 2.4 if on else 0.0)
		m.emission_energy_multiplier = 2.4 if on else 0.0


# ---------------------------------------------------------------- 7. Platzierbare 6-fach Industrie-Stromleiste

func _build_power_strip() -> void:
	var mdl := ModelLoader.instantiate_custom_model("power_strip")
	if mdl != null:
		add_child(mdl)
		_bind_strip(mdl, "PS_Switch", "PS_Led", "", 6)
		_add_strip_display(Vector3(0.2660, 0.0538, 0.0), 0.046)
	else:
		_box(self, Vector3(0.0, 0.025, 0.0), Vector3(0.60, 0.050, 0.110), _mat(Color(0.72, 0.75, 0.79), 0.35, 0.80))
		_box(self, Vector3(0.0, 0.052, 0.0), Vector3(0.54, 0.008, 0.082), _mat(Color(0.14, 0.16, 0.19), 0.55, 0.20))

	_socket_local_positions.clear()
	for i in range(6):
		var sx := -0.20 + float(i) * 0.08
		var spos := Vector3(sx, 0.058, 0.0)
		_socket_local_positions.append(spos)
		var area := _make_interact_area(Vector3(0.074, 0.095, 0.135), {
			"interact_type": "power_port",
			"entity_id": decor_id,
			"slot_idx": i,
		})
		area.position = Vector3(sx, 0.068, 0.0)
		add_child(area)
	_add_collider(Vector3(0.0, 0.028, 0.0), Vector3(0.66, 0.056, 0.13))
	_add_info_area(Vector3(0.30, 0.05, 0.0), Vector3(0.10, 0.11, 0.16))
	_add_switch_area(Vector3(-0.275, 0.06, 0.0), Vector3(0.062, 0.12, 0.16))


# ---------------------------------------------------------------- 8. Platzierbare 8-Port LAN-Verteilerleiste

func _build_lan_strip() -> void:
	var mdl := ModelLoader.instantiate_custom_model("lan_strip")
	if mdl != null:
		add_child(mdl)
		_bind_strip(mdl, "LS_Switch", "LS_Link", "LS_Act", 8)
		_add_strip_display(Vector3(0.2580, 0.0512, 0.0), 0.044)
	else:
		_box(self, Vector3(0.0, 0.025, 0.0), Vector3(0.56, 0.048, 0.125), _mat(Color(0.16, 0.19, 0.24), 0.38, 0.75))
		_box(self, Vector3(0.0, 0.050, 0.054), Vector3(0.54, 0.005, 0.010), _mat(Color(0.14, 0.46, 0.86), 0.35, 0.15))

	_socket_local_positions.clear()
	for i in range(8):
		var px := -0.21 + float(i) * 0.06
		var ppos := Vector3(px, 0.056, 0.0)
		_socket_local_positions.append(ppos)
		var area := _make_interact_area(Vector3(0.056, 0.095, 0.140), {
			"interact_type": "net_port",
			"entity_id": decor_id,
			"slot_idx": i,
		})
		area.position = Vector3(px, 0.066, 0.0)
		add_child(area)
	_add_collider(Vector3(0.0, 0.028, 0.0), Vector3(0.62, 0.056, 0.14))
	_add_info_area(Vector3(0.27, 0.05, 0.0), Vector3(0.08, 0.11, 0.17))
	_add_switch_area(Vector3(-0.268, 0.06, 0.0), Vector3(0.050, 0.12, 0.17))


# ---------------------------------------------------------------- Helfer

func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_collider(pos: Vector3, sz: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	add_child(body)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	col.shape = bs
	body.add_child(col)


func _add_switch_area(pos: Vector3, sz: Vector3) -> void:
	var area := _make_interact_area(sz, {"interact_type": "strip_switch", "decor_id": decor_id})
	area.position = pos
	add_child(area)


## Wippe und LEDs an eigene Materialkopien binden, damit jede Leiste einzeln leuchtet.
func _bind_strip(mdl: Node3D, sw_name: String, led_prefix: String, act_prefix: String, count: int) -> void:
	_switch_node = mdl.find_child("Switch", true, false) as Node3D
	_led_mats.clear()
	_act_mats.clear()
	var found := {}
	for n in mdl.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if not (src is StandardMaterial3D):
				continue
			var rn := src.resource_name
			if rn != sw_name and not rn.begins_with(led_prefix) and (act_prefix == "" or not rn.begins_with(act_prefix)):
				continue
			if not found.has(rn):
				var d := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				d.emission_enabled = true
				d.albedo_color = d.albedo_color.darkened(0.7)
				found[rn] = d
			mi.set_surface_override_material(s, found[rn])
	_switch_mat = found.get(sw_name)
	for i in range(count):
		if found.has(led_prefix + str(i)):
			_led_mats.append(found[led_prefix + str(i)])
		if act_prefix != "" and found.has(act_prefix + str(i)):
			_act_mats.append(found[act_prefix + str(i)])


func _add_strip_display(pos: Vector3, width: float) -> void:
	_disp = Label3D.new()
	_disp.font_size = 30
	_disp.pixel_size = width / 118.0
	_disp.outline_size = 0
	_disp.shaded = false
	_disp.double_sided = false
	_disp.line_spacing = -5.0
	_disp.position = pos
	_disp.rotation_degrees.x = -90.0
	_disp.visibility_range_end = 5.0
	add_child(_disp)


func _process_strip(delta: float) -> void:
	var is_power := item_type == "prop_power_strip"
	_strip_accum += delta
	if _strip_accum >= 0.4:
		_strip_accum = 0.0
		_refresh_strip_state(is_power)
	# Wippe kippt sichtbar, leuchtet nur eingeschaltet
	var want := deg_to_rad(9.0) if _on else deg_to_rad(-9.0)
	_switch_node.rotation.x = lerpf(_switch_node.rotation.x, want, clampf(delta * 18.0, 0.0, 1.0))
	if _switch_mat != null:
		var e := 1.3 if _on else 0.02
		if _tripped:
			e = 1.6 if fmod(_anim_t, 0.6) < 0.3 else 0.02
		_switch_mat.emission_energy_multiplier = e
	for i in range(_led_mats.size()):
		var st := _port_state[i] if i < _port_state.size() else 0
		var m := _led_mats[i]
		if _tripped:
			m.emission = Color(0.95, 0.10, 0.06)
			m.emission_energy_multiplier = 1.2 if fmod(_anim_t, 0.6) < 0.3 else 0.02
		elif not _on or st == 0:
			m.emission_energy_multiplier = 0.02
		else:
			m.emission = Color(0.12, 0.92, 0.34) if st == 2 else Color(0.98, 0.64, 0.10)
			m.emission_energy_multiplier = 1.3
	for i in range(_act_mats.size()):
		var st2 := _port_state[i] if i < _port_state.size() else 0
		var busy := _on and st2 == 2 and sin(_anim_t * (17.0 + float(i) * 5.3)) * cos(_anim_t * 7.1 + float(i)) > 0.05
		_act_mats[i].emission_energy_multiplier = 1.4 if busy else 0.02


func _refresh_strip_state(is_power: bool) -> void:
	var ctype := "power" if is_power else "network"
	var count := 6 if is_power else 8
	_port_state.resize(count)
	_port_state.fill(0)
	var live := 0
	var smap: Dictionary = GameState.get_cable_slot_map(ctype, decor_id)
	for cid in smap.keys():
		var idx := int(smap[cid])
		if idx < 0 or idx >= count or not GameState.cables.has(cid):
			continue
		var c: Dictionary = GameState.cables[cid]
		var other := str(c["to_id"]) if str(c["from_id"]) == decor_id else str(c["from_id"])
		var ok := true
		if GameState.racks.has(other):
			ok = bool(GameState.racks[other].get("powered" if is_power else "networked", false))
		elif GameState.coolers.has(other):
			ok = bool(GameState.coolers[other].get("powered", false))
		elif GameState.ups_units.has(other):
			ok = bool(GameState.ups_units[other].get("connected", false))
		elif is_power:
			ok = GameState.breaker_on or GameState.ups_backup_active
		_port_state[idx] = 2 if ok and _on else 1
		if _port_state[idx] == 2:
			live += 1
	if _disp == null:
		return
	if _tripped:
		_disp.text = tr("ÜBER-\nLAST")
		_disp.modulate = Color(1.0, 0.30, 0.24)
	elif not _on:
		_disp.text = tr("AUS")
		_disp.modulate = Color(0.40, 0.42, 0.45)
	elif is_power:
		var w := GameState.get_strip_load(decor_id)
		var lim := GameState.get_strip_limit(decor_id)
		_disp.text = "%d W\n%d %%" % [w, roundi(float(w) / float(maxi(1, lim)) * 100.0)]
		_disp.modulate = Color(1.0, 0.36, 0.28) if w > lim else (Color(1.0, 0.76, 0.30) if float(w) > float(lim) * 0.85 else Color(0.46, 0.95, 0.60))
	else:
		_disp.text = "%d/8\nLINK" % live
		_disp.modulate = Color(0.46, 0.80, 1.0)


func _add_info_area(pos: Vector3, sz: Vector3) -> void:
	var area := _make_interact_area(sz, {
		"interact_type": "decor_info",
		"decor_id": decor_id,
		"item_type": item_type,
	})
	area.position = pos
	add_child(area)


func _make_interact_area(sz: Vector3, meta: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	col.shape = bs
	area.add_child(col)
	# Der Spieler-Controller liest bei jedem Ziel "entity_id".
	area.set_meta("entity_id", decor_id)
	for k in meta.keys():
		area.set_meta(k, meta[k])
	return area


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
