class_name WorkbenchUI
extends Control
## Arbeitsplatz an der echten Werkbank: Die Kamera fährt über die ESD-Matte, Teile werden mit der Maus
## gegriffen und eingesetzt, Schrauben, Hebel, Stecker und Paste einzeln von Hand erledigt.
## Das Bild kommt direkt aus der Spielwelt; diese Oberfläche zeigt nur Werkzeugleiste und Hinweise.

signal close_requested

const CAM_TIME := 0.60
const VIEW_FOV := 53.0
const VIEW_POS := Vector3(0.09, 0.82, 0.80)     # relativ zur Mattenoberkante
const VIEW_LOOK := Vector3(0.10, 0.03, 0.065)
const TOOL_VIEW_POS := Vector3(0.03, 0.62, 0.55)
const TOOL_VIEW_LOOK := Vector3(0.03, 0.05, 0.055)
const PICK_PX := 30.0
const SNAP_IN := 0.045
const SNAP_OUT := 0.085
const DRAG_H := 0.17
const SEND_INTERVAL := 0.07

const TOOL_LABELS := [
	["", "1", "Hand"],
	[AssemblyPlan.TOOL_DRIVER, "2", "Schraubendreher"],
	[AssemblyPlan.TOOL_PASTE, "3", "Leitpaste"],
	[AssemblyPlan.TOOL_TWEEZERS, "4", "Pinzette"],
	[AssemblyPlan.TOOL_METER, "5", "Messgerät"],
]

var prop: WorkbenchProp
var piece: WorkbenchPiece

var _cam: Camera3D
var _cam_from: Transform3D
var _cam_from_fov: float = 75.0
var _cam_t: float = 0.0
var _zoom: float = 1.0
var _orbit: Vector2 = Vector2.ZERO
var _pan: Vector2 = Vector2.ZERO
var _orbiting: bool = false
var _tool_blend: float = 0.0

var _tool: String = ""
var _mouse: Vector2 = Vector2.ZERO
var _lmb: bool = false
var _cand: Dictionary = {}          # {task, item, ok, reason}
var _action: Dictionary = {}        # laufender Handgriff: {task, item, kind, t, phase, ...}
var _tick_accum: float = 0.0
var _send_accum: float = 0.0
var _guide: bool = true
var _toast_left: float = 0.0
var _live_ok_until: int = 0          # bis dahin gilt die Bestätigung "trotz Strom"
var _lid_ok_until: int = 0
var _last_next: String = ""

var _title_lbl: Label
var _bar: ProgressBar
var _step_lbl: Label
var _hint_lbl: Label
var _toast_lbl: Label
var _ring: Control
var _ring_value: float = -1.0
var _ring_color: Color = Color(0.4, 0.8, 1.0)
var _tool_btns: Array[Button] = []
var _supply_lbl: Label
var _diag_panel: PanelContainer
var _diag_code: Label
var _diag_text: RichTextLabel
var _diag_sig: String = ""
var _choose_panel: PanelContainer
var _choose_list: VBoxContainer
var _choose_sig: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	GameState.workbench_changed.connect(_on_workbench_changed)
	GameState.event_logged.connect(_on_event)
	GameState.bench_supplies_changed.connect(_refresh_panel)
	GameState.inventory_changed.connect(_refresh_panel)
	GameState.shelf_changed.connect(_refresh_panel)


# ------------------------------------------------------------------ Öffnen / Schließen

func open_workbench() -> void:
	var wb := GameState.workbench_state
	if not GameState.is_workbench_job():
		return
	var who := GameState.get_workbench_worker()
	if who > 0 and who != multiplayer.get_unique_id():
		return
	prop = get_tree().get_first_node_in_group("workbench") as WorkbenchProp
	if prop == null or prop.piece.is_empty():
		return
	piece = prop.piece
	_tool = ""
	_cand = {}
	_action = {}
	_lmb = false
	_zoom = 1.0
	_orbit = Vector2.ZERO
	_pan = Vector2.ZERO
	_tool_blend = 0.0
	_cam_t = 0.0
	_last_next = ""
	_toast_lbl.text = ""
	var cur := get_viewport().get_camera_3d()
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.near = 0.03
		prop.add_child(_cam)
	_cam_from = cur.global_transform if cur != null else _view_xf()
	_cam_from_fov = cur.fov if cur != null else VIEW_FOV
	_cam.global_transform = _cam_from
	_cam.fov = _cam_from_fov
	_cam.make_current()
	visible = true
	_mouse = get_viewport().get_mouse_position()
	GameState.request_workbench_enter()
	SfxManager.play("pickup", -12.0)
	_refresh_panel()


func close_workbench() -> void:
	if not visible:
		return
	_cancel_action()
	if is_instance_valid(piece):
		piece.set_highlight([])
		piece.clear_ghost()
		piece.held_tool = ""
		piece.tool_active = false
		piece.wake()
	visible = false
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	GameState.send_workbench_hand({})
	GameState.request_workbench_leave()
	close_requested.emit()


func _on_workbench_changed() -> void:
	if not visible:
		return
	var who := GameState.get_workbench_worker()
	if not GameState.is_workbench_job():
		close_workbench()
		return
	if who > 0 and who != multiplayer.get_unique_id():
		close_workbench()
		return
	_refresh_panel()


func _on_event(message: String, severity: String) -> void:
	if visible and (severity == "alert" or severity == "warn"):
		_show_toast(message, true)


func _show_toast(text: String, warn: bool = false) -> void:
	_toast_lbl.text = text
	_toast_lbl.modulate = UIStyle.COL_AMBER if warn else UIStyle.COL_TEXT_MAIN
	_toast_left = 2.6


# ------------------------------------------------------------------ Oberfläche

