class_name PartFx
extends Node3D
## Lebendige Hardware: Licht nach Last, Flackern bei Fehlern, Glühen und Flimmern bei Hitze, Staub,
## fließendes Wasser. Hängt als Kind an einem Server oder Einzelteil und wird von außen gefüttert.

const HOT := 68.0
const GLOW := 88.0
const OVERLAY := "
shader_type spatial;
render_mode blend_mix, depth_draw_never, unshaded, cull_back, shadows_disabled;
uniform float heat = 0.0;
uniform float dust = 0.0;
varying vec3 wn;
varying vec3 wp;
float h31(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); wp = VERTEX; VERTEX += NORMAL * 0.00008; }
void fragment() {
	float up = clamp(wn.y * 0.8 + 0.35, 0.0, 1.0);
	float n = h31(floor(wp * 1400.0)) * 0.5 + h31(floor(wp * 420.0)) * 0.5;
	float d = dust * up * smoothstep(0.15, 0.75, n + dust * 0.45);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.5);
	float g = heat * heat * (0.65 + 0.35 * sin(TIME * 2.0 + wp.x * 40.0)) * (0.35 + 0.65 * rim);
	vec3 hot = mix(vec3(0.75, 0.10, 0.02), vec3(1.0, 0.55, 0.16), heat);
	ALBEDO = mix(vec3(0.30, 0.285, 0.26), hot, step(0.001, g) * clamp(g / max(g + d, 0.001), 0.0, 1.0));
	ALPHA = clamp(d * 0.55 + g * 0.30, 0.0, 0.8);
}
"
const HAZE := "
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float fade = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.6, UV.y);
	vec2 o = vec2(sin(UV.y * 38.0 - TIME * 7.0) + sin(UV.y * 21.0 - TIME * 4.3), cos(UV.x * 30.0 + TIME * 5.0)) * 0.0008 * strength * fade;
	ALBEDO = textureLod(screen, SCREEN_UV + o, 0.0).rgb;
	ALPHA = fade * min(1.0, strength * 2.0);
}
"

static var _ov_shader: Shader
static var _hz_shader: Shader

var load_f := 0.4
var temp := 30.0
var dust := 0.0
var powered := true
var fault := false
## Ohne Überzug (z. B. im Rack von weitem) nur Licht und Wasser.
var with_overlay := true

var _glow: Array[StandardMaterial3D] = []
var _base: PackedFloat32Array = []
var _flows: Array[ShaderMaterial] = []
var _fans: Array = []
var _ov: ShaderMaterial
var _haze: MeshInstance3D
var _hz: ShaderMaterial
var _t := 0.0
var _speed := 0.0
var _flick := 1.0


## Server oder Teil anschließen. fans: Lüfter, die hier gedreht werden sollen (leer = dreht jemand anders).
func attach(root: Node, fans: Array = [], overlay: bool = true) -> void:
	_fans = fans
	with_overlay = overlay
	if overlay:
		if _ov_shader == null:
			_ov_shader = Shader.new()
			_ov_shader.code = OVERLAY
			_hz_shader = Shader.new()
			_hz_shader.code = HAZE
		_ov = ShaderMaterial.new()
		_ov.shader = _ov_shader
	var dup: Dictionary = {}
	_scan(root, dup, false)


func _scan(n: Node, dup: Dictionary, hot: bool) -> void:
	var h := hot or str(n.get_meta("part_cat", "")) in ["cpu", "gpu", "ram", "storage", "cooling"]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		if mi.has_meta("flow"):
			var sm := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			mi.material_override = sm
			_flows.append(sm)
		else:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as StandardMaterial3D
				if m == null or not m.resource_name.begins_with("HWL_"):
					continue
				if not dup.has(m.resource_name):
					var d := m.duplicate() as StandardMaterial3D
					d.resource_name = m.resource_name
					dup[m.resource_name] = d
					_glow.append(d)
					_base.append(maxf(0.6, m.emission_energy_multiplier))
				mi.set_surface_override_material(s, dup[m.resource_name])
			if _ov != null and h:
				mi.material_overlay = _ov
	for c in n.get_children():
		if c != self:
			_scan(c, dup, h)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var on := 1.0 if powered else 0.0
	_speed = lerpf(_speed, on * (4.0 + load_f * 12.0 + clampf((temp - 35.0) * 0.35, 0.0, 20.0)), clampf(delta * 1.6, 0.0, 1.0))
	if fault:
		_flick = 1.0 if fmod(_t * 7.3 + sin(_t * 13.0), 1.7) > 0.55 else 0.12
	else:
		_flick = 1.0
	var breathe := 0.75 + 0.25 * sin(_t * (1.2 + load_f * 3.0))
	for i in _glow.size():
		_glow[i].emission_energy_multiplier = _base[i] * on * _flick * breathe * (0.45 + load_f * 0.9)
		if fault:
			_glow[i].emission = Color(1.0, 0.18, 0.10)
	for f in _flows:
		f.set_shader_parameter("speed", on * (0.35 + load_f) * (0.15 if fault else 1.0))
	for f in _fans:
		if is_instance_valid(f):
			var n := f as Node3D
			match str(n.get_meta("spin_axis", "z")):
				"x":
					n.rotation.x += delta * _speed
				"y":
					n.rotation.y += delta * _speed
				_:
					n.rotation.z += delta * _speed
	if _ov != null:
		var heat := clampf((temp - HOT) / (GLOW - HOT), 0.0, 1.0)
		_ov.set_shader_parameter("heat", heat)
		_ov.set_shader_parameter("dust", clampf(dust / 100.0, 0.0, 1.0))
		_update_haze(heat)


func _update_haze(heat: float) -> void:
	if heat <= 0.02:
		if _haze != null:
			_haze.visible = false
		return
	if _haze == null:
		_haze = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.34, 0.30)
		_haze.mesh = q
		_hz = ShaderMaterial.new()
		_hz.shader = _hz_shader
		_haze.material_override = _hz
		_haze.position = Vector3(-0.05, 0.24, -0.05)
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_haze)
	_haze.visible = true
	_hz.set_shader_parameter("strength", heat)
