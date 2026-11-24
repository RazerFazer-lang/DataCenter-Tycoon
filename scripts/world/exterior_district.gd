class_name ExteriorDistrict
extends Node3D
## Außenwelt 2.0: Vollständiges 360°-Industrie- & Gewerbegebiet rund um das DataCenter
## (keine sichtbare Leere/Void!), vorbeifahrender KI-Straßenverkehr, Straßenlaternen,
## 20-kV-Trafohäuschen, Nachbarhallen, Bäume, Zäune, Horizont-Kulisse, Regen & Blitze.

const TRAFFIC_X_MIN := -82.0
const TRAFFIC_X_MAX := 86.0

var _street_lamp_mats: Array[StandardMaterial3D] = []
var _window_mats: Array[StandardMaterial3D] = []
var _tower_beacon_mat: StandardMaterial3D
var _traffic_cars: Array[Dictionary] = []
var _car_headlight_mats: Array[StandardMaterial3D] = []
var _car_taillight_mats: Array[StandardMaterial3D] = []

# 3D-Regen (MultiMesh folgt dem Spieler im Außenbereich, regnet nicht ins Gebäude!)
var _rain_mm_inst: MultiMeshInstance3D
var _rain_drops: Array[Vector3] = []
var _rain_speeds: PackedFloat32Array = PackedFloat32Array()
var _lightning_light: DirectionalLight3D
var _lightning_flash: float = 0.0
var _lightning_cooldown: float = 9.0
var _anim_t: float = 0.0


func _ready() -> void:
	_build_360_terrain_and_horizon()
	_build_extended_road_and_lamps()
	_build_south_industrial_neighbors()
	_build_west_yard_and_containers()
	_build_east_substation_and_fence()
	_build_north_hinterland_and_tower()
	_build_ambient_traffic()
	_build_weather_vfx()


func _process(delta: float) -> void:
	_anim_t += delta
	_update_night_lights()
	_update_traffic(delta)
	_update_weather(delta)


# ---------------------------------------------------------------- 360°-Gelände & Horizont (0 % Void!)

