class_name TerminalUI
extends Control
## Verion OS am Büro-PC ([E] am Schreibtisch). Die Arbeitsfläche (Fenster, Dock, Statusleiste)
## liegt in VerionDesktop, hier stehen die Inhalte der Apps. Alle Apps sind mit hellen Farben
## aufgebaut, VerionTheme färbt sie für den dunklen Modus um.

signal close_requested
signal typing_state_changed(is_typing: bool)

var _monitor_frame: PanelContainer
var _desktop: VerionDesktop
var _app_body_host: VBoxContainer
var _call_popup: PanelContainer
var _call_body: VBoxContainer
## Apps, deren Fenster neu gezeichnet werden müssen (App -> true).
var _dirty_apps: Dictionary = {}
## Scrollstellungen, die nach dem Neuzeichnen noch gesetzt werden müssen: app -> {"vals": Array[int], "frames": int}.
## Die neue Liste kennt ihre Höhe erst nach ein paar Layout-Durchläufen und würde sonst auf 0 zurückspringen.
var _scroll_restore: Dictionary = {}
var _dirty_accum := 0.0
var _mouse_down := false
var _idle_accum := 0.0
var _mail_state: Dictionary = {"folder": "all", "mail": "", "msg": "", "ok": true}
var _market_state: Dictionary = {"tab": "overview", "msg": "", "ok": true}
var _ops_state: Dictionary = {"tab": "power", "msg": "", "ok": true}
var _fw_state: Dictionary = {"msg": "", "ok": true}
var _cams_state: Dictionary = {"big": "", "page": 0}

var _active_app: String = "" # "" | "shop" | "support" | "upgrades" | "monitor"
var _shop_tab: String = "chassis" # "chassis" | "infra" | "cpu" | "ram" | "gpu" | "storage" | "cooling" | "psu" | "warehouse"
var _shop_subfilter: String = "Alle"
var _support_tab: String = "tickets" # "tickets" | "contracts" | "ai"

# Real Shopping Cart: Array of {key, kind, id, cat, name, price, qty}
var _cart: Array = []

# Realistic Mechanical Keyboard Typing Animation & Sound
var _typing_ticket_id: String = ""
## Status-Labels der Ticket-Karten (Ticket-ID -> Label) für die Countdown-Anzeige.
var _ticket_status_labels: Dictionary = {}
var _ticket_status_accum: float = 0.0
const TICKET_STATUS_REFRESH_INTERVAL := 0.5
var _typing_timer: float = 0.0
var _typing_key_accum: float = 0.0
var _manual_typing_pulse: float = 0.0
var _last_emitted_typing: bool = false
var _ticket_drafts: Dictionary = {}

# Letzte Rückmeldung der Finanz-Apps (Personal, Bank, Rechnungen)
var _fin_msg: String = ""
var _fin_msg_ok: bool = true

# Der PC bleibt an, bis jemand im Startmenü "Herunterfahren" wählt.
# Nur ein ausgeschalteter PC fährt beim Hinsetzen mit BIOS und Verion-Logo hoch.
var _boot_screen: PcBootScreen = null
var _boot_cold: bool = true
var _terminal_open: bool = false
var _shutting_down: bool = false
const TRAY_REFRESH_INTERVAL := 0.25
var _tray_accum: float = 0.0
const OPEN_FADE_TIME := 0.25
# Zeitpunkt, an dem der laufende Startvorgang begann (-1 = PC lief schon oder kein Start).
var _boot_started_msec: int = -1

const FINANCE_APPS: Array[String] = ["staff", "bank", "balance", "bills"]
const APP_ORDER: Array[String] = ["mail", "shop", "support", "market", "upgrades", "ops", "firewall", "monitor", "cams", "staff", "bank", "balance", "bills"]
## Diese Apps zeigen laufende Werte und werden im Spieltakt neu gezeichnet.
const LIVE_APPS: Array[String] = ["support", "upgrades", "monitor", "ops", "firewall"]
const REFRESH_ACTIVE := 0.2
const REFRESH_IDLE := 1.5
const HISTORY_CHART := preload("res://scripts/ui/history_chart.gd")
const APP_META := {
	"mail": {"icon": "mail", "name": "E-Mail", "title": "Verion Mail — Postfach der Firma"},
	"market": {"icon": "market", "name": "Markt", "title": "Markt & Konkurrenz — Preise, Werbung und Abwerben"},
	"shop": {"icon": "cart", "name": "Shop", "title": "CloudParts.de — Hardware-Shop, Warenkorb & Teile-Lager"},
	"support": {"icon": "headset", "name": "Support", "title": "ServiceDesk & Kunden-Hub — Tickets, Verträge & AI"},
	"upgrades": {"icon": "building", "name": "Gebäude", "title": "Gebäude & Anschlüsse — Router, Strom und Hallen-Ausbau"},
	"ops": {"icon": "power", "name": "Betrieb", "title": "Betrieb — Strompreis, Notstrom, Fernwärme & Zertifikate"},
	"firewall": {"icon": "net", "name": "Firewall", "title": "Verion Firewall — Regeln und Abwehr von Angriffen"},
	"monitor": {"icon": "chart", "name": "Monitor", "title": "Verion OS Systemmonitor — Live Rechenzentrum-Monitor"},
	"cams": {"icon": "camera", "name": "Kameras", "title": "Verion SecureView — Live-Bilder der Überwachungsstelen"},
	"staff": {"icon": "people", "name": "Personal", "title": "Personalverwaltung — Team, Löhne & Bewerbungen"},
	"bank": {"icon": "bank", "name": "Bank", "title": "Hanse Direktbank — Geschäftskonto, Kredite & Kontoauszug"},
	"balance": {"icon": "chart", "name": "Bilanz", "title": "Monatsbilanz — Einnahmen, Ausgaben und Ergebnis"},
	"bills": {"icon": "invoice", "name": "Rechnungen", "title": "Rechnungen — Strom, Garagenmiete, Internet & Versicherung"},
}


## Darstellung des PCs: eigene kleine Datei, damit die Spiel-Einstellungen unberührt bleiben.
const PC_DESKTOP_CFG := "user://pc_desktop.cfg"
var _price_overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_load_theme()
	_build_ui()
	GameState.state_updated.connect(_on_state_tick)
	for sig in [GameState.room_level_changed, GameState.van_updated, GameState.racks_changed, GameState.inventory_changed,
			GameState.fuses_changed, GameState.cart_changed, GameState.shelf_changed, GameState.tickets_changed]:
		(sig as Signal).connect(_mark_dirty.bind(["shop", "support", "upgrades", "monitor", "mail"]))
	GameState.event_logged.connect(_on_event_logged)
	MailManager.mails_changed.connect(_mark_dirty.bind(["mail"]))
	MailManager.mail_added.connect(_on_mail_added)
	MailManager.action_result.connect(_on_app_result.bind("mail"))
	MarketManager.market_changed.connect(_mark_dirty.bind(["market", "mail"]))
	MarketManager.action_result.connect(_on_app_result.bind("market"))
	Operations.operations_changed.connect(_mark_dirty.bind(["ops"]))
	Operations.action_result.connect(_on_app_result.bind("ops"))
	Cyber.cyber_changed.connect(_mark_dirty.bind(["firewall", "support"]))
	Cyber.action_result.connect(_on_app_result.bind("firewall"))
	GameState.call_changed.connect(_refresh_call_popup)
	FinanceManager.finance_changed.connect(_on_finance_changed)
	# „Gerade: …“ und liegengebliebene Aufträge im Personal-Fenster aktuell halten.
	TechnicianManager.technician_changed.connect(_mark_dirty.bind(["staff"]))
	FinanceManager.action_result.connect(_on_finance_result)
	visibility_changed.connect(_on_visibility_changed)
	visibility_changed.connect(_close_price_overlay)


func _process(delta: float) -> void:
	if not visible:
		if _last_emitted_typing:
			_last_emitted_typing = false
			typing_state_changed.emit(false)
		return

	if _price_overlay != null and is_instance_valid(_price_overlay) and not _price_overlay.has_meta("vt"):
		VerionTheme.apply(_price_overlay)
		_price_overlay.set_meta("vt", true)
		_price_overlay.add_to_group("verion_overlay")
	_process_dirty(delta)
	if not _scroll_restore.is_empty():
		_apply_scroll_restore()

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

	if _active_app == "support" and not _ticket_status_labels.is_empty():
		_ticket_status_accum += delta
		if _ticket_status_accum >= TICKET_STATUS_REFRESH_INTERVAL:
			_ticket_status_accum = 0.0
			_update_ticket_status_labels()


func _ticket_status_text(t: Dictionary, is_fixed: bool) -> String:
	if is_fixed:
		return tr("BEHOBEN!")
	if bool(t.get("escalated", false)):
		return tr("⏰ ESKALIERT")
	if not bool(t.get("reassured", false)):
		return tr("AKTIV • Antwort in %ds") % ceili(GameState.get_ticket_sla_remaining(t))
	return tr("AKTIV")


## Ändert nur den Text der Status-Labels, damit Entwürfe und Scroll-Position erhalten bleiben.
func _update_ticket_status_labels() -> void:
	for tid in _ticket_status_labels.keys():
		var lbl: Variant = _ticket_status_labels[tid]
		if not is_instance_valid(lbl) or not GameState.support_tickets.has(tid):
			continue
		var t: Dictionary = GameState.support_tickets[tid]
		(lbl as Label).text = _ticket_status_text(t, GameState.is_ticket_issue_fixed(t))


func _input(event: InputEvent) -> void:
	if not visible:
		_mouse_down = false
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
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
	_refresh_dock()
	_refresh_call_popup()
	_mark_dirty(LIVE_APPS)


func _mark_dirty(app_list: Array) -> void:
	if not visible:
		return
	for a in app_list:
		_dirty_apps[str(a)] = true


## Zeichnet geänderte Fenster neu: das vordere schnell, die anderen seltener.
## Solange die Maus gedrückt ist oder jemand in einem Textfeld schreibt, bleibt das Fenster stehen.
func _process_dirty(delta: float) -> void:
	_dirty_accum += delta
	_idle_accum += delta
	if _dirty_apps.is_empty() or _mouse_down:
		return
	var do_active := _dirty_accum >= REFRESH_ACTIVE
	var do_idle := _idle_accum >= REFRESH_IDLE
	if not do_active and not do_idle:
		return
	if do_active:
		_dirty_accum = 0.0
	if do_idle:
		_idle_accum = 0.0
	for a in _desktop.shown_apps():
		if not _dirty_apps.has(a) or _is_busy_typing(a):
			continue
		if (a == _active_app and do_active) or do_idle:
			_render_window(a)


func _is_busy_typing(app: String) -> bool:
	if app == "support" and not _typing_ticket_id.is_empty():
		return true
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit or f is TextEdit):
		return false
	var w := _desktop.window(app)
	return w != null and w.is_ancestor_of(f)


func _on_event_logged(text: String, severity: String) -> void:
	_desktop.add_note(text, severity)


