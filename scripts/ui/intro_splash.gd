class_name IntroSplash
extends Control
## Ruhiges, erwachsenes, 100 % KI-freies Studio- & Titel-Intro für Vexom Studio / DataCenter Together.
## Übernimmt nahtlos aus dem Boot-Splash (#0B0D10):
##   Phase 1 (0.0 – 3.5 s): Messerscharfes Vektor-Logo "VEXOM STUDIO" auf Mattschwarz + Power-On-Sound
##   Phase 2 (3.5 – 6.4 s): Echtes Blender-3D-Studio-Key-Art unserer Spiel-Racks + "DATACENTER TOGETHER"
## Jederzeit per Leertaste, Enter, ESC oder Mausklick sauber überspringbar.

signal intro_fading_out
signal intro_finished

const BG_COLOR := Color(0.0431, 0.0510, 0.0627, 1.0) # Exakt identisch mit boot_splash/bg_color (#0B0D10)
const EMBLEM_PATH := "res://assets/branding/vexom_emblem.png"
const KEYART_PATH := "res://assets/branding/title_keyart.png"

const PHASE_STUDIO_END := 3.5
const PHASE_TOTAL := 6.4

var _active: bool = false
var _finishing: bool = false
var _elapsed: float = 0.0
var _phase2_triggered: bool = false

var _bg_tex: TextureRect
var _vignette: Control
var _letterbox: IntroLetterbox

var _studio_box: Control
var _emblem_rect: TextureRect
var _studio_line: ColorRect
var _studio_name_lbl: Label
var _studio_sub_lbl: Label

var _title_box: Control
var _title_eyebrow: Label
var _title_main: Label
var _title_badge_box: Control
var _title_tagline: Label

var _skip_lbl: Label
var _fade_tween: Tween


