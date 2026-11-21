class_name PcBootScreen
extends Control
## Hochfahr-Animation des Büro-PCs.
## Kaltstart: Hersteller-Logo, BIOS-Selbsttest, Windows-Ladekreis, Anmeldung.
## Aufwachen aus dem Energiesparmodus: nur der Anmeldebildschirm.
## Klick, Leertaste oder Enter springt direkt zur Anmeldung.

signal finished

const COLD_DURATION := 5.6
const COLD_LOGIN_START := 4.4
const WAKE_DURATION := 1.4
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
	elif _t < _duration():
		_t = _duration()
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
	UIStyle.draw_icon(self, "windows", Rect2(c.x - s * 0.5, c.y - s * 0.85, s, s), Color(0.20, 0.60, 1.0, a))
	_draw_spinner(Vector2(c.x, c.y + s * 0.75), 22.0 * k, t, a)


func _draw_login(r: Rect2, k: float, t: float) -> void:
	draw_wallpaper(self, r)
	var c := r.get_center()
	var av_r := 70.0 * k
	var av_c := Vector2(c.x, c.y - 70.0 * k)
	draw_circle(av_c, av_r, Color(0.88, 0.91, 0.95, 0.95))
	var shown_name := _user if not _user.is_empty() else "Admin"
	_text_center(shown_name.substr(0, 1).to_upper(), av_c.y + 26.0 * k, int(72.0 * k), Color(0.15, 0.30, 0.50), r.size.x, _font)
	_text_center(shown_name, av_c.y + av_r + 50.0 * k, int(34.0 * k), Color.WHITE, r.size.x, _font)
	var text_y := av_c.y + av_r + 110.0 * k
	_draw_spinner(Vector2(c.x - 82.0 * k, text_y - 8.0 * k), 11.0 * k, t, 1.0)
	draw_string(_font, Vector2(c.x - 58.0 * k, text_y), tr("Willkommen"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * k), Color.WHITE)
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

static func draw_wallpaper(ci: CanvasItem, r: Rect2) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([
		Color(0.05, 0.14, 0.32), Color(0.12, 0.36, 0.66), Color(0.26, 0.54, 0.84), Color(0.04, 0.10, 0.24),
	])
	ci.draw_polygon(pts, cols)
	var s := r.size
	ci.draw_circle(r.position + Vector2(s.x * 0.72, s.y * 0.38), s.y * 0.42, Color(0.55, 0.75, 1.0, 0.10))
	ci.draw_circle(r.position + Vector2(s.x * 0.80, s.y * 0.46), s.y * 0.26, Color(0.75, 0.88, 1.0, 0.10))
	ci.draw_circle(r.position + Vector2(s.x * 0.20, s.y * 0.85), s.y * 0.35, Color(0.20, 0.40, 0.80, 0.10))


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