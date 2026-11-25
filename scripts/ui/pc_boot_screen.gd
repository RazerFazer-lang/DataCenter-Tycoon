class_name PcBootScreen
extends Control
## Hochfahr-Animation des Büro-PCs.
## Kaltstart: Hersteller-Logo, BIOS-Selbsttest, Ladekreis, Anmeldung. Die Anmeldung wartet auf Klick oder Enter.
## Aufwachen aus dem Energiesparmodus: nur der Anmeldebildschirm.
## Klick, Leertaste oder Enter springt direkt zur Anmeldung.

signal finished

const COLD_DURATION := 6.1
const COLD_LOGIN_START := 4.4
const WAKE_DURATION := 1.4
## Ab hier wartet die Anmeldung. Ohne Eingabe geht es nach AUTO_LOGIN Sekunden von selbst weiter.
const LOGIN_HOLD := 4.9
const AUTO_LOGIN := 6.0
const PASSWORD_TIME := 0.5
const PASSWORD_DOTS := 8
const FADE_TIME := 0.4
const VENDOR_START := 0.3
const POST_START := 1.4
const POST_LINE_STEP := 0.11
const OS_LOGO_START := 2.85
const MEMORY_MB := 32768
const MEMORY_COUNT_TIME := 0.5
const SHUTDOWN_DURATION := 2.2
const SHUTDOWN_FADE := 0.6
const MODE_BOOT := 0
const MODE_SHUTDOWN := 1

const POST_LINES: Array[String] = [
	"NTX UEFI BIOS v2.14.1187   (C) 2026 NTX Computer GmbH",
	"",
	"Prozessor: 16-Kern Workstation-CPU @ 3,80 GHz",
	"Arbeitsspeicher-Test: %MEM%",
	"Systemlaufwerk: NVMe SSD 1 TB ............ OK",
	"Netzwerk: 10-Gigabit-Ethernet ............ verbunden",
	"USB-Geräte: Tastatur, Maus, Headset ...... OK",
	"",
	"Lade Startmanager ...",
]

## false für die Kopie auf dem 3D-Monitor: kein Ton, keine Eingaben.
var interactive: bool = true

var _cold: bool = true
var _mode: int = MODE_BOOT
var _t: float = 0.0
var _running: bool = false
var _login_pressed: bool = false
var _login_wait: float = 0.0
var _user: String = ""
var _font: Font
var _mono: SystemFont


func _init() -> void:
	_font = ThemeDB.fallback_font
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])


func _ready() -> void:
	# Per Code erzeugt startet das Control mit Größe 0 × 0. set_anchors_preset allein behält diese Größe,
	# dann wird der Boot-/Anmeldebildschirm verkleinert oben links gezeichnet. Anker und Abstände zusammen setzen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _running:
		visible = false
		set_process(false)


func play(cold: bool, user_name: String, start_offset: float = 0.0) -> void:
	_mode = MODE_BOOT
	_cold = cold
	_user = user_name.strip_edges()
	_t = maxf(0.0, start_offset)
	_login_pressed = not cold
	_login_wait = 0.0
	if cold:
		_t = minf(_t, LOGIN_HOLD)
	_running = true
	modulate.a = 1.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()
	if interactive and start_offset <= 0.0:
		SfxManager.play("click", -4.0, 0.55 if cold else 0.9)


## Herunterfahren: "Wird heruntergefahren" auf dem Hintergrundbild, danach Schwarz.
## Das schwarze Bild bleibt stehen, bis stop() oder play() aufgerufen wird.
func play_shutdown() -> void:
	_mode = MODE_SHUTDOWN
	_t = 0.0
	if interactive:
		SfxManager.play("win_shutdown", -8.0)
	_running = true
	modulate.a = 1.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func is_showing_shutdown() -> bool:
	return visible and _mode == MODE_SHUTDOWN


func stop() -> void:
	_running = false
	visible = false
	modulate.a = 1.0
	set_process(false)


func is_running() -> bool:
	return _running


