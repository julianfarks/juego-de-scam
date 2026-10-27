extends SceneTree
## Prueba de voz de ida y vuelta: Kokoro (español) sintetiza frases, Whisper las
## transcribe y se compara el resultado. Mide tiempos y calidad sin oír el audio.
## godot --headless --path . -s tests/eval/voice_eval.gd -- --models=ruta

const PHRASES := [
	"Hola, buenas tardes. ¿Quién me llama a estas horas?",
	"No me interesa ningún seguro contra extraterrestres, gracias.",
	"¿Y cuánto me va a costar eso al mes?",
	"Mi vecino Ramón ya tiene uno y está encantado.",
	"Le doy garantía de devolución por escrito, no se preocupe.",
]


func _norm(s: String) -> PackedStringArray:
	var t := s.to_lower()
	for a in [["á","a"],["é","e"],["í","i"],["ó","o"],["ú","u"],["ñ","n"],["¿",""],["?",""],["¡",""],["!",""],[",",""],[".",""]]:
		t = t.replace(a[0], a[1])
	return t.split(" ", false)


func _wer(ref: String, hyp: String) -> float:
	var r := _norm(ref)
	var h := _norm(hyp)
	var d := []
	for i in r.size() + 1:
		var row := []
		row.resize(h.size() + 1)
		d.append(row)
	for i in r.size() + 1:
		d[i][0] = i
	for j in h.size() + 1:
		d[0][j] = j
	for i in range(1, r.size() + 1):
		for j in range(1, h.size() + 1):
			var c := 0 if r[i - 1] == h[j - 1] else 1
			d[i][j] = mini(mini(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + c)
	return float(d[r.size()][h.size()]) / maxf(1.0, r.size())


func _initialize() -> void:
	var m := "models_local"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--models="): m = a.substr(9)
	m = ProjectSettings.globalize_path("res://" + m) if not m.begins_with("/") else m
	var stt_dir := "whisper-base"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stt="): stt_dir = a.substr(6)
	var t0 := Time.get_ticks_msec()
	var stt = await ClassDB.class_call_static("NobodyWhoSpeechToText", "create", m.path_join(stt_dir), {"language": "es", "quantization": "q4"})
	print("Whisper (%s) cargado: %s en %d ms" % [stt_dir, stt != null, Time.get_ticks_msec() - t0])
	var total_wer := 0.0
	for voice in ["ef_dora", "em_alex"]:
		t0 = Time.get_ticks_msec()
		var tts = await ClassDB.class_call_static("NobodyWhoTextToSpeech", "create", m.path_join("kokoro-es"), {"architecture": "kokoro", "voice": voice, "language": "es", "device": "cpu"})
		print("Kokoro %s cargado: %s en %d ms" % [voice, tts != null, Time.get_ticks_msec() - t0])
		if tts == null:
			continue
		for p in PHRASES:
			t0 = Time.get_ticks_msec()
			var wav: PackedByteArray = await tts.synthesize(p)
			var t_tts := Time.get_ticks_msec() - t0
			var stream := AudioStreamWAV.load_from_buffer(wav)
			var secs := stream.get_length() if stream else 0.0
			# PCM a 16 kHz mono para Whisper
			var pcm := wav.slice(44)
			var rate: int = stream.mix_rate if stream else 24000
			t0 = Time.get_ticks_msec()
			var text: String = await stt.transcribe_pcm(pcm, rate)
			var t_stt := Time.get_ticks_msec() - t0
			var w := _wer(p, text)
			total_wer += w
			print("[%s] TTS %d ms (audio %.1f s) | STT %d ms | WER %.2f\n   ref: %s\n   oído: %s" % [voice, t_tts, secs, t_stt, w, p, text])
	# VAD sobre un audio con silencio + voz + silencio
	var vad = await ClassDB.class_call_static("NobodyWhoVoiceActivityDetection", "create", m.path_join("silero-vad"), {"sample_rate": 24000})
	print("VAD cargado: ", vad != null)
	if vad:
		var tts2 = await ClassDB.class_call_static("NobodyWhoTextToSpeech", "create", m.path_join("kokoro-es"), {"architecture": "kokoro", "voice": "ef_dora", "language": "es", "device": "cpu"})
		var wav2: PackedByteArray = await tts2.synthesize(PHRASES[2])
		var speech := wav2.slice(44)
		var sil := PackedByteArray()
		sil.resize(24000 * 2)
		var all := sil + speech + sil + sil
		var events := []
		var step := 4800
		for i in range(0, all.size(), step):
			var ev: String = vad.push(all.slice(i, mini(i + step, all.size())))
			if events.is_empty() or events[-1] != ev:
				events.append(ev)
		var seg: PackedByteArray = vad.finish()
		print("VAD eventos: ", events, " · segmento: %d bytes (voz original %d)" % [seg.size(), speech.size()])
		var t3: String = await stt.transcribe_pcm(seg, 24000)
		print("VAD+STT: ", t3)
	print("WER medio: %.2f" % (total_wer / 10.0))
	quit()
