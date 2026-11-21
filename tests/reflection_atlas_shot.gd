extends SceneTree
## Bildvergleich für die Größe des Reflection-Atlas (Punkt 2.7 im Optimierungsdokument).
## Bild aufnehmen (mit Fenster):  godot --path . --resolution 1280x720 --script res://tests/reflection_atlas_shot.gd -- out=a8_1
## Zwei Bilder vergleichen:        godot --headless --path . --script res://tests/reflection_atlas_shot.gd -- compare=a8_1,a64
## Ausgabe: Zeilen mit "ATLAS".

const SHOT_DIR := "res://tests/out/atlas"
const WAIT_SEC := 8.0
const TIMEOUT_SEC := 40.0
## Ab dieser Abweichung pro Kanal (0..255) zählt ein Pixel als verändert.
const PIXEL_THRESHOLD := 8


func _initialize() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


func _shot_path(shot_name: String) -> String:
	return ProjectSettings.globalize_path("%s/%s.png" % [SHOT_DIR, shot_name])


func _run() -> void:
	var args := _args()
	if args.has("compare"):
		quit(_compare(str(args["compare"])))
		return
	if not args.has("out"):
		print("ATLAS FEHLER: out=<name> oder compare=<a>,<b> fehlt")
		quit(1)
		return

	create_timer(TIMEOUT_SEC).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	await process_frame
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		print("ATLAS FEHLER: main.tscn nicht ladbar")
		quit(1)
		return
	root.add_child(packed.instantiate())
	await create_timer(WAIT_SEC).timeout

	var tex := root.get_texture()
	var img := tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		print("ATLAS FEHLER: kein Bild")
		quit(1)
		return
	var path := _shot_path(str(args["out"]))
	var err := img.save_png(path)
	print("ATLAS reflection_count=%s shot=%s err=%d" % [
		str(ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count", "?")), path, err])
	quit(0 if err == OK else 1)


func _load_rgb(shot_name: String) -> Image:
	var img := Image.load_from_file(_shot_path(shot_name))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


func _compare(spec: String) -> int:
	var names := spec.split(",")
	if names.size() != 2:
		print("ATLAS FEHLER: compare=<a>,<b> erwartet")
		return 1
	var a := _load_rgb(names[0])
	var b := _load_rgb(names[1])
	if a == null or b == null:
		print("ATLAS FEHLER: Bild fehlt (%s / %s)" % [names[0], names[1]])
		return 1
	if a.get_size() != b.get_size():
		print("ATLAS FEHLER: Größen verschieden %s vs %s" % [str(a.get_size()), str(b.get_size())])
		return 1

	var da := a.get_data()
	var db := b.get_data()
	var sum := 0
	var max_diff := 0
	var changed := 0
	var pixels := da.size() / 3
	for p in range(pixels):
		var i := p * 3
		var d0 := absi(da[i] - db[i])
		var d1 := absi(da[i + 1] - db[i + 1])
		var d2 := absi(da[i + 2] - db[i + 2])
		var m := maxi(d0, maxi(d1, d2))
		sum += d0 + d1 + d2
		if m > max_diff:
			max_diff = m
		if m > PIXEL_THRESHOLD:
			changed += 1
	print("ATLAS VERGLEICH %s vs %s: mittlere Abweichung %.3f / 255, max %d, veränderte Pixel %.3f %%" % [
		names[0], names[1], float(sum) / float(pixels * 3), max_diff, 100.0 * float(changed) / float(pixels)])
	return 0