class_name DeliveryNoteUI
extends Control
## Lieferschein auf dem Klemmbrett des Fahrers: Positionen, Datum, Fahrzeug, Unterschrift des Fahrers
## und ein Feld, in dem der Spieler mit der Maus selbst unterschreibt. Daten kommen aus GameState.van_plan["doc"].

signal closed

const BOARD := Vector2(780, 1090)
const PAPER_POS := Vector2(30, 74)
const PAPER := Vector2(720, 948)
const MAX_ROWS := 10
const TXT := Color(0.13, 0.14, 0.17)
const SUB := Color(0.40, 0.42, 0.46)
const BRAND := Color(0.09, 0.27, 0.52)
const RULE := Color(0.72, 0.73, 0.75)
const STAMP := Color(0.78, 0.14, 0.12, 0.88)

var _board: Control
var _paper: PanelContainer
var _body: VBoxContainer
var _pad: SignaturePad
var _sign_btn: Button
var _clear_btn: Button
var _cancel_btn: Button
var _status: Label
var _stamp: PanelContainer
var _stamp_date: Label
var _sent := false
var _closing := false
var _font_r: SystemFont
var _font_b: SystemFont
var _font_m: SystemFont
# Der Stift: liegt am Brett und folgt der Maus, sobald sie über dem Papier ist.
var _pen: Control
var _pen_pos := Vector2.ZERO
var _pen_angle := -0.95
var _pen_lift := 1.0
var _pen_held := false
var _pen_blend := 1.0
var _pen_from := Vector2.ZERO
var _pen_vx := 0.0
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font_r = SystemFont.new()
	_font_r.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	_font_b = SystemFont.new()
	_font_b.font_names = _font_r.font_names
	_font_b.font_weight = 700
	_font_m = SystemFont.new()
	_font_m.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_board = Control.new()
	_board.size = BOARD
	_board.pivot_offset = BOARD * 0.5
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	add_child(_board)
	_paper = PanelContainer.new()
	_paper.position = PAPER_POS
	_paper.size = PAPER
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.976, 0.972, 0.948)
	ps.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	ps.shadow_size = 5
	ps.shadow_offset = Vector2(0, 2)
	ps.set_content_margin_all(0)
	_paper.add_theme_stylebox_override("panel", ps)
	_paper.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_paper)
	# Klemme über dem Papier
	var clip := Control.new()
	clip.position = Vector2(BOARD.x * 0.5 - 130, 10)
	clip.size = Vector2(260, 74)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.draw.connect(func() -> void: _draw_clip(clip))
	_board.add_child(clip)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 34)
	m.add_theme_constant_override("margin_top", 46)
	m.add_theme_constant_override("margin_bottom", 22)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	_paper.add_child(m)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(_body)
	# Knöpfe unten auf dem Brett
	var row := HBoxContainer.new()
	row.position = Vector2(30, BOARD.y - 62)
	row.size = Vector2(PAPER.x, 44)
	row.add_theme_constant_override("separation", 10)
	_board.add_child(row)
	_status = _l("", 14, Color(0.97, 0.93, 0.84), _font_r)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_status)
	_clear_btn = _button(tr("Neu zeichnen"), Color(0.22, 0.17, 0.12, 0.92))
	_clear_btn.pressed.connect(func() -> void: _pad.clear())
	row.add_child(_clear_btn)
	_cancel_btn = _button(tr("Abbrechen  [Esc]"), Color(0.22, 0.17, 0.12, 0.92))
	_cancel_btn.pressed.connect(close)
	row.add_child(_cancel_btn)
	_sign_btn = _button(tr("Unterzeichnen"), Color(0.12, 0.36, 0.20, 0.97), UIStyle.COL_GREEN)
	_sign_btn.pressed.connect(_on_sign)
	row.add_child(_sign_btn)
	_pen = Control.new()
	_pen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pen.draw.connect(_draw_pen)
	add_child(_pen)
	visible = false
	resized.connect(_fit)
	GameState.van_updated.connect(_on_van_updated)


