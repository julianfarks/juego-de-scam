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
	test_free_proposals()
	test_economy_free_prices()
	test_transactions_and_balance()
	await test_timeouts_never_hang()
	test_schema_order()
	test_adaptive_limits()
	await test_ai_call_with_fake_engine()
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
	st.stated_price = 999999
	st.quantity = 99
	var amt := Economy.compute_amount(st)
	check(amt <= int(st.budget * Economy.AMOUNT_CAP_X_BUDGET), "el importe nunca supera el tope según el presupuesto (%d)" % amt)
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
		s.stated_price = 30
		if Economy.attempt_close(s, _rng(i), 1)["success"]:
			wins += 1
	check(wins > 80 and wins < 200, "un cliente receptivo suele aceptar, pero no siempre (%d/200)" % wins)
	var s3 := _new_state("pilar")
	s3.offer_explained = true
	s3.stated_price = 30
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
	var cap := int(ClientDB.budget("pilar", 1) * Economy.AMOUNT_CAP_X_BUDGET)
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
	check(int(m["version"]) == 3, "migra a la versión actual (v3)")
	var v2 := {"version": 2, "money": 500, "transactions": [{"day": 1, "client": "Pilar", "offer": "Club VIP", "amount": 40, "card": "0000"}]}
	var m2: Dictionary = get_tree().root.get_node("Save").migrate(v2)
	var t0: Dictionary = m2["transactions"][0]
	check(t0["proposal"] == "Club VIP" and int(t0["quantity"]) == 1 and int(t0["commission"]) == 40 and t0["status"] == "completada", "v2→v3: las transacciones antiguas se conservan con el nuevo formato")
	check(m2["movements"] is Array, "v2→v3: añade el registro de movimientos")
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
	s.start("pilar", 1, UpgradeDB.aggregate_mods([]), {"force_basic": true}, 1234)
	check(spoken.size() == 1, "el cliente saluda al empezar")
	s.player_says("Hola, buenas tardes, me llamo Julián y le llamo de TeleTimo")
	s.player_says("Le ofrezco una garantía para su tostadora, es como un seguro: si se rompe, se la cambiamos gratis")
	s.player_says("Entiendo que lo tenga que pensar, pero le doy garantía de devolución por escrito")
	s.player_says("Cuesta solo 29 euros y además hoy le hago un descuento")
	check(spoken.size() >= 5, "responde a cada turno")
	check(spoken.all(func(x): return x[1] == "basico"), "sin IA cargada todo es diálogo básico (y así se etiqueta)")
	s.player_says("Perfecto, ¿me dicta el número de su tarjeta?")
	check(result.size() > 0 or s.active, "el intento de cierre se resuelve")
	if not result.is_empty() and result["outcome"] == "success":
		check(int(result["amount"]) == 29 * maxi(1, int(result["quantity"])), "importe = precio dicho × cantidad")
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
	s2.start("brayan", 1, {}, {"force_basic": true}, 9)
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
	var money_before: int = save.data["money"]
	game.apply_call_result({"client_id": "profesor", "client_name": "Profesor", "offer_name": "Colchón de nube", "outcome": "success", "amount": q + 50, "unit_price": q + 50, "quantity": 1, "duration": 60})
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


# ------------------------------------------------------------------ Propuestas libres

