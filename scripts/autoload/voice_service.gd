extends Node
## Micrófono (grabación + transcripción remota) y voces de los personajes
## (TTS del sistema Android, TTS remoto opcional, o simulación sin voz).
## El micrófono SOLO graba mientras el jugador lo activa explícitamente.

signal mic_state_changed(state: String)  # ready | listening | transcribing | processing | speaking | error | offline
signal transcription_ready(text: String)
signal transcription_failed(reason: String)
signal speech_started(speaker: String)
signal speech_finished(speaker: String)
signal permission_result(granted: bool)

const MAX_RECORD_S := 20.0
const SILENCE_STOP_S := 1.6
const SPEECH_LEVEL := 0.06

var mic_state := "ready"
var _mic_player: AudioStreamPlayer
var _mic_spectrum: AudioEffectSpectrumAnalyzerInstance
var _record_time := 0.0
var _silence_time := 0.0
var _heard_speech := false
var mic_level := 0.0

var _tts_voices: Array = []
var _utterance_id := 0
var _speaking := false
var _speak_end_time := 0.0
var _speak_mode := ""
var _boundary_pulse := 0.0
var _remote_player: AudioStreamPlayer
var current_speaker := ""
var _speech_token := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	var mic_idx := AudioServer.get_bus_index("Mic")
	var an := AudioEffectSpectrumAnalyzer.new()
	an.buffer_length = 0.1
	AudioServer.add_bus_effect(mic_idx, an)
	_mic_spectrum = AudioServer.get_bus_effect_instance(mic_idx, AudioServer.get_bus_effect_count(mic_idx) - 1) as AudioEffectSpectrumAnalyzerInstance
	_remote_player = AudioStreamPlayer.new()
	_remote_player.bus = "Voice"
	add_child(_remote_player)
	_remote_player.finished.connect(_on_speech_done.bind(-1))
	_init_tts()
	if get_tree().has_signal("on_request_permissions_result"):
		get_tree().on_request_permissions_result.connect(_on_permission)


# ------------------------------------------------------------------ TTS

func _init_tts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_tts_voices = DisplayServer.tts_get_voices_for_language("es")
	if _tts_voices.is_empty():
		_tts_voices = DisplayServer.tts_get_voices_for_language("spa")
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_end)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_tts_end)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, _on_tts_boundary)


func system_tts_available() -> bool:
	return not _tts_voices.is_empty()


func tts_status_text() -> String:
	match str(Settings.get_value("tts_mode")):
		"off":
			return "Voces desactivadas (solo subtítulos)"
		"remote":
			return "Voz remota (servidor IA)" if Settings.is_ai_configured() else "Voz remota sin servidor: se usará la del sistema"
	if system_tts_available():
		return "Voz del sistema (%d voces en español)" % _tts_voices.size()
	return "Este dispositivo no ofrece voces en español: solo subtítulos"


## Elige una voz del sistema estable por personaje.
func _pick_voice(profile: Dictionary) -> String:
	if _tts_voices.is_empty():
		return ""
	var want_f: bool = profile.get("gender", "m") == "f"
	var candidates := []
	for v in _tts_voices:
		var n := str(v.get("name", "")).to_lower() + " " + str(v.get("id", "")).to_lower()
		var is_f := "female" in n or "mujer" in n or "-f" in n
		var is_m := "male" in n and not "female" in n
		if (want_f and is_f) or (not want_f and is_m):
			candidates.append(v)
	if candidates.is_empty():
		candidates = _tts_voices
	var h := absi(hash(str(profile.get("id", ""))))
	return str(candidates[h % candidates.size()]["id"])


## Habla un texto con el perfil de voz del personaje. Devuelve inmediatamente.
func speak(text: String, profile: Dictionary) -> void:
	stop_speaking()
	_speech_token += 1
	var token := _speech_token
	current_speaker = str(profile.get("id", ""))
	_speaking = true
	_set_mic_state("speaking")
	speech_started.emit(current_speaker)
	Audio.duck_music(true)
	var rate := clampf(float(profile.get("rate", 1.0)) * float(Settings.get_value("voice_speed")), 0.5, 2.0)
	var mode := str(Settings.get_value("tts_mode"))
	if mode == "remote" and AI.remote_available():
		_speak_mode = "remote"
		var r := await AI.synthesize(text, str(profile.get("remote_voice", "alloy")), str(profile.get("instructions", "")))
		if token != _speech_token:
			return
		if r["ok"]:
			var mp3 := AudioStreamMP3.new()
			mp3.data = r["bytes"]
			if mp3.get_length() > 0.05:
				_remote_player.stream = mp3
				_remote_player.pitch_scale = 1.0
				_remote_player.play()
				_speak_end_time = Time.get_ticks_msec() / 1000.0 + mp3.get_length() + 0.5
				return
		mode = "system"
	if mode != "off" and system_tts_available():
		_speak_mode = "system"
		_utterance_id += 1
		var pitch := clampf(float(profile.get("pitch", 1.0)), 0.5, 2.0)
		var vol := int(clampf(float(Settings.get_value("vol_voice")) * float(Settings.get_value("vol_master")), 0.0, 1.0) * 100.0)
		DisplayServer.tts_speak(text, _pick_voice(profile), vol, pitch, rate, _utterance_id, true)
		# Respaldo por si el sistema no informa del final
		_speak_end_time = Time.get_ticks_msec() / 1000.0 + estimate_duration(text, rate) * 1.8 + 2.0
		return
	# Sin voz: simulamos la duración para animar la boca y los subtítulos
	_speak_mode = "silent"
	_speak_end_time = Time.get_ticks_msec() / 1000.0 + estimate_duration(text, rate)


