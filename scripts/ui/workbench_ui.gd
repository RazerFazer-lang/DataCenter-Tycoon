class_name WorkbenchUI
extends Control
## Interaktive 3D-Werkbank-Station für realistischen Zusammenbau & Reparatur:
## - Frei dreh- & zoombare 3D-Ansicht des Servers auf der ESD-Matte mit automatischem Close-Up-Fokus
## - Realistische Einzelschritte pro Bauteil (RAM-Clips, 4 Kühler-Schrauben, Wärmeleitpaste halten,
##   PCIe-Verriegelung & 8-Pin-Stecker, M.2-Schraube, PWM-Stecker, 24-Pin/8-Pin PSU-Kabel)
## - Verbraucht passende Reparatur-Kits aus Hand/Lagerregal

signal close_requested

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model_holder: Node3D
var _overlay: Control
var _title_lbl: Label
var _sub_lbl: Label
var _step_list_box: VBoxContainer
var _action_btn: Button
var _action_hint: Label
var _kit_status_lbl: Label
var _paste_bar: ProgressBar
var _progress_lbl: Label

var _yaw: float = 0.42
var _pitch: float = -0.10
var _zoom: float = 0.96
var _target_yaw: float = 0.42
var _target_pitch: float = -0.10
var _target_zoom: float = 0.96
var _dragging: bool = false
var _click_travel: float = 0.0

var _mode: String = "" # "assembly" | "repair"
var _steps: Array = [] # Array of {id, label, cat, kind, sub_count, done_count, focus_yaw, focus_zoom}
var _cur_step: int = 0
var _paste_holding: bool = false
var _paste_progress: float = 0.0
var _assembled_cats: Dictionary = {} # cat -> true (für live 3D-Aufbau)
var _repair_removed_broken: bool = false
var _repair_installed_new: bool = false
var _part_nodes: Array = []
var _pulse_t: float = 0.0
var _highlight_mat: StandardMaterial3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	GameState.workbench_changed.connect(_on_workbench_changed)
	GameState.shelf_changed.connect(_refresh_kit_status)


func open_workbench() -> void:
	var wb := GameState.workbench_state
	var m := str(wb.get("mode", ""))
	if m != "assembly" and m != "repair":
		return
	_mode = m
	_cur_step = 0
	_paste_holding = false
	_paste_progress = 0.0
	_assembled_cats.clear()
	_repair_removed_broken = false
	_repair_installed_new = false
	_build_steps_for_current_state()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_focus_camera_for_current_step()
	_rebuild_3d_server()
	_refresh_panel()


func close_workbench() -> void:
	_paste_holding = false
	visible = false
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	close_requested.emit()