func test_free_proposals() -> void:
	section("Propuestas libres (reglas)")
	var t := Proposal.tags_for("Buenas, tengo un queso artesanal y además se lo llevamos a domicilio")
	check(t.has("comida") and t.has("servicios"), "detecta categorías de una propuesta inventada (%s)" % str(t))
	check(Proposal.tags_for("le vendo hierbas medicinales para dormir").has("salud"), "hierbas medicinales → salud")
	check(Proposal.tags_for("un servicio de jardinería para su casa").has("servicios"), "jardinería → servicios")
	check(Proposal.quantity_from("le dejo dos cajas por 20 pesos cada una") == 2, "cantidad en letra («dos cajas»)")
	check(Proposal.quantity_from("son 3 kilos a 15 pesos") == 3, "cantidad en cifra («3 kilos»)")
	check(Proposal.quantity_from("media docena de frascos") == 6, "«media docena» = 6")
	check(Proposal.quantity_from("cuesta 30 pesos") == 0, "sin cantidad explícita → 0")
	check(Proposal.quantity_from("99 cajas") == Proposal.MAX_QUANTITY, "cantidad acotada")
	check(Proposal.price_from("si se lleva dos piezas se las dejo en 18 pesos cada una") == 18, "precio: el número pegado a la moneda, no la cantidad")
	check(Proposal.price_from("Cuesta veinte pesos la pieza") == 20, "precio en letra")
	check(Proposal.price_from("son 3 kilos a 15") == 15, "sin moneda: descarta la cantidad")
	check(Proposal.price_from("solo $25 al mes") == 25, "precio con símbolo $")
	check(Proposal.price_from("le dejo tres botes por 12 pesos cada uno") == 12, "tres botes por 12 pesos → 12")
	check(Proposal.price_from("no tiene precio") == 0, "sin número → sin precio")
	check(Proposal.price_from("Entonces, ¿le preparo las dos piezas?") == 0, "«¿…las dos piezas?» es una cantidad, no un precio")
	check(Proposal.quantity_from("¿le preparo las dos piezas?") == 2, "cantidad aunque vaya pegada a «?»")
	check(Proposal.is_action_label("Confirmar el pago") and not Proposal.is_action_label("Queso artesanal"), "detecta etiquetas de acción")
	# Memoria de la propuesta y cambio de propuesta sin reiniciar
	var st := _new_state("pilar")
	check(st.set_proposal("queso artesanal de cabra"), "registra la propuesta")
	check(not st.set_proposal("Queso artesanal de cabra"), "no duplica si no cambia")
	check(st.set_proposal("queso artesanal con entrega a domicilio") and st.proposal_log.size() == 2, "cambia la propuesta y guarda el historial")
	check(st.proposal_label().begins_with("Queso"), "etiqueta legible de la propuesta")
	check(not st.set_proposal("Confirmar la compra de los dos quesos") and st.proposal.begins_with("Queso"), "una acción no sustituye a la propuesta")
	for meta in ["Despedida y colgar", "Esperando información", "Recordar la primera oferta", "Nada", "Información sobre si tengo plantas", "¡Tráeme varias! ¡Quiero hacer una fiesta de quesos!", "Dime qué vendes", "¡Perfecto! ¡Listo para recibir mis quesos!"]:
		check(not st.set_proposal(meta), "«%s» no es una propuesta" % meta)
	st.add_history("player", "Le ofrezco un servicio de jardinería a domicilio")
	check(not st.set_proposal("Seguro de coches"), "no se registra algo que el vendedor nunca ofreció")
	check(st.set_proposal("Servicio de jardinería a domicilio"), "sí se registra lo que el vendedor ofreció")
	# Negociar a la baja no es contradicción; subir el precio sí
	var rng := _rng(3)
	var a1 := IntentClassifier.analyze("Cuesta 50 pesos")
	ConversationRules.apply_turn(st, a1, rng, {})
	var a2 := IntentClassifier.analyze("Bueno, para usted lo dejo en 40 pesos")
	var r2 := ConversationRules.apply_turn(st, a2, rng, {})
	check(st.stated_price == 40 and st.contradictions.is_empty() and r2["events"].has("price_lowered"), "bajar el precio es negociar")
	var a3 := IntentClassifier.analyze("En realidad cuesta 70 pesos")
	ConversationRules.apply_turn(st, a3, rng, {})
	check(st.contradictions.size() == 1 and st.stated_price == 70, "subir el precio cuenta como contradicción")
	check(st.price_history.size() == 3, "historial de precios")


func test_economy_free_prices() -> void:
	section("Economía con precios libres")
	var st := _new_state("pilar")
	st.trust = 80
	st.understanding = 70
	st.suspicion = 5
	check(Economy.missing_for_close(st) == "propuesta", "sin propuesta no se puede cobrar")
	st.set_proposal("queso artesanal")
	check(Economy.missing_for_close(st) == "precio", "sin precio no se puede cobrar")
	var res := Economy.attempt_close(st, _rng(1), 1)
	check(not res["success"] and res["missing"] == "precio" and st.close_attempts == 0, "pedir el pago sin precio: el cliente pregunta el precio (no cuenta como intento)")
	st.stated_price = 20
	var p_cheap := Economy.close_probability(st)
	st.stated_price = st.budget * 3
	var p_exp := Economy.close_probability(st)
	check(p_cheap > p_exp + 0.3, "un precio muy por encima del presupuesto casi nunca se acepta (%.2f vs %.2f)" % [p_cheap, p_exp])
	st.stated_price = 15
	st.quantity = 3
	check(Economy.compute_amount(st) == 45, "importe = precio × cantidad")
	check(Economy.commission(100, {}) == int(100 * Economy.COMMISSION_RATE), "comisión base")
	check(Economy.commission(100, {"amount_mult": 1.15}) > Economy.commission(100, {}), "las mejoras suben la comisión")
	check(ClientDB.budget("profesor", 1) > ClientDB.budget("tomasito", 1), "clientes con presupuestos distintos")
	check(ClientDB.budget("pilar", 5) > ClientDB.budget("pilar", 1), "el presupuesto crece con los días")
	check(Proposal.affinity("remedios", ["seguro"]) > Proposal.affinity("remedios", ["tecnologia"]), "a cada cliente le gustan cosas distintas")


