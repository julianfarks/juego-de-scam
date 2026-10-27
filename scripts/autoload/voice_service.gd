extends Node
## Voz LOCAL en español, sin servidores:
##  - Micrófono → detección de voz (Silero VAD) → transcripción (Whisper) en el móvil.
##  - Voces de los clientes con Kokoro (síntesis neuronal en el móvil), con tono
##    distinto por personaje. Si los modelos de voz no están, se usa la voz del sistema
##    Android y la interfaz lo indica (no se presenta como voz generativa).
## El micrófono SOLO graba mientras el jugador lo activa.

signal mic_state_changed(state: String)  # ready | listening | transcribing | processing | speaking | error | offline
signal transcription_ready(text: String)
signal transcription_failed(reason: String)
signal speech_started(speaker: String)
signal speech_finished(speaker: String)
signal permission_result(granted: bool)

const MAX_RECORD_S := 25.0
const RATE := 16000

var mic_state := "ready"
var mic_level := 0.0
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _vad: Object = null
var _raw := PackedByteArray()
var _record_time := 0.0
var _heard_speech := false
var _resample_acc := 0.0

var _player: AudioStreamPlayer
var _queue: Array = []              # AudioStreamWAV pendientes de la frase actual
var _speaking := false
var _speak_mode := ""               # ia | sistema | silencio
var _speak_end_time := 0.0
var _speech_token := 0
var _utterance_id := 0
var _tts_voices: Array = []
var current_speaker := ""
var _sys_tts_checked := false


## La voz del sistema solo se consulta cuando hace falta (en algunos Android sin
## motor de voz, consultarla al arrancar puede dar problemas).
func _system_voices() -> Array:
	if not _sys_tts_checked:
		_sys_tts_checked = true
		if DisplayServer.get_name() != "headless" and ProjectSettings.get_setting("audio/general/text_to_speech", false):
			_tts_voices = DisplayServer.tts_get_voices_for_language("es")
			DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_end)
			DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_tts_end)
	return _tts_voices
var last_tts_engine := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	_capture = Audio.capture_effect
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)
	_player.finished.connect(_on_chunk_finished)
	if get_tree().has_signal("on_request_permissions_result"):
		get_tree().on_request_permissions_result.connect(_on_permission)


# ------------------------------------------------------------------ Estado

func neural_voice_ready() -> bool:
	return Brain.voice_state == "ready" and str(Settings.get_value("tts_mode")) == "ia"


func stt_available() -> bool:
	return Brain.voice_state == "ready" and Brain.stt != null


func can_speak() -> bool:
	var mode := str(Settings.get_value("tts_mode"))
	if mode == "off":
		return false
	return neural_voice_ready() or not _system_voices().is_empty()


func tts_status_text() -> String:
	if str(Settings.get_value("tts_mode")) == "off":
		return "Voces desactivadas (solo subtítulos)"
	if neural_voice_ready():
		return "Voces neuronales en el móvil (Kokoro)"
	if Brain.voice_state in ["missing", "downloading", "error"]:
		return "Voces neuronales sin descargar: se usa la voz del sistema" if not _system_voices().is_empty() else "Sin voces disponibles: solo subtítulos"
	return "Voz del sistema Android" if not _system_voices().is_empty() else "Sin voces disponibles: solo subtítulos"


func stt_status_text() -> String:
	match Brain.voice_state:
		"ready":
			return "Reconocimiento de voz en el móvil (Whisper)"
		"loading":
			return "Cargando reconocimiento de voz…"
		"unsupported":
			return "Reconocimiento de voz no disponible en esta plataforma"
	return "Reconocimiento de voz sin descargar: usa el modo texto"


# ------------------------------------------------------------------ Hablar

## Habla con la voz del personaje. profile: {id, female, variant, speed, pitch}
func speak(text: String, profile: Dictionary) -> void:
	stop_speaking()
	_speech_token += 1
	var token := _speech_token
	current_speaker = str(profile.get("id", ""))
	_speaking = true
	_set_mic_state("speaking")
	speech_started.emit(current_speaker)
	Audio.duck_music(true)
	var mode := str(Settings.get_value("tts_mode"))
	if mode == "ia" and neural_voice_ready():
		_speak_mode = "ia"
		var voice := "ef_dora" if profile.get("female", false) else "em_alex"
		var engine: Object = await Brain.get_tts(voice)
		if token != _speech_token:
			return
		if engine != null:
			last_tts_engine = "kokoro:" + voice
			_player.pitch_scale = clampf(float(profile.get("pitch", 1.0)), 0.8, 1.25)
			var sentences := _split_sentences(text)
			var first := true
			for s in sentences:
				var wav: PackedByteArray = await engine.synthesize(s)
				if token != _speech_token:
					return
				var stream := AudioStreamWAV.load_from_buffer(wav) if wav.size() > 100 else null
				if stream == null:
					continue
				if first and not _player.playing:
					_player.stream = stream
					_player.play()
					first = false
				else:
					_queue.append(stream)
			if not _player.playing and _queue.is_empty():
				_on_speech_done()
			return
	if mode != "off" and not _system_voices().is_empty():
		_speak_mode = "sistema"
		last_tts_engine = "sistema"
		_utterance_id += 1
		var vol := int(clampf(float(Settings.get_value("vol_voice")) * float(Settings.get_value("vol_master")), 0.0, 1.0) * 100.0)
		var v := str(_tts_voices[absi(hash(current_speaker)) % _tts_voices.size()]["id"])
		DisplayServer.tts_speak(text, v, vol, clampf(float(profile.get("pitch", 1.0)), 0.5, 2.0), clampf(float(profile.get("speed", 1.0)), 0.5, 2.0), _utterance_id, true)
		_speak_end_time = Time.get_ticks_msec() / 1000.0 + estimate_duration(text) * 1.8 + 2.0
		return
	_speak_mode = "silencio"
	last_tts_engine = "ninguna"
	_speak_end_time = Time.get_ticks_msec() / 1000.0 + estimate_duration(text)


