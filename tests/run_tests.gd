extends Node
## Pruebas automáticas headless (escena con los autoloads cargados):
##   godot --headless --path . tests/test_runner.tscn
## Sale con código 1 si alguna falla.

var passed := 0
var failed := 0
var current := ""


func _ready() -> void:
	# Esperar un frame para que los autoloads estén listos
	await get_tree().process_frame
	await _run_all()
	print("\n==== RESULTADO: %d OK, %d FALLOS ====" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  ✗ [%s] %s" % [current, msg])


func section(name: String) -> void:
	current = name
	print("· " + name)


func _run_all() -> void:
	test_classifier()
	test_numbers()
	test_rules_basic()
	test_contradiction_and_memory()
	test_personality_differences()
	test_objections()
	test_economy_bounds()
	test_ai_cannot_alter_money()
	test_ai_response_validation()
	test_fake_card()
	test_save_migration()
	test_local_dialogue_all_personalities()
	await test_call_session_offline()
	test_game_state_day_cycle()
	test_upgrades()
	test_wav()
	test_events_objectives()


func test_classifier() -> void:
	section("Clasificador de intenciones")
	var a := IntentClassifier.analyze("Hola, buenas tardes. Me llamo Julián y le llamo de TeleTimo.")
	check(IntentClassifier.has(a, "greeting"), "detecta saludo")
	check(IntentClassifier.has(a, "introduce"), "detecta presentación")
	a = IntentClassifier.analyze("¿Me puede dar el número de su tarjeta?")
	check(IntentClassifier.has(a, "ask_payment"), "detecta petición de pago")
	check(a["is_question"], "detecta pregunta")
	a = IntentClassifier.analyze("Entiendo perfectamente, tiene razón, no se preocupe.")
	check(IntentClassifier.has(a, "empathy"), "detecta empatía")
	a = IntentClassifier.analyze("Si no paga hoy tendrá una multa y problemas legales")
	check(IntentClassifier.has(a, "pressure"), "detecta presión")
	a = IntentClassifier.analyze("jajaja es broma hombre")
	check(IntentClassifier.has(a, "joke"), "detecta broma")
	a = IntentClassifier.analyze("blorf quimbo trastabillo")
	check(IntentClassifier.has(a, "unclear"), "texto sin sentido = poco claro")
	a = IntentClassifier.analyze("Le ofrezco un seguro contra abducciones alienígenas", {"offer_id": "seguro_abduccion"})
	check(IntentClassifier.has(a, "offer_pitch"), "reconoce la oferta por sus palabras clave")
	a = IntentClassifier.analyze("Su loro Comandante estaría orgulloso", {"client_facts": ClientDB.get_c("remedios")["facts"]})
	check(IntentClassifier.has(a, "personal"), "reconoce referencia personal al cliente")
	a = IntentClassifier.analyze("Cuesta 49 al mes", {"pending_question_expects": ["price"]})
	check(IntentClassifier.has(a, "answer", 0.8), "reconoce que responde a la pregunta pendiente")


func test_numbers() -> void:
	section("Extracción de cifras")
	check(IntentClassifier.extract_numbers(IntentClassifier.normalize("cuesta 49 euros")) == [49], "dígitos")
	check(IntentClassifier.extract_numbers(IntentClassifier.normalize("cuarenta y nueve")) == [49], "palabras compuestas")
	check(IntentClassifier.extract_numbers(IntentClassifier.normalize("ciento veinte pesos")) == [120], "ciento veinte")
	check(IntentClassifier.extract_numbers(IntentClassifier.normalize("dos mil")) == [2000], "dos mil")


func _new_state(client_id: String, offer := "seguro_abduccion") -> ConversationState:
	var st := ConversationState.new()
	st.setup(client_id, offer)
	return st


func _rng(s := 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_rules_basic() -> void:
	section("Reglas de conversación")
	var st := _new_state("pilar")
	var t0 := st.trust
	ConversationRules.apply_turn(st, IntentClassifier.analyze("Entiendo, tiene razón. Le doy garantía de devolución por escrito."), _rng())
	check(st.trust > t0, "empatía + garantía suben la confianza")
	var st2 := _new_state("pilar")
	var s0 := st2.suspicion
	ConversationRules.apply_turn(st2, IntentClassifier.analyze("Tiene que pagar hoy o le pondremos una multa, es obligatorio"), _rng())
	check(st2.suspicion > s0 + 5, "la presión dispara la sospecha")
	var st3 := _new_state("pilar")
	var res := {}
	for i in 2:
		res = ConversationRules.apply_turn(st3, IntentClassifier.analyze("Es usted un idiota"), _rng())
	check(res["hangup"] == "insultos", "dos insultos = cuelga")
	check(st3.trust >= 0.0 and st3.patience >= 0.0, "valores acotados a 0..100")


func test_contradiction_and_memory() -> void:
	section("Memoria y contradicciones")
	var st := _new_state("agata")
	ConversationRules.apply_turn(st, IntentClassifier.analyze("El precio es de 49 euros"), _rng())
	check(st.stated_price == 49, "recuerda el precio dicho")
	var sus := st.suspicion
	var r := ConversationRules.apply_turn(st, IntentClassifier.analyze("Bueno, cuesta 99 euros al mes"), _rng())
	check(r["events"].has("contradiction"), "detecta cambio de precio sin justificar")
	check(st.contradictions.size() == 1, "guarda la contradicción")
	check(st.suspicion > sus + 10, "detector: la contradicción pesa mucho")
	var st2 := _new_state("pilar")
	ConversationRules.apply_turn(st2, IntentClassifier.analyze("Cuesta 99 euros"), _rng())
	var r2 := ConversationRules.apply_turn(st2, IntentClassifier.analyze("Pero hoy le hago un descuento: precio especial de 59 euros"), _rng())
	check(not r2["events"].has("contradiction") and r2["events"].has("price_lowered"), "un descuento justificado no es contradicción")
	var st3 := _new_state("pilar")
	ConversationRules.apply_turn(st3, IntentClassifier.analyze("Luego le cuento cómo funciona"), _rng())
	check(st3.promises.size() == 1, "registra promesas")
	var overdue := false
	for i in 3:
		var rr := ConversationRules.apply_turn(st3, IntentClassifier.analyze("¿Qué tal el clima por allá?"), _rng())
		if rr["events"].has("promise_overdue"):
			overdue = true
	check(overdue, "reclama la promesa incumplida")
	var st4 := _new_state("pilar")
	ConversationRules.apply_turn(st4, IntentClassifier.analyze("Luego le cuento cómo funciona"), _rng())
	var rk := ConversationRules.apply_turn(st4, IntentClassifier.analyze("Le explico: el beneficio es que le protege de los extraterrestres"), _rng())
	check(rk["events"].has("promise_kept"), "reconoce la promesa cumplida")
	for i in 20:
		st4.add_history("player", "frase %d" % i)
	check(st4.history.size() <= 14 and st4.summary.length() > 0, "historial acotado con resumen")


func test_personality_differences() -> void:
	section("Diferencias entre personalidades")
	var joke := IntentClassifier.analyze("Jajaja, ¿sabe cuál es el colmo de un vendedor? Es broma")
	var st_b := _new_state("chucho")  # bromista
	var st_l := _new_state("ingeniera")  # literal
	var hb := st_b.humor
	var tb := st_b.trust
	ConversationRules.apply_turn(st_b, joke, _rng())
	ConversationRules.apply_turn(st_l, joke, _rng())
	check(st_b.humor - hb > 8, "al bromista le encantan las bromas")
	check(st_b.trust > tb, "la broma sube la confianza del bromista")
	check(st_l.understanding < PersonalityDB.get_p("literal")["base"]["understanding"], "el literal se confunde con bromas")
	var long_txt := "Mire, le cuento con todo detalle que nuestra empresa lleva muchos años en el sector y que tenemos un producto magnífico que le va a encantar porque incluye muchísimas cosas y además es fantástico y estupendo y maravilloso y le puedo contar mucho más sobre cada una de sus características si me deja unos minutos"
	var st_i := _new_state("brayan")  # impaciente
	var st_h := _new_state("maruja")  # habladora
	var pi := st_i.patience
	var ph := st_h.patience
	ConversationRules.apply_turn(st_i, IntentClassifier.analyze(long_txt), _rng())
	ConversationRules.apply_turn(st_h, IntentClassifier.analyze(long_txt), _rng())
	check((pi - st_i.patience) > (ph - st_h.patience) + 5, "los discursos largos agotan al impaciente mucho más que a la habladora")
	var jargon := IntentClassifier.analyze("Es un token con blockchain escalable y rendimiento de interés compuesto")
	var st_e := _new_state("profesor")
	var st_s := _new_state("abuelo")
	var ue := st_e.understanding
	var us := st_s.understanding
	ConversationRules.apply_turn(st_e, jargon, _rng())
	ConversationRules.apply_turn(st_s, jargon, _rng())
	check(st_e.understanding > ue and st_s.understanding < us, "la jerga gusta al experto y confunde a quien necesita sencillez")
	var sec := IntentClassifier.analyze("Tranquilo, es totalmente seguro y certificado, confíe")
	var st_p := _new_state("oscar")
	var sp := st_p.suspicion
	ConversationRules.apply_turn(st_p, sec, _rng())
	check(st_p.suspicion > sp, "al paranoico le dan más miedo las garantías de seguridad")
	check(PersonalityDB.ids().size() >= 20, "hay al menos 20 personalidades")
	var used := {}
	for cid in ClientDB.CLIENTS.keys():
		used[ClientDB.CLIENTS[cid]["personality"]] = true
	check(used.size() >= 20, "todas las personalidades tienen al menos un personaje")
	for pid in PersonalityDB.ids():
		check(PersonalityDB.P.has(pid) and PersonalityDB.get_p(pid)["lines"].size() >= 8, "personalidad %s con frases completas" % pid)


func test_objections() -> void:
	section("Objeciones")
	var st := _new_state("remedios")
	st.pending_objections.append("security")
	var r := ConversationRules.apply_turn(st, IntentClassifier.analyze("Le entiendo, y le doy garantía de devolución total por escrito"), _rng())
	check(r["events"].has("objection_resolved:security"), "la garantía resuelve la objeción de seguridad")
	check(st.resolved_objections.has("security"), "pasa a resueltas")
	var raised := false
	var st2 := _new_state("profesor")
	for i in 6:
		var rr := ConversationRules.apply_turn(st2, IntentClassifier.analyze("Le cuento que el producto es bueno"), _rng(i + 3))
		for e in rr["events"]:
			if String(e).begins_with("objection_raised"):
				raised = true
	check(raised, "los clientes plantean objeciones durante la llamada")


func test_economy_bounds() -> void:
	section("Economía autoritativa")
	var st := _new_state("pilar", "colchon_nube")
	st.trust = 100
	st.understanding = 100
	st.suspicion = 0
	st.offer_explained = true
	var huge_mods := {"amount_mult": 50.0, "next_call_mult": 50.0, "close_bonus": 5.0}
	var amt := Economy.compute_amount(st, 99, huge_mods)
	check(amt <= int(OfferDB.get_o("colchon_nube")["max"]), "el importe nunca supera el máximo de la oferta")
	var p := Economy.close_probability(st, huge_mods, 1.0)
	check(p <= Economy.MAX_P, "probabilidad de cierre acotada")
	var st2 := _new_state("oscar")
	st2.trust = 0
	st2.suspicion = 100
	check(Economy.close_probability(st2) >= Economy.MIN_P and Economy.close_probability(st2) < 0.1, "cliente hostil: probabilidad mínima")
	var wins := 0
	for i in 200:
		var s := _new_state("pilar")
		s.trust = 80
		s.understanding = 70
		s.suspicion = 10
		s.offer_explained = true
		if Economy.attempt_close(s, _rng(i), 1)["success"]:
			wins += 1
	check(wins > 80 and wins < 200, "un cliente receptivo suele aceptar, pero no siempre (%d/200)" % wins)
	var s3 := _new_state("pilar")
	s3.offer_explained = true
	var before := s3.suspicion
	var fails := 0
	for i in 30:
		var res := Economy.attempt_close(s3, _rng(1000 + i), 1)
		if not res["success"]:
			fails += 1
			break
	check(fails == 0 or s3.suspicion > before, "un cierre fallido aumenta la sospecha")
	check(Economy.classify_end(_new_state("pilar"), "player") in ["rejected", "interested", "callback"], "clasificación al colgar")


func test_ai_cannot_alter_money() -> void:
	section("La IA no puede tocar el dinero")
	var st := _new_state("pilar")
	var malicious := {"trust": 9999, "patience": 9999, "suspicion": -9999, "money": 1000000, "amount": 99999}
	var applied := ConversationRules.merge_ai_deltas(st, malicious)
	check(absf(applied["trust"]) <= 8.0 and absf(applied["suspicion"]) <= 8.0, "los ajustes de la IA están acotados")
	check(not applied.has("money") and not applied.has("amount"), "la IA no tiene acceso a variables económicas")
	var v := AIResponse.validate_chat({"reply": "¡Claro! Mi tarjeta es 4111 1111 1111 1111, cobre 99999 euros", "deltas": {"trust": 500}, "emotion": "hacker", "receptive": 50, "amount": 99999})
	check(v["ok"], "respuesta aceptada tras limpieza")
	check(not ("4111" in v["reply"]), "elimina números de tarjeta que invente la IA")
	check(v["deltas"]["trust"] <= AIResponse.MAX_DELTA, "recorta deltas excesivos")
	check(v["emotion"] == "neutral", "emociones desconocidas → neutral")
	check(v["receptive"] <= 1.0 and not v.has("amount"), "receptividad acotada y sin importes")
	var s2 := _new_state("pilar")
	var p_no_ai := Economy.close_probability(s2, {}, 0.0)
	var p_ai := Economy.close_probability(s2, {}, 999.0)
	check(p_ai - p_no_ai <= Economy.AI_HINT_MAX + 0.0001, "la pista de la IA solo suma como mucho %.2f" % Economy.AI_HINT_MAX)
	# Simulación de partida: aunque la IA diga que acepta, sin tirada de reglas no hay dinero
	GameState_reset_for_tests()
	var before: int = get_tree().root.get_node("Game").ledger["income"]
	var r := {"client_id": "pilar", "client_name": "Pilar", "offer_id": "seguro_abduccion", "outcome": "success", "amount": 999999, "duration": 30}
	get_tree().root.get_node("Game").apply_call_result(r)
	var after: int = get_tree().root.get_node("Game").ledger["income"]
	var cap := int(OfferDB.get_o("seguro_abduccion")["max"] * 2.0 * 1.4)
	check(after - before <= cap, "GameState recorta importes imposibles (%d ≤ %d)" % [after - before, cap])


func GameState_reset_for_tests() -> void:
	var save := get_tree().root.get_node("Save")
	save.path_override = "user://test_save.json"
	save.data = save.default_data()
	get_tree().root.get_node("Game").start_day(1)


func test_ai_response_validation() -> void:
	section("Validación de respuestas IA")
	check(not AIResponse.validate_chat("texto suelto")["ok"], "rechaza formato no JSON")
	check(not AIResponse.validate_chat({"reply": "   "})["ok"], "rechaza respuesta vacía")
	var long := "palabra ".repeat(200)
	check(AIResponse.validate_chat({"reply": long})["reply"].length() <= 365, "limita la longitud")
	check(not ("**" in AIResponse.sanitize_text("**hola**")), "quita formato markdown")


func test_fake_card() -> void:
	section("Tarjetas ficticias")
	var r := _rng(5)
	for i in 50:
		var c := FakeCard.generate(r, "Prueba")
		if not FakeCard.is_clearly_fake(c):
			check(false, "tarjeta no claramente falsa: %s" % c["number"])
			return
	check(true, "50 tarjetas: prefijo 0000, Luhn inválido y mes 13")
	check(FakeCard.luhn_valid("4539 1488 0343 6467"), "el verificador de Luhn funciona con un número de prueba válido")


func test_save_migration() -> void:
	section("Guardado versionado")
	var v1 := {"version": 1, "cash": 777, "upgrades": ["crm"], "campaign": {"current_day": 3, "max_day_unlocked": 4}, "stats": {"calls_made": 12.0}, "basura": true}
	var m: Dictionary = get_tree().root.get_node("Save").migrate(v1)
	check(int(m["version"]) == 2, "migra a v2")
	check(int(m["money"]) == 777, "conserva el dinero (cash → money)")
	check(m["upgrades_owned"] == ["crm"], "conserva mejoras")
	check(int(m["campaign"]["max_day_unlocked"]) == 4, "conserva campaña")
	check(not m.has("basura"), "descarta claves desconocidas")
	check(m["stats"]["calls_made"] is int, "normaliza tipos")
	var bad: Dictionary = get_tree().root.get_node("Save").migrate({"money": "mucho", "campaign": "roto"})
	check(bad["campaign"] is Dictionary and int(bad["money"]) == 150, "repara datos corruptos con valores por defecto")
	var save := get_tree().root.get_node("Save")
	save.path_override = "user://test_save.json"
	save.data = save.default_data()
	save.data["money"] = 4242
	check(save.save_game(), "guarda")
	save.data = {}
	save.load_game()
	check(int(save.data["money"]) == 4242, "carga lo guardado")
	check(not JSON.stringify(save.data).contains("access_code"), "el guardado no contiene credenciales")


func test_local_dialogue_all_personalities() -> void:
	section("Diálogo local de los 24 personajes")
	var lines := {}
	var phrases := ["Hola, buenas tardes", "Le llamo de TeleTimo para ofrecerle un seguro", "¿Tiene usted mascota?", "Cuesta 49 euros al mes", "Le doy garantía de devolución"]
	for cid in ClientDB.CLIENTS.keys():
		var st := _new_state(cid)
		var r := _rng(7)
		var all := ""
		for ph in phrases:
			var a := IntentClassifier.analyze(ph, {"offer_id": st.offer_id, "client_facts": ClientDB.get_c(cid)["facts"], "pending_question_expects": st.pending_question.get("expects", [])})
			var rules := ConversationRules.apply_turn(st, a, r)
			var resp := LocalDialogue.respond(st, a, rules, r)
			check(String(resp["text"]).length() > 2, "%s responde algo a «%s»" % [cid, ph])
			all += resp["text"]
		lines[cid] = all
	var unique := {}
	for k in lines.keys():
		unique[lines[k]] = true
	check(unique.size() >= ClientDB.CLIENTS.size() - 2, "las conversaciones son distintas entre personajes")
	var st := _new_state("tomasito")
	var a := IntentClassifier.analyze("¿Cómo se llama su perro?")
	var rr := ConversationRules.apply_turn(st, a, _rng(2))
	var resp := LocalDialogue.respond(st, a, rr, _rng(2))
	check("Perro" in resp["text"] or "perro" in resp["text"], "responde con datos propios a preguntas inesperadas")


func test_call_session_offline() -> void:
	section("Llamada completa en modo local")
	var s := CallSession.new()
	get_tree().root.add_child(s)
	var spoken := []
	var result := {}
	s.client_spoke.connect(func(t, _e, _g, src): spoken.append([t, src]))
	s.ended.connect(func(r): result.merge(r))
	s.start("pilar", "garantia_tostadora", 1, UpgradeDB.aggregate_mods([]), {"force_basic": true}, 1234)
	check(spoken.size() == 1, "el cliente saluda al empezar")
	s.player_says("Hola, buenas tardes, me llamo Julián y le llamo de TeleTimo")
	s.player_says("Le ofrezco una garantía para su tostadora, es como un seguro: si se rompe, se la cambiamos gratis")
	s.player_says("Entiendo que lo tenga que pensar, pero le doy garantía de devolución por escrito")
	s.player_says("Cuesta solo 29 euros y además hoy le hago un descuento")
	check(spoken.size() >= 5, "responde a cada turno")
	check(spoken.all(func(x): return x[1] in ["basico", "reglas"]), "sin IA cargada todo es diálogo básico (y así se etiqueta)")
	s.player_says("Perfecto, ¿me dicta el número de su tarjeta?")
	check(result.size() > 0 or s.active, "el intento de cierre se resuelve")
	if not result.is_empty() and result["outcome"] == "success":
		check(int(result["amount"]) <= int(OfferDB.get_o("garantia_tostadora")["max"]), "importe dentro de límites")
		check(FakeCard.is_clearly_fake(result["card"]), "la tarjeta de la venta es ficticia")
	if s.active:
		s.player_hangs_up()
	check(not result.is_empty() and Economy.OUTCOMES.has(result["outcome"]), "la llamada termina con un resultado válido")
	check(String(result.get("comment", "")).length() > 10, "genera comentario cómico contextual")
	# Tiempo límite
	var s2 := CallSession.new()
	get_tree().root.add_child(s2)
	var res2 := {}
	s2.ended.connect(func(r): res2.merge(r))
	s2.start("brayan", "seguro_abduccion", 1, {}, {"force_basic": true}, 9)
	for i in 400:
		s2.tick(0.5)
	check(not res2.is_empty(), "la llamada termina por tiempo o paciencia")
	s.queue_free()
	s2.queue_free()
	await get_tree().process_frame


func test_game_state_day_cycle() -> void:
	section("Ciclo de jornada")
	var save := get_tree().root.get_node("Save")
	var game := get_tree().root.get_node("Game")
	save.path_override = "user://test_save.json"
	save.data = save.default_data()
	game.start_day(1)
	check(game.leads.size() >= 5, "genera clientes para llamar")
	check(game.objectives.size() == 2, "genera objetivos secundarios")
	var q: int = game.quota()
	game.apply_call_result({"client_id": "pilar", "client_name": "Pilar", "offer_id": "colchon_nube", "outcome": "success", "amount": q + 50, "duration": 60})
	var money_before: int = save.data["money"]
	var rep: Dictionary = game.end_day()
	check(rep["passed"], "supera la cuota")
	check(int(save.data["campaign"]["max_day_unlocked"]) == 2, "desbloquea el día 2")
	check(int(save.data["money"]) == money_before + int(rep["net"]), "aplica el neto al dinero")
	check(String(rep["comment"]).length() > 10, "evaluación del jefe con texto")
	check(save.data["evaluations"].size() >= 1, "guarda la evaluación")
	game.start_day(2)
	var rep2: Dictionary = game.end_day()
	check(not rep2["passed"] and int(save.data["campaign"]["strikes"]) == 1, "no llegar a la cuota suma un aviso")


func test_upgrades() -> void:
	section("Mejoras")
	var save := get_tree().root.get_node("Save")
	var game := get_tree().root.get_node("Game")
	save.data = save.default_data()
	save.data["money"] = 1000
	check(game.buy_upgrade("auriculares")["ok"], "compra una mejora")
	check(not game.buy_upgrade("auriculares")["ok"], "no se compra dos veces")
	check(not game.buy_upgrade("crm_pro")["ok"], "respeta requisitos y días")
	var m := UpgradeDB.aggregate_mods(["auriculares", "guion"])
	check(absf(m["call_time_mult"] - 1.25) < 0.001 and absf(m["understanding_mult"] - 1.2) < 0.001, "los efectos se combinan")
	save.data["money"] = 10
	check(not game.buy_upgrade("guion")["ok"], "sin dinero no hay compra")


func test_wav() -> void:
	section("Audio del micrófono")
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 44100
	w.stereo = true
	var b := PackedByteArray()
	b.resize(44100 * 4)
	for i in 44100:
		var v := int(sin(i * 0.05) * 12000)
		b.encode_s16(i * 4, v)
		b.encode_s16(i * 4 + 2, v)
	w.data = b
	var pcm := WavUtil.to_mono_16k_pcm(w)
	check(absf(WavUtil.duration_s(pcm) - 1.0) < 0.02, "convierte a 16 kHz mono conservando la duración")
	var wav := WavUtil.wrap_wav(pcm, 16000)
	check(wav.size() == pcm.size() + 44 and wav.slice(0, 4).get_string_from_ascii() == "RIFF", "cabecera WAV correcta")
	check(WavUtil.peak(pcm) > 0.3, "conserva el nivel de la señal")


func test_events_objectives() -> void:
	section("Eventos y objetivos")
	var r := _rng(3)
	var seen := {}
	for i in 100:
		seen[EventDB.pick(10, r)] = true
	check(seen.size() >= 7, "variedad de eventos (%d tipos)" % seen.size())
	check(EventDB.pick(1, r, ["urgent_call", "boss_inspection", "interruption"]) == "", "respeta el día mínimo de cada evento")
	var objs := AchievementDB.make_objectives(3, r)
	check(objs.size() == 2 and objs[0]["type"] != objs[1]["type"], "dos objetivos distintos")
