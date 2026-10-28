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
var tts_ok := false                 # ¿se cargó Kokoro?
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
	AILog.add("inicio", "%s %s · %d núcleos · RAM %.1f GB · cerebro %s · GPU %s" % [OS.get_name(), OS.get_model_name(), OS.get_processor_count(), total_ram_bytes() / 1073741824.0, llm_pack, "activada" if Settings.get_value("ai_gpu") else "desactivada"])
	for r in verify_packs():
		AILog.add("archivos", "%s: %s" % [r["label"], r["detail"]])


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


## Archivos que debe contener cada paquete comprimido (para comprobar que la
## descompresión fue completa sin volver a descargar nada).
const PACK_FILES := {
	"stt": ["config.json", "tokenizer.json", "onnx/encoder_model_q4.onnx", "onnx/decoder_model_merged_q4.onnx"],
	"vad": ["onnx/model.onnx"],
	"tts": ["model.onnx", "config.json", "voices/ef_dora.safetensors", "voices/em_alex.safetensors"],
}


## Comprueba los modelos YA descargados sin borrarlos ni volver a descargarlos:
## tamaño exacto, cabecera GGUF del modelo de lenguaje y archivos de cada paquete.
func verify_packs() -> Array:
	var out := []
	for id in needed_packs():
		var p: Dictionary = PACKS[id]
		var r := {"id": id, "label": p["label"], "ok": false, "detail": ""}
		if p.has("dir"):
			var d := DIR.path_join(p["dir"])
			if not FileAccess.file_exists(d.path_join(".ok")):
				r["detail"] = "sin descargar"
			else:
				var missing := []
				for rel in PACK_FILES.get(id, []):
					var full := d.path_join(rel)
					if not FileAccess.file_exists(full):
						missing.append(rel)
				r["ok"] = missing.is_empty()
				r["detail"] = "completo" if r["ok"] else "faltan: " + ", ".join(PackedStringArray(missing))
		else:
			var f := DIR.path_join(p["file"])
			if not FileAccess.file_exists(f):
				r["detail"] = "sin descargar" + (" (descarga a medias)" if FileAccess.file_exists(f + ".part") or FileAccess.file_exists(f + ".001") else "")
			else:
				var size := FileAccess.get_size(f)
				var fh := FileAccess.open(f, FileAccess.READ)
				var magic := fh.get_buffer(4).get_string_from_ascii() if fh else ""
				var version := fh.get_32() if fh else 0
				if fh:
					fh.close()
				r["ok"] = size == int(p["size"]) and magic == "GGUF"
				r["detail"] = "%.2f GB, cabecera %s v%d%s" % [size / 1e9, magic if magic != "" else "?", version, "" if size == int(p["size"]) else " — TAMAÑO INCORRECTO (esperado %d)" % int(p["size"])]
		out.append(r)
	return out


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
	# Espacio: lo que falta + margen (al unir las partes hace falta una parte más).
	var need := total + 1700000000 if missing_packs().any(func(id): return PACKS[id].has("parts")) else total + 200000000
	var dir := DirAccess.open(DIR)
	var free_space: int = dir.get_space_left() if dir else -1
	if free_space > 0 and free_space < need:
		last_error = "No hay espacio suficiente: hacen falta %.1f GB libres y hay %.1f GB." % [need / 1e9, free_space / 1e9]
		downloading = false
		llm_state = "error" if not pack_present(llm_pack) else llm_state
		voice_state = "error" if voice_state == "downloading" else voice_state
		state_changed.emit()
		return false
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

## Carga el LLM y lo PRUEBA (respuesta corta con tiempo límite) antes de darlo por
## listo. Si la GPU está activada y no responde, se recarga en el procesador y se
## desactiva la GPU para la próxima vez. Todo queda en el registro de diagnóstico.
func load_llm() -> bool:
	if llm_state == "ready":
		return true
	if not available or not pack_present(llm_pack):
		return false
	llm_state = "loading"
	last_error = ""
	state_changed.emit()
	var want_gpu := bool(Settings.get_value("ai_gpu")) and not bool(Settings.get_value("gpu_probe"))
	var ok := await _load_and_test(want_gpu)
	if not ok and want_gpu:
		AILog.add("carga", "La prueba con GPU falló: se reintenta solo con el procesador y se desactiva la GPU.")
		Settings.set_value("ai_gpu", false)
		ok = await _load_and_test(false)
	if not ok:
		model = null
		llm_state = "error"
		state_changed.emit()
		return false
	llm_state = "ready"
	state_changed.emit()
	return true


