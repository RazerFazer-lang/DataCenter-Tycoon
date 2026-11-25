class_name DecorSpec
extends RefCounted
## Maße und Modelle der Einrichtung sowie die Regeln fürs Aufstellen (Rechtecke statt Kreise).

## Breite, Höhe, Tiefe. Vorderseite zeigt nach +Z.
const SIZES := {
	"prop_shelf_small": Vector3(1.58, 1.84, 0.50),
	"prop_storage_shelf": Vector3(1.97, 2.14, 0.68),
	"prop_pallet_rack": Vector3(3.04, 2.46, 1.06),
	"prop_esd_workbench": Vector3(1.60, 1.70, 0.84),
	"prop_parts_cabinet": Vector3(1.16, 2.06, 0.60),
	"prop_cold_aisle_gate": Vector3(2.28, 2.60, 0.26),
	"prop_vending_lounge": Vector3(0.98, 1.96, 0.82),
	"prop_cctv_monitor": Vector3(0.50, 2.55, 0.42),
	"prop_sofa": Vector3(2.10, 0.82, 0.92),
	"prop_water": Vector3(0.36, 1.32, 0.40),
	"prop_tool_cart": Vector3(0.78, 1.04, 0.50),
	"prop_dehumidifier": Vector3(0.62, 1.02, 0.56),
	"prop_logo_sign": Vector3(1.80, 0.46, 0.12),
}
const MODELS := {
	"prop_shelf_small": "shelf_small", "prop_storage_shelf": "shelf_heavy", "prop_pallet_rack": "shelf_pallet",
	"prop_esd_workbench": "decor_esd_workbench", "prop_parts_cabinet": "decor_parts_cabinet",
	"prop_cold_aisle_gate": "decor_cold_aisle_gate", "prop_vending_lounge": "decor_vending_lounge",
	"prop_cctv_monitor": "decor_cctv_monitor", "prop_sofa": "decor_sofa", "prop_water": "decor_water",
	"prop_tool_cart": "decor_tool_cart", "prop_dehumidifier": "decor_dehumidifier", "prop_logo_sign": "decor_logo_sign",
}
## Diese Stücke rasten mit dem Rücken an der Wand ein.
const WALL_SNAP: Array[String] = [
	"prop_shelf_small", "prop_storage_shelf", "prop_pallet_rack", "prop_esd_workbench", "prop_parts_cabinet",
	"prop_vending_lounge", "prop_water", "prop_sofa", "prop_dehumidifier", "prop_tool_cart",
]
## Diese Stücke rasten nebeneinander ein.
const SIDE_SNAP: Array[String] = ["prop_shelf_small", "prop_storage_shelf", "prop_pallet_rack", "prop_parts_cabinet", "prop_vending_lounge"]
const WALL_GAP := 0.015
const SNAP_DIST := 0.55
const SIDE_DIST := 0.45
const GRID := 0.05
const SIGN_MIN_Y := 1.50
const SIGN_MAX_Y := 2.85

## Fest verbaute Dinge in der Garage: [x, z, halbe Breite x, halbe Tiefe z].
const GARAGE_BLOCKS := [
	[2.77, -3.55, 1.24, 1.00], [4.55, -4.02, 0.62, 0.50], [-4.95, 2.25, 0.46, 0.84], [-5.30, -3.62, 0.24, 0.50],
	[0.0, 3.60, 2.25, 0.95], [15.5, -3.9, 2.0, 0.65], [-5.28, 0.25, 0.62, 1.05], [-5.0, 3.65, 0.75, 0.55],
]
const GARAGE_COLUMNS_X := [-5.28, -2.05, 1.85, 5.50, 9.00, 12.50, 17.85, 21.28]
const NORD_BLOCKS := [[7.1, -4.1, 2.8, 1.85], [-6.9, -5.2, 3.2, 0.75], [3.2, -5.1, 0.9, 0.85], [0.0, 5.0, 2.35, 1.0]]


static func footprint(item_type: String) -> Vector2:
	var s: Vector3 = SIZES.get(item_type, Vector3(0.6, 1.0, 0.6))
	return Vector2(s.x, s.z)


