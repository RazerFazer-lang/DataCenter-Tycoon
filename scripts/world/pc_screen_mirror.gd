class_name PcScreenMirror
extends Node
## Bild des 3D-Monitors am Schreibtisch.
## Rendert in einen SubViewport, was der Spieler am PC gerade macht (Sperrbildschirm,
## Hochfahren, Desktop mit offener App). Grundlage ist PcScreenState, das alle Spieler teilen.
## Die Finanz-Apps werden mit denselben Funktionen gezeichnet wie am echten PC.

const VIEW_PIXELS := Vector2i(1024, 550)
const VIEW_LOGICAL := Vector2i(1536, 825)
const REFRESH_INTERVAL := 0.1
const IDLE_REFRESH_INTERVAL := 1.0
const BOOT_REFRESH_INTERVAL := 0.05
const LIVE_REBUILD_INTERVAL := 1.0
const HISTORY_LEN := 60
const TASKBAR_H := 48.0
const ICON_COLUMN_W := 150.0
## Mitspieler sehen nicht, was am PC gemacht wird. Der Monitor zeigt nur Hochfahren und den leeren Desktop.
const SHOW_APP_CONTENT := false

const APP_INFO := {
	"mail": {"icon": "mail", "name": "Verion Mail", "short": "E-Mail"},
	"shop": {"icon": "cart", "name": "Hardware-Shop", "short": "Shop"},
	"support": {"icon": "headset", "name": "Support-Center", "short": "Support"},
	"market": {"icon": "market", "name": "Markt & Konkurrenz", "short": "Markt"},
	"upgrades": {"icon": "building", "name": "Upgrades", "short": "Upgrades"},
	"monitor": {"icon": "chart", "name": "Task-Manager", "short": "Monitor"},
	"cams": {"icon": "camera", "name": "Kameras", "short": "Kameras"},
	"staff": {"icon": "people", "name": "Personalverwaltung", "short": "Personal"},
	"bank": {"icon": "bank", "name": "Hanse Direktbank", "short": "Bank"},
	"bills": {"icon": "invoice", "name": "Rechnungen & Zahlungen", "short": "Rechnungen"},
}

const SHOP_TABS := {
	"chassis": "Racks & Gehäuse", "infra": "Infrastruktur", "cpu": "Prozessoren", "ram": "Arbeitsspeicher",
	"gpu": "Grafikkarten", "storage": "Speicher", "cooling": "Kühlung", "psu": "Netzteile", "warehouse": "Lager",
}

const SUPPORT_TABS := {"tickets": "Tickets", "contracts": "Verträge", "ai": "KI-Plattform"}

const FINANCE_APPS: Array[String] = ["staff", "bank", "bills"]
const LIVE_APPS: Array[String] = ["shop", "support", "upgrades", "monitor", "cams"]

## Shader-Material des alten Monitors. Die Garage setzt dort jedes Frame "power_on",
## daran erkennt der Spiegel, ob der Strom da ist.
var power_source: ShaderMaterial = null

var _vp: SubViewport
var _screen: Control
var _lock: Control
var _desk: Control
var _window: PanelContainer
var _win_icon: Control
var _win_icon_kind: String = "verion"
var _win_title: Label
var _win_typing: Label
var _win_body: VBoxContainer
var _alert: PanelContainer
var _boot: PcBootScreen
var _off: ColorRect
var _font: Font
## Material des 3D-Monitors. Die Viewport-Textur wird in _ready() erneut zugewiesen,
## weil sie vor dem Eintritt in den Szenenbaum noch keine gültige Render-Textur hat.
var _screen_mat: StandardMaterial3D = null

var _accum: float = 0.0
var _live_accum: float = 0.0
var _live_due: bool = false
var _finance_dirty: bool = false
var _body_key: String = ""
var _last_boot_serial: int = -1
var _watt_hist: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_font = ThemeDB.fallback_font
	_vp = SubViewport.new()
	_vp.size = VIEW_PIXELS
	_vp.size_2d_override = VIEW_LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_build()


