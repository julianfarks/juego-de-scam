class_name GemmaBench
extends RefCounted
## Prueba INDEPENDIENTE del modelo de lenguaje: sin personajes, voz ni interfaz de
## llamada. Mide con el modelo YA cargado, para cada número de hilos:
##   - tokens de entrada (exactos, con el tokenizador del modelo),
##   - tiempo hasta el primer token (= lectura del texto de entrada),
##   - tokens generados y velocidad de generación,
##   - memoria del proceso (VmRSS) cuando el sistema la expone.
## La usan Ajustes → IA y voz → Diagnóstico (en el móvil) y la prueba de CI en ARM.

const PROMPT_SHORT := "Eres un cliente que contesta al teléfono. Responde en español, muy breve."
const QUESTION := "Saluda en una frase corta."


## Memoria residente del proceso en MB (Linux/Android), o -1.
static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return -1.0


## Memoria disponible del sistema en MB (MemAvailable), o -1.
static func mem_available_mb() -> float:
	var f := FileAccess.open("/proc/meminfo", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("MemAvailable:"):
			return float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return -1.0


## Núcleos «grandes» según la frecuencia máxima de cada núcleo (los pequeños de
## eficiencia ralentizan a llama.cpp porque reparte el trabajo a partes iguales).
## Devuelve {total, big, freqs_mhz}.
static func cpu_topology() -> Dictionary:
	var freqs := []
	for i in 64:
		var p := "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq" % i
		if not FileAccess.file_exists(p):
			if not DirAccess.dir_exists_absolute("/sys/devices/system/cpu/cpu%d" % i):
				break
			continue
		freqs.append(int(FileAccess.get_file_as_string(p).strip_edges()) / 1000)
	var total := OS.get_processor_count()
	if freqs.is_empty():
		return {"total": total, "big": total, "freqs_mhz": []}
	var top := 0
	for f in freqs:
		top = maxi(top, int(f))
	var big := 0
	for f in freqs:
		if float(f) >= 0.75 * top:
			big += 1
	return {"total": total, "big": maxi(1, big), "freqs_mhz": freqs}


## Hilos recomendados: los núcleos grandes, entre 2 y 6.
static func recommended_threads() -> int:
	var t := cpu_topology()
	return clampi(int(t["big"]), 2, 6) if int(t["total"]) > 2 else maxi(1, int(t["total"]))


## Una medición: crea una conversación con n hilos y genera una respuesta.
## prompt: instrucciones de sistema (corta o la real de un cliente).
static func measure(model: Object, n_threads: int, prompt: String, question: String = QUESTION, limits: Dictionary = {}, game_sampler := false) -> Dictionary:
	var out := {"sampler": "juego (JSON)" if game_sampler else "texto libre", "threads": n_threads, "ok": false, "error": "", "prompt_tokens": -1, "first_ms": -1, "tokens": 0, "total_ms": 0, "gen_tps": 0.0, "prompt_tps": 0.0, "rss_mb": -1.0, "text": "", "sentence_ms": -1}
	var cfg := {"system_prompt": prompt, "n_ctx": 4096, "template_variables": {"enable_thinking": false}}
	if n_threads > 0:
		cfg["n_threads"] = n_threads
	if game_sampler:
		cfg["sampler"] = Brain.make_sampler(Persona.schema())
	var c := await Timed.run(func(): return await ClassDB.class_call_static("NobodyWhoChat", "create", model, cfg), 60000)
	if not c["ok"] or c["value"] == null:
		out["error"] = "no se pudo crear la conversación"
		return out
	var chat: Object = c["value"]
	var tk := await Timed.run(func(): return await chat.tokenize(prompt + "\n" + question), 30000)
	if tk["ok"] and tk["value"] != null:
		out["prompt_tokens"] = (tk["value"] as Array).size() if tk["value"] is Array else int(tk["value"].size())
	var lim := {"first": 600000, "stall": 60000, "total": 900000}
	lim.merge(limits, true)
	var t_start := Time.get_ticks_msec()
	var on_tok := func(txt: String) -> void:
		if out["sentence_ms"] < 0 and JsonPeek.string_field_closed(txt, "respuesta"):
			out["sentence_ms"] = Time.get_ticks_msec() - t_start
	var r := await AIStream.read(chat, chat.ask(question), on_tok, {}, lim)
	out["first_ms"] = r["first_ms"]
	out["tokens"] = r["tokens"]
	out["total_ms"] = r["total_ms"]
	out["text"] = r["text"].substr(0, 160)
	out["ok"] = r["ok"]
	out["error"] = AIStream.error_text(r["error"]) if r["error"] != "" else ""
	if r["first_ms"] > 0 and out["prompt_tokens"] > 0:
		out["prompt_tps"] = float(out["prompt_tokens"]) / (r["first_ms"] / 1000.0)
	var gen_ms: int = r["total_ms"] - maxi(0, r["first_ms"])
	if r["tokens"] > 1 and gen_ms > 0:
		out["gen_tps"] = float(r["tokens"] - 1) / (gen_ms / 1000.0)
	out["rss_mb"] = rss_mb()
	chat.stop_generation()
	return out


static func describe(m: Dictionary) -> String:
	if not m["ok"] and m["tokens"] == 0:
		return "%d hilos: FALLO (%s) tras %.1f s; texto de entrada %d tokens" % [m["threads"], m["error"], m["total_ms"] / 1000.0, m["prompt_tokens"]]
	return "%d hilos (%s): entrada %d tokens leídos en %.1f s (%.1f tokens/s) · %d tokens generados a %.1f tokens/s · total %.1f s%s · memoria %.0f MB%s" % [
		m["threads"], m["sampler"], m["prompt_tokens"], m["first_ms"] / 1000.0, m["prompt_tps"], m["tokens"], m["gen_tps"], m["total_ms"] / 1000.0, (" · FRASE DEL CLIENTE LISTA EN %.1f s" % (m["sentence_ms"] / 1000.0)) if m["sentence_ms"] >= 0 else "", m["rss_mb"], "" if m["ok"] else " · " + m["error"]]
