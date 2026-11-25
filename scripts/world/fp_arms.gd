class_name FpArms
extends Node3D
## Eigene Arme in der Ich-Ansicht: dieselbe Figur wie die Mitspieler sehen (Ärmel, Haut, Uhr, Handschuhe),
## nur Arme. Die Hände greifen per IK an das gehaltene Ding und führen kurze Handlungen aus
## (greifen, ablegen, stecken, drücken, trinken, Gesten). Hängt an der Kamera.

const ARM_SCALE := 0.92
## Lage des Körpers zur Kamera: Schultern etwas vor dem Auge, damit die Arme reichen.
const BODY_POS := Vector3(0.0, -1.585, -0.02)
const REACH := 0.50
## Nur für die Kamera des Spielers sichtbar (nicht im Spiegel).
const LAYER := 1 << 17
const LOW := Vector3(0.30, -0.75, -0.10)
const PARTS: Array[String] = ["Hands", "Arms", "Acc_Gloves", "Acc_Watch"]

const LENGTHS := {
	"pickup": 0.42, "place": 0.42, "reach": 0.42, "plug": 0.55, "press": 0.36, "screw": 1.4, "drink": 2.2, "wave": 2.0, "point": 1.6, "thumbs": 1.6,
	"dance": 3.0, "cheer": 2.2, "shrug": 1.5, "clap": 2.2, "laugh": 1.6, "salute": 1.5, "facepalm": 1.6, "nod": 0.0, "no": 0.0, "feed": 1.4, "sweep": 1.6,
}

var human: HumanModel
## Gehaltenes: "", box, item, ext, cable, push
var grip_mode := ""
## Halbe Breite des Gegenstands (Kamera-Maß) und Lage seines Halters.
var half_w := 0.15
var item_xf := Transform3D.IDENTITY
## Weltpunkte der Griffe beim Schieben.
var push_l := Vector3.ZERO
var push_r := Vector3.ZERO
var bob := Vector3.ZERO
var _action := ""
var _t := 0.0
var _len := 0.0
var _at := Vector3(0, -0.1, -0.5)
var _cur: Dictionary = {}
var _time := 0.0
var _plug: Node3D
var _plug_col := Color.BLACK


func set_look(look: Dictionary) -> void:
	if human != null:
		human.queue_free()
	# Nur Farben und Kleidung übernehmen: Größe und Statur würden Brust und Schultern ins Bild schieben.
	var lk := HumanModel.sanitize(look)
	lk.merge({"height": 59, "build": 0, "fem": 0}, true)
	human = HumanModel.create(lk)
	human.manual = true
	human.scale = Vector3.ONE * ARM_SCALE
	human.position = BODY_POS * ARM_SCALE
	add_child(human)
	for mi_n in human.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		var nm := str(mi.name)
		if not (nm in PARTS or nm.begins_with("Top_")):
			mi.queue_free()
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2.0
		mi.layers = LAYER
	for l in human.find_children("*", "Label3D", true, false):
		l.queue_free()


## Handlung starten. world_at: Punkt in der Welt, zu dem die Hand geht.
func play(action: String, world_at: Variant = null) -> void:
	if not LENGTHS.has(action) or float(LENGTHS[action]) <= 0.0:
		return
	_action = action
	_t = 0.0
	_len = float(LENGTHS[action])
	var p := Vector3(0.10, -0.10, -0.5)
	if world_at is Vector3:
		p = to_local(world_at)
		if p.z > -0.12:
			p.z = -0.12
		if p.length() > REACH:
			p = p.normalized() * REACH
	_at = p


func is_busy() -> bool:
	return _action != ""


func set_plug(on: bool, col: Color) -> void:
	if _plug == null:
		_plug = Node3D.new()
		add_child(_plug)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.026, 0.020, 0.044)
		body.mesh = bm
		body.name = "Body"
		_plug.add_child(body)
		var tip := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.016, 0.012, 0.020)
		tip.mesh = tm
		tip.position.z = -0.030
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.78, 0.74, 0.60)
		tmat.metallic = 0.8
		tmat.roughness = 0.35
		tip.material_override = tmat
		_plug.add_child(tip)
		var cab := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0055
		cm.bottom_radius = 0.0055
		cm.height = 0.42
		cab.mesh = cm
		cab.position = Vector3(0.0, -0.12, 0.17)
		cab.rotation_degrees.x = 55.0
		cab.name = "Cable"
		_plug.add_child(cab)
		for m in _plug.get_children():
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(m as MeshInstance3D).layers = LAYER
	_plug.visible = on
	if on and col != _plug_col:
		_plug_col = col
		var mt := StandardMaterial3D.new()
		mt.albedo_color = col
		mt.roughness = 0.55
		(_plug.get_node("Body") as MeshInstance3D).material_override = mt
		(_plug.get_node("Cable") as MeshInstance3D).material_override = mt