func _build_ui() -> void:
	_ring = Control.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.06, 0.065, 0.075, 0.86), UIStyle.COL_BORDER, 8, 1, 16, 8))
	top.offset_left = 18
	top.offset_right = 400
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_theme_constant_override("separation", 5)
	top.add_child(tv)
	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 15)
	_title_lbl.modulate = UIStyle.COL_TEXT_MAIN
	tv.add_child(_title_lbl)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_bar)
	_supply_lbl = Label.new()
	_supply_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_supply_lbl.add_theme_font_size_override("font_size", 11)
	_supply_lbl.modulate = UIStyle.COL_TEXT_SUB
	tv.add_child(_supply_lbl)

	# Prüfgerät: POST-Code und Messwerte zum Ablesen
	_diag_panel = PanelContainer.new()
	_diag_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.02, 0.045, 0.05, 0.92), Color(0.20, 0.45, 0.42), 8, 1, 14, 10))
	_diag_panel.offset_left = 18
	_diag_panel.offset_right = 300
	_diag_panel.offset_top = 100
	_diag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diag_panel.visible = false
	add_child(_diag_panel)
	var dv := VBoxContainer.new()
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dv.add_theme_constant_override("separation", 4)
	_diag_panel.add_child(dv)
	_diag_code = Label.new()
	_diag_code.add_theme_font_size_override("font_size", 24)
	dv.add_child(_diag_code)
	_diag_text = RichTextLabel.new()
	_diag_text.bbcode_enabled = true
	_diag_text.fit_content = true
	_diag_text.scroll_active = false
	_diag_text.custom_minimum_size = Vector2(254, 0)
	_diag_text.add_theme_font_size_override("normal_font_size", 12)
	_diag_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dv.add_child(_diag_text)

	# Ersatzteil-Auswahl (erscheint nur, wenn sie dran ist)
	_choose_panel = PanelContainer.new()
	_choose_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.06, 0.065, 0.075, 0.94), UIStyle.COL_ACCENT, 8, 1, 14, 12))
	_choose_panel.anchor_left = 1.0
	_choose_panel.anchor_right = 1.0
	_choose_panel.offset_left = -366
	_choose_panel.offset_right = -18
	_choose_panel.offset_top = 70
	_choose_panel.offset_bottom = 480
	_choose_panel.visible = false
	add_child(_choose_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_choose_panel.add_child(cv)
	var ch := Label.new()
	ch.text = tr("Ersatzteil wählen")
	ch.add_theme_font_size_override("font_size", 16)
	ch.modulate = UIStyle.COL_GOLD_TEXT
	cv.add_child(ch)
	var cs := ScrollContainer.new()
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(cs)
	_choose_list = VBoxContainer.new()
	_choose_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choose_list.add_theme_constant_override("separation", 6)
	cs.add_child(_choose_list)

	var close_b := Button.new()
	close_b.text = tr("Werkbank verlassen [ESC]")
	close_b.anchor_left = 1.0
	close_b.anchor_right = 1.0
	close_b.offset_left = -236
	close_b.offset_right = -18
	close_b.offset_top = 18
	close_b.offset_bottom = 54
	close_b.focus_mode = Control.FOCUS_NONE
	UIStyle.style_button(close_b)
	close_b.pressed.connect(close_workbench)
	add_child(close_b)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.06, 0.065, 0.075, 0.88), UIStyle.COL_BORDER, 8, 1, 18, 10))
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -420
	bottom.offset_right = 420
	bottom.offset_top = -116
	bottom.offset_bottom = -10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	_step_lbl = Label.new()
	_step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_lbl.add_theme_font_size_override("font_size", 17)
	_step_lbl.modulate = UIStyle.COL_GOLD_TEXT
	bv.add_child(_step_lbl)
	_hint_lbl = Label.new()
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.modulate = UIStyle.COL_TEXT_SUB
	bv.add_child(_hint_lbl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(row)
	for t in TOOL_LABELS:
		var b := Button.new()
		b.text = "[%s] %s" % [t[1], _tool_label(str(t[0]))]
		b.custom_minimum_size = Vector2(150, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		var tid := str(t[0])
		b.pressed.connect(func(): _select_tool(tid))
		row.add_child(b)
		_tool_btns.append(b)

	_toast_lbl = Label.new()
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.anchor_left = 0.0
	_toast_lbl.anchor_right = 1.0
	_toast_lbl.anchor_top = 1.0
	_toast_lbl.anchor_bottom = 1.0
	_toast_lbl.offset_top = -152
	_toast_lbl.offset_bottom = -126
	_toast_lbl.add_theme_font_size_override("font_size", 14)
	_toast_lbl.add_theme_constant_override("outline_size", 5)
	_toast_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03))
	_toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_lbl)


func _task_label(task: Dictionary) -> String:
	var s := tr(str(task["label"]))
	if task.has("label_arg"):
		s = s % tr(str(task["label_arg"]))
	return s


func _tool_label(tool_id: String) -> String:
	match tool_id:
		AssemblyPlan.TOOL_DRIVER:
			if GameState.has_bench_tool("torque"):
				return tr("Drehmoment-Akku")
			if GameState.has_bench_tool("akku"):
				return tr("Akkuschrauber")
		AssemblyPlan.TOOL_PASTE:
			if GameState.has_bench_tool("paste_gun"):
				return tr("Dosierpistole")
		AssemblyPlan.TOOL_METER:
			if GameState.has_bench_tool("meter_pro"):
				return tr("Profi-Multimeter")
	for t in TOOL_LABELS:
		if str(t[0]) == tool_id:
			return tr(str(t[2]))
	return ""


func _tool_key(tool_id: String) -> String:
	for t in TOOL_LABELS:
		if str(t[0]) == tool_id:
			return str(t[1])
	return ""


