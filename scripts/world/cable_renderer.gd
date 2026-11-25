class_name CableRenderer
extends Node3D
## Strom- (gelb) und Netzwerkkabel (blau) als 3D-Schläuche mit detaillierten Steckern.
## Verlegte Kabel verlassen den Port waagerecht, biegen nach unten und laufen rechtwinklig über den Boden,
## wie in einem echten Serverraum. Strom- und Datenkabel liegen auf getrennten Spuren, Kabelschellen
## halten sie am Boden. Das Kabel in der Hand ist ein Seil mit Schwerkraft und Trägheit, das am Boden
## aufliegt und beim Zielen auf einen Port zur Buchse einrastet (grün = frei, rot = nicht möglich).

const FLOOR_Y := 0.0
const POWER_RADIUS := 0.011
const NET_RADIUS := 0.0072
const RADIAL_SIDES := 14
const POWER_BEND_RADIUS := 0.16 # Kaltgerätekabel sind steifer als Patchkabel
const NET_BEND_RADIUS := 0.10
const BEND_STEPS := 10
const EXIT_LEN := 0.11 # waagerechtes Stück direkt hinter dem Stecker
const LIFT_POWER := 0.115 # Steckerlänge bei Buchsen, die nach oben zeigen
const LIFT_NET := 0.075
const PLUG_INSET := 0.012 # Stecker sitzt etwas in der Buchse
const TYPE_SEPARATION := 0.07 # Abstand zwischen Strom- und Datenspur (Trennung wie im Rechenzentrum)
const LANE_SPACING := 0.026 # Abstand paralleler Kabel gleichen Typs
const LANE_COUNT := 7
const SHORT_RUN := 0.45 # darunter hängt das Kabel frei statt über den Boden zu laufen
const MIN_LEG := 0.30 # kürzere Teilstrecken werden nicht rechtwinklig geführt
const LAID_SLACK := 1.06
const CLIP_SPACING := 0.9 # Abstand der Kabelschellen auf dem Boden
const CLIP_EDGE := 0.28 # erste Schelle hinter einer Biegung
const MIN_POINT_GAP := 0.004
const PRINT_REPEAT := 0.5 # Mantelaufdruck wiederholt sich alle 0,5 m

# Kabel in der Hand (Verlet-Seil)
const ROPE_SEGMENTS := 26
const ROPE_ITERATIONS := 14
const ROPE_GRAVITY := 9.8
const ROPE_DAMPING := 0.985
const ROPE_FLOOR_FRICTION := 0.55
const ROPE_RESET_JUMP := 3.0 # springt die Hand weiter (Teleport), wird das Seil neu aufgebaut
const PREVIEW_SLACK := 1.12
const PREVIEW_EXTRA := 0.25 # zusätzliche Kabellänge in der Hand
const SNAP_SPEED := 14.0

const TARGET_NONE := 0
const TARGET_VALID := 1
const TARGET_INVALID := 2

var _cable_nodes: Dictionary = {} # cable_id -> Node3D
var _cable_keys: Dictionary = {} # cable_id -> Geometrie-Schlüssel (unverändert = nicht neu bauen)

var _power_mat: StandardMaterial3D
var _net_mat: StandardMaterial3D
var _cluster_mat: StandardMaterial3D
var _plug_mat: StandardMaterial3D
var _rj45_mat: StandardMaterial3D
var _metal_mat: StandardMaterial3D
var _clip_mat: StandardMaterial3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D

var _power_head_mesh: BoxMesh
var _power_rib_mesh: BoxMesh
var _power_ring_mesh: CylinderMesh
var _power_boot_mesh: CylinderMesh
var _power_boot_rib_a: CylinderMesh
var _power_boot_rib_b: CylinderMesh
var _net_head_mesh: BoxMesh
var _net_contact_mesh: BoxMesh
var _net_latch_mesh: BoxMesh
var _net_boot_mesh: CylinderMesh
var _net_guard_mesh: BoxMesh
var _clip_power_mesh: ArrayMesh
var _clip_net_mesh: ArrayMesh
var _glow_power_mesh: TorusMesh
var _glow_net_mesh: TorusMesh