## Schein öffnen und dem Host sagen, dass hier gerade jemand unterschreibt (der Fahrer wartet dann).
func open() -> void:
	_sent = false
	_closing = false
	_build_doc(GameState.van_plan.get("doc", {}))
	_fit()
	_pen_held = false
	_pen_blend = 1.0
	_pen_pos = _parked()[0]
	visible = true
	modulate.a = 0.0
	var y0 := _board.position.y
	_board.position.y = y0 + 60.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_board, "position:y", y0, 0.26)
	SfxManager.play("click", -10.0, 0.8)
	GameState.request_delivery_note(true)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	if not _sent:
		GameState.request_delivery_note(false)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tw.chain().tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		_closing = false
		closed.emit()
	)


func is_signed() -> bool:
	return _sent


func _fit() -> void:
	if _board == null:
		return
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var s := minf(1.0, minf((vp.y - 24.0) / BOARD.y, (vp.x - 32.0) / BOARD.x))
	_board.scale = Vector2(s, s)
	_board.position = (vp - BOARD) * 0.5


func _on_sign() -> void:
	if _sent or _pad == null or _pad.ink() < DeliveryNote.MIN_INK:
		return
	var strokes := _pad.strokes_normalized()
	if not DeliveryNote.valid_signature(strokes):
		_status.text = tr("Das ist noch keine Unterschrift. Bitte richtig unterschreiben.")
		return
	_sent = true
	_pad.readonly = true
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_buttons()
	_status.text = tr("Wird übergeben …")
	GameState.request_sign_delivery(strokes)
	# Kommt keine Antwort (Host hat abgelehnt), darf man es noch einmal versuchen.
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if visible and _sent and GameState.van_trip_phase == "sign":
			_sent = false
			_pad.readonly = false
			_pad.mouse_filter = Control.MOUSE_FILTER_STOP
			_update_buttons()
			_status.text = tr("Das hat nicht geklappt. Bitte noch einmal unterschreiben.")
	)


func _on_van_updated() -> void:
	if not visible or _closing:
		return
	if _sent and GameState.van_trip_phase != "sign":
		_show_stamp()
		return
	if GameState.van_phase != "unloading" or GameState.van_trip_phase != "sign":
		_status.text = tr("Der Fahrer ist schon weiter.")
		get_tree().create_timer(1.2).timeout.connect(close)
		return
	var who := GameState.van_sign_peer
	if who != 0 and who != multiplayer.get_unique_id():
		_status.text = tr("%s unterschreibt gerade.") % NetworkManager.get_player_name(who)
	_update_buttons()


func _show_stamp() -> void:
	if _stamp == null or _stamp.visible:
		return
	_stamp_date.text = tr("Tag %d · %s Uhr") % [GameState.day_number, GameState.get_time_string()]
	_stamp.visible = true
	_stamp.reset_size()
	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.scale = Vector2(1.6, 1.6)
	_stamp.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_stamp, "scale", Vector2.ONE, 0.22)
	tw.tween_property(_stamp, "modulate:a", 1.0, 0.12)
	SfxManager.play("place", -4.0, 0.7)
	_status.text = tr("Unterschrieben. Danke!")
	get_tree().create_timer(1.5).timeout.connect(close)


func _update_buttons() -> void:
	if _sign_btn == null:
		return
	var other := GameState.van_sign_peer != 0 and GameState.van_sign_peer != multiplayer.get_unique_id()
	var enough := _pad != null and _pad.ink() >= DeliveryNote.MIN_INK
	_sign_btn.disabled = _sent or other or not enough
	_clear_btn.disabled = _sent or _pad == null or _pad.is_empty()
	_cancel_btn.disabled = _sent
	if not _sent and not other:
		_status.text = tr("Stift nehmen: Maus aufs Papier. Mit gedrückter linker Maustaste unterschreiben.") if not enough else tr("Passt die Unterschrift? Dann auf Unterzeichnen drücken.")


# ---------------------------------------------------------------- Inhalt

