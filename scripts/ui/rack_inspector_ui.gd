class_name RackInspectorUI
extends Control
## v2.0 Rack-, Router- und Geräte-Menü (komplettes Redesign, gleiche Spielfunktionen wie v1.2).
## Rack-Ansicht: oben Live-Kennzahlen mit Ringanzeigen, links der Rack-Schrank mit allen Einschüben,
## in der Mitte der gewählte Einschub (Mainboard-Auswahl oder Komponenten mit Teileliste),
## rechts die drehbare 3D-Vorschau. Zweiter Reiter: Vermietung & Auslastung.
## Bedienung: [E] am Rack öffnet das Menü, darin wird alles mit der Maus angeklickt
## (siehe MOUSE_CLICKS_ENABLED). [ESC] schließt.

signal close_requested
signal relocate_rack_requested(rack_id: String)
signal cable_pull_requested(cable_type: String, entity_id: String)

## true = Schaltflächen im Menü werden mit der Maus angeklickt; [E] löst im Menü nichts aus.
const MOUSE_CLICKS_ENABLED := true
const CARD_MAX_SIZE := Vector2(1440, 1000)
const CARD_MIN_SIZE := Vector2(940, 580)
const SCREEN_MARGIN := 24.0
const RACK_COL_W := 268.0
const SIDE_COL_W := 300.0
const PREVIEW_H := 240.0
## Kameraposition der 3D-Vorschau bei Zoom 1.0. Die Kamera zielt ungefähr auf den Ursprung,
## deshalb zoomt das Skalieren dieser Position zur Modellmitte hin.
const PREVIEW_CAM_POS := Vector3(0.0, 0.64, 0.92)
const PREVIEW_ZOOM_MIN := 0.45
const PREVIEW_ZOOM_MAX := 1.6
const PREVIEW_ZOOM_STEP := 0.9
const SLOT_ROW_H := 58.0
const TILE_H := 58.0
## Mausrad in Listen: Pixel pro Raste und wie schnell die Liste zum Ziel gleitet.
const WHEEL_STEP := 96.0
const SMOOTH_SCROLL_SPEED := 16.0
## Höhe einer Mainboard-Zeile: klein genug, dass bei 1280×720 etwa 6 Boards sichtbar sind.
const MB_ROW_H := 50.0
const LOAD_WARN_PCT := 72.0
const LOAD_CRIT_PCT := 90.0
const TEMP_CRIT := 70.0
const TEMP_WARN_SPAN := 12.0
const TEMP_GAUGE_MAX := 90.0
const SAT_WARN := 75.0
const RING_PX := 40
const RING_ANIM_TIME := 0.7
const COL_SELECT := Color(0.86, 0.58, 0.16, 0.20)
const COL_RACK_FRAME := Color(0.050, 0.053, 0.059, 0.98)
const COL_SLOT_BG := Color(0.092, 0.097, 0.105, 0.98)
const COL_LED_OFF := Color(0.30, 0.31, 0.33)
const COL_LED_DARK := Color(0.42, 0.42, 0.44)

var _mode: String = "rack" # "rack" | "router" | "cooler" | "ups" | "cart"
var _entity_id: String = ""
var _selected_slot: int = 0
var _active_tab: String = "hardware" # "hardware" | "rental"
var _selected_cat: String = "cpu"
var _selected_filter: String = "Alle"
var _only_in_stock: bool = false
var _confirm_sell_entity: bool = false
var _confirm_sell_module: bool = false
# Freier Einschub: false = Übersicht mit "Mainboard auswählen", true = Mainboard-Liste.
var _mb_picker_open: bool = false
# Gewählte Mainboard-Kategorie ("" = alle).
var _mb_cat: String = ""
# Ansicht, zu der die gemerkte Scroll-Position gehört (siehe _scroll_view_key).
var _scroll_key: String = ""

var _card: PanelContainer
var _title_lbl: Label
var _subtitle_lbl: Label
var _rename_edit: LineEdit
var _rename_cancelled := false
var _status_panel: PanelContainer
var _status_lbl: Label
var _kpi_row: HBoxContainer
var _tab_row: HBoxContainer
var _body_host: VBoxContainer
var _footer_actions: HBoxContainer
var _display_font: FontVariation

# Bedienung: alle Schaltflächen des aktuellen Aufbaus, Fokus-Schlüssel und Eingabemodus.
var _buttons: Array = []
var _focus_key: String = ""
var _pointer_mode: bool = false
var _animate_next: bool = false
var _pulse_nodes: Array = []
var _pulse_t: float = 0.0
var _parts_scroll: ScrollContainer
var _parts_scroll_v: int = 0
var _smooth_target: float = 0.0
var _smooth_pos: float = 0.0
var _smooth_written: int = 0
var _smooth_active: bool = false
var _rental_scroll: ScrollContainer
var _rental_scroll_v: float = 0.0
var _mb_money_label: Label
var _mb_afford_sig: int = -1
const LIVE_REFRESH_MS := 1000
var _last_live_refresh_ms: int = 0
var _live_sig: String = ""

# Drehbare 3D-Vorschau (wird bei jedem Aufbau in die rechte Spalte gehängt)
var _preview_frame: PanelContainer
var _preview_vp: SubViewport
var _preview_pivot: Node3D
var _preview_model_holder: Node3D
var _preview_fans: Array = []
var _preview_fx: PartFx
var _preview_sig: String = ""
var _preview_dragging: bool = false
var _preview_yaw: float = 0.45
var _preview_pitch: float = -0.05
var _preview_cam: Camera3D
var _preview_overlay: Control
## Kleiner als 1.0 = näher dran.
var _preview_zoom: float = 1.0
## Im Vollbild hängt _preview_frame in _preview_fs_host. In der Seitenspalte hält
## _preview_placeholder den Platz frei, damit die Vorschau beim Beenden dorthin zurückkann.
var _preview_fullscreen := false
var _preview_fs_host: PanelContainer
var _preview_fs_btn: Button
var _preview_placeholder: Control
# Fehlersuche: Bauteile im Modell tragen die Meta "part_cat" (siehe HardwareMeshFactory).
var _preview_part_nodes: Array = []
var _preview_faulty_cat: String = ""
var _preview_fault_mat: StandardMaterial3D
var _preview_hover_lbl: Label
var _tri_mesh_cache: Dictionary = {} # Mesh -> TriangleMesh fuer pixelgenaues Hover-Picking
## Verhindert, dass jede Mausbewegung über dem defekten Teil eine neue Diagnose-RPC schickt.
var _diag_requested_key: String = ""
## Mausweg in Pixeln seit dem Drücken in der 3D-Vorschau. Bis PREVIEW_CLICK_SLOP gilt es als Klick, sonst als Drehen.
var _preview_click_travel: float = 0.0
const PREVIEW_CLICK_SLOP := 6.0
## Server-Konfigurator für freie Slots (-> Warenkorb -> Lieferung -> Werkbank).
var _cfg_open: bool = false
var _cfg_mb: String = ""
var _cfg_comps: Dictionary = {}
var _cfg_toast: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	# Sync-Signale kommen jeden Tick. Sie laufen gebündelt über _queue_refresh, statt das Menü
	# jedes Mal komplett neu aufzubauen (das ließ es zittern und Klicks ins Leere gehen).
	GameState.racks_changed.connect(_queue_refresh)
	GameState.coolers_changed.connect(_queue_refresh)
	GameState.ups_changed.connect(_queue_refresh)
	GameState.carts_changed.connect(_queue_refresh)
	GameState.inventory_changed.connect(_queue_refresh)
	GameState.panel_states_changed.connect(_queue_refresh)
	GameState.cart_changed.connect(_queue_refresh)
	GameState.state_updated.connect(_on_state_updated)
	get_viewport().size_changed.connect(_on_viewport_resized)


## Rack-Felder, die sich jeden Tick ändern. Sie laufen über den gedrosselten Live-Pfad (_live_signature).
const VOLATILE_RACK_KEYS: Array[String] = [
	"temp", "metrics", "active_users", "satisfaction", "services", "grace_timer", "rental_income",
]

var _refresh_queued := false
var _struct_sig := ""


## Fasst mehrere Signale aus demselben Frame zu einer Prüfung zusammen.
func _queue_refresh() -> void:
	if not visible or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	_refresh_queued = false
	if not visible:
		return
	if _struct_signature() != _struct_sig:
		_refresh()
		return
	# Nur Live-Werte geändert: gedrosselt über den Live-Pfad aktualisieren.
	_on_state_updated()


## Struktur des geöffneten Geräts (Bauteile, Dienste, Strom/Netz, Lager). Ändert sie sich, wird sofort neu gebaut.
## Außerhalb der Rack-Ansicht bleibt das alte Verhalten (immer neu bauen).
func _struct_signature() -> String:
	if _mode != "rack":
		return "%s|%d" % [_mode, Time.get_ticks_usec()]
	if not GameState.racks.has(_entity_id):
		return "missing"
	var r: Dictionary = GameState.racks[_entity_id]
	var parts := PackedStringArray([_entity_id, str(GameState.get_total_inventory_parts())])
	for k in r.keys():
		if VOLATILE_RACK_KEYS.has(str(k)):
			continue
		parts.append("%s=%s" % [str(k), _coarse_str(r[k])])
	for s in r.get("services", []):
		if s is Dictionary:
			var sd: Dictionary = s
			parts.append("svc=%s/%s" % [str(sd.get("type", "")), str(sd.get("customer", ""))])
	return "|".join(parts)


## Wandelt Werte grob gerundet in Text um, damit winzige Float-Schwankungen keinen Neuaufbau auslösen.
func _coarse_str(v: Variant) -> String:
	if v is float:
		return str(roundi(float(v) * 20.0))
	if v is Dictionary:
		var d: Dictionary = v
		var out := PackedStringArray()
		for k in d.keys():
			if str(k) == "boot_left" or str(k) == "boot_wait":
				continue
			out.append("%s:%s" % [str(k), _coarse_str(d[k])])
		return "{" + ",".join(out) + "}"
	if v is Array:
		var a: Array = v
		var out_a := PackedStringArray()
		for e in a:
			out_a.append(_coarse_str(e))
		return "[" + ",".join(out_a) + "]"
	return str(v)


## Spiel-Tick: Bei offener Mainboard-Liste wird nur das Guthaben aktualisiert. Neu gebaut wird nur,
## wenn sich ändert, wie viele Boards bezahlbar sind. Der Neuaufbau bei jedem Tick ließ das Scrollen ruckeln.
func _on_state_updated() -> void:
	if not visible:
		return
	if _mb_picker_open and _mode == "rack" and is_instance_valid(_parts_scroll):
		if is_instance_valid(_mb_money_label):
			_mb_money_label.text = "$%.0f" % GameState.money
		# Offene Mainboard-Liste: nur neu aufbauen, wenn sich die Zahl bezahlbarer Boards ändert.
		if _mb_affordable_count() != _mb_afford_sig:
			_refresh()
		return
	# Live-Werte: nur neu aufbauen, wenn sich etwas Sichtbares geändert hat, und höchstens 1x pro Sekunde.
	# Der Neuaufbau bei jedem Tick ließ das Menü zittern und Klicks ins Leere gehen.
	var sig := _live_signature()
	if sig == _live_sig:
		return
	var now := Time.get_ticks_msec()
	if now - _last_live_refresh_ms < LIVE_REFRESH_MS:
		return
	_last_live_refresh_ms = now
	_live_sig = sig
	_refresh()


## Gerundete Kennwerte, die das Rack-Menü anzeigt. Kleine Schwankungen lösen keinen Neuaufbau aus.
func _live_signature() -> String:
	if _mode != "rack" or not GameState.racks.has(_entity_id):
		return str(floori(Time.get_ticks_msec() / 2000.0))
	var r: Dictionary = GameState.racks[_entity_id]
	var m: Dictionary = r.get("metrics", {})
	return "%s|%d|%d|%d|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d|%s" % [
		_active_tab,
		(r.get("services", []) as Array).size(),
		GameState.get_reputation_tier() * 10 + GameState.get_company_level(),
		roundi(float(r.get("temp", 22.0))),
		str(r.get("powered", false)),
		str(r.get("networked", false)),
		str(r.get("rental_type", "none")),
		int(r.get("active_users", 0)),
		roundi(float(r.get("satisfaction", 100.0)) / 2.0),
		roundi(float(m.get("ram_pct", 0.0)) / 5.0),
		roundi(float(m.get("cpu_pct", 0.0)) / 5.0),
		roundi(float(m.get("gpu_pct", 0.0)) / 5.0),
		roundi(float(m.get("storage_pct", 0.0)) / 5.0),
		roundi(float(m.get("net_pct", 0.0)) / 5.0),
		str(m.get("bottleneck", "ok")),
	]


func _mb_affordable_count() -> int:
	var n := 0
	for id in GameState.get_mainboards():
		if float(GameState.ITEM_CATALOG[id]["price"]) <= float(GameState.money) and GameState.is_item_unlocked(str(id)):
			n += 1
	return n


## Mausrad über der Mainboard-Liste: Ziel verschieben, _process gleitet weich dorthin.
func _handle_wheel(mb: InputEventMouseButton) -> bool:
	if not mb.pressed or not _mb_picker_open or not is_instance_valid(_parts_scroll):
		return false
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	if not _parts_scroll.get_global_rect().has_point(_parts_scroll.get_global_mouse_position()):
		return false
	var bar := _parts_scroll.get_v_scroll_bar()
	var max_v := maxf(0.0, bar.max_value - bar.page)
	if not _smooth_active:
		_smooth_pos = float(_parts_scroll.scroll_vertical)
		_smooth_target = _smooth_pos
		_smooth_written = _parts_scroll.scroll_vertical
	var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var factor := mb.factor if mb.factor > 0.0 else 1.0
	_smooth_target = clampf(_smooth_target + dir * WHEEL_STEP * factor, 0.0, max_v)
	_smooth_active = true
	return true


func _update_smooth_scroll(delta: float) -> void:
	if not _smooth_active:
		return
	if not is_instance_valid(_parts_scroll) or absi(_parts_scroll.scroll_vertical - _smooth_written) > 2:
		# Liste neu gebaut oder Scrollbalken von Hand gezogen: Gleiten abbrechen.
		_smooth_active = false
		return
	_smooth_pos = lerpf(_smooth_pos, _smooth_target, 1.0 - exp(-SMOOTH_SCROLL_SPEED * delta))
	if absf(_smooth_target - _smooth_pos) < 0.5:
		_smooth_pos = _smooth_target
		_smooth_active = false
	_smooth_written = roundi(_smooth_pos)
	_parts_scroll.scroll_vertical = _smooth_written


func _process(delta: float) -> void:
	if not visible:
		return
	_update_smooth_scroll(delta)
	_pulse_t += delta
	var pulse := 0.35 + 0.65 * absf(sin(_pulse_t * 4.0))
	for n in _pulse_nodes:
		if is_instance_valid(n):
			(n as CanvasItem).modulate.a = pulse

	# Nach einem Neuaufbau ohne Vorschau (z. B. leerer Einschub) bleibt sonst ein leeres Vollbild stehen.
	if _preview_fullscreen and not _preview_frame.is_inside_tree():
		set_preview_fullscreen(false)
	if _preview_vp == null or not _preview_frame.is_inside_tree() or not _preview_frame.visible:
		return
	if _preview_pivot != null:
		_preview_pivot.rotation.y = _preview_yaw
		_preview_pivot.rotation.x = _preview_pitch
	var pspeed := 14.0
	if _preview_fx != null and is_instance_valid(_preview_fx) and GameState.racks.has(_entity_id):
		var prack: Dictionary = GameState.racks[_entity_id]
		var pslots: Array = prack.get("slots", [])
		var pslot: Dictionary = pslots[_selected_slot] if _selected_slot >= 0 and _selected_slot < pslots.size() and pslots[_selected_slot] is Dictionary else {}
		_preview_fx.temp = float(prack.get("temp", 25.0))
		_preview_fx.dust = float(pslot.get("dust_level", 0.0))
		_preview_fx.fault = str(pslot.get("state", "ok")) != "ok"
		_preview_fx.powered = bool(prack.get("powered", false)) and not bool(pslot.get("offline", false)) and not _preview_fx.fault
		pspeed = (11.0 + clampf((_preview_fx.temp - 25.0) * 0.35, 0.0, 22.0)) if _preview_fx.powered else 0.0
	for fn in _preview_fans:
		if is_instance_valid(fn):
			var fnode := fn as Node3D
			if str(fnode.get_meta("spin_axis", "z")) == "x":
				fnode.rotation.x += delta * pspeed
			else:
				fnode.rotation.z += delta * pspeed
	if _preview_fault_mat != null and _preview_faulty_cat != "":
		_preview_fault_mat.albedo_color.a = 0.15 + 0.30 * absf(sin(_pulse_t * 3.0))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Beim Tippen gehören die Tasten dem Umbenennen-Feld. Ein Klick daneben beendet die Eingabe.
	if is_typing():
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and not _rename_edit.get_global_rect().has_point(get_global_mouse_position()):
			_rename_edit.release_focus()
		return
	# Im Vollbild gehören Maus und Mausrad der Vorschau. [ESC] wird in main.gd behandelt.
	if _preview_fullscreen:
		return
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 1.0:
			_set_pointer_mode(true)
			_focus_under_pointer()
		return
	if event is InputEventMouseButton:
		if _handle_wheel(event as InputEventMouseButton):
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	# Enter/Leertaste lösen keine Schaltflächen aus: im Menü wird mit der Maus geklickt.
	if event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_left") \
			or event.is_action("ui_right") or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
		_set_pointer_mode(false)
		_ensure_focus()