func _on_mail_added(m: Dictionary) -> void:
	if not visible or (_boot_screen != null and _boot_screen.is_running()):
		return
	var id := str(m["id"])
	var cat: Dictionary = MailManager.CATS.get(str(m.get("cat", "system")), {})
	_desktop.toast(str(m["from"]), MailManager.text_of(m["subject"]), str(cat.get("icon", "mail")),
		VerionTheme.BAD if bool(m.get("urgent", false)) else VerionTheme.ACCENT, func():
			_mail_state["folder"] = "all"
			_mail_state["mail"] = id
			_mail_state["msg"] = ""
			MailManager.request_read(id)
			_open_app("mail"))
	SfxManager.play("ticket_notify", -12.0, 1.25)


func _on_app_result(ok: bool, message: String, app: String) -> void:
	var st := _mail_state if app == "mail" else (_ops_state if app == "ops" else (_fw_state if app == "firewall" else _market_state))
	st["msg"] = message
	st["ok"] = ok
	if not ok:
		SfxManager.play("win_error", -8.0)
	_mark_dirty([app])


func open_terminal() -> void:
	GameState.request_mark_checklist_opened_pc()
	_desktop.hide_menus()
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
	# Ein Mitspieler hatte zuletzt eine App offen: hier mit derselben weitermachen.
	if not _active_app.is_empty() and APP_META.has(_active_app) and not _desktop.windows.has(_active_app):
		_desktop.open_window(_active_app)
	_refresh_all()
	_refresh_call_popup()
	SfxManager.play("click", -8.0, 1.1)


func close_terminal() -> void:
	_desktop.hide_menus()
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
		_desktop.close_all()
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
		# Fährt noch hoch (z. B. aufgestanden, bevor das System fertig war): an derselben Stelle weiter.
		_boot_cold = PcScreenState.cold_boot
		_boot_started_msec = now - int(PcScreenState.get_boot_elapsed() * 1000.0)
		_active_app = ""
		PcScreenState.report_local(PcScreenState.PHASE_BOOT, "", _boot_cold, "")
	else:
		# PC ist aus: echter Kaltstart, danach Homescreen ohne offene App.
		_boot_cold = true
		_boot_started_msec = now
		_desktop.close_all()
		_active_app = ""
		PcScreenState.report_local(PcScreenState.PHASE_BOOT, "", true, "")
		SfxManager.play("click", -6.0, 0.6)


## Aufstehen, bevor das Vollbild offen war. Der PC fährt trotzdem fertig hoch und bleibt an.
func cancel_power_on() -> void:
	_boot_started_msec = -1
	PcScreenState.report_local_released()


## Startmenü "Herunterfahren": das System fährt herunter, der Bildschirm wird schwarz, dann steht der Spieler auf.
func _shut_down_pc() -> void:
	if _shutting_down or not _terminal_open or _boot_screen == null:
		return
	_desktop.hide_menus()
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
		_monitor_frame.size = get_viewport_rect().size


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
	if app_id == "":
		_minimize_app()
		return
	if not APP_META.has(app_id):
		return
	var was_open := _desktop.is_shown(app_id)
	# Klick auf das Dock bei der vorderen App legt sie wieder ab.
	if was_open and _active_app == app_id:
		_desktop.minimize(app_id)
		return
	_desktop.open_window(app_id)
	if was_open:
		SfxManager.play_typing_key(-12.0)
	else:
		SfxManager.play("win_open", -10.0)
	_manual_typing_pulse = 0.28
	_render_window(app_id)
	_refresh_dock()
	_report_screen_state()


func _minimize_app() -> void:
	if not _active_app.is_empty():
		_desktop.minimize(_active_app)


func _on_active_changed(app: String) -> void:
	_active_app = app
	_report_screen_state()


func _trigger_quick_save() -> void:
	_desktop.hide_menus()
	if multiplayer.is_server():
		GameState.save_current_world("", false)
		_desktop.toast(tr("Gespeichert!"), "", "save", VerionTheme.GOOD)
		SfxManager.play("cash", -10.0, 1.2)
	else:
		_desktop.toast(tr("Nur Host kann speichern"), "", "warn", VerionTheme.WARN)


func _on_finance_changed() -> void:
	_mark_dirty(["staff", "bank", "bills", "mail"])


func _on_finance_result(ok: bool, message: String) -> void:
	_fin_msg = message
	_fin_msg_ok = ok
	if not ok:
		SfxManager.play("win_error", -8.0)
	_mark_dirty(FINANCE_APPS)
	if _active_app == "mail":
		_on_app_result(ok, message, "mail")


## Alle sichtbaren Fenster sofort neu zeichnen.
func _refresh_all() -> void:
	if not visible:
		return
	_report_screen_state()
	_refresh_dock()
	_refresh_call_popup()
	for a in _desktop.shown_apps():
		_render_window(a)


func _render_window(app: String) -> void:
	var w := _desktop.window(app)
	if w == null:
		return
	_dirty_apps.erase(app)
	w.needs_render = false
	var meta: Dictionary = APP_META[app]
	var parts := tr(str(meta["title"])).split(" — ", true, 1)
	w.set_title(parts[0], parts[1] if parts.size() > 1 else "", str(meta["icon"]))
	var scrolls: Array[int] = []
	var pending: Array = (_scroll_restore.get(app, {}) as Dictionary).get("vals", [])
	for sc in w.body.find_children("*", "ScrollContainer", true, false):
		var v := (sc as ScrollContainer).scroll_vertical
		# Läuft das Zurücksetzen vom letzten Neuzeichnen noch, gilt dessen Ziel.
		if scrolls.size() < pending.size():
			v = maxi(v, int(pending[scrolls.size()]))
		scrolls.append(v)
	for c in w.body.get_children():
		w.body.remove_child(c)
		c.queue_free()
	_app_body_host = w.body
	match app:
		"mail":
			MailApp.render(w.body, _mail_state, _mark_dirty.bind(["mail"]), _open_app)
		"market":
			MarketApp.render(w.body, _market_state, _mark_dirty.bind(["market"]))
		"ops":
			OperationsApp.render(w.body, _ops_state, _mark_dirty.bind(["ops"]))
		"firewall":
			FirewallApp.render(w.body, _fw_state, _mark_dirty.bind(["firewall"]))
		"shop":
			_render_shop_app()
		"support":
			_render_support_hub_app()
		"upgrades":
			_render_upgrades_app()
		"monitor":
			_render_monitor_app()
		"cams":
			CameraApp.render(w.body, _cams_state)
		"staff":
			FinanceApps.render_staff(w.body, _fin_msg, _fin_msg_ok)
		"bank":
			FinanceApps.render_bank(w.body, _fin_msg, _fin_msg_ok)
		"balance":
			FinanceApps.render_balance(w.body, _fin_msg, _fin_msg_ok)
		"bills":
			FinanceApps.render_bills(w.body, _fin_msg, _fin_msg_ok)
	VerionTheme.apply(w.body)
	# Scrollstellung behalten. Der Balken kennt seine Länge erst nach dem Layout, daher vorher weit aufmachen.
	var i := 0
	for sc_n in w.body.find_children("*", "ScrollContainer", true, false):
		if i < scrolls.size() and scrolls[i] > 0:
			var sc := sc_n as ScrollContainer
			sc.get_v_scroll_bar().max_value = maxf(sc.get_v_scroll_bar().max_value, 100000.0)
			sc.scroll_vertical = scrolls[i]
		i += 1
	if scrolls.any(func(v: int) -> bool: return v > 0):
		_scroll_restore[app] = {"vals": scrolls, "frames": 12}


## Setzt gemerkte Scrollstellungen erneut, bis die neu gebaute Liste lang genug ist.
func _apply_scroll_restore() -> void:
	for app in _scroll_restore.keys():
		var r: Dictionary = _scroll_restore[app]
		var w := _desktop.window(app) if _desktop != null else null
		r["frames"] = int(r["frames"]) - 1
		if w == null or int(r["frames"]) < 0:
			_scroll_restore.erase(app)
			continue
		var vals: Array = r["vals"]
		var i := 0
		for sc_n in w.body.find_children("*", "ScrollContainer", true, false):
			if i < vals.size() and int(vals[i]) > 0:
				var sc := sc_n as ScrollContainer
				if sc.scroll_vertical != int(vals[i]):
					sc.scroll_vertical = int(vals[i])
			i += 1


func _refresh_tray() -> void:
	if _desktop != null:
		_desktop.refresh_tray()


func _refresh_dock() -> void:
	_refresh_tray()
	var open_t := GameState.get_open_ticket_count()
	var has_call := not GameState.active_call.is_empty()
	var cart_n := _get_cart_item_count()
	_desktop.set_badge("support", maxi(open_t, 1 if has_call else 0), "phone" if has_call else "headset")
	_desktop.set_badge("shop", cart_n)
	_desktop.set_badge("mail", MailManager.get_unread_count())
	_desktop.set_badge("cams", 1 if not DecorManager.thief.is_empty() and DecorManager.has_camera(Vector3(0.0, 0.0, 6.0)) else 0)
	_desktop.set_badge("bills", FinanceManager.get_dunning_count())
	_desktop.set_badge("market", MarketManager.leads.size() + (1 if not MarketManager.poach.is_empty() else 0))


func _refresh_call_popup() -> void:
	if _call_popup == null:
		return
	var call_d := GameState.active_call
	if call_d.is_empty():
		_call_popup.visible = false
		return
	var key := "%s|%s" % [str(call_d.get("id", "")), str(call_d.get("state", ""))]
	if _call_popup.visible and str(_call_popup.get_meta("key", "")) == key:
		return
	_call_popup.set_meta("key", key)
	_call_popup.visible = true
	_clear_children(_call_body)
	VerionTheme.apply.call_deferred(_call_body)

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
# SHOPPING CART HELPERS (geteilt über GameState.shopping_cart mit Rack-Konfigurator)
# ==============================================================================
func _cart_add(kind: String, id: String, cat: String, display_name: String, price: int, amount: int = 1) -> void:
	GameState.cart_add_entry(kind, id, cat, display_name, price, amount)
	SfxManager.play_typing_key(-11.0)
	_manual_typing_pulse = 0.25
	_refresh_all()


func _cart_delta(key: String, delta_n: int) -> void:
	GameState.cart_change_qty(key, delta_n)
	SfxManager.play("click", -12.0, 0.95)
	_refresh_all()


func _get_cart_total() -> int:
	return GameState.get_cart_total()


func _get_cart_item_count() -> int:
	return GameState.get_cart_count()


var _cart_express_delivery: bool = false


