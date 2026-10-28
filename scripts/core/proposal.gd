class_name Proposal
extends RefCounted
## Reglas DETERMINISTAS sobre la propuesta libre que el jugador inventa durante la
## llamada (queso artesanal, jardinería, un seguro absurdo…). La IA describe con sus
## palabras lo que ha entendido, pero las categorías, la cantidad y el precio que
## cuentan para el dinero se sacan aquí, del texto del jugador, con reglas fijas.

## Categorías de producto → palabras que las delatan (texto normalizado, sin tildes).
const TAG_WORDS := {
	"comida": ["queso", "jamon", "embutido", "miel", "pan", "pastel", "tarta", "galleta", "vino", "aceite", "mermelada", "chocolate", "cafe", "comida", "receta", "fruta", "verdura", "huevo", "salsa", "conserva", "cerveza"],
	"salud": ["hierba", "infusion", "remedio", "vitamina", "masaje", "salud", "dieta", "medicin", "crema", "pomada", "yoga", "relaj"],
	"hogar": ["casa", "hogar", "cocina", "mueble", "lampara", "colchon", "electrodomest", "tostador", "nevera", "lavadora", "limpieza", "jardin", "planta", "maceta", "calcetin", "toalla"],
	"servicios": ["servicio", "reparacion", "arreglo", "limpieza", "jardineria", "entrega", "envio", "domicilio", "mantenimiento", "clases", "curso", "asesor", "cuidado", "paseo"],
	"seguro": ["seguro", "garantia", "proteccion", "cobertura", "poliza", "asegur"],
	"tecnologia": ["wifi", "internet", "movil", "app", "aplicacion", "robot", "ordenador", "tecnolog", "digital", "cripto", "router"],
	"inversion": ["inversion", "acciones", "cripto", "moneda", "rentab", "interes", "fondo", "terreno", "parcela"],
	"lujo": ["lujo", "vip", "exclusiv", "premium", "oro", "diamante", "titulo", "duque", "crucero"],
	"viajes": ["viaje", "crucero", "vacacion", "hotel", "billete", "excursion", "tour"],
	"mascotas": ["mascota", "perro", "gato", "pez", "loro", "hamster", "veterinar"],
	"suerte": ["loteria", "sorteo", "suerte", "premio", "amuleto", "horoscopo"],
	"rareza": ["alien", "extraterrest", "fantasma", "magia", "magico", "imaginari", "invisible", "dragon", "unicornio", "absurd", "coleccion", "rareza"],
}

const UNIT_WORDS := ["unidades", "unidad", "cajas", "caja", "kilos", "kilo", "kg", "botes", "bote", "paquetes", "paquete", "botellas", "botella", "piezas", "pieza", "packs", "pack", "lotes", "lote", "sesiones", "sesion", "meses", "mes", "visitas", "visita", "frascos", "frasco", "ruedas", "rueda"]
const MAX_QUANTITY := 12

