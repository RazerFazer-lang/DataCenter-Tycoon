class_name AdminUI
extends Control
## Admin-Menü [F10]: nur für den Host und von ihm freigeschaltete Mitspieler.
## Sendet ausschließlich Befehle an AdminManager, geprüft wird beim Host.

signal close_requested

const TABS := [["players", "SPIELER"], ["money", "GELD & RUF"], ["world", "ZEIT & WETTER"], ["events", "EREIGNISSE"], ["items", "ITEMS"], ["log", "PROTOKOLL"]]
const WEATHER_NAMES := {"clear": "Sonnig", "cloudy": "Bewölkt", "rain": "Regen", "storm": "Gewitter", "heatwave": "Hitzewelle"}

var _tab := "players"
var _tab_row: HBoxContainer
var _body: VBoxContainer
var _search: String = ""
var _list_box: VBoxContainer
var _confirm_key: String = ""
var _login_msg: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 560)
	panel.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_DARK, UIStyle.COL_ACCENT, 8, 1, 20, 16))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = tr("ADMIN-MENÜ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(title, 20, UIStyle.COL_GOLD_TEXT)
	head.add_child(title)
	var close := _btn(tr("Schließen [F10]"), func(): close_requested.emit())
	head.add_child(close)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	v.add_child(_tab_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	AdminManager.rights_changed.connect(_on_rights_changed)
	AdminManager.log_changed.connect(_on_log_changed)
	AdminManager.login_result.connect(_on_login_result)
	NetworkManager.players_changed.connect(func(): if visible and _tab == "players": refresh())
	GameState.build_rights_changed.connect(func(): if visible and _tab == "players": refresh())


func open() -> void:
	visible = true
	_confirm_key = ""
	refresh()


func _on_rights_changed() -> void:
	if not visible:
		return
	if not AdminManager.is_local_admin():
		if not AdminManager.login_available:
			close_requested.emit()
			return
	refresh()


func _on_login_result(ok: bool, text: String) -> void:
	if ok or not visible or _login_msg == null or not is_instance_valid(_login_msg):
		return
	_login_msg.text = text


## Dedizierter Server: Anmeldung mit dem Admin-Passwort aus der server.cfg.
func _build_login() -> void:
	_body.add_child(_label(tr("Dieser Server hat keinen Host-Spieler. Melde dich mit dem Admin-Passwort aus der server.cfg an."), 14))
	var row := _row(tr("Admin-Passwort"))
	var le := LineEdit.new()
	le.secret = true
	le.max_length = 64
	le.custom_minimum_size = Vector2(320, 34)
	UIStyle.style_line_edit(le)
	row.add_child(le)
	var go := func():
		if _login_msg != null and is_instance_valid(_login_msg):
			_login_msg.text = tr("Prüfe …") if le.text != "" else ""
		AdminManager.login(le.text)
		le.text = ""
	row.add_child(_btn(tr("Anmelden"), go))
	le.text_submitted.connect(func(_t: String): go.call())
	_login_msg = _label("", 13, UIStyle.COL_AMBER)
	_body.add_child(_login_msg)
	le.grab_focus.call_deferred()


func _on_log_changed() -> void:
	if visible and _tab == "log":
		refresh()


func refresh() -> void:
	_clear(_tab_row)
	if not AdminManager.is_local_admin():
		_clear(_body)
		_build_login()
		return
	for t in TABS:
		var id := str(t[0])
		var b := _btn(tr(str(t[1])), func():
			_tab = id
			_confirm_key = ""
			refresh())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if id == _tab:
			UIStyle.style_button(b, Color(0.26, 0.20, 0.10), UIStyle.COL_ACCENT)
		_tab_row.add_child(b)
	_clear(_body)
	match _tab:
		"players":
			_build_players()
		"money":
			_build_money()
		"world":
			_build_world()
		"events":
			_build_events()
		"items":
			_build_items()
		"log":
			_build_log()


# ------------------------------------------------------------------ Reiter

func _build_players() -> void:
	var me := multiplayer.get_unique_id()
	var host := AdminManager.is_local_owner()
	for pid_v in NetworkManager.players.keys():
		var pid := int(pid_v)
		var card := _card()
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		card.add_child(row)
		var tag := tr("Host") if pid == 1 else (tr("Admin") if AdminManager.is_admin(pid) else tr("Spieler"))
		var nl := _label("%s  (%s)" % [NetworkManager.get_player_name(pid), tag], 15)
		nl.custom_minimum_size = Vector2(250, 32)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nl)
		if pid != me:
			row.add_child(_cmd_btn(tr("Hingehen"), "goto", {"peer": pid}))
			row.add_child(_cmd_btn(tr("Herholen"), "bring", {"peer": pid}))
		row.add_child(_cmd_btn(tr("Zur Garage"), "send_site", {"peer": pid, "site": "garage"}))
		if GameState.halle_nord_owned:
			row.add_child(_cmd_btn(tr("Zur Halle Nord"), "send_site", {"peer": pid, "site": "halle_nord"}))
		if pid != 1 and not GameState.build_open and not AdminManager.is_admin(pid):
			if GameState.can_build(pid):
				row.add_child(_cmd_btn(tr("Baurecht entziehen"), "build_off", {"peer": pid}))
			else:
				row.add_child(_cmd_btn(tr("Bauen erlauben"), "build_on", {"peer": pid}))
		if host and not AdminManager.is_owner(pid):
			if AdminManager.is_admin(pid):
				row.add_child(_cmd_btn(tr("Admin entziehen"), "revoke", {"peer": pid}))
			else:
				row.add_child(_confirm_btn(tr("Zum Admin machen"), "grant", {"peer": pid}))
		if not AdminManager.is_owner(pid) and pid != me and (host or not AdminManager.is_admin(pid)):
			row.add_child(_confirm_btn(tr("Kicken"), "kick", {"peer": pid}, UIStyle.COL_AMBER))
			row.add_child(_confirm_btn(tr("Bannen"), "ban", {"peer": pid}, UIStyle.COL_RED))
	if host:
		_body.add_child(_label(tr("Admin-Rechte gelten nur bis zum Ende dieser Sitzung. Alles steht im Protokoll."), 12, UIStyle.COL_TEXT_SUB))


func _build_money() -> void:
	_body.add_child(_label(tr("Guthaben: $%d   •   Ruf: %d (%s)   •   Firmenstufe: %d") % [int(GameState.money), roundi(GameState.reputation), tr(GameState.get_reputation_label()), GameState.get_company_level()], 14))
	var r1 := _row(tr("Geld"))
	for d in [1000, 10000, 100000, -10000]:
		r1.add_child(_cmd_btn("%+d $" % int(d), "money_add", {"v": int(d)}))
	var spin := _spin(0, SecurityGuard.MAX_MONEY, 100, GameState.money)
	r1.add_child(spin)
	r1.add_child(_btn(tr("Setzen"), func(): _send("money_set", {"v": spin.value})))
	var r2 := _row(tr("Ruf"))
	var rs := _spin(0, 100, 1, GameState.reputation)
	r2.add_child(rs)
	r2.add_child(_btn(tr("Setzen"), func(): _send("reputation", {"v": rs.value})))
	var r3 := _row(tr("Firmenstufe"))
	var ls := _spin(1, GameState.COMPANY_LEVEL_THRESHOLDS.size(), 1, GameState.get_company_level())
	r3.add_child(ls)
	r3.add_child(_btn(tr("Setzen"), func(): _send("level", {"v": ls.value})))


func _build_world() -> void:
	_body.add_child(_label(tr("Tag %d, %s Uhr   •   Wetter: %s   •   Uhr: %s") % [GameState.day_number, GameState.get_time_string(), GameState.get_weather_label(), "×%d" % int(GameState.clock_scale)], 14))
	var r1 := _row(tr("Uhrzeit"))
	for h in [6, 9, 12, 18, 22]:
		r1.add_child(_cmd_btn("%02d:00" % int(h), "time", {"v": int(h)}))
	r1.add_child(_confirm_btn(tr("Nächster Tag"), "next_day", {}))
	var r2 := _row(tr("Wetter"))
	for w in AdminManager.WEATHERS:
		r2.add_child(_cmd_btn(tr(str(WEATHER_NAMES[w])), "weather", {"v": w}))
	var r3 := _row(tr("Tempo der Uhr"))
	for s in AdminManager.TIME_SCALES:
		r3.add_child(_cmd_btn(tr("Anhalten") if s == 0.0 else "×%d" % int(s), "time_scale", {"v": s}))


func _build_events() -> void:
	var r1 := _row(tr("Auslösen"))
	r1.add_child(_confirm_btn(tr("Brand"), "fire", {}, UIStyle.COL_RED))
	r1.add_child(_confirm_btn(tr("Defekt"), "crash", {}, UIStyle.COL_AMBER))
	r1.add_child(_confirm_btn(tr("Netzausfall"), "outage", {}, UIStyle.COL_AMBER))
	r1.add_child(_confirm_btn(tr("DDoS-Angriff"), "ddos", {}, UIStyle.COL_AMBER))
	var r2 := _row(tr("Beheben"))
	r2.add_child(_cmd_btn(tr("Alles löschen & reparieren"), "repair_all", {}))
	r2.add_child(_cmd_btn(tr("Alles reinigen"), "clean_all", {}))
	r2.add_child(_cmd_btn(tr("Netzausfall beenden"), "outage_end", {}))


func _build_items() -> void:
	var r := _row(tr("Lieferung"))
	r.add_child(_cmd_btn(tr("Bestellte Ware sofort liefern"), "deliver_now", {}))
	var sr := _row(tr("Suche"))
	var le := LineEdit.new()
	le.placeholder_text = tr("Name …")
	le.text = _search
	le.max_length = 40
	le.custom_minimum_size = Vector2(300, 34)
	UIStyle.style_line_edit(le)
	le.text_changed.connect(func(t: String):
		_search = t
		_fill_items())
	sr.add_child(le)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_body.add_child(_list_box)
	_fill_items()


func _fill_items() -> void:
	_clear(_list_box)
	var q := _search.strip_edges().to_lower()
	var shown := 0
	for id in AdminManager.get_giveable_items():
		var name := tr(str(GameState.ITEM_CATALOG[id]["name"]))
		if q != "" and not name.to_lower().contains(q):
			continue
		_list_box.add_child(_item_row(name, "give_item", id, GameState.BULK_PACK_MAX if GameState.is_bulk_packable(id) else 1))
	if q.length() < 2:
		_list_box.add_child(_label(tr("Für einzelne Bauteile mindestens zwei Buchstaben eingeben."), 12, UIStyle.COL_TEXT_SUB))
		return
	for cat in HardwareCatalog.CATEGORY_ORDER:
		for p in HardwareCatalog.PARTS[cat]:
			var pd: Dictionary = p
			if int(pd.get("cost", 0)) <= 0 or not str(pd["name"]).to_lower().contains(q):
				continue
			shown += 1
			if shown > 30:
				return
			_list_box.add_child(_item_row(str(pd["name"]), "give_part", str(pd["id"]), 4))


func _item_row(text: String, cmd: String, id: String, bulk: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := _label(text, 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	row.add_child(_cmd_btn("+1", cmd, {"id": id, "n": 1}))
	if bulk > 1:
		row.add_child(_cmd_btn("+%d" % bulk, cmd, {"id": id, "n": bulk}))
	return row


func _build_log() -> void:
	if AdminManager.log_entries.is_empty():
		_body.add_child(_label(tr("Noch keine Admin-Befehle in dieser Sitzung."), 13, UIStyle.COL_TEXT_SUB))
	for e in AdminManager.log_entries:
		var ed: Dictionary = e
		_body.add_child(_label("%s   %s: %s" % [str(ed["time"]), str(ed["who"]), str(ed["text"])], 13, UIStyle.COL_TEXT_MAIN if bool(ed["ok"]) else UIStyle.COL_RED))


# ------------------------------------------------------------------ Bausteine

func _send(cmd: String, args: Dictionary) -> void:
	SfxManager.play("click", -8.0)
	AdminManager.send(cmd, args)
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_inside_tree() and visible and _tab != "items":
			refresh())


func _cmd_btn(text: String, cmd: String, args: Dictionary) -> Button:
	return _btn(text, func(): _send(cmd, args))


## Zweimal klicken bei Befehlen mit Folgen.
func _confirm_btn(text: String, cmd: String, args: Dictionary, col: Color = UIStyle.COL_ACCENT) -> Button:
	var key := "%s%s" % [cmd, str(args)]
	var armed := _confirm_key == key
	var b := _btn(tr("Sicher?") if armed else text, func():
		if _confirm_key == key:
			_confirm_key = ""
			_send(cmd, args)
		else:
			_confirm_key = key
			refresh())
	UIStyle.style_button(b, Color(0.30, 0.14, 0.10) if armed else Color(0.165, 0.170, 0.182, 0.97), col)
	return b


func _btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.focus_mode = Control.FOCUS_NONE
	UIStyle.style_button(b)
	b.pressed.connect(on_press)
	return b


func _row(title: String) -> HFlowContainer:
	var card := _card()
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	card.add_child(row)
	var l := _label(title, 14, UIStyle.COL_GOLD_TEXT)
	l.custom_minimum_size = Vector2(130, 32)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


func _card() -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 6, 1, 12, 8))
	_body.add_child(c)
	return c


func _label(text: String, size_px: int, col: Color = UIStyle.COL_TEXT_MAIN) -> Label:
	var l := Label.new()
	l.text = text
	UIStyle.style_label(l, size_px, col)
	return l


func _spin(lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(150, 32)
	return s


func _clear(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
