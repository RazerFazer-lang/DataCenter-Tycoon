extends Node
## Angestellte Techniker: holen defekte Server aus dem Rack, bauen und reparieren an der Werkbank
## mit denselben Handgriffen wie ein Spieler und setzen sie wieder ein. Läuft nur auf dem Host;
## Clients bekommen Ort, Tätigkeit und Text für die Figur.

signal technician_changed

const WORKER_ID := -1
const WALK_SPEED := 1.5
const HOME := Vector3(-3.35, 0.0, 3.35)
const BENCH_STAND := Vector3(-4.05, 0.0, 2.25)
const SHUTTLE := Vector3(-4.6, 0.0, -3.4)
const SHUTTLE_TIME := 12.0
const THINK_INTERVAL := 1.5
const YIELD_TIME := 12.0
const DAY_START := 6.0 / 24.0
const DAY_END := 18.0 / 24.0
const SHIFTS: Array[String] = ["day", "night"]
const DUTIES: Array[String] = ["build", "repair", "service"]
const SERVICE_BELOW := 70
const HAND_INTERVAL := 0.10

## Grundzeit je Handgriff in Sekunden.
const TASK_TIME := {
	"screw": 1.7, "unscrew": 1.3, "place": 2.3, "remove": 1.9, "plug": 1.6, "unplug": 1.1, "paste": 2.6,
	"lever": 1.1, "press": 1.0, "measure": 1.9, "wipe": 1.8, "choose": 1.6,
}

## Für alle sichtbar: {id, name, phase, from, to, dur, t0, text, carry}
var view: Dictionary = {}

var _emp_id: String = ""
var _phase: String = "idle"
var _pos: Vector3 = HOME
var _path: Array = []
var _path_dur: float = 0.0
var _wait: float = 0.0
var _think: float = 0.0
var _yield_left: float = 0.0
var _after: Callable = Callable()
var _task_id: String = ""
var _task_t: float = 0.0
var _task_dur: float = 1.0
var _hand_accum: float = 0.0
var _skips: Dictionary = {}
var _job: Dictionary = {}          # {kind, rack, slot, crate, fixed}
var _warned: Dictionary = {}
var _post_wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	multiplayer.peer_connected.connect(func(pid: int):
		if multiplayer.is_server() and not view.is_empty():
			_rpc_sync_view.rpc_id(pid, view))


func reset() -> void:
	_emp_id = ""
	_phase = "idle"
	_pos = HOME
	_path = []
	_task_id = ""
	_job = {}
	_skips = {}
	_warned = {}
	_after = Callable()
	_yield_left = 0.0
	if not view.is_empty():
		view = {}
		technician_changed.emit()


func get_worker_name() -> String:
	return str(view.get("name", tr("Techniker")))


# ------------------------------------------------------------------ Schichten und Aufgaben

func get_technicians() -> Array:
	var out: Array = []
	for e_v in FinanceManager.employees.values():
		if str((e_v as Dictionary).get("role", "")) == "technician":
			out.append(e_v)
	return out


static func shift_of(e: Dictionary) -> String:
	var s := str(e.get("shift", "day"))
	return s if SHIFTS.has(s) else "day"


static func has_duty(e: Dictionary, duty: String) -> bool:
	var d: Variant = e.get("duties", null)
	return true if not (d is Dictionary) else bool((d as Dictionary).get(duty, true))


func is_day() -> bool:
	return GameState.time_of_day >= DAY_START and GameState.time_of_day < DAY_END


## Wer gerade arbeitet: aus der laufenden Schicht die erfahrenste Person.
func pick_active() -> Dictionary:
	var want := "day" if is_day() else "night"
	var best: Dictionary = {}
	for e in get_technicians():
		if shift_of(e) == want and (best.is_empty() or int(e["skill"]) > int(best["skill"])):
			best = e
	return best


func request_set_shift(emp_id: String, shift: String) -> void:
	_rpc_req_set_shift.rpc_id(1, emp_id, shift)


