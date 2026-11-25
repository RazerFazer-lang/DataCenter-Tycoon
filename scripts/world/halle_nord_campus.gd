class_name HalleNordCampus
extends Node3D
## Außenwelt für den Großstandort 'Halle Nord' — Tier-4 Enterprise Rechenzentrums-Campus:
## - 360°-Landschaft mit variiertem Wiesen-Shader, bewaldeter Hügelkette, 4 drehenden Windrädern
##   und 3 Hochspannungsmasten + durchhängenden Leitungen bis zum eigenen 20-kV-Umspannwerk.
## - Komplette 'Rechenzentrums-Allee 1' mit Querstraßen, Gehwegen, Bordsteinen, Laternen,
##   Hydranten, Gullys & fließendem KI-Verkehr.
## - Vollständig eingezäuntes Hochsicherheits-Gelände mit Pförtnerhaus, Schranke & Campus-Pylon.
## - Technik-Hof West: 2-MVA Notstrom-Dieselgenerator mit Kabelbrücke, 20-kV-Umspannwerk & Container.
## - Empfang & Parkplatz Ost: 3 wehende Firmen-Fahnenmasten, Solar-Carport mit PV-Modulen,
##   gestrichelte Parkbuchten mit Flottenfahrzeugen sowie moderne Nachbar-Campusgebäude gegenüber.

const ROAD_Z := 22.0
const CAMPUS_TRAFFIC_MIN := -78.0
const CAMPUS_TRAFFIC_MAX := 82.0

var _wind_shader: Shader
var _flag_shader: Shader
var _wind_materials: Array[ShaderMaterial] = []
var _flag_materials: Array[ShaderMaterial] = []
var _street_lamp_mats: Array[StandardMaterial3D] = []
var _street_spot_lights: Array[SpotLight3D] = []
var _evening_window_mats: Array[StandardMaterial3D] = []
var _aviation_beacon_mats: Array[StandardMaterial3D] = []
var _turbine_rotors: Array[Dictionary] = []
var _traffic_cars: Array[Dictionary] = []
var _pylon_sign_lbl: Label3D
var _diesel_audio: AudioStreamPlayer3D
var _anim_t: float = 0.0
var _upg_security_node: Node3D
var _upg_diesel_node: Node3D
var _upg_pv_node: Node3D


func _ready() -> void:
	_init_shaders()
	_build_terrain_and_horizon()
	_build_roads_and_yard()
	_build_perimeter_fence_and_gatehouse()
	_build_west_tech_yard()
	_build_east_parking_and_solar_carport()
	_build_south_campus_neighbors()
	_build_living_horizon_and_powerlines()
	_build_campus_traffic()
	GameState.building_upgrades_changed.connect(sync_building_upgrades)
	sync_building_upgrades()


func sync_building_upgrades() -> void:
	if _upg_security_node != null:
		_upg_security_node.visible = GameState.has_building_upgrade("upg_security_gate")
	if _upg_diesel_node != null:
		_upg_diesel_node.visible = GameState.has_building_upgrade("upg_diesel_gen")
	if _upg_pv_node != null:
		_upg_pv_node.visible = GameState.has_building_upgrade("upg_pv_solar")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_anim_t += delta
	_update_night_lights()
	_update_wind_and_flags()
	_update_turbines(delta)
	_update_traffic(delta)
	_update_diesel_audio()


func update_company_name(cname: String) -> void:
	if _pylon_sign_lbl != null:
		_pylon_sign_lbl.text = "%s\nTIER-4 CAMPUS\nHALLE NORD" % cname.to_upper()


# ---------------------------------------------------------------- Shader (Wind, Laub & Fahnen)

func _init_shaders() -> void:
	_wind_shader = Shader.new()
	_wind_shader.code = """
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo_color : source_color = vec4(0.20, 0.40, 0.16, 1.0);
uniform float roughness_val = 0.78;
uniform float wind_strength = 0.075;
uniform float wind_speed = 1.55;
uniform float height_start = 0.15;

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
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h_factor = clamp((VERTEX.y - height_start) * 0.28, 0.0, 1.8);
	float phase = TIME * wind_speed + wpos.x * 0.35 + wpos.z * 0.28;
	VERTEX.x += (sin(phase) * 0.65 + sin(phase * 2.13 + wpos.y * 0.8) * 0.35) * wind_strength * h_factor;
	VERTEX.z += cos(phase * 0.87 + wpos.x * 0.22) * 0.55 * wind_strength * h_factor;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float leaf_fine = vnoise3(v_wpos * 14.5);
	float leaf_mid = vnoise3(v_wpos * 4.8);
	float dapple = mix(0.44, 1.12, leaf_fine * 0.65 + leaf_mid * 0.35);
	float sun_tip = clamp(0.76 + v_lpos.y * 0.048, 0.68, 1.08);
	vec3 warm_shift = mix(vec3(0.76, 0.90, 0.80), vec3(1.02, 1.00, 0.78), leaf_fine);
	ALBEDO = albedo_color.rgb * 0.78 * dapple * sun_tip * warm_shift;
	ROUGHNESS = clamp(roughness_val + (0.5 - leaf_fine) * 0.16, 0.58, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
"""

	_flag_shader = Shader.new()
	_flag_shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 flag_color : source_color = vec4(0.08, 0.24, 0.48, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.14, 0.70, 0.96, 1.0);
uniform float wind_amp = 0.095;
uniform float wind_speed = 4.3;

varying float v_u;
varying float v_v;

void vertex() {
	v_u = clamp((VERTEX.x - 0.08) / 0.98, 0.0, 1.0);
	v_v = clamp((VERTEX.y - 4.55) / 2.45, 0.0, 1.0);
	float loose = (1.0 - v_v * 0.65) * (0.25 + v_u * 0.75);
	VERTEX.z += sin(TIME * wind_speed - v_v * 4.8 - v_u * 3.5) * wind_amp * loose;
	VERTEX.x += cos(TIME * wind_speed * 0.85 - v_v * 3.0) * wind_amp * 0.35 * loose;
}

