class_name RackInspectorUI
extends Control
## v1.2 Rack-, Router- und Geräte-Overlay im Stil von Hauptmenü und HUD (Anthrazit, gedämpftes Amber).
## Keine Emoji-Symbole mehr: Klartext, gezeichnete Symbole, Akzentleisten und Reiter mit Unterstrich.
## Clean 3-Tab Rack Layout:
##   1. [📊 Übersicht & Vermietung] — Hardware Totals, Rental Purpose & Live User Load Bars
##   2. [🔧 Hardware-Bau (Lager)]   — 66 Parts with Generation Filters (DDR2-DDR5, HDD/SSD/NVMe) installed from Teile-Lager
##   3. [🖥 3D-Vorschau]            — Spacious 360°-Rotatable Live 3D Hardware Workbench
## Zero "CU" jargon — 100% real metrics (GB RAM, TB Storage, Mbit/Gbit, Watts, °C).

signal close_requested
signal relocate_rack_requested(rack_id: String)

var _mode: String = "rack" # "rack" | "router" | "cooler" | "ups" | "cart"
var _entity_id: String = ""
var _selected_slot: int = 0
var _active_tab: String = "overview" # "overview" | "hardware" | "preview"
var _selected_cat: String = "ram"
var _selected_filter: String = "Alle"
var _only_in_stock: bool = false
var _confirm_sell_entity: bool = false

var _card: PanelContainer
var _title_lbl: Label
var _subtitle_lbl: Label
var _stat_strip: HBoxContainer
var _tab_row: HBoxContainer
var _body_host: VBoxContainer
var _display_font: FontVariation

# Spacious 360° 3D Hardware Preview Studio (shown on Tab 3!)
var _preview_frame: PanelContainer
var _preview_vp: SubViewport
var _preview_pivot: Node3D
var _preview_model_holder: Node3D
var _preview_fans: Array = []
var _preview_sig: String = ""
var _preview_dragging: bool = false
var _preview_yaw: float = 0.45
var _preview_pitch: float = -0.05


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	GameState.racks_changed.connect(_refresh)
	GameState.coolers_changed.connect(_refresh)
	GameState.ups_changed.connect(_refresh)
	GameState.carts_changed.connect(_refresh)
	GameState.inventory_changed.connect(_refresh)
	GameState.state_updated.connect(_refresh)


func _process(delta: float) -> void:
	if not visible or _preview_vp == null or not _preview_frame.visible:
		return
	if not _preview_dragging:
		_preview_yaw += delta * 0.28
	if _preview_pivot != null:
		_preview_pivot.rotation.y = _preview_yaw
		_preview_pivot.rotation.x = _preview_pitch
	for fn in _preview_fans:
		if is_instance_valid(fn):
			var fnode := fn as Node3D
			if str(fnode.get_meta("spin_axis", "z")) == "x":
				fnode.rotation.x += delta * 14.0
			else:
				fnode.rotation.z += delta * 14.0


func open_rack(rack_id: String, initial_slot: int = 0) -> void:
	if not GameState.racks.has(rack_id):
		return
	_mode = "rack"
	_entity_id = rack_id
	_selected_slot = clampi(initial_slot, 0, (GameState.racks[rack_id]["slots"] as Array).size() - 1)
	_confirm_sell_entity = false
	_preview_sig = ""
	UIStyle.animate_popup_open(self, _card)
	_refresh()
	SfxManager.play("click", -8.0, 1.15)


func open_device(kind: String, entity_id: String) -> void:
	_mode = kind
	_entity_id = entity_id
	_confirm_sell_entity = false
	_preview_sig = ""
	UIStyle.animate_popup_open(self, _card)
	_refresh()
	SfxManager.play("click", -8.0, 1.15)


func close_inspector() -> void:
	_confirm_sell_entity = false
	_preview_dragging = false
	if _preview_vp != null:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	UIStyle.animate_popup_close(self, _card)
	SfxManager.play("click", -10.0, 0.85)


func _refresh() -> void:
	if not visible:
		return
	if _mode == "rack":
		if not GameState.racks.has(_entity_id):
			close_requested.emit()
			return
		_render_rack_view()
	elif _mode == "router":
		_render_router_view()
	elif _mode == "cooler":
		if not GameState.coolers.has(_entity_id):
			close_requested.emit()
			return
		_render_device_view("cooler")
	elif _mode == "ups":
		if not GameState.ups_units.has(_entity_id):
			close_requested.emit()
			return
		_render_device_view("ups")
	elif _mode == "cart":
		if not GameState.carts.has(_entity_id):
			close_requested.emit()
			return
		_render_device_view("cart")


