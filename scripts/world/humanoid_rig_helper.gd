class_name HumanoidRigHelper
extends RefCounted
## Verbindet echte realistische Skeleton3D-Charaktere (Mixamo, MakeHuman / MPFB2, ReadyPlayerMe)
## mit PlayerController, DeliveryDriver und dem 3D-Skin-Editor:
## - Findet Skeleton3D & typische Humanoid-Bones automatisch (inkl. mixamorig12_*, MakeHuman, Rigify)
## - Normalisiert Groesse (~1,74 m), Bodenkontakt (Y=0), Blickrichtung (-Z) und matte Stoff-/Haut-Roughness
## - Senkt Mixamo-T-Pose-Arme automatisch in eine natuerliche stehende Haltung ab
## - Faerbt Materialien (Haut, Jacke/Top, Hose, Haare, Schuhe) live im Skin-Editor ein

const TARGET_HEIGHT := 1.74


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root as Skeleton3D
	for c in root.get_children():
		var found := find_skeleton(c)
		if found != null:
			return found
	return null


static func find_anim_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var found := find_anim_player(c)
		if found != null:
			return found
	return null


static func _strip_rig_prefix(raw_name: String) -> String:
	var bn := raw_name.to_lower()
	if bn.begins_with("mixamorig"):
		var sep := bn.find(":")
		if sep < 0:
			sep = bn.find("_")
		if sep >= 0:
			bn = bn.substr(sep + 1)
	return bn


## Sucht Standard-Humanoid-Bones unabhaengig vom Namensschema (Mixamo, MakeHuman, MPFB2, Rigify).
static func map_bones(skel: Skeleton3D) -> Dictionary:
	var out := {
		"hips": -1, "spine": -1, "chest": -1, "head": -1,
		"thigh_l": -1, "thigh_r": -1, "knee_l": -1, "knee_r": -1,
		"arm_l": -1, "arm_r": -1, "forearm_l": -1, "forearm_r": -1,
	}
	if skel == null:
		return out
	for i in range(skel.get_bone_count()):
		var bn := _strip_rig_prefix(skel.get_bone_name(i))
		if out["hips"] == -1 and (bn == "hips" or bn == "pelvis" or bn == "root"):
			out["hips"] = i
		elif out["head"] == -1 and bn == "head":
			out["head"] = i
		elif out["chest"] == -1 and (bn == "spine2" or bn == "spine1" or bn == "chest" or bn == "upperchest" or bn == "spine02"):
			out["chest"] = i
		elif out["spine"] == -1 and (bn == "spine" or bn == "spine01"):
			out["spine"] = i
		elif out["thigh_l"] == -1 and _match_side(bn, true) and (_has_any(bn, ["upleg", "thigh", "upperleg"])):
			out["thigh_l"] = i
		elif out["thigh_r"] == -1 and _match_side(bn, false) and (_has_any(bn, ["upleg", "thigh", "upperleg"])):
			out["thigh_r"] = i
		elif out["knee_l"] == -1 and _match_side(bn, true) and (_has_any(bn, ["leg", "shin", "calf", "lowerleg"])) and not _has_any(bn, ["upleg", "upperleg", "thigh"]):
			out["knee_l"] = i
		elif out["knee_r"] == -1 and _match_side(bn, false) and (_has_any(bn, ["leg", "shin", "calf", "lowerleg"])) and not _has_any(bn, ["upleg", "upperleg", "thigh"]):
			out["knee_r"] = i
		elif out["forearm_l"] == -1 and _match_side(bn, true) and (_has_any(bn, ["forearm", "lowerarm"])):
			out["forearm_l"] = i
		elif out["forearm_r"] == -1 and _match_side(bn, false) and (_has_any(bn, ["forearm", "lowerarm"])):
			out["forearm_r"] = i
		elif out["arm_l"] == -1 and _match_side(bn, true) and (_has_any(bn, ["arm", "upperarm"])) and not _has_any(bn, ["forearm", "lowerarm"]):
			out["arm_l"] = i
		elif out["arm_r"] == -1 and _match_side(bn, false) and (_has_any(bn, ["arm", "upperarm"])) and not _has_any(bn, ["forearm", "lowerarm"]):
			out["arm_r"] = i
	return out


