extends SceneTree
## Code & Technik (TEC-01..05) ohne zweiten Spieler:
## Spielstand-Schema und Migrationen (TEC-02), Bereichsmodule von GameState (TEC-01),
## Datenklassen um Racks, Leisten und Kabel (TEC-03), entfernte Modelle (TEC-04), Zeilenenden (TEC-05).
## Aufruf: godot --headless --path . --script res://tests/code_technik_check.gd

const PORT := 7907

var bad := 0
var gs: Node
var sm: Node
var main: Node
var events: Array[String] = []


func chk(label: String, ok: bool, extra: Variant = "") -> void:
	if not ok:
		bad += 1
	print("PASS  " if ok else "FAIL  ", label, "  ", extra)


func wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	gs = root.get_node("GameState")
	sm = root.get_node("SaveManager")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	root.get_node("NetworkManager").call("_start_host_internal", "Test", PORT, {}, "", "CodeTechnik", "", false, false)
	await wait(20)
	gs.event_logged.connect(func(msg: String, _sev: String) -> void: events.append(msg))
	gs.money = 50000.0

	_check_schema_table()
	await _check_schema_load()
	if has_method("_check_modules"):
		await call("_check_modules")
	if has_method("_check_data_classes"):
		await call("_check_data_classes")
	if has_method("_check_removed_models"):
		call("_check_removed_models")
	if has_method("_check_line_endings"):
		call("_check_line_endings")

	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").leave_session()
	quit(1 if bad > 0 else 0)


# --- TEC-02: Spielstand-Schema ---

func _check_schema_table() -> void:
	var keys: Array = SaveSchema.STEPS.keys()
	keys.sort()
	var want: Array = []
	for v in range(1, SaveSchema.CURRENT + 1):
		want.append(v)
	chk("Schema: eine Migration je Version 1..%d" % SaveSchema.CURRENT, keys == want, keys)
	var stages_ok := true
	for v in keys:
		var s: Array = SaveSchema.STEPS[v]
		if s.size() != 3 or not (str(s[1]) in ["data", "world"]) or str(s[2]).is_empty():
			stages_ok = false
	chk("Schema: jede Migration hat Version, Zeitpunkt und Beschreibung", stages_ok)
	chk("Schema: alter Spielstand ohne Nummer ist Version 0", SaveSchema.version_of({}) == 0)
	chk("Schema: Unsinn ist Version 0", SaveSchema.version_of({"schema": "drei"}) == 0 and SaveSchema.version_of({"schema": -4}) == 0)
	chk("Schema: Kommazahl aus JSON wird gelesen", SaveSchema.version_of({"schema": 3.0}) == 3)
	chk("Schema: Version 0 braucht alle Migrationen", SaveSchema.pending(0, "data").size() + SaveSchema.pending(0, "world").size() == SaveSchema.CURRENT)
	chk("Schema: aktueller Stand braucht keine", SaveSchema.pending(SaveSchema.CURRENT, "data").is_empty() and SaveSchema.pending(SaveSchema.CURRENT, "world").is_empty())
	chk("Schema: nur die neueren laufen", Array(SaveSchema.pending(4, "world")) == [5], SaveSchema.pending(4, "world"))


func _count_strip_crates() -> int:
	var n := 0
	for c in gs.crates.values():
		if str(c.get("item_type", "")) == "prop_power_strip":
			n += int(c.get("pack_count", 1))
	return n


