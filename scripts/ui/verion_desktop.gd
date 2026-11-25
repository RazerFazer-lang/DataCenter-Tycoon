class_name VerionDesktop
extends Control
## Arbeitsfläche von Verion OS: Hintergrund, Statusleiste oben, Dock unten, Fenster,
## Startmenü, Meldungen und Widget. Den Inhalt der Fenster zeichnet TerminalUI.

signal app_requested(app: String)
signal active_changed(app: String)
signal exit_requested
signal shutdown_requested
signal save_requested
signal theme_toggled

const BAR_H := 34.0
const DOCK_H := 66.0
const TILE := 46.0
const TOAST_MAX := 4
const TOAST_SECONDS := 6.0
const NOTES_MAX := 24

var apps: Dictionary = {}
var order: Array[String] = []

var windows: Dictionary = {}
var _area: Control
var _wall: Control
var _widget: Control
var _bar: PanelContainer
var _dock: PanelContainer
var _dock_row: HBoxContainer
var _tiles: Dictionary = {}
var _badges: Dictionary = {}
var _start: PanelContainer
var _theme_btn: Button
var _notes_panel: PanelContainer
var _notes_body: VBoxContainer
var _notes: Array = []
var _notes_new := 0
var _toasts: VBoxContainer
var _lbl_app: Label
var _lbl_clock: Label
var _lbl_power: Label
var _lbl_temp: Label
var _lbl_net: Label
var _lbl_money: Label
var _lbl_mail: Label
var _ic_power: Control
var _ic_temp: Control
var _ic_net: Control
var _ic_mail: Control
var _ic_bell: Control
var _cascade := 0
var _widget_accum := 0.0


func setup(p_apps: Dictionary, p_order: Array[String]) -> void:
	apps = p_apps
	order = p_order
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_meta("vt", true)
	_build()


# ---------------------------------------------------------------- Aufbau

func _build() -> void:
	_wall = Control.new()
	_wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall.draw.connect(func(): PcBootScreen.draw_wallpaper(_wall, Rect2(Vector2.ZERO, _wall.size)))
	add_child(_wall)

	_widget = Control.new()
	_widget.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_widget.offset_left = -318.0
	_widget.offset_right = -18.0
	_widget.offset_top = BAR_H + 18.0
	_widget.offset_bottom = BAR_H + 400.0
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.draw.connect(_draw_widget)
	add_child(_widget)

	_area = Control.new()
	_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_area.offset_top = BAR_H
	_area.offset_bottom = -DOCK_H
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.resized.connect(func():
		for w in windows.values():
			(w as VerionWindow).fit()
	)
	add_child(_area)

	_build_bar()
	_build_dock()
	_build_start()
	_build_notes()

	_toasts = VBoxContainer.new()
	# Unten links, damit Meldungen nicht auf den Fensterknöpfen liegen. Der Anruf erscheint unten rechts.
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.offset_left = 14.0
	_toasts.offset_right = 366.0
	_toasts.offset_bottom = -DOCK_H - 8.0
	_toasts.offset_top = -DOCK_H - 8.0
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 8)
	add_child(_toasts)
	restyle()


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = BAR_H
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)

	var start := Button.new()
	start.custom_minimum_size = Vector2(112, 26)
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.text = "      Verion"
	start.alignment = HORIZONTAL_ALIGNMENT_LEFT
	start.add_theme_font_size_override("font_size", 13)
	VerionTheme.flat_button(start, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.10), VerionTheme.TEXT, 6)
	var logo := VerionTheme.icon("verion", 16, VerionTheme.ACCENT)
	logo.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	logo.offset_left = 9.0
	logo.offset_right = 25.0
	logo.offset_top = -8.0
	logo.offset_bottom = 8.0
	start.add_child(logo)
	start.pressed.connect(toggle_start)
	row.add_child(start)
	_lbl_app = VerionTheme.label("", 13, VerionTheme.MUTED)
	_lbl_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_app.clip_text = true
	row.add_child(_lbl_app)

	# Die Uhr liegt fest in der Mitte der Leiste, egal wie breit der Infobereich ist.
	_lbl_clock = VerionTheme.label("", 13, VerionTheme.TEXT)
	_lbl_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	_lbl_clock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_clock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lbl_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_clock.offset_top = 0.0
	_lbl_clock.offset_bottom = BAR_H
	add_child(_lbl_clock)

	_ic_power = VerionTheme.icon("power", 13, VerionTheme.MUTED)
	_lbl_power = _tray(row, _ic_power)
	_ic_temp = VerionTheme.icon("temp", 13, VerionTheme.MUTED)
	_lbl_temp = _tray(row, _ic_temp)
	_ic_net = VerionTheme.icon("net", 13, VerionTheme.MUTED)
	_lbl_net = _tray(row, _ic_net)
	_lbl_money = VerionTheme.label("", 13, VerionTheme.GOOD)
	row.add_child(_lbl_money)

	var mb := _bar_button(row, "mail", func(): app_requested.emit("mail"))
	_ic_mail = mb.get_child(0)
	_lbl_mail = _count_label(mb)
	var bb := _bar_button(row, "bell", toggle_notes)
	_ic_bell = bb.get_child(0)
	var ob := _bar_button(row, "power_off", func(): exit_requested.emit())
	ob.tooltip_text = "Aufstehen, PC bleibt an [ESC]"


