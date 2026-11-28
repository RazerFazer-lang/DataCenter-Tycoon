class_name DeliveryPlan
extends RefCounted
## Lieferung: Fahrweg der Fahrzeuge, Stellplätze in der Lieferzone und der Ablauf des Abladens.
## Der Host baut den Plan einmal, alle Mitspieler spielen ihn nach der Uhr ab (reine Funktionen der Zeit).
## Alle Orte stehen in Koordinaten der Garage. Für Halle Nord kommt nur der Versatz NORD_OFFSET dazu.

const NORD_OFFSET := Vector3(-7.0, 0.0, -317.5)
const LANE_GARAGE := 16.35
const LANE_NORD := 21.4
const START_X := -58.0
const ARRIVE_DRIVE := 6.2
const ARRIVE_WAIT := 0.8
const ARRIVE_BACK := 6.4
const ARRIVE_TIME := 13.8
const DEPART_TIME := 11.2

## axle_z: Hinterachse am Stellplatz. ro/fo: Überstand hinten/vorn ab Hinterachse. bed: Ladefläche (z0, z1 ab Achse).
const VEHICLES := {
	1: {"model": "deliver_van", "axle_z": 9.80, "ro": 1.12, "fo": 4.92, "half": 1.00, "wb": 3.66, "r": 0.35, "floor": 0.63, "top": 2.45,
		"bed": Vector2(-0.95, 1.85), "bed_w": 1.72, "crew": 1, "speed": 1.0, "max_truck": 4},
	2: {"model": "deliver_truck", "axle_z": 10.45, "ro": 1.25, "fo": 5.15, "half": 1.20, "wb": 4.15, "r": 0.42, "floor": 0.95, "top": 3.1,
		"bed": Vector2(-1.15, 2.95), "bed_w": 2.15, "crew": 2, "speed": 1.12, "max_truck": 5},
	3: {"model": "deliver_heavy", "axle_z": 11.15, "ro": 1.55, "fo": 6.05, "half": 1.25, "wb": 4.95, "r": 0.50, "floor": 1.12, "top": 3.5,
		"bed": Vector2(-1.45, 3.65), "bed_w": 2.25, "crew": 3, "speed": 1.22, "max_truck": 6},
}
const LIFT_LEN := 1.32
const WALK := 1.40

## Feste Paletten für kleine Kartons (Mitte x, z).
const SMALL_PALLETS := [Vector2(-1.52, 5.72), Vector2(-1.52, 6.80)]
const PALLET_H := 0.144
## Stapelplätze für Geräte-Kartons.
const MEDIUM_SPOTS := [Vector2(1.52, 5.45), Vector2(1.52, 6.16), Vector2(1.52, 6.87), Vector2(1.52, 7.58), Vector2(-1.52, 7.72)]
## Einzelplätze für große Geräte auf Paletten. Hinten anfangen, damit niemand eingebaut wird.
const BIG_SPOTS := [Vector2(2.90, 5.60), Vector2(2.90, 6.75), Vector2(-2.90, 6.55), Vector2(2.90, 7.90), Vector2(-2.90, 7.70), Vector2(0.0, 5.60), Vector2(0.0, 6.75)]
const CART_SPOTS := [Vector2(-2.85, 8.85), Vector2(2.85, 9.0), Vector2(-0.45, 5.5), Vector2(0.45, 5.5)]
const SMALL_MAX_H := 0.95
const MEDIUM_MAX_H := 1.12


static func spec(tier: int) -> Dictionary:
	return VEHICLES[clampi(tier, 1, 3)]


static func offset(site: String) -> Vector3:
	return NORD_OFFSET if site == "halle_nord" else Vector3.ZERO


static func lane_z(site: String) -> float:
	return LANE_NORD if site == "halle_nord" else LANE_GARAGE


## z der hinteren Kante des stehenden Fahrzeugs (Garagen-Koordinaten).
static func rear_z(tier: int) -> float:
	var v := spec(tier)
	return float(v["axle_z"]) - float(v["ro"])


