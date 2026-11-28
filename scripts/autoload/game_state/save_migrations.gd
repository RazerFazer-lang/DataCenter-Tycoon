extends RefCounted
## Spielstand-Migrationen (TEC-02): eine Funktion je Version aus SaveSchema.STEPS.
## run() wird beim Laden zweimal aufgerufen: vor dem Einlesen ("data") und danach ("world").
##
## Der Zustand liegt weiter in GameState. Die Funktionen hier sind statisch und greifen über das
## Autoload GameState darauf zu. Wo andere Skripte sie brauchen, leitet GameState weiter.


## Führt die Migrationen aus, die dieser Spielstand für den Zeitpunkt noch braucht, in Reihenfolge.
## Gibt die Nummern der gelaufenen Migrationen zurück.
static func run(data: Dictionary, from_version: int, stage: String) -> Array[int]:
	var done: Array[int] = []
	for v in SaveSchema.pending(from_version, stage):
		match v:
			1:
				_v1_room_level(data)
			2:
				_v2_starter_cart(data)
			3:
				_migrate_mounted_strips(data)
			4:
				_migrate_shelves()
			5:
				_migrate_strip_ports()
			6:
				_v6_nord_diesel()
			7:
				_v7_halle_nord_neu()
			_:
				push_error("Spielstand: %s hat keine Funktion in save_migrations.gd." % SaveSchema.describe(v))
				continue
		done.append(v)
	return done


## 6 (v3.6): Das Aggregat an Halle Nord lief früher ohne Tank. Wer es schon hat, bekommt einen vollen Tank.
static func _v6_nord_diesel() -> void:
	if GameState.has_building_upgrade("upg_diesel_gen"):
		Operations.init_nord_tank(true)


## 7 (v3.8): Halle Nord ist neu gebaut (24 × 14 m, drei Abschnitte, Technikecke und Büro).
## Wer sie schon hatte, behält alles: alle Abschnitte offen, Geräte in Technikecke, Büro oder
## vor dem Tor rücken auf den nächsten freien Platz.
static func _v7_halle_nord_neu() -> Array:
	if not GameState.halle_nord_owned:
		return [0]
	for uid in ["upg_nord_hall", "upg_nord_section_2", "upg_nord_section_3"]:
		GameState.building_upgrades[uid] = true
		GameState.active_constructions.erase(uid)
	var moved := 0
	for kind in ["racks", "coolers", "ups_units", "decor_items"]:
		var dict: Dictionary = GameState.get(kind)
		for id in dict.keys():
			var d: Dictionary = dict[id]
			var pos: Vector3 = d.get("pos", Vector3.ZERO)
			if not HalleNordLayout.is_nord(pos) or _v7_fits(kind, str(id), d, pos):
				continue
			var best := _v7_free_spot(kind, str(id), d, pos)
			if best != pos:
				d["pos"] = best
				moved += 1
	if moved > 0:
		GameState.post_event_f("🏭 Halle Nord ist neu gebaut (24 × 14 m, alle 3 Abschnitte offen). %d Geräte sind auf freie Plätze gerückt.", [moved], "info")
	return [moved]


static func _v7_fits(kind: String, id: String, d: Dictionary, pos: Vector3) -> bool:
	if kind == "racks":
		return GameState.can_place_at(pos, id)
	if kind == "decor_items":
		var it := str(d.get("item_type", ""))
		if DecorSpec.is_wall_sign(it) or GameState.is_strip_type(it):
			return true
		if DecorSpec.SIZES.has(it):
			return DecorSpec.can_place(it, pos, float(d.get("rot_y", 0.0)), id)
	var l := HalleNordLayout.local(pos)
	return HalleNordLayout.can_stand(Vector2(l.x, l.z), Vector2(0.4, 0.4))


static func _v7_free_spot(kind: String, id: String, d: Dictionary, pos: Vector3) -> Vector3:
	for ring in range(1, 40):
		var r := float(ring) * 0.35
		for k in range(16):
			var a := TAU * float(k) / 16.0
			var cand := Vector3(pos.x + cos(a) * r, pos.y, pos.z + sin(a) * r)
			var keep: Vector3 = d["pos"]
			d["pos"] = cand
			var ok := _v7_fits(kind, id, d, cand)
			d["pos"] = keep
			if ok:
				return cand
	return pos


