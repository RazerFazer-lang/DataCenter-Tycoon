extends SceneTree
## Baut die Garage headless auf und prüft Wandmaterial und Schild über dem PC.
## Aufruf: godot --headless --path . --script res://tests/garage_smoke.gd
## garage_builder.gd wird erst nach dem ersten Frame per load() geholt, weil es Autoloads
## (SettingsManager, MatLib) nutzt, die beim Kompilieren eines --script noch nicht registriert sind.

const GARAGE_SCRIPT := "res://scripts/world/garage_builder.gd"
const TIMEOUT_SEC := 30.0


func _initialize() -> void:
	# Sicherheitsnetz: Test beendet sich auch dann, wenn unterwegs etwas hängen bleibt.
	create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		print("FEHLER  Zeitlimit von %d s überschritten" % int(TIMEOUT_SEC))
		quit(2))
	await process_frame

	var failed := 0
	var script := load(GARAGE_SCRIPT) as GDScript
	if script == null or not script.can_instantiate():
		print("FEHLER  %s ließ sich nicht laden" % GARAGE_SCRIPT)
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var garage := script.new() as Node3D
	garage.name = "Garage"
	root.add_child(garage)
	await process_frame
	await process_frame
	print("Garage aufgebaut in %d ms" % (Time.get_ticks_msec() - t0))

	var matlib := root.get_node_or_null("MatLib")
	if matlib == null:
		print("FEHLER  Autoload MatLib nicht gefunden")
		failed += 1
	else:
		var wall := matlib.call("get_mat", "garage_wall") as StandardMaterial3D
		if wall == null or wall.albedo_texture == null or wall.normal_texture == null:
			print("FEHLER  garage_wall hat keine Albedo- oder Normal-Textur")
			failed += 1
		else:
			var img := wall.albedo_texture.get_image()
			print("garage_wall: %dx%d, Mipmaps=%s, Filter=%d" % [
				img.get_width(), img.get_height(), str(img.has_mipmaps()), wall.texture_filter])
			if img.get_width() != 1024 or not img.has_mipmaps():
				print("FEHLER  Wandtextur nicht 1024 px oder ohne Mipmaps")
				failed += 1

	var sign_found := false
	for n in garage.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.text.begins_with("WINDOWS SERVER-PC"):
			sign_found = true
			print("Schild: font_size=%d pixel_size=%.4f" % [l.font_size, l.pixel_size])
	if not sign_found:
		print("FEHLER  Schild über dem PC nicht gefunden")
		failed += 1

	print("Ergebnis: %d Fehler" % failed)
	quit(1 if failed > 0 else 0)