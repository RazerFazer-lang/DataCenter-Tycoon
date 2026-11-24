extends Node
## v1.0 Realistic Click-Free 44.1 kHz Audio Engine (16-bit PCM).
## Zero loop clicks/pops (warmed-up filters, equal-power circular crossfades, integer-cycle harmonics,
## safe loop_end = count - 1). Includes tactile mechanical keyboard typing, VoIP phone ringing,
## support ticket chime, chair sit-down sound, RJ45/IEC plugs, 1U rails, footsteps & 3D hardware hums.

const MIX_RATE := 44100
# Erzeugte Klänge werden hier gespeichert, damit nur der erste Start rechnen muss (~870 ms gemessen).
const SFX_CACHE_DIR := "user://sfx_cache"
# Erhöhen, wenn sich ein Generator oder seine Parameter ändern, sonst bleiben die alten Klänge im Cache.
const SFX_CACHE_VERSION := 15
const EXTERNAL_AUDIO_DIR := "res://assets/audio"

var _sounds: Dictionary = {}
var _loops: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _room_amb_player: AudioStreamPlayer
var _rain_amb_player: AudioStreamPlayer
var _rain_roof_player: AudioStreamPlayer
var _outdoor_day_player: AudioStreamPlayer
var _outdoor_night_player: AudioStreamPlayer
var _distant_highway_player: AudioStreamPlayer
var _wind_gust_player: AudioStreamPlayer
var _overload_player: AudioStreamPlayer
var _overload_stinger_accum: float = 0.0
var _listener_outdoor: bool = false
var _outdoor_blend: float = 0.0
var _garage_door_open: float = 1.0


func _ready() -> void:
	for _i in range(16):
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_pool.append(player)

	if not _load_sound_cache():
		_generate_sounds()
		_save_sound_cache()
	_load_external_audio_samples()
	_setup_room_ambience()


func _generate_sounds() -> void:
	# Tactile mechanical & UI interaction sounds (zero harsh synth beeps)
	_sounds["click"] = _gen_mouse_click()
	_sounds["key_type"] = _gen_keyboard_keystroke()
	_sounds["chair_sit"] = _gen_chair_sit()
	_sounds["pickup"] = _gen_handling_thud(155.0, 0.11, true)
	_sounds["drop"] = _gen_handling_thud(110.0, 0.14, false)
	_sounds["place"] = _gen_heavy_steel_place()
	_sounds["snap"] = _gen_server_rail_slide()
	_sounds["cable"] = _gen_cable_plug_snap(true)
	_sounds["cable_cut"] = _gen_cable_plug_snap(false)
	_sounds["breaker_on"] = _gen_breaker_switch_on()
	_sounds["breaker_trip"] = _gen_breaker_trip()
	_sounds["power_down"] = _gen_power_down_whine()
	_sounds["upgrade"] = _gen_hardware_install_ratchet()
	# Werkbank: Schraubendreher, Clips, Steckplätze, Paste
	_sounds["screw_tick"] = _gen_click_burst([[0.0, 2300.0, 0.30, 260.0], [0.006, 1500.0, 0.20, 210.0]], 0.035, 0.30)
	_sounds["screw_tight"] = _gen_click_burst([[0.0, 900.0, 0.36, 60.0], [0.045, 1650.0, 0.42, 120.0], [0.052, 520.0, 0.30, 50.0]], 0.16, 0.26)
	_sounds["screw_loose"] = _gen_click_burst([[0.0, 620.0, 0.30, 55.0], [0.030, 2100.0, 0.24, 150.0]], 0.13, 0.22)
	_sounds["clip"] = _gen_click_burst([[0.0, 1850.0, 0.46, 120.0], [0.022, 780.0, 0.36, 80.0], [0.026, 3100.0, 0.18, 220.0]], 0.11, 0.34)
	_sounds["part_set"] = _gen_click_burst([[0.0, 240.0, 0.48, 44.0], [0.004, 1250.0, 0.20, 130.0]], 0.15, 0.24)
	_sounds["part_touch"] = _gen_click_burst([[0.0, 1400.0, 0.24, 150.0]], 0.06, 0.18)
	_sounds["part_slide"] = _gen_friction_slide(0.20)
	_sounds["tool_pick"] = _gen_click_burst([[0.0, 3400.0, 0.20, 75.0], [0.018, 2500.0, 0.16, 60.0]], 0.14, 0.10)
	_sounds["paste"] = _gen_soft_squish(0.22)
	_sounds["screw_strain"] = _gen_click_burst([[0.0, 310.0, 0.34, 18.0], [0.05, 460.0, 0.30, 22.0], [0.11, 620.0, 0.26, 26.0]], 0.24, 0.20)
	_sounds["drill"] = _gen_drill_burst(0.15)
	_sounds["post_beep"] = _gen_soft_chime([987.77], 0.16, 0.30)
	_sounds["meter_beep"] = _gen_soft_chime([1760.0], 0.09, 0.20)
	for v in range(FOOTSTEP_VARIANTS):
		_sounds["footstep_%d" % v] = _gen_footstep(v)
	_sounds["footstep"] = _sounds["footstep_0"]
	_sounds["step_raised"] = _gen_step_raised_floor()
	_sounds["step_wet"] = _gen_step_wet_asphalt()
	_sounds["extinguisher_start"] = _gen_extinguisher_burst()
	_sounds["van_horn"] = _gen_van_horn()
	_sounds["van_door"] = _gen_sliding_door()
	_sounds["cart_load"] = _gen_handling_thud(185.0, 0.10, false)
	_sounds["spark"] = _gen_spark_crack()
	_sounds["thunder"] = _gen_thunder_roll()
	_sounds["ping"] = _gen_soft_chime([880.0, 1318.51], 0.04, 0.13)
	_sounds["emote"] = _gen_soft_chime([523.25, 659.25], 0.045, 0.12)
	_sounds["backup_beep"] = _gen_backup_beep()
	_sounds["air_brake"] = _gen_air_brake_hiss()
	_sounds["garage_door_stop"] = _gen_handling_thud(92.0, 0.18, false)
	_sounds["distant_jet"] = _gen_distant_jet_pass()
	_sounds["distant_yard_beep"] = _gen_distant_yard_beep()

	# Support Desk, VoIP Phone & Clean System Chimes
	_sounds["phone_ring"] = _gen_office_phone_ring()
	_sounds["phone_pickup"] = _gen_soft_chime([520.0, 740.0], 0.045, 0.14)
	_sounds["phone_hangup"] = _gen_soft_chime([620.0, 410.0], 0.055, 0.14)
	_sounds["ticket_notify"] = _gen_soft_chime([659.25, 880.0], 0.06, 0.16)
	_sounds["cash"] = _gen_soft_chime([587.33, 880.0], 0.075, 0.18)
	_sounds["sell"] = _gen_soft_chime([659.25, 987.77], 0.075, 0.18)
	_sounds["save"] = _gen_soft_chime([523.25, 659.25, 783.99], 0.06, 0.16)
	_sounds["repair"] = _gen_soft_chime([440.0, 554.37, 659.25], 0.07, 0.18)
	_sounds["error"] = _gen_soft_thud_buzz()
	_sounds["alarm"] = _gen_soft_chime([720.0, 540.0], 0.11, 0.18)
	_sounds["ups_beep"] = _gen_soft_chime([1120.0], 0.08, 0.14)
	_sounds["bill"] = _gen_soft_chime([440.0, 392.0], 0.09, 0.16)

	# Windows-typische Systemklänge des Büro-PCs
	_sounds["win_logon"] = _gen_os_chord([392.0, 587.33, 783.99, 1174.66], 0.16, 1.6, 0.11)
	_sounds["win_shutdown"] = _gen_os_chord([1174.66, 783.99, 587.33, 392.0], 0.14, 1.4, 0.10)
	_sounds["win_notify"] = _gen_soft_chime([880.0, 1318.51], 0.05, 0.13)
	_sounds["win_ding"] = _gen_soft_chime([1046.5, 1046.5], 0.0, 0.10)
	_sounds["win_error"] = _gen_soft_chime([587.33, 440.0], 0.07, 0.15)
	_sounds["win_start"] = _gen_soft_chime([660.0, 990.0], 0.03, 0.07)
	_sounds["win_open"] = _gen_filtered_noise(0.09, 0.07, 0.45)

	# 100% Seamless, Click-Free Looping 3D Spatial Hardware & Room Ambience
	_loops["server_fan"] = _gen_server_fan_loop(3.0)
	_loops["cooler_fan"] = _gen_cooler_fan_loop(2.0)
	_loops["pc_hum"] = _gen_pc_workstation_loop(2.0)
	_loops["breaker_hum"] = _gen_mains_hum_loop(2.0, 50.0)
	_loops["ups_hum"] = _gen_ups_loop(2.0)
	_loops["room_ambience"] = _gen_room_hvac_loop(3.0)
	_loops["van_engine"] = _gen_van_engine_loop(2.0)
	_loops["cart_roll"] = _gen_cart_roll_loop(2.0)
	_loops["extinguisher_spray"] = _gen_extinguisher_spray_loop(2.5)
	_loops["rain_ambience"] = _gen_rain_loop(8.0)
	_loops["rain_roof_indoor"] = _gen_rain_roof_loop(7.0)
	_loops["outdoor_day"] = _gen_outdoor_day_loop(14.0)
	_loops["outdoor_night"] = _gen_outdoor_night_loop(9.0)
	_loops["wind_gust"] = _gen_wind_gust_loop(4.0)
	_loops["car_pass_sedan"] = _gen_car_pass_loop(2.0, false)
	_loops["car_pass_truck"] = _gen_car_pass_loop(2.5, true)
	_loops["tire_wet"] = _gen_tire_wet_loop(2.0)
	_loops["substation_hum"] = _gen_mains_hum_loop(2.0, 50.0)
	_loops["diesel_gen_idle"] = _gen_diesel_gen_loop(3.0)
	_loops["garage_door_motor"] = _gen_garage_door_motor_loop(2.0)
	_loops["distant_highway"] = _gen_distant_highway_loop(5.0)


const FOOTSTEP_VARIANTS := 6
## Wie lange der Sprühton nach dem letzten keep_extinguisher_spraying()-Aufruf weiterläuft.
## Großzügig genug, damit auch bei Mikrorucklern kein Hacken ("zz zzz zz") entsteht.
const SPRAY_HOLD_TIME := 0.22

