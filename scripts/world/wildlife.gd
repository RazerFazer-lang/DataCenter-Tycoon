class_name Wildlife
extends Node3D
## Vögel und kleine Tiere rund um die Halle. Läuft auf jedem Rechner für sich (nur fürs Auge und Ohr).
## Spatzen, Tauben, Krähen und Schwalben fliegen, landen, picken, hüpfen, fliehen und singen.
## Katze, Eichhörnchen, Igel, Schmetterlinge kommen je nach Tageszeit und Jahreszeit.

const BIRDS := [["sparrow", 7], ["pigeon", 4], ["crow", 3], ["swallow", 5]]
## Landeplätze am Boden (Radius) und auf Zäunen, Dach, Tränke.
const GROUND := [Vector4(-8.4, 0.0, 1.6, 1.6), Vector4(-7.6, 0.0, -0.4, 0.9), Vector4(14.0, 0.0, -7.6, 2.6), Vector4(24.2, 0.0, 3.0, 1.6), Vector4(8.8, 0.0, 8.6, 1.4), Vector4(-7.0, 0.0, 8.4, 1.5), Vector4(0.0, 0.0, 12.6, 2.6)]
const PERCH: Array[Vector3] = [Vector3(-10.8, 1.98, -3.0), Vector3(-10.8, 1.98, 1.4), Vector3(-10.8, 1.98, 6.2), Vector3(26.5, 1.98, -2.0), Vector3(26.5, 1.98, 4.0), Vector3(9.0, 1.98, -9.5), Vector3(16.0, 1.98, -9.5), Vector3(-9.2, 0.79, 0.45), Vector3(-9.35, 0.79, 0.75), Vector3(2.0, 4.40, 4.9), Vector3(6.0, 4.40, 4.9), Vector3(-5.0, 4.40, -4.9), Vector3(14.0, 4.40, 4.9), Vector3(18.0, 1.98, 10.35), Vector3(22.0, 1.98, 10.35)]
const FEEDER := Vector3(-7.6, 1.335, -0.4)
const SPEED := {"sparrow": 6.5, "pigeon": 8.5, "crow": 7.5, "swallow": 11.0}
const FLAP := {"sparrow": 15.0, "pigeon": 8.0, "crow": 4.6, "swallow": 11.0}
const FEAR := {"sparrow": 3.2, "pigeon": 2.4, "crow": 5.0, "swallow": 6.0}

static var _mat_done: Dictionary = {}