func request_set_duty(emp_id: String, duty: String, on: bool) -> void:
	_rpc_req_set_duty.rpc_id(1, emp_id, duty, on)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_shift(emp_id: String, shift: String) -> void:
	if not multiplayer.is_server() or not SHIFTS.has(shift) or not FinanceManager.employees.has(emp_id):
		return
	if not SecurityGuard.check_rate_limit(_sender(), "tech_opt", 12, 5.0):
		return
	FinanceManager.employees[emp_id]["shift"] = shift
	FinanceManager.sync_employees()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_set_duty(emp_id: String, duty: String, on: bool) -> void:
	if not multiplayer.is_server() or not DUTIES.has(duty) or not FinanceManager.employees.has(emp_id):
		return
	if not SecurityGuard.check_rate_limit(_sender(), "tech_opt", 12, 5.0):
		return
	var e: Dictionary = FinanceManager.employees[emp_id]
	var d: Dictionary = e.get("duties", {}) if e.get("duties", {}) is Dictionary else {}
	d[duty] = on
	e["duties"] = d
	FinanceManager.sync_employees()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


# ------------------------------------------------------------------ Ablauf (Host)

func _process(delta: float) -> void:
	if not GameState.is_active or not NetworkManager.is_in_session or multiplayer.multiplayer_peer == null:
		if _emp_id != "" or not view.is_empty():
			reset()
		return
	if not multiplayer.is_server() or GameState.is_world_paused_for_empty_server():
		return
	# Der Techniker arbeitet immer an der großen Werkbank, egal wo der Host gerade steht.
	var prev: String = GameState.set_bench_ctx(GameState.MAIN_BENCH)
	tick(delta * DecorManager.staff_speed())
	GameState.set_bench_ctx(prev)


func tick(delta: float) -> void:
	var active := pick_active()
	var employed := _emp_id != "" and FinanceManager.employees.has(_emp_id)
	if not employed and _emp_id != "":
		_go_off_duty()
	# Schichtwechsel erst, wenn nichts in der Hand und kein Handgriff läuft.
	if _phase == "idle" and _job.is_empty() and str(active.get("id", "")) != _emp_id:
		if _emp_id != "":
			_go_off_duty()
		if not active.is_empty():
			_emp_id = str(active["id"])
			_pos = HOME
			_set_phase("idle", tr("wartet auf Arbeit"))
	if _emp_id == "":
		return
	_yield_left = maxf(0.0, _yield_left - delta)

	match _phase:
		"walk":
			_advance_walk(delta)
		"wait":
			_wait -= delta
			if _wait <= 0.0:
				_run_after()
		"work":
			_advance_work(delta)
		_:
			_think -= delta
			if _think <= 0.0:
				_think = THINK_INTERVAL
				_find_job()


func _me() -> Dictionary:
	return FinanceManager.employees.get(_emp_id, {})


func _skill() -> int:
	return clampi(int(_me().get("skill", 2)), 1, 5)


## Können in Prozent (Erfahrung 2 ≈ 62, 5 ≈ 95).
func _skill_pct() -> float:
	return 40.0 + 11.0 * float(_skill())


func _go_off_duty() -> void:
	_leave_bench()
	_drop_carried()
	_emp_id = ""
	_phase = "idle"
	_job = {}
	_path = []
	_task_id = ""
	view = {}
	_rpc_sync_view.rpc(view)


func _leave_bench() -> void:
	if GameState.get_workbench_worker() == WORKER_ID:
		GameState.set_workbench_worker(0)
		GameState.send_workbench_hand({})


func _set_phase(phase: String, text: String, path: Array = [], dur: float = 0.0) -> void:
	_phase = phase
	var carry := str(_job.get("carry", ""))
	view = {"id": _emp_id, "name": str(_me().get("name", "")), "phase": phase, "path": path, "dur": dur, "pos": _pos, "text": text, "carry": carry, "stamp": Time.get_ticks_msec()}
	_rpc_sync_view.rpc(view)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_view(data: Dictionary) -> void:
	view = data.duplicate(true)
	# Bei Clients zählt die Ankunftszeit.
	if not view.is_empty():
		view["stamp"] = Time.get_ticks_msec()
	technician_changed.emit()


