class_name ThiefNpc
extends Node3D
## Sichtbare Figur des nächtlichen Diebs. Weg und Ablauf kommen aus DecorManager.

var _body: Node3D
var _skel: Skeleton3D
var _bones: Dictionary = {}
var _box: Node3D
var _anim := 0.0
var _yaw := 0.0
var _last := Vector3.ZERO


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
	var m := ModelLoader.instantiate_custom_model("delivery_driver_realistic")
	if m != null:
		_body.add_child(m)
		HumanoidRigHelper.normalize_character_root(m, true)
		HumanoidRigHelper.apply_skin_to_skeleton_model(m, {}, Color(0.20, 0.21, 0.24))
		DeliveryCrew.dress(m, {"Vest": Color(0.07, 0.07, 0.08), "Shirt": Color(0.10, 0.10, 0.12), "Pants": Color(0.09, 0.10, 0.13), "Helmet": Color(0.05, 0.05, 0.06), "Boots": Color(0.06, 0.06, 0.06)})
		_skel = HumanoidRigHelper.find_skeleton(m)
		if _skel != null:
			_bones = HumanoidRigHelper.map_bones(_skel)
			HumanoidRigHelper.apply_relaxed_standing_pose(_skel, _bones)
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
	var speed := 0.0 if phase == "grab" else (DecorManager.THIEF_WALK if phase == "in" else DecorManager.THIEF_RUN)
	_anim += delta * (3.2 + speed * 1.9)
	if _skel != null:
		var carry := not (th.get("carry", {}) as Dictionary).is_empty()
		var stride := clampf(speed / 1.7, 0.0, 1.5)
		NpcWalker.legs(_skel, _bones, _anim, stride, 0.55 if phase == "grab" else 0.0)
		NpcWalker.apply(_skel, _bones, NpcWalker.pose("low" if phase == "grab" else ("carry" if carry else "walk"), _anim, stride))
	_body.position.y = -0.28 if phase == "grab" else 0.0
