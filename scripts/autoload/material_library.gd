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
# Texturen, die schon mit Mipmaps aus _cached_textures kommen. _finalize_textures überspringt sie,
# statt ihr Bild erneut von der Grafikkarte zurückzulesen.
var _mipmapped: Dictionary = {}

# Fertig erzeugte Wandtexturen werden hier zwischengespeichert, damit nur der erste Start rechnen muss.
# WALL_TEX_VERSION erhöhen, wenn sich Farben oder Aufbau der Wandtextur ändern.
const WALL_TEX_CACHE_DIR := "user://tex_cache"
const WALL_TEX_VERSION := 1
# Gleiches Prinzip für Böden, Ziegel und Wellblech. Erhöhen, wenn sich deren Aufbau oder Farben ändern.
const SURFACE_TEX_VERSION := 1
# Gleiches Prinzip für Platinen, Kühlkörper, gebürstetes Metall, Lochblech und Warnstreifen.
const GEN_TEX_VERSION := 1
# Version der Platinen-Textur (_gen_pcb_tex). Erhöhen, wenn sich die Funktion ändert.
const PCB_TEX_VERSION := 3


func _ready() -> void:
	_build_all_materials()
	_finalize_textures()
	_build_custom_shaders()


## Gibt allen Bildtexturen Mipmaps und schaltet anisotrope Filterung ein.
## Ohne Mipmaps flimmern Böden und Wände in der Ferne, und die Anisotropie-Einstellung im Menü wirkt gar nicht.
func _finalize_textures() -> void:
	var done: Dictionary = {}
	for key in _materials:
		var m := _materials[key] as BaseMaterial3D
		if m == null:
			continue
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.albedo_texture = _with_mipmaps(m.albedo_texture, false, done)
		if m.normal_enabled:
			m.normal_texture = _with_mipmaps(m.normal_texture, true, done)
	_mipmapped.clear()