static func is_wall_sign(item_type: String) -> bool:
	return item_type == "prop_logo_sign"


## Überlappen sich zwei gedrehte Rechtecke? (Mitte, halbe Größe, Drehung)
static func rects_overlap(c1: Vector2, h1: Vector2, r1: float, c2: Vector2, h2: Vector2, r2: float, gap: float = 0.0) -> bool:
	# Drehung um Y in Godot: lokales X zeigt nach (cos r, -sin r).
	var ax := [Vector2(cos(r1), -sin(r1)), Vector2(sin(r1), cos(r1)), Vector2(cos(r2), -sin(r2)), Vector2(sin(r2), cos(r2))]
	var d := c2 - c1
	for a_v in ax:
		var a: Vector2 = a_v
		var e1 := absf(a.dot(ax[0])) * h1.x + absf(a.dot(ax[1])) * h1.y
		var e2 := absf(a.dot(ax[2])) * h2.x + absf(a.dot(ax[3])) * h2.y
		if absf(d.dot(a)) >= e1 + e2 + gap - 0.004:
			return false
	return true


static func corners(pos: Vector3, rot: float, fp: Vector2) -> Array[Vector2]:
	var ax := Vector2(cos(rot), -sin(rot)) * fp.x * 0.5
	var az := Vector2(sin(rot), cos(rot)) * fp.y * 0.5
	var c := Vector2(pos.x, pos.z)
	return [c + ax + az, c + ax - az, c - ax + az, c - ax - az]


## Wandflächen: Normale, Ebene, Bereich. Nur Wände, an denen man Dinge aufstellen kann.
static func walls(nord: bool) -> Array:
	if nord:
		var oz: float = GameState.HALLE_NORD_ORIGIN.z
		return [
			{"n": Vector2(0, 1), "at": oz - 5.86}, {"n": Vector2(0, -1), "at": oz + 5.86},
			{"n": Vector2(1, 0), "at": -9.86}, {"n": Vector2(-1, 0), "at": 9.86},
		]
	return [
		{"n": Vector2(0, 1), "at": GameState.WALL_FACE_NORTH_Z}, {"n": Vector2(0, -1), "at": GameState.WALL_FACE_SOUTH_Z},
		{"n": Vector2(1, 0), "at": GameState.WALL_FACE_WEST_X}, {"n": Vector2(-1, 0), "at": GameState._interior_max_x()},
	]


## Lage fürs Aufstellen: feines Raster, an Wände und an gleiche Nachbarn eingerastet.
## keep_rot: der Spieler hat selbst gedreht. Dann rasten nur Wände ein, zu denen die Drehung passt.
static func snap_pose(item_type: String, pos: Vector3, rot: float, ignore_id: String = "", keep_rot: bool = false) -> Dictionary:
	var nord: bool = GameState.halle_nord_owned and pos.z < -100.0
	var fp := footprint(item_type)
	var p := Vector3(snappedf(pos.x, GRID), 0.0, snappedf(pos.z, GRID))
	var r := rot
	if WALL_SNAP.has(item_type):
		var best := SNAP_DIST
		var found := {}
		for w in walls(nord):
			var n: Vector2 = w["n"]
			if keep_rot and absf(angle_difference(atan2(n.x, n.y), rot)) > 0.1:
				continue
			var dist: float = (p.x - float(w["at"])) * n.x if n.x != 0.0 else (p.z - float(w["at"])) * n.y
			var back := dist - fp.y * 0.5
			if absf(back) < best or (dist > 0.0 and back < 0.0 and dist < best + fp.y * 0.5):
				best = absf(back)
				found = w
		if not found.is_empty():
			var n2: Vector2 = found["n"]
			r = atan2(n2.x, n2.y)
			var off := fp.y * 0.5 + WALL_GAP
			if n2.x != 0.0:
				p.x = float(found["at"]) + n2.x * off
			else:
				p.z = float(found["at"]) + n2.y * off
	if SIDE_SNAP.has(item_type):
		for did in GameState.decor_items.keys():
			if str(did) == ignore_id:
				continue
			var d: Dictionary = GameState.decor_items[did]
			var ot := str(d.get("item_type", ""))
			if not SIDE_SNAP.has(ot):
				continue
			var or_y := float(d.get("rot_y", 0.0))
			if absf(angle_difference(or_y, r)) > 0.1:
				continue
			var op: Vector3 = d["pos"]
			var ofp := footprint(ot)
			var ax := Vector3(cos(or_y), 0.0, -sin(or_y))
			var az := Vector3(sin(or_y), 0.0, cos(or_y))
			var delta := p - op
			var along := delta.dot(ax)
			var across := delta.dot(az)
			var want := (fp.x + ofp.x) * 0.5 + 0.002
			# Rücken bündig: unterschiedliche Tiefen gleichen sich hinten aus.
			var back_off := (fp.y - ofp.y) * 0.5
			if absf(absf(along) - want) < SIDE_DIST and absf(across - back_off) < SIDE_DIST:
				p = op + ax * signf(along) * want + az * back_off
				r = or_y
				break
	return {"pos": p, "rot_y": r}


