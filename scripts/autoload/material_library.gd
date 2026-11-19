extends Node
## v0.6 Realistic Industrial & Hardware PBR Material Library.
## Generates crisp tileable architectural & authentic PC/Server hardware textures
## (Natural Concrete, Datacenter Raised Floor, Off-White Drywall, Red-Brown Brick,
## Emerald & Matte-Black Motherboard PCBs with Copper Traces, Finned Heatsinks,
## Brushed Aluminum, Copper, Gold Contacts) + Non-Neon IPS Monitor & Natural Sky Shaders.

var _materials: Dictionary = {}
var _sky_shader_mat: ShaderMaterial = null
var _os_screen_mat: ShaderMaterial = null
var _telemetry_screen_mat: ShaderMaterial = null


func _ready() -> void:
	_build_all_materials()
	_build_custom_shaders()


func get_mat(mat_id: String) -> StandardMaterial3D:
	if _materials.has(mat_id):
		return _materials[mat_id] as StandardMaterial3D
	return _materials.get("default", StandardMaterial3D.new()) as StandardMaterial3D


func make_brushed_metal(col: Color, rough: float = 0.34, metal: float = 0.72) -> StandardMaterial3D:
	var base := get_mat("brushed_steel")
	var m := base.duplicate() as StandardMaterial3D
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func get_sky_shader_material() -> ShaderMaterial:
	return _sky_shader_mat


func get_os_screen_material() -> ShaderMaterial:
	return _os_screen_mat


func get_telemetry_screen_material() -> ShaderMaterial:
	return _telemetry_screen_mat