func _ready() -> void:
	FinanceManager.finance_changed.connect(_on_finance_changed)
	PcScreenState.screen_changed.connect(_on_screen_changed)
	_rebind_screen_texture.call_deferred()


func _rebind_screen_texture() -> void:
	if _screen_mat == null:
		return
	_screen_mat.emission_texture = _vp.get_texture()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func make_screen_material() -> StandardMaterial3D:
	var tex := _vp.get_texture()
	# Ein Monitor leuchtet selbst: Das Bild kommt nur über die Emission.
	# Eine fast schwarze Albedo verhindert, dass die Raumlampen das Bild zusätzlich aufhellen
	# und es zusammen mit Glow weiß überstrahlt. Die glatte Oberfläche spiegelt leicht wie eine Glasscheibe.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.015, 0.015, 0.018)
	m.emission_enabled = true
	# Multiply statt dem Standard Add: Bei Add würde Weiß + Bild immer reines Weiß ergeben.
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission = Color.WHITE
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.85
	m.roughness = 0.12
	m.metallic = 0.0
	m.metallic_specular = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_screen_mat = m
	return m


func _on_finance_changed() -> void:
	_finance_dirty = true


func _on_screen_changed() -> void:
	# Beim nächsten Frame sofort neu zeichnen, egal welches Intervall gerade gilt (idle = 1 s).
	# Nur erhöhen: nach dem Vollbild ist _accum schon groß und darf nicht zurückgesetzt werden.
	_accum = maxf(_accum, IDLE_REFRESH_INTERVAL)


func _process(delta: float) -> void:
	_accum += delta
	_live_accum += delta
	if _live_accum >= LIVE_REBUILD_INTERVAL:
		_live_accum = 0.0
		_live_due = true
		_sample_history()
	# Wer selbst im Vollbild am PC sitzt, sieht den 3D-Monitor nicht. Dann wird nichts gerendert.
	if PcScreenState.is_local_user() and PcScreenState.local_fullscreen:
		return
	var interval := REFRESH_INTERVAL
	if _boot.is_running():
		interval = BOOT_REFRESH_INTERVAL
	elif PcScreenState.phase == PcScreenState.PHASE_IDLE:
		interval = IDLE_REFRESH_INTERVAL
	if _accum < interval:
		return
	_accum = 0.0
	_apply_state()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ---------------------------------------------------------------- Zustand übernehmen

func _is_powered() -> bool:
	if power_source == null:
		return true
	var v: Variant = power_source.get_shader_parameter("power_on")
	return v == null or float(v) > 0.5


func _apply_state() -> void:
	var phase: String = PcScreenState.phase
	var pc_on := _is_powered() and phase != PcScreenState.PHASE_IDLE
	# Ausgeschalteter PC oder kein Strom: der Monitor ist schwarz.
	_off.visible = not pc_on
	if not pc_on:
		if _boot.is_running() or _boot.visible:
			_boot.stop()
		return

	if phase == PcScreenState.PHASE_SHUTDOWN:
		if not _boot.is_showing_shutdown():
			_boot.play_shutdown()
	elif phase == PcScreenState.PHASE_BOOT:
		if _last_boot_serial != PcScreenState.boot_serial:
			_last_boot_serial = PcScreenState.boot_serial
			_boot.play(PcScreenState.cold_boot, PcScreenState.user_name, PcScreenState.get_boot_elapsed())
	elif _boot.is_running() or _boot.visible:
		_boot.stop()

	# Der PC läuft: Desktop mit der zuletzt geöffneten App, auch wenn gerade niemand davor sitzt.
	_lock.visible = false
	_desk.visible = true
	_alert.visible = GameState.is_active and GameState.ddos_active
	_update_window()
	_desk.queue_redraw()


