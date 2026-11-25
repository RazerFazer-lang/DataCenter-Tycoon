class_name OutdoorWorld
extends Node3D
## Begehbares Grundstück rund um die Halle: Boden, Zaun, Tor, Hintertür, Dach, Garten, Außenlampen und Jahreszeiten-Effekte.
## Den Zustand führt OutdoorManager.

## Grundstück (innerhalb des Zauns) und Straße bis zu den Querstraßen.
const PLOT := Rect2(-10.8, -9.5, 37.3, 19.85)
const STREET := Rect2(-41.0, 10.35, 80.5, 10.0)
const HALL := Rect2(-5.85, -4.9, 27.7, 9.8)
const ROOF_Y := 4.40
const DOOR_POS := Vector3(-5.62, 0.0, 3.65)
const LADDER_POS := Vector3(3.4, 0.0, -4.86)
const GARDEN := Vector3(-8.4, 0.0, -4.6)
const BED_POS: Array[Vector3] = [Vector3(-9.6, 0, -8.2), Vector3(-7.7, 0, -8.2), Vector3(-5.8, 0, -8.2)]
const BENCH_POS := [[Vector3(-9.9, 0, -4.4), 90.0], [Vector3(-7.1, 0, -6.35), 0.0]]
const FEEDER_POS := Vector3(-7.6, 0, -0.4)
const BATH_POS := Vector3(-9.2, 0, 0.6)
const GRILL_POS := Vector3(-8.3, 0, -2.5)
const GATE_OPEN := 7.9
const FOLIAGE := {"tomato": "plant_tomato", "lettuce": "plant_lettuce", "berry": "plant_berry"}

static var _mats: Dictionary = {}

var _gate_panel: Node3D
var _gate_body: StaticBody3D
var _gate_u := 1.0
var _door_leaf: Node3D
var _door_col: CollisionShape3D
var _door_u := 0.0
var _lamps: Array = []
var _solar: Array = []
var _solar_site: Node3D
var _solar_dirt_mat: StandardMaterial3D
var _dish_arm: Node3D
var _cups: Node3D
var _vane: Node3D
var _grill_lid: Node3D
var _grill_food: Node3D
var _grill_smoke: CPUParticles3D
var _feed_seed: Node3D
var _plants: Array = [null, null, null]
var _plant_kind: Array = ["", "", ""]
var _bed_mats: Array = []
var _snow_nodes: Array = []
var _units: Dictionary = {}
var _roof_mat: StandardMaterial3D
var _fall: CPUParticles3D
var _fall_kind := ""
var _flies: MultiMeshInstance3D
var _fly_seed: PackedFloat32Array = []
var _t := 0.0
var wildlife: Wildlife


func _ready() -> void:
	_build_ground()
	_build_bounds()
	_build_fence_and_gate()
	_build_back_door()
	_build_roof()
	_build_garden()
	_build_lamps()
	_build_season_fx()
	wildlife = Wildlife.new()
	add_child(wildlife)
	OutdoorManager.changed.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------- Hilfen

## Modell mit den OD_*-Materialien des Spiels (Holz, Metall, Erde mit Struktur).
static func model(id: String) -> Node3D:
	var m := ModelLoader.instantiate_custom_model(id)
	if m == null:
		return Node3D.new()
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src != null and src.resource_name.begins_with("OD_"):
				mi.set_surface_override_material(s, mat(src))
	return m


static func mat(src: StandardMaterial3D) -> StandardMaterial3D:
	var nm := src.resource_name
	if _mats.has(nm):
		return _mats[nm]
	var m := src.duplicate() as StandardMaterial3D
	var noise_f := 0.0
	var stretch := Vector3.ONE
	match nm:
		"OD_Wood", "OD_WoodDark":
			noise_f = 0.05
			stretch = Vector3(1.2, 14.0, 14.0)
		"OD_Concrete", "OD_Soil", "OD_Terra", "OD_Snow":
			noise_f = 0.06
			stretch = Vector3.ONE * 5.0
		"OD_Fabric":
			noise_f = 0.2
			stretch = Vector3.ONE * 12.0
	if noise_f > 0.0:
		var n := FastNoiseLite.new()
		n.frequency = noise_f
		n.fractal_octaves = 4
		n.seed = nm.length() * 7
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.noise = n
		var g := Gradient.new()
		g.set_color(0, Color(0.62, 0.62, 0.62))
		g.set_color(1, Color(1.15, 1.15, 1.15))
		t.color_ramp = g
		m.albedo_texture = t
		var tn := NoiseTexture2D.new()
		tn.width = 256
		tn.height = 256
		tn.seamless = true
		tn.as_normal_map = true
		tn.bump_strength = 5.0
		tn.noise = n
		m.normal_enabled = true
		m.normal_texture = tn
		m.uv1_triplanar = true
		m.uv1_scale = stretch
	if nm == "OD_Glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.74, 0.80, 0.28)
		m.roughness = 0.04
	if nm == "OD_Water":
		m.roughness = 0.03
		m.metallic_specular = 0.8
	if nm.begins_with("OD_Leaf"):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.backlight_enabled = true
		m.backlight = m.albedo_color * 0.5
	if nm in ["OD_LedRed", "OD_LedGreen", "OD_Ember"]:
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.2
	_mats[nm] = m
	return m


