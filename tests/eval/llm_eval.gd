extends SceneTree
## Evaluación de calidad del LLM local con conversaciones de prueba.
## godot --headless --path . -s tests/eval/llm_eval.gd -- --model=ruta.gguf --client=chucho

func _initialize() -> void:
	var model_path := ""
	var client := "pilar"
	var offer := "garantia_tostadora"
	var lines := ["Hola, buenas tardes, le llamo de TeleTimo.", "Le quiero ofrecer una garantía extendida para su tostadora.", "Cubre todo: si se rompe, si se pone triste o si quema el pan.", "Cuesta solo 29 pesos al mes.", "¿Y usted cómo se llama?", "Jaja, por cierto, ¿qué tal el día?", "Volviendo a lo nuestro, ¿le interesa?", "Bueno, en realidad son 49 pesos."]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.substr(8)
		if a.begins_with("--client="): client = a.substr(9)
		if a.begins_with("--offer="): offer = a.substr(8)
	var t0 := Time.get_ticks_msec()
	var model = await ClassDB.class_call_static("NobodyWhoModel", "create", model_path, {"use_gpu": false})
	print("Modelo cargado en %d ms" % (Time.get_ticks_msec() - t0))
	var sampler = NobodyWhoSamplerBuilder.new().json_schema(JSON.stringify(Persona.schema())).dry(0.8, 1.75, 2, 256, PackedStringArray(["\n", ":", "\"", "*"])).temperature(0.8).top_p(0.92, 1).dist()
	var sys := Persona.system_prompt(client, offer, Persona.SITUATIONS[0])
	var chat = await ClassDB.class_call_static("NobodyWhoChat", "create", model, {"system_prompt": sys, "n_ctx": 4096, "sampler": sampler, "template_variables": {"enable_thinking": false}, "n_threads": 2})
	print("CLIENTE: ", ClientDB.get_c(client)["name"], " (", ClientDB.get_c(client)["personality"], ")")
	var first := true
	for l in ["[La llamada empieza: descuelgas el teléfono.]"] + lines:
		t0 = Time.get_ticks_msec()
		var out: String = await chat.ask(l).completed()
		var ms := Time.get_ticks_msec() - t0
		var j = JSON.parse_string(out)
		print("\n> ", l)
		if j is Dictionary:
			print("< [%s|%s|%d|%s] %s   (%d ms)" % [j.get("emocion"), j.get("efecto"), int(j.get("interes", -1)), j.get("duda"), j.get("dice"), ms])
		else:
			print("< JSON INVALIDO: ", out, "  (%d ms)" % ms)
	var st = await chat.get_stats()
	print("\nSTATS ", st)
	quit()