func _checkout_cart() -> void:
	if GameState.shopping_cart.is_empty():
		return
	var preview := GameState.preview_cart_delivery(GameState.shopping_cart)
	var cart_tier := int(preview["tier"])
	var shipping_fee := GameState.get_delivery_fee(cart_tier, _cart_express_delivery)
	var total := _get_cart_total() + shipping_fee
	if GameState.money < float(total):
		SfxManager.play("error", -8.0)
		return
	if int(preview["crates"]) > GameState.get_delivery_zone_free_slots():
		SfxManager.play("error", -8.0)
		return
	var payload: Array = []
	for item in GameState.shopping_cart:
		var d: Dictionary = item
		if str(d.get("kind", "")) == "slot_build":
			payload.append({
				"kind": "slot_build",
				"rack_id": str(d.get("rack_id", "")),
				"slot_idx": int(d.get("slot_idx", 0)),
				"rack_label": str(d.get("rack_label", "Rack")),
				"mainboard_id": str(d.get("mainboard_id", "")),
				"components": (d.get("components", {}) as Dictionary).duplicate(true),
				"qty": 1,
			})
		else:
			payload.append({"kind": str(d["kind"]), "id": str(d["id"]), "cat": str(d["cat"]), "qty": int(d["qty"])})
	GameState.cart_clear()
	SfxManager.play_typing_key(-9.0)
	GameState.request_checkout_cart(payload, _cart_express_delivery)
	_refresh_all()


