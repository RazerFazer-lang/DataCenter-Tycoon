extends SceneTree
## Misst Speicher und Grafikspeicher im Hauptmenü-Showcase bei einer Grafikstufe.
## 1. Listet die Texturen, die von Nodes, Materialien, Meshes und Skript-Variablen erreichbar sind (geschätzte Größe).
## 2. Schaltet Render-Effekte und interne Puffer nacheinander ab und zeigt, wie viel VRAM jeweils frei wird.
## Alle Änderungen gelten nur für diesen Testlauf, settings.cfg bleibt unberührt.
## Aufruf: godot --path . --resolution 1280x720 --script res://tests/mem_probe.gd -- q=3 [up=0|1|2]
## up= setzt den Upscaler (0 = Bilinear, 1 = FSR 1.0, 2 = FSR 2.2). Ohne up= gilt der Wert aus settings.cfg.
## res=BxH (z. B. res=1920x1080) erzwingt den Fenstermodus mit dieser Größe. Ohne res= setzt
## SettingsManager Fenstermodus und -größe aus settings.cfg, --resolution wirkt dann nicht.
## Ausgabe: Zeilen mit "MEM", Werte in MB.

const WARMUP_SEC := 6.0
const SETTLE_SEC := 2.0
const MB := 1048576.0
const TOP_TEXTURES := 30
const MAX_DEPTH := 6
## Reihenfolge: größte erwartete Verbraucher zuerst.
const EFFECTS: Array[String] = [
	"sdfgi_enabled",
	"volumetric_fog_enabled",
	"ssr_enabled",
	"ssil_enabled",
	"ssao_enabled",
	"glow_enabled",
]

## instance_id -> {bytes, desc, cls, path, origin, users}
var _tex_seen: Dictionary = {}
var _res_seen: Dictionary = {}


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	var quality := 3
	var upscaler := -1
	var res := Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("q="):
			quality = clampi(int(arg.substr(2)), 0, 3)
		elif arg.begins_with("up="):
			upscaler = clampi(int(arg.substr(3)), 0, 2)
		elif arg.begins_with("res="):
			var parts := arg.substr(4).split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				res = Vector2i(int(parts[0]), int(parts[1]))
			else:
				print("MEM res= ungültig: %s" % arg)
	await process_frame
	var settings := root.get_node_or_null("SettingsManager")
	if settings != null:
		settings.set("graphics_quality", quality)
		if upscaler >= 0:
			settings.set("upscaler", upscaler)
		if res.x >= 640 and res.y >= 360:
			# 0 = SettingsManager.WINDOW_WINDOWED
			settings.set("window_mode", 0)
			settings.set("window_size", res)
			# Setzt Fenster, UI-Skalierung und ruft am Ende apply_graphics_settings() auf.
			settings.call("apply_display_settings")
		elif upscaler >= 0:
			settings.call("apply_graphics_settings")
	await process_frame
	await process_frame
	print("MEM upscaler=%s res=%s fenster=%s" % [
		str(upscaler) if upscaler >= 0 else "aus settings.cfg",
		str(res) if res != Vector2i.ZERO else "aus settings.cfg",
		str(DisplayServer.window_get_size()),
	])
	_print_mem("vor_szene", quality)

	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(WARMUP_SEC).timeout
	_print_mem("basis", quality)
	_print_viewport_info()
	_print_scene_textures()

	var env := _find_environment()
	if env == null:
		print("MEM keine WorldEnvironment gefunden, Effekt-Schritte entfallen")
	else:
		for prop in EFFECTS:
			if not (prop in env):
				print("MEM %-28s unbekannte Eigenschaft" % prop)
				continue
			if not bool(env.get(prop)):
				print("MEM %-28s war schon aus" % prop)
				continue
			await _step(prop, func() -> void: env.set(prop, false))

	await _step("reflection_probes_aus", _hide_reflection_probes)
	await _step("punktlicht_schatten_aus", _disable_positional_shadows)
	await _step("sonnen_atlas_256", func() -> void: RenderingServer.directional_shadow_atlas_set_size(256, true))
	await _step("subviewports_2x2", _shrink_subviewports)
	if env != null and env.sky != null:
		await _step("himmel_radiance_32", func() -> void: env.sky.radiance_size = Sky.RADIANCE_SIZE_32)
	await _step("msaa_aus", func() -> void: root.msaa_3d = Viewport.MSAA_DISABLED)
	await _step("fsr2_taa_aus", func() -> void:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.use_taa = false)
	await _step("aufloesung_50", func() -> void: root.scaling_3d_scale = 0.5)
	_print_mem("alles_aus", quality)
	quit(0)