# ==============================================================================
# RACK OVERLAY (3 CLEAN TABS: ÜBERSICHT & VERMIETUNG | HARDWARE-BAU | 3D-VORSCHAU)
# ==============================================================================
func _render_rack_view() -> void:
	_clear(_stat_strip)
	_clear(_tab_row)
	_clear(_body_host)

	var rack: Dictionary = GameState.racks[_entity_id]
	var rtype := str(rack.get("rack_type", "rack"))
	var cat_rack: Dictionary = GameState.ITEM_CATALOG[rtype]
	var slots: Array = rack["slots"]
	_selected_slot = clampi(_selected_slot, 0, slots.size() - 1)

	var hw := GameState.get_rack_hardware_summary(_entity_id)
	var used_slots := 0
	for s in slots:
		if str((s as Dictionary)["item_type"]) != "":
			used_slots += 1
	var max_pdu := int(cat_rack.get("max_pdu_watts", 3200))
	var temp := float(rack["temp"])
	var powered := bool(rack["powered"])
	var networked := bool(rack["networked"])

	_title_lbl.text = "%s  —  %s" % [_entity_id.to_upper(), str(cat_rack["name"])]
	_subtitle_lbl.text = "Guthaben: $%.0f   •   Teile im Lager: %d   •   Restwert: $%d" % [
		GameState.money, GameState.get_total_inventory_parts(), GameState.get_rack_sell_value(_entity_id)
	]

	# Compact Top 4-Stat Strip (Slate & Gold Pills — airy and readable!)
	_stat_strip.visible = true
	_add_stat_pill("STROMLAST", "%d / %d W" % [int(hw["watts"]), max_pdu], UIStyle.COL_RED if int(hw["watts"]) > max_pdu else UIStyle.COL_GOLD_TEXT, "power")
	_add_stat_pill("EINSCHÜBE", "%d / %d belegt" % [used_slots, slots.size()], UIStyle.COL_GREEN if used_slots < slots.size() else UIStyle.COL_AMBER)
	_add_stat_pill("TEMPERATUR", "%.0f °C" % temp, UIStyle.COL_RED if temp >= 70.0 else UIStyle.COL_BLUE, "temp")
	_add_stat_pill("ANSCHLÜSSE", "Strom %s  •  LAN %s" % ["OK" if powered else "FEHLT", "OK" if networked else "FEHLT"], UIStyle.COL_GREEN if (powered and networked) else UIStyle.COL_AMBER, "info" if (powered and networked) else "warn")

	# 3 Clean Main Tabs
	_tab_row.visible = true
	var inv_n := GameState.get_total_inventory_parts()
	_add_main_tab("overview", "ÜBERSICHT & VERMIETUNG")
	_add_main_tab("hardware", "HARDWARE-BAU  (%d IM LAGER)" % inv_n)
	_add_main_tab("preview", "3D-VORSCHAU")

	# Toggle 3D SubViewport cleanly ONLY on Tab 3!
	if _active_tab == "preview":
		var cur_slot: Dictionary = slots[_selected_slot]
		_update_3d_preview(str(cur_slot["item_type"]), cur_slot.get("components", {}) as Dictionary)
		_render_tab_preview(slots)
	else:
		_update_3d_preview("", {})
		if _active_tab == "overview":
			_render_tab_overview(rack, hw)
		else:
			_render_tab_hardware(rack, slots)


func _add_main_tab(tab_id: String, label_txt: String) -> void:
	var btn := Button.new()
	btn.text = label_txt
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 13)
	_style_tab(btn, _active_tab == tab_id)
	var cap := tab_id
	btn.pressed.connect(func():
		_active_tab = cap
		SfxManager.play("click", -12.0, 1.1)
		_render_rack_view()
	)
	_tab_row.add_child(btn)


