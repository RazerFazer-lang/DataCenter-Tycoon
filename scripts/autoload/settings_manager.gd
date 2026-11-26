extends Node
## Persists player preferences, audio levels, controls, display mode,
## graphics quality preset, detailed graphics options (anti-aliasing, render scale,
## upscaler, sharpness, texture filtering, V-Sync, FPS limit),
## and recently joined Co-op host IPs in user://settings.cfg.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

# Kantenglättung
const AA_OFF := 0
const AA_FXAA := 1
const AA_SMAA := 2
const AA_TAA := 3
const AA_MSAA_2X := 4
const AA_MSAA_4X := 5
const AA_COUNT := 6

# Hochskalierung, wenn render_scale < 1.0
const UPSCALER_BILINEAR := 0
const UPSCALER_FSR1 := 1
const UPSCALER_FSR2 := 2
const UPSCALER_COUNT := 3

const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 1.5

## Index 0..4 -> Aus, 2x, 4x, 8x, 16x
const ANISO_LEVELS := [
	Viewport.ANISOTROPY_DISABLED,
	Viewport.ANISOTROPY_2X,
	Viewport.ANISOTROPY_4X,
	Viewport.ANISOTROPY_8X,
	Viewport.ANISOTROPY_16X,
]

## 0 = unbegrenzt
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 240]

## Anzeigetexte für Haupt- und Pausemenü, gleiche Reihenfolge wie die Konstanten oben.
const AA_LABELS: Array[String] = [
	"Aus (am schärfsten)",
	"FXAA (schnell, weich)",
	"SMAA (scharf, empfohlen)",
	"TAA (sehr glatt, weicher)",
	"MSAA 2x (nur Kanten)",
	"MSAA 4x (nur Kanten)",
]
const UPSCALER_LABELS: Array[String] = ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"]
const ANISO_LABELS: Array[String] = ["Aus", "Anisotrop 2x", "Anisotrop 4x", "Anisotrop 8x", "Anisotrop 16x"]

## Fenstermodus
const WINDOW_WINDOWED := 0
const WINDOW_BORDERLESS := 1
const WINDOW_EXCLUSIVE := 2
const WINDOW_MODE_COUNT := 3
const WINDOW_MODE_LABELS: Array[String] = ["Fenster", "Randloses Vollbild", "Exklusives Vollbild"]
## Auflösungen für Fenster und Vollbild. Angeboten werden nur Größen, die auf den Monitor passen.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1024, 576),
	Vector2i(1024, 768),
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1280, 1024),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3200, 1800),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)

## UI-Skalierung: 0.0 = automatisch nach Fensterhöhe.
const UI_SCALE_VALUES: Array[float] = [0.0, 1.0, 1.25, 1.5, 1.75, 2.0]
const UI_SCALE_LABELS: Array[String] = ["Automatisch", "100 %", "125 %", "150 %", "175 %", "200 %"]
## Höhe, für die die Oberfläche gebaut ist (project.godot: viewport_height).
const UI_BASE_HEIGHT := 720.0

## Tastenbelegung: Aktionen, die der Spieler ändern kann (Reihenfolge = Reihenfolge im Menü).
const REBINDABLE_ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "crouch", "interact", "inspect_rack", "drop_item", "rotate_item",
	"tool_hands", "tool_power_cable", "tool_net_cable", "tool_slot_4", "toggle_help", "open_chat", "toggle_perf", "emote_wheel",
]
const ACTION_LABELS := {
	"move_forward": "Vorwärts",
	"move_back": "Rückwärts",
	"move_left": "Links",
	"move_right": "Rechts",
	"jump": "Springen",
	"sprint": "Sprinten",
	"crouch": "Ducken",
	"interact": "Interagieren",
	"inspect_rack": "Rack untersuchen",
	"drop_item": "Gegenstand ablegen",
	"rotate_item": "Gegenstand drehen",
	"tool_hands": "Slot 1 wählen",
	"tool_power_cable": "Slot 2 wählen",
	"tool_net_cable": "Slot 3 wählen",
	"tool_slot_4": "Slot 4 wählen",
	"toggle_help": "Hilfe ein/aus",
	"toggle_perf": "Leistungsanzeige",
	"open_chat": "Chat öffnen",
	"admin_menu": "Admin-Menü",
	"emote_wheel": "Gesten-Rad (halten)",
}
## Tasten, die nicht belegt werden dürfen (Escape öffnet das Pausemenü und bricht die Tastenabfrage ab).
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE]

