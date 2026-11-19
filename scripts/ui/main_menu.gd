class_name MainMenu
extends Control
## v1.2 Hauptmenü über dem live gerenderten 3D-Showcase der Garage.
## Links: Logo, Navigationsliste und Inhaltskarte der gewählten Seite; rechts bleibt der Blick auf die Szene frei.
## Seiten: Neues Co-op-Spiel, Spielstand laden, Co-op beitreten (mit zuletzt genutzten IPs), Einstellungen, Beenden.

const SHADE := Color(0.025, 0.028, 0.034)
const NAV_TEXT_X := 18.0
const NAV_HOVER_SHIFT := 8.0

var _nav_buttons: Dictionary = {}
var _nav_titles: Dictionary = {}
var _pages: Dictionary = {}
var _active_page: String = "new_game"

var _status_lbl: Label
var _busy: bool = false
var _display_font: FontVariation
var _player_chip_lbl: Label
var _intro_tween: Tween

# New Game page inputs
var _host_name_input: LineEdit
var _world_name_input: LineEdit
var _host_port_input: LineEdit
var _host_start_btn: Button

# Load Game page container
var _saves_list: VBoxContainer
var _load_port_input: LineEdit

# Join Game page inputs
var _join_name_input: LineEdit
var _join_ip_input: LineEdit
var _join_port_input: LineEdit
var _join_btn: Button
var _recent_ips_box: HBoxContainer

# Settings page controls
var _set_name_input: LineEdit
var _master_slider: HSlider
var _master_val: Label
var _sfx_slider: HSlider
var _sfx_val: Label
var _fan_slider: HSlider
var _fan_val: Label
var _sens_slider: HSlider
var _sens_val: Label
var _fov_slider: HSlider
var _fov_val: Label
var _gfx_option: OptionButton
var _fullscreen_check: CheckButton
var _autosave_check: CheckButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_sync_from_settings()
	_switch_page("new_game", false)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected_from_session.connect(_on_disconnected)
	visibility_changed.connect(_on_visibility_changed)
	_play_intro.call_deferred()


func refresh_on_show() -> void:
	_busy = false
	_set_action_buttons_disabled(false)
	_sync_from_settings()
	_rebuild_saves_list()
	_rebuild_recent_ips()


func show_status(text: String, color: Color = Color(0.80, 0.80, 0.78)) -> void:
	if _status_lbl != null:
		_status_lbl.text = text
		_status_lbl.modulate = color
	_busy = false
	_set_action_buttons_disabled(false)


## Übernimmt die Startwerte aus dem Launcher in die Menüfelder. Gestartet wird erst per Klick.
func apply_launcher_prefill(mode: String, player_name: String, world_name: String, join_ip: String, port: int) -> void:
	var clean_name := player_name.strip_edges()
	if not clean_name.is_empty():
		for input_v in [_host_name_input, _join_name_input]:
			if input_v != null:
				(input_v as LineEdit).text = clean_name
	for port_v in [_host_port_input, _load_port_input, _join_port_input]:
		if port_v != null:
			(port_v as LineEdit).text = str(port)
	if mode == "host" and _world_name_input != null and not world_name.strip_edges().is_empty():
		_world_name_input.text = world_name.strip_edges()
	if mode == "join" and _join_ip_input != null and not join_ip.strip_edges().is_empty():
		_join_ip_input.text = join_ip.strip_edges()
	match mode:
		"host":
			_switch_page("new_game", false)
		"load":
			_switch_page("load_game", false)
		"join":
			_switch_page("join_game", false)


func _on_visibility_changed() -> void:
	if visible:
		_play_intro()


## Sanftes Einblenden beim Öffnen des Menüs.
func _play_intro() -> void:
	if not visible:
		return
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	modulate.a = 0.0
	_intro_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(self, "modulate:a", 1.0, 0.55)


func _set_action_buttons_disabled(disabled: bool) -> void:
	if _host_start_btn != null:
		_host_start_btn.disabled = disabled
	if _join_btn != null:
		_join_btn.disabled = disabled