# ==============================================================================
# TAB 1: ÜBERSICHT & VERMIETUNG (Clean 2-Column Overview + Live User Load Bars)
# ==============================================================================
func _render_tab_overview(rack: Dictionary, hw: Dictionary) -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	_body_host.add_child(split)

	# LEFT: Hardware Totals + Actions
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 10)
	split.add_child(left)

	var hw_card := PanelContainer.new()
	hw_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 4, 1, 14, 12))
	left.add_child(hw_card)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hw_card.add_child(hv)

	hv.add_child(_section_label("HARDWARE IM RACK"))

	_add_kv_line(hv, "Aktive Server", "%d / %d online" % [int(hw["active_servers"]), int(hw["total_servers"])])
	_add_kv_line(hv, "CPU-Leistung", "%d Pkt." % int(hw["cpu_score"]))
	_add_kv_line(hv, "Arbeitsspeicher", "%d GB RAM" % int(hw["ram_gb"]))
	_add_kv_line(hv, "Grafik / VRAM", "%d Pkt. (%d GB)" % [int(hw["gpu_score"]), int(hw["vram_gb"])])
	_add_kv_line(hv, "Speicherplatz", "%.1f TB" % float(hw["storage_tb"]))
	_add_kv_line(hv, "Haus-Router", HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps))

	if bool(hw.get("psu_overloaded", false)):
		var pw := Label.new()
		pw.text = "Mindestens ein Netzteil ist zu schwach für seine Bauteile."
		pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(pw, 12, UIStyle.COL_RED)
		hv.add_child(pw)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)

	var move_btn := Button.new()
	move_btn.text = "Rack umsetzen"
	move_btn.custom_minimum_size = Vector2(0, 38)
	UIStyle.style_button(move_btn, Color(0.15, 0.17, 0.19), UIStyle.COL_BLUE)
	move_btn.pressed.connect(func(): relocate_rack_requested.emit(_entity_id))
	left.add_child(move_btn)

	var sell_val := GameState.get_rack_sell_value(_entity_id)
	var sell_btn := Button.new()
	sell_btn.custom_minimum_size = Vector2(0, 38)
	if _confirm_sell_entity:
		sell_btn.text = "WIRKLICH VERKAUFEN? (+$%d)" % sell_val
		UIStyle.style_button(sell_btn, Color(0.62, 0.16, 0.14), UIStyle.COL_RED)
	else:
		sell_btn.text = "Rack verkaufen (+$%d)" % sell_val
		UIStyle.style_button(sell_btn, Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell_btn.pressed.connect(func():
		if not _confirm_sell_entity:
			_confirm_sell_entity = true
			SfxManager.play("click", -8.0, 0.9)
			_render_rack_view()
		else:
			GameState.request_sell_rack(_entity_id)
			close_requested.emit()
	)
	left.add_child(sell_btn)

	# RIGHT: Scrollable Live Load + Rental Service Picker
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 10)
	scroll.add_child(rv)

	var r_rent := str(rack.get("rental_type", "none"))
	var m: Dictionary = rack.get("metrics", {})
	if r_rent != "none" and HardwareCatalog.RENTAL_PROFILES.has(r_rent):
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[r_rent]
		var users := int(rack.get("active_users", 0))
		var sat := float(rack.get("satisfaction", 100.0))
		var inc := float(rack.get("rental_income", 0.0))

		var load_card := PanelContainer.new()
		var bn := str(m.get("bottleneck", "ok"))
		load_card.add_theme_stylebox_override("panel", UIStyle.make_panel(
			UIStyle.COL_BG_CARD, UIStyle.COL_RED if bn != "ok" else UIStyle.COL_GREEN, 8, 1, 14, 12
		))
		rv.add_child(load_card)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		load_card.add_child(lv)

		var lh := Label.new()
		lh.text = "%s  —  %s" % [str(prof["short"]).to_upper(), str(rack.get("rental_customer", ""))]
		lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(lh, 14, UIStyle.COL_TEXT_MAIN, _display_font)
		lv.add_child(lh)

		var lmeta := Label.new()
		lmeta.text = "%d aktive Nutzer   •   Zufriedenheit %.0f %%   •   +$%.0f pro 5 s" % [users, sat, inc]
		lmeta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(lmeta, 12, UIStyle.COL_AMBER if sat < 75.0 else UIStyle.COL_GREEN)
		lv.add_child(lmeta)

		_add_load_bar_row(lv, "RAM-Belegung", "%.1f / %.0f GB (%.0f%%)" % [float(m.get("ram_used_gb", 0.0)), float(m.get("ram_total_gb", 0.0)), float(m.get("ram_pct", 0.0))], float(m.get("ram_pct", 0.0)))
		_add_load_bar_row(lv, "CPU-Auslastung", "%.0f%% Last" % float(m.get("cpu_pct", 0.0)), float(m.get("cpu_pct", 0.0)))
		_add_load_bar_row(lv, "Speicherplatz", "%.2f / %.1f TB (%.0f%%)" % [float(m.get("storage_used_tb", 0.0)), float(m.get("storage_total_tb", 0.0)), float(m.get("storage_pct", 0.0))], float(m.get("storage_pct", 0.0)))
		if float(prof["gpu_per_user"]) > 0.001:
			_add_load_bar_row(lv, "GPU-Auslastung", "%.0f%% Last" % float(m.get("gpu_pct", 0.0)), float(m.get("gpu_pct", 0.0)))
		_add_load_bar_row(lv, "Internet-Uplink", "%s / %s" % [
			HardwareCatalog.format_speed_mbps(float(m.get("net_used_mbps", 0.0))),
			HardwareCatalog.format_speed_mbps(GameState.max_bandwidth_mbps)
		], float(m.get("net_pct", 0.0)))

	rv.add_child(_section_label("VERMIETUNG WÄHLEN"))
	var pick_lbl := Label.new()
	pick_lbl.text = "Schätze selbst ein, ob RAM, CPU, Speicher und Router für den Dienst reichen."
	pick_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(pick_lbl, 12, UIStyle.COL_TEXT_SUB)
	rv.add_child(pick_lbl)

	for key in HardwareCatalog.RENTAL_ORDER:
		var prof: Dictionary = HardwareCatalog.RENTAL_PROFILES[key]
		var is_cur := (key == r_rent)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIStyle.make_panel(
			Color(0.11, 0.19, 0.14, 0.96) if is_cur else UIStyle.COL_BG_CARD,
			UIStyle.COL_GREEN if is_cur else UIStyle.COL_BORDER,
			7, 1, 12, 8
		))
		rv.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		var iv := VBoxContainer.new()
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_theme_constant_override("separation", 2)
		row.add_child(iv)

		var tl := Label.new()
		var pay_s := ("   •   $%.2f pro Nutzer" % float(prof["pay_per_user"])) if key != "none" else ""
		tl.text = "%s%s" % [str(prof["label"]), pay_s]
		UIStyle.style_label(tl, 14, UIStyle.COL_GREEN if is_cur else UIStyle.COL_TEXT_MAIN, _display_font)
		iv.add_child(tl)

		var dl := Label.new()
		dl.text = str(prof["desc"])
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(dl, 12, UIStyle.COL_TEXT_SUB)
		iv.add_child(dl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(146, 34)
		if is_cur:
			btn.text = "AKTIV"
			btn.disabled = true
			UIStyle.style_button(btn, Color(0.16, 0.26, 0.16), UIStyle.COL_GREEN)
		else:
			btn.text = "Freigeben" if key == "none" else "Vermieten"
			UIStyle.style_button(btn, Color(0.18, 0.17, 0.15), UIStyle.COL_GOLD_TEXT)
			var cap_k: String = key
			btn.pressed.connect(func(): GameState.request_set_rack_rental(_entity_id, cap_k))
		row.add_child(btn)


# ==============================================================================
# TAB 2: HARDWARE-BAU (INSTALL PARTS FROM TEILE-LAGER WITH GENERATION FILTERS!)
# ==============================================================================
func _render_tab_hardware(_rack: Dictionary, slots: Array) -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	_body_host.add_child(split)

	# LEFT: Clean Server Slot Selector
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 7)
	split.add_child(left)

	left.add_child(_section_label("EINSCHÜBE"))

	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var itype := str(slot["item_type"])
		var sstate := str(slot["state"])
		var is_sel := (i == _selected_slot)

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 48)
		if itype == "":
			btn.text = "  Slot %d  —  [ Leer / Frei ]" % (i + 1)
		else:
			var cname := str(GameState.ITEM_CATALOG[itype]["name"])
			var st := GameState.get_slot_stats(slot)
			var warn := "   •   BRAND" if sstate == "burning" else ("   •   AUSGEFALLEN" if sstate == "crashed" else "")
			if GameState.is_slot_upgradeable(itype):
				btn.text = "  Slot %d  —  %s%s\n  %d GB %s • %.1f TB • %d W" % [
					i + 1, cname, warn, int(st["ram_gb"]), str(st["ram_tag"]), float(st["storage_tb"]), int(st["watts"])
				]
			else:
				btn.text = "  Slot %d  —  %s%s\n  %d W • Netzwerk-Switch" % [i + 1, cname, warn, int(st["watts"])]
		UIStyle.style_button(
			btn,
			Color(0.86, 0.58, 0.16, 0.24) if is_sel else UIStyle.COL_BG_CARD,
			UIStyle.COL_RED if (sstate == "burning" or sstate == "crashed") else (UIStyle.COL_GOLD_TEXT if is_sel else UIStyle.COL_BORDER)
		)
		var cap_i := i
		btn.pressed.connect(func():
			_selected_slot = cap_i
			SfxManager.play("click", -12.0, 1.1)
			_render_rack_view()
		)
		left.add_child(btn)

	# RIGHT: Filtered Hardware Assembly from Teile-Lager
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	var cur_slot: Dictionary = slots[_selected_slot]
	var cur_type := str(cur_slot["item_type"])
	var cur_state := str(cur_slot["state"])

	if cur_type == "":
		var empty_c := PanelContainer.new()
		empty_c.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 8, 1, 16, 14))
		right.add_child(empty_c)
		var el := Label.new()
		el.text = "Slot %d ist leer.\n\nBestelle im Windows-PC-Shop ein Server-Chassis (1U Standard, 2U Storage oder 4U GPU), nimm den Karton aus der Lieferzone auf und schiebe ihn mit [E] in diesen Slot!" % (_selected_slot + 1)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIStyle.style_label(el, 13, UIStyle.COL_TEXT_SUB)
		empty_c.add_child(el)
		return

	var stats := GameState.get_slot_stats(cur_slot)
	var sum_card := PanelContainer.new()
	sum_card.add_theme_stylebox_override("panel", UIStyle.make_panel(
		UIStyle.COL_BG_CARD, UIStyle.COL_RED if bool(stats["psu_overloaded"]) else UIStyle.COL_BORDER, 8, 1, 12, 9
	))
	right.add_child(sum_card)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sum_card.add_child(sv)

	var sh_row := HBoxContainer.new()
	sh_row.add_theme_constant_override("separation", 8)
	sv.add_child(sh_row)

	var stitle := Label.new()
	stitle.text = "Slot %d: %s" % [_selected_slot + 1, str(GameState.ITEM_CATALOG[cur_type]["name"])]
	stitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(stitle, 16, UIStyle.COL_TEXT_MAIN, _display_font)
	sh_row.add_child(stitle)

	if cur_state == "crashed":
		var rep := Button.new()
		rep.text = "Reparieren"
		UIStyle.style_button(rep, Color(0.18, 0.30, 0.18), UIStyle.COL_GREEN)
		rep.pressed.connect(func(): GameState.request_repair_slot(_entity_id, _selected_slot, 1.0))
		sh_row.add_child(rep)

	var sell_m := Button.new()
	var sv_amt := int(roundf(float(stats["total_value"]) * GameState.SELL_REFUND_RATIO))
	sell_m.text = "Modul verkaufen (+$%d)" % sv_amt
	sell_m.disabled = (cur_state == "burning")
	UIStyle.style_button(sell_m, Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell_m.pressed.connect(func(): GameState.request_sell_slot_module(_entity_id, _selected_slot))
	sh_row.add_child(sell_m)

	var psu_note := "   •   NETZTEIL ZU SCHWACH" if bool(stats["psu_overloaded"]) else ""
	var spec_l := Label.new()
	spec_l.text = "CPU %d  •  RAM %d GB %s  •  GPU %d (%d GB)  •  Speicher %.1f TB  •  %d / %d W Netzteil%s" % [
		int(stats["cpu_score"]), int(stats["ram_gb"]), str(stats["ram_tag"]),
		int(stats["gpu_score"]), int(stats["vram_gb"]), float(stats["storage_tb"]),
		int(stats["watts"]), int(stats["psu_max_watts"]), psu_note
	]
	spec_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(spec_l, 12, UIStyle.COL_RED if bool(stats["psu_overloaded"]) else UIStyle.COL_TEXT_SUB)
	sv.add_child(spec_l)

	if not GameState.is_slot_upgradeable(cur_type):
		var sw := Label.new()
		sw.text = "Ein Rack-Switch benötigt keine internen Bauteile und leitet LAN automatisch an bis zu 3 weitere Racks weiter."
		sw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sw.modulate = UIStyle.COL_TEXT_SUB
		right.add_child(sw)
		return

	# 6 Category Tabs
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 5)
	right.add_child(cat_row)
	for cat_k in HardwareCatalog.CATEGORY_ORDER:
		var cm: Dictionary = HardwareCatalog.CATEGORY_META[cat_k]
		var stock_in_cat := 0
		for p in HardwareCatalog.get_category_parts(cat_k):
			stock_in_cat += GameState.get_part_stock(str((p as Dictionary)["id"]))
		var cbtn := Button.new()
		cbtn.text = "%s%s" % [str(cm["short"]).to_upper(), ("  (%d)" % stock_in_cat) if stock_in_cat > 0 else ""]
		cbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cbtn.custom_minimum_size = Vector2(0, 32)
		cbtn.add_theme_font_size_override("font_size", 12)
		_style_tab(cbtn, _selected_cat == cat_k)
		var cap_c: String = cat_k
		cbtn.pressed.connect(func():
			_selected_cat = cap_c
			_selected_filter = "Alle"
			SfxManager.play("click", -12.0, 1.15)
			_render_rack_view()
		)
		cat_row.add_child(cbtn)

	# Sub-Generation Filter Row (DDR2 | DDR3 | DDR4 | DDR5 etc.) + "Nur aus Lager" Toggle!
	var flt_row := HBoxContainer.new()
	flt_row.add_theme_constant_override("separation", 5)
	right.add_child(flt_row)
	var flts: Array = HardwareCatalog.CATEGORY_FILTERS.get(_selected_cat, ["Alle"])
	for flt_name in flts:
		var fn_str := str(flt_name)
		var fb := Button.new()
		fb.text = fn_str
		fb.custom_minimum_size = Vector2(0, 26)
		fb.add_theme_font_size_override("font_size", 11)
		var fsel := (_selected_filter == fn_str)
		UIStyle.style_button(fb, Color(0.17, 0.21, 0.25) if fsel else Color(0.115, 0.12, 0.13), UIStyle.COL_BLUE if fsel else UIStyle.COL_BORDER)
		fb.pressed.connect(func():
			_selected_filter = fn_str
			SfxManager.play("click", -13.0, 1.1)
			_render_rack_view()
		)
		flt_row.add_child(fb)

	var flt_sp := Control.new()
	flt_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flt_row.add_child(flt_sp)

	var stock_btn := Button.new()
	stock_btn.text = "Nur Lager" if not _only_in_stock else "Nur Lager: AN"
	stock_btn.custom_minimum_size = Vector2(118, 26)
	stock_btn.add_theme_font_size_override("font_size", 11)
	UIStyle.style_button(stock_btn, Color(0.16, 0.27, 0.16) if _only_in_stock else Color(0.115, 0.12, 0.13), UIStyle.COL_GREEN if _only_in_stock else UIStyle.COL_BORDER)
	stock_btn.pressed.connect(func():
		_only_in_stock = not _only_in_stock
		SfxManager.play("click", -12.0, 1.1)
		_render_rack_view()
	)
	flt_row.add_child(stock_btn)

	# Scrollable Filtered Parts List with Strength Bars & Warehouse Stock!
	var pscroll := ScrollContainer.new()
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(pscroll)
	var plist := VBoxContainer.new()
	plist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plist.add_theme_constant_override("separation", 6)
	pscroll.add_child(plist)

	var comps := HardwareCatalog.normalize_components(cur_slot.get("components", {}) as Dictionary, cur_type)
	var cur_pid := str(comps.get(_selected_cat, HardwareCatalog.DEFAULT_PARTS[_selected_cat]))
	var shown := 0

	for p in HardwareCatalog.get_category_parts(_selected_cat):
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

		var pcard := PanelContainer.new()
		var pbg := Color(0.11, 0.16, 0.11, 0.96) if installed else (Color(0.13, 0.145, 0.16, 0.96) if stock > 0 else UIStyle.COL_BG_CARD)
		var pbd := UIStyle.COL_GREEN if installed else (UIStyle.COL_GOLD_TEXT if stock > 0 else UIStyle.COL_BORDER)
		pcard.add_theme_stylebox_override("panel", UIStyle.make_panel(pbg, pbd, 6, 1, 10, 7))
		plist.add_child(pcard)

		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 10)
		pcard.add_child(prow)

		var pinfo := VBoxContainer.new()
		pinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pinfo.add_theme_constant_override("separation", 3)
		prow.add_child(pinfo)

		var plbl := Label.new()
		var stock_tag := ("   •   Im Lager: %d×" % stock) if stock > 0 else ""
		plbl.text = "[%s]  %s%s" % [str(pd.get("tag", "")), str(pd["name"]), stock_tag]
		plbl.add_theme_font_size_override("font_size", 13)
		plbl.modulate = UIStyle.COL_GREEN if installed else (UIStyle.COL_GOLD_TEXT if stock > 0 else UIStyle.COL_TEXT_MAIN)
		pinfo.add_child(plbl)

		# Clean Comparison Bar + Real Specs
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 8)
		pinfo.add_child(bar_row)
		var pbar := ProgressBar.new()
		pbar.min_value = 0.0
		pbar.max_value = 100.0
		pbar.value = HardwareCatalog.get_part_strength_pct(_selected_cat, pd)
		pbar.show_percentage = false
		pbar.custom_minimum_size = Vector2(90, 7)
		var bstyles := UIStyle.make_bar_styles(UIStyle.COL_GREEN if installed else UIStyle.COL_GOLD_TEXT)
		pbar.add_theme_stylebox_override("background", bstyles[0])
		pbar.add_theme_stylebox_override("fill", bstyles[1])
		bar_row.add_child(pbar)

		var pspec := Label.new()
		pspec.text = _format_catalog_part_specs(_selected_cat, pd)
		pspec.add_theme_font_size_override("font_size", 11)
		pspec.modulate = UIStyle.COL_TEXT_SUB
		bar_row.add_child(pspec)

		var ibtn := Button.new()
		ibtn.custom_minimum_size = Vector2(162, 34)
		if installed:
			ibtn.text = "VERBAUT"
			ibtn.disabled = true
			UIStyle.style_button(ibtn, Color(0.16, 0.26, 0.16), UIStyle.COL_GREEN)
		elif stock > 0 or is_default:
			ibtn.text = "Einbauen (Lager)" if stock > 0 else "Basis einbauen"
			ibtn.disabled = (cur_state == "burning")
			UIStyle.style_button(ibtn, Color(0.18, 0.30, 0.18), UIStyle.COL_GREEN)
			var cap_cat := _selected_cat
			var cap_pid := pid
			ibtn.pressed.connect(func():
				GameState.request_install_component(_entity_id, _selected_slot, cap_cat, cap_pid)
			)
		else:
			ibtn.text = "PC-Shop ($%d)" % int(pd["cost"])
			ibtn.disabled = true
			UIStyle.style_button(ibtn, Color(0.10, 0.12, 0.15), UIStyle.COL_BORDER)
		prow.add_child(ibtn)

	if shown == 0:
		var nl := Label.new()
		nl.text = "Keine passenden Bauteile im Teile-Lager! Kaufe CPUs, DDR2–DDR5 RAM, GPUs, SSDs & Netzteile im Windows-PC-Shop (Warenkorb) — der Cloud Express Sprinter liefert direkt in dein Lager!"
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.modulate = UIStyle.COL_TEXT_SUB
		plist.add_child(nl)


