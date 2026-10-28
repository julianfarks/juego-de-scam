class_name CallSession
extends Node
## Orquesta una llamada como una MÁQUINA DE ESTADOS explícita.
##
## Fases (phase):
##   preparando → el cliente se está preparando (crear la conversación, pensar el saludo)
##   listo      → esperando a que el jugador hable o escriba
##   pensando   → la IA está generando la respuesta (con límites de tiempo reales)
##   error      → la IA falló; el jugador puede Reintentar, seguir sin IA o colgar
##   terminada  → la llamada acabó
## (Escuchar, transcribir, generar voz y reproducir los gestiona VoiceService y la
##  pantalla de llamada los muestra junto a estas fases.)
##
## Modo "ia": el cliente lo interpreta el modelo de lenguaje LOCAL con su personalidad,
## su situación y la memoria de la llamada. La conversación es LIBRE: el jugador puede
## proponer cualquier cosa, cambiarla, bromear o cambiar de tema.
## Modo "basico": solo si la IA no está disponible (o el jugador lo elige tras un
## error); se indica siempre en pantalla.
## El dinero y el «sí» al pago los deciden las reglas (Economy), nunca el modelo.

signal client_spoke(text: String, emotion: String, gesture: String, source: String)
signal client_partial(text: String)
signal client_text_ready(text: String)   # frase completa antes de terminar el JSON (para la voz)
signal state_updated
signal busy_changed(busy: bool)
signal phase_changed(phase: String)
signal ai_error(message: String, technical: String)
signal proposal_changed(text: String)
signal gen_progress(stage: String, tokens: int)   # leyendo | escribiendo | completada | error
signal sale_completed(card: Dictionary, amount: int)
signal ended(result: Dictionary)
signal notice(text: String)

const PHASES := {
	"preparando": "Preparando al cliente…",
	"listo": "Tu turno: habla o escribe",
	"pensando": "El cliente está pensando…",
	"error": "La IA ha fallado",
	"terminada": "Llamada terminada",
}

var st: ConversationState
var rng := RandomNumberGenerator.new()
var day := 1
var mods: Dictionary = {}
var flags: Dictionary = {}
var busy := false
var active := false
var phase := ""
var mode := "basico"            # ia | basico
var chat: Object = null
var situation := ""
var ai_turns := 0
var basic_turns := 0
var voice_turns := 0
var regenerations := 0
var errors := 0
var last_error := ""
var last_turn_ms := 0
var turn_times: Array = []
var first_token_times: Array = []

var chat_factory: Callable = Callable()   # pruebas: crea un chat falso en vez de usar Brain
var _sys_prompt := ""
var _msgs: Array = []            # memoria propia de la conversación (para reconstruirla)
var _failed: Dictionary = {}     # petición que falló: {kind, message, extra}
var _cancel := {"cancel": false}
var _prep := "none"              # none | running | done
var _greeting: Dictionary = {}
var _pending_end := ""
var _pending_sale: Dictionary = {}
var _announced := false
var _rebuild_chars := 0
var gen_stage := ""              # leyendo (antes del primer token) | escribiendo | completada | error
var gen_tokens := 0          # al reintentar se relee toda la conversación


# ------------------------------------------------------------------ Preparación

## Empieza a preparar al cliente (conversación y saludo) mientras el jugador mira su
## ficha, para ocultar el tiempo de arranque del modelo.
func prepare(client_id: String, p_flags: Dictionary = {}, seed_v: int = -1) -> void:
	if _prep != "none":
		return
	_prep = "running"
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	flags = p_flags
	day = int(flags.get("day", day))
	st = ConversationState.new()
	st.setup(client_id, String(flags.get("offer_id", "")), float(flags.get("extra_trust", 0.0)), float(flags.get("extra_patience", 0.0)), day)
	situation = Persona.SITUATIONS[rng.randi() % Persona.SITUATIONS.size()]
	_set_phase("preparando")
	if flags.get("force_basic", false) == false and (Brain.is_ready() or chat_factory.is_valid()):
		mode = "ia"
		_sys_prompt = Persona.system_prompt(client_id, situation, st.budget)
		chat = await _new_chat()
		if chat == null:
			_greeting = {"ok": false, "error": "sin_chat"}
		else:
			var opening := "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]"
			if flags.get("weird_question", false):
				opening = "[Suena el teléfono y descuelgas. Saluda y suelta enseguida una pregunta rarísima e inesperada al que llama.]"
			_greeting = await _generate("saludo", opening, func(): return chat.ask(opening), false)
	_prep = "done"


