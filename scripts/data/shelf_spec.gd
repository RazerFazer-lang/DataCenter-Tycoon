class_name ShelfSpec
extends RefCounted
## Maße der drei Lagerregale und der Ware. Ein Fach ist cols Einheiten breit, jede Ware belegt
## so viele Einheiten nebeneinander, wie sie wirklich breit ist. Höhe und Tiefe müssen auch passen.
## Index einer Einheit: Ebene * cols + Spalte (Ebene 0 unten, Spalte 0 links).

const SPECS := {
	"prop_shelf_small": {
		"model": "shelf_small", "cols": 4, "unit_w": 0.37, "depth": 0.46, "levels": [0.10, 0.52, 0.94, 1.36],
		"clear": 0.37, "size": Vector3(1.58, 1.84, 0.50), "pallet": false,
	},
	"prop_storage_shelf": {
		"model": "shelf_heavy", "cols": 5, "unit_w": 0.37, "depth": 0.64, "levels": [0.12, 0.71, 1.30, 1.89],
		"clear": 0.54, "size": Vector3(1.97, 2.14, 0.68), "pallet": false,
	},
	"prop_pallet_rack": {
		"model": "shelf_pallet", "cols": 3, "unit_w": 0.94, "depth": 1.02, "levels": [0.0, 1.46],
		"clear": 1.28, "size": Vector3(3.04, 2.46, 1.06), "pallet": true,
	},
}
const PALLET_H := 0.144

## Große Geräte kommen auf Paletten und passen nur ins Palettenregal.
const PALLET_GOODS: Array[String] = [
	"rack", "rack_pro", "ups_cabinet", "ups_container", "chiller", "cool_k90", "cool_tower", "cool_inrow", "cool_cdu",
	"prop_storage_shelf", "prop_pallet_rack", "prop_esd_workbench", "prop_parts_cabinet", "prop_cold_aisle_gate",
	"prop_vending_lounge", "prop_sofa",
]


static func is_shelf(item_type: String) -> bool:
	return SPECS.has(item_type)


static func unit_count(item_type: String) -> int:
	var s: Dictionary = SPECS[item_type]
	return int(s["cols"]) * (s["levels"] as Array).size()


## Breite, Höhe, Tiefe einer Ware in Metern.
static func dims(crate: Dictionary) -> Vector3:
	var t := str(crate.get("item_type", ""))
	if int(crate.get("pack_count", 1)) > 1:
		return Vector3(0.45, 0.26, 0.37)
	if t.begins_with("kit_"):
		return Vector3(0.36, 0.135, 0.30)
	if t == "server_tray":
		return Vector3(0.47, 0.10, 0.43)
	if t == "old_fuse":
		return Vector3(0.10, 0.08, 0.10)
	var kind := CartonFactory.kind_for(t)
	var s: Array = CartonFactory.SIZES[kind]
	return Vector3(float(s[0]), float(s[1]) + float(s[3]) + 0.012, float(s[2]))


static func needs_pallet(crate: Dictionary) -> bool:
	return PALLET_GOODS.has(str(crate.get("item_type", ""))) and int(crate.get("pack_count", 1)) <= 1


## Wie viele Einheiten nebeneinander die Ware in diesem Regal braucht. 0 = passt nicht.
static func span(shelf_type: String, crate: Dictionary) -> int:
	var s: Dictionary = SPECS.get(shelf_type, {})
	if s.is_empty():
		return 0
	var t := str(crate.get("item_type", ""))
	if t == "empty_carton" or t == "cart":
		return 0
	if bool(s["pallet"]):
		return 1
	if needs_pallet(crate):
		return 0
	var d := dims(crate)
	if d.z > float(s["depth"]) + 0.02 or d.y > float(s["clear"]):
		return 0
	var n := ceili((d.x - 0.005) / float(s["unit_w"]))
	return n if n <= int(s["cols"]) else 0


## Liste der Einheiten auf die richtige Länge bringen.
static func units(d: Dictionary) -> Array:
	var t := str(d.get("item_type", ""))
	var n := unit_count(t)
	var raw: Variant = d.get("stored_items", [])
	var arr: Array = raw if raw is Array else []
	while arr.size() < n:
		arr.append(null)
	d["stored_items"] = arr
	return arr


## Start-Einheit der Ware, die diese Einheit belegt, sonst -1.
static func owner_of(d: Dictionary, idx: int) -> int:
	var t := str(d.get("item_type", ""))
	if not SPECS.has(t):
		return -1
	var arr: Array = d.get("stored_items", [])
	var cols := int(SPECS[t]["cols"])
	var row := idx / cols
	for i in range(row * cols, mini(idx + 1, arr.size())):
		if arr[i] is Dictionary and i + maxi(1, span(t, arr[i])) > idx:
			return i
	return -1


## Passende Start-Einheit für die Ware in der Nähe von idx, sonst -1.
static func fit(d: Dictionary, idx: int, crate: Dictionary) -> int:
	var t := str(d.get("item_type", ""))
	var n := span(t, crate)
	if n <= 0 or idx < 0 or idx >= unit_count(t):
		return -1
	var cols := int(SPECS[t]["cols"])
	var row := idx / cols
	var col := idx % cols
	for c in range(col, col - n, -1):
		if c < 0 or c + n > cols:
			continue
		var free := true
		for k in n:
			if owner_of(d, row * cols + c + k) >= 0:
				free = false
				break
		if free:
			return row * cols + c
	return -1


## Erste freie Stelle im ganzen Regal, sonst -1.
static func first_fit(d: Dictionary, crate: Dictionary) -> int:
	for i in unit_count(str(d.get("item_type", ""))):
		if owner_of(d, i) < 0:
			var f := fit(d, i, crate)
			if f >= 0:
				return f
	return -1


## Mittelpunkt (Boden) der Ware ab Einheit start mit n Einheiten, im Regal-Koordinatensystem.
static func spot(shelf_type: String, start: int, n: int) -> Vector3:
	var s: Dictionary = SPECS[shelf_type]
	var cols := int(s["cols"])
	var uw := float(s["unit_w"])
	var x0 := -uw * float(cols) * 0.5
	var y := float((s["levels"] as Array)[start / cols])
	if bool(s["pallet"]):
		y += PALLET_H
	return Vector3(x0 + (float(start % cols) + float(n) * 0.5) * uw, y, 0.0)
