class_name DeliveryCrew
extends Node3D
## Eine Figur des Lieferdienstes. DeliveryVan sagt jede Sekunde, wo sie steht und was sie tut,
## hier werden Schritte, Haltung und Drehung weich gemischt.

const VEST := Color(0.05, 0.42, 0.48)
## Arbeitskleidung des Lieferdienstes: Mesh-Endung -> Farbe.
const CLOTHES := {"Vest": Color(0.98, 0.50, 0.06), "Shirt": Color(0.08, 0.36, 0.42), "Pants": Color(0.17, 0.19, 0.23), "Helmet": Color(0.93, 0.94, 0.95), "Boots": Color(0.20, 0.15, 0.11)}

var _body: Node3D
var _skel: Skeleton3D
var _bones: Dictionary = {}
var _pose := PackedFloat32Array([0, 0, 0.2, 0.2, 0.05, 0])
var _phase := 0.0
var _stride := 0.0
var _crouch := 0.0
var _yaw := 0.0
var _last := Vector3.ZERO
var _placed := false
var _tablet: Node3D
var _bubble: Label3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var m := ModelLoader.instantiate_custom_model("delivery_driver_realistic")
	if m != null:
		_body.add_child(m)
		HumanoidRigHelper.normalize_character_root(m, true)
		HumanoidRigHelper.apply_skin_to_skeleton_model(m, {}, VEST)
		dress(m)
		_skel = HumanoidRigHelper.find_skeleton(m)
		if _skel != null:
			_bones = HumanoidRigHelper.map_bones(_skel)
			HumanoidRigHelper.apply_relaxed_standing_pose(_skel, _bones)
	_tablet = Node3D.new()
	_tablet.position = Vector3(0.0, 1.12, -0.36)
	_tablet.rotation_degrees.x = 48.0
	_tablet.visible = false
	_body.add_child(_tablet)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.012, 0.16)
	mi.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.06, 0.06, 0.07)
	mi.material_override = mt
	_tablet.add_child(mi)
	var sc := MeshInstance3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(0.20, 0.004, 0.14)
	sc.mesh = qm
	sc.position.y = 0.008
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.85, 0.92, 1.0)
	ms.emission_enabled = true
	ms.emission = Color(0.7, 0.85, 1.0)
	ms.emission_energy_multiplier = 0.8
	sc.material_override = ms
	_tablet.add_child(sc)
	_bubble = Label3D.new()
	_bubble.position = Vector3(0.0, 2.02, 0.0)
	_bubble.font_size = 30
	_bubble.pixel_size = 0.0030
	_bubble.outline_size = 8
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.modulate = Color(1.0, 0.92, 0.55)
	_bubble.visibility_range_end = 14.0
	add_child(_bubble)


static func dress(m: Node3D, clothes: Dictionary = CLOTHES) -> void:
	for mi_n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		for k in clothes.keys():
			if not str(mi.name).ends_with(k):
				continue
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s) as StandardMaterial3D
				if src == null:
					continue
				var mt := src.duplicate() as StandardMaterial3D
				mt.albedo_texture = null
				mt.albedo_color = clothes[k]
				mt.metallic = 0.0
				mt.roughness = 0.82
				if k == "Vest" and (clothes[k] as Color).get_luminance() > 0.2:
					mt.emission_enabled = true
					mt.emission = clothes[k]
					mt.emission_energy_multiplier = 0.22
				mi.set_surface_override_material(s, mt)


func reset() -> void:
	_placed = false
	visible = false


## st: {"pos", "yaw", "pose", "crouch", "seated", "tablet", "text"}. yaw -> Blickrichtung (Figur schaut nach -Z).
func drive(st: Dictionary, delta: float) -> void:
	visible = bool(st.get("visible", true))
	if not visible:
		_placed = false
		return
	var p: Vector3 = st["pos"]
	var yaw := float(st["yaw"])
	if not _placed:
		_placed = true
		_last = p
		_yaw = yaw
	# Sprünge zwischen zwei Aufgaben werden zu schnellen Schritten.
	var shown := _last.lerp(p, 1.0 - exp(-delta * 14.0)) if _last.distance_to(p) < 2.5 else p
	var d := shown - _last
	_last = shown
	position = shown
	var flat := Vector2(d.x, d.z).length() / maxf(delta, 0.001)
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-delta * 10.0))
	_body.rotation.y = _yaw
	var seated := bool(st.get("seated", false))
	_stride = lerpf(_stride, 0.0 if seated else clampf(flat / 1.4, 0.0, 1.25), 1.0 - exp(-delta * 10.0))
	# Rückwärts gehen: Schritte laufen andersherum.
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, _yaw)
	var dir := -1.0 if d.dot(fwd) < -0.0005 else 1.0
	_phase += delta * dir * (2.0 + minf(flat, 2.2) * 4.4) * (1.0 if flat > 0.05 else 0.0)
	_crouch = lerpf(_crouch, float(st.get("crouch", 0.0)), 1.0 - exp(-delta * 7.0))
	_body.position.y = absf(sin(_phase)) * 0.022 * _stride - _crouch * 0.34
	_tablet.visible = bool(st.get("tablet", false))
	var txt := str(st.get("text", ""))
	if _bubble.text != txt:
		_bubble.text = txt
	if _skel == null:
		return
	var idle := Time.get_ticks_msec() / 1000.0
	var want := NpcWalker.pose(str(st.get("pose", "walk")), _phase if str(st.get("pose", "")) != "wave" else idle * 5.0, _stride)
	_pose = NpcWalker.mix(_pose, want, 1.0 - exp(-delta * 9.0))
	if seated:
		for side in ["l", "r"]:
			HumanoidRigHelper.set_leg_pitch(_skel, _bones, "thigh_" + side, 1.42)
			HumanoidRigHelper.set_leg_pitch(_skel, _bones, "knee_" + side, -1.35)
	else:
		NpcWalker.legs(_skel, _bones, _phase, _stride, _crouch * 0.55)
	NpcWalker.apply(_skel, _bones, _pose)
