class_name SlotData
extends RefCounted
## Typisierte Hülle um einen Einschub eines Racks (ein Eintrag in RackData.slots) (TEC-03).
## Liest und schreibt direkt im Dictionary, Spielstand und Netzwerk bleiben unverändert.

## Zustände eines Einschubs.
const OK := "ok"
const CRASHED := "crashed"
const BROKEN := "broken"

var raw: Dictionary

## Gehäuse bzw. Mainboard ("" = leer).
var item_type: String:
	get:
		return str(raw.get("item_type", ""))
	set(value):
		raw["item_type"] = value

## "ok", "crashed", "broken" ...
var state: String:
	get:
		return str(raw.get("state", OK))
	set(value):
		raw["state"] = value

var components: Dictionary:
	get:
		var c: Variant = raw.get("components", {})
		return c if c is Dictionary else {}
	set(value):
		raw["components"] = value

var repair_progress: float:
	get:
		return float(raw.get("repair_progress", 0.0))
	set(value):
		raw["repair_progress"] = value

var fire_level: float:
	get:
		return float(raw.get("fire_level", 0.0))
	set(value):
		raw["fire_level"] = value

## Defektes Bauteil ("" = keins).
var faulty_part: String:
	get:
		return str(raw.get("faulty_part", ""))
	set(value):
		raw["faulty_part"] = value

var diagnosed: bool:
	get:
		return bool(raw.get("diagnosed", false))
	set(value):
		raw["diagnosed"] = value

## Vom Spieler ausgeschaltet.
var offline: bool:
	get:
		return bool(raw.get("offline", false))
	set(value):
		raw["offline"] = value

## Restzeit beim Hochfahren in Sekunden (0 = läuft).
var boot_left: float:
	get:
		return float(raw.get("boot_left", 0.0))
	set(value):
		raw["boot_left"] = value


static func of(d: Dictionary) -> SlotData:
	var s := SlotData.new()
	s.raw = d
	return s


## Leerer Einschub, so wie er in einem neuen Rack steht.
static func make_empty(empty_components: Dictionary) -> Dictionary:
	return {
		"item_type": "",
		"state": OK,
		"repair_progress": 0.0,
		"fire_level": 0.0,
		"components": empty_components,
	}


func is_empty() -> bool:
	return item_type.is_empty()


func is_ok() -> bool:
	return state == OK


func is_failed() -> bool:
	return state == CRASHED or state == BROKEN


func is_burning() -> bool:
	return fire_level > 0.0


## Bauteil-ID einer Kategorie ("cpu", "ram", ...). "" = nicht eingebaut.
func part(cat: String) -> String:
	return str(components.get(cat, ""))


static func problems(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (d is Dictionary):
		return ["kein Dictionary"]
	var dd: Dictionary = d
	if not (dd.get("item_type", "") is String):
		out.append("item_type ist kein Text")
	if not (dd.get("state", OK) is String):
		out.append("state ist kein Text")
	if dd.has("components") and not (dd["components"] is Dictionary):
		out.append("components ist kein Dictionary")
	for k in ["repair_progress", "fire_level"]:
		if dd.has(k) and not (dd[k] is float or dd[k] is int):
			out.append("%s ist keine Zahl" % k)
	return out
