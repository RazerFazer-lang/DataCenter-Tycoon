extends SceneTree
## Lieferschein mit echter Unterschrift: Inhalt, Fahrer wartet, Unterschrift prüfen, Overlay mit Zeichenfeld.
## Aufruf: godot --headless --path . --script res://tests/delivery_note_check.gd

const PORT := 7913

var bad := 0
var gs: Node
var main: Node
var DN: GDScript


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	await process_frame
	gs = root.get_node("GameState")
	DN = load("res://scripts/data/delivery_note.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Tester", PORT, {}, "", "Lieferschein", "", false, false)
	await wait(20)

	_check_rules()
	await _check_flow()
	await _check_unsigned()

	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").leave_session()
	quit(1 if bad > 0 else 0)


func _check_rules() -> void:
	chk("leer ist keine Unterschrift", not DN.valid_signature([]))
	chk("ein Punkt ist keine Unterschrift", not DN.valid_signature([PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.52, 0.5)])]))
	chk("außerhalb des Feldes zählt nicht", not DN.valid_signature([PackedVector2Array([Vector2(0.1, 0.5), Vector2(3.0, 0.5)])]))
	chk("falscher Typ zählt nicht", not DN.valid_signature("unterschrift") and not DN.valid_signature([[0.1, 0.2]]))
	var many := PackedVector2Array()
	for i in DN.MAX_POINTS + 10:
		many.append(Vector2(fmod(float(i) * 0.013, 1.0), 0.5))
	chk("zu viele Punkte zählen nicht", not DN.valid_signature([many]))
	chk("echte Unterschrift zählt", DN.valid_signature(DN.test_signature()), DN.ink(DN.test_signature()))
	var a: Array = DN.driver_signature(42)
	var b: Array = DN.driver_signature(42)
	chk("Fahrer unterschreibt immer gleich", a.size() == b.size() and a[0] == b[0] and a[0] != DN.driver_signature(43)[0])


func _start_trip(cargo: Array, parcel: Array) -> void:
	gs.money = 50000.0
	gs.van_phase = "idle"
	gs.van_cargo = cargo.duplicate()
	gs._van_parcel_parts = parcel.duplicate()
	gs._start_delivery_van()
	var t := 0.0
	while gs.van_trip_phase != "sign" and t < 400.0:
		gs._update_delivery_van(0.25)
		t += 0.25


