class_name CoolerProp
extends Node3D
## Goldis-Wärmepumpe im Stil einer Bosch-Luft/Wasser-Wärmepumpe.
## cooler = Außengerät mit einem Lüfter, chiller = Außengerät Pro mit zwei Lüftern,
## indoor_unit = Goldis Innengerät für die Wand (ohne eigenen Stromanschluss).

const INDOOR_TYPE := "indoor_unit"
const FLAP_OPEN_RAD := -1.0
const OUTDOOR_BASE_H := 0.10
const GOLDIS_RED := Color(0.78, 0.07, 0.10)
const GOLDIS_TEXT := Color(0.16, 0.17, 0.19)

var cooler_id: String = ""
var cooler_type: String = "cooler"
var is_showcase_only: bool = false
var _powered: bool = false

var _fan_rotors: Array[Node3D] = []
var _flap: Node3D
var _led_mat: StandardMaterial3D
var _status_label: Label3D
var _power_port_marker: Node3D
var _fan_audio: AudioStreamPlayer3D
var _spin_speed: float = 0.0
var _smooth_vol: float = 0.0


func setup(id: String, p_cooler_type: String = "cooler", p_showcase: bool = false) -> void:
	cooler_id = id
	cooler_type = p_cooler_type
	is_showcase_only = p_showcase
	_build_geometry()
	_setup_audio()


func is_indoor() -> bool:
	return cooler_type == INDOOR_TYPE


func apply_data(data: Dictionary) -> void:
	position = data["pos"]
	rotation.y = float(data["rot_y"])
	_powered = bool(data.get("powered", false))

	if _led_mat != null:
		_led_mat.emission = Color(0.22, 0.72, 0.38) if _powered else Color(0.18, 0.18, 0.20)
		_led_mat.emission_energy_multiplier = 0.85 if _powered else 0.05
	if _status_label != null:
		if is_indoor():
			_status_label.text = "GOLDIS %s\n%s" % [cooler_id.to_upper(), tr("KÜHLT") if _powered else tr("AUSSENGERÄT AUS")]
		else:
			var cooling_val := 40 if cooler_type == "chiller" else 18
			var title := "GOLDIS PRO" if cooler_type == "chiller" else "GOLDIS"
			_status_label.text = "%s  %s\n%s (-%d°C)" % [title, cooler_id.to_upper(), tr("KÜHLT") if _powered else tr("KEIN STROM"), cooling_val]
		_status_label.modulate = Color(0.90, 0.92, 0.94) if _powered else Color(0.92, 0.76, 0.40)


func get_power_port_global_pos() -> Vector3:
	return _power_port_marker.global_position if _power_port_marker != null else global_position


func _setup_audio() -> void:
	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.position = Vector3(0.0, 0.0, 0.12) if is_indoor() else Vector3(0.0, 0.50, 0.25)
	_fan_audio.stream = SfxManager.get_loop_stream("cooler_fan")
	_fan_audio.max_distance = 12.0
	_fan_audio.unit_size = 2.5
	_fan_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_fan_audio.volume_db = -60.0
	add_child(_fan_audio)


