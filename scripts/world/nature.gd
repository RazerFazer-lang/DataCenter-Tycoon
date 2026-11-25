class_name Nature
extends RefCounted
## Bäume, Büsche, Wiese und ihre Jahreszeiten. Alle Materialien werden geteilt, update() stellt sie um.
## Jahreszeit als Zahl 0..4: 0 Frühling, 1 Sommer, 2 Herbst, 3 Winter (dazwischen fließend).

const SPECIES: Array[String] = ["oak", "birch", "maple", "pine", "apple", "bush"]
const FAR_DIST := 46.0

const LEAF_SHADER := "
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 col_a : source_color = vec3(0.16, 0.34, 0.10);
uniform vec3 col_b : source_color = vec3(0.34, 0.50, 0.16);
uniform vec3 blossom_col : source_color = vec3(1.0, 0.86, 0.90);
uniform float amount = 1.0;
uniform float blossom = 0.0;
uniform float snow = 0.0;
uniform float wind = 0.065;
uniform float wind_speed = 1.45;
uniform float flutter = 1.0;
instance uniform float seed = 0.0;
varying float v_rnd;
varying float v_ao;
varying float v_up;
void vertex() {
	v_rnd = fract(COLOR.g + seed * 0.37);
	v_ao = COLOR.r;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y * 0.16, 0.0, 1.6);
	float p = TIME * wind_speed + w.x * 0.32 + w.z * 0.27 + seed * 6.0;
	vec3 off = vec3(sin(p) * 0.65 + sin(p * 2.13) * 0.35, 0.0, cos(p * 0.87) * 0.55) * wind * h * 2.0;
	float f = TIME * wind_speed * 4.2 + v_rnd * 40.0 + w.y * 3.0;
	off += NORMAL * sin(f) * wind * 0.55 * flutter * COLOR.b;
	off.y += cos(f * 0.8) * wind * 0.35 * flutter * COLOR.b;
	VERTEX += off;
	if (v_rnd > amount) {
		VERTEX = vec3(0.0, 0.3, 0.0);
	}
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
void fragment() {
	vec4 t = texture(leaf_tex, UV);
	vec2 dx = dFdx(UV) * 1024.0;
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), 0.0001)));
	ALPHA = t.a * (1.0 + mip * 0.28);
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	float l = t.r;
	vec3 c = mix(col_a, col_b, v_rnd * 0.75 + l * 0.25);
	float tint = fract(seed * 1.7);
	c *= mix(vec3(0.90, 0.95, 0.92), vec3(1.08, 1.03, 0.96), tint);
	c *= (0.45 + 0.85 * l) * mix(0.60, 1.08, v_ao);
	float bl = step(fract(v_rnd * 7.3 + floor(UV.x * 22.0) * 0.37 + floor(UV.y * 22.0) * 0.61), blossom) * step(0.5, l);
	c = mix(c, blossom_col * (0.75 + 0.3 * l), bl);
	float s = smoothstep(0.15, 0.7, v_up + (l - 0.5) * 0.5) * snow;
	c = mix(c, vec3(0.90, 0.93, 0.97), s);
	ALBEDO = c;
	ROUGHNESS = mix(0.72, 0.9, s);
	SPECULAR = 0.22;
	BACKLIGHT = c * 0.55;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"