func _build_360_terrain_and_horizon() -> void:
	var grass_mat := MatLib.get_mat("grass")
	var terrain_mat: StandardMaterial3D
	if grass_mat is StandardMaterial3D:
		terrain_mat = (grass_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		terrain_mat.albedo_color = Color(0.56, 0.66, 0.44)
		terrain_mat.uv1_triplanar = true
		terrain_mat.uv1_world_triplanar = true
		terrain_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	else:
		terrain_mat = _mat(Color(0.24, 0.34, 0.20), 0.94, 0.0)

	# Riesiger 520 × 520 m Grundboden in alle 4 Himmelsrichtungen (tief genug unter Hof/Straße, kein Z-Fighting)
	_add_box(Vector3(6.0, -0.30, 8.0), Vector3(520.0, 0.20, 520.0), terrain_mat, false)

	# Ferne grüne Hügelkette rund um den gesamten Horizont (360°), damit nirgends eine Kante sichtbar ist
	var hill_mat := _mat(Color(0.18, 0.25, 0.19), 0.96, 0.0)
	var skyline_mat := _mat(Color(0.16, 0.19, 0.24), 0.86, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	for i in range(28):
		var ang := (float(i) / 28.0) * TAU
		var dist := rng.randf_range(108.0, 145.0)
		var hx := 6.0 + cos(ang) * dist
		var hz := 6.0 + sin(ang) * dist
		var hw := rng.randf_range(34.0, 62.0)
		var hh := rng.randf_range(7.0, 18.0)
		var hd := rng.randf_range(22.0, 38.0)
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.0
		sm.radial_segments = 14
		sm.rings = 6
		m.mesh = sm
		m.material_override = hill_mat
		m.position = Vector3(hx, -2.5, hz)
		m.scale = Vector3(hw, hh, hd)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)

		# Gelegentliche ferne Gewerbe-/Hochhaus-Silhouetten am Horizont
		if i % 2 == 0:
			var bdist := rng.randf_range(82.0, 108.0)
			var bx := 6.0 + cos(ang + 0.06) * bdist
			var bz := 6.0 + sin(ang + 0.06) * bdist
			var bh := rng.randf_range(10.0, 26.0)
			var bw := rng.randf_range(10.0, 22.0)
			_add_box(Vector3(bx, bh * 0.5 - 0.2, bz), Vector3(bw, bh, rng.randf_range(10.0, 18.0)), skyline_mat, false)


# ---------------------------------------------------------------- Verlängerte Straße, Laternen & Schilder

func _build_extended_road_and_lamps() -> void:
	var pole_mat := MatLib.make_brushed_metal(Color(0.24, 0.27, 0.30), 0.45, 0.65)
	var sign_blue := _mat(Color(0.10, 0.32, 0.68), 0.45, 0.15)
	var sign_white := _mat(Color(0.92, 0.93, 0.95), 0.55, 0.05)
	var sign_red := _mat(Color(0.84, 0.14, 0.14), 0.45, 0.10)
	var curb_mat := _mat(Color(0.55, 0.56, 0.58), 0.88, 0.0)

	# 8 Straßenlaternen links & rechts entlang der Gewerbestraße
	var lamp_xs: Array[float] = [-46.0, -30.0, -14.0, 18.0, 34.0, 50.0, -22.0, 26.0]
	for idx in range(lamp_xs.size()):
		var lx := lamp_xs[idx]
		var far_side := idx >= 6
		var lz := 18.65 if far_side else 10.25
		var arm_dir := -1.0 if far_side else 1.0
		_add_cyl(Vector3(lx, 2.5, lz), 0.065, 0.095, 5.0, pole_mat)
		_add_box(Vector3(lx, 4.95, lz + arm_dir * 0.55), Vector3(0.12, 0.09, 1.15), pole_mat, false)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(1.0, 0.94, 0.78)
		lmat.emission_enabled = true
		lmat.emission = Color(1.0, 0.88, 0.62)
		lmat.emission_energy_multiplier = 0.2
		_street_lamp_mats.append(lmat)
		_add_box(Vector3(lx, 4.87, lz + arm_dir * 0.95), Vector3(0.24, 0.06, 0.44), lmat, false)

	# Straßenschilder: "GEWERBEPARK NORD" + Tempo-30-Schild am Einfahrtsrand
	_add_cyl(Vector3(-4.6, 1.25, 10.1), 0.035, 0.035, 2.5, pole_mat)
	_add_box(Vector3(-4.6, 2.25, 10.1), Vector3(0.95, 0.28, 0.04), sign_blue, false)
	_add_label(Vector3(-4.6, 2.25, 10.07), "TECHPARK RING 4", 26, 0.0042, Color(0.96, 0.97, 1.0), 180.0)

	# Tempo-30-Schild gegenüber
	_add_cyl(Vector3(9.5, 1.25, 18.7), 0.035, 0.035, 2.5, pole_mat)
	_add_cyl(Vector3(9.5, 2.28, 18.66), 0.28, 0.28, 0.03, sign_red, Vector3(90, 0, 0))
	_add_cyl(Vector3(9.5, 2.28, 18.645), 0.21, 0.21, 0.03, sign_white, Vector3(90, 0, 0))
	_add_label(Vector3(9.5, 2.28, 18.62), "30", 34, 0.006, Color(0.10, 0.11, 0.13), 180.0)

	# Roter Überflurhydrant + Leitpfosten
	_add_cyl(Vector3(-5.8, 0.38, 10.05), 0.10, 0.12, 0.76, sign_red)
	_add_cyl(Vector3(-5.8, 0.78, 10.05), 0.12, 0.09, 0.09, sign_red)
	for px in [-24.0, -12.0, 12.0, 24.0, 36.0]:
		_add_box(Vector3(float(px), 0.42, 10.55), Vector3(0.10, 0.84, 0.06), sign_white, false)
		_add_box(Vector3(float(px), 0.65, 10.58), Vector3(0.105, 0.14, 0.065), _mat(Color(0.10, 0.11, 0.13), 0.7, 0.0), false)

	# Zebrastreifen bei X = -12
	for zi in range(5):
		_add_box(Vector3(-12.0, -0.012, 11.8 + float(zi) * 1.35), Vector3(2.4, 0.01, 0.65), sign_white, false)

	# Zusätzliche Gehweg-Kante diesseits links/rechts der Einfahrt
	_add_box(Vector3(-25.0, -0.04, 9.75), Vector3(36.0, 0.12, 1.5), curb_mat, false)
	_add_box(Vector3(26.0, -0.04, 9.75), Vector3(40.0, 0.12, 1.5), curb_mat, false)


# ---------------------------------------------------------------- Süden: Nachbarhallen, Trafohäuschen & Parkplatz

func _build_south_industrial_neighbors() -> void:
	var concrete := _mat(Color(0.58, 0.60, 0.62), 0.88, 0.05)
	var steel_dark := _mat(Color(0.20, 0.24, 0.29), 0.55, 0.45)
	var steel_blue := _mat(Color(0.18, 0.28, 0.42), 0.58, 0.35)
	var accent_amber := _mat(Color(0.86, 0.58, 0.12), 0.45, 0.15)
	var roof_mat := _mat(Color(0.24, 0.26, 0.28), 0.85, 0.15)
	var door_mat := _mat(Color(0.32, 0.34, 0.37), 0.65, 0.45)
	var asp_mat := MatLib.get_mat("asphalt")

	# 1. Nachbar-Logistikhalle (Südwest, Z = 29.5, X = -18.0)
	_add_box(Vector3(-18.0, 3.2, 29.5), Vector3(22.0, 6.4, 13.0), concrete, false)
	_add_box(Vector3(-18.0, 6.55, 29.5), Vector3(22.5, 0.35, 13.5), steel_dark, false)
	_add_box(Vector3(-18.0, 5.4, 22.96), Vector3(22.1, 0.42, 0.08), accent_amber, false)
	_add_label(Vector3(-18.0, 5.88, 22.94), "NORDKRAFT LOGISTIK", 42, 0.009, Color(0.95, 0.96, 0.98), 180.0)
	# 3 Rolltore + Bürofenster
	for gx in [-24.0, -18.0, -12.0]:
		_add_box(Vector3(float(gx), 1.9, 22.96), Vector3(3.6, 3.8, 0.12), door_mat, false)
	var win_m1 := _make_window_mat()
	for wx in [-26.5, -24.5, -9.5, -7.5]:
		_add_box(Vector3(float(wx), 4.1, 22.96), Vector3(1.5, 1.1, 0.08), win_m1, false)
	# Dach-Lüftungseinheiten
	_add_box(Vector3(-21.0, 7.1, 28.0), Vector3(2.8, 1.0, 2.2), roof_mat, false)
	_add_box(Vector3(-14.5, 7.0, 30.0), Vector3(2.2, 0.9, 2.0), roof_mat, false)

	# 2. Nachbar-Tech-Bürogebäude (Südost, Z = 30.0, X = 18.0)
	_add_box(Vector3(18.0, 4.0, 30.0), Vector3(20.0, 8.0, 12.0), steel_blue, false)
	_add_box(Vector3(18.0, 8.15, 30.0), Vector3(20.4, 0.32, 12.4), steel_dark, false)
	_add_label(Vector3(18.0, 7.1, 23.94), "RHEIN-TECH SYSTEMS", 40, 0.009, Color(0.94, 0.96, 1.0), 180.0)
	var win_m2 := _make_window_mat()
	for floor_y in [2.2, 4.8]:
		for wx in range(10, 27, 3):
			_add_box(Vector3(float(wx), float(floor_y), 23.95), Vector3(2.1, 1.35, 0.08), win_m2, false)
	# Asphalt-Parkplatz vor dem Bürogebäude mit 3 parkenden Autos
	_add_box(Vector3(18.0, -0.09, 22.4), Vector3(18.0, 0.12, 3.4), asp_mat, false)
	_add_parked_car(Vector3(12.5, 0.0, 22.5), 180.0, Color(0.18, 0.24, 0.34))
	_add_parked_car(Vector3(16.8, 0.0, 22.5), 180.0, Color(0.76, 0.78, 0.80))
	_add_parked_car(Vector3(21.4, 0.0, 22.5), 180.0, Color(0.58, 0.14, 0.14))

	# 3. Städtisches 20-kV-Trafohäuschen (Süden Mitte, Z = 24.0, X = 2.0)
	_add_box(Vector3(2.0, 1.45, 24.4), Vector3(4.2, 2.9, 3.2), concrete, false)
	_add_box(Vector3(2.0, 3.0, 24.4), Vector3(4.5, 0.22, 3.5), roof_mat, false)
	_add_box(Vector3(1.1, 1.15, 22.78), Vector3(1.1, 2.1, 0.08), steel_dark, false)
	_add_box(Vector3(2.8, 1.35, 22.78), Vector3(1.2, 0.9, 0.08), steel_dark, false)
	_add_box(Vector3(1.1, 1.65, 22.72), Vector3(0.32, 0.28, 0.02), accent_amber, false)
	_add_label(Vector3(2.0, 2.52, 22.74), "TRAFO 20 kV", 24, 0.0048, Color(0.95, 0.78, 0.22), 180.0)


# ---------------------------------------------------------------- Westen: Nachbar-Lagerhof, Container & Zaun

func _build_west_yard_and_containers() -> void:
	var fence_mat := _mat(Color(0.22, 0.26, 0.28), 0.55, 0.55)
	var c_blue := _mat(Color(0.14, 0.28, 0.46), 0.68, 0.25)
	var c_rust := _mat(Color(0.54, 0.22, 0.14), 0.74, 0.20)
	var c_gray := _mat(Color(0.36, 0.39, 0.42), 0.72, 0.25)
	var hall_mat := _mat(Color(0.42, 0.45, 0.48), 0.80, 0.18)

	# Industrie-Gitterzaun entlang der Westgrenze (X = -10.8)
	_build_industrial_fence(Vector3(-10.8, 0.0, -10.0), Vector3(-10.8, 0.0, 10.4), fence_mat)

	# Übersee-Container + Nachbar-Lagerhalle links neben der Garage
	_add_box(Vector3(-17.5, 1.3, 4.5), Vector3(2.5, 2.6, 6.0), c_blue, false)
	_add_box(Vector3(-20.4, 1.3, 4.5), Vector3(2.5, 2.6, 6.0), c_rust, false)
	_add_box(Vector3(-18.9, 3.9, 4.5), Vector3(2.5, 2.6, 6.0), c_gray, false)
	_add_box(Vector3(-26.0, 3.0, -4.5), Vector3(14.0, 6.0, 16.0), hall_mat, false)
	_add_box(Vector3(-26.0, 6.15, -4.5), Vector3(14.5, 0.30, 16.5), fence_mat, false)

	for tz in [-14.0, -6.0, 2.0, 8.2]:
		BuildingPropFactory.build_realistic_tree(self, Vector3(-13.4, 0.0, float(tz)), 1.15)


# ---------------------------------------------------------------- Osten: Umspannwerk & Grundstücksgrenze

func _build_east_substation_and_fence() -> void:
	var fence_mat := _mat(Color(0.22, 0.26, 0.28), 0.55, 0.55)
	var concrete := _mat(Color(0.52, 0.54, 0.56), 0.88, 0.05)
	var metal := _mat(Color(0.34, 0.38, 0.42), 0.48, 0.65)
	var dark_panel := _mat(Color(0.10, 0.14, 0.22), 0.28, 0.55)

	# Zaun an der Ostgrenze (hinter Halle C bei X = 26.5)
	_build_industrial_fence(Vector3(26.5, 0.0, -10.0), Vector3(26.5, 0.0, 10.4), fence_mat)

	# Kleines Umspannwerk / Industrietrafos + Solar-Carport rechts hinter Halle C
	_add_box(Vector3(34.0, 0.08, 1.0), Vector3(12.0, 0.16, 14.0), concrete, false)
	for tz in [-2.5, 2.5]:
		_add_box(Vector3(33.5, 1.4, float(tz)), Vector3(2.4, 2.6, 2.0), metal, false)
		for ix in [-0.6, 0.0, 0.6]:
			_add_cyl(Vector3(33.5 + float(ix), 3.1, float(tz)), 0.10, 0.13, 0.85, _mat(Color(0.45, 0.32, 0.24), 0.35, 0.1))

	# Solar-Carport-Dach rechts an der Straße
	for sx in [29.0, 35.0, 41.0]:
		_add_cyl(Vector3(float(sx), 1.4, 7.6), 0.09, 0.09, 2.8, metal)
	var roof := _add_box(Vector3(35.0, 2.88, 7.6), Vector3(14.0, 0.10, 4.4), dark_panel, false)
	roof.rotation_degrees.x = 8.0

	for tz in [-12.0, -5.0, 3.0, 8.4]:
		BuildingPropFactory.build_realistic_tree(self, Vector3(29.0, 0.0, float(tz)), 1.25)


# ---------------------------------------------------------------- Norden: Rückseite, Schallschutz & Fernmeldeturm

func _build_north_hinterland_and_tower() -> void:
	var fence_mat := _mat(Color(0.22, 0.26, 0.28), 0.55, 0.55)
	var wall_mat := _mat(Color(0.46, 0.48, 0.45), 0.90, 0.0)
	var tower_mat := _mat(Color(0.62, 0.64, 0.67), 0.72, 0.25)

	# Zaun + Schallschutzwall hinter dem Rechenzentrum (Z = -10.0 bis -18.0)
	_build_industrial_fence(Vector3(-10.8, 0.0, -10.0), Vector3(26.5, 0.0, -10.0), fence_mat)
	_add_box(Vector3(8.0, 1.8, -16.5), Vector3(68.0, 3.6, 1.4), wall_mat, false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	for i in range(18):
		var tx := -26.0 + float(i) * 4.2 + rng.randf_range(-0.8, 0.8)
		var tz := rng.randf_range(-14.5, -11.5)
		BuildingPropFactory.build_realistic_tree(self, Vector3(tx, 0.0, tz), rng.randf_range(1.1, 1.55))

	# Fernmelde-/Richtfunkturm im Hintergrund mit blinkendem rotem Warnlicht bei Nacht!
	var tpos := Vector3(14.0, 0.0, -54.0)
	_add_cyl(tpos + Vector3(0.0, 18.0, 0.0), 0.65, 1.65, 36.0, tower_mat)
	_add_cyl(tpos + Vector3(0.0, 26.0, 0.0), 2.8, 2.4, 2.4, _mat(Color(0.24, 0.28, 0.34), 0.55, 0.35))
	_add_cyl(tpos + Vector3(0.0, 39.5, 0.0), 0.14, 0.35, 7.0, _mat(Color(0.84, 0.16, 0.14), 0.55, 0.2))
	_tower_beacon_mat = StandardMaterial3D.new()
	_tower_beacon_mat.albedo_color = Color(1.0, 0.15, 0.12)
	_tower_beacon_mat.emission_enabled = true
	_tower_beacon_mat.emission = Color(1.0, 0.12, 0.10)
	_tower_beacon_mat.emission_energy_multiplier = 3.0
	var beacon := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.38
	bsm.height = 0.76
	beacon.mesh = bsm
	beacon.material_override = _tower_beacon_mat
	beacon.position = tpos + Vector3(0.0, 43.2, 0.0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)


# ---------------------------------------------------------------- Vorbeifahrender KI-Verkehr

func _build_ambient_traffic() -> void:
	var specs := [
		{"x": -52.0, "z": 12.65, "dir": 1.0,  "speed": 9.8,  "col": Color(0.76, 0.79, 0.82), "is_van": false},
		{"x":  24.0, "z": 12.65, "dir": 1.0,  "speed": 8.4,  "col": Color(0.16, 0.26, 0.44), "is_van": true},
		{"x":  58.0, "z": 16.35, "dir": -1.0, "speed": 10.6, "col": Color(0.68, 0.16, 0.16), "is_van": false},
		{"x": -18.0, "z": 16.35, "dir": -1.0, "speed": 8.9,  "col": Color(0.22, 0.25, 0.28), "is_van": true},
	]
	for sp in specs:
		var car_root := _create_traffic_vehicle(sp["col"] as Color, bool(sp["is_van"]))
		car_root.position = Vector3(float(sp["x"]), 0.0, float(sp["z"]))
		car_root.rotation_degrees.y = 90.0 if float(sp["dir"]) > 0.0 else -90.0
		add_child(car_root)
		_traffic_cars.append({
			"node": car_root,
			"dir": float(sp["dir"]),
			"speed": float(sp["speed"]),
			"z": float(sp["z"]),
		})


func _create_traffic_vehicle(body_col: Color, is_van: bool) -> Node3D:
	var root := Node3D.new()
	var paint := _mat(body_col, 0.28, 0.35)
	var glass := _mat(Color(0.12, 0.18, 0.24), 0.12, 0.45)
	var tire := _mat(Color(0.08, 0.08, 0.09), 0.85, 0.0)
	var rim := _mat(Color(0.75, 0.78, 0.82), 0.25, 0.80)

	var head_m := StandardMaterial3D.new()
	head_m.albedo_color = Color(1.0, 0.98, 0.90)
	head_m.emission_enabled = true
	head_m.emission = Color(1.0, 0.96, 0.84)
	head_m.emission_energy_multiplier = 0.25
	_car_headlight_mats.append(head_m)

	var tail_m := StandardMaterial3D.new()
	tail_m.albedo_color = Color(0.95, 0.15, 0.12)
	tail_m.emission_enabled = true
	tail_m.emission = Color(1.0, 0.12, 0.10)
	tail_m.emission_energy_multiplier = 0.35
	_car_taillight_mats.append(tail_m)

	var length := 4.8 if is_van else 4.2
	var h_body := 0.78 if is_van else 0.62
	_add_box_to(root, Vector3(0.0, 0.32 + h_body * 0.5, 0.0), Vector3(1.86, h_body, length), paint)
	if is_van:
		_add_box_to(root, Vector3(0.0, 1.48, -0.45), Vector3(1.82, 0.92, 3.3), paint)
		_add_box_to(root, Vector3(0.0, 1.38, 1.24), Vector3(1.68, 0.58, 0.12), glass)
	else:
		_add_box_to(root, Vector3(0.0, 1.18, -0.18), Vector3(1.62, 0.56, 2.05), paint)
		_add_box_to(root, Vector3(0.0, 1.16, -0.18), Vector3(1.65, 0.44, 1.78), glass)

	# Scheinwerfer vorn (+Z lokal) & Rücklichter hinten (-Z lokal)
	var zf := length * 0.5 + 0.01
	for sx in [-0.64, 0.64]:
		_add_box_to(root, Vector3(float(sx), 0.66, zf), Vector3(0.32, 0.14, 0.04), head_m)
		_add_box_to(root, Vector3(float(sx), 0.66, -zf), Vector3(0.32, 0.14, 0.04), tail_m)

	# 4 Räder
	for wx in [-0.90, 0.90]:
		for wz in [-1.32, 1.32]:
			_add_cyl_to(root, Vector3(float(wx), 0.32, float(wz)), 0.32, 0.32, 0.22, tire, Vector3(0, 0, 90))
			_add_cyl_to(root, Vector3(float(wx) + (0.02 if float(wx) > 0.0 else -0.02), 0.32, float(wz)), 0.17, 0.17, 0.22, rim, Vector3(0, 0, 90))
	return root


func _add_parked_car(pos: Vector3, yaw_deg: float, col: Color) -> void:
	var c := _create_traffic_vehicle(col, false)
	c.position = pos
	c.rotation_degrees.y = yaw_deg
	add_child(c)


func _update_traffic(delta: float) -> void:
	var van_busy := GameState.van_phase == "arriving" or GameState.van_phase == "departing"
	for entry in _traffic_cars:
		var node: Node3D = entry["node"]
		var dir: float = float(entry["dir"])
		var spd: float = float(entry["speed"])
		# Kurz warten, falls der Lieferwagen gerade direkt an der Einfahrt rangiert
		if van_busy and absf(node.position.x) < 12.0 and dir > 0.0 and node.position.x < -3.0:
			continue
		node.position.x += dir * spd * delta
		if dir > 0.0 and node.position.x > TRAFFIC_X_MAX:
			node.position.x = TRAFFIC_X_MIN
		elif dir < 0.0 and node.position.x < TRAFFIC_X_MIN:
			node.position.x = TRAFFIC_X_MAX


# ---------------------------------------------------------------- Wetter: 3D-Regen & Gewitter-Blitze

func _build_weather_vfx() -> void:
	var drop_count := 260
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.55, 0.012)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.76, 0.86, 0.98, 0.38)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = drop_count

	var rng := RandomNumberGenerator.new()
	rng.seed = 8842
	_rain_drops.clear()
	_rain_speeds.resize(drop_count)
	for i in range(drop_count):
		var p := Vector3(rng.randf_range(-16.0, 26.0), rng.randf_range(0.0, 11.0), rng.randf_range(5.2, 22.0))
		_rain_drops.append(p)
		_rain_speeds[i] = rng.randf_range(14.5, 19.5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))

	_rain_mm_inst = MultiMeshInstance3D.new()
	_rain_mm_inst.multimesh = mm
	_rain_mm_inst.material_override = rmat
	_rain_mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mm_inst.visible = false
	add_child(_rain_mm_inst)

	_lightning_light = DirectionalLight3D.new()
	_lightning_light.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	_lightning_light.light_color = Color(0.84, 0.92, 1.0)
	_lightning_light.light_energy = 0.0
	_lightning_light.shadow_enabled = false
	add_child(_lightning_light)