var _preview_mesh: MeshInstance3D
var _preview_plug: Node3D
var _preview_start_plug: Node3D
var _preview_glow: MeshInstance3D
var _preview_plug_type: String = ""

var _rope_pts: Array[Vector3] = []
var _rope_prev: Array[Vector3] = []
var _rope_active := false
var _rope_type := ""
var _rope_start := Vector3.ZERO
var _rope_hand := Vector3.ZERO
var _rope_end := Vector3.ZERO
var _rope_target_state := TARGET_NONE
var _rope_snap: Variant = null


func _ready() -> void:
	var jacket_tex := _make_jacket_texture()

	# PVC-Mantel mit seitlichem Aufdruck, wie echte Kaltgeräte- und Cat6A-Kabel
	_power_mat = _make_jacket_mat(Color(0.80, 0.60, 0.12), 0.60, jacket_tex)
	_net_mat = _make_jacket_mat(Color(0.15, 0.38, 0.66), 0.50, jacket_tex)
	_cluster_mat = _make_jacket_mat(Color(0.52, 0.28, 0.74), 0.50, jacket_tex)

	_plug_mat = _make_mat(Color(0.08, 0.08, 0.09), 0.62, 0.0)
	_clip_mat = _make_mat(Color(0.20, 0.21, 0.23), 0.50, 0.0)
	_metal_mat = _make_mat(Color(0.86, 0.72, 0.36), 0.30, 0.9)

	_rj45_mat = _make_mat(Color(0.88, 0.92, 0.94, 0.55), 0.22, 0.0)
	_rj45_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_ok_mat = StandardMaterial3D.new()
	_ok_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ok_mat.albedo_color = Color(0.25, 1.0, 0.45)
	_bad_mat = StandardMaterial3D.new()
	_bad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bad_mat.albedo_color = Color(1.0, 0.30, 0.25)

	# Steckerteile einmal anlegen und für alle Kabel wiederverwenden
	_power_head_mesh = _box(Vector3(0.044, 0.048, 0.030))
	_power_rib_mesh = _box(Vector3(0.047, 0.003, 0.033))
	_power_ring_mesh = _cyl(0.0185, 0.0185, 0.005, 16)
	_power_boot_mesh = _cyl(POWER_RADIUS + 0.0025, 0.017, 0.05, 16)
	_power_boot_rib_a = _cyl(0.0158, 0.0158, 0.003, 16)
	_power_boot_rib_b = _cyl(0.0146, 0.0146, 0.003, 16)

	# Auf die Buchsen der 3D-Modelle abgestimmt (Öffnung 24–28 mm), sonst verschwindet der Stecker darin.
	_net_head_mesh = _box(Vector3(0.0215, 0.032, 0.0185))
	_net_contact_mesh = _box(Vector3(0.0155, 0.004, 0.0015))
	_net_latch_mesh = _box(Vector3(0.0088, 0.024, 0.0018))
	_net_boot_mesh = _cyl(NET_RADIUS + 0.0015, 0.0115, 0.030, 12)
	_net_guard_mesh = _box(Vector3(0.010, 0.016, 0.005))

	_clip_power_mesh = _make_clip_mesh(POWER_RADIUS)
	_clip_net_mesh = _make_clip_mesh(NET_RADIUS)

	_glow_power_mesh = TorusMesh.new()
	_glow_power_mesh.inner_radius = 0.028
	_glow_power_mesh.outer_radius = 0.032
	_glow_net_mesh = TorusMesh.new()
	_glow_net_mesh.inner_radius = 0.0125
	_glow_net_mesh.outer_radius = 0.0155

	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.visible = false
	add_child(_preview_mesh)

	_preview_plug = Node3D.new()
	_preview_plug.visible = false
	add_child(_preview_plug)

	_preview_start_plug = Node3D.new()
	_preview_start_plug.visible = false
	add_child(_preview_start_plug)


