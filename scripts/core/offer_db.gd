class_name OfferDB
extends RefCounted
## Ofertas 100 % ficticias y absurdas. El precio lo decide SIEMPRE el juego (base y
## máximo), nunca la IA ni lo que el jugador diga por el micrófono.

const OFFERS := {
	"seguro_abduccion": {"name": "Seguro contra abducciones alienígenas", "price": 49, "max": 130, "day": 1, "tags": ["seguro", "rareza"], "plaus": 0.9,
		"pitch": "Cubre traslados en platillo volante, sondas y devoluciones a la Tierra.", "keywords": ["alien", "extraterrest", "abduc", "ovni", "platillo", "marciano"]},
	"garantia_tostadora": {"name": "Garantía extendida para tostadoras emocionales", "price": 29, "max": 80, "day": 1, "tags": ["hogar"], "plaus": 1.1,
		"pitch": "Terapia para tostadoras deprimidas y cambio gratis si quema el pan con rencor.", "keywords": ["tostador", "garantia", "pan", "electrodomest"]},
	"club_calcetines": {"name": "Club VIP del Calcetín Desparejado", "price": 39, "max": 100, "day": 1, "tags": ["hogar", "lujo"], "plaus": 1.0,
		"pitch": "Cada mes recibe un calcetín sin pareja de un famoso desconocido.", "keywords": ["calcetin", "club", "vip", "media"]},
	"loteria_inversa": {"name": "Lotería inversa: gana si NO le toca", "price": 25, "max": 70, "day": 2, "tags": ["suerte"], "plaus": 1.0,
		"pitch": "Si su número no sale, ¡enhorabuena! Recibe un diploma de no-ganador.", "keywords": ["loteria", "sorteo", "suerte", "premio", "numero"]},
	"seguro_mascota": {"name": "Seguro dental para mascotas imaginarias", "price": 35, "max": 90, "day": 2, "tags": ["mascotas", "seguro"], "plaus": 0.9,
		"pitch": "Limpiezas, empastes y ortodoncia para el dragón invisible de su infancia.", "keywords": ["mascota", "perro", "gato", "dental", "dragon", "imaginari"]},
	"herencia_patatonia": {"name": "Herencia del Príncipe de Patatonia", "price": 89, "max": 260, "day": 2, "tags": ["herencia", "suerte"], "plaus": 0.7,
		"pitch": "Un príncipe le deja su fortuna en patatas; solo hay que pagar el 'envío real'.", "keywords": ["herencia", "principe", "patatonia", "fortuna", "millon"]},
	"crucero_charco": {"name": "Crucero de lujo por el charco municipal", "price": 120, "max": 300, "day": 3, "tags": ["viajes", "lujo"], "plaus": 0.85,
		"pitch": "Tres días navegando un charco de 4 metros con bufé de galletas.", "keywords": ["crucero", "barco", "viaje", "vacacion", "charco", "mar"]},
	"curso_aire": {"name": "Curso: vivir del aire acondicionado", "price": 59, "max": 150, "day": 3, "tags": ["salud"], "plaus": 0.85,
		"pitch": "Nutricionistas de mentira enseñan a alimentarse de brisa fresca.", "keywords": ["curso", "aire", "dieta", "salud", "adelgaz"]},
	"patatacoin": {"name": "PatataCoin, la criptomoneda tubérculo", "price": 150, "max": 420, "day": 4, "tags": ["tecnologia", "inversion"], "plaus": 0.75,
		"pitch": "Minada a mano en huertos digitales. Sube cuando llueve.", "keywords": ["cripto", "moneda", "bitcoin", "patatacoin", "inversion", "blockchain"]},
	"wifi_plantas": {"name": "Wifi cuántico para plantas", "price": 69, "max": 180, "day": 4, "tags": ["tecnologia", "hogar"], "plaus": 0.9,
		"pitch": "Sus potos por fin podrán ver vídeos de fotosíntesis en 4K.", "keywords": ["wifi", "internet", "planta", "cuantic", "router"]},
	"pulsera_antilunes": {"name": "Pulsera antilunes con imanes de nevera", "price": 45, "max": 120, "day": 5, "tags": ["salud", "suerte"], "plaus": 1.0,
		"pitch": "Convierte los lunes en martes gracias a la magnetoterapia de souvenir.", "keywords": ["pulsera", "lunes", "iman", "energia"]},
	"parcela_luna": {"name": "Parcela en la cara oculta de la Luna", "price": 199, "max": 520, "day": 5, "tags": ["lujo", "viajes", "inversion"], "plaus": 0.75,
		"pitch": "Vistas privilegiadas a la nada. Incluye bandera para clavar.", "keywords": ["luna", "parcela", "terreno", "espacio", "lunar"]},
	"colchon_nube": {"name": "Colchón de nube certificada", "price": 249, "max": 620, "day": 6, "tags": ["hogar", "lujo"], "plaus": 0.85,
		"pitch": "Nube auténtica atrapada en Galicia. Puede llover ligeramente.", "keywords": ["colchon", "nube", "dormir", "cama", "sueño"]},
	"titulo_duque": {"name": "Título de Duque de su propio salón", "price": 179, "max": 480, "day": 7, "tags": ["lujo", "herencia"], "plaus": 0.9,
		"pitch": "Pergamino oficial-ish y derecho a exigir reverencias en el sofá.", "keywords": ["titulo", "duque", "noble", "conde", "salon", "pergamino"]},
}


static func get_o(id: String) -> Dictionary:
	return OFFERS.get(id, OFFERS["seguro_abduccion"])


static func unlocked_for_day(day: int) -> Array:
	var out := []
	for id in OFFERS.keys():
		if int(OFFERS[id]["day"]) <= day:
			out.append(id)
	return out
