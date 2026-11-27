class_name StaffNpc
extends Node3D
## Sichtbare Figur für Sicherheitsdienst oder Reinigung (GAME-07). Zeigt nur, was StaffManager vorgibt.

var role := "security"
var _body: Node3D
var _human: HumanModel
var _name_lbl: Label3D
var _yaw: float = 0.0
var _built_for: String = ""


static func make(p_role: String) -> StaffNpc:
	var n := StaffNpc.new()
	n.role = p_role
	n.name = "Staff_" + p_role
	return n


func _ready() -> void:
	Staff.staff_changed.connect(_on_changed)
	_on_changed()


func _look() -> Dictionary:
	var id := str((Staff.views.get(role, {}) as Dictionary).get("id", ""))
	if role == "security":
		return HumanModel.job_look("guard", id.hash() % 977)
	if role == "auditor":
		# Prüfer: Anzug, Brille, Ausweis.
		var a := HumanModel.job_look("technician", 4242)
		a.merge({"top": 8, "top_a": 1, "top_b": 3, "bottom": 4, "bottom_a": 1, "shoes": 2, "shoe_a": 0, "glasses": 2, "badge": 1, "belt": 0, "hat": 0, "gloves": 0, "logo": 0}, true)
		return a
	# Reinigung: helle Arbeitskleidung, Handschuhe, Turnschuhe.
	var d := HumanModel.job_look("technician", id.hash() % 977)
	d.merge({"top": 7, "top_a": 9, "top_b": 4, "bottom": 3, "bottom_a": 9, "shoes": 0, "shoe_a": 4, "gloves": 1, "belt": 0, "badge": 1, "hat": 0}, true)
	return d


func _on_changed() -> void:
	var v: Dictionary = Staff.views.get(role, {})
	var id := str(v.get("id", ""))
	if id == "":
		visible = false
		return
	if _body == null:
		_build()
	if id != _built_for:
		_built_for = id
		if _human != null:
			_human.queue_free()
		_human = HumanModel.create(_look())
		_body.add_child(_human)
		position = v.get("pos", position)
	_name_lbl.text = "%s\n%s" % [tr(str(v.get("name", ""))), GameState.format_message(str(v.get("text", "")), v.get("args", []))]


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_name_lbl = Label3D.new()
	_name_lbl.position = Vector3(0.0, 2.02, 0.0)
	_name_lbl.font_size = 30
	_name_lbl.pixel_size = 0.0028
	_name_lbl.outline_size = 8
	_name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_lbl.modulate = Color(1.0, 0.86, 0.55) if role == "security" else Color(0.70, 0.95, 0.85)
	_name_lbl.visibility_range_end = 12.0
	add_child(_name_lbl)


func _process(delta: float) -> void:
	var v: Dictionary = Staff.views.get(role, {})
	if v.is_empty() or _body == null:
		visible = false
		return
	visible = true
	var phase := str(v.get("phase", "idle"))
	var speed := 0.0
	var want := Staff.pos_of(role)
	if phase == "walk":
		var before := position
		position = want
		var d := position - before
		if d.length() > 0.0005:
			_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), clampf(delta * 9.0, 0.0, 1.0))
			speed = d.length() / maxf(delta, 0.001)
	else:
		position = want if position.distance_to(want) > 3.0 else position.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	_body.rotation.y = _yaw
	if _human != null and _human.rig != null:
		_human.move(Vector3(0, 0, -minf(speed, 4.0)).rotated(Vector3.UP, _yaw))
		_human.rig.base = "work" if phase == "work" else ""