func start(client_id: String, p_day: int, p_mods: Dictionary, p_flags: Dictionary = {}, seed_v: int = -1) -> void:
	day = p_day
	mods = p_mods
	if _prep == "none":
		var f := p_flags.duplicate()
		f["day"] = p_day
		prepare(client_id, f, seed_v)
	st.time_limit = 240.0 * float(flags.get("time_mult", 1.0))
	active = true
	_set_busy(true)
	while _prep != "done":
		await get_tree().process_frame
	_set_busy(false)
	if not active:
		return
	if mode == "ia":
		if _greeting.get("ok", false):
			_emit_ai(_greeting, false)
			_set_phase("listo")
		else:
			_fail("saludo", "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]", _greeting.get("error", "sin_respuesta"))
	else:
		var greet := LocalDialogue.greeting(st, rng)
		st.add_history("client", greet)
		st.client_lines.append(greet)
		client_spoke.emit(greet, "neutral", "", "basico")
		_set_phase("listo")
	state_updated.emit()


func _new_chat() -> Object:
	if chat_factory.is_valid():
		return await chat_factory.call(_sys_prompt)
	return await Brain.new_chat(_sys_prompt, Persona.schema())


func client() -> Dictionary:
	return ClientDB.get_c(st.client_id)


func personality() -> Dictionary:
	return PersonalityDB.get_p(st.personality_id)


# ------------------------------------------------------------------ Turnos

func player_says(text: String, via_voice := false) -> void:
	text = text.strip_edges().substr(0, 500)
	if not active or busy or text == "" or phase == "error":
		return
	if via_voice:
		voice_turns += 1
	st.add_history("player", text)
	var ctx := {"offer_id": st.offer_id, "pending_question_expects": st.pending_question.get("expects", []), "client_facts": client()["facts"]}
	var analysis := IntentClassifier.analyze(text, ctx)
	if IntentClassifier.has(analysis, "ask_payment", 0.5):
		ConversationRules.track_facts(st, analysis)
		await _close_turn(text)
		return
	var rules := ConversationRules.apply_turn(st, analysis, rng, mods, mode != "ia")
	state_updated.emit()
	if mode != "ia":
		_basic_reply(analysis, rules)
		return
	var notes := _notes_for(rules)
	if rules["hangup"] != "":
		notes.append(_hangup_note(rules["hangup"]))
	var msg := Persona.turn_message(text, notes)
	var r := await _generate("turno", msg, func(): return chat.ask(msg))
	if not active:
		return
	if not r.get("ok", false):
		_fail("turno", msg, r.get("error", ""), {"hangup": rules["hangup"], "analysis": analysis, "rules": rules})
		return
	_after_ai_turn(r, rules["hangup"])


func _after_ai_turn(r: Dictionary, hangup: String) -> void:
	_emit_ai(r)
	_maybe_suggest_light()
	if hangup != "":
		_finish(hangup)
	elif r["cuelga"] and _may_hang_up():
		_finish("paciencia" if st.patience < 30.0 else "sospecha")
	else:
		_set_phase("listo")


func _basic_reply(analysis: Dictionary, rules: Dictionary) -> void:
	var resp := LocalDialogue.respond(st, analysis, rules, rng)
	basic_turns += 1
	st.add_history("client", resp["text"])
	st.client_lines.append(resp["text"])
	client_spoke.emit(resp["text"], resp["emotion"], resp["gesture"], "basico")
	state_updated.emit()
	if rules["hangup"] != "":
		_finish(rules["hangup"])
	else:
		_set_phase("listo")


