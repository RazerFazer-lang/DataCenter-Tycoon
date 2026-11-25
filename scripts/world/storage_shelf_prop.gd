class_name StorageShelfProp
extends RefCounted
## Anzeige für Reparatur-Kits, Mengen-Kisten und Server-Schlitten (Boden, Rollwagen, Regal)
## sowie die Hologramm-Färbung der Regal-Vorschau. Die Regale selbst stehen in ShelfProp.


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
		var box_m := CartonFactory.build("build", GameState.get_crate_display_label(data))
		box_m.scale = Vector3(0.80, 0.80, 0.80)
		root.add_child(box_m)
	elif itype == "server_tray":
		var td: Dictionary = data.get("tray_data", {}) as Dictionary
		var mb_id := str(td.get("mainboard_id", "web_server"))
		var comps: Dictionary = td.get("components", {}) as Dictionary
		var brk := GameState.get_visible_fault(td)
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], brk)
		srv.scale = Vector3(0.56, 0.56, 0.56)
		root.add_child(srv)
	else:
		var item_v := HardwareMeshFactory.build_item_visual(itype, data)
		item_v.scale = Vector3(0.62, 0.62, 0.62)
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