## Freier Bereich hinter dem Fahrzeug, in dem nichts stehen darf (z-Grenze).
static func clear_z(tier: int) -> float:
	return rear_z(tier) - (1.45 if tier == 2 else (2.0 if tier == 3 else 0.9))


## Bis hierhin dürfen Stellplätze in der Mitte reichen, damit das Personal noch durchkommt.
static func spot_limit(tier: int) -> float:
	return 8.0 if tier == 1 else 7.35


# ---------------------------------------------------------------- Fahrweg

static func turn_radius(site: String, tier: int) -> float:
	return minf(lane_z(site) - float(spec(tier)["axle_z"]), 6.6)


static func back_length(site: String, tier: int) -> float:
	var r := turn_radius(site, tier)
	return r * PI * 0.5 + (lane_z(site) - r - float(spec(tier)["axle_z"]))


## Lage der Hinterachse auf dem Rückwärtsweg. s = 0 auf der Straße, s = back_length() am Tor.
static func _back_pose(site: String, tier: int, s: float) -> Dictionary:
	var r := turn_radius(site, tier)
	var lz := lane_z(site)
	var arc := r * PI * 0.5
	var o := offset(site)
	if s <= arc:
		var a := s / r
		var steer := smoothstep(0.0, 0.14, a) * smoothstep(0.0, 0.14, PI * 0.5 - a) if s > 0.0 else 0.0
		return {"pos": o + Vector3(r - r * sin(a), 0.0, lz - r + r * cos(a)), "yaw": PI * 0.5 - a, "steer": atan(float(spec(tier)["wb"]) / r) * steer}
	return {"pos": o + Vector3(0.0, 0.0, lz - r - (s - arc)), "yaw": 0.0, "steer": 0.0}


## Lage des Fahrzeugs: {"pos", "yaw", "steer", "dir"}. dir: 1 vorwärts, -1 rückwärts, 0 steht.
static func vehicle_pose(site: String, tier: int, phase: String, t: float) -> Dictionary:
	var o := offset(site)
	var r := turn_radius(site, tier)
	var lz := lane_z(site)
	var l := back_length(site, tier)
	match phase:
		"arriving":
			if t < ARRIVE_DRIVE:
				var u := clampf(t / ARRIVE_DRIVE, 0.0, 1.0)
				return {"pos": o + Vector3(lerpf(START_X, r, 1.0 - pow(1.0 - u, 1.6)), 0.0, lz), "yaw": PI * 0.5, "steer": 0.0, "dir": 1 if u < 0.995 else 0}
			if t < ARRIVE_DRIVE + ARRIVE_WAIT:
				return {"pos": o + Vector3(r, 0.0, lz), "yaw": PI * 0.5, "steer": 0.0, "dir": 0}
			var u2 := clampf((t - ARRIVE_DRIVE - ARRIVE_WAIT) / ARRIVE_BACK, 0.0, 1.0)
			var p := _back_pose(site, tier, l * u2 * u2 * (3.0 - 2.0 * u2))
			p["dir"] = -1 if u2 > 0.001 and u2 < 0.999 else 0
			return p
		"departing":
			var d := 0.55 * maxf(0.0, t - 0.4) * maxf(0.0, t - 0.4)
			if d <= l:
				var p2 := _back_pose(site, tier, l - d)
				p2["dir"] = 1 if d > 0.0 else 0
				return p2
			return {"pos": o + Vector3(r + d - l, 0.0, lz), "yaw": PI * 0.5, "steer": 0.0, "dir": 1}
	var e := _back_pose(site, tier, l)
	e["dir"] = 0
	return e


## Grundfläche des stehenden oder fahrenden Fahrzeugs: steht der Punkt darin?
static func inside_vehicle(pose: Dictionary, tier: int, p: Vector3, grow: float) -> Vector2:
	var v := spec(tier)
	var rel := p - (pose["pos"] as Vector3)
	var yaw := float(pose["yaw"])
	var x := rel.x * cos(yaw) - rel.z * sin(yaw)
	var z := rel.x * sin(yaw) + rel.z * cos(yaw)
	var hx := float(v["half"]) + grow
	var z0 := -float(v["ro"]) - grow
	var z1 := float(v["fo"]) + grow
	if absf(x) >= hx or z <= z0 or z >= z1:
		return Vector2.ZERO
	# Kürzester Weg nach draußen, zurück in Weltkoordinaten.
	var push := Vector2(signf(x if x != 0.0 else 1.0) * (hx - absf(x)), 0.0)
	if z - z0 < absf(push.x):
		push = Vector2(0.0, z0 - z)
	elif z1 - z < absf(push.x):
		push = Vector2(0.0, z1 - z)
	return Vector2(push.x * cos(yaw) + push.y * sin(yaw), -push.x * sin(yaw) + push.y * cos(yaw))


