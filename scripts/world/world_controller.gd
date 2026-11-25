class_name WorldController
extends Node3D
## Synchronizes all 3D visual entities (Garage, Racks, Coolers, UPS units, Crates, Cables, Players),
## drives the Dynamic Day/Night Sky & Lighting cycle, applies Graphics Quality presets (SSAO/SSIL/Shadows),
## renders the live Main Menu 3D showcase, and relays player poses across ENet peers.

signal terminal_open_requested
signal rack_inspect_requested(rack_id: String, slot_index: int)
signal device_inspect_requested(kind: String, entity_id: String)
signal workbench_open_requested
signal locker_open_requested

var local_player: PlayerController = null

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun_light: DirectionalLight3D = $SunLight

var _garage: GarageBuilder
var _delivery_van: DeliveryVan
var _cable_renderer: CableRenderer
var _racks_container: Node3D
var _coolers_container: Node3D
var _ups_container: Node3D
var _carts_container: Node3D
var _crates_container: Node3D
var _players_container: Node3D
var _showcase_container: Node3D

var _rack_nodes: Dictionary = {}   # rack_id -> RackProp
var _outdoor_amb := 0.0
var _cooler_nodes: Dictionary = {} # cooler_id -> CoolerProp
var _ups_nodes: Dictionary = {}    # ups_id -> UpsProp
var _extinguisher_nodes: Dictionary = {}
var _decor_nodes: Dictionary = {}  # decor_id -> DecorProp
var _cart_nodes: Dictionary = {}   # cart_id -> CartProp
var _crate_nodes: Dictionary = {}  # crate_id -> CrateProp
var _player_nodes: Dictionary = {} # peer_id -> PlayerController


func _ready() -> void:
	_garage = GarageBuilder.new()
	_garage.name = "Garage"
	add_child(_garage)

	_delivery_van = DeliveryVan.new()
	_delivery_van.name = "DeliveryVan"
	add_child(_delivery_van)

	_racks_container = Node3D.new()
	_racks_container.name = "Racks"
	add_child(_racks_container)

	_coolers_container = Node3D.new()
	_coolers_container.name = "Coolers"
	add_child(_coolers_container)

	_ups_container = Node3D.new()
	_ups_container.name = "UpsUnits"
	add_child(_ups_container)

	_carts_container = Node3D.new()
	_carts_container.name = "Carts"
	add_child(_carts_container)

	_crates_container = Node3D.new()
	_crates_container.name = "Crates"
	add_child(_crates_container)

	_players_container = Node3D.new()
	_players_container.name = "Players"
	add_child(_players_container)

	_showcase_container = Node3D.new()
	_showcase_container.name = "MenuShowcase"
	add_child(_showcase_container)

	_cable_renderer = CableRenderer.new()
	_cable_renderer.name = "Cables"
	add_child(_cable_renderer)

	GameState.world_snapshot_loaded.connect(_on_full_rebuild)
	GameState.racks_changed.connect(_sync_racks)
	GameState.coolers_changed.connect(_sync_coolers)
	GameState.ups_changed.connect(_sync_ups)
	GameState.decor_items_changed.connect(_sync_decor_items)
	GameState.carts_changed.connect(_sync_carts)
	GameState.crates_changed.connect(_sync_crates)
	GameState.cables_changed.connect(_sync_cables)
	# Router-Upgrade verschiebt die LAN-Buchse: Kabel nach dem Neubau des Modells neu zeichnen.
	_garage.router_visuals_rebuilt.connect(_on_router_visuals_rebuilt, CONNECT_DEFERRED)
	GameState.extinguisher_changed.connect(_sync_extinguisher)
	GameState.unpack_started.connect(_on_unpack_started)
	DecorManager.world = self
	var thief_npc := ThiefNpc.new()
	thief_npc.name = "ThiefNpc"
	add_child(thief_npc)
	GameState.room_level_changed.connect(_sync_room_level)
	GameState.state_updated.connect(_on_state_updated)
	GameState.world_ping_received.connect(_on_world_ping_received)

	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_skin_changed.connect(_on_player_skin)
	NetworkManager.player_left.connect(_on_player_left)
	SettingsManager.settings_changed.connect(_apply_graphics_quality)

	# Upgrade Sky to Custom Cloud + Twinkling Starfield ShaderMaterial!
	if _world_env != null and _world_env.environment != null:
		var sky_mat := MatLib.get_sky_shader_material()
		if sky_mat != null:
			if _world_env.environment.sky == null:
				_world_env.environment.sky = Sky.new()
			_world_env.environment.sky.sky_material = sky_mat

	_apply_graphics_quality()
	_prewarm_shaders()


## Anzahl Bilder, in denen alle Hallen und Lampenschatten hinter dem Ladebildschirm gerendert werden.
const SHADER_PREWARM_FRAMES := 4


func _prewarm_shaders() -> void:
	if _garage == null or not _garage.has_method("begin_shader_prewarm"):
		return
	_garage.begin_shader_prewarm()
	for i in range(SHADER_PREWARM_FRAMES):
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if not is_inside_tree():
		return
	# Echten Zustand wiederherstellen: Lampenschatten nach Qualitätsstufe, Wände nach room_level.
	if _garage != null and _garage.has_method("end_shader_prewarm"):
		_garage.end_shader_prewarm()
	_apply_graphics_quality()
	_sync_room_level()


# Lampen mit Helligkeit 0 kosten auf der Grafikkarte genauso viel wie helle: solange sie aus sind, ausblenden.
var _gate_lights: Array = []
var _gate_scan: float = 0.0
var _gate_tick: float = 0.0


