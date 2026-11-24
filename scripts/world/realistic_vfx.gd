class_name RealisticVfx
extends RefCounted
## Photorealistischer Soft-Billboard-Rauch, Wasserdampf, Diesel-Abgase, Chiller-Kondensdunst
## & Server-Brand-Rauch/Flammen (256x256 Multi-Oktaven-FBM-Wolkentextur statt harter 3D-Kugeln!).

static var _puff_tex: ImageTexture = null


static func get_smoke_puff_texture() -> ImageTexture:
	if _puff_tex != null:
		return _puff_tex
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n1.frequency = 0.022
	n1.fractal_octaves = 5
	n1.fractal_lacunarity = 2.1
	n1.fractal_gain = 0.52
	n1.seed = 4242

	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.030
	n2.seed = 9191

	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			if r >= 1.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue
			# Weicher organischer Wolken-Rand (kein Kreis!)
			var fbm := clampf(n1.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
			var billow := clampf(1.0 - absf(n2.get_noise_2d(float(x), float(y))), 0.0, 1.0)
			var radial := pow(clampf(1.0 - r, 0.0, 1.0), 1.65)
			var alpha := clampf(radial * (0.55 + fbm * 0.65 + billow * 0.25) - 0.08, 0.0, 1.0)
			# Subtile innere Wolken-Schattierung (oben heller, unten etwas dichter)
			var shade := clampf(0.76 + fbm * 0.26 - dy * 0.14, 0.45, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, alpha))
	img.generate_mipmaps()
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static func make_soft_smoke_material(base_col: Color, unshaded_glow: bool = false, em_col: Color = Color.BLACK, em_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_col
	m.albedo_texture = get_smoke_puff_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.96
	m.metallic = 0.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.75
	# Echtes Wolken-/Dampf-Streulicht (Backlight Scattering): strahlend weiß bei Sonne, natürlich dunkel bei Nacht!
	m.backlight_enabled = true
	m.backlight = Color(base_col.r * 0.88, base_col.g * 0.90, base_col.b * 0.94)
	if unshaded_glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if em_energy > 0.0:
		m.emission_enabled = true
		m.emission = em_col
		m.emission_energy_multiplier = em_energy
	return m


## 1. Dichter realistischer Heizkraftwerk-Wasserdampf (hohe Partikelzahl, Wind-Drift, weiches Ausfaden!)
static func create_chp_steam_plume(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 88
	p.lifetime = 9.0
	p.preprocess = 5.5
	p.randomness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.05
	p.direction = Vector3(0.45, 1.0, -0.18).normalized()
	p.spread = 15.0
	p.gravity = Vector3(0.55, 0.32, -0.20)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.0
	p.damping_min = 0.12
	p.damping_max = 0.25
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0
	p.scale_amount_min = 3.2
	p.scale_amount_max = 5.2
	p.scale_amount_curve = _make_growth_curve(0.45, 2.55)
	p.color_ramp = _make_alpha_ramp(Color(0.96, 0.98, 1.0, 0.0), Color(0.98, 0.99, 1.0, 0.62), Color(0.92, 0.95, 0.98, 0.0))
	var qm := QuadMesh.new()
	qm.size = Vector2(2.6, 2.6)
	qm.material = make_soft_smoke_material(Color(0.98, 0.99, 1.0, 1.0))
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 2. Dieselgenerator-Abgas-Schwaden (durchgehende weiche Industrie-Auspufffahne!)
static func create_diesel_exhaust(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 52
	p.lifetime = 4.5
	p.preprocess = 2.5
	p.randomness = 0.28
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.14
	p.direction = Vector3(0.28, 1.0, -0.12).normalized()
	p.spread = 13.0
	p.gravity = Vector3(0.38, 0.24, -0.14)
	p.initial_velocity_min = 1.1
	p.initial_velocity_max = 1.8
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -24.0
	p.angular_velocity_max = 24.0
	p.scale_amount_min = 0.85
	p.scale_amount_max = 1.55
	p.scale_amount_curve = _make_growth_curve(0.38, 2.35)
	p.color_ramp = _make_alpha_ramp(Color(0.42, 0.45, 0.49, 0.0), Color(0.56, 0.59, 0.63, 0.44), Color(0.72, 0.75, 0.78, 0.0))
	var qm := QuadMesh.new()
	qm.size = Vector2(1.25, 1.25)
	qm.material = make_soft_smoke_material(Color(0.62, 0.65, 0.69, 1.0))
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 3. Feiner Kaltwasserkühler-/Chiller-Kondensdunst (bei Regen/kühler Luft sichtbar!)
static func create_chiller_mist(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 28
	p.lifetime = 3.4
	p.preprocess = 1.5
	p.randomness = 0.40
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.85, 0.08, 0.45)
	p.direction = Vector3(0.18, 1.0, 0.08).normalized()
	p.spread = 22.0
	p.gravity = Vector3(0.20, 0.15, 0.05)
	p.initial_velocity_min = 0.65
	p.initial_velocity_max = 1.25
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_min = 0.65
	p.scale_amount_max = 1.10
	p.scale_amount_curve = _make_growth_curve(0.50, 1.95)
	p.color_ramp = _make_alpha_ramp(Color(0.88, 0.94, 1.0, 0.0), Color(0.90, 0.95, 1.0, 0.24), Color(0.88, 0.94, 1.0, 0.0))
	var qm := QuadMesh.new()
	qm.size = Vector2(1.15, 1.15)
	qm.material = make_soft_smoke_material(Color(0.90, 0.95, 1.0, 1.0))
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 4. Realistischer Server-Brand-Rauch (dichter dunkler Elektronik-Rauch!)
static func create_server_fire_smoke(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 36
	p.lifetime = 2.4
	p.randomness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.26, 0.06, 0.14)
	p.direction = Vector3(0.0, 1.0, 0.22).normalized()
	p.spread = 24.0
	p.gravity = Vector3(0.0, 0.35, 0.05)
	p.initial_velocity_min = 0.55
	p.initial_velocity_max = 1.15
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -45.0
	p.angular_velocity_max = 45.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.72
	p.scale_amount_curve = _make_growth_curve(0.40, 2.20)
	p.color_ramp = _make_alpha_ramp(Color(0.10, 0.10, 0.12, 0.0), Color(0.14, 0.14, 0.16, 0.72), Color(0.28, 0.28, 0.30, 0.0))
	var qm := QuadMesh.new()
	qm.size = Vector2(0.75, 0.75)
	qm.material = make_soft_smoke_material(Color(0.22, 0.22, 0.24, 1.0))
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _make_growth_curve(start_v: float, end_v: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, start_v))
	c.add_point(Vector2(0.45, lerpf(start_v, end_v, 0.62)))
	c.add_point(Vector2(1.0, end_v))
	return c


static func _make_alpha_ramp(c0: Color, c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	g.colors = PackedColorArray([c0, c1, Color(c1.r, c1.g, c1.b, c1.a * 0.65), c2])
	return g