# ---------------------------------------------------------------- Ware

## Packstück-Text ("rack", "bulk:kit_cpu:6", "build:o1", "cart", "parts_parcel") in eine Kisten-Beschreibung.
static func crate_of(item: String) -> Dictionary:
	if item.begins_with("bulk:"):
		var p := item.split(":")
		return {"item_type": p[1] if p.size() > 1 else item, "pack_count": clampi(int(p[2]) if p.size() > 2 else 1, 1, 6)}
	if item.begins_with("build:"):
		return {"item_type": "slot_build_box", "pack_count": 1}
	return {"item_type": item, "pack_count": 1}


static func dims_of(crate: Dictionary) -> Vector3:
	if str(crate.get("item_type", "")) == "cart":
		return Vector3(0.70, 1.0, 1.0)
	if str(crate.get("item_type", "")) == "empty_carton":
		return Vector3(0.64, 0.36, 0.58)
	return ShelfSpec.dims(crate)


## "parcel", "cart", "big", "medium" oder "small".
static func size_class(crate: Dictionary) -> String:
	var t := str(crate.get("item_type", ""))
	if t == GameState.VAN_PARCEL_ITEM:
		return "parcel"
	if t == "cart":
		return "cart"
	if ShelfSpec.needs_pallet(crate):
		return "big"
	var d := dims_of(crate)
	return "small" if d.x <= 0.47 and d.z <= 0.48 else "medium"


# ---------------------------------------------------------------- Stellplätze

## Stapelsäulen der kleinen Paletten: {"key", "pos", "base", "max", "half"}
static func columns(kind: String) -> Array:
	var out: Array = []
	if kind == "small":
		for p in SMALL_PALLETS.size():
			for k in 4:
				var c: Vector2 = SMALL_PALLETS[p]
				out.append({"key": "s%d%d" % [p, k], "pos": c + Vector2(-0.215 if k % 2 == 0 else 0.215, -0.245 if k < 2 else 0.245), "base": PALLET_H, "max": SMALL_MAX_H, "half": Vector2(0.19, 0.20)})
	else:
		for i in MEDIUM_SPOTS.size():
			out.append({"key": "m%d" % i, "pos": MEDIUM_SPOTS[i], "base": 0.0, "max": MEDIUM_MAX_H, "half": Vector2(0.33, 0.30)})
	return out


## Belegung der Lieferzone in Garagen-Koordinaten.
static func survey(site: String) -> Dictionary:
	var o := offset(site)
	var occ := {"stacks": {}, "rects": []}
	for c in GameState.crates.values():
		var cd: Dictionary = c
		if int(cd.get("held_by", 0)) != 0:
			continue
		var p: Vector3 = (cd["pos"] as Vector3) - o
		if absf(p.x) > 4.0 or p.z < 4.0 or p.z > 12.0:
			continue
		_occupy(occ, p, dims_of(cd), str(cd.get("stk", "")))
	for c in GameState.carts.values():
		var p2: Vector3 = ((c as Dictionary)["pos"] as Vector3) - o
		if absf(p2.x) < 4.0 and p2.z > 4.0 and p2.z < 12.0:
			(occ["rects"] as Array).append([Vector2(p2.x, p2.z), Vector2(0.40, 0.55)])
	return occ


static func _occupy(occ: Dictionary, p: Vector3, d: Vector3, key: String) -> void:
	if key != "":
		var st: Dictionary = occ["stacks"]
		st[key] = float(st.get(key, 0.0)) + d.y
	else:
		(occ["rects"] as Array).append([Vector2(p.x, p.z), Vector2(d.x, d.z) * 0.5])


