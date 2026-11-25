class_name DecorProp
extends Node3D
## Frei platzierbare, kaufbare 2K-ORM-PBR Einrichtungs- & Technik-Items aus Blender 5.2:
## - prop_storage_shelf   (decor_storage_shelf.glb — 4 echte Ablageplätze)
## - prop_esd_workbench   (decor_esd_workbench.glb — Eichenplatte, ESD-Matte, 2-Ch-Oszilloskop, Lochwand)
## - prop_parts_cabinet   (decor_parts_cabinet.glb — Stahlschrank mit Echtglastüren & Sichtlagerkästen)
## - prop_cold_aisle_gate (decor_cold_aisle_gate.glb — Alu-Kaltgang-Portal mit Echtglas-Schiebetüren)
## - prop_vending_lounge  (decor_vending_lounge.glb — Getränkeautomat mit 3D-Dosen hinter Glas + Pflanze)
## - prop_cctv_monitor    (decor_cctv_monitor.glb + decor_cctv_cam_head.glb — Telemetrie-Stele & PTZ-Kamera)

var decor_id: String = ""
var item_type: String = ""
var _shelf_crate_nodes: Array[Node3D] = []
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


func setup(did: String, itype: String, data: Dictionary) -> void:
	decor_id = did
	item_type = itype
	_apply_pose(data)
	match itype:
		"prop_storage_shelf":
			_build_storage_shelf()
		"prop_esd_workbench":
			_build_esd_workbench()
		"prop_parts_cabinet":
			_build_parts_cabinet()
		"prop_cold_aisle_gate":
			_build_cold_aisle_gate()
		"prop_vending_lounge":
			_build_vending_lounge()
		"prop_cctv_monitor":
			_build_cctv_monitor()
		"prop_power_strip":
			_build_power_strip()
		"prop_lan_strip":
			_build_lan_strip()
	apply_data(data)


## Am Boden liegend oder an der Wand (Oberseite zeigt dann in den Raum).
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
	if item_type == "prop_storage_shelf":
		_sync_shelf_slots(data.get("stored_items", [null, null, null, null]) as Array)


func _process(delta: float) -> void:
	_anim_t += delta
	if _cctv_cam != null:
		_cctv_cam.rotation_degrees.y = sin(_anim_t * 0.75) * 38.0
	if _switch_node != null and GameState.is_active:
		_process_strip(delta)
	if _temp_lbl != null and GameState.is_active:
		_temp_lbl.text = "%.1f °C  •  OK" % GameState.room_temp


# ---------------------------------------------------------------- 1. Schwerlast-Lagerregal (4 echte Ablageplätze!)

func _build_storage_shelf() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_storage_shelf")
	if mdl != null:
		add_child(mdl)
	else:
		var steel := MatLib.make_brushed_metal(Color(0.20, 0.23, 0.28), 0.40, 0.70)
		var wood := MatLib.get_mat("wood_desk")
		for sx in [-0.74, 0.74]:
			for sz in [-0.25, 0.25]:
				_box(self, Vector3(float(sx), 1.08, float(sz)), Vector3(0.045, 2.16, 0.045), steel)
		for sy_f in [0.22, 0.78, 1.34, 1.90]:
			_box(self, Vector3(0.0, float(sy_f), 0.0), Vector3(1.52, 0.035, 0.52), wood)

	var shelf_ys := [0.22, 0.78, 1.34, 1.90]
	_shelf_crate_nodes.clear()
	for idx in range(4):
		var sy: float = shelf_ys[idx]
		var holder := Node3D.new()
		holder.position = Vector3(0.0, sy + 0.02, 0.0)
		add_child(holder)
		_shelf_crate_nodes.append(holder)
		var area := _make_interact_area(Vector3(1.42, 0.48, 0.62), {
			"interact_type": "decor_shelf_slot",
			"decor_id": decor_id,
			"slot_idx": idx,
		})
		area.position = Vector3(0.0, sy + 0.26, 0.05)
		add_child(area)
	_add_collider(Vector3(0.0, 1.08, 0.0), Vector3(1.56, 2.16, 0.56))


