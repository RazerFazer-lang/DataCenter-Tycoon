class_name WorkbenchProp
extends Node3D
## Funktionale industrielle 3D-IT-Werkbank (2K PBR aus Blender).
## Zeigt live den Arbeitsgegenstand auf der ESD-Matte: Bausatz-Karton, den halb fertigen Server
## mit jedem einzelnen Teil (WorkbenchPiece) oder den fertigen Server mit Deckel.

const MAT_TOP := 0.886

var workbench_id: String = "wb_main"
var piece: WorkbenchPiece
var _work_holder: Node3D
var _status_lbl: Label3D


var model_id: String = "workshop_workbench"


func setup(p_id: String = "wb_main", p_model: String = "workshop_workbench") -> void:
	workbench_id = p_id
	model_id = p_model
	add_to_group("workbench")
	_build_bench()
	GameState.workbench_changed.connect(_refresh_workpiece)
	GameState.world_snapshot_loaded.connect(_refresh_workpiece)
	GameState.shelf_changed.connect(_on_kits_changed)
	GameState.crates_changed.connect(_on_kits_changed)
	GameState.inventory_changed.connect(_on_kits_changed)
	GameState.bench_supplies_changed.connect(func(): piece.refresh_tools())
	GameState.workbench_hand_moved.connect(_on_hand_moved)
	GameState.workbench_task_rejected.connect(func(task_id: String):
		if workbench_id == GameState.local_bench:
			piece.reject(task_id))
	_refresh_workpiece()


func _build_bench() -> void:
	var model := ModelLoader.instantiate_custom_model(model_id)
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
	_work_holder.position = Vector3(0.0, MAT_TOP, 0.02)
	add_child(_work_holder)

	piece = WorkbenchPiece.new()
	piece.bench_id = workbench_id
	piece.name = "Piece"
	piece.position = Vector3(0.0, MAT_TOP, 0.0)
	add_child(piece)

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


func _on_kits_changed() -> void:
	if not piece.is_empty():
		piece._refresh_visibility()


func _on_hand_moved(data: Dictionary) -> void:
	if str(data.get("b", "wb_main")) != workbench_id:
		return
	# Wer selbst arbeitet, bewegt die Teile direkt.
	var own := data.duplicate()
	own.erase("b")
	if int((GameState.bench_states.get(workbench_id, {}) as Dictionary).get("worker", 0)) != multiplayer.get_unique_id():
		piece.apply_remote_hand(own)


func _refresh_workpiece() -> void:
	if _work_holder == null:
		return
	var prev: String = GameState.set_bench_ctx(workbench_id)
	_show_workpiece()
	GameState.set_bench_ctx(prev)


func _show_workpiece() -> void:
	for c in _work_holder.get_children():
		c.queue_free()

	var wb := GameState.workbench_state
	var mode := str(wb.get("mode", ""))
	if GameState.is_workbench_job():
		piece.sync_from_state(wb)
		if GameState.get_workbench_worker() == 0:
			piece.stop_remote_hand()
	else:
		piece.clear()

	if wb.is_empty():
		_status_lbl.text = tr("IT-WERKBANK  ·  FREI")
		_status_lbl.modulate = Color(0.72, 0.84, 0.94)
		return

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
	elif GameState.is_workbench_job():
		_set_progress_label(mode, lbl)
	elif mode == "ready_tray":
		_status_lbl.text = tr("FERTIG: %s  ·  [E] MITNEHMEN") % lbl
		var q := GameState.get_build_quality(wb)
		if q < 100:
			_status_lbl.text += "\n" + tr("Bauqualität %d %%  ·  [F] ÜBERHOLEN") % q
		_status_lbl.modulate = Color(0.26, 0.92, 0.48)
		var mb_id := str(wb.get("mainboard_id", "web_server"))
		var comps: Dictionary = wb.get("components", {}) as Dictionary
		var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, comps, [], "")
		srv.scale = Vector3.ONE * WorkbenchPiece.S
		_work_holder.add_child(srv)
		var lid := ModelLoader.instantiate_custom_model("asm_lid")
		if lid != null:
			_apply_lid_material(lid)
			lid.position = AssemblyPlan.LID_POS
			srv.add_child(lid)


func _set_progress_label(mode: String, lbl: String) -> void:
	var total := AssemblyPlan.count_total(piece.plan)
	var n := AssemblyPlan.count_done(piece.plan, piece.done)
	var who := GameState.get_workbench_worker()
	var head := tr("ZUSAMMENBAU") if mode == "assembly" else (tr("REPARATUR") if mode == "repair" else tr("ÜBERHOLUNG"))
	_status_lbl.modulate = Color(0.32, 0.82, 0.98) if mode == "assembly" else Color(0.98, 0.36, 0.26)
	if who != 0:
		_status_lbl.text = "%s: %s  ·  %d/%d\n%s" % [head, lbl, n, total, tr("%s arbeitet gerade") % GameState.get_worker_name(who)]
	else:
		_status_lbl.text = "%s: %s  ·  %d/%d  ·  %s" % [head, lbl, n, total, tr("[E] WEITER") if n > 0 else tr("[E] START")]


func _apply_lid_material(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			if m != null:
				var shared := WorkbenchPiece._shared_material(m.resource_name, "asm_lid")
				if shared != null:
					mi.set_surface_override_material(s, shared)
	for c in n.get_children():
		_apply_lid_material(c)
