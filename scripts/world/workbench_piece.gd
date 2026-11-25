class_name WorkbenchPiece
extends Node3D
## Der Server auf der Werkbank mit allen einzeln greifbaren Teilen, Schrauben, Hebeln und Kabeln.
## Zeigt für alle Spieler denselben Stand (workbench_state.done) und wird vom Spieler an der
## Werkbank über WorkbenchUI bewegt. Koordinaten: Ursprung = Oberkante der ESD-Matte.

const S := 0.72
const CHASSIS_POS := Vector3(0.0, 0.0, 0.02)
const TRAY_POS := Vector3(0.56, 0.026, 0.22)
const TOOL_TRAY_POS := Vector3(-0.385, 0.0, 0.17)
const MOVE_TIME := 0.32
const LIFT := 0.07
const SCREW_OUT := 0.0085

const TOOL_NODES := {
	AssemblyPlan.TOOL_DRIVER: ["Screwdriver", -0.045],
	AssemblyPlan.TOOL_PASTE: ["Syringe", 0.0],
	AssemblyPlan.TOOL_TWEEZERS: ["Tweezers", 0.045],
	AssemblyPlan.TOOL_METER: ["Probes", -0.110],
}
## Gekauftes Werkzeug tauscht das Modell in der Schale.
const TOOL_UPGRADES := {AssemblyPlan.TOOL_DRIVER: ["akku", "PowerDriver"], AssemblyPlan.TOOL_PASTE: ["paste_gun", "PasteGun"]}
const METER_POS := Vector3(-0.585, 0.0, 0.335)
## Bildschirm des Prüfgeräts (Oszilloskop links auf der Werkbank).
const SCREEN_POS := Vector3(-0.58, 0.116, -0.0075)
const POST_TIME := 2.3
const POST_RUN := ["19", "31", "4F", "60", "72", "92"]

static var _mat_cache: Dictionary = {}
static var _mat_sources_done: Dictionary = {}


class Item:
	var id: String
	var spec: Dictionary
	var node: Node3D
	var seat: Transform3D          # Sitz relativ zum Eltern-Teil
	var node_local: Transform3D    # Lage des Blender-Objekts in seinem Bauteil
	var state: String = ""
	var cur: Transform3D
	var from: Transform3D
	var t: float = 1.0
	var held: bool = false
	var hold_xf: Transform3D
	var progress: float = -1.0     # >= 0: Schraube dreht gerade, Hebel bewegt sich
	var aabb: AABB
	var amount: float = 0.0
	var cable: MeshInstance3D


## Zu welcher Werkbank dieses Werkstück gehört.
var bench_id: String = "wb_main"
var plan: Dictionary = {}
var done: Dictionary = {}
var items: Dictionary = {}
var tools: Dictionary = {}
var held_tool: String = ""
var tool_xf: Transform3D
var tool_active: bool = false

var _order: Array = []
var _pending: Dictionary = {}      # task_id -> {t, v}: lokal erledigt, vom Host noch nicht bestätigt
var _job_key: String = ""
var _turn_over: Dictionary = {}   # job_key -> Vierteldrehungen der CPU
var _shell: Node3D
var _ghost: Node3D
var _ghost_item: String = ""
var _highlight: StandardMaterial3D
var _highlighted: Array = []
var _cable_mat: StandardMaterial3D
var _moving: bool = true
var _pulse: float = 0.0
var _fans: Array = []            # [{node, owner}]
var last_reading: Dictionary = {}
## Inhalt des Prüfgerät-Bildschirms für die Anzeige am Arbeitsplatz.
var screen_info: Dictionary = {}
var _powered: bool = false
var _power_time: float = 0.0
var _beeps_left: int = -1
var _beep_wait: float = 0.0
var _fan_speed: float = 0.0
var _screen: Node3D
var _scr_code: Label3D
var _scr_msg: Label3D
var _scr_leds: Dictionary = {}
var _meter_lbl: Label3D
var _meter_node: Node3D
var _probe_cable: MeshInstance3D
var _status_led: MeshInstance3D
var _led_mat: StandardMaterial3D
var _fan_audio: AudioStreamPlayer3D
var _beep_audio: AudioStreamPlayer3D
var _points_shown: bool = false


func _ready() -> void:
	_highlight = StandardMaterial3D.new()
	_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight.albedo_color = Color(0.30, 0.75, 1.0, 0.2)
	_cable_mat = StandardMaterial3D.new()
	_cable_mat.albedo_color = Color(0.055, 0.058, 0.066)
	_cable_mat.roughness = 0.72


func is_empty() -> bool:
	return items.is_empty()


# ------------------------------------------------------------------ Aufbau

func sync_from_state(wb: Dictionary) -> void:
	var key := "%s|%s|%s|%s|%s" % [str(wb.get("mode", "")), str(wb.get("label", "")), str(wb.get("mainboard_id", "")), str(wb.get("faulty_part", "")), str(wb.get("components", {}))] \
		+ "|%s|%s|%s" % [str(AssemblyPlan.spare_of(wb)), str(wb.get("fault_hidden", false)), str(wb.get("diagnosed", false))] + str(wb.get("broken", []))
	if key != _job_key:
		_job_key = key
		_build(wb)
	_apply_done(AssemblyPlan.sanitize_done(plan, wb.get("done", {})))


func clear() -> void:
	_job_key = ""
	_free_all()
	plan = {}
	done = {}


func _free_all() -> void:
	clear_ghost()
	for c in get_children():
		c.queue_free()
	items.clear()
	_order.clear()
	tools.clear()
	_pending.clear()
	_highlighted.clear()
	_fans.clear()
	held_tool = ""
	tool_active = false
	_screen = null
	_meter_node = null
	_probe_cable = null
	_status_led = null
	_fan_audio = null
	_beep_audio = null
	_points_shown = false


func _build(wb: Dictionary) -> void:
	_free_all()
	plan = AssemblyPlan.build(wb)
	done = AssemblyPlan.sanitize_done(plan, wb.get("done", {}))
	var chassis := str(plan["variant"]["chassis"])
	_shell = HardwareMeshFactory.build_chassis_shell(chassis, wb.get("components", {}) as Dictionary)
	_shell.transform = _chassis_xf()
	add_child(_shell)

	var models: Dictionary = {}
	for id in (plan["items"] as Dictionary).keys():
		_create_item(plan["items"][id], models)
	for m in models.values():
		(m as Node).queue_free()
	_build_tools()
	_build_diag()

	var st := AssemblyPlan.states(plan, done)
	for id in _order:
		var it: Item = items[id]
		it.state = str(st[id])
		if it.spec["kind"] == "paste" and it.state == "on":
			it.amount = float(done.get("paste", 1.0))
	last_reading = AssemblyPlan.reading(plan, str(plan["repair_cat"])) if done.has("meas_" + str(plan["repair_cat"])) else {}
	_powered = AssemblyPlan.is_powered(done)
	_power_time = POST_TIME + 1.0 if _powered else 0.0
	_beeps_left = -1
	update_poses(0.0)
	_refresh_visibility()
	_update_screen()


