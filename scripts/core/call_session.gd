class_name CallSession
extends Node
## Orquesta una llamada: estado, reglas, IA remota o diálogo local, cierre de venta
## autoritativo, tiempo límite y resultado final. No depende de la escena 3D, así que
## se puede probar en modo headless.

signal client_spoke(text: String, emotion: String, gesture: String, source: String)
signal state_updated
signal busy_changed(busy: bool)
signal sale_completed(card: Dictionary, amount: int)
signal ended(result: Dictionary)
signal notice(text: String)

var st: ConversationState
var rng := RandomNumberGenerator.new()
var day := 1
var mods: Dictionary = {}
var flags: Dictionary = {}
var busy := false
var active := false
var use_remote := true
var source_last := "local"
var remote_turns := 0
var local_turns := 0
var voice_turns := 0
var _end_pending: Dictionary = {}
var _turn_seq := 0
var ai_receptive := 0.0
var player_name := "Novato"


func start(client_id: String, offer_id: String, p_day: int, p_mods: Dictionary, p_flags: Dictionary = {}, seed_v: int = -1) -> void:
	if seed_v >= 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	day = p_day
	mods = p_mods
	flags = p_flags
	st = ConversationState.new()
	st.setup(client_id, offer_id, float(flags.get("extra_trust", 0.0)), float(flags.get("extra_patience", 0.0)))
	st.time_limit = 150.0 * float(flags.get("time_mult", 1.0))
	active = true
	busy = false
	_end_pending = {}
	var greet := LocalDialogue.greeting(st, rng)
	if flags.get("weird_question", false):
		var q := {"key": "weird", "text": _pick(["Antes de nada: si usted fuera una fruta, ¿cuál sería y por qué?", "Pregunta seria: ¿las cucharas tienen derechos?", "Necesito saberlo ya: ¿cuántos patos caben en un ascensor?"]),
			"expects": ["joke", "answer", "smalltalk", "drama_hook", "personal"], "turn": 0, "answered": false}
		st.pending_question = q
		st.client_questions.append(q)
		greet += " " + q["text"]
	st.add_history("client", greet)
	client_spoke.emit(greet, "neutral", "", "local")
	state_updated.emit()


func _pick(arr: Array) -> String:
	return str(arr[rng.randi() % arr.size()])


func client() -> Dictionary:
	return ClientDB.get_c(st.client_id)


func personality() -> Dictionary:
	return PersonalityDB.get_p(st.personality_id)


## Turno del jugador (texto o voz transcrita).
func player_says(text: String, via_voice := false) -> void:
	text = text.strip_edges().substr(0, 500)
	if not active or busy or text == "":
		return
	if via_voice:
		voice_turns += 1
	st.add_history("player", text)
	var ctx := {
		"offer_id": st.offer_id,
		"pending_question_expects": st.pending_question.get("expects", []),
		"client_facts": client()["facts"],
	}
	var analysis := IntentClassifier.analyze(text, ctx)
	# Pedir la tarjeta = intento de cierre (decidido por las reglas, no por la IA)
	if IntentClassifier.has(analysis, "ask_payment", 0.5):
		st.turn += 1
		attempt_close()
		return
	var rules := ConversationRules.apply_turn(st, analysis, rng, mods)
	state_updated.emit()
	_turn_seq += 1
	var my_turn := _turn_seq
	if use_remote and AI.remote_available() and rules["hangup"] == "":
		_set_busy(true)
		var r := await AI.chat(_build_payload(text, analysis, rules))
		if not active or my_turn != _turn_seq:
			return
		_set_busy(false)
		if r.get("ok", false):
			var applied := ConversationRules.merge_ai_deltas(st, r["deltas"])
			ai_receptive = float(r["receptive"])
			remote_turns += 1
			source_last = "remote"
			st.add_history("client", r["reply"])
			client_spoke.emit(r["reply"], r["emotion"], r["gesture"], "remote")
			state_updated.emit()
			# La IA puede pedir colgar, pero solo si las reglas lo permiten (paciencia baja)
			if r["hang_up"] and (st.patience < 25.0 or st.suspicion > 80.0):
				_finish("paciencia" if st.patience < 25.0 else "sospecha")
			return
		if not r.get("cancelled", false):
			notice.emit("IA remota no disponible (%s). Sigo con el diálogo local." % str(r.get("error", "")).substr(0, 60))
	_local_reply(analysis, rules)