func _solid(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	b.position = pos
	add_child(b)
	return b


func _vis(pos: Vector3, size: Vector3, m: Material, shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _area(id: String, pos: Vector3, size: Vector3, kind: String = "outdoor") -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 4
	a.collision_mask = 0
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	a.add_child(c)
	a.position = pos
	a.set_meta("interact_type", kind)
	a.set_meta("entity_id", id)
	add_child(a)
	return a


func _place(id: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var m := model(id)
	m.position = pos
	m.rotation_degrees.y = yaw
	add_child(m)
	return m


# ---------------------------------------------------------------- Boden und Grenzen

func _build_ground() -> void:
	# Ein großer Boden für alles außerhalb der Halle. Einfahrt und Rasen davor haben ihren eigenen.
	_solid(Vector3(0.0, -0.28, 0.0), Vector3(130.0, 0.5, 60.0))
	# Gehweg gegenüber
	_solid(Vector3(0.0, -0.02, 19.40), Vector3(130.0, 0.14, 1.86))
	var meadow := Nature.meadow(MatLib.get_mat("grass"))
	# Rasen links, hinten und rechts der Halle (vorn liegt er schon)
	_vis(Vector3(-8.25, -0.13, -2.55), Vector3(5.1, 0.2, 13.9), meadow)
	_vis(Vector3(8.0, -0.13, -7.2), Vector3(27.4, 0.2, 4.6), meadow)
	_vis(Vector3(24.1, -0.13, -2.55), Vector3(4.8, 0.2, 13.9), meadow)
	_vis(Vector3(25.0, -0.135, 7.4), Vector3(3.2, 0.2, 5.9), meadow)
	# Schotterstreifen an der Wand und Plattenweg rundherum
	var gravel := StandardMaterial3D.new()
	gravel.albedo_color = Color(0.46, 0.45, 0.43)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.09
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	var gr := Gradient.new()
	gr.set_color(0, Color(0.45, 0.44, 0.42))
	gr.set_color(1, Color(1.1, 1.08, 1.04))
	t.color_ramp = gr
	gravel.albedo_texture = t
	var tn := NoiseTexture2D.new()
	tn.width = 256
	tn.height = 256
	tn.seamless = true
	tn.as_normal_map = true
	tn.bump_strength = 8.0
	tn.noise = n
	gravel.normal_enabled = true
	gravel.normal_texture = tn
	gravel.uv1_triplanar = true
	gravel.uv1_world_triplanar = true
	gravel.uv1_scale = Vector3.ONE * 0.9
	gravel.roughness = 0.95
	Nature.register_tint(gravel, 0.8)
	for e in [[Vector3(-6.15, -0.02, 0.0), Vector3(0.62, 0.02, 10.6)], [Vector3(8.0, -0.02, -5.15), Vector3(28.6, 0.02, 0.62)], [Vector3(22.15, -0.02, 0.0), Vector3(0.62, 0.02, 10.6)]]:
		_vis(e[0], e[1], gravel)
	var slab := StandardMaterial3D.new()
	slab.albedo_color = Color(0.66, 0.65, 0.62)
	var st := t.duplicate() as NoiseTexture2D
	var sg := Gradient.new()
	sg.set_color(0, Color(0.84, 0.83, 0.81))
	sg.set_color(1, Color(1.06, 1.05, 1.03))
	st.color_ramp = sg
	slab.albedo_texture = st
	slab.uv1_triplanar = true
	slab.uv1_world_triplanar = true
	slab.uv1_scale = Vector3.ONE * 0.35
	slab.roughness = 0.92
	Nature.register_tint(slab, 0.7)
	var pts: Array[Vector3] = [Vector3(-3.4, 0, 7.6), Vector3(-6.9, 0, 5.4), Vector3(-7.0, 0, 3.65), Vector3(-7.0, 0, -4.2), Vector3(-5.4, 0, -6.3), Vector3(8.0, 0, -6.4), Vector3(21.0, 0, -6.4), Vector3(23.4, 0, -4.6), Vector3(23.4, 0, 5.0), Vector3(21.6, 0, 7.2)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.74, 0.05, 0.46)
	mm.mesh = bm
	var xf: Array = []
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var cnt := int(seg.length() / 0.56)
		var b := Basis(Vector3.UP, atan2(seg.x, seg.z))
		for k in cnt:
			var p := pts[i - 1].lerp(pts[i], (k + 0.5) / cnt)
			if p.x > -3.9 and p.x < 3.9 and p.z > 4.6:
				continue
			var r := sin(p.x * 12.9 + p.z * 78.2)
			xf.append(Transform3D(b * Basis(Vector3.UP, r * 0.06), p + Vector3(r * 0.03, -0.030, 0)))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = slab
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Terrasse am Grill
	_vis(Vector3(-8.35, -0.022, -3.9), Vector3(3.9, 0.03, 4.2), slab)


func _build_bounds() -> void:
	# Unsichtbare Grenzen: Straße bis zu den Querstraßen, beide Gehwege.
	_solid(Vector3(-41.2, 2.0, 15.0), Vector3(0.4, 5.0, 13.0))
	_solid(Vector3(39.7, 2.0, 15.0), Vector3(0.4, 5.0, 13.0))
	_solid(Vector3(0.0, 2.0, 20.55), Vector3(84.0, 5.0, 0.4))
	_solid(Vector3(-26.0, 2.0, 8.85), Vector3(30.4, 5.0, 0.4))
	_solid(Vector3(33.2, 2.0, 8.85), Vector3(13.4, 5.0, 0.4))


	# Masten, Schilder, Stromkasten, Hydrant, Aufliegernase, Bäume
	for p in [Vector3(-30, 0, 10.15), Vector3(-14, 0, 10.15), Vector3(18, 0, 10.15), Vector3(30, 0, 10.15), Vector3(-24, 0, 18.85), Vector3(-2, 0, 18.85), Vector3(24, 0, 18.85), Vector3(4.35, 0, 10.15), Vector3(-4.6, 0, 10.05), Vector3(9.5, 0, 18.75), Vector3(-5.8, 0, 9.95)]:
		_solid(p + Vector3(0, 1.2, 0), Vector3(0.22, 2.4, 0.22))
	_solid(Vector3(6.2, 0.7, 9.55), Vector3(0.9, 1.4, 0.5))
	_solid(Vector3(-26.3, 1.6, 19.2), Vector3(2.7, 3.4, 4.4))
	for p in [Vector3(-7.4, 0, 7.6), Vector3(7.6, 0, 7.8), Vector3(23.6, 0, 7.4)]:
		_solid(p + Vector3(0, 1.2, 0), Vector3(0.5, 2.4, 0.5))


func _build_fence_and_gate() -> void:
	# Zaun ist fest (bis 2,4 m, darüber nichts).
	_solid(Vector3(-10.8, 1.2, 0.4), Vector3(0.16, 2.4, 20.0))
	_solid(Vector3(26.5, 1.2, 0.4), Vector3(0.16, 2.4, 20.0))
	_solid(Vector3(7.85, 1.2, -9.5), Vector3(37.4, 2.4, 0.16))
	_solid(Vector3(-7.4, 1.2, 10.35), Vector3(6.9, 2.4, 0.16))
	_solid(Vector3(15.3, 1.2, 10.35), Vector3(22.6, 2.4, 0.16))
	var g := _place("gate", Vector3(0.0, 0.0, 10.16))
	_gate_panel = g.find_child("Panel", true, false) as Node3D
	_gate_body = _solid(Vector3(0.0, 1.0, 10.16), Vector3(8.0, 2.0, 0.14))
	_place("gate_post", Vector3(3.55, 0.0, 9.25), -90.0)
	_area("gate", Vector3(3.55, 1.1, 9.25), Vector3(0.5, 1.0, 0.5))
	_place("gate_post", Vector3(4.75, 0.0, 10.95), 180.0)
	_area("gate", Vector3(4.75, 1.1, 10.95), Vector3(0.5, 1.0, 0.5))


func _build_back_door() -> void:
	var d := _place("back_door", DOOR_POS, -90.0)
	_door_leaf = d.find_child("Leaf", true, false) as Node3D
	var b := _solid(DOOR_POS + Vector3(-0.20, 1.05, 0.0), Vector3(0.10, 2.1, 0.94))
	_door_col = b.get_child(0) as CollisionShape3D
	_area("door", DOOR_POS + Vector3(-0.10, 1.05, 0.0), Vector3(0.62, 2.1, 1.0))
	# Vordach und Lichtschalter
	_place("wall_lamp", Vector3(-5.84, 2.75, 3.65), -90.0)
	var sw := _vis(Vector3(-5.46, 1.25, 2.98), Vector3(0.02, 0.09, 0.09), _plain(Color(0.94, 0.94, 0.92)))
	sw.add_child(_label("Außenlicht", Vector3(0.015, 0.075, 0.0), 90.0, 20, 0.0012, Color(0.25, 0.27, 0.30)))
	_area("lamps", Vector3(-5.40, 1.25, 2.98), Vector3(0.22, 0.26, 0.26))


func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _label(text: String, pos: Vector3, yaw: float, fs: int, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees.y = yaw
	l.font_size = fs
	l.pixel_size = px
	l.outline_size = 0
	l.modulate = col
	l.visibility_range_end = 10.0
	return l


# ---------------------------------------------------------------- Dach

func _build_roof() -> void:
	_solid(Vector3(8.0, ROOF_Y - 0.06, 0.0), Vector3(28.0, 0.12, 10.0))
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.36, 0.37, 0.39)
	_roof_mat.roughness = 0.94
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	var gr := Gradient.new()
	gr.set_color(0, Color(0.72, 0.72, 0.72))
	gr.set_color(1, Color(1.08, 1.08, 1.08))
	t.color_ramp = gr
	_roof_mat.albedo_texture = t
	_roof_mat.uv1_triplanar = true
	_roof_mat.uv1_world_triplanar = true
	_roof_mat.uv1_scale = Vector3.ONE * 0.22
	_vis(Vector3(8.0, ROOF_Y, 0.0), Vector3(27.5, 0.02, 9.5), _roof_mat)
	Nature.register_tint(_roof_mat, 0.95)
	# Bahnen der Abdichtung und Laufweg aus Platten
	for i in 9:
		_vis(Vector3(-4.5 + i * 3.1, ROOF_Y + 0.011, 0.0), Vector3(0.05, 0.004, 9.4), _plain(Color(0.26, 0.27, 0.29)))
	var pave := _plain(Color(0.60, 0.60, 0.58))
	Nature.register_tint(pave, 0.9)
	for i in 26:
		_vis(Vector3(-4.2 + i * 0.95, ROOF_Y + 0.03, -3.75), Vector3(0.82, 0.04, 0.62), pave)
	for i in 5:
		_vis(Vector3(LADDER_POS.x, ROOF_Y + 0.03, -2.9 + i * 0.8), Vector3(0.62, 0.04, 0.70), pave)
	# Geländer (Lücke an der Leiter)
	for i in 14:
		var x := -5.0 + i * 2.0
		for z in [-4.72, 4.72]:
			if z < 0.0 and absf(x - LADDER_POS.x) < 1.35:
				continue
			_place("roof_rail", Vector3(x, ROOF_Y, float(z)), 180.0 if z > 0.0 else 0.0)
	for i in 5:
		for x in [-5.72, 21.72]:
			_place("roof_rail", Vector3(float(x), ROOF_Y, -3.9 + i * 2.0 - 0.1), 90.0 if x < 0.0 else -90.0)
	_solid(Vector3(8.0, ROOF_Y + 0.6, 4.78), Vector3(27.8, 1.2, 0.1))
	_solid(Vector3(-5.80, ROOF_Y + 0.6, 0.0), Vector3(0.1, 1.2, 9.6))
	_solid(Vector3(21.80, ROOF_Y + 0.6, 0.0), Vector3(0.1, 1.2, 9.6))
	_solid(Vector3((-5.8 + LADDER_POS.x - 0.45) * 0.5, ROOF_Y + 0.6, -4.78), Vector3(LADDER_POS.x - 0.45 + 5.8, 1.2, 0.1))
	_solid(Vector3((21.8 + LADDER_POS.x + 0.45) * 0.5, ROOF_Y + 0.6, -4.78), Vector3(21.8 - LADDER_POS.x - 0.45, 1.2, 0.1))
	# Leiter
	_place("roof_ladder", LADDER_POS + Vector3(0, 0, -0.02), 180.0)
	_area("ladder", LADDER_POS + Vector3(0.0, 1.4, -0.35), Vector3(0.7, 2.6, 0.5), "ladder")
	_area("ladder_top", Vector3(LADDER_POS.x, ROOF_Y + 0.75, -4.95), Vector3(0.8, 1.3, 0.4), "ladder")
	# Solar: acht Module, erst nach dem Kauf
	_solar_site = Node3D.new()
	add_child(_solar_site)
	for r in 2:
		for c in 5:
			var p := model("solar_panel")
			p.position = Vector3(8.0 + c * 1.35, ROOF_Y, -1.35 + r * 2.5)
			_solar_site.add_child(p)
			for mi in p.find_children("*", "MeshInstance3D", true, false):
				_solar.append(mi)
	_solar_dirt_mat = StandardMaterial3D.new()
	_solar_dirt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_solar_dirt_mat.albedo_color = Color(0.45, 0.40, 0.30, 0.0)
	_solar_dirt_mat.roughness = 1.0
	for mi in _solar:
		(mi as MeshInstance3D).material_overlay = _solar_dirt_mat
	var inv := Vector3(6.6, ROOF_Y, 0.2)
	_vis(inv + Vector3(0, 0.55, 0), Vector3(0.46, 0.62, 0.22), _plain(Color(0.92, 0.93, 0.94)), true)
	_vis(inv + Vector3(0, 0.14, 0), Vector3(0.10, 0.28, 0.10), _plain(Color(0.30, 0.32, 0.35)), true)
	add_child(_label("SOLAR", inv + Vector3(-0.0, 0.70, -0.12), 180.0, 34, 0.0022, Color(0.10, 0.35, 0.16)))
	_area("solar", inv + Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.6))
	_area("solar", Vector3(10.7, ROOF_Y + 0.4, -0.1), Vector3(6.6, 0.7, 4.6))
	# Schüssel und Wetterstation
	var dish := _place("sat_dish", Vector3(-3.4, ROOF_Y, 1.2))
	_dish_arm = dish.find_child("Arm", true, false) as Node3D
	_area("dish", Vector3(-3.4, ROOF_Y + 0.9, 1.2), Vector3(1.2, 1.8, 1.2))
	_solid(Vector3(-3.4, ROOF_Y + 0.6, 1.2), Vector3(0.3, 1.2, 0.3))
	var ws := _place("weather_station", Vector3(-0.6, ROOF_Y, 2.4), 180.0)
	_cups = ws.find_child("Cups", true, false) as Node3D
	_vane = ws.find_child("Vane", true, false) as Node3D
	_area("station", Vector3(-0.6, ROOF_Y + 1.0, 2.4), Vector3(0.8, 2.0, 0.7))
	_solid(Vector3(-0.6, ROOF_Y + 0.6, 2.4), Vector3(0.3, 1.2, 0.3))
	_solid(Vector3(10.7, ROOF_Y + 0.3, -1.35), Vector3(6.6, 0.6, 1.5))
	_solid(Vector3(10.7, ROOF_Y + 0.3, 1.15), Vector3(6.6, 0.6, 1.5))
	_solid(inv + Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0.3))


# ---------------------------------------------------------------- Garten

func _build_garden() -> void:
	for i in BED_POS.size():
		_place("raised_bed", BED_POS[i])
		_solid(BED_POS[i] + Vector3(0, 0.25, 0), Vector3(1.62, 0.5, 0.82))
		_area("bed:%d" % i, BED_POS[i] + Vector3(0, 0.45, 0), Vector3(1.7, 0.9, 0.95))
		_bed_mats.append(null)
	for e in BENCH_POS:
		_place("garden_bench", e[0], e[1])
		var b := _solid((e[0] as Vector3) + Vector3(0, 0.22, 0), Vector3(1.6, 0.44, 0.5))
		b.rotation_degrees.y = float(e[1])
		var a := _area("bench", (e[0] as Vector3) + Vector3(0, 0.5, 0), Vector3(1.7, 1.0, 0.7), "bench")
		a.rotation_degrees.y = float(e[1])
		a.set_meta("yaw", float(e[1]))
	_place("garden_table", Vector3(-8.5, 0, -4.4), 90.0)
	_solid(Vector3(-8.5, 0.37, -4.4), Vector3(0.9, 0.74, 1.5))
	var g := _place("grill", GRILL_POS, 35.0)
	_grill_lid = g.find_child("Lid", true, false) as Node3D
	_grill_food = g.find_child("Food", true, false) as Node3D
	_solid(GRILL_POS + Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0.5))
	_area("grill", GRILL_POS + Vector3(0, 0.65, 0), Vector3(0.75, 1.2, 0.75))
	_grill_smoke = CPUParticles3D.new()
	_grill_smoke.position = GRILL_POS + Vector3(0, 0.95, 0)
	_grill_smoke.amount = 22
	_grill_smoke.lifetime = 2.6
	_grill_smoke.direction = Vector3(0.2, 1, 0.1)
	_grill_smoke.spread = 12.0
	_grill_smoke.gravity = Vector3(0.15, 0.25, 0.0)
	_grill_smoke.initial_velocity_min = 0.35
	_grill_smoke.initial_velocity_max = 0.7
	_grill_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_grill_smoke.emission_sphere_radius = 0.18
	var qm := QuadMesh.new()
	qm.size = Vector2(0.30, 0.30)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.75, 0.75, 0.75, 0.16)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gg
	sm.albedo_texture = gt
	qm.material = sm
	_grill_smoke.mesh = qm
	_grill_smoke.emitting = false
	add_child(_grill_smoke)
	var f := _place("bird_feeder", FEEDER_POS, 20.0)
	_feed_seed = f.find_child("Seed", true, false) as Node3D
	_solid(FEEDER_POS + Vector3(0, 0.7, 0), Vector3(0.12, 1.4, 0.12))
	_area("feeder", FEEDER_POS + Vector3(0, 1.2, 0), Vector3(0.7, 1.0, 0.7))
	_place("bird_bath", BATH_POS)
	_solid(BATH_POS + Vector3(0, 0.4, 0), Vector3(0.5, 0.8, 0.5))
	# Bepflanzung: Obstbäume, Büsche am Zaun
	for e in [["apple", Vector3(-9.6, 0, -1.8), 1.0], ["apple", Vector3(-9.7, 0, 3.2), 0.92], ["maple", Vector3(24.6, 0, -7.6), 0.85], ["birch", Vector3(16.5, 0, -8.5), 0.85], ["birch", Vector3(11.5, 0, -8.6), 0.78], ["oak", Vector3(24.9, 0, 1.0), 0.80]]:
		add_child(Nature.tree(e[0], e[1], e[2], (e[1] as Vector3).x * 31.0))
		_solid((e[1] as Vector3) + Vector3(0, 1.2, 0), Vector3(0.34, 2.4, 0.34))
	for p in [Vector3(-10.3, 0, 5.4), Vector3(-10.3, 0, 7.0), Vector3(-10.3, 0, 9.0), Vector3(-8.8, 0, 9.8), Vector3(0.5, 0, -8.9), Vector3(3.0, 0, -9.0), Vector3(6.2, 0, -8.8), Vector3(19.0, 0, -8.9), Vector3(21.5, 0, -8.8), Vector3(25.9, 0, -4.4), Vector3(25.9, 0, -1.6), Vector3(25.9, 0, 4.2), Vector3(13.4, 0, 9.7), Vector3(16.2, 0, 9.8), Vector3(19.6, 0, 9.7), Vector3(-3.0, 0, -9.0)]:
		add_child(Nature.tree("bush", p, 0.85 + fposmod(p.x * 0.37, 0.4), p.x * 57.0))


