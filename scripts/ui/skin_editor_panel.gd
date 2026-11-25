class_name SkinEditorPanel
extends HBoxContainer
## Figuren-Editor: links die eigene Figur in 3D (drehen, zoomen, Gesten ansehen), rechts Körper, Gesicht, Haare,
## Kleidung, Zubehör und gespeicherte Outfits. Läuft im Hauptmenü, im Pausemenü und am Spind.

signal look_changed(look: Dictionary)

const TABS := [["body", "Körper"], ["face", "Gesicht"], ["hair", "Haare"], ["clothes", "Kleidung"], ["extras", "Zubehör"], ["outfits", "Outfits"]]
const FOCUS := {"body": [1.0, 3.5], "face": [1.60, 1.05], "hair": [1.62, 1.15], "clothes": [0.98, 3.3], "extras": [1.15, 2.7], "outfits": [1.0, 3.5]}
const SWATCH := 30
const PRESETS := [
	["Alltag", {"top": 4, "top_a": 6, "top_b": 3, "bottom": 0, "bottom_a": 5, "shoes": 0, "shoe_a": 1, "hat": 0, "glasses": 0, "belt": 0, "gloves": 0, "badge": 0, "logo": 0}],
	["Firma", {"top": 1, "top_a": 8, "top_b": 4, "bottom": 1, "bottom_a": 0, "shoes": 0, "shoe_a": 0, "hat": 0, "belt": 0, "gloves": 0, "badge": 1, "logo": 1}],
	["Techniker", {"top": 6, "top_a": 6, "top_b": 14, "bottom": 3, "bottom_a": 0, "shoes": 3, "shoe_a": 0, "hat": 0, "belt": 1, "gloves": 0, "badge": 1, "logo": 1}],
	["Baustelle", {"top": 7, "top_a": 1, "acc_a": 13, "bottom": 3, "bottom_a": 20, "shoes": 3, "shoe_a": 20, "hat": 3, "belt": 1, "gloves": 1, "badge": 0, "logo": 1}],
	["Büro", {"top": 2, "top_a": 4, "top_b": 4, "bottom": 1, "bottom_a": 0, "shoes": 2, "shoe_a": 19, "hat": 0, "belt": 0, "gloves": 0, "badge": 1, "logo": 0}],
	["Anzug", {"top": 8, "top_a": 0, "top_b": 4, "bottom": 4, "bottom_a": 0, "shoes": 2, "shoe_a": 0, "hat": 0, "belt": 0, "gloves": 0, "badge": 0, "logo": 0}],
	["Labor", {"top": 9, "top_a": 4, "top_b": 4, "bottom": 1, "bottom_a": 1, "shoes": 0, "shoe_a": 4, "hat": 0, "glasses": 3, "belt": 0, "gloves": 1, "badge": 1, "logo": 1}],
	["Winter", {"top": 5, "top_a": 16, "top_b": 0, "bottom": 0, "bottom_a": 5, "shoes": 1, "shoe_a": 19, "hat": 2, "acc_a": 16, "belt": 0, "gloves": 1, "badge": 0, "logo": 0}],
]

var look: Dictionary = {}
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _human: HumanModel
var _yaw := 0.25
var _zoom := 0.0
var _cam_y := 1.0
var _cam_d := 3.5
var _dragging := false
var _tab := "body"
var _tab_btns: Dictionary = {}
var _page: VBoxContainer
var _dirty := 0.0
var _unsent := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	look = SettingsManager.get_skin()
	_build_ui()
	_show_tab("body")


func set_preview_active(active: bool) -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		refresh_from_settings()
	else:
		if _dirty > 0.0:
			_commit()
		if _unsent:
			_unsent = false
			NetworkManager.update_my_skin(look)


func refresh_from_settings() -> void:
	look = SettingsManager.get_skin()
	if _human != null:
		_human.apply(look)
	if _page != null:
		_show_tab(_tab)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _pivot == null:
		return
	_pivot.rotation.y = _yaw
	var f: Array = FOCUS[_tab]
	_cam_y = lerpf(_cam_y, lerpf(float(f[0]), 1.60, maxf(0.0, _zoom)) * _human.root_scale(), 1.0 - exp(-delta * 6.0))
	_cam_d = lerpf(_cam_d, lerpf(float(f[1]), 0.95, maxf(0.0, _zoom)) - minf(0.0, _zoom) * 1.2, 1.0 - exp(-delta * 6.0))
	_cam.position = Vector3(0.0, _cam_y + 0.06 * _cam_d, _cam_d)
	_cam.look_at(Vector3(0.0, _cam_y, 0.0))
	if _human.rig != null:
		# Schaut dem Betrachter hinterher.
		var rel := wrapf(-_yaw, -PI, PI)
		_human.rig.look_yaw = rel if absf(rel) < 1.2 else 0.0
		_human.rig.mood = 0.35
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			_commit()