var _footstep_count := FOOTSTEP_VARIANTS
var _last_footstep := -1
var _spray_player: AudioStreamPlayer
var _spray_hold := 0.0
var _spray_level := 0.0
var _was_spraying := false


## Lädt echte Audio-Aufnahmen (.ogg / .wav) aus res://assets/audio/ und überschreibt damit
## die prozeduralen Fallbacks (Schritte auf Beton + Feuerlöscher Start/Loop/Stop).
func _load_external_audio_samples() -> void:
	var loaded_steps := 0
	for i in range(12):
		var step_stream := _load_audio_file("footstep_%d" % i)
		if step_stream == null:
			break
		_sounds["footstep_%d" % i] = step_stream
		loaded_steps += 1
	if loaded_steps > 0:
		_footstep_count = loaded_steps
		_sounds["footstep"] = _sounds["footstep_0"]

	var ext_start := _load_audio_file("extinguisher_start")
	if ext_start != null:
		_sounds["extinguisher_start"] = ext_start
	var ext_stop := _load_audio_file("extinguisher_stop")
	if ext_stop != null:
		_sounds["extinguisher_stop"] = ext_stop
	var ext_loop := _load_audio_file("extinguisher_loop")
	if ext_loop != null:
		if ext_loop is AudioStreamWAV:
			var wav := ext_loop as AudioStreamWAV
			# get_length() liefert auch bei QOA/IMA-ADPCM-Kompression immer die exakte echte Gesamtdauer!
			var total_frames := int(roundf(wav.get_length() * float(maxi(1, wav.mix_rate))))
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = maxi(1, total_frames - 2)
		elif ext_loop is AudioStreamOggVorbis:
			(ext_loop as AudioStreamOggVorbis).loop = true
		_loops["extinguisher_spray"] = ext_loop

	var intro_studio := _load_audio_file("intro_studio_swell")
	if intro_studio != null:
		_sounds["intro_studio_swell"] = intro_studio
	var intro_title := _load_audio_file("intro_title_hit")
	if intro_title != null:
		_sounds["intro_title_hit"] = intro_title


func _load_audio_file(base_name: String) -> AudioStream:
	for ext in [".wav", ".ogg"]:
		var path := "%s/%s%s" % [EXTERNAL_AUDIO_DIR, base_name, ext]
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path)
			if res is AudioStream:
				return res as AudioStream
	return null


func _setup_room_ambience() -> void:
	# Very subtle warm room presence (ONLY plays in-game, completely quiet in Main Menu!)
	_room_amb_player = AudioStreamPlayer.new()
	_room_amb_player.stream = _loops["room_ambience"]
	_room_amb_player.volume_db = -80.0
	add_child(_room_amb_player)
	SettingsManager.settings_changed.connect(_update_room_ambience_volume)
	_overload_player = AudioStreamPlayer.new()
	_overload_player.stream = _loops["breaker_hum"]
	_overload_player.volume_db = -80.0
	add_child(_overload_player)
	_spray_player = AudioStreamPlayer.new()
	_spray_player.stream = _loops.get("extinguisher_spray") as AudioStream
	_spray_player.volume_db = -80.0
	add_child(_spray_player)
	_rain_amb_player = AudioStreamPlayer.new()
	_rain_amb_player.stream = _loops.get("rain_ambience") as AudioStream
	_rain_amb_player.volume_db = -80.0
	add_child(_rain_amb_player)
	_rain_roof_player = AudioStreamPlayer.new()
	_rain_roof_player.stream = _loops.get("rain_roof_indoor") as AudioStream
	_rain_roof_player.volume_db = -80.0
	add_child(_rain_roof_player)
	_outdoor_day_player = AudioStreamPlayer.new()
	_outdoor_day_player.stream = _loops.get("outdoor_day") as AudioStream
	_outdoor_day_player.volume_db = -80.0
	add_child(_outdoor_day_player)
	_outdoor_night_player = AudioStreamPlayer.new()
	_outdoor_night_player.stream = _loops.get("outdoor_night") as AudioStream
	_outdoor_night_player.volume_db = -80.0
	add_child(_outdoor_night_player)
	_distant_highway_player = AudioStreamPlayer.new()
	_distant_highway_player.stream = _loops.get("distant_highway") as AudioStream
	_distant_highway_player.volume_db = -80.0
	add_child(_distant_highway_player)
	_wind_gust_player = AudioStreamPlayer.new()
	_wind_gust_player.stream = _loops.get("wind_gust") as AudioStream
	_wind_gust_player.volume_db = -80.0
	add_child(_wind_gust_player)


func _cache_index_path() -> String:
	return "%s/index_v%d.cfg" % [SFX_CACHE_DIR, SFX_CACHE_VERSION]


func _cache_stream_path(kind: String, stream_name: String) -> String:
	return "%s/%s_%s_v%d.res" % [SFX_CACHE_DIR, kind, stream_name, SFX_CACHE_VERSION]


