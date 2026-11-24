class_name SkinEditorPanel
extends HBoxContainer
## Interaktiver 3D-Skin-Editor für das Spielermodell (player.glb / player_realistic.glb).
## Links: Live drehbare 3D-Vorschau auf einem Podest; Rechts: Farbfelder & Accessoire-Auswahl.

const RigHelper := preload("res://scripts/world/humanoid_rig_helper.gd")

var _vp: SubViewport
var _pivot: Node3D
var _avatar: Node3D
var _yaw: float = 0.25
var _dragging: bool = false
var _auto_spin: bool = true

var _opt_headwear: OptionButton
var _opt_glasses: OptionButton
var _swatch_rows: Dictionary = {} # field -> Array[Button]


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	_build_ui()
	refresh_from_settings()


func set_preview_active(active: bool) -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		refresh_from_settings()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _pivot == null:
		return
	if _auto_spin and not _dragging:
		_yaw += delta * 0.45
	_pivot.rotation.y = _yaw


func _build_ui() -> void:
	# LINKS: 3D-Live-Vorschau des Spielers
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	add_child(left)

	var vp_frame := PanelContainer.new()
	vp_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_frame.add_theme_stylebox_override("panel", UIStyle.make_panel(Color(0.05, 0.06, 0.08, 0.96), UIStyle.COL_ACCENT, 8, 1, 0, 0))
	left.add_child(vp_frame)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_preview_input)
	vp_frame.add_child(overlay)

	var vpc := SubViewportContainer.new()
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(vpc)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vpc.add_child(_vp)

	var sky_m := ProceduralSkyMaterial.new()
	sky_m.sky_top_color = Color(0.54, 0.62, 0.74)
	sky_m.sky_horizon_color = Color(0.84, 0.88, 0.92)
	var sky := Sky.new()
	sky.sky_material = sky_m
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.088, 0.112)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
	key.light_energy = 1.45
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, -145.0, 0.0)
	rim.light_energy = 0.65
	_vp.add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.position = Vector3(0.0, 1.05, 2.75)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	_vp.add_child(cam)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	# Podest unter dem Charakter
	var ped := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.44
	pc.bottom_radius = 0.48
	pc.height = 0.06
	ped.mesh = pc
	ped.position = Vector3(0.0, -0.03, 0.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.14, 0.16, 0.20)
	pm.roughness = 0.35
	pm.metallic = 0.65
	ped.material_override = pm
	_pivot.add_child(ped)

	var model_id := PlayerController.REALISTIC_AVATAR_MODEL_ID if ModelLoader.has_custom_model(PlayerController.REALISTIC_AVATAR_MODEL_ID) else PlayerController.AVATAR_MODEL_ID
	_avatar = ModelLoader.instantiate_custom_model(model_id)
	if _avatar != null:
		_pivot.add_child(_avatar)
		var skel: Skeleton3D = RigHelper.find_skeleton(_avatar)
		if skel != null:
			# Mixamo/MakeHuman schauen bereits nach +Z (zur Kamera), nur Höhe, Roughness & entspannte Arme anwenden
			RigHelper.normalize_character_root(_avatar, false)
		else:
			# player.glb schaut nach -Z -> um 180° drehen, damit der Charakter die Kamera anschaut
			_avatar.rotation_degrees.y = 180.0

	var drag_hint := Label.new()
	drag_hint.text = tr("Ziehen zum Drehen (360°)")
	drag_hint.position = Vector2(10, 8)
	drag_hint.add_theme_font_size_override("font_size", 11)
	drag_hint.modulate = UIStyle.COL_GOLD_TEXT
	drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(drag_hint)

	var rand_btn := Button.new()
	rand_btn.text = tr("🎲 Zufälliger Skin")
	rand_btn.custom_minimum_size = Vector2(0, 36)
	UIStyle.style_button(rand_btn, Color(0.14, 0.22, 0.34), UIStyle.COL_ACCENT)
	rand_btn.pressed.connect(_randomize_skin)
	left.add_child(rand_btn)

	# RECHTS: Scrollbare Farb- & Accessoire-Auswahl
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	scroll.add_child(right)

	var hdr := Label.new()
	hdr.text = tr("CHARAKTER & SKIN-EDITOR")
	UIStyle.style_label(hdr, 16, UIStyle.COL_GOLD_TEXT)
	right.add_child(hdr)

	_add_color_row(right, tr("Hautton"), "tone", SettingsManager.SKIN_TONE_COLORS, SettingsManager.SKIN_TONE_LABELS)
	_add_color_row(right, tr("Jacke / Hoodie"), "jacket", SettingsManager.SKIN_JACKET_COLORS, SettingsManager.SKIN_JACKET_LABELS)
	_add_color_row(right, tr("Hose"), "pants", SettingsManager.SKIN_PANTS_COLORS, SettingsManager.SKIN_PANTS_LABELS)
	_add_color_row(right, tr("Haarfarbe"), "hair", SettingsManager.SKIN_HAIR_COLORS, SettingsManager.SKIN_HAIR_LABELS)
	_add_color_row(right, tr("Schuhe"), "shoes", SettingsManager.SKIN_SHOE_COLORS, SettingsManager.SKIN_SHOE_LABELS)
	_add_color_row(right, tr("Akzent / Badge / Lanyard"), "accent", SettingsManager.SKIN_ACCENT_COLORS, SettingsManager.SKIN_ACCENT_LABELS)

	_opt_headwear = _add_option_row(right, tr("Frisur & Kopfbedeckung"), SettingsManager.SKIN_HEADWEAR_LABELS, func(idx: int):
		SettingsManager.skin_headwear = idx
		_save_and_apply()
	)
	_opt_glasses = _add_option_row(right, tr("Brille"), SettingsManager.SKIN_GLASSES_LABELS, func(idx: int):
		SettingsManager.skin_glasses = idx
		_save_and_apply()
	)