func _sync_shelf_slots(stored: Array) -> void:
	for i in range(mini(stored.size(), _shelf_crate_nodes.size())):
		var h := _shelf_crate_nodes[i]
		for c in h.get_children():
			c.queue_free()
		if stored[i] == null or not (stored[i] is Dictionary):
			continue
		var sd: Dictionary = stored[i]
		var itype := str(sd.get("item_type", ""))
		var col := Color(0.72, 0.56, 0.38)
		var ilbl := itype
		if GameState.ITEM_CATALOG.has(itype):
			var cat: Dictionary = GameState.ITEM_CATALOG[itype]
			col = cat.get("color", col)
			ilbl = str(cat.get("label", itype))
		var box_mdl := StorageShelfProp.build_stored_visual(sd)
		h.add_child(box_mdl)
		var tag := Label3D.new()
		tag.text = ilbl.left(18)
		tag.font_size = 20
		tag.pixel_size = 0.0015
		tag.outline_size = 2
		tag.modulate = col.lerp(Color.WHITE, 0.45)
		tag.position = Vector3(0.0, 0.14, 0.22)
		h.add_child(tag)


# ---------------------------------------------------------------- 2. ESD-Diagnose-Werkbank

func _build_esd_workbench() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_esd_workbench")
	if mdl != null:
		add_child(mdl)
		var hw_disp := HardwareMeshFactory.build_workbench_display()
		hw_disp.position = Vector3(-0.04, 0.880, 0.06)
		add_child(hw_disp)
	else:
		add_child(BuildingPropFactory.build_hardware_workbench())

	var task_light := OmniLight3D.new()
	task_light.position = Vector3(0.0, 1.68, -0.05)
	task_light.light_color = Color(0.98, 0.97, 0.94)
	task_light.light_energy = 0.75
	task_light.omni_range = 2.8
	add_child(task_light)

	_add_collider(Vector3(0.0, 0.65, 0.0), Vector3(1.56, 1.30, 0.82))
	var area := _make_interact_area(Vector3(1.5, 1.3, 0.9), {
		"interact_type": "decor_info",
		"decor_id": decor_id,
		"item_type": item_type,
	})
	area.position = Vector3(0.0, 0.9, 0.1)
	add_child(area)


# ---------------------------------------------------------------- 3. Ersatzteil-Schrank & Kabeltrommel-Ständer

func _build_parts_cabinet() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_parts_cabinet")
	if mdl != null:
		add_child(mdl)
	else:
		_box(self, Vector3(0.0, 1.02, 0.0), Vector3(1.12, 2.04, 0.56), _mat(Color(0.14, 0.16, 0.20), 0.38, 0.68))

	var lbl := Label3D.new()
	lbl.text = "ERSATZTEIL-SCHRANK\n[E] +3 Wartungs-Kits ($20)"
	lbl.font_size = 20
	lbl.pixel_size = 0.0020
	lbl.outline_size = 0
	lbl.position = Vector3(0.0, 1.98, 0.315)
	lbl.modulate = Color(0.98, 0.86, 0.38)
	add_child(lbl)
	var area := _make_interact_area(Vector3(1.16, 1.9, 0.7), {
		"interact_type": "parts_cabinet",
		"decor_id": decor_id,
	})
	area.position = Vector3(0.0, 1.0, 0.15)
	add_child(area)
	_add_collider(Vector3(0.0, 1.02, 0.0), Vector3(1.14, 2.04, 0.58))


# ---------------------------------------------------------------- 4. Kaltgang-Schiebetür-Portal