## Tastenbelegung wurde geändert oder zurückgesetzt.
signal key_bindings_changed

# 0 = Performance, 1 = Mittel, 2 = Hoch, 3 = Ultra (SDFGI + Vol. Fog + SSR)
var graphics_quality: int = 2

var anti_aliasing: int = AA_SMAA
var render_scale: float = 1.0
var upscaler: int = UPSCALER_FSR1
## 0.0 = weich, 1.0 = maximal scharf (nur wirksam mit FSR bei Auflösung unter 100 %)
var sharpness: float = 0.8
var anisotropic: int = 4
var vsync: bool = true
## Eigene Figur wirft auch unter den Hallenlampen Schatten. Kostet Leistung: Jede Bewegung zwingt
## die Lampen, ihre ganzen Schatten neu zu zeichnen. Den Sonnenschatten gibt es immer.
var own_lamp_shadow: bool = false
var max_fps: int = 0

var player_name: String = "Admin"
## Aussehen der eigenen Figur (HumanModel, Format v2) und gespeicherte Outfits.
var skin: Dictionary = {}
var outfits: Array = []
const MAX_OUTFITS := 6
var master_volume: float = 0.85
var sfx_volume: float = 0.85
var fan_volume: float = 0.70
var mouse_sensitivity: float = 0.0024
var fov: float = 75.0
var window_mode: int = WINDOW_WINDOWED
## -1 = Monitor nicht wechseln, sonst Index von DisplayServer.get_screen_count()
var screen_index: int = -1
var window_size: Vector2i = DEFAULT_WINDOW_SIZE
## Render-Auflösung im Vollbild. Vector2i.ZERO = native Monitorauflösung.
var fullscreen_resolution: Vector2i = Vector2i.ZERO
var ui_scale: float = 0.0
## Geänderte Tastenbelegungen: action -> Array physischer Keycodes. Fehlt eine Aktion, gelten die Standardtasten.
var key_bindings: Dictionary = {}
## Standardtasten aus NetworkManager._setup_input_actions(), beim ersten apply_key_bindings() gemerkt.
var _default_keys: Dictionary = {}
## Zwischenspeicher für remap_prompt_keys(): Originaltext -> umgeschriebener Text.
var _prompt_key_cache: Dictionary = {}
var _prompt_regex: RegEx = null
## Zuletzt angewendete Fensterwerte, damit save_settings() das Fenster nicht bei jedem Speichern zurücksetzt.
var _applied_window: Dictionary = {}

## Kompatibilität mit älterem Code: true = irgendein Vollbildmodus.
var fullscreen: bool:
	get:
		return window_mode != WINDOW_WINDOWED
	set(value):
		if value == (window_mode != WINDOW_WINDOWED):
			return
		window_mode = WINDOW_BORDERLESS if value else WINDOW_WINDOWED
var autosave_enabled: bool = true
var recent_ips: Array[String] = ["127.0.0.1"]
## Geheime Kennung dieses Spielers. Geht nie selbst übers Netz, nur ein Schlüssel je Welt daraus (Baurechte, Wiederverbinden).
var client_id: String = ""
## Lobby: gespeicherte Server [{name, ip, port}].
var saved_servers: Array = []
## Version, deren Neuigkeiten der Spieler zuletzt gesehen hat (REL-06). "" = noch nie.
var last_seen_version: String = ""
const SAVED_SERVERS_MAX := 12

