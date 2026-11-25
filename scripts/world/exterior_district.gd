class_name ExteriorDistrict
extends Node3D
## Außenwelt 3.1 (Deutsches Gewerbegebiet "Techpark Ring 4" + Logik & Lebendiger Horizont):
## - 100 % echte Blender-5.2-PBR-Modelle (Gebaeude, Fahrzeuge, Baeume, Hecken, Laternen, Zaeune)
## - Bauliche Logik ohne "random Gras": Querstrassen, hintere Ringstrasse (Z=42.5), gepflasterte
##   LKW-Ladehoefe mit angedockten Aufliegern, gestrichelte Parkplaetze, eingezäuntes 20-kV-Umspannwerk
##   mit Hochspannungsmasten & gespannten Leitungen sowie Einfahrten + Autos an allen Hintergrund-Haeusern!
## - Lebendige Hintergrund-Illusion (minimalste Last, 60+ FPS):
##   * Pendelnder gelber Gabelstapler mit Blinklicht bei Nordkraft Logistik (+ leises fernes Hof-Piepen)
##   * 5 drehende Windraeder mit rotem Flugsicherungs-Blinklicht am Horizont
##   * Langsam schwenkender gelber Baukran + Heizkraftwerk mit aufsteigenden Dampfwolken
##   * Erhoehte Fern-Autobahn (Z=82) mit 24 fliessenden Scheinwerfer-/Ruecklicht-Stroemen (MultiMesh!)
##   * Zweiter Hintergrund-Verkehr auf der Ringstrasse + wehende Firmen-Fahnen
##   * Vögel und Tiere siehe Wildlife, gelegentliches Flugzeug mit Kondensstreifen & Jet-Sound

const TRAFFIC_X_MIN := -86.0
const TRAFFIC_X_MAX := 90.0

var _street_lamp_mats: Array[StandardMaterial3D] = []
var _street_spot_lights: Array[SpotLight3D] = []
var _evening_window_mats: Array[StandardMaterial3D] = []
var _aviation_beacon_mats: Array[StandardMaterial3D] = []
var _traffic_cars: Array[Dictionary] = []
var _bg_traffic_cars: Array[Dictionary] = []
var _wind_materials: Array[ShaderMaterial] = []
var _flag_materials: Array[ShaderMaterial] = []
var _substation_audio: AudioStreamPlayer3D

# Lebendiger Horizont & Hof-Animationen
var _turbine_rotors: Array[Dictionary] = []
var _crane_jib: Node3D
var _forklift_node: Node3D
var _forklift_beacon_mat: StandardMaterial3D
var _forklift_audio: AudioStreamPlayer3D
var _forklift_phase: float = 0.0
var _forklift_beep_accum: float = 0.0
var _steam_emitters: Array[CPUParticles3D] = []

# Fern-Autobahn Lichterstroeme (1 MultiMesh je Richtung = 2 Draw Calls!)
var _hw_head_mm: MultiMesh
var _hw_tail_mm: MultiMesh
var _hw_cars: Array[Dictionary] = []

# Hohes Linienflugzeug + Kondensstreifen
var _jet_node: Node3D
var _jet_timer: float = 28.0
var _jet_active: bool = false
var _jet_t: float = 0.0
var _jet_start: Vector3 = Vector3(-135.0, 68.0, 72.0)
var _jet_end: Vector3 = Vector3(145.0, 72.0, -42.0)

# 3D-Regen & Gewitter-Blitze
var _rain_mm_inst: MultiMeshInstance3D
var _rain_drops: Array[Vector3] = []
var _snow_mode := false
var _drop_mesh: Mesh
var _rain_speeds: PackedFloat32Array = PackedFloat32Array()
var _lightning_light: DirectionalLight3D
var _lightning_flash: float = 0.0
var _lightning_cooldown: float = 9.0
var _anim_t: float = 0.0
var _wind_shader: Shader
var _flag_shader: Shader


func _ready() -> void:
	_init_wind_shader()
	_init_flag_shader()
	_build_360_terrain_and_horizon()
	_build_logical_road_network()
	_build_extended_road_and_lamps()
	_build_south_industrial_neighbors()
	_build_west_yard_and_containers()
	_build_east_substation_and_fence()
	_build_north_hinterland_and_tower()
	_build_living_horizon_landmarks()
	_build_ambient_traffic()
	_build_background_ring_traffic()
	_build_distant_highway_stream()
	_build_sky_life()
	MeshMerger.set_outside(self)
	_build_weather_vfx()


func _process(delta: float) -> void:
	_anim_t += delta
	_update_night_lights()
	_update_traffic(delta)
	_update_background_ring_traffic(delta)
	_update_living_horizon(delta)
	_update_sky_life(delta)
	_update_weather(delta)
	_update_wind_shader()
	_update_substation_audio()


# ---------------------------------------------------------------- Wind- & Flaggen-Shader

func _init_wind_shader() -> void:
	_wind_shader = Shader.new()
	_wind_shader.code = """
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(0.20, 0.40, 0.16, 1.0);
uniform float roughness_val = 0.78;
uniform float wind_strength = 0.08;
uniform float wind_speed = 1.65;
uniform float height_start = 0.15;
uniform vec3 season_mul = vec3(1.0);
uniform float snow = 0.0;
varying float v_up;

varying vec3 v_wpos;
varying vec3 v_lpos;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i + vec3(0,0,0)), hash31(i + vec3(1,0,0)), f.x),
		    mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
		    mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
}

void vertex() {
	v_lpos = VERTEX;
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h_factor = clamp((VERTEX.y - height_start) * 0.28, 0.0, 1.8);
	float phase = TIME * wind_speed + wpos.x * 0.35 + wpos.z * 0.28;
	float sway_x = sin(phase) * 0.65 + sin(phase * 2.13 + wpos.y * 0.8) * 0.35;
	float sway_z = cos(phase * 0.87 + wpos.x * 0.22) * 0.55;
	VERTEX.x += sway_x * wind_strength * h_factor;
	VERTEX.z += sway_z * wind_strength * h_factor;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float leaf_fine = vnoise3(v_wpos * 14.5);
	float leaf_mid = vnoise3(v_wpos * 4.8);
	float dapple = mix(0.44, 1.12, leaf_fine * 0.65 + leaf_mid * 0.35);
	float sun_tip = clamp(0.76 + v_lpos.y * 0.048, 0.68, 1.08);
	vec3 warm_shift = mix(vec3(0.76, 0.90, 0.80), vec3(1.02, 1.00, 0.78), leaf_fine);
	vec3 c = albedo_color.rgb * 0.78 * dapple * sun_tip * warm_shift * season_mul;
	ALBEDO = mix(c, vec3(0.88, 0.91, 0.95), smoothstep(0.1, 0.6, v_up + (leaf_fine - 0.5) * 0.6) * snow);
	ROUGHNESS = clamp(roughness_val + (0.5 - leaf_fine) * 0.16, 0.58, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
"""


func _init_flag_shader() -> void:
	_flag_shader = Shader.new()
	_flag_shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 flag_color : source_color = vec4(0.12, 0.30, 0.58, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.92, 0.68, 0.14, 1.0);
uniform float wind_amp = 0.09;
uniform float wind_speed = 4.2;

varying float v_u;
varying float v_v;

void vertex() {
	v_u = clamp((VERTEX.x - 0.08) / 0.98, 0.0, 1.0);
	v_v = clamp((VERTEX.y - 4.55) / 2.45, 0.0, 1.0);
	float loose = (1.0 - v_v * 0.65) * (0.25 + v_u * 0.75);
	float wave = sin(TIME * wind_speed - v_v * 4.8 - v_u * 3.5) * wind_amp * loose;
	VERTEX.z += wave;
	VERTEX.x += cos(TIME * wind_speed * 0.85 - v_v * 3.0) * wind_amp * 0.35 * loose;
}

