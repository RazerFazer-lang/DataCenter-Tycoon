class_name VerionTheme
extends RefCounted
## Farben von Verion OS. Die Apps sind mit hellen Farben aufgebaut. apply() setzt fertige
## Oberflächen auf den dunklen Verion-Stil um: helle Flächen werden dunkel, dunkle Schrift hell,
## farbige Knöpfe bleiben farbig. Im hellen Modus passiert nichts.

const BAR := Color(0.045, 0.055, 0.085, 0.94)
const WINDOW := Color(0.083, 0.098, 0.140)
const TITLE := Color(0.110, 0.130, 0.185)
const TITLE_IDLE := Color(0.088, 0.104, 0.148)
const CARD := Color(0.120, 0.142, 0.198)
const CONTROL := Color(0.165, 0.195, 0.268)
const BORDER := Color(0.200, 0.238, 0.325)
const TEXT := Color(0.905, 0.930, 0.970)
const MUTED := Color(0.610, 0.665, 0.760)
const ACCENT := Color(0.235, 0.610, 1.0)
const GOOD := Color(0.270, 0.800, 0.480)
const BAD := Color(0.980, 0.380, 0.360)
const WARN := Color(0.980, 0.720, 0.250)

const L_BAR := Color(0.95, 0.96, 0.98, 0.96)
const L_WINDOW := Color(0.95, 0.96, 0.97)
const L_TITLE := Color(0.90, 0.92, 0.95)

## Farbe je App für Dock und Fensterkopf.
const APP_COLORS := {
	"shop": Color(0.96, 0.55, 0.16), "support": Color(0.10, 0.66, 0.66), "upgrades": Color(0.56, 0.40, 0.90),
	"monitor": Color(0.22, 0.70, 0.36), "staff": Color(0.26, 0.50, 0.92), "bank": Color(0.82, 0.62, 0.16),
	"bills": Color(0.86, 0.28, 0.30), "mail": Color(0.14, 0.58, 0.96), "market": Color(0.84, 0.26, 0.60),
}

static var dark := true


static func app_color(app: String) -> Color:
	return APP_COLORS.get(app, ACCENT)


## Wendet den Stil auf einen fertigen Baum an. Jeder Knoten wird nur einmal umgefärbt.
static func apply(root: Node) -> void:
	if not dark or root == null or not is_instance_valid(root):
		return
	_apply_node(root)
	for c in root.get_children():
		apply(c)


static func _apply_node(n: Node) -> void:
	if not (n is Control) or n.has_meta("vt"):
		return
	n.set_meta("vt", true)
	var c := n as Control
	if c.modulate != Color.WHITE and not (c is Container) and not (c is BaseButton):
		c.modulate = text_color(c.modulate)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_placeholder_color", "default_color"]:
		if c.has_theme_color_override(key):
			c.add_theme_color_override(key, text_color(c.get_theme_color(key)))
	for key in ["panel", "normal", "hover", "pressed", "disabled", "focus", "background", "fill", "read_only"]:
		if c.has_theme_stylebox_override(key):
			var sb := c.get_theme_stylebox(key)
			if sb is StyleBoxFlat:
				var d := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				d.bg_color = surface(d.bg_color)
				d.border_color = border(d.border_color)
				c.add_theme_stylebox_override(key, d)
	if c is ColorRect:
		(c as ColorRect).color = surface((c as ColorRect).color)
	elif c is ScrollContainer or c is BoxContainer:
		pass


## Helle Fläche -> dunkle Fläche. Getönte Hinweise behalten ihren Farbton.
static func surface(col: Color) -> Color:
	if col.a < 0.02:
		return col
	var l := col.get_luminance()
	if l < 0.70:
		return col
	var out := CARD
	if col.s > 0.055 and not (col.s < 0.10 and col.h > 0.54 and col.h < 0.70):
		out = Color.from_hsv(col.h, clampf(col.s * 4.0, 0.25, 0.55), 0.22)
	elif l >= 0.985:
		out = CARD
	elif l >= 0.935:
		out = Color(0.098, 0.116, 0.164)
	elif l >= 0.80:
		out = CONTROL
	else:
		out = Color(0.22, 0.255, 0.34)
	out.a = col.a
	return out


static func border(col: Color) -> Color:
	if col.a < 0.02:
		return col
	var l := col.get_luminance()
	if l < 0.60:
		return col
	var out := BORDER
	if col.s > 0.14:
		out = Color.from_hsv(col.h, clampf(col.s * 1.4, 0.3, 0.65), 0.48)
	out.a = col.a
	return out


## Dunkle Schrift -> helle Schrift. Farbige Schrift wird heller, Weiß bleibt weiß.
static func text_color(col: Color) -> Color:
	var l := col.get_luminance()
	if l >= 0.52:
		return col
	var out := TEXT
	if col.s >= 0.55 and col.v >= 0.30:
		out = Color.from_hsv(col.h, minf(col.s, 0.62), 0.96)
	elif l < 0.22:
		out = TEXT
	else:
		out = MUTED.lerp(TEXT, clampf((0.40 - l) / 0.30, 0.0, 1.0) * 0.5)
	out.a = col.a
	return out


static func flat(bg: Color, radius: int = 8, border_col: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border_col
		sb.set_border_width_all(border_w)
	return sb


static func pad(sb: StyleBoxFlat, x: float, y: float) -> StyleBoxFlat:
	sb.content_margin_left = x
	sb.content_margin_right = x
	sb.content_margin_top = y
	sb.content_margin_bottom = y
	return sb


static func label(text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.set_meta("vt", true)
	return l


static func icon(kind: String, px: float, col: Color) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_meta("kind", kind)
	ic.set_meta("vt", true)
	ic.modulate = col
	ic.draw.connect(func() -> void: UIStyle.draw_icon(ic, str(ic.get_meta("kind", "")), Rect2(Vector2.ZERO, ic.size), Color.WHITE))
	return ic


static func set_icon(ic: Control, kind: String) -> void:
	if ic != null and str(ic.get_meta("kind", "")) != kind:
		ic.set_meta("kind", kind)
		ic.queue_redraw()


## Flacher Knopf für Leisten und Menüs.
static func flat_button(btn: Button, bg: Color, hover: Color, txt: Color, radius: int = 7) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("vt", true)
	for st in [["normal", bg], ["hover", hover], ["pressed", hover.darkened(0.12)], ["disabled", Color(bg.r, bg.g, bg.b, bg.a * 0.5)]]:
		btn.add_theme_stylebox_override(str(st[0]), pad(flat(st[1], radius), 10.0, 4.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(k, txt)