func _check_flow() -> void:
	_start_trip(["parts_parcel", "rack", "bulk:web_server:3", "cart"], ["acc:fuse", "acc:screw_box"])
	chk("Fahrer wartet auf die Unterschrift", gs.van_phase == "unloading" and gs.van_trip_phase == "sign")
	var doc: Dictionary = gs.van_plan.get("doc", {})
	chk("Lieferschein hat Nummer, Fahrer und Kennzeichen", str(doc.get("no", "")).begins_with("LS-") and str(doc.get("driver", "")) != "" and str(doc.get("plate", "")).begins_with("VRN-CE"), doc.get("no", ""))
	var lines: Array = doc.get("lines", [])
	chk("jede Ware steht auf dem Schein", lines.size() == 4, lines.size())
	var by_name := {}
	for ln in lines:
		by_name[str(ln["name"])] = ln
	chk("Sammelpaket mit Teilezahl", str(by_name.get("Sammelpaket Bauteile & Zubehör", {}).get("extra", "")) == "2 Teile")
	var web := str(gs.ITEM_CATALOG["web_server"]["name"])
	chk("Sammelkiste mit Menge 3", int(by_name.get(web, {}).get("qty", 0)) == 3, by_name.keys())
	chk("Gewicht geschätzt", int(doc.get("kg", 0)) > 30 and int(doc.get("packages", 0)) == 4, doc.get("kg", 0))
	chk("Empfänger ist die eigene Firma", str(doc.get("company", "")) == str(gs.current_save_name))
	# Overlay öffnen: Fahrer wartet, solange der Schein in der Hand ist.
	var ui: Control = main.get("delivery_note_ui")
	main.call("_open_delivery_note")
	await wait(4)
	chk("Lieferschein-Fenster ist offen", ui.visible and gs.van_sign_peer == 1, gs.van_sign_peer)
	var lp0: Node = main.get("world").local_player
	chk("Maus frei, Spieler steht", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and (lp0 == null or bool(lp0.get("ui_locked"))))
	for i in 200:
		gs._update_delivery_van(0.25)
	chk("Fahrer wartet, solange unterschrieben wird", gs.van_trip_phase == "sign")
	var btn: Button = ui.get("_sign_btn")
	chk("Unterschreiben geht erst mit Unterschrift", btn.disabled)
	# Mit der Maus unterschreiben
	var pad: Control = ui.get("_pad")
	chk("Zeichenfeld hat eine Größe", pad.size.x > 200.0 and pad.size.y > 60.0, pad.size)
	var amp: float = _draw_on(pad)
	chk("Stift kratzt beim Schreiben hörbar", pad.get("_audio") != null and amp > 0.1, amp)
	await wait(2)
	chk("Tinte reicht für eine Unterschrift", pad.call("ink") >= DN.MIN_INK, pad.call("ink"))
	chk("jetzt geht Unterschreiben", not btn.disabled)
	var rep0: float = gs.reputation
	var m0: float = gs.money
	ui.call("_on_sign")
	await wait(4)
	chk("unterschrieben: Fahrer steigt ein", gs.van_trip_phase == "enter" and gs.money > m0 and gs.reputation > rep0)
	chk("Name steht im Plan", str(gs.van_plan.get("signed_by", "")) == "Tester", gs.van_plan.get("signed_by", ""))
	chk("Stempel ist zu sehen", (ui.get("_stamp") as Control).visible)
	await create_timer(2.0).timeout
	await wait(3)
	chk("Fenster schließt sich danach", not ui.visible)
	var lp: Node = main.get("world").local_player
	chk("Spieler kann wieder laufen", lp == null or not bool(lp.get("ui_locked")))
	var t := 0.0
	while gs.van_phase != "idle" and t < 80.0:
		gs._update_delivery_van(0.25)
		t += 0.25
	var mail: Dictionary = root.get_node("MailManager").mails[0]
	chk("Mail nennt Lieferschein und Unterschrift", JSON.stringify(mail.get("body", [])).contains("unterschrieben von") and JSON.stringify(mail.get("body", [])).contains(str(doc["no"])))


func _draw_on(pad: Control) -> float:
	var sz: Vector2 = pad.size
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(sz.x * 0.08, sz.y * 0.6)
	pad.call("_gui_input", down)
	for i in 60:
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = Vector2(sz.x * (0.08 + i * 0.012), sz.y * (0.55 + 0.3 * sin(i * 0.6)))
		pad.call("_gui_input", mv)
	var amp: float = pad.get("_amp_target")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(sz.x * 0.8, sz.y * 0.6)
	pad.call("_gui_input", up)
	return amp


func _check_unsigned() -> void:
	_start_trip(["web_server"], [])
	var nm: Node = root.get_node("NetworkManager")
	# Ein Mitspieler hat den Schein in der Hand: Man kommt nicht dazwischen.
	nm.players[777] = {"name": "Bert"}
	gs.van_sign_peer = 777
	var ui: Control = main.get("delivery_note_ui")
	main.call("_open_delivery_note")
	await wait(2)
	chk("besetzt: Fenster bleibt zu", not ui.visible)
	var m0: float = gs.money
	gs.request_sign_delivery(DN.test_signature())
	await wait(2)
	chk("besetzt: man kann nicht dazwischen unterschreiben", gs.van_trip_phase == "sign" and gs.money == m0)
	# Mitspieler geht: Der Fahrer ist wieder frei.
	nm.players.erase(777)
	gs._update_delivery_van(0.25)
	chk("Mitspieler weg: Schein wieder frei", gs.van_sign_peer == 0)
	# Öffnen und zurückgeben ohne Unterschrift
	main.call("_open_delivery_note")
	await wait(3)
	ui.call("close")
	await create_timer(0.5).timeout
	await wait(2)
	chk("zurückgegeben: niemand hält den Schein", gs.van_sign_peer == 0 and not ui.visible)
	var t := 0.0
	while gs.van_phase != "idle" and t < 120.0:
		gs._update_delivery_van(0.25)
		t += 0.25
	var mail: Dictionary = root.get_node("MailManager").mails[0]
	chk("ohne Unterschrift: Ware trotzdem da, Mail sagt es", gs.van_phase == "idle" and JSON.stringify(mail.get("body", [])).contains("Niemand hat unterschrieben"))
