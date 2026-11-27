class_name SignaturePad
extends Control
## Feld für eine handschriftliche Unterschrift mit der Maus. Die Strichstärke folgt dem Tempo wie bei einem
## Kugelschreiber: langsam dick, schnell dünn. Beim Schreiben kratzt der Stift hörbar über das Papier,
## je schneller, desto lauter. Mit readonly zeigt es nur fertige Striche (z. B. den Fahrer).

signal changed

const INK := Color(0.07, 0.12, 0.36, 0.96)
const LINE := Color(0.20, 0.22, 0.26, 0.55)
const W_MAX := 3.4
const W_MIN := 1.15

var readonly := false
var hint := ""
## Je Strich die Punkte in Pixeln und die Breite an jedem Punkt.
var _strokes: Array[PackedVector2Array] = []
var _widths: Array[PackedFloat32Array] = []
var _drawing := false
var _last_t := 0
## Fertige Striche (0..1), die bei jeder Größenänderung neu auf das Feld gelegt werden.
var _source: Array = []
# Schreibgeräusch: gefiltertes Rauschen, Lautstärke folgt dem Tempo.
const MIX := 22050.0
var _audio: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _amp := 0.0
var _amp_target := 0.0
var _last_move := 0
var _tick := 0.0
var _w_prev := 0.0
var _hp := 0.0
var _lp := 0.0
var _body := 0.0
var _grain := 1.0
var _grain_n := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	resized.connect(func() -> void:
		if not _source.is_empty():
			_rebuild()
		queue_redraw()
	)
	if not readonly:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = MIX
		gen.buffer_length = 0.08
		_audio = AudioStreamPlayer.new()
		_audio.stream = gen
		_audio.volume_db = -4.0
		add_child(_audio)
		visibility_changed.connect(_sync_audio)
		_sync_audio.call_deferred()


func is_drawing() -> bool:
	return _drawing


func _sync_audio() -> void:
	if _audio == null or not is_inside_tree():
		return
	if is_visible_in_tree() and not _audio.playing:
		_audio.play()
		_pb = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	elif not is_visible_in_tree() and _audio.playing:
		_audio.stop()
		_pb = null


func _process(_delta: float) -> void:
	if _pb == null:
		return
	if not _drawing or Time.get_ticks_msec() - _last_move > 45:
		_amp_target = 0.0
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	var gain := SettingsManager.get_effective_sfx_gain()
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_amp += (_amp_target - _amp) * (0.012 if _amp_target > _amp else 0.0035)
		if _amp < 0.0004 and _tick < 0.0004:
			continue
		var w := randf_range(-1.0, 1.0)
		# Hochpass gegen Rumpeln, Tiefpass gegen Zischen: übrig bleibt das Kratzen der Kugel.
		_hp = 0.86 * (_hp + w - _w_prev)
		_w_prev = w
		_lp += 0.5 * (_hp - _lp)
		# Das Brett darunter klingt dumpf mit.
		_body += 0.03 * (w - _body)
		_grain_n -= 1
		if _grain_n <= 0:
			_grain = randf_range(0.5, 1.0)
			_grain_n = randi_range(40, 160)
		var v := (_lp * 0.50 * _grain + _body * 0.85) * _amp
		if _tick > 0.0004:
			v += (w * 0.35 + _body * 3.2) * _tick
			_tick *= 0.982
		buf[i] = Vector2(v, v) * gain
	_pb.push_buffer(buf)


func clear() -> void:
	_source = []
	_strokes.clear()
	_widths.clear()
	_drawing = false
	queue_redraw()
	changed.emit()


func is_empty() -> bool:
	return _strokes.is_empty()


## Tinte in Feldbreiten (wie DeliveryNote.ink).
func ink() -> float:
	return DeliveryNote.ink(strokes_normalized())


## Striche mit Koordinaten von 0 bis 1, so geht die Unterschrift an den Host.
func strokes_normalized() -> Array:
	var out: Array = []
	var sz := size.max(Vector2(1, 1))
	for s in _strokes:
		if s.size() < 2:
			continue
		var n := PackedVector2Array()
		var step := maxi(1, ceili(float(s.size()) / 120.0))
		for i in range(0, s.size(), step):
			n.append(Vector2(clampf(s[i].x / sz.x, 0.0, 1.0), clampf(s[i].y / sz.y, 0.0, 1.0)))
		if (s.size() - 1) % step != 0:
			n.append(Vector2(clampf(s[s.size() - 1].x / sz.x, 0.0, 1.0), clampf(s[s.size() - 1].y / sz.y, 0.0, 1.0)))
		out.append(n)
	return out


