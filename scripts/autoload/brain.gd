extends Node
## IA LOCAL del juego (sin servidores ni claves). Gestiona:
##  - la descarga única de los modelos en el primer inicio (con progreso y reanudación),
##  - la carga del modelo de lenguaje (LLM) compartido por todas las llamadas,
##  - la voz a texto (Whisper), la detección de voz (Silero VAD) y la síntesis (Kokoro).
## Todo se ejecuta en el propio dispositivo mediante la extensión NobodyWho.
## Estados (llm_state / voice_state): missing | downloading | loading | ready | error | unsupported

signal state_changed
signal download_progress(done: int, total: int, label: String)

const DIR := "user://ia"
const MIRROR := "https://github.com/julianfarks/juego-de-scam/releases/download/modelos/"

## Paquetes de modelos. "size" permite comprobar la descarga y reanudarla.
const PACKS := {
	# Gemma 4 E2B: el mejor en las pruebas de conversación (coherente, en personaje,
	# recuerda precios y contradicciones). Pesa más de 2 GB, así que el espejo de
	# GitHub lo guarda en dos partes que se unen tras la descarga.
	"llm_normal": {"file": "gemma4-e2b-q4km.gguf", "size": 3106736256, "label": "Cerebro de los clientes (Gemma 4 E2B)",
		"parts": [1600000000, 1506736256],
		"hf": "https://huggingface.co/NobodyWho/Google_Gemma4-E2B-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"},
	# Para móviles con poca memoria. Responde peor (más corto y menos ingenioso).
	"llm_ligero": {"file": "qwen3.5-0.8b-q4km.gguf", "size": 532517344, "label": "Cerebro ligero (Qwen3.5 0.8B)",
		"hf": "https://huggingface.co/NobodyWho/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/Qwen_Qwen3.5-0.8B-Q4_K_M-vendor-sampling.gguf"},
	"stt": {"file": "whisper-base.zip", "size": 144862025, "label": "Oído (Whisper)", "dir": "whisper"},
	"vad": {"file": "silero-vad.zip", "size": 2243150, "label": "Detector de voz (Silero)", "dir": "vad"},
	"tts": {"file": "kokoro-es.zip", "size": 327138358, "label": "Voces (Kokoro)", "dir": "kokoro"},
}

var llm_state := "missing"
var voice_state := "missing"
var last_error := ""
var model: Object = null            # NobodyWhoModel
var stt: Object = null              # NobodyWhoSpeechToText
var vad_source := ""
var tts_engines: Dictionary = {}    # voz → NobodyWhoTextToSpeech
var llm_pack := "llm_normal"
var downloading := false
var _downloader: Downloader
var available := false              # ¿está la extensión NobodyWho en esta plataforma?
var gpu_used := false
var load_ms := 0
var turns_total := 0
var turn_ms_total := 0
var _dl_done := 0
var _dl_total := 0


func _ready() -> void:
	available = ClassDB.class_exists("NobodyWhoChat")
	DirAccess.make_dir_recursive_absolute(DIR)
	if not available:
		llm_state = "unsupported"
		voice_state = "unsupported"
		last_error = "La IA local no está disponible en esta plataforma."
		return
	llm_pack = choose_llm_pack()
	_refresh_presence()
	Settings.changed.connect(_on_setting)


## Cambiar el tamaño del cerebro en Ajustes se aplica al momento: se libera el
## modelo cargado y se carga el nuevo si ya está descargado (si no, hay que descargarlo).
func _on_setting(key: String) -> void:
	if key != "llm_size" or downloading:
		return
	var nuevo := choose_llm_pack()
	if nuevo == llm_pack:
		return
	llm_pack = nuevo
	model = null
	if llm_state in ["ready", "error"]:
		llm_state = "missing"
	_refresh_presence()
	if pack_present(llm_pack) and llm_state == "missing":
		load_llm()


## Elige el modelo según la memoria del dispositivo (se puede forzar en Ajustes).
func choose_llm_pack() -> String:
	var forced := str(Settings.get_value("llm_size"))
	if forced == "ligero":
		return "llm_ligero"
	if forced == "normal":
		return "llm_normal"
	var phys := total_ram_bytes()
	if phys > 0 and phys < int(5.0 * 1024 * 1024 * 1024):
		return "llm_ligero"
	return "llm_normal"


## Memoria total del dispositivo. En Android OS.get_memory_info() devuelve -1,
## así que se lee /proc/meminfo.
static func total_ram_bytes() -> int:
	var phys := int(OS.get_memory_info().get("physical", -1))
	if phys > 0:
		return phys
	var f := FileAccess.open("/proc/meminfo", FileAccess.READ)
	if f == null:
		return -1
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("MemTotal:"):
			return int(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) * 1024
	return -1


