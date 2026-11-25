class_name ShelfProp
extends Node3D
## Lagerregal in drei Größen (ShelfSpec). Zeigt die Ware in echter Größe, hat je Einheit eine
## Zielfläche und beim Anvisieren einen Rahmen mit Vorschau, der grün (passt) oder rot (passt nicht) ist.

var decor_id := ""
var shelf_type := "prop_storage_shelf"

var _goods: Node3D
var _hover: Node3D
var _hover_pad: MeshInstance3D
var _hover_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _edges: Array[MeshInstance3D] = []
var _ghost: Node3D
var _ghost_sig := ""
var _sig := ""


func setup(p_id: String, p_type: String) -> void:
	decor_id = p_id
	shelf_type = p_type
	var s: Dictionary = ShelfSpec.SPECS[shelf_type]
	var mdl := ModelLoader.instantiate_custom_model(str(s["model"]))
	if mdl != null:
		add_child(mdl)
	else:
		_fallback(s)
	_goods = Node3D.new()
	add_child(_goods)
	_build_areas(s)
	_build_hover()


func _fallback(s: Dictionary) -> void:
	var sz: Vector3 = s["size"]
	for y in s["levels"]:
		_box(Vector3(0, float(y) - 0.015, 0), Vector3(sz.x, 0.03, sz.z))
	for sx in [-0.5, 0.5]:
		for sz_f in [-0.45, 0.45]:
			_box(Vector3(sz.x * float(sx), sz.y * 0.5, sz.z * float(sz_f)), Vector3(0.05, sz.y, 0.05))


func _box(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = MatLib.get_mat("rack_frame")
	add_child(mi)


func _build_areas(s: Dictionary) -> void:
	var cols := int(s["cols"])
	var h := float(s["clear"])
	for i in ShelfSpec.unit_count(shelf_type):
		var area := Area3D.new()
		area.collision_layer = 4
		area.collision_mask = 0
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		# Ragt vorn heraus, damit man das Fach auch schräg gut trifft.
		sh.size = Vector3(float(s["unit_w"]) - 0.01, h, float(s["depth"]) + 0.10)
		col.shape = sh
		area.add_child(col)
		var p := ShelfSpec.spot(shelf_type, i, 1)
		area.position = Vector3(p.x, float((s["levels"] as Array)[i / cols]) + h * 0.5, 0.05)
		area.set_meta("interact_type", "decor_shelf_slot")
		area.set_meta("decor_id", decor_id)
		area.set_meta("entity_id", decor_id)
		area.set_meta("slot_idx", i)
		area.set_meta("shelf_prop", self)
		add_child(area)


func _build_hover() -> void:
	_hover = Node3D.new()
	_hover.visible = false
	add_child(_hover)
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat = _hover_mat.duplicate()
	_hover_pad = MeshInstance3D.new()
	_hover_pad.mesh = BoxMesh.new()
	_hover_pad.material_override = _hover_mat
	_hover_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.add_child(_hover_pad)
	for i in 4:
		var e := MeshInstance3D.new()
		e.mesh = BoxMesh.new()
		e.material_override = _edge_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hover.add_child(e)
		_edges.append(e)
	_ghost = Node3D.new()
	_hover.add_child(_ghost)


func _data() -> Dictionary:
	return GameState.decor_items.get(decor_id, {})


## Ware neu aufbauen, wenn sich etwas geändert hat.
func sync() -> void:
	var d := _data()
	var arr: Array = d.get("stored_items", [])
	var sig := str(arr.hash())
	if sig == _sig:
		return
	_sig = sig
	for c in _goods.get_children():
		c.queue_free()
	var s: Dictionary = ShelfSpec.SPECS[shelf_type]
	for i in mini(arr.size(), ShelfSpec.unit_count(shelf_type)):
		if not (arr[i] is Dictionary):
			continue
		var crate: Dictionary = arr[i]
		var n := maxi(1, ShelfSpec.span(shelf_type, crate))
		var holder := Node3D.new()
		holder.position = ShelfSpec.spot(shelf_type, i, n)
		_goods.add_child(holder)
		if bool(s["pallet"]):
			var pal := ModelLoader.instantiate_custom_model("euro_pallet")
			if pal != null:
				pal.position.y = -ShelfSpec.PALLET_H
				holder.add_child(pal)
		var vis := goods_visual(crate)
		# Vorderkante bündig: flache Ware nicht nach hinten rutschen lassen.
		var dm := ShelfSpec.dims(crate)
		vis.position.z = maxf(0.0, (float(s["depth"]) - dm.z) * 0.5 - 0.03) if not bool(s["pallet"]) else 0.0
		holder.add_child(vis)
		_add_tag(i, n, crate, s)


## Ware in echter Größe.
static func goods_visual(crate: Dictionary) -> Node3D:
	var t := str(crate.get("item_type", ""))
	if int(crate.get("pack_count", 1)) > 1 or GameState.is_repair_kit(t) or t == "server_tray":
		return StorageShelfProp.build_stored_visual(crate)
	if t == "slot_build_box":
		return CartonFactory.build("build", GameState.get_crate_display_label(crate))
	return HardwareMeshFactory.build_item_visual(t, crate)


func _add_tag(start: int, n: int, crate: Dictionary, s: Dictionary) -> void:
	var p := ShelfSpec.spot(shelf_type, start, n)
	var level_y := float((s["levels"] as Array)[start / int(s["cols"])])
	var w := minf(float(s["unit_w"]) * float(n) - 0.05, 0.44)
	var plate := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, 0.044)
	plate.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.93, 0.90)
	m.roughness = 0.7
	plate.material_override = m
	var tag_y := level_y - 0.030 if level_y > 0.06 else level_y + 0.075
	plate.position = Vector3(p.x, tag_y, float(s["size"].z) * 0.5 + 0.006)
	_goods.add_child(plate)
	var l := Label3D.new()
	l.text = GameState.get_crate_display_label(crate)
	l.font_size = 22
	l.pixel_size = 0.0011
	var width_m := ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
	if width_m > w - 0.02:
		l.pixel_size *= (w - 0.02) / width_m
	l.outline_size = 0
	l.modulate = Color(0.06, 0.07, 0.09)
	l.shaded = false
	l.double_sided = false
	l.visibility_range_end = 7.0
	l.position = plate.position + Vector3(0, 0, 0.003)
	_goods.add_child(l)