## Notas verificables que el juego pasa al modelo en cada turno: la MEMORIA fiable de
## la llamada (propuesta, precios, cantidad, contradicciones, promesas, decisiones).
func _notes_for(rules: Dictionary) -> Array:
	var notes := []
	var events: Array = rules["events"]
	if events.has("price_set"):
		notes.append("el vendedor dice que cuesta %d pesos" % st.stated_price)
	if events.has("contradiction"):
		var c: Dictionary = st.contradictions[-1]
		notes.append("OJO: el vendedor dijo antes que costaba %d y ahora dice %d" % [c["a"], c["b"]])
	elif events.has("price_lowered"):
		var prev := int(st.price_history[-2]["price"]) if st.price_history.size() >= 2 else st.stated_price
		notes.append("el vendedor baja el precio de %d a %d pesos" % [prev, st.stated_price])
	if events.has("quantity"):
		notes.append("propone %d unidades (total %d pesos)" % [st.quantity, st.quantity * maxi(0, st.stated_price)] if st.stated_price > 0 else "propone %d unidades" % st.quantity)
	if events.has("promise_overdue"):
		var pr: Array = st.promises.filter(func(p): return p.get("reminded", false) and not p["fulfilled"])
		if not pr.is_empty():
			notes.append("el vendedor prometió «%s» y aún no lo ha cumplido" % String(pr[-1]["text"]).strip_edges())
	if events.has("greeted_again"):
		notes.append("el vendedor vuelve a saludar aunque ya os habíais saludado")
	if st.insults > 0 and IntentClassifier.has(IntentClassifier.analyze(st.history[-1]["text"]), "insult"):
		notes.append("el vendedor te ha faltado al respeto")
	if st.patience < 25.0:
		notes.append("se te está acabando la paciencia")
	if st.time_limit - st.elapsed < 35.0:
		notes.append("tienes que colgar muy pronto")
	# Recordatorio: cada 4 turnos y SIEMPRE que el jugador pregunta por algo anterior
	var last_norm := IntentClassifier.normalize(String(st.history[-1]["text"])) if not st.history.is_empty() else ""
	var asks_memory := false
	for k in ["recuerda", "acuerda", "lo primero", "le ofreci", "le estaba ofreciendo", "le dije", "que le comente", "antes le"]:
		if last_norm.contains(k):
			asks_memory = true
	if st.turn > 0 and (st.turn % 4 == 0 or asks_memory):
		var mem := []
		if st.proposal != "":
			mem.append("te ofrece: %s" % st.proposal)
		if st.proposal_log.size() > 1 and String(st.proposal_log[0]["text"]).to_lower() != st.proposal.to_lower():
			mem.append("lo primero que te ofreció fue: %s" % st.proposal_log[0]["text"])
		if st.stated_price > 0:
			mem.append("precio actual: %d pesos%s" % [st.stated_price, (" x %d" % st.quantity) if st.quantity > 1 else ""])
		if st.ai_doubt != "":
			mem.append("tu duda: %s" % st.ai_doubt)
		if st.close_attempts > 0:
			mem.append("ya te negaste a pagar %d vez/veces" % st.close_attempts)
		if not mem.is_empty():
			if asks_memory:
				notes.append("te pregunta por lo hablado: contéstale con estos datos (a tu manera) — " + "; ".join(PackedStringArray(mem)))
			else:
				notes.append("recuerda — " + "; ".join(PackedStringArray(mem)))
	return notes


func _hangup_note(reason: String) -> String:
	match reason:
		"insultos":
			return "estás harto de las faltas de respeto: despídete con enfado y cuelga"
		"sospecha":
			return "estás convencido de que te quieren engañar: dilo y cuelga"
	return "se te ha acabado la paciencia: despídete y cuelga"


func _may_hang_up() -> bool:
	return st.patience < 45.0 or st.suspicion > 60.0 or st.insults > 0 or st.turn >= 14


# ------------------------------------------------------------------ Generación