func skip() -> void:
	if not _running or _mode == MODE_SHUTDOWN:
		return
	if _cold and _t < COLD_LOGIN_START:
		_t = COLD_LOGIN_START
	elif _cold and not _login_pressed:
		_press_login()
	elif _t < _duration():
		_t = _duration()
	queue_redraw()


func is_waiting_for_login() -> bool:
	return _running and _mode == MODE_BOOT and _cold and not _login_pressed and _t >= LOGIN_HOLD - 0.01


func _press_login() -> void:
	_login_pressed = true
	_t = maxf(_t, LOGIN_HOLD)
	if interactive:
		SfxManager.play_typing_key(-8.0)
	queue_redraw()


func _duration() -> float:
	if _mode == MODE_SHUTDOWN:
		return SHUTDOWN_DURATION
	return COLD_DURATION if _cold else WAKE_DURATION


func _process(delta: float) -> void:
	if not _running:
		return
	var before := _t
	_t += delta
	if _mode == MODE_SHUTDOWN:
		if _t >= SHUTDOWN_DURATION:
			_t = SHUTDOWN_DURATION
			_running = false
			set_process(false)
			queue_redraw()
			finished.emit()
			return
		queue_redraw()
		return
	if _cold and not _login_pressed and _t >= LOGIN_HOLD:
		_t = LOGIN_HOLD
		_login_wait += delta
		if interactive and _login_wait >= AUTO_LOGIN:
			_press_login()
	if interactive and _cold and _login_pressed and _t < LOGIN_HOLD + PASSWORD_TIME and int(before * 16.0) != int(_t * 16.0):
		SfxManager.play_typing_key(-12.0)
	if interactive and _cold and before < COLD_LOGIN_START and _t >= COLD_LOGIN_START:
		SfxManager.play("click", -10.0, 1.3)
	var dur := _duration()
	if interactive and _cold and before < dur and _t >= dur:
		SfxManager.play("win_logon", -8.0)
	if _t >= dur:
		modulate.a = clampf(1.0 - (_t - dur) / FADE_TIME, 0.0, 1.0)
		if _t >= dur + FADE_TIME:
			stop()
			finished.emit()
			return
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive or not _running:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		skip()
		accept_event()


func _input(event: InputEvent) -> void:
	if not interactive or not _running:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		skip()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- Zeichnen

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var k := maxf(0.35, size.y / 720.0)
	draw_rect(r, Color.BLACK)
	if _mode == MODE_SHUTDOWN:
		_draw_shutdown(r, k, _t)
		return
	if not _cold:
		_draw_login(r, k, _t)
	elif _t >= COLD_LOGIN_START:
		_draw_login(r, k, _t - COLD_LOGIN_START)
	elif _t >= OS_LOGO_START:
		_draw_os_logo(r, k, _t - OS_LOGO_START)
	elif _t >= POST_START and _t < OS_LOGO_START - 0.2:
		_draw_post(r, k, _t - POST_START)
	elif _t >= VENDOR_START and _t < POST_START:
		_draw_vendor(r, k, _t - VENDOR_START)


