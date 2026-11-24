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


func setup(did: String, itype: String, data: Dictionary) -> void:
	decor_id = did
	item_type = itype
	position = data.get("pos", Vector3.ZERO) as Vector3
	rotation.y = float(data.get("rot_y", 0.0))
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
	position = data.get("pos", position) as Vector3
	rotation.y = float(data.get("rot_y", rotation.y))
	if item_type == "prop_storage_shelf":
		_sync_shelf_slots(data.get("stored_items", [null, null, null, null]) as Array)


func _process(delta: float) -> void:
	_anim_t += delta
	if _cctv_cam != null:
		_cctv_cam.rotation_degrees.y = sin(_anim_t * 0.75) * 38.0
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
		var box_mdl := ModelLoader.instantiate_custom_model("delivery_build_box")
		if box_mdl != null:
			box_mdl.scale = Vector3(0.88, 0.88, 0.88)
			h.add_child(box_mdl)
		else:
			_box(h, Vector3(0.0, 0.16, 0.0), Vector3(0.54, 0.30, 0.40), MatLib.get_mat("cardboard"))
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


# ---------------------------------------------------------------- 7. Platzierbare 6-fach Industrie-Stromleiste

func _build_power_strip() -> void:
	var mdl := ModelLoader.instantiate_custom_model("power_strip")
	if mdl != null:
		add_child(mdl)
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


# ---------------------------------------------------------------- 8. Platzierbare 8-Port LAN-Verteilerleiste

func _build_lan_strip() -> void:
	var mdl := ModelLoader.instantiate_custom_model("lan_strip")
	if mdl != null:
		add_child(mdl)
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
