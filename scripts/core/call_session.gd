class_name CallSession
extends Node
## Orquesta una llamada.
##  - Modo "ia": el cliente lo interpreta un modelo de lenguaje LOCAL (NobodyWho) con
##    su personalidad, su situación y la memoria de la llamada. El modelo devuelve lo
##    que dice y su juicio (emoción, efecto de la frase, interés, duda, colgar).
##  - Modo "basico": sin modelo disponible, responde el diálogo por reglas (y la
##    interfaz lo indica claramente; no se presenta como IA).
## En ambos modos el reglamento es el árbitro: memoria verificable (cifras,
## contradicciones, promesas), paciencia, tiempo, y el cierre de la venta y el importe
## los decide Economy, nunca el modelo.

signal client_spoke(text: String, emotion: String, gesture: String, source: String)
signal client_partial(text: String)
signal state_updated
signal busy_changed(busy: bool)
signal sale_completed(card: Dictionary, amount: int)
signal ended(result: Dictionary)
signal notice(text: String)

const TURN_TIMEOUT_MS := 60000

var st: ConversationState
var rng := RandomNumberGenerator.new()
var day := 1
var mods: Dictionary = {}
var flags: Dictionary = {}
var busy := false
var active := false
var mode := "basico"
var chat: Object = null
var situation := ""
var ai_turns := 0
var basic_turns := 0
var voice_turns := 0
var regenerations := 0
var last_turn_ms := 0
var turn_times: Array = []
var _turn_seq := 0
var _pending_end := ""


var _prep := "none"          # none | running | done
var _greeting: Dictionary = {}
var _offer_told := false


## Empieza a preparar al cliente (crear la conversación y pensar el saludo) antes de
## que el jugador elija la oferta, para ocultar el tiempo de arranque del modelo.
func prepare(client_id: String, p_flags: Dictionary = {}, seed_v: int = -1) -> void:
	if _prep != "none":
		return
	_prep = "running"
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	flags = p_flags
	st = ConversationState.new()
	st.setup(client_id, "seguro_abduccion", float(flags.get("extra_trust", 0.0)), float(flags.get("extra_patience", 0.0)))
	situation = Persona.SITUATIONS[rng.randi() % Persona.SITUATIONS.size()]
	if flags.get("force_basic", false) == false and Brain.is_ready():
		chat = await Brain.new_chat(Persona.system_prompt(client_id, situation), Persona.schema())
		if chat != null:
			mode = "ia"
			var opening := "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]"
			if flags.get("weird_question", false):
				opening = "[Suena el teléfono y descuelgas. Saluda y suelta enseguida una pregunta rarísima e inesperada al que llama.]"
			_greeting = await _ask_ai(opening, false)
	_prep = "done"


func start(client_id: String, offer_id: String, p_day: int, p_mods: Dictionary, p_flags: Dictionary = {}, seed_v: int = -1) -> void:
	day = p_day
	mods = p_mods
	if _prep == "none":
		prepare(client_id, p_flags, seed_v)
	st.offer_id = offer_id
	st.time_limit = 210.0 * float(flags.get("time_mult", 1.0))
	active = true
	_set_busy(true)
	while _prep != "done":
		await get_tree().process_frame
	_set_busy(false)
	if not active:
		return
	if mode == "ia" and _greeting.get("ok", false):
		_emit_ai(_greeting, false)
	else:
		_fallback_greeting()
	state_updated.emit()


func _fallback_greeting() -> void:
	mode = "basico" if chat == null else mode
	var greet := LocalDialogue.greeting(st, rng)
	st.add_history("client", greet)
	st.client_lines.append(greet)
	client_spoke.emit(greet, "neutral", "", "basico")


func client() -> Dictionary:
	return ClientDB.get_c(st.client_id)


func personality() -> Dictionary:
	return PersonalityDB.get_p(st.personality_id)


# ------------------------------------------------------------------ Turnos

func player_says(text: String, via_voice := false) -> void:
	text = text.strip_edges().substr(0, 500)
	if not active or busy or text == "":
		return
	if via_voice:
		voice_turns += 1
	st.add_history("player", text)
	var ctx := {"offer_id": st.offer_id, "pending_question_expects": st.pending_question.get("expects", []), "client_facts": client()["facts"]}
	var analysis := IntentClassifier.analyze(text, ctx)
	if IntentClassifier.has(analysis, "ask_payment", 0.5):
		await _close_turn(text)
		return
	var rules := ConversationRules.apply_turn(st, analysis, rng, mods, mode != "ia")
	state_updated.emit()
	if mode == "ia":
		var notes := _notes_for(rules)
		if not _offer_told:
			_offer_told = true
			notes.push_front(Persona.offer_note(st.offer_id))
		if rules["hangup"] != "":
			notes.append(_hangup_note(rules["hangup"]))
		_set_busy(true)
		var r := await _ask_ai(Persona.turn_message(text, notes))
		_set_busy(false)
		if not active:
			return
		if r.get("ok", false):
			_emit_ai(r)
			if rules["hangup"] != "":
				_finish(rules["hangup"])
			elif r["cuelga"] and _may_hang_up():
				_finish("paciencia" if st.patience < 30.0 else "sospecha")
			return
		notice.emit("La IA no respondió a tiempo; esta respuesta es del diálogo básico.")
	_basic_reply(analysis, rules)


