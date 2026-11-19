extends Node3D
## Sackkarre des CLOUD-EXPRESS-Fahrers (rein visuell, keine Kollision).
## Ursprung am Boden unter der Radachse. Die Schaufel zeigt nach -Z, die Griffe nach oben und leicht nach +Z.
## Kippen dreht den Rahmen um die Radachse (positiver Winkel = Griffe Richtung +Z).

const WHEEL_RADIUS := 0.13
const WHEEL_X := 0.255
const RAIL_X := 0.19
const FRAME_Z := -0.05
const FRAME_TOP := 1.05 # über der Achse
const FRAME_BOTTOM := -0.11 # unter der Achse, Schaufel knapp über dem Boden
const MAX_CRATES := 4
const CRATE_SIZE := Vector3(0.40, 0.27, 0.34)

var _pivot: Node3D
var _wheels: Array[Node3D] = []
var _crates: Array[Node3D] = []
var _spin: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _has_last_pos: bool = false


func _ready() -> void:
	_ensure_built()


## Setzt Lage, Kippwinkel (Radiant) und die Zahl der sichtbaren Kartons.
## Die Räder drehen sich passend zur zurückgelegten Strecke.
func set_pose(pos: Vector3, yaw: float, tilt: float, crate_count: int) -> void:
	_ensure_built()
	if _has_last_pos:
		var moved := pos - _last_pos
		moved.y = 0.0
		var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
		_spin = wrapf(_spin - moved.dot(forward) / WHEEL_RADIUS, -TAU, TAU)
	_last_pos = pos
	_has_last_pos = true
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	_pivot.rotation.x = tilt
	for w in _wheels:
		w.rotation.x = _spin
	var n := clampi(crate_count, 0, MAX_CRATES)
	for i in range(_crates.size()):
		_crates[i].visible = i < n


## Nach einem Sprung (z. B. aus dem Laderaum) sollen sich die Räder nicht schlagartig drehen.
func reset_motion() -> void:
	_has_last_pos = false


