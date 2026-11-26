extends Node
## Handles saving, listing, loading, and deleting DataCenter Tycoon Co-op worlds
## as clean human-readable JSON files in user://saves/. Backward-compatible with v0.2 saves.

const SAVES_SUBDIR := "saves"
const SAVE_FORMAT_VERSION := 2
## Sicherungen liegen in user://saves/backups/<save_id>/<unix_zeit>.json.
const BACKUPS_SUBDIR := "backups"
## So viele Sicherungen bleiben pro Welt erhalten.
const MAX_BACKUPS := 5
## Bereiche mit (auch verschachtelten) "pos"-Feldern, die JSON nicht als Vector3 speichern kann.
const NESTED_POS_KEYS: Array[String] = ["decor_items", "storage_shelf_slots", "extinguishers"]


func _ensure_saves_dir() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if not dir.dir_exists(SAVES_SUBDIR):
		var err := dir.make_dir(SAVES_SUBDIR)
		return err == OK
	return true


func sanitize_save_id(raw_name: String) -> String:
	var cleaned := raw_name.strip_edges().to_lower()
	var out := ""
	for i in range(cleaned.length()):
		var ch := cleaned.substr(i, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().left(32)
	if out.is_empty():
		out = "datacenter_save"
	return out


func get_save_path(save_id: String) -> String:
	return "user://%s/%s.json" % [SAVES_SUBDIR, sanitize_save_id(save_id)]


func save_world(save_id: String, display_name: String, state_data: Dictionary, make_backup: bool = false) -> Dictionary:
	if not _ensure_saves_dir():
		return {"ok": false, "error": "Speicherordner konnte nicht erstellt werden."}

	var clean_id := sanitize_save_id(save_id)
	if make_backup:
		_backup_current(clean_id)
	var clean_display := SecurityGuard.sanitize_label(display_name, 32, clean_id)

	var serialized_state := _serialize_state(state_data)
	var state_sig := signature_for_file(serialized_state)
	var rack_count := (state_data.get("racks", {}) as Dictionary).size()
	var payload := {
		"version": SAVE_FORMAT_VERSION,
		"save_id": clean_id,
		"display_name": clean_display,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"_sig": state_sig,
		"summary": {
			"money": int(roundf(float(state_data.get("money", 0.0)))),
			"rack_count": rack_count,
			"total_ram_gb": int(state_data.get("total_ram_gb", 0)),
			"total_compute": int(state_data.get("total_compute", 0)),
			"power_tier": int(state_data.get("power_tier", 0)),
			"room_level": int(state_data.get("room_level", 0)),
			"day_number": int(state_data.get("day_number", 1)),
			"ai_platform_level": int(state_data.get("ai_platform_level", 0)),
		},
		"state": serialized_state,
	}

	var json_text := JSON.stringify(payload, "\t")
	var path := get_save_path(clean_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": TranslationServer.translate("Datei konnte nicht geschrieben werden: %s") % path}

	file.store_string(json_text)
	file.close()
	return {"ok": true, "save_id": clean_id, "display_name": clean_display, "path": path}


## Signatur über genau die Werte, die beim Laden wieder aus der Datei kommen. JSON schreibt Kommazahlen
## nur mit 14 Stellen und macht ganze Zahlen zu Kommazahlen. Lag ein Wert knapp an einer Rundungsgrenze,
## rundete die Prüfung nach dem Laden anders als beim Speichern, und der Spielstand galt als „manipuliert“.
func signature_for_file(serialized_state: Dictionary) -> String:
	var stored: Variant = JSON.parse_string(JSON.stringify(serialized_state))
	return SecurityGuard.compute_save_signature(stored if stored is Dictionary else serialized_state)


func load_world_file(save_id: String) -> Dictionary:
	var path := get_save_path(save_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Spielstand nicht gefunden."}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Spielstand konnte nicht geöffnet werden."}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "Spielstand ist beschädigt (ungültiges JSON)."}

	var root: Dictionary = parsed
	if not root.has("state") or not (root["state"] is Dictionary):
		return {"ok": false, "error": "Spielstand enthält keine gültigen Weltdaten."}

	var state_dict := _deserialize_state(root["state"] as Dictionary)
	var integrity := SecurityGuard.verify_and_sanitize_save(root, state_dict)
	if str(integrity.get("status", "")) == "tampered":
		push_warning("Spielstand '%s' wurde außerhalb des Spiels verändert (Prüfsumme ungültig) — unplausible Werte wurden bereinigt." % save_id)
	return {
		"ok": true,
		"save_id": str(root.get("save_id", save_id)),
		"display_name": SecurityGuard.sanitize_label(str(root.get("display_name", save_id)), 32, save_id),
		"saved_at": str(root.get("saved_at", "")),
		"state": state_dict,
		"integrity": integrity,
	}


func list_saves() -> Array:
	var results: Array = []
	if not _ensure_saves_dir():
		return results

	var dir := DirAccess.open("user://%s" % SAVES_SUBDIR)
	if dir == null:
		return results

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var full_path := "user://%s/%s" % [SAVES_SUBDIR, fname]
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					var d: Dictionary = parsed
					results.append({
						"save_id": str(d.get("save_id", fname.get_basename())),
						"display_name": str(d.get("display_name", fname.get_basename())),
						"saved_at": str(d.get("saved_at", "")),
						"summary": d.get("summary", {}),
					})
		fname = dir.get_next()
	dir.list_dir_end()

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("saved_at", "")) > str(b.get("saved_at", ""))
	)
	return results