# ==============================================================================
# TAB 3: SPACIOUS 360° 3D HARDWARE WORKBENCH PREVIEW
# ==============================================================================
func _render_tab_preview(slots: Array) -> void:
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	_body_host.add_child(srow)
	for i in range(slots.size()):
		var sd: Dictionary = slots[i]
		var itype := str(sd["item_type"])
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 32)
		btn.text = "Slot %d: %s" % [i + 1, str(GameState.ITEM_CATALOG[itype]["name"]) if itype != "" else "Leer"]
		var is_sel := (i == _selected_slot)
		UIStyle.style_button(btn, Color(0.86, 0.58, 0.16, 0.24) if is_sel else UIStyle.COL_BG_CARD, UIStyle.COL_GOLD_TEXT if is_sel else UIStyle.COL_BORDER)
		var cap_i := i
		btn.pressed.connect(func():
			_selected_slot = cap_i
			SfxManager.play("click", -12.0, 1.1)
			_render_rack_view()
		)
		srow.add_child(btn)

	var cur_slot: Dictionary = slots[_selected_slot]
	var cur_type := str(cur_slot["item_type"])
	if cur_type == "":
		var el := Label.new()
		el.text = "Dieser Einschub ist leer — wähle oben einen belegten Slot für die drehbare 3D-Hardware-Ansicht!"
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.modulate = UIStyle.COL_TEXT_SUB
		_body_host.add_child(el)
		return

	var comps := HardwareCatalog.normalize_components(cur_slot.get("components", {}) as Dictionary, cur_type)
	var info_card := PanelContainer.new()
	info_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 8, 1, 14, 10))
	_body_host.add_child(info_card)
	var il := Label.new()
	if GameState.is_slot_upgradeable(cur_type):
		il.text = "VERBAUT IN SLOT %d:   CPU %s   •   RAM %s   •   GPU %s   •   Speicher %s   •   Kühlung %s   •   Netzteil %s" % [
			_selected_slot + 1,
			str(HardwareCatalog.get_part("cpu", str(comps["cpu"])).get("name", "-")),
			str(HardwareCatalog.get_part("ram", str(comps["ram"])).get("name", "-")),
			str(HardwareCatalog.get_part("gpu", str(comps["gpu"])).get("name", "-")),
			str(HardwareCatalog.get_part("storage", str(comps["storage"])).get("name", "-")),
			str(HardwareCatalog.get_part("cooling", str(comps["cooling"])).get("name", "-")),
			str(HardwareCatalog.get_part("psu", str(comps["psu"])).get("name", "-")),
		]
	else:
		il.text = "VERBAUT IN SLOT %d:   24-Port Managed Ethernet Switch (leitet LAN an 3 weitere Racks weiter)" % (_selected_slot + 1)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.add_theme_font_size_override("font_size", 12)
	il.modulate = UIStyle.COL_TEXT_MAIN
	info_card.add_child(il)


