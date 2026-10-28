extends Node
## Prueba automática DENTRO del juego (se usa en el emulador Android del CI).
## Se activa si existe user://autotest.flag o con el argumento --autotest.
## Recorre: descarga de modelos → carga de la IA → jornada → llamada con IA real →
## venta/rechazo por reglas → voz (Kokoro→Whisper) → fin de jornada → guardado.
## Escribe user://autotest/resultado.txt y capturas PNG.

const OUT := "user://autotest"
var main: Node
var log_lines: PackedStringArray = []
var ok_count := 0
var fail_count := 0


func _ready() -> void:
	main = get_parent()
	DirAccess.make_dir_recursive_absolute(OUT)
	_run()


func say(t: String) -> void:
	var line := "[%7.1f s] %s" % [Time.get_ticks_msec() / 1000.0, t]
	print("AUTOTEST ", line)
	log_lines.append(line)
	_flush()


func check(c: bool, what: String) -> void:
	if c:
		ok_count += 1
	else:
		fail_count += 1
	say(("OK   " if c else "FALLO ") + what)


func _flush() -> void:
	var f := FileAccess.open(OUT.path_join("resultado.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


var last_shot_colors := 0

func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	last_shot_colors = 0
	if img:
		img.save_png(OUT.path_join(name + ".png"))
		# ¿Se ve algo? Cuenta colores distintos en una versión reducida de la imagen.
		var small := img.duplicate() as Image
		small.resize(64, 36, Image.INTERPOLATE_NEAREST)
		var seen := {}
		for y in small.get_height():
			for x in small.get_width():
				seen[small.get_pixel(x, y).to_html(false)] = true
		last_shot_colors = seen.size()
	say("captura %s (%d colores)" % [name, last_shot_colors])


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	say("Plataforma %s · %s · CPU %d · memoria %s" % [OS.get_name(), OS.get_model_name(), OS.get_processor_count(), str(OS.get_memory_info())])
	await wait(4.0)
	await shot("01_inicio")
	check(Brain.available, "la extensión de IA local (NobodyWho) se carga en esta plataforma")
	# 1. Descarga de modelos (o ya presentes)
	if not Brain.missing_packs().is_empty():
		say("Descargando %.2f GB de modelos…" % (Brain.missing_bytes() / 1073741824.0))
		var last := -10
		Brain.download_progress.connect(func(d: int, t: int, l: String) -> void:
			var pc := int(100.0 * d / maxf(1.0, t))
			if pc >= last + 10:
				last = pc
				say("  descarga %d %% (%s)" % [pc, l]))
		var dl_ok: bool = await Brain.download_all()
		check(dl_ok, "descarga de modelos completa (%s)" % Brain.last_error)
	check(Brain.missing_packs().is_empty(), "todos los modelos están en el dispositivo")
	# 2. Carga
	var t0 := Time.get_ticks_msec()
	while Brain.llm_state in ["loading", "missing", "downloading"] and Time.get_ticks_msec() - t0 < 600000:
		if Brain.llm_state == "missing" and Brain.missing_packs().is_empty():
			Brain.load_all()
		await wait(1.0)
	check(Brain.is_ready(), "modelo de lenguaje cargado en %.1f s (%s)" % [(Time.get_ticks_msec() - t0) / 1000.0, Brain.status_text()])
	t0 = Time.get_ticks_msec()
	while Brain.voice_state in ["loading", "missing"] and Time.get_ticks_msec() - t0 < 300000:
		await wait(1.0)
	check(Brain.voice_state == "ready" and Brain.stt != null, "oído cargado: Whisper (%s)" % Brain.voice_state)
	check(Brain.tts_ok, "voces neuronales cargadas: Kokoro (%s)" % ("sí" if Brain.tts_ok else Brain.last_error))
	# 3. Jornada y llamada con IA
	main._start_day(1)
	await wait(3.0)
	await shot("02_oficina")
	check(last_shot_colors > 20, "la oficina 3D se dibuja en pantalla (%d colores; %s)" % [last_shot_colors, RenderingServer.get_video_adapter_name()])
	var office: OfficeController = main.office
	check(office.player != null and Game.in_shift, "jornada iniciada y jugador en la oficina")
	var p0: Vector3 = office.player.global_position
	office.player.move_input = Vector2(0.0, -1.0)
	await wait(1.5)
	office.player.move_input = Vector2.ZERO
	check(office.player.global_position.distance_to(p0) > 0.5, "el jugador se mueve con el joystick")
	var lead: Dictionary = Game.leads[0].duplicate()
	lead["client_id"] = "chucho"
	lead["name"] = "Chucho Carcajada"
	office._start_call(lead, true)
	await wait(1.0)
	await shot("03_ficha")
	var cs: CallScreen = office.call_screen
	cs._begin_call()
	var s: CallSession = cs.session
	t0 = Time.get_ticks_msec()
	while (s.phase in ["", "preparando", "pensando"]) and Time.get_ticks_msec() - t0 < 900000:
		await wait(0.5)
	check(s.mode == "ia", "la llamada usa la IA local (modo %s)" % s.mode)
	if s.phase == "error":
		say("El saludo falló (%s): se reintenta" % s.last_error)
		await s.retry()
	say("Saludo del cliente (%.1f s): %s" % [(Time.get_ticks_msec() - t0) / 1000.0, s.st.history[-1]["text"] if not s.st.history.is_empty() else "-"])
	# Conversación LIBRE de 10 intercambios: producto inventado, cambio de propuesta,
	# cambio de tema, broma, negociación con cantidad, pregunta de memoria.
	var script_lines := [
		"Buenas, le llamo de TeleTimo. Tengo un queso artesanal de cabra que le va a encantar.",
		"Está hecho con una receta familiar de mi abuela y tiene un sabor muy diferente.",
		"Cuesta 20 pesos la pieza.",
		"Y además se lo llevamos a domicilio sin coste.",
		"Oiga, ¿y usted a qué se dedica?",
		"Jaja, qué bueno. ¿Sabe por qué el queso nunca miente? Porque es muy curado.",
		"Volviendo al queso: si se lleva dos piezas se las dejo en 18 pesos cada una.",
		"¿Recuerda qué le estaba ofreciendo y a qué precio?",
		"Le doy garantía: si no le gusta, le devolvemos el dinero.",
		"Entonces, ¿le preparo las dos piezas?",
	]
	var stuck := 0
	var memory_answer := ""
	for line in script_lines:
		if not s.active:
			break
		cs._say(line, false)
		t0 = Time.get_ticks_msec()
		await wait(0.3)
		while s.phase == "pensando" and Time.get_ticks_msec() - t0 < 900000:
			await wait(0.5)
		if s.phase == "pensando":
			stuck += 1
		if s.phase == "error":
			say("  Error de la IA (%s) tras %.1f s: se pulsa Reintentar" % [s.last_error, (Time.get_ticks_msec() - t0) / 1000.0])
			await s.retry()
			while s.phase == "pensando":
				await wait(0.5)
			if s.phase == "error":
				say("  Sigue fallando: «Seguir sin IA»")
				s.continue_basic()
		var reply: String = s.st.history[-1]["text"] if s.st.history[-1]["who"] == "client" else "(sin respuesta)"
		if line.begins_with("¿Recuerda"):
			memory_answer = reply
		say("Vendedor: %s\n            Cliente (%.1f s): %s" % [line, (Time.get_ticks_msec() - t0) / 1000.0, reply])
	await shot("04_llamada")
	check(last_shot_colors > 20, "la pantalla de llamada se dibuja (%d colores)" % last_shot_colors)
	check(stuck == 0, "ninguna respuesta se quedó «pensando» sin límite")
	check(s.ai_turns >= 8, "el cliente respondió con la IA (%d turnos de IA, %d errores)" % [s.ai_turns, s.errors])
	check(s.st.proposal.to_lower().contains("queso"), "el cliente recuerda la propuesta inventada («%s»)" % s.st.proposal)
	check(s.st.stated_price == 18 and s.st.quantity == 2, "las reglas registran el precio negociado y la cantidad (%d × %d)" % [s.st.stated_price, s.st.quantity])
	check(memory_answer.to_lower().contains("queso") or memory_answer.contains("18") or memory_answer.contains("20") or memory_answer.to_lower().contains("dieciocho") or memory_answer.to_lower().contains("veinte"), "responde a la pregunta de memoria con lo hablado («%s»)" % memory_answer)
	# 4. Voz: el cliente habla con la voz neuronal y Whisper entiende una frase sintetizada
	if Brain.tts_ok and Brain.stt != null:
		var eng: Object = await Brain.get_tts("ef_dora")
		t0 = Time.get_ticks_msec()
		var wav: PackedByteArray = await eng.synthesize("¿Y cuánto me va a costar eso al mes?")
		var t_tts := Time.get_ticks_msec() - t0
		var st := AudioStreamWAV.load_from_buffer(wav)
		check(st != null and st.get_length() > 0.5, "voz neuronal generada (%.1f s de audio en %.1f s)" % [st.get_length() if st else 0.0, t_tts / 1000.0])
		t0 = Time.get_ticks_msec()
		var heard: String = await Brain.stt.transcribe_pcm(wav.slice(44), st.mix_rate if st else 24000)
		check(heard.to_lower().contains("cuesta") or heard.to_lower().contains("costar") or heard.to_lower().contains("mes"), "Whisper transcribe español: «%s» (%.1f s)" % [heard, (Time.get_ticks_msec() - t0) / 1000.0])
	# 5. Cierre por reglas (se fuerza un cliente muy receptivo para comprobar el registro)
	var bal0 := int(Save.data["money"])
	s.st.trust = 95.0
	s.st.understanding = 90.0
	s.st.suspicion = 0.0
	s.st.offer_explained = true
	s.st.pending_objections.clear()
	t0 = Time.get_ticks_msec()
	var tries := 0
	while s.active and tries < 4 and Time.get_ticks_msec() - t0 < 400000:
		if s.phase == "error":
			s.continue_basic()
		if s.phase == "listo":
			cs._ask_payment()
			tries += 1
		await wait(0.5)
	if s.active:
		s.player_hangs_up()
	await wait(1.0)
	await shot("05_venta")
	check(not s.active, "la llamada termina con un resultado (%s)" % s.st.outcome)
	while is_instance_valid(cs) and not cs.summary_shown:
		await wait(0.5)
	await shot("06_resumen")
	if is_instance_valid(cs):
		cs.finish()
	check(int(Game.ledger["calls"]) == 1, "la llamada cuenta en la jornada")
	var income: int = Game.ledger["income"]
	if s.st.outcome == "success":
		var tx: Dictionary = Save.data["transactions"][-1]
		check(int(tx["amount"]) == 36 and String(tx["proposal"]).to_lower().contains("queso"), "transacción registrada: %s, %d × %d = %d" % [tx["proposal"], int(tx["unit_price"]), int(tx["quantity"]), int(tx["amount"])])
		check(int(Save.data["money"]) == bal0 + int(tx["commission"]), "el saldo sube con la comisión (%d → %d)" % [bal0, int(Save.data["money"])])
	else:
		check(income == 0, "sin venta no hay ingreso (resultado: %s)" % s.st.outcome)
	# 6. Fin de jornada y guardado
	Game.shift_left = 0.0
	t0 = Time.get_ticks_msec()
	while not office.day_over and Time.get_ticks_msec() - t0 < 30000:
		await wait(0.5)
	await wait(4.0)
	await shot("07_evaluacion")
	check(int(Save.data["stats"]["calls_made"]) >= 1, "el progreso se guarda (llamadas en el guardado: %d)" % int(Save.data["stats"]["calls_made"]))
	check(FileAccess.file_exists("user://save.json"), "existe el archivo de guardado")
	say("Tiempo medio de respuesta de la IA: %.1f s" % Brain.avg_turn_seconds())
	say("RESULTADO FINAL: %d OK, %d FALLOS" % [ok_count, fail_count])
	var done := FileAccess.open(OUT.path_join("terminado.txt"), FileAccess.WRITE)
	done.store_string("%d %d" % [ok_count, fail_count])
	done.close()
	# Cierra el juego al terminar (si no, queda abierto con el modelo cargado en memoria)
	await wait(3.0)
	get_tree().quit()