func _refresh_panel() -> void:
	if piece == null or piece.plan.is_empty():
		return
	var wb := GameState.workbench_state
	if not visible:
		return
	var total := AssemblyPlan.count_total(piece.plan)
	var n := AssemblyPlan.count_done(piece.plan, piece.done)
	var pm := str(piece.plan["mode"])
	var head := tr("ZUSAMMENBAU") if pm == "assembly" else (tr("REPARATUR") if pm == "repair" else tr("ÜBERHOLUNG"))
	_title_lbl.text = "%s  ·  %s  ·  %d / %d" % [head, str(wb.get("label", "Server")), n, total]
	_bar.max_value = maxf(1.0, float(total))
	_bar.value = float(n)
	_supply_lbl.text = tr("Schrauben: %d  •  Wärmeleitpaste: %.1f") % [GameState.bench_screws, GameState.bench_paste]
	_supply_lbl.modulate = UIStyle.COL_AMBER if (GameState.bench_screws < 12 or GameState.bench_paste < 1.0) else UIStyle.COL_TEXT_SUB
	_refresh_choose()
	var nt := AssemblyPlan.next_task(piece.plan, piece.done)
	if nt.is_empty():
		_step_lbl.text = ""
	else:
		var same := 0
		var same_done := 0
		for t in piece.plan["tasks"]:
			if t["group"] == nt["group"] and str(t.get("label_arg", "")) == str(nt.get("label_arg", "")):
				same += 1
				if piece.done.has(t["id"]):
					same_done += 1
		_step_lbl.text = _task_label(nt) + ("  (%d/%d)" % [same_done, same] if same > 1 else "")
		if str(nt["kind"]) == "measure":
			_step_lbl.text = tr(AssemblyPlan.LBL_MEASURE) + "  " + tr("(%d geprüft)") % same_done
		if GameState.needs_workbench_replacement() and str(nt["id"]) == "cpu_place":
			_step_lbl.text = tr("CPU zerstört – rechts eine neue wählen")
		elif bool(nt["kit"]) and not piece._kit_available():
			_step_lbl.text = tr("Ersatzteil fehlt: %s im PC-Shop kaufen") % _kit_name()
	for i in range(_tool_btns.size()):
		var tid := str(TOOL_LABELS[i][0])
		var sel := tid == _tool
		_tool_btns[i].text = "[%s] %s" % [TOOL_LABELS[i][1], _tool_label(tid)]
		UIStyle.style_button(_tool_btns[i], Color(0.30, 0.23, 0.10, 0.97) if sel else Color(0.165, 0.170, 0.182, 0.97))
	_update_highlight(nt)


func _update_diag_panel() -> void:
	var info := piece.screen_info
	var show: bool = bool(info.get("cable", false))
	_diag_panel.visible = show
	if not show:
		_diag_sig = ""
		return
	var sus := piece.suspects()
	var sig := "%s|%s|%s|%d" % [str(info), str(sus), str(piece.done.keys()), int(piece.is_post_finished())]
	if sig == _diag_sig:
		return
	_diag_sig = sig
	_diag_code.text = "POST  %s" % str(info["code"])
	_diag_code.modulate = info["color"]
	var lines := PackedStringArray()
	lines.append(str(info["msg"]))
	var on_leds: Array = info["leds"]
	if not on_leds.is_empty():
		lines.append(tr("Q-LED: %s") % ", ".join(PackedStringArray(on_leds)))
	if not sus.is_empty():
		var names := PackedStringArray()
		for c in sus:
			names.append(GameState.get_component_label(str(c)))
		lines.append("[color=#f0c060]" + tr("Verdacht: %s") % ", ".join(names) + "[/color]")
	for t in piece.plan["tasks"]:
		if str(t["kind"]) == "measure" and piece.done.has(t["id"]):
			var r := AssemblyPlan.reading(piece.plan, str(t["cat"]))
			var col := "#6fe08a" if bool(r["ok"]) else ("#f0c060" if bool(r["weak"]) else "#ff6a55")
			lines.append("[color=%s]%s: %s[/color]" % [col, tr(str(r["name"])), str(r["text"])])
	_diag_text.text = "\n".join(lines)