func _chassis_xf() -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(S, S, S)), CHASSIS_POS)


func _create_item(spec: Dictionary, models: Dictionary) -> void:
	var it := Item.new()
	it.id = str(spec["id"])
	it.spec = spec
	it.node = Node3D.new()
	it.node.name = it.id
	add_child(it.node)
	it.node_local = Transform3D.IDENTITY

	var model := str(spec["model"])
	if model.begins_with("#"):
		_add_assembly_model(it, model)
	elif spec["kind"] == "paste":
		it.node.add_child(_make_paste_mesh())
	elif spec["kind"] == "point":
		it.node.add_child(_make_point_mesh())
	else:
		var src := _get_model(model, models)
		var mesh := _find_node(src, str(spec["node"]))
		if mesh != null:
			it.node_local = Transform3D(Basis.IDENTITY, mesh.position)
			_add_mesh_copy(it.node, mesh, Transform3D.IDENTITY, model)
			if spec.has("rotors"):
				for c in src.get_children():
					if c is MeshInstance3D and str(c.name).begins_with("Rotor_X"):
						var rot := _add_mesh_copy(it.node, c as MeshInstance3D, Transform3D(Basis.IDENTITY, (c as Node3D).position - mesh.position), model)
						rot.set_meta("spin_axis", "x")
						_fans.append({"node": rot, "owner": it.id})
		else:
			# Modell fehlt: einfacher Platzhalter, damit die Arbeit trotzdem weitergeht.
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.02, 0.05)
			b.mesh = bm
			b.position.y = 0.01
			it.node.add_child(b)

	it.seat = Transform3D(spec.get("rot", Basis.IDENTITY) as Basis, spec["base"] as Vector3) * it.node_local
	if str(spec.get("parent_space", "")) == "mb":
		# Gefangene Schrauben hängen am Kühler, sind im Modell aber im selben Raum wie er.
		var owner_item: Item = items[str(spec["parent"])]
		it.seat = owner_item.seat.affine_inverse() * it.seat
	it.aabb = _node_aabb(it.node, Transform3D.IDENTITY)
	items[it.id] = it
	_order.append(it.id)


func _add_assembly_model(it: Item, model: String) -> void:
	var tier := int(it.spec.get("tier", 0))
	var m: Node3D
	var rotors: Array = []
	match model:
		"#cooling":
			m = PartModels.mount(str(it.spec.get("pid", "")), rotors)
			if m == null:
				m = HardwareMeshFactory.build_cooling_wall(tier, rotors)
		"#cooling_broken":
			m = HardwareMeshFactory.build_cooling_wall(0, rotors, true)
		"#psu":
			m = PartModels.mount(str(it.spec.get("pid", "")))
			if m == null:
				m = HardwareMeshFactory.build_psu_unit(tier)
		_:
			m = HardwareMeshFactory.build_psu_unit(0, true)
	it.node.add_child(m)
	for r in rotors:
		_fans.append({"node": r, "owner": it.id})
	if model.begins_with("#psu"):
		# Die festen Kabel ersetzt die Werkbank durch bewegliche.
		for c in m.find_children("Cable_*", "", true, false):
			(c as Node3D).visible = false
		var tmp: Dictionary = {}
		var br := _find_node(_get_model("asm_tools", tmp), "PsuBracket")
		if br != null:
			_add_mesh_copy(it.node, br, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.0006, float(it.spec["front"]) + 0.0115)), "asm_tools")
		for x in tmp.values():
			(x as Node).queue_free()


func _get_model(model: String, models: Dictionary) -> Node3D:
	if models.has(model):
		return models[model]
	var inst := ModelLoader.instantiate_custom_model(model) if ModelLoader.has_custom_model(model) else null
	if inst == null:
		inst = Node3D.new()
	models[model] = inst
	return inst


static func _find_node(root: Node, node_name: String) -> MeshInstance3D:
	if root is MeshInstance3D and str(root.name) == node_name:
		return root as MeshInstance3D
	for c in root.get_children():
		var r := _find_node(c, node_name)
		if r != null:
			return r
	return null


