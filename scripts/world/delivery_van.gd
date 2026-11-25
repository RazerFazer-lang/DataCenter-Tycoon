class_name DeliveryVan
extends Node3D
## Lieferfahrzeuge (E-Transporter, 7,5 t mit Ladebordwand, 18 t mit Mitnahmestapler) samt Personal und Ladung.
## Fahrweg und Ablauf kommen aus DeliveryPlan und sind reine Funktionen der Zeit: Alle sehen dasselbe.

const DRIVE_IN_END := 5.2
const FORK_DOCK_Y := 0.46
const BRAND := "CLOUD EXPRESS"

var _veh: Node3D
var _active_tier := 0
var _site := "garage"
var _wheels: Array[Node3D] = []
var _wheel_bases: Array[Transform3D] = []
var _wheel_spin := 0.0
var _doors: Array[Node3D] = []
var _roller: Node3D
var _roller_y := 0.0
var _lift: Node3D
var _cab_door: Node3D
var _mats: Dictionary = {}
var _headlight: SpotLight3D
var _cargo_light: OmniLight3D
var _engine: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D

var _crew: Array[DeliveryCrew] = []
var _sacks: Array[Node3D] = []
var _sack_wheels: Array = []
var _sack_last: Array[Vector3] = []
var _jack: Node3D
var _jack_handle: Node3D
var _fork: Node3D
var _fork_lift: Node3D
var _fork_wheels: Array[Node3D] = []
var _fork_last := Vector3.ZERO
var _goods: Array[Node3D] = []
var _pallets: Dictionary = {}
var _plan_ref: Dictionary = {}
var _sign_area: Area3D

var _prev_phase := "idle"
var _prev_trip := ""
var _prev_pos := Vector3.ZERO
var _beep := 0.0
var _blink := 0.0
var _door_u := 0.0
var _was_open := false
var _cab_u := 0.0


func _ready() -> void:
	visible = false
	_veh = Node3D.new()
	add_child(_veh)
	_engine = AudioStreamPlayer3D.new()
	_engine.position = Vector3(0.0, 0.85, 3.4)
	_engine.stream = SfxManager.get_loop_stream("van_engine")
	_engine.max_distance = 34.0
	_engine.unit_size = 4.6
	_engine.volume_db = -60.0
	_veh.add_child(_engine)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.position = Vector3(0.0, 1.2, -1.0)
	_sfx.max_distance = 34.0
	_sfx.unit_size = 5.0
	_veh.add_child(_sfx)
	_sign_area = Area3D.new()
	_sign_area.collision_layer = 4
	_sign_area.collision_mask = 0
	_sign_area.set_meta("interact_type", "delivery_sign")
	_sign_area.set_meta("entity_id", "van")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 1.9, 0.8)
	cs.shape = bs
	cs.position.y = 0.95
	cs.disabled = true
	_sign_area.add_child(cs)
	add_child(_sign_area)


# ---------------------------------------------------------------- Aufbau

func _switch(tier: int) -> void:
	if tier == _active_tier:
		return
	_active_tier = tier
	var v := DeliveryPlan.spec(tier)
	for c in _veh.get_children():
		if c != _engine and c != _sfx:
			_veh.remove_child(c)
			c.queue_free()
	_wheels.clear()
	_wheel_bases.clear()
	_doors.clear()
	_mats.clear()
	_roller = null
	_lift = null
	_cab_door = null
	var m := ModelLoader.instantiate_custom_model(str(v["model"]))
	if m != null:
		_veh.add_child(m)
		for n in ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]:
			var w := m.find_child(n, true, false) as Node3D
			if w != null:
				_wheels.append(w)
				_wheel_bases.append(w.transform)
		for n in ["Door_RL", "Door_RR"]:
			var d := m.find_child(n, true, false) as Node3D
			if d != null:
				_doors.append(d)
		_roller = m.find_child("Rear_Door", true, false) as Node3D
		if _roller != null:
			_roller_y = _roller.position.y
		_lift = m.find_child("Tail_Lift", true, false) as Node3D
		_cab_door = m.find_child("Cab_Door_L", true, false) as Node3D
		for mn in ["Van_BeaconMat", "Van_HazardMat", "Van_BrakeMat", "Van_HeadMat", "Van_CargoMat"]:
			_mats[mn] = _take_mat(m, mn)
	var half := float(v["half"])
	for sx in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = BRAND
		l.font_size = 64
		l.pixel_size = 0.0030 if tier == 1 else 0.0046
		l.outline_size = 0
		l.modulate = Color(0.04, 0.30, 0.38)
		l.position = Vector3(sx * (half + (0.008 if tier > 1 else -0.008)), 1.62 if tier == 1 else float(v["floor"]) + 1.35, 0.55 if tier == 1 else 1.0)
		l.rotation_degrees.y = 90.0 * sx
		if tier == 1:
			l.rotation_degrees.x = 0.0
		_veh.add_child(l)
	_headlight = SpotLight3D.new()
	_headlight.position = Vector3(0.0, 0.95, float(v["fo"]))
	_headlight.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
	_headlight.spot_range = 18.0
	_headlight.spot_angle = 42.0
	_headlight.light_color = Color(1.0, 0.96, 0.88)
	_headlight.shadow_enabled = false
	_veh.add_child(_headlight)
	_cargo_light = OmniLight3D.new()
	_cargo_light.position = Vector3(0.0, float(v["top"]) - 0.3, 0.2)
	_cargo_light.omni_range = 4.5
	_cargo_light.light_color = Color(1.0, 0.97, 0.90)
	_veh.add_child(_cargo_light)
	_build_crew(v, tier)


