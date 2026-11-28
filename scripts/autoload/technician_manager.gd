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
## Haltestelle in Halle Nord (vor dem Shuttle-Kiosk), relativ zu GameState.HALLE_NORD_ORIGIN.
const NORD_STOP := Vector3(-5.4, 0.0, 5.4)
const SHUTTLE_TIME := 12.0
## Wie lange ein Auftrag liegen bleibt, wenn der Techniker nicht hinkommt.
const BLOCKED_MS := 60000
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
var _unreachable: Dictionary = {}  # Kiste/Rack -> Zeitpunkt, bis zu dem es liegen bleibt
var _unreachable_why: Dictionary = {}  # Kiste/Rack -> was der Techniker vorhatte
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
	_unreachable = {}
	_unreachable_why = {}
	_outdoor_read = false
	_outdoor_cells = []
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


## Liegengebliebene Aufträge sofort wieder versuchen (Knopf im Personal-Fenster).
func request_retry_blocked() -> void:
	_rpc_req_retry_blocked.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_retry_blocked() -> void:
	if not multiplayer.is_server() or _unreachable.is_empty():
		return
	if not SecurityGuard.check_rate_limit(_sender(), "tech_opt", 12, 5.0):
		return
	_unreachable = {}
	_unreachable_why = {}
	_yield_left = 0.0
	_think = 0.0
	_warned.erase("noway")
	_send_blocked()


## Nur die Liste der liegengebliebenen Aufträge neu verteilen (ohne den Laufweg neu zu starten).
func _send_blocked() -> void:
	if view.is_empty():
		return
	view["blocked"] = _blocked_list()
	_rpc_sync_blocked.rpc(view["blocked"])


@rpc("authority", "call_local", "reliable")
func _rpc_sync_blocked(list: Array) -> void:
	if view.is_empty():
		return
	view["blocked"] = list
	view["blocked_stamp"] = Time.get_ticks_msec()
	technician_changed.emit()


## [[Bezeichnung, Sekunden bis zum nächsten Versuch, Grund], …]
func _blocked_list() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for id in _unreachable.keys():
		var left := int(_unreachable[id]) - now
		if left <= 0:
			_unreachable.erase(id)
			_unreachable_why.erase(id)
			continue
		out.append([_blocked_label(str(id)), int(ceilf(float(left) / 1000.0)), str(_unreachable_why.get(id, ""))])
	return out


func _blocked_label(id: String) -> String:
	if GameState.racks.has(id):
		var p: Vector3 = GameState.racks[id].get("pos", Vector3.ZERO)
		return GameState.get_rack_display_name(id) + (" (%s)" % tr("Halle Nord") if _is_remote(p) else "")
	if GameState.crates.has(id):
		var c: Dictionary = GameState.crates[id]
		var p2: Vector3 = c.get("pos", Vector3.ZERO)
		return GameState.get_crate_display_label(c) + (" (%s)" % tr("Halle Nord") if _is_remote(p2) else "")
	return id


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
	view = {"id": _emp_id, "name": str(_me().get("name", "")), "phase": phase, "path": path, "dur": dur, "pos": _pos, "text": text, "carry": carry,
		"blocked": _blocked_list(), "stamp": Time.get_ticks_msec()}
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

## Zu einem Ort laufen. Liegt er am anderen Standort, fährt das Shuttle. Ohne Weg: if_no_way, sonst _no_way.
func _walk_to(target: Vector3, text: String, after: Callable, if_no_way: Callable = Callable()) -> void:
	if _is_remote(target) != _is_remote(_pos):
		_ride(target, text, after)
		return
	var way := find_path(_pos, target)
	if way.is_empty():
		if if_no_way.is_valid():
			if_no_way.call()
		else:
			_no_way(text)
		return
	_path = way
	_use_back_door(way)
	var length := 0.0
	for i in range(1, _path.size()):
		length += (_path[i] as Vector3).distance_to(_path[i - 1])
	_path_dur = maxf(0.2, length / WALK_SPEED)
	_wait = 0.0
	_after = after
	_set_phase("walk", text, _path, _path_dur)


