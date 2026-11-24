class_name ConstructionCrew
extends Node3D
## Live-Bautrupp für gekaufte Gebäude-Upgrades:
## Spawnt Bau-Transporter mit blinkendem Rundumlicht, Absperrband, Leitkegel, Baugerüst,
## 2 animierte Handwerker in Warnwesten & Bauhelmen und eine Live-Fortschrittstafel!

var _sites: Dictionary = {} # uid -> {root, workers, beacon_mat, lbl, sfx_accum}
var _anim_t: float = 0.0


func _ready() -> void:
	GameState.constructions_changed.connect(_sync_constructions)
	GameState.building_upgrades_changed.connect(_sync_constructions)
	_sync_constructions()


func _process(delta: float) -> void:
	if _sites.is_empty():
		return
	_anim_t += delta
	var flash := 1.0 if sin(_anim_t * 9.0) > 0.0 else 0.15
	for uid in _sites.keys():
		var sd: Dictionary = _sites[uid]
		var bm: StandardMaterial3D = sd.get("beacon_mat")
		if bm != null:
			bm.emission_energy_multiplier = flash * 3.8
		var workers: Array = sd.get("workers", [])
		for wi in range(workers.size()):
			var w: Dictionary = workers[wi]
			var skel: Skeleton3D = w.get("skel")
			var bones: Dictionary = w.get("bones", {})
			var body: Node3D = w["root"]
			var phase := _anim_t * 5.8 + float(wi) * 2.1
			if skel != null:
				HumanoidRigHelper.set_arm_pose(skel, bones, false, 0.65 + sin(phase) * 0.45, 0.08)
				HumanoidRigHelper.set_forearm_bend(skel, bones, false, 0.72 + cos(phase) * 0.25)
				HumanoidRigHelper.set_arm_pose(skel, bones, true, 0.25, 0.05)
			if body != null:
				body.position.y = absf(sin(phase * 0.5)) * 0.022
		var lbl: Label3D = sd.get("lbl")
		if lbl != null and GameState.active_constructions.has(uid):
			var ac: Dictionary = GameState.active_constructions[uid]
			var dur := maxf(1.0, float(ac.get("duration", 50.0)))
			var rem := maxf(0.0, float(ac.get("remaining", 0.0)))
			var pct := int(roundf(clampf((1.0 - rem / dur) * 100.0, 0.0, 100.0)))
			var u_name := str((GameState.BUILDING_UPGRADE_CATALOG.get(uid, {}) as Dictionary).get("name", uid))
			lbl.text = "🚧 BAUSTELLE: %s\nBautrupp aktiv  •  %d %%  •  noch %d s" % [u_name, pct, int(ceilf(rem))]
		# Dezentes periodisches Hämmern/Schrauben in Spielernähe
		sd["sfx_accum"] = float(sd.get("sfx_accum", 0.0)) + delta
		if float(sd["sfx_accum"]) >= 2.6:
			sd["sfx_accum"] = 0.0
			var lp := get_tree().get_first_node_in_group("local_player") as Node3D
			var sroot: Node3D = sd["root"]
			if lp != null and sroot != null and lp.global_position.distance_to(sroot.global_position) < 28.0:
				SfxManager.play("snap", -14.0, randf_range(0.82, 1.15))


func _sync_constructions() -> void:
	for uid in _sites.keys():
		if not GameState.active_constructions.has(uid):
			var r: Node3D = _sites[uid]["root"]
			if is_instance_valid(r):
				r.queue_free()
			_sites.erase(uid)
	for uid in GameState.active_constructions.keys():
		if not _sites.has(uid):
			var ac: Dictionary = GameState.active_constructions[uid]
			var site_str := str(ac.get("site", "halle_nord"))
			_spawn_construction_site(str(uid), _get_site_position(str(uid), site_str))


func _get_site_position(uid: String, site_str: String) -> Vector3:
	if site_str == "garage" and not GameState.halle_nord_owned:
		if uid == "upg_pv_solar":
			return Vector3(7.5, 0.0, 7.2)
		return Vector3(-5.0, 0.0, 7.2)
	var o := GameState.HALLE_NORD_ORIGIN
	match uid:
		"upg_pv_solar":
			return o + Vector3(19.0, 0.0, 3.0)
		"upg_diesel_gen":
			return o + Vector3(-16.2, 0.0, 4.0)
		"upg_security_gate":
			return o + Vector3(0.0, 0.0, 15.8)
		"upg_noc_suite":
			return o + Vector3(6.8, 0.0, -3.8)
		"upg_roof_chillers":
			return o + Vector3(-6.5, 0.0, 8.2)
		"upg_cold_aisle_pro":
			return o + Vector3(-1.5, 0.0, 0.2)
	return o + Vector3(0.0, 0.0, 9.0)