void fragment() {
	float band = step(0.16, v_u) * (1.0 - step(0.30, v_u));
	ALBEDO = mix(flag_color.rgb, stripe_color.rgb, band);
	ROUGHNESS = 0.76;
	METALLIC = 0.0;
}
"""


func _apply_wind_to_canopy(root_node: Node3D, height_start: float = 0.20, tint_shift: float = 1.0) -> void:
	if _wind_shader == null or root_node == null:
		return
	var canopy := root_node.find_child("Canopy", true, false) as MeshInstance3D
	if canopy == null or canopy.mesh == null:
		return
	for surf_i in range(canopy.mesh.get_surface_count()):
		var orig := canopy.mesh.surface_get_material(surf_i)
		var base_col := Color(0.20, 0.40, 0.16)
		var rough := 0.78
		if orig is BaseMaterial3D:
			var bm := orig as BaseMaterial3D
			base_col = bm.albedo_color
			rough = bm.roughness
		var sm := ShaderMaterial.new()
		sm.shader = _wind_shader
		sm.set_shader_parameter("albedo_color", Color(
			clampf(base_col.r * tint_shift, 0.04, 1.0),
			clampf(base_col.g * tint_shift, 0.06, 1.0),
			clampf(base_col.b * tint_shift, 0.04, 1.0),
			1.0
		))
		sm.set_shader_parameter("roughness_val", rough)
		sm.set_shader_parameter("height_start", height_start)
		canopy.set_surface_override_material(surf_i, sm)
		_wind_materials.append(sm)


func _spawn_flagpole(pos: Vector3, yaw_deg: float, flag_col: Color, stripe_col: Color) -> void:
	var fp := _spawn_blender_model("ext_flagpole", pos, yaw_deg)
	if fp == null or _flag_shader == null:
		return
	var flag_mi := fp.find_child("Flag", true, false) as MeshInstance3D
	if flag_mi != null:
		var sm := ShaderMaterial.new()
		sm.shader = _flag_shader
		sm.set_shader_parameter("flag_color", flag_col)
		sm.set_shader_parameter("stripe_color", stripe_col)
		flag_mi.material_override = sm
		_flag_materials.append(sm)


func _update_wind_shader() -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var target_str := 0.065
	var target_spd := 1.45
	var f_amp := 0.09
	var f_spd := 4.2
	if w == "storm":
		target_str = 0.24
		target_spd = 3.45
		f_amp = 0.22
		f_spd = 9.5
	elif w == "rain":
		target_str = 0.135
		target_spd = 2.25
		f_amp = 0.14
		f_spd = 6.2
	elif w == "cloudy":
		target_str = 0.095
		target_spd = 1.80
		f_amp = 0.11
		f_spd = 5.0
	for sm in _wind_materials:
		if sm != null:
			sm.set_shader_parameter("wind_strength", target_str)
			sm.set_shader_parameter("season_mul", Vector3.ONE.lerp(Vector3(1.5, 0.92, 0.5), Nature.mix4([0.0, 0.0, 0.75, 0.45])))
			sm.set_shader_parameter("snow", OutdoorManager.snow_shown)
			sm.set_shader_parameter("wind_speed", target_spd)
	for fm in _flag_materials:
		if fm != null:
			fm.set_shader_parameter("wind_amp", f_amp)
			fm.set_shader_parameter("wind_speed", f_spd)


# ---------------------------------------------------------------- 360°-Gelände & dichte Horizont-Kulisse (0 % Void!)

func _build_360_terrain_and_horizon() -> void:
	var grass_mat := MatLib.get_mat("grass")
	var terrain_mat := Nature.meadow(grass_mat, 0.22)

	# 560 × 560 m Grundboden in alle 4 Himmelsrichtungen
	_add_box(Vector3(6.0, -0.32, 8.0), Vector3(560.0, 0.20, 560.0), terrain_mat, false)

	# 360°-Hügelkette am fernen Horizont
	var hill_mat := _mat(Color(0.16, 0.24, 0.16), 0.96, 0.0)
	Nature.register_tint(hill_mat, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	for i in range(34):
		var ang := (float(i) / 34.0) * TAU
		var dist := rng.randf_range(118.0, 156.0)
		var hx := 6.0 + cos(ang) * dist
		var hz := 10.0 + sin(ang) * dist
		var hw := rng.randf_range(38.0, 68.0)
		var hh := rng.randf_range(9.0, 22.0)
		var hd := rng.randf_range(26.0, 44.0)
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

	# Dichter 360°-Waldgürtel am Übergang zur Hügellandschaft (58..76 m, Straßen & Autobahn ausgespart!)
	for ti in range(48):
		var ang := (float(ti) / 48.0) * TAU + rng.randf_range(-0.03, 0.03)
		var dist := rng.randf_range(60.0, 74.0)
		var tx := 4.0 + cos(ang) * dist
		var tz := 14.0 + sin(ang) * dist
		if (tz > 9.0 and tz < 21.0) or (tz > 38.0 and tz < 47.0):
			continue
		if absf(tx - (-38.0)) < 5.0 or absf(tx - 36.0) < 5.0:
			continue
		spawn_tree(Vector3(tx, 0.0, tz), (ti % 2 == 0), rng.randf_range(1.0, 1.48), rng.randf_range(0.0, 360.0), false)


# ---------------------------------------------------------------- Bauliche Logik: Querstraßen, Ringstraße & Wohnsiedlung!

func _build_logical_road_network() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var curb_mat := _mat(Color(0.55, 0.56, 0.58), 0.88, 0.0)
	var walk_mat := _mat(Color(0.60, 0.60, 0.58), 0.90, 0.0)
	var stripe_mat := _mat(Color(0.90, 0.90, 0.88), 0.78, 0.0)

	# 1. Hintere Parallel-Ringstraße "GEWERBERING SÜD" bei Z = 42.5 (verbindet alle hinteren Höfe & Wohnhäuser!)
	_add_box(Vector3(2.0, -0.13, 42.5), Vector3(170.0, 0.20, 7.2), asp_mat, false)
	for sx in range(-78, 84, 5):
		_add_box(Vector3(float(sx), -0.024, 42.5), Vector3(2.0, 0.01, 0.13), stripe_mat, false)
	for cz in [38.85, 46.15]:
		_add_box(Vector3(2.0, -0.02, float(cz)), Vector3(170.0, 0.12, 0.18), curb_mat, false)
	_add_box(Vector3(2.0, -0.06, 47.15), Vector3(170.0, 0.18, 1.8), walk_mat, false) # Gehweg vor der Wohnsiedlung!

	# 2. Zwei echte Querstraßen (West bei X = -38.0 & Ost bei X = +36.0) von Hauptstraße (Z=14.5) nach Ringstraße (Z=42.5)
	for qx in [-38.0, 36.0]:
		_add_box(Vector3(float(qx), -0.125, 34.0), Vector3(6.8, 0.20, 42.0), asp_mat, false)
		for sz in range(19, 54, 5):
			_add_box(Vector3(float(qx), -0.020, float(sz)), Vector3(0.13, 0.01, 2.0), stripe_mat, false)
		for dx in [-3.45, 3.45]:
			_add_box(Vector3(float(qx) + float(dx), -0.02, 34.0), Vector3(0.18, 0.12, 42.0), curb_mat, false)
		# Straßenlaternen entlang der Quer- & Ringstraße
		for lz in [26.0, 38.5]:
			var lamp := _spawn_blender_model("ext_street_lamp", Vector3(float(qx) - 3.8, 0.0, float(lz)), 90.0)
			if lamp != null:
				var gm := _clone_material_by_name(lamp, "Lamp_GlassMat")
				if gm != null:
					_street_lamp_mats.append(gm)

	for lx in [-24.0, -4.0, 16.0, 46.0]:
		var blamp := _spawn_blender_model("ext_street_lamp", Vector3(float(lx), 0.0, 46.8), 180.0)
		if blamp != null:
			var gm := _clone_material_by_name(blamp, "Lamp_GlassMat")
			if gm != null:
				_street_lamp_mats.append(gm)

	# 3. Geordnete Wohnsiedlung entlang der Südseite der Ringstraße (Z = 54.5):
	#    JEDES Haus steht auf einem klaren Grundstück mit eigener Asphalt-Einfahrt, parkendem Auto & Hecke!
	var house_slots: Array = [
		[-26.0, 180.0, "ext_car_sedan", Color(0.22, 0.34, 0.46)],
		[-9.0,  180.0, "ext_car_suv",   Color(0.76, 0.78, 0.80)],
		[9.0,   180.0, "ext_car_sedan", Color(0.54, 0.16, 0.14)],
		[26.0,  180.0, "ext_car_van",   Color(0.90, 0.91, 0.92)],
	]
	for hs in house_slots:
		var hx: float = float(hs[0])
		var hyaw: float = float(hs[1])
		var hnode := _spawn_blender_model("ext_house_suburban", Vector3(hx, 0.0, 54.8), hyaw)
		_register_evening_windows(hnode, "House_GlassMat")
		# Gepflasterte Einfahrt direkt von der Ringstraße (Z=47) bis vor Garage/Haustür (Z=53)
		_add_box(Vector3(hx - 5.2, -0.10, 50.2), Vector3(3.8, 0.12, 6.2), asp_mat, false)
		_add_box(Vector3(hx, -0.09, 49.6), Vector3(1.8, 0.12, 4.8), walk_mat, false)
		# Parkendes Auto in der eigenen Einfahrt!
		_spawn_parked_vehicle(str(hs[2]), Vector3(hx - 5.2, 0.0, 50.4), 90.0, hs[3] as Color)
		# Grundstücks-Hecke vorne am Gehweg (links/rechts der Einfahrt)
		var hedge := _spawn_blender_model("ext_hedge_bush", Vector3(hx + 3.2, 0.0, 48.3), 0.0, Vector3(2.4, 1.0, 1.0))
		_apply_wind_to_canopy(hedge, 0.10, 0.96)
		# Gartenbaum neben jedem Haus
		spawn_tree(Vector3(hx + 7.2, 0.0, 52.8), false, 0.92, hx * 13.0, false)

	# Zusätzliche entfernte Häuser hinter den Seitenstraßen & im Norden
	for extra in [
		[Vector3(-52.0, 0.0, 26.0), 90.0],
		[Vector3(-52.0, 0.0, -14.0), 90.0],
		[Vector3(56.0, 0.0, 24.0), -90.0],
		[Vector3(-18.0, 0.0, -34.0), 0.0],
		[Vector3(8.0, 0.0, -36.0), 0.0],
		[Vector3(34.0, 0.0, -34.0), 0.0],
	]:
		var eh := _spawn_blender_model("ext_house_suburban", extra[0] as Vector3, float(extra[1]))
		_register_evening_windows(eh, "House_GlassMat")


# ---------------------------------------------------------------- Hauptstraße, Blender-Laternen, Gullys & Schilder

func _build_extended_road_and_lamps() -> void:
	var pole_mat := MatLib.make_brushed_metal(Color(0.24, 0.27, 0.30), 0.45, 0.65)
	var sign_blue := _mat(Color(0.09, 0.30, 0.66), 0.45, 0.15)
	var sign_white := _mat(Color(0.92, 0.93, 0.95), 0.55, 0.05)
	var sign_red := _mat(Color(0.84, 0.14, 0.14), 0.45, 0.10)
	var curb_mat := _mat(Color(0.55, 0.56, 0.58), 0.88, 0.0)

	var lamp_specs: Array = [
		[Vector3(-48.0, 0.0, 10.15), 0.0, false],
		[Vector3(-30.0, 0.0, 10.15), 0.0, false],
		[Vector3(-14.0, 0.0, 10.15), 0.0, true],
		[Vector3(18.0, 0.0, 10.15), 0.0, true],
		[Vector3(30.0, 0.0, 10.15), 0.0, false],
		[Vector3(50.0, 0.0, 10.15), 0.0, false],
		[Vector3(-24.0, 0.0, 18.85), 180.0, false],
		[Vector3(-2.0, 0.0, 18.85), 180.0, true],
		[Vector3(24.0, 0.0, 18.85), 180.0, false],
		[Vector3(44.0, 0.0, 18.85), 180.0, false],
	]
	for ls in lamp_specs:
		var lpos: Vector3 = ls[0]
		var lyaw: float = float(ls[1])
		var add_spot: bool = bool(ls[2])
		var lamp := _spawn_blender_model("ext_street_lamp", lpos, lyaw)
		if lamp != null:
			var gmat := _clone_material_by_name(lamp, "Lamp_GlassMat")
			if gmat != null:
				_street_lamp_mats.append(gmat)
		if add_spot:
			var sp := SpotLight3D.new()
			var arm_z := 1.35 if lyaw < 90.0 else -1.35
			sp.position = lpos + Vector3(0.0, 5.35, arm_z)
			sp.rotation_degrees.x = -90.0
			sp.light_color = Color(1.0, 0.90, 0.70)
			sp.light_energy = 0.0
			sp.spot_range = 13.0
			sp.spot_angle = 62.0
			sp.shadow_enabled = false
			add_child(sp)
			_street_spot_lights.append(sp)

	_add_cyl(Vector3(-4.6, 1.25, 10.05), 0.035, 0.035, 2.5, pole_mat)
	_add_box(Vector3(-4.6, 2.25, 10.05), Vector3(0.98, 0.28, 0.04), sign_blue, false)
	_add_label(Vector3(-4.6, 2.25, 10.02), "TECHPARK RING 4", 26, 0.0042, Color(0.96, 0.97, 1.0), 180.0)

	_add_cyl(Vector3(9.5, 1.25, 18.75), 0.035, 0.035, 2.5, pole_mat)
	_add_cyl(Vector3(9.5, 2.28, 18.71), 0.28, 0.28, 0.03, sign_red, Vector3(90, 0, 0))
	_add_cyl(Vector3(9.5, 2.28, 18.695), 0.21, 0.21, 0.03, sign_white, Vector3(90, 0, 0))
	_add_label(Vector3(9.5, 2.28, 18.67), "30", 34, 0.006, Color(0.10, 0.11, 0.13), 180.0)

	_spawn_blender_model("ext_hydrant", Vector3(-5.8, 0.0, 9.95), 0.0)
	_spawn_blender_model("ext_utility_box", Vector3(6.2, 0.0, 9.55), 180.0)
	for mx in [-26.0, -8.5, 8.5, 26.0]:
		_spawn_blender_model("ext_manhole", Vector3(float(mx), -0.015, 11.45), 0.0)
		_spawn_blender_model("ext_manhole", Vector3(float(mx) + 4.0, -0.015, 17.55), 0.0)

	for px in [-24.0, -12.0, 12.0, 24.0, 31.0]:
		_add_box(Vector3(float(px), 0.42, 10.55), Vector3(0.10, 0.84, 0.06), sign_white, false)
		_add_box(Vector3(float(px), 0.65, 10.58), Vector3(0.105, 0.14, 0.065), _mat(Color(0.10, 0.11, 0.13), 0.7, 0.0), false)

	for zi in range(5):
		_add_box(Vector3(-12.0, -0.012, 11.8 + float(zi) * 1.35), Vector3(2.4, 0.01, 0.65), sign_white, false)

	_add_box(Vector3(-21.0, -0.04, 9.75), Vector3(28.0, 0.12, 1.5), curb_mat, false)
	_add_box(Vector3(21.0, -0.04, 9.75), Vector3(26.0, 0.12, 1.5), curb_mat, false)

	var grng := RandomNumberGenerator.new()
	grng.seed = 6612
	for gx in [-10.2, -7.8, -5.2, 4.4, 7.6, 11.2, 14.5, -16.0, -4.5, 5.5, 16.5]:
		var gz := 10.25 if gx < 14.0 else 18.65
		var tuft := _spawn_blender_model("ext_grass_tuft", Vector3(float(gx), 0.0, gz), grng.randf_range(0.0, 360.0), Vector3.ONE * grng.randf_range(0.85, 1.25))
		_apply_wind_to_canopy(tuft, 0.02, grng.randf_range(0.90, 1.10))

	# Hecken auf der Gegenseite (LKW-Einfahrt bei Nordkraft, Trafo-Zufahrt & Büro-Parkplatz bleiben logisch offen!)
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 4712
	var hx := -33.0
	while hx <= 31.0:
		var is_open := (hx > -32.0 and hx < -25.0) or (hx > -1.5 and hx < 4.5) or (hx > 10.0 and hx < 26.0)
		if not is_open:
			var hnode := _spawn_blender_model("ext_hedge_bush", Vector3(hx, 0.0, 20.65), hrng.randf_range(-4.0, 4.0), Vector3(1.05, hrng.randf_range(0.92, 1.18), 1.0))
			_apply_wind_to_canopy(hnode, 0.10, hrng.randf_range(0.88, 1.12))
		hx += 2.25


# ---------------------------------------------------------------- Süden: Logische Höfe, Gabelstapler, Auflieger & 20-kV-Trasse

func _build_south_industrial_neighbors() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var gravel_mat := _mat(Color(0.46, 0.45, 0.43), 0.96, 0.0)
	var stripe_w := _mat(Color(0.90, 0.90, 0.88), 0.78, 0.0)
	var stripe_y := _mat(Color(0.92, 0.72, 0.12), 0.68, 0.0)

	# 1. NORDKRAFT LOGISTIK: kompletter gepflasterter LKW-Ladehof (X = -33..-5, Z = 20..38.5)
	_add_box(Vector3(-19.0, -0.10, 29.5), Vector3(28.5, 0.12, 18.2), asp_mat, false)
	var log_hall := _spawn_blender_model("ext_logistics_hall", Vector3(-18.5, 0.0, 31.2), 0.0)
	_register_evening_windows(log_hall, "Log_WindowGlass")
	_add_label(Vector3(-18.5, 6.42, 24.60), "NORDKRAFT LOGISTIK", 42, 0.009, Color(0.96, 0.97, 0.99), 180.0)
	# Gelbe LKW-Spurmarkierungen vor den 3 Laderampen + angedockter 40t-Auflieger an Rampe 1!
	for lx in [-26.3, -21.1, -15.9]:
		_add_box(Vector3(float(lx) - 1.55, -0.028, 22.8), Vector3(0.12, 0.01, 4.4), stripe_y, false)
		_add_box(Vector3(float(lx) + 1.55, -0.028, 22.8), Vector3(0.12, 0.01, 4.4), stripe_y, false)
	# Abgesattelter 40t-Auflieger buendig an Rampe 1 angedockt (Nase bleibt sauber im Ladehof!)
	_spawn_blender_model("ext_dock_trailer", Vector3(-26.3, 0.0, 23.4), 90.0)
	_spawn_blender_model("ext_pallet_stack", Vector3(-10.5, 0.0, 23.6), 8.0)
	_spawn_blender_model("ext_pallet_stack", Vector3(-8.8, 0.0, 23.8), -5.0)
	_spawn_blender_model("ext_trash_bin", Vector3(-7.0, 0.0, 24.5), 180.0)
	# Gelber Gabelstapler pendelt lebendig auf dem Ladehof mit Blinklicht!
	_forklift_node = _spawn_blender_model("ext_forklift", Vector3(-18.0, 0.0, 22.2), 0.0)
	if _forklift_node != null:
		_forklift_beacon_mat = _clone_material_by_name(_forklift_node, "FL_BeaconMat")
		_forklift_audio = AudioStreamPlayer3D.new()
		_forklift_audio.max_distance = 34.0
		_forklift_audio.unit_size = 4.2
		_forklift_node.add_child(_forklift_audio)
	# Hof-Begrenzungszaun zwischen Nordkraft und Umspannwerk
	_build_blender_fence_line(Vector3(-4.8, 0.0, 21.0), Vector3(-4.8, 0.0, 38.5))

	# 2. RHEIN-TECH SYSTEMS: kompletter gestrichelter Firmenparkplatz + wehende Fahnenmasten!
	_add_box(Vector3(18.5, -0.10, 29.8), Vector3(24.0, 0.12, 17.8), asp_mat, false)
	var off_node := _spawn_blender_model("ext_office_tech", Vector3(18.5, 0.0, 31.2), 0.0)
	_register_evening_windows(off_node, "Off_WindowGlass")
	_add_label(Vector3(18.5, 7.62, 25.00), "RHEIN-TECH SYSTEMS", 40, 0.009, Color(0.95, 0.97, 1.0), 180.0)
	# Weiße Parkplatz-Linien + 4 parkende Blender-Autos!
	for px in [10.0, 13.4, 16.8, 20.2, 23.6, 27.0]:
		_add_box(Vector3(float(px), -0.028, 22.6), Vector3(0.10, 0.01, 3.8), stripe_w, false)
	_spawn_parked_vehicle("ext_car_sedan", Vector3(11.7, 0.0, 22.6), -90.0, Color(0.14, 0.24, 0.40))
	_spawn_parked_vehicle("ext_car_suv",   Vector3(15.1, 0.0, 22.6), -90.0, Color(0.76, 0.78, 0.80))
	_spawn_parked_vehicle("ext_car_sedan", Vector3(21.9, 0.0, 22.6), -90.0, Color(0.56, 0.12, 0.12))
	_spawn_parked_vehicle("ext_car_van",   Vector3(25.3, 0.0, 22.6), -90.0, Color(0.92, 0.93, 0.94))
	# 3 wehende Firmen-Fahnenmasten vor Rhein-Tech Systems!
	_spawn_flagpole(Vector3(8.4, 0.0, 23.2), 180.0, Color(0.10, 0.28, 0.56), Color(0.92, 0.68, 0.12))
	_spawn_flagpole(Vector3(8.4, 0.0, 25.4), 180.0, Color(0.14, 0.18, 0.24), Color(0.18, 0.72, 0.92))
	_spawn_flagpole(Vector3(28.8, 0.0, 23.2), 180.0, Color(0.10, 0.28, 0.56), Color(0.92, 0.68, 0.12))

	# 3. STÄDTISCHES 20-kV-UMSPANNWERK: eigenes Schotterbett, Sicherheitszaun & Hochspannungs-Trasse zum Horizont!
	_add_box(Vector3(1.5, -0.09, 29.0), Vector3(11.5, 0.12, 16.5), gravel_mat, false)
	_build_blender_fence_line(Vector3(-4.2, 0.0, 37.2), Vector3(6.8, 0.0, 37.2))
	_build_blender_fence_line(Vector3(6.8, 0.0, 21.0), Vector3(6.8, 0.0, 37.2))
	_spawn_blender_model("ext_substation_20kv", Vector3(1.5, 0.0, 25.4), 0.0)
	_add_label(Vector3(-0.15, 2.75, 23.62), "TRAFO 20 kV", 24, 0.0046, Color(0.96, 0.78, 0.20), 180.0)
	var hum_stream := SfxManager.get_loop_stream("substation_hum")
	if hum_stream != null:
		_substation_audio = AudioStreamPlayer3D.new()
		_substation_audio.stream = hum_stream
		_substation_audio.position = Vector3(3.2, 1.6, 25.4)
		_substation_audio.max_distance = 28.0
		_substation_audio.unit_size = 4.5
		_substation_audio.volume_db = -24.0
		add_child(_substation_audio)

	# 4 echte Hochspannungs-Gittermasten vom Umspannwerk nach Süden in den Horizont + durchhängende Leitungen!
	var pylon_positions: Array[Vector3] = [
		Vector3(1.5, 0.0, 32.5),
		Vector3(1.5, 0.0, 62.0),
		Vector3(1.5, 0.0, 92.0),
		Vector3(1.5, 0.0, 122.0),
	]
	for pp in pylon_positions:
		_spawn_blender_model("ext_power_pylon", pp, 0.0)
	# Durchhängende schwarze Hochspannungs-Leiterseile zwischen allen Masten!
	var wire_mat := _mat(Color(0.06, 0.065, 0.07), 0.75, 0.35)
	for pi in range(pylon_positions.size() - 1):
		var a: Vector3 = pylon_positions[pi]
		var b: Vector3 = pylon_positions[pi + 1]
		for arm_spec in [[13.35, 5.55], [17.05, 4.15]]:
			var ay: float = float(arm_spec[0])
			var ax: float = float(arm_spec[1])
			for side in [-1.0, 1.0]:
				_add_sagging_wire(
					Vector3(a.x + side * ax, ay, a.z),
					Vector3(b.x + side * ax, ay, b.z),
					1.35,
					wire_mat
				)
	# Zuleitung vom 1. Mast herunter auf die 3 Keramik-Isolatoren des 20-kV-Öltrafos!
	for side_x in [-0.62, 0.0, 0.62]:
		_add_sagging_wire(
			Vector3(1.5 + side_x * 6.5, 13.35, 32.5),
			Vector3(3.45 + side_x, 3.42, 25.05),
			0.65,
			wire_mat
		)

	# Bäume sauber an den Hof- & Straßenrändern (nicht mitten im Hof!)
	var south_trees: Array = [
		[Vector3(-33.5, 0.0, 22.0), false, 1.05, 24.0],
		[Vector3(-5.8,  0.0, 22.4), false, 0.92, 110.0],
		[Vector3(7.4,   0.0, 22.2), true,  0.92, 48.0],
		[Vector3(31.2,  0.0, 22.8), false, 1.08, 215.0],
		[Vector3(31.5,  0.0, 35.5), true,  1.12, 78.0],
	]
	for st in south_trees:
		spawn_tree(st[0] as Vector3, bool(st[1]), float(st[2]), float(st[3]), true)


# ---------------------------------------------------------------- Westen: Container-Hof, Doppelstabmattenzaun & Nachbarhalle

func _build_west_yard_and_containers() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	_add_box(Vector3(-23.0, -0.10, -2.0), Vector3(24.0, 0.12, 24.0), asp_mat, false)
	_build_blender_fence_line(Vector3(-10.8, 0.0, -9.5), Vector3(-10.8, 0.0, 10.2))

	_spawn_colored_container(Vector3(-17.8, 0.0, 4.2), 90.0, Color(0.14, 0.29, 0.48))
	_spawn_colored_container(Vector3(-20.8, 0.0, 4.2), 90.0, Color(0.56, 0.21, 0.14))
	_spawn_colored_container(Vector3(-19.3, 2.59, 4.2), 90.0, Color(0.32, 0.36, 0.40))
	_spawn_blender_model("ext_pallet_stack", Vector3(-14.6, 0.0, 5.2), 18.0)
	_spawn_blender_model("ext_pallet_stack", Vector3(-14.6, 0.0, 3.6), -6.0)
	_spawn_blender_model("ext_trash_bin", Vector3(-13.8, 0.0, 7.6), 90.0)
	_spawn_blender_model("ext_trash_bin", Vector3(-13.8, 0.0, 6.8), 95.0)

	var wh := _spawn_blender_model("ext_logistics_hall", Vector3(-28.5, 0.0, -8.0), 90.0, Vector3(0.85, 0.92, 0.85))
	_register_evening_windows(wh, "Log_WindowGlass")
	spawn_tree(Vector3(-13.2, 0.0, -10.0), false, 1.12, 35.0, true)
	spawn_tree(Vector3(-13.5, 0.0, -2.5), true, 1.08, 160.0, true)
	spawn_tree(Vector3(-13.2, 0.0, 8.2), false, 1.02, 275.0, true)


# ---------------------------------------------------------------- Osten: Zweites Umspannwerk, Solar-Carport & Zaun

func _build_east_substation_and_fence() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var metal := _mat(Color(0.34, 0.38, 0.42), 0.48, 0.65)
	var dark_panel := _mat(Color(0.08, 0.12, 0.22), 0.22, 0.55)

	_add_box(Vector3(36.0, -0.10, 2.0), Vector3(18.0, 0.12, 18.0), asp_mat, false)
	_build_blender_fence_line(Vector3(26.5, 0.0, -9.5), Vector3(26.5, 0.0, 10.2))

	_spawn_blender_model("ext_substation_20kv", Vector3(34.5, 0.0, -0.5), 90.0)
	for sx in [29.5, 35.5, 41.5]:
		_add_cyl(Vector3(float(sx), 1.4, 7.6), 0.09, 0.09, 2.8, metal)
	var roof := _add_box(Vector3(35.5, 2.88, 7.6), Vector3(14.0, 0.10, 4.4), dark_panel, false)
	roof.rotation_degrees.x = 8.0
	_spawn_parked_vehicle("ext_car_van", Vector3(33.0, 0.0, 7.6), -90.0, Color(0.92, 0.93, 0.94))
	_spawn_parked_vehicle("ext_car_suv", Vector3(38.2, 0.0, 7.6), -90.0, Color(0.18, 0.22, 0.28))

	spawn_tree(Vector3(29.2, 0.0, -10.5), true, 1.18, 52.0, true)
	spawn_tree(Vector3(29.0, 0.0, -4.0), false, 1.15, 195.0, true)
	spawn_tree(Vector3(28.8, 0.0, 4.2), false, 1.05, 88.0, true)


# ---------------------------------------------------------------- Norden: Schallschutzwand, Funkmast & Wald

func _build_north_hinterland_and_tower() -> void:
	var wall_mat := _mat(Color(0.38, 0.42, 0.36), 0.88, 0.05)
	var steel := _mat(Color(0.55, 0.58, 0.62), 0.42, 0.72)

	_add_box(Vector3(8.0, 1.5, -13.5), Vector3(58.0, 3.0, 0.45), wall_mat, false)
	_build_blender_fence_line(Vector3(-10.8, 0.0, -9.5), Vector3(26.5, 0.0, -9.5))

	var tx := 28.0
	var tz := -22.0
	_add_cyl(Vector3(tx, 14.0, tz), 0.22, 0.55, 28.0, steel)
	_add_cyl(Vector3(tx, 25.5, tz), 1.4, 1.4, 0.22, steel)
	for ai in range(3):
		var a := float(ai) * (TAU / 3.0)
		_add_box(Vector3(tx + cos(a) * 1.35, 26.2, tz + sin(a) * 1.35), Vector3(0.28, 1.65, 0.16), _mat(Color(0.86, 0.88, 0.90), 0.5, 0.1), false)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.15, 0.12)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.12, 0.10)
	bmat.emission_energy_multiplier = 3.5
	_aviation_beacon_mats.append(bmat)
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	b.mesh = sm
	b.material_override = bmat
	b.position = Vector3(tx, 28.3, tz)
	add_child(b)

	for i in range(11):
		var nx := -26.0 + float(i) * 6.8
		spawn_tree(Vector3(nx, 0.0, -18.5 - (float(i % 3) * 2.4)), i % 2 == 0, 1.18 + float(i % 3) * 0.12, float(i * 47), true)


# ---------------------------------------------------------------- Lebendiger Horizont: Windräder, Baukran & Heizkraftwerk mit Dampf!

func _build_living_horizon_landmarks() -> void:
	# 1. 5 drehende deutsche Windräder auf den fernen Hügelketten (Süd- & Nord-Horizont!)
	var turbine_specs: Array = [
		[Vector3(-68.0, 0.0, 102.0), 155.0, 1.15, 0.42],
		[Vector3(-22.0, 0.0, 114.0), 172.0, 1.20, 0.38],
		[Vector3(26.0,  0.0, 110.0), 188.0, 1.18, 0.45],
		[Vector3(78.0,  0.0, 100.0), 205.0, 1.12, 0.40],
		[Vector3(-34.0, 0.0, -86.0),  18.0, 1.15, 0.41],
	]
	for ts in turbine_specs:
		var wt := _spawn_blender_model("ext_wind_turbine", ts[0] as Vector3, float(ts[1]), Vector3.ONE * float(ts[2]))
		if wt != null:
			var rotor := wt.find_child("Rotor", true, false) as Node3D
			if rotor != null:
				rotor.rotation.z = randf_range(0.0, TAU)
				_turbine_rotors.append({"node": rotor, "speed": float(ts[3])})
			var bm := _clone_material_by_name(wt, "WT_BeaconMat")
			if bm != null:
				_aviation_beacon_mats.append(bm)

	# 2. Langsam schwenkender gelber Baukran im fernen Südwest-Gewerbegebiet (X = -54, Z = 56)
	var crane := _spawn_blender_model("ext_tower_crane", Vector3(-54.0, 0.0, 56.0), 25.0)
	if crane != null:
		_crane_jib = crane.find_child("Jib", true, false) as Node3D
		var cbm := _clone_material_by_name(crane, "Crane_BeaconMat")
		if cbm != null:
			_aviation_beacon_mats.append(cbm)

	# 3. Deutsches Heizkraftwerk im Südosten (X = 52, Z = 58) + aufsteigende weiße Dampfwolken aus beiden Schornsteinen!
	var chp := _spawn_blender_model("ext_chp_plant", Vector3(52.0, 0.0, 58.0), -18.0)
	_register_evening_windows(chp, "CHP_Glass")
	# Schornstein-Spitzen in Weltkoordinaten (lokal (-5.5, 25.5, 4.8) & (1.5, 22.0, 4.8) mit Yaw -18°)
	var chp_basis := Basis(Vector3.UP, deg_to_rad(-18.0))
	for local_top in [Vector3(-5.5, 25.8, 4.8), Vector3(1.5, 22.3, 4.8)]:
		var world_top := Vector3(52.0, 0.0, 58.0) + chp_basis * (local_top as Vector3)
		_spawn_steam_plume(world_top)


func _spawn_steam_plume(world_pos: Vector3) -> void:
	var p := RealisticVfx.create_chp_steam_plume(world_pos)
	add_child(p)
	_steam_emitters.append(p)


# ---------------------------------------------------------------- Erhöhte Fern-Autobahn am Horizont (2 MultiMeshes = 2 Draw Calls!)

func _build_distant_highway_stream() -> void:
	var conc_mat := _mat(Color(0.46, 0.48, 0.50), 0.90, 0.05)
	var asp_mat := _mat(Color(0.18, 0.19, 0.21), 0.92, 0.0)
	# Erhöhter Autobahn-Damm + Schallschutzwand bei Z = 82.0 (gut sichtbar über die Lücken hinweg!)
	_add_box(Vector3(4.0, 2.2, 82.0), Vector3(260.0, 4.4, 14.0), conc_mat, false)
	_add_box(Vector3(4.0, 4.45, 82.0), Vector3(260.0, 0.18, 12.6), asp_mat, false)
	_add_box(Vector3(4.0, 4.95, 75.6), Vector3(260.0, 0.85, 0.25), conc_mat, false) # Niedrige Beton-Leitwand vorne

	# 24 fließende Scheinwerfer- & Rücklicht-Paare in 2 Fahrtrichtungen (minimalste Last!)
	var count := 24
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.42, 0.28, 1.35)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.96, 0.84)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.95, 0.80)
	head_mat.emission_energy_multiplier = 3.2
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mesh.material = head_mat

	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.38, 0.26, 1.35)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(1.0, 0.16, 0.10)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.14, 0.08)
	tail_mat.emission_energy_multiplier = 3.6
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail_mesh.material = tail_mat

	_hw_head_mm = MultiMesh.new()
	_hw_head_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hw_head_mm.mesh = head_mesh
	_hw_head_mm.instance_count = count
	var h_inst := MultiMeshInstance3D.new()
	h_inst.multimesh = _hw_head_mm
	h_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(h_inst)

	_hw_tail_mm = MultiMesh.new()
	_hw_tail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hw_tail_mm.mesh = tail_mesh
	_hw_tail_mm.instance_count = count
	var t_inst := MultiMeshInstance3D.new()
	t_inst.multimesh = _hw_tail_mm
	t_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(t_inst)

	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	for i in range(count):
		var dir := 1.0 if i < count / 2 else -1.0
		var lane_z := (79.2 if (i % 2 == 0) else 77.6) if dir < 0.0 else (84.2 if (i % 2 == 0) else 85.8)
		_hw_cars.append({
			"x": rng.randf_range(-124.0, 128.0),
			"z": lane_z,
			"dir": dir,
			"speed": rng.randf_range(24.0, 34.0),
		})


# ---------------------------------------------------------------- Zweiter Hintergrund-Verkehr auf der Ringstraße (Z = 42.5)

func _build_background_ring_traffic() -> void:
	var specs: Array = [
		{"model": "ext_car_sedan", "z": 40.9, "dir": -1.0, "speed": 11.5, "x": 38.0, "color": Color(0.74, 0.76, 0.78)},
		{"model": "ext_car_van",   "z": 44.1, "dir":  1.0, "speed":  9.8, "x": -34.0, "color": Color(0.92, 0.93, 0.94)},
		{"model": "ext_car_suv",   "z": 40.9, "dir": -1.0, "speed": 10.6, "x": -48.0, "color": Color(0.16, 0.24, 0.34)},
	]
	for sp in specs:
		var r := Node3D.new()
		r.position = Vector3(float(sp["x"]), 0.0, float(sp["z"]))
		r.rotation_degrees.y = 0.0 if float(sp["dir"]) > 0.0 else 180.0
		add_child(r)
		var m := ModelLoader.instantiate_custom_model(str(sp["model"]))
		if m != null:
			r.add_child(m)
			_override_material_color(m, "Car_PaintMat", sp["color"] as Color)
		_bg_traffic_cars.append({"node": r, "dir": float(sp["dir"]), "speed": float(sp["speed"])})


func _update_background_ring_traffic(delta: float) -> void:
	for car in _bg_traffic_cars:
		var n: Node3D = car["node"]
		var d: float = float(car["dir"])
		n.position.x += d * float(car["speed"]) * delta
		if d > 0.0 and n.position.x > 82.0:
			n.position.x = -78.0
		elif d < 0.0 and n.position.x < -78.0:
			n.position.x = 82.0


# ---------------------------------------------------------------- Himmel: Kreisender Vogelschwarm + Flugzeug mit Kondensstreifen!

func _build_sky_life() -> void:
	# 2. Linienflugzeug in großer Höhe + weißer Kondensstreifen
	_jet_node = Node3D.new()
	_jet_node.visible = false
	add_child(_jet_node)
	var jmat := StandardMaterial3D.new()
	jmat.albedo_color = Color(0.96, 0.97, 0.99)
	jmat.emission_enabled = true
	jmat.emission = Color(0.95, 0.96, 1.0)
	jmat.emission_energy_multiplier = 0.8
	var fuse := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.2, 0.45, 0.45)
	fuse.mesh = fm
	fuse.material_override = jmat
	_jet_node.add_child(fuse)
	var wing := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.8, 0.12, 3.0)
	wing.mesh = wm
	wing.material_override = jmat
	_jet_node.add_child(wing)
	# Langer, sanfter weißer Kondensstreifen hinter dem Jet
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.95, 0.97, 1.0, 0.28)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side_z in [-0.42, 0.42]:
		var trail := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(44.0, 0.22, 0.32)
		trail.mesh = tm
		trail.material_override = cmat
		trail.position = Vector3(-23.5, 0.0, float(side_z))
		_jet_node.add_child(trail)


func _update_living_horizon(delta: float) -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var wind_mult := 2.4 if w == "storm" else (1.55 if w == "rain" else 1.0)

	# 1. Windräder drehen sich sanft mit dem Wind!
	for tr in _turbine_rotors:
		var r: Node3D = tr["node"]
		if r != null:
			r.rotation.z -= float(tr["speed"]) * wind_mult * delta

	# 2. Baukran schwenkt langsam & glaubwürdig hin und her
	if _crane_jib != null:
		_crane_jib.rotation_degrees.y = sin(_anim_t * 0.085) * 42.0

	# 3. Gabelstapler pendelt lebendig auf dem Ladehof von Nordkraft Logistik!
	if _forklift_node != null:
		_forklift_phase += delta * 0.24
		var cyc := fmod(_forklift_phase, 4.0)
		var fx := -18.0
		var yaw := 0.0
		var reversing := false
		if cyc < 1.4:
			var u := smoothstep(0.0, 1.0, cyc / 1.4)
			fx = lerpf(-22.5, -10.5, u)
			yaw = 0.0
		elif cyc < 2.0:
			fx = -10.5
			yaw = 0.0 # Kurz Palette abstellen/warten
		elif cyc < 3.4:
			var u := smoothstep(0.0, 1.0, (cyc - 2.0) / 1.4)
			fx = lerpf(-10.5, -22.5, u)
			yaw = 0.0 # Rückwärts zurückfahren!
			reversing = true
		else:
			fx = -22.5
			yaw = 0.0
		_forklift_node.position.x = fx
		_forklift_node.rotation_degrees.y = yaw
		if _forklift_beacon_mat != null:
			var blink := 1.0 if sin(_anim_t * 10.0) > 0.0 else 0.15
			_forklift_beacon_mat.emission_energy_multiplier = 4.5 * blink
		# Leises, gedämpftes Hof-Rückfahrpiepen drüben bei Nordkraft Logistik!
		if reversing and _forklift_audio != null and GameState.is_active:
			_forklift_beep_accum += delta
			if _forklift_beep_accum >= 0.85:
				_forklift_beep_accum = 0.0
				var yb := SfxManager.get_sound_stream("distant_yard_beep")
				var g_gain := SettingsManager.get_effective_fan_gain()
				var trans := SfxManager.get_outdoor_transmission()
				if yb != null and g_gain > 0.005 and trans > 0.35:
					_forklift_audio.stream = yb
					_forklift_audio.volume_db = linear_to_db(g_gain * trans) - 13.0
					_forklift_audio.play()

	# 4. Autobahn-Lichterströme auf dem fernen Viadukt (Z = 82)
	if _hw_head_mm != null and _hw_tail_mm != null:
		for i in range(_hw_cars.size()):
			var hc: Dictionary = _hw_cars[i]
			var d: float = float(hc["dir"])
			var x: float = float(hc["x"]) + d * float(hc["speed"]) * delta
			if d > 0.0 and x > 130.0:
				x = -126.0
			elif d < 0.0 and x < -126.0:
				x = 130.0
			hc["x"] = x
			var z: float = float(hc["z"])
			_hw_head_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x + d * 1.9, 5.10, z)))
			_hw_tail_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x - d * 1.9, 5.10, z)))


func _update_sky_life(delta: float) -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	# 2. Gelegentlicher Linienflugzeug-Überflug mit Kondensstreifen & leisem Jet-Rauschen!
	if _jet_node != null and GameState.is_active:
		if not _jet_active:
			_jet_timer -= delta
			if _jet_timer <= 0.0 and w != "storm":
				_jet_active = true
				_jet_t = 0.0
				_jet_node.visible = true
				var trans := SfxManager.get_outdoor_transmission()
				if trans > 0.35:
					SfxManager.play("distant_jet", -16.0 + linear_to_db(trans), randf_range(0.94, 1.06))
		else:
			_jet_t += delta / 22.0
			if _jet_t >= 1.0:
				_jet_active = false
				_jet_node.visible = false
				_jet_timer = randf_range(65.0, 110.0)
			else:
				var p := _jet_start.lerp(_jet_end, _jet_t)
				_jet_node.position = p
				var dir_v := (_jet_end - _jet_start).normalized()
				_jet_node.rotation.y = atan2(-dir_v.z, dir_v.x)


# ---------------------------------------------------------------- Lebendiger Hauptstraßen-Verkehr (4 Blender-Fahrzeuge + 3D-Sound!)

func _build_ambient_traffic() -> void:
	var specs: Array = [
		{"model": "ext_car_sedan", "lane_z": 12.75, "dir": -1.0, "speed": 10.8, "x": -18.0, "color": Color(0.14, 0.28, 0.48), "wheel_r": 0.33, "truck": false},
		{"model": "ext_car_suv",   "lane_z": 12.75, "dir": -1.0, "speed": 10.2, "x":  44.0, "color": Color(0.76, 0.78, 0.82), "wheel_r": 0.39, "truck": false},
		{"model": "ext_car_van",   "lane_z": 12.75, "dir": -1.0, "speed":  9.2, "x":  84.0, "color": Color(0.92, 0.93, 0.95), "wheel_r": 0.37, "truck": false},
		{"model": "ext_car_truck", "lane_z": 16.35, "dir":  1.0, "speed":  8.2, "x": -62.0, "color": Color(0.12, 0.22, 0.38), "wheel_r": 0.51, "truck": true},
		{"model": "ext_car_sedan", "lane_z": 16.35, "dir":  1.0, "speed": 11.4, "x":   6.0, "color": Color(0.62, 0.13, 0.12), "wheel_r": 0.33, "truck": false},
		{"model": "ext_car_suv",   "lane_z": 16.35, "dir":  1.0, "speed": 10.4, "x":  66.0, "color": Color(0.16, 0.20, 0.24), "wheel_r": 0.39, "truck": false},
	]
	for sp in specs:
		var root := Node3D.new()
		root.position = Vector3(float(sp["x"]), 0.0, float(sp["lane_z"]))
		root.rotation_degrees.y = 0.0 if float(sp["dir"]) > 0.0 else 180.0
		add_child(root)

		var model := ModelLoader.instantiate_custom_model(str(sp["model"]))
		var wheels: Array[Node3D] = []
		var head_mat: StandardMaterial3D = null
		var tail_mat: StandardMaterial3D = null
		var brake_mat: StandardMaterial3D = null
		if model != null:
			root.add_child(model)
			_override_material_color(model, "Car_PaintMat", sp["color"] as Color)
			head_mat = _clone_material_by_name(model, "Car_HeadlightMat")
			tail_mat = _clone_material_by_name(model, "Car_TaillightMat")
			brake_mat = _clone_material_by_name(model, "Car_BrakeMat")
			_collect_wheels(model, wheels)

		var is_truck: bool = bool(sp["truck"])
		var eng_audio := AudioStreamPlayer3D.new()
		eng_audio.stream = SfxManager.get_loop_stream("car_pass_truck" if is_truck else "car_pass_sedan")
		eng_audio.max_distance = 54.0 if is_truck else 42.0
		eng_audio.unit_size = 7.5 if is_truck else 5.2
		eng_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		eng_audio.volume_db = -80.0
		root.add_child(eng_audio)

		var wet_audio := AudioStreamPlayer3D.new()
		wet_audio.stream = SfxManager.get_loop_stream("tire_wet")
		wet_audio.max_distance = 36.0
		wet_audio.unit_size = 4.6
		wet_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		wet_audio.volume_db = -80.0
		root.add_child(wet_audio)

		var sfx_audio := AudioStreamPlayer3D.new()
		sfx_audio.max_distance = 38.0
		sfx_audio.unit_size = 5.5
		root.add_child(sfx_audio)

		_traffic_cars.append({
			"node": root,
			"dir": float(sp["dir"]),
			"base_speed": float(sp["speed"]),
			"cur_speed": float(sp["speed"]),
			"lane_z": float(sp["lane_z"]),
			"wheel_r": float(sp["wheel_r"]),
			"truck": is_truck,
			"wheels": wheels,
			"head_mat": head_mat,
			"tail_mat": tail_mat,
			"brake_mat": brake_mat,
			"eng_audio": eng_audio,
			"wet_audio": wet_audio,
			"sfx_audio": sfx_audio,
			"was_braking": false,
			"pitch_seed": randf_range(0.92, 1.08),
		})


func _update_traffic(delta: float) -> void:
	# Lieferfahrzeug: beim Rangieren hält alles an, sonst nur die Spur, in die es hineinragt.
	var van_busy := false
	var van_far := false
	var van_x := -999.0
	if GameState.is_active and GameState.van_phase != "idle" and GameState.van_site == "garage":
		var vp := DeliveryPlan.vehicle_pose("garage", GameState.van_delivery_tier, GameState.van_phase, GameState.van_phase_time)
		var vpos: Vector3 = vp["pos"]
		if vpos.z > 16.0:
			van_x = vpos.x
		van_busy = absf(vpos.x) < 12.0 and not (GameState.van_phase == "arriving" and GameState.van_phase_time < 2.5)
		van_far = van_busy and (GameState.van_phase != "unloading" or GameState.van_delivery_tier == 3)

	var tod := GameState.time_of_day if GameState.is_active else 0.36
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var raining := (w == "rain" or w == "storm")
	var lights_on := (tod < 0.25 or tod > 0.72 or raining)
	var fan_gain := SettingsManager.get_effective_fan_gain()
	var trans := SfxManager.get_outdoor_transmission()
	var audio_active := GameState.is_active and fan_gain > 0.005

	var walkers: Array[Vector3] = []
	for p_n in get_tree().get_nodes_in_group("player_body"):
		var pp := (p_n as Node3D).global_position
		if pp.z > 10.3 and pp.z < 19.0 and pp.y < 2.0:
			walkers.append(pp)
	for idx in range(_traffic_cars.size()):
		var car: Dictionary = _traffic_cars[idx]
		var n: Node3D = car["node"]
		var d: float = float(car["dir"])
		var base_spd: float = float(car["base_speed"])
		var cur_spd: float = float(car["cur_speed"])
		var target_spd := base_spd
		var is_braking := false

		var stop_here := van_busy if float(car["lane_z"]) < 14.5 else van_far
		if stop_here:
			if d < 0.0 and n.position.x > 9.5 and n.position.x < 24.0:
				target_spd = 0.0
				is_braking = true
			elif d > 0.0 and n.position.x < -6.5 and n.position.x > -24.0:
				target_spd = 0.0
				is_braking = true
		if van_x > -900.0 and d > 0.0 and float(car["lane_z"]) > 14.5:
			var vgap := van_x - n.position.x
			if vgap > 0.0 and vgap < 15.0:
				target_spd = 0.0
				is_braking = true
			elif vgap <= 0.0 and vgap > -26.0:
				target_spd = base_spd * 1.7

		# Wer auf der Fahrbahn steht, wird nicht überfahren.
		for pl in walkers:
			var gapp := (pl.x - n.position.x) * d
			if absf(pl.z - float(car["lane_z"])) < 1.7 and gapp > -0.5 and gapp < 11.0:
				target_spd = 0.0
				is_braking = true
				if gapp < 5.0 and float(car.get("honk", 0.0)) <= 0.0 and audio_active:
					car["honk"] = 6.0
					SfxManager.play("van_horn", -10.0, 1.1 if not bool(car["truck"]) else 0.8)
		car["honk"] = maxf(0.0, float(car.get("honk", 0.0)) - delta)

		for j in range(_traffic_cars.size()):
			if j == idx:
				continue
			var other: Dictionary = _traffic_cars[j]
			if absf(float(other["lane_z"]) - float(car["lane_z"])) > 1.2:
				continue
			var onode: Node3D = other["node"]
			var gap := (onode.position.x - n.position.x) * d
			var min_gap := 18.0 if (bool(car["truck"]) or bool(other["truck"])) else 11.0
			if gap > 0.0 and gap < min_gap:
				target_spd = minf(target_spd, float(other["cur_speed"]) * 0.75)
				if gap < min_gap * 0.78:
					target_spd = 0.0
					is_braking = true

		var accel := 9.0 if target_spd < cur_spd else 4.2
		cur_spd = move_toward(cur_spd, target_spd, delta * accel)
		car["cur_speed"] = cur_spd

		var was_braking := bool(car["was_braking"])
		if is_braking and not was_braking and bool(car["truck"]) and audio_active:
			var sa: AudioStreamPlayer3D = car["sfx_audio"]
			var ab := SfxManager.get_sound_stream("air_brake")
			if sa != null and ab != null and absf(n.position.x) < 35.0:
				sa.stream = ab
				sa.volume_db = linear_to_db(fan_gain * trans) - 6.0
				sa.pitch_scale = randf_range(0.92, 1.06)
				sa.play()
		car["was_braking"] = is_braking

		n.position.x += d * cur_spd * delta
		if d > 0.0 and n.position.x > TRAFFIC_X_MAX:
			n.position.x = TRAFFIC_X_MIN
		elif d < 0.0 and n.position.x < TRAFFIC_X_MIN:
			n.position.x = TRAFFIC_X_MAX

		var wr: float = maxf(0.20, float(car["wheel_r"]))
		var wheel_step := (cur_spd / wr) * delta
		var wheels: Array = car["wheels"]
		for wh in wheels:
			if wh is Node3D:
				(wh as Node3D).rotation.z -= wheel_step

		var hm: StandardMaterial3D = car["head_mat"]
		if hm != null:
			hm.emission_energy_multiplier = 4.6 if lights_on else 0.25
		var tm: StandardMaterial3D = car["tail_mat"]
		if tm != null:
			tm.emission_energy_multiplier = 2.4 if lights_on else 0.15
		var bm: StandardMaterial3D = car["brake_mat"]
		if bm != null:
			bm.emission_energy_multiplier = 5.2 if is_braking else (1.4 if lights_on else 0.12)

		var ea: AudioStreamPlayer3D = car["eng_audio"]
		if ea != null and ea.stream != null:
			var audible := audio_active and absf(n.position.x) < 52.0
			if not audible:
				if ea.playing:
					ea.stop()
			else:
				if not ea.playing:
					ea.play(randf_range(0.0, 1.2))
				var spd_ratio := clampf(cur_spd / maxf(base_spd, 1.0), 0.0, 1.2)
				var base_db := (-5.5 if bool(car["truck"]) else -9.0) + lerpf(-9.0, 0.0, spd_ratio)
				ea.volume_db = linear_to_db(fan_gain * trans) + base_db
				ea.pitch_scale = float(car["pitch_seed"]) * lerpf(0.72, 1.12, spd_ratio)

		var wa: AudioStreamPlayer3D = car["wet_audio"]
		if wa != null and wa.stream != null:
			var wet_on := audio_active and raining and cur_spd > 1.8 and absf(n.position.x) < 38.0
			if not wet_on:
				if wa.playing:
					wa.stop()
			else:
				if not wa.playing:
					wa.play(randf_range(0.0, 1.2))
				var spd_r := clampf(cur_spd / 10.0, 0.15, 1.2)
				wa.volume_db = linear_to_db(fan_gain * trans * spd_r) - 10.5
				wa.pitch_scale = lerpf(0.86, 1.18, spd_r)


# ---------------------------------------------------------------- 3D-Regen, Gewitter-Blitze & Nacht-Beleuchtung

func _build_weather_vfx() -> void:
	var drop_count := 380
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dm := BoxMesh.new()
	dm.size = Vector3(0.014, 0.56, 0.014)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.72, 0.84, 0.96, 0.36)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = dmat
	mm.mesh = dm
	_drop_mesh = dm
	mm.instance_count = drop_count

	_rain_drops.clear()
	_rain_speeds.resize(drop_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in range(drop_count):
		_rain_drops.append(Vector3(rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 12.0), rng.randf_range(-18.0, 18.0)))
		_rain_speeds[i] = rng.randf_range(13.0, 19.0)

	_rain_mm_inst = MultiMeshInstance3D.new()
	_rain_mm_inst.multimesh = mm
	_rain_mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mm_inst.visible = false
	add_child(_rain_mm_inst)

	_lightning_light = DirectionalLight3D.new()
	_lightning_light.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	_lightning_light.light_color = Color(0.82, 0.90, 1.0)
	_lightning_light.light_energy = 0.0
	_lightning_light.shadow_enabled = false
	add_child(_lightning_light)


func _flake_mesh() -> Mesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.055, 0.055)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g
	m.albedo_texture = gt
	qm.material = m
	return qm


func _update_night_lights() -> void:
	var tod := GameState.time_of_day if GameState.is_active else 0.36
	var is_night := (tod < 0.24 or tod > 0.74)
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var lamps_on := is_night or w == "storm"
	var lamp_e := 4.0 if lamps_on else 0.15
	for lm in _street_lamp_mats:
		lm.emission_energy_multiplier = lamp_e
	var spot_e := 3.4 if lamps_on else 0.0
	for sp in _street_spot_lights:
		sp.light_energy = spot_e
	# Warme leuchtende Büro- & Wohnfenster in der Dämmerung / Nacht!
	for wi in range(_evening_window_mats.size()):
		var wm := _evening_window_mats[wi]
		wm.emission_enabled = true
		wm.emission = Color(1.0, 0.82, 0.48)
		wm.emission_energy_multiplier = (2.1 + 0.4 * sin(_anim_t * 0.25 + float(wi))) if is_night else 0.0
	# Synchronisierte rote Flugsicherungs-Blinklichter an Windrädern, Baukran & Funkmast!
	var pulse := 0.2 + 5.2 * pow(0.5 + 0.5 * sin(_anim_t * 3.0), 3.0)
	for abm in _aviation_beacon_mats:
		abm.emission_energy_multiplier = pulse


func _update_substation_audio() -> void:
	if _substation_audio == null:
		return
	var gain := SettingsManager.get_effective_fan_gain()
	var active := GameState.is_active and gain > 0.005
	if not active:
		if _substation_audio.playing:
			_substation_audio.stop()
		return
	if not _substation_audio.playing:
		_substation_audio.play()
	var trans := SfxManager.get_outdoor_transmission()
	var tod := GameState.time_of_day
	var night_boost := 3.5 if (tod < 0.24 or tod > 0.74) else 0.0
	_substation_audio.volume_db = linear_to_db(gain * trans) - 18.0 + night_boost


func _update_weather(delta: float) -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var raining := (w == "rain" or w == "storm")
	var snowing: bool = raining and OutdoorManager.is_snowing()

	if _rain_mm_inst != null:
		_rain_mm_inst.visible = raining
		if snowing != _snow_mode:
			_snow_mode = snowing
			_rain_mm_inst.multimesh.mesh = _flake_mesh() if snowing else _drop_mesh
		if raining:
			var center := Vector3(0.0, 0.0, 8.0)
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				center = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
			var mm := _rain_mm_inst.multimesh
			var wind_x := -2.6 if w == "storm" else -0.8
			var tilt := Basis(Vector3.FORWARD, -0.18 if w == "storm" else -0.05)
			for i in range(_rain_drops.size()):
				var p := _rain_drops[i]
				p.y -= _rain_speeds[i] * delta * (0.10 if snowing else 1.0)
				p.x += wind_x * delta
				if snowing:
					p.x += sin(_anim_t * 1.3 + i) * delta * 0.5
					p.z += cos(_anim_t * 1.1 + i * 1.7) * delta * 0.5
				if p.y < 0.0:
					p.y += 12.0
				if p.x < -18.0:
					p.x += 36.0
				_rain_drops[i] = p
				var wp := Vector3(center.x + p.x, p.y, center.z + p.z)
				var inside_hall := (wp.x > -5.9 and wp.x < 21.9 and wp.z > -4.9 and wp.z < 4.9 and wp.y < 4.35)
				if inside_hall:
					mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), wp))
				else:
					mm.set_instance_transform(i, Transform3D(tilt, wp))

	if _lightning_light != null:
		if w == "storm" and GameState.is_active:
			_lightning_cooldown -= delta
			if _lightning_cooldown <= 0.0:
				_lightning_cooldown = randf_range(7.0, 16.0)
				_lightning_flash = 1.0
				SfxManager.play("thunder", -6.5, randf_range(0.86, 1.12))
		if _lightning_flash > 0.001:
			_lightning_flash = maxf(0.0, _lightning_flash - delta * 3.8)
			_lightning_light.light_energy = _lightning_flash * 4.2
		else:
			_lightning_light.light_energy = 0.0


# ---------------------------------------------------------------- Oeffentliche & interne Hilfsfunktionen

func spawn_tree(pos: Vector3, is_pine: bool, scale_val: float = 1.0, yaw_deg: float = 0.0, with_wind: bool = true) -> Node3D:
	var node := Nature.tree(Nature.species_for(pos, is_pine), pos, scale_val, yaw_deg, with_wind, with_wind)
	add_child(node)
	return node


func _register_evening_windows(node: Node, mat_name: String) -> void:
	if node == null:
		return
	var wm := _clone_material_by_name(node, mat_name)
	if wm != null:
		_evening_window_mats.append(wm)


func _add_sagging_wire(a: Vector3, b: Vector3, sag: float, mat: Material) -> void:
	var segs := 6
	var prev := a
	for i in range(1, segs + 1):
		var u := float(i) / float(segs)
		var p := a.lerp(b, u)
		p.y -= 4.0 * sag * u * (1.0 - u)
		var seg := p - prev
		var ln := seg.length()
		if ln > 0.05:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.032
			cm.bottom_radius = 0.032
			cm.height = ln
			cm.radial_segments = 5
			mi.mesh = cm
			mi.material_override = mat
			var dir_v := seg / ln
			var q := Quaternion(Vector3.UP, dir_v) if dir_v.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
			mi.transform = Transform3D(Basis(q), (prev + p) * 0.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		prev = p


func _spawn_blender_model(model_id: String, pos: Vector3, yaw_deg: float = 0.0, scale_v: Vector3 = Vector3.ONE) -> Node3D:
	var inst := ModelLoader.instantiate_custom_model(model_id)
	if inst == null:
		return null
	inst.position = pos
	inst.rotation_degrees.y = yaw_deg
	inst.scale = scale_v
	add_child(inst)
	return inst


func _spawn_colored_container(pos: Vector3, yaw_deg: float, col: Color) -> void:
	var c := _spawn_blender_model("ext_shipping_container", pos, yaw_deg)
	if c != null:
		_override_material_color(c, "Container_PaintMat", col)


func _spawn_parked_vehicle(model_id: String, pos: Vector3, yaw_deg: float, paint_col: Color) -> void:
	var v := _spawn_blender_model(model_id, pos, yaw_deg)
	if v != null:
		_override_material_color(v, "Car_PaintMat", paint_col)
		var hm := _clone_material_by_name(v, "Car_HeadlightMat")
		if hm != null:
			hm.emission_energy_multiplier = 0.05
		var tm := _clone_material_by_name(v, "Car_TaillightMat")
		if tm != null:
			tm.emission_energy_multiplier = 0.05
		var bm := _clone_material_by_name(v, "Car_BrakeMat")
		if bm != null:
			bm.emission_energy_multiplier = 0.05


func _build_blender_fence_line(a: Vector3, b: Vector3) -> void:
	var diff := b - a
	var length := diff.length()
	if length < 0.5:
		return
	var seg_w := 2.50
	var count := maxi(1, int(roundf(length / seg_w)))
	var step := diff / float(count)
	var yaw := rad_to_deg(atan2(-diff.z, diff.x))
	var scale_x := (length / float(count)) / seg_w
	for i in range(count):
		var mid := a + step * (float(i) + 0.5)
		_spawn_blender_model("ext_fence_panel", mid, yaw, Vector3(scale_x, 1.0, 1.0))


func _override_material_color(node: Node, mat_name: String, col: Color) -> void:
	var m := _clone_material_by_name(node, mat_name)
	if m != null:
		m.albedo_color = col


func _clone_material_by_name(node: Node, mat_name: String) -> StandardMaterial3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for si in range(mi.mesh.get_surface_count()):
				var cur := mi.get_surface_override_material(si)
				if cur == null:
					cur = mi.mesh.surface_get_material(si)
				if cur is StandardMaterial3D and cur.resource_name == mat_name:
					var dup := (cur as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(si, dup)
					return dup
	for ch in node.get_children():
		var found := _clone_material_by_name(ch, mat_name)
		if found != null:
			return found
	return null


func _collect_wheels(node: Node, out_wheels: Array[Node3D]) -> void:
	if node is Node3D and node.name.begins_with("Wheel_"):
		out_wheels.append(node as Node3D)
	for ch in node.get_children():
		_collect_wheels(ch, out_wheels)


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _add_box(pos: Vector3, sz: Vector3, mat: Material, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add_cyl(pos: Vector3, top_r: float, bot_r: float, h: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
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
	add_child(mi)
	return mi


func _add_label(pos: Vector3, txt: String, fsize: int, psize: float, col: Color, yaw_deg: float = 0.0) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = fsize
	lbl.pixel_size = psize
	lbl.outline_size = 0
	lbl.position = pos
	lbl.rotation_degrees.y = yaw_deg
	lbl.modulate = col
	add_child(lbl)