func _add_mesh_copy(parent: Node3D, src: MeshInstance3D, xf: Transform3D, model: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.transform = xf
	if src.mesh != null:
		for s in range(src.mesh.get_surface_count()):
			var m := src.mesh.surface_get_material(s)
			if m != null:
				var shared := _shared_material(m.resource_name, model)
				if shared != null:
					mi.set_surface_override_material(s, shared)
	parent.add_child(mi)
	return mi


## asm_*.glb haben keine Texturen. Die fertigen Materialien liegen in den part_*.glb.
static func _shared_material(mat_name: String, model: String) -> Material:
	if not mat_name.begins_with("PBR_"):
		return null
	if model.begins_with("hwm_"):
		return PartModels.pbr(mat_name)
	if _mat_cache.has(mat_name):
		return _mat_cache[mat_name]
	var sources: Array[String] = [model.replace("asm_", "part_"), "part_cpu_t1", "part_psu_t0", "part_ram_t1", "part_gpu_t2", "part_mainboard"]
	for src in sources:
		if _mat_sources_done.has(src):
			continue
		_mat_sources_done[src] = true
		if not ModelLoader.has_custom_model(src):
			continue
		var inst := ModelLoader.instantiate_custom_model(src)
		if inst == null:
			continue
		_collect_materials(inst)
		inst.queue_free()
		if _mat_cache.has(mat_name):
			return _mat_cache[mat_name]
	return null


static func _collect_materials(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh := (n as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(s)
			if m != null and not m.resource_name.is_empty() and not _mat_cache.has(m.resource_name):
				_mat_cache[m.resource_name] = m
	for c in n.get_children():
		_collect_materials(c)


func _make_paste_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 20
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.63, 0.65)
	m.roughness = 0.34
	m.metallic = 0.25
	mi.material_override = m
	return mi


func _build_tools() -> void:
	var models: Dictionary = {}
	var src := _get_model("asm_tools", models)
	var tray := _find_node(src, "ToolTray")
	if tray != null:
		var t := _add_mesh_copy(self, tray, Transform3D(Basis.IDENTITY, TOOL_TRAY_POS), "asm_tools")
		t.name = "ToolTray"
	# Ein paar lose Schrauben in der Magnetschale
	var screw := _find_node(src, "ScrewM3")
	if screw != null:
		for k in range(9):
			var a := float(k) * 2.4
			var rr := 0.007 + 0.0032 * float(k)
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(82.0 + 9.0 * sin(a)))
			var sm := _add_mesh_copy(self, screw, Transform3D(b.scaled(Vector3.ONE * S), Vector3(TRAY_POS.x + cos(a) * rr, 0.0245, TRAY_POS.z + sin(a) * rr)), "asm_tools")
			sm.name = "TrayScrew%d" % k
	for tool_id in TOOL_NODES.keys():
		var n := Node3D.new()
		n.name = "Tool_" + str(tool_id)
		add_child(n)
		tools[tool_id] = n
		n.transform = tool_rest_xf(tool_id)
	for m in models.values():
		(m as Node).queue_free()
	refresh_tools()


func refresh_tools() -> void:
	if tools.is_empty():
		return
	var models: Dictionary = {}
	var src := _get_model("asm_tools", models)
	for tool_id in tools.keys():
		var node_name := str(TOOL_NODES[tool_id][0])
		if TOOL_UPGRADES.has(tool_id) and GameState.has_bench_tool(str(TOOL_UPGRADES[tool_id][0])):
			node_name = str(TOOL_UPGRADES[tool_id][1])
		var n: Node3D = tools[tool_id]
		if str(n.get_meta("model", "")) == node_name:
			continue
		n.set_meta("model", node_name)
		for c in n.get_children():
			c.queue_free()
		var mesh := _find_node(src, node_name)
		if mesh != null:
			_add_mesh_copy(n, mesh, Transform3D.IDENTITY, "asm_tools")
	for m in models.values():
		(m as Node).queue_free()
	_moving = true


func _make_point_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.0060
	tm.outer_radius = 0.0090
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.albedo_color = Color(0.35, 0.80, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _label(parent: Node3D, pos: Vector3, size: int, col: Color, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.0005
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = align
	l.position = pos
	parent.add_child(l)
	return l


## Prüfgerät-Bildschirm, Messgerät, Status-LED und Töne.
func _build_diag() -> void:
	_screen = Node3D.new()
	_screen.position = SCREEN_POS
	add_child(_screen)
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.206, 0.102)
	bg.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.015, 0.035, 0.040)
	bg.material_override = bm
	_screen.add_child(bg)
	_scr_code = _label(_screen, Vector3(0.0, 0.020, 0.0015), 104, Color(0.40, 1.0, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_scr_msg = _label(_screen, Vector3(0.0, -0.038, 0.0015), 25, Color(0.80, 0.92, 0.90), HORIZONTAL_ALIGNMENT_CENTER)
	_scr_leds.clear()
	var names := ["CPU", "DRAM", "VGA", "BOOT"]
	for i in range(names.size()):
		_scr_leds[names[i]] = _label(_screen, Vector3(-0.072 + 0.048 * float(i), -0.016, 0.0015), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

	var models: Dictionary = {}
	var src := _get_model("asm_tools", models)
	_meter_node = Node3D.new()
	_meter_node.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(14.0)), METER_POS)
	add_child(_meter_node)
	var body := _find_node(src, "Multimeter")
	if body != null:
		_add_mesh_copy(_meter_node, body, Transform3D.IDENTITY, "asm_tools")
	for m in models.values():
		(m as Node).queue_free()
	_meter_lbl = _label(_meter_node, Vector3(0.0, 0.0336, -0.044), 44, Color(0.05, 0.08, 0.06), HORIZONTAL_ALIGNMENT_CENTER)
	_meter_lbl.rotation_degrees.x = -90.0
	_probe_cable = MeshInstance3D.new()
	_probe_cable.mesh = ArrayMesh.new()
	_probe_cable.material_override = _cable_mat
	add_child(_probe_cable)

	_status_led = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0035
	sm.height = 0.0070
	_status_led.mesh = sm
	_led_mat = StandardMaterial3D.new()
	_led_mat.emission_enabled = true
	_status_led.material_override = _led_mat
	_status_led.position = _chassis_xf() * (AssemblyPlan.BUTTON_POS + Vector3(0.0, 0.030, 0.003))
	add_child(_status_led)

	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.stream = SfxManager.get_loop_stream("server_fan")
	_fan_audio.volume_db = -60.0
	_fan_audio.max_distance = 9.0
	_fan_audio.unit_size = 1.4
	add_child(_fan_audio)
	_beep_audio = AudioStreamPlayer3D.new()
	_beep_audio.stream = SfxManager.get_sound_stream("post_beep")
	_beep_audio.max_distance = 12.0
	_beep_audio.unit_size = 2.0
	add_child(_beep_audio)


## Anzeige des laufenden Einschaltens: {ok, code, msg, leds}
func run_result() -> Dictionary:
	if is_fault_run():
		var p: Dictionary = AssemblyPlan.POST.get(str(plan["repair_cat"]), AssemblyPlan.POST["mainboard"])
		return {"ok": false, "code": p["code"], "msg": p["msg"], "leds": p["leds"], "kind": "", "beeps": p["beeps"]}
	var t: Variant = (GameState.bench_states.get(bench_id, {}) as Dictionary).get("test", {})
	if t is Dictionary and not (t as Dictionary).is_empty():
		var d: Dictionary = (t as Dictionary).duplicate()
		d["beeps"] = 1 if bool(d.get("ok", true)) else 4
		return d
	return {"ok": true, "code": "AA", "msg": "System bereit – alles in Ordnung", "leds": [], "kind": "", "beeps": 1}


## Läuft der Server gerade mit dem Defekt (Fehlersuche) oder schon repariert (Testlauf)?
func is_fault_run() -> bool:
	return done.has("power_on") and not done.has("power_off")


func is_post_finished() -> bool:
	return _powered and _power_time >= POST_TIME


func suspects() -> Array:
	if not is_fault_run() or not is_post_finished():
		return []
	var sus: Array = (AssemblyPlan.POST.get(str(plan["repair_cat"]), AssemblyPlan.POST["mainboard"]) as Dictionary)["suspects"]
	# Das Profi-Multimeter schließt einen Teil der Verdächtigen gleich aus.
	return sus.slice(0, 2) if GameState.has_bench_tool("meter_pro") else sus


func _update_diag(delta: float) -> void:
	if _screen == null:
		return
	var on := AssemblyPlan.is_powered(done)
	if on != _powered:
		_powered = on
		_power_time = 0.0
		_beeps_left = -1
		_update_screen()
	var rcat := str(plan.get("repair_cat", ""))
	var res := run_result()
	var dead := _powered and str(res["code"]) == "--" and not bool(res["ok"])
	var no_pwm := items.has("plug_pwm") and (items["plug_pwm"] as Item).state != "plugged"
	if _powered:
		var before := _power_time
		_power_time += delta
		if before < POST_TIME and _power_time >= POST_TIME:
			_beeps_left = int(res["beeps"])
			_beep_wait = 0.0
		if _power_time < POST_TIME + 0.2:
			_update_screen()
	if _beeps_left > 0 and _beep_audio != null:
		_beep_wait -= delta
		if _beep_wait <= 0.0:
			_beep_wait = 0.30
			_beeps_left -= 1
			_beep_audio.pitch_scale = 1.0
			_beep_audio.volume_db = -6.0 + linear_to_db(maxf(0.001, SettingsManager.get_effective_sfx_gain()))
			_beep_audio.play()

	# Lüfter: ein totes Netzteil lässt sie nur kurz zucken, eine defekte Lüfterwand steht still.
	var want := 1.0 if _powered else 0.0
	if dead:
		want = 0.25 if fmod(_power_time, 1.6) < 0.25 else 0.0
	_fan_speed = move_toward(_fan_speed, want, delta * (0.9 if want > _fan_speed else 0.45))
	if _fan_speed > 0.001:
		for f in _fans:
			var n: Node3D = f["node"]
			if not is_instance_valid(n) or (str(f["owner"]) == "wall_old" and rcat == "cooling"):
				continue
			if no_pwm and str(f["owner"]).begins_with("wall"):
				continue
			var it: Item = items.get(str(f["owner"]))
			if it == null or it.state != "seat":
				continue
			if str(n.get_meta("spin_axis", "z")) == "x":
				n.rotate_object_local(Vector3.RIGHT, delta * 34.0 * _fan_speed)
			else:
				n.rotate_object_local(Vector3.BACK, delta * 34.0 * _fan_speed)
	if _fan_audio != null and _fan_audio.stream != null:
		if _fan_speed > 0.02:
			if not _fan_audio.playing:
				_fan_audio.play()
			_fan_audio.pitch_scale = 0.55 + 0.50 * _fan_speed
			_fan_audio.volume_db = linear_to_db(maxf(0.001, _fan_speed * 0.45 * SettingsManager.get_effective_sfx_gain()))
		elif _fan_audio.playing:
			_fan_audio.stop()

	var led := Color(0.05, 0.05, 0.05)
	if _powered:
		if not is_post_finished():
			led = Color(0.9, 0.9, 0.9)
		elif not bool(res["ok"]):
			led = Color(1.0, 0.45, 0.05) if fmod(_power_time, 0.8) < 0.4 else Color(0.15, 0.06, 0.0)
			if dead:
				led = Color(0.6, 0.1, 0.05) if fmod(_power_time, 1.6) < 0.2 else Color(0.05, 0.05, 0.05)
		else:
			led = Color(0.2, 1.0, 0.35)
	_led_mat.albedo_color = led
	_led_mat.emission = led
	_led_mat.emission_energy_multiplier = 2.2 if _powered else 0.0
	_update_probe_cable()


func _update_screen() -> void:
	if _screen == null:
		return
	var res := run_result()
	_screen.visible = str(plan["variant"]["chassis"]) != "net_switch"
	var cable := items.has("plug_diag") and (items["plug_diag"] as Item).state == "plugged"
	var code := ""
	var msg := tr("Prüfkabel anstecken")
	var on_leds: Array = []
	var col := Color(0.40, 1.0, 0.55)
	if cable:
		msg = tr("Verbunden – Server einschalten")
		code = "- -"
	if _powered:
		if not is_post_finished():
			code = POST_RUN[int(_power_time * 5.0) % POST_RUN.size()]
			msg = tr("POST läuft…")
			on_leds = [["CPU", "DRAM", "VGA", "BOOT"][mini(3, int(_power_time / POST_TIME * 4.0))]]
			col = Color(0.90, 0.95, 0.70)
		else:
			code = str(res["code"])
			msg = tr(str(res["msg"]))
			on_leds = res["leds"]
			if not bool(res["ok"]):
				col = Color(1.0, 0.42, 0.30)
	_scr_code.text = code
	_scr_code.modulate = col
	_scr_msg.text = msg
	for k in _scr_leds.keys():
		var l: Label3D = _scr_leds[k]
		l.text = "%s" % k
		l.modulate = Color(1.0, 0.35, 0.25) if on_leds.has(k) else (Color(0.30, 0.85, 0.45) if (_powered and is_post_finished() and bool(res["ok"])) else Color(0.22, 0.30, 0.30))
	screen_info = {"cable": cable, "code": code, "msg": msg, "color": col, "leds": on_leds}
	if _meter_lbl != null:
		_meter_lbl.text = str(last_reading.get("text", "0,00 V"))


func _update_probe_cable() -> void:
	if _probe_cable == null or not tools.has(AssemblyPlan.TOOL_METER):
		return
	var probes: Node3D = tools[AssemblyPlan.TOOL_METER]
	var sig := str(probes.transform.origin.snapped(Vector3.ONE * 0.001)) + str(probes.transform.basis.y.snapped(Vector3.ONE * 0.02))
	if str(_probe_cable.get_meta("sig", "")) == sig:
		return
	_probe_cable.set_meta("sig", sig)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var a: Vector3 = _meter_node.transform * Vector3(0.018 * s, 0.036, 0.060)
		var b: Vector3 = probes.transform * Vector3(0.031 * s, 0.114, 0.0)
		var up: Vector3 = probes.transform.basis.y
		_append_tube(st, a, a + Vector3(0.0, 0.05, 0.03), b + up * 0.09, b, 0.0019)
	st.generate_normals()
	_probe_cable.mesh = st.commit()


## Leuchtringe an den Messpunkten: Verdächtige laut POST-Code heben sich ab, Gemessenes wird grün/rot.
func show_points(active: bool) -> void:
	var can := active and is_fault_run()
	var sus := suspects()
	for id in _order:
		var it: Item = items[id]
		if it.spec["kind"] != "point":
			continue
		it.node.visible = can
		if not can:
			continue
		var cat := str(it.spec["cat"])
		var col := Color(0.35, 0.75, 1.0)
		if done.has("meas_" + cat):
			var r := AssemblyPlan.reading(plan, cat)
			col = Color(0.35, 0.95, 0.45) if bool(r["ok"]) else (Color(0.95, 0.75, 0.25) if bool(r["weak"]) else Color(1.0, 0.28, 0.20))
		elif sus.has(cat):
			col = Color(1.0, 0.80, 0.25)
		var mi := it.node.get_child(0) as MeshInstance3D
		(mi.material_override as StandardMaterial3D).albedo_color = col
		mi.scale = Vector3.ONE * (1.0 + (0.18 * sin(_pulse * 5.0) if not done.has("meas_" + cat) else 0.0))
	_points_shown = can


func tool_rest_xf(tool_id: String) -> Transform3D:
	if tool_id == AssemblyPlan.TOOL_METER:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(-8.0)) * Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(-0.500, 0.007, 0.270))
	# Liegt flach im Einsatz, Spitze zeigt zum Server nach hinten.
	var x := float(TOOL_NODES[tool_id][1])
	var b := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	return Transform3D(b, TOOL_TRAY_POS + Vector3(x, 0.020, -0.095))


