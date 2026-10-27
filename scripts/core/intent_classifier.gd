class_name IntentClassifier
extends RefCounted
## Analiza lo que dice el jugador combinando varias señales: familias léxicas con
## raíces, estructura de la frase (pregunta, longitud, complejidad), cifras
## (en dígitos o en palabras), referencias a la oferta, a la pregunta pendiente del
## cliente y a datos del cliente. Devuelve puntuaciones por intención, no una sola
## palabra clave. Lo usan el motor local (modo sin conexión) y el reglamento común.

const LEX := {
	"greeting": ["hola", "buenos dias", "buenas tardes", "buenas noches", "buenas", "que tal", "saludos", "alo", "como esta", "como le va"],
	"introduce": ["me llamo", "mi nombre es", "soy de", "le llamo de", "le hablo de", "de parte de", "represento", "nuestra empresa", "trabajo en", "trabajo para", "somos una", "somos la", "teletimo", "ofertas milagrosas"],
	"offer_pitch": ["oferta", "promocion", "producto", "servicio", "plan ", "seguro", "membresia", "suscripcion", "regalo", "ha ganado", "ganador", "le ofrezco", "le traigo", "tenemos", "vendemos", "le propongo", "exclusiv"],
	"benefit": ["beneficio", "ventaja", "ahorr", "gratis", "incluye", "le permite", "sirve para", "podra", "proteg", "tranquilidad", "disfrut", "mejorar", "le ayuda", "nunca mas", "le dara", "le va a encantar", "resuelve"],
	"price": ["precio", "cuesta", "vale ", "pesos", "euros", "dolares", "monedas", "solo paga", "pago", "cuota", "al mes", "mensual", "unicamente", "tarifa", "importe"],
	"discount": ["descuento", "rebaja", "mitad de precio", "2x1", "dos por uno", "gratis el primer", "sin coste", "sin costo", "oferta especial", "le hago un precio", "precio especial", "por ser usted"],
	"urgency": ["hoy", "ahora mismo", "ultimo dia", "solo hoy", "se acaba", "quedan pocos", "urgente", "rapido", "inmediat", "antes de que", "limitad", "ultima oportunidad", "ya mismo"],
	"flattery": ["usted parece", "inteligente", "se nota que", "una persona como usted", "elegante", "encantador", "encantadora", "simpatic", "que voz", "guap", "especial", "listo", "lista", "muy amable", "admiro"],
	"joke": ["jaja", "jeje", "haha", "jiji", "broma", "chiste", "lol", "xd", "es broma", "de chiste"],
	"empathy": ["entiendo", "comprendo", "tiene razon", "le entiendo", "es normal", "no se preocupe", "tranquil", "lo se", "respeto", "me pongo en su lugar", "es logico"],
	"reassure_security": ["es seguro", "seguridad", "confianza", "protegid", "encript", "certificad", "legal", "oficial", "garantizad", "confie", "fiable", "serio"],
	"guarantee": ["garantia", "devolucion", "devuelvo", "reembolso", "sin riesgo", "si no le gusta", "por escrito", "contrato", "le mando", "le envio", "correo", "factura", "recibo"],
	"social_proof": ["miles de", "todo el mundo", "sus vecinos", "famos", "recomendad", "numero uno", "otros clientes", "muy popular", "la gente", "millones de", "el mas vendido"],
	"ask_payment": ["tarjeta", "numero de la tarjeta", "datos de pago", "cvv", "codigo de seguridad", "fecha de caducidad", "vencimiento", "me da sus datos", "me dicta", "pagar ahora", "cobrar", "domicili", "medio de pago", "como quiere pagar", "datos bancarios"],
	"pressure": ["tiene que", "debe ", "obligatori", "si no ", "multa", "problema legal", "policia", "demanda", "perdera", "se arrepentira", "no tiene opcion", "o paga", "sancion"],
	"insult": ["tonto", "idiota", "estupid", "imbecil", "inutil", "callese", "callate", "pesad", "burro", "bobo", "tarado", "vieja loca", "viejo loco"],
	"apology": ["perdon", "disculp", "lo siento", "perdone", "me equivoque", "error mio"],
	"smalltalk": ["el clima", "el tiempo hace", "lluvia", "calor", "frio", "perro", "gato", "mascota", "familia", "futbol", "partido", "comida", "fin de semana", "vacaciones", "su dia", "como esta usted", "hijos", "nietos"],
	"farewell": ["adios", "hasta luego", "chao", "nos vemos", "gracias por su tiempo", "que tenga buen dia", "hasta pronto"],
	"jargon": ["blockchain", "algoritmo", "sinergia", "apalanca", "rendimiento", "cripto", "nft", "kpi", "roi", "escalable", "disrupt", "interes compuesto", "cuantic", "token", "liquidez", "dividendo", "volatil", "optimiz"],
	"simple_explanation": ["es como", "en pocas palabras", "o sea", "es decir", "simplemente", "facil", "sencill", "basicamente", "imagine que", "por ejemplo", "le explico", "en resumen"],
	"promise": ["luego le cuento", "ahora le digo", "mas tarde", "en un momento le", "se lo explico", "despues le", "ahora le explico", "enseguida le", "ya le cuento", "le prometo"],
	"competitive_hook": ["ganar", "mejor que", "vecino", "nadie mas", "el primero", "la primera", "reto", "apuesto", "competencia", "ranking", "superar", "campeon", "ramon"],
	"drama_hook": ["increible", "historia", "imagine", "emocionante", "tragedia", "milagro", "destino", "su vida va a cambiar", "sueno", "magia", "aventura", "corazon"],
	"honesty": ["sinceramente", "le sere sincero", "honestamente", "con toda franqueza", "la verdad es que", "no le voy a mentir", "le soy honesto"],
	"yes": ["si", "claro", "vale", "de acuerdo", "por supuesto", "exacto", "correcto", "ok", "okay"],
	"no": ["no", "nada", "nunca", "jamas", "para nada"],
}