## Lädt alle Klänge aus user://sfx_cache. Liefert false, wenn der Index fehlt oder ein Klang fehlt
## oder kaputt ist. Dann bleiben _sounds und _loops leer, und der Aufrufer erzeugt alles neu.
func _load_sound_cache() -> bool:
	var index_path := _cache_index_path()
	if not FileAccess.file_exists(index_path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(index_path) != OK:
		return false
	var ok := _load_streams_into(_sounds, "sfx", cfg.get_value("cache", "sounds", PackedStringArray())) \
		and _load_streams_into(_loops, "loop", cfg.get_value("cache", "loops", PackedStringArray()))
	if not ok or _sounds.is_empty() or not _loops.has("room_ambience"):
		_sounds.clear()
		_loops.clear()
		return false
	return true


func _load_streams_into(target: Dictionary, kind: String, names: Variant) -> bool:
	if not (names is PackedStringArray):
		return false
	for stream_name in names:
		var path := _cache_stream_path(kind, stream_name)
		if not ResourceLoader.exists(path):
			return false
		var res := ResourceLoader.load(path, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE)
		if not (res is AudioStreamWAV):
			return false
		target[stream_name] = res
	return true


## Speichert alle Klänge. Den Index erst zum Schluss schreiben, damit ein halb gespeicherter Cache nie geladen wird.
func _save_sound_cache() -> void:
	DirAccess.make_dir_recursive_absolute(SFX_CACHE_DIR)
	if not (_save_streams(_sounds, "sfx") and _save_streams(_loops, "loop")):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("cache", "sounds", PackedStringArray(_sounds.keys()))
	cfg.set_value("cache", "loops", PackedStringArray(_loops.keys()))
	var err := cfg.save(_cache_index_path())
	if err != OK:
		push_warning("Sound-Cache-Index konnte nicht gespeichert werden (Fehler %d)" % err)


func _save_streams(source: Dictionary, kind: String) -> bool:
	for stream_name in source:
		var path := _cache_stream_path(kind, stream_name)
		var err := ResourceSaver.save(source[stream_name] as Resource, path)
		if err != OK:
			push_warning("Klang '%s' konnte nicht gespeichert werden (Fehler %d)" % [stream_name, err])
			return false
	return true


var _hall_reverb: AudioEffectReverb = null
var _listener_in_large_hall: bool = false


func set_listener_outdoor(outdoor: bool, in_large_hall: bool = false) -> void:
	_listener_outdoor = outdoor
	_listener_in_large_hall = in_large_hall
	if _hall_reverb == null:
		var bus_idx := AudioServer.get_bus_index("Master")
		if bus_idx >= 0:
			_hall_reverb = AudioEffectReverb.new()
			_hall_reverb.room_size = 0.48
			_hall_reverb.damping = 0.58
			_hall_reverb.spread = 0.72
			_hall_reverb.wet = 0.0
			_hall_reverb.dry = 1.0
			AudioServer.add_bus_effect(bus_idx, _hall_reverb)
	if _hall_reverb != null:
		if outdoor:
			_hall_reverb.wet = 0.0
		elif in_large_hall:
			_hall_reverb.room_size = 0.56
			_hall_reverb.wet = 0.14
		else:
			_hall_reverb.room_size = 0.28
			_hall_reverb.wet = 0.06


func set_garage_door_open(open_amount: float) -> void:
	_garage_door_open = clampf(open_amount, 0.0, 1.0)


## Wie stark Aussengeraeusche (Verkehr, Wind, Voegel) beim Spieler ankommen:
## 1.0 draussen, ~0.58 drinnen bei offenem Tor, ~0.16 drinnen bei geschlossenem Tor!
func get_outdoor_transmission() -> float:
	var inside_leak := lerpf(0.16, 0.58, _garage_door_open)
	return lerpf(inside_leak, 1.0, _outdoor_blend)


func _process(delta: float) -> void:
	_outdoor_blend = move_toward(_outdoor_blend, 1.0 if _listener_outdoor else 0.0, delta * 3.2)
	_update_overload_hum(delta)
	_update_extinguisher_spray(delta)
	_update_rain_ambience()
	_update_outdoor_ambience()
	if _room_amb_player == null:
		return
	var should_play := GameState.is_active and SettingsManager.get_effective_fan_gain() > 0.005
	if should_play:
		if not _room_amb_player.playing:
			_room_amb_player.play()
		_update_room_ambience_volume()
	else:
		if _room_amb_player.playing:
			_room_amb_player.stop()


func _update_room_ambience_volume() -> void:
	if _room_amb_player == null:
		return
	var gain := SettingsManager.get_effective_fan_gain()
	if not GameState.is_active or gain <= 0.005:
		_room_amb_player.volume_db = -80.0
	else:
		# Dynamische Raum-Akustik: leere Garage ist still, volles Rechenzentrum hat tiefes Rauschen; draußen gedämpft!
		var rack_fill := clampf(float(GameState.racks.size()) / 8.0, 0.0, 1.0)
		var power_mult := 1.0 if (GameState.breaker_on or GameState.ups_backup_active) else 0.15
		var indoor_db := lerpf(-37.0, -25.0, rack_fill * power_mult)
		var outdoor_muffle := _outdoor_blend * 9.5
		_room_amb_player.volume_db = linear_to_db(gain) + indoor_db - outdoor_muffle
		_room_amb_player.pitch_scale = lerpf(0.95, 1.06, rack_fill * power_mult)


func _update_rain_ambience() -> void:
	var w: String = GameState.weather_state if GameState.is_active else "clear"
	var raining := (w == "rain" or w == "storm")
	var gain := SettingsManager.get_effective_fan_gain()
	var trans := get_outdoor_transmission()
	if _rain_amb_player != null and _rain_amb_player.stream != null:
		if not raining or gain <= 0.005:
			if _rain_amb_player.playing:
				_rain_amb_player.stop()
		else:
			if not _rain_amb_player.playing:
				_rain_amb_player.play()
			var storm_boost := 3.5 if w == "storm" else 0.0
			var base_db := lerpf(-27.0, -12.5, trans) + storm_boost
			_rain_amb_player.volume_db = linear_to_db(gain) + base_db

	# Echtes Regen-Prasseln auf dem Hallen-Blechdach (drinnen deutlich hoerbar!)
	if _rain_roof_player != null and _rain_roof_player.stream != null:
		if not raining or gain <= 0.005 or _outdoor_blend > 0.96:
			if _rain_roof_player.playing:
				_rain_roof_player.stop()
		else:
			if not _rain_roof_player.playing:
				_rain_roof_player.play()
			var indoor_factor := clampf(1.0 - _outdoor_blend, 0.05, 1.0)
			var roof_boost := 3.0 if w == "storm" else 0.0
			_rain_roof_player.volume_db = linear_to_db(gain * indoor_factor) - 17.5 + roof_boost

	# Windboeen bei Gewitter / Regen
	if _wind_gust_player != null and _wind_gust_player.stream != null:
		var windy := (w == "storm" or w == "rain") and GameState.is_active and gain > 0.005
		if not windy:
			if _wind_gust_player.playing:
				_wind_gust_player.stop()
		else:
			if not _wind_gust_player.playing:
				_wind_gust_player.play()
			var w_db := (-15.5 if w == "storm" else -24.0) + lerpf(-10.0, 0.0, trans)
			_wind_gust_player.volume_db = linear_to_db(gain) + w_db


func _update_outdoor_ambience() -> void:
	var gain := SettingsManager.get_effective_fan_gain()
	var active := GameState.is_active and gain > 0.005
	var trans := get_outdoor_transmission()
	var w: String = GameState.weather_state if active else "clear"
	var quiet_birds := (w == "rain" or w == "storm")
	var tod := GameState.time_of_day if active else 0.38
	var is_night := (tod < 0.24 or tod > 0.76)

	if _outdoor_day_player != null and _outdoor_day_player.stream != null:
		var day_on := active and not is_night and not quiet_birds and trans > 0.14
		if not day_on:
			if _outdoor_day_player.playing:
				_outdoor_day_player.stop()
		else:
			if not _outdoor_day_player.playing:
				_outdoor_day_player.play()
			_outdoor_day_player.volume_db = linear_to_db(gain * trans) - 18.5

	if _outdoor_night_player != null and _outdoor_night_player.stream != null:
		var night_on := active and is_night and not quiet_birds and trans > 0.14
		if not night_on:
			if _outdoor_night_player.playing:
				_outdoor_night_player.stop()
		else:
			if not _outdoor_night_player.playing:
				_outdoor_night_player.play()
			_outdoor_night_player.volume_db = linear_to_db(gain * trans) - 21.5

	# Ganz leises fernes Autobahn-/Gewerbegebiets-Rauschen am Horizont (macht die Welt lebendig!)
	if _distant_highway_player != null and _distant_highway_player.stream != null:
		var hw_on := active and trans > 0.22
		if not hw_on:
			if _distant_highway_player.playing:
				_distant_highway_player.stop()
		else:
			if not _distant_highway_player.playing:
				_distant_highway_player.play()
			var night_drop := -4.5 if is_night else 0.0
			_distant_highway_player.volume_db = linear_to_db(gain * trans) - 25.0 + night_drop


## Überlast-Kulisse: Während der Hauptschalter über der Leistungsgrenze läuft, wird das
## Brummen lauter und höher, und in unregelmäßigen Abständen kommt ein Alarmstoß.
## Der Pegel steigt mit dem Überlast-Timer (0 bis 3 Sekunden bis zum Auslösen).
func _update_overload_hum(delta: float) -> void:
	if _overload_player == null:
		return
	var gain := SettingsManager.get_effective_sfx_gain()
	var overloaded := GameState.is_active and GameState.breaker_on and GameState.total_watts > GameState.max_watts
	var level := clampf(GameState.overload_timer / 3.0, 0.0, 1.0) if overloaded else 0.0
	if level <= 0.01 or gain <= 0.005:
		if _overload_player.playing:
			_overload_player.stop()
		_overload_stinger_accum = 0.0
		return
	if not _overload_player.playing:
		_overload_player.play()
	_overload_player.volume_db = linear_to_db(gain) - 18.0 + level * 10.0
	_overload_player.pitch_scale = lerpf(1.0, 1.3, level)
	_overload_stinger_accum += delta
	if _overload_stinger_accum >= lerpf(3.0, 1.2, level):
		_overload_stinger_accum = 0.0
		play("alarm", -10.0 + level * 4.0, lerpf(0.9, 1.15, level))


func play(sfx_name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not _sounds.has(sfx_name):
		return
	var gain := SettingsManager.get_effective_sfx_gain()
	if gain <= 0.005:
		return
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = _sounds[sfx_name]
	player.volume_db = volume_db + linear_to_db(gain)
	player.pitch_scale = pitch
	player.play()


func play_typing_key(volume_db: float = -10.5) -> void:
	play("key_type", volume_db, randf_range(0.88, 1.16))


## Spielt eine zufällige Schritt-Variante passend zum Untergrund (Beton / Doppelboden / nasser Asphalt).
func play_footstep(sprinting: bool = false, surface: String = "concrete") -> void:
	var vol := -9.5 if sprinting else -13.0
	var pitch := randf_range(0.95, 1.09) if sprinting else randf_range(0.91, 1.05)
	if surface == "raised_floor" and _sounds.has("step_raised"):
		play("step_raised", vol + randf_range(-1.0, 0.8), pitch)
		return
	if surface == "wet" and _sounds.has("step_wet"):
		play("step_wet", vol + randf_range(-0.8, 0.8), pitch)
		return
	var count := maxi(1, _footstep_count)
	var idx := randi() % count
	if count > 1 and idx == _last_footstep:
		idx = (idx + 1) % count
	_last_footstep = idx
	play("footstep_%d" % idx, vol + randf_range(-1.0, 1.0), pitch)


## Jeden Frame aufrufen, solange gesprüht wird. Bleibt der Aufruf aus, blendet der Ton kurz aus.
func keep_extinguisher_spraying() -> void:
	_spray_hold = SPRAY_HOLD_TIME


func _update_extinguisher_spray(delta: float) -> void:
	if _spray_player == null or _spray_player.stream == null:
		return
	_spray_hold = maxf(_spray_hold - delta, 0.0)
	var active := _spray_hold > 0.0 and GameState.is_active
	var target := 1.0 if active else 0.0
	if active and not _was_spraying:
		play("extinguisher_start", -6.5, randf_range(0.97, 1.04))
	elif not active and _was_spraying:
		if _sounds.has("extinguisher_stop"):
			play("extinguisher_stop", -7.0, randf_range(0.96, 1.04))
	_was_spraying = active

	var rate := 14.0 if target > _spray_level else 7.0
	_spray_level = move_toward(_spray_level, target, delta * rate)
	var gain := SettingsManager.get_effective_sfx_gain()
	if _spray_level <= 0.001 or gain <= 0.005:
		if _spray_player.playing:
			_spray_player.stop()
		return
	if not _spray_player.playing:
		_spray_player.play(randf_range(0.0, 2.2))
	_spray_player.volume_db = linear_to_db(gain * _spray_level) - 6.5


func get_loop_stream(loop_name: String) -> AudioStreamWAV:
	if _loops.has(loop_name):
		return _loops[loop_name] as AudioStreamWAV
	return null


func get_sound_stream(sfx_name: String) -> AudioStream:
	if _sounds.has(sfx_name):
		return _sounds[sfx_name] as AudioStream
	return null


func _make_wav(samples: PackedFloat32Array, looping: bool = false) -> AudioStreamWAV:
	var n := samples.size()
	if n == 0:
		return AudioStreamWAV.new()
	# Remove any DC bias so loops and one-shots never click at start/end
	var mean := 0.0
	for i in range(n):
		mean += samples[i]
	mean /= float(n)

	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var v := clampf(samples[i] - mean, -0.98, 0.98)
		if not looping:
			# Micro 2ms fade-in/out on one-shots to eliminate any start/end pop
			var edge_n := mini(88, n / 4)
			if i < edge_n:
				v *= float(i) / float(edge_n)
			elif i >= n - edge_n:
				v *= float(n - 1 - i) / float(edge_n)
		bytes.encode_s16(i * 2, int(v * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# Safe loop_end for Godot's cubic interpolator (prevents OOB zero-sample click!)
		wav.loop_end = maxi(1, n - 2)
	return wav


func _make_seamless_noise(count: int, fade: int, alpha1: float, alpha2: float, w1: float, w2: float) -> PackedFloat32Array:
	# 1. Warm up lowpass filters so sample 0 starts in steady-state (zero ramp transient)
	var lp1 := 0.0
	var lp2 := 0.0
	for _w in range(4096):
		var r := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, r, alpha1)
		lp2 = lerpf(lp2, lp1, alpha2)

	# 2. Generate count + fade continuous filtered samples
	var raw := PackedFloat32Array()
	raw.resize(count + fade)
	for i in range(count + fade):
		var r := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, r, alpha1)
		lp2 = lerpf(lp2, lp1, alpha2)
		raw[i] = lp1 * w1 + lp2 * w2

	# 3. Equal-power cosine crossfade of tail [count..count+fade) into head [0..fade)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		if i < fade:
			var u := float(i) / float(fade)
			var c_tail := cos(u * PI * 0.5)
			var c_head := sin(u * PI * 0.5)
			out[i] = raw[count + i] * c_tail + raw[i] * c_head
		else:
			out[i] = raw[i]

	# 4. Lock last 2 samples smoothly to sample 0 for sample-exact cubic wrap
	if count > 4:
		out[count - 1] = lerpf(out[count - 2], out[0], 0.5)
	return out


## Einpoliger Tiefpass über einen Loop-Puffer. Der erste Durchlauf schwingt den Filter
## ein, dadurch läuft das Ergebnis an der Loop-Grenze ohne Sprung weiter.
func _loop_lowpass(src: PackedFloat32Array, alpha: float) -> PackedFloat32Array:
	var n := src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	if n == 0:
		return out
	var y := 0.0
	for i in range(n):
		y = lerpf(y, src[i], alpha)
	for i in range(n):
		y = lerpf(y, src[i], alpha)
		out[i] = y
	return out


## Ganze Schwingungen pro Loop, damit ein Ton an der Loop-Grenze nahtlos weiterläuft.
func _loop_cycles(hz: float, duration: float) -> float:
	return maxf(1.0, roundf(hz * duration))


## Skaliert einen Puffer auf einen Ziel-RMS, damit die Lautstärke-Balance der Props stimmt.
func _normalize_rms(samples: PackedFloat32Array, target_rms: float) -> PackedFloat32Array:
	var n := samples.size()
	if n == 0:
		return samples
	var acc := 0.0
	for i in range(n):
		acc += samples[i] * samples[i]
	var rms := sqrt(acc / float(n))
	if rms < 0.000001:
		return samples
	var g := target_rms / rms
	for i in range(n):
		samples[i] = clampf(samples[i] * g, -0.95, 0.95)
	return samples


## Ein Sample Trafobrummen: Grundton plus Obertöne durch weiches Clipping (Kernsättigung).
func _transformer_hum(ph: float, cycles: float) -> float:
	return tanh((sin(ph * cycles) + 0.35 * sin(ph * cycles * 2.0 + 0.4)) * 1.8)


## Mischt kurze, gedämpfte Kopf-Seek-Ticks einer Festplatte in einen Loop.
## Fester Seed, damit der Loop bei jedem Start gleich klingt.
func _add_disk_seeks(samples: PackedFloat32Array, seeks: int, seed_value: int) -> PackedFloat32Array:
	var n := samples.size()
	var tick_len := int(MIX_RATE * 0.014)
	var margin := int(MIX_RATE * 0.05)
	if n <= tick_len + margin * 2:
		return samples
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _s in range(seeks):
		var start := rng.randi_range(margin, n - tick_len - margin)
		var amp := rng.randf_range(0.012, 0.026)
		var hz := rng.randf_range(2200.0, 3400.0)
		for k in range(tick_len):
			var tk := float(k) / float(MIX_RATE)
			var env := exp(-tk * 420.0)
			samples[start + k] = clampf(samples[start + k] + sin(TAU * hz * tk) * env * amp, -0.95, 0.95)
	return samples


## Hängt die ersten zwei Samples hinten an. _make_wav setzt loop_end = n - 2, dadurch läuft
## der Loop genau über die ursprüngliche Periode, und hinter loop_end liegen die echten
## Folgesamples für den kubischen Interpolator.
func _pad_loop_wrap(samples: PackedFloat32Array) -> PackedFloat32Array:
	if samples.size() < 2:
		return samples
	samples.append(samples[0])
	samples.append(samples[1])
	return samples


# ==============================================================================
# REALISTIC TACTILE MECHANICAL INTERACTION SOUNDS
# ==============================================================================

func _gen_mouse_click() -> AudioStreamWAV:
	var count := int(MIX_RATE * 0.024)
	var s := PackedFloat32Array()
	s.resize(count)
	var prev := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 210.0)
		var w := randf_range(-1.0, 1.0)
		prev = lerpf(prev, w, 0.45)
		var snap := sin(TAU * 1850.0 * t) * 0.35 + (w - prev) * 0.65
		s[i] = clampf(snap * env * 0.48, -0.95, 0.95)
	return _make_wav(s)


func _gen_keyboard_keystroke() -> AudioStreamWAV:
	# Authentic tactile mechanical keyboard key downstroke + soft bottom-out thock
	var count := int(MIX_RATE * 0.048)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.30)
		# Crisp switch tactile bump at 0..8ms
		var click_env := exp(-t * 290.0)
		var switch_click := ((w - lp) * 0.58 + sin(TAU * 2350.0 * t) * 0.25) * click_env
		# Keycap bottom-out PBT plastic thock at 9ms
		var dt := t - 0.009
		var thock := 0.0
		if dt >= 0.0:
			var t_env := exp(-dt * 120.0)
			thock = (sin(TAU * 340.0 * dt) * 0.42 + lp * 0.48) * t_env
		s[i] = clampf((switch_click * 0.55 + thock * 0.62) * 0.52, -0.95, 0.95)
	return _make_wav(s)