func pack_path(id: String) -> String:
	var p: Dictionary = PACKS[id]
	if p.has("dir"):
		return DIR.path_join(p["dir"])
	return DIR.path_join(p["file"])


func pack_present(id: String) -> bool:
	var p: Dictionary = PACKS[id]
	if p.has("dir"):
		return FileAccess.file_exists(DIR.path_join(p["dir"]).path_join(".ok"))
	var f := DIR.path_join(p["file"])
	return FileAccess.file_exists(f) and FileAccess.get_size(f) == int(p["size"])


func needed_packs() -> Array:
	return [llm_pack, "stt", "vad", "tts"]


func missing_packs() -> Array:
	return needed_packs().filter(func(id): return not pack_present(id))


func missing_bytes() -> int:
	var t := 0
	for id in missing_packs():
		t += int(PACKS[id]["size"])
	return t


func _refresh_presence() -> void:
	if llm_state in ["missing", "error"]:
		llm_state = "missing" if not pack_present(llm_pack) else llm_state
	if voice_state in ["missing", "error"]:
		voice_state = "missing" if not (pack_present("stt") and pack_present("vad") and pack_present("tts")) else voice_state
	state_changed.emit()


func is_ready() -> bool:
	return llm_state == "ready"


func status_text() -> String:
	match llm_state:
		"ready":
			return "IA local activa (%s)" % PACKS[llm_pack]["label"].get_slice("(", 1).trim_suffix(")")
		"loading":
			return "Cargando la IA local…"
		"downloading":
			return "Descargando la IA local…"
		"missing":
			if pack_present(llm_pack):
				return "IA local descargada, aún sin cargar"
			return "IA local sin descargar: diálogo básico"
		"unsupported":
			return "IA local no disponible: diálogo básico"
	return "IA local con error: diálogo básico"


# ------------------------------------------------------------------ Descarga

func download_all() -> bool:
	if downloading or not available:
		return false
	downloading = true
	llm_state = "downloading" if not pack_present(llm_pack) else llm_state
	if voice_state != "ready":
		voice_state = "downloading"
	state_changed.emit()
	var ok := true
	var total := missing_bytes()
	var done_before := 0
	for id in missing_packs():
		var p: Dictionary = PACKS[id]
		_downloader = Downloader.new()
		var base := done_before
		_downloader.progress.connect(func(d: int, _t: int) -> void:
			_dl_done = base + d
			_dl_total = total
			download_progress.emit(base + d, total, p["label"]))
		var dest := DIR.path_join(p["file"])
		var got := false
		if p.has("parts"):
			got = await _fetch_parts(p, dest, base, total)
		else:
			got = await _downloader.fetch(MIRROR + p["file"], dest, int(p["size"]))
		if not got and not _downloader.cancelled and p.has("hf"):
			# Plan B: el archivo entero desde Hugging Face.
			var first_error := _downloader.last_error
			_downloader = Downloader.new()
			_downloader.progress.connect(func(d: int, _t: int) -> void:
				_dl_done = base + d
				_dl_total = total
				download_progress.emit(base + d, total, p["label"]))
			got = await _downloader.fetch(p["hf"], dest, int(p["size"]))
			if got:
				_remove_parts(p, dest)
			elif _downloader.last_error == "":
				_downloader.last_error = first_error
		if not got:
			last_error = "%s: %s" % [p["label"], _downloader.last_error]
			ok = false
			break
		if p.has("dir"):
			download_progress.emit(base + int(p["size"]), total, "Descomprimiendo " + p["label"])
			await get_tree().process_frame
			var outdir := pack_path(id)
			if not Downloader.unzip(dest, outdir):
				last_error = "No se pudo descomprimir " + p["label"]
				ok = false
				break
			var mark := FileAccess.open(outdir.path_join(".ok"), FileAccess.WRITE)
			mark.store_string("ok")
			mark.close()
			DirAccess.remove_absolute(dest)
		done_before += int(p["size"])
	downloading = false
	_downloader = null
	if not ok:
		llm_state = "error" if not pack_present(llm_pack) else "missing"
		voice_state = "error" if voice_state == "downloading" else voice_state
	else:
		llm_state = "missing"
		voice_state = "missing"
	_refresh_presence()
	if ok:
		load_all()
	return ok