# ==============================================================================
# APP 1: HARDWARE SHOP (CLOUDPARTS.DE) + REAL SHOPPING CART + TEILE-LAGER!
# ==============================================================================
## Sicherungen kommen mit dem Lieferwagen im Sammelpaket und landen dann im Lager.
func _add_fuse_shop_card(list: VBoxContainer) -> void:
	var fuse_name := "Schraubsicherung 63 A (Sicherungskasten)"
	_add_shop_item_card(list, {
		"title": tr(fuse_name),
		"desc": tr("Lieferung per Lieferwagen im Sammelpaket. Danach am Sicherungskasten mit [E] in einen leeren oder durchgebrannten Steckplatz stecken."),
		"info": tr("Im Lager: %d  •  Intakt im Kasten: %d / %d") % [GameState.fuse_stock, GameState.count_working_fuses(), GameState.FUSE_SLOT_COUNT],
		"color": Color(0.86, 0.70, 0.36),
		"price": GameState.FUSE_PRICE,
		"on_buy": func(): _cart_add("acc", "fuse", "", fuse_name, GameState.FUSE_PRICE),
	})


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

	# Bauteile: 3D-Vorschau, ein Klick nimmt das Teil groß in die Hand.
	var part_id := str(opts.get("part_id", ""))
	if PartModels.has_product(part_id):
		var tb := TextureButton.new()
		tb.texture_normal = PartThumbs.get_texture(part_id)
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(84, 62)
		tb.focus_mode = Control.FOCUS_NONE
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tb.tooltip_text = tr("In 3D ansehen")
		tb.pressed.connect(func(): PartViewer.open(self, [part_id]))
		row.add_child(tb)

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
		badge_txt = tr("Sofort verfügbar") if instant else tr("Lieferung per Lieferwagen")
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
	var on_buy_bulk: Callable = opts.get("on_buy_bulk", Callable())
	if on_buy_bulk.is_valid():
		var bbulk := Button.new()
		bbulk.text = str(opts.get("bulk_text", tr("+ 6er-Kiste")))
		bbulk.custom_minimum_size = Vector2(140, 26)
		bbulk.disabled = is_disabled
		bbulk.add_theme_font_size_override("font_size", 11)
		_style_win_btn(bbulk, Color(0.14, 0.56, 0.36), Color(0.10, 0.44, 0.28), Color.WHITE)
		bbulk.pressed.connect(func():
			if on_buy_bulk.is_valid():
				on_buy_bulk.call()
		)
		buy_col.add_child(bbulk)


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
		{"id": "kits", "label": "Reparatur-Kits"},
		{"id": "infra", "label": "Klima & USV"},
		{"id": "deals", "label": "Gebrauchtmarkt"},
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
		tl.text = "START-TIPP: Lege 1× Server-Rack (4U) in den Warenkorb → Bestellen → der Cloud-Express-Lieferwagen liefert es. Am Rack drückst du [E], klickst einen freien Einschub an und wählst mit der Maus dein Mainboard. CPU, RAM, GPU, SSD & Co. kaufst du danach direkt im Einschub."
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.add_theme_font_size_override("font_size", 11.5)
		tl.modulate = Color(0.12, 0.38, 0.18)
		tip.add_child(tl)

	if _shop_tab == "chassis":
		_add_shop_section(left_list, tr("Server-Racks"), tr("Gehäuse für deine Einschübe. Lieferung per Lieferwagen."))
		_populate_physical_shop_list(left_list, ["rack", "rack_pro"])
		_add_shop_section(left_list, tr("Netzwerk"), tr("Switches für mehr Netzwerk-Ports im Rack."))
		_populate_physical_shop_list(left_list, ["net_switch"])
	elif _shop_tab == "kits":
		_add_shop_section(left_list, tr("Wartungs- & Reinigungs-Kits (Druckluft & Wärmeleitpaste)"), tr("Vorrat: %d / 12 Kits • Für vorbeugende Wartung & 2,2× schnellere Reparaturen.") % GameState.maint_kits)
		_add_shop_item_card(left_list, {
			"title": tr("+3 Wartungs- & Ersatzteil-Kits (Sofort-Vorrat)"),
			"desc": tr("Senkt Ausfallrisiko durch Staub-Reinigung & Wärmeleitpaste fast auf 0 %. Mit Ersatzteil-Schrank nur $20!"),
			"info": tr("Aktueller Vorrat: %d / 12 Kits") % GameState.maint_kits,
			"color": Color(0.18, 0.72, 0.56),
			"price": 45,
			"on_buy": func():
				GameState.request_refill_maint_kits()
				_refresh_all(),
		})
		_add_shop_section(left_list, tr("Werkbank-Material"), tr("Schrauben und Wärmeleitpaste für Zusammenbau und Reparatur. Lieferung per Lieferwagen."))
		_add_shop_item_card(left_list, {
			"title": tr("Schraubensortiment (%d Stück)") % GameState.SCREW_BOX_COUNT,
			"desc": tr("M3- und M.2-Schrauben. Beim Ausbauen gelöste Schrauben landen wieder in der Schale."),
			"info": tr("Vorrat an der Werkbank: %d Schrauben") % GameState.bench_screws,
			"color": Color(0.46, 0.52, 0.60),
			"price": GameState.SCREW_BOX_PRICE,
			"on_buy": func(): _cart_add("acc", "screw_box", "", "Schraubensortiment", GameState.SCREW_BOX_PRICE),
		})
		_add_shop_item_card(left_list, {
			"title": tr("Wärmeleitpaste (%d Anwendungen)") % int(GameState.PASTE_TUBE_USES),
			"desc": tr("Für jeden CPU-Kühler. Im CPU-Reparatur-Kit liegt eine kleine Tube bei."),
			"info": tr("Vorrat an der Werkbank: %.1f Anwendungen") % GameState.bench_paste,
			"color": Color(0.62, 0.64, 0.68),
			"price": GameState.PASTE_TUBE_PRICE,
			"on_buy": func(): _cart_add("acc", "paste_tube", "", "Wärmeleitpaste", GameState.PASTE_TUBE_PRICE),
		})
		_add_shop_section(left_list, tr("Profi-Werkzeug"), tr("Einmal kaufen, für alle an der Werkbank. Auch Techniker arbeiten damit besser."))
		for tid_v in GameState.BENCH_TOOLS.keys():
			var tid := str(tid_v)
			var td: Dictionary = GameState.BENCH_TOOLS[tid]
			var owned: bool = GameState.has_bench_tool(tid)
			var need := str(td.get("needs", ""))
			var locked: bool = need != "" and not GameState.has_bench_tool(need)
			var tname := str(td["name"])
			var tprice := int(td["price"])
			_add_shop_item_card(left_list, {
				"title": tr(tname),
				"desc": tr(str(td["desc"])),
				"info": tr("Vorhanden") if owned else (tr("Braucht: %s") % tr(str(GameState.BENCH_TOOLS[need]["name"])) if locked else tr("Lieferung per Lieferwagen")),
				"color": Color(0.80, 0.52, 0.18),
				"price": tprice,
				"disabled": owned or locked,
				"btn_text": tr("Vorhanden") if owned else (tr("Gesperrt") if locked else ""),
				"on_buy": func(): _cart_add("acc", "tool_" + tid, "", tname, tprice),
			})
		_add_shop_section(left_list, tr("Werkstatt-Spar-Bundle"), tr("Alle 7 Reparatur-Kits im Paket — Lieferung per Lieferwagen zum Einlagern im Regal."))
		_populate_physical_shop_list(left_list, ["kit_bundle_all"])
		_add_shop_section(left_list, tr("Einzelne Reparatur-Kits"), tr("Für Reparaturen an der 3D-Werkbank. Mehrere Kits gleicher Art kommen automatisch in platzsparenden 6er-Mengen-Kisten!"))
		for kid in GameState.REPAIR_KIT_ORDER:
			var kd: Dictionary = GameState.ITEM_CATALOG[kid]
			var kcat := str(kd.get("kit_cat", ""))
			var stock_n := GameState.count_repair_kits(kcat)
			var cap_kid := str(kid)
			var cap_kname := str(kd["name"])
			var cap_kprice := int(kd["price"])
			_add_shop_item_card(left_list, {
				"title": cap_kname,
				"desc": str(kd["desc"]),
				"info": tr("Vorrat im Lager/Halle: %d Stück") % stock_n,
				"color": kd["color"],
				"price": cap_kprice,
				"on_buy": func(): _cart_add("item", cap_kid, "repair_kit", cap_kname, cap_kprice, 1),
				"on_buy_bulk": func(): _cart_add("item", cap_kid, "repair_kit", cap_kname, cap_kprice, GameState.BULK_PACK_MAX),
				"bulk_text": tr("+ %der-Kiste ($%d)") % [GameState.BULK_PACK_MAX, cap_kprice * GameState.BULK_PACK_MAX],
			})
	elif _shop_tab == "infra":
		_add_shop_section(left_list, tr("Kühlung"), tr("Hält die Raumtemperatur unter Kontrolle."))
		_populate_physical_shop_list(left_list, ["cooler", "chiller", "indoor_unit", "cool_k90", "cool_inrow", "cool_tower", "cool_cdu"])
		_add_shop_section(left_list, tr("Stromversorgung"), tr("Der Stromkasten hat nur eine Steckdose: mit Stromleisten verteilst du weiter."))
		_populate_physical_shop_list(left_list, ["prop_power_strip", "ups", "ups_cabinet", "ups_container"])
		_add_fuse_shop_card(left_list)
		_add_shop_section(left_list, tr("Netzwerk-Zubehör"), tr("Mehr Netzwerkdosen über LAN-Leisten."))
		_populate_physical_shop_list(left_list, ["prop_lan_strip"])
		_add_shop_section(left_list, tr("Lagerregale"), tr("Drei Größen. Regale rasten an Wänden und aneinander ein, jede Ware braucht ihren echten Platz."))
		_populate_physical_shop_list(left_list, ["prop_shelf_small", "prop_storage_shelf", "prop_pallet_rack"])
		_add_shop_section(left_list, tr("Werkstatt & Technik"), tr("Zweite Werkbank, Ersatzteile, Kaltgang, Kameras und Luftentfeuchter."))
		_populate_physical_shop_list(left_list, [
			"prop_esd_workbench", "prop_parts_cabinet", "prop_tool_cart", "prop_cold_aisle_gate", "prop_cctv_monitor", "prop_dehumidifier",
		])
		_add_shop_section(left_list, tr("Pausenraum & Außenwirkung"), tr("Mit [E] benutzen. Macht dich und dein Team schneller und hebt den Ruf."))
		_populate_physical_shop_list(left_list, ["prop_vending_lounge", "prop_water", "prop_sofa", "prop_logo_sign"])
	elif _shop_tab == "deals":
		_add_shop_section(left_list, tr("Gebrauchtmarkt & Firmenauflösungen (Tag %d)") % GameState.day_number, tr("Täglich wechselnde B-Ware mit 35–45 % Rabatt! Nur einmal pro Angebot verfügbar."))
		if GameState.daily_deals.is_empty():
			var empty_l := Label.new()
			empty_l.text = tr("Heute sind noch keine Angebote eingetroffen.")
			empty_l.modulate = Color(0.35, 0.38, 0.44)
			left_list.add_child(empty_l)
		else:
			for d_v in GameState.daily_deals:
				var deal: Dictionary = d_v
				var did := str(deal.get("deal_id", ""))
				var sold := bool(deal.get("sold", false))
				var price := int(deal.get("price", 0))
				var orig := int(deal.get("orig_price", price))
				var disc := int(deal.get("discount_pct", 35))
				var card := _make_light_card(
					Color(0.94, 0.95, 0.96) if sold else Color(1.0, 0.99, 0.95),
					Color(0.76, 0.78, 0.82) if sold else Color(0.88, 0.66, 0.22),
					6, 12, 9
				)
				left_list.add_child(card)
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 12)
				card.add_child(h)
				var info_v := VBoxContainer.new()
				info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				info_v.add_theme_constant_override("separation", 2)
				h.add_child(info_v)
				var t_lbl := Label.new()
				t_lbl.text = "%s   [-%d%%]" % [str(deal.get("name", "B-Ware")), disc]
				t_lbl.add_theme_font_size_override("font_size", 13)
				t_lbl.modulate = Color(0.45, 0.48, 0.52) if sold else Color(0.12, 0.14, 0.18)
				info_v.add_child(t_lbl)
				var s_lbl := Label.new()
				s_lbl.text = tr("Anbieter: %s  •  Neupreis: $%d") % [str(deal.get("seller", "")), orig]
				s_lbl.add_theme_font_size_override("font_size", 11)
				s_lbl.modulate = Color(0.36, 0.40, 0.46)
				info_v.add_child(s_lbl)
				var bbtn := Button.new()
				bbtn.text = tr("VERKAUFT") if sold else tr("Kaufen ($%d)") % price
				bbtn.disabled = sold or GameState.money < float(price)
				bbtn.custom_minimum_size = Vector2(132, 32)
				_style_win_btn(
					bbtn,
					Color(0.78, 0.80, 0.84) if bbtn.disabled else Color(0.16, 0.56, 0.30),
					Color(0.65, 0.68, 0.72) if bbtn.disabled else Color(0.12, 0.44, 0.22),
					Color(0.36, 0.38, 0.42) if bbtn.disabled else Color.WHITE
				)
				var cap_did := did
				bbtn.pressed.connect(func():
					GameState.request_buy_daily_deal(cap_did)
					_refresh_all()
				)
				h.add_child(bbtn)
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

	if GameState.shopping_cart.is_empty():
		var ce := Label.new()
		ce.text = tr("Dein Warenkorb ist leer.") + "\n\n" + tr("Sammle links Racks & Reparatur-Kits oder konfiguriere am Rack einen Slot für den Warenkorb — alles kommt per Lieferwagen!")
		ce.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ce.add_theme_font_size_override("font_size", 11.5)
		ce.modulate = Color(0.42, 0.46, 0.54)
		clist.add_child(ce)
	else:
		for item in GameState.shopping_cart:
			var d: Dictionary = item
			var is_build := str(d.get("kind", "")) == "slot_build"
			var row_c := _make_light_card(Color(0.95, 0.98, 1.0) if is_build else Color.WHITE, Color(0.45, 0.68, 0.92) if is_build else Color(0.84, 0.87, 0.91), 5, 8, 5)
			clist.add_child(row_c)
			var rv := VBoxContainer.new()
			rv.add_theme_constant_override("separation", 3)
			row_c.add_child(rv)
			var nl := Label.new()
			nl.text = ("📦 " if is_build else "") + tr(str(d["name"]))
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.add_theme_font_size_override("font_size", 11.5)
			nl.modulate = Color(0.08, 0.24, 0.48) if is_build else Color(0.12, 0.14, 0.18)
			rv.add_child(nl)
			if is_build:
				var sub_b := Label.new()
				sub_b.text = tr("Bausatz-Karton → an der Werkbank zusammenbauen")
				sub_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sub_b.add_theme_font_size_override("font_size", 10)
				sub_b.modulate = Color(0.32, 0.44, 0.58)
				rv.add_child(sub_b)

			var brow := HBoxContainer.new()
			brow.add_theme_constant_override("separation", 4)
			rv.add_child(brow)
			var qty_n := int(d["qty"])
			var bulk_hint := ""
			if str(d.get("kind", "")) == "item" and GameState.is_bulk_packable(str(d.get("id", ""))) and qty_n > 1:
				var boxes := ceili(float(qty_n) / float(GameState.BULK_PACK_MAX))
				bulk_hint = " (%d %s)" % [boxes, tr("Kiste") if boxes == 1 else tr("Kisten")]
			var pl := Label.new()
			pl.text = "%d×%s  •  $%d" % [qty_n, bulk_hint, int(d["price"]) * qty_n]
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pl.add_theme_font_size_override("font_size", 11)
			pl.modulate = Color(0.16, 0.46, 0.26)
			brow.add_child(pl)

			var cap_k := str(d["key"])
			var bm := Button.new()
			bm.text = "✕" if is_build else "−"
			bm.custom_minimum_size = Vector2(24, 22)
			_style_win_btn(bm, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.84), Color(0.20, 0.22, 0.26))
			bm.pressed.connect(func(): _cart_delta(cap_k, -1))
			brow.add_child(bm)

			if not is_build:
				var bp := Button.new()
				bp.text = "+"
				bp.custom_minimum_size = Vector2(24, 22)
				_style_win_btn(bp, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.84), Color(0.20, 0.22, 0.26))
				bp.pressed.connect(func(): _cart_delta(cap_k, 1))
				brow.add_child(bp)

	cv.add_child(HSeparator.new())
	# Live-Anzeige für Liefer-Kategorie (Stufe 1/2/3) & Lieferflächen-Limit (max. 16 Plätze)
	var delivery_preview := GameState.preview_cart_delivery(GameState.shopping_cart)
	var cart_crates := int(delivery_preview["crates"])
	var cart_tier := int(delivery_preview["tier"])
	var used_zone := GameState.get_delivery_zone_used_slots()
	var max_zone := GameState.DELIVERY_ZONE_MAX_CRATES
	var over_limit := (used_zone + cart_crates) > max_zone

	if not GameState.shopping_cart.is_empty():
		var tmeta: Dictionary = GameState.DELIVERY_TIER_META.get(cart_tier, GameState.DELIVERY_TIER_META[1])
		var tier_bg := Color(0.92, 0.96, 1.0) if cart_tier == 1 else (Color(1.0, 0.96, 0.88) if cart_tier == 2 else Color(0.96, 0.92, 1.0))
		var tier_bd := Color(0.36, 0.64, 0.92) if cart_tier == 1 else (Color(0.88, 0.56, 0.14) if cart_tier == 2 else Color(0.58, 0.34, 0.88))
		var tier_card := _make_light_card(tier_bg, tier_bd, 6, 8, 6)
		cv.add_child(tier_card)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 2)
		tier_card.add_child(tv)
		var tl1 := Label.new()
		tl1.text = "%s Stufe %d: %s" % [str(tmeta["icon"]), cart_tier, str(tmeta["name"])]
		tl1.add_theme_font_size_override("font_size", 12)
		tl1.modulate = Color(0.10, 0.22, 0.42)
		tv.add_child(tl1)
		var tl2 := Label.new()
		tl2.text = "%s · %d %s" % [str(tmeta["method"]), int(delivery_preview["total_packages"]), tr("Paket") if int(delivery_preview["total_packages"]) == 1 else tr("Pakete")]
		tl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl2.add_theme_font_size_override("font_size", 10.5)
		tl2.modulate = Color(0.28, 0.34, 0.44)
		tv.add_child(tl2)

	var zone_box := VBoxContainer.new()
	zone_box.add_theme_constant_override("separation", 3)
	cv.add_child(zone_box)
	var zone_lbl := Label.new()
	if cart_crates > 0:
		zone_lbl.text = tr("Lieferfläche: %d + %d / %d Plätze") % [used_zone, cart_crates, max_zone]
	else:
		zone_lbl.text = tr("Lieferfläche: %d / %d Plätze belegt") % [used_zone, max_zone]
	zone_lbl.add_theme_font_size_override("font_size", 11)
	zone_lbl.modulate = Color(0.80, 0.14, 0.12) if over_limit else (Color(0.76, 0.48, 0.06) if used_zone + cart_crates >= max_zone - 3 else Color(0.22, 0.44, 0.28))
	zone_box.add_child(zone_lbl)

	var zpb := ProgressBar.new()
	zpb.show_percentage = false
	zpb.min_value = 0.0
	zpb.max_value = float(max_zone)
	zpb.value = minf(float(used_zone + cart_crates), float(max_zone))
	zpb.custom_minimum_size = Vector2(0, 7)
	var zbg := StyleBoxFlat.new()
	zbg.bg_color = Color(0.86, 0.88, 0.92)
	zbg.set_corner_radius_all(3)
	var zfill := StyleBoxFlat.new()
	zfill.bg_color = Color(0.86, 0.20, 0.18) if over_limit else (Color(0.92, 0.62, 0.12) if used_zone + cart_crates >= max_zone - 3 else Color(0.18, 0.68, 0.40))
	zfill.set_corner_radius_all(3)
	zpb.add_theme_stylebox_override("background", zbg)
	zpb.add_theme_stylebox_override("fill", zfill)
	zone_box.add_child(zpb)

	var subtotal := _get_cart_total()
	var shipping_fee := 0 if GameState.shopping_cart.is_empty() else GameState.get_delivery_fee(cart_tier, _cart_express_delivery)
	var tot := subtotal + shipping_fee

	# Lieferzeit-Auswahl (Feste Lieferfenster 08:00/12:00/16:00/20:00 vs. Sofort-Express)
	if not GameState.shopping_cart.is_empty():
		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override("separation", 6)
		cv.add_child(slot_row)
		var btn_std := Button.new()
		btn_std.text = tr("Zeitfenster %s ($%d)") % [GameState.get_next_delivery_slot_label(), GameState.get_delivery_fee(cart_tier, false)]
		btn_std.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_std.custom_minimum_size = Vector2(0, 28)
		btn_std.add_theme_font_size_override("font_size", 10.5)
		_style_win_btn(
			btn_std,
			Color(0.14, 0.50, 0.84) if not _cart_express_delivery else Color(0.92, 0.94, 0.96),
			Color(0.10, 0.40, 0.72),
			Color.WHITE if not _cart_express_delivery else Color(0.24, 0.28, 0.36)
		)
		btn_std.pressed.connect(func():
			_cart_express_delivery = false
			_refresh_all()
		)
		slot_row.add_child(btn_std)

		var btn_exp := Button.new()
		btn_exp.text = tr("⚡ Sofort-Express (+$%d)") % GameState.DELIVERY_EXPRESS_SURCHARGE
		btn_exp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_exp.custom_minimum_size = Vector2(0, 28)
		btn_exp.add_theme_font_size_override("font_size", 10.5)
		_style_win_btn(
			btn_exp,
			Color(0.86, 0.46, 0.08) if _cart_express_delivery else Color(0.92, 0.94, 0.96),
			Color(0.72, 0.36, 0.06),
			Color.WHITE if _cart_express_delivery else Color(0.24, 0.28, 0.36)
		)
		btn_exp.pressed.connect(func():
			_cart_express_delivery = true
			_refresh_all()
		)
		slot_row.add_child(btn_exp)

		var fee_lbl := Label.new()
		fee_lbl.text = tr("Warenwert: $%d  •  Lieferkosten: $%d  •  Lieferzeiten: 08 / 12 / 16 / 20 Uhr") % [subtotal, shipping_fee]
		fee_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fee_lbl.add_theme_font_size_override("font_size", 10.5)
		fee_lbl.modulate = Color(0.32, 0.38, 0.48)
		cv.add_child(fee_lbl)

	if GameState.pending_delivery_count > 0 and GameState.van_phase == "idle":
		var wait_lbl := Label.new()
		wait_lbl.text = tr("🕒 %d Paket(e) geplant für Lieferfenster: %s") % [GameState.pending_delivery_count, GameState.get_scheduled_delivery_label()]
		wait_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wait_lbl.add_theme_font_size_override("font_size", 11)
		wait_lbl.modulate = Color(0.14, 0.44, 0.72)
		cv.add_child(wait_lbl)

	var tot_lbl := Label.new()
	tot_lbl.text = tr("Gesamtsumme:  $%d") % tot
	tot_lbl.add_theme_font_size_override("font_size", 14)
	tot_lbl.modulate = Color(0.78, 0.16, 0.14) if GameState.money < float(tot) else Color(0.10, 0.44, 0.24)
	cv.add_child(tot_lbl)

	var order_btn := Button.new()
	if GameState.shopping_cart.is_empty():
		order_btn.text = tr("Warenkorb leer")
	elif over_limit:
		order_btn.text = tr("Lieferfläche voll! (%d/%d)") % [used_zone + cart_crates, max_zone]
	else:
		order_btn.text = " " + tr("Alles bestellen ($%d)") % tot
	order_btn.custom_minimum_size = Vector2(0, 40)
	order_btn.disabled = GameState.shopping_cart.is_empty() or GameState.money < float(tot) or over_limit
	_style_win_btn(
		order_btn,
		Color(0.10, 0.48, 0.84) if not order_btn.disabled else Color(0.84, 0.86, 0.89),
		Color(0.08, 0.38, 0.70),
		Color.WHITE if not order_btn.disabled else Color(0.45, 0.48, 0.52)
	)
	order_btn.pressed.connect(_checkout_cart)
	cv.add_child(order_btn)

	if not GameState.shopping_cart.is_empty():
		var clr_btn := Button.new()
		clr_btn.text = "Warenkorb leeren"
		clr_btn.custom_minimum_size = Vector2(0, 26)
		clr_btn.add_theme_font_size_override("font_size", 11)
		_style_win_btn(clr_btn, Color(0.92, 0.93, 0.95), Color(0.78, 0.81, 0.86), Color(0.26, 0.28, 0.34))
		clr_btn.pressed.connect(func():
			GameState.cart_clear()
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
		var cap_p := GameState.get_discounted_price(float(cat["price"]))
		var unlocked := GameState.is_item_unlocked(cap_it)
		var req_lvl := GameState.get_item_required_level(cap_it)
		var card_opts := {
			"title": tr(cap_n),
			"desc": tr(str(cat.get("desc", ""))),
			"color": cat.get("color", Color(0.46, 0.50, 0.56)),
			"price": cap_p,
			"on_buy": func(): _cart_add("item", cap_it, "", cap_n, cap_p, 1),
		}
		if not unlocked:
			card_opts["disabled"] = true
			card_opts["btn_text"] = tr("🔒 Ab Firmenstufe %d") % req_lvl
		elif GameState.is_bulk_packable(cap_it):
			card_opts["on_buy_bulk"] = func(): _cart_add("item", cap_it, "", cap_n, cap_p, GameState.BULK_PACK_MAX)
			card_opts["bulk_text"] = tr("+ %der-Kiste ($%d)") % [GameState.BULK_PACK_MAX, cap_p * GameState.BULK_PACK_MAX]
		_add_shop_item_card(parent, card_opts)


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
		var card_opts := {
			"title": ("[%s]  %s" % [tag, cap_name]) if tag != "" else cap_name,
			"info": (tr("Im Lager: %d×") % stock) if stock > 0 else "",
			"color": _part_accent(cap_cat),
			"part_id": cap_pid,
			"price": cap_cost,
			"strength_pct": HardwareCatalog.get_part_strength_pct(cap_cat, pd),
			"specs": _format_part_specs_short(cap_cat, pd),
			"on_buy": func(): _cart_add("part", cap_pid, cap_cat, cap_name, cap_cost),
		}
		# Gesperrte Teile bleiben sichtbar, damit man sieht, was spätere Firmenstufen bringen.
		if not GameState.is_part_unlocked(pd):
			card_opts["disabled"] = true
			card_opts["btn_text"] = tr("🔒 Ab Firmenstufe %d") % GameState.get_part_required_level(pd)
		_add_shop_item_card(parent, card_opts)


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
				"part_id": pid,
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
		{"id": "contracts", "label": tr("Großkunden-Verträge (%d/%d)") % [GameState.get_active_contract_count(), GameState.get_max_contracts_limit()]},
		{"id": "career", "label": tr("Karriere & Team (%d/%d)") % [GameState.career_completed.size(), GameState.CAREER_MILESTONES.size()]},
		{"id": "ai", "label": tr("AI-Cluster & Firewall") + (" (" + tr("Angriff!") + ")" if not Cyber.attack.is_empty() else "")},
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
	elif _support_tab == "career":
		_render_career_subtab(content)
	else:
		_render_ai_firewall_subtab(content)


func _render_career_subtab(content: VBoxContainer) -> void:
	# 1. Aktiver Co-op Team-Auftrag + Betriebs-Boni (Airflow, Kabelmanagement, Wetter)
	var team_card := _make_light_card(Color(0.94, 0.97, 1.0), Color(0.24, 0.56, 0.86), 6, 12, 10)
	content.add_child(team_card)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 5)
	team_card.add_child(tv)

	var o := GameState.active_team_order
	var ot := Label.new()
	if not o.is_empty():
		var done := bool(o.get("done", false))
		var prog := float(o.get("progress", 0.0))
		var targ := maxf(1.0, float(o.get("target", 1.0)))
		ot.text = ("%s  —  %s  (Prämie: +$%d)" % [
			str(o.get("title", "")),
			tr("ABGESCHLOSSEN!") if done else ("%d / %d" % [int(prog), int(targ)]),
			int(o.get("reward", 0))
		])
		ot.modulate = Color(0.12, 0.48, 0.22) if done else Color(0.10, 0.24, 0.46)
	else:
		ot.text = tr("Kein aktiver Team-Auftrag.")
		ot.modulate = Color(0.32, 0.36, 0.42)
	ot.add_theme_font_size_override("font_size", 13)
	tv.add_child(ot)

	var bonus_lbl := Label.new()
	bonus_lbl.text = tr("Wetter: %s  •  Kaltgang-Airflow: +%d%% Kühlung  •  Kabelmanagement: +%d%% Ruf-/Umsatz-Bonus") % [
		GameState.get_weather_label(),
		int(roundf(GameState.airflow_bonus * 100.0)),
		int(roundf(GameState.cable_mgmt_bonus * 100.0)),
	]
	bonus_lbl.add_theme_font_size_override("font_size", 11.5)
	bonus_lbl.modulate = Color(0.24, 0.32, 0.44)
	tv.add_child(bonus_lbl)

	# 2. Firmenstufe & Meilenstein-Boni Übersicht (Level 1 bis 10)
	var cur_lvl := GameState.get_company_level()
	var lvl_card := _make_light_card(Color(0.94, 0.96, 1.0), Color(0.28, 0.52, 0.86), 7, 14, 10)
	content.add_child(lvl_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lvl_card.add_child(lv)
	var l_head := Label.new()
	var cur_val := GameState.get_company_value()
	var next_thr := int(GameState.COMPANY_LEVEL_THRESHOLDS[mini(cur_lvl, GameState.COMPANY_LEVEL_THRESHOLDS.size() - 1)])
	l_head.text = tr("FIRMENSTUFE %d / 10  •  Firmenwert: $%d%s") % [
		cur_lvl, cur_val, (tr("  (Nächste Stufe bei $%d)") % next_thr) if cur_lvl < GameState.COMPANY_LEVEL_THRESHOLDS.size() else tr("  (MAXIMALSTUFE)")
	]
	l_head.add_theme_font_size_override("font_size", 13.5)
	l_head.modulate = Color(0.08, 0.24, 0.48)
	lv.add_child(l_head)
	for lvl_i in range(1, GameState.COMPANY_LEVEL_THRESHOLDS.size() + 1):
		var b_info: Dictionary = GameState.COMPANY_LEVEL_BENEFITS.get(lvl_i, {})
		var unlocked_l := cur_lvl >= lvl_i
		var bl := Label.new()
		bl.text = "%s Stufe %d ($%d): %s" % [
			"✓" if unlocked_l else "🔒",
			lvl_i,
			int(GameState.COMPANY_LEVEL_THRESHOLDS[lvl_i - 1]),
			str(b_info.get("summary", "")),
		]
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.add_theme_font_size_override("font_size", 11.5)
		bl.modulate = Color(0.12, 0.44, 0.22) if unlocked_l else Color(0.42, 0.46, 0.52)
		lv.add_child(bl)

	# 3. Karriere-Meilensteine (bodenständige Großkunden-Stufen mit permanenten Boni!)
	for m_v in GameState.CAREER_MILESTONES:
		var m: Dictionary = m_v
		var done := GameState.career_completed.has(str(m["id"]))
		var mc := _make_light_card(
			Color(0.92, 0.98, 0.93) if done else Color(0.98, 0.98, 0.99),
			Color(0.28, 0.68, 0.38) if done else Color(0.78, 0.81, 0.86),
			6, 12, 9
		)
		content.add_child(mc)
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 2)
		mc.add_child(mv)
		var head := Label.new()
		head.text = "%s %s — %s  (Prämie: +$%d)" % [
			"✓" if done else "○",
			str(m["title"]),
			str(m["client"]),
			int(m["reward"]),
		]
		head.add_theme_font_size_override("font_size", 13)
		head.modulate = Color(0.12, 0.46, 0.22) if done else Color(0.12, 0.15, 0.20)
		mv.add_child(head)
		var dl := Label.new()
		dl.text = str(m["desc"])
		dl.add_theme_font_size_override("font_size", 11.5)
		dl.modulate = Color(0.32, 0.36, 0.42)
		mv.add_child(dl)