func _local_reply(analysis: Dictionary, rules: Dictionary) -> void:
	var resp := LocalDialogue.respond(st, analysis, rules, rng)
	local_turns += 1
	source_last = "local"
	st.add_history("client", resp["text"])
	client_spoke.emit(resp["text"], resp["emotion"], resp["gesture"], "local")
	state_updated.emit()
	if rules["hangup"] != "":
		_finish(rules["hangup"])


func _build_payload(text: String, analysis: Dictionary, rules: Dictionary) -> Dictionary:
	var c := client()
	var p := personality()
	var o := OfferDB.get_o(st.offer_id)
	var hist := []
	for h in st.recent_history(8):
		hist.append({"role": "vendedor" if h["who"] == "player" else "cliente", "text": String(h["text"]).substr(0, 300)})
	var detected := []
	for k in analysis["intents"].keys():
		detected.append(k)
	var events := []
	for e in rules["events"]:
		events.append(str(e))
	return {
		"language": Loc.lang,
		"client": {
			"name": c["name"], "personality": st.personality_id, "personality_name": p["name"],
			"style": p["prompt"], "facts": c["facts"], "quirks": p["quirks"],
			"example_lines": [p["lines"]["positive"][0], p["lines"]["negative"][0], p["lines"]["quirk"][0]],
		},
		"offer": {"name": o["name"], "pitch": o["pitch"], "reference_price": int(o["price"])},
		"state": st.to_prompt_dict(),
		"history": hist,
		"player_text": text,
		"analysis": {"intents": detected, "numbers": analysis["numbers"], "events": events},
		"emotion_hint": st.emotion(),
	}


## Intento de cierre: la probabilidad y el importe los calcula Economy.
func attempt_close() -> void:
	if not active or busy:
		return
	var m := mods.duplicate()
	m["amount_mult"] = float(m.get("amount_mult", 1.0)) * float(flags.get("amount_extra", 1.0))
	var res := Economy.attempt_close(st, rng, day, m, ai_receptive * Economy.AI_HINT_MAX)
	var reply := LocalDialogue.close_reply(st, res["success"], rng)
	st.add_history("client", reply)
	client_spoke.emit(reply, "happy" if res["success"] else "distrust", "nod" if res["success"] else "shake", "rules")
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
	if not active:
		return
	var reason := ConversationRules.tick(st, delta, mods)
	if reason != "" and not busy:
		var line := PersonalityDB.line(st.personality_id, "hangup", rng) if reason == "paciencia" else "Bueno, se me acabó el tiempo. Ya hablaremos."
		st.add_history("client", line)
		client_spoke.emit(line, "angry" if reason == "paciencia" else "neutral", "hangup", "rules")
		_finish(reason)


func player_hangs_up() -> void:
	if active:
		_finish("player")


func interrupt(reason: String) -> void:
	if active:
		_finish(reason)


func cancel_pending() -> void:
	_turn_seq += 1
	if busy:
		AI.cancel_all()
		_set_busy(false)


func _set_busy(b: bool) -> void:
	busy = b
	busy_changed.emit(b)


func _finish(reason: String, amount := 0, card: Dictionary = {}) -> void:
	if not active:
		return
	active = false
	_turn_seq += 1
	if busy:
		AI.cancel_all()
		_set_busy(false)
	var outcome := Economy.classify_end(st, reason)
	st.ended = true
	st.outcome = outcome
	var c := client()
	var result := {
		"client_id": st.client_id, "client_name": c["name"], "personality": st.personality_id,
		"offer_id": st.offer_id, "offer_name": OfferDB.get_o(st.offer_id)["name"],
		"outcome": outcome, "outcome_text": Economy.OUTCOMES[outcome], "reason": reason,
		"amount": amount if outcome == "success" else 0, "card": card,
		"duration": int(st.elapsed), "turns": st.turn,
		"objections_resolved": st.resolved_objections.size(), "objections_pending": st.pending_objections.size(),
		"contradictions": st.contradictions.size(), "voice_turns": voice_turns,
		"remote_turns": remote_turns, "local_turns": local_turns,
		"comment": BossLines.call_comment(st, outcome, amount, rng),
		"final_state": st.to_prompt_dict(),
	}
	ended.emit(result)