## Wird von main.gd bei [E] aufgerufen: löst die Schaltfläche unter dem Mauszeiger
## bzw. (bei Pfeiltasten-Bedienung) die angewählte Schaltfläche aus.
func press_interact() -> void:
	# Mit Mausbedienung löst [E] im Menü nichts aus.
	if not visible or MOUSE_CLICKS_ENABLED:
		return
	var btn := _find_target_button()
	if btn == null:
		return
	if btn.disabled:
		SfxManager.play("error", -10.0)
		return
	_focus_key = str(btn.get_meta("key", ""))
	btn.grab_focus()
	btn.pressed.emit()


func open_rack(rack_id: String, initial_slot: int = 0) -> void:
	if not GameState.racks.has(rack_id):
		return
	_mode = "rack"
	_entity_id = rack_id
	var slot_n := (GameState.racks[rack_id]["slots"] as Array).size()
	_selected_slot = clampi(initial_slot, 0, maxi(slot_n - 1, 0))
	_active_tab = "hardware"
	_focus_key = "slot_%d" % _selected_slot
	_rename_cancelled = false
	_rename_edit.visible = true
	_rename_edit.text = str((GameState.racks[rack_id] as Dictionary).get("custom_name", ""))
	_open_common()


func open_device(kind: String, entity_id: String) -> void:
	_mode = kind
	_entity_id = entity_id
	_focus_key = "primary"
	_rename_edit.visible = false
	_open_common()


## true, solange das Umbenennen-Feld den Tastaturfokus hat. main.gd leitet dann keine Tasten um.
func is_typing() -> bool:
	return is_instance_valid(_rename_edit) and _rename_edit.has_focus()


## [ESC] beim Tippen: Eingabe verwerfen, Menü bleibt offen.
func cancel_typing() -> void:
	if not is_typing():
		return
	_rename_cancelled = true
	_rename_edit.release_focus()


func _commit_rename() -> void:
	if _mode != "rack" or not GameState.racks.has(_entity_id):
		_rename_cancelled = false
		return
	var current := str((GameState.racks[_entity_id] as Dictionary).get("custom_name", ""))
	if _rename_cancelled:
		_rename_cancelled = false
		_rename_edit.text = current
		return
	var wanted := _rename_edit.text.strip_edges()
	if wanted != current:
		GameState.request_rename_rack(_entity_id, wanted)


func close_inspector() -> void:
	_confirm_sell_entity = false
	_confirm_sell_module = false
	_preview_dragging = false
	set_preview_fullscreen(false)
	if _preview_vp != null:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	UIStyle.animate_popup_close(self, _card)
	SfxManager.play("click", -10.0, 0.85)


func _open_common() -> void:
	_confirm_sell_entity = false
	_confirm_sell_module = false
	_preview_sig = ""
	_parts_scroll_v = 0
	_rental_scroll_v = 0.0
	_pointer_mode = false
	_animate_next = true
	_fit_card_size()
	UIStyle.animate_popup_open(self, _card)
	_refresh()
	SfxManager.play("click", -8.0, 1.15)


func _on_viewport_resized() -> void:
	if visible:
		_fit_card_size()


func _fit_card_size() -> void:
	if _card == null:
		return
	var vp := get_viewport_rect().size
	_card.custom_minimum_size = Vector2(
		clampf(vp.x - SCREEN_MARGIN, CARD_MIN_SIZE.x, CARD_MAX_SIZE.x),
		clampf(vp.y - SCREEN_MARGIN, CARD_MIN_SIZE.y, CARD_MAX_SIZE.y)
	)


func _refresh() -> void:
	if not visible:
		return
	match _mode:
		"rack":
			if not GameState.racks.has(_entity_id):
				close_requested.emit()
				return
			_render_rack_view()
		"router":
			_render_router_view()
		"cooler", "ups", "cart", "decor":
			if not _device_exists(_mode):
				close_requested.emit()
				return
			_render_device_view(_mode)
		_:
			return
	_restore_focus()
	_animate_next = false
	# Stand merken, damit identische Sync-Signale danach keinen weiteren Neuaufbau auslösen.
	_struct_sig = _struct_signature()
	_live_sig = _live_signature()
	_last_live_refresh_ms = Time.get_ticks_msec()


func _device_exists(kind: String) -> bool:
	match kind:
		"cooler":
			return GameState.coolers.has(_entity_id)
		"ups":
			return GameState.ups_units.has(_entity_id)
		"cart":
			return GameState.carts.has(_entity_id)
		"decor":
			return GameState.decor_items.has(_entity_id)
	return false


## Räumt den alten Aufbau ab. Die 3D-Vorschau wird vorher herausgelöst, damit sie nicht mit gelöscht wird.
func _begin_render() -> void:
	if is_instance_valid(_rental_scroll):
		_rental_scroll_v = float(_rental_scroll.scroll_vertical)
	_rental_scroll = null
	if is_instance_valid(_parts_scroll):
		_parts_scroll_v = roundi(_smooth_target) if _smooth_active else _parts_scroll.scroll_vertical
	_parts_scroll = null
	_smooth_active = false
	_mb_money_label = null
	var pp := _preview_frame.get_parent()
	if pp != null:
		pp.remove_child(_preview_frame)
	_clear(_kpi_row)
	_clear(_tab_row)
	_clear(_body_host)
	_clear(_footer_actions)
	_buttons.clear()
	_pulse_nodes.clear()


# ==============================================================================
# RACK
# ==============================================================================
func _render_rack_view() -> void:
	_begin_render()
	var rack: Dictionary = GameState.racks[_entity_id]
	var rtype := str(rack.get("rack_type", "rack"))
	var cat_rack: Dictionary = GameState.ITEM_CATALOG[rtype]
	var slots: Array = rack["slots"]
	_selected_slot = clampi(_selected_slot, 0, maxi(slots.size() - 1, 0))

	var hw := GameState.get_rack_hardware_summary(_entity_id)
	var used_slots := _count_used_slots(slots)
	var max_pdu := maxi(int(cat_rack.get("max_pdu_watts", 3200)), 1)
	var watts := int(hw["watts"])
	var temp := float(rack["temp"])
	var powered := bool(rack["powered"])
	var networked := bool(rack["networked"])

	_title_lbl.text = "%s  —  %s" % [GameState.get_rack_display_name(_entity_id), tr(str(cat_rack["name"]))]
	# Namen übernehmen, den ein Mitspieler vergeben hat, außer während hier getippt wird.
	if not is_typing():
		var saved_name := str(rack.get("custom_name", ""))
		if _rename_edit.text != saved_name:
			_rename_edit.text = saved_name
	_subtitle_lbl.text = tr("Guthaben: $%.0f   •   Teile im Lager: %d   •   Haus-Router: %s") % [
		GameState.money, GameState.get_total_inventory_parts(), HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
	]
	var status := _rack_status(slots, powered, networked, temp, watts, max_pdu)
	_set_status(str(status[0]), status[1] as Color)

	# Kennzahlen
	var watt_ratio := float(watts) / float(max_pdu)
	_add_kpi("STROMLAST", "%d / %d W" % [watts, max_pdu], tr("PDU des Racks"),
		UIStyle.COL_RED if watts > max_pdu else _load_color(watt_ratio * 100.0), watt_ratio)
	_add_kpi("TEMPERATUR", "%.0f °C" % temp, tr("kritisch ab %.0f °C") % TEMP_CRIT,
		UIStyle.COL_RED if temp >= TEMP_CRIT else (UIStyle.COL_AMBER if temp >= TEMP_CRIT - TEMP_WARN_SPAN else UIStyle.COL_BLUE),
		temp / TEMP_GAUGE_MAX)
	_add_kpi("EINSCHÜBE", tr("%d / %d belegt") % [used_slots, slots.size()], tr("%d Server online") % int(hw["active_servers"]),
		UIStyle.COL_GREEN if used_slots < slots.size() else UIStyle.COL_AMBER, float(used_slots) / float(maxi(slots.size(), 1)))
	var r_rent := str(rack.get("rental_type", "none"))
	if r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
		var sat := float(rack.get("satisfaction", 100.0))
		_add_kpi("EINNAHMEN", "+$%.0f / 5 s" % float(rack.get("rental_income", 0.0)),
			tr("%d Nutzer  •  %.0f %% zufrieden") % [int(rack.get("active_users", 0)), sat],
			UIStyle.COL_AMBER if sat < SAT_WARN else UIStyle.COL_GREEN, sat / 100.0)
	else:
		_add_kpi("EINNAHMEN", tr("Nicht vermietet"), tr("Reiter VERMIETUNG"), UIStyle.COL_TEXT_SUB, -1.0, "info")
	_add_kpi("ANSCHLÜSSE", tr("Strom %s  •  LAN %s") % ["OK" if powered else tr("FEHLT"), "OK" if networked else tr("FEHLT")],
		"", UIStyle.COL_GREEN if (powered and networked) else UIStyle.COL_AMBER, -1.0, "info" if (powered and networked) else "warn")

	# Reiter
	_tab_row.visible = true
	_add_tab("hardware", tr("HARDWARE & EINSCHÜBE"))
	_add_tab("rental", tr("VERMIETUNG & AUSLASTUNG"))

	# Rack-Aktionen unten rechts
	var move_btn := _make_btn(tr("Rack umsetzen"), "rack_move", Vector2(150, 34))
	_style_btn(move_btn, Color(0.15, 0.17, 0.19), UIStyle.COL_BLUE)
	move_btn.pressed.connect(func(): relocate_rack_requested.emit(_entity_id))
	_footer_actions.add_child(move_btn)

	var sell_val := GameState.get_rack_sell_value(_entity_id)
	var sell_btn := _make_btn("", "rack_sell", Vector2(200, 34))
	if _confirm_sell_entity:
		sell_btn.text = tr("WIRKLICH VERKAUFEN? (+$%d)") % sell_val
		_style_btn(sell_btn, Color(0.62, 0.16, 0.14), UIStyle.COL_RED)
	else:
		sell_btn.text = tr("Rack verkaufen (+$%d)") % sell_val
		_style_btn(sell_btn, Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell_btn.pressed.connect(func():
		if not _confirm_sell_entity:
			_confirm_sell_entity = true
			SfxManager.play("click", -8.0, 0.9)
			_refresh()
		else:
			GameState.request_sell_rack(_entity_id)
			close_requested.emit()
	)
	_footer_actions.add_child(sell_btn)

	if slots.is_empty():
		_update_3d_preview("", {})
		_body_host.add_child(_make_label(tr("Dieses Rack hat keine Einschübe."), 14, UIStyle.COL_TEXT_SUB))
		return

	if _active_tab == "rental":
		_update_3d_preview("", {})
		_render_rack_rental(rack, hw)
	else:
		_render_rack_hardware(slots, hw, powered)


func _rack_status(slots: Array, powered: bool, networked: bool, temp: float, watts: int, max_pdu: int) -> Array:
	for s in slots:
		if str((s as Dictionary)["state"]) == "burning":
			return [tr("BRAND!"), UIStyle.COL_RED]
	if not powered:
		return [tr("KEIN STROM"), UIStyle.COL_RED]
	if watts > max_pdu:
		return [tr("ÜBERLAST"), UIStyle.COL_RED]
	if temp >= TEMP_CRIT:
		return [tr("ÜBERHITZT"), UIStyle.COL_RED]
	for s in slots:
		if str((s as Dictionary)["state"]) == "crashed":
			return [tr("STÖRUNG"), UIStyle.COL_AMBER]
	if not networked:
		return [tr("KEIN LAN"), UIStyle.COL_AMBER]
	return [tr("IN BETRIEB"), UIStyle.COL_GREEN]


func _count_used_slots(slots: Array) -> int:
	var n := 0
	for s in slots:
		if str((s as Dictionary)["item_type"]) != "":
			n += 1
	return n


# ------------------------------------------------------------------------------
# Reiter HARDWARE: Rack-Schrank | Einschub | 3D-Vorschau
# ------------------------------------------------------------------------------
func _render_rack_hardware(slots: Array, hw: Dictionary, powered: bool) -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	_body_host.add_child(split)

	_build_rack_column(split, slots, hw, powered)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	split.add_child(mid)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_COL_W, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	split.add_child(side)

	var slot: Dictionary = slots[_selected_slot]
	var itype := str(slot["item_type"])
	if itype == "":
		_build_mainboard_picker(mid)
	else:
		_build_slot_detail(mid, slot, itype)
	_build_side_column(side, slot, itype)


func _build_rack_column(parent: HBoxContainer, slots: Array, hw: Dictionary, powered: bool) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(RACK_COL_W, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	col.add_child(_section_label("RACK-SCHRANK"))

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UIStyle.make_panel(COL_RACK_FRAME, UIStyle.COL_BORDER, 6, 1, 8, 8))
	col.add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	for i in range(slots.size()):
		list.add_child(_make_slot_button(i, slots[i] as Dictionary, powered))

	var sum := PanelContainer.new()
	sum.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 6, 1, 12, 9))
	col.add_child(sum)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sum.add_child(sv)
	_add_kv_line(sv, "CPU-Leistung", tr("%d Pkt.") % int(hw["cpu_score"]))
	_add_kv_line(sv, "Arbeitsspeicher", "%d GB" % int(hw["ram_gb"]))
	_add_kv_line(sv, "Grafik / VRAM", tr("%d Pkt. (%d GB)") % [int(hw["gpu_score"]), int(hw["vram_gb"])])
	_add_kv_line(sv, "Speicherplatz", "%.1f TB" % float(hw["storage_tb"]))


func _make_slot_button(i: int, slot: Dictionary, powered: bool) -> Button:
	var itype := str(slot["item_type"])
	var state := str(slot["state"])
	var sel := (i == _selected_slot)
	var bad := state == "burning" or state == "crashed"

	var btn := _make_btn("", "slot_%d" % i, Vector2(0, SLOT_ROW_H))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn, COL_SELECT if sel else COL_SLOT_BG, UIStyle.COL_RED if bad else (UIStyle.COL_ACCENT if sel else UIStyle.COL_BORDER))
	# Gilt für freie und belegte Einschübe; vorher fehlte das bei freien Slots.
	btn.pressed.connect(func(): _select_slot(i))

	var m := _btn_content(btn, 10, 6)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	m.add_child(row)

	var u := _make_label("U%d" % (i + 1), 11, UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_SUB, true)
	u.custom_minimum_size = Vector2(26, 0)
	u.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(u)

	var led := ColorRect.new()
	led.custom_minimum_size = Vector2(8, 8)
	led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	led.color = _slot_led_color(slot, powered)
	row.add_child(led)
	if bad:
		_pulse_nodes.append(led)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	if itype == "":
		info.add_child(_make_label(tr("Frei"), 13, UIStyle.COL_TEXT_SUB, true))
		info.add_child(_make_label(tr("Mainboard einbauen"), 11, Color(UIStyle.COL_TEXT_SUB, 0.75)))
		var plus := _make_label("+", 20, UIStyle.COL_ACCENT, true)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(plus)
		return btn

	info.add_child(_make_label(tr(str(GameState.ITEM_CATALOG[itype]["name"])), 13, UIStyle.COL_TEXT_MAIN, true))
	var st := GameState.get_slot_stats(slot)
	var line := ""
	if GameState.is_slot_upgradeable(itype):
		line = "%d GB %s  •  %.1f TB  •  %d W" % [int(st["ram_gb"]), str(st["ram_tag"]), float(st["storage_tb"]), int(st["watts"])]
	else:
		line = tr("Netzwerk-Switch  •  %d W") % int(st["watts"])
	if state == "burning":
		info.add_child(_make_label(tr("BRAND!"), 11, UIStyle.COL_RED, true))
	elif state == "crashed":
		info.add_child(_make_label(tr("AUSGEFALLEN"), 11, UIStyle.COL_AMBER, true))
	elif bool(slot.get("offline", false)):
		info.add_child(_make_label(tr("FÄHRT HOCH …") if float(slot.get("boot_total", 0.0)) > 0.0 else tr("STROMLOS (ausgefahren)"), 11, UIStyle.COL_BLUE, true))
	else:
		info.add_child(_make_label(line, 11, UIStyle.COL_TEXT_SUB))
	return btn


func _select_slot(i: int) -> void:
	if i != _selected_slot:
		_confirm_sell_module = false
		_parts_scroll_v = 0
		_mb_picker_open = false
	_selected_slot = i
	SfxManager.play("click", -12.0, 1.1)
	_refresh()


func _slot_led_color(slot: Dictionary, powered: bool) -> Color:
	var itype := str(slot["item_type"])
	var state := str(slot["state"])
	if itype == "":
		return COL_LED_OFF
	if state == "burning":
		return UIStyle.COL_RED
	if state == "crashed":
		return UIStyle.COL_AMBER
	if not powered:
		return COL_LED_DARK
	if bool(slot.get("offline", false)):
		return UIStyle.COL_BLUE if float(slot.get("boot_total", 0.0)) > 0.0 else COL_LED_DARK
	return UIStyle.COL_GREEN


