class_name StripRules
extends RefCounted
## Steckleisten mit Ein- und Ausgang an der Seite.
##   Oben:   Buchsen für Geräte (Strom 6, LAN 8)
##   Links:  Eingang (Schalterseite, weiß)   – Strom kommt vom Kasten, Router oder der Leiste davor
##   Rechts: Ausgang (Anzeigeseite, rot)     – führt zur nächsten Leiste
## Leisten hängen nur über die Seiten aneinander: per Kabel oder direkt zusammengesteckt.

const POWER_TOP := 6
const LAN_TOP := 8
## Abstand der Mitten zweier zusammengesteckter Leisten (Gehäuse 0,71 m + Stecker).
const LINK_PITCH := 0.74
## Seitenbuchsen in Leisten-Koordinaten (Ausgang +X, Eingang -X).
const SIDE_X := 0.371
const SIDE_Y := 0.026
const LINK_TOL := 0.05
## Grenzen: jede Leiste für sich, jede Kette am Abgang des Sicherungskastens.
const STRIP_LIMIT_W := 11000
const CHAIN_LIMIT_W := 22000


static func top_count(ctype: String) -> int:
	return POWER_TOP if ctype == "power" else LAN_TOP


static func in_slot(ctype: String) -> int:
	return top_count(ctype)


static func out_slot(ctype: String) -> int:
	return top_count(ctype) + 1


static func strip_item(ctype: String) -> String:
	return "prop_power_strip" if ctype == "power" else "prop_lan_strip"


static func is_strip(ctype: String, eid: String) -> bool:
	var d: Variant = _gs().decor_items.get(eid)
	return d is Dictionary and str((d as Dictionary).get("item_type", "")) == strip_item(ctype)


## Rolle eines Anschlusses für eine Kabelart: source, strip, ups, hub, device oder "".
static func role(ctype: String, eid: String) -> String:
	if ctype == "power":
		if eid == _gs().WALL_BREAKER_ID or eid == _gs().HALL_C_BREAKER_ID or eid == _gs().HALL_NORD_BREAKER_ID:
			return "source"
		if is_strip(ctype, eid):
			return "strip"
		if _gs().ups_units.has(eid):
			return "ups"
		if _gs().racks.has(eid) or _gs().coolers.has(eid):
			return "device"
		return ""
	if ctype == "network":
		if eid == _gs().WALL_ROUTER_ID or eid == _gs().HALL_C_ROUTER_ID or eid == _gs().HALL_NORD_ROUTER_ID:
			return "source"
		if is_strip(ctype, eid):
			return "strip"
		if _gs().racks.has(eid):
			# Racks mit eingebautem Switch verteilen weiter wie bisher.
			return "hub" if _gs()._count_rack_switches(eid) > 0 else "device"
	return ""


static func slot_kind(ctype: String, eid: String, slot: int) -> String:
	if role(ctype, eid) != "strip" or slot < 0:
		return ""
	if slot == in_slot(ctype):
		return "in"
	if slot == out_slot(ctype):
		return "out"
	return "top"


# ------------------------------------------------------------------ Direkt gesteckte Leisten

## Weltpunkt einer Seitenbuchse aus den gespeicherten Daten (geht auch ohne 3D-Szene).
static func side_point(d: Dictionary, out_side: bool) -> Vector3:
	var yaw := Basis(Vector3.UP, float(d.get("rot_y", 0.0)))
	var b := yaw * Basis(Vector3.RIGHT, PI * 0.5) if bool(d.get("wall", false)) else yaw
	return (d.get("pos", Vector3.ZERO) as Vector3) + b * Vector3(SIDE_X if out_side else -SIDE_X, SIDE_Y, 0.0)


static func axis(d: Dictionary) -> Vector3:
	return Basis(Vector3.UP, float(d.get("rot_y", 0.0))) * Vector3.RIGHT


## Paare [Leiste mit Ausgang, Leiste mit Eingang], die direkt aneinanderstecken.
static func links(ctype: String) -> Array:
	var ids: Array = []
	for did in _gs().decor_items.keys():
		if is_strip(ctype, str(did)):
			ids.append(str(did))
	ids.sort()
	var out: Array = []
	for a in ids:
		var da: Dictionary = _gs().decor_items[a]
		var pa := side_point(da, true)
		for b in ids:
			if a == b:
				continue
			var db: Dictionary = _gs().decor_items[b]
			if bool(da.get("wall", false)) != bool(db.get("wall", false)):
				continue
			if absf(angle_difference(float(da.get("rot_y", 0.0)), float(db.get("rot_y", 0.0)))) > 0.05:
				continue
			if pa.distance_to(side_point(db, false)) < LINK_TOL:
				out.append([a, b])
	return out


