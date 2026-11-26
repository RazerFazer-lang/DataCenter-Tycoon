class_name GameHUD
extends Control
## v1.2 Spiel-HUD im Stil des Hauptmenüs (Anthrazit, gedämpftes Amber, kleine Radien).
## Oben links: Kontostand, Stromlast und Raumtemperatur als Kacheln mit Symbol und Balken.
## Oben rechts: Tag und Uhrzeit, darunter Co-op-Crew und die Steuerungshilfe [H].
## Darunter: Aufgaben-Tracker "Erste Schritte", Warnbanner, Meldungen, Lieferungsanzeige,
## Fadenkreuz mit Interaktions-Hinweis (Tastenkappe) und das Pause-Menü.
## Symbole werden gezeichnet, damit keine Emoji-Schrift nötig ist.

signal resume_requested
signal leave_requested
signal admin_requested
signal avatar_requested

const HUD_BG := Color(0.055, 0.058, 0.066, 0.86)
const HUD_BORDER := Color(0.24, 0.25, 0.27, 0.85)
const EDGE := 20
const TOAST_TOP := 146.0
const TOAST_TIME := 3.8
const TOAST_FADE := 0.35

var _world: WorldController = null
var _display_font: FontVariation
var _key_regex: RegEx

# Statusanzeigen
var _money_lbl: Label
var _power_lbl: Label
var _power_bar: ProgressBar
var _power_icon: Control
var _temp_lbl: Label
var _temp_bar: ProgressBar
var _temp_icon: Control
var _rep_lbl: Label
var _rep_bar: ProgressBar
var _clock_lbl: Label
var _day_lbl: Label
var _clock_icon: Control
var _is_night: bool = false

# Hand-Inventar: Slot-Leiste unten in der Mitte (Slots 1-4)
var _slot_bar: HBoxContainer
var _slot_styles: Array[StyleBoxFlat] = []
var _slot_item_lbls: Array[Label] = []
var _slot_sig: String = ""

# Bedingte Panels (nur sichtbar, wenn etwas anliegt)
var _alert_panel: PanelContainer
var _alert_lbl: Label
var _alert_strip: ColorRect
var _alert_icon: Control
var _van_panel: PanelContainer
var _van_lbl: Label
var _van_bar: ProgressBar
var _toast_panel: PanelContainer
var _toast_title: Label
var _toast_lbl: Label
var _toast_strip: ColorRect
var _toast_icon: Control
var _toast_tween: Tween
var _checklist_panel: PanelContainer
var _checklist_box: VBoxContainer
var _checklist_count_lbl: Label
var _crew_panel: PanelContainer
var _crew_box: VBoxContainer
## Pausemenü: Mitspielerliste mit Ping und Kick-Knopf (nur Host).
var _pause_players_box: VBoxContainer
var _pause_admin_btn: Button
## peer_id -> Ping-Label in der Pausemenü-Liste
var _pause_ping_labels: Dictionary = {}
var _help_panel: PanelContainer

# Fadenkreuz & Interaktions-Hinweis
var _crosshair: Control
var _crosshair_active: bool = false
var _prompt_panel: PanelContainer
var _prompt_key_cap: PanelContainer
var _prompt_key_lbl: Label
## Tastenkappe "Steuerung" unten rechts (folgt der Belegung von toggle_help).
var _help_key_lbl: Label
## true, sobald die Checkliste in dieser Sitzung unvollständig angezeigt wurde (für die Abschlussmeldung).
var _checklist_seen_open: bool = false
var _prompt_lbl: Label
var _sub_prompt_lbl: Label

# Pause-Menü
var _pause_overlay: ColorRect
var _pause_card: PanelContainer
var _pause_world_lbl: Label
var _pause_runs_lbl: Label
var _save_section: VBoxContainer
var _save_name_input: LineEdit
var _pause_master_slider: HSlider
var _pause_fan_slider: HSlider
var _pause_sens_slider: HSlider
var _pause_gfx_option: OptionButton
var _pause_gfx_toggle: Button
var _pause_gfx_details: VBoxContainer
var _pause_aa_option: OptionButton
var _pause_scale_slider: HSlider
var _pause_upscaler_option: OptionButton
var _pause_sharp_slider: HSlider
var _pause_aniso_option: OptionButton
var _pause_fps_option: OptionButton
var _pause_vsync_check: CheckButton
var _pause_shadow_check: CheckButton
var _pause_sfx_slider: HSlider
var _pause_fov_slider: HSlider
var _pause_window_mode_option: OptionButton
var _pause_screen_option: OptionButton
var _pause_window_size_option: OptionButton
var _pause_ui_scale_option: OptionButton
var _pause_language_option: OptionButton
var _pause_autosave_check: CheckButton
var _pause_window_size_values: Array[Vector2i] = []
## true = die Auflösungsliste gehört zu einem Vollbildmodus und schreibt fullscreen_resolution.
var _pause_window_size_list_fullscreen := false
var _pause_keybind_buttons: Dictionary = {}
## Aktion, für die gerade eine neue Taste abgefragt wird ("" = keine Abfrage aktiv).
var _pause_rebind_action := ""
var _pause_keybind_hint: Label

var _display_money: float = 1800.0
var _toast_timer: float = 0.0
var _blink_t: float = 0.0
var _prompt_alpha: float = 0.0


func bind_world(world_ref: WorldController) -> void:
	_world = world_ref


var _buff_row: HBoxContainer
var _buff_cells: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_regex = RegEx.new()
	_key_regex.compile("^\\s*\\[([^\\]]{1,12})\\]\\s*(.*)$")
	_build_ui()

	GameState.state_updated.connect(_refresh_all)
	GameState.cable_hint.connect(func(m: String): show_toast(m, true))
	GameState.racks_changed.connect(_refresh_checklist)
	GameState.cables_changed.connect(_refresh_checklist)
	GameState.crates_changed.connect(_refresh_checklist)
	GameState.inventory_changed.connect(_refresh_checklist)
	GameState.checklist_changed.connect(_refresh_checklist)
	GameState.world_snapshot_loaded.connect(func():
		_display_money = GameState.money
		_refresh_all()
	)
	GameState.event_logged.connect(_on_event_logged)
	GameState.world_saved.connect(_on_world_saved)
	GameState.daily_bill_charged.connect(_on_daily_bill_charged)
	GameState.van_updated.connect(_refresh_van_badge)
	NetworkManager.players_changed.connect(_refresh_crew)
	NetworkManager.pings_updated.connect(_refresh_crew)
	GameState.build_rights_changed.connect(func():
		_update_net_warn()
		if _pause_overlay != null and _pause_overlay.visible:
			_refresh_pause_players())
	NetworkManager.pings_updated.connect(_update_pause_pings)
	NetworkManager.players_changed.connect(func() -> void:
		if _pause_overlay != null and _pause_overlay.visible:
			_refresh_pause_players()
	)
	NetworkManager.ban_list_changed.connect(func() -> void:
		if _pause_overlay != null and _pause_overlay.visible:
			_refresh_pause_players()
	)
	GameState.host_permissions_changed.connect(func() -> void:
		if _pause_overlay != null and _pause_overlay.visible:
			_refresh_pause_players()
	)


func set_pause_visible(show_pause: bool) -> void:
	if _pause_overlay == null:
		return
	if show_pause:
		_pause_world_lbl.text = tr("%s  •  Tag %d, %s Uhr") % [GameState.current_save_name, GameState.day_number, GameState.get_time_string()]
		var is_host := NetworkManager.is_in_session and multiplayer.is_server()
		if is_host and not NetworkManager.public_ip.is_empty():
			_pause_world_lbl.text += "  •  " + tr("IP für Freunde: %s (Port %d)") % [NetworkManager.public_ip, NetworkManager.hosted_port]
		var coop := NetworkManager.players.size() > 1 or not multiplayer.is_server()
		_pause_runs_lbl.text = tr("Co-op: Die Welt läuft für alle weiter, auch während dieses Menü offen ist.") if coop \
			else tr("Die Spielzeit läuft weiter, auch während dieses Menü offen ist.")
		var succ := SessionKeeper.successor()
		if is_host and succ > 0:
			_pause_runs_lbl.text += "\n" + tr("Gehst du, übernimmt %s die Welt.") % NetworkManager.get_player_name(succ)
		_save_section.visible = is_host
		_pause_admin_btn.visible = AdminManager.is_local_admin() or AdminManager.login_available
		_refresh_pause_players()
		_save_name_input.text = GameState.current_save_name
		_pause_master_slider.set_value_no_signal(SettingsManager.master_volume * 100.0)
		_pause_fan_slider.set_value_no_signal(SettingsManager.fan_volume * 100.0)
		_pause_sens_slider.set_value_no_signal(SettingsManager.mouse_sensitivity * 1000.0)
		_update_slider_label(_pause_master_slider)
		_update_slider_label(_pause_fan_slider)
		_update_slider_label(_pause_sens_slider)
		_sync_pause_general()
		_pause_gfx_option.selected = SettingsManager.graphics_quality
		_sync_pause_graphics()
		UIStyle.animate_popup_open(_pause_overlay, _pause_card)
	else:
		UIStyle.animate_popup_close(_pause_overlay, _pause_card)