func _run_after() -> void:
	var cb := _after
	_after = Callable()
	if cb.is_valid():
		cb.call()
	else:
		_set_phase("idle", tr("wartet auf Arbeit"))


# ------------------------------------------------------------------ Wege

func _walk_to(target: Vector3, text: String, after: Callable) -> void:
	_path = find_path(_pos, target)
	var length := 0.0
	for i in range(1, _path.size()):
		length += (_path[i] as Vector3).distance_to(_path[i - 1])
	_path_dur = maxf(0.2, length / WALK_SPEED)
	_wait = 0.0
	_after = after
	_set_phase("walk", text, _path, _path_dur)


func _advance_walk(delta: float) -> void:
	_wait += delta
	if _wait >= _path_dur:
		_pos = _path[_path.size() - 1] if not _path.is_empty() else _pos
		_wait = 0.0
		_phase = "idle"
		_run_after()


## Weg um Racks, Geräte und Werkbank herum (Raster 0,4 m). Ohne freien Weg geht es geradeaus.
func find_path(a: Vector3, b: Vector3) -> Array:
	const CELL := 0.4
	var grid := AStarGrid2D.new()
	var max_x := 5.0 if GameState.room_level == 0 else (11.8 if GameState.room_level == 1 else 20.8)
	var min_c := Vector2i(int(floorf(-5.0 / CELL)), int(floorf(-4.0 / CELL)))
	var max_c := Vector2i(int(ceilf(max_x / CELL)), int(ceilf(8.8 / CELL)))
	grid.region = Rect2i(min_c, max_c - min_c + Vector2i.ONE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var blocks: Array = []
	for d in [GameState.racks, GameState.ups_units, GameState.decor_items]:
		for it in (d as Dictionary).values():
			var p: Variant = (it as Dictionary).get("pos", null)
			if p is Vector3 and (p as Vector3).z > -100.0:
				blocks.append([p, 0.62])
	blocks.append([Vector3(-4.95, 0.0, 2.25), 0.70])
	blocks.append([Vector3(2.78, 0.0, -3.4), 0.95])
	for bl in blocks:
		var c: Vector3 = bl[0]
		var r: float = bl[1]
		for x in range(int(floorf((c.x - r) / CELL)), int(ceilf((c.x + r) / CELL)) + 1):
			for y in range(int(floorf((c.z - r) / CELL)), int(ceilf((c.z + r) / CELL)) + 1):
				var id := Vector2i(x, y)
				if grid.is_in_boundsv(id) and Vector2(x * CELL - c.x, y * CELL - c.z).length() < r:
					grid.set_point_solid(id, true)
	# Wand zwischen Halle und Einfahrt: nur durchs Tor.
	for x in range(min_c.x, max_c.x + 1):
		if absf(x * CELL) > 1.8:
			for y in [int(roundf(4.4 / CELL)), int(roundf(4.8 / CELL))]:
				if grid.is_in_boundsv(Vector2i(x, y)):
					grid.set_point_solid(Vector2i(x, y), true)
	var sa := Vector2i(int(roundf(a.x / CELL)), int(roundf(a.z / CELL))).clamp(min_c, max_c)
	var sb := Vector2i(int(roundf(b.x / CELL)), int(roundf(b.z / CELL))).clamp(min_c, max_c)
	grid.set_point_solid(sa, false)
	grid.set_point_solid(sb, false)
	var out: Array = [a]
	for id in grid.get_id_path(sa, sb, true):
		out.append(Vector3(id.x * CELL, 0.0, id.y * CELL))
	out.append(b)
	return out


func _rack_front(rack_id: String) -> Vector3:
	var r: Dictionary = GameState.racks[rack_id]
	var p: Vector3 = r.get("pos", Vector3.ZERO)
	return p + Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, float(r.get("rot_y", 0.0))) * 1.05


func _is_remote(p: Vector3) -> bool:
	return p.z < -100.0