func estimate_duration(text: String, rate := 1.0) -> float:
	return clampf(text.length() / (14.5 * rate), 0.8, 14.0)


func stop_speaking() -> void:
	if not _speaking:
		return
	_speech_token += 1
	if _speak_mode == "system" and DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
	_remote_player.stop()
	_on_speech_done(-2)


func is_speaking() -> bool:
	return _speaking


func _on_tts_end(id: int) -> void:
	if id == _utterance_id:
		call_deferred("_on_speech_done", id)


func _on_tts_boundary(_pos: int, id: int) -> void:
	if id == _utterance_id:
		_boundary_pulse = 1.0


func _on_speech_done(_id: int) -> void:
	if not _speaking:
		return
	_speaking = false
	Audio.duck_music(false)
	var who := current_speaker
	if mic_state == "speaking":
		_set_mic_state("ready")
	speech_finished.emit(who)


## Apertura de boca 0..1 para el personaje que habla.
func mouth_open(t: float) -> float:
	if not _speaking:
		return 0.0
	match _speak_mode:
		"remote":
			return Audio.voice_level()
		"system":
			_boundary_pulse = maxf(0.0, _boundary_pulse - get_process_delta_time() * 4.0)
			return clampf(0.25 + 0.45 * absf(sin(t * 13.0)) * (0.6 + 0.4 * sin(t * 3.1)) + _boundary_pulse * 0.3, 0.0, 1.0)
	return clampf(0.2 + 0.6 * absf(sin(t * 12.0)) * (0.5 + 0.5 * sin(t * 2.7)), 0.0, 1.0)


# ------------------------------------------------------------------ Micrófono

func stt_available() -> bool:
	return str(Settings.get_value("stt_mode")) == "remote" and Settings.is_ai_configured() and AI.remote_available()


func request_mic_permission() -> void:
	if OS.get_name() != "Android":
		permission_result.emit(true)
		return
	var granted := OS.get_granted_permissions()
	if "android.permission.RECORD_AUDIO" in granted:
		permission_result.emit(true)
		return
	OS.request_permission("android.permission.RECORD_AUDIO")


func has_mic_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	return "android.permission.RECORD_AUDIO" in OS.get_granted_permissions()


func _on_permission(permission: String, granted: bool) -> void:
	if "RECORD_AUDIO" in permission:
		permission_result.emit(granted)


func start_listening() -> bool:
	if mic_state == "listening":
		return true
	if not stt_available():
		_set_mic_state("offline")
		return false
	if not has_mic_permission():
		request_mic_permission()
		_set_mic_state("error")
		transcription_failed.emit("Necesito permiso de micrófono. Acéptalo y vuelve a pulsar.")
		return false
	stop_speaking()
	_record_time = 0.0
	_silence_time = 0.0
	_heard_speech = false
	if not _mic_player.playing:
		_mic_player.play()
	Audio.record_effect.set_recording_active(true)
	_set_mic_state("listening")
	return true


func cancel_listening() -> void:
	if mic_state != "listening":
		return
	Audio.record_effect.set_recording_active(false)
	_mic_player.stop()
	_set_mic_state("ready")


func stop_listening() -> void:
	if mic_state != "listening":
		return
	var rec: AudioStreamWAV = Audio.record_effect.get_recording()
	Audio.record_effect.set_recording_active(false)
	_mic_player.stop()
	if rec == null:
		_fail("No se grabó audio")
		return
	var pcm := WavUtil.to_mono_16k_pcm(rec)
	if WavUtil.duration_s(pcm) < 0.4 or WavUtil.peak(pcm) < 0.015:
		_fail("No te he oído. Acerca el micrófono e inténtalo otra vez.")
		return
	_set_mic_state("transcribing")
	var r := await AI.transcribe(WavUtil.wrap_wav(pcm, 16000), Loc.lang)
	if mic_state != "transcribing":
		return  # cancelado mientras tanto
	if r["ok"]:
		_set_mic_state("processing")
		Save.stat_add("voice_turns")
		transcription_ready.emit(r["text"])
	else:
		_fail(str(r.get("error", "Error de transcripción")))


func _fail(reason: String) -> void:
	_set_mic_state("error")
	transcription_failed.emit(reason)


func set_processing(on: bool) -> void:
	if on:
		_set_mic_state("processing")
	elif mic_state == "processing":
		_set_mic_state("ready")


func reset_state() -> void:
	if mic_state in ["error", "offline", "processing"]:
		_set_mic_state("ready")


func _set_mic_state(s: String) -> void:
	if s != mic_state:
		mic_state = s
		mic_state_changed.emit(s)


func _process(delta: float) -> void:
	if _speaking and Time.get_ticks_msec() / 1000.0 > _speak_end_time and not _remote_player.playing:
		if _speak_mode != "system" or not DisplayServer.tts_is_speaking():
			_on_speech_done(-3)
	if mic_state != "listening":
		mic_level = lerpf(mic_level, 0.0, delta * 8.0)
		return
	_record_time += delta
	var m := Vector2.ZERO
	if _mic_spectrum:
		m = _mic_spectrum.get_magnitude_for_frequency_range(100.0, 4000.0)
	mic_level = clampf((m.x + m.y) * 25.0, 0.0, 1.0)
	if mic_level > SPEECH_LEVEL:
		_heard_speech = true
		_silence_time = 0.0
	else:
		_silence_time += delta
	if _record_time >= MAX_RECORD_S:
		stop_listening()
	elif Settings.get_value("vad_auto_stop") and _heard_speech and _silence_time >= SILENCE_STOP_S:
		stop_listening()


func _notification(what: int) -> void:
	# Si la app pasa a segundo plano (p. ej. entra una llamada real), se suelta el micrófono
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mic_state == "listening":
			cancel_listening()
		stop_speaking()