## Genera una respuesta del cliente con límites de tiempo reales.
## make_stream: Callable que devuelve el stream (chat.ask o chat.complete).
## Devuelve el resultado ya analizado {ok, dice, emocion, …} o {ok:false, error}.
func _generate(kind: String, message: String, make_stream: Callable, announce := true) -> Dictionary:
	if chat == null:
		return {"ok": false, "error": "sin_chat"}
	_cancel = {"cancel": false}
	var my_cancel := _cancel
	_set_busy(true)
	_set_phase("pensando")
	_announced = not announce
	_throttle(true)
	var t0 := Time.get_ticks_msec()
	var stream: Object = make_stream.call()
	var lim := _limits(message)
	gen_stage = "leyendo"
	gen_tokens = 0
	gen_progress.emit(gen_stage, 0)
	var res := await AIStream.read(chat, stream, func(txt: String): _on_partial(txt, my_cancel), my_cancel, lim)
	gen_stage = "completada" if res["ok"] else "error"
	gen_progress.emit(gen_stage, gen_tokens)
	_throttle(false)
	_set_busy(false)
	if my_cancel["cancel"]:
		return {"ok": false, "error": "cancelado"}
	if res["first_ms"] >= 0:
		first_token_times.append(res["first_ms"])
	if res["ok"]:
		Brain.record_speed(message.length() + 300 + (_sys_prompt.length() if _msgs.is_empty() else 0), res["first_ms"], res["tokens"], res["total_ms"])
	if not res["ok"]:
		AILog.add("llamada", "%s: %s (primer token %s, %d tokens, %.1f s; límites: primer token %d s, total %d s)" % [kind, AIStream.error_text(res["error"]), str(res["first_ms"]), res["tokens"], res["total_ms"] / 1000.0, lim["first"] / 1000, lim["total"] / 1000])
		return {"ok": false, "error": res["error"]}
	var r := _parse(res["text"])
	if not r["ok"]:
		AILog.add("llamada", "%s: respuesta sin el formato esperado (%d caracteres)" % [kind, res["text"].length()])
		return {"ok": false, "error": "formato"}
	# Evita que el cliente repita frases o muletillas, o que diga las notas internas: se regenera una vez
	if _is_repeat(r["dice"]) and regenerations < 8:
		regenerations += 1
		var msgs := _msgs.duplicate(true)
		msgs.append({"role": "user", "content": message + "\n[Nota del juego: contesta con palabras nuevas; no repitas frases ni muletillas que ya dijiste y no menciones estas notas.]"})
		_cancel = {"cancel": false}
		my_cancel = _cancel
		_announced = not announce
		_set_busy(true)
		var res2 := await AIStream.read(chat, chat.complete(msgs, {}), func(txt: String): _on_partial(txt, my_cancel), my_cancel, _limits(message + _sys_prompt))
		_set_busy(false)
		var r2 := _parse(res2["text"]) if res2["ok"] else {"ok": false}
		if r2["ok"] and not _leaks_notes(r2["dice"]):
			r = r2
			res = res2
	_msgs.append({"role": "user", "content": message})
	_msgs.append({"role": "assistant", "content": res["text"]})
	last_turn_ms = Time.get_ticks_msec() - t0
	turn_times.append(last_turn_ms)
	Brain.record_turn(last_turn_ms)
	AILog.add("llamada", "%s OK · primer token %.1f s · %d tokens · %.1f s" % [kind, res["first_ms"] / 1000.0, res["tokens"], last_turn_ms / 1000.0])
	return r


## Límites de esta petición. El primer mensaje incluye las instrucciones completas del
## cliente (unos 3000 caracteres), que el modelo tiene que leer antes de contestar.
func _limits(message: String = "") -> Dictionary:
	if flags.has("first_token_ms"):  # pruebas
		var f := int(flags["first_token_ms"])
		return {"first": f, "stall": mini(AIStream.STALL_MS, f), "total": AIStream.TOTAL_MS}
	var chars := message.length() + 300 + _rebuild_chars
	if _msgs.is_empty() or _rebuild_chars > 0:
		chars += _sys_prompt.length()
	return Brain.limits_for(chars)


