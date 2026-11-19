extends SceneTree
## Macht zwei Screenshots vom Schreibtisch-PC (Übersicht und Nahaufnahme des Towers).
## Aufruf: godot --path . --resolution 1600x900 --script res://tests/desk_shot_probe.gd -- q=3
## Ausgabe: tests/_shot_desk.png und tests/_shot_tower.png

const SHOTS := [
	{"file": "res://tests/_shot_desk.png", "cam": Vector3(0.55, 1.45, 1.45), "target": Vector3(0.15, 1.0, -0.15)},
	{"file": "res://tests/_shot_tower.png", "cam": Vector3(0.05, 1.12, 0.55), "target": Vector3(0.68, 1.06, -0.10)},
]


func _initialize() -> void:
	create_timer(56.0).timeout.connect(func() -> void:
		print("SHOT Timer-Abbruch nach 56 s")
		quit(2))
	var quality := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("q="):
			quality = clampi(int(arg.substr(2)), 0, 3)
	await process_frame
	var settings := root.get_node_or_null("SettingsManager")
	if settings != null:
		settings.set("graphics_quality", quality)
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(8.0).timeout

	var quads := get_nodes_in_group("pc_screen")
	if quads.is_empty():
		print("SHOT kein Knoten in Gruppe pc_screen gefunden")
		quit(1)
		return
	var desk := (quads[0] as Node3D).get_parent() as Node3D
	if desk == null:
		print("SHOT Schreibtisch-Knoten fehlt")
		quit(1)
		return

	var hidden := _hide_ui(root)
	print("SHOT UI ausgeblendet: %d Knoten" % hidden)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.02
	root.add_child(cam)
	for shot in SHOTS:
		var d: Dictionary = shot
		cam.global_position = desk.to_global(d["cam"])
		cam.look_at(desk.to_global(d["target"]), Vector3.UP)
		for i in range(45):
			cam.make_current()
			await process_frame
		var img := root.get_texture().get_image()
		if img == null:
			print("SHOT kein Bild für %s" % d["file"])
			continue
		var err := img.save_png(ProjectSettings.globalize_path(d["file"]))
		print("SHOT %s err=%d size=%s" % [d["file"], err, str(img.get_size())])
	await _compare_quad_shots(cam, desk)
	_dump_screen_viewport(desk)
	quit(0)


## Vergleichsaufnahmen: Quad ausgeblendet und Quad knallrot ohne Beleuchtung.
## Bleibt die Fläche in beiden Bildern weiß, liegt eine andere Fläche vor dem Quad.
func _compare_quad_shots(cam: Camera3D, desk: Node3D) -> void:
	var quad := desk.get_node_or_null("PcScreenQuad") as MeshInstance3D
	if quad == null:
		print("SHOT Vergleich: PcScreenQuad nicht gefunden")
		return
	_list_meshes_near(desk, quad.global_position, 0.30)
	var d0: Dictionary = SHOTS[0]
	cam.global_position = desk.to_global(d0["cam"])
	cam.look_at(desk.to_global(d0["target"]), Vector3.UP)
	var orig := quad.material_override
	quad.visible = false
	await _shoot(cam, "res://tests/_shot_desk_noquad.png")
	quad.visible = true
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.0, 0.0)
	quad.material_override = red
	await _shoot(cam, "res://tests/_shot_desk_redquad.png", quad)

	# Viewport-Bild ohne Beleuchtung: zeigt, was die Textur allein liefert.
	var mirror: Node = desk.get_node_or_null("PcScreenMirror")
	var vp = mirror.get("_vp") if mirror != null else null
	if vp is SubViewport:
		var unlit := StandardMaterial3D.new()
		unlit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		unlit.albedo_texture = (vp as SubViewport).get_texture()
		quad.material_override = unlit
		await _shoot(cam, "res://tests/_shot_desk_unlitvp.png", quad)

	# Echtes Material, aber völlig matt: verschwindet das Weiß, ist es eine Spiegelung.
	if orig is StandardMaterial3D:
		var matte := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
		matte.roughness = 1.0
		matte.metallic_specular = 0.0
		quad.material_override = matte
		await _shoot(cam, "res://tests/_shot_desk_matte.png", quad)

	quad.material_override = orig
	await _shoot(cam, "res://tests/_shot_desk_orig.png", quad)

	# PC einschalten: Strom an und Desktop-Phase setzen. PcScreenState._process würde den
	# Zustand ohne Netzwerksitzung sofort auf "idle" zurücksetzen, deshalb wird es angehalten.
	var state: Node = root.get_node_or_null("PcScreenState")
	if state == null:
		print("SHOT PcScreenState nicht gefunden")
		return
	state.set_process(false)
	var lib: Node = root.get_node_or_null("MatLib")
	if lib != null and lib.has_method("get_os_screen_material"):
		var sm: Variant = lib.call("get_os_screen_material")
		if sm is ShaderMaterial:
			(sm as ShaderMaterial).set_shader_parameter("power_on", 1.0)
	else:
		print("SHOT MatLib nicht gefunden, power_on nicht gesetzt")
	state.call("_apply", "desktop", "", "", 0, "Test", false, false)
	await _shoot(cam, "res://tests/_shot_desk_on.png", quad)


