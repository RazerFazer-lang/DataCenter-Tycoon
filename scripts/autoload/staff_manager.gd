extends Node
## Neues Personal mit Figur (GAME-07): Der Sicherheitsdienst läuft nachts Runden, schreckt Diebe ab
## und stellt sie. Die Reinigung entstaubt tagsüber die Racks. Der Netzwerk-Admin hat keine Figur,
## er arbeitet in CyberManager. Der Host lenkt die Figuren, die Clients zeigen nur, was er schickt.

signal staff_changed

const ROLES_WITH_FIGURE: Array[String] = ["security", "cleaning"]
const WALK_SPEED := 1.4
const RUN_SPEED := 3.6
const THINK := 1.0
## Runde des Wachdienstes vor der Garage (Spielkoordinaten).
const PATROL: Array[Vector3] = [Vector3(0.0, 0.0, 7.6), Vector3(5.2, 0.0, 8.6), Vector3(0.0, 0.0, 10.0), Vector3(-4.4, 0.0, 8.6)]
const GUARD_HOME := Vector3(-1.2, 0.0, 9.4)
const CLEANER_HOME := Vector3(-2.6, 0.0, 2.8)
## Ab so viel Staub (Prozent) lohnt sich ein Rack.
const DUST_MIN := 18.0
## Staub nach dem Putzen (Anteil vom alten Wert).
const CLEAN_KEEP := 0.3
## Reichweite, in der der Wachdienst einen Dieb stellt.
const CATCH_DIST := 2.1

## Rolle -> Anzeige {id, name, phase, path, dur, pos, text, args, stamp}. text ist die deutsche Vorlage,
## jeder Rechner übersetzt sie selbst (GameState.format_message), damit Co-op mit gemischten Sprachen passt.
var views := {"security": {}, "cleaning": {}, "auditor": {}}
var _state := {}
var _think := 0.0
var _skip_rack: Dictionary = {}
var _was_active := false


func _process(delta: float) -> void:
	var active: bool = NetworkManager.is_in_session and GameState.is_active
	if not active:
		if _was_active:
			_was_active = false
			reset()
		return
	_was_active = true
	if not multiplayer.is_server():
		return
	_think += delta
	for role in ROLES_WITH_FIGURE:
		_advance(role, delta)
	if _think >= THINK:
		_think = 0.0
		_plan("security")
		_plan("cleaning")


func reset() -> void:
	views = {"security": {}, "cleaning": {}, "auditor": {}}
	_state = {}
	_skip_rack = {}
	staff_changed.emit()


## Bester Mitarbeiter einer Rolle (höchste Erfahrung), leer wenn keiner eingestellt ist.
func worker(role: String) -> Dictionary:
	var best: Dictionary = {}
	for e in FinanceManager.employees.values():
		if str(e.get("role", "")) == role and int(e.get("skill", 0)) > int(best.get("skill", -1)):
			best = e
	return best


func is_night() -> bool:
	var h := PowerTariff.hour_of(GameState.time_of_day)
	return h >= 18.0 or h < 6.0


func on_duty(role: String) -> bool:
	if worker(role).is_empty():
		return false
	return is_night() if role == "security" else not is_night()


## Faktor auf die Chance für Diebe: Ein Wachdienst schreckt ab, je erfahrener, desto mehr.
func thief_factor() -> float:
	if not on_duty("security"):
		return 1.0
	return clampf(0.6 - 0.06 * float(worker("security").get("skill", 1)), 0.25, 0.6)


## Wo eine Figur gerade ist (auf allen Rechnern gleich gerechnet).
func pos_of(role: String) -> Vector3:
	var v: Dictionary = views.get(role, {})
	if v.is_empty():
		return Vector3.INF
	if str(v.get("phase", "")) == "walk":
		var dur := maxf(0.1, float(v.get("dur", 1.0)))
		var t := clampf(float(Time.get_ticks_msec() - int(v.get("stamp", 0))) / 1000.0 / dur, 0.0, 1.0)
		return along(v.get("path", []), t, v.get("pos", Vector3.ZERO))
	return v.get("pos", Vector3.ZERO)