static func can_place(item_type: String, pos: Vector3, rot: float, ignore_id: String = "") -> bool:
	var nord: bool = GameState.halle_nord_owned and pos.z < -100.0
	var fp := footprint(item_type)
	var c := Vector2(pos.x, pos.z)
	var half := fp * 0.5
	var oz: float = GameState.HALLE_NORD_ORIGIN.z if nord else 0.0
	var lo := Vector2(-9.86, oz - 5.86) if nord else Vector2(GameState.WALL_FACE_WEST_X, GameState.WALL_FACE_NORTH_Z)
	var hi := Vector2(9.86, oz + 5.86) if nord else Vector2(GameState._interior_max_x(), GameState.WALL_FACE_SOUTH_Z)
	for k in corners(pos, rot, fp):
		if k.x < lo.x - 0.004 or k.x > hi.x + 0.004 or k.y < lo.y - 0.004 or k.y > hi.y + 0.004:
			return false
	var blocks: Array = NORD_BLOCKS if nord else GARAGE_BLOCKS
	for b in blocks:
		if rects_overlap(c, half, rot, Vector2(float(b[0]), float(b[1]) + oz), Vector2(float(b[2]), float(b[3])), 0.0):
			return false
	if not nord:
		for cx in GARAGE_COLUMNS_X:
			for cz in [-4.34, 4.34]:
				if rects_overlap(c, half, rot, Vector2(float(cx), float(cz)), Vector2(0.15, 0.15), 0.0):
					return false
		# Stromkasten, Router und Feuerlöscher an der Wand bleiben erreichbar (niedrige Möbel dürfen darunter)
		var tall: float = (SIZES.get(item_type, Vector3.ONE) as Vector3).y
		for k in GameState.STRIP_WALL_KEEPOUT:
			if tall > float(k[2]) - float(k[4]) and rects_overlap(c, half, rot, Vector2(float(k[1]), float(k[0]) + 0.35), Vector2(float(k[3]) - 0.10, 0.35), 0.0):
				return false
		# Trennwände der Hallen nicht zustellen
		for dx in ([5.50, 12.50] if GameState.room_level >= 1 else []):
			if rects_overlap(c, half, rot, Vector2(float(dx), 0.0), Vector2(0.25, 1.6), 0.0):
				return false
	return not overlaps_things(c, half, rot, ignore_id, 0.02, nord)


## Steht hier schon ein Rack, Gerät oder anderes Einrichtungsstück?
static func overlaps_things(c: Vector2, half: Vector2, rot: float, ignore_id: String, gap: float, nord: bool) -> bool:
	for rid in GameState.racks.keys():
		var r: Dictionary = GameState.racks[rid]
		if str(rid) != ignore_id and _hit(c, half, rot, r, Vector2(0.45, 0.49), gap):
			return true
	for uid in GameState.ups_units.keys():
		var u: Dictionary = GameState.ups_units[uid]
		var us: Vector3 = UpsProp.SIZES.get(str(u.get("ups_type", "ups")), Vector3(0.5, 1, 0.64))
		if _hit(c, half, rot, u, Vector2(us.x, us.z) * 0.5, gap):
			return true
	for cid in GameState.coolers.keys():
		var cl: Dictionary = GameState.coolers[cid]
		var ct := str(cl.get("cooler_type", ""))
		if not GameState.is_floor_cooler_type(ct):
			continue
		var cs: Vector3 = CoolerProp.GHOST_SIZES.get(ct, Vector3(0.8, 2, 0.98))
		if _hit(c, half, rot, cl, Vector2(cs.x, cs.z) * 0.5, gap):
			return true
	for did in GameState.decor_items.keys():
		if str(did) == ignore_id:
			continue
		var d: Dictionary = GameState.decor_items[did]
		var dt := str(d.get("item_type", ""))
		if not SIZES.has(dt) or is_wall_sign(dt):
			continue
		if _hit(c, half, rot, d, footprint(dt) * 0.5, 0.0):
			return true
	return false


