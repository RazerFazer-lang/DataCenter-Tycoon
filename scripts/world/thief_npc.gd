class_name ThiefNpc
extends Node3D
## Sichtbare Figur des nächtlichen Diebs. Weg und Ablauf kommen aus DecorManager.

var _body: Node3D
var _human: HumanModel
var _box: Node3D
var _yaw := 0.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO


func _ready() -> void:
	visible = false
	DecorManager.thief_changed.connect(_on_changed)


func _on_changed() -> void:
	if DecorManager.thief.is_empty():
		visible = false
		return
	if _body == null:
		_build()
	for c in _box.get_children():
		c.queue_free()
	var carry: Dictionary = DecorManager.thief.get("carry", {})
	if not carry.is_empty():
		_box.add_child(ShelfProp.goods_visual(carry))


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_human = HumanModel.create(HumanModel.job_look("thief", randi() % 50))
	_body.add_child(_human)
	_human.rig.mood = -0.5
	_box = Node3D.new()
	_box.position = Vector3(0.0, 0.92, -0.48)
	_body.add_child(_box)


func _process(delta: float) -> void:
	var th: Dictionary = DecorManager.thief
	if th.is_empty() or _body == null:
		visible = false
		return
	visible = true
	var p: Vector3 = DecorManager.thief_pos()
	position = p
	var d := p - _last
	_last = p
	if d.length() > 0.0005 and d.length() < 2.0:
		_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), clampf(delta * 9.0, 0.0, 1.0))
	_body.rotation.y = _yaw
	var phase := str(th.get("phase", ""))
	var r := _human.rig
	if r == null:
		return
	if d.length() < 2.0:
		_vel = _vel.lerp(Vector3(d.x, 0.0, d.z) / maxf(delta, 0.001), 1.0 - exp(-delta * 8.0))
	_human.move(Vector3.ZERO if phase == "grab" else _vel)
	var carry := not (th.get("carry", {}) as Dictionary).is_empty()
	r.base = "low" if phase == "grab" else ("carry_box" if carry else "")
	r.crouch = 0.35 if phase == "in" else 0.0
	r.look_yaw = sin(Time.get_ticks_msec() / 900.0) * 0.7 if phase != "out" else 0.0