func _build_crew(v: Dictionary, tier: int) -> void:
	for c in _crew:
		c.queue_free()
	_crew.clear()
	for s in _sacks:
		s.queue_free()
	_sacks.clear()
	_sack_wheels.clear()
	_sack_last.clear()
	for n in [_jack, _fork]:
		if n != null:
			n.queue_free()
	_jack = null
	_fork = null
	_fork_wheels.clear()
	for i in int(v["crew"]):
		var c := DeliveryCrew.new()
		add_child(c)
		c.visible = false
		_crew.append(c)
		var s := ModelLoader.instantiate_custom_model("sack_truck")
		if s == null:
			s = Node3D.new()
		add_child(s)
		s.visible = false
		_sacks.append(s)
		_sack_wheels.append([s.find_child("Wheel_L", true, false), s.find_child("Wheel_R", true, false)])
		_sack_last.append(Vector3.ZERO)
	if tier == 2:
		_jack = ModelLoader.instantiate_custom_model("pallet_jack")
		if _jack != null:
			add_child(_jack)
			_jack_handle = _jack.find_child("Handle", true, false) as Node3D
	if tier == 3:
		_fork = ModelLoader.instantiate_custom_model("forklift")
		if _fork != null:
			add_child(_fork)
			_fork_lift = _fork.find_child("Forks", true, false) as Node3D
			for n in ["Wheel_FL", "Wheel_FR", "Wheel_B"]:
				var w := _fork.find_child(n, true, false) as Node3D
				if w != null:
					_fork_wheels.append(w)