func _render_support_tickets_subtab(content: VBoxContainer) -> void:
	_ticket_status_labels.clear()
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
			st_l.text = _ticket_status_text(t, is_fixed)
			_ticket_status_labels[str(tid)] = st_l
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
	hl.text = tr("Aktive Großkunden-Verträge: %d / %d   •   Verfügbarer RAM: %d GB   •   Router: %s") % [
		GameState.get_active_contract_count(), GameState.get_max_contracts_limit(), GameState.total_ram_gb, HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
	]
	hl.add_theme_font_size_override("font_size", 12.5)
	hl.modulate = Color(0.14, 0.22, 0.32)
	b.add_child(hl)

	# GAME-05: Bewertungen der Kunden
	var rv := _make_light_card(Color(1.0, 0.98, 0.92), Color(0.90, 0.78, 0.40), 6, 12, 8)
	content.add_child(rv)
	var avg := GameState.rating_avg()
	var rh := Label.new()
	rh.text = tr("Bewertungen: %s  %.1f von 5  (%d)") % [Sla.stars_text(avg), avg, GameState.reviews.size()]
	rh.add_theme_font_size_override("font_size", 13)
	rh.modulate = Color(0.45, 0.30, 0.04)
	rv.add_child(rh)
	var rn := Label.new()
	rn.text = tr("Gute Bewertungen bringen mehr und besser bezahlte Anfragen. SLA Silber gibt es ab 3, Gold ab 4 Sternen im Schnitt.")
	rn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rn.add_theme_font_size_override("font_size", 11.5)
	rn.modulate = Color(0.34, 0.38, 0.44)
	rv.add_child(rn)
	for i in range(GameState.reviews.size() - 1, maxi(-1, GameState.reviews.size() - 4), -1):
		var r: Dictionary = GameState.reviews[i]
		var rl2 := Label.new()
		rl2.text = "%s  %s, Tag %d: „%s“" % [Sla.stars_text(float(r["stars"])), str(r["client"]), int(r["day"]), str(r["text"])]
		rl2.add_theme_font_size_override("font_size", 11.5)
		rl2.modulate = Color(0.22, 0.26, 0.32)
		rv.add_child(rl2)

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
		if active:
			var tier := Sla.tier(c)
			sl.text += "\n" + tr("SLA %s  •  Verfügbarkeit %.1f %% (Ziel %.1f %%)  •  zahlt ×%.2f, Strafe ×%.1f") % [
				tr(str(tier["name"])), Sla.availability(c) * 100.0, float(tier["target"]) * 100.0, float(tier["pay"]), float(tier["penalty"])]
		sl.add_theme_font_size_override("font_size", 11.5)
		sl.modulate = Color(0.34, 0.38, 0.44)
		iv.add_child(sl)
		var rival_line := ""
		if MarketManager.is_contract_taken(c):
			rival_line = tr("Läuft gerade bei %s (bis Tag %d).") % [MarketManager.rival_name(str(c["taken_by"])), int(c["taken_until"])]
		elif not active and str(c.get("bid_rival", "")) != "":
			rival_line = tr("%s bietet mit: noch %d s. Jetzt annehmen für $%d je Zyklus.") % [
				MarketManager.rival_name(str(c["bid_rival"])), int(float(c.get("bid_left", 0.0))), MarketManager.contract_payout(c)]
		if rival_line != "":
			var rl := Label.new()
			rl.text = rival_line
			rl.add_theme_font_size_override("font_size", 12)
			rl.modulate = Color(0.72, 0.34, 0.06)
			iv.add_child(rl)

		var cap_id := cid
		if active:
			var btn := Button.new()
			btn.text = tr("Kündigen")
			btn.custom_minimum_size = Vector2(130, 34)
			_style_win_btn(btn, Color(0.80, 0.22, 0.20), Color(0.64, 0.14, 0.12), Color.WHITE)
			btn.pressed.connect(func(): GameState.request_toggle_contract(cap_id))
			hb.add_child(btn)
		else:
			# GAME-05: Annehmen mit SLA-Stufe
			var taken := MarketManager.is_contract_taken(c)
			var full := GameState.get_active_contract_count() >= GameState.get_max_contracts_limit()
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 3)
			hb.add_child(col)
			for t_id in Sla.ORDER:
				var tier: Dictionary = Sla.TIERS[t_id]
				var b2 := Button.new()
				b2.text = tr("%s  ×%.2f") % [tr(str(tier["name"])), float(tier["pay"])]
				b2.tooltip_text = tr("Verspricht %.1f %% Verfügbarkeit. Zahlt ×%.2f, Strafe ×%.1f.") % [float(tier["target"]) * 100.0, float(tier["pay"]), float(tier["penalty"])]
				b2.custom_minimum_size = Vector2(130, 26)
				b2.disabled = taken or full or avg < float(tier["min_stars"])
				var tcol := Color(0.62, 0.42, 0.20) if t_id == "bronze" else (Color(0.48, 0.52, 0.58) if t_id == "silver" else Color(0.80, 0.62, 0.10))
				_style_win_btn(b2, tcol if not b2.disabled else Color(0.84, 0.86, 0.89), tcol.darkened(0.2), Color.WHITE if not b2.disabled else Color(0.45, 0.48, 0.52))
				var cap_tier := t_id
				b2.pressed.connect(func(): GameState.request_toggle_contract(cap_id, cap_tier))
				col.add_child(b2)


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
	dt.text = "Verion OS Firewall & DDoS-Abwehr"
	dt.add_theme_font_size_override("font_size", 15)
	dt.modulate = Color(0.10, 0.12, 0.16)
	di.add_child(dt)
	var dd := Label.new()
	var cyber_on := not Cyber.attack.is_empty()
	dd.text = (tr("ALARM: %s läuft! In der Firewall-App die Angreifer blocken.") % tr(str(Cyber.KINDS[str(Cyber.attack["kind"])]["name"]))) if cyber_on else tr("Geschützt — Netzwerkverkehr und Kunden laufen störungsfrei.")
	dd.add_theme_font_size_override("font_size", 12)
	dd.modulate = Color(0.76, 0.14, 0.12) if cyber_on else Color(0.14, 0.48, 0.24)
	di.add_child(dd)

	var dbtn := Button.new()
	dbtn.text = tr("Zur Firewall") if cyber_on else tr("Kein Angriff")
	dbtn.custom_minimum_size = Vector2(158, 36)
	dbtn.disabled = not cyber_on
	_style_win_btn(dbtn, Color(0.82, 0.18, 0.16) if cyber_on else Color(0.86, 0.88, 0.90), Color(0.66, 0.12, 0.10), Color.WHITE if cyber_on else Color(0.45, 0.48, 0.52))
	dbtn.pressed.connect(func(): _open_app("firewall"))
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
		ubtn.pressed.connect(_open_ai_overlay)
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

	var at_nord := _pc_at_nord()
	# Garagen-PC: Anschlüsse und Garagen-Ausbau. PC in Halle Nord: nur die Halle und ihre Ausbauten.
	if not at_nord:
		_render_garage_connection_cards(content)
	_render_halle_nord_card(content, at_nord)

	# 3d. Sichtbarer Gebäude-Ausbau mit Bautrupp, je PC nur die Ausbauten dieses Standorts
	var site := "halle_nord" if at_nord else "garage"
	var bupg_card := _make_light_card(Color(0.95, 0.98, 1.0), Color(0.24, 0.54, 0.82), 7, 14, 12)
	if at_nord and not GameState.halle_nord_owned:
		bupg_card.visible = false
	content.add_child(bupg_card)
	var buv := VBoxContainer.new()
	buv.add_theme_constant_override("separation", 8)
	bupg_card.add_child(buv)
	var bu_t := Label.new()
	bu_t.text = tr("🚧 Ausbau Halle Nord") if at_nord else tr("🚧 Ausbau Garage")
	bu_t.add_theme_font_size_override("font_size", 15)
	bu_t.modulate = Color(0.08, 0.28, 0.54)
	buv.add_child(bu_t)
	var bu_sub := Label.new()
	bu_sub.text = tr("Nach dem Kauf rückt ein Bautrupp an und baut den Ausbau sichtbar in etwa einer Minute.") + ("" if at_nord else "  " + tr("Ausbauten für Halle Nord gibt es am PC in Halle Nord."))
	bu_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bu_sub.add_theme_font_size_override("font_size", 11.5)
	bu_sub.modulate = Color(0.24, 0.30, 0.38)
	buv.add_child(bu_sub)
	for uid in GameState.BUILDING_UPGRADE_ORDER:
		if GameState.upgrade_site(uid) != site:
			continue
		var um: Dictionary = GameState.BUILDING_UPGRADE_CATALOG[uid]
		var built := GameState.has_building_upgrade(uid)
		var building := GameState.is_construction_active(uid)
		var block := GameState.upgrade_block_reason(uid)
		var price := int(um.get("price", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		buv.add_child(row)
		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_v)
		var nl := Label.new()
		nl.text = "%s %s" % [str(um.get("icon", "🏗")), str(um.get("name", uid))]
		nl.add_theme_font_size_override("font_size", 13)
		nl.modulate = Color(0.10, 0.42, 0.22) if built else Color(0.14, 0.18, 0.24)
		info_v.add_child(nl)
		var el := Label.new()
		el.text = "%s  •  %s" % [str(um.get("effect", "")), str(um.get("desc", ""))]
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.add_theme_font_size_override("font_size", 11)
		el.modulate = Color(0.32, 0.38, 0.46)
		info_v.add_child(el)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 32)
		if built:
			btn.text = tr("✅ Gebaut & aktiv")
			btn.disabled = true
			_style_win_btn(btn, Color(0.84, 0.94, 0.86), Color(0.24, 0.62, 0.34), Color(0.12, 0.40, 0.18))
		elif building:
			var rem := int(ceilf(float((GameState.active_constructions[uid] as Dictionary).get("remaining", 0.0))))
			btn.text = tr("🚧 Bautrupp (%d s)") % rem
			btn.disabled = true
			_style_win_btn(btn, Color(0.98, 0.92, 0.76), Color(0.82, 0.56, 0.12), Color(0.48, 0.30, 0.04))
		elif block != "":
			btn.text = "🔒 " + block
			btn.disabled = true
			_style_win_btn(btn, Color(0.90, 0.91, 0.93), Color(0.70, 0.72, 0.76), Color(0.42, 0.44, 0.48))
		else:
			btn.text = tr("Bauen ($%d)") % price
			btn.disabled = GameState.money < float(price)
			_style_win_btn(btn, Color(0.10, 0.46, 0.82), Color(0.08, 0.36, 0.68), Color.WHITE)
			var cap_uid := str(uid)
			btn.pressed.connect(func():
				SfxManager.play("click", -10.0)
				GameState.request_buy_building_upgrade(cap_uid)
				_refresh_all()
			)
		row.add_child(btn)

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
			var row_btn := Button.new()
			row_btn.text = tr("• %s:  %d/%d W  •  %d GB RAM  •  %.1f TB  •  %.0f°C  •  %s  •  Strom:%s LAN:%s") % [
				str(rid).to_upper(), int(hw["watts"]), max_pdu, int(hw["ram_gb"]), float(hw["storage_tb"]),
				float(r["temp"]), rent_txt, tr("an") if bool(r["powered"]) else tr("aus"), tr("ok") if bool(r["networked"]) else tr("fehlt")
			]
			row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_btn.tooltip_text = tr("Klicken für Details zu diesem Rack")
			row_btn.add_theme_font_size_override("font_size", 12)
			_style_win_btn(row_btn, Color(0.97, 0.98, 0.99), Color(0.86, 0.89, 0.93), Color(0.14, 0.16, 0.20))
			var detail_id := str(rid)
			row_btn.pressed.connect(func(): _open_rack_detail_overlay(detail_id))
			tv.add_child(row_btn)
			for fault_txt in _rack_fault_lines(r):
				var fl := Label.new()
				fl.text = "      → " + fault_txt
				fl.add_theme_font_size_override("font_size", 12)
				fl.modulate = Color(0.78, 0.22, 0.14)
				tv.add_child(fl)