## Leerer Einschub: zuerst eine Übersicht mit "Mainboard auswählen", danach die Mainboard-Liste.
## Die Liste ist nach Kategorien gruppiert und innerhalb jeder Kategorie nach Preis sortiert.
## Ein Klick auf eine Zeile kauft das Mainboard und baut es sofort ein.
func _build_mainboard_picker(parent: VBoxContainer) -> void:
	if not _mb_picker_open:
		_build_empty_slot_intro(parent)
		return

	# Kopfzeile: Titel, Guthaben, Zurück
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT, 8, 1, 14, 6))
	parent.add_child(head)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 14)
	head.add_child(hr)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 2)
	hr.add_child(hv)
	hv.add_child(_make_label(tr("Mainboard für Einschub U%d") % (_selected_slot + 1), 16, UIStyle.COL_TEXT_MAIN, true))
	var hint := _make_label(tr("Zeile anklicken: Das Mainboard wird gekauft und sofort eingebaut."), 11, UIStyle.COL_TEXT_SUB)
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.clip_text = true
	hv.add_child(hint)

	var money_box := VBoxContainer.new()
	money_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_box.add_theme_constant_override("separation", 0)
	hr.add_child(money_box)
	var ml := _make_label(tr("GUTHABEN"), 10, UIStyle.COL_TEXT_SUB, true)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(ml)
	var mv := _make_label("$%.0f" % GameState.money, 18, UIStyle.COL_GOLD_TEXT, true)
	mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(mv)
	_mb_money_label = mv
	_mb_afford_sig = _mb_affordable_count()

	var back := _make_btn(tr("Zurück"), "mb_back", Vector2(100, 30))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_btn(back, Color(0.15, 0.17, 0.19), UIStyle.COL_BORDER)
	back.pressed.connect(func():
		_mb_picker_open = false
		_focus_key = "mb_open"
		SfxManager.play("click", -12.0, 1.1)
		_refresh()
	)
	hr.add_child(back)

	# Kategorie-Reiter: gleich breit über die ganze Spalte
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	parent.add_child(tabs)
	tabs.add_child(_make_mb_cat_btn("", tr("Alle"), GameState.get_mainboards().size(), UIStyle.COL_ACCENT))
	for c in GameState.MAINBOARD_CATEGORIES:
		var cd := c as Dictionary
		var cid := str(cd["id"])
		tabs.add_child(_make_mb_cat_btn(cid, tr(str(cd["label"])), GameState.get_mainboards(cid).size(), cd["color"] as Color))

	# Liste: eine Zeile pro Mainboard, darüber je Kategorie eine farbige Kopfzeile
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	parent.add_child(scroll)
	_parts_scroll = scroll

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(pad)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	pad.add_child(list)

	var first := true
	for c in GameState.MAINBOARD_CATEGORIES:
		var cd := c as Dictionary
		var cid := str(cd["id"])
		if _mb_cat != "" and cid != _mb_cat:
			continue
		var ids := GameState.get_mainboards(cid)
		if ids.is_empty():
			continue
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 6)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			list.add_child(gap)
		first = false
		list.add_child(_make_mb_group_header(cd, ids.size()))
		for id in ids:
			list.add_child(_make_mainboard_card(str(id)))


## Übersicht für einen freien Einschub: Server-Konfigurator (-> Warenkorb -> Werkbank) + Schachtsteuerung.
func _build_empty_slot_intro(parent: VBoxContainer) -> void:
	var slots: Array = GameState.racks[_entity_id]["slots"]
	var free_n := slots.size() - _count_used_slots(slots)
	var all_ids := GameState.get_mainboards()
	var from_price := 0 if all_ids.is_empty() else int(GameState.ITEM_CATALOG[all_ids[0]]["price"])

	if _cfg_open:
		_build_slot_configurator(parent, all_ids)
		return

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT, 10, 1, 22, 18))
	parent.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 10)
	head.add_child(hv)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	hv.add_child(title_row)
	var tl := _make_label(tr("Einschub U%d ist frei") % (_selected_slot + 1), 22, UIStyle.COL_TEXT_MAIN, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(tl)
	title_row.add_child(_make_chip(tr("%d / %d FREI") % [free_n, slots.size()], UIStyle.COL_GREEN))

	var info := _make_label(tr("Konfiguriere einen Server für diesen Einschub, lege ihn in den Warenkorb und baue den gelieferten Bausatz an der Werkbank zusammen."), 12, UIStyle.COL_TEXT_SUB)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(info)

	if not _cfg_toast.is_empty():
		var toast_l := _make_label(_cfg_toast, 12, UIStyle.COL_GREEN, true)
		toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(toast_l)

	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UIStyle.COL_BORDER
	hv.add_child(line)

	var steps := [
		tr("Server hier im Einschub konfigurieren & „In den Warenkorb“ legen"),
		tr("Am PC-Shop bestellen → beschrifteter Bausatz-Karton wird per Lieferwagen geliefert"),
		tr("An der Werkbank realistisch zusammenbauen & in den ausgefahrenen Schacht einsetzen"),
	]
	for i in range(steps.size()):
		var sr := HBoxContainer.new()
		sr.add_theme_constant_override("separation", 10)
		hv.add_child(sr)
		var num := _make_chip(str(i + 1), UIStyle.COL_ACCENT)
		num.custom_minimum_size = Vector2(26, 0)
		sr.add_child(num)
		var sl := _make_label(str(steps[i]), 13, UIStyle.COL_TEXT_MAIN)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(sl)

	var cfg_btn := _make_btn(tr("SERVER KONFIGURIEREN (→ WARENKORB)"), "cfg_open", Vector2(0, 56))
	cfg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(cfg_btn, COL_SELECT, UIStyle.COL_ACCENT)
	if _display_font != null:
		cfg_btn.add_theme_font_override("font", _display_font)
	cfg_btn.add_theme_font_size_override("font_size", 17)
	cfg_btn.pressed.connect(func():
		_open_slot_configurator(all_ids)
	)
	parent.add_child(cfg_btn)

	var row_actions := HBoxContainer.new()
	row_actions.add_theme_constant_override("separation", 10)
	parent.add_child(row_actions)

	var is_ext := GameState.is_slot_extended(_entity_id, _selected_slot)
	var ext_btn := _make_btn(tr("Schacht einfahren") if is_ext else tr("Schacht ausfahren (Teleskop)"), "slot_extend", Vector2(0, 40))
	ext_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(ext_btn, Color(0.14, 0.28, 0.38) if is_ext else UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT)
	ext_btn.pressed.connect(func():
		GameState.request_toggle_slot_extended(_entity_id, _selected_slot)
		SfxManager.play("click", -10.0, 1.05)
	)
	row_actions.add_child(ext_btn)

	var open_btn := _make_btn(tr("Direkt-Mainboard (ab $%d)") % from_price, "mb_open", Vector2(0, 40))
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(open_btn, UIStyle.COL_BG_CARD, UIStyle.COL_BORDER)
	open_btn.pressed.connect(func(): _open_mb_picker(""))
	row_actions.add_child(open_btn)


func _open_slot_configurator(all_ids: Array) -> void:
	_cfg_open = true
	_cfg_toast = ""
	if _cfg_mb.is_empty() or not GameState.ITEM_CATALOG.has(_cfg_mb):
		_cfg_mb = str(all_ids[0]) if not all_ids.is_empty() else "web_server"
	_ensure_cfg_defaults()
	SfxManager.play("click", -12.0, 1.1)
	_refresh()


func _ensure_cfg_defaults() -> void:
	for cat_v in GameState.COMPONENT_ORDER:
		var cat := str(cat_v)
		if cat == "gpu":
			continue
		var cur := str(_cfg_comps.get(cat, ""))
		if cur.is_empty() or HardwareCatalog.get_part(cat, cur).is_empty():
			var plist: Array = HardwareCatalog.PARTS.get(cat, [])
			for p in plist:
				var pd: Dictionary = p
				if GameState.is_part_unlocked(pd):
					_cfg_comps[cat] = str(pd["id"])
					break


func _build_slot_configurator(parent: VBoxContainer, all_ids: Array) -> void:
	_ensure_cfg_defaults()
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT, 8, 1, 14, 10))
	parent.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	head.add_child(hv)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hv.add_child(hrow)
	var title := _make_label(tr("Konfigurator · %s · Slot %d") % [GameState.get_rack_display_name(_entity_id), _selected_slot + 1], 16, UIStyle.COL_TEXT_MAIN, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(title)
	var back_b := _make_btn(tr("Zurück"), "cfg_back", Vector2(88, 28))
	_style_btn(back_b, UIStyle.COL_BG_DARK, UIStyle.COL_BORDER)
	back_b.pressed.connect(func():
		_cfg_open = false
		_refresh()
	)
	hrow.add_child(back_b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	# 1. Mainboard-Auswahl
	var mb_row := HBoxContainer.new()
	mb_row.add_theme_constant_override("separation", 8)
	list.add_child(mb_row)
	var mbl := _make_label(tr("Mainboard"), 13, UIStyle.COL_ACCENT, true)
	mbl.custom_minimum_size = Vector2(126, 0)
	mb_row.add_child(mbl)
	var mb_opt := OptionButton.new()
	mb_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mb_sel_idx := 0
	var unlocked_mbs: Array[String] = []
	for mid_v in all_ids:
		var mid := str(mid_v)
		if GameState.is_item_unlocked(mid):
			var md: Dictionary = GameState.ITEM_CATALOG[mid]
			mb_opt.add_item("%s ($%d)" % [str(md["name"]), int(md["price"])])
			if mid == _cfg_mb:
				mb_sel_idx = unlocked_mbs.size()
			unlocked_mbs.append(mid)
	if not unlocked_mbs.is_empty():
		mb_opt.select(mb_sel_idx)
		_cfg_mb = unlocked_mbs[mb_sel_idx]
	mb_opt.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < unlocked_mbs.size():
			_cfg_mb = unlocked_mbs[idx]
			_refresh()
	)
	mb_row.add_child(mb_opt)

	# 2. Komponenten-Auswahl (CPU, RAM, GPU, Storage, Cooling, PSU)
	for cat_v in GameState.COMPONENT_ORDER:
		var cat := str(cat_v)
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		list.add_child(crow)
		var cl := _make_label(GameState.get_component_label(cat), 13, UIStyle.COL_TEXT_MAIN, true)
		cl.custom_minimum_size = Vector2(126, 0)
		crow.add_child(cl)
		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ids: Array[String] = []
		if cat == "gpu":
			opt.add_item(tr("Keine GPU ($0)"))
			ids.append("")
		var plist: Array = HardwareCatalog.PARTS.get(cat, [])
		var cur_pid := str(_cfg_comps.get(cat, ""))
		var sel_i := 0
		for p in plist:
			var pd: Dictionary = p
			if not GameState.is_part_unlocked(pd):
				continue
			var pid := str(pd["id"])
			opt.add_item("%s ($%d)" % [str(pd["name"]), int(pd.get("cost", 0))])
			if pid == cur_pid:
				sel_i = ids.size()
			ids.append(pid)
		if not ids.is_empty():
			opt.select(sel_i)
			_cfg_comps[cat] = ids[sel_i]
		var cap_cat := cat
		opt.item_selected.connect(func(idx: int):
			if idx >= 0 and idx < ids.size():
				_cfg_comps[cap_cat] = ids[idx]
				_refresh()
		)
		crow.add_child(opt)

	var total_p := GameState.calculate_slot_build_price(_cfg_mb, _cfg_comps)
	var add_btn := _make_btn(tr("IN DEN WARENKORB ($%d)") % total_p, "cfg_add_cart", Vector2(0, 48))
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(add_btn, Color(0.14, 0.44, 0.24), UIStyle.COL_GREEN)
	if _display_font != null:
		add_btn.add_theme_font_override("font", _display_font)
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.pressed.connect(func():
		if GameState.cart_add_slot_build(_entity_id, _selected_slot, _cfg_mb, _cfg_comps):
			SfxManager.play("click", -8.0, 1.2)
			_cfg_open = false
			_cfg_toast = tr("✓ In den Warenkorb gelegt (%s · Slot %d)! Bestelle am PC-Shop.") % [GameState.get_rack_display_name(_entity_id), _selected_slot + 1]
			_refresh()
	)
	parent.add_child(add_btn)


func _open_mb_picker(cid: String) -> void:
	_mb_picker_open = true
	_mb_cat = cid
	_parts_scroll_v = 0
	_focus_key = "mbcat_%s" % (cid if cid != "" else "all")
	SfxManager.play("click", -12.0, 1.1)
	_refresh()


func _make_mb_cat_btn(cid: String, label: String, count: int, col: Color) -> Button:
	var sel := (cid == _mb_cat)
	var b := _make_btn("%s  %d" % [label, count], "mbcat_%s" % (cid if cid != "" else "all"), Vector2(0, 28))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	_style_btn(b, Color(col, 0.22) if sel else UIStyle.COL_BG_CARD, col if sel else UIStyle.COL_BORDER)
	if sel:
		b.add_theme_color_override("font_color", UIStyle.COL_TEXT_MAIN)
	b.pressed.connect(func():
		_mb_cat = cid
		_parts_scroll_v = 0
		SfxManager.play("click", -12.0, 1.1)
		_refresh()
	)
	return b


## Farbige Kopfzeile einer Mainboard-Kategorie in der Liste.
func _make_mb_group_header(cd: Dictionary, count: int) -> PanelContainer:
	var col := cd["color"] as Color
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIStyle.make_panel(Color(col, 0.12), Color(col, 0.60), 6, 1, 10, 4)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(_make_label(tr(str(cd["label"])).to_upper(), 13, col, true))
	var dl := _make_label(tr(str(cd["desc"])), 11, UIStyle.COL_TEXT_SUB)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dl.clip_text = true
	h.add_child(dl)
	h.add_child(_make_chip(str(cd["form"]), col))
	h.add_child(_make_label(tr("%d Boards") % count, 11, UIStyle.COL_TEXT_SUB, true))
	return p


## Eine Mainboard-Zeile: Farbleiste, Name mit Beschreibung, Werte als Chips, rechts der Preis.
func _make_mainboard_card(item_type: String) -> Button:
	var item: Dictionary = GameState.ITEM_CATALOG[item_type]
	var price := int(item.get("price", 0))
	var unlocked := GameState.is_item_unlocked(item_type)
	var affordable := unlocked and GameState.money >= float(price)
	var accent := item.get("color", UIStyle.COL_ACCENT) as Color
	var bonus := int(roundf(float(item.get("revenue_bonus", 0.0)) * 100.0))

	var btn := _make_btn("", "mb_%s" % item_type, Vector2(0, MB_ROW_H))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not affordable
	btn.tooltip_text = tr(str(item.get("desc", "")))
	_style_btn(btn, UIStyle.COL_BG_CARD, accent if affordable else UIStyle.COL_BORDER)
	var m := _btn_content(btn, 10, 5)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	m.add_child(row)

	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.color = accent if affordable else Color(accent, 0.35)
	row.add_child(stripe)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)

	var nl := _make_label(tr(str(item.get("name", item_type))), 14, UIStyle.COL_TEXT_MAIN if affordable else UIStyle.COL_TEXT_SUB, true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	v.add_child(nl)

	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 5)
	v.add_child(chips)
	chips.add_child(_make_chip(str(item.get("form", "")), accent))
	chips.add_child(_make_chip(tr("LEISTUNG %d") % int(item.get("base_compute", 0)), UIStyle.COL_BLUE))
	if bonus > 0:
		chips.add_child(_make_chip(tr("+%d %% EINNAHMEN") % bonus, UIStyle.COL_GREEN))
	chips.add_child(_make_chip("%d W" % int(item.get("watts", 0)), UIStyle.COL_AMBER))

	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(96, 0)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 0)
	row.add_child(pv)
	var price_l := _make_label("$%d" % price, 17, UIStyle.COL_GOLD_TEXT if affordable else UIStyle.COL_RED, true)
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(price_l)
	var act_text := tr("KAUFEN & EINBAUEN")
	if not unlocked:
		act_text = tr("🔒 AB FIRMENSTUFE %d") % GameState.get_item_required_level(item_type)
	elif not affordable:
		act_text = tr("ZU WENIG GELD")
	var act_l := _make_label(act_text, 9, UIStyle.COL_TEXT_SUB, true)
	act_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(act_l)

	var cap_slot := _selected_slot
	btn.pressed.connect(func():
		SfxManager.play("click", -12.0, 1.1)
		_mb_picker_open = false
		_selected_cat = "cpu"
		_selected_filter = "Alle"
		_parts_scroll_v = 0
		_focus_key = "cat_cpu"
		GameState.request_buy_install_module(_entity_id, cap_slot, item_type)
	)
	return btn


