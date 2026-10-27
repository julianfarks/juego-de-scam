class_name BossLines
extends RefCounted
## Comentarios de respaldo (sin IA) del jefe Don Ramiro Billetes y comentarios cómicos
## de fin de llamada. Usan los datos reales de la partida, no frases al azar.

const BOSS_NAME := "Don Ramiro Billetes"


static func grade_for(income: int, quota: int, hangups: int, calls: int) -> String:
	var ratio := float(income) / maxf(1.0, float(quota))
	var g := "F"
	if ratio >= 2.0:
		g = "S"
	elif ratio >= 1.3:
		g = "A"
	elif ratio >= 1.0:
		g = "B"
	elif ratio >= 0.7:
		g = "C"
	elif ratio >= 0.4:
		g = "D"
	if calls >= 3 and hangups >= calls - 1 and g in ["S", "A"]:
		g = "B"
	return g


static func evaluation(stats: Dictionary, rng: RandomNumberGenerator) -> String:
	var income: int = stats["income"]
	var quota: int = stats["quota"]
	var grade: String = stats["grade"]
	var parts := []
	match grade:
		"S":
			parts.append(_pick(rng, ["¡%d de %d! Voy a enmarcar tu cara en el pasillo. Bueno, una foto borrosa." % [income, quota], "¡Bestial! %d. Hasta el pez de la pecera ha aplaudido." % income]))
		"A":
			parts.append(_pick(rng, ["%d. Superaste la cuota con estilo. No te acostumbres a los elogios." % income, "Buen trabajo: %d. Casi me emociono. Casi." % income]))
		"B":
			parts.append(_pick(rng, ["Cuota cumplida por los pelos: %d de %d. Ni frío ni calor, como el café de la máquina." % [income, quota], "%d. Aprobado raspado. Mi sobrino lo haría igual, y es un perro." % income]))
		"C":
			parts.append(_pick(rng, ["%d de %d. Te faltó poco… poco talento, digo." % [income, quota], "No llegaste: %d. Mañana quiero ver garra, no excusas." % income]))
		_:
			parts.append(_pick(rng, ["¿%d? ¿De %d? ¿Estabas vendiendo o rezando?" % [income, quota], "%d. He visto plantas de plástico vender más." % income]))
	if int(stats.get("hangups", 0)) >= 3:
		parts.append("Y te colgaron %d veces. El teléfono ya te tiene miedo." % stats["hangups"])
	if int(stats.get("contradictions", 0)) >= 2:
		parts.append("Te pillaron %d contradicciones. Apúntate las cifras, genio." % stats["contradictions"])
	if int(stats.get("best_sale", 0)) >= 250:
		parts.append("Esa venta de %d me ha gustado. Repítela." % stats["best_sale"])
	if int(stats.get("calls", 0)) <= 1:
		parts.append("¿Una sola llamada en todo el día? ¿Te pagan por mirar la pared?")
	if int(stats.get("incidents", 0)) >= 3:
		parts.append("Sí, sí, hubo averías. La cuota no entiende de averías.")
	return " ".join(PackedStringArray(parts.slice(0, 3)))


static func remark(kind: String, rng: RandomNumberGenerator, data: Dictionary = {}) -> String:
	match kind:
		"quota_half":
			return _pick(rng, ["Vas por la mitad de la cuota. La otra mitad no se vende sola.", "Mitad del objetivo. Ni se te ocurra relajarte."])
		"quota_done":
			return _pick(rng, ["¡Cuota cumplida! Lo que venga ahora es para mi yate imaginario.", "Cuota hecha. ¡Sigue, que el récord está ahí!"])
		"late_low":
			return _pick(rng, ["Queda poco y vas fatal. ¡A los teléfonos!", "El reloj corre y tu cuota no. ¡Muévete!"])
		"sale":
			return _pick(rng, ["¡Eso es! %d más para la empresa." % int(data.get("amount", 0)), "¡Venta! Así me gusta, tiburón."])
		"hangup":
			return _pick(rng, ["¿Te han colgado otra vez? Habla con más encanto.", "Otro que cuelga. ¿Les estás contando tu vida?"])
		"inspection_good":
			return _pick(rng, ["Bien, bien, trabajando. Sigue así.", "Te veo ocupado. Eso me gusta."])
		"inspection_bad":
			return _pick(rng, ["¿Paseando? ¿Contemplando la planta? Multa de 15.", "Te pago por llamar, no por hacer turismo. -15."])
		"idle":
			return _pick(rng, ["El teléfono no se contesta solo.", "¿Hay alguien vivo en esa mesa?"])
		"missed":
			return _pick(rng, ["¡Has dejado sonar una llamada! Eso era dinero.", "Llamada perdida. Dinero perdido. Felicidades."])
	return ""


## Comentario cómico de fin de llamada basado en lo que realmente pasó.
static func call_comment(st: ConversationState, outcome: String, amount: int, rng: RandomNumberGenerator) -> String:
	var c := ClientDB.get_c(st.client_id)
	var first := String(c["name"]).split(" ")[0]
	var offer := String(OfferDB.get_o(st.offer_id)["name"]).to_lower()
	if outcome == "success":
		if st.contradictions.size() > 0:
			return "%s compró %s a pesar de tus %d contradicciones. Milagro de oficina." % [first, offer, st.contradictions.size()]
		if st.resolved_objections.size() >= 2:
			return "Desmontaste %d objeciones y vendiste %s. El guion te envidia." % [st.resolved_objections.size(), offer]
		if amount >= 300:
			return "%d por %s. Alguien acaba de comprar aire caro." % [amount, offer]
		return _pick(rng, ["%s ya presume de su %s. Nadie sabe para qué sirve." % [first, offer], "Venta cerrada en %d s. %s ni pestañeó." % [int(st.elapsed), first]])
	if st.insults > 0:
		return "Insultar al cliente: técnica poco recomendada por los expertos (y por %s)." % first
	if outcome == "contradiction":
		return "%s te pilló: %d no es lo mismo que %d. Las matemáticas no perdonan." % [first, st.contradictions[-1]["a"] if st.contradictions.size() > 0 else 0, st.contradictions[-1]["b"] if st.contradictions.size() > 0 else 0]
	if st.unfulfilled_promises().size() > 0:
		return "Prometiste explicar algo y nunca lo hiciste. %s sigue esperando." % first
	if st.pending_objections.size() > 0:
		return "%s se quedó con la duda: «%s». Resolver objeciones ayuda, dicen." % [first, PersonalityDB.OBJECTIONS[st.pending_objections[0]]["label"]]
	if outcome == "callback":
		return "%s quiere que le vuelvas a llamar. Lo tienes en la lista del ordenador." % first
	if outcome == "interested":
		return "%s se quedó con ganas. Un empujoncito más y caía." % first
	if outcome == "tech_fail":
		return "La centralita se comió la llamada. No fue culpa tuya. Esta vez."
	if outcome == "interrupted":
		return "Entre una cosa y otra, la llamada se fue al garete."
	if st.patience <= 1.0:
		return "Agotaste la paciencia de %s en %d turnos. Récord personal." % [first, st.turn]
	return _pick(rng, ["%s dijo que no. Ni el %s pudo salvarte." % [first, offer], "Llamada sin premio. Pero el café sigue caliente."])


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return str(arr[rng.randi() % arr.size()]) if not arr.is_empty() else ""