func show_toast(msg: String, is_warn: bool = false) -> void:
	if _toast_panel == null:
		return
	var col := UIStyle.COL_AMBER if is_warn else UIStyle.COL_GREEN
	_toast_title.text = tr("WARNUNG") if is_warn else tr("MELDUNG")
	_toast_title.add_theme_color_override("font_color", col)
	_toast_lbl.text = msg
	_toast_strip.color = col
	_set_icon(_toast_icon, "warn" if is_warn else "info", col)
	_toast_panel.visible = true
	# Controls schrumpfen nicht von selbst: ohne Reset bleibt der Rahmen so hoch wie die bisher längste Meldung.
	_toast_panel.reset_size()
	_toast_panel.reset_size.call_deferred()
	_toast_panel.modulate.a = 0.0
	_toast_panel.position.y = TOAST_TOP - 12.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_property(_toast_panel, "position:y", TOAST_TOP, 0.28)
	_toast_timer = TOAST_TIME


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_help") and _help_panel != null:
		_help_panel.visible = not _help_panel.visible
		SfxManager.play("click", -12.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_blink_t += delta
	_net_warn_accum += delta
	if _net_warn_accum >= 1.0:
		_net_warn_accum = 0.0
		if _crew_panel != null and _crew_panel.visible:
			_update_net_warn()

	_display_money = lerpf(_display_money, GameState.money, clampf(delta * 9.0, 0.0, 1.0))
	if absf(_display_money - GameState.money) < 0.6:
		_display_money = GameState.money
	if _money_lbl != null:
		_money_lbl.text = _format_money(_display_money)
		_money_lbl.add_theme_color_override("font_color", UIStyle.COL_RED if _display_money < 0.0 else UIStyle.COL_GOLD_TEXT)
	if _clock_lbl != null:
		var night := GameState.time_of_day < 0.24 or GameState.time_of_day > 0.76
		if night != _is_night:
			_is_night = night
			_set_icon(_clock_icon, "moon" if night else "sun", Color(0.70, 0.76, 0.92) if night else UIStyle.COL_GOLD_TEXT)
		_clock_lbl.text = GameState.get_time_string()
		var af_b := int(roundf(GameState.airflow_bonus * 100.0))
		var cm_b := int(roundf(GameState.cable_mgmt_bonus * 100.0))
		var bonus_str := ""
		if af_b > 0: bonus_str += "  •  Airflow +%d%%" % af_b
		if cm_b > 0: bonus_str += "  •  Kabel +%d%%" % cm_b
		var site_str := ("  •  [T] Halle Nord" if GameState.halle_nord_owned else "")
		_day_lbl.text = (tr("TAG %d") % GameState.day_number) + ("  •  Lv.%d" % GameState.get_company_level()) + "  •  " + OutdoorManager.season_label() + "  •  " + GameState.get_weather_label() + bonus_str + site_str

	_refresh_player_hud(delta)
	_refresh_slot_bar()
	_refresh_buff_row()
	_refresh_alert_banner()
	_refresh_van_badge()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= TOAST_FADE and _toast_panel != null:
			_toast_panel.modulate.a = maxf(0.0, _toast_timer / TOAST_FADE)
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false


func _format_money(v: float) -> String:
	var n := int(roundf(v))
	var digits := str(absi(n))
	var grouped := ""
	while digits.length() > 3:
		grouped = "." + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-$" if n < 0 else "$") + digits + grouped


func _on_world_saved(display_name: String, is_autosave: bool) -> void:
	if is_autosave:
		show_toast("Auto-Save: %s" % display_name)
	else:
		show_toast(tr("Spielstand '%s' gespeichert.") % display_name)


func _on_daily_bill_charged(day_num: int, bill_amount: int, kwh_used: float) -> void:
	show_toast(tr("Stromrechnung Tag %d: -$%d (%.1f kWh)") % [day_num - 1, bill_amount, kwh_used], true)


func _on_event_logged(message: String, severity: String) -> void:
	if severity == "alert" or severity == "warn" or severity == "good":
		show_toast(message, severity != "good")


func _refresh_all() -> void:
	_refresh_stats()
	_refresh_checklist()
	_refresh_crew()


## Schriftfarbe nur bei Änderung setzen: Jede Überschreibung löst ein neues Layout aus.
static func _set_font_col(lbl: Control, col: Color) -> void:
	if not lbl.has_theme_color_override("font_color") or lbl.get_theme_color("font_color") != col:
		lbl.add_theme_color_override("font_color", col)


## Was die Startliste und die Crew-Liste zuletzt gezeigt haben (neu aufbauen nur bei Änderung).
var _checklist_sig: Array = []
var _crew_sig: Array = []
var _crew_ping_lbls: Dictionary = {}
var _net_warn_lbl: Label
var _net_warn_accum: float = 0.0
var _build_lbl: Label


func _refresh_stats() -> void:
	if _power_lbl == null:
		return
	var pwr_ratio := clampf(float(GameState.total_watts) / float(maxi(GameState.max_watts, 1)), 0.0, 1.0)
	var pwr_state := "" if GameState.breaker_on else ("  " + tr("USV") if GameState.ups_backup_active else "  " + tr("AUS"))
	_power_lbl.text = "%d / %d W%s" % [GameState.total_watts, GameState.max_watts, pwr_state]
	_power_bar.value = pwr_ratio * 100.0
	var p_col := UIStyle.COL_GREEN
	if not GameState.breaker_on or GameState.total_watts > GameState.max_watts:
		p_col = UIStyle.COL_AMBER if GameState.ups_backup_active else UIStyle.COL_RED
	elif pwr_ratio > 0.80:
		p_col = UIStyle.COL_AMBER
	_set_font_col(_power_lbl, UIStyle.COL_TEXT_MAIN if p_col == UIStyle.COL_GREEN else p_col)
	_set_bar_color(_power_bar, p_col)
	_set_icon(_power_icon, "power", UIStyle.COL_GOLD_TEXT if p_col == UIStyle.COL_GREEN else p_col)

	_temp_lbl.text = "%.0f °C" % GameState.room_temp
	_temp_bar.value = clampf((GameState.room_temp - 15.0) / 75.0 * 100.0, 0.0, 100.0)
	var hot := GameState.room_temp >= 56.0
	var t_col := UIStyle.COL_TEXT_MAIN if not hot else (UIStyle.COL_AMBER if GameState.room_temp < 72.0 else UIStyle.COL_RED)
	_set_font_col(_temp_lbl, t_col)
	_set_bar_color(_temp_bar, UIStyle.COL_BLUE if not hot else t_col)
	_set_icon(_temp_icon, "temp", UIStyle.COL_BLUE if not hot else t_col)

	_rep_lbl.text = "%s • %s %d" % [GameState.get_reputation_label(), tr("Stufe"), GameState.get_company_level()]
	_rep_bar.value = clampf(GameState.reputation, 0.0, 100.0)


func _refresh_checklist() -> void:
	if _checklist_panel == null or _checklist_box == null:
		return
	if GameState.checklist_dismissed:
		_checklist_panel.visible = false
		return
	var steps := GameState.get_starter_checklist()
	var done_n := 0
	for s in steps:
		if bool((s as Dictionary)["done"]):
			done_n += 1
	if done_n == steps.size():
		_checklist_panel.visible = false
		if _checklist_seen_open:
			_checklist_seen_open = false
			GameState.event_logged.emit(tr("Erste Schritte geschafft! Dein erstes Rack ist vermietet und verdient Geld."), "good")
		return

	_checklist_seen_open = true
	_checklist_panel.visible = true
	_checklist_count_lbl.text = "%d / %d" % [done_n, steps.size()]
	# Kommt mit jedem Sim-Takt: nur neu aufbauen, wenn sich ein Schritt oder eine Taste geändert hat.
	var sig: Array = [TranslationServer.get_locale()]
	for s in steps:
		var sd0: Dictionary = s
		sig.append_array([bool(sd0["done"]), SettingsManager.remap_prompt_keys(tr(str(sd0["text"]))), _format_checklist_hint(tr(str(sd0.get("hint", ""))))])
	if sig == _checklist_sig and _checklist_box.get_child_count() > 0:
		return
	_checklist_sig = sig
	for c in _checklist_box.get_children():
		c.queue_free()

	var shown_next := false
	for s in steps:
		var sd: Dictionary = s
		var done := bool(sd["done"])
		# 2 = erledigt, 1 = aktueller Schritt, 0 = noch offen
		var state := 2 if done else (0 if shown_next else 1)
		if state == 1:
			shown_next = true

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_checklist_box.add_child(row)

		var box := Control.new()
		box.custom_minimum_size = Vector2(14, 14)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := state
		box.draw.connect(func() -> void: _draw_check_box(box, st))
		row.add_child(box)

		var lbl := Label.new()
		lbl.text = SettingsManager.remap_prompt_keys(tr(str(sd["text"])))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := UIStyle.COL_TEXT_MAIN
		if state == 2:
			col = Color(UIStyle.COL_TEXT_SUB, 0.75)
		elif state == 0:
			col = Color(UIStyle.COL_TEXT_SUB, 0.9)
		UIStyle.style_label(lbl, 13 if state == 1 else 12, col)
		row.add_child(lbl)

		var hint := str(sd.get("hint", ""))
		if state == 1 and not hint.is_empty():
			var hint_margin := MarginContainer.new()
			hint_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hint_margin.add_theme_constant_override("margin_left", 27)
			var hint_lbl := Label.new()
			hint_lbl.text = _format_checklist_hint(tr(hint))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			UIStyle.style_label(hint_lbl, 12, UIStyle.COL_TEXT_SUB)
			hint_margin.add_child(hint_lbl)
			_checklist_box.add_child(hint_margin)


## Standardtasten auf die Belegung umschreiben und {aktion} durch die belegte Taste ersetzen.
func _format_checklist_hint(hint: String) -> String:
	var out := SettingsManager.remap_prompt_keys(hint)
	for action in SettingsManager.REBINDABLE_ACTIONS:
		var token := "{%s}" % action
		if out.contains(token):
			out = out.replace(token, SettingsManager.get_action_key_label(action))
	return out


func _draw_check_box(ci: Control, state: int) -> void:
	var r := Rect2(Vector2(1.0, 1.0), ci.size - Vector2(2.0, 2.0))
	match state:
		2:
			ci.draw_rect(r, UIStyle.COL_GREEN)
			var sz := ci.size
			ci.draw_polyline(PackedVector2Array([
				Vector2(0.24, 0.52) * sz, Vector2(0.43, 0.72) * sz, Vector2(0.78, 0.30) * sz
			]), Color(0.05, 0.08, 0.05), 2.0, true)
		1:
			ci.draw_rect(r, Color(UIStyle.COL_ACCENT, 0.18))
			ci.draw_rect(r, UIStyle.COL_ACCENT, false, 1.5)
		_:
			ci.draw_rect(r, Color(0.45, 0.46, 0.48), false, 1.0)


func _set_bar_color(bar: ProgressBar, col: Color) -> void:
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null and fill.bg_color != col:
		fill.bg_color = col


func _refresh_van_badge() -> void:
	if _van_panel == null:
		return
	var ph := GameState.van_phase
	if ph == "idle":
		_van_panel.visible = false
		return
	_van_panel.visible = true
	var q_n := GameState.van_cargo_count + GameState.pending_delivery_count
	match ph:
		"arriving":
			var dur := maxf(float(GameState.VAN_ARRIVE_DURATION), 0.01)
			var eta := maxf(0.0, dur - GameState.van_phase_time)
			_van_lbl.text = tr("Ankunft in %d s  •  %d Artikel") % [int(ceilf(eta)), q_n]
			_van_lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_MAIN)
			_van_bar.value = clampf(GameState.van_phase_time / dur, 0.0, 1.0) * 100.0
			_set_bar_color(_van_bar, UIStyle.COL_ACCENT)
		"unloading":
			var total_n := maxi(GameState.van_trip_total, 1)
			var done_n := mini(GameState.van_trip_done, total_n)
			_van_lbl.text = tr("Fahrer wartet auf Unterschrift [E]") if GameState.van_trip_phase == "sign" else tr("Fahrer lädt aus  •  %d / %d") % [done_n, total_n]
			_van_lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_MAIN)
			_van_bar.value = float(done_n) / float(total_n) * 100.0
			_set_bar_color(_van_bar, UIStyle.COL_GREEN)
		"departing":
			_van_lbl.text = "Lieferung abgeschlossen"
			_van_lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_SUB)
			_van_bar.value = 100.0
			_set_bar_color(_van_bar, UIStyle.COL_GREEN)


