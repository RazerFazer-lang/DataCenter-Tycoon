extends CanvasLayer
## Leistungsanzeige (Standardtaste F3, Aktion "toggle_perf"): FPS, Frametime, Ping, Draw Calls.

const ACTION := "toggle_perf"
## Abstand zwischen zwei Aktualisierungen der Anzeige in Sekunden.
const UPDATE_INTERVAL := 0.25

var _panel: PanelContainer
var _label: Label
var _accum: float = 0.0
var _frames: int = 0
var _worst_ms: float = 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.055, 0.06, 0.78)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(_label, 13, UIStyle.COL_TEXT_MAIN)
	_panel.add_child(_label)

	visible = false
	set_process(false)


func _input(event: InputEvent) -> void:
	if not InputMap.has_action(ACTION) or not event.is_action_pressed(ACTION):
		return
	get_viewport().set_input_as_handled()
	visible = not visible
	_reset_counters()
	set_process(visible)
	if visible:
		_label.text = "Messe..."


func _reset_counters() -> void:
	_accum = 0.0
	_frames = 0
	_worst_ms = 0.0


func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if _accum < UPDATE_INTERVAL or _frames == 0:
		return
	var fps := float(_frames) / _accum
	var avg_ms := _accum * 1000.0 / float(_frames)
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_label.text = "FPS: %d\nFrametime: %.1f ms (max %.1f ms)\nPing: %s\nDraw Calls: %d" % [
		roundi(fps), avg_ms, _worst_ms, _ping_text(), draw_calls,
	]
	_reset_counters()


func _ping_text() -> String:
	if not NetworkManager.is_in_session or multiplayer.multiplayer_peer == null:
		return "–"
	if multiplayer.is_server():
		return "Host"
	var ms := int(NetworkManager.player_pings.get(multiplayer.get_unique_id(), -1))
	if ms < 0:
		return tr("wird gemessen...")
	return "%d ms" % ms