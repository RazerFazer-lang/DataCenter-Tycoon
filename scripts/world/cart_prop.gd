class_name CartProp
extends Node3D
## Heavy-Duty 4-Crate Co-op Push Cart (Schwerlast-Rollwagen).
## Displays up to 4 loaded hardware crates in 3D on its platform, smoothly interpolates
## while pushed across halls, and plays spatial 3D caster-wheel rolling audio.

var cart_id: String = ""
var pushed_by: int = 0
var _data: Array = []
var _items: Array = []

var _target_pos: Vector3 = Vector3.ZERO
var _target_rot_y: float = 0.0
var _initialized_pose: bool = false

var _slot_visuals: Array = []
var _label: Label3D
var _area: Area3D
var _roll_audio: AudioStreamPlayer3D
var _prev_pos: Vector3 = Vector3.ZERO
var _smooth_roll_vol: float = 0.0


func setup(id: String) -> void:
	cart_id = id
	_build_geometry()
	_setup_audio()


func apply_data(data: Dictionary) -> void:
	pushed_by = int(data.get("pushed_by", 0))
	_data = (data.get("data", []) as Array).duplicate() if data.get("data", []) is Array else []
	_items = (data.get("items", []) as Array).duplicate()
	var dpos: Vector3 = data["pos"]
	var drot: float = float(data.get("rot_y", 0.0))

	if not _initialized_pose or pushed_by != multiplayer.get_unique_id():
		_target_pos = dpos
		_target_rot_y = drot
		if not _initialized_pose:
			position = dpos
			rotation.y = drot
			_prev_pos = dpos
			_initialized_pose = true

	# Disable cart's own raycast hitbox while the LOCAL player is pushing it so they
	# can aim straight through onto ground crates to scoop them up effortlessly!
	var is_pushed_by_me := (pushed_by == multiplayer.get_unique_id())
	_set_interactable(not is_pushed_by_me)
	_refresh_cargo_visuals()


func apply_live_pose(pos: Vector3, rot_y: float, immediate: bool = false) -> void:
	_target_pos = pos
	_target_rot_y = rot_y
	if immediate:
		position = pos
		rotation.y = rot_y


func _set_interactable(enabled: bool) -> void:
	if _area == null:
		return
	for c in _area.get_children():
		if c is CollisionShape3D:
			c.disabled = not enabled


func _setup_audio() -> void:
	_roll_audio = AudioStreamPlayer3D.new()
	_roll_audio.position = Vector3(0.0, 0.16, 0.0)
	_roll_audio.stream = SfxManager.get_loop_stream("cart_roll")
	_roll_audio.max_distance = 10.0
	_roll_audio.unit_size = 2.2
	_roll_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_roll_audio.volume_db = -60.0
	add_child(_roll_audio)