func _refresh_alert_banner() -> void:
	if _alert_panel == null:
		return
	var alerts: Array[String] = []
	if GameState.grid_outage_left > 0.0:
		if GameState.ups_backup_active:
			alerts.append(tr("NETZAUSFALL: USV-Notstrom (%.0f%%), noch ca. %d Min.") % [GameState.avg_ups_charge, GameState.get_grid_outage_minutes()])
		else:
			alerts.append(tr("NETZAUSFALL: kein Strom, noch ca. %d Min.") % GameState.get_grid_outage_minutes())
	elif not GameState.breaker_on:
		if GameState.ups_backup_active:
			alerts.append(tr("USV-Notstrom (%.0f%%): Sicherung [E] einschalten") % GameState.avg_ups_charge)
		else:
			alerts.append(tr("BLACKOUT: Hauptsicherung [E] einschalten"))
	elif GameState.total_watts > GameState.max_watts:
		alerts.append(tr("STROM-ÜBERLAST (%d / %d W)") % [GameState.total_watts, GameState.max_watts])
	if GameState.has_any_fire():
		alerts.append(tr("SERVER-BRAND: Feuerlöscher an der Wand holen"))
	if GameState.ddos_active:
		alerts.append(tr("DDoS-ANGRIFF: am Router [E] oder PC abwehren"))
	if not GameState.active_call.is_empty():
		alerts.append(tr("KUNDENANRUF (%s): [E] am Schreibtisch") % str(GameState.active_call.get("customer", "Kunde")))
	elif GameState.get_open_ticket_count() > 0:
		alerts.append(tr("%d offene Support-Tickets am PC") % GameState.get_open_ticket_count())
	if GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps:
		alerts.append(tr("Router am Limit (%s / %s): upgraden [F]") % [
			HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps),
			HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
		])

	if alerts.is_empty():
		_alert_panel.visible = false
		return
	_alert_panel.visible = true
	# Nur die wichtigste Warnung ausschreiben, damit das Banner einzeilig bleibt.
	var alert_txt := alerts[0]
	if alerts.size() > 1:
		alert_txt += "   " + tr("(+%d weitere)") % (alerts.size() - 1)
	_alert_lbl.text = alert_txt
	var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(_blink_t * 7.0))
	_alert_strip.modulate.a = pulse
	_alert_icon.modulate.a = pulse


func _refresh_player_hud(delta: float) -> void:
	if _world == null or _world.local_player == null:
		return
	var lp := _world.local_player

	var want_prompt := (not lp.current_prompt.is_empty() or not lp.current_sub_prompt.is_empty()) and not lp.ui_locked
	_prompt_alpha = lerpf(_prompt_alpha, 1.0 if want_prompt else 0.0, clampf(delta * 16.0, 0.0, 1.0))
	_prompt_panel.visible = _prompt_alpha > 0.02
	_prompt_panel.modulate.a = _prompt_alpha
	if want_prompt:
		var m := _key_regex.search(SettingsManager.remap_prompt_keys(lp.current_prompt))
		if m != null:
			_prompt_key_cap.visible = true
			_prompt_key_lbl.text = m.get_string(1)
			_prompt_lbl.text = m.get_string(2)
		else:
			_prompt_key_cap.visible = false
			_prompt_lbl.text = SettingsManager.remap_prompt_keys(lp.current_prompt)
		_prompt_lbl.visible = not _prompt_lbl.text.is_empty()
		_sub_prompt_lbl.text = SettingsManager.remap_prompt_keys(lp.current_sub_prompt)
		_sub_prompt_lbl.visible = not lp.current_sub_prompt.is_empty()

	var active := not lp.current_prompt.is_empty()
	if active != _crosshair_active:
		_crosshair_active = active
		_crosshair.queue_redraw()


func _refresh_crew() -> void:
	if _crew_panel == null or _crew_box == null:
		return
	# Im Solo-Spiel bleibt das Crew-Panel ausgeblendet
	if NetworkManager.players.size() <= 1:
		_crew_panel.visible = false
		return
	_crew_panel.visible = true
	_update_net_warn()
	# Gleiche Leute wie beim letzten Mal: nur die Ping-Anzeigen auffrischen.
	var sig: Array = []
	for pid0 in NetworkManager.players.keys():
		var inf0: Dictionary = NetworkManager.players[pid0]
		sig.append_array([pid0, str(inf0.get("name", "")), inf0.get("color", Color.WHITE)])
	if sig == _crew_sig and _crew_box.get_child_count() > 0:
		for pid1 in _crew_ping_lbls:
			var pl: Label = _crew_ping_lbls[pid1]
			if not is_instance_valid(pl):
				continue
			_show_ping(pl, int(pid1))
		return
	_crew_sig = sig
	_crew_ping_lbls.clear()
	for child in _crew_box.get_children():
		child.queue_free()

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_box.add_child(head)
	var title := Label.new()
	title.text = "CO-OP CREW"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(title, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	head.add_child(title)
	var count := Label.new()
	count.text = "%d / %d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	UIStyle.style_label(count, 11, UIStyle.COL_TEXT_SUB)
	head.add_child(count)

	for pid in NetworkManager.players.keys():
		var info: Dictionary = NetworkManager.players[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crew_box.add_child(row)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = (info.get("color", Color.WHITE) as Color).lightened(0.2)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)

		var name_lbl := Label.new()
		name_lbl.text = str(info.get("name", tr("Spieler")))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIStyle.style_label(name_lbl, 13, UIStyle.COL_TEXT_MAIN)
		row.add_child(name_lbl)

		if int(pid) != 1:
			var ping_lbl := Label.new()
			ping_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			UIStyle.style_label(ping_lbl, 10, Color(0.45, 0.85, 0.50))
			row.add_child(ping_lbl)
			_crew_ping_lbls[pid] = ping_lbl
			_show_ping(ping_lbl, int(pid))

		if int(pid) == 1:
			var host_lbl := Label.new()
			host_lbl.text = "HOST"
			UIStyle.style_label(host_lbl, 10, UIStyle.COL_GOLD_TEXT, _display_font)
			row.add_child(host_lbl)


const REACH_NAMES := {"lan": "LAN", "tailscale": "Tailscale", "radmin": "Radmin VPN", "hamachi": "Hamachi", "public": "Internet"}
const REACH_HELP := "So kommen Freunde ohne Portfreigabe dazu:\n• Gleiches WLAN oder Netzwerk: Dein Spiel steht bei ihnen unter „Beitreten“ in der LAN-Liste, sonst die LAN-Adresse eintragen.\n• Tailscale (tailscale.com): Beide installieren und im selben Tailnet anmelden (oder dein Gerät teilen). Dann die Tailscale-Adresse (100.x.x.x) eintragen.\n• Radmin VPN: Beide installieren und demselben Netzwerk beitreten. Dann die Radmin-Adresse (26.x.x.x) eintragen.\n• Internet direkt: Nur wenn der Router Port %d (UDP) freigibt. Das versucht das Spiel per UPnP selbst."


## Pausemenü des Hosts: Adressen, unter denen Freunde beitreten können, mit Kopierknopf und Anleitung.
func _add_reach_info(box: VBoxContainer) -> void:
	box.add_child(_section_label(tr("SO ERREICHEN DICH FREUNDE")))
	var port := NetworkManager.hosted_port if NetworkManager.hosted_port > 0 else NetworkManager.DEFAULT_PORT
	var addrs: Array = NetworkManager.reach_addresses()
	if addrs.is_empty():
		var none := Label.new()
		none.text = tr("Keine LAN- oder VPN-Adresse gefunden. Installiere Tailscale oder Radmin VPN, siehe Anleitung.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(none, 12, UIStyle.COL_TEXT_SUB)
		box.add_child(none)
	for a_v in addrs:
		var a: Dictionary = a_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var kind_lbl := Label.new()
		kind_lbl.text = tr(str(REACH_NAMES.get(a["kind"], "")))
		kind_lbl.custom_minimum_size = Vector2(96, 0)
		UIStyle.style_label(kind_lbl, 12, UIStyle.COL_TEXT_SUB)
		row.add_child(kind_lbl)
		var ip_lbl := Label.new()
		var text := "%s:%d" % [str(a["ip"]), port] if port != NetworkManager.DEFAULT_PORT else str(a["ip"])
		ip_lbl.text = text
		ip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIStyle.style_label(ip_lbl, 13, UIStyle.COL_TEXT_MAIN)
		row.add_child(ip_lbl)
		var copy := Button.new()
		copy.text = tr("KOPIEREN")
		copy.custom_minimum_size = Vector2(84, 26)
		UIStyle.style_button(copy, Color(0.14, 0.14, 0.16), UIStyle.COL_BLUE)
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(str(a["ip"]))
			copy.text = tr("KOPIERT")
		)
		row.add_child(copy)
	var help := Label.new()
	help.visible = false
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = tr(REACH_HELP) % port
	UIStyle.style_label(help, 12, UIStyle.COL_TEXT_SUB)
	var help_btn := Button.new()
	help_btn.text = tr("Wie kommen Freunde ohne Portfreigabe dazu?")
	help_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	help_btn.flat = true
	help_btn.add_theme_color_override("font_color", UIStyle.COL_BLUE)
	help_btn.pressed.connect(func() -> void: help.visible = not help.visible)
	box.add_child(help_btn)
	box.add_child(help)


## Läuft auch, wenn vom Host gar nichts mehr kommt (dann gibt es keine Ping- oder Sim-Signale).
func _update_net_warn() -> void:
	if _net_warn_lbl == null:
		return
	if _build_lbl != null:
		_build_lbl.visible = not GameState.local_can_build()
	var warn := NetworkManager.connection_warning()
	_net_warn_lbl.visible = warn != ""
	if warn != "" and _net_warn_lbl.text != "⚠ " + warn:
		_net_warn_lbl.text = "⚠ " + warn


## Ping eines Mitspielers, rot ab 150 ms, mit ⚠ bei Paketverlust.
func _show_ping(pl: Label, peer_id: int) -> void:
	var p := NetworkManager.get_player_ping(peer_id)
	pl.visible = p >= 0
	if p < 0:
		return
	var loss := NetworkManager.get_player_loss(peer_id)
	var bad_loss := loss >= NetworkManager.CONN_LOSS_WARN
	var txt := ("⚠ %d ms" if bad_loss else "%d ms") % p
	if pl.text != txt:
		pl.text = txt
		pl.tooltip_text = tr("%d %% Paketverlust") % int(roundf(loss)) if bad_loss else ""
	_set_font_col(pl, Color(1.0, 0.42, 0.38) if p > 150 or bad_loss else (Color(0.95, 0.85, 0.35) if p > 80 else Color(0.45, 0.85, 0.50)))


func _on_pause_quick_settings_changed(_val: float = 0.0) -> void:
	SettingsManager.master_volume = _pause_master_slider.value / 100.0
	SettingsManager.fan_volume = _pause_fan_slider.value / 100.0
	SettingsManager.mouse_sensitivity = _pause_sens_slider.value / 1000.0
	_apply_pause_general()
	SettingsManager.graphics_quality = clampi(_pause_gfx_option.selected, 0, 3)
	if _pause_aa_option != null:
		SettingsManager.anti_aliasing = clampi(_pause_aa_option.selected, 0, SettingsManager.AA_COUNT - 1)
		SettingsManager.render_scale = clampf(_pause_scale_slider.value / 100.0, SettingsManager.RENDER_SCALE_MIN, SettingsManager.RENDER_SCALE_MAX)
		SettingsManager.upscaler = clampi(_pause_upscaler_option.selected, 0, SettingsManager.UPSCALER_COUNT - 1)
		SettingsManager.sharpness = clampf(_pause_sharp_slider.value / 100.0, 0.0, 1.0)
		SettingsManager.anisotropic = clampi(_pause_aniso_option.selected, 0, SettingsManager.ANISO_LEVELS.size() - 1)
		var fps_idx := clampi(_pause_fps_option.selected, 0, SettingsManager.FPS_LIMITS.size() - 1)
		SettingsManager.max_fps = SettingsManager.FPS_LIMITS[fps_idx]
		SettingsManager.vsync = _pause_vsync_check.button_pressed
		SettingsManager.own_lamp_shadow = _pause_shadow_check.button_pressed
		_update_pause_sharpness_state()
	SettingsManager.save_settings()


func _sync_pause_graphics() -> void:
	if _pause_aa_option == null:
		return
	_pause_aa_option.selected = SettingsManager.anti_aliasing
	_pause_scale_slider.set_value_no_signal(SettingsManager.render_scale * 100.0)
	_pause_upscaler_option.selected = SettingsManager.upscaler
	_pause_sharp_slider.set_value_no_signal(SettingsManager.sharpness * 100.0)
	_pause_aniso_option.selected = SettingsManager.anisotropic
	_pause_fps_option.selected = maxi(SettingsManager.FPS_LIMITS.find(SettingsManager.max_fps), 0)
	_pause_vsync_check.set_pressed_no_signal(SettingsManager.vsync)
	_pause_shadow_check.set_pressed_no_signal(SettingsManager.own_lamp_shadow)
	_update_slider_label(_pause_scale_slider)
	_update_slider_label(_pause_sharp_slider)
	_update_pause_sharpness_state()


func _update_pause_sharpness_state() -> void:
	if _pause_sharp_slider == null or _pause_scale_slider == null or _pause_upscaler_option == null:
		return
	var active := SettingsManager.is_sharpness_active(_pause_scale_slider.value / 100.0, _pause_upscaler_option.selected)
	_pause_sharp_slider.editable = active
	_pause_sharp_slider.modulate.a = 1.0 if active else 0.45


func _on_port_forward_finished(ok: bool, _ip: String, message: String) -> void:
	show_toast(message, not ok)


func _build_ui() -> void:
	_display_font = UIStyle.make_display_font(get_theme_default_font(), 0.5, 1)
	if not NetworkManager.port_forward_finished.is_connected(_on_port_forward_finished):
		NetworkManager.port_forward_finished.connect(_on_port_forward_finished)
	_build_stats_row()
	_build_checklist()
	_build_clock_widget()
	_build_alert_banner()
	_build_toast()
	_build_van_widget()
	_build_right_column()
	_build_key_hints()
	_build_slot_bar()
	_build_buff_row()
	_build_crosshair_and_prompt()
	# Alles außer dem Pause-Menü lässt Mausklicks durch
	for child in get_children():
		_ignore_mouse_recursive(child)
	_build_pause_overlay()


func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse_recursive(c)


func _build_stats_row() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(EDGE, EDGE)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var money_v := _make_chip(row, "", "KONTOSTAND")
	_money_lbl = Label.new()
	_money_lbl.text = "$1.800"
	UIStyle.style_label(_money_lbl, 21, UIStyle.COL_GOLD_TEXT, _display_font, true)
	money_v.add_child(_money_lbl)

	var pwr_v := _make_chip(row, "power", "STROMLAST")
	_power_icon = pwr_v.get_meta("icon") as Control
	_power_lbl = Label.new()
	_power_lbl.text = "0 / 2400 W"
	UIStyle.style_label(_power_lbl, 14, UIStyle.COL_TEXT_MAIN, _display_font)
	pwr_v.add_child(_power_lbl)
	_power_bar = _make_mini_bar(UIStyle.COL_GREEN)
	_power_bar.custom_minimum_size = Vector2(150, 5)
	pwr_v.add_child(_power_bar)

	var tmp_v := _make_chip(row, "temp", "RAUMTEMPERATUR")
	_temp_icon = tmp_v.get_meta("icon") as Control
	_temp_lbl = Label.new()
	_temp_lbl.text = "22 °C"
	UIStyle.style_label(_temp_lbl, 14, UIStyle.COL_TEXT_MAIN, _display_font)
	tmp_v.add_child(_temp_lbl)
	_temp_bar = _make_mini_bar(UIStyle.COL_BLUE)
	_temp_bar.custom_minimum_size = Vector2(110, 5)
	tmp_v.add_child(_temp_bar)

	var rep_v := _make_chip(row, "", "RUF")
	_rep_lbl = Label.new()
	_rep_lbl.text = tr("Unbekannt")
	UIStyle.style_label(_rep_lbl, 14, UIStyle.COL_TEXT_MAIN, _display_font)
	rep_v.add_child(_rep_lbl)
	_rep_bar = _make_mini_bar(UIStyle.COL_ACCENT)
	rep_v.add_child(_rep_bar)


## Status-Kachel: optionales Symbol links, rechts Beschriftung und Inhalt.
## Gibt die Inhalts-Spalte zurück; das Symbol liegt als Meta "icon" daran.
func _make_chip(parent: HBoxContainer, icon_kind: String, caption: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 12, 8))
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)

	var icon: Control = null
	if not icon_kind.is_empty():
		icon = _make_icon(icon_kind, UIStyle.COL_GOLD_TEXT, 18)
		h.add_child(icon)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)

	var cap := Label.new()
	cap.text = caption
	UIStyle.style_label(cap, 10, UIStyle.COL_TEXT_SUB, _display_font)
	v.add_child(cap)
	v.set_meta("icon", icon)
	return v


