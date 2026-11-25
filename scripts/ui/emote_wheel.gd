class_name EmoteWheel
extends Control
## Gesten-Rad: Taste halten, Maus in eine Richtung, loslassen. Die Maus bleibt dabei gefangen.

const EMOTES: Array[String] = ["wave", "thumbs", "point", "clap", "cheer", "dance", "laugh", "salute", "shrug", "facepalm", "nod", "no"]
const LABELS := {
	"wave": "Winken", "thumbs": "Daumen hoch", "point": "Zeigen", "clap": "Klatschen", "cheer": "Jubeln", "dance": "Tanzen",
	"laugh": "Lachen", "salute": "Salutieren", "shrug": "Schulterzucken", "facepalm": "Hand vors Gesicht", "nod": "Nicken", "no": "Kopfschütteln",
}
## Text über dem Kopf der Figur.
const SAYS := {
	"wave": "Hallo!", "thumbs": "Top!", "point": "Schau mal!", "clap": "Bravo!", "cheer": "Juhu!", "dance": "♪ ♫", "laugh": "Haha!", "salute": "Jawohl!",
	"shrug": "Keine Ahnung", "facepalm": "Oh nein …", "nod": "Ja", "no": "Nein",
}

var _vec := Vector2.ZERO
var _sel := -1
var _open := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	visible = true
	_vec = Vector2.ZERO
	_sel = -1
	_open = 0.0


## Schließt und liefert die gewählte Geste ("" = keine).
func close() -> String:
	visible = false
	return EMOTES[_sel] if _sel >= 0 else ""


func move(rel: Vector2) -> void:
	_vec = (_vec + rel).limit_length(150.0)
	if _vec.length() < 36.0:
		_sel = -1
	else:
		var step := TAU / EMOTES.size()
		_sel = int(round(fposmod(_vec.angle() + PI * 0.5, TAU) / step)) % EMOTES.size()
	queue_redraw()


func _process(delta: float) -> void:
	if visible and _open < 1.0:
		_open = minf(1.0, _open + delta * 7.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r1 := 92.0 * _open
	var r2 := 232.0 * _open
	var step := TAU / EMOTES.size()
	var font := get_theme_default_font()
	draw_circle(c, r2 + 6.0, Color(0.03, 0.04, 0.05, 0.55 * _open))
	for i in EMOTES.size():
		var a0 := -PI * 0.5 + (i - 0.5) * step
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(c + Vector2.from_angle(a0 + 0.02 + (step - 0.04) * k / 8.0) * r2)
		for k in 9:
			pts.append(c + Vector2.from_angle(a0 + 0.03 + (step - 0.06) * (8 - k) / 8.0) * r1)
		var on := i == _sel
		draw_colored_polygon(pts, Color(0.86, 0.60, 0.18, 0.92) if on else Color(0.10, 0.12, 0.15, 0.88))
		if _open > 0.7:
			var mid := c + Vector2.from_angle(a0 + step * 0.5) * (r1 + r2) * 0.5
			var words := tr(LABELS[EMOTES[i]])
			var lines: PackedStringArray = words.split(" ") if words.length() > 11 else PackedStringArray([words])
			for li in lines.size():
				var w := font.get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(font, mid + Vector2(-w * 0.5, 5.0 + (li - (lines.size() - 1) * 0.5) * 17.0), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.08, 0.07, 0.05) if on else Color(0.92, 0.93, 0.95))
	draw_circle(c, r1 - 6.0, Color(0.06, 0.07, 0.09, 0.9))
	draw_line(c, c + _vec.limit_length(r1 - 14.0), Color(0.96, 0.72, 0.24), 3.0)
	var t := tr("Gesten")
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, c + Vector2(-tw * 0.5, 34.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.78, 0.82))