func _process(delta: float) -> void:
	if not _rope_active:
		return
	_step_rope(minf(delta, 1.0 / 30.0))
	_draw_rope()


# ------------------------------------------------------------------------------
# Öffentliche API
# ------------------------------------------------------------------------------
## dir_resolver (optional): Callable(cable_type, endpoint_id) -> Vector3, Richtung, in die der Port zeigt.
## Ohne Richtung verlässt das Kabel den Port in Richtung des anderen Endes.
## cable_port_resolver (optional): Callable(cable_id, cable_type, endpoint_id) -> Vector3 oder null.
## Liefert eine eigene Buchse pro Kabel (z. B. Steckdosenleiste); bei null gilt port_resolver.
## cable_dir_resolver (optional): Callable(cable_id, cable_type, endpoint_id) -> Vector3 oder null, Richtung je Buchse.
func rebuild_cables(cables_dict: Dictionary, port_resolver: Callable, dir_resolver: Callable = Callable(), cable_port_resolver: Callable = Callable(), cable_dir_resolver: Callable = Callable()) -> void:
	var ids: Array = cables_dict.keys()
	ids.sort()
	var lane_idx := {"power": 0, "network": 0}
	var seen := {}

	for cid_v in ids:
		var cid := str(cid_v)
		var c: Dictionary = cables_dict[cid_v]
		var ctype := str(c.get("cable_type", "power"))
		var from_id := str(c.get("from_id", ""))
		var to_id := str(c.get("to_id", ""))
		var p_a: Variant = _resolve_port(port_resolver, cable_port_resolver, cid, ctype, from_id)
		var p_b: Variant = _resolve_port(port_resolver, cable_port_resolver, cid, ctype, to_id)
		if not (p_a is Vector3) or not (p_b is Vector3):
			continue
		var va: Vector3 = p_a
		var vb: Vector3 = p_b
		var dr := dir_resolver
		if cable_dir_resolver.is_valid():
			dr = func(ct: String, eid: String) -> Variant:
				var v: Variant = cable_dir_resolver.call(cid, ct, eid)
				if v is Vector3:
					return v
				return dir_resolver.call(ct, eid) if dir_resolver.is_valid() else null
		var n_a := _resolve_dir(dr, ctype, from_id, va, vb)
		var n_b := _resolve_dir(dr, ctype, to_id, vb, va)
		var up_a := _is_upward(dr, ctype, from_id)
		var up_b := _is_upward(dr, ctype, to_id)
		var li := int(lane_idx.get(ctype, 0))
		lane_idx[ctype] = li + 1
		var lane := _lane_offset(ctype, li)

		var key := "%s|%s|%s|%s|%s|%.4f" % [ctype, va, vb, n_a, n_b, lane]
		seen[cid] = true
		var existing: Variant = _cable_nodes.get(cid)
		if str(_cable_keys.get(cid, "")) == key and is_instance_valid(existing) and not (existing as Node).is_queued_for_deletion():
			continue
		_free_cable(cid)

		var radius := _radius_for(ctype)
		# Buchsen, die nach oben zeigen (Leisten): erst senkrecht aus der Buchse, dann im Bogen zur Seite.
		var lift := Vector3.UP * (LIFT_POWER if ctype == "power" else LIFT_NET)
		var pts := _laid_path(va + lift if up_a else va, vb + lift if up_b else vb, n_a, n_b, lane, radius, _bend_for(ctype))
		if up_a:
			pts = _with_lift(va, pts)
		if up_b:
			pts.reverse()
			pts = _with_lift(vb, pts)
			pts.reverse()
		if pts.size() < 2:
			continue
		_cable_nodes[cid] = _build_laid_cable(ctype, pts, radius)
		_cable_keys[cid] = key

	for cid_k in _cable_nodes.keys():
		if not seen.has(cid_k):
			_free_cable(str(cid_k))


