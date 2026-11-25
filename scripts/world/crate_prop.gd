class_name CrateProp
extends Node3D
## Ware in der Lieferzone und unterwegs: Kartons je Warenart (CartonFactory), Kits, Server-Schlitten und Mengen-Kisten.

var crate_id: String = ""
var item_type: String = ""
var _crate_data: Dictionary = {}

var _label: Label3D
var _area: Area3D
var _visual_holder: Node3D
var _cached_pack_count: int = 1
var _settle: Tween
var _pallet: Node3D


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
		rotation.y = float(data.get("rot", 0.0))
		# Nachrutschen im Stapel sieht man, statt dass der Karton springt.
		var np: Vector3 = data["pos"]
		if _settle != null and _settle.is_valid():
			_settle.kill()
		if is_inside_tree() and np.y < position.y - 0.02 and Vector2(np.x - position.x, np.z - position.z).length() < 0.05:
			_settle = create_tween()
			_settle.tween_property(self, "position", np, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			position = np
		_set_interactable(true)
	_show_pallet(held_by == 0 and bool(data.get("pal", false)))
	var disp := GameState.get_crate_display_label(data)
	if _label != null:
		_label.text = disp


## Große Geräte kommen auf einer Palette. Wer das Gerät nimmt, räumt sie mit weg.
func _show_pallet(on: bool) -> void:
	if on and _pallet == null:
		_pallet = ModelLoader.instantiate_custom_model("euro_pallet")
		if _pallet != null:
			_pallet.position.y = -DeliveryPlan.PALLET_H
			add_child(_pallet)
	elif not on and _pallet != null:
		_pallet.queue_free()
		_pallet = null


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
	_label.position = Vector3(0.0, _visual_height() + 0.16, 0.0)
	_label.visibility_range_end = 6.0
	_label.modulate = Color(0.95, 0.95, 0.93)
	add_child(_label)

	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	var ah := maxf(0.22, _visual_height() + 0.06)
	sh.size = Vector3(0.74, ah, 0.72)
	col.shape = sh
	col.position = Vector3(0.0, ah * 0.5, 0.0)
	_area.add_child(col)
	_area.set_meta("interact_type", "crate")
	_area.set_meta("entity_id", crate_id)
	add_child(_area)


func _visual_height() -> float:
	if item_type == "server_tray" or GameState.is_repair_kit(item_type):
		return 0.26
	if item_type == "old_fuse":
		return 0.10
	if item_type == "empty_carton":
		return CartonFactory.height(str(_crate_data.get("carton", "deco")))
	if int(_crate_data.get("pack_count", 1)) > 1:
		return 0.30
	return CartonFactory.height(CartonFactory.kind_for(item_type))


func _populate_visual() -> void:
	var pcount := maxi(1, int(_crate_data.get("pack_count", 1)))

	if pcount > 1:
		_visual_holder.add_child(StorageShelfProp.build_stored_visual(_crate_data))
	elif item_type == "slot_build_box":
		_visual_holder.add_child(CartonFactory.build("build", GameState.get_crate_display_label(_crate_data)))
	elif GameState.is_repair_kit(item_type):
		_visual_holder.add_child(StorageShelfProp.build_stored_visual(_crate_data if not _crate_data.is_empty() else {"item_type": item_type}))
	elif item_type == "server_tray":
		var td: Dictionary = _crate_data.get("tray_data", {}) as Dictionary
		var mb_id := str(td.get("mainboard_id", "web_server"))
		var comps: Dictionary = td.get("components", {}) as Dictionary
		var brk := GameState.get_visible_fault(td)
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], brk)
		srv.position = Vector3(0.0, 0.02, 0.0)
		_visual_holder.add_child(srv)
	else:
		var pkg := HardwareMeshFactory.build_item_visual(item_type, _crate_data)
		if item_type == "old_fuse" and ModelLoader.has_custom_model("fuse_d02_blown"):
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
