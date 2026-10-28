extends Node
## Prueba INDEPENDIENTE de Gemma (sin 3D, voz ni llamada) con el archivo de modelo real:
##   godot --headless --path . tests/eval/gemma_bench.tscn -- --model=ruta.gguf --threads=1,2,4
## Mide carga, memoria, tokens de entrada, primer token y velocidad para cada número
## de hilos, con texto libre y con el muestreador del juego (JSON).

func _ready() -> void:
	var model_path := ""
	var threads := [1, 2, 4]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.substr(8)
		if a.begins_with("--threads="): threads = Array(a.substr(10).split(",")).map(func(x): return int(x))
	await get_tree().process_frame
	var topo := GemmaBench.cpu_topology()
	print("BENCH sistema: %s · %d núcleos · frecuencias máx. %s MHz · grandes %d · recomendados %d hilos · memoria disponible %.0f MB · RSS antes %.0f MB" % [
		OS.get_name(), topo["total"], str(topo["freqs_mhz"]), topo["big"], GemmaBench.recommended_threads(), GemmaBench.mem_available_mb(), GemmaBench.rss_mb()])
	var t0 := Time.get_ticks_msec()
	var model = await NobodyWhoModel.create(model_path, {"use_gpu": false})
	if model == null:
		print("BENCH ERROR: no se pudo cargar ", model_path)
		get_tree().quit(1)
		return
	print("BENCH carga: %.1f s · RSS después %.0f MB · memoria disponible %.0f MB" % [(Time.get_ticks_msec() - t0) / 1000.0, GemmaBench.rss_mb(), GemmaBench.mem_available_mb()])
	var real_prompt := Persona.system_prompt("tomasito", Persona.SITUATIONS[0], 100)
	var greet := "[Suena el teléfono y descuelgas. Saluda a tu manera; aún no sabes quién llama.]"
	print("BENCH instrucciones del cliente: %d caracteres" % real_prompt.length())
	for n in threads:
		var a := await GemmaBench.measure(model, n, GemmaBench.PROMPT_SHORT)
		print("BENCH corta  · ", GemmaBench.describe(a))
		var b := await GemmaBench.measure(model, n, real_prompt, greet, {}, true)
		print("BENCH saludo · ", GemmaBench.describe(b), " · «", b["text"].substr(0, 90), "»")
	get_tree().quit()
