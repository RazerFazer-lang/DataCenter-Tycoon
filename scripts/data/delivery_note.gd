class_name DeliveryNote
extends RefCounted
## Lieferschein des Lieferdienstes Cloud Express: Inhalt aus dem Ladeplan und Prüfung der Unterschrift.
## Der Host baut den Schein beim Abladen (build) und schickt ihn mit dem Ladeplan an alle.
## Unterschriften sind Striche mit Punkten von 0 bis 1 (x über die Breite, y über die Höhe des Feldes).

const COMPANY := "Cloud Express Logistik GmbH"
const COMPANY_ADDR := "Hafenring 12 · 28217 Verion"
const DRIVERS: Array[String] = ["Marco Brandt", "Jana Petrović", "Kemal Aydın", "Lisa Hoffmann", "Tobias Krüger", "Sofia Lindqvist", "Dennis Wolf", "Aylin Demir"]
## Lieferort -> [Name, Zusatz]
const SITE_ADDR := {"garage": ["Gewerbegarage", "Tor 1"], "halle_nord": ["Halle Nord", "Laderampe 2"]}
## Ungefähres Gewicht je Packstück-Größe.
const KG := {"parcel": 3.5, "small": 6.0, "medium": 14.0, "big": 38.0, "cart": 24.0}
const MAX_STROKES := 40
const MAX_POINTS := 1500
## So viel Tinte braucht eine Unterschrift mindestens (Summe der Strichlängen in Feldbreiten).
const MIN_INK := 0.35
## Höhe des Feldes im Verhältnis zur Breite. Damit werden Längen in y fair gemessen.
const PAD_ASPECT := 0.30


static func build(plan: Dictionary, tier: int, site: String, parcel_parts: int, day: int, time_str: String, company: String, seq: int) -> Dictionary:
	var lines: Array = []
	var kg := 0.0
	for e in plan.get("items", []):
		var d: Dictionary = e
		kg += float(KG.get(str(d.get("cls", "small")), 6.0))
		lines.append(line_for(str(d.get("it", "")), str(d.get("label", "")), parcel_parts))
	var no := "LS-%04d-%02d" % [day, seq]
	var h := absi(no.hash())
	return {
		"no": no, "day": day, "time": time_str, "company": company, "site": site, "tier": tier,
		"driver": DRIVERS[h % DRIVERS.size()], "plate": "VRN-CE %d" % (1000 + h % 9000),
		"lines": lines, "packages": lines.size(), "kg": roundi(kg), "seed": h,
	}


## Eine Zeile des Scheins: {"name", "extra", "qty", "unit", "sku"}. name und unit sind deutsche Vorlagen.
static func line_for(it: String, label: String, parcel_parts: int) -> Dictionary:
	var base := it
	var qty := 1
	var unit := "Stk."
	var name := ""
	var extra := ""
	if it == "cart":
		name = "Transportwagen"
	elif it.begins_with("build:"):
		name = "Vormontierter Einschub"
		extra = label
	elif it == GameState.VAN_PARCEL_ITEM:
		name = "Sammelpaket Bauteile & Zubehör"
		unit = "Paket"
		extra = "%d Teile" % maxi(parcel_parts, 1)
	else:
		if it.begins_with("bulk:"):
			var p := it.split(":")
			base = p[1] if p.size() > 1 else it
			qty = clampi(int(p[2]) if p.size() > 2 else 1, 1, 99)
			extra = "Sammelkiste"
		name = str(GameState.ITEM_CATALOG.get(base, {}).get("name", base))
	return {"name": name, "extra": extra, "qty": qty, "unit": unit, "sku": "CE-%05d" % (absi(base.hash()) % 100000)}


## Ist das eine echte Unterschrift? Prüft Form, Grenzen und genug Tinte.
static func valid_signature(strokes: Variant) -> bool:
	if not strokes is Array:
		return false
	var arr: Array = strokes
	if arr.is_empty() or arr.size() > MAX_STROKES:
		return false
	var points := 0
	for s in arr:
		if not s is PackedVector2Array:
			return false
		points += (s as PackedVector2Array).size()
		for p in (s as PackedVector2Array):
			if p.x < -0.05 or p.x > 1.05 or p.y < -0.05 or p.y > 1.05 or is_nan(p.x) or is_nan(p.y):
				return false
	return points <= MAX_POINTS and ink(arr) >= MIN_INK


## Summe der Strichlängen, gemessen in Feldbreiten.
static func ink(strokes: Array) -> float:
	var total := 0.0
	for s in strokes:
		var pts: PackedVector2Array = s
		for i in range(1, pts.size()):
			var d := pts[i] - pts[i - 1]
			total += Vector2(d.x, d.y * PAD_ASPECT).length()
	return total


## Unterschrift des Fahrers: ein flüssiger Schriftzug, immer gleich für denselben Schein.
static func driver_signature(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	var pts := PackedVector2Array()
	var x := 0.06
	var loops := rng.randi_range(5, 8)
	var phase := rng.randf() * TAU
	var steps := loops * 14
	for i in steps + 1:
		var t := float(i) / float(steps)
		x = 0.06 + t * 0.78
		var amp := 0.22 + 0.12 * sin(t * 3.1 + phase)
		var y := 0.55 - amp * sin(t * TAU * loops * 0.5 + phase) * (1.0 - t * 0.35) - 0.10 * sin(t * PI)
		pts.append(Vector2(x + 0.025 * cos(t * TAU * loops * 0.5 + phase), clampf(y, 0.08, 0.95)))
	out.append(pts)
	# Unterstrich mit Schwung
	var u := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		u.append(Vector2(0.10 + t * 0.80, 0.84 - 0.06 * sin(t * PI) + 0.02 * t))
	out.append(u)
	return out


## Eine gültige Test-Unterschrift (für Tests und den Server-Bot).
static func test_signature() -> Array:
	return driver_signature(4711)