func _build_all_materials() -> void:
	_materials["default"] = _simple(Color(0.55, 0.55, 0.54), 0.7, 0.1)

	# 1. Natural Warm-Grey Poured Garage Concrete Floor (real expansion joints, matte-satin)
	var conc_pair := _gen_tiled_concrete(256)
	var conc_mat := StandardMaterial3D.new()
	conc_mat.albedo_texture = conc_pair[0]
	conc_mat.normal_enabled = true
	conc_mat.normal_texture = conc_pair[1]
	conc_mat.normal_scale = 0.55
	conc_mat.roughness = 0.76
	conc_mat.metallic = 0.04
	conc_mat.uv1_triplanar = true
	conc_mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	_materials["concrete_floor"] = conc_mat

	# 2. Industrial Anti-Static Light-Grey Raised Floor (Hall B — realistic server room tiles)
	var epoxy_pair := _gen_raised_floor_tiles(256, Color(0.45, 0.47, 0.49), Color(0.52, 0.54, 0.56), Color(0.24, 0.26, 0.28))
	var epoxy_mat := StandardMaterial3D.new()
	epoxy_mat.albedo_texture = epoxy_pair[0]
	epoxy_mat.normal_enabled = true
	epoxy_mat.normal_texture = epoxy_pair[1]
	epoxy_mat.normal_scale = 0.36
	epoxy_mat.roughness = 0.42
	epoxy_mat.metallic = 0.10
	epoxy_mat.clearcoat_enabled = true
	epoxy_mat.clearcoat = 0.18
	epoxy_mat.clearcoat_roughness = 0.34
	epoxy_mat.uv1_triplanar = true
	epoxy_mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
	_materials["epoxy_floor"] = epoxy_mat

	# 3. Clean Bright Enterprise Raised Datacenter Floor (Hall C — like Hetzner/AWS/Google DC)
	var ent_pair := _gen_raised_floor_tiles(256, Color(0.68, 0.70, 0.72), Color(0.75, 0.77, 0.79), Color(0.36, 0.38, 0.41))
	var ent_mat := StandardMaterial3D.new()
	ent_mat.albedo_texture = ent_pair[0]
	ent_mat.normal_enabled = true
	ent_mat.normal_texture = ent_pair[1]
	ent_mat.normal_scale = 0.42
	ent_mat.roughness = 0.38
	ent_mat.metallic = 0.14
	ent_mat.clearcoat_enabled = true
	ent_mat.clearcoat = 0.22
	ent_mat.clearcoat_roughness = 0.28
	ent_mat.uv1_triplanar = true
	ent_mat.uv1_scale = Vector3(0.60, 0.60, 0.60)
	_materials["enterprise_floor"] = ent_mat

	# 4. Realistic Painted Off-White / Warm Light-Grey Drywall & Concrete Block Interior Wall
	var wall_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.08, 3, 404)
	var wall_tex := _make_noise_tex(wall_noise, 256, Color(0.74, 0.73, 0.70), Color(0.83, 0.82, 0.79))
	var wall_norm := _make_normal_tex(wall_noise, 256, 1.1)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_texture = wall_tex
	wall_mat.normal_enabled = true
	wall_mat.normal_texture = wall_norm
	wall_mat.normal_scale = 0.32
	wall_mat.roughness = 0.86
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	_materials["garage_wall"] = wall_mat

	# 5. Realistic Industrial Medium-Grey Lower Wall Paint (Wainscoting)
	var wain_mat := wall_mat.duplicate() as StandardMaterial3D
	wain_mat.albedo_texture = _make_noise_tex(wall_noise, 256, Color(0.38, 0.40, 0.42), Color(0.45, 0.47, 0.50))
	wain_mat.roughness = 0.72
	wain_mat.metallic = 0.04
	_materials["wainscot_wall"] = wain_mat

	# 6. Brushed Anodized Server Steel & Galvanized Chassis Metal
	var steel_pair := _gen_brushed_metal_tex(128)
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.18, 0.19, 0.21)
	steel_mat.normal_enabled = true
	steel_mat.normal_texture = steel_pair[1]
	steel_mat.normal_scale = 0.28
	steel_mat.roughness = 0.36
	steel_mat.metallic = 0.72
	steel_mat.uv1_scale = Vector3(3.0, 2.0, 3.0)
	_materials["brushed_steel"] = steel_mat

	# 7. Perforated Server Rack Hex/Grid Steel Mesh
	var perf_pair := _gen_perforated_mesh_tex(128)
	var perf_mat := StandardMaterial3D.new()
	perf_mat.albedo_texture = perf_pair[0]
	perf_mat.normal_enabled = true
	perf_mat.normal_texture = perf_pair[1]
	perf_mat.normal_scale = 1.10
	perf_mat.roughness = 0.48
	perf_mat.metallic = 0.62
	perf_mat.uv1_scale = Vector3(4.0, 6.0, 4.0)
	_materials["perforated_mesh"] = perf_mat

	# 8. Diagonal Industrial Safety Hazard Stripes (Muted realistic safety yellow & matte charcoal)
	var haz_tex := _gen_hazard_stripes_tex(128)
	var haz_mat := StandardMaterial3D.new()
	haz_mat.albedo_texture = haz_tex
	haz_mat.roughness = 0.62
	haz_mat.metallic = 0.06
	haz_mat.uv1_triplanar = true
	haz_mat.uv1_scale = Vector3(0.85, 0.85, 0.85)
	_materials["hazard_stripes"] = haz_mat

	# 9. Corrugated Galvanized Steel (Garage Door & Expansion Partitions)
	var corr_pair := _gen_corrugated_tex(128)
	var corr_mat := StandardMaterial3D.new()
	corr_mat.albedo_texture = corr_pair[0]
	corr_mat.normal_enabled = true
	corr_mat.normal_texture = corr_pair[1]
	corr_mat.normal_scale = 0.90
	corr_mat.roughness = 0.48
	corr_mat.metallic = 0.48
	corr_mat.uv1_triplanar = true
	corr_mat.uv1_scale = Vector3(0.65, 0.65, 0.65)
	_materials["corrugated_metal"] = corr_mat

	# 10. Realistic Warm Red-Brown Architectural Brick Exterior Facade
	var brick_pair := _gen_brick_tex(256)
	var brick_mat := StandardMaterial3D.new()
	brick_mat.albedo_texture = brick_pair[0]
	brick_mat.normal_enabled = true
	brick_mat.normal_texture = brick_pair[1]
	brick_mat.normal_scale = 0.88
	brick_mat.roughness = 0.86
	brick_mat.uv1_triplanar = true
	brick_mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
	_materials["exterior_brick"] = brick_mat

	# 11. Natural Warm Oak Workbench / Desk Wood
	var wood_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.05, 4, 606)
	var wood_tex := _make_noise_tex(wood_noise, 256, Color(0.42, 0.29, 0.17), Color(0.60, 0.44, 0.28))
	var wood_norm := _make_normal_tex(wood_noise, 256, 0.9)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_texture = wood_tex
	wood_mat.normal_enabled = true
	wood_mat.normal_texture = wood_norm
	wood_mat.normal_scale = 0.24
	wood_mat.roughness = 0.52
	wood_mat.metallic = 0.02
	wood_mat.uv1_scale = Vector3(3.5, 0.6, 1.0)
	_materials["wood_desk"] = wood_mat

	# 12. Natural Kraft Corrugated Cardboard Box
	var card_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.16, 3, 707)
	var card_tex := _make_noise_tex(card_noise, 128, Color(0.60, 0.47, 0.32), Color(0.72, 0.58, 0.41))
	var card_norm := _make_normal_tex(card_noise, 128, 1.0)
	var card_mat := StandardMaterial3D.new()
	card_mat.albedo_texture = card_tex
	card_mat.normal_enabled = true
	card_mat.normal_texture = card_norm
	card_mat.normal_scale = 0.34
	card_mat.roughness = 0.88
	_materials["cardboard"] = card_mat

	# 13. Exterior Asphalt Driveway / Road
	var asp_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.25, 4, 808)
	var asp_tex := _make_noise_tex(asp_noise, 256, Color(0.24, 0.24, 0.25), Color(0.35, 0.35, 0.36))
	var asp_norm := _make_normal_tex(asp_noise, 256, 2.2)
	var asp_mat := StandardMaterial3D.new()
	asp_mat.albedo_texture = asp_tex
	asp_mat.normal_enabled = true
	asp_mat.normal_texture = asp_norm
	asp_mat.normal_scale = 0.55
	asp_mat.roughness = 0.89
	asp_mat.uv1_triplanar = true
	asp_mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
	_materials["asphalt"] = asp_mat

	# 14. Natural Exterior Grass Lawn
	var grass_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.12, 4, 909)
	var grass_tex := _make_noise_tex(grass_noise, 256, Color(0.22, 0.36, 0.16), Color(0.34, 0.48, 0.22))
	var grass_norm := _make_normal_tex(grass_noise, 256, 1.5)
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_texture = grass_tex
	grass_mat.normal_enabled = true
	grass_mat.normal_texture = grass_norm
	grass_mat.normal_scale = 0.42
	grass_mat.roughness = 0.92
	grass_mat.uv1_triplanar = true
	grass_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	_materials["grass"] = grass_mat

	# 15. Realistic Clear / Slightly Tinted Cabinet Glass
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.80, 0.84, 0.20)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.12
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.75
	glass.clearcoat_roughness = 0.06
	_materials["smoked_glass"] = glass

	# ==========================================================================
	# NEW v0.6 AUTHENTIC PC & SERVER HARDWARE PBR MATERIALS!
	# ==========================================================================

	# 16. Enterprise Green Server Motherboard PCB (with copper circuit traces & gold vias!)
	var pcb_g_pair := _gen_pcb_tex(256, Color(0.06, 0.26, 0.14), Color(0.11, 0.36, 0.20), Color(0.76, 0.64, 0.26))
	var pcb_g := StandardMaterial3D.new()
	pcb_g.albedo_texture = pcb_g_pair[0]
	pcb_g.normal_enabled = true
	pcb_g.normal_texture = pcb_g_pair[1]
	pcb_g.normal_scale = 0.85
	pcb_g.roughness = 0.36
	pcb_g.metallic = 0.18
	_materials["pcb_green"] = pcb_g

	# 17. Matte-Black Workstation/GPU PCB (with metallic dark-gold circuit paths!)
	var pcb_b_pair := _gen_pcb_tex(256, Color(0.08, 0.09, 0.10), Color(0.14, 0.15, 0.17), Color(0.62, 0.52, 0.28))
	var pcb_b := StandardMaterial3D.new()
	pcb_b.albedo_texture = pcb_b_pair[0]
	pcb_b.normal_enabled = true
	pcb_b.normal_texture = pcb_b_pair[1]
	pcb_b.normal_scale = 0.85
	pcb_b.roughness = 0.40
	pcb_b.metallic = 0.22
	_materials["pcb_black"] = pcb_b

	# 18. Finned Aluminum Heatsink (ribbed cooling fins + normal map)
	var fin_pair := _gen_heatsink_fins_tex(128, Color(0.72, 0.74, 0.77))
	var fin_al := StandardMaterial3D.new()
	fin_al.albedo_texture = fin_pair[0]
	fin_al.normal_enabled = true
	fin_al.normal_texture = fin_pair[1]
	fin_al.normal_scale = 1.25
	fin_al.roughness = 0.28
	fin_al.metallic = 0.86
	_materials["heatsink_aluminum"] = fin_al

	# 19. Finned Copper Server Heatsink
	var fin_cu_pair := _gen_heatsink_fins_tex(128, Color(0.84, 0.48, 0.28))
	var fin_cu := StandardMaterial3D.new()
	fin_cu.albedo_texture = fin_cu_pair[0]
	fin_cu.normal_enabled = true
	fin_cu.normal_texture = fin_cu_pair[1]
	fin_cu.normal_scale = 1.25
	fin_cu.roughness = 0.26
	fin_cu.metallic = 0.88
	_materials["heatsink_copper"] = fin_cu

	# 20. Pure Hardware Metals: Brushed Copper, Gold PCIe/CPU Contacts, Nickel CPU IHS, Matte Silicon IC, Anti-Static ESD Mat
	_materials["copper_metal"] = make_brushed_metal(Color(0.85, 0.47, 0.26), 0.24, 0.90)
	_materials["gold_contacts"] = _simple(Color(0.92, 0.75, 0.26), 0.22, 0.94)
	_materials["cpu_ihs"] = make_brushed_metal(Color(0.78, 0.80, 0.83), 0.20, 0.88)
	_materials["galvanized_steel"] = make_brushed_metal(Color(0.64, 0.66, 0.69), 0.34, 0.78)
	_materials["ic_chip"] = _simple(Color(0.11, 0.11, 0.12), 0.42, 0.15)
	_materials["plastic_black"] = _simple(Color(0.13, 0.14, 0.15), 0.56, 0.04)
	_materials["esd_mat"] = _simple(Color(0.24, 0.36, 0.46), 0.78, 0.02)
	_materials["packing_foam"] = _simple(Color(0.20, 0.21, 0.23), 0.92, 0.0)


