class_name VerionWindow
extends PanelContainer
## Ein Fenster von Verion OS: verschieben am Titel, Größe an Rändern und Ecken,
## Doppelklick auf den Titel maximiert. Der Inhalt liegt in body.

signal focus_requested(app: String)
signal close_pressed(app: String)
signal minimize_pressed(app: String)

const MIN_SIZE := Vector2(520.0, 300.0)
const GRIP := 7.0
const TITLE_H := 36.0

var app := ""
var body: VBoxContainer
var maximized := false
var needs_render := true

var _title: Label
var _subtitle: Label
var _icon: Control
var _title_panel: PanelContainer
var _max_icon: Control
var _restore_rect := Rect2()
var _drag := false
var _drag_off := Vector2.ZERO
var _resize_dir := Vector2.ZERO
var _resize_start := Rect2()
var _resize_mouse := Vector2.ZERO
var _active := false


func _init() -> void:
	set_meta("vt", true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Zwischenschicht ohne Mindestgröße: Der Inhalt darf das Fenster nicht aufblähen.
	var host := Control.new()
	host.set_meta("vt", true)
	host.clip_contents = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	var v := VBoxContainer.new()
	v.set_meta("vt", true)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	host.add_child(v)

	_title_panel = PanelContainer.new()
	_title_panel.set_meta("vt", true)
	_title_panel.custom_minimum_size = Vector2(0, TITLE_H)
	_title_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_panel.gui_input.connect(_on_title_input)
	v.add_child(_title_panel)
	var row := HBoxContainer.new()
	row.set_meta("vt", true)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_title_panel.add_child(row)
	_icon = VerionTheme.icon("verion", 16, Color.WHITE)
	row.add_child(_icon)
	_title = VerionTheme.label("", 14, VerionTheme.TEXT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_title)
	_subtitle = VerionTheme.label("", 11, VerionTheme.MUTED)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.clip_text = true
	row.add_child(_subtitle)
	_add_ctl(row, "minimize", Color(1, 1, 1, 0.10), func(): minimize_pressed.emit(app))
	_max_icon = _add_ctl(row, "maximize", Color(1, 1, 1, 0.10), toggle_maximize)
	_add_ctl(row, "close", Color(0.90, 0.26, 0.26, 0.95), func(): close_pressed.emit(app))

	var m := MarginContainer.new()
	m.set_meta("vt", true)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + str(side), 10)
	v.add_child(m)
	body = VBoxContainer.new()
	body.set_meta("vt", true)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	# Ist der Inhalt breiter als das Fenster, lässt er sich waagerecht schieben.
	var hs := ScrollContainer.new()
	hs.set_meta("vt", true)
	hs.set_meta("outer", true)
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(hs)
	hs.add_child(body)
	_style()


func _add_ctl(row: HBoxContainer, kind: String, hover: Color, cb: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 24)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	VerionTheme.flat_button(b, Color(1, 1, 1, 0.0), hover, VerionTheme.TEXT, 6)
	var ic := VerionTheme.icon(kind, 12, VerionTheme.TEXT)
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.offset_left = -6.0
	ic.offset_right = 6.0
	ic.offset_top = -6.0
	ic.offset_bottom = 6.0
	b.add_child(ic)
	b.pressed.connect(cb)
	row.add_child(b)
	return ic