func _tray(row: HBoxContainer, ic: Control) -> Label:
	row.add_child(ic)
	var l := VerionTheme.label("", 12, VerionTheme.TEXT)
	row.add_child(l)
	return l


func _bar_button(row: HBoxContainer, kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 26)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	VerionTheme.flat_button(b, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.12), VerionTheme.TEXT, 6)
	var ic := VerionTheme.icon(kind, 15, VerionTheme.TEXT)
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.offset_left = -7.5
	ic.offset_right = 7.5
	ic.offset_top = -7.5
	ic.offset_bottom = 7.5
	b.add_child(ic)
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _count_label(parent: Control) -> Label:
	var l := VerionTheme.label("", 10, Color.WHITE)
	l.add_theme_stylebox_override("normal", VerionTheme.pad(VerionTheme.flat(VerionTheme.BAD.darkened(0.12), 7), 4.0, 0.0))
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.offset_right = 3.0
	l.offset_top = -2.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	parent.add_child(l)
	return l


func _build_dock() -> void:
	_dock = PanelContainer.new()
	_dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dock.offset_top = -DOCK_H + 3.0
	_dock.offset_bottom = -5.0
	add_child(_dock)
	_dock_row = HBoxContainer.new()
	_dock_row.add_theme_constant_override("separation", 8)
	_dock.add_child(_dock_row)
	for a in order:
		_add_tile(a, str(apps[a]["icon"]), str(apps[a]["name"]), VerionTheme.app_color(a), func(): app_requested.emit(a))
	_add_tile("save", "save", "Speichern", Color(0.30, 0.36, 0.46), func(): save_requested.emit())


func _add_tile(id: String, icon_kind: String, tip: String, col: Color, cb: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE, TILE + 4.0)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.set_meta("vt", true)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var face := Control.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_meta("kind", icon_kind)
	face.draw.connect(func() -> void:
		var hov := b.is_hovered()
		var lift := -3.0 if hov else 0.0
		var r := Rect2(1.0, 1.0 + lift, TILE - 2.0, TILE - 4.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.10) if hov else col
		sb.set_corner_radius_all(11)
		sb.border_color = col.lightened(0.35)
		sb.border_width_top = 1
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 5
		face.draw_style_box(sb, r)
		# Verlauf: unten etwas dunkler
		var lo := StyleBoxFlat.new()
		lo.bg_color = Color(0, 0, 0, 0.16)
		lo.corner_radius_bottom_left = 11
		lo.corner_radius_bottom_right = 11
		face.draw_style_box(lo, Rect2(r.position.x, r.get_center().y, r.size.x, r.size.y * 0.5))
		UIStyle.draw_icon(face, str(face.get_meta("kind")), Rect2(r.get_center() - Vector2(12, 12), Vector2(24, 24)), Color.WHITE)
		if windows.has(id):
			var on: bool = active_app() == id
			face.draw_circle(Vector2(TILE * 0.5, TILE + 1.5), 2.6 if on else 2.0, Color.WHITE if on else Color(1, 1, 1, 0.5))
	)
	b.add_child(face)
	b.mouse_entered.connect(face.queue_redraw)
	b.mouse_exited.connect(face.queue_redraw)
	b.pressed.connect(cb)
	_dock_row.add_child(b)
	_tiles[id] = face
	_badges[id] = _count_label(b)