## Zu einem Ort gehen; nach Halle Nord fährt das Shuttle.
func _travel(target: Vector3, text: String, after: Callable) -> void:
	if not _is_remote(target):
		_walk_to(target, text, after)
		return
	_walk_to(SHUTTLE, text, func():
		_after = after
		_wait = SHUTTLE_TIME
		_set_phase("wait", tr("mit dem Shuttle nach Halle Nord")))
	# Während der Fahrt ist die Figur nicht zu sehen (Phase "wait" mit Text).


# ------------------------------------------------------------------ Arbeit finden

func _idle(text: String) -> void:
	if _pos.distance_to(HOME) > 0.4:
		_walk_to(HOME, text, func(): _set_phase("idle", text))
	elif str(view.get("text", "")) != text or _phase != "idle":
		_set_phase("idle", text)


func _find_job() -> void:
	if _yield_left > 0.0:
		return
	var e := _me()
	var worker := GameState.get_workbench_worker()
	if worker > 0:
		_idle(tr("wartet, bis die Werkbank frei ist"))
		return
	var mode := str(GameState.workbench_state.get("mode", ""))
	if mode == "ready_tray":
		if _try_install_from_bench():
			return
		_idle(tr("wartet auf Arbeit"))
		return
	if mode == "build_box" and has_duty(e, "build"):
		_walk_to(BENCH_STAND, tr("packt den Bausatz aus"), func():
			GameState.server_workbench_unpack()
			_start_bench_work())
		return
	if GameState.is_workbench_job():
		var duty := "build" if mode == "assembly" else mode
		if has_duty(e, duty):
			var block := _bench_block_reason()
			if block != "":
				_warn_once("bench", block)
				_idle(block)
				return
			_walk_to(BENCH_STAND, tr("geht zur Werkbank"), _start_bench_work)
			return
		_idle(tr("wartet auf Arbeit"))
		return
	if mode != "":
		_idle(tr("wartet auf Arbeit"))
		return
	# Werkbank frei: eigene Kiste zurückholen, defekte Server, Bausätze, Überholungen.
	if _try_own_crate() or (has_duty(e, "repair") and _try_fetch_crashed()) or (has_duty(e, "build") and _try_build_box()) or (has_duty(e, "service") and _try_fetch_service()):
		return
	_idle(tr("wartet auf Arbeit"))


## Fehlt etwas, damit die Arbeit an der Werkbank weitergehen kann?
func _bench_block_reason() -> String:
	var plan := AssemblyPlan.build(GameState.workbench_state)
	var done := AssemblyPlan.sanitize_done(plan, GameState.get_workbench_done())
	var needs_screw := false
	var needs_paste := false
	for t in plan["tasks"]:
		if not done.has(t["id"]):
			if str(t["kind"]) == "screw" and not bool(((plan["items"] as Dictionary).get(t["item"], {}) as Dictionary).get("captive", false)):
				needs_screw = true
			elif str(t["kind"]) == "paste":
				needs_paste = true
	if needs_screw and GameState.bench_screws <= 0 and str(plan["mode"]) != "service":
		return tr("braucht Schrauben")
	if needs_paste and GameState.bench_paste < AssemblyPlan.PASTE_MIN:
		return tr("braucht Wärmeleitpaste")
	if GameState.needs_workbench_replacement() and choose_spare("cpu") == "":
		return tr("braucht eine neue CPU")
	if str(plan["mode"]) == "repair" and not bool(GameState.workbench_state.get("kit_used", false)):
		var has_spare := GameState.is_workbench_spare_ready() if done.has("choose") else choose_spare(str(plan["repair_cat"])) != ""
		if not has_spare:
			return tr("braucht Ersatzteil: %s") % _part_label(str(GameState.workbench_state.get("faulty_part", "")))
	return ""


func _part_label(cat: String) -> String:
	return GameState.get_component_label(cat if cat != "" else "mainboard")


func _warn_once(key: String, text: String) -> void:
	if str(_warned.get(key, "")) == text:
		return
	_warned[key] = text
	GameState.post_event_f("🧑‍🔧 %s %s.", [get_worker_name(), text], "warn")


