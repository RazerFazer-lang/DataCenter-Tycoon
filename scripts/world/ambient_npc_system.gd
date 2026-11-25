class_name AmbientNpcSystem
extends Node3D
## Passanten (eigene Figuren, jeder sieht anders aus), Pförtner und Regenpfützen mit Tropfenringen.

var _walkers: Array[Dictionary] = []
var _puddle_shader_mat: ShaderMaterial
var _puddle_nodes: Array[MeshInstance3D] = []
var _puddle_wetness: float = 0.0
var _guard_node: Node3D
var _anim_t: float = 0.0


func _ready() -> void:
	_build_pedestrians()
	_build_rain_puddles()
	_build_gatehouse_guard()
	GameState.building_upgrades_changed.connect(_sync_guard)
	GameState.halle_nord_changed.connect(_sync_guard)
	_sync_guard()


func _process(delta: float) -> void:
	_anim_t += delta
	for w in _walkers:
		var root: Node3D = w["root"]
		if not is_instance_valid(root):
			continue
		var is_nord: bool = bool(w["is_nord"])
		root.visible = (not is_nord) or GameState.halle_nord_owned
		if not root.visible:
			continue
		var dir: float = float(w["dir"])
		var spd: float = float(w["speed"])
		var xmin: float = float(w["xmin"])
		var xmax: float = float(w["xmax"])
		root.position.x += dir * spd * delta
		if dir > 0.0 and root.position.x > xmax:
			root.position.x = xmin
		elif dir < 0.0 and root.position.x < xmin:
			root.position.x = xmax
		_walk(w, dir, spd, delta)

	# Organische Regenpfützen mit Ripples weich ein-/ausblenden
	var w_st: String = GameState.weather_state if GameState.is_active else "clear"
	var target_w := 1.0 if (w_st == "rain" or w_st == "storm") else 0.0
	_puddle_wetness = move_toward(_puddle_wetness, target_w, delta * 0.18)
	if _puddle_shader_mat != null:
		_puddle_shader_mat.set_shader_parameter("wetness", _puddle_wetness)
		_puddle_shader_mat.set_shader_parameter("rain_active", 1.0 if target_w > 0.5 else 0.0)
	var vis := _puddle_wetness > 0.02
	for pm in _puddle_nodes:
		if is_instance_valid(pm):
			pm.visible = vis


func _sync_guard() -> void:
	if _guard_node != null:
		_guard_node.visible = GameState.halle_nord_owned and GameState.has_building_upgrade("upg_security_gate")


## Passant: geht, schaut sich um, bleibt manchmal stehen und grüßt Spieler in der Nähe.
func _walk(w: Dictionary, dir: float, spd: float, delta: float) -> void:
	var h: HumanModel = w["human"]
	if h.rig == null:
		return
	var root: Node3D = w["root"]
	w["wait"] = maxf(0.0, float(w["wait"]) - delta)
	w["cool"] = maxf(0.0, float(w["cool"]) - delta)
	var lp := get_tree().get_first_node_in_group("local_player") as Node3D
	var look := 0.0
	if lp != null:
		var to := lp.global_position - root.global_position
		if to.length() < 5.5:
			var loc := root.global_basis.inverse() * to
			look = clampf(atan2(-loc.x, -loc.z), -1.1, 1.1) if loc.z < 0.5 else 0.0
			if float(w["cool"]) <= 0.0 and loc.z < 0.0:
				w["cool"] = randf_range(25.0, 60.0)
				w["wait"] = 2.4
				h.rig.play("wave" if randf() < 0.6 else "nod")
	var waiting := float(w["wait"]) > 0.0
	if waiting:
		root.position.x -= dir * spd * delta
	h.move(Vector3.ZERO if waiting else Vector3(dir * spd, 0, 0))
	h.rig.look_yaw = look
	h.rig.mood = 0.5 if absf(look) > 0.01 else 0.0


