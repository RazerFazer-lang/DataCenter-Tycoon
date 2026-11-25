extends Control
## Liniendiagramm für eine Reihe aus StatsHistory. Farben folgen der Darstellung von Verion OS.

const HEADER_H := 18.0
const FOOTER_H := 14.0
const FONT_SIZE := 11
var COL_TEXT := Color(0.42, 0.46, 0.52)
var COL_VALUE := Color(0.10, 0.12, 0.16)
var COL_PLOT_BG := Color(0.96, 0.97, 0.98)
var COL_GRID := Color(0.86, 0.88, 0.91)

## Schlüssel der Reihe in StatsHistory ("money", "watts", "temp").
var series: String = ""
var title: String = ""
## Formatstring für einen Wert, z. B. "%.0f W".
var unit_format: String = "%.0f"
var line_color: Color = Color(0.12, 0.50, 0.84)
## Optionale Grenzlinie (z. B. Stromlimit). NAN = keine.
var ref_value: float = NAN
var ref_label: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(0, 110)
	if VerionTheme.dark:
		COL_TEXT = VerionTheme.MUTED
		COL_VALUE = VerionTheme.TEXT
		COL_PLOT_BG = Color(0.083, 0.098, 0.140)
		COL_GRID = Color(0.17, 0.20, 0.27)
		line_color = line_color.lightened(0.18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	StatsHistory.sample_added.connect(queue_redraw)
	resized.connect(queue_redraw)


func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var values := StatsHistory.get_series(series)

	draw_string(font, Vector2(0, FONT_SIZE), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COL_TEXT)
	if not values.is_empty():
		draw_string(font, Vector2(0, FONT_SIZE), unit_format % values[values.size() - 1],
			HORIZONTAL_ALIGNMENT_RIGHT, w, FONT_SIZE + 1, COL_VALUE)

	var plot := Rect2(0.0, HEADER_H, w, maxf(10.0, size.y - HEADER_H - FOOTER_H))
	draw_rect(plot, COL_PLOT_BG)
	for i in range(3):
		var gy := plot.position.y + plot.size.y * float(i) / 2.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), COL_GRID, 1.0)

	if values.size() < 2:
		draw_string(font, Vector2(0, plot.position.y + plot.size.y * 0.5 + FONT_SIZE * 0.4),
			tr("Sammle Daten..."), HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE, COL_TEXT)
		return

	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var has_ref := is_finite(ref_value)
	if has_ref:
		lo = minf(lo, ref_value)
		hi = maxf(hi, ref_value)
	if hi - lo < 0.001:
		hi += 1.0
		lo -= 1.0
	var pad := (hi - lo) * 0.08
	hi += pad
	lo -= pad

	var n := values.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in range(n):
		var x := plot.position.x + plot.size.x * float(i) / float(n - 1)
		var y := plot.end.y - (values[i] - lo) / (hi - lo) * plot.size.y
		pts[i] = Vector2(x, y)

	if has_ref:
		var ry := plot.end.y - (ref_value - lo) / (hi - lo) * plot.size.y
		var ref_col := Color(0.82, 0.20, 0.16, 0.8)
		draw_dashed_line(Vector2(plot.position.x, ry), Vector2(plot.end.x, ry), ref_col, 1.0, 5.0)
		if not ref_label.is_empty():
			draw_string(font, Vector2(0, ry - 3.0), "%s %s" % [ref_label, unit_format % ref_value],
				HORIZONTAL_ALIGNMENT_RIGHT, w - 4.0, FONT_SIZE - 1, ref_col)

	draw_polyline(pts, line_color, 2.0, true)

	draw_string(font, Vector2(4.0, plot.position.y + FONT_SIZE), unit_format % hi,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, COL_TEXT)
	draw_string(font, Vector2(4.0, plot.end.y - 3.0), unit_format % lo,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, COL_TEXT)

	var span_s := int(StatsHistory.SAMPLE_INTERVAL * float(n - 1))
	var span_txt := tr("vor %d min") % int(span_s / 60.0) if span_s >= 60 else tr("vor %d s") % span_s
	var foot_y := size.y - 2.0
	draw_string(font, Vector2(0, foot_y), span_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, COL_TEXT)
	draw_string(font, Vector2(0, foot_y), tr("jetzt"), HORIZONTAL_ALIGNMENT_RIGHT, w, FONT_SIZE - 1, COL_TEXT)