static func _match_side(bn: String, is_left: bool) -> bool:
	if is_left:
		return bn.contains("left") or bn.ends_with(".l") or bn.ends_with("_l") or bn.begins_with("l_")
	return bn.contains("right") or bn.ends_with(".r") or bn.ends_with("_r") or bn.begins_with("r_")


static func _has_any(s: String, words: Array[String]) -> bool:
	for w in words:
		if s.contains(w):
			return true
	return false


## Skaliert ein importiertes Charakter-Modell sauber auf ~1,74 m Koerpergroesse,
## stellt Fuesse auf Y=0, entfernt Plastik-Glanz auf Kleidung/Haut und senkt T-Pose-Arme ab.
static func normalize_character_root(model: Node3D, face_minus_z: bool = true) -> void:
	if model == null:
		return
	var aabb := _calc_mesh_aabb(model)
	if aabb.size.y > 0.05:
		var scale_f := TARGET_HEIGHT / aabb.size.y
		if absf(scale_f - 1.0) > 0.08:
			model.scale = Vector3.ONE * scale_f
		model.position.y = -aabb.position.y * model.scale.y
	if face_minus_z:
		# Mixamo & MakeHuman exportieren standardmaessig nach +Z -> in Godot nach -Z drehen
		model.rotation_degrees.y = 180.0
	_fix_mixamo_materials(model)
	var skel := find_skeleton(model)
	if skel != null:
		apply_relaxed_standing_pose(skel, map_bones(skel))


## Entfernt den typischen Mixamo-FBX-Plastikglanz auf Stoff, Jeans, Haut und Haaren.
static func _fix_mixamo_materials(model: Node3D) -> void:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var mesh_l := mi.name.to_lower()
				for s in range(mi.mesh.get_surface_count()):
					var sm := mi.mesh.surface_get_material(s)
					if not (sm is StandardMaterial3D):
						continue
					var mname := (sm as StandardMaterial3D).resource_name.to_lower()
					var dup := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
					_tune_material_roughness(dup, mname, mesh_l)
					mi.set_surface_override_material(s, dup)
		for ch in cur.get_children():
			stack.append(ch)


static func _tune_material_roughness(mat: StandardMaterial3D, mname: String, mesh_l: String) -> void:
	var combined := mname + " " + mesh_l
	mat.roughness_texture = null
	mat.metallic_texture = null
	if _has_any(combined, ["helmet", "glass", "visor"]):
		mat.roughness = 0.28
		mat.metallic = 0.08
	elif _has_any(combined, ["shoe", "boot", "sneaker"]):
		mat.roughness = 0.68
		mat.metallic = 0.02
	elif _has_any(combined, ["hair", "beard", "lash"]):
		mat.roughness = 0.88
		mat.metallic = 0.0
	elif _has_any(combined, ["shirt", "pants", "vest", "jacket", "hoodie", "top", "jeans", "coat", "trouser"]):
		mat.roughness = 0.86
		mat.metallic = 0.0
		mat.metallic_specular = 0.18
	else:
		# Haut / Koerper
		mat.roughness = 0.62
		mat.metallic = 0.0
		mat.metallic_specular = 0.28


static func _calc_mesh_aabb(n: Node) -> AABB:
	var combined := AABB()
	var has_any := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var b := mi.mesh.get_aabb()
				if not has_any:
					combined = b
					has_any = true
				else:
					combined = combined.merge(b)
		for ch in cur.get_children():
			stack.append(ch)
	return combined


## Wendet Skin-Editor-Farben intelligent auf echte Mixamo-/MakeHuman-Materialien an (erhaelt Texturen/Normalmaps!).
static func apply_skin_to_skeleton_model(model: Node3D, skin: Variant, fallback_team_color: Color = Color(0.14, 0.28, 0.54)) -> void:
	if model == null:
		return
	var c := SettingsManager.skin_colors(skin, fallback_team_color)
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var mesh_l := mi.name.to_lower()
				for s in range(mi.mesh.get_surface_count()):
					var sm := mi.mesh.surface_get_material(s)
					if not (sm is StandardMaterial3D):
						continue
					var mname := (sm as StandardMaterial3D).resource_name.to_lower()
					var dup := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
					_tune_material_roughness(dup, mname, mesh_l)
					var key := _classify_slot(mname, mesh_l)
					if not key.is_empty():
						var target_col: Color = c[key]
						if dup.albedo_texture != null and key == "tone":
							dup.albedo_color = target_col.lerp(Color.WHITE, 0.35)
						else:
							dup.albedo_color = target_col
					mi.set_surface_override_material(s, dup)
		for ch in cur.get_children():
			stack.append(ch)


