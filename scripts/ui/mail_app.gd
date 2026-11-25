class_name MailApp
extends RefCounted
## Postfach im PC: links Ordner, in der Mitte die Liste, rechts die geöffnete E-Mail.
## Daten und Aktionen kommen aus MailManager. state merkt sich Ordner und Auswahl:
## {"folder": "all", "mail": "M12", "msg": "", "ok": true}

const T := preload("res://scripts/ui/finance_apps.gd")
const FOLDERS: Array[String] = ["all", "unread", "todo", "bill", "customer", "contract", "order", "bank", "city", "rival", "job", "spam", "system"]


static func folder_mails(folder: String) -> Array:
	var out: Array = []
	for m_v in MailManager.mails:
		var m: Dictionary = m_v
		match folder:
			"all":
				out.append(m)
			"unread":
				if not bool(m.get("read", false)):
					out.append(m)
			"todo":
				if not MailManager.actions_of(m).is_empty() and str(m.get("kind", "")) != "praise":
					out.append(m)
			_:
				if str(m.get("cat", "")) == folder:
					out.append(m)
	return out


static func render(host: Control, state: Dictionary, refresh: Callable, open_app: Callable) -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	host.add_child(split)
	_render_folders(split, state, refresh)
	var mails := folder_mails(str(state.get("folder", "all")))
	_render_list(split, mails, state, refresh)
	_render_reader(split, state, refresh, open_app)


