extends SceneTree
## Benchmark: feste Blickpunkte, feste Welt, Ergebnis als Tabelle und JSON.
##   godot --path . --resolution 1280x720 -s res://tests/perf_bench.gd -- [Optionen]
## Optionen:
##   --save=<id>         eigenen Spielstand laden (sonst eine feste Testwelt mit 12 vollen Racks)
##   --spots=a,b         nur diese Blickpunkte
##   --secs=3            Messdauer je Blickpunkt
##   --size=2560x1440    Fenstergröße (Standard: 2560x1440)
##   --quality=3         Grafikstufe 0–3 (Standard: 3 = Ultra, FSR 2.2, 100 %)
##   --hide=Klasse,...   Knoten dieser Klassen ausblenden (Ursachen suchen)
##   --shots=<ordner>    je Blickpunkt ein Bild speichern (zum Vergleichen)
## Ergebnis: Tabelle auf der Konsole, user://perf_bench/last.json; liegt dort schon ein Lauf,
## steht die Veränderung in Prozent dahinter.

const SPOTS := {
	"himmel": [Vector3(2, 6.0, -2), Vector3(20, 14, 12)],
	"garage": [Vector3(3.8, 1.65, 2.8), Vector3(-3, 1.2, -1)],
	"racks": [Vector3(0.5, 1.65, 2.0), Vector3(0, 1.0, -3)],
	"halle": [Vector3(1.0, 1.7, 0.5), Vector3(20, 1.2, 0)],
	"tor_raus": [Vector3(0, 1.65, 2.0), Vector3(0, 1.3, 14)],
	"strasse": [Vector3(-3, 1.7, 14), Vector3(3, 1.5, 0)],
	"hof_weit": [Vector3(-9, 1.7, 9), Vector3(25, 1.5, -5)],
	"hinten": [Vector3(-9.5, 1.7, -8.5), Vector3(20, 2.5, -6)],
	"dach": [Vector3(2, 6.0, -2), Vector3(20, 2.0, 20)],
	"nord": [Vector3(-6.0, 1.7, -322.0), Vector3(6.0, 1.0, -318.0)],
}

var gs: Node
var main: Node
var cam: Camera3D