func _build_cold_aisle_gate() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_cold_aisle_gate")
	if mdl != null:
		add_child(mdl)
	else:
		var dark := _mat(Color(0.12, 0.15, 0.19), 0.36, 0.72)
		_box(self, Vector3(-1.05, 1.28, 0.0), Vector3(0.14, 2.56, 0.18), dark)
		_box(self, Vector3( 1.05, 1.28, 0.0), Vector3(0.14, 2.56, 0.18), dark)
		_box(self, Vector3(0.0, 2.48, 0.0), Vector3(2.24, 0.20, 0.20), dark)

	_temp_lbl = Label3D.new()
	_temp_lbl.text = "22.0 °C  •  OK"
	_temp_lbl.font_size = 26
	_temp_lbl.pixel_size = 0.0024
	_temp_lbl.outline_size = 0
	_temp_lbl.position = Vector3(0.0, 2.49, 0.118)
	_temp_lbl.modulate = Color(0.58, 0.90, 1.0)
	add_child(_temp_lbl)
	# Nur die beiden Seitenpfosten blockieren — Spieler läuft frei durch die Mitte!
	_add_collider(Vector3(-1.05, 1.28, 0.0), Vector3(0.18, 2.56, 0.20))
	_add_collider(Vector3( 1.05, 1.28, 0.0), Vector3(0.18, 2.56, 0.20))
	for gx in [-1.05, 1.05]:
		_add_info_area(Vector3(float(gx), 1.28, 0.0), Vector3(0.26, 2.5, 0.28))


# ---------------------------------------------------------------- 5. Getränkeautomat & Kaffee-Lounge

func _build_vending_lounge() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_vending_lounge")
	if mdl != null:
		add_child(mdl)
	else:
		_box(self, Vector3(-0.22, 0.98, 0.0), Vector3(0.96, 1.96, 0.72), _mat(Color(0.14, 0.16, 0.20), 0.36, 0.45))

	var vend_glow := OmniLight3D.new()
	vend_glow.position = Vector3(-0.34, 1.15, 0.55)
	vend_glow.light_color = Color(0.92, 0.96, 1.0)
	vend_glow.light_energy = 0.45
	vend_glow.omni_range = 2.4
	add_child(vend_glow)
	_add_collider(Vector3(0.05, 0.98, 0.0), Vector3(1.48, 1.96, 0.74))
	_add_info_area(Vector3(0.05, 0.98, 0.0), Vector3(1.56, 1.98, 0.82))


# ---------------------------------------------------------------- 6. CCTV- & Temperatur-Stele

func _build_cctv_monitor() -> void:
	var mdl := ModelLoader.instantiate_custom_model("decor_cctv_monitor")
	if mdl != null:
		add_child(mdl)
	else:
		_box(self, Vector3(0.0, 1.18, 0.0), Vector3(0.46, 2.24, 0.22), _mat(Color(0.13, 0.15, 0.19), 0.34, 0.75))

	_temp_lbl = Label3D.new()
	_temp_lbl.text = "22.0 °C  •  OK"
	_temp_lbl.font_size = 24
	_temp_lbl.pixel_size = 0.0020
	_temp_lbl.outline_size = 0
	_temp_lbl.position = Vector3(0.0, 1.56, 0.136)
	_temp_lbl.modulate = Color(0.92, 0.98, 1.0)
	add_child(_temp_lbl)

	# Schwenkender High-Poly PTZ-Kamerakopf ganz oben
	_cctv_cam = Node3D.new()
	_cctv_cam.position = Vector3(0.0, 2.38, 0.06)
	add_child(_cctv_cam)
	var cam_head := ModelLoader.instantiate_custom_model("decor_cctv_cam_head")
	if cam_head != null:
		_cctv_cam.add_child(cam_head)
	else:
		_box(_cctv_cam, Vector3(0.0, 0.0, 0.10), Vector3(0.12, 0.10, 0.24), _mat(Color(0.72, 0.76, 0.80), 0.28, 0.86))
	_add_collider(Vector3(0.0, 1.15, 0.0), Vector3(0.72, 2.30, 0.48))
	_add_info_area(Vector3(0.0, 1.15, 0.0), Vector3(0.80, 2.32, 0.56))


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
