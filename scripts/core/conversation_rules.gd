class_name ConversationRules
extends RefCounted
## Reglamento determinista de la conversación. Se aplica SIEMPRE (con IA remota o
## sin ella). La IA remota solo puede añadir pequeños ajustes acotados encima.

const INTENT_DELTAS := {
	# intent: [trust, patience, humor, understanding, suspicion]
	"greeting": [3, 1, 1, 0, -1],
	"introduce": [5, 0, 0, 2, -4],
	"offer_pitch": [1, -1, 0, 9, 2],
	"benefit": [3, 0, 0, 7, -1],
	"price": [0, 0, 0, 4, 1],
	"discount": [3, 1, 1, 2, 1],
	"urgency": [1, -3, 0, 0, 6],
	"flattery": [3, 1, 3, 0, 3],
	"joke": [2, 1, 9, 0, -1],
	"empathy": [5, 4, 1, 1, -3],
	"reassure_security": [3, 0, 0, 1, -6],
	"guarantee": [5, 1, 0, 2, -5],
	"social_proof": [3, 0, 0, 1, -1],
	"pressure": [-7, -8, -4, 0, 12],
	"insult": [-15, -20, -10, 0, 8],
	"apology": [3, 3, 1, 0, -2],
	"smalltalk": [2, 2, 4, 0, -1],
	"question": [2, 0, 1, 0, 0],
	"jargon": [0, -2, 0, -6, 4],
	"simple_explanation": [2, 1, 0, 10, -1],
	"competitive_hook": [1, 0, 1, 1, 0],
	"drama_hook": [1, 0, 2, 1, 1],
	"honesty": [4, 1, 0, 1, -3],
	"answer": [3, 2, 0, 3, -2],
	"personal": [4, 2, 3, 0, -2],
	"brief": [0, 2, 0, 0, 0],
	"long": [0, -6, -1, -1, 0],
	"unclear": [-1, -4, 0, -3, 1],
	"farewell": [0, -5, 0, 0, 0],
}

const KEYS := ["trust", "patience", "humor", "understanding", "suspicion"]
const LIKE_MULT := 1.8
const DISLIKE_PENALTY := [-4, -5, -2, 0, 4]


## Aplica las reglas de un turno del jugador. mods = modificadores de mejoras.
## Devuelve {deltas:{...}, events:[...], hangup:"" | motivo}
static func apply_turn(st: ConversationState, a: Dictionary, rng: RandomNumberGenerator, mods: Dictionary = {}) -> Dictionary:
	var p := PersonalityDB.get_p(st.personality_id)
	var mult: Dictionary = p["mult"]
	var d := {"trust": 0.0, "patience": 0.0, "humor": 0.0, "understanding": 0.0, "suspicion": 0.0}
	var events: Array = []
	var intents: Dictionary = a["intents"]
	st.turn += 1

	for intent in intents.keys():
		if not INTENT_DELTAS.has(intent):
			continue
		var w: float = intents[intent]
		var row: Array = INTENT_DELTAS[intent]
		var liked: bool = p["likes"].has(intent)
		var disliked: bool = p["dislikes"].has(intent)
		for i in KEYS.size():
			var v := float(row[i]) * w
			if liked and v > 0.0 and KEYS[i] != "suspicion":
				v *= LIKE_MULT
			if liked and KEYS[i] == "suspicion" and v > 0.0:
				v *= 0.4
			if liked and KEYS[i] != "suspicion" and v < 0.0:
				v = absf(v) * 0.5  # lo que a otros molesta, a este cliente le gusta
			if disliked:
				v = minf(v, 0.0) if KEYS[i] != "suspicion" else maxf(v, 0.0)
				v += DISLIKE_PENALTY[i] * w
			d[KEYS[i]] += v
		if liked:
			events.append("liked:" + intent)
		if disliked:
			events.append("disliked:" + intent)

	_apply_quirks(st, a, p, d, events, rng)

	# Saludar a mitad de la llamada no tiene sentido
	if intents.has("greeting"):
		if st.greeted and st.turn > 2:
			d["patience"] -= 4
			events.append("greeted_again")
		st.greeted = true
	if intents.has("introduce"):
		st.intro_done = true
	if intents.has("offer_pitch") or intents.has("benefit") or intents.has("simple_explanation"):
		if not st.intro_done and intents.has("offer_pitch") and st.turn <= 2:
			d["suspicion"] += 3
		st.offer_explained = st.offer_explained or st.understanding + d["understanding"] >= 45

	# Repetir la misma idea una y otra vez cansa
	if a["top"] != "" and a["top"] == st.last_top_intent and not a["top"] in ["answer", "question"]:
		st.same_intent_streak += 1
	else:
		st.same_intent_streak = 0
	st.last_top_intent = a["top"]
	if st.same_intent_streak >= 2:
		d["patience"] -= 5
		d["trust"] -= 2
		events.append("repetition")

	# Fuera de tema
	var on_topic := false
	for k in ["offer_pitch", "benefit", "price", "discount", "guarantee", "answer", "simple_explanation", "reassure_security", "ask_payment", "introduce"]:
		if intents.has(k):
			on_topic = true
	st.off_topic_streak = 0 if on_topic else st.off_topic_streak + 1
	if st.off_topic_streak >= 3 and not PersonalityDB.has_quirk(st.personality_id, "topic_changer") and not PersonalityDB.has_quirk(st.personality_id, "rambles"):
		d["patience"] -= 3
		events.append("off_topic")

	# Memoria de cifras y contradicciones
	_track_amounts(st, a, d, events)
	# Promesas
	_track_promises(st, a, d, events)
	# Objeciones: resolución y aparición
	_track_objections(st, a, p, d, events, rng)
	# Pregunta pendiente del cliente
	if not st.pending_question.is_empty():
		if intents.has("answer") and float(intents["answer"]) >= 0.8:
			st.pending_question["answered"] = true
			st.pending_question = {}
			events.append("question_answered")
		elif st.turn - int(st.pending_question.get("turn", st.turn)) >= 2:
			d["patience"] -= 3
			d["trust"] -= 2
			events.append("question_ignored")

	if intents.has("insult"):
		st.insults += 1

	# Desgaste natural de la paciencia
	d["patience"] -= 2.5 * float(mult["patience_drain"]) * float(mods.get("patience_drain_mult", 1.0))

	# Multiplicadores de personalidad y mejoras
	if d["trust"] > 0.0:
		d["trust"] *= float(mult["trust_gain"]) * float(mods.get("trust_mult", 1.0))
	if d["suspicion"] > 0.0:
		d["suspicion"] *= float(mult["suspicion_gain"])
	if d["understanding"] > 0.0:
		d["understanding"] *= float(mult["understanding_gain"]) * float(mods.get("understanding_mult", 1.0))

	for k in KEYS:
		st.set(k, float(st.get(k)) + d[k])
	st.clamp_all()
	st.update_provisional()

	var hangup := ""
	if st.insults >= 2:
		hangup = "insultos"
	elif st.patience <= 0.0:
		hangup = "paciencia"
	elif st.suspicion >= 100.0:
		hangup = "sospecha"
	return {"deltas": d, "events": events, "hangup": hangup}