func _update_light_gate(delta: float) -> void:
	_gate_scan -= delta
	if _gate_scan <= 0.0:
		_gate_scan = 4.0
		_gate_lights = find_children("*", "OmniLight3D", true, false)
		_gate_lights.append_array(find_children("*", "SpotLight3D", true, false))
	_gate_tick -= delta
	if _gate_tick > 0.0:
		return
	_gate_tick = 0.06
	for n in _gate_lights:
		if not is_instance_valid(n):
			continue
		var l := n as Light3D
		if l.light_energy <= 0.0005:
			if l.visible:
				l.visible = false
				l.set_meta("gated", true)
		elif l.has_meta("gated"):
			l.remove_meta("gated")
			l.visible = true


func _process(delta: float) -> void:
	_update_day_night_atmosphere()
	_update_light_gate(delta)
	_update_world_pings(delta)


var _active_pings: Array[Dictionary] = []


func _on_world_ping_received(sender_peer: int, world_pos: Vector3, kind: String, label: String) -> void:
	var col := NetworkManager.get_player_color(sender_peer)
	if kind == "alert":
		col = Color(1.0, 0.28, 0.18)
	elif kind == "cable":
		col = Color(0.28, 0.72, 1.0)
	var marker := Node3D.new()
	marker.position = world_pos + Vector3(0.0, 0.25, 0.0)
	add_child(marker)

	var ring_m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.21
	ring_m.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = col
	rmat.emission_enabled = true
	rmat.emission = col
	rmat.emission_energy_multiplier = 3.2
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_m.material_override = rmat
	ring_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring_m)

	var beam_m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.025
	cm.height = 1.6
	beam_m.mesh = cm
	var bmat := rmat.duplicate() as StandardMaterial3D
	bmat.albedo_color = Color(col.r, col.g, col.b, 0.45)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.material_override = bmat
	beam_m.position = Vector3(0.0, 0.85, 0.0)
	beam_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam_m)

	var lbl := Label3D.new()
	lbl.text = "%s: %s" % [NetworkManager.get_player_name(sender_peer), label]
	lbl.font_size = 34
	lbl.pixel_size = 0.0052
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, 1.75, 0.0)
	lbl.modulate = col.lerp(Color.WHITE, 0.35)
	marker.add_child(lbl)

	_active_pings.append({"node": marker, "ring": ring_m, "time": 0.0, "ttl": 6.5})


func _update_world_pings(delta: float) -> void:
	for i in range(_active_pings.size() - 1, -1, -1):
		var p: Dictionary = _active_pings[i]
		p["time"] = float(p["time"]) + delta
		var t: float = float(p["time"])
		var ttl: float = float(p["ttl"])
		var nd: Node3D = p["node"]
		if not is_instance_valid(nd) or t >= ttl:
			if is_instance_valid(nd):
				nd.queue_free()
			_active_pings.remove_at(i)
			continue
		var ring: Node3D = p["ring"]
		var s := 0.85 + 0.35 * absf(sin(t * 4.5))
		ring.scale = Vector3(s, 1.0, s)
		nd.position.y += sin(t * 3.0) * 0.0008


func _apply_graphics_quality() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	var q := SettingsManager.graphics_quality
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	# Dezentes Bloom: nur echte Lichtquellen (Lampenleisten, LEDs, Bildschirme) strahlen über.
	env.glow_enabled = (q >= 1)
	env.glow_intensity = 0.32 if q >= 2 else 0.22
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Mehr Kontrast und Farbe gegen das flache, graue Bild. Kostet praktisch nichts, daher auf allen Stufen.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.12
	env.adjustment_brightness = 1.00

	# Umgebungsverdeckung: kräftiger und mit Kontaktschatten in Ecken, an Rack-Füßen und Kabeln.
	env.ssao_enabled = (q >= 1)
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15
	env.ssil_enabled = (q >= 2)
	env.ssil_intensity = 0.8
	env.ssil_radius = 4.0
	# Spiegelungen auf den glänzenden Böden schon ab Mittel.
	env.ssr_enabled = (q >= 1)
	# Ultra wie Hoch: 64 statt 48 Schritte kosteten ~0,5 ms, sichtbar nur an sehr flachen Blickwinkeln.
	env.ssr_max_steps = 48 if q >= 2 else 32
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.sdfgi_enabled = (q >= 3)
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 0.78
	env.sdfgi_cascades = 3
	# Realistische Luftperspektive & Tiefennebel: entfernte Hügel, Windräder & Gebäude verschmelzen weich mit dem Horizont!
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0024
	env.fog_aerial_perspective = 0.78
	env.fog_sky_affect = 0.32
	env.fog_light_color = Color(0.68, 0.76, 0.86)
	env.volumetric_fog_enabled = (q >= 3)
	env.volumetric_fog_density = 0.0022
	env.volumetric_fog_albedo = Color(0.88, 0.89, 0.90)
	env.volumetric_fog_emission_energy = 0.0

	# Kosten begrenzen. Gemessen auf Ultra in 2560x1440 (21.11.2026): SSIL MEDIUM ~1,2 ms, SDFGI ~1,1 ms,
	# SSR 48 Schritte ~0,7 ms, Nebel 32x48 ~0,3 ms pro Bild. MSAA ist bei FSR 2.2 aus (settings_manager.gd).
	RenderingServer.gi_set_use_half_resolution(true)
	# Nebel-Volumen 32 x 32 x 48 statt 48 x 48 x 48: ~55 % weniger Zellen. Der Nebel ist sehr dünn (0.0022)
	# und wird gefiltert, die geringere Breiten-Auflösung fällt kaum auf.
	RenderingServer.environment_set_volumetric_fog_volume_size(32, 48)
	var ao_q := RenderingServer.ENV_SSAO_QUALITY_HIGH if q >= 3 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM
	# SSIL auf allen Stufen MEDIUM: HIGH war auf Ultra mit ~2,8 ms der teuerste Effekt.
	var il_q := RenderingServer.ENV_SSIL_QUALITY_MEDIUM
	RenderingServer.environment_set_ssao_quality(ao_q, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(il_q, true, 0.5, 2, 50.0, 300.0)
	# Die Halle ist weitgehend statisch: Lichtänderungen auf 8 statt 4 Bilder verteilen.
	# Folge: Indirektes Licht reagiert bei Flackern oder USV-Wechsel ~0,1 s träger.
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES)

	# Schatten: höher aufgelöste Shadow-Maps und weichere Kanten je nach Stufe.
	var shadow_q := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	if q >= 3:
		shadow_q = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	elif q >= 2:
		shadow_q = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_q)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_q)
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)
	var vp := get_viewport()
	if vp != null:
		vp.positional_shadow_atlas_size = 4096 if q >= 2 else 2048
	if env.sky != null:
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		env.sky.radiance_size = Sky.RADIANCE_SIZE_128 if q >= 3 else Sky.RADIANCE_SIZE_64

	# Kantenglättung, Auflösung und Texturfilter setzt jetzt SettingsManager.apply_graphics_settings()
	# (eigene Optionen im Menü). Früher erzwangen FXAA und TAA hier ein weiches Bild.

	if _sun_light != null:
		_sun_light.shadow_enabled = (q >= 1)
		_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun_light.directional_shadow_max_distance = 60.0
		_sun_light.shadow_blur = 1.2
	if _garage != null and _garage.has_method("apply_graphics_quality"):
		_garage.apply_graphics_quality(q)