static func _rect_free(occ: Dictionary, c: Vector2, half: Vector2, gap: float = 0.02) -> bool:
	for r in occ["rects"]:
		var rc: Vector2 = r[0]
		var rh: Vector2 = r[1]
		if absf(rc.x - c.x) < rh.x + half.x + gap and absf(rc.y - c.y) < rh.y + half.y + gap:
			return false
	return true


## Platz für eine Ware suchen und gleich als belegt merken.
## Ergebnis: {"pos": Vector3 (Garagen-Koordinaten), "stk": Säule, "pal": auf Palette}
static func assign(occ: Dictionary, crate: Dictionary, limit_z: float = 8.3) -> Dictionary:
	var cls := size_class(crate)
	var d := dims_of(crate)
	if cls == "parcel":
		return {"pos": Vector3(-1.05, 0.0, 7.2), "stk": "", "pal": false}
	if cls == "cart":
		for s in CART_SPOTS:
			if _rect_free(occ, s, Vector2(0.38, 0.5)):
				(occ["rects"] as Array).append([s, Vector2(0.38, 0.5)])
				return {"pos": Vector3(s.x, 0.0, s.y), "stk": "", "pal": false}
		return {"pos": Vector3(0.0, 0.0, 6.2), "stk": "", "pal": false}
	if cls == "big":
		for s in BIG_SPOTS:
			if s.y > limit_z and absf(s.x) < 2.0:
				continue
			if _rect_free(occ, s, Vector2(0.44, 0.50)) and _lane_free(occ, s):
				(occ["rects"] as Array).append([s, Vector2(0.44, 0.50)])
				return {"pos": Vector3(s.x, PALLET_H, s.y), "stk": "", "pal": true}
		for s in BIG_SPOTS:
			if _rect_free(occ, s, Vector2(0.36, 0.34)):
				(occ["rects"] as Array).append([s, Vector2(0.36, 0.34)])
				return {"pos": Vector3(s.x, 0.0, s.y), "stk": "", "pal": false}
	# Stapel: die Säulen gleichmäßig füllen, beim kleinsten Stapel anfangen.
	for kind in (["small", "medium"] if cls == "small" else ["medium"]):
		var best := {}
		var best_h := 99.0
		for col in columns(kind):
			var h := float((occ["stacks"] as Dictionary).get(col["key"], 0.0))
			if (col["pos"] as Vector2).y > limit_z or h + d.y > float(col["max"]) or not _rect_free(occ, col["pos"], col["half"]):
				continue
			if h < best_h - 0.001:
				best_h = h
				best = col
		if not best.is_empty():
			(occ["stacks"] as Dictionary)[best["key"]] = best_h + d.y
			var bp: Vector2 = best["pos"]
			return {"pos": Vector3(bp.x, float(best["base"]) + best_h, bp.y), "stk": str(best["key"]), "pal": false}
	# Notlösung: irgendwo in der Einfahrt, wo noch Platz ist. Die Mitte zuletzt.
	var spots: Array = []
	for zi in 10:
		for xi in 21:
			spots.append(Vector2(-3.2 + 0.32 * xi, 5.35 + 0.32 * zi))
	spots.sort_custom(func(a, b): return absf(a.x) - a.y * 0.05 > absf(b.x) - b.y * 0.05)
	var half := Vector2(d.x, d.z) * 0.5
	for s in spots:
		if s.y > limit_z or (absf(s.x) < 1.35 and s.y > 7.2):
			continue
		if not _rect_free(occ, s, half, 0.03):
			continue
		var on_fixed := false
		for kind in ["small", "medium"]:
			for col in columns(kind):
				var ch: Vector2 = col["half"]
				var cp: Vector2 = col["pos"]
				if absf(cp.x - s.x) < ch.x + half.x and absf(cp.y - s.y) < ch.y + half.y and (kind == "small" or float((occ["stacks"] as Dictionary).get(col["key"], 0.0)) > 0.0):
					on_fixed = true
		if on_fixed:
			continue
		(occ["rects"] as Array).append([s, half])
		return {"pos": Vector3(s.x, 0.0, s.y), "stk": "", "pal": false}
	# Alles voll: auf den niedrigsten Stapel.
	var low := {}
	var low_h := 99.0
	for col in columns("medium"):
		var h2 := float((occ["stacks"] as Dictionary).get(col["key"], 0.0))
		if h2 < low_h:
			low_h = h2
			low = col
	(occ["stacks"] as Dictionary)[low["key"]] = low_h + d.y
	var lp: Vector2 = low["pos"]
	return {"pos": Vector3(lp.x, low_h, lp.y), "stk": str(low["key"]), "pal": false}


