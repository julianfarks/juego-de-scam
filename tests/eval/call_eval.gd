extends SceneTree
## Evaluación de conversaciones LIBRES con la IA local usando EL MISMO CÓDIGO que el
## juego (CallSession: memoria, notas, límites de tiempo, cierre por reglas).
##   godot --headless --path . -s tests/eval/call_eval.gd -- --model=ruta.gguf --client=chucho --script=queso
## Imprime la transcripción y una línea RESUMEN con métricas comprobables.

const SCRIPTS := {
	# Producto inventado, detalles, precio, servicio añadido, cambio de tema, broma,
	# negociación con cantidad, pregunta de memoria, garantía y cierre.
	"queso": [
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
		"PAGO",
	],
	# Cambio completo de propuesta a mitad de llamada y vuelta a un tema anterior.
	"jardin": [
		"Hola, buenas. Le ofrezco un servicio de jardinería a domicilio: podamos, regamos y quitamos malas hierbas.",
		"Son 30 pesos al mes y vamos una vez por semana.",
		"¿Tiene usted plantas o jardín en casa?",
		"Bueno, olvide la jardinería. Mejor le ofrezco unas hierbas medicinales para dormir como un bebé.",
		"Son de un huerto de la sierra, hechas con flores de manzanilla y tila.",
		"Le dejo tres botes por 12 pesos cada uno.",
		"¿Se acuerda de lo primero que le ofrecí?",
		"Si quiere, también le regalo una maceta con una planta que canta por las mañanas.",
		"¿Y qué opina usted de las plantas que cantan?",
		"Entonces, ¿le mando los tres botes de hierbas?",
		"PAGO",
	],
}


func _initialize() -> void:
	var model_path := ""
	var client := "chucho"
	var script_id := "queso"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.substr(8)
		if a.begins_with("--client="): client = a.substr(9)
		if a.begins_with("--script="): script_id = a.substr(9)
	await process_frame
	var brain = root.get_node("Brain")
	var t0 := Time.get_ticks_msec()
	var model = await NobodyWhoModel.create(model_path, {"use_gpu": false})
	if model == null:
		print("ERROR: no se pudo cargar ", model_path)
		quit(1)
		return
	brain.model = model
	brain.llm_state = "ready"
	print("Modelo %s cargado en %d ms" % [model_path.get_file(), Time.get_ticks_msec() - t0])
	var c := ClientDB.get_c(client)
	print("CLIENTE: %s (%s) · presupuesto %d · guion %s" % [c["name"], c["personality"], ClientDB.budget(client, 1), script_id])
	var s := CallSession.new()
	root.add_child(s)
	var lines := []
	s.client_spoke.connect(func(t, emo, _g, src): lines.append([t, emo, src]))
	var result := {}
	s.ended.connect(func(r): result.merge(r))
	s.start(client, 1, {}, {"day": 1}, 42)
	while s.phase in ["", "preparando", "pensando"]:
		await process_frame
	_report("[Suena el teléfono]", s, lines)
	var timeouts := 0
	var no_entiendo := 0
	var memory_answer := ""
	for line in SCRIPTS[script_id]:
		if not s.active:
			break
		if s.phase == "error":
			timeouts += 1
			await s.retry()
			while s.phase == "pensando":
				await process_frame
			if s.phase == "error":
				s.continue_basic()
		var n0 := lines.size()
		if line == "PAGO":
			s.st.trust = maxf(s.st.trust, 80.0)   # cliente receptivo para comprobar el cierre
			s.st.suspicion = minf(s.st.suspicion, 15.0)
			await s.attempt_close()
		else:
			await s.player_says(line)
		while s.phase == "pensando":
			await process_frame
		if s.phase == "error":
			timeouts += 1
		var reply: String = lines[-1][0] if lines.size() > n0 else "(sin respuesta: %s)" % s.last_error
		if IntentClassifier.normalize(reply).contains("no entiend"):
			no_entiendo += 1
		if line.contains("Recuerda") or line.contains("acuerda"):
			memory_answer = reply
		_report(line, s, lines)
	if s.active:
		s.player_hangs_up()
	var avg := 0
	for t in s.turn_times:
		avg += int(t)
	avg = avg / maxi(1, s.turn_times.size())
	var words := {}
	var total_words := 0
	for l in lines:
		for w in IntentClassifier.normalize(l[0]).split(" ", false):
			words[w] = true
			total_words += 1
	print("\nMEMORIA: «%s»" % memory_answer)
	print("PROPUESTA FINAL (según el cliente): «%s» · precio reglas %d × %d · historial de propuestas: %s" % [s.st.proposal, s.st.stated_price, s.st.quantity, str(s.st.proposal_log.map(func(p): return p["text"]))])
	print("RESUMEN modelo=%s cliente=%s guion=%s turnos_ia=%d errores=%d no_entiendo=%d repeticiones_regeneradas=%d media=%.1f s palabras_por_respuesta=%.1f vocabulario=%d resultado=%s importe=%d" % [
		model_path.get_file(), client, script_id, s.ai_turns, timeouts, no_entiendo, s.regenerations, avg / 1000.0,
		float(total_words) / maxf(1.0, lines.size()), words.size(), result.get("outcome", "?"), int(result.get("amount", 0))])
	quit()


func _report(line: String, s: CallSession, lines: Array) -> void:
	var last: Array = lines[-1] if not lines.is_empty() else ["-", "", ""]
	print("\n> %s" % line)
	print("< %s\n   [%s · %s · confianza %d · sospecha %d · interés %d · duda «%s» · propuesta «%s» · %.1f s]" % [
		last[0], last[2], last[1], int(s.st.trust), int(s.st.suspicion), s.st.ai_interest, s.st.ai_doubt, s.st.proposal, s.last_turn_ms / 1000.0])