## target_state: TARGET_NONE, TARGET_VALID (Port frei) oder TARGET_INVALID (belegt / nicht erlaubt).
## snap_pos: Weltposition der anvisierten Buchse; das Kabelende rastet dorthin ein (null = in der Hand).
func update_preview_cable(active: bool, cable_type: String, start_pos: Vector3, end_pos: Vector3, target_state: int = TARGET_NONE, snap_pos: Variant = null) -> void:
	if not active:
		_rope_active = false
		_preview_mesh.visible = false
		_preview_plug.visible = false
		_preview_start_plug.visible = false
		return
	var needs_reset := not _rope_active or cable_type != _rope_type \
		or _rope_start.distance_to(start_pos) > 0.5 or _rope_hand.distance_to(end_pos) > ROPE_RESET_JUMP
	_rope_type = cable_type
	_rope_start = start_pos
	_rope_hand = end_pos
	_rope_target_state = target_state
	_rope_snap = snap_pos
	if needs_reset:
		_reset_rope(start_pos, end_pos)
	_rope_active = true
	_ensure_preview_plugs(cable_type)


# ------------------------------------------------------------------------------
# Verlegte Kabel
# ------------------------------------------------------------------------------
func _free_cable(cid: String) -> void:
	var node: Variant = _cable_nodes.get(cid)
	if is_instance_valid(node):
		(node as Node).queue_free()
	_cable_nodes.erase(cid)
	_cable_keys.erase(cid)


func _build_laid_cable(ctype: String, pts: Array[Vector3], radius: float) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)

	var mi := MeshInstance3D.new()
	mi.mesh = _build_tube_mesh(pts, radius)
	mi.material_override = _cable_mat(ctype)
	holder.add_child(mi)

	var last := pts.size() - 1
	_attach_plug(holder, ctype, pts[0], pts[1] - pts[0])
	_attach_plug(holder, ctype, pts[last], pts[last - 1] - pts[last])
	_add_floor_clips(holder, pts, radius, _clip_power_mesh if ctype == "power" else _clip_net_mesh)
	return holder


func _resolve_port(port_resolver: Callable, cable_port_resolver: Callable, cid: String, cable_type: String, endpoint_id: String) -> Variant:
	if cable_port_resolver.is_valid():
		var v: Variant = cable_port_resolver.call(cid, cable_type, endpoint_id)
		if v is Vector3:
			return v
	return port_resolver.call(cable_type, endpoint_id)


func _cable_mat(cable_type: String) -> StandardMaterial3D:
	if cable_type == "cluster":
		return _cluster_mat
	return _power_mat if cable_type == "power" else _net_mat


func _radius_for(cable_type: String) -> float:
	return POWER_RADIUS if cable_type == "power" else NET_RADIUS


func _bend_for(cable_type: String) -> float:
	return POWER_BEND_RADIUS if cable_type == "power" else NET_BEND_RADIUS


## Stromkabel liegen immer auf der positiven, Datenkabel auf der negativen Seite der Trasse.
func _lane_offset(cable_type: String, idx: int) -> float:
	var off := TYPE_SEPARATION * 0.5 + float(posmod(idx, LANE_COUNT)) * LANE_SPACING
	# Cluster-Kabel liegen außen neben den Datenkabeln, damit sich die Spuren nicht überlagern.
	if cable_type == "cluster":
		return -(off + TYPE_SEPARATION)
	return off if cable_type == "power" else -off


func _is_upward(dir_resolver: Callable, cable_type: String, endpoint_id: String) -> bool:
	if not dir_resolver.is_valid():
		return false
	var v: Variant = dir_resolver.call(cable_type, endpoint_id)
	return v is Vector3 and (v as Vector3).y > 0.5


## Setzt das senkrechte Stück vor den Pfad und rundet die Ecke ab.
func _with_lift(port: Vector3, pts: Array[Vector3]) -> Array[Vector3]:
	if pts.size() < 2:
		return pts
	var corner: Array[Vector3] = [port, pts[0], pts[0] + (pts[1] - pts[0]).normalized() * 0.03]
	var out := _round_polyline(corner, 0.03)
	for i in range(1, pts.size()):
		out.append(pts[i])
	return _dedupe(out)