## Führt eine Änderung aus, wartet kurz und gibt den frei gewordenen Grafikspeicher aus.
func _step(label: String, action: Callable) -> void:
	var before_video := _video_mem()
	var before_tex := _tex_mem()
	action.call()
	await create_timer(SETTLE_SEC).timeout
	var now_video := _video_mem()
	print("MEM %-28s VRAM %.1f MB (frei: %.1f MB, davon Texturen %.1f MB)" % [
		label, now_video / MB, (before_video - now_video) / MB, (before_tex - _tex_mem()) / MB,
	])


func _print_viewport_info() -> void:
	print("MEM fenster=%s viewport=%s msaa_3d=%d scaling_mode=%d scale=%.2f taa=%s ssaa=%d" % [
		str(DisplayServer.window_get_size()), str(root.get_visible_rect().size),
		int(root.msaa_3d), int(root.scaling_3d_mode), root.scaling_3d_scale,
		str(root.use_taa), int(root.screen_space_aa),
	])


func _hide_reflection_probes() -> void:
	for n in root.find_children("*", "ReflectionProbe", true, false):
		(n as Node3D).visible = false


func _disable_positional_shadows() -> void:
	for n in root.find_children("*", "Light3D", true, false):
		if not (n is DirectionalLight3D):
			(n as Light3D).shadow_enabled = false
	for vp in _all_viewports():
		vp.positional_shadow_atlas_size = 0


func _shrink_subviewports() -> void:
	for n in root.find_children("*", "SubViewport", true, false):
		(n as SubViewport).size = Vector2i(2, 2)


func _all_viewports() -> Array[Viewport]:
	var list: Array[Viewport] = [root]
	for n in root.find_children("*", "SubViewport", true, false):
		list.append(n as Viewport)
	return list


# ---------------------------------------------------------------- Texturliste

func _print_scene_textures() -> void:
	_tex_seen.clear()
	_res_seen.clear()
	_walk_object(root, "/root", 0)
	for n in root.find_children("*", "", true, false):
		var node_path := str((n as Node).get_path())
		_walk_object(n, node_path, 0)
		if n is SubViewport:
			_add_texture((n as SubViewport).get_texture(), node_path + ":get_texture()")

	var rows: Array = _tex_seen.values()
	if rows.is_empty():
		print("MEM keine Texturen in der Szene gefunden")
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bytes"]) > int(b["bytes"]))

	var total := 0
	var by_class: Dictionary = {}
	for r in rows:
		var row: Dictionary = r
		total += int(row["bytes"])
		var cls := str(row["cls"])
		by_class[cls] = int(by_class.get(cls, 0)) + int(row["bytes"])
	print("MEM szene_texturen anzahl=%d summe=%.1f MB (geschätzt, ohne Schatten-/Reflexions-Atlas, SDFGI und Font-Caches)" % [rows.size(), total / MB])
	for cls in by_class.keys():
		print("MEM   klasse %-22s %8.1f MB" % [cls, int(by_class[cls]) / MB])
	for i in range(mini(TOP_TEXTURES, rows.size())):
		var row: Dictionary = rows[i]
		var src := str(row["path"])
		if src.is_empty():
			src = "(Laufzeit) " + str(row["origin"])
		print("MEM tex %8.1f MB  x%-3d %-20s %-30s %s" % [
			int(row["bytes"]) / MB, int(row["users"]), str(row["cls"]), str(row["desc"]), src.right(110),
		])