func _make_icon(kind: String, col: Color, px: int) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_meta("kind", kind)
	ic.set_meta("col", col)
	ic.draw.connect(func() -> void:
		UIStyle.draw_icon(ic, str(ic.get_meta("kind")), Rect2(Vector2.ZERO, ic.size), ic.get_meta("col") as Color)
	)
	return ic


func _set_icon(ic: Control, kind: String, col: Color) -> void:
	if ic == null:
		return
	if ic.get_meta("kind", "") == kind and ic.get_meta("col", Color.TRANSPARENT) == col:
		return
	ic.set_meta("kind", kind)
	ic.set_meta("col", col)
	ic.queue_redraw()


func _build_clock_widget() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -EDGE
	panel.offset_right = -EDGE
	panel.offset_top = EDGE
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 14, 8))
	add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)

	_clock_icon = _make_icon("sun", UIStyle.COL_GOLD_TEXT, 22)
	h.add_child(_clock_icon)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)

	_day_lbl = Label.new()
	_day_lbl.text = "TAG 1"
	UIStyle.style_label(_day_lbl, 10, UIStyle.COL_TEXT_SUB, _display_font)
	v.add_child(_day_lbl)

	_clock_lbl = Label.new()
	_clock_lbl.text = "08:00"
	UIStyle.style_label(_clock_lbl, 20, UIStyle.COL_TEXT_MAIN, _display_font, true)
	v.add_child(_clock_lbl)


func _build_checklist() -> void:
	_checklist_panel = PanelContainer.new()
	_checklist_panel.position = Vector2(EDGE, 92)
	_checklist_panel.custom_minimum_size = Vector2(290, 0)
	_checklist_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 0, 0))
	add_child(_checklist_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	_checklist_panel.add_child(h)

	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(3, 0)
	strip.color = UIStyle.COL_ACCENT
	h.add_child(strip)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	h.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "ERSTE SCHRITTE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(title, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	head.add_child(title)
	_checklist_count_lbl = Label.new()
	UIStyle.style_label(_checklist_count_lbl, 11, UIStyle.COL_TEXT_SUB)
	head.add_child(_checklist_count_lbl)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.tooltip_text = tr("Checkliste ausblenden")
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.add_theme_color_override("font_color", UIStyle.COL_TEXT_SUB)
	close_btn.pressed.connect(_on_checklist_dismissed)
	head.add_child(close_btn)

	_checklist_box = VBoxContainer.new()
	_checklist_box.add_theme_constant_override("separation", 6)
	v.add_child(_checklist_box)


func _on_checklist_dismissed() -> void:
	GameState.checklist_dismissed = true
	_refresh_checklist()


func _build_alert_banner() -> void:
	_alert_panel = PanelContainer.new()
	_alert_panel.anchor_left = 0.5
	_alert_panel.anchor_right = 0.5
	_alert_panel.offset_left = -220
	_alert_panel.offset_right = 220
	_alert_panel.offset_top = 92
	_alert_panel.visible = false
	_alert_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.20, 0.06, 0.055, 0.92), Color(UIStyle.COL_RED, 0.8), 4, 1, 0, 0))
	add_child(_alert_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_alert_panel.add_child(h)

	_alert_strip = ColorRect.new()
	_alert_strip.custom_minimum_size = Vector2(4, 0)
	_alert_strip.color = UIStyle.COL_RED
	h.add_child(_alert_strip)

	_alert_icon = _make_icon("warn", Color(1.0, 0.78, 0.70), 14)
	h.add_child(_alert_icon)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	h.add_child(m)

	_alert_lbl = Label.new()
	_alert_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.style_label(_alert_lbl, 12, Color(1.0, 0.90, 0.86), _display_font)
	m.add_child(_alert_lbl)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.offset_left = -180
	_toast_panel.offset_right = 180
	_toast_panel.offset_top = TOAST_TOP
	_toast_panel.offset_bottom = TOAST_TOP
	_toast_panel.custom_minimum_size = Vector2(360, 0)
	_toast_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toast_panel.visible = false
	_toast_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.065, 0.068, 0.076, 0.94), HUD_BORDER, 4, 1, 0, 0))
	add_child(_toast_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_toast_panel.add_child(h)

	_toast_strip = ColorRect.new()
	_toast_strip.custom_minimum_size = Vector2(3, 0)
	_toast_strip.color = UIStyle.COL_GREEN
	h.add_child(_toast_strip)

	_toast_icon = _make_icon("info", UIStyle.COL_GREEN, 14)
	h.add_child(_toast_icon)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 6)
	h.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	m.add_child(v)

	_toast_title = Label.new()
	_toast_title.text = "MELDUNG"
	UIStyle.style_label(_toast_title, 9, UIStyle.COL_GREEN, _display_font)
	v.add_child(_toast_title)

	_toast_lbl = Label.new()
	_toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Feste Mindestbreite, damit der Umbruch nie mit Breite 0 rechnet (ein Wort pro Zeile).
	_toast_lbl.custom_minimum_size = Vector2(300, 0)
	_toast_lbl.max_lines_visible = 3
	UIStyle.style_label(_toast_lbl, 12, UIStyle.COL_TEXT_MAIN)
	v.add_child(_toast_lbl)


