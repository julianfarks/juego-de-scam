extends Node
## Buses de audio (Master/Music/SFX/Voice/Ambient/Mic), efectos procedurales con
## variación anti-repetición, música con fundidos y ambiente de oficina.

const BUSES := ["Music", "SFX", "Voice", "Ambient", "Mic"]
const POOL_SIZE := 10

var sounds: Dictionary = {}
var music_tracks: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _last_played: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _ambient_timer := 0.0
var ambient_on := false
var _wanted_music := ""
var _music_thread: Thread
var spectrum: AudioEffectSpectrumAnalyzerInstance
var capture_effect: AudioEffectCapture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_sounds()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = "Music"
	add_child(_music_player_b)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.stream = sounds["hum"]
	add_child(_ambient_player)
	apply_volumes()
	Settings.changed.connect(func(k: String) -> void:
		if k.begins_with("vol_"):
			apply_volumes())
	# La música se genera en segundo plano para no retrasar el arranque.
	_music_thread = Thread.new()
	_music_thread.start(_generate_music)


func _generate_music() -> void:
	var office := Synth.music_loop("office")
	var menu := Synth.music_loop("menu")
	call_deferred("_music_ready", office, menu)


func _music_ready(office: AudioStreamWAV, menu: AudioStreamWAV) -> void:
	music_tracks["office"] = office
	music_tracks["menu"] = menu
	if _music_thread:
		_music_thread.wait_to_finish()
		_music_thread = null
	if _wanted_music != "":
		play_music(_wanted_music)


func _exit_tree() -> void:
	if _music_thread and _music_thread.is_started():
		_music_thread.wait_to_finish()


func _setup_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")
	var voice_idx := AudioServer.get_bus_index("Voice")
	var an := AudioEffectSpectrumAnalyzer.new()
	an.buffer_length = 0.1
	an.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
	AudioServer.add_bus_effect(voice_idx, an)
	spectrum = AudioServer.get_bus_effect_instance(voice_idx, 0) as AudioEffectSpectrumAnalyzerInstance
	var mic_idx := AudioServer.get_bus_index("Mic")
	capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 3.0
	AudioServer.add_bus_effect(mic_idx, capture_effect)
	# Se captura sin devolver el sonido al altavoz (volumen mínimo, sin silenciar el bus)
	AudioServer.set_bus_volume_db(mic_idx, -80.0)


func _build_sounds() -> void:
	sounds["click"] = Synth.tone([1500.0], 0.05, 0.001, 0.015, "sine", 0.4)
	sounds["tap"] = Synth.tone([900.0, 1350.0], 0.08, 0.001, 0.03, "tri", 0.35)
	sounds["ding"] = Synth.tone([1320.0, 1760.0], 0.8, 0.002, 0.25, "sine", 0.4)
	sounds["notify"] = Synth.tone([988.0, 1319.0], 0.4, 0.002, 0.12, "tri", 0.35)
	sounds["error"] = Synth.tone([180.0, 186.0], 0.35, 0.005, 0.25, "square", 0.25)
	sounds["ring"] = Synth.phone_ring()
	sounds["pickup"] = Synth.noise_burst(0.12, 0.03, 0.6, 0.5, 2)
	sounds["hangup"] = Synth.tone([480.0, 620.0], 0.6, 0.005, 0.5, "square", 0.18)
	sounds["cash"] = Synth.cash_register()
	sounds["coin"] = Synth.tone([988.0, 1976.0], 0.25, 0.001, 0.08, "square", 0.2)
	sounds["wahwah"] = Synth.wah_wah()
	sounds["boing"] = Synth.sweep(180.0, 700.0, 0.35)
	sounds["whoosh"] = Synth.noise_burst(0.4, 0.15, 0.08, 0.5, 9)
	sounds["applause"] = Synth.applause()
	sounds["laugh"] = Synth.laugh()
	sounds["step"] = Synth.tone([90.0, 70.0], 0.09, 0.001, 0.03, "sine", 0.4)
	sounds["hum"] = Synth.brown_noise(4.0, 0.18)
	sounds["levelup"] = Synth.sweep(400.0, 1200.0, 0.5, "saw", 0.25)
	sounds["fail"] = Synth.sweep(500.0, 120.0, 0.6, "saw", 0.25)
	for i in 4:
		sounds["type%d" % i] = Synth.noise_burst(0.04, 0.008 + i * 0.002, 0.3 + i * 0.1, 0.35, 20 + i)
	sounds["far_ring"] = Synth.tone([440.0, 480.0], 0.5, 0.02, 0.3, "sine", 0.08)


func apply_volumes() -> void:
	_set_bus_lin("Master", Settings.get_value("vol_master"))
	_set_bus_lin("Music", Settings.get_value("vol_music"))
	_set_bus_lin("SFX", Settings.get_value("vol_sfx"))
	_set_bus_lin("Ambient", float(Settings.get_value("vol_sfx")) * 0.7)
	_set_bus_lin("Voice", Settings.get_value("vol_voice"))


func _set_bus_lin(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	v = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


## Reproduce un efecto. Evita repetir el mismo sonido demasiado seguido y varía el tono.
func play(name: String, volume_db := 0.0, pitch_var := 0.06, min_interval := 0.04) -> void:
	if name == "type":
		name = "type%d" % (randi() % 4)
	if not sounds.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(name, -10.0)) < min_interval:
		return
	_last_played[name] = now
	var p := _free_player()
	p.stream = sounds[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func stop(name: String) -> void:
	if not sounds.has(name):
		return
	for p in _pool:
		if p.playing and p.stream == sounds[name]:
			p.stop()


func is_playing(name: String) -> bool:
	for p in _pool:
		if p.playing and p.stream == sounds.get(name):
			return true
	return false


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[randi() % _pool.size()]


func play_music(track: String) -> void:
	_wanted_music = track
	if not music_tracks.has(track):
		return
	if _music_player.stream == music_tracks[track] and _music_player.playing:
		return
	var old := _music_player
	_music_player = _music_player_b
	_music_player_b = old
	_music_player.stream = music_tracks[track]
	_music_player.volume_db = -30.0
	_music_player.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_player, "volume_db", 0.0, 1.2)
	tw.tween_property(old, "volume_db", -40.0, 1.2)
	tw.chain().tween_callback(old.stop)


func duck_music(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -12.0 if on else 0.0, 0.4)


func set_ambient(on: bool) -> void:
	ambient_on = on
	if on and not _ambient_player.playing:
		_ambient_player.play()
	elif not on:
		_ambient_player.stop()


func _process(delta: float) -> void:
	if not ambient_on:
		return
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		_ambient_timer = randf_range(2.5, 7.0)
		var r := randf()
		if r < 0.45:
			for i in randi_range(3, 9):
				get_tree().create_timer(i * randf_range(0.07, 0.13)).timeout.connect(play.bind("type", -14.0, 0.15, 0.0))
		elif r < 0.65:
			play("far_ring", -6.0, 0.03, 1.0)


## Amplitud actual del bus de voz (0..1) para animar bocas con audio remoto.
func voice_level() -> float:
	if spectrum == null:
		return 0.0
	var m := spectrum.get_magnitude_for_frequency_range(150.0, 3500.0)
	return clampf((m.x + m.y) * 18.0, 0.0, 1.0)