func _load_and_test(use_gpu: bool) -> bool:
	model = null
	if use_gpu:
		Settings.set_value("gpu_probe", true)  # si el juego se cierra cargando, la próxima vez sin GPU
	var path := ProjectSettings.globalize_path(pack_path(llm_pack))
	AILog.add("carga", "Cargando %s (%s)…" % [PACKS[llm_pack]["label"], "GPU" if use_gpu else "procesador"])
	var t0 := Time.get_ticks_msec()
	var r := await Timed.run(func(): return await ClassDB.class_call_static("NobodyWhoModel", "create", path, {"use_gpu": use_gpu}), 600000)
	if use_gpu:
		Settings.set_value("gpu_probe", false)
	if not r["ok"] or r["value"] == null:
		last_error = "No se pudo cargar el modelo de lenguaje" + (" (tiempo agotado)" if r["timeout"] else "")
		AILog.add("error", last_error)
		return false
	model = r["value"]
	gpu_used = use_gpu
	load_ms = Time.get_ticks_msec() - t0
	AILog.add("carga", "Modelo cargado en %.1f s" % (load_ms / 1000.0))
	# Prueba real: ¿devuelve tokens? (antes esto no se comprobaba y una GPU bloqueada
	# dejaba al cliente «pensando» para siempre)
	llm_state = "ready"
	var test := await self_test(45000)
	llm_state = "loading"
	if not test["ok"]:
		last_error = "El modelo se cargó pero no responde: %s" % test["error_text"]
		AILog.add("error", last_error)
		model = null
		return false
	return true


## Prueba rápida del modelo: una respuesta corta con tiempo límite.
## Devuelve {ok, error, error_text, first_ms, total_ms, tokens, tok_per_s, text}.
func self_test(first_limit_ms := 45000) -> Dictionary:
	var out := {"ok": false, "error": "", "error_text": "", "first_ms": -1, "total_ms": 0, "tokens": 0, "tok_per_s": 0.0, "text": ""}
	if model == null:
		out["error"] = "sin_modelo"
		out["error_text"] = "El modelo no está cargado"
		return out
	var chat: Object = await new_chat("Eres un cliente que contesta al teléfono. Responde en español, muy breve.", {"type": "object", "properties": {"respuesta": {"type": "string", "maxLength": 80}}, "required": ["respuesta"], "additionalProperties": false}, 0.7)
	if chat == null:
		out["error"] = "sin_chat"
		out["error_text"] = "No se pudo crear la conversación"
		AILog.add("prueba", out["error_text"])
		return out
	var r := await AIStream.read(chat, chat.ask("Saluda en una frase corta."), Callable(), {}, {"first": first_limit_ms, "stall": 20000, "total": first_limit_ms + 30000})
	out["first_ms"] = r["first_ms"]
	out["total_ms"] = r["total_ms"]
	out["tokens"] = r["tokens"]
	out["text"] = r["text"]
	var gen_ms := maxi(1, r["total_ms"] - maxi(0, r["first_ms"]))
	out["tok_per_s"] = float(maxi(0, r["tokens"] - 1)) / (gen_ms / 1000.0)
	var j = JSON.parse_string(r["text"]) if r["ok"] else null
	out["ok"] = r["ok"] and j is Dictionary and str(j.get("respuesta", "")) != ""
	out["error"] = r["error"] if r["error"] != "" else ("" if out["ok"] else "json")
	out["error_text"] = AIStream.error_text(out["error"]) if out["error"] != "json" else "La respuesta no tenía el formato esperado"
	AILog.add("prueba", "%s · primer token %s · %d tokens en %.1f s (%.1f tokens/s)%s" % [
		"OK" if out["ok"] else "FALLO", ("%.1f s" % (r["first_ms"] / 1000.0)) if r["first_ms"] >= 0 else "nunca",
		r["tokens"], r["total_ms"] / 1000.0, out["tok_per_s"], "" if out["ok"] else " · " + out["error_text"]])
	return out