func _take_mat(root: Node, mat_name: String) -> StandardMaterial3D:
	var found: StandardMaterial3D = null
	for mi_n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(s)
			if sm is StandardMaterial3D and sm.resource_name == mat_name:
				if found == null:
					found = (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
					found.emission_enabled = true
				mi.set_surface_override_material(s, found)
	return found


func _set_glow(n: String, e: float) -> void:
	var m: StandardMaterial3D = _mats.get(n)
	if m != null:
		m.emission_energy_multiplier = e


func _play(id: String, db: float = -4.0, pitch: float = 1.0) -> void:
	var st := SfxManager.get_sound_stream(id)
	var g := SettingsManager.get_effective_sfx_gain()
	if st == null or g < 0.005:
		return
	_sfx.stream = st
	_sfx.volume_db = linear_to_db(g * SfxManager.get_outdoor_transmission()) + db
	_sfx.pitch_scale = pitch
	_sfx.play()


# ---------------------------------------------------------------- Ablauf

func _process(delta: float) -> void:
	_blink += delta
	var phase := GameState.van_phase
	if not GameState.is_active or phase == "idle":
		if visible:
			_hide_all()
		_prev_phase = "idle"
		return
	var tier := clampi(GameState.van_delivery_tier, 1, 3)
	if tier != _active_tier:
		_switch(tier)
	_site = GameState.van_site
	visible = true
	var t := GameState.van_phase_time
	var trip := GameState.van_trip_phase
	var tt := GameState.van_trip_time
	var pose := DeliveryPlan.vehicle_pose(_site, tier, phase, t)
	if phase != _prev_phase:
		if _prev_phase == "idle":
			_prev_pos = pose["pos"]
		if phase == "unloading" and tier >= 2:
			_play("air_brake", -4.5, randf_range(0.92, 1.05))
		_prev_phase = phase
	_veh.position = pose["pos"]
	_veh.rotation.y = float(pose["yaw"])
	_update_wheels(pose, tier)
	_update_lights(delta, phase, t, pose)
	_update_engine(delta, pose)
	var want_door := 0.0
	var plan: Dictionary = GameState.van_plan
	if phase == "unloading" and not plan.is_empty():
		want_door = 1.0 if (trip == "work" and t >= float(plan.get("t_open", 9.0)) - 0.3) or trip == "sign" or (trip == "enter" and tt < 1.6) else 0.0
	_door_u = move_toward(_door_u, want_door, delta / 1.3)
	if (want_door > 0.5) != _was_open:
		_was_open = want_door > 0.5
		_play("van_door", -5.0, 0.8 if tier > 1 else 1.0)
	_update_doors(tier, plan, phase, trip, t)
	_update_plan_nodes(plan, phase)
	_update_crew(delta, plan, phase, trip, t, tt, tier)
	_push_player(pose, tier)
	_prev_pos = pose["pos"]


func _hide_all() -> void:
	visible = false
	_door_u = 0.0
	_cab_u = 0.0
	for c in _crew:
		c.reset()
	for g in _goods:
		if is_instance_valid(g):
			g.queue_free()
	_goods.clear()
	for k in _pallets.keys():
		(_pallets[k] as Node3D).queue_free()
	_pallets.clear()
	_plan_ref = {}
	_set_sign(false, Vector3.ZERO)
	if _engine.playing:
		_engine.stop()


func _update_wheels(pose: Dictionary, tier: int) -> void:
	var v := DeliveryPlan.spec(tier)
	var d := (pose["pos"] as Vector3) - _prev_pos
	var fwd := Vector3(sin(float(pose["yaw"])), 0.0, cos(float(pose["yaw"])))
	_wheel_spin = wrapf(_wheel_spin + d.dot(fwd) / float(v["r"]), -TAU, TAU)
	for i in _wheels.size():
		var b := Basis(Vector3.RIGHT, _wheel_spin)
		if str(_wheels[i].name).begins_with("Wheel_F"):
			b = Basis(Vector3.UP, float(pose["steer"])) * b
		_wheels[i].transform = Transform3D(_wheel_bases[i].basis * b, _wheel_bases[i].origin)


func _update_lights(delta: float, phase: String, _t: float, pose: Dictionary) -> void:
	var on := sin(_blink * 9.5) > 0.0
	var dir := int(pose["dir"])
	var warn := phase == "unloading" or dir < 0
	_set_glow("Van_BeaconMat", (2.8 if on else 0.2) if warn else 0.12)
	_set_glow("Van_HazardMat", (2.6 if on else 0.05) if warn else 0.05)
	_set_glow("Van_BrakeMat", 2.6 if dir <= 0 else 0.6)
	_set_glow("Van_CargoMat", 0.2 + 1.6 * _door_u)
	var night := GameState.time_of_day < 0.25 or GameState.time_of_day > 0.74
	_set_glow("Van_HeadMat", 3.0 if night else 0.9)
	_headlight.light_energy = 3.0 if night else 0.0
	_headlight.visible = night
	_cargo_light.light_energy = 1.1 * _door_u
	_cargo_light.visible = _door_u > 0.02
	if dir < 0:
		_beep += delta
		if _beep >= 0.68:
			_beep = 0.0
			_play("backup_beep", -6.5, 1.0 if _active_tier < 3 else 0.94)
	else:
		_beep = 0.55


func _update_engine(delta: float, pose: Dictionary) -> void:
	var gain := SettingsManager.get_effective_sfx_gain()
	var parked := GameState.van_phase == "unloading" and GameState.van_phase_time > 1.0 and GameState.van_trip_phase != "enter"
	if gain <= 0.005 or (parked and _active_tier == 1):
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	var speed := (pose["pos"] as Vector3).distance_to(_prev_pos) / maxf(delta, 0.001)
	var vol := clampf((0.16 + clampf(speed / 12.0, 0.0, 0.5)) * gain * SfxManager.get_outdoor_transmission(), 0.005, 1.0)
	if parked:
		vol *= 0.45
	# Der Transporter fährt elektrisch: leiser und heller als die Lkw.
	_engine.volume_db = linear_to_db(vol) - (13.0 if _active_tier == 1 else (5.0 if _active_tier == 2 else 3.5))
	_engine.pitch_scale = clampf((0.84 + speed * 0.042) * [1.5, 0.84, 0.68][_active_tier - 1], 0.5, 2.0)


func _update_doors(tier: int, plan: Dictionary, phase: String, trip: String, t: float) -> void:
	if tier == 1:
		for d in _doors:
			var sx := 1.0 if str(d.name) == "Door_RL" else -1.0
			d.rotation.y = -sx * smoothstep(0.0, 1.0, _door_u) * deg_to_rad(108.0)
	elif _roller != null:
		var u := smoothstep(0.0, 1.0, clampf(_door_u * 1.2, 0.0, 1.0))
		_roller.scale.y = maxf(0.04, 1.0 - u * 0.96)
	if _lift != null:
		var h := _lift_height(plan, phase, trip, t)
		var fold := smoothstep(0.0, 1.0, clampf(_door_u / 0.6, 0.0, 1.0))
		# 90 Grad = hochgeklappt vor der Tür
		_lift.rotation.x = deg_to_rad(90.0) * (1.0 - fold)
		_lift.position.y = lerpf(0.05, float(DeliveryPlan.spec(2)["floor"]), maxf(h, 1.0 - smoothstep(0.5, 1.0, _door_u)))
	if _cab_door != null:
		var want := 0.0
		if phase == "unloading":
			if (trip == "work" and t < 1.7 and t > 0.2) or (trip == "enter" and GameState.van_trip_time > 6.4 and GameState.van_trip_time < 8.4):
				want = 1.0
		_cab_u = move_toward(_cab_u, want, get_process_delta_time() / 0.5)
		_cab_door.rotation.y = deg_to_rad(62.0) * smoothstep(0.0, 1.0, _cab_u)


## Höhe der Ladebordwand: 0 am Boden, 1 auf Ladehöhe.
func _lift_height(plan: Dictionary, phase: String, trip: String, t: float) -> float:
	if phase != "unloading" or trip != "work" or plan.is_empty():
		return 0.0 if trip == "sign" else (1.0 if phase != "unloading" else 0.0)
	for j in plan["jobs"]:
		if str(j["kind"]) != "jack":
			continue
		var u := (t - float(j["t"])) / float(j["load"])
		if u >= 0.0 and u < 1.0:
			return smoothstep(0.0, 0.26, u) * (1.0 - smoothstep(0.56, 0.86, u))
		# Zum Verladen des leeren Hubwagens nach der Rückkehr
		var b0 := float(j["t"]) + float(j["load"]) + float(j["go"]) + float(j["drop"])
		var ub := (t - b0) / float(j["back"])
		if ub > 0.8 and ub <= 1.0:
			return smoothstep(0.8, 1.0, ub) * 0.0
	return 0.0


# ---------------------------------------------------------------- Ladung

func _update_plan_nodes(plan: Dictionary, phase: String) -> void:
	if plan.is_empty() or phase != "unloading":
		for g in _goods:
			g.visible = false
		for k in _pallets.keys():
			(_pallets[k] as Node3D).visible = false
		return
	var sig := {"n": (plan["items"] as Array).size(), "end": plan["end"], "site": plan["site"]}
	if sig == _plan_ref:
		return
	_plan_ref = sig
	for g in _goods:
		g.queue_free()
	_goods.clear()
	for k in _pallets.keys():
		(_pallets[k] as Node3D).queue_free()
	_pallets.clear()
	for i in (plan["items"] as Array).size():
		var e: Dictionary = plan["items"][i]
		var n := Node3D.new()
		add_child(n)
		n.visible = false
		_goods.append(n)
		var cr := DeliveryPlan.crate_of(str(e["it"]))
		if e.has("label"):
			cr["label"] = e["label"]
		match str(e["cls"]):
			"parcel":
				n.add_child(CartonFactory.build("parcel", tr("Bauteile")))
			"cart":
				var cm := ModelLoader.instantiate_custom_model("cart")
				if cm != null:
					n.add_child(cm)
			_:
				n.add_child(ShelfProp.goods_visual(cr))
		if str(e["cls"]) == "big":
			var p := ModelLoader.instantiate_custom_model("euro_pallet")
			if p != null:
				add_child(p)
				p.visible = false
				_pallets[i] = p


func _world(p: Vector2, y: float = 0.0) -> Vector3:
	return DeliveryPlan.offset(_site) + Vector3(p.x, y, p.y)


func _bed_pos(e: Dictionary) -> Vector3:
	var v := DeliveryPlan.spec(_active_tier)
	var b: Vector3 = e.get("bed", Vector3.ZERO)
	return _veh.transform * Vector3(b.x, float(v["floor"]) + b.y, b.z)


func _put(i: int, pos: Vector3, yaw: float, pal_y: float = -1.0) -> void:
	if i >= _goods.size():
		return
	var n := _goods[i]
	n.visible = true
	n.position = pos
	n.rotation = Vector3(0.0, yaw, 0.0)
	if _pallets.has(i):
		var p: Node3D = _pallets[i]
		p.visible = pal_y >= -0.5
		if p.visible:
			p.position = Vector3(pos.x, pal_y, pos.z)
			p.rotation = Vector3(0.0, yaw, 0.0)
			n.position.y = pal_y + DeliveryPlan.PALLET_H


# ---------------------------------------------------------------- Personal

static func _yaw_to(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func _update_crew(delta: float, plan: Dictionary, phase: String, trip: String, t: float, tt: float, tier: int) -> void:
	for s in _sacks:
		s.visible = false
	for i in _goods.size():
		_goods[i].visible = false
	for k in _pallets.keys():
		(_pallets[k] as Node3D).visible = false
	var parked := phase == "unloading" and not plan.is_empty()
	_dock_machines(parked, t, trip, tt, plan)
	if not parked:
		for c in _crew:
			c.drive({"visible": false}, delta)
		_set_sign(false, Vector3.ZERO)
		return
	# Alles, was noch nicht angefasst wurde, steht auf der Ladefläche.
	var started: Dictionary = {}
	for j in plan["jobs"]:
		if trip != "work" or t >= float(j["t"]):
			for i in j["items"]:
				started[int(i)] = true
	if _door_u > 0.02:
		for i in (plan["items"] as Array).size():
			if not started.has(i):
				var bp := _bed_pos(plan["items"][i])
				_put(i, bp, 0.0, bp.y if _pallets.has(i) else -1.0)
	var lead := 1 if _crew.size() > 1 else 0
	for w in _crew.size():
		var st := _crew_state(w, plan, trip, t, tt, tier, w == lead)
		_crew[w].drive(st, delta)
	if trip == "sign":
		_set_sign(true, _world(_sign_spot(tier)))
	else:
		_set_sign(false, Vector3.ZERO)


func _set_sign(on: bool, pos: Vector3) -> void:
	var cs := _sign_area.get_child(0) as CollisionShape3D
	if cs.disabled == on:
		cs.disabled = not on
	_sign_area.position = pos


func _sign_spot(tier: int) -> Vector2:
	return Vector2(0.45, minf(DeliveryPlan.rear_z(tier) - 1.7, 7.3)) if tier < 3 else Vector2(0.2, 6.4)


func _wait_spot(w: int, tier: int) -> Vector2:
	var rz := DeliveryPlan.rear_z(tier)
	if tier == 1:
		return Vector2(0.0, rz - 0.8)
	return Vector2(-1.75 if w % 2 == 0 else 1.75, rz - 0.5)


func _cab_point(w: int, tier: int) -> Vector2:
	var v := DeliveryPlan.spec(tier)
	var sx := -1.0 if w == 1 else 1.0
	return Vector2(sx * (float(v["half"]) + 0.55), float(v["axle_z"]) + float(v["wb"]) - 0.55)


func _corner_point(w: int, tier: int) -> Vector2:
	var v := DeliveryPlan.spec(tier)
	var sx := -1.0 if w == 1 else 1.0
	return Vector2(sx * (float(v["half"]) + 0.55), DeliveryPlan.rear_z(tier) - 0.15)


func _crew_state(w: int, plan: Dictionary, trip: String, t: float, tt: float, tier: int, lead: bool) -> Dictionary:
	var forkman := tier == 3 and w == 0
	if trip == "enter":
		return _enter_state(w, tier, tt, lead, forkman)
	var mine: Array = []
	for j in plan["jobs"]:
		if int(j["w"]) == w:
			mine.append(j)
	if trip == "sign":
		if forkman and not mine.is_empty():
			if tt < 2.4:
				return _fork_seat("dock", tt)
			return {"pos": _world(Vector2(1.35, DeliveryPlan.rear_z(tier) - 0.7)), "yaw": 0.0, "pose": "walk"}
		if lead:
			return {"pos": _world(_sign_spot(tier)), "yaw": 0.0, "pose": "wave" if tt < 2.0 else "tablet", "tablet": tt >= 2.0, "text": tr("Bitte unterschreiben! [E]")}
		var ws := _wait_spot(w, tier)
		return {"pos": _world(ws), "yaw": 0.0, "pose": "walk"}
	# Aussteigen und nach hinten gehen
	var delay := 0.0 if w < 2 else 1.0
	var a := _cab_point(w, tier)
	var c := _corner_point(w, tier)
	var start_spot := _wait_spot(w, tier)
	var t_walk := float(plan["t_walk"])
	if t < 1.0 + delay:
		return {"visible": false, "pos": _world(a), "yaw": 0.0}
	if t < t_walk + delay:
		var r := DeliveryPlan.along(PackedVector2Array([a, c, start_spot]), (t - 1.0 - delay) / maxf(0.1, t_walk - 1.0))
		return {"pos": _world(r[0]), "yaw": _yaw_to(r[1]), "pose": "walk"}
	var t0 := float(plan["t0"])
	if t < t0 or mine.is_empty():
		if forkman and not mine.is_empty():
			return _fork_board(t, t0, start_spot)
		# Türen öffnen
		var opening := w == 0 and t > float(plan["t_open"]) - 0.4 and t < float(plan["t_open"]) + 1.2
		return {"pos": _world(start_spot), "yaw": PI if t < t0 else 0.0, "pose": "reach" if opening else "walk"}
	for j in mine:
		var jt := float(j["t"])
		if t < jt:
			# Auf den nächsten Auftrag warten
			if forkman:
				return _fork_seat("wait", 0.0, j)
			var p0: PackedVector2Array = j["path"]
			return {"pos": _world(p0[0] if tier == 1 else start_spot.lerp(p0[0], smoothstep(jt - 1.6, jt - 0.2, t))), "yaw": PI, "pose": "walk"}
		if t < jt + float(j["load"]) + float(j["go"]) + float(j["drop"]) + float(j["back"]):
			return _job_state(j, plan, t - jt, w, tier)
	# Fertig: warten, der Wortführer geht schon Richtung Tor.
	if forkman:
		return _fork_seat("wait", 0.0, mine[mine.size() - 1])
	var last: PackedVector2Array = (mine[mine.size() - 1] as Dictionary)["path"]
	var goal := _sign_spot(tier) if lead else start_spot
	var fin: Dictionary = mine[mine.size() - 1]
	var since := t - (float(fin["t"]) + float(fin["load"]) + float(fin["go"]) + float(fin["drop"]) + float(fin["back"]))
	var l2 := maxf(0.3, last[0].distance_to(goal) / DeliveryPlan.WALK)
	var u := clampf(since / l2, 0.0, 1.0)
	var pos := last[0].lerp(goal, u)
	return {"pos": _world(pos), "yaw": _yaw_to(goal - last[0]) if u < 1.0 else 0.0, "pose": "walk"}


func _enter_state(w: int, tier: int, tt: float, lead: bool, forkman: bool) -> Dictionary:
	var from := _sign_spot(tier) if lead else _wait_spot(w, tier)
	if forkman:
		from = Vector2(1.35, DeliveryPlan.rear_z(tier) - 0.7)
	var t_go := 1.4
	if tt < t_go:
		return {"pos": _world(from), "yaw": 0.0, "pose": "wave" if lead else "walk", "text": tr("Danke, schönen Tag noch!") if lead and GameState.van_trip_phase == "enter" else ""}
	var a := _cab_point(w, tier)
	var c := _corner_point(w, tier)
	var u := (tt - t_go) / (7.6 - t_go)
	if u >= 1.0:
		return {"visible": false, "pos": _world(a), "yaw": 0.0}
	var r := DeliveryPlan.along(PackedVector2Array([from, c, a]), u)
	return {"pos": _world(r[0]), "yaw": _yaw_to(r[1]), "pose": "walk"}


## Ein Auftrag: laden, hingehen, absetzen, zurück.
func _job_state(j: Dictionary, plan: Dictionary, s: float, w: int, tier: int) -> Dictionary:
	var kind := str(j["kind"])
	if kind == "fork":
		return _fork_job(j, plan, s)
	if kind == "jack":
		return _jack_job(j, plan, s, tier)
	var path: PackedVector2Array = j["path"]
	var load_t := float(j["load"])
	var go := float(j["go"])
	var drop := float(j["drop"])
	var back := float(j["back"])
	var items: Array = j["items"]
	var first: Dictionary = plan["items"][int(items[0])]
	var target: Vector3 = first["pos"]
	var end := path[path.size() - 1]
	var face := Vector2(target.x, target.z) - end
	var pos := path[0]
	var yaw := PI
	var pose := "carry"
	var crouch := 0.0
	var stage := 0
	var u := 0.0
	if s < load_t:
		u = s / load_t
		pose = "reach" if (u < 0.5 if kind == "hand" else true) else "carry"
	elif s < load_t + go:
		stage = 1
		u = (s - load_t) / go
		var eased := u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65
		var r := DeliveryPlan.along(path, eased)
		pos = r[0]
		yaw = _yaw_to(r[1])
		pose = "carry" if kind == "hand" else "push"
		if u > 0.94:
			yaw = _yaw_to(face)
	elif s < load_t + go + drop:
		stage = 2
		u = (s - load_t - go) / drop
		pos = end
		yaw = _yaw_to(face)
		if kind == "hand":
			var low := target.y < 0.5
			pose = "low" if low else "reach"
			crouch = (0.75 if low else 0.15) * sin(clampf(u * 1.1, 0.0, 1.0) * PI)
		else:
			pose = "reach" if kind == "truck" and u > 0.15 else "push"
			if str(first["cls"]) != "big" and kind == "truck":
				crouch = 0.35 * absf(sin(u * PI * float(items.size())))
	else:
		stage = 3
		u = clampf((s - load_t - go - drop) / back, 0.0, 1.0)
		var r2 := DeliveryPlan.along(path, 1.0 - u)
		pos = r2[0]
		yaw = _yaw_to(-(r2[1] as Vector2))
		pose = "walk" if kind == "hand" else ("push" if kind == "truck" else "walk")
		if u > 0.95:
			yaw = PI
	if stage < 3 and stage > 0 and kind == "hand" and u < 0.55 and stage == 2:
		pose = "low" if target.y < 0.5 else "reach"
	var wp := _world(pos)
	if tier == 2 and pos.y > DeliveryPlan.rear_z(tier) - DeliveryPlan.LIFT_LEN:
		wp.y = 0.05
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	if kind == "hand":
		_carry_items(items, plan, stage, u, wp, yaw, fwd)
	elif kind == "truck":
		_sack_items(items, plan, stage, u, wp, yaw, fwd, w)
	else:
		_roll_items(items, plan, stage, u, wp, yaw, fwd)
	return {"pos": wp, "yaw": yaw, "pose": pose, "crouch": crouch}


func _carry_items(items: Array, plan: Dictionary, stage: int, u: float, wp: Vector3, yaw: float, fwd: Vector3) -> void:
	var i := int(items[0])
	var e: Dictionary = plan["items"][i]
	var d: Vector3 = e["d"]
	var hand := wp + fwd * (0.30 + d.z * 0.5) + Vector3(0.0, 0.98 - d.y * 0.35, 0.0)
	var goal := (e["pos"] as Vector3) + DeliveryPlan.offset(_site)
	match stage:
		0:
			var k := smoothstep(0.35, 0.95, u)
			_put(i, _bed_pos(e).lerp(hand, k) + Vector3(0.0, sin(k * PI) * 0.10, 0.0), lerp_angle(0.0, yaw, k))
		1:
			_put(i, hand + Vector3(0.0, absf(sin(Time.get_ticks_msec() * 0.009)) * 0.012, 0.0), yaw)
		2:
			if u < 0.80:
				var k2 := smoothstep(0.1, 0.75, u)
				_put(i, hand.lerp(goal, k2), lerp_angle(yaw, 0.0, k2))


func _sack_items(items: Array, plan: Dictionary, stage: int, u: float, wp: Vector3, yaw: float, fwd: Vector3, w: int) -> void:
	var sack := _sacks[w]
	sack.visible = true
	var axle := wp + fwd * 0.48
	var tilt := 0.0
	match stage:
		1:
			tilt = 0.62 * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.92, 1.0, u))
		3:
			tilt = 0.55 * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.9, 1.0, u))
	var basis := Basis(Vector3.UP, yaw)
	sack.transform = Transform3D(basis * Basis(Vector3.RIGHT, tilt), axle + Vector3(0.0, 0.0, 0.0))
	# Kippen um die Achse (y = 0,13), nicht um den Boden.
	sack.position = axle + Vector3(0.0, 0.13, 0.0) - sack.basis * Vector3(0.0, 0.13, 0.0)
	var moved := axle - _sack_last[w]
	_sack_last[w] = axle
	if moved.length() < 1.0:
		for wh in _sack_wheels[w]:
			if wh != null:
				(wh as Node3D).rotate_x(-moved.dot(fwd) / 0.13)
	var n := items.size()
	var y := 0.032
	for k in n:
		var i := int(items[k])
		var e: Dictionary = plan["items"][i]
		var d: Vector3 = e["d"]
		var slot := sack.transform * Vector3(0.0, y, -0.075 - d.z * 0.5)
		var goal := (e["pos"] as Vector3) + DeliveryPlan.offset(_site)
		# Unten zuerst laden, oben zuerst abladen.
		match stage:
			0:
				var a0 := (float(k) + 0.2) / (float(n) + 0.2)
				var a1 := (float(k) + 1.0) / (float(n) + 0.2)
				var q := smoothstep(a0, a1, u)
				_put(i, _bed_pos(e).lerp(slot, q) + Vector3(0.0, sin(q * PI) * 0.22, 0.0), lerp_angle(0.0, yaw, q))
			1:
				_put(i, slot, yaw)
				_goods[i].basis = sack.basis
			2:
				# Reihenfolge wie im Plan: Das k-te Paket wird bei (0.7 + 0.85 (k+0.8)) fällig.
				var tot := 0.7 + 0.85 * float(n)
				var due := (0.7 + 0.85 * (float(k) + 0.8)) / tot
				var q2 := smoothstep(due - 0.62 * 0.85 / tot, due - 0.04, u)
				if u < due:
					_put(i, slot.lerp(goal, q2) + Vector3(0.0, sin(q2 * PI) * 0.25, 0.0), lerp_angle(yaw, 0.0, q2))
		y += d.y