func _update_weather(delta: float) -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var raining := (w == "rain" or w == "storm")
	if _rain_mm_inst != null:
		_rain_mm_inst.visible = raining
		if raining:
			var mm := _rain_mm_inst.multimesh
			var wind_x := -2.6 if w == "storm" else -0.9
			var tilt := Basis.from_euler(Vector3(0.0, 0.0, -0.14 if w == "storm" else -0.05))
			for i in range(_rain_drops.size()):
				var p: Vector3 = _rain_drops[i]
				p.y -= _rain_speeds[i] * delta
				p.x += wind_x * delta
				if p.y < 0.0:
					p.y += 11.0
					if p.x < -16.0:
						p.x += 42.0
				_rain_drops[i] = p
				mm.set_instance_transform(i, Transform3D(tilt, p))

	if _lightning_light != null:
		if w == "storm":
			_lightning_cooldown -= delta
			if _lightning_cooldown <= 0.0:
				_lightning_cooldown = randf_range(8.0, 18.0)
				_lightning_flash = 1.0
				SfxManager.play("thunder", -6.0, randf_range(0.88, 1.12))
		if _lightning_flash > 0.0:
			_lightning_flash = maxf(0.0, _lightning_flash - delta * 4.2)
			var flicker := 1.0 if fmod(_lightning_flash * 14.0, 1.0) > 0.35 else 0.25
			_lightning_light.light_energy = _lightning_flash * 3.8 * flicker
		else:
			_lightning_light.light_energy = 0.0