func _on_workbench_changed() -> void:
	if not visible:
		return
	var m := str(GameState.workbench_state.get("mode", ""))
	if m != "assembly" and m != "repair":
		close_workbench()


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_t += delta
	if _pivot != null:
		_yaw = lerpf(_yaw, _target_yaw, clampf(delta * 7.0, 0.0, 1.0))
		_pitch = lerpf(_pitch, _target_pitch, clampf(delta * 7.0, 0.0, 1.0))
		_zoom = lerpf(_zoom, _target_zoom, clampf(delta * 7.0, 0.0, 1.0))
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	if _cam != null:
		_cam.position = Vector3(0.0, 0.62, 0.88) * _zoom
	if _highlight_mat != null:
		_highlight_mat.albedo_color.a = 0.14 + 0.24 * absf(sin(_pulse_t * 4.2))

	# Wärmeleitpaste-Schritt: Maustaste gedrückt halten füllt sauber die Paste auf!
	if _paste_holding and _cur_step < _steps.size():
		var st: Dictionary = _steps[_cur_step]
		if str(st.get("kind", "")) == "paste":
			_paste_progress = clampf(_paste_progress + delta * 1.15, 0.0, 1.0)
			_paste_bar.value = _paste_progress * 100.0
			if _paste_progress >= 1.0:
				_paste_holding = false
				_advance_current_step()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.035, 0.048, 0.92)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	margin.add_child(root_v)

	# Kopfzeile
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root_v.add_child(top)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_v)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.modulate = UIStyle.COL_TEXT_MAIN
	title_v.add_child(_title_lbl)
	_sub_lbl = Label.new()
	_sub_lbl.add_theme_font_size_override("font_size", 12)
	_sub_lbl.modulate = UIStyle.COL_TEXT_SUB
	title_v.add_child(_sub_lbl)

	var close_b := Button.new()
	close_b.text = tr("Werkbank verlassen [ESC]")
	close_b.custom_minimum_size = Vector2(210, 38)
	close_b.pressed.connect(close_workbench)
	top.add_child(close_b)

	# Hauptbereich: Links 3D-ESD-Werkbank, Rechts Schritt-für-Schritt-Montage/Reparatur
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	root_v.add_child(split)

	var vp_frame := PanelContainer.new()
	vp_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_frame.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.06, 0.07, 0.09, 1.0), UIStyle.COL_ACCENT, 10, 1, 0, 0))
	split.add_child(vp_frame)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_3d_gui_input)
	vp_frame.add_child(_overlay)

	var vpc := SubViewportContainer.new()
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(vpc)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vpc.add_child(_vp)

	# Studio-Beleuchtung ueber der ESD-Matte
	var sky_m := ProceduralSkyMaterial.new()
	sky_m.sky_top_color = Color(0.58, 0.64, 0.72)
	sky_m.sky_horizon_color = Color(0.84, 0.87, 0.90)
	var sky := Sky.new()
	sky.sky_material = sky_m
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.095, 0.118)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -140.0, 0.0)
	fill.light_energy = 0.50
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 0.62, 0.88)
	_cam.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
	_cam.fov = 38.0
	_vp.add_child(_cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var bench := HardwareMeshFactory.build_preview_workbench()
	if bench != null:
		_pivot.add_child(bench)
	_model_holder = Node3D.new()
	_pivot.add_child(_model_holder)

	var cam_hint := Label.new()
	cam_hint.text = tr("Ziehen: Drehen  •  Mausrad: Zoomen  •  Klick auf markiertes Bauteil oder Aktion rechts")
	cam_hint.position = Vector2(14, 12)
	cam_hint.add_theme_font_size_override("font_size", 11)
	cam_hint.modulate = UIStyle.COL_GOLD_TEXT
	cam_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(cam_hint)

	# Rechte Spalte: Checkliste + interaktive Schritt-Ausfuehrung
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(390, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 10, 1, 16, 14))
	split.add_child(side)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	side.add_child(sv)

	_progress_lbl = Label.new()
	_progress_lbl.add_theme_font_size_override("font_size", 13)
	_progress_lbl.modulate = UIStyle.COL_ACCENT
	sv.add_child(_progress_lbl)

	_kit_status_lbl = Label.new()
	_kit_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kit_status_lbl.add_theme_font_size_override("font_size", 12)
	sv.add_child(_kit_status_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)
	_step_list_box = VBoxContainer.new()
	_step_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_step_list_box)

	_paste_bar = ProgressBar.new()
	_paste_bar.min_value = 0.0
	_paste_bar.max_value = 100.0
	_paste_bar.value = 0.0
	_paste_bar.custom_minimum_size = Vector2(0, 18)
	_paste_bar.visible = false
	sv.add_child(_paste_bar)

	_action_hint = Label.new()
	_action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_hint.add_theme_font_size_override("font_size", 12)
	_action_hint.modulate = UIStyle.COL_TEXT_SUB
	sv.add_child(_action_hint)

	_action_btn = Button.new()
	_action_btn.custom_minimum_size = Vector2(0, 52)
	_action_btn.add_theme_font_size_override("font_size", 15)
	_action_btn.button_down.connect(_on_action_btn_down)
	_action_btn.button_up.connect(_on_action_btn_up)
	sv.add_child(_action_btn)


func _on_3d_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_click_travel = 0.0
				if _cur_step < _steps.size() and str(_steps[_cur_step].get("kind", "")) == "paste":
					_paste_holding = true
			else:
				_paste_holding = false
				if _dragging and _click_travel <= 6.0:
					_on_3d_click()
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_zoom = clampf(_target_zoom * 0.9, 0.55, 1.45)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_zoom = clampf(_target_zoom / 0.9, 0.55, 1.45)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_click_travel += mm.relative.length()
		_target_yaw += mm.relative.x * 0.011
		_target_pitch = clampf(_target_pitch + mm.relative.y * 0.008, -0.45, 0.35)


func _on_3d_click() -> void:
	if _cur_step >= _steps.size():
		return
	var st: Dictionary = _steps[_cur_step]
	if str(st.get("kind", "")) == "paste":
		return
	if not _can_run_current_step():
		SfxManager.play("error", -8.0)
		return
	_trigger_step_click()