func _roll_items(items: Array, plan: Dictionary, stage: int, u: float, wp: Vector3, yaw: float, fwd: Vector3) -> void:
	var i := int(items[0])
	var e: Dictionary = plan["items"][i]
	var front := wp + fwd * 0.95
	var goal := (e["pos"] as Vector3) + DeliveryPlan.offset(_site)
	match stage:
		0:
			var q := smoothstep(0.2, 0.95, u)
			_put(i, _bed_pos(e).lerp(wp + fwd * 0.75, q), 0.0)
		1:
			_put(i, front, yaw)
		2:
			if u < 0.75:
				_put(i, front.lerp(goal, smoothstep(0.0, 0.7, u)), lerp_angle(yaw, 0.0, u))


# ---------------------------------------------------------------- Hubwagen und Stapler

func _jack_job(j: Dictionary, plan: Dictionary, s: float, tier: int) -> Dictionary:
	var path: PackedVector2Array = j["path"]
	var i := int((j["items"] as Array)[0])
	var e: Dictionary = plan["items"][i]
	var rz := DeliveryPlan.rear_z(tier)
	var fl := float(DeliveryPlan.spec(tier)["floor"])
	var load_t := float(j["load"])
	var go := float(j["go"])
	var drop := float(j["drop"])
	var pos := Vector2.ZERO
	var dir := Vector2(0, -1)
	var y := 0.0
	var lift := 0.0
	var show := true
	var handle := 0.5
	var bed_z := float(DeliveryPlan.spec(tier)["axle_z"]) + (e["bed"] as Vector3).z
	if s < load_t:
		var u := s / load_t
		# Von der Ladefläche auf die Bordwand, dann hinunter.
		var inside := Vector2(0.0, bed_z + 0.66)
		var on_lift := Vector2(0.0, rz - 0.02 - 0.0)
		pos = inside.lerp(on_lift, smoothstep(0.26, 0.56, u))
		if u > 0.86:
			pos = on_lift.lerp(path[0] + Vector2(0.0, 0.0), smoothstep(0.86, 1.0, u))
		y = lerpf(0.05, fl, 1.0 - smoothstep(0.56, 0.86, u)) if u < 0.9 else lerpf(0.05, 0.0, smoothstep(0.9, 1.0, u))
		lift = smoothstep(0.05, 0.2, u)
	elif s < load_t + go:
		var u2 := (s - load_t) / go
		var r := DeliveryPlan.along(path, u2 * u2 * (3.0 - 2.0 * u2))
		pos = r[0]
		dir = r[1]
		lift = 1.0
		if u2 > 0.9:
			dir = dir.lerp(Vector2(0, -1), (u2 - 0.9) * 10.0).normalized()
	elif s < load_t + go + drop:
		var u3 := (s - load_t - go) / drop
		pos = path[path.size() - 1]
		lift = 1.0 - smoothstep(0.1, 0.6, u3)
		show = u3 < 0.75
		handle = lerpf(0.5, 0.15, smoothstep(0.0, 0.3, u3))
	else:
		var u4 := clampf((s - load_t - go - drop) / float(j["back"]), 0.0, 1.0)
		var r2 := DeliveryPlan.along(path, 1.0 - u4)
		pos = r2[0]
		dir = r2[1]
		show = false
	var fig_yaw := _yaw_to(dir)
	var wp := _world(pos, y)
	var f3 := Vector3(dir.x, 0.0, dir.y)
	if _jack != null:
		_jack.visible = true
		_jack.position = wp
		_jack.rotation.y = atan2(dir.x, dir.y)
		if _jack_handle != null:
			_jack_handle.rotation.x = -handle
	if show:
		var py := y + 0.02 + 0.06 * lift
		_put(i, wp + f3 * 0.66 + Vector3(0.0, py - y, 0.0), atan2(dir.x, dir.y), py)
	return {"pos": wp - f3 * 0.62, "yaw": fig_yaw, "pose": "push"}


