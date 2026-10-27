class_name CampaignDB
extends RefCounted
## Campaña de 12 jornadas con dificultad creciente y modo infinito después.

const DAYS := [
	{"quota": 110, "title": "Primer día en TeleTimo", "boss": "Bienvenido, novato. Aquí vendemos humo de primera calidad. Cuota pequeñita para que no llores.", "events": 1, "lead_bonus": 0},
	{"quota": 170, "title": "Herencias reales (de mentira)", "boss": "Hoy estrenamos la herencia del Príncipe de Patatonia. Si alguien se la cree, invito yo al café… de máquina.", "events": 2, "lead_bonus": 0},
	{"quota": 240, "title": "Cruceros y cursos", "boss": "Nuevos productos: cruceros por el charco y cursos de vivir del aire. El cliente siempre tiene razón, salvo cuando no paga.", "events": 2, "lead_bonus": 1},
	{"quota": 320, "title": "La fiebre de la PatataCoin", "boss": "Criptomonedas tubérculo. No sé qué son, pero suben cuando llueve. ¡A vender!", "events": 3, "lead_bonus": 1},
	{"quota": 410, "title": "Bienes raíces lunares", "boss": "Parcelas en la cara oculta de la Luna. Nadie ha ido a comprobarlo. Perfecto.", "events": 3, "lead_bonus": 1},
	{"quota": 500, "title": "Colchones de nube", "boss": "Colchones de nube certificada. Si llueve en la cama, es una característica, no un defecto.", "events": 3, "lead_bonus": 2},
	{"quota": 600, "title": "Nobleza para todos", "boss": "Títulos de duque. Cualquiera puede ser noble por un módico precio de mentira.", "events": 4, "lead_bonus": 2},
	{"quota": 710, "title": "Inspección de la central", "boss": "Viene la central a vigilarnos. Sonríe, vende y no mires a la planta de plástico, que es una cámara.", "events": 4, "lead_bonus": 2},
	{"quota": 830, "title": "Clientes de élite", "boss": "Hoy solo llaman los más duros. Si sobrevives, te subo el sueldo imaginario.", "events": 4, "lead_bonus": 3},
	{"quota": 960, "title": "La semana del caos", "boss": "Se ha roto media oficina. Teléfonos, ordenadores, la cafetera… ¡pero la cuota sigue intacta!", "events": 5, "lead_bonus": 3},
	{"quota": 1100, "title": "Récord histórico", "boss": "Quiero el récord histórico de TeleTimo. El anterior lo tiene mi sobrino, y lo odio.", "events": 5, "lead_bonus": 3},
	{"quota": 1260, "title": "El gran final", "boss": "Último día de la campaña. Si llegas a la cuota, te nombro Empleado del Mes Eterno.", "events": 5, "lead_bonus": 4},
]

const SHIFT_START_HOUR := 9
const SHIFT_END_HOUR := 17


static func day_info(day: int) -> Dictionary:
	if day <= DAYS.size():
		return DAYS[day - 1]
	var extra := day - DAYS.size()
	return {"quota": quota(day), "title": "Jornada infinita %d" % extra, "boss": "Modo infinito. La cuota sube cada día. Como la deuda del país, pero de mentira.", "events": 5, "lead_bonus": 4}


static func quota(day: int) -> int:
	if day <= DAYS.size():
		return int(DAYS[day - 1]["quota"])
	return 1260 + (day - DAYS.size()) * 170


static func is_campaign_end(day: int) -> bool:
	return day == DAYS.size()


## Gastos ficticios de la jornada (se descuentan del sueldo de mentira).
static func expenses(day: int, owned: Array) -> Array:
	var out := []
	out.append({"label": "Línea telefónica", "amount": 6 + day * 2})
	if not owned.has("cafetera"):
		out.append({"label": "Cafés de máquina", "amount": 8})
	if day >= 4:
		out.append({"label": "Alquiler de la silla", "amount": 5 if owned.has("silla_gamer") else 10})
	return out
