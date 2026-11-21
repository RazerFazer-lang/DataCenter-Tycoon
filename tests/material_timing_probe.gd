extends SceneTree
## Misst die einzelnen Textur-Generatoren von MaterialLibrary (Punkt 2.6 im Optimierungsdokument).
## Aufruf: Godot --path <projekt> --script res://tests/material_timing_probe.gd
## Texturen mit Cache (_cached_tex_pair, _gen_block_wall_set) werden aus user://tex_cache geladen,
## gemessen wird also ein normaler Start. Die Farben sind beliebig, sie beeinflussen nur die Pixelwerte.

const RUNS := 3
const MATLIB_PATH := "res://scripts/autoload/material_library.gd"

var _totals: Dictionary = {}
var _order: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var matlib_script: GDScript = load(MATLIB_PATH)
	if matlib_script == null:
		push_error("MATPROBE Skript nicht gefunden")
		quit(1)
		return

	var grey := Color(0.5, 0.5, 0.5)
	var dark := Color(0.2, 0.2, 0.2)
	var light := Color(0.8, 0.8, 0.8)

	for run in range(RUNS):
		var ml: Node = matlib_script.new()
		_time("cache concrete_floor 1024", func() -> void:
			ml.call("_cached_tex_pair", "concrete_floor", 1024, Callable(ml, "_render_concrete")))
		_time("cache raised_floor_b 1024", func() -> void:
			ml.call("_cached_tex_pair", "raised_floor_b", 1024, Callable(ml, "_render_raised_floor").bind(grey, light, dark)))
		_time("cache raised_floor_c 1024", func() -> void:
			ml.call("_cached_tex_pair", "raised_floor_c", 1024, Callable(ml, "_render_raised_floor").bind(grey, light, dark)))
		_time("cache block_wall 1024", func() -> void:
			ml.call("_gen_block_wall_set", 1024, grey, light, dark, grey))
		_time("cache corrugated 512", func() -> void:
			ml.call("_cached_tex_pair", "corrugated", 512, Callable(ml, "_render_corrugated")))
		_time("cache exterior_brick 1024", func() -> void:
			ml.call("_cached_tex_pair", "exterior_brick", 1024, Callable(ml, "_render_brick")))
		_time("gen brushed_metal 128", func() -> void:
			ml.call("_gen_brushed_metal_tex", 128))
		_time("gen perforated_mesh 128", func() -> void:
			ml.call("_gen_perforated_mesh_tex", 128))
		_time("gen hazard_stripes 512", func() -> void:
			ml.call("_gen_hazard_stripes_tex", 512))
		_time("gen pcb 256 (x2)", func() -> void:
			ml.call("_gen_pcb_tex", 256, dark, grey, light)
			ml.call("_gen_pcb_tex", 256, dark, grey, light))
		_time("gen heatsink_fins 128 (x2)", func() -> void:
			ml.call("_gen_heatsink_fins_tex", 128, light)
			ml.call("_gen_heatsink_fins_tex", 128, grey))
		_time("noise tex anlegen 1024 (x2)", func() -> void:
			var n: FastNoiseLite = ml.call("_make_noise", FastNoiseLite.TYPE_SIMPLEX, 0.05, 5, 1)
			ml.call("_make_noise_tex", n, 1024, dark, light)
			ml.call("_make_normal_tex", n, 1024, 3.0))
		_time("gesamt _build_all_materials", func() -> void:
			ml.call("_build_all_materials"))
		ml.free()

	for label in _order:
		print("MATPROBE %-30s %7.1f ms (Mittel aus %d)" % [label, float(_totals[label]) / RUNS / 1000.0, RUNS])
	quit(0)


func _time(label: String, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var dt := Time.get_ticks_usec() - t0
	if not _totals.has(label):
		_totals[label] = 0
		_order.append(label)
	_totals[label] = int(_totals[label]) + dt