# Zuletzt an den Himmels-Shader gesendete Werte. Neue Werte nur bei echter Änderung senden,
# damit der Himmel nicht in jedem Frame neu berechnet wird.
var _sky_sun_dir_sent: Vector3 = Vector3.ZERO
var _sky_day_sent: float = -1.0
var _sky_sunset_sent: float = -1.0
var _sky_cov_sent: float = -1.0
var _sky_dark_sent: float = -1.0
var _sky_half_sent: bool = true
var _sky_half_set: bool = false
# Startwerte wie im Sky-Shader: get_shader_parameter() liefert null, solange nie ein Wert gesetzt wurde.
var _cloud_coverage: float = 0.48
var _cloud_darkness: float = 0.0


func _update_day_night_atmosphere() -> void:
	if _world_env == null or _world_env.environment == null or _sun_light == null:
		return
	var tod := GameState.time_of_day if GameState.is_active else 0.38
	var env := _world_env.environment

	var sun_phase := (tod - 0.25) * TAU
	var elev := sin(sun_phase)
	var day_factor := clampf(elev * 2.4 + 0.15, 0.0, 1.0)
	var sunset_factor := clampf(1.0 - absf(elev) * 4.5, 0.0, 1.0)

	var pitch_deg := lerpf(-16.0, -68.0, clampf(absf(elev), 0.0, 1.0))
	var yaw_deg := lerpf(-75.0, 75.0, clampf((tod - 0.20) / 0.60, 0.0, 1.0))
	_sun_light.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)

	if elev >= -0.05:
		var noon_col := Color(1.0, 0.97, 0.92)
		var sunset_col := Color(1.0, 0.54, 0.24)
		var w: String = GameState.weather_state if GameState.is_active else "clear"
		var w_sun_mult := 1.0
		if w == "cloudy":
			w_sun_mult = 0.62
		elif w == "rain":
			w_sun_mult = 0.42
			noon_col = Color(0.76, 0.82, 0.90)
		elif w == "storm":
			w_sun_mult = 0.24
			noon_col = Color(0.58, 0.66, 0.78)
		elif w == "heatwave":
			w_sun_mult = 1.22
			noon_col = Color(1.0, 0.92, 0.78)
		_sun_light.light_color = noon_col.lerp(sunset_col, sunset_factor * 0.88)
		_sun_light.light_energy = lerpf(0.24, 1.6, day_factor) * w_sun_mult
	else:
		_sun_light.light_color = Color(0.42, 0.62, 0.98)
		_sun_light.light_energy = 0.28

	# Dynamische Innen-/Außen-Raumakustik & Hallen-Reverb (Garage: Tor bei Z = 4.65; Halle Nord: 20 x 12 m)
	if local_player != null and is_instance_valid(local_player):
		var lp: Vector3 = local_player.position
		if lp.z < -80.0:
			var lz := lp.z - GameState.HALLE_NORD_ORIGIN.z
			var in_hn := (absf(lp.x) < 10.1 and absf(lz) < 6.1)
			SfxManager.set_listener_outdoor(not in_hn, in_hn)
		else:
			SfxManager.set_listener_outdoor(OutdoorWorld.is_outside(lp), false)

	var sky_sh := MatLib.get_sky_shader_material()
	if sky_sh != null:
		var sun_dir := (_sun_light.global_transform.basis.z).normalized()
		if sun_dir.distance_squared_to(_sky_sun_dir_sent) > 0.00001 \
				or absf(day_factor - _sky_day_sent) > 0.003 \
				or absf(sunset_factor - _sky_sunset_sent) > 0.003:
			_sky_sun_dir_sent = sun_dir
			_sky_day_sent = day_factor
			_sky_sunset_sent = sunset_factor
			sky_sh.set_shader_parameter("sun_dir", sun_dir)
			sky_sh.set_shader_parameter("day_factor", day_factor)
			sky_sh.set_shader_parameter("sunset_factor", sunset_factor)

	env.ambient_light_color = Color(0.08, 0.13, 0.24).lerp(Color(0.28, 0.33, 0.40), day_factor)
	# Etwas weniger Grundhelligkeit, damit Lampen und Schatten das Bild formen statt flachem Einheitslicht.
	env.ambient_light_energy = lerpf(0.20, 0.45, day_factor)
	# Draußen füllt der Himmel die Schatten auf (drinnen formen die Lampen das Bild).
	var out_cam := get_viewport().get_camera_3d()
	var out_on := out_cam != null and OutdoorWorld.is_outside(out_cam.global_position)
	_outdoor_amb = lerpf(_outdoor_amb, 1.0 if out_on else 0.0, 0.05)
	env.ambient_light_energy *= 1.0 + _outdoor_amb * lerpf(0.6, 1.5, day_factor)

	# Dynamische Nebel-Atmosphäre, volumetrische Wolken-Dichte & nasser spiegelnder Asphalt bei Regen/Gewitter!
	var w_now: String = GameState.weather_state if GameState.is_active else "clear"
	if sky_sh != null:
		var target_cov := 0.46
		var target_dark := 0.0
		match w_now:
			"heatwave":
				target_cov = 0.24
				target_dark = 0.0
			"cloudy":
				target_cov = 0.68
				target_dark = 0.28
			"rain":
				target_cov = 0.82
				target_dark = 0.62
			"storm":
				target_cov = 0.92
				target_dark = 0.85
		_cloud_coverage = lerpf(_cloud_coverage, target_cov, 0.03)
		_cloud_darkness = lerpf(_cloud_darkness, target_dark, 0.03)
		if absf(_cloud_coverage - _sky_cov_sent) > 0.0015 or absf(_cloud_darkness - _sky_dark_sent) > 0.0015:
			_sky_cov_sent = _cloud_coverage
			_sky_dark_sent = _cloud_darkness
			sky_sh.set_shader_parameter("cloud_coverage", _cloud_coverage)
			sky_sh.set_shader_parameter("cloud_darkness", _cloud_darkness)
		# Drinnen sieht man nur wenig Himmel: dort ist volle Auflösung billiger als der Zwischendurchgang.
		var half := out_on
		if out_cam != null and out_cam.global_position.z < -100.0:
			var hp := out_cam.global_position - GameState.HALLE_NORD_ORIGIN
			half = absf(hp.x) > 10.1 or absf(hp.z) > 6.1
		elif out_cam != null and GameState.garage_door_open and out_cam.global_position.z > 3.0:
			half = true
		if half != _sky_half_sent or not _sky_half_set:
			_sky_half_sent = half
			_sky_half_set = true
			sky_sh.set_shader_parameter("half_clouds", half)
	var snowing: bool = OutdoorManager.is_snowing()
	var is_wet: bool = (w_now == "rain" or w_now == "storm") and not snowing
	env.fog_density = 0.0062 if w_now == "storm" else (0.0044 if w_now == "rain" else 0.0022)
	var day_fog := Color(0.58, 0.64, 0.72) if is_wet else Color(0.70, 0.78, 0.88)
	var night_fog := Color(0.06, 0.09, 0.16)
	env.fog_light_color = night_fog.lerp(day_fog, day_factor)
	var asp := MatLib.get_mat("asphalt")
	if asp != null:
		asp.roughness = lerpf(asp.roughness, 0.18 if is_wet else 0.86, 0.06)
		asp.clearcoat_enabled = is_wet or asp.clearcoat > 0.02
		asp.clearcoat = lerpf(asp.clearcoat, 0.82 if is_wet else 0.0, 0.06)
		var asp_col := (Color(0.56, 0.58, 0.62) if is_wet else Color(1.0, 1.0, 1.0)).lerp(Color(2.1, 2.2, 2.35), OutdoorManager.snow_shown * 0.55)
		asp.albedo_color = asp.albedo_color.lerp(asp_col, 0.06)