var _birds: Array = []
var _cat: Dictionary = {}
var _squirrel: Dictionary = {}
var _hedgehog: Dictionary = {}
var _flies: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for e in BIRDS:
		for i in int(e[1]):
			_birds.append(_make_bird(str(e[0]), i))
	_cat = _make_animal("animal_cat", Vector3(-9.6, 0, 6.6))
	_squirrel = _make_animal("animal_squirrel", Vector3(12.5, 0, -8.0))
	_hedgehog = _make_animal("animal_hedgehog", Vector3(18.0, 0, -8.4))
	for i in 6:
		var m := _model("butterfly")
		add_child(m)
		var col: Color = [Color(0.95, 0.60, 0.12), Color(0.98, 0.96, 0.90), Color(0.95, 0.88, 0.25), Color(0.45, 0.65, 0.95), Color(0.90, 0.35, 0.15), Color(0.98, 0.96, 0.90)][i]
		for n in ["WingL", "WingR"]:
			var mi := m.find_child(n, true, false) as MeshInstance3D
			if mi != null:
				var mt := (mi.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
				mt.albedo_color = col
				mi.material_override = mt
		_flies.append({"n": m, "l": m.find_child("WingL", true, false), "r": m.find_child("WingR", true, false), "s": _rng.randf() * 50.0, "home": [Vector3(-8.2, 0, -7.6), Vector3(-7.0, 0, -8.0), Vector3(-9.4, 0, 2.2), Vector3(16.0, 0, -8.0), Vector3(24.6, 0, -3.0), Vector3(8.0, 0, 9.0)][i]})


static func _model(id: String) -> Node3D:
	var m := ModelLoader.instantiate_custom_model(id)
	if m == null:
		return Node3D.new()
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mt := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mt != null and not _mat_done.has(mt):
				_mat_done[mt] = true
				mt.vertex_color_use_as_albedo = mt.resource_name in ["Bird", "Fur", "Spike", "Wing"]
				mt.vertex_color_is_srgb = false
				if mt.resource_name in ["Bird", "Wing", "Spike"]:
					mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.visibility_range_end = 75.0
	return m


# ---------------------------------------------------------------- Vögel

func _make_bird(kind: String, i: int) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var m := _model("bird_" + kind)
	root.add_child(m)
	var b := {"kind": kind, "n": root, "m": m, "head": m.find_child("Head", true, false), "wl": m.find_child("WingL", true, false), "wr": m.find_child("WingR", true, false), "wl2": m.find_child("WingL2", true, false), "wr2": m.find_child("WingR2", true, false), "tail": m.find_child("Tail", true, false), "legs": m.find_child("Legs", true, false),
		"state": "sit", "t": _rng.randf_range(0.5, 6.0), "s": _rng.randf() * 100.0, "vel": Vector3.ZERO, "fold": 1.0, "hop": 0.0, "peck": 0.0, "sing": _rng.randf_range(3.0, 20.0), "to": Vector3.ZERO, "flap": 0.0, "dive": 0.0}
	root.position = _spot(kind, i)
	root.rotation.y = _rng.randf() * TAU
	if kind == "swallow":
		b["state"] = "soar"
		root.position = Vector3(_rng.randf_range(-20, 20), 9.0, _rng.randf_range(0, 26))
	return b


func _spot(kind: String, i: int = -1) -> Vector3:
	var r := _rng.randf()
	if kind == "sparrow" and float(OutdoorManager.state["feed"]) > 0.05 and r < 0.55:
		return FEEDER + Vector3(_rng.randf_range(-0.13, 0.13), 0, _rng.randf_range(-0.10, 0.10))
	if kind in ["crow", "swallow"] and r < 0.6 or r < 0.3:
		return PERCH[_rng.randi() % PERCH.size()]
	var g: Vector4 = GROUND[(_rng.randi() if i < 0 else (i * 3 + kind.length())) % GROUND.size()]
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * g.w
	return Vector3(g.x + cos(a) * d, -0.02, g.z + sin(a) * d)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.z < -60.0:
		visible = false
		return
	visible = true
	_t += delta
	var active := GameState.is_active
	var tod := GameState.time_of_day if active else 0.4
	var w: String = GameState.weather_state if active else "clear"
	var night := tod < 0.23 or tod > 0.79
	var bad := w in ["rain", "storm"]
	var lp := get_tree().get_first_node_in_group("local_player") as Node3D
	var pp := lp.global_position if lp != null and lp.is_inside_tree() else Vector3(999, 0, 0)
	var se := OutdoorManager.season()
	for b in _birds:
		# Schwalben sind im Winter im Süden. Nachts und bei Sturm schlafen alle.
		var away: bool = night or (bad and str(b["kind"]) != "crow") or (str(b["kind"]) == "swallow" and (se > 2.3 and se < 3.95))
		(b["n"] as Node3D).visible = not away
		if not away:
			_bird(b, delta, pp, cam.global_position)
	_update_cat(delta, pp, night)
	_update_squirrel(delta, pp, night or bad, se)
	_update_hedgehog(delta, pp, night, se)
	_update_butterflies(delta, not night and not bad and se > 0.15 and se < 2.4)


func _bird(b: Dictionary, delta: float, pp: Vector3, cp: Vector3) -> void:
	var n: Node3D = b["n"]
	var kind := str(b["kind"])
	var far := n.position.distance_squared_to(cp) > 3600.0
	b["t"] = float(b["t"]) - delta
	match str(b["state"]):
		"soar":
			_soar(b, delta)
		"fly":
			_fly(b, delta)
		_:
			_sit(b, delta, pp)
	if far:
		return
	# Flügel: gefaltet am Körper oder schlagend
	var flying: bool = str(b["state"]) in ["fly", "soar"]
	b["fold"] = lerpf(float(b["fold"]), 0.0 if flying else 1.0, 1.0 - exp(-delta * 9.0))
	var fo: float = b["fold"]
	var beat: float = float(FLAP[kind])
	var glide := 1.0
	if str(b["state"]) == "soar":
		glide = 0.25 + 0.75 * smoothstep(-0.2, 0.5, sin(_t * 1.3 + float(b["s"])))
	elif kind in ["crow", "pigeon"]:
		glide = 0.35 + 0.65 * smoothstep(-0.4, 0.3, sin(_t * 0.9 + float(b["s"])))
	b["flap"] = float(b["flap"]) + delta * beat * (0.4 + 0.6 * glide)
	var f := sin(float(b["flap"])) * 0.85 * glide + 0.12
	var f2 := sin(float(b["flap"]) - 0.9) * 0.6 * glide
	for s in [-1.0, 1.0]:
		var w1: Node3D = b["wl"] if s < 0.0 else b["wr"]
		var w2: Node3D = b["wl2"] if s < 0.0 else b["wr2"]
		if w1 == null or w2 == null:
			continue
		w1.rotation = Vector3(0.0, 0.0, f * s).lerp(Vector3(0.10, -1.42 * s, -0.95 * s), fo)
		w2.rotation = Vector3(0.0, 0.0, f2 * s).lerp(Vector3(0.0, -0.10 * s, 0.0), fo)
		w2.scale = Vector3.ONE.lerp(Vector3(0.72, 1.0, 0.8), fo)
	(b["legs"] as Node3D).rotation.x = lerpf(0.0, -1.2, 1.0 - fo)
	(b["tail"] as Node3D).rotation.x = 0.1 * sin(_t * 2.0 + float(b["s"])) + (0.25 if flying else 0.0)
	(b["m"] as Node3D).rotation.x = lerpf(0.0, -0.45, 1.0 - fo)
	var hd: Node3D = b["head"]
	var pk := float(b["peck"])
	hd.rotation.x = lerpf(hd.rotation.x, 0.45 if flying else -pk * 1.1, 1.0 - exp(-delta * 18.0))
	if not flying:
		# Vögel schauen ruckartig
		hd.rotation.y = lerpf(hd.rotation.y, sin(floor(_t * 1.4 + float(b["s"])) * 12.7) * 0.8, 1.0 - exp(-delta * 16.0))


func _sit(b: Dictionary, delta: float, pp: Vector3) -> void:
	var n: Node3D = b["n"]
	var kind := str(b["kind"])
	var fear: float = FEAR[kind]
	var d := Vector2(pp.x - n.position.x, pp.z - n.position.z).length()
	if d < fear and absf(pp.y - n.position.y) < 4.0:
		_take_off(b, true)
		return
	if not _cat.is_empty() and (_cat["n"] as Node3D).visible and (_cat["n"] as Node3D).position.distance_to(n.position) < 1.7:
		_take_off(b, true)
		return
	# Picken und hüpfen
	b["peck"] = maxf(0.0, sin(_t * 9.0 + float(b["s"]))) if fposmod(_t * 0.23 + float(b["s"]), 1.0) < 0.45 and n.position.y < 1.5 else 0.0
	b["hop"] = maxf(0.0, float(b["hop"]) - delta * 3.4)
	if n.position.y < 0.2:
		var walk := kind in ["pigeon", "crow"]
		if float(b["hop"]) <= 0.0 and float(b["peck"]) <= 0.0 and _rng.randf() < delta * (0.9 if not walk else 0.7):
			b["hop"] = 1.0
			n.rotation.y += _rng.randf_range(-0.9, 0.9)
		if float(b["hop"]) > 0.0:
			var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, n.rotation.y)
			var np := n.position + fwd * delta * (0.55 if not walk else 0.30)
			if not OutdoorWorld.HALL.grow(0.4).has_point(Vector2(np.x, np.z)):
				n.position = np
			n.position.y = -0.02 + (sin(float(b["hop"]) * PI) * 0.035 if not walk else 0.0)
			if walk:
				(b["head"] as Node3D).position.z += 0.0
	b["sing"] = float(b["sing"]) - delta
	if float(b["sing"]) <= 0.0:
		b["sing"] = _rng.randf_range(7.0, 26.0)
		if n.position.distance_to(pp) < 24.0 and GameState.is_active:
			SfxManager.play_at("bird_" + kind, n.global_position, -9.0, _rng.randf_range(0.92, 1.1))
	if float(b["t"]) <= 0.0:
		_take_off(b, false)


