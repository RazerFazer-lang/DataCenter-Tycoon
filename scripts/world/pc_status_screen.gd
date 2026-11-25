class_name PcStatusScreen
extends Node
## Zweiter Monitor am Schreibtisch: zeigt immer live Strom, Temperatur, Einnahmen, Postfach,
## Marktanteile und Sperren, auch wenn niemand am PC sitzt. Ein Bild für beide Standorte.

const VIEW := Vector2i(896, 502)
const INTERVAL := 1.0
const NEAR := 14.0

## Shader-Material des alten Monitors, daran hängt "power_on".
var power_source: ShaderMaterial = null
## Plätze, an denen der Monitor steht. Ist keine Kamera in der Nähe, wird nicht gezeichnet.
var spots: Array[Node3D] = []

var _vp: SubViewport
var _screen: Control
var _mat: StandardMaterial3D
var _accum := INTERVAL
var _watts: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.draw.connect(_draw_screen)
	_vp.add_child(_screen)


func _ready() -> void:
	_rebind.call_deferred()


func _rebind() -> void:
	if _mat != null:
		_mat.emission_texture = _vp.get_texture()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func make_material() -> StandardMaterial3D:
	if _mat != null:
		return _mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.015, 0.015, 0.018)
	m.emission_enabled = true
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission = Color.WHITE
	m.emission_texture = _vp.get_texture()
	m.emission_energy_multiplier = 0.85
	m.roughness = 0.14
	m.metallic_specular = 0.6
	_mat = m
	return m


func _process(delta: float) -> void:
	_accum += delta
	if _accum < INTERVAL:
		return
	_accum = 0.0
	if GameState.is_active:
		_watts.append(float(GameState.total_watts))
		while _watts.size() > 90:
			_watts.remove_at(0)
	if not _is_near():
		return
	_screen.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _is_near() -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null or PcScreenState.local_fullscreen:
		return false
	for s in spots:
		if is_instance_valid(s) and s.global_position.distance_to(cam.global_position) < NEAR:
			return true
	return false


func _powered() -> bool:
	if power_source == null:
		return true
	var v: Variant = power_source.get_shader_parameter("power_on")
	return v == null or float(v) > 0.5