## Kein Weg dorthin (Tor zu, Ware hinter dem Zaun): Auftrag liegen lassen und später wieder versuchen.
func _no_way(why: String = "") -> void:
	for k in ["crate", "rack"]:
		if str(_job.get(k, "")) != "":
			_unreachable[str(_job[k])] = Time.get_ticks_msec() + BLOCKED_MS
			_unreachable_why[str(_job[k])] = why
	_drop_carried()
	_job = {}
	_yield_left = 3.0
	_warn_once("noway", tr("kommt nicht an die Ware. Ist das Garagentor zu?"))
	_set_phase("idle", tr("wartet, der Weg ist versperrt"))


func _is_unreachable(id: String) -> bool:
	return Time.get_ticks_msec() < int(_unreachable.get(id, 0))


## Führt der Weg durch die Hintertür, macht der Techniker sie auf.
func _use_back_door(way: Array) -> void:
	if bool(OutdoorManager.state.get("door", false)):
		return
	for p in way:
		if BACK_DOOR.has_point(Vector2((p as Vector3).x, (p as Vector3).z)):
			OutdoorManager.state["door"] = true
			OutdoorManager.broadcast()
			GameState._rpc_play_sfx.rpc("van_door")
			return


func _advance_walk(delta: float) -> void:
	_wait += delta
	if _wait >= _path_dur:
		_pos = _path[_path.size() - 1] if not _path.is_empty() else _pos
		_wait = 0.0
		_phase = "idle"
		_run_after()


const CELL := 0.4
const BODY_R := 0.24
## Durchgänge in den Außenwänden: Garagentor und Hintertür (Rasterzellen dürfen dort frei sein).
const GATE_HALF_X := 1.9
const BACK_DOOR := Rect2(-6.3, 3.4, 1.4, 0.5)

## Weg um Wände, Racks, Geräte und Einrichtung herum (Raster 0,4 m, ganzes Grundstück).
## Wände und ein geschlossenes Tor sind immer dicht. Ist der Weg nur zugestellt, zwängt sich der
## Techniker zwischen den Möbeln durch. Leer heißt: dort kommt man nicht hin.
func find_path(a: Vector3, b: Vector3) -> Array:
	if _is_remote(a) != _is_remote(b):
		return [] # Zwischen den Standorten fährt das Shuttle (siehe _ride).
	for with_things in [true, false]:
		var grid := _build_nord_grid(with_things) if _is_remote(a) else _build_grid(with_things)
		var sa := _free_cell(grid, a)
		var sb := _free_cell(grid, b)
		if sa == Vector2i.MAX or sb == Vector2i.MAX:
			continue
		var ids := grid.get_id_path(sa, sb)
		if ids.is_empty():
			continue
		var out: Array = [a]
		for id in ids:
			out.append(Vector3(id.x * CELL, 0.0, id.y * CELL))
		# Das letzte Stück nur, wenn das Ziel selbst frei liegt.
		if sb == _cell(b):
			out[out.size() - 1] = b if out.size() > 2 else out[out.size() - 1]
			if out[out.size() - 1] != b:
				out.append(b)
		return out
	return []


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(roundf(p.x / CELL)), int(roundf(p.z / CELL)))