## Auswahlliste: passendes Reparatur-Kit und alle passenden Teile aus dem Teile-Lager.
func _refresh_choose() -> void:
	var show := false
	var rcat := str(piece.plan.get("repair_cat", ""))
	if str(piece.plan["mode"]) == "repair" and (piece.plan["by_id"] as Dictionary).has("choose"):
		show = AssemblyPlan.is_available(piece.plan, piece.done, "choose") \
			or (piece.done.has("choose") and not AssemblyPlan.is_choice_locked(piece.plan, piece.done))
	if GameState.needs_workbench_replacement():
		show = true
		rcat = "cpu"
	_choose_panel.visible = show
	if not show:
		_choose_sig = ""
		return
	var spare := AssemblyPlan.spare_of(GameState.workbench_state)
	var kits := GameState.count_repair_kits(GameState.get_workbench_kit_cat())
	var sig := "%s|%s|%d|%s" % [rcat, str(spare), kits, str(GameState.parts_inventory)]
	if sig == _choose_sig:
		return
	_choose_sig = sig
	for c in _choose_list.get_children():
		c.queue_free()
	var kid := GameState.get_workbench_kit_id()
	_add_choice(tr(str((GameState.ITEM_CATALOG.get(kid, {}) as Dictionary).get("name", "Reparatur-Kit"))),
		tr("Standard-Ersatz, Server bleibt wie er war  •  %d vorhanden") % kits, kits > 0,
		str(spare.get("kind", "")) == AssemblyPlan.SPARE_KIT, AssemblyPlan.SPARE_KIT)
	var found := 0
	if AssemblyPlan.accepts_parts(rcat):
		var cur_id := str((GameState.workbench_state.get("components", {}) as Dictionary).get(rcat, ""))
		for pd_v in HardwareCatalog.get_category_parts(rcat):
			var pd: Dictionary = pd_v
			var pid := str(pd["id"])
			var stock := int(GameState.parts_inventory.get(pid, 0))
			if stock <= 0 or (rcat == "gpu" and int(pd.get("vtier", 0)) <= 0):
				continue
			found += 1
			var note := tr("gleiches Modell") if pid == cur_id else tr("ersetzt: %s") % str(HardwareCatalog.get_part(rcat, cur_id).get("name", "–"))
			_add_choice(str(pd["name"]), "%s  •  %s" % [note, tr("%d im Teile-Lager") % stock], true,
				str(spare.get("id", "")) == pid, pid)
	if found == 0:
		var l := Label.new()
		l.text = tr("Kein passendes Teil im Teile-Lager. Im PC-Shop gekaufte Bauteile tauchen hier auf.") if AssemblyPlan.accepts_parts(rcat) else tr("Platinen gibt es nur als Reparatur-Kit.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 11)
		l.modulate = UIStyle.COL_TEXT_SUB
		_choose_list.add_child(l)


func _add_choice(title: String, info: String, enabled: bool, selected: bool, spare_id: String) -> void:
	var b := Button.new()
	b.text = ("✓ " if selected else "") + title + "\n" + info
	b.custom_minimum_size = Vector2(0, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.disabled = not enabled
	UIStyle.style_button(b, Color(0.30, 0.23, 0.10, 0.97) if selected else Color(0.165, 0.170, 0.182, 0.97))
	b.pressed.connect(func(): GameState.request_workbench_choose(spare_id))
	_choose_list.add_child(b)


func _kit_name() -> String:
	var spare := AssemblyPlan.spare_of(GameState.workbench_state)
	if str(spare.get("kind", "")) == "part":
		return str(HardwareCatalog.get_part(str(piece.plan["repair_cat"]), str(spare.get("id", ""))).get("name", "Teil"))
	var kid := GameState.get_workbench_kit_id()
	return tr(str((GameState.ITEM_CATALOG.get(kid, {}) as Dictionary).get("name", "Reparatur-Kit")))


func _update_highlight(nt: Dictionary) -> void:
	var ids: Array = []
	if _guide and not nt.is_empty() and _action.is_empty() and not (str(nt["kind"]) in ["measure", "choose"]):
		for t in piece.plan["tasks"]:
			if t["group"] == nt["group"] and str(t.get("label_arg", "")) == str(nt.get("label_arg", "")) and AssemblyPlan.is_available(piece.plan, piece.done, str(t["id"])):
				ids.append(str(t["item"]))
	piece.set_highlight_color(Color(1.0, 0.36, 0.20) if not nt.is_empty() and str(nt["kind"]) in ["remove", "unscrew", "unplug"] else Color(0.30, 0.75, 1.0))
	piece.set_highlight(ids)


func _draw_ring() -> void:
	if _ring_value < 0.0:
		return
	var c := _mouse
	_ring.draw_arc(c, 22.0, 0.0, TAU, 40, Color(0.02, 0.02, 0.03, 0.55), 6.0, true)
	_ring.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(_ring_value, 0.0, 1.0), 40, _ring_color, 4.0, true)


# ------------------------------------------------------------------ Kamera

func _view_xf() -> Transform3D:
	var base := prop.piece.global_transform
	var p := VIEW_POS.lerp(TOOL_VIEW_POS, _tool_blend)
	var l := VIEW_LOOK.lerp(TOOL_VIEW_LOOK, _tool_blend)
	l += Vector3(_pan.x, 0.0, _pan.y)
	p += Vector3(_pan.x, 0.0, _pan.y)
	var rel := (p - l) * _zoom
	rel = Basis(Vector3.UP, _orbit.x) * rel
	var right := rel.cross(Vector3.UP).normalized()
	rel = Basis(right, _orbit.y) * rel
	rel.y = maxf(rel.y, 0.10)
	p = l + rel
	return base * Transform3D(Basis.IDENTITY, p).looking_at(l, Vector3.UP)


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(piece) or not is_instance_valid(_cam):
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast_lbl.modulate.a = clampf(_toast_left * 2.0, 0.0, 1.0)

	_cam_t = minf(1.0, _cam_t + delta / CAM_TIME)
	var want_tool := 1.0 if _tool != "" else 0.0
	_tool_blend = lerpf(_tool_blend, want_tool, clampf(delta * 4.0, 0.0, 1.0))
	# Der Blick folgt der Maus ein Stück, damit man auch herangezoomt alles erreicht.
	var vs := get_viewport_rect().size
	var m := Vector2(clampf(_mouse.x / vs.x * 2.0 - 1.0, -1.0, 1.0), clampf(_mouse.y / vs.y * 2.0 - 1.0, -1.0, 1.0))
	if _action.is_empty() or str(_action.get("phase", "")) == "drag":
		var reach := Vector2(0.10, 0.08) + Vector2(0.26, 0.20) * (1.0 - clampf(_zoom, 0.0, 1.0)) + Vector2(0.14, 0.06) * _tool_blend
		_pan = _pan.lerp(m * reach, clampf(delta * 2.6, 0.0, 1.0))
	var view := _view_xf()
	if _cam_t < 1.0:
		var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		_cam.global_transform = _cam_from.interpolate_with(view, e)
		_cam.fov = lerpf(_cam_from_fov, VIEW_FOV, e)
	else:
		_cam.global_transform = _cam.global_transform.interpolate_with(view, clampf(delta * 10.0, 0.0, 1.0))
		_cam.fov = VIEW_FOV

	if _action.is_empty():
		_cand = _find_candidate()
	else:
		_run_action(delta)
	# Der letzte Handgriff schließt die Werkbank sofort.
	if not visible or not is_instance_valid(_cam) or piece.is_empty():
		return
	_update_tool_pose()
	piece.show_points(_guide or _tool == AssemblyPlan.TOOL_METER)
	_update_hint()
	_update_diag_panel()
	_send_hand(delta)
	_ring.queue_redraw()
	var nt := AssemblyPlan.next_task(piece.plan, piece.done)
	var nid := str(nt.get("id", "")) + ("|a" if not _action.is_empty() else "")
	if nid != _last_next:
		_last_next = nid
		_refresh_panel()


func _ray() -> Array:
	var inv := piece.global_transform.affine_inverse()
	var o := inv * _cam.project_ray_origin(_mouse)
	var d := (inv.basis * _cam.project_ray_normal(_mouse)).normalized()
	return [o, d]


func _screen(p_local: Vector3) -> Vector2:
	return _cam.unproject_position(piece.global_transform * p_local)


func _on_plane(y: float) -> Vector3:
	var r := _ray()
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if d.y > -0.01:
		return o + d * 0.8
	var p := o + d * ((y - o.y) / d.y)
	return Vector3(clampf(p.x, -0.75, 0.80), y, clampf(p.z, -0.36, 0.42))


# ------------------------------------------------------------------ Auswahl

func _find_candidate() -> Dictionary:
	var r := _ray()
	var best: Dictionary = {}
	var best_score := 1e9
	var blocked: Dictionary = {}
	var blocked_score := 1e9
	for t in piece.plan["tasks"]:
		var id := str(t["id"])
		if piece.done.has(id) or not piece.items.has(str(t["item"])):
			continue
		var item_id := str(t["item"])
		var it: WorkbenchPiece.Item = piece.items[item_id]
		var kind := str(t["kind"])
		var score := -1.0
		if kind == "place" and str(it.spec["kind"]) != "screw":
			if it.state != "rest" or not it.node.visible:
				continue
			score = _hit_score(piece.ray_hits_item(item_id, r[0], r[1]), 0.0)
		elif kind == "remove":
			if it.state != "seat":
				continue
			score = _hit_score(piece.ray_hits_item(item_id, r[0], r[1]), 0.0)
		elif kind in ["plug", "unplug"]:
			if not it.node.visible:
				continue
			score = _hit_score(piece.ray_hits_item(item_id, r[0], r[1], 0.010), 0.12)
		elif kind == "lever" or kind == "press":
			score = _hit_score(piece.ray_hits_item(item_id, r[0], r[1], 0.010), 0.10)
			if score < 0.0:
				var dl := _screen(piece.anchor_of(item_id)).distance_to(_mouse)
				if dl < PICK_PX:
					score = 0.5 + dl * 0.01
		else:
			# Schrauben, Paste, Pinzetten-Schraube: Abstand auf dem Bildschirm
			var limit := PICK_PX * (1.8 if kind in ["paste", "wipe"] else 1.0)
			var d := _screen(piece.anchor_of(item_id)).distance_to(_mouse)
			if d < limit:
				score = 0.2 + d * 0.01
		if score < 0.0:
			continue
		# Was zum Werkzeug in der Hand passt, hat Vorrang.
		if str(t["tool"]) != _tool:
			score += 10.0
		if AssemblyPlan.is_available(piece.plan, piece.done, id):
			if score < best_score:
				best_score = score
				best = {"task": t, "item": item_id, "ok": true}
		elif kind == "screw" and it.state == "out" and str(piece.plan["mode"]) == "repair":
			continue # gerade erst gelöst, kein Hinweis nötig
		elif score < blocked_score:
			blocked_score = score
			blocked = {"task": t, "item": item_id, "ok": false, "reason": "need"}
	if best.is_empty():
		return blocked
	var task: Dictionary = best["task"]
	if str(task["tool"]) != _tool:
		best["ok"] = false
		best["reason"] = "tool"
	elif str(task["id"]) == "cpu_place" and GameState.needs_workbench_replacement():
		best["ok"] = false
		best["reason"] = "broken"
	elif bool(task["kit"]) and not piece._kit_available():
		best["ok"] = false
		best["reason"] = "kit"
	elif not GameState._use_bench_supplies(piece.plan, task, 1.0, true):
		best["ok"] = false
		best["reason"] = "supplies"
	elif str(task["id"]) == "test_off" and not piece.is_post_finished():
		best["ok"] = false
		best["reason"] = "post"
	return best


## Direkt getroffene Kleinteile (bias > 0) schlagen alles, was nur in der Nähe des Zeigers liegt.
func _hit_score(dist: float, bias: float) -> float:
	if dist < 0.0:
		return -1.0
	return bias + dist * 0.05 if bias > 0.0 else maxf(0.001, dist)


func _update_hint() -> void:
	var base := tr("Rechte Maustaste ziehen: Blick drehen  •  Mausrad: Zoom  •  [H] Hilfe an/aus")
	if not _action.is_empty():
		match str(_action.get("phase", "")):
			"drag":
				base = tr("An die markierte Stelle führen und gedrückt halten, bis es einrastet")
				if int(_action.get("turns", 0)) != 0:
					base = tr("Goldenes Dreieck auf die Ecke des Sockels ausrichten: [R] drehen")
			"press":
				base = tr("Weiter drücken…")
				if int(_action.get("turns", 0)) != 0:
					base = tr("Sitzt nicht! Loslassen und mit [R] drehen – mit Gewalt brechen die Pins")
			"hold":
				if str(_action["kind"]) == "screw":
					var tv := float(_action["t"])
					base = tr("Festziehen…") if tv < 1.0 else (tr("Fest! Jetzt loslassen") if tv < AssemblyPlan.SCREW_OVER else tr("Zu fest! Loslassen, sonst überdreht die Schraube"))
			"paste":
				var a := float(_action["t"])
				base = tr("Pastenmenge: %d %%  •  ideal sind 80–110 %%") % int(roundf(a * 100.0))
	elif not _cand.is_empty():
		var t: Dictionary = _cand["task"]
		match str(_cand.get("reason", "")):
			"tool":
				var tl := str(t["tool"])
				base = tr("Dafür brauchst du: %s [%s]") % [_tool_label(tl), _tool_key(tl)] if tl != "" else tr("Erst das Werkzeug weglegen: Hand [1]")
			"need":
				var need := AssemblyPlan.missing_need(t, piece.done)
				if (piece.plan["by_id"] as Dictionary).has(need):
					base = tr("Vorher nötig: %s") % _task_label(piece.plan["by_id"][need])
			"broken":
				base = tr("CPU zerstört – rechts eine neue wählen")
			"supplies":
				base = tr("Schrauben oder Wärmeleitpaste sind leer – im PC-Shop unter „Kits“ nachbestellen")
			"post":
				base = tr("Warte, bis der POST durchgelaufen ist")
			"kit":
				base = tr("Ersatzteil fehlt: %s im PC-Shop kaufen") % _kit_name()
			_:
				base = _task_label(t)
				if str(t["kind"]) == "measure":
					base = tr("Messen: %s") % tr(str(AssemblyPlan.READINGS[str(t["cat"])][0]))
	_hint_lbl.text = base


# ------------------------------------------------------------------ Eingabe

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _orbiting:
			_orbit.x = clampf(_orbit.x - mm.relative.x * 0.005, -0.75, 0.75)
			_orbit.y = clampf(_orbit.y + mm.relative.y * 0.004, -0.35, 0.45)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb = true
					_press()
				else:
					_lmb = false
					_release()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_orbiting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom * 0.90, 0.38, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom / 0.90, 0.38, 1.15)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_select_tool("")
		KEY_2:
			_select_tool(AssemblyPlan.TOOL_DRIVER)
		KEY_3:
			_select_tool(AssemblyPlan.TOOL_PASTE)
		KEY_4:
			_select_tool(AssemblyPlan.TOOL_TWEEZERS)
		KEY_5:
			_select_tool(AssemblyPlan.TOOL_METER)
		KEY_R:
			if not _action.is_empty() and _action.has("turns"):
				_action["turns"] = (int(_action["turns"]) + 1) % 4
				_action["t"] = 0.0
				SfxManager.play("part_touch", -14.0, 1.2)
		KEY_H:
			_guide = not _guide
			_show_toast(tr("Markierungen an") if _guide else tr("Markierungen aus"))
			_refresh_panel()
		_:
			return
	get_viewport().set_input_as_handled()