const BARK_SHADER := "
shader_type spatial;
uniform vec3 col_a : source_color = vec3(0.30, 0.23, 0.17);
uniform vec3 col_b : source_color = vec3(0.16, 0.12, 0.09);
uniform float mode = 0.0;
uniform float snow = 0.0;
uniform float wind = 0.065;
uniform float wind_speed = 1.45;
instance uniform float seed = 0.0;
varying vec3 lp;
varying vec3 wn;
float h31(vec3 p) { p = fract(p * 0.3183 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1,0,0)), f.x), mix(h31(i + vec3(0,1,0)), h31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h31(i + vec3(0,0,1)), h31(i + vec3(1,0,1)), f.x), mix(h31(i + vec3(0,1,1)), h31(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lp = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y * 0.16, 0.0, 1.6);
	float p = TIME * wind_speed + w.x * 0.32 + w.z * 0.27 + seed * 6.0;
	VERTEX += vec3(sin(p) * 0.65 + sin(p * 2.13) * 0.35, 0.0, cos(p * 0.87) * 0.55) * wind * h * h * 1.3;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float ridge = vn(vec3(lp.x * 22.0, lp.y * 4.0, lp.z * 22.0) + vn(lp * 5.0) * 2.0);
	float fine = vn(lp * 60.0);
	vec3 c = mix(col_b, col_a, smoothstep(0.25, 0.75, ridge) * 0.8 + fine * 0.2);
	if (mode > 0.5) {
		float band = smoothstep(0.62, 0.72, vn(vec3(lp.x * 7.0, lp.y * 17.0, lp.z * 7.0)));
		c = mix(vec3(0.86, 0.85, 0.82) * (0.82 + 0.2 * fine), vec3(0.10, 0.09, 0.08), band);
		c = mix(c, vec3(0.14, 0.12, 0.10), smoothstep(0.5, 0.0, lp.y) * 0.8);
	}
	float moss = smoothstep(0.55, 0.8, vn(lp * 3.0 + 9.0)) * smoothstep(1.2, 0.0, lp.y) * (1.0 - mode);
	c = mix(c, vec3(0.17, 0.22, 0.09), moss * 0.6);
	c = mix(c, vec3(0.90, 0.93, 0.97), smoothstep(0.35, 0.75, wn.y) * snow);
	ALBEDO = c;
	ROUGHNESS = 0.94;
	SPECULAR = 0.15;
	NORMAL = normalize(NORMAL + (vec3(ridge, fine, vn(lp * 24.0)) - 0.5) * 0.5);
}
"
const MEADOW_SHADER := "
shader_type spatial;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D grass_norm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D var_noise : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float tex_scale = 0.45;
uniform float normal_strength = 0.6;
uniform vec3 tint_lush : source_color = vec3(0.86, 1.0, 0.80);
uniform vec3 tint_dry : source_color = vec3(1.10, 1.02, 0.68);
uniform vec3 tint_dark : source_color = vec3(0.62, 0.76, 0.58);
uniform vec3 season_mul = vec3(1.0);
uniform float leaves = 0.0;
uniform float flowers = 0.0;
uniform float snow = 0.0;
varying vec3 wpos;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wpos.xz * tex_scale;
	vec3 base = texture(grass_tex, uv).rgb;
	float big = texture(var_noise, wpos.xz * 0.012).r;
	float mid = texture(var_noise, wpos.xz * 0.05 + vec2(0.37, 0.71)).r;
	float fine = texture(var_noise, wpos.xz * 0.22 + vec2(0.13, 0.52)).r;
	vec3 tint = mix(tint_lush, tint_dry, smoothstep(0.45, 0.75, big));
	tint = mix(tint, tint_dark, smoothstep(0.5, 0.8, mid) * 0.6);
	tint *= 0.9 + fine * 0.2;
	vec3 c = base * tint * season_mul;
	c = mix(vec3(dot(c, vec3(0.3, 0.6, 0.1))), c, 0.74) * vec3(1.03, 0.97, 0.94);
	// Laub und Blumen als kleine Flecken
	vec2 g = wpos.xz * 5.5;
	vec2 id = floor(g);
	float r = h21(id);
	vec2 d = fract(g) - vec2(0.3 + 0.4 * h21(id + 3.1), 0.3 + 0.4 * h21(id + 7.7));
	float spot = 1.0 - smoothstep(0.10, 0.16, length(d * vec2(1.0, 1.6)));
	float near = 1.0 - smoothstep(14.0, 34.0, length(VERTEX));
	float leaf_on = step(r, leaves * smoothstep(0.25, 0.75, mid + fine * 0.3)) * spot;
	c = mix(c, mix(vec3(0.62, 0.26, 0.05), vec3(0.75, 0.55, 0.10), h21(id + 1.3)), leaf_on * mix(0.35, 1.0, near));
	float fl = step(r, flowers * 0.16 * smoothstep(0.45, 0.8, mid)) * (1.0 - smoothstep(0.06, 0.09, length(d)));
	c = mix(c, h21(id + 5.0) > 0.5 ? vec3(0.95, 0.93, 0.88) : vec3(0.95, 0.78, 0.12), fl * near);
	float sn = smoothstep(0.0, 0.35, snow * 1.35 - (1.0 - (mid * 0.6 + fine * 0.4)) * 0.55);
	c = mix(c, vec3(0.88, 0.91, 0.95) * (0.94 + fine * 0.08), sn);
	ALBEDO = c;
	NORMAL_MAP = texture(grass_norm, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - sn * 0.75);
	ROUGHNESS = mix(0.95, 0.8, sn);
	SPECULAR = 0.3;
}
"

static var season := 1.4
static var snow := 0.0
static var wind := 0.065
static var wind_speed := 1.45
static var _leaf: Dictionary = {}
static var _bark: Dictionary = {}
static var _ground: Array = []
static var _tints: Array = []
static var _leaf_sh: Shader
static var _bark_sh: Shader
static var _meadow_sh: Shader
static var _noise: NoiseTexture2D