func _gen_chair_sit() -> AudioStreamWAV:
	# Realistic office chair pneumatic gas-lift settle + leather cushion soft thump
	var count := int(MIX_RATE * 0.28)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.10)
		var env := sin(minf(t / 0.04, 1.0) * PI * 0.5) * exp(-t * 10.5)
		var cushion := sin(TAU * lerpf(95.0, 58.0, t / 0.28) * t) * 0.36 + lp * 0.52
		var hiss := lp * exp(-maxf(0.0, t - 0.05) * 18.0) * 0.16
		s[i] = clampf((cushion * env + hiss) * 0.48, -0.95, 0.95)
	return _make_wav(s)


func _gen_office_phone_ring() -> AudioStreamWAV:
	# Clean modern European office VoIP double-ring tone (pleasant, recognizable, non-harsh)
	var duration := 0.85
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var active := (t >= 0.02 and t <= 0.34) or (t >= 0.44 and t <= 0.78)
		if not active:
			s[i] = 0.0
			continue
		var tr := sin(TAU * 22.0 * t) * 0.16 + 0.84
		var tone := (sin(TAU * 660.0 * t) * 0.38 + sin(TAU * 830.6 * t) * 0.34 + sin(TAU * 1320.0 * t) * 0.10) * tr
		var edge := 1.0
		if t < 0.04:
			edge = (t - 0.02) / 0.02
		elif t > 0.31 and t <= 0.34:
			edge = (0.34 - t) / 0.03
		elif t >= 0.44 and t < 0.46:
			edge = (t - 0.44) / 0.02
		elif t > 0.75:
			edge = (0.78 - t) / 0.03
		s[i] = clampf(tone * clampf(edge, 0.0, 1.0) * 0.36, -0.95, 0.95)
	return _make_wav(s)


func _gen_handling_thud(base_hz: float, duration: float, rising: bool) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		var hz := lerpf(base_hz * 0.82, base_hz * 1.18, u) if rising else lerpf(base_hz * 1.15, base_hz * 0.62, u)
		var env := sin(minf(u * 9.0, 1.0) * PI * 0.5) * exp(-u * 5.2)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.16)
		var body := sin(TAU * hz * t) * 0.46 + sin(TAU * hz * 1.9 * t) * 0.15 + lp * 0.45
		s[i] = clampf(body * env * 0.56, -0.95, 0.95)
	return _make_wav(s)


func _gen_heavy_steel_place() -> AudioStreamWAV:
	var duration := 0.22
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.14)
		var env_low := exp(-u * 6.5)
		var env_ring := exp(-u * 13.0)
		var thud := sin(TAU * lerpf(115.0, 52.0, u) * t) * 0.62 * env_low
		var metal := (sin(TAU * 420.0 * t) * 0.15 + sin(TAU * 695.0 * t) * 0.09) * env_ring
		var rattle := lp * 0.40 * exp(-u * 9.0)
		s[i] = clampf((thud + metal + rattle) * 0.60, -0.95, 0.95)
	return _make_wav(s)


func _gen_server_rail_slide() -> AudioStreamWAV:
	var duration := 0.29
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, w, 0.36)
		lp2 = lerpf(lp2, lp1, 0.10)
		var scrape_env := sin(clampf(t / 0.17, 0.0, 1.0) * PI)
		var scrape := (lp1 - lp2) * 0.34 * scrape_env
		var latch := 0.0
		if t >= 0.175:
			var lt := t - 0.175
			var lenv := exp(-lt * 44.0)
			latch = (sin(TAU * 920.0 * lt) * 0.34 + sin(TAU * 2380.0 * lt) * 0.20 + w * 0.36) * lenv
		s[i] = clampf((scrape + latch) * 0.56, -0.95, 0.95)
	return _make_wav(s)


func _gen_cable_plug_snap(plugging_in: bool) -> AudioStreamWAV:
	var duration := 0.14
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.28)
		var v := 0.0
		if plugging_in:
			var e1 := exp(-t * 58.0)
			v += (sin(TAU * 260.0 * t) * 0.42 + lp * 0.44) * e1
			if t >= 0.048:
				var ct := t - 0.048
				var e2 := exp(-ct * 125.0)
				v += (sin(TAU * 2650.0 * ct) * 0.30 + sin(TAU * 1380.0 * ct) * 0.25 + (w - lp) * 0.52) * e2
		else:
			var e1 := exp(-t * 115.0)
			v += (sin(TAU * 2100.0 * t) * 0.25 + (w - lp) * 0.48) * e1
			if t >= 0.032:
				var dt := t - 0.032
				var e2 := exp(-dt * 42.0)
				v += (sin(TAU * 185.0 * dt) * 0.34 + lp * 0.38) * e2
		s[i] = clampf(v * 0.56, -0.95, 0.95)
	return _make_wav(s)


func _gen_breaker_switch_on() -> AudioStreamWAV:
	var duration := 0.22
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.24)
		var clack_env := exp(-t * 48.0)
		var clack := (sin(TAU * 165.0 * t) * 0.52 + sin(TAU * 760.0 * t) * 0.24 + lp * 0.42) * clack_env
		var hum := 0.0
		if t >= 0.04:
			var ht := t - 0.04
			hum = (sin(TAU * 50.0 * ht) * 0.16 + sin(TAU * 100.0 * ht) * 0.09) * exp(-ht * 9.0)
		s[i] = clampf((clack + hum) * 0.62, -0.95, 0.95)
	return _make_wav(s)