func _on_partial(txt: String, my_cancel: Dictionary) -> void:
	if my_cancel["cancel"]:
		return
	gen_tokens += 1
	if gen_stage == "leyendo":
		gen_stage = "escribiendo"
	if gen_tokens == 1 or gen_tokens % 5 == 0:
		gen_progress.emit(gen_stage, gen_tokens)
	if _announced:
		return
	var partial := JsonPeek.string_field(txt, "respuesta")
	if partial != "":
		client_partial.emit(partial)
	if JsonPeek.string_field_closed(txt, "respuesta"):
		_announced = true
		if _prep == "done" and active:
			client_text_ready.emit(AIResponse.sanitize_text(partial, 300))


## La IA ha fallado: estado de error explícito (sin inventar respuestas).
func _fail(kind: String, message: String, code: String, extra: Dictionary = {}) -> void:
	errors += 1
	last_error = code
	_failed = {"kind": kind, "message": message, "extra": extra}
	var human := AIStream.error_text(code) if AIStream.ERRORS.has(code) else ("La respuesta de la IA no tenía el formato esperado" if code == "formato" else "No se pudo crear la conversación con la IA" if code == "sin_chat" else "La IA no respondió")
	_set_phase("error")
	ai_error.emit(human, code)
	state_updated.emit()


## Reintenta la última petición fallida en una conversación NUEVA reconstruida con
## la memoria del juego (el motor anterior puede seguir bloqueado).
func retry() -> void:
	if phase != "error" or _failed.is_empty() or not active:
		return
	var f := _failed
	_failed = {}
	_set_phase("preparando")
	chat = await _new_chat()
	if not active:
		return
	if chat == null:
		_fail(f["kind"], f["message"], "sin_chat", f["extra"])
		return
	var msgs := _msgs.slice(maxi(0, _msgs.size() - 12))
	msgs.append({"role": "user", "content": f["message"]})
	_rebuild_chars = 0
	for m in msgs:
		_rebuild_chars += str(m["content"]).length()
	var r := await _generate(f["kind"], f["message"], func(): return chat.complete(msgs, {}))
	_rebuild_chars = 0
	if not active:
		return
	if not r.get("ok", false):
		_fail(f["kind"], f["message"], r.get("error", ""), f["extra"])
		return
	match f["kind"]:
		"saludo":
			_emit_ai(r, false)
			_set_phase("listo")
		"turno":
			_after_ai_turn(r, f["extra"].get("hangup", ""))
		"cierre":
			_after_close_line(r, f["extra"]["res"])
		"despedida":
			_emit_ai(r, false)
			_finish(f["extra"].get("reason", "tiempo"))


## El jugador decide seguir la llamada sin IA (queda indicado en pantalla).
func continue_basic() -> void:
	if phase != "error" or not active:
		return
	var f := _failed
	_failed = {}
	mode = "basico"
	chat = null
	notice.emit("Sigues la llamada con el diálogo básico (sin IA).")
	match f.get("kind", ""):
		"turno":
			var ex: Dictionary = f["extra"]
			_basic_reply(ex["analysis"], ex["rules"])
		"cierre":
			var res: Dictionary = f["extra"]["res"]
			var reply := LocalDialogue.close_reply(st, res["success"], rng)
			st.add_history("client", reply)
			client_spoke.emit(reply, "happy" if res["success"] else "distrust", "nod" if res["success"] else "shake", "basico")
			_resolve_close(res)
		"despedida":
			_finish(f["extra"].get("reason", "tiempo"))
		_:
			var greet := LocalDialogue.greeting(st, rng)
			st.add_history("client", greet)
			client_spoke.emit(greet, "neutral", "", "basico")
			_set_phase("listo")


## Si el móvil tarda demasiado, se avisa (una vez por sesión) de que existe el
## cerebro ligero. No se cambia solo: es decisión del jugador.
static var _light_suggested := false
func _maybe_suggest_light() -> void:
	if _light_suggested or Brain.llm_pack != "llm_normal" or last_turn_ms < 40000:
		return
	_light_suggested = true
	notice.emit("Tu móvil ha tardado %d s en esta respuesta. En Ajustes → IA y voz puedes probar el cerebro ligero: responde más rápido, aunque conversa peor (0,5 GB)." % int(last_turn_ms / 1000.0))


