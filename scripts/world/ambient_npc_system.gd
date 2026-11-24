class_name AmbientNpcSystem
extends Node3D
## Photorealistische 4K-Mixamo-Außen-NPCs (player_realistic & delivery_driver_realistic via HumanoidRigHelper)
## mit echter Skeleton3D-Geh-Animation + organischer Regenpfützen-Shader mit Regentropfen-Ripples!

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
		# Echte Skeleton3D-Geh-Animation (Oberschenkel, Knie, Oberarme & Unterarme!)
		var skel: Skeleton3D = w["skel"]
		var bones: Dictionary = w["bones"]
		if skel != null:
			var phase := _anim_t * spd * 4.6 + float(w["phase"])
			var s := sin(phase)
			HumanoidRigHelper.set_leg_pitch(skel, bones, "thigh_l", s * 0.44)
			HumanoidRigHelper.set_leg_pitch(skel, bones, "thigh_r", -s * 0.44)
			HumanoidRigHelper.set_leg_pitch(skel, bones, "knee_l", -maxf(0.0, -s) * 0.55)
			HumanoidRigHelper.set_leg_pitch(skel, bones, "knee_r", -maxf(0.0, s) * 0.55)
			HumanoidRigHelper.set_arm_pose(skel, bones, true, -s * 0.34, 0.04)
			HumanoidRigHelper.set_arm_pose(skel, bones, false, s * 0.34, 0.04)
			HumanoidRigHelper.set_forearm_bend(skel, bones, true, 0.22 + maxf(0.0, -s) * 0.22)
			HumanoidRigHelper.set_forearm_bend(skel, bones, false, 0.22 + maxf(0.0, s) * 0.22)
			root.position.y = absf(s) * 0.024

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


func _build_pedestrians() -> void:
	var o := GameState.HALLE_NORD_ORIGIN
	var specs := [
		["player_realistic",          Vector3(-18.0, 0.0, 19.35),  1.0, 1.32, -44.0, 46.0, Color(0.18, 0.36, 0.58), false],
		["delivery_driver_realistic", Vector3( 14.0, 0.0, 19.65), -1.0, 1.18, -44.0, 46.0, Color(0.58, 0.22, 0.20), false],
		["player_realistic",          Vector3(  2.0, 0.0, 19.10),  1.0, 1.42, -44.0, 46.0, Color(0.22, 0.44, 0.30), false],
		["player_realistic",          o + Vector3(-22.0, 0.0, 26.85),  1.0, 1.35, -48.0, 48.0, Color(0.16, 0.28, 0.48), true],
		["delivery_driver_realistic", o + Vector3( 16.0, 0.0, 27.15), -1.0, 1.24, -48.0, 48.0, Color(0.52, 0.34, 0.18), true],
		["player_realistic",          o + Vector3( 13.0, 0.0, 11.40),  1.0, 1.10,   8.0, 21.0, Color(0.24, 0.28, 0.36), true],
	]
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var npc := _spawn_realistic_human(str(sp[0]), sp[6] as Color)
		var r: Node3D = npc["root"]
		r.position = sp[1] as Vector3
		var dir: float = float(sp[2])
		# HumanoidRigHelper dreht Mixamo-Blickrichtung auf -Z -> +X ist -90°, -X ist +90°!
		r.rotation_degrees.y = -90.0 if dir > 0.0 else 90.0
		add_child(r)
		npc["dir"] = dir
		npc["speed"] = float(sp[3])
		npc["xmin"] = float(sp[4])
		npc["xmax"] = float(sp[5])
		npc["is_nord"] = bool(sp[7])
		npc["phase"] = float(i) * 1.4
		_walkers.append(npc)


func _build_gatehouse_guard() -> void:
	var g := _spawn_realistic_human("delivery_driver_realistic", Color(0.09, 0.16, 0.30))
	_guard_node = g["root"]
	_guard_node.position = GameState.HALLE_NORD_ORIGIN + Vector3(-4.55, 0.18, 16.25)
	_guard_node.rotation_degrees.y = 160.0
	add_child(_guard_node)


func _spawn_realistic_human(model_id: String, outfit_col: Color) -> Dictionary:
	var holder := Node3D.new()
	var m := ModelLoader.instantiate_custom_model(model_id)
	var skel: Skeleton3D = null
	var bones: Dictionary = {}
	if m != null:
		holder.add_child(m)
		HumanoidRigHelper.normalize_character_root(m, true)
		HumanoidRigHelper.apply_skin_to_skeleton_model(m, {}, outfit_col)
		skel = HumanoidRigHelper.find_skeleton(m)
		if skel != null:
			bones = HumanoidRigHelper.map_bones(skel)
			HumanoidRigHelper.apply_relaxed_standing_pose(skel, bones)
	return {"root": holder, "skel": skel, "bones": bones}


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