## Belegter Einschub: Kopfkarte, Komponenten-Kacheln und Teileliste der gewählten Kategorie.
func _build_slot_detail(parent: VBoxContainer, slot: Dictionary, itype: String) -> void:
	var state := str(slot["state"])
	var stats := GameState.get_slot_stats(slot)
	var overloaded := bool(stats["psu_overloaded"])
	var bad := state == "burning" or state == "crashed"

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UIStyle.make_panel(
		UIStyle.COL_BG_CARD, UIStyle.COL_RED if (overloaded or bad) else UIStyle.COL_BORDER, 8, 1, 14, 10
	))
	parent.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	head.add_child(hv)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	hv.add_child(top)

	var name_l := _make_label("U%d  ·  %s" % [_selected_slot + 1, tr(str(GameState.ITEM_CATALOG[itype]["name"]))], 17, UIStyle.COL_TEXT_MAIN, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name_l)

	if state == "burning":
		top.add_child(_make_chip(tr("BRENNT"), UIStyle.COL_RED))
	elif state == "crashed":
		top.add_child(_make_chip(tr("AUSGEFALLEN"), UIStyle.COL_AMBER))
	elif bool(slot.get("offline", false)):
		top.add_child(_make_chip(tr("FÄHRT HOCH …") if float(slot.get("boot_total", 0.0)) > 0.0 else tr("STROMLOS (ausgefahren)"), UIStyle.COL_BLUE))
	else:
		top.add_child(_make_chip(tr("ONLINE"), UIStyle.COL_GREEN))

	# Reparieren geht nur über die 3D-Vorschau: Klick auf das defekte Bauteil.

	var sv_amt := int(roundf(float(stats["total_value"]) * GameState.SELL_REFUND_RATIO))
	var sell := _make_btn("", "slot_sell", Vector2(190, 32))
	sell.disabled = (state == "burning")
	if _confirm_sell_module:
		sell.text = tr("WIRKLICH VERKAUFEN? (+$%d)") % sv_amt
		_style_btn(sell, Color(0.62, 0.16, 0.14), UIStyle.COL_RED)
	else:
		sell.text = tr("Modul verkaufen (+$%d)") % sv_amt
		_style_btn(sell, Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell.pressed.connect(func():
		if not _confirm_sell_module:
			_confirm_sell_module = true
			SfxManager.play("click", -8.0, 0.9)
			_refresh()
		else:
			_confirm_sell_module = false
			_focus_key = "slot_%d" % _selected_slot
			GameState.request_sell_slot_module(_entity_id, _selected_slot)
	)
	top.add_child(sell)

	if not GameState.is_slot_upgradeable(itype):
		var sw := _make_label(tr("Ein Rack-Switch braucht keine internen Bauteile und leitet LAN automatisch an bis zu 3 weitere Racks weiter."), 12, UIStyle.COL_TEXT_SUB)
		sw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(sw)
		return

	var spec := _make_label(tr("CPU %d Pkt.  •  RAM %d GB %s  •  GPU %d Pkt. (%d GB)  •  Speicher %.1f TB") % [
		int(stats["cpu_score"]), int(stats["ram_gb"]), str(stats["ram_tag"]),
		int(stats["gpu_score"]), int(stats["vram_gb"]), float(stats["storage_tb"])
	], 12, UIStyle.COL_TEXT_SUB)
	spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(spec)
	if overloaded:
		hv.add_child(_make_label(tr("Netzteil zu schwach: %d W Bedarf, %d W maximal") % [int(stats["watts"]), int(stats["psu_max_watts"])], 12, UIStyle.COL_RED, true))

	# Schacht-Steuerung & Herausziehen für Reparatur an der Werkbank
	var tray_row := HBoxContainer.new()
	tray_row.add_theme_constant_override("separation", 8)
	hv.add_child(tray_row)
	var is_ext := GameState.is_slot_extended(_entity_id, _selected_slot)
	var ext_btn := _make_btn(tr("Schacht einfahren") if is_ext else tr("Schacht ausfahren"), "slot_ext_occ", Vector2(0, 32))
	ext_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(ext_btn, Color(0.14, 0.28, 0.38) if is_ext else UIStyle.COL_BG_DARK, UIStyle.COL_ACCENT)
	ext_btn.pressed.connect(func():
		GameState.request_toggle_slot_extended(_entity_id, _selected_slot)
		SfxManager.play("click", -10.0, 1.05)
	)
	tray_row.add_child(ext_btn)

	var pull_btn := _make_btn(tr("🔧 Server zur Werkbank ziehen") if state == "crashed" else tr("Server-Schlitten herausziehen"), "slot_pull_tray", Vector2(0, 32))
	pull_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pull_btn.disabled = (state == "burning") or GameState.is_player_holding_anything(multiplayer.get_unique_id())
	_style_btn(pull_btn, Color(0.46, 0.22, 0.08) if state == "crashed" else UIStyle.COL_BG_DARK, UIStyle.COL_AMBER if state == "crashed" else UIStyle.COL_BORDER)
	pull_btn.pressed.connect(func():
		if not GameState.is_slot_extended(_entity_id, _selected_slot):
			GameState.request_toggle_slot_extended(_entity_id, _selected_slot)
		GameState.request_pull_server_tray(_entity_id, _selected_slot)
		close_requested.emit()
	)
	tray_row.add_child(pull_btn)

	parent.add_child(_section_label("KOMPONENTEN  ·  KATEGORIE WÄHLEN"))
	var comps := HardwareCatalog.normalize_components(slot.get("components", {}) as Dictionary, itype)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for cat_k in HardwareCatalog.CATEGORY_ORDER:
		grid.add_child(_make_category_tile(str(cat_k), comps))

	_build_part_picker(parent, comps, state)


func _make_category_tile(cat_k: String, comps: Dictionary) -> Button:
	var cm: Dictionary = HardwareCatalog.CATEGORY_META[cat_k]
	var sel := (cat_k == _selected_cat)
	var stock_n := 0
	for p in HardwareCatalog.get_category_parts(cat_k):
		stock_n += GameState.get_part_stock(str((p as Dictionary)["id"]))
	var pid := str(comps.get(cat_k, HardwareCatalog.DEFAULT_PARTS.get(cat_k, "")))
	var part: Dictionary = HardwareCatalog.get_part(cat_k, pid)

	var btn := _make_btn("", "cat_%s" % cat_k, Vector2(0, TILE_H))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn, COL_SELECT if sel else UIStyle.COL_BG_CARD, UIStyle.COL_ACCENT if sel else UIStyle.COL_BORDER)
	var m := _btn_content(btn, 10, 6)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)

	var tr_row := HBoxContainer.new()
	tr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr_row)
	var cl := _make_label(tr(str(cm["short"])).to_upper(), 10, UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_SUB, true)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_row.add_child(cl)
	if stock_n > 0:
		tr_row.add_child(_make_label(tr("%d im Lager") % stock_n, 10, UIStyle.COL_GREEN))

	if part.is_empty():
		var required := GameState.REQUIRED_PART_CATS.has(cat_k)
		v.add_child(_make_label(tr("Leer – Pflichtteil fehlt") if required else tr("Leer – optional"), 13, UIStyle.COL_RED if required else UIStyle.COL_TEXT_SUB))
	else:
		v.add_child(_make_label(str(part.get("name", "-")), 13, UIStyle.COL_TEXT_MAIN))
	var strength := 0.0 if part.is_empty() else HardwareCatalog.get_part_strength_pct(cat_k, part)
	v.add_child(_make_bar(strength, UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_GREEN, 5))

	btn.pressed.connect(func():
		_selected_cat = cat_k
		_selected_filter = "Alle"
		_parts_scroll_v = 0
		SfxManager.play("click", -12.0, 1.15)
		_refresh()
	)
	return btn


func _build_part_picker(parent: VBoxContainer, comps: Dictionary, state: String) -> void:
	var cm: Dictionary = HardwareCatalog.CATEGORY_META[_selected_cat]

	var flt_row := HBoxContainer.new()
	flt_row.add_theme_constant_override("separation", 5)
	parent.add_child(flt_row)

	var head := _section_label(tr("%s WÄHLEN") % tr(str(cm["short"])).to_upper())
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.custom_minimum_size = Vector2(110, 0)
	flt_row.add_child(head)

	var flts: Array = HardwareCatalog.CATEGORY_FILTERS.get(_selected_cat, ["Alle"])
	for flt_name in flts:
		var fn_str := str(flt_name)
		var fsel := (_selected_filter == fn_str)
		var fb := _make_btn(tr(fn_str), "flt_%s" % fn_str, Vector2(0, 26))
		fb.add_theme_font_size_override("font_size", 11)
		_style_btn(fb, Color(0.17, 0.21, 0.25) if fsel else Color(0.115, 0.12, 0.13), UIStyle.COL_BLUE if fsel else UIStyle.COL_BORDER)
		fb.pressed.connect(func():
			_selected_filter = fn_str
			_parts_scroll_v = 0
			SfxManager.play("click", -13.0, 1.1)
			_refresh()
		)
		flt_row.add_child(fb)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flt_row.add_child(sp)

	var stock_btn := _make_btn(tr("Nur Lager: AN") if _only_in_stock else tr("Nur Lager"), "flt_stock", Vector2(118, 26))
	stock_btn.add_theme_font_size_override("font_size", 11)
	_style_btn(stock_btn, Color(0.16, 0.27, 0.16) if _only_in_stock else Color(0.115, 0.12, 0.13), UIStyle.COL_GREEN if _only_in_stock else UIStyle.COL_BORDER)
	stock_btn.pressed.connect(func():
		_only_in_stock = not _only_in_stock
		_parts_scroll_v = 0
		SfxManager.play("click", -12.0, 1.1)
		_refresh()
	)
	flt_row.add_child(stock_btn)

	_parts_scroll = ScrollContainer.new()
	_parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Aus: beim Neuaufbau bekommt ein Knopf den Fokus, sonst springt die Liste dorthin.
	_parts_scroll.follow_focus = false
	parent.add_child(_parts_scroll)
	var plist := VBoxContainer.new()
	plist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plist.add_theme_constant_override("separation", 6)
	_parts_scroll.add_child(plist)

	var cur_pid := str(comps.get(_selected_cat, HardwareCatalog.DEFAULT_PARTS[_selected_cat]))
	var sorted_parts: Array = HardwareCatalog.get_category_parts(_selected_cat).duplicate()
	sorted_parts.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
	var shown := 0
	for p in sorted_parts:
		var pd: Dictionary = p
		var pid := str(pd["id"])
		if not HardwareCatalog.matches_filter(_selected_cat, pd, _selected_filter):
			continue
		var installed := (pid == cur_pid)
		var is_default := HardwareCatalog.is_stock_default_part(pid)
		var stock := GameState.get_part_stock(pid)
		if _only_in_stock and not installed and stock <= 0 and not is_default:
			continue
		shown += 1
		plist.add_child(_make_part_row(pd, installed, is_default, stock, state))

	if shown == 0:
		var nl := _make_label(tr("Keine passenden Bauteile. Ändere den Filter oder schalte „Nur Lager“ aus. Fehlende Teile kaufst du hier direkt mit „Kaufen & einbauen“."), 12, UIStyle.COL_TEXT_SUB)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plist.add_child(nl)

	if _parts_scroll_v > 0:
		var sc := _parts_scroll
		var v := _parts_scroll_v
		var restore := func() -> void:
			if is_instance_valid(sc):
				sc.scroll_vertical = v
		get_tree().process_frame.connect(restore, CONNECT_ONE_SHOT)


func _make_part_row(pd: Dictionary, installed: bool, is_default: bool, stock: int, state: String) -> PanelContainer:
	var pid := str(pd["id"])
	var pcard := PanelContainer.new()
	var pbg := Color(0.11, 0.16, 0.11, 0.96) if installed else (Color(0.13, 0.145, 0.16, 0.96) if stock > 0 else UIStyle.COL_BG_CARD)
	var pbd := UIStyle.COL_GREEN if installed else (UIStyle.COL_GOLD_TEXT if stock > 0 else UIStyle.COL_BORDER)
	pcard.add_theme_stylebox_override("panel", UIStyle.make_panel(pbg, pbd, 6, 1, 10, 7))

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	pcard.add_child(prow)

	if PartModels.has_product(pid):
		var tb := TextureButton.new()
		tb.texture_normal = PartThumbs.get_texture(pid)
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(64, 46)
		tb.focus_mode = Control.FOCUS_NONE
		tb.tooltip_text = tr("In die Hand nehmen")
		tb.pressed.connect(func(): PartViewer.open(self, [pid]))
		prow.add_child(tb)

	var tag := str(pd.get("tag", ""))
	if not tag.is_empty():
		var chip := _make_chip(tr(tag), UIStyle.COL_GREEN if installed else UIStyle.COL_BLUE)
		chip.custom_minimum_size = Vector2(62, 0)
		prow.add_child(chip)

	var pinfo := VBoxContainer.new()
	pinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pinfo.add_theme_constant_override("separation", 3)
	prow.add_child(pinfo)

	var stock_tag := ("   •   " + tr("Im Lager: %d×") % stock) if stock > 0 else ""
	pinfo.add_child(_make_label("%s%s" % [str(pd["name"]), stock_tag], 13,
		UIStyle.COL_GREEN if installed else (UIStyle.COL_GOLD_TEXT if stock > 0 else UIStyle.COL_TEXT_MAIN)))

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	pinfo.add_child(bar_row)
	var pbar := _make_bar(HardwareCatalog.get_part_strength_pct(_selected_cat, pd), UIStyle.COL_GREEN if installed else UIStyle.COL_GOLD_TEXT, 6)
	pbar.size_flags_horizontal = Control.SIZE_FILL
	pbar.custom_minimum_size = Vector2(90, 6)
	bar_row.add_child(pbar)
	bar_row.add_child(_make_label(_format_catalog_part_specs(_selected_cat, pd), 11, UIStyle.COL_TEXT_SUB))

	var ibtn := _make_btn("", "part_%s" % pid, Vector2(170, 34))
	ibtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if installed:
		ibtn.text = tr("VERBAUT")
		ibtn.disabled = true
		_style_btn(ibtn, Color(0.16, 0.26, 0.16), UIStyle.COL_GREEN)
	elif stock > 0 or is_default:
		ibtn.text = tr("Einbauen (Lager)") if stock > 0 else tr("Basis einbauen")
		ibtn.disabled = (state == "burning")
		_style_btn(ibtn, Color(0.18, 0.30, 0.18), UIStyle.COL_GREEN)
		var cap_cat := _selected_cat
		ibtn.pressed.connect(func():
			GameState.request_install_component(_entity_id, _selected_slot, cap_cat, pid)
		)
	elif not GameState.is_part_unlocked(pd):
		ibtn.text = tr("🔒 Ab Firmenstufe %d") % GameState.get_part_required_level(pd)
		ibtn.disabled = true
		_style_btn(ibtn, Color(0.13, 0.13, 0.14), UIStyle.COL_BORDER)
	else:
		var buy_cost := int(pd["cost"])
		ibtn.text = tr("Kaufen & einbauen ($%d)") % buy_cost
		ibtn.disabled = (state == "burning") or GameState.money < float(buy_cost)
		_style_btn(ibtn, Color(0.20, 0.26, 0.12), UIStyle.COL_GOLD_TEXT)
		var buy_cat := _selected_cat
		ibtn.pressed.connect(func():
			GameState.request_buy_install_component(_entity_id, _selected_slot, buy_cat, pid)
		)
	prow.add_child(ibtn)
	return pcard


func _build_side_column(side: VBoxContainer, slot: Dictionary, itype: String) -> void:
	side.add_child(_section_label("3D-VORSCHAU"))
	if itype == "" and _cfg_open and not _cfg_mb.is_empty():
		_preview_frame.custom_minimum_size = Vector2(0, PREVIEW_H)
		_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.add_child(_preview_frame)
		if _preview_fullscreen:
			_move_preview_to_fullscreen()
		_update_3d_preview(_cfg_mb, _cfg_comps, "", false, "")
		var cfg_hint := Label.new()
		cfg_hint.text = tr("Live-Vorschau deiner Konfiguration. Lege sie in den Warenkorb und baue sie an der Werkbank zusammen.")
		cfg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cfg_hint.add_theme_font_size_override("font_size", 11)
		cfg_hint.add_theme_color_override("font_color", UIStyle.COL_TEXT_SUB)
		side.add_child(cfg_hint)
		return
	if itype != "":
		_preview_frame.custom_minimum_size = Vector2(0, PREVIEW_H)
		_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.add_child(_preview_frame)
		if _preview_fullscreen:
			_move_preview_to_fullscreen()
		var slot_state := str(slot.get("state", ""))
		var faulty_cat := str(slot.get("faulty_part", "")) if slot_state == "crashed" else ""
		var broken_visual_cat := GameState.get_visible_fault(slot)
		if faulty_cat == "" and (slot_state == "crashed" or slot_state == "burning"):
			broken_visual_cat = "mainboard"
		# Vor der Diagnose bleibt das rote Highlight aus, aber das Bauteil sieht im 3D-Menü sichtbar kaputt aus!
		var reveal_fault := not GameState.is_slot_awaiting_diagnosis(slot)
		_update_3d_preview(itype, slot.get("components", {}) as Dictionary, faulty_cat, reveal_fault, broken_visual_cat)
		if GameState.is_slot_awaiting_diagnosis(slot):
			var hint := Label.new()
			hint.text = tr("Störung ohne bekannte Ursache: Fahre mit der Maus über die Bauteile, um das defekte Teil zu finden — oder zieh den Server heraus und miss ihn an der Werkbank durch.")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_size_override("font_size", 12)
			hint.add_theme_color_override("font_color", UIStyle.COL_AMBER)
			side.add_child(hint)
		elif faulty_cat != "":
			var diag := GameState.get_fault_diagnosis_info(slot)
			var found := Label.new()
			found.text = tr("[%s] %s (%s)\nEmpfohlen: %s — an der Werkbank ordentlich reparieren. Hier am Rack geht nur eine Notreparatur (Bauqualität höchstens 70 %%).") % [
				str(diag.get("code", "ERR")),
				GameState.get_component_label(faulty_cat),
				str(diag.get("cause", "")),
				str(diag.get("tool", "Wartungs-Kit")),
			]
			found.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			found.add_theme_font_size_override("font_size", 11.5)
			found.add_theme_color_override("font_color", UIStyle.COL_RED)
			side.add_child(found)
		elif str(slot.get("state", "")) == "crashed":
			var crashed_l := Label.new()
			crashed_l.text = tr("Ausgefallen: Klicke in der 3D-Vorschau auf ein Bauteil, um den Server zu reparieren.")
			crashed_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			crashed_l.add_theme_font_size_override("font_size", 12)
			crashed_l.add_theme_color_override("font_color", UIStyle.COL_AMBER)
			side.add_child(crashed_l)
		elif str(slot.get("state", "")) == "ok":
			var dust_pct := int(roundf(float(slot.get("dust_level", 0.0))))
			var th_pct := int(roundf(float(slot.get("thermal_health", 100.0))))
			var m_row := HBoxContainer.new()
			m_row.add_theme_constant_override("separation", 8)
			side.add_child(m_row)
			var ml := Label.new()
			ml.text = tr("Staub: %d %%  •  Wärmeleitpaste/Lüfter: %d %%") % [dust_pct, th_pct]
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ml.add_theme_font_size_override("font_size", 11.5)
			ml.add_theme_color_override("font_color", UIStyle.COL_AMBER if (dust_pct >= 55 or th_pct <= 45) else UIStyle.COL_TEXT_SUB)
			m_row.add_child(ml)
			var bq := GameState.get_build_quality(slot)
			var ql := Label.new()
			ql.text = tr("Bauqualität: %d %%") % bq
			ql.tooltip_text = tr("Unter 100 % läuft der Server wärmer und fällt öfter aus. An der Werkbank mit [F] überholen.")
			ql.mouse_filter = Control.MOUSE_FILTER_PASS
			ql.add_theme_font_size_override("font_size", 11.5)
			ql.add_theme_color_override("font_color", UIStyle.COL_GREEN if bq >= 90 else (UIStyle.COL_AMBER if bq >= 60 else UIStyle.COL_RED))
			m_row.add_child(ql)
			if GameState.is_slot_maintainable(slot):
				var mbtn := Button.new()
				mbtn.text = tr("🧹 Warten (%d Kits)") % GameState.maint_kits
				mbtn.custom_minimum_size = Vector2(148, 26)
				mbtn.pressed.connect(func():
					GameState.request_maintain_slot(_entity_id, _selected_slot)
				)
				m_row.add_child(mbtn)
	else:
		_update_3d_preview("", {})
		var ph := PanelContainer.new()
		ph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ph.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.08, 0.095, 0.115, 0.98), UIStyle.COL_BORDER, 8, 1, 14, 14))
		side.add_child(ph)
		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 8)
		ph.add_child(cv)
		var ic := _make_icon("info", UIStyle.COL_TEXT_SUB, 30)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ic)
		var l1 := _make_label(tr("Kein Server in U%d") % (_selected_slot + 1), 14, UIStyle.COL_TEXT_MAIN, true)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(l1)
		var l2 := _make_label(tr("Wähle links ein Mainboard,\ndann erscheint es hier in 3D."), 12, UIStyle.COL_TEXT_SUB)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(l2)
		return

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 6, 1, 12, 10))
	side.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)
	var st := GameState.get_slot_stats(slot)
	v.add_child(_section_label(tr("EINSCHUB U%d") % (_selected_slot + 1)))
	var watts := int(st["watts"])
	if GameState.is_slot_upgradeable(itype):
		var psu_max := maxi(int(st["psu_max_watts"]), 1)
		var pct := float(watts) / float(psu_max) * 100.0
		_add_load_bar_row(v, "Netzteil", "%d / %d W" % [watts, psu_max], pct, 70.0, 90.0)
	else:
		_add_kv_line(v, "Stromverbrauch", "%d W" % watts)
	_add_kv_line(v, "Modulwert", "$%d" % int(roundf(float(st["total_value"]) * GameState.SELL_REFUND_RATIO)))


