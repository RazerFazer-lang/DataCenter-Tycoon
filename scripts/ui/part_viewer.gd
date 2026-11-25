class_name PartViewer
extends Control
## Bauteil groß vor die Kamera nehmen: drehen, heranholen, Datenblatt, Strom, Last und Temperatur ausprobieren.
## Aufruf: PartViewer.open(irgendein Control, ["cpu_epyc_64c", ...])

const SPECS := {
	"cost": ["Preis", "$%d"], "cpu_score": ["Rechenleistung", "%d Punkte"], "gpu_score": ["Grafikleistung", "%d Punkte"], "compute": ["Compute", "%d CU"],
	"vram_gb": ["Grafikspeicher", "%d GB"], "ram_gb": ["Kapazität", "%d GB"], "ram_speed": ["Takt", "%d MT/s"], "storage_tb": ["Speicherplatz", "%.2f TB"],
	"io_score": ["Datenrate", "%d Punkte"], "cooling_bonus": ["Kühlleistung", "%.1f"], "psu_watts": ["Leistung", "%d W"], "efficiency": ["Wirkungsgrad", "%d %%"],
	"watts": ["Verbrauch", "%d W"], "heat": ["Abwärme", "%.1f"], "airflow": ["Luftstrom", "%d"],
}

var ids: Array = []
var index := 0
var _vp: SubViewport
var _pivot: Node3D
var _holder: Node3D
var _cam: Camera3D
var _fx: PartFx
var _yaw := 0.7
var _pitch := 0.45
var _dist := 1.0
var _dist_to := 1.0
var _spin := true
var _drag := false
var _info: VBoxContainer
var _title: Label
var _list: VBoxContainer
var _power := true
var _load := 0.4
var _temp := 35.0
var _dust := 0.0


static func open(from: Control, part_ids: Array, start: int = 0) -> PartViewer:
	var list: Array = part_ids.filter(func(p): return PartModels.has_product(str(p)))
	if list.is_empty():
		return null
	var v := PartViewer.new()
	v.ids = list
	v.index = clampi(start, 0, list.size() - 1)
	var layer := CanvasLayer.new()
	layer.layer = 90
	from.get_tree().root.add_child(layer)
	layer.add_child(v)
	v.tree_exited.connect(layer.queue_free)
	# Geht das Fenster dahinter zu, verschwindet auch die Ansicht.
	from.visibility_changed.connect(v._on_owner_hidden.bind(from))
	from.tree_exiting.connect(v.close)
	SfxManager.play("pickup", -8.0)
	return v


func _on_owner_hidden(from: Control) -> void:
	if not is_instance_valid(from) or not from.is_visible_in_tree():
		close()


func close() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 28)
	add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	m.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	if ids.size() > 1:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(190, 0)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		row.add_child(sc)
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(_list)
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.mouse_default_cursor_shape = Control.CURSOR_MOVE
	stage.gui_input.connect(_on_stage_input)
	row.add_child(stage)
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(_vp)
	build_studio(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_holder = Node3D.new()
	_pivot.add_child(_holder)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.01
	_vp.add_child(_cam)
	_cam.current = true
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(310, 0)
	side.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.07, 0.08, 0.10, 0.96), UIStyle.COL_BORDER, 10, 1, 18, 16))
	row.add_child(side)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	side.add_child(_info)
	_show(index)


## Studiolicht für Vorschau und Vorschaubilder.
static func build_studio(vp: SubViewport) -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.86, 0.96)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.55, 0.62, 0.72)
	ps.sky_horizon_color = Color(0.92, 0.94, 0.97)
	ps.ground_bottom_color = Color(0.10, 0.11, 0.13)
	ps.ground_horizon_color = Color(0.45, 0.48, 0.52)
	sky.sky_material = ps
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.glow_enabled = true
	e.glow_intensity = 0.5
	we.environment = e
	vp.add_child(we)
	for l in [[Vector3(-42, 38, 0), Color(1.0, 0.97, 0.92), 1.0, true], [Vector3(-18, -130, 0), Color(0.60, 0.74, 1.0), 0.55, false], [Vector3(30, 170, 0), Color(1.0, 0.85, 0.7), 0.25, false]]:
		var d := DirectionalLight3D.new()
		d.rotation_degrees = l[0]
		d.light_color = l[1]
		d.light_energy = l[2]
		d.shadow_enabled = l[3]
		vp.add_child(d)