## Descarga un modelo troceado (.001, .002…) del espejo y lo vuelve a unir.
func _fetch_parts(p: Dictionary, dest: String, base: int, total: int) -> bool:
	var sizes: Array = p["parts"]
	var offset := 0
	for i in sizes.size():
		var part_dest := "%s.%03d" % [dest, i + 1]
		var d := Downloader.new()
		_downloader = d
		var off := offset
		d.progress.connect(func(x: int, _t: int) -> void:
			_dl_done = base + off + x
			_dl_total = total
			download_progress.emit(base + off + x, total, p["label"]))
		if not await d.fetch("%s%s.%03d" % [MIRROR, p["file"], i + 1], part_dest, int(sizes[i])):
			return false
		offset += int(sizes[i])
	download_progress.emit(base + offset, total, "Uniendo " + p["label"])
	await get_tree().process_frame
	# La primera parte se renombra (sin copiarla) y las demás se le añaden al final:
	# así el espacio extra necesario es solo el de una parte.
	if FileAccess.file_exists(dest + ".part"):
		DirAccess.remove_absolute(dest + ".part")
	DirAccess.rename_absolute("%s.001" % dest, dest + ".part")
	var out := FileAccess.open(dest + ".part", FileAccess.READ_WRITE)
	if out == null:
		_downloader.last_error = "No se pudo escribir en el almacenamiento"
		return false
	out.seek_end()
	for i in range(1, sizes.size()):
		var src_path := "%s.%03d" % [dest, i + 1]
		var src := FileAccess.open(src_path, FileAccess.READ)
		while src.get_position() < src.get_length():
			out.store_buffer(src.get_buffer(8 * 1024 * 1024))
			await get_tree().process_frame
		src.close()
		DirAccess.remove_absolute(src_path)
	out.close()
	if FileAccess.get_size(dest + ".part") != int(p["size"]):
		_downloader.last_error = "El archivo unido no tiene el tamaño esperado"
		DirAccess.remove_absolute(dest + ".part")
		return false
	DirAccess.rename_absolute(dest + ".part", dest)
	_remove_parts(p, dest)
	return true


func _remove_parts(p: Dictionary, dest: String) -> void:
	if not p.has("parts"):
		return
	for i in (p["parts"] as Array).size():
		for x in ["%s.%03d" % [dest, i + 1], "%s.%03d.part" % [dest, i + 1]]:
			if FileAccess.file_exists(x):
				DirAccess.remove_absolute(x)


## Carga en segundo plano todo lo que esté descargado.
func load_all() -> void:
	if not available:
		return
	if pack_present(llm_pack) and llm_state != "ready" and llm_state != "loading":
		await load_llm()
	if voice_state != "ready" and voice_state != "loading" and pack_present("stt") and pack_present("vad") and pack_present("tts"):
		await load_voice()


func cancel_download() -> void:
	if _downloader:
		_downloader.cancel()


func delete_models() -> void:
	unload()
	for id in PACKS.keys():
		var p: Dictionary = PACKS[id]
		if p.has("dir"):
			_remove_tree(pack_path(id))
		var f := DIR.path_join(p["file"])
		_remove_parts(p, f)
		for x in [f, f + ".part"]:
			if FileAccess.file_exists(x):
				DirAccess.remove_absolute(x)
	llm_state = "missing"
	voice_state = "missing"
	state_changed.emit()


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ------------------------------------------------------------------ Carga

## Carga el LLM. Si una carga con GPU dejó el juego colgado o cerrado la vez anterior,
## esta vez se usa solo la CPU (marca persistente "gpu_probe").
func load_llm() -> bool:
	if llm_state == "ready":
		return true
	if not available or not pack_present(llm_pack):
		return false
	llm_state = "loading"
	state_changed.emit()
	var want_gpu := bool(Settings.get_value("ai_gpu")) and not bool(Settings.get_value("gpu_probe"))
	if want_gpu:
		Settings.set_value("gpu_probe", true)
	var t0 := Time.get_ticks_msec()
	model = await ClassDB.class_call_static("NobodyWhoModel", "create", ProjectSettings.globalize_path(pack_path(llm_pack)), {"use_gpu": want_gpu})
	if model == null and want_gpu:
		want_gpu = false
		model = await ClassDB.class_call_static("NobodyWhoModel", "create", ProjectSettings.globalize_path(pack_path(llm_pack)), {"use_gpu": false})
	if want_gpu:
		Settings.set_value("gpu_probe", false)
	if model == null:
		llm_state = "error"
		last_error = "No se pudo cargar el modelo de lenguaje"
		state_changed.emit()
		return false
	gpu_used = want_gpu
	load_ms = Time.get_ticks_msec() - t0
	llm_state = "ready"
	state_changed.emit()
	return true