static func _node_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
		out = xf * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D:
			if not (c as Node3D).visible:
				continue
			var sub := _node_aabb(c, xf * (c as Node3D).transform)
			if sub.size != Vector3.ZERO:
				out = sub if first else out.merge(sub)
				first = false
	return out


# ------------------------------------------------------------------ Zustand

func _apply_done(server_done: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	for k in _pending.keys():
		if server_done.has(k) or now - int(_pending[k]["t"]) > 1500:
			_pending.erase(k)
	var merged := server_done.duplicate()
	for k in _pending.keys():
		merged[k] = _pending[k]["v"]
	# Nur behalten, was nach dem Stand des Hosts auch möglich ist.
	_set_done(AssemblyPlan.sanitize_done(plan, merged))


## Sofortige Anzeige beim Spieler, der arbeitet; der Host bestätigt kurz danach.
func local_done(task_id: String, amount: float) -> void:
	_pending[task_id] = {"t": Time.get_ticks_msec(), "v": amount}
	var merged := done.duplicate()
	merged[task_id] = amount
	_set_done(merged)


## Der Host hat abgelehnt: dieser und alle darauf wartenden Handgriffe gelten nicht.
func reject(task_id: String) -> void:
	_pending.erase(task_id)


func _set_done(new_done: Dictionary) -> void:
	for k in new_done.keys():
		if not done.has(k) and str(k).begins_with("meas_"):
			last_reading = AssemblyPlan.reading(plan, str(k).substr(5))
	done = new_done
	var st := AssemblyPlan.states(plan, done)
	for id in _order:
		var it: Item = items[id]
		var ns := str(st[id])
		if it.spec["kind"] == "paste":
			it.amount = float(done.get("paste", 1.0)) if (ns == "on" and not (done.has("wipe") and not done.has("paste"))) else (it.amount if it.progress >= 0.0 else 0.0)
		if ns != it.state:
			it.from = it.cur
			it.t = 0.0
			it.state = ns
			it.held = false
			it.progress = -1.0
	_moving = true
	_refresh_visibility()
	_update_screen()


func _kit_available() -> bool:
	var prev: String = GameState.set_bench_ctx(bench_id)
	var ok: bool = GameState.is_workbench_spare_ready()
	GameState.set_bench_ctx(prev)
	return ok


func _refresh_visibility() -> void:
	var kit := str(plan.get("mode", "")) != "repair" or _kit_available()
	for id in _order:
		var it: Item = items[id]
		var vis := true
		match str(it.spec["kind"]):
			"screw":
				# Gelöste Schrauben liegen in der Magnetschale; gefangene bleiben am Kühler.
				vis = it.state != "out" or bool(it.spec.get("captive", false)) or it.t < 1.0 or it.progress >= 0.0
			"paste":
				vis = it.amount > 0.01
			"plug":
				vis = _plug_owner_ready(it)
			"point":
				vis = _points_shown
		if bool(it.spec.get("spare", false)) and it.state == "rest" and not kit and not it.held:
			vis = false
		if bool(it.spec.get("captive", false)):
			vis = vis and (items[str(it.spec["parent"])] as Item).node.visible
		it.node.visible = vis
		if it.cable != null:
			it.cable.visible = vis


func _plug_owner_ready(it: Item) -> bool:
	if (it.spec["owners"] as Array).is_empty():
		return true
	for o in it.spec["owners"]:
		if items.has(o) and (items[o] as Item).state == "seat":
			return true
	return false


# ------------------------------------------------------------------ Posen

func _resolve_parent(parent: String) -> String:
	if parent == "mb" and items.has("mb_old") and (items["mb_old"] as Item).state == "seat":
		return "mb_old"
	return parent


func _parent_space(it: Item) -> Transform3D:
	var parent := _resolve_parent(str(it.spec["parent"]))
	if parent == "chassis":
		return _chassis_xf()
	if not items.has(parent):
		return _chassis_xf()
	var p: Item = items[parent]
	if bool(p.spec.get("board", false)):
		return p.cur * p.node_local.affine_inverse()
	return p.cur


func seat_xf(it: Item) -> Transform3D:
	if it.spec.has("alt_base"):
		var when: Item = items.get(str(it.spec["alt_when"]))
		if when != null and (when.state == "seat" or when.held):
			return _parent_space(it) * Transform3D(Basis.IDENTITY, it.spec["alt_base"] as Vector3) * it.node_local
	return _parent_space(it) * it.seat


func _target_xf(it: Item) -> Transform3D:
	var base := seat_xf(it)
	match it.state:
		"rest":
			return rest_xf(it, false)
		"defect":
			return rest_xf(it, true)
		"tray":
			return Transform3D(Basis.IDENTITY.scaled(Vector3(S, S, S)), TRAY_POS + Vector3(0.012 * float(int(it.spec.get("n", 0)) - 1), 0.0, 0.010))
		"out":
			if bool(it.spec.get("captive", false)):
				return base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.004, 0.0))
			return Transform3D(Basis.IDENTITY.scaled(Vector3(S, S, S)), TRAY_POS)
		"set":
			return base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.004, 0.0))
		"open":
			return base * Transform3D(Basis(it.spec["axis"] as Vector3, deg_to_rad(float(it.spec["angle"]))), Vector3.ZERO)
		"unplugged":
			return loose_plug_xf(it)
	return base