# ==============================================================================
# WALL ROUTER UPGRADE OVERLAY (Matching Slate & Gold, Real Mbit/s & Gbit/s!)
# ==============================================================================
func _render_router_view() -> void:
	_clear(_stat_strip)
	_clear(_tab_row)
	_clear(_body_host)
	_tab_row.visible = false
	_update_3d_preview("", {})

	var rt := clampi(GameState.router_tier, 0, GameState.ROUTER_TIERS.size() - 1)
	var cur: Dictionary = GameState.ROUTER_TIERS[rt]
	var used_ports := GameState.count_cables_on("network", GameState.WALL_ROUTER_ID)
	var max_ports := int(cur["ports"])
	var max_mbps := float(cur["max_mbps"])
	var bottleneck := GameState.used_bandwidth_mbps > max_mbps

	_title_lbl.text = "INTERNET-ROUTER  —  %s" % str(cur["label"])
	_subtitle_lbl.text = "Guthaben: $%.0f   •   Stufe %d / %d" % [GameState.money, rt + 1, GameState.ROUTER_TIERS.size()]

	_stat_strip.visible = true
	_add_stat_pill("GESCHWINDIGKEIT", str(cur["speed"]), UIStyle.COL_GOLD_TEXT)
	_add_stat_pill("AUSLASTUNG", "%s / %s" % [HardwareCatalog.format_speed_mbps(GameState.used_bandwidth_mbps), str(cur["speed"])], UIStyle.COL_RED if bottleneck else UIStyle.COL_GREEN)
	_add_stat_pill("LAN-PORTS", "%d / %d belegt" % [used_ports, max_ports], UIStyle.COL_AMBER if used_ports >= max_ports else UIStyle.COL_BLUE)
	_add_stat_pill("DDOS-SCHUTZ", "+%.0f%%" % ((float(cur["ddos_mult"]) - 1.0) * 100.0), UIStyle.COL_GREEN)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_GOLD_TEXT if rt + 1 < GameState.ROUTER_TIERS.size() else UIStyle.COL_GREEN, 8, 1, 16, 14))
	_body_host.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	if rt + 1 < GameState.ROUTER_TIERS.size():
		var nxt: Dictionary = GameState.ROUTER_TIERS[rt + 1]
		var cost := int(nxt["cost"])
		var h := Label.new()
		h.text = "NÄCHSTE ROUTER-STUFE:  %s" % str(nxt["label"])
		UIStyle.style_label(h, 16, UIStyle.COL_GOLD_TEXT, _display_font)
		v.add_child(h)

		var d := Label.new()
		d.text = "• Geschwindigkeit: %s  →  %s\n• LAN-Ports am Wand-Router: %d  →  %d Ports\n• DDoS-Schutz: +%.0f%%  →  +%.0f%%\n• Das 3D-Wandgerät entwickelt sich sichtbar mit!" % [
			str(cur["speed"]), str(nxt["speed"]), max_ports, int(nxt["ports"]),
			(float(cur["ddos_mult"]) - 1.0) * 100.0, (float(nxt["ddos_mult"]) - 1.0) * 100.0
		]
		d.add_theme_font_size_override("font_size", 13)
		d.modulate = UIStyle.COL_TEXT_MAIN
		v.add_child(d)

		var btn := Button.new()
		btn.text = "Auf %s upgraden  ($%d)" % [str(nxt["speed"]), cost]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = GameState.money < float(cost)
		UIStyle.style_button(btn, Color(0.76, 0.50, 0.12), UIStyle.COL_GOLD_TEXT)
		btn.pressed.connect(func(): GameState.request_upgrade_router())
		v.add_child(btn)
	else:
		var ml := Label.new()
		ml.text = "Höchste Stufe erreicht: 100-Gbit/s-Glasfaser-Anbindung"
		ml.add_theme_font_size_override("font_size", 16)
		ml.modulate = UIStyle.COL_GREEN
		v.add_child(ml)


