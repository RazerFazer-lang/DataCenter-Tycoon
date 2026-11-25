class_name UIStyle
extends RefCounted
## v1.1 Realistisches Industrie-UI: neutrales Anthrazit, gedämpftes Amber, kleine Radien, Tiefe über Schatten und Kanten.
## Gemeinsam genutzt von Hauptmenü, Loadingscreen, HUD, Pause-Menü, Rack-, Router- und Geräte-Overlays
## (der PC-Monitor bleibt ein heller Desktop).
## Konstantennamen und Funktionssignaturen sind unverändert, damit alle bestehenden Aufrufer weiter funktionieren.

const COL_BG_DARK := Color(0.072, 0.077, 0.086, 0.95)
const COL_BG_CARD := Color(0.112, 0.118, 0.128, 0.97)
const COL_BG_CARD_ALT := Color(0.148, 0.154, 0.166, 0.97)
const COL_BORDER := Color(0.29, 0.30, 0.32, 0.90)
const COL_ACCENT := Color(0.86, 0.62, 0.24)
const COL_GOLD_TEXT := Color(0.93, 0.76, 0.43)
const COL_TEXT_MAIN := Color(0.92, 0.92, 0.90)
const COL_TEXT_SUB := Color(0.63, 0.64, 0.65)
const COL_GREEN := Color(0.42, 0.70, 0.38)
const COL_AMBER := Color(0.90, 0.64, 0.22)
const COL_RED := Color(0.82, 0.31, 0.25)
const COL_BLUE := Color(0.40, 0.59, 0.78)

## Obergrenze für Eckenradien: kantige Panels wirken wie echte Geräte-/Werkzeug-UIs.
const MAX_RADIUS := 4
const BUTTON_RADIUS := 3
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)


static func make_panel(bg: Color = COL_BG_DARK, border: Color = COL_BORDER, radius: int = 10, border_w: int = 1, pad_x: int = 14, pad_y: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(mini(radius, MAX_RADIUS))
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0.0, 4.0)
	return sb


static func style_button(btn: Button, bg: Color = Color(0.165, 0.170, 0.182, 0.97), accent: Color = COL_ACCENT) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(BUTTON_RADIUS)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	# Dunklere Unterkante gibt dem Button Tiefe
	normal.border_width_bottom = 2
	normal.border_blend = false

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.08)
	hover.border_color = accent

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.18)
	pressed.border_color = accent
	pressed.border_width_bottom = 1
	pressed.border_width_top = 2
	pressed.content_margin_top = 7
	pressed.content_margin_bottom = 5

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.105, 0.115, 0.70)
	disabled.border_color = Color(0.22, 0.23, 0.25, 0.50)

	# Fokus-Rahmen für Tastatur-/Controller-Navigation, zeichnet keinen Hintergrund
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(BUTTON_RADIUS)
	focus.set_expand_margin_all(2.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", COL_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", COL_GOLD_TEXT)
	btn.add_theme_color_override("font_focus_color", COL_TEXT_MAIN)
	btn.add_theme_color_override("font_disabled_color", Color(0.46, 0.47, 0.49))


static func make_bar_styles(fill_color: Color) -> Array:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.055, 0.058, 0.064, 0.95)
	bg.border_color = Color(0.20, 0.21, 0.23, 0.90)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.border_color = fill_color.darkened(0.30)
	fill.border_width_bottom = 2
	fill.set_corner_radius_all(2)
	return [bg, fill]


static func animate_popup_open(root_overlay: Control, card: Control = null) -> void:
	root_overlay.visible = true
	root_overlay.modulate.a = 0.0
	var tw := root_overlay.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(root_overlay, "modulate:a", 1.0, 0.16)
	if card != null:
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(0.97, 0.97)
		tw.tween_property(card, "scale", Vector2.ONE, 0.18)