func set_title(title: String, subtitle: String, icon_kind: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	VerionTheme.set_icon(_icon, icon_kind)
	_icon.modulate = VerionTheme.app_color(app).lightened(0.15)


func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	_style()


func is_active_window() -> bool:
	return _active


func restyle() -> void:
	_style()


func _style() -> void:
	var dark := VerionTheme.dark
	var sb := VerionTheme.flat(VerionTheme.WINDOW if dark else VerionTheme.L_WINDOW, 0 if maximized else 10,
		VerionTheme.app_color(app).lerp(VerionTheme.BORDER, 0.35) if _active else (VerionTheme.BORDER if dark else Color(0.70, 0.74, 0.80)), 1)
	sb.shadow_color = Color(0, 0, 0, 0.55 if _active else 0.30)
	sb.shadow_size = 0 if maximized else (18 if _active else 9)
	sb.set_content_margin_all(1.0)
	add_theme_stylebox_override("panel", sb)
	var tb := VerionTheme.flat((VerionTheme.TITLE if _active else VerionTheme.TITLE_IDLE) if dark else VerionTheme.L_TITLE, 0)
	tb.corner_radius_top_left = 0 if maximized else 9
	tb.corner_radius_top_right = tb.corner_radius_top_left
	tb.border_color = VerionTheme.app_color(app) if _active else VerionTheme.BORDER
	tb.border_width_bottom = 1
	tb.content_margin_left = 12.0
	tb.content_margin_right = 6.0
	_title_panel.add_theme_stylebox_override("panel", tb)
	_title.add_theme_color_override("font_color", VerionTheme.TEXT if dark else Color(0.10, 0.12, 0.16))
	_subtitle.add_theme_color_override("font_color", VerionTheme.MUTED if dark else Color(0.36, 0.40, 0.46))
	for b in _title_panel.find_children("*", "Button", true, false):
		for ic in (b as Button).get_children():
			(ic as Control).modulate = VerionTheme.TEXT if dark else Color(0.18, 0.20, 0.24)


# ---------------------------------------------------------------- Größe und Lage

func _area() -> Vector2:
	var p := get_parent() as Control
	return p.size if p != null else Vector2(1280, 610)


func toggle_maximize() -> void:
	if maximized:
		maximized = false
		position = _restore_rect.position
		size = _restore_rect.size
	else:
		_restore_rect = Rect2(position, size)
		maximized = true
	VerionTheme.set_icon(_max_icon, "restore" if maximized else "maximize")
	fit()
	_style()
	SfxManager.play("click", -14.0, 1.2)


## Passt das Fenster in die Arbeitsfläche ein (nach Größenänderung des Bildschirms).
func fit() -> void:
	var a := _area()
	if a.x < 10.0:
		return
	if maximized:
		position = Vector2.ZERO
		size = a
		return
	size = Vector2(clampf(size.x, minf(MIN_SIZE.x, a.x), a.x), clampf(size.y, minf(MIN_SIZE.y, a.y), a.y))
	position = Vector2(clampf(position.x, -size.x + 120.0, a.x - 120.0), clampf(position.y, 0.0, a.y - TITLE_H))


func _on_title_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			focus_requested.emit(app)
			if mb.double_click:
				toggle_maximize()
				return
			_drag = true
			_drag_off = mb.global_position - global_position
		else:
			_drag = false
		return
	if event is InputEventMouseMotion and _drag:
		var mouse := (event as InputEventMouseMotion).global_position
		if maximized:
			# Maximiertes Fenster am Titel herunterziehen: normale Größe unter dem Mauszeiger.
			var rel := clampf(_drag_off.x / maxf(1.0, size.x), 0.1, 0.9)
			toggle_maximize()
			_drag_off = Vector2(size.x * rel, TITLE_H * 0.5)
		var p := get_parent() as Control
		position = mouse - _drag_off - (p.global_position if p != null else Vector2.ZERO)
		fit()


func _edge_at(pos: Vector2) -> Vector2:
	if maximized:
		return Vector2.ZERO
	var d := Vector2.ZERO
	if pos.x <= GRIP:
		d.x = -1.0
	elif pos.x >= size.x - GRIP:
		d.x = 1.0
	if pos.y <= GRIP * 0.5:
		d.y = -1.0
	elif pos.y >= size.y - GRIP:
		d.y = 1.0
	return d


func _cursor_for(d: Vector2) -> Control.CursorShape:
	if d == Vector2.ZERO:
		return Control.CURSOR_ARROW
	if d.x != 0.0 and d.y != 0.0:
		return Control.CURSOR_FDIAGSIZE if d.x == d.y else Control.CURSOR_BDIAGSIZE
	return Control.CURSOR_HSIZE if d.x != 0.0 else Control.CURSOR_VSIZE


func _input(event: InputEvent) -> void:
	# Ränder liegen über dem Inhalt, deshalb hier statt in _gui_input.
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion and _resize_dir != Vector2.ZERO:
		_do_resize((event as InputEventMouseMotion).global_position)
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		if _resize_dir != Vector2.ZERO:
			_resize_dir = Vector2.ZERO
			get_viewport().set_input_as_handled()
		_drag = false
		return
	var local := mb.global_position - global_position
	if not Rect2(Vector2.ZERO, size).has_point(local) or not _is_top_at(mb.global_position):
		return
	focus_requested.emit(app)
	var d := _edge_at(local)
	if d != Vector2.ZERO:
		_resize_dir = d
		_resize_start = Rect2(position, size)
		_resize_mouse = mb.global_position
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var local := get_global_mouse_position() - global_position
	if _resize_dir == Vector2.ZERO:
		mouse_default_cursor_shape = _cursor_for(_edge_at(local)) if Rect2(Vector2.ZERO, size).has_point(local) else Control.CURSOR_ARROW


## Liegt an dieser Stelle kein anderes Fenster darüber?
func _is_top_at(global: Vector2) -> bool:
	var p := get_parent()
	if p == null:
		return true
	if not (p as Control).get_global_rect().has_point(global):
		return false
	for i in range(get_index() + 1, p.get_child_count()):
		var o := p.get_child(i) as Control
		if o != null and o.visible and o.get_global_rect().has_point(global):
			return false
	# Menüs, Meldungen und das Anruf-Fenster liegen über den Fenstern.
	return not VerionDesktop.is_overlay_at(get_tree(), global)


func _do_resize(mouse: Vector2) -> void:
	var m := mouse - _resize_mouse
	var r := _resize_start
	var a := _area()
	if _resize_dir.x > 0.0:
		r.size.x = clampf(_resize_start.size.x + m.x, MIN_SIZE.x, a.x - r.position.x)
	elif _resize_dir.x < 0.0:
		var nx := clampf(_resize_start.position.x + m.x, 0.0, _resize_start.end.x - MIN_SIZE.x)
		r.size.x = _resize_start.end.x - nx
		r.position.x = nx
	if _resize_dir.y > 0.0:
		r.size.y = clampf(_resize_start.size.y + m.y, MIN_SIZE.y, a.y - r.position.y)
	elif _resize_dir.y < 0.0:
		var ny := clampf(_resize_start.position.y + m.y, 0.0, _resize_start.end.y - MIN_SIZE.y)
		r.size.y = _resize_start.end.y - ny
		r.position.y = ny
	position = r.position
	size = r.size