func _build_start() -> void:
	_start = PanelContainer.new()
	_start.visible = false
	_start.position = Vector2(8, BAR_H + 6.0)
	_start.custom_minimum_size = Vector2(290, 0)
	_start.add_to_group("verion_overlay")
	add_child(_start)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_start.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(VerionTheme.icon("verion", 24, VerionTheme.ACCENT))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	head.add_child(hv)
	hv.add_child(VerionTheme.label("Verion OS 4", 15, VerionTheme.TEXT))
	hv.add_child(VerionTheme.label("Arbeitsplatz der Firma", 11, VerionTheme.MUTED))
	v.add_child(HSeparator.new())
	for a in order:
		_menu_row(v, str(apps[a]["icon"]), str(apps[a]["name"]), VerionTheme.app_color(a).lightened(0.15), func(): app_requested.emit(a))
	v.add_child(HSeparator.new())
	_menu_row(v, "save", "Speichern", VerionTheme.MUTED, func(): save_requested.emit())
	_theme_btn = _menu_row(v, "moon", "Darstellung: Dunkel", VerionTheme.MUTED, func(): theme_toggled.emit())
	_menu_row(v, "power_off", "Herunterfahren", VerionTheme.BAD, func(): shutdown_requested.emit())
	_menu_row(v, "people", "Aufstehen, PC bleibt an [ESC]", VerionTheme.MUTED, func(): exit_requested.emit())


func _menu_row(v: VBoxContainer, icon_kind: String, text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 31)
	b.add_theme_font_size_override("font_size", 13)
	VerionTheme.flat_button(b, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.09), VerionTheme.TEXT, 6)
	for st in ["normal", "hover", "pressed"]:
		(b.get_theme_stylebox(st) as StyleBoxFlat).content_margin_left = 36.0
	var ic := VerionTheme.icon(icon_kind, 16, col)
	ic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	ic.offset_left = 10.0
	ic.offset_right = 26.0
	ic.offset_top = -8.0
	ic.offset_bottom = 8.0
	b.add_child(ic)
	b.pressed.connect(func():
		_start.visible = false
		cb.call()
	)
	v.add_child(b)
	return b