func _take_off(b: Dictionary, scared: bool) -> void:
	var n: Node3D = b["n"]
	b["state"] = "fly"
	b["to"] = _spot(str(b["kind"]))
	b["t"] = 9.0
	if scared:
		# Weit weg, und die anderen in der Nähe gleich mit
		for k in 6:
			if (b["to"] as Vector3).distance_to(n.position) > 9.0:
				break
			b["to"] = _spot(str(b["kind"]))
		for o in _birds:
			if o != b and str(o["state"]) == "sit" and (o["n"] as Node3D).position.distance_to(n.position) < 1.6:
				o["t"] = minf(float(o["t"]), _rng.randf_range(0.05, 0.4))
	b["vel"] = Vector3(0, 2.2, 0) + Vector3(0, 0, -1.5).rotated(Vector3.UP, n.rotation.y)
	if n.position.distance_to(get_viewport().get_camera_3d().global_position) < 14.0 and GameState.is_active:
		SfxManager.play_at("bird_wings", n.global_position, -14.0, {"sparrow": 1.5, "pigeon": 0.9, "crow": 0.75, "swallow": 1.4}[str(b["kind"])])


func _fly(b: Dictionary, delta: float) -> void:
	var n: Node3D = b["n"]
	var to: Vector3 = b["to"]
	var v: Vector3 = b["vel"]
	var diff := to - n.position
	var flat := Vector2(diff.x, diff.z).length()
	var sp: float = SPEED[str(b["kind"])]
	var aim := to + Vector3(0, clampf(flat * 0.32, 0.0, 5.0), 0)
	# Nicht durch die Halle
	if flat > 3.0 and n.position.y < 5.6 and OutdoorWorld.HALL.grow(1.5).has_point(Vector2(n.position.x, n.position.z) + Vector2(v.x, v.z) * 0.5):
		aim.y = 7.5
	var want := (aim - n.position).normalized() * sp * clampf(flat / 3.0, 0.35, 1.0)
	v = v.lerp(want, 1.0 - exp(-delta * (2.6 if flat > 2.0 else 5.0)))
	n.position += v * delta
	b["vel"] = v
	_face_dir(n, v, delta, 7.0)
	if n.position.distance_to(to) < 0.16 or (flat < 0.4 and float(b["t"]) < 0.0):
		n.position = to
		b["state"] = "sit"
		b["t"] = _rng.randf_range(4.0, 18.0)
		n.rotation.x = 0.0
		n.rotation.z = 0.0
		if str(b["kind"]) == "swallow":
			b["t"] = _rng.randf_range(2.0, 6.0)
	elif float(b["t"]) < -6.0:
		b["to"] = _spot(str(b["kind"]))
		b["t"] = 9.0
	if str(b["kind"]) == "swallow" and flat > 6.0 and _rng.randf() < delta * 0.3:
		b["state"] = "soar"
		b["t"] = _rng.randf_range(15.0, 40.0)