## Störungen eines Racks für die Live-Übersicht. Ein defektes Bauteil wird erst genannt,
## nachdem es jemand in der 3D-Vorschau am Rack gefunden hat.
func _rack_fault_lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var slots: Array = r.get("slots", []) as Array
	for si in range(slots.size()):
		var sl: Dictionary = slots[si]
		if str(sl.get("item_type", "")) == "":
			continue
		var st := str(sl.get("state", ""))
		if st == "burning":
			out.append(tr("Slot %d: BRAND!") % (si + 1))
		elif st == "crashed":
			if GameState.is_slot_awaiting_diagnosis(sl):
				out.append(tr("Störung – Ursache unbekannt, am Rack nachsehen"))
			elif str(sl.get("faulty_part", "")) != "":
				out.append(tr("Slot %d: %s defekt – in der 3D-Vorschau am Rack reparieren") % [si + 1, GameState.get_component_label(str(sl["faulty_part"]))])
			else:
				out.append(tr("Slot %d ausgefallen – in der 3D-Vorschau am Rack reparieren") % (si + 1))
	return out


## Detailansicht eines Racks aus der Live-Übersicht. Das defekte Bauteil steht erst drin,
## nachdem es jemand in der 3D-Vorschau am Rack gefunden hat.
func _open_rack_detail_overlay(rack_id: String) -> void:
	_close_price_overlay()
	if not GameState.racks.has(rack_id):
		return
	var r: Dictionary = GameState.racks[rack_id]
	var rtype := str(r.get("rack_type", "rack"))
	var max_pdu := int((GameState.ITEM_CATALOG.get(rtype, {}) as Dictionary).get("max_pdu_watts", 3200))
	var hw := GameState.get_rack_hardware_summary(rack_id)

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
	card.custom_minimum_size = Vector2(600, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var title := Label.new()
	title.text = GameState.get_rack_display_name(rack_id)
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.10, 0.12, 0.16)
	col.add_child(title)

	var rent_txt := tr("Standby")
	var r_rent := str(r.get("rental_type", "none"))
	if r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
		rent_txt = tr("%s (%d User)") % [tr(str(HardwareCatalog.RENTAL_PROFILES[r_rent]["short"])), int(r.get("active_users", 0))]

	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 18)
	info_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(info_grid)
	var info_rows: Array = [
		[tr("Strom"), tr("an") if bool(r.get("powered", false)) else tr("aus")],
		[tr("LAN"), tr("ok") if bool(r.get("networked", false)) else tr("fehlt")],
		[tr("Verbrauch"), "%d / %d W" % [int(hw["watts"]), max_pdu]],
		[tr("Temperatur"), "%.1f °C" % float(r.get("temp", 0.0))],
		[tr("RAM"), "%d GB" % int(hw["ram_gb"])],
		[tr("Speicher"), "%.1f TB" % float(hw["storage_tb"])],
		[tr("Vermietung"), rent_txt],
	]
	for row in info_rows:
		var k := Label.new()
		k.text = str(row[0])
		k.custom_minimum_size = Vector2(120, 0)
		k.add_theme_font_size_override("font_size", 13)
		k.modulate = Color(0.36, 0.40, 0.46)
		info_grid.add_child(k)
		var v := Label.new()
		v.text = str(row[1])
		v.add_theme_font_size_override("font_size", 13)
		v.modulate = Color(0.10, 0.12, 0.16)
		info_grid.add_child(v)

	var slot_head := Label.new()
	slot_head.text = tr("GERÄTE IM RACK")
	slot_head.add_theme_font_size_override("font_size", 11)
	slot_head.modulate = Color(0.34, 0.40, 0.48)
	col.add_child(slot_head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var slot_list := VBoxContainer.new()
	slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_list.add_theme_constant_override("separation", 4)
	scroll.add_child(slot_list)

	var slots: Array = r.get("slots", []) as Array
	var shown := 0
	for si in range(slots.size()):
		var sl: Dictionary = slots[si]
		var itype := str(sl.get("item_type", ""))
		if itype == "":
			continue
		shown += 1
		var item_label := str((GameState.ITEM_CATALOG.get(itype, {}) as Dictionary).get("label", itype))
		var st := str(sl.get("state", ""))
		var status_txt := tr("läuft")
		var status_col := Color(0.08, 0.44, 0.24)
		if st == "burning":
			status_txt = tr("BRAND!")
			status_col = Color(0.78, 0.22, 0.14)
		elif st == "crashed":
			status_col = Color(0.78, 0.22, 0.14)
			if GameState.is_slot_awaiting_diagnosis(sl):
				status_txt = tr("ausgefallen – Ursache unbekannt, am Rack in der 3D-Vorschau nachsehen")
			elif str(sl.get("faulty_part", "")) != "":
				status_txt = tr("%s defekt – in der 3D-Vorschau am Rack reparieren") % GameState.get_component_label(str(sl["faulty_part"]))
			else:
				status_txt = tr("ausgefallen – in der 3D-Vorschau am Rack reparieren")
		elif st != "ok":
			status_txt = st
			status_col = Color(0.45, 0.48, 0.52)
		var sl_lbl := Label.new()
		sl_lbl.text = tr("Slot %d: %s  •  %s") % [si + 1, tr(item_label), status_txt]
		sl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl_lbl.add_theme_font_size_override("font_size", 12)
		sl_lbl.modulate = status_col
		slot_list.add_child(sl_lbl)
	if shown == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = tr("Keine Geräte eingebaut.")
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.modulate = Color(0.42, 0.46, 0.52)
		slot_list.add_child(empty_lbl)
	scroll.custom_minimum_size = Vector2(0, clampf(float(maxi(shown, 1)) * 26.0, 30.0, 300.0))

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(btn_row)
	var close_btn := Button.new()
	close_btn.text = tr("Schließen")
	close_btn.custom_minimum_size = Vector2(120, 38)
	_style_win_btn(close_btn, Color(0.92, 0.93, 0.95), Color(0.76, 0.79, 0.82), Color(0.20, 0.24, 0.30))
	close_btn.pressed.connect(_close_price_overlay)
	btn_row.add_child(close_btn)


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
	_monitor_frame = PanelContainer.new()
	# Vollbild: der PC füllt den ganzen Bildschirm, ohne Rahmen. Die Größe setzt _fit_fullscreen().
	_monitor_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = Color(0.0, 0.0, 0.0)
	bezel.set_content_margin_all(0)
	_monitor_frame.add_theme_stylebox_override("panel", bezel)
	add_child(_monitor_frame)

	var layer := Control.new()
	_monitor_frame.add_child(layer)
	_desktop = VerionDesktop.new()
	layer.add_child(_desktop)
	_desktop.setup(APP_META, APP_ORDER)
	_desktop.app_requested.connect(_open_app)
	_desktop.active_changed.connect(_on_active_changed)
	_desktop.exit_requested.connect(func(): close_requested.emit())
	_desktop.shutdown_requested.connect(_shut_down_pc)
	_desktop.save_requested.connect(_trigger_quick_save)
	_desktop.theme_toggled.connect(_toggle_theme)

	# Anruf-Fenster unten rechts über dem Dock
	_call_popup = PanelContainer.new()
	_call_popup.visible = false
	_call_popup.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_call_popup.offset_left = -380
	_call_popup.offset_right = -14
	_call_popup.offset_top = -320
	_call_popup.offset_bottom = -VerionDesktop.DOCK_H - 8.0
	_call_popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var cp_sb := StyleBoxFlat.new()
	cp_sb.bg_color = Color(0.98, 0.99, 1.0, 0.99)
	cp_sb.border_color = Color(0.82, 0.24, 0.18)
	cp_sb.set_border_width_all(2)
	cp_sb.set_corner_radius_all(12)
	cp_sb.set_content_margin_all(14)
	cp_sb.shadow_color = Color(0, 0, 0, 0.5)
	cp_sb.shadow_size = 14
	_call_popup.add_theme_stylebox_override("panel", cp_sb)
	_call_popup.add_to_group("verion_overlay")
	layer.add_child(_call_popup)
	_call_body = VBoxContainer.new()
	_call_body.add_theme_constant_override("separation", 7)
	_call_popup.add_child(_call_body)
	VerionTheme.apply(_call_popup)


func _load_theme() -> void:
	var cfg := ConfigFile.new()
	VerionTheme.dark = true
	if cfg.load(PC_DESKTOP_CFG) == OK:
		VerionTheme.dark = bool(cfg.get_value("desktop", "verion_dark", true))


func _toggle_theme() -> void:
	VerionTheme.dark = not VerionTheme.dark
	var cfg := ConfigFile.new()
	# Fehlt die Datei noch, wird sie beim Speichern neu angelegt.
	cfg.load(PC_DESKTOP_CFG)
	cfg.set_value("desktop", "verion_dark", VerionTheme.dark)
	var err := cfg.save(PC_DESKTOP_CFG)
	if err != OK:
		push_warning("PC-Darstellung konnte nicht gespeichert werden (Fehler %d)." % err)
	_desktop.restyle()
	_refresh_all()
	SfxManager.play("click", -10.0, 1.05)


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
	if GameState.power_fuse_stock > 0 or GameState.is_power_fuse_on_way():
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
	note.text = tr("Du kaufst eine Drehsicherung. Sie kommt mit dem Lieferwagen im Sammelpaket ins Lager. Setze sie am Sicherungskasten mit [E] in Steckplatz F2 ein: Erst dann steigt die Stromstufe, und die alte Sicherung bekommst du in die Hand.")
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


## Gemeinsames Vergleichs-Overlay für Gebäude-Upgrades (Router, Hallen, KI-Plattform).
## rows: Array aus 3er-Arrays [Merkmal, Aktuell, Neu]; die erste Zeile ist die Kopfzeile.
func _open_upgrade_overlay(title_text: String, rows: Array, note_text: String, cost: int, can_buy: bool, on_buy: Callable) -> void:
	_close_price_overlay()

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
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.10, 0.12, 0.16)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)

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

	if note_text != "":
		var note := Label.new()
		note.text = note_text
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
	buy_btn.disabled = not can_buy
	_style_win_btn(buy_btn, Color(0.12, 0.56, 0.32) if can_buy else Color(0.84, 0.86, 0.89), Color(0.08, 0.44, 0.24), Color.WHITE if can_buy else Color(0.45, 0.48, 0.52))
	buy_btn.pressed.connect(func():
		on_buy.call()
		_close_price_overlay()
	)
	btn_row.add_child(buy_btn)