func loose_plug_xf(it: Item) -> Transform3D:
	if it.spec.has("loose_abs"):
		return Transform3D((Basis(Vector3.UP, 0.35) * Basis(Vector3.BACK, deg_to_rad(90.0))).scaled(Vector3.ONE * S), it.spec["loose_abs"] as Vector3)
	return _chassis_xf() * Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, deg_to_rad(76.0)), it.spec["loose"] as Vector3)


## Ablage neben dem Gehäuse. Neue Teile und ausgebaute defekte liegen getrennt.
func rest_xf(it: Item, defect: bool) -> Transform3D:
	var sc := Vector3(S, S, S)
	var id := it.id
	var n := int(it.spec.get("n", 0))
	var rot := Basis.IDENTITY
	var pos := Vector3(0.45, 0.004, 0.10)
	var flat := Basis(Vector3(0, 0, 1), deg_to_rad(90.0))
	if id == "lid":
		rot = Basis(Vector3(0, 0, 1), deg_to_rad(80.0))
		pos = Vector3(0.765, 0.272, 0.0)
	elif id == "mb" and str(plan["variant"]["chassis"]) != "net_switch":
		rot = Basis(Vector3.RIGHT, deg_to_rad(79.0))
		pos = Vector3(0.0, 0.178, -0.305)
	elif bool(it.spec.get("board", false)):
		pos = Vector3(0.53, 0.008, -0.05) if defect else Vector3(0.0, 0.178, -0.305)
		if not defect:
			rot = Basis(Vector3.RIGHT, deg_to_rad(79.0))
		else:
			rot = Basis(Vector3.UP, deg_to_rad(6.0))
	elif id.begins_with("psu"):
		pos = Vector3(0.40, 0.002, -0.11) if not defect else Vector3(0.40, 0.002, 0.20)
	elif id.begins_with("gpu"):
		rot = flat
		pos = Vector3(0.575 + 0.085 * float(n), 0.006, -0.12) if not defect else Vector3(0.70 - 0.090 * float(n), 0.006, 0.07)
	elif id == "bridge":
		pos = Vector3(0.50, 0.002, 0.04)
	elif id.begins_with("cpu"):
		if not defect:
			rot = Basis(Vector3.UP, cpu_turns() * PI * 0.5)
		pos = Vector3(0.39, 0.002, 0.13) if not defect else Vector3(0.39, 0.002, -0.10)
	elif id.begins_with("cooler"):
		pos = Vector3(0.475, 0.002, 0.13) if not defect else Vector3(0.50, 0.002, -0.10)
	elif id.begins_with("stick"):
		rot = flat
		var slot := float(n)
		pos = Vector3(0.375 + slot * 0.036, 0.003, 0.330) if not defect else Vector3(0.40 + slot * 0.040, 0.003, -0.02)
	elif id.begins_with("ssd"):
		pos = Vector3(0.675, 0.002, 0.10 + 0.028 * float(n)) if not defect else Vector3(0.45, 0.002, -0.05 + 0.030 * float(n))
	elif id.begins_with("wall"):
		pos = Vector3(0.0, 0.002, 0.368)
		if defect:
			rot = Basis(Vector3.UP, deg_to_rad(90.0))
			pos = Vector3(0.45, 0.002, -0.06)
	return Transform3D(rot.scaled_local(sc) if rot != Basis.IDENTITY else Basis.IDENTITY.scaled(sc), pos)


