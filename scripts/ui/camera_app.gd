class_name CameraApp
extends VBoxContainer
## Kamera-App am PC: Live-Bilder aller Überwachungsstelen. Bis zu vier gleichzeitig, ein Klick macht eines groß.
## Die Bilder werden nur ein paar Mal pro Sekunde neu gezeichnet, damit der PC flüssig bleibt.

const T := preload("res://scripts/ui/finance_apps.gd")
const PER_PAGE := 4
const FEED := Vector2i(640, 360)
const FEED_BIG := Vector2i(1120, 630)
const INTERVAL := 0.20
const INTERVAL_BIG := 0.07
const PITCH := deg_to_rad(-16.0)

const SHADER := "
shader_type canvas_item;
uniform float night = 0.0;
uniform float lost = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + TIME * 3.1) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 c = texture(TEXTURE, uv).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 n = vec3(0.55, 1.0, 0.72) * clamp(g * 2.6 + 0.03, 0.0, 1.0);
	c = mix(c, n, night);
	c *= 0.93 + 0.07 * sin(uv.y * 720.0);
	c += (rnd(floor(uv * 320.0)) - 0.5) * 0.05;
	vec3 s = vec3(rnd(floor(uv * vec2(220.0, 130.0)))) * 0.45;
	c = mix(c, s, lost);
	float v = distance(uv, vec2(0.5));
	c *= 1.0 - v * v * 0.75;
	COLOR = vec4(c, 1.0);
}
"

var state: Dictionary = {}
var _feeds: Array[Dictionary] = []
var _host: Control
var _clock := 0.0
var _ids: Array = []
var _info: Label


static func render(host: Control, st: Dictionary) -> void:
	var app := CameraApp.new()
	app.state = st
	app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(app)


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	set_meta("vt", true)
	_rebuild()


static func cam_ids() -> Array:
	var out: Array = []
	for d in GameState.decor_items.values():
		if str((d as Dictionary).get("item_type", "")) == "prop_cctv_monitor":
			out.append(str(d["id"]))
	out.sort()
	return out


static func place_name(p: Vector3) -> String:
	if p.z < -50.0:
		return TranslationServer.translate("Halle Nord")
	if p.z > 4.6:
		return TranslationServer.translate("Lieferzone")
	return TranslationServer.translate("Garage")


func _cam_node(did: String) -> Node3D:
	for n in get_tree().get_nodes_in_group("cctv_cam"):
		if str((n as Node).get_meta("decor_id", "")) == did and (n as Node3D).is_inside_tree():
			return n as Node3D
	return null


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_feeds.clear()
	_ids = cam_ids()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", Color(0.78, 0.83, 0.90))
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_info)
	if _ids.is_empty():
		_info.text = tr("Keine Kameras aufgestellt")
		var box := CenterContainer.new()
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(box)
		var l := Label.new()
		l.text = tr("Kauf eine Überwachungsstele im Shop (Infrastruktur) und stell sie auf.\nSie warnt vor Hitze, Rauch und Dieben, und hier siehst du ihr Live-Bild.")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
		box.add_child(l)
		return
	var big := str(state.get("big", ""))
	if not _ids.has(big):
		big = ""
		state["big"] = ""
	var pages := ceili(float(_ids.size()) / float(PER_PAGE))
	var page := clampi(int(state.get("page", 0)), 0, pages - 1)
	_info.text = tr("%d Kameras") % _ids.size() if _ids.size() != 1 else tr("1 Kamera")
	if big != "":
		head.add_child(_btn(tr("Alle zeigen"), func():
			state["big"] = ""
			_rebuild()))
	elif pages > 1:
		head.add_child(_btn("<", func():
			state["page"] = posmod(page - 1, pages)
			_rebuild()))
		head.add_child(_btn("%d / %d" % [page + 1, pages], Callable()))
		head.add_child(_btn(">", func():
			state["page"] = posmod(page + 1, pages)
			_rebuild()))
	var show: Array = [big] if big != "" else _ids.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
	var grid := GridContainer.new()
	grid.columns = 1 if show.size() == 1 else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for did in show:
		_add_feed(grid, str(did), show.size() == 1)


func _btn(text: String, press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	if press.is_valid():
		b.pressed.connect(press)
	else:
		b.disabled = true
	return b


func _add_feed(grid: Control, did: String, big: bool) -> void:
	var panel := Control.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(240, 136)
	panel.clip_contents = true
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			state["big"] = "" if str(state.get("big", "")) == did else did
			SfxManager.play("click", -12.0, 1.1)
			_rebuild.call_deferred())
	grid.add_child(panel)
	var vp := SubViewport.new()
	vp.size = FEED_BIG if big else FEED
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 1024
	vp.world_3d = get_viewport().find_world_3d()
	panel.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 74.0
	cam.near = 0.08
	cam.far = 90.0
	vp.add_child(cam)
	cam.make_current()
	var pic := TextureRect.new()
	pic.texture = vp.get_texture()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	pic.material = mat
	panel.add_child(pic)
	var title := _overlay(panel, 8, 6, false)
	var stamp := _overlay(panel, 8, 6, true)
	var mid := Label.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mid.add_theme_font_size_override("font_size", 22 if big else 16)
	mid.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(mid)
	_feeds.append({"id": did, "vp": vp, "cam": cam, "mat": mat, "title": title, "stamp": stamp, "mid": mid, "t": float(_feeds.size()) * 0.05, "big": big, "n": _ids.find(did) + 1})


func _overlay(panel: Control, x: float, y: float, bottom: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if bottom else Control.PRESET_TOP_LEFT)
	l.position = Vector2(x, -24.0 if bottom else y)
	panel.add_child(l)
	if bottom:
		l.offset_top = -24.0
		l.offset_left = x
	return l


func _process(delta: float) -> void:
	_clock += delta
	if cam_ids() != _ids:
		_rebuild()
		return
	if not is_visible_in_tree():
		return
	var power: bool = DecorManager.has_power()
	var dark: bool = GameState.time_of_day < 0.24 or GameState.time_of_day > 0.78
	for f in _feeds:
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) > 0.0:
			continue
		f["t"] = INTERVAL_BIG if bool(f["big"]) else INTERVAL
		var src := _cam_node(str(f["id"]))
		var ok := power and src != null
		(f["mat"] as ShaderMaterial).set_shader_parameter("lost", 0.0 if ok else 1.0)
		(f["mat"] as ShaderMaterial).set_shader_parameter("night", 1.0 if dark and src != null and src.global_position.z > 4.6 else 0.0)
		(f["mid"] as Label).text = "" if ok else (tr("KEIN STROM") if not power else tr("KEIN SIGNAL"))
		var rec := ok and fmod(_clock, 1.2) < 0.7
		var place := place_name(src.global_position) if src != null else "-"
		(f["title"] as Label).text = tr("KAM %d  %s") % [int(f["n"]), place] + ("  ●" if rec else "")
		(f["title"] as Label).add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if rec else Color(1, 1, 1, 0.95))
		(f["stamp"] as Label).text = tr("Tag %d  %s") % [GameState.day_number, GameState.get_time_string()] + ("  +  " + tr("DIEB ERKANNT") if not DecorManager.thief.is_empty() and ok and src.global_position.distance_to(Vector3(0, 0, 6)) < DecorManager.CAM_RANGE else "")
		if not ok:
			continue
		var tf := src.global_transform.orthonormalized()
		tf.basis = tf.basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PITCH)
		tf.origin = src.global_transform * Vector3(0.0, 0.05, 0.30)
		(f["cam"] as Camera3D).global_transform = tf
		(f["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
