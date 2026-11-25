class_name AssemblyPlan
extends RefCounted
## Montageplan der Werkbank: welche Teile ein Server hat und welche Handgriffe beim
## Zusammenbau bzw. bei einer Reparatur nötig sind. Host und Clients bauen aus dem
## workbench_state denselben Plan; gespeichert und übertragen wird nur "done" (und "spare").
##
## Teil (items):     id -> {kind, parent, model, node, base, init, ...}
## Handgriff (tasks): {id, kind, item, label, needs, set, tool, hold, kit, optional}
##   kind: place | remove | screw | unscrew | lever | paste | plug | unplug | press | measure | choose
##   set:  Teil-Zustände nach dem Handgriff, z. B. {"cpu": "seat"}
## Zustände: seat, rest, defect, in, out, tray, set, open, closed, plugged, unplugged, on, off
##
## Reparatur: Prüfkabel anstecken, einschalten, POST-Code lesen, Deckel ab, messen, ausschalten,
## Ersatzteil wählen, tauschen, Testlauf. Wer den Defekt schon am Rack gefunden hat, spart das Messen.

const TOOL_HAND := ""
const TOOL_DRIVER := "driver"
const TOOL_PASTE := "paste"
const TOOL_TWEEZERS := "tweezers"
const TOOL_METER := "meter"

## Lage der Baugruppen im Gehäuse (wie HardwareMeshFactory.build_open_server_chassis).
const MB_POS := Vector3(-0.04, 0.022, -0.07)
const CPU_POS := Vector3(-0.07, 0.006, -0.01)
const RAM_POS := Vector3(0.09, 0.008, -0.03)
const GPU_POS := Vector3(-0.21, 0.008, 0.05)
const SSD_POS := Vector3(0.04, 0.008, 0.14)
const WALL_POS := Vector3(-0.02, 0.018, 0.21)
const PSU_POS := Vector3(0.285, 0.018, -0.17)
const LID_POS := Vector3(0.0, 0.152, -0.036)
const PORT_POS := Vector3(-0.345, 0.060, 0.371)
const BUTTON_POS := Vector3(0.345, 0.060, 0.371)

const MB_SCREWS := 8
const RAM_SLOTS := 8
const PASTE_MIN := 0.5
const PASTE_MAX := 1.4
const DONE_MAX := 1.6
const SPARE_KIT := "kit"

## Schraube: fest genug ab 0.9, zu fest ab 1.2, überdreht ab 1.45. Loslassen geht ab 0.7.
const SCREW_MIN := 0.7
const SCREW_LOOSE := 0.9
const SCREW_OVER := 1.2
const SCREW_STRIP := 1.45
const PASTE_LOW := 0.8
const PASTE_HIGH := 1.1

## Gewicht der Baugruppen in der Bauqualität.
const QUALITY_WEIGHTS := {"mb": 24.0, "cooler": 24.0, "paste": 30.0, "gpu": 6.0, "ssd": 6.0, "psu": 6.0, "lid": 4.0}
const QUALITY_GROUP := {"Mainboard": "mb", "Platine": "mb", "CPU-Kühler": "cooler", "Grafikkarte": "gpu", "M.2-SSD": "ssd", "Netzteil": "psu", "Deckel": "lid"}
const FLAW_COST := {"live": 15.0}

const LBL_SCREW := "Schrauben festziehen: %s"
const LBL_UNSCREW := "Schrauben lösen: %s"
const LBL_MEASURE := "Fehler suchen: Messpunkte mit dem Messgerät prüfen"

## POST-Code je Defekt: Anzeige, Meldung, leuchtende Q-LEDs, Signaltöne und die Teile, die in Frage kommen.
const POST := {
	"cpu": {"code": "00", "msg": "CPU antwortet nicht", "leds": ["CPU"], "beeps": 5, "suspects": ["cpu", "mainboard"]},
	"ram": {"code": "55", "msg": "Speicher-Init fehlgeschlagen", "leds": ["DRAM"], "beeps": 3, "suspects": ["ram", "cpu", "mainboard"]},
	"gpu": {"code": "d6", "msg": "Keine Grafikausgabe", "leds": ["VGA"], "beeps": 4, "suspects": ["gpu", "mainboard"]},
	"storage": {"code": "A2", "msg": "Kein Boot-Laufwerk", "leds": ["BOOT"], "beeps": 1, "suspects": ["storage", "mainboard"]},
	"cooling": {"code": "F1", "msg": "Lüfterfehler, Start abgebrochen", "leds": ["CPU"], "beeps": 2, "suspects": ["cooling", "cpu"]},
	"psu": {"code": "--", "msg": "Spannung bricht ein", "leds": [], "beeps": 0, "suspects": ["psu", "mainboard"]},
	"mainboard": {"code": "b2", "msg": "Bus-Fehler", "leds": ["CPU", "DRAM", "VGA"], "beeps": 7, "suspects": ["mainboard", "ram", "gpu", "cpu"]},
}

## Messpunkt je Teil: Name, Einheit, Sollwert, Wert bei Defekt, Nachkommastellen.
const READINGS := {
	"psu": ["12-V-Schiene", "V", 12.06, 7.41, 2],
	"mainboard": ["VRM-Ausgang", "V", 1.80, 0.32, 2],
	"cpu": ["Kernspannung", "V", 1.12, 0.04, 2],
	"ram": ["DIMM-Spannung", "V", 1.20, 0.58, 2],
	"gpu": ["PCIe 8-Pin", "V", 12.02, 3.86, 2],
	"storage": ["M.2-Versorgung", "V", 3.31, 1.07, 2],
	"cooling": ["Lüfter-Tacho", "U/min", 8240.0, 0.0, 0],
}


static func variant(wb: Dictionary) -> Dictionary:
	var mb_id := str(wb.get("mainboard_id", "web_server"))
	var comps: Dictionary = wb.get("components", {}) as Dictionary if wb.get("components", {}) is Dictionary else {}
	var chassis := GameState.get_chassis_visual(mb_id)
	var v := {"chassis": chassis, "ai": chassis == "gpu_server"}
	for cat in ["cpu", "ram", "storage", "cooling", "psu"]:
		v[cat] = HardwareMeshFactory.get_visual_tier(comps, cat) if HardwareMeshFactory.has_part(comps, cat) else -1
	var gpu := HardwareMeshFactory.get_visual_tier(comps, "gpu") if HardwareMeshFactory.has_part(comps, "gpu") else 0
	if chassis == "gpu_server":
		gpu = maxi(1, gpu)
	v["gpu"] = gpu
	# Welches Teil genau steckt: jedes hat sein eigenes Modell.
	var ids: Dictionary = {}
	for cat in ["cpu", "ram", "gpu", "storage", "cooling", "psu"]:
		var cv: Variant = comps.get(cat, "")
		ids[cat] = str(cv) if cv is String else ""
	v["ids"] = ids
	return v


## Modell eines Teils: eigenes (hwm_<id>), sonst das allgemeine der Stufe.
static func model_of(v: Dictionary, cat: String, fallback: String) -> String:
	var id := str((v.get("ids", {}) as Dictionary).get(cat, ""))
	if cat == "gpu" and int(HardwareCatalog.get_part("gpu", id).get("vtier", 0)) <= 0:
		return fallback
	return "hwm_" + id if PartModels.has_mount(id) else fallback


## Defekte Kategorie, so wie sie sich an diesem Server wirklich tauschen lässt.
## Onboard-Grafik sitzt auf der Platine, also wird dafür die Platine getauscht.
static func repair_cat(wb: Dictionary) -> String:
	var v := variant(wb)
	if str(v["chassis"]) == "net_switch":
		return "switch"
	var cat := str(wb.get("faulty_part", ""))
	if cat == "gpu" and int(v["gpu"]) <= 0:
		return "mainboard"
	if cat in ["cpu", "ram", "storage", "cooling", "psu"] and int(v[cat]) < 0:
		return "mainboard"
	if cat in ["cpu", "ram", "gpu", "storage", "cooling", "psu"]:
		return cat
	return "mainboard"