## Sprachcodes für TranslationServer. Die Namen bleiben unübersetzt, damit man die eigene Sprache immer findet.
const LANGUAGE_CODES: Array[String] = ["de", "en"]
const LANGUAGE_LABELS: Array[String] = ["Deutsch", "English"]
## Leer bedeutet: noch nicht gespeichert, dann gilt die Systemsprache.
var language: String = ""


func _ready() -> void:
	load_settings()
	apply_language()
	apply_display_settings()


## Deutsch bei deutschem System, sonst Englisch.
func _default_language() -> String:
	return "de" if OS.get_locale_language() == "de" else "en"


## Setzt die Sprache im TranslationServer. Godot übersetzt Label- und Button-Texte danach selbst neu.
func apply_language() -> void:
	if not LANGUAGE_CODES.has(language):
		language = _default_language()
	if TranslationServer.get_locale() != language:
		TranslationServer.set_locale(language)


## Aktuelles Aussehen als Netzwerk-Dictionary (nur Zahlen).
func get_skin() -> Dictionary:
	return sanitize_skin(skin)


## Prüft ein Aussehen aus Datei oder Netzwerk. Ungültige Werte fallen auf den Standard zurück.
func sanitize_skin(raw: Variant) -> Dictionary:
	return HumanModel.sanitize(raw)


func set_skin(look: Dictionary) -> void:
	skin = sanitize_skin(look)
	save_settings()


func save_outfit(slot: int, p_name: String, look: Dictionary) -> void:
	if slot < 0 or slot >= MAX_OUTFITS:
		return
	while outfits.size() <= slot:
		outfits.append({})
	outfits[slot] = {"name": p_name.strip_edges().substr(0, 20), "look": sanitize_skin(look)}
	save_settings()