func _gen_breaker_trip() -> AudioStreamWAV:
	var duration := 0.42
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.34)
		var snap := (sin(TAU * 135.0 * t) * 0.58 + (w - lp) * 0.52) * exp(-t * 28.0)
		var arc := (w - lp) * 0.36 * exp(-t * 14.0) * (0.5 + 0.5 * sin(TAU * 100.0 * t))
		var spin_hz := lerpf(360.0, 58.0, clampf(t / duration, 0.0, 1.0))
		var spindown := sin(TAU * spin_hz * t) * 0.16 * exp(-t * 4.5)
		s[i] = clampf((snap + arc + spindown) * 0.64, -0.95, 0.95)
	return _make_wav(s)


func _gen_power_down_whine() -> AudioStreamWAV:
	var duration := 0.62
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var phase := 0.0
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		var hz := lerpf(420.0, 55.0, pow(u, 0.72))
		phase += TAU * hz / float(MIX_RATE)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.14)
		var env := (1.0 - u) * sin(minf(u * 14.0, 1.0) * PI * 0.5)
		s[i] = clampf((sin(phase) * 0.24 + sin(phase * 2.0) * 0.09 + lp * 0.26) * env * 0.56, -0.95, 0.95)
	return _make_wav(s)


## Kurze mechanische Klicks: je Eintrag [Zeitpunkt, Frequenz, Lautstärke, Abklingrate] plus Geräuschanteil.
func _gen_click_burst(hits: Array, duration: float, noise: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.30)
		var v := 0.0
		for h in hits:
			var dt := t - float(h[0])
			if dt >= 0.0:
				var env := exp(-dt * float(h[3]))
				v += (sin(TAU * float(h[1]) * dt) * float(h[2]) + (w - lp) * noise) * env
		s[i] = clampf(v * 0.62, -0.95, 0.95)
	return _make_wav(s)


## Kurzer Motorstoß des Akkuschraubers.
func _gen_drill_burst(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var p := float(i) / float(count)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)
		var v := sin(TAU * 420.0 * t) * 0.18 + sin(TAU * 840.0 * t) * 0.12 + sin(TAU * 1370.0 * t) * 0.07 + lp * 0.22
		s[i] = v * minf(1.0, sin(p * PI) * 2.2) * 0.75
	return _make_wav(s)


## Blech bzw. Platine gleitet aus der Führung.
func _gen_friction_slide(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var p := float(i) / float(count)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.22 + 0.16 * p)
		lp2 = lerpf(lp2, lp, 0.08)
		s[i] = (lp - lp2) * 0.50 * sin(p * PI) * (0.75 + 0.25 * sin(p * 61.0))
	return _make_wav(s)


## Zähes, leises Quetschen der Wärmeleitpaste.
func _gen_soft_squish(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var p := float(i) / float(count)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.05 + 0.05 * sin(p * 17.0))
		s[i] = lp * 1.1 * sin(p * PI)
	return _make_wav(s)


func _gen_hardware_install_ratchet() -> AudioStreamWAV:
	var duration := 0.34
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var click_times: Array[float] = [0.015, 0.075, 0.135, 0.21]
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.32)
		var v := 0.0
		for ci in range(click_times.size()):
			var dt := t - click_times[ci]
			if dt >= 0.0 and dt < 0.07:
				var f := 1420.0 + float(ci) * 230.0
				var env := exp(-dt * 95.0)
				v += (sin(TAU * f * dt) * 0.30 + (w - lp) * 0.42) * env
		if t >= 0.205:
			var st := t - 0.205
			v += sin(TAU * 640.0 * st) * 0.18 * exp(-st * 24.0)
		s[i] = clampf(v * 0.54, -0.95, 0.95)
	return _make_wav(s)