func _add_color_row(parent: VBoxContainer, title: String, field: String, colors: Array, labels: Array) -> void:
	var lbl := Label.new()
	lbl.text = title
	UIStyle.style_label(lbl, 12, UIStyle.COL_TEXT_SUB)
	parent.add_child(lbl)

	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 6)
	parent.add_child(flow)
	var btns: Array[Button] = []
	for i in range(colors.size()):
		var col: Color = colors[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 28)
		b.tooltip_text = tr(str(labels[i])) if i < labels.size() else ""
		var shown_col := Color(0.16, 0.56, 0.88) if (field == "jacket" and i == 0) else col
		if field == "jacket" and i == 0:
			b.text = "A"
		var sb := StyleBoxFlat.new()
		sb.bg_color = shown_col
		sb.border_color = Color(0.30, 0.34, 0.40)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		b.add_theme_stylebox_override("normal", sb)
		var cap_i := i
		b.pressed.connect(func():
			match field:
				"jacket": SettingsManager.skin_jacket = cap_i
				"pants": SettingsManager.skin_pants = cap_i
				"tone": SettingsManager.skin_tone = cap_i
				"hair": SettingsManager.skin_hair = cap_i
				"shoes": SettingsManager.skin_shoes = cap_i
				"accent": SettingsManager.skin_accent = cap_i
			_save_and_apply()
		)
		flow.add_child(b)
		btns.append(b)
	_swatch_rows[field] = btns


func _add_option_row(parent: VBoxContainer, title: String, labels: Array, on_sel: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = title
	lbl.custom_minimum_size = Vector2(155, 0)
	UIStyle.style_label(lbl, 12, UIStyle.COL_TEXT_SUB)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in labels:
		opt.add_item(tr(str(s)))
	opt.item_selected.connect(on_sel)
	row.add_child(opt)
	return opt


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_auto_spin = false
	elif event is InputEventMouseMotion and _dragging:
		_yaw += (event as InputEventMouseMotion).relative.x * 0.015


func _randomize_skin() -> void:
	SettingsManager.skin_jacket = randi() % SettingsManager.SKIN_JACKET_COLORS.size()
	SettingsManager.skin_pants = randi() % SettingsManager.SKIN_PANTS_COLORS.size()
	SettingsManager.skin_tone = randi() % SettingsManager.SKIN_TONE_COLORS.size()
	SettingsManager.skin_hair = randi() % SettingsManager.SKIN_HAIR_COLORS.size()
	SettingsManager.skin_shoes = randi() % SettingsManager.SKIN_SHOE_COLORS.size()
	SettingsManager.skin_accent = randi() % SettingsManager.SKIN_ACCENT_COLORS.size()
	SettingsManager.skin_headwear = randi() % SettingsManager.SKIN_HEADWEAR_LABELS.size()
	SettingsManager.skin_glasses = randi() % SettingsManager.SKIN_GLASSES_LABELS.size()
	_save_and_apply()


func _save_and_apply() -> void:
	SfxManager.play("click", -10.0, 1.1)
	SettingsManager.save_settings()
	refresh_from_settings()


func refresh_from_settings() -> void:
	if _avatar != null:
		PlayerController.apply_skin_to_model(_avatar, SettingsManager.get_skin(), Color(0.16, 0.56, 0.88))
	if _opt_headwear != null:
		_opt_headwear.select(clampi(SettingsManager.skin_headwear, 0, _opt_headwear.item_count - 1))
	if _opt_glasses != null:
		_opt_glasses.select(clampi(SettingsManager.skin_glasses, 0, _opt_glasses.item_count - 1))
	var active_map := {
		"jacket": SettingsManager.skin_jacket,
		"pants": SettingsManager.skin_pants,
		"tone": SettingsManager.skin_tone,
		"hair": SettingsManager.skin_hair,
		"shoes": SettingsManager.skin_shoes,
		"accent": SettingsManager.skin_accent,
	}
	for field in active_map.keys():
		var sel_i := int(active_map[field])
		var btns: Array = _swatch_rows.get(field, [])
		for i in range(btns.size()):
			var b := btns[i] as Button
			var sb := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.border_color = UIStyle.COL_GOLD_TEXT if i == sel_i else Color(0.28, 0.32, 0.38)
			sb.set_border_width_all(3 if i == sel_i else 1)
			b.add_theme_stylebox_override("normal", sb)
