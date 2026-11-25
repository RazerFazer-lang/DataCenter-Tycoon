class_name CartonFactory
extends RefCounted
## Versandkartons aus tools/blender/build_paket_a.py: je Warenart ein Modell mit beweglichen Klappen.
## Die Pappe teilt sich eine Textur (assets/textures/carton), damit die Modelle klein bleiben.

## Art -> [Breite, Höhe, Tiefe, Bodenhöhe (Palette/Kufen), Aufkleberbreite, Aufkleberhöhe]
const SIZES := {
	"server": [0.64, 0.20, 0.58, 0.0, 0.20, 0.133],
	"build": [0.50, 0.24, 0.42, 0.0, 0.20, 0.133],
	"cooler": [0.62, 0.46, 0.54, 0.0, 0.20, 0.133],
	"ups": [0.52, 0.44, 0.46, 0.062, 0.20, 0.133],
	"strip": [0.70, 0.10, 0.17, 0.0, 0.13, 0.086],
	"deco": [0.60, 0.36, 0.52, 0.0, 0.20, 0.133],
	"parcel": [0.42, 0.26, 0.32, 0.0, 0.17, 0.113],
	"pallet": [0.62, 0.36, 0.50, 0.10, 0.20, 0.133],
}
## Pfandgeld für einen leeren Karton im Altpapier-Container.
const REFUND := {"server": 3, "build": 2, "cooler": 5, "ups": 4, "strip": 1, "deco": 4, "parcel": 2, "pallet": 8}

static var _mats: Dictionary = {}


static func kind_for(item_type: String) -> String:
	if item_type == "slot_build_box":
		return "build"
	if item_type == "parts_parcel":
		return "parcel"
	if item_type.begins_with("rack"):
		return "pallet"
	if item_type.begins_with("ups"):
		return "ups"
	if GameState.is_strip_type(item_type):
		return "strip"
	if GameState.is_heat_pump_type(item_type) or GameState.is_floor_cooler_type(item_type) or item_type == GameState.INDOOR_UNIT_TYPE:
		return "cooler"
	if GameState.is_slot_upgradeable(item_type) or item_type == "net_switch":
		return "server"
	return "deco"


static func refund(kind: String) -> int:
	return int(REFUND.get(kind, 2))


static func height(kind: String) -> float:
	var s: Array = SIZES.get(kind, SIZES["deco"])
	return float(s[1]) + float(s[3])


## Baut einen Karton. label = Produktname auf dem Aufkleber, open 0 = zu, 1 = Klappen ganz offen.
static func build(kind: String, label: String = "", open: float = 0.0) -> Node3D:
	if not SIZES.has(kind):
		kind = "deco"
	var root := ModelLoader.instantiate_custom_model("carton_" + kind)
	if root == null:
		root = Node3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SIZES[kind][0], SIZES[kind][1], SIZES[kind][2])
		mi.mesh = bm
		mi.material_override = MatLib.get_mat("cardboard")
		mi.position.y = float(SIZES[kind][3]) + bm.size.y * 0.5
		root.add_child(mi)
	_dress(root)
	root.set_meta("carton_kind", kind)
	if label != "":
		_add_label(root, kind, label)
	set_open(root, open)
	return root


## Klappen 0..1 öffnen. Das Klebeband reißt gleich zu Beginn ab.
static func set_open(root: Node3D, t: float) -> void:
	var inner := clampf((t - 0.35) / 0.65, 0.0, 1.0)
	var outer := clampf(t / 0.70, 0.0, 1.0)
	_flap(root, "Flap_F", Vector3.RIGHT, deg_to_rad(212.0) * _ease(outer))
	_flap(root, "Flap_B", Vector3.RIGHT, -deg_to_rad(206.0) * _ease(outer))
	_flap(root, "Flap_L", Vector3.BACK, deg_to_rad(202.0) * _ease(inner))
	_flap(root, "Flap_R", Vector3.BACK, -deg_to_rad(208.0) * _ease(inner))
	var tape := root.find_child("Tape", true, false) as Node3D
	if tape != null:
		tape.visible = t < 0.02
	for part in ["Film_Glass", "Straps"]:
		var pn := root.find_child(str(part), true, false) as Node3D
		if pn != null:
			pn.visible = t < 0.02


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _flap(root: Node3D, n: String, axis: Vector3, angle: float) -> void:
	var f := root.find_child(n, true, false) as Node3D
	if f != null:
		f.basis = Basis(axis, angle)


static func _add_label(root: Node3D, kind: String, text: String) -> void:
	var s: Array = SIZES[kind]
	var w := float(s[0])
	var lw := float(s[4])
	var lh := float(s[5])
	var ly0 := float(s[3]) + float(s[1]) * 0.5 - lh * 0.5 + (0.02 if float(s[1]) > 0.3 else 0.0)
	var inset := 0.07 if kind == "cooler" or kind == "pallet" else 0.03
	var lx0 := -w * 0.5 + inset if w > 0.5 else -lw * 0.5
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = lw / 620.0
	l.width = 560.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.line_spacing = -6.0
	l.modulate = Color(0.05, 0.06, 0.08)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = Vector3(lx0 + lw * 0.5, ly0 + lh * 0.685, float(s[2]) * 0.5 + 0.0062)
	l.visibility_range_end = 7.0
	root.add_child(l)


## Pappe aus der gemeinsamen Textur, damit nicht jedes Modell eigene Bilder mitbringt.
static func _dress(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s)
				if m != null and m.resource_name == "CT_Kraft":
					mi.set_surface_override_material(s, _kraft())
	for c in n.get_children():
		_dress(c)


static func _kraft() -> Material:
	if not _mats.has("kraft"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/carton/kraft_alb.png")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/carton/kraft_nrm.png")
		m.normal_scale = 0.8
		var orm: Texture2D = load("res://assets/textures/carton/kraft_orm.png")
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = orm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["kraft"] = m
	return _mats["kraft"]
