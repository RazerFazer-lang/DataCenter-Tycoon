class_name MeshMerger
extends Node
## Fasst viele kleine, unbewegte Netze zu wenigen zusammen. Das Bild bleibt gleich, die Grafikkarte
## bekommt aber statt hunderter Zeichenaufrufe je Server nur noch einen je Material.
##
##   merge_primitives()  sofort, für Aufbauten aus Box/Zylinder (Kühlgeräte, Stecker)
##   queue_server()      im Hintergrund-Thread, für Server im Rack
## Die Geometrie der Bauteile liest es aus assets/merge_cache (tools/build_merge_cache.gd). Nur was dort
## fehlt, wird von der Grafikkarte zurückgeholt; das wartet jedes Mal auf das laufende Bild.

const FETCH_BUDGET_USEC := 4000
const CACHE_MAX := 96
const CACHE_DIR := "res://assets/merge_cache/"
## So lange darf das Anwenden fertiger Ergebnisse je Bild dauern.
const APPLY_BUDGET_USEC := 2500

## Ebene für alles, was weit draußen steht und sich bewegt (Laub, Verkehr, Tiere).
const OUTSIDE_LAYER := 1 << 10
## Ebene der eigenen (nur Schatten werfenden) Figur.
const LOCAL_BODY_LAYER := 1 << 11

static var _inst: MeshMerger
static var _mat_keys: Dictionary = {}
static var _flat_vals: Dictionary = {}
static var _flat_mats: Dictionary = {}
## Schlichte Materialien ohne Textur: Farbe steckt in der Eckenfarbe, Metall und Rauheit in den UVs.
## Gleiches Lichtmodell wie StandardMaterial3D, aber ein einziger Zeichenaufruf für alle.
const FLAT_SHADER := "
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, %s, diffuse_burley, specular_schlick_ggx;
varying flat vec2 mr;
void vertex() { mr = UV; }
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	METALLIC = mr.x;
	ROUGHNESS = mr.y;
	SPECULAR = 0.5;
}
"

var _jobs: Array = []
## sig -> {mesh_cold, mats_cold, mesh_hot, mats_hot}; mats: [{mat, hwl}]
var _cache: Dictionary = {}
## Schlüssel -> Flächen-Arrays (Quelldaten im Arbeitsspeicher)
var _arrays: Dictionary = {}
## Modell -> {Pfad|Fläche -> Arrays} aus assets/merge_cache; leeres Dictionary = keine Datei.
var _models: Dictionary = {}
var _task := -1
var _load_task := -1
## Statistik für Tests: wie oft musste die Grafikkarte doch gefragt werden?
var gpu_fetches := 0
var cache_hits := 0


static func instance() -> MeshMerger:
	if _inst == null or not is_instance_valid(_inst):
		_inst = MeshMerger.new()
		_inst.name = "MeshMerger"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


## Drehende Lüfter sitzen hinter Gittern: ihr Schatten ist nicht zu sehen, zwingt aber jede Lampe,
## ihre Schatten in jedem Bild neu zu zeichnen.
static func no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		no_shadow(c)


## Kleinteile unter max_size (Meter) werfen keinen Schatten: kleiner als ein Bildpunkt der Schattenkarte.
static func small_no_shadow(n: Node, max_size: float = 0.07) -> void:
	if n is Wildlife:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).skin == null:
		var mi := n as MeshInstance3D
		var sz := mi.mesh.get_aabb().size * (mi.global_transform.basis.get_scale() if mi.is_inside_tree() else mi.scale)
		if maxf(sz.x, maxf(sz.y, sz.z)) < max_size:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		small_no_shadow(c, max_size)