func _draw_vendor(r: Rect2, k: float, t: float) -> void:
	var a := clampf(t / 0.25, 0.0, 1.0)
	var c := r.get_center()
	var fs := int(96.0 * k)
	_text_center("NTX", c.y + fs * 0.3, fs, Color(1, 1, 1, a), r.size.x, _font)
	var bar_w := 220.0 * k
	draw_rect(Rect2(c.x - bar_w * 0.5, c.y + fs * 0.5, bar_w, 5.0 * k), Color(0.86, 0.12, 0.16, a))
	_text_center("PERFORMANCE WORKSTATION", c.y + fs * 0.5 + 34.0 * k, int(18.0 * k), Color(0.75, 0.77, 0.80, a), r.size.x, _font)
	draw_string(_font, Vector2(30.0 * k, r.size.y - 30.0 * k), tr("ENTF: BIOS-Setup    F12: Bootmenü"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(15.0 * k), Color(0.70, 0.70, 0.70, a))


func _draw_post(r: Rect2, k: float, t: float) -> void:
	var fs := int(17.0 * k)
	var lh := float(fs) * 1.45
	var x := 36.0 * k
	var y := 46.0 * k
	var text_col := Color(0.82, 0.84, 0.86)
	draw_string(_font, Vector2(r.size.x - 140.0 * k, 60.0 * k), "NTX", HORIZONTAL_ALIGNMENT_LEFT, -1, int(40.0 * k), Color(1, 1, 1, 0.9))
	var shown := mini(POST_LINES.size(), int(t / POST_LINE_STEP) + 1)
	for i in range(shown):
		var line: String = tr(POST_LINES[i]) if not POST_LINES[i].is_empty() else ""
		if line.contains("%MEM%"):
			var line_t := t - float(i) * POST_LINE_STEP
			var mb := int(clampf(line_t / MEMORY_COUNT_TIME, 0.0, 1.0) * float(MEMORY_MB))
			var mem_txt := ("%d MB" % mb) + (" OK" if mb >= MEMORY_MB else "")
			line = line.replace("%MEM%", mem_txt)
		draw_string(_mono, Vector2(x, y + lh * float(i)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	if fmod(t, 0.5) < 0.25:
		var cy := y + lh * float(shown)
		draw_rect(Rect2(x, cy - float(fs) * 0.15, float(fs) * 0.6, float(fs) * 0.2), text_col)


func _draw_os_logo(r: Rect2, k: float, t: float) -> void:
	var a := clampf(t / 0.35, 0.0, 1.0)
	var c := r.get_center()
	var s := 120.0 * k
	UIStyle.draw_icon(self, "verion", Rect2(c.x - s * 0.5, c.y - s * 0.85, s, s), Color(0.20, 0.60, 1.0, a))
	_draw_spinner(Vector2(c.x, c.y + s * 0.75), 22.0 * k, t, a)


func _draw_login(r: Rect2, k: float, t: float) -> void:
	draw_wallpaper(self, r)
	draw_rect(r, Color(0.0, 0.01, 0.03, 0.30))
	var c := r.get_center()
	_text_center(format_real_clock(), r.position.y + 118.0 * k, int(76.0 * k), Color(1, 1, 1, 0.95), r.size.x, _font)
	_text_center(format_real_date(), r.position.y + 158.0 * k, int(20.0 * k), Color(1, 1, 1, 0.75), r.size.x, _font)
	var av_r := 54.0 * k
	var av_c := Vector2(c.x, c.y + 10.0 * k)
	draw_circle(av_c, av_r + 4.0 * k, Color(1, 1, 1, 0.18))
	draw_circle(av_c, av_r, Color(0.12, 0.36, 0.72))
	draw_circle(av_c + Vector2(0, av_r * 0.22), av_r * 0.78, Color(0.16, 0.46, 0.88, 0.55))
	var shown_name := _user if not _user.is_empty() else "Admin"
	_text_center(shown_name.substr(0, 1).to_upper(), av_c.y + 19.0 * k, int(54.0 * k), Color.WHITE, r.size.x, _font)
	_text_center(shown_name, av_c.y + av_r + 40.0 * k, int(26.0 * k), Color.WHITE, r.size.x, _font)
	var y := av_c.y + av_r + 62.0 * k
	var press_t := _t - LOGIN_HOLD if _cold else t
	if _login_pressed and press_t > PASSWORD_TIME:
		_draw_spinner(Vector2(c.x - 70.0 * k, y + 20.0 * k), 10.0 * k, t, 1.0)
		draw_string(_font, Vector2(c.x - 48.0 * k, y + 27.0 * k), tr("Willkommen"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k), Color.WHITE)
	else:
		# Kennwortfeld: erst leer mit Hinweis, nach dem Klick tippen sich die Punkte.
		var box := Rect2(c.x - 125.0 * k, y, 250.0 * k, 38.0 * k)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.04, 0.09, 0.70)
		sb.border_color = Color(1, 1, 1, 0.30)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(19.0 * k))
		draw_style_box(sb, box)
		var btn := Rect2(box.end.x - 34.0 * k, box.position.y + 4.0 * k, 30.0 * k, 30.0 * k)
		draw_circle(btn.get_center(), 14.0 * k, VerionTheme.ACCENT)
		var bc := btn.get_center()
		draw_polyline(PackedVector2Array([bc + Vector2(-4, -6) * k, bc + Vector2(4, 0) * k, bc + Vector2(-4, 6) * k]), Color.WHITE, 2.2 * k, true)
		if _login_pressed:
			var dots := clampi(int(press_t / PASSWORD_TIME * float(PASSWORD_DOTS)) + 1, 0, PASSWORD_DOTS)
			for i in dots:
				draw_circle(Vector2(box.position.x + (26.0 + 15.0 * float(i)) * k, box.get_center().y), 4.0 * k, Color.WHITE)
		else:
			var a := 0.55 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.004)
			draw_string(_font, Vector2(box.position.x + 18.0 * k, box.get_center().y + 5.0 * k), tr("Klick oder Enter"), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 60.0 * k, int(14.0 * k), Color(1, 1, 1, a))
	UIStyle.draw_icon(self, "verion", Rect2(r.position.x + 28.0 * k, r.end.y - 58.0 * k, 30.0 * k, 30.0 * k), Color(1, 1, 1, 0.8))
	draw_string(_font, Vector2(r.position.x + 68.0 * k, r.end.y - 36.0 * k), "Verion OS 4", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k), Color(1, 1, 1, 0.75))
	var fade := clampf(t / 0.3, 0.0, 1.0)
	if fade < 1.0:
		draw_rect(r, Color(0, 0, 0, 1.0 - fade))