## Wo eine neue Leiste an eine vorhandene gesteckt würde. Leer = keine in der Nähe.
## Ergebnis: {pos, rot_y, wall, other, out_side} (out_side: die neue sitzt am Ausgang der vorhandenen).
static func snap_spot(ctype: String, pos: Vector3, wall: bool, ignore_id: String = "") -> Dictionary:
	var best := {}
	var best_d := 0.22
	for did in _gs().decor_items.keys():
		if str(did) == ignore_id or not is_strip(ctype, str(did)):
			continue
		var d: Dictionary = _gs().decor_items[did]
		if bool(d.get("wall", false)) != wall:
			continue
		for out_side in [true, false]:
			var cand := (d["pos"] as Vector3) + axis(d) * (LINK_PITCH if out_side else -LINK_PITCH)
			var dist := cand.distance_to(pos)
			if dist < best_d and not _side_taken(ctype, str(did), out_side):
				best_d = dist
				best = {"pos": cand, "rot_y": float(d.get("rot_y", 0.0)), "wall": wall, "other": str(did), "out_side": out_side}
	return best


static func _side_taken(ctype: String, did: String, out_side: bool) -> bool:
	return slot_used(ctype, did, out_slot(ctype) if out_side else in_slot(ctype))


static func is_linked(ctype: String, did: String, slot: int) -> bool:
	if slot != in_slot(ctype) and slot != out_slot(ctype):
		return false
	for l in links(ctype):
		if (slot == out_slot(ctype) and l[0] == did) or (slot == in_slot(ctype) and l[1] == did):
			return true
	return false


static func slot_used(ctype: String, eid: String, slot: int) -> bool:
	if not _gs().get_cable_on_slot(ctype, eid, slot).is_empty():
		return true
	return role(ctype, eid) == "strip" and is_linked(ctype, eid, slot)


static func _first_free_top(ctype: String, eid: String) -> int:
	for i in top_count(ctype):
		if not slot_used(ctype, eid, i):
			return i
	return -1


# ------------------------------------------------------------------ Welche Buchse für ein neues Kabel?

## {ok, a_slot, b_slot, msg}. a_slot/b_slot = -1 heißt: wie bisher frei wählen (keine Leiste beteiligt).
static func plan(ctype: String, a: String, sa: int, b: String, sb: int) -> Dictionary:
	if ctype == "cluster":
		return {"ok": true, "a_slot": sa, "b_slot": sb, "msg": ""}
	var ra := role(ctype, a)
	var rb := role(ctype, b)
	# Ohne Leiste: Geräte geben keinen Strom weiter.
	if ra != "strip" and rb != "strip":
		if ctype == "power" and ra == "device" and rb == "device":
			return _no("Racks und Kühlgeräte geben keinen Strom weiter. Schließe sie an eine Stromleiste oder den Kasten an.")
		if ctype == "power" and ra == "source" and rb == "source":
			return _no("Zwei Stromkästen lassen sich nicht verbinden.")
		return {"ok": true, "a_slot": sa, "b_slot": sb, "msg": ""}
	if ra == "strip" and rb == "strip":
		return _plan_two_strips(ctype, a, sa, b, sb)
	var flip := rb == "strip"
	var s := b if flip else a
	var ss := sb if flip else sa
	var o_role := ra if flip else rb
	var r := _plan_strip_other(ctype, s, ss, o_role)
	if not bool(r["ok"]):
		return r
	return {"ok": true, "a_slot": sa if flip else int(r["slot"]), "b_slot": int(r["slot"]) if flip else sb, "msg": ""}


## Falsch gezielt (z. B. Kasten auf eine Steckdose oben) kommt das Kabel an die richtige Buchse, wenn sie frei ist.
static func _plan_strip_other(ctype: String, s: String, ss: int, o_role: String) -> Dictionary:
	var kind := slot_kind(ctype, s, ss)
	var into_in := o_role == "source" or ((o_role == "ups" or o_role == "hub") and kind == "in")
	if into_in:
		if slot_used(ctype, s, in_slot(ctype)):
			return _no("Der Eingang dieser Leiste ist schon belegt.")
		return {"ok": true, "slot": in_slot(ctype)}
	if kind == "top" and not slot_used(ctype, s, ss):
		return {"ok": true, "slot": ss}
	var free := _first_free_top(ctype, s)
	if free < 0:
		return _no("Alle Buchsen oben sind belegt. Hänge seitlich eine weitere Leiste an.")
	return {"ok": true, "slot": free}


