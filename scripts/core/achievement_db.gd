class_name AchievementDB
extends RefCounted
## Logros locales y objetivos secundarios diarios.

const ACHIEVEMENTS := {
	"first_sale": {"name": "Primer timo (de mentira)", "desc": "Completa tu primera transacción ficticia."},
	"ten_sales": {"name": "Vendedor de humo", "desc": "10 transacciones ficticias."},
	"fifty_sales": {"name": "Fábrica de nubes", "desc": "50 transacciones ficticias."},
	"first_day": {"name": "Sobreviviste al lunes", "desc": "Completa una jornada."},
	"double_quota": {"name": "Empleado sobrado", "desc": "Consigue el doble de la cuota en una jornada."},
	"voice_seller": {"name": "Pico de oro", "desc": "Habla 20 veces por micrófono."},
	"detector_sale": {"name": "Coherencia absoluta", "desc": "Vende a un detector de contradicciones."},
	"paranoid_sale": {"name": "Agente de confianza", "desc": "Vende a un cliente paranoico."},
	"meet_all": {"name": "Conozco a todo el mundo", "desc": "Habla con 15 clientes distintos."},
	"perfect_day": {"name": "Nadie me cuelga", "desc": "Termina una jornada sin que nadie te cuelgue (mín. 3 llamadas)."},
	"big_fish": {"name": "Pez gordo", "desc": "Una sola venta de 400 o más."},
	"campaign_done": {"name": "Empleado del Mes Eterno", "desc": "Completa la campaña de 12 días."},
	"comedian": {"name": "Risas enlatadas", "desc": "Usa la botonera de risas 5 veces."},
	"long_talk": {"name": "Charla eterna", "desc": "Mantén una llamada más de 2 minutos."},
	"rich": {"name": "Millonario imaginario", "desc": "Gana 5.000 en total."},
	"streak": {"name": "En racha", "desc": "3 ventas seguidas en una jornada."},
	"grade_s": {"name": "Matrícula de honor", "desc": "Saca una S en la evaluación del jefe."},
}

const OBJECTIVE_TEMPLATES := [
	{"type": "sales", "min": 2, "max": 4, "text": "Consigue %d transacciones", "reward": 40},
	{"type": "voice_turns", "min": 4, "max": 8, "text": "Habla %d veces por micrófono", "reward": 30},
	{"type": "resolve_objections", "min": 2, "max": 5, "text": "Resuelve %d objeciones", "reward": 35},
	{"type": "no_hangups", "min": 0, "max": 0, "text": "Que ningún cliente te cuelgue", "reward": 50},
	{"type": "big_sale", "min": 120, "max": 260, "text": "Una venta de al menos %d", "reward": 45},
	{"type": "calls", "min": 4, "max": 7, "text": "Atiende %d llamadas", "reward": 25},
]


static func make_objectives(day: int, rng: RandomNumberGenerator) -> Array:
	var pool := OBJECTIVE_TEMPLATES.duplicate()
	var out := []
	for i in 2:
		var t: Dictionary = pool.pop_at(rng.randi() % pool.size())
		var target := rng.randi_range(int(t["min"]), int(t["max"]))
		if t["type"] == "big_sale":
			target = int(target * (1.0 + 0.1 * day))
		var txt: String = t["text"] % target if "%d" in String(t["text"]) else String(t["text"])
		out.append({"type": t["type"], "target": target, "text": txt, "reward": int(t["reward"]) + day * 5, "progress": 0, "done": false})
	return out