func _draw_shutdown(r: Rect2, k: float, t: float) -> void:
	draw_wallpaper(self, r)
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.35))
	var c := r.get_center()
	_draw_spinner(Vector2(c.x - 118.0 * k, c.y - 8.0 * k), 11.0 * k, t, 1.0)
	draw_string(_font, Vector2(c.x - 96.0 * k, c.y), tr("Wird heruntergefahren"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * k), Color.WHITE)
	var black := clampf((t - (SHUTDOWN_DURATION - SHUTDOWN_FADE)) / SHUTDOWN_FADE, 0.0, 1.0)
	if black > 0.0:
		draw_rect(r, Color(0.0, 0.0, 0.0, black))


func _draw_spinner(center: Vector2, radius: float, t: float, alpha: float) -> void:
	for i in range(6):
		var ang := t * 5.0 - float(i) * 0.42
		var p := center + Vector2(cos(ang), sin(ang)) * radius
		draw_circle(p, radius * 0.14, Color(1, 1, 1, alpha * (1.0 - float(i) * 0.15)))


func _text_center(text: String, baseline_y: float, fs: int, col: Color, width: float, font: Font) -> void:
	draw_string(font, Vector2(0.0, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)


# ---------------------------------------------------------------- Gemeinsam mit dem 3D-Monitor

## Verion-Hintergrund: Nachthimmel mit Lichtbändern und dem gefalteten V.
static func draw_wallpaper(ci: CanvasItem, r: Rect2) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([
		Color(0.030, 0.050, 0.120), Color(0.050, 0.070, 0.180), Color(0.020, 0.030, 0.075), Color(0.015, 0.022, 0.055),
	]))
	var s := r.size
	# Sterne, feste Verteilung
	for i in 70:
		var sx := fposmod(float(i) * 0.6180339 + 0.13, 1.0)
		var sy := fposmod(float(i) * 0.7548776 + 0.37, 1.0)
		var a := 0.10 + 0.28 * fposmod(float(i) * 0.3247, 1.0)
		ci.draw_circle(r.position + Vector2(sx * s.x, sy * s.y * 0.72), s.y * (0.0010 + 0.0012 * fposmod(float(i) * 0.91, 1.0)), Color(0.8, 0.9, 1.0, a))
	# Lichtbänder
	var bands := [
		[0.60, 0.10, Color(0.10, 0.75, 0.80), 0.0, 0.20], [0.68, 0.13, Color(0.22, 0.46, 1.00), 1.1, 0.26],
		[0.78, 0.11, Color(0.52, 0.30, 0.95), 2.0, 0.24], [0.88, 0.10, Color(0.80, 0.24, 0.66), 2.9, 0.16],
	]
	for b in bands:
		var col: Color = b[2]
		var steps := 36
		for layer in 3:
			var th := s.y * float(b[1]) * (1.0 - 0.28 * float(layer))
			for j in steps:
				var u0 := float(j) / float(steps)
				var u1 := float(j + 1) / float(steps)
				var y0 := _band_y(u0, float(b[0]), float(b[3])) * s.y
				var y1 := _band_y(u1, float(b[0]), float(b[3])) * s.y
				var a0 := float(b[4]) * 0.34 * (0.35 + 0.65 * sin(u0 * PI))
				var a1 := float(b[4]) * 0.34 * (0.35 + 0.65 * sin(u1 * PI))
				ci.draw_polygon(PackedVector2Array([
					r.position + Vector2(u0 * s.x, y0 - th), r.position + Vector2(u1 * s.x, y1 - th),
					r.position + Vector2(u1 * s.x, y1), r.position + Vector2(u0 * s.x, y0)]),
					PackedColorArray([Color(col, 0.0), Color(col, 0.0), Color(col, a1), Color(col, a0)]))
				ci.draw_polygon(PackedVector2Array([
					r.position + Vector2(u0 * s.x, y0), r.position + Vector2(u1 * s.x, y1),
					r.position + Vector2(u1 * s.x, y1 + th * 0.35), r.position + Vector2(u0 * s.x, y0 + th * 0.35)]),
					PackedColorArray([Color(col, a0), Color(col, a1), Color(col, 0.0), Color(col, 0.0)]))
	# Großes V aus zwei Flächen
	var c := r.position + Vector2(s.x * 0.5, s.y * 0.44)
	var q := s.y * 0.30
	ci.draw_polygon(PackedVector2Array([c + Vector2(-0.95, -0.80) * q, c + Vector2(-0.42, -0.80) * q, c + Vector2(0.06, 0.36) * q, c + Vector2(-0.14, 0.84) * q]),
		PackedColorArray([Color(0.35, 0.75, 1.0, 0.34), Color(0.35, 0.75, 1.0, 0.22), Color(0.30, 0.50, 1.0, 0.12), Color(0.30, 0.50, 1.0, 0.20)]))
	ci.draw_polygon(PackedVector2Array([c + Vector2(0.95, -0.80) * q, c + Vector2(0.42, -0.80) * q, c + Vector2(-0.14, 0.84) * q, c + Vector2(0.14, 0.84) * q]),
		PackedColorArray([Color(0.70, 0.45, 1.0, 0.30), Color(0.60, 0.45, 1.0, 0.18), Color(0.30, 0.40, 1.0, 0.16), Color(0.40, 0.35, 1.0, 0.10)]))


static func _band_y(u: float, base: float, ph: float) -> float:
	return base + 0.060 * sin(u * 4.2 + ph) + 0.030 * sin(u * 9.1 + ph * 1.7) - 0.10 * u


const WEEKDAYS: Array[String] = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
const MONTHS: Array[String] = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]


## Echte Uhrzeit des Computers, wie bei einem richtigen PC.
static func format_real_clock() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d" % [int(t["hour"]), int(t["minute"])]


static func format_real_date() -> String:
	var d := Time.get_date_dict_from_system()
	return TranslationServer.translate("{weekday}, {day}. {month}").format({
		"weekday": TranslationServer.translate(WEEKDAYS[int(d["weekday"]) % 7]),
		"day": int(d["day"]),
		"month": TranslationServer.translate(MONTHS[clampi(int(d["month"]) - 1, 0, 11)]),
	})


static func format_game_clock() -> String:
	var tod: float = GameState.time_of_day if GameState.is_active else 0.36
	var minutes := int(fposmod(tod, 1.0) * 1440.0)
	return "%02d:%02d" % [floori(float(minutes) / 60.0), minutes % 60]