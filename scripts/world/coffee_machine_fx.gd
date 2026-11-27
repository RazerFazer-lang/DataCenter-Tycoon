class_name CoffeeMachineFx
extends Node3D
## Kaffeevollautomat zum Benutzen: [E] brüht einen Kaffee (echte Aufnahme), Kaffee läuft in die Tasse,
## es dampft. Danach gibt es den Kaffee-Bonus. Der Host rechnet in DecorManager, hier nur Bild und Ton.
## Koordinaten passen zum Modell prop_coffee_machine (Auslauf über der Tasse bei x -0.08, z 0.18).

const BREW_SOUND := "res://assets/audio/coffee_brew.ogg"
const SPOUT := Vector3(-0.08, 0.897, 0.18)
const CUP_TOP := Vector3(-0.08, 0.884, 0.18)

var machine := "garage"
var _audio: AudioStreamPlayer3D
var _steam: GPUParticles3D
var _stream: MeshInstance3D
var _steam_left := 0.0
var _flow := 0.0


static func make(id: String) -> CoffeeMachineFx:
	var n := CoffeeMachineFx.new()
	n.machine = id
	n.name = "CoffeeFx_" + id
	return n


func _ready() -> void:
	# Bereich zum Benutzen (Gehäuse der Maschine)
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("interact_type", "coffee_machine")
	area.set_meta("entity_id", machine)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.34, 0.46, 0.44)
	cs.shape = bs
	cs.position = Vector3(-0.08, 0.98, 0.02)
	area.add_child(cs)
	add_child(area)
	_audio = AudioStreamPlayer3D.new()
	_audio.position = Vector3(-0.08, 0.96, 0.05)
	_audio.unit_size = 2.2
	_audio.max_distance = 14.0
	if ResourceLoader.exists(BREW_SOUND):
		_audio.stream = load(BREW_SOUND)
	add_child(_audio)
	# Kaffeestrahl aus dem Auslauf
	_stream = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0028
	cm.bottom_radius = 0.0022
	cm.height = SPOUT.y - CUP_TOP.y
	cm.radial_segments = 8
	_stream.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.22, 0.11, 0.04)
	sm.roughness = 0.15
	_stream.material_override = sm
	_stream.position = (SPOUT + CUP_TOP) * 0.5
	_stream.visible = false
	add_child(_stream)
	_steam = _make_steam()
	_steam.position = CUP_TOP + Vector3(0, 0.01, 0)
	add_child(_steam)
	DecorManager.brew_changed.connect(_on_brew)


func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.8
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.10
	pm.gravity = Vector3(0, 0.03, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.2, Color(1, 1, 1, 0.18))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_dot()
	q.material = qm
	p.draw_pass_1 = q
	return p


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


func _on_brew(id: String, on: bool) -> void:
	if id != machine:
		return
	if on:
		if _audio.stream != null:
			_audio.volume_db = linear_to_db(maxf(SettingsManager.get_effective_sfx_gain(), 0.001)) - 2.0
			_audio.play()
		_steam.emitting = true
		_steam_left = DecorManager.BREW_SECS + 14.0
		_flow = 0.0
	else:
		_stream.visible = false


func _process(delta: float) -> void:
	if DecorManager.is_brewing(machine):
		# Erst mahlen, dann läuft der Kaffee (ab etwa einem Drittel der Brühzeit).
		_flow += delta
		_stream.visible = _flow > DecorManager.BREW_SECS * 0.30 and _flow < DecorManager.BREW_SECS * 0.85
	elif _steam_left > 0.0:
		_steam_left -= delta
		if _steam_left <= 0.0:
			_steam.emitting = false