func _build_doc(doc: Dictionary) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if doc.is_empty():
		doc = DeliveryNote.build(GameState.van_plan, GameState.van_delivery_tier, GameState.van_site, 0, GameState.day_number, GameState.get_time_string(), GameState.current_save_name, 1)
	# Kopf: Absender links, Belegart rechts
	var head := HBoxContainer.new()
	_body.add_child(head)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 8)
	left.add_child(logo)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(34, 30)
	mark.draw.connect(func() -> void: _draw_cloud(mark))
	logo.add_child(mark)
	logo.add_child(_l("CLOUD EXPRESS", 24, BRAND, _font_b))
	left.add_child(_l("%s · %s" % [DeliveryNote.COMPANY, DeliveryNote.COMPANY_ADDR], 11, SUB, _font_r))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	head.add_child(right)
	var title := _l(tr("LIEFERSCHEIN"), 24, TXT, _font_b)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(title)
	var no := _l(tr("Nr. %s") % str(doc.get("no", "")), 14, TXT, _font_m)
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(no)
	_body.add_child(_rule(BRAND, 2))
	# Angaben in zwei Spalten
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	_body.add_child(grid)
	var site: Array = DeliveryNote.SITE_ADDR.get(str(doc.get("site", "garage")), DeliveryNote.SITE_ADDR["garage"])
	var tmeta: Dictionary = GameState.DELIVERY_TIER_META.get(int(doc.get("tier", 1)), GameState.DELIVERY_TIER_META[1])
	var info := [
		["Empfänger", str(doc.get("company", ""))], ["Lieferdatum", tr("Tag %d") % int(doc.get("day", 1))],
		["Lieferadresse", "%s, %s" % [tr(str(site[0])), tr(str(site[1]))]], ["Uhrzeit", tr("%s Uhr") % str(doc.get("time", ""))],
		["Fahrzeug", tr(str(tmeta.get("name", "")))], ["Kennzeichen", str(doc.get("plate", ""))],
		["Fahrer", str(doc.get("driver", ""))], ["Packstücke", tr("%d Stück · ca. %d kg") % [int(doc.get("packages", 0)), int(doc.get("kg", 0))]],
	]
	for pair in info:
		var k := _l(tr(str(pair[0])) + ":", 12, SUB, _font_r)
		grid.add_child(k)
		var v := _l(str(pair[1]), 13, TXT, _font_b)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.clip_text = true
		grid.add_child(v)
	_body.add_child(_spacer(4))
	_table(doc.get("lines", []))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(fill)
	# Bestätigung und Unterschriften
	var ok_row := HBoxContainer.new()
	ok_row.add_theme_constant_override("separation", 9)
	_body.add_child(ok_row)
	var box := Control.new()
	box.custom_minimum_size = Vector2(15, 15)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.draw.connect(func() -> void:
		box.draw_rect(Rect2(Vector2(0.5, 0.5), Vector2(14, 14)), TXT, false, 1.2)
		box.draw_polyline(PackedVector2Array([Vector2(2.5, 7.5), Vector2(6.0, 12.0), Vector2(15.5, -1.0)]), SignaturePad.INK, 2.2, true)
	)
	ok_row.add_child(box)
	ok_row.add_child(_l(tr("Ware vollständig und ohne äußerlich erkennbare Schäden erhalten."), 13, TXT, _font_r))
	var sig := HBoxContainer.new()
	sig.add_theme_constant_override("separation", 26)
	_body.add_child(sig)
	var dcol := VBoxContainer.new()
	dcol.custom_minimum_size = Vector2(230, 0)
	sig.add_child(dcol)
	dcol.add_child(_l(tr("Unterschrift Fahrer"), 11, SUB, _font_r))
	var dpad := SignaturePad.new()
	dpad.readonly = true
	dpad.custom_minimum_size = Vector2(230, 96)
	dcol.add_child(dpad)
	dcol.add_child(_rule(RULE, 2))
	dcol.add_child(_l(str(doc.get("driver", "")), 12, TXT, _font_r))
	dpad.set_strokes(DeliveryNote.driver_signature(int(doc.get("seed", 1))))
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sig.add_child(rcol)
	rcol.add_child(_l(tr("Unterschrift Empfänger"), 11, SUB, _font_r))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 124)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	rcol.add_child(holder)
	_pad = SignaturePad.new()
	_pad.hint = tr("Hier unterschreiben")
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.changed.connect(_update_buttons)
	holder.add_child(_pad)
	# Stempel „ERHALTEN“ mit Datum, schräg über der Unterschrift
	_stamp = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = STAMP
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	_stamp.add_theme_stylebox_override("panel", sb)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -2)
	_stamp.add_child(sv)
	var st := _l(tr("ERHALTEN"), 26, STAMP, _font_b)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(st)
	_stamp_date = _l("", 13, STAMP, _font_b)
	_stamp_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_stamp_date)
	_stamp.position = Vector2(170, 10)
	_stamp.rotation_degrees = -11.0
	_stamp.visible = false
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_stamp)
	rcol.add_child(_rule(RULE, 2))
	rcol.add_child(_l(tr("Name: %s") % NetworkManager.local_player_name, 12, TXT, _font_r))
	_body.add_child(_spacer(2))
	var foot := _l(tr("Es gelten die AGB der Cloud Express Logistik GmbH. Reklamationen bitte innerhalb von 24 Stunden melden. Durchschlag für den Empfänger."), 10, SUB, _font_r)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(foot)
	_update_buttons()