## Kommt der Stapler von der Straße gerade an diesen Platz heran?
static func _lane_free(occ: Dictionary, s: Vector2) -> bool:
	for r in occ["rects"]:
		var rc: Vector2 = r[0]
		var rh: Vector2 = r[1]
		if rc.y > s.y and rc.y < 9.0 and absf(rc.x - s.x) < rh.x + 0.55:
			return false
	return true


## Gestapelte Kartons nachrutschen lassen, wenn weiter unten einer weggenommen wurde.
static func settle(crates: Dictionary) -> void:
	var groups: Dictionary = {}
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		if int(c.get("held_by", 0)) != 0:
			c.erase("stk")
			c.erase("pal")
			continue
		var key := str(c.get("stk", ""))
		if key == "":
			continue
		var g := ("n" if (c["pos"] as Vector3).z < -100.0 else "g") + key
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(c)
	for g in groups.keys():
		var arr: Array = groups[g]
		arr.sort_custom(func(a, b): return (a["pos"] as Vector3).y < (b["pos"] as Vector3).y)
		var y := PALLET_H if str(g).substr(1).begins_with("s") else 0.0
		for c in arr:
			var p: Vector3 = c["pos"]
			p.y = y
			c["pos"] = p
			y += dims_of(c).y


# ---------------------------------------------------------------- Ablaufplan