func show_menu_showcase() -> void:
	clear_menu_showcase()

	var rack_a := RackProp.new()
	_showcase_container.add_child(rack_a)
	rack_a.setup("rack_1", "rack_pro", true)
	rack_a.apply_data({
		"id": "rack_1",
		"rack_type": "rack_pro",
		"pos": Vector3(-2.4, 0.0, -2.4),
		"rot_y": 0.0,
		"powered": true,
		"networked": true,
		"temp": 44.0,
		"rental_type": "ai",
		"rental_customer": "VektorLabs AI",
		"active_users": 148,
		"metrics": {"bottleneck": "ok"},
		"slots": [
			{"item_type": "web_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_epyc_64c", "gpu": "gpu_rtx4070ti", "ram": "ram_ddr5_256gb", "storage": "sto_nvme4_8tb", "cooling": "cool_fanwall", "psu": "psu_1000w_plat"}},
			{"item_type": "storage_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_xeon_14c", "gpu": "gpu_onboard", "ram": "ram_ddr4_128gb", "storage": "sto_allflash_128tb", "cooling": "cool_noctua", "psu": "psu_850w_gold"}},
			{"item_type": "gpu_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_epyc_128c", "gpu": "gpu_h200_dual", "ram": "ram_ddr5_512gb", "storage": "sto_nvme5_64tb", "cooling": "cool_direct_liquid", "psu": "psu_2400w_dual"}},
			{"item_type": "net_switch", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {}},
			{"item_type": "gpu_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_epyc_64c", "gpu": "gpu_h100", "ram": "ram_ddr5_256gb", "storage": "sto_nvme4_24tb", "cooling": "cool_aio_liquid", "psu": "psu_1600w_tit"}},
			{"item_type": "", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {}},
		],
	})

	var rack_b := RackProp.new()
	_showcase_container.add_child(rack_b)
	rack_b.setup("rack_2", "rack", true)
	rack_b.apply_data({
		"id": "rack_2",
		"rack_type": "rack",
		"pos": Vector3(-1.1, 0.0, -2.4),
		"rot_y": 0.0,
		"powered": true,
		"networked": true,
		"temp": 38.0,
		"rental_type": "game",
		"rental_customer": "NordicFrag Clan",
		"active_users": 215,
		"metrics": {"bottleneck": "ok"},
		"slots": [
			{"item_type": "web_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_ryzen9_16c", "gpu": "gpu_gtx1660ti", "ram": "ram_ddr4_128gb", "storage": "sto_nvme4_8tb", "cooling": "cool_noctua", "psu": "psu_750w_gold"}},
			{"item_type": "storage_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_xeon_14c", "gpu": "gpu_onboard", "ram": "ram_ddr4_64gb", "storage": "sto_nvme4_24tb", "cooling": "cool_copper_hp", "psu": "psu_650w_silver"}},
			{"item_type": "gpu_server", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {"cpu": "cpu_epyc_24c", "gpu": "gpu_rtx4090", "ram": "ram_ddr5_128gb", "storage": "sto_nvme3_2tb", "cooling": "cool_vapor", "psu": "psu_1200w_red"}},
			{"item_type": "", "state": "ok", "repair_progress": 0.0, "fire_level": 0.0, "components": {}},
		],
	})

	var cooler_a := CoolerProp.new()
	_showcase_container.add_child(cooler_a)
	cooler_a.setup("chiller_1", "chiller", true)
	cooler_a.apply_data({
		"id": "chiller_1",
		"cooler_type": "chiller",
		"pos": Vector3(-3.8, 0.0, -1.0),
		"rot_y": PI * 0.45,
		"powered": true,
	})

	var showcase_cables := {
		"sc_1": {"cable_type": "power", "from_id": GameState.WALL_BREAKER_ID, "to_id": "sc_rack_1"},
		"sc_2": {"cable_type": "power", "from_id": "sc_rack_1", "to_id": "sc_rack_2"},
		"sc_3": {"cable_type": "power", "from_id": GameState.WALL_BREAKER_ID, "to_id": "sc_cooler_1"},
		"sc_4": {"cable_type": "network", "from_id": GameState.WALL_ROUTER_ID, "to_id": "sc_rack_1"},
		"sc_5": {"cable_type": "network", "from_id": "sc_rack_1", "to_id": "sc_rack_2"},
	}
	var resolver := func(ctype: String, eid: String) -> Variant:
		if eid == GameState.WALL_BREAKER_ID:
			return _garage.breaker_port_pos
		if eid == GameState.WALL_ROUTER_ID:
			return _garage.router_port_pos
		if eid == "sc_rack_1":
			return rack_a.get_power_port_global_pos() if ctype == "power" else rack_a.get_net_port_global_pos()
		if eid == "sc_rack_2":
			return rack_b.get_power_port_global_pos() if ctype == "power" else rack_b.get_net_port_global_pos()
		if eid == "sc_cooler_1":
			return cooler_a.get_power_port_global_pos()
		return null
	_cable_renderer.rebuild_cables(showcase_cables, resolver, get_port_world_dir)