func _on_action_btn_down() -> void:
	if _cur_step >= _steps.size():
		return
	if not _can_run_current_step():
		SfxManager.play("error", -8.0)
		return
	var st: Dictionary = _steps[_cur_step]
	if str(st.get("kind", "")) == "paste":
		_paste_holding = true
	else:
		_trigger_step_click()


func _on_action_btn_up() -> void:
	_paste_holding = false


func _can_run_current_step() -> bool:
	if _mode == "repair":
		var fcat := _get_repair_cat()
		var st: Dictionary = _steps[_cur_step]
		if bool(st.get("needs_kit", false)) and GameState.count_repair_kits(fcat) <= 0:
			return false
	return true


func _trigger_step_click() -> void:
	var st: Dictionary = _steps[_cur_step]
	var sub_n := int(st.get("sub_count", 1))
	var done_n := int(st.get("done_count", 0)) + 1
	st["done_count"] = done_n
	SfxManager.play("snap" if done_n >= sub_n else "click", -8.0, 0.95 + float(done_n) * 0.08)
	if done_n >= sub_n:
		_advance_current_step()
	else:
		_refresh_panel()


func _advance_current_step() -> void:
	var st: Dictionary = _steps[_cur_step]
	var cat := str(st.get("cat", ""))
	var effect := str(st.get("effect", ""))
	if _mode == "assembly":
		if effect == "install_part" and not cat.is_empty():
			_assembled_cats[cat] = true
			_rebuild_3d_server()
	elif _mode == "repair":
		if effect == "remove_broken":
			_repair_removed_broken = true
			_rebuild_3d_server()
		elif effect == "install_new":
			_repair_installed_new = true
			_rebuild_3d_server()

	_cur_step += 1
	_paste_progress = 0.0
	_paste_bar.value = 0.0
	if _cur_step >= _steps.size():
		if _mode == "assembly":
			GameState.request_workbench_complete_assembly()
		elif _mode == "repair":
			GameState.request_workbench_complete_repair(_get_repair_cat())
		close_workbench()
		return
	_focus_camera_for_current_step()
	_refresh_panel()


func _get_repair_cat() -> String:
	var fcat := str(GameState.workbench_state.get("faulty_part", ""))
	return fcat if not fcat.is_empty() else "mainboard"


