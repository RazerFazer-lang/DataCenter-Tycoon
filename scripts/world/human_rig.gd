class_name HumanRig
extends RefCounted
## Bewegt eine HumanModel-Figur: Gehen mit Füßen am Boden (IK), Rennen, Ducken, Springen, Sitzen, Leiter,
## Tragen, Greifen, Arbeiten, Gesten, Blick und Mimik. Alles wird weich gemischt, keine Animationsdateien.
## Raum der Rechnung: Skelett, Figur blickt nach +Z, links ist +X.

const UP := Vector3.UP
const FWD := Vector3(0, 0, 1)
const ANKLE_Y := 0.092

## Eingaben
var velocity := Vector2.ZERO      # lokal: x = links, y = vorwärts (m/s)
var crouch := 0.0
var airborne := false
var seat := 0.0                   # 0 steht, 1 sitzt
var seat_height := 0.46
var look_yaw := 0.0
var look_pitch := 0.0             # + nach oben
var base := ""                    # Haltung: "", carry_small, carry_box, carry_wide, one, extinguisher, push, tablet, drive, type, sofa, ladder, tool
var talk := 0.0
var mood := 0.0                   # -1 wütend .. 1 fröhlich
var tempo := 1.0

var _m: HumanModel
var _s: Skeleton3D
var _b: Dictionary = {}
var _rest: Array[Transform3D] = []
var _rest_g: Array[Transform3D] = []
var _par: PackedInt32Array = []
var _g: Array[Transform3D] = []
var _phase := 0.0
var _t := 0.0
var _move := 0.0
var _vel := Vector2.ZERO
var _crouch := 0.0
var _air := 0.0
var _seat := 0.0
var _look := Vector2.ZERO
var _land := 0.0
var _was_air := false
var _base_w: Dictionary = {}
var _action := ""
var _action_t := 0.0
var _action_len := 0.0
var _action_at := Vector3(0, 0.9, 0.5)
var _blink := 0.0
var _blink_next := 2.0
var _hand_l := Vector3.ZERO
var _hand_r := Vector3.ZERO
var _hand_init := false
var _fing := Vector2(0.25, 0.25)
var _lean := 0.0
var _seed := randf() * 10.0

const BASES: Array[String] = ["carry_small", "carry_box", "carry_wide", "one", "extinguisher", "push", "pull", "reach", "low", "work", "hammer", "grill", "tablet", "drive", "type", "sofa", "ladder", "tool", "lean"]
const ACTIONS := {
	"pickup": 0.75, "place": 0.75, "reach": 0.7, "plug": 1.1, "press": 0.55, "screw": 1.6, "drink": 2.2, "wave": 2.0, "point": 1.6, "thumbs": 1.6, "dance": 4.0,
	"cheer": 2.2, "shrug": 1.5, "clap": 2.2, "laugh": 2.2, "salute": 1.5, "facepalm": 1.8, "nod": 0.9, "no": 1.0, "feed": 1.6, "sweep": 1.6,
}


func setup(m: HumanModel, s: Skeleton3D) -> void:
	_m = m
	_s = s
	for i in s.get_bone_count():
		_b[s.get_bone_name(i)] = i
		_rest.append(s.get_bone_rest(i))
		_rest_g.append(s.get_bone_global_rest(i))
		_par.append(s.get_bone_parent(i))
		_g.append(s.get_bone_global_rest(i))
	update(0.0)


## Kurze Handlung. at: Ziel der Hand relativ zur Figur (x links, y hoch, z vorn), in Metern.
func play(action: String, at: Vector3 = Vector3(0, 0.9, 0.5), length: float = -1.0) -> void:
	if not ACTIONS.has(action):
		return
	_action = action
	_action_t = 0.0
	_action_len = float(ACTIONS[action]) if length <= 0.0 else length
	_action_at = at


func is_playing() -> bool:
	return _action != ""


func stop() -> void:
	_action = ""


# ---------------------------------------------------------------- Hauptschritt

func update(delta: float) -> void:
	if _s == null:
		return
	_t += delta
	var k := 1.0 - exp(-delta * 9.0)
	_vel = _vel.lerp(velocity, 1.0 - exp(-delta * 7.0))
	var sp := _vel.length()
	_move = lerpf(_move, clampf(sp / 0.5, 0.0, 1.0), k)
	_crouch = lerpf(_crouch, crouch, k)
	_seat = lerpf(_seat, seat, 1.0 - exp(-delta * 5.0))
	_look = _look.lerp(Vector2(clampf(look_yaw, -1.2, 1.2), clampf(look_pitch, -0.9, 0.9)), 1.0 - exp(-delta * 8.0))
	if _was_air and not airborne:
		_land = 1.0
	_was_air = airborne
	_air = lerpf(_air, 1.0 if airborne else 0.0, 1.0 - exp(-delta * 10.0))
	_land = maxf(0.0, _land - delta * 3.5)
	for key in BASES:
		_base_w[key] = lerpf(float(_base_w.get(key, 0.0)), 1.0 if base == key else 0.0, 1.0 - exp(-delta * 8.0))
	if _action != "":
		_action_t += delta
		if _action_t >= _action_len:
			_action = ""
	# Schrittlänge und Tempo: schneller heißt längere und häufigere Schritte.
	var run := clampf((sp - 2.2) / 2.5, 0.0, 1.0)
	# stride = Weg je Doppelschritt. Der Fuß legt am Boden genau seinen Anteil zurück und rutscht nicht.
	var stride := lerpf(0.70 + sp * 0.42, 1.10 + sp * 0.30, run) * lerpf(1.0, 0.75, _crouch)
	if sp > 0.05:
		_phase = fposmod(_phase + delta * sp / maxf(0.3, stride), 1.0)
	_solve(delta, sp, run, stride)
	_face(delta)


