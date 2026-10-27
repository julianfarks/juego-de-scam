extends SceneTree
## Evaluación del LLM local con una conversación larga y exigente: presentación,
## preguntas del cliente, broma, pregunta personal inesperada, cambio de tema,
## contradicción de precio, promesa, petición de pago (decisión del juego).
## godot --headless --path . -s tests/eval/llm_eval.gd -- --model=ruta.gguf --client=chucho [--gpu]

const SCRIPT := [
	["", "Hola, buenas tardes, le llamo de TeleTimo, ¿qué tal está?"],
	["OFERTA", "Le llamo para ofrecerle una garantía extendida para su tostadora."],
	["", "Cubre todo: si se rompe, si se pone triste o si quema el pan."],
	["", "Cuesta 29 pesos al mes, y el primer mes es gratis."],
	["", "Oiga, ¿y usted a qué se dedica?"],
	["", "Jajaja, qué bueno. ¿Y qué tal el tiempo por allá?"],
	["", "Volviendo a lo nuestro: luego le explico cómo funciona la devolución."],
	["", "Bueno, en realidad son 49 pesos al mes."],
	["", "¿Qué fue lo primero que le dije que costaba?"],
	["PAGO_NO", "¿Me facilita los datos de pago?"],
	["", "Le entiendo. Le doy garantía por escrito y si no le gusta le devolvemos el dinero."],
	["PAGO_SI", "¿Entonces me dice los datos para completar el pedido?"],
]


func _initialize() -> void:
	var model_path := ""
	var client := "pilar"
	var offer := "garantia_tostadora"
	var gpu := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.substr(8)
		if a.begins_with("--client="): client = a.substr(9)
		if a.begins_with("--offer="): offer = a.substr(8)
		if a == "--gpu": gpu = true
	var t0 := Time.get_ticks_msec()
	var model = await NobodyWhoModel.create(model_path, {"use_gpu": gpu})
	if model == null:
		print("ERROR: no se pudo cargar ", model_path)
		quit(1)
		return
	print("Modelo %s cargado en %d ms" % [model_path.get_file(), Time.get_ticks_msec() - t0])
	var sampler = NobodyWhoSamplerBuilder.new().json_schema(JSON.stringify(Persona.schema())).dry(0.8, 1.75, 2, 256, PackedStringArray(["\n", ":", "\"", "*"])).temperature(0.8).top_p(0.92, 1).dist()
	var sys := Persona.system_prompt(client, Persona.SITUATIONS[3])
	var chat = await NobodyWhoChat.create(model, {"system_prompt": sys, "n_ctx": 4096, "sampler": sampler, "template_variables": {"enable_thinking": false}})
	var c := ClientDB.get_c(client)
	print("CLIENTE: %s (%s) · tokens del prompt de sistema: %d" % [c["name"], c["personality"], (await chat.tokenize(sys)).size()])
	var total_ms := 0
	var turns := 0
	var bad := 0
	var said := []
	var msgs := [["", "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]"]] + SCRIPT
	for pair in msgs:
		var tag: String = pair[0]
		var line: String = pair[1]
		var notes := []
		if tag == "OFERTA":
			notes.append(Persona.offer_note(offer))
		if tag == "PAGO_NO":
			notes += ["el vendedor te pide los datos de pago", "DECISIÓN DEL JUEGO: NO aceptas pagar todavía. Dilo a tu manera"]
		if tag == "PAGO_SI":
			notes += ["el vendedor te pide los datos de pago", "DECISIÓN DEL JUEGO: aceptas pagar. Dilo a tu manera; no digas ningún número"]
		if line.contains("49"):
			notes.append("el vendedor dijo antes que costaba 29 y ahora dice 49")
		var msg := line if line.begins_with("[") else Persona.turn_message(line, notes)
		t0 = Time.get_ticks_msec()
		var out: String = await chat.ask(msg).completed()
		var ms := Time.get_ticks_msec() - t0
		total_ms += ms
		turns += 1
		var j = JSON.parse_string(out)
		print("\n> ", line, ("   " + str(notes)) if not notes.is_empty() else "")
		if j is Dictionary:
			var r := str(j.get("respuesta", ""))
			if said.has(r):
				bad += 1
			said.append(r)
			print("< %s\n   [emoción %s · efecto %s · interés %d · duda «%s» · cuelga %s] (%.1f s, %d tokens)" % [r, j.get("emocion"), j.get("efecto"), int(j.get("interes", -1)), j.get("duda"), j.get("cuelga"), ms / 1000.0, (await chat.tokenize(out)).size()])
		else:
			bad += 1
			print("< JSON INVALIDO: ", out, "  (%d ms)" % ms)
	var st = await chat.get_stats()
	print("\nRESUMEN modelo=%s cliente=%s turnos=%d media=%.1f s fallos=%d contexto=%s" % [model_path.get_file(), client, turns, total_ms / 1000.0 / turns, bad, str(st)])
	quit()