func wait(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		if cam != null and not cam.current:
			cam.make_current()
		await process_frame


func _initialize() -> void:
	var opt := {"save": "", "spots": SPOTS.keys(), "secs": 3.0, "size": Vector2i(2560, 1440), "quality": 3, "hide": [], "shots": ""}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"save": opt["save"] = kv[1]
			"spots": opt["spots"] = Array(kv[1].split(","))
			"secs": opt["secs"] = float(kv[1])
			"size": opt["size"] = Vector2i(int(kv[1].get_slice("x", 0)), int(kv[1].get_slice("x", 1)))
			"quality": opt["quality"] = clampi(int(kv[1]), 0, 3)
			"hide": opt["hide"] = Array(kv[1].split(","))
			"shots": opt["shots"] = kv[1]
	await process_frame
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var sm := root.get_node("SettingsManager")
	sm.graphics_quality = opt["quality"]
	sm.anti_aliasing = 3
	sm.upscaler = 2
	sm.render_scale = 1.0
	sm.vsync = false
	sm.max_fps = 0
	sm.window_mode = 0
	gs = root.get_node("GameState")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait(0.5)
	main.get("intro_splash").set_process(false)
	main.get("intro_splash").visible = false
	main.get("loading_screen").visible = false
	main.set("_startup_done", true)
	# Ohne Aufwärm-Fahrt beim Betreten: die Messung steuert die Kamera selbst.
	main.set("_session_warmed", true)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = opt["size"]
	var nm := root.get_node("NetworkManager")
	if opt["save"] != "":
		var l: Dictionary = root.get_node("SaveManager").load_world_file(opt["save"])
		if not bool(l.get("ok", false)):
			print("BENCH Spielstand nicht gefunden: ", opt["save"])
			quit(1)
			return
		nm.call("_start_host_internal", "Bench", 7876, l["state"], str(l["save_id"]) + "_bench", "Bench", "", false, false)
	else:
		nm.call("_start_host_internal", "Bench", 7876, {}, "", "Bench", "", false, false)
		await wait(1.0)
		_build_test_world()
	await wait(2.0)
	gs.time_of_day = 0.5
	gs.weather_state = "clear"
	gs._weather_timer = 99999.0
	gs.clock_scale = 0.0
	sm.apply_graphics_settings()
	root.size = opt["size"]
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for h in opt["hide"]:
		for n in root.find_children("*", str(h), true, false):
			if "visible" in n:
				n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
	cam = Camera3D.new()
	cam.fov = 75
	root.add_child(cam)
	var lp = main.get("world").local_player
	if lp != null:
		cam.cull_mask = lp._camera.cull_mask
		cam.near = lp._camera.near
		cam.far = lp._camera.far
		lp.ui_locked = true
	main.get("hud").visible = false
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	# Erst alles einmal sehen lassen, damit Zusammenfassen und Shader fertig sind.
	var tm := Time.get_ticks_msec()
	await wait(2.0)
	var mm = load("res://scripts/world/mesh_merger.gd").call("instance")
	while not mm.is_idle() and Time.get_ticks_msec() - tm < 120000:
		await wait(0.25)
	var merge_s := (Time.get_ticks_msec() - tm) / 1000.0
	await wait(2.0)
	var result := {"date": Time.get_datetime_string_from_system(), "version": ProjectSettings.get_setting("application/config/version"),
		"save": opt["save"], "size": "%dx%d" % [opt["size"].x, opt["size"].y], "quality": opt["quality"], "spots": {}}
	result["tick_ms"] = _measure_tick()
	result["merge_s"] = snappedf(merge_s, 0.1)
	result["vram_mb"] = roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	result["tex_mb"] = roundi(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)
	var live := 0
	for r in gs.racks.values():
		live += int(bool(r.get("powered", false)))
	print("BENCH %s, %s, Stufe %d, %d Racks (%d mit Strom)" % [result["version"], result["size"], opt["quality"], gs.racks.size(), live])
	for s in opt["spots"]:
		if not SPOTS.has(s):
			continue
		var sp: Array = SPOTS[s]
		if lp != null:
			lp.global_position = Vector3(sp[0].x, sp[0].y - 1.6, sp[0].z) if sp[0].y < 3.0 else Vector3(0, 0.1, 0)
		cam.global_position = sp[0]
		cam.look_at(sp[1])
		_restore_window(opt["size"])
		await wait(2.0)
		var n := 0
		var gpu := 0.0
		var cpu := 0.0
		var frames: Array = []
		var drawn0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < float(opt["secs"]) * 1e6:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			n += 1
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		# Minimiert Windows das Fenster (Fokuswechsel), zählt das Spiel weiter, zeichnet aber nicht: ungültig.
		var drawn := Engine.get_frames_drawn() - drawn0
		frames.sort()
		var total: float = frames.reduce(func(a, b): return a + b, 0.0)
		result["spots"][s] = {
			"fps": snappedf(n * 1000.0 / total, 0.1), "ms": snappedf(total / n, 0.01), "p99": snappedf(frames[int(n * 0.99)], 0.01),
			"gpu": snappedf(gpu / n, 0.01), "cpu": snappedf(cpu / n, 0.01),
			"draws": RenderingServer.viewport_get_render_info(vp, 0, 2), "shadow_draws": RenderingServer.viewport_get_render_info(vp, 1, 2),
			"prims": RenderingServer.viewport_get_render_info(vp, 0, 1) + RenderingServer.viewport_get_render_info(vp, 1, 1),
			"valid": drawn >= int(n * 0.95),
		}
		if opt["shots"] != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(str(opt["shots"]).path_join(s + ".png"))
	_report(result)
	quit()


## Feste Testwelt: drei Hallen offen, 12 Racks mit je 4–6 Servern, Leistenkette, Kühlung, USV.
func _build_test_world() -> void:
	gs.room_level = 2
	gs.halle_nord_owned = true
	gs.halle_nord_changed.emit()
	gs.money = 9999999.0
	gs.power_tier = gs.POWER_TIERS.size() - 1
	var hc: Script = load("res://scripts/data/hardware_catalog.gd")
	var boards := ["web_server", "storage_server", "gpu_server"]
	for r in 12:
		var id := "bench_r%d" % r
		var rt := "rack_pro" if r % 2 == 0 else "rack"
		var pos := Vector3(-3.0 + float(r % 6) * 1.2 + (7.0 if r >= 6 else 0.0), 0.0, -1.2 if r < 6 else 1.4)
		gs.racks[id] = gs._make_rack_data(id, rt, pos, 0.0 if r < 6 else PI)
		var slots: Array = gs.racks[id]["slots"]
		for i in slots.size():
			var comps := {}
			for cat in ["cpu", "gpu", "ram", "storage", "cooling", "psu"]:
				var parts: Array = hc.call("get_category_parts", cat)
				comps[cat] = str(parts[(r * 3 + i * 5 + cat.length()) % parts.size()]["id"])
			(slots[i] as Dictionary).merge({"item_type": boards[(r + i) % 3], "state": "ok", "components": comps, "build_quality": 90}, true)
	# Sechs Leisten an eigenen Abgängen (Halle C), je zwei Racks: so löst nichts aus.
	for k in 6:
		var did := "bench_s%d" % k
		gs.decor_items[did] = {"id": did, "item_type": "prop_power_strip", "pos": Vector3(-3.0 + 1.2 * k, 0, -2.6), "rot_y": 0.0, "wall": false, "stored_items": []}
	gs._broadcast_decor_items()
	gs._broadcast_racks()
	for k in 6:
		gs._rpc_req_connect_cable("power", gs.HALL_C_BREAKER_ID, "bench_s%d" % k, -1, -1)
	for r in 12:
		gs._rpc_req_connect_cable("power", "bench_s%d" % (r % 6), "bench_r%d" % r, -1, -1)
		gs._rpc_req_connect_cable("network", gs.WALL_ROUTER_ID if r == 0 else "bench_r0", "bench_r%d" % r, -1, -1)
	for c in 3:
		var cid: String = gs._alloc_id("cooler")
		gs.coolers[cid] = {"id": cid, "cooler_type": "cool_inrow", "pos": Vector3(3.5 + c * 4.0, 0, 3.0), "rot_y": PI, "powered": false}
	gs._broadcast_coolers()
	for r in 12:
		for s in gs.racks["bench_r%d" % r]["slots"]:
			(s as Dictionary)["offline"] = false
	gs._recalculate_networks_and_metrics()
	gs._broadcast_racks()


## Hat Windows das Fenster weggeklappt, wieder herstellen.
func _restore_window(size: Vector2i) -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED or not DisplayServer.window_can_draw():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		root.size = size


## Simulationstakt allein (ohne Zeichnen): Mittel aus 10 Schritten.
func _measure_tick() -> float:
	gs.set_process(false)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		gs._run_simulation_step(0.5)
	gs.set_process(true)
	return snappedf((Time.get_ticks_usec() - t0) / 10000.0, 0.01)


func _report(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://perf_bench")
	var prev := {}
	var f := FileAccess.open("user://perf_bench/last.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and str(parsed.get("save", "")) == str(result["save"]) and str(parsed.get("size", "")) == str(result["size"]):
			prev = parsed
	var pt: float = float(prev.get("tick_ms", 0.0))
	print("BENCH Grafikspeicher %d MB, davon Texturen %d MB%s" % [result["vram_mb"], result["tex_mb"], _delta(result["tex_mb"], float(prev.get("tex_mb", 0.0)), true)])
	print("BENCH Takt: %.2f ms%s   Server zusammengefasst nach %.1f s%s" % [result["tick_ms"], _delta(result["tick_ms"], pt, true), result["merge_s"], _delta(result["merge_s"], float(prev.get("merge_s", 0.0)), true)])
	print("BENCH %-9s %7s %7s %7s %7s %7s %7s %7s" % ["Punkt", "FPS", "ms", "p99", "GPU", "CPU", "Draws", "Schatten"])
	for s in result["spots"]:
		var r: Dictionary = result["spots"][s]
		var p: Dictionary = (prev.get("spots", {}) as Dictionary).get(s, {})
		if not bool(r.get("valid", true)):
			print("BENCH %-9s ungültig: Fenster war minimiert oder verdeckt (Bilder nicht gezeichnet)" % s)
			continue
		print("BENCH %-9s %7.1f %7.2f %7.2f %7.2f %7.2f %7d %7d%s" % [s, r["fps"], r["ms"], r["p99"], r["gpu"], r["cpu"], r["draws"], r["shadow_draws"],
			("   FPS" + _delta(r["fps"], float(p.get("fps", 0.0)), false)) if not p.is_empty() and bool(p.get("valid", true)) else ""])
	var w := FileAccess.open("user://perf_bench/last.json", FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify(result, "  "))
	print("BENCH gespeichert: ", ProjectSettings.globalize_path("user://perf_bench/last.json"))


func _delta(now: float, before: float, lower_is_better: bool) -> String:
	if before <= 0.0:
		return ""
	var d := (now - before) / before * 100.0
	return " (%+.0f %%%s)" % [d, " besser" if (d < 0.0) == lower_is_better and absf(d) >= 1.0 else ""]
