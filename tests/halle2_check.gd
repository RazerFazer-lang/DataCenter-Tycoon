extends SceneTree
## Prüft die neue Halle Nord (v3.8): Kauf mit Bautrupp, Abschnitte, Verteiler und Ports, Platzierung,
## eigene Temperatur, Ausbauten nur am passenden PC und die Übernahme alter Spielstände (Migration 7).
## Aufruf: godot --headless --path . --script res://tests/halle2_check.gd

var bad := 0
var gs: Node
var nm: Node
var main: Node
var world: Node
var p: Node3D
## Erst zur Laufzeit laden: beim Kompilieren des Tests gibt es GameState noch nicht.
var HL: GDScript


func chk(n: String, ok: bool, x: Variant = "") -> void:
	print("PASS  " if ok else "FAIL  ", n, "  ", x)
	if not ok:
		bad += 1


func wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	gs = root.get_node("GameState")
	nm = root.get_node("NetworkManager")
	HL = load("res://scripts/data/halle_nord_layout.gd")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	nm.call("_start_host_internal", "Test", 7857, {}, "", "Halle2", "", false, false)
	await wait(20)
	world = main.get("world")
	p = world.local_player
	gs._weather_timer = 9999.0
	await _buy_flow()
	await _sections()
	await _placement()
	_temperature()
	await _pc_lists()
	_migration()
	print("ERGEBNIS Fehler ", bad)
	quit(1 if bad > 0 else 0)


func _o() -> Vector3:
	return gs.HALLE_NORD_ORIGIN


# ---------------------------------------------------------------- Kauf und Bautrupp

func _buy_flow() -> void:
	chk("Halle anfangs nicht da", not gs.halle_nord_owned and HL.sections() == 0)
	gs.company_level = 2
	gs.money = 50000.0
	gs.request_buy_halle_nord()
	await wait(3)
	chk("unter Stufe 3 kein Kauf", not gs.is_construction_active("upg_nord_hall") and gs.money == 50000.0)
	gs.company_level = 3
	gs.request_buy_halle_nord()
	await wait(3)
	chk("Kauf kostet 12.000", is_equal_approx(gs.money, 38000.0), gs.money)
	chk("Bautrupp baut, Halle noch zu", gs.is_construction_active("upg_nord_hall") and not gs.halle_nord_owned)
	chk("Garagen-PC-Liste zeigt den Hallenbau nicht", not _site_list("garage").has("upg_nord_hall") and not _site_list("halle_nord").has("upg_nord_hall"))
	p.call("teleport_between_sites")
	await wait(3)
	chk("kein Shuttle während des Baus", p.global_position.z > -100.0)
	gs._tick_constructions(999.0)
	await wait(3)
	chk("Schlüsselübergabe: Halle gehört uns", gs.halle_nord_owned and HL.sections() == 1)
	chk("Bau zählt zum Firmenwert", gs.get_company_value() >= int(gs.money) + gs.HALLE_NORD_COST)


func _site_list(site: String) -> Array:
	var out := []
	for uid in gs.BUILDING_UPGRADE_ORDER:
		if gs.upgrade_site(uid) == site:
			out.append(uid)
	return out


# ---------------------------------------------------------------- Abschnitte, Strom, Netz

func _sections() -> void:
	var b1: String = gs.HALL_NORD_BREAKER_IDS[0]
	var b2: String = gs.HALL_NORD_BREAKER_IDS[1]
	chk("Verteiler 1 mit 16 Dosen", gs.get_max_ports("power", b1) == 16)
	chk("Verteiler 2 noch nicht nutzbar", not gs._Cables._is_valid_cable_endpoint("power", b2))
	chk("Core-Switch 16 Ports", gs.get_max_ports("network", gs.HALL_NORD_ROUTER_ID) == 16)
	gs._recalculate_networks_and_metrics()
	var base_w: int = int(gs.POWER_TIERS[gs.power_tier]["watts"])
	chk("Abschnitt 1 bringt 4.500 W", gs.max_watts == base_w + 4500, gs.max_watts)
	gs.company_level = 3
	chk("Abschnitt 2 erst ab Stufe 4", gs.upgrade_block_reason("upg_nord_section_2") != "")
	chk("Abschnitt 3 braucht Abschnitt 2", gs.upgrade_block_reason("upg_nord_section_3") != "")
	gs.company_level = 6
	chk("Abschnitt 2 ab Stufe 4 baubar", gs.can_build_upgrade("upg_nord_section_2"))
	gs.money = 100000.0
	gs.request_buy_building_upgrade("upg_nord_section_2")
	await wait(3)
	chk("Abschnitt 2 kostet 9.000", is_equal_approx(gs.money, 91000.0), gs.money)
	gs._tick_constructions(999.0)
	await wait(3)
	chk("2 Abschnitte offen", HL.sections() == 2)
	chk("Verteiler 2 jetzt nutzbar", gs._Cables._is_valid_cable_endpoint("power", b2) and gs.get_max_ports("power", b2) == 12)
	chk("Core-Switch 28 Ports", gs.get_max_ports("network", gs.HALL_NORD_ROUTER_ID) == 28)
	gs._recalculate_networks_and_metrics()
	chk("2 Abschnitte bringen 9.000 W", gs.max_watts == base_w + 9000, gs.max_watts)
	var socks: Array = world.get_socket_positions("power", b2)
	chk("Steckdosen von Verteiler 2 sitzen am Verteiler", socks.size() == 12 and (socks[0] as Vector3).distance_to(_o() + HL.BREAKER_POS[1]) < 1.2)
	var nsocks: Array = world.get_socket_positions("network", gs.HALL_NORD_ROUTER_ID)
	chk("Core-Ports sitzen am Schrank", nsocks.size() == 28 and (nsocks[27] as Vector3).distance_to(_o() + HL.CORE_POS) < 1.6)
	var builder: Node = main.find_child("HalleNord", true, false)
	chk("Trennwand zu Abschnitt 2 weg, zu Abschnitt 3 da", builder != null and not builder._partitions[0].visible and builder._partitions[1].visible)