func _walk_object(obj: Object, origin: String, depth: int) -> void:
	if obj == null or depth > MAX_DEPTH:
		return
	for p in obj.get_property_list():
		var t := int(p.get("type", TYPE_NIL))
		if t != TYPE_OBJECT and t != TYPE_ARRAY and t != TYPE_DICTIONARY:
			continue
		var pname := str(p.get("name", ""))
		if pname.is_empty():
			continue
		_walk_value(obj.get(pname), origin + ":" + pname, depth)


func _walk_value(v: Variant, origin: String, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	if v is Texture:
		_add_texture(v as Texture, origin)
	elif v is Resource:
		var id := (v as Resource).get_instance_id()
		if _res_seen.has(id):
			return
		_res_seen[id] = true
		_walk_object(v as Object, origin, depth + 1)
	elif v is Array:
		for item in (v as Array):
			_walk_value(item, origin, depth + 1)
	elif v is Dictionary:
		for item in (v as Dictionary).values():
			_walk_value(item, origin, depth + 1)


func _add_texture(tex: Texture, origin: String) -> void:
	if tex == null:
		return
	var id := tex.get_instance_id()
	if _tex_seen.has(id):
		var known: Dictionary = _tex_seen[id]
		known["users"] = int(known["users"]) + 1
		return
	var info := _texture_info(tex)
	info["cls"] = tex.get_class()
	info["path"] = tex.resource_path
	info["origin"] = origin
	info["users"] = 1
	_tex_seen[id] = info


## Größe aus den echten Bilddaten (inkl. Mipmaps und Kompression), sonst Schätzung mit 4 Byte pro Pixel.
func _texture_info(tex: Texture) -> Dictionary:
	if tex is Texture2D:
		var t2 := tex as Texture2D
		var img: Image = t2.get_image()
		if img != null and not img.is_empty():
			return {
				"bytes": img.get_data_size(),
				"desc": "%dx%d fmt=%d mip=%s" % [img.get_width(), img.get_height(), img.get_format(), str(img.has_mipmaps())],
			}
		return {"bytes": t2.get_width() * t2.get_height() * 4, "desc": "%dx%d (geschätzt)" % [t2.get_width(), t2.get_height()]}
	if tex is TextureLayered:
		var tl := tex as TextureLayered
		var layer: Image = tl.get_layer_data(0) if tl.get_layers() > 0 else null
		var per_layer := layer.get_data_size() if layer != null else tl.get_width() * tl.get_height() * 4
		return {"bytes": per_layer * tl.get_layers(), "desc": "%dx%d layers=%d" % [tl.get_width(), tl.get_height(), tl.get_layers()]}
	if tex is Texture3D:
		var t3 := tex as Texture3D
		return {
			"bytes": t3.get_width() * t3.get_height() * t3.get_depth() * 4,
			"desc": "%dx%dx%d (geschätzt)" % [t3.get_width(), t3.get_height(), t3.get_depth()],
		}
	return {"bytes": 0, "desc": "unbekannt"}


# ---------------------------------------------------------------- Monitore

func _video_mem() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)


func _tex_mem() -> float:
	return Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)


func _print_mem(label: String, quality: int) -> void:
	print("MEM q=%d %-18s static=%.1f static_max=%.1f video=%.1f textures=%.1f buffers=%.1f" % [
		quality, label,
		Performance.get_monitor(Performance.MEMORY_STATIC) / MB,
		Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / MB,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / MB,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / MB,
	])
	print("MEM q=%d %-18s objects=%d nodes=%d resources=%d orphan_nodes=%d" % [
		quality, label,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])


func _find_environment() -> Environment:
	for n in root.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	var world := root.get_world_3d()
	if world != null and world.environment != null:
		return world.environment
	return null