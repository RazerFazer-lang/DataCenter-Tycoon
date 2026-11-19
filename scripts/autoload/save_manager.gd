extends Node
## Handles saving, listing, loading, and deleting DataCenter Tycoon Co-op worlds
## as clean human-readable JSON files in user://saves/. Backward-compatible with v0.2 saves.

const SAVES_SUBDIR := "saves"
const SAVE_FORMAT_VERSION := 2


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


func save_world(save_id: String, display_name: String, state_data: Dictionary) -> Dictionary:
	if not _ensure_saves_dir():
		return {"ok": false, "error": "Speicherordner konnte nicht erstellt werden."}

	var clean_id := sanitize_save_id(save_id)
	var clean_display := display_name.strip_edges()
	if clean_display.is_empty():
		clean_display = clean_id

	var serialized_state := _serialize_state(state_data)
	var rack_count := (state_data.get("racks", {}) as Dictionary).size()
	var payload := {
		"version": SAVE_FORMAT_VERSION,
		"save_id": clean_id,
		"display_name": clean_display,
		"saved_at": Time.get_datetime_string_from_system(false, true),
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
		return {"ok": false, "error": "Datei konnte nicht geschrieben werden: %s" % path}

	file.store_string(json_text)
	file.close()
	return {"ok": true, "save_id": clean_id, "display_name": clean_display, "path": path}


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
	return {
		"ok": true,
		"save_id": str(root.get("save_id", save_id)),
		"display_name": str(root.get("display_name", save_id)),
		"saved_at": str(root.get("saved_at", "")),
		"state": state_dict,
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
	out["extinguisher_held_by"] = 0
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
	out["extinguisher_held_by"] = 0
	return out


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
	return Vector3.ZERO