func delete_outfit(slot: int) -> void:
	if slot >= 0 and slot < outfits.size():
		outfits[slot] = {}
		save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return

	player_name = str(cfg.get_value("player", "name", "Admin"))
	var raw_skin: Variant = cfg.get_value("player", "skin", {})
	if not (raw_skin is Dictionary) or (raw_skin as Dictionary).is_empty():
		# Einstellungen bis v2.9: einzelne Felder.
		raw_skin = {}
		for k in ["jacket", "pants", "tone", "hair", "shoes", "accent", "headwear", "glasses"]:
			if cfg.has_section_key("player", "skin_" + k):
				raw_skin[k] = cfg.get_value("player", "skin_" + k)
	skin = sanitize_skin(raw_skin)
	outfits.clear()
	var raw_outfits: Variant = cfg.get_value("player", "outfits", [])
	if raw_outfits is Array:
		for o in (raw_outfits as Array).slice(0, MAX_OUTFITS):
			if o is Dictionary and (o as Dictionary).has("look"):
				outfits.append({"name": str(o.get("name", "")).substr(0, 20), "look": sanitize_skin(o["look"])})
			else:
				outfits.append({})
	master_volume = clampf(float(cfg.get_value("audio", "master", 0.85)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", 0.85)), 0.0, 1.0)
	fan_volume = clampf(float(cfg.get_value("audio", "fans", 0.70)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sens", 0.0024)), 0.0008, 0.0065)
	fov = clampf(float(cfg.get_value("video", "fov", 75.0)), 60.0, 105.0)
	var legacy_full := bool(cfg.get_value("video", "fullscreen", false))
	var mode_default := WINDOW_BORDERLESS if legacy_full else WINDOW_WINDOWED
	window_mode = clampi(int(cfg.get_value("video", "window_mode", mode_default)), 0, WINDOW_MODE_COUNT - 1)
	screen_index = maxi(int(cfg.get_value("video", "screen", -1)), -1)
	var win_w := clampi(int(cfg.get_value("video", "window_width", DEFAULT_WINDOW_SIZE.x)), 640, 7680)
	var win_h := clampi(int(cfg.get_value("video", "window_height", DEFAULT_WINDOW_SIZE.y)), 360, 4320)
	window_size = Vector2i(win_w, win_h)
	var fs_w := mini(int(cfg.get_value("video", "fullscreen_width", 0)), 7680)
	var fs_h := mini(int(cfg.get_value("video", "fullscreen_height", 0)), 4320)
	fullscreen_resolution = Vector2i(fs_w, fs_h) if fs_w >= 640 and fs_h >= 360 else Vector2i.ZERO
	ui_scale = float(cfg.get_value("video", "ui_scale", 0.0))
	if not UI_SCALE_VALUES.has(ui_scale):
		ui_scale = 0.0
	graphics_quality = clampi(int(cfg.get_value("video", "graphics_quality", 2)), 0, 3)
	anti_aliasing = clampi(int(cfg.get_value("video", "anti_aliasing", AA_SMAA)), 0, AA_COUNT - 1)
	render_scale = clampf(float(cfg.get_value("video", "render_scale", 1.0)), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	upscaler = clampi(int(cfg.get_value("video", "upscaler", UPSCALER_FSR1)), 0, UPSCALER_COUNT - 1)
	sharpness = clampf(float(cfg.get_value("video", "sharpness", 0.8)), 0.0, 1.0)
	anisotropic = clampi(int(cfg.get_value("video", "anisotropic", 4)), 0, ANISO_LEVELS.size() - 1)
	vsync = bool(cfg.get_value("video", "vsync", true))
	own_lamp_shadow = bool(cfg.get_value("video", "own_lamp_shadow", false))
	var saved_fps := int(cfg.get_value("video", "max_fps", 0))
	max_fps = saved_fps if FPS_LIMITS.has(saved_fps) else 0
	autosave_enabled = bool(cfg.get_value("gameplay", "autosave", true))
	var saved_lang := str(cfg.get_value("general", "language", ""))
	language = saved_lang if LANGUAGE_CODES.has(saved_lang) else ""

	key_bindings.clear()
	if cfg.has_section("keybinds"):
		for action in cfg.get_section_keys("keybinds"):
			if not REBINDABLE_ACTIONS.has(action):
				continue
			var raw: Variant = cfg.get_value("keybinds", action, [])
			if not (raw is Array):
				continue
			var codes: Array = []
			for item in raw:
				var code := int(item)
				if code > 0 and not RESERVED_KEYS.has(code) and not codes.has(code):
					codes.append(code)
			if not codes.is_empty():
				key_bindings[action] = codes

	var saved_ips: Variant = cfg.get_value("network", "recent_ips", ["127.0.0.1"])
	recent_ips.clear()
	if saved_ips is Array:
		for item in saved_ips:
			var ip_str := str(item).strip_edges()
			if not ip_str.is_empty() and not recent_ips.has(ip_str):
				recent_ips.append(ip_str)
	if recent_ips.is_empty():
		recent_ips.append("127.0.0.1")
	client_id = str(cfg.get_value("network", "client_id", "")).strip_edges().left(64)
	last_seen_version = str(cfg.get_value("general", "last_seen_version", "")).strip_edges().left(24)
	saved_servers.clear()
	var raw_servers: Variant = cfg.get_value("network", "saved_servers", [])
	if raw_servers is Array:
		for s_v in raw_servers:
			if s_v is Dictionary and saved_servers.size() < SAVED_SERVERS_MAX:
				var sd: Dictionary = s_v
				var sp := int(sd.get("port", 0))
				var sip := str(sd.get("ip", "")).strip_edges().left(64)
				if not sip.is_empty() and sp >= 1024 and sp <= 65533:
					saved_servers.append({"name": str(sd.get("name", sip)).left(28), "ip": sip, "port": sp})


## Legt die Kennung beim ersten Bedarf an und speichert sie.
## Merkt sich die gesehene Version, ohne Fenster, Sprache und Bild neu anzuwenden.
func remember_seen_version(version: String) -> void:
	last_seen_version = version.strip_edges().left(24)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("general", "last_seen_version", last_seen_version)
	cfg.save(SETTINGS_PATH)


func get_client_id() -> String:
	if client_id.length() < 16:
		client_id = Crypto.new().generate_random_bytes(16).hex_encode()
		save_settings()
	return client_id


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "skin", get_skin())
	cfg.set_value("player", "outfits", outfits)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "fans", fan_volume)
	cfg.set_value("controls", "mouse_sens", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "screen", screen_index)
	cfg.set_value("video", "window_width", window_size.x)
	cfg.set_value("video", "window_height", window_size.y)
	cfg.set_value("video", "fullscreen_width", fullscreen_resolution.x)
	cfg.set_value("video", "fullscreen_height", fullscreen_resolution.y)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("video", "anti_aliasing", anti_aliasing)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "upscaler", upscaler)
	cfg.set_value("video", "sharpness", sharpness)
	cfg.set_value("video", "anisotropic", anisotropic)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "own_lamp_shadow", own_lamp_shadow)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("gameplay", "autosave", autosave_enabled)
	if LANGUAGE_CODES.has(language):
		cfg.set_value("general", "language", language)
	cfg.set_value("network", "recent_ips", recent_ips)
	cfg.set_value("network", "client_id", client_id)
	cfg.set_value("network", "saved_servers", saved_servers)
	cfg.set_value("general", "last_seen_version", last_seen_version)
	for action in key_bindings.keys():
		cfg.set_value("keybinds", action, key_bindings[action])
	cfg.save(SETTINGS_PATH)
	apply_language()
	apply_display_settings()
	settings_changed.emit()


func apply_display_settings() -> void:
	_apply_window_settings()
	if is_inside_tree():
		var root := get_tree().root
		if not root.size_changed.is_connected(_apply_ui_scale):
			root.size_changed.connect(_apply_ui_scale)
		# Die Vollbild-Auflösung hängt von der echten Fenstergröße ab, die erst nach dem Moduswechsel feststeht.
		if not root.size_changed.is_connected(apply_graphics_settings):
			root.size_changed.connect(apply_graphics_settings)
	_apply_ui_scale()
	apply_graphics_settings()


## Tatsächlicher Skalierungsfaktor. Er wird so begrenzt, dass mindestens UI_BASE_HEIGHT Pixel Höhe für die Oberfläche bleiben.
func get_effective_ui_scale() -> float:
	var h := float(DisplayServer.window_get_size().y)
	if h <= 0.0:
		return 1.0
	var max_scale := maxf(1.0, h / UI_BASE_HEIGHT)
	var wanted := ui_scale
	if wanted <= 0.0:
		wanted = clampf(snappedf(h / 1080.0, 0.25), 1.0, 2.0)
	return clampf(wanted, 1.0, max_scale)


func _apply_ui_scale() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var root := get_tree().root
	var s := get_effective_ui_scale()
	if not is_equal_approx(root.content_scale_factor, s):
		root.content_scale_factor = s


func _resolve_screen(screen: int) -> int:
	if screen >= 0 and screen < DisplayServer.get_screen_count():
		return screen
	return DisplayServer.window_get_current_screen()


func _apply_window_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := _resolve_screen(screen_index)
	var wanted := {"mode": window_mode, "screen": target, "size": window_size}
	if wanted == _applied_window:
		return
	_applied_window = wanted

	var desired := DisplayServer.WINDOW_MODE_WINDOWED
	match window_mode:
		WINDOW_BORDERLESS:
			desired = DisplayServer.WINDOW_MODE_FULLSCREEN
		WINDOW_EXCLUSIVE:
			desired = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	# Den Monitor zuverlässig im Fenstermodus wechseln, danach auf dem neuen Monitor in den Vollbildmodus gehen.
	if DisplayServer.window_get_current_screen() != target:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(target)

	if desired == DisplayServer.WINDOW_MODE_WINDOWED:
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)
		var usable := DisplayServer.screen_get_usable_rect(target)
		var win_size := window_size
		if usable.size.x > 0 and usable.size.y > 0:
			win_size = Vector2i(mini(window_size.x, usable.size.x), mini(window_size.y, usable.size.y))
		DisplayServer.window_set_size(win_size)
		DisplayServer.window_set_position(usable.position + (usable.size - win_size) / 2)
	elif DisplayServer.window_get_mode() != desired:
		DisplayServer.window_set_mode(desired)