func _resolve_dir(dir_resolver: Callable, cable_type: String, endpoint_id: String, pos: Vector3, other: Vector3) -> Vector3:
	if dir_resolver.is_valid():
		var v: Variant = dir_resolver.call(cable_type, endpoint_id)
		if v is Vector3:
			var flat := Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
			if flat.length_squared() > 0.0001:
				flat = flat.normalized()
				# Nach oben zeigende Buchsen dürfen zu beiden Seiten abgehen.
				if (v as Vector3).y > 0.5 and flat.dot(other - pos) < 0.0:
					flat = -flat
				return flat
	var to_other := Vector3(other.x - pos.x, 0.0, other.z - pos.z)
	if to_other.length_squared() > 0.0001:
		return to_other.normalized()
	return Vector3.FORWARD


# ------------------------------------------------------------------------------
# Kabelverlauf
# ------------------------------------------------------------------------------
## Port → waagerecht raus → senkrecht runter → rechtwinklig über den Boden (erst in Port-Richtung, dann quer) → hoch zum Ziel.
func _laid_path(a: Vector3, b: Vector3, n_a: Vector3, n_b: Vector3, lane: float, radius: float, bend: float) -> Array[Vector3]:
	var floor_y := FLOOR_Y + radius
	var a_out := a + n_a * EXIT_LEN
	var b_out := b + n_b * EXIT_LEN
	var run := Vector3(b_out.x - a_out.x, 0.0, b_out.z - a_out.z)

	if run.length() < SHORT_RUN:
		# Kurze Verbindung (z. B. Nachbar-Racks): Kabel hängt frei zwischen den Ports durch
		var short_pts: Array[Vector3] = [a]
		short_pts.append_array(_hang_path(a_out, b_out, LAID_SLACK, radius))
		short_pts.append(b)
		return _round_polyline(_dedupe(short_pts), bend * 0.5)

	var a_floor: Vector3
	var corner: Vector3
	var b_floor: Vector3
	if absf(n_a.x) >= absf(n_a.z):
		a_floor = Vector3(a_out.x, floor_y, a_out.z + lane)
		corner = Vector3(b_out.x + lane, floor_y, a_out.z + lane)
		b_floor = Vector3(b_out.x + lane, floor_y, b_out.z)
	else:
		a_floor = Vector3(a_out.x + lane, floor_y, a_out.z)
		corner = Vector3(a_out.x + lane, floor_y, b_out.z + lane)
		b_floor = Vector3(b_out.x, floor_y, b_out.z + lane)

	var poly: Array[Vector3] = [a, a_out]
	if a_floor.distance_to(corner) < MIN_LEG or corner.distance_to(b_floor) < MIN_LEG:
		# Fast gerade Strecke: direkt verlegen statt mit kurzem Knick
		var side := run.normalized().cross(Vector3.UP) * lane
		poly.append(Vector3(a_out.x, floor_y, a_out.z) + side)
		poly.append(Vector3(b_out.x, floor_y, b_out.z) + side)
	else:
		poly.append(a_floor)
		poly.append(corner)
		poly.append(b_floor)
	poly.append(b_out)
	poly.append(b)
	return _dedupe(_round_polyline(_dedupe(poly), bend))


## Durchhang als Parabel: Bogenlänge ≈ d + 8s²/(3d), daraus ergibt sich der Durchhang s für die gewünschte Länge.
func _hang_path(a: Vector3, b: Vector3, slack: float, radius: float) -> Array[Vector3]:
	var floor_y := FLOOR_Y + radius
	var dist := a.distance_to(b)
	var sag := maxf(0.02, sqrt(maxf(0.0, 3.0 * dist * dist * (slack - 1.0) / 8.0)))
	var out: Array[Vector3] = []
	var samples := 28
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var p := a.lerp(b, t)
		p.y = maxf(floor_y, p.y - 4.0 * sag * t * (1.0 - t))
		out.append(p)
	return out