func _process(delta: float) -> void:
	var target_spin := 0.0
	if _powered:
		target_spin = 18.0 if cooler_type == "chiller" else (9.0 if is_indoor() else 15.0)
	_spin_speed = lerpf(_spin_speed, target_spin, clampf(delta * 3.0, 0.0, 1.0))
	if _spin_speed > 0.05:
		for r in _fan_rotors:
			r.rotation.z += delta * _spin_speed
	if _flap != null:
		# Luftklappe des Innengeräts öffnet sich, sobald Kälte kommt
		var flap_target := FLAP_OPEN_RAD if _powered else 0.0
		_flap.rotation.x = lerpf(_flap.rotation.x, flap_target, clampf(delta * 1.6, 0.0, 1.0))

	if _fan_audio == null or is_showcase_only:
		return
	var gain := SettingsManager.get_effective_fan_gain()
	var base_gain := 0.72 if cooler_type == "chiller" else (0.22 if is_indoor() else 0.56)
	var target_vol := (base_gain * gain) if (_powered and gain > 0.005) else 0.0
	_smooth_vol = lerpf(_smooth_vol, target_vol, clampf(delta * 3.2, 0.0, 1.0))
	if _smooth_vol <= 0.01:
		if _fan_audio.playing:
			_fan_audio.stop()
	else:
		if not _fan_audio.playing:
			_fan_audio.play(randf_range(0.0, 1.6))
		_fan_audio.volume_db = linear_to_db(_smooth_vol) - 7.0
		var base_pitch := 0.78 if cooler_type == "chiller" else (1.12 if is_indoor() else 0.88)
		_fan_audio.pitch_scale = base_pitch + (_spin_speed / 18.0) * 0.26


func _build_geometry() -> void:
	var custom_m := ModelLoader.instantiate_custom_model(cooler_type)
	if custom_m != null:
		add_child(custom_m)
	if is_indoor():
		_build_indoor_unit()
	else:
		_build_outdoor_unit()