static func set_outside(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = OUTSIDE_LAYER
	for c in n.get_children():
		set_outside(c)


# ------------------------------------------------------------------ Sofort: Grundkörper

## Fasst alle Grundkörper unter root zusammen, die sich nicht bewegen. keep: Knoten, deren Teilbaum
## unangetastet bleibt (Lüfterräder, Türen). Gibt die Zahl der eingesparten Netze zurück.
static func merge_primitives(root: Node3D, keep: Array = []) -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	var groups: Dictionary = {}
	_collect_primitives(root, root, Transform3D.IDENTITY, keep, groups)
	var saved := 0
	for k in groups:
		var list: Array = groups[k]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		var first: MeshInstance3D = list[0][0]
		var ok := true
		for e in list:
			st.append_from((e[0] as MeshInstance3D).mesh, 0, e[1])
		var mesh := st.commit()
		if mesh == null or not ok:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material_of(first)
		mi.cast_shadow = first.cast_shadow
		mi.layers = first.layers
		mi.gi_mode = first.gi_mode
		mi.visibility_range_end = first.visibility_range_end
		mi.visibility_range_end_margin = first.visibility_range_end_margin
		mi.visibility_range_fade_mode = first.visibility_range_fade_mode
		root.add_child(mi)
		for e in list:
			var old: MeshInstance3D = e[0]
			if old.get_child_count() > 0:
				old.mesh = null
			else:
				old.queue_free()
		saved += list.size() - 1
	return saved


static func _collect_primitives(n: Node, root: Node3D, xf: Transform3D, keep: Array, groups: Dictionary) -> void:
	for c in n.get_children():
		if keep.has(c) or c.get_script() != null or c is CollisionObject3D or c is Skeleton3D:
			continue
		var cx := xf
		if c is Node3D:
			if not (c as Node3D).visible or (c as Node3D).top_level:
				continue
			cx = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is PrimitiveMesh:
			var mi := c as MeshInstance3D
			var mat := _material_of(mi)
			# Durchsichtiges bleibt einzeln, sonst stimmt die Sortierung nicht mehr.
			var glassy := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			if mat != null and not glassy and mi.material_overlay == null and not mi.has_meta("spin_axis") and cx.basis.determinant() > 0.0:
				var key := "%d|%d|%d|%d|%.2f" % [mat.get_instance_id(), mi.cast_shadow, mi.layers, mi.gi_mode, mi.visibility_range_end]
				if not groups.has(key):
					groups[key] = []
				(groups[key] as Array).append([mi, cx])
		_collect_primitives(c, root, cx, keep, groups)


static func _material_of(mi: MeshInstance3D) -> Material:
	if mi.material_override != null:
		return mi.material_override
	if mi.mesh is PrimitiveMesh and (mi.mesh as PrimitiveMesh).material != null:
		return (mi.mesh as PrimitiveMesh).material
	return mi.get_active_material(0)


# ------------------------------------------------------------------ Verteilt: Server im Rack

## srv: fertig gebauter Server (PartFx schon angeschlossen). keep: Lüfter, die sich drehen.
func queue_server(srv: Node3D, sig: String, keep: Array, fx: PartFx) -> void:
	# Ohne Bildschirm gibt es nichts zu zeichnen (dedizierter Server).
	if DisplayServer.get_name() == "headless":
		return
	_jobs.append({"srv": srv, "sig": sig, "keep": keep.duplicate(), "fx": fx, "state": 0})


func is_idle() -> bool:
	return _jobs.is_empty()


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	# Mehrere Aufträge je Bild, solange es schnell geht (gleiche Server kommen aus dem Speicher).
	while not _jobs.is_empty() and Time.get_ticks_usec() - t0 < APPLY_BUDGET_USEC:
		if not _step(_jobs[0], t0):
			return


## Ein Schritt am vordersten Auftrag. false = in diesem Bild nicht weitermachen.
func _step(job: Dictionary, t0: int) -> bool:
	if not is_instance_valid(job["srv"]) or not is_instance_valid(job["fx"]) or (job["srv"] as Node).is_queued_for_deletion():
		# Läuft dafür noch ein Thread, wird sein Ergebnis beim Abholen verworfen.
		if int(job["state"]) == 1 and not WorkerThreadPool.is_task_completed(_load_task):
			return false
		if int(job["state"]) == 3 and not WorkerThreadPool.is_task_completed(_task):
			return false
		_wait_tasks(job)
		_jobs.pop_front()
		return true
	match int(job["state"]):
		0:
			if _cache.has(job["sig"]):
				_apply(job, _cache[job["sig"]], _gather(job))
				_jobs.pop_front()
				return true
			job["entries"] = _gather(job)
			var need: Array = []
			for e in job["entries"]:
				var mid := str(e["model"])
				if mid != "" and not _models.has(mid) and not need.has(mid):
					need.append(mid)
			job["state"] = 1
			if not need.is_empty():
				var got := {}
				job["loaded"] = got
				_load_task = WorkerThreadPool.add_task(_load_models.bind(need, got), false, "MeshMerger Cache")
			return true
		1:
			if job.has("loaded"):
				if not WorkerThreadPool.is_task_completed(_load_task):
					return false
				WorkerThreadPool.wait_for_task_completion(_load_task)
				for k in (job["loaded"] as Dictionary):
					_models[k] = job["loaded"][k]
				job.erase("loaded")
			job["state"] = 2
			return true
		2:
			# Aus dem Teile-Cache, sonst (selten) von der Grafikkarte, mit Zeitbudget.
			for e in job["entries"]:
				if _arrays.has(e["key"]):
					continue
				var a := _cached_arrays(e)
				if a.is_empty():
					if Time.get_ticks_usec() - t0 > FETCH_BUDGET_USEC:
						return false
					a = (e["mesh"] as Mesh).surface_get_arrays(int(e["surface"]))
					gpu_fetches += 1
				else:
					cache_hits += 1
				_arrays[e["key"]] = a
			# Der Thread bekommt nur reine Daten, keine Knoten.
			var plain: Array = []
			for e in job["entries"]:
				plain.append({"g": e["group"], "xf": e["xf"], "a": _arrays[e["key"]], "flat": e["flat"]})
			job["out"] = {}
			_task = WorkerThreadPool.add_task(_build.bind(plain, job["out"]), false, "MeshMerger")
			job["state"] = 3
			return false
		3:
			if not WorkerThreadPool.is_task_completed(_task):
				return false
			WorkerThreadPool.wait_for_task_completion(_task)
			var res := _finish(job)
			if _cache.size() >= CACHE_MAX:
				_cache.clear()
			_cache[job["sig"]] = res
			_apply(job, res, job["entries"])
			_jobs.pop_front()
			if _arrays.size() > 6000:
				_arrays.clear()
			return true
	return false


func _wait_tasks(job: Dictionary) -> void:
	if int(job.get("state", 0)) == 1 and job.has("loaded"):
		WorkerThreadPool.wait_for_task_completion(_load_task)
	if int(job.get("state", 0)) == 3:
		WorkerThreadPool.wait_for_task_completion(_task)


func _exit_tree() -> void:
	if not _jobs.is_empty():
		_wait_tasks(_jobs[0])
	_jobs.clear()


## Läuft im Hintergrund: Cache-Dateien der Modelle lesen und entpacken.
static func _load_models(ids: Array, out: Dictionary) -> void:
	for id in ids:
		var path := CACHE_DIR + str(id) + ".bin"
		var data := {}
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var size := f.get_32()
				var packed := f.get_buffer(f.get_length() - 4)
				var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
				var v: Variant = bytes_to_var(raw)
				if v is Dictionary:
					data = v
		out[id] = data


## Flächendaten aus dem Teile-Cache, wenn sie zur geladenen Fläche passen. Leer = nicht da.
func _cached_arrays(e: Dictionary) -> Array:
	if e["mesh"] is PrimitiveMesh:
		return (e["mesh"] as PrimitiveMesh).get_mesh_arrays()
	var m: Dictionary = _models.get(str(e["model"]), {})
	var a: Variant = m.get(str(e["mkey"]))
	if not (a is Array) or (a as Array).size() < Mesh.ARRAY_MAX or a[Mesh.ARRAY_VERTEX] == null:
		return []
	# Passt die Datei nicht mehr zum Modell (neu gebaut, Cache alt), lieber von der Grafikkarte holen.
	if (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != (e["mesh"] as ArrayMesh).surface_get_array_len(int(e["surface"])):
		return []
	return a


## Alle unbewegten Flächen des Servers samt Lage und Material.
func _gather(job: Dictionary) -> Array:
	var out: Array = []
	var fx: PartFx = job["fx"]
	_walk(job["srv"], Transform3D.IDENTITY, job["keep"], fx, out, null)
	return out


func _walk(n: Node, xf: Transform3D, keep: Array, fx: PartFx, out: Array, model: Node) -> void:
	for c in n.get_children():
		if c == fx or keep.has(c) or c.get_script() != null:
			continue
		var cx := xf
		if c is Node3D:
			if not (c as Node3D).visible:
				continue
			cx = xf * (c as Node3D).transform
		var cm := model
		if c.scene_file_path.begins_with("res://assets/models/"):
			cm = c
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and not c.has_meta("flow") and not c.has_meta("spin_axis") and cx.basis.determinant() > 0.0:
			var mi := c as MeshInstance3D
			var m := mi.mesh
			var plain := (m is ArrayMesh and (m as ArrayMesh).get_blend_shape_count() == 0 and mi.skin == null) or m is PrimitiveMesh
			if plain and _all_opaque(mi):
				var hot := fx.overlays(mi)
				for s in m.get_surface_count():
					var mat := mi.get_active_material(s)
					var fl := flat_values(mat)
					var mid := cm.scene_file_path.get_file().get_basename() if cm != null else ""
					out.append({"flat": fl, "node": mi, "mesh": m, "surface": s, "xf": cx, "mat": mat,
						"key": ("%s|%s|%d" % [mid, cm.get_path_to(mi), s]) if cm != null else ("%d:%d" % [m.get_instance_id(), s]),
						"model": mid, "mkey": ("%s|%d" % [cm.get_path_to(mi), s]) if cm != null else "",
						"hwl": mat.resource_name if mat != null and mat.resource_name.begins_with("HWL_") else "",
						"group": ("H|" if hot else "C|") + (("FLAT%d" % int(fl[3])) if not fl.is_empty() else material_key(mat))})
		_walk(c, cx, keep, fx, out, cm)


func _all_opaque(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat == null or not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			return false
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	return true


static func flat_material(cull: int) -> Material:
	if not _flat_mats.has(cull):
		var sh := Shader.new()
		sh.code = FLAT_SHADER % ["cull_back" if cull == BaseMaterial3D.CULL_BACK else ("cull_disabled" if cull == BaseMaterial3D.CULL_DISABLED else "cull_front")]
		var m := ShaderMaterial.new()
		m.shader = sh
		_flat_mats[cull] = m
	return _flat_mats[cull]


## [Farbe, Metall, Rauheit, Cull], wenn das Material nur aus diesen Werten besteht, sonst leer.
static func flat_values(m: Material) -> Array:
	if m == null or not (m is StandardMaterial3D) or m.resource_name.begins_with("HWL_"):
		return []
	var id := m.get_instance_id()
	if _flat_vals.has(id):
		return _flat_vals[id]
	var s := m as StandardMaterial3D
	var ok := s.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and s.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
		and s.diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY and s.specular_mode == BaseMaterial3D.SPECULAR_SCHLICK_GGX \
		and is_equal_approx(s.metallic_specular, 0.5) and not s.vertex_color_use_as_albedo and s.next_pass == null \
		and s.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and s.blend_mode == BaseMaterial3D.BLEND_MODE_MIX \
		and not s.grow and not s.proximity_fade_enabled and s.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and not s.no_depth_test
	for f in BaseMaterial3D.FEATURE_MAX:
		ok = ok and not s.get_feature(f)
	for t in BaseMaterial3D.TEXTURE_MAX:
		ok = ok and s.get_texture(t) == null
	_flat_vals[id] = [s.albedo_color, s.metallic, s.roughness, int(s.cull_mode)] if ok else []
	if _flat_vals.size() > 4000:
		_flat_vals.clear()
		return flat_values(m)
	return _flat_vals[id]


## Gleich aussehende Materialien aus verschiedenen Dateien bekommen denselben Schlüssel.
static func material_key(m: Material) -> String:
	if m == null:
		return "null"
	var id := m.get_instance_id()
	if _mat_keys.has(id):
		return _mat_keys[id]
	var key := ""
	if m.resource_name.begins_with("HWL_"):
		key = m.resource_name
	elif m is StandardMaterial3D:
		var parts: Array = []
		for p in m.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
				continue
			var nm := str(p["name"])
			if nm.begins_with("resource_") or nm == "script":
				continue
			var v: Variant = m.get(nm)
			parts.append(str((v as Object).get_instance_id()) if v is Object else var_to_str(v))
		key = "|".join(PackedStringArray(parts)).sha1_text()
	else:
		key = "i%d" % id
	if _mat_keys.size() > 4000:
		_mat_keys.clear()
	_mat_keys[id] = key
	return key


# Läuft im Hintergrund-Thread: nur Rechenarbeit an Arrays.
func _build(plain: Array, out: Dictionary) -> void:
	var by_group: Dictionary = {}
	for e in plain:
		var g := str(e["g"])
		if not by_group.has(g):
			by_group[g] = []
		(by_group[g] as Array).append(e)
	var surf: Dictionary = {}
	for g in by_group:
		var list: Array = by_group[g]
		var use_tan := true
		var use_col := false
		var flat := not (list[0]["flat"] as Array).is_empty()
		if flat:
			use_tan = false
			use_col = true
		for e in list:
			if flat:
				break
			var a: Array = e["a"]
			if a[Mesh.ARRAY_TANGENT] == null:
				use_tan = false
			if a[Mesh.ARRAY_COLOR] != null:
				use_col = true
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var tans := PackedFloat32Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for e in list:
			var a: Array = e["a"]
			var xf: Transform3D = e["xf"]
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var base := verts.size()
			verts.append_array(xf * v)
			var nb := xf.basis.inverse().transposed()
			var nn: PackedVector3Array = Transform3D(nb, Vector3.ZERO) * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)
			for i in nn.size():
				nn[i] = nn[i].normalized()
			norms.append_array(nn)
			if use_tan:
				var tt: PackedFloat32Array = (a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate()
				for i in range(0, tt.size(), 4):
					var t3 := (xf.basis * Vector3(tt[i], tt[i + 1], tt[i + 2])).normalized()
					tt[i] = t3.x
					tt[i + 1] = t3.y
					tt[i + 2] = t3.z
				tans.append_array(tt)
			if flat:
				var fv: Array = e["flat"]
				var fu := PackedVector2Array()
				fu.resize(v.size())
				fu.fill(Vector2(float(fv[1]), float(fv[2])))
				uvs.append_array(fu)
				var fc := PackedColorArray()
				fc.resize(v.size())
				fc.fill(fv[0])
				cols.append_array(fc)
			elif a[Mesh.ARRAY_TEX_UV] != null:
				uvs.append_array(a[Mesh.ARRAY_TEX_UV])
			else:
				var zu := PackedVector2Array()
				zu.resize(v.size())
				uvs.append_array(zu)
			if use_col and not flat:
				if a[Mesh.ARRAY_COLOR] != null:
					cols.append_array(a[Mesh.ARRAY_COLOR])
				else:
					var wc := PackedColorArray()
					wc.resize(v.size())
					wc.fill(Color.WHITE)
					cols.append_array(wc)
			if a[Mesh.ARRAY_INDEX] != null:
				var ii: PackedInt32Array = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
				for i in ii.size():
					ii[i] += base
				idx.append_array(ii)
			else:
				var ni := PackedInt32Array()
				ni.resize(v.size())
				for i in v.size():
					ni[i] = base + i
				idx.append_array(ni)
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		if use_tan:
			arr[Mesh.ARRAY_TANGENT] = tans
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if use_col:
			arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		surf[g] = arr
	# Wie beim Import: vereinfachte Stufen für die Ferne.
	for pre in ["C|", "H|"]:
		var im := ImporterMesh.new()
		var order: Array = []
		for g in surf:
			if str(g).begins_with(pre):
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, surf[g])
				order.append(g)
		if not order.is_empty():
			im.generate_lods(20.0, 60.0, [])
		out[pre] = {"im": im, "order": order}


func _finish(job: Dictionary) -> Dictionary:
	var mats: Dictionary = {}
	for e in job["entries"]:
		if not mats.has(e["group"]):
			var fl: Array = e["flat"]
			mats[e["group"]] = {"mat": flat_material(int(fl[3])) if not fl.is_empty() else e["mat"], "hwl": e["hwl"]}
	var res := {}
	for pre in ["C|", "H|"]:
		var o: Dictionary = job["out"][pre]
		if (o["order"] as Array).is_empty():
			continue
		var list: Array = []
		for g in o["order"]:
			list.append(mats[g])
		res[pre] = {"mesh": (o["im"] as ImporterMesh).get_mesh(), "mats": list}
	job.erase("out")
	job.erase("plain")
	return res


func _apply(job: Dictionary, res: Dictionary, entries: Array) -> void:
	if entries.is_empty():
		return
	var srv: Node3D = job["srv"]
	var fx: PartFx = job["fx"]
	var first: MeshInstance3D = entries[0]["node"]
	# Die Leuchten dieses Servers (jeder Server blinkt für sich).
	var own_led: Dictionary = {}
	for e in entries:
		if str(e["hwl"]) != "":
			own_led[e["hwl"]] = e["mat"]
	for pre in res:
		var r: Dictionary = res[pre]
		var mi := MeshInstance3D.new()
		mi.name = "Merged_" + ("hot" if pre == "H|" else "cold")
		mi.mesh = r["mesh"]
		var mats: Array = r["mats"]
		for s in mats.size():
			var led := str(mats[s]["hwl"])
			mi.set_surface_override_material(s, own_led.get(led, mats[s]["mat"]) if led != "" else mats[s]["mat"])
		mi.cast_shadow = first.cast_shadow
		mi.layers = first.layers
		mi.visibility_range_end = first.visibility_range_end
		mi.visibility_range_end_margin = first.visibility_range_end_margin
		srv.add_child(mi)
		if pre == "H|":
			fx.add_overlay_mesh(mi)
	for e in entries:
		var n: MeshInstance3D = e["node"]
		if is_instance_valid(n) and n.mesh != null:
			fx.drop_overlay_mesh(n)
			n.mesh = null