func _build_custom_shaders() -> void:
	# 1. Natural Realistic Day/Night Sky Shader (Soft Sunlight, Natural Clouds, Subtle Stars)
	var sky_sh := Shader.new()
	sky_sh.code = """
shader_type sky;

uniform vec3 sun_dir = vec3(0.3, 0.6, -0.5);
uniform float day_factor : hint_range(0.0, 1.0) = 0.8;
uniform float sunset_factor : hint_range(0.0, 1.0) = 0.0;
uniform float power_glow : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise2d(p);
		p *= 2.05;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, 0.0, 1.0);

	vec3 top_day = vec3(0.24, 0.48, 0.78);
	vec3 top_sunset = vec3(0.26, 0.26, 0.42);
	vec3 top_night = vec3(0.018, 0.028, 0.055);

	vec3 hor_day = vec3(0.72, 0.82, 0.90);
	vec3 hor_sunset = vec3(0.92, 0.56, 0.34);
	vec3 hor_night = vec3(0.05, 0.07, 0.12);

	vec3 top_col = mix(mix(top_night, top_day, day_factor), top_sunset, sunset_factor * 0.70);
	vec3 hor_col = mix(mix(hor_night, hor_day, day_factor), hor_sunset, sunset_factor * 0.82);
	vec3 col = mix(hor_col, top_col, pow(h, 0.55));

	if (dir.y < 0.0) {
		col = mix(hor_col * 0.60, vec3(0.12, 0.13, 0.14), clamp(-dir.y * 3.0, 0.0, 1.0));
	}

	vec3 sdir = normalize(sun_dir);
	float sun_dot = max(dot(dir, sdir), 0.0);
	float sun_disc = smoothstep(0.9988, 0.9996, sun_dot) * day_factor;
	float sun_halo = pow(sun_dot, 22.0) * 0.38 * (day_factor + sunset_factor * 0.6);
	vec3 sun_tint = mix(vec3(1.0, 0.97, 0.90), vec3(1.0, 0.62, 0.36), sunset_factor);
	col += sun_tint * (sun_disc * 2.2 + sun_halo);

	vec3 mdir = normalize(vec3(-sdir.x, max(abs(sdir.y), 0.32), -sdir.z));
	float night_vis = clamp(1.0 - day_factor * 1.4, 0.0, 1.0);
	float moon_dot = max(dot(dir, mdir), 0.0);
	float moon_disc = smoothstep(0.9990, 0.9997, moon_dot) * night_vis;
	float moon_halo = pow(moon_dot, 28.0) * 0.16 * night_vis;
	col += vec3(0.84, 0.88, 0.96) * (moon_disc * 1.5 + moon_halo);

	if (dir.y > 0.04 && night_vis > 0.05) {
		vec2 suv = dir.xz / (dir.y + 0.35) * 90.0;
		vec2 cell = floor(suv);
		vec2 local = fract(suv) - 0.5;
		float rnd = hash21(cell);
		if (rnd > 0.972) {
			float d = length(local);
			float twinkle = 0.70 + 0.30 * sin(TIME * (2.0 + rnd * 5.0) + rnd * 40.0);
			float star = smoothstep(0.15, 0.01, d) * twinkle * night_vis * smoothstep(0.04, 0.22, dir.y);
			col += vec3(0.90, 0.93, 0.98) * star * 1.1;
		}
	}

	if (dir.y > 0.02) {
		vec2 cuv = dir.xz / (dir.y + 0.22) * 1.45 + vec2(TIME * 0.012, TIME * 0.004);
		float n = fbm(cuv);
		float cloud_mask = smoothstep(0.50, 0.78, n) * smoothstep(0.02, 0.24, dir.y);
		vec3 cloud_day = mix(vec3(0.95, 0.96, 0.97), vec3(0.96, 0.76, 0.58), sunset_factor * 0.80);
		vec3 cloud_night = vec3(0.09, 0.11, 0.16);
		vec3 cloud_col = mix(cloud_night, cloud_day, day_factor);
		col = mix(col, cloud_col, cloud_mask * 0.70);
	}

	COLOR = col;
}
"""
	_sky_shader_mat = ShaderMaterial.new()
	_sky_shader_mat.shader = sky_sh

	# 2. Realistic Non-Neon Office IPS Monitor (Clean Server Admin Dashboard UI)
	var os_sh := Shader.new()
	os_sh.code = """
shader_type spatial;

uniform float power_on = 1.0;
uniform float alert_mode = 0.0;

void fragment() {
	vec2 uv = UV;
	// Realistic light-slate enterprise desktop UI (zero neon bloom!)
	vec3 bg = mix(vec3(0.88, 0.90, 0.92), vec3(0.32, 0.12, 0.12), alert_mode);
	vec3 header = mix(vec3(0.18, 0.24, 0.31), vec3(0.72, 0.16, 0.14), alert_mode);
	vec3 sidebar = vec3(0.22, 0.25, 0.29);
	vec3 card = vec3(0.96, 0.97, 0.98);
	vec3 chart_col = mix(vec3(0.16, 0.46, 0.74), vec3(0.82, 0.20, 0.16), alert_mode);
	vec3 ok_col = vec3(0.18, 0.62, 0.34);

	vec3 col = bg;
	// Top window title bar
	if (uv.y < 0.11) {
		col = header;
	} else if (uv.x < 0.22) {
		col = sidebar;
	} else if (uv.x > 0.26 && uv.x < 0.95 && uv.y > 0.16 && uv.y < 0.68) {
		col = card;
		// Subtle graph grid lines
		float gx = step(0.97, fract(uv.x * 14.0));
		float gy = step(0.96, fract(uv.y * 10.0));
		col = mix(col, vec3(0.84, 0.87, 0.90), max(gx, gy) * 0.6);
		// Live CPU/Network line chart
		float wy = 0.42 + 0.11 * sin(uv.x * 12.0 - TIME * 2.2) * cos(uv.x * 4.5 + TIME * 0.9);
		float wl = smoothstep(0.014, 0.004, abs(uv.y - wy));
		col = mix(col, chart_col, wl);
		float wy2 = 0.54 + 0.06 * sin(uv.x * 16.0 - TIME * 3.1);
		float wl2 = smoothstep(0.011, 0.003, abs(uv.y - wy2));
		col = mix(col, ok_col, wl2);
	} else if (uv.x > 0.26 && uv.x < 0.95 && uv.y > 0.73 && uv.y < 0.93) {
		col = card;
		float idx = floor((uv.x - 0.26) * 10.0);
		float bx = fract((uv.x - 0.26) * 10.0);
		float h = 0.35 + 0.50 * abs(sin(idx * 1.7 + TIME * 1.1));
		if (bx > 0.20 && bx < 0.80 && (0.91 - uv.y) / 0.16 < h) {
			col = mix(col, chart_col, 0.85);
		}
	}

	col *= mix(0.06, 1.0, power_on);
	ALBEDO = col;
	EMISSION = col * mix(0.02, 0.48, power_on);
	ROUGHNESS = 0.28;
	METALLIC = 0.04;
}
"""
	_os_screen_mat = ShaderMaterial.new()
	_os_screen_mat.shader = os_sh

	# 3. Realistic Secondary Linux Server Console / htop Telemetry LCD
	var tel_sh := Shader.new()
	tel_sh.code = """
shader_type spatial;

uniform float power_on = 1.0;
uniform float heat_warn = 0.0;

void fragment() {
	vec2 uv = UV;
	vec3 bg = vec3(0.09, 0.10, 0.11);
	vec3 text_c = mix(vec3(0.68, 0.78, 0.70), vec3(0.90, 0.56, 0.24), heat_warn);
	vec3 bar_c = mix(vec3(0.28, 0.66, 0.38), vec3(0.86, 0.40, 0.16), heat_warn);

	vec3 col = bg;
	if (uv.y < 0.56) {
		float row = floor((uv.y + TIME * 0.08) * 14.0);
		float rfrac = fract((uv.y + TIME * 0.08) * 14.0);
		float len = 0.22 + 0.64 * fract(sin(row * 91.7) * 43758.5);
		if (uv.x > 0.07 && uv.x < len && rfrac > 0.28 && rfrac < 0.68) {
			col = mix(col, text_c, 0.85);
		}
	} else {
		float col_i = floor(uv.x * 10.0);
		float cx = fract(uv.x * 10.0);
		float bh = 0.25 + 0.62 * abs(sin(col_i * 2.1 + TIME * 1.3));
		float norm_y = (0.93 - uv.y) / 0.34;
		if (cx > 0.22 && cx < 0.78 && norm_y > 0.0 && norm_y < bh) {
			col = mix(col, bar_c, 0.9);
		}
	}

	col *= mix(0.05, 1.0, power_on);
	ALBEDO = col;
	EMISSION = col * mix(0.02, 0.42, power_on);
	ROUGHNESS = 0.30;
	METALLIC = 0.04;
}
"""
	_telemetry_screen_mat = ShaderMaterial.new()
	_telemetry_screen_mat.shader = tel_sh