## Speichern (gebündelt, nicht bei jedem Regler-Schritt). Die Mitspieler sehen es beim Schließen.
func _commit() -> void:
	_dirty = 0.0
	SettingsManager.set_skin(look)
	_unsent = true
	look_changed.emit(look)


func _change(key: String, v: int, rebuild: bool = true) -> void:
	look[key] = v
	look = HumanModel.sanitize(look)
	_human.apply(look)
	_dirty = 0.5
	if rebuild:
		SfxManager.play("click", -12.0, 1.1)
		_show_tab(_tab)


# ------------------------------------------------------------------ Aufbau

func _build_ui() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	left.add_theme_constant_override("separation", 8)
	add_child(left)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(0, 360)
	frame.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.05, 0.06, 0.08, 0.96), UIStyle.COL_BORDER, 8, 1, 0, 0))
	left.add_child(frame)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.clip_contents = true
	overlay.gui_input.connect(_on_preview_input)
	frame.add_child(overlay)
	var vpc := SubViewportContainer.new()
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(vpc)
	_build_scene(vpc)
	var hint := Label.new()
	hint.text = "Ziehen dreht, Mausrad zoomt"
	hint.position = Vector2(12, 8)
	UIStyle.style_label(hint, 11, UIStyle.COL_TEXT_SUB)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	left.add_child(row)
	for e in [["wave", "Winken"], ["thumbs", "Daumen"], ["cheer", "Jubeln"], ["dance", "Tanzen"], ["clap", "Klatschen"]]:
		var b := _btn(str(e[1]), false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void: _human.rig.play(str(e[0])))
		row.add_child(b)
	var rnd := _btn("Zufällige Figur", false)
	rnd.pressed.connect(_randomize)
	left.add_child(rnd)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(430, 0)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	for t in TABS:
		var b := _btn(str(t[1]), false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void:
			SfxManager.play("click", -12.0, 1.0)
			_show_tab(str(t[0])))
		tabs.add_child(b)
		_tab_btns[str(t[0])] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 14)
	scroll.add_child(pad)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	pad.add_child(_page)


func _build_scene(vpc: SubViewportContainer) -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vpc.add_child(_vp)
	var sky_m := ProceduralSkyMaterial.new()
	sky_m.sky_top_color = Color(0.56, 0.64, 0.76)
	sky_m.sky_horizon_color = Color(0.86, 0.88, 0.92)
	sky_m.ground_horizon_color = Color(0.40, 0.40, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_m
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.105, 0.120, 0.145)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 32.0, 0.0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.96, 0.90)
	key.directional_shadow_max_distance = 8.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18.0, -150.0, 0.0)
	rim.light_energy = 0.75
	rim.light_color = Color(0.80, 0.88, 1.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.05
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var ped := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.50
	pc.bottom_radius = 0.54
	pc.height = 0.06
	pc.radial_segments = 64
	ped.mesh = pc
	ped.position.y = -0.03
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.17, 0.19, 0.23)
	pm.roughness = 0.4
	pm.metallic = 0.3
	ped.material_override = pm
	_pivot.add_child(ped)
	_human = HumanModel.create(look, true)
	_human.rotation.y = PI
	_pivot.add_child(_human)