func _aw() -> float:
	if _action == "":
		return 0.0
	var u := _action_t / maxf(0.01, _action_len)
	return smoothstep(0.0, 0.28, u) * (1.0 - smoothstep(0.72, 1.0, u))


func _solve(delta: float, sp: float, run: float, stride: float) -> void:
	var aw := _aw()
	var breathe := sin(_t * 1.7 + _seed) * 0.004
	var ph := _phase * TAU
	var dir := _vel.normalized() if sp > 0.05 else Vector2(0, 1)
	var sit := _seat
	var low := 0.0
	var reach_low := 0.0
	if _action in ["pickup", "place", "plug", "reach", "screw", "feed", "sweep"]:
		reach_low = aw * smoothstep(0.95, 0.25, _action_at.y)
	low = maxf(_crouch, maxf(reach_low * 0.85, float(_base_w["low"]) * 0.8))
	var lad := float(_base_w["ladder"])
	# Hüfte
	var bob := absf(sin(ph)) * lerpf(0.018, 0.045, run) * _move - 0.010 * _move
	var hip := Vector3(0.0, 0.965 + bob + breathe * 0.3 - low * 0.36 - _land * 0.10 * (1.0 - _seat), 0.0)
	hip.x = sin(ph) * 0.016 * _move * (1.0 - run)
	hip.z = -low * 0.06
	if sit > 0.0:
		hip = hip.lerp(Vector3(0.0, seat_height + 0.09, -0.02), sit)
	if _air > 0.0:
		hip.y += 0.02 * _air
	if _action == "dance":
		hip.y += absf(sin(_t * 7.0)) * -0.05 * aw
		hip.x += sin(_t * 3.5) * 0.06 * aw
	# Neigung: beim Rennen nach vorn, beim Tragen leicht zurück
	var heavy := float(_base_w["carry_box"]) + float(_base_w["carry_wide"]) * 1.2
	var lean_t := run * 0.20 + _move * 0.03 - heavy * 0.07 + float(_base_w["push"]) * 0.22 + float(_base_w["reach"]) * 0.16 + float(_base_w["work"]) * 0.14 + low * 0.34 + reach_low * 0.42 - sit * 0.04 - float(_base_w["sofa"]) * 0.16 + float(_base_w["type"]) * 0.06
	if _vel.y < -0.2:
		lean_t *= 0.2
	if _action == "laugh":
		lean_t += aw * (0.12 + sin(_t * 16.0) * 0.05)
	_lean = lerpf(_lean, lean_t, 1.0 - exp(-delta * 8.0) if delta > 0.0 else 1.0)
	var pelvis_yaw := sin(ph) * 0.10 * _move * dir.y
	var roll := -sin(ph) * 0.035 * _move
	var hip_b := Basis(UP, pelvis_yaw) * Basis(FWD, roll) * Basis(Vector3.RIGHT, _lean * 0.35 - sit * 0.10 * 0.0 + low * 0.16)
	_put("Hips", hip, hip_b)
	var twist := -pelvis_yaw * 1.7
	if _action == "dance":
		twist += sin(_t * 7.0) * 0.22 * aw
	var ly := _look.x
	var lp := _look.y
	_turn("Spine", Basis(UP, twist * 0.35 + ly * 0.10) * Basis(Vector3.RIGHT, _lean * 0.30 - lp * 0.05 + breathe * 2.0) * Basis(FWD, -roll * 0.7))
	_turn("Spine1", Basis(UP, twist * 0.35 + ly * 0.12) * Basis(Vector3.RIGHT, _lean * 0.25 - lp * 0.07) * Basis(FWD, -roll * 0.6))
	_turn("Spine2", Basis(UP, twist * 0.30 + ly * 0.12) * Basis(Vector3.RIGHT, _lean * 0.15 - lp * 0.06 - breathe * 2.0))
	var nod := 0.0
	var shake := 0.0
	match _action:
		"nod":
			nod = sin(_action_t * 14.0) * 0.16 * aw
		"no":
			shake = sin(_action_t * 13.0) * 0.30 * aw
		"facepalm":
			nod = 0.30 * aw
		"dance":
			nod = sin(_t * 14.0) * 0.08 * aw
		"drink":
			nod = -0.22 * aw
	var down := float(_base_w["tablet"]) * 0.30 + float(_base_w["work"]) * 0.34 + float(_base_w["grill"]) * 0.30 + float(_base_w["type"]) * 0.06 + reach_low * 0.12
	var idle := Vector2(sin(_t * 0.43 + _seed) * 0.10, sin(_t * 0.31 + _seed * 2.0) * 0.04) * (1.0 - _move)
	_turn("Neck", Basis(UP, (ly + idle.x + shake) * 0.28) * Basis(Vector3.RIGHT, -lp * 0.30 - _lean * 0.35 + down * 0.5 + nod * 0.4 + idle.y))
	_turn("Head", Basis(UP, (ly + idle.x + shake) * 0.38) * Basis(Vector3.RIGHT, -lp * 0.50 - _lean * 0.45 + down * 0.6 + nod))
	_legs(sp, run, stride, dir, low, lad)
	_arms(delta, sp, run, ph, aw, heavy)
	_apply()