func test_transactions_and_balance() -> void:
	section("Transacciones ficticias y saldo")
	var save := get_tree().root.get_node("Save")
	var game := get_tree().root.get_node("Game")
	save.path_override = "user://test_save.json"
	save.data = save.default_data()
	game.start_day(1)
	var bal0: int = save.data["money"]
	game.apply_call_result({"client_id": "pilar", "client_name": "Pilar Quizás", "offer_name": "Queso artesanal con entrega", "outcome": "success", "outcome_text": "Transacción ficticia completada",
		"amount": 60, "unit_price": 20, "quantity": 3, "commission": 30, "card": {"masked": "0000 •••• •••• 1234"}, "duration": 90, "turns": 8})
	var tx: Dictionary = save.data["transactions"][-1]
	check(tx["proposal"] == "Queso artesanal con entrega" and int(tx["unit_price"]) == 20 and int(tx["quantity"]) == 3 and int(tx["amount"]) == 60, "registra propuesta, precio, cantidad e importe")
	check(int(tx["commission"]) == 30 and tx["status"] == "completada" and int(tx["day"]) == 1, "registra comisión, estado y jornada")
	check(int(save.data["money"]) == bal0 + 30, "el saldo sube al momento con la comisión")
	check(save.data["movements"][-1]["kind"] == "comision" and int(save.data["movements"][-1]["amount"]) == 30, "queda un movimiento de comisión")
	check(int(game.ledger["income"]) == 60, "la venta cuenta para la cuota")
	game.add_fine(15, "Multa de prueba")
	game.add_bonus(10, "Bono de prueba")
	check(int(save.data["money"]) == bal0 + 25, "multas y bonos se aplican al saldo")
	game.apply_call_result({"client_id": "brayan", "client_name": "Brayan", "offer_name": "Wifi para plantas", "outcome": "rejected", "amount": 0, "duration": 40})
	check(save.data["transactions"].size() == 1, "una llamada sin venta no crea transacción")
	var before_end: int = save.data["money"]
	var rep: Dictionary = game.end_day()
	var gastos := 0
	for e in rep["expenses"]:
		gastos += int(e["amount"])
	check(gastos > 0 and save.data["movements"].filter(func(m): return m["kind"] == "gasto").size() == rep["expenses"].size(), "los gastos del día se registran como movimientos")
	check(int(save.data["money"]) == before_end + int(rep["rewards"]) + int(rep["day_bonus"]) - gastos, "al cerrar la jornada: recompensas y bono menos gastos")
	check(int(rep["net"]) == int(save.data["money"]) - bal0, "el neto del día cuadra con el saldo")
	save.save_game()
	var n_mov: int = save.data["movements"].size()
	save.data = {}
	save.load_game()
	check(save.data["movements"].size() == n_mov and save.data["transactions"].size() == 1, "el guardado conserva transacciones y movimientos")


# ------------------------------------------------------------------ Tiempos límite reales

class FakeStream:
	extends RefCounted
	signal never
	var tokens: Array = []
	var hang_after := -1      # -1 = no se cuelga; 0 = no da ni el primer token
	var i := 0
	func next_token():
		if hang_after >= 0 and i >= hang_after:
			await never
		await Engine.get_main_loop().process_frame
		if i >= tokens.size():
			return null
		i += 1
		return tokens[i - 1]


class FakeChat:
	extends RefCounted
	var replies: Array = []        # textos JSON por orden
	var hang := -2                 # índice de la petición que se cuelga (-2 = ninguna)
	var calls := 0
	var stopped := 0
	var history: Array = []
	var served := 0
	func _stream_for(_m) -> FakeStream:
		var s := FakeStream.new()
		if calls == hang:
			s.hang_after = 0
			calls += 1
			return s
		var text: String = replies[mini(served, replies.size() - 1)] if not replies.is_empty() else ""
		for ch in text:
			s.tokens.append(ch)
		calls += 1
		served += 1
		return s
	func ask(msg):
		history.append(msg)
		return _stream_for(msg)
	func complete(msgs, _cfg):
		history.append(msgs)
		return _stream_for(msgs)
	func stop_generation():
		stopped += 1


