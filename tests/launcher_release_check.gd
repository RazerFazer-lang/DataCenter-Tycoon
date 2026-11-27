extends SceneTree
## Launcher & Veröffentlichung (REL-01, REL-06, REL-07) im Spiel:
## Roadmap im Launcher aktuell, „Neu in Version“ nach Updates, Erfolge und Steam-Platzhalter.
## Der Launcher-Teil (kleine Updates, Absturzbericht) hat eigene Prüfungen im DeltaTool.
## Aufruf: godot --headless --path . --script res://tests/launcher_release_check.gd

const PORT := 7909

var bad := 0
var gs: Node
var ach: Node
var main: Node


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
	ach = root.get_node("Achievements")
	_check_version_files()
	_check_whats_new_logic()
	_check_steam_bridge()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	await _check_whats_new_dialog()
	await _check_menu_page()
	root.get_node("NetworkManager").call("_start_host_internal", "Test", PORT, {}, "", "Erfolge", "", false, false)
	await wait(20)
	await _check_achievements()
	print("ERGEBNIS: %d Fehler" % bad)
	root.get_node("NetworkManager").leave_session()
	quit(1 if bad > 0 else 0)


# --- REL-01 ---

func _check_version_files() -> void:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://version.json"))
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	chk("version.json passt zur Spielversion", str(v.get("version", "")) == current, [v.get("version"), current])
	chk("Changelog hat einen Eintrag für die aktuelle Version", str((v["changelog"] as Array)[0]["version"]) == "v" + current)
	var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roadmap.json"))
	var stale: Array = []
	for col in r["columns"]:
		if str(col["id"]) == "done":
			continue
		for it in col["items"]:
			if WhatsNew.compare(str(it.get("version", "")), current) <= 0:
				stale.append("%s: %s" % [it.get("version"), it.get("title")])
	chk("Launcher-Roadmap: nichts Geplantes ist älter als die aktuelle Version", stale.is_empty(), stale)
	var cols := {}
	for col in r["columns"]:
		cols[str(col["id"])] = (col["items"] as Array).size()
	# „In Arbeit“ ist direkt nach einem Release leer: bump_version.js verschiebt das Paket nach „Fertig“.
	chk("Launcher-Roadmap hat Geplant, In Arbeit und Fertig", int(cols.get("planned", 0)) >= 3 and cols.has("in_progress") and int(cols.get("done", 0)) >= 20, cols)


# --- REL-06 ---

func _check_whats_new_logic() -> void:
	chk("Version lesen", Array(WhatsNew.parse_version("v3.4.0")) == [3, 4, 0] and Array(WhatsNew.parse_version("3.4")) == [3, 4, 0])
	chk("Versionen vergleichen", WhatsNew.compare("v3.10.0", "3.9.9") == 1 and WhatsNew.compare("3.4", "v3.4.0") == 0 and WhatsNew.compare("3.3.0", "3.4.0") == -1)
	var log := [
		{"version": "v3.5.0", "title": "C", "items": ["[NEU] c"]},
		{"version": "v3.4.0", "title": "B", "items": ["[TECHNIK] b", "ohne Kennung"]},
		{"version": "v3.3.0", "title": "A", "items": []},
		{"version": "v3.2.1", "title": "Z", "items": []},
		{"version": "v3.2.0", "title": "Y", "items": []},
	]
	var after_33 := WhatsNew.entries_between(log, "3.3.0", "3.5.0")
	chk("Nach dem Update: nur die neueren Versionen", after_33.size() == 2 and str(after_33[0]["version"]) == "v3.5.0", after_33.size())
	chk("Künftige Versionen tauchen nicht auf", WhatsNew.entries_between(log, "3.3.0", "3.4.0").size() == 1)
	chk("Ohne Stand: die letzten drei", WhatsNew.entries_between(log, "", "3.5.0").size() == WhatsNew.MAX_VERSIONS)
	chk("Erster Start zeigt nichts", not WhatsNew.should_show("", "3.5.0", false))
	chk("Spieler mit Spielständen sieht es einmal", WhatsNew.should_show("", "3.5.0", true))
	chk("Nach einem Update zeigen", WhatsNew.should_show("3.4.0", "3.5.0", true))
	chk("Gleiche Version zeigt nichts", not WhatsNew.should_show("3.5.0", "3.5.0", true))
	chk("Kennung abtrennen", Array(WhatsNew.split_item("[CO-OP] Text")) == ["CO-OP", "Text"] and Array(WhatsNew.split_item("Nur Text")) == ["", "Nur Text"])