## Ersetzt jede Ecke durch eine quadratische Bézierkurve, begrenzt auf die halbe Länge der Nachbarsegmente.
func _round_polyline(pts: Array[Vector3], radius: float) -> Array[Vector3]:
	if pts.size() < 3:
		return pts.duplicate()
	var out: Array[Vector3] = [pts[0]]
	for i in range(1, pts.size() - 1):
		var prev := pts[i - 1]
		var cur := pts[i]
		var nxt := pts[i + 1]
		var r := minf(radius, minf(prev.distance_to(cur), cur.distance_to(nxt)) * 0.5)
		if r < 0.001:
			out.append(cur)
			continue
		var p0 := cur + (prev - cur).normalized() * r
		var p2 := cur + (nxt - cur).normalized() * r
		for s in range(BEND_STEPS + 1):
			var t := float(s) / float(BEND_STEPS)
			var u := 1.0 - t
			out.append(p0 * (u * u) + cur * (2.0 * u * t) + p2 * (t * t))
	out.append(pts[pts.size() - 1])
	return out


func _dedupe(pts: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > MIN_POINT_GAP:
			out.append(p)
	return out


## Kabelschellen in festen Abständen auf allen Stücken, die flach auf dem Boden liegen.
func _add_floor_clips(holder: Node3D, pts: Array[Vector3], radius: float, mesh: Mesh) -> void:
	var floor_y := FLOOR_Y + radius
	var run := 0.0
	var next_at := CLIP_EDGE
	for i in range(pts.size() - 1):
		var p := pts[i]
		var q := pts[i + 1]
		if absf(p.y - floor_y) > 0.002 or absf(q.y - floor_y) > 0.002:
			run = 0.0
			next_at = CLIP_EDGE
			continue
		var seg := p.distance_to(q)
		if seg < 0.000001:
			continue
		while run + seg >= next_at:
			var clip := MeshInstance3D.new()
			clip.mesh = mesh
			clip.material_override = _clip_mat
			clip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			clip.transform = Transform3D(_orient_basis(q - p), p.lerp(q, (next_at - run) / seg))
			holder.add_child(clip)
			next_at += CLIP_SPACING
		run += seg


# ------------------------------------------------------------------------------
# Kabel in der Hand
# ------------------------------------------------------------------------------
func _reset_rope(start: Vector3, end: Vector3) -> void:
	_rope_pts.clear()
	_rope_prev.clear()
	for i in range(ROPE_SEGMENTS + 1):
		var p := start.lerp(end, float(i) / float(ROPE_SEGMENTS))
		_rope_pts.append(p)
		_rope_prev.append(p)
	_rope_end = end


func _step_rope(delta: float) -> void:
	var n := _rope_pts.size()
	if n < 3:
		return
	var floor_y := FLOOR_Y + _radius_for(_rope_type)
	var goal := _rope_hand
	if _rope_snap is Vector3:
		goal = _rope_snap
	_rope_end = _rope_end.lerp(goal, clampf(delta * SNAP_SPEED, 0.0, 1.0))

	var seg_len := maxf(0.01, (_rope_start.distance_to(_rope_end) * PREVIEW_SLACK + PREVIEW_EXTRA) / float(n - 1))
	var gravity := Vector3(0.0, -ROPE_GRAVITY * delta * delta, 0.0)
	for i in range(1, n - 1):
		var p := _rope_pts[i]
		var vel := (p - _rope_prev[i]) * ROPE_DAMPING
		if p.y <= floor_y + 0.001:
			vel.x *= ROPE_FLOOR_FRICTION
			vel.z *= ROPE_FLOOR_FRICTION
		_rope_prev[i] = p
		_rope_pts[i] = p + vel + gravity
	_rope_pts[0] = _rope_start
	_rope_pts[n - 1] = _rope_end

	for _it in range(ROPE_ITERATIONS):
		for i in range(n - 1):
			var a := _rope_pts[i]
			var b := _rope_pts[i + 1]
			var d := b - a
			var l := d.length()
			if l < 0.000001:
				continue
			var wa := 0.0 if i == 0 else 0.5
			var wb := 0.0 if i + 1 == n - 1 else 0.5
			var wsum := wa + wb
			if wsum <= 0.0:
				continue
			var corr := d * ((l - seg_len) / l)
			_rope_pts[i] = a + corr * (wa / wsum)
			_rope_pts[i + 1] = b - corr * (wb / wsum)
		for i in range(1, n - 1):
			if _rope_pts[i].y < floor_y:
				var q := _rope_pts[i]
				q.y = floor_y
				_rope_pts[i] = q


func _draw_rope() -> void:
	var pts := _dedupe(_rope_pts)
	if pts.size() < 2:
		_preview_mesh.visible = false
		_preview_plug.visible = false
		_preview_start_plug.visible = false
		return
	_preview_mesh.mesh = _build_tube_mesh(pts, _radius_for(_rope_type))
	_preview_mesh.material_override = _cable_mat(_rope_type)
	_preview_mesh.visible = true

	var last := pts.size() - 1
	_preview_plug.transform = Transform3D(_orient_basis(pts[last - 1] - pts[last]), pts[last])
	_preview_plug.visible = true
	var start_basis := _orient_basis(pts[1] - pts[0])
	_preview_start_plug.transform = Transform3D(start_basis, pts[0] - start_basis.y * PLUG_INSET)
	_preview_start_plug.visible = true

	if _preview_glow != null:
		_preview_glow.visible = _rope_target_state != TARGET_NONE
		_preview_glow.material_override = _ok_mat if _rope_target_state == TARGET_VALID else _bad_mat


func _ensure_preview_plugs(cable_type: String) -> void:
	if _preview_plug_type == cable_type:
		return
	for c in _preview_plug.get_children():
		c.queue_free()
	for c in _preview_start_plug.get_children():
		c.queue_free()
	_preview_plug.add_child(_make_plug(cable_type))
	_preview_start_plug.add_child(_make_plug(cable_type))

	_preview_glow = MeshInstance3D.new()
	_preview_glow.mesh = _glow_power_mesh if cable_type == "power" else _glow_net_mesh
	_preview_glow.position = Vector3(0.0, 0.022 if cable_type == "power" else 0.010, 0.0)
	_preview_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_glow.visible = false
	_preview_plug.add_child(_preview_glow)
	_preview_plug_type = cable_type


# ------------------------------------------------------------------------------
# Geometrie
# ------------------------------------------------------------------------------
## Rohr mit Parallel-Transport-Rahmen (verdreht sich in Kurven nicht) und weichen Normalen.
## UV: u = Umfang, v = Länge in Metern (für den Mantelaufdruck).
func _build_tube_mesh(pts: Array[Vector3], radius: float) -> ArrayMesh:
	var count := pts.size()
	if count < 2:
		return ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var t0 := (pts[1] - pts[0]).normalized()
	var ref0 := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := t0.cross(ref0).normalized()
	var v_len := 0.0

	for i in range(count):
		var tangent: Vector3
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == count - 1:
			tangent = pts[i] - pts[i - 1]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		tangent = tangent.normalized()

		normal = normal - tangent * normal.dot(tangent)
		if normal.length_squared() < 0.00000001:
			var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			normal = tangent.cross(ref)
		normal = normal.normalized()
		var binormal := tangent.cross(normal).normalized()

		if i > 0:
			v_len += pts[i].distance_to(pts[i - 1])
		for s in range(RADIAL_SIDES + 1):
			var ang := TAU * float(s) / float(RADIAL_SIDES)
			var dir := normal * cos(ang) + binormal * sin(ang)
			st.set_normal(dir)
			st.set_uv(Vector2(float(s) / float(RADIAL_SIDES), v_len))
			st.add_vertex(pts[i] + dir * radius)

	var ring := RADIAL_SIDES + 1
	for i in range(count - 1):
		for s in range(RADIAL_SIDES):
			var i00 := i * ring + s
			var i01 := i00 + 1
			var i10 := i00 + ring
			var i11 := i10 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)
	return st.commit()