func _build_van_widget() -> void:
	_van_panel = PanelContainer.new()
	_van_panel.anchor_top = 1.0
	_van_panel.anchor_bottom = 1.0
	_van_panel.offset_left = EDGE
	_van_panel.offset_top = -EDGE
	_van_panel.offset_bottom = -EDGE
	_van_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_van_panel.custom_minimum_size = Vector2(280, 0)
	_van_panel.visible = false
	_van_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 14, 10))
	add_child(_van_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_van_panel.add_child(h)

	h.add_child(_make_icon("truck", UIStyle.COL_GOLD_TEXT, 24))

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)

	var cap := Label.new()
	cap.text = "LIEFERUNG  •  CLOUD EXPRESS"
	UIStyle.style_label(cap, 10, UIStyle.COL_GOLD_TEXT, _display_font)
	v.add_child(cap)

	_van_lbl = Label.new()
	UIStyle.style_label(_van_lbl, 13, UIStyle.COL_TEXT_MAIN)
	v.add_child(_van_lbl)

	_van_bar = _make_mini_bar(UIStyle.COL_ACCENT)
	_van_bar.custom_minimum_size = Vector2(0, 4)
	v.add_child(_van_bar)


func _build_right_column() -> void:
	var right_col := VBoxContainer.new()
	right_col.anchor_left = 1.0
	right_col.anchor_right = 1.0
	right_col.offset_left = -290
	right_col.offset_right = -EDGE
	right_col.offset_top = 86
	right_col.add_theme_constant_override("separation", 8)
	add_child(right_col)

	_crew_panel = PanelContainer.new()
	_crew_panel.visible = false
	_crew_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 12, 10))
	right_col.add_child(_crew_panel)

	var crew_v := VBoxContainer.new()
	crew_v.add_theme_constant_override("separation", 6)
	crew_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crew_panel.add_child(crew_v)
	# Warnung zur eigenen Verbindung (Paketverlust, hoher Ping, Host schweigt).
	_net_warn_lbl = Label.new()
	_net_warn_lbl.visible = false
	_net_warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(_net_warn_lbl, 12, Color(1.0, 0.55, 0.40))
	crew_v.add_child(_net_warn_lbl)
	_build_lbl = Label.new()
	_build_lbl.visible = false
	_build_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_lbl.text = tr("🔒 Du kannst dich umsehen und helfen. Bauen geht erst, wenn dich Host oder Admin freigeben.")
	UIStyle.style_label(_build_lbl, 12, UIStyle.COL_AMBER)
	crew_v.add_child(_build_lbl)
	_crew_box = VBoxContainer.new()
	_crew_box.add_theme_constant_override("separation", 5)
	crew_v.add_child(_crew_box)

	_help_panel = PanelContainer.new()
	_help_panel.visible = false # Standardmäßig aus, Umschalten mit [H]
	_help_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 14, 12))
	right_col.add_child(_help_panel)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	_help_panel.add_child(hv)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	hv.add_child(head)
	var title := Label.new()
	title.text = "STEUERUNG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(title, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	head.add_child(title)
	head.add_child(_make_keycap("H"))
	var close_lbl := Label.new()
	close_lbl.text = "schließen"
	UIStyle.style_label(close_lbl, 11, UIStyle.COL_TEXT_SUB)
	head.add_child(close_lbl)

	var rows: Array = [
		["E", tr("Interagieren (Kontext-Hand)")],
		["E", tr("Am PC: hinsetzen, Shop & Support")],
		["E", tr("Buchse: Kabel ziehen (gelb Strom, blau LAN)")],
		["E", tr("Am Rack: Übersicht & Teile einbauen")],
		["F", tr("Am Router: Geschwindigkeit upgraden")],
		["RMB", tr("Trennen / Ausbauen")],
		["R", tr("Drehen")],
		["Q", tr("Ablegen")],
		["G / MMB", tr("3D-Ping / Wegpunkt im Team setzen")],
		["B / N", tr("Emotes: Winken & Daumen hoch")],
		["V", tr("Gesten-Rad (halten)")],
		["E", tr("Garagentor-Taster (öffnet/schließt Tor & dämpft Lärm)")],
		["ESC", "Pause"],
	]
	for item in rows:
		var pair: Array = item
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		hv.add_child(r)
		var cap := _make_keycap(str(pair[0]))
		cap.custom_minimum_size = Vector2(40, 0)
		r.add_child(cap)
		var d := Label.new()
		d.text = str(pair[1])
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(d, 12, UIStyle.COL_TEXT_MAIN)
		r.add_child(d)


func _build_key_hints() -> void:
	var hints := HBoxContainer.new()
	hints.anchor_left = 1.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = -EDGE
	hints.offset_right = -EDGE
	hints.offset_top = -EDGE
	hints.offset_bottom = -EDGE
	hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.add_theme_constant_override("separation", 6)
	hints.modulate.a = 0.8
	add_child(hints)

	var help_cap := _make_keycap(SettingsManager.get_action_key_label("toggle_help"))
	_help_key_lbl = help_cap.get_child(0) as Label
	hints.add_child(help_cap)
	if not SettingsManager.key_bindings_changed.is_connected(_on_key_bindings_changed):
		SettingsManager.key_bindings_changed.connect(_on_key_bindings_changed)
	hints.add_child(_hint_label(tr("Steuerung")))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	hints.add_child(gap)
	hints.add_child(_make_keycap("G"))
	hints.add_child(_hint_label("Ping"))
	var gap_em := Control.new()
	gap_em.custom_minimum_size = Vector2(8, 0)
	hints.add_child(gap_em)
	hints.add_child(_make_keycap("V"))
	hints.add_child(_hint_label("Gesten"))
	var gap_p := Control.new()
	gap_p.custom_minimum_size = Vector2(8, 0)
	hints.add_child(gap_p)
	hints.add_child(_make_keycap("ESC"))
	hints.add_child(_hint_label("Pause"))


func _on_key_bindings_changed() -> void:
	if _help_key_lbl != null and is_instance_valid(_help_key_lbl):
		_help_key_lbl.text = SettingsManager.get_action_key_label("toggle_help")
	_refresh_checklist()


func _hint_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(l, 12, UIStyle.COL_TEXT_SUB, null, true)
	return l


func _build_crosshair_and_prompt() -> void:
	_crosshair = Control.new()
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -12
	_crosshair.offset_top = -12
	_crosshair.offset_right = 12
	_crosshair.offset_bottom = 12
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)

	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_top = 30
	center.offset_bottom = 96
	add_child(center)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.visible = false
	_prompt_panel.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.05, 0.053, 0.06, 0.84), HUD_BORDER, 4, 1, 12, 8))
	center.add_child(_prompt_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_prompt_panel.add_child(h)

	_prompt_key_cap = _make_keycap("E", 12)
	_prompt_key_cap.custom_minimum_size = Vector2(24, 22)
	_prompt_key_lbl = _prompt_key_cap.get_child(0) as Label
	h.add_child(_prompt_key_cap)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)

	_prompt_lbl = Label.new()
	UIStyle.style_label(_prompt_lbl, 13, UIStyle.COL_TEXT_MAIN, _display_font)
	v.add_child(_prompt_lbl)

	_sub_prompt_lbl = Label.new()
	UIStyle.style_label(_sub_prompt_lbl, 11, UIStyle.COL_TEXT_SUB)
	v.add_child(_sub_prompt_lbl)


func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	if _crosshair_active:
		_crosshair.draw_arc(c, 8.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.35), 3.0, true)
		_crosshair.draw_arc(c, 8.0, 0.0, TAU, 32, UIStyle.COL_GOLD_TEXT, 1.5, true)
		_crosshair.draw_circle(c, 2.0, UIStyle.COL_GOLD_TEXT)
	else:
		_crosshair.draw_circle(c, 3.0, Color(0.0, 0.0, 0.0, 0.35))
		_crosshair.draw_circle(c, 2.0, Color(1.0, 1.0, 1.0, 0.85))


## Hand-Inventar: vier Slots unten in der Mitte. Der aktive Slot hat einen Amber-Rahmen.
func _build_slot_bar() -> void:
	_slot_bar = HBoxContainer.new()
	_slot_bar.anchor_left = 0.5
	_slot_bar.anchor_right = 0.5
	_slot_bar.anchor_top = 1.0
	_slot_bar.anchor_bottom = 1.0
	_slot_bar.offset_top = -EDGE
	_slot_bar.offset_bottom = -EDGE
	_slot_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slot_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_slot_bar.add_theme_constant_override("separation", 6)
	add_child(_slot_bar)

	for i in GameState.SLOT_COUNT:
		var sb := UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 10, 6)
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(112, 0)
		cell.add_theme_stylebox_override("panel", sb)
		_slot_bar.add_child(cell)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		cell.add_child(h)

		h.add_child(_make_keycap(str(i + 1)))

		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIStyle.style_label(name_lbl, 11, UIStyle.COL_TEXT_SUB)
		h.add_child(name_lbl)

		_slot_styles.append(sb)
		_slot_item_lbls.append(name_lbl)


## Kleine Anzeige über der Slot-Leiste: Kaffee, Wasser und Pause mit Restzeit.
const BUFF_META := {
	"coffee": ["cup", "Kaffee", Color(0.93, 0.70, 0.38)],
	"water": ["drop", "Erfrischt", Color(0.45, 0.78, 1.0)],
	"rest": ["sofa", "Ausgeruht", Color(0.62, 0.92, 0.60)],
	"food": ["cup", "Gestärkt", Color(0.95, 0.55, 0.35)],
}


func _build_buff_row() -> void:
	_buff_row = HBoxContainer.new()
	_buff_row.anchor_left = 0.5
	_buff_row.anchor_right = 0.5
	_buff_row.anchor_top = 1.0
	_buff_row.anchor_bottom = 1.0
	_buff_row.offset_top = -EDGE - 46.0
	_buff_row.offset_bottom = -EDGE - 46.0
	_buff_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buff_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_buff_row.add_theme_constant_override("separation", 6)
	add_child(_buff_row)
	for k in BUFF_META.keys():
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", UIStyle.make_panel(HUD_BG, HUD_BORDER, 4, 1, 8, 4))
		cell.visible = false
		_buff_row.add_child(cell)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		cell.add_child(h)
		h.add_child(_make_icon(str(BUFF_META[k][0]), BUFF_META[k][2], 14))
		var l := Label.new()
		UIStyle.style_label(l, 11, UIStyle.COL_TEXT_MAIN)
		h.add_child(l)
		_buff_cells[k] = [cell, l]