# ---------------------------------------------------------------- Beine

func _legs(sp: float, run: float, stride: float, dir: Vector2, low: float, lad: float) -> void:
	var fly := _air
	for side in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		var p := fposmod(_phase + (0.0 if side == "Left" else 0.5), 1.0)
		var stance := lerpf(0.62, 0.42, run)
		var foot := Vector3(0.102 * s, ANKLE_Y, -0.018)
		var pitch := 0.0
		if _move > 0.01:
			var along := 0.0
			var lift := 0.0
			if p < stance:
				var u := p / stance
				along = lerpf(0.5, -0.5, u)
				pitch = lerpf(-0.22, 0.0, smoothstep(0.0, 0.18, u)) + smoothstep(0.68, 1.0, u) * 0.55
				lift = smoothstep(0.70, 1.0, u) * 0.045
			else:
				var u2 := (p - stance) / (1.0 - stance)
				along = lerpf(-0.5, 0.5, u2 * u2 * (3.0 - 2.0 * u2))
				lift = sin(u2 * PI) * lerpf(0.10, 0.26, run) + (1.0 - u2) * 0.045
				pitch = lerpf(0.75, -0.25, u2) * lerpf(0.7, 1.0, run)
			var st := stride * stance
			foot += Vector3(dir.x * along * st, lift, dir.y * along * st + (0.02 if run > 0.5 else 0.0)) * _move
			foot.x = lerpf(foot.x, 0.05 * s + dir.x * along * st, run * _move * 0.6)
			pitch *= _move
			pitch *= signf(dir.y) if absf(dir.y) > 0.3 else 0.4
		else:
			foot.x += 0.016 * s
			foot.z += 0.012 * s
		var toe_out := 0.14 * s * (1.0 - run)
		if low > 0.05:
			foot.x += 0.030 * s * low
			foot.z += (0.13 if s > 0.0 else -0.13) * low * (1.0 - _move)
			if s < 0.0:
				pitch += 0.5 * low * (1.0 - _move)
				foot.y += 0.03 * low * (1.0 - _move)
		if fly > 0.02:
			foot = foot.lerp(Vector3(0.105 * s, ANKLE_Y + (0.22 if s > 0.0 else 0.10), 0.06 if s > 0.0 else -0.16), fly)
			pitch = lerpf(pitch, 0.5, fly)
		if _seat > 0.02:
			var so := float(_base_w["sofa"])
			var sf := Vector3(0.115 * s, ANKLE_Y, 0.40 + 0.06 * so)
			if base == "drive":
				sf = Vector3(0.12 * s, seat_height - 0.30, 0.42)
			foot = foot.lerp(sf, _seat)
			pitch = lerpf(pitch, 0.0, _seat)
		if lad > 0.02:
			var lu := fposmod(_t * 0.9 * tempo + (0.0 if s > 0.0 else 0.5), 1.0)
			foot = foot.lerp(Vector3(0.12 * s, ANKLE_Y + 0.12 + 0.30 * absf(sin(lu * PI)), 0.20), lad)
		if _action == "dance":
			var dw := _aw()
			foot.y += maxf(0.0, sin(_t * 7.0 + (0.0 if s > 0.0 else PI))) * 0.10 * dw
			foot.x += 0.04 * s * dw
		var up_i: int = _b[side + "UpLeg"]
		var hip_p := _child_pos(up_i)
		var l1 := (_rest_g[_b[side + "Leg"]].origin - _rest_g[up_i].origin).length()
		var l2 := (_rest_g[_b[side + "Foot"]].origin - _rest_g[_b[side + "Leg"]].origin).length()
		var pole := Vector3(0.16 * s + 0.35 * s * low + 0.10 * s * _seat, 0.0, 1.0)
		var kn := _ik(hip_p, foot, l1, l2, pole)
		_aim(side + "UpLeg", hip_p, kn, pole, FWD)
		_aim(side + "Leg", _child_pos(_b[side + "Leg"]), foot, pole, FWD)
		# Fuß: Ruhelage, gekippt um die Querachse
		var fi: int = _b[side + "Foot"]
		var fb := Basis(UP, toe_out) * Basis(Vector3.RIGHT, pitch) * _rest_g[fi].basis
		_g[fi] = Transform3D(fb, _child_pos(fi))
		var ti: int = _b[side + "Toe"]
		_g[ti] = Transform3D(Basis(UP, toe_out) * Basis(Vector3.RIGHT, minf(pitch, 0.0) + maxf(pitch, 0.0) * 0.15) * _rest_g[ti].basis, _child_pos(ti))


