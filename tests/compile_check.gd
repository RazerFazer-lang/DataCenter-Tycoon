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
	"res://scripts/autoload/pc_screen_state.gd",
	"res://scripts/world/garage_builder.gd",
	"res://scripts/autoload/network_manager.gd",
	"res://scripts/autoload/settings_manager.gd",
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/ui_theme.gd",
	"res://scripts/ui/perf_overlay.gd",
	"res://scripts/ui/history_chart.gd",
	"res://scripts/autoload/stats_history.gd",
	"res://scripts/ui/rack_inspector_ui.gd",
	"res://scripts/world/rack_prop.gd",
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