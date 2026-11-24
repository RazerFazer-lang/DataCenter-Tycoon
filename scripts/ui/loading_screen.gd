class_name LoadingScreen
extends Control
## v1.2 Ladebildschirm beim Start eines neuen Spiels, beim Laden eines Spielstands und beim Co-op-Beitritt.
## Hintergrund: dunkler Serverraum-Gang mit langsam vorbeiziehenden Racks und blinkenden Status-LEDs.
## Vorn: Marke, Überschrift des Ladevorgangs, Tipp-Karte, Ladeschritt mit Kreisel und Fortschrittsbalken.

signal loading_finished

const TIPS: Array[String] = [
	"TIPP: Du startest in einer leeren Garage mit $1.800 — kaufe im PC-Shop dein erstes Rack und wähle am Rack [E] per Mausklick ein Mainboard für einen freien Einschub!",
	"TIPP: Kaufe CPUs, DDR2–DDR5 RAM, GPUs, NVMe-SSDs & Netzteile im PC-Shop ins Teile-Lager — und schraube sie am Rack [E] direkt ein!",
	"TIPP: Vermiete deine Racks für Webhosting, Game-Server, Cloud-Storage, Streaming, Datenbanken oder KI — und prüfe live, ob der RAM (GB) reicht!",
	"TIPP: Überlastete Kunden schreiben Tickets in der Support-App oder rufen live am PC an — rechtzeitiges Antworten kauft dir Zeit zum Aufrüsten!",
	"TIPP: Reiner 1-Hand-Modus — schau einfach auf eine gelbe Strombuchse oder blaue LAN-Buchse und drücke [E], um direkt ein Kabel zu ziehen!",
	"TIPP: Dein alter 50-Mbit/s-DSL-Router kommt bei vielen Usern schnell ans Limit! Rüste ihn am Wand-Router [F] oder am PC bis auf 100 Gbit/s auf.",
]

const STAGES: Array[String] = [
	"Initialisiere Gebäude-Architektur & 3D-Beleuchtung…",
	"Lade 66 Hardware-Komponenten (DDR2–DDR5, EPYC, H200)…",
	"Kalibriere Raum-Akustik & 3D-Lüfter-Simulation…",
	"Starte Windows-Workstation & Kunden-Support-Desk…",
	"Synchronisiere Co-op-Netzwerk & Weltzustand…",
	"Rechenzentrum bereit!",
]

const TIP_INTERVAL := 4.5
const FADE_IN_TIME := 0.35
const FADE_OUT_TIME := 0.65
const SPIN_SPEED := 5.5
## Spielbild als Hintergrund. Fehlt es, bleibt der gezeichnete Serverraum-Gang.
const KEYART_PATH := "res://assets/branding/title_keyart.png"
const BG_PATH := "res://assets/loading/loading_bg.png"

var _aisle: RackAisle
var _bg: TextureRect
var _content: Control
var _spinner: Control
var _title_lbl: Label
var _subtitle_lbl: Label
var _stage_lbl: Label
var _pct_lbl: Label
var _progress_bar: ProgressBar
var _tip_lbl: Label
var _tip_count_lbl: Label

var _active: bool = false
var _elapsed: float = 0.0
var _duration: float = 1.65
var _fading_out: bool = false
var _stage_idx: int = -1
var _tip_idx: int = 0
var _tip_t: float = 0.0
var _spin_angle: float = 0.0
var _fade_tween: Tween