func _sync_from_settings() -> void:
	var pname := SettingsManager.player_name
	if _host_name_input != null:
		_host_name_input.text = pname
	if _join_name_input != null:
		_join_name_input.text = pname
	if _set_name_input != null:
		_set_name_input.text = pname
	if _player_chip_lbl != null:
		_player_chip_lbl.text = pname

	if _master_slider != null:
		_master_slider.set_value_no_signal(SettingsManager.master_volume * 100.0)
		_master_val.text = "%d%%" % int(roundf(SettingsManager.master_volume * 100.0))
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(SettingsManager.sfx_volume * 100.0)
		_sfx_val.text = "%d%%" % int(roundf(SettingsManager.sfx_volume * 100.0))
	if _fan_slider != null:
		_fan_slider.set_value_no_signal(SettingsManager.fan_volume * 100.0)
		_fan_val.text = "%d%%" % int(roundf(SettingsManager.fan_volume * 100.0))
	if _sens_slider != null:
		_sens_slider.set_value_no_signal(SettingsManager.mouse_sensitivity * 1000.0)
		_sens_val.text = "%.1f" % (SettingsManager.mouse_sensitivity * 1000.0)
	if _fov_slider != null:
		_fov_slider.set_value_no_signal(SettingsManager.fov)
		_fov_val.text = "%d°" % int(roundf(SettingsManager.fov))
	if _gfx_option != null:
		_gfx_option.selected = SettingsManager.graphics_quality
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(SettingsManager.fullscreen)
	if _autosave_check != null:
		_autosave_check.set_pressed_no_signal(SettingsManager.autosave_enabled)
	if _join_ip_input != null and not SettingsManager.recent_ips.is_empty():
		_join_ip_input.text = SettingsManager.recent_ips[0]


func _switch_page(page_id: String, animate: bool = true) -> void:
	var changed := page_id != _active_page
	_active_page = page_id
	for pid in _pages.keys():
		(_pages[pid] as Control).visible = (pid == page_id)
	for pid in _nav_buttons.keys():
		_apply_nav_style(str(pid), pid == page_id)
	if animate and changed and _pages.has(page_id):
		var page := _pages[page_id] as Control
		page.modulate.a = 0.0
		var tw := page.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(page, "modulate:a", 1.0, 0.2)
	if page_id == "load_game":
		_rebuild_saves_list()
	elif page_id == "join_game":
		_rebuild_recent_ips()
	elif page_id == "settings":
		_sync_from_settings()


func _parse_port(text: String) -> int:
	var p := int(text.strip_edges())
	return p if p > 1024 and p < 65535 else NetworkManager.DEFAULT_PORT


func _on_host_new_pressed() -> void:
	if _busy:
		return
	SfxManager.play("click")
	var port := _parse_port(_host_port_input.text)
	var world_title := _world_name_input.text.strip_edges()
	if world_title.is_empty():
		world_title = "Mein DataCenter"
	show_status("Starte neue Co-op Welt '%s' auf Port %d..." % [world_title, port])
	_busy = true
	_set_action_buttons_disabled(true)
	NetworkManager.host_game(_host_name_input.text, port, world_title)


func _on_load_save_pressed(save_id: String, display_name: String) -> void:
	if _busy:
		return
	SfxManager.play("click")
	var port := _parse_port(_load_port_input.text)
	show_status("Lade Spielstand '%s' & starte Host auf Port %d..." % [display_name, port])
	_busy = true
	_set_action_buttons_disabled(true)
	NetworkManager.host_from_save(save_id, SettingsManager.player_name, port)


func _on_delete_save_pressed(save_id: String) -> void:
	SfxManager.play("cable_cut")
	SaveManager.delete_save(save_id)
	_rebuild_saves_list()
	show_status("Spielstand gelöscht.", Color(0.95, 0.72, 0.32))


func _on_join_pressed() -> void:
	if _busy:
		return
	SfxManager.play("click")
	var port := _parse_port(_join_port_input.text)
	var ip := _join_ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	show_status("Verbinde mit %s:%d..." % [ip, port], Color(0.95, 0.85, 0.35))
	_busy = true
	_set_action_buttons_disabled(true)
	NetworkManager.join_game(ip, _join_name_input.text, port)


func _on_connection_failed(reason: String) -> void:
	SfxManager.play("error")
	show_status(reason, Color(1.0, 0.42, 0.38))


func _on_disconnected(reason: String) -> void:
	refresh_on_show()
	show_status(reason, Color(1.0, 0.72, 0.35))