## Schwalben jagen in weiten Bögen um die Halle.
func _soar(b: Dictionary, delta: float) -> void:
	var n: Node3D = b["n"]
	var s: float = b["s"]
	var c := Vector3(6.0 + sin(_t * 0.05 + s) * 14.0, 8.0 + sin(_t * 0.37 + s * 2.0) * 3.0, 6.0 + cos(_t * 0.043 + s) * 12.0)
	var a := _t * 0.55 + s * 3.0
	var target := c + Vector3(cos(a) * 11.0, sin(a * 1.7) * 2.0 - 1.0, sin(a) * 9.0)
	var v: Vector3 = b["vel"]
	v = v.lerp((target - n.position).normalized() * float(SPEED["swallow"]), 1.0 - exp(-delta * 1.8))
	if n.position.y < 5.4 and OutdoorWorld.HALL.grow(2.0).has_point(Vector2(n.position.x, n.position.z)):
		v.y = maxf(v.y, 3.0)
	if n.position.y < 1.2:
		v.y = maxf(v.y, 2.0)
	n.position += v * delta
	b["vel"] = v
	_face_dir(n, v, delta, 5.0)
	if float(b["t"]) <= 0.0:
		b["state"] = "fly"
		b["to"] = PERCH[_rng.randi() % PERCH.size()]
		b["t"] = 9.0