func _table(lines: Array) -> void:
	var cols := [["Pos.", 44], ["Art.-Nr.", 92], ["Artikel", 0], ["Menge", 64], ["Einheit", 66]]
	var head := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.88, 0.89, 0.90)
	hs.set_content_margin_all(5)
	head.add_theme_stylebox_override("panel", hs)
	_body.add_child(head)
	head.add_child(_row(cols, cols.map(func(c): return tr(str(c[0]))), true))
	var shown := mini(lines.size(), MAX_ROWS)
	for i in shown:
		var ln: Dictionary = lines[i]
		var art := tr(str(ln.get("name", "")))
		var extra := str(ln.get("extra", ""))
		if extra != "":
			art += "  ·  " + _tr_extra(extra)
		var r := _row(cols, [str(i + 1), str(ln.get("sku", "")), art, str(int(ln.get("qty", 1))), tr(str(ln.get("unit", "Stk.")))], false)
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_left", 5)
		wrap.add_theme_constant_override("margin_right", 5)
		wrap.add_child(r)
		_body.add_child(wrap)
		_body.add_child(_rule(Color(0.88, 0.88, 0.89), 2))
	if lines.size() > shown:
		_body.add_child(_l(tr("… und %d weitere Positionen") % (lines.size() - shown), 12, SUB, _font_r))


func _tr_extra(extra: String) -> String:
	# "12 Teile" kommt als fertiger Text vom Host, die Zahl bleibt, das Wort wird übersetzt.
	var parts := extra.split(" ", false, 1)
	if parts.size() == 2 and parts[0].is_valid_int():
		return tr("%d Teile") % int(parts[0])
	return tr(extra)


func _row(cols: Array, vals: Array, bold: bool) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	for i in cols.size():
		var mono: bool = i == 1 or i == 3
		var lbl := _l(str(vals[i]), 12 if bold else 13, TXT, _font_b if bold else (_font_m if mono else _font_r))
		var w := int(cols[i][1])
		if w > 0:
			lbl.custom_minimum_size = Vector2(w, 0)
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
		if i == 3:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(lbl)
	return r


# ---------------------------------------------------------------- Stift

## Wo der Stift liegt, wenn man ihn nicht hält: rechts am Rand des Klemmbretts. [Spitze, Winkel]
func _parked() -> Array:
	return [_board.get_global_transform() * Vector2(BOARD.x - 15.0, 470.0), -PI * 0.5]


func _process(delta: float) -> void:
	if not visible or _board == null:
		return
	var mouse := get_global_mouse_position()
	var over := not _sent and not _closing and _paper.get_global_rect().has_point(mouse)
	if over != _pen_held:
		_pen_held = over
		_pen_from = _pen_pos
		_pen_blend = 0.0
		if over:
			SfxManager.play("click", -20.0, 1.7)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if over else Input.MOUSE_MODE_VISIBLE
	var park: Array = _parked()
	var target: Vector2 = mouse if _pen_held else park[0]
	var target_angle: float = -0.95 if _pen_held else float(park[1])
	_pen_blend = minf(1.0, _pen_blend + delta / 0.14)
	var e := 1.0 - pow(1.0 - _pen_blend, 3.0)
	_pen_pos = _pen_from.lerp(target, e) if _pen_blend < 1.0 else target
	# Leichtes Kippen mit der Bewegung, wie eine Hand, die schreibt.
	var vx := (mouse.x - _last_mouse.x) / maxf(delta, 0.001)
	_last_mouse = mouse
	_pen_vx = lerpf(_pen_vx, vx, clampf(delta * 8.0, 0.0, 1.0))
	var tilt := clampf(_pen_vx * 0.00012, -0.10, 0.10) if _pen_held else 0.0
	_pen_angle = lerp_angle(_pen_angle, target_angle + tilt, clampf(delta * (18.0 if _pen_held else 10.0), 0.0, 1.0))
	var pressing := _pen_held and _pad != null and _pad.is_drawing()
	var lift_target := 0.0 if pressing else (1.0 if _pen_held else 0.15)
	_pen_lift = lerpf(_pen_lift, lift_target, clampf(delta * 22.0, 0.0, 1.0))
	_pen.queue_redraw()