func _draw_screen() -> void:
	var c := _screen
	var f := ThemeDB.fallback_font
	var s := Vector2(VIEW)
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.008, 0.010, 0.014))
	if not _powered() or not GameState.is_active:
		return
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.040, 0.050, 0.080))
	# Kopf
	c.draw_rect(Rect2(0, 0, s.x, 52), Color(0.065, 0.080, 0.125))
	UIStyle.draw_icon(c, "verion", Rect2(18, 12, 28, 28), VerionTheme.ACCENT)
	c.draw_string(f, Vector2(58, 35), GameState.current_save_name, HORIZONTAL_ALIGNMENT_LEFT, 420, 22, VerionTheme.TEXT)
	c.draw_string(f, Vector2(s.x - 300, 35), "%s   %s" % [_s("Tag %d") % GameState.day_number, PcBootScreen.format_game_clock()], HORIZONTAL_ALIGNMENT_RIGHT, 282, 22, VerionTheme.MUTED)
	# Kacheln links
	var wp := clampf(float(GameState.total_watts) / maxf(1.0, float(GameState.max_watts)), 0.0, 1.0)
	_tile(c, f, Rect2(16, 66, 278, 118), "power", _s("Strom"), "%d W" % GameState.total_watts, _s("von %d W") % GameState.max_watts, wp, VerionTheme.BAD if wp > 0.9 or FinanceManager.is_power_blocked() else VerionTheme.WARN)
	var tp := clampf((GameState.room_temp - 18.0) / 60.0, 0.0, 1.0)
	_tile(c, f, Rect2(308, 66, 278, 118), "temp", _s("Raumtemperatur"), "%.1f °C" % GameState.room_temp, _s("%d Kühlgeräte") % GameState.coolers.size(), tp, VerionTheme.BAD if GameState.room_temp >= 60.0 else Color(0.20, 0.75, 0.85))
	var np := clampf(GameState.used_bandwidth_mbps / maxf(1.0, GameState.max_bandwidth_mbps), 0.0, 1.0)
	_tile(c, f, Rect2(600, 66, 280, 118), "net", _s("Internet"), HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps), _s("von %s") % HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps), np, VerionTheme.BAD if np >= 0.95 else VerionTheme.ACCENT)
	# Stromverlauf
	var pr := Rect2(16, 198, 570, 150)
	c.draw_style_box(VerionTheme.flat(Color(0.065, 0.080, 0.125), 10), pr)
	c.draw_string(f, pr.position + Vector2(14, 24), _s("Stromverlauf"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, VerionTheme.MUTED)
	if _watts.size() >= 2:
		var hi := maxf(100.0, float(GameState.max_watts))
		for v in _watts:
			hi = maxf(hi, v)
		var pts := PackedVector2Array()
		for i in _watts.size():
			pts.append(Vector2(pr.position.x + 14.0 + (pr.size.x - 28.0) * float(i) / float(_watts.size() - 1), pr.end.y - 14.0 - (pr.size.y - 56.0) * _watts[i] / hi))
		c.draw_polyline(pts, VerionTheme.WARN, 2.5, true)
	# Zahlen rechts
	var nr := Rect2(600, 198, 280, 150)
	c.draw_style_box(VerionTheme.flat(Color(0.065, 0.080, 0.125), 10), nr)
	var users := 0
	for rid in GameState.racks.keys():
		users += int((GameState.racks[rid] as Dictionary).get("active_users", 0)) if str((GameState.racks[rid] as Dictionary).get("rental_type", "none")) != "none" else 0
	var un := MailManager.get_unread_count()
	var rows := [
		[_s("Konto"), FinanceManager.format_money(GameState.money), VerionTheme.GOOD if GameState.money >= 0.0 else VerionTheme.BAD],
		[_s("Miete"), "+$%.0f / 5 s" % GameState.total_rental_income_per_cycle, VerionTheme.GOOD],
		[_s("Kunden"), str(users), VerionTheme.TEXT],
		[_s("Ungelesene E-Mails"), str(un), VerionTheme.ACCENT.lightened(0.25) if un > 0 else VerionTheme.TEXT],
		[_s("Offene Tickets"), str(GameState.get_open_ticket_count()), VerionTheme.BAD if GameState.get_open_ticket_count() > 0 else VerionTheme.TEXT],
	]
	var y := nr.position.y + 30.0
	for r in rows:
		c.draw_string(f, Vector2(nr.position.x + 14, y), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, 170, 17, VerionTheme.MUTED)
		c.draw_string(f, Vector2(nr.position.x + 120, y), str(r[1]), HORIZONTAL_ALIGNMENT_RIGHT, 146, 18, r[2])
		y += 27.0
	# Markt
	var mr := Rect2(16, 362, 864, 124)
	c.draw_style_box(VerionTheme.flat(Color(0.065, 0.080, 0.125), 10), mr)
	var sh: Dictionary = MarketManager.get_total_shares()
	c.draw_string(f, mr.position + Vector2(14, 26), _s("Marktanteile"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, VerionTheme.MUTED)
	c.draw_string(f, mr.position + Vector2(mr.size.x - 250, 28), _s("Du: %.1f %%") % (float(sh["you"]) * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 236, 19, MarketApp.COL_YOU.lightened(0.2))
	var bx := mr.position.x + 14.0
	var bw := mr.size.x - 28.0
	var x := bx
	var parts: Array = [["you", MarketApp.COL_YOU]]
	for rid2 in MarketManager.RIVAL_ORDER:
		parts.append([rid2, MarketApp.rival_color(rid2)])
	for p in parts:
		var pw := bw * float(sh.get(p[0], 0.0))
		c.draw_rect(Rect2(x, mr.position.y + 40, maxf(0.0, pw - 1.0), 22), p[1])
		x += pw
	c.draw_rect(Rect2(x, mr.position.y + 40, maxf(0.0, bx + bw - x), 22), Color(1, 1, 1, 0.10))
	var blocked := FinanceManager.get_blocked_kinds()
	var line := ""
	var line_col := VerionTheme.MUTED
	if not blocked.is_empty():
		var names: Array = []
		for b in blocked:
			names.append(_s(str(FinanceManager.BILL_KINDS[b]["title"])))
		line = _s("GESPERRT: %s") % ", ".join(names)
		line_col = VerionTheme.BAD
	elif not MarketManager.poach.is_empty():
		line = _s("%s will %s abwerben!") % [MarketManager.rival_name(str(MarketManager.poach["rival"])), str(MarketManager.poach["customer"])]
		line_col = VerionTheme.WARN
	elif not MarketManager.news.is_empty():
		var n: Dictionary = MarketManager.news[0]
		line = GameState.format_message(str(n["text"]), n.get("args", []))
	else:
		line = _s("Offene Rechnungen: %s") % FinanceManager.format_money(FinanceManager.get_open_bills_total())
	c.draw_string(f, Vector2(bx, mr.position.y + 98), line, HORIZONTAL_ALIGNMENT_LEFT, bw, 17, line_col)


func _tile(c: Control, f: Font, r: Rect2, icon: String, name: String, val: String, sub: String, p: float, col: Color) -> void:
	c.draw_style_box(VerionTheme.flat(Color(0.065, 0.080, 0.125), 10), r)
	UIStyle.draw_icon(c, icon, Rect2(r.position + Vector2(14, 13), Vector2(18, 18)), col)
	c.draw_string(f, r.position + Vector2(40, 28), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 54, 15, VerionTheme.MUTED)
	c.draw_string(f, r.position + Vector2(14, 70), val, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28, 32, VerionTheme.TEXT)
	c.draw_string(f, r.position + Vector2(14, 70), sub, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28, 14, VerionTheme.MUTED)
	var b := Rect2(r.position + Vector2(14, 90), Vector2(r.size.x - 28, 10))
	c.draw_style_box(VerionTheme.flat(Color(1, 1, 1, 0.09), 5), b)
	if p > 0.01:
		c.draw_style_box(VerionTheme.flat(col, 5), Rect2(b.position, Vector2(maxf(10.0, b.size.x * p), b.size.y)))


func _s(t: String) -> String:
	return String(TranslationServer.translate(t))