func _shoot(cam: Camera3D, file: String, probe: Node3D = null) -> void:
	for i in range(12):
		cam.make_current()
		await process_frame
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT kein Bild für %s" % file)
		return
	var err := img.save_png(ProjectSettings.globalize_path(file))
	var px_info := ""
	if probe != null and not cam.is_position_behind(probe.global_position):
		var sp := cam.unproject_position(probe.global_position)
		var x := clampi(int(sp.x), 0, img.get_width() - 1)
		var y := clampi(int(sp.y), 0, img.get_height() - 1)
		px_info = " quad_px=(%d,%d) farbe=%s" % [x, y, str(img.get_pixel(x, y))]
	print("SHOT %s err=%d%s" % [file, err, px_info])


## Listet alle sichtbaren Meshes, deren Mittelpunkt nahe an der Bildschirmfläche liegt.
func _list_meshes_near(node: Node, center: Vector3, radius: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var dist := mi.global_position.distance_to(center)
			if mi.is_visible_in_tree() and dist <= radius:
				print("SHOT nahe Mesh %s dist=%.3f mesh=%s mat=%s" % [
					str(mi.get_path()), dist, str(mi.mesh), str(mi.material_override)])
		_list_meshes_near(child, center, radius)


## Speichert den Inhalt des Monitor-Viewports, um zu sehen, ob das Bild selbst weiß ist
## oder erst durch Material und Glow überstrahlt wird.
func _dump_screen_viewport(desk: Node3D) -> void:
	var mirror: Node = desk.get_node_or_null("PcScreenMirror")
	if mirror == null:
		print("SHOT PcScreenMirror nicht gefunden")
		return
	var vp = mirror.get("_vp")
	if not (vp is SubViewport):
		print("SHOT _vp ist kein SubViewport")
		return
	var vimg := (vp as SubViewport).get_texture().get_image()
	if vimg == null:
		print("SHOT Viewport-Bild leer")
		return
	var c := vimg.get_pixel(vimg.get_width() / 2, vimg.get_height() / 2)
	print("SHOT viewport size=%s center=%s" % [str(vimg.get_size()), str(c)])
	var quad := desk.get_node_or_null("PcScreenQuad") as MeshInstance3D
	if quad == null:
		print("SHOT PcScreenQuad nicht gefunden")
	else:
		var qm := quad.material_override as StandardMaterial3D
		if qm == null:
			print("SHOT Quad-Material ist kein StandardMaterial3D: %s" % str(quad.material_override))
		else:
			var et := qm.emission_texture
			var same := et != null and et.get_rid() == (vp as SubViewport).get_texture().get_rid()
			print("SHOT quad emission_tex=%s rid_valid=%s same_as_vp=%s albedo=%s energy=%s" % [
				str(et), str(et != null and et.get_rid().is_valid()), str(same),
				str(qm.albedo_color), str(qm.emission_energy_multiplier)])
	vimg.save_png(ProjectSettings.globalize_path("res://tests/_shot_viewport.png"))


## Blendet Menüs und HUD aus, damit nur die 3D-Szene im Bild ist.
## CanvasLayer werden komplett versteckt; Controls direkt unter dem Root oder unter einem Node3D ebenfalls.
## SubViewports bleiben unangetastet, weil darin z. B. das Bild des 3D-Monitors gezeichnet wird.
func _hide_ui(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is SubViewport:
			continue
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
			count += 1
		elif child is Control and not (node is Control):
			(child as Control).visible = false
			count += 1
		else:
			count += _hide_ui(child)
	return count