## Blattfarben je Art: [Frühling a,b, Sommer a,b, Herbst a,b, Winter a,b]
const COLORS := {
	"oak": ["5f8a2a", "8fae3c", "2c5a1c", "5a8a2c", "8a5a1c", "c08a2c", "6a4526", "7a5430"],
	"birch": ["7fae36", "a8c84a", "3f7a24", "78a83c", "d8a82a", "f0cf4a", "a88a3a", "b89a4a"],
	"maple": ["7aa836", "a0c048", "2f6a22", "5f9a34", "b8321a", "e8822a", "7a3a1c", "8a4a24"],
	"pine": ["2c5a34", "4a7a44", "20482c", "3c6a3c", "20462c", "38643a", "1e4030", "335c3a"],
	"apple": ["7aa83c", "98c04a", "3a7028", "6a9c38", "a89a2c", "d0a83c", "7a5a2c", "8a6a34"],
	"bush": ["5a8a30", "86b044", "2f6424", "5c9034", "96501e", "c87a2c", "5a4a2a", "6a5a34"],
}
## Anteil der Blätter: Frühling, Sommer, Herbst, Winter
const AMOUNT := {"oak": [0.85, 1.0, 0.78, 0.08], "birch": [0.85, 1.0, 0.62, 0.0], "maple": [0.85, 1.0, 0.70, 0.0], "pine": [1.0, 1.0, 1.0, 1.0], "apple": [0.9, 1.0, 0.62, 0.0], "bush": [0.9, 1.0, 0.85, 0.35]}
const BARKS := {"oak": ["5a4634", "2e241a"], "birch": ["dcd8d0", "201c18"], "maple": ["6a5a48", "3a2f25"], "pine": ["7a4e34", "3c281c"], "apple": ["5c4a3a", "32281f"], "bush": ["5a4838", "362a20"]}


static func species_for(pos: Vector3, pine: bool) -> String:
	if pine:
		return "pine"
	var h := absi(int(pos.x * 7.3) * 73 + int(pos.z * 5.1) * 151)
	return ["oak", "birch", "maple", "oak", "maple", "birch"][h % 6]


## Baum mit Nah- und Fernfassung. near = false: nur die Fernfassung (Waldgürtel).
static func tree(species: String, pos: Vector3, scale_v: float = 1.0, yaw_deg: float = 0.0, near: bool = true, shadow: bool = true) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	root.scale = Vector3.ONE * scale_v
	var sd := fposmod(pos.x * 0.173 + pos.z * 0.319 + yaw_deg * 0.011, 1.0)
	if species == "bush":
		_add(root, "bush_%d" % (1 + int(sd * 1.99)), species, sd, 0.0, 60.0, shadow)
		return root
	var vr := 1 if species == "apple" else 1 + int(sd * 1.99)
	if near:
		_add(root, "tree_%s_%d" % [species, vr], species, sd, 0.0, FAR_DIST, shadow)
		_add(root, "tree_%s_far" % species, species, sd, FAR_DIST, 0.0, shadow)
	else:
		_add(root, "tree_%s_far" % species, species, sd, 0.0, 0.0, false)
	return root


static func _add(root: Node3D, id: String, species: String, sd: float, from: float, to: float, shadow: bool) -> void:
	var m := ModelLoader.instantiate_custom_model(id)
	if m == null:
		return
	root.add_child(m)
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = leaf_mat(species) if str(mi.name).begins_with("Leaves") else bark_mat(species)
		mi.layers = MeshMerger.OUTSIDE_LAYER
		if DisplayServer.get_name() != "headless":
			mi.set_instance_shader_parameter("seed", sd)
		mi.visibility_range_begin = from
		mi.visibility_range_end = to
		if from > 0.0:
			mi.visibility_range_begin_margin = 1.0
		if to > 0.0:
			mi.visibility_range_end_margin = 1.0
		mi.extra_cull_margin = 0.6
		mi.lod_bias = 8.0
		if not shadow or from > 0.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func leaf_mat(species: String) -> ShaderMaterial:
	if not _leaf.has(species):
		if _leaf_sh == null:
			_leaf_sh = Shader.new()
			_leaf_sh.code = LEAF_SHADER
		var m := ShaderMaterial.new()
		m.shader = _leaf_sh
		m.set_shader_parameter("leaf_tex", load("res://assets/textures/nature/leaf_%s.png" % species))
		m.set_shader_parameter("flutter", 0.35 if species == "pine" else (1.5 if species == "birch" else 1.0))
		if species == "apple":
			m.set_shader_parameter("blossom_col", Color(1.0, 0.88, 0.92))
		_leaf[species] = m
		_apply_leaf(species)
	return _leaf[species]