func clear_menu_showcase() -> void:
	for child in _showcase_container.get_children():
		child.queue_free()


func activate_session() -> void:
	clear_menu_showcase()
	_sync_cables()
	_sync_all_players()
	_on_full_rebuild()


func reset_world() -> void:
	for container_dict in [_rack_nodes, _cooler_nodes, _ups_nodes, _decor_nodes, _cart_nodes, _crate_nodes, _player_nodes]:
		var d: Dictionary = container_dict
		for node in d.values():
			if is_instance_valid(node):
				(node as Node).queue_free()
		d.clear()
	local_player = null
	_cable_renderer.rebuild_cables({}, get_port_world_pos)
	_cable_renderer.update_preview_cable(false, "power", Vector3.ZERO, Vector3.ZERO)
	_garage.set_room_level(0)
	for st in GameState.EXT_STATIONS:
		_garage.set_extinguisher_mounted(st, true)
	_sync_extinguisher()


func open_terminal() -> void:
	terminal_open_requested.emit()


func open_locker() -> void:
	locker_open_requested.emit()


func open_workbench() -> void:
	workbench_open_requested.emit()


func open_rack_inspector(rack_id: String, slot_index: int = 0) -> void:
	rack_inspect_requested.emit(rack_id, slot_index)


func open_device_inspector(kind: String, entity_id: String) -> void:
	device_inspect_requested.emit(kind, entity_id)


func start_relocate_rack(rack_id: String) -> void:
	if local_player != null:
		local_player.start_relocate_rack(rack_id)


func update_cable_preview(active: bool, cable_type: String, start_pos: Vector3, end_pos: Vector3, target_state: int = CableRenderer.TARGET_NONE, snap_pos: Variant = null) -> void:
	if _cable_renderer != null:
		_cable_renderer.update_preview_cable(active, cable_type, start_pos, end_pos, target_state, snap_pos)


func get_port_world_pos(cable_type: String, endpoint_id: String) -> Variant:
	if endpoint_id == GameState.WALL_BREAKER_ID:
		return _garage.breaker_port_pos
	if endpoint_id == GameState.WALL_ROUTER_ID:
		return _garage.router_port_pos
	if endpoint_id == GameState.HALL_C_BREAKER_ID:
		return _garage.hall_c_breaker_port_pos
	if endpoint_id == GameState.HALL_C_ROUTER_ID:
		return _garage.hall_c_router_port_pos
	if endpoint_id == GameState.HALL_NORD_BREAKER_ID:
		return _garage.hall_nord_breaker_port_pos
	if endpoint_id == GameState.HALL_NORD_ROUTER_ID:
		return _garage.hall_nord_router_port_pos
	if _rack_nodes.has(endpoint_id):
		var rp: RackProp = _rack_nodes[endpoint_id]
		if cable_type == "cluster":
			return rp.get_cluster_port_global_pos()
		return rp.get_power_port_global_pos() if cable_type == "power" else rp.get_net_port_global_pos()
	if _cooler_nodes.has(endpoint_id):
		var cp: CoolerProp = _cooler_nodes[endpoint_id]
		return cp.get_power_port_global_pos()
	if _ups_nodes.has(endpoint_id):
		var up: UpsProp = _ups_nodes[endpoint_id]
		return up.get_power_port_global_pos()
	if _decor_nodes.has(endpoint_id):
		var dp: DecorProp = _decor_nodes[endpoint_id]
		return dp.get_port_world_pos()
	return null