func _refresh_buff_row() -> void:
	if _buff_row == null:
		return
	var b: Dictionary = {}
	if _world != null and _world.local_player != null and not _world.local_player.ui_locked:
		b = DecorManager.get_buffs(_world.local_player.peer_id)
	for k in _buff_cells.keys():
		var left := float(b.get(k, 0.0))
		var cell: PanelContainer = _buff_cells[k][0]
		cell.visible = left > 0.0
		if left > 0.0:
			(_buff_cells[k][1] as Label).text = "%s %d:%02d" % [tr(str(BUFF_META[k][1])), int(left) / 60, int(left) % 60]


## Liest pro Frame, was in welchem Slot liegt, und baut die Leiste nur bei Änderungen neu auf.
func _refresh_slot_bar() -> void:
	if _slot_bar == null:
		return
	if _world == null or _world.local_player == null:
		_slot_bar.visible = false
		return
	var lp := _world.local_player
	_slot_bar.visible = not lp.ui_locked
	if not _slot_bar.visible:
		return

	var pid: int = lp.peer_id
	var active: int = GameState.get_active_slot(pid)
	var names := PackedStringArray()
	names.resize(GameState.SLOT_COUNT)
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if int(c.get("held_by", 0)) != pid:
			continue
		var s := clampi(int(c.get("held_slot", 1)), 1, GameState.SLOT_COUNT)
		names[s - 1] = GameState.get_crate_display_label(c)
	for ext_id in GameState.extinguishers.keys():
		var ext: Dictionary = GameState.extinguishers[ext_id]
		if int(ext["held_by"]) == pid:
			names[clampi(int(ext["slot"]), 1, GameState.SLOT_COUNT) - 1] = tr("Feuerlöscher")
	for i in GameState.SLOT_COUNT:
		if not names[i].is_empty():
			continue
		var cable_type: String = lp.get_slot_cable_type(i + 1)
		if not cable_type.is_empty():
			if cable_type == "cluster":
				names[i] = tr("Cluster-Kabel")
			else:
				names[i] = tr("Stromkabel") if cable_type == "power" else tr("Netzwerkkabel")

	var sig := "%d|%s" % [active, "|".join(names)]
	if sig == _slot_sig:
		return
	_slot_sig = sig
	for i in _slot_styles.size():
		var is_active := i + 1 == active
		_slot_styles[i].border_color = UIStyle.COL_ACCENT if is_active else HUD_BORDER
		var lbl := _slot_item_lbls[i]
		lbl.text = names[i] if not names[i].is_empty() else tr("Leer")
		lbl.add_theme_color_override("font_color", UIStyle.COL_TEXT_MAIN if is_active else UIStyle.COL_TEXT_SUB)


func _make_keycap(key: String, font_size: int = 11) -> PanelContainer:
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
	cap.custom_minimum_size = Vector2(22, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.style_label(l, font_size, UIStyle.COL_TEXT_MAIN, _display_font)
	cap.add_child(l)
	return cap


func _build_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.02, 0.022, 0.026, 0.62)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	_pause_overlay.add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.6)]),
		PackedFloat32Array([0.35, 1.0]),
		Vector2(0.5, 0.5), Vector2(1.05, 0.5), true
	))

	var pcenter := CenterContainer.new()
	pcenter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(pcenter)

	_pause_card = PanelContainer.new()
	_pause_card.custom_minimum_size = Vector2(480, 0)
	_pause_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_DARK, UIStyle.COL_BORDER, UIStyle.MAX_RADIUS, 1, 28, 24))
	pcenter.add_child(_pause_card)

	var pvbox := VBoxContainer.new()
	pvbox.add_theme_constant_override("separation", 10)
	_pause_card.add_child(pvbox)

	# Kopf: Logo, Titel, Welt und Uhrzeit
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	pvbox.add_child(head)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(40, 40)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.draw.connect(func() -> void: UIStyle.draw_logo_mark(logo, Rect2(Vector2.ZERO, logo.size)))
	head.add_child(logo)

	var head_v := VBoxContainer.new()
	head_v.add_theme_constant_override("separation", 0)
	head_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_v)

	var ptitle := Label.new()
	ptitle.text = "PAUSIERT"
	UIStyle.style_label(ptitle, 26, UIStyle.COL_TEXT_MAIN, _display_font, true)
	head_v.add_child(ptitle)

	_pause_world_lbl = Label.new()
	_pause_world_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(_pause_world_lbl, 12, UIStyle.COL_TEXT_SUB)
	head_v.add_child(_pause_world_lbl)
	# Das Menü hält nichts an: Uhr, Server und Mitspieler laufen weiter (auch beim Host).
	_pause_runs_lbl = Label.new()
	_pause_runs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(_pause_runs_lbl, 12, UIStyle.COL_AMBER)
	head_v.add_child(_pause_runs_lbl)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(56, 2)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.color = UIStyle.COL_ACCENT
	pvbox.add_child(accent)

	var resume_btn := Button.new()
	resume_btn.text = "WEITERSPIELEN"
	resume_btn.custom_minimum_size = Vector2(0, 46)
	UIStyle.style_button(resume_btn, Color(0.74, 0.49, 0.12), Color(0.96, 0.72, 0.24))
	resume_btn.add_theme_font_override("font", _display_font)
	resume_btn.add_theme_font_size_override("font_size", 16)
	resume_btn.pressed.connect(func(): resume_requested.emit())
	pvbox.add_child(resume_btn)

	var fig_btn := Button.new()
	fig_btn.text = "FIGUR ANPASSEN"
	fig_btn.custom_minimum_size = Vector2(0, 38)
	UIStyle.style_button(fig_btn, Color(0.14, 0.17, 0.22), UIStyle.COL_BORDER)
	fig_btn.add_theme_font_override("font", _display_font)
	fig_btn.pressed.connect(func(): avatar_requested.emit())
	pvbox.add_child(fig_btn)

	_save_section = VBoxContainer.new()
	_save_section.add_theme_constant_override("separation", 6)
	pvbox.add_child(_save_section)
	_save_section.add_child(_section_label(tr("SPIELSTAND (HOST)")))

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	_save_section.add_child(srow)

	_save_name_input = LineEdit.new()
	_save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name_input.max_length = 32
	UIStyle.style_line_edit(_save_name_input)
	srow.add_child(_save_name_input)

	var save_btn := Button.new()
	save_btn.text = "SPEICHERN"
	save_btn.custom_minimum_size = Vector2(126, 36)
	UIStyle.style_button(save_btn, Color(0.16, 0.26, 0.16), UIStyle.COL_GREEN)
	save_btn.add_theme_font_override("font", _display_font)
	save_btn.pressed.connect(func():
		var res := GameState.save_current_world(_save_name_input.text, false)
		if not bool(res.get("ok", false)):
			show_toast(tr(str(res.get("error", "Speichern fehlgeschlagen"))), true)
	)
	srow.add_child(save_btn)

	pvbox.add_child(_section_label(tr("SCHNELL-EINSTELLUNGEN")))
	_pause_master_slider = _add_pause_slider(pvbox, "Gesamtlautstärke", 0, 100, 1, "%d%%")
	_pause_sfx_slider = _add_pause_slider(pvbox, "Effekte & UI (SFX)", 0, 100, 1, "%d%%")
	_pause_fan_slider = _add_pause_slider(pvbox, "Server-Lüfter & Raum", 0, 100, 1, "%d%%")
	_pause_sens_slider = _add_pause_slider(pvbox, "Maus-Empfindlichkeit", 0.5, 8.0, 0.1, "%.1f")
	_pause_fov_slider = _add_pause_slider(pvbox, "Sichtfeld (FOV)", 60, 105, 1, "%d°")

	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 10)
	pvbox.add_child(grow)
	var glbl := Label.new()
	glbl.text = "Grafikqualität"
	glbl.custom_minimum_size = Vector2(170, 0)
	glbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(glbl, 13, Color(0.80, 0.81, 0.81))
	grow.add_child(glbl)
	_pause_gfx_option = OptionButton.new()
	_pause_gfx_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_gfx_option.custom_minimum_size = Vector2(0, 34)
	_pause_gfx_option.add_item("Niedrig (FPS)")
	_pause_gfx_option.add_item("Mittel (SSAO)")
	_pause_gfx_option.add_item("Hoch (SSIL + SSR)")
	_pause_gfx_option.add_item("Ultra (SDFGI + Nebel)")
	UIStyle.style_button(_pause_gfx_option)
	_pause_gfx_option.item_selected.connect(func(_idx: int): _on_pause_quick_settings_changed())
	grow.add_child(_pause_gfx_option)

	_pause_gfx_toggle = Button.new()
	_pause_gfx_toggle.text = "Erweiterte Grafik ▸"
	_pause_gfx_toggle.toggle_mode = true
	_pause_gfx_toggle.custom_minimum_size = Vector2(0, 32)
	UIStyle.style_button(_pause_gfx_toggle)
	pvbox.add_child(_pause_gfx_toggle)

	# Eigener Scrollbereich, damit das Pausemenü auch auf 720p-Bildschirmen passt.
	var gfx_scroll := ScrollContainer.new()
	gfx_scroll.custom_minimum_size = Vector2(0, 230)
	gfx_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gfx_scroll.visible = false
	pvbox.add_child(gfx_scroll)

	_pause_gfx_details = VBoxContainer.new()
	_pause_gfx_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_gfx_details.add_theme_constant_override("separation", 8)
	gfx_scroll.add_child(_pause_gfx_details)

	_pause_gfx_toggle.toggled.connect(func(on: bool):
		gfx_scroll.visible = on
		_pause_gfx_toggle.text = "Erweiterte Grafik ▾" if on else "Erweiterte Grafik ▸"
	)

	_pause_aa_option = _add_pause_option(_pause_gfx_details, "Kantenglättung", SettingsManager.AA_LABELS)
	_pause_scale_slider = _add_pause_slider(_pause_gfx_details, "Render-Auflösung", SettingsManager.RENDER_SCALE_MIN * 100.0, SettingsManager.RENDER_SCALE_MAX * 100.0, 5.0, "%d%%")
	_pause_upscaler_option = _add_pause_option(_pause_gfx_details, "Hochskalierung", SettingsManager.UPSCALER_LABELS)
	if _pause_aa_option != null:
		_pause_aa_option.tooltip_text = tr("Mit AMD FSR 2.2 ist MSAA automatisch aus, weil FSR 2.2 die Kanten selbst glättet. Deine MSAA-Auswahl greift wieder bei Bilinear oder FSR 1.0.")
	_pause_sharp_slider = _add_pause_slider(_pause_gfx_details, "Schärfe (FSR)", 0.0, 100.0, 5.0, "%d%%")
	_pause_aniso_option = _add_pause_option(_pause_gfx_details, "Texturfilter", SettingsManager.ANISO_LABELS)
	_pause_fps_option = _add_pause_option(_pause_gfx_details, "FPS-Limit", SettingsManager.get_fps_labels())

	_pause_vsync_check = CheckButton.new()
	_pause_vsync_check.text = "V-Sync (kein Bildreißen)"
	_pause_vsync_check.add_theme_font_size_override("font_size", 13)
	_pause_vsync_check.add_theme_color_override("font_color", Color(0.80, 0.81, 0.81))
	_pause_vsync_check.toggled.connect(func(_on: bool): _on_pause_quick_settings_changed())
	_pause_gfx_details.add_child(_pause_vsync_check)
	_pause_shadow_check = CheckButton.new()
	_pause_shadow_check.text = tr("Eigener Schatten unter Hallenlampen (kostet FPS)")
	_pause_shadow_check.add_theme_font_size_override("font_size", 13)
	_pause_shadow_check.add_theme_color_override("font_color", Color(0.80, 0.81, 0.81))
	_pause_shadow_check.toggled.connect(func(_on: bool): _on_pause_quick_settings_changed())
	_pause_gfx_details.add_child(_pause_shadow_check)

	_build_pause_general_section(pvbox)

	_pause_players_box = VBoxContainer.new()
	_pause_players_box.add_theme_constant_override("separation", 6)
	_pause_players_box.visible = false
	pvbox.add_child(_pause_players_box)

	_pause_admin_btn = Button.new()
	_pause_admin_btn.text = tr("Admin-Menü [F10]")
	_pause_admin_btn.custom_minimum_size = Vector2(0, 34)
	UIStyle.style_button(_pause_admin_btn, Color(0.20, 0.17, 0.10), UIStyle.COL_ACCENT)
	_pause_admin_btn.pressed.connect(func(): admin_requested.emit())
	pvbox.add_child(_pause_admin_btn)

	var log_btn := Button.new()
	log_btn.text = "Log-Ordner öffnen"
	log_btn.custom_minimum_size = Vector2(0, 32)
	UIStyle.style_button(log_btn, Color(0.12, 0.15, 0.17), UIStyle.COL_BORDER)
	log_btn.pressed.connect(_open_log_folder)
	pvbox.add_child(log_btn)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(UIStyle.COL_BORDER, 0.7)
	pvbox.add_child(rule)

	var leave_btn := Button.new()
	leave_btn.text = "ZURÜCK ZUM HAUPTMENÜ"
	leave_btn.custom_minimum_size = Vector2(0, 40)
	UIStyle.style_button(leave_btn, Color(0.24, 0.11, 0.10), UIStyle.COL_RED)
	leave_btn.add_theme_font_override("font", _display_font)
	leave_btn.pressed.connect(func(): leave_requested.emit())
	pvbox.add_child(leave_btn)