# ---------------------------------------------------------------- Arme

## Wunschlage der Hände je Haltung, relativ zur Brust. [Position, Handrichtung, Ellbogen-Pol, Griff]
func _arms(delta: float, sp: float, run: float, ph: float, aw: float, heavy: float) -> void:
	var chest := _g[_b["Spine2"]]
	var yaw_b := Basis(UP, _look.x * 0.25)
	var total := 0.0
	for key in _base_w.keys():
		total = maxf(total, float(_base_w[key]))
	for side in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		# Schulter
		var shi: int = _b[side + "Shoulder"]
		var raise := 0.0
		if _action in ["cheer", "dance"]:
			raise = 0.25 * aw
		elif _action == "shrug":
			raise = 0.34 * aw
		_turn(side + "Shoulder", Basis(FWD, raise * s) * Basis(UP, -0.06 * s * heavy))
		var ai: int = _b[side + "Arm"]
		var sh := _child_pos(ai)
		var l1 := (_rest_g[_b[side + "ForeArm"]].origin - _rest_g[ai].origin).length()
		var l2 := (_rest_g[_b[side + "Hand"]].origin - _rest_g[_b[side + "ForeArm"]].origin).length()
		# Freies Schwingen
		var sw := -sin(ph) * s
		var swing := sw * lerpf(0.20, 0.42, run) * _move * (signf(_vel.y) if absf(_vel.y) > 0.3 else 0.3)
		var bend := lerpf(0.10, 1.35, run * _move)
		var free := sh + Vector3(0.050 * s + 0.02 * s * run, -0.50 + bend * 0.14, 0.035 + swing + bend * 0.13)
		if _move < 0.2:
			free += Vector3(0.0, sin(_t * 1.1 + s) * 0.004, sin(_t * 0.7 + s * 2.0) * 0.008)
		if _air > 0.05:
			free = free.lerp(sh + Vector3(0.30 * s, -0.30, 0.10), _air * 0.7)
		if _seat > 0.1:
			free = free.lerp(Vector3(0.14 * s, seat_height + 0.16, 0.26), _seat)
		var hand := free
		var palm := Vector3(-s, 0.0, 0.15)     # wohin die Handfläche zeigt
		var fing_dir := Vector3(0.0, -1.0, 0.25)
		if run > 0.3:
			fing_dir = fing_dir.lerp(Vector3(-0.2 * s, 0.2, 1.0), run * _move)
		var pole := Vector3(0.55 * s, -0.25, -1.0)
		var grip := 0.30 + run * 0.5
		var cy := chest.origin.y
		for key in _base_w.keys():
			var w := float(_base_w[key])
			if w < 0.01:
				continue
			var tgt := hand
			var tp := palm
			var tf := fing_dir
			var tg := grip
			var po := pole
			var jig := Vector3(0.0, sin(ph * 2.0) * 0.008 * _move, 0.0)
			match key:
				"carry_small":
					tgt = Vector3(0.115 * s, cy - 0.20, 0.34) + jig
					tp = Vector3(-s, 0.35, 0.0)
					tf = Vector3(-0.25 * s, 0.05, 1.0)
					tg = 0.45
				"carry_box":
					tgt = Vector3(0.235 * s, cy - 0.30, 0.36) + jig
					tp = Vector3(-s * 0.8, 0.6, 0.0)
					tf = Vector3(-0.45 * s, 0.0, 1.0)
					tg = 0.35
				"carry_wide":
					tgt = Vector3(0.315 * s, cy - 0.34, 0.34) + jig
					tp = Vector3(-s * 0.7, 0.7, 0.0)
					tf = Vector3(-0.5 * s, 0.0, 1.0)
					tg = 0.35
				"one":
					if s < 0.0:
						tgt = Vector3(0.20 * s, cy - 0.26, 0.30) + jig
						tp = Vector3(-s, 0.3, 0.0)
						tf = Vector3(0.0, 0.1, 1.0)
						tg = 0.75
				"tool":
					if s < 0.0:
						tgt = sh + Vector3(0.04 * s, -0.44, 0.12 + swing * 0.5)
						tf = Vector3(0.0, -0.8, 0.5)
						tg = 0.9
				"extinguisher":
					tgt = Vector3(0.10, cy - 0.16, 0.40) if s > 0.0 else Vector3(-0.17, cy - 0.34, 0.24)
					tp = Vector3(-s, 0.2, 0.0)
					tf = Vector3(0.0, 0.0, 1.0)
					tg = 0.85
				"push":
					tgt = Vector3(0.22 * s, cy - 0.30, 0.50)
					tp = Vector3(0.0, -0.5, 1.0)
					tf = Vector3(-0.3 * s, 0.8, 0.5)
					tg = 0.8
					po = Vector3(0.8 * s, -0.4, -0.6)
				"pull":
					tgt = sh + Vector3(0.06 * s, -0.42, -0.24)
					tp = Vector3(-s, 0.0, 0.0)
					tf = Vector3(0.0, -0.9, -0.4)
					tg = 0.85
				"reach":
					tgt = Vector3(0.20 * s, cy - 0.04 + sin(_t * 2.0 + s) * 0.03, 0.50)
					tp = Vector3(-s, 0.0, 0.0)
					tf = Vector3(-0.2 * s, 0.1, 1.0)
					tg = 0.4
				"low":
					tgt = Vector3(0.20 * s, maxf(0.30, cy - 0.52), 0.46)
					tp = Vector3(-s, 0.2, 0.0)
					tf = Vector3(-0.2 * s, -0.5, 1.0)
					tg = 0.4
				"work":
					tgt = Vector3(0.13 * s + sin(_t * 1.3 + s) * 0.03, cy - 0.30 + absf(sin(_t * 2.1 + s)) * 0.03, 0.40)
					if s < 0.0:
						tgt += Vector3(sin(_t * 8.0) * 0.012, 0.03, cos(_t * 8.0) * 0.012)
					tp = Vector3(-0.5 * s, -0.8, 0.2)
					tf = Vector3(-0.25 * s, -0.35, 1.0)
					tg = 0.65
				"hammer":
					if s < 0.0:
						var hm := pow(absf(sin(_t * 2.9)), 3.0)
						tgt = Vector3(-0.16, cy - 0.16 + hm * 0.30, 0.40 - hm * 0.12)
						tf = Vector3(0.0, 0.2 + hm, 1.0)
					else:
						tgt = Vector3(0.12, cy - 0.20, 0.42)
						tf = Vector3(-0.2, 0.0, 1.0)
					tp = Vector3(-s, 0.0, 0.0)
					tg = 0.85
				"grill":
					if s < 0.0:
						tgt = Vector3(-0.12 + sin(_t * 1.9) * 0.10, cy - 0.28 + maxf(0.0, sin(_t * 3.8)) * 0.07, 0.42)
						tf = Vector3(0.0, -0.2, 1.0)
						tg = 0.8
				"lean":
					tgt = Vector3(0.24 * s, cy - 0.34, 0.30)
					tp = Vector3(0.0, -1.0, 0.2)
					tf = Vector3(-0.2 * s, 0.0, 1.0)
					tg = 0.2
				"tablet":
					tgt = Vector3(0.09, cy - 0.14, 0.30) if s > 0.0 else Vector3(-0.03 + sin(_t * 2.6) * 0.02, cy - 0.11, 0.31)
					tp = Vector3(-0.3 * s, 1.0, 0.0) if s > 0.0 else Vector3(0.3, -0.8, 0.3)
					tf = Vector3(-0.5 * s, 0.2, 0.8)
					tg = 0.5
				"drive":
					tgt = Vector3(0.14 * s, cy - 0.12, 0.40) + Vector3(0, sin(_t * 1.3) * 0.02 * s, 0)
					tp = Vector3(-s * 0.5, -0.3, 0.8)
					tf = Vector3(-0.2 * s, 0.6, 0.6)
					tg = 0.85
				"type":
					var ty := sin(_t * 19.0 + s * 1.3) * 0.010 + sin(_t * 31.0 + s) * 0.005
					tgt = Vector3(0.12 * s + sin(_t * 2.3 + s) * 0.03, cy - 0.20 + ty, 0.46)
					tp = Vector3(0.0, -1.0, 0.1)
					tf = Vector3(-0.15 * s, -0.15, 1.0)
					tg = 0.38 + absf(ty) * 8.0
					po = Vector3(0.9 * s, -0.5, -0.5)
				"sofa":
					tgt = Vector3(0.26 * s, seat_height + 0.14, 0.18)
					tf = Vector3(0.1 * s, -0.2, 1.0)
					tp = Vector3(0.0, -1.0, 0.0)
				"ladder":
					var lu := fposmod(_t * 0.9 * tempo + (0.5 if s > 0.0 else 0.0), 1.0)
					tgt = Vector3(0.18 * s, cy + 0.14 + 0.22 * sin(lu * TAU), 0.34)
					tp = Vector3(0.0, 0.0, 1.0)
					tf = Vector3(0.0, 1.0, 0.2)
					tg = 0.95
			hand = hand.lerp(tgt, w)
			palm = palm.lerp(tp, w)
			fing_dir = fing_dir.lerp(tf, w)
			pole = pole.lerp(po, w)
			grip = lerpf(grip, tg, w)
		if aw > 0.0:
			var act := _action_hand(s, sh, cy, hand)
			if not act.is_empty():
				var w2: float = aw * float(act.get("w", 1.0))
				hand = hand.lerp(act["pos"], w2)
				palm = palm.lerp(act.get("palm", palm), w2)
				fing_dir = fing_dir.lerp(act.get("dir", fing_dir), w2)
				grip = lerpf(grip, float(act.get("grip", grip)), w2)
				pole = pole.lerp(act.get("pole", pole), w2)
		hand = sh + yaw_b * (hand - sh) if base != "" and total > 0.2 and not (base in ["type", "sofa", "drive", "ladder", "push"]) else hand
		# Weich folgen, aber ohne beim Gehen hinterherzuhinken
		var kk := 1.0 - exp(-delta * 16.0) if _hand_init and delta > 0.0 else 1.0
		if s > 0.0:
			_hand_l = _hand_l.lerp(hand, kk)
			hand = _hand_l
		else:
			_hand_r = _hand_r.lerp(hand, kk)
			hand = _hand_r
		var elb := _ik(sh, hand, l1, l2, pole)
		_aim(side + "Arm", sh, elb, pole, Vector3(0, 0, -1))
		_aim(side + "ForeArm", _child_pos(_b[side + "ForeArm"]), hand, palm, Vector3(-s * 0.707, -0.707, 0.0))
		# Hand ausrichten
		var hi: int = _b[side + "Hand"]
		var fore_dir := (hand - elb).normalized()
		var fd := fing_dir.normalized()
		# Handgelenk knickt höchstens rund 70 Grad.
		if fore_dir.dot(fd) < 0.35:
			fd = (fd + fore_dir * 1.2).normalized()
		_aim_dir(side + "Hand", _child_pos(hi), fd, palm, Vector3(-s * 0.707, -0.707, 0.0))
		_fingers(side, s, grip)
	_hand_init = true