## Dezente Kino-Letterbox-Balken oben & unten — kein Neon-Kitsch, keine Partikel.
class IntroLetterbox extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		if s.x < 10.0 or s.y < 10.0:
			return
		var bar_h := maxf(24.0, s.y * 0.052)
		draw_rect(Rect2(0.0, 0.0, s.x, bar_h), Color(0.020, 0.024, 0.030, 0.94))
		draw_rect(Rect2(0.0, s.y - bar_h, s.x, bar_h), Color(0.020, 0.024, 0.030, 0.94))
		draw_line(Vector2(0.0, bar_h), Vector2(s.x, bar_h), Color(1.0, 1.0, 1.0, 0.07), 1.0)
		draw_line(Vector2(0.0, s.y - bar_h), Vector2(s.x, s.y - bar_h), Color(1.0, 1.0, 1.0, 0.07), 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


func start_intro() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_active = true
	_finishing = false
	_elapsed = 0.0
	_phase2_triggered = false
	modulate.a = 1.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	_studio_box.visible = true
	_studio_box.modulate.a = 1.0 # Nahtlos aus boot_splash.png!
	_emblem_rect.scale = Vector2(1.0, 1.0)
	_studio_line.custom_minimum_size.x = 0.0
	_studio_sub_lbl.modulate.a = 0.0

	_title_box.visible = false
	_title_box.modulate.a = 0.0
	_skip_lbl.modulate.a = 0.0

	if _bg_tex != null:
		_bg_tex.modulate.a = 0.0
		_bg_tex.scale = Vector2(1.02, 1.02)

	SfxManager.play("intro_studio_swell", -3.0, 1.0)


func _input(event: InputEvent) -> void:
	if not _active or _finishing or _elapsed < 0.40:
		return
	var skip := false
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_ESCAPE:
			skip = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish_intro(0.32)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta

	if not _finishing:
		_skip_lbl.modulate.a = clampf((_elapsed - 0.7) / 0.6, 0.0, 0.55)

	if _elapsed < PHASE_STUDIO_END:
		# --- PHASE 1: VEXOM STUDIO (ruhig, klar, selbstbewusst) ---
		var p := _elapsed
		var fade_out := _smoothstep(clampf((PHASE_STUDIO_END - p) / 0.55, 0.0, 1.0))
		_studio_box.modulate.a = fade_out

		_emblem_rect.pivot_offset = _emblem_rect.size * 0.5
		var s := lerpf(0.98, 1.03, _smoothstep(clampf(p / PHASE_STUDIO_END, 0.0, 1.0)))
		_emblem_rect.scale = Vector2(s, s)

		var line_t := _smoothstep(clampf((p - 0.30) / 0.75, 0.0, 1.0))
		_studio_line.custom_minimum_size.x = 180.0 * line_t

		_studio_sub_lbl.modulate.a = _smoothstep(clampf((p - 0.75) / 0.50, 0.0, 1.0))
	else:
		# --- PHASE 2: ECHTES 3D-STUDIO-KEY-ART + DATACENTER TOGETHER ---
		if not _phase2_triggered:
			_phase2_triggered = true
			_studio_box.visible = false
			_title_box.visible = true
			SfxManager.play("intro_title_hit", -2.5, 1.0)

		var p2 := _elapsed - PHASE_STUDIO_END
		var dur2 := PHASE_TOTAL - PHASE_STUDIO_END
		var fade_in := _smoothstep(clampf(p2 / 0.70, 0.0, 1.0))
		_title_box.modulate.a = fade_in

		if _bg_tex != null:
			_bg_tex.modulate.a = fade_in * 0.85
			_bg_tex.pivot_offset = _bg_tex.size * 0.5
			var zoom := lerpf(1.02, 1.08, _smoothstep(clampf(p2 / dur2, 0.0, 1.0)))
			_bg_tex.scale = Vector2(zoom, zoom)

		_title_eyebrow.modulate.a = _smoothstep(clampf((p2 - 0.10) / 0.45, 0.0, 1.0))
		_title_badge_box.modulate.a = _smoothstep(clampf((p2 - 0.30) / 0.45, 0.0, 1.0))
		_title_tagline.modulate.a = _smoothstep(clampf((p2 - 0.55) / 0.50, 0.0, 1.0))

		if p2 >= dur2 and not _finishing:
			_finish_intro(0.55)


func _finish_intro(fade_sec: float) -> void:
	if _finishing:
		return
	_finishing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_fading_out.emit()
	_fade_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_sec)
	_fade_tween.tween_callback(func() -> void:
		_active = false
		visible = false
		modulate.a = 1.0
		intro_finished.emit()
	)