## Mientras el modelo piensa se baja la tasa de imágenes: la pantalla de llamada
## apenas cambia y así el procesador (y la batería) se dedican a la IA.
static var _saved_fps := -1
func _throttle(on: bool) -> void:
	if on and _saved_fps < 0:
		_saved_fps = Engine.max_fps
		Engine.max_fps = 12 if _saved_fps == 0 else mini(_saved_fps, 12)
	elif not on and _saved_fps >= 0:
		Engine.max_fps = _saved_fps
		_saved_fps = -1


func _parse(raw: String) -> Dictionary:
	var j = JSON.parse_string(raw) if raw.strip_edges().ends_with("}") else null
	if not (j is Dictionary):
		# Respuesta cortada: si la frase ya estaba completa, se usa (es texto real de la IA)
		if JsonPeek.string_field_closed(raw, "respuesta"):
			j = {"respuesta": JsonPeek.string_field(raw, "respuesta"), "emocion": "neutral", "efecto": "igual", "interes": 5, "duda": "", "propuesta": "", "cuelga": false}
		else:
			return {"ok": false}
	var dice := AIResponse.sanitize_text(str(j.get("respuesta", "")), 300)
	# Si aun así se cuela una nota interna, se quita (nunca se inventa texto nuevo)
	var rx := RegEx.new()
	rx.compile("(?i)\\[[^\\]]*\\]|decisi[oóÓ]n del juego:?|notas? del juego:?")
	dice = rx.sub(dice, "", true).strip_edges()
	if dice.length() < 2:
		return {"ok": false}
	var emo := str(j.get("emocion", "neutral"))
	if not Persona.EMOTIONS.has(emo):
		emo = "neutral"
	var eff := str(j.get("efecto", "igual"))
	if not eff in ["mejora", "igual", "empeora"]:
		eff = "igual"
	return {"ok": true, "dice": dice, "emocion": emo, "efecto": eff, "interes": clampi(int(j.get("interes", 5)), 0, 10),
		"duda": AIResponse.sanitize_text(str(j.get("duda", "")), 70), "propuesta": str(j.get("propuesta", "")),
		"cuelga": bool(j.get("cuelga", false))}


## Frase repetida, muletilla gastada (4 palabras seguidas ya dichas 2 veces) o notas
## internas del juego filtradas en la respuesta → se regenera.
func _is_repeat(text: String) -> bool:
	if _leaks_notes(text):
		return true
	var norm := IntentClassifier.normalize(text).replace("?", " ").split(" ", false)
	for i in range(0, norm.size() - 3):
		var gram := " ".join(norm.slice(i, i + 4))
		var seen := 0
		for prev in st.client_lines:
			if (" " + " ".join(IntentClassifier.normalize(prev).replace("?", " ").split(" ", false)) + " ").contains(" " + gram + " "):
				seen += 1
		if seen >= 2:
			return true
	var a := _words(text)
	if a.size() < 4:
		return false
	for prev in st.client_lines:
		var b := _words(prev)
		var inter := 0
		for w in a:
			if b.has(w):
				inter += 1
		var union := a.size() + b.size() - inter
		if union > 0 and float(inter) / union > 0.65:
			return true
	return false


static func _leaks_notes(text: String) -> bool:
	var n := IntentClassifier.normalize(text)
	return n.contains("decision del juego") or n.contains("notas del juego") or n.contains("nota del juego") or text.contains("[")


func _words(t: String) -> Array:
	var out := []
	for w in IntentClassifier.normalize(t).strip_edges().split(" ", false):
		if w.length() > 2 and not out.has(w):
			out.append(w)
	return out