func _build_steps_for_current_state() -> void:
	_steps.clear()
	var wb := GameState.workbench_state
	var comps: Dictionary = wb.get("components", {}) as Dictionary

	if _mode == "assembly":
		_steps.append({"label": tr("Mainboard ins Chassis einsetzen"), "cat": "mainboard", "effect": "install_part", "sub_count": 1, "done_count": 0, "focus_yaw": 0.42, "focus_zoom": 0.96})
		_steps.append({"label": tr("Mainboard-Schrauben festziehen (4 Schrauben)"), "cat": "mainboard", "sub_count": 4, "done_count": 0, "focus_yaw": 0.42, "focus_zoom": 0.88})
		if not str(comps.get("cpu", "")).is_empty():
			_steps.append({"label": tr("CPU-Sockelhebel öffnen & CPU einsetzen"), "cat": "cpu", "sub_count": 2, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.72})
			_steps.append({"label": tr("Wärmeleitpaste auftragen (gedrückt halten)"), "cat": "cpu", "kind": "paste", "sub_count": 1, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.68})
			_steps.append({"label": tr("CPU-Kühler aufsetzen & 4 Schrauben anziehen"), "cat": "cpu", "effect": "install_part", "sub_count": 4, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.74})
		if not str(comps.get("ram", "")).is_empty():
			_steps.append({"label": tr("RAM-Halteclips öffnen & Riegel einsetzen"), "cat": "ram", "effect": "install_part", "sub_count": 2, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.74})
			_steps.append({"label": tr("RAM-Clips oben & unten einrasten"), "cat": "ram", "sub_count": 2, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.74})
		if not str(comps.get("storage", "")).is_empty():
			_steps.append({"label": tr("M.2 NVMe SSD einsetzen & festschrauben"), "cat": "storage", "effect": "install_part", "sub_count": 2, "done_count": 0, "focus_yaw": 0.40, "focus_zoom": 0.76})
		if not str(comps.get("gpu", "")).is_empty():
			_steps.append({"label": tr("PCIe-Clip öffnen & Grafikkarte einsetzen"), "cat": "gpu", "effect": "install_part", "sub_count": 2, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.78})
			_steps.append({"label": tr("GPU-Slot-Schraube & 8-Pin-Stromkabel anstecken"), "cat": "gpu", "sub_count": 2, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.78})
		if not str(comps.get("cooling", "")).is_empty():
			_steps.append({"label": tr("Lüfterwand einsetzen & PWM-Kabel verbinden"), "cat": "cooling", "effect": "install_part", "sub_count": 2, "done_count": 0, "focus_yaw": 0.15, "focus_zoom": 0.86})
		if not str(comps.get("psu", "")).is_empty():
			_steps.append({"label": tr("Netzteil verschrauben & 24-Pin/8-Pin anstecken"), "cat": "psu", "effect": "install_part", "sub_count": 3, "done_count": 0, "focus_yaw": 0.82, "focus_zoom": 0.84})
	else:
		var fcat := _get_repair_cat()
		match fcat:
			"ram":
				_steps.append({"label": tr("RAM-Halteclips an beiden Enden umklippen"), "cat": "ram", "sub_count": 2, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.72})
				_steps.append({"label": tr("Defekte RAM-Riegel herausziehen"), "cat": "ram", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.72})
				_steps.append({"label": tr("Neues RAM-Reparatur-Kit einsetzen"), "cat": "ram", "effect": "install_new", "needs_kit": true, "sub_count": 1, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.72})
				_steps.append({"label": tr("RAM-Halteclips wieder einrasten"), "cat": "ram", "sub_count": 2, "done_count": 0, "focus_yaw": 0.55, "focus_zoom": 0.72})
			"cpu":
				_steps.append({"label": tr("4 Kühler-Schrauben über Kreuz lösen"), "cat": "cpu", "sub_count": 4, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.70})
				_steps.append({"label": tr("CPU-Kühler abnehmen & Sockel-Hebel öffnen"), "cat": "cpu", "sub_count": 2, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.70})
				_steps.append({"label": tr("Defekte CPU herausnehmen"), "cat": "cpu", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.68})
				_steps.append({"label": tr("Neues CPU-Kit einsetzen & Hebel schließen"), "cat": "cpu", "effect": "install_new", "needs_kit": true, "sub_count": 2, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.68})
				_steps.append({"label": tr("Frische Wärmeleitpaste auftragen (halten)"), "cat": "cpu", "kind": "paste", "sub_count": 1, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.66})
				_steps.append({"label": tr("Kühler aufsetzen & 4 Schrauben anziehen"), "cat": "cpu", "sub_count": 4, "done_count": 0, "focus_yaw": 0.30, "focus_zoom": 0.72})
			"gpu":
				_steps.append({"label": tr("8-Pin-Stromstecker von der GPU abziehen"), "cat": "gpu", "sub_count": 1, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.76})
				_steps.append({"label": tr("Slot-Schraube lösen & PCIe-Clip öffnen"), "cat": "gpu", "sub_count": 2, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.76})
				_steps.append({"label": tr("Defekte Grafikkarte herausziehen"), "cat": "gpu", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.76})
				_steps.append({"label": tr("Neues GPU-Kit einsetzen & verschrauben"), "cat": "gpu", "effect": "install_new", "needs_kit": true, "sub_count": 2, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.76})
				_steps.append({"label": tr("8-Pin-Stromkabel wieder einstecken"), "cat": "gpu", "sub_count": 1, "done_count": 0, "focus_yaw": -0.35, "focus_zoom": 0.76})
			"storage":
				_steps.append({"label": tr("M.2-Halteschraube lösen"), "cat": "storage", "sub_count": 1, "done_count": 0, "focus_yaw": 0.40, "focus_zoom": 0.72})
				_steps.append({"label": tr("Defekte M.2 NVMe SSD herausziehen"), "cat": "storage", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": 0.40, "focus_zoom": 0.72})
				_steps.append({"label": tr("Neues SSD-Kit einsetzen & festschrauben"), "cat": "storage", "effect": "install_new", "needs_kit": true, "sub_count": 2, "done_count": 0, "focus_yaw": 0.40, "focus_zoom": 0.72})
			"cooling":
				_steps.append({"label": tr("PWM-Kabel abziehen & Verriegelung öffnen"), "cat": "cooling", "sub_count": 2, "done_count": 0, "focus_yaw": 0.12, "focus_zoom": 0.82})
				_steps.append({"label": tr("Defekte Lüfterwand herausziehen"), "cat": "cooling", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": 0.12, "focus_zoom": 0.82})
				_steps.append({"label": tr("Neues Kühlungs-Kit einsetzen & PWM anstecken"), "cat": "cooling", "effect": "install_new", "needs_kit": true, "sub_count": 2, "done_count": 0, "focus_yaw": 0.12, "focus_zoom": 0.82})
			"psu":
				_steps.append({"label": tr("24-Pin ATX & 8-Pin EPS Kabel abziehen"), "cat": "psu", "sub_count": 2, "done_count": 0, "focus_yaw": 0.82, "focus_zoom": 0.82})
				_steps.append({"label": tr("4 Netzteil-Schrauben lösen & Netzteil ziehen"), "cat": "psu", "effect": "remove_broken", "sub_count": 4, "done_count": 0, "focus_yaw": 0.82, "focus_zoom": 0.82})
				_steps.append({"label": tr("Neues Netzteil-Kit einsetzen & verschrauben"), "cat": "psu", "effect": "install_new", "needs_kit": true, "sub_count": 2, "done_count": 0, "focus_yaw": 0.82, "focus_zoom": 0.82})
				_steps.append({"label": tr("24-Pin ATX & 8-Pin EPS wieder anstecken"), "cat": "psu", "sub_count": 2, "done_count": 0, "focus_yaw": 0.82, "focus_zoom": 0.82})
			_:
				_steps.append({"label": tr("Steckverbindungen & 4 Mainboard-Schrauben lösen"), "cat": "mainboard", "sub_count": 4, "done_count": 0, "focus_yaw": 0.42, "focus_zoom": 0.90})
				_steps.append({"label": tr("Verkohltes Mainboard ausbauen"), "cat": "mainboard", "effect": "remove_broken", "sub_count": 1, "done_count": 0, "focus_yaw": 0.42, "focus_zoom": 0.90})
				_steps.append({"label": tr("Neues Mainboard-Kit einsetzen & verschrauben"), "cat": "mainboard", "effect": "install_new", "needs_kit": true, "sub_count": 4, "done_count": 0, "focus_yaw": 0.42, "focus_zoom": 0.90})


func _focus_camera_for_current_step() -> void:
	if _cur_step < _steps.size():
		var st: Dictionary = _steps[_cur_step]
		_target_yaw = float(st.get("focus_yaw", 0.42))
		_target_zoom = float(st.get("focus_zoom", 0.88))
		_target_pitch = -0.10


func _rebuild_3d_server() -> void:
	if _vp == null or _model_holder == null:
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for c in _model_holder.get_children():
		c.queue_free()
	_part_nodes.clear()

	var wb := GameState.workbench_state
	var mb_id := str(wb.get("mainboard_id", "web_server"))
	var full_comps: Dictionary = wb.get("components", {}) as Dictionary
	var shown_comps: Dictionary = {}
	var brk := ""

	if _mode == "assembly":
		for cat_v in GameState.COMPONENT_ORDER:
			var cat := str(cat_v)
			if _assembled_cats.has(cat):
				shown_comps[cat] = full_comps.get(cat, "")
	else:
		var fcat := _get_repair_cat()
		for cat_v in GameState.COMPONENT_ORDER:
			var cat := str(cat_v)
			if cat == fcat and _repair_removed_broken and not _repair_installed_new:
				continue
			shown_comps[cat] = full_comps.get(cat, "")
		if not _repair_removed_broken and not _repair_installed_new:
			brk = fcat

	var srv := HardwareMeshFactory.build_open_server_chassis(mb_id, shown_comps, [], brk)
	_model_holder.add_child(srv)
	_collect_parts(srv)
	_apply_step_highlight()


func _collect_parts(n: Node) -> void:
	if n.has_meta("part_cat"):
		_part_nodes.append(n)
	for c in n.get_children():
		_collect_parts(c)


func _apply_step_highlight() -> void:
	if _cur_step >= _steps.size():
		return
	var target_cat := str(_steps[_cur_step].get("cat", ""))
	if _highlight_mat == null:
		_highlight_mat = StandardMaterial3D.new()
		_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.albedo_color = Color(0.98, 0.24, 0.14, 0.28) if _mode == "repair" else Color(0.18, 0.78, 0.98, 0.28)
	for pn in _part_nodes:
		if is_instance_valid(pn) and str((pn as Node).get_meta("part_cat", "")) == target_cat:
			_set_overlay(pn as Node, _highlight_mat)


func _set_overlay(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = mat
	for c in n.get_children():
		if c.has_meta("part_cat"):
			continue
		_set_overlay(c, mat)


func _refresh_kit_status() -> void:
	if _kit_status_lbl == null:
		return
	if _mode != "repair":
		_kit_status_lbl.visible = false
		return
	_kit_status_lbl.visible = true
	var fcat := _get_repair_cat()
	var kid := GameState.get_repair_kit_id_for_cat(fcat)
	var kname := str(GameState.ITEM_CATALOG.get(kid, {}).get("name", "Reparatur-Kit"))
	var n := GameState.count_repair_kits(fcat)
	if n > 0:
		_kit_status_lbl.text = tr("✓ Benötigtes Kit verfügbar: %s (%d× im Lager/Hand)") % [kname, n]
		_kit_status_lbl.modulate = UIStyle.COL_GREEN
	else:
		_kit_status_lbl.text = tr("⚠ Fehlt: %s! Kaufe es am PC-Shop (Tab „Reparatur-Kits“) und stelle es ins Lagerregal.") % kname
		_kit_status_lbl.modulate = UIStyle.COL_RED


func _refresh_panel() -> void:
	var wb := GameState.workbench_state
	var lbl := str(wb.get("label", "Server"))
	if _mode == "assembly":
		_title_lbl.text = tr("IT-Werkbank · Zusammenbau (%s)") % lbl
		_sub_lbl.text = tr("Baue alle gelieferten Komponenten Schritt für Schritt ins Server-Chassis ein.")
	else:
		var fcat := _get_repair_cat()
		_title_lbl.text = tr("IT-Werkbank · Reparatur (%s)") % lbl
		_sub_lbl.text = tr("Defektes Bauteil: %s — ausbauen, mit Reparatur-Kit tauschen & wieder sichern.") % GameState.get_component_label(fcat)

	_progress_lbl.text = tr("SCHRITT %d / %d") % [mini(_cur_step + 1, _steps.size()), _steps.size()]
	_refresh_kit_status()

	for c in _step_list_box.get_children():
		c.queue_free()
	for i in range(_steps.size()):
		var st: Dictionary = _steps[i]
		var row := PanelContainer.new()
		var done := i < _cur_step
		var active := i == _cur_step
		row.add_theme_stylebox_override("panel", UIStyle.make_panel(
			Color(0.10, 0.24, 0.16, 0.85) if done else (Color(0.14, 0.20, 0.30, 0.95) if active else Color(0.08, 0.09, 0.11, 0.70)),
			UIStyle.COL_GREEN if done else (UIStyle.COL_ACCENT if active else UIStyle.COL_BORDER),
			6, 1, 10, 6
		))
		_step_list_box.add_child(row)
		var l := Label.new()
		var prefix := "✓ " if done else ("▶ " if active else "○ ")
		var sub_n := int(st.get("sub_count", 1))
		var done_n := int(st.get("done_count", 0))
		var suffix := (" (%d/%d)" % [done_n, sub_n]) if (active and sub_n > 1) else ""
		l.text = prefix + str(st["label"]) + suffix
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		l.modulate = UIStyle.COL_GREEN if done else (UIStyle.COL_TEXT_MAIN if active else UIStyle.COL_TEXT_SUB)
		row.add_child(l)

	if _cur_step < _steps.size():
		var cur: Dictionary = _steps[_cur_step]
		var is_paste := str(cur.get("kind", "")) == "paste"
		_paste_bar.visible = is_paste
		var can_run := _can_run_current_step()
		_action_btn.disabled = not can_run
		if is_paste:
			_action_btn.text = tr("Wärmeleitpaste auftragen (gedrückt halten)")
			_action_hint.text = tr("Halte die Maustaste auf diesem Button oder der CPU gedrückt, bis die Paste verteilt ist.")
		else:
			var sub_n := int(cur.get("sub_count", 1))
			var done_n := int(cur.get("done_count", 0))
			_action_btn.text = (tr("%s (%d/%d)") % [str(cur["label"]), done_n, sub_n]) if sub_n > 1 else str(cur["label"])
			_action_hint.text = tr("Klicke hier oder direkt auf das markierte 3D-Bauteil.") if can_run else tr("Kaufe zuerst das benötigte Reparatur-Kit im PC-Shop!")
	_apply_step_highlight()
