class_name StorageShelfProp
extends Node3D
## Funktionales 3D-Schwerlast-Lagerregal (12 freie Stellplätze auf 4 Ebenen).
## Zeigt abgestellte Reparatur-Kits, Bausatz-Kartons & Server-Schlitten mit gut lesbarem
## 3D-Etikett, großzügigen vorderen Fach-Hitboxen sowie AAA 3D-Hover-Rahmen + Hologramm-Vorschau!

var shelf_id: String = "shelf_0"

const LEVEL_Y: Array[float] = [0.18, 0.68, 1.18, 1.68]
const COL_X: Array[float] = [-0.50, 0.0, 0.50]

var _slot_holders: Array[Node3D] = []
var _slot_labels: Array[Label3D] = []

var _hover_root: Node3D
var _hover_pad_mat: StandardMaterial3D
var _hover_frame_mat: StandardMaterial3D
var _hover_ghost_holder: Node3D
var _hover_slot_idx: int = -1
var _hover_ghost_sig: String = ""


func setup(p_shelf_id: String = "shelf_0") -> void:
	shelf_id = p_shelf_id
	_build_shelf()
	_build_hover_visuals()
	GameState.shelf_changed.connect(_refresh_slots)
	GameState.world_snapshot_loaded.connect(_refresh_slots)
	_refresh_slots()


func _build_shelf() -> void:
	var model := ModelLoader.instantiate_custom_model("workshop_storage_shelf")
	if model != null:
		add_child(model)
	else:
		# Minimaler Fallback
		var frame_m := MatLib.get_mat("rack_frame")
		var steel_m := MatLib.get_mat("galvanized_steel")
		for y in LEVEL_Y:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.56, 0.03, 0.54)
			mi.mesh = bm
			mi.material_override = steel_m
			mi.position = Vector3(0.0, y - 0.015, 0.0)
			add_child(mi)
		for sx in [-0.78, 0.78]:
			for sz in [-0.26, 0.26]:
				var pi := MeshInstance3D.new()
				var pb := BoxMesh.new()
				pb.size = Vector3(0.04, 2.08, 0.04)
				pi.mesh = pb
				pi.material_override = frame_m
				pi.position = Vector3(sx, 1.04, sz)
				add_child(pi)

	_slot_holders.clear()
	_slot_labels.clear()
	var idx := 0
	for ly in LEVEL_Y:
		for cx in COL_X:
			var holder := Node3D.new()
			holder.position = Vector3(cx, ly, 0.02)
			add_child(holder)
			_slot_holders.append(holder)

			# Gut lesbares 3D-Etikett vorne auf der Regalschiene (Front ist +Z in Godot!)
			var lbl := Label3D.new()
			lbl.text = ""
			lbl.font_size = 24
			lbl.pixel_size = 0.00145
			lbl.outline_size = 3
			lbl.outline_modulate = Color(0.04, 0.05, 0.06)
			lbl.shaded = false
			lbl.double_sided = false
			lbl.position = Vector3(cx, ly - 0.026, 0.295)
			lbl.visibility_range_end = 9.0
			add_child(lbl)
			_slot_labels.append(lbl)

			# Großzügige vordere Interaktions-Area pro Stellplatz (Layer 4, ragt frei nach vorn heraus!)
			var area := Area3D.new()
			area.collision_layer = 4
			area.collision_mask = 0
			var col := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.49, 0.44, 0.68)
			col.shape = sh
			col.position = Vector3(0.0, 0.22, 0.06)
			area.add_child(col)
			area.position = Vector3(cx, ly, 0.0)
			area.set_meta("interact_type", "storage_shelf_slot")
			area.set_meta("entity_id", shelf_id)
			area.set_meta("slot_index", idx)
			area.set_meta("shelf_prop", self)
			add_child(area)
			idx += 1


func _build_hover_visuals() -> void:
	_hover_root = Node3D.new()
	_hover_root.visible = false
	add_child(_hover_root)

	_hover_pad_mat = StandardMaterial3D.new()
	_hover_pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_pad_mat.albedo_color = Color(0.18, 0.92, 0.52, 0.22)
	_hover_pad_mat.no_depth_test = false

	_hover_frame_mat = StandardMaterial3D.new()
	_hover_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_frame_mat.albedo_color = Color(0.24, 0.98, 0.62, 0.92)

	# Boden-Highlight im Fach
	var pad := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(0.44, 0.008, 0.46)
	pad.mesh = pbm
	pad.material_override = _hover_pad_mat
	pad.position = Vector3(0.0, 0.006, 0.02)
	_hover_root.add_child(pad)

	# 4 leuchtende Eck-Winkel (AAA Placement-Frame)
	for sx in [-0.21, 0.21]:
		for sz in [-0.20, 0.24]:
			var bar_x := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.08, 0.012, 0.012)
			bar_x.mesh = bx
			bar_x.material_override = _hover_frame_mat
			bar_x.position = Vector3(sx - signf(sx) * 0.035, 0.012, sz)
			_hover_root.add_child(bar_x)

			var bar_z := MeshInstance3D.new()
			var bz := BoxMesh.new()
			bz.size = Vector3(0.012, 0.012, 0.08)
			bar_z.mesh = bz
			bar_z.material_override = _hover_frame_mat
			bar_z.position = Vector3(sx, 0.012, sz - signf(sz) * 0.035)
			_hover_root.add_child(bar_z)

			var post := MeshInstance3D.new()
			var bp := BoxMesh.new()
			bp.size = Vector3(0.010, 0.09, 0.010)
			post.mesh = bp
			post.material_override = _hover_frame_mat
			post.position = Vector3(sx, 0.052, sz)
			_hover_root.add_child(post)

	_hover_ghost_holder = Node3D.new()
	_hover_ghost_holder.position = Vector3(0.0, 0.008, 0.02)
	_hover_root.add_child(_hover_ghost_holder)


