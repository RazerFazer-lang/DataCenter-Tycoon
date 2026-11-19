extends SceneTree
## Nimmt ein Bild der Hauptmenü-Ansicht ohne Oberfläche auf und speichert es als Ladebildschirm-Hintergrund.
## Aufruf: godot --path . --resolution 1920x1080 --script res://tests/capture_loading_bg.gd


func _initialize() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	await process_frame
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(6.0).timeout
	var ui := main_scene.get_node_or_null("UI")
	if ui != null:
		ui.set("visible", false)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://assets/loading")
	DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(dir.path_join("loading_bg.png"))
	print("CAPTURE: ", error_string(err), " ", img.get_size())
	quit(0 if err == OK else 1)