## Nur die Arme (Ich-Ansicht): Brust bleibt in Ruhelage. l, r: {"pos", "palm", "dir", "grip", "pole"} im Skelett-Raum.
func arms_only(l: Dictionary, r: Dictionary) -> void:
	for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		var i: int = _b[b]
		_g[i] = _rest_g[i]
	for side in ["Left", "Right"]:
		var s := 1.0 if side == "Left" else -1.0
		var d: Dictionary = l if side == "Left" else r
		_turn(side + "Shoulder", Basis(UP, -0.10 * s) * Basis(FWD, float(d.get("raise", 0.0)) * s))
		var ai: int = _b[side + "Arm"]
		var sh := _child_pos(ai)
		var l1 := (_rest_g[_b[side + "ForeArm"]].origin - _rest_g[ai].origin).length()
		var l2 := (_rest_g[_b[side + "Hand"]].origin - _rest_g[_b[side + "ForeArm"]].origin).length()
		var hand: Vector3 = d["pos"]
		var pole: Vector3 = d.get("pole", Vector3(0.75 * s, -0.75, -0.5))
		var palm: Vector3 = d.get("palm", Vector3(-s, 0.2, 0.0))
		var elb := _ik(sh, hand, l1, l2, pole)
		var reach := (hand - sh)
		if reach.length() > l1 + l2 - 0.004:
			hand = sh + reach.normalized() * (l1 + l2 - 0.004)
		_aim(side + "Arm", sh, elb, pole, Vector3(0, 0, -1))
		_aim(side + "ForeArm", _child_pos(_b[side + "ForeArm"]), hand, palm, Vector3(-s * 0.707, -0.707, 0.0))
		var fore_dir := (hand - elb).normalized()
		var fd: Vector3 = (d.get("dir", Vector3(0, 0, 1)) as Vector3).normalized()
		if fore_dir.dot(fd) < 0.25:
			fd = (fd + fore_dir * 1.1).normalized()
		_aim_dir(side + "Hand", _child_pos(_b[side + "Hand"]), fd, palm, Vector3(-s * 0.707, -0.707, 0.0))
		_fingers(side, s, float(d.get("grip", 0.3)))
	_apply()