func _apply_settings_change() -> void:
	var new_name := _set_name_input.text.strip_edges().left(18)
	if not new_name.is_empty():
		SettingsManager.player_name = new_name
		_host_name_input.text = new_name
		_join_name_input.text = new_name
		if _player_chip_lbl != null:
			_player_chip_lbl.text = new_name
	SettingsManager.master_volume = _master_slider.value / 100.0
	SettingsManager.sfx_volume = _sfx_slider.value / 100.0
	SettingsManager.fan_volume = _fan_slider.value / 100.0
	SettingsManager.mouse_sensitivity = _sens_slider.value / 1000.0
	SettingsManager.fov = _fov_slider.value
	if _gfx_option != null:
		SettingsManager.graphics_quality = clampi(_gfx_option.selected, 0, 3)
	SettingsManager.fullscreen = _fullscreen_check.button_pressed
	SettingsManager.autosave_enabled = _autosave_check.button_pressed

	_master_val.text = "%d%%" % int(roundf(_master_slider.value))
	_sfx_val.text = "%d%%" % int(roundf(_sfx_slider.value))
	_fan_val.text = "%d%%" % int(roundf(_fan_slider.value))
	_sens_val.text = "%.1f" % _sens_slider.value
	_fov_val.text = "%d°" % int(roundf(_fov_slider.value))

	SettingsManager.save_settings()


func _rebuild_saves_list() -> void:
	if _saves_list == null:
		return
	for c in _saves_list.get_children():
		c.queue_free()

	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Noch keine Spielstände vorhanden.\nStarte ein neues Spiel und speichere im Pause-Menü [ESC] oder am Windows-PC!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(empty_lbl, 13, UIStyle.COL_TEXT_SUB)
		_saves_list.add_child(empty_lbl)
		return

	for item in saves:
		var entry: Dictionary = item
		var sid := str(entry["save_id"])
		var dname := str(entry["display_name"])
		var saved_at := str(entry.get("saved_at", ""))
		var summary: Dictionary = entry.get("summary", {})
		var money_i := int(summary.get("money", 0))
		var rack_c := int(summary.get("rack_count", 0))
		var ram_gb := int(summary.get("total_ram_gb", 0))
		var day_n := int(summary.get("day_number", 1))
		var rlvl := int(summary.get("room_level", 1 if bool(summary.get("room_expanded", false)) else 0))
		var exp_txt := " • Halle B" if rlvl == 1 else (" • Halle C Enterprise" if rlvl >= 2 else "")

		var card := _make_card_panel(Color(0.10, 0.105, 0.115, 0.92), UIStyle.COL_BORDER, 14, 10)
		_saves_list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)

		var title := Label.new()
		title.text = dname
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIStyle.style_label(title, 16, UIStyle.COL_GOLD_TEXT, _display_font)
		info.add_child(title)

		var meta := Label.new()
		meta.text = "Tag %d  •  $%d  •  %d Racks  •  %d GB RAM%s\nGespeichert: %s" % [
			day_n, money_i, rack_c, ram_gb, exp_txt, saved_at
		]
		UIStyle.style_label(meta, 12, UIStyle.COL_TEXT_SUB)
		info.add_child(meta)

		var load_btn := Button.new()
		load_btn.text = "LADEN"
		load_btn.custom_minimum_size = Vector2(110, 38)
		load_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIStyle.style_button(load_btn, Color(0.70, 0.46, 0.12), Color(0.96, 0.72, 0.24))
		load_btn.add_theme_font_override("font", _display_font)
		var cap_id := sid
		var cap_name := dname
		load_btn.pressed.connect(func(): _on_load_save_pressed(cap_id, cap_name))
		row.add_child(load_btn)

		var del_btn := Button.new()
		del_btn.text = "Löschen"
		del_btn.tooltip_text = "Spielstand löschen"
		del_btn.custom_minimum_size = Vector2(84, 38)
		del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIStyle.style_button(del_btn, Color(0.20, 0.11, 0.11, 0.95), Color(0.68, 0.26, 0.24))
		del_btn.pressed.connect(func(): _on_delete_save_pressed(cap_id))
		row.add_child(del_btn)