## Lokale +Y-Achse zeigt vom Port weg in Kabelrichtung (bei waagerechtem Kabel zeigt +Z nach oben).
func _orient_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.DOWN
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _attach_plug(parent: Node3D, cable_type: String, port_pos: Vector3, cable_dir: Vector3) -> void:
	var plug := _make_plug(cable_type)
	var plug_basis := _orient_basis(cable_dir)
	plug.transform = Transform3D(plug_basis, port_pos - plug_basis.y * PLUG_INSET)
	parent.add_child(plug)


## Kaltgerätestecker (Griffrillen, Farbring, Knickschutz) bzw. RJ45 (klarer Kopf, Goldkontakte, Rastnase, Schutzkappe).
func _make_plug(cable_type: String) -> Node3D:
	var plug := Node3D.new()
	if cable_type == "power":
		_add_part(plug, _power_head_mesh, _plug_mat, Vector3(0.0, 0.024, 0.0))
		for rib_y in [0.029, 0.036, 0.043]:
			_add_part(plug, _power_rib_mesh, _plug_mat, Vector3(0.0, float(rib_y), 0.0))
		_add_part(plug, _power_ring_mesh, _power_mat, Vector3(0.0, 0.0505, 0.0))
		_add_part(plug, _power_boot_mesh, _plug_mat, Vector3(0.0, 0.078, 0.0))
		_add_part(plug, _power_boot_rib_a, _plug_mat, Vector3(0.0, 0.066, 0.0))
		_add_part(plug, _power_boot_rib_b, _plug_mat, Vector3(0.0, 0.080, 0.0))
	else:
		_add_part(plug, _net_head_mesh, _rj45_mat, Vector3(0.0, 0.014, 0.0))
		_add_part(plug, _net_contact_mesh, _metal_mat, Vector3(0.0, 0.0035, 0.0093))
		_add_part(plug, _net_latch_mesh, _rj45_mat, Vector3(0.0, 0.014, -0.0108), Vector3(-0.18, 0.0, 0.0))
		_add_part(plug, _net_boot_mesh, _net_mat, Vector3(0.0, 0.044, 0.0))
		_add_part(plug, _net_guard_mesh, _net_mat, Vector3(0.0, 0.034, -0.0105))
	return plug