## Baut den kompletten Ablauf. Zeiten in Sekunden ab dem Moment, in dem das Fahrzeug steht.
static func build(site: String, tier: int, cargo: Array) -> Dictionary:
	var v := spec(tier)
	var occ := survey(site)
	var lim := spot_limit(tier)
	var order: Array = cargo.duplicate()
	var rank := {"parcel": 0, "big": 1, "medium": 2, "small": 3, "cart": 4}
	var tagged: Array = []
	for i in order.size():
		tagged.append([int(rank[size_class(crate_of(str(order[i])))]), i, str(order[i])])
	tagged.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var items: Array = []
	for e in tagged:
		var it := str(e[2])
		var cr := crate_of(it)
		var sp := assign(occ, cr, lim)
		items.append({"it": it, "cls": size_class(cr), "pos": sp["pos"], "stk": sp["stk"], "pal": sp["pal"], "d": dims_of(cr)})
	var jobs := _make_jobs(tier, items)
	_place_in_bed(tier, items)
	# Ankunft: aussteigen, nach hinten gehen, aufmachen.
	var speed := float(v["speed"])
	var t_walk := 1.2 + (float(v["wb"]) + float(v["ro"]) + 1.6) / WALK
	var t_open := t_walk + 0.2
	var t0 := t_open + (2.6 if tier == 2 else 1.6)
	if tier == 3:
		t0 += 2.6
	var free: Array = []
	for w in int(v["crew"]):
		free.append(t0 + 0.7 * float(w))
	var rear_free := t0
	var grid := _make_grid(tier, site)
	# Schweres und Leichtes laufen nebeneinander: immer das, was als Nächstes anfangen kann.
	var heavy: Array = jobs.filter(func(j): return str(j["kind"]) == "fork" or str(j["kind"]) == "jack")
	var light: Array = jobs.filter(func(j): return not (str(j["kind"]) == "fork" or str(j["kind"]) == "jack"))
	while not heavy.is_empty() or not light.is_empty():
		var take_heavy := not heavy.is_empty()
		if take_heavy and not light.is_empty():
			var wl := _pick_worker(tier, str(light[0]["kind"]), free)
			take_heavy = float(free[0]) <= float(free[wl])
		var job: Dictionary = heavy.pop_front() if take_heavy else light.pop_front()
		var w := _pick_worker(tier, str(job["kind"]), free)
		job["w"] = w
		_route(job, tier, items, grid)
		var n := (job["items"] as Array).size()
		var vel: float = WALK * speed * {"hand": 1.0, "truck": 0.92, "roll": 0.9, "jack": 0.78, "fork": 1.15}[job["kind"]]
		job["load"] = float({"hand": 1.5, "truck": 0.8 + 0.85 * n, "roll": 1.6, "jack": 5.4, "fork": 5.6}[job["kind"]]) / lerpf(1.0, speed, 0.6)
		job["go"] = maxf(0.6, _len(job["path"]) / vel) + (1.2 if str(job["kind"]) == "fork" else 0.35)
		job["drop"] = float({"hand": 1.1, "truck": 0.7 + 0.85 * n, "roll": 0.8, "jack": 1.8, "fork": 2.2}[job["kind"]]) / lerpf(1.0, speed, 0.6)
		job["back"] = maxf(0.6, _len(job["path"]) / (vel * 1.1)) + (1.2 if str(job["kind"]) == "fork" else 0.35)
		var st := float(free[w])
		# Hinten ist nur Platz für einen, solange Hubwagen oder Stapler am Werk sind.
		st = maxf(st, rear_free if tier > 1 else st)
		job["t"] = st
		rear_free = st + float(job["load"]) + (0.4 if tier > 1 else 0.0)
		free[w] = st + float(job["load"]) + float(job["go"]) + float(job["drop"]) + float(job["back"])
	var end := t0
	for f in free:
		end = maxf(end, float(f))
	if jobs.is_empty():
		end = t0 + 0.5
	var drops: Array = []
	for j in jobs:
		var job2: Dictionary = j
		var arr: Array = job2["items"]
		var d0 := float(job2["t"]) + float(job2["load"]) + float(job2["go"])
		for k in arr.size():
			var u := 1.0
			if str(job2["kind"]) == "truck":
				u = (0.7 + 0.85 * (float(k) + 0.8)) / (0.7 + 0.85 * float(arr.size()))
			else:
				u = 0.75
			drops.append([d0 + float(job2["drop"]) * u, int(arr[k])])
	drops.sort_custom(func(a, b): return a[0] < b[0])
	return {"site": site, "tier": tier, "items": items, "jobs": jobs, "drops": drops, "t_walk": t_walk, "t_open": t_open, "t0": t0, "end": end + 0.3}


static func _pick_worker(tier: int, kind: String, free: Array) -> int:
	if tier == 3 and kind == "fork":
		return 0
	if tier == 2 and kind == "jack":
		return 0
	var from := 1 if tier == 3 else 0
	var best := from
	for i in range(from, free.size()):
		if float(free[i]) < float(free[best]) - 0.001:
			best = i
	return best


static func _make_jobs(tier: int, items: Array) -> Array:
	var jobs: Array = []
	var limit := int(spec(tier)["max_truck"])
	var i := 0
	while i < items.size():
		var it: Dictionary = items[i]
		match str(it["cls"]):
			"parcel":
				jobs.append({"kind": "hand", "items": [i]})
				i += 1
			"cart":
				jobs.append({"kind": "roll", "items": [i]})
				i += 1
			"big":
				jobs.append({"kind": "truck" if tier == 1 else ("jack" if tier == 2 else "fork"), "items": [i]})
				i += 1
			_:
				var g: Array = [i]
				var h := (it["d"] as Vector3).y
				var p0: Vector3 = it["pos"]
				var j := i + 1
				while j < items.size() and g.size() < limit and str(items[j]["cls"]) == str(it["cls"]):
					var p1: Vector3 = items[j]["pos"]
					var dj := (items[j]["d"] as Vector3).y
					if absf(p1.x - p0.x) > 0.6 or absf(p1.z - p0.z) > 1.15 or h + dj > 1.05:
						break
					h += dj
					g.append(j)
					j += 1
				jobs.append({"kind": "hand" if g.size() == 1 else "truck", "items": g})
				i = j
	# Stapler und Hubwagen zuerst an den Anfang, aber die Reihenfolge der übrigen bleibt.
	return jobs