## Serverraum-Gang: zwei Reihen Racks in unterschiedlicher Tiefe ziehen langsam nach links.
## Das LED-Muster jeder Höheneinheit ergibt sich aus einem Hash, deshalb muss nichts gespeichert werden.
class RackAisle extends Control:
	const UNITS := 18
	const LED_GREEN := Color(0.30, 0.86, 0.42)
	const LED_AMBER := Color(0.98, 0.66, 0.18)
	const LED_BLUE := Color(0.36, 0.62, 0.98)

	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func tick(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 1.0 or s.y < 1.0:
			return
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.035, 0.038, 0.044))
		# Kabeltrasse unter der Decke
		draw_rect(Rect2(0.0, s.y * 0.03, s.x, maxf(3.0, s.y * 0.006)), Color(0.11, 0.115, 0.125))
		_draw_layer(s, 0, s.y * 0.20, s.y * 0.50, s.y * 0.17, s.y * 0.02, 6.0, 0.45)
		_draw_layer(s, 1, s.y * 0.07, s.y * 0.85, s.y * 0.28, s.y * 0.035, 14.0, 1.0)
		# Boden
		draw_rect(Rect2(0.0, s.y * 0.92, s.x, s.y * 0.08), Color(0.028, 0.030, 0.034))
		draw_line(Vector2(0.0, s.y * 0.92), Vector2(s.x, s.y * 0.92), Color(0.12, 0.125, 0.135), 1.0)

	func _draw_layer(s: Vector2, layer: int, top: float, h: float, w: float, gap: float, speed: float, bright: float) -> void:
		var pitch := w + gap
		var travel := _t * speed
		var first := floori(travel / pitch)
		var scroll := travel - float(first) * pitch
		var count := ceili(s.x / pitch) + 1
		var unit_h := 0.0
		for i in range(-1, count):
			var k := first + i
			var r := Rect2(float(i) * pitch - scroll, top, w, h)
			draw_rect(r, _dim(Color(0.085, 0.090, 0.100), bright))
			draw_rect(r, _dim(Color(0.17, 0.18, 0.20), bright), false, 1.0)
			var inner := r.grow(-w * 0.07)
			draw_rect(inner, _dim(Color(0.050, 0.053, 0.060), bright))
			unit_h = inner.size.y / float(UNITS)
			var led_size := Vector2(maxf(2.0, w * 0.020), maxf(2.0, unit_h * 0.18))
			for u in range(UNITS):
				var y := inner.position.y + float(u) * unit_h
				draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), _dim(Color(0.11, 0.115, 0.13), bright), 1.0)
				var hv := absi(hash(Vector3i(k, u, layer)))
				if hv % 5 == 0:
					continue # leere Blende
				# Laufwerksschacht
				draw_rect(Rect2(inner.position.x + w * 0.34, y + unit_h * 0.28, inner.size.x * 0.56, unit_h * 0.44), _dim(Color(0.095, 0.10, 0.11), bright))
				var col := LED_GREEN
				var ci := (hv >> 9) % 10
				if ci >= 8:
					col = LED_AMBER
				elif ci == 7:
					col = LED_BLUE
				var phase := float(hv % 628) * 0.01
				var rate := 1.5 + float((hv >> 4) % 40) * 0.1
				var on := 0.25 + 0.75 * clampf(sin(_t * rate + phase) * 3.0, 0.0, 1.0)
				var lp := Vector2(inner.position.x + w * 0.06, y + (unit_h - led_size.y) * 0.5)
				draw_rect(Rect2(lp - led_size, led_size * 3.0), Color(col.r, col.g, col.b, 0.10 * on * bright))
				draw_rect(Rect2(lp, led_size), Color(col.r, col.g, col.b, on * bright))
				draw_rect(Rect2(lp + Vector2(led_size.x * 2.5, 0.0), led_size), Color(LED_GREEN.r, LED_GREEN.g, LED_GREEN.b, 0.5 * bright))

	func _dim(c: Color, f: float) -> Color:
		return Color(c.r * f, c.g * f, c.b * f, c.a)


func _ready() -> void:
	# Per Code erzeugt startet das Control mit Größe 0 × 0. set_anchors_preset allein behält diese Größe,
	# dann ist nur ein Teil des Ladebildschirms zu sehen. Anker und Abstände müssen zusammen gesetzt werden.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func start_loading(headline: String = "LADE RECHENZENTRUM…", duration: float = 1.65) -> void:
	# Ein noch laufendes Ausblenden darf den neuen Ladevorgang nicht verstecken
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_active = true
	_fading_out = false
	_elapsed = 0.0
	_duration = maxf(0.8, duration)
	_subtitle_lbl.text = tr(headline).to_upper()
	_show_tip(randi() % TIPS.size(), false)
	_tip_t = 0.0
	_progress_bar.value = 0.0
	_pct_lbl.text = "0 %"
	_set_stage(0, false)
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_content.modulate.a = 0.0
	_fade_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(_content, "modulate:a", 1.0, FADE_IN_TIME)