func _face_dir(n: Node3D, v: Vector3, delta: float, rate: float) -> void:
	if Vector2(v.x, v.z).length() < 0.05:
		return
	var yaw := atan2(-v.x, -v.z)
	var turn := angle_difference(n.rotation.y, yaw)
	n.rotation.y = lerp_angle(n.rotation.y, yaw, 1.0 - exp(-delta * rate))
	n.rotation.x = lerpf(n.rotation.x, clampf(atan2(v.y, Vector2(v.x, v.z).length()), -0.8, 0.8), 1.0 - exp(-delta * rate))
	n.rotation.z = lerpf(n.rotation.z, clampf(turn * 1.2, -0.9, 0.9), 1.0 - exp(-delta * rate))


# ---------------------------------------------------------------- Vierbeiner

func _make_animal(id: String, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var m := _model(id)
	root.add_child(m)
	var a := {"n": root, "m": m, "head": m.find_child("Head", true, false), "tail": m.find_child("Tail", true, false), "legs": [], "state": "idle", "t": 3.0, "to": pos, "ph": 0.0, "sp": 0.0}
	for l in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		a["legs"].append(m.find_child(l, true, false))
	return a


func _walk_to(a: Dictionary, delta: float, speed: float, stride: float, bound: bool = false) -> bool:
	var n: Node3D = a["n"]
	var d: Vector3 = (a["to"] as Vector3) - n.position
	d.y = 0.0
	var go := d.length() > 0.12
	a["sp"] = lerpf(float(a["sp"]), speed if go else 0.0, 1.0 - exp(-delta * 5.0))
	if go:
		var yaw := atan2(-d.x, -d.z)
		n.rotation.y = lerp_angle(n.rotation.y, yaw, 1.0 - exp(-delta * 5.0))
		n.position += Vector3(0, 0, -1).rotated(Vector3.UP, n.rotation.y) * float(a["sp"]) * delta
	a["ph"] = float(a["ph"]) + delta * float(a["sp"]) / stride * TAU
	var k := clampf(float(a["sp"]) / 0.4, 0.0, 1.0)
	var off := [0.0, PI, PI, 0.0] if not bound else [0.0, 0.4, PI, PI + 0.4]
	for i in 4:
		var l: Node3D = a["legs"][i]
		if l != null:
			l.rotation.x = sin(float(a["ph"]) + float(off[i])) * 0.55 * k
	(a["m"] as Node3D).position.y = absf(sin(float(a["ph"]))) * (0.06 if bound else 0.008) * k
	(a["m"] as Node3D).rotation.x = sin(float(a["ph"])) * (0.18 if bound else 0.02) * k
	return not go


func _free_point() -> Vector3:
	for i in 12:
		var p := Vector3(_rng.randf_range(-10.2, 26.0), -0.02, _rng.randf_range(-9.0, 9.8))
		if not OutdoorWorld.HALL.grow(0.8).has_point(Vector2(p.x, p.z)) and not (absf(p.x) < 4.0 and p.z > 4.5):
			return p
	return Vector3(-8.5, -0.02, 2.0)


## Um die Halle herum: über Eckpunkte gehen statt durch die Wand.
func _route(from: Vector3, to: Vector3) -> Vector3:
	var r := OutdoorWorld.HALL.grow(0.9)
	var steps := 14
	for i in range(1, steps):
		var p := from.lerp(to, i / float(steps))
		if r.has_point(Vector2(p.x, p.z)):
			var best := to
			var bd := 1e9
			for c in [Vector3(r.position.x - 0.3, -0.02, r.position.y - 0.3), Vector3(r.end.x + 0.3, -0.02, r.position.y - 0.3), Vector3(r.position.x - 0.3, -0.02, r.end.y + 0.3), Vector3(r.end.x + 0.3, -0.02, r.end.y + 0.3)]:
				var d := from.distance_to(c) + (c as Vector3).distance_to(to)
				if from.distance_to(c) > 0.5 and d < bd:
					var clear := true
					for k in range(1, 8):
						var q := from.lerp(c, k / 8.0)
						if r.grow(-0.2).has_point(Vector2(q.x, q.z)):
							clear = false
					if clear:
						bd = d
						best = c
			return best
	return to


func _update_cat(delta: float, pp: Vector3, night: bool) -> void:
	var a := _cat
	var n: Node3D = a["n"]
	if n == null:
		return
	n.visible = not (GameState.is_active and GameState.weather_state == "storm")
	if not n.visible:
		return
	a["t"] = float(a["t"]) - delta
	var near := n.position.distance_to(pp) < 2.4
	var tail: Node3D = a["tail"]
	var head: Node3D = a["head"]
	match str(a["state"]):
		"idle":
			_walk_to(a, delta, 0.0, 0.5)
			# sitzt: Hinterteil unten, putzt sich oder schaut zum Spieler
			(a["m"] as Node3D).rotation.x = lerpf((a["m"] as Node3D).rotation.x, 0.0, delta * 4.0)
			var want_y := 0.0
			if near:
				var l := n.to_local(pp)
				want_y = clampf(atan2(-l.x, -l.z), -1.2, 1.2)
				if _rng.randf() < delta * 0.12 and GameState.is_active:
					SfxManager.play_at("meow", n.global_position, -8.0, _rng.randf_range(0.95, 1.1))
			head.rotation.y = lerpf(head.rotation.y, want_y, delta * 4.0)
			head.rotation.x = lerpf(head.rotation.x, (0.30 + sin(_t * 7.0) * 0.15 if not near and fposmod(_t, 14.0) < 5.0 else 0.0), delta * 5.0)
			if float(a["t"]) <= 0.0:
				a["state"] = "walk"
				a["goal"] = pp if near and _rng.randf() < 0.6 and OutdoorWorld.is_outside(pp) and pp.y < 1.0 else _free_point()
				a["t"] = 26.0
		_:
			a["to"] = _route(n.position, a["goal"])
			var goal: Vector3 = a["goal"]
			var hunt := false
			for b in _birds:
				if str(b["state"]) == "sit" and (b["n"] as Node3D).position.y < 0.2 and (b["n"] as Node3D).position.distance_to(n.position) < 4.0:
					hunt = true
			_walk_to(a, delta, 0.42 if hunt else (1.0 if not night else 0.8), 0.62)
			if n.position.distance_to(goal) < 0.4 or float(a["t"]) < 0.0:
				a["state"] = "idle"
				a["t"] = _rng.randf_range(6.0, 22.0)
			head.rotation.y = lerpf(head.rotation.y, 0.0, delta * 4.0)
	tail.rotation.x = sin(_t * 1.6) * 0.18
	tail.rotation.y = sin(_t * 1.1) * 0.45


func _update_squirrel(delta: float, pp: Vector3, hide: bool, se: float) -> void:
	var a := _squirrel
	var n: Node3D = a["n"]
	n.visible = not hide and not (se > 3.1 and se < 3.8)
	if not n.visible:
		return
	a["t"] = float(a["t"]) - delta
	var tree := Vector3(16.5, 0, -8.5) if not a.has("tree") else (a["tree"] as Vector3)
	var tail: Node3D = a["tail"]
	tail.rotation.x = sin(_t * 5.0) * 0.12
	match str(a["state"]):
		"idle":
			_walk_to(a, delta, 0.0, 0.4, true)
			(a["m"] as Node3D).rotation.x = lerpf((a["m"] as Node3D).rotation.x, 0.45, delta * 5.0)
			(a["head"] as Node3D).rotation.x = -0.35 + sin(_t * 16.0) * 0.08
			if n.position.distance_to(pp) < 4.0:
				a["state"] = "flee"
				a["to"] = tree + Vector3(0.0, 0.0, 0.32)
			elif float(a["t"]) <= 0.0:
				a["state"] = "run"
				var ang := _rng.randf() * TAU
				a["to"] = Vector3(clampf(tree.x + cos(ang) * 3.4, -10.2, 25.8), -0.02, clampf(tree.z + absf(sin(ang)) * 2.0, -9.1, -6.0))
		"run":
			if _walk_to(a, delta, 1.8, 0.45, true):
				a["state"] = "idle"
				a["t"] = _rng.randf_range(1.5, 5.0)
			if n.position.distance_to(pp) < 4.0:
				a["state"] = "flee"
				a["to"] = tree + Vector3(0.0, 0.0, 0.32)
		"flee":
			if _walk_to(a, delta, 3.4, 0.5, true):
				a["state"] = "climb"
				a["t"] = _rng.randf_range(8.0, 16.0)
		"climb":
			# Am Stamm hinauf, warten, wieder hinunter
			var up := clampf((16.0 - float(a["t"])) * 1.6, 0.0, 2.6) if float(a["t"]) > 2.0 else clampf(float(a["t"]) * 1.3, 0.0, 2.6)
			n.position = tree + Vector3(0.0, up, 0.20)
			n.rotation = Vector3(PI * 0.5 if float(a["t"]) > 2.0 else -PI * 0.5, 0.0, 0.0)
			if float(a["t"]) <= 0.0 and n.position.distance_to(pp) > 4.5:
				n.rotation = Vector3.ZERO
				n.position = tree + Vector3(0, -0.02, 0.4)
				a["state"] = "idle"
				a["t"] = 2.0


func _update_hedgehog(delta: float, pp: Vector3, night: bool, se: float) -> void:
	var a := _hedgehog
	var n: Node3D = a["n"]
	n.visible = night and se > 0.2 and se < 2.8
	if not n.visible:
		return
	a["t"] = float(a["t"]) - delta
	var scared := n.position.distance_to(pp) < 1.6
	# Zusammenrollen, wenn jemand kommt
	var roll := lerpf(float(a.get("roll", 0.0)), 1.0 if scared else 0.0, 1.0 - exp(-delta * 4.0))
	a["roll"] = roll
	(a["head"] as Node3D).scale = Vector3.ONE * lerpf(1.0, 0.35, roll)
	(a["head"] as Node3D).position.z = lerpf(-0.085, -0.02, roll)
	for l in a["legs"]:
		if l != null:
			(l as Node3D).scale = Vector3.ONE * lerpf(1.0, 0.2, roll)
	if scared:
		a["sp"] = 0.0
		return
	a["to"] = _route(n.position, a.get("goal", n.position))
	if _walk_to(a, delta, 0.22, 0.16) and float(a["t"]) <= 0.0:
		a["goal"] = _free_point()
		a["t"] = _rng.randf_range(4.0, 16.0)
	(a["head"] as Node3D).rotation.x = 0.15 + sin(_t * 6.0) * 0.10


func _update_butterflies(delta: float, on: bool) -> void:
	for f in _flies:
		var n: Node3D = f["n"]
		n.visible = on
		if not on:
			continue
		var s: float = f["s"]
		var h: Vector3 = f["home"]
		var sit := fposmod(_t * 0.07 + s, 1.0) < 0.22
		var p := h + Vector3(sin(_t * 0.5 + s) * 1.6 + sin(_t * 2.3 + s) * 0.25, 0.75 + sin(_t * 1.1 + s * 2.0) * 0.35 + sin(_t * 5.0 + s) * 0.05, cos(_t * 0.43 + s * 1.3) * 1.4)
		if sit:
			p = n.position
			p.y = lerpf(p.y, 0.5, delta * 2.0)
		var d := p - n.position
		n.position = n.position.lerp(p, 1.0 - exp(-delta * 4.0))
		if d.length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(-d.x, -d.z), delta * 4.0)
		var fl := sin(_t * (3.0 if sit else 19.0) + s) * 0.9 + 0.25
		(f["l"] as Node3D).rotation.z = -fl
		(f["r"] as Node3D).rotation.z = fl


## Für Tests.
func count_visible() -> int:
	var c := 0
	for b in _birds:
		if (b["n"] as Node3D).visible:
			c += 1
	return c