## Realistischer Schritt (Arbeitsschuh / Sneaker auf Beton-/Fliesenboden im Rechenzentrum):
## Fersen-Gewichtsimpuls + harter Sohlenkontakt + feiner Beton-Grit + Abrollen über den Ballen + kurze Raumreflexion.
func _gen_footstep(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13337 + variant * 104729
	var duration := 0.24
	var count := int(MIX_RATE * duration)
	var dry := PackedFloat32Array()
	dry.resize(count)

	var body_hz := rng.randf_range(68.0, 86.0)
	var slap_hz := rng.randf_range(520.0, 740.0)
	var tile_hz := rng.randf_range(1650.0, 2250.0)
	var toe_at := rng.randf_range(0.044, 0.062)
	var toe_gain := rng.randf_range(0.42, 0.62)
	var grit_gain := rng.randf_range(0.16, 0.28)

	var lp_sub := 0.0
	var lp_mid := 0.0
	var hp_in := 0.0
	var hp_out := 0.0
	var bp_slap := 0.0
	var bp_slap_v := 0.0
	var bp_tile := 0.0
	var bp_tile_v := 0.0
	var slap_w := TAU * slap_hz / float(MIX_RATE)
	var tile_w := TAU * tile_hz / float(MIX_RATE)
	var phase := 0.0

	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lp_sub = lerpf(lp_sub, w, 0.045)
		lp_mid = lerpf(lp_mid, w, 0.16)
		hp_out = 0.86 * (hp_out + w - hp_in)
		hp_in = w

		# Resonanter Sohlen-Kontakt (gedämpfter 2.-Ordnung-Filter für echte Fliesen-/Beton-Akustik)
		var slap_in := (lp_mid - lp_sub) * 1.6
		bp_slap_v += (slap_in - bp_slap - bp_slap_v * 0.52) * slap_w
		bp_slap += bp_slap_v * slap_w

		var tile_in := hp_out * 0.85
		bp_tile_v += (tile_in - bp_tile - bp_tile_v * 0.42) * tile_w
		bp_tile += bp_tile_v * tile_w

		# 1. Fersen-Gewichtsübertragung (dumpfer Bodenimpuls ohne künstlichen Sinus-Ton)
		phase += TAU * body_hz * (1.0 - 0.40 * minf(t / 0.035, 1.0)) / float(MIX_RATE)
		var heel_att := minf(t / 0.0022, 1.0)
		var heel_weight := (lp_sub * 3.8 + sin(phase) * 0.14) * heel_att * exp(-t * 48.0)
		var heel_slap := bp_slap * 1.45 * heel_att * exp(-t * 95.0)
		var heel_click := bp_tile * 0.65 * minf(t / 0.001, 1.0) * exp(-t * 210.0)
		var heel_grit := hp_out * grit_gain * 0.55 * heel_att * exp(-t * 85.0)

		# 2. Abrollen über den Fußballen + leichtes Gummi-Schleifen
		var toe := 0.0
		if t >= toe_at:
			var tt := t - toe_at
			var ta := minf(tt / 0.004, 1.0)
			var toe_body := lp_sub * 2.4 * ta * exp(-tt * 55.0)
			var toe_slap := bp_slap * 0.95 * ta * exp(-tt * 110.0)
			var scuff := hp_out * grit_gain * 0.48 * sin(minf(tt / 0.055, 1.0) * PI) * exp(-tt * 28.0)
			toe = (toe_body + toe_slap + scuff) * toe_gain

		dry[i] = heel_weight + heel_slap + heel_click + heel_grit + toe

	# Kurze Serverraum-Erstreflexionen (Betonboden + Wände bei 11 ms & 24 ms) für räumliche Tiefe
	var s := PackedFloat32Array()
	s.resize(count)
	var d1 := int(MIX_RATE * 0.011)
	var d2 := int(MIX_RATE * 0.024)
	var ref_lp := 0.0
	for i in range(count):
		var refl := 0.0
		if i >= d1:
			refl += dry[i - d1] * 0.16
		if i >= d2:
			refl += dry[i - d2] * 0.08
		ref_lp = lerpf(ref_lp, refl, 0.35)
		s[i] = dry[i] + ref_lp

	s = _normalize_peak(s, 0.72)
	return _make_wav(s)


## Realistischer Feuerlöscher-Start: metallischer Griff-Klick + plötzlicher Hochdruck-CO2/Pulver-Stoß aus der Düse.
func _gen_extinguisher_burst() -> AudioStreamWAV:
	var duration := 0.36
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var hp_in := 0.0
	var hp_out := 0.0
	var lp_roar := 0.0
	var lp_mid := 0.0
	var bp1 := 0.0
	var bp1_v := 0.0
	var w1 := TAU * 2100.0 / float(MIX_RATE)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var w := randf_range(-1.0, 1.0)
		hp_out = 0.91 * (hp_out + w - hp_in)
		hp_in = w
		lp_roar = lerpf(lp_roar, w, 0.055)
		lp_mid = lerpf(lp_mid, w, 0.28)
		# Konische Löschdüsen-Resonanz (charakteristisches Druckgas-Fauchen)
		bp1_v += ((lp_mid - lp_roar) - bp1 - bp1_v * 0.36) * w1
		bp1 += bp1_v * w1
		# Metallisches Auslösehebel-Klicken (0..12 ms)
		var latch := (sin(TAU * 2450.0 * t) * 0.45 + sin(TAU * 4180.0 * t) * 0.25 + hp_out * 0.4) * exp(-t * 240.0)
		# Druckstoß aus Tank & Schlauch (steigt in 16 ms steil an)
		var blast_env := minf(t / 0.016, 1.0) * exp(-t * 6.5)
		var thump := sin(TAU * 118.0 * t) * exp(-t * 38.0) * 0.32
		var jet := (hp_out * 0.85 + bp1 * 1.45 + lp_roar * 2.1) * blast_env
		s[i] = latch * 0.45 + thump + jet
	s = _normalize_peak(s, 0.78)
	return _make_wav(s)


func _normalize_peak(samples: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	var out := samples.duplicate()
	if peak <= 0.0001:
		return out
	var k := target / peak
	for i in range(out.size()):
		out[i] = clampf(out[i] * k, -0.95, 0.95)
	return out


func _gen_sliding_door() -> AudioStreamWAV:
	var duration := 0.46
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		var w := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, w, 0.24)
		lp2 = lerpf(lp2, lp1, 0.06)
		var env := sin(u * PI)
		var roll := (lp1 - lp2) * 0.34 + lp2 * 0.40
		var clunk := 0.0
		if t > 0.37:
			var ct := t - 0.37
			clunk = (sin(TAU * 130.0 * ct) * 0.52 + lp1 * 0.28) * exp(-ct * 35.0)
		s[i] = clampf((roll * env + clunk) * 0.48, -0.95, 0.95)
	return _make_wav(s)


func _gen_soft_thud_buzz() -> AudioStreamWAV:
	var duration := 0.17
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		var env := sin(minf(u * 12.0, 1.0) * PI * 0.5) * exp(-u * 5.0)
		var tone := sin(TAU * 145.0 * t) * 0.48 + sin(TAU * 218.0 * t) * 0.22
		s[i] = clampf(tone * env * 0.42, -0.95, 0.95)
	return _make_wav(s)


func _gen_soft_chime(freqs: Array, step_dur: float, amp: float) -> AudioStreamWAV:
	var total_dur := step_dur * float(freqs.size()) + 0.18
	var count := int(MIX_RATE * total_dur)
	var s := PackedFloat32Array()
	s.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var v := 0.0
		for n_idx in range(freqs.size()):
			var nt := t - float(n_idx) * step_dur
			if nt >= 0.0:
				var f := float(freqs[n_idx])
				var env := sin(minf(nt / 0.008, 1.0) * PI * 0.5) * exp(-nt * 10.5)
				v += (sin(TAU * f * nt) * 0.72 + sin(TAU * f * 2.0 * nt) * 0.18) * env
		s[i] = clampf(v * amp, -0.95, 0.95)
	return _make_wav(s)


## Weicher Akkord mit gestaffelten Einsätzen und langem Ausklang,
## wie der Anmelde- oder Abmeldeklang eines Desktop-Betriebssystems.
func _gen_os_chord(freqs: Array, step_dur: float, tail: float, amp: float) -> AudioStreamWAV:
	var total_dur := step_dur * float(freqs.size()) + tail
	var count := int(MIX_RATE * total_dur)
	var s := PackedFloat32Array()
	s.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var v := 0.0
		for n_idx in range(freqs.size()):
			var nt := t - float(n_idx) * step_dur
			if nt < 0.0:
				continue
			var f := float(freqs[n_idx])
			var env := sin(minf(nt / 0.06, 1.0) * PI * 0.5) * exp(-nt * 2.2)
			# Grundton, Oktave und eine minimal verstimmte Zweitstimme für leichtes Schweben
			v += (sin(TAU * f * nt) * 0.62 + sin(TAU * f * 2.0 * nt) * 0.14 + sin(TAU * f * 1.003 * nt) * 0.22) * env
		var fade_out := clampf((total_dur - t) / 0.25, 0.0, 1.0)
		s[i] = clampf(v * amp * fade_out, -0.95, 0.95)
	return _make_wav(s)


func _gen_filtered_noise(duration: float, amp: float, alpha: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var prev := 0.0
	for i in range(count):
		var t := float(i) / float(maxi(count - 1, 1))
		prev = lerpf(prev, randf_range(-1.0, 1.0), alpha)
		s[i] = prev * amp * sin(t * PI)
	return _make_wav(s)


## Realistischer CO2-/Pulver-Feuerlöscher-Sprühstrahl:
## Tiefes Schlauch-/Tank-Rauschen + resonantes Trichter-Fauchen (~1,8 & 3,7 kHz) + luftiges Hochdruck-Zischen.
func _gen_extinguisher_spray_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.30)
	var total := count + fade
	var raw := PackedFloat32Array()
	raw.resize(total)
	var hp_in := 0.0
	var hp_out := 0.0
	var lp_roar1 := 0.0
	var lp_roar2 := 0.0
	var lp_mid := 0.0
	var bp_horn1 := 0.0
	var bp_horn1_v := 0.0
	var bp_horn2 := 0.0
	var bp_horn2_v := 0.0
	var w_horn1 := TAU * 1850.0 / float(MIX_RATE)
	var w_horn2 := TAU * 3750.0 / float(MIX_RATE)

	for i in range(total + 4096):
		var w := randf_range(-1.0, 1.0)
		hp_out = 0.90 * (hp_out + w - hp_in)
		hp_in = w
		lp_roar1 = lerpf(lp_roar1, w, 0.055)
		lp_roar2 = lerpf(lp_roar2, lp_roar1, 0.22)
		lp_mid = lerpf(lp_mid, w, 0.36)

		# Zwei konische Düsen-Formanten (geben das typische laute Feuerlöscher-Fauchen)
		bp_horn1_v += ((lp_mid - lp_roar1) - bp_horn1 - bp_horn1_v * 0.38) * w_horn1
		bp_horn1 += bp_horn1_v * w_horn1
		bp_horn2_v += (hp_out - bp_horn2 - bp_horn2_v * 0.45) * w_horn2
		bp_horn2 += bp_horn2_v * w_horn2

		if i >= 4096:
			raw[i - 4096] = lp_roar2 * 2.3 + bp_horn1 * 1.45 + bp_horn2 * 0.85 + hp_out * 0.48

	var s := PackedFloat32Array()
	s.resize(count)
	for i in range(count):
		s[i] = raw[i]
	for i in range(fade):
		var a := float(i) / float(fade)
		s[i] = raw[i] * sin(a * PI * 0.5) + raw[count + i] * cos(a * PI * 0.5)

	# Organisches Druck-Pulsieren (ganze Perioden pro Loop für 100 % knackfreie Schleife)
	var c1 := maxf(roundf(2.4 * duration), 1.0)
	var c2 := maxf(roundf(6.4 * duration), 1.0)
	var c3 := maxf(roundf(13.6 * duration), 1.0)
	for i in range(count):
		var u := float(i) / float(count)
		var turb := 1.0 + 0.07 * sin(TAU * c1 * u) + 0.05 * sin(TAU * c2 * u + 1.4) + 0.03 * sin(TAU * c3 * u + 3.1)
		s[i] *= turb

	s = _normalize_peak(s, 0.78)
	return _make_wav(s, true)


# ==============================================================================
# 100% CLICK-FREE SEAMLESS 3D SPATIAL AMBIENCE & HARDWARE HUM LOOPS
# ==============================================================================

func _gen_server_fan_loop(duration: float) -> AudioStreamWAV:
	# Mehrere 40-mm-Hochdrehzahllüfter (~11.000-12.000 U/min, 7 Blätter): breitbandiges
	# Luftrauschen, drei leicht verstimmte Blattfrequenzen mit hörbarer Schwebung,
	# leises Netzteilbrummen und vereinzelte Festplatten-Seeks.
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var white := _make_seamless_noise(count, fade, 1.0, 1.0, 1.0, 0.0)
	var band_top := _loop_lowpass(white, 0.45)
	var band_low := _loop_lowpass(white, 0.04)
	var b1 := _loop_cycles(183.0 * 7.0, duration)
	var b2 := _loop_cycles(189.5 * 7.0, duration)
	var b3 := _loop_cycles(196.0 * 7.0, duration)
	var r1 := _loop_cycles(183.0, duration)
	var hum := _loop_cycles(100.0, duration)
	var w1 := _loop_cycles(0.7, duration)
	var w2 := _loop_cycles(1.9, duration)
	var w3 := _loop_cycles(3.3, duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var ph := TAU * float(i) / float(count)
		var wobble := 1.0 + 0.07 * sin(ph * w1 + 0.6) + 0.04 * sin(ph * w2 + 2.1)
		var turbulence := 1.0 + 0.10 * sin(ph * w3 + 4.0)
		var air := (band_top[i] - band_low[i]) * 0.9 + (white[i] - band_top[i]) * 0.10 + band_low[i] * 0.6
		var blades := (
			sin(ph * b1) * 0.050 + sin(ph * b1 * 2.0 + 0.9) * 0.018
			+ sin(ph * b2 + 1.7) * 0.045 + sin(ph * b2 * 2.0 + 2.4) * 0.016
			+ sin(ph * b3 + 3.1) * 0.040 + sin(ph * b3 * 2.0 + 0.3) * 0.014
		)
		var imbalance := sin(ph * r1) * 0.012
		var psu := sin(ph * hum) * 0.010 + sin(ph * hum * 3.0) * 0.004
		samples[i] = air * wobble * turbulence + blades * (0.85 + 0.15 * wobble) + imbalance + psu
	samples = _normalize_rms(samples, 0.06)
	samples = _add_disk_seeks(samples, maxi(1, int(duration * 1.4)), 7341)
	return _make_wav(_pad_loop_wrap(samples), true)


func _gen_cooler_fan_loop(duration: float) -> AudioStreamWAV:
	# Präzisionsklima/Chiller: zwei große Axiallüfter (~900 U/min, 5 Blätter) mit tiefem
	# Luftstrom, ein Verdichter mit Motorschlupf (48,5 Hz) und leises Kältemittelzischen.
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var white := _make_seamless_noise(count, fade, 1.0, 1.0, 1.0, 0.0)
	var low := _loop_lowpass(white, 0.012)
	var mid := _loop_lowpass(white, 0.10)
	var top := _loop_lowpass(white, 0.32)
	var f1 := _loop_cycles(14.6 * 5.0, duration)
	var f2 := _loop_cycles(15.4 * 5.0, duration)
	var comp := _loop_cycles(48.5, duration)
	var w1 := _loop_cycles(0.4, duration)
	var w2 := _loop_cycles(1.1, duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var ph := TAU * float(i) / float(count)
		var gust := 1.0 + 0.09 * sin(ph * w1 + 1.2) + 0.05 * sin(ph * w2 + 0.4)
		var air := low[i] * 1.6 + (mid[i] - low[i]) * 0.75 + (top[i] - mid[i]) * 0.10
		var blades := (
			sin(ph * f1) * 0.060 + sin(ph * f1 * 2.0 + 0.8) * 0.025 + sin(ph * f1 * 3.0 + 1.9) * 0.010
			+ sin(ph * f2 + 2.2) * 0.055 + sin(ph * f2 * 2.0 + 0.1) * 0.022
		)
		var motor := sin(ph * comp) + 0.45 * sin(ph * comp * 2.0 + 0.5) + 0.20 * sin(ph * comp * 3.0 + 1.3)
		var compressor := tanh(motor * 1.4) * 0.07
		samples[i] = (air + blades) * gust + compressor
	return _make_wav(_pad_loop_wrap(_normalize_rms(samples, 0.075)), true)


func _gen_pc_workstation_loop(duration: float) -> AudioStreamWAV:
	# Büro-Tower: zwei 120-mm-Gehäuselüfter (~900 U/min, 7 Blätter), CPU-Kühler
	# (~1.100 U/min, 9 Blätter), weiches Luftrauschen und das leise 120-Hz-Singen
	# einer 7.200er-Festplatte.
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var white := _make_seamless_noise(count, fade, 1.0, 1.0, 1.0, 0.0)
	var soft := _loop_lowpass(white, 0.06)
	var base := _loop_lowpass(white, 0.008)
	var c1 := _loop_cycles(15.0 * 7.0, duration)
	var c2 := _loop_cycles(16.2 * 7.0, duration)
	var cpu := _loop_cycles(18.3 * 9.0, duration)
	var hdd := _loop_cycles(120.0, duration)
	var w1 := _loop_cycles(0.6, duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var ph := TAU * float(i) / float(count)
		var air := (soft[i] - base[i]) * 0.8 + base[i] * 1.2
		var fans := (
			sin(ph * c1) * 0.035 + sin(ph * c1 * 2.0 + 1.1) * 0.012
			+ sin(ph * c2 + 2.0) * 0.030
			+ sin(ph * cpu + 0.7) * 0.022 + sin(ph * cpu * 2.0 + 2.6) * 0.008
		)
		var hdd_tone := sin(ph * hdd) * 0.008 + sin(ph * hdd * 2.0 + 0.5) * 0.004
		samples[i] = air * (1.0 + 0.05 * sin(ph * w1)) + fans + hdd_tone
	return _make_wav(_pad_loop_wrap(_normalize_rms(samples, 0.045)), true)


func _gen_mains_hum_loop(duration: float, base_hz: float) -> AudioStreamWAV:
	# Trafo-/Schützbrummen: Grundton mit sättigungsbedingten Obertönen, leichte
	# Lastschwankung und ein Hauch Rauschen, damit es nicht nach reinem Sinus klingt.
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var hiss := _loop_lowpass(_make_seamless_noise(count, fade, 1.0, 1.0, 1.0, 0.0), 0.05)
	var c1 := _loop_cycles(base_hz, duration)
	var cw := _loop_cycles(0.5, duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var ph := TAU * float(i) / float(count)
		var sway := 1.0 + 0.04 * sin(ph * cw)
		samples[i] = _transformer_hum(ph, c1) * 0.30 * sway + hiss[i] * 0.25
	return _make_wav(_pad_loop_wrap(_normalize_rms(samples, 0.20)), true)


func _gen_ups_loop(duration: float) -> AudioStreamWAV:
	# Online-USV: 100-Hz-Trafobrummen, kleiner 60-mm-Lüfter (~2.900 U/min, 7 Blätter)
	# und leises Spulenfiepen des Wechselrichters.
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var white := _make_seamless_noise(count, fade, 1.0, 1.0, 1.0, 0.0)
	var air_top := _loop_lowpass(white, 0.25)
	var air_low := _loop_lowpass(white, 0.03)
	var c_hum := _loop_cycles(100.0, duration)
	var fan := _loop_cycles(48.0 * 7.0, duration)
	var whine := _loop_cycles(3150.0, duration)
	var cw := _loop_cycles(1.5, duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var ph := TAU * float(i) / float(count)
		var hum := _transformer_hum(ph, c_hum) * 0.26
		var air := (air_top[i] - air_low[i]) * 0.25
		var fan_tone := sin(ph * fan) * 0.022 + sin(ph * fan * 2.0 + 1.4) * 0.008
		var coil := sin(ph * whine) * 0.006 * (0.7 + 0.3 * sin(ph * cw))
		samples[i] = hum + air + fan_tone + coil
	return _make_wav(_pad_loop_wrap(_normalize_rms(samples, 0.19)), true)


func _gen_room_hvac_loop(duration: float) -> AudioStreamWAV:
	# Ultra-warm, silky deep indoor air circulation (zero harsh hiss, zero loop pop!)
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.60)
	var noise := _make_seamless_noise(count, fade, 0.035, 0.014, 0.20, 0.92)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c1 := roundf(50.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		samples[i] = clampf(noise[i] * 0.34 + sin(TAU * c1 * t) * 0.025, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_van_horn() -> AudioStreamWAV:
	var duration := 0.56
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var in_beep := (t >= 0.02 and t <= 0.19) or (t >= 0.27 and t <= 0.50)
		if not in_beep:
			samples[i] = 0.0
			continue
		var f1 := sin(TAU * 392.0 * t)
		var f2 := sin(TAU * 493.88 * t)
		var f3 := sin(TAU * 784.0 * t) * 0.24
		var edge := 1.0
		if t < 0.04:
			edge = (t - 0.02) / 0.02
		elif t > 0.17 and t <= 0.19:
			edge = (0.19 - t) / 0.02
		elif t >= 0.27 and t < 0.29:
			edge = (t - 0.27) / 0.02
		elif t > 0.47:
			edge = (0.50 - t) / 0.03
		samples[i] = clampf((f1 * 0.40 + f2 * 0.36 + f3) * 0.46 * clampf(edge, 0.0, 1.0), -0.95, 0.95)
	return _make_wav(samples)


func _gen_van_engine_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.30)
	var noise := _make_seamless_noise(count, fade, 0.07, 0.025, 0.35, 0.65)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var cp := roundf(18.0 * duration)
	var c1 := roundf(52.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var pulse := 0.68 + 0.32 * sin(TAU * cp * t)
		var chug := (sin(TAU * c1 * t) * 0.22 + sin(TAU * c1 * 2.0 * t) * 0.12 + sin(TAU * c1 * 3.0 * t) * 0.04) * pulse
		samples[i] = clampf(chug + noise[i] * 0.18, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_cart_roll_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.25)
	var noise := _make_seamless_noise(count, fade, 0.12, 0.04, 0.40, 0.65)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var cm := roundf(9.0 * duration)
	var cc := roundf(95.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var wheel_mod := 0.74 + 0.26 * sin(TAU * cm * t)
		var clatter := sin(TAU * cc * t) * 0.045
		samples[i] = clampf((noise[i] * 0.32 + clatter) * wheel_mod, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_spark_crack() -> AudioStreamWAV:
	var duration := 0.32
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 14.0)
		var crackle := 1.0 if randf() > 0.42 else 0.15
		var raw := randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.35)
		var hi := raw - lp
		var buzz := sin(TAU * 100.0 * t) * 0.25 + sin(TAU * 1850.0 * t) * 0.18
		samples[i] = clampf((hi * 0.72 * crackle + buzz) * env, -0.95, 0.95)
	return _make_wav(samples)


func _gen_thunder_roll() -> AudioStreamWAV:
	var duration := 2.6
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var atk := clampf(t / 0.12, 0.0, 1.0)
		var dec := exp(-t * 1.15)
		var roll := 0.65 + 0.35 * sin(TAU * 2.2 * t + sin(TAU * 0.7 * t))
		var r := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, r, 0.045)
		lp2 = lerpf(lp2, lp1, 0.025)
		var sub := sin(TAU * (46.0 - t * 6.0) * t) * 0.28
		samples[i] = clampf((lp2 * 2.2 + sub) * atk * dec * roll, -0.95, 0.95)
	return _make_wav(samples)


## Mehrschichtiger realistischer Regen draussen: warmes Rosa-Rauschen + feines Prasseln + 180 weiche Tropfen-Platscher!
func _gen_rain_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.55)
	var deep_body := _make_seamless_noise(count, fade, 0.11, 0.025, 0.28, 0.86)
	var fine_spray := _make_seamless_noise(count, fade, 0.20, 0.055, 0.58, 0.42)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(count)
		var gust := 0.88 + 0.12 * sin(TAU * 2.0 * t)
		samples[i] = (deep_body[i] * 0.42 + fine_spray[i] * 0.24) * gust
	# 180 weiche, kurze Wasser-Tropfen- & Pfuetzen-Platscher (gefilterter Rausch-Impuls statt Sinus!)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4412
	for _d in range(180):
		var start := rng.randi_range(0, count - 1)
		var d_len := int(MIX_RATE * rng.randf_range(0.006, 0.018))
		var amp := rng.randf_range(0.04, 0.13)
		var lp := 0.0
		var alpha := rng.randf_range(0.22, 0.52)
		for k in range(d_len):
			var idx := (start + k) % count
			var u := float(k) / float(maxi(1, d_len))
			var env := sin(PI * u) * exp(-u * 3.8)
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), alpha)
			samples[idx] = clampf(samples[idx] + lp * env * amp, -0.95, 0.95)
	return _make_wav(samples, true)


## Gemuetliches, warmes Blech-/Industriedach-Regentrommeln (drinnen hoerbar — KEINE schrillen Sinus-Pings!)
func _gen_rain_roof_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.55)
	var warm_wash := _make_seamless_noise(count, fade, 0.085, 0.018, 0.24, 0.90)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		samples[i] = warm_wash[i] * 0.40
	var rng := RandomNumberGenerator.new()
	rng.seed = 7721
	for _d in range(150):
		var start := rng.randi_range(0, count - 1)
		var freq := rng.randf_range(135.0, 340.0)
		var amp := rng.randf_range(0.035, 0.095)
		var d_len := int(MIX_RATE * rng.randf_range(0.014, 0.032))
		var lp := 0.0
		for k in range(d_len):
			var idx := (start + k) % count
			var t := float(k) / float(MIX_RATE)
			var u := float(k) / float(maxi(1, d_len))
			var env := sin(PI * u) * exp(-u * 4.5)
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
			var thud := (sin(TAU * freq * t) * 0.55 + lp * 0.45) * env * amp
			samples[idx] = clampf(samples[idx] + thud, -0.95, 0.95)
	return _make_wav(samples, true)


## Tagsueber draussen (14 s Loop): organisches Blaetterrauschen & nur 3 entfernte, weiche Vogelrufe mit langen Pausen!
func _gen_outdoor_day_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.80)
	var leaves := _make_seamless_noise(count, fade, 0.068, 0.016, 0.26, 0.86)
	var air := _make_seamless_noise(count, fade, 0.022, 0.008, 0.16, 0.94)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(count)
		var swell := 0.65 + 0.35 * sin(TAU * 1.0 * t)
		samples[i] = leaves[i] * 0.25 * swell + air[i] * 0.16
	# Nur 3 weit entfernte, natuerliche Amsel-/Singdrossel-Phrasen ueber 14 Sek. (weich, leise, lange Pausen!)
	var calls: Array = [
		# [start_s, f_start, f_mid, f_end, dur_s, amp]
		[1.40, 2180.0, 2680.0, 2340.0, 0.24, 0.024],
		[1.72, 2450.0, 2890.0, 2220.0, 0.28, 0.020],
		[6.85, 2550.0, 2120.0, 2420.0, 0.26, 0.022],
		[11.30, 2040.0, 2620.0, 2180.0, 0.30, 0.019],
	]
	for ch in calls:
		var s0 := int(float(ch[0]) * MIX_RATE)
		var f0: float = float(ch[1])
		var fm: float = float(ch[2])
		var f1: float = float(ch[3])
		var clen := int(float(ch[4]) * MIX_RATE)
		var amp: float = float(ch[5])
		var phase := 0.0
		for k in range(clen):
			var idx := (s0 + k) % count
			var u := float(k) / float(maxi(1, clen))
			# Sanfte natuerliche Glockenhuelle (kein hartes Klicken!)
			var env := pow(sin(PI * u), 2.4)
			var f := lerpf(f0, fm, u * 2.0) if u < 0.5 else lerpf(fm, f1, (u - 0.5) * 2.0)
			f += 42.0 * sin(TAU * 14.0 * u)
			phase += TAU * f / float(MIX_RATE)
			var tone := (sin(phase) * 0.82 + sin(phase * 2.0) * 0.12) * env * amp
			samples[idx] = clampf(samples[idx] + tone, -0.95, 0.95)
	return _make_wav(samples, true)


## Nachts draussen: ruhige kuehle Nachtluft & ganz dezentes fernes Grillen-Zirpen
func _gen_outdoor_night_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.65)
	var air := _make_seamless_noise(count, fade, 0.032, 0.010, 0.16, 0.93)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(count)
		var sec := float(i) / float(MIX_RATE)
		# Dezentes fernes Grillen-Zirpen (sanft gepulst)
		var chirp_gate := clampf(sin(TAU * 0.55 * sec) * 1.8 - 0.85, 0.0, 1.0)
		var trill := 0.5 + 0.5 * sin(TAU * 22.0 * sec)
		var cricket := sin(TAU * 4120.0 * sec) * chirp_gate * trill * 0.012
		samples[i] = clampf(air[i] * 0.22 * (0.80 + 0.20 * sin(TAU * t)) + cricket, -0.95, 0.95)
	return _make_wav(samples, true)


