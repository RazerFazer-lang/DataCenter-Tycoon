class_name NpcWalker
extends RefCounted
## Bewegungen für Figuren mit Skelett (Lieferanten, Dieb): gehen, tragen, schieben, in die Hocke,
## greifen, winken, sitzen. Alle Werte in Radiant, blend 0..1 mischt weich ein.

const R := preload("res://scripts/world/humanoid_rig_helper.gd")


## phase läuft mit dem Weg, stride 0 = steht.
static func legs(skel: Skeleton3D, bones: Dictionary, phase: float, stride: float, crouch: float = 0.0) -> void:
	var s := sin(phase)
	var lift_l := maxf(0.0, -cos(phase))
	var lift_r := maxf(0.0, cos(phase))
	var th_l := s * 0.46 * stride + crouch * 1.15
	var th_r := -s * 0.46 * stride + crouch * 1.15
	R.set_leg_pitch(skel, bones, "thigh_l", th_l)
	R.set_leg_pitch(skel, bones, "thigh_r", th_r)
	R.set_leg_pitch(skel, bones, "knee_l", -(lift_l * 0.75 * stride + crouch * 2.0))
	R.set_leg_pitch(skel, bones, "knee_r", -(lift_r * 0.75 * stride + crouch * 2.0))


static func arms(skel: Skeleton3D, bones: Dictionary, l_fwd: float, r_fwd: float, l_bend: float, r_bend: float, spread: float = 0.06) -> void:
	R.set_arm_pose(skel, bones, true, l_fwd, spread)
	R.set_arm_pose(skel, bones, false, r_fwd, spread)
	R.set_forearm_bend(skel, bones, true, l_bend)
	R.set_forearm_bend(skel, bones, false, r_bend)


## pose: [l_fwd, r_fwd, l_bend, r_bend, spread, torso]
static func pose(name: String, phase: float, stride: float) -> PackedFloat32Array:
	var sw := sin(phase) * 0.36 * stride
	match name:
		"carry":
			return PackedFloat32Array([0.52, 0.52, 1.10, 1.10, 0.10, -0.05])
		"push":
			return PackedFloat32Array([0.78, 0.78, 0.55, 0.55, 0.08, 0.16])
		"pull":
			return PackedFloat32Array([-0.35, -0.35, 0.35, 0.35, 0.14, 0.10])
		"reach":
			return PackedFloat32Array([1.10, 1.10, 0.40, 0.40, 0.08, 0.18])
		"low":
			return PackedFloat32Array([0.85, 0.85, 0.35, 0.35, 0.12, 0.55])
		"wave":
			return PackedFloat32Array([0.04, 2.45, 0.18, 0.50 + sin(phase * 1.6) * 0.45, 0.22, 0.0])
		"tablet":
			return PackedFloat32Array([0.50, 0.62, 1.35, 1.10, 0.05, 0.06])
		"drive":
			return PackedFloat32Array([0.85, 0.85, 0.75, 0.75, 0.10, 0.0])
	return PackedFloat32Array([-sw, sw, 0.22 + 0.10 * stride, 0.22 + 0.10 * stride, 0.05, 0.02 * stride])


static func mix(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in a.size():
		out.append(lerpf(a[i], b[i], t))
	return out


static func apply(skel: Skeleton3D, bones: Dictionary, p: PackedFloat32Array) -> void:
	arms(skel, bones, p[0], p[1], p[2], p[3], p[4])
	if bones.has("spine"):
		R.set_torso_pitch(skel, bones, "spine", p[5])
