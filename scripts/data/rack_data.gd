class_name RackData
extends RefCounted
## Typisierte Hülle um ein Rack aus GameState.racks (TEC-03).
## Liest und schreibt direkt im Dictionary. Spielstand und Netzwerk bleiben dadurch unverändert.
## Tippfehler in Feldnamen fallen beim Kompilieren auf, nicht erst beim Spielen.
##   var r := RackData.of(GameState.racks[rid])
##   for i in r.slot_count(): if not r.slot(i).is_empty(): ...

var raw: Dictionary

var id: String:
	get:
		return str(raw.get("id", ""))

## Vom Spieler vergebener Name ("" = keiner).
var custom_name: String:
	get:
		var v: Variant = raw.get("custom_name", "")
		return v if v is String else ""
	set(value):
		raw["custom_name"] = value

## "rack", "rack_pro" ...
var rack_type: String:
	get:
		return str(raw.get("rack_type", "rack"))
	set(value):
		raw["rack_type"] = value

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

var powered: bool:
	get:
		return bool(raw.get("powered", false))
	set(value):
		raw["powered"] = value

var networked: bool:
	get:
		return bool(raw.get("networked", false))
	set(value):
		raw["networked"] = value

## Temperatur im Rack in °C.
var temp: float:
	get:
		return float(raw.get("temp", 22.0))
	set(value):
		raw["temp"] = value

## Erster Dienst des Racks ("none" = vermietet nichts).
var rental_type: String:
	get:
		return str(raw.get("rental_type", "none"))
	set(value):
		raw["rental_type"] = value

var rental_customer: String:
	get:
		return str(raw.get("rental_customer", ""))
	set(value):
		raw["rental_customer"] = value

var active_users: int:
	get:
		return int(raw.get("active_users", 0))
	set(value):
		raw["active_users"] = value

## Kundenzufriedenheit 0..100.
var satisfaction: float:
	get:
		return float(raw.get("satisfaction", 100.0))
	set(value):
		raw["satisfaction"] = value

var grace_timer: float:
	get:
		return float(raw.get("grace_timer", 0.0))
	set(value):
		raw["grace_timer"] = value

var rental_income: float:
	get:
		return float(raw.get("rental_income", 0.0))
	set(value):
		raw["rental_income"] = value

var metrics: Dictionary:
	get:
		var m: Variant = raw.get("metrics", {})
		return m if m is Dictionary else {}
	set(value):
		raw["metrics"] = value

## Dienste auf diesem Rack: [{type, customer, users, trend}].
var services: Array:
	get:
		var s: Variant = raw.get("services", [])
		return s if s is Array else []
	set(value):
		raw["services"] = value

## Einschübe als Dictionaries (siehe SlotData).
var slots: Array:
	get:
		var s: Variant = raw.get("slots", [])
		return s if s is Array else []


static func of(d: Dictionary) -> RackData:
	var r := RackData.new()
	r.raw = d
	return r


## Neues Rack als Dictionary, so wie es in GameState.racks steht.
static func make(rack_id: String, type: String, at: Vector3, yaw: float, empty_slots: Array) -> Dictionary:
	return {
		"id": rack_id,
		"custom_name": "",
		"rack_type": type,
		"pos": at,
		"rot_y": yaw,
		"powered": false,
		"networked": false,
		"temp": 22.0,
		"rental_type": "none",
		"rental_customer": "",
		"active_users": 0,
		"satisfaction": 100.0,
		"grace_timer": 0.0,
		"rental_income": 0.0,
		"metrics": {},
		"services": [],
		"slots": empty_slots,
	}


## Ergänzt fehlende Felder alter Spielstände mit den Werten eines neuen Racks.
## Dienste und Einschübe behandelt GameState selbst (dort steckt mehr Logik drin).
static func fill_defaults(d: Dictionary) -> void:
	if not d.has("rack_type"):
		d["rack_type"] = "rack"
	if not (d.get("custom_name") is String):
		d["custom_name"] = ""
	for k in ["rental_type", "rental_customer", "active_users", "satisfaction", "grace_timer", "rental_income"]:
		if not d.has(k):
			d[k] = DEFAULTS[k]
	if not d.has("metrics") or not (d["metrics"] is Dictionary):
		d["metrics"] = {}


const DEFAULTS := {
	"rental_type": "none", "rental_customer": "", "active_users": 0, "satisfaction": 100.0,
	"grace_timer": 0.0, "rental_income": 0.0,
}


func slot_count() -> int:
	return slots.size()


## Einschub i als SlotData. Liegt i außerhalb, eine leere Hülle (nichts eingebaut).
func slot(i: int) -> SlotData:
	var arr := slots
	if i < 0 or i >= arr.size() or not (arr[i] is Dictionary):
		return SlotData.of({})
	return SlotData.of(arr[i])


## Indizes der belegten Einschübe.
func used_slots() -> Array[int]:
	var out: Array[int] = []
	var arr := slots
	for i in arr.size():
		if arr[i] is Dictionary and not str((arr[i] as Dictionary).get("item_type", "")).is_empty():
			out.append(i)
	return out


static func problems(d: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (d is Dictionary):
		return ["kein Dictionary"]
	var dd: Dictionary = d
	var r := RackData.of(dd)
	if r.id.is_empty():
		out.append("ohne id")
	if dd.has("pos") and not (dd["pos"] is Vector3):
		out.append("pos ist kein Vector3")
	if not (dd.get("slots", []) is Array):
		out.append("slots ist keine Liste")
	else:
		for i in (dd["slots"] as Array).size() if dd.has("slots") else 0:
			for p in SlotData.problems((dd["slots"] as Array)[i]):
				out.append("Einschub %d: %s" % [i, p])
	if dd.has("services") and not (dd["services"] is Array):
		out.append("services ist keine Liste")
	return out