func _check_whats_new_dialog() -> void:
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	var log := WhatsNew.load_changelog()
	var CP: GDScript = load("res://scripts/ui/changelog_page.gd")
	var page: Control = CP.new()
	root.add_child(page)
	page.call("setup", log, "3.5.0")
	await wait(2)
	chk("Changelog: jede Version in der Liste", page.find_children("Version_*", "Button", true, false).size() == log.size(), log.size())
	chk("Changelog: neueste Version ist gewählt", WhatsNew.compare(page.call("selected"), current) == 0, page.call("selected"))
	chk("Changelog: neue Versionen sind markiert", page.call("is_new", current) and not page.call("is_new", "3.5.0") and not page.call("is_new", "3.4.0"))
	var want := 0
	for e in log:
		if WhatsNew.compare(str(e["version"]), "3.6.0") == 0:
			want = (e["items"] as Array).size()
	page.call("select", "v3.6.0")
	await wait(2)
	var rows := page.find_children("Punkt_*", "HBoxContainer", true, false).size()
	chk("Changelog: zeigt jeden Punkt der gewählten Version", rows == want and want > 0, [rows, want])
	chk("Changelog: Kennungen landen im richtigen Bereich", CP.category_of("NEU / STROM") == "neu" and CP.category_of("FIX") == "fix" and CP.category_of("CO-OP") == "coop" and CP.category_of("PERFORMANCE") == "technik" and CP.category_of("WAS ANDERES") == "sonst")
	chk("Changelog: Titel ohne „Update x:“", CP.short_title("Update 3.6.1: Lieferschein mit Unterschrift") == "Lieferschein mit Unterschrift")
	page.queue_free()
	var sm := root.get_node("SettingsManager")
	sm.remember_seen_version("3.4.0")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	chk("Gesehene Version wird gespeichert", str(cfg.get_value("general", "last_seen_version", "")) == "3.4.0" and sm.last_seen_version == "3.4.0")
	sm.remember_seen_version(current)


func _check_menu_page() -> void:
	var menu: Node = main.get("main_menu")
	if menu == null:
		menu = main.find_child("MainMenu", true, false)
	chk("Hauptmenü gefunden", menu != null)
	if menu == null:
		return
	var pages: Dictionary = menu.get("_pages")
	chk("Hauptmenü hat die Seite ERFOLGE", pages.has("achievements"))
	chk("Hauptmenü hat den Reiter CHANGELOG", pages.has("changelog") and (menu.get("_nav_buttons") as Dictionary).has("changelog"))
	chk("Kein Changelog-Overlay mehr", menu.find_child("WhatsNew", true, false) == null)
	menu.call("_switch_page", "achievements", false)
	var box: VBoxContainer = menu.get("_achievements_box")
	await wait(2)
	var cards := 0
	for c in box.get_children():
		if str(c.name).begins_with("Erfolg_"):
			cards += 1
	chk("Seite ERFOLGE zeigt alle Erfolge", cards == ach.LIST.size(), [cards, ach.LIST.size()])
	menu.call("_switch_page", "new_game", false)


# --- REL-07 ---

func _check_steam_bridge() -> void:
	chk("Ohne GodotSteam ist Steam aus", not SteamBridge.available() and SteamBridge.steam() == null)
	chk("Erfolg an Steam melden tut ohne Steam nichts", SteamBridge.unlock_achievement("first_rack") == false)
	chk("API-Name für Steamworks", SteamBridge.achievement_api_name("first_rack") == "ACH_FIRST_RACK")
	SteamBridge.set_status("Test")
	SteamBridge.poll()


func _check_achievements() -> void:
	var list: Dictionary = ach.LIST
	var names := {}
	var untranslated: Array = []
	TranslationServer.set_locale("en")
	for id in list:
		var n := str(list[id]["name"])
		names[n] = true
		if TranslationServer.translate(n) == n or TranslationServer.translate(str(list[id]["desc"])) == str(list[id]["desc"]):
			untranslated.append(id)
	TranslationServer.set_locale("de")
	chk("Erfolge haben eindeutige Namen", names.size() == list.size())
	chk("Alle Erfolge sind übersetzt", untranslated.is_empty(), untranslated)
	var doc := FileAccess.get_file_as_string("res://docs/steam/achievements.md")
	var missing: Array = []
	for id in list:
		if not doc.contains("| " + SteamBridge.achievement_api_name(str(id)) + " |"):
			missing.append(id)
	chk("Steamworks-Liste passt zu den Erfolgen", missing.is_empty() and not doc.is_empty(), missing)

	ach.reset_for_test()
	var got: Array = []
	ach.unlocked.connect(func(id: String) -> void: got.append(id))
	chk("Leere Welt: nur Teamarbeit fehlt noch, nichts schaltet frei", ach.check_now().is_empty(), ach.done.keys())
	gs.racks["rack_a1"] = gs._make_rack_data("rack_a1", "rack", Vector3(1, 0, 1), 0.0)
	gs.money = 150000.0
	gs.company_level = 3
	var new1: Array = ach.check_now()
	chk("Rack, Geld und Firmenstufe schalten frei", new1.has("first_rack") and new1.has("money_100k") and new1.has("level_3") and not new1.has("money_1m"), new1)
	chk("Signal für die Meldung im HUD", got.has("first_rack"))
	chk("Kein Erfolg doppelt", ach.check_now().is_empty())
	var cfg := ConfigFile.new()
	cfg.load("user://achievements.cfg")
	chk("Erfolge werden gespeichert", cfg.has_section_key("unlocked", "first_rack") and int(cfg.get_value("unlocked", "first_rack", 0)) > 0)
	ach.done.clear()
	ach.call("_load")
	chk("Erfolge werden geladen", ach.is_unlocked("first_rack") and ach.is_unlocked("level_3"))
	# Brand gelöscht: erst ein Brand, dann keiner mehr.
	var slot: Dictionary = gs.racks["rack_a1"]["slots"][0]
	slot["item_type"] = "web_server"
	slot["fire_level"] = 0.5
	slot["state"] = "burning"
	ach.check_now()
	var burning: bool = gs.has_any_fire()
	slot["fire_level"] = 0.0
	slot["state"] = "ok"
	var out: Array = ach.check_now()
	chk("Gelöschter Brand zählt", (burning and out.has("fire_out")) or not burning, [burning, out])
	gs.racks.erase("rack_a1")
	ach.reset_for_test()
	ach.call("_save")