func _action_hand(s: float, sh: Vector3, cy: float, cur: Vector3) -> Dictionary:
	var u := _action_t / maxf(0.01, _action_len)
	var at := _action_at
	match _action:
		"pickup", "place":
			var half := clampf(0.16 + at.x * 0.0, 0.10, 0.3)
			return {"pos": Vector3(half * s, at.y, at.z), "palm": Vector3(-s, 0.2, 0.0), "dir": Vector3(-0.25 * s, -0.35, 1.0), "grip": 0.25 + 0.4 * smoothstep(0.4, 0.6, u) if _action == "pickup" else 0.65 - 0.4 * smoothstep(0.5, 0.7, u)}
		"reach":
			return {"pos": Vector3(0.12 * s, at.y, at.z), "palm": Vector3(-s, 0.0, 0.0), "dir": Vector3(-0.1 * s, 0.0, 1.0), "grip": 0.4}
		"plug":
			if s < 0.0:
				var tw := sin(_action_t * 20.0) * 0.006
				return {"pos": Vector3(at.x - 0.02, at.y + tw, at.z + 0.02 * smoothstep(0.5, 0.7, u)), "palm": Vector3(1, -0.2, 0), "dir": Vector3(0, 0, 1), "grip": 0.85}
			return {"pos": Vector3(0.14, at.y - 0.06, at.z - 0.06), "palm": Vector3(-1, 0.2, 0), "dir": Vector3(-0.2, 0, 1), "grip": 0.5, "w": 0.7}
		"press":
			if s < 0.0:
				return {"pos": Vector3(at.x, at.y, at.z), "palm": Vector3(0, -1, 0), "dir": Vector3(0, 0.1, 1), "grip": 0.2}
		"screw":
			if s < 0.0:
				var a := _action_t * 9.0
				return {"pos": Vector3(at.x, at.y, at.z), "palm": Vector3(cos(a), sin(a), 0.0), "dir": Vector3(0, 0, 1), "grip": 0.9}
			return {"pos": Vector3(0.16, at.y - 0.04, at.z - 0.02), "palm": Vector3(-1, 0, 0), "dir": Vector3(-0.2, 0, 1), "grip": 0.4, "w": 0.8}
		"drink":
			if s < 0.0:
				return {"pos": Vector3(-0.05, cy + 0.24, 0.17), "palm": Vector3(1, 0, 0), "dir": Vector3(0.3, 0.6, 0.5), "grip": 0.7, "pole": Vector3(-0.9, -0.5, 0.0)}
		"wave":
			if s < 0.0:
				return {"pos": sh + Vector3(-0.22 + sin(_action_t * 11.0) * 0.10, 0.34, 0.14), "palm": Vector3(0, 0, 1), "dir": Vector3(sin(_action_t * 11.0) * 0.4, 1, 0), "grip": 0.05, "pole": Vector3(-1, -0.6, -0.2)}
		"salute":
			if s < 0.0:
				return {"pos": Vector3(-0.11, cy + 0.30, 0.12), "palm": Vector3(0, -0.6, 0.6), "dir": Vector3(0.6, 0.6, 0.1), "grip": 0.0, "pole": Vector3(-1, 0.0, -0.1)}
		"point":
			if s < 0.0:
				return {"pos": sh + Vector3(-0.02, 0.04, 0.50), "palm": Vector3(1, -0.4, 0), "dir": Vector3(0, 0.05, 1), "grip": 0.75}
		"thumbs":
			if s < 0.0:
				return {"pos": sh + Vector3(-0.02, -0.12, 0.40), "palm": Vector3(1, 0, 0), "dir": Vector3(0.1, 0.1, 1), "grip": 1.0}
		"cheer":
			return {"pos": sh + Vector3(0.20 * s, 0.46 + sin(_action_t * 12.0) * 0.05, 0.06), "palm": Vector3(-s, 0, 0.3), "dir": Vector3(0, 1, 0), "grip": 0.9, "pole": Vector3(s, -0.3, -0.3)}
		"clap":
			var c := absf(sin(_action_t * 11.0))
			return {"pos": Vector3((0.03 + 0.09 * c) * s, cy + 0.02, 0.34), "palm": Vector3(-s, 0, 0), "dir": Vector3(0, 0.6, 0.8), "grip": 0.05}
		"shrug":
			return {"pos": sh + Vector3(0.16 * s, -0.20, 0.22), "palm": Vector3(0, 1, 0.2), "dir": Vector3(0.6 * s, 0.1, 0.6), "grip": 0.1}
		"facepalm":
			if s < 0.0:
				return {"pos": Vector3(-0.02, cy + 0.26, 0.17), "palm": Vector3(0, 0, -1), "dir": Vector3(0.3, 1, -0.1), "grip": 0.1, "pole": Vector3(-0.8, -0.6, 0.2)}
		"laugh":
			return {"pos": Vector3(0.08 * s, cy - 0.28, 0.20), "palm": Vector3(-s * 0.4, 0, -1), "dir": Vector3(-s, 0, 0.2), "grip": 0.3, "w": 0.8}
		"dance":
			var q := sin(_t * 7.0 + (0.0 if s > 0.0 else PI))
			return {"pos": sh + Vector3(0.22 * s, 0.02 + q * 0.22, 0.28), "palm": Vector3(-s, 0, 0.2), "dir": Vector3(0, 0.7, 0.7), "grip": 0.7}
		"feed", "sweep":
			if s < 0.0:
				var f := sin(_action_t * 7.0)
				return {"pos": Vector3(-0.10 + f * 0.14, at.y, at.z), "palm": Vector3(0.2, -1, 0), "dir": Vector3(f * 0.4, -0.1, 1), "grip": 0.3}
	return {}