func _basic_reply(analysis: Dictionary, rules: Dictionary) -> void:
	var resp := LocalDialogue.respond(st, analysis, rules, rng)
	basic_turns += 1
	st.add_history("client", resp["text"])
	st.client_lines.append(resp["text"])
	client_spoke.emit(resp["text"], resp["emotion"], resp["gesture"], "basico")
	state_updated.emit()
	if rules["hangup"] != "":
		_finish(rules["hangup"])


## Notas verificables que el juego pasa al modelo en cada turno (memoria fiable).
func _notes_for(rules: Dictionary) -> Array:
	var notes := []
	var events: Array = rules["events"]
	if events.has("contradiction"):
		var c: Dictionary = st.contradictions[-1]
		notes.append("el vendedor dijo antes que costaba %d y ahora dice %d" % [c["a"], c["b"]])
	elif events.has("price_lowered"):
		notes.append("el vendedor ha bajado el precio a %d" % st.stated_price)
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
	if st.stated_price > 0 and not events.has("contradiction") and rng.randf() < 0.25:
		notes.append("precio dicho por el vendedor: %d" % st.stated_price)
	return notes


func _hangup_note(reason: String) -> String:
	match reason:
		"insultos":
			return "estás harto de las faltas de respeto: despídete con enfado y cuelga"
		"sospecha":
			return "estás convencido de que te quieren engañar: dilo y cuelga"
	return "se te ha acabado la paciencia: despídete y cuelga"


func _may_hang_up() -> bool:
	return st.patience < 45.0 or st.suspicion > 60.0 or st.insults > 0 or st.turn >= 12


## Pregunta al modelo y valida la respuesta. Evita repeticiones regenerando una vez.
func _ask_ai(message: String, cancellable := true) -> Dictionary:
	if chat == null:
		return {"ok": false}
	if cancellable:
		_turn_seq += 1
	var my := _turn_seq
	var t0 := Time.get_ticks_msec()
	var raw := await _stream(chat.ask(message), my)
	if my != _turn_seq or (not active and _prep == "done"):
		return {"ok": false, "cancelled": true}
	var r := _parse(raw)
	if r["ok"] and _is_repeat(r["dice"]) and regenerations < 6:
		regenerations += 1
		var hist: Array = await chat.get_chat_history()
		if hist.size() >= 2 and str(hist[-1].get("role", "")) == "assistant":
			hist.pop_back()
			var raw2 := await _stream(chat.complete(hist, {}), my)
			var r2 := _parse(raw2)
			if r2["ok"]:
				r = r2
	last_turn_ms = Time.get_ticks_msec() - t0
	turn_times.append(last_turn_ms)
	Brain.record_turn(last_turn_ms)
	return r


## Lee la respuesta token a token; muestra el texto de «dice» mientras se genera.
func _stream(stream: Object, my: int) -> String:
	if stream == null:
		return ""
	var out := ""
	var t0 := Time.get_ticks_msec()
	while true:
		var tok = await stream.next_token()
		if tok == null:
			break
		out += str(tok)
		if my != _turn_seq or (not active and _prep == "done"):
			chat.stop_generation()
			return ""
		var partial := JsonPeek.string_field(out, "respuesta")
		if partial != "":
			client_partial.emit(partial)
		if Time.get_ticks_msec() - t0 > TURN_TIMEOUT_MS:
			chat.stop_generation()
			break
	return out


func _parse(raw: String) -> Dictionary:
	var j = JSON.parse_string(raw)
	if not (j is Dictionary):
		return {"ok": false}
	var dice := AIResponse.sanitize_text(str(j.get("respuesta", "")), 300)
	if dice.length() < 2:
		return {"ok": false}
	var emo := str(j.get("emocion", "neutral"))
	if not Persona.EMOTIONS.has(emo):
		emo = "neutral"
	var eff := str(j.get("efecto", "igual"))
	if not eff in ["mejora", "igual", "empeora"]:
		eff = "igual"
	return {"ok": true, "dice": dice, "emocion": emo, "efecto": eff, "interes": clampi(int(j.get("interes", 5)), 0, 10),
		"duda": AIResponse.sanitize_text(str(j.get("duda", "")), 70), "cuelga": bool(j.get("cuelga", false))}