# ==============================================================================
# AUSSENGERÄT: weißes Gehäuse, runder Lüfter mit waagrechtem Gitter, Logo oben rechts,
# Verdampferlamellen hinten, Stromanschluss an der rechten Seite
# ==============================================================================
func _build_outdoor_unit() -> void:
	var is_pro := cooler_type == "chiller"
	var w := 1.10 if is_pro else 1.00
	var h := 1.38 if is_pro else 0.86
	var d := 0.46 if is_pro else 0.42
	var y0 := OUTDOOR_BASE_H
	var cy := y0 + h * 0.5
	var front_z := d * 0.5
	var side_x := w * 0.5

	var body_mat := _mat(Color(0.94, 0.95, 0.95), 0.36, 0.04)
	var side_mat := _mat(Color(0.88, 0.89, 0.90), 0.42, 0.06)
	var fan_well_mat := _mat(Color(0.07, 0.08, 0.09), 0.85, 0.05)
	var grille_mat := _mat(Color(0.26, 0.27, 0.29), 0.45, 0.55)
	var blade_mat := _mat(Color(0.18, 0.19, 0.21), 0.55, 0.20)
	var foot_mat := _mat(Color(0.17, 0.18, 0.19), 0.80, 0.10)
	var coil_mat := _mat(Color(0.55, 0.57, 0.60), 0.40, 0.70)
	var copper_mat := MatLib.get_mat("copper_metal")
	var insul_mat := _mat(Color(0.08, 0.08, 0.08), 0.90, 0.0)

	if not is_showcase_only:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(w + 0.04, y0 + h + 0.03, d + 0.06)
		col.shape = sh
		col.position = Vector3(0.0, (y0 + h + 0.03) * 0.5, 0.0)
		sb.add_child(col)
		add_child(sb)

	# Bodenkonsole aus zwei Profilschienen
	for fxv in [-0.36, 0.36]:
		var fx := float(fxv) * w
		_add_box(self, Vector3(fx, y0 * 0.5, 0.0), Vector3(0.07, y0, d + 0.10), foot_mat)
		_add_box(self, Vector3(fx, 0.006, 0.0), Vector3(0.12, 0.012, d + 0.14), foot_mat)

	# Gehäuse, überstehender Deckel, dunkle Sockelleiste, Fugen zur Front
	_add_box(self, Vector3(0.0, cy, 0.0), Vector3(w, h, d), body_mat)
	_add_box(self, Vector3(0.0, y0 + h + 0.012, 0.0), Vector3(w + 0.02, 0.024, d + 0.02), body_mat)
	_add_box(self, Vector3(0.0, y0 + 0.02, 0.0), Vector3(w + 0.006, 0.04, d + 0.006), foot_mat)
	for sxv in [-1.0, 1.0]:
		_add_box(self, Vector3(float(sxv) * (side_x - 0.012), cy, front_z + 0.002), Vector3(0.006, h - 0.06, 0.004), side_mat)

	# Lüfter: Standard einer, Pro zwei übereinander
	var fan_r := 0.29 if is_pro else 0.33
	var fan_x := -w * 0.10
	var fan_ys: Array = [y0 + 0.36, y0 + 1.0] if is_pro else [y0 + h * 0.47]
	for fyv in fan_ys:
		_build_fan(Vector3(fan_x, float(fyv), front_z), fan_r, fan_well_mat, grille_mat, blade_mat, side_mat)

	# Goldis-Logo oben rechts, Modellbezeichnung und Status-LED darunter
	var logo_x := side_x - 0.30
	var logo_y := y0 + h - 0.085
	_add_goldis_logo(self, Vector3(logo_x, logo_y, front_z), 0.045)
	var model_name := "WP 7000i" if is_pro else "WP 5000i"
	_add_text(self, model_name, Vector3(logo_x + 0.16, logo_y - 0.07, front_z + 0.004), 48, 0.0007, Color(0.42, 0.44, 0.47))
	_led_mat = _make_led_mat()
	_add_box(self, Vector3(logo_x + 0.16, logo_y - 0.11, front_z + 0.003), Vector3(0.05, 0.012, 0.006), _led_mat)

	# Verdampfer-Lamellen auf der Rückseite (dort saugt die Wärmepumpe die Luft an)
	_add_box(self, Vector3(0.0, cy, -front_z - 0.004), Vector3(w - 0.08, h - 0.12, 0.008), fan_well_mat)
	var coil_w := w - 0.12
	var fin_count := int(coil_w / 0.045)
	for i in range(fin_count + 1):
		var fin_x := -coil_w * 0.5 + float(i) * 0.045
		_add_box(self, Vector3(fin_x, cy, -front_z - 0.010), Vector3(0.008, h - 0.14, 0.008), coil_mat)

	# Lüftungsschlitze auf der linken Seite
	var louvers := int((h - 0.2) / 0.06)
	for i in range(louvers):
		var ly := y0 + 0.12 + float(i) * 0.06
		_add_box(self, Vector3(-side_x - 0.004, ly, 0.0), Vector3(0.008, 0.022, d - 0.10), side_mat)

	# Rechte Seite: Servicedeckel mit gelber Strombuchse und Kältemittelleitungen
	var port_y := y0 + h * 0.55
	var port_z := -d * 0.18
	_add_box(self, Vector3(side_x + 0.004, y0 + h * 0.45, -d * 0.05), Vector3(0.008, h * 0.60, d * 0.62), side_mat)
	_add_box(self, Vector3(side_x + 0.03, port_y, port_z), Vector3(0.05, 0.12, 0.15), foot_mat)
	var p_mat := _mat(Color(0.84, 0.66, 0.14), 0.48, 0.08)
	_add_box(self, Vector3(side_x + 0.058, port_y, port_z), Vector3(0.012, 0.08, 0.10), p_mat)
	_power_port_marker = Node3D.new()
	_power_port_marker.position = Vector3(side_x + 0.09, port_y, port_z)
	add_child(_power_port_marker)

	for pi in range(2):
		var pz := -front_z + 0.06 + float(pi) * 0.07
		var pr := 0.022 if pi == 0 else 0.016
		_add_cylinder(self, Vector3(side_x + 0.05, y0 + 0.10, pz), pr, 0.40, insul_mat, Vector3.ZERO)
		_add_cylinder(self, Vector3(side_x + 0.025, y0 + 0.28, pz), pr * 0.6, 0.06, copper_mat, Vector3(0.0, 0.0, 90.0))

	if not is_showcase_only:
		_add_area(Vector3(side_x + 0.08, port_y, port_z), Vector3(0.22, 0.26, 0.30), "power_port")
		_add_area(Vector3(0.0, (y0 + h) * 0.5, 0.02), Vector3(w + 0.06, y0 + h, d + 0.10), "cooler_unit")

	_status_label = Label3D.new()
	_status_label.text = cooler_id.to_upper()
	_status_label.font_size = 24
	_status_label.pixel_size = 0.0042
	_status_label.position = Vector3(0.0, y0 + h + 0.28, 0.15)
	add_child(_status_label)