func _fingers(side: String, s: float, grip: float) -> void:
	# Beugen um die Querachse der Hand.
	var hb := _g[_b[side + "Hand"]].basis
	var rb := _rest_g[_b[side + "Hand"]].basis
	var ax := (hb * rb.inverse()) * Vector3(0, 0, -s)
	var c := clampf(grip, 0.0, 1.0)
	var point := _action == "point" and side == "Right"
	for e in [["Fingers1", 1.25], ["Fingers2", 1.5]]:
		var i: int = _b[side + str(e[0])]
		var p := _g[_par[i]]
		var local := _rest[i]
		var b := p.basis * local.basis
		b = Basis(ax.normalized(), c * float(e[1]) * (0.55 if point else 1.0)) * b
		_g[i] = Transform3D(b, p * local.origin)
	for e in [["Thumb1", 0.5], ["Thumb2", 0.7]]:
		var i2: int = _b[side + str(e[0])]
		var p2 := _g[_par[i2]]
		var l2 := _rest[i2]
		var th := c * float(e[1]) * (-0.4 if _action == "thumbs" and side == "Right" else 1.0)
		_g[i2] = Transform3D(Basis(ax.normalized(), th) * (p2.basis * l2.basis), p2 * l2.origin)


# ---------------------------------------------------------------- Rechnen