# ------------------------------------------------------------------------------
# Reiter VERMIETUNG
# ------------------------------------------------------------------------------
func _render_rack_rental(rack: Dictionary, hw: Dictionary) -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	_body_host.add_child(split)

	var lscroll := ScrollContainer.new()
	lscroll.custom_minimum_size = Vector2(340, 0)
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(lscroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	lscroll.add_child(left)

	var hw_card := PanelContainer.new()
	hw_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 6, 1, 14, 12))
	left.add_child(hw_card)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hw_card.add_child(hv)
	hv.add_child(_section_label("HARDWARE IM RACK"))
	_add_kv_line(hv, "Aktive Server", tr("%d / %d online") % [int(hw["active_servers"]), int(hw["total_servers"])])
	_add_kv_line(hv, "CPU-Leistung", tr("%d Pkt.") % int(hw["cpu_score"]))
	_add_kv_line(hv, "Arbeitsspeicher", "%d GB RAM" % int(hw["ram_gb"]))
	_add_kv_line(hv, "Grafik / VRAM", tr("%d Pkt. (%d GB)") % [int(hw["gpu_score"]), int(hw["vram_gb"])])
	_add_kv_line(hv, "Speicherplatz", "%.1f TB" % float(hw["storage_tb"]))
	_add_kv_line(hv, "Haus-Router", HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps))
	if bool(hw.get("psu_overloaded", false)):
		var pw := _make_label(tr("Mindestens ein Netzteil ist zu schwach für seine Bauteile."), 12, UIStyle.COL_RED)
		pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(pw)

	var r_rent := str(rack.get("rental_type", "none"))
	var load_card := PanelContainer.new()
	left.add_child(load_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 7)
	load_card.add_child(lv)
	if r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[r_rent]
		var m: Dictionary = rack.get("metrics", {})
		var bn := str(m.get("bottleneck", "ok"))
		load_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_RED if bn != "ok" else UIStyle.COL_GREEN, 8, 1, 14, 12))
		lv.add_child(_section_label("LIVE-AUSLASTUNG"))
		var lh := _make_label("%s  —  %s" % [tr(str(prof["short"])).to_upper(), str(rack.get("rental_customer", ""))], 14, UIStyle.COL_TEXT_MAIN, true)
		lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(lh)
		# Geliehene Hardware über Cluster-Kabel anzeigen.
		var cb: Dictionary = m["cluster_borrowed"] if m.get("cluster_borrowed") is Dictionary else {}
		if not cb.is_empty():
			var parts := PackedStringArray()
			if cb.has("ram_gb"):
				parts.append(tr("%.1f GB RAM") % float(cb["ram_gb"]))
			if cb.has("cpu_score"):
				parts.append(tr("%.0f CPU") % float(cb["cpu_score"]))
			if cb.has("gpu_score"):
				parts.append(tr("%.0f GPU") % float(cb["gpu_score"]))
			if cb.has("storage_tb"):
				parts.append(tr("%.2f TB Speicher") % float(cb["storage_tb"]))
			var cl := _make_label(tr("🔗 Vom Cluster geliehen: %s") % ", ".join(parts), 12, UIStyle.COL_ACCENT, false)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(cl)
		# Live-Feedback pro Dienst: Nutzer, Trend und Obergrenze beim aktuellen Ruf.
		var svc_list: Array = rack.get("services", [])
		for s in svc_list:
			if not (s is Dictionary):
				continue
			var sd: Dictionary = s
			var stype := str(sd.get("type", ""))
			if not HardwareCatalog.RENTAL_PROFILES.has(stype):
				continue
			var sp: Dictionary = HardwareCatalog.RENTAL_PROFILES[stype]
			var trend := float(sd.get("trend", 0.0))
			var trend_col := UIStyle.COL_GREEN if trend > 0.3 else (UIStyle.COL_RED if trend < -0.3 else UIStyle.COL_TEXT_SUB)
			var sl := _make_label(tr("%s %s – %s: %d Nutzer  (%+.1f/min)") % [
				str(sp.get("icon", "")), tr(str(sp.get("short", stype))), str(sd.get("customer", "")),
				int(roundf(float(sd.get("users", 0.0)))), trend,
			], 12, trend_col)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(sl)
		var rep_l := _make_label(tr("Ruf: %s (%.0f/100). Höherer Ruf bringt mehr und schneller Kunden.") % [
			tr(GameState.get_reputation_label()), GameState.reputation,
		], 11, UIStyle.COL_GOLD_TEXT)
		rep_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(rep_l)
		_add_load_bar_row(lv, "RAM", "%.1f / %.0f GB" % [float(m.get("ram_used_gb", 0.0)), float(m.get("ram_total_gb", 0.0))], float(m.get("ram_pct", 0.0)))
		_add_load_bar_row(lv, "CPU", tr("%.0f%% Last") % float(m.get("cpu_pct", 0.0)), float(m.get("cpu_pct", 0.0)))
		_add_load_bar_row(lv, "Speicher", "%.2f / %.1f TB" % [float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0))], float(m.get("storage_pct", 0.0)))
		if float(prof["gpu_per_user"]) > 0.001:
			_add_load_bar_row(lv, "GPU", tr("%.0f%% Last") % float(m.get("gpu_pct", 0.0)), float(m.get("gpu_pct", 0.0)))
		_add_load_bar_row(lv, "Uplink", HardwareCatalog.format_speed_mbps(float(m.get("net_used_mbps", 0.0))), float(m.get("net_pct", 0.0)))
	else:
		load_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 8, 1, 14, 12))
		lv.add_child(_section_label("LIVE-AUSLASTUNG"))
		var nr := _make_label(tr("Dieses Rack ist nicht vermietet. Wähle rechts einen Dienst, danach siehst du hier RAM, CPU, Speicher und Uplink live."), 12, UIStyle.COL_TEXT_SUB)
		nr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(nr)

	var rscroll := ScrollContainer.new()
	rscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rscroll.follow_focus = true
	split.add_child(rscroll)
	_rental_scroll = rscroll
	if _rental_scroll_v > 0.0:
		rscroll.set_deferred("scroll_vertical", roundi(_rental_scroll_v))
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 8)
	rscroll.add_child(rv)
	rv.add_child(_section_label("DIENST WÄHLEN"))
	var pick := _make_label(tr("Schätze selbst ein, ob RAM, CPU, Speicher und Router für den Dienst reichen."), 12, UIStyle.COL_TEXT_SUB)
	pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(pick)
	var active_types: Array = []
	for s in rack.get("services", []):
		if s is Dictionary:
			active_types.append(str((s as Dictionary).get("type", "")))
	var cnt := _make_label(tr("Aktive Dienste: %d / %d   •   Ruf: %s") % [
		active_types.size(), GameState.MAX_SERVICES_PER_RACK, tr(GameState.get_reputation_label()),
	], 12, UIStyle.COL_GOLD_TEXT, true)
	rv.add_child(cnt)
	# "Alle beenden" oben, danach die Dienste nach Kategorie gruppiert.
	rv.add_child(_make_rental_button("none", active_types))
	for cat in HardwareCatalog.RENTAL_CATEGORIES:
		var cd: Dictionary = cat
		rv.add_child(_section_label(tr(str(cd.get("label", ""))).to_upper()))
		for key in cd.get("keys", []):
			if HardwareCatalog.RENTAL_PROFILES.has(str(key)):
				rv.add_child(_make_rental_button(str(key), active_types))


func _make_rental_button(k: String, active: Array) -> Button:
	var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[k]
	var is_cur := active.is_empty() if k == "none" else active.has(k)
	var full := active.size() >= GameState.MAX_SERVICES_PER_RACK
	var btn := _make_btn("", "rent_%s" % k, Vector2(0, 76))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn, Color(0.11, 0.19, 0.14, 0.96) if is_cur else UIStyle.COL_BG_CARD, UIStyle.COL_GREEN if is_cur else UIStyle.COL_BORDER)
	var m := _btn_content(btn, 12, 8)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var iv := VBoxContainer.new()
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_theme_constant_override("separation", 2)
	row.add_child(iv)
	var pay_s := ""
	if k != "none":
		pay_s = "   •   " + tr("$%.2f pro Nutzer") % float(prof.get("pay_per_user", 0.0))
	iv.add_child(_make_label(tr(str(prof["label"])) + pay_s, 14, UIStyle.COL_GREEN if is_cur else UIStyle.COL_TEXT_MAIN, true))
	var dl := _make_label(tr(str(prof.get("desc", ""))), 11, UIStyle.COL_TEXT_SUB)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.max_lines_visible = 2
	iv.add_child(dl)

	var act_txt := tr("AKTIV – Beenden")
	var act_col := UIStyle.COL_GREEN
	var clickable := true
	if k == "none":
		act_txt = tr("Nicht vermietet") if is_cur else tr("Alle beenden")
		act_col = UIStyle.COL_TEXT_SUB if is_cur else UIStyle.COL_GOLD_TEXT
		clickable = not is_cur
	elif not is_cur:
		if full:
			act_txt = tr("Rack voll")
			act_col = UIStyle.COL_TEXT_SUB
			clickable = false
		else:
			act_txt = tr("+ Vermieten")
			act_col = UIStyle.COL_GOLD_TEXT
	var al := _make_label(act_txt, 12, act_col, true)
	al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(al)

	if clickable:
		btn.pressed.connect(func():
			SfxManager.play("click", -10.0, 1.1)
			GameState.request_set_rack_rental(_entity_id, k)
		)
	return btn


# ==============================================================================
# ROUTER
# ==============================================================================
func _render_router_view() -> void:
	_begin_render()
	_tab_row.visible = false
	_update_3d_preview("", {})

	var tiers_n := GameState.ROUTER_TIERS.size()
	var rt := clampi(GameState.router_tier, 0, tiers_n - 1)
	var cur: Dictionary = GameState.ROUTER_TIERS[rt]
	var used_ports := GameState.count_cables_on("network", GameState.WALL_ROUTER_ID)
	var max_ports := maxi(int(cur["ports"]), 1)
	var max_mbps := maxf(float(cur["max_mbps"]), 0.001)
	var used_mbps := float(GameState.used_bandwidth_mbps)
	var bottleneck := used_mbps > max_mbps
	var bw_ratio := used_mbps / max_mbps

	_title_lbl.text = tr("INTERNET-ROUTER  —  %s") % tr(str(cur["label"]))
	_subtitle_lbl.text = tr("Guthaben: $%.0f   •   Stufe %d / %d") % [GameState.money, rt + 1, tiers_n]
	_set_status(tr("ENGPASS") if bottleneck else tr("ONLINE"), UIStyle.COL_RED if bottleneck else UIStyle.COL_GREEN)

	_add_kpi("GESCHWINDIGKEIT", str(cur["speed"]), tr("Stufe %d / %d") % [rt + 1, tiers_n], UIStyle.COL_GOLD_TEXT, float(rt + 1) / float(maxi(tiers_n, 1)))
	_add_kpi("AUSLASTUNG", HardwareCatalog.format_speed_mbps(used_mbps), tr("von %s") % str(cur["speed"]),
		UIStyle.COL_RED if bottleneck else _load_color(bw_ratio * 100.0), bw_ratio)
	_add_kpi("LAN-PORTS", tr("%d / %d belegt") % [used_ports, max_ports], "",
		UIStyle.COL_AMBER if used_ports >= max_ports else UIStyle.COL_BLUE, float(used_ports) / float(max_ports))
	_add_kpi("DDOS-SCHUTZ", "+%.0f%%" % ((float(cur["ddos_mult"]) - 1.0) * 100.0), "", UIStyle.COL_GREEN, -1.0, "check")

	var has_next := rt + 1 < tiers_n
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_GOLD_TEXT if has_next else UIStyle.COL_GREEN, 8, 1, 18, 16))
	_body_host.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	if not has_next:
		v.add_child(_section_label("AUSBAUSTUFE"))
		v.add_child(_make_label(tr("Höchste Stufe erreicht: 100-Gbit/s-Glasfaser-Anbindung"), 16, UIStyle.COL_GREEN, true))
		return

	var nxt: Dictionary = GameState.ROUTER_TIERS[rt + 1]
	var cost := int(nxt["cost"])
	v.add_child(_section_label("NÄCHSTE STUFE"))
	v.add_child(_make_label(tr(str(nxt["label"])), 18, UIStyle.COL_GOLD_TEXT, true))

	var cmp := GridContainer.new()
	cmp.columns = 3
	cmp.add_theme_constant_override("h_separation", 24)
	cmp.add_theme_constant_override("v_separation", 6)
	v.add_child(cmp)
	_add_compare_row(cmp, "Geschwindigkeit", str(cur["speed"]), str(nxt["speed"]))
	_add_compare_row(cmp, "LAN-Ports", str(int(cur["ports"])), str(int(nxt["ports"])))
	_add_compare_row(cmp, "DDoS-Schutz", "+%.0f%%" % ((float(cur["ddos_mult"]) - 1.0) * 100.0), "+%.0f%%" % ((float(nxt["ddos_mult"]) - 1.0) * 100.0))

	var btn := _make_btn(tr("Auf %s upgraden  ($%d)") % [str(nxt["speed"]), cost], "primary", Vector2(0, 46))
	btn.disabled = GameState.money < float(cost)
	_style_btn(btn, Color(0.76, 0.50, 0.12), UIStyle.COL_GOLD_TEXT)
	btn.add_theme_font_override("font", _display_font)
	btn.pressed.connect(func(): GameState.request_upgrade_router())
	v.add_child(btn)
	if btn.disabled:
		v.add_child(_make_label(tr("Dir fehlen noch $%.0f.") % (float(cost) - GameState.money), 12, UIStyle.COL_RED))


func _add_compare_row(grid: GridContainer, k: String, cur_txt: String, next_txt: String) -> void:
	grid.add_child(_make_label(tr(k), 13, UIStyle.COL_TEXT_SUB))
	grid.add_child(_make_label(cur_txt, 13, UIStyle.COL_TEXT_MAIN))
	grid.add_child(_make_label("→  " + next_txt, 13, UIStyle.COL_GOLD_TEXT, true))