func _process(delta: float) -> void:
	_pulse += delta
	if _highlight != null:
		_highlight.albedo_color.a = 0.04 + 0.13 * absf(sin(_pulse * 3.2))
	if items.is_empty():
		return
	if _moving or tool_active:
		update_poses(delta)
	_update_diag(delta)


func update_poses(delta: float) -> void:
	var busy := false
	for id in _order:
		var it: Item = items[id]
		if it.held:
			it.cur = it.cur.interpolate_with(it.hold_xf, clampf(delta * 18.0, 0.0, 1.0)) if delta > 0.0 else it.hold_xf
			busy = true
		else:
			var tgt := _target_xf(it)
			if it.progress >= 0.0:
				tgt = _progress_xf(it, tgt)
				it.t = 1.0
				busy = true
			if it.t < 1.0:
				busy = true
				var fast := str(it.spec["kind"]) in ["lever", "latch", "paste"]
				it.t = minf(1.0, it.t + delta / (0.18 if fast else MOVE_TIME))
				var e := it.t * it.t * (3.0 - 2.0 * it.t)
				it.cur = it.from.interpolate_with(tgt, e)
				if not fast and (it.from.origin - tgt.origin).length() > 0.10:
					it.cur.origin.y += sin(e * PI) * LIFT
				if it.t >= 1.0:
					_refresh_visibility.call_deferred()
			else:
				it.cur = tgt
		it.node.transform = it.cur
		match str(it.spec["kind"]):
			"paste":
				var a := clampf(it.amount, 0.0, AssemblyPlan.PASTE_MAX)
				var r := 0.010 + 0.030 * a
				it.node.transform = it.cur * Transform3D(Basis.IDENTITY.scaled(Vector3(r, 0.0016 + 0.0034 * a, r)), Vector3.ZERO)
				it.node.visible = a > 0.01
			"plug":
				_update_cable(it)
	for tool_id in tools.keys():
		var n: Node3D = tools[tool_id]
		if tool_id == held_tool and tool_active:
			n.transform = n.transform.interpolate_with(tool_xf, clampf(delta * 22.0, 0.0, 1.0)) if delta > 0.0 else tool_xf
			busy = true
		else:
			var rest := tool_rest_xf(tool_id)
			if not n.transform.origin.is_equal_approx(rest.origin):
				n.transform = n.transform.interpolate_with(rest, clampf(delta * 14.0, 0.0, 1.0))
				if n.transform.origin.distance_to(rest.origin) < 0.001:
					n.transform = rest
				busy = true
	_moving = busy


func wake() -> void:
	_moving = true