# ==============================================================================
# CRISP REALISTIC PROCEDURAL PBR TEXTURE GENERATORS
# ==============================================================================

func _gen_tiled_concrete(size: int) -> Array:
	var n := _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 4, 101)
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var tile := size / 2
	for y in range(size):
		for x in range(size):
			var v := (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var gx := x % tile
			var gy := y % tile
			var is_seam := (gx <= 2 or gy <= 2)
			var base := lerpf(0.46, 0.58, v)
			if is_seam:
				base *= 0.62
			# Warm natural garage concrete (zero blue cast)
			alb.set_pixel(x, y, Color(base * 1.01, base * 1.0, base * 0.97))
			var hv := 0.24 if is_seam else lerpf(0.52, 0.78, v)
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 2.0)]


func _gen_raised_floor_tiles(size: int, col_a: Color, col_b: Color, grout_col: Color) -> Array:
	var n := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.14, 3, 202)
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var tile := size / 4
	for y in range(size):
		for x in range(size):
			var v := (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var gx := x % tile
			var gy := y % tile
			var is_grout := (gx <= 1 or gy <= 1)
			var c := grout_col if is_grout else col_a.lerp(col_b, v)
			alb.set_pixel(x, y, c)
			var hv := 0.20 if is_grout else lerpf(0.68, 0.80, v)
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 1.8)]


