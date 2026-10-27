class_name ConversationState
extends RefCounted
## Estado estructurado de una llamada: emociones, objeciones, memoria de hechos
## (cifras, promesas, preguntas respondidas, contradicciones) e historial resumido.
## Este estado es NARRATIVO. El dinero vive en Economy y nunca se toca desde aquí.

var client_id := ""
var personality_id := ""
var offer_id := ""

var trust := 30.0
var patience := 60.0
var humor := 40.0
var understanding := 30.0
var suspicion := 25.0

var pending_objections: Array = []     # ids de OBJECTIONS
var resolved_objections: Array = []
var raised_count := 0

var amounts: Array = []                # [{value, turn, kind}]
var stated_price := -1                 # primera cifra de precio que dijo el jugador
var promises: Array = []               # [{text, turn, fulfilled}]
var contradictions: Array = []         # [{a, b, turn}]
var client_questions: Array = []       # [{text, expects, turn, answered}]
var pending_question: Dictionary = {}
var decisions: Array = []              # ["rechazó pagar en el turno 4", ...]
var topics_mentioned: Array = []
var intro_done := false
var offer_explained := false
var greeted := false
var insults := 0
var close_attempts := 0
var same_intent_streak := 0
var last_top_intent := ""
var off_topic_streak := 0
var provisional := "en_curso"          # en_curso | receptivo | dudoso | hostil
var ended := false
var outcome := ""

var history: Array = []                # [{who: "player"/"client", text, turn}]
var summary := ""                      # resumen de turnos antiguos
var turn := 0
var elapsed := 0.0
var time_limit := 150.0


func setup(p_client_id: String, p_offer_id: String, extra_trust := 0.0, extra_patience := 0.0) -> void:
	client_id = p_client_id
	offer_id = p_offer_id
	var c := ClientDB.get_c(client_id)
	personality_id = c["personality"]
	var base: Dictionary = PersonalityDB.get_p(personality_id)["base"]
	trust = clampf(base["trust"] + extra_trust, 0, 100)
	patience = clampf(base["patience"] + extra_patience, 0, 100)
	humor = base["humor"]
	understanding = base["understanding"]
	suspicion = base["suspicion"]


func clamp_all() -> void:
	trust = clampf(trust, 0.0, 100.0)
	patience = clampf(patience, 0.0, 100.0)
	humor = clampf(humor, 0.0, 100.0)
	understanding = clampf(understanding, 0.0, 100.0)
	suspicion = clampf(suspicion, 0.0, 100.0)


func add_history(who: String, text: String) -> void:
	history.append({"who": who, "text": text, "turn": turn})
	# Mantiene el historial acotado: los turnos antiguos pasan al resumen.
	if history.size() > 14:
		var old: Dictionary = history.pop_front()
		var short_txt: String = old["text"].substr(0, 70)
		summary += ("J: " if old["who"] == "player" else "C: ") + short_txt + " | "
		if summary.length() > 700:
			summary = summary.substr(summary.length() - 700)


func recent_history(n := 8) -> Array:
	var start := maxi(0, history.size() - n)
	return history.slice(start)


func unfulfilled_promises() -> Array:
	return promises.filter(func(p): return not p["fulfilled"])


func emotion() -> String:
	if suspicion >= 75:
		return "distrust"
	if patience <= 20:
		return "angry"
	if humor >= 70 and trust >= 45:
		return "joy"
	if understanding <= 20:
		return "confused"
	if trust >= 60:
		return "happy"
	return "neutral"


func update_provisional() -> void:
	if suspicion >= 70 or patience <= 15:
		provisional = "hostil"
	elif trust >= 55 and understanding >= 45 and pending_objections.size() <= 1:
		provisional = "receptivo"
	elif trust < 30 or suspicion >= 50:
		provisional = "dudoso"
	else:
		provisional = "en_curso"


## Datos compactos para la IA remota y para las pantallas de depuración.
func to_prompt_dict() -> Dictionary:
	var objs := []
	for o in pending_objections:
		objs.append(PersonalityDB.OBJECTIONS[o]["label"])
	var proms := []
	for p in unfulfilled_promises():
		proms.append(p["text"])
	var amts := []
	for a in amounts.slice(maxi(0, amounts.size() - 6)):
		amts.append(a["value"])
	var contr := []
	for c in contradictions:
		contr.append("dijo %d y luego %d" % [c["a"], c["b"]])
	return {
		"trust": int(trust), "patience": int(patience), "humor": int(humor),
		"understanding": int(understanding), "suspicion": int(suspicion),
		"pending_objections": objs, "resolved_objections": resolved_objections.size(),
		"amounts_mentioned": amts, "stated_price": stated_price, "unfulfilled_promises": proms,
		"contradictions": contr, "pending_question": pending_question.get("text", ""),
		"decisions": decisions.slice(maxi(0, decisions.size() - 4)), "provisional": provisional,
		"turn": turn, "seconds_left": int(maxf(0.0, time_limit - elapsed)), "summary": summary,
		"intro_done": intro_done, "offer_explained": offer_explained,
	}