## Router-Overlay: zeigt Geschwindigkeit, Ports und DDoS-Schutz der nächsten Stufe.
func _open_router_overlay() -> void:
	_close_price_overlay()
	var rt := clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)
	if rt + 1 >= GameState.ROUTER_TIERS.size():
		return
	var cur: Dictionary = GameState.ROUTER_TIERS[rt]
	var nxt: Dictionary = GameState.ROUTER_TIERS[rt + 1]
	var cost := int(nxt["cost"])
	var rows: Array = [
		["", tr("Aktuell"), tr("Neu")],
		[tr("Geschwindigkeit"), str(cur["speed"]), str(nxt["speed"])],
		[tr("LAN-Ports"), str(int(cur["ports"])), str(int(nxt["ports"]))],
		[tr("DDoS-Schutz"),
			"+%.0f%%" % ((float(cur["ddos_mult"]) - 1.0) * 100.0),
			"+%.0f%%" % ((float(nxt["ddos_mult"]) - 1.0) * 100.0)],
		[tr("Preis"), "–", "$%d" % cost],
	]
	_open_upgrade_overlay(tr("Internet-Router upgraden"), rows, "", cost, GameState.money >= float(cost), GameState.request_upgrade_router)


## Hallen-Overlay: zeigt, welcher Gebäudeteil dazukommt und wie viel Fläche er bringt.
func _open_hall_overlay() -> void:
	_close_price_overlay()
	if GameState.room_level >= 2:
		return
	var cost := GameState.HALL_B_COST if GameState.room_level == 0 else GameState.HALL_C_COST
	var cur_name := tr("Garage") if GameState.room_level == 0 else tr("Garage + Halle B")
	var nxt_name := tr("Garage + Halle B") if GameState.room_level == 0 else tr("Vollausbau (3/3 Hallen)")
	var area := "+63 m²" if GameState.room_level == 0 else "+81 m²"
	var note := tr("Öffnet HALLE B (+63 m² Doppelboden-Serverraum).") if GameState.room_level == 0 else tr("Öffnet HALLE C — ENTERPRISE RECHENZENTRUM (+81 m²) mit eigenem Strom- & Glasfaserbus!")
	var rows: Array = [
		["", tr("Aktuell"), tr("Neu")],
		[tr("Gebäude"), cur_name, nxt_name],
		[tr("Zusatzfläche"), "–", area],
		[tr("Preis"), "–", "$%d" % cost],
	]
	_open_upgrade_overlay(tr("Gebäude-Ausbau"), rows, note, cost, GameState.money >= float(cost), GameState.request_expand_room)