# ---------------------------------------------------------------- Licht

func _build_lamps() -> void:
	for p in [Vector3(-6.75, 0, 5.9), Vector3(-6.3, 0, 1.2), Vector3(-6.3, 0, -5.2), Vector3(-9.9, 0, -6.6), Vector3(1.0, 0, -6.95), Vector3(8.0, 0, -6.95), Vector3(15.0, 0, -6.95), Vector3(22.8, 0, -5.6), Vector3(22.85, 0, 1.4), Vector3(22.0, 0, 6.6)]:
		var m := _place("bollard_lamp", p)
		_solid(p + Vector3(0, 0.5, 0), Vector3(0.14, 1.0, 0.14))
		_add_lamp(m, p + Vector3(0, 0.92, 0), 4.2, 0.9)
	for e in [[Vector3(-5.84, 3.1, -2.4), -90.0], [Vector3(6.8, 3.1, -4.84), 180.0], [Vector3(14.6, 3.1, -4.84), 180.0], [Vector3(21.84, 3.1, 0.0), 90.0]]:
		var m2 := _place("wall_lamp", e[0], e[1])
		var out := Basis(Vector3.UP, deg_to_rad(float(e[1]))) * Vector3(0, -0.15, 0.5)
		_add_lamp(m2, (e[0] as Vector3) + out, 7.0, 1.7)
	var dl := find_child("Glow", true, false)
	if dl != null:
		_add_lamp(null, DOOR_POS + Vector3(-0.9, 2.5, 0.0), 5.0, 1.2)