## Index 0 = "Aktueller Monitor" (screen_index -1), Index i + 1 = Monitor i.
func get_screen_labels() -> Array[String]:
	var labels: Array[String] = [tr("Aktueller Monitor")]
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		labels.append(tr("Monitor %d (%d × %d)") % [i + 1, s.x, s.y])
	return labels


func get_screen_size(screen: int = -1) -> Vector2i:
	return DisplayServer.screen_get_size(_resolve_screen(screen))


## Auflösungen, die auf den Monitor passen, aufsteigend sortiert.
## Fenstermodus: die native Größe und die aktuelle Fenstergröße sind immer dabei.
## Vollbild: ohne die native Größe (die bietet das Menü als eigenen Eintrag an), die gewählte Vollbild-Auflösung ist immer dabei.
func get_window_sizes(screen: int = -1, for_fullscreen: bool = false) -> Array[Vector2i]:
	var max_size := get_screen_size(screen)
	var sizes: Array[Vector2i] = []
	for s in WINDOW_SIZES:
		if max_size.x <= 0 or (s.x <= max_size.x and s.y <= max_size.y):
			sizes.append(s)
	if for_fullscreen:
		sizes.erase(max_size)
		if fullscreen_resolution != Vector2i.ZERO and fullscreen_resolution != max_size and not sizes.has(fullscreen_resolution):
			sizes.append(fullscreen_resolution)
	else:
		if max_size.x > 0 and not sizes.has(max_size):
			sizes.append(max_size)
		if not sizes.has(window_size):
			sizes.append(window_size)
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return sizes