func _check_schema_load() -> void:
	var data: Dictionary = gs.export_save_data()
	chk("Speichern schreibt die Schema-Nummer", int(data.get("schema", -1)) == SaveSchema.CURRENT, data.get("schema"))
	var r: Dictionary = sm.save_world("codetechnik", "CodeTechnik", data)
	var l: Dictionary = sm.load_world_file("codetechnik")
	chk("Schema-Nummer übersteht Speichern und Laden", r.get("ok", false) and SaveSchema.version_of(l.get("state", {})) == SaveSchema.CURRENT)

	# Aktueller Spielstand mit einem Feld, das nur alte Spielstände hatten: Migration 3 darf nicht laufen.
	var cur: Dictionary = data.duplicate(true)
	cur["power_strips"] = 2
	var before := _count_strip_crates()
	gs.load_from_save_data(cur, "codetechnik", "CodeTechnik")
	await wait(5)
	chk("Aktueller Spielstand: keine alte Migration", _count_strip_crates() == before, [before, _count_strip_crates()])

	# Derselbe Inhalt als alter Spielstand ohne Nummer: Migration 3 macht aus 2 montierten Leisten eine Kiste.
	var old: Dictionary = data.duplicate(true)
	old.erase("schema")
	old["power_strips"] = 2
	old.erase("room_level")
	old["room_expanded"] = true
	old.erase("carts")
	gs.load_from_save_data(old, "codetechnik", "CodeTechnik")
	await wait(5)
	chk("Alter Spielstand: montierte Leisten werden Kiste", _count_strip_crates() == before + 2, [before, _count_strip_crates()])
	chk("Alter Spielstand: Raumstufe aus room_expanded", gs.room_level == 1, gs.room_level)
	chk("Alter Spielstand: Startwagen", gs.carts.size() == 1, gs.carts.size())
	chk("Nach dem Laden wird mit aktueller Nummer gespeichert", int(gs.export_save_data().get("schema", -1)) == SaveSchema.CURRENT)

	# Alle Migrationen haben eine Funktion.
	var M: GDScript = load("res://scripts/autoload/game_state/save_migrations.gd")
	var probe: Dictionary = gs.export_save_data()
	probe.erase("carts")
	var ran: Array = []
	ran.append_array(M.run(probe, 0, "data"))
	ran.append_array(M.run(probe, 0, "world"))
	ran.sort()
	var all: Array = SaveSchema.STEPS.keys()
	all.sort()
	chk("Jede Migration hat eine Funktion", ran == all, ran)

	# Spielstand aus einer neueren Version: lädt, warnt aber.
	var newer: Dictionary = data.duplicate(true)
	newer["schema"] = SaveSchema.CURRENT + 3
	events.clear()
	gs.load_from_save_data(newer, "codetechnik", "CodeTechnik")
	await wait(5)
	var warned := false
	for e in events:
		if e.contains("neueren Spielversion"):
			warned = true
	chk("Neuerer Spielstand lädt mit Warnung", warned and gs.racks.size() == (data.get("racks", {}) as Dictionary).size(), events)
	gs.load_from_save_data(data.duplicate(true), "codetechnik", "CodeTechnik")
	await wait(5)


# --- TEC-01: Bereichsmodule ---

const MODULES: Array[String] = ["power", "cables", "delivery", "racks", "contracts", "save_migrations"]