# ==============================================================================
# KÜHLER / USV / ROLLWAGEN
# ==============================================================================
func _render_device_view(kind: String) -> void:
	_begin_render()
	_tab_row.visible = false
	_update_3d_preview("", {})

	var note := ""
	match kind:
		"cooler":
			var c: Dictionary = GameState.coolers[_entity_id]
			var ctype := str(c.get("cooler_type", "cooler"))
			var cat: Dictionary = GameState.ITEM_CATALOG[ctype]
			var on := bool(c["powered"])
			_title_lbl.text = "%s  —  %s" % [_entity_id.to_upper(), tr(str(cat["name"]))]
			if ctype == GameState.INDOOR_UNIT_TYPE:
				_set_status(tr("KÜHLT") if on else tr("AUSSENGERÄT AUS"), UIStyle.COL_GREEN if on else UIStyle.COL_RED)
				_add_kpi("KÜHLLEISTUNG", tr("über Außengerät"), "", UIStyle.COL_BLUE, -1.0, "temp")
				_add_kpi("ANSCHLUSS", tr("Kein Kabel nötig"), "", UIStyle.COL_GREEN, -1.0, "check")
				if not on:
					note = tr("Kein Außengerät mit Strom: eine Goldis-Wärmepumpe auf den Rasen rechts vom Garagentor stellen und seitlich verkabeln.")
			elif GameState.is_floor_cooler_type(ctype):
				_set_status(tr("AKTIV") if on else tr("KEIN STROM"), UIStyle.COL_GREEN if on else UIStyle.COL_RED)
				_add_kpi("KÜHLLEISTUNG", "%.0f °C" % float(cat["heat"]), "", UIStyle.COL_BLUE, -1.0, "temp")
				_add_kpi("STROMVERBRAUCH", "%d W" % int(cat["watts"]), "", UIStyle.COL_AMBER, -1.0, "power")
				_add_kpi("NAHE RACKS", "-%.0f °C" % float(cat.get("relief", 0.0)), tr("bis %.1f m") % float(cat.get("relief_radius", 0.0)), UIStyle.COL_BLUE, -1.0, "temp")
				if not on:
					note = tr("Kein Strom: die gelbe Buchse oben am Gerät verkabeln.")
			else:
				var has_indoor := GameState.has_indoor_unit()
				_set_status(tr("AKTIV") if on else tr("KEIN STROM"), UIStyle.COL_GREEN if on else UIStyle.COL_RED)
				_add_kpi("KÜHLLEISTUNG", "%.0f °C" % float(cat["heat"]), "", UIStyle.COL_BLUE, -1.0, "temp")
				_add_kpi("STROMVERBRAUCH", "%d W" % int(cat["watts"]), "", UIStyle.COL_AMBER, -1.0, "power")
				_add_kpi("ANSCHLUSS", tr("Strom OK") if on else tr("Strom FEHLT"), "",
					UIStyle.COL_GREEN if on else UIStyle.COL_RED, -1.0, "check" if on else "warn")
				_add_kpi("INNENGERÄT", tr("Vorhanden") if has_indoor else tr("FEHLT"), "",
					UIStyle.COL_GREEN if has_indoor else UIStyle.COL_RED, -1.0, "check" if has_indoor else "warn")
				if not on:
					note = tr("Kein Strom: die gelbe Buchse an der rechten Seite verkabeln.")
				elif not has_indoor:
					note = tr("Ohne Goldis Innengerät kommt keine Kälte in den Raum. Innengerät im Shop kaufen und an eine Innenwand hängen.")
		"ups":
			var u: Dictionary = GameState.ups_units[_entity_id]
			var charge := float(u.get("charge", 0.0))
			var dis := bool(u.get("discharging", false))
			var conn := bool(u.get("connected", false))
			_title_lbl.text = "%s  —  %s" % [_entity_id.to_upper(), tr(str(GameState.ITEM_CATALOG[GameState.get_ups_type(u)]["name"]))]
			if bool(u.get("tripped", false)):
				_set_status(tr("ÜBERLASTET"), UIStyle.COL_RED)
			elif dis:
				_set_status(tr("NOTSTROM"), UIStyle.COL_AMBER)
			elif conn:
				_set_status(tr("VERBUNDEN"), UIStyle.COL_GREEN)
			else:
				_set_status(tr("NICHT VERKABELT"), UIStyle.COL_AMBER)
			var ch_col := UIStyle.COL_RED if charge < 20.0 else (UIStyle.COL_AMBER if charge < 50.0 else UIStyle.COL_GREEN)
			_add_kpi("LADESTAND", "%.0f %%" % charge, "", ch_col, charge / 100.0)
			_add_kpi("BETRIEB", tr("Entlädt") if dis else tr("Bereitschaft"), tr("Reicht ca. %d Min.") % GameState.get_ups_runtime_minutes(), UIStyle.COL_AMBER if dis else UIStyle.COL_BLUE, -1.0, "power")
			var uspec := GameState.get_ups_spec(u)
			var uhealth := GameState.get_ups_health(u)
			_add_kpi("KAPAZITÄT", "%d / %d Wh" % [int(GameState.get_ups_stored_wh(u)), int(GameState.get_ups_capacity(u))], tr("bis %d W Abgabe") % int(uspec["out"]), UIStyle.COL_BLUE, -1.0, "power")
			_add_kpi("AKKU-ZUSTAND", "%.0f %%" % uhealth, tr("sinkt mit jeder Entladung"), UIStyle.COL_RED if uhealth < 55.0 else (UIStyle.COL_AMBER if uhealth < 80.0 else UIStyle.COL_GREEN), uhealth / 100.0)
			note = tr("Übernimmt bei Blackout sofort unterbrechungsfrei die Stromversorgung. Ist die Last höher als die Abgabe aller Geräte, schalten sie ab.")
		"cart":
			var cart: Dictionary = GameState.carts[_entity_id]
			var items: Array = cart.get("items", [])
			var max_i := maxi(int(GameState.CART_MAX_ITEMS), 1)
			_title_lbl.text = tr("%s  —  Schwerlast-Rollwagen") % _entity_id.to_upper()
			_set_status(tr("BEREIT"), UIStyle.COL_BLUE)
			_add_kpi("BELADUNG", tr("%d / %d Pakete") % [items.size(), max_i], "",
				UIStyle.COL_AMBER if items.size() >= max_i else UIStyle.COL_BLUE, float(items.size()) / float(max_i))
			note = tr("Mit [E] schieben und bis zu %d Pakete gleichzeitig durch das Gebäude transportieren.") % max_i
		"decor":
			_title_lbl.text = tr(GameState.get_decor_name(_entity_id))
			_set_status(tr("AUFGESTELLT"), UIStyle.COL_BLUE)
			var ctype_d := "power" if GameState.is_power_strip_decor(_entity_id) else ("network" if GameState.is_lan_strip_decor(_entity_id) else "")
			if ctype_d != "":
				var used_d := GameState.count_cables_on(ctype_d, _entity_id)
				var max_d := GameState.get_max_ports(ctype_d, _entity_id)
				_add_kpi("ANSCHLÜSSE", tr("%d / %d belegt") % [used_d, max_d], "", UIStyle.COL_AMBER if used_d >= max_d else UIStyle.COL_BLUE, float(used_d) / float(maxi(max_d, 1)))
				note = tr("Beim Umsetzen bleiben alle Kabel stecken.")
				var dd: Dictionary = GameState.decor_items[_entity_id]
				if bool(dd.get("tripped", false)):
					_set_status(tr("AUSGELÖST"), UIStyle.COL_RED)
				elif not GameState.is_strip_on(_entity_id):
					_set_status(tr("AUS"), UIStyle.COL_AMBER)
				else:
					_set_status(tr("EIN"), UIStyle.COL_GREEN)
				if not GameState.is_strip_fed(ctype_d, _entity_id):
					_set_status(tr("KEIN STROM") if ctype_d == "power" else tr("KEIN UPLINK"), UIStyle.COL_AMBER)
				if ctype_d == "power":
					var lim := GameState.get_strip_limit(_entity_id)
					var lw := GameState.get_strip_load(_entity_id)
					_add_kpi("STROMLAST", "%d / %d W" % [lw, lim], "", UIStyle.COL_RED if lw > lim else (UIStyle.COL_AMBER if float(lw) > float(lim) * 0.85 else UIStyle.COL_GREEN), float(lw) / float(maxi(lim, 1)))
					var cw := GameState.get_chain_load(_entity_id)
					var cl := StripRules.CHAIN_LIMIT_W
					_add_kpi("KETTE", tr("%d / %d W • %d Leisten") % [cw, cl, maxi(1, GameState.get_chain_length(_entity_id))], "", UIStyle.COL_RED if cw > cl else (UIStyle.COL_AMBER if float(cw) > float(cl) * 0.85 else UIStyle.COL_GREEN), float(cw) / float(cl))
					note = tr("Links weißer Eingang, rechts roter Ausgang zur nächsten Leiste. Oben nur Geräte. Jede Leiste trägt %d W, die ganze Kette am Abgang %d W.") % [lim, cl]
				else:
					var root := GameState.get_lan_chain_root(_entity_id)
					var mb := float(GameState.lan_chain_mbps.get(root, 0.0))
					var cap := GameState.lan_chain_cap()
					_add_kpi("KETTE", tr("%.0f / %.0f Mbit/s") % [mb, cap], "", UIStyle.COL_RED if mb > cap else UIStyle.COL_BLUE, mb / cap)
					note = tr("Links weißer Eingang (Uplink), rechts roter Ausgang zur nächsten LAN-Leiste. Alle Leisten der Kette teilen sich einen Uplink mit %.0f Mbit/s.") % cap
					if mb > cap:
						note += " " + tr("Überlastet: Die Racks dieser Kette laufen nur mit %d %% und verdienen entsprechend weniger. Eine zweite Kette direkt am Router entlastet.") % int(cap / mb * 100.0)
			else:
				var di: Dictionary = GameState.decor_items[_entity_id]
				var dtype := str(di.get("item_type", ""))
				note = tr(str((GameState.ITEM_CATALOG.get(dtype, {}) as Dictionary).get("desc", "")))
				if ShelfSpec.is_shelf(dtype):
					var used_s := 0
					var n_s := ShelfSpec.unit_count(dtype)
					for ui in n_s:
						if ShelfSpec.owner_of(di, ui) >= 0:
							used_s += 1
					_add_kpi("BELEGUNG", tr("%d / %d Plätze") % [used_s, n_s], "", UIStyle.COL_AMBER if used_s >= n_s else UIStyle.COL_BLUE, float(used_s) / float(maxi(1, n_s)))
					note += "\n" + tr("Umsetzen ist kostenlos. Eingelagerte Kisten bleiben im Regal.")
				elif dtype == "prop_dehumidifier":
					var tk := float(di.get("tank", 0.0))
					_add_kpi("TANK", "%d %%" % int(tk * 100.0), "", UIStyle.COL_RED if tk >= 1.0 else (UIStyle.COL_AMBER if tk > 0.8 else UIStyle.COL_BLUE), tk)
				elif dtype == "prop_tool_cart":
					var kc := DecorManager.kit_count(di)
					_add_kpi("KITS", "%d / %d" % [kc, DecorManager.TOOL_CART_SLOTS], "", UIStyle.COL_BLUE, float(kc) / float(DecorManager.TOOL_CART_SLOTS))
				elif dtype == "prop_cold_aisle_gate":
					_add_kpi("KALTGÄNGE", str(DecorManager.get_aisles().size()), "", UIStyle.COL_GREEN if not DecorManager.get_aisles().is_empty() else UIStyle.COL_AMBER, 0.0 if DecorManager.get_aisles().is_empty() else 1.0)

	var refund := GameState.get_device_sell_value(kind, _entity_id)
	_subtitle_lbl.text = tr("Guthaben: $%.0f   •   Restwert: $%d") % [GameState.money, refund]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 8, 1, 18, 16))
	_body_host.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(_section_label("AKTIONEN"))
	if not note.is_empty():
		var nl := _make_label(note, 14, UIStyle.COL_TEXT_MAIN)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nl)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)

	if kind == "ups":
		var uu: Dictionary = GameState.ups_units[_entity_id]
		var swap_cost := GameState.get_ups_swap_cost(uu)
		var swap_btn := _make_btn(tr("Akkus tauschen ($%d)") % swap_cost, "ups_swap", Vector2(0, 44))
		swap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(swap_btn, Color(0.14, 0.20, 0.16), UIStyle.COL_GREEN)
		swap_btn.disabled = GameState.get_ups_health(uu) > 95.0 or GameState.money < float(swap_cost) or bool(uu.get("discharging", false))
		swap_btn.pressed.connect(func():
			SfxManager.play("click", -8.0)
			GameState.request_swap_ups_cells(_entity_id))
		brow.add_child(swap_btn)

	if kind == "cooler" or kind == "ups":
		var pack_btn := _make_btn(tr("[E]  Abbauen und in die Hand nehmen"), "primary", Vector2(0, 44))
		pack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(pack_btn, Color(0.15, 0.19, 0.23), UIStyle.COL_BLUE)
		pack_btn.pressed.connect(func():
			GameState.request_pack_device(kind, _entity_id)
			close_requested.emit()
		)
		brow.add_child(pack_btn)

	if kind == "decor" and (GameState.is_power_strip_decor(_entity_id) or GameState.is_lan_strip_decor(_entity_id)):
		var sw_btn := _make_btn(tr("Ausschalten") if GameState.is_strip_on(_entity_id) else tr("Einschalten"), "strip_sw", Vector2(0, 44))
		sw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(sw_btn, Color(0.20, 0.17, 0.10), UIStyle.COL_AMBER)
		sw_btn.pressed.connect(func():
			GameState.request_toggle_strip(_entity_id)
			get_tree().create_timer(0.15).timeout.connect(_queue_refresh))
		brow.add_child(sw_btn)

	if kind == "decor":
		var mv_btn := _make_btn(tr("[E]  Umsetzen"), "primary", Vector2(0, 44))
		mv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(mv_btn, Color(0.15, 0.19, 0.23), UIStyle.COL_BLUE)
		mv_btn.pressed.connect(func(): relocate_rack_requested.emit(_entity_id))
		brow.add_child(mv_btn)

	var sell_btn := _make_btn("", "dev_sell", Vector2(0, 44))
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _confirm_sell_entity:
		sell_btn.text = tr("WIRKLICH VERKAUFEN? (+$%d)") % refund
		_style_btn(sell_btn, Color(0.60, 0.16, 0.14), UIStyle.COL_RED)
	else:
		sell_btn.text = tr("Verkaufen (+$%d)") % refund
		_style_btn(sell_btn, Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell_btn.pressed.connect(func():
		if not _confirm_sell_entity:
			_confirm_sell_entity = true
			SfxManager.play("click", -8.0, 0.9)
			_refresh()
		else:
			if kind == "decor":
				GameState.request_sell_decor(_entity_id)
			else:
				GameState.request_sell_device(kind, _entity_id)
			close_requested.emit()
	)
	brow.add_child(sell_btn)


## Ende der Ansichten. Ab hier: Bausteine, Bedienung und 3D-Vorschau.

# ==============================================================================
# BEDIENUNG MIT [E]
# ==============================================================================
var _close_btn: Button


func _set_pointer_mode(on: bool) -> void:
	if _pointer_mode == on:
		return
	_pointer_mode = on
	# Beim Zeigen mit der Maus soll die Liste nicht mitscrollen, bei Pfeiltasten schon.
	_apply_follow_focus(_body_host, not on)


func _apply_follow_focus(node: Node, on: bool) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is ScrollContainer:
			(c as ScrollContainer).follow_focus = on
		_apply_follow_focus(c, on)


func _all_buttons() -> Array:
	var arr: Array = []
	for b in _buttons:
		if is_instance_valid(b):
			arr.append(b)
	if is_instance_valid(_close_btn):
		arr.append(_close_btn)
	return arr


func _point_visible_in(ctrl: Control, p: Vector2) -> bool:
	if not ctrl.get_global_rect().has_point(p):
		return false
	var n: Node = ctrl.get_parent()
	while n != null and n != self:
		if n is ScrollContainer and not (n as Control).get_global_rect().has_point(p):
			return false
		n = n.get_parent()
	return true


func _button_under_pointer() -> Button:
	var mp := get_global_mouse_position()
	for b in _all_buttons():
		var btn := b as Button
		if btn != null and btn.is_visible_in_tree() and _point_visible_in(btn, mp):
			return btn
	return null


func _focus_under_pointer() -> void:
	if _preview_dragging or is_typing():
		return
	var btn := _button_under_pointer()
	if btn != null and not btn.has_focus():
		btn.grab_focus()


func _find_target_button() -> Button:
	if _pointer_mode:
		return _button_under_pointer()
	var fo := get_viewport().gui_get_focus_owner()
	if fo is Button and _all_buttons().has(fo):
		return fo as Button
	return null


func _button_by_key(key: String) -> Button:
	if key.is_empty():
		return null
	for b in _all_buttons():
		var btn := b as Button
		if btn != null and str(btn.get_meta("key", "")) == key and btn.is_visible_in_tree():
			return btn
	return null


func _first_focusable() -> Button:
	for b in _buttons:
		if not is_instance_valid(b):
			continue
		var btn := b as Button
		if btn != null and not btn.disabled and btn.is_visible_in_tree():
			return btn
	return _close_btn


func _ensure_focus() -> void:
	if is_typing():
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and _all_buttons().has(fo):
		return
	var btn := _button_by_key(_focus_key)
	if btn == null:
		btn = _first_focusable()
	if btn != null:
		btn.grab_focus()


func _restore_focus() -> void:
	# Mit Mausbedienung scrollt kein Container automatisch zum fokussierten Knopf.
	_apply_follow_focus(_body_host, not _pointer_mode and not MOUSE_CLICKS_ENABLED)
	call_deferred("_deferred_focus")
	_restore_scroll()


## Kennung der aktuellen Ansicht. Ändert sie sich (anderer Einschub, Reiter, Kategorie),
## beginnt die Liste wieder oben, sonst bleibt die Scroll-Position erhalten.
func _scroll_view_key() -> String:
	return "%s|%s|%d|%s|%s|%s|%s" % [str(_entity_id), str(_active_tab), _selected_slot,
		str(_selected_cat), str(_selected_filter), str(_mb_picker_open), _mb_cat]


## Setzt die Scroll-Position der Liste nach dem Neuaufbau wieder, sonst springt sie bei jedem
## Spiel-Tick nach oben. Einmal verzögert und einmal nach dem nächsten Frame, weil der
## ScrollContainer seine Höhe erst nach dem Layout kennt.
func _restore_scroll() -> void:
	var key := _scroll_view_key()
	var same_view := key == _scroll_key
	_scroll_key = key
	var sc := _parts_scroll
	var v := _parts_scroll_v if same_view else 0
	_parts_scroll_v = v
	if not is_instance_valid(sc) or v <= 0:
		return
	sc.set_deferred("scroll_vertical", v)
	await get_tree().process_frame
	if is_instance_valid(sc) and sc == _parts_scroll:
		sc.scroll_vertical = v


func _deferred_focus() -> void:
	if not visible:
		return
	if _pointer_mode or MOUSE_CLICKS_ENABLED:
		_focus_under_pointer()
		return
	var btn := _button_by_key(_focus_key)
	if btn == null:
		btn = _first_focusable()
	if btn != null and not btn.has_focus():
		btn.grab_focus()


# ==============================================================================
# BAUSTEINE
# ==============================================================================
## Schaltfläche im Rack-Menü. Mit MOUSE_CLICKS_ENABLED = true wird sie per Linksklick ausgelöst.
func _make_btn(txt: String, key: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.clip_contents = true
	if not MOUSE_CLICKS_ENABLED:
		b.button_mask = 0
	b.set_meta("key", key)
	b.focus_entered.connect(func(): _focus_key = key)
	_buttons.append(b)
	return b


func _make_focus_box() -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = UIStyle.COL_GOLD_TEXT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(UIStyle.BUTTON_RADIUS)
	focus.set_expand_margin_all(3.0)
	focus.shadow_color = Color(UIStyle.COL_ACCENT, 0.35)
	focus.shadow_size = 8
	return focus


func _style_btn(btn: Button, bg: Color, accent: Color) -> void:
	UIStyle.style_button(btn, bg, accent)
	btn.add_theme_stylebox_override("focus", _make_focus_box())


## Innenabstand für Schaltflächen mit eigenem Inhalt (Kacheln, Zeilen).
func _btn_content(btn: Button, pad_x: int, pad_y: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", pad_x)
	m.add_theme_constant_override("margin_right", pad_x)
	m.add_theme_constant_override("margin_top", pad_y)
	m.add_theme_constant_override("margin_bottom", pad_y)
	btn.add_child(m)
	return m


func _make_label(txt: String, font_size: int, col: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(l, font_size, col, _display_font if bold else null)
	return l


func _make_bar(pct: float, col: Color, h: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = clampf(pct, 0.0, 100.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, h)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIStyle.make_bar_styles(col)
	pb.add_theme_stylebox_override("background", st[0])
	pb.add_theme_stylebox_override("fill", st[1])
	return pb


func _make_icon(kind: String, col: Color, px: int) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func() -> void: UIStyle.draw_icon(ic, kind, Rect2(Vector2.ZERO, ic.size), col))
	return ic


## Ringanzeige: dünner Kreis, der beim Öffnen des Menüs auf den Wert hochläuft.
func _make_ring(ratio: float, col: Color) -> Control:
	var target := clampf(ratio, 0.0, 1.0)
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(RING_PX, RING_PX)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_meta("v", 0.0 if _animate_next else target)
	ring.draw.connect(func() -> void:
		var c := ring.size * 0.5
		var r := minf(ring.size.x, ring.size.y) * 0.5 - 3.0
		ring.draw_arc(c, r, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.08), 4.0, true)
		var cur_v := float(ring.get_meta("v", 0.0))
		if cur_v > 0.002:
			ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * cur_v, 48, col, 4.0, true)
		ring.draw_circle(c, 2.5, Color(col, 0.8))
	)
	if _animate_next and target > 0.0:
		var setter := func(x: float) -> void:
			ring.set_meta("v", x)
			ring.queue_redraw()
		var starter := func() -> void:
			var tw := ring.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_method(setter, 0.0, target, RING_ANIM_TIME)
		ring.ready.connect(starter, CONNECT_ONE_SHOT)
	return ring


## Kennzahl-Kachel oben: Farbleiste, Ring (ratio >= 0) oder Symbol, Titel, Wert, Zusatzzeile.
func _add_kpi(title: String, value_txt: String, sub_txt: String, col: Color, ratio: float, icon_kind: String = "") -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 6, 1, 12, 9)
	sb.shadow_size = 6
	card.add_theme_stylebox_override("panel", sb)
	_kpi_row.add_child(card)

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)

	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(3, 0)
	strip.color = col
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(strip)

	if ratio >= 0.0:
		h.add_child(_make_ring(ratio, col))
	else:
		h.add_child(_make_icon(icon_kind if not icon_kind.is_empty() else "info", col, 26))

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	v.add_child(_make_label(tr(title), 10, UIStyle.COL_TEXT_SUB, true))
	var vl := _make_label(value_txt, 15, col, true)
	vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(vl)
	if not sub_txt.is_empty():
		var sl := _make_label(sub_txt, 10, UIStyle.COL_TEXT_SUB)
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(sl)


