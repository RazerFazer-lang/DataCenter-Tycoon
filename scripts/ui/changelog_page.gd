class_name ChangelogPage
extends HBoxContainer
## Reiter CHANGELOG im Hauptmenü: links alle Versionen (neueste oben, neue seit dem letzten Start markiert),
## rechts die gewählte Version mit ihren Punkten, nach Bereichen sortiert. Daten aus res://version.json.

signal version_selected(version: String)

## Bereiche in dieser Reihenfolge: [id, Name, Farbe]
const CATEGORIES := [
	["neu", "Neu", Color(0.93, 0.70, 0.30)],
	["gameplay", "Gameplay", Color(0.45, 0.76, 0.42)],
	["verbesserung", "Verbesserungen", Color(0.40, 0.70, 0.86)],
	["grafik", "Grafik & Ton", Color(0.78, 0.56, 0.90)],
	["coop", "Co-op & Server", Color(0.36, 0.80, 0.76)],
	["technik", "Technik & Launcher", Color(0.62, 0.66, 0.72)],
	["fix", "Fehler behoben", Color(0.90, 0.46, 0.40)],
	["sonst", "Sonstiges", Color(0.62, 0.64, 0.66)],
]

var _entries: Array = []
var _new_after := ""
var _list: VBoxContainer
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _buttons := {}
var _selected := ""
var _font: Font


## Bereich zu einer Kennung wie "NEU / STROM", "FIX" oder "CO-OP".
static func category_of(tag: String) -> String:
	var main := tag.split("/")[0].strip_edges().to_upper()
	match main:
		"NEU", "INHALT", "BRANDING":
			return "neu"
		"GAMEPLAY", "TECHNIKER", "BALANCE":
			return "gameplay"
		"VERBESSERUNG", "KOMFORT":
			return "verbesserung"
		"GRAFIK", "3D", "AUDIO":
			return "grafik"
		"CO-OP", "SERVER":
			return "coop"
		"PERFORMANCE", "TECHNIK", "SPIELSTAND", "LAUNCHER", "DOWNLOAD":
			return "technik"
		"FIX", "FEHLER":
			return "fix"
	return "sonst"


## Zusatz hinter dem Schrägstrich: "NEU / STROM" -> "STROM".
static func subtag_of(tag: String) -> String:
	var parts := tag.split("/", false, 1)
	return parts[1].strip_edges() if parts.size() == 2 else ""


## "Update 3.6.1: Lieferschein" -> "Lieferschein"
static func short_title(title: String) -> String:
	var re := RegEx.new()
	re.compile("^\\s*Update\\s+[0-9.]+\\s*[:–-]\\s*")
	return re.sub(title, "").strip_edges()


static func nice_date(iso: String) -> String:
	var p := iso.split("-")
	if p.size() != 3:
		return iso
	if TranslationServer.get_locale().begins_with("de"):
		return "%s.%s.%s" % [p[2], p[1], p[0]]
	return iso


static func category_color(id: String) -> Color:
	for c in CATEGORIES:
		if str(c[0]) == id:
			return c[2]
	return Color.WHITE


func setup(changelog: Array, new_after: String, font: Font = null) -> void:
	_font = font
	_new_after = new_after
	_entries = []
	for e in changelog:
		if e is Dictionary and str((e as Dictionary).get("version", "")) != "":
			_entries.append(e)
	_entries.sort_custom(func(a, b): return WhatsNew.compare(str(a["version"]), str(b["version"])) > 0)
	if _list == null:
		_build()
	_fill_list()
	if not _entries.is_empty():
		select(str(_entries[0]["version"]))


func is_new(version: String) -> bool:
	return _new_after != "" and WhatsNew.compare(version, _new_after) > 0


func selected() -> String:
	return _selected


func _build() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Linke Spalte: Versionen
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(236, 0)
	left.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.05, 0.055, 0.06, 0.85), Color(UIStyle.COL_BORDER, 0.6), 8, 1, 6, 6))
	add_child(left)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	ls.add_child(_list)
	# Rechte Spalte: Inhalt der Version
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	_detail_scroll.add_child(_detail)