func _select_tool(tool_id: String) -> void:
	if not _action.is_empty() or tool_id == _tool:
		return
	_tool = tool_id
	piece.held_tool = tool_id
	piece.tool_active = tool_id != ""
	piece.wake()
	SfxManager.play("tool_pick" if tool_id != "" else "drop", -12.0, 1.0 if tool_id != "" else 1.3)
	_refresh_panel()


func _press() -> void:
	if not _action.is_empty():
		return
	var r := _ray()
	var tool_hit := piece.ray_hits_tool(r[0], r[1])
	if tool_hit != "":
		_select_tool(tool_hit)
		return
	# Werkzeug in die Schale zurücklegen
	if _tool != "":
		var p := _on_plane(0.02)
		var d := p - WorkbenchPiece.TOOL_TRAY_POS
		if absf(d.x) < 0.075 and absf(d.z) < 0.135:
			_select_tool("")
			return
	_cand = _find_candidate()
	if _cand.is_empty():
		return
	if not bool(_cand["ok"]):
		SfxManager.play("error", -16.0)
		_update_hint()
		_show_toast(_hint_lbl.text, true)
		return
	var ct: Dictionary = _cand["task"]
	var now := Time.get_ticks_msec()
	# Grober Fehler: erst warnen, dann beim zweiten Klick machen lassen.
	if AssemblyPlan.is_live_risk(ct, piece.done) and now > _live_ok_until:
		_live_ok_until = now + 4000
		SfxManager.play("error", -10.0)
		_show_toast(tr("ACHTUNG: Der Server steht unter Strom! Erst ausschalten. (Nochmal klicken = trotzdem)"), true)
		return
	if str(ct["id"]) == "lid_on" and now > _lid_ok_until:
		var open := AssemblyPlan.open_soft(piece.plan, piece.done)
		if not open.is_empty():
			_lid_ok_until = now + 5000
			SfxManager.play("error", -12.0)
			var names := PackedStringArray()
			for o in open:
				var nm := _task_label(o)
				if not names.has(nm):
					names.append(nm)
			_show_toast(tr("Noch offen (%d): %s – nochmal klicken = trotzdem zu") % [open.size(), ", ".join(names.slice(0, 3))], true)
			return
	_begin_action(ct, str(_cand["item"]))