func _emit_ai(r: Dictionary, apply_judgement := true) -> void:
	ai_turns += 1
	if apply_judgement and st.turn > 0:
		ConversationRules.apply_ai_judgement(st, r["efecto"], r["emocion"], r["interes"], mods)
	st.ai_doubt = r["duda"]
	if st.set_proposal(r.get("propuesta", "")):
		proposal_changed.emit(st.proposal)
	st.add_history("client", r["dice"])
	st.client_lines.append(r["dice"])
	var anim: String = Persona.EMOTION_TO_ANIM.get(r["emocion"], "neutral")
	var gesture: String = {"risa": "laugh", "sorpresa": "surprised", "confusion": "head_scratch", "enfado": "angry", "desconfianza": "arms_crossed"}.get(r["emocion"], "")
	if gesture == "":
		gesture = "nod" if r["efecto"] == "mejora" else ("shake" if r["efecto"] == "empeora" else "")
	client_spoke.emit(r["dice"], anim, gesture, "ia")
	state_updated.emit()


# ------------------------------------------------------------------ Cierre

## El jugador pide los datos de pago: la decisión la toman las reglas (Economy).
func attempt_close() -> void:
	if not active or busy or phase == "error":
		return
	var line := "¿Entonces le apunto? ¿Me facilita los datos de pago para completar el pedido?"
	st.add_history("player", line)
	await _close_turn(line)


func _close_turn(player_text: String) -> void:
	if not active or busy:
		return
	st.turn += 1
	var res := Economy.attempt_close(st, rng, day, mods)
	state_updated.emit()
	if mode == "ia":
		var note := ""
		match res.get("missing", ""):
			"propuesta":
				note = "DECISIÓN DEL JUEGO (no la menciones): todavía no pagas porque no sabes bien qué te venden; pregúntalo"
			"precio":
				note = "DECISIÓN DEL JUEGO (no la menciones): todavía no pagas porque no te ha dicho el precio; pregunta cuánto cuesta"
			_:
				if res["success"]:
					note = "DECISIÓN DEL JUEGO (no la menciones): aceptas comprar%s por %d pesos; dilo con tus palabras y di que le das tus datos (no digas números)" % [(" " + st.proposal) if st.proposal != "" else "", res["amount"]]
				else:
					var why := ""
					if st.ai_doubt != "":
						why = " (sigue tu duda: %s)" % st.ai_doubt
					elif st.stated_price * maxi(1, st.quantity) > st.budget:
						why = " (te parece caro)"
					elif st.trust < 40:
						why = " (no te fías todavía)"
					note = "DECISIÓN DEL JUEGO (no la menciones): NO aceptas pagar todavía%s; dilo con tus palabras" % why
		var msg := Persona.turn_message(player_text, ["el vendedor te pide los datos de pago", note])
		var r := await _generate("cierre", msg, func(): return chat.ask(msg))
		if not active:
			return
		if not r.get("ok", false):
			_pending_sale = res if res["success"] else {}
			_fail("cierre", msg, r.get("error", ""), {"res": res})
			return
		_after_close_line(r, res)
	else:
		var reply := LocalDialogue.close_reply(st, res["success"], rng)
		if res.get("missing", "") == "precio":
			reply = "¿Pero cuánto cuesta exactamente? No me ha dicho el precio."
		elif res.get("missing", "") == "propuesta":
			reply = "Un momento, ¿pero qué es exactamente lo que me vende?"
		st.add_history("client", reply)
		client_spoke.emit(reply, "happy" if res["success"] else "distrust", "nod" if res["success"] else "shake", "basico")
		_resolve_close(res)


func _after_close_line(r: Dictionary, res: Dictionary) -> void:
	if res["success"]:
		r["emocion"] = "contento" if r["emocion"] in ["enfado", "desconfianza", "triste"] else r["emocion"]
	_emit_ai(r, false)
	_resolve_close(res)


func _resolve_close(res: Dictionary) -> void:
	_pending_sale = {}
	state_updated.emit()
	if res["success"]:
		sale_completed.emit(res["card"], res["amount"])
		_finish("success", res["amount"], res["card"])
	elif st.suspicion >= 100.0 or st.patience <= 0.0:
		_finish("sospecha" if st.suspicion >= 100.0 else "paciencia")
	else:
		_set_phase("listo")


