class_name TerminalUI
extends Control
## v1.0 Streamlined Realistic Windows 11 Desktop OS Workstation (opened with [E] at PC Desk).
## Exactly 4 Clean Apps:
##   1. [🛒 Shop]     — CloudParts.de with Empty Chassis, 66 Filtered Parts (DDR2-DDR5), Real Shopping Cart & Teile-Lager
##   2. [🎧 Support]  — Tickets, Live VoIP Customer Calls, Rented Racks, Client Contracts & AI/DDoS Firewall
##   3. [🏗 Gebäude]  — 5-Tier Router (Mbit/Gbit), Power/Transformer, Hall B/C & kWh Meter
##   4. [📊 Monitor]  — Windows Task-Manager with 100% Real Hardware Metrics (GB RAM, TB, Mbit/s, Watts — Zero "CU")

signal close_requested
signal typing_state_changed(is_typing: bool)

var _monitor_frame: PanelContainer
var _app_window: PanelContainer
var _win_title_lbl: Label
var _win_subtitle_lbl: Label
var _app_body_host: VBoxContainer
var _start_menu: PanelContainer
var _call_popup: PanelContainer
var _call_body: VBoxContainer
var _taskbar_btns: Dictionary = {}
var _desktop_btns: Dictionary = {}

# System Tray labels
var _tray_money: Label
var _tray_power: Label
var _tray_temp: Label
var _tray_net: Label
var _tray_clock: Label
var _tray_power_icon: Control
var _tray_temp_icon: Control
var _tray_net_icon: Control
var _win_title_icon: Control

var _active_app: String = "" # "" | "shop" | "support" | "upgrades" | "monitor"
var _shop_tab: String = "chassis" # "chassis" | "infra" | "cpu" | "ram" | "gpu" | "storage" | "cooling" | "psu" | "warehouse"
var _shop_subfilter: String = "Alle"
var _support_tab: String = "tickets" # "tickets" | "contracts" | "ai"

# Real Shopping Cart: Array of {key, kind, id, cat, name, price, qty}
var _cart: Array = []

var _save_toast_text: String = ""
var _save_toast_timer: float = 0.0

# Realistic Mechanical Keyboard Typing Animation & Sound
var _typing_ticket_id: String = ""
var _typing_timer: float = 0.0
var _typing_key_accum: float = 0.0
var _manual_typing_pulse: float = 0.0
var _last_emitted_typing: bool = false
var _ticket_drafts: Dictionary = {}

# Letzte Rückmeldung der Finanz-Apps (Personal, Bank, Rechnungen)
var _fin_msg: String = ""
var _fin_msg_ok: bool = true

# Der PC bleibt an, bis jemand im Startmenü "Herunterfahren" wählt.
# Nur ein ausgeschalteter PC fährt beim Hinsetzen mit BIOS und Windows-Logo hoch.
var _boot_screen: PcBootScreen = null
var _boot_cold: bool = true
var _terminal_open: bool = false
var _shutting_down: bool = false
const TRAY_REFRESH_INTERVAL := 0.25
var _tray_accum: float = 0.0
const OPEN_FADE_TIME := 0.25
# Zeitpunkt, an dem der laufende Startvorgang begann (-1 = PC lief schon oder kein Start).
var _boot_started_msec: int = -1

const FINANCE_APPS: Array[String] = ["staff", "bank", "bills"]
const APP_ORDER: Array[String] = ["shop", "support", "upgrades", "monitor", "staff", "bank", "bills"]
const HISTORY_CHART := preload("res://scripts/ui/history_chart.gd")
const APP_META := {
	"shop": {"icon": "cart", "name": "Shop", "title": "CloudParts.de — Hardware-Shop, Warenkorb & Teile-Lager"},
	"support": {"icon": "headset", "name": "Support", "title": "ServiceDesk & Kunden-Hub — Tickets, Verträge & AI"},
	"upgrades": {"icon": "building", "name": "Gebäude", "title": "Router (Mbit/Gbit), Stromanschluss & Hallen-Ausbau"},
	"monitor": {"icon": "chart", "name": "Monitor", "title": "Windows Task-Manager — Live Rechenzentrum-Monitor"},
	"staff": {"icon": "people", "name": "Personal", "title": "Personalverwaltung — Team, Löhne & Bewerbungen"},
	"bank": {"icon": "bank", "name": "Bank", "title": "Hanse Direktbank — Geschäftskonto, Kredite & Kontoauszug"},
	"bills": {"icon": "invoice", "name": "Rechnungen", "title": "Rechnungen — Strom, Garagenmiete, Internet & Versicherung"},
}