static func _plan_two_strips(ctype: String, a: String, sa: int, b: String, sb: int) -> Dictionary:
	var ka := slot_kind(ctype, a, sa)
	var kb := slot_kind(ctype, b, sb)
	# Oben gezielt: wie ohne Wahl, die Seiten werden genommen.
	if ka == "top":
		ka = ""
	if kb == "top":
		kb = ""
	var options: Array = []
	if ka != "in" and kb != "out":
		options.append([out_slot(ctype), in_slot(ctype)])
	if ka != "out" and kb != "in":
		options.append([in_slot(ctype), out_slot(ctype)])
	if (ka == "in" and kb == "in") or (ka == "out" and kb == "out"):
		return _no("Immer Ausgang (rot) mit Eingang (weiß) verbinden.")
	for o in options:
		if not slot_used(ctype, a, int(o[0])) and not slot_used(ctype, b, int(o[1])):
			if _would_loop(ctype, a, int(o[0]), b):
				return _no("Das wäre ein Ring: die Leiste speist sich selbst.")
			return {"ok": true, "a_slot": int(o[0]), "b_slot": int(o[1]), "msg": ""}
	return _no("Die passende Seite ist schon belegt.")


## Würde die Verbindung einen Kreis ergeben? Ausgang von a → Eingang von b (oder umgekehrt).
static func _would_loop(ctype: String, a: String, a_slot: int, b: String) -> bool:
	var up := b if a_slot == out_slot(ctype) else a
	var down := a if a_slot == out_slot(ctype) else b
	# Hängt "up" schon (über Eingänge zurück) an "down"?
	var cur := up
	for i in 128:
		var feeder := upstream_strip(ctype, cur)
		if feeder == "":
			return false
		if feeder == down:
			return true
		cur = feeder
	return true


## Leiste, die über den Eingang in diese Leiste speist, sonst "".
static func upstream_strip(ctype: String, did: String) -> String:
	for e in edges(ctype):
		if e[2] == did and int(e[3]) == in_slot(ctype) and is_strip(ctype, e[0]):
			return e[0]
		if e[0] == did and int(e[1]) == in_slot(ctype) and is_strip(ctype, e[2]):
			return e[2]
	return ""


static func _no(msg: String) -> Dictionary:
	return {"ok": false, "a_slot": -1, "b_slot": -1, "msg": msg}


# ------------------------------------------------------------------ Graph für die Verteilung

## Alle Verbindungen einer Art: [a, a_slot, b, b_slot] aus Kabeln und gesteckten Leisten.
static func edges(ctype: String) -> Array:
	var out: Array = []
	var maps := {}
	for cid in _gs().cables.keys():
		var c: Dictionary = _gs().cables[cid]
		if str(c.get("cable_type", "")) != ctype:
			continue
		var a := str(c["from_id"])
		var b := str(c["to_id"])
		for e in [a, b]:
			if not maps.has(e):
				maps[e] = _gs().get_cable_slot_map(ctype, e)
		out.append([a, int((maps[a] as Dictionary).get(str(cid), -1)), b, int((maps[b] as Dictionary).get(str(cid), -1))])
	if ctype == "power" or ctype == "network":
		for l in links(ctype):
			out.append([l[0], out_slot(ctype), l[1], in_slot(ctype)])
	return out


## Darf Strom/Netz über diese Verbindung von cur zu other fließen?
static func flows(ctype: String, cur: String, cur_slot: int, other: String, other_slot: int) -> bool:
	var rc := role(ctype, cur)
	var ro := role(ctype, other)
	if rc == "strip":
		if cur_slot == in_slot(ctype):
			return false
		if ro == "strip" and (cur_slot != out_slot(ctype) or other_slot != in_slot(ctype)):
			return false
	if ro == "strip" and other_slot != in_slot(ctype):
		return false
	if ctype == "power" and rc == "device":
		return false
	return true


## Spielzustand ohne festen Bezug: GameState lädt dieses Skript selbst, ein direkter Verweis wäre ein Kreis.
static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")
