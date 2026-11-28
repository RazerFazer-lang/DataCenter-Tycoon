extends SceneTree
## Rund um die Garage: Kaffeevollautomat, Katze streicheln, Außenbeleuchtung, echte Aufnahmen,
## entfernte Mülltonne und doppelte Poller, Shop-Liste springt nach dem Warenkorb nicht nach oben.
## Aufruf: godot --headless --path . --script res://tests/garage_life_check.gd

const PORT := 7921

var bad := 0
var gs: Node
var dm: Node
var main: Node


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
	dm = root.get_node("DecorManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Tester", PORT, {}, "", "Garage", "", false, false)
	await wait(20)

	_check_sounds()
	await _check_coffee()
	await _check_cat()
	await _check_lights()
	_check_removed()
	await _check_shop_scroll()

	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").leave_session()
	quit(1 if bad > 0 else 0)


func _check_sounds() -> void:
	var sounds: Dictionary = root.get_node("SfxManager").get("_sounds")
	var meows := 0
	for i in range(1, 9):
		if sounds.get("meow_%d" % i) is AudioStreamOggVorbis:
			meows += 1
	chk("Katze: echte Miau-Aufnahmen", meows >= 5, meows)
	chk("Getränkeautomat: echte Kaffee-Aufnahme", sounds.get("coffee") is AudioStreamOggVorbis)
	var birds_ok := true
	for b in ["bird_sparrow", "bird_crow", "bird_swallow", "bird_wings"]:
		birds_ok = birds_ok and sounds.get(b) is AudioStreamOggVorbis
	chk("Vögel: echte Aufnahmen", birds_ok)
	chk("Tauben ohne erzeugtes Gurren", not sounds.has("bird_pigeon"))
	chk("Rolltor: echter Motor und Anschlag", sounds.get("garage_door_stop") is AudioStreamOggVorbis and root.get_node("SfxManager").call("get_loop_stream", "garage_door_motor") is AudioStreamOggVorbis)


func _check_coffee() -> void:
	var fx: Node = main.find_child("CoffeeFx_garage", true, false)
	chk("Kaffeevollautomat in der Garage ist benutzbar", fx != null and fx.find_children("*", "Area3D", true, false).size() == 1)
	var area: Area3D = fx.find_children("*", "Area3D", true, false)[0] if fx != null else null
	chk("[E] am Automaten: Kaffee kochen", area != null and str(area.get_meta("interact_type", "")) == "coffee_machine")
	gs.breaker_on = true
	(dm.get("buffs") as Dictionary).clear()
	chk("Text: kostenlos kochen", str(dm.brew_prompt("garage", 1)[0]).contains("kostenlos"))
	var m0: float = gs.money
	dm.request_brew("garage")
	await wait(2)
	chk("Brühen läuft", dm.is_brewing("garage"))
	chk("Kostet nichts", gs.money == m0)
	chk("Dampf steigt auf", bool((fx.get("_steam") as GPUParticles3D).emitting))
	chk("Echter Brüh-Ton", (fx.get("_audio") as AudioStreamPlayer3D).stream is AudioStreamOggVorbis)
	chk("Text während des Brühens", str(dm.brew_prompt("garage", 1)[0]).contains("läuft"))
	dm.call("_tick_brew", dm.BREW_SECS + 0.5)
	await wait(2)
	chk("Fertig: Kaffee-Bonus", not dm.is_brewing("garage") and dm.has_buff(1, "coffee"))
	chk("Gleich danach: wirkt noch", str(dm.brew_prompt("garage", 1)[0]).contains("wirkt noch"))
	dm.request_brew("garage")
	await wait(2)
	chk("Kein zweiter Kaffee, solange er wirkt", not dm.is_brewing("garage"))
	(dm.get("buffs") as Dictionary).clear()
	gs.breaker_on = false
	gs.ups_backup_active = false
	chk("Ohne Strom: kein Kaffee", str(dm.brew_prompt("garage", 1)[0]).contains("kein Strom"))
	dm.request_brew("garage")
	await wait(2)
	chk("Ohne Strom brüht nichts", not dm.is_brewing("garage"))
	gs.breaker_on = true