func _reply(dice: String, propuesta := "", interes := 5, emo := "neutral") -> String:
	return JSON.stringify({"respuesta": dice, "emocion": emo, "efecto": "igual", "interes": interes, "duda": "", "propuesta": propuesta, "cuelga": false})


func test_timeouts_never_hang() -> void:
	section("Tiempos límite reales (la IA no puede dejar el juego «pensando»)")
	var t0 := Time.get_ticks_msec()
	var never := FakeStream.new()
	never.hang_after = 0
	var r := await Timed.run(func(): return await never.next_token(), 300)
	check(r["timeout"] and Time.get_ticks_msec() - t0 < 2000, "una operación que nunca termina se corta al llegar al límite")
	var ok := await Timed.run(func(): return 42, 1000)
	check(ok["ok"] and ok["value"] == 42, "una operación normal devuelve su valor")
	var chat := FakeChat.new()
	var s1 := FakeStream.new()
	s1.hang_after = 0
	var a := await AIStream.read(chat, s1, Callable(), {}, {"first": 300, "stall": 300, "total": 2000})
	check(not a["ok"] and a["error"] == "sin_primer_token" and chat.stopped == 1, "sin primer token → error explícito y se detiene la generación")
	var s2 := FakeStream.new()
	s2.tokens = ["{", "\"r", "e"]
	s2.hang_after = 2
	var b := await AIStream.read(chat, s2, Callable(), {}, {"first": 300, "stall": 300, "total": 2000})
	check(not b["ok"] and b["error"] == "atasco" and b["tokens"] == 2, "atasco a mitad de respuesta → error explícito")
	var s3 := FakeStream.new()
	for ch in _reply("Hola"):
		s3.tokens.append(ch)
	var c := await AIStream.read(chat, s3)
	check(c["ok"] and JSON.parse_string(c["text"]) is Dictionary and c["first_ms"] >= 0, "respuesta normal completa con tiempo del primer token")
	var s4 := FakeStream.new()
	s4.hang_after = 0
	var cancel := {"cancel": false}
	var t1 := Time.get_ticks_msec()
	var box := {"d": null}
	var runner := func(): box["d"] = await AIStream.read(chat, s4, Callable(), cancel, {"first": 10000})
	runner.call()
	await get_tree().process_frame
	cancel["cancel"] = true
	while box["d"] == null and Time.get_ticks_msec() - t1 < 5000:
		await get_tree().process_frame
	var d: Dictionary = box["d"] if box["d"] != null else {"error": ""}
	check(d["error"] == "cancelado" and Time.get_ticks_msec() - t1 < 2000, "Cancelar corta la espera al momento")


func test_schema_order() -> void:
	section("Orden del JSON de la IA")
	var txt := JSON.stringify(Persona.schema(), "", false)
	check(txt.find("respuesta") < txt.find("cuelga") and txt.find("respuesta") < txt.find("duda"), "«respuesta» va la PRIMERA en el esquema (la frase se ve y se oye mientras la IA sigue)")
	check(JSON.stringify(Persona.schema()).find("respuesta") > JSON.stringify(Persona.schema()).find("cuelga"), "(comprobación: con el orden alfabético por defecto iría al final)")


func test_adaptive_limits() -> void:
	section("Límites de tiempo adaptados a la velocidad del dispositivo")
	var brain := get_tree().root.get_node("Brain")
	var old_p: float = brain.prompt_tps
	var old_g: float = brain.gen_tps
	brain.prompt_tps = 200.0
	brain.gen_tps = 20.0
	var fast: Dictionary = brain.limits_for(3500)
	check(fast["first"] == 60000, "móvil rápido: 60 s para el primer token")
	brain.prompt_tps = 5.0
	brain.gen_tps = 1.4
	var slow: Dictionary = brain.limits_for(3500)
	check(slow["first"] > 300000 and slow["first"] <= 420000, "dispositivo lento: más margen, pero con tope (%d s)" % (slow["first"] / 1000))
	check(slow["total"] > slow["first"] and slow["stall"] == 25000, "límite total y de atasco")
	brain.record_speed(3500, 20000, 100, 40000)
	check(brain.prompt_tps > 5.0, "la velocidad medida se actualiza con respuestas reales")
	brain.prompt_tps = old_p
	brain.gen_tps = old_g