func _fork_path_state(j: Dictionary, u: float) -> Array:
	var path: PackedVector2Array = j["path"]
	var r := DeliveryPlan.along(path, u)
	# Am Lkw zeigt die Gabel zum Fahrzeug (+Z), am Stellplatz zum Tor (-Z). Gedreht wird auf dem Weg nach außen.
	var side := float(j.get("side", 1.0))
	var yaw := side * PI * smoothstep(0.10, 0.62, u)
	return [r[0], yaw]


func _place_fork(pos: Vector3, yaw: float, fork_y: float) -> void:
	if _fork == null:
		return
	_fork.visible = true
	_fork.position = pos
	_fork.rotation.y = yaw
	if _fork_lift != null:
		_fork_lift.position.y = fork_y
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var moved := (pos - _fork_last)
	_fork_last = pos
	if moved.length() < 1.0:
		for wh in _fork_wheels:
			wh.rotate_x(moved.dot(fwd) / 0.30)


func _fork_driver(pos: Vector3, yaw: float) -> Dictionary:
	var b := Basis(Vector3.UP, yaw)
	# Figur schaut nach -Z, der Stapler nach +Z.
	return {"pos": pos + b * Vector3(0.12, 0.13, -0.66), "yaw": yaw + PI, "pose": "drive", "seated": true}


