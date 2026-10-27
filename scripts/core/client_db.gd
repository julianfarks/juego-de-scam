class_name ClientDB
extends RefCounted
## Personajes adultos ficticios. Cada uno combina una personalidad, un aspecto 3D
## propio (silueta, pelo, ropa, accesorios), su casa, su voz y datos que puede
## mencionar en la conversación. Las ciudades y empresas son inventadas.

const CLIENTS := {
	"remedios": {"name": "Doña Remedios Pocafé", "personality": "desconfiado", "day": 1, "difficulty": 2, "gender": "f",
		"look": {"skin": "e8b894", "body": "short", "hair": "bun", "hair_color": "d9d9d9", "shirt": "7a4a8c", "pants": "3b3b4f", "acc": ["glasses", "cardigan"]},
		"home": {"wall": "c9b28f", "prop": "bookshelf"}, "likes": ["seguro", "hogar"], "dislikes": ["inversion", "tecnologia"],
		"facts": {"job": "costurera jubilada", "pet": "un loro llamado Comandante", "city": "Villa Mantequilla", "hobby": "ver telenovelas de detectives", "family": "tres nietos que nunca llaman"}},
	"brayan": {"name": "Brayan Turbo", "personality": "impaciente", "day": 1, "difficulty": 1, "gender": "m",
		"look": {"skin": "c68e63", "body": "thin", "hair": "mohawk", "hair_color": "1a1a1a", "shirt": "e0482b", "pants": "1f2a44", "acc": ["headphones", "watch"]},
		"home": {"wall": "8fb8c9", "prop": "tv"}, "likes": ["tecnologia", "suerte"], "dislikes": ["hogar"],
		"facts": {"job": "repartidor en patinete", "pet": "ninguna, no tiene tiempo", "city": "Puerto Prisa", "hobby": "batir récords de velocidad comiendo", "family": "un hermano gemelo más lento"}},
	"chucho": {"name": "Chucho Carcajada", "personality": "bromista", "day": 1, "difficulty": 1, "gender": "m",
		"look": {"skin": "f1c7a3", "body": "wide", "hair": "curly", "hair_color": "8a4b1f", "shirt": "f2c12e", "pants": "4b6b3a", "acc": ["bowtie", "mustache"]},
		"home": {"wall": "f0d3a8", "prop": "guitar"}, "likes": ["rareza", "suerte"], "dislikes": ["inversion"],
		"facts": {"job": "payaso de fiestas infantiles retirado", "pet": "un pez llamado Ronaldiño", "city": "Risalandia", "hobby": "coleccionar narices de goma", "family": "una esposa que no se ríe de sus chistes"}},
	"maruja": {"name": "Maruja Parlanchina", "personality": "hablador", "day": 1, "difficulty": 1, "gender": "f",
		"look": {"skin": "f4cfae", "body": "wide", "hair": "curly", "hair_color": "b5532a", "shirt": "e86aa6", "pants": "5a3a6b", "acc": ["earrings", "apron"]},
		"home": {"wall": "f2c9c9", "prop": "plant"}, "likes": ["hogar", "mascotas", "lujo"], "dislikes": ["tecnologia"],
		"facts": {"job": "peluquera del barrio", "pet": "siete gatos con nombres de cantantes", "city": "Villa Mantequilla", "hobby": "enterarse de todo", "family": "una sobrina que se casa en abril"}},
	"tomasito": {"name": "Tomasito Despiste", "personality": "distraido", "day": 1, "difficulty": 1, "gender": "m",
		"look": {"skin": "e0a882", "body": "tall", "hair": "messy", "hair_color": "c9a14a", "shirt": "6aa3e8", "pants": "6b5a3a", "acc": ["glasses"]},
		"home": {"wall": "b8d9b0", "prop": "aquarium"}, "likes": ["mascotas", "rareza"], "dislikes": ["inversion"],
		"facts": {"job": "probador de colchones", "pet": "un perro que se llama Perro", "city": "Valle Siesta", "hobby": "mirar las nubes", "family": "no recuerda cuántos primos tiene"}},
	"ingeniera": {"name": "Ing. Rigoberta Exacta", "personality": "literal", "day": 2, "difficulty": 2, "gender": "f",
		"look": {"skin": "d9a37e", "body": "avg", "hair": "ponytail", "hair_color": "2b1d14", "shirt": "e8e8e8", "pants": "2f3e57", "acc": ["glasses", "watch"]},
		"home": {"wall": "d0d6dc", "prop": "bookshelf"}, "likes": ["tecnologia", "seguro"], "dislikes": ["rareza", "suerte"],
		"facts": {"job": "ingeniera de semáforos", "pet": "un cactus llamado Cactus", "city": "Ciudad Cuadrícula", "hobby": "medir cosas con regla", "family": "un marido que dice 'más o menos'"}},
	"profesor": {"name": "Prof. Evaristo Sabelotodo", "personality": "experto", "day": 3, "difficulty": 3, "gender": "m",
		"look": {"skin": "efc19b", "body": "avg", "hair": "bald", "hair_color": "9a9a9a", "shirt": "8c6a3f", "pants": "3a3a3a", "acc": ["glasses", "beard", "bowtie"]},
		"home": {"wall": "a89a84", "prop": "bookshelf"}, "likes": ["inversion", "tecnologia"], "dislikes": ["suerte", "rareza"],
		"facts": {"job": "catedrático de Economía Imaginaria", "pet": "una tortuga llamada Keynes", "city": "Universidad de Villa Pedante", "hobby": "corregir a la gente", "family": "seis libros publicados y cero amigos"}},
	"pilar": {"name": "Pilar Quizás", "personality": "indeciso", "day": 1, "difficulty": 1, "gender": "f",
		"look": {"skin": "f3d2b5", "body": "thin", "hair": "long", "hair_color": "e0c070", "shirt": "9ad1c0", "pants": "c08a9a", "acc": ["scarf"]},
		"home": {"wall": "e6dcf2", "prop": "plant"}, "likes": ["hogar", "viajes"], "dislikes": [],
		"facts": {"job": "catadora de helados", "pet": "quizá un hámster, o quizá no", "city": "Pueblo Tal Vez", "hobby": "empezar puzzles", "family": "una madre que decide por ella"}},
	"oscar": {"name": "Óscar Conspiranoia", "personality": "sospechoso", "day": 2, "difficulty": 3, "gender": "m",
		"look": {"skin": "c99572", "body": "thin", "hair": "long", "hair_color": "4a3b2a", "shirt": "556b2f", "pants": "3d3d2f", "acc": ["foil_hat", "beard"]},
		"home": {"wall": "6f7a5c", "prop": "tv"}, "likes": ["rareza", "seguro"], "dislikes": ["tecnologia", "inversion"],
		"facts": {"job": "vigilante nocturno de palomas", "pet": "una paloma infiltrada llamada Agente Cero", "city": "un búnker en Villa Secreta", "hobby": "forrar muebles con papel de aluminio", "family": "no se fía ni de su madre"}},
	"conde": {"name": "Don Fernando de la Cortesía", "personality": "educado_firme", "day": 2, "difficulty": 2, "gender": "m",
		"look": {"skin": "f0cfb0", "body": "tall", "hair": "slick", "hair_color": "3a2a1a", "shirt": "2a2a3a", "pants": "1a1a2a", "acc": ["tie", "mustache"]},
		"home": {"wall": "8c2f39", "prop": "lamp"}, "likes": ["lujo", "herencia"], "dislikes": ["rareza"],
		"facts": {"job": "mayordomo de un castillo de cartón", "pet": "un galgo llamado Sir Patas", "city": "Villa Etiqueta", "hobby": "doblar servilletas en forma de cisne", "family": "una tía duquesa (eso dice)"}},
	"lucia": {"name": "Lucía Saltamontes", "personality": "cambia_tema", "day": 1, "difficulty": 1, "gender": "f",
		"look": {"skin": "b9825c", "body": "short", "hair": "afro", "hair_color": "1a1410", "shirt": "f28c28", "pants": "2c5f8a", "acc": ["earrings", "flower"]},
		"home": {"wall": "fae3b0", "prop": "plant"}, "likes": ["viajes", "mascotas", "suerte"], "dislikes": ["inversion"],
		"facts": {"job": "cocinera de sopas experimentales", "pet": "un gato que juega al fútbol", "city": "Cerro Bullicio", "hobby": "aprender idiomas de pájaros", "family": "cinco hermanos futboleros"}},
	"gregorio": {"name": "Gregorio Patinazo", "personality": "malinterpreta", "day": 2, "difficulty": 2, "gender": "m",
		"look": {"skin": "e5b48c", "body": "wide", "hair": "short", "hair_color": "7a7a7a", "shirt": "4f9a6a", "pants": "6b4a2a", "acc": ["cap", "mustache"]},
		"home": {"wall": "c6dbe8", "prop": "tv"}, "likes": ["viajes", "suerte"], "dislikes": ["tecnologia"],
		"facts": {"job": "conductor de autobús de juguete", "pet": "un canario sordo", "city": "Villa Confusión", "hobby": "el karaoke con letras inventadas", "family": "una suegra que habla bajito"}},
	"nina": {"name": "Nina Porqué", "personality": "pregunton", "day": 2, "difficulty": 2, "gender": "f",
		"look": {"skin": "f7d6bd", "body": "thin", "hair": "pigtails", "hair_color": "c23b22", "shirt": "6b4fd1", "pants": "2b2b44", "acc": ["glasses"]},
		"home": {"wall": "d7f0f5", "prop": "bookshelf"}, "likes": ["tecnologia", "rareza", "mascotas"], "dislikes": [],
		"facts": {"job": "bibliotecaria de libros de preguntas", "pet": "un gato llamado Por Qué", "city": "Villa Duda", "hobby": "concursos de televisión", "family": "un novio que solo responde 'porque sí'"}},
	"ejecutivo": {"name": "Ejecutivo Julián Reloj", "personality": "rapido", "day": 1, "difficulty": 2, "gender": "m",
		"look": {"skin": "d4a07a", "body": "avg", "hair": "slick", "hair_color": "1a1a1a", "shirt": "dfe6ee", "pants": "2a2f3a", "acc": ["tie", "watch"]},
		"home": {"wall": "e9ecef", "prop": "lamp"}, "likes": ["inversion", "lujo"], "dislikes": ["mascotas", "rareza"],
		"facts": {"job": "director de reuniones sobre reuniones", "pet": "un pez de bajo mantenimiento", "city": "Torre Prisa", "hobby": "contestar correos en el baño", "family": "ve a sus hijos por videollamada"}},
	"abuelo": {"name": "Abuelo Cleto Tranquilo", "personality": "sencillo", "day": 1, "difficulty": 1, "gender": "m",
		"look": {"skin": "ecc5a5", "body": "short", "hair": "bald", "hair_color": "eeeeee", "shirt": "8a9a5b", "pants": "5a4a3a", "acc": ["glasses", "cardigan", "cane"]},
		"home": {"wall": "e3d5b8", "prop": "lamp"}, "likes": ["hogar", "salud", "mascotas"], "dislikes": ["tecnologia", "inversion"],
		"facts": {"job": "agricultor de tomates gigantes jubilado", "pet": "una gallina llamada Josefina", "city": "Aldea Calma", "hobby": "dar de comer a las palomas", "family": "veinte nietos y un bisnieto"}},
	"ramona": {"name": "Ramona Ganadora", "personality": "competitivo", "day": 3, "difficulty": 2, "gender": "f",
		"look": {"skin": "c48a64", "body": "avg", "hair": "ponytail", "hair_color": "2a1a10", "shirt": "d62839", "pants": "1d3557", "acc": ["cap", "medal"]},
		"home": {"wall": "f1faee", "prop": "trophies"}, "likes": ["lujo", "inversion", "suerte"], "dislikes": ["salud"],
		"facts": {"job": "campeona regional de petanca", "pet": "un perro más rápido que el del vecino", "city": "Villa Podio", "hobby": "ganarle a su vecino Ramón en todo", "family": "un marido que siempre queda segundo"}},
	"estrella": {"name": "Estrella del Drama", "personality": "dramatico", "day": 2, "difficulty": 2, "gender": "f",
		"look": {"skin": "f2c7a5", "body": "tall", "hair": "long", "hair_color": "6a1a3a", "shirt": "9b1d64", "pants": "2a0a1a", "acc": ["sunglasses", "scarf", "earrings"]},
		"home": {"wall": "5a1a3a", "prop": "lamp"}, "likes": ["herencia", "lujo", "viajes"], "dislikes": ["salud", "tecnologia"],
		"facts": {"job": "actriz de anuncios de yogur", "pet": "un caniche llamado Telenovela", "city": "Villa Escenario", "hobby": "llorar en los atardeceres", "family": "un gemelo malvado (dice ella)"}},
	"sergio": {"name": "Sergio Ironías", "personality": "sarcastico", "day": 3, "difficulty": 3, "gender": "m",
		"look": {"skin": "e2b08a", "body": "thin", "hair": "messy", "hair_color": "3a2a2a", "shirt": "2f2f2f", "pants": "4a4a4a", "acc": ["beanie", "beard"]},
		"home": {"wall": "5c6670", "prop": "guitar"}, "likes": ["rareza"], "dislikes": ["lujo", "herencia"],
		"facts": {"job": "crítico de restaurantes que no existen", "pet": "un gato que lo desprecia", "city": "Villa Desgana", "hobby": "suspirar", "family": "una familia que no entiende su humor"}},
	"agata": {"name": "Ágata Libreta", "personality": "detector", "day": 3, "difficulty": 3, "gender": "f",
		"look": {"skin": "d8a585", "body": "avg", "hair": "bob", "hair_color": "141414", "shirt": "3e6a8a", "pants": "2a2a2a", "acc": ["glasses", "pencil"]},
		"home": {"wall": "dfe7ec", "prop": "bookshelf"}, "likes": ["seguro", "hogar"], "dislikes": ["herencia", "inversion"],
		"facts": {"job": "taquígrafa del juzgado de Villa Norma", "pet": "un búho llamado Acta", "city": "Villa Norma", "hobby": "apuntar matrículas de coches", "family": "un hermano que miente fatal"}},
	"zoe": {"name": "Zoe Pregunta Rara", "personality": "sorpresa", "day": 2, "difficulty": 2, "gender": "f",
		"look": {"skin": "f0c2a0", "body": "short", "hair": "space_buns", "hair_color": "4ac0c0", "shirt": "ffd23f", "pants": "8a4fd1", "acc": ["sunglasses"]},
		"home": {"wall": "fbe2f4", "prop": "aquarium"}, "likes": ["rareza", "viajes", "mascotas"], "dislikes": ["seguro"],
		"facts": {"job": "diseñadora de nubes para dibujos animados", "pet": "un axolote llamado Galaxia", "city": "Villa Rareza", "hobby": "preguntar cosas raras", "family": "una abuela astronauta (de cartón)"}},
	"paco": {"name": "Paco Desconfío", "personality": "desconfiado", "day": 4, "difficulty": 3, "gender": "m",
		"look": {"skin": "b07a55", "body": "wide", "hair": "short", "hair_color": "2a2a2a", "shirt": "6b6b6b", "pants": "2a2a3a", "acc": ["sunglasses", "beard"]},
		"home": {"wall": "8a8070", "prop": "tv"}, "likes": ["seguro"], "dislikes": ["herencia", "suerte", "inversion"],
		"facts": {"job": "cerrajero de cajas fuertes de juguete", "pet": "un pitbull llamado Algodón", "city": "Villa Candado", "hobby": "cambiar las cerraduras cada semana", "family": "un primo que le vendió un coche sin ruedas"}},
	"luz": {"name": "Luz Prisas", "personality": "impaciente", "day": 4, "difficulty": 2, "gender": "f",
		"look": {"skin": "e9b996", "body": "tall", "hair": "bob", "hair_color": "e05a2a", "shirt": "2a9d8f", "pants": "264653", "acc": ["watch", "earrings"]},
		"home": {"wall": "e9f5f2", "prop": "plant"}, "likes": ["viajes", "salud"], "dislikes": ["hogar"],
		"facts": {"job": "cronometradora de huevos pasados por agua", "pet": "un galgo jubilado", "city": "Puerto Prisa", "hobby": "el maratón", "family": "dos hijos que van al ralentí"}},
	"bartolo": {"name": "Bartolo Chistera", "personality": "bromista", "day": 5, "difficulty": 2, "gender": "m",
		"look": {"skin": "d39b74", "body": "tall", "hair": "curly", "hair_color": "1a1a1a", "shirt": "3fa34d", "pants": "f2c12e", "acc": ["top_hat", "bowtie"]},
		"home": {"wall": "c7e8c0", "prop": "guitar"}, "likes": ["rareza", "lujo"], "dislikes": [],
		"facts": {"job": "mago de cumpleaños especializado en desaparecer pagos", "pet": "un conejo que no sale de la chistera", "city": "Villa Truco", "hobby": "trucos de cartas que fallan", "family": "una asistente que desapareció de verdad"}},
	"margarita": {"name": "Margarita Telenovela", "personality": "dramatico", "day": 6, "difficulty": 3, "gender": "f",
		"look": {"skin": "c2895f", "body": "wide", "hair": "long", "hair_color": "1a0a0a", "shirt": "c1121f", "pants": "3a0a1a", "acc": ["earrings", "flower", "scarf"]},
		"home": {"wall": "7a1a2a", "prop": "lamp"}, "likes": ["herencia", "lujo"], "dislikes": ["tecnologia"],
		"facts": {"job": "guionista de telenovelas que nadie emite", "pet": "un loro que dice '¡traición!'", "city": "Villa Lágrima", "hobby": "abofetear el aire", "family": "una hermana perdida en un crucero"}},
}


static func get_c(id: String) -> Dictionary:
	return CLIENTS.get(id, CLIENTS["pilar"])


static func available_for_day(day: int) -> Array:
	var out := []
	for id in CLIENTS.keys():
		if int(CLIENTS[id]["day"]) <= day:
			out.append(id)
	return out


## Afinidad de un cliente con una oferta (multiplicador para la probabilidad de cierre).
static func offer_affinity(client_id: String, offer_id: String) -> float:
	var c := get_c(client_id)
	var o := OfferDB.get_o(offer_id)
	var aff := 1.0
	for tag in o["tags"]:
		if c["likes"].has(tag):
			aff += 0.18
		if c["dislikes"].has(tag):
			aff -= 0.22
	return clampf(aff, 0.5, 1.5)