## Halbe Breite des Stifts an der Stelle x (0 = Spitze, 160 = Ende).
static func _pen_hw(x: float) -> float:
	if x < 16.0:
		return lerpf(0.9, 4.3, x / 16.0)
	if x < 54.0:
		return 4.9
	if x < 150.0:
		return 5.1
	return lerpf(5.1, 3.6, (x - 150.0) / 10.0)


## Ein echter Kugelschreiber ist fast halb so lang wie ein A4-Blatt. 2× ergibt gut ein Drittel.
const PEN_SCALE := 2.0


func _draw_pen() -> void:
	var s := _board.scale.x * PEN_SCALE
	var rot := Transform2D(_pen_angle, Vector2.ZERO)
	var axis := rot * Vector2(1, 0)
	var nrm := rot * Vector2(0, 1)
	# Schatten: beginnt an der Spitze und fällt nach rechts unten, gehoben weiter weg.
	var lift_off := Vector2(4.0, 6.0) * (0.25 + _pen_lift) * s
	var sh := PackedVector2Array()
	var xs := [0.0, 4.0, 10.0, 16.0, 30.0, 54.0, 90.0, 130.0, 150.0, 160.0]
	for x: float in xs:
		var drop: Vector2 = Vector2(16.0, 22.0) * (x / 160.0) * (0.45 + _pen_lift * 0.8) * s + lift_off * (x / 160.0 + 0.25)
		sh.append(_pen_pos + axis * x * s - nrm * _pen_hw(x) * s + drop)
	for i in range(xs.size() - 1, -1, -1):
		var x: float = xs[i]
		var drop: Vector2 = Vector2(16.0, 22.0) * (x / 160.0) * (0.45 + _pen_lift * 0.8) * s + lift_off * (x / 160.0 + 0.25)
		sh.append(_pen_pos + axis * x * s + nrm * _pen_hw(x) * s * 1.3 + drop)
	_pen.draw_colored_polygon(sh, Color(0.0, 0.0, 0.0, 0.16 + 0.06 * (1.0 - _pen_lift)))
	# Stift selbst, im eigenen Koordinatensystem: x entlang des Stifts, Spitze bei 0.
	var lift_scale := 1.0 + 0.035 * _pen_lift
	_pen.draw_set_transform(_pen_pos, _pen_angle, Vector2(s, s) * lift_scale)
	var chrome_l := Color(0.86, 0.88, 0.91)
	var chrome_d := Color(0.46, 0.48, 0.52)
	var grip := Color(0.17, 0.18, 0.20)
	var barrel := Color(0.11, 0.20, 0.46)
	var barrel_l := Color(0.34, 0.48, 0.80)
	# Spitze (Kegel aus Chrom, oben hell, unten dunkel)
	_pen.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(16, -4.3), Vector2(16, 0)]), chrome_l)
	_pen.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(16, 4.3)]), chrome_d)
	_pen.draw_circle(Vector2(0.6, 0), 0.9, Color(0.20, 0.21, 0.24), true, -1.0, true)
	# Griffzone mit Rillen
	_pen.draw_rect(Rect2(16, -4.9, 38, 9.8), grip)
	for k in 9:
		var gx := 19.0 + k * 4.0
		_pen.draw_line(Vector2(gx, -4.9), Vector2(gx, 4.9), Color(0.08, 0.08, 0.09), 1.2, true)
	_pen.draw_line(Vector2(16, -3.2), Vector2(54, -3.2), Color(0.36, 0.37, 0.40), 1.0, true)
	# Schaft mit Glanzkante
	_pen.draw_rect(Rect2(54, -5.1, 96, 10.2), barrel)
	_pen.draw_line(Vector2(56, -2.6), Vector2(148, -2.6), barrel_l, 1.6, true)
	_pen.draw_line(Vector2(56, 3.6), Vector2(148, 3.6), Color(0.05, 0.09, 0.22), 1.4, true)
	_pen.draw_rect(Rect2(52, -5.2, 3, 10.4), chrome_l)
	# Kappe und Druckknopf
	_pen.draw_colored_polygon(PackedVector2Array([Vector2(150, -5.1), Vector2(160, -3.6), Vector2(160, 3.6), Vector2(150, 5.1)]), chrome_d)
	_pen.draw_line(Vector2(150, -3.4), Vector2(159, -2.4), chrome_l, 1.4, true)
	_pen.draw_rect(Rect2(160, -2.4, 5, 4.8), Color(0.62, 0.64, 0.68))
	# Clip
	_pen.draw_rect(Rect2(110, -7.6, 38, 2.6), chrome_l)
	_pen.draw_rect(Rect2(110, -5.2, 38, 0.8), chrome_d)
	_pen.draw_circle(Vector2(110.5, -6.3), 1.6, chrome_l, true, -1.0, true)
	_pen.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- Zeichnen