## Ersatzteil wählen: Kit, sonst ein gleichwertiges oder das schwächste Teil aus dem Lager. "" = nichts da.
func choose_spare(rcat: String, kit_cat: String = "") -> String:
	if kit_cat == "":
		kit_cat = GameState.get_workbench_kit_cat() if GameState.is_workbench_job() else rcat
	if GameState.count_repair_kits(kit_cat) > 0:
		return AssemblyPlan.SPARE_KIT
	if not AssemblyPlan.accepts_parts(rcat):
		return ""
	for pd_v in HardwareCatalog.get_category_parts(rcat):
		var pd: Dictionary = pd_v
		if rcat == "gpu" and int(pd.get("vtier", 0)) <= 0:
			continue
		if int(GameState.parts_inventory.get(str(pd["id"]), 0)) > 0:
			return str(pd["id"])
	return ""


func _try_own_crate() -> bool:
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if bool(c.get("tech", false)) and int(c.get("held_by", 0)) == 0:
			_job = {"kind": "crate", "crate": cid}
			_walk_to(_stand_near(c.get("pos", Vector3.ZERO)), tr("holt den Server"), _pick_crate_to_bench)
			return true
	return false


func _stand_near(p: Vector3) -> Vector3:
	return p + Vector3(0.0, 0.0, -0.6 if p.z > 5.0 else 0.6)


func _try_build_box() -> bool:
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if str(c.get("item_type", "")) == "slot_build_box" and int(c.get("held_by", 0)) == 0:
			var p: Vector3 = c.get("pos", Vector3.ZERO)
			if _is_remote(p):
				continue
			_job = {"kind": "crate", "crate": cid}
			_walk_to(_stand_near(p), tr("holt einen Bausatz"), _pick_crate_to_bench)
			return true
	return false


func _pick_crate_to_bench() -> void:
	var cid := str(_job.get("crate", ""))
	if not GameState.crates.has(cid) or int(GameState.crates[cid].get("held_by", 0)) != 0:
		_job = {}
		_set_phase("idle", tr("wartet auf Arbeit"))
		return
	GameState.server_hold_crate(cid, WORKER_ID)
	_job["carry"] = cid
	_walk_to(BENCH_STAND, tr("trägt den Server zur Werkbank"), _put_crate_on_bench)


func _put_crate_on_bench() -> void:
	var cid := str(_job.get("carry", ""))
	if not GameState.server_place_on_bench(cid):
		_drop_carried()
		_job = {}
		_yield_left = YIELD_TIME
		_set_phase("idle", tr("wartet, bis die Werkbank frei ist"))
		return
	_job = {}
	if str(GameState.workbench_state.get("mode", "")) == "build_box":
		GameState.server_workbench_unpack()
	if str(GameState.workbench_state.get("mode", "")) == "ready_tray" and GameState.can_workbench_service():
		GameState.server_workbench_service()
	_start_bench_work()


func _try_fetch_crashed() -> bool:
	for rid in GameState.racks.keys():
		var slots: Array = GameState.racks[rid].get("slots", [])
		for i in range(slots.size()):
			var s: Dictionary = slots[i]
			if str(s.get("item_type", "")) == "" or str(s.get("state", "")) != "crashed":
				continue
			var wb := {"mode": "repair", "mainboard_id": s["item_type"], "components": s.get("components", {}), "faulty_part": s.get("faulty_part", "")}
			var rcat := AssemblyPlan.repair_cat(wb)
			var kit_cat := str(s.get("faulty_part", ""))
			if choose_spare(rcat, kit_cat if kit_cat != "" else "mainboard") == "":
				_warn_once("%s:%d" % [rid, i], tr("kann %s Slot %d nicht reparieren, Ersatzteil fehlt: %s") % [GameState.get_rack_display_name(rid), i + 1, _part_label(kit_cat)])
				continue
			_fetch(rid, i, tr("holt einen defekten Server"))
			return true
	return false