func _with_mipmaps(tex: Texture2D, is_normal: bool, done: Dictionary) -> Texture2D:
	if not (tex is ImageTexture):
		return tex
	if _mipmapped.has(tex):
		return tex
	if done.has(tex):
		return done[tex] as Texture2D
	var img := tex.get_image()
	if img == null or img.is_empty() or img.is_compressed() or img.has_mipmaps():
		done[tex] = tex
		return tex
	img.generate_mipmaps(is_normal)
	var out := ImageTexture.create_from_image(img)
	done[tex] = out
	return out


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
	var conc_pair := _cached_tex_pair("concrete_floor", 1024, _render_concrete)
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
	var epoxy_pair := _cached_tex_pair("raised_floor_b", 1024, _render_raised_floor.bind(Color(0.45, 0.47, 0.49), Color(0.52, 0.54, 0.56), Color(0.24, 0.26, 0.28)))
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

	# 3. Clean Bright Enterprise Raised Datacenter Floor (Hall C — hyperscale style)
	var ent_pair := _cached_tex_pair("raised_floor_c", 1024, _render_raised_floor.bind(Color(0.68, 0.70, 0.72), Color(0.75, 0.77, 0.79), Color(0.36, 0.38, 0.41)))
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
	# Gestrichene Betonsteinwand im Läuferverband: 1024 px pro 1,6 m Kachel (~640 px/m statt ~115 px/m vorher).
	var wall_set := _gen_block_wall_set(1024,
		Color(0.76, 0.75, 0.72), Color(0.83, 0.82, 0.79),
		Color(0.39, 0.41, 0.43), Color(0.45, 0.47, 0.50))
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_texture = wall_set[0]
	wall_mat.normal_enabled = true
	wall_mat.normal_texture = wall_set[2]
	wall_mat.normal_scale = 0.85
	wall_mat.roughness = 0.84
	wall_mat.uv1_triplanar = true
	# Weltkoordinaten: Steinreihen laufen über alle Wandstücke durch und beginnen am Boden.
	wall_mat.uv1_world_triplanar = true
	wall_mat.uv1_triplanar_sharpness = 4.0
	wall_mat.uv1_scale = Vector3(0.625, 0.625, 0.625)
	_materials["garage_wall"] = wall_mat

	# 5. Realistic Industrial Medium-Grey Lower Wall Paint (Wainscoting)
	var wain_mat := wall_mat.duplicate() as StandardMaterial3D
	wain_mat.albedo_texture = wall_set[1]
	wain_mat.roughness = 0.72
	wain_mat.metallic = 0.04
	_materials["wainscot_wall"] = wain_mat

	# 6. Brushed Anodized Server Steel & Galvanized Chassis Metal
	var steel_pair := _cached_textures("brushed_metal_g%d_128" % GEN_TEX_VERSION, _gen_brushed_metal_tex.bind(128), [false, true])
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
	var perf_pair := _cached_textures("perforated_mesh_g%d_128" % GEN_TEX_VERSION, _gen_perforated_mesh_tex.bind(128), [false, true])
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
	var haz_tex: Texture2D = _cached_textures("hazard_stripes_g%d_512" % GEN_TEX_VERSION, func() -> Array: return [_gen_hazard_stripes_tex(512)], [false])[0]
	var haz_mat := StandardMaterial3D.new()
	haz_mat.albedo_texture = haz_tex
	haz_mat.roughness = 0.62
	haz_mat.metallic = 0.06
	haz_mat.uv1_triplanar = true
	haz_mat.uv1_scale = Vector3(0.85, 0.85, 0.85)
	_materials["hazard_stripes"] = haz_mat

	# 9. Corrugated Galvanized Steel (Garage Door & Expansion Partitions)
	var corr_pair := _cached_tex_pair("corrugated", 512, _render_corrugated)
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
	var brick_pair := _cached_tex_pair("exterior_brick", 1024, _render_brick)
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
	# Rauschtexturen: 4-fache Auflösung, Frequenz durch 4 (gleiche Grobstruktur) und 2 Oktaven mehr für feine Details.
	# Bump × 3, weil die Höhenunterschiede pro Pixel bei höherer Auflösung kleiner werden.
	var wood_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.0125, 6, 606)
	var wood_tex := _make_noise_tex(wood_noise, 1024, Color(0.42, 0.29, 0.17), Color(0.60, 0.44, 0.28))
	var wood_norm := _make_normal_tex(wood_noise, 1024, 2.7)
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
	var card_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.04, 5, 707)
	var card_tex := _make_noise_tex(card_noise, 512, Color(0.60, 0.47, 0.32), Color(0.72, 0.58, 0.41))
	var card_norm := _make_normal_tex(card_noise, 512, 3.0)
	var card_mat := StandardMaterial3D.new()
	card_mat.albedo_texture = card_tex
	card_mat.normal_enabled = true
	card_mat.normal_texture = card_norm
	card_mat.normal_scale = 0.34
	card_mat.roughness = 0.88
	_materials["cardboard"] = card_mat

	# 13. Exterior Asphalt Driveway / Road
	var asp_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.0625, 6, 808)
	var asp_tex := _make_noise_tex(asp_noise, 1024, Color(0.24, 0.24, 0.25), Color(0.35, 0.35, 0.36))
	var asp_norm := _make_normal_tex(asp_noise, 1024, 6.6)
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
	var grass_noise := _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.03, 6, 909)
	var grass_tex := _make_noise_tex(grass_noise, 1024, Color(0.22, 0.36, 0.16), Color(0.34, 0.48, 0.22))
	var grass_norm := _make_normal_tex(grass_noise, 1024, 4.5)
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
	var pcb_g_pair := _cached_textures("pcb_green_p%d_1024" % PCB_TEX_VERSION, _gen_pcb_tex.bind(1024, Color(0.06, 0.26, 0.14), Color(0.11, 0.36, 0.20), Color(0.76, 0.64, 0.26)), [false, true])
	var pcb_g := StandardMaterial3D.new()
	pcb_g.albedo_texture = pcb_g_pair[0]
	pcb_g.normal_enabled = true
	pcb_g.normal_texture = pcb_g_pair[1]
	pcb_g.normal_scale = 0.85
	pcb_g.roughness = 0.36
	pcb_g.metallic = 0.18
	_materials["pcb_green"] = pcb_g

	# 17. Matte-Black Workstation/GPU PCB (with metallic dark-gold circuit paths!)
	var pcb_b_pair := _cached_textures("pcb_black_p%d_1024" % PCB_TEX_VERSION, _gen_pcb_tex.bind(1024, Color(0.08, 0.09, 0.10), Color(0.14, 0.15, 0.17), Color(0.62, 0.52, 0.28)), [false, true])
	var pcb_b := StandardMaterial3D.new()
	pcb_b.albedo_texture = pcb_b_pair[0]
	pcb_b.normal_enabled = true
	pcb_b.normal_texture = pcb_b_pair[1]
	pcb_b.normal_scale = 0.85
	pcb_b.roughness = 0.40
	pcb_b.metallic = 0.22
	_materials["pcb_black"] = pcb_b

	# 18. Finned Aluminum Heatsink (ribbed cooling fins + normal map)
	var fin_pair := _cached_textures("heatsink_aluminum_g%d_128" % GEN_TEX_VERSION, _gen_heatsink_fins_tex.bind(128, Color(0.72, 0.74, 0.77)), [false, true])
	var fin_al := StandardMaterial3D.new()
	fin_al.albedo_texture = fin_pair[0]
	fin_al.normal_enabled = true
	fin_al.normal_texture = fin_pair[1]
	fin_al.normal_scale = 1.25
	fin_al.roughness = 0.28
	fin_al.metallic = 0.86
	_materials["heatsink_aluminum"] = fin_al

	# 19. Finned Copper Server Heatsink
	var fin_cu_pair := _cached_textures("heatsink_copper_g%d_128" % GEN_TEX_VERSION, _gen_heatsink_fins_tex.bind(128, Color(0.84, 0.48, 0.28)), [false, true])
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
	# 1. AAA Raymarched Volumetric Clouds + Atmospheric Day/Night Sky Shader
	var sky_sh := Shader.new()
	sky_sh.code = """
shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 sun_dir = vec3(0.3, 0.6, -0.5);
uniform float day_factor : hint_range(0.0, 1.0) = 0.8;
uniform float sunset_factor : hint_range(0.0, 1.0) = 0.0;
uniform float power_glow : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform bool half_clouds = true;
// Niedrige Grafikstufen: eine flache Wolkenschicht statt der Volumenwolken (ein paar Rauschwerte je Pixel).
uniform bool cheap_clouds = false;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

float fbm3d(vec3 p) {
	float v = 0.0;
	float amp = 0.52;
	for (int i = 0; i < 4; i++) {
		v += amp * noise3d(p);
		p = p * 2.04 + vec3(13.7, 7.1, 19.3);
		amp *= 0.48;
	}
	return v;
}

float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * 3.14159265 * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.001), 1.5));
}

// 3D volumetric cloud density in normalized altitude layer y in [0.0, 1.0]
float sample_cloud_density(vec3 p, float height_frac, float coverage) {
	// Cumulus vertical profile: crisp flat base, billowing rounded top
	float h_profile = smoothstep(0.0, 0.18, height_frac) * smoothstep(1.0, 0.58, height_frac);
	if (h_profile <= 0.001) {
		return 0.0;
	}
	vec3 wind = vec3(TIME * 0.018, 0.0, TIME * 0.007);
	vec3 q = p * 0.00055 + wind;
	float threshold = mix(0.66, 0.34, coverage);
	// Genaue Abkürzung: Reicht es nach zwei Oktaven selbst mit dem Höchstwert der übrigen (0.178) nicht, ist hier Himmel.
	float need = (threshold * 0.62 / h_profile - 0.2084) / 0.78;
	float base_shape = 0.52 * noise3d(q);
	vec3 q1 = q * 2.04 + vec3(13.7, 7.1, 19.3);
	base_shape += 0.2496 * noise3d(q1);
	if (base_shape + 0.1774 <= need) {
		return 0.0;
	}
	q1 = q1 * 2.04 + vec3(13.7, 7.1, 19.3);
	base_shape += 0.119808 * noise3d(q1);
	q1 = q1 * 2.04 + vec3(13.7, 7.1, 19.3);
	base_shape += 0.05750784 * noise3d(q1);
	// Auch mit größtmöglichem Detail (0.947) bliebe es leer: Detail gar nicht erst rechnen.
	if ((base_shape * 0.78 + 0.2084) * h_profile <= threshold * 0.62) {
		return 0.0;
	}
	// Billowy high-frequency erosion along upper edges
	float detail = fbm3d(q * 2.85 - wind * 1.4 + vec3(4.2, height_frac * 1.5, 9.1));
	float d = (base_shape * 0.78 + detail * 0.22) * h_profile;
	d = smoothstep(threshold * 0.62, threshold * 0.62 + 0.30, d);
	// Carve crisp wispy edges with detail noise
	d = max(d - (1.0 - detail) * 0.24 * smoothstep(0.25, 0.95, height_frac), 0.0);
	return d;
}

// Volumetrische Wolken (Beer-Lambert + Dual-Lobe HG Scattering): Farbe und Deckung
vec4 march_clouds(vec3 dir, vec3 sdir, vec3 mdir, float sun_raw, vec3 hor_col) {
	vec4 cloud_out = vec4(0.0);
	if (dir.y > 0.015) {
		// Virtual curved atmosphere slab: base = 1350m, top = 3150m
		float elev = max(dir.y, 0.045);
		float t_bot = 1350.0 / elev;
		float t_top = 3150.0 / elev;
		float march_dist = min(t_top - t_bot, 7500.0);

		const int STEPS = 20;
		float step_len = march_dist / float(STEPS);

		// Subtle blue-noise-like jitter to eliminate raymarching banding
		float jitter = hash21(dir.xz * 713.3 + vec2(dir.y * 211.7));
		float t = t_bot + step_len * jitter;

		float transmittance = 1.0;
		vec3 light_energy = vec3(0.0);

		// Dual-lobe Henyey-Greenstein phase for realistic silver lining & soft back-scatter
		float phase_fwd = hg_phase(sun_raw, 0.68);
		float phase_back = hg_phase(sun_raw, -0.25);
		float phase = mix(phase_back, phase_fwd, 0.72) * 3.8 + 0.35;

		vec3 sun_col = mix(vec3(1.06, 1.02, 0.96), vec3(1.15, 0.62, 0.34), sunset_factor);
		sun_col *= mix(1.0, 0.42, cloud_darkness);
		vec3 amb_top = mix(vec3(0.08, 0.11, 0.18), mix(vec3(0.56, 0.68, 0.86), vec3(0.76, 0.50, 0.44), sunset_factor * 0.7), day_factor);
		vec3 amb_bot = mix(vec3(0.03, 0.04, 0.07), mix(vec3(0.32, 0.38, 0.48), vec3(0.36, 0.25, 0.30), sunset_factor * 0.7), day_factor);
		amb_top *= mix(1.0, 0.55, cloud_darkness);
		amb_bot *= mix(1.0, 0.45, cloud_darkness);

		vec3 light_dir = (day_factor > 0.12) ? sdir : mdir;
		vec3 direct_light = mix(vec3(0.18, 0.22, 0.32), sun_col, smoothstep(0.05, 0.35, day_factor));

		for (int i = 0; i < STEPS; i++) {
			if (transmittance < 0.025) {
				break;
			}
			vec3 pos = dir * t;
			float h_frac = clamp((pos.y - 1350.0) / 1800.0, 0.0, 1.0);
			float dens = sample_cloud_density(pos, h_frac, cloud_coverage);

			if (dens > 0.008) {
				// 4-step shadow raymarch toward sun/moon for crisp 3D self-shadowing
				float shadow_od = 0.0;
				vec3 sp = pos;
				float s_step = 260.0;
				for (int s = 0; s < 4; s++) {
					sp += light_dir * s_step;
					float sh_frac = clamp((sp.y - 1350.0) / 1800.0, 0.0, 1.0);
					shadow_od += sample_cloud_density(sp, sh_frac, cloud_coverage) * s_step * 0.0014;
					s_step *= 1.45;
				}
				// Beer-Lambert + multi-scattering approximation + powder effect
				float beer = exp(-shadow_od * 1.85);
				float multi_scatter = exp(-shadow_od * 0.42) * 0.55;
				float powder = 1.0 - exp(-dens * 3.5);
				float sun_atten = max(beer, multi_scatter) * (0.55 + 0.45 * powder);

				vec3 ambient = mix(amb_bot, amb_top, clamp(h_frac * 1.15, 0.0, 1.0));
				vec3 sample_col = ambient + direct_light * sun_atten * phase;

				float sigma = dens * step_len * 0.00165;
				float step_trans = exp(-sigma);
				light_energy += transmittance * (1.0 - step_trans) * sample_col;
				transmittance *= step_trans;
			}
			t += step_len;
		}

		// Aerial perspective fade near the horizon so distant volumetric clouds blend naturally
		float horizon_fade = smoothstep(0.015, 0.16, dir.y);
		float cloud_alpha = (1.0 - transmittance) * horizon_fade;
		vec3 final_cloud = light_energy / max(1.0 - transmittance, 0.001);
		final_cloud = mix(hor_col, final_cloud, smoothstep(0.015, 0.22, dir.y));
		cloud_out = vec4(final_cloud, clamp(cloud_alpha, 0.0, 0.96));
	}
	return cloud_out;
}

// Flache Wolkenschicht: dieselbe Form und Bewegung wie die Volumenwolken, aber nur eine Ebene in
// mittlerer Höhe, ohne Strahlverfolgung und Eigenschatten.
vec4 flat_clouds(vec3 dir, float sun_raw, vec3 hor_col) {
	if (dir.y <= 0.015) {
		return vec4(0.0);
	}
	float elev = max(dir.y, 0.045);
	vec3 p = dir * (2250.0 / elev);
	vec3 wind = vec3(TIME * 0.018, 0.0, TIME * 0.007);
	vec3 q = p * 0.00055 + wind;
	float base_shape = 0.52 * noise3d(q);
	vec3 q1 = q * 2.04 + vec3(13.7, 7.1, 19.3);
	base_shape += 0.2496 * noise3d(q1);
	q1 = q1 * 2.04 + vec3(13.7, 7.1, 19.3);
	base_shape += 0.119808 * noise3d(q1);
	float threshold = mix(0.66, 0.34, cloud_coverage);
	float d = smoothstep(threshold * 0.62, threshold * 0.62 + 0.26, base_shape * 0.78 + 0.15);

	vec3 sun_col = mix(vec3(1.06, 1.02, 0.96), vec3(1.15, 0.62, 0.34), sunset_factor) * mix(1.0, 0.42, cloud_darkness);
	vec3 amb = mix(vec3(0.08, 0.11, 0.18), mix(vec3(0.56, 0.68, 0.86), vec3(0.76, 0.50, 0.44), sunset_factor * 0.7), day_factor);
	amb *= mix(1.0, 0.55, cloud_darkness);
	vec3 direct = mix(vec3(0.18, 0.22, 0.32), sun_col, smoothstep(0.05, 0.35, day_factor));
	float silver = pow(max(sun_raw, 0.0), 6.0) * 0.55;
	vec3 c = amb * 0.78 + direct * (0.56 - 0.30 * d + silver);
	c = mix(hor_col, c, smoothstep(0.015, 0.22, dir.y));
	float a = (1.0 - exp(-d * 3.2)) * smoothstep(0.015, 0.16, dir.y);
	return vec4(c, clamp(a, 0.0, 0.94));
}

vec4 clouds(vec3 dir, vec3 sdir, vec3 mdir, float sun_raw, vec3 hor_col) {
	if (cheap_clouds) {
		return flat_clouds(dir, sun_raw, hor_col);
	}
	return march_clouds(dir, sdir, mdir, sun_raw, hor_col);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, 0.0, 1.0);

	vec3 top_day = vec3(0.11, 0.31, 0.68);
	vec3 mid_day = vec3(0.32, 0.55, 0.84);
	vec3 hor_day = vec3(0.75, 0.85, 0.94);

	vec3 top_sunset = vec3(0.22, 0.22, 0.40);
	vec3 hor_sunset = vec3(0.95, 0.54, 0.30);

	vec3 top_night = vec3(0.016, 0.026, 0.054);
	vec3 hor_night = vec3(0.045, 0.068, 0.12);

	vec3 top_col = mix(mix(top_night, top_day, day_factor), top_sunset, sunset_factor * 0.72);
	vec3 mid_col = mix(mix(top_night * 1.35, mid_day, day_factor), mix(top_sunset, hor_sunset, 0.45), sunset_factor * 0.76);
	vec3 hor_col = mix(mix(hor_night, hor_day, day_factor), hor_sunset, sunset_factor * 0.85);

	// Weather overcast desaturation
	vec3 storm_sky = mix(vec3(0.06, 0.08, 0.11), vec3(0.42, 0.47, 0.54), day_factor);
	top_col = mix(top_col, storm_sky * 0.85, cloud_darkness * 0.55);
	mid_col = mix(mid_col, storm_sky, cloud_darkness * 0.55);
	hor_col = mix(hor_col, storm_sky * 1.15, cloud_darkness * 0.55);

	vec3 col = mix(hor_col, mid_col, smoothstep(0.0, 0.26, h));
	col = mix(col, top_col, smoothstep(0.20, 0.94, h));

	vec3 sdir = normalize(sun_dir);
	float sun_raw = dot(dir, sdir);
	float sun_dot = max(sun_raw, 0.0);
	vec3 sun_tint = mix(vec3(1.0, 0.96, 0.88), vec3(1.0, 0.58, 0.30), sunset_factor);

	if (dir.y < 0.0) {
		vec3 ground_col = mix(vec3(0.02, 0.025, 0.03), vec3(0.22, 0.27, 0.21), day_factor);
		col = mix(hor_col * 0.85, ground_col, clamp(-dir.y * 4.0, 0.0, 1.0));
	}

	// Atmospheric Mie glow + Sun disc
	float mie = pow(sun_dot, 5.0) * (1.0 - h) * 0.30 * (day_factor + sunset_factor) * (1.0 - cloud_darkness * 0.6);
	col += sun_tint * mie;

	float sun_disc = smoothstep(0.9988, 0.9996, sun_dot) * day_factor * (1.0 - cloud_darkness * 0.75);
	float sun_halo = pow(sun_dot, 22.0) * 0.36 * (day_factor + sunset_factor * 0.6) * (1.0 - cloud_darkness * 0.55);
	sun_halo += pow(sun_dot, 180.0) * 0.55 * day_factor * (1.0 - cloud_darkness * 0.7);
	col += sun_tint * (sun_disc * 2.4 + sun_halo);

	// Moon + twinkling stars at night
	vec3 mdir = normalize(vec3(-sdir.x, max(abs(sdir.y), 0.32), -sdir.z));
	float night_vis = clamp(1.0 - day_factor * 1.4, 0.0, 1.0);
	float moon_dot = max(dot(dir, mdir), 0.0);
	float moon_disc = smoothstep(0.9990, 0.9997, moon_dot) * night_vis;
	float moon_halo = pow(moon_dot, 28.0) * 0.16 * night_vis;
	col += vec3(0.84, 0.89, 0.98) * (moon_disc * 1.6 + moon_halo);

	if (dir.y > 0.04 && night_vis > 0.05) {
		vec2 suv = dir.xz / (dir.y + 0.35) * 90.0;
		vec2 cell = floor(suv);
		vec2 local = fract(suv) - 0.5;
		float rnd = hash21(cell);
		if (rnd > 0.972) {
			float d = length(local);
			float twinkle = 0.70 + 0.30 * sin(TIME * (2.0 + rnd * 5.0) + rnd * 40.0);
			float star = smoothstep(0.15, 0.01, d) * twinkle * night_vis * smoothstep(0.04, 0.22, dir.y);
			col += vec3(0.90, 0.94, 1.0) * star * 1.1;
		}
	}

	// Draußen laufen die Wolken in einem gröberen Durchgang (weich, kaum Unterschied), drinnen nur für
	// die wenigen sichtbaren Himmelspixel in voller Auflösung. Sonne, Mond und Sterne bleiben immer voll scharf.
	if (AT_QUARTER_RES_PASS) {
		vec4 c = vec4(0.0);
		if (half_clouds) {
			c = clouds(dir, sdir, mdir, sun_raw, hor_col);
		}
		COLOR = c.rgb * c.a;
		ALPHA = c.a;
	} else {
	if (half_clouds) {
		col = col * (1.0 - QUARTER_RES_COLOR.a) + QUARTER_RES_COLOR.rgb;
	} else {
		vec4 c = clouds(dir, sdir, mdir, sun_raw, hor_col);
		col = mix(col, c.rgb, c.a);
	}

	// Horizon haze blending seamlessly into distant treeline
	float haze = exp(-max(dir.y, 0.0) * 15.0) * step(0.0, dir.y);
	col = mix(col, hor_col, haze * 0.42);

	COLOR = col;
	}
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

## Lädt [Albedo, Normal-Map] für `key` aus user://tex_cache oder rechnet sie einmal mit `render(size)` und speichert sie.
## `render` muss [Albedo-Image RGB8, Normal-Image] liefern. Rückgabe: zwei ImageTextures mit Mipmaps.
func _cached_tex_pair(key: String, size: int, render: Callable) -> Array:
	var cache_key := "%s_v%d_%d" % [key, SURFACE_TEX_VERSION, size]
	return _cached_textures(cache_key, func() -> Array: return render.call(size), [false, true])


## Lädt Texturen für `key` als fertige Images mit Mipmaps aus user://tex_cache (.res) oder rechnet sie
## einmal mit `render` und speichert sie. `render` liefert ein Array aus Image oder ImageTexture,
## `normal_flags[i]` gibt an, ob Eintrag i eine Normal-Map ist. Rückgabe: ImageTextures mit Mipmaps.
## Grund: PNG entpacken und Mipmaps rechnen kostete bei jedem Start ~314 ms (gemessen).
func _cached_textures(key: String, render: Callable, normal_flags: Array) -> Array:
	var count := normal_flags.size()
	var paths: PackedStringArray = []
	for i in range(count):
		paths.append("%s/%s_%d.res" % [WALL_TEX_CACHE_DIR, key, i])

	var imgs: Array = []
	for p in paths:
		if not ResourceLoader.exists(p):
			imgs.clear()
			break
		var res := ResourceLoader.load(p, "Image", ResourceLoader.CACHE_MODE_IGNORE)
		if not (res is Image) or (res as Image).is_empty() or not (res as Image).has_mipmaps():
			imgs.clear()
			break
		imgs.append(res)

	if imgs.size() != count:
		imgs = _images_with_mipmaps(render.call(), normal_flags)
		DirAccess.make_dir_recursive_absolute(WALL_TEX_CACHE_DIR)
		for i in range(count):
			if imgs[i] == null:
				continue
			var err := ResourceSaver.save(imgs[i] as Image, paths[i])
			if err != OK:
				push_warning("Textur konnte nicht gecacht werden: %s (Fehler %d)" % [paths[i], err])

	var out: Array = []
	for img in imgs:
		if img == null:
			out.append(null)
			continue
		var tex := ImageTexture.create_from_image(img as Image)
		_mipmapped[tex] = true
		out.append(tex)
	return out


func _images_with_mipmaps(raw: Variant, normal_flags: Array) -> Array:
	var items: Array = raw if raw is Array else []
	var imgs: Array = []
	for i in range(normal_flags.size()):
		var item: Variant = items[i] if i < items.size() else null
		var img: Image = null
		if item is Image:
			img = item as Image
		elif item is Texture2D:
			img = (item as Texture2D).get_image()
		if img == null or img.is_empty():
			push_warning("Texturgenerator lieferte für Eintrag %d kein Bild" % i)
			imgs.append(null)
			continue
		if not img.is_compressed() and not img.has_mipmaps():
			img.generate_mipmaps(bool(normal_flags[i]))
		imgs.append(img)
	return imgs


## Kachelbares Rauschen als Graustufen-Bytes (0..255), nativ erzeugt statt per get_noise_2d pro Pixel.
func _noise_l8(noise_type: int, freq: float, octaves: int, seed_val: int, size: int) -> PackedByteArray:
	var img := _make_noise(noise_type, freq, octaves, seed_val).get_seamless_image(size, size)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


func _finish_pair(size: int, alb: PackedByteArray, hg: PackedByteArray, bump: float) -> Array:
	var alb_img := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, alb)
	var nrm_img := Image.create_from_data(size, size, false, Image.FORMAT_L8, hg)
	nrm_img.bump_map_to_normal_map(bump)
	return [alb_img, nrm_img]


## Gegossener Garagenboden: 2 × 2 Platten pro Kachel mit Fugenschnitt und gefaster Kante,
## Kellenflecken, Zuschlagkörnung, Luftporen und leicht unterschiedlichem Farbton pro Platte.
func _render_concrete(size: int) -> Array:
	var tile := size / 2
	var joint := maxi(2, size / 256)
	var bevel := maxi(2, size / 256)
	var cd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 4, 101, size)
	var md := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.03, 3, 102, size)
	var fd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.45, 1, 103, size)
	var alb := PackedByteArray()
	alb.resize(size * size * 3)
	var hg := PackedByteArray()
	hg.resize(size * size)
	for y in range(size):
		var slab_row := y / tile
		var gy := y % tile
		var dy := mini(gy, tile - 1 - gy)
		var slab_var_l := float(((0 * 73856093) ^ ((slab_row + 1) * 19349663)) & 1023) / 1023.0
		var slab_var_r := float(((1 * 73856093) ^ ((slab_row + 1) * 19349663)) & 1023) / 1023.0
		for x in range(size):
			var gx := x % tile
			var d := mini(dy, mini(gx, tile - 1 - gx))
			var i := y * size + x
			var c := float(cd[i]) / 255.0
			var m := float(md[i]) / 255.0
			var f := float(fd[i]) / 255.0
			var slab_var := slab_var_l if x < tile else slab_var_r
			var v := c * 0.55 + m * 0.30 + slab_var * 0.15
			var base := lerpf(0.46, 0.60, v) * (0.95 + f * 0.09)
			var h := lerpf(0.55, 0.75, v) + (f - 0.5) * 0.08
			if f < 0.05:
				# Luftporen
				base *= 0.78
				h -= 0.14
			elif f > 0.96:
				# helle Zuschlagkörner
				base *= 1.07
			if d < joint:
				base *= 0.55
				h = 0.16
			elif d < joint + bevel:
				var e := float(d - joint + 1) / float(bevel + 1)
				base *= lerpf(0.80, 1.0, e)
				h = lerpf(0.30, h, e)
			var j := i * 3
			# Warmer Beton ohne Blaustich
			alb[j] = clampi(int(base * 1.01 * 255.0), 0, 255)
			alb[j + 1] = clampi(int(base * 255.0), 0, 255)
			alb[j + 2] = clampi(int(base * 0.97 * 255.0), 0, 255)
			hg[i] = clampi(int(h * 255.0), 0, 255)
	return _finish_pair(size, alb, hg, 5.0)


## Doppelboden: 4 × 4 Platten pro Kachel, schmale Fuge, gefaste Plattenkante,
## Farbton pro Platte und feine helle/dunkle Chips wie bei antistatischem Vinylbelag.
func _render_raised_floor(size: int, col_a: Color, col_b: Color, grout_col: Color) -> Array:
	var tile := size / 4
	var joint := maxi(2, size / 400)
	var bevel := maxi(3, size / 128)
	var cd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 3, 202, size)
	var fd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.35, 1, 203, size)
	var alb := PackedByteArray()
	alb.resize(size * size * 3)
	var hg := PackedByteArray()
	hg.resize(size * size)
	for y in range(size):
		var ty := y / tile
		var gy := y % tile
		var dy := mini(gy, tile - 1 - gy)
		for x in range(size):
			var tx := x / tile
			var gx := x % tile
			var d := mini(dy, mini(gx, tile - 1 - gx))
			var i := y * size + x
			var c := float(cd[i]) / 255.0
			var f := float(fd[i]) / 255.0
			var tile_var := float((((tx + 1) * 73856093) ^ ((ty + 1) * 19349663)) & 1023) / 1023.0
			var t := clampf(c * 0.6 + tile_var * 0.4, 0.0, 1.0)
			var r := lerpf(col_a.r, col_b.r, t)
			var g := lerpf(col_a.g, col_b.g, t)
			var b := lerpf(col_a.b, col_b.b, t)
			var shade := 0.97 + c * 0.04
			var h := 0.80 + (c - 0.5) * 0.04
			if f > 0.93:
				shade *= 1.10
			elif f < 0.07:
				shade *= 0.88
			if d < joint:
				r = grout_col.r
				g = grout_col.g
				b = grout_col.b
				shade = 1.0
				h = 0.14
			elif d < joint + bevel:
				var e := float(d - joint + 1) / float(bevel + 1)
				shade *= lerpf(0.86, 1.0, e)
				h = lerpf(0.42, h, e)
			var j := i * 3
			alb[j] = clampi(int(r * shade * 255.0), 0, 255)
			alb[j + 1] = clampi(int(g * shade * 255.0), 0, 255)
			alb[j + 2] = clampi(int(b * shade * 255.0), 0, 255)
			hg[i] = clampi(int(h * 255.0), 0, 255)
	return _finish_pair(size, alb, hg, 6.0)


func _gen_pcb_tex(size: int, base_col: Color, trace_col: Color, pad_col: Color) -> Array:
	# Zwei kachelbare Rauschfelder: Körnung des Lötstopplacks und feine helle Punkte.
	var grain := _noise_l8(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 3, 811, size)
	var speck := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.5, 1, 812, size)
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_L8)
	var dark_base := base_col.darkened(0.25)
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var n := float(grain[i]) / 255.0
			var s := float(speck[i]) / 255.0
			var c := base_col.lerp(dark_base, n * 0.5)
			var hv := 0.40 + n * 0.08
			if s > 0.80:
				c = c.lightened(0.05)
			# Kupferbahnen: 2 px breit, mit leicht dunklerem, körnigem Rand
			var hx := x % 16
			var hy := y % 16
			var diag := (x + y) % 32
			var on_trace := hx == 2 or hx == 3 or hy == 4 or hy == 5 or (diag == 6 and ((x / 16) % 2 == 0))
			if on_trace:
				c = trace_col.lerp(dark_base, n * 0.3)
				hv = 0.70 + n * 0.04
			# Durchkontaktierungen: goldener Kern, dunkler Ring, Kupfer-Lötring
			var vx := (x % 32) - 16
			var vy := (y % 32) - 16
			var d2 := vx * vx + vy * vy
			if d2 <= 5:
				c = pad_col
				hv = 0.92
			elif d2 <= 10:
				c = dark_base
				hv = 0.25
			elif d2 <= 14:
				c = c.lerp(pad_col, 0.25)
				hv = 0.55
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


## Warnstreifen mit leichter Abnutzung. Streifenbreite size/4, damit sich das diagonale Muster
## an den Kachelrändern nahtlos fortsetzt (die alte Breite 24 von 128 erzeugte eine Naht).
func _gen_hazard_stripes_tex(size: int) -> ImageTexture:
	var band_w := maxi(1, size / 4)
	var wear := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.05, 4, 660, size)
	var yellow := Color(0.82, 0.64, 0.14)
	var dark := Color(0.14, 0.14, 0.15)
	var px := PackedByteArray()
	px.resize(size * size * 3)
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var c := yellow if ((x + y) / band_w) % 2 == 0 else dark
			var w := 0.92 + float(wear[i]) / 255.0 * 0.10
			var j := i * 3
			px[j] = clampi(int(c.r * w * 255.0), 0, 255)
			px[j + 1] = clampi(int(c.g * w * 255.0), 0, 255)
			px[j + 2] = clampi(int(c.b * w * 255.0), 0, 255)
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGB8, px))


## Wellblech: 8 Wellen pro Kachel wie bisher, dazu Verzinkungsflecken und feine Körnung.
func _render_corrugated(size: int) -> Array:
	var sd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 3, 671, size)
	var fd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.30, 1, 672, size)
	var alb := PackedByteArray()
	alb.resize(size * size * 3)
	var hg := PackedByteArray()
	hg.resize(size * size)
	for y in range(size):
		var wave := 0.5 + 0.5 * sin(float(y) / float(size) * TAU * 8.0)
		var base := lerpf(0.46, 0.62, wave)
		for x in range(size):
			var i := y * size + x
			var s := float(sd[i]) / 255.0
			var f := float(fd[i]) / 255.0
			var v := clampi(int(base * (0.92 + s * 0.12) * (0.97 + f * 0.06) * 255.0), 0, 255)
			var j := i * 3
			alb[j] = v
			alb[j + 1] = v
			alb[j + 2] = v
			hg[i] = clampi(int((wave * 0.92 + f * 0.03) * 255.0), 0, 255)
	return _finish_pair(size, alb, hg, 10.0)


## Ziegelfassade: gleiche Steinaufteilung wie bisher (4 × 8 pro Kachel), dazu Farbton pro Stein,
## gefaste Kanten, vertiefte Mörtelfugen mit Körnung und kleine Poren im Stein.
func _render_brick(size: int) -> Array:
	var bw := size / 4
	var bh := size / 8
	var joint := maxi(2, size / 200)
	var bevel := maxi(3, size / 170)
	var cd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 4, 777, size)
	var md := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.05, 3, 778, size)
	var fd := _noise_l8(FastNoiseLite.TYPE_SIMPLEX, 0.40, 1, 779, size)
	var alb := PackedByteArray()
	alb.resize(size * size * 3)
	var hg := PackedByteArray()
	hg.resize(size * size)
	for y in range(size):
		var row := y / bh
		var ly := y % bh
		var dy := mini(ly, bh - 1 - ly)
		var shift := bw / 2 if row % 2 == 1 else 0
		for x in range(size):
			var sx := (x + shift) % size
			var col := sx / bw
			var lx := sx % bw
			var d := mini(dy, mini(lx, bw - 1 - lx))
			var i := y * size + x
			var c := float(cd[i]) / 255.0
			var m := float(md[i]) / 255.0
			var f := float(fd[i]) / 255.0
			var r: float
			var g: float
			var b: float
			var h: float
			if d < joint:
				var mv := 0.90 + f * 0.14
				r = 0.58 * mv
				g = 0.56 * mv
				b = 0.52 * mv
				h = 0.16 + f * 0.08
			else:
				var hsh := (((col + 1) * 73856093) ^ ((row + 1) * 19349663)) & 1023
				var brick_var := float(hsh) / 1023.0
				var hue := float((hsh >> 3) & 127) / 127.0
				var e := clampf(float(d - joint + 1) / float(bevel), 0.0, 1.0)
				e = e * (2.0 - e)
				var br := lerpf(0.40, 0.60, clampf(brick_var * 0.45 + c * 0.35 + m * 0.20, 0.0, 1.0))
				br *= (0.93 + f * 0.12) * lerpf(0.88, 1.0, e)
				h = lerpf(0.40, 0.80, e) + (m - 0.5) * 0.10 + (f - 0.5) * 0.08
				if f < 0.06:
					br *= 0.85
					h -= 0.15
				r = br * lerpf(1.06, 1.18, hue)
				g = br * 0.64
				b = br * 0.48
			var j := i * 3
			alb[j] = clampi(int(r * 255.0), 0, 255)
			alb[j + 1] = clampi(int(g * 255.0), 0, 255)
			alb[j + 2] = clampi(int(b * 255.0), 0, 255)
			hg[i] = clampi(int(h * 255.0), 0, 255)
	return _finish_pair(size, alb, hg, 5.0)


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


## Liefert [Albedo oben, Albedo Sockel, Normal-Map] als ImageTextures mit Mipmaps.
## Lädt aus dem Cache in user://, sonst wird einmal gerechnet und gespeichert.
func _gen_block_wall_set(size: int, upper_a: Color, upper_b: Color, lower_a: Color, lower_b: Color) -> Array:
	var cache_key := "block_wall_v%d_%d" % [WALL_TEX_VERSION, size]
	return _cached_textures(cache_key, func() -> Array:
		return _render_block_wall(size, upper_a, upper_b, lower_a, lower_b), [false, false, true])


## Rechnet die Wand: 4 × 8 Steine (40 × 20 cm) pro Kachel, ~1 cm Fuge, gefaste Kanten,
## feine Porenstruktur unter der Farbe, leichte Farbunterschiede pro Stein und großflächig.
## Arbeitet auf PackedByteArrays statt set_pixel, damit 1024² Pixel schnell genug gehen.
func _render_block_wall(size: int, upper_a: Color, upper_b: Color, lower_a: Color, lower_b: Color) -> Array:
	var cols := 4
	var rows := 8
	var bw := size / cols
	var bh := size / rows
	var joint := maxi(2, size / 170)
	var bevel := maxi(3, size / 100)

	var fine_img := _make_noise(FastNoiseLite.TYPE_SIMPLEX, 0.30, 2, 4041).get_seamless_image(size, size)
	var coarse_img := _make_noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0045, 3, 4042).get_seamless_image(size, size)
	fine_img.convert(Image.FORMAT_L8)
	coarse_img.convert(Image.FORMAT_L8)
	var fd := fine_img.get_data()
	var cd := coarse_img.get_data()

	var up := PackedByteArray()
	up.resize(size * size * 3)
	var lo := PackedByteArray()
	lo.resize(size * size * 3)
	var hg := PackedByteArray()
	hg.resize(size * size)

	for y in range(size):
		var row := y / bh
		var ly := y % bh
		var dy := mini(ly, bh - 1 - ly)
		var shift := bw / 2 if row % 2 == 1 else 0
		for x in range(size):
			var sx := (x + shift) % size
			var col := sx / bw
			var lx := sx % bw
			var d := mini(dy, mini(lx, bw - 1 - lx))
			var i := y * size + x
			var f := float(fd[i]) / 255.0
			var c := float(cd[i]) / 255.0
			var h: float
			var t: float
			var shade: float
			if d < joint:
				# Fuge: vertieft, etwas dunkler, gleiche Farbe (überstrichen).
				h = 0.16 + f * 0.08
				t = c
				shade = 0.80 + f * 0.06
			else:
				var edge := clampf(float(d - joint + 1) / float(bevel), 0.0, 1.0)
				edge = edge * (2.0 - edge)
				var block_var := float(((col * 73856093) ^ (row * 19349663)) & 1023) / 1023.0
				t = clampf(c * 0.7 + block_var * 0.3, 0.0, 1.0)
				h = lerpf(0.40, 0.74, edge) + (f - 0.5) * 0.14
				shade = lerpf(0.91, 1.0, edge) * (0.95 + f * 0.09)
				if f < 0.14:
					# Kleine Poren im Stein.
					h -= 0.16
					shade *= 0.86
			hg[i] = clampi(int(h * 255.0), 0, 255)
			var j := i * 3
			up[j] = clampi(int(lerpf(upper_a.r, upper_b.r, t) * shade * 255.0), 0, 255)
			up[j + 1] = clampi(int(lerpf(upper_a.g, upper_b.g, t) * shade * 255.0), 0, 255)
			up[j + 2] = clampi(int(lerpf(upper_a.b, upper_b.b, t) * shade * 255.0), 0, 255)
			lo[j] = clampi(int(lerpf(lower_a.r, lower_b.r, t) * shade * 255.0), 0, 255)
			lo[j + 1] = clampi(int(lerpf(lower_a.g, lower_b.g, t) * shade * 255.0), 0, 255)
			lo[j + 2] = clampi(int(lerpf(lower_a.b, lower_b.b, t) * shade * 255.0), 0, 255)

	var up_img := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, up)
	var lo_img := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, lo)
	var nrm_img := Image.create_from_data(size, size, false, Image.FORMAT_L8, hg)
	# Gleiche Umrechnung, die NoiseTexture2D für as_normal_map nutzt (native, schnell).
	nrm_img.bump_map_to_normal_map(5.0)
	return [up_img, lo_img, nrm_img]


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