func _gen_pcb_tex(size: int, base_col: Color, trace_col: Color, pad_col: Color) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	for y in range(size):
		for x in range(size):
			var c := base_col
			var hv := 0.45
			# Fine horizontal & vertical PCB copper trace buses
			var hx := x % 16
			var hy := y % 16
			var diag := (x + y) % 32
			if hx == 2 or hy == 4 or (diag == 6 and ((x / 16) % 2 == 0)):
				c = trace_col
				hv = 0.72
			# Gold solder via pads at grid intersections
			var vx := (x % 32) - 16
			var vy := (y % 32) - 16
			var d2 := vx * vx + vy * vy
			if d2 <= 5:
				c = pad_col
				hv = 0.92
			elif d2 <= 10:
				c = base_col.darkened(0.25)
				hv = 0.25
			alb.set_pixel(x, y, c)
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 2.4)]


func _gen_heatsink_fins_tex(size: int, metal_col: Color) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	for y in range(size):
		for x in range(size):
			var fin := (x % 8) < 4
			var c := metal_col if fin else metal_col.darkened(0.62)
			var hv := 0.92 if fin else 0.14
			alb.set_pixel(x, y, c)
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 3.2)]


func _gen_brushed_metal_tex(size: int) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var n := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.35, 2, 505)
	for y in range(size):
		var streak := (n.get_noise_2d(0.0, float(y) * 2.5) + 1.0) * 0.5
		for x in range(size):
			var micro := (n.get_noise_2d(float(x) * 0.25, float(y) * 2.5) + 1.0) * 0.5
			var v := lerpf(0.48, 0.72, streak * 0.65 + micro * 0.35)
			alb.set_pixel(x, y, Color(v, v, v))
			hgt.set_pixel(x, y, Color(v, v, v))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 1.4)]