func _build_fan(c: Vector3, r: float, well_mat: Material, grille_mat: Material, blade_mat: Material, rim_mat: Material) -> void:
	_add_disc(self, c + Vector3(0.0, 0.0, 0.003), r, 0.006, well_mat)
	_add_ring(self, c + Vector3(0.0, 0.0, 0.010), r + 0.028, r, rim_mat)

	var rotor := Node3D.new()
	rotor.position = c + Vector3(0.0, 0.0, 0.026)
	add_child(rotor)
	for bi in range(3):
		var piv := Node3D.new()
		piv.rotation.z = TAU * float(bi) / 3.0
		rotor.add_child(piv)
		var tilt := Node3D.new()
		tilt.position = Vector3(r * 0.46, 0.0, 0.0)
		tilt.rotation.x = 0.35
		piv.add_child(tilt)
		_add_box(tilt, Vector3.ZERO, Vector3(r * 0.78, r * 0.34, 0.006), blade_mat)
	_add_disc(rotor, Vector3.ZERO, r * 0.16, 0.03, blade_mat)
	_fan_rotors.append(rotor)

	# Schutzgitter mit waagrechten Stäben, Mittelsteg, Rahmenring und Nabenkappe
	var grille_z := c.z + 0.056
	var bars := int(r / 0.034)
	var spacing := r / (float(bars) + 0.5)
	for i in range(-bars, bars + 1):
		var yy := float(i) * spacing
		var half := sqrt(maxf(r * r - yy * yy, 0.0))
		if half < 0.02:
			continue
		_add_box(self, Vector3(c.x, c.y + yy, grille_z), Vector3(half * 2.0, 0.007, 0.006), grille_mat)
	_add_box(self, Vector3(c.x, c.y, grille_z + 0.004), Vector3(0.012, r * 2.0, 0.006), grille_mat)
	_add_ring(self, Vector3(c.x, c.y, grille_z), r + 0.006, r - 0.012, grille_mat)
	_add_disc(self, Vector3(c.x, c.y, grille_z + 0.006), r * 0.13, 0.008, grille_mat)