func _rebuild_recent_ips() -> void:
	if _recent_ips_box == null:
		return
	for c in _recent_ips_box.get_children():
		c.queue_free()

	if SettingsManager.recent_ips.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "Noch keine Verbindungen gespeichert."
		UIStyle.style_label(none_lbl, 12, UIStyle.COL_TEXT_SUB)
		_recent_ips_box.add_child(none_lbl)
		return

	for ip_str in SettingsManager.recent_ips:
		var btn := Button.new()
		btn.text = ip_str
		btn.custom_minimum_size = Vector2(0, 30)
		UIStyle.style_button(btn, Color(0.13, 0.135, 0.145, 0.95), UIStyle.COL_BLUE)
		var cap_ip := ip_str
		btn.pressed.connect(func():
			SfxManager.play("click", -10.0)
			_join_ip_input.text = cap_ip
		)
		_recent_ips_box.add_child(btn)


func _build_ui() -> void:
	_display_font = UIStyle.make_display_font(get_theme_default_font(), 0.55, 2)

	# Weicher Verlauf links hinter Navigation und Inhalt; rechts bleibt die 3D-Szene frei
	add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(SHADE, 0.93), Color(SHADE, 0.74), Color(SHADE, 0.0)]),
		PackedFloat32Array([0.0, 0.42, 0.72]),
		Vector2(0.0, 0.5), Vector2(1.0, 0.5)
	))
	# Oben leicht für den Titel, unten kräftiger für die Fußleiste
	add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(SHADE, 0.55), Color(SHADE, 0.0), Color(SHADE, 0.0), Color(SHADE, 0.85)]),
		PackedFloat32Array([0.0, 0.22, 0.78, 1.0]),
		Vector2(0.5, 0.0), Vector2(0.5, 1.0)
	))

	var top_accent := ColorRect.new()
	top_accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_accent.offset_bottom = 2
	top_accent.color = Color(UIStyle.COL_ACCENT, 0.92)
	top_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_accent)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 26)
	margin.add_child(main_v)

	main_v.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	main_v.add_child(body)

	body.add_child(_build_nav_column())

	var content_card := _make_card_panel(Color(0.07, 0.074, 0.082, 0.90), UIStyle.COL_BORDER, 22, 18)
	content_card.custom_minimum_size = Vector2(520, 0)
	body.add_child(content_card)

	var content_wrap := VBoxContainer.new()
	content_wrap.add_theme_constant_override("separation", 12)
	content_card.add_child(content_wrap)

	var stack := MarginContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_wrap.add_child(stack)

	_pages["new_game"] = _build_new_game_page()
	_pages["load_game"] = _build_load_game_page()
	_pages["join_game"] = _build_join_game_page()
	_pages["settings"] = _build_settings_page()
	for p in _pages.values():
		stack.add_child(p as Control)

	content_wrap.add_child(_make_rule())

	_status_lbl = Label.new()
	_status_lbl.text = "Bereit — starte dein eigenes Rechenzentrum allein oder im Co-op!"
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.modulate = UIStyle.COL_TEXT_SUB
	content_wrap.add_child(_status_lbl)

	# Rechts frei für den Blick auf das live gerenderte Rechenzentrum
	var open_view_spacer := Control.new()
	open_view_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_view_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(open_view_spacer)

	main_v.add_child(_build_footer())
	add_child(_build_player_chip())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(64, 64)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.draw.connect(func() -> void: UIStyle.draw_logo_mark(logo, Rect2(Vector2.ZERO, logo.size)))
	header.add_child(logo)

	var title_v := VBoxContainer.new()
	title_v.add_theme_constant_override("separation", 2)
	title_v.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(title_v)

	var title := Label.new()
	title.text = "DATACENTER TYCOON"
	UIStyle.style_label(title, 50, Color(0.96, 0.965, 0.97), _display_font, true)
	title_v.add_child(title)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 12)
	title_v.add_child(tag_row)

	var tagline := Label.new()
	tagline.text = "VOM GARAGENSTART ZUM ENTERPRISE-RECHENZENTRUM"
	tagline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(tagline, 13, UIStyle.COL_GOLD_TEXT, _display_font)
	tag_row.add_child(tagline)

	var badge := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(UIStyle.COL_ACCENT, 0.16)
	bsb.border_color = Color(UIStyle.COL_ACCENT, 0.75)
	bsb.set_border_width_all(1)
	bsb.set_corner_radius_all(UIStyle.BUTTON_RADIUS)
	bsb.content_margin_left = 8
	bsb.content_margin_right = 8
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", bsb)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_row.add_child(badge)

	var blbl := Label.new()
	blbl.text = "1–4 SPIELER CO-OP"
	UIStyle.style_label(blbl, 11, UIStyle.COL_GOLD_TEXT)
	badge.add_child(blbl)

	var desc := Label.new()
	desc.text = "66 Hardware-Teile von DDR2 bis DDR5, Vermietung an Kunden und Live-Support"
	UIStyle.style_label(desc, 12, UIStyle.COL_TEXT_SUB)
	title_v.add_child(desc)
	return header