## Ladefläche: Reihen von hinten nach vorn, damit das Nächste immer an der Tür liegt.
static func _place_in_bed(tier: int, items: Array) -> void:
	var v := spec(tier)
	var bed: Vector2 = v["bed"]
	var bw := float(v["bed_w"])
	var x := -bw * 0.5
	var z := bed.x + 0.05
	var row_d := 0.0
	var y := 0.0
	var last_w := 0.0
	var top := float(v["top"]) - float(v["floor"]) - 0.15
	for e in items:
		var it: Dictionary = e
		var d: Vector3 = it["d"]
		var big := str(it["cls"]) == "big"
		var w := 0.90 if big else d.x + 0.04
		var dep := 1.0 if big else d.z + 0.05
		var h := d.y + (PALLET_H if big else 0.0)
		if big and tier > 1:
			# Große Paletten stehen mittig hintereinander, damit Gabel und Hubwagen drankommen.
			if y > 0.0 or x > -bw * 0.5:
				z += row_d
				row_d = 0.0
				x = -bw * 0.5
				y = 0.0
			it["bed"] = Vector3(0.0, 0.0, minf(z + 0.5, bed.y - 0.5))
			z += 1.02
			continue
		if not big and last_w > 0.0 and absf(last_w - w) < 0.16 and y + h < minf(top, 1.30):
			it["bed"] = Vector3(x - last_w * 0.5, y, minf(z + dep * 0.5, bed.y - dep * 0.5))
			y += h
			continue
		if x + w > bw * 0.5:
			x = -bw * 0.5
			z += row_d
			row_d = 0.0
		it["bed"] = Vector3(x + w * 0.5, 0.0, minf(z + dep * 0.5, bed.y - dep * 0.5))
		x += w
		y = h
		last_w = w if not big else 0.0
		row_d = maxf(row_d, dep)


static func _len(path: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i].distance_to(path[i - 1])
	return l


## Wo der Arbeiter hinter dem Fahrzeug steht und wohin er geht.
static func _route(job: Dictionary, tier: int, items: Array, grid: AStarGrid2D) -> void:
	var rz := rear_z(tier)
	var kind := str(job["kind"])
	var first: Dictionary = items[int((job["items"] as Array)[0])]
	var tp: Vector3 = first["pos"]
	match kind:
		"fork":
			var a := Vector2(0.0, rz - 2.05)
			var side := signf(tp.x) if absf(tp.x) > 0.5 else 1.0
			var stand := Vector2(tp.x, tp.z + 0.92)
			if absf(tp.x) > 2.0:
				job["path"] = PackedVector2Array([a, Vector2(side * 1.0, rz - 1.85), Vector2(tp.x, maxf(stand.y + 0.5, rz - 1.1)), stand])
			else:
				job["path"] = PackedVector2Array([a, Vector2(0.6, rz - 1.8), Vector2(tp.x, maxf(stand.y + 0.4, rz - 2.2)), stand])
			job["side"] = side
		"jack":
			var a2 := Vector2(0.0, rz - LIFT_LEN - 0.10)
			var stand2 := Vector2(tp.x, tp.z + 0.66)
			if absf(tp.x) > 2.0:
				job["path"] = PackedVector2Array([a2, Vector2(signf(tp.x) * 0.9, a2.y - 0.35), Vector2(tp.x, maxf(stand2.y + 0.35, a2.y - 0.1)), stand2])
			else:
				job["path"] = PackedVector2Array([a2, stand2])
		_:
			var px := 0.0 if tier == 1 else (-0.55 if int(job["w"]) % 2 == 0 else 0.55)
			var pick := Vector2(px, rz - (0.95 if kind != "hand" else 0.62))
			var stand3: Vector2
			if str(first["cls"]) == "big" or kind == "roll":
				stand3 = Vector2(tp.x, tp.z + 0.95)
			elif absf(tp.x) > 1.0:
				var off := 0.80 if kind == "truck" else 0.62
				stand3 = Vector2(tp.x - signf(tp.x) * (off + (0.10 if str(first["cls"]) == "small" else 0.12)), tp.z)
				if str(first["cls"]) == "small":
					stand3.x = -0.72
			else:
				stand3 = Vector2(tp.x, tp.z + 0.75)
			var path := _find(grid, pick, stand3)
			job["path"] = path


