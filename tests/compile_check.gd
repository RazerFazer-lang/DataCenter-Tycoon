extends SceneTree
## Lädt die geänderten Skripte mit aktiven Autoloads und meldet Kompilierfehler.
## Aufruf: godot --headless --path . --script res://tests/compile_check.gd

const SCRIPTS: Array[String] = [
	"res://scripts/world/player_controller.gd",
	"res://scripts/ui/terminal_ui.gd",
	"res://scripts/main.gd",
	"res://scripts/ui/pc_boot_screen.gd",
	"res://scripts/world/pc_screen_mirror.gd",
	"res://scripts/autoload/game_state.gd",
	"res://scripts/autoload/security_guard.gd",
	"res://scripts/autoload/save_manager.gd",
	"res://scripts/autoload/finance_manager.gd",
	"res://scripts/autoload/pc_screen_state.gd",
	"res://scripts/world/garage_builder.gd",
	"res://scripts/world/exterior_district.gd",
	"res://scripts/autoload/network_manager.gd",
	"res://scripts/autoload/settings_manager.gd",
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/intro_splash.gd",
	"res://scripts/ui/loading_screen.gd",
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/ui_theme.gd",
	"res://scripts/ui/perf_overlay.gd",
	"res://scripts/ui/history_chart.gd",
	"res://scripts/autoload/stats_history.gd",
	"res://scripts/ui/rack_inspector_ui.gd",
	"res://scripts/world/rack_prop.gd",
	"res://scripts/world/storage_shelf_prop.gd",
	"res://scripts/world/workbench_prop.gd",
	"res://scripts/ui/workbench_ui.gd",
	"res://scripts/world/workbench_piece.gd",
	"res://scripts/data/assembly_plan.gd",
	"res://scripts/autoload/technician_manager.gd",
	"res://scripts/world/technician_npc.gd",
	"res://scripts/ui/skin_editor_panel.gd",
	"res://scripts/world/delivery_van.gd",
	"res://scripts/world/delivery_driver.gd",
	"res://scripts/world/humanoid_rig_helper.gd",
	"res://scripts/world/decor_prop.gd",
	"res://scripts/world/building_prop_factory.gd",
	"res://scripts/world/halle_nord_campus.gd",
	"res://scripts/autoload/model_loader.gd",
]


func _initialize() -> void:
	await process_frame
	var failed := 0
	for path in SCRIPTS:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("FEHLER  ", path)
			failed += 1
		else:
			print("OK      ", path)
	print("Ergebnis: %d Fehler" % failed)
	quit(1 if failed > 0 else 0)