func _process(delta: float) -> void:
	if not _active:
		return
	if _aisle.visible:
		_aisle.tick(delta)
	if _bg != null:
		_bg.pivot_offset = _bg.size * 0.5
		var z := 1.03 + clampf(_elapsed / maxf(_duration, 0.5), 0.0, 1.0) * 0.05
		_bg.scale = Vector2(z, z)
	_spin_angle = wrapf(_spin_angle + delta * SPIN_SPEED, 0.0, TAU)
	_spinner.queue_redraw()
	if _fading_out:
		return

	_elapsed += delta
	var raw_t := clampf(_elapsed / _duration, 0.0, 1.0)
	var eased := raw_t * raw_t * (3.0 - 2.0 * raw_t)
	var pct := eased * 100.0
	_progress_bar.value = pct
	_pct_lbl.text = "%d %%" % int(roundf(pct))

	var stage_idx := clampi(floori(raw_t * float(STAGES.size() - 1)), 0, STAGES.size() - 1)
	if raw_t >= 0.96:
		stage_idx = STAGES.size() - 1
	if stage_idx != _stage_idx:
		_set_stage(stage_idx, true)

	_tip_t += delta
	if _tip_t >= TIP_INTERVAL:
		_tip_t = 0.0
		_show_tip((_tip_idx + 1) % TIPS.size(), true)

	if raw_t >= 1.0:
		_fading_out = true
		# Während des Ausblendens keine Klicks mehr abfangen
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_TIME)
		_fade_tween.tween_callback(_on_fade_out_done)


## Erst wenn der Ladebildschirm ganz verschwunden ist, darf das Hauptmenü kommen.
## Sonst liegen beide halb transparent übereinander.
func _on_fade_out_done() -> void:
	_active = false
	visible = false
	modulate.a = 1.0
	loading_finished.emit()


func _set_stage(idx: int, animate: bool) -> void:
	_stage_idx = idx
	_stage_lbl.text = tr(STAGES[idx])
	var done := idx == STAGES.size() - 1
	_stage_lbl.add_theme_color_override("font_color", UIStyle.COL_GREEN if done else UIStyle.COL_TEXT_MAIN)
	if animate:
		_stage_lbl.modulate.a = 0.3
		_stage_lbl.create_tween().tween_property(_stage_lbl, "modulate:a", 1.0, 0.2)
	else:
		_stage_lbl.modulate.a = 1.0


func _show_tip(idx: int, animate: bool) -> void:
	_tip_idx = idx
	_tip_lbl.text = tr(TIPS[idx]).trim_prefix(tr("TIPP: "))
	_tip_count_lbl.text = "%d / %d" % [idx + 1, TIPS.size()]
	if animate:
		_tip_lbl.modulate.a = 0.0
		_tip_lbl.create_tween().tween_property(_tip_lbl, "modulate:a", 1.0, 0.3)
	else:
		_tip_lbl.modulate.a = 1.0


func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := minf(c.x, c.y) - 2.0
	_spinner.draw_arc(c, r, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.10), 2.0, true)
	_spinner.draw_arc(c, r, _spin_angle, _spin_angle + PI * 0.6, 16, UIStyle.COL_ACCENT, 2.0, true)