func _put(bone: String, pos: Vector3, b: Basis) -> void:
	var i: int = _b[bone]
	_g[i] = Transform3D(b * _rest_g[i].basis, pos)


func _child_pos(i: int) -> Vector3:
	return _g[_par[i]] * _rest[i].origin


## Dreht einen Knochen gegenüber seinem Elternteil um eine Drehung im Skelett-Raum der Ruhelage.
func _turn(bone: String, d: Basis) -> void:
	var i: int = _b[bone]
	var pg := _g[_par[i]]
	var prg := _rest_g[_par[i]].basis
	var pd := pg.basis * prg.inverse()
	_g[i] = Transform3D(pd * d * _rest_g[i].basis, pg * _rest[i].origin)


func _ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := t - a
	var len := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.004)
	var n := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var x := (l1 * l1 - l2 * l2 + len * len) / (2.0 * len)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var p := pole - n * pole.dot(n)
	if p.length() < 0.001:
		p = Vector3(0, 0, 1) - n * n.z
	return a + n * x + p.normalized() * h


func _aim(bone: String, from: Vector3, to: Vector3, pole: Vector3, rest_pole: Vector3) -> void:
	_aim_dir(bone, from, (to - from).normalized(), pole, rest_pole)


## Knochen auf eine Richtung stellen und so verdrehen, dass rest_pole zu pole zeigt.
func _aim_dir(bone: String, from: Vector3, dir: Vector3, pole: Vector3, rest_pole: Vector3) -> void:
	var i: int = _b[bone]
	var rb := _rest_g[i].basis
	var rd := rb.y.normalized()
	var q := Quaternion(rd, dir) if rd.dot(dir) > -0.9999 else Quaternion(Vector3.UP, PI)
	var p1 := q * rest_pole
	p1 = p1 - dir * p1.dot(dir)
	var p2 := pole - dir * pole.dot(dir)
	if p1.length() > 0.01 and p2.length() > 0.01:
		var ang := p1.normalized().signed_angle_to(p2.normalized(), dir)
		q = Quaternion(dir, ang) * q
	_g[i] = Transform3D(Basis(q) * rb, from)


func _apply() -> void:
	for i in _g.size():
		var p := _par[i]
		if p < 0:
			_s.set_bone_pose_position(i, _g[i].origin)
			_s.set_bone_pose_rotation(i, _g[i].basis.get_rotation_quaternion())
		elif _s.get_bone_name(i) == "Jaw":
			continue
		else:
			_s.set_bone_pose_rotation(i, (_g[p].basis.inverse() * _g[i].basis).get_rotation_quaternion())


## Weltlage einer Hand (für gehaltene Dinge).
func hand_transform(left: bool) -> Transform3D:
	var i: int = _b["LeftHand" if left else "RightHand"]
	return _s.global_transform * _s.get_bone_global_pose(i)


# ---------------------------------------------------------------- Gesicht

func _face(delta: float) -> void:
	_blink_next -= delta
	if _blink_next <= 0.0:
		_blink = 1.0
		_blink_next = randf_range(1.8, 5.5) if randf() > 0.15 else 0.28
	_blink = maxf(0.0, _blink - delta * 7.0)
	_m.face("Blink", sin(clampf(_blink, 0.0, 1.0) * PI))
	var open := 0.0
	if talk > 0.0:
		open = talk * clampf(0.35 + 0.65 * sin(_t * 17.0) * sin(_t * 7.3 + 1.0), 0.0, 1.0)
	var happy := maxf(0.0, mood + 0.12)
	var aw := _aw()
	match _action:
		"cheer", "laugh":
			open = maxf(open, aw * (0.6 + 0.4 * sin(_t * 14.0)))
			happy = maxf(happy, aw)
		"dance", "wave", "thumbs", "clap":
			happy = maxf(happy, aw * 0.8)
	_m.face("Mouth_Open", open)
	_m.face("Smile", happy)
	_m.face("Frown", maxf(0.0, -mood))
	_m.face("Brow_Up", clampf(happy * 0.5 + (aw if _action == "shrug" else 0.0), 0.0, 1.0))
	_m.face("Brow_Angry", maxf(0.0, -mood))
	_m.face("Squint", happy * 0.5)