const NUM_WORDS := {"un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12, "media docena": 6, "docena": 12}


## Categorías detectadas en un texto (normalizado o no).
static func tags_for(text: String) -> Array:
	var norm := " " + IntentClassifier.normalize(text) + " "
	var out := []
	for tag in TAG_WORDS.keys():
		for w in TAG_WORDS[tag]:
			if norm.contains(w):
				out.append(tag)
				break
	return out


## Cantidad que el vendedor propone («dos cajas», «3 kilos», «media docena»).
## Si no dice ninguna, devuelve 0 (sin cantidad explícita). Se limita a MAX_QUANTITY.
static func quantity_from(text: String) -> int:
	var norm := IntentClassifier.normalize(text).replace("?", " ")
	if norm.contains("media docena"):
		return 6
	if norm.contains("una docena") or norm.contains(" docena de"):
		return 12
	var words := norm.split(" ", false)
	for i in words.size() - 1:
		var nxt: String = words[i + 1]
		if not UNIT_WORDS.has(nxt):
			continue
		var w: String = words[i]
		var n := 0
		if w.is_valid_int():
			n = int(w)
		elif NUM_WORDS.has(w):
			n = int(NUM_WORDS[w])
		if n > 0:
			return clampi(n, 1, MAX_QUANTITY)
	return 0


const CURRENCY := ["peso", "pesos", "euro", "euros", "dolar", "dolares", "pavos", "monedas"]


## Precio que dice el vendedor: el número pegado a la moneda («18 pesos», «$20»).
## Si no nombra moneda, el primer número que NO sea una cantidad («dos piezas»).
## Devuelve 0 si no hay precio.
static func price_from(text: String) -> int:
	var t := text
	var re := RegEx.new()
	re.compile("\\$\\s*(\\d+)")
	t = re.sub(t, "$1 pesos", true)
	var words := IntentClassifier.normalize(t).replace("?", " ").strip_edges().split(" ", false)
	for k in words.size():
		if CURRENCY.has(words[k]):
			var window := " " + " ".join(words.slice(maxi(0, k - 4), k)) + " "
			var nums := IntentClassifier.extract_numbers(window)
			if not nums.is_empty():
				return int(nums[-1])
	# Sin moneda: se quitan las cantidades («2 cajas», «dos piezas») y se toma el primer número
	var kept := []
	var i := 0
	while i < words.size():
		var w: String = words[i]
		var is_num := w.is_valid_int() or NUM_WORDS.has(w)
		if is_num and i + 1 < words.size() and UNIT_WORDS.has(words[i + 1]):
			i += 2
			continue
		kept.append(w)
		i += 1
	var rest := IntentClassifier.extract_numbers(" " + " ".join(kept) + " ")
	return int(rest[0]) if not rest.is_empty() else 0


## Palabras que indican que la IA ha descrito una ACCIÓN y no el producto
## («Confirmar el pago»); en ese caso se conserva la propuesta anterior.
const ACTION_WORDS := ["confirmar", "pagar", "comprar", "aceptar", "recibir", "preparar", "enviar", "cerrar", "dar", "facilitar", "completar", "finalizar", "terminar",
	# descripciones de la conversación, no de un producto
	"informacion", "esperando", "esperar", "recordar", "recuerdo", "despedida", "despedirse", "colgar", "nada", "nadalgo", "ninguna", "ninguno", "nadie", "pregunta", "preguntar", "saber", "conocer", "duda", "llamada", "saludo", "saludar", "vendedor"]


## ¿La etiqueta comparte alguna palabra con lo que dijo el vendedor? (para que no se
## registre como «propuesta» algo que el jugador nunca ofreció)
static func overlaps_seller(label: String, seller_texts: Array) -> bool:
	var said := {}
	for t in seller_texts:
		for w in IntentClassifier.normalize(String(t)).replace("?", " ").split(" ", false):
			if w.length() >= 4:
				said[w.substr(0, 5)] = true
	for w in IntentClassifier.normalize(label).replace("?", " ").split(" ", false):
		if w.length() >= 4 and said.has(w.substr(0, 5)):
			return true
	return false


static func is_action_label(text: String) -> bool:
	var w := IntentClassifier.normalize(text).strip_edges().split(" ", false)
	return not w.is_empty() and ACTION_WORDS.has(w[0])


## Afinidad del cliente con las categorías de la propuesta (multiplicador de cierre).
static func affinity(client_id: String, tags: Array) -> float:
	var c := ClientDB.get_c(client_id)
	var aff := 1.0
	for tag in tags:
		if c["likes"].has(tag):
			aff += 0.15
		if c["dislikes"].has(tag):
			aff -= 0.2
	return clampf(aff, 0.55, 1.45)


## Cuánto le parece «caro» al cliente un precio, según su presupuesto.
## Devuelve un ajuste para la probabilidad de cierre (positivo = barato).
static func price_factor(price: int, quantity: int, budget: int) -> float:
	if price <= 0:
		return 0.0
	var total := price * maxi(1, quantity)
	var ratio := float(total) / float(maxi(1, budget))
	if ratio <= 0.35:
		return 0.12
	if ratio <= 0.7:
		return 0.05
	if ratio <= 1.0:
		return 0.0
	if ratio <= 1.5:
		return -0.22
	if ratio <= 2.5:
		return -0.45
	return -0.8


## Texto corto y seguro para mostrar la propuesta (viene de la IA o del jugador).
static func clean_label(text: String) -> String:
	var t := AIResponse.sanitize_text(text, 90).strip_edges()
	t = t.trim_suffix(".")
	if t.length() > 0:
		t = t.substr(0, 1).to_upper() + t.substr(1)
	return t