func _update_window() -> void:
	var app: String = PcScreenState.app
	_window.visible = SHOW_APP_CONTENT and not app.is_empty()
	if not _window.visible:
		_body_key = ""
		return
	var info: Dictionary = APP_INFO.get(app, {"icon": "verion", "name": app, "short": app})
	_win_title.text = tr(str(info["name"]))
	_win_icon_kind = str(info["icon"])
	_win_icon.queue_redraw()
	_win_typing.visible = PcScreenState.typing

	var detail: String = PcScreenState.detail
	var key := "%s|%s" % [app, detail]
	var need := key != _body_key
	if not need and _finance_dirty and FINANCE_APPS.has(app):
		need = true
	if not need and _live_due and LIVE_APPS.has(app):
		need = true
	if need:
		_rebuild_body(app, detail)
		_body_key = key
		_finance_dirty = false
		_live_due = false


func _sample_history() -> void:
	if not GameState.is_active:
		return
	var maxw := maxf(1.0, float(GameState.max_watts))
	_watt_hist.append(float(GameState.total_watts) / maxw)
	while _watt_hist.size() > HISTORY_LEN:
		_watt_hist.remove_at(0)


# ---------------------------------------------------------------- Aufbau

func _build() -> void:
	_screen = Control.new()
	_full(_screen)
	_vp.add_child(_screen)

	var backdrop := Control.new()
	_full(backdrop)
	backdrop.draw.connect(func(): PcBootScreen.draw_wallpaper(backdrop, Rect2(Vector2.ZERO, backdrop.size)))
	_screen.add_child(backdrop)

	_lock = Control.new()
	_full(_lock)
	_lock.draw.connect(_draw_lock)
	_screen.add_child(_lock)

	_desk = Control.new()
	_full(_desk)
	_desk.draw.connect(_draw_desk)
	_desk.visible = false
	_screen.add_child(_desk)

	_build_window()
	_build_alert()

	_boot = PcBootScreen.new()
	_boot.interactive = false
	_boot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_boot)

	_off = ColorRect.new()
	_full(_off)
	_off.color = Color(0.01, 0.01, 0.012)
	_off.visible = false
	_screen.add_child(_off)


func _build_window() -> void:
	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.offset_left = ICON_COLUMN_W
	_window.offset_top = 22.0
	_window.offset_right = -22.0
	_window.offset_bottom = -(TASKBAR_H + 14.0)
	_window.clip_contents = true
	_window.visible = false
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.95, 0.96, 0.97)
	wsb.border_color = Color(0.70, 0.74, 0.80)
	wsb.set_border_width_all(1)
	wsb.set_corner_radius_all(8)
	wsb.shadow_color = Color(0, 0, 0, 0.35)
	wsb.shadow_size = 14
	wsb.set_content_margin_all(0)
	_window.add_theme_stylebox_override("panel", wsb)
	_desk.add_child(_window)

	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	_window.add_child(wv)

	var title_bar := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.99, 0.99, 1.0)
	tsb.corner_radius_top_left = 8
	tsb.corner_radius_top_right = 8
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 8
	title_bar.add_theme_stylebox_override("panel", tsb)
	wv.add_child(title_bar)

	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	title_bar.add_child(th)
	_win_icon = Control.new()
	_win_icon.custom_minimum_size = Vector2(20, 20)
	_win_icon.draw.connect(func(): UIStyle.draw_icon(_win_icon, _win_icon_kind, Rect2(Vector2.ZERO, _win_icon.size), FinanceApps.COL_ACCENT))
	th.add_child(_win_icon)
	_win_title = FinanceApps._label("", 15, FinanceApps.COL_TEXT)
	_win_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_win_title)
	_win_typing = FinanceApps._label("tippt …", 13, FinanceApps.COL_ACCENT)
	_win_typing.visible = false
	th.add_child(_win_typing)
	for kind in ["minimize", "close"]:
		th.add_child(FinanceApps._icon(str(kind), 14, FinanceApps.COL_MUTED))

	_win_body = VBoxContainer.new()
	_win_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_win_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.add_child(_win_body)