# ==============================================================================
# COOLER / UPS / CART DEVICE OVERLAY (Matching Slate & Gold)
# ==============================================================================
func _render_device_view(kind: String) -> void:
	_clear(_stat_strip)
	_clear(_tab_row)
	_clear(_body_host)
	_stat_strip.visible = false
	_tab_row.visible = false
	_update_3d_preview("", {})

	var desc_txt := ""
	if kind == "cooler":
		var c: Dictionary = GameState.coolers[_entity_id]
		var ctype := str(c.get("cooler_type", "cooler"))
		var cat: Dictionary = GameState.ITEM_CATALOG[ctype]
		_title_lbl.text = "%s  —  %s" % [_entity_id.to_upper(), str(cat["name"])]
		desc_txt = "Status: %s\nKühlleistung: %.0f°C  •  Stromverbrauch: %d W" % [
			"AKTIV" if bool(c["powered"]) else "KEIN STROM (gelbe Buchse verkabeln!)",
			float(cat["heat"]), int(cat["watts"])
		]
	elif kind == "ups":
		var u: Dictionary = GameState.ups_units[_entity_id]
		_title_lbl.text = "%s  —  USV-Notstrom-Batterie" % _entity_id.to_upper()
		desc_txt = "Ladestand: %.0f%%  •  Status: %s\nÜbernimmt bei Blackout sofort unterbrechungsfrei die Stromversorgung!" % [
			float(u["charge"]),
			"ENTLÄDT (NOTSTROM!)" if bool(u.get("discharging", false)) else ("VERBUNDEN" if bool(u.get("connected", false)) else "NICHT VERKABELT")
		]
	elif kind == "cart":
		var k: Dictionary = GameState.carts[_entity_id]
		var items: Array = k.get("items", [])
		_title_lbl.text = "%s  —  Schwerlast-Rollwagen" % _entity_id.to_upper()
		desc_txt = "Beladung: %d / %d Pakete\nMit [E] schieben und bis zu 4 Pakete gleichzeitig durch das Gebäude transportieren!" % [items.size(), GameState.CART_MAX_ITEMS]

	var refund := GameState.get_device_sell_value(kind, _entity_id)
	_subtitle_lbl.text = "Guthaben: $%.0f   •   Restwert: $%d" % [GameState.money, refund]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 8, 1, 16, 14))
	_body_host.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var dl := Label.new()
	dl.text = desc_txt
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.style_label(dl, 14, UIStyle.COL_TEXT_MAIN)
	v.add_child(dl)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)

	if kind == "cooler" or kind == "ups":
		var pack_btn := Button.new()
		pack_btn.text = "Abbauen und in die Hand nehmen"
		pack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pack_btn.custom_minimum_size = Vector2(0, 40)
		UIStyle.style_button(pack_btn, Color(0.15, 0.19, 0.23), UIStyle.COL_BLUE)
		pack_btn.pressed.connect(func():
			GameState.request_pack_device(kind, _entity_id)
			close_requested.emit()
		)
		brow.add_child(pack_btn)

	var sell_btn := Button.new()
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.custom_minimum_size = Vector2(0, 40)
	sell_btn.text = ("WIRKLICH VERKAUFEN? (+$%d)" % refund) if _confirm_sell_entity else ("Verkaufen (+$%d)" % refund)
	UIStyle.style_button(sell_btn, Color(0.60, 0.16, 0.14) if _confirm_sell_entity else Color(0.28, 0.13, 0.14), UIStyle.COL_RED)
	sell_btn.pressed.connect(func():
		if not _confirm_sell_entity:
			_confirm_sell_entity = true
			SfxManager.play("click", -8.0, 0.9)
			_render_device_view(kind)
		else:
			GameState.request_sell_device(kind, _entity_id)
			close_requested.emit()
	)
	brow.add_child(sell_btn)