func _fork_home(tier: int = 3) -> Vector2:
	return Vector2(0.0, DeliveryPlan.rear_z(tier) - 2.05)


func _fork_dock() -> Vector2:
	return Vector2(0.0, DeliveryPlan.rear_z(3) - 0.60)


func _dock_machines(parked: bool, t: float, trip: String, tt: float, plan: Dictionary) -> void:
	if _jack != null:
		# Der Hubwagen wartet auf der Ladefläche ganz hinten.
		_jack.visible = parked and _door_u > 0.05
		if _jack.visible:
			var has := false
			for j in plan["jobs"]:
				if str(j["kind"]) == "jack":
					has = true
			_jack.position = _veh.transform * Vector3(0.75, float(DeliveryPlan.spec(2)["floor"]), 1.9)
			_jack.rotation.y = PI
			_jack.visible = has
	if _fork == null:
		return
	if not parked or trip == "enter" or (trip == "sign" and tt >= 2.4) or (trip == "work" and t < float(plan.get("t0", 9.0)) - 1.8):
		# Hängt am Heck, Gabel unter der Ladefläche.
		_fork.visible = true
		var dock := _veh.transform * Vector3(0.0, FORK_DOCK_Y, -float(DeliveryPlan.spec(3)["ro"]) - 0.60)
		_place_fork(dock, _veh.rotation.y, 0.06)