## Gewähltes Ersatzteil: {"kind": "kit"|"part", "id": ...} oder leer.
static func spare_of(wb: Dictionary) -> Dictionary:
	var raw: Variant = wb.get("spare", {})
	return raw if raw is Dictionary else {}


## Lassen sich für diesen Defekt Teile aus dem Teile-Lager einbauen? (Platinen gibt es nur als Kit.)
static func accepts_parts(rcat: String) -> bool:
	return rcat in ["cpu", "ram", "gpu", "storage", "cooling", "psu"]


static func ram_count(tier: int) -> int:
	return clampi(2 + tier * 2, 0, RAM_SLOTS) if tier >= 0 else 0


static func ssd_count(tier: int) -> int:
	return mini(1 + tier, 3) if tier >= 0 else 0


static func cooler_screws(tier: int) -> int:
	return 2 if tier == 2 else 4


static func gpu_cards(tier: int) -> int:
	return 0 if tier <= 0 else (2 if tier >= 3 else 1)


static func gpu_height(tier: int) -> float:
	return 0.072 if tier == 1 else 0.088


static func build(wb: Dictionary) -> Dictionary:
	var mode := str(wb.get("mode", ""))
	var v := variant(wb)
	var rcat := repair_cat(wb) if mode == "repair" else ""
	var spare := spare_of(wb)
	# nv = Ausstattung nach der Reparatur; "full" = komplettes neues Teil statt Standard-Kit.
	var nv := v.duplicate()
	var full := mode == "repair" and accepts_parts(rcat) and str(spare.get("kind", "")) == "part"
	if full:
		var pd := HardwareCatalog.get_part(rcat, str(spare.get("id", "")))
		nv[rcat] = clampi(int(pd.get("vtier", 0)), 1 if rcat == "gpu" else 0, 3)
		var nids: Dictionary = (v["ids"] as Dictionary).duplicate()
		nids[rcat] = str(spare.get("id", ""))
		nv["ids"] = nids
	var ctx := {
		"mode": mode, "v": v, "nv": nv, "rcat": rcat, "full": full,
		"hidden": bool(wb.get("fault_hidden", false)),
		"known": bool(wb.get("diagnosed", false)),
		"broken": wb.get("broken", []) if wb.get("broken", []) is Array else [],
	}
	var items: Dictionary = {}
	var tasks: Array = []
	if str(v["chassis"]) == "net_switch":
		_switch_items(items)
		if mode == "repair":
			_switch_repair(tasks)
	else:
		_server_items(items, ctx)
		if mode == "assembly":
			_assembly_tasks(tasks, v)
		elif mode == "repair":
			_repair_tasks(tasks, ctx)
		elif mode == "service":
			_service_tasks(tasks, v)
	var by_id: Dictionary = {}
	for t in tasks:
		by_id[str(t["id"])] = t
	return {"mode": mode, "variant": v, "new_variant": nv, "repair_cat": rcat, "full": full, "items": items, "tasks": tasks, "by_id": by_id}


## Aktueller Zustand aller Teile nach den erledigten Handgriffen.
static func states(plan: Dictionary, done: Dictionary) -> Dictionary:
	var st: Dictionary = {}
	var items: Dictionary = plan["items"]
	for id in items.keys():
		st[id] = str((items[id] as Dictionary).get("init", "seat"))
	for t in plan["tasks"]:
		if done.has(t["id"]):
			var changes: Dictionary = t["set"]
			for k in changes.keys():
				st[k] = changes[k]
	return st


static func is_powered(done: Dictionary) -> bool:
	return (done.has("power_on") and not done.has("power_off")) or (done.has("test_on") and not done.has("test_off"))


static func is_available(plan: Dictionary, done: Dictionary, task_id: String) -> bool:
	var by_id: Dictionary = plan["by_id"]
	if not by_id.has(task_id) or done.has(task_id):
		return false
	var t: Dictionary = by_id[task_id]
	for b in t["blocked_by"]:
		if done.has(b):
			return false
	return missing_need(t, done).is_empty()


## Erste noch fehlende Voraussetzung ("" = keine).
static func missing_need(task: Dictionary, done: Dictionary) -> String:
	for n in task["needs"]:
		if not done.has(n):
			return str(n)
	return ""


static func next_task(plan: Dictionary, done: Dictionary) -> Dictionary:
	for t in plan["tasks"]:
		if not bool(t["optional"]) and is_available(plan, done, str(t["id"])):
			return t
	return {}


## Pflicht-Handgriffe gesamt bzw. erledigt (freiwillige Messungen zählen nicht).
static func count_total(plan: Dictionary) -> int:
	var n := 0
	for t in plan["tasks"]:
		if not bool(t["optional"]):
			n += 1
	return n


static func count_done(plan: Dictionary, done: Dictionary) -> int:
	var n := 0
	for t in plan["tasks"]:
		if not bool(t["optional"]) and done.has(t["id"]):
			n += 1
	return n


## Fertig, sobald alle zwingenden Handgriffe getan sind. Vergessene Schrauben kosten nur Qualität.
static func is_complete(plan: Dictionary, done: Dictionary) -> bool:
	var any := false
	for t in plan["tasks"]:
		if is_hard(t):
			any = true
			if not done.has(t["id"]):
				return false
	return any


static func is_hard(t: Dictionary) -> bool:
	return not bool(t["optional"]) and not bool(t["soft"])


## Noch offene Handgriffe, die man weglassen könnte (Schrauben, Paste, Kabel).
static func open_soft(plan: Dictionary, done: Dictionary) -> Array:
	var out: Array = []
	for t in plan["tasks"]:
		if bool(t["soft"]) and not done.has(t["id"]) and str(t["id"]) != "power_off":
			out.append(t)
	return out


## Teile unter Strom anzufassen ist ein grober Fehler.
static func is_live_risk(task: Dictionary, done: Dictionary) -> bool:
	return is_powered(done) and str(task["kind"]) in ["remove", "place", "plug", "unplug"] and not (str(task["item"]) in ["lid", "plug_diag"])


## Ergebnis des Testlaufs: {ok, code, msg, leds, kind}. kind: "" | cable | cpu | mainboard
static func test_result(plan: Dictionary, done: Dictionary, wb: Dictionary) -> Dictionary:
	var st := states(plan, done)
	if str(st.get("plug_atx", "plugged")) != "plugged":
		return {"ok": false, "code": "--", "msg": "Kein Strom: 24-Pin-Kabel fehlt", "leds": [], "kind": "cable"}
	if str(st.get("plug_eps", "plugged")) != "plugged":
		return {"ok": false, "code": "00", "msg": "CPU ohne Strom: 8-Pin-Kabel fehlt", "leds": ["CPU"], "kind": "cable"}
	if str(wb.get("extra_fault", "")) == "mainboard":
		return {"ok": false, "code": "b2", "msg": "Mainboard durch Kurzschluss beschädigt", "leds": ["CPU", "DRAM", "VGA"], "kind": "mainboard"}
	if st.has("paste") and str(st["paste"]) == "off":
		return {"ok": false, "code": "00", "msg": "CPU ohne Wärmeleitpaste durchgebrannt", "leds": ["CPU"], "kind": "cpu"}
	for c in range(2):
		# Nur Karten prüfen, die wirklich stecken.
		if str(st.get("gpu%d" % c, "")) == "seat" and str(st.get("plug_gpu%d" % c, "plugged")) != "plugged":
			return {"ok": false, "code": "d6", "msg": "Grafikkarte ohne Strom: PCIe-Kabel fehlt", "leds": ["VGA"], "kind": "cable"}
	if str(st.get("plug_pwm", "plugged")) != "plugged":
		return {"ok": false, "code": "F1", "msg": "Lüfter ohne Signal: PWM-Kabel fehlt", "leds": ["CPU"], "kind": "cable"}
	var nv: Dictionary = plan["new_variant"]
	if int(nv["cpu"]) < 0 or int(nv["ram"]) < 0 or int(nv["psu"]) < 0:
		return {"ok": true, "code": "--", "msg": "Unvollständig – es fehlen noch Bauteile", "leds": [], "kind": ""}
	return {"ok": true, "code": "AA", "msg": "System bereit – alles in Ordnung", "leds": [], "kind": ""}