func _begin_action(task: Dictionary, item_id: String) -> void:
	var kind := str(task["kind"])
	_action = {"task": task, "item": item_id, "kind": kind, "t": 0.0, "phase": "hold", "sent": false}
	match kind:
		"place":
			_start_drag(item_id)
		"plug":
			_start_drag(item_id)
		"remove":
			_action["phase"] = "pull"
			SfxManager.play("part_slide", -14.0, 1.15)
		"paste":
			_action["phase"] = "paste"
			var it: WorkbenchPiece.Item = piece.items["paste"]
			_action["t"] = it.amount
		"screw", "unscrew":
			_tick_accum = 0.0
	_refresh_panel()


func _start_drag(item_id: String) -> void:
	var it: WorkbenchPiece.Item = piece.items[item_id]
	_action["phase"] = "drag"
	_action["rest_basis"] = it.cur.basis
	_action["snapped"] = false
	if bool(it.spec.get("turns", false)):
		_action["turns"] = int(_action.get("turns", piece.cpu_turns()))
	var ground := _on_plane(it.cur.origin.y)
	_action["grab"] = Vector3(it.cur.origin.x - ground.x, 0.0, it.cur.origin.z - ground.z).limit_length(0.12)
	SfxManager.play("pickup", -13.0, 1.25)
	piece.show_ghost(item_id)


func _release() -> void:
	if _action.is_empty():
		return
	var phase := str(_action["phase"])
	if phase == "paste":
		if float(_action["t"]) >= AssemblyPlan.PASTE_MIN:
			_finish_action(float(_action["t"]))
			return
		# Zu wenig: Menge bleibt auf der CPU, man kann gleich weitermachen.
		_show_toast(tr("Zu wenig Paste – weiter auftragen"), true)
		_action = {}
		_ring_value = -1.0
		return
	if phase == "carry":
		_drop_removed()
		return
	# Schraube: ab 70 % zählt sie, perfekt ist sie erst nach dem Klick.
	if str(_action["kind"]) == "screw" and float(_action["t"]) >= AssemblyPlan.SCREW_MIN:
		_finish_action(float(_action["t"]))
		return
	_cancel_action()


func _cancel_action() -> void:
	if _action.is_empty():
		return
	var item_id := str(_action["item"])
	if is_instance_valid(piece) and piece.items.has(item_id):
		if str(_action["kind"]) == "wipe":
			piece.wipe_paste(0.0)
		elif str(_action["kind"]) != "paste":
			piece.set_progress(item_id, -1.0)
		piece.release_item(item_id)
		piece.clear_ghost()
	if str(_action["phase"]) in ["drag", "press", "carry"]:
		SfxManager.play("drop", -14.0, 1.2)
	_action = {}
	_ring_value = -1.0
	_last_next = ""


func _finish_action(amount: float = 1.0) -> void:
	var task: Dictionary = _action["task"]
	var item_id := str(_action["item"])
	var kind := str(_action["kind"])
	_action = {}
	_ring_value = -1.0
	piece.clear_ghost()
	if kind != "paste" and kind != "wipe":
		piece.set_progress(item_id, -1.0)
	if piece.items.has(item_id):
		(piece.items[item_id] as WorkbenchPiece.Item).held = false
	match kind:
		"screw":
			if amount < AssemblyPlan.SCREW_LOOSE:
				SfxManager.play("screw_loose", -13.0)
				_show_toast(tr("Schraube nur handfest"), true)
			elif amount >= AssemblyPlan.SCREW_STRIP:
				SfxManager.play("spark", -16.0, 1.4)
				_show_toast(tr("Schraube überdreht!"), true)
			elif amount >= AssemblyPlan.SCREW_OVER:
				_show_toast(tr("Schraube zu fest"), true)
		"wipe":
			SfxManager.play("paste", -12.0, 1.3)
		"unscrew":
			SfxManager.play("screw_loose", -11.0, randf_range(0.95, 1.05))
		"lever":
			SfxManager.play("clip", -9.0, randf_range(0.92, 1.05))
		"plug":
			SfxManager.play("cable", -8.0, randf_range(0.97, 1.05))
		"unplug":
			SfxManager.play("cable_cut", -9.0)
		"press":
			SfxManager.play("click", -8.0, 0.8)
		"measure":
			var r := AssemblyPlan.reading(piece.plan, str(task["cat"]))
			SfxManager.play("meter_beep", -12.0, 1.25 if bool(r["ok"]) else 0.72)
			var verdict := tr("in Ordnung") if bool(r["ok"]) else (tr("schwankt") if bool(r["weak"]) else tr("AUSSER TOLERANZ – Defekt gefunden!"))
			_show_toast("%s: %s  –  %s" % [tr(str(r["name"])), str(r["text"]), verdict], not bool(r["ok"]))
		"place":
			SfxManager.play("clip" if str(task.get("click", "")) == "clip" else "part_set", -8.0, randf_range(0.96, 1.04))
		"remove":
			SfxManager.play("drop", -11.0, 1.15)
		"paste":
			SfxManager.play("paste", -14.0, 0.9)
			var good := amount >= AssemblyPlan.PASTE_LOW and amount <= AssemblyPlan.PASTE_HIGH
			_show_toast(tr("Perfekte Menge") if good else (tr("Etwas wenig Paste") if amount < AssemblyPlan.PASTE_LOW else tr("Etwas viel Paste")), not good)
	piece.local_done(str(task["id"]), amount)
	GameState.request_workbench_task(str(task["id"]), amount)
	_last_next = ""