## Schraube dreht sich rein bzw. raus, Hebel folgt dem Finger, Teil wird herausgezogen.
func _progress_xf(it: Item, tgt: Transform3D) -> Transform3D:
	var p := clampf(it.progress, 0.0, 1.0)
	var seat := seat_xf(it)
	match str(it.spec["kind"]):
		"screw":
			var inward := it.state != "in"
			var depth := (1.0 - p) if inward else p
			var travel := 0.004 if bool(it.spec.get("captive", false)) else SCREW_OUT
			return seat * Transform3D(Basis(Vector3.UP, -p * TAU * 5.0 * (1.0 if inward else -1.0)), Vector3(0.0, depth * travel, 0.0))
		"lever", "latch":
			var ang := deg_to_rad(float(it.spec["angle"]))
			var k := p if it.state != "open" else 1.0 - p
			return seat * Transform3D(Basis(it.spec["axis"] as Vector3, ang * k), Vector3.ZERO)
		"plug":
			return tgt * Transform3D(Basis.IDENTITY, Vector3(0.0, p * 0.010, 0.0))
		"button":
			return seat * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.0016 * sin(minf(p, 1.0) * PI), 0.0))
		"part":
			return tgt * Transform3D(Basis(Vector3.RIGHT, sin(p * 26.0) * 0.010 * (1.0 - p)), Vector3(0.0, p * 0.020, 0.0))
	return tgt


func set_progress(item_id: String, p: float) -> void:
	if items.has(item_id):
		var it: Item = items[item_id]
		var was := it.progress
		it.progress = p
		if p < 0.0 and was >= 0.0:
			it.from = it.cur
			it.t = 0.4
		_moving = true
		if (was < 0.0) != (p < 0.0):
			_refresh_visibility()


## Die neue CPU liegt zufällig gedreht bereit (0 = richtig herum).
func cpu_turns() -> int:
	return int(_turn_over.get(_job_key, 1 + absi(hash(_job_key)) % 3))


## Merkt sich, wie herum der Spieler die CPU abgelegt hat.
func set_cpu_turns(turns: int) -> void:
	_turn_over = {_job_key: posmod(turns, 4)}


## Dreht ein abgelegtes Teil sichtbar in seine neue Lage.
func respin_item(item_id: String) -> void:
	if items.has(item_id):
		var it: Item = items[item_id]
		it.from = it.cur
		it.t = 0.0
		_moving = true


func wipe_paste(t: float) -> void:
	if items.has("paste"):
		(items["paste"] as Item).amount = clampf(1.0 - t, 0.0, 1.0)
		_moving = true


func set_paste(amount: float) -> void:
	if items.has("paste"):
		var it: Item = items["paste"]
		it.amount = amount
		it.progress = 0.0 if amount > 0.0 and it.state == "off" else -1.0
		_moving = true


func hold_item(item_id: String, xf: Transform3D) -> void:
	if items.has(item_id):
		var it: Item = items[item_id]
		it.held = true
		it.progress = -1.0
		it.hold_xf = xf
		it.node.visible = true
		_moving = true


func release_item(item_id: String) -> void:
	if items.has(item_id):
		var it: Item = items[item_id]
		if it.held:
			it.held = false
			it.from = it.cur
			it.t = 0.0
			_moving = true


# ------------------------------------------------------------------ Kabel

func _update_cable(it: Item) -> void:
	if not it.node.visible:
		if it.cable != null:
			it.cable.visible = false
		return
	if it.cable == null:
		it.cable = MeshInstance3D.new()
		it.cable.mesh = ArrayMesh.new()
		it.cable.material_override = _cable_mat
		it.cable.name = it.id + "_cable"
		add_child(it.cable)
		it.cable.set_meta("sig", "")
	it.cable.visible = true
	var ch := _chassis_xf()
	var a: Vector3 = it.spec["from_abs"] if it.spec.has("from_abs") else ch * (it.spec["from"] as Vector3)
	var plug_h := it.aabb.size.y
	var up := it.cur.basis.y.normalized()
	var b: Vector3 = it.cur * Vector3(0.0, plug_h, 0.0)
	var sig := "%s|%s" % [str(b.snapped(Vector3.ONE * 0.0005)), str(up.snapped(Vector3.ONE * 0.01))]
	if it.cable.get_meta("sig") == sig:
		return
	it.cable.set_meta("sig", sig)
	var radius := float(it.spec.get("radius", 0.003)) * S
	var strands := int(it.spec.get("strands", 2))
	var spread := float(it.spec.get("spread", 0.006)) * S
	var arc := float(it.spec.get("arc", 0.045)) * S
	var side := it.cur.basis.z.normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(strands):
		var k := (float(s) / float(maxi(1, strands - 1)) - 0.5) if strands > 1 else 0.0
		var pa := a + Vector3(float(s % 2) * radius * 2.2, float(s / 2 % 3) * radius * 2.1, 0.0)
		var pb := b + side * (k * spread)
		var c1 := pa + Vector3(0.0, arc * 0.35, 0.055 * S)
		var c2 := pb + up * arc + Vector3(0.0, 0.004 * float(s % 2), 0.0)
		# Eingesteckte Kabel bleiben unter dem Deckel.
		if it.state == "plugged":
			var roof := CHASSIS_POS.y + (AssemblyPlan.LID_POS.y - 0.004) * S
			c1.y = minf(c1.y, roof)
			c2.y = minf(c2.y, roof)
		_append_tube(st, pa, c1, c2, pb, radius)
	st.generate_normals()
	it.cable.mesh = st.commit()


static func _append_tube(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, r: float) -> void:
	const SEG := 14
	const SIDES := 6
	var rings: Array = []
	var prev_n := Vector3.ZERO
	for i in range(SEG + 1):
		var t := float(i) / float(SEG)
		var p := p0.bezier_interpolate(p1, p2, p3, t)
		var tan := p0.bezier_derivative(p1, p2, p3, t)
		tan = tan.normalized() if tan.length_squared() > 1e-10 else Vector3.UP
		var n := prev_n
		if i == 0:
			n = tan.cross(Vector3.RIGHT if absf(tan.x) < 0.9 else Vector3.UP).normalized()
		else:
			n = (n - tan * n.dot(tan)).normalized()
		prev_n = n
		var bn := tan.cross(n)
		var ring: Array[Vector3] = []
		for k in range(SIDES):
			var a := TAU * float(k) / float(SIDES)
			ring.append(p + (n * cos(a) + bn * sin(a)) * r)
		rings.append(ring)
	for i in range(SEG):
		for k in range(SIDES):
			var kn := (k + 1) % SIDES
			st.set_smooth_group(0)
			for v in [rings[i][k], rings[i + 1][k], rings[i][kn], rings[i][kn], rings[i + 1][k], rings[i + 1][kn]]:
				st.add_vertex(v)


# ------------------------------------------------------------------ Auswahl & Hinweise