static func animate_popup_close(root_overlay: Control, card: Control = null) -> void:
	if not root_overlay.visible:
		return
	var tw := root_overlay.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(root_overlay, "modulate:a", 0.0, 0.12)
	if card != null:
		card.pivot_offset = card.size * 0.5
		tw.tween_property(card, "scale", Vector2(0.97, 0.97), 0.12)
	var finish := func() -> void:
		root_overlay.visible = false
		root_overlay.modulate.a = 1.0
		if card != null:
			card.scale = Vector2.ONE
	tw.chain().tween_callback(finish)


## Versionsnummer aus den Projekteinstellungen (application/config/version), sonst 1.0.0.
static func game_version() -> String:
	var ver := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return ver if not ver.is_empty() else "1.0.0"


## Etwas fettere Schrift mit Buchstabenabstand für Titel und Überschriften.
static func make_display_font(base: Font, embolden: float = 0.5, glyph_spacing: int = 2) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_embolden = embolden
	fv.spacing_glyph = glyph_spacing
	return fv


static func style_label(lbl: Label, font_size: int, color: Color, font: Font = null, shadow: bool = false) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if font != null:
		lbl.add_theme_font_override("font", font)
	if shadow:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 3)
		lbl.add_theme_constant_override("shadow_outline_size", 6)