func _split_sentences(text: String) -> Array:
	var out := []
	var cur := ""
	for ch in text:
		cur += ch
		if ch in [".", "!", "?", "…"] and cur.strip_edges().length() > 12:
			out.append(cur.strip_edges())
			cur = ""
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out


func _on_chunk_finished() -> void:
	if not _queue.is_empty():
		_player.stream = _queue.pop_front()
		_player.play()
	elif _speak_mode == "ia":
		_on_speech_done()


func estimate_duration(text: String) -> float:
	return clampf(text.length() / 14.5, 0.8, 14.0)


func stop_speaking() -> void:
	_speech_token += 1
	_queue.clear()
	if not _speaking:
		return
	if _speak_mode == "sistema" and DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
	_player.stop()
	_on_speech_done()


func is_speaking() -> bool:
	return _speaking


func _on_tts_end(id: int) -> void:
	if id == _utterance_id:
		call_deferred("_on_speech_done")


func _on_speech_done() -> void:
	if not _speaking:
		return
	_speaking = false
	Audio.duck_music(false)
	if mic_state == "speaking":
		_set_mic_state("ready")
	speech_finished.emit(current_speaker)


## Apertura de la boca (0..1) del personaje que habla.
func mouth_open(t: float) -> float:
	if not _speaking:
		return 0.0
	if _speak_mode == "ia":
		return Audio.voice_level()
	return clampf(0.2 + 0.6 * absf(sin(t * 12.0)) * (0.5 + 0.5 * sin(t * 2.7)), 0.0, 1.0)


# ------------------------------------------------------------------ Micrófono

func request_mic_permission() -> void:
	if OS.get_name() != "Android":
		permission_result.emit(true)
		return
	if "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		permission_result.emit(true)
		return
	OS.request_permission("android.permission.RECORD_AUDIO")


func has_mic_permission() -> bool:
	return OS.get_name() != "Android" or "android.permission.RECORD_AUDIO" in OS.get_granted_permissions()


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
		_fail("Necesito permiso de micrófono. Acéptalo y vuelve a pulsar.")
		return false
	stop_speaking()
	_vad = await Brain.new_vad()
	_raw = PackedByteArray()
	_record_time = 0.0
	_heard_speech = false
	_resample_acc = 0.0
	_capture.clear_buffer()
	if not _mic_player.playing:
		_mic_player.play()
	_set_mic_state("listening")
	return true


func cancel_listening() -> void:
	if mic_state != "listening":
		return
	_mic_player.stop()
	_vad = null
	_set_mic_state("ready")


func stop_listening() -> void:
	if mic_state != "listening":
		return
	_drain_capture()
	_mic_player.stop()
	var speech := PackedByteArray()
	if _vad != null:
		speech = _vad.finish()
	_vad = null
	if speech.size() < RATE * 2 * 0.3:
		speech = _raw  # el jugador paró antes de que el detector cerrara el tramo
	if speech.size() < RATE * 2 * 0.4 or WavUtil.peak(speech) < 0.02:
		_fail("No te he oído. Acércate al micrófono e inténtalo otra vez.")
		return
	_set_mic_state("transcribing")
	var text: String = await Brain.stt.transcribe_pcm(speech, RATE)
	if mic_state != "transcribing":
		return
	text = text.strip_edges()
	if text.length() < 2 or text in ["[BLANK_AUDIO]", "(silencio)"]:
		_fail("No he entendido lo que dijiste. Repítelo, por favor.")
		return
	_set_mic_state("processing")
	Save.stat_add("voice_turns")
	transcription_ready.emit(text)


## Lee lo capturado del micrófono, lo pasa a 16 kHz mono y lo da al detector de voz.
func _drain_capture() -> void:
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	var step := float(AudioServer.get_mix_rate()) / RATE
	var chunk := PackedByteArray()
	chunk.resize(int(frames.size() / step + 2) * 2)
	var count := 0
	var peak := 0.0
	var pos := _resample_acc
	while pos < frames.size():
		var f: Vector2 = frames[int(pos)]
		var v := clampf((f.x + f.y) * 0.5, -1.0, 1.0)
		peak = maxf(peak, absf(v))
		chunk.encode_s16(count * 2, int(v * 32767.0))
		count += 1
		pos += step
	_resample_acc = pos - frames.size()
	chunk.resize(count * 2)
	_raw.append_array(chunk)
	mic_level = lerpf(mic_level, clampf(peak * 3.0, 0.0, 1.0), 0.5)
	if _vad != null and chunk.size() > 0:
		var ev: String = _vad.push(chunk)
		if ev in ["speech_started", "speech"]:
			_heard_speech = true
		if ev == "speech_ended" and _heard_speech and Settings.get_value("vad_auto_stop"):
			call_deferred("stop_listening")


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
	if _speaking and _speak_mode != "ia" and Time.get_ticks_msec() / 1000.0 > _speak_end_time:
		if _speak_mode != "sistema" or not DisplayServer.tts_is_speaking():
			_on_speech_done()
	if mic_state != "listening":
		mic_level = lerpf(mic_level, 0.0, delta * 8.0)
		return
	_record_time += delta
	_drain_capture()
	if _record_time >= MAX_RECORD_S:
		stop_listening()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mic_state == "listening":
			cancel_listening()
		stop_speaking()