# ==============================================================================
# UI HELPERS & BUILD SHELL
# ==============================================================================
## Statuskachel: farbige Akzentleiste links, optional ein gezeichnetes Symbol, Beschriftung und Wert.
func _add_stat_pill(title: String, value_txt: String, accent: Color, icon_kind: String = "") -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_CARD, UIStyle.COL_BORDER, 4, 1, 0, 0))
	_stat_strip.add_child(card)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)

	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(3, 0)
	strip.color = accent
	h.add_child(strip)

	if not icon_kind.is_empty():
		h.add_child(_make_icon(icon_kind, accent, 18))

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 2)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 7)
	m.add_theme_constant_override("margin_bottom", 8)
	h.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	m.add_child(v)

	var tl := Label.new()
	tl.text = title
	UIStyle.style_label(tl, 10, UIStyle.COL_TEXT_SUB, _display_font)
	v.add_child(tl)

	var vl := Label.new()
	vl.text = value_txt
	vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(vl, 15, accent, _display_font)
	v.add_child(vl)


func _add_kv_line(parent: VBoxContainer, k: String, v_txt: String) -> void:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var kl := Label.new()
	kl.text = k
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyle.style_label(kl, 13, UIStyle.COL_TEXT_SUB)
	r.add_child(kl)
	var vl := Label.new()
	vl.text = v_txt
	UIStyle.style_label(vl, 13, UIStyle.COL_TEXT_MAIN, _display_font)
	r.add_child(vl)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(UIStyle.COL_BORDER, 0.35)
	parent.add_child(rule)


