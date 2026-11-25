class_name PartModels
extends RefCounted
## Lädt die eigenen 3D-Modelle der Bauteile (tools/blender/build_parts_d.py).
##   hw_<id>.glb   Produkt (Shop, Teile-Lager, in der Hand)
##   hwm_<id>.glb  Einbauvariante im Server und auf der Werkbank
## PBR_*-Materialien mit Texturen kommen aus den part_*.glb und werden von allen geteilt.

const PBR_SOURCES: Array[String] = ["part_cpu_t1", "part_psu_t0", "part_psu_t2", "part_ram_t1", "part_gpu_t2", "part_cooling_t3", "part_storage_t1", "part_mainboard"]
const FLOW_SHADER := "
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float speed = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; VERTEX += NORMAL * 0.0002; }
void fragment() {
	float t = fract(UV.y * 2.0 - TIME * speed * 0.8);
	float b = smoothstep(0.42, 0.5, t) * (1.0 - smoothstep(0.5, 0.62, t));
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	EMISSION = tint.rgb * (0.10 + b * 0.8) * min(speed, 1.0);
	ALPHA = 0.16 + b * 0.5 * min(speed, 1.0);
}
"

static var _pbr: Dictionary = {}
static var _pbr_done := false
static var _flow_shader: Shader


static func has_product(id: String) -> bool:
	return id != "" and ModelLoader.has_custom_model("hw_" + id)


static func has_mount(id: String) -> bool:
	return id != "" and ModelLoader.has_custom_model("hwm_" + id)


## Produktmodell mit Aufschrift. Drehende Lüfter stehen in out_fans.
static func product(id: String, out_fans: Array = [], with_text: bool = true) -> Node3D:
	if not has_product(id):
		return null
	var n := ModelLoader.instantiate_custom_model("hw_" + id)
	if n != null:
		prepare(n, out_fans)
		if with_text:
			add_text(n, id)
	return n


static func mount(id: String, out_fans: Array = []) -> Node3D:
	if not has_mount(id):
		return null
	var n := ModelLoader.instantiate_custom_model("hwm_" + id)
	if n != null:
		prepare(n, out_fans)
	return n


## Gemeinsame Materialien zuweisen, Lüfter einsammeln, Wasser vorbereiten.
static func prepare(n: Node, out_fans: Array = []) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := str(mi.name)
		if nm.begins_with("Rotor_"):
			mi.set_meta("spin_axis", "x" if nm.begins_with("Rotor_X") else ("y" if nm.begins_with("Rotor_Y") else "z"))
			out_fans.append(mi)
		if nm.begins_with("Flow_"):
			_setup_flow(mi)
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m != null and m.resource_name.begins_with("PBR_"):
					var sh := pbr(m.resource_name)
					if sh != null:
						mi.set_surface_override_material(s, sh)
	for c in n.get_children():
		prepare(c, out_fans)


static func _setup_flow(mi: MeshInstance3D) -> void:
	if _flow_shader == null:
		_flow_shader = Shader.new()
		_flow_shader.code = FLOW_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _flow_shader
	if mi.mesh != null and mi.mesh.get_surface_count() > 0:
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src != null:
			sm.set_shader_parameter("tint", src.albedo_color)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("flow", true)


static func pbr(mat_name: String) -> Material:
	if not _pbr_done:
		_pbr_done = true
		for src in PBR_SOURCES:
			if not ModelLoader.has_custom_model(src):
				continue
			var inst := ModelLoader.instantiate_custom_model(src)
			if inst != null:
				_collect(inst)
				inst.free()
	return _pbr.get(mat_name)


static func _collect(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and not m.resource_name.is_empty() and not _pbr.has(m.resource_name):
				_pbr[m.resource_name] = m
	for c in n.get_children():
		_collect(c)


## Name und Kurzdaten auf die Label_*-Flächen schreiben.
static func add_text(root: Node3D, id: String) -> void:
	var pd := HardwareCatalog.get_part(HardwareCatalog.find_part_category(id), id)
	if pd.is_empty():
		return
	var full := str(pd.get("name", id))
	var short := full.get_slice(" (", 0)
	for a in root.find_children("Label_*", "Node3D", true, false):
		var holder := a as Node3D
		var b := holder.transform.basis
		var w := b.x.length()
		var h := b.y.length()
		if w < 0.0001 or h < 0.0001:
			continue
		var l := Label3D.new()
		var side := str(holder.name).begins_with("Label_back") or str(holder.name).begins_with("Label_side")
		l.text = short.to_upper() if side else short
		l.font_size = 48
		l.outline_size = 0
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if h > w * 0.3 else TextServer.AUTOWRAP_OFF
		l.modulate = _text_color(root, holder, side)
		var font := ThemeDB.fallback_font
		var tw := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		var px := h / float(l.font_size) * 0.72
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			px = minf(px, w / maxf(tw, 1.0) * 0.94)
		else:
			px = minf(h / (float(l.font_size) * 3.2), w / maxf(tw / 2.0, 1.0) * 0.94)
			l.width = w / px
		l.pixel_size = px
		l.transform = Transform3D(Basis(b.x.normalized(), b.y.normalized(), b.z.normalized()), holder.position)
		l.visibility_range_end = 4.0
		(holder.get_parent() as Node3D).add_child(l)


static func _text_color(_root: Node3D, holder: Node3D, side: bool) -> Color:
	if side:
		return Color(0.92, 0.94, 0.96, 0.95)
	return Color(0.10, 0.11, 0.13) if str(holder.name) == "Label_name" else Color(0.9, 0.9, 0.9)
