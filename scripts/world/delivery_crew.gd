class_name DeliveryCrew
extends Node3D
## Eine Figur des Lieferdienstes. DeliveryVan sagt jede Sekunde, wo sie steht und was sie tut,
## hier werden Schritte, Haltung und Drehung weich gemischt.

const POSES := {"carry": "carry_box", "push": "push", "pull": "pull", "reach": "reach", "low": "low", "tablet": "tablet", "drive": "drive"}

var _body: Node3D
var _human: HumanModel
var _yaw := 0.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _placed := false
var _waved := 0.0
var _tablet: Node3D
var _bubble: Label3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_human = HumanModel.create(HumanModel.job_look("delivery", get_instance_id() % 97 if get_index() < 0 else get_index() * 11 + 3))
	_body.add_child(_human)
	_tablet = Node3D.new()
	_tablet.position = Vector3(0.0, 1.12, -0.36)
	_tablet.rotation_degrees.x = 48.0
	_tablet.visible = false
	_body.add_child(_tablet)
	# Klemmbrett mit Lieferschein (passt zum Lieferschein-Fenster beim Unterschreiben)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.010, 0.33)
	mi.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.47, 0.32, 0.19)
	mt.roughness = 0.7
	mi.material_override = mt
	_tablet.add_child(mi)
	var sc := MeshInstance3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(0.215, 0.003, 0.29)
	sc.mesh = qm
	sc.position = Vector3(0.0, 0.0065, 0.012)
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.96, 0.95, 0.92)
	ms.roughness = 0.9
	sc.material_override = ms
	_tablet.add_child(sc)
	var clip := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.09, 0.016, 0.03)
	clip.mesh = cm
	clip.position = Vector3(0.0, 0.010, -0.150)
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.72, 0.74, 0.77)
	mc.metallic = 0.85
	mc.roughness = 0.3
	clip.material_override = mc
	_tablet.add_child(clip)
	_bubble = Label3D.new()
	_bubble.position = Vector3(0.0, 2.02, 0.0)
	_bubble.font_size = 30
	_bubble.pixel_size = 0.0030
	_bubble.outline_size = 8
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.modulate = Color(1.0, 0.92, 0.55)
	_bubble.visibility_range_end = 14.0
	add_child(_bubble)


func reset() -> void:
	_placed = false
	visible = false


## st: {"pos", "yaw", "pose", "crouch", "seated", "tablet", "text"}. yaw -> Blickrichtung (Figur schaut nach -Z).
func drive(st: Dictionary, delta: float) -> void:
	visible = bool(st.get("visible", true))
	if not visible:
		_placed = false
		return
	var p: Vector3 = st["pos"]
	var yaw := float(st["yaw"])
	if not _placed:
		_placed = true
		_last = p
		_yaw = yaw
	# Sprünge zwischen zwei Aufgaben werden zu schnellen Schritten.
	var shown := _last.lerp(p, 1.0 - exp(-delta * 14.0)) if _last.distance_to(p) < 2.5 else p
	var d := shown - _last
	_last = shown
	position = shown
	_vel = _vel.lerp(Vector3(d.x, 0.0, d.z) / maxf(delta, 0.001), 1.0 - exp(-delta * 10.0))
	_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-delta * 10.0))
	_body.rotation.y = _yaw
	_tablet.visible = bool(st.get("tablet", false))
	var txt := str(st.get("text", ""))
	if _bubble.text != txt:
		_bubble.text = txt
	var r := _human.rig
	if r == null:
		return
	var seated := bool(st.get("seated", false))
	var pose := str(st.get("pose", "walk"))
	_human.move(Vector3.ZERO if seated else _vel)
	r.seat = 1.0 if seated else 0.0
	r.seat_height = 0.82
	r.crouch = float(st.get("crouch", 0.0))
	r.base = str(POSES.get(pose, ""))
	r.talk = 1.0 if txt != "" and fmod(Time.get_ticks_msec() / 1000.0, 4.0) < 1.8 else 0.0
	r.mood = 0.6 if txt != "" or pose == "wave" else 0.0
	_waved = maxf(0.0, _waved - delta)
	if pose == "wave" and _waved <= 0.0:
		_waved = 3.2
		r.play("wave")