static func bounds(n: Node, x: Transform3D = Transform3D.IDENTITY, out: Array = [null]) -> AABB:
	if n is Node3D:
		x = x * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a: AABB = x * (n as MeshInstance3D).mesh.get_aabb()
		out[0] = a if out[0] == null else (out[0] as AABB).merge(a)
	for c in n.get_children():
		bounds(c, x, out)
	return out[0] if out[0] != null else AABB(Vector3.ZERO, Vector3.ONE * 0.1)


func _show(i: int) -> void:
	index = i
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	var id := str(ids[i])
	var fans: Array = []
	var n := PartModels.product(id, fans)
	if n == null:
		return
	var b := bounds(n)
	n.position = -b.get_center()
	_holder.add_child(n)
	_holder.scale = Vector3.ONE * (1.0 / maxf(0.02, maxf(b.size.x, maxf(b.size.y, b.size.z))))
	_fx = PartFx.new()
	_holder.add_child(_fx)
	n.set_meta("part_cat", HardwareCatalog.find_part_category(id))
	_fx.attach(n, fans, true)
	_dist_to = 2.0
	_dist = 3.2
	_spin = true
	_fill_info(id)
	for c in _list.get_children():
		c.queue_free()
	for k in ids.size():
		var pd := HardwareCatalog.get_part(HardwareCatalog.find_part_category(str(ids[k])), str(ids[k]))
		var btn := Button.new()
		btn.text = str(pd.get("name", ids[k])).get_slice(" (", 0)
		btn.clip_text = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(180, 38)
		btn.icon = PartThumbs.get_texture(str(ids[k]))
		btn.expand_icon = true
		UIStyle.style_button(btn, Color(0.30, 0.23, 0.10, 0.97) if k == i else Color(0.13, 0.14, 0.16, 0.97))
		btn.pressed.connect(func():
			SfxManager.play("click", -12.0, 1.1)
			_show(k))
		_list.add_child(btn)


