extends "res://tests/perf_bench.gd"
## Was bleibt beim Beenden liegen? Mit Fenster starten (ohne Fenster legt Godot keine Texturen an):
##   godot --path . --resolution 1280x720 -s res://tests/exit_leak_probe.gd -- --mode=session
## --mode=menu     nur Hauptmenü
## --mode=session  Testwelt hosten, 6 s laufen lassen, beenden
## --mode=left     Sitzung verlassen, dann beenden
## Danach die Ausgabe ansehen:
##   „ObjectDB instances were leaked“ oder „resources still in use“: Fehler bei uns, mit --verbose suchen.
##   „7 RIDs of type "Texture" were leaked“: kommt von Godot 4.7.2 selbst. Jede ReflectionProbe legt
##   einen Reflexionsatlas an, den die Engine beim Beenden nicht freigibt (nachgestellt in einem leeren
##   Projekt mit nur einer Sonde; Sonde oder Welt vorher freigeben hilft nicht). Harmlos, Windows gibt
##   den Grafikspeicher beim Programmende ohnehin frei.
var mode := "session"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	await process_frame
	gs = root.get_node("GameState")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.5).timeout
	if mode != "menu":
		main.get("intro_splash").set_process(false)
		main.get("intro_splash").visible = false
		main.get("loading_screen").visible = false
		main.set("_startup_done", true)
		main.set("_session_warmed", true)
		var nm := root.get_node("NetworkManager")
		nm.call("_start_host_internal", "Leak", 7895, {}, "", "LEAK", "", false, false)
		await create_timer(1.0).timeout
		_build_test_world()
		await create_timer(6.0).timeout
		if mode == "left":
			nm.leave_session()
			await create_timer(2.0).timeout
	else:
		await create_timer(4.0).timeout
	print("EXIT_PROBE beendet (", mode, ")")
	quit()