func _build_ui() -> void:
	var display_font := UIStyle.make_display_font(get_theme_default_font(), 0.5, 2)

	_aisle = RackAisle.new()
	_aisle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_aisle)

	var bg_tex: Texture2D = null
	if ResourceLoader.exists(KEYART_PATH):
		bg_tex = load(KEYART_PATH) as Texture2D
	elif ResourceLoader.exists(BG_PATH):
		bg_tex = load(BG_PATH) as Texture2D
	if bg_tex != null:
		_bg = TextureRect.new()
		_bg.texture = bg_tex
		_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
		_aisle.visible = false

	# Abdunklung: oben leicht, unten kräftig, dazu eine Vignette an den Rändern
	var shade := Color(0.02, 0.022, 0.026)
	add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(shade, 0.72), Color(shade, 0.28), Color(shade, 0.97)]),
		PackedFloat32Array([0.0, 0.40, 0.86]),
		Vector2(0.5, 0.0), Vector2(0.5, 1.0)
	))
	add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.65)]),
		PackedFloat32Array([0.45, 1.0]),
		Vector2(0.5, 0.5), Vector2(1.05, 0.5), true
	))

	var top_bar := ColorRect.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 2
	top_bar.color = Color(UIStyle.COL_ACCENT, 0.92)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_content = margin

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	margin.add_child(v)

	# Kopfzeile: Logo, Marke, Edition
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(36, 36)
	logo.draw.connect(func() -> void: UIStyle.draw_logo_mark(logo, Rect2(Vector2.ZERO, logo.size)))
	top.add_child(logo)

	_title_lbl = Label.new()
	_title_lbl.text = "DATACENTER TYCOON"
	_title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(_title_lbl, 17, UIStyle.COL_TEXT_MAIN, display_font)
	top.add_child(_title_lbl)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_spacer)

	var edition := Label.new()
	edition.text = "VERION-DIGITAL  •  CO-OP EDITION  •  v%s" % UIStyle.game_version()
	edition.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(edition, 12, UIStyle.COL_TEXT_SUB)
	top.add_child(edition)

	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mid_spacer)

	# Überschrift links, Tipp-Karte rechts
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 48)
	v.add_child(bottom)

	var head_v := VBoxContainer.new()
	head_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_v.size_flags_vertical = Control.SIZE_SHRINK_END
	head_v.add_theme_constant_override("separation", 6)
	bottom.add_child(head_v)

	var overline := Label.new()
	overline.text = "WIRD GELADEN"
	UIStyle.style_label(overline, 12, UIStyle.COL_GOLD_TEXT, display_font)
	head_v.add_child(overline)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = "LADE RECHENZENTRUM…"
	_subtitle_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(_subtitle_lbl, 30, Color(0.96, 0.965, 0.97), display_font, true)
	head_v.add_child(_subtitle_lbl)

	var accent_line := ColorRect.new()
	accent_line.custom_minimum_size = Vector2(72, 3)
	accent_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent_line.color = UIStyle.COL_ACCENT
	head_v.add_child(accent_line)

	var tip_card := PanelContainer.new()
	tip_card.custom_minimum_size = Vector2(420, 0)
	tip_card.size_flags_vertical = Control.SIZE_SHRINK_END
	tip_card.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.07, 0.074, 0.082, 0.88), Color(0.26, 0.27, 0.29, 0.9), 4, 1, 0, 0))
	bottom.add_child(tip_card)

	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 0)
	tip_card.add_child(tip_row)

	var tip_strip := ColorRect.new()
	tip_strip.custom_minimum_size = Vector2(3, 0)
	tip_strip.color = UIStyle.COL_ACCENT
	tip_row.add_child(tip_strip)

	var tip_margin := MarginContainer.new()
	tip_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_margin.add_theme_constant_override("margin_left", 16)
	tip_margin.add_theme_constant_override("margin_right", 16)
	tip_margin.add_theme_constant_override("margin_top", 12)
	tip_margin.add_theme_constant_override("margin_bottom", 14)
	tip_row.add_child(tip_margin)

	var tip_v := VBoxContainer.new()
	tip_v.add_theme_constant_override("separation", 6)
	tip_margin.add_child(tip_v)

	var tip_head := HBoxContainer.new()
	tip_v.add_child(tip_head)
	var tip_title := Label.new()
	tip_title.text = "TIPP"
	tip_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(tip_title, 12, UIStyle.COL_GOLD_TEXT, display_font)
	tip_head.add_child(tip_title)
	_tip_count_lbl = Label.new()
	UIStyle.style_label(_tip_count_lbl, 11, UIStyle.COL_TEXT_SUB)
	tip_head.add_child(_tip_count_lbl)

	_tip_lbl = Label.new()
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(_tip_lbl, 14, Color(0.84, 0.85, 0.85))
	tip_v.add_child(_tip_lbl)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	v.add_child(gap)

	# Ladeschritt mit Kreisel und Prozent
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(22, 22)
	_spinner.draw.connect(_draw_spinner)
	row.add_child(_spinner)

	_stage_lbl = Label.new()
	_stage_lbl.text = tr(STAGES[0])
	_stage_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stage_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(_stage_lbl, 14, UIStyle.COL_TEXT_MAIN)
	row.add_child(_stage_lbl)

	_pct_lbl = Label.new()
	_pct_lbl.text = "0 %"
	_pct_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(_pct_lbl, 15, UIStyle.COL_GOLD_TEXT, display_font)
	row.add_child(_pct_lbl)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap2)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0, 6)
	var bar_styles := UIStyle.make_bar_styles(UIStyle.COL_ACCENT)
	_progress_bar.add_theme_stylebox_override("background", bar_styles[0] as StyleBox)
	_progress_bar.add_theme_stylebox_override("fill", bar_styles[1] as StyleBox)
	v.add_child(_progress_bar)

	_show_tip(0, false)