## Dark Mode des PCs: eigene kleine Datei, damit die Spiel-Einstellungen unberührt bleiben.
const PC_DESKTOP_CFG := "user://pc_desktop.cfg"
## Kehrt die Helligkeit um und behält den Farbton. Weiße Flächen werden dunkelgrau, dunkle Schrift wird hell.
## Abgerundete Ecken werden ausgespart, damit am Rand kein Hintergrund mit umgefärbt wird.
const DARK_FILTER_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 rect_size = vec2(1.0, 1.0);
uniform float corner_radius = 0.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 half_size = rect_size * 0.5;
	float r = min(corner_radius, min(half_size.x, half_size.y));
	vec2 q = abs(p - half_size) - (half_size - vec2(r));
	if (length(max(q, vec2(0.0))) - r > 0.0) {
		discard;
	}
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(src, vec3(0.299, 0.587, 0.114));
	vec3 chroma = src - vec3(luma);
	float inv = mix(0.10, 0.93, 1.0 - luma);
	COLOR = vec4(clamp(vec3(inv) + chroma * 0.9, 0.0, 1.0), 1.0);
}
"""

var _dark_mode: bool = false
var _dark_toggle_btn: Button
var _taskbar_panel: Control
var _dark_targets: Array[Control] = []
var _dark_filters: Array[ColorRect] = []
var _price_overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_load_dark_mode()
	_build_ui()
	_build_dark_filter()
	GameState.state_updated.connect(_on_state_tick)
	GameState.room_level_changed.connect(_refresh_all)
	GameState.van_updated.connect(_refresh_all)
	GameState.racks_changed.connect(_refresh_all)
	GameState.inventory_changed.connect(_refresh_all)
	GameState.fuses_changed.connect(_refresh_all)
	GameState.accessories_changed.connect(_refresh_all)
	GameState.tickets_changed.connect(_refresh_all)
	GameState.call_changed.connect(_refresh_call_popup)
	FinanceManager.finance_changed.connect(_on_finance_changed)
	FinanceManager.action_result.connect(_on_finance_result)
	visibility_changed.connect(_on_visibility_changed)
	visibility_changed.connect(_close_price_overlay)


func _process(delta: float) -> void:
	if not visible:
		if _last_emitted_typing:
			_last_emitted_typing = false
			typing_state_changed.emit(false)
		return

	_update_dark_filter()

	if _save_toast_timer > 0.0:
		_save_toast_timer = maxf(0.0, _save_toast_timer - delta)
		if _save_toast_timer <= 0.0:
			_save_toast_text = ""

	if not _typing_ticket_id.is_empty():
		_typing_timer -= delta
		_typing_key_accum += delta
		if _typing_key_accum >= 0.075:
			_typing_key_accum = 0.0
			SfxManager.play_typing_key(-10.0)
		if _typing_timer <= 0.0:
			var done_tid := _typing_ticket_id
			_typing_ticket_id = ""
			_ticket_drafts.erase(done_tid)
			GameState.request_reply_ticket(done_tid, "reassure")
			_refresh_all()

	if _manual_typing_pulse > 0.0:
		_manual_typing_pulse = maxf(0.0, _manual_typing_pulse - delta)

	var typing_now := (not _typing_ticket_id.is_empty()) or (_manual_typing_pulse > 0.0)
	if typing_now != _last_emitted_typing:
		_last_emitted_typing = typing_now
		typing_state_changed.emit(typing_now)

	_tray_accum += delta
	if _tray_accum >= TRAY_REFRESH_INTERVAL:
		_tray_accum = 0.0
		_refresh_tray()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: Key = (event as InputEventKey).keycode
		if kc != KEY_ESCAPE and kc != KEY_SHIFT and kc != KEY_CTRL and kc != KEY_ALT:
			var focused := get_viewport().gui_get_focus_owner()
			if focused is LineEdit or focused is TextEdit:
				SfxManager.play_typing_key(-10.0)
				_manual_typing_pulse = 0.55


func _on_state_tick() -> void:
	if not visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if _active_app == "support" and (focused is LineEdit or not _typing_ticket_id.is_empty()):
		_refresh_tray()
		_refresh_taskbar_highlights()
		_refresh_call_popup()
		return
	if FINANCE_APPS.has(_active_app):
		# Finanz-Apps werden nur bei finance_changed neu aufgebaut, damit die Scrollposition bleibt.
		_refresh_tray()
		_refresh_taskbar_highlights()
		_refresh_call_popup()
		_refresh_window_subtitle()
		return
	if _active_app == "shop" or ["staff", "bank", "bills"].has(_active_app):
		# Shop und Finanz-Apps nicht jeden Tick neu aufbauen (Finanz-Apps aktualisiert finance_changed).
		_refresh_tray()
		_refresh_taskbar_highlights()
		_refresh_call_popup()
		_refresh_window_subtitle()
		return
	_refresh_all()


func open_terminal() -> void:
	GameState.request_mark_checklist_opened_pc()
	_start_menu.visible = false
	# Keine App automatisch öffnen: nach dem Hochfahren erscheint der Homescreen.
	# Läuft der PC schon, bleibt die zuletzt geöffnete App offen (power_on_pc übernimmt sie).
	# Die Kamera steht schon vor dem Monitor, deshalb nur kurz in das Vollbild überblenden.
	modulate.a = 0.0
	visible = true
	PcScreenState.local_fullscreen = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, OPEN_FADE_TIME)
	fade.tween_callback(_on_open_faded)
	_start_boot()
	_refresh_all()
	_refresh_call_popup()
	SfxManager.play("click", -8.0, 1.1)


func close_terminal() -> void:
	_start_menu.visible = false
	_typing_ticket_id = ""
	_manual_typing_pulse = 0.0
	if _last_emitted_typing:
		_last_emitted_typing = false
		typing_state_changed.emit(false)
	_terminal_open = false
	_boot_started_msec = -1
	_set_world_rendering(true)
	PcScreenState.local_fullscreen = false
	if _shutting_down:
		# Heruntergefahren: das Bild bleibt schwarz, bis das Vollbild zu ist. Danach ist der PC aus.
		_shutting_down = false
		_active_app = ""
		PcScreenState.report_local_closed()
	else:
		# Aufstehen: der PC läuft weiter, die Mitspieler sehen weiter den Desktop.
		if _boot_screen != null:
			_boot_screen.stop()
		PcScreenState.report_local_released()
	UIStyle.animate_popup_close(self, _monitor_frame)
	SfxManager.play("click", -8.0, 0.85)


func _start_boot() -> void:
	_terminal_open = true
	_shutting_down = false
	if _boot_screen == null:
		_boot_screen = PcBootScreen.new()
		add_child(_boot_screen)
		_boot_screen.finished.connect(_on_boot_finished)
		get_viewport().size_changed.connect(_fit_fullscreen)
	_fit_fullscreen()
	move_child(_boot_screen, get_child_count() - 1)
	var now := Time.get_ticks_msec()
	if _boot_started_msec < 0 and not is_pc_running():
		# Ohne Hinsetzen geöffnet (keine Spielfigur): ein ausgeschalteter PC fährt trotzdem hoch.
		_boot_cold = true
		_boot_started_msec = now
		_active_app = ""
		PcScreenState.report_local(PcScreenState.PHASE_BOOT, "", true, "")
	if _boot_started_msec >= 0:
		# Der Startvorgang lief schon auf dem 3D-Monitor, im Vollbild geht es an derselben Stelle weiter.
		var offset := float(now - _boot_started_msec) / 1000.0
		_boot_started_msec = -1
		_boot_screen.play(_boot_cold, PcScreenState.get_local_name(), offset)
	else:
		_boot_screen.stop()
	_report_screen_state()


## true, solange der PC an ist (er fährt hoch oder zeigt den Desktop).
func is_pc_running() -> bool:
	return PcScreenState.phase == PcScreenState.PHASE_BOOT or PcScreenState.phase == PcScreenState.PHASE_DESKTOP


## Beim Hinsetzen: ein ausgeschalteter PC fährt hoch, ein laufender zeigt sofort den Desktop.
func power_on_pc() -> void:
	var now := Time.get_ticks_msec()
	if PcScreenState.phase == PcScreenState.PHASE_DESKTOP:
		_boot_started_msec = -1
		_boot_cold = false
		_active_app = PcScreenState.app
		PcScreenState.report_local(PcScreenState.PHASE_DESKTOP, PcScreenState.app, false, PcScreenState.detail)
	elif PcScreenState.phase == PcScreenState.PHASE_BOOT:
		# Fährt noch hoch (z. B. aufgestanden, bevor Windows fertig war): an derselben Stelle weiter.
		_boot_cold = PcScreenState.cold_boot
		_boot_started_msec = now - int(PcScreenState.get_boot_elapsed() * 1000.0)
		_active_app = ""
		PcScreenState.report_local(PcScreenState.PHASE_BOOT, "", _boot_cold, "")
	else:
		# PC ist aus: echter Kaltstart, danach Homescreen ohne offene App.
		_boot_cold = true
		_boot_started_msec = now
		_active_app = ""
		PcScreenState.report_local(PcScreenState.PHASE_BOOT, "", true, "")
		SfxManager.play("click", -6.0, 0.6)


## Aufstehen, bevor das Vollbild offen war. Der PC fährt trotzdem fertig hoch und bleibt an.
func cancel_power_on() -> void:
	_boot_started_msec = -1
	PcScreenState.report_local_released()


## Startmenü "Herunterfahren": Windows fährt herunter, der Bildschirm wird schwarz, dann steht der Spieler auf.
func _shut_down_pc() -> void:
	if _shutting_down or not _terminal_open or _boot_screen == null:
		return
	_start_menu.visible = false
	_shutting_down = true
	_typing_ticket_id = ""
	move_child(_boot_screen, get_child_count() - 1)
	_boot_screen.play_shutdown()
	PcScreenState.report_local(PcScreenState.PHASE_SHUTDOWN, "", false, "")
	SfxManager.play("click", -8.0, 0.7)


## Sobald das Vollbild deckend ist, wird die 3D-Welt dahinter nicht mehr gerendert.
func _on_open_faded() -> void:
	if _terminal_open and visible:
		_set_world_rendering(false)


func _set_world_rendering(on: bool) -> void:
	var vp := get_viewport()
	if vp != null and vp.disable_3d == on:
		vp.disable_3d = not on


func _on_visibility_changed() -> void:
	if not visible:
		_set_world_rendering(true)
		PcScreenState.local_fullscreen = false


func _fit_fullscreen() -> void:
	if _monitor_frame != null:
		_monitor_frame.custom_minimum_size = get_viewport_rect().size


func _on_boot_finished() -> void:
	if _shutting_down:
		close_requested.emit()
		return
	_report_screen_state()


func _report_screen_state() -> void:
	if not _terminal_open or _shutting_down:
		return
	var booting := _boot_screen != null and _boot_screen.is_running()
	var detail := ""
	if _active_app == "shop":
		detail = _shop_tab
	elif _active_app == "support":
		detail = _support_tab
	var phase: String = PcScreenState.PHASE_BOOT if booting else PcScreenState.PHASE_DESKTOP
	PcScreenState.report_local(phase, _active_app, _boot_cold, detail)


func _open_app(app_id: String) -> void:
	var was_open := (_active_app == app_id)
	_active_app = app_id
	_start_menu.visible = false
	if was_open:
		SfxManager.play_typing_key(-12.0)
	else:
		SfxManager.play("win_open", -10.0)
	_manual_typing_pulse = 0.28
	_refresh_all()


func _minimize_app() -> void:
	_active_app = ""
	_start_menu.visible = false
	SfxManager.play("click", -10.0, 0.90)
	_refresh_all()


func _trigger_quick_save() -> void:
	_start_menu.visible = false
	if multiplayer.is_server():
		GameState.save_current_world("", false)
		_save_toast_text = tr("Gespeichert!")
		_save_toast_timer = 3.0
		SfxManager.play("cash", -10.0, 1.2)
	else:
		_save_toast_text = tr("Nur Host kann speichern")
		_save_toast_timer = 3.0
	_refresh_tray()


func _refresh_window_subtitle() -> void:
	if _win_subtitle_lbl == null:
		return
	var bw_warn := " LIMIT!" if GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps else ""
	_win_subtitle_lbl.text = tr("Guthaben: $%.0f   •   Strom: %d / %d W   •   Internet: %s / %s%s   •   Teile-Lager: %d   •   Tickets: %d") % [
		GameState.money, GameState.total_watts, GameState.max_watts,
		HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps),
		HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps),
		bw_warn, GameState.get_total_inventory_parts(), GameState.get_open_ticket_count()
	]


func _on_finance_changed() -> void:
	if visible and FINANCE_APPS.has(_active_app):
		_refresh_all()


func _on_finance_result(ok: bool, message: String) -> void:
	_fin_msg = message
	_fin_msg_ok = ok
	if not ok:
		SfxManager.play("win_error", -8.0)
	if visible and FINANCE_APPS.has(_active_app):
		_refresh_all()


func _refresh_all() -> void:
	if not visible:
		return
	_report_screen_state()
	_refresh_tray()
	_refresh_taskbar_highlights()
	_refresh_call_popup()

	if _active_app.is_empty() or not APP_META.has(_active_app):
		_app_window.visible = false
		return

	_app_window.visible = true
	var meta: Dictionary = APP_META[_active_app]
	_win_title_lbl.text = tr(str(meta["title"]))
	_set_win_icon_kind(_win_title_icon, str(meta["icon"]))
	_refresh_window_subtitle()

	_clear_children(_app_body_host)
	match _active_app:
		"shop":
			_render_shop_app()
		"support":
			_render_support_hub_app()
		"upgrades":
			_render_upgrades_app()
		"monitor":
			_render_monitor_app()
		"staff":
			FinanceApps.render_staff(_app_body_host, _fin_msg, _fin_msg_ok)
		"bank":
			FinanceApps.render_bank(_app_body_host, _fin_msg, _fin_msg_ok)
		"bills":
			FinanceApps.render_bills(_app_body_host, _fin_msg, _fin_msg_ok)


func _refresh_tray() -> void:
	if _tray_money == null:
		return
	if not _save_toast_text.is_empty():
		_tray_money.text = _save_toast_text
		_tray_money.modulate = Color(0.14, 0.58, 0.30)
	else:
		_tray_money.text = "$%.0f" % GameState.money
		_tray_money.modulate = Color(0.10, 0.45, 0.24)

	var ups_txt := (" " + tr("(USV %.0f%%)") % GameState.avg_ups_charge) if not GameState.ups_units.is_empty() else ""
	_tray_power.text = "%d/%dW%s" % [GameState.total_watts, GameState.max_watts, ups_txt]
	_tray_power.modulate = Color(0.78, 0.16, 0.14) if GameState.total_watts > GameState.max_watts else Color(0.18, 0.20, 0.24)
	_tray_power_icon.modulate = _tray_power.modulate

	_tray_temp.text = "%.0f°C" % GameState.room_temp
	_tray_temp.modulate = Color(0.78, 0.22, 0.12) if GameState.room_temp >= 68.0 else Color(0.18, 0.20, 0.24)
	_tray_temp_icon.modulate = _tray_temp.modulate

	var spd_str := HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
	var is_throttled := GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps
	if GameState.ddos_active:
		_tray_net.text = "DDoS!"
		_tray_net.modulate = Color(0.80, 0.16, 0.14)
	elif is_throttled:
		_tray_net.text = tr("%s LIMIT!") % spd_str
		_tray_net.modulate = Color(0.76, 0.42, 0.06)
	else:
		_tray_net.text = spd_str
		_tray_net.modulate = Color(0.12, 0.42, 0.66)
	_set_win_icon_kind(_tray_net_icon, "warn" if GameState.ddos_active or is_throttled else "net")
	_tray_net_icon.modulate = _tray_net.modulate

	var today := Time.get_date_dict_from_system()
	_tray_clock.text = "%s\n%02d.%02d.%d" % [
		PcBootScreen.format_real_clock(), int(today["day"]), int(today["month"]), int(today["year"])
	]
	_tray_clock.tooltip_text = tr("Spieltag %d") % GameState.day_number


func _refresh_taskbar_highlights() -> void:
	var open_t := GameState.get_open_ticket_count()
	var has_call := not GameState.active_call.is_empty()
	var cart_n := _get_cart_item_count()
	for app_id in _taskbar_btns.keys():
		var aid := str(app_id)
		var btn: Button = _taskbar_btns[aid]
		var meta: Dictionary = APP_META[aid]
		var is_open := (aid == _active_app)
		var app_name := str(meta["name"])
		_set_win_icon_kind(_btn_icon(btn), "phone" if aid == "support" and has_call else str(meta["icon"]))
		# Windows 11: nur Symbole. Zähler stehen als kleines Abzeichen neben dem Symbol.
		if aid == "support" and (open_t > 0 or has_call):
			btn.text = str(open_t)
			btn.tooltip_text = tr("%s: %d offene Tickets%s") % [app_name, open_t, (" · " + tr("eingehender Anruf")) if has_call else ""]
			_style_taskbar_btn(btn, is_open, true)
		elif aid == "shop" and cart_n > 0:
			btn.text = str(cart_n)
			btn.tooltip_text = tr("%s: %d Artikel im Warenkorb") % [app_name, cart_n]
			_style_taskbar_btn(btn, is_open, false)
		else:
			btn.text = ""
			btn.tooltip_text = app_name
			_style_taskbar_btn(btn, is_open, false)

	if _desktop_btns.has("support"):
		var dbtn: Button = _desktop_btns["support"]
		_set_win_icon_kind(_btn_icon(dbtn), "phone" if has_call else "headset")
		if open_t > 0 or has_call:
			dbtn.text = tr("Support (%d)") % open_t
			_style_win_btn(dbtn, Color(0.62, 0.16, 0.14, 0.88), Color(0.95, 0.42, 0.36, 0.82), Color.WHITE)
		else:
			dbtn.text = "Support"
			_style_win_btn(dbtn, Color(0.12, 0.22, 0.34, 0.58), Color(0.45, 0.62, 0.80, 0.30), Color(0.96, 0.98, 1.0))


func _refresh_call_popup() -> void:
	if _call_popup == null:
		return
	var call_d := GameState.active_call
	if call_d.is_empty():
		_call_popup.visible = false
		return
	_call_popup.visible = true
	_clear_children(_call_body)

	var is_ringing := str(call_d.get("state", "ringing")) == "ringing"
	var hdr_col := Color(0.78, 0.16, 0.12) if is_ringing else Color(0.10, 0.50, 0.26)
	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 8)
	_call_body.add_child(hdr_row)
	var hdr_icon := _win_icon("phone", 16)
	hdr_icon.modulate = hdr_col
	hdr_row.add_child(hdr_icon)
	var hdr := Label.new()
	hdr.text = tr("EINGEHENDER KUNDENANRUF!") if is_ringing else tr("AKTIVES TELEFONAT — VOIP")
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.modulate = hdr_col
	hdr_row.add_child(hdr)

	var who := Label.new()
	who.text = "%s  (%s)" % [str(call_d.get("customer", "Kunde")), str(call_d.get("rack_id", "")).to_upper()]
	who.add_theme_font_size_override("font_size", 13)
	who.modulate = Color(0.10, 0.14, 0.20)
	_call_body.add_child(who)

	if is_ringing:
		var ring_lbl := Label.new()
		ring_lbl.text = "Kunde ruft wegen einer Störung an! Annehmen, um Zufriedenheit zu schützen."
		ring_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ring_lbl.add_theme_font_size_override("font_size", 12)
		ring_lbl.modulate = Color(0.30, 0.34, 0.40)
		_call_body.add_child(ring_lbl)

		var ans_btn := Button.new()
		ans_btn.text = "Anruf annehmen"
		ans_btn.custom_minimum_size = Vector2(0, 36)
		_add_btn_icon(ans_btn, "phone", 16)
		_style_win_btn(ans_btn, Color(0.12, 0.58, 0.30), Color(0.08, 0.44, 0.22), Color.WHITE)
		ans_btn.pressed.connect(func(): GameState.request_answer_call())
		_call_body.add_child(ans_btn)
	else:
		var msg_card := _make_light_card(Color(0.95, 0.97, 1.0), Color(0.76, 0.84, 0.92), 6, 10, 8)
		_call_body.add_child(msg_card)
		var ml := Label.new()
		ml.text = GameState.format_message(str(call_d.get("message", "")), call_d.get("message_args", []))
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.add_theme_font_size_override("font_size", 12)
		ml.modulate = Color(0.12, 0.16, 0.22)
		msg_card.add_child(ml)

		var b1 := Button.new()
		b1.text = "Sofort-Upgrade zusagen (+60s Zeit)"
		b1.custom_minimum_size = Vector2(0, 32)
		_style_win_btn(b1, Color(0.10, 0.48, 0.84), Color(0.08, 0.38, 0.70), Color.WHITE)
		b1.pressed.connect(func():
			SfxManager.play_typing_key(-10.0)
			GameState.request_resolve_call("upgrade_promise")
		)
		_call_body.add_child(b1)

		var b2 := Button.new()
		b2.text = tr("Neustart & $60 Gutschrift (+26%)")
		b2.custom_minimum_size = Vector2(0, 32)
		b2.disabled = GameState.money < 60.0
		_style_win_btn(b2, Color(0.14, 0.56, 0.32), Color(0.10, 0.44, 0.24), Color.WHITE)
		b2.pressed.connect(func():
			SfxManager.play_typing_key(-10.0)
			GameState.request_resolve_call("restart_compensate")
		)
		_call_body.add_child(b2)

		var b3 := Button.new()
		b3.text = "Auflegen (kümmern uns gleich)"
		b3.custom_minimum_size = Vector2(0, 28)
		_style_win_btn(b3, Color(0.88, 0.90, 0.93), Color(0.74, 0.78, 0.82), Color(0.18, 0.20, 0.24))
		b3.pressed.connect(func(): GameState.request_resolve_call("later"))
		_call_body.add_child(b3)


# ==============================================================================
# SHOPPING CART HELPERS
# ==============================================================================
func _cart_add(kind: String, id: String, cat: String, display_name: String, price: int) -> void:
	var key := "%s:%s" % [kind, id]
	for item in _cart:
		var d: Dictionary = item
		if str(d["key"]) == key:
			d["qty"] = mini(20, int(d["qty"]) + 1)
			SfxManager.play_typing_key(-11.0)
			_manual_typing_pulse = 0.25
			_refresh_all()
			return
	_cart.append({"key": key, "kind": kind, "id": id, "cat": cat, "name": display_name, "price": price, "qty": 1})
	SfxManager.play_typing_key(-11.0)
	_manual_typing_pulse = 0.25
	_refresh_all()


func _cart_delta(key: String, delta_n: int) -> void:
	for i in range(_cart.size()):
		var d: Dictionary = _cart[i]
		if str(d["key"]) == key:
			var nq := int(d["qty"]) + delta_n
			if nq <= 0:
				_cart.remove_at(i)
			else:
				d["qty"] = mini(20, nq)
			SfxManager.play("click", -12.0, 0.95)
			_refresh_all()
			return


func _get_cart_total() -> int:
	var sum := 0
	for item in _cart:
		var d: Dictionary = item
		sum += int(d["price"]) * int(d["qty"])
	return sum


func _get_cart_item_count() -> int:
	var n := 0
	for item in _cart:
		n += int((item as Dictionary)["qty"])
	return n


func _checkout_cart() -> void:
	if _cart.is_empty():
		return
	var total := _get_cart_total()
	if GameState.money < float(total):
		SfxManager.play("error", -8.0)
		return
	var payload: Array = []
	for item in _cart:
		var d: Dictionary = item
		payload.append({"kind": str(d["kind"]), "id": str(d["id"]), "cat": str(d["cat"]), "qty": int(d["qty"])})
	_cart.clear()
	SfxManager.play_typing_key(-9.0)
	GameState.request_checkout_cart(payload)
	_refresh_all()


# ==============================================================================
# APP 1: HARDWARE SHOP (CLOUDPARTS.DE) + REAL SHOPPING CART + TEILE-LAGER!
# ==============================================================================
## Sicherungen werden ohne Lieferung direkt ins Lager gebucht und am Sicherungskasten eingesetzt.
func _add_fuse_shop_card(list: VBoxContainer) -> void:
	_add_shop_item_card(list, {
		"title": tr("Schraubsicherung 63 A (Sicherungskasten)"),
		"desc": tr("Kommt sofort ins Lager, ohne Lieferung. Am Sicherungskasten mit [E] in einen leeren oder durchgebrannten Steckplatz stecken."),
		"info": tr("Im Lager: %d  •  Intakt im Kasten: %d / %d") % [GameState.fuse_stock, GameState.count_working_fuses(), GameState.FUSE_SLOT_COUNT],
		"color": Color(0.86, 0.70, 0.36),
		"price": GameState.FUSE_PRICE,
		"instant": true,
		"on_buy": func(): GameState.request_buy_fuse(),
	})


## Steckleisten (Stromkasten) und Netzwerk-Verteiler (Router): werden sofort montiert, ohne Lieferung.
func _add_power_strip_card(list: VBoxContainer) -> void:
	var breaker_cap := GameState.BREAKER_BASE_SOCKETS + GameState.power_strips * GameState.POWER_STRIP_EXTRA
	var at_max := GameState.power_strips >= GameState.POWER_STRIP_MAX
	_add_shop_item_card(list, {
		"title": tr("Steckleiste 4-fach (Stromkasten)"),
		"desc": tr("Wird sofort am Stromkasten montiert. Belegt eine Steckdose und bringt +%d Steckplätze.") % GameState.POWER_STRIP_EXTRA,
		"info": tr("Steckplätze am Kasten: %d  •  Montiert: %d / %d") % [breaker_cap, GameState.power_strips, GameState.POWER_STRIP_MAX],
		"color": Color(0.84, 0.66, 0.14),
		"price": GameState.POWER_STRIP_PRICE,
		"instant": true,
		"disabled": at_max,
		"btn_text": tr("Maximum erreicht") if at_max else "",
		"on_buy": func(): GameState.request_buy_power_strip(),
	})


func _add_net_hub_card(list: VBoxContainer) -> void:
	var router_cap := GameState.ROUTER_BASE_PORTS + GameState.net_hubs * GameState.NET_HUB_EXTRA
	var at_max := GameState.net_hubs >= GameState.NET_HUB_MAX
	_add_shop_item_card(list, {
		"title": tr("Netzwerk-Verteiler 4-Port (Router)"),
		"desc": tr("Wird sofort am Router montiert. Belegt einen Port und bringt +%d Netzwerkdosen.") % GameState.NET_HUB_EXTRA,
		"info": tr("Ports am Router: %d  •  Montiert: %d / %d") % [router_cap, GameState.net_hubs, GameState.NET_HUB_MAX],
		"color": Color(0.16, 0.40, 0.68),
		"price": GameState.NET_HUB_PRICE,
		"instant": true,
		"disabled": at_max,
		"btn_text": tr("Maximum erreicht") if at_max else "",
		"on_buy": func(): GameState.request_buy_net_hub(),
	})


## Steckleisten und Netzwerk-Verteiler werden sofort montiert, ohne Lieferung.
func _add_accessory_shop_cards(list: VBoxContainer) -> void:
	_add_power_strip_card(list)
	_add_net_hub_card(list)


## Abschnittsüberschrift im Shop, gruppiert die Karten nach Kategorie.
func _add_shop_section(list: VBoxContainer, heading: String, hint: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	list.add_child(box)
	if list.get_child_count() > 1:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		box.add_child(gap)

	var h := Label.new()
	h.text = heading.to_upper()
	h.add_theme_font_size_override("font_size", 12)
	h.modulate = Color(0.10, 0.24, 0.44)
	box.add_child(h)

	if hint != "":
		var s := Label.new()
		s.text = hint
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_font_size_override("font_size", 11)
		s.modulate = Color(0.42, 0.46, 0.54)
		box.add_child(s)

	box.add_child(HSeparator.new())


## Einheitliche Karte für alle bestellbaren Artikel.
## opts: title, desc, info, color, price, instant (sofort gebucht statt Warenkorb), disabled, btn_text, on_buy
func _add_shop_item_card(list: VBoxContainer, opts: Dictionary) -> void:
	var instant := bool(opts.get("instant", false))
	var price := int(opts.get("price", 0))
	var accent: Color = opts.get("color", Color(0.46, 0.50, 0.56))
	var is_disabled := bool(opts.get("disabled", false)) or (instant and GameState.money < float(price))

	var card := _make_light_card(Color.WHITE, Color(0.82, 0.85, 0.89), 6, 12, 9)
	list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(6, 44)
	swatch.color = accent
	row.add_child(swatch)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 3)
	row.add_child(info_box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info_box.add_child(head)

	var title_lbl := Label.new()
	title_lbl.text = str(opts.get("title", ""))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.tooltip_text = title_lbl.text
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.modulate = Color(0.10, 0.12, 0.16)
	head.add_child(title_lbl)

	var badge := _make_light_card(
		Color(0.90, 0.97, 0.91) if instant else Color(0.92, 0.95, 1.0),
		Color(0.52, 0.78, 0.58) if instant else Color(0.62, 0.74, 0.90),
		4, 6, 1)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var badge_lbl := Label.new()
	var badge_txt := str(opts.get("badge", ""))
	if badge_txt == "":
		badge_txt = tr("Sofort verfügbar") if instant else tr("Lieferung per Sprinter")
	badge_lbl.text = badge_txt
	badge_lbl.add_theme_font_size_override("font_size", 10)
	badge_lbl.modulate = Color(0.14, 0.44, 0.22) if instant else Color(0.12, 0.32, 0.58)
	badge.add_child(badge_lbl)

	var desc := str(opts.get("desc", ""))
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.modulate = Color(0.36, 0.40, 0.46)
		info_box.add_child(desc_lbl)

	var extra := str(opts.get("info", ""))
	if extra != "":
		var extra_lbl := Label.new()
		extra_lbl.text = extra
		extra_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		extra_lbl.add_theme_font_size_override("font_size", 11)
		extra_lbl.modulate = Color(0.20, 0.36, 0.56)
		info_box.add_child(extra_lbl)

	# Optional: Leistungsbalken mit Kurz-Specs (Einzelteile)
	if opts.has("strength_pct"):
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 8)
		info_box.add_child(bar_row)
		var pb := ProgressBar.new()
		pb.min_value = 0.0
		pb.max_value = 100.0
		pb.value = clampf(float(opts.get("strength_pct", 0.0)), 0.0, 100.0)
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(90, 7)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.88, 0.90, 0.93)
		bg_sb.set_corner_radius_all(3)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = accent
		fill_sb.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("background", bg_sb)
		pb.add_theme_stylebox_override("fill", fill_sb)
		bar_row.add_child(pb)
		var specs := str(opts.get("specs", ""))
		if specs != "":
			var specs_lbl := Label.new()
			specs_lbl.text = specs
			specs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			specs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			specs_lbl.add_theme_font_size_override("font_size", 11)
			specs_lbl.modulate = Color(0.36, 0.40, 0.48)
			bar_row.add_child(specs_lbl)

	var buy_col := VBoxContainer.new()
	buy_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_col.add_theme_constant_override("separation", 4)
	row.add_child(buy_col)

	var price_lbl := Label.new()
	var has_price_text := opts.has("price_text")
	price_lbl.text = str(opts.get("price_text", "$%d" % price))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.add_theme_font_size_override("font_size", 16)
	if has_price_text:
		price_lbl.modulate = Color(0.10, 0.44, 0.24)
	else:
		price_lbl.modulate = Color(0.10, 0.44, 0.24) if GameState.money >= float(price) else Color(0.78, 0.16, 0.14)
	buy_col.add_child(price_lbl)

	var btn_text := str(opts.get("btn_text", ""))
	if btn_text == "":
		btn_text = tr("Sofort kaufen") if instant else tr("+ Warenkorb")
	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(140, 32)
	btn.disabled = is_disabled
	if str(opts.get("btn_style", "")) == "danger":
		_style_win_btn(btn, Color(0.82, 0.24, 0.20), Color(0.66, 0.16, 0.14), Color.WHITE)
	else:
		_style_win_btn(btn, Color(0.10, 0.48, 0.84), Color(0.08, 0.38, 0.70), Color.WHITE)
	var on_buy: Callable = opts.get("on_buy", Callable())
	btn.pressed.connect(func():
		if instant:
			SfxManager.play("click", -12.0, 1.1)
		if on_buy.is_valid():
			on_buy.call()
	)
	buy_col.add_child(btn)


func _render_shop_app() -> void:
	# Clean Browser Navigation + Category Ribbon
	var nav_bar := _make_light_card(Color(0.95, 0.96, 0.98), Color(0.80, 0.83, 0.87), 6, 10, 6)
	_app_body_host.add_child(nav_bar)
	var nav_v := VBoxContainer.new()
	nav_v.add_theme_constant_override("separation", 6)
	nav_bar.add_child(nav_v)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 5)
	nav_v.add_child(tab_row)

	var tabs: Array = [
		{"id": "chassis", "label": "Racks & Chassis"},
		{"id": "infra", "label": "Klima & USV"},
		{"id": "warehouse", "label": tr("Lager (%d)") % GameState.get_total_inventory_parts()},
	]
	for t in tabs:
		var td: Dictionary = t
		var tid := str(td["id"])
		var tb := Button.new()
		tb.text = tr(str(td["label"]))
		tb.custom_minimum_size = Vector2(0, 28)
		tb.add_theme_font_size_override("font_size", 11)
		var sel := (_shop_tab == tid)
		_style_win_btn(
			tb,
			Color(0.10, 0.46, 0.82) if sel else Color(0.90, 0.92, 0.95),
			Color(0.08, 0.36, 0.68) if sel else Color(0.76, 0.80, 0.85),
			Color.WHITE if sel else Color(0.16, 0.18, 0.22)
		)
		tb.pressed.connect(func():
			_shop_tab = tid
			_shop_subfilter = "Alle"
			SfxManager.play("click", -12.0, 1.1)
			_refresh_all()
		)
		tab_row.add_child(tb)

	# Sub-Generation Filter Row for Hardware Part Tabs (e.g. DDR2 | DDR3 | DDR4 | DDR5!)
	if HardwareCatalog.CATEGORY_FILTERS.has(_shop_tab):
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 6)
		nav_v.add_child(frow)
		var flbl := Label.new()
		flbl.text = tr("Filter:")
		flbl.add_theme_font_size_override("font_size", 11.5)
		flbl.modulate = Color(0.32, 0.36, 0.44)
		frow.add_child(flbl)
		for f in HardwareCatalog.CATEGORY_FILTERS[_shop_tab]:
			var fn := str(f)
			var fb := Button.new()
			fb.text = tr(fn)
			fb.custom_minimum_size = Vector2(0, 24)
			fb.add_theme_font_size_override("font_size", 11)
			var fsel := (_shop_subfilter == fn)
			_style_win_btn(
				fb,
				Color(0.16, 0.52, 0.32) if fsel else Color(0.92, 0.94, 0.96),
				Color(0.12, 0.40, 0.24) if fsel else Color(0.78, 0.81, 0.86),
				Color.WHITE if fsel else Color(0.20, 0.24, 0.30)
			)
			fb.pressed.connect(func():
				_shop_subfilter = fn
				SfxManager.play("click", -13.0, 1.1)
				_refresh_all()
			)
			frow.add_child(fb)

	# MAIN SPLIT: Left Catalog List (~68%) + Right Live Shopping Cart (~32%)!
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	_app_body_host.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_scroll)

	var left_list := VBoxContainer.new()
	left_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_list.add_theme_constant_override("separation", 7)
	left_scroll.add_child(left_list)

	if GameState.racks.is_empty() and _shop_tab == "chassis":
		var tip := _make_light_card(Color(0.93, 0.98, 0.92), Color(0.36, 0.72, 0.44), 6, 12, 8)
		left_list.add_child(tip)
		var tl := Label.new()
		tl.text = "START-TIPP: Lege 1× Server-Rack (4U) in den Warenkorb → Bestellen → der Cloud Express Sprinter liefert es. Am Rack drückst du [E], klickst einen freien Einschub an und wählst mit der Maus dein Mainboard. CPU, RAM, GPU, SSD & Co. kaufst du danach direkt im Einschub."
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.add_theme_font_size_override("font_size", 11.5)
		tl.modulate = Color(0.12, 0.38, 0.18)
		tip.add_child(tl)

	if _shop_tab == "chassis":
		_add_shop_section(left_list, tr("Server-Racks"), tr("Gehäuse für deine Einschübe. Lieferung per Sprinter."))
		_populate_physical_shop_list(left_list, ["rack", "rack_pro"])
		_add_shop_section(left_list, tr("Netzwerk"), tr("Switches für mehr Netzwerk-Ports im Rack."))
		_populate_physical_shop_list(left_list, ["net_switch"])
	elif _shop_tab == "infra":
		_add_shop_section(left_list, tr("Kühlung"), tr("Hält die Raumtemperatur unter Kontrolle."))
		_populate_physical_shop_list(left_list, ["cooler", "chiller"])
		_add_shop_section(left_list, tr("Stromversorgung"), tr("Notstrom, Sicherungen und zusätzliche Steckplätze am Stromkasten."))
		_populate_physical_shop_list(left_list, ["ups"])
		_add_power_strip_card(left_list)
		_add_fuse_shop_card(left_list)
		_add_shop_section(left_list, tr("Netzwerk-Zubehör"), tr("Mehr Netzwerkdosen am Router."))
		_add_net_hub_card(left_list)
		_add_shop_section(left_list, tr("Transport"), tr("Hilfsmittel zum Bewegen von Hardware."))
		_populate_physical_shop_list(left_list, ["cart"])
	elif _shop_tab == "warehouse":
		_populate_warehouse_list(left_list)
	elif HardwareCatalog.PARTS.has(_shop_tab):
		_populate_parts_shop_list(left_list, _shop_tab)

	# RIGHT: REAL SHOPPING CART PANEL (Warenkorb)
	var cart_panel := _make_light_card(Color(0.97, 0.98, 0.99), Color(0.74, 0.80, 0.88), 8, 12, 10)
	cart_panel.custom_minimum_size = Vector2(276, 0)
	cart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(cart_panel)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cart_panel.add_child(cv)

	var chdr := Label.new()
	chdr.text = tr("WARENKORB (%d)") % _get_cart_item_count()
	chdr.add_theme_font_size_override("font_size", 14)
	chdr.modulate = Color(0.10, 0.24, 0.44)
	cv.add_child(chdr)

	var cscroll := ScrollContainer.new()
	cscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(cscroll)
	var clist := VBoxContainer.new()
	clist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clist.add_theme_constant_override("separation", 5)
	cscroll.add_child(clist)

	if _cart.is_empty():
		var ce := Label.new()
		ce.text = tr("Dein Warenkorb ist leer.") + "\n\n" + tr("Sammle links Racks, Server-Chassis und Einzelteile (CPUs, DDR2–DDR5 RAM, GPUs…) und bestelle alles gemeinsam per Sprinter!")
		ce.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ce.add_theme_font_size_override("font_size", 11.5)
		ce.modulate = Color(0.42, 0.46, 0.54)
		clist.add_child(ce)
	else:
		for item in _cart:
			var d: Dictionary = item
			var row_c := _make_light_card(Color.WHITE, Color(0.84, 0.87, 0.91), 5, 8, 5)
			clist.add_child(row_c)
			var rv := VBoxContainer.new()
			rv.add_theme_constant_override("separation", 3)
			row_c.add_child(rv)
			var nl := Label.new()
			nl.text = tr(str(d["name"]))
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.add_theme_font_size_override("font_size", 11.5)
			nl.modulate = Color(0.12, 0.14, 0.18)
			rv.add_child(nl)

			var brow := HBoxContainer.new()
			brow.add_theme_constant_override("separation", 4)
			rv.add_child(brow)
			var pl := Label.new()
			pl.text = "%d×  •  $%d" % [int(d["qty"]), int(d["price"]) * int(d["qty"])]
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pl.add_theme_font_size_override("font_size", 11)
			pl.modulate = Color(0.16, 0.46, 0.26)
			brow.add_child(pl)

			var cap_k := str(d["key"])
			var bm := Button.new()
			bm.text = "−"
			bm.custom_minimum_size = Vector2(24, 22)
			_style_win_btn(bm, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.84), Color(0.20, 0.22, 0.26))
			bm.pressed.connect(func(): _cart_delta(cap_k, -1))
			brow.add_child(bm)

			var bp := Button.new()
			bp.text = "+"
			bp.custom_minimum_size = Vector2(24, 22)
			_style_win_btn(bp, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.84), Color(0.20, 0.22, 0.26))
			bp.pressed.connect(func(): _cart_delta(cap_k, 1))
			brow.add_child(bp)

	cv.add_child(HSeparator.new())
	var tot := _get_cart_total()
	var tot_lbl := Label.new()
	tot_lbl.text = tr("Gesamtsumme:  $%d") % tot
	tot_lbl.add_theme_font_size_override("font_size", 14)
	tot_lbl.modulate = Color(0.78, 0.16, 0.14) if GameState.money < float(tot) else Color(0.10, 0.44, 0.24)
	cv.add_child(tot_lbl)

	var order_btn := Button.new()
	order_btn.text = (" " + tr("Alles bestellen ($%d)") % tot) if not _cart.is_empty() else tr("Warenkorb leer")
	order_btn.custom_minimum_size = Vector2(0, 40)
	order_btn.disabled = _cart.is_empty() or GameState.money < float(tot)
	_style_win_btn(
		order_btn,
		Color(0.10, 0.48, 0.84) if not order_btn.disabled else Color(0.84, 0.86, 0.89),
		Color(0.08, 0.38, 0.70),
		Color.WHITE if not order_btn.disabled else Color(0.45, 0.48, 0.52)
	)
	order_btn.pressed.connect(_checkout_cart)
	cv.add_child(order_btn)

	if not _cart.is_empty():
		var clr_btn := Button.new()
		clr_btn.text = "Warenkorb leeren"
		clr_btn.custom_minimum_size = Vector2(0, 26)
		clr_btn.add_theme_font_size_override("font_size", 11)
		_style_win_btn(clr_btn, Color(0.92, 0.93, 0.95), Color(0.78, 0.81, 0.86), Color(0.26, 0.28, 0.34))
		clr_btn.pressed.connect(func():
			_cart.clear()
			_refresh_all()
		)
		cv.add_child(clr_btn)


func _populate_physical_shop_list(parent: VBoxContainer, keys: Array) -> void:
	for item_type in keys:
		var cap_it := str(item_type)
		if not GameState.ITEM_CATALOG.has(cap_it):
			continue
		var cat: Dictionary = GameState.ITEM_CATALOG[cap_it]
		var cap_n := str(cat["name"])
		var cap_p := int(cat["price"])
		_add_shop_item_card(parent, {
			"title": tr(cap_n),
			"desc": tr(str(cat.get("desc", ""))),
			"color": cat.get("color", Color(0.46, 0.50, 0.56)),
			"price": cap_p,
			"on_buy": func(): _cart_add("item", cap_it, "", cap_n, cap_p),
		})


func _populate_parts_shop_list(parent: VBoxContainer, cat: String) -> void:
	for p in HardwareCatalog.get_category_parts(cat):
		var pd: Dictionary = p
		var cost := int(pd["cost"])
		if cost <= 0:
			continue # Zero-cost barebones stock defaults don't need to be bought!
		if not HardwareCatalog.matches_filter(cat, pd, _shop_subfilter):
			continue
		var cap_pid := str(pd["id"])
		var cap_cat := cat
		var cap_name := str(pd["name"])
		var cap_cost := cost
		var stock := GameState.get_part_stock(cap_pid)
		var tag := tr(str(pd.get("tag", "")))
		_add_shop_item_card(parent, {
			"title": ("[%s]  %s" % [tag, cap_name]) if tag != "" else cap_name,
			"info": (tr("Im Lager: %d×") % stock) if stock > 0 else "",
			"color": _part_accent(cap_cat),
			"price": cap_cost,
			"strength_pct": HardwareCatalog.get_part_strength_pct(cap_cat, pd),
			"specs": _format_part_specs_short(cap_cat, pd),
			"on_buy": func(): _cart_add("part", cap_pid, cap_cat, cap_name, cap_cost),
		})


## Akzentfarbe je Einzelteil-Kategorie, damit die Karten pro Kategorie erkennbar bleiben.
func _part_accent(cat: String) -> Color:
	match cat:
		"cpu":
			return Color(0.20, 0.50, 0.84)
		"ram":
			return Color(0.30, 0.64, 0.38)
		"gpu":
			return Color(0.56, 0.32, 0.78)
		"storage":
			return Color(0.86, 0.52, 0.16)
		"cooling":
			return Color(0.18, 0.64, 0.74)
		"psu":
			return Color(0.84, 0.66, 0.14)
	return Color(0.46, 0.50, 0.56)


func _populate_warehouse_list(parent: VBoxContainer) -> void:
	var inv_n := GameState.get_total_inventory_parts()
	_add_shop_section(parent, tr("Mein Teile-Lager (%d Bauteile)") % inv_n,
		tr("Am Rack mit [E] → Tab „Hardware-Bau“ kostenlos einbauen oder ungenutzte Teile hier verkaufen."))

	if inv_n == 0:
		var el := Label.new()
		el.text = "Noch keine Einzelteile im Lager. Bestelle oben CPUs, DDR2–DDR5 RAM, GPUs, SSDs oder Netzteile!"
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.modulate = Color(0.42, 0.46, 0.54)
		parent.add_child(el)
		return

	# Lagerbestand nach Kategorie gruppieren (Reihenfolge wie CATEGORY_ORDER, Unbekanntes zuletzt)
	var by_cat := {}
	for pid_k in GameState.parts_inventory.keys():
		var pid := str(pid_k)
		if int(GameState.parts_inventory[pid]) <= 0:
			continue
		var cat := HardwareCatalog.find_part_category(pid)
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(pid)

	var cat_order: Array = []
	for c in HardwareCatalog.CATEGORY_ORDER:
		if by_cat.has(c):
			cat_order.append(c)
	for c in by_cat.keys():
		if not cat_order.has(c):
			cat_order.append(c)

	for cat_k in cat_order:
		var cat := str(cat_k)
		var meta: Dictionary = HardwareCatalog.CATEGORY_META.get(cat, {})
		var heading := str(meta.get("label", "")) if not meta.is_empty() else tr("Sonstiges")
		_add_shop_section(parent, tr(heading), "")
		for pid_v in by_cat[cat]:
			var pid := str(pid_v)
			var cnt := int(GameState.parts_inventory[pid])
			var pd := HardwareCatalog.get_part(cat, pid)
			var refund := maxi(5, int(roundf(float(pd.get("cost", 0)) * 0.60)))
			var tag := tr(str(pd.get("tag", "")))
			var pname := str(pd.get("name", pid))
			var cap_p := pid
			var opts := {
				"title": ("[%s]  %s" % [tag, pname]) if tag != "" else pname,
				"info": tr("Im Lager: %d×") % cnt,
				"color": _part_accent(cat),
				"price": refund,
				"price_text": "+$%d" % refund,
				"badge": tr("Im Lager"),
				"btn_text": tr("Verkaufen"),
				"btn_style": "danger",
				"on_buy": func(): GameState.request_sell_inventory_part(cap_p),
			}
			if not pd.is_empty():
				opts["strength_pct"] = HardwareCatalog.get_part_strength_pct(cat, pd)
				opts["specs"] = _format_part_specs_short(cat, pd)
			_add_shop_item_card(parent, opts)


func _format_part_specs_short(cat: String, pd: Dictionary) -> String:
	match cat:
		"cpu":
			return tr("Leistung %d Pkt. • %d W • +%.1f°C") % [int(pd.get("cpu_score", 0)), int(pd.get("watts", 0)), float(pd.get("heat", 0.0))]
		"ram":
			return "%d GB %s • %d W" % [int(pd.get("ram_gb", 0)), str(pd.get("tag", "")), int(pd.get("watts", 0))]
		"gpu":
			return tr("GPU %d Pkt. • %d GB VRAM • %d W") % [int(pd.get("gpu_score", 0)), int(pd.get("vram_gb", 0)), int(pd.get("watts", 0))]
		"storage":
			return "%.1f TB • %d W" % [float(pd.get("storage_tb", 0.0)), int(pd.get("watts", 0))]
		"cooling":
			return tr("Kühlung %.1f°C • %d W") % [float(pd.get("heat", 0.0)), int(pd.get("watts", 0))]
		"psu":
			return tr("Max. %d W • Effizienz %+d%%") % [int(pd.get("psu_max_watts", 350)), int(roundf((1.0 - float(pd.get("watt_mult", 1.0))) * 100.0))]
	return ""


# ==============================================================================
# APP 2: UNIFIED SUPPORT & KUNDEN-HUB (3 SUB-TABS: TICKETS | VERTRÄGE | AI & FIREWALL)
# ==============================================================================
func _render_support_hub_app() -> void:
	var sub_bar := _make_light_card(Color(0.95, 0.96, 0.98), Color(0.80, 0.83, 0.87), 6, 10, 6)
	_app_body_host.add_child(sub_bar)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	sub_bar.add_child(srow)

	var stabs: Array = [
{"id": "tickets", "label": tr("Tickets & Vermietung (%d)") % GameState.get_open_ticket_count()},
{"id": "contracts", "label": tr("Großkunden-Verträge (%d/4)") % GameState.get_active_contract_count()},
{"id": "ai", "label": tr("AI-Cluster & Firewall") + (" (DDoS!)" if GameState.ddos_active else "")},
	]
	for t in stabs:
		var td: Dictionary = t
		var tid := str(td["id"])
		var sb := Button.new()
		sb.text = tr(str(td["label"]))
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size = Vector2(0, 30)
		var sel := (_support_tab == tid)
		_style_win_btn(
			sb,
			Color(0.10, 0.46, 0.82) if sel else Color(0.90, 0.92, 0.95),
			Color(0.08, 0.36, 0.68) if sel else Color(0.76, 0.80, 0.85),
			Color.WHITE if sel else Color(0.16, 0.18, 0.22)
		)
		sb.pressed.connect(func():
			_support_tab = tid
			SfxManager.play("click", -12.0, 1.1)
			_refresh_all()
		)
		srow.add_child(sb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_app_body_host.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	if _support_tab == "tickets":
		_render_support_tickets_subtab(content)
	elif _support_tab == "contracts":
		_render_contracts_subtab(content)
	else:
		_render_ai_firewall_subtab(content)


func _render_support_tickets_subtab(content: VBoxContainer) -> void:
	var total_users := 0
	var rented_count := 0
	for rid in GameState.racks.keys():
		var rk: Dictionary = GameState.racks[rid]
		if str(rk.get("rental_type", "none")) != "none":
			rented_count += 1
			total_users += int(rk.get("active_users", 0))

	var banner := _make_light_card(Color(0.93, 0.96, 1.0), Color(0.70, 0.80, 0.92), 6, 12, 8)
	content.add_child(banner)
	var bl := Label.new()
	bl.text = tr("Offene Tickets: %d   •   Vermietete Racks: %d   •   Aktive User: %d   •   Miete: +$%.0f / 5s") % [
		GameState.get_open_ticket_count(), rented_count, total_users, GameState.total_rental_income_per_cycle
	]
	bl.add_theme_font_size_override("font_size", 13)
	bl.modulate = Color(0.12, 0.22, 0.34)
	banner.add_child(bl)

	if GameState.support_tickets.is_empty():
		var ok_c := _make_light_card(Color(0.93, 0.99, 0.95), Color(0.42, 0.76, 0.52), 6, 14, 10)
		content.add_child(ok_c)
		var ok_l := Label.new()
		ok_l.text = "Keine offenen Support-Tickets! Alle vermieteten Racks laufen stabil."
		ok_l.add_theme_font_size_override("font_size", 12.5)
		ok_l.modulate = Color(0.14, 0.42, 0.24)
		ok_c.add_child(ok_l)
	else:
		for tid in GameState.support_tickets.keys():
			var t: Dictionary = GameState.support_tickets[tid]
			var is_fixed := GameState.is_ticket_issue_fixed(t)
			var is_crit := str(t.get("priority", "HOCH")) == "KRITISCH"
			var is_typing_this := (_typing_ticket_id == str(tid))

			var bg := Color(0.92, 0.99, 0.94) if is_fixed else (Color(1.0, 0.93, 0.93) if is_crit else Color(1.0, 0.97, 0.92))
			var bd := Color(0.28, 0.72, 0.42) if is_fixed else (Color(0.84, 0.26, 0.22) if is_crit else Color(0.84, 0.56, 0.16))
			var tcard := _make_light_card(bg, bd, 7, 14, 10)
			content.add_child(tcard)
			var tv := VBoxContainer.new()
			tv.add_theme_constant_override("separation", 6)
			tcard.add_child(tv)

			var top_r := HBoxContainer.new()
			tv.add_child(top_r)
			var ttl := Label.new()
			ttl.text = "[%s]  %s — %s (%s) • %s" % [
				tr(str(t.get("priority", "HOCH"))), str(tid), str(t.get("customer", "")),
				str(t.get("rack_id", "")).to_upper(), GameState.format_message(str(t.get("title", "")), t.get("title_args", []))
			]
			ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ttl.add_theme_font_size_override("font_size", 13.5)
			ttl.modulate = Color(0.10, 0.46, 0.22) if is_fixed else (Color(0.74, 0.14, 0.12) if is_crit else Color(0.58, 0.34, 0.06))
			top_r.add_child(ttl)

			var st_l := Label.new()
			st_l.text = "BEHOBEN!" if is_fixed else "AKTIV"
			st_l.add_theme_font_size_override("font_size", 12)
			st_l.modulate = Color(0.10, 0.54, 0.26) if is_fixed else Color(0.78, 0.20, 0.16)
			top_r.add_child(st_l)

			var msg := Label.new()
			msg.text = GameState.format_message(str(t.get("message", "")), t.get("message_args", []))
			msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			msg.add_theme_font_size_override("font_size", 12)
			msg.modulate = Color(0.20, 0.24, 0.30)
			tv.add_child(msg)

			var reply_in := LineEdit.new()
			reply_in.placeholder_text = tr("Optional: Eigene Antwort tippen (mechanischer Tastatur-Sound)…")
			reply_in.text = str(_ticket_drafts.get(str(tid), ""))
			var cap_in := str(tid)
			reply_in.text_changed.connect(func(nt: String): _ticket_drafts[cap_in] = nt)
			tv.add_child(reply_in)

			var arow := HBoxContainer.new()
			arow.add_theme_constant_override("separation", 8)
			tv.add_child(arow)

			var cap_tid := str(tid)
			var brep := Button.new()
			brep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			brep.custom_minimum_size = Vector2(0, 32)
			if is_typing_this:
				brep.text = "Tippe Antwort…"
				brep.disabled = true
			elif bool(t.get("reassured", false)):
				brep.text = "Beantwortet"
				brep.disabled = true
			else:
				brep.text = "Antwort tippen (+45s)"
			_style_win_btn(brep, Color(0.10, 0.48, 0.84), Color(0.08, 0.38, 0.70), Color.WHITE)
			brep.pressed.connect(func():
				_typing_ticket_id = cap_tid
				_typing_timer = 1.1
				_typing_key_accum = 0.0
				SfxManager.play_typing_key(-9.0)
				_refresh_all()
			)
			arow.add_child(brep)

			var bcomp := Button.new()
			bcomp.custom_minimum_size = Vector2(0, 32)
			bcomp.text = tr("Rabatt erteilt") if bool(t.get("compensated", false)) else tr("$60 Rabatt")
			bcomp.disabled = bool(t.get("compensated", false)) or GameState.money < 60.0
			_style_win_btn(bcomp, Color(0.76, 0.48, 0.12), Color(0.60, 0.36, 0.08), Color.WHITE)
			bcomp.pressed.connect(func(): GameState.request_reply_ticket(cap_tid, "compensate"))
			arow.add_child(bcomp)

			var bdone := Button.new()
			bdone.custom_minimum_size = Vector2(0, 32)
			bdone.text = tr("Lösen (+$35)") if is_fixed else tr("Erst fixen")
			bdone.disabled = not is_fixed
			_style_win_btn(bdone, Color(0.12, 0.58, 0.30) if is_fixed else Color(0.84, 0.86, 0.89), Color(0.08, 0.44, 0.22), Color.WHITE if is_fixed else Color(0.45, 0.48, 0.52))
			bdone.pressed.connect(func(): GameState.request_reply_ticket(cap_tid, "resolve"))
			arow.add_child(bdone)

	if rented_count > 0:
		var fhdr := Label.new()
		fhdr.text = "VERMIETETE RACKS (LIVE-AUSLASTUNG):"
		fhdr.add_theme_font_size_override("font_size", 11.5)
		fhdr.modulate = Color(0.32, 0.38, 0.46)
		content.add_child(fhdr)
		for rid in GameState.racks.keys():
			var r: Dictionary = GameState.racks[rid]
			var rtype := str(r.get("rental_type", "none"))
			if rtype == "none" or not HardwareCatalog.RENTAL_PROFILES.has(rtype):
				continue
			var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[rtype]
			var m: Dictionary = r.get("metrics", {})
			var bn := str(m.get("bottleneck", "ok"))
			var rc := _make_light_card(Color(1.0, 0.94, 0.93) if bn != "ok" else Color.WHITE, Color(0.84, 0.30, 0.24) if bn != "ok" else Color(0.78, 0.83, 0.88), 6, 12, 8)
			content.add_child(rc)
			var rl := Label.new()
			rl.text = tr("%s %s (%s) • %d User • RAM: %.1f/%.0f GB (%.0f%%) • CPU: %.0f%% • %.1f/%.1f TB • %.0f%% • +$%.0f/5s") % [
				str(prof["icon"]), str(rid).to_upper(), str(r.get("rental_customer", "")),
				int(r.get("active_users", 0)),
				float(m.get("ram_used_gb", 0.0)), float(m.get("ram_total_gb", 0.0)), float(m.get("ram_pct", 0.0)),
				float(m.get("cpu_pct", 0.0)), float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0)),
				float(r.get("satisfaction", 100.0)), float(r.get("rental_income", 0.0))
			]
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.add_theme_font_size_override("font_size", 12)
			rl.modulate = Color(0.72, 0.16, 0.14) if bn != "ok" else Color(0.14, 0.18, 0.24)
			rc.add_child(rl)


func _render_contracts_subtab(content: VBoxContainer) -> void:
	var b := _make_light_card(Color(0.94, 0.96, 0.99), Color(0.76, 0.82, 0.90), 6, 12, 8)
	content.add_child(b)
	var hl := Label.new()
	hl.text = tr("Aktive Großkunden-Verträge: %d / 4   •   Verfügbarer RAM: %d GB   •   Router: %s") % [
		GameState.get_active_contract_count(), GameState.total_ram_gb, HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
	]
	hl.add_theme_font_size_override("font_size", 12.5)
	hl.modulate = Color(0.14, 0.22, 0.32)
	b.add_child(hl)

	for cid_v in GameState.get_contract_display_order():
		var cid := str(cid_v)
		if not GameState.contracts.has(cid):
			continue
		var c: Dictionary = GameState.contracts[cid]
		var active := bool(c["active"])
		var status := str(c["status"])
		var row := _make_light_card(
			Color(0.93, 0.99, 0.95) if (active and status == "ok") else (Color(1.0, 0.93, 0.93) if active else Color.WHITE),
			Color(0.32, 0.72, 0.44) if (active and status == "ok") else (Color(0.84, 0.30, 0.28) if active else Color(0.82, 0.85, 0.89)),
			6, 12, 9
		)
		content.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)

		var iv := VBoxContainer.new()
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(iv)

		var badge := ("  " + tr("[AKTIV]") if status == "ok" else "  " + tr("[UNTERVERSORGT]")) if active else ""
		var tl := Label.new()
		tl.text = "%s (%s)%s" % [tr(str(c["title"])), str(c["client"]), badge]
		tl.add_theme_font_size_override("font_size", 14)
		tl.modulate = Color(0.10, 0.48, 0.24) if (active and status == "ok") else (Color(0.76, 0.16, 0.14) if active else Color(0.10, 0.12, 0.16))
		iv.add_child(tl)

		var eff_pay := int(roundf(float(c["payout_per_cycle"]) * GameState.revenue_bonus_mult))
		var sl := Label.new()
		sl.text = tr("Bedarf: %d GB RAM  •  %s Bandbreite  •  Einnahmen: +$%d / 5s  •  Strafe: -$%d") % [
			int(c.get("req_ram_gb", 4)), HardwareCatalog.format_speed_mbps(float(c.get("req_mbps", 15.0))),
			eff_pay, int(c["penalty_per_cycle"])
		]
		if bool(c.get("random", false)):
			if active:
				sl.text += "\n" + tr("Befristet  •  Laufzeit: noch %d Tag(e)") % int(c.get("days_left", 0))
			else:
				sl.text += "\n" + tr("Befristet  •  Laufzeit: %d Tag(e)  •  Angebot gilt noch %d Tag(e)") % [
					int(c.get("duration_days", 1)), int(c.get("offer_days_left", 1))
				]
		sl.add_theme_font_size_override("font_size", 11.5)
		sl.modulate = Color(0.34, 0.38, 0.44)
		iv.add_child(sl)

		var btn := Button.new()
		btn.text = tr("Kündigen") if active else tr("Annehmen")
		btn.custom_minimum_size = Vector2(130, 34)
		btn.disabled = (not active) and GameState.get_active_contract_count() >= 4
		_style_win_btn(
			btn,
			Color(0.80, 0.22, 0.20) if active else (Color(0.10, 0.48, 0.84) if not btn.disabled else Color(0.84, 0.86, 0.89)),
			Color(0.64, 0.14, 0.12) if active else Color(0.08, 0.38, 0.70),
			Color.WHITE if not btn.disabled else Color(0.45, 0.48, 0.52)
		)
		var cap_id := cid
		btn.pressed.connect(func(): GameState.request_toggle_contract(cap_id))
		hb.add_child(btn)


func _render_ai_firewall_subtab(content: VBoxContainer) -> void:
	var ddos_c := _make_light_card(
		Color(1.0, 0.92, 0.92) if GameState.ddos_active else Color(0.94, 0.99, 0.95),
		Color(0.84, 0.24, 0.22) if GameState.ddos_active else Color(0.36, 0.74, 0.46),
		7, 14, 12
	)
	content.add_child(ddos_c)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 12)
	ddos_c.add_child(dh)

	var di := VBoxContainer.new()
	di.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(di)
	var dt := Label.new()
	dt.text = "Windows Server Firewall & DDoS-Abwehr"
	dt.add_theme_font_size_override("font_size", 15)
	dt.modulate = Color(0.10, 0.12, 0.16)
	di.add_child(dt)
	var dd := Label.new()
	dd.text = tr("ALARM: Aktiver DDoS-Angriff blockiert alle Einnahmen!") if GameState.ddos_active else tr("Geschützt — Netzwerkverkehr und Kunden laufen störungsfrei.")
	dd.add_theme_font_size_override("font_size", 12)
	dd.modulate = Color(0.76, 0.14, 0.12) if GameState.ddos_active else Color(0.14, 0.48, 0.24)
	di.add_child(dd)

	var dbtn := Button.new()
	dbtn.text = tr("DDoS abwehren!") if GameState.ddos_active else tr("Kein Angriff")
	dbtn.custom_minimum_size = Vector2(158, 36)
	dbtn.disabled = not GameState.ddos_active
	_style_win_btn(dbtn, Color(0.82, 0.18, 0.16) if GameState.ddos_active else Color(0.86, 0.88, 0.90), Color(0.66, 0.12, 0.10), Color.WHITE if GameState.ddos_active else Color(0.45, 0.48, 0.52))
	dbtn.pressed.connect(func(): GameState.request_mitigate_ddos())
	dh.add_child(dbtn)

	var cur_lvl := GameState.ai_platform_level
	var cur_tier: Dictionary = GameState.AI_TIERS[cur_lvl]
	var ai_c := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(ai_c)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 8)
	ai_c.add_child(av)

	var at := Label.new()
	at.text = tr("Eigene AI-Plattform: %s") % tr(str(cur_tier["label"]))
	at.add_theme_font_size_override("font_size", 16)
	at.modulate = Color(0.12, 0.26, 0.52)
	av.add_child(at)

	var ast := Label.new()
	ast.text = (tr("Monetarisiert freie Server-Kapazität automatisch nebenbei.") + "\n" + tr("Live-Einnahmen: +$%.2f / Sek.  •  Gesamt: %d GB RAM & GPU-Power %d Pkt.")) % [
		GameState.ai_revenue_per_sec, GameState.total_ram_gb, GameState.total_gpu_score
	]
	ast.add_theme_font_size_override("font_size", 12.5)
	ast.modulate = Color(0.24, 0.28, 0.34)
	av.add_child(ast)

	if cur_lvl + 1 < GameState.AI_TIERS.size():
		var nxt: Dictionary = GameState.AI_TIERS[cur_lvl + 1]
		var ncost := int(nxt["cost"])
		var mram := int(nxt.get("min_ram_gb", 16))
		var mgpu := int(nxt.get("min_gpu", 30))
		var ubtn := Button.new()
		ubtn.text = tr("Freischalten: %s ($%d  |  benötigt %d GB RAM & %d GPU)") % [tr(str(nxt["label"])), ncost, mram, mgpu]
		ubtn.custom_minimum_size = Vector2(0, 38)
		ubtn.disabled = (GameState.money < float(ncost)) or (GameState.total_ram_gb < mram) or (GameState.total_gpu_score < mgpu)
		_style_win_btn(ubtn, Color(0.10, 0.48, 0.84) if not ubtn.disabled else Color(0.84, 0.86, 0.89), Color(0.08, 0.38, 0.70), Color.WHITE if not ubtn.disabled else Color(0.45, 0.48, 0.52))
		ubtn.pressed.connect(func(): GameState.request_upgrade_ai_platform())
		av.add_child(ubtn)
	else:
		var ml := Label.new()
		ml.text = tr("Maximale AI-Plattform-Stufe erreicht!")
		ml.modulate = Color(0.12, 0.52, 0.26)
		av.add_child(ml)


# ==============================================================================
# APP 3: GEBÄUDE, ROUTER & STROMANSCHLUSS
# ==============================================================================
func _render_upgrades_app() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_app_body_host.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	# 1. Internet Router Upgrade (Real Mbit/s & Gbit/s!)
	var rt_idx := clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)
	var cur_rt: Dictionary = GameState.ROUTER_TIERS[rt_idx]
	var rt_lim := GameState.used_bandwidth_mbps > GameState.max_bandwidth_mbps
	var rt_c := _make_light_card(Color(1.0, 0.95, 0.90) if rt_lim else Color.WHITE, Color(0.86, 0.48, 0.14) if rt_lim else Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(rt_c)
	var rth := HBoxContainer.new()
	rth.add_theme_constant_override("separation", 12)
	rt_c.add_child(rth)

	var rti := VBoxContainer.new()
	rti.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rth.add_child(rti)
	var rtt := Label.new()
	rtt.text = tr("Internet-Router (Stufe %d/%d): %s") % [rt_idx + 1, GameState.ROUTER_TIERS.size(), tr(str(cur_rt["label"]))]
	rtt.add_theme_font_size_override("font_size", 15)
	rtt.modulate = Color(0.68, 0.28, 0.06) if rt_lim else Color(0.10, 0.12, 0.16)
	rti.add_child(rtt)
	var rtd := Label.new()
	var used_ports := GameState.count_cables_on("network", GameState.WALL_ROUTER_ID)
	rtd.text = tr("Auslastung: %s / %s  •  LAN-Ports: %d/%d  •  DDoS-Schutz: +%.0f%%") % [
		HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps), str(cur_rt["speed"]),
		used_ports, int(cur_rt["ports"]), (float(cur_rt["ddos_mult"]) - 1.0) * 100.0
	]
	rtd.add_theme_font_size_override("font_size", 12)
	rtd.modulate = Color(0.66, 0.24, 0.06) if rt_lim else Color(0.36, 0.40, 0.46)
	rti.add_child(rtd)

	var rtbtn := Button.new()
	rtbtn.custom_minimum_size = Vector2(210, 38)
	if rt_idx + 1 < GameState.ROUTER_TIERS.size():
		var nxt: Dictionary = GameState.ROUTER_TIERS[rt_idx + 1]
		rtbtn.text = "$%d" % int(nxt["cost"])
		rtbtn.disabled = GameState.money < float(nxt["cost"])
		_style_win_btn(rtbtn, Color(0.10, 0.48, 0.84) if not rtbtn.disabled else Color(0.84, 0.86, 0.89), Color(0.08, 0.38, 0.70), Color.WHITE if not rtbtn.disabled else Color(0.45, 0.48, 0.52))
		rtbtn.pressed.connect(func(): GameState.request_upgrade_router())
	else:
		rtbtn.text = "100 Gbit/s Max"
		rtbtn.disabled = true
		_style_win_btn(rtbtn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
	rth.add_child(rtbtn)

	# 2. Power Tier
	var pc := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(pc)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	pc.add_child(ph)
	var pi := VBoxContainer.new()
	pi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pi)
	var cur_p: Dictionary = GameState.POWER_TIERS[GameState.power_tier]
	var pt := Label.new()
	pt.text = tr("Sicherungskasten & Transformator: %s") % tr(str(cur_p["label"]))
	pt.add_theme_font_size_override("font_size", 15)
	pt.modulate = Color(0.10, 0.12, 0.16)
	pi.add_child(pt)
	var pd := Label.new()
	pd.text = tr("Erhöht das Watt-Limit vor Sicherungs-Blackouts & gibt +2 Steckdosen (Verlängerungskabel) am Sicherungskasten.")
	pd.add_theme_font_size_override("font_size", 12)
	pd.modulate = Color(0.36, 0.40, 0.46)
	pi.add_child(pd)
	var pbtn := Button.new()
	pbtn.custom_minimum_size = Vector2(210, 38)
	if GameState.power_fuse_stock > 0:
		pbtn.text = tr("Im Lager: am Kasten in F2 einsetzen")
		pbtn.disabled = true
		_style_win_btn(pbtn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
	elif GameState.power_tier + 1 < GameState.POWER_TIERS.size():
		var np: Dictionary = GameState.POWER_TIERS[GameState.power_tier + 1]
		var can_afford := GameState.money >= float(np["cost"])
		pbtn.text = "$%d" % int(np["cost"])
		_style_win_btn(pbtn, Color(0.12, 0.56, 0.32) if can_afford else Color(0.84, 0.86, 0.89), Color(0.08, 0.44, 0.24), Color.WHITE if can_afford else Color(0.45, 0.48, 0.52))
		pbtn.pressed.connect(_open_power_overlay)
	else:
		pbtn.text = tr("Max. Strom-Stufe")
		pbtn.disabled = true
		_style_win_btn(pbtn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
	ph.add_child(pbtn)

	# 3. Hall B & C
	var rc := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(rc)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 12)
	rc.add_child(rh)
	var ri := VBoxContainer.new()
	ri.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(ri)
	var htitle := tr("Gebäude-Ausbau: Garage (Stufe 1/3)")
	var hdesc := tr("Öffnet HALLE B (+63 m² Doppelboden-Serverraum).")
	if GameState.room_level == 1:
		htitle = tr("Gebäude-Ausbau: Garage + Halle B (Stufe 2/3)")
		hdesc = tr("Öffnet HALLE C — ENTERPRISE RECHENZENTRUM (+81 m²) mit eigenem Strom- & Glasfaserbus!")
	elif GameState.room_level >= 2:
		htitle = tr("Gebäude-Ausbau: Vollausbau (3/3 Hallen)")
		hdesc = tr("Alle Rechenzentrums-Hallen sind vollständig freigeschaltet!") + "\n" + GameState.get_company_goal_text()
	var rt_l := Label.new()
	rt_l.text = htitle
	rt_l.add_theme_font_size_override("font_size", 15)
	rt_l.modulate = Color(0.10, 0.12, 0.16)
	ri.add_child(rt_l)
	var rd_l := Label.new()
	rd_l.text = hdesc
	rd_l.add_theme_font_size_override("font_size", 12)
	rd_l.modulate = Color(0.36, 0.40, 0.46)
	ri.add_child(rd_l)
	var rbtn := Button.new()
	rbtn.custom_minimum_size = Vector2(210, 38)
	if GameState.room_level < 2:
		var rcost := GameState.HALL_B_COST if GameState.room_level == 0 else GameState.HALL_C_COST
		rbtn.text = (tr("Halle B ($%d)") if GameState.room_level == 0 else tr("Halle C ($%d)")) % rcost
		rbtn.disabled = GameState.money < float(rcost)
		_style_win_btn(rbtn, Color(0.10, 0.48, 0.84) if not rbtn.disabled else Color(0.84, 0.86, 0.89), Color(0.08, 0.38, 0.70), Color.WHITE if not rbtn.disabled else Color(0.45, 0.48, 0.52))
		rbtn.pressed.connect(func(): GameState.request_expand_room())
	else:
		rbtn.text = "Alle Hallen offen"
		rbtn.disabled = true
		_style_win_btn(rbtn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
	rh.add_child(rbtn)

	# 4. Electricity Meter
	var bc := _make_light_card(Color(0.99, 0.98, 0.94), Color(0.86, 0.78, 0.56), 7, 14, 12)
	content.add_child(bc)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	bc.add_child(bv)
	var bt := Label.new()
	bt.text = tr("Stromzähler & Tagesabrechnung (Tag %d • %s)") % [GameState.day_number, GameState.get_time_string()]
	bt.add_theme_font_size_override("font_size", 14.5)
	bt.modulate = Color(0.56, 0.38, 0.08)
	bv.add_child(bt)
	var bd := Label.new()
	bd.text = tr("Heute verbraucht: %.1f kWh   •   Geschätzte Rechnung um 00:00 Uhr: ~$%d   (Gestern: $%d)") % [
		GameState.daily_kwh, GameState.get_estimated_daily_bill(), GameState.last_daily_bill
	]
	bd.add_theme_font_size_override("font_size", 12)
	bd.modulate = Color(0.28, 0.26, 0.22)
	bv.add_child(bd)
	var bp := Label.new()
	bp.text = tr("Strompreis heute: $%.2f pro kWh   (Gestern: $%.2f pro kWh)") % [
		GameState.electricity_rate, GameState.last_bill_rate
	]
	bp.add_theme_font_size_override("font_size", 12)
	bp.modulate = Color(0.28, 0.26, 0.22)
	bv.add_child(bp)

	# 5. Forschung
	_add_research_card(content)


# ==============================================================================
# APP 4: WINDOWS TASK-MANAGER (100% REAL METRICS — ZERO "CU"!)
# ==============================================================================
func _render_monitor_app() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_app_body_host.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)

	var p_pct := clampf(float(GameState.total_watts) / float(maxi(GameState.max_watts, 1)) * 100.0, 0.0, 100.0)
	_add_monitor_card(grid, "Stromnetz", "%d / %d W (%.0f%%)" % [GameState.total_watts, GameState.max_watts, p_pct], tr("Tagesverbrauch: %.1f kWh • USV: %d") % [GameState.daily_kwh, GameState.ups_units.size()], p_pct, Color(0.82, 0.20, 0.16) if p_pct >= 90.0 else Color(0.12, 0.50, 0.84))

	var bw_pct := clampf(GameState.used_bandwidth_mbps / maxf(1.0, GameState.max_bandwidth_mbps) * 100.0, 0.0, 100.0)
	_add_monitor_card(grid, "Internet-Uplink", "%s / %s" % [HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps), HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)], tr("Router-Stufe %d/5 • DDoS: %s") % [GameState.router_tier + 1, tr("AKTIV!") if GameState.ddos_active else tr("Geschützt")], bw_pct, Color(0.84, 0.36, 0.10) if bw_pct >= 90.0 else Color(0.14, 0.58, 0.34))

	var t_pct := clampf((GameState.room_temp - 18.0) / 72.0 * 100.0, 0.0, 100.0)
	_add_monitor_card(grid, "Raumtemperatur", "%.1f °C" % GameState.room_temp, tr("Kühlgeräte: %d • Kritisch ab 74°C") % GameState.coolers.size(), t_pct, Color(0.84, 0.24, 0.14) if GameState.room_temp >= 68.0 else Color(0.16, 0.56, 0.72))

	_add_monitor_card(grid, "Gesamt-Hardware (Online)", "%d GB RAM  •  %.1f TB" % [GameState.total_ram_gb, GameState.total_storage_tb], tr("CPU: %d • GPU: %d • Racks: %d • Lager: %d Teile") % [GameState.total_cpu_score, GameState.total_gpu_score, GameState.racks.size(), GameState.get_total_inventory_parts()], minf(100.0, float(GameState.racks.size()) * 20.0), Color(0.32, 0.44, 0.64))

	_add_history_card(content)

	var tbl := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(tbl)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tbl.add_child(tv)

	var thead := Label.new()
	thead.text = "LIVE RACK-ÜBERSICHT (Strom • RAM • Speicher • Vermietung • Temperatur)"
	thead.add_theme_font_size_override("font_size", 11.5)
	thead.modulate = Color(0.34, 0.40, 0.48)
	tv.add_child(thead)

	if GameState.racks.is_empty():
		var nl := Label.new()
		nl.text = "Noch keine Server-Racks im Gebäude aufgestellt."
		nl.modulate = Color(0.42, 0.46, 0.52)
		tv.add_child(nl)
	else:
		for rid in GameState.racks.keys():
			var r: Dictionary = GameState.racks[rid]
			var rtype := str(r.get("rack_type", "rack"))
			var max_pdu := int(GameState.ITEM_CATALOG[rtype].get("max_pdu_watts", 3200))
			var hw := GameState.get_rack_hardware_summary(str(rid))
			var r_rent := str(r.get("rental_type", "none"))
			var rent_txt := "Standby"
			if r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
				rent_txt = tr("%s (%d User)") % [tr(str(HardwareCatalog.RENTAL_PROFILES[r_rent]["short"])), int(r.get("active_users", 0))]
			var row_l := Label.new()
			row_l.text = tr("• %s:  %d/%d W  •  %d GB RAM  •  %.1f TB  •  %.0f°C  •  %s  •  Strom:%s LAN:%s") % [
				str(rid).to_upper(), int(hw["watts"]), max_pdu, int(hw["ram_gb"]), float(hw["storage_tb"]),
				float(r["temp"]), rent_txt, tr("an") if bool(r["powered"]) else tr("aus"), tr("ok") if bool(r["networked"]) else tr("fehlt")
			]
			row_l.add_theme_font_size_override("font_size", 12)
			row_l.modulate = Color(0.14, 0.16, 0.20)
			tv.add_child(row_l)


func _add_research_card(content: VBoxContainer) -> void:
	var card := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	var head := Label.new()
	head.text = "FORSCHUNG (gilt für alle Server)"
	head.add_theme_font_size_override("font_size", 11)
	head.modulate = Color(0.34, 0.40, 0.48)
	v.add_child(head)

	for branch in GameState.RESEARCH_ORDER:
		var node: Dictionary = GameState.RESEARCH_TREE[branch]
		var levels: Array = node["levels"]
		var lvl := GameState.get_research_level(branch)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var title_lbl := Label.new()
		title_lbl.text = tr("%s (Stufe %d/%d)") % [tr(str(node["label"])), lvl, levels.size()]
		title_lbl.add_theme_font_size_override("font_size", 14)
		title_lbl.modulate = Color(0.10, 0.12, 0.16)
		info.add_child(title_lbl)

		var desc_lbl := Label.new()
		var cur_pct := (1.0 - GameState.get_research_mult(branch)) * 100.0
		var desc := tr("%s  •  Aktuell: -%.0f%% %s") % [tr(str(node["desc"])), cur_pct, tr(str(node["stat"]))]
		if lvl < levels.size():
			desc += "  •  " + tr("Nächste Stufe: -%.0f%%") % ((1.0 - float(levels[lvl]["mult"])) * 100.0)
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.modulate = Color(0.36, 0.40, 0.46)
		info.add_child(desc_lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(210, 38)
		var reason := GameState.get_research_block_reason(branch)
		if reason.is_empty():
			var cost := GameState.get_research_cost(branch)
			btn.text = tr("Erforschen ($%d)") % cost
			btn.disabled = GameState.money < float(cost)
			_style_win_btn(btn, Color(0.42, 0.26, 0.74) if not btn.disabled else Color(0.84, 0.86, 0.89), Color(0.32, 0.18, 0.60), Color.WHITE if not btn.disabled else Color(0.45, 0.48, 0.52))
			btn.pressed.connect(func(): GameState.request_research(branch))
		else:
			btn.text = reason
			btn.disabled = true
			_style_win_btn(btn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
		row.add_child(btn)


func _add_history_card(content: VBoxContainer) -> void:
	var card := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 12)
	content.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var head := Label.new()
	head.text = tr("VERLAUF (letzte %d Minuten, ein Messpunkt alle %d s)") % [
		int(StatsHistory.SAMPLE_INTERVAL * float(StatsHistory.MAX_SAMPLES) / 60.0), int(StatsHistory.SAMPLE_INTERVAL)
	]
	head.add_theme_font_size_override("font_size", 11)
	head.modulate = Color(0.34, 0.40, 0.48)
	v.add_child(head)

	_add_history_chart(v, "money", "Kontostand", "$%.0f", Color(0.14, 0.58, 0.34), NAN, "")
	_add_history_chart(v, "watts", "Stromverbrauch", "%.0f W", Color(0.12, 0.50, 0.84), float(GameState.max_watts), "Limit")
	_add_history_chart(v, "temp", "Raumtemperatur", "%.1f °C", Color(0.84, 0.24, 0.14), 74.0, "Kritisch")


func _add_history_chart(parent: VBoxContainer, series: String, title: String, unit_format: String, col: Color, ref_value: float, ref_label: String) -> void:
	var chart := HISTORY_CHART.new()
	chart.series = series
	chart.title = tr(title)
	chart.unit_format = unit_format
	chart.line_color = col
	chart.ref_value = ref_value
	chart.ref_label = tr(ref_label)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(chart)


func _add_monitor_card(grid: GridContainer, title: String, value_txt: String, sub_txt: String, pct: float, bar_col: Color) -> void:
	var card := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 7, 14, 10)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)
	var t := Label.new()
	t.text = tr(title)
	t.add_theme_font_size_override("font_size", 11.5)
	t.modulate = Color(0.36, 0.42, 0.48)
	v.add_child(t)
	var val := Label.new()
	val.text = value_txt
	val.add_theme_font_size_override("font_size", 16)
	val.modulate = Color(0.10, 0.12, 0.16)
	v.add_child(val)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = pct
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 9)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.88, 0.90, 0.93)
	bg_sb.set_corner_radius_all(4)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = bar_col
	fill_sb.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg_sb)
	pb.add_theme_stylebox_override("fill", fill_sb)
	v.add_child(pb)
	var sub := Label.new()
	sub.text = tr(sub_txt)
	sub.add_theme_font_size_override("font_size", 11)
	sub.modulate = Color(0.42, 0.46, 0.52)
	v.add_child(sub)


# ==============================================================================
# BUILD REALISTIC WINDOWS 11 DESKTOP MONITOR SHELL (4 CLEAN APPS!)
# ==============================================================================
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.64)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_monitor_frame = PanelContainer.new()
	# Vollbild: der PC füllt den ganzen Bildschirm, ohne Rahmen. Die Größe setzt _fit_fullscreen().
	_monitor_frame.custom_minimum_size = get_viewport_rect().size
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0.0, 0.0, 0.0)
	bezel.set_border_width_all(0)
	bezel.set_corner_radius_all(0)
	bezel.set_content_margin_all(0)
	_monitor_frame.add_theme_stylebox_override("panel", bezel)
	center.add_child(_monitor_frame)

	var screen_v := VBoxContainer.new()
	screen_v.add_theme_constant_override("separation", 0)
	_monitor_frame.add_child(screen_v)

	var desktop_area := PanelContainer.new()
	desktop_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wp_sb := StyleBoxFlat.new()
	wp_sb.bg_color = Color(0.14, 0.25, 0.38)
	wp_sb.set_content_margin_all(0)
	desktop_area.add_theme_stylebox_override("panel", wp_sb)
	screen_v.add_child(desktop_area)

	var desktop_layer := Control.new()
	desktop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	desktop_area.add_child(desktop_layer)

	var wp_accent := ColorRect.new()
	wp_accent.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wp_accent.offset_top = -220
	wp_accent.color = Color(0.10, 0.19, 0.31, 0.55)
	wp_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desktop_layer.add_child(wp_accent)

	var desk_hbox := HBoxContainer.new()
	desk_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk_hbox.add_theme_constant_override("separation", 12)
	desktop_layer.add_child(desk_hbox)

	# LEFT DESKTOP ICONS (4 Clean Apps + Save Shortcut)
	var icon_margin := MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 12)
	icon_margin.add_theme_constant_override("margin_top", 14)
	icon_margin.add_theme_constant_override("margin_bottom", 14)
	desk_hbox.add_child(icon_margin)

	var icon_col := VBoxContainer.new()
	icon_col.custom_minimum_size = Vector2(96, 0)
	icon_col.add_theme_constant_override("separation", 10)
	icon_margin.add_child(icon_col)

	for aid in APP_ORDER:
		var meta: Dictionary = APP_META[aid]
		var ibtn := Button.new()
		ibtn.text = tr(str(meta["name"]))
		_add_btn_icon(ibtn, str(meta["icon"]), 26, "top")
		ibtn.custom_minimum_size = Vector2(90, 66)
		ibtn.add_theme_font_size_override("font_size", 12)
		_style_win_btn(ibtn, Color(0.12, 0.22, 0.34, 0.58), Color(0.45, 0.62, 0.80, 0.30), Color(0.96, 0.98, 1.0))
		var cap_aid := aid
		ibtn.pressed.connect(func(): _open_app(cap_aid))
		icon_col.add_child(ibtn)
		_desktop_btns[aid] = ibtn

	var save_icon := Button.new()
	save_icon.text = "Speichern"
	_add_btn_icon(save_icon, "save", 26, "top")
	save_icon.custom_minimum_size = Vector2(90, 66)
	save_icon.add_theme_font_size_override("font_size", 12)
	_style_win_btn(save_icon, Color(0.12, 0.22, 0.34, 0.58), Color(0.45, 0.62, 0.80, 0.30), Color(0.96, 0.98, 1.0))
	save_icon.pressed.connect(_trigger_quick_save)
	icon_col.add_child(save_icon)

	# MAIN FLOATING WINDOWS 11 APP WINDOW
	var win_margin := MarginContainer.new()
	win_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	win_margin.add_theme_constant_override("margin_top", 12)
	win_margin.add_theme_constant_override("margin_right", 12)
	win_margin.add_theme_constant_override("margin_bottom", 12)
	desk_hbox.add_child(win_margin)

	_app_window = PanelContainer.new()
	_app_window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_app_window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var win_sb := StyleBoxFlat.new()
	win_sb.bg_color = Color(0.95, 0.96, 0.97, 0.99)
	win_sb.border_color = Color(0.68, 0.73, 0.80)
	win_sb.set_border_width_all(1)
	win_sb.set_corner_radius_all(8)
	win_sb.set_content_margin_all(0)
	_app_window.add_theme_stylebox_override("panel", win_sb)
	win_margin.add_child(_app_window)

	var win_v := VBoxContainer.new()
	win_v.add_theme_constant_override("separation", 0)
	_app_window.add_child(win_v)

	# Light Title Bar
	var tb_panel := PanelContainer.new()
	var tb_sb := StyleBoxFlat.new()
	tb_sb.bg_color = Color(0.90, 0.92, 0.95)
	tb_sb.border_color = Color(0.80, 0.84, 0.88)
	tb_sb.border_width_bottom = 1
	tb_sb.corner_radius_top_left = 7
	tb_sb.corner_radius_top_right = 7
	tb_sb.content_margin_left = 14
	tb_sb.content_margin_right = 8
	tb_sb.content_margin_top = 6
	tb_sb.content_margin_bottom = 6
	tb_panel.add_theme_stylebox_override("panel", tb_sb)
	win_v.add_child(tb_panel)

	var tb_row := HBoxContainer.new()
	tb_row.add_theme_constant_override("separation", 6)
	tb_panel.add_child(tb_row)

	_win_title_icon = _win_icon("cart", 16)
	_win_title_icon.modulate = Color(0.10, 0.46, 0.82)
	tb_row.add_child(_win_title_icon)

	_win_title_lbl = Label.new()
	_win_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_win_title_lbl.add_theme_font_size_override("font_size", 14)
	_win_title_lbl.modulate = Color(0.10, 0.12, 0.16)
	tb_row.add_child(_win_title_lbl)

	var min_btn := Button.new()
	_add_btn_icon(min_btn, "minimize", 12, "center")
	min_btn.custom_minimum_size = Vector2(34, 26)
	_style_win_btn(min_btn, Color(0.90, 0.92, 0.95), Color(0.80, 0.84, 0.88), Color(0.18, 0.20, 0.24))
	min_btn.pressed.connect(_minimize_app)
	tb_row.add_child(min_btn)

	var cls_btn := Button.new()
	_add_btn_icon(cls_btn, "close", 12, "center")
	cls_btn.custom_minimum_size = Vector2(38, 26)
	_style_win_btn(cls_btn, Color(0.84, 0.22, 0.20), Color(0.70, 0.16, 0.14), Color.WHITE)
	cls_btn.pressed.connect(_minimize_app)
	tb_row.add_child(cls_btn)

	var sub_panel := PanelContainer.new()
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(0.96, 0.97, 0.98)
	sub_sb.border_color = Color(0.86, 0.88, 0.91)
	sub_sb.border_width_bottom = 1
	sub_sb.content_margin_left = 14
	sub_sb.content_margin_right = 14
	sub_sb.content_margin_top = 5
	sub_sb.content_margin_bottom = 5
	sub_panel.add_theme_stylebox_override("panel", sub_sb)
	win_v.add_child(sub_panel)

	_win_subtitle_lbl = Label.new()
	_win_subtitle_lbl.add_theme_font_size_override("font_size", 11.5)
	_win_subtitle_lbl.modulate = Color(0.28, 0.34, 0.42)
	sub_panel.add_child(_win_subtitle_lbl)

	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 12)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.add_theme_constant_override("margin_top", 10)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	win_v.add_child(body_margin)

	_app_body_host = VBoxContainer.new()
	_app_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_app_body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_app_body_host.add_theme_constant_override("separation", 8)
	body_margin.add_child(_app_body_host)

	# START MENU POPUP
	_start_menu = PanelContainer.new()
	_start_menu.visible = false
	# Windows 11: das Startmenü öffnet sich mittig über der Taskleiste
	_start_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_start_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_start_menu.offset_left = -170.0
	_start_menu.offset_right = 170.0
	_start_menu.offset_top = -412.0
	_start_menu.offset_bottom = -12.0
	var sm_sb := StyleBoxFlat.new()
	sm_sb.bg_color = Color(0.95, 0.96, 0.98, 0.98)
	sm_sb.border_color = Color(0.68, 0.73, 0.80)
	sm_sb.set_border_width_all(1)
	sm_sb.set_corner_radius_all(8)
	sm_sb.set_content_margin_all(14)
	_start_menu.add_theme_stylebox_override("panel", sm_sb)
	desktop_layer.add_child(_start_menu)

	var sm_v := VBoxContainer.new()
	sm_v.add_theme_constant_override("separation", 6)
	_start_menu.add_child(sm_v)
	var sm_hdr_row := HBoxContainer.new()
	sm_hdr_row.add_theme_constant_override("separation", 8)
	sm_v.add_child(sm_hdr_row)
	var sm_logo := _win_icon("windows", 16)
	sm_logo.modulate = Color(0.10, 0.46, 0.82)
	sm_hdr_row.add_child(sm_logo)
	var sm_hdr := Label.new()
	sm_hdr.text = "Windows Server — Start"
	sm_hdr.add_theme_font_size_override("font_size", 14)
	sm_hdr.modulate = Color(0.10, 0.14, 0.20)
	sm_hdr_row.add_child(sm_hdr)
	sm_v.add_child(HSeparator.new())

	for aid in APP_ORDER:
		var meta: Dictionary = APP_META[aid]
		var sbtn := Button.new()
		sbtn.text = tr(str(meta["name"]))
		_add_btn_icon(sbtn, str(meta["icon"]), 16)
		sbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sbtn.custom_minimum_size = Vector2(0, 34)
		_style_win_btn(sbtn, Color(0.92, 0.94, 0.97), Color(0.80, 0.84, 0.89), Color(0.12, 0.14, 0.18))
		var cap_id := aid
		sbtn.pressed.connect(func(): _open_app(cap_id))
		sm_v.add_child(sbtn)

	var sm_sp := Control.new()
	sm_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sm_v.add_child(sm_sp)
	sm_v.add_child(HSeparator.new())

	_dark_toggle_btn = Button.new()
	_dark_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dark_toggle_btn.custom_minimum_size = Vector2(0, 34)
	_style_win_btn(_dark_toggle_btn, Color(0.92, 0.94, 0.97), Color(0.80, 0.84, 0.89), Color(0.12, 0.14, 0.18))
	_dark_toggle_btn.pressed.connect(_toggle_dark_mode)
	sm_v.add_child(_dark_toggle_btn)
	_update_dark_toggle_text()

	var shutdown_btn := Button.new()
	shutdown_btn.text = "Herunterfahren"
	_add_btn_icon(shutdown_btn, "power_off", 16)
	shutdown_btn.custom_minimum_size = Vector2(0, 36)
	_style_win_btn(shutdown_btn, Color(0.92, 0.94, 0.97), Color(0.80, 0.84, 0.89), Color(0.12, 0.14, 0.18))
	shutdown_btn.pressed.connect(_shut_down_pc)
	sm_v.add_child(shutdown_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Aufstehen, PC bleibt an [ESC]"
	_add_btn_icon(exit_btn, "power_off", 16)
	exit_btn.custom_minimum_size = Vector2(0, 36)
	_style_win_btn(exit_btn, Color(0.82, 0.22, 0.20), Color(0.66, 0.16, 0.14), Color.WHITE)
	exit_btn.pressed.connect(func(): close_requested.emit())
	sm_v.add_child(exit_btn)

	# FLOATING VOIP PHONE CALL POPUP
	_call_popup = PanelContainer.new()
	_call_popup.visible = false
	_call_popup.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_call_popup.offset_left = -380
	_call_popup.offset_right = -14
	_call_popup.offset_top = -310
	_call_popup.offset_bottom = -14
	var cp_sb := StyleBoxFlat.new()
	cp_sb.bg_color = Color(0.98, 0.99, 1.0, 0.99)
	cp_sb.border_color = Color(0.82, 0.24, 0.18)
	cp_sb.set_border_width_all(2)
	cp_sb.set_corner_radius_all(10)
	cp_sb.set_content_margin_all(14)
	_call_popup.add_theme_stylebox_override("panel", cp_sb)
	desktop_layer.add_child(_call_popup)

	_call_body = VBoxContainer.new()
	_call_body.add_theme_constant_override("separation", 7)
	_call_popup.add_child(_call_body)

	# BOTTOM WINDOWS 11 TASKBAR: Start und App-Symbole in der Mitte, Infobereich rechts
	var taskbar := PanelContainer.new()
	taskbar.custom_minimum_size = Vector2(0, 48)
	var tb_bar_sb := StyleBoxFlat.new()
	tb_bar_sb.bg_color = Color(0.93, 0.94, 0.97, 0.97)
	tb_bar_sb.border_color = Color(0.80, 0.83, 0.88)
	tb_bar_sb.border_width_top = 1
	tb_bar_sb.content_margin_left = 10
	tb_bar_sb.content_margin_right = 10
	tb_bar_sb.content_margin_top = 4
	tb_bar_sb.content_margin_bottom = 4
	taskbar.add_theme_stylebox_override("panel", tb_bar_sb)
	screen_v.add_child(taskbar)
	_taskbar_panel = taskbar

	var t_row := HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 4)
	taskbar.add_child(t_row)

	# Zwei Platzhalter links und rechts halten Start und Apps in der Mitte, ohne den Infobereich zu überdecken.
	var tb_left_sp := Control.new()
	tb_left_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_row.add_child(tb_left_sp)

	var start_btn := Button.new()
	start_btn.tooltip_text = "Start"
	_add_btn_icon(start_btn, "windows", 20, "center")
	start_btn.custom_minimum_size = Vector2(44, 40)
	_style_taskbar_btn(start_btn, false, false)
	_btn_icon(start_btn).modulate = Color(0.0, 0.47, 0.84)
	start_btn.pressed.connect(func():
		_start_menu.visible = not _start_menu.visible
		if _start_menu.visible:
			SfxManager.play("win_start", -10.0)
		else:
			SfxManager.play("click", -10.0, 1.05)
	)
	t_row.add_child(start_btn)

	for aid in APP_ORDER:
		var meta: Dictionary = APP_META[aid]
		var pbtn := Button.new()
		pbtn.tooltip_text = tr(str(meta["name"]))
		_add_btn_icon(pbtn, str(meta["icon"]), 20)
		pbtn.custom_minimum_size = Vector2(40, 40)
		pbtn.add_theme_font_size_override("font_size", 12)
		_style_taskbar_btn(pbtn, false, false)
		var cap_id := aid
		pbtn.pressed.connect(func(): _open_app(cap_id))
		t_row.add_child(pbtn)
		_taskbar_btns[aid] = pbtn

	var tb_sp := Control.new()
	tb_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_row.add_child(tb_sp)

	_tray_money = Label.new()
	_tray_money.add_theme_font_size_override("font_size", 13)
	t_row.add_child(_tray_money)
	t_row.add_child(VSeparator.new())
	_tray_power_icon = _win_icon("power", 14)
	t_row.add_child(_tray_power_icon)
	_tray_power = Label.new()
	_tray_power.add_theme_font_size_override("font_size", 12)
	t_row.add_child(_tray_power)
	t_row.add_child(VSeparator.new())
	_tray_temp_icon = _win_icon("temp", 14)
	t_row.add_child(_tray_temp_icon)
	_tray_temp = Label.new()
	_tray_temp.add_theme_font_size_override("font_size", 12)
	t_row.add_child(_tray_temp)
	t_row.add_child(VSeparator.new())
	_tray_net_icon = _win_icon("net", 14)
	t_row.add_child(_tray_net_icon)
	_tray_net = Label.new()
	_tray_net.add_theme_font_size_override("font_size", 12)
	t_row.add_child(_tray_net)
	t_row.add_child(VSeparator.new())
	# Windows-Infobereich: WLAN und Lautsprecher, daneben Uhrzeit und Datum
	var tray_wifi := _win_icon("wifi", 16)
	tray_wifi.modulate = Color(0.16, 0.18, 0.22)
	t_row.add_child(tray_wifi)
	var tray_speaker := _win_icon("speaker", 16)
	tray_speaker.modulate = Color(0.16, 0.18, 0.22)
	t_row.add_child(tray_speaker)
	_tray_clock = Label.new()
	_tray_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tray_clock.add_theme_font_size_override("font_size", 11)
	_tray_clock.modulate = Color(0.14, 0.16, 0.20)
	_tray_clock.custom_minimum_size = Vector2(70, 0)
	# Damit der Tooltip mit dem Spieltag erscheint, muss das Label die Maus sehen.
	_tray_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	t_row.add_child(_tray_clock)

	var leave_btn := Button.new()
	leave_btn.text = "ESC"
	_add_btn_icon(leave_btn, "power_off", 14)
	leave_btn.custom_minimum_size = Vector2(64, 32)
	_style_win_btn(leave_btn, Color(0.84, 0.24, 0.22), Color(0.68, 0.16, 0.14), Color.WHITE)
	leave_btn.pressed.connect(func(): close_requested.emit())
	t_row.add_child(leave_btn)


func _load_dark_mode() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PC_DESKTOP_CFG) == OK:
		_dark_mode = bool(cfg.get_value("desktop", "dark_mode", false))


func _save_dark_mode() -> void:
	var cfg := ConfigFile.new()
	# Fehlt die Datei noch, wird sie beim Speichern neu angelegt.
	cfg.load(PC_DESKTOP_CFG)
	cfg.set_value("desktop", "dark_mode", _dark_mode)
	var err := cfg.save(PC_DESKTOP_CFG)
	if err != OK:
		push_warning("PC-Dark-Mode konnte nicht gespeichert werden (Fehler %d)." % err)


func _build_dark_filter() -> void:
	var shader := Shader.new()
	shader.code = DARK_FILTER_SHADER
	for target in [_app_window, _start_menu, _call_popup, _taskbar_panel]:
		var ctrl := target as Control
		if ctrl == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var rect := ColorRect.new()
		rect.material = mat
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		# Als letzte Kinder gezeichnet, damit sie über dem fertigen Desktop liegen.
		add_child(rect)
		_dark_targets.append(ctrl)
		_dark_filters.append(rect)


func _update_dark_filter() -> void:
	var booting := _boot_screen != null and _boot_screen.is_running()
	for i in range(_dark_filters.size()):
		var rect := _dark_filters[i]
		var target := _dark_targets[i]
		var active := _dark_mode and not booting and is_instance_valid(target) and target.is_visible_in_tree()
		rect.visible = active
		if not active:
			continue
		var g := target.get_global_rect()
		rect.global_position = g.position
		rect.size = g.size
		var radius := 0.0
		var sb := target.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			radius = float(sb.corner_radius_top_left)
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("rect_size", g.size)
		mat.set_shader_parameter("corner_radius", radius)


func _toggle_dark_mode() -> void:
	_dark_mode = not _dark_mode
	_save_dark_mode()
	_update_dark_toggle_text()
	_update_dark_filter()
	SfxManager.play("click", -10.0, 1.05)


func _update_dark_toggle_text() -> void:
	if _dark_toggle_btn == null:
		return
	_dark_toggle_btn.text = "Dunkler Modus: An" if _dark_mode else "Dunkler Modus: Aus"


## Gezeichnetes Symbol aus UIStyle.draw_icon. Es wird weiß gezeichnet, die Farbe kommt über modulate.
func _win_icon(kind: String, px: int) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_meta("kind", kind)
	ic.draw.connect(func() -> void:
		UIStyle.draw_icon(ic, str(ic.get_meta("kind", "")), Rect2(Vector2.ZERO, ic.size), Color.WHITE)
	)
	return ic


func _set_win_icon_kind(ic: Control, kind: String) -> void:
	if ic == null or str(ic.get_meta("kind", "")) == kind:
		return
	ic.set_meta("kind", kind)
	ic.queue_redraw()


func _btn_icon(btn: Button) -> Control:
	if btn == null or not btn.has_meta("icon_ctrl"):
		return null
	return btn.get_meta("icon_ctrl") as Control


## Setzt ein gezeichnetes Symbol in einen Button. Vor _style_win_btn aufrufen:
## _style_win_btn rückt den Text passend ein und färbt das Symbol wie den Text.
## layout: "left" = links neben dem Text, "top" = über dem Text (Desktop-Kacheln), "center" = nur Symbol.
func _add_btn_icon(btn: Button, kind: String, px: int, layout: String = "left") -> Control:
	var ic := _win_icon(kind, px)
	var half := float(px) * 0.5
	match layout:
		"top":
			ic.set_anchors_preset(Control.PRESET_CENTER_TOP)
			ic.offset_left = -half
			ic.offset_right = half
			ic.offset_top = 8.0
			ic.offset_bottom = 8.0 + float(px)
			btn.set_meta("icon_pad_top", px + 8)
		"center":
			ic.set_anchors_preset(Control.PRESET_CENTER)
			ic.offset_left = -half
			ic.offset_right = half
			ic.offset_top = -half
			ic.offset_bottom = half
		_:
			ic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			ic.offset_left = 10.0
			ic.offset_right = 10.0 + float(px)
			ic.offset_top = -half
			ic.offset_bottom = half
			btn.set_meta("icon_pad_left", px + 8)
	btn.add_child(ic)
	btn.set_meta("icon_ctrl", ic)
	return ic


func _close_price_overlay() -> void:
	if _price_overlay != null and is_instance_valid(_price_overlay):
		_price_overlay.queue_free()
	_price_overlay = null


## Preis-Overlay für die Stromstufe: Vergleich "Aktuell" gegen "Neu", unten der Kaufen-Button.
func _open_power_overlay() -> void:
	_close_price_overlay()
	if GameState.power_fuse_stock > 0:
		return
	if GameState.power_tier + 1 >= GameState.POWER_TIERS.size():
		return
	var cur: Dictionary = GameState.POWER_TIERS[GameState.power_tier]
	var nxt: Dictionary = GameState.POWER_TIERS[GameState.power_tier + 1]
	var cost := int(nxt["cost"])
	var can_afford := GameState.money >= float(cost)

	_price_overlay = Control.new()
	_price_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_price_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_price_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_price_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_price_overlay.add_child(center)

	var card := _make_light_card(Color.WHITE, Color(0.80, 0.84, 0.89), 10, 22, 18)
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var title := Label.new()
	title.text = tr("Stromversorgung upgraden")
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.10, 0.12, 0.16)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)

	var cur_watts := int(cur["watts"])
	var nxt_watts := int(nxt["watts"])
	var rows: Array = [
		["", tr("Aktuell"), tr("Neu")],
		[tr("Stufe"),
			"%d / %d" % [GameState.power_tier + 1, GameState.POWER_TIERS.size()],
			"%d / %d" % [GameState.power_tier + 2, GameState.POWER_TIERS.size()]],
		[tr("Anschluss"), tr(str(cur["label"])), tr(str(nxt["label"]))],
		[tr("Watt-Limit"),
			"%.1f kW" % (float(cur_watts) / 1000.0),
			"%.1f kW (+%.1f kW)" % [float(nxt_watts) / 1000.0, float(nxt_watts - cur_watts) / 1000.0]],
		[tr("Preis"), "–", "$%d" % cost],
	]
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(3):
			var lbl := Label.new()
			lbl.text = str(row[c])
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(150 if c > 0 else 90, 0)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 13)
			if r == 0 or c == 0:
				lbl.modulate = Color(0.36, 0.40, 0.46)
			elif c == 1:
				lbl.modulate = Color(0.45, 0.48, 0.52)
			else:
				lbl.modulate = Color(0.08, 0.44, 0.24)
			grid.add_child(lbl)

	var note := Label.new()
	note.text = tr("Du kaufst eine Drehsicherung. Sie kommt ins Lager. Setze sie am Sicherungskasten mit [E] in Steckplatz F2 ein: Erst dann steigt die Stromstufe, und die alte Sicherung bekommst du in die Hand.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(0.36, 0.40, 0.46)
	col.add_child(note)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Abbrechen")
	cancel_btn.custom_minimum_size = Vector2(120, 38)
	_style_win_btn(cancel_btn, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.82), Color(0.20, 0.24, 0.30))
	cancel_btn.pressed.connect(_close_price_overlay)
	btn_row.add_child(cancel_btn)

	var buy_btn := Button.new()
	buy_btn.text = tr("Kaufen ($%d)") % cost
	buy_btn.custom_minimum_size = Vector2(170, 38)
	buy_btn.disabled = not can_afford
	_style_win_btn(buy_btn, Color(0.12, 0.56, 0.32) if can_afford else Color(0.84, 0.86, 0.89), Color(0.08, 0.44, 0.24), Color.WHITE if can_afford else Color(0.45, 0.48, 0.52))
	buy_btn.pressed.connect(func():
		GameState.request_upgrade_power()
		_close_price_overlay()
	)
	btn_row.add_child(buy_btn)


func _make_light_card(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	card.add_theme_stylebox_override("panel", sb)
	return card


func _style_win_btn(btn: Button, bg: Color, border: Color, txt_col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = border
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 10 + int(btn.get_meta("icon_pad_left", 0))
	normal.content_margin_right = 10
	normal.content_margin_top = 4 + int(btn.get_meta("icon_pad_top", 0))
	normal.content_margin_bottom = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.darkened(0.08) if bg.get_luminance() > 0.5 else bg.lightened(0.10)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.88, 0.89, 0.91)
	disabled.border_color = Color(0.78, 0.80, 0.83)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", txt_col)
	btn.add_theme_color_override("font_pressed_color", txt_col)
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.53, 0.57))
	var ic := _btn_icon(btn)
	if ic != null:
		ic.modulate = txt_col


## Taskleisten-Button im Windows-11-Stil: flach, beim Überfahren hell hinterlegt,
## geöffnete App mit blauem Strich unten, Warnzustand rot hinterlegt.
## Ohne Text sitzt das Symbol mittig, mit Text (Zähler) rückt der Text neben das Symbol.
func _style_taskbar_btn(btn: Button, is_open: bool, alert: bool) -> void:
	var accent := Color(0.0, 0.47, 0.84)
	var txt_col := Color(0.66, 0.12, 0.10) if alert else Color(0.10, 0.12, 0.15)
	var normal := StyleBoxFlat.new()
	if alert:
		normal.bg_color = Color(0.98, 0.86, 0.84, 0.95)
	elif is_open:
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.80)
	else:
		normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	normal.set_corner_radius_all(5)
	var pad_left := 10
	if not btn.text.is_empty():
		pad_left += int(btn.get_meta("icon_pad_left", 0))
	normal.content_margin_left = pad_left
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	if is_open:
		normal.border_color = accent
		normal.border_width_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.darkened(0.05) if alert else Color(1.0, 1.0, 1.0, 0.65)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.86, 0.88, 0.92, 0.90)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", txt_col)
	btn.add_theme_color_override("font_pressed_color", txt_col)
	var ic := _btn_icon(btn)
	if ic != null:
		ic.modulate = accent if is_open and not alert else txt_col


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