func _add_lamp(m: Node3D, pos: Vector3, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = rng
	l.light_color = Color(1.0, 0.88, 0.68)
	l.light_energy = 0.0
	l.visible = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 26.0
	l.distance_fade_length = 8.0
	add_child(l)
	var gm: StandardMaterial3D = null
	if m != null:
		var g := m.find_child("Glow", true, false) as MeshInstance3D
		if g != null:
			gm = (g.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			gm.emission_enabled = true
			gm.emission = Color(1.0, 0.86, 0.62)
			gm.emission_energy_multiplier = 0.0
			g.material_override = gm
	_lamps.append({"l": l, "m": gm, "e": energy})


# ---------------------------------------------------------------- Zustand zeigen

func _refresh() -> void:
	var s: Dictionary = OutdoorManager.state
	_solar_site.visible = bool(s["solar"])
	_solar_dirt_mat.albedo_color = Color(0.45, 0.40, 0.30, float(s["solar_dirt"]) * 0.62).lerp(Color(0.92, 0.95, 0.98, 0.95), float(s["snow"]) * 0.9)
	if _feed_seed != null:
		_feed_seed.visible = float(s["feed"]) > 0.05
		_feed_seed.scale.y = maxf(0.2, float(s["feed"]))
	if _grill_food != null:
		_grill_food.visible = int(s["grill_left"]) > 0
	for i in 3:
		_refresh_bed(i, s["beds"][i])
	_refresh_units()


func _refresh_bed(i: int, b: Dictionary) -> void:
	var p := str(b["p"])
	if p != _plant_kind[i]:
		_plant_kind[i] = p
		if _plants[i] != null:
			(_plants[i] as Node3D).queue_free()
			_plants[i] = null
		if p != "":
			var root := Node3D.new()
			root.position = BED_POS[i] + Vector3(0, 0.425, 0)
			add_child(root)
			var cols := 4 if p == "tomato" else 5
			for c in cols:
				for r in 2:
					var m := model(FOLIAGE[p])
					m.position = Vector3(-0.60 + 1.2 * c / (cols - 1.0), 0, -0.18 + 0.36 * r)
					m.rotation.y = c * 1.7 + r * 2.3
					root.add_child(m)
			_plants[i] = root
	if _plants[i] == null:
		return
	var g := float(b["g"])
	var dry := float(b["w"]) < 0.1 and g < 1.0
	for m in (_plants[i] as Node3D).get_children():
		(m as Node3D).scale = Vector3.ONE * lerpf(0.15, 1.0, pow(g, 0.7)) * (Vector3(1.0, 0.72, 1.0) if dry else Vector3.ONE)
		var fr := m.find_child("Fruit", true, false) as Node3D
		if fr != null:
			fr.visible = g > 0.72


## Laub, Schnee und Staub auf den Außengeräten.
func _refresh_units() -> void:
	for cid in _units.keys():
		if not GameState.coolers.has(cid):
			(_units[cid]["node"] as Node3D).queue_free()
			_units.erase(cid)
	for cid in GameState.coolers.keys():
		var d: Dictionary = GameState.coolers[cid]
		if not GameState.is_heat_pump_type(str(d.get("cooler_type", "cooler"))):
			continue
		var c := OutdoorManager.clog(cid)
		var kind := OutdoorManager.clog_kind()
		if _units.has(cid) and str(_units[cid]["kind"]) != kind:
			(_units[cid]["node"] as Node3D).queue_free()
			_units.erase(cid)
		if c < 0.05:
			if _units.has(cid):
				(_units[cid]["node"] as Node3D).visible = false
			continue
		if not _units.has(cid):
			var root := Node3D.new()
			add_child(root)
			_units[cid] = {"node": root, "kind": kind}
			var sz: Vector3 = CoolerProp.GHOST_SIZES.get(str(d.get("cooler_type", "cooler")), Vector3(1.0, 1.0, 0.5))
			if kind == "dust":
				var grill := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(sz.x * 0.86, sz.y * 0.8)
				grill.mesh = qm
				grill.position = Vector3(0, sz.y * 0.52, sz.z * 0.5 + 0.10)
				grill.name = "Dust"
				var dm := StandardMaterial3D.new()
				dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var n := FastNoiseLite.new()
				n.frequency = 0.03
				var t := NoiseTexture2D.new()
				t.noise = n
				var gr := Gradient.new()
				gr.set_color(0, Color(0.45, 0.40, 0.32, 0.15))
				gr.set_color(1, Color(0.52, 0.47, 0.38, 1.0))
				t.color_ramp = gr
				dm.albedo_texture = t
				grill.material_override = dm
				root.add_child(grill)
			else:
				var id := "leaf_pile" if kind == "leaves" else "snow_cap"
				var top := model(id)
				top.position = Vector3(0, sz.y + 0.01, 0)
				top.scale = Vector3(sz.x * 0.95, 1.0, sz.z * 0.95)
				root.add_child(top)
				var fr := model(id)
				fr.position = Vector3(0, 0.0, sz.z * 0.5 + 0.22)
				fr.scale = Vector3(sz.x * 1.1, 2.6, 0.6)
				fr.name = "Front"
				root.add_child(fr)
		var nd: Node3D = _units[cid]["node"]
		nd.visible = true
		nd.position = d["pos"]
		nd.rotation.y = float(d.get("rot_y", 0.0))
		nd.scale = Vector3(1.0, 0.35 + 0.9 * c, 1.0) if kind != "dust" else Vector3.ONE
		if kind == "dust":
			((nd.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, c * 0.85)


# ---------------------------------------------------------------- Jahreszeiten-Effekte

func _build_season_fx() -> void:
	_fall = CPUParticles3D.new()
	_fall.amount = 70
	_fall.lifetime = 9.0
	_fall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fall.emission_box_extents = Vector3(16, 1.0, 16)
	_fall.direction = Vector3(0.5, -1, 0.2)
	_fall.spread = 25.0
	_fall.gravity = Vector3(0.0, -0.12, 0.0)
	_fall.initial_velocity_min = 0.35
	_fall.initial_velocity_max = 0.8
	_fall.angular_velocity_min = -160.0
	_fall.angular_velocity_max = 160.0
	_fall.angle_max = 360.0
	_fall.particle_flag_rotate_y = true
	_fall.emitting = false
	_fall.local_coords = false
	add_child(_fall)
	# Glühwürmchen
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 1))
	gg.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gg
	m.albedo_texture = gt
	qm.material = m
	mm.mesh = qm
	mm.instance_count = 36
	_flies = MultiMeshInstance3D.new()
	_flies.multimesh = mm
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flies.visible = false
	add_child(_flies)
	for i in 36:
		_fly_seed.append(randf() * 100.0)
	# Schneehauben auf Möbeln und Pfosten
	for e in [[Vector3(-8.5, 0.755, -4.4), Vector3(0.9, 0.6, 1.5)], [Vector3(-9.6, 0.50, -8.2), Vector3(1.6, 0.5, 0.8)], [Vector3(-7.7, 0.50, -8.2), Vector3(1.6, 0.5, 0.8)], [Vector3(-5.8, 0.50, -8.2), Vector3(1.6, 0.5, 0.8)], [FEEDER_POS + Vector3(0, 1.66, 0), Vector3(0.5, 0.5, 0.5)], [BATH_POS + Vector3(0, 0.76, 0), Vector3(0.62, 0.5, 0.62)], [GRILL_POS + Vector3(0, 1.0, 0), Vector3(0.4, 0.5, 0.4)], [Vector3(-9.95, 0.46, -4.4), Vector3(0.45, 0.4, 1.5)], [Vector3(-7.1, 0.46, -6.30), Vector3(1.5, 0.4, 0.45)], [Vector3(-3.4, 4.5, 1.2), Vector3(1.0, 0.8, 0.8)]]:
		var sc := model("snow_cap")
		sc.position = e[0]
		sc.scale = e[1]
		sc.visible = false
		add_child(sc)
		_snow_nodes.append([sc, (e[1] as Vector3).y])


func _set_fall(kind: String) -> void:
	if kind == _fall_kind:
		return
	_fall_kind = kind
	_fall.emitting = kind != ""
	if kind == "":
		return
	var qm := QuadMesh.new()
	qm.size = Vector2(0.085, 0.055) if kind == "leaf" else Vector2(0.035, 0.03)
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	qm.material = m
	_fall.mesh = qm
	var g := Gradient.new()
	if kind == "leaf":
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.72, 0.28, 0.05), Color(0.86, 0.58, 0.10), Color(0.50, 0.30, 0.10)])
	else:
		g.set_color(0, Color(1.0, 0.88, 0.92))
		g.set_color(1, Color(1.0, 0.97, 0.96))
	_fall.color_initial_ramp = g
	_fall.amount = 70 if kind == "leaf" else 34


