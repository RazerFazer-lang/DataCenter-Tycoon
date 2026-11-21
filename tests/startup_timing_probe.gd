extends SceneTree
## Misst die Startkosten von MaterialLibrary und SfxManager (Punkt 2.6 im Optimierungsdokument).
## Aufruf: Godot --path <projekt> --script res://tests/startup_timing_probe.gd
## Die Texturen kommen dabei aus dem vorhandenen Cache in user://tex_cache, gemessen wird also ein normaler Start.

const RUNS := 3
const MATLIB_PATH := "res://scripts/autoload/material_library.gd"
const SFX_PATH := "res://scripts/autoload/sfx_manager.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Ein Bild abwarten, damit alle Autoloads bereit sind.
	await process_frame

	var matlib_script: GDScript = load(MATLIB_PATH)
	var sfx_script: GDScript = load(SFX_PATH)
	if matlib_script == null or sfx_script == null:
		push_error("STARTUP Skripte nicht gefunden")
		quit(1)
		return

	for run in range(RUNS):
		var ml: Node = matlib_script.new()
		var t0 := Time.get_ticks_usec()
		ml.call("_build_all_materials")
		var t1 := Time.get_ticks_usec()
		ml.call("_finalize_textures")
		var t2 := Time.get_ticks_usec()
		ml.call("_build_custom_shaders")
		var t3 := Time.get_ticks_usec()
		ml.free()

		var sfx: Node = sfx_script.new()
		var t4 := Time.get_ticks_usec()
		# add_child löst _ready() aus, dort entstehen alle Klänge.
		root.add_child(sfx)
		var t5 := Time.get_ticks_usec()
		root.remove_child(sfx)
		sfx.free()

		print("STARTUP lauf=%d materialien=%.1f ms mipmaps=%.1f ms shader=%.1f ms sounds=%.1f ms" % [
			run + 1,
			(t1 - t0) / 1000.0,
			(t2 - t1) / 1000.0,
			(t3 - t2) / 1000.0,
			(t5 - t4) / 1000.0,
		])

	quit(0)