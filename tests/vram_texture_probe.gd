extends SceneTree
## Misst die Texturen aus .glb-Modellen und Bilddateien im Projekt (Punkt 2.7 im Optimierungsdokument).
## Aufruf: Godot --path <projekt> --script res://tests/vram_texture_probe.gd
## Nicht headless starten: get_image() braucht einen echten Renderer.
## Größe = Image.get_data_size() inklusive Mipmaps, also etwa der Platz im Grafikspeicher.

const EXTENSIONS := ["glb", "gltf", "png", "jpg", "jpeg", "webp"]

var _seen: Dictionary = {}
var _records: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var files: PackedStringArray = []
	_collect("res://", files)
	for path in files:
		var ext := path.get_extension().to_lower()
		if ext == "glb" or ext == "gltf":
			var ps := load(path) as PackedScene
			if ps == null:
				print("VRAMPROBE FEHLER laden: %s" % path)
				continue
			var inst := ps.instantiate()
			if inst == null:
				continue
			_walk(inst, path)
			inst.free()
		else:
			var tex := load(path) as Texture2D
			if tex != null:
				_add_tex(tex, path, "datei")

	_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bytes"]) > int(b["bytes"]))
	var total := 0
	var total_glb := 0
	for r in _records:
		total += int(r["bytes"])
		if str(r["src"]).get_extension().to_lower() in ["glb", "gltf"]:
			total_glb += int(r["bytes"])
		print("VRAMPROBE %7.1f MB  %5dx%-5d fmt=%-2d komp=%-5s mips=%-5s %s [%s]" % [
			float(r["bytes"]) / 1048576.0, int(r["w"]), int(r["h"]), int(r["fmt"]),
			str(r["compressed"]), str(r["mips"]), str(r["src"]), str(r["slot"])])
	print("VRAMPROBE SUMME %d Texturen: %.1f MB, davon aus Modellen %.1f MB" % [
		_records.size(), float(total) / 1048576.0, float(total_glb) / 1048576.0])
	quit(0)


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var p := dir.path_join(entry)
			if d.current_is_dir():
				_collect(p, out)
			elif entry.get_extension().to_lower() in EXTENSIONS:
				out.append(p)
		entry = d.get_next()
	d.list_dir_end()


func _walk(n: Node, src: String) -> void:
	if n is GeometryInstance3D:
		_add_mat((n as GeometryInstance3D).material_override, src)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				_add_mat(mi.mesh.surface_get_material(s), src)
				_add_mat(mi.get_surface_override_material(s), src)
	for c in n.get_children():
		_walk(c, src)


func _add_mat(m: Material, src: String) -> void:
	if m == null:
		return
	for p in m.get_property_list():
		if int(p["type"]) != TYPE_OBJECT:
			continue
		var v: Variant = m.get(str(p["name"]))
		if v is Texture2D:
			_add_tex(v as Texture2D, src, str(p["name"]))


func _add_tex(t: Texture2D, src: String, slot: String) -> void:
	if _seen.has(t):
		return
	_seen[t] = true
	var img := t.get_image()
	if img == null or img.is_empty():
		_records.append({"src": src, "slot": slot, "w": t.get_width(), "h": t.get_height(),
			"fmt": -1, "compressed": false, "mips": false, "bytes": 0})
		return
	_records.append({"src": src, "slot": slot, "w": img.get_width(), "h": img.get_height(),
		"fmt": img.get_format(), "compressed": img.is_compressed(), "mips": img.has_mipmaps(),
		"bytes": img.get_data_size()})