func _build_alert() -> void:
	_alert = PanelContainer.new()
	_alert.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_alert.offset_bottom = 40.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.72, 0.12, 0.10, 0.95)
	sb.set_content_margin_all(8)
	_alert.add_theme_stylebox_override("panel", sb)
	_alert.visible = false
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_alert.add_child(row)
	row.add_child(FinanceApps._icon("warn", 20, Color.WHITE))
	row.add_child(FinanceApps._label("Warnung: DDoS-Angriff auf das Netzwerk erkannt", 16, Color.WHITE))
	_desk.add_child(_alert)


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------- Sperrbildschirm & Desktop

func _draw_lock() -> void:
	var s := _lock.size
	var day: int = GameState.day_number if GameState.is_active else 1
	_lock.draw_string(_font, Vector2(70, s.y - 200), PcBootScreen.format_real_clock(), HORIZONTAL_ALIGNMENT_LEFT, -1, 120, Color.WHITE)
	_lock.draw_string(_font, Vector2(76, s.y - 140), tr("%s  •  Spieltag %d") % [PcBootScreen.format_real_date(), day], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 0.9))
	UIStyle.draw_icon(_lock, "net", Rect2(s.x - 110, s.y - 70, 30, 30), Color(1, 1, 1, 0.85))
	UIStyle.draw_icon(_lock, "power", Rect2(s.x - 64, s.y - 70, 30, 30), Color(1, 1, 1, 0.85))


func _draw_desk() -> void:
	var s := _desk.size
	# Statusleiste oben
	_desk.draw_rect(Rect2(0, 0, s.x, 40), Color(0.045, 0.055, 0.085, 0.94))
	UIStyle.draw_icon(_desk, "verion", Rect2(14, 9, 22, 22), VerionTheme.ACCENT)
	var user := PcScreenState.user_name if not PcScreenState.user_name.is_empty() else "Verion"
	_desk.draw_string(_font, Vector2(46, 27), user, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, VerionTheme.TEXT)
	_desk.draw_string(_font, Vector2(0, 27), "%s   %s" % [PcBootScreen.format_real_date(), PcBootScreen.format_real_clock()], HORIZONTAL_ALIGNMENT_CENTER, s.x, 17, VerionTheme.TEXT)
	var day: int = GameState.day_number if GameState.is_active else 1
	_desk.draw_string(_font, Vector2(s.x - 230, 27), tr("Tag %d") % day, HORIZONTAL_ALIGNMENT_RIGHT, 210, 17, VerionTheme.MUTED)
	# Dock
	var keys: Array = APP_INFO.keys()
	var tile := 56.0
	var gap := 11.0
	var w := float(keys.size()) * (tile + gap) + gap
	var dock := Rect2((s.x - w) * 0.5, s.y - tile - 30.0, w, tile + 20.0)
	_desk.draw_style_box(VerionTheme.flat(Color(0.07, 0.085, 0.13, 0.80), 20, Color(1, 1, 1, 0.12), 1), dock)
	for k in range(keys.size()):
		var aid := str(keys[k])
		var r := Rect2(dock.position.x + gap + float(k) * (tile + gap), dock.position.y + 10.0, tile, tile)
		_desk.draw_style_box(VerionTheme.flat(VerionTheme.app_color(aid), 14), r)
		UIStyle.draw_icon(_desk, str(APP_INFO[aid]["icon"]), Rect2(r.get_center() - Vector2(15, 15), Vector2(30, 30)), Color.WHITE)
		if aid == PcScreenState.app:
			_desk.draw_circle(Vector2(r.get_center().x, dock.end.y - 4.0), 2.6, Color.WHITE)


# ---------------------------------------------------------------- Inhalte der App-Fenster

func _rebuild_body(app: String, detail: String) -> void:
	for c in _win_body.get_children():
		_win_body.remove_child(c)
		c.queue_free()
	match app:
		"staff":
			FinanceApps.render_staff(_win_body, "", true)
		"bank":
			FinanceApps.render_bank(_win_body, "", true)
		"bills":
			FinanceApps.render_bills(_win_body, "", true)
		"shop":
			_render_shop(detail)
		"support":
			_render_support(detail)
		"upgrades":
			_render_upgrades()
		"monitor":
			_render_monitor()
		"cams":
			_render_cams()