func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for e in _entries:
		var v := str(e["version"])
		var b := Button.new()
		b.name = "Version_" + v.replace(".", "_")
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 54)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.clip_contents = true
		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 12
		inner.offset_right = -8
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 0)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(top)
		var vl := Label.new()
		vl.text = v
		vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIStyle.style_label(vl, 15, UIStyle.COL_TEXT_MAIN, _font)
		top.add_child(vl)
		if is_new(v):
			top.add_child(_pill(tr("NEU"), UIStyle.COL_ACCENT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(sp)
		var dl := Label.new()
		dl.text = nice_date(str(e.get("date", "")))
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIStyle.style_label(dl, 11, UIStyle.COL_TEXT_SUB)
		top.add_child(dl)
		var tl := Label.new()
		tl.text = short_title(str(e.get("title", "")))
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIStyle.style_label(tl, 12, UIStyle.COL_TEXT_SUB)
		inner.add_child(tl)
		b.pressed.connect(func() -> void:
			SfxManager.play("click", -12.0, 1.1)
			select(v)
		)
		_buttons[v] = b
		_list.add_child(b)
		_style_entry(b, false)


func _style_entry(b: Button, sel: bool) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(UIStyle.COL_ACCENT, 0.16) if sel else Color(0, 0, 0, 0)
	n.set_corner_radius_all(6)
	n.border_width_left = 3
	n.border_color = UIStyle.COL_ACCENT if sel else Color(0, 0, 0, 0)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(UIStyle.COL_ACCENT, 0.22) if sel else Color(1, 1, 1, 0.05)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)


func select(version: String) -> void:
	_selected = version
	for v in _buttons.keys():
		_style_entry(_buttons[v], v == version)
	var entry: Dictionary = {}
	for e in _entries:
		if str(e["version"]) == version:
			entry = e
	_show(entry)
	_detail_scroll.scroll_vertical = 0
	version_selected.emit(version)


func _show(e: Dictionary) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	if e.is_empty():
		return
	var items: Array = e.get("items", [])
	# Kopf
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var vl := Label.new()
	vl.text = str(e["version"])
	UIStyle.style_label(vl, 26, UIStyle.COL_GOLD_TEXT, _font)
	head.add_child(vl)
	if is_new(str(e["version"])):
		var pc := CenterContainer.new()
		pc.add_child(_pill(tr("NEU"), UIStyle.COL_ACCENT))
		head.add_child(pc)
	var tl := Label.new()
	tl.text = short_title(str(e.get("title", "")))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(tl, 17, UIStyle.COL_TEXT_MAIN)
	_detail.add_child(tl)
	var meta := Label.new()
	meta.text = tr("%s  ·  %d Änderungen") % [nice_date(str(e.get("date", ""))), items.size()]
	UIStyle.style_label(meta, 12, UIStyle.COL_TEXT_SUB)
	_detail.add_child(meta)
	# Kleine Übersicht: Bereich und Anzahl
	var groups := {}
	for it in items:
		var parts := WhatsNew.split_item(str(it))
		var cat := category_of(parts[0]) if parts[0] != "" else "sonst"
		if not groups.has(cat):
			groups[cat] = []
		(groups[cat] as Array).append(parts)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	_detail.add_child(chips)
	for c in CATEGORIES:
		if groups.has(c[0]):
			chips.add_child(_pill("%s  %d" % [tr(str(c[1])), (groups[c[0]] as Array).size()], c[2]))
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(UIStyle.COL_BORDER, 0.7)
	_detail.add_child(rule)
	# Punkte nach Bereich
	var n := 0
	for c in CATEGORIES:
		if not groups.has(c[0]):
			continue
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		_detail.add_child(gap)
		var gh := HBoxContainer.new()
		gh.add_theme_constant_override("separation", 8)
		_detail.add_child(gh)
		var bar := ColorRect.new()
		bar.color = c[2]
		bar.custom_minimum_size = Vector2(4, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gh.add_child(bar)
		var gl := Label.new()
		gl.text = tr(str(c[1])).to_upper()
		UIStyle.style_label(gl, 12, c[2], _font)
		gh.add_child(gl)
		for parts in groups[c[0]]:
			n += 1
			var row := HBoxContainer.new()
			row.name = "Punkt_%d" % n
			row.add_theme_constant_override("separation", 8)
			var dot := Label.new()
			dot.text = "•"
			UIStyle.style_label(dot, 14, c[2])
			dot.custom_minimum_size = Vector2(14, 0)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(dot)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 1)
			row.add_child(col)
			var sub := subtag_of(str(parts[0]))
			if sub != "":
				var sl := Label.new()
				sl.text = sub
				UIStyle.style_label(sl, 10, Color(c[2], 0.85))
				col.add_child(sl)
			var txt := Label.new()
			txt.text = str(parts[1])
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UIStyle.style_label(txt, 13, UIStyle.COL_TEXT_MAIN)
			col.add_child(txt)
			_detail.add_child(row)


func _pill(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.16)
	sb.border_color = Color(col, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(l, 10, col.lightened(0.15))
	p.add_child(l)
	return p