## Anteil der gewählten Vollbild-Auflösung an der echten Fensterhöhe.
## 1.0 im Fenstermodus oder bei nativer Auflösung.
func get_fullscreen_resolution_factor() -> float:
	if window_mode == WINDOW_WINDOWED or fullscreen_resolution == Vector2i.ZERO:
		return 1.0
	var h := float(DisplayServer.window_get_size().y)
	if h <= 0.0:
		return 1.0
	return clampf(float(fullscreen_resolution.y) / h, 0.25, 1.0)


## Wendet Kantenglättung, Auflösung, Hochskalierung, Texturfilter, V-Sync und FPS-Limit
## auf den Haupt-Viewport an. Die Umgebungseffekte (SSAO, SSR, SDFGI …) bleiben beim
## Qualitäts-Preset in world_controller.gd.
func apply_graphics_settings() -> void:
	if not is_inside_tree():
		return
	var vp: Viewport = get_tree().root
	if vp == null:
		return

	var eff_scale := maxf(render_scale * get_fullscreen_resolution_factor(), 0.25)
	var supersampling := eff_scale > 1.0
	var use_fsr2 := upscaler == UPSCALER_FSR2 and not supersampling

	# FSR 2.2 glättet Kanten selbst. MSAA wäre dann doppelt und kostet viel VRAM
	# (MSAA 4x bei 2560x1392 gemessen ~484 MB, tests/mem_probe.gd, 21.11.2026).
	# Die gespeicherte Auswahl bleibt erhalten und greift wieder, sobald ein anderer Upscaler aktiv ist.
	if use_fsr2:
		vp.msaa_3d = Viewport.MSAA_DISABLED
	else:
		match anti_aliasing:
			AA_MSAA_2X:
				vp.msaa_3d = Viewport.MSAA_2X
			AA_MSAA_4X:
				vp.msaa_3d = Viewport.MSAA_4X
			_:
				vp.msaa_3d = Viewport.MSAA_DISABLED
	match anti_aliasing:
		AA_FXAA:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AA_SMAA:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		_:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# FSR 2.2 bringt eine eigene zeitliche Glättung mit, TAA wäre dann doppelt.
	vp.use_taa = anti_aliasing == AA_TAA and not use_fsr2

	vp.scaling_3d_scale = eff_scale
	if supersampling:
		# FSR ist nur fürs Hochskalieren gedacht. Über 100 % wird bilinear heruntergerechnet.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif upscaler == UPSCALER_FSR2:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	elif upscaler == UPSCALER_FSR1:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# Godot: 0.0 = schärfste Stufe, 2.0 = weichste.
	vp.fsr_sharpness = (1.0 - sharpness) * 2.0

	vp.anisotropic_filtering_level = ANISO_LEVELS[anisotropic]
	# Automatische Detailstufen der Modelle: Ultra wechselt erst, wenn der Unterschied unter einem Pixel
	# liegt (unsichtbar). Darunter darf er etwas früher wechseln, das entlastet den Hauptdurchgang.
	vp.mesh_lod_threshold = [3.0, 2.0, 1.25, 1.0][clampi(graphics_quality, 0, 3)]

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