## KI-Plattform-Overlay: zeigt die nächste Stufe mit den nötigen RAM- und GPU-Werten.
func _open_ai_overlay() -> void:
	_close_price_overlay()
	var cur_lvl := GameState.ai_platform_level
	if cur_lvl + 1 >= GameState.AI_TIERS.size():
		return
	var cur: Dictionary = GameState.AI_TIERS[cur_lvl]
	var nxt: Dictionary = GameState.AI_TIERS[cur_lvl + 1]
	var cost := int(nxt["cost"])
	var mram := int(nxt.get("min_ram_gb", 16))
	var mgpu := int(nxt.get("min_gpu", 30))
	var have_ram := int(GameState.total_ram_gb)
	var have_gpu := int(GameState.total_gpu_score)
	var can_buy := GameState.money >= float(cost) and have_ram >= mram and have_gpu >= mgpu
	var rows: Array = [
		["", tr("Aktuell"), tr("Neu")],
		[tr("Stufe"), "%d / %d" % [cur_lvl + 1, GameState.AI_TIERS.size()], "%d / %d" % [cur_lvl + 2, GameState.AI_TIERS.size()]],
		[tr("Plattform"), tr(str(cur["label"])), tr(str(nxt["label"]))],
		[tr("Mindest-RAM"), "%d GB" % int(cur.get("min_ram_gb", 0)), "%d GB" % mram],
		[tr("Mindest-GPU"), str(int(cur.get("min_gpu", 0))), str(mgpu)],
		[tr("Preis"), "–", "$%d" % cost],
	]
	var note := tr("Dein Bestand: %d GB RAM, GPU-Wert %d.") % [have_ram, have_gpu]
	_open_upgrade_overlay(tr("KI-Plattform upgraden"), rows, note, cost, can_buy, GameState.request_upgrade_ai_platform)


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


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()



## Router, Netzanschluss und Halle B/C (nur am Garagen-PC).
func _render_garage_connection_cards(content: VBoxContainer) -> void:
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
		rtbtn.pressed.connect(_open_router_overlay)
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
	elif GameState.is_power_fuse_on_way():
		pbtn.text = tr("Unterwegs mit dem Lieferwagen")
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
		rbtn.pressed.connect(_open_hall_overlay)
	else:
		rbtn.text = "Alle Hallen offen"
		rbtn.disabled = true
		_style_win_btn(rbtn, Color(0.88, 0.90, 0.93), Color(0.76, 0.79, 0.82), Color(0.32, 0.36, 0.42))
	rh.add_child(rbtn)


## Steht der eigene Spieler in Halle Nord (dann ist das der PC dort)?
func _pc_at_nord() -> bool:
	var lp := get_tree().get_first_node_in_group("local_player") as Node3D
	return lp != null and HalleNordLayout.is_nord(lp.global_position)


## Karte für Halle Nord: am Garagen-PC Kauf und Bau, am PC in Halle Nord der Zustand der Halle.
func _render_halle_nord_card(content: VBoxContainer, at_nord: bool) -> void:
	var owned := GameState.halle_nord_owned
	var building := GameState.is_construction_active("upg_nord_hall")
	var lvl_ok := GameState.get_company_level() >= GameState.HALLE_NORD_REQ_LEVEL
	var card := _make_light_card(
		Color(0.93, 0.98, 0.94) if owned else Color(0.97, 0.98, 1.0),
		Color(0.26, 0.68, 0.40) if owned else Color(0.42, 0.62, 0.88), 7, 14, 12)
	content.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var n := HalleNordLayout.sections()
	var title := Label.new()
	var desc := Label.new()
	if at_nord:
		title.text = tr("Halle Nord  •  Abschnitt %d / 3 offen  •  %.1f °C") % [n, GameState.nord_room_temp]
		desc.text = tr("Strom: %d W über %d Verteiler  •  Core-Switch: %d Ports  •  Eigene Raumtemperatur: Reihenkühler und Flüssigkühlung kühlen hier, der Kaltgang-Ausbau hilft zusätzlich.") % [
			HalleNordLayout.WATTS_PER_SECTION * n, n, HalleNordLayout.core_ports(n)]
	else:
		title.text = tr("Standort 2: Halle Nord (24 × 14 m, 3 Abschnitte)") + (tr("  •  AKTIV") if owned else "")
		desc.text = tr("Helle Rechenzentrumshalle mit Technikecke, Büro und eigenem PC. Abschnitt 1 ist dabei (%d W, 16 Steckdosen, 16 Ports), Abschnitt 2 und 3 baust du am PC in Halle Nord aus. Hin und zurück mit dem Shuttle [T].") % HalleNordLayout.WATTS_PER_SECTION
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(0.10, 0.42, 0.22) if owned else Color(0.10, 0.14, 0.22)
	info.add_child(title)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(0.32, 0.36, 0.44)
	info.add_child(desc)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 38)
	if owned:
		btn.text = tr("🚐 Shuttle zur Garage [T]") if at_nord else tr("🚐 Shuttle nach Halle Nord [T]")
		_style_win_btn(btn, Color(0.12, 0.54, 0.34), Color(0.08, 0.42, 0.26), Color.WHITE)
		btn.pressed.connect(func():
			SfxManager.play("click", -10.0)
			close_requested.emit()
			var lp := get_tree().get_first_node_in_group("local_player")
			if lp != null and lp.has_method("teleport_between_sites"):
				lp.call("teleport_between_sites")
		)
	elif building:
		var rem := int(ceilf(float((GameState.active_constructions["upg_nord_hall"] as Dictionary).get("remaining", 0.0))))
		btn.text = tr("🚧 Bautrupp baut (%d s)") % rem
		btn.disabled = true
		_style_win_btn(btn, Color(0.98, 0.92, 0.76), Color(0.82, 0.56, 0.12), Color(0.48, 0.30, 0.04))
	elif not lvl_ok:
		btn.text = tr("🔒 Ab Firmenstufe %d") % GameState.HALLE_NORD_REQ_LEVEL
		btn.disabled = true
		_style_win_btn(btn, Color(0.84, 0.86, 0.89), Color(0.74, 0.76, 0.80), Color(0.45, 0.48, 0.52))
	else:
		btn.text = tr("Kaufen ($%d)") % GameState.HALLE_NORD_COST
		btn.disabled = GameState.money < float(GameState.HALLE_NORD_COST)
		_style_win_btn(btn, Color(0.10, 0.48, 0.84) if not btn.disabled else Color(0.84, 0.86, 0.89), Color(0.08, 0.38, 0.70), Color.WHITE if not btn.disabled else Color(0.45, 0.48, 0.52))
		btn.pressed.connect(func():
			SfxManager.play("click", -10.0)
			GameState.request_buy_halle_nord()
			_refresh_all()
		)
	h.add_child(btn)
	if not owned:
		return
	var del_row := HBoxContainer.new()
	del_row.add_theme_constant_override("separation", 8)
	v.add_child(del_row)
	var del_lbl := Label.new()
	del_lbl.text = tr("Lieferziel für Shop-Bestellungen:")
	del_lbl.add_theme_font_size_override("font_size", 12)
	del_lbl.modulate = Color(0.20, 0.28, 0.36)
	del_row.add_child(del_lbl)
	for site_spec in [["garage", tr("Garage")], ["halle_nord", tr("Halle Nord")]]:
		var sid := str(site_spec[0])
		var sb := Button.new()
		sb.text = str(site_spec[1])
		sb.custom_minimum_size = Vector2(150, 28)
		var is_sel := (GameState.delivery_target_site == sid)
		_style_win_btn(sb, Color(0.10, 0.46, 0.82) if is_sel else Color(0.90, 0.92, 0.95), Color(0.08, 0.36, 0.68), Color.WHITE if is_sel else Color(0.18, 0.22, 0.28))
		sb.pressed.connect(func():
			SfxManager.play("click", -12.0)
			GameState.request_set_delivery_site(sid)
			_refresh_all()
		)
		del_row.add_child(sb)