## 1 (v0.3): Früher gab es nur room_expanded (an/aus), seitdem die Raumstufe 0 bis 2.
static func _v1_room_level(data: Dictionary) -> void:
	if not data.has("room_level"):
		data["room_level"] = 1 if bool(data.get("room_expanded", false)) else 0


## 2 (v0.3): Spielstände ohne Rollwagen bekommen den Startwagen.
static func _v2_starter_cart(data: Dictionary) -> void:
	if data.has("carts"):
		return
	var cid := GameState._alloc_id("cart")
	GameState.carts[cid] = {"id": cid, "pos": Vector3(-3.2, 0.0, 2.8), "rot_y": 0.25, "pushed_by": 0, "items": []}
	GameState.carts_changed.emit()


## Seit den Seitenbuchsen: alte Kabel an Leisten auf die richtige Buchse stecken.
## Leiste an Leiste: von der näher am Kasten liegenden aus dem Ausgang in den Eingang der anderen.
## Kasten/Router kommt in den Eingang, Geräte oben. Was nicht mehr passt, wird abgezogen.
## Gibt [umgesteckt, abgezogen] zurück.
static func _migrate_strip_ports() -> Array:
	var moved := 0
	var dropped: Array = []
	for ctype in ["power", "network"]:
		var depth := _cable_depths(ctype)
		var ids: Array = []
		for cid in GameState.cables.keys():
			if CableData.of(GameState.cables[cid]).cable_type == ctype:
				ids.append(str(cid))
		# Kabel nah am Kasten zuerst, damit die Kette von vorn aufgebaut wird.
		ids.sort_custom(func(x, y):
			var dx := mini(int(depth.get(str(GameState.cables[x]["from_id"]), 999)), int(depth.get(str(GameState.cables[x]["to_id"]), 999)))
			var dy := mini(int(depth.get(str(GameState.cables[y]["from_id"]), 999)), int(depth.get(str(GameState.cables[y]["to_id"]), 999)))
			return dx < dy if dx != dy else x < y)
		var taken := {}
		# Kabel ohne Leiste behalten ihre Buchsen.
		for cid in ids:
			var c: Dictionary = GameState.cables[cid]
			for end in [["from_id", "from_slot"], ["to_id", "to_slot"]]:
				var eid := str(c[end[0]])
				if StripRules.role(ctype, eid) != "strip":
					continue
		for cid in ids:
			var c: Dictionary = GameState.cables[cid]
			var a := CableData.of(c).from_id
			var b := CableData.of(c).to_id
			var ra := StripRules.role(ctype, a)
			var rb := StripRules.role(ctype, b)
			if ctype == "power" and ra == "device" and rb == "device":
				dropped.append(cid)
				continue
			if ra != "strip" and rb != "strip":
				continue
			var sa := -1
			var sb := -1
			if ra == "strip" and rb == "strip":
				var a_up := int(depth.get(a, 999)) <= int(depth.get(b, 999))
				sa = StripRules.out_slot(ctype) if a_up else StripRules.in_slot(ctype)
				sb = StripRules.in_slot(ctype) if a_up else StripRules.out_slot(ctype)
			else:
				var s_is_a := ra == "strip"
				var strip := a if s_is_a else b
				var other := b if s_is_a else a
				var orole := rb if s_is_a else ra
				var feeds := orole == "source" or ((orole == "ups" or orole == "hub") and int(depth.get(other, 999)) < int(depth.get(strip, 999)))
				var slot := StripRules.in_slot(ctype)
				if not feeds:
					slot = -1
					for i in StripRules.top_count(ctype):
						if not (taken.get(strip, {}) as Dictionary).has(i):
							slot = i
							break
				if s_is_a:
					sa = slot
				else:
					sb = slot
			var ok := true
			for pair in [[a, sa], [b, sb]]:
				if int(pair[1]) < 0 and StripRules.role(ctype, str(pair[0])) == "strip":
					ok = false
				elif int(pair[1]) >= 0 and (taken.get(pair[0], {}) as Dictionary).has(int(pair[1])):
					ok = false
			if not ok:
				dropped.append(cid)
				continue
			for pair in [[a, sa, "from_slot"], [b, sb, "to_slot"]]:
				if int(pair[1]) < 0:
					continue
				if not taken.has(pair[0]):
					taken[pair[0]] = {}
				taken[pair[0]][int(pair[1])] = true
				if int(c.get(pair[2], -1)) != int(pair[1]):
					c[pair[2]] = int(pair[1])
					moved += 1
	for cid in dropped:
		GameState.cables.erase(cid)
	if moved > 0 or not dropped.is_empty():
		GameState.post_event_f("🔌 Steckleisten haben jetzt Eingang (weiß) und Ausgang (rot) an der Seite: %d Kabel umgesteckt, %d Kabel abgezogen. Racks geben keinen Strom mehr weiter, sie hängen an Leisten oder am Kasten.", [moved, dropped.size()], "info")
	return [moved, dropped.size()]