## Aufklappbarer Bereich mit Anzeige- und allgemeinen Einstellungen (wie im Hauptmenü).
func _build_pause_general_section(parent: VBoxContainer) -> void:
	var toggle := Button.new()
	toggle.text = "Anzeige, Steuerung & Allgemein ▸"
	toggle.toggle_mode = true
	toggle.custom_minimum_size = Vector2(0, 32)
	UIStyle.style_button(toggle)
	parent.add_child(toggle)

	# Eigener Scrollbereich wie bei der erweiterten Grafik, damit das Menü auf 720p passt.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	parent.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	toggle.toggled.connect(func(on: bool):
		scroll.visible = on
		toggle.text = "Anzeige, Steuerung & Allgemein ▾" if on else "Anzeige, Steuerung & Allgemein ▸"
	)

	_pause_window_mode_option = _add_pause_option(box, "Fenstermodus", SettingsManager.WINDOW_MODE_LABELS)
	# Läuft nach _on_pause_quick_settings_changed (Reihenfolge der Verbindungen), damit die Liste zum neuen Modus passt.
	_pause_window_mode_option.item_selected.connect(func(_i: int): _rebuild_pause_window_sizes())
	_pause_screen_option = _add_pause_option(box, "Monitor", SettingsManager.get_screen_labels())
	_pause_screen_option.item_selected.connect(func(_i: int): _rebuild_pause_window_sizes())
	_pause_window_size_option = _add_pause_option(box, "Auflösung", [])
	_pause_ui_scale_option = _add_pause_option(box, "UI-Skalierung", SettingsManager.UI_SCALE_LABELS)
	_pause_ui_scale_option.tooltip_text = tr("Automatisch: 100 % bis 1080p, 125 % bei 1440p, 200 % bei 4K.")
	_pause_language_option = _add_pause_option(box, "Sprache", SettingsManager.LANGUAGE_LABELS)

	_pause_autosave_check = CheckButton.new()
	_pause_autosave_check.text = "Auto-Save alle 3 Minuten (Host)"
	_pause_autosave_check.add_theme_font_size_override("font_size", 13)
	_pause_autosave_check.add_theme_color_override("font_color", Color(0.80, 0.81, 0.81))
	_pause_autosave_check.toggled.connect(func(_on: bool): _on_pause_quick_settings_changed())
	box.add_child(_pause_autosave_check)

	# --- Tastenbelegung (gleiche Logik wie im Hauptmenü) ---
	var kb_title := Label.new()
	kb_title.text = "Tastenbelegung (anklicken, dann neue Taste drücken)"
	kb_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(kb_title, 12, UIStyle.COL_TEXT_SUB)
	box.add_child(kb_title)

	_pause_keybind_buttons.clear()
	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)

		var lbl := Label.new()
		lbl.text = SettingsManager.get_action_label(action)
		lbl.custom_minimum_size = Vector2(170, 0)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIStyle.style_label(lbl, 13, Color(0.80, 0.81, 0.81))
		row.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIStyle.style_button(btn)
		var cap_action: String = action
		btn.pressed.connect(func() -> void: _start_pause_rebind(cap_action))
		row.add_child(btn)
		_pause_keybind_buttons[action] = btn

	_pause_keybind_hint = Label.new()
	_pause_keybind_hint.text = "ESC oder Mausklick bricht die Abfrage ab. Belegte Tasten werden getauscht."
	_pause_keybind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(_pause_keybind_hint, 12, UIStyle.COL_TEXT_SUB)
	box.add_child(_pause_keybind_hint)

	var reset_keys_btn := Button.new()
	reset_keys_btn.text = "Standardtasten wiederherstellen"
	reset_keys_btn.custom_minimum_size = Vector2(240, 32)
	reset_keys_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	UIStyle.style_button(reset_keys_btn)
	reset_keys_btn.pressed.connect(func() -> void:
		SfxManager.play("click", -10.0)
		_pause_rebind_action = ""
		SettingsManager.reset_key_bindings()
		_refresh_pause_keybind_buttons()
		_pause_keybind_hint.text = "Standardtasten wiederhergestellt."
	)
	box.add_child(reset_keys_btn)

	# Änderungen aus dem Hauptmenü oder durch Tauschen sofort übernehmen.
	SettingsManager.key_bindings_changed.connect(_refresh_pause_keybind_buttons)
	_refresh_pause_keybind_buttons()


## Überträgt SFX, Sichtfeld, Anzeige und Allgemeines aus dem Pausemenü in den SettingsManager.
func _apply_pause_general() -> void:
	if _pause_sfx_slider != null:
		SettingsManager.sfx_volume = _pause_sfx_slider.value / 100.0
	if _pause_fov_slider != null:
		SettingsManager.fov = _pause_fov_slider.value
	if _pause_window_mode_option != null:
		SettingsManager.window_mode = clampi(_pause_window_mode_option.selected, 0, SettingsManager.WINDOW_MODE_COUNT - 1)
	if _pause_screen_option != null:
		SettingsManager.screen_index = maxi(_pause_screen_option.selected - 1, -1)
	if _pause_window_size_option != null and _pause_window_size_option.selected >= 0 and _pause_window_size_option.selected < _pause_window_size_values.size():
		var picked: Vector2i = _pause_window_size_values[_pause_window_size_option.selected]
		if _pause_window_size_list_fullscreen:
			SettingsManager.fullscreen_resolution = picked
		else:
			SettingsManager.window_size = picked
	if _pause_ui_scale_option != null and _pause_ui_scale_option.selected >= 0 and _pause_ui_scale_option.selected < SettingsManager.UI_SCALE_VALUES.size():
		SettingsManager.ui_scale = SettingsManager.UI_SCALE_VALUES[_pause_ui_scale_option.selected]
	if _pause_language_option != null:
		var lang_idx := clampi(_pause_language_option.selected, 0, SettingsManager.LANGUAGE_CODES.size() - 1)
		SettingsManager.language = SettingsManager.LANGUAGE_CODES[lang_idx]
	if _pause_autosave_check != null:
		SettingsManager.autosave_enabled = _pause_autosave_check.button_pressed


## Setzt die neuen Pausemenü-Felder auf die aktuellen Werte, ohne Signale auszulösen.
func _sync_pause_general() -> void:
	if _pause_sfx_slider != null:
		_pause_sfx_slider.set_value_no_signal(SettingsManager.sfx_volume * 100.0)
		_update_slider_label(_pause_sfx_slider)
	if _pause_fov_slider != null:
		_pause_fov_slider.set_value_no_signal(SettingsManager.fov)
		_update_slider_label(_pause_fov_slider)
	if _pause_window_mode_option != null:
		_pause_window_mode_option.select(clampi(SettingsManager.window_mode, 0, _pause_window_mode_option.item_count - 1))
	if _pause_screen_option != null:
		# Monitore können seit dem Spielstart an- oder abgesteckt worden sein.
		_pause_screen_option.clear()
		var screen_labels := SettingsManager.get_screen_labels()
		for i in screen_labels.size():
			_pause_screen_option.add_item(tr(screen_labels[i]), i)
		if _pause_screen_option.item_count > 0:
			_pause_screen_option.select(clampi(SettingsManager.screen_index + 1, 0, _pause_screen_option.item_count - 1))
	if _pause_ui_scale_option != null:
		_pause_ui_scale_option.select(maxi(SettingsManager.UI_SCALE_VALUES.find(SettingsManager.ui_scale), 0))
	if _pause_language_option != null:
		_pause_language_option.select(maxi(SettingsManager.LANGUAGE_CODES.find(SettingsManager.language), 0))
	if _pause_autosave_check != null:
		_pause_autosave_check.set_pressed_no_signal(SettingsManager.autosave_enabled)
	_rebuild_pause_window_sizes()
	_pause_rebind_action = ""
	_refresh_pause_keybind_buttons()