func _build_nav_column() -> Control:
	var nav_v := VBoxContainer.new()
	nav_v.custom_minimum_size = Vector2(300, 0)
	nav_v.add_theme_constant_override("separation", 4)

	var section := Label.new()
	section.text = "HAUPTMENÜ"
	UIStyle.style_label(section, 11, UIStyle.COL_TEXT_SUB, _display_font)
	nav_v.add_child(section)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	nav_v.add_child(gap)

	_add_nav_button(nav_v, "new_game", "NEUES SPIEL", "Eigenes Rechenzentrum hosten")
	_add_nav_button(nav_v, "load_game", "SPIELSTAND LADEN", "Gespeicherte Welt fortsetzen")
	_add_nav_button(nav_v, "join_game", "CO-OP BEITRETEN", "Per IP mit Freunden spielen")
	_add_nav_button(nav_v, "settings", "EINSTELLUNGEN", "Grafik, Audio und Steuerung")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_v.add_child(spacer)

	nav_v.add_child(_make_rule())

	var quit_item := _make_nav_item(nav_v, "BEENDEN", "Zurück zum Desktop")
	var quit_btn := quit_item[0] as Button
	_nav_styles(quit_btn, UIStyle.COL_RED, false)
	quit_btn.pressed.connect(func(): get_tree().quit())
	return nav_v


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	_key_hint(footer, "E", "Interagieren")
	_key_hint(footer, "F", "Rack-Menü")
	_key_hint(footer, "Rechtsklick", "Trennen")
	_key_hint(footer, "R", "Drehen")
	_key_hint(footer, "Q", "Ablegen")
	_key_hint(footer, "H", "Hilfe")
	_key_hint(footer, "ESC", "Pause")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)

	var ver_lbl := Label.new()
	ver_lbl.text = "v%s  •  LIVE-3D-SHOWCASE" % UIStyle.game_version()
	ver_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(ver_lbl, 11, Color(UIStyle.COL_TEXT_MAIN, 0.6))
	footer.add_child(ver_lbl)
	return footer


func _build_player_chip() -> Control:
	var chip := PanelContainer.new()
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.offset_right = -48
	chip.offset_left = -48
	chip.offset_top = 46
	chip.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.07, 0.074, 0.082, 0.85), Color(0.26, 0.27, 0.29, 0.9), 4, 1, 14, 8))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = UIStyle.COL_GREEN
	row.add_child(dot)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	row.add_child(v)

	var cap := Label.new()
	cap.text = "SPIELER"
	UIStyle.style_label(cap, 10, UIStyle.COL_TEXT_SUB, _display_font)
	v.add_child(cap)

	_player_chip_lbl = Label.new()
	_player_chip_lbl.text = SettingsManager.player_name
	UIStyle.style_label(_player_chip_lbl, 15, UIStyle.COL_TEXT_MAIN, _display_font)
	v.add_child(_player_chip_lbl)
	return chip


func _add_nav_button(parent: VBoxContainer, page_id: String, title_txt: String, hint_txt: String) -> void:
	var item := _make_nav_item(parent, title_txt, hint_txt)
	var btn := item[0] as Button
	btn.pressed.connect(func():
		SfxManager.play("click", -10.0)
		_switch_page(page_id)
	)
	_nav_buttons[page_id] = btn
	_nav_titles[page_id] = item[1] as Label


## Navigationseintrag: Titel und Hinweiszeile; beim Überfahren rückt der Text leicht nach rechts.
func _make_nav_item(parent: VBoxContainer, title_txt: String, hint_txt: String) -> Array:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 58)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(btn)

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = NAV_TEXT_X
	inner.offset_right = -10
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var title := Label.new()
	title.text = title_txt
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(title, 19, UIStyle.COL_TEXT_MAIN, _display_font)
	inner.add_child(title)

	var hint := Label.new()
	hint.text = hint_txt
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(hint, 12, UIStyle.COL_TEXT_SUB)
	inner.add_child(hint)

	btn.mouse_entered.connect(func(): _slide_nav(inner, NAV_TEXT_X + NAV_HOVER_SHIFT))
	btn.mouse_exited.connect(func(): _slide_nav(inner, NAV_TEXT_X))
	_nav_styles(btn, UIStyle.COL_ACCENT, false)
	return [btn, title]