const QUESTION_STARTS := ["que", "como", "cuando", "donde", "por que", "porque", "cual", "cuales", "quien", "cuanto", "cuanta", "le gustaria", "tiene", "usted", "sabe", "ha "]

const NUM_WORDS := {
	"cero": 0, "uno": 1, "una": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
	"diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16, "diecisiete": 17, "dieciocho": 18,
	"diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintidos": 22, "veinticinco": 25, "treinta": 30, "cuarenta": 40, "cincuenta": 50,
	"sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100, "ciento": 100, "doscientos": 200, "trescientos": 300,
	"cuatrocientos": 400, "quinientos": 500, "seiscientos": 600, "setecientos": 700, "ochocientos": 800, "novecientos": 900, "mil": 1000,
}


static func normalize(text: String) -> String:
	var s := text.to_lower()
	var from := "áàäâéèëêíìïîóòöôúùüûñç¿¡"
	var to := "aaaaeeeeiiiioooouuuunc  "
	var out := ""
	for ch in s:
		var idx := from.find(ch)
		out += to[idx] if idx >= 0 else ch
	var clean := ""
	for ch in out:
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or ch == "?" or ch == " " or ch == "%":
			clean += ch
		else:
			clean += " "
	while clean.find("  ") >= 0:
		clean = clean.replace("  ", " ")
	return " " + clean.strip_edges() + " "


static func extract_numbers(norm: String) -> Array:
	var nums := []
	var words := norm.strip_edges().split(" ", false)
	var acc := -1
	var cur := 0
	for w in words:
		var digits := w.replace("?", "")
		if digits.is_valid_int():
			if acc >= 0:
				nums.append(acc + cur)
				acc = -1
				cur = 0
			nums.append(int(digits))
			continue
		if NUM_WORDS.has(digits):
			var v: int = NUM_WORDS[digits]
			if acc < 0:
				acc = 0
			if v == 1000:
				cur = maxi(cur, 1) * 1000
				acc += cur
				cur = 0
			else:
				cur += v
		elif digits == "y" and acc >= 0:
			continue
		elif acc >= 0:
			nums.append(acc + cur)
			acc = -1
			cur = 0
	if acc >= 0:
		nums.append(acc + cur)
	var out := []
	for n in nums:
		if n >= 2 and n <= 100000:
			out.append(n)
	return out