func _check_modules() -> void:
	var gs_script: Script = gs.get_script()
	var consts: Dictionary = gs_script.get_script_constant_map()
	var props := {}
	for p in gs.get_property_list():
		props[str(p["name"])] = true
	var access := RegEx.create_from_string(r"GameState\.([A-Za-z_][A-Za-z0-9_]*)")
	# Zeichenketten und Kommentare zählen nicht als Zugriff.
	var noise := RegEx.create_from_string(r'"(?:[^"\\\n]|\\.)*"|#[^\n]*')
	var total := 0
	var missing: Array[String] = []
	for m in MODULES:
		var path := "res://scripts/autoload/game_state/%s.gd" % m
		var s: GDScript = load(path)
		chk("Modul %s lädt" % m, s != null and s.can_instantiate())
		if s == null:
			continue
		var own_vars: Array[String] = []
		for p in s.get_script_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				own_vars.append(str(p["name"]))
		chk("Modul %s hat keinen eigenen Zustand" % m, own_vars.is_empty(), own_vars)
		var not_static: Array[String] = []
		for f in s.get_script_method_list():
			if (int(f["flags"]) & METHOD_FLAG_STATIC) == 0:
				not_static.append(str(f["name"]))
		chk("Modul %s: nur statische Funktionen" % m, not_static.is_empty(), not_static)
		var src := noise.sub(FileAccess.get_file_as_string(path), "", true)
		for r in access.search_all(src):
			var n := r.get_string(1)
			total += 1
			if not (gs.has_method(n) or gs.has_signal(n) or consts.has(n) or props.has(n)):
				missing.append("%s: %s" % [m, n])
	chk("Jeder GameState-Zugriff der Module trifft ein echtes Feld (%d Zugriffe)" % total, missing.is_empty() and total > 1000, missing)
	var gs_lines := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd").split("\n").size()
	chk("game_state.gd ist aufgeteilt (%d Zeilen)" % gs_lines, gs_lines < 8000, gs_lines)
	var rpc_cfg: Variant = gs_script.get_rpc_config()
	var rpc_n: int = (rpc_cfg as Dictionary).size() if rpc_cfg is Dictionary else 0
	chk("Alle 113 Netzwerkaufrufe bleiben auf GameState", rpc_n == 113 and (rpc_cfg as Dictionary).has("_rpc_req_connect_cable") and (rpc_cfg as Dictionary).has("_rpc_sync_van_state"), rpc_n)
	chk("Weiterleitung Strom", gs.is_strip_type("prop_power_strip") and not gs.is_strip_type("rack"))
	chk("Weiterleitung Kabel", gs.get_max_ports("power", gs.WALL_BREAKER_ID) == gs.BREAKER_BASE_SOCKETS)
	chk("Weiterleitung Einkauf", gs.get_cart_total() == 0)
	chk("Weiterleitung Racks", (gs._make_rack_data("rack_x", "rack", Vector3.ZERO, 0.0)["slots"] as Array).size() == 4)
	chk("Weiterleitung Verträge", gs.get_active_contract_count() >= 0 and not gs.get_reputation_label().is_empty())

	# Zusammenspiel der Module: Rack am Kasten (Kabel) bekommt Strom (Strom) und zählt als Rack (Racks).
	var rid := "rack_ct"
	gs.racks[rid] = gs._make_rack_data(rid, "rack", Vector3(1.0, 0.0, 1.0), 0.0)
	gs.cables["cable_ct"] = CableData.make("cable_ct", CableData.POWER, gs.WALL_BREAKER_ID, 0, rid, 0)
	gs.breaker_on = true
	gs._recalculate_networks_and_metrics()
	chk("Rack am Kasten hat Strom", RackData.of(gs.racks[rid]).powered, gs.racks[rid].get("powered"))
	chk("Kabel wird an der Buchse gefunden", str(gs.get_cable_on_slot("power", rid, 0).get("id", "")) == "cable_ct")
	chk("Kabel zählt", gs.count_cables_on("power", rid) == 1)


# --- TEC-03: Datenklassen ---