func _gen_perforated_mesh_tex(size: int) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var cell := 16
	for y in range(size):
		for x in range(size):
			var row := y / cell
			var ox := (x + (row % 2) * (cell / 2)) % cell
			var oy := y % cell
			var dx := (float(ox) - float(cell) * 0.5) / (float(cell) * 0.5)
			var dy := (float(oy) - float(cell) * 0.5) / (float(cell) * 0.5)
			var dist := sqrt(dx * dx + dy * dy)
			if dist < 0.62:
				alb.set_pixel(x, y, Color(0.04, 0.04, 0.05))
				hgt.set_pixel(x, y, Color(0.10, 0.10, 0.10))
			else:
				alb.set_pixel(x, y, Color(0.24, 0.25, 0.27))
				hgt.set_pixel(x, y, Color(0.85, 0.85, 0.85))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 3.0)]


func _gen_hazard_stripes_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var yellow := Color(0.82, 0.64, 0.14)
	var dark := Color(0.14, 0.14, 0.15)
	for y in range(size):
		for x in range(size):
			var band := ((x + y) / 24) % 2
			img.set_pixel(x, y, yellow if band == 0 else dark)
	return ImageTexture.create_from_image(img)


func _gen_corrugated_tex(size: int) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	for y in range(size):
		var wave := 0.5 + 0.5 * sin(float(y) / float(size) * TAU * 8.0)
		var shade := lerpf(0.46, 0.62, wave)
		for x in range(size):
			alb.set_pixel(x, y, Color(shade, shade, shade))
			hgt.set_pixel(x, y, Color(wave, wave, wave))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 2.6)]