func _lbl(txt: String, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	UIStyle.style_label(l, size, col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _fill_info(id: String) -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var cat := HardwareCatalog.find_part_category(id)
	var pd := HardwareCatalog.get_part(cat, id)
	_info.add_child(_lbl(tr(str((HardwareCatalog.CATEGORY_META.get(cat, {}) as Dictionary).get("label", cat))), 11, UIStyle.COL_GOLD_TEXT))
	_info.add_child(_lbl(str(pd.get("name", id)), 18, UIStyle.COL_TEXT_MAIN, true))
	if str(pd.get("tag", "")) != "":
		_info.add_child(_lbl(tr(str(pd["tag"])), 12, UIStyle.COL_BLUE))
	_info.add_child(HSeparator.new())
	for k in SPECS.keys():
		if not pd.has(k) or (k != "cost" and float(pd[k]) <= 0.0):
			continue
		var r := HBoxContainer.new()
		var a := _lbl(tr(str(SPECS[k][0])), 13, UIStyle.COL_TEXT_SUB)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(a)
		var v: float = float(pd[k]) * (100.0 if k == "efficiency" and float(pd[k]) <= 1.5 else 1.0)
		var fmt := str(SPECS[k][1])
		r.add_child(_lbl(fmt % (int(roundf(v)) if fmt.contains("%d") else v), 13, UIStyle.COL_TEXT_MAIN))
		_info.add_child(r)
	if pd.has("fault_mult"):
		var r2 := HBoxContainer.new()
		var a2 := _lbl(tr("Zuverlässigkeit"), 13, UIStyle.COL_TEXT_SUB)
		a2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(a2)
		r2.add_child(_lbl("%d %%" % int(roundf(100.0 / maxf(0.2, float(pd["fault_mult"])))), 13, UIStyle.COL_TEXT_MAIN))
		_info.add_child(r2)
	var sb := HBoxContainer.new()
	var sl := _lbl(tr("Stärke"), 13, UIStyle.COL_TEXT_SUB)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_child(sl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.value = HardwareCatalog.get_part_strength_pct(cat, pd)
	sb.add_child(bar)
	_info.add_child(sb)
	var stock := GameState.get_part_stock(id)
	_info.add_child(_lbl(tr("Im Lager: %d×") % stock, 13, UIStyle.COL_GREEN if stock > 0 else UIStyle.COL_TEXT_SUB))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_child(sp)
	_info.add_child(HSeparator.new())
	var pw := CheckButton.new()
	pw.text = tr("Strom an")
	pw.button_pressed = _power
	pw.focus_mode = Control.FOCUS_NONE
	pw.toggled.connect(func(on: bool):
		_power = on
		SfxManager.play("switch_on" if on else "click", -10.0))
	_info.add_child(pw)
	_slider(tr("Last"), 0.0, 1.0, _load, func(v: float): _load = v)
	_slider(tr("Temperatur"), 25.0, 95.0, _temp, func(v: float): _temp = v)
	_slider(tr("Staub"), 0.0, 100.0, _dust, func(v: float): _dust = v)
	_info.add_child(_lbl(tr("Ziehen: drehen   Mausrad: heranholen   [ESC] zurück"), 11, UIStyle.COL_TEXT_SUB, true))
	var cb := Button.new()
	cb.text = tr("Zurücklegen")
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(0, 38)
	UIStyle.style_button(cb, Color(0.16, 0.18, 0.21))
	cb.pressed.connect(close)
	_info.add_child(cb)


func _slider(txt: String, lo: float, hi: float, v: float, cb: Callable) -> void:
	var r := HBoxContainer.new()
	var l := _lbl(txt, 12, UIStyle.COL_TEXT_SUB)
	l.custom_minimum_size = Vector2(92, 0)
	r.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = v
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	r.add_child(s)
	_info.add_child(r)


func _on_stage_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_drag = b.pressed
				_spin = false
			MOUSE_BUTTON_WHEEL_UP:
				_dist_to = maxf(0.85, _dist_to * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist_to = minf(4.0, _dist_to * 1.14)
	elif e is InputEventMouseMotion and _drag:
		var mo := e as InputEventMouseMotion
		_yaw += mo.relative.x * 0.009
		_pitch = clampf(_pitch + mo.relative.y * 0.009, -1.45, 1.45)


func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or (e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()
	elif e is InputEventKey and (e as InputEventKey).pressed and ids.size() > 1:
		var k := (e as InputEventKey).keycode
		if k == KEY_RIGHT or k == KEY_LEFT:
			get_viewport().set_input_as_handled()
			_show(posmod(index + (1 if k == KEY_RIGHT else -1), ids.size()))


func _process(delta: float) -> void:
	if _cam == null:
		return
	if _spin:
		_yaw += delta * 0.5
	_dist = lerpf(_dist, _dist_to, 1.0 - exp(-delta * 6.0))
	_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	_cam.position = Vector3(0.0, sin(_pitch), cos(_pitch)) * _dist
	_cam.look_at(Vector3.ZERO, Vector3.UP if absf(_pitch) < 1.4 else Vector3.BACK)
	if _fx != null and is_instance_valid(_fx):
		_fx.powered = _power
		_fx.load_f = _load
		_fx.temp = _temp
		_fx.dust = _dust