## context: {offer_id, pending_question_expects:Array, client_facts:Dictionary, client_name:String, last_intents:Array}
static func analyze(text: String, context: Dictionary = {}) -> Dictionary:
	var norm := normalize(text)
	var words := norm.strip_edges().split(" ", false)
	var wc := words.size()
	var scores := {}
	for intent in LEX.keys():
		var s := 0.0
		for kw in LEX[intent]:
			var k: String = kw
			if intent in ["yes", "no"]:
				if (" " + k + " ") in norm:
					s += 1.0
			elif k.ends_with(" "):
				if (" " + k) in norm:
					s += 1.0
			elif (" " + k) in norm or (k.length() >= 6 and k in norm):
				s += 1.0
		if s > 0.0:
			scores[intent] = minf(1.0, 0.55 + 0.25 * (s - 1.0))
	# Señales estructurales
	var is_question := "?" in text or (wc > 1 and _starts_with_any(norm.strip_edges(), QUESTION_STARTS) and wc < 18)
	if is_question:
		scores["question"] = maxf(scores.get("question", 0.0), 0.7)
	var numbers := extract_numbers(norm)
	if not numbers.is_empty():
		scores["price"] = maxf(scores.get("price", 0.0), 0.6)
	var total_len := 0
	for w in words:
		total_len += w.length()
	var avg_len := float(total_len) / maxf(1.0, wc)
	var complexity := clampf((avg_len - 4.0) / 4.0 + wc / 60.0, 0.0, 1.0)
	if wc >= 45:
		scores["long"] = 1.0
	elif wc > 0 and wc <= 14 and (scores.size() > 0):
		scores["brief"] = 0.7
	# Mención de la oferta seleccionada → es una presentación de la oferta
	var offer_id: String = context.get("offer_id", "")
	if offer_id != "":
		var o := OfferDB.get_o(offer_id)
		for kw in o["keywords"]:
			if kw in norm:
				scores["offer_pitch"] = maxf(scores.get("offer_pitch", 0.0), 0.8)
				break
	# ¿Responde a la pregunta que hizo el cliente?
	var expects: Array = context.get("pending_question_expects", [])
	if not expects.is_empty() and wc >= 2:
		for e in expects:
			if scores.has(e) or (e == "price" and not numbers.is_empty()):
				scores["answer"] = 0.9
				break
		if not scores.has("answer") and not is_question and wc >= 5 and not scores.has("insult"):
			scores["answer"] = 0.45  # intento de respuesta genérico
	# Menciona algo del cliente (su mascota, su ciudad…): conecta personalmente
	var facts: Dictionary = context.get("client_facts", {})
	for k in facts.keys():
		var fact_words := normalize(str(facts[k])).strip_edges().split(" ", false)
		for fw in fact_words:
			if fw.length() >= 5 and (" " + fw) in norm:
				scores["personal"] = 0.8
				break
	# Si no hay nada reconocible y el mensaje no es trivial: poco claro
	var meaningful := scores.keys().filter(func(k): return not k in ["brief", "long", "yes", "no"])
	if meaningful.is_empty():
		scores["unclear"] = 0.7 if wc >= 3 else 0.5
	var top := ""
	var best := 0.0
	for k in scores.keys():
		if k in ["brief", "long"]:
			continue
		if scores[k] > best:
			best = scores[k]
			top = k
	return {
		"text": text, "norm": norm, "intents": scores, "top": top, "numbers": numbers,
		"is_question": is_question, "word_count": wc, "complexity": complexity,
	}


static func _starts_with_any(s: String, arr: Array) -> bool:
	for a in arr:
		if s.begins_with(a + " ") or s == a:
			return true
	return false


static func has(analysis: Dictionary, intent: String, threshold := 0.5) -> bool:
	return float(analysis["intents"].get(intent, 0.0)) >= threshold