func _check_data_classes() -> void:
	var d := CableData.make("c_t", CableData.POWER, "a", 1, "b", 2)
	var c := CableData.of(d)
	chk("CableData liest", c.id == "c_t" and c.is_power() and c.from_slot == 1 and c.other_end("b") == "a" and c.slot_at("b") == 2 and c.slot_at("x") == -1)
	c.set_slot_at("a", 5)
	c.to_slot = 7
	chk("CableData schreibt ins Dictionary", int(d["from_slot"]) == 5 and int(d["to_slot"]) == 7)
	chk("CableData prüft", CableData.problems(d).is_empty() and CableData.problems({"id": "x", "cable_type": "strom", "from_id": "a", "to_id": "a"}).size() == 2)

	var rd: Dictionary = gs._make_rack_data("rack_t", "rack", Vector3(1, 0, 2), 0.5)
	var r := RackData.of(rd)
	chk("RackData liest", r.id == "rack_t" and r.slot_count() == 4 and r.slot(0).is_empty() and r.used_slots().is_empty() and r.pos == Vector3(1, 0, 2) and r.rental_type == "none")
	r.slot(1).item_type = "web_server"
	chk("SlotData schreibt ins Rack", Array(r.used_slots()) == [1] and str(rd["slots"][1]["item_type"]) == "web_server")
	chk("Einschub außerhalb ist leer", r.slot(9).is_empty() and r.slot(-1).is_empty())
	chk("RackData prüft", RackData.problems(rd).is_empty() and not RackData.problems({"id": "x", "pos": "da", "slots": [{"state": 3}]}).is_empty())
	var old := {"id": "rack_o", "slots": []}
	RackData.fill_defaults(old)
	chk("Fehlende Felder alter Racks werden ergänzt", str(old["rental_type"]) == "none" and float(old["satisfaction"]) == 100.0 and old["metrics"] is Dictionary)

	var sd := {"id": "decor_t", "item_type": StripData.POWER_TYPE, "pos": Vector3.ZERO}
	var s := StripData.of(sd)
	chk("StripData liest", s.is_power() and s.on and not s.wall and not s.tripped and s.cable_type() == CableData.POWER and StripData.problems(sd).is_empty())
	s.on = false
	chk("StripData schreibt ins Dictionary", sd["on"] == false)
	chk("StripData erkennt Leisten", StripData.is_strip(sd) and not StripData.is_strip({"item_type": "prop_sofa"}))

	# Lesen über die Hülle verändert nichts, Spielstand und Netzwerk sehen dieselben Daten.
	var snap := var_to_str(gs.racks) + var_to_str(gs.cables) + var_to_str(gs.decor_items)
	var bad_entries: Array[String] = []
	for rk in gs.racks:
		var rr := RackData.of(gs.racks[rk])
		var _x: Variant = [rr.custom_name, rr.rack_type, rr.pos, rr.temp, rr.services, rr.metrics, rr.used_slots()]
		for i in rr.slot_count():
			var sl := rr.slot(i)
			_x = [sl.state, sl.components, sl.faulty_part, sl.boot_left, sl.offline]
		for p in RackData.problems(gs.racks[rk]):
			bad_entries.append("%s: %s" % [rk, p])
	for ck in gs.cables:
		var cc := CableData.of(gs.cables[ck])
		var _y: Variant = [cc.from_id, cc.to_id, cc.from_slot, cc.to_slot]
		for p in CableData.problems(gs.cables[ck]):
			bad_entries.append("%s: %s" % [ck, p])
	for dk in gs.decor_items:
		if StripData.is_strip(gs.decor_items[dk]):
			for p in StripData.problems(gs.decor_items[dk]):
				bad_entries.append("%s: %s" % [dk, p])
	chk("Lesen über die Hülle ändert nichts", snap == var_to_str(gs.racks) + var_to_str(gs.cables) + var_to_str(gs.decor_items))
	chk("Alle Racks, Kabel und Leisten der Welt sind gültig", bad_entries.is_empty(), bad_entries)


# --- TEC-04 / TEC-05 ---

const REMOVED_MODELS: Array[String] = ["delivery_van", "delivery_truck_medium", "delivery_truck_heavy", "decor_storage_shelf", "workshop_storage_shelf", "ext_tree_oak", "ext_tree_pine"]


func _check_removed_models() -> void:
	var left: Array[String] = []
	for id in REMOVED_MODELS:
		if ResourceLoader.exists("res://assets/models/%s.glb" % id):
			left.append(id)
	chk("Ungenutzte Modelle sind entfernt", left.is_empty(), left)
	var ml := root.get_node("ModelLoader")
	var vehicles_ok := true
	# Erst zur Laufzeit laden: Beim Kompilieren dieses Testskripts gibt es die Autoloads noch nicht.
	var vehicles: Dictionary = load("res://scripts/data/delivery_plan.gd").get("VEHICLES")
	for tier in vehicles:
		if not ml.has_custom_model(str(vehicles[tier]["model"])):
			vehicles_ok = false
	chk("Alle Lieferfahrzeuge haben ihr Modell", vehicles_ok)
	chk("Regal und Bäume haben ihr Modell", ml.has_custom_model("shelf_heavy") and ml.has_custom_model("tree_oak_1") and ml.has_custom_model("tree_pine_far"))


func _check_line_endings() -> void:
	var ga := FileAccess.get_file_as_string("res://.gitattributes")
	chk("Zeilenenden sind festgelegt", ga.contains("* text=auto eol=lf") and ga.contains("*.glb binary"))
	var imp := FileAccess.get_file_as_string("res://assets/models/rack.glb.import")
	chk(".import-Dateien haben LF", not imp.is_empty() and not imp.contains("\r\n"))