func _add_tab(tab_id: String, label_txt: String) -> void:
	var btn := _make_btn(label_txt, "tab_%s" % tab_id, Vector2(0, 38))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	_style_tab(btn, _active_tab == tab_id)
	btn.pressed.connect(func():
		if _active_tab == tab_id:
			return
		_active_tab = tab_id
		_confirm_sell_module = false
		_parts_scroll_v = 0
		SfxManager.play("click", -12.0, 1.1)
		_refresh()
	)
	_tab_row.add_child(btn)


## Reiter: der aktive bekommt eine Amber-Unterkante und Amber-Schrift.
func _style_tab(btn: Button, sel: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(UIStyle.COL_ACCENT, 0.14) if sel else Color(0.095, 0.10, 0.11, 0.92)
	normal.border_color = UIStyle.COL_ACCENT if sel else UIStyle.COL_BORDER
	normal.set_border_width_all(1)
	normal.border_width_bottom = 3 if sel else 1
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.08)
	if not sel:
		hover.border_color = Color(UIStyle.COL_ACCENT, 0.55)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.15)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_stylebox_override("focus", _make_focus_box())
	var fc := UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_SUB
	btn.add_theme_color_override("font_color", fc)
	btn.add_theme_color_override("font_focus_color", UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_MAIN)
	btn.add_theme_color_override("font_pressed_color", UIStyle.COL_GOLD_TEXT)
	btn.add_theme_font_override("font", _display_font)


func _section_label(txt: String) -> Label:
	return _make_label(tr(txt), 11, UIStyle.COL_GOLD_TEXT, true)


## Kleines farbiges Etikett (z. B. "1U", "LEISTUNG 7", "+5 % EINNAHMEN").
func _make_chip(txt: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UIStyle.make_panel(Color(col, 0.16), Color(col, 0.55), 4, 1, 7, 2)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	var l := _make_label(txt, 10, col.lightened(0.15), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _add_kv_line(parent: VBoxContainer, k: String, v_txt: String) -> void:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var kl := _make_label(tr(k), 13, UIStyle.COL_TEXT_SUB)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(kl)
	r.add_child(_make_label(v_txt, 13, UIStyle.COL_TEXT_MAIN, true))
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(UIStyle.COL_BORDER, 0.35)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _add_load_bar_row(parent: VBoxContainer, label_txt: String, val_txt: String, pct: float, warn: float = LOAD_WARN_PCT, crit: float = LOAD_CRIT_PCT) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := _make_label(tr(label_txt), 12, UIStyle.COL_TEXT_SUB)
	l.custom_minimum_size = Vector2(70, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var col := UIStyle.COL_RED if pct >= crit else (UIStyle.COL_AMBER if pct >= warn else UIStyle.COL_GREEN)
	var pb := _make_bar(pct, col, 8)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pb)
	var v := _make_label(val_txt, 12, UIStyle.COL_RED if pct >= crit else UIStyle.COL_TEXT_MAIN, true)
	v.custom_minimum_size = Vector2(120, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)


func _load_color(pct: float) -> Color:
	if pct >= LOAD_CRIT_PCT:
		return UIStyle.COL_RED
	if pct >= LOAD_WARN_PCT:
		return UIStyle.COL_AMBER
	return UIStyle.COL_GREEN


func _set_status(txt: String, col: Color) -> void:
	_status_lbl.text = txt
	_status_lbl.add_theme_color_override("font_color", col)
	_status_lbl.modulate.a = 1.0
	var sb := UIStyle.make_panel(Color(col, 0.14), Color(col, 0.8), 3, 1, 12, 5)
	sb.shadow_size = 0
	_status_panel.add_theme_stylebox_override("panel", sb)
	_status_panel.visible = not txt.is_empty()
	if col == UIStyle.COL_RED:
		_pulse_nodes.append(_status_lbl)


func _format_catalog_part_specs(cat: String, pd: Dictionary) -> String:
	match cat:
		"cpu":
			return tr("Leistung %d Pkt.  •  %d W  •  +%.1f°C") % [int(pd.get("cpu_score", 0)), int(pd.get("watts", 0)), float(pd.get("heat", 0.0))]
		"ram":
			return "%d GB %s  •  %d W" % [int(pd.get("ram_gb", 0)), str(pd.get("tag", "")), int(pd.get("watts", 0))]
		"gpu":
			return tr("Leistung %d Pkt.  •  %d GB VRAM  •  %d W") % [int(pd.get("gpu_score", 0)), int(pd.get("vram_gb", 0)), int(pd.get("watts", 0))]
		"storage":
			return "%.1f TB  •  %d W" % [float(pd.get("storage_tb", 0.0)), int(pd.get("watts", 0))]
		"cooling":
			return tr("Kühlung %.1f°C  •  %d W") % [float(pd.get("heat", 0.0)), int(pd.get("watts", 0))]
		"psu":
			return tr("Max. %d W  •  Effizienz %+d%%") % [int(pd.get("psu_max_watts", 350)), int(roundf((1.0 - float(pd.get("watt_mult", 1.0))) * 100.0))]
	return ""


func _clear(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		c.queue_free()


# ==============================================================================
# GRUNDAUFBAU
# ==============================================================================
func _build_ui() -> void:
	_display_font = UIStyle.make_display_font(get_theme_default_font(), 0.5, 1)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.022, 0.026, 0.70)
	add_child(dim)
	dim.add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.6)]),
		PackedFloat32Array([0.35, 1.0]),
		Vector2(0.5, 0.5), Vector2(1.05, 0.5), true
	))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = CARD_MIN_SIZE
	var card_sb := UIStyle.make_panel(UIStyle.COL_BG_DARK, UIStyle.COL_BORDER, UIStyle.MAX_RADIUS, 1, 22, 18)
	card_sb.shadow_size = 28
	card_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	_card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(_card)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	_card.add_child(root_v)

	# Kopfzeile: Logo, Titel, Status, Schließen
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_v.add_child(header)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(38, 38)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.draw.connect(func() -> void: UIStyle.draw_logo_mark(logo, Rect2(Vector2.ZERO, logo.size)))
	header.add_child(logo)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)

	_title_lbl = Label.new()
	_title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(_title_lbl, 21, UIStyle.COL_TEXT_MAIN, _display_font, true)
	title_box.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(_subtitle_lbl, 12, UIStyle.COL_TEXT_SUB)
	title_box.add_child(_subtitle_lbl)

	# Umbenennen: nur bei Racks sichtbar. Enter oder Verlassen speichert, leer = Standardname.
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = tr("Rack umbenennen …")
	_rename_edit.tooltip_text = tr("Enter speichert, leer = Standardname, [ESC] bricht ab")
	_rename_edit.max_length = GameState.RACK_NAME_MAX_LEN
	_rename_edit.custom_minimum_size = Vector2(220, 36)
	_rename_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rename_edit.select_all_on_focus = true
	_rename_edit.visible = false
	UIStyle.style_line_edit(_rename_edit)
	_rename_edit.text_submitted.connect(func(_t: String) -> void: _rename_edit.release_focus())
	_rename_edit.focus_exited.connect(_commit_rename)
	header.add_child(_rename_edit)

	_status_panel = PanelContainer.new()
	_status_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.visible = false
	header.add_child(_status_panel)
	_status_lbl = Label.new()
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(_status_lbl, 12, UIStyle.COL_GREEN, _display_font)
	_status_panel.add_child(_status_lbl)

	_close_btn = Button.new()
	_close_btn.text = tr("SCHLIESSEN  [E / ESC]")
	_close_btn.custom_minimum_size = Vector2(170, 36)
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not MOUSE_CLICKS_ENABLED:
		_close_btn.button_mask = 0
	_close_btn.set_meta("key", "close")
	_close_btn.focus_entered.connect(func(): _focus_key = "close")
	_style_btn(_close_btn, Color(0.165, 0.170, 0.182, 0.97), UIStyle.COL_ACCENT)
	_close_btn.add_theme_font_override("font", _display_font)
	_close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(_close_btn)

	var glow := UIStyle.make_gradient_rect(
		PackedColorArray([UIStyle.COL_ACCENT, Color(UIStyle.COL_ACCENT, 0.0)]),
		PackedFloat32Array([0.0, 1.0]),
		Vector2(0.0, 0.5), Vector2(1.0, 0.5)
	)
	glow.custom_minimum_size = Vector2(0, 2)
	root_v.add_child(glow)

	_kpi_row = HBoxContainer.new()
	_kpi_row.add_theme_constant_override("separation", 10)
	root_v.add_child(_kpi_row)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	root_v.add_child(_tab_row)

	_body_host = VBoxContainer.new()
	_body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_host.add_theme_constant_override("separation", 10)
	root_v.add_child(_body_host)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root_v.add_child(footer)
	var hint := _make_label(tr("Mit der Maus auswählen    •    [E / ESC] Schließen"), 11, UIStyle.COL_TEXT_SUB)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(hint)
	_footer_actions = HBoxContainer.new()
	_footer_actions.add_theme_constant_override("separation", 8)
	footer.add_child(_footer_actions)

	_build_preview()


## Die 3D-Vorschau wird einmal gebaut und bei jedem Aufbau in die rechte Spalte gehängt.
func _build_preview() -> void:
	_preview_frame = PanelContainer.new()
	_preview_frame.custom_minimum_size = Vector2(0, PREVIEW_H)
	_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_frame.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.08, 0.095, 0.115, 0.98), UIStyle.COL_BORDER, 8, 1, 4, 4))

	var vp_overlay := Control.new()
	vp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	vp_overlay.gui_input.connect(_on_preview_gui_input)
	_preview_frame.add_child(vp_overlay)
	_preview_overlay = vp_overlay

	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_overlay.add_child(vp_container)

	# Bauteilname unter der Maus; liegt über dem Viewport, fängt selbst keine Klicks.
	_preview_hover_lbl = Label.new()
	_preview_hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_hover_lbl.visible = false
	_preview_hover_lbl.add_theme_font_size_override("font_size", 13)
	_preview_hover_lbl.add_theme_stylebox_override("normal", UIStyle.make_panel(Color(0.05, 0.06, 0.08, 0.92), UIStyle.COL_BORDER, 6, 1, 8, 4))
	vp_overlay.add_child(_preview_hover_lbl)
	vp_overlay.mouse_exited.connect(_clear_preview_hover)

	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.msaa_3d = Viewport.MSAA_4X
	_preview_vp.positional_shadow_atlas_size = 2048
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp_container.add_child(_preview_vp)

	# Studio-Himmel nur für Spiegelungen und Umgebungslicht; sichtbar bleibt die ruhige Hintergrundfarbe.
	# Ohne Himmel spiegeln metallische Teile (Kühler, Heatspreader, Gehäuse) nichts und wirken flach grau.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.62, 0.68, 0.76)
	sky_mat.sky_horizon_color = Color(0.86, 0.88, 0.91)
	sky_mat.ground_horizon_color = Color(0.42, 0.44, 0.47)
	sky_mat.ground_bottom_color = Color(0.12, 0.13, 0.15)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.115, 0.138)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	# Kontaktschatten zwischen dicht gesetzten Bauteilen (nur im Forward+-Renderer wirksam).
	env.ssao_enabled = true
	env.ssao_radius = 0.12
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_vp.add_child(we)

	var key_l := DirectionalLight3D.new()
	key_l.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
	key_l.light_energy = 1.25
	key_l.light_color = Color(1.0, 0.97, 0.92)
	key_l.shadow_enabled = true
	key_l.shadow_blur = 1.5
	key_l.shadow_bias = 0.02
	key_l.shadow_normal_bias = 0.6
	# Die Szene ist kleiner als 1,2 m: eine einzige Schattenkarte ergibt scharfe Schatten.
	key_l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key_l.directional_shadow_max_distance = 3.0
	_preview_vp.add_child(key_l)

	var fill_l := DirectionalLight3D.new()
	fill_l.rotation_degrees = Vector3(-22.0, -138.0, 0.0)
	fill_l.light_energy = 0.45
	fill_l.light_color = Color(0.86, 0.91, 1.0)
	_preview_vp.add_child(fill_l)

	# Kantenlicht von hinten oben trennt Lamellen, Riegel und Kartenkanten vom Hintergrund (ohne Spiegel-Blendung auf der Platine).
	var rim_l := DirectionalLight3D.new()
	rim_l.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim_l.light_energy = 0.50
	rim_l.light_specular = 0.45
	_preview_vp.add_child(rim_l)

	var cam := Camera3D.new()
	cam.position = PREVIEW_CAM_POS * _preview_zoom
	cam.rotation_degrees = Vector3(-33.5, 0.0, 0.0)
	cam.fov = 38.0
	_preview_vp.add_child(cam)
	_preview_cam = cam

	_preview_pivot = Node3D.new()
	_preview_vp.add_child(_preview_pivot)

	# Werkbank mit ESD-Matte aus Blender; fehlt das Modell, bleibt die einfache Matte.
	var bench := HardwareMeshFactory.build_preview_workbench()
	if bench != null:
		_preview_pivot.add_child(bench)
	else:
		var pad := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.12, 0.02, 1.02)
		pad.mesh = pm
		pad.material_override = MatLib.get_mat("esd_mat")
		pad.position = Vector3(0.0, -0.015, 0.0)
		_preview_pivot.add_child(pad)

	_preview_model_holder = Node3D.new()
	_preview_pivot.add_child(_preview_model_holder)

	var hint_lbl := Label.new()
	hint_lbl.text = tr("Maus ziehen zum Drehen, Mausrad zum Zoomen")
	UIStyle.style_label(hint_lbl, 11, UIStyle.COL_GOLD_TEXT, _display_font, true)
	hint_lbl.position = Vector2(12, 10)
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_overlay.add_child(hint_lbl)

	# Unten rechts, damit der Knopf in schmalen Spalten nicht über dem Hinweistext liegt.
	_preview_fs_btn = Button.new()
	_preview_fs_btn.text = tr("Vollbild")
	_preview_fs_btn.focus_mode = Control.FOCUS_NONE
	_preview_fs_btn.add_theme_font_size_override("font_size", 12)
	_style_btn(_preview_fs_btn, Color(0.165, 0.170, 0.182, 0.97), UIStyle.COL_ACCENT)
	_preview_fs_btn.anchor_left = 1.0
	_preview_fs_btn.anchor_right = 1.0
	_preview_fs_btn.anchor_top = 1.0
	_preview_fs_btn.anchor_bottom = 1.0
	_preview_fs_btn.offset_left = -8.0
	_preview_fs_btn.offset_right = -8.0
	_preview_fs_btn.offset_top = -8.0
	_preview_fs_btn.offset_bottom = -8.0
	_preview_fs_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_preview_fs_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_preview_fs_btn.pressed.connect(func() -> void: set_preview_fullscreen(not _preview_fullscreen))
	vp_overlay.add_child(_preview_fs_btn)

	# Liegt als letztes Kind über der Karte und fängt alle Klicks daneben ab.
	_preview_fs_host = PanelContainer.new()
	_preview_fs_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_fs_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_fs_host.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.03, 0.035, 0.045, 0.94), UIStyle.COL_BORDER, 0, 0, 32, 32))
	_preview_fs_host.hide()
	add_child(_preview_fs_host)