static func _classify_slot(mat_l: String, mesh_l: String) -> String:
	var combined := mat_l + " " + mesh_l
	if _has_any(combined, ["dct_jacket", "jacket", "hoodie", "shirt", "top", "sweater", "coat", "torso", "polo", "vest"]):
		return "jacket"
	if _has_any(combined, ["dct_pants", "pants", "trouser", "jeans", "bottom", "shorts"]):
		return "pants"
	if _has_any(combined, ["dct_hair", "hair", "eyebrow", "beard"]):
		return "hair"
	if _has_any(combined, ["dct_shoes", "shoe", "boot", "sneaker", "footwear"]):
		return "shoes"
	if _has_any(combined, ["dct_accent", "accent", "lanyard", "badge", "cap", "beanie", "helmet"]):
		return "accent"
	if _has_any(combined, ["dct_skin", "skin", "body", "head", "face"]) and not _has_any(combined, ["eye", "teeth", "lash"]):
		return "tone"
	return ""


## Berechnet die charakter-eigenen Skelett-Achsen (up, left, forward) unabhaengig von Blender/FBX-Export-Rotation.
static func get_rig_axes(skel: Skeleton3D, bones: Dictionary) -> Dictionary:
	var up := Vector3.UP
	var left := Vector3.RIGHT
	var hips_i: int = int(bones.get("hips", -1))
	var head_i: int = int(bones.get("head", -1))
	if hips_i >= 0 and head_i >= 0:
		var d := skel.get_bone_global_rest(head_i).origin - skel.get_bone_global_rest(hips_i).origin
		if d.length_squared() > 0.0001:
			up = d.normalized()
	var al_i: int = int(bones.get("arm_l", -1))
	var ar_i: int = int(bones.get("arm_r", -1))
	if al_i >= 0 and ar_i >= 0:
		var d := skel.get_bone_global_rest(al_i).origin - skel.get_bone_global_rest(ar_i).origin
		if d.length_squared() > 0.0001:
			left = d.normalized()
	var fwd := left.cross(up).normalized()
	return {"up": up, "left": left, "fwd": fwd}


## Prueft, ob das Skelett in einer horizontalen T-Pose steht (Arme seitlich ausgestreckt).
static func is_t_pose(skel: Skeleton3D, bones: Dictionary) -> bool:
	var al: int = int(bones.get("arm_l", -1))
	var fl: int = int(bones.get("forearm_l", -1))
	if skel == null or al < 0 or fl < 0:
		return false
	var axes := get_rig_axes(skel, bones)
	var d := (skel.get_bone_global_rest(fl).origin - skel.get_bone_global_rest(al).origin).normalized()
	return absf(d.dot(axes["left"] as Vector3)) > 0.72


## Dreht einen Bone um eine Achse im Skelett-Raum (funktioniert fuer Mixamo, MakeHuman & Rigify gleich).
static func _rotate_bone_skel_space(skel: Skeleton3D, bone_idx: int, skel_q: Quaternion) -> void:
	if skel == null or bone_idx < 0:
		return
	var p_idx := skel.get_bone_parent(bone_idx)
	var parent_q := skel.get_bone_global_rest(p_idx).basis.get_rotation_quaternion() if p_idx >= 0 else Quaternion.IDENTITY
	var rest_q := skel.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
	var local_delta := parent_q.inverse() * skel_q * parent_q
	skel.set_bone_pose_rotation(bone_idx, local_delta * rest_q)