func _on_full_rebuild() -> void:
	_sync_room_level()
	_sync_extinguisher()
	_sync_racks()
	_sync_coolers()
	_sync_ups()
	_sync_decor_items()
	_sync_carts()
	_sync_crates()
	_sync_cables()


func _on_state_updated() -> void:
	for rid in GameState.racks.keys():
		if _rack_nodes.has(rid):
			(_rack_nodes[rid] as RackProp).apply_data(GameState.racks[rid])
	for cid in GameState.coolers.keys():
		if _cooler_nodes.has(cid):
			(_cooler_nodes[cid] as CoolerProp).apply_data(GameState.coolers[cid])
	for uid in GameState.ups_units.keys():
		if _ups_nodes.has(uid):
			(_ups_nodes[uid] as UpsProp).apply_data(GameState.ups_units[uid])


func _sync_room_level() -> void:
	_garage.set_room_level(GameState.room_level)


## Auspacken: Klebeband ab, Klappen auf, das Gerät kommt heraus, der leere Karton rutscht zur Seite.
func _on_unpack_started(entity_id: String, item_type: String, carton_pos: Vector3) -> void:
	# Das Gerät selbst wird erst mit dem nächsten Abgleich gebaut.
	await get_tree().process_frame
	await get_tree().process_frame
	var node: Node3D = null
	for group in [_rack_nodes, _cooler_nodes, _ups_nodes, _decor_nodes]:
		if (group as Dictionary).has(entity_id):
			node = (group as Dictionary)[entity_id]
	if node == null or not is_instance_valid(node):
		return
	var fx := UnpackFx.new()
	add_child(fx)
	fx.start(node, CartonFactory.kind_for(item_type), carton_pos)


func _sync_extinguisher() -> void:
	for st in GameState.EXT_STATIONS:
		_garage.set_extinguisher_mounted(st, GameState.get_extinguisher_at_station(st) != "")
	for id in GameState.extinguishers.keys():
		var e: Dictionary = GameState.extinguishers[id]
		var on_floor: bool = GameState.is_active and int(e["held_by"]) == 0 and str(e["station"]) == ""
		var node: Variant = _extinguisher_nodes.get(id)
		if not on_floor:
			if is_instance_valid(node):
				(node as Node).queue_free()
			_extinguisher_nodes.erase(id)
			continue
		if not is_instance_valid(node):
			node = _garage.build_loose_extinguisher(str(id))
			add_child(node as Node3D)
			_extinguisher_nodes[id] = node
		(node as Node3D).position = e["pos"]
		(node as Node3D).rotation.y = float(e["yaw"])


func _sync_racks() -> void:
	for rid in _rack_nodes.keys():
		if not GameState.racks.has(rid):
			_rack_nodes[rid].queue_free()
			_rack_nodes.erase(rid)
	for rid in GameState.racks.keys():
		var data: Dictionary = GameState.racks[rid]
		if not _rack_nodes.has(rid):
			var rp := RackProp.new()
			rp.name = rid
			_racks_container.add_child(rp)
			rp.setup(rid, str(data.get("rack_type", "rack")), false)
			_rack_nodes[rid] = rp
		(_rack_nodes[rid] as RackProp).apply_data(data)
	_sync_cables()


func _sync_coolers() -> void:
	for cid in _cooler_nodes.keys():
		if not GameState.coolers.has(cid):
			_cooler_nodes[cid].queue_free()
			_cooler_nodes.erase(cid)
	for cid in GameState.coolers.keys():
		var data: Dictionary = GameState.coolers[cid]
		if not _cooler_nodes.has(cid):
			var cp := CoolerProp.new()
			cp.name = cid
			_coolers_container.add_child(cp)
			cp.setup(cid, str(data.get("cooler_type", "cooler")), false)
			_cooler_nodes[cid] = cp
		(_cooler_nodes[cid] as CoolerProp).apply_data(data)
	_sync_cables()


func _sync_ups() -> void:
	for uid in _ups_nodes.keys():
		if not GameState.ups_units.has(uid):
			_ups_nodes[uid].queue_free()
			_ups_nodes.erase(uid)
	for uid in GameState.ups_units.keys():
		if not _ups_nodes.has(uid):
			var up := UpsProp.new()
			up.name = uid
			_ups_container.add_child(up)
			up.setup(uid, str((GameState.ups_units[uid] as Dictionary).get("ups_type", "ups")))
			_ups_nodes[uid] = up
		(_ups_nodes[uid] as UpsProp).apply_data(GameState.ups_units[uid])
	_sync_cables()


func _sync_decor_items() -> void:
	for did in _decor_nodes.keys():
		if not GameState.decor_items.has(did):
			_decor_nodes[did].queue_free()
			_decor_nodes.erase(did)
	for did in GameState.decor_items.keys():
		var d: Dictionary = GameState.decor_items[did]
		if not _decor_nodes.has(did):
			var dp := DecorProp.new()
			dp.name = str(did)
			_ups_container.add_child(dp)
			dp.setup(str(did), str(d.get("item_type", "")), d)
			_decor_nodes[did] = dp
		else:
			(_decor_nodes[did] as DecorProp).apply_data(d)
	_sync_cables()


func _sync_carts() -> void:
	for cid in _cart_nodes.keys():
		if not GameState.carts.has(cid):
			_cart_nodes[cid].queue_free()
			_cart_nodes.erase(cid)
	for cid in GameState.carts.keys():
		if not _cart_nodes.has(cid):
			var cp := CartProp.new()
			cp.name = cid
			_carts_container.add_child(cp)
			cp.setup(cid)
			_cart_nodes[cid] = cp
		(_cart_nodes[cid] as CartProp).apply_data(GameState.carts[cid])


func update_local_pushed_cart(cart_id: String, pos: Vector3, rot_y: float) -> void:
	if _cart_nodes.has(cart_id):
		(_cart_nodes[cart_id] as CartProp).apply_live_pose(pos, rot_y, true)