func _smoothstep(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _build_ui() -> void:
	var display_font := UIStyle.make_display_font(get_theme_default_font(), 0.55, 3)
	var wide_font := UIStyle.make_display_font(get_theme_default_font(), 0.40, 7)

	# 1. Reines Mattschwarz (#0B0D10 — 100 % identisch zum Boot-Splash)
	var bg_rect := ColorRect.new()
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.color = BG_COLOR
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	# 2. Echtes Blender-3D-Studio-Key-Art unserer eigenen Spiel-Racks (Phase 2)
	if ResourceLoader.exists(KEYART_PATH):
		var ktex := load(KEYART_PATH) as Texture2D
		if ktex != null:
			_bg_tex = TextureRect.new()
			_bg_tex.texture = ktex
			_bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_bg_tex.modulate = Color(1.0, 1.0, 1.0, 0.0)
			_bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_bg_tex)

	# Ruhige dunkle Vignette für perfekte Lesbarkeit der Typografie
	_vignette = UIStyle.make_gradient_rect(
		PackedColorArray([Color(0.03, 0.035, 0.045, 0.45), Color(0.02, 0.025, 0.032, 0.88)]),
		PackedFloat32Array([0.28, 1.0]),
		Vector2(0.5, 0.5), Vector2(1.05, 0.5), true
	)
	add_child(_vignette)

	# 3. Dezente Kino-Letterbox-Balken
	_letterbox = IntroLetterbox.new()
	_letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_letterbox)

	# 4. PHASE 1: VEXOM STUDIO VEKTOR-STUDIO-REVEAL
	var studio_center := CenterContainer.new()
	studio_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(studio_center)

	_studio_box = VBoxContainer.new()
	_studio_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_studio_box.add_theme_constant_override("separation", 16)
	_studio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	studio_center.add_child(_studio_box)

	_emblem_rect = TextureRect.new()
	_emblem_rect.custom_minimum_size = Vector2(152, 152)
	_emblem_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_emblem_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(EMBLEM_PATH):
		_emblem_rect.texture = load(EMBLEM_PATH) as Texture2D
	_studio_box.add_child(_emblem_rect)

	_studio_name_lbl = Label.new()
	_studio_name_lbl.text = "VEXOM  STUDIO"
	_studio_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_label(_studio_name_lbl, 28, Color(0.94, 0.95, 0.97), wide_font, true)
	_studio_box.add_child(_studio_name_lbl)

	var line_wrap := CenterContainer.new()
	line_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_studio_box.add_child(line_wrap)
	_studio_line = ColorRect.new()
	_studio_line.custom_minimum_size = Vector2(0, 1)
	_studio_line.color = Color(0.93, 0.66, 0.16, 0.85)
	_studio_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_wrap.add_child(_studio_line)

	_studio_sub_lbl = Label.new()
	_studio_sub_lbl.text = "P R E S E N T S"
	_studio_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_label(_studio_sub_lbl, 11, Color(0.68, 0.72, 0.78), display_font)
	_studio_box.add_child(_studio_sub_lbl)

	# 5. PHASE 2: DATACENTER TOGETHER TITLE LOCKUP
	var title_center := CenterContainer.new()
	title_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_center)

	_title_box = VBoxContainer.new()
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 12)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.add_child(_title_box)

	_title_eyebrow = Label.new()
	_title_eyebrow.text = "VEXOM STUDIO"
	_title_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_label(_title_eyebrow, 12, Color(0.93, 0.66, 0.16, 0.92), wide_font)
	_title_box.add_child(_title_eyebrow)

	_title_main = Label.new()
	_title_main.text = "DATACENTER TOGETHER"
	_title_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_label(_title_main, 52, Color(0.97, 0.98, 1.0), display_font, true)
	_title_box.add_child(_title_main)

	var badge_center := CenterContainer.new()
	badge_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(badge_center)
	_title_badge_box = PanelContainer.new()
	_title_badge_box.add_theme_stylebox_override("panel", UIStyle.make_panel(
		Color(0.06, 0.07, 0.09, 0.86),
		Color(0.93, 0.66, 0.16, 0.85),
		3, 1, 18, 5
	))
	badge_center.add_child(_title_badge_box)

	var badge_lbl := Label.new()
	badge_lbl.text = "CO-OP EDITION  •  v%s" % UIStyle.game_version()
	UIStyle.style_label(badge_lbl, 13, Color(0.94, 0.95, 0.97), display_font)
	_title_badge_box.add_child(badge_lbl)

	_title_tagline = Label.new()
	_title_tagline.text = "BUILD   •   WIRE   •   COOL   •   SCALE"
	_title_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.style_label(_title_tagline, 12, Color(0.74, 0.78, 0.84, 0.85), display_font)
	_title_box.add_child(_title_tagline)

	# 6. Überspringen-Hinweis unten rechts
	var skip_margin := MarginContainer.new()
	skip_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_margin.offset_left = -320
	skip_margin.offset_top = -50
	skip_margin.add_theme_constant_override("margin_right", 36)
	skip_margin.add_theme_constant_override("margin_bottom", 13)
	skip_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skip_margin)

	_skip_lbl = Label.new()
	_skip_lbl.text = tr("[LEERTASTE / KLICK] Überspringen")
	_skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_label(_skip_lbl, 11, Color(0.68, 0.72, 0.78))
	skip_margin.add_child(_skip_lbl)