func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Bodenschelle: Bügel über dem Kabel, zwei Seitenwangen und zwei Schraublaschen.
## Lokal: +Y entlang des Kabels, +Z nach oben, Kabelmitte im Ursprung.
func _make_clip_mesh(radius: float) -> ArrayMesh:
	var strap := _box(Vector3(radius * 2.0 + 0.014, 0.012, 0.003))
	var cheek := _box(Vector3(0.005, 0.012, radius * 2.0 + 0.003))
	var tab := _box(Vector3(0.008, 0.012, 0.0015))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(strap, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, radius + 0.0015)))
	for side in [-1.0, 1.0]:
		var sx := float(side)
		st.append_from(cheek, 0, Transform3D(Basis.IDENTITY, Vector3(sx * (radius + 0.0045), 0.0, 0.0)))
		st.append_from(tab, 0, Transform3D(Basis.IDENTITY, Vector3(sx * (radius + 0.010), 0.0, -radius + 0.00075)))
	return st.commit()


## Graustufen-Textur für den Mantel: leichtes Rauschen plus Aufdruck-Striche auf einer Seite.
func _make_jacket_texture() -> ImageTexture:
	var w := 16
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(h):
		for x in range(w):
			var v := 0.93 + rng.randf() * 0.07
			img.set_pixel(x, y, Color(v, v, v))
	for y in range(8, 44):
		if posmod(y, 5) < 3:
			for x in range(0, 2):
				img.set_pixel(x, y, Color(0.42, 0.42, 0.42))
	return ImageTexture.create_from_image(img)


func _make_jacket_mat(col: Color, rough: float, tex: Texture2D) -> StandardMaterial3D:
	var m := _make_mat(col, rough, 0.0)
	m.albedo_texture = tex
	m.uv1_scale = Vector3(1.0, 1.0 / PRINT_REPEAT, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top_r: float, bottom_r: float, height: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = sides
	return c