## Wendet gespeicherte Tasten auf die InputMap an. Muss nach dem Anlegen der Aktionen laufen.
func apply_key_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if not _default_keys.has(action):
			_default_keys[action] = _get_action_keys(action)
		var keys: Array = _default_keys[action]
		if key_bindings.has(action):
			keys = key_bindings[action]
		_set_action_keys(action, keys)
	_prompt_key_cache.clear()
	key_bindings_changed.emit()


func _get_action_keys(action: String) -> Array:
	var keys: Array = []
	if not InputMap.has_action(action):
		return keys
	for ev in InputMap.action_get_events(action):
		var key_ev := ev as InputEventKey
		if key_ev == null:
			continue
		var code := int(key_ev.physical_keycode)
		if code == 0:
			code = int(key_ev.keycode)
		if code != 0 and not keys.has(code):
			keys.append(code)
	return keys


func _set_action_keys(action: String, keys: Array) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for code in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)


func get_action_label(action: String) -> String:
	return tr(str(ACTION_LABELS.get(action, action)))


## Anzeigename der Tasten einer Aktion im aktuellen Tastaturlayout, z. B. "W / Up".
func get_action_key_label(action: String) -> String:
	var keys := _get_action_keys(action)
	if keys.is_empty():
		return "–"
	var names: Array[String] = []
	for code in keys:
		names.append(_physical_key_name(int(code)))
	return " / ".join(names)


## Tastenname im aktuellen Layout. Ohne Bildschirm (dedizierter Server mit --headless)
## gibt es kein Tastaturlayout, dann gilt der physische Name.
func _physical_key_name(code: int) -> String:
	if DisplayServer.get_name() == "headless":
		return OS.get_keycode_string(code)
	var key_name := OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code))
	if key_name.is_empty():
		key_name = OS.get_keycode_string(code)
	return key_name


## Belegt eine Aktion mit genau einer Taste. Hat eine andere Aktion diese Taste, bekommt sie
## die bisherige Taste dieser Aktion. Rückgabe: Name der getauschten Aktion oder "".
func set_key_binding(action: String, physical_keycode: int) -> String:
	if not REBINDABLE_ACTIONS.has(action) or not InputMap.has_action(action):
		return ""
	if physical_keycode <= 0 or RESERVED_KEYS.has(physical_keycode):
		return ""
	var old_keys := _get_action_keys(action)
	var swapped := ""
	for other in REBINDABLE_ACTIONS:
		if other == action or not InputMap.has_action(other):
			continue
		var other_keys := _get_action_keys(other)
		if not other_keys.has(physical_keycode):
			continue
		other_keys.erase(physical_keycode)
		if other_keys.is_empty():
			for k in old_keys:
				if int(k) != physical_keycode:
					other_keys.append(k)
					break
		key_bindings[other] = other_keys
		_set_action_keys(other, other_keys)
		swapped = get_action_label(other)
	key_bindings[action] = [physical_keycode]
	_set_action_keys(action, [physical_keycode])
	save_settings()
	_prompt_key_cache.clear()
	key_bindings_changed.emit()
	return swapped