func delete_save(save_id: String) -> bool:
	var path := get_save_path(save_id)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return err == OK


func _backup_dir(save_id: String) -> String:
	return "user://%s/%s/%s" % [SAVES_SUBDIR, BACKUPS_SUBDIR, sanitize_save_id(save_id)]


## Kopiert den aktuellen Spielstand in den Sicherungsordner und löscht überzählige Sicherungen.
func _backup_current(clean_id: String) -> bool:
	var src := get_save_path(clean_id)
	if not FileAccess.file_exists(src):
		return false
	var dir_path := _backup_dir(clean_id)
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		if DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
			push_warning("Sicherungsordner konnte nicht erstellt werden: %s" % abs_dir)
			return false
	var stamp := int(Time.get_unix_time_from_system())
	var dst := "%s/%d.json" % [dir_path, stamp]
	var n := 1
	while FileAccess.file_exists(dst):
		dst = "%s/%d_%d.json" % [dir_path, stamp, n]
		n += 1
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	if err != OK:
		push_warning("Sicherung fehlgeschlagen (%d): %s" % [err, dst])
		return false
	_prune_backups(clean_id)
	return true


## Dateinamen der Sicherungen einer Welt, neueste zuerst.
func _backup_files(save_id: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(_backup_dir(save_id))
	if dir == null:
		return files
	for fname in dir.get_files():
		if fname.ends_with(".json"):
			files.append(fname)
	files.sort()
	files.reverse()
	return files


func _prune_backups(save_id: String) -> void:
	var files := _backup_files(save_id)
	var dir_path := _backup_dir(save_id)
	for i in range(MAX_BACKUPS, files.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [dir_path, files[i]]))


