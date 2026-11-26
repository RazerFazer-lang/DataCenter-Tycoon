class_name TechnicianNpc
extends Node3D
## Sichtbare Figur des Technikers im Dienst. Zeigt nur an, was TechnicianManager vorgibt:
## Wege laufen, an der Werkbank schrauben, Server tragen, mit dem Shuttle weg sein.

var _body: Node3D
var _human: HumanModel
var _name_lbl: Label3D
var _tray: Node3D
var _yaw: float = 0.0
var _built_for: String = ""


func _ready() -> void:
	TechnicianManager.technician_changed.connect(_on_changed)
	_on_changed()


func _on_changed() -> void:
	var v: Dictionary = TechnicianManager.view
	var id := str(v.get("id", ""))
	if id == "":
		visible = false
		return
	if _body == null:
		_build()
	if id != _built_for:
		_built_for = id
		# Jeder Techniker hat sein eigenes Gesicht.
		if _human != null:
			_human.queue_free()
		_human = HumanModel.create(HumanModel.job_look("technician", id.hash() % 977))
		_body.add_child(_human)
		position = v.get("pos", TechnicianManager.HOME)
	_name_lbl.text = "%s\n%s" % [str(v.get("name", "")), str(v.get("text", ""))]
	if _tray != null:
		_tray.visible = str(v.get("carry", "")) != ""


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_name_lbl = Label3D.new()
	_name_lbl.position = Vector3(0.0, 2.02, 0.0)
	_name_lbl.font_size = 30
	_name_lbl.pixel_size = 0.0028
	_name_lbl.outline_size = 8
	_name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_lbl.modulate = Color(0.72, 0.88, 1.0)
	_name_lbl.visibility_range_end = 12.0
	add_child(_name_lbl)
	# Getragener Server vor dem Bauch
	_tray = HardwareMeshFactory.build_chassis_shell("web_server", {})
	_tray.scale = Vector3.ONE * 0.62
	_tray.position = Vector3(0.0, 1.02, -0.42)
	_tray.visible = false
	_body.add_child(_tray)


func _process(delta: float) -> void:
	var v: Dictionary = TechnicianManager.view
	if v.is_empty() or _body == null:
		visible = false
		return
	var phase := str(v.get("phase", "idle"))
	# Unterwegs mit dem Shuttle: nicht zu sehen.
	visible = phase != "wait"
	if not visible:
		return
	var speed := 0.0
	if phase == "walk":
		var path: Array = v.get("path", [])
		var dur := maxf(0.1, float(v.get("dur", 1.0)))
		var t := clampf(float(Time.get_ticks_msec() - int(v.get("stamp", 0))) / 1000.0 / dur, 0.0, 1.0)
		var before := position
		position = _along(path, t)
		var d := position - before
		if d.length() > 0.0005:
			_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), clampf(delta * 9.0, 0.0, 1.0))
		speed = TechnicianManager.WALK_SPEED if t < 1.0 else 0.0
	else:
		var want: Vector3 = v.get("pos", position)
		# Nach dem Shuttle oder einem Schichtwechsel steht er woanders: dort erscheinen, nicht hinübergleiten.
		position = want if position.distance_to(want) > 3.0 else position.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
		if phase == "work":
			# Zur Werkbank schauen (sie steht bei x = -4,95 an der Westwand).
			_yaw = lerp_angle(_yaw, PI * 0.5, clampf(delta * 6.0, 0.0, 1.0))
	_body.rotation.y = _yaw
	_animate(delta, speed, phase == "work")


func _along(path: Array, t: float) -> Vector3:
	if path.is_empty():
		return position
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector3).distance_to(path[i - 1])
	var want := total * t
	for i in range(1, path.size()):
		var seg := (path[i] as Vector3).distance_to(path[i - 1])
		if want <= seg and seg > 0.0001:
			return (path[i - 1] as Vector3).lerp(path[i], want / seg)
		want -= seg
	return path[path.size() - 1]


func _animate(_delta: float, speed: float, working: bool) -> void:
	if _human == null or _human.rig == null:
		return
	var r := _human.rig
	_human.move(Vector3(0, 0, -speed).rotated(Vector3.UP, _yaw))
	var carrying := _tray != null and _tray.visible
	r.base = "carry_box" if carrying else ("work" if working else "")
	if working and not r.is_playing() and randf() < 0.004:
		r.play("screw", Vector3(0.0, 1.05, 0.42))