func _gen_brick_tex(size: int) -> Array:
	var n := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.12, 3, 777)
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var bh := 32
	var bw := 64
	for y in range(size):
		var row := y / bh
		var ly := y % bh
		for x in range(size):
			var sx := (x + (row % 2) * (bw / 2)) % size
			var lx := sx % bw
			var is_mortar := (lx < 3 or ly < 3)
			var nv := (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			if is_mortar:
				alb.set_pixel(x, y, Color(0.58, 0.56, 0.52))
				hgt.set_pixel(x, y, Color(0.20, 0.20, 0.20))
			else:
				var br := lerpf(0.44, 0.58, nv)
				alb.set_pixel(x, y, Color(br * 1.12, br * 0.64, br * 0.48))
				var hv := lerpf(0.72, 0.88, nv)
				hgt.set_pixel(x, y, Color(hv, hv, hv))
	return [ImageTexture.create_from_image(alb), _height_to_normal(hgt, 2.6)]


func _height_to_normal(hgt: Image, strength: float) -> ImageTexture:
	var w := hgt.get_width()
	var h := hgt.get_height()
	var norm := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		var ym := (y - 1 + h) % h
		var yp := (y + 1) % h
		for x in range(w):
			var xm := (x - 1 + w) % w
			var xp := (x + 1) % w
			var hl := hgt.get_pixel(xm, y).r
			var hr := hgt.get_pixel(xp, y).r
			var hu := hgt.get_pixel(x, ym).r
			var hd := hgt.get_pixel(x, yp).r
			var v := Vector3((hl - hr) * strength, (hu - hd) * strength, 1.0).normalized()
			norm.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5))
	return ImageTexture.create_from_image(norm)


func _make_noise(noise_type: int, freq: float, octaves: int, seed_val: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = noise_type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed_val
	return n


func _make_noise_tex(noise: FastNoiseLite, size: int, col_a: Color, col_b: Color) -> NoiseTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, col_a)
	grad.set_color(1, col_b)
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	return tex


func _make_normal_tex(noise: FastNoiseLite, size: int, bump: float) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = bump
	tex.noise = noise
	return tex


func _simple(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
