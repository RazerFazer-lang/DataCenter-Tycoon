class_name WhatsNew
extends Control
## „Neu in dieser Version“ (REL-06): Nach einem Update zeigt das Hauptmenü einmal, was sich geändert hat.
## Die Einträge kommen aus res://version.json, derselben Datei, aus der der Launcher seine Patchnotes liest.

signal closed

## So viele Versionen zeigt das Fenster höchstens (die neuesten zuerst).
const MAX_VERSIONS := 3
const SOURCE := "res://version.json"

var _card: PanelContainer


## "v3.4.0" oder "3.4" -> [3, 4, 0]. Unbrauchbares wird zu 0.
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	var clean := v.strip_edges().trim_prefix("v").trim_prefix("V")
	for part in clean.split("."):
		var digits := ""
		for ch in part:
			if ch >= "0" and ch <= "9":
				digits += ch
			else:
				break
		out.append(int(digits) if not digits.is_empty() else 0)
	while out.size() < 3:
		out.append(0)
	return out


## -1, 0 oder 1 wie bei einem Vergleich a < b, a == b, a > b.
static func compare(a: String, b: String) -> int:
	var pa := parse_version(a)
	var pb := parse_version(b)
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i] if i < pa.size() else 0
		var y := pb[i] if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func load_changelog(path: String = SOURCE) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("changelog", []) is Array):
		return []
	return (parsed as Dictionary)["changelog"]


## Einträge, die neuer sind als after und höchstens upto, neueste zuerst. after "" = alle bis upto.
static func entries_between(changelog: Array, after: String, upto: String, limit: int = MAX_VERSIONS) -> Array:
	var out: Array = []
	for e in changelog:
		if not (e is Dictionary):
			continue
		var v := str((e as Dictionary).get("version", ""))
		if v.is_empty() or compare(v, upto) > 0:
			continue
		if not after.is_empty() and compare(v, after) <= 0:
			continue
		out.append(e)
	out.sort_custom(func(x, y): return compare(str(x["version"]), str(y["version"])) > 0)
	return out.slice(0, limit)


## Nach einem Update einmal zeigen. Wer das Spiel zum ersten Mal startet, bekommt nichts zu sehen.
## Ältere Versionen kannten den Wert noch nicht: Wer schon Spielstände hat, sieht die neue Version.
static func should_show(last_seen: String, current: String, returning_player: bool) -> bool:
	if last_seen.strip_edges().is_empty():
		return returning_player
	return compare(current, last_seen) > 0


## Text eines Eintrags in Kennzeichnung und Text zerlegen: "[CO-OP] Text" -> ["CO-OP", "Text"].
static func split_item(item: String) -> Array[String]:
	var s := item.strip_edges()
	if s.begins_with("["):
		var close := s.find("]")
		if close > 1:
			return [s.substr(1, close - 1).strip_edges(), s.substr(close + 1).strip_edges()]
	return ["", s]


func setup(entries: Array, current: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760, 0)
	_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT, 12, 1, 26, 22))
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_card.add_child(col)
	var title := Label.new()
	title.text = tr("NEU IN VERSION %s") % current
	UIStyle.style_label(title, 22, UIStyle.COL_GOLD_TEXT)
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 380)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	list.name = "Eintraege"
	scroll.add_child(list)
	if entries.is_empty():
		var none := Label.new()
		none.text = tr("Für diese Version gibt es keine Hinweise.")
		UIStyle.style_label(none, 14, UIStyle.COL_TEXT_SUB)
		list.add_child(none)
	var n := 0
	for e in entries:
		var head := Label.new()
		head.text = "%s  ·  %s" % [str(e.get("version", "")), str(e.get("title", ""))]
		UIStyle.style_label(head, 16, UIStyle.COL_TEXT_MAIN)
		list.add_child(head)
		for item in (e.get("items", []) as Array):
			var parts := split_item(str(item))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			n += 1
			row.name = "Punkt_%d" % n
			var chip := Label.new()
			chip.text = parts[0] if not parts[0].is_empty() else "•"
			chip.custom_minimum_size = Vector2(120, 0)
			UIStyle.style_label(chip, 11, UIStyle.COL_ACCENT)
			row.add_child(chip)
			var txt := Label.new()
			txt.text = parts[1]
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UIStyle.style_label(txt, 13, UIStyle.COL_TEXT_MAIN)
			row.add_child(txt)
			list.add_child(row)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		list.add_child(gap)

	var ok := Button.new()
	ok.text = tr("WEITER")
	ok.custom_minimum_size = Vector2(180, 40)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	UIStyle.style_button(ok)
	ok.pressed.connect(close)
	col.add_child(ok)
	UIStyle.animate_popup_open(self, _card)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