## Vollflächiger Farbverlauf (linear oder radial), der keine Maus-Eingaben abfängt.
static func make_gradient_rect(colors: PackedColorArray, offsets: PackedFloat32Array, fill_from: Vector2, fill_to: Vector2, radial: bool = false) -> TextureRect:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	tex.fill_from = fill_from
	tex.fill_to = fill_to
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Runder Schieberegler-Knopf mit Rand, kantengeglättet.
static func make_circle_texture(diameter: int, fill: Color, ring: Color, ring_w: float = 2.0) -> ImageTexture:
	var img := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := float(diameter) * 0.5
	for y in range(diameter):
		for x in range(diameter):
			var d := Vector2(float(x) + 0.5 - r, float(y) + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var c := ring if d > r - ring_w else fill
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	return ImageTexture.create_from_image(img)


## Logo: stilisiertes Rack mit drei Höheneinheiten und Status-LEDs.
static func draw_logo_mark(ci: CanvasItem, r: Rect2, accent: Color = COL_ACCENT) -> void:
	ci.draw_rect(r, Color(0.10, 0.105, 0.115, 0.95))
	ci.draw_rect(r.grow(-1.0), accent, false, 2.0)
	var inner := r.grow(-r.size.x * 0.18)
	var unit_h := inner.size.y / 3.0
	for i in range(3):
		var y := inner.position.y + float(i) * unit_h
		var bar := Rect2(inner.position.x, y + unit_h * 0.16, inner.size.x, unit_h * 0.68)
		ci.draw_rect(bar, Color(0.20, 0.21, 0.23))
		var led_s := bar.size.y * 0.38
		ci.draw_rect(Rect2(bar.position.x + led_s * 0.8, bar.position.y + (bar.size.y - led_s) * 0.5, led_s, led_s), accent if i == 0 else COL_GREEN)
		ci.draw_rect(Rect2(bar.position.x + bar.size.x * 0.45, bar.position.y + bar.size.y * 0.38, bar.size.x * 0.45, bar.size.y * 0.24), Color(0.34, 0.35, 0.38))


const COL_INPUT_BG := Color(0.045, 0.048, 0.054, 0.96)
const COL_INPUT_BORDER := Color(0.24, 0.25, 0.27, 0.90)


## Eingabefeld im Menü-Stil: dunkler Grund, dünner Rand, Akzentrahmen bei Fokus.
static func style_line_edit(le: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_INPUT_BG
	normal.border_color = COL_INPUT_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(BUTTON_RADIUS)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	# Fokus wird über "normal" gezeichnet, daher nur ein Rahmen
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = COL_ACCENT
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(BUTTON_RADIUS)
	var read_only := normal.duplicate() as StyleBoxFlat
	read_only.bg_color = Color(COL_INPUT_BG, 0.6)
	le.add_theme_stylebox_override("normal", normal)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_stylebox_override("read_only", read_only)
	le.add_theme_color_override("font_color", COL_TEXT_MAIN)
	le.add_theme_color_override("font_placeholder_color", Color(0.45, 0.46, 0.48))
	le.add_theme_color_override("caret_color", COL_ACCENT)
	le.add_theme_color_override("selection_color", Color(COL_ACCENT, 0.35))
	le.add_theme_font_size_override("font_size", 14)


## Schieberegler: schmale Spur, Akzent-Füllung, runder Knopf.
static func style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = COL_INPUT_BG
	track.border_color = COL_INPUT_BORDER
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(COL_ACCENT, 0.85)
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = COL_ACCENT.lightened(0.1)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", make_circle_texture(16, Color(0.92, 0.92, 0.90), COL_ACCENT))
	s.add_theme_icon_override("grabber_highlight", make_circle_texture(16, Color.WHITE, COL_ACCENT.lightened(0.15)))


## Gezeichnete HUD-Symbole, damit keine Emoji-Schrift nötig ist.
## kind: "power", "temp", "sun", "moon", "truck", "warn", "info",
##       "cart", "headset", "building", "chart", "save", "verion", "power_off",
##       "net", "phone", "close", "minimize", "check"
static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	if s < 2.0:
		return
	var w := maxf(1.5, s * 0.1)
	match kind:
		"people":
			ci.draw_circle(c + Vector2(-0.16, -0.18) * s, s * 0.12, col)
			ci.draw_circle(c + Vector2(0.20, -0.14) * s, s * 0.10, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.40, 0.38) * s,
				c + Vector2(-0.34, 0.02) * s,
				c + Vector2(0.02, 0.02) * s,
				c + Vector2(0.08, 0.38) * s,
			]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.11, 0.38) * s,
				c + Vector2(0.11, 0.06) * s,
				c + Vector2(0.34, 0.06) * s,
				c + Vector2(0.42, 0.38) * s,
			]), col)
		"bank":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -0.44) * s,
				c + Vector2(0.44, -0.18) * s,
				c + Vector2(-0.44, -0.18) * s,
			]), col)
			for i in range(4):
				var px := -0.30 + float(i) * 0.20
				ci.draw_rect(Rect2(c + Vector2(px - 0.05, -0.12) * s, Vector2(0.10, 0.40) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.44, 0.30) * s, Vector2(0.88, 0.12) * s), col)
		"invoice":
			var pw := s * 0.62
			var ph := s * 0.84
			var tl := c - Vector2(pw, ph) * 0.5
			ci.draw_rect(Rect2(tl, Vector2(pw, ph)), col, false, w)
			for i in range(3):
				var ly := tl.y + ph * (0.30 + float(i) * 0.20)
				ci.draw_line(Vector2(tl.x + pw * 0.2, ly), Vector2(tl.x + pw * 0.8, ly), col, w * 0.8)
		"power":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.10, -0.48) * s,
				c + Vector2(-0.26, 0.06) * s,
				c + Vector2(-0.02, 0.06) * s,
				c + Vector2(-0.10, 0.48) * s,
				c + Vector2(0.26, -0.08) * s,
				c + Vector2(0.02, -0.08) * s,
			]), col)
		"temp":
			ci.draw_line(c + Vector2(0.0, -0.40) * s, c + Vector2(0.0, 0.14) * s, col, s * 0.18)
			ci.draw_circle(c + Vector2(0.0, 0.28) * s, s * 0.18, col)
		"sun":
			ci.draw_circle(c, s * 0.20, col)
			for i in range(8):
				var dir := Vector2.from_angle(float(i) * TAU / 8.0)
				ci.draw_line(c + dir * s * 0.31, c + dir * s * 0.46, col, w)
		"moon":
			# Sichel: äußerer Kreis minus versetzter Kreis gleicher Größe
			var rr := s * 0.40
			var d := rr * 0.62
			var h := sqrt(rr * rr - d * d * 0.25)
			var a := atan2(h, d * 0.5)
			var pts := PackedVector2Array()
			for i in range(17):
				var t := lerpf(a, TAU - a, float(i) / 16.0)
				pts.append(c + Vector2(cos(t), sin(t)) * rr)
			for i in range(1, 16):
				var t2 := lerpf(PI + a, PI - a, float(i) / 16.0)
				pts.append(c + Vector2(d + cos(t2) * rr, sin(t2) * rr))
			ci.draw_colored_polygon(pts, col)
		"truck":
			ci.draw_rect(Rect2(c + Vector2(-0.48, -0.30) * s, Vector2(0.58, 0.44) * s), col)
			ci.draw_rect(Rect2(c + Vector2(0.14, -0.10) * s, Vector2(0.34, 0.24) * s), col)
			ci.draw_circle(c + Vector2(-0.28, 0.22) * s, s * 0.10, col)
			ci.draw_circle(c + Vector2(0.30, 0.22) * s, s * 0.10, col)
		"warn":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(0.0, -0.44) * s,
				c + Vector2(0.48, 0.40) * s,
				c + Vector2(-0.48, 0.40) * s,
				c + Vector2(0.0, -0.44) * s,
			]), col, w, true)
			ci.draw_line(c + Vector2(0.0, -0.14) * s, c + Vector2(0.0, 0.12) * s, col, w)
			ci.draw_rect(Rect2(c + Vector2(-w * 0.5, s * 0.22 - w * 0.5), Vector2(w, w)), col)
		"info":
			ci.draw_arc(c, s * 0.44, 0.0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(0.0, -0.02) * s, c + Vector2(0.0, 0.24) * s, col, w)
			ci.draw_rect(Rect2(c + Vector2(-w * 0.5, -0.20 * s - w * 0.5), Vector2(w, w)), col)
		"cart":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.46, -0.36) * s,
				c + Vector2(-0.30, -0.36) * s,
				c + Vector2(-0.18, 0.14) * s,
				c + Vector2(0.34, 0.14) * s,
				c + Vector2(0.44, -0.22) * s,
				c + Vector2(-0.24, -0.22) * s,
			]), col, w, true)
			ci.draw_circle(c + Vector2(-0.12, 0.32) * s, s * 0.08, col)
			ci.draw_circle(c + Vector2(0.28, 0.32) * s, s * 0.08, col)
		"headset":
			ci.draw_arc(c + Vector2(0.0, 0.04) * s, s * 0.34, PI, TAU, 16, col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-0.44, 0.0) * s, Vector2(0.18, 0.30) * s), col)
			ci.draw_rect(Rect2(c + Vector2(0.26, 0.0) * s, Vector2(0.18, 0.30) * s), col)
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(0.34, 0.30) * s,
				c + Vector2(0.34, 0.42) * s,
				c + Vector2(0.06, 0.42) * s,
			]), col, w, true)
		"building":
			ci.draw_rect(Rect2(c + Vector2(-0.34, -0.42) * s, Vector2(0.68, 0.84) * s), col, false, w)
			for by_i in range(3):
				for bx_i in range(2):
					ci.draw_rect(Rect2(c + Vector2(-0.19 + 0.24 * float(bx_i), -0.28 + 0.22 * float(by_i)) * s, Vector2(0.14, 0.12) * s), col)
		"chart":
			ci.draw_line(c + Vector2(-0.44, 0.42) * s, c + Vector2(0.44, 0.42) * s, col, w)
			var hs := PackedFloat32Array([0.30, 0.55, 0.42, 0.78])
			for i in range(4):
				var bx := -0.38 + 0.21 * float(i)
				ci.draw_rect(Rect2(c + Vector2(bx, 0.36 - hs[i]) * s, Vector2(0.14, hs[i]) * s), col)
		"save":
			ci.draw_rect(Rect2(c + Vector2(-0.40, -0.40) * s, Vector2(0.80, 0.80) * s), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-0.22, -0.40) * s, Vector2(0.40, 0.26) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.24, 0.06) * s, Vector2(0.48, 0.28) * s), col, false, w)
		"verion":
			# Verion OS: gefaltetes V aus zwei Bändern, der rechte Schenkel dunkler
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.46, -0.40) * s, c + Vector2(-0.20, -0.40) * s, c + Vector2(0.03, 0.18) * s, c + Vector2(-0.07, 0.42) * s,
			]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.46, -0.40) * s, c + Vector2(0.20, -0.40) * s, c + Vector2(-0.07, 0.42) * s, c + Vector2(0.07, 0.42) * s,
			]), Color(col.r * 0.72, col.g * 0.72, col.b * 0.72, col.a))
		"power_off":
			ci.draw_arc(c + Vector2(0.0, 0.04) * s, s * 0.36, -PI * 0.5 + 0.7, PI * 1.5 - 0.7, 24, col, w, true)
			ci.draw_line(c + Vector2(0.0, -0.46) * s, c + Vector2(0.0, -0.02) * s, col, w)
		"net":
			ci.draw_arc(c, s * 0.42, 0.0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(-0.42, 0.0) * s, c + Vector2(0.42, 0.0) * s, col, w * 0.8)
			var pts_e := PackedVector2Array()
			for i in range(25):
				var t3 := float(i) / 24.0 * TAU
				pts_e.append(c + Vector2(cos(t3) * 0.18, sin(t3) * 0.42) * s)
			ci.draw_polyline(pts_e, col, w * 0.8, true)
		"phone":
			var pc := c + Vector2(0.12, -0.12) * s
			ci.draw_arc(pc, s * 0.34, PI * 0.5, PI, 12, col, s * 0.14, true)
			ci.draw_circle(pc + Vector2(0.0, 0.34) * s, s * 0.12, col)
			ci.draw_circle(pc + Vector2(-0.34, 0.0) * s, s * 0.12, col)
		"close":
			ci.draw_line(c + Vector2(-0.30, -0.30) * s, c + Vector2(0.30, 0.30) * s, col, w, true)
			ci.draw_line(c + Vector2(0.30, -0.30) * s, c + Vector2(-0.30, 0.30) * s, col, w, true)
		"minimize":
			ci.draw_line(c + Vector2(-0.30, 0.0) * s, c + Vector2(0.30, 0.0) * s, col, w)
		"check":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.34, 0.02) * s,
				c + Vector2(-0.10, 0.28) * s,
				c + Vector2(0.36, -0.26) * s,
			]), col, w * 1.2, true)
		"wifi":
			# Drei Bögen über einem Punkt, wie das WLAN-Symbol im Infobereich
			var wifi_base := c + Vector2(0.0, 0.32) * s
			ci.draw_circle(wifi_base, s * 0.07, col)
			for wi in range(3):
				var wifi_r := s * (0.24 + 0.18 * float(wi))
				ci.draw_arc(wifi_base, wifi_r, -PI * 0.75, -PI * 0.25, 16, col, w, true)
		"speaker":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.44, -0.14) * s,
				c + Vector2(-0.24, -0.14) * s,
				c + Vector2(0.0, -0.38) * s,
				c + Vector2(0.0, 0.38) * s,
				c + Vector2(-0.24, 0.14) * s,
				c + Vector2(-0.44, 0.14) * s,
			]), col)
			var spk_c := c + Vector2(0.02, 0.0) * s
			ci.draw_arc(spk_c, s * 0.20, -PI * 0.3, PI * 0.3, 10, col, w, true)
			ci.draw_arc(spk_c, s * 0.38, -PI * 0.3, PI * 0.3, 14, col, w, true)