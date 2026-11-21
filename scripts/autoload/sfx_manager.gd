extends Node
## v1.0 Realistic Click-Free 44.1 kHz Audio Engine (16-bit PCM).
## Zero loop clicks/pops (warmed-up filters, equal-power circular crossfades, integer-cycle harmonics,
## safe loop_end = count - 1). Includes tactile mechanical keyboard typing, VoIP phone ringing,
## support ticket chime, chair sit-down sound, RJ45/IEC plugs, 1U rails, footsteps & 3D hardware hums.

const MIX_RATE := 44100
# Erzeugte Klänge werden hier gespeichert, damit nur der erste Start rechnen muss (~870 ms gemessen).
const SFX_CACHE_DIR := "user://sfx_cache"
# Erhöhen, wenn sich ein Generator oder seine Parameter ändern, sonst bleiben die alten Klänge im Cache.
const SFX_CACHE_VERSION := 1

var _sounds: Dictionary = {}
var _loops: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _room_amb_player: AudioStreamPlayer


func _ready() -> void:
	for _i in range(16):
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_pool.append(player)

	if not _load_sound_cache():
		_generate_sounds()
		_save_sound_cache()
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
	_sounds["footstep"] = _gen_footstep()
	_sounds["foam"] = _gen_filtered_noise(0.16, 0.22, 0.30)
	_sounds["van_horn"] = _gen_van_horn()
	_sounds["van_door"] = _gen_sliding_door()
	_sounds["cart_load"] = _gen_handling_thud(185.0, 0.10, false)

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
	_loops["server_fan"] = _gen_server_fan_loop(2.0)
	_loops["cooler_fan"] = _gen_cooler_fan_loop(2.0)
	_loops["pc_hum"] = _gen_pc_workstation_loop(2.0)
	_loops["breaker_hum"] = _gen_mains_hum_loop(2.0, 50.0)
	_loops["ups_hum"] = _gen_mains_hum_loop(2.0, 100.0)
	_loops["room_ambience"] = _gen_room_hvac_loop(3.0)
	_loops["van_engine"] = _gen_van_engine_loop(2.0)
	_loops["cart_roll"] = _gen_cart_roll_loop(2.0)


func _setup_room_ambience() -> void:
	# Very subtle warm room presence (ONLY plays in-game, completely quiet in Main Menu!)
	_room_amb_player = AudioStreamPlayer.new()
	_room_amb_player.stream = _loops["room_ambience"]
	_room_amb_player.volume_db = -80.0
	add_child(_room_amb_player)
	SettingsManager.settings_changed.connect(_update_room_ambience_volume)


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


func _process(_delta: float) -> void:
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
		# Ultra-gentle warm room tone (no harsh static hiss!)
		_room_amb_player.volume_db = linear_to_db(gain) - 33.0


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


func get_loop_stream(loop_name: String) -> AudioStreamWAV:
	if _loops.has(loop_name):
		return _loops[loop_name] as AudioStreamWAV
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


func _gen_footstep() -> AudioStreamWAV:
	var duration := 0.095
	var count := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var u := t / duration
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)
		var env := sin(minf(u * 10.0, 1.0) * PI * 0.5) * exp(-u * 6.5)
		var heel := sin(TAU * lerpf(135.0, 62.0, u) * t) * 0.54 + lp * 0.48
		s[i] = clampf(heel * env * 0.46, -0.95, 0.95)
	return _make_wav(s)


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


# ==============================================================================
# 100% CLICK-FREE SEAMLESS 3D SPATIAL AMBIENCE & HARDWARE HUM LOOPS
# ==============================================================================

func _gen_server_fan_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var noise := _make_seamless_noise(count, fade, 0.22, 0.06, 0.28, 0.72)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c1 := roundf(100.0 * duration)
	var c2 := roundf(200.0 * duration)
	var c3 := roundf(300.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var hum := sin(TAU * c1 * t) * 0.055 + sin(TAU * c2 * t) * 0.035 + sin(TAU * c3 * t) * 0.018
		samples[i] = clampf(noise[i] * 0.36 + hum, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_cooler_fan_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var noise := _make_seamless_noise(count, fade, 0.08, 0.03, 0.38, 0.80)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c1 := roundf(50.0 * duration)
	var c2 := roundf(100.0 * duration)
	var c3 := roundf(150.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var comp := sin(TAU * c1 * t) * 0.085 + sin(TAU * c2 * t) * 0.042 + sin(TAU * c3 * t) * 0.018
		samples[i] = clampf(noise[i] * 0.38 + comp, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_pc_workstation_loop(duration: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var fade := int(MIX_RATE * 0.35)
	var noise := _make_seamless_noise(count, fade, 0.07, 0.025, 0.30, 0.72)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c1 := roundf(90.0 * duration)
	var c2 := roundf(180.0 * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var hum := sin(TAU * c1 * t) * 0.040 + sin(TAU * c2 * t) * 0.018
		samples[i] = clampf(noise[i] * 0.25 + hum, -0.95, 0.95)
	return _make_wav(samples, true)


func _gen_mains_hum_loop(duration: float, base_hz: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var c1 := roundf(base_hz * duration)
	for i in range(count):
		var t := float(i) / float(count)
		var h := (
			sin(TAU * c1 * t) * 0.26
			+ sin(TAU * c1 * 2.0 * t) * 0.14
			+ sin(TAU * c1 * 3.0 * t) * 0.06
		)
		samples[i] = clampf(h, -0.95, 0.95)
	return _make_wav(samples, true)


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