## Fertige Striche (0..1) anzeigen. Die Breite wird aus dem Punktabstand geschätzt.
func set_strokes(norm: Array) -> void:
	_source = norm.duplicate()
	_rebuild()


func _rebuild() -> void:
	var norm := _source
	_strokes.clear()
	_widths.clear()
	var sz := size.max(Vector2(1, 1))
	for s in norm:
		var pts := PackedVector2Array()
		var ws := PackedFloat32Array()
		var w := W_MAX * 0.8
		var prev := Vector2.INF
		for p in (s as PackedVector2Array):
			var q := Vector2(p.x * sz.x, p.y * sz.y)
			if prev != Vector2.INF:
				w = lerpf(w, clampf(W_MAX - q.distance_to(prev) * 0.09, W_MIN, W_MAX), 0.4)
			pts.append(q)
			ws.append(w)
			prev = q
		_strokes.append(pts)
		_widths.append(ws)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if readonly:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_drawing = true
			_last_t = Time.get_ticks_msec()
			_tick = 0.9
			_strokes.append(PackedVector2Array([mb.position]))
			_widths.append(PackedFloat32Array([W_MAX * 0.7]))
			if _strokes.size() > DeliveryNote.MAX_STROKES:
				_strokes.pop_front()
				_widths.pop_front()
		else:
			_drawing = false
			changed.emit()
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _drawing:
		var mm := event as InputEventMouseMotion
		var s := _strokes[_strokes.size() - 1]
		var w := _widths[_widths.size() - 1]
		var last := s[s.size() - 1]
		# Etwas glätten, damit der Strich nicht zittert.
		var p := last.lerp(mm.position.clamp(Vector2.ZERO, size), 0.65)
		var dist := p.distance_to(last)
		if dist < 1.2:
			return
		var now := Time.get_ticks_msec()
		var speed := dist / maxf(1.0, float(now - _last_t))
		_last_t = now
		var target := clampf(W_MAX - speed * 1.35, W_MIN, W_MAX)
		_amp_target = clampf(pow(speed / 1.3, 0.7), 0.15, 1.0)
		_last_move = now
		s.append(p)
		w.append(lerpf(w[w.size() - 1], target, 0.35))
		_strokes[_strokes.size() - 1] = s
		_widths[_widths.size() - 1] = w
		accept_event()
		queue_redraw()
		changed.emit()


func _draw() -> void:
	if not readonly:
		# Linie mit Kreuz wie auf einem Formular.
		var y := size.y * 0.80
		var x := 10.0
		while x < size.x - 8.0:
			draw_line(Vector2(x, y), Vector2(minf(x + 7.0, size.x - 8.0), y), LINE, 1.2, true)
			x += 11.0
		draw_line(Vector2(8, y - 16), Vector2(20, y - 4), LINE, 1.6, true)
		draw_line(Vector2(20, y - 16), Vector2(8, y - 4), LINE, 1.6, true)
		if _strokes.is_empty() and hint != "":
			var f := get_theme_default_font()
			draw_string(f, Vector2(30, y - 8), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 40, 13, Color(0.35, 0.38, 0.45, 0.55))
	for k in _strokes.size():
		var s := _strokes[k]
		var w := _widths[k]
		if s.size() == 1:
			draw_circle(s[0], w[0] * 0.5, INK, true, -1.0, true)
			continue
		# Catmull-Rom zwischen den Punkten: runde Bögen statt Ecken.
		var prev := s[0]
		var prev_w := w[0]
		for i in range(1, s.size()):
			var p0 := s[maxi(i - 2, 0)]
			var p1 := s[i - 1]
			var p2 := s[i]
			var p3 := s[mini(i + 1, s.size() - 1)]
			var sub := clampi(int(p1.distance_to(p2) / 3.0), 1, 8)
			for j in range(1, sub + 1):
				var t := float(j) / float(sub)
				var q := _catmull(p0, p1, p2, p3, t)
				var wq := lerpf(w[i - 1], w[i], t)
				var wi := (prev_w + wq) * 0.5
				draw_line(prev, q, INK, wi, true)
				draw_circle(q, wi * 0.5, INK, true, -1.0, true)
				prev = q
				prev_w = wq


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