func _slide_nav(inner: Control, x: float) -> void:
	if inner.has_meta("slide_tw"):
		var old := inner.get_meta("slide_tw") as Tween
		if old != null and old.is_valid():
			old.kill()
	var tw := inner.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(inner, "position:x", x, 0.14)
	inner.set_meta("slide_tw", tw)


func _apply_nav_style(page_id: String, active: bool) -> void:
	if not _nav_buttons.has(page_id):
		return
	_nav_styles(_nav_buttons[page_id] as Button, UIStyle.COL_ACCENT, active)
	var title := _nav_titles.get(page_id) as Label
	if title != null:
		title.add_theme_color_override("font_color", UIStyle.COL_GOLD_TEXT if active else UIStyle.COL_TEXT_MAIN)


## Navigationseinträge haben keinen Kasten: nur eine Akzentleiste links und ein leichter Hintergrund.
func _nav_styles(btn: Button, accent: Color, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent, 0.13) if active else Color(0.0, 0.0, 0.0, 0.0)
	normal.border_color = accent
	normal.border_width_left = 4 if active else 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.18) if active else Color(1.0, 1.0, 1.0, 0.05)
	hover.border_color = accent if active else Color(accent, 0.7)
	hover.border_width_left = 4 if active else 2

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.24)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(accent, 0.6)
	focus.set_border_width_all(1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)


func _key_hint(parent: HBoxContainer, key: String, txt: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)

	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.165, 0.18, 0.95)
	sb.border_color = Color(0.36, 0.37, 0.40)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(cap)

	var key_lbl := Label.new()
	key_lbl.text = key
	UIStyle.style_label(key_lbl, 11, UIStyle.COL_TEXT_MAIN, _display_font)
	cap.add_child(key_lbl)

	var t := Label.new()
	t.text = txt
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(t, 12, UIStyle.COL_TEXT_SUB)
	box.add_child(t)


func _build_new_game_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	v.add_child(_page_heading("NEUES RECHENZENTRUM HOSTEN", "Starte allein oder mit bis zu 4 Freunden im Co-op."))

	v.add_child(_field_label("Name der Welt / des Spielstands"))
	_world_name_input = LineEdit.new()
	_world_name_input.text = "Garage Cloud GmbH"
	_world_name_input.placeholder_text = "z. B. Freitag Co-op Serverraum"
	_world_name_input.max_length = 32
	_style_line_edit(_world_name_input)
	v.add_child(_world_name_input)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	var name_v := VBoxContainer.new()
	name_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_v.add_theme_constant_override("separation", 6)
	row.add_child(name_v)
	name_v.add_child(_field_label("Dein Spielername"))
	_host_name_input = LineEdit.new()
	_host_name_input.text = SettingsManager.player_name
	_host_name_input.max_length = 18
	_style_line_edit(_host_name_input)
	name_v.add_child(_host_name_input)

	var port_v := VBoxContainer.new()
	port_v.add_theme_constant_override("separation", 6)
	row.add_child(port_v)
	port_v.add_child(_field_label("Port (UDP)"))
	_host_port_input = LineEdit.new()
	_host_port_input.text = str(NetworkManager.DEFAULT_PORT)
	_host_port_input.custom_minimum_size = Vector2(120, 0)
	_style_line_edit(_host_port_input)
	port_v.add_child(_host_port_input)

	var note := Label.new()
	note.text = "Freunde können jederzeit über deine LAN-, Radmin-VPN- oder Tailscale-IP beitreten (auch später per Late-Join). Dein Fortschritt wird alle 3 Minuten automatisch gespeichert."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(note, 12, UIStyle.COL_TEXT_SUB)
	v.add_child(note)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	v.add_child(spacer)

	_host_start_btn = Button.new()
	_host_start_btn.text = "RECHENZENTRUM STARTEN"
	_host_start_btn.custom_minimum_size = Vector2(0, 50)
	UIStyle.style_button(_host_start_btn, Color(0.74, 0.49, 0.12), Color(0.96, 0.72, 0.24))
	_host_start_btn.add_theme_font_override("font", _display_font)
	_host_start_btn.add_theme_font_size_override("font_size", 16)
	_host_start_btn.pressed.connect(_on_host_new_pressed)
	v.add_child(_host_start_btn)
	return v


