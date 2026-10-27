class_name EventDB
extends RefCounted
## Eventos de jornada. Aportan variedad pero no bloquean el progreso (duración corta
## y nunca más de uno activo a la vez).

const EVENTS := {
	"urgent_call": {"name": "¡Llamada urgente!", "desc": "Un cliente VIP llama ahora. Contesta en 20 s: importe ×1,5.", "weight": 3, "day": 1, "duration": 20.0},
	"special_opportunity": {"name": "Oportunidad especial", "desc": "La próxima venta vale el DOBLE.", "weight": 2, "day": 2, "duration": 0.0},
	"boss_inspection": {"name": "Inspección del jefe", "desc": "El jefe viene a tu mesa. Que te vea trabajando…", "weight": 3, "day": 1, "duration": 25.0},
	"pc_crash": {"name": "Fallo informático", "desc": "El ordenador se ha colgado. Toca la pantalla para reiniciarlo antes.", "weight": 2, "day": 2, "duration": 30.0},
	"phone_outage": {"name": "Avería telefónica", "desc": "La centralita se ha caído: no entran llamadas durante un rato.", "weight": 2, "day": 3, "duration": 35.0},
	"interruption": {"name": "Compañero pesado", "desc": "Rigo, el de contabilidad, viene a contarte su fin de semana.", "weight": 3, "day": 1, "duration": 18.0},
	"hard_client": {"name": "Cliente extremadamente complicado", "desc": "El próximo cliente es de los duros, pero paga un 40 % más.", "weight": 2, "day": 3, "duration": 0.0},
	"weird_clarification": {"name": "Aclaración inesperada", "desc": "El próximo cliente empezará con una pregunta rarísima.", "weight": 2, "day": 2, "duration": 0.0},
	"pizza": {"name": "¡Pizza en la sala de descanso!", "desc": "Coge una porción: +15 de paciencia inicial en la próxima llamada.", "weight": 2, "day": 2, "duration": 45.0},
}


static func pick(day: int, rng: RandomNumberGenerator, exclude: Array = []) -> String:
	var pool := []
	var total := 0
	for id in EVENTS.keys():
		var e: Dictionary = EVENTS[id]
		if int(e["day"]) > day or exclude.has(id):
			continue
		pool.append(id)
		total += int(e["weight"])
	if pool.is_empty():
		return ""
	var r := rng.randi_range(1, total)
	for id in pool:
		r -= int(EVENTS[id]["weight"])
		if r <= 0:
			return id
	return pool[0]