func load_voice() -> bool:
	if voice_state == "ready":
		return true
	if not available or not (pack_present("stt") and pack_present("vad") and pack_present("tts")):
		return false
	voice_state = "loading"
	state_changed.emit()
	# Kokoro extrae los datos fonéticos de eSpeak a una carpeta que NobodyWho toma
	# de NOBODYWHO_ESPEAK_DATA_DIR (su puente de Kotlin la fija en Android, el de
	# Godot no). Sin ella usa la carpeta temporal del sistema, que en Android no se
	# puede escribir ("Could not create espeak data dir"). Se usa el almacenamiento del juego.
	var espeak_dir := ProjectSettings.globalize_path(DIR.path_join("espeak-ng-data"))
	DirAccess.make_dir_recursive_absolute(espeak_dir)
	if OS.get_environment("NOBODYWHO_ESPEAK_DATA_DIR") == "":
		OS.set_environment("NOBODYWHO_ESPEAK_DATA_DIR", espeak_dir)
	if OS.has_feature("android"):
		var tmp := ProjectSettings.globalize_path("user://tmp")
		DirAccess.make_dir_recursive_absolute(tmp)
		OS.set_environment("TMPDIR", tmp)
	var t0 := Time.get_ticks_msec()
	var stt_path := ProjectSettings.globalize_path(pack_path("stt"))
	var rs := await Timed.run(func(): return await ClassDB.class_call_static("NobodyWhoSpeechToText", "create", stt_path, {"language": "es", "quantization": "q4"}), 90000)
	stt = rs["value"] if rs["ok"] else null
	AILog.add("voz", "Whisper %s en %.1f s" % ["cargado" if stt != null else ("NO cargado (tiempo agotado)" if rs["timeout"] else "NO cargado"), (Time.get_ticks_msec() - t0) / 1000.0])
	vad_source = ProjectSettings.globalize_path(pack_path("vad"))
	t0 = Time.get_ticks_msec()
	var tts_engine: Object = await get_tts("ef_dora")
	tts_ok = tts_engine != null
	AILog.add("voz", "Kokoro %s en %.1f s" % ["cargado" if tts_ok else "NO cargado", (Time.get_ticks_msec() - t0) / 1000.0])
	if stt == null and not tts_ok:
		voice_state = "error"
		last_error = "No se pudieron cargar los modelos de voz"
		state_changed.emit()
		return false
	# Oído y voz son independientes: si falla uno, el otro sigue funcionando.
	if stt == null:
		last_error = "No se pudo cargar el reconocimiento de voz (Whisper)"
	elif not tts_ok:
		last_error = "No se pudieron cargar las voces neuronales (Kokoro)"
	voice_state = "ready"
	state_changed.emit()
	return true


## Un motor de síntesis por voz de Kokoro (se crean bajo demanda y se reutilizan).
func get_tts(voice: String) -> Object:
	if tts_engines.has(voice):
		return tts_engines[voice]
	var path := ProjectSettings.globalize_path(pack_path("tts"))
	var r := await Timed.run(func(): return await ClassDB.class_call_static("NobodyWhoTextToSpeech", "create", path, {"architecture": "kokoro", "voice": voice, "language": "es", "device": "cpu"}), 90000)
	var e: Object = r["value"] if r["ok"] else null
	if e != null:
		tts_engines[voice] = e
	return e


func new_vad() -> Object:
	if vad_source == "":
		return null
	return await ClassDB.class_call_static("NobodyWhoVoiceActivityDetection", "create", vad_source, {"sample_rate": 16000, "threshold": 0.5, "min_silence_duration_ms": 700, "preroll_duration_ms": 400})


## Nueva conversación con el modelo compartido.
func new_chat(system_prompt: String, schema: Dictionary, temperature := 0.8) -> Object:
	if llm_state != "ready" or model == null:
		return null
	var sampler = ClassDB.instantiate("NobodyWhoSamplerBuilder").json_schema(JSON.stringify(schema)).dry(0.8, 1.75, 2, 256, PackedStringArray(["\n", ":", "\"", "*"])).temperature(temperature).top_p(0.92, 1).dist()
	var m := model
	var r := await Timed.run(func(): return await ClassDB.class_call_static("NobodyWhoChat", "create", m, {
		"system_prompt": system_prompt, "n_ctx": 4096, "sampler": sampler,
		"template_variables": {"enable_thinking": false},
		"context_shift": {"keep_first_turns": 1, "keep_last_turns": 6, "target": 0.6},
	}), 30000)
	if not r["ok"] or r["value"] == null:
		AILog.add("error", "No se pudo crear la conversación%s" % (" (tiempo agotado)" if r["timeout"] else ""))
		return null
	return r["value"]


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
	var r := await AIStream.read(chat, chat.ask(data))
	if not r["ok"]:
		AILog.add("jefe", "Comentario del jefe sin IA: %s" % AIStream.error_text(r["error"]))
		return ""
	record_turn(r["total_ms"])
	var j = JSON.parse_string(r["text"])
	if j is Dictionary:
		return AIResponse.sanitize_text(str(j.get("comentario", "")), 420)
	return ""


func unload() -> void:
	model = null
	stt = null
	tts_engines.clear()
	tts_ok = false
	if llm_state == "ready":
		llm_state = "missing"
	if voice_state == "ready":
		voice_state = "missing"
	_refresh_presence()