func _to_skel(p: Vector3) -> Vector3:
	var q := human.transform.affine_inverse() * p
	return Vector3(-q.x, q.y, -q.z) / human.root_scale()


## Wunschlage je Hand in Kamera-Koordinaten (s = -1 links, +1 rechts).
func _base(s: float) -> Dictionary:
	var rest := {"pos": Vector3(LOW.x * s, LOW.y, LOW.z), "palm": Vector3(-s, 0, 0), "dir": Vector3(0, -0.3, -1), "grip": 0.35, "on": 0.0}
	match grip_mode:
		"box":
			return {"pos": item_xf * Vector3(half_w * s, 0.02, 0.08), "palm": item_xf.basis * Vector3(-s, 0.35, 0.0), "dir": item_xf.basis * Vector3(-0.22 * s, -0.10, -1.0), "grip": 0.24, "on": 1.0}
		"item":
			if s > 0.0:
				return {"pos": item_xf * Vector3(0.06, -0.08, 0.10), "palm": Vector3(-0.8, 0.6, 0.0), "dir": Vector3(-0.25, 0.10, -1.0), "grip": 0.55, "on": 1.0}
		"ext":
			if s > 0.0:
				return {"pos": item_xf * Vector3(0.012, 0.300, 0.085), "palm": Vector3(-1.0, -0.2, 0.0), "dir": Vector3(-0.15, -0.15, -1.0), "grip": 0.85, "on": 1.0}
			return {"pos": item_xf * Vector3(-0.030, 0.0, -0.190), "palm": Vector3(0.9, 0.2, 0.0), "dir": Vector3(0.35, 0.10, -1.0), "grip": 0.8, "on": 1.0}
		"cable":
			if s > 0.0:
				return {"pos": Vector3(0.17, -0.20, -0.36) + bob, "palm": Vector3(-1, 0.1, 0), "dir": Vector3(-0.15, 0.15, -1), "grip": 0.7, "on": 1.0}
		"push":
			var w := push_r if s > 0.0 else push_l
			var p := to_local(w)
			return {"pos": p, "palm": Vector3(0, -0.4, -1), "dir": Vector3(-0.25 * s, 0.7, -0.6), "grip": 0.8, "on": 1.0}
	return rest