## Überholen nur, wenn das Rack gerade niemandem vermietet ist.
func _try_fetch_service() -> bool:
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		if not (r.get("services", []) as Array).is_empty():
			continue
		var slots: Array = r.get("slots", [])
		for i in range(slots.size()):
			var s: Dictionary = slots[i]
			if str(s.get("item_type", "")) != "" and str(s.get("state", "")) == "ok" and GameState.get_build_quality(s) < SERVICE_BELOW \
					and AssemblyPlan.can_service({"mainboard_id": s["item_type"], "components": s.get("components", {})}):
				_fetch(rid, i, tr("holt einen Server zum Überholen"))
				return true
	return false


func _fetch(rack_id: String, slot_idx: int, text: String) -> void:
	_job = {"kind": "fetch", "rack": rack_id, "slot": slot_idx}
	_travel(_rack_front(rack_id), text, func():
		var cid := GameState.server_take_tray(rack_id, slot_idx, WORKER_ID)
		if cid == "":
			_job = {}
			_set_phase("idle", tr("wartet auf Arbeit"))
			return
		GameState.crates[cid]["tech"] = true
		_job["carry"] = cid
		var back := func(): _walk_to(BENCH_STAND, tr("trägt den Server zur Werkbank"), _put_crate_on_bench)
		if _is_remote(_rack_front(rack_id)):
			_after = back
			_wait = SHUTTLE_TIME
			_set_phase("wait", tr("mit dem Shuttle zurück"))
		else:
			back.call())


func _try_install_from_bench() -> bool:
	var wb := GameState.workbench_state
	var rid := str(wb.get("rack_id", ""))
	var idx := int(wb.get("slot_idx", 0))
	if not GameState.racks.has(rid):
		return false
	var slots: Array = GameState.racks[rid].get("slots", [])
	if idx < 0 or idx >= slots.size() or str((slots[idx] as Dictionary).get("item_type", "")) != "":
		return false
	_job = {"kind": "install", "rack": rid, "slot": idx}
	_walk_to(BENCH_STAND, tr("holt den fertigen Server"), func():
		var cid := GameState.server_take_from_bench(WORKER_ID)
		if cid == "":
			_job = {}
			_set_phase("idle", tr("wartet auf Arbeit"))
			return
		GameState.crates[cid]["tech"] = true
		_job["carry"] = cid
		_travel(_rack_front(rid), tr("setzt den Server ein"), func():
			if not GameState.server_put_tray(cid, rid, idx, get_worker_name()):
				_drop_carried()
			_job = {}
			_set_phase("idle", tr("wartet auf Arbeit"))))
	return true


func _drop_carried() -> void:
	var cid := str(_job.get("carry", ""))
	if cid != "" and GameState.crates.has(cid) and int(GameState.crates[cid].get("held_by", 0)) == WORKER_ID:
		GameState.server_drop_crate(cid, _pos)
	_job.erase("carry")


# ------------------------------------------------------------------ An der Werkbank

func _start_bench_work() -> void:
	if not GameState.is_workbench_job() or GameState.get_workbench_worker() > 0:
		_yield_left = YIELD_TIME
		_set_phase("idle", tr("wartet, bis die Werkbank frei ist"))
		return
	GameState.set_workbench_worker(WORKER_ID)
	_skips = {}
	_task_id = ""
	_post_wait = 0.0
	_set_phase("work", _work_text())


func _work_text() -> String:
	match str(GameState.workbench_state.get("mode", "")):
		"assembly":
			return tr("baut %s zusammen") % str(GameState.workbench_state.get("label", "Server"))
		"service":
			return tr("überholt %s") % str(GameState.workbench_state.get("label", "Server"))
	return tr("repariert %s") % str(GameState.workbench_state.get("label", "Server"))


func _advance_work(delta: float) -> void:
	if GameState.get_workbench_worker() != WORKER_ID:
		# Ein Spieler hat übernommen oder die Arbeit ist fertig.
		_task_id = ""
		_job = {}
		if GameState.get_workbench_worker() > 0:
			_yield_left = YIELD_TIME
		_think = 0.4
		_set_phase("idle", tr("wartet auf Arbeit"))
		return
	_post_wait = maxf(0.0, _post_wait - delta)
	if _task_id == "":
		if _post_wait <= 0.0:
			_next_task()
		return
	_task_t += delta
	_hand_accum += delta
	if _hand_accum >= HAND_INTERVAL:
		_hand_accum = 0.0
		GameState.send_workbench_hand({"auto": true, "task": _task_id, "t": clampf(_task_t / _task_dur, 0.0, 1.0)})
	if _task_t >= _task_dur:
		_finish_task()