func use_soundboard() -> bool:
	if not active or busy:
		return false
	var p := personality()
	var mult := 1.6 if p["likes"].has("joke") else (0.3 if p["dislikes"].has("joke") else 1.0)
	st.humor += 12.0 * mult
	st.trust += 3.0 * mult
	if PersonalityDB.has_quirk(st.personality_id, "literal"):
		st.understanding -= 5.0
	st.clamp_all()
	state_updated.emit()
	return true


func tick(delta: float) -> void:
	if not active or busy or phase == "error":
		return
	var reason := ConversationRules.tick(st, delta, mods)
	if reason == "" or _pending_end != "":
		return
	_pending_end = reason
	if mode == "ia":
		var msg := "[Nota del juego: %s.]" % ("se te ha acabado la paciencia: despídete y cuelga" if reason == "paciencia" else "tienes que colgar ya: despídete")
		var r := await _generate("despedida", msg, func(): return chat.ask(msg))
		if not active:
			return
		if r.get("ok", false):
			_emit_ai(r, false)
		else:
			notice.emit("El cliente cuelga (la IA no llegó a despedirse: %s)." % AIStream.error_text(r.get("error", "")))
		_finish(reason)
		return
	var line := PersonalityDB.line(st.personality_id, "hangup", rng) if reason == "paciencia" else "Bueno, se me acabó el tiempo. Ya hablaremos."
	st.add_history("client", line)
	client_spoke.emit(line, "angry" if reason == "paciencia" else "neutral", "hangup", "basico")
	_finish(reason)


func player_hangs_up() -> void:
	if not active:
		return
	# Si el cliente ya había aceptado pagar y la IA falló al decirlo, la venta vale
	if not _pending_sale.is_empty():
		var res := _pending_sale
		_pending_sale = {}
		sale_completed.emit(res["card"], res["amount"])
		_finish("success", res["amount"], res["card"])
		return
	_finish("player")


func interrupt(reason: String) -> void:
	if active:
		_finish(reason)


## Cancela la respuesta que se está generando (botón Cancelar).
func cancel_pending() -> void:
	_cancel["cancel"] = true
	if busy and chat:
		chat.stop_generation()
	_set_busy(false)
	if active and phase == "pensando":
		_set_phase("listo")


func _commission_mods() -> Dictionary:
	var m := mods.duplicate()
	m["amount_mult"] = float(m.get("amount_mult", 1.0)) * float(flags.get("amount_extra", 1.0))
	return m


func _set_busy(b: bool) -> void:
	busy = b
	busy_changed.emit(b)


func _set_phase(p: String) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


func _finish(reason: String, amount := 0, card: Dictionary = {}) -> void:
	if not active:
		return
	active = false
	_cancel["cancel"] = true
	if busy and chat:
		chat.stop_generation()
		_set_busy(false)
	var outcome := Economy.classify_end(st, reason)
	st.ended = true
	st.outcome = outcome
	var c := client()
	var avg := 0
	for t in turn_times:
		avg += int(t)
	avg = avg / maxi(1, turn_times.size())
	var result := {
		"client_id": st.client_id, "client_name": c["name"], "personality": st.personality_id,
		"offer_id": st.offer_id, "offer_name": st.proposal_label(),
		"proposal": st.proposal, "tags": st.tags.duplicate(), "unit_price": maxi(0, st.stated_price), "quantity": st.quantity,
		"outcome": outcome, "outcome_text": Economy.OUTCOMES[outcome], "reason": reason,
		"amount": amount if outcome == "success" else 0, "card": card,
		"commission": Economy.commission(amount, _commission_mods()) if outcome == "success" else 0,
		"duration": int(st.elapsed), "turns": st.turn,
		"objections_resolved": st.resolved_objections.size(), "objections_pending": st.pending_objections.size() + (1 if st.ai_doubt != "" else 0),
		"contradictions": st.contradictions.size(), "voice_turns": voice_turns,
		"ai_turns": ai_turns, "basic_turns": basic_turns, "mode": mode, "avg_turn_ms": avg, "ai_errors": errors,
		"comment": BossLines.call_comment(st, outcome, amount, rng),
		"final_state": st.to_prompt_dict(),
	}
	chat = null
	_set_phase("terminada")
	ended.emit(result)