func load_voice() -> bool:
	if voice_state == "ready":
		return true
	if not available or not (pack_present("stt") and pack_present("vad") and pack_present("tts")):
		return false
	voice_state = "loading"
	state_changed.emit()
	stt = await ClassDB.class_call_static("NobodyWhoSpeechToText", "create", ProjectSettings.globalize_path(pack_path("stt")), {"language": "es", "quantization": "q4"})
	vad_source = ProjectSettings.globalize_path(pack_path("vad"))
	var tts_ok: Object = await get_tts("ef_dora")
	if stt == null or tts_ok == null:
		voice_state = "error"
		last_error = "No se pudieron cargar los modelos de voz"
		state_changed.emit()
		return false
	voice_state = "ready"
	state_changed.emit()
	return true


## Un motor de síntesis por voz de Kokoro (se crean bajo demanda y se reutilizan).
func get_tts(voice: String) -> Object:
	if tts_engines.has(voice):
		return tts_engines[voice]
	var e: Object = await ClassDB.class_call_static("NobodyWhoTextToSpeech", "create", ProjectSettings.globalize_path(pack_path("tts")), {"architecture": "kokoro", "voice": voice, "language": "es", "device": "cpu"})
	if e != null:
		tts_engines[voice] = e
	return e


func new_vad() -> Object:
	if vad_source == "":
		return null
	return await ClassDB.class_call_static("NobodyWhoVoiceActivityDetection", "create", vad_source, {"sample_rate": 16000, "threshold": 0.5, "min_silence_duration_ms": 700, "preroll_duration_ms": 400})


## Nueva conversación con el modelo compartido.
func new_chat(system_prompt: String, schema: Dictionary, temperature := 0.8) -> Object:
	if llm_state != "ready":
		return null
	var sampler = ClassDB.instantiate("NobodyWhoSamplerBuilder").json_schema(JSON.stringify(schema)).dry(0.8, 1.75, 2, 256, PackedStringArray(["\n", ":", "\"", "*"])).temperature(temperature).top_p(0.92, 1).dist()
	return await ClassDB.class_call_static("NobodyWhoChat", "create", model, {
		"system_prompt": system_prompt, "n_ctx": 4096, "sampler": sampler,
		"template_variables": {"enable_thinking": false},
		"context_shift": {"keep_first_turns": 1, "keep_last_turns": 4, "target": 0.6},
	})


func download_percent() -> float:
	return 100.0 * float(_dl_done) / maxf(1.0, float(_dl_total))


func record_turn(ms: int) -> void:
	turns_total += 1
	turn_ms_total += ms


func avg_turn_seconds() -> float:
	return float(turn_ms_total) / 1000.0 / maxf(1.0, float(turns_total))


## Comentario de fin de jornada del jefe, generado por el modelo local.
func boss_comment(stats: Dictionary) -> String:
	var sys := "Eres Don Ramiro Billetes, el jefe exagerado, sarcástico y cómico de TeleTimo, un call center ficticio de un videojuego de humor. Evalúas la jornada de un empleado en 2 a 4 frases en español, con humor de oficina, usando SOLO los datos que te dan (menciona sus cifras). Sin insultos graves."
	var chat: Object = await new_chat(sys, {"type": "object", "properties": {"comentario": {"type": "string", "minLength": 20, "maxLength": 420}}, "required": ["comentario"], "additionalProperties": false}, 0.9)
	if chat == null:
		return ""
	var data := "Día %d. Ingresos ficticios: %d de una cuota de %d (%s). Nota: %s. Llamadas: %d, ventas: %d, le colgaron %d veces, contradicciones pilladas: %d, mejor venta: %d, incidentes: %d, llamadas perdidas: %d." % [
		stats["day"], stats["income"], stats["quota"], "cuota cumplida" if stats["passed"] else "NO llegó a la cuota", stats["grade"],
		stats["calls"], stats["successes"], stats["hangups"], stats["contradictions"], stats["best_sale"], stats["incidents"], stats["missed"]]
	var t0 := Time.get_ticks_msec()
	var out: String = await chat.ask(data).completed()
	record_turn(Time.get_ticks_msec() - t0)
	var j = JSON.parse_string(out)
	if j is Dictionary:
		return AIResponse.sanitize_text(str(j.get("comentario", "")), 420)
	return ""


func unload() -> void:
	model = null
	stt = null
	tts_engines.clear()
	if llm_state == "ready":
		llm_state = "missing"
	if voice_state == "ready":
		voice_state = "missing"
	_refresh_presence()