## Nächste freie Zelle auf derselben Seite der Wand (höchstens 1,2 m entfernt).
func _free_cell(grid: AStarGrid2D, p: Vector3) -> Vector2i:
	var c := _cell(p)
	var inside := OutdoorWorld.HALL.grow(-0.3).has_point(Vector2(p.x, p.z))
	var best := Vector2i.MAX
	var best_d := INF
	for x in range(c.x - 3, c.x + 4):
		for y in range(c.y - 3, c.y + 4):
			var id := Vector2i(x, y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
				continue
			var w := Vector2(x * CELL, y * CELL)
			if OutdoorWorld.HALL.grow(-0.3).has_point(w) != inside:
				continue
			var d := w.distance_to(Vector2(p.x, p.z))
			if d < best_d:
				best_d = d
				best = id
	return best


func _build_grid(with_things: bool) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	var plot := OutdoorWorld.PLOT.grow(-0.5)
	var lo := Vector2i(int(ceilf(plot.position.x / CELL)), int(ceilf(plot.position.y / CELL)))
	var hi := Vector2i(int(floorf(plot.end.x / CELL)), int(floorf(plot.end.y / CELL)))
	grid.region = Rect2i(lo, hi - lo + Vector2i.ONE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	# Feste Gegenstände drinnen und draußen
	for k in DecorSpec.GARAGE_BLOCKS:
		if absf(float(k[0])) > 0.01 or float(k[1]) < 3.0: # der freigehaltene Torbereich ist kein Hindernis
			if not Rect2(-5.8, 3.0, 1.6, 1.2).has_point(Vector2(float(k[0]), float(k[1]))): # Platz vor der Hintertür
				_block(grid, Vector2(float(k[0]), float(k[1])), Vector2(float(k[2]), float(k[3])), 0.0)
	for id in _outdoor_solid():
		if grid.is_in_boundsv(id):
			grid.set_point_solid(id, true)
	if with_things:
		_block_things(grid)
	# Außenwände mit Tor und Hintertür, dazu die noch geschlossenen Trennwände.
	var gate_open := GameState.garage_door_open
	_wall_x(grid, -5.6, -4.6, 4.6)
	_wall_x(grid, 21.6, -4.6, 4.6)
	_wall_z(grid, -4.6, -5.6, 21.6)
	_wall_z(grid, 4.6, -5.6, -GATE_HALF_X if gate_open else 0.0)
	_wall_z(grid, 4.6, GATE_HALF_X if gate_open else 0.0, 21.6)
	if GameState.room_level < 1:
		_wall_x(grid, 5.5, -4.6, 4.6)
	if GameState.room_level < 2:
		_wall_x(grid, 12.5, -4.6, 4.6)
	for x in range(int(floorf(BACK_DOOR.position.x / CELL)), int(ceilf(BACK_DOOR.end.x / CELL)) + 1):
		for y in range(int(floorf(BACK_DOOR.position.y / CELL)), int(ceilf(BACK_DOOR.end.y / CELL)) + 1):
			if BACK_DOOR.has_point(Vector2(x * CELL, y * CELL)) and grid.is_in_boundsv(Vector2i(x, y)):
				grid.set_point_solid(Vector2i(x, y), false)
	return grid


func _block_things(grid: AStarGrid2D) -> void:
	for r in GameState.racks.values():
		_block_entity(grid, r, Vector2(0.45, 0.49))
	for u in GameState.ups_units.values():
		var us: Vector3 = UpsProp.SIZES.get(str((u as Dictionary).get("ups_type", "ups")), Vector3(0.5, 1.0, 0.64))
		_block_entity(grid, u, Vector2(us.x, us.z) * 0.5)
	for c in GameState.coolers.values():
		var ct := str((c as Dictionary).get("cooler_type", "cooler"))
		if ct != GameState.INDOOR_UNIT_TYPE:
			var cs: Vector3 = CoolerProp.GHOST_SIZES.get(ct, Vector3(1.0, 1.0, 0.5))
			_block_entity(grid, c, Vector2(cs.x, cs.z) * 0.5)
	for d in GameState.decor_items.values():
		var dt := str((d as Dictionary).get("item_type", ""))
		# Durch die Kaltgang-Portale geht man hindurch, Schilder hängen an der Wand.
		if DecorSpec.SIZES.has(dt) and not DecorSpec.is_wall_sign(dt) and dt != "prop_cold_aisle_gate":
			_block_entity(grid, d, DecorSpec.footprint(dt) * 0.5)
	for k in GameState.carts.values():
		if int((k as Dictionary).get("pushed_by", 0)) == 0:
			_block_entity(grid, k, Vector2(0.36, 0.52))


## Gilt für Garage und Halle Nord: Was außerhalb des Rasters steht, übergeht _block.
func _block_entity(grid: AStarGrid2D, e: Dictionary, half: Vector2) -> void:
	var p: Variant = e.get("pos", null)
	if p is Vector3:
		_block(grid, Vector2((p as Vector3).x, (p as Vector3).z), half, float(e.get("rot_y", 0.0)))


## Rechteck samt Körperbreite sperren.
func _block(grid: AStarGrid2D, c: Vector2, half: Vector2, rot: float) -> void:
	var h := half + Vector2(BODY_R, BODY_R)
	var reach := h.length()
	var ax := Vector2(cos(rot), -sin(rot))
	var az := Vector2(sin(rot), cos(rot))
	for x in range(int(floorf((c.x - reach) / CELL)), int(ceilf((c.x + reach) / CELL)) + 1):
		for y in range(int(floorf((c.y - reach) / CELL)), int(ceilf((c.y + reach) / CELL)) + 1):
			var id := Vector2i(x, y)
			var d := Vector2(x * CELL, y * CELL) - c
			if grid.is_in_boundsv(id) and absf(d.dot(ax)) < h.x and absf(d.dot(az)) < h.y:
				grid.set_point_solid(id, true)


## Feste Einbauten in Halle Nord (lokal, Mitte und halbe Größe) stehen in HalleNordLayout.SOLID.

## Raster für Halle Nord: nur der Innenraum, Wände sind der Rand.
func _build_nord_grid(with_things: bool) -> AStarGrid2D:
	var oz := GameState.HALLE_NORD_ORIGIN.z
	var grid := AStarGrid2D.new()
	var lo := Vector2i(int(ceilf((-HalleNordLayout.WALL_X + 0.3) / CELL)), int(ceilf((oz - HalleNordLayout.WALL_Z + 0.3) / CELL)))
	var hi := Vector2i(int(floorf((HalleNordLayout.open_max_x() - 0.3) / CELL)), int(floorf((oz + HalleNordLayout.WALL_Z - 0.3) / CELL)))
	grid.region = Rect2i(lo, hi - lo + Vector2i.ONE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for b in HalleNordLayout.SOLID:
		_block(grid, Vector2(float(b[0]), float(b[1]) + oz), Vector2(float(b[2]), float(b[3])), 0.0)
	if with_things:
		_block_things(grid)
	return grid


func _nord_stop() -> Vector3:
	return GameState.HALLE_NORD_ORIGIN + NORD_STOP


## Zwischen Garage und Halle Nord: zur Haltestelle gehen, mit dem Shuttle fahren (dabei unsichtbar)
## und drüben von der Haltestelle aus weiterlaufen.
func _ride(target: Vector3, text: String, after: Callable) -> void:
	var to_nord := _is_remote(target)
	var there := _nord_stop() if to_nord else SHUTTLE
	var ride_text := tr("mit dem Shuttle nach Halle Nord") if to_nord else tr("mit dem Shuttle zurück")
	var go := func():
		_after = func():
			_pos = there
			_walk_to(target, text, after)
		_wait = SHUTTLE_TIME
		_set_phase("wait", ride_text)
	# Ist die Haltestelle zugestellt, nimmt er trotzdem das Shuttle, statt festzusitzen.
	_walk_to(_nord_stop() if not to_nord else SHUTTLE, text, go, go)


func _wall_x(grid: AStarGrid2D, wx: float, z0: float, z1: float) -> void:
	_block(grid, Vector2(wx, (z0 + z1) * 0.5), Vector2(0.12, (z1 - z0) * 0.5), 0.0)


func _wall_z(grid: AStarGrid2D, wz: float, x0: float, x1: float) -> void:
	_block(grid, Vector2((x0 + x1) * 0.5, wz), Vector2((x1 - x0) * 0.5, 0.12), 0.0)


## Bäume, Beete, Container und Geländer draußen: einmal aus den Kollisionen gelesen.
var _outdoor_cells: Array = []
var _outdoor_read := false

func _outdoor_solid() -> Array:
	if _outdoor_read:
		return _outdoor_cells
	var w3d := get_viewport().find_world_3d()
	if w3d == null or w3d.direct_space_state == null or get_tree().get_first_node_in_group("outdoor_world") == null:
		return []
	var space := w3d.direct_space_state
	_outdoor_read = true
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.44, 1.0, 0.44)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1
	var skip: Array[RID] = []
	for n in get_tree().get_nodes_in_group("players"):
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var plot := OutdoorWorld.PLOT.grow(-0.5)
	var hall := OutdoorWorld.HALL.grow(0.5)
	for x in range(int(ceilf(plot.position.x / CELL)), int(floorf(plot.end.x / CELL)) + 1):
		for y in range(int(ceilf(plot.position.y / CELL)), int(floorf(plot.end.y / CELL)) + 1):
			var w := Vector2(x * CELL, y * CELL)
			if hall.has_point(w):
				continue
			q.transform = Transform3D(Basis.IDENTITY, Vector3(w.x, 0.85, w.y))
			for hit in space.intersect_shape(q, 4):
				var col := hit["collider"] as Node
				# Nur Festes: Geräte und Ware stehen schon in den Daten, Fahrzeuge fahren weg.
				if col is StaticBody3D and not _belongs_to_entity(col):
					_outdoor_cells.append(Vector2i(x, y))
					break
	return _outdoor_cells


func _belongs_to_entity(n: Node) -> bool:
	var p := n
	while p != null:
		if p is CoolerProp or p is UpsProp or p is RackProp or p is DecorProp or p is CartProp or p is CrateProp or p is DeliveryVan:
			return true
		p = p.get_parent()
	return false


func _rack_front(rack_id: String) -> Vector3:
	var r: Dictionary = GameState.racks[rack_id]
	var p: Vector3 = r.get("pos", Vector3.ZERO)
	return p + Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, float(r.get("rot_y", 0.0))) * 1.05


func _is_remote(p: Vector3) -> bool:
	return p.z < -100.0


## Zu einem Ort gehen; nach Halle Nord und zurück fährt das Shuttle (siehe _ride).
func _travel(target: Vector3, text: String, after: Callable) -> void:
	_walk_to(target, text, after)


# ------------------------------------------------------------------ Arbeit finden

func _idle(text: String) -> void:
	# Nach einem Einsatz in Halle Nord fährt er zurück an seinen Platz.
	if _is_remote(_pos):
		_walk_to(HOME, text, func(): _set_phase("idle", text))
		return
	if _pos.distance_to(HOME) > 0.4:
		var way := find_path(_pos, HOME)
		# Steht sein Platz voll, wartet er so nah dran, wie es geht.
		if not way.is_empty() and (way[way.size() - 1] as Vector3).distance_to(_pos) > 0.45:
			_walk_to(HOME, text, func(): _set_phase("idle", text))
			return
	if str(view.get("text", "")) != text or _phase != "idle":
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
		if bool(c.get("tech", false)) and int(c.get("held_by", 0)) == 0 and not _is_unreachable(str(cid)):
			_job = {"kind": "crate", "crate": cid}
			_walk_to(_stand_near(c.get("pos", Vector3.ZERO)), tr("holt den Server"), _pick_crate_to_bench)
			return true
	return false


## Freier Platz neben der Ware, möglichst nah am Techniker.
func _stand_near(p: Vector3) -> Vector3:
	var grid := _build_grid(true)
	var best := p + Vector3(0.0, 0.0, -0.6 if p.z > 5.0 else 0.6)
	var best_d := INF
	for k in 8:
		var s := p + Vector3(0.6, 0.0, 0.0).rotated(Vector3.UP, TAU * float(k) / 8.0)
		var id := _cell(s)
		if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
			continue
		if OutdoorWorld.HALL.grow(-0.3).has_point(Vector2(s.x, s.z)) != OutdoorWorld.HALL.grow(-0.3).has_point(Vector2(p.x, p.z)):
			continue
		var d := s.distance_to(_pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func _try_build_box() -> bool:
	for cid in GameState.crates.keys():
		var c: Dictionary = GameState.crates[cid]
		if str(c.get("item_type", "")) == "slot_build_box" and int(c.get("held_by", 0)) == 0 and not _is_unreachable(str(cid)):
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
		if _is_unreachable(str(rid)):
			continue
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
		if _is_unreachable(str(rid)) or not (r.get("services", []) as Array).is_empty():
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
		_walk_to(BENCH_STAND, tr("trägt den Server zur Werkbank"), _put_crate_on_bench))


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