## Steht der Wachdienst nah genug, um den Dieb an dieser Stelle zu stellen?
func guard_catches(thief_at: Vector3) -> bool:
	if not on_duty("security"):
		return false
	var p := pos_of("security")
	return p != Vector3.INF and Vector2(p.x - thief_at.x, p.z - thief_at.z).length() < CATCH_DIST


## Besucher ohne Anstellung (GAME-09 Prüfer): eine Figur, die einen Weg abläuft. Nur Host.
func show_visitor(role: String, who: String, phase: String, text: String, path: Array, dur: float, args: Array = []) -> void:
	views[role] = {"id": role, "name": who, "role": role, "phase": phase, "path": path, "dur": dur,
		"pos": path[path.size() - 1] if not path.is_empty() else Vector3.ZERO, "text": text, "args": args, "stamp": Time.get_ticks_msec()}
	_rpc_sync_view.rpc(role, views[role])


func hide_visitor(role: String) -> void:
	views[role] = {}
	_rpc_sync_view.rpc(role, {})


func guard_name() -> String:
	return str(worker("security").get("name", tr("Wachdienst")))


static func along(path: Array, t: float, fallback: Vector3) -> Vector3:
	if path.is_empty():
		return fallback
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector3).distance_to(path[i - 1])
	var want := total * t
	for i in range(1, path.size()):
		var seg := (path[i] as Vector3).distance_to(path[i - 1])
		if want <= seg and seg > 0.0001:
			return (path[i - 1] as Vector3).lerp(path[i], want / seg)
		want -= seg
	return path[path.size() - 1]


# ---------------------------------------------------------------- Host: Ablauf

func _st(role: String) -> Dictionary:
	if not _state.has(role):
		_state[role] = {"phase": "", "wait": 0.0, "dur": 0.0, "target": "", "patrol": 0, "id": ""}
	return _state[role]


func _set_view(role: String, phase: String, text: String, path: Array, dur: float, pos: Vector3, args: Array = []) -> void:
	var e := worker(role)
	views[role] = {"id": str(e.get("id", "")), "name": str(e.get("name", "")), "role": role, "phase": phase, "path": path,
		"dur": dur, "pos": pos, "text": text, "args": args, "stamp": Time.get_ticks_msec()}
	_rpc_sync_view.rpc(role, views[role])


@rpc("authority", "call_local", "reliable")
func _rpc_sync_view(role: String, data: Dictionary) -> void:
	views[role] = data.duplicate(true)
	if not data.is_empty():
		views[role]["stamp"] = Time.get_ticks_msec()
	staff_changed.emit()


func _walk(role: String, target: Vector3, text: String, run: bool = false, args: Array = []) -> void:
	var from := pos_of(role)
	if from == Vector3.INF:
		from = GUARD_HOME if role == "security" else CLEANER_HOME
	var way: Array = TechnicianManager.find_path(from, target)
	if way.is_empty():
		way = [from, target]
	var length := 0.0
	for i in range(1, way.size()):
		length += (way[i] as Vector3).distance_to(way[i - 1])
	var dur := maxf(0.2, length / (RUN_SPEED if run else WALK_SPEED))
	var st := _st(role)
	st["phase"] = "walk"
	st["wait"] = 0.0
	st["dur"] = dur
	_set_view(role, "walk", text, way, dur, target, args)


func _advance(role: String, delta: float) -> void:
	var st := _st(role)
	if str(st["phase"]) == "":
		return
	st["wait"] = float(st["wait"]) + delta
	if float(st["wait"]) < float(st["dur"]):
		return
	match str(st["phase"]):
		"walk":
			st["phase"] = "arrived"
		"work":
			_finish_clean(st)
			st["phase"] = "idle"
			_set_view(role, "idle", "fertig", [], 0.0, pos_of(role))


