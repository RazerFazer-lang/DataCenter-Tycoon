extends SceneTree
## Minimal-Nachbau: Leakt eine ReflectionProbe beim Beenden Texturen, ganz ohne Projekt-Code?
## Aufruf: godot --path . --script res://tests/probe_repro.gd -- [count=N] [always] [nointerior] [nobox] [hide] [free]
##   count=N     Anzahl Probes (Standard 1, 0 = Kontrolllauf)
##   always      UPDATE_ALWAYS statt UPDATE_ONCE
##   nointerior  interior = false
##   nobox       box_projection = false
##   hide        Probes 30 Frames vor quit() unsichtbar schalten
##   free        Probes 30 Frames vor quit() freigeben

const RUN_FRAMES := 150
const PREP_FRAMES := 30

var _frames: int = 0
var _probes: Array[ReflectionProbe] = []
var _hide_before_quit: bool = false
var _free_before_quit: bool = false
var _quitting: bool = false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := 1
	for a in args:
		if a.begins_with("count="):
			count = maxi(0, a.substr(6).to_int())
	_hide_before_quit = args.has("hide")
	_free_before_quit = args.has("free")

	var world := Node3D.new()
	world.name = "ReproWorld"
	root.add_child(world)

	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	world.add_child(box)

	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.look_at_from_position(Vector3(2.0, 4.0, 1.0), Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(3.0, 2.0, 3.0), Vector3.ZERO, Vector3.UP)
	cam.current = true

	for i in count:
		var rp := ReflectionProbe.new()
		rp.position = Vector3(float(i) * 2.0, 1.0, 0.0)
		rp.size = Vector3(4.0, 4.0, 4.0)
		rp.box_projection = not args.has("nobox")
		rp.interior = not args.has("nointerior")
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		rp.update_mode = ReflectionProbe.UPDATE_ALWAYS if args.has("always") else ReflectionProbe.UPDATE_ONCE
		world.add_child(rp)
		_probes.append(rp)

	print("PROBE_REPRO start count=%d always=%s interior=%s box=%s hide=%s free=%s" % [
		count, str(args.has("always")), str(not args.has("nointerior")),
		str(not args.has("nobox")), str(_hide_before_quit), str(_free_before_quit)])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == RUN_FRAMES - PREP_FRAMES:
		for rp in _probes:
			if not is_instance_valid(rp):
				continue
			if _hide_before_quit:
				rp.visible = false
			if _free_before_quit:
				rp.get_parent().remove_child(rp)
				rp.free()
		if _free_before_quit:
			_probes.clear()
		print("PROBE_REPRO vorbereitet (Frame %d)" % _frames)
	if _frames >= RUN_FRAMES and not _quitting:
		_quitting = true
		print("PROBE_REPRO quit() nach %d Frames" % _frames)
		quit(0)
	return false