# ---------------------------------------------------------------- Anvisieren

func set_hovered_slot(idx: int, held: Dictionary) -> void:
	var d := _data()
	if idx < 0 or d.is_empty():
		_hover.visible = false
		return
	var s: Dictionary = ShelfSpec.SPECS[shelf_type]
	var start := -1
	var n := 1
	var col := Color(0.30, 0.75, 1.0)
	var owner_i := ShelfSpec.owner_of(d, idx)
	var h := float(s["clear"]) - 0.03
	if held.is_empty():
		if owner_i < 0:
			_hover.visible = false
			_clear_ghost()
			return
		start = owner_i
		n = maxi(1, ShelfSpec.span(shelf_type, (d["stored_items"] as Array)[owner_i]))
		h = minf(h, ShelfSpec.dims((d["stored_items"] as Array)[owner_i]).y + 0.03)
		_clear_ghost()
	else:
		start = ShelfSpec.fit(d, idx, held)
		n = maxi(1, ShelfSpec.span(shelf_type, held))
		if start >= 0:
			col = Color(0.24, 0.98, 0.60)
			h = minf(h, ShelfSpec.dims(held).y + 0.03)
			_show_ghost(held, s)
		else:
			col = Color(1.0, 0.28, 0.24)
			start = idx
			n = 1
			_clear_ghost()
	var p := ShelfSpec.spot(shelf_type, start, n)
	_hover.position = p
	_hover.visible = true
	var w := float(s["unit_w"]) * float(n) - 0.02
	var dz := float(s["depth"]) - 0.04
	(_hover_pad.mesh as BoxMesh).size = Vector3(w, 0.006, dz)
	_hover_pad.position = Vector3(0, 0.005, 0)
	_hover_mat.albedo_color = Color(col, 0.20)
	_edge_mat.albedo_color = Color(col, 0.90)
	var t := 0.010
	var zf := dz * 0.5
	var rects := [
		[Vector3(0, 0.005, zf), Vector3(w, t, t)], [Vector3(0, h, zf), Vector3(w, t, t)],
		[Vector3(-w * 0.5, h * 0.5, zf), Vector3(t, h, t)], [Vector3(w * 0.5, h * 0.5, zf), Vector3(t, h, t)],
	]
	for i in 4:
		(_edges[i].mesh as BoxMesh).size = rects[i][1]
		_edges[i].position = rects[i][0]


func _show_ghost(held: Dictionary, s: Dictionary) -> void:
	var sig := "%s|%d" % [str(held.get("item_type", "")), int(held.get("pack_count", 1))]
	if sig == _ghost_sig:
		return
	_clear_ghost()
	_ghost_sig = sig
	var vis := goods_visual(held)
	var dm := ShelfSpec.dims(held)
	vis.position.z = maxf(0.0, (float(s["depth"]) - dm.z) * 0.5 - 0.03) if not bool(s["pallet"]) else 0.0
	_ghost.add_child(vis)
	StorageShelfProp._apply_hologram_tint(vis, Color(0.24, 0.98, 0.60, 0.42))


func _clear_ghost() -> void:
	_ghost_sig = ""
	for c in _ghost.get_children():
		c.queue_free()


func clear_hover() -> void:
	_hover.visible = false
	_clear_ghost()