static func screw_score(v: float) -> float:
	if v <= 0.0:
		return 0.0
	if v < SCREW_LOOSE:
		return 0.55
	if v < SCREW_OVER:
		return 1.0
	return 0.75 if v < SCREW_STRIP else 0.4


static func paste_score(a: float) -> float:
	if a <= 0.0:
		return 0.0
	if a < PASTE_LOW:
		return lerpf(0.45, 1.0, clampf((a - PASTE_MIN) / (PASTE_LOW - PASTE_MIN), 0.0, 1.0))
	if a <= PASTE_HIGH:
		return 1.0
	return lerpf(1.0, 0.55, clampf((a - PASTE_HIGH) / (PASTE_MAX - PASTE_HIGH), 0.0, 1.0))


## Bauqualität 0–100 mit Begründung. Nicht angefasste Baugruppen behalten ihre bisherige Qualität.
## Rückgabe: {quality: int, notes: Array[[Text, Werte]]}
static func quality(plan: Dictionary, done: Dictionary, wb: Dictionary) -> Dictionary:
	var old := clampf(float(wb.get("build_quality", 100.0)), 0.0, 100.0) / 100.0
	var building := str(plan["mode"]) == "assembly"
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	var missing: Dictionary = {}
	var loose := 0
	var over := 0
	var stripped := 0
	var notes: Array = []
	for t in plan["tasks"]:
		var g := str(t["qgroup"])
		if g == "" or g == "paste":
			continue
		var v := float(done.get(t["id"], 0.0))
		# Beim Überholen sind nicht nachgezogene Schrauben nur locker, nicht weg.
		if v <= 0.0 and str(plan["mode"]) == "service":
			v = SCREW_MIN
		sums[g] = float(sums.get(g, 0.0)) + screw_score(v)
		counts[g] = int(counts.get(g, 0)) + 1
		if v <= 0.0:
			missing[t["label_arg"]] = int(missing.get(t["label_arg"], 0)) + 1
		elif v < SCREW_LOOSE:
			loose += 1
		elif v >= SCREW_STRIP:
			stripped += 1
		elif v >= SCREW_OVER:
			over += 1
	var total := 0.0
	var weight := 0.0
	for g in QUALITY_WEIGHTS.keys():
		var w := float(QUALITY_WEIGHTS[g])
		var score := -1.0
		if g == "paste":
			if (plan["by_id"] as Dictionary).has("paste"):
				var a := float(done.get("paste", 0.0))
				score = paste_score(a)
				if a <= 0.0:
					notes.append(["keine Wärmeleitpaste", []])
				elif a < PASTE_LOW:
					notes.append(["zu wenig Wärmeleitpaste", []])
				elif a > PASTE_HIGH:
					notes.append(["zu viel Wärmeleitpaste", []])
		elif counts.has(g):
			score = float(sums[g]) / float(counts[g])
		if score < 0.0:
			if building:
				continue
			score = old
		total += w * score
		weight += w
	var q := (total / weight * 100.0) if weight > 0.0 else 100.0
	for k in missing.keys():
		notes.append(["%d Schraube(n) fehlen: %s", [missing[k], str(k)]])
	if stripped > 0:
		notes.append(["%d Schraube(n) überdreht", [stripped]])
	if over > 0:
		notes.append(["%d Schraube(n) zu fest", [over]])
	if loose > 0:
		notes.append(["%d Schraube(n) locker", [loose]])
	var flaws: Variant = wb.get("flaws", [])
	if flaws is Array:
		for f in flaws:
			q -= float(FLAW_COST.get(str(f), 0.0))
			if str(f) == "live":
				notes.append(["unter Strom gearbeitet", []])
	return {"quality": clampi(int(roundf(q)), 5, 100), "notes": notes}


## Wurde nach der Wahl des Ersatzteils schon etwas getan? Dann ist die Wahl fest.
static func is_choice_locked(plan: Dictionary, done: Dictionary) -> bool:
	for t in plan["tasks"]:
		if done.has(t["id"]) and (t["needs"] as Array).has("choose"):
			return true
	return false


