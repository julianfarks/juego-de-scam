class_name LocalDialogue
extends RefCounted
## Motor de diálogo LOCAL (sin conexión). No es generativo: combina reglas,
## memoria de la llamada, intención detectada, personalidad y plantillas con huecos
## para construir respuestas contextuales. El juego lo identifica siempre como
## "Diálogo local" para no confundirlo con la IA generativa remota.

const QUESTION_TOPICS := {
	"job": ["a que se dedica", "trabaja", "su trabajo", "profesion", "en que trabaja"],
	"pet": ["mascota", "perro", "gato", "animal"],
	"name": ["como se llama", "su nombre", "con quien hablo", "quien es usted"],
	"city": ["donde vive", "de donde es", "de que ciudad", "su ciudad", "donde esta"],
	"hobby": ["que le gusta", "hobby", "tiempo libre", "aficion", "que hace para divertirse"],
	"family": ["familia", "hijos", "nietos", "esposa", "esposo", "pareja"],
	"how_are_you": ["como esta", "que tal esta", "como le va", "como se encuentra"],
	"weather": ["clima", "tiempo hace", "llueve", "calor", "frio"],
	"interest": ["le interesa", "le gustaria", "que le parece", "quiere", "acepta", "se anima"],
	"money": ["cuanto gana", "cuanto dinero", "tiene dinero", "ahorros", "su sueldo"],
}

const MISHEARD := ["patata", "canguro", "orquesta", "pato", "fontanero", "flamenco", "submarino", "tortilla", "pingüino", "acordeón"]

const CLIENT_QUESTIONS := {
	"who": {"text": ["¿Y usted quién es exactamente?", "¿De qué empresa me dice que llama?"], "expects": ["introduce", "honesty"]},
	"what": {"text": ["¿Pero qué es lo que vende?", "A ver, ¿qué me está ofreciendo?"], "expects": ["offer_pitch", "benefit", "simple_explanation"]},
	"price": {"text": ["¿Y eso cuánto cuesta?", "¿Cuánto me va a costar la broma?"], "expects": ["price", "discount"]},
	"gain": {"text": ["¿Y qué gano yo con eso?", "¿Para qué me sirve a mí?"], "expects": ["benefit", "drama_hook", "competitive_hook"]},
	"guarantee": {"text": ["¿Y si no me gusta, qué?", "¿Me devuelven el dinero si sale mal?"], "expects": ["guarantee", "honesty"]},
	"why_me": {"text": ["¿Y por qué me llama a mí?", "¿Cómo consiguió mi número?"], "expects": ["flattery", "honesty", "introduce", "personal"]},
}


static func greeting(st: ConversationState, rng: RandomNumberGenerator) -> String:
	return PersonalityDB.line(st.personality_id, "greet", rng)