## Hebt das anvisierte Fach live hervor und zeigt beim Einlagern eine 3D-Hologramm-Vorschau im Fach!
func set_hovered_slot(slot_idx: int, held_crate: Dictionary) -> void:
	if _hover_root == null:
		return
	if slot_idx < 0 or slot_idx >= _slot_holders.size():
		_hover_root.visible = false
		_hover_slot_idx = -1
		return

	_hover_slot_idx = slot_idx
	var holder := _slot_holders[slot_idx]
	_hover_root.position = Vector3(holder.position.x, holder.position.y, 0.0)
	_hover_root.visible = true

	var skey := "%s:%d" % [shelf_id, slot_idx]
	var has_item := GameState.storage_shelf_slots.has(skey)
	var has_held := not held_crate.is_empty()

	if has_held and not has_item:
		# Grün + 3D-Hologramm-Vorschau des gehaltenen Items im freien Fach!
		_hover_pad_mat.albedo_color = Color(0.16, 0.94, 0.50, 0.24)
		_hover_frame_mat.albedo_color = Color(0.24, 1.0, 0.58, 0.95)
		var sig := "%s|%s|%d" % [
			str(held_crate.get("item_type", "")),
			str(held_crate.get("label", "")),
			maxi(1, int(held_crate.get("pack_count", 1))),
		]
		if _hover_ghost_sig != sig:
			for c in _hover_ghost_holder.get_children():
				c.queue_free()
			var preview := build_stored_visual(held_crate)
			_apply_hologram_tint(preview, Color(0.20, 0.96, 0.54, 0.42))
			_hover_ghost_holder.add_child(preview)
			_hover_ghost_sig = sig
		_hover_ghost_holder.visible = true
	elif not has_held and has_item:
		# Gold-Cyan Rahmen zum Herausnehmen!
		_hover_pad_mat.albedo_color = Color(0.98, 0.78, 0.22, 0.22)
		_hover_frame_mat.albedo_color = Color(1.0, 0.84, 0.28, 0.96)
		_hover_ghost_holder.visible = false
	elif has_held and has_item:
		# Rot = Fach belegt
		_hover_pad_mat.albedo_color = Color(0.95, 0.24, 0.22, 0.22)
		_hover_frame_mat.albedo_color = Color(1.0, 0.30, 0.26, 0.92)
		_hover_ghost_holder.visible = false
	else:
		# Leer ohne Item in der Hand: dezentes Blau-Grau
		_hover_pad_mat.albedo_color = Color(0.35, 0.62, 0.88, 0.14)
		_hover_frame_mat.albedo_color = Color(0.42, 0.72, 0.96, 0.58)
		_hover_ghost_holder.visible = false