func _btn(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = false
	if on:
		UIStyle.style_button(b, Color(0.74, 0.49, 0.12), Color(0.96, 0.72, 0.24))
	else:
		UIStyle.style_button(b, Color(0.11, 0.13, 0.17), Color(0.30, 0.34, 0.40))
	return b


func _show_tab(id: String) -> void:
	if id != _tab:
		_zoom = 0.0
	_tab = id
	for k in _tab_btns.keys():
		var b: Button = _tab_btns[k]
		if k == id:
			UIStyle.style_button(b, Color(0.74, 0.49, 0.12), Color(0.96, 0.72, 0.24))
		else:
			UIStyle.style_button(b, Color(0.11, 0.13, 0.17), Color(0.30, 0.34, 0.40))
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	match id:
		"body":
			_slider("Körpergröße", "height")
			_choice("Statur", "build", HumanModel.BUILD_NAMES)
			if int(look["build"]) > 0:
				_slider("Ausprägung", "amount")
			_slider("Figur (männlich – weiblich)", "fem")
			_colors("Hautton", "tone", HumanModel.TONES)
		"face":
			for k in HumanModel.FACE_KEYS:
				_slider(str(HumanModel.FACE_NAMES[k]), k)
			_colors("Augenfarbe", "eyes", HumanModel.EYES)
			_choice("Augenbrauen", "brows", HumanModel.BROW_NAMES)
		"hair":
			_choice("Frisur", "hair", HumanModel.HAIR_NAMES)
			_choice("Bart", "beard", HumanModel.BEARD_NAMES)
			_colors("Haarfarbe", "hair_col", HumanModel.HAIRS)
		"clothes":
			_choice("Oberteil", "top", HumanModel.TOP_NAMES)
			_colors("Farbe", "top_a", HumanModel.CLOTHES)
			_colors("Zweite Farbe", "top_b", HumanModel.CLOTHES)
			_choice("Hose", "bottom", HumanModel.BOTTOM_NAMES)
			_colors("Farbe", "bottom_a", HumanModel.CLOTHES)
			_choice("Schuhe", "shoes", HumanModel.SHOE_NAMES)
			_colors("Farbe", "shoe_a", HumanModel.CLOTHES)
		"extras":
			_choice("Kopf", "hat", HumanModel.HAT_NAMES)
			_choice("Brille", "glasses", HumanModel.GLASSES_NAMES)
			_colors("Farbe von Kappe, Mütze, Helm und Weste", "acc_a", HumanModel.CLOTHES)
			_head("Dabei")
			var g := _grid(3)
			for k in HumanModel.FLAGS:
				var on := int(look[k]) == 1
				var b := _btn(str(HumanModel.EXTRA_NAMES[k]), on)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.pressed.connect(func() -> void: _change(k, 0 if on else 1))
				g.add_child(b)
		"outfits":
			_outfits()


func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	UIStyle.style_label(l, 12, UIStyle.COL_TEXT_SUB)
	_page.add_child(l)


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	_page.add_child(g)
	return g


func _choice(title: String, key: String, names: Array) -> void:
	_head(title)
	var g := _grid(3)
	for i in names.size():
		var b := _btn(str(names[i]), int(look[key]) == i)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: _change(key, i))
		g.add_child(b)


func _colors(title: String, key: String, cols: Array) -> void:
	_head(title)
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 5)
	f.add_theme_constant_override("v_separation", 5)
	_page.add_child(f)
	for i in cols.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(SWATCH, SWATCH - 2)
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = cols[i]
			sb.set_corner_radius_all(6)
			var on := int(look[key]) == i
			sb.border_color = UIStyle.COL_GOLD_TEXT if on else (Color(0.8, 0.82, 0.85) if st == "hover" else Color(0.26, 0.30, 0.36))
			sb.set_border_width_all(3 if on else 1)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func() -> void: _change(key, i))
		f.add_child(b)


func _slider(title: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_page.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(170, 0)
	UIStyle.style_label(l, 12, UIStyle.COL_TEXT_SUB)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = int(look[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: _change(key, int(v), false))
	row.add_child(s)


func _outfits() -> void:
	_head("Fertige Kleidung anziehen")
	var g := _grid(4)
	for p in PRESETS:
		var b := _btn(str(p[0]), false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void:
			look.merge(p[1], true)
			_change("v", 2))
		g.add_child(b)
	_head("Eigene Outfits (mit Gesicht und Frisur)")
	for i in SettingsManager.MAX_OUTFITS:
		var o: Dictionary = SettingsManager.outfits[i] if i < SettingsManager.outfits.size() else {}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_page.add_child(row)
		var nm := LineEdit.new()
		nm.max_length = 20
		nm.text = str(o.get("name", ""))
		nm.placeholder_text = tr("Platz %d") % (i + 1)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIStyle.style_line_edit(nm)
		row.add_child(nm)
		var sv := _btn("Speichern", false)
		sv.pressed.connect(func() -> void:
			SettingsManager.save_outfit(i, nm.text if nm.text.strip_edges() != "" else tr("Outfit %d") % (i + 1), look)
			SfxManager.play("save", -12.0, 1.1)
			_show_tab("outfits"))
		row.add_child(sv)
		if not o.is_empty():
			var wear := _btn("Anziehen", true)
			wear.pressed.connect(func() -> void:
				look = HumanModel.sanitize(o["look"])
				_change("v", 2))
			row.add_child(wear)
			var del := _btn("✕", false)
			del.tooltip_text = "Outfit löschen"
			del.pressed.connect(func() -> void:
				SettingsManager.delete_outfit(i)
				_show_tab("outfits"))
			row.add_child(del)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(1.0, _zoom + 0.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(-0.6, _zoom - 0.12)
	elif event is InputEventMouseMotion and _dragging:
		_yaw = wrapf(_yaw + (event as InputEventMouseMotion).relative.x * 0.012, -PI, PI)


func _randomize() -> void:
	var keep := {"badge": look["badge"], "logo": look["logo"]}
	look = HumanModel.sanitize(HumanModel.random_look(randi()))
	look.merge(keep, true)
	_change("v", 2)
	_human.rig.play(["wave", "nod", "thumbs", "shrug"][randi() % 4])
