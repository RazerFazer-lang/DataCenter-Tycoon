class_name CableData
extends RefCounted
## Typisierte Hülle um ein Kabel aus GameState.cables (TEC-03).
## Liest und schreibt direkt im Dictionary. Spielstand und Netzwerk bleiben dadurch unverändert.
## Tippfehler in Feldnamen fallen beim Kompilieren auf, nicht erst beim Spielen.
##   var c := CableData.of(GameState.cables[cid])
##   if c.is_power() and c.touches(rack_id): ...

const POWER := "power"
const NETWORK := "network"
## Kabel zwischen zwei Racks eines Clusters.
const CLUSTER := "cluster"
const TYPES: Array[String] = [POWER, NETWORK, CLUSTER]

## Das Kabel-Dictionary selbst.
var raw: Dictionary

var id: String:
	get:
		return str(raw.get("id", ""))
	set(value):
		raw["id"] = value

## "power", "network" oder "cluster".
var cable_type: String:
	get:
		return str(raw.get("cable_type", ""))
	set(value):
		raw["cable_type"] = value

var from_id: String:
	get:
		return str(raw.get("from_id", ""))
	set(value):
		raw["from_id"] = value

var to_id: String:
	get:
		return str(raw.get("to_id", ""))
	set(value):
		raw["to_id"] = value

## Buchse am Anfang. -1 = alter Spielstand ohne Buchse (bekommt beim Zählen die nächste freie).
var from_slot: int:
	get:
		return int(raw.get("from_slot", -1))
	set(value):
		raw["from_slot"] = value

var to_slot: int:
	get:
		return int(raw.get("to_slot", -1))
	set(value):
		raw["to_slot"] = value


static func of(d: Dictionary) -> CableData:
	var c := CableData.new()
	c.raw = d
	return c


## Neues Kabel als Dictionary, so wie es in GameState.cables steht.
static func make(cable_id: String, type: String, a_id: String, a_slot: int, b_id: String, b_slot: int) -> Dictionary:
	return {
		"id": cable_id, "cable_type": type, "from_id": a_id, "to_id": b_id,
		"from_slot": a_slot, "to_slot": b_slot,
	}


func is_power() -> bool:
	return cable_type == POWER


func is_network() -> bool:
	return cable_type == NETWORK


func touches(endpoint_id: String) -> bool:
	return from_id == endpoint_id or to_id == endpoint_id


## Das andere Ende. "" wenn das Kabel nicht an endpoint_id hängt.
func other_end(endpoint_id: String) -> String:
	if from_id == endpoint_id:
		return to_id
	if to_id == endpoint_id:
		return from_id
	return ""


## Gespeicherte Buchse am Ende endpoint_id. -1 wenn keine gespeichert ist oder das Kabel dort nicht hängt.
func slot_at(endpoint_id: String) -> int:
	if from_id == endpoint_id:
		return from_slot
	if to_id == endpoint_id:
		return to_slot
	return -1


func set_slot_at(endpoint_id: String, slot: int) -> void:
	if from_id == endpoint_id:
		from_slot = slot
	elif to_id == endpoint_id:
		to_slot = slot


## Was an einem Kabel-Dictionary nicht stimmt. Leer = in Ordnung.
static func problems(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (d is Dictionary):
		return ["kein Dictionary"]
	var c := CableData.of(d)
	if c.id.is_empty():
		out.append("ohne id")
	if not (c.cable_type in TYPES):
		out.append("unbekannte Kabelart '%s'" % c.cable_type)
	if c.from_id.is_empty() or c.to_id.is_empty():
		out.append("ohne Ende")
	elif c.from_id == c.to_id:
		out.append("beide Enden gleich")
	for k in ["from_slot", "to_slot"]:
		if (d as Dictionary).has(k) and not ((d as Dictionary)[k] is int or (d as Dictionary)[k] is float):
			out.append("%s ist keine Zahl" % k)
	return out