func _process(delta: float) -> void:
	_t += delta
	var s: Dictionary = OutdoorManager.state
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else Vector3.ZERO
	var near := cp.z > -60.0
	# Tor
	var gu := 0.0 if bool(s["gate"]) else 1.0
	_gate_u = move_toward(_gate_u, gu, delta / 3.2)
	if _gate_panel != null:
		_gate_panel.position.x = GATE_OPEN * smoothstep(0.0, 1.0, _gate_u)
	_gate_body.position.x = GATE_OPEN * smoothstep(0.0, 1.0, _gate_u)
	# Hintertür schwingt nach außen
	_door_u = move_toward(_door_u, 1.0 if bool(s["door"]) else 0.0, delta * 2.2)
	if _door_leaf != null:
		_door_leaf.rotation.y = -1.75 * smoothstep(0.0, 1.0, _door_u)
	_door_col.disabled = _door_u > 0.35
	# Lampen
	var on := OutdoorManager.lamps_on() if GameState.is_active else false
	for e in _lamps:
		var l: OmniLight3D = e["l"]
		l.light_energy = move_toward(l.light_energy, float(e["e"]) if on else 0.0, delta * 2.0)
		l.visible = l.light_energy > 0.01
		if e["m"] != null:
			(e["m"] as StandardMaterial3D).emission_energy_multiplier = 3.0 * l.light_energy / float(e["e"])
	if not near:
		return
	# Wetterstation, Schüssel
	var wind: float = {"storm": 9.0, "rain": 4.5, "cloudy": 2.6}.get(GameState.weather_state if GameState.is_active else "clear", 1.4)
	if _cups != null:
		_cups.rotation.y += delta * wind
	if _vane != null:
		_vane.rotation.y = sin(_t * 0.31) * 0.6 + sin(_t * 1.7) * 0.06 * wind
	if _dish_arm != null:
		var off := 1.0 - float(s["dish"])
		var want := Vector3(deg_to_rad(-34.0 + 22.0 * off), deg_to_rad(-28.0 + 70.0 * off), 0.0)
		_dish_arm.rotation = _dish_arm.rotation.lerp(want, 1.0 - exp(-delta * 3.0))
	# Grill
	var hot := float(s["grill_t"]) > 0.0 or int(s["grill_left"]) > 0
	if _grill_lid != null:
		_grill_lid.rotation.x = lerpf(_grill_lid.rotation.x, -1.25 if hot else 0.0, 1.0 - exp(-delta * 4.0))
	_grill_smoke.emitting = hot
	# Schneehauben
	var sn := OutdoorManager.snow_shown
	for e in _snow_nodes:
		(e[0] as Node3D).visible = sn > 0.06
		(e[0] as Node3D).scale.y = float(e[1]) * maxf(0.05, sn)
	# Fallende Blätter und Blüten
	var se := OutdoorManager.season()
	var dry := not (GameState.weather_state in ["rain", "storm"])
	_set_fall(("leaf" if se > 2.05 and se < 2.95 else ("petal" if se < 0.9 else "")) if dry else "")
	_fall.position = Vector3(cp.x, 6.5, cp.z)
	_fall.visible = not _inside(cp)
	_update_flies(cp, se)