func _draw_board() -> void:
	var r := Rect2(Vector2.ZERO, BOARD)
	_board.draw_style_box(_box(Color(0.47, 0.32, 0.19), Color(0, 0, 0, 0.45), 18, 14), r)
	# Maserung
	for i in 22:
		var y := 30.0 + i * 48.0 + sin(i * 1.7) * 9.0
		var c := Color(0.36, 0.23, 0.13, 0.20 + 0.10 * sin(i * 2.3))
		var pts := PackedVector2Array()
		for k in 13:
			var x := k * BOARD.x / 12.0
			pts.append(Vector2(x, y + sin(k * 0.9 + i) * 4.0))
		_board.draw_polyline(pts, c, 1.4, true)
	_board.draw_circle(Vector2(BOARD.x * 0.5, 26), 7.0, Color(0.30, 0.20, 0.12), true, -1.0, true)


func _draw_clip(c: Control) -> void:
	var r := Rect2(Vector2(0, 8), Vector2(c.size.x, c.size.y - 8))
	c.draw_style_box(_box(Color(0.66, 0.68, 0.71), Color(0, 0, 0, 0.40), 10, 5), r)
	c.draw_style_box(_box(Color(0.83, 0.85, 0.88), Color(0, 0, 0, 0), 8, 0), r.grow(-4))
	# Glanzkante und Biegung der Klemme
	c.draw_rect(Rect2(14, 14, c.size.x - 28, 3), Color(1, 1, 1, 0.55))
	c.draw_rect(Rect2(20, r.end.y - 18, c.size.x - 40, 6), Color(0.52, 0.54, 0.57))
	# Loch zum Aufhängen
	c.draw_circle(Vector2(c.size.x * 0.5, 22), 7.5, Color(0.30, 0.20, 0.12), true, -1.0, true)
	c.draw_arc(Vector2(c.size.x * 0.5, 22), 7.5, 0.0, TAU, 24, Color(0.45, 0.47, 0.50), 1.5, true)


func _draw_cloud(c: Control) -> void:
	var col := BRAND
	c.draw_circle(Vector2(11, 18), 8.0, col, true, -1.0, true)
	c.draw_circle(Vector2(19, 12), 10.0, col, true, -1.0, true)
	c.draw_circle(Vector2(27, 18), 7.0, col, true, -1.0, true)
	c.draw_rect(Rect2(11, 18, 16, 7), col)
	c.draw_line(Vector2(2, 28), Vector2(32, 28), Color(0.86, 0.47, 0.12), 2.5, true)


func _box(bg: Color, shadow: Color, radius: int, shadow_size: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	s.shadow_offset = Vector2(0, 6) if shadow_size > 0 else Vector2.ZERO
	s.anti_aliasing = true
	return s


func _l(text: String, fsize: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule(col: Color, h: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, bg: Color, accent: Color = UIStyle.COL_ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 15)
	UIStyle.style_button(b, bg, accent)
	return b