static func bark_mat(species: String) -> ShaderMaterial:
	if not _bark.has(species):
		if _bark_sh == null:
			_bark_sh = Shader.new()
			_bark_sh.code = BARK_SHADER
		var m := ShaderMaterial.new()
		m.shader = _bark_sh
		m.set_shader_parameter("col_a", Color(BARKS[species][0]))
		m.set_shader_parameter("col_b", Color(BARKS[species][1]))
		m.set_shader_parameter("mode", 1.0 if species == "birch" else 0.0)
		_bark[species] = m
	return _bark[species]


static func meadow(grass_mat: Material, tex_scale: float = 0.45) -> ShaderMaterial:
	if _meadow_sh == null:
		_meadow_sh = Shader.new()
		_meadow_sh.code = MEADOW_SHADER
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.01
		noise.fractal_octaves = 4
		noise.seed = 2024
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.noise = noise
	var sm := ShaderMaterial.new()
	sm.shader = _meadow_sh
	sm.set_shader_parameter("var_noise", _noise)
	sm.set_shader_parameter("tex_scale", tex_scale)
	var std := grass_mat as StandardMaterial3D
	if std != null:
		if std.albedo_texture != null:
			sm.set_shader_parameter("grass_tex", std.albedo_texture)
		if std.normal_enabled and std.normal_texture != null:
			sm.set_shader_parameter("grass_norm", std.normal_texture)
	_ground.append(sm)
	_apply_ground(sm)
	return sm


## Einfache Materialien (Hügel, Dächer), die im Winter weiß werden.
static func register_tint(mat: StandardMaterial3D, amount: float = 0.85) -> void:
	_tints.append([mat, mat.albedo_color, amount])


## Werte zwischen den vier Jahreszeiten weich mischen.
static func mix4(v: Array) -> float:
	var s := fposmod(season, 4.0)
	var i := int(s)
	return lerpf(float(v[i]), float(v[(i + 1) % 4]), _ease(s - i))


## Die Mitte einer Jahreszeit hält ihr Bild, der Wechsel liegt am Ende.
static func _ease(f: float) -> float:
	return smoothstep(0.62, 1.0, f)


static func mix4c(v: Array, o: int) -> Color:
	var s := fposmod(season, 4.0)
	var i := int(s)
	return Color(str(v[i * 2 + o])).lerp(Color(str(v[((i + 1) % 4) * 2 + o])), _ease(s - i))


static func _apply_leaf(sp: String) -> void:
	var m: ShaderMaterial = _leaf[sp]
	m.set_shader_parameter("col_a", mix4c(COLORS[sp], 0))
	m.set_shader_parameter("col_b", mix4c(COLORS[sp], 1))
	m.set_shader_parameter("amount", mix4(AMOUNT[sp]))
	m.set_shader_parameter("blossom", mix4([0.62 if sp == "apple" else 0.0, 0.0, 0.0, 0.0]))
	m.set_shader_parameter("snow", snow)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("wind_speed", wind_speed)


static func _apply_ground(m: ShaderMaterial) -> void:
	var a := mix4([1.0, 1.0, 0.0, 0.0])
	m.set_shader_parameter("season_mul", Vector3(1.0, 1.0, 1.0).lerp(Vector3(1.10, 0.90, 0.62), (1.0 - a) * 0.75))
	m.set_shader_parameter("leaves", mix4([0.0, 0.0, 0.55, 0.12]))
	m.set_shader_parameter("flowers", mix4([1.0, 0.55, 0.0, 0.0]))
	m.set_shader_parameter("snow", snow)


static func update(p_season: float, p_snow: float, p_wind: float, p_speed: float) -> void:
	season = p_season
	snow = p_snow
	wind = p_wind
	wind_speed = p_speed
	for sp in _leaf.keys():
		_apply_leaf(sp)
	for sp in _bark.keys():
		var b: ShaderMaterial = _bark[sp]
		b.set_shader_parameter("snow", snow)
		b.set_shader_parameter("wind", wind)
		b.set_shader_parameter("wind_speed", wind_speed)
	for m in _ground:
		_apply_ground(m)
	var white := Color(0.88, 0.91, 0.95)
	for t in _tints:
		(t[0] as StandardMaterial3D).albedo_color = (t[1] as Color).lerp(white, snow * float(t[2]))


static func season_name(s: float) -> String:
	return ["Frühling", "Sommer", "Herbst", "Winter"][int(fposmod(s, 4.0))]