## Senkt T-Pose-Arme natuerlich an den Koerper ab (fuer Skin-Editor & Ruhezustand).
static func apply_relaxed_standing_pose(skel: Skeleton3D, bones: Dictionary) -> void:
	if skel == null:
		return
	set_arm_pose(skel, bones, true, 0.04, 0.0)
	set_arm_pose(skel, bones, false, 0.04, 0.0)
	set_forearm_bend(skel, bones, true, 0.14)
	set_forearm_bend(skel, bones, false, 0.14)


## Steuert einen Oberarm inkl. automatischer T-Pose-Korrektur (forward_rad > 0 = Arm nach vorn heben).
static func set_arm_pose(skel: Skeleton3D, bones: Dictionary, is_left: bool, forward_rad: float, spread_rad: float = 0.0) -> void:
	var idx: int = int(bones.get("arm_l" if is_left else "arm_r", -1))
	if skel == null or idx < 0:
		return
	var axes := get_rig_axes(skel, bones)
	var fwd: Vector3 = axes["fwd"]
	var left: Vector3 = axes["left"]
	var q := Quaternion.IDENTITY
	if is_t_pose(skel, bones):
		var drop := 1.32 - spread_rad
		q = Quaternion(fwd, -drop if is_left else drop)
	elif absf(spread_rad) > 0.001:
		q = Quaternion(fwd, spread_rad if is_left else -spread_rad)
	if absf(forward_rad) > 0.0001:
		q = Quaternion(left, -forward_rad) * q
	_rotate_bone_skel_space(skel, idx, q)


## Beugt den Unterarm am Ellbogen nach vorn/oben (bend_rad > 0 = anwinkeln).
## Beruecksichtigt automatisch, dass T-Pose-Ellbogen in der Rest-Pose um die vertikale Achse (up) beugen.
static func set_forearm_bend(skel: Skeleton3D, bones: Dictionary, is_left: bool, bend_rad: float) -> void:
	var idx: int = int(bones.get("forearm_l" if is_left else "forearm_r", -1))
	if skel == null or idx < 0:
		return
	var axes := get_rig_axes(skel, bones)
	if is_t_pose(skel, bones):
		var up: Vector3 = axes["up"]
		var q := Quaternion(up, -bend_rad if is_left else bend_rad)
		_rotate_bone_skel_space(skel, idx, q)
	else:
		var left: Vector3 = axes["left"]
		_rotate_bone_skel_space(skel, idx, Quaternion(left, -bend_rad))


## Schwenkt Beine/Knie sauber im Skelett-Raum (forward_rad > 0 = nach vorn heben, < 0 = nach hinten beugen).
## Beispiel Sitzen: thigh = +1.48 (Oberschenkel waagerecht nach vorn), knee = -1.48 (Unterschenkel senkrecht nach unten).
static func set_leg_pitch(skel: Skeleton3D, bones: Dictionary, bone_key: String, forward_rad: float) -> void:
	var idx: int = int(bones.get(bone_key, -1))
	if skel == null or idx < 0:
		return
	var axes := get_rig_axes(skel, bones)
	var left: Vector3 = axes["left"]
	_rotate_bone_skel_space(skel, idx, Quaternion(left, -forward_rad))


## Neigt Oberkoerper oder Kopf sauber im Skelett-Raum (lean_fwd_rad > 0 = nach vorn beugen / nicken).
static func set_torso_pitch(skel: Skeleton3D, bones: Dictionary, bone_key: String, lean_fwd_rad: float) -> void:
	var idx: int = int(bones.get(bone_key, -1))
	if skel == null or idx < 0:
		return
	var axes := get_rig_axes(skel, bones)
	var left: Vector3 = axes["left"]
	_rotate_bone_skel_space(skel, idx, Quaternion(left, lean_fwd_rad))


## Dreht einen Bone sauber relativ zu seiner Rest-Pose (fuer prozedurale Lauf-/Trage-/Sitz-Animation).
static func set_bone_euler(skel: Skeleton3D, bone_idx: int, euler_rad: Vector3) -> void:
	if skel == null or bone_idx < 0:
		return
	var rest_q := skel.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
	var delta_q := Quaternion.from_euler(euler_rad)
	skel.set_bone_pose_rotation(bone_idx, rest_q * delta_q)
