class_name CableRenderer
extends Node3D
## Renders smooth high-fidelity 3D catenary-sagging Power (yellow) & Network (cyan) cables
## with molded 3D strain-relief plug connectors at both endpoints, plus live preview cable.

const SEGMENTS := 18
const CABLE_RADIUS := 0.022
const RADIAL_SIDES := 8

var _cable_nodes: Dictionary = {} # cable_id -> Node3D
var _power_mat: StandardMaterial3D
var _net_mat: StandardMaterial3D
var _boot_mat: StandardMaterial3D
var _preview_mesh: MeshInstance3D
var _preview_plug: Node3D
var _preview_plug_type: String = ""


func _ready() -> void:
	# Realistic non-glowing matte industrial PVC power & Cat6A Ethernet cables
	_power_mat = StandardMaterial3D.new()
	_power_mat.albedo_color = Color(0.84, 0.64, 0.14)
	_power_mat.roughness = 0.48
	_power_mat.metallic = 0.04
	_power_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_net_mat = StandardMaterial3D.new()
	_net_mat.albedo_color = Color(0.18, 0.44, 0.72)
	_net_mat.roughness = 0.44
	_net_mat.metallic = 0.06
	_net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_boot_mat = StandardMaterial3D.new()
	_boot_mat.albedo_color = Color(0.12, 0.13, 0.14)
	_boot_mat.roughness = 0.52
	_boot_mat.metallic = 0.18

	# Das Kabel in der Hand ist ein echtes 3D-Kabel (gleiches Material wie verlegte Kabel) mit Stecker am Ende.
	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.visible = false
	add_child(_preview_mesh)

	_preview_plug = Node3D.new()
	_preview_plug.visible = false
	add_child(_preview_plug)


func rebuild_cables(cables_dict: Dictionary, port_resolver: Callable) -> void:
	for node in _cable_nodes.values():
		if is_instance_valid(node):
			(node as Node).queue_free()
	_cable_nodes.clear()

	for cid in cables_dict.keys():
		var c: Dictionary = cables_dict[cid]
		var ctype := str(c["cable_type"])
		var p_a: Variant = port_resolver.call(ctype, str(c["from_id"]))
		var p_b: Variant = port_resolver.call(ctype, str(c["to_id"]))
		if p_a == null or p_b == null:
			continue
		var va: Vector3 = p_a
		var vb: Vector3 = p_b
		var cmat := _power_mat if ctype == "power" else _net_mat

		var holder := Node3D.new()
		add_child(holder)

		var mi := MeshInstance3D.new()
		mi.mesh = _build_tube_mesh(va, vb)
		mi.material_override = cmat
		holder.add_child(mi)

		# Molded 3D connector plugs at both endpoints!
		_add_plug_connector(holder, va, cmat)
		_add_plug_connector(holder, vb, cmat)
		_cable_nodes[cid] = holder


func _add_plug_connector(parent: Node3D, pos: Vector3, accent_mat: Material) -> void:
	var boot := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.068, 0.068, 0.085)
	boot.mesh = bm
	boot.material_override = _boot_mat
	boot.position = pos
	parent.add_child(boot)

	var collar := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.074, 0.074, 0.025)
	collar.mesh = cm
	collar.material_override = accent_mat
	collar.position = pos + Vector3(0.0, 0.0, 0.015)
	parent.add_child(collar)


func update_preview_cable(active: bool, cable_type: String, start_pos: Vector3, end_pos: Vector3) -> void:
	if not active:
		_preview_mesh.visible = false
		_preview_plug.visible = false
		return
	var cmat := _power_mat if cable_type == "power" else _net_mat
	_preview_mesh.visible = true
	_preview_mesh.material_override = cmat
	_preview_mesh.mesh = _build_tube_mesh(start_pos, end_pos)

	if _preview_plug_type != cable_type:
		for c in _preview_plug.get_children():
			c.queue_free()
		_add_plug_connector(_preview_plug, Vector3.ZERO, cmat)
		_preview_plug_type = cable_type
	_preview_plug.position = end_pos
	_preview_plug.visible = true


func _build_tube_mesh(a: Vector3, b: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var dist := a.distance_to(b)
	var sag := clampf(dist * 0.22, 0.15, 1.25)

	var points: Array[Vector3] = []
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var pt := a.lerp(b, t)
		var drop := 4.0 * sag * t * (1.0 - t)
		pt.y = maxf(0.05, pt.y - drop)
		points.append(pt)

	var rings: Array = []
	for i in range(points.size()):
		var tangent: Vector3
		if i == 0:
			tangent = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			tangent = (points[i] - points[i - 1]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD

		var up_ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var side := tangent.cross(up_ref).normalized()
		var up := side.cross(tangent).normalized()

		var ring: Array[Vector3] = []
		for s in range(RADIAL_SIDES):
			var angle := TAU * float(s) / float(RADIAL_SIDES)
			var offset := (side * cos(angle) + up * sin(angle)) * CABLE_RADIUS
			ring.append(points[i] + offset)
		rings.append(ring)

	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(RADIAL_SIDES):
			var sn := (s + 1) % RADIAL_SIDES
			var v00: Vector3 = r0[s]
			var v01: Vector3 = r0[sn]
			var v10: Vector3 = r1[s]
			var v11: Vector3 = r1[sn]
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)

	st.generate_normals()
	return st.commit()
