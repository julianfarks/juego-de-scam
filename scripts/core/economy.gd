class_name Economy
extends RefCounted
## Reglas económicas AUTORITATIVAS. Ninguna respuesta de la IA, ni lo que el jugador
## diga en voz alta, puede fijar cantidades: el importe sale del catálogo de ofertas,
## del estado de la llamada y de las mejoras, y siempre queda dentro de los límites.

const OUTCOMES := {
	"success": "Transacción ficticia completada",
	"interested": "Interesado, pero indeciso",
	"callback": "Pide que le llamen otra vez",
	"rejected": "Rechazó la propuesta",
	"contradiction": "Detectó contradicciones",
	"hangup": "Colgó",
	"interrupted": "Interrumpida por un evento",
	"tech_fail": "Fallo técnico",
}

const MIN_P := 0.03
const MAX_P := 0.93
const AI_HINT_MAX := 0.06


static func close_probability(st: ConversationState, mods: Dictionary = {}, ai_hint := 0.0) -> float:
	var p := PersonalityDB.get_p(st.personality_id)
	var base := 0.02
	base += (st.trust - 35.0) / 100.0 * 0.9
	base += (st.understanding - 35.0) / 100.0 * 0.5
	base -= (st.suspicion - 25.0) / 100.0 * 0.8
	base += (st.humor - 45.0) / 100.0 * 0.15
	base -= 0.09 * st.pending_objections.size()
	base -= 0.12 * st.contradictions.size()
	base -= 0.06 * st.unfulfilled_promises().size()
	if not st.offer_explained:
		base -= 0.15
	# Insistir con el cierre baja la probabilidad
	base -= 0.07 * st.close_attempts
	# Interés que estima la IA (0-10): influye, pero acotado a ±0,15
	if st.ai_interest >= 0:
		base += clampf((float(st.ai_interest) - 5.0) * 0.03, -0.15, 0.15)
	base *= float(p["accept"])
	base *= ClientDB.offer_affinity(st.client_id, st.offer_id)
	base *= float(OfferDB.get_o(st.offer_id)["plaus"])
	base += float(mods.get("close_bonus", 0.0))
	base += clampf(ai_hint, 0.0, AI_HINT_MAX)  # la IA solo puede insinuar, muy poco
	return clampf(base, MIN_P, MAX_P)


static func compute_amount(st: ConversationState, day: int, mods: Dictionary = {}) -> int:
	var o := OfferDB.get_o(st.offer_id)
	var price := float(o["price"])
	var mult := 0.85 + st.trust / 250.0 + st.understanding / 500.0
	mult *= 1.0 + 0.06 * float(maxi(0, day - 1))
	mult *= float(mods.get("amount_mult", 1.0))
	mult *= float(mods.get("next_call_mult", 1.0))
	var amount := int(round(price * mult))
	return clampi(amount, int(o["price"] * 0.5), int(o["max"]))


## Intento de cierre. Lo decide una tirada con la probabilidad calculada por las reglas.
static func attempt_close(st: ConversationState, rng: RandomNumberGenerator, day: int, mods: Dictionary = {}, ai_hint := 0.0) -> Dictionary:
	var p := close_probability(st, mods, ai_hint)
	st.close_attempts += 1
	var roll := rng.randf()
	if roll < p:
		var amount := compute_amount(st, day, mods)
		st.decisions.append("aceptó pagar en el turno %d" % st.turn)
		return {"success": true, "p": p, "amount": amount, "card": FakeCard.generate(rng, ClientDB.get_c(st.client_id)["name"])}
	st.decisions.append("se negó a pagar en el turno %d" % st.turn)
	st.suspicion = clampf(st.suspicion + 12.0, 0, 100)
	st.patience = clampf(st.patience - 12.0, 0, 100)
	st.trust = clampf(st.trust - 4.0, 0, 100)
	st.update_provisional()
	return {"success": false, "p": p, "amount": 0, "card": {}}


## Clasifica cómo terminó la llamada si no hubo transacción.
static func classify_end(st: ConversationState, reason: String) -> String:
	match reason:
		"success":
			return "success"
		"interrupted":
			return "interrupted"
		"tech_fail":
			return "tech_fail"
		"sospecha":
			return "contradiction" if not st.contradictions.is_empty() else "hangup"
		"insultos", "paciencia", "tiempo":
			if not st.contradictions.is_empty() and PersonalityDB.has_quirk(st.personality_id, "detects_contradictions"):
				return "contradiction"
			if reason == "tiempo" and st.trust >= 50:
				return "callback"
			return "hangup"
	# El jugador colgó
	if st.trust >= 60 and st.understanding >= 50 and st.suspicion < 50:
		return "callback"
	if st.trust >= 45 and st.suspicion < 60:
		return "interested"
	if not st.contradictions.is_empty() and st.suspicion >= 60:
		return "contradiction"
	return "rejected"


## Pequeña compensación por llamadas no cerradas pero bien llevadas (comisión de mentira).
static func consolation(outcome: String) -> int:
	match outcome:
		"callback":
			return 5
		"interested":
			return 3
	return 0


static func quota_for_day(day: int) -> int:
	return CampaignDB.quota(day)
