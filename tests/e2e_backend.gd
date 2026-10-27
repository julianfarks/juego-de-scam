extends Node
## Prueba de integración juego ↔ servidor (con el backend en modo mock):
##   (cd backend && npm run mock) &
##   godot --headless --path . tests/e2e_runner.tscn -- --backend=http://127.0.0.1:8787 --code=XXXX

var passed := 0
var failed := 0


func check(c: bool, msg: String) -> void:
	if c:
		passed += 1
		print("  ✓ ", msg)
	else:
		failed += 1
		print("  ✗ ", msg)


func _ready() -> void:
	await get_tree().process_frame
	var url := "http://127.0.0.1:8787"
	var code := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--backend="):
			url = a.substr(10)
		if a.begins_with("--code="):
			code = a.substr(7)
	Settings.set_value("backend_url", url, false)
	Settings.set_value("access_code", code, false)
	var h: Dictionary = await AI.health()
	check(h.get("ok", false), "health responde")
	check(h.get("session", false), "sesión obtenida con el código de acceso")
	# Turnos de conversación por la IA remota
	var s := CallSession.new()
	add_child(s)
	var replies := []
	var result := {}
	s.client_spoke.connect(func(t, _e, _g, src): replies.append([t, src]))
	s.ended.connect(func(r): result.merge(r))
	s.start("pilar", "seguro_abduccion", 1, {}, {}, 5)
	s.player_says("Hola, le llamo de TeleTimo")
	while s.busy:
		await get_tree().process_frame
	s.player_says("Le doy garantía de devolución")
	while s.busy:
		await get_tree().process_frame
	check(s.remote_turns == 2, "dos respuestas generadas por el servidor (%d)" % s.remote_turns)
	check(replies.size() >= 3 and replies[-1][1] == "remote", "el cliente habla con la respuesta remota")
	check(str(replies[-1][0]).contains("garant"), "la respuesta remota recibió el contexto del jugador")
	var money_before: int = Game.ledger.get("income", 0)
	s.player_hangs_up()
	check(not result.is_empty() and int(result["amount"]) == 0, "sin cierre por reglas no hay dinero aunque la IA hable")
	# Transcripción con un WAV generado
	var pcm := PackedByteArray()
	pcm.resize(16000 * 2)
	for i in 16000:
		pcm.encode_s16(i * 2, int(sin(i * 0.07) * 9000))
	var t: Dictionary = await AI.transcribe(WavUtil.wrap_wav(pcm, 16000), "es")
	check(t.get("ok", false) and str(t.get("text", "")).length() > 3, "transcripción recibida: %s" % t.get("text", t.get("error", "")))
	var b: Dictionary = await AI.boss_comment({"income": 120, "quota": 110, "grade": "B", "day": 1})
	check(b.get("ok", false), "comentario del jefe remoto")
	var tts: Dictionary = await AI.synthesize("Hola", "coral", "")
	check(not tts.get("ok", true), "TTS desactivado en el servidor → el juego lo detecta y usará la voz del sistema")
	# Servidor caído → modo local sin bloquear
	Settings.set_value("backend_url", "http://127.0.0.1:9", false)
	AI.token = ""
	AI._offline_until = 0.0
	var s2 := CallSession.new()
	add_child(s2)
	var src2 := []
	s2.client_spoke.connect(func(_t, _e, _g, src): src2.append(src))
	s2.start("brayan", "seguro_abduccion", 1, {}, {}, 6)
	s2.player_says("Hola, buenas")
	while s2.busy:
		await get_tree().process_frame
	check(src2.size() >= 2 and src2[-1] == "local", "sin conexión responde el diálogo local")
	check(not AI.remote_available(), "tras el fallo espera antes de reintentar el servidor")
	print("\n==== E2E: %d OK, %d FALLOS ====" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
