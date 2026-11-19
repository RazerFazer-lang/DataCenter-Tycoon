extends Node
## Persists player preferences, audio levels, controls, display mode,
## graphics quality preset, and recently joined Co-op host IPs in user://settings.cfg.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

# 0 = Performance, 1 = Mittel, 2 = Hoch, 3 = Ultra (SDFGI + Vol. Fog + SSR)
var graphics_quality: int = 2

var player_name: String = "Admin"
var master_volume: float = 0.85
var sfx_volume: float = 0.85
var fan_volume: float = 0.70
var mouse_sensitivity: float = 0.0024
var fov: float = 75.0
var fullscreen: bool = false
var autosave_enabled: bool = true
var recent_ips: Array[String] = ["127.0.0.1"]


func _ready() -> void:
	load_settings()
	apply_display_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return

	player_name = str(cfg.get_value("player", "name", "Admin"))
	master_volume = clampf(float(cfg.get_value("audio", "master", 0.85)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", 0.85)), 0.0, 1.0)
	fan_volume = clampf(float(cfg.get_value("audio", "fans", 0.70)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sens", 0.0024)), 0.0008, 0.0065)
	fov = clampf(float(cfg.get_value("video", "fov", 75.0)), 60.0, 105.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	graphics_quality = clampi(int(cfg.get_value("video", "graphics_quality", 2)), 0, 3)
	autosave_enabled = bool(cfg.get_value("gameplay", "autosave", true))

	var saved_ips: Variant = cfg.get_value("network", "recent_ips", ["127.0.0.1"])
	recent_ips.clear()
	if saved_ips is Array:
		for item in saved_ips:
			var ip_str := str(item).strip_edges()
			if not ip_str.is_empty() and not recent_ips.has(ip_str):
				recent_ips.append(ip_str)
	if recent_ips.is_empty():
		recent_ips.append("127.0.0.1")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "fans", fan_volume)
	cfg.set_value("controls", "mouse_sens", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("gameplay", "autosave", autosave_enabled)
	cfg.set_value("network", "recent_ips", recent_ips)
	cfg.save(SETTINGS_PATH)
	apply_display_settings()
	settings_changed.emit()


func apply_display_settings() -> void:
	var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != desired:
		DisplayServer.window_set_mode(desired)


func record_recent_ip(ip: String) -> void:
	var clean := ip.strip_edges()
	if clean.is_empty():
		return
	recent_ips.erase(clean)
	recent_ips.push_front(clean)
	while recent_ips.size() > 6:
		recent_ips.pop_back()
	save_settings()


func get_effective_sfx_gain() -> float:
	return clampf(master_volume * sfx_volume, 0.0, 1.0)


func get_effective_fan_gain() -> float:
	return clampf(master_volume * fan_volume, 0.0, 1.0)