func send_cart_pose(cart_id: String, pos: Vector3, rot_y: float) -> void:
	if not NetworkManager.is_in_session:
		return
	if multiplayer.is_server():
		GameState.update_cart_pose_from_host(cart_id, pos, rot_y)
		_rpc_relay_cart_pose.rpc(1, cart_id, pos, rot_y)
	else:
		_rpc_submit_cart_pose.rpc_id(1, cart_id, pos, rot_y)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_cart_pose(cart_id: String, pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	if not GameState.carts.has(cart_id) or int(GameState.carts[cart_id].get("pushed_by", 0)) != sid:
		return
	GameState.update_cart_pose_from_host(cart_id, pos, rot_y)
	if _cart_nodes.has(cart_id):
		(_cart_nodes[cart_id] as CartProp).apply_live_pose(pos, rot_y, false)
	_rpc_relay_cart_pose.rpc(sid, cart_id, pos, rot_y)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_relay_cart_pose(pusher_id: int, cart_id: String, pos: Vector3, rot_y: float) -> void:
	if pusher_id == multiplayer.get_unique_id():
		return
	if _cart_nodes.has(cart_id):
		(_cart_nodes[cart_id] as CartProp).apply_live_pose(pos, rot_y, false)


func _sync_crates() -> void:
	for cid in _crate_nodes.keys():
		if not GameState.crates.has(cid):
			_crate_nodes[cid].queue_free()
			_crate_nodes.erase(cid)
	for cid in GameState.crates.keys():
		var data: Dictionary = GameState.crates[cid]
		if not _crate_nodes.has(cid):
			var cp := CrateProp.new()
			cp.name = cid
			_crates_container.add_child(cp)
			cp.setup(cid, str(data["item_type"]), data)
			_crate_nodes[cid] = cp
		(_crate_nodes[cid] as CrateProp).apply_data(data)


func _sync_cables() -> void:
	_cable_renderer.rebuild_cables(GameState.cables, get_port_world_pos, get_port_world_dir, _make_cable_socket_resolver(), _make_cable_dir_resolver())


## Im Menü bleiben die Showcase-Kabel stehen; nur in einer laufenden Sitzung neu zeichnen.
func _on_router_visuals_rebuilt() -> void:
	if GameState.is_active:
		_sync_cables()


## Legt jedes Kabel an Anschlüssen mit mehreren Buchsen (Strombus Halle C, Wand-Router)
## auf die beim Stecken gewählte Buchse. null = allgemeiner Port des Anschlusses.
func _make_cable_socket_resolver() -> Callable:
	var slot_maps := {}
	return func(cid: String, ctype: String, eid: String) -> Variant:
		var socks := get_socket_positions(ctype, eid)
		if socks.is_empty():
			return null
		var key := ctype + "|" + eid
		if not slot_maps.has(key):
			slot_maps[key] = GameState.get_cable_slot_map(ctype, eid)
		var slots: Dictionary = slot_maps[key]
		if not slots.has(cid):
			return null
		var idx := int(slots[cid])
		if idx >= 0 and idx < socks.size():
			return socks[idx]
		return null


## Seitenbuchsen der Leisten zeigen zur Seite, nicht nach oben.
func _make_cable_dir_resolver() -> Callable:
	var slot_maps := {}
	return func(cid: String, ctype: String, eid: String) -> Variant:
		if StripRules.role(ctype, eid) != "strip" or not _decor_nodes.has(eid):
			return null
		var key := ctype + "|" + eid
		if not slot_maps.has(key):
			slot_maps[key] = GameState.get_cable_slot_map(ctype, eid)
		var idx := int((slot_maps[key] as Dictionary).get(cid, -1))
		var dn: DecorProp = _decor_nodes[eid]
		if not is_instance_valid(dn) or not dn.is_inside_tree():
			return null
		if idx == StripRules.in_slot(ctype):
			return -dn.global_transform.basis.x
		if idx == StripRules.out_slot(ctype):
			return dn.global_transform.basis.x
		return null


## Weltpositionen der einzelnen Buchsen eines Anschlusses. Leer = Anschluss hat nur einen Steckpunkt.
func get_socket_positions(cable_type: String, endpoint_id: String) -> Array[Vector3]:
	if cable_type == "power" and endpoint_id == GameState.HALL_C_BREAKER_ID:
		return _garage.get_hall_c_socket_positions()
	if cable_type == "network" and endpoint_id == GameState.WALL_ROUTER_ID:
		return _garage.get_router_jack_positions()
	var fixed: Array[Vector3] = _garage.get_fixed_socket_positions(cable_type, endpoint_id)
	if not fixed.is_empty():
		return fixed
	if _rack_nodes.has(endpoint_id):
		var rp: RackProp = _rack_nodes[endpoint_id]
		if is_instance_valid(rp):
			return rp.get_socket_world_positions(cable_type)
	if cable_type == "power" and _ups_nodes.has(endpoint_id):
		var up: UpsProp = _ups_nodes[endpoint_id]
		if is_instance_valid(up):
			return up.get_socket_world_positions()
	if _decor_nodes.has(endpoint_id):
		var dp: DecorProp = _decor_nodes[endpoint_id]
		if is_instance_valid(dp):
			return dp.get_socket_world_positions()
	return []


## Weltposition der Buchse idx, sonst der allgemeine Port des Anschlusses.
func get_socket_world_pos(cable_type: String, endpoint_id: String, idx: int) -> Variant:
	var socks := get_socket_positions(cable_type, endpoint_id)
	if idx >= 0 and idx < socks.size():
		return socks[idx]
	return get_port_world_pos(cable_type, endpoint_id)


## Richtung, in die ein Port zeigt (Kabel verlässt die Buchse in diese Richtung). null = unbekannt.
func get_port_world_dir(_cable_type: String, endpoint_id: String) -> Variant:
	# Wandkästen hängen an der Rückwand und zeigen in den Raum (+Z)
	if endpoint_id == GameState.WALL_BREAKER_ID or endpoint_id == GameState.HALL_C_BREAKER_ID \
			or endpoint_id == GameState.HALL_NORD_BREAKER_ID \
			or endpoint_id == GameState.WALL_ROUTER_ID or endpoint_id == GameState.HALL_C_ROUTER_ID \
			or endpoint_id == GameState.HALL_NORD_ROUTER_ID:
		return Vector3.BACK
	if _rack_nodes.has(endpoint_id):
		var rp: RackProp = _rack_nodes[endpoint_id]
		if is_instance_valid(rp) and rp.is_inside_tree():
			# Rack-Ports (Strom, LAN, Cluster-Link) sitzen an der Rückseite (-Z lokal) -> Kabel nach hinten herausführen!
			return -rp.global_transform.basis.z
	if _ups_nodes.has(endpoint_id):
		var up: UpsProp = _ups_nodes[endpoint_id]
		if is_instance_valid(up) and up.is_inside_tree():
			return up.global_transform.basis.z
	if _decor_nodes.has(endpoint_id):
		var dn: DecorProp = _decor_nodes[endpoint_id]
		if is_instance_valid(dn) and dn.is_inside_tree():
			if dn.is_on_wall():
				return dn.global_transform.basis.y
			# Buchsen zeigen nach oben (y > 0.5), das Kabel läuft quer zur Leiste weg.
			return dn.global_transform.basis.z + Vector3.UP
		return Vector3.UP
	return null


func _sync_all_players() -> void:
	for pid in NetworkManager.players.keys():
		_spawn_player_if_missing(int(pid), NetworkManager.players[pid])


func _on_player_joined(peer_id: int, info: Dictionary) -> void:
	if not NetworkManager.is_in_session:
		return
	_spawn_player_if_missing(peer_id, info)


func _on_player_left(peer_id: int) -> void:
	if _player_nodes.has(peer_id):
		var node: Node = _player_nodes[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_player_nodes.erase(peer_id)


func _spawn_player_if_missing(peer_id: int, info: Dictionary) -> void:
	if _player_nodes.has(peer_id):
		return
	var my_id := multiplayer.get_unique_id()
	var is_me := (peer_id == my_id)

	var p := PlayerController.new()
	p.name = "Player_%d" % peer_id
	var spawn_idx := _player_nodes.size()
	p.position = Vector3(-1.2 + float(spawn_idx) * 1.1, 0.05, 1.6)
	p.setup(
		peer_id,
		is_me,
		str(info.get("name", "Spieler")),
		info.get("color", Color(0.22, 0.72, 0.98)),
		self
	)
	p.apply_skin(info.get("skin", {}))
	_players_container.add_child(p)
	p.add_to_group("players")
	_player_nodes[peer_id] = p
	if is_me:
		local_player = p


func _on_player_skin(peer_id: int) -> void:
	var node: PlayerController = _player_nodes.get(peer_id) as PlayerController
	if node != null and is_instance_valid(node) and NetworkManager.players.has(peer_id):
		node.apply_skin((NetworkManager.players[peer_id] as Dictionary).get("skin", {}))


## Kurze Handlung (greifen, stecken, drücken) bei den Mitspielern zeigen.
func send_local_action(action: String, at: Vector3) -> void:
	if not NetworkManager.is_in_session:
		return
	if multiplayer.is_server():
		_rpc_relay_action.rpc(1, action, at)
	else:
		_rpc_submit_action.rpc_id(1, action, at)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_submit_action(action: String, at: Vector3) -> void:
	if not multiplayer.is_server() or not HumanRig.ACTIONS.has(action) or not at.is_finite():
		return
	var sid := multiplayer.get_remote_sender_id()
	if not SecurityGuard.check_rate_limit(sid, "action", 12, 2.0, false):
		return
	var node := _ensure_remote_player(sid)
	if node != null:
		node.play_remote_action(action, at)
	_rpc_relay_action.rpc(sid, action, at)


@rpc("authority", "call_remote", "unreliable")
func _rpc_relay_action(peer_id: int, action: String, at: Vector3) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var node := _ensure_remote_player(peer_id)
	if node != null:
		node.play_remote_action(action, at)


func send_local_pose(pos: Vector3, yaw: float, pitch: float, tool: int, spraying: bool) -> void:
	if not NetworkManager.is_in_session:
		return
	if multiplayer.is_server():
		_rpc_relay_pose.rpc(1, pos, yaw, pitch, tool, spraying)
	else:
		_rpc_submit_pose.rpc_id(1, pos, yaw, pitch, tool, spraying)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_pose(pos: Vector3, yaw: float, pitch: float, tool: int, spraying: bool) -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	var node := _ensure_remote_player(sid)
	if node != null:
		node.apply_remote_pose(pos, yaw, pitch, tool, spraying)
	_rpc_relay_pose.rpc(sid, pos, yaw, pitch, tool, spraying)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_relay_pose(peer_id: int, pos: Vector3, yaw: float, pitch: float, tool: int, spraying: bool) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var node := _ensure_remote_player(peer_id)
	if node != null:
		node.apply_remote_pose(pos, yaw, pitch, tool, spraying)


## Liefert die Figur eines fremden Spielers und legt sie bei Bedarf an.
## Fängt ab, dass player_joined zu früh kam oder die Figur inzwischen entfernt wurde.
func _ensure_remote_player(peer_id: int) -> PlayerController:
	if _player_nodes.has(peer_id) and not is_instance_valid(_player_nodes[peer_id]):
		_player_nodes.erase(peer_id)
	if not _player_nodes.has(peer_id):
		if not NetworkManager.is_in_session or not NetworkManager.players.has(peer_id):
			return null
		_spawn_player_if_missing(peer_id, NetworkManager.players[peer_id])
	return _player_nodes.get(peer_id) as PlayerController