func _next_task() -> void:
	var plan := AssemblyPlan.build(GameState.workbench_state)
	var done := AssemblyPlan.sanitize_done(plan, GameState.get_workbench_done())
	var block := _bench_block_reason()
	if block != "" and not _can_go_on(plan, done):
		_warn_once("bench", block)
		_leave_bench()
		_yield_left = 8.0
		_set_phase("idle", block)
		return
	var pick: Dictionary = {}
	for t in plan["tasks"]:
		var id := str(t["id"])
		if bool(t["optional"]) or _skips.has(id) or not AssemblyPlan.is_available(plan, done, id):
			continue
		# Niemand vom Personal fasst einen Server unter Strom an.
		if AssemblyPlan.is_live_risk(t, done):
			continue
		# Wer wenig Erfahrung hat, übersieht manchmal eine Schraube.
		if bool(t["soft"]) and str(t["kind"]) == "screw" and _rng.randf() < (100.0 - _skill_pct()) * 0.0016:
			_skips[id] = true
			continue
		pick = t
		break
	if pick.is_empty():
		_leave_bench()
		_yield_left = 8.0
		_set_phase("idle", tr("kommt nicht weiter"))
		return
	_task_id = str(pick["id"])
	_task_t = 0.0
	var base := float(TASK_TIME.get(str(pick["kind"]), 1.5)) * (1.40 - 0.13 * float(_skill()))
	_task_dur = maxf(0.25, base * GameState.get_tool_time_mult(str(pick["kind"])))


## Es fehlt zwar etwas, aber bis dahin gibt es noch zu tun.
func _can_go_on(plan: Dictionary, done: Dictionary) -> bool:
	var nt := AssemblyPlan.next_task(plan, done)
	if nt.is_empty() or str(nt["kind"]) in ["choose", "screw", "paste"] or bool(nt["kit"]) or str(nt["id"]) == "cpu_place":
		return false
	return true


func _finish_task() -> void:
	var id := _task_id
	_task_id = ""
	var plan := AssemblyPlan.build(GameState.workbench_state)
	if not (plan["by_id"] as Dictionary).has(id):
		return
	var task: Dictionary = plan["by_id"][id]
	if str(task["kind"]) == "choose" or (id == "cpu_place" and GameState.needs_workbench_replacement()):
		GameState.server_workbench_choose(WORKER_ID, choose_spare(str(plan["repair_cat"]) if str(plan["mode"]) == "repair" else "cpu"))
		return
	var err := (100.0 - _skill_pct()) / 100.0
	var amount := 1.0
	match str(task["kind"]):
		"screw":
			amount = clampf(1.06 + _rng.randfn(0.0, err * 0.30), AssemblyPlan.SCREW_MIN, 1.5)
			if GameState.has_bench_tool("torque"):
				amount = 1.05
		"paste":
			amount = clampf(0.95 + _rng.randfn(0.0, err * 0.45), AssemblyPlan.PASTE_MIN, AssemblyPlan.PASTE_MAX)
			if GameState.has_bench_tool("paste_gun"):
				amount = 0.95
	var ok := GameState.server_workbench_task(WORKER_ID, id, amount)
	if not ok:
		_post_wait = 1.0
	if id == "power_on" or id == "test_on":
		_post_wait = 2.8
	if str(GameState.workbench_state.get("mode", "")) == "ready_tray":
		_on_job_done()


func _on_job_done() -> void:
	GameState.send_workbench_hand({})
	var e := _me()
	if not e.is_empty():
		e["work_done"] = int(e.get("work_done", 0)) + 1
		FinanceManager.sync_employees()
	_warned.erase("bench")
	_job = {}
	_think = 0.3
	_set_phase("idle", tr("ist fertig"))