## Baut die Auflösungsliste passend zu Fenstermodus und Monitor neu auf (gleiche Logik wie im Hauptmenü).
func _rebuild_pause_window_sizes() -> void:
	if _pause_window_size_option == null:
		return
	var screen := SettingsManager.screen_index
	if _pause_screen_option != null:
		screen = _pause_screen_option.selected - 1
	var mode := SettingsManager.window_mode
	if _pause_window_mode_option != null:
		mode = _pause_window_mode_option.selected
	_pause_window_size_list_fullscreen = mode != SettingsManager.WINDOW_WINDOWED

	var native: Vector2i = SettingsManager.get_screen_size(screen)
	var wanted: Vector2i = SettingsManager.window_size
	var values: Array[Vector2i] = []
	if _pause_window_size_list_fullscreen:
		values.append(Vector2i.ZERO)
		wanted = SettingsManager.fullscreen_resolution
		if wanted == native:
			wanted = Vector2i.ZERO
	values.append_array(SettingsManager.get_window_sizes(screen, _pause_window_size_list_fullscreen))
	# Eine gespeicherte Größe, die nicht in der Liste steht, bleibt wählbar. Sonst würde die nächste Änderung sie überschreiben.
	if not values.has(wanted):
		values.append(wanted)
	_pause_window_size_values = values

	_pause_window_size_option.clear()
	var current := 0
	for i in values.size():
		var s: Vector2i = values[i]
		if s == Vector2i.ZERO:
			_pause_window_size_option.add_item(tr("Nativ (%d × %d)") % [native.x, native.y], i)
		else:
			_pause_window_size_option.add_item("%d × %d" % [s.x, s.y], i)
		if s == wanted:
			current = i
	if _pause_window_size_option.item_count > 0:
		_pause_window_size_option.select(current)
	_pause_window_size_option.tooltip_text = tr("Im Vollbild wird das Bild in dieser Auflösung berechnet und auf den Monitor hochskaliert.") if _pause_window_size_list_fullscreen else ""


func _refresh_pause_keybind_buttons() -> void:
	for action in _pause_keybind_buttons.keys():
		var btn := _pause_keybind_buttons[action] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		if action == _pause_rebind_action:
			btn.text = "Taste drücken..."
		else:
			btn.text = SettingsManager.get_action_key_label(action)


func _start_pause_rebind(action: String) -> void:
	SfxManager.play("click", -10.0)
	_pause_rebind_action = action
	_refresh_pause_keybind_buttons()
	if _pause_keybind_hint != null:
		_pause_keybind_hint.text = tr("Neue Taste für „%s“ drücken (ESC bricht ab).") % SettingsManager.get_action_label(action)


func _cancel_pause_rebind() -> void:
	_pause_rebind_action = ""
	_refresh_pause_keybind_buttons()
	if _pause_keybind_hint != null:
		_pause_keybind_hint.text = "Abgebrochen, Belegung unverändert."


## Fängt während der Tastenabfrage alle Tasten ab. Das HUD liegt unter Main im Baum und bekommt
## _input deshalb vor main.gd. So schließt ESC hier nur die Abfrage und nicht das Pausemenü.
func _input(event: InputEvent) -> void:
	if _pause_rebind_action.is_empty():
		return
	if not is_visible_in_tree() or _pause_overlay == null or not _pause_overlay.visible:
		_cancel_pause_rebind()
		return
	if event is InputEventMouseButton and event.is_pressed():
		_cancel_pause_rebind()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var code := int(key.physical_keycode)
	if code == 0:
		code = int(key.keycode)
	if code == 0 or SettingsManager.RESERVED_KEYS.has(code):
		_cancel_pause_rebind()
		return
	var action := _pause_rebind_action
	_pause_rebind_action = ""
	var swapped := SettingsManager.set_key_binding(action, code)
	_refresh_pause_keybind_buttons()
	if _pause_keybind_hint != null:
		if swapped.is_empty():
			_pause_keybind_hint.text = tr("„%s“ liegt jetzt auf %s.") % [SettingsManager.get_action_label(action), SettingsManager.get_action_key_label(action)]
		else:
			_pause_keybind_hint.text = tr("„%s“ liegt jetzt auf %s. „%s“ hat die alte Taste bekommen.") % [SettingsManager.get_action_label(action), SettingsManager.get_action_key_label(action), swapped]


## Öffnet den Ordner mit den Godot-Logs (user://logs) im Datei-Explorer.
func _open_log_folder() -> void:
	var dir := ProjectSettings.globalize_path("user://logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var err := OS.shell_open(dir)
	if err != OK:
		push_warning("Log-Ordner konnte nicht geöffnet werden (%s): %s" % [error_string(err), dir])


func _add_pause_option(parent: VBoxContainer, label_txt: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr(label_txt)
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(lbl, 13, Color(0.80, 0.81, 0.81))
	row.add_child(lbl)

	var opt := OptionButton.new()
	for i in items.size():
		opt.add_item(tr(str(items[i])), i)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size = Vector2(0, 34)
	UIStyle.style_button(opt)
	opt.item_selected.connect(func(_idx: int): _on_pause_quick_settings_changed())
	row.add_child(opt)
	return opt


func _ping_color(ms: int) -> Color:
	if ms > 150:
		return Color(1.0, 0.42, 0.38)
	if ms > 80:
		return Color(0.95, 0.85, 0.35)
	return Color(0.45, 0.85, 0.50)


func _refresh_pause_players() -> void:
	if _pause_players_box == null:
		return
	for child in _pause_players_box.get_children():
		child.queue_free()
	_pause_ping_labels.clear()
	var is_host := NetworkManager.is_in_session and multiplayer.is_server()
	_pause_players_box.visible = is_host
	if not _pause_players_box.visible:
		return

	_add_reach_info(_pause_players_box)
	_pause_players_box.add_child(_section_label(tr("HOST-MODERATION & SCHUTZ")))

	var lock_check := CheckButton.new()
	lock_check.text = tr("Nur Host: Verkaufen, Kredite & Ausbau")
	lock_check.button_pressed = GameState.host_only_destructive
	lock_check.add_theme_font_size_override("font_size", 13)
	lock_check.add_theme_color_override("font_color", Color(0.86, 0.87, 0.88))
	lock_check.tooltip_text = tr("Verhindert, dass Mitspieler Racks/Geräte verkaufen, Kredite aufnehmen, Mitarbeiter entlassen oder Hallen ausbauen.")
	lock_check.toggled.connect(func(on: bool) -> void:
		GameState.set_host_only_destructive(on)
	)
	_pause_players_box.add_child(lock_check)

	for pid in NetworkManager.players.keys():
		var peer_id := int(pid)
		if peer_id == 1:
			continue
		var info: Dictionary = NetworkManager.players[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_pause_players_box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = str(info.get("name", tr("Spieler")))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UIStyle.style_label(name_lbl, 13, UIStyle.COL_TEXT_MAIN)
		row.add_child(name_lbl)

		var ping_lbl := Label.new()
		ping_lbl.custom_minimum_size = Vector2(56, 0)
		ping_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UIStyle.style_label(ping_lbl, 12, UIStyle.COL_TEXT_SUB)
		row.add_child(ping_lbl)
		_pause_ping_labels[peer_id] = ping_lbl

		# Baurecht nur in Welten ohne Passwort (sonst dürfen alle). Admins dürfen ohnehin.
		if not GameState.build_open and not AdminManager.is_admin(peer_id):
			var may := GameState.can_build(peer_id)
			var build_btn := Button.new()
			build_btn.text = tr("BAUT") if may else tr("BAUEN?")
			build_btn.tooltip_text = tr("Darf aufstellen, verkaufen, ausbauen und Kabel ziehen. Klicken nimmt das Recht weg.") if may else tr("Darf sich umsehen und helfen, aber noch nicht bauen. Klicken gibt das Baurecht.")
			build_btn.custom_minimum_size = Vector2(76, 30)
			UIStyle.style_button(build_btn, Color(0.08, 0.20, 0.12) if may else Color(0.14, 0.14, 0.16), UIStyle.COL_GREEN if may else UIStyle.COL_TEXT_SUB)
			build_btn.pressed.connect(func() -> void:
				GameState.set_build_right(peer_id, not may)
				_refresh_pause_players()
			)
			row.add_child(build_btn)

		var kick_btn := Button.new()
		kick_btn.text = "KICK"
		kick_btn.custom_minimum_size = Vector2(68, 30)
		UIStyle.style_button(kick_btn, Color(0.24, 0.16, 0.08), UIStyle.COL_AMBER)
		kick_btn.pressed.connect(func() -> void:
			kick_btn.disabled = true
			NetworkManager.kick_player(peer_id)
		)
		row.add_child(kick_btn)

		var ban_btn := Button.new()
		ban_btn.text = "BANN"
		ban_btn.custom_minimum_size = Vector2(68, 30)
		UIStyle.style_button(ban_btn, Color(0.28, 0.09, 0.09), UIStyle.COL_RED)
		ban_btn.pressed.connect(func() -> void:
			ban_btn.disabled = true
			kick_btn.disabled = true
			NetworkManager.ban_player(peer_id)
		)
		row.add_child(ban_btn)

	var ban_count := NetworkManager.get_ban_count()
	if ban_count > 0:
		var unban_btn := Button.new()
		unban_btn.text = tr("Banns zurücksetzen (%d)") % ban_count
		unban_btn.custom_minimum_size = Vector2(0, 30)
		UIStyle.style_button(unban_btn, Color(0.14, 0.17, 0.20), UIStyle.COL_BORDER)
		unban_btn.pressed.connect(func() -> void:
			NetworkManager.clear_bans()
			show_toast(tr("Sitzungs-Bannliste wurde geleert."), false)
		)
		_pause_players_box.add_child(unban_btn)
	_update_pause_pings()

func _update_pause_pings() -> void:
	for peer_id in _pause_ping_labels.keys():
		var lbl := _pause_ping_labels[peer_id] as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		var ms := NetworkManager.get_player_ping(int(peer_id))
		if ms < 0:
			lbl.text = "– ms"
			lbl.modulate = Color.WHITE
		else:
			lbl.text = "%d ms" % ms
			lbl.modulate = _ping_color(ms)


func _section_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	UIStyle.style_label(l, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	return l


func _make_mini_bar(col: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	var styles := UIStyle.make_bar_styles(col)
	bar.add_theme_stylebox_override("background", styles[0] as StyleBox)
	bar.add_theme_stylebox_override("fill", styles[1] as StyleBox)
	return bar


func _add_pause_slider(parent: VBoxContainer, label_txt: String, min_v: float, max_v: float, step_v: float, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr(label_txt)
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(lbl, 13, Color(0.80, 0.81, 0.81))
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_slider(sl)
	row.add_child(sl)

	var val := Label.new()
	val.custom_minimum_size = Vector2(50, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_label(val, 13, UIStyle.COL_GOLD_TEXT)
	row.add_child(val)

	sl.set_meta("val_lbl", val)
	sl.set_meta("fmt", fmt)
	sl.value_changed.connect(func(_v: float): _update_slider_label(sl))
	sl.value_changed.connect(_on_pause_quick_settings_changed)
	return sl


func _update_slider_label(sl: HSlider) -> void:
	if sl == null or not sl.has_meta("val_lbl"):
		return
	var val := sl.get_meta("val_lbl") as Label
	var fmt := str(sl.get_meta("fmt"))
	if fmt.contains("%d"):
		val.text = fmt % int(roundf(sl.value))
	else:
		val.text = fmt % sl.value
