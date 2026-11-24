class_name WorkbenchProp
extends Node3D
## Funktionale industrielle 3D-IT-Werkbank (2K PBR aus Blender).
## Zeigt live den aktuellen Arbeitsgegenstand auf der ESD-Matte (Bausatz-Karton,
## zerlegter Bausatz, defekter Server-Schlitten oder fertiger Server).

var workbench_id: String = "wb_main"
var _work_holder: Node3D
var _status_lbl: Label3D


func setup(p_id: String = "wb_main") -> void:
	workbench_id = p_id
	_build_bench()
	GameState.workbench_changed.connect(_refresh_workpiece)
	GameState.world_snapshot_loaded.connect(_refresh_workpiece)
	_refresh_workpiece()


func _build_bench() -> void:
	var model := ModelLoader.instantiate_custom_model("workshop_workbench")
	if model != null:
		add_child(model)
	else:
		add_child(BuildingPropFactory.build_hardware_workbench())

	# Warmes Arbeitslicht direkt unter der LED-Leiste
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 1.66, 0.06)
	lamp.light_color = Color(0.96, 0.98, 1.0)
	lamp.light_energy = 1.15
	lamp.omni_range = 3.2
	lamp.shadow_enabled = false
	add_child(lamp)

	# Ablage-Anker mittig auf der ESD-Matte (Oberkante y = 0.885 m)
	_work_holder = Node3D.new()
	_work_holder.position = Vector3(0.12, 0.886, 0.04)
	add_child(_work_holder)

	# Status-Anzeige an der Lochwand
	_status_lbl = Label3D.new()
	_status_lbl.text = tr("IT-WERKBANK BEREIT")
	_status_lbl.font_size = 24
	_status_lbl.pixel_size = 0.0017
	_status_lbl.outline_size = 3
	_status_lbl.outline_modulate = Color(0.03, 0.04, 0.06)
	_status_lbl.shaded = false
	_status_lbl.double_sided = false
	_status_lbl.position = Vector3(0.12, 1.56, -0.35)
	_status_lbl.visibility_range_end = 8.5
	add_child(_status_lbl)

	# Interaktions-Area ueber der Arbeitsflaeche
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.56, 1.10, 0.86)
	col.shape = sh
	col.position = Vector3(0.0, 0.95, 0.0)
	area.add_child(col)
	area.set_meta("interact_type", "workbench")
	area.set_meta("entity_id", workbench_id)
	add_child(area)


func _refresh_workpiece() -> void:
	if _work_holder == null:
		return
	for c in _work_holder.get_children():
		c.queue_free()

	var wb := GameState.workbench_state
	if wb.is_empty():
		_status_lbl.text = tr("IT-WERKBANK  ·  FREI")
		_status_lbl.modulate = Color(0.72, 0.84, 0.94)
		return

	var mode := str(wb.get("mode", ""))
	var lbl := str(wb.get("label", "Server"))
	if mode == "build_box":
		_status_lbl.text = tr("BAUSATZ: %s  ·  [E] AUSPACKEN") % lbl
		_status_lbl.modulate = Color(0.95, 0.78, 0.24)
		var box_m := ModelLoader.instantiate_custom_model("delivery_build_box")
		if box_m != null:
			_work_holder.add_child(box_m)
		var tl := Label3D.new()
		tl.text = lbl
		tl.font_size = 24
		tl.pixel_size = 0.0014
		tl.modulate = Color(0.06, 0.08, 0.12)
		tl.outline_size = 0
		tl.shaded = false
		tl.position = Vector3(0.0, 0.225, 0.06)
		tl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_work_holder.add_child(tl)
	elif mode == "assembly":
		_status_lbl.text = tr("ZUSAMMENBAU: %s  ·  [E] MONTIEREN") % lbl
		_status_lbl.modulate = Color(0.32, 0.82, 0.98)
		var mb_id := str(wb.get("mainboard_id", "web_server"))
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, {}, [], "")
		srv.scale = Vector3(0.72, 0.72, 0.72)
		_work_holder.add_child(srv)
	elif mode == "repair":
		_status_lbl.text = tr("REPARATUR: %s  ·  [E] REPARIEREN") % lbl
		_status_lbl.modulate = Color(0.98, 0.36, 0.26)
		var mb_id := str(wb.get("mainboard_id", "web_server"))
		var comps: Dictionary = wb.get("components", {}) as Dictionary
		var fcat := str(wb.get("faulty_part", "mainboard"))
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], fcat)
		srv.scale = Vector3(0.72, 0.72, 0.72)
		_work_holder.add_child(srv)
	elif mode == "ready_tray":
		_status_lbl.text = tr("FERTIG: %s  ·  [E] MITNEHMEN") % lbl
		_status_lbl.modulate = Color(0.26, 0.92, 0.48)
		var mb_id := str(wb.get("mainboard_id", "web_server"))
		var comps: Dictionary = wb.get("components", {}) as Dictionary
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], "")
		srv.scale = Vector3(0.72, 0.72, 0.72)
		_work_holder.add_child(srv)