## Entfernt unbekannte oder ungültige Einträge (alte Spielstände, fremde Daten).
static func sanitize_done(plan: Dictionary, raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for t in plan["tasks"]:
		var id := str(t["id"])
		if (raw as Dictionary).has(id) and missing_need(t, out).is_empty():
			var val: Variant = raw[id]
			out[id] = clampf(float(val), 0.0, DONE_MAX) if (val is float or val is int) else 1.0
	return out


## Messwert an einem Teil: {name, value, unit, text, ok, weak}
static func reading(plan: Dictionary, cat: String) -> Dictionary:
	var r: Array = READINGS.get(cat, READINGS["mainboard"])
	var rcat := str(plan["repair_cat"])
	var bad := cat == rcat
	# Bricht das Netzteil ein, schwanken auch alle anderen Werte etwas.
	var weak := not bad and rcat == "psu"
	var val := float(r[3]) if bad else float(r[2]) * (0.91 if weak else 1.0)
	var num := ("%.0f" % val) if int(r[4]) == 0 else ("%.2f" % val)
	return {"name": str(r[0]), "unit": str(r[1]), "value": val, "text": "%s %s" % [num.replace(".", ","), str(r[1])], "ok": not bad and not weak, "weak": weak}


# ------------------------------------------------------------------ Teile

static func _item(items: Dictionary, id: String, kind: String, parent: String, model: String, node: String, base: Vector3, init: String, extra: Dictionary = {}) -> void:
	var d := {"id": id, "kind": kind, "parent": parent, "model": model, "node": node, "base": base, "init": init}
	d.merge(extra, true)
	items[id] = d


static func _server_items(items: Dictionary, ctx: Dictionary) -> void:
	var v: Dictionary = ctx["v"]
	var nv: Dictionary = ctx["nv"]
	var rcat: String = ctx["rcat"]
	var full: bool = ctx["full"]
	var hidden: bool = ctx["hidden"]
	var building := str(ctx["mode"]) == "assembly"
	# Überholen: alles sitzt, aber die Schrauben haben sich gelockert und werden nachgezogen.
	var service := str(ctx["mode"]) == "service"
	var cpu_broken := (ctx["broken"] as Array).has("cpu")
	var loose := "rest" if building else "seat"
	var sc := "out" if building else ("set" if service else "in")
	var mb_model := "asm_mainboard_ai" if bool(v["ai"]) else "asm_mainboard"

	# Platine. Bei der Reparatur gibt es zusätzlich die defekte; alle Teile darauf wandern mit.
	_item(items, "standoffs", "fixed", "chassis", mb_model, "Standoffs", MB_POS, "seat")
	if rcat == "mainboard":
		_item(items, "mb_old", "part", "chassis", mb_model if hidden else mb_model + "_broken", "Board", MB_POS, "seat", {"board": true})
		_item(items, "mb", "part", "chassis", mb_model, "Board", MB_POS, "rest", {"board": true, "spare": true})
	else:
		_item(items, "mb", "part", "chassis", mb_model, "Board", MB_POS, loose, {"board": true})
	for i in range(MB_SCREWS):
		_item(items, "mb_s%d" % i, "screw", "mb", mb_model, "Screw_%d" % i, Vector3.ZERO, sc, {"own": service})

	# CPU: Sockel, Halterahmen und Hebel gehören zur Platine.
	var ct := int(v["cpu"])
	var ctn := int(nv["cpu"])
	var cm := model_of(v, "cpu", "asm_cpu_t%d" % maxi(0, ct))
	var cmn := model_of(nv, "cpu", "asm_cpu_t%d" % maxi(0, ctn))
	_item(items, "cpu_socket", "fixed", "mb", cm, "Socket", CPU_POS, "seat")
	_item(items, "cpu_frame", "lever", "mb", cm, "Frame", CPU_POS, "closed", {"axis": Vector3(0, 0, 1), "angle": 104.0})
	_item(items, "cpu_lever", "lever", "mb", cm, "Lever", CPU_POS, "closed", {"axis": Vector3(1, 0, 0), "angle": -98.0})
	if ct >= 0:
		var fix := rcat == "cpu"
		if fix:
			var om := cm if hidden else "asm_cpu_broken"
			_item(items, "cpu_old", "part", "mb", om, "CPU", CPU_POS, "seat")
			_item(items, "cooler_old", "part", "mb", om, "Cooler", CPU_POS, "seat")
			for i in range(cooler_screws(ct)):
				_item(items, "cs_old%d" % i, "screw", "cooler_old", cm, "Screw_%d" % i, CPU_POS, "in", {"captive": true, "parent_space": "mb"})
		var cinit := "rest" if (building or fix) else "seat"
		_item(items, "cpu", "part", "mb", cmn, "CPU", CPU_POS, cinit, {"spare": fix or (building and cpu_broken), "turns": true})
		_item(items, "paste", "paste", "mb", "", "", CPU_POS + Vector3(0.0, 0.0152, 0.0), "off" if (building or fix) else "on")
		_item(items, "cooler", "part", "mb", cmn, "Cooler", CPU_POS, cinit, {"spare": fix})
		for i in range(cooler_screws(ctn)):
			_item(items, "cs%d" % i, "screw", "cooler", cmn, "Screw_%d" % i, CPU_POS, "out" if (building or fix) else "in", {"captive": true, "parent_space": "mb"})

	# RAM: ein Kit ersetzt die zwei defekten Riegel, ein neues Teil den ganzen Satz.
	var rt := int(v["ram"])
	var rtn := int(nv["ram"])
	var rm := model_of(v, "ram", "asm_ram_t%d" % maxi(0, rt))
	var rmn := model_of(nv, "ram", "asm_ram_t%d" % maxi(0, rtn))
	var swap: Array = _ram_swap(ctx) if rcat == "ram" else []
	_item(items, "ram_slots", "fixed", "mb", rm, "Slots", RAM_POS, "seat")
	for i in range(RAM_SLOTS):
		for e in range(2):
			_item(items, "latch%d_%d" % [i, e], "latch", "mb", rm, "Latch_%d_%d" % [i, e], RAM_POS, "closed",
				{"axis": Vector3(1, 0, 0), "angle": -28.0 if e == 0 else 28.0})
	var burnt := _bad_sticks(rt)
	for i in range(ram_count(rt)):
		if swap.has(i):
			if not hidden and burnt.has(i):
				var src: int = 2 + burnt.find(i)
				_item(items, "stick_old%d" % i, "part", "mb", "asm_ram_broken", "Stick_%d" % src, RAM_POS + Vector3(float(i - src) * 0.018, 0.0, 0.0), "seat", {"n": i})
			else:
				_item(items, "stick_old%d" % i, "part", "mb", rm, "Stick_%d" % i, RAM_POS, "seat", {"n": i})
		else:
			_item(items, "stick%d" % i, "part", "mb", rm, "Stick_%d" % i, RAM_POS, loose, {"n": i})
	if rcat == "ram":
		for i in (range(ram_count(rtn)) if full else swap):
			_item(items, "stick%d" % i, "part", "mb", rmn, "Stick_%d" % i, RAM_POS, "rest", {"n": i, "spare": true})

	# SSDs
	var st := int(v["storage"])
	var stn := int(nv["storage"])
	var sm := model_of(v, "storage", "asm_storage_t%d" % maxi(0, st))
	var smn := model_of(nv, "storage", "asm_storage_t%d" % maxi(0, stn))
	var sfix := rcat == "storage"
	if st >= 0:
		_item(items, "ssd_slots", "fixed", "mb", smn if (sfix and full and ssd_count(stn) >= ssd_count(st)) else sm, "Slots", SSD_POS, "seat")
		for i in range(ssd_count(st)):
			if sfix and (full or i == 0):
				_item(items, "ssd_old%d" % i, "part", "mb", "asm_storage_broken" if (i == 0 and not hidden) else sm, "SSD_%d" % i, SSD_POS, "seat", {"n": i})
				_item(items, "ssd_so%d" % i, "screw", "mb", sm, "Screw_%d" % i, SSD_POS, "in", {"n": i})
			else:
				_item(items, "ssd%d" % i, "part", "mb", sm, "SSD_%d" % i, SSD_POS, loose, {"n": i})
				_item(items, "ssd_s%d" % i, "screw", "mb", sm, "Screw_%d" % i, SSD_POS, "tray" if building else ("set" if service else "in"), {"n": i, "own": service})
		if sfix:
			for i in (range(ssd_count(stn)) if full else [0]):
				_item(items, "ssd%d" % i, "part", "mb", smn, "SSD_%d" % i, SSD_POS, "rest", {"n": i, "spare": true})
				_item(items, "ssd_s%d" % i, "screw", "mb", smn, "Screw_%d" % i, SSD_POS, "tray", {"n": i})

	# GPU-Karten
	var gt := int(v["gpu"])
	var gtn := int(nv["gpu"])
	var gfix := rcat == "gpu"
	var slots_n := maxi(gpu_cards(gt), gpu_cards(gtn) if gfix else 0)
	for c in range(slots_n):
		_item(items, "gpu_slot%d" % c, "fixed", "mb", "asm_gpu_t3" if c == 1 else "asm_gpu_t%d" % maxi(1, gt), "Slot_%d" % c, GPU_POS, "seat")
	for c in range(gpu_cards(gt)):
		var gm := model_of(v, "gpu", "asm_gpu_t%d" % gt)
		var torn := c == 0 and not hidden
		if gfix and (full or c == 0):
			_item(items, "gpu_old%d" % c, "part", "mb", "asm_gpu_broken" if torn else gm, "Card_%d" % c, GPU_POS, "seat", {"n": c})
			_item(items, "gpu_so%d" % c, "screw", "mb", "asm_tools", "ScrewM3", _gpu_screw_pos(gt, c), "in")
		else:
			_item(items, "gpu%d" % c, "part", "mb", gm, "Card_%d" % c, GPU_POS, loose, {"n": c, "rotors": gm})
			_item(items, "gpu_s%d" % c, "screw", "mb", "asm_tools", "ScrewM3", _gpu_screw_pos(gt, c), sc, {"own": service})
	if gfix:
		for c in (range(gpu_cards(gtn)) if full else [0]):
			var gmn := model_of(nv, "gpu", "asm_gpu_t%d" % gtn)
			_item(items, "gpu%d" % c, "part", "mb", gmn, "Card_%d" % c, GPU_POS, "rest", {"n": c, "rotors": gmn, "spare": true})
			_item(items, "gpu_s%d" % c, "screw", "mb", "asm_tools", "ScrewM3", _gpu_screw_pos(gtn, c), "out")
	if gt >= 3:
		_item(items, "bridge", "part", "mb", "asm_gpu_t3", "Bridge", GPU_POS, loose)
	elif gfix and gtn >= 3:
		_item(items, "bridge", "part", "mb", "asm_gpu_t3", "Bridge", GPU_POS, "rest", {"spare": true})

	# Lüfterwand und Netzteil
	var wt := int(v["cooling"])
	if wt >= 0:
		var wfix := rcat == "cooling"
		if wfix:
			_item(items, "wall_old", "part", "chassis", "#cooling" if hidden else "#cooling_broken", "", WALL_POS, "seat", {"tier": wt, "pid": str(v["ids"]["cooling"])})
		_item(items, "wall", "part", "chassis", "#cooling", "", WALL_POS, "rest" if (building or wfix) else "seat", {"tier": int(nv["cooling"]), "spare": wfix, "pid": str(nv["ids"]["cooling"])})
		_item(items, "plug_pwm", "plug", "mb", "asm_tools", "PlugPWM", Vector3(0.125, 0.0105, 0.218), "unplugged" if building else "plugged",
			{"owners": ["wall", "wall_old"], "from": Vector3(0.135, 0.022, 0.186), "loose": Vector3(0.175, 0.026, 0.135), "radius": 0.0022, "strands": 2})
	var pt := int(v["psu"])
	if pt >= 0:
		var pfix := rcat == "psu"
		var front_old := _psu_front(pt)
		var front := _psu_front(int(nv["psu"]))
		if pfix:
			_item(items, "psu_old", "part", "chassis", "#psu" if hidden else "#psu_broken", "", PSU_POS, "seat", {"tier": pt, "front": front_old, "pid": str(v["ids"]["psu"])})
			for i in range(2):
				_item(items, "psu_so%d" % i, "screw", "chassis", "asm_tools", "ScrewM3", _psu_screw_pos(front_old, i), "in")
		_item(items, "psu", "part", "chassis", "#psu", "", PSU_POS, "rest" if (building or pfix) else "seat", {"tier": int(nv["psu"]), "front": front, "spare": pfix, "pid": str(nv["ids"]["psu"])})
		for i in range(2):
			_item(items, "psu_s%d" % i, "screw", "chassis", "asm_tools", "ScrewM3", _psu_screw_pos(front, i), "out" if pfix else sc, {"own": service})
		var plugged := "unplugged" if building else "plugged"
		var out := PSU_POS + Vector3(-0.036, 0.036, front - 0.004)
		_item(items, "plug_atx", "plug", "mb", "asm_tools", "PlugATX", Vector3(0.235, 0.0215, -0.060), plugged,
			{"owners": ["psu", "psu_old"], "from": out, "loose": Vector3(0.262, 0.024, 0.085), "radius": 0.0031, "strands": 6, "spread": 0.076})
		_item(items, "plug_eps", "plug", "mb", "asm_tools", "PlugEPS", Vector3(0.0, 0.0205, -0.162), plugged,
			{"owners": ["psu", "psu_old"], "from": out + Vector3(0.0, 0.010, 0.0), "loose": Vector3(0.300, 0.024, 0.140), "radius": 0.0026, "strands": 4, "spread": 0.016, "arc": 0.075})
		for c in range(slots_n):
			var had := c < gpu_cards(gt)
			var ex := {"owners": ["psu", "psu_old"], "from": out + Vector3(0.012, 0.016, 0.0), "loose": Vector3(0.335, 0.024, 0.060 + 0.045 * float(c)), "radius": 0.0024, "strands": 4, "spread": 0.014, "arc": 0.060}
			if gfix and full:
				# Andere Bauhöhe: sobald die neue Karte sitzt, gilt deren Anschluss.
				ex["alt_base"] = _gpu_plug_pos(gtn, c)
				ex["alt_when"] = "gpu%d" % c
			_item(items, "plug_gpu%d" % c, "plug", "mb", "asm_tools", "PlugPCIE", _gpu_plug_pos(gt if had else gtn, c), "unplugged" if (building or not had) else "plugged", ex)

	_diag_items(items)
	if str(ctx["mode"]) == "repair":
		_point(items, "mainboard", Vector3(-0.0645, 0.0225, -0.175))
		if ct >= 0:
			_point(items, "cpu", Vector3(-0.065, 0.0180, -0.103))
		if rt >= 0:
			_point(items, "ram", Vector3(0.090, 0.0240, 0.050))
		if gt > 0:
			_point(items, "gpu", _gpu_plug_pos(gt, 0) + Vector3(0.0, 0.016, 0.0))
		if st >= 0:
			_point(items, "storage", SSD_POS + Vector3(-0.0565, 0.0085, -0.032))
		if wt >= 0:
			_point(items, "cooling", Vector3(0.125, 0.0225, 0.218))
		if pt >= 0:
			_point(items, "psu", Vector3(0.235, 0.0410, -0.030))

	_lid_items(items, loose, "in" if service else sc)


static func _lid_items(items: Dictionary, lid_state: String, screw_state: String) -> void:
	_item(items, "lid", "part", "chassis", "asm_lid", "Lid", LID_POS, lid_state)
	for i in range(2):
		_item(items, "lid_s%d" % i, "screw", "chassis", "asm_tools", "ScrewM3", LID_POS + Vector3(-0.31 + 0.62 * float(i), 0.0016, -0.285), screw_state)


## Prüfanschluss und Einschalter sitzen vorn in den Rack-Ohren.
static func _diag_items(items: Dictionary) -> void:
	var front := Basis(Vector3.RIGHT, PI * 0.5)
	_item(items, "diag_port", "fixed", "chassis", "asm_tools", "DiagPort", PORT_POS, "seat", {"rot": front})
	_item(items, "pwr_btn", "button", "chassis", "asm_tools", "PowerButton", BUTTON_POS, "seat", {"rot": front})
	_item(items, "plug_diag", "plug", "chassis", "asm_tools", "PlugDiag", PORT_POS + Vector3(0.0, 0.0, 0.004), "unplugged",
		{"owners": [], "rot": front, "from_abs": Vector3(-0.475, 0.035, 0.005), "loose_abs": Vector3(-0.300, 0.006, 0.365), "radius": 0.0034, "strands": 1, "arc": 0.060})


static func _point(items: Dictionary, cat: String, pos: Vector3) -> void:
	_item(items, "pt_" + cat, "point", "mb", "", "", pos, "seat", {"cat": cat})


static func _switch_items(items: Dictionary) -> void:
	_item(items, "mb_old", "part", "chassis", "asm_tools", "SwitchBoard", Vector3(0.0, 0.034, -0.04), "seat", {"board": true})
	_item(items, "mb", "part", "chassis", "asm_tools", "SwitchBoard", Vector3(0.0, 0.034, -0.04), "rest", {"board": true, "spare": true})
	for i in range(4):
		_item(items, "mb_s%d" % i, "screw", "mb", "asm_tools", "ScrewM3", Vector3(-0.30 if i % 2 == 0 else 0.30, 0.0055, -0.21 if i < 2 else 0.21), "in")
	_lid_items(items, "seat", "in")


static func _bad_sticks(tier: int) -> Array:
	return [2, 3] if ram_count(tier) >= 4 else [0, 1]


## Welche alten Riegel raus müssen.
static func _ram_swap(ctx: Dictionary) -> Array:
	var rt := int(ctx["v"]["ram"])
	return range(ram_count(rt)) if bool(ctx["full"]) else _bad_sticks(rt)


static func _gpu_screw_pos(tier: int, c: int) -> Vector3:
	return GPU_POS + Vector3(float(c) * 0.056 + 0.012, 0.0162 + gpu_height(tier), -0.152)


static func _gpu_plug_pos(tier: int, c: int) -> Vector3:
	var pz := 0.141 if tier >= 3 else (0.025 if tier == 1 else 0.095)
	return GPU_POS + Vector3(float(c) * 0.056 + (0.010 if tier >= 3 else 0.009), 0.0165 + gpu_height(tier), pz)


static func _psu_front(tier: int) -> float:
	return 0.170 if tier >= 2 else 0.152


static func _psu_screw_pos(front: float, i: int) -> Vector3:
	return PSU_POS + Vector3(-0.046 + 0.092 * float(i), 0.0018, front + 0.0125)


# ------------------------------------------------------------------ Handgriffe

static func _task(tasks: Array, id: String, kind: String, item: String, label: String, needs: Array, changes: Dictionary, extra: Dictionary = {}) -> void:
	var tool := TOOL_HAND
	var hold := 0.35
	match kind:
		"screw":
			tool = TOOL_DRIVER
			hold = 1.15
		"unscrew":
			tool = TOOL_DRIVER
			hold = 0.95
		"paste":
			tool = TOOL_PASTE
			hold = 1.8
		"measure":
			tool = TOOL_METER
			hold = 0.90
		"lever":
			hold = 0.45
		"wipe":
			hold = 1.10
		"press":
			hold = 0.30
		"remove", "unplug":
			hold = 0.40
	var t := {"id": id, "kind": kind, "item": item, "label": label, "needs": needs, "set": changes, "tool": tool, "hold": hold,
		"kit": false, "group": label, "optional": false, "soft": false, "qgroup": "", "blocked_by": []}
	t.merge(extra, true)
	tasks.append(t)


static func _screws(tasks: Array, prefix: String, item_prefix: String, count: int, what: String, needs: Array, tighten: bool = true) -> Array:
	var ids: Array = []
	for i in range(count):
		var id := "%s%d" % [prefix, i]
		ids.append(id)
		_task(tasks, id, "screw" if tighten else "unscrew", "%s%d" % [item_prefix, i], LBL_SCREW if tighten else LBL_UNSCREW, needs,
			{"%s%d" % [item_prefix, i]: "in" if tighten else "out"}, _screw_extra(what, tighten))
	return ids


## Festziehen darf man vergessen (kostet Qualität), Lösen nicht. Nur der Deckel gehört zum Abschluss.
static func _screw_extra(what: String, tighten: bool) -> Dictionary:
	var ex := {"label_arg": what}
	if tighten:
		ex["qgroup"] = str(QUALITY_GROUP.get(what, ""))
		if what != "Deckel":
			ex["soft"] = true
			ex["blocked_by"] = ["lid_on"]
	return ex


## Handgriff, den man vergessen kann.
static func _soft(extra: Dictionary = {}) -> Dictionary:
	var d := extra.duplicate()
	d["soft"] = true
	if not d.has("blocked_by"):
		d["blocked_by"] = ["lid_on"]
	return d


## Alle Pflicht-Handgriffe bis hierher.
static func _ids(tasks: Array) -> Array:
	var out: Array = []
	for t in tasks:
		if is_hard(t):
			out.append(t["id"])
	return out


## Testlauf mit Prüfkabel, danach Deckel drauf.
static func _finish(tasks: Array, cable_in_place: bool) -> void:
	var before := _ids(tasks)
	for t in tasks:
		if str(t["id"]) == "power_off":
			before.append("power_off")
	if not cable_in_place:
		_task(tasks, "diag_plug", "plug", "plug_diag", "Prüfkabel vorn einstecken", before, {"plug_diag": "plugged"})
		before = ["diag_plug"]
	_task(tasks, "test_on", "press", "pwr_btn", "Testlauf: Server einschalten", before, {})
	_task(tasks, "test_off", "press", "pwr_btn", "Testlauf: Server ausschalten", ["test_on"], {})
	_task(tasks, "diag_unplug", "unplug", "plug_diag", "Prüfkabel abziehen", ["test_off"], {"plug_diag": "unplugged"})
	_lid_on(tasks, ["diag_unplug"])


static func _lid_on(tasks: Array, needs: Array) -> void:
	_task(tasks, "lid_on", "place", "lid", "Gehäusedeckel aufsetzen", needs, {"lid": "seat"}, {"hold": 0.45})
	_screws(tasks, "lid_in", "lid_s", 2, "Deckel", ["lid_on"])


static func _lid_off(tasks: Array, needs: Array) -> void:
	var un := _screws(tasks, "lid_out", "lid_s", 2, "Deckel", needs, false)
	_task(tasks, "lid_off", "remove", "lid", "Gehäusedeckel abnehmen", un, {"lid": "rest"})


static func _paste_and_cooler(tasks: Array, tier: int, needs: Array) -> void:
	_task(tasks, "paste", "paste", "paste", "Wärmeleitpaste auftragen", needs, {"paste": "on"}, {"soft": true, "qgroup": "paste", "blocked_by": ["cooler_place"]})
	_task(tasks, "cooler_place", "place", "cooler", "CPU-Kühler aufsetzen", needs, {"cooler": "seat"}, {"hold": 0.50})
	_screws(tasks, "cooler_in", "cs", cooler_screws(tier), "CPU-Kühler", ["cooler_place"])


static func _ssd_in(tasks: Array, i: int, label: String, needs: Array, kit: bool) -> void:
	_task(tasks, "ssd_in%d" % i, "place", "ssd%d" % i, label, needs, {"ssd%d" % i: "seat"}, {"hold": 0.40, "kit": kit})
	_task(tasks, "ssd_set%d" % i, "place", "ssd_s%d" % i, "Kleine M.2-Schraube mit der Pinzette ansetzen", ["ssd_in%d" % i], {"ssd_s%d" % i: "set"}, _soft({"tool": TOOL_TWEEZERS, "hold": 0.25}))
	_task(tasks, "ssd_screw%d" % i, "screw", "ssd_s%d" % i, LBL_SCREW, ["ssd_set%d" % i], {"ssd_s%d" % i: "in"}, _soft({"label_arg": "M.2-SSD", "hold": 0.85, "qgroup": "ssd"}))


static func _assembly_tasks(tasks: Array, v: Dictionary) -> void:
	_task(tasks, "mb_place", "place", "mb", "Mainboard auf die Abstandshalter setzen", [], {"mb": "seat"}, {"hold": 0.50})
	var mb := ["mb_place"]
	_screws(tasks, "mb_in", "mb_s", MB_SCREWS, "Mainboard", mb)

	if int(v["cpu"]) >= 0:
		_task(tasks, "lever_open", "lever", "cpu_lever", "CPU-Sockel entriegeln", mb, {"cpu_lever": "open", "cpu_frame": "open"})
		_task(tasks, "cpu_place", "place", "cpu", "CPU einsetzen", ["lever_open"], {"cpu": "seat"}, {"hold": 0.55})
		_task(tasks, "lever_close", "lever", "cpu_lever", "CPU-Sockel verriegeln", ["cpu_place"], {"cpu_lever": "closed", "cpu_frame": "closed"})
		_paste_and_cooler(tasks, int(v["cpu"]), ["lever_close"])

	var sticks := ram_count(int(v["ram"]))
	if sticks > 0:
		_task(tasks, "ram_open", "lever", "latch0_1", "RAM-Halteclips öffnen", mb, _latches(range(sticks), "open"))
		for i in range(sticks):
			_task(tasks, "ram_in%d" % i, "place", "stick%d" % i, "RAM-Riegel einrasten", ["ram_open"],
				{"stick%d" % i: "seat", "latch%d_0" % i: "closed", "latch%d_1" % i: "closed"}, {"hold": 0.45, "click": "clip"})

	for i in range(ssd_count(int(v["storage"]))):
		_ssd_in(tasks, i, "M.2-SSD einstecken", mb, false)

	# Netzteil und Lüfter vor den Kabeln; die GPU kommt erst, wenn das Board fest sitzt.
	if int(v["cooling"]) >= 0:
		_task(tasks, "wall_place", "place", "wall", "Lüfterwand einsetzen", [], {"wall": "seat"}, {"hold": 0.50, "click": "clip"})
		_task(tasks, "pwm_plug", "plug", "plug_pwm", "Lüfterkabel (PWM) anstecken", ["wall_place"] + mb, {"plug_pwm": "plugged"}, _soft())
	var cards := gpu_cards(int(v["gpu"]))
	for c in range(cards):
		_task(tasks, "gpu_in%d" % c, "place", "gpu%d" % c, "Grafikkarte in den PCIe-Slot drücken", mb, {"gpu%d" % c: "seat"}, {"hold": 0.55, "click": "clip"})
		_task(tasks, "gpu_screw%d" % c, "screw", "gpu_s%d" % c, LBL_SCREW, ["gpu_in%d" % c], {"gpu_s%d" % c: "in"}, _soft({"label_arg": "Grafikkarte", "qgroup": "gpu"}))
	if cards >= 2:
		_task(tasks, "bridge_in", "place", "bridge", "GPU-Brücke aufstecken", ["gpu_in0", "gpu_in1"], {"bridge": "seat"}, {"click": "clip"})
	if int(v["psu"]) >= 0:
		_task(tasks, "psu_place", "place", "psu", "Netzteil einschieben", [], {"psu": "seat"}, {"hold": 0.55})
		_screws(tasks, "psu_in", "psu_s", 2, "Netzteil", ["psu_place"])
		_task(tasks, "atx_plug", "plug", "plug_atx", "24-Pin-Stromkabel einstecken", ["psu_place"] + mb, {"plug_atx": "plugged"}, _soft({"hold": 0.45}))
		_task(tasks, "eps_plug", "plug", "plug_eps", "8-Pin-CPU-Kabel einstecken", ["psu_place"] + mb, {"plug_eps": "plugged"}, _soft())
		for c in range(cards):
			_task(tasks, "gpu_plug%d" % c, "plug", "plug_gpu%d" % c, "PCIe-Stromkabel an die Grafikkarte stecken", ["psu_place", "gpu_in%d" % c], {"plug_gpu%d" % c: "plugged"}, _soft())
	_finish(tasks, false)


static func _latches(idx: Array, state: String) -> Dictionary:
	var d: Dictionary = {}
	for i in idx:
		d["latch%d_0" % i] = state
		d["latch%d_1" % i] = state
	return d


## Fehlersuche. Liefert die Voraussetzungen, unter denen getauscht werden darf.
static func _diagnosis(tasks: Array, ctx: Dictionary) -> Array:
	var rcat: String = ctx["rcat"]
	if bool(ctx["known"]):
		_lid_off(tasks, [])
		_task(tasks, "choose", "choose", "", "Ersatzteil wählen", [], {})
		return ["lid_off", "choose"]
	_task(tasks, "diag_plug", "plug", "plug_diag", "Prüfkabel vorn einstecken", [], {"plug_diag": "plugged"})
	_task(tasks, "power_on", "press", "pwr_btn", "Server einschalten und POST-Code ablesen", ["diag_plug"], {})
	_lid_off(tasks, ["power_on"])
	var v: Dictionary = ctx["v"]
	for cat in ["mainboard", "cpu", "ram", "gpu", "storage", "cooling", "psu"]:
		var present: bool = cat == "mainboard" or (int(v["gpu"]) > 0 if cat == "gpu" else int(v[cat]) >= 0)
		if present:
			_task(tasks, "meas_" + cat, "measure", "pt_" + cat, LBL_MEASURE, ["power_on", "lid_off"], {}, {"optional": cat != rcat, "cat": cat, "blocked_by": ["power_off"]})
	_task(tasks, "power_off", "press", "pwr_btn", "Server ausschalten, bevor du Teile anfasst", ["meas_" + rcat], {}, {"soft": true})
	_task(tasks, "choose", "choose", "", "Ersatzteil wählen", ["meas_" + rcat], {})
	return ["lid_off", "choose"]


static func _repair_tasks(tasks: Array, ctx: Dictionary) -> void:
	var v: Dictionary = ctx["v"]
	var nv: Dictionary = ctx["nv"]
	var rcat: String = ctx["rcat"]
	var full: bool = ctx["full"]
	var start := _diagnosis(tasks, ctx)
	var cards := gpu_cards(int(v["gpu"]))
	var has_psu := int(v["psu"]) >= 0
	match rcat:
		"cpu":
			var un := _screws(tasks, "cooler_out", "cs_old", cooler_screws(int(v["cpu"])), "CPU-Kühler", start, false)
			_task(tasks, "cooler_off", "remove", "cooler_old", "Alten CPU-Kühler abnehmen", un, {"cooler_old": "defect"})
			_task(tasks, "lever_open", "lever", "cpu_lever", "CPU-Sockel entriegeln", ["cooler_off"], {"cpu_lever": "open", "cpu_frame": "open"})
			_task(tasks, "cpu_out", "remove", "cpu_old", "Defekte CPU herausnehmen", ["lever_open"], {"cpu_old": "defect"})
			_task(tasks, "cpu_place", "place", "cpu", "Neue CPU einsetzen", ["cpu_out"], {"cpu": "seat"}, {"hold": 0.55, "kit": true})
			_task(tasks, "lever_close", "lever", "cpu_lever", "CPU-Sockel verriegeln", ["cpu_place"], {"cpu_lever": "closed", "cpu_frame": "closed"})
			_paste_and_cooler(tasks, int(nv["cpu"]), ["lever_close"])
		"ram":
			var old := _ram_swap(ctx)
			var fresh: Array = range(ram_count(int(nv["ram"]))) if full else old
			var all := old.duplicate()
			for i in fresh:
				if not all.has(i):
					all.append(i)
			_task(tasks, "ram_open", "lever", "latch%d_1" % int(old[0]), "RAM-Halteclips öffnen", start, _latches(all, "open"))
			var outs: Array = []
			for b in old:
				_task(tasks, "ram_out%d" % b, "remove", "stick_old%d" % b, "Alte RAM-Riegel herausziehen" if full else "Defekten RAM-Riegel herausziehen", ["ram_open"], {"stick_old%d" % b: "defect"})
				outs.append("ram_out%d" % b)
			for b in fresh:
				var changes := _latches([b], "closed")
				changes["stick%d" % b] = "seat"
				if b == fresh[fresh.size() - 1]:
					for x in all:
						if not fresh.has(x):
							changes.merge(_latches([x], "closed"))
				_task(tasks, "ram_in%d" % b, "place", "stick%d" % b, "Neuen RAM-Riegel einrasten", outs, changes, {"hold": 0.45, "click": "clip", "kit": true})
		"gpu":
			var old_n := cards if full else 1
			var new_n := gpu_cards(int(nv["gpu"])) if full else 1
			var first: Array = start
			if has_psu:
				var un: Array = []
				for c in range(old_n):
					_task(tasks, "gpu_unplug%d" % c, "unplug", "plug_gpu%d" % c, "PCIe-Stromkabel abziehen", start, {"plug_gpu%d" % c: "unplugged"})
					un.append("gpu_unplug%d" % c)
				first = un
			if cards >= 2:
				_task(tasks, "bridge_off", "remove", "bridge", "GPU-Brücke abziehen", first, {"bridge": "rest"})
				first = ["bridge_off"]
			var outs: Array = []
			for c in range(old_n):
				_task(tasks, "gpu_unscrew%d" % c, "unscrew", "gpu_so%d" % c, LBL_UNSCREW, first, {"gpu_so%d" % c: "out"}, {"label_arg": "Grafikkarte"})
				_task(tasks, "gpu_out%d" % c, "remove", "gpu_old%d" % c, "Alte Grafikkarte herausziehen", ["gpu_unscrew%d" % c], {"gpu_old%d" % c: "defect"})
				outs.append("gpu_out%d" % c)
			var ins: Array = []
			for c in range(new_n):
				_task(tasks, "gpu_in%d" % c, "place", "gpu%d" % c, "Neue Grafikkarte in den PCIe-Slot drücken", outs, {"gpu%d" % c: "seat"}, {"hold": 0.55, "click": "clip", "kit": true})
				_task(tasks, "gpu_screw%d" % c, "screw", "gpu_s%d" % c, LBL_SCREW, ["gpu_in%d" % c], {"gpu_s%d" % c: "in"}, _soft({"label_arg": "Grafikkarte", "qgroup": "gpu"}))
				ins.append("gpu_in%d" % c)
			if (full and new_n >= 2) or (not full and cards >= 2):
				_task(tasks, "bridge_in", "place", "bridge", "GPU-Brücke aufstecken", ins, {"bridge": "seat"}, {"click": "clip"})
			if has_psu:
				for c in range(new_n):
					_task(tasks, "gpu_plug%d" % c, "plug", "plug_gpu%d" % c, "PCIe-Stromkabel an die Grafikkarte stecken", ["gpu_in%d" % c], {"plug_gpu%d" % c: "plugged"}, _soft())
		"storage":
			var outs: Array = []
			for i in (range(ssd_count(int(v["storage"]))) if full else [0]):
				_task(tasks, "ssd_unscrew%d" % i, "unscrew", "ssd_so%d" % i, LBL_UNSCREW, start, {"ssd_so%d" % i: "out"}, {"label_arg": "M.2-SSD", "hold": 0.85})
				_task(tasks, "ssd_out%d" % i, "remove", "ssd_old%d" % i, "Alte M.2-SSD herausziehen", ["ssd_unscrew%d" % i], {"ssd_old%d" % i: "defect"})
				outs.append("ssd_out%d" % i)
			for i in (range(ssd_count(int(nv["storage"]))) if full else [0]):
				_ssd_in(tasks, i, "Neue M.2-SSD einstecken", outs, true)
		"cooling":
			_task(tasks, "pwm_unplug", "unplug", "plug_pwm", "Lüfterkabel (PWM) abziehen", start, {"plug_pwm": "unplugged"})
			_task(tasks, "wall_out", "remove", "wall_old", "Defekte Lüfterwand herausziehen", ["pwm_unplug"], {"wall_old": "defect"})
			_task(tasks, "wall_place", "place", "wall", "Neue Lüfterwand einsetzen", ["wall_out"], {"wall": "seat"}, {"hold": 0.50, "click": "clip", "kit": true})
			_task(tasks, "pwm_plug", "plug", "plug_pwm", "Lüfterkabel (PWM) anstecken", ["wall_place"], {"plug_pwm": "plugged"}, _soft())
		"psu":
			var unplugs := _power_unplug(tasks, cards, start)
			var un := _screws(tasks, "psu_out", "psu_so", 2, "Netzteil", start, false)
			_task(tasks, "psu_off", "remove", "psu_old", "Defektes Netzteil herausziehen", unplugs + un, {"psu_old": "defect"})
			_task(tasks, "psu_place", "place", "psu", "Neues Netzteil einschieben", ["psu_off"], {"psu": "seat"}, {"hold": 0.55, "kit": true})
			_screws(tasks, "psu_in", "psu_s", 2, "Netzteil", ["psu_place"])
			_power_plug(tasks, cards, ["psu_place"])
		_:
			var un: Array = []
			if has_psu:
				un += _power_unplug(tasks, cards, start)
			if int(v["cooling"]) >= 0:
				_task(tasks, "pwm_unplug", "unplug", "plug_pwm", "Lüfterkabel (PWM) abziehen", start, {"plug_pwm": "unplugged"})
				un.append("pwm_unplug")
			un += _screws(tasks, "mb_out", "mb_s", MB_SCREWS, "Mainboard", start, false)
			_task(tasks, "mb_off", "remove", "mb_old", "Defektes Mainboard herausheben", un, {"mb_old": "defect"})
			_task(tasks, "mb_place", "place", "mb", "Neues Mainboard einsetzen", ["mb_off"], {"mb": "seat"}, {"hold": 0.50, "kit": true})
			_screws(tasks, "mb_in", "mb_s", MB_SCREWS, "Mainboard", ["mb_place"])
			if has_psu:
				_power_plug(tasks, cards, ["mb_place"])
			if int(v["cooling"]) >= 0:
				_task(tasks, "pwm_plug", "plug", "plug_pwm", "Lüfterkabel (PWM) anstecken", ["mb_place"], {"plug_pwm": "plugged"}, _soft())
	_finish(tasks, not bool(ctx["known"]))


static func _power_unplug(tasks: Array, cards: int, needs: Array) -> Array:
	var out: Array = ["atx_unplug", "eps_unplug"]
	_task(tasks, "atx_unplug", "unplug", "plug_atx", "24-Pin-Stromkabel abziehen", needs, {"plug_atx": "unplugged"}, {"hold": 0.50})
	_task(tasks, "eps_unplug", "unplug", "plug_eps", "8-Pin-CPU-Kabel abziehen", needs, {"plug_eps": "unplugged"})
	for c in range(cards):
		_task(tasks, "gpu_unplug%d" % c, "unplug", "plug_gpu%d" % c, "PCIe-Stromkabel abziehen", needs, {"plug_gpu%d" % c: "unplugged"})
		out.append("gpu_unplug%d" % c)
	return out


static func _power_plug(tasks: Array, cards: int, needs: Array) -> void:
	_task(tasks, "atx_plug", "plug", "plug_atx", "24-Pin-Stromkabel einstecken", needs, {"plug_atx": "plugged"}, _soft({"hold": 0.45}))
	_task(tasks, "eps_plug", "plug", "plug_eps", "8-Pin-CPU-Kabel einstecken", needs, {"plug_eps": "plugged"}, _soft())
	for c in range(cards):
		_task(tasks, "gpu_plug%d" % c, "plug", "plug_gpu%d" % c, "PCIe-Stromkabel an die Grafikkarte stecken", needs, {"plug_gpu%d" % c: "plugged"}, _soft())


## Überholen eines laufenden Servers: Schrauben nachziehen, Wärmeleitpaste erneuern, testen.
static func _service_tasks(tasks: Array, v: Dictionary) -> void:
	_lid_off(tasks, [])
	var open := ["lid_off"]
	_screws(tasks, "mb_in", "mb_s", MB_SCREWS, "Mainboard", open)
	if int(v["cpu"]) >= 0:
		var un := _screws(tasks, "cooler_out", "cs", cooler_screws(int(v["cpu"])), "CPU-Kühler", open, false)
		_task(tasks, "cooler_off", "remove", "cooler", "CPU-Kühler abnehmen", un, {"cooler": "rest"})
		_task(tasks, "wipe", "wipe", "paste", "Alte Wärmeleitpaste abwischen", ["cooler_off"], {"paste": "off"})
		_paste_and_cooler(tasks, int(v["cpu"]), ["wipe"])
	for i in range(ssd_count(int(v["storage"]))):
		_task(tasks, "ssd_screw%d" % i, "screw", "ssd_s%d" % i, LBL_SCREW, open, {"ssd_s%d" % i: "in"}, _soft({"label_arg": "M.2-SSD", "hold": 0.85, "qgroup": "ssd"}))
	for c in range(gpu_cards(int(v["gpu"]))):
		_task(tasks, "gpu_screw%d" % c, "screw", "gpu_s%d" % c, LBL_SCREW, open, {"gpu_s%d" % c: "in"}, _soft({"label_arg": "Grafikkarte", "qgroup": "gpu"}))
	if int(v["psu"]) >= 0:
		_screws(tasks, "psu_in", "psu_s", 2, "Netzteil", open)
	_finish(tasks, false)


static func _switch_repair(tasks: Array) -> void:
	_lid_off(tasks, [])
	_task(tasks, "choose", "choose", "", "Ersatzteil wählen", [], {})
	var un := _screws(tasks, "mb_out", "mb_s", 4, "Platine", ["lid_off", "choose"], false)
	_task(tasks, "mb_off", "remove", "mb_old", "Defekte Platine herausheben", un, {"mb_old": "defect"})
	_task(tasks, "mb_place", "place", "mb", "Neue Platine einsetzen", ["mb_off"], {"mb": "seat"}, {"hold": 0.50, "kit": true})
	_screws(tasks, "mb_in", "mb_s", 4, "Platine", ["mb_place"])
	_lid_on(tasks, _ids(tasks))


## Kann man diesen Server überholen? (Switches haben nichts nachzuziehen.)
static func can_service(wb: Dictionary) -> bool:
	return str(variant(wb)["chassis"]) != "net_switch"