# ---------------------------------------------------------------- Platzierung

func _placement() -> void:
	var o := _o()
	chk("Rack in Abschnitt 1 erlaubt", gs.can_place_at(o + Vector3(-6.0, 0.0, -1.0)))
	chk("nicht in der Technikecke", not gs.can_place_at(o + Vector3(-10.5, 0.0, -5.0)))
	chk("nicht im Büro", not gs.can_place_at(o + Vector3(-10.5, 0.0, 5.0)))
	chk("nicht vor dem Rolltor", not gs.can_place_at(o + Vector3(-7.0, 0.0, 6.0)))
	chk("in Abschnitt 2 erlaubt", gs.can_place_at(o + Vector3(1.0, 0.0, 0.5)))
	chk("Abschnitt 3 noch zu", not gs.can_place_at(o + Vector3(8.0, 0.0, 0.5)))
	chk("nicht vor Verteiler 2", not gs.can_place_at(o + Vector3(0.0, 0.0, -5.9)))
	# Spieler an der Halle: Kollision der offenen Trennwand ist weg
	p.global_position = o + Vector3(-6.0, 0.15, 0.0)
	await wait(4)
	p.velocity = Vector3.ZERO
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o + Vector3(-6.0, 1.0, 0.0), o + Vector3(2.0, 1.0, 0.0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	chk("Weg durch offenen Abschnitt frei", hit.is_empty(), hit.get("position", ""))
	q = PhysicsRayQueryParameters3D.create(o + Vector3(2.0, 1.0, 0.0), o + Vector3(9.0, 1.0, 0.0))
	q.collision_mask = 1
	hit = space.intersect_ray(q)
	chk("Trennwand zu Abschnitt 3 hält auf", not hit.is_empty() and absf((hit["position"] as Vector3).x - o.x - 4.0) < 0.3, hit.get("position", ""))


# ---------------------------------------------------------------- Temperatur

func _temperature() -> void:
	gs.room_temp = 30.0
	gs.nord_room_temp = 50.0
	chk("Temperatur je Standort", is_equal_approx(gs.site_temp(_o()), 50.0) and is_equal_approx(gs.site_temp(Vector3(1, 0, 0)), 30.0))
	gs.room_temp = 22.0
	gs.nord_room_temp = 22.0


# ---------------------------------------------------------------- Ausbauten nur am passenden PC

func _pc_lists() -> void:
	var t: Node = main.get("terminal_ui")
	p.global_position = Vector3(2.5, 0.15, -1.5)
	await wait(3)
	var garage_txt := _app_text(t)
	chk("Garagen-PC zeigt Garagen-Ausbauten", garage_txt.contains("Außenbeleuchtung") and garage_txt.contains("Fernwärme"))
	chk("Garagen-PC zeigt keine Hallen-Ausbauten", not garage_txt.contains("Pförtnerhaus") and not garage_txt.contains("Abschnitt 3") and not garage_txt.contains("NOC"))
	p.global_position = _o() + HL.ARRIVAL
	await wait(3)
	var nord_txt := _app_text(t)
	chk("PC in Halle Nord zeigt Hallen-Ausbauten", nord_txt.contains("Pförtnerhaus") and nord_txt.contains("Abschnitt 3") and nord_txt.contains("NOC"))
	chk("PC in Halle Nord zeigt keine Garagen-Ausbauten", not nord_txt.contains("Außenbeleuchtung") and not nord_txt.contains("Halle B"))


func _app_text(t: Node) -> String:
	if t._active_app == "upgrades":
		t._open_app("mail")
	t._open_app("upgrades")
	var body: Node = t._desktop.window("upgrades").body
	var out := ""
	for n in body.find_children("*", "", true, false):
		if n is Label:
			out += (n as Label).text + "\n"
		elif n is Button:
			out += (n as Button).text + "\n"
	return out


# ---------------------------------------------------------------- Alte Spielstände (Migration 7)

func _migration() -> void:
	var o := _o()
	gs.building_upgrades.erase("upg_nord_hall")
	gs.building_upgrades.erase("upg_nord_section_2")
	gs.building_upgrades.erase("upg_nord_section_3")
	gs.halle_nord_owned = true
	var rid := "rack_mig_test"
	gs.racks[rid] = {"id": rid, "pos": o + Vector3(-10.4, 0.0, -5.2), "rot_y": 0.0, "slots": [], "temp": 22.0, "rack_type": "rack"}
	var SM: GDScript = load("res://scripts/autoload/game_state/save_migrations.gd")
	var res: Array = SM.call("_v7_halle_nord_neu")
	chk("alte Halle: alle 3 Abschnitte offen", HL.sections() == 3)
	var np: Vector3 = gs.racks[rid]["pos"]
	chk("Rack aus der Technikecke gerückt", int(res[0]) >= 1 and gs.can_place_at(np, rid), np - o)
	gs.racks.erase(rid)