func _add_load_bar_row(parent: VBoxContainer, label_txt: String, val_txt: String, pct: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_txt
	l.custom_minimum_size = Vector2(142, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_label(l, 12, UIStyle.COL_TEXT_SUB)
	row.add_child(l)

	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = clampf(pct, 0.0, 100.0)
	pb.show_percentage = false
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size = Vector2(0, 8)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UIStyle.COL_RED if pct >= 90.0 else (UIStyle.COL_AMBER if pct >= 72.0 else UIStyle.COL_GREEN)
	var bstyles := UIStyle.make_bar_styles(col)
	pb.add_theme_stylebox_override("background", bstyles[0])
	pb.add_theme_stylebox_override("fill", bstyles[1])
	row.add_child(pb)

	var v := Label.new()
	v.text = val_txt
	v.custom_minimum_size = Vector2(148, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyle.style_label(v, 12, UIStyle.COL_RED if pct >= 90.0 else UIStyle.COL_TEXT_MAIN, _display_font)
	row.add_child(v)


func _format_catalog_part_specs(cat: String, pd: Dictionary) -> String:
	match cat:
		"cpu":
			return "Leistung %d Pkt.  •  %d W  •  +%.1f°C" % [int(pd.get("cpu_score", 0)), int(pd.get("watts", 0)), float(pd.get("heat", 0.0))]
		"ram":
			return "%d GB %s  •  %d W" % [int(pd.get("ram_gb", 0)), str(pd.get("tag", "")), int(pd.get("watts", 0))]
		"gpu":
			return "Leistung %d Pkt.  •  %d GB VRAM  •  %d W" % [int(pd.get("gpu_score", 0)), int(pd.get("vram_gb", 0)), int(pd.get("watts", 0))]
		"storage":
			return "%.1f TB  •  %d W" % [float(pd.get("storage_tb", 0.0)), int(pd.get("watts", 0))]
		"cooling":
			return "Kühlung %.1f°C  •  %d W" % [float(pd.get("heat", 0.0)), int(pd.get("watts", 0))]
		"psu":
			return "Max. %d W  •  Effizienz %+d%%" % [int(pd.get("psu_max_watts", 350)), int(roundf((1.0 - float(pd.get("watt_mult", 1.0))) * 100.0))]
	return ""


func _build_ui() -> void:
	_display_font = UIStyle.make_display_font(get_theme_default_font(), 0.5, 1)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.022, 0.026, 0.66)
	add_child(dim)
	dim.add_child(UIStyle.make_gradient_rect(
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.6)]),
		PackedFloat32Array([0.35, 1.0]),
		Vector2(0.5, 0.5), Vector2(1.05, 0.5), true
	))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(980, 620)
	_card.add_theme_stylebox_override("panel", UIStyle.make_panel(UIStyle.COL_BG_DARK, UIStyle.COL_BORDER, UIStyle.MAX_RADIUS, 1, 22, 18))
	center.add_child(_card)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	_card.add_child(root_v)

	# Kopfzeile: Logo, Titel, Untertitel, Schließen
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_v.add_child(header)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(36, 36)
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
	UIStyle.style_label(_title_lbl, 20, UIStyle.COL_TEXT_MAIN, _display_font, true)
	title_box.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyle.style_label(_subtitle_lbl, 12, UIStyle.COL_TEXT_SUB)
	title_box.add_child(_subtitle_lbl)

	var close_btn := Button.new()
	close_btn.text = "SCHLIESSEN  [ESC]"
	close_btn.custom_minimum_size = Vector2(160, 36)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIStyle.style_button(close_btn)
	close_btn.add_theme_font_override("font", _display_font)
	close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(close_btn)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(56, 2)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.color = UIStyle.COL_ACCENT
	root_v.add_child(accent)

	# Compact 4-Pill Status Strip
	_stat_strip = HBoxContainer.new()
	_stat_strip.add_theme_constant_override("separation", 10)
	root_v.add_child(_stat_strip)

	# Clean 3-Tab Navigation Bar
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	root_v.add_child(_tab_row)

	# Dynamic Body Container
	_body_host = VBoxContainer.new()
	_body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_host.add_theme_constant_override("separation", 10)
	root_v.add_child(_body_host)

	# Spacious 360° 3D Hardware Workbench Frame (shown ONLY on Tab 3!)
	_preview_frame = PanelContainer.new()
	_preview_frame.visible = false
	_preview_frame.custom_minimum_size = Vector2(0, 380)
	_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_frame.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.08, 0.095, 0.115, 0.98), UIStyle.COL_BORDER, 8, 1, 4, 4))
	root_v.add_child(_preview_frame)

	var vp_overlay := Control.new()
	vp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	vp_overlay.gui_input.connect(_on_preview_gui_input)
	_preview_frame.add_child(vp_overlay)

	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_overlay.add_child(vp_container)

	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.msaa_3d = Viewport.MSAA_2X
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp_container.add_child(_preview_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.115, 0.138)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.78, 0.84)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_vp.add_child(we)

	var key_l := DirectionalLight3D.new()
	key_l.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	key_l.light_energy = 1.6
	_preview_vp.add_child(key_l)

	var fill_l := DirectionalLight3D.new()
	fill_l.rotation_degrees = Vector3(-22.0, -138.0, 0.0)
	fill_l.light_energy = 0.7
	_preview_vp.add_child(fill_l)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.64, 0.92)
	cam.rotation_degrees = Vector3(-33.5, 0.0, 0.0)
	cam.fov = 38.0
	_preview_vp.add_child(cam)

	_preview_pivot = Node3D.new()
	_preview_vp.add_child(_preview_pivot)

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
	hint_lbl.text = "3D-WERKBANK   •   Linke Maustaste ziehen zum Drehen"
	UIStyle.style_label(hint_lbl, 11, UIStyle.COL_GOLD_TEXT, _display_font, true)
	hint_lbl.position = Vector2(12, 10)
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_overlay.add_child(hint_lbl)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_preview_dragging = event.pressed
	elif event is InputEventMouseMotion and _preview_dragging:
		_preview_yaw += event.relative.x * 0.012
		_preview_pitch = clampf(_preview_pitch + event.relative.y * 0.008, -0.45, 0.35)


func _update_3d_preview(item_type: String, comps: Dictionary) -> void:
	if _preview_frame == null or _preview_vp == null:
		return
	if item_type == "":
		_preview_frame.visible = false
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	_preview_frame.visible = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var sig := "%s:%s:%s:%s:%s:%s:%s" % [
		item_type,
		str(comps.get("cpu", "")),
		str(comps.get("gpu", "")),
		str(comps.get("ram", "")),
		str(comps.get("storage", "")),
		str(comps.get("cooling", "")),
		str(comps.get("psu", "")),
	]
	if _preview_sig == sig:
		return
	_preview_sig = sig

	_clear(_preview_model_holder)
	_preview_fans.clear()
	var srv := HardwareMeshFactory.build_open_server_chassis(item_type, comps, _preview_fans)
	_preview_model_holder.add_child(srv)


func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


func _section_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	UIStyle.style_label(l, 11, UIStyle.COL_GOLD_TEXT, _display_font)
	return l


func _make_icon(kind: String, col: Color, px: int) -> Control:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func() -> void: UIStyle.draw_icon(ic, kind, Rect2(Vector2.ZERO, ic.size), col))
	return ic


## Reiter: dunkle Fläche, der aktive Reiter bekommt eine Amber-Unterkante und Amber-Schrift.
func _style_tab(btn: Button, sel: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(UIStyle.COL_ACCENT, 0.14) if sel else Color(0.095, 0.10, 0.11, 0.92)
	normal.border_color = UIStyle.COL_ACCENT if sel else UIStyle.COL_BORDER
	normal.set_border_width_all(1)
	normal.border_width_bottom = 2 if sel else 1
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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_SUB
	btn.add_theme_color_override("font_color", fc)
	btn.add_theme_color_override("font_focus_color", fc)
	btn.add_theme_color_override("font_hover_color", UIStyle.COL_GOLD_TEXT if sel else UIStyle.COL_TEXT_MAIN)
	btn.add_theme_color_override("font_pressed_color", UIStyle.COL_GOLD_TEXT)
	btn.add_theme_font_override("font", _display_font)