func _build_pedestrians() -> void:
	var o := GameState.HALLE_NORD_ORIGIN
	var specs := [
		[Vector3(-18.0, 0.0, 19.35), 1.0, 1.32, -44.0, 46.0, false],
		[Vector3(14.0, 0.0, 19.65), -1.0, 1.18, -44.0, 46.0, false],
		[Vector3(2.0, 0.0, 19.10), 1.0, 1.42, -44.0, 46.0, false],
		[Vector3(-31.0, 0.0, 19.50), -1.0, 1.26, -44.0, 46.0, false],
		[o + Vector3(-22.0, 0.0, 26.85), 1.0, 1.35, -48.0, 48.0, true],
		[o + Vector3(16.0, 0.0, 27.15), -1.0, 1.24, -48.0, 48.0, true],
		[o + Vector3(13.0, 0.0, 11.40), 1.0, 1.10, 8.0, 21.0, true],
	]
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var r := Node3D.new()
		var h := HumanModel.create(HumanModel.random_look(i * 5 + 2))
		r.add_child(h)
		r.position = sp[0] as Vector3
		var dir: float = float(sp[1])
		r.rotation_degrees.y = -90.0 if dir > 0.0 else 90.0
		add_child(r)
		_walkers.append({"root": r, "human": h, "dir": dir, "speed": float(sp[2]), "xmin": float(sp[3]), "xmax": float(sp[4]), "is_nord": bool(sp[5]), "wait": 0.0, "cool": randf() * 10.0})


func _build_gatehouse_guard() -> void:
	_guard_node = Node3D.new()
	_guard_node.add_child(HumanModel.create(HumanModel.job_look("guard", 7)))
	_guard_node.position = GameState.HALLE_NORD_ORIGIN + Vector3(-4.55, 0.18, 16.25)
	_guard_node.rotation_degrees.y = 160.0
	add_child(_guard_node)


func _build_rain_puddles() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform float wetness = 0.0;
uniform float rain_active = 0.0;

varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float n = vnoise(wpos.xz * 1.15) * 0.65 + vnoise(wpos.xz * 2.8) * 0.35;
	float shape = smoothstep(0.92, 0.32, r + (n - 0.5) * 0.55);
	vec2 cell = floor(wpos.xz * 2.4);
	vec2 luv = fract(wpos.xz * 2.4) - 0.5;
	float rnd = hash21(cell);
	float t = fract(TIME * 1.35 + rnd);
	float ring = smoothstep(0.04, 0.0, abs(length(luv) - t * 0.45)) * (1.0 - t) * rain_active;
	ALBEDO = vec3(0.07, 0.11, 0.15) + vec3(0.18, 0.22, 0.26) * ring;
	ROUGHNESS = 0.03 + ring * 0.15;
	METALLIC = 0.42;
	SPECULAR = 0.95;
	ALPHA = clamp(shape * wetness * 0.62, 0.0, 0.68);
}
"""
	_puddle_shader_mat = ShaderMaterial.new()
	_puddle_shader_mat.shader = sh

	var o := GameState.HALLE_NORD_ORIGIN
	var spots := [
		[Vector3(-1.8, 0.008, 8.2), Vector2(4.4, 3.2)],
		[Vector3( 2.4, 0.008, 13.4), Vector2(5.6, 3.6)],
		[Vector3(-6.2, 0.008, 15.2), Vector2(4.8, 3.0)],
		[o + Vector3(-2.6, 0.008, 11.4), Vector2(5.2, 3.6)],
		[o + Vector3( 5.4, 0.008, 13.2), Vector2(5.8, 3.4)],
		[o + Vector3(-4.5, 0.008, 21.4), Vector2(6.5, 3.8)],
	]
	for sp in spots:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var sz: Vector2 = sp[1]
		pm.size = sz
		mi.mesh = pm
		mi.material_override = _puddle_shader_mat
		mi.position = sp[0] as Vector3
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_puddle_nodes.append(mi)