func _build_notes() -> void:
	_notes_panel = PanelContainer.new()
	_notes_panel.visible = false
	_notes_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_notes_panel.offset_left = -360.0
	_notes_panel.offset_right = -8.0
	_notes_panel.offset_top = BAR_H + 6.0
	_notes_panel.offset_bottom = -DOCK_H - 6.0
	_notes_panel.add_to_group("verion_overlay")
	add_child(_notes_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_notes_panel.add_child(v)
	v.add_child(VerionTheme.label("Mitteilungen", 15, VerionTheme.TEXT))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_notes_body = VBoxContainer.new()
	_notes_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_body.add_theme_constant_override("separation", 6)
	sc.add_child(_notes_body)


## Liegt an dieser Stelle etwas über den Fenstern (Menü, Meldung, Anruf, Dialog)?
static func is_overlay_at(tree: SceneTree, global: Vector2) -> bool:
	for n in tree.get_nodes_in_group("verion_overlay"):
		var c := n as Control
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(global):
			return true
	return false


func restyle() -> void:
	var dark := VerionTheme.dark
	var bar := VerionTheme.pad(VerionTheme.flat(VerionTheme.BAR, 0), 6.0, 3.0)
	bar.border_color = Color(1, 1, 1, 0.07)
	bar.border_width_bottom = 1
	_bar.add_theme_stylebox_override("panel", bar)
	_dock.add_theme_stylebox_override("panel", VerionTheme.pad(VerionTheme.flat(Color(0.07, 0.085, 0.13, 0.80), 16, Color(1, 1, 1, 0.12), 1), 10.0, 4.0))
	for p in [_start, _notes_panel]:
		var sb := VerionTheme.flat(Color(0.075, 0.090, 0.132, 0.985), 12, VerionTheme.BORDER, 1)
		sb.set_content_margin_all(12.0)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 16
		(p as PanelContainer).add_theme_stylebox_override("panel", sb)
	_theme_btn.text = "Darstellung: Dunkel" if dark else "Darstellung: Hell"
	for w in windows.values():
		(w as VerionWindow).restyle()


# ---------------------------------------------------------------- Fenster

func active_app() -> String:
	for i in range(_area.get_child_count() - 1, -1, -1):
		var w := _area.get_child(i) as VerionWindow
		if w != null and w.visible:
			return w.app
	return ""


func window(app: String) -> VerionWindow:
	return windows.get(app) as VerionWindow


func is_shown(app: String) -> bool:
	return windows.has(app) and (windows[app] as VerionWindow).visible


func shown_apps() -> Array[String]:
	var out: Array[String] = []
	for c in _area.get_children():
		var w := c as VerionWindow
		if w != null and w.visible:
			out.append(w.app)
	return out


func open_window(app: String) -> VerionWindow:
	_start.visible = false
	var w: VerionWindow = windows.get(app)
	if w == null:
		w = VerionWindow.new()
		w.app = app
		windows[app] = w
		_area.add_child(w)
		var a := _area.size if _area.size.x > 100.0 else Vector2(1280, 620)
		w.size = Vector2(minf(a.x - 40.0, maxf(1040.0, a.x * 0.80)), minf(a.y - 16.0, maxf(540.0, a.y * 0.90)))
		var off := Vector2(26.0, 14.0) * float(_cascade % 5)
		_cascade += 1
		w.position = ((a - w.size) * 0.5 + off - Vector2(44.0, 24.0)).clamp(Vector2.ZERO, (a - w.size).max(Vector2.ZERO))
		w.focus_requested.connect(focus)
		w.close_pressed.connect(close_window)
		w.minimize_pressed.connect(minimize)
		w.pivot_offset = w.size * 0.5
		w.scale = Vector2(0.96, 0.96)
		w.modulate.a = 0.0
		var tw := w.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(w, "scale", Vector2.ONE, 0.16)
		tw.tween_property(w, "modulate:a", 1.0, 0.12)
	w.visible = true
	w.needs_render = true
	focus(app)
	return w


func focus(app: String) -> void:
	hide_menus()
	var w := window(app)
	if w == null:
		return
	if w.get_index() != _area.get_child_count() - 1:
		_area.move_child(w, _area.get_child_count() - 1)
	_update_active()


func minimize(app: String) -> void:
	var w := window(app)
	if w != null:
		w.visible = false
		SfxManager.play("click", -10.0, 0.90)
	_update_active()


func close_window(app: String) -> void:
	var w := window(app)
	if w != null:
		windows.erase(app)
		_area.remove_child(w)
		w.queue_free()
		SfxManager.play("click", -10.0, 0.82)
	_update_active()


func close_all() -> void:
	for a in windows.keys():
		var w := window(str(a))
		_area.remove_child(w)
		w.queue_free()
	windows.clear()
	_update_active()


func _update_active() -> void:
	var a := active_app()
	for w in windows.values():
		(w as VerionWindow).set_active((w as VerionWindow).app == a)
	_lbl_app.text = str(apps[a]["name"]) if apps.has(a) else ""
	for f in _tiles.values():
		(f as Control).queue_redraw()
	active_changed.emit(a)


func toggle_start() -> void:
	_start.visible = not _start.visible
	_notes_panel.visible = false
	_toasts.visible = true
	SfxManager.play("win_start" if _start.visible else "click", -10.0, 1.0)


func hide_menus() -> void:
	_start.visible = false
	_notes_panel.visible = false
	_toasts.visible = true


func is_menu_open() -> bool:
	return _start.visible or _notes_panel.visible


func _input(event: InputEvent) -> void:
	# Klick neben ein offenes Menü schließt es.
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not is_visible_in_tree() or not is_menu_open():
		return
	var p := mb.global_position
	if p.y < BAR_H or (_start.visible and _start.get_global_rect().has_point(p)) or (_notes_panel.visible and _notes_panel.get_global_rect().has_point(p)):
		return
	hide_menus()


# ---------------------------------------------------------------- Statusleiste, Dock

func set_badge(app: String, n: int, icon_kind: String = "") -> void:
	var l: Label = _badges.get(app)
	if l == null:
		return
	l.visible = n > 0
	l.text = str(mini(n, 99))
	if icon_kind != "":
		var f: Control = _tiles[app]
		if str(f.get_meta("kind")) != icon_kind:
			f.set_meta("kind", icon_kind)
			f.queue_redraw()


func set_tip(app: String, tip: String) -> void:
	if _tiles.has(app):
		((_tiles[app] as Control).get_parent() as Button).tooltip_text = tip


func refresh_tray() -> void:
	var over := GameState.total_watts > GameState.max_watts
	var blocked := FinanceManager.is_power_blocked()
	var ups_txt := (" " + tr("(USV %.0f%%)") % GameState.avg_ups_charge) if not GameState.ups_units.is_empty() else ""
	_lbl_power.text = "%d/%d W%s" % [GameState.total_watts, GameState.max_watts, ups_txt]
	var pc := VerionTheme.BAD if over or blocked else VerionTheme.TEXT
	_lbl_power.add_theme_color_override("font_color", pc)
	_ic_power.modulate = pc if over or blocked else VerionTheme.WARN
	_lbl_temp.text = "%.0f °C" % GameState.room_temp
	var hot := GameState.room_temp >= 68.0
	_lbl_temp.add_theme_color_override("font_color", VerionTheme.BAD if hot else VerionTheme.TEXT)
	_ic_temp.modulate = VerionTheme.BAD if hot else VerionTheme.MUTED
	var limit := GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps
	var spd := HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
	_lbl_net.text = "DDoS!" if GameState.ddos_active else (tr("%s LIMIT!") % spd if limit else spd)
	var bad_net: bool = GameState.ddos_active or limit or FinanceManager.is_blocked("internet")
	_lbl_net.add_theme_color_override("font_color", VerionTheme.BAD if bad_net else VerionTheme.TEXT)
	VerionTheme.set_icon(_ic_net, "warn" if GameState.ddos_active or limit else "net")
	_ic_net.modulate = VerionTheme.BAD if bad_net else VerionTheme.ACCENT
	_lbl_money.text = FinanceManager.format_money(GameState.money)
	_lbl_money.add_theme_color_override("font_color", VerionTheme.BAD if GameState.money < 0.0 else VerionTheme.GOOD)
	_lbl_clock.text = "%s   %s" % [PcBootScreen.format_real_date(), PcBootScreen.format_real_clock()]
	_lbl_clock.tooltip_text = tr("Spieltag %d") % GameState.day_number
	var un := MailManager.get_unread_count()
	_lbl_mail.visible = un > 0
	_lbl_mail.text = str(mini(un, 99))
	_ic_mail.modulate = VerionTheme.ACCENT.lightened(0.2) if un > 0 else VerionTheme.TEXT
	_ic_bell.modulate = VerionTheme.WARN if _notes_new > 0 else VerionTheme.TEXT
	_widget.queue_redraw()


# ---------------------------------------------------------------- Meldungen

func add_note(text: String, severity: String) -> void:
	_notes.push_front({"text": text, "sev": severity, "clock": PcBootScreen.format_real_clock()})
	while _notes.size() > NOTES_MAX:
		_notes.pop_back()
	if not _notes_panel.visible:
		_notes_new += 1
	else:
		_fill_notes()


func toggle_notes() -> void:
	_notes_panel.visible = not _notes_panel.visible
	_toasts.visible = not _notes_panel.visible
	_start.visible = false
	SfxManager.play("click", -10.0, 1.1)
	if _notes_panel.visible:
		_notes_new = 0
		_fill_notes()


func _sev_color(sev: String) -> Color:
	match sev:
		"alert":
			return VerionTheme.BAD
		"warn":
			return VerionTheme.WARN
		"good":
			return VerionTheme.GOOD
	return VerionTheme.ACCENT


func _fill_notes() -> void:
	for c in _notes_body.get_children():
		c.queue_free()
	if _notes.is_empty():
		_notes_body.add_child(VerionTheme.label("Noch keine Mitteilungen.", 13, VerionTheme.MUTED))
	for n in _notes:
		var d: Dictionary = n
		var p := PanelContainer.new()
		var sb := VerionTheme.pad(VerionTheme.flat(VerionTheme.CARD, 8), 10.0, 7.0)
		sb.border_color = _sev_color(str(d["sev"]))
		sb.border_width_left = 3
		p.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		p.add_child(v)
		v.add_child(VerionTheme.label(str(d["clock"]), 10, VerionTheme.MUTED))
		var l := VerionTheme.label(str(d["text"]), 12, VerionTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
		_notes_body.add_child(p)


func toast(title: String, text: String, icon_kind: String, col: Color, cb: Callable = Callable()) -> void:
	if not is_visible_in_tree():
		return
	while _toasts.get_child_count() >= TOAST_MAX:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	var sb := VerionTheme.pad(VerionTheme.flat(Color(0.085, 0.102, 0.150, 0.98), 10, VerionTheme.BORDER, 1), 12.0, 9.0)
	sb.border_color = col.lerp(VerionTheme.BORDER, 0.3)
	sb.border_width_left = 4
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	row.add_child(VerionTheme.icon(icon_kind, 20, col))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	v.add_child(VerionTheme.label(title, 13, VerionTheme.TEXT))
	if text != "":
		var l := VerionTheme.label(text, 12, VerionTheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.max_lines_visible = 2
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed:
			p.queue_free()
			if cb.is_valid():
				cb.call()
	)
	p.add_to_group("verion_overlay")
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- Widget auf der Arbeitsfläche

func _draw_widget() -> void:
	var h := 346.0 + (36.0 if not FinanceManager.get_blocked_kinds().is_empty() else 0.0)
	draw_status_card(_widget, Rect2(0.0, 0.0, _widget.size.x, h))


## Übersichtskarte auf der Arbeitsfläche.
static func draw_status_card(ci: CanvasItem, r: Rect2) -> void:
	var f := ThemeDB.fallback_font
	var sb := VerionTheme.flat(Color(0.05, 0.065, 0.105, 0.72), 14, Color(1, 1, 1, 0.10), 1)
	ci.draw_style_box(sb, r)
	var k := r.size.x / 300.0
	var x := r.position.x + 18.0 * k
	var w := r.size.x - 36.0 * k
	var y := r.position.y + 32.0 * k
	ci.draw_string(f, Vector2(x, y), _s("Überblick, Tag %d") % GameState.day_number, HORIZONTAL_ALIGNMENT_LEFT, w, int(16.0 * k), VerionTheme.TEXT)
	y += 18.0 * k
	var wp := clampf(float(GameState.total_watts) / maxf(1.0, float(GameState.max_watts)), 0.0, 1.0)
	y = _gauge(ci, f, x, y, w, k, _s("Strom"), "%d / %d W" % [GameState.total_watts, GameState.max_watts], wp, VerionTheme.BAD if wp > 0.9 else VerionTheme.WARN)
	var tp := clampf((GameState.room_temp - 18.0) / 60.0, 0.0, 1.0)
	y = _gauge(ci, f, x, y, w, k, _s("Raumtemperatur"), "%.1f °C" % GameState.room_temp, tp, VerionTheme.BAD if GameState.room_temp >= 60.0 else Color(0.20, 0.75, 0.85))
	var np := clampf(GameState.used_bandwidth_mbps / maxf(1.0, GameState.max_bandwidth_mbps), 0.0, 1.0)
	y = _gauge(ci, f, x, y, w, k, _s("Internet"), "%s / %s" % [HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps), HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)], np, VerionTheme.BAD if np >= 0.95 else VerionTheme.ACCENT)
	var users := 0
	var sat := 0.0
	var n := 0
	for rid in GameState.racks.keys():
		var rk: Dictionary = GameState.racks[rid]
		if str(rk.get("rental_type", "none")) != "none":
			users += int(rk.get("active_users", 0))
			sat += float(rk.get("satisfaction", 100.0))
			n += 1
	y += 6.0 * k
	var rows := [
		[_s("Miete"), "+$%.0f / 5 s" % GameState.total_rental_income_per_cycle, VerionTheme.GOOD],
		[_s("Kunden"), "%d" % users, VerionTheme.TEXT],
		[_s("Zufriedenheit"), ("%d %%" % int(sat / float(n))) if n > 0 else "–", VerionTheme.TEXT],
		[_s("Marktanteil"), "%.1f %%" % (float(MarketManager.get_total_shares().get("you", 0.0)) * 100.0), Color(0.95, 0.50, 0.78)],
		[_s("Offene Rechnungen"), FinanceManager.format_money(FinanceManager.get_open_bills_total()), VerionTheme.BAD if FinanceManager.get_dunning_count() > 0 else VerionTheme.TEXT],
		[_s("Ungelesene E-Mails"), str(MailManager.get_unread_count()), VerionTheme.ACCENT.lightened(0.2) if MailManager.get_unread_count() > 0 else VerionTheme.TEXT],
		[_s("Offene Tickets"), str(GameState.get_open_ticket_count()), VerionTheme.BAD if GameState.get_open_ticket_count() > 0 else VerionTheme.TEXT],
	]
	for row in rows:
		y += 22.0 * k
		ci.draw_string(f, Vector2(x, y), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, int(13.0 * k), VerionTheme.MUTED)
		ci.draw_string(f, Vector2(x + w * 0.45, y), str(row[1]), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.55, int(13.0 * k), row[2])
	var blocked := FinanceManager.get_blocked_kinds()
	if not blocked.is_empty():
		y += 12.0 * k
		ci.draw_style_box(VerionTheme.flat(Color(0.55, 0.10, 0.10, 0.85), int(6.0 * k)), Rect2(x, y, w, 24.0 * k))
		var names: Array = []
		for b in blocked:
			names.append(_s(str(FinanceManager.BILL_KINDS[b]["title"])))
		ci.draw_string(f, Vector2(x + 8.0 * k, y + 17.0 * k), _s("GESPERRT: %s") % ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, w - 16.0 * k, int(12.0 * k), Color.WHITE)


static func _s(t: String) -> String:
	return String(TranslationServer.translate(t))


static func _gauge(ci: CanvasItem, f: Font, x: float, y: float, w: float, k: float, name: String, val: String, p: float, col: Color) -> float:
	ci.draw_string(f, Vector2(x, y + 16.0 * k), name, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5, int(12.0 * k), VerionTheme.MUTED)
	ci.draw_string(f, Vector2(x + w * 0.4, y + 16.0 * k), val, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.6, int(12.0 * k), VerionTheme.TEXT)
	var r := Rect2(x, y + 22.0 * k, w, 6.0 * k)
	ci.draw_style_box(VerionTheme.flat(Color(1, 1, 1, 0.10), int(3.0 * k)), r)
	if p > 0.01:
		ci.draw_style_box(VerionTheme.flat(col, int(3.0 * k)), Rect2(r.position, Vector2(maxf(6.0 * k, r.size.x * p), r.size.y)))
	return y + 38.0 * k