func _fork_board(t: float, t0: float, start: Vector2) -> Dictionary:
	# Letzte 2,6 Sekunden vor Beginn: aufsteigen, absenken, zurücksetzen.
	var board := Vector2(1.15, DeliveryPlan.rear_z(3) - 1.2)
	if t < t0 - 1.8:
		var u := smoothstep(t0 - 3.4, t0 - 1.9, t)
		return {"pos": _world(start.lerp(board, u)), "yaw": PI * 0.5 if u > 0.9 else _yaw_to(board - start), "pose": "walk"}
	return _fork_seat("undock", t - (t0 - 1.8))


func _fork_seat(mode: String, s: float, j: Dictionary = {}) -> Dictionary:
	var dock := _fork_dock()
	var home := _fork_home()
	var pos := home
	var y := 0.0
	var yaw := 0.0
	match mode:
		"undock":
			var u := clampf(s / 1.8, 0.0, 1.0)
			pos = dock.lerp(home, smoothstep(0.35, 1.0, u))
			y = FORK_DOCK_Y * (1.0 - smoothstep(0.0, 0.35, u))
		"dock":
			var u2 := clampf(s / 2.4, 0.0, 1.0)
			pos = home.lerp(dock, smoothstep(0.0, 0.6, u2))
			y = FORK_DOCK_Y * smoothstep(0.65, 1.0, u2)
	if mode == "wait" and not j.is_empty():
		pos = (j["path"] as PackedVector2Array)[0]
	var wp := _world(pos, y)
	_place_fork(wp, yaw, 0.06)
	return _fork_driver(wp, yaw)