void fragment() {
	float band = step(0.16, v_u) * (1.0 - step(0.32, v_u));
	ALBEDO = mix(flag_color.rgb, stripe_color.rgb, band);
	ROUGHNESS = 0.76;
	METALLIC = 0.0;
}
"""


func _make_meadow_material() -> Material:
	var grass_mat := MatLib.get_mat("grass")
	var sh := Shader.new()
	sh.code = """
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D grass_norm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D var_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float tex_scale = 0.42;
uniform float normal_strength = 0.55;
uniform vec3 tint_lush : source_color = vec3(0.80, 0.96, 0.74);
uniform vec3 tint_dry : source_color = vec3(1.04, 0.98, 0.66);
uniform vec3 tint_dark : source_color = vec3(0.56, 0.72, 0.52);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tex_scale;
	vec3 base = texture(grass_tex, uv).rgb;
	float big = texture(var_noise, wpos.xz * 0.014).r;
	float mid = texture(var_noise, wpos.xz * 0.055 + vec2(0.41, 0.67)).r;
	float fine = texture(var_noise, wpos.xz * 0.24 + vec2(0.19, 0.43)).r;
	vec3 tint = mix(tint_lush, tint_dry, smoothstep(0.44, 0.76, big));
	tint = mix(tint, tint_dark, smoothstep(0.50, 0.80, mid) * 0.58);
	tint *= 0.90 + fine * 0.20;
	ALBEDO = base * tint;
	NORMAL_MAP = texture(grass_norm, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.94;
	SPECULAR = 0.25;
}
"""
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.011
	noise.fractal_octaves = 4
	noise.seed = 4048
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.noise = noise
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("var_noise", noise_tex)
	if grass_mat is StandardMaterial3D:
		var std := grass_mat as StandardMaterial3D
		if std.albedo_texture != null:
			sm.set_shader_parameter("grass_tex", std.albedo_texture)
		if std.normal_enabled and std.normal_texture != null:
			sm.set_shader_parameter("grass_norm", std.normal_texture)
	return sm


# ---------------------------------------------------------------- A. 360°-Landschaft, Hügel & Waldgürtel

func _build_terrain_and_horizon() -> void:
	var meadow_mat := _make_meadow_material()
	# 340 × 320 m variierter Wiesenboden (passt exakt zwischen Garage-Horizont und Nord-Horizont, 0 % Void!)
	_add_box(Vector3(0.0, -0.26, 8.0), Vector3(340.0, 0.24, 300.0), meadow_mat, false)

	# 360°-Hügelkette am fernen Horizont
	var hill_mat := _mat(Color(0.15, 0.24, 0.16), 0.96, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	for i in range(32):
		var ang := (float(i) / 32.0) * TAU
		var dist := rng.randf_range(108.0, 142.0)
		var hx := cos(ang) * dist
		var hz := 12.0 + sin(ang) * dist
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.0
		sm.radial_segments = 14
		sm.rings = 6
		m.mesh = sm
		m.material_override = hill_mat
		m.position = Vector3(hx, -2.2, hz)
		m.scale = Vector3(rng.randf_range(42.0, 74.0), rng.randf_range(13.0, 27.0), rng.randf_range(32.0, 50.0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)

	# Dichter 360°-Waldgürtel aus Blender-Eichen & Kiefern (54..72 m, Straßen & Höfe ausgespart!)
	for ti in range(44):
		var ang := (float(ti) / 44.0) * TAU + rng.randf_range(-0.03, 0.03)
		var dist := rng.randf_range(56.0, 72.0)
		var tx := cos(ang) * dist
		var tz := 14.0 + sin(ang) * dist
		if tz > 15.5 and tz < 28.5:
			continue
		if absf(tx - (-42.0)) < 5.5 or absf(tx - 44.0) < 5.5:
			continue
		if tz > 28.0 and tz < 56.0 and tx > -32.0 and tx < 36.0:
			continue
		_spawn_tree(Vector3(tx, 0.0, tz), (ti % 2 == 0), rng.randf_range(1.05, 1.48), rng.randf_range(0.0, 360.0), false)


# ---------------------------------------------------------------- B. Straßen, Vorplatz, Bordsteine & Laternen

func _build_roads_and_yard() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var dark_asp := asp_mat.duplicate() as StandardMaterial3D
	dark_asp.albedo_color = Color(0.76, 0.79, 0.83)
	var curb_mat := _mat(Color(0.56, 0.57, 0.59), 0.88, 0.0)
	var walk_mat := _mat(Color(0.62, 0.63, 0.61), 0.90, 0.0)
	var joint_mat := _mat(Color(0.36, 0.37, 0.36), 0.95, 0.0)
	var stripe_mat := _mat(Color(0.92, 0.93, 0.91), 0.72, 0.0)
	var sign_blue := _mat(Color(0.08, 0.30, 0.66), 0.42, 0.15)
	var pole_mat := MatLib.make_brushed_metal(Color(0.24, 0.27, 0.30), 0.42, 0.68)

	# 1. Großer asphaltierter Campus-Hof (komplett eingezäunter Bereich X=-24.5..+26.5, Z=-12.5..+16.0)
	#    inkl. sauberer Zufahrt durch das Torhaus bis zur Campus-Allee!
	_add_box_static(Vector3(1.0, -0.11, 11.4), Vector3(51.0, 0.20, 10.6), dark_asp)
	_add_box_static(Vector3(-17.2, -0.11, -1.5), Vector3(14.6, 0.20, 21.5), dark_asp) # Technik-Hof West
	_add_box_static(Vector3( 18.2, -0.11, -1.5), Vector3(16.6, 0.20, 21.5), dark_asp) # Parkplatz Ost
	_add_box_static(Vector3(  0.0, -0.11, -9.5), Vector3(51.0, 0.20, 6.2), dark_asp)  # Feuerwehr-Umfahrt Nord
	_add_box_static(Vector3(  0.0, -0.11, 17.6), Vector3(10.8, 0.20, 4.6), dark_asp)  # Einfahrts-Trichter

	# Beton-Gehweg direkt vor dem Glas-Empfangserker rechts (X=+5.4..+11.2, Z=+6.2..+8.4)
	_add_box(Vector3(8.2, -0.02, 7.6), Vector3(5.8, 0.12, 2.2), walk_mat, false)

	# Weiße Fahrbahn-Leitlinien durch die Einfahrt & Ladehof
	for lz in [11.5, 13.5, 15.5, 17.5]:
		_add_box(Vector3(0.0, -0.005, float(lz)), Vector3(0.14, 0.008, 1.05), stripe_mat, false)
	# Rand-Bordsteine rund um die Einfahrt & den Campus-Hof
	_add_box(Vector3(-5.5, 0.01, 17.5), Vector3(0.18, 0.12, 3.2), curb_mat, false)
	_add_box(Vector3( 5.5, 0.01, 17.5), Vector3(0.18, 0.12, 3.2), curb_mat, false)

	# 2. Breite 2-spurige Hauptstraße 'RECHENZENTRUMS-ALLEE' bei Z = +22.0
	_add_box(Vector3(0.0, -0.12, ROAD_Z), Vector3(180.0, 0.20, 7.8), asp_mat, false)
	for sx in range(-86, 90, 4):
		_add_box(Vector3(float(sx), -0.014, ROAD_Z), Vector3(1.9, 0.01, 0.14), stripe_mat, false)
	for lz in [ROAD_Z - 3.55, ROAD_Z + 3.55]:
		_add_box(Vector3(0.0, -0.014, float(lz)), Vector3(180.0, 0.01, 0.12), stripe_mat, false)
	# Bordsteine + Gehwege (nördlich unterbrochen an der Einfahrt, südlich durchgehend)
	_add_box(Vector3(-47.7, 0.0, ROAD_Z - 3.98), Vector3(84.4, 0.12, 0.18), curb_mat, false)
	_add_box(Vector3( 47.7, 0.0, ROAD_Z - 3.98), Vector3(84.4, 0.12, 0.18), curb_mat, false)
	_add_box(Vector3(  0.0, -0.03, ROAD_Z - 3.98), Vector3(11.0, 0.06, 0.18), curb_mat, false)
	_add_box(Vector3(-47.7, -0.05, ROAD_Z - 4.95), Vector3(84.4, 0.20, 1.8), walk_mat, false)
	_add_box(Vector3( 47.7, -0.05, ROAD_Z - 4.95), Vector3(84.4, 0.20, 1.8), walk_mat, false)
	_add_box(Vector3(  0.0, 0.0, ROAD_Z + 3.98), Vector3(180.0, 0.12, 0.18), curb_mat, false)
	_add_box(Vector3(  0.0, -0.05, ROAD_Z + 4.95), Vector3(180.0, 0.20, 1.8), walk_mat, false)
	for jx in range(-36, 40, 2):
		_add_box(Vector3(float(jx), 0.052, ROAD_Z + 4.95), Vector3(0.025, 0.004, 1.8), joint_mat, false)

	# 2 seitliche Querstraßen (X = -42 & X = +44) für echte gewachsene Gewerbegebiets-Logik
	for qx in [-42.0, 44.0]:
		_add_box(Vector3(float(qx), -0.125, 36.0), Vector3(6.8, 0.20, 56.0), asp_mat, false)
		for sz in range(10, 62, 5):
			if absf(float(sz) - ROAD_Z) < 4.5:
				continue
			_add_box(Vector3(float(qx), -0.018, float(sz)), Vector3(0.13, 0.01, 2.0), stripe_mat, false)
		for dx in [-3.48, 3.48]:
			_add_box(Vector3(float(qx) + float(dx), -0.02, 46.0), Vector3(0.18, 0.12, 38.0), curb_mat, false)

	# 3. 8 deutsche Peitschen-Straßenlaternen (mit warmen Nacht-SpotLights an den Schlüssellampen!)
	var lamp_specs := [
		[Vector3(-34.0, 0.0, ROAD_Z - 4.35), 0.0, false],
		[Vector3(-12.0, 0.0, ROAD_Z - 4.35), 0.0, true],
		[Vector3( 12.0, 0.0, ROAD_Z - 4.35), 0.0, true],
		[Vector3( 34.0, 0.0, ROAD_Z - 4.35), 0.0, false],
		[Vector3(-24.0, 0.0, ROAD_Z + 4.35), 180.0, false],
		[Vector3(  0.0, 0.0, ROAD_Z + 4.35), 180.0, true],
		[Vector3( 24.0, 0.0, ROAD_Z + 4.35), 180.0, false],
		[Vector3( 13.5, 0.0, 12.8), 180.0, true], # Hof-Laterne am Parkplatz
	]
	for ls in lamp_specs:
		var lpos: Vector3 = ls[0]
		var lyaw: float = float(ls[1])
		var lamp := _spawn_model("ext_street_lamp", lpos, lyaw)
		if lamp != null:
			var gm := _clone_material_by_name(lamp, "Lamp_GlassMat")
			if gm != null:
				_street_lamp_mats.append(gm)
		if bool(ls[2]):
			var spot := SpotLight3D.new()
			var fwd := Vector3(0.0, 0.0, 1.3).rotated(Vector3.UP, deg_to_rad(lyaw))
			spot.position = lpos + fwd + Vector3(0.0, 4.95, 0.0)
			spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			spot.light_color = Color(1.0, 0.88, 0.64)
			spot.light_energy = 0.0
			spot.spot_range = 19.0
			spot.spot_angle = 68.0
			spot.shadow_enabled = false
			add_child(spot)
			_street_spot_lights.append(spot)

	# 4. Straßendetails: Gullys, Hydrant, Stromkasten & blaues Straßenschild 'RECHENZENTRUMS-ALLEE 1'
	for mx in [-18.0, -7.0, 7.5, 21.0]:
		_spawn_model("ext_manhole", Vector3(float(mx), 0.0, ROAD_Z - 3.25), 0.0)
	_spawn_model("ext_hydrant", Vector3(-9.5, 0.0, ROAD_Z - 4.85), 0.0)
	_spawn_model("ext_utility_box", Vector3(9.6, 0.0, ROAD_Z - 4.95), 0.0)

	# Straßenschild rechts an der Einfahrt
	var s_pos := Vector3(6.8, 0.0, ROAD_Z - 4.8)
	_add_cyl(s_pos + Vector3(0.0, 1.45, 0.0), 0.036, 2.9, pole_mat)
	_add_box(s_pos + Vector3(0.0, 2.68, 0.0), Vector3(1.55, 0.30, 0.04), sign_blue, false)
	var slbl := Label3D.new()
	slbl.text = "RECHENZENTRUMS-ALLEE 1"
	slbl.font_size = 24
	slbl.pixel_size = 0.0024
	slbl.outline_size = 0
	slbl.modulate = Color(0.95, 0.97, 1.0)
	slbl.position = s_pos + Vector3(0.0, 2.68, 0.03)
	add_child(slbl)


# ---------------------------------------------------------------- C. Hochsicherheits-Zaun + Pförtnerhaus + Pylon

func _build_perimeter_fence_and_gatehouse() -> void:
	# Vorne (Z = +16.2): links X=-25.0..-6.4 und rechts X=+5.6..+26.6 (Einfahrt + Pförtnerhaus dazwischen!)
	_build_fence_line(Vector3(-25.0, 0.0, 16.2), Vector3(-6.4, 0.0, 16.2))
	_build_fence_line(Vector3(  5.6, 0.0, 16.2), Vector3( 26.6, 0.0, 16.2))
	# Hinten (Z = -12.6) + Westseite (X = -25.0) + Ostseite (X = +26.6)
	_build_fence_line(Vector3(-25.0, 0.0, -12.6), Vector3(26.6, 0.0, -12.6))
	_build_fence_line(Vector3(-25.0, 0.0, -12.6), Vector3(-25.0, 0.0, 16.2))
	_build_fence_line(Vector3( 26.6, 0.0, -12.6), Vector3( 26.6, 0.0, 16.2))

	# Blender-Pförtnerhaus + hochgeklappte Sicherheits-Schranke + Campus-Pylon (Gebäude-Upgrade 'upg_security_gate'!)
	_upg_security_node = Node3D.new()
	add_child(_upg_security_node)
	var gh := ModelLoader.instantiate_custom_model("halle_nord_gatehouse")
	if gh != null:
		gh.position = Vector3(0.0, 0.0, 16.2)
		_upg_security_node.add_child(gh)
		var glow_m := _clone_material_by_name(gh, "GH_IntGlow")
		if glow_m != null:
			_evening_window_mats.append(glow_m)

	# Firmenname auf dem beleuchteten Campus-Pylon (X = +4.65, Z = 16.5)
	_pylon_sign_lbl = Label3D.new()
	_pylon_sign_lbl.text = "MEIN DATACENTER\nTIER-4 CAMPUS\nHALLE NORD"
	_pylon_sign_lbl.font_size = 22
	_pylon_sign_lbl.pixel_size = 0.0024
	_pylon_sign_lbl.outline_size = 0
	_pylon_sign_lbl.modulate = Color(0.92, 0.98, 1.0)
	_pylon_sign_lbl.position = Vector3(4.65, 3.55, 16.72)
	_upg_security_node.add_child(_pylon_sign_lbl)

	# Mikrodetails an der Einfahrt: 30-km/h-Verkehrsschild, Paketbox/Briefkasten & Beton-Blumenkübel!
	var p_mat := MatLib.make_brushed_metal(Color(0.24, 0.27, 0.30), 0.42, 0.68)
	_add_cyl(Vector3(-6.8, 1.35, ROAD_Z - 4.8), 0.032, 2.7, p_mat)
	_add_box(Vector3(-6.8, 2.48, ROAD_Z - 4.78), Vector3(0.56, 0.56, 0.03), _mat(Color(0.86, 0.14, 0.12), 0.40, 0.10), false)
	_add_box(Vector3(-6.8, 2.48, ROAD_Z - 4.76), Vector3(0.42, 0.42, 0.02), _mat(Color(0.95, 0.96, 0.96), 0.45, 0.02), false)
	var spd_lbl := Label3D.new()
	spd_lbl.text = "30"
	spd_lbl.font_size = 38
	spd_lbl.pixel_size = 0.0042
	spd_lbl.outline_size = 0
	spd_lbl.modulate = Color(0.08, 0.08, 0.10)
	spd_lbl.position = Vector3(-6.8, 2.48, ROAD_Z - 4.73)
	add_child(spd_lbl)
	# Briefkasten / Paketstation rechts am Gehweg
	_add_box(Vector3(7.8, 0.65, 16.8), Vector3(0.72, 1.30, 0.46), _mat(Color(0.92, 0.72, 0.10), 0.42, 0.15), false)
	# 2 bepflanzte Beton-Blumenkübel vor dem Empfangserker
	for bx in [5.9, 10.1]:
		_add_box(Vector3(float(bx), 0.26, 8.35), Vector3(0.68, 0.52, 0.68), _mat(Color(0.52, 0.54, 0.56), 0.86, 0.0), false)
		_spawn_model("ext_grass_tuft", Vector3(float(bx), 0.52, 8.35), float(bx) * 19.0, Vector3(0.85, 0.9, 0.85))

	# Zier-Hecken & Bäume entlang des Sicherheitszauns (weiches, edles Campus-Bild!)
	for hx in [-21.5, -15.5, -10.0, 10.2, 16.2, 22.4]:
		var hedge := _spawn_model("ext_hedge_bush", Vector3(float(hx), 0.0, 16.85), 0.0, Vector3(1.9, 1.0, 0.95))
		_apply_wind_to_canopy(hedge, 0.10, 0.96)
	for tp in [
		[Vector3(-27.8, 0.0, 12.5), false, 1.15, 22.0],
		[Vector3(-28.4, 0.0,  2.5), true,  1.18, 95.0],
		[Vector3(-27.5, 0.0, -8.5), false, 1.22, 180.0],
		[Vector3( 29.2, 0.0, 12.0), false, 1.12, 48.0],
		[Vector3( 29.8, 0.0,  1.5), true,  1.16, 140.0],
		[Vector3( 29.0, 0.0, -9.0), false, 1.20, 260.0],
		[Vector3( -9.5, 0.0, -16.5), true, 1.24, 30.0],
		[Vector3(  8.5, 0.0, -17.0), false, 1.22, 115.0],
	]:
		_spawn_tree(tp[0] as Vector3, bool(tp[1]), float(tp[2]), float(tp[3]), false)


# ---------------------------------------------------------------- D. Technik-Hof West (Diesel-Generator + 20-kV-Umspannwerk)

func _build_west_tech_yard() -> void:
	var galv := MatLib.make_brushed_metal(Color(0.58, 0.62, 0.66), 0.36, 0.80)
	var steel_dark := MatLib.make_brushed_metal(Color(0.14, 0.16, 0.20), 0.40, 0.72)

	# 1. Massiver 2-MVA Notstrom-Dieselgenerator (Gebäude-Upgrade 'upg_diesel_gen'!)
	_upg_diesel_node = Node3D.new()
	add_child(_upg_diesel_node)
	var d_gen := ModelLoader.instantiate_custom_model("halle_nord_diesel_gen")
	if d_gen != null:
		d_gen.position = Vector3(-16.2, 0.0, 3.8)
		_upg_diesel_node.add_child(d_gen)
	# Realistische Diesel-Abgas-Schwaden aus beiden Chrom-Auspuffrohren auf dem Dach!
	_upg_diesel_node.add_child(RealisticVfx.create_diesel_exhaust(Vector3(-17.55, 4.35, 3.38)))
	_upg_diesel_node.add_child(RealisticVfx.create_diesel_exhaust(Vector3(-17.55, 4.35, 4.22)))
	# Feiner Kondens-Dunst über dem Dach-Rückkühlwerk der Halle Nord
	add_child(RealisticVfx.create_chiller_mist(Vector3(-3.2, 7.15, -0.55)))
	add_child(RealisticVfx.create_chiller_mist(Vector3( 3.2, 7.15, -0.55)))
	# Verzinkte Hochstrom-Kabelbrücke direkt vom Generator-Container in die Westwand der Halle Nord!
	_add_box_to(_upg_diesel_node, Vector3(-12.0, 2.55, 3.8), Vector3(4.0, 0.22, 0.65), galv, false)
	_add_box_to(_upg_diesel_node, Vector3(-13.6, 1.32, 3.8), Vector3(0.16, 2.52, 0.56), steel_dark, false)
	# Sattes tiefes 2-MVA Dieselgenerator-Brummen am Technik-Hof
	var sub_stream := SfxManager.get_loop_stream("diesel_gen_idle")
	if sub_stream == null:
		sub_stream = SfxManager.get_loop_stream("substation_hum")
	if sub_stream != null:
		_diesel_audio = AudioStreamPlayer3D.new()
		_diesel_audio.stream = sub_stream
		_diesel_audio.position = Vector3(-16.5, 1.8, 0.5)
		_diesel_audio.max_distance = 36.0
		_diesel_audio.unit_size = 5.0
		_diesel_audio.volume_db = -80.0
		_upg_diesel_node.add_child(_diesel_audio)

	# 2. Eigenes 20-kV-Umspannwerk (Blender ext_substation_20kv.glb) im Nordwest-Technikhof!
	_spawn_model("ext_substation_20kv", Vector3(-18.2, 0.0, -5.8), 90.0)
	# Zweite Kabelbrücke vom Umspannwerk zur Halle Nord
	_add_box(Vector3(-12.8, 2.75, -5.0), Vector3(5.6, 0.20, 0.55), galv, false)
	_add_box(Vector3(-15.2, 1.40, -5.0), Vector3(0.14, 2.72, 0.45), steel_dark, false)

	# 3. Lager-Container, Palettenstapel & Mülltonnen im hinteren Wirtschaftshof West
	_spawn_model("ext_shipping_container", Vector3(-20.4, 0.0, 11.4), 0.0)
	_spawn_model("ext_pallet_stack", Vector3(-14.6, 0.0, 11.8), 12.0)
	_spawn_model("ext_pallet_stack", Vector3(-12.8, 0.0, 12.2), -8.0)
	_spawn_model("ext_trash_bin", Vector3(-10.8, 0.0, 7.6), 90.0)
	_spawn_model("ext_trash_bin", Vector3(-10.8, 0.0, 8.6), 90.0)


# ---------------------------------------------------------------- E. Empfang Ost: 3 Fahnenmasten, Solar-Carport & Parkplatz

func _build_east_parking_and_solar_carport() -> void:
	var steel := MatLib.make_brushed_metal(Color(0.15, 0.18, 0.22), 0.36, 0.78)
	var alu := MatLib.make_brushed_metal(Color(0.70, 0.74, 0.78), 0.28, 0.85)
	var pv_mat := StandardMaterial3D.new()
	pv_mat.albedo_color = Color(0.06, 0.14, 0.28)
	pv_mat.roughness = 0.12
	pv_mat.metallic = 0.48
	pv_mat.clearcoat_enabled = true
	pv_mat.clearcoat = 0.85
	var stripe_mat := _mat(Color(0.92, 0.93, 0.91), 0.72, 0.0)
	var green_charge := StandardMaterial3D.new()
	green_charge.albedo_color = Color(0.14, 0.90, 0.44)
	green_charge.emission_enabled = true
	green_charge.emission = Color(0.14, 0.92, 0.44)
	green_charge.emission_energy_multiplier = 1.6

	# 1. 3 repräsentative wehende Firmen-Fahnenmasten direkt vor dem Glas-NOC-Erker!
	_spawn_flagpole(Vector3(11.4, 0.0, 10.6), 15.0, Color(0.08, 0.22, 0.44), Color(0.14, 0.72, 0.98))
	_spawn_flagpole(Vector3(13.2, 0.0, 10.6), 15.0, Color(0.12, 0.15, 0.20), Color(0.96, 0.74, 0.14))
	_spawn_flagpole(Vector3(15.0, 0.0, 10.6), 15.0, Color(0.08, 0.22, 0.44), Color(0.14, 0.72, 0.98))

	# 2. Moderner Solar-Carport + Wallboxen (Gebäude-Upgrade 'upg_pv_solar'!)
	_upg_pv_node = Node3D.new()
	add_child(_upg_pv_node)
	var cp_x := 20.2
	var cp_z := 1.6
	for pz in [-3.4, 1.6, 6.6]:
		_add_box_to(_upg_pv_node, Vector3(cp_x + 2.6, 1.55, float(pz)), Vector3(0.24, 3.10, 0.24), steel, false)
		_add_box_to(_upg_pv_node, Vector3(cp_x + 0.2, 3.05, float(pz)), Vector3(5.8, 0.20, 0.20), steel, false)
	# Geneigtes Photovoltaik-Moduldach mit Alu-Rahmen & 4 PV-Reihen
	var pv_roof := Node3D.new()
	pv_roof.position = Vector3(cp_x + 0.1, 3.22, cp_z)
	pv_roof.rotation_degrees.z = 8.0
	_upg_pv_node.add_child(pv_roof)
	_add_box_to(pv_roof, Vector3.ZERO, Vector3(6.2, 0.10, 11.8), alu)
	for ri in range(4):
		var rz := -4.35 + float(ri) * 2.90
		_add_box_to(pv_roof, Vector3(0.0, 0.065, rz), Vector3(5.85, 0.04, 2.65), pv_mat)

	# 4 weiße Parkbucht-Linien + Parkplatz-Nummern (P1–P4) + dezente Reifenspuren in der Einfahrt!
	for pi in range(5):
		var lz := -4.2 + float(pi) * 2.9
		_add_box(Vector3(cp_x, -0.005, lz), Vector3(5.4, 0.008, 0.11), stripe_mat, false)
	for bi in range(4):
		var pl := Label3D.new()
		pl.text = "P%d" % (bi + 1)
		pl.font_size = 44
		pl.pixel_size = 0.0052
		pl.outline_size = 0
		pl.modulate = Color(0.88, 0.90, 0.92, 0.72)
		pl.rotation_degrees = Vector3(-90.0, 90.0, 0.0)
		pl.position = Vector3(cp_x - 2.1, 0.005, -2.75 + float(bi) * 2.9)
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pl)
	# Dezente dunkle Reifenspuren durch die Einfahrt bis vor die Ladebucht (Weathering!)
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.06, 0.065, 0.07, 0.32)
	tire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tire_mat.roughness = 0.92
	for tx in [-0.92, 0.92]:
		_add_box(Vector3(float(tx), 0.004, 14.2), Vector3(0.42, 0.004, 11.2), tire_mat, false)
	for cz in [-2.75, 0.15, 3.05, 5.95]:
		_add_box_to(_upg_pv_node, Vector3(cp_x + 2.95, 0.72, float(cz)), Vector3(0.22, 1.42, 0.28), steel, false)
		_add_box_to(_upg_pv_node, Vector3(cp_x + 2.83, 1.12, float(cz)), Vector3(0.03, 0.24, 0.14), green_charge, false)

	# 3 geparkte Blender-Flotten- & Mitarbeiter-Fahrzeuge sauber unter dem Solar-Carport (erscheinen mit dem Carport!)
	for pv_car in [
		["ext_car_sedan", Vector3(cp_x + 0.1, 0.0, -2.75), 180.0, Color(0.10, 0.22, 0.38)],
		["ext_car_suv",   Vector3(cp_x + 0.1, 0.0,  0.15), 180.0, Color(0.76, 0.79, 0.83)],
		["ext_car_van",   Vector3(cp_x + 0.3, 0.0,  5.95), 180.0, Color(0.92, 0.93, 0.95)],
	]:
		var cinst := ModelLoader.instantiate_custom_model(str(pv_car[0]))
		if cinst != null:
			cinst.position = pv_car[1] as Vector3
			cinst.rotation_degrees.y = float(pv_car[2])
			_upg_pv_node.add_child(cinst)
			var cpm := _clone_material_by_name(cinst, "Car_PaintMat")
			if cpm != null:
				cpm.albedo_color = pv_car[3] as Color

	# Dekorative Zier-Grasbüschel & Heckeninsel zwischen Einfahrt und Fahnenmasten
	_add_box(Vector3(13.2, -0.02, 10.6), Vector3(6.6, 0.14, 2.1), _mat(Color(0.54, 0.56, 0.58), 0.88, 0.0), false)
	_add_box(Vector3(13.2, 0.055, 10.6), Vector3(6.2, 0.04, 1.7), _mat(Color(0.20, 0.34, 0.18), 0.94, 0.0), false)
	for gx in [10.6, 12.2, 14.0, 15.6]:
		_spawn_model("ext_grass_tuft", Vector3(float(gx), 0.06, 10.6), float(gx) * 23.0, Vector3(1.1, 1.0, 1.1))


# ---------------------------------------------------------------- F. Gegenüberliegende Campus-Nachbarn (0 % Ödnis!)

func _build_south_campus_neighbors() -> void:
	var asp_mat := MatLib.get_mat("asphalt")
	var stripe_mat := _mat(Color(0.90, 0.90, 0.88), 0.76, 0.0)

	# 1. Links gegenüber (Z = +36): Moderner Tech-Bürokomplex 'VERION CLOUD CAMPUS II'
	_add_box(Vector3(-19.5, -0.10, 32.5), Vector3(24.0, 0.16, 12.0), asp_mat, false)
	var office := _spawn_model("ext_office_tech", Vector3(-19.5, 0.0, 41.0), 180.0)
	_register_evening_windows(office, "Off_GlassMat")
	_spawn_parked_vehicle("ext_car_sedan", Vector3(-25.0, 0.0, 30.8), 90.0, Color(0.52, 0.16, 0.14))
	_spawn_parked_vehicle("ext_car_suv",   Vector3(-21.2, 0.0, 30.8), 90.0, Color(0.18, 0.24, 0.32))
	_spawn_parked_vehicle("ext_car_sedan", Vector3(-14.5, 0.0, 30.8), 90.0, Color(0.84, 0.86, 0.88))
	for px in [-26.8, -23.1, -19.4, -12.6]:
		_add_box(Vector3(float(px), -0.015, 30.8), Vector3(0.10, 0.008, 4.6), stripe_mat, false)
	_spawn_flagpole(Vector3(-9.5, 0.0, 31.2), 180.0, Color(0.12, 0.32, 0.62), Color(0.92, 0.70, 0.16))

	# 2. Rechts gegenüber (Z = +39): Große Nachbar-Datacenter-/Logistikhalle 'NORDCLOUD DATA HUB'
	_add_box(Vector3(19.5, -0.10, 34.0), Vector3(28.0, 0.16, 15.0), asp_mat, false)
	var hall := _spawn_model("ext_logistics_hall", Vector3(20.5, 0.0, 43.0), 180.0)
	_register_evening_windows(hall, "Log_GlassMat")
	_spawn_model("ext_dock_trailer", Vector3(14.5, 0.0, 35.8), 180.0)
	_spawn_parked_vehicle("ext_car_van", Vector3(27.5, 0.0, 31.5), 90.0, Color(0.92, 0.93, 0.94))

	# 3. Weiteres entferntes Tech-Gebäude westlich der Querstraße (X = -58) + Bäume & Hecken
	var west_off := _spawn_model("ext_office_tech", Vector3(-58.0, 0.0, 8.0), 90.0)
	_register_evening_windows(west_off, "Off_GlassMat")
	var east_off := _spawn_model("ext_office_tech", Vector3(58.0, 0.0, 8.0), -90.0)
	_register_evening_windows(east_off, "Off_GlassMat")

	for tx in [-33.0, -5.5, 4.5, 34.5]:
		_spawn_tree(Vector3(float(tx), 0.0, 29.8), int(absf(tx)) % 2 == 0, 1.05, float(tx) * 7.0, false)
	for hx in [-31.0, -10.5, 2.0, 31.5]:
		var hb := _spawn_model("ext_hedge_bush", Vector3(float(hx), 0.0, 27.6), 0.0, Vector3(2.2, 1.0, 1.0))
		_apply_wind_to_canopy(hb, 0.10, 0.94)


# ---------------------------------------------------------------- G. Lebendiger Horizont: 4 Windräder + Hochspannungsmasten

func _build_living_horizon_and_powerlines() -> void:
	# 4 drehende Windräder auf den umliegenden Hügeln
	var turbine_specs := [
		[Vector3(-76.0, 0.0, -58.0), 145.0, 1.15, 0.85, 0.2],
		[Vector3( 78.0, 0.0, -52.0), -135.0, 1.22, 0.78, 1.9],
		[Vector3(-82.0, 0.0,  62.0), 32.0,  1.18, 0.92, 3.6],
		[Vector3( 84.0, 0.0,  64.0), -36.0, 1.25, 0.82, 5.1],
	]
	for ts in turbine_specs:
		var wt := _spawn_model("ext_wind_turbine", ts[0] as Vector3, float(ts[1]), Vector3.ONE * float(ts[2]))
		if wt != null:
			var rotor := wt.find_child("Rotor", true, false) as Node3D
			if rotor != null:
				_turbine_rotors.append({"node": rotor, "speed": float(ts[3]), "phase": float(ts[4])})
			var bm := _clone_material_by_name(wt, "WT_BeaconMat")
			if bm != null:
				_aviation_beacon_mats.append(bm)

	# 3 Hochspannungs-Gittermasten von Nordwest direkt bis zum eigenen 20-kV-Umspannwerk (-18.2, -5.8)!
	var pylon_positions: Array[Vector3] = [
		Vector3(-92.0, 0.0, -32.0),
		Vector3(-56.0, 0.0, -20.0),
		Vector3(-30.0, 0.0, -10.5),
	]
	for pp in pylon_positions:
		_spawn_model("ext_power_pylon", pp, 18.0, Vector3.ONE * 0.95)

	var cable_mat := _mat(Color(0.08, 0.09, 0.11), 0.60, 0.50)
	for i in range(pylon_positions.size() - 1):
		var a := pylon_positions[i]
		var b := pylon_positions[i + 1]
		for off in [Vector3(0.0, 17.4, -3.4), Vector3(0.0, 17.4, 3.4), Vector3(0.0, 13.6, 0.0)]:
			_add_sagging_cable(a + off, b + off, 1.85, 0.045, cable_mat)
	# Zuleitung vom letzten Mast direkt herunter aufs 20-kV-Umspannwerk!
	var last_p := pylon_positions[pylon_positions.size() - 1]
	for off in [Vector3(0.0, 13.6, -2.0), Vector3(0.0, 13.6, 2.0)]:
		_add_sagging_cable(last_p + off, Vector3(-19.5, 4.4, -6.2) + Vector3(0.0, 0.0, off.z * 0.4), 0.95, 0.04, cable_mat)


# ---------------------------------------------------------------- H. Lebendiger KI-Verkehr auf der Rechenzentrums-Allee

func _build_campus_traffic() -> void:
	var specs := [
		["ext_car_sedan", 1.0,  -45.0, ROAD_Z + 1.85, 10.5, Color(0.14, 0.24, 0.40)],
		["ext_car_suv",   -1.0,  36.0, ROAD_Z - 1.85, 11.2, Color(0.76, 0.78, 0.80)],
		["ext_car_van",   1.0,   18.0, ROAD_Z + 1.85,  9.2, Color(0.92, 0.93, 0.95)],
	]
	for sp in specs:
		var m_id := str(sp[0])
		var dir := float(sp[1])
		var x0 := float(sp[2])
		var z0 := float(sp[3])
		var spd := float(sp[4])
		var col: Color = sp[5]
		var car := _spawn_model(m_id, Vector3(x0, 0.0, z0), 0.0 if dir > 0.0 else 180.0)
		if car == null:
			continue
		var pm := _clone_material_by_name(car, "Car_PaintMat")
		if pm != null:
			pm.albedo_color = col
		var wheels: Array[Node3D] = []
		for wn in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
			var w := car.find_child(wn, true, false) as Node3D
			if w != null:
				wheels.append(w)
		_traffic_cars.append({
			"node": car,
			"dir": dir,
			"z": z0,
			"speed": spd,
			"wheels": wheels,
		})


# ---------------------------------------------------------------- Live-Updates

func _update_night_lights() -> void:
	var tod := GameState.time_of_day if GameState.is_active else 0.38
	var elev := sin((tod - 0.25) * TAU)
	var night_t := clampf(1.0 - (elev * 4.0 + 0.35), 0.0, 1.0)
	for gm in _street_lamp_mats:
		gm.emission_enabled = (night_t > 0.05)
		gm.emission = Color(1.0, 0.86, 0.56)
		gm.emission_energy_multiplier = night_t * 3.2
	for sp in _street_spot_lights:
		sp.light_energy = night_t * 4.4
	for wm in _evening_window_mats:
		wm.emission_enabled = (night_t > 0.12)
		wm.emission = Color(1.0, 0.88, 0.64)
		wm.emission_energy_multiplier = night_t * 1.9
	var pulse := 1.0 if sin(_anim_t * 2.8) > 0.35 else 0.08
	for bm in _aviation_beacon_mats:
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.14, 0.10)
		bm.emission_energy_multiplier = pulse * (3.2 + night_t * 2.8)


func _update_wind_and_flags() -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var t_str := 0.075
	var t_spd := 1.55
	var f_amp := 0.095
	var f_spd := 4.3
	if w == "storm":
		t_str = 0.24
		t_spd = 3.4
		f_amp = 0.22
		f_spd = 9.5
	elif w == "rain":
		t_str = 0.14
		t_spd = 2.3
		f_amp = 0.14
		f_spd = 6.2
	for sm in _wind_materials:
		sm.set_shader_parameter("wind_strength", t_str)
		sm.set_shader_parameter("wind_speed", t_spd)
	for fm in _flag_materials:
		fm.set_shader_parameter("wind_amp", f_amp)
		fm.set_shader_parameter("wind_speed", f_spd)


func _update_turbines(delta: float) -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var mult := 2.1 if w == "storm" else (1.45 if w == "rain" else 1.0)
	for tr_d in _turbine_rotors:
		var r: Node3D = tr_d["node"]
		if r != null:
			r.rotation.z -= float(tr_d["speed"]) * mult * delta


## Steht das Lieferfahrzeug im Weg? Dann halten die Autos davor an.
func _van_blocks(node: Node3D, dir: float) -> bool:
	if not GameState.is_active or GameState.van_phase == "idle" or GameState.van_site != "halle_nord" or GameState.van_phase == "unloading":
		return false
	var vp := DeliveryPlan.vehicle_pose("halle_nord", GameState.van_delivery_tier, GameState.van_phase, GameState.van_phase_time)
	var gap := ((vp["pos"] as Vector3).x - node.position.x) * dir
	return gap > 0.0 and gap < 15.0


func _update_traffic(delta: float) -> void:
	for c in _traffic_cars:
		var node: Node3D = c["node"]
		var dir: float = float(c["dir"])
		var spd: float = float(c["speed"])
		if _van_blocks(node, dir):
			spd = 0.0
		node.position.x += dir * spd * delta
		if dir > 0.0 and node.position.x > CAMPUS_TRAFFIC_MAX:
			node.position.x = CAMPUS_TRAFFIC_MIN
		elif dir < 0.0 and node.position.x < CAMPUS_TRAFFIC_MIN:
			node.position.x = CAMPUS_TRAFFIC_MAX
		var rot_d := (spd * delta) / 0.36
		for w in (c["wheels"] as Array):
			(w as Node3D).rotation.z -= rot_d


func _update_diesel_audio() -> void:
	if _diesel_audio == null:
		return
	var gain := SettingsManager.get_effective_sfx_gain()
	if not GameState.is_active or gain < 0.005:
		if _diesel_audio.playing:
			_diesel_audio.stop()
		return
	if not _diesel_audio.playing:
		_diesel_audio.play()
	_diesel_audio.volume_db = linear_to_db(gain) - 18.0


# ---------------------------------------------------------------- Helfer

func _spawn_model(model_id: String, pos: Vector3, yaw_deg: float = 0.0, scl: Vector3 = Vector3.ONE) -> Node3D:
	var inst := ModelLoader.instantiate_custom_model(model_id)
	if inst == null:
		return null
	inst.position = pos
	inst.rotation_degrees.y = yaw_deg
	inst.scale = scl
	add_child(inst)
	return inst


func _spawn_tree(pos: Vector3, is_pine: bool, scale_val: float, yaw_deg: float, cast_sh: bool) -> void:
	var tr := _spawn_model("ext_tree_pine" if is_pine else "ext_tree_oak", pos, yaw_deg, Vector3.ONE * scale_val)
	if tr == null:
		return
	if not cast_sh:
		_set_shadows_recursive(tr, false)
	_apply_wind_to_canopy(tr, 1.2 if is_pine else 1.8, 0.92 + fmod(absf(pos.x * 0.13 + pos.z * 0.07), 0.16))


func _spawn_flagpole(pos: Vector3, yaw_deg: float, flag_col: Color, stripe_col: Color) -> void:
	var fp := _spawn_model("ext_flagpole", pos, yaw_deg)
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


func _spawn_parked_vehicle(model_id: String, pos: Vector3, yaw_deg: float, paint_col: Color) -> void:
	var car := _spawn_model(model_id, pos, yaw_deg)
	if car == null:
		return
	var pm := _clone_material_by_name(car, "Car_PaintMat")
	if pm != null:
		pm.albedo_color = paint_col


func _build_fence_line(a: Vector3, b: Vector3) -> void:
	var diff := b - a
	var length := diff.length()
	if length < 0.2:
		return
	var count := maxi(1, int(roundf(length / 2.50)))
	var step := length / float(count)
	var yaw := rad_to_deg(atan2(-diff.z, diff.x))
	var dir := diff / length
	for i in range(count):
		var p := a + dir * ((float(i) + 0.5) * step)
		_spawn_model("ext_fence_panel", p, yaw, Vector3(step / 2.50, 1.0, 1.0))


func _add_sagging_cable(a: Vector3, b: Vector3, sag: float, radius: float, mat: Material) -> void:
	var segs := 8
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var pt := a.lerp(b, t)
		pt.y -= sin(t * PI) * sag
		var d := pt - prev
		var l := d.length()
		if l > 0.01:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = radius
			cm.bottom_radius = radius
			cm.height = l
			cm.radial_segments = 6
			mi.mesh = cm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var dir := d / l
			var q: Quaternion = Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
			mi.transform = Transform3D(Basis(q), (prev + pt) * 0.5)
			add_child(mi)
		prev = pt


func _apply_wind_to_canopy(root_node: Node3D, height_start: float, tint_shift: float) -> void:
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


func _register_evening_windows(root_node: Node3D, mat_substr: String) -> void:
	if root_node == null:
		return
	var wm := _clone_material_by_name(root_node, mat_substr)
	if wm != null:
		_evening_window_mats.append(wm)


func _clone_material_by_name(root_node: Node, substr: String) -> StandardMaterial3D:
	if root_node is MeshInstance3D:
		var mi := root_node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D and mat.resource_name.find(substr) >= 0:
					var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, dup)
					return dup
	for c in root_node.get_children():
		var found := _clone_material_by_name(c, substr)
		if found != null:
			return found
	return null


func _set_shadows_recursive(node: Node, enabled: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_set_shadows_recursive(c, enabled)


func _add_box(pos: Vector3, sz: Vector3, mat: Material, cast_sh: bool = false) -> MeshInstance3D:
	return _add_box_to(self, pos, sz, mat, cast_sh)


func _add_box_to(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, cast_sh: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_box_static(pos: Vector3, sz: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	add_child(body)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	col.shape = bs
	body.add_child(col)
	_add_box_to(body, Vector3.ZERO, sz, mat, false)


func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