func _check_cat() -> void:
	var wl: Node = null
	for n in main.find_children("*", "Node3D", true, false):
		if n.has_method("pet_cat"):
			wl = n
	chk("Katze gefunden", wl != null)
	if wl == null:
		return
	var cat: Dictionary = wl.get("_cat")
	var cat_node: Node3D = cat["n"]
	cat_node.visible = true
	var areas := cat_node.find_children("*", "Area3D", true, false)
	chk("Katze hat [E] zum Streicheln", areas.size() == 1 and str(areas[0].get_meta("interact_type", "")) == "pet_cat")
	chk("Streicheln klappt", wl.call("pet_cat", cat_node.global_position + Vector3(0.8, 0, 0)))
	chk("Katze bleibt gestreichelt stehen", float(wl.get("_pet_t")) > 3.0)
	await wait(20)
	var purr: AudioStreamPlayer3D = wl.get("_purr")
	chk("Schnurren ist eine echte Aufnahme", purr != null and purr.stream is AudioStreamOggVorbis and (purr.stream as AudioStreamOggVorbis).loop)


func _check_lights() -> void:
	chk("Außenbeleuchtung ist ein Gebäude-Ausbau", gs.BUILDING_UPGRADE_CATALOG.has("upg_exterior_lights") and "upg_exterior_lights" in gs.BUILDING_UPGRADE_ORDER)
	var node: Node3D = main.find_child("ExteriorLights", true, false)
	chk("Ohne Ausbau keine Leuchten", node != null and not node.visible)
	gs.building_upgrades["upg_exterior_lights"] = true
	gs.building_upgrades_changed.emit()
	await wait(2)
	chk("Nach dem Ausbau sichtbar", node.visible)
	var lamps: Array = main.find_children("*", "Node3D", true, false).filter(func(n): return n.get_parent() == node and n is OmniLight3D)
	chk("Wand- und Wegleuchten", lamps.size() >= 11, lamps.size())
	gs.time_of_day = 0.95
	gs.weather_state = "clear"
	var builder: Node = node.get_parent()
	for i in 4:
		builder.call("_update_garage_lights", 1.0)
	var lit := lamps.filter(func(l): return (l as OmniLight3D).light_energy > 0.5).size()
	chk("Nachts brennen sie (wenn die Gartenlampen an sind)", lit == lamps.size() or not root.get_node("OutdoorManager").lamps_on(), [lit, root.get_node("OutdoorManager").lamps_on()])
	chk("Weniger Diebe mit Licht", dm.EXTERIOR_LIGHT_THIEF < 1.0)
	gs.building_upgrades.erase("upg_exterior_lights")
	gs.building_upgrades_changed.emit()


func _check_removed() -> void:
	var near_bin := 0
	var bollards := 0
	for n in main.find_children("*", "Node3D", true, false):
		var p: Vector3 = (n as Node3D).global_position
		if p.distance_to(Vector3(-3.35, 0.0, 5.35)) < 0.05 and n.get_parent() != null and n.get_parent().name.begins_with("Garage"):
			near_bin += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is CylinderMesh and absf(absf(p.x) - 2.45) < 0.01 and absf(p.z - 4.95) < 0.01:
			bollards += 1
	chk("Mülltonne am Tor ist weg", near_bin == 0)
	chk("Keine doppelten Poller am Tor", bollards == 0, bollards)


func _check_shop_scroll() -> void:
	var term: Node = main.get("terminal_ui")
	term.visible = true
	term.call("_open_app", "shop")
	await wait(30)
	var w: Node = term.get("_desktop").call("window", "shop")
	var left: ScrollContainer = w.get("body").find_children("*", "ScrollContainer", true, false)[0]
	left.scroll_vertical = 120
	await wait(3)
	var before := left.scroll_vertical
	term.call("_cart_add", "item", "rack", "", "Server-Rack", 500, 1)
	await wait(20)
	var now: ScrollContainer = w.get("body").find_children("*", "ScrollContainer", true, false)[0]
	chk("Shop: Liste springt beim Warenkorb nicht nach oben", before > 0 and absi(now.scroll_vertical - before) <= 2, [before, now.scroll_vertical])
	gs.shopping_cart.clear()
	term.visible = false
