class_name DiagnosticsPanel
extends Control
## Diagnóstico de la IA en el propio móvil. Cada prueba es INDEPENDIENTE, para saber
## qué pieza falla: archivos, Gemma sola (sin personajes, voz ni llamada), número de
## hilos, voz (Kokoro), oído (Whisper) y una conversación de 10 intercambios con el
## código real de la llamada. Todo se escribe en un informe que se puede copiar.

signal closed

const CALL_LINES := [
	"Buenas, le llamo de TeleTimo. Tengo un queso artesanal de cabra que le va a encantar.",
	"Está hecho con una receta familiar y tiene un sabor muy diferente.",
	"Cuesta 20 pesos la pieza.",
	"Y además se lo llevamos a domicilio sin coste.",
	"Oiga, ¿y usted a qué se dedica?",
	"Jaja, qué bueno. ¿Sabe por qué el queso nunca miente? Porque es muy curado.",
	"Si se lleva dos piezas se las dejo en 18 pesos cada una.",
	"¿Recuerda qué le estaba ofreciendo y a qué precio?",
	"Le doy garantía: si no le gusta, le devolvemos el dinero.",
	"Entonces, ¿le preparo las dos piezas?",
]

var report: TextEdit
var buttons: Array = []
var running := false
var _cancel := {"cancel": false}
var _session: CallSession = null


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	add_child(m)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("Diagnóstico de la IA", 30, UIKit.C_ACCENT))
	v.add_child(UIKit.label("Cada prueba usa los modelos ya descargados (no descarga nada). Pulsa una, espera el resultado y usa «Copiar informe» para enviarlo.", 18, UIKit.C_MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	v.add_child(flow)
	for b in [["1. Archivos", _t_files], ["2. Gemma sola", _t_gemma], ["3. Comparar hilos", _t_threads], ["4. Voz (Kokoro)", _t_tts], ["5. Oído (Whisper)", _t_stt], ["6. Conversación de 10", _t_call]]:
		var btn := UIKit.button(b[0], b[1], UIKit.C_BLUE, 56, 19)
		flow.add_child(btn)
		buttons.append(btn)
	report = TextEdit.new()
	report.editable = false
	report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report.add_theme_font_size_override("font_size", 16)
	v.add_child(report)
	var h := UIKit.hbox(8)
	v.add_child(h)
	h.add_child(UIKit.button("Cancelar prueba", func() -> void:
		_cancel["cancel"] = true
		if _session and _session.active:
			_session.cancel_pending()
			_session.player_hangs_up(), UIKit.C_PANEL2, 56, 19))
	h.add_child(UIKit.button("Copiar informe", func() -> void:
		DisplayServer.clipboard_set(report.text + "\n\n--- Registro técnico ---\n" + AILog.text().right(6000))
		_line("(Informe y registro copiados al portapapeles)"), UIKit.C_GOOD, 56, 19))
	h.add_child(UIKit.button("Cerrar", func() -> void:
		_cancel["cancel"] = true
		closed.emit()
		queue_free(), UIKit.C_BAD, 56, 19))
	_header()


func _header() -> void:
	var topo := GemmaBench.cpu_topology()
	_line("Dispositivo: %s %s · %d núcleos (frecuencias máx. %s MHz; grandes: %d) · RAM %.1f GB, disponible %.0f MB · memoria del juego %.0f MB" % [
		OS.get_name(), OS.get_model_name(), topo["total"], str(topo["freqs_mhz"]), topo["big"], Brain.total_ram_bytes() / 1073741824.0, GemmaBench.mem_available_mb(), GemmaBench.rss_mb()])
	_line("IA: %s · estado del modelo: %s · GPU: %s · hilos: %d" % [Brain.status_text(), Brain.llm_state, "sí" if Brain.gpu_used else "no", Brain.threads()])


func _line(t: String) -> void:
	report.text += t + "\n"
	report.scroll_vertical = report.get_line_count()
	AILog.add("diagnóstico", t)


func _begin() -> bool:
	if running:
		_line("Ya hay una prueba en marcha.")
		return false
	running = true
	_cancel = {"cancel": false}
	for b in buttons:
		b.disabled = true
	return true


func _end() -> void:
	running = false
	for b in buttons:
		if is_instance_valid(b):
			b.disabled = false


func _need_model() -> bool:
	if Brain.llm_state == "ready" and Brain.model != null:
		return true
	if Brain.llm_state == "loading":
		_line("El modelo se está cargando; espera a que termine.")
	elif Brain.missing_packs().is_empty():
		_line("El modelo no está cargado (%s). Se intenta cargar ahora…" % Brain.llm_state)
		Brain.load_all()
	else:
		_line("Faltan modelos por descargar: %s" % ", ".join(PackedStringArray(Brain.missing_packs())))
	return false


# ------------------------------------------------------------------ Pruebas

func _t_files() -> void:
	_line("\n== 1. Archivos (sin descargar nada) ==")
	for r in Brain.verify_packs():
		_line("%s %s: %s" % ["✔" if r["ok"] else "✘", r["label"], r["detail"]])


func _t_gemma() -> void:
	if not _need_model() or not _begin():
		return
	_line("\n== 2. Gemma sola (sin personajes, voz ni llamada) · %d hilos ==" % Brain.threads())
	var a := await GemmaBench.measure(Brain.model, Brain.threads(), GemmaBench.PROMPT_SHORT)
	_line("Texto corto: " + GemmaBench.describe(a) + " · «%s»" % a["text"].substr(0, 60))
	if not _cancel["cancel"]:
		_line("Instrucciones reales de un cliente + saludo, con el formato JSON del juego…")
		var b := await GemmaBench.measure(Brain.model, Brain.threads(), Persona.system_prompt("tomasito", Persona.SITUATIONS[0], 100), "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]", {}, true)
		_line("Saludo real: " + GemmaBench.describe(b))
		_line("  Texto: «%s»" % b["text"].substr(0, 120))
		if b["ok"]:
			Brain.prompt_tps = maxf(1.0, b["prompt_tps"])
			Brain.gen_tps = maxf(0.3, b["gen_tps"])
			_line("  → Con esta velocidad, el cliente tarda unos %d s en empezar a hablar." % int(b["sentence_ms"] / 1000.0 if b["sentence_ms"] > 0 else Brain.expected_reply_seconds()))
	_end()


func _t_threads() -> void:
	if not _need_model() or not _begin():
		return
	var topo := GemmaBench.cpu_topology()
	var cands := []
	for n in [int(topo["big"]), maxi(2, int(topo["big"]) - 2), int(topo["total"]), 4]:
		n = clampi(n, 1, int(topo["total"]))
		if not cands.has(n):
			cands.append(n)
	_line("\n== 3. Comparar hilos: %s (instrucciones reales de un cliente) ==" % str(cands))
	var best := -1
	var best_ms := 1 << 30
	var prompt := Persona.system_prompt("tomasito", Persona.SITUATIONS[0], 100)
	for n in cands:
		if _cancel["cancel"]:
			break
		_line("Probando %d hilos…" % n)
		var r := await GemmaBench.measure(Brain.model, n, prompt, "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]", {}, true)
		_line("  " + GemmaBench.describe(r))
		var ms: int = r["sentence_ms"] if r["sentence_ms"] > 0 else (r["total_ms"] if r["ok"] else 1 << 30)
		if ms < best_ms:
			best_ms = ms
			best = n
	if best > 0:
		Settings.set_value("ai_threads", best)
		_line("→ El más rápido: %d hilos (frase del cliente en %.1f s). Guardado en Ajustes." % [best, best_ms / 1000.0])
	_end()


func _t_tts() -> void:
	if not _begin():
		return
	_line("\n== 4. Voz (Kokoro) ==")
	if not Brain.tts_ok:
		_line("Kokoro no está cargado (%s)." % Brain.voice_state)
		if Brain.voice_state != "loading" and Brain.missing_packs().is_empty():
			await Brain.load_voice()
	var eng: Object = await Brain.get_tts("ef_dora")
	if eng == null:
		_line("✘ No se pudo crear la voz neuronal.")
		_end()
		return
	var t0 := Time.get_ticks_msec()
	var r := await Timed.run(func(): return await eng.synthesize("Hola, soy una clienta de prueba y le escucho perfectamente."), 30000)
	if not r["ok"]:
		_line("✘ Kokoro no terminó en 30 s.")
		_end()
		return
	var st := AudioStreamWAV.load_from_buffer(r["value"])
	_line("✔ %.1f s de audio generados en %.1f s. Se reproduce ahora." % [st.get_length() if st else 0.0, (Time.get_ticks_msec() - t0) / 1000.0])
	Voice.speak("Hola, soy una clienta de prueba y le escucho perfectamente.", {"id": "diag", "female": true, "pitch": 1.05, "speed": 1.0})
	_end()


func _t_stt() -> void:
	if not _begin():
		return
	_line("\n== 5. Oído (Whisper) ==")
	if Brain.stt == null:
		_line("Whisper no está cargado (%s)." % Brain.voice_state)
		_end()
		return
	if not bool(Settings.get_value("mic_consent")):
		Settings.set_value("mic_consent", true)
	Voice.request_mic_permission()
	_line("Habla ahora (di por ejemplo «cuánto cuesta el queso»). Se para al detectar silencio o a los 15 s.")
	var box := {"text": "", "done": false}
	var ok_cb := func(t: String) -> void:
		box["text"] = t
		box["done"] = true
	var fail_cb := func(why: String) -> void:
		box["text"] = "(fallo: %s)" % why
		box["done"] = true
	Voice.transcription_ready.connect(ok_cb, CONNECT_ONE_SHOT)
	Voice.transcription_failed.connect(fail_cb, CONNECT_ONE_SHOT)
	Voice.start_listening()
	var t0 := Time.get_ticks_msec()
	while not box["done"] and Time.get_ticks_msec() - t0 < 15000 and not _cancel["cancel"]:
		await get_tree().process_frame
	if not box["done"] and Voice.mic_state == "listening":
		Voice.stop_listening()
	while not box["done"] and Time.get_ticks_msec() - t0 < 50000:
		await get_tree().process_frame
	if Voice.transcription_ready.is_connected(ok_cb):
		Voice.transcription_ready.disconnect(ok_cb)
	if Voice.transcription_failed.is_connected(fail_cb):
		Voice.transcription_failed.disconnect(fail_cb)
	Voice.reset_state()
	_line(("✔ Whisper entendió: «%s»" % box["text"]) if box["done"] and not String(box["text"]).begins_with("(fallo") else "✘ " + (String(box["text"]) if box["done"] else "Sin resultado en 50 s"))
	_end()


func _t_call() -> void:
	if not _need_model() or not _begin():
		return
	_line("\n== 6. Conversación de 10 intercambios (código real de la llamada) ==")
	_session = CallSession.new()
	add_child(_session)
	var replies := []
	_session.client_spoke.connect(func(t, _e, _g, src): replies.append([t, src]))
	_session.start("tomasito", 1, {}, {"day": 1}, 11)
	var t0 := Time.get_ticks_msec()
	while _session.phase in ["", "preparando", "pensando"] and not _cancel["cancel"]:
		await get_tree().process_frame
	_line("Saludo (%.1f s): %s" % [(Time.get_ticks_msec() - t0) / 1000.0, replies[-1][0] if not replies.is_empty() else "(error: %s)" % _session.last_error])
	var answered := 0
	for line in CALL_LINES:
		if _cancel["cancel"] or not _session.active:
			break
		if _session.phase == "error":
			_line("  Error: %s → se pulsa Reintentar" % AIStream.error_text(_session.last_error))
			await _session.retry()
			while _session.phase == "pensando":
				await get_tree().process_frame
			if _session.phase == "error":
				_line("  Sigue fallando; se detiene la prueba.")
				break
		var n0 := replies.size()
		t0 = Time.get_ticks_msec()
		await _session.player_says(line)
		while _session.phase == "pensando" and not _cancel["cancel"]:
			await get_tree().process_frame
		var got := replies.size() > n0
		if got:
			answered += 1
		_line("Tú: %s\n  Cliente (%.1f s, %s): %s" % [line, (Time.get_ticks_msec() - t0) / 1000.0, replies[-1][1] if got else "-", replies[-1][0] if got else "(sin respuesta: %s)" % AIStream.error_text(_session.last_error)])
	_line("→ %d de %d frases respondidas por la IA · errores %d · propuesta recordada: «%s» · precio %d × %d" % [answered, CALL_LINES.size(), _session.errors, _session.st.proposal, _session.st.stated_price, _session.st.quantity])
	if _session.active:
		_session.player_hangs_up()
	_session.queue_free()
	_session = null
	_end()
