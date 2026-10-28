class_name Economy
extends RefCounted
## Reglas económicas AUTORITATIVAS. La IA nunca fija cantidades ni decide si se paga:
## el importe es el último precio que DIJO EL JUGADOR (extraído de su frase por reglas)
## por la cantidad propuesta, con tope según el presupuesto del cliente; el «sí» sale
## de una tirada con la probabilidad que calculan estas reglas.

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
const COMMISSION_RATE := 0.5          # parte de cada venta que cobra el jugador
const AMOUNT_CAP_X_BUDGET := 3.0       # nadie paga más de 3 veces su presupuesto


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
	# Precio frente al presupuesto del cliente (reglas)
	base += Proposal.price_factor(st.stated_price, st.quantity, st.budget)
	base *= float(p["accept"])
	base *= Proposal.affinity(st.client_id, st.tags)
	base += float(mods.get("close_bonus", 0.0))
	base += clampf(ai_hint, 0.0, AI_HINT_MAX)  # la IA solo puede insinuar, muy poco
	return clampf(base, MIN_P, MAX_P)


## Importe que paga el cliente: el precio acordado (el último que dijo el vendedor)
## por la cantidad, con un tope en función de su presupuesto. Lo que el jugador
## cobra es una COMISIÓN de ese importe (ver commission()).
static func compute_amount(st: ConversationState) -> int:
	var price := maxi(0, st.stated_price)
	var amount := price * maxi(1, st.quantity)
	return clampi(amount, 0, int(st.budget * AMOUNT_CAP_X_BUDGET))


static func commission(amount: int, mods: Dictionary = {}) -> int:
	var mult := float(mods.get("amount_mult", 1.0)) * float(mods.get("next_call_mult", 1.0))
	return int(round(float(amount) * COMMISSION_RATE * mult))


## ¿Se puede intentar cerrar? Sin propuesta o sin precio, el cliente no puede pagar
## (pregunta por lo que falta en vez de contar como un intento fallido).
static func missing_for_close(st: ConversationState) -> String:
	if not st.offer_explained and st.proposal == "" and st.tags.is_empty():
		return "propuesta"
	if st.stated_price <= 0:
		return "precio"
	return ""


## Intento de cierre. Lo decide una tirada con la probabilidad calculada por las reglas.
static func attempt_close(st: ConversationState, rng: RandomNumberGenerator, day: int, mods: Dictionary = {}, ai_hint := 0.0) -> Dictionary:
	var missing := missing_for_close(st)
	if missing != "":
		st.decisions.append("pidió saber %s antes de pagar (turno %d)" % ["qué le venden" if missing == "propuesta" else "el precio", st.turn])
		return {"success": false, "missing": missing, "p": 0.0, "amount": 0, "card": {}}
	var p := close_probability(st, mods, ai_hint)
	st.close_attempts += 1
	var roll := rng.randf()
	if roll < p:
		var amount := compute_amount(st)
		st.decisions.append("aceptó pagar %d en el turno %d" % [amount, st.turn])
		return {"success": true, "missing": "", "p": p, "amount": amount, "card": FakeCard.generate(rng, ClientDB.get_c(st.client_id)["name"])}
	st.decisions.append("se negó a pagar en el turno %d" % st.turn)
	st.suspicion = clampf(st.suspicion + 12.0, 0, 100)
	st.patience = clampf(st.patience - 12.0, 0, 100)
	st.trust = clampf(st.trust - 4.0, 0, 100)
	st.update_provisional()
	return {"success": false, "missing": "", "p": p, "amount": 0, "card": {}}


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
