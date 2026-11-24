class_name CrateProp
extends Node3D
## Realistic 3D Hardware Shipping Tray / Packaging:
## Server modules (Web-Server, Storage-NAS, GPU-AI-Server, Rack-Switch) sit openly inside
## protective grey ESD foam trays so you literally see the real 3D Motherboard, CPU, RAM,
## GPU & drive caddies! Larger floor equipment sits in strapped industrial freight crates.

var crate_id: String = ""
var item_type: String = ""
var _crate_data: Dictionary = {}

var _label: Label3D
var _box_front_lbl: Label3D
var _box_top_lbl: Label3D
var _area: Area3D
var _visual_holder: Node3D
var _cached_pack_count: int = 1


func setup(id: String, p_item_type: String, p_data: Dictionary = {}) -> void:
	crate_id = id
	item_type = p_item_type
	_crate_data = p_data.duplicate(true)
	_cached_pack_count = maxi(1, int(_crate_data.get("pack_count", 1)))
	_build_geometry()


func apply_data(data: Dictionary) -> void:
	_crate_data = data.duplicate(true)
	var new_pack := maxi(1, int(data.get("pack_count", 1)))
	if new_pack != _cached_pack_count and _visual_holder != null:
		_cached_pack_count = new_pack
		for c in _visual_holder.get_children():
			c.queue_free()
		_populate_visual()
	var held_by := int(data.get("held_by", 0))
	if held_by != 0:
		visible = false
		_set_interactable(false)
	else:
		visible = true
		position = data["pos"]
		_set_interactable(true)
	var disp := GameState.get_crate_display_label(data)
	if _label != null:
		_label.text = disp
	if _box_front_lbl != null:
		_box_front_lbl.text = disp + "\nBausatz → Werkbank"
	if _box_top_lbl != null:
		_box_top_lbl.text = disp


func _set_interactable(enabled: bool) -> void:
	if _area == null:
		return
	for child in _area.get_children():
		if child is CollisionShape3D:
			child.disabled = not enabled


func _build_geometry() -> void:
	_visual_holder = Node3D.new()
	add_child(_visual_holder)
	_populate_visual()

	var disp := GameState.get_crate_display_label(_crate_data)
	_label = Label3D.new()
	_label.text = disp
	_label.font_size = 20
	_label.pixel_size = 0.0040
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 0.64, 0.0)
	_label.modulate = Color(0.95, 0.95, 0.93)
	add_child(_label)

	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.74, 0.54, 0.72)
	col.shape = sh
	col.position = Vector3(0.0, 0.27, 0.0)
	_area.add_child(col)
	_area.set_meta("interact_type", "crate")
	_area.set_meta("entity_id", crate_id)
	add_child(_area)


func _populate_visual() -> void:
	_box_front_lbl = null
	_box_top_lbl = null
	var pcount := maxi(1, int(_crate_data.get("pack_count", 1)))

	if pcount > 1:
		_visual_holder.add_child(StorageShelfProp.build_stored_visual(_crate_data))
	elif item_type == "slot_build_box":
		var bmod := ModelLoader.instantiate_custom_model("delivery_build_box")
		if bmod != null:
			_visual_holder.add_child(bmod)
		else:
			_add_box(_visual_holder, Vector3(0.0, 0.11, 0.0), Vector3(0.46, 0.22, 0.40), MatLib.get_mat("cardboard"))
		var disp_txt := GameState.get_crate_display_label(_crate_data)
		_box_front_lbl = Label3D.new()
		_box_front_lbl.text = disp_txt + "\nBausatz → Werkbank"
		_box_front_lbl.font_size = 20
		_box_front_lbl.pixel_size = 0.0014
		_box_front_lbl.modulate = Color(0.06, 0.08, 0.12)
		_box_front_lbl.outline_size = 0
		_box_front_lbl.shaded = false
		_box_front_lbl.position = Vector3(0.0, 0.12, 0.204)
		_visual_holder.add_child(_box_front_lbl)
		_box_top_lbl = Label3D.new()
		_box_top_lbl.text = disp_txt
		_box_top_lbl.font_size = 22
		_box_top_lbl.pixel_size = 0.0015
		_box_top_lbl.modulate = Color(0.06, 0.08, 0.12)
		_box_top_lbl.outline_size = 0
		_box_top_lbl.shaded = false
		_box_top_lbl.position = Vector3(0.0, 0.225, 0.06)
		_box_top_lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_visual_holder.add_child(_box_top_lbl)
	elif GameState.is_repair_kit(item_type):
		_visual_holder.add_child(StorageShelfProp.build_stored_visual(_crate_data if not _crate_data.is_empty() else {"item_type": item_type}))
	elif item_type == "server_tray":
		var td: Dictionary = _crate_data.get("tray_data", {}) as Dictionary
		var mb_id := str(td.get("mainboard_id", "web_server"))
		var comps: Dictionary = td.get("components", {}) as Dictionary
		var brk := str(td.get("faulty_part", "")) if str(td.get("state", "ok")) == "crashed" else ""
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], brk)
		srv.position = Vector3(0.0, 0.02, 0.0)
		_visual_holder.add_child(srv)
	elif GameState.is_slot_upgradeable(item_type) or item_type == "net_switch":
		var box_mat := MatLib.get_mat("cardboard")
		var foam_mat := MatLib.get_mat("packing_foam")
		_add_box(_visual_holder, Vector3(0.0, 0.03, 0.0), Vector3(0.72, 0.06, 0.68), box_mat)
		_add_box(_visual_holder, Vector3(-0.34, 0.12, 0.0), Vector3(0.04, 0.16, 0.68), box_mat)
		_add_box(_visual_holder, Vector3(0.34, 0.12, 0.0), Vector3(0.04, 0.16, 0.68), box_mat)
		_add_box(_visual_holder, Vector3(0.0, 0.12, -0.32), Vector3(0.66, 0.16, 0.04), box_mat)
		_add_box(_visual_holder, Vector3(0.0, 0.12, 0.32), Vector3(0.66, 0.16, 0.04), box_mat)
		for fx in [-0.29, 0.29]:
			_add_box(_visual_holder, Vector3(float(fx), 0.11, 0.0), Vector3(0.055, 0.11, 0.58), foam_mat)
		var srv := HardwareMeshFactory.build_item_visual(item_type)
		srv.position = Vector3(0.0, 0.085, 0.0)
		_visual_holder.add_child(srv)
	else:
		var pkg := HardwareMeshFactory.build_item_visual(item_type)
		var uses_fuse_model := item_type == "old_fuse" and ModelLoader.has_custom_model("fuse_d02_blown")
		if not uses_fuse_model:
			pkg.scale = Vector3(1.12, 1.18, 1.12)
		else:
			pkg.position = Vector3(0.0, 0.024, 0.0)
		_visual_holder.add_child(pkg)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