## Sicherungen einer Welt, neueste zuerst: [{file, saved_at, summary}].
func list_backups(save_id: String) -> Array:
	var results: Array = []
	var dir_path := _backup_dir(save_id)
	for fname in _backup_files(save_id):
		var f := FileAccess.open("%s/%s" % [dir_path, fname], FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			continue
		var d: Dictionary = parsed
		results.append({
			"file": fname,
			"saved_at": str(d.get("saved_at", "")),
			"summary": d.get("summary", {}),
		})
	return results


## Ersetzt den Spielstand durch eine Sicherung. Der aktuelle Stand wird vorher selbst gesichert.
func restore_backup(save_id: String, backup_file: String) -> Dictionary:
	var clean_id := sanitize_save_id(save_id)
	# Nur Dateinamen aus dem eigenen Sicherungsordner zulassen (kein "../").
	if not _backup_files(clean_id).has(backup_file):
		return {"ok": false, "error": "Sicherung nicht gefunden."}
	var f := FileAccess.open("%s/%s" % [_backup_dir(clean_id), backup_file], FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Sicherung konnte nicht geöffnet werden."}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("state") is Dictionary):
		return {"ok": false, "error": "Sicherung ist beschädigt."}
	if not _ensure_saves_dir():
		return {"ok": false, "error": "Speicherordner konnte nicht erstellt werden."}
	_backup_current(clean_id)
	var out := FileAccess.open(get_save_path(clean_id), FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Spielstand konnte nicht geschrieben werden."}
	out.store_string(text)
	out.close()
	return {"ok": true, "save_id": clean_id}


func _serialize_state(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)

	for key in ["racks", "coolers", "ups_units", "carts"]:
		var dict_in: Dictionary = out.get(key, {})
		var dict_out: Dictionary = {}
		for eid in dict_in.keys():
			var item: Dictionary = (dict_in[eid] as Dictionary).duplicate(true)
			item["pos"] = _vec3_to_arr(item.get("pos", Vector3.ZERO))
			if key == "carts":
				item["pushed_by"] = 0
			dict_out[eid] = item
		out[key] = dict_out

	var crates_in: Dictionary = out.get("crates", {})
	var crates_out: Dictionary = {}
	var dropped_idx := 0
	for kid in crates_in.keys():
		var k: Dictionary = (crates_in[kid] as Dictionary).duplicate(true)
		if int(k.get("held_by", 0)) != 0:
			k["held_by"] = 0
			k["pos"] = _vec3_to_arr(Vector3(-0.9 + float(dropped_idx % 4) * 0.65, 0.0, 2.2))
			dropped_idx += 1
		else:
			k["pos"] = _vec3_to_arr(k.get("pos", Vector3.ZERO))
		crates_out[kid] = k
	out["crates"] = crates_out
	for key in NESTED_POS_KEYS:
		if out.has(key):
			out[key] = _convert_nested_pos(out[key], true)
	if out.get("extinguishers", null) is Dictionary:
		# Wer speichert, während er einen Löscher trägt, findet ihn danach wieder im Halter.
		for ext_id in (out["extinguishers"] as Dictionary).keys():
			var ext: Variant = (out["extinguishers"] as Dictionary)[ext_id]
			if ext is Dictionary and int((ext as Dictionary).get("held_by", 0)) != 0:
				(ext as Dictionary)["held_by"] = 0
				(ext as Dictionary)["station"] = ext_id
	return out


func _deserialize_state(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)

	for key in ["racks", "coolers", "ups_units", "carts"]:
		var dict_in: Dictionary = out.get(key, {})
		var dict_out: Dictionary = {}
		for eid in dict_in.keys():
			var item: Dictionary = (dict_in[eid] as Dictionary).duplicate(true)
			item["pos"] = _arr_to_vec3(item.get("pos", [0.0, 0.0, 0.0]))
			if key == "carts":
				item["pushed_by"] = 0
			dict_out[eid] = item
		out[key] = dict_out

	var crates_in: Dictionary = out.get("crates", {})
	var crates_out: Dictionary = {}
	for kid in crates_in.keys():
		var k: Dictionary = (crates_in[kid] as Dictionary).duplicate(true)
		k["pos"] = _arr_to_vec3(k.get("pos", [0.0, 0.0, 0.0]))
		k["held_by"] = 0
		crates_out[kid] = k
	out["crates"] = crates_out
	for key in NESTED_POS_KEYS:
		if out.has(key):
			out[key] = _convert_nested_pos(out[key], false)
	if out.get("extinguishers", null) is Dictionary:
		# Wer speichert, während er einen Löscher trägt, findet ihn danach wieder im Halter.
		for ext_id in (out["extinguishers"] as Dictionary).keys():
			var ext: Variant = (out["extinguishers"] as Dictionary)[ext_id]
			if ext is Dictionary and int((ext as Dictionary).get("held_by", 0)) != 0:
				(ext as Dictionary)["held_by"] = 0
				(ext as Dictionary)["station"] = ext_id
	return out


## Wandelt alle "pos"-Felder in verschachtelten Daten um (z. B. eingelagerte Kisten in einem Deko-Regal).
func _convert_nested_pos(value: Variant, to_array: bool) -> Variant:
	if value is Dictionary:
		var d_out: Dictionary = {}
		for k in (value as Dictionary).keys():
			var v: Variant = value[k]
			if str(k) == "pos":
				d_out[k] = _vec3_to_arr(v) if to_array else _arr_to_vec3(v)
			else:
				d_out[k] = _convert_nested_pos(v, to_array)
		return d_out
	if value is Array:
		var a_out: Array = []
		for item in (value as Array):
			a_out.append(_convert_nested_pos(item, to_array))
		return a_out
	return value


func _vec3_to_arr(v: Variant) -> Array:
	if v is Vector3:
		var vec: Vector3 = v
		return [vec.x, vec.y, vec.z]
	if v is Array and v.size() >= 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return [0.0, 0.0, 0.0]


func _arr_to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	# Spielstände bis v2.4.1 enthalten Deko-Positionen als Text: "(x, y, z)".
	if v is String:
		var parts: PackedStringArray = (v as String).trim_prefix("(").trim_suffix(")").split(",")
		if parts.size() == 3:
			var vec := Vector3(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float())
			if SecurityGuard.is_finite_vec3(vec):
				return vec
	return Vector3.ZERO