## Dumpfes, sattes 2-MVA Notstrom-Dieselgenerator-Brummen (50 Hz + 100 Hz + leichter mechanischer Takt)
func _gen_diesel_gen_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var rumble := _make_seamless_noise(count, fade, 0.055, 0.014, 0.22, 0.92)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var f50 := roundf(50.0 * duration)
	var f100 := roundf(100.0 * duration)
	var f150 := roundf(150.0 * duration)
	var f_takt := roundf(12.5 * duration)
	for i in range(count):
		var u := float(i) / float(count)
		var mod := 0.82 + 0.18 * sin(TAU * f_takt * u)
		var hum := (sin(TAU * f50 * u) * 0.42 + sin(TAU * f100 * u) * 0.26 + sin(TAU * f150 * u) * 0.10) * mod
		samples[i] = clampf(hum * 0.55 + rumble[i] * 0.28, -0.95, 0.95)
	return _make_wav(samples, true)


## Dumpfes, leicht hohles Doppelboden-Trittgeraeusch (Halle Nord)
func _gen_step_raised_floor() -> AudioStreamWAV:
	var count := int(MIX_RATE * 0.13)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3301
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 34.0)
		var hollow := (sin(TAU * 118.0 * t) * 0.55 + sin(TAU * 245.0 * t) * 0.25) * env
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.24)
		samples[i] = clampf((hollow + lp * 0.28 * exp(-t * 48.0)) * 0.62, -0.95, 0.95)
	return _make_wav(samples)