func _process(delta: float) -> void:
	# Nach dem Verlassen der Sitzung gibt es kurz keinen Peer mehr.
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	if pushed_by != me:
		position = position.lerp(_target_pos, clampf(delta * 15.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_rot_y, clampf(delta * 15.0, 0.0, 1.0))

	var speed := Vector2(position.x - _prev_pos.x, position.z - _prev_pos.z).length() / maxf(delta, 0.001)
	_prev_pos = position

	if _roll_audio != null:
		var gain := SettingsManager.get_effective_sfx_gain()
		var target_vol := 0.0
		if speed > 0.35 and gain > 0.005:
			target_vol = clampf(speed / 6.0, 0.15, 0.75) * gain
		_smooth_roll_vol = lerpf(_smooth_roll_vol, target_vol, clampf(delta * 10.0, 0.0, 1.0))
		if _smooth_roll_vol <= 0.01:
			if _roll_audio.playing:
				_roll_audio.stop()
		else:
			if not _roll_audio.playing:
				_roll_audio.play(randf_range(0.0, 1.2))
			_roll_audio.volume_db = linear_to_db(_smooth_roll_vol) - 8.0
			_roll_audio.pitch_scale = clampf(0.78 + speed * 0.08, 0.75, 1.40)


func _refresh_cargo_visuals() -> void:
	for i in range(_slot_visuals.size()):
		var vis: Dictionary = _slot_visuals[i]
		var box_root: Node3D = vis["root"]
		if i < _items.size():
			var item_type := str(_items[i])
			var cat: Dictionary = GameState.ITEM_CATALOG.get(item_type, {"name": item_type, "color": Color.WHITE})
			box_root.visible = true
			if str(vis["item"]) != item_type:
				vis["item"] = item_type
				var holder: Node3D = vis["holder"]
				for c in holder.get_children():
					c.queue_free()
				var full: Dictionary = _data[i] if i < _data.size() and _data[i] is Dictionary else {}
				if full.is_empty():
					full = {"item_type": item_type}
				if GameState.is_repair_kit(item_type) or item_type == "server_tray" or item_type == "slot_build_box" or int(full.get("pack_count", 1)) > 1:
					holder.add_child(StorageShelfProp.build_stored_visual(full))
				else:
					holder.add_child(HardwareMeshFactory.build_item_visual(item_type, full))
			(vis["lbl"] as Label3D).text = tr(str(cat["name"])).left(14)
		else:
			box_root.visible = false

	if _label != null:
		var status := ""
		if pushed_by != 0:
			status = " • %s" % NetworkManager.get_player_name(pushed_by)
		_label.text = tr("ROLLWAGEN (%d/%d)%s") % [_items.size(), GameState.CART_MAX_ITEMS, status]
		_label.modulate = Color(0.55, 0.94, 1.0) if _items.size() < GameState.CART_MAX_ITEMS else Color(1.0, 0.80, 0.30)


func _build_geometry() -> void:
	var custom_m := ModelLoader.instantiate_custom_model("cart")
	if custom_m != null:
		add_child(custom_m)
	var deck_mat := MatLib.make_brushed_metal(Color(0.18, 0.44, 0.72), 0.42, 0.48)
	var mat_pad := _mat(Color(0.11, 0.13, 0.16), 0.86, 0.10)
	var steel_mat := MatLib.make_brushed_metal(Color(0.62, 0.66, 0.72), 0.32, 0.75)
	var grip_mat := _mat(Color(0.96, 0.76, 0.12), 0.55, 0.05)
	var wheel_mat := _mat(Color(0.08, 0.09, 0.10), 0.90, 0.0)
	var card_mat := MatLib.get_mat("cardboard")

	# 4 Caster Wheels + Metal Forks
	for wx in [-0.36, 0.36]:
		for wz in [-0.46, 0.46]:
			_add_box(self, Vector3(float(wx), 0.13, float(wz)), Vector3(0.06, 0.08, 0.06), steel_mat)
			var wh := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			wc.top_radius = 0.08
			wc.bottom_radius = 0.08
			wc.height = 0.055
			wh.mesh = wc
			wh.material_override = wheel_mat
			wh.position = Vector3(float(wx), 0.08, float(wz))
			wh.rotation_degrees.z = 90.0
			add_child(wh)

	# Heavy-Duty Flatbed Deck + Non-Slip Rubber Top + Corner Bumpers
	_add_box(self, Vector3(0.0, 0.21, 0.0), Vector3(0.92, 0.08, 1.18), deck_mat)
	_add_box(self, Vector3(0.0, 0.255, 0.0), Vector3(0.84, 0.015, 1.08), mat_pad)
	for cx in [-0.45, 0.45]:
		for cz in [-0.58, 0.58]:
			_add_box(self, Vector3(float(cx), 0.21, float(cz)), Vector3(0.06, 0.09, 0.06), grip_mat)

	# Rear Push Handlebar (+Z side faces the player pushing the cart forward along -Z!)
	_add_box(self, Vector3(-0.38, 0.62, 0.54), Vector3(0.045, 0.80, 0.045), steel_mat)
	_add_box(self, Vector3(0.38, 0.62, 0.54), Vector3(0.045, 0.80, 0.045), steel_mat)
	_add_box(self, Vector3(0.0, 1.00, 0.54), Vector3(0.82, 0.05, 0.05), grip_mat)
	_add_box(self, Vector3(0.0, 0.62, 0.54), Vector3(0.74, 0.035, 0.035), steel_mat)

	# 4 Visual Cargo Crate Slots (2×2 neat layout on deck)
	var slot_offsets: Array[Vector3] = [
		Vector3(-0.21, 0.43, -0.26),
		Vector3(0.21, 0.43, -0.26),
		Vector3(-0.21, 0.43, 0.22),
		Vector3(0.21, 0.43, 0.22),
	]
	for so in slot_offsets:
		var root := Node3D.new()
		root.position = so
		root.visible = false
		add_child(root)
		var holder := Node3D.new()
		holder.position.y = -0.17
		holder.scale = Vector3.ONE * 0.62
		root.add_child(holder)
		var lbl := Label3D.new()
		lbl.font_size = 15
		lbl.pixel_size = 0.0032
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.28, 0.0)
		root.add_child(lbl)
		_slot_visuals.append({"root": root, "holder": holder, "item": "", "lbl": lbl})

	_label = Label3D.new()
	_label.text = "ROLLWAGEN (0/4)"
	_label.font_size = 22
	_label.pixel_size = 0.0042
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 1.24, 0.22)
	add_child(_label)

	_area = Area3D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.02, 1.05, 1.28)
	col.shape = sh
	col.position = Vector3(0.0, 0.54, 0.02)
	_area.add_child(col)
	_area.set_meta("interact_type", "cart")
	_area.set_meta("entity_id", cart_id)
	add_child(_area)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