# ------------------------------------------------------------------ Laufender Handgriff

func _run_action(delta: float) -> void:
	var task: Dictionary = _action["task"]
	var item_id := str(_action["item"])
	if not piece.items.has(item_id) or piece.done.has(task["id"]):
		_action = {}
		_ring_value = -1.0
		piece.clear_ghost()
		return
	var hold := maxf(0.05, float(task["hold"]) * GameState.get_tool_time_mult(str(task["kind"])))
	match str(_action["phase"]):
		"hold":
			_run_hold(delta, task, item_id, hold)
		"paste":
			_run_paste(delta)
		"drag", "press":
			_run_drag(delta, task, item_id, hold)
		"pull":
			_action["t"] = float(_action["t"]) + delta / hold
			_ring_value = float(_action["t"])
			_ring_color = Color(1.0, 0.55, 0.25)
			piece.set_progress(item_id, float(_action["t"]))
			if float(_action["t"]) >= 1.0:
				piece.set_progress(item_id, -1.0)
				_action["phase"] = "carry"
				_ring_value = -1.0
				SfxManager.play("part_slide", -10.0, 0.95)
		"carry":
			var it: WorkbenchPiece.Item = piece.items[item_id]
			var p := _on_plane(DRAG_H)
			var b := piece.seat_xf(it).basis
			piece.hold_item(item_id, Transform3D(b, p - b * Vector3(0.0, it.aabb.get_center().y, 0.0)))


func _run_hold(delta: float, task: Dictionary, item_id: String, hold: float) -> void:
	# Wer mit der Maus abrutscht, verliert den Halt.
	var kind := str(task["kind"])
	var limit := PICK_PX * (2.4 if kind in ["screw", "unscrew"] else 4.0)
	var d := _screen(piece.anchor_of(item_id)).distance_to(_mouse)
	if d > limit and not (kind in ["lever", "unplug", "press"] and piece.ray_hits_item(item_id, _ray()[0], _ray()[1], 0.03) >= 0.0):
		if kind in ["screw", "unscrew"]:
			_show_toast(tr("Abgerutscht – Schraubendreher auf der Schraube halten"), true)
		_cancel_action()
		return
	var before := float(_action["t"])
	# Kurz vor fest wird es zäh: so bleibt Zeit, im richtigen Moment loszulassen.
	var t := before + delta / hold * (0.32 if (kind == "screw" and before > 0.95) else 1.0)
	_action["t"] = t
	_ring_value = t
	_ring_color = Color(0.35, 0.80, 1.0) if not (kind in ["unscrew", "unplug"]) else Color(1.0, 0.55, 0.25)
	if kind == "wipe":
		piece.wipe_paste(t)
	else:
		piece.set_progress(item_id, clampf(t, 0.0, 1.0))
	if kind == "screw":
		if t >= AssemblyPlan.SCREW_OVER:
			_ring_color = Color(1.0, 0.30, 0.22)
		elif t >= 1.0:
			_ring_color = Color(0.40, 0.95, 0.45)
		if before < 1.0 and t >= 1.0:
			SfxManager.play("screw_tight", -8.0, randf_range(0.96, 1.04))
		if before < AssemblyPlan.SCREW_OVER and t >= AssemblyPlan.SCREW_OVER:
			SfxManager.play("screw_strain", -8.0)
	if kind in ["screw", "unscrew"]:
		_tick_accum += delta
		# Zum Schluss greift die Schraube schwerer: die Ratsche wird langsamer und tiefer.
		var interval := lerpf(0.060, 0.125, clampf(t, 0.0, 1.0)) if kind == "screw" else lerpf(0.120, 0.060, clampf(t, 0.0, 1.0))
		if _tick_accum >= interval:
			_tick_accum = 0.0
			if GameState.has_bench_tool("akku"):
				SfxManager.play("drill", -13.0, lerpf(1.10, 0.80, clampf(t, 0.0, 1.2)) if kind == "screw" else 1.05)
			else:
				SfxManager.play("screw_tick", -17.0, lerpf(1.15, 0.85, t) if kind == "screw" else lerpf(0.85, 1.15, t))
	if kind == "screw":
		# Die Kupplung rastet aus, sobald die Schraube richtig sitzt.
		if GameState.has_bench_tool("torque") and t >= 1.05:
			_finish_action(1.05)
		elif t >= 1.5:
			_finish_action(t)
	elif t >= 1.0:
		_finish_action()


func _run_paste(delta: float) -> void:
	var d := _screen(piece.anchor_of("paste")).distance_to(_mouse)
	if d > PICK_PX * 3.0:
		_release()
		return
	var gun := GameState.has_bench_tool("paste_gun")
	var a := minf(AssemblyPlan.PASTE_MAX, float(_action["t"]) + delta * (0.86 if gun else 0.56))
	_action["t"] = a
	piece.set_paste(a)
	_ring_value = a / AssemblyPlan.PASTE_MAX
	_ring_color = Color(0.45, 0.90, 0.45) if a >= 0.8 and a <= 1.1 else Color(0.95, 0.70, 0.25)
	_tick_accum += delta
	if _tick_accum > 0.28:
		_tick_accum = 0.0
		SfxManager.play("paste", -22.0, randf_range(0.95, 1.05))
	if gun and a >= 0.95:
		_finish_action(0.95)
	elif a >= AssemblyPlan.PASTE_MAX:
		_finish_action(a)