## Leicht nasses Asphalt-Schrittgeraeusch bei Regen/Gewitter
func _gen_step_wet_asphalt() -> AudioStreamWAV:
	var count := int(MIX_RATE * 0.14)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3309
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 26.0)
		var thud := sin(TAU * 92.0 * t) * exp(-t * 42.0) * 0.35
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)
		var splash := lp * env * 0.45
		samples[i] = clampf((thud + splash) * 0.60, -0.95, 0.95)
	return _make_wav(samples)


## Sturm-Windboeen (schwellen langsam an und ab)
func _gen_wind_gust_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.65)
	var wind := _make_seamless_noise(count, fade, 0.095, 0.018, 0.35, 0.86)
	var howl := _make_seamless_noise(count, fade, 0.16, 0.045, 0.50, 0.72)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(count)
		var gust := 0.55 + 0.45 * sin(TAU * t)
		samples[i] = clampf((wind[i] * 0.45 + howl[i] * 0.22) * gust, -0.95, 0.95)
	return _make_wav(samples, true)


## 3D-Fahrzeug-Loop fuer vorbeifahrende Autos (PKW/SUV/Van vs. 40t-LKW Diesel + Reifenabrollgeraeusch!)
func _gen_car_pass_loop(duration: float, is_truck: bool) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var tire := _make_seamless_noise(count, fade, 0.18 if not is_truck else 0.12, 0.045, 0.48, 0.62)
	var rumble := _make_seamless_noise(count, fade, 0.045, 0.015, 0.25, 0.88)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var f_base := roundf((44.0 if is_truck else 86.0) * duration)
	var f_pulse := roundf((16.0 if is_truck else 28.0) * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var ph := TAU * t
		var pulse := (0.72 + 0.28 * sin(ph * f_pulse)) if is_truck else (0.86 + 0.14 * sin(ph * f_pulse))
		var eng := (
			sin(ph * f_base) * (0.34 if is_truck else 0.22)
			+ sin(ph * f_base * 2.0 + 0.5) * (0.20 if is_truck else 0.14)
			+ sin(ph * f_base * 3.0 + 1.1) * (0.10 if is_truck else 0.06)
		) * pulse
		var road := tire[i] * (0.38 if is_truck else 0.46) + rumble[i] * (0.30 if is_truck else 0.16)
		samples[i] = clampf(eng + road, -0.95, 0.95)
	return _make_wav(samples, true)


## Nasses Reifen-Zischen auf regenfeuchtem Asphalt
func _gen_tire_wet_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var spray := _make_seamless_noise(count, fade, 0.48, 0.18, 0.72, 0.30)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		samples[i] = clampf(spray[i] * 0.56, -0.95, 0.95)
	return _make_wav(samples, true)


## Elektrischer Kettenantrieb + Laufrollen fuer das Sektional-Garagentor
func _gen_garage_door_motor_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.25)
	var rattle := _make_seamless_noise(count, fade, 0.15, 0.04, 0.42, 0.68)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c_hum := roundf(100.0 * duration)
	var c_gear := roundf(240.0 * duration)
	var c_chain := roundf(14.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var ph := TAU * t
		var motor := sin(ph * c_hum) * 0.18 + sin(ph * c_gear) * 0.09
		var chain := (0.70 + 0.30 * sin(ph * c_chain)) * rattle[i] * 0.34
		samples[i] = clampf(motor + chain, -0.95, 0.95)
	return _make_wav(samples, true)


## Authentisches LKW-/Lieferwagen-Rueckfahrpiepen (europaeischer 1240-Hz-Piezo-Intervallton)
func _gen_backup_beep() -> AudioStreamWAV:
	var duration := 0.34
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		if t > 0.26:
			samples[i] = 0.0
			continue
		var env := clampf(t / 0.008, 0.0, 1.0) * clampf((0.26 - t) / 0.012, 0.0, 1.0)
		var s := sin(TAU * 1240.0 * t) * 0.55 + sin(TAU * 2480.0 * t) * 0.14
		samples[i] = clampf(s * env * 0.52, -0.95, 0.95)
	return _make_wav(samples)


## Druckluft-Bremszischen ("pssshhh!") fuer 7,5t/18t/40t LKW beim Anhalten
func _gen_air_brake_hiss() -> AudioStreamWAV:
	var duration := 0.58
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var atk := clampf(t / 0.025, 0.0, 1.0)
		var dec := exp(-t * 5.8)
		var raw := randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.22)
		var hi := raw - lp * 0.75
		samples[i] = clampf(hi * atk * dec * 0.65, -0.95, 0.95)
	return _make_wav(samples)


## Fernes weiches Autobahn- & Industriegebiets-Rauschen (tiefe Horizon-Kulisse)
func _gen_distant_highway_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.65)
	var wash := _make_seamless_noise(count, fade, 0.038, 0.011, 0.22, 0.92)
	var air := _make_seamless_noise(count, fade, 0.085, 0.025, 0.34, 0.84)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(count)
		var swell := 0.78 + 0.22 * sin(TAU * t + 0.4 * sin(TAU * 2.0 * t))
		samples[i] = clampf((wash[i] * 0.44 + air[i] * 0.18) * swell, -0.95, 0.95)
	return _make_wav(samples, true)


## Leiser, tief gefilterter Linienflugzeug-Ueberflug in grosser Hoehe (5.2 s)
func _gen_distant_jet_pass() -> AudioStreamWAV:
	var duration := 5.2
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var u := float(i) / float(count)
		var env := sin(PI * u)
		env = env * env
		var raw := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, raw, 0.055)
		lp2 = lerpf(lp2, lp1, 0.032)
		var turbine := sin(TAU * (138.0 - 24.0 * u) * (float(i) / float(MIX_RATE))) * 0.06
		samples[i] = clampf((lp2 * 2.1 + turbine) * env * 0.48, -0.95, 0.95)
	return _make_wav(samples)


## Gedaempftes fernes Gabelstapler-Piepen vom Nachbar-Logistikhof
func _gen_distant_yard_beep() -> AudioStreamWAV:
	var duration := 0.28
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		if t > 0.20:
			samples[i] = 0.0
			continue
		var env := clampf(t / 0.015, 0.0, 1.0) * clampf((0.20 - t) / 0.025, 0.0, 1.0)
		samples[i] = clampf(sin(TAU * 980.0 * t) * env * 0.24, -0.95, 0.95)
	return _make_wav(samples)