func _update_night_lights() -> void:
	var tod := GameState.time_of_day if GameState.is_active else 0.38
	var elev := sin((tod - 0.25) * TAU)
	var night := clampf((-elev + 0.14) * 3.2, 0.0, 1.0)
	var storm_dark := 0.35 if GameState.weather_state == "storm" else 0.0
	var on_lvl := clampf(maxf(night, storm_dark), 0.0, 1.0)

	for m in _street_lamp_mats:
		m.emission_energy_multiplier = lerpf(0.15, 3.6, on_lvl)
	for wm in _window_mats:
		wm.emission_energy_multiplier = lerpf(0.05, 1.25, night)
	for hm in _car_headlight_mats:
		hm.emission_energy_multiplier = lerpf(0.3, 3.8, on_lvl)
	for tm in _car_taillight_mats:
		tm.emission_energy_multiplier = lerpf(0.4, 2.4, on_lvl)
	if _tower_beacon_mat != null:
		var blink := 1.0 if sin(_anim_t * 3.2) > 0.1 else 0.15
		_tower_beacon_mat.emission_energy_multiplier = lerpf(0.5, 5.5, night) * blink


# ---------------------------------------------------------------- Geometrie-Helfer

func _build_industrial_fence(a: Vector3, b: Vector3, mat: Material) -> void:
	var d := b - a
	var length := d.length()
	var mid := (a + b) * 0.5
	var yaw := atan2(d.x, d.z)
	for rail_y in [0.25, 1.10, 1.95]:
		var rail := _add_box(Vector3(mid.x, float(rail_y), mid.z), Vector3(0.04, 0.05, length), mat, false)
		rail.rotation.y = yaw
	var posts := maxi(2, int(roundf(length / 2.6)))
	for i in range(posts + 1):
		var p := a.lerp(b, float(i) / float(posts))
		_add_box(Vector3(p.x, 1.05, p.z), Vector3(0.08, 2.10, 0.08), mat, false)


func _make_window_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.22, 0.28)
	m.roughness = 0.14
	m.metallic = 0.35
	m.emission_enabled = true
	m.emission = Color(0.95, 0.88, 0.68)
	m.emission_energy_multiplier = 0.05
	_window_mats.append(m)
	return m


func _add_box(pos: Vector3, dims: Vector3, mat: Material, shadow: bool = false) -> MeshInstance3D:
	return _add_box_to(self, pos, dims, mat, shadow)


func _add_box_to(parent: Node3D, pos: Vector3, dims: Vector3, mat: Material, shadow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = dims
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cyl(pos: Vector3, top_r: float, bot_r: float, h: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_cyl_to(self, pos, top_r, bot_r, h, mat, rot_deg)


func _add_cyl_to(parent: Node3D, pos: Vector3, top_r: float, bot_r: float, h: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_label(pos: Vector3, txt: String, fsize: int, px_size: float, col: Color, yaw_deg: float = 0.0) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = fsize
	lbl.pixel_size = px_size
	lbl.position = pos
	lbl.rotation_degrees.y = yaw_deg
	lbl.modulate = col
	add_child(lbl)
	return lbl


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