func _inside(p: Vector3) -> bool:
	return p.y < ROOF_Y and HALL.has_point(Vector2(p.x, p.z))


func _update_flies(cp: Vector3, se: float) -> void:
	var on := GameState.is_active and OutdoorManager.is_night() and se > 0.6 and se < 2.1 and not (GameState.weather_state in ["rain", "storm"])
	_flies.visible = on
	if not on:
		return
	var mm := _flies.multimesh
	for i in mm.instance_count:
		var s := _fly_seed[i]
		var base: Vector3 = [GARDEN, Vector3(-8.5, 0, 2.5), Vector3(14, 0, -7.4), Vector3(24.2, 0, -2.0)][i % 4]
		var p := base + Vector3(sin(_t * 0.23 + s) * 2.2 + sin(_t * 0.7 + s * 2.0) * 0.4, 0.8 + sin(_t * 0.41 + s * 3.0) * 0.5, cos(_t * 0.19 + s * 1.7) * 2.2)
		var b := maxf(0.0, sin(_t * 1.6 + s * 5.0))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_color(i, Color(0.75, 1.0, 0.25, 1.0) * b * 1.6)


## Draußen auf dem Grundstück, der Straße oder dem Dach? (Geräusche, Schritte)
static func is_outside(p: Vector3) -> bool:
	if p.z < -60.0:
		return false
	return p.y > 3.6 or not HALL.has_point(Vector2(p.x, p.z))


static func surface(p: Vector3) -> String:
	if p.y > 3.6 or p.z < -60.0 or not is_outside(p):
		return "concrete"
	if p.z > 10.4 or (absf(p.x) < 3.8 and p.z > 4.6):
		return "concrete"
	return "grass"