func _spawn_construction_site(uid: String, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var is_indoor := (uid == "upg_noc_suite" or uid == "upg_cold_aisle_pro")
	var orange := _mat(Color(0.96, 0.44, 0.06), 0.42, 0.08)
	var white := _mat(Color(0.95, 0.95, 0.96), 0.50, 0.02)
	var yellow := _mat(Color(0.96, 0.78, 0.08), 0.38, 0.12)
	var steel := MatLib.make_brushed_metal(Color(0.62, 0.66, 0.70), 0.35, 0.82)
	var dark := _mat(Color(0.14, 0.16, 0.20), 0.50, 0.40)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.62, 0.08)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.58, 0.06)
	beacon_mat.emission_energy_multiplier = 3.0

	# 1. Absperrkegel + rot-weißes Absperrband rund um die Baustelle
	var half_x := 2.4 if is_indoor else 3.4
	var half_z := 1.8 if is_indoor else 2.6
	for cx in [-half_x, half_x]:
		for cz in [-half_z, half_z]:
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.18
			cm.height = 0.58
			cone.mesh = cm
			cone.material_override = orange
			cone.position = Vector3(float(cx), 0.29, float(cz))
			root.add_child(cone)
			_box(root, Vector3(float(cx), 0.32, float(cz)), Vector3(0.24, 0.09, 0.24), white)
	# Gespanntes Warnband
	_box(root, Vector3(0.0, 0.50, half_z), Vector3(half_x * 2.0, 0.06, 0.02), orange)
	_box(root, Vector3(0.0, 0.50, -half_z), Vector3(half_x * 2.0, 0.06, 0.02), orange)
	_box(root, Vector3(-half_x, 0.50, 0.0), Vector3(0.02, 0.06, half_z * 2.0), orange)
	_box(root, Vector3(half_x, 0.50, 0.0), Vector3(0.02, 0.06, half_z * 2.0), orange)

	# 2. Verzinktes Baugerüst + Material-Palette
	for sx in [-1.2, 1.2]:
		for sz in [-0.6, 0.6]:
			_box(root, Vector3(float(sx), 1.35, float(sz)), Vector3(0.05, 2.70, 0.05), steel)
	_box(root, Vector3(0.0, 1.45, 0.0), Vector3(2.45, 0.06, 1.20), MatLib.get_mat("wood_desk"))
	_box(root, Vector3(0.0, 2.40, 0.60), Vector3(2.45, 0.04, 0.04), steel)

	# 3. Gelber Bau-Transporter mit blinkendem Rundumlicht (nur bei Außen-Baustellen!)
	if not is_indoor:
		var van := ModelLoader.instantiate_custom_model("ext_car_van")
		if van != null:
			van.position = Vector3(-4.2, 0.0, 2.2)
			van.rotation_degrees.y = 28.0
			root.add_child(van)
			_tint_paint(van, Color(0.92, 0.66, 0.08))
		var bcn := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.09
		bm.bottom_radius = 0.11
		bm.height = 0.18
		bcn.mesh = bm
		bcn.material_override = beacon_mat
		bcn.position = Vector3(-4.2, 2.38, 2.2)
		root.add_child(bcn)

	# 4. Zwei animierte Handwerker in Warnwesten & gelben Bauhelmen!
	var workers: Array = []
	var w_positions := [Vector3(-1.45, 0.0, 0.95), Vector3(1.55, 0.0, -0.85)]
	var w_yaws := [35.0, -140.0]
	for wi in range(2):
		var wr := _build_worker_npc(yellow, dark, orange)
		wr["root"].position = w_positions[wi]
		wr["root"].rotation_degrees.y = w_yaws[wi]
		root.add_child(wr["root"])
		workers.append(wr)

	# 5. Große Baustellen-Fortschrittstafel
	_box(root, Vector3(0.0, 1.95, half_z + 0.15), Vector3(2.25, 0.72, 0.06), dark)
	_box(root, Vector3(0.0, 2.32, half_z + 0.15), Vector3(2.28, 0.06, 0.08), yellow)
	var lbl := Label3D.new()
	lbl.text = "🚧 BAUSTELLE AKTIV"
	lbl.font_size = 24
	lbl.pixel_size = 0.0028
	lbl.outline_size = 0
	lbl.position = Vector3(0.0, 1.95, half_z + 0.20)
	lbl.modulate = Color(1.0, 0.88, 0.38)
	root.add_child(lbl)

	_sites[uid] = {
		"root": root,
		"workers": workers,
		"beacon_mat": beacon_mat,
		"lbl": lbl,
		"sfx_accum": 0.0,
	}


func _build_worker_npc(_helmet_mat: Material, _pants_mat: Material, _vest_mat: Material) -> Dictionary:
	var holder := Node3D.new()
	var m := ModelLoader.instantiate_custom_model("delivery_driver_realistic")
	var skel: Skeleton3D = null
	var bones: Dictionary = {}
	if m != null:
		holder.add_child(m)
		HumanoidRigHelper.normalize_character_root(m, true)
		HumanoidRigHelper.apply_skin_to_skeleton_model(m, {}, Color(0.95, 0.46, 0.06))
		skel = HumanoidRigHelper.find_skeleton(m)
		if skel != null:
			bones = HumanoidRigHelper.map_bones(skel)
			HumanoidRigHelper.apply_relaxed_standing_pose(skel, bones)
	return {"root": holder, "skel": skel, "bones": bones}


func _tint_paint(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D and mat.resource_name.find("Car_PaintMat") >= 0:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = col
					mi.set_surface_override_material(i, dup)
	for c in node.get_children():
		_tint_paint(c, col)


func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