# ==============================================================================
# INNENGERÄT: weißes Wandgerät mit Frontblende, Luftklappe unten, Display und Logo.
# Der Ursprung liegt in der Gerätemitte, die Rückseite zeigt zur Wand (-Z).
# ==============================================================================
func _build_indoor_unit() -> void:
	var w := 0.96
	var h := 0.30
	var d := 0.22
	var front_z := d * 0.5
	var body_mat := _mat(Color(0.96, 0.96, 0.95), 0.32, 0.02)
	var front_mat := _mat(Color(0.985, 0.985, 0.975), 0.22, 0.02)
	var dark_mat := _mat(Color(0.12, 0.13, 0.14), 0.60, 0.10)
	var grey_mat := _mat(Color(0.80, 0.81, 0.82), 0.40, 0.10)

	# Montageplatte, Gehäuse, Frontblende
	_add_box(self, Vector3(0.0, 0.0, -front_z + 0.005), Vector3(w - 0.10, h - 0.06, 0.01), grey_mat)
	_add_box(self, Vector3(0.0, 0.0, 0.0), Vector3(w, h, d), body_mat)
	_add_box(self, Vector3(0.0, 0.03, front_z + 0.006), Vector3(w - 0.02, 0.22, 0.012), front_mat)

	# Ansauggitter oben
	for i in range(6):
		_add_box(self, Vector3(0.0, h * 0.5 + 0.002, -front_z + 0.035 + float(i) * 0.03), Vector3(w - 0.06, 0.004, 0.008), grey_mat)

	# Luftauslass unten und die Klappe, die sich bei Betrieb öffnet
	_add_box(self, Vector3(0.0, -0.12, front_z - 0.03), Vector3(w - 0.14, 0.035, 0.07), dark_mat)
	_flap = Node3D.new()
	_flap.position = Vector3(0.0, -0.08, front_z + 0.006)
	add_child(_flap)
	_add_box(_flap, Vector3(0.0, -0.035, 0.0), Vector3(w - 0.14, 0.07, 0.008), front_mat)

	# Logo links oben, Display und Status-LED rechts
	_add_goldis_logo(self, Vector3(-0.38, 0.09, front_z + 0.012), 0.022)
	_add_box(self, Vector3(0.32, 0.0, front_z + 0.013), Vector3(0.07, 0.03, 0.004), dark_mat)
	_led_mat = _make_led_mat()
	_add_box(self, Vector3(0.32, 0.0, front_z + 0.016), Vector3(0.03, 0.012, 0.004), _led_mat)

	if not is_showcase_only:
		_add_area(Vector3(0.0, 0.0, 0.03), Vector3(w + 0.06, h + 0.08, d + 0.10), "cooler_unit")

	_status_label = Label3D.new()
	_status_label.text = cooler_id.to_upper()
	_status_label.font_size = 22
	_status_label.pixel_size = 0.0036
	_status_label.position = Vector3(0.0, -0.27, 0.14)
	add_child(_status_label)


# ==============================================================================
# HILFSFUNKTIONEN
# ==============================================================================
## Rote Scheibe mit weißem Ring und "G", rechts daneben der Schriftzug GOLDIS.
func _add_goldis_logo(parent: Node3D, at: Vector3, disc_r: float) -> void:
	var red_mat := _mat(GOLDIS_RED, 0.40, 0.10)
	var white_mat := _mat(Color(0.97, 0.97, 0.97), 0.35, 0.05)
	_add_disc(parent, at + Vector3(0.0, 0.0, 0.003), disc_r, 0.006, red_mat)
	_add_ring(parent, at + Vector3(0.0, 0.0, 0.007), disc_r * 0.86, disc_r * 0.78, white_mat)
	_add_text(parent, "G", at + Vector3(0.0, 0.0, 0.010), 64, disc_r * 1.3 / 64.0, Color(1.0, 1.0, 1.0))
	_add_text(parent, "GOLDIS", at + Vector3(disc_r * 3.7, 0.0, 0.004), 64, disc_r * 1.25 / 64.0, GOLDIS_TEXT)


func _make_led_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.65, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.22, 0.65, 0.35)
	m.emission_energy_multiplier = 0.08
	return m


func _add_area(pos: Vector3, size: Vector3, interact_type: String) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	area.position = pos
	area.add_child(col)
	area.set_meta("interact_type", interact_type)
	area.set_meta("entity_id", cooler_id)
	add_child(area)
	return area


func _add_text(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel_size: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	parent.add_child(l)
	return l


func _add_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 32
	mi.mesh = cm
	mi.material_override = mat
	mi.rotation_degrees = rot_deg
	mi.position = pos
	parent.add_child(mi)
	return mi


## Flache Scheibe, deren Fläche nach +Z zeigt.
func _add_disc(parent: Node3D, pos: Vector3, radius: float, depth: float, mat: Material) -> MeshInstance3D:
	return _add_cylinder(parent, pos, radius, depth, mat, Vector3(90.0, 0.0, 0.0))


## Ring, dessen Fläche nach +Z zeigt.
func _add_ring(parent: Node3D, pos: Vector3, outer_r: float, inner_r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = 40
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = mat
	mi.rotation_degrees.x = 90.0
	mi.position = pos
	parent.add_child(mi)
	return mi


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