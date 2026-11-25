extends SceneTree
## Prüft Roadmap-Paket D: Bauteil-Modelle, Figuren und Editor, Außenbereich, Dach, Garten, Jahreszeiten, Natur.
## Aufruf: godot --headless --path . --script res://tests/paketd_check.gd

var bad := 0
var gs: Node
var om: Node
var dm: Node
var nm: Node
var st: Node
var main: Node
var world: Node
var p: Node
var me := 1
var ow: Node


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func secs(s: float) -> void:
	await create_timer(s).timeout


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	gs = root.get_node("GameState")
	om = root.get_node("OutdoorManager")
	dm = root.get_node("DecorManager")
	nm = root.get_node("NetworkManager")
	st = root.get_node("SettingsManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	nm.call("_start_host_internal", "Test", 7855, {}, "", "PaketD", "", false, false)
	await wait(20)
	me = root.multiplayer.get_unique_id()
	gs.money = 50000.0
	gs.room_level = 1
	gs.time_of_day = 0.5
	gs._weather_timer = 9999.0
	world = main.get("world")
	p = world.local_player
	for n in root.find_children("*", "OutdoorWorld", true, false):
		ow = n
	_parts()
	await _figures()
	await _skins()
	await _walk()
	await _gate()
	await _units()
	await _roof()
	await _garden()
	await _seasons()
	await _wild()
	await _ladder()
	await _save()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


# ---------------------------------------------------------------- Bauteile

func _parts() -> void:
	var HC: GDScript = load("res://scripts/data/hardware_catalog.gd")
	var PM: GDScript = load("res://scripts/world/part_models.gd")
	var miss: Array = []
	var miss_m: Array = []
	var total := 0
	var cat: Dictionary = HC.get_script_constant_map().get("PARTS", {}) if HC != null else {}
	if cat.is_empty() and "PARTS_CATALOG" in gs:
		cat = gs.PARTS_CATALOG
	for c in cat.keys():
		for e in (cat[c] as Dictionary).keys() if cat[c] is Dictionary else (cat[c] as Array):
			var id: String = str(e["id"]) if e is Dictionary else str(e)
			if id == "" or id == "none" or id.begins_with("none"):
				continue
			total += 1
			if not PM.has_product(id):
				miss.append(id)
			if not PM.has_mount(id):
				miss_m.append(id)
	chk("Jedes Bauteil hat ein eigenes Modell", miss.is_empty() and total >= 180, [total, miss])
	chk("Einbauvarianten", miss_m.size() <= 1, miss_m)
	var fans: Array = []
	var n: Node3D = PM.product("gpu_rtx4090", fans)
	chk("Grafikkarte mit drehenden Lüftern", n != null and fans.size() >= 2, fans.size())
	if n != null:
		n.free()


# ---------------------------------------------------------------- Figuren

func _figures() -> void:
	var HM: GDScript = load("res://scripts/world/human_model.gd")
	var HR: GDScript = load("res://scripts/world/human_rig.gd")
	var h = HM.create(HM.DEFAULT)
	root.add_child(h)
	chk("Figur lädt mit Skelett", h.skeleton != null and h.rig != null)
	chk("Alle Teile des Aussehens vorhanden", h._parts.has("Face") and h._parts.has("Top_Hoodie") and h._parts.has("Bottom_Jeans"), h._parts.size())
	# Füße bleiben beim Stehen am Boden, Hände vor dem Körper beim Tragen
	h.rig.base = "carry_box"
	for i in 60:
		h.rig.update(0.033)
	var l: Transform3D = h.rig.hand_transform(true)
	var r: Transform3D = h.rig.hand_transform(false)
	chk("Beide Hände vorn am Karton", l.origin.z < -0.2 and r.origin.z < -0.2 and absf(l.origin.y - r.origin.y) < 0.08, [l.origin, r.origin])
	h.rig.base = ""
	var lo := 9.0
	for i in 120:
		h.rig.velocity = Vector2(0, 1.5)
		h.rig.update(0.033)
		var fy: float = (h.skeleton.global_transform * h.skeleton.get_bone_global_pose(h.skeleton.find_bone("LeftFoot"))).origin.y
		lo = minf(lo, fy)
	chk("Fuß sinkt beim Gehen nicht ein", lo > 0.05 and lo < 0.14, lo)
	var okp := true
	for a in HR.ACTIONS.keys():
		h.rig.play(str(a), Vector3(0, 0.8, 0.4))
		for i in 20:
			h.rig.update(0.05)
		for b in h.skeleton.get_bone_count():
			if not h.skeleton.get_bone_global_pose(b).is_finite():
				okp = false
	chk("Alle Handlungen rechnen sauber", okp, HR.ACTIONS.size())
	for b in HR.BASES:
		h.rig.base = str(b)
		for i in 20:
			h.rig.update(0.05)
		for k in h.skeleton.get_bone_count():
			if not h.skeleton.get_bone_global_pose(k).is_finite():
				okp = false
	chk("Alle Haltungen rechnen sauber", okp, HR.BASES.size())
	h.queue_free()
	var bad_look: Dictionary = HM.sanitize({"v": 2, "tone": 99, "hair": "x", "jaw": -50, "top": 3.7})
	chk("Aussehen wird begrenzt", int(bad_look["tone"]) == 7 and int(bad_look["hair"]) == int(HM.DEFAULT["hair"]) and int(bad_look["jaw"]) == 0)
	var old: Dictionary = HM.sanitize({"jacket": 3, "pants": 1, "tone": 2, "hair": 3, "shoes": 0, "accent": 1, "headwear": 2, "glasses": 1})
	chk("Altes Aussehen wird übernommen", int(old["v"]) == 2 and int(old["hat"]) == 1 and int(old["glasses"]) == 2)
	for j in ["delivery", "technician", "builder", "guard", "thief"]:
		var x = HM.create(HM.job_look(j, 4))
		chk("Beruf %s" % j, x._parts.size() > 8)
		x.free()
	chk("Eigene Figur wirft nur Schatten", p.human_model() != null and (p.human_model().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	chk("Arme in der Ich-Ansicht", p._fp != null and p._fp.human != null)
	p._fp.play("wave")
	for i in 20:
		p._fp.update(0.05)
	chk("Winken zeigt die Hand", p._fp.visible)
	# Mitspieler
	var PC: GDScript = load("res://scripts/world/player_controller.gd")
	var rp = PC.new()
	rp.setup(77, false, "Mia", Color(0.3, 0.7, 0.9), world)
	rp.apply_skin(HM.random_look(3))
	world.add_child(rp)
	rp.apply_remote_pose(Vector3(1, 0, 1), 0.0, 0.0, 3, false)
	await wait(40)
	chk("Mitspieler duckt sich", rp.human_model().rig._crouch > 0.5)
	rp.apply_remote_pose(Vector3(1, 0, 1), 0.0, 0.0, 2, false)
	await wait(60)
	chk("Mitspieler sitzt und tippt", rp.human_model().rig._seat > 0.6 and rp.human_model().rig.base == "type")
	rp.play_remote_action("press", Vector3(0, 1.0, 0.4))
	chk("Handlung beim Mitspieler", rp.human_model().rig.is_playing())
	rp.queue_free()
	await wait(2)


func _skins() -> void:
	var HM: GDScript = load("res://scripts/world/human_model.gd")
	var look: Dictionary = HM.random_look(12)
	nm.update_my_skin(look)
	await wait(5)
	chk("Aussehen im Spiel ändern", int(p.skin_data["hair"]) == int(look["hair"]) and int((nm.players[me]["skin"] as Dictionary)["top_a"]) == int(look["top_a"]))
	st.set_skin(look)
	st.save_outfit(2, "Testoutfit", look)
	st.load_settings()
	chk("Aussehen gespeichert", int(st.get_skin()["tone"]) == int(look["tone"]))
	chk("Outfit gespeichert", st.outfits.size() >= 3 and str((st.outfits[2] as Dictionary).get("name", "")) == "Testoutfit")
	st.delete_outfit(2)
	chk("Outfit gelöscht", (st.outfits[2] as Dictionary).is_empty())
	main._open_avatar(false)
	await wait(5)
	chk("Editor am Spind offen", main.avatar_ui.visible and p.ui_locked and p.at_locker)
	var pan = main.avatar_ui.panel
	for t in ["body", "face", "hair", "clothes", "extras", "outfits"]:
		pan._show_tab(t)
		await wait(2)
		chk("Reiter %s gefüllt" % t, pan._page.get_child_count() > 2, pan._page.get_child_count())
	pan._change("hat", 3)
	chk("Helm aufgesetzt", (pan._human._parts["Hat_Helmet"] as MeshInstance3D).visible)
	pan._randomize()
	await secs(0.9)
	chk("Änderung gespeichert", int(st.get_skin()["top"]) == int(pan.look["top"]))
	main.avatar_ui.close()
	await wait(3)
	chk("Beim Schließen verteilt", int(p.skin_data["top"]) == int(pan.look["top"]) and int(p.skin_data["top_a"]) == int(pan.look["top_a"]))
	chk("Editor zu, Spiel läuft", not main.avatar_ui.visible and not p.ui_locked)
	chk("Spind steht in der Garage", not get_nodes_in_group("locker_prop").is_empty())
	# Gesten
	var EW: GDScript = load("res://scripts/ui/emote_wheel.gd")
	chk("Zwölf Gesten", EW.EMOTES.size() == 12)
	gs.request_player_emote("dance")
	await wait(3)
	chk("Geste läuft", p.human_model().rig.is_playing())
	var w = EW.new()
	root.add_child(w)
	w.open()
	w.move(Vector2(0, -80))
	chk("Gesten-Rad oben = Winken", w.close() == "wave")
	w.queue_free()


# ---------------------------------------------------------------- Laufen

func _ray(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not (p as Node3D).get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Läuft die Kapsel des Spielers von a nach b? Rest-Abstand zurück.
func _go(a: Vector3, b: Vector3, steps: int = 200) -> float:
	p.set_physics_process(false)
	p.global_position = a
	await physics_frame
	for i in steps:
		var d: Vector3 = b - p.global_position
		d.y = 0.0
		if d.length() < 0.15:
			break
		p.velocity = d.normalized() * 6.0 + Vector3(0, p.velocity.y - 13.5 / 60.0 if not p.is_on_floor() else -0.5, 0)
		p.move_and_slide()
		await physics_frame
	var rest: float = Vector2(p.global_position.x - b.x, p.global_position.z - b.z).length()
	p.set_physics_process(true)
	return rest


func _walk() -> void:
	chk("Außenwelt gebaut", ow != null)
	om.state["gate"] = false
	om.state["door"] = true
	ow._gate_u = 1.0
	ow._door_u = 1.0
	await wait(20)
	chk("Aus dem Tor auf die Straße", await _go(Vector3(0, 0.1, 6.5), Vector3(0, 0, 14.5)) < 0.3)
	chk("Straße bis zum Gehweg gegenüber", await _go(Vector3(0, 0.1, 14.5), Vector3(0, 0, 19.3)) < 0.3, p.global_position)
	chk("Straße nach Westen bis zur Querstraße", await _go(Vector3(-5, 0.1, 14.5), Vector3(-39, 0, 14.5), 500) < 0.3, p.global_position)
	chk("Hinter der Querstraße ist Schluss", await _go(Vector3(-38, 0.1, 14.5), Vector3(-46, 0, 14.5), 120) > 2.0)
	chk("Hinter dem Gehweg ist Schluss", await _go(Vector3(5, 0.1, 18), Vector3(5, 0, 24), 100) > 2.0)
	chk("Vorn links um die Ecke", await _go(Vector3(-3.4, 0.1, 8.0), Vector3(-6.6, 0, 5.6)) < 0.3, p.global_position)
	chk("Westseite nach hinten", await _go(Vector3(-6.6, 0.1, 2.0), Vector3(-6.7, 0, -5.4)) < 0.3, p.global_position)
	chk("Rückseite entlang", await _go(Vector3(-4.0, 0.1, -6.4), Vector3(20.5, 0, -6.4), 400) < 0.3, p.global_position)
	chk("Ostseite nach vorn", await _go(Vector3(23.4, 0.1, -5.0), Vector3(23.4, 0, 6.0)) < 0.3, p.global_position)
	chk("Durch die Hintertür hinein", await _go(Vector3(-7.2, 0.1, 3.65), Vector3(-4.4, 0, 3.65)) < 0.3, p.global_position)
	om.state["door"] = false
	ow._door_u = 0.0
	await wait(4)
	chk("Geschlossene Hintertür hält", await _go(Vector3(-7.2, 0.1, 3.65), Vector3(-4.4, 0, 3.65), 90) > 1.0)
	chk("Zaun hält", await _go(Vector3(-9.0, 0.1, -3.0), Vector3(-14.0, 0, -3.0), 90) > 2.0)
	chk("Westwand sonst dicht", await _go(Vector3(-7.2, 0.1, -2.0), Vector3(-4.0, 0, -2.0), 90) > 1.0)
	p.global_position = Vector3(0, 0.1, 2.0)
	var OW: GDScript = load("res://scripts/world/outdoor_world.gd")
	chk("Draußen erkannt", OW.is_outside(Vector3(-8, 0, 0)) and OW.is_outside(Vector3(8, 5, 0)) and not OW.is_outside(Vector3(0, 0, 0)))
	chk("Ablegen auf dem Rasen bleibt draußen", gs._clamp_drop_pos(Vector3(-8.5, 0, 1.5)).distance_to(Vector3(-8.5, 0, 1.5)) < 0.1)
	chk("Ablegen in der Halle bleibt drin", gs._clamp_drop_pos(Vector3(-5.5, 0, 0)).x >= -5.0)
	chk("Ablegen auf der Straße wird zurückgeholt", gs._clamp_drop_pos(Vector3(2, 0, 16)).z <= 8.9)


func _gate() -> void:
	om.state["gate"] = false
	om.do_use("gate", me)
	chk("Tor schließt", bool(om.state["gate"]))
	await secs(3.8)
	chk("Geschlossenes Tor hält", await _go(Vector3(0, 0.1, 8.5), Vector3(0, 0, 13.0), 90) > 1.5)
	om.do_use("gate", me, true)
	chk("Nachtautomatik umgeschaltet", not bool(om.state["gate_auto"]))
	om.do_use("gate", me, true)
	var f: float = om.thief_factor()
	om.state["gate"] = false
	chk("Tor schützt vor Dieben", f < om.thief_factor() * 0.3, f)
	var l: float = om.thief_factor()
	om.state["lamps"] = false
	chk("Licht schützt vor Dieben", l < om.thief_factor())
	om.state["lamps"] = true
	gs.time_of_day = 0.9
	om._last_night = false
	om.tick(1.0)
	chk("Nachts von allein zu", bool(om.state["gate"]))
	chk("Lampen nachts an", om.lamps_on())
	gs.van_phase = "arriving"
	gs.van_site = "garage"
	om.tick(1.0)
	chk("Für die Lieferung auf", not bool(om.state["gate"]))
	SecurityClear()
	om.do_use("gate", me)
	chk("Bei Lieferung nicht schließbar", not bool(om.state["gate"]))
	gs.van_phase = "idle"
	gs.time_of_day = 0.5
	om.tick(1.0)
	om._last_night = false
	om.force_gate_open()


func SecurityClear() -> void:
	root.get_node("SecurityGuard").clear_peer(me)


func _units() -> void:
	var cid: String = gs._alloc_id("cooler")
	gs.coolers[cid] = {"id": cid, "cooler_type": "cooler", "pos": Vector3(5.0, 0, 6.2), "rot_y": 0.0, "powered": true, "connected": true}
	gs.day_number = 10
	om._last_day = 10
	chk("Herbst", om.season_index() == 2, om.season())
	for i in 40:
		om.tick(60.0)
	chk("Laub setzt das Gerät zu", om.clog(cid) > 0.5, om.clog(cid))
	chk("Zugesetztes Gerät kühlt schwächer", om.unit_factor(cid) < 0.85, om.unit_factor(cid))
	om.changed.emit()
	chk("Laubhaufen zu sehen", ow._units.has(cid))
	SecurityClear()
	om.do_use("unit:" + cid, me)
	chk("Gereinigt", om.clog(cid) == 0.0 and om.unit_factor(cid) == 1.0)
	gs.coolers.erase(cid)
	om.tick(1.0)
	chk("Verkauftes Gerät vergessen", not (om.state["clog"] as Dictionary).has(cid))


func _roof() -> void:
	SecurityClear()
	var m0: float = gs.money
	om.state["solar"] = false
	om.do_use("solar", me)
	chk("Solaranlage gekauft", bool(om.state["solar"]) and gs.money < m0 - 2000.0, m0 - gs.money)
	gs.time_of_day = 0.5
	gs.day_number = 6
	gs.weather_state = "clear"
	om.state["snow"] = 0.0
	chk("Mittags liefert sie", om.solar_output() > 0.9 and om.power_mult() < 0.75, om.solar_output())
	gs.time_of_day = 0.05
	chk("Nachts nicht", om.solar_output() == 0.0)
	gs.time_of_day = 0.5
	om.state["solar_dirt"] = 1.0
	chk("Schmutz kostet Leistung", om.solar_output() < 0.4)
	om.do_use("solar", me)
	chk("Geputzt", float(om.state["solar_dirt"]) == 0.0)
	om._last_weather = "clear"
	gs.weather_state = "storm"
	om.tick(1.0)
	chk("Sturm verstellt die Schüssel", float(om.state["dish"]) < 0.8, om.state["dish"])
	om.state["dish"] = 0.4
	chk("Ohne Signal kein Bonus", om.dish_bonus() == 0.0)
	SecurityClear()
	om.do_use("dish", me)
	om.do_use("dish", me)
	chk("Nachgestellt", om.dish_bonus() > 0.0, om.state["dish"])
	gs.weather_state = "clear"
	gs._weather_timer = 30.0
	gs.weather_next = ""
	gs._tick_weather(0.1)
	chk("Wetterstation sagt voraus", gs.weather_next != "", gs.weather_next)
	var nx: String = gs.weather_next
	gs._tick_weather(31.0)
	chk("Vorhersage trifft ein", gs.weather_state == nx, gs.weather_state)
	gs.weather_state = "clear"
	gs._weather_timer = 9999.0
	for e in [["solar", "outdoor"], ["dish", "outdoor"], ["station", "outdoor"], ["gate", "outdoor"], ["door", "outdoor"], ["lamps", "outdoor"], ["grill", "outdoor"], ["feeder", "outdoor"], ["bed:0", "outdoor"], ["bench", "bench"], ["ladder", "ladder"]]:
		var t: Array = load("res://scripts/world/outdoor_prompts.gd").prompt_for(e[0], e[1])
		chk("Hinweis %s" % e[0], str(t[0]) != "" and not str(t[0]).contains("%s") and not str(t[0]).contains("%d"), t[0])


func _garden() -> void:
	SecurityClear()
	gs.day_number = 6
	om._last_day = 6
	om.do_use("bed:0", me)
	chk("Gepflanzt", str(om.state["beds"][0]["p"]) != "", om.state["beds"][0])
	for i in 60:
		om.state["beds"][0]["w"] = 1.0
		om.tick(60.0)
	chk("Gewachsen", float(om.state["beds"][0]["g"]) >= 1.0)
	om.changed.emit()
	chk("Pflanzen zu sehen", ow._plants[0] != null)
	var m0: float = gs.money
	om.do_use("bed:0", me)
	chk("Geerntet", gs.money > m0 + 20.0 and str(om.state["beds"][0]["p"]) == "")
	om.do_use("bed:1", me)
	om.state["beds"][1]["w"] = 0.0
	var g0: float = om.state["beds"][1]["g"]
	om.tick(60.0)
	chk("Ohne Wasser wächst nichts", float(om.state["beds"][1]["g"]) == g0)
	SecurityClear()
	om.do_use("bed:1", me)
	chk("Gegossen", float(om.state["beds"][1]["w"]) > 0.9)
	om.do_use("grill", me)
	chk("Grill an", float(om.state["grill_t"]) > 0.0)
	om.tick(30.0)
	chk("Essen fertig", float(om.state["grill_t"]) <= 0.0 and int(om.state["grill_left"]) == 4)
	om.do_use("grill", me)
	chk("Gegessen: Stärkung", dm.has_buff(me, "food") and int(om.state["grill_left"]) == 3 and dm.work_mult(me, Vector3(100, 0, 0)) < 0.95)
	om.do_use("feeder", me)
	chk("Futter nachgefüllt", float(om.state["feed"]) > 0.95)
	var r0: float = gs.reputation
	gs.reputation = 40.0
	om._run_day()
	chk("Ruf steigt durch Vögel und Garten", gs.reputation > 40.3, gs.reputation)
	gs.reputation = r0
	dm.buffs.erase(me)
	om.do_use("bench", me)
	chk("Bank: ausgeruht", dm.has_buff(me, "rest"))


func _seasons() -> void:
	var N: GDScript = load("res://scripts/world/nature.gd")
	var names: Array = []
	for i in 4:
		gs.day_number = 2 + i * 4
		gs.time_of_day = 0.5
		names.append(om.season_label())
	chk("Vier Jahreszeiten", names.size() == 4 and names[0] != names[2] and names[1] != names[3], names)
	gs.day_number = 14
	om._last_day = 14
	gs.weather_state = "rain"
	chk("Im Winter schneit es", om.is_snowing() and gs.get_weather_label() != tr("Regen"), gs.get_weather_label())
	om.state["snow"] = 0.0
	for i in 100:
		om.tick(1.0)
	chk("Schnee bleibt liegen", float(om.state["snow"]) > 0.9, om.state["snow"])
	gs.day_number = 18
	om._last_day = 18
	gs.weather_state = "clear"
	for i in 130:
		om.tick(1.0)
	chk("Im Frühling taut es", float(om.state["snow"]) < 0.05, om.state["snow"])
	N.update(2.2, 0.0, 0.06, 1.4)
	var maple: Color = N.leaf_mat("maple").get_shader_parameter("col_a")
	N.update(1.2, 0.0, 0.06, 1.4)
	var maple2: Color = N.leaf_mat("maple").get_shader_parameter("col_a")
	chk("Ahorn im Herbst rot, im Sommer grün", maple.r > maple.g * 2.0 and maple2.g > maple2.r * 1.5, [maple, maple2])
	N.update(3.3, 1.0, 0.06, 1.4)
	chk("Im Winter kahl", float(N.leaf_mat("maple").get_shader_parameter("amount")) < 0.05 and float(N.leaf_mat("pine").get_shader_parameter("amount")) > 0.9)
	gs.day_number = 6
	chk("Keine Hitzewelle im Winter", om.SEASON_TEMP[3] < 0.0)
	for sp in N.SPECIES:
		var t: Node3D = N.tree(sp, Vector3.ZERO)
		chk("Baum %s" % sp, t.find_children("*", "MeshInstance3D", true, false).size() >= 2)
		t.free()


func _wild() -> void:
	var w = ow.wildlife
	gs.time_of_day = 0.5
	gs.weather_state = "clear"
	gs.day_number = 6
	await secs(0.5)
	chk("Vögel da", w._birds.size() >= 15 and w.count_visible() >= 15, w.count_visible())
	var b: Dictionary = w._birds[0]
	b["state"] = "sit"
	b["t"] = 99.0
	(b["n"] as Node3D).position = p.global_position + Vector3(0.5, 0, 0)
	await secs(0.3)
	chk("Vogel flieht vor dem Spieler", str(b["state"]) == "fly")
	gs.time_of_day = 0.02
	await secs(0.3)
	chk("Nachts schlafen die Vögel", w.count_visible() == 0)
	gs.day_number = 6
	chk("Igel kommt nachts", (w._hedgehog["n"] as Node3D).visible)
	gs.time_of_day = 0.5
	await secs(3.0)
	var ok := true
	for x in w._birds:
		if not (x["n"] as Node3D).position.is_finite() or (x["n"] as Node3D).position.length() > 90.0:
			ok = false
	chk("Vögel bleiben in der Gegend", ok)
	var cat: Node3D = w._cat["n"]
	chk("Katze läuft herum", cat.visible and cat.position.is_finite())


func _ladder() -> void:
	p.set_ui_locked(false)
	p.global_position = Vector3(3.4, 0.1, -6.0)
	p.start_ladder(false)
	chk("An der Leiter", p.on_ladder)
	Input.action_press("move_forward")
	await secs(3.4)
	Input.action_release("move_forward")
	chk("Oben auf dem Dach", not p.on_ladder and p.global_position.y > 4.2, p.global_position)
	await secs(0.6)
	chk("Dach trägt", p.global_position.y > 4.2 and p.is_on_floor(), p.global_position)
	chk("Über das Dach zur Schüssel", await _go(p.global_position, Vector3(-2.4, 0, -3.4), 240) < 0.4 and p.global_position.y > 4.2, p.global_position)
	chk("Geländer hält", await _go(Vector3(0, 4.6, 3.6), Vector3(0, 0, 8.0), 90) > 2.5 and p.global_position.y > 4.2, p.global_position)
	p.global_position = Vector3(3.4, 4.5, -4.2)
	p.start_ladder(true)
	p._head_pivot.rotation.x = 0.0
	Input.action_press("move_back")
	await secs(3.4)
	Input.action_release("move_back")
	chk("Wieder unten", not p.on_ladder and p.global_position.y < 0.6, p.global_position)
	# Bank
	var bench: Node3D = null
	for a in ow.get_children():
		if a is Area3D and str(a.get_meta("interact_type", "")) == "bench":
			bench = a
	p.global_position = bench.global_position + Vector3(0, 0.1, 1.2)
	p.sit_on_bench(bench)
	await secs(1.2)
	chk("Sitzt auf der Bank", p.seat_kind == "bench" and Vector2(p.global_position.x - bench.global_position.x, p.global_position.z - bench.global_position.z).length() < 0.6, p.global_position)
	Input.action_press("move_forward")
	await secs(0.5)
	Input.action_release("move_forward")
	chk("Steht wieder auf", p.seat_kind == "")


func _save() -> void:
	om.state["gate_auto"] = false
	om.state["solar"] = true
	om.state["beds"][2] = {"p": "berry", "g": 0.5, "w": 0.4}
	var snap: Dictionary = gs.build_snapshot()
	var js: Dictionary = JSON.parse_string(JSON.stringify(snap["outdoor"]))
	om.reset()
	chk("Zurückgesetzt", not bool(om.state["solar"]))
	om.load_data(js)
	chk("Geladen", bool(om.state["solar"]) and not bool(om.state["gate_auto"]) and str(om.state["beds"][2]["p"]) == "berry" and absf(float(om.state["beds"][2]["g"]) - 0.5) < 0.01)
	om.load_data({"snow": NAN, "beds": "x", "clog": {"a": 7.0}, "grill_t": -5, "next_plant": 44})
	chk("Kaputte Daten werden begrenzt", float(om.state["snow"]) == 0.0 and (om.state["beds"] as Array).size() == 3 and float(om.state["clog"]["a"]) == 1.0 and int(om.state["next_plant"]) == 2)
	om.load_data({})
	chk("Alte Spielstände ohne Außenbereich", not bool(om.state["gate"]) and float(om.state["dish"]) == 1.0)