func _plan(role: String) -> void:
	var st := _st(role)
	if not on_duty(role):
		if not (views.get(role, {}) as Dictionary).is_empty():
			st["phase"] = ""
			views[role] = {}
			_rpc_sync_view.rpc(role, {})
		return
	var e := worker(role)
	if str(st.get("id", "")) != str(e.get("id", "")) or (views.get(role, {}) as Dictionary).is_empty():
		st["id"] = str(e.get("id", ""))
		var home := GUARD_HOME if role == "security" else CLEANER_HOME
		st["phase"] = "idle"
		_set_view(role, "idle", "Dienstbeginn", [], 0.0, home)
		return
	if role == "security":
		_plan_guard(st)
	else:
		_plan_cleaner(st)


func _plan_guard(st: Dictionary) -> void:
	if not DecorManager.thief.is_empty():
		var tp: Vector3 = DecorManager.thief_pos()
		var cur: Dictionary = views.get("security", {})
		var cur_target: Vector3 = cur.get("pos", Vector3.INF)
		if str(st["phase"]) != "walk" or cur_target.distance_to(tp) > 1.5:
			_walk("security", tp, "jagt einen Dieb", true)
		return
	if str(st["phase"]) in ["idle", "arrived"]:
		st["patrol"] = (int(st["patrol"]) + 1) % PATROL.size()
		_walk("security", PATROL[int(st["patrol"])], "läuft Streife")


func _plan_cleaner(st: Dictionary) -> void:
	match str(st["phase"]):
		"walk":
			return
		"work":
			return
		"arrived":
			if str(st["target"]) != "" and GameState.racks.has(str(st["target"])):
				var skill := int(worker("cleaning").get("skill", 1))
				st["phase"] = "work"
				st["wait"] = 0.0
				st["dur"] = maxf(4.0, 12.0 - float(skill) * 1.4)
				_set_view("cleaning", "work", "entstaubt %s", [], float(st["dur"]), pos_of("cleaning"), [GameState.get_rack_display_name(str(st["target"]))])
				return
			st["phase"] = "idle"
	var rid := _dustiest_rack()
	if rid == "":
		if pos_of("cleaning").distance_to(CLEANER_HOME) > 0.5:
			st["target"] = ""
			_walk("cleaning", CLEANER_HOME, "wartet auf Staub")
		return
	var r := RackData.of(GameState.racks[rid])
	var front := r.pos + Vector3(sin(r.rot_y), 0.0, cos(r.rot_y)) * 0.95
	var way: Array = TechnicianManager.find_path(pos_of("cleaning"), front)
	if way.is_empty():
		_skip_rack[rid] = Time.get_ticks_msec() + 60000
		return
	st["target"] = rid
	_walk("cleaning", front, "geht zu %s", false, [GameState.get_rack_display_name(rid)])


func _dustiest_rack() -> String:
	var best := ""
	var best_dust := DUST_MIN
	var now := Time.get_ticks_msec()
	for rid in GameState.racks.keys():
		if int(_skip_rack.get(rid, 0)) > now:
			continue
		var r := RackData.of(GameState.racks[rid])
		if r.pos.z < -100.0:
			continue # Halle Nord: dort putzt (noch) niemand.
		var dust := 0.0
		for i in r.used_slots():
			dust = maxf(dust, float(r.slot(i).raw.get("dust_level", 0.0)))
		if dust > best_dust:
			best_dust = dust
			best = str(rid)
	return best


func _finish_clean(st: Dictionary) -> void:
	var rid := str(st.get("target", ""))
	st["target"] = ""
	if not GameState.racks.has(rid):
		return
	var r := RackData.of(GameState.racks[rid])
	for i in r.used_slots():
		var raw: Dictionary = r.slot(i).raw
		raw["dust_level"] = float(raw.get("dust_level", 0.0)) * CLEAN_KEEP
	var e := worker("cleaning")
	if not e.is_empty():
		e["work_done"] = int(e.get("work_done", 0)) + 1
	GameState._broadcast_racks()