static func _apply_quirks(st: ConversationState, a: Dictionary, p: Dictionary, d: Dictionary, events: Array, rng: RandomNumberGenerator) -> void:
	var q: Array = p["quirks"]
	var intents: Dictionary = a["intents"]
	var wc: int = a["word_count"]
	if q.has("hates_long") and wc > 28:
		d["patience"] -= 8
		events.append("too_long")
	if q.has("needs_simple") and a["complexity"] > 0.55:
		d["understanding"] -= 6
		events.append("too_complex")
	if q.has("literal") and (intents.has("joke") or intents.has("drama_hook") or intents.has("flattery")):
		d["understanding"] -= 4
		events.append("literal_confused")
	if q.has("jokes") and intents.has("joke"):
		d["trust"] += 4
	if q.has("challenges") and intents.has("jargon"):
		d["understanding"] += 6
		d["trust"] += 3
	if q.has("paranoid") and intents.has("reassure_security"):
		d["suspicion"] += 8  # «eso es lo que diría un espía»
		events.append("paranoid_reassure")
	if q.has("competitive") and intents.has("competitive_hook"):
		d["trust"] += 6
		d["humor"] += 3
	if q.has("dramatic") and intents.has("drama_hook"):
		d["trust"] += 5
		d["humor"] += 4
	if q.has("rambles") and (intents.has("question") or intents.has("smalltalk") or intents.has("personal")):
		d["trust"] += 3
	if q.has("distracted") and rng.randf() < 0.3:
		d["understanding"] -= 4
		events.append("distracted")
	if q.has("misinterprets") and rng.randf() < 0.35 and not intents.has("simple_explanation"):
		d["understanding"] -= 5
		events.append("misinterpreted")
	if q.has("sarcastic") and intents.has("flattery"):
		d["suspicion"] += 4
	if q.has("indecisive") and rng.randf() < 0.25:
		d["trust"] -= 3
		events.append("doubting")
	if q.has("wants_out") and wc > 20:
		d["patience"] -= 5
	if q.has("firm") and (intents.has("pressure") or intents.has("urgency")):
		d["trust"] -= 6
	if q.has("question_machine") and intents.has("answer"):
		d["trust"] += 3
		d["understanding"] += 3
	if q.has("surprise_questions") and intents.has("answer") and intents.has("joke"):
		d["trust"] += 5