func _build_load_game_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	v.add_child(_page_heading("SPIELSTAND LADEN & HOSTEN", "Wähle eine gespeicherte Welt aus user://saves/"))

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 10)
	v.add_child(port_row)
	var plbl := _field_label("Host-Port")
	plbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	port_row.add_child(plbl)
	_load_port_input = LineEdit.new()
	_load_port_input.text = str(NetworkManager.DEFAULT_PORT)
	_load_port_input.custom_minimum_size = Vector2(100, 0)
	_style_line_edit(_load_port_input)
	port_row.add_child(_load_port_input)
	var row_spacer := Control.new()
	row_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(row_spacer)
	var ref_btn := Button.new()
	ref_btn.text = "Aktualisieren"
	ref_btn.custom_minimum_size = Vector2(0, 34)
	UIStyle.style_button(ref_btn)
	ref_btn.pressed.connect(_rebuild_saves_list)
	port_row.add_child(ref_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_saves_list = VBoxContainer.new()
	_saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saves_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_saves_list)
	return v


func _build_join_game_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	v.add_child(_page_heading("CO-OP SITZUNG BEITRETEN", "Trage die IP-Adresse deines Hosts ein (LAN / Radmin VPN / Tailscale)."))

	v.add_child(_field_label("Dein Spielername"))
	_join_name_input = LineEdit.new()
	_join_name_input.text = SettingsManager.player_name
	_join_name_input.max_length = 18
	_style_line_edit(_join_name_input)
	v.add_child(_join_name_input)

	v.add_child(_field_label("Host-IP & Port"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	_join_ip_input = LineEdit.new()
	_join_ip_input.text = "127.0.0.1"
	_join_ip_input.placeholder_text = "z. B. 127.0.0.1 oder 26.x.x.x"
	_join_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(_join_ip_input)
	row.add_child(_join_ip_input)

	_join_port_input = LineEdit.new()
	_join_port_input.text = str(NetworkManager.DEFAULT_PORT)
	_join_port_input.custom_minimum_size = Vector2(100, 0)
	_style_line_edit(_join_port_input)
	row.add_child(_join_port_input)

	v.add_child(_field_label("Zuletzt genutzt (Klicken zum Einfügen)"))
	_recent_ips_box = HBoxContainer.new()
	_recent_ips_box.add_theme_constant_override("separation", 6)
	v.add_child(_recent_ips_box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	v.add_child(spacer)

	_join_btn = Button.new()
	_join_btn.text = "MIT HOST VERBINDEN"
	_join_btn.custom_minimum_size = Vector2(0, 50)
	UIStyle.style_button(_join_btn, Color(0.16, 0.24, 0.32, 0.97), UIStyle.COL_BLUE)
	_join_btn.add_theme_font_override("font", _display_font)
	_join_btn.add_theme_font_size_override("font_size", 16)
	_join_btn.pressed.connect(_on_join_pressed)
	v.add_child(_join_btn)
	return v


func _build_settings_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)

	v.add_child(_page_heading("EINSTELLUNGEN", "Änderungen werden sofort gespeichert."))

	v.add_child(_section_label("SPIELER"))
	v.add_child(_field_label("Standard-Spielername"))
	_set_name_input = LineEdit.new()
	_set_name_input.max_length = 18
	_style_line_edit(_set_name_input)
	_set_name_input.text_changed.connect(func(_t: String): _apply_settings_change())
	v.add_child(_set_name_input)

	v.add_child(_section_label("AUDIO"))
	var m_pair := _add_slider_row(v, "Gesamt-Lautstärke", 0.0, 100.0, 1.0)
	_master_slider = m_pair[0]
	_master_val = m_pair[1]

	var s_pair := _add_slider_row(v, "Effekte & UI (SFX)", 0.0, 100.0, 1.0)
	_sfx_slider = s_pair[0]
	_sfx_val = s_pair[1]

	var f_pair := _add_slider_row(v, "Server- & Klima-Lüfter", 0.0, 100.0, 1.0)
	_fan_slider = f_pair[0]
	_fan_val = f_pair[1]

	var test_sfx_btn := Button.new()
	test_sfx_btn.text = "Test-Ton abspielen"
	test_sfx_btn.custom_minimum_size = Vector2(180, 32)
	test_sfx_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UIStyle.style_button(test_sfx_btn)
	test_sfx_btn.pressed.connect(func(): SfxManager.play("cash"))
	v.add_child(test_sfx_btn)

	v.add_child(_section_label("STEUERUNG"))
	var ms_pair := _add_slider_row(v, "Maus-Empfindlichkeit", 0.8, 6.0, 0.1)
	_sens_slider = ms_pair[0]
	_sens_val = ms_pair[1]

	var fov_pair := _add_slider_row(v, "Sichtfeld (FOV)", 60.0, 105.0, 1.0)
	_fov_slider = fov_pair[0]
	_fov_val = fov_pair[1]

	v.add_child(_section_label("GRAFIK & SYSTEM"))
	var gfx_row := HBoxContainer.new()
	gfx_row.add_theme_constant_override("separation", 10)
	v.add_child(gfx_row)
	var glbl := _field_label("Grafikqualität")
	glbl.custom_minimum_size = Vector2(185, 0)
	glbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gfx_row.add_child(glbl)
	_gfx_option = OptionButton.new()
	_gfx_option.add_item("Performance (Schnell)", 0)
	_gfx_option.add_item("Mittel (SSAO + Schatten)", 1)
	_gfx_option.add_item("Hoch (SSR + ReflectionProbes + Spot-Schatten)", 2)
	_gfx_option.add_item("Ultra (SDFGI + Vol. Fog + Full Reflections)", 3)
	_gfx_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gfx_option.custom_minimum_size = Vector2(0, 34)
	UIStyle.style_button(_gfx_option)
	_gfx_option.item_selected.connect(func(_i: int): _apply_settings_change())
	gfx_row.add_child(_gfx_option)

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Vollbildmodus"
	_style_check(_fullscreen_check)
	_fullscreen_check.toggled.connect(func(_on: bool): _apply_settings_change())
	v.add_child(_fullscreen_check)

	_autosave_check = CheckButton.new()
	_autosave_check.text = "Auto-Save alle 3 Minuten (Host)"
	_style_check(_autosave_check)
	_autosave_check.toggled.connect(func(_on: bool): _apply_settings_change())
	v.add_child(_autosave_check)
	return scroll


func _add_slider_row(parent: VBoxContainer, label_txt: String, min_v: float, max_v: float, step_v: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := _field_label(label_txt)
	lbl.custom_minimum_size = Vector2(185, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	slider.value_changed.connect(func(_val: float): _apply_settings_change())
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(54, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_label(val_lbl, 13, UIStyle.COL_GOLD_TEXT)
	row.add_child(val_lbl)
	return [slider, val_lbl]


func _page_heading(title_txt: String, sub_txt: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 5)
	var t := Label.new()
	t.text = title_txt
	UIStyle.style_label(t, 21, UIStyle.COL_TEXT_MAIN, _display_font)
	b.add_child(t)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(48, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.color = UIStyle.COL_ACCENT
	b.add_child(line)
	var s := Label.new()
	s.text = sub_txt
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(s, 12, UIStyle.COL_TEXT_SUB)
	b.add_child(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	b.add_child(gap)
	return b


func _section_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	UIStyle.style_label(l, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	return l


func _field_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	UIStyle.style_label(l, 13, Color(0.80, 0.81, 0.81))
	return l


func _make_rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = Color(UIStyle.COL_BORDER, 0.7)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _make_card_panel(bg: Color, border: Color, pad_x: int = 18, pad_y: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.make_panel(bg, border, UIStyle.MAX_RADIUS, 1, pad_x, pad_y))
	return p


func _style_line_edit(le: LineEdit) -> void:
	UIStyle.style_line_edit(le)


func _style_slider(s: HSlider) -> void:
	UIStyle.style_slider(s)


func _style_check(cb: CheckButton) -> void:
	cb.add_theme_color_override("font_color", Color(0.80, 0.81, 0.81))
	cb.add_theme_color_override("font_hover_color", Color.WHITE)
	cb.add_theme_color_override("font_pressed_color", UIStyle.COL_TEXT_MAIN)
	cb.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	cb.add_theme_font_size_override("font_size", 13)