## Abstand jedes Anschlusses zum Kasten bzw. Router über beliebige Kabel (alte Regeln).
static func _cable_depths(ctype: String) -> Dictionary:
	var depth := {}
	var queue: Array = []
	for src in ([GameState.WALL_BREAKER_ID, GameState.HALL_C_BREAKER_ID] + GameState.HALL_NORD_BREAKER_IDS if ctype == "power" else [GameState.WALL_ROUTER_ID, GameState.HALL_C_ROUTER_ID, GameState.HALL_NORD_ROUTER_ID]):
		depth[src] = 0
		queue.append(src)
	while not queue.is_empty():
		var cur := str(queue.pop_front())
		for cid in GameState.cables.keys():
			var c: Dictionary = GameState.cables[cid]
			if str(c.get("cable_type", "")) != ctype:
				continue
			var other := str(c["to_id"]) if str(c["from_id"]) == cur else (str(c["from_id"]) if str(c["to_id"]) == cur else "")
			if other == "" or depth.has(other):
				continue
			depth[other] = int(depth[cur]) + 1
			queue.append(other)
	return depth


## Spielstände vor v2.6: am Kasten bzw. Router montierte Leisten werden zu echten Leisten in Kisten.
static func _migrate_mounted_strips(data: Dictionary) -> void:
	var got := 0
	for pair in [["power_strips", "prop_power_strip"], ["net_hubs", "prop_lan_strip"]]:
		var left := clampi(int(data.get(pair[0], 0)), 0, 8)
		got += left
		while left > 0:
			var n := mini(left, GameState.BULK_PACK_MAX)
			GameState._spawn_crate_internal(str(pair[1]), n)
			left -= n
	if got > 0:
		GameState.crates_changed.emit()
		GameState.post_event_f("📦 %d montierte Leisten sind jetzt echte Leisten und stehen als Kiste in der Lieferzone. Alte Kabel bleiben stecken, bis du sie ziehst.", [got], "info")


## Spielstände vor v2.9: festes Regal und 4er-Regale auf das neue System umstellen.
static func _migrate_shelves() -> void:
	for did in GameState.decor_items.keys():
		var d: Dictionary = GameState.decor_items[did]
		if str(d.get("item_type", "")) != "prop_storage_shelf":
			continue
		var old: Array = GameState._decor_list(did, "stored_items")
		if old.size() != 4:
			continue
		d["stored_items"] = []
		var arr := ShelfSpec.units(d)
		for i in 4:
			if old[i] is Dictionary:
				arr[i * 5 + 1] = old[i]
	if GameState.start_shelf_done:
		return
	GameState.start_shelf_done = true
	var left: Array = []
	var d0 := GameState._make_start_shelf()
	for k in GameState.storage_shelf_slots.keys():
		if not str(k).begins_with("shelf_0:"):
			continue
		var item: Dictionary = (GameState.storage_shelf_slots[k] as Dictionary).duplicate(true)
		item["held_by"] = 0
		item["pos"] = Vector3.ZERO
		var at := ShelfSpec.first_fit(d0, item)
		if at >= 0:
			ShelfSpec.units(d0)[at] = item
		else:
			left.append(item)
		GameState.storage_shelf_slots.erase(k)
	# Was nicht ins Regal passt (große Geräte), steht davor.
	for i in left.size():
		var c: Dictionary = left[i]
		var cid := GameState._alloc_id("crate")
		c["id"] = cid
		c["pos"] = Vector3(-3.6 + float(i / 3) * 0.75, 0.0, -2.9 + float(i % 3) * 0.75)
		GameState.crates[cid] = c