func _ensure_built() -> void:
	if _pivot != null:
		return
	var steel := _mat(Color(0.16, 0.30, 0.52), 0.42, 0.55) # blau pulverbeschichtetes Stahlrohr
	var plate := _mat(Color(0.62, 0.64, 0.67), 0.38, 0.85) # Riffelblech
	var rubber := _mat(Color(0.06, 0.06, 0.065), 0.92, 0.0)
	var rim_mat := _mat(Color(0.80, 0.62, 0.14), 0.45, 0.35)
	var grip_mat := _mat(Color(0.09, 0.09, 0.10), 0.85, 0.0)
	var tape_mat := _mat(Color(0.74, 0.62, 0.42), 0.50, 0.0)
	var label_mat := _mat(Color(0.93, 0.93, 0.90), 0.60, 0.0)
	var cardboard: Material = MatLib.get_mat("cardboard")

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, WHEEL_RADIUS, 0.0)
	add_child(_pivot)

	# Rahmen: zwei Holme mit gebogenen Griffen und Achshaltern
	var rail_h := FRAME_TOP - FRAME_BOTTOM
	for sx in [-RAIL_X, RAIL_X]:
		var x := float(sx)
		_add_cyl(_pivot, Vector3(x, FRAME_BOTTOM + rail_h * 0.5, FRAME_Z), 0.016, rail_h, steel, Vector3.ZERO)
		_add_sphere(_pivot, Vector3(x, FRAME_TOP, FRAME_Z), 0.017, steel)
		_add_cyl(_pivot, Vector3(x, FRAME_TOP + 0.035, FRAME_Z + 0.07), 0.016, 0.15, steel, Vector3(62.0, 0.0, 0.0))
		_add_cyl(_pivot, Vector3(x, FRAME_TOP + 0.08, FRAME_Z + 0.195), 0.021, 0.12, grip_mat, Vector3(80.0, 0.0, 0.0))
		_add_box(_pivot, Vector3(x, -0.02, FRAME_Z + 0.025), Vector3(0.03, 0.13, 0.06), steel)
		_add_box(_pivot, Vector3(x, FRAME_BOTTOM + 0.05, FRAME_Z - 0.05), Vector3(0.02, 0.10, 0.10), steel)

	# Querstreben
	for y in [0.12, 0.45, 0.78]:
		_add_cyl(_pivot, Vector3(0.0, float(y), FRAME_Z), 0.011, RAIL_X * 2.0, steel, Vector3(0.0, 0.0, 90.0))
	_add_cyl(_pivot, Vector3(0.0, FRAME_TOP - 0.02, FRAME_Z), 0.014, RAIL_X * 2.0, steel, Vector3(0.0, 0.0, 90.0))

	# Radachse
	_add_cyl(_pivot, Vector3.ZERO, 0.012, WHEEL_X * 2.0 - 0.02, steel, Vector3(0.0, 0.0, 90.0))

	# Schaufel aus Riffelblech mit Rippen und Vorderkante
	_add_box(_pivot, Vector3(0.0, FRAME_BOTTOM + 0.006, FRAME_Z - 0.15), Vector3(0.44, 0.012, 0.30), plate)
	for i in range(5):
		_add_box(_pivot, Vector3(0.0, FRAME_BOTTOM + 0.0135, FRAME_Z - 0.04 - float(i) * 0.055), Vector3(0.40, 0.004, 0.012), plate)
	_add_box(_pivot, Vector3(0.0, FRAME_BOTTOM + 0.015, FRAME_Z - 0.30), Vector3(0.44, 0.03, 0.012), plate)

	# Kartons auf der Schaufel, leicht versetzt gestapelt
	var jitter_x: Array[float] = [0.0, 0.018, -0.012, 0.010]
	var jitter_yaw: Array[float] = [0.0, 2.5, -3.0, 1.5]
	for i in range(MAX_CRATES):
		var crate := Node3D.new()
		crate.position = Vector3(
			jitter_x[i],
			FRAME_BOTTOM + 0.012 + CRATE_SIZE.y * (float(i) + 0.5) + 0.002 * float(i),
			FRAME_Z - 0.006 - CRATE_SIZE.z * 0.5
		)
		crate.rotation_degrees.y = jitter_yaw[i]
		_pivot.add_child(crate)
		_add_box(crate, Vector3.ZERO, CRATE_SIZE, cardboard)
		_add_box(crate, Vector3(0.0, CRATE_SIZE.y * 0.5 + 0.002, 0.0), Vector3(0.06, 0.004, CRATE_SIZE.z + 0.004), tape_mat)
		_add_box(crate, Vector3(0.08, 0.02, -CRATE_SIZE.z * 0.5 - 0.002), Vector3(0.12, 0.08, 0.004), label_mat)
		crate.visible = false
		_crates.append(crate)

	# Räder: Gummireifen, Felge, Nabe und Speichen (damit man das Drehen sieht)
	for sx in [-WHEEL_X, WHEEL_X]:
		var w := Node3D.new()
		w.position = Vector3(float(sx), WHEEL_RADIUS, 0.0)
		add_child(w)
		_add_cyl(w, Vector3.ZERO, WHEEL_RADIUS, 0.075, rubber, Vector3(0.0, 0.0, 90.0))
		_add_cyl(w, Vector3.ZERO, 0.075, 0.082, rim_mat, Vector3(0.0, 0.0, 90.0))
		_add_cyl(w, Vector3.ZERO, 0.025, 0.092, plate, Vector3(0.0, 0.0, 90.0))
		for k in range(3):
			var spoke := _add_box(w, Vector3.ZERO, Vector3(0.086, 0.15, 0.022), plate)
			spoke.rotation.x = float(k) * PI / 3.0
		_wheels.append(w)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _add_sphere(parent: Node3D, pos: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
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