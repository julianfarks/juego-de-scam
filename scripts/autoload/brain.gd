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
	"llm_normal": {"file": "qwen3.5-2b-q4km.gguf", "size": 1280836064, "label": "Cerebro de los clientes (Qwen3.5 2B)",
		"hf": "https://huggingface.co/NobodyWho/Qwen_Qwen3.5-2B-GGUF/resolve/main/Qwen_Qwen3.5-2B-Q4_K_M-vendor-sampling.gguf"},
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


## Elige el modelo según la memoria del dispositivo (se puede forzar en Ajustes).
func choose_llm_pack() -> String:
	var forced := str(Settings.get_value("llm_size"))
	if forced == "ligero":
		return "llm_ligero"
	if forced == "normal":
		return "llm_normal"
	var mem: Dictionary = OS.get_memory_info()
	var phys := int(mem.get("physical", 0))
	if phys > 0 and phys < int(5.5 * 1024 * 1024 * 1024):
		return "llm_ligero"
	return "llm_normal"


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
			return "IA local activa (%s%s)" % [PACKS[llm_pack]["label"].get_slice("(", 1).trim_suffix(")"), ", GPU" if gpu_used else ""]
		"loading":
			return "Cargando la IA local…"
		"downloading":
			return "Descargando la IA local…"
		"missing":
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
		_downloader.progress.connect(func(d: int, _t: int) -> void: download_progress.emit(base + d, total, p["label"]))
		var dest := DIR.path_join(p["file"])
		var got: bool = await _downloader.fetch(MIRROR + p["file"], dest, int(p["size"]))
		if not got and not _downloader.cancelled and p.has("hf"):
			got = await _downloader.fetch(p["hf"], dest, int(p["size"]))
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
	return ok


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
	var sampler = ClassDB.instantiate("NobodyWhoSamplerBuilder").json_schema(schema).dry(0.8, 1.75, 2, 256, ["\n", ":", "\"", "*"]).temperature(temperature).top_p(0.92, 1).dist()
	var threads := clampi(OS.get_processor_count() - 2, 2, 6)
	return await ClassDB.class_call_static("NobodyWhoChat", "create", model, {
		"system_prompt": system_prompt, "n_ctx": 4096, "sampler": sampler,
		"template_variables": {"enable_thinking": false}, "n_threads": threads,
		"context_shift": {"keep_first_turns": 1, "keep_last_turns": 4, "target": 0.6},
	})


func unload() -> void:
	model = null
	stt = null
	tts_engines.clear()
	if llm_state == "ready":
		llm_state = "missing"
	if voice_state == "ready":
		voice_state = "missing"
	_refresh_presence()