static func _hit(c: Vector2, half: Vector2, rot: float, e: Dictionary, eh: Vector2, gap: float) -> bool:
	var p: Vector3 = e.get("pos", Vector3.ZERO)
	return rects_overlap(c, half, rot, Vector2(p.x, p.z), eh, float(e.get("rot_y", 0.0)), gap)


## Platz für das Leuchtschild an der Wand. Leer = geht nicht.
static func sign_spot(hit: Vector3, normal: Vector3) -> Dictionary:
	if absf(normal.y) > 0.3:
		return {}
	var nord: bool = GameState.halle_nord_owned and hit.z < -100.0
	var n := Vector2(signf(normal.x), 0.0) if absf(normal.x) > absf(normal.z) else Vector2(0.0, signf(normal.z))
	var y := clampf(snappedf(hit.y, 0.05), SIGN_MIN_Y, SIGN_MAX_Y)
	for w in walls(nord):
		if not (w["n"] as Vector2).is_equal_approx(n):
			continue
		var at := float(w["at"])
		if absf((hit.x if n.x != 0.0 else hit.z) - at) > 0.35:
			continue
		var pos := Vector3(at + n.x * 0.062, y, snappedf(hit.z, 0.1)) if n.x != 0.0 else Vector3(snappedf(hit.x, 0.1), y, at + n.y * 0.062)
		return {"pos": pos, "rot_y": atan2(n.x, n.y)}
	return {}


static func can_place_sign(pos: Vector3, rot: float, ignore_id: String = "") -> bool:
	var n := Vector3(sin(rot), 0.0, cos(rot)).round()
	var spot := sign_spot(pos, n)
	if spot.is_empty() or (spot["pos"] as Vector3).distance_to(pos) > 0.12:
		return false
	var nord: bool = GameState.halle_nord_owned and pos.z < -100.0
	var lz: float = pos.z - (GameState.HALLE_NORD_ORIGIN.z if nord else 0.0)
	var along := pos.x if absf(n.z) > 0.5 else lz
	if absf(n.z) > 0.5:
		var lo := -9.0 if nord else -4.6
		var hi: float = 9.0 if nord else GameState._interior_max_x() - 0.95
		if along < lo or along > hi:
			return false
		# Über den Toren und beim Firmenschild über dem PC bleibt frei
		if n.z < 0.0 and absf(pos.x) < 3.2:
			return false
		if not nord and n.z > 0.0 and absf(pos.x - 3.0) < 2.2 and pos.y > 2.3:
			return false
		for k in GameState.STRIP_WALL_KEEPOUT:
			if not nord and absf(pos.z - float(k[0])) < 0.3 and absf(pos.x - float(k[1])) < float(k[3]) + 0.92 and absf(pos.y - float(k[2])) < float(k[4]) + 0.25:
				return false
	elif absf(along) > (4.9 if nord else 3.4):
		return false
	for did in GameState.decor_items.keys():
		var d: Dictionary = GameState.decor_items[did]
		if str(did) == ignore_id or not is_wall_sign(str(d.get("item_type", ""))):
			continue
		if (d["pos"] as Vector3).distance_to(pos) < 1.9:
			return false
	for cid in GameState.coolers.keys():
		var cl: Dictionary = GameState.coolers[cid]
		if str(cl.get("cooler_type", "")) == GameState.INDOOR_UNIT_TYPE and (cl["pos"] as Vector3).distance_to(pos) < 1.45:
			return false
	return true