func _run_drag(delta: float, task: Dictionary, item_id: String, hold: float) -> void:
	var it: WorkbenchPiece.Item = piece.items[item_id]
	var seat := piece.seat_xf(it)
	piece.show_ghost(item_id)
	var turns := int(_action.get("turns", 0))
	if turns != 0:
		seat.basis = seat.basis * Basis(Vector3.UP, float(turns) * PI * 0.5)
	var raise := 0.016 if str(task["kind"]) == "plug" or str(it.spec["kind"]) == "screw" else 0.026
	var axis := seat.basis.y.normalized()
	var hover := Transform3D(seat.basis, seat.origin + axis * raise)
	# Nähe zum Steckplatz auf dem Bildschirm und auf der Arbeitsebene
	var p := _on_plane(seat.origin.y + raise)
	var dist := Vector2(p.x - seat.origin.x, p.z - seat.origin.z).length()
	var px := _screen(seat.origin + Vector3(0.0, it.aabb.get_center().y * WorkbenchPiece.S, 0.0)).distance_to(_mouse)
	var near := dist < SNAP_IN or px < PICK_PX * 1.4
	var far := dist > SNAP_OUT and px > PICK_PX * 2.8
	if bool(_action["snapped"]):
		if far:
			_action["snapped"] = false
			_action["phase"] = "drag"
			_action["t"] = 0.0
			_ring_value = -1.0
	elif near:
		_action["snapped"] = true
		_action["phase"] = "press"
		_action["t"] = 0.0
		SfxManager.play("part_touch", -16.0)
	if bool(_action["snapped"]):
		# Verkehrt herum geht es nur mit Gewalt – und dann brechen die Pins.
		var t := float(_action["t"]) + delta / (hold if turns == 0 else 2.2)
		_action["t"] = t
		_ring_value = t
		_ring_color = Color(0.35, 0.80, 1.0) if turns == 0 else Color(1.0, 0.25, 0.20)
		var press := Transform3D(seat.basis, seat.origin + axis * (raise * (1.0 - clampf(t, 0.0, 1.0) * clampf(t, 0.0, 1.0))))
		piece.hold_item(item_id, press if (t > 0.0 and turns == 0) else hover)
		if t >= 1.0:
			if turns == 0:
				_finish_action()
			else:
				GameState.request_workbench_break(str(task["id"]))
				_cancel_action()
		return
	var target := _on_plane(DRAG_H)
	var k := clampf(1.0 - (dist - SNAP_IN) / 0.22, 0.0, 1.0)
	var rb: Basis = _action["rest_basis"]
	var b := rb.orthonormalized().slerp(seat.basis.orthonormalized(), k).scaled(Vector3.ONE * WorkbenchPiece.S)
	var pos := target + (_action["grab"] as Vector3) * (1.0 - k)
	# Mitte des Teils an den Mauszeiger, nicht der Drehpunkt
	pos -= b * it.aabb.get_center() * 0.85
	piece.hold_item(item_id, Transform3D(b, pos))


func _drop_removed() -> void:
	var item_id := str(_action["item"])
	var it: WorkbenchPiece.Item = piece.items[item_id]
	var p := _on_plane(0.0)
	var c := WorkbenchPiece.CHASSIS_POS
	var outside := absf(p.x - c.x) > 0.29 or absf(p.z - c.z) > 0.28
	if outside:
		_finish_action()
	else:
		_show_toast(tr("Neben dem Gehäuse ablegen"), true)
		it.held = true
		_cancel_action()


# ------------------------------------------------------------------ Werkzeug in der Hand

func _update_tool_pose() -> void:
	# Nach einem Neuaufbau (z. B. Ersatzteil gewählt) bleibt das Werkzeug in der Hand.
	piece.held_tool = _tool
	piece.tool_active = _tool != ""
	if _tool == "":
		return
	piece.wake()
	var tip := _on_plane(0.10)
	var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(-26.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(18.0))
	var task: Dictionary = _action.get("task", {}) if not _action.is_empty() else (_cand.get("task", {}) if bool(_cand.get("ok", false)) else {})
	if not task.is_empty() and str(task["tool"]) == _tool:
		var item_id := str(task["item"])
		var it: WorkbenchPiece.Item = piece.items[item_id]
		if _tool == AssemblyPlan.TOOL_TWEEZERS:
			tip = it.cur * Vector3(0.0, 0.002, 0.0)
		elif _tool == AssemblyPlan.TOOL_PASTE:
			var wob := Vector3.ZERO
			if not _action.is_empty():
				var a := float(_action["t"]) * 9.0
				wob = Vector3(cos(a) * 0.011, 0.0, sin(a) * 0.011)
			tip = piece.anchor_of(item_id) + wob + Vector3(0.0, 0.004, 0.0)
			tilt = Basis(Vector3(0, 0, 1), deg_to_rad(-14.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(10.0))
		elif _tool == AssemblyPlan.TOOL_METER:
			tip = piece.anchor_of(item_id) + Vector3(0.0, 0.0 if not _action.is_empty() else 0.008, 0.0)
			tilt = Basis(Vector3(1, 0, 0), deg_to_rad(16.0))
		else:
			tip = it.cur * Vector3(0.0, it.aabb.end.y, 0.0) if not _action.is_empty() else piece.anchor_of(item_id) + Vector3(0.0, 0.010, 0.0)
			tilt = Basis.IDENTITY
			if not _action.is_empty():
				var dir := 1.0 if str(task["kind"]) == "unscrew" else -1.0
				tilt = Basis(Vector3.UP, dir * float(_action["t"]) * TAU * 5.0)
	piece.tool_xf = Transform3D(tilt, tip)


func _send_hand(delta: float) -> void:
	_send_accum += delta
	if _send_accum < SEND_INTERVAL or NetworkManager.players.size() < 2:
		return
	_send_accum = 0.0
	var data := {"tool": _tool, "item": "", "xf": piece.tool_xf, "task": "", "t": 0.0}
	if not _action.is_empty():
		var item_id := str(_action["item"])
		var it: WorkbenchPiece.Item = piece.items.get(item_id)
		if it != null and it.held:
			data["item"] = item_id
			data["xf"] = it.hold_xf
		else:
			data["task"] = str((_action["task"] as Dictionary)["id"])
			data["t"] = float(_action["t"])
	GameState.send_workbench_hand(data)