func _render_shop(tab: String) -> void:
	var body := FinanceApps._scroll_body(_win_body)
	FinanceApps._header(body, "cart", "Hardware-Shop", tr("Kategorie: %s  •  Kontostand %s") % [
		tr(str(SHOP_TABS.get(tab, "Alle Produkte"))), FinanceApps._money(GameState.money)
	])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	for i in range(8):
		var card := FinanceApps._card(grid)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pic := ColorRect.new()
		pic.color = Color(0.90, 0.92, 0.95)
		pic.custom_minimum_size = Vector2(0, 96)
		card.add_child(pic)
		var name_line := ColorRect.new()
		name_line.color = Color(0.70, 0.74, 0.80)
		name_line.custom_minimum_size = Vector2(120 + (i * 13) % 60, 10)
		name_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.add_child(name_line)
		var price_line := ColorRect.new()
		price_line.color = FinanceApps.COL_ACCENT
		price_line.custom_minimum_size = Vector2(64, 14)
		price_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.add_child(price_line)


func _render_support(tab: String) -> void:
	var body := FinanceApps._scroll_body(_win_body)
	FinanceApps._header(body, "headset", "Support-Center", "Kundenanfragen und Anrufe deiner Mieter.")
	var open_n: int = GameState.get_open_ticket_count()
	var in_call: bool = not GameState.active_call.is_empty()
	FinanceApps._stat_tiles(body, [
		["Offene Tickets", str(open_n), FinanceApps.COL_BAD if open_n > 0 else FinanceApps.COL_TEXT],
		["Anruf", "läuft" if in_call else "keiner", FinanceApps.COL_WARN if in_call else FinanceApps.COL_TEXT],
		["Ansicht", str(SUPPORT_TABS.get(tab, "Tickets")), FinanceApps.COL_TEXT],
	])
	FinanceApps._section(body, "Tickets")
	var shown := 0
	for tid in GameState.support_tickets.keys():
		if shown >= 6:
			break
		var t_v: Variant = GameState.support_tickets[tid]
		if not t_v is Dictionary:
			continue
		var t: Dictionary = t_v
		var done := bool(t.get("reassured", false))
		var card := FinanceApps._card(body, FinanceApps.COL_GOOD if done else FinanceApps.COL_WARN)
		var subject := GameState.format_message(str(t.get("subject", t.get("title", "Kundenanfrage"))), t.get("title_args", []))
		card.add_child(FinanceApps._label("Ticket %s  •  %s" % [str(tid), subject], 14, FinanceApps.COL_TEXT))
		card.add_child(FinanceApps._label("beantwortet" if done else "wartet auf Antwort", 12, FinanceApps.COL_GOOD if done else FinanceApps.COL_WARN))
		shown += 1
	if shown == 0:
		var empty_card := FinanceApps._card(body)
		empty_card.add_child(FinanceApps._label("Keine Tickets vorhanden.", 13, FinanceApps.COL_MUTED))


func _render_upgrades() -> void:
	var body := FinanceApps._scroll_body(_win_body)
	FinanceApps._header(body, "power", "Upgrades", "Ausbaustand deiner Garage.")
	var tiered := [
		["Stromanschluss", int(GameState.power_tier), GameState.POWER_TIERS.size()],
		["Router", int(GameState.router_tier), GameState.ROUTER_TIERS.size()],
	]
	for row_v in tiered:
		var row: Array = row_v
		var tier := int(row[1])
		var count := maxi(1, int(row[2]))
		var card := FinanceApps._card(body, FinanceApps.COL_ACCENT)
		card.add_child(FinanceApps._label(tr("%s  •  Stufe %d von %d") % [tr(str(row[0])), tier + 1, count], 15, FinanceApps.COL_TEXT))
		card.add_child(FinanceApps._bar(float(tier + 1) / float(count), FinanceApps.COL_ACCENT))
	var room_card := FinanceApps._card(body)
	room_card.add_child(FinanceApps._label(tr("Raumausbau  •  Stufe %d") % int(GameState.room_level), 15, FinanceApps.COL_TEXT))
	var ai_card := FinanceApps._card(body)
	ai_card.add_child(FinanceApps._label(tr("KI-Plattform  •  Stufe %d") % int(GameState.ai_platform_level), 15, FinanceApps.COL_TEXT))


