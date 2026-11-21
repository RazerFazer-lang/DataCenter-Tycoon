class_name CrateProp
extends Node3D
## Realistic 3D Hardware Shipping Tray / Packaging:
## Server modules (Web-Server, Storage-NAS, GPU-AI-Server, Rack-Switch) sit openly inside
## protective grey ESD foam trays so you literally see the real 3D Motherboard, CPU, RAM,
## GPU & drive caddies! Larger floor equipment sits in strapped industrial freight crates.

var crate_id: String = ""
var item_type: String = ""

var _label: Label3D
var _area: Area3D


func setup(id: String, p_item_type: String) -> void:
	crate_id = id
	item_type = p_item_type
	_build_geometry()


func apply_data(data: Dictionary) -> void:
	var held_by := int(data.get("held_by", 0))
	if held_by != 0:
		visible = false
		_set_interactable(false)
	else:
		visible = true
		position = data["pos"]
		_set_interactable(true)


func _set_interactable(enabled: bool) -> void:
	if _area == null:
		return
	for child in _area.get_children():
		if child is CollisionShape3D:
			child.disabled = not enabled


func _build_geometry() -> void:
	var cat: Dictionary = GameState.ITEM_CATALOG.get(item_type, {
		"name": item_type,
		"color": Color(0.5, 0.5, 0.5),
	})

	var custom := ModelLoader.instantiate_custom_model("crate")
	if custom != null:
		add_child(custom)
	elif GameState.is_slot_upgradeable(item_type) or item_type == "net_switch":
		# Open-top cardboard + protective ESD foam tray revealing the REAL 3D Server Hardware inside!
		var box_mat := MatLib.get_mat("cardboard")
		var foam_mat := MatLib.get_mat("packing_foam")
		_add_box(self, Vector3(0.0, 0.03, 0.0), Vector3(0.72, 0.06, 0.68), box_mat)
		_add_box(self, Vector3(-0.34, 0.12, 0.0), Vector3(0.04, 0.16, 0.68), box_mat)
		_add_box(self, Vector3(0.34, 0.12, 0.0), Vector3(0.04, 0.16, 0.68), box_mat)
		_add_box(self, Vector3(0.0, 0.12, -0.32), Vector3(0.66, 0.16, 0.04), box_mat)
		_add_box(self, Vector3(0.0, 0.12, 0.32), Vector3(0.66, 0.16, 0.04), box_mat)
		# Dark grey ESD foam corner cushions
		for fx in [-0.29, 0.29]:
			_add_box(self, Vector3(float(fx), 0.11, 0.0), Vector3(0.055, 0.11, 0.58), foam_mat)
		# REAL 3D Open-Top Server Chassis with Motherboard, CPU, RAM, GPU, Fans & Drive Bays!
		var srv := HardwareMeshFactory.build_item_visual(item_type)
		srv.position = Vector3(0.0, 0.085, 0.0)
		add_child(srv)
	else:
		# Realistic strapped industrial freight carton for large equipment (Racks, Coolers, UPS, Cart)
		var pkg := HardwareMeshFactory.build_item_visual(item_type)
		# Das echte Sicherungsmodell bekommt keinen Zusatzfaktor, wie in der Garagen-Ablage.
		# Fällt es auf den Karton zurück, bleibt der bisherige Faktor erhalten.
		var uses_fuse_model := item_type == "old_fuse" and ModelLoader.has_custom_model("fuse_d02_blown")
		if not uses_fuse_model:
			pkg.scale = Vector3(1.12, 1.18, 1.12)
		else:
			# Das Modell ist im Ursprung zentriert (Unterkante bei y = -0.024 m). Um die Höhe anheben, damit es auf dem Boden liegt.
			pkg.position = Vector3(0.0, 0.024, 0.0)
		add_child(pkg)

	_label = Label3D.new()
	_label.text = str(cat["name"])
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


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