## Punkt zum Anvisieren (Schraubenkopf, Hebelgriff, CPU-Mitte, Steckeroberseite).
func anchor_of(item_id: String) -> Vector3:
	if not items.has(item_id):
		return Vector3.ZERO
	var it: Item = items[item_id]
	match str(it.spec["kind"]):
		"screw":
			if it.state == "tray":
				return it.cur.origin
			return seat_xf(it) * Vector3(0.0, it.aabb.end.y, 0.0)
		"paste", "point":
			return seat_xf(it).origin
	return it.cur * it.aabb.get_center()


func ray_hits_item(item_id: String, from_local: Vector3, dir_local: Vector3, grow: float = 0.004) -> float:
	var it: Item = items[item_id]
	if not it.node.visible:
		return -1.0
	var inv := it.cur.affine_inverse()
	var o := inv * from_local
	var d := inv.basis * dir_local
	var box := it.aabb.grow(grow)
	var hit: Variant = box.intersects_ray(o, d)
	if hit == null:
		return -1.0
	return (it.cur * (hit as Vector3)).distance_to(from_local)


## Ray gegen ein abgelegtes Werkzeug; liefert dessen ID.
func ray_hits_tool(from_local: Vector3, dir_local: Vector3) -> String:
	if held_tool != AssemblyPlan.TOOL_METER and _meter_node != null:
		var mi := _meter_node.transform.affine_inverse()
		if AABB(Vector3(-0.042, 0.0, -0.080), Vector3(0.084, 0.040, 0.160)).intersects_ray(mi * from_local, mi.basis * dir_local) != null:
			return AssemblyPlan.TOOL_METER
	for tool_id in tools.keys():
		if tool_id == held_tool:
			continue
		var n: Node3D = tools[tool_id]
		var inv := n.transform.affine_inverse()
		var box := _node_aabb(n, Transform3D.IDENTITY).grow(0.010)
		if box.intersects_ray(inv * from_local, inv.basis * dir_local) != null:
			return tool_id
	return ""


func set_highlight(ids: Array) -> void:
	if ids == _highlighted:
		return
	for id in _highlighted:
		if items.has(id):
			_set_overlay((items[id] as Item).node, null)
	_highlighted = ids.duplicate()
	for id in _highlighted:
		if items.has(id):
			_set_overlay((items[id] as Item).node, _highlight)


func set_highlight_color(c: Color) -> void:
	_highlight.albedo_color = Color(c.r, c.g, c.b, _highlight.albedo_color.a)


static func _set_overlay(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = mat
	for c in n.get_children():
		_set_overlay(c, mat)


## Durchsichtige Vorschau am Einbauort, solange ein Teil in der Hand ist.
func show_ghost(item_id: String) -> void:
	if _ghost_item == item_id and is_instance_valid(_ghost):
		_ghost.transform = seat_xf(items[item_id])
		return
	clear_ghost()
	if not items.has(item_id):
		return
	var it: Item = items[item_id]
	_ghost = it.node.duplicate() as Node3D
	_ghost.visible = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.85, 1.0, 0.16)
	_set_override(_ghost, m)
	add_child(_ghost)
	_ghost.transform = seat_xf(it)
	_ghost_item = item_id


func clear_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_item = ""


static func _set_override(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_overlay = null
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_override(c, mat)


# ------------------------------------------------------------------ Mitspieler schaut zu

var _remote_item: String = ""
var _remote_task: String = ""


func apply_remote_hand(data: Dictionary) -> void:
	if items.is_empty():
		return
	if bool(data.get("auto", false)):
		data = _auto_hand(str(data.get("task", "")), float(data.get("t", 0.0)))
	var item_id := str(data.get("item", ""))
	var task_id := str(data.get("task", ""))
	if _remote_item != "" and _remote_item != item_id:
		release_item(_remote_item)
	if _remote_task != "" and _remote_task != task_id:
		_clear_remote_progress()
	_remote_item = item_id
	_remote_task = task_id
	held_tool = str(data.get("tool", ""))
	tool_active = held_tool != "" and tools.has(held_tool)
	var xf: Transform3D = data.get("xf", Transform3D.IDENTITY)
	if item_id != "" and items.has(item_id):
		hold_item(item_id, xf)
	elif tool_active:
		tool_xf = xf
	if task_id != "" and (plan["by_id"] as Dictionary).has(task_id) and not done.has(task_id):
		var task: Dictionary = plan["by_id"][task_id]
		if str(task["kind"]) == "paste":
			set_paste(float(data.get("t", 0.0)))
		elif items.has(str(task["item"])):
			set_progress(str(task["item"]), float(data.get("t", 0.0)))
	_moving = true


## Techniker: Bewegung aus Handgriff und Fortschritt selbst berechnen.
func _auto_hand(task_id: String, t: float) -> Dictionary:
	var out := {"tool": "", "item": "", "xf": Transform3D.IDENTITY, "task": "", "t": t}
	if not (plan.get("by_id", {}) as Dictionary).has(task_id) or done.has(task_id):
		return out
	var task: Dictionary = plan["by_id"][task_id]
	var item_id := str(task["item"])
	if not items.has(item_id):
		return out
	var it: Item = items[item_id]
	out["tool"] = str(task["tool"])
	var kind := str(task["kind"])
	if kind in ["place", "plug", "remove"]:
		var a := _target_xf(it)
		var b := seat_xf(it) if kind != "remove" else rest_xf(it, true)
		var e := t * t * (3.0 - 2.0 * t)
		var xf := a.interpolate_with(b, e)
		xf.origin.y += sin(e * PI) * 0.12
		out["item"] = item_id
		out["xf"] = xf
	else:
		out["task"] = task_id
		if kind == "paste":
			out["t"] = t * 0.95
		out["xf"] = Transform3D(Basis(Vector3.UP, -t * TAU * 4.0) if kind in ["screw", "unscrew"] else Basis(Vector3(0, 0, 1), deg_to_rad(-14.0)), anchor_of(item_id))
	return out


func _clear_remote_progress() -> void:
	if (plan.get("by_id", {}) as Dictionary).has(_remote_task):
		var task: Dictionary = plan["by_id"][_remote_task]
		if str(task["kind"]) != "paste":
			set_progress(str(task["item"]), -1.0)


func stop_remote_hand() -> void:
	if _remote_item != "":
		release_item(_remote_item)
	if _remote_task != "":
		_clear_remote_progress()
	_remote_item = ""
	_remote_task = ""
	held_tool = ""
	tool_active = false
	_moving = true
