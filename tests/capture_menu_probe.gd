extends SceneTree
## Startet das Spiel, wartet bis das Hauptmenü da ist, speichert einen Screenshot
## und gibt den Zustand des Ladebildschirms aus.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/capture_menu_probe.gd


func _initialize() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	for t in [1.0, 3.0, 6.0]:
		await create_timer(t if t == 1.0 else t - (3.0 if t == 6.0 else 1.0)).timeout
		var ls: Control = main_scene.get("loading_screen")
		var mm: Control = main_scene.get("main_menu")
		print("PROBE t=%.1f loading.visible=%s loading.modulate.a=%.2f loading.size=%s menu.visible=%s menu.modulate.a=%.2f" % [
			t, str(ls.visible), ls.modulate.a, str(ls.size), str(mm.visible), mm.modulate.a
		])
		for c in main_scene.get_node("UI").get_children():
			if c is Control and (c as Control).visible:
				print("PROBE   sichtbar: %s (%s) a=%.2f rect=%s" % [c.name, c.get_class(), (c as Control).modulate.a, str((c as Control).get_global_rect())])
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://tests/_menu_capture.png")
	print("PROBE save=%d -> %s" % [img.save_png(out), out])
	quit(0)