func _is_repeat(text: String) -> bool:
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
	st.add_history("client", r["dice"])
	st.client_lines.append(r["dice"])
	var anim: String = Persona.EMOTION_TO_ANIM.get(r["emocion"], "neutral")
	var gesture: String = {"risa": "laugh", "sorpresa": "surprised", "confusion": "head_scratch", "enfado": "angry", "desconfianza": "arms_crossed"}.get(r["emocion"], "")
	if gesture == "":
		gesture = "nod" if r["efecto"] == "mejora" else ("shake" if r["efecto"] == "empeora" else "")
	client_spoke.emit(r["dice"], anim, gesture, "ia")
	state_updated.emit()


# ------------------------------------------------------------------ Cierre

## El jugador pide los datos de pago: la decisión la toma Economy (reglas).
func attempt_close() -> void:
	await _close_turn("¿Me facilita los datos de pago para completar el pedido?")


func _close_turn(player_text: String) -> void:
	if not active or busy:
		return
	st.turn += 1
	var m := mods.duplicate()
	m["amount_mult"] = float(m.get("amount_mult", 1.0)) * float(flags.get("amount_extra", 1.0))
	var res := Economy.attempt_close(st, rng, day, m)
	state_updated.emit()
	var said := false
	if mode == "ia":
		var why := ""
		if not res["success"]:
			if st.ai_doubt != "":
				why = " (sigue tu duda: %s)" % st.ai_doubt
			elif st.trust < 40:
				why = " (no te fías todavía)"
		var note := "DECISIÓN DEL JUEGO: aceptas pagar. Dilo a tu manera; no digas ningún número" if res["success"] else "DECISIÓN DEL JUEGO: NO aceptas pagar todavía%s. Dilo a tu manera" % why
		_set_busy(true)
		var r := await _ask_ai(Persona.turn_message(player_text, ["el vendedor te pide los datos de pago", note]))
		_set_busy(false)
		if not active:
			return
		if r.get("ok", false):
			if res["success"]:
				r["emocion"] = "contento" if r["emocion"] in ["enfado", "desconfianza", "triste"] else r["emocion"]
			_emit_ai(r, false)
			said = true
	if not said:
		var reply := LocalDialogue.close_reply(st, res["success"], rng)
		st.add_history("client", reply)
		client_spoke.emit(reply, "happy" if res["success"] else "distrust", "nod" if res["success"] else "shake", "reglas")
	state_updated.emit()
	if res["success"]:
		sale_completed.emit(res["card"], res["amount"])
		_finish("success", res["amount"], res["card"])
	elif st.suspicion >= 100.0 or st.patience <= 0.0:
		_finish("sospecha" if st.suspicion >= 100.0 else "paciencia")


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
	if not active or busy:
		return
	var reason := ConversationRules.tick(st, delta, mods)
	if reason == "" or _pending_end != "":
		return
	_pending_end = reason
	if mode == "ia":
		_set_busy(true)
		var r := await _ask_ai("[Nota del juego: %s.]" % ("se te ha acabado la paciencia: despídete y cuelga" if reason == "paciencia" else "tienes que colgar ya: despídete"))
		_set_busy(false)
		if r.get("ok", false) and active:
			_emit_ai(r, false)
			_finish(reason)
			return
	var line := PersonalityDB.line(st.personality_id, "hangup", rng) if reason == "paciencia" else "Bueno, se me acabó el tiempo. Ya hablaremos."
	st.add_history("client", line)
	client_spoke.emit(line, "angry" if reason == "paciencia" else "neutral", "hangup", "reglas")
	_finish(reason)


func player_hangs_up() -> void:
	if active:
		_finish("player")


func interrupt(reason: String) -> void:
	if active:
		_finish(reason)


func cancel_pending() -> void:
	_turn_seq += 1
	if busy and chat:
		chat.stop_generation()
	_set_busy(false)


func _set_busy(b: bool) -> void:
	busy = b
	busy_changed.emit(b)


func _finish(reason: String, amount := 0, card: Dictionary = {}) -> void:
	if not active:
		return
	active = false
	_turn_seq += 1
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
		"offer_id": st.offer_id, "offer_name": OfferDB.get_o(st.offer_id)["name"],
		"outcome": outcome, "outcome_text": Economy.OUTCOMES[outcome], "reason": reason,
		"amount": amount if outcome == "success" else 0, "card": card,
		"duration": int(st.elapsed), "turns": st.turn,
		"objections_resolved": st.resolved_objections.size(), "objections_pending": st.pending_objections.size() + (1 if st.ai_doubt != "" else 0),
		"contradictions": st.contradictions.size(), "voice_turns": voice_turns,
		"ai_turns": ai_turns, "basic_turns": basic_turns, "mode": mode, "avg_turn_ms": avg,
		"comment": BossLines.call_comment(st, outcome, amount, rng),
		"final_state": st.to_prompt_dict(),
	}
	chat = null
	ended.emit(result)