## Ersetzt Standardtasten in Hinweisen wie "[E] Aufheben" oder "[Q / Rechtsklick] Abbrechen"
## durch die aktuelle Belegung. Ohne geänderte Tasten bleibt der Text unverändert.
func remap_prompt_keys(text: String) -> String:
	if key_bindings.is_empty() or text.find("[") < 0:
		return text
	if _prompt_key_cache.has(text):
		return str(_prompt_key_cache[text])
	if _prompt_regex == null:
		_prompt_regex = RegEx.new()
		_prompt_regex.compile("\\[([^\\]]{1,32})\\]")
	var defaults := _default_key_names()
	var out := ""
	var pos := 0
	for m: RegExMatch in _prompt_regex.search_all(text):
		out += text.substr(pos, m.get_start() - pos)
		var parts: Array[String] = []
		for part: String in m.get_string(1).split("/"):
			var p: String = part.strip_edges()
			var space: int = p.find(" ")
			var word: String = p if space < 0 else p.left(space)
			if defaults.has(word):
				var rest: String = "" if space < 0 else p.substr(space)
				p = _primary_key_name(str(defaults[word])) + rest
			parts.append(p)
		out += "[" + " / ".join(parts) + "]"
		pos = m.get_end()
	out += text.substr(pos)
	# Hinweise mit Prozentwerten ändern sich laufend; Cache begrenzen.
	if _prompt_key_cache.size() > 256:
		_prompt_key_cache.clear()
	_prompt_key_cache[text] = out
	return out


## Name der ersten Standardtaste -> Aktion, z. B. "E" -> "interact".
func _default_key_names() -> Dictionary:
	var names := {}
	for action in REBINDABLE_ACTIONS:
		var keys: Array = _default_keys.get(action, [])
		if keys.is_empty():
			continue
		var key_name := OS.get_keycode_string(int(keys[0]))
		if not key_name.is_empty() and not names.has(key_name):
			names[key_name] = action
	return names


## Anzeigename der ersten aktuellen Taste einer Aktion im aktuellen Tastaturlayout.
func _primary_key_name(action: String) -> String:
	var keys := _get_action_keys(action)
	if keys.is_empty():
		return "–"
	return _physical_key_name(int(keys[0]))


func reset_key_bindings() -> void:
	key_bindings.clear()
	apply_key_bindings()
	save_settings()


func get_fps_labels() -> Array[String]:
	var labels: Array[String] = []
	for fps in FPS_LIMITS:
		labels.append(tr("Unbegrenzt") if fps == 0 else "%d FPS" % fps)
	return labels


## Der Schärfe-Regler wirkt nur mit FSR: FSR 1.0 unter 100 %, FSR 2.2 bis einschließlich 100 %.
func is_sharpness_active(scale_factor: float, upscaler_mode: int) -> bool:
	if upscaler_mode == UPSCALER_FSR2:
		return scale_factor <= 1.0
	if upscaler_mode == UPSCALER_FSR1:
		return scale_factor < 1.0
	return false


## Lobby: gespeicherte Server [{name, ip, port}], höchstens SAVED_SERVERS_MAX.
func add_saved_server(server_name: String, ip: String, port: int) -> bool:
	var clean_ip := ip.strip_edges().left(64)
	if clean_ip.is_empty() or port < 1024 or port > 65533:
		return false
	remove_saved_server(clean_ip, port)
	var nm := SecurityGuard.sanitize_label(server_name, 28, clean_ip)
	saved_servers.push_front({"name": nm, "ip": clean_ip, "port": port})
	while saved_servers.size() > SAVED_SERVERS_MAX:
		saved_servers.pop_back()
	save_settings()
	return true


func remove_saved_server(ip: String, port: int) -> void:
	for i in range(saved_servers.size() - 1, -1, -1):
		var s: Dictionary = saved_servers[i]
		if str(s.get("ip", "")) == ip.strip_edges() and int(s.get("port", 0)) == port:
			saved_servers.remove_at(i)
	save_settings()


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