static func _render_folders(split: HBoxContainer, state: Dictionary, refresh: Callable) -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(172, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	sc.add_child(col)
	for f in FOLDERS:
		var n := folder_mails(f).size() if f == "todo" else _unread(f)
		var name := "Posteingang" if f == "all" else ("Ungelesen" if f == "unread" else ("Zu erledigen" if f == "todo" else str(MailManager.CATS[f]["name"])))
		var sel: bool = str(state.get("folder", "all")) == f
		var b := Button.new()
		b.text = "%s%s" % [T._t(name), ("  (%d)" % n) if n > 0 else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 29)
		b.add_theme_font_size_override("font_size", 12)
		_flat(b, Color(0.10, 0.46, 0.82) if sel else Color(0.95, 0.96, 0.97, 0.0), Color(0.10, 0.46, 0.82) if sel else Color(0.88, 0.90, 0.93), Color.WHITE if sel else T.COL_TEXT)
		b.pressed.connect(func():
			state["folder"] = f
			SfxManager.play("click", -12.0, 1.1)
			refresh.call()
		)
		col.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	if MailManager.get_unread_count() > 0:
		var ra := T._button("Alle gelesen", Color(0.42, 0.48, 0.58), MailManager.request_read_all)
		col.add_child(ra)


static func _unread(folder: String) -> int:
	var n := 0
	for m in folder_mails(folder):
		if not bool((m as Dictionary).get("read", false)):
			n += 1
	return n


static func _render_list(split: HBoxContainer, mails: Array, state: Dictionary, refresh: Callable) -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(304, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	sc.add_child(col)
	if mails.is_empty():
		col.add_child(T._label("Keine E-Mails in diesem Ordner.", 13, T.COL_MUTED, true))
	for m_v in mails:
		var m: Dictionary = m_v
		var id := str(m["id"])
		var unread := not bool(m.get("read", false))
		var sel: bool = str(state.get("mail", "")) == id
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.clip_contents = true
		_flat(b, Color(0.86, 0.92, 0.99) if sel else Color.WHITE, Color(0.90, 0.94, 0.99), T.COL_TEXT)
		b.pressed.connect(func():
			state["mail"] = id
			state["msg"] = ""
			if not bool(MailManager.find(id).get("read", false)):
				MailManager.request_read(id)
			SfxManager.play("click", -13.0, 1.15)
			refresh.call()
		)
		col.add_child(b)
		var mg := MarginContainer.new()
		mg.set_anchors_preset(Control.PRESET_FULL_RECT)
		mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right"]:
			mg.add_theme_constant_override("margin_" + str(side), 9)
		for side in ["top", "bottom"]:
			mg.add_theme_constant_override("margin_" + str(side), 5)
		b.add_child(mg)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		mg.add_child(row)
		var cat: Dictionary = MailManager.CATS.get(str(m.get("cat", "system")), MailManager.CATS["system"])
		row.add_child(T._icon(str(cat["icon"]), 18, T.COL_BAD if bool(m.get("urgent", false)) and MailManager.status_of(m) == "" else (T.COL_ACCENT if unread else T.COL_MUTED)))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		row.add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var fl := T._label(str(m["from"]), 13, T.COL_TEXT if unread else T.COL_MUTED)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.clip_text = true
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(fl)
		top.add_child(T._label(_when(m), 11, T.COL_MUTED))
		var sl := T._label(MailManager.text_of(m["subject"]), 12, T.COL_TEXT if unread else T.COL_MUTED)
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(sl)
		if unread:
			var dot := ColorRect.new()
			dot.set_anchors_preset(Control.PRESET_LEFT_WIDE)
			dot.offset_right = 3.0
			dot.color = T.COL_ACCENT
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(dot)


static func _render_reader(split: HBoxContainer, state: Dictionary, refresh: Callable, open_app: Callable) -> void:
	var panel := T._card(split)
	var outer := panel.get_parent() as PanelContainer
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var id := str(state.get("mail", ""))
	var m := MailManager.find(id)
	if m.is_empty():
		var sp := CenterContainer.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(sp)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		sp.add_child(v)
		var ic := T._icon("mail", 56, Color(0.62, 0.68, 0.76))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(T._label("Wähle links eine E-Mail aus.", 14, T.COL_MUTED))
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	panel.add_child(head)
	var subj := T._label(MailManager.text_of(m["subject"]), 18, T.COL_TEXT, true)
	head.add_child(subj)
	var del := T._button("Löschen", Color(0.46, 0.50, 0.58), func():
		state["mail"] = ""
		MailManager.request_delete(id)
	)
	head.add_child(del)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 10)
	panel.add_child(fr)
	fr.add_child(_avatar(str(m["from"])))
	var fv := VBoxContainer.new()
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.add_theme_constant_override("separation", 0)
	fr.add_child(fv)
	fv.add_child(T._label(str(m["from"]), 14, T.COL_TEXT))
	fv.add_child(T._label(str(m["addr"]), 12, T.COL_MUTED))
	fr.add_child(T._label(_when(m), 12, T.COL_MUTED))
	var sep := ColorRect.new()
	sep.color = Color(0.82, 0.85, 0.89)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.set_meta("vt", true)
	sep.modulate.a = 0.35
	panel.add_child(sep)
	if MailManager.is_flagged(m) and MailManager.status_of(m) == "":
		T._feedback_bar(panel, "Die Buchhaltung warnt: Absender und Text passen nicht zusammen. Vermutlich Betrug.", false)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	sc.add_child(body)
	for line in m.get("body", []):
		body.add_child(T._label(MailManager.text_of(line), 14, T.COL_TEXT, true))
	var status := MailManager.status_of(m)
	if status != "":
		body.add_child(T._label(T._t("Stand: %s") % T._t(status), 13, T.COL_GOOD if not status.begins_with("Auf Betrug") else T.COL_BAD))
	if str(state.get("msg", "")) != "":
		T._feedback_bar(panel, str(state["msg"]), bool(state.get("ok", true)))
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 6)
	panel.add_child(acts)
	for a_v in MailManager.actions_of(m):
		var a: Dictionary = a_v
		var aid := str(a["id"])
		var col: Color = {"good": T.COL_GOOD, "accent": T.COL_ACCENT}.get(str(a.get("style", "plain")), Color(0.42, 0.48, 0.58))
		acts.add_child(T._button(MailManager.text_of(a["label"]), col, func():
			if aid.begins_with("open:"):
				open_app.call(aid.substr(5))
			else:
				MailManager.request_action(id, aid)
				refresh.call()
		))
	if status == "" and str(m.get("cat", "")) != "system":
		acts.add_child(T._button("Als Betrug melden", T.COL_BAD, func(): MailManager.request_report(id)))


static func _avatar(from: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(38, 38)
	var h := float(absi(from.hash()) % 360) / 360.0
	var col := Color.from_hsv(h, 0.55, 0.72)
	c.draw.connect(func():
		c.draw_circle(Vector2(19, 19), 18.0, col)
		c.draw_string(ThemeDB.fallback_font, Vector2(0, 26), from.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 38, 19, Color.WHITE)
	)
	return c


static func _when(m: Dictionary) -> String:
	var mins := int(fposmod(float(m.get("tod", 0.5)), 1.0) * 1440.0)
	return T._t("Tag %d, %s") % [int(m.get("day", 1)), "%02d:%02d" % [mins / 60, mins % 60]]


static func _flat(b: Button, bg: Color, hover: Color, txt: Color) -> void:
	for st in [["normal", bg], ["hover", hover], ["pressed", hover], ["disabled", bg]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10.0
		sb.content_margin_right = 8.0
		b.add_theme_stylebox_override(str(st[0]), sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, txt)