func _fork_job(j: Dictionary, plan: Dictionary, s: float) -> Dictionary:
	var i := int((j["items"] as Array)[0])
	var e: Dictionary = plan["items"][i]
	var path: PackedVector2Array = j["path"]
	var fl := float(DeliveryPlan.spec(3)["floor"])
	var load_t := float(j["load"])
	var go := float(j["go"])
	var drop := float(j["drop"])
	var pos := path[0]
	var yaw := 0.0
	var fy := 0.10
	var show := true
	var on_fork := true
	var bed := _bed_pos(e)
	var edge := _world(Vector2(0.0, DeliveryPlan.rear_z(3) + 0.50), fl)
	if s < load_t:
		var u := s / load_t
		var reach := DeliveryPlan.rear_z(3) + 0.50 - 0.90 - path[0].y
		pos = path[0] + Vector2(0.0, reach * smoothstep(0.28, 0.48, u) * (1.0 - smoothstep(0.60, 0.80, u)))
		var top := fl + 0.02 + 0.07 * smoothstep(0.50, 0.58, u)
		fy = lerpf(0.06, top, smoothstep(0.02, 0.26, u)) if u < 0.62 else lerpf(top, 0.12, smoothstep(0.80, 1.0, u))
		on_fork = u > 0.55
		# Die Palette rutscht vorher an die Ladekante.
		if not on_fork:
			bed = bed.lerp(edge, smoothstep(0.0, 0.25, u))
	elif s < load_t + go:
		var r := _fork_path_state(j, (s - load_t) / go)
		pos = r[0]
		yaw = r[1]
		fy = 0.14
	elif s < load_t + go + drop:
		var u2 := (s - load_t - go) / drop
		pos = path[path.size() - 1]
		yaw = float(j.get("side", 1.0)) * PI
		fy = lerpf(0.14, 0.02, smoothstep(0.1, 0.6, u2))
		show = u2 < 0.75
	else:
		var u3 := clampf((s - load_t - go - drop) / float(j["back"]), 0.0, 1.0)
		var r2 := _fork_path_state(j, 1.0 - u3)
		pos = r2[0]
		yaw = r2[1]
		fy = 0.06
		show = false
	var wp := _world(pos)
	_place_fork(wp, yaw, fy)
	if show:
		if on_fork:
			var f := Vector3(sin(yaw), 0.0, cos(yaw))
			_put(i, wp + f * 0.90, yaw, fy)
		else:
			_put(i, bed, 0.0, bed.y)
	return _fork_driver(wp, yaw)


# ---------------------------------------------------------------- Spieler aus dem Weg schieben

func _push_player(pose: Dictionary, tier: int) -> void:
	var world := get_parent()
	if world == null:
		return
	var lp: Variant = world.get("local_player")
	if lp == null or not is_instance_valid(lp):
		return
	var n := lp as Node3D
	var push := DeliveryPlan.inside_vehicle(pose, tier, n.position, 0.34)
	if push != Vector2.ZERO:
		n.position += Vector3(push.x, 0.0, push.y)
