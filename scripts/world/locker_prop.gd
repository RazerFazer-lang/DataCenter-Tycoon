class_name LockerProp
extends Node3D
## Spind in der Garage: [E] öffnet den Figuren-Editor. Daneben ein echter Spiegel, der sich nur
## einschaltet, wenn man davorsteht.

const MIRROR_POS := Vector3(0.50, 1.06, 0.215)
const MIRROR_SIZE := Vector2(0.56, 1.64)
const LAYER := 1 << 18

var _vp: SubViewport
var _cam: Camera3D
var _quad: MeshInstance3D
var _mat: StandardMaterial3D
var _body: HumanModel
var _body_look := ""
var _doors: Array[Node3D] = []
var _open := 0.0


func _ready() -> void:
	add_to_group("locker_prop")
	var m := ModelLoader.instantiate_custom_model("locker")
	if m != null:
		add_child(m)
		for n in ["Door_A", "Door_B"]:
			var d := m.find_child(n, true, false) as Node3D
			if d != null:
				_doors.append(d)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.62, 2.0, 0.44)
	cs.shape = bs
	cs.position.y = 1.0
	body.add_child(cs)
	add_child(body)
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("interact_type", "locker")
	area.set_meta("entity_id", "locker")
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(1.64, 2.0, 0.50)
	ac.shape = ab
	ac.position.y = 1.0
	area.add_child(ac)
	add_child(area)
	_build_mirror()


func _build_mirror() -> void:
	_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = MIRROR_SIZE
	_quad.mesh = q
	_quad.position = MIRROR_POS
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.62, 0.66, 0.70)
	_mat.metallic = 1.0
	_mat.roughness = 0.06
	_quad.material_override = _mat
	if DisplayServer.get_name() == "headless":
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(384, int(384.0 * MIRROR_SIZE.y / MIRROR_SIZE.x))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.use_hdr_2d = true
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.cull_mask = 0xFFFFF & ~FpArms.LAYER
	_vp.add_child(_cam)


func _process(delta: float) -> void:
	var lp := get_tree().get_first_node_in_group("local_player") as PlayerController
	var near := lp != null and lp.is_inside_tree() and lp.global_position.distance_to(global_position) < 3.4
	_open = move_toward(_open, 1.0 if near and lp.ui_locked and lp.at_locker else 0.0, delta * 2.2)
	for i in _doors.size():
		_doors[i].rotation.y = (-1.9 if i == 0 else 1.9) * smoothstep(0.0, 1.0, _open)
	if _vp == null:
		return
	var cam := get_viewport().get_camera_3d()
	var on := near and cam != null and to_local(cam.global_position).z > 0.30
	if on != (_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS):
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if on:
			_mat.metallic = 0.0
			_mat.roughness = 1.0
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mat.albedo_color = Color(0.94, 0.96, 0.97)
			_mat.albedo_texture = _vp.get_texture()
			_mat.uv1_scale = Vector3(-1, 1, 1)
			_mat.uv1_offset = Vector3(1, 0, 0)
		else:
			_mat.albedo_texture = null
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_mat.metallic = 1.0
			_mat.roughness = 0.06
			_mat.albedo_color = Color(0.62, 0.66, 0.70)
			if _body != null:
				_body.queue_free()
				_body = null
	if on:
		_render(cam, lp)


## Spiegelbild: Kamera hinter dem Spiegel, deren Bildausschnitt genau die Spiegelfläche ist.
func _render(cam: Camera3D, lp: PlayerController) -> void:
	var n := global_basis.z.normalized()
	var c := _quad.global_position
	var e := cam.global_position
	var d := (e - c).dot(n)
	var e2 := e - n * 2.0 * d
	var bx := Vector3.UP.cross(-n).normalized()
	_cam.global_transform = Transform3D(Basis(bx, Vector3.UP, -n), e2)
	var off := c - e2
	if _cam.environment == null and cam.get_world_3d().environment != null:
		# Ohne eigene Farbkorrektur: die bekommt das Bild erst mit der ganzen Szene.
		var env := cam.get_world_3d().environment.duplicate() as Environment
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.adjustment_enabled = false
		env.glow_enabled = false
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		_cam.environment = env
	_cam.set_frustum(MIRROR_SIZE.y, Vector2(off.dot(bx), off.dot(Vector3.UP)), maxf(0.05, d), 40.0)
	var key := str(lp.skin_data.hash())
	if _body == null or key != _body_look:
		_body_look = key
		if _body != null:
			_body.queue_free()
		_body = HumanModel.create(lp.skin_data if not lp.skin_data.is_empty() else SettingsManager.get_skin())
		_body.manual = true
		get_parent().add_child(_body)
		for mi in _body.find_children("*", "VisualInstance3D", true, false):
			(mi as VisualInstance3D).layers = LAYER
			if mi is GeometryInstance3D:
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.cull_mask = cam.cull_mask & ~LAYER
	_body.global_transform = lp.global_transform
	if lp.human_model() != null:
		var src := lp.human_model().skeleton
		for i in src.get_bone_count():
			_body.skeleton.set_bone_pose_position(i, src.get_bone_pose_position(i))
			_body.skeleton.set_bone_pose_rotation(i, src.get_bone_pose_rotation(i))