func _render_cams() -> void:
	var body := FinanceApps._scroll_body(_win_body)
	var ids := CameraApp.cam_ids()
	FinanceApps._header(body, "camera", "Kameras", tr("%d Kameras") % ids.size() if ids.size() != 1 else tr("1 Kamera"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var power: bool = DecorManager.has_power()
	for i in mini(4, ids.size()):
		var pic := ColorRect.new()
		pic.color = Color(0.10, 0.16, 0.17) if power else Color(0.03, 0.03, 0.04)
		pic.custom_minimum_size = Vector2(300, 168)
		pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(pic)
		var p: Vector3 = (GameState.decor_items[ids[i]] as Dictionary).get("pos", Vector3.ZERO)
		var l := FinanceApps._label((tr("KAM %d  %s") % [i + 1, CameraApp.place_name(p)]) if power else tr("KEIN STROM"), 14, Color(0.80, 0.95, 0.88))
		l.position = Vector2(10, 8)
		pic.add_child(l)


func _render_monitor() -> void:
	var body := FinanceApps._scroll_body(_win_body)
	FinanceApps._header(body, "chart", "Task-Manager", "Live-Werte deines Rechenzentrums.")
	var watts := float(GameState.total_watts)
	var maxw := maxf(1.0, float(GameState.max_watts))
	var temp := float(GameState.room_temp)
	var used := float(GameState.used_compute)
	var total := maxf(1.0, float(GameState.total_compute))
	FinanceApps._stat_tiles(body, [
		["Stromlast", "%d / %d W" % [int(watts), int(maxw)], FinanceApps.COL_BAD if watts / maxw > 0.9 else FinanceApps.COL_TEXT],
		["Raumtemperatur", "%.1f °C" % temp, FinanceApps.COL_BAD if temp >= 60.0 else FinanceApps.COL_TEXT],
		["Rechenleistung", "%d / %d CU" % [int(used), int(total)], FinanceApps.COL_TEXT],
	])
	var chart_card := FinanceApps._card(body)
	chart_card.add_child(FinanceApps._label(tr("Stromlast, letzte %d Sekunden") % HISTORY_LEN, 13, FinanceApps.COL_MUTED))
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, 170)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.draw.connect(_draw_chart.bind(chart, _watt_hist.duplicate()))
	chart_card.add_child(chart)
	var bars_card := FinanceApps._card(body)
	bars_card.add_child(FinanceApps._label("Stromlast", 12, FinanceApps.COL_MUTED))
	bars_card.add_child(FinanceApps._bar(watts / maxw, FinanceApps.COL_ACCENT))
	bars_card.add_child(FinanceApps._label("Temperatur", 12, FinanceApps.COL_MUTED))
	bars_card.add_child(FinanceApps._bar(temp / 80.0, FinanceApps.COL_WARN))
	bars_card.add_child(FinanceApps._label("Auslastung", 12, FinanceApps.COL_MUTED))
	bars_card.add_child(FinanceApps._bar(used / total, FinanceApps.COL_GOOD))


func _draw_chart(chart: Control, hist: PackedFloat32Array) -> void:
	var sz := chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.97, 0.98, 1.0))
	for g in range(1, 4):
		var gy := sz.y * float(g) / 4.0
		chart.draw_line(Vector2(0, gy), Vector2(sz.x, gy), Color(0.85, 0.88, 0.92), 1.0)
	if hist.size() < 2:
		return
	var offset := HISTORY_LEN - hist.size()
	var pts := PackedVector2Array()
	for i in range(hist.size()):
		var x := sz.x * float(i + offset) / float(HISTORY_LEN - 1)
		pts.append(Vector2(x, sz.y * (1.0 - clampf(hist[i], 0.0, 1.0))))
	chart.draw_polyline(pts, FinanceApps.COL_ACCENT, 2.0, true)