func test_ai_call_with_fake_engine() -> void:
	section("Llamada con IA: fases, error, reintento y propuesta libre")
	# 1) El motor se cuelga en el saludo → error explícito, sin respuesta inventada
	var s := CallSession.new()
	get_tree().root.add_child(s)
	var fake := FakeChat.new()
	fake.replies = [_reply("¿Diga? ¿Quién es?"), _reply("¿Queso? ¿Y qué tiene de especial?", "queso artesanal", 4),
		_reply("Ah, con entrega a casa. ¿Y cuánto cuesta?", "queso artesanal con entrega a domicilio", 5),
		_reply("Veinte pesos... vale, me lo quedo.", "queso artesanal con entrega a domicilio, 20 pesos", 8, "contento")]
	fake.hang = 0
	s.chat_factory = func(_p): return fake
	var phases := []
	var errs := []
	var spoken := []
	var result := {}
	s.phase_changed.connect(func(p): phases.append(p))
	s.ai_error.connect(func(m, c): errs.append([m, c]))
	s.client_spoke.connect(func(t, _e, _g, src): spoken.append([t, src]))
	s.ended.connect(func(r): result.merge(r))
	# límite corto para la prueba (flag first_token_ms)
	s.start("chucho", 1, {}, {"day": 1, "first_token_ms": 300}, 7)
	var t0 := Time.get_ticks_msec()
	while s.phase != "error" and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	check(s.phase == "error" and errs.size() == 1, "si la IA no responde, la llamada pasa a «error» (no se queda pensando)")
	check(spoken.is_empty(), "no se inventa ninguna respuesta del cliente")
	check(phases.has("preparando") and phases.has("pensando"), "fases visibles: preparando → pensando → error")
	# 2) Reintentar: conversación nueva y responde
	await s.retry()
	check(s.phase == "listo" and spoken.size() == 1 and spoken[0][1] == "ia", "Reintentar recupera la llamada sin reiniciar el juego")
	# 3) Propuesta libre que cambia a mitad de llamada
	await s.player_says("Buenas, tengo un queso artesanal que le va a encantar")
	check(s.st.proposal.to_lower().contains("queso"), "el cliente entiende una propuesta inventada")
	await s.player_says("Y además se lo llevamos a domicilio sin coste")
	check(s.st.proposal.to_lower().contains("entrega") and s.st.proposal_log.size() == 2, "la propuesta cambia sin reiniciar la conversación")
	check(s.st.tags.has("comida") and s.st.tags.has("servicios"), "las reglas detectan qué se vende (%s)" % str(s.st.tags))
	await s.player_says("Cuesta 20 pesos")
	check(s.st.stated_price == 20, "el precio lo extraen las reglas de la frase del jugador")
	check(fake.history.size() >= 4, "cada turno se envía a la IA")
	var last_msg := str(fake.history[-1])
	check(last_msg.contains("cuesta 20"), "la memoria del juego (precio) se pasa a la IA en las notas")
	# 4) Cierre: lo deciden las reglas
	s.st.trust = 95.0
	s.st.understanding = 90.0
	s.st.suspicion = 0.0
	s.st.pending_objections.clear()
	var tries := 0
	while s.active and tries < 6:
		await s.attempt_close()
		tries += 1
	if not result.is_empty() and result["outcome"] == "success":
		check(int(result["amount"]) == 20 and int(result["unit_price"]) == 20 and String(result["offer_name"]).to_lower().contains("queso"), "la venta registra la propuesta y el precio dicho")
		check(int(result["commission"]) == int(20 * Economy.COMMISSION_RATE), "comisión calculada por reglas")
	else:
		check(not result.is_empty() or s.active, "el cierre se resuelve por reglas")
	if s.active:
		s.player_hangs_up()
	check(not result.is_empty() and s.phase == "terminada", "la llamada termina con resultado y fase «terminada»")
	s.queue_free()
	# 5) Error en mitad de la llamada → seguir sin IA (elección del jugador, etiquetada)
	var s2 := CallSession.new()
	get_tree().root.add_child(s2)
	var fake2 := FakeChat.new()
	fake2.replies = [_reply("¿Sí? Dígame.")]
	fake2.hang = 1
	s2.chat_factory = func(_p): return fake2
	var spoken2 := []
	s2.client_spoke.connect(func(t, _e, _g, src): spoken2.append(src))
	s2.start("pilar", 1, {}, {"day": 1, "first_token_ms": 300}, 8)
	while s2.phase != "listo" and s2.phase != "error":
		await get_tree().process_frame
	await s2.player_says("Le llamo para ofrecerle unas hierbas medicinales")
	check(s2.phase == "error", "fallo en un turno → error recuperable")
	s2.continue_basic()
	check(s2.mode == "basico" and spoken2[-1] == "basico" and s2.phase == "listo", "«Seguir sin IA» responde con el diálogo básico, etiquetado")
	s2.player_hangs_up()
	s2.queue_free()
	await get_tree().process_frame