## Construye la respuesta del cliente a un turno del jugador.
static func respond(st: ConversationState, a: Dictionary, rules: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Dictionary:
	var pid := st.personality_id
	var c := ClientDB.get_c(st.client_id)
	var facts: Dictionary = c["facts"]
	var events: Array = rules["events"]
	var intents: Dictionary = a["intents"]
	var parts: Array[String] = []
	var emotion := st.emotion()
	var gesture := ""

	if rules.get("hangup", "") != "":
		return {"text": PersonalityDB.line(pid, "hangup", rng), "emotion": "angry", "gesture": "hangup"}

	# 1) Lo más urgente: contradicciones e insultos
	if events.has("contradiction"):
		var last: Dictionary = st.contradictions[-1]
		parts.append(_pick(rng, [
			"Un momento: antes me dijo %d y ahora %d. ¿En qué quedamos?" % [last["a"], last["b"]],
			"¿%d? Hace un rato eran %d. Aquí hay algo raro." % [last["b"], last["a"]],
			"Eso no cuadra: primero %d, luego %d. Lo tengo apuntado." % [last["a"], last["b"]],
		]))
		emotion = "distrust"
		gesture = "point"
	elif intents.has("insult"):
		parts.append(_pick(rng, ["¡Oiga! A mí no me hable así.", "¿Perdone? Qué falta de respeto.", "Uy, qué maleducado. Una más y cuelgo."]))
		emotion = "angry"
		gesture = "angry"
	elif intents.has("pressure"):
		parts.append(_pick(rng, ["¿Me está amenazando? No me gusta nada ese tono.", "A mí nadie me obliga a nada.", "Uy, ¿y esas prisas y amenazas? Mala señal."]))
		emotion = "distrust"

	# 2) Rarezas de personalidad que dominan el turno
	if parts.is_empty():
		if events.has("misinterpreted"):
			var words: Array = String(a["norm"]).strip_edges().split(" ", false)
			var long_words := words.filter(func(w): return w.length() >= 5)
			var w: String = long_words[rng.randi() % long_words.size()] if not long_words.is_empty() else "eso"
			parts.append("¿Ha dicho «%s»? Yo entendí «%s». ¿Qué tiene que ver un %s con esto?" % [w, MISHEARD[rng.randi() % MISHEARD.size()], MISHEARD[rng.randi() % MISHEARD.size()]])
			emotion = "confused"
			gesture = "head_scratch"
		elif events.has("literal_confused"):
			parts.append(PersonalityDB.line(pid, "quirk", rng) if rng.randf() < 0.5 else PersonalityDB.line(pid, "confused", rng))
			emotion = "confused"
		elif events.has("too_long"):
			parts.append(_pick(rng, ["¡Resuma, por favor! Me he perdido en el segundo párrafo.", "Demasiado largo. En una frase.", "Bla, bla, bla… ¿al grano?"]))
			emotion = "angry"
		elif events.has("too_complex"):
			parts.append(_pick(rng, ["Uy, palabras muy difíciles. ¿Me lo dice más fácil?", "No entendí nada. Explíquemelo como a mi nieto."]))
			emotion = "confused"
			gesture = "head_scratch"

	# 3) Respuesta a lo que preguntó el jugador
	if parts.is_empty() and a["is_question"] and not intents.has("ask_payment"):
		var ans := _answer_question(st, a, facts, rng)
		if ans != "":
			parts.append(ans)

	# 4) Reacción a la intención principal
	if parts.is_empty():
		parts.append(_react(st, a, events, rng))

	# 5) Objeciones resueltas / nuevas
	for e in events:
		if String(e).begins_with("objection_resolved:"):
			parts.append(_pick(rng, ["Vale, eso me tranquiliza un poco.", "Bueno, eso resuelve mi duda.", "Ah, entonces eso ya no me preocupa."]))
			emotion = "happy"
			break
	for e in events:
		if String(e).begins_with("objection_raised:"):
			var oid := String(e).split(":")[1]
			parts.append(_pick(rng, PersonalityDB.OBJECTIONS[oid]["text"]))
			gesture = "arms_crossed"
			break

	# 6) Memoria: promesas incumplidas, preguntas ignoradas, cifras recordadas
	if events.has("promise_overdue") and parts.size() < 3:
		var pr: Array = st.promises.filter(func(p): return p.get("reminded", false) and not p["fulfilled"])
		if not pr.is_empty():
			parts.append("Por cierto, me dijo «%s»… y sigo esperando." % String(pr[-1]["text"]).strip_edges())
	elif events.has("question_ignored") and parts.size() < 3:
		parts.append("Y no me ha respondido a lo que le pregunté.")
	elif events.has("repetition") and parts.size() < 3:
		parts.append(_pick(rng, ["Eso ya me lo ha dicho.", "Me repite lo mismo una y otra vez."]))
	if not a["numbers"].is_empty() and PersonalityDB.has_quirk(pid, "remembers") and not events.has("contradiction") and parts.size() < 3:
		parts.append("%d. Apuntado." % int(a["numbers"][0]))

	# 7) El cliente hace una pregunta (y la recuerda hasta que se la respondan)
	if st.pending_question.is_empty() and parts.size() < 3 and rng.randf() < _question_chance(st):
		var q := _choose_client_question(st, rng)
		if not q.is_empty():
			st.pending_question = q
			st.client_questions.append(q)
			parts.append(q["text"])

	# 8) Rarezas ambientales
	if parts.size() < 3:
		var quirk_chance := 0.18
		if PersonalityDB.has_quirk(pid, "distracted") or PersonalityDB.has_quirk(pid, "topic_changer") or PersonalityDB.has_quirk(pid, "rambles") or PersonalityDB.has_quirk(pid, "surprise_questions"):
			quirk_chance = 0.4
		if events.has("distracted") or rng.randf() < quirk_chance:
			parts.append(PersonalityDB.line(pid, "quirk", rng))

	var text := " ".join(PackedStringArray(parts.slice(0, 3)))
	text = _style(pid, text, rng)
	return {"text": text, "emotion": emotion, "gesture": gesture}


static func _question_chance(st: ConversationState) -> float:
	var base := 0.3
	if PersonalityDB.has_quirk(st.personality_id, "question_machine"):
		base = 0.75
	if PersonalityDB.has_quirk(st.personality_id, "wants_out"):
		base = 0.15
	return base


static func _choose_client_question(st: ConversationState, rng: RandomNumberGenerator) -> Dictionary:
	var key := ""
	if PersonalityDB.has_quirk(st.personality_id, "surprise_questions") and rng.randf() < 0.5:
		return {"text": PersonalityDB.line(st.personality_id, "quirk", rng), "expects": ["joke", "drama_hook", "benefit", "smalltalk", "personal"], "turn": st.turn, "answered": false}
	if not st.intro_done:
		key = "who"
	elif not st.offer_explained:
		key = "what"
	elif st.stated_price < 0:
		key = "price"
	else:
		key = _pick(rng, ["gain", "guarantee", "why_me"])
	var asked := st.client_questions.map(func(q): return q.get("key", ""))
	if asked.has(key):
		var options := CLIENT_QUESTIONS.keys().filter(func(k): return not asked.has(k))
		if options.is_empty():
			return {}
		key = options[rng.randi() % options.size()]
	var cq: Dictionary = CLIENT_QUESTIONS[key]
	return {"key": key, "text": _pick(rng, cq["text"]), "expects": cq["expects"], "turn": st.turn, "answered": false}


static func _answer_question(st: ConversationState, a: Dictionary, facts: Dictionary, rng: RandomNumberGenerator) -> String:
	var norm: String = a["norm"]
	var c := ClientDB.get_c(st.client_id)
	var topic := ""
	for t in QUESTION_TOPICS.keys():
		for kw in QUESTION_TOPICS[t]:
			if kw in norm:
				topic = t
				break
		if topic != "":
			break
	var first_name: String = String(c["name"]).split(" ")[0]
	if String(c["name"]).begins_with("Don") or String(c["name"]).begins_with("Doña") or String(c["name"]).begins_with("Prof") or String(c["name"]).begins_with("Ing") or String(c["name"]).begins_with("Abuelo") or String(c["name"]).begins_with("Ejecutivo"):
		first_name = String(c["name"])
	match topic:
		"name":
			return "Soy %s. ¿Y usted?" % first_name
		"job":
			return "Trabajo de %s, si tanto le interesa." % facts["job"] if st.trust < 45 else "Pues soy %s. ¡Es apasionante!" % facts["job"]
		"pet":
			return "Tengo %s." % facts["pet"]
		"city":
			return "Vivo en %s." % facts["city"] if st.suspicion < 60 else "¿Y para qué quiere saber dónde vivo?"
		"hobby":
			return "Me encanta %s." % facts["hobby"]
		"family":
			return "Pues tengo %s." % facts["family"]
		"how_are_you":
			return _pick(rng, ["Bien, hasta que sonó el teléfono.", "Pues tirando, como todos.", "Muy bien, gracias por preguntar."])
		"weather":
			return _pick(rng, ["Aquí hace un día raro, ni frío ni calor.", "Llueve de lado. Normal en %s." % facts["city"]])
		"interest":
			match st.provisional:
				"receptivo":
					return _pick(rng, ["La verdad es que sí, me está convenciendo.", "Puede que sí… cuénteme cómo sería."])
				"hostil":
					return _pick(rng, ["¿Interesarme? Ni un poquito.", "Lo que me interesa es colgar."])
				_:
					return _pick(rng, ["Todavía no lo tengo claro.", "Depende. Convénzame."])
		"money":
			return _pick(rng, ["Eso no es asunto suyo.", "¿Y a usted qué le importa mi dinero?"])
	return ""


static func _react(st: ConversationState, a: Dictionary, events: Array, rng: RandomNumberGenerator) -> String:
	var pid := st.personality_id
	var intents: Dictionary = a["intents"]
	var top: String = a["top"]
	for e in events:
		if String(e).begins_with("disliked:"):
			return PersonalityDB.line(pid, "negative", rng)
	if events.has("paranoid_reassure"):
		return "«Seguro», dice… eso es justo lo que diría alguien que no lo es."
	if events.has("price_lowered"):
		return _pick(rng, ["Mmm, %d ya suena mejor." % st.stated_price, "Eso es más razonable."])
	if events.has("promise_kept"):
		return _pick(rng, ["Vale, por fin me lo explica.", "Ahora sí, gracias por cumplir."])
	match top:
		"greeting":
			if events.has("greeted_again"):
				return "Ya nos hemos saludado, ¿eh?"
			return _pick(rng, ["Hola, hola. ¿Qué quiere?", "Buenas. Le escucho."])
		"introduce":
			return _pick(rng, ["Vale. ¿Y qué quiere de mí su empresa?", "Nunca había oído hablar de ustedes."]) if st.trust < 40 else "Ah, encantado. Siga."
		"offer_pitch":
			if st.understanding < 35:
				return "No sé ni qué es eso que me ofrece. Explíquemelo mejor."
			return _pick(rng, ["Vaya, qué cosa más rara me ofrece.", "Hmm… curioso. ¿Y para qué sirve?"])
		"benefit":
			return PersonalityDB.line(pid, "positive", rng) if st.trust >= 35 else "Eso dicen todos los anuncios."
		"price":
			if st.stated_price > 0:
				if st.stated_price * maxi(1, st.quantity) > st.budget:
					return "¿%d? ¡Eso es carísimo!" % st.stated_price
				return _pick(rng, ["%d… no sé, no sé." % st.stated_price, "Hmm, %d. Me lo pienso." % st.stated_price])
			return "¿Pero cuánto exactamente?"
		"discount":
			return _pick(rng, ["Un descuento siempre suena bien.", "Ah, ¿con rebaja? Eso cambia las cosas."])
		"urgency":
			return _pick(rng, ["¿Y tanta prisa por qué?", "Las prisas no son buenas consejeras."])
		"flattery":
			return _pick(rng, ["Ay, qué cosas dice.", "Halagos aparte… ¿qué vende?"])
		"joke":
			return PersonalityDB.line(pid, "positive", rng) if st.humor >= 45 else "Muy gracioso. ¿Algo más?"
		"empathy":
			return _pick(rng, ["Gracias por entenderlo.", "Bueno, al menos usted escucha."])
		"reassure_security":
			return "Bueno, si usted lo dice…" if st.suspicion < 50 else "Eso habrá que verlo."
		"guarantee":
			return _pick(rng, ["Si hay garantía, la cosa cambia.", "¿Garantía por escrito? Eso me gusta."])
		"social_proof":
			return _pick(rng, ["¿Ah, sí? ¿Y quién más lo tiene?", "Si lo tiene todo el mundo, será por algo."])
		"apology":
			return _pick(rng, ["Disculpas aceptadas.", "Bueno, no pasa nada."])
		"smalltalk", "personal":
			return PersonalityDB.line(pid, "positive", rng) if PersonalityDB.get_p(pid)["likes"].has("smalltalk") else _pick(rng, ["Sí, sí… ¿pero a qué viene eso?", "Muy bien, pero ¿qué quiere?"])
		"answer":
			return PersonalityDB.line(pid, "positive", rng)
		"jargon":
			return PersonalityDB.line(pid, "positive", rng) if PersonalityDB.has_quirk(pid, "challenges") else PersonalityDB.line(pid, "confused", rng)
		"simple_explanation":
			return _pick(rng, ["Ah, vale, ahora lo entiendo mejor.", "Así explicado, sí."])
		"competitive_hook", "drama_hook":
			return PersonalityDB.line(pid, "positive", rng)
		"honesty":
			return _pick(rng, ["Valoro la sinceridad.", "Vaya, un vendedor sincero. Qué raro."])
		"farewell":
			return "¿Ya se va? Bueno."
		"unclear":
			return PersonalityDB.line(pid, "confused", rng)
		"yes":
			return _pick(rng, ["¿Sí qué?", "Vale, ¿y?"])
		"no":
			return _pick(rng, ["¿No qué?", "Ah, bueno."])
	# Si nada encaja, reacciona según cómo va la llamada
	if st.trust >= 55:
		return PersonalityDB.line(pid, "positive", rng)
	if st.suspicion >= 60:
		return PersonalityDB.line(pid, "negative", rng)
	return PersonalityDB.line(pid, "confused", rng)


static func close_reply(st: ConversationState, success: bool, rng: RandomNumberGenerator) -> String:
	if success:
		return PersonalityDB.line(st.personality_id, "accept", rng) + " Le dicto los números de mi tarjeta… de mentira."
	var t := PersonalityDB.line(st.personality_id, "refuse", rng)
	if not st.pending_objections.is_empty():
		t += " " + _pick(rng, PersonalityDB.OBJECTIONS[st.pending_objections[0]]["text"])
	elif not st.offer_explained:
		t += " ¡Si ni siquiera sé bien qué me vende!"
	return t


static func _style(pid: String, text: String, rng: RandomNumberGenerator) -> String:
	match pid:
		"dramatico":
			if rng.randf() < 0.4:
				text = _pick(rng, ["¡Ay! ", "¡Dios mío! ", "¡Oh! "]) + text
		"sarcastico":
			if rng.randf() < 0.25:
				text += _pick(rng, [" Qué emoción.", " Fascinante.", " Increíble, de verdad."])
		"indeciso":
			if rng.randf() < 0.3:
				text += " …Creo."
		"impaciente", "rapido":
			if text.length() > 140:
				text = text.substr(0, 140).rsplit(" ", true, 1)[0] + "…"
	return text


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[rng.randi() % arr.size()])
