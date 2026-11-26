class_name StripData
extends RefCounted
## Typisierte Hülle um eine Steck- oder LAN-Leiste aus GameState.decor_items (TEC-03).
## Leisten sind Einrichtungsstücke mit item_type prop_power_strip oder prop_lan_strip.
## Liest und schreibt direkt im Dictionary, Spielstand und Netzwerk bleiben unverändert.

const POWER_TYPE := "prop_power_strip"
const LAN_TYPE := "prop_lan_strip"

var raw: Dictionary

var id: String:
	get:
		return str(raw.get("id", ""))

var item_type: String:
	get:
		return str(raw.get("item_type", ""))

var pos: Vector3:
	get:
		var p: Variant = raw.get("pos", Vector3.ZERO)
		return p if p is Vector3 else Vector3.ZERO
	set(value):
		raw["pos"] = value

var rot_y: float:
	get:
		return float(raw.get("rot_y", 0.0))
	set(value):
		raw["rot_y"] = value

## Hängt an der Wand statt auf dem Boden zu liegen.
var wall: bool:
	get:
		return bool(raw.get("wall", false))
	set(value):
		raw["wall"] = value

## Schalter der Leiste. Fehlt der Wert (alte Spielstände), ist sie an.
var on: bool:
	get:
		return bool(raw.get("on", true))
	set(value):
		raw["on"] = value

## Wegen Überlast ausgelöst (bleibt aus, bis jemand sie wieder einschaltet).
var tripped: bool:
	get:
		return bool(raw.get("tripped", false))
	set(value):
		raw["tripped"] = value


static func of(d: Dictionary) -> StripData:
	var s := StripData.new()
	s.raw = d
	return s


static func is_strip_type(type: String) -> bool:
	return type == POWER_TYPE or type == LAN_TYPE


static func is_strip(d: Variant) -> bool:
	return d is Dictionary and is_strip_type(str((d as Dictionary).get("item_type", "")))


func is_power() -> bool:
	return item_type == POWER_TYPE


func is_lan() -> bool:
	return item_type == LAN_TYPE


## Kabelart, die an diese Leiste passt.
func cable_type() -> String:
	return CableData.POWER if is_power() else CableData.NETWORK


static func problems(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (d is Dictionary):
		return ["kein Dictionary"]
	var s := StripData.of(d)
	if s.id.is_empty():
		out.append("ohne id")
	if not is_strip_type(s.item_type):
		out.append("keine Leiste: '%s'" % s.item_type)
	if (d as Dictionary).has("pos") and not ((d as Dictionary)["pos"] is Vector3):
		out.append("pos ist kein Vector3")
	if (d as Dictionary).has("on") and not ((d as Dictionary)["on"] is bool):
		out.append("on ist kein bool")
	return out