static func _apply_hologram_tint(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var hm := StandardMaterial3D.new()
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.albedo_color = col
		hm.emission_enabled = true
		hm.emission = Color(col.r, col.g, col.b)
		hm.emission_energy_multiplier = 0.85
		mi.material_override = hm
	elif n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_apply_hologram_tint(c, col)


func _refresh_slots() -> void:
	for idx in range(mini(_slot_holders.size(), GameState.STORAGE_SHELF_SLOTS)):
		var holder := _slot_holders[idx]
		var lbl := _slot_labels[idx]
		for c in holder.get_children():
			c.queue_free()
		var key := "%s:%d" % [shelf_id, idx]
		if not GameState.storage_shelf_slots.has(key):
			lbl.text = tr("FREI")
			lbl.modulate = Color(0.50, 0.54, 0.60)
			continue
		var data: Dictionary = GameState.storage_shelf_slots[key] as Dictionary
		var itype := str(data.get("item_type", ""))
		var txt := GameState.get_crate_display_label(data)
		lbl.text = txt
		var col := Color(0.95, 0.96, 0.98)
		if GameState.ITEM_CATALOG.has(itype):
			col = (GameState.ITEM_CATALOG[itype].get("color", col) as Color).lightened(0.25)
		lbl.modulate = col
		var vis := build_stored_visual(data)
		holder.add_child(vis)


static func build_stored_visual(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	var itype := str(data.get("item_type", ""))
	var pcount := maxi(1, int(data.get("pack_count", 1)))
	if pcount > 1:
		# Dedizierte Mengen-Kiste (bis 6 Stück/Box) mit farbcodiertem Band & Mengen-Etikett!
		var bulk_m := ModelLoader.instantiate_custom_model("bulk_pack_crate")
		var col := Color(0.22, 0.68, 0.96)
		if GameState.ITEM_CATALOG.has(itype):
			col = GameState.ITEM_CATALOG[itype].get("color", col) as Color
		if bulk_m != null:
			_tint_material_by_name(bulk_m, "WS_KitStripe", col)
			root.add_child(bulk_m)
		else:
			var fb := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.24, 0.34)
			fb.mesh = bm
			fb.position = Vector3(0.0, 0.12, 0.0)
			root.add_child(fb)
		var disp_txt := GameState.get_crate_display_label(data)
		var l_top := Label3D.new()
		l_top.text = disp_txt
		l_top.font_size = 24
		l_top.pixel_size = 0.00145
		l_top.modulate = Color(0.06, 0.08, 0.12)
		l_top.outline_size = 0
		l_top.shaded = false
		l_top.position = Vector3(0.0, 0.258, -0.01)
		l_top.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		root.add_child(l_top)
		var l_front := Label3D.new()
		l_front.text = "%s\nMENGEN-KISTE" % disp_txt
		l_front.font_size = 20
		l_front.pixel_size = 0.00125
		l_front.modulate = Color(0.06, 0.08, 0.12)
		l_front.outline_size = 0
		l_front.shaded = false
		l_front.position = Vector3(0.0, 0.140, 0.184)
		root.add_child(l_front)
		var l_badge := Label3D.new()
		l_badge.text = "%d×" % pcount
		l_badge.font_size = 34
		l_badge.pixel_size = 0.0015
		l_badge.modulate = col.lightened(0.35)
		l_badge.outline_size = 4
		l_badge.outline_modulate = Color(0.04, 0.05, 0.07)
		l_badge.shaded = false
		l_badge.position = Vector3(0.145, 0.195, 0.186)
		root.add_child(l_badge)
	elif GameState.is_repair_kit(itype):
		var kit_m := ModelLoader.instantiate_custom_model("repair_kit_case")
		if kit_m != null:
			var col: Color = GameState.ITEM_CATALOG[itype].get("color", Color(0.25, 0.68, 0.95))
			_tint_material_by_name(kit_m, "WS_KitStripe", col)
			root.add_child(kit_m)
		else:
			var fb := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.30, 0.11, 0.22)
			fb.mesh = bm
			fb.position = Vector3(0.0, 0.055, 0.0)
			root.add_child(fb)
		var l_top := Label3D.new()
		l_top.text = GameState.get_crate_display_label(data)
		l_top.font_size = 24
		l_top.pixel_size = 0.00135
		l_top.modulate = Color(0.08, 0.10, 0.14)
		l_top.outline_size = 0
		l_top.shaded = false
		l_top.position = Vector3(0.0, 0.128, 0.095)
		l_top.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		root.add_child(l_top)
		var l_front := Label3D.new()
		l_front.text = GameState.get_crate_display_label(data)
		l_front.font_size = 20
		l_front.pixel_size = 0.00105
		l_front.modulate = Color(0.95, 0.96, 0.98)
		l_front.outline_size = 3
		l_front.outline_modulate = Color(0.05, 0.06, 0.08)
		l_front.shaded = false
		l_front.position = Vector3(0.0, 0.095, 0.126)
		root.add_child(l_front)
	elif itype == "slot_build_box":
		var box_m := ModelLoader.instantiate_custom_model("delivery_build_box")
		if box_m != null:
			box_m.scale = Vector3(0.88, 0.88, 0.88)
			root.add_child(box_m)
		var fl := Label3D.new()
		fl.text = GameState.get_crate_display_label(data)
		fl.font_size = 22
		fl.pixel_size = 0.0013
		fl.modulate = Color(0.08, 0.10, 0.14)
		fl.outline_size = 0
		fl.shaded = false
		fl.position = Vector3(0.0, 0.105, 0.180)
		root.add_child(fl)
	elif itype == "server_tray":
		var td: Dictionary = data.get("tray_data", {}) as Dictionary
		var mb_id := str(td.get("mainboard_id", "web_server"))
		var comps: Dictionary = td.get("components", {}) as Dictionary
		var brk := GameState.get_visible_fault(td)
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], brk)
		srv.scale = Vector3(0.56, 0.56, 0.56)
		root.add_child(srv)
	else:
		var item_v := HardwareMeshFactory.build_item_visual(itype)
		item_v.scale = Vector3(0.55, 0.55, 0.55)
		root.add_child(item_v)
	return root


static func _tint_material_by_name(n: Node, mat_name: String, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var sm := mi.mesh.surface_get_material(s)
				if sm is StandardMaterial3D and sm.resource_name == mat_name:
					var dup := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = col
					mi.set_surface_override_material(s, dup)
	for c in n.get_children():
		_tint_material_by_name(c, mat_name, col)