const CELL := 0.15
const GRID_X0 := -3.6
const GRID_Z0 := 4.75
const GRID_W := 49
const GRID_H := 66


static func _make_grid(tier: int, site: String) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, GRID_W, GRID_H)
	g.cell_size = Vector2(CELL, CELL)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	var occ := survey(site)
	for r in occ["rects"]:
		_block(g, r[0], r[1], 0.26)
	for p in SMALL_PALLETS:
		_block(g, p, Vector2(0.43, 0.49), 0.22)
	for k in (occ["stacks"] as Dictionary).keys():
		for col in columns("medium"):
			if str(col["key"]) == str(k):
				_block(g, col["pos"], col["half"], 0.24)
	var v := spec(tier)
	_block(g, Vector2(0.0, (rear_z(tier) + 15.0) * 0.5), Vector2(float(v["half"]), (15.0 - rear_z(tier)) * 0.5), 0.22)
	for bx in [-2.45, 2.45]:
		_block(g, Vector2(bx, 4.95), Vector2(0.1, 0.1), 0.22)
	return g


static func _block(g: AStarGrid2D, c: Vector2, half: Vector2, grow: float) -> void:
	var x0 := clampi(ceili((c.x - half.x - grow - GRID_X0) / CELL), 0, GRID_W - 1)
	var x1 := clampi(floori((c.x + half.x + grow - GRID_X0) / CELL), 0, GRID_W - 1)
	var z0 := clampi(ceili((c.y - half.y - grow - GRID_Z0) / CELL), 0, GRID_H - 1)
	var z1 := clampi(floori((c.y + half.y + grow - GRID_Z0) / CELL), 0, GRID_H - 1)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			g.set_point_solid(Vector2i(x, z), true)


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(roundi((p.x - GRID_X0) / CELL), 0, GRID_W - 1), clampi(roundi((p.y - GRID_Z0) / CELL), 0, GRID_H - 1))


static func _free_cell(g: AStarGrid2D, c: Vector2i) -> Vector2i:
	if not g.is_point_solid(c):
		return c
	for r in range(1, 12):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dz)
				if q.x >= 0 and q.y >= 0 and q.x < GRID_W and q.y < GRID_H and not g.is_point_solid(q):
					return q
	return c


## Weg um alle Hindernisse, geglättet. Endpunkte bleiben exakt.
static func _find(g: AStarGrid2D, a: Vector2, b: Vector2) -> PackedVector2Array:
	var ids := g.get_id_path(_free_cell(g, _cell(a)), _free_cell(g, _cell(b)), true)
	var pts := PackedVector2Array([a])
	for id in ids:
		pts.append(Vector2(GRID_X0 + float(id.x) * CELL, GRID_Z0 + float(id.y) * CELL))
	pts.append(b)
	# Unnötige Zwischenpunkte weglassen (Sichtlinie prüfen).
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _clear_line(g, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


static func _clear_line(g: AStarGrid2D, a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / (CELL * 0.5))
	for k in range(1, n):
		if g.is_point_solid(_cell(a.lerp(b, float(k) / float(n)))):
			return false
	return true


## Punkt und Richtung auf dem Weg. u = 0..1
static func along(path: PackedVector2Array, u: float) -> Array:
	if path.is_empty():
		return [Vector2.ZERO, Vector2(0, -1)]
	if path.size() == 1:
		return [path[0], Vector2(0, -1)]
	var want := _len(path) * clampf(u, 0.0, 1.0)
	for i in range(1, path.size()):
		var seg := path[i].distance_to(path[i - 1])
		if want <= seg and seg > 0.0001:
			return [path[i - 1].lerp(path[i], want / seg), (path[i] - path[i - 1]).normalized()]
		want -= seg
	return [path[path.size() - 1], (path[path.size() - 1] - path[path.size() - 2]).normalized()]