static func _track_amounts(st: ConversationState, a: Dictionary, d: Dictionary, events: Array) -> void:
	var nums: Array = a["numbers"]
	if nums.is_empty():
		return
	var intents: Dictionary = a["intents"]
	var price_ctx := intents.has("price") or intents.has("discount")
	for n in nums:
		st.amounts.append({"value": n, "turn": st.turn, "kind": "precio" if price_ctx else "cifra"})
	if not price_ctx:
		return
	var price: int = nums[0]
	if st.stated_price < 0:
		st.stated_price = price
		return
	if price == st.stated_price:
		return
	var is_discount := intents.has("discount") and price < st.stated_price
	if is_discount:
		st.stated_price = price
		events.append("price_lowered")
		return
	# Cambiar el precio sin justificarlo es una contradicción
	var detector := PersonalityDB.has_quirk(st.personality_id, "detects_contradictions")
	st.contradictions.append({"a": st.stated_price, "b": price, "turn": st.turn})
	d["suspicion"] += 16.0 if detector else 9.0
	d["trust"] -= 8.0 if detector else 4.0
	events.append("contradiction")
	st.stated_price = price


static func _track_promises(st: ConversationState, a: Dictionary, d: Dictionary, events: Array) -> void:
	var intents: Dictionary = a["intents"]
	if intents.has("promise"):
		st.promises.append({"text": String(a["text"]).substr(0, 60), "turn": st.turn, "fulfilled": false})
		events.append("promise_made")
		return
	var explains := intents.has("benefit") or intents.has("simple_explanation") or intents.has("offer_pitch") or intents.has("guarantee")
	for pr in st.promises:
		if pr["fulfilled"]:
			continue
		if explains:
			pr["fulfilled"] = true
			d["trust"] += 3
			events.append("promise_kept")
		elif st.turn - int(pr["turn"]) >= 3 and not pr.get("reminded", false):
			pr["reminded"] = true
			d["trust"] -= 4
			d["patience"] -= 3
			events.append("promise_overdue")


static func _track_objections(st: ConversationState, a: Dictionary, p: Dictionary, d: Dictionary, events: Array, rng: RandomNumberGenerator) -> void:
	var intents: Dictionary = a["intents"]
	for obj in st.pending_objections.duplicate():
		var res: Array = PersonalityDB.OBJECTIONS[obj]["resolved_by"]
		for r in res:
			if float(intents.get(r, 0.0)) >= 0.5:
				st.pending_objections.erase(obj)
				st.resolved_objections.append(obj)
				d["trust"] += 6
				d["suspicion"] -= 4
				events.append("objection_resolved:" + obj)
				break
	# Nuevas objeciones entre los turnos 2 y 7 (máx. según dificultad)
	var difficulty := int(ClientDB.get_c(st.client_id)["difficulty"])
	var max_obj := 1 + difficulty
	if st.turn >= 2 and st.turn <= 7 and st.raised_count < max_obj and st.pending_objections.size() < 2:
		var chance := 0.35 + 0.1 * difficulty
		if rng.randf() < chance:
			var pool: Array = p["objections"].filter(func(o): return not st.pending_objections.has(o) and not st.resolved_objections.has(o))
			if intents.has("jargon") and not st.resolved_objections.has("jargon") and not st.pending_objections.has("jargon") and PersonalityDB.has_quirk(st.personality_id, "needs_simple"):
				pool = ["jargon"]
			if not pool.is_empty():
				var o: String = pool[rng.randi() % pool.size()]
				st.pending_objections.append(o)
				st.raised_count += 1
				events.append("objection_raised:" + o)


## Integra ajustes sugeridos por la IA remota: acotados y con peso parcial.
static func merge_ai_deltas(st: ConversationState, ai_deltas: Dictionary, max_abs := 8.0, weight := 0.5) -> Dictionary:
	var applied := {}
	for k in KEYS:
		var v := clampf(float(ai_deltas.get(k, 0.0)), -max_abs, max_abs) * weight
		applied[k] = v
		st.set(k, float(st.get(k)) + v)
	st.clamp_all()
	st.update_provisional()
	return applied


## Tiempo: cada segundo de llamada cansa un poco.
static func tick(st: ConversationState, delta: float, mods: Dictionary = {}) -> String:
	st.elapsed += delta
	st.patience -= delta * 0.12 * float(PersonalityDB.get_p(st.personality_id)["mult"]["patience_drain"]) * float(mods.get("patience_drain_mult", 1.0))
	st.clamp_all()
	if st.elapsed >= st.time_limit:
		return "tiempo"
	if st.patience <= 0.0:
		return "paciencia"
	return ""