func _act(s: float, cur: Dictionary) -> Dictionary:
	var u := _t / maxf(0.01, _len)
	var right := s > 0.0
	match _action:
		"pickup", "place", "reach":
			if _action == "reach" and not right:
				return {}
			var off := 0.0 if _action == "reach" else 0.12
			return {"pos": _at + Vector3(off * s, -0.02, 0.03), "palm": Vector3(-s, -0.15, 0), "dir": Vector3(-0.15 * s, -0.1, -1), "grip": 0.15 + 0.5 * smoothstep(0.35, 0.6, u)}
		"plug":
			if right:
				return {"pos": _at + Vector3(0.01, -0.01, 0.06), "palm": Vector3(-1, 0.0, 0), "dir": Vector3(0, 0, -1), "grip": 0.8}
		"press":
			if right:
				return {"pos": _at + Vector3(0.0, -0.02, 0.06), "palm": Vector3(0, -1, 0), "dir": Vector3(0, 0, -1), "grip": 0.5, "point": true}
		"screw":
			if right:
				var a := _t * 9.0
				return {"pos": _at + Vector3(0.0, 0.0, 0.08), "palm": Vector3(-cos(a), sin(a), 0), "dir": Vector3(0, 0, -1), "grip": 0.9}
		"drink":
			if right:
				return {"pos": Vector3(0.05, -0.10, -0.15), "palm": Vector3(-1, 0, 0.2), "dir": Vector3(-0.3, 0.7, -0.3), "grip": 0.7}
		"wave":
			if right:
				var w := sin(_t * 11.0)
				return {"pos": Vector3(0.22 + w * 0.05, 0.02, -0.40), "palm": Vector3(0, 0, -1), "dir": Vector3(w * 0.4, 1, 0), "grip": 0.05}
		"point":
			if right:
				return {"pos": Vector3(0.10, -0.10, -0.48), "palm": Vector3(-0.6, -0.8, 0), "dir": Vector3(-0.05, 0.05, -1), "grip": 0.8, "point": true}
		"thumbs":
			if right:
				return {"pos": Vector3(0.16, -0.12, -0.42), "palm": Vector3(-1, 0, 0), "dir": Vector3(-0.35, 0.05, -1), "grip": 1.0}
		"clap":
			var c := absf(sin(_t * 11.0))
			return {"pos": Vector3((0.02 + 0.09 * c) * s, -0.18, -0.38), "palm": Vector3(-s, 0, 0), "dir": Vector3(0, 0.5, -0.8), "grip": 0.05}
		"cheer":
			return {"pos": Vector3(0.28 * s, 0.10 + sin(_t * 12.0) * 0.04, -0.36), "palm": Vector3(-s, 0, -0.3), "dir": Vector3(0, 1, 0), "grip": 0.9}
		"dance":
			var q := sin(_t * 7.0 + (0.0 if right else PI))
			return {"pos": Vector3(0.24 * s, -0.16 + q * 0.12, -0.38), "palm": Vector3(-s, 0, 0.2), "dir": Vector3(0, 0.7, -0.7), "grip": 0.7}
		"shrug":
			return {"pos": Vector3(0.30 * s, -0.24, -0.36), "palm": Vector3(0, 1, 0.2), "dir": Vector3(0.6 * s, 0.1, -0.6), "grip": 0.1}
		"salute":
			if right:
				return {"pos": Vector3(0.14, 0.06, -0.20), "palm": Vector3(0, -0.6, -0.6), "dir": Vector3(-0.7, 0.4, -0.1), "grip": 0.0}
		"facepalm":
			if right:
				return {"pos": Vector3(0.05, -0.05, -0.17), "palm": Vector3(0, 0, 1), "dir": Vector3(-0.4, 1, 0), "grip": 0.1}
		"laugh":
			return {"pos": Vector3(0.12 * s, -0.36, -0.28), "palm": Vector3(-s * 0.4, 0, 1), "dir": Vector3(-s, 0, -0.2), "grip": 0.3}
		"feed", "sweep":
			if right:
				var f := sin(_t * 7.0)
				return {"pos": _at + Vector3(f * 0.12, 0, 0.04), "palm": Vector3(0, -1, 0), "dir": Vector3(f * 0.3, -0.1, -1), "grip": 0.3}
	return {}


func update(delta: float) -> void:
	if human == null or human.rig == null:
		return
	_time += delta
	if _action != "":
		_t += delta
		if _t >= _len:
			_action = ""
	var u := _t / maxf(0.01, _len)
	var aw := smoothstep(0.0, 0.32, u) * (1.0 - smoothstep(0.62, 1.0, u)) if _action != "" else 0.0
	var res: Array = []
	var any := false
	for s in [-1.0, 1.0]:
		var want := _base(s)
		var key := "l" if s < 0.0 else "r"
		var act := _act(s, want) if _action != "" else {}
		if not act.is_empty():
			want = {"pos": (want["pos"] as Vector3).lerp(act["pos"], aw), "palm": (want["palm"] as Vector3).lerp(act["palm"], aw), "dir": (want["dir"] as Vector3).lerp(act["dir"], aw), "grip": lerpf(float(want["grip"]), float(act["grip"]), aw), "on": maxf(float(want["on"]), aw)}
		var c: Dictionary = _cur.get(key, want)
		var k := 1.0 - exp(-delta * (22.0 if _action != "" else 15.0))
		# Am Gegenstand bleiben: kein Nachziehen, sobald die Hand dort ist.
		if grip_mode != "" and _action == "" and (c["pos"] as Vector3).distance_to(want["pos"]) < 0.03:
			k = 1.0
		c = {"pos": (c["pos"] as Vector3).lerp(want["pos"], k), "palm": (c["palm"] as Vector3).lerp(want["palm"], k), "dir": (c["dir"] as Vector3).lerp(want["dir"], k), "grip": lerpf(float(c["grip"]), float(want["grip"]), k), "on": want["on"]}
		_cur[key] = c
		if (c["pos"] as Vector3).y > LOW.y + 0.10:
			any = true
		var sp: Vector3 = c["palm"]
		var sd: Vector3 = c["dir"]
		res.append({"pos": _to_skel(c["pos"]), "palm": Vector3(-sp.x, sp.y, -sp.z), "dir": Vector3(-sd.x, sd.y, -sd.z), "grip": c["grip"]})
	visible = any
	if not any:
		return
	human.rig.arms_only(res[0], res[1])
	if _plug != null and _plug.visible:
		var rc: Dictionary = _cur["r"]
		_plug.position = (rc["pos"] as Vector3) + (rc["dir"] as Vector3).normalized() * 0.085 + Vector3(-0.012, -0.004, 0.0)