func is_preview_fullscreen() -> bool:
	return _preview_fullscreen


func set_preview_fullscreen(on: bool) -> void:
	if on == _preview_fullscreen:
		return
	if on and (_preview_frame.get_parent() == null or not _preview_frame.is_visible_in_tree()):
		return
	_preview_fullscreen = on
	_preview_dragging = false
	if on:
		_move_preview_to_fullscreen()
		_preview_fs_host.show()
	else:
		_restore_preview_home()
		_preview_fs_host.hide()
	_preview_fs_btn.text = tr("Vollbild beenden [ESC]") if on else tr("Vollbild")
	SfxManager.play("click", -10.0, 1.0)


func _move_preview_to_fullscreen() -> void:
	var home := _preview_frame.get_parent()
	if home == null or home == _preview_fs_host:
		return
	var idx := _preview_frame.get_index()
	home.remove_child(_preview_frame)
	_preview_placeholder = Control.new()
	_preview_placeholder.custom_minimum_size = Vector2(0, PREVIEW_H)
	_preview_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home.add_child(_preview_placeholder)
	home.move_child(_preview_placeholder, idx)
	_preview_fs_host.add_child(_preview_frame)


func _restore_preview_home() -> void:
	var cur := _preview_frame.get_parent()
	if cur != null:
		cur.remove_child(_preview_frame)
	if is_instance_valid(_preview_placeholder) and _preview_placeholder.is_inside_tree() \
			and not _preview_placeholder.is_queued_for_deletion():
		var home := _preview_placeholder.get_parent()
		var idx := _preview_placeholder.get_index()
		home.add_child(_preview_frame)
		home.move_child(_preview_frame, idx)
		home.remove_child(_preview_placeholder)
		_preview_placeholder.queue_free()
	# Ohne gültigen Platzhalter bleibt die Vorschau frei, der nächste Aufbau hängt sie wieder ein.
	_preview_placeholder = null


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_preview_click_travel = 0.0
			elif _preview_dragging and _preview_click_travel <= PREVIEW_CLICK_SLOP:
				# Klick ohne Drehen: angeklicktes Bauteil reparieren.
				_try_repair_preview_part(mb.position)
			_preview_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var step := PREVIEW_ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / PREVIEW_ZOOM_STEP
				_set_preview_zoom(_preview_zoom * step)
			# Das Mausrad gehört hier der Vorschau, sonst scrollt die Seite mit.
			_preview_overlay.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _preview_dragging:
			_preview_click_travel += mm.relative.length()
			_preview_yaw += mm.relative.x * 0.012
			_preview_pitch = clampf(_preview_pitch + mm.relative.y * 0.008, -0.45, 0.35)
		_update_preview_hover(mm.position)


func _update_preview_hover(pos: Vector2) -> void:
	if _preview_cam == null or _preview_vp == null or _preview_overlay == null or _preview_hover_lbl == null:
		return
	var ov_size := _preview_overlay.size
	if ov_size.x <= 0.0 or ov_size.y <= 0.0 or _preview_part_nodes.is_empty():
		_clear_preview_hover()
		return
	var cat := _preview_part_at(pos)
	if cat == "":
		_clear_preview_hover()
		return
	var faulty := cat == _preview_faulty_cat
	var txt := GameState.get_component_label(cat)
	if faulty:
		txt = tr("%s – DEFEKT!") % txt
	if _can_repair_preview_part(cat):
		txt = tr("%s  ·  Klicken: Server zur Werkbank ziehen") % txt
	_preview_hover_lbl.text = txt
	_preview_hover_lbl.add_theme_color_override("font_color", UIStyle.COL_RED if faulty else Color(0.92, 0.94, 0.97))
	_preview_hover_lbl.visible = true
	_preview_hover_lbl.reset_size()
	var lsize := _preview_hover_lbl.get_combined_minimum_size()
	var p := pos + Vector2(14.0, 10.0)
	p.x = maxf(0.0, minf(p.x, ov_size.x - lsize.x - 4.0))
	p.y = maxf(0.0, minf(p.y, ov_size.y - lsize.y - 4.0))
	_preview_hover_lbl.position = p
	if faulty:
		_try_diagnose_selected_slot()


## Bauteil-Kategorie unter der Mausposition in der 3D-Vorschau, "" wenn nichts getroffen wird.
func _preview_part_at(pos: Vector2) -> String:
	if _preview_cam == null or _preview_vp == null or _preview_overlay == null:
		return ""
	var ov_size := _preview_overlay.size
	if ov_size.x <= 0.0 or ov_size.y <= 0.0 or _preview_part_nodes.is_empty():
		return ""
	var vp_pos := pos * (Vector2(_preview_vp.size) / ov_size)
	return _pick_preview_part(_preview_cam.project_ray_origin(vp_pos), _preview_cam.project_ray_normal(vp_pos))


func _selected_slot_data() -> Dictionary:
	if not GameState.racks.has(_entity_id):
		return {}
	var slots: Array = GameState.racks[_entity_id]["slots"]
	if _selected_slot < 0 or _selected_slot >= slots.size():
		return {}
	return slots[_selected_slot] as Dictionary


## Darf ein Klick auf dieses Bauteil den gewählten Slot reparieren?
func _can_repair_preview_part(cat: String) -> bool:
	var slot := _selected_slot_data()
	if str(slot.get("state", "")) != "crashed" or GameState.is_slot_awaiting_diagnosis(slot):
		return false
	var faulty := str(slot.get("faulty_part", ""))
	# Ohne bestimmtes defektes Teil (z. B. Überhitzung) reicht ein Klick auf irgendein Bauteil.
	return faulty == "" or cat == faulty


func _try_repair_preview_part(pos: Vector2) -> void:
	var cat := _preview_part_at(pos)
	if cat == "" or not _can_repair_preview_part(cat):
		return
	if GameState.is_player_holding_anything(multiplayer.get_unique_id()):
		SfxManager.play("error", -8.0)
		return
	SfxManager.play("pickup", -8.0, 1.0)
	if not GameState.is_slot_extended(_entity_id, _selected_slot):
		GameState.request_toggle_slot_extended(_entity_id, _selected_slot)
	GameState.request_pull_server_tray(_entity_id, _selected_slot)
	close_requested.emit()


func _clear_preview_hover() -> void:
	if _preview_hover_lbl != null:
		_preview_hover_lbl.visible = false


## Exaktes Bauteil unter dem Mausstrahl mittels lokalem AABB-Vortest + Dreiecks-Raycast (TriangleMesh).
## Verhindert die aufgeblähte Welt-AABB gedrehter Mainboards, sodass jedes Teil sauber erkannt wird.
func _pick_preview_part(origin: Vector3, dir: Vector3) -> String:
	var best_non_mb_cat := ""
	var best_non_mb_d := INF
	var best_mb_d := INF
	for part_v in _preview_part_nodes:
		if not is_instance_valid(part_v):
			continue
		var part := part_v as Node
		var cat := str(part.get_meta("part_cat", ""))
		var d := _ray_hit_distance(part, origin, dir, true)
		if cat == "mainboard":
			best_mb_d = minf(best_mb_d, d)
		elif d < best_non_mb_d:
			best_non_mb_d = d
			best_non_mb_cat = cat
	if best_non_mb_cat != "" and best_non_mb_d <= best_mb_d + 0.001:
		return best_non_mb_cat
	# Schmale Luftspalte (z. B. zwischen Kühlrippen, RAM-Modulen oder Lüfterflügeln) dem davor liegenden
	# Bauteil zuordnen, solange dessen lokale Hüllbox vor der Mainboard-Fläche liegt. Kabel-AABBs (PSU/GPU)
	# werden ausgenommen, weil diagonale Stränge sonst freie Mainboard-Bereiche überdecken.
	var box_cat := ""
	var box_d := INF
	for part_v in _preview_part_nodes:
		if not is_instance_valid(part_v):
			continue
		var part := part_v as Node
		var cat := str(part.get_meta("part_cat", ""))
		if cat != "cpu" and cat != "ram" and cat != "storage" and cat != "cooling":
			continue
		var bd := _ray_hit_distance(part, origin, dir, false)
		if bd <= best_mb_d + 0.002 and bd < box_d:
			box_d = bd
			box_cat = cat
	if box_cat != "":
		return box_cat
	return "mainboard" if best_mb_d < INF else ""


func _get_triangle_mesh(mesh: Mesh) -> TriangleMesh:
	if mesh == null:
		return null
	if _tri_mesh_cache.has(mesh):
		return _tri_mesh_cache[mesh] as TriangleMesh
	var tm := mesh.generate_triangle_mesh()
	_tri_mesh_cache[mesh] = tm
	return tm


func _ray_hit_distance(n: Node, origin: Vector3, dir: Vector3, tri_exact: bool = true) -> float:
	var best := INF
	if not tri_exact and n.name.begins_with("Cable"):
		return best
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			var inv := mi.global_transform.affine_inverse()
			var local_o := inv * origin
			var local_d := inv.basis * dir
			if local_d.length_squared() > 1e-10:
				local_d = local_d.normalized()
				var box_hit: Variant = mi.get_aabb().intersects_ray(local_o, local_d)
				if box_hit != null:
					var tm := _get_triangle_mesh(mi.mesh) if tri_exact else null
					if tm != null:
						var thit: Variant = tm.intersect_ray(local_o, local_d)
						if thit is Dictionary and (thit as Dictionary).has("position"):
							var world_p: Vector3 = mi.global_transform * ((thit as Dictionary)["position"] as Vector3)
							best = minf(best, origin.distance_to(world_p))
					elif not tri_exact or tm == null:
						var world_b: Vector3 = mi.global_transform * (box_hit as Vector3)
						best = minf(best, origin.distance_to(world_b))
	for c in n.get_children():
		# Eingebaute Bauteile (z. B. die CPU auf dem Mainboard) werden einzeln getestet.
		if c.has_meta("part_cat"):
			continue
		best = minf(best, _ray_hit_distance(c, origin, dir, tri_exact))
	return best


func _try_diagnose_selected_slot() -> void:
	if not GameState.racks.has(_entity_id):
		return
	var slots: Array = GameState.racks[_entity_id]["slots"]
	if _selected_slot < 0 or _selected_slot >= slots.size():
		return
	if not GameState.is_slot_awaiting_diagnosis(slots[_selected_slot] as Dictionary):
		return
	var key := "%s:%d" % [_entity_id, _selected_slot]
	if _diag_requested_key == key:
		return
	_diag_requested_key = key
	SfxManager.play("click", -8.0, 0.8)
	GameState.request_diagnose_slot(_entity_id, _selected_slot)


func _collect_preview_parts(n: Node) -> void:
	if n.has_meta("part_cat"):
		_preview_part_nodes.append(n)
	for c in n.get_children():
		_collect_preview_parts(c)


func _set_overlay_recursive(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = mat
	for c in n.get_children():
		# Nur das markierte Bauteil einfärben, nicht die Teile, die darauf sitzen.
		if c.has_meta("part_cat"):
			continue
		_set_overlay_recursive(c, mat)


func _get_fault_mat() -> StandardMaterial3D:
	if _preview_fault_mat == null:
		_preview_fault_mat = StandardMaterial3D.new()
		_preview_fault_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview_fault_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_fault_mat.albedo_color = Color(1.0, 0.12, 0.08, 0.35)
	return _preview_fault_mat


func _set_preview_zoom(value: float) -> void:
	_preview_zoom = clampf(value, PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX)
	if _preview_cam != null:
		_preview_cam.position = PREVIEW_CAM_POS * _preview_zoom


func _update_3d_preview(item_type: String, comps: Dictionary, faulty_cat: String = "", reveal_fault: bool = true, broken_visual_cat: String = "") -> void:
	if _preview_vp == null:
		return
	if item_type == "":
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_preview_faulty_cat = ""
		_clear_preview_hover()
		return
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var sig := "%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [
		item_type,
		str(comps.get("cpu", "")),
		str(comps.get("gpu", "")),
		str(comps.get("ram", "")),
		str(comps.get("storage", "")),
		str(comps.get("cooling", "")),
		str(comps.get("psu", "")),
		faulty_cat,
		broken_visual_cat,
		"%s:%d" % [_entity_id, _selected_slot],
		str(reveal_fault),
	]
	if _preview_sig == sig:
		return
	_preview_sig = sig
	_diag_requested_key = ""
	_preview_faulty_cat = faulty_cat
	_clear_preview_hover()

	_clear(_preview_model_holder)
	_preview_fans.clear()
	_preview_part_nodes.clear()
	var srv := HardwareMeshFactory.build_open_server_chassis(item_type, comps, _preview_fans, broken_visual_cat)
	_preview_model_holder.add_child(srv)
	_preview_fx = PartFx.new()
	_preview_fx.attach(srv, [], true)
	srv.add_child(_preview_fx)
	_collect_preview_parts(srv)
	if broken_visual_cat != "":
		for part_v in _preview_part_nodes:
			var part := part_v as Node
			if str(part.get_meta("part_cat", "")) == broken_visual_cat:
				if part is Node3D:
					_attach_preview_damage_vfx(part as Node3D, broken_visual_cat)
				if faulty_cat != "" and reveal_fault:
					_set_overlay_recursive(part, _get_fault_mat())


## Dezenter Rauchfaden + Mikro-Funken direkt über dem defekten Bauteil in der 3D-Vorschau.
func _attach_preview_damage_vfx(target: Node3D, cat: String) -> void:
	var offset := Vector3(0.0, 0.04, 0.0)
	if cat == "mainboard":
		offset = Vector3(-0.08, 0.03, -0.15)
	elif cat == "psu":
		offset = Vector3(0.0, 0.08, -0.02)
	elif cat == "cooling":
		offset = Vector3(0.0, 0.06, 0.0)
	elif cat == "gpu":
		offset = Vector3(0.01, 0.06, 0.03)

	var smoke := CPUParticles3D.new()
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.amount = 14
	smoke.lifetime = 1.4
	smoke.preprocess = 0.6
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.024
	smoke.direction = Vector3(0.0, 1.0, 0.0)
	smoke.spread = 18.0
	smoke.gravity = Vector3(0.0, 0.08, 0.0)
	smoke.initial_velocity_min = 0.06
	smoke.initial_velocity_max = 0.14
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.6
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.billboard_keep_scale = true
	smat.vertex_color_use_as_albedo = true
	smat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	smat.albedo_color = Color(0.18, 0.18, 0.20, 0.42)
	qm.material = smat
	smoke.mesh = qm
	smoke.position = offset
	target.add_child(smoke)

	var sparks := CPUParticles3D.new()
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.amount = 8
	sparks.lifetime = 0.45
	sparks.preprocess = 0.3
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.018
	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 55.0
	sparks.gravity = Vector3(0.0, -1.2, 0.0)
	sparks.initial_velocity_min = 0.18
	sparks.initial_velocity_max = 0.45
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.1
	var sqm := QuadMesh.new()
	sqm.size = Vector2(0.010, 0.010)
	var spmat := StandardMaterial3D.new()
	spmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spmat.billboard_keep_scale = true
	spmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spmat.albedo_color = Color(1.0, 0.72, 0.22, 0.95)
	sqm.material = spmat
	sparks.mesh = sqm
	sparks.position = offset
	target.add_child(sparks)


## Die Vorschau hängt zwischen zwei Aufbauten frei im Speicher und wird hier mit aufgeräumt.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_preview_frame) and _preview_frame.get_parent() == null:
		_preview_frame.free()