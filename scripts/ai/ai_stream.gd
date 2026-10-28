class_name AIStream
extends RefCounted
## Lee la respuesta del modelo token a token con tres límites de tiempo reales:
##  - primer token: si el motor no empieza a contestar (p. ej. GPU bloqueada),
##  - atasco: si deja de producir tokens a mitad de respuesta,
##  - total: si la respuesta se eterniza.
## Al pasarse de cualquier límite se detiene la generación y se devuelve un error
## explícito (nunca se inventa una respuesta).

const FIRST_TOKEN_MS := 60000
const STALL_MS := 25000
const TOTAL_MS := 120000

const ERRORS := {
	"sin_primer_token": "La IA no empezó a responder a tiempo",
	"atasco": "La IA se quedó atascada a mitad de la respuesta",
	"demasiado_largo": "La IA tardó demasiado en terminar la respuesta",
	"sin_respuesta": "La IA no devolvió ninguna respuesta",
	"cancelado": "Cancelado",
}


## chat: el NobodyWhoChat (para poder detenerlo). stream: lo que devuelve ask()/complete().
## on_token(text_so_far) se llama con cada token. cancel: {"cancel": true} para cancelar.
static func read(chat: Object, stream: Object, on_token: Callable = Callable(), cancel: Dictionary = {}, limits: Dictionary = {}) -> Dictionary:
	var first_ms := int(limits.get("first", FIRST_TOKEN_MS))
	var stall_ms := int(limits.get("stall", STALL_MS))
	var total_ms := int(limits.get("total", TOTAL_MS))
	var res := {"ok": false, "text": "", "error": "", "first_ms": -1, "total_ms": 0, "tokens": 0}
	if stream == null:
		res["error"] = "sin_respuesta"
		return res
	var t0 := Time.get_ticks_msec()
	while true:
		var elapsed := Time.get_ticks_msec() - t0
		var budget := (first_ms if res["tokens"] == 0 else stall_ms)
		budget = mini(budget, total_ms - elapsed)
		if budget <= 0:
			_stop(chat)
			res["error"] = "demasiado_largo"
			break
		var r := await Timed.run(func(): return await stream.next_token(), budget, cancel)
		if r.get("cancelled", false):
			_stop(chat)
			res["error"] = "cancelado"
			break
		if r["timeout"]:
			_stop(chat)
			if res["tokens"] == 0:
				res["error"] = "sin_primer_token"
			elif Time.get_ticks_msec() - t0 >= total_ms:
				res["error"] = "demasiado_largo"
			else:
				res["error"] = "atasco"
			break
		var tok = r["value"]
		if tok == null:
			res["ok"] = res["tokens"] > 0
			if not res["ok"]:
				res["error"] = "sin_respuesta"
			break
		if res["tokens"] == 0:
			res["first_ms"] = Time.get_ticks_msec() - t0
		res["tokens"] += 1
		res["text"] += str(tok)
		if on_token.is_valid():
			on_token.call(res["text"])
	res["total_ms"] = Time.get_ticks_msec() - t0
	return res


static func _stop(chat: Object) -> void:
	if chat != null and is_instance_valid(chat) and chat.has_method("stop_generation"):
		chat.stop_generation()


static func error_text(code: String) -> String:
	return